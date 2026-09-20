# -*- coding: utf-8 -*-
"""Mise a jour automatique depuis les Releases GitHub.

Point important : on ne telecharge jamais un .exe et on n'en lance jamais un.
On recupere une archive ZIP, on l'extrait *par le code*, et on remplace les
fichiers .py de l'application. Un fichier ecrit par un programme ne recoit pas
la marque « Mark of the Web » que Windows appose sur les telechargements, donc
SmartScreen ne se declenche pas. L'utilisateur ne voit jamais d'avertissement.

Seul le dossier `app/` est remplace : Python, PyQt6 et ffmpeg ne bougent pas,
ce qui reduit une mise a jour a quelques centaines de kilo-octets.
"""
import json
import logging
import os
import shutil
import ssl
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

log = logging.getLogger(__name__)

def _kit() -> dict:
    """Fiche d'identite de l'application, posee a cote du module."""
    try:
        chemin = Path(__file__).resolve().parent / 'kit.json'
        return json.loads(chemin.read_text(encoding='utf-8'))
    except Exception:
        return {}


# Depot d'ou viennent les versions. Il doit etre PUBLIC : l'API GitHub repond
# 404 a qui n'a pas acces au depot, et la mise a jour ne partirait jamais.
REPO = _kit().get('depot_distribution', '')
API_LATEST = f'https://api.github.com/repos/{REPO}/releases/latest'
# Prefixe de l'archive applicative attachee aux Releases.
PREFIXE_ARCHIVE = (_kit().get('nom_technique') or 'app') + '-app-'
TIMEOUT = 20

# Fichiers que l'on ne remplace jamais : ils appartiennent a l'utilisateur.
PROTECTED = set(_kit().get('fichiers_proteges') or [])


def _version_tuple(text):
    """'3.5.4' -> (3, 5, 4). Tolere un 'v' et des suffixes."""
    text = (text or '').strip().lstrip('vV')
    parts = []
    for chunk in text.split('.'):
        digits = ''
        for ch in chunk:
            if ch.isdigit():
                digits += ch
            else:
                break
        parts.append(int(digits) if digits else 0)
    return tuple(parts or [0])


def is_newer(remote, local):
    return _version_tuple(remote) > _version_tuple(local)


def app_dir():
    """Dossier `app/` du paquet installe, ou dossier source en developpement."""
    return Path(__file__).parent.resolve()


def is_packaged():
    """Vrai si l'on tourne depuis le paquet autonome (python embarque a cote)."""
    return (app_dir().parent / 'python' / 'python.exe').exists()


def _open(url):
    req = urllib.request.Request(url, headers={
        'User-Agent': 'updater-kit-windows',
        'Accept': 'application/vnd.github+json',
    })
    ctx = ssl.create_default_context()
    return urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx)


def check(current_version):
    """Interroge GitHub. Renvoie un dict decrivant la mise a jour, ou None."""
    if not current_version:
        # Version courante inconnue : toute comparaison serait fausse, et une
        # comparaison fausse se traduit chez l'utilisateur par une proposition
        # de mise a jour qui revient a chaque demarrage.
        log.info("Version courante inconnue : verification des mises a jour ignoree")
        return None
    if not REPO:
        log.info("Aucun depot de distribution declare : pas de mise a jour")
        return None
    try:
        with _open(API_LATEST) as r:
            data = json.load(r)
    except Exception as e:
        log.info("Verification des mises a jour impossible : %s", e)
        return None

    tag = (data.get('tag_name') or '').lstrip('vV')
    if not tag or not is_newer(tag, current_version):
        return None

    # On cherche l'archive de mise a jour applicative, pas l'installeur complet.
    asset = None
    for a in data.get('assets', []):
        name = (a.get('name') or '').lower()
        if name.startswith(PREFIXE_ARCHIVE) and name.endswith('.zip'):
            asset = a
            break
    if asset is None:
        log.info("Version %s publiee, mais sans archive de mise a jour", tag)
        return None

    return {
        'version': tag,
        'url': asset['browser_download_url'],
        'size': asset.get('size', 0),
        'notes': data.get('body') or '',
    }


def download_and_apply(update, progress=None):
    """Telecharge l'archive et remplace le contenu de `app/`.

    L'ancienne version est mise de cote avant toute ecriture : si l'extraction
    echoue a mi-chemin, on la remet en place plutot que de laisser une
    installation a moitie ecrasee.

    Renvoie True si la mise a jour est posee et qu'un redemarrage suffit.
    """
    target = app_dir()
    tmpdir = Path(tempfile.mkdtemp(prefix='maj-'))
    archive = tmpdir / 'update.zip'

    try:
        with _open(update['url']) as r, open(archive, 'wb') as f:
            total = int(r.headers.get('Content-Length') or update.get('size') or 0)
            done = 0
            while True:
                chunk = r.read(65536)
                if not chunk:
                    break
                f.write(chunk)
                done += len(chunk)
                if progress:
                    progress(done, total)

        extracted = tmpdir / 'contenu'
        with zipfile.ZipFile(archive) as z:
            # Refuse les chemins qui sortent du dossier d'extraction.
            for member in z.namelist():
                dest = (extracted / member).resolve()
                if not str(dest).startswith(str(extracted.resolve())):
                    raise RuntimeError(f"Archive suspecte : {member}")
            z.extractall(extracted)

        # Certaines archives contiennent un dossier racine unique.
        entries = [p for p in extracted.iterdir()]
        if len(entries) == 1 and entries[0].is_dir():
            extracted = entries[0]

        # Garde-fou : une archive tronquee ne doit jamais ecraser une
        # installation qui fonctionne.
        entree = _kit().get('point_entree') or ''
        if entree and not (extracted / entree).exists():
            raise RuntimeError(f"Archive incomplete : {entree} absent")

        backup = tmpdir / 'precedent'
        backup.mkdir()
        replaced = []
        for item in extracted.iterdir():
            if item.name in PROTECTED:
                continue
            dest = target / item.name
            if dest.exists():
                shutil.move(str(dest), str(backup / item.name))
                replaced.append(item.name)
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)

        log.info("Mise a jour %s posee (%d fichiers)", update['version'],
                 len(list(extracted.iterdir())))
        return True

    except Exception as e:
        log.exception("Mise a jour echouee")
        # Tentative de remise en etat
        try:
            backup = tmpdir / 'precedent'
            if backup.exists():
                for item in backup.iterdir():
                    dest = target / item.name
                    if dest.exists():
                        if dest.is_dir():
                            shutil.rmtree(dest, ignore_errors=True)
                        else:
                            dest.unlink(missing_ok=True)
                    shutil.move(str(item), str(dest))
                log.info("Version precedente restauree")
        except Exception:
            log.exception("Restauration impossible")
        raise RuntimeError(str(e))

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def restart():
    """Relance l'application avec l'interpreteur embarque, puis rend la main."""
    try:
        base = app_dir().parent
        pyw = base / 'python' / 'pythonw.exe'
        script = app_dir() / (_kit().get('point_entree') or '')
        if pyw.exists():
            os.spawnv(os.P_NOWAIT, str(pyw), [str(pyw), str(script)])
        else:
            os.spawnv(os.P_NOWAIT, sys.executable, [sys.executable, str(script)])
        return True
    except Exception:
        log.exception("Redemarrage automatique impossible")
        return False
