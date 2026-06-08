"""Bridge entre le sim Python v1.9.1 et le viewer Godot 3D.

Lance Godot en sous-processus en mode CLIENT (--client) et stream l'état
physique du sim via UDP localhost:7777. Le viewer Godot affiche la vue
3D FPV depuis le cockpit du conducteur, synchronisée avec le sim Python.

Mode standalone (multiplateforme) :
    Le viewer 3D est livré sous forme d'un binaire EXPORTÉ (engine +
    projet embarqués) dans bundled_godot/ à côté du sim Python :
      - Linux x86_64 : bundled_godot/perce_neige_3d.x86_64
      - Windows      : bundled_godot/perce_neige_3d.exe
      - macOS        : bundled_godot/perce_neige_3d.app/Contents/MacOS/perce_neige_3d
    PyInstaller bundle ce dossier dans la distrib finale → l'utilisateur
    n'a RIEN à installer (ni Godot, ni le projet 3D).

Mode dev (fallback) :
    Si le binaire bundled n'existe pas mais qu'un Godot system + projet
    source est dispo, on utilise ceux-là pour permettre le développement.

Usage :
    bridge = GodotBridge(bundled_dir="/path/to/perce-neige-sim/bundled_godot")
    bridge.start()
    bridge.send_state({...})
    bridge.stop()
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Optional


class GodotBridge:
    DEFAULT_PORT = 7777

    def __init__(
        self,
        bundled_dir: str | Path | None = None,
        dev_project_dir: str | Path | None = None,
        port: int = DEFAULT_PORT,
    ) -> None:
        # bundled_dir : où chercher le binaire exporté standalone
        # dev_project_dir : projet source Godot pour fallback dev
        self.bundled_dir = Path(bundled_dir).expanduser().resolve() if bundled_dir else None
        self.dev_project_dir = Path(dev_project_dir).expanduser().resolve() if dev_project_dir else None
        self.port = port
        self._proc: Optional[subprocess.Popen] = None
        self._sock: Optional[socket.socket] = None
        self._addr = ("127.0.0.1", port)
        # Résolution du binaire à utiliser (cache)
        self._resolved_cmd: Optional[list] = None
        # Fichier de log : capture stderr du viewer + diagnostic de lancement,
        # car le sim PyInstaller tourne sans console (console=False) → c'est le
        # seul moyen de savoir POURQUOI la vue 3D n'a pas démarré.
        import tempfile
        self._logfile = Path(tempfile.gettempdir()) / "perce_neige_3d.log"

    def _bundled_binary_path(self) -> Optional[Path]:
        """Retourne le chemin du binaire exporté standalone selon la plateforme,
        ou None s'il n'existe pas dans bundled_dir.
        """
        if self.bundled_dir is None or not self.bundled_dir.is_dir():
            return None
        if sys.platform.startswith("win"):
            cand = self.bundled_dir / "perce_neige_3d.exe"
        elif sys.platform == "darwin":
            cand = self.bundled_dir / "perce_neige_3d.app" / "Contents" / "MacOS" / "perce_neige_3d"
        else:  # linux + autres unix
            cand = self.bundled_dir / "perce_neige_3d.x86_64"
        return cand if cand.is_file() else None

    @staticmethod
    def _find_godot_executable() -> Optional[str]:
        """Cherche le binaire Godot installé sur la machine.
        - Essaie d'abord le PATH du processus (cas standard).
        - Sur Windows, fallback : lit le PATH utilisateur du registre +
          emplacements connus (~/Documents/Godot, paquet winget). Ce
          fallback couvre le cas où launch.bat est lancé depuis un
          Explorer.exe qui hérite d'un PATH antérieur à l'install Godot
          (les variables utilisateur ne se propagent pas aux processus
          déjà lancés).
        - Préfère un .exe Godot direct au wrapper .cmd, car CreateProcess
          sur Windows ne sait pas spawner un .cmd sans shell=True.
        """
        found = shutil.which("godot")
        if found:
            return found
        if not sys.platform.startswith("win"):
            return None
        candidate_dirs: list[Path] = []
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment") as key:
                user_path, _ = winreg.QueryValueEx(key, "Path")
            for entry in user_path.split(";"):
                entry = entry.strip().strip('"')
                if entry:
                    candidate_dirs.append(Path(os.path.expandvars(entry)))
        except (OSError, ImportError, FileNotFoundError):
            pass
        home = Path.home()
        candidate_dirs.extend([
            home / "Documents" / "Godot",
            home / "AppData" / "Local" / "Microsoft" / "WinGet" / "Packages" /
                "GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe",
        ])
        for d in candidate_dirs:
            if not d.is_dir():
                continue
            # Préférence 1 : .exe Godot principal (exclut le binaire console)
            exes = sorted(
                p for p in d.glob("Godot*.exe")
                if p.is_file() and "console" not in p.name.lower()
            )
            if exes:
                return str(exes[-1])  # tri lexico → version la plus récente en dernier
            # Préférence 2 : wrapper .cmd / .bat
            for name in ("godot.cmd", "godot.bat", "godot.exe"):
                cand = d / name
                if cand.is_file():
                    return str(cand)
        return None

    def _resolve_command(self, engine_args: Optional[list] = None) -> Optional[list]:
        """Retourne la cmdline complète à exécuter, ou None si rien trouvé.
        Préfère le binaire exporté standalone, fallback sur Godot system + projet.

        ``engine_args`` : arguments moteur Godot insérés AVANT le ``--`` (p.ex.
        ``["--rendering-method", "gl_compatibility"]`` pour forcer le rendu
        OpenGL sur une machine sans Vulkan).
        """
        eng = list(engine_args) if engine_args else []
        # 1. Binaire bundled exporté
        bundled = self._bundled_binary_path()
        if bundled is not None:
            return [str(bundled), *eng, "--", "--client", f"--port={self.port}"]
        # 2. Fallback dev : godot system + projet source
        if self.dev_project_dir and self.dev_project_dir.is_dir():
            sys_godot = self._find_godot_executable()
            if sys_godot is not None:
                return [sys_godot, "--path", str(self.dev_project_dir),
                        *eng, "--", "--client", f"--port={self.port}"]
        return None

    def _log(self, msg: str) -> None:
        try:
            with open(self._logfile, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
        except OSError:
            pass

    def _spawn(self, cmd: list, grace_s: float = 1.6) -> bool:
        """Lance ``cmd`` et attend ``grace_s`` pour détecter une mort précoce
        (échec d'init du driver Vulkan/OpenGL → sortie en ~1 s). Retourne True
        si le process est encore vivant après le délai (et stocke self._proc),
        False sinon (process déjà mort, ou échec de spawn).
        """
        import time
        try:
            logf = open(self._logfile, "ab")
        except OSError:
            logf = subprocess.DEVNULL
        try:
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=logf,
            )
        except (FileNotFoundError, OSError, PermissionError) as e:
            self._log(f"[spawn] échec lancement : {e}\n  cmd={cmd}")
            if logf not in (subprocess.DEVNULL,):
                try:
                    logf.close()
                except OSError:
                    pass
            return False
        deadline = time.monotonic() + grace_s
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                self._log(
                    f"[spawn] viewer 3D mort en <{grace_s}s (rc={proc.returncode})\n"
                    f"  cmd={cmd}\n  → tentative de fallback rendu si dispo")
                return False
            time.sleep(0.1)
        self._proc = proc
        return True

    # ------------------------------------------------------------------ #
    # Subprocess management
    # ------------------------------------------------------------------ #

    def is_available(self) -> tuple[bool, str]:
        """Vérifie si on PEUT lancer Godot. Retourne (ok, raison_si_pas_ok).
        Mode normal (utilisateur final) : binaire bundled embarqué dans la
        distribution PyInstaller → toujours dispo. Mode dev : fallback sur
        Godot system + projet source.
        """
        cmd = self._resolve_command()
        if cmd is not None:
            return True, ""
        bundled = self._bundled_binary_path()
        has_dev_proj = self.dev_project_dir is not None and self.dev_project_dir.is_dir()
        sys_godot = self._find_godot_executable()
        if sys.platform.startswith("win"):
            bin_name = "perce_neige_3d.exe"
            install_hint = "godotengine.org/download/windows (Godot 4.6 Standard)"
        elif sys.platform == "darwin":
            bin_name = "perce_neige_3d.app"
            install_hint = "godotengine.org/download/macos (Godot 4.6 Standard)"
        else:
            bin_name = "perce_neige_3d.x86_64"
            install_hint = "godotengine.org/download/linux (Godot 4.6 Standard)"
        bundled_loc = str(self.bundled_dir) if self.bundled_dir else "<non configuré>"
        if bundled is None and not has_dev_proj and sys_godot is None:
            msg = (
                f"Viewer 3D indisponible — ni binaire bundlé, ni Godot installé.\n"
                f"  • Binaire bundlé attendu : {bundled_loc}/{bin_name} (absent)\n"
                f"  • Godot system (fallback dev) : pas dans le PATH\n"
                f"  • Projet 3D source : {self.dev_project_dir or '<absent>'}\n"
                f"→ Installer Godot 4.6 : {install_hint}"
            )
        elif bundled is None and has_dev_proj and sys_godot is None:
            msg = (
                f"Viewer 3D indisponible — projet trouvé ({self.dev_project_dir}) "
                f"mais Godot pas dans le PATH.\n"
                f"→ Installer Godot 4.6 : {install_hint}"
            )
        elif bundled is None and not has_dev_proj and sys_godot is not None:
            msg = (
                f"Viewer 3D indisponible — Godot trouvé ({sys_godot}) "
                f"mais aucun projet 3D source.\n"
                f"→ Cloner github.com/ARP273-ROSE/perce-neige-sim-3d "
                f"dans ~/Documents/, ou builder le binaire bundlé via build_godot_viewer."
            )
        else:
            msg = (
                f"Viewer 3D indisponible — état inattendu "
                f"(bundled={bundled}, dev_proj={has_dev_proj}, godot={sys_godot})"
            )
        return False, msg

    def start(self) -> bool:
        """Démarre Godot en mode --client. Retourne True si OK.
        Si False : aucune exception, le sim continue avec la vue cabine
        procédurale Python (aucune régression).
        """
        if self.is_running():
            return True
        cmd = self._resolve_command()
        if cmd is None:
            ok, reason = self.is_available()
            self._log(f"[start] indisponible : {reason}")
            print(f"[GodotBridge] Viewer 3D non disponible — {reason}")
            print(f"[GodotBridge] → Fallback : vue cabine procédurale Python")
            return False

        # Deux tentatives :
        #  1. rendu par défaut du projet (Forward+ / Vulkan) — qualité maximale
        #     (SDFGI, brouillard volumétrique) sur les machines compatibles.
        #  2. si le viewer meurt aussitôt (pas de Vulkan : Intel HD ancien,
        #     drivers absents, machine virtuelle…), relance en rendu OpenGL
        #     "Compatibility" qui tourne quasiment partout. On perd quelques
        #     effets avancés mais la vue 3D s'affiche.
        attempts = [
            ("Forward+/Vulkan (défaut)", None),
            ("OpenGL Compatibility (fallback)",
             ["--rendering-method", "gl_compatibility",
              "--rendering-driver", "opengl3"]),
        ]
        started = False
        for label, eng_args in attempts:
            c = self._resolve_command(engine_args=eng_args) if eng_args else cmd
            if c is None:
                continue
            self._log(f"[start] tentative : {label}")
            if self._spawn(c):
                self._resolved_cmd = c
                started = True
                self._log(f"[start] OK ({label}, PID={self._proc.pid})")
                break

        if not started:
            print(f"[GodotBridge] Lancement viewer 3D échoué (Vulkan ET OpenGL)")
            print(f"[GodotBridge] → voir {self._logfile}")
            print(f"[GodotBridge] → Fallback : vue cabine procédurale Python")
            return False

        # Crée le socket UDP de send
        if self._sock is None:
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self._sock.setblocking(False)
        mode = "bundled" if self._bundled_binary_path() else "dev"
        print(f"[GodotBridge] Viewer 3D lancé ({mode}, PID={self._proc.pid}, UDP {self.port})")
        return True

    def stop(self) -> None:
        if self._proc is not None:
            try:
                self._proc.terminate()
                try:
                    self._proc.wait(timeout=1.5)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
                    self._proc.wait(timeout=1.0)
            except Exception:
                pass
            print(f"[GodotBridge] Godot arrêté")
            self._proc = None
        if self._sock is not None:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None

    def is_running(self) -> bool:
        if self._proc is None:
            return False
        return self._proc.poll() is None

    def find_window_xid(self, timeout_s: float = 4.0) -> int | None:
        """Alias historique de find_window_id (X11 seul)."""
        return self.find_window_id(timeout_s=timeout_s)

    def find_window_id(self, timeout_s: float = 4.0) -> int | None:
        """Cherche le handle natif de la fenêtre Godot.

        Multiplateforme :
          - Linux X11 : XID via `xdotool search --pid`
          - Windows   : HWND via `EnumWindows + GetWindowThreadProcessId`
                        (utilise ctypes, aucune dépendance externe)
          - macOS / Wayland : non supporté → retourne None

        Le handle retourné est compatible avec `QWindow.fromWinId(int)`
        sur la plateforme courante. Bloquant jusqu'à timeout_s (poll ~10 Hz).
        """
        if self._proc is None:
            return None
        import time
        deadline = time.monotonic() + timeout_s
        pid = self._proc.pid

        if sys.platform.startswith("win"):
            return _find_hwnd_for_pid(pid, deadline)

        if sys.platform.startswith("linux"):
            if shutil.which("xdotool") is None:
                return None
            while time.monotonic() < deadline:
                try:
                    out = subprocess.check_output(
                        ["xdotool", "search", "--pid", str(pid),
                         "--onlyvisible", "--name", "Perce-Neige"],
                        stderr=subprocess.DEVNULL,
                    ).decode().strip()
                    if out:
                        return int(out.splitlines()[-1])
                except subprocess.CalledProcessError:
                    pass
                time.sleep(0.10)
            return None

        # macOS, Wayland, autres : non supporté pour l'embedding
        return None

    def find_window_id_once(self) -> int | None:
        """Recherche du handle natif de la fenêtre en UNE seule passe, SANS
        bloquer (ni sleep, ni timeout). Destiné à être appelé en boucle par
        un QTimer côté sim pour ne jamais geler l'UI. Retourne le handle ou
        None si pas (encore) trouvé."""
        if self._proc is None or self._proc.poll() is not None:
            return None
        pid = self._proc.pid
        if sys.platform.startswith("win"):
            return _enum_hwnd_for_pid(pid)
        if sys.platform.startswith("linux"):
            if shutil.which("xdotool") is None:
                return None
            try:
                out = subprocess.check_output(
                    ["xdotool", "search", "--pid", str(pid),
                     "--onlyvisible", "--name", "Perce-Neige"],
                    stderr=subprocess.DEVNULL,
                ).decode().strip()
                if out:
                    return int(out.splitlines()[-1])
            except subprocess.CalledProcessError:
                pass
            return None
        return None

    # ------------------------------------------------------------------ #
    # State streaming
    # ------------------------------------------------------------------ #

    def send_state(self, state: dict) -> None:
        """Envoie un dict d'état physique en JSON via UDP. Non-bloquant.
        Champs attendus côté Godot :
          s, v, direction, doors_open, trip_started, finished,
          tension_dan, power_kw, speed_cmd, lights_head, lights_cabin,
          emergency, active_fault (str optionnel)
        """
        if self._sock is None or not self.is_running():
            return
        try:
            payload = (json.dumps(state, separators=(",", ":")) + "\n").encode("utf-8")
            self._sock.sendto(payload, self._addr)
        except (BlockingIOError, OSError):
            # Buffer plein ou socket fermé : on ignore (next frame réessaiera)
            pass


def _enum_hwnd_for_pid(target_pid: int) -> int | None:
    """UNE passe EnumWindows (non bloquante). Renvoie le HWND top-level
    visible appartenant à `target_pid` dont le titre contient "Perce-Neige"
    (la dernière si plusieurs — Godot crée parfois une splash + main window),
    ou None. ctypes seulement, dispo sur tout Python Windows."""
    import ctypes
    import ctypes.wintypes as wt

    user32 = ctypes.windll.user32
    EnumWindowsProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    found: list[int] = []

    def _cb(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == target_pid:
            # Filtre : titre contient "Perce-Neige" pour éviter de tomber
            # sur une splash invisible ou une window utilitaire de Godot.
            length = user32.GetWindowTextLengthW(hwnd)
            if length > 0:
                buf = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buf, length + 1)
                if "Perce-Neige" in buf.value:
                    found.append(hwnd)
        return True   # continue l'énumération

    user32.EnumWindows(EnumWindowsProc(_cb), 0)
    return found[-1] if found else None


def _find_hwnd_for_pid(target_pid: int, deadline: float) -> int | None:
    """Cherche le HWND d'une fenêtre top-level appartenant à `target_pid`,
    en pollant jusqu'à `deadline` (time.monotonic()). Retourne None si rien
    trouvé avant l'échéance."""
    import time
    while time.monotonic() < deadline:
        hwnd = _enum_hwnd_for_pid(target_pid)
        if hwnd is not None:
            return int(hwnd)
        time.sleep(0.10)
    return None


def physics_to_state_dict(tr, st=None) -> dict:
    """Helper : convertit un objet TrainPhysics du sim Python en dict
    compatible avec le StateReceiver Godot. Robuste aux champs manquants.
    """
    out = {
        "s": float(getattr(tr, "s", 0.0)),
        "v": float(getattr(tr, "v", 0.0)),
        "direction": int(getattr(tr, "direction", 1)),
        "doors_open": bool(getattr(tr, "doors_open", False)),
        "trip_started": bool(getattr(tr, "trip_started", False)) if not hasattr(st, "trip_started") else bool(getattr(st, "trip_started", False)),
        "finished": bool(getattr(tr, "finished", False)),
        "tension_dan": float(getattr(tr, "cable_tension_dan", getattr(tr, "tension_dan", 0.0))),
        "power_kw": float(getattr(tr, "motor_power_kw", getattr(tr, "power_kw", 0.0))),
        "speed_cmd": float(getattr(tr, "speed_cmd", 0.0)),
        "lights_head": bool(getattr(tr, "lights_head", False)),
        "lights_cabin": bool(getattr(tr, "lights_cabin", True)),
        "emergency": bool(getattr(tr, "emergency", False) or getattr(tr, "electric_stop", False)),
    }
    # Panne courante si le sim Python l'expose
    fault = getattr(st, "active_fault", None) if st is not None else None
    if fault:
        out["active_fault"] = str(fault)
    return out
