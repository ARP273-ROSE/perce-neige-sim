# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the standalone Perce-Neige Simulator.

Produces a single, console-less executable that bundles:
  - Python, PyQt6, PyQt6-Multimedia plugins
  - On-board announcement audio (sons/)
  - Logo, user manual PDF
  - autoupdate and bugreport helper modules

Usage
-----
  pip install pyinstaller
  pyinstaller perce_neige.spec
Output: dist/PerceNeigeSimulator(.exe)
"""
from pathlib import Path
import sys

HERE = Path(SPECPATH).resolve() if "SPECPATH" in globals() else Path.cwd()

def _collect_sons():
    """Bundle on-board announcement audio but EXCLUDE sons/videos/
    which contains large local reference material not needed at runtime."""
    out = []
    root = HERE / "sons"
    if not root.exists():
        return out
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        rel_parts = p.relative_to(root).parts
        if rel_parts and rel_parts[0] == "videos":
            continue
        dest = "sons" / Path(*rel_parts).parent
        out.append((str(p), str(dest)))
    return out


def _collect_godot_bundled():
    """Bundle le viewer Godot 3D standalone exporté pour la plateforme cible.
    Le binaire .x86_64 / .exe / .app contient le moteur + le projet PCK,
    donc l'utilisateur n'a RIEN à installer pour la vue F4 en 3D.
    Si bundled_godot/ n'existe pas (build sans le viewer 3D), tant pis :
    F4 fait fallback sur la vue cabine procédurale Python.
    """
    out = []
    root = HERE / "bundled_godot"
    if not root.exists():
        return out
    target = sys.platform
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        name = p.name
        # Filtre selon la plateforme courante (PyInstaller build OS-spécifique)
        if target.startswith("win"):
            if not (name.endswith(".exe") or name.endswith(".pck")):
                continue
        elif target == "darwin":
            # macOS : tout le contenu de l'app bundle
            if ".app" not in str(p):
                continue
        else:  # linux + autres
            if not (name.endswith(".x86_64") or name.endswith(".pck")):
                continue
        rel = p.relative_to(root)
        dest = "bundled_godot" / rel.parent
        out.append((str(p), str(dest)))
    return out


datas = _collect_sons() + _collect_godot_bundled() + [
    ("logo.png", "."),
    ("logo_64.png", "."),
    ("logo.ico", "."),
    ("manuel_perce_neige.pdf", "."),
    ("godot_bridge.py", "."),
]

hiddenimports = [
    "autoupdate",
    "bugreport",
    "PyQt6.QtMultimedia",
    "godot_bridge",
]

block_cipher = None

a = Analysis(
    ["perce_neige_sim.py"],
    pathex=[str(HERE)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="PerceNeigeSimulator",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon="logo.ico",
)
