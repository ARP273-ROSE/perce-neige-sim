#!/usr/bin/env bash
# Exporte le viewer Godot 3D en binaires standalone (engine + projet embarqués)
# pour la/les plateformes cibles, et copie dans bundled_godot/ pour que
# PyInstaller puisse les embarquer dans la distribution finale du sim Python.
#
# Prérequis :
#   - Godot 4.6.x installé (binaire `godot` dans le PATH)
#   - Templates d'export Godot installés (depuis godotengine.org/download)
#     ~/.local/share/godot/export_templates/4.6.1.stable/
#   - Projet Godot dans ~/Documents/perce-neige-sim-3d/ (ou variable GODOT_PROJ)
#
# Usage :
#   ./build_godot_viewer.sh           # toutes plateformes
#   ./build_godot_viewer.sh linux     # uniquement Linux x86_64
#   ./build_godot_viewer.sh windows   # uniquement Windows x86_64
#   ./build_godot_viewer.sh macos     # uniquement macOS (depuis un Mac)

set -euo pipefail

GODOT_PROJ="${GODOT_PROJ:-$HOME/Documents/perce-neige-sim-3d}"
GODOT_BIN="${GODOT_BIN:-godot}"
SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_DIR="$SIM_DIR/bundled_godot"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    echo "Erreur : binaire '$GODOT_BIN' introuvable. Installer Godot 4.6+." >&2
    exit 1
fi

if [[ ! -d "$GODOT_PROJ" ]]; then
    echo "Erreur : projet Godot introuvable : $GODOT_PROJ" >&2
    echo "Cloner depuis github.com/ARP273-ROSE/perce-neige-sim-3d" >&2
    exit 1
fi

mkdir -p "$BUNDLED_DIR"
TARGET="${1:-all}"

build_linux() {
    echo "→ Export Linux x86_64 (engine + projet embarqués)..."
    cd "$GODOT_PROJ"
    "$GODOT_BIN" --headless --path . --export-release "Linux x86_64" 2>&1 | tail -3
    if [[ -f "$BUNDLED_DIR/perce_neige_3d.x86_64" ]]; then
        chmod +x "$BUNDLED_DIR/perce_neige_3d.x86_64"
        ls -lh "$BUNDLED_DIR/perce_neige_3d.x86_64"
    else
        echo "Erreur : export Linux échoué" >&2
        exit 1
    fi
}

build_windows() {
    echo "→ Export Windows x86_64 (engine + projet embarqués)..."
    cd "$GODOT_PROJ"
    "$GODOT_BIN" --headless --path . --export-release "Windows x86_64" 2>&1 | tail -3
    if [[ -f "$BUNDLED_DIR/perce_neige_3d.exe" ]]; then
        ls -lh "$BUNDLED_DIR/perce_neige_3d.exe"
    else
        echo "Erreur : export Windows échoué" >&2
        exit 1
    fi
}

build_macos() {
    echo "→ Export macOS (depuis un Mac uniquement)..."
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "macOS export saute (pas sur un Mac). Lancer ce script sur macOS." >&2
        return 0
    fi
    cd "$GODOT_PROJ"
    "$GODOT_BIN" --headless --path . --export-release "macOS" 2>&1 | tail -3
}

case "$TARGET" in
    linux)   build_linux ;;
    windows) build_windows ;;
    macos)   build_macos ;;
    all)
        build_linux
        build_windows
        build_macos
        ;;
    *)
        echo "Usage: $0 [linux|windows|macos|all]" >&2
        exit 1
        ;;
esac

echo ""
echo "✓ Viewer 3D exporté dans $BUNDLED_DIR/"
echo "  PyInstaller (perce_neige.spec) embarquera automatiquement le binaire"
echo "  de la plateforme courante dans la distribution finale du sim Python."
