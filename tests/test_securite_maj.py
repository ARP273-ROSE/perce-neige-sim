"""Mise à jour du kit (updater.py) : empreinte obligatoire, extraction sûre.

Une archive n'est posée que si la Release publie SHA256SUMS ET une ligne pour
elle ; une archive dont un membre sortirait du dossier d'extraction est
refusée avant toute écriture.

Exécution : pytest tests/test_securite_maj.py -v
"""
import hashlib
import io
import sys
import zipfile
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))

import updater  # noqa: E402
import autoupdate  # noqa: E402


class _Flux(io.BytesIO):
    headers: dict = {}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _archive(tmp_path, contenu=b"donnees"):
    chemin = tmp_path / "maj.zip"
    chemin.write_bytes(contenu)
    return chemin


def _maj(nom="pn-app-1.0.zip", sommes=True, taille=0):
    return {"version": "1.0", "url": "https://github.com/x/" + nom, "nom": nom,
            "size": taille,
            "sha256sums_url": "https://github.com/x/SHA256SUMS" if sommes else ""}


def test_refuse_sans_sha256sums(tmp_path):
    with pytest.raises(RuntimeError, match="SHA256SUMS"):
        updater.verifier_integrite(_maj(sommes=False), _archive(tmp_path), 7)


def test_refuse_sans_ligne_pour_l_archive(tmp_path, monkeypatch):
    autre = "0" * 64 + "  autre-archive.zip\n"
    monkeypatch.setattr(updater, "_open", lambda url: _Flux(autre.encode()))
    with pytest.raises(RuntimeError, match="empreinte"):
        updater.verifier_integrite(_maj(), _archive(tmp_path), 7)


def test_refuse_empreinte_differente(tmp_path, monkeypatch):
    fausse = "f" * 64 + "  pn-app-1.0.zip\n"
    monkeypatch.setattr(updater, "_open", lambda url: _Flux(fausse.encode()))
    with pytest.raises(RuntimeError, match="SHA-256"):
        updater.verifier_integrite(_maj(), _archive(tmp_path), 7)


def test_accepte_empreinte_juste(tmp_path, monkeypatch):
    archive = _archive(tmp_path)
    bonne = hashlib.sha256(archive.read_bytes()).hexdigest() + " *pn-app-1.0.zip\n"
    monkeypatch.setattr(updater, "_open", lambda url: _Flux(bonne.encode()))
    updater.verifier_integrite(_maj(), archive, archive.stat().st_size)


@pytest.mark.parametrize("membre", ["../dehors.py", "a/../../dehors.py",
                                    "/etc/dehors.py", ""])
def test_membre_hors_du_dossier(tmp_path, membre):
    assert updater.hors_du_dossier(tmp_path / "contenu", membre)


def test_dossier_voisin_refuse(tmp_path):
    # « contenu-bis » commence comme « contenu » : la comparaison de chaînes
    # d'avant l'aurait laissé passer
    assert updater.hors_du_dossier(tmp_path / "contenu", "../contenu-bis/x.py")


@pytest.mark.parametrize("membre", ["app/x.py", "x.py", "a/b/../c.py"])
def test_membre_dans_le_dossier(tmp_path, membre):
    assert not updater.hors_du_dossier(tmp_path / "contenu", membre)


def test_archive_evadee_refusee_sans_rien_ecrire(tmp_path, monkeypatch):
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as z:
        z.writestr("app/ok.py", "x = 1\n")
        z.writestr("../evade.py", "x = 2\n")
    donnees = tampon.getvalue()
    nom = "pn-app-1.0.zip"
    somme = hashlib.sha256(donnees).hexdigest() + "  " + nom + "\n"
    cible = tmp_path / "app"
    cible.mkdir()
    (cible / "existant.py").write_text("garde\n")

    def ouvrir(url):
        return _Flux(somme.encode() if url.endswith("SHA256SUMS") else donnees)

    monkeypatch.setattr(updater, "_open", ouvrir)
    monkeypatch.setattr(updater, "app_dir", lambda: cible)
    with pytest.raises(RuntimeError, match="suspecte"):
        updater.download_and_apply(_maj(nom, taille=len(donnees)))
    assert (cible / "existant.py").read_text() == "garde\n"
    assert not (cible / "ok.py").exists()
    assert not (tmp_path / "evade.py").exists()


def test_archive_sans_empreinte_refusee_sans_rien_ecrire(tmp_path, monkeypatch):
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as z:
        z.writestr("ok.py", "x = 1\n")
    donnees = tampon.getvalue()
    cible = tmp_path / "app"
    cible.mkdir()
    monkeypatch.setattr(updater, "_open", lambda url: _Flux(donnees))
    monkeypatch.setattr(updater, "app_dir", lambda: cible)
    with pytest.raises(RuntimeError, match="SHA256SUMS"):
        updater.download_and_apply(_maj(sommes=False, taille=len(donnees)))
    assert list(cible.iterdir()) == []


def test_tar_evade_refuse(tmp_path):
    import tarfile
    archive = tmp_path / "a.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        info = tarfile.TarInfo("../dest-bis/x")
        info.size = 1
        tf.addfile(info, io.BytesIO(b"x"))
    dest = tmp_path / "dest"
    dest.mkdir()
    with pytest.raises(RuntimeError):
        autoupdate._extraire_tar_sur(archive, dest)
    assert not (tmp_path / "dest-bis").exists()
