#!/usr/bin/env bash
# Construit Perce-Neige Simulator pour macOS : application autonome (.app)
# dans une image disque (.dmg).
#
# Sur un Mac (le workflow GitHub l'appelle sur macos-15 = Apple Silicon et
# macos-15-intel = Intel) :
#   bash packaging/build_macos.sh apple-silicon     # ou : intel
# Prérequis : python3 (3.12), bundled_godot/perce_neige_3d_macos.zip (export
# Godot « macOS », binaire universel, signature ad hoc).
# Sortie : dist_macos/PerceNeigeSimulator-<version>-macos-<archi>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHI=${1:?"usage : build_macos.sh apple-silicon|intel"}
VERSION=$(tr -d ' \r\n' < VERSION)
echo "→ Perce-Neige Simulator $VERSION (macOS $ARCHI, $(uname -m))"
VIEWER_ZIP=bundled_godot/perce_neige_3d_macos.zip
test -f "$VIEWER_ZIP" || { echo "ERREUR : viewer 3D macOS absent ($VIEWER_ZIP)"; exit 1; }

python3 -m venv /tmp/venv-pn
/tmp/venv-pn/bin/pip install -q --upgrade pip
/tmp/venv-pn/bin/pip install -q -r requirements.txt pyinstaller
mkdir -p build
/tmp/venv-pn/bin/python -c "from PIL import Image; \
Image.open('logo.png').convert('RGBA').resize((1024, 1024)).save('build/logo.icns')"

rm -rf dist_macos build/pyi_macos
/tmp/venv-pn/bin/pyinstaller --noconfirm --log-level WARN \
    --distpath dist_macos --workpath build/pyi_macos perce_neige_unix.spec
APP=dist_macos/PerceNeigeSimulator.app
test -d "$APP"

# Viewer 3D recopié APRÈS PyInstaller avec ditto (droits d'exécution et
# signature de l'app Godot conservés) dans Resources, avec le lien depuis
# Frameworks (= sys._MEIPASS) que PyInstaller pose pour ses propres données.
mkdir -p "$APP/Contents/Resources/bundled_godot"
ditto -x -k "$VIEWER_ZIP" "$APP/Contents/Resources/bundled_godot/"
ln -sfn ../Resources/bundled_godot "$APP/Contents/Frameworks/bundled_godot"
VIEWER_APP=$(find "$APP/Contents/Resources/bundled_godot" -maxdepth 1 -name "*.app" | head -1)
VIEWER_BIN=$(find "$VIEWER_APP/Contents/MacOS" -type f | head -1)
test -x "$VIEWER_BIN" || { echo "ERREUR : exécutable du viewer introuvable"; exit 1; }

# Signature ad hoc de l'ensemble : obligatoire sur Apple Silicon (un binaire
# non signé n'y démarre pas), et le paquet a changé depuis PyInstaller.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Essais : le simulateur démarre (sans écran) et le viewer 3D s'exécute.
echo "→ essai de démarrage"
QT_QPA_PLATFORM=offscreen "$APP/Contents/MacOS/PerceNeigeSimulator" > build/essai_macos.log 2>&1 &
PID=$!
sleep 25
if ! kill -0 "$PID" 2>/dev/null || grep -q "Traceback" build/essai_macos.log; then
    echo "ERREUR : l'application ne démarre pas"; tail -40 build/essai_macos.log; exit 1
fi
kill "$PID" || true
echo "   simulateur OK"
if ! "$VIEWER_BIN" --headless --quit > build/essai_viewer.log 2>&1; then
    echo "ERREUR : le viewer 3D ne démarre pas"; tail -20 build/essai_viewer.log; exit 1
fi
echo "   viewer 3D OK ($(lipo -archs "$VIEWER_BIN"))"

# Image disque : l'app et un raccourci vers Applications (glisser-déposer)
STAGE=build/dmg
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Perce-Neige Simulator.app"
ln -s /Applications "$STAGE/Applications"
DMG="dist_macos/PerceNeigeSimulator-$VERSION-macos-$ARCHI.dmg"
hdiutil create -volname "Perce-Neige Simulator" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
ls -lh "$DMG"
