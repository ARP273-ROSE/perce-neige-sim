#!/usr/bin/env bash
# Perce-Neige Simulator launcher (Linux / macOS).
set -e

APP="PerceNeigeSim"
PROJ="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/$APP"
VENV="$DATA/venv"
REQ="$PROJ/requirements.txt"
MARKER="$VENV/.deps_installed"

PY=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1; then
        PY="$cand"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "[Perce-Neige] ERROR: Python 3 not found."
    exit 1
fi

mkdir -p "$DATA"
if [ ! -x "$VENV/bin/python" ]; then
    echo "[Perce-Neige] Creating venv at $VENV"
    "$PY" -m venv "$VENV"
fi
# Validate venv
if ! "$VENV/bin/python" -c 'print("ok")' >/dev/null 2>&1; then
    echo "[Perce-Neige] Rebuilding broken venv"
    rm -rf "$VENV"
    "$PY" -m venv "$VENV"
fi

if ! cmp -s "$REQ" "$MARKER" 2>/dev/null; then
    echo "[Perce-Neige] Installing dependencies"
    "$VENV/bin/python" -m pip install --upgrade pip >/dev/null
    "$VENV/bin/python" -m pip install -r "$REQ"
    cp "$REQ" "$MARKER"
fi

exec "$VENV/bin/python" "$PROJ/perce_neige_sim.py" "$@"
