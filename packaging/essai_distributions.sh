#!/usr/bin/env bash
# Lance l'AppImage dans des conteneurs de plusieurs distributions, comme sur
# un poste de bureau ordinaire (serveur X virtuel, bibliothèques graphiques
# et son courantes — sans libxcb-cursor, qu'Ubuntu n'installe pas d'office).
# Démarrage réussi = toujours vivant après 25 s, aucun plugin Qt manquant.
#   bash packaging/essai_distributions.sh dist_linux/PerceNeigeSimulator-X-linux.AppImage
set -uo pipefail
APPIMAGE=$(readlink -f "$1")
SRC=$(dirname "$APPIMAGE")
NOM=$(basename "$APPIMAGE")
declare -A PREP=(
  [ubuntu:22.04]="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libgl1 libegl1 libfontconfig1 libx11-6 libx11-xcb1 libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 libpulse0 xvfb >/dev/null"
  [ubuntu:24.04]="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libgl1 libegl1 libfontconfig1 libx11-6 libx11-xcb1 libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 libpulse0 xvfb >/dev/null"
  [debian:12]="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libgl1 libegl1 libfontconfig1 libx11-6 libx11-xcb1 libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 libpulse0 xvfb >/dev/null"
  [fedora:41]="dnf install -y -q mesa-libGL mesa-libEGL fontconfig libX11 libX11-xcb libxkbcommon-x11 dbus-libs pulseaudio-libs xorg-x11-server-Xvfb >/dev/null"
  [archlinux:latest]="pacman -Sy --noconfirm --quiet mesa fontconfig libx11 libxkbcommon-x11 dbus libpulse xorg-server-xvfb >/dev/null"
  [opensuse/tumbleweed]="zypper -q -n install Mesa-libGL1 Mesa-libEGL1 fontconfig libX11-6 libX11-xcb1 libxkbcommon-x11-0 libdbus-1-3 libpulse0 xvfb-run xorg-x11-server-Xvfb >/dev/null"
)
ok=0; ko=0
for img in "${!PREP[@]}"; do
  printf '%-22s ' "$img"
  sortie=$(docker run --rm -v "$SRC":/app:ro "$img" bash -c "
    ${PREP[$img]} || exit 90
    Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
    sleep 2
    cd /tmp && DISPLAY=:99 QT_QPA_PLATFORM=xcb timeout 25 /app/$NOM --appimage-extract-and-run > /tmp/log 2>&1
    code=\$?
    echo CODE=\$code
    grep -iE 'could not load|cannot open shared|Traceback|error while loading' /tmp/log | head -5
    ldd /tmp/appimage_extracted_*/usr/bin/_internal/bundled_godot/perce_neige_3d.x86_64 2>/dev/null | grep -c 'not found' | sed 's/^/LIBS_MANQUANTES_VIEWER=/'
  " 2>&1)
  if echo "$sortie" | grep -q "CODE=124" && ! echo "$sortie" | grep -qiE "could not load|cannot open shared|Traceback|error while loading"; then
    echo "OK   $(echo "$sortie" | grep LIBS_MANQUANTES_VIEWER)"; ok=$((ok+1))
  else
    echo "ÉCHEC"; echo "$sortie" | tail -8 | sed 's/^/      /'; ko=$((ko+1))
  fi
done
echo "→ $ok distribution(s) OK, $ko échec(s)"
[ "$ko" -eq 0 ]
