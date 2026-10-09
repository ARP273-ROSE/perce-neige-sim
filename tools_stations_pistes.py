"""Station (Tignes / Val d'Isère) de chaque piste du jeu — régénérable :
    python3 tools_stations_pistes.py
      → godot_project/scripts/stations_pistes.gd
Kevin, 09/10/2026 : « si les pistes sont sur le domaine de Val d'Isère, tu
mets Val d'Isère sur tes panneaux, pas Tignes ». Six noms existent dans les
deux stations (Face, Glacier, Génépy, Signal…) : chaque tracé du jeu prend
la station du tronçon OpenSkiMap le plus proche (milieu du tracé), d'après
le dossier de données du domaine (secteur = commune OpenSkiMap).
"""
import json
import math
import re
import sys

LAT_O, LON_O = 45.45188591, 6.89898136
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))
SOURCE = sys.argv[1] if len(sys.argv) > 1 else "/workspace/_docs/Tignes-ValDisere-Domaine/pistes.json"

d = json.load(open(SOURCE, encoding="utf-8"))
ref = []                                    # (x, z, secteur)
for p in d["pistes_osm"]:
    g = p.get("geometrie") or []
    pts = g if g and isinstance(g[0], (list, tuple)) and isinstance(g[0][0], (int, float)) else \
        [q for part in g for q in part] if g else []
    for q in pts[:: max(1, len(pts) // 12)]:
        ref.append(((q[0] - LON_O) * M_LON, -(q[1] - LAT_O) * M_LAT, p.get("secteur") or ""))

s = open("godot_project/scripts/pistes_donnees.gd", encoding="utf-8").read()
lignes = re.findall(r'^\t\["([^"]*)", (-?\d+), \[([^\]]*)\]', s, re.M)
val = []
for i, (nom, _c, axe) in enumerate(lignes):
    v = [float(x) for x in axe.split(",") if x.strip()]
    pts = list(zip(v[0::2], v[1::2]))
    mx, mz = pts[len(pts) // 2]
    best = min(ref, key=lambda r: (r[0] - mx) ** 2 + (r[1] - mz) ** 2)
    if "Val" in best[2]:
        val.append(i)
open("godot_project/scripts/stations_pistes.gd", "w", encoding="utf-8").write(
    "class_name StationsPistes\nextends RefCounted\n"
    "## GÉNÉRÉ par tools_stations_pistes.py — ne pas éditer à la main.\n"
    "## Indices (dans PistesDonnees.PISTES) des pistes du domaine de Val d'Isère ;\n"
    "## les autres sont à Tignes.\n"
    "const VAL_DISERE: Array = [%s]\n" % ", ".join(map(str, val)))
print("%d pistes, dont %d à Val d'Isère" % (len(lignes), len(val)))
