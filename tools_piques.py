"""Génère godot_project/scripts/pn_quips_extra.gd depuis piques_avis.py (la
même banque de piques et d'avis pour le PC et la PWA).

    python3 tools_piques.py

Adaptations Web (cf. pn_quips.gd) : drapeau emoji → code pays entre
crochets, VO affichée seulement si elle s'écrit en alphabet latin.
"""
import json
from pathlib import Path

import piques_avis as pa

ICI = Path(__file__).resolve().parent
SORTIE = ICI / "godot_project" / "scripts" / "pn_quips_extra.gd"


def _code_pays(qui: str) -> str:
    drapeau, _, reste = qui.partition(" ")
    lettres = [chr(ord(c) - 0x1F1E6 + ord("A")) for c in drapeau if 0x1F1E6 <= ord(c) <= 0x1F1FF]
    return f"[{''.join(lettres)}] {reste}" if len(lettres) == 2 else qui


def _latin(txt: str) -> bool:
    return all(ord(c) < 0x250 or c in "’‘“”«»…—–−" for c in txt)


def _s(x: str) -> str:
    return json.dumps(x, ensure_ascii=False)


def main() -> None:
    out = ["# FICHIER GÉNÉRÉ par tools_piques.py depuis piques_avis.py — ne pas modifier.",
           "class_name PNQuipsExtra", "extends Object", ""]
    for nom in ("CRASH", "CRASH_LENT", "CRASH_VIOLENT", "DERAIL", "CABIN", "REVERSE", "DOORS_OPEN",
                "SKIEUR_HORS_PISTE", "SKIEUR_RATE", "SKIEUR_EVACUATION", "SKIEUR_VOIE", "SKIEUR_SORTIE"):
        out.append(f"const {nom}: Array = [")
        for fr, en in getattr(pa, nom):
            out.append(f"\t[{_s(fr)},\n\t {_s(en)}],")
        out += ["]", ""]
    for tier, liste in pa.REVIEWS.items():
        out.append(f"const REVIEWS_{tier.upper()}: Array = [")
        for qui, vo, fr, en in liste:
            vo_aff = vo if (vo and vo != fr and _latin(vo)) else ""
            out.append(f"\t[{_s(_code_pays(qui))}, {_s(vo_aff)}, {'true' if vo_aff else 'false'},\n"
                       f"\t {_s(fr)},\n\t {_s(en)}],")
        out += ["]", ""]
    SORTIE.write_text("\n".join(out), encoding="utf-8")
    print(f"écrit {SORTIE} ({sum(len(getattr(pa, n)) for n in ('CRASH','CRASH_LENT','CRASH_VIOLENT','DERAIL','CABIN','REVERSE','DOORS_OPEN','SKIEUR_HORS_PISTE','SKIEUR_RATE','SKIEUR_EVACUATION','SKIEUR_VOIE','SKIEUR_SORTIE'))} piques, "
          f"{sum(len(v) for v in pa.REVIEWS.values())} avis)")


if __name__ == "__main__":
    main()
