"""Mise à jour automatique sous Linux (09/10/2026).

Retour d'utilisateur, sous Manjaro : « la mise à jour auto de Coupole ça marche mais celle
du funi ça marche pas, il dit qu'il trouve pas GitHub ». L'erreur réseau
réelle était avalée, et une AppImage ou un dossier .tar.gz ne savaient
qu'ouvrir la page de la version. On simule ici le téléchargement : la pièce
testée est la mise en place (AppImage remplacée, dossier échangé, ancienne
version intacte si la vérification échoue).
"""
import hashlib
import io
import os
import sys
import tarfile
from pathlib import Path

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import autoupdate as au  # noqa: E402


def _release(*assets):
    return au.ReleaseInfo(tag="v9.9.9", version="9.9.9", name="", body="",
                          zipball_url="https://x", html_url="https://x",
                          assets=[au.ReleaseAsset(n, "https://example/" + n, len(c))
                                  for n, c in assets])


def _brancher(monkeypatch, contenus, sums_ok=True):
    def faux_dl(url, dest, progress=None, max_bytes=0):
        Path(dest).write_bytes(contenus[url.rsplit("/", 1)[1]])

    def fausse_verif(release, asset, chemin):
        attendu = hashlib.sha256(contenus[asset.name]).hexdigest()
        if not sums_ok or hashlib.sha256(Path(chemin).read_bytes()).hexdigest() != attendu:
            raise RuntimeError("SHA-256 mismatch")

    monkeypatch.setattr(au, "_stream_download", faux_dl)
    monkeypatch.setattr(au, "_verify_asset_sha256", fausse_verif)
    monkeypatch.setattr(au.sys, "platform", "linux")
    monkeypatch.setattr(au.sys, "frozen", True, raising=False)


def test_appimage_remplacee(tmp_path, monkeypatch):
    app = tmp_path / "PerceNeigeSimulator-1.19.4-linux.AppImage"
    app.write_bytes(b"ancienne")
    monkeypatch.setenv("APPIMAGE", str(app))
    nom = "PerceNeigeSimulator-9.9.9-linux.AppImage"
    _brancher(monkeypatch, {nom: b"nouvelle version"})
    exe = au.installer_linux(_release((nom, b"nouvelle version")))
    assert exe == app
    assert app.read_bytes() == b"nouvelle version"
    assert os.access(app, os.X_OK)
    assert not list(tmp_path.glob(".*.maj"))


def test_appimage_corrompue_laisse_l_ancienne(tmp_path, monkeypatch):
    app = tmp_path / "PerceNeigeSimulator-linux.AppImage"
    app.write_bytes(b"ancienne")
    monkeypatch.setenv("APPIMAGE", str(app))
    nom = "PerceNeigeSimulator-9.9.9-linux.AppImage"
    _brancher(monkeypatch, {nom: b"xx"}, sums_ok=False)
    with pytest.raises(RuntimeError):
        au.installer_linux(_release((nom, b"xx")))
    assert app.read_bytes() == b"ancienne"
    assert not list(tmp_path.glob(".*.maj"))


def _tgz(fichiers):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for nom, data in fichiers.items():
            ti = tarfile.TarInfo(nom)
            ti.size = len(data)
            ti.mode = 0o755
            tf.addfile(ti, io.BytesIO(data))
    return buf.getvalue()


def test_dossier_tar_echange(tmp_path, monkeypatch):
    monkeypatch.delenv("APPIMAGE", raising=False)
    dossier = tmp_path / "PerceNeigeSimulator"
    dossier.mkdir()
    (dossier / "PerceNeigeSimulator").write_bytes(b"ancien")
    monkeypatch.setattr(au.sys, "executable", str(dossier / "PerceNeigeSimulator"))
    nom = "PerceNeigeSimulator-9.9.9-linux-x86_64.tar.gz"
    tgz = _tgz({"PerceNeigeSimulator/PerceNeigeSimulator": b"neuf",
                "PerceNeigeSimulator/_internal/lib.so": b"lib"})
    _brancher(monkeypatch, {nom: tgz})
    exe = au.installer_linux(_release((nom, tgz)))
    assert exe == dossier / "PerceNeigeSimulator"
    assert exe.read_bytes() == b"neuf"
    assert (dossier / "_internal" / "lib.so").read_bytes() == b"lib"
    assert not (tmp_path / "PerceNeigeSimulator.ancien").exists()
    assert not list(tmp_path.glob(".pn_maj_*"))


def test_tar_avec_chemin_sortant_refuse(tmp_path, monkeypatch):
    monkeypatch.delenv("APPIMAGE", raising=False)
    dossier = tmp_path / "PerceNeigeSimulator"
    dossier.mkdir()
    (dossier / "PerceNeigeSimulator").write_bytes(b"ancien")
    monkeypatch.setattr(au.sys, "executable", str(dossier / "PerceNeigeSimulator"))
    nom = "PerceNeigeSimulator-9.9.9-linux-x86_64.tar.gz"
    tgz = _tgz({"../evil": b"x"})
    _brancher(monkeypatch, {nom: tgz})
    with pytest.raises(RuntimeError):
        au.installer_linux(_release((nom, tgz)))
    assert (dossier / "PerceNeigeSimulator").read_bytes() == b"ancien"
    assert not (tmp_path / "evil").exists()


def test_erreur_reseau_conservee(monkeypatch):
    def boum(url):
        raise OSError("[SSL: CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate")
    monkeypatch.setattr(au, "_http_get_json", boum)
    assert au.check_latest_release("a", "b") is None
    assert "CERTIFICATE_VERIFY_FAILED" in au.DERNIERE_ERREUR
