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


datas = _collect_sons() + [
    ("logo.png", "."),
    ("logo_64.png", "."),
    ("logo.ico", "."),
    ("manuel_perce_neige.pdf", "."),
]

hiddenimports = [
    "autoupdate",
    "bugreport",
    "PyQt6.QtMultimedia",
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
