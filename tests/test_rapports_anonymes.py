"""Rapports d'incident : rien qui nomme la machine, le compte ou le dossier
personnel (nom du PC remplacé par une empreinte courte et stable).

Exécution : pytest tests/test_rapports_anonymes.py -v
"""
import json
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))

import reporting  # noqa: E402

POSTE = "POSTE-ESSAI-42"
COMPTE = "jdupont"


def _faux_poste(monkeypatch):
    monkeypatch.setattr(reporting.platform, "node", lambda: POSTE)
    monkeypatch.setattr(reporting, "_nom_compte", lambda: COMPTE)
    monkeypatch.setattr(reporting.Path, "home", classmethod(lambda cls: Path("/home/jdupont")))


def test_empreinte_courte_et_stable(monkeypatch):
    _faux_poste(monkeypatch)
    a = reporting.empreinte_poste()
    assert a == reporting.empreinte_poste()
    assert len(a) == 10 and all(c in "0123456789abcdef" for c in a)
    monkeypatch.setattr(reporting.platform, "node", lambda: "AUTRE-POSTE")
    assert reporting.empreinte_poste() != a


def test_machine_sans_nom_du_poste(monkeypatch):
    _faux_poste(monkeypatch)
    infos = reporting._machine()
    assert infos["poste"] == reporting.empreinte_poste()
    assert POSTE.lower() not in json.dumps(infos).lower()


def test_anonymiser_chemins_et_noms(monkeypatch):
    _faux_poste(monkeypatch)
    texte = ("/home/jdupont/donnees/x.log ; C:\\Users\\jdupont\\AppData\\y.txt ; "
             "c:/users/jdupont/z ; poste " + POSTE + " ; compte jdupont")
    sortie = reporting.anonymiser(texte)
    assert "jdupont" not in sortie.lower()
    assert POSTE.lower() not in sortie.lower()
    assert "~" in sortie


def test_envoyer_anonymise_aussi_les_dict(monkeypatch):
    _faux_poste(monkeypatch)
    monkeypatch.setattr(reporting, "consentement", lambda: False)
    monkeypatch.setattr(reporting, "_mettre_en_file", lambda r: None)
    rapport = reporting.envoyer(
        "essai", journal="erreur dans /home/jdupont/x.py",
        contexte={"chemin": "C:\\Users\\jdupont\\x", "liste": [POSTE], "n": 3})
    texte = json.dumps(rapport, ensure_ascii=False).lower()
    assert "jdupont" not in texte
    assert POSTE.lower() not in texte
    assert rapport["contexte"]["n"] == 3
