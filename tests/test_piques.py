"""Banque commune de piques et d'avis (piques_avis.py, 09/10/2026) : le PC
l'ajoute à ses listes, ne ressort pas une pique tirée récemment, et la PWA
reçoit exactement la même chose (pn_quips_extra.gd à jour)."""
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import piques_avis as pa  # noqa: E402
import perce_neige_sim as pn  # noqa: E402

ICI = Path(__file__).resolve().parent.parent


def test_listes_fusionnees():
    assert set(pa.CRASH) <= set(pn.CRASH_QUIPS)
    assert len(pn.CRASH_QUIPS) >= 30
    assert pn.CRASH_LENT_QUIPS and pn.CRASH_VIOLENT_QUIPS
    for tier in ("great", "rough", "disaster"):
        assert len(pn.PAX_REVIEWS[tier]) >= 25
        for qui, vo, fr, en in pn.PAX_REVIEWS[tier]:
            assert qui and vo and fr and en


def test_pas_de_repetition_rapprochee():
    l = pn.DERAIL_QUIPS
    vus = [pn._tirer(l) for _ in range(len(l) // 2)]
    assert len(set(vus)) == len(vus)


def test_pwa_a_jour():
    gd = (ICI / "godot_project" / "scripts" / "pn_quips_extra.gd").read_text(encoding="utf-8")
    for fr, _en in pa.CRASH + pa.SKIEUR_RATE:
        assert fr.replace('"', '\\"') in gd, "relancer : python3 tools_piques.py"
