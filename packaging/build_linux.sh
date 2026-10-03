#!/usr/bin/env bash
# Construit Perce-Neige Simulator pour Linux : AppImage + archive .tar.gz.
#
# À lancer DANS un conteneur almalinux:9 (glibc 2.34 ; pas l'image manylinux,
# dont les Python statiques ne conviennent pas à PyInstaller) : c'est le plancher des roues PyQt6 ≥ 6.10 (Qt 6.11, la même
# version que sous Windows). Tourne donc sur toutes les distributions encore
# suivies : Ubuntu ≥ 22.04, Debian ≥ 12, Fedora ≥ 35, RHEL/Alma/Rocky ≥ 9,
# Mint ≥ 21, Arch, openSUSE Tumbleweed… Le workflow GitHub (job build-linux)
# l'appelle tel quel ; en local :
#   docker run --rm -v "$PWD":/src -w /src almalinux:9 \
#       bash packaging/build_linux.sh
# Prérequis : bundled_godot/perce_neige_3d.x86_64 (viewer 3D exporté).
# Sortie : dist_linux/PerceNeigeSimulator-<version>-linux.AppImage
#          dist_linux/PerceNeigeSimulator-<version>-linux-x86_64.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d ' \r\n' < VERSION)
echo "→ Perce-Neige Simulator $VERSION (Linux)"
test -f bundled_godot/perce_neige_3d.x86_64 || { echo "ERREUR : viewer 3D Linux absent"; exit 1; }

# Bibliothèques que Qt charge et que toutes les distributions n'installent
# pas d'office (libxcb-cursor manque sur Ubuntu : « could not load the Qt
# platform plugin xcb ») : présentes ici, PyInstaller les embarque.
dnf install -y -q epel-release >/dev/null
dnf install -y -q python3.12 python3.12-pip binutils libxkbcommon-x11 xcb-util-cursor xcb-util-wm xcb-util-image \
    xcb-util-keysyms xcb-util-renderutil libXrender libXi fontconfig freetype \
    dbus-libs pulseaudio-libs alsa-lib mesa-libGL mesa-libEGL file >/dev/null

PY=python3.12
"$PY" -m venv /tmp/venv-pn
/tmp/venv-pn/bin/pip install -q --upgrade pip
/tmp/venv-pn/bin/pip install -q -r requirements.txt pyinstaller

rm -rf dist_linux build/pyi_linux build/AppDir
/tmp/venv-pn/bin/pyinstaller --noconfirm --log-level WARN \
    --distpath dist_linux --workpath build/pyi_linux perce_neige_unix.spec

# Essai de démarrage sans écran : vivant après 20 s = démarré (une fenêtre
# modale peut attendre un clic, elle ne gêne pas) ; un plantage sort avant.
echo "→ essai de démarrage"
set +e
QT_QPA_PLATFORM=offscreen timeout 20 dist_linux/PerceNeigeSimulator/PerceNeigeSimulator \
    > build/essai_linux.log 2>&1
code=$?
set -e
if [ "$code" -ne 124 ] || grep -q "Traceback" build/essai_linux.log; then
    echo "ERREUR : l'application ne démarre pas (code $code)"
    tail -40 build/essai_linux.log
    exit 1
fi
echo "   démarrage OK"

# AppImage : le dossier PyInstaller dans usr/bin, un lanceur, l'icône et
# le .desktop ; appimagetool (runtime statique : fonctionne aussi sans
# libfuse2, absente des distributions récentes)
APPDIR=build/AppDir
mkdir -p "$APPDIR/usr/bin"
cp -a dist_linux/PerceNeigeSimulator/. "$APPDIR/usr/bin/"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/PerceNeigeSimulator" "$@"
EOF
chmod +x "$APPDIR/AppRun"
cp logo.png "$APPDIR/perce-neige-simulator.png"
cat > "$APPDIR/perce-neige-simulator.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Perce-Neige Simulator
Comment=Simulateur du funiculaire Perce-Neige (Tignes)
Exec=PerceNeigeSimulator
Icon=perce-neige-simulator
Categories=Game;Simulation;
Terminal=false
EOF
curl -sSL -o /tmp/appimagetool \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x /tmp/appimagetool
ARCH=x86_64 /tmp/appimagetool --appimage-extract-and-run --no-appstream "$APPDIR" \
    "dist_linux/PerceNeigeSimulator-$VERSION-linux.AppImage" >/dev/null
tar -C dist_linux -czf "dist_linux/PerceNeigeSimulator-$VERSION-linux-x86_64.tar.gz" PerceNeigeSimulator
ls -lh dist_linux/*.AppImage dist_linux/*.tar.gz
