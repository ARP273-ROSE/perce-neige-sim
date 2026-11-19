"""Ciel étoilé du simulateur — régénérable :
    python3 tools_etoiles.py [bsc5.dat.gz]
      → godot_project/scripts/etoiles_donnees.gd

Source : Yale Bright Star Catalogue, 5e édition (BSC5, 1991), données publiques
distribuées par le Centre de données astronomiques (format ASCII de la table V/50, copie du
Harvard-Smithsonian Center for Astrophysics : http://tdc-www.harvard.edu/catalogs/bsc5.dat.gz).
Seules des valeurs numériques entrent dans le dépôt : position J2000, magnitude V, indice B−V,
pour les étoiles de magnitude ≤ 6,0 (≈ 5 000), triées par éclat.
"""
import base64
import gzip
import io
import struct
import sys
import urllib.request
from pathlib import Path

URL = "http://tdc-www.harvard.edu/catalogs/bsc5.dat.gz"
MAG_MAX = 6.0
SORTIE = Path(__file__).resolve().parent / "godot_project" / "scripts" / "etoiles_donnees.gd"


def lire(chemin=None):
    brut = Path(chemin).read_bytes() if chemin else urllib.request.urlopen(URL, timeout=60).read()
    etoiles = []
    for ligne in gzip.open(io.BytesIO(brut), "rt", encoding="latin-1"):
        if len(ligne) < 114:
            continue
        try:
            rah, ram, ras = int(ligne[75:77]), int(ligne[77:79]), float(ligne[79:83])
            sg, dd, dm, ds = ligne[83], int(ligne[84:86]), int(ligne[86:88]), int(ligne[88:90])
            v = float(ligne[102:107])
        except ValueError:
            continue          # novæ et objets sans position (quelques entrées)
        bv_txt = ligne[109:114].strip()
        bv = float(bv_txt) if bv_txt else 0.6
        ra = (rah + ram / 60 + ras / 3600) * 15.0
        de = (dd + dm / 60 + ds / 3600) * (-1 if sg == "-" else 1)
        if v <= MAG_MAX:
            etoiles.append((ra, de, v, bv))
    etoiles.sort(key=lambda e: e[2])
    return etoiles


def ecrire(etoiles):
    b = bytearray()
    for ra, de, v, bv in etoiles:
        b += struct.pack("<HHHH", int(round(ra / 360 * 65535)) % 65536, int(round((de + 90) / 180 * 65535)),
                         int(round((v + 2) * 1000)), int(round((max(-0.5, min(2.5, bv)) + 0.5) * 10000)))
    s = base64.b64encode(bytes(b)).decode()
    lignes = [s[i:i + 120] for i in range(0, len(s), 120)]
    n = len(etoiles)
    tete = f"""## GÉNÉRÉ par tools_etoiles.py (catalogue d'étoiles brillantes de Yale, 5e édition, BSC5 : données publiques du
## Centre de données astronomiques). Ne pas éditer à la main. {n} étoiles de magnitude visuelle ≤ 6,0, triées par éclat.
## Par étoile, 4 entiers 16 bits petit-boutistes : ascension droite J2000 (×65535/360°), déclinaison J2000
## ((δ + 90°) × 65535/180°), magnitude V ((V + 2) × 1000), indice B−V ((B−V + 0,5) × 10000).
class_name EtoilesDonnees
extends RefCounted

const N: int = {n}
const DONNEES: String = (
"""
    SORTIE.write_text(tete + " +\n".join(f'\t"{l}"' for l in lignes) + "\n)\n", encoding="utf-8")
    print(f"{n} étoiles → {SORTIE}")


if __name__ == "__main__":
    ecrire(lire(sys.argv[1] if len(sys.argv) > 1 else None))
