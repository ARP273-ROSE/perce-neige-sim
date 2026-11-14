"""Pack HD abîmé : la vue 3D le signale, le marqueur est effacé et le
téléchargement relancé — une seule fois par version du pack.

Exécution : pytest tests/test_pack_hd_reparer.py -v
"""
import sys
import threading
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))

import pack_hd  # noqa: E402


def _pack_installe(donnees: Path) -> None:
    d = pack_hd.dossier(donnees)
    d.mkdir(parents=True)
    (d / "relief.pnhd").write_bytes(b"abime")
    (d / ".installe").write_text(pack_hd.EMPREINTE, encoding="ascii")


def test_reparer_efface_le_marqueur_et_relance(tmp_path, monkeypatch):
    _pack_installe(tmp_path)
    lances = []
    monkeypatch.setattr(pack_hd, "demarrer", lambda d: lances.append(d))
    assert pack_hd.dossier_si_pret(tmp_path) is not None
    assert pack_hd.reparer(tmp_path) is True
    assert pack_hd.dossier_si_pret(tmp_path) is None
    assert lances == [tmp_path]


def test_reparer_une_seule_fois_par_version(tmp_path, monkeypatch):
    _pack_installe(tmp_path)
    lances = []
    monkeypatch.setattr(pack_hd, "demarrer", lambda d: lances.append(d))
    assert pack_hd.reparer(tmp_path) is True
    # le nouveau pack posé reste illisible : pas de second téléchargement
    (pack_hd.dossier(tmp_path) / ".installe").write_text(pack_hd.EMPREINTE, encoding="ascii")
    assert pack_hd.reparer(tmp_path) is False
    assert len(lances) == 1
    assert pack_hd.dossier_si_pret(tmp_path) is not None


def test_reparer_sans_pack_ne_plante_pas(tmp_path, monkeypatch):
    monkeypatch.setattr(pack_hd, "demarrer", lambda d: None)
    pack_hd.reparer(tmp_path / "absent")


def test_demarrer_ne_lance_pas_deux_installations(tmp_path, monkeypatch):
    libre = threading.Event()
    appels = []

    def installer(d):
        appels.append(d)
        libre.wait(5)

    monkeypatch.setattr(pack_hd, "installer", installer)
    pack_hd.demarrer(tmp_path)
    pack_hd.demarrer(tmp_path)
    libre.set()
    pack_hd._fil.join(5)
    assert len(appels) == 1
