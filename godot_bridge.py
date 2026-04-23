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
            sys_godot = shutil.which("godot")
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
        if cmd is None:
            # Diagnostic détaillé
            bundled = self._bundled_binary_path()
            if self.bundled_dir is None:
                msg = "Aucun bundled_dir configuré et pas de mode dev"
            elif bundled is None:
                msg = (
                    f"Binaire 3D bundled non trouvé dans {self.bundled_dir}.\n"
                    f"Plateforme attendue : {sys.platform}.\n"
                    f"Fichier attendu selon OS : "
                    f"perce_neige_3d.exe (Win) / .x86_64 (Linux) / .app/... (macOS)"
                )
            else:
                msg = "Configuration inconsistante"
            return False, msg
        return True, ""

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
