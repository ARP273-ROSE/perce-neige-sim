"""Mise à jour automatique : compatibilité avec les versions INSTALLÉES.

Depuis la 1.20.0, chaque système publie sa propre archive de mise à jour
(le viewer 3D est un binaire propre au système) :

    perce-neige-sim-app-X.zip                    Windows (viewer .exe)
    perce-neige-sim-maj-linux-x86_64-X.zip       Linux x86_64
    perce-neige-sim-maj-linux-arm64-X.zip        Linux ARM64
    perce-neige-sim-maj-macos-<arch>-X.zip       macOS

Les paquets Windows déjà installés (Setup 1.15.3 → 1.19.30) gardent leur
updater, qui prend la PREMIÈRE archive « perce-neige-sim-app-*.zip » de la
Release : elle doit être celle de Windows quel que soit l'ordre des
fichiers. Les anciens paquets Linux (AppImage, dossier .tar.gz, PyInstaller)
se remplaçaient par « …-linux.AppImage » / « …-linux-x86_64.tar.gz » avec
SHA256SUMS obligatoire : la Release fournit une passerelle pour chacun.

Exécution : pytest tests/test_maj_compat.py -v
"""
import hashlib
import importlib.util
import json
import sys
import tarfile
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parent.parent
ANCIENS = Path(__file__).resolve().parent / "anciens"
V = "1.20.0"

FICHIERS = [
    f"PerceNeigeSimulator-{V}-linux-arm64.tar.gz",
    f"PerceNeigeSimulator-{V}-linux-x86_64.tar.gz",
    f"PerceNeigeSimulator-{V}-linux.AppImage",
    f"PerceNeigeSimulator-{V}-macos-arm64.dmg",
    f"PerceNeigeSimulator-{V}-macos-x86_64.dmg",
    f"PerceNeigeSimulator-Setup-{V}.exe",
    "PerceNeigeSimulator-Setup.exe",
    "PerceNeigeSimulator-linux-x86_64.tar.gz",
    "SHA256SUMS",
    f"perce-neige-sim-app-{V}.zip",
    f"perce-neige-sim-maj-linux-arm64-{V}.zip",
    f"perce-neige-sim-maj-linux-x86_64-{V}.zip",
    f"perce-neige-sim-maj-macos-arm64-{V}.zip",
    f"perce-neige-sim-maj-macos-x86_64-{V}.zip",
]


def _release(noms):
    return {"tag_name": f"v{V}", "body": "## Francais\nnotes\n## English\nnotes",
            "html_url": "https://github.com/ARP273-ROSE/perce-neige-sim/releases/tag/v" + V,
            "zipball_url": "https://api.github.com/x",
            "assets": [{"name": n, "size": 10,
                        "browser_download_url": f"https://github.com/ARP273-ROSE/perce-neige-sim/releases/download/v{V}/{n}"}
                       for n in noms]}


def _module(chemin, nom):
    spec = importlib.util.spec_from_file_location(nom, chemin)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[nom] = mod                   # dataclasses en ont besoin
    sys.path.insert(0, str(RACINE))          # kit.json, contexte_tls
    spec.loader.exec_module(mod)
    return mod


class _Reponse:
    def __init__(self, data):
        self.data = json.dumps(data).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, *a):
        d, self.data = self.data, b""
        return d


@pytest.mark.parametrize("ordre", ["alphabetique", "inverse", "maj_d_abord"])
def test_ancien_updater_windows_prend_l_archive_windows(monkeypatch, ordre):
    ancien = _module(ANCIENS / "updater_1_19_30.py", "updater_1_19_30")
    # l'ancien updater lit le kit.json installé à côté de lui (même dépôt,
    # même nom technique qu'aujourd'hui)
    monkeypatch.setattr(ancien, "REPO", "ARP273-ROSE/perce-neige-sim")
    monkeypatch.setattr(ancien, "PREFIXE_ARCHIVE", "perce-neige-sim-app-")
    noms = sorted(FICHIERS, key=str.lower)
    if ordre == "inverse":
        noms = noms[::-1]
    elif ordre == "maj_d_abord":
        noms = sorted(noms, key=lambda n: "-maj-" not in n)
    monkeypatch.setattr(ancien, "_open", lambda url: _Reponse(_release(noms)))
    info = ancien.check("1.19.30")
    assert info["url"].endswith(f"/perce-neige-sim-app-{V}.zip")


@pytest.mark.parametrize("plate,arch,attendu", [
    ("windows", "x86_64", f"perce-neige-sim-app-{V}.zip"),
    ("linux", "x86_64", f"perce-neige-sim-maj-linux-x86_64-{V}.zip"),
    ("linux", "arm64", f"perce-neige-sim-maj-linux-arm64-{V}.zip"),
    ("macos", "arm64", f"perce-neige-sim-maj-macos-arm64-{V}.zip"),
    ("macos", "x86_64", f"perce-neige-sim-maj-macos-x86_64-{V}.zip"),
])
def test_nouvel_updater_prend_l_archive_de_son_systeme(monkeypatch, plate, arch, attendu):
    sys.path.insert(0, str(RACINE))
    import updater
    monkeypatch.setattr(updater, "plateforme", lambda: plate)
    monkeypatch.setattr(updater, "architecture", lambda: arch)
    monkeypatch.setattr(updater, "_open", lambda url: _Reponse(_release(FICHIERS)))
    info = updater.check("1.19.30")
    assert info["url"].endswith("/" + attendu)
    assert "notes" in updater.notes_dans_la_langue(info["notes"], "fr")


def test_kit_json_publie_une_archive_par_systeme():
    kit = json.loads((RACINE / "kit.json").read_text(encoding="utf-8"))
    assert kit["archive_par_systeme"] is True
    assert kit["passerelle_pyinstaller"] is True
    # chaque système a SON viewer 3D, et seulement le sien
    vus = {tuple(r.get("systemes") or ()): r for r in kit["copies"] if r["de"] == "bundled_godot"}
    assert set(vus) == {("windows",), ("linux-x86_64",), ("linux-arm64",), ("macos",)}
    assert vus[("macos",)].get("decompresser") is True
    # les données de l'utilisateur ne partent jamais dans l'archive
    assert {"exploitation.db", "challenge_best.json"} <= set(kit["fichiers_proteges"])
    assert "challenge_best.json" not in kit["assets"]


def test_ancienne_maj_linux_dossier_accepte_le_paquet_du_kit(tmp_path, monkeypatch):
    """L'ancien paquet Linux PyInstaller en dossier remplace son dossier par
    celui de « …-linux-x86_64.tar.gz » s'il y trouve un exécutable
    « PerceNeigeSimulator » — que le paquet du kit fournit (lanceur nu)."""
    au = _module(ANCIENS / "autoupdate_1_19_30.py", "autoupdate_1_19_30")
    ancien_dossier = tmp_path / "jeu" / "PerceNeigeSimulator"
    ancien_dossier.mkdir(parents=True)
    exe = ancien_dossier / "PerceNeigeSimulator"
    exe.write_text("ancien binaire PyInstaller")
    # paquet du kit tel que build_unix le produit (réduit à sa structure)
    paquet = tmp_path / "neuf" / "PerceNeigeSimulator"
    (paquet / "app").mkdir(parents=True)
    (paquet / "python" / "bin").mkdir(parents=True)
    (paquet / "app" / "VERSION").write_text(V)
    (paquet / "PerceNeigeSimulator").write_text("#!/bin/sh\n")
    (paquet / "PerceNeigeSimulator.sh").write_text("#!/bin/sh\n")
    archive = tmp_path / f"PerceNeigeSimulator-{V}-linux-x86_64.tar.gz"
    with tarfile.open(archive, "w:gz") as t:
        t.add(paquet, arcname="PerceNeigeSimulator")
    somme = hashlib.sha256(archive.read_bytes()).hexdigest()
    sums = tmp_path / "SHA256SUMS"
    sums.write_text(f"{somme}  {archive.name}\n")

    rel = au.ReleaseInfo(tag=f"v{V}", version=V, name="", body="", zipball_url="",
                         html_url="", assets=[
                             au.ReleaseAsset(archive.name, "https://github.com/x/" + archive.name,
                                             archive.stat().st_size),
                             au.ReleaseAsset("SHA256SUMS", "https://github.com/x/SHA256SUMS",
                                             sums.stat().st_size)])

    def faux_telechargement(url, dest, progress=None, max_bytes=None):
        source = archive if url.endswith(".tar.gz") else sums
        Path(dest).write_bytes(source.read_bytes())

    monkeypatch.setattr(au, "_stream_download", faux_telechargement)
    monkeypatch.setattr(au, "installation_linux", lambda: ("dossier", ancien_dossier))
    monkeypatch.setattr(au.sys, "executable", str(exe))
    relance = au.installer_linux(rel)
    assert relance == ancien_dossier / "PerceNeigeSimulator"
    assert (ancien_dossier / "app" / "VERSION").read_text() == V
    assert (ancien_dossier / "PerceNeigeSimulator.sh").exists()


def test_ancienne_maj_appimage_trouve_la_passerelle():
    """L'ancien paquet AppImage cherche « PerceNeigeSimulator…-linux.AppImage »."""
    au = _module(ANCIENS / "autoupdate_1_19_30.py", "autoupdate_1_19_30b")
    noms = [n for n in FICHIERS
            if n.startswith(au.APP_ASSET_PREFIX) and n.endswith("-linux.AppImage")]
    assert noms == [f"PerceNeigeSimulator-{V}-linux.AppImage"]
