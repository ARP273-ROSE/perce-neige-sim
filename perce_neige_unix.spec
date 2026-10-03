# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller — Perce-Neige Simulator pour Linux et macOS (2026-10-03).

Windows a son propre paquet (kit : Python embarqué + Inno Setup, voir
.github/workflows/release-windows.yml). Ici, un dossier autonome (« onedir »,
démarrage rapide, pas de décompression à chaque lancement) :
  - Linux : dist/PerceNeigeSimulator/ — mis en AppImage et en .tar.gz par
    le workflow (job build-linux) ;
  - macOS : dist/PerceNeigeSimulator.app — mis en .dmg par le workflow
    (job build-macos), le viewer 3D (perce_neige_3d.app) y est recopié
    après coup avec ditto pour garder ses droits d'exécution.

Le viewer Linux (bundled_godot/perce_neige_3d.x86_64) est embarqué ici
comme donnée ; godot_bridge le cherche sous sys._MEIPASS/bundled_godot.

Exécution : pyinstaller --noconfirm perce_neige_unix.spec
"""
import sys
from pathlib import Path

HERE = Path(SPECPATH)
MACOS = sys.platform == "darwin"


def _collect_sons():
    """Uniquement l'audio chargé à l'exécution (comme perce_neige.spec) :
    le dossier sons/ contient aussi photos et vidéos de référence."""
    out = []
    root = HERE / "sons"
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".wav", ".mp3", ".ogg"}:
            dest = "sons" / p.relative_to(root).parent
            out.append((str(p), str(dest)))
    return out


def _collect_viewer_linux():
    out = []
    viewer = HERE / "bundled_godot" / "perce_neige_3d.x86_64"
    if not MACOS and viewer.is_file():
        out.append((str(viewer), "bundled_godot"))
    return out


# VERSION et kit.json sont relus à côté du code (_lire_version, reporting,
# updater) : sans eux, l'application se croirait en version « » et
# proposerait une mise à jour à chaque démarrage.
datas = _collect_sons() + _collect_viewer_linux() + [
    (str(HERE / f), ".") for f in (
        "VERSION", "kit.json", "logo.png", "logo_64.png", "logo.ico",
        "manuel_perce_neige.pdf", "guide_theorique.pdf", "challenge_best.json",
        "README.md")
    if (HERE / f).is_file()
]

a = Analysis(
    ["perce_neige_sim.py"],
    pathex=[str(HERE)],
    binaries=[],
    datas=datas,
    hiddenimports=["autoupdate", "bugreport", "reporting", "updater",
                   "godot_bridge", "PyQt6.QtMultimedia"],
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="PerceNeigeSimulator",
    debug=False,
    strip=False,
    upx=False,
    console=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="PerceNeigeSimulator",
)
if MACOS:
    app = BUNDLE(
        coll,
        name="PerceNeigeSimulator.app",
        icon=str(HERE / "build" / "logo.icns") if (HERE / "build" / "logo.icns").is_file() else None,
        bundle_identifier="re.giff.perceneige.simulator",
        info_plist={
            "CFBundleName": "Perce-Neige Simulator",
            "CFBundleDisplayName": "Perce-Neige Simulator",
            "CFBundleShortVersionString": (HERE / "VERSION").read_text().strip(),
            "CFBundleVersion": (HERE / "VERSION").read_text().strip(),
            "NSHighResolutionCapable": True,
            "LSMinimumSystemVersion": "11.0",
        },
    )
