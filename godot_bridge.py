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

    def _resolve_command(self) -> Optional[list]:
        """Retourne la cmdline complète à exécuter, ou None si rien trouvé.
        Préfère le binaire exporté standalone, fallback sur Godot system + projet.
        """
        # 1. Binaire bundled exporté
        bundled = self._bundled_binary_path()
        if bundled is not None:
            return [str(bundled), "--", "--client", f"--port={self.port}"]
        # 2. Fallback dev : godot system + projet source
        if self.dev_project_dir and self.dev_project_dir.is_dir():
            sys_godot = self._find_godot_executable()
            if sys_godot is not None:
                return [sys_godot, "--path", str(self.dev_project_dir),
                        "--", "--client", f"--port={self.port}"]
        return None

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
            print(f"[GodotBridge] Viewer 3D non disponible — {reason}")
            print(f"[GodotBridge] → Fallback : vue cabine procédurale Python")
            return False
        self._resolved_cmd = cmd
        try:
            self._proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (FileNotFoundError, OSError, PermissionError) as e:
            print(f"[GodotBridge] Lancement viewer 3D échoué : {e}")
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


def _find_hwnd_for_pid(target_pid: int, deadline: float) -> int | None:
    """Cherche le HWND d'une fenêtre top-level appartenant à `target_pid`.

    Polling jusqu'à `deadline` (time.monotonic()). On enumère toutes les
    fenêtres top-level visibles via user32.EnumWindows et on garde la
    première dont le PID propriétaire match (ou la dernière si plusieurs,
    Godot crée parfois une splash + main window).

    Pas de dépendance externe : ctypes seulement, dispo sur tout Python
    Windows. Retourne None si aucune fenêtre trouvée avant la deadline.
    """
    import ctypes
    import ctypes.wintypes as wt
    import time

    user32 = ctypes.windll.user32
    EnumWindowsProc = ctypes.WINFUNCTYPE(
        wt.BOOL, wt.HWND, wt.LPARAM)

    def _enum_once() -> int | None:
        found: list[int] = []

        def _cb(hwnd: int, _lparam: int) -> bool:
            if not user32.IsWindowVisible(hwnd):
                return True
            pid = wt.DWORD()
            user32.GetWindowThreadProcessId(
                hwnd, ctypes.byref(pid))
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

    while time.monotonic() < deadline:
        hwnd = _enum_once()
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
