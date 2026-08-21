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

# Tampon de build : ecrit la date/heure dans PNConstants.BUILD_TAG le temps
# de l export (affiche sur l ecran de choix du scenario), puis remis a "dev"
# pour ne pas salir le depot. Sert a verifier d un coup d oeil que la PWA ne
# tourne pas sur une vieille copie du service worker.
CONST_GD="$SIM_DIR/godot_project/scripts/constants.gd"
BUILD_STAMP=$(date +"%Y-%m-%d %H:%M")
restore_build_tag() { sed -i 's|^const BUILD_TAG: String = .*|const BUILD_TAG: String = "dev"|' "$CONST_GD"; }
trap restore_build_tag EXIT
sed -i "s|^const BUILD_TAG: String = .*|const BUILD_TAG: String = \"$BUILD_STAMP\"|" "$CONST_GD"
echo "→ Export Web…"
mkdir -p "$SIM_DIR/build/web"
"$GODOT" --headless --path "$SIM_DIR/godot_project" \
    --export-release "Web" 2>&1 | grep -viE "fontconfig|get_system_font" | tail -2

test -f "$SIM_DIR/build/web/index.wasm" || { echo "ERREUR : export Web échoué"; exit 1; }

echo "→ Déploiement vers $WEB_ROOT (uid 33)…"
mkdir -p "$WEB_ROOT"
cp "$SIM_DIR"/build/web/* "$WEB_ROOT/"
# En-têtes de cache : sans eux Cloudflare garde l'export 4 h et il faut
# purger à la main après chaque déploiement (cf. commentaires du fichier).
cp "$SIM_DIR/deploy_web.htaccess" "$WEB_ROOT/.htaccess"
chown -R 33:33 "$WEB_ROOT"

echo "✓ Déployé. https://funiculaire.giff.re ($(du -sh "$WEB_ROOT" | cut -f1))"
echo "  (rappel : le sous-domaine doit exister côté Cloudflare Tunnel)"
