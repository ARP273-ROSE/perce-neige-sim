#!/usr/bin/env bash
# Exporte la PWA pour le banc de fluidité (tests/web_perf.py) : conduite
# d'essai forcée, chronométrage des rappels requestAnimationFrame, sans
# service worker. usage : web_perf_export.sh <dossier> [arguments Godot…]
set -euo pipefail
SIM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"; shift
ARGS='"--","--drivetest"'
for a in "$@"; do ARGS="$ARGS,\"$a\""; done
GODOT="${GODOT_BIN:-godot}"
"$GODOT" --headless --path "$SIM/godot_project" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$SIM/godot_project" --export-release "Web" 2>&1 | grep -viE "fontconfig|get_system_font" | tail -1
python3 "$SIM/web_patch.py" "$SIM/build/web/index.js"
rm -rf "$OUT"; mkdir -p "$OUT"; cp "$SIM"/build/web/* "$OUT/"
python3 - "$OUT/index.html" "$ARGS" <<'PY'
import re, sys
p, args = sys.argv[1], sys.argv[2]
t = open(p).read()
t = t.replace('"args":[]', '"args":[' + args + ']', 1)
hook = ('<script>(function(){const raf=window.requestAnimationFrame.bind(window);'
        'window.__pn={d:[],t:[]};window.requestAnimationFrame=function(cb){return raf(function(ts){'
        'const a=performance.now();cb(ts);window.__pn.d.push(performance.now()-a);window.__pn.t.push(ts);});};})();</script>')
t = t.replace('<head>', '<head>' + hook, 1)
t = re.sub(r'"serviceWorker":"[^"]*"', '"serviceWorker":""', t)
open(p, 'w').write(t)
PY
chmod -R a+rwX "$OUT"
echo "→ $OUT"
