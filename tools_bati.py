"""Lumières des villages, la nuit — régénérable :
    python3 tools_bati.py [bati.json]
      → godot_project/scripts/bati_donnees.gd

Source : bâtiments d'OpenStreetMap (© contributeurs OpenStreetMap, licence ODbL), centres des
emprises « building » sur l'emprise du relief (Overpass API). Seules des valeurs numériques entrent
dans le dépôt : position du centre dans le repère du jeu (x vers l'est, z vers le sud, mètres,
origine au pied de la voie du Perce-Neige) et une taille (1 maison ou chalet, 2 immeuble, hôtel).
Ruines, toits seuls, abris, garages et transformateurs sont écartés.
"""
import base64
import json
import math
import struct
import sys
import urllib.parse
import urllib.request
from pathlib import Path

LAT_O, LON_O = 45.45188591, 6.89898136        # pied de la voie (repère du jeu, comme tools_relief3d.py)
LAT0, LAT1, LON0, LON1 = 45.375, 45.530, 6.820, 7.090
M_LAT = 111320.0
M_LON = 111320.0 * math.cos(math.radians(LAT_O))
URL = "https://overpass-api.de/api/interpreter"
ECARTES = {"ruins", "construction", "roof", "shed", "garage", "garages", "service", "transformer_tower",
           "bunker", "water_tower", "carport"}
GRANDS = {"apartments", "hotel", "residential", "commercial", "retail", "dormitory", "school", "public"}
SORTIE = Path(__file__).resolve().parent / "godot_project" / "scripts" / "bati_donnees.gd"


def lire(chemin=None):
    if chemin:
        return json.loads(Path(chemin).read_text(encoding="utf-8"))
    q = f'[out:json][timeout:200];way["building"]({LAT0},{LON0},{LAT1},{LON1});out center tags;'
    req = urllib.request.Request(URL, data=urllib.parse.urlencode({"data": q}).encode(),
                                 headers={"User-Agent": "pn-sim-carto/1.0"})
    return json.loads(urllib.request.urlopen(req, timeout=240).read())


def ecrire(d):
    b = bytearray()
    n = 0
    for e in d["elements"]:
        c = e.get("center")
        t = e.get("tags", {}).get("building", "yes")
        if not c or t in ECARTES:
            continue
        x = (c["lon"] - LON_O) * M_LON
        z = -(c["lat"] - LAT_O) * M_LAT
        b += struct.pack("<hhh", int(round(x)), int(round(z)), 2 if t in GRANDS else 1)
        n += 1
    s = base64.b64encode(bytes(b)).decode()
    lignes = [s[i:i + 120] for i in range(0, len(s), 120)]
    tete = f"""## GÉNÉRÉ par tools_bati.py — bâtiments d'OpenStreetMap (© contributeurs OpenStreetMap, licence ODbL).
## Ne pas éditer à la main. {n} bâtiments ; par bâtiment, 3 entiers 16 bits signés petit-boutistes : x, z du centre
## (m, repère du jeu : x vers l'est, z vers le sud) et la taille (1 maison ou chalet, 2 immeuble ou hôtel).
class_name BatiDonnees
extends RefCounted

const N: int = {n}
const DONNEES: String = (
"""
    SORTIE.write_text(tete + " +\n".join(f'\t"{l}"' for l in lignes) + "\n)\n", encoding="utf-8")
    print(f"{n} bâtiments → {SORTIE}")


if __name__ == "__main__":
    ecrire(lire(sys.argv[1] if len(sys.argv) > 1 else None))
