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
    """Vrai si l'on tourne depuis le paquet autonome (python embarque a cote).

    Windows : python/python.exe ; macOS et Linux : python/bin/python3. Ne
    tester que python.exe faisait croire aux paquets macOS et Linux qu'ils
    tournaient depuis les sources : aucune mise a jour n'y etait jamais
    recherchee au demarrage.
    """
    python = app_dir().parent / 'python'
    return (python / 'python.exe').exists() or (python / 'bin' / 'python3').exists()


# Seuls ces hotes peuvent livrer du code. L'adresse vient deja d'une reponse
# de GitHub lue en TLS verifie, mais une mise a jour, c'est du code qui
# s'execute : la provenance se verifie deux fois plutot qu'une.
HOTES_AUTORISES = ('github.com', 'objects.githubusercontent.com',
                   'release-assets.githubusercontent.com',
                   'api.github.com')


def _hote_de_confiance(url):
    from urllib.parse import urlparse
    decoupe = urlparse(url)
    if decoupe.scheme != 'https':
        return False
    hote = (decoupe.hostname or '').lower()
    return hote in HOTES_AUTORISES or hote.endswith('.githubusercontent.com')


def _open(url):
    if not _hote_de_confiance(url):
        raise RuntimeError(f"Adresse refusee : {url}")
    req = urllib.request.Request(url, headers={
        'User-Agent': 'updater-kit-windows',
        'Accept': 'application/vnd.github+json',
    })
    try:
        # Cascade de certificats commune (magasin du systeme, racines de la
        # distribution, puis certifi et kit.json « racines_tls ») : voir
        # reporting.ouvrir_url. Le module accompagne toujours celui-ci.
        from reporting import ouvrir_url
    except Exception:
        ouvrir_url = None
    if ouvrir_url is not None:
        return ouvrir_url(req, timeout=TIMEOUT)
    ctx = ssl.create_default_context()
    return urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx)


def plateforme() -> str:
    """'windows', 'macos' ou 'linux' — le suffixe des archives publiees."""
    if sys.platform.startswith('win'):
        return 'windows'
    if sys.platform == 'darwin':
        return 'macos'
    return 'linux'


def architecture() -> str:
    """'arm64' ou 'x86_64' : le suffixe des paquets et archives publies."""
    import platform
    machine = platform.machine().lower()
    return 'arm64' if machine in ('arm64', 'aarch64') else 'x86_64'


# Archives propres a un systeme (kit.json « archive_par_systeme ») : quand
# app/ embarque des binaires (un moteur 3D exporte, par exemple), chaque
# systeme publie la sienne sous ce prefixe DISTINCT de PREFIXE_ARCHIVE :
#     <nom_technique>-maj-<systeme>-<architecture>-<version>.zip
# Distinct, parce que les updaters deja installes prennent la PREMIERE
# archive « -app-*.zip » de la Release : une archive Linux nommee « -app- »
# pouvait passer avant celle de Windows et remplacer le moteur 3D d'un poste
# Windows par celui de Linux. L'archive « -app- » reste celle de Windows.
PREFIXE_SYSTEME = (_kit().get('nom_technique') or 'app') + '-maj-'


SECTIONS = {'en': 'English', 'fr': 'Francais', 'nl': 'Nederlands'}


def notes_dans_la_langue(corps: str, langue: str) -> str:
    """Extrait la section de la langue demandee dans les notes de version.

    Les notes publiees portent les trois langues, chacune sous un titre de
    niveau 2. Sans ce tri, un utilisateur neerlandais lisait les trois d'un
    coup — et avant que les notes ne soient traduites, il lisait du francais.
    Si le decoupage echoue, on rend le texte entier : mieux vaut trop que
    rien.
    """
    if not corps:
        return corps
    titres = {nom: lang for lang, nom in SECTIONS.items()}
    blocs, courant, lignes = {}, None, []
    for ligne in corps.splitlines():
        nu = ligne.strip()
        if nu.startswith('## ') and nu[3:].strip() in titres:
            if courant:
                blocs[courant] = '\n'.join(lignes).strip()
            courant, lignes = titres[nu[3:].strip()], []
        elif courant:
            lignes.append(ligne)
    if courant:
        blocs[courant] = '\n'.join(lignes).strip()
    return blocs.get(langue) or blocs.get('en') or corps


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

    # On cherche l'archive applicative, jamais l'installeur complet.
    # Si la Release en publie une par systeme, on prend celle du notre : poser
    # une archive Windows sur un macOS remplacerait l'application par des
    # binaires inutilisables. Si elle n'en publie qu'une, sans suffixe, elle
    # convient a tous — elle ne contient que du Python pur.
    plate = plateforme()
    if _kit().get('archive_par_systeme'):
        propres = [a for a in data.get('assets', [])
                   if (a.get('name') or '').lower().endswith('.zip')
                   and (a.get('name') or '').lower().startswith(PREFIXE_SYSTEME)]
        for motif in (f'{PREFIXE_SYSTEME}{plate}-{architecture()}-',
                      f'{PREFIXE_SYSTEME}{plate}-'):
            choix = [a for a in propres if (a.get('name') or '').lower().startswith(motif)]
            if choix:
                return _decrire(tag, choix[0], data)
        if plate != 'windows':
            # L'archive commune est celle de Windows : la poser ici
            # remplacerait les binaires de ce systeme par ceux d'un autre.
            log.info("Version %s publiee, mais sans archive pour %s-%s",
                     tag, plate, architecture())
            return None
    candidates = [
        a for a in data.get('assets', [])
        if (a.get('name') or '').lower().startswith(PREFIXE_ARCHIVE)
        and (a.get('name') or '').lower().endswith('.zip')
    ]
    asset = None
    for a in candidates:
        if f'-{plate}.' in (a.get('name') or '').lower():
            asset = a
            break
    if asset is None:
        # Une archive sans suffixe convient a tout le monde : elle ne contient
        # que le dossier `app/`, c'est-a-dire du Python pur. Les dependances
        # compilees vivent dans `python/`, que la mise a jour ne touche pas.
        # C'est aussi ce que publiaient les versions anterieures.
        sans_suffixe = [
            a for a in candidates
            if not any(f'-{p}.' in (a.get('name') or '').lower()
                       for p in ('windows', 'macos', 'linux'))
        ]
        if sans_suffixe:
            asset = sans_suffixe[0]
    if asset is None:
        log.info("Version %s publiee, mais sans archive de mise a jour pour %s",
                 tag, plate)
        return None

    return _decrire(tag, asset, data)


def _decrire(tag, asset, data):
    """La mise a jour retenue, avec de quoi verifier son integrite : taille
    annoncee par l'API et, si la Release le publie, le fichier SHA256SUMS."""
    sommes = [a for a in data.get('assets', []) if (a.get('name') or '') == 'SHA256SUMS']
    return {
        'version': tag,
        'url': asset['browser_download_url'],
        'nom': asset.get('name') or '',
        'size': asset.get('size', 0),
        'sha256sums_url': sommes[0]['browser_download_url'] if sommes else '',
        'notes': data.get('body') or '',
    }


def verifier_integrite(update, archive, taille):
    """Aucun plafond de taille fixe : une archive se juge a ce qu'annonce la
    Release (taille de l'API GitHub, empreinte de SHA256SUMS), pas a un seuil
    grave dans le code — un plafond finit toujours par refuser une vraie
    version plus grosse, sans recours pour une installation deja posee."""
    attendu = int(update.get('size') or 0)
    if attendu and taille != attendu:
        raise RuntimeError(f"Archive tronquee : {taille} octets recus sur {attendu}")
    if not update.get('sha256sums_url') or not update.get('nom'):
        return                       # Release sans SHA256SUMS (anciennes versions)
    import hashlib
    with _open(update['sha256sums_url']) as r:
        sommes = r.read(1 << 20).decode('utf-8', 'replace')
    ligne = [l.split() for l in sommes.splitlines()
             if l.split() and l.split()[-1].lstrip('*') == update['nom']]
    if not ligne:
        return
    h = hashlib.sha256()
    with open(archive, 'rb') as f:
        for bloc in iter(lambda: f.read(1 << 20), b''):
            h.update(bloc)
    if h.hexdigest().lower() != ligne[0][0].lower():
        raise RuntimeError("Empreinte SHA-256 differente de SHA256SUMS : archive refusee")


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
        verifier_integrite(update, archive, done)

        extracted = tmpdir / 'contenu'
        with zipfile.ZipFile(archive) as z:
            # Refuse les chemins qui sortent du dossier d'extraction.
            for member in z.namelist():
                dest = (extracted / member).resolve()
                if not str(dest).startswith(str(extracted.resolve())):
                    raise RuntimeError(f"Archive suspecte : {member}")
            z.extractall(extracted)
            # zipfile ne restitue pas le bit d'execution. Sous Windows cela
            # n'a aucune importance ; ailleurs, le lanceur et l'interpreteur
            # embarque ressortent non executables et l'application ne demarre
            # plus apres sa premiere mise a jour.
            if os.name != 'nt':
                for info in z.infolist():
                    mode = info.external_attr >> 16
                    if mode & 0o111:
                        chemin = extracted / info.filename
                        if chemin.exists():
                            chemin.chmod(chemin.stat().st_mode | 0o111)

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
