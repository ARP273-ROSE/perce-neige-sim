#!/usr/bin/env bash
# Exporte le simulateur en Web (WASM) et le déploie sur le NAS gypaete
# derrière le conteneur web-pwa → https://funiculaire.giff.re (PWA iPad).
#
# Prérequis (déjà installés sur le NAS) :
#   - Godot 4.6.1 : /root/godot/godot
#   - templates web : ~/.local/share/godot/export_templates/4.6.1.stable/
# Le variant "nothreads" est utilisé → aucun en-tête COOP/COEP requis.
set -euo pipefail

GODOT="${GODOT_BIN:-/root/godot/godot}"
SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="/mnt/apps_pool/Web/funiculaire"

echo "→ Import des ressources…"
"$GODOT" --headless --path "$SIM_DIR/godot_project" --import >/dev/null 2>&1 || true

echo "→ Export Web…"
mkdir -p "$SIM_DIR/build/web"
"$GODOT" --headless --path "$SIM_DIR/godot_project" \
    --export-release "Web" 2>&1 | grep -viE "fontconfig|get_system_font" | tail -2

test -f "$SIM_DIR/build/web/index.wasm" || { echo "ERREUR : export Web échoué"; exit 1; }

echo "→ Déploiement vers $WEB_ROOT (uid 33)…"
mkdir -p "$WEB_ROOT"
cp "$SIM_DIR"/build/web/* "$WEB_ROOT/"
chown -R 33:33 "$WEB_ROOT"

echo "✓ Déployé. https://funiculaire.giff.re ($(du -sh "$WEB_ROOT" | cut -f1))"
echo "  (rappel : le sous-domaine doit exister côté Cloudflare Tunnel)"
