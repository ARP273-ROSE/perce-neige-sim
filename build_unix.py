#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Construit le paquet macOS ou Linux.

La structure est LA MEME que celle du paquet Windows produit par
`build_package.py` :

    <NomApp>/
        python/     un CPython autonome
        app/        le code de l'application
        <NomApp>.sh (ou le bundle .app sous macOS)

C'est ce qui permet a `updater.py` de fonctionner a l'identique sur les trois
systemes : il ne remplace que le contenu de `app/`, du Python pur, et ne touche
jamais a l'interpreteur ni aux dependances compilees.

L'interpreteur vient de python-build-standalone, l'equivalent pour Unix du
Python « embeddable » de Windows. Dependre du Python du systeme serait plus
simple et plus fragile : sur macOS il peut ne pas etre installe, et sur Linux
sa version varie d'une distribution a l'autre.

Sous Linux, le dossier livre contient aussi `installer.sh` : il installe
dans le profil de l'utilisateur (~/.local/share), sans sudo, et pose l'entree
de menu. Sous macOS, le bundle `.app` se glisse dans Applications.

Usage :
    python3 build_unix.py [--version X.Y.Z]
"""

import argparse
import json
import os
import platform
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KIT = json.loads((ROOT / 'kit.json').read_text(encoding='utf-8'))
NOM = KIT['nom_fichier']
NOM_TECHNIQUE = KIT['nom_technique']
NOM_AFFICHE = KIT.get('nom_affiche', NOM)
POINT_ENTREE = KIT['point_entree']

PY_VERSION = '3.12.14'
PY_BUILD = '20260901'
DIST = ROOT / 'dist'
PKG = DIST / NOM
CACHE = ROOT / '.build_cache'


def _version_courante():
    return (ROOT / KIT.get('fichier_version', 'VERSION')).read_text().strip()


def log(msg):
    print(f'  {msg}', flush=True)


def cible_python():
    """Le triplet python-build-standalone de la machine courante."""
    machine = platform.machine().lower()
    if sys.platform == 'darwin':
        return 'aarch64-apple-darwin' if machine in ('arm64', 'aarch64') else 'x86_64-apple-darwin'
    if machine in ('aarch64', 'arm64'):
        return 'aarch64-unknown-linux-gnu'
    return 'x86_64-unknown-linux-gnu'


def plateforme():
    return 'macos' if sys.platform == 'darwin' else 'linux'


def architecture():
    """'arm64' ou 'x86_64' : le suffixe des paquets publies. Le Python
    embarque est propre a une architecture, le mauvais ne demarre pas."""
    machine = platform.machine().lower()
    return 'arm64' if machine in ('arm64', 'aarch64') else 'x86_64'


#: icone du programme (PNG carre), relative a la racine du depot. Facultatif :
#: sans elle, le bundle et l'entree de menu fonctionnent, sans icone.
ICONE_PNG = KIT.get('icone_png') or ''
ICONE_GRANDE = KIT.get('icone_grande') or ICONE_PNG

#: entree de menu Linux : noms et description dans les deux langues
#: (une cle vide de l'amorce vaut une cle absente)
NOM_FR = KIT.get('nom_affiche_fr') or NOM_AFFICHE
NOM_EN = KIT.get('nom_affiche_en') or NOM_AFFICHE
DESCRIPTION_FR = KIT.get('description_fr') or ''
DESCRIPTION_EN = KIT.get('description_en') or DESCRIPTION_FR
CATEGORIES = KIT.get('categories_linux') or 'Utility;'


def regle_pour_ce_systeme(regle) -> bool:
    """Vrai si la regle de copie vaut pour le systeme construit."""
    systemes = regle.get('systemes') or []
    if not systemes:
        return True
    return plateforme() in systemes or f'{plateforme()}-{architecture()}' in systemes


def deployer_zip(archive: Path, dossier: Path):
    """Deploie une archive .zip en gardant les droits d'execution et les
    liens symboliques (zipfile seul les perd : une application macOS ou un
    moteur Linux ressortaient non executables)."""
    dossier.mkdir(parents=True, exist_ok=True)
    base = dossier.resolve()
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            dest = (dossier / info.filename).resolve()
            if not str(dest).startswith(str(base)):
                raise RuntimeError(f'Archive suspecte : {info.filename}')
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                dest.parent.mkdir(parents=True, exist_ok=True)
                if dest.exists() or dest.is_symlink():
                    dest.unlink()
                os.symlink(z.read(info).decode('utf-8'), dest)
                continue
            z.extract(info, dossier)
            if mode & 0o777 and not info.is_dir():
                dest.chmod(mode & 0o777)
    log(f'archive deployee : {archive.name}')


def fetch(url, dest):
    if dest.exists() and dest.stat().st_size > 0:
        log(f'deja en cache : {dest.name}')
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f'telechargement : {url}')
    with urllib.request.urlopen(url, timeout=180) as r, open(dest, 'wb') as f:
        shutil.copyfileobj(r, f)
    return dest


def step_python():
    """Pose un CPython autonome dans <PKG>/python."""
    cible = cible_python()
    # Variante « stripped » : sans symboles de debogage. Le binaire python3.12
    # de Linux pesait 102 Mo (39 Mo compresses), et `strip` ne peut pas s'y
    # appliquer sans le casser (« undefined symbol ») — seule libpython l'est.
    nom = f'cpython-{PY_VERSION}+{PY_BUILD}-{cible}-install_only_stripped.tar.gz'
    url = (f'https://github.com/astral-sh/python-build-standalone/releases/'
           f'download/{PY_BUILD}/{nom}')
    archive = fetch(url, CACHE / nom)

    cible_dir = PKG / 'python'
    if cible_dir.exists():
        shutil.rmtree(cible_dir)
    tmp = DIST / '_py'
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    log('extraction de l\'interpreteur')
    with tarfile.open(archive) as t:
        # L'archive contient un unique dossier « python/ ».
        for membre in t.getmembers():
            if os.path.isabs(membre.name) or '..' in Path(membre.name).parts:
                raise RuntimeError(f'Archive suspecte : {membre.name}')
        # filtre « data » quand il existe (3.12+) : refuse liens et chemins
        # hors du dossier, et fait taire l'avertissement de Python 3.14
        if hasattr(tarfile, 'data_filter'):
            t.extractall(tmp, filter='data')
        else:
            t.extractall(tmp)
    shutil.move(str(tmp / 'python'), str(cible_dir))
    shutil.rmtree(tmp, ignore_errors=True)

    exe = cible_dir / 'bin' / 'python3'
    if not exe.exists():
        raise RuntimeError(f'Interpreteur introuvable : {exe}')
    sortie = subprocess.run([str(exe), '-V'], capture_output=True, text=True)
    log(f'interpreteur : {sortie.stdout.strip() or sortie.stderr.strip()}')
    return exe


def step_deps(exe):
    reqs = ROOT / (KIT.get('requirements') or 'requirements.txt')
    if not reqs.exists():
        log('aucun requirements.txt')
        return
    log(f'installation depuis {reqs.name}')
    subprocess.run([str(exe), '-m', 'pip', 'install', '-q',
                    '--no-warn-script-location', '-r', str(reqs)], check=True)


def step_app():
    """Copie le code dans <PKG>/app."""
    app = PKG / 'app'
    if app.exists():
        shutil.rmtree(app)
    app.mkdir(parents=True)
    for module in KIT.get('modules', []):
        src = ROOT / module
        if src.exists():
            shutil.copy2(src, app / src.name)
    for paquet in KIT.get('paquets', []):
        src = ROOT / paquet
        if src.exists():
            shutil.copytree(src, app / src.name,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    for actif in KIT.get('assets', []):
        src = ROOT / actif
        if not src.exists():
            continue
        if src.is_dir():
            shutil.copytree(src, app / src.name,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        else:
            shutil.copy2(src, app / src.name)
    # Copies selectives (kit.json « copies »), comme build_package.py sous
    # Windows : seuls les fichiers retenus par les motifs, a la meme place
    # relative. Sans elles, ce que l'application ouvre depuis un sous-dossier
    # (le manuel dans docs/, par exemple) manquait aux paquets macOS et Linux.
    # « systemes » : regle reservee a certains systemes (« linux »,
    # « linux-arm64 », « macos »...) ; « decompresser » : une archive .zip
    # retenue est deployee a sa place (voir build_package.py).
    for regle in KIT.get('copies', []):
        if not regle_pour_ce_systeme(regle):
            continue
        source = ROOT / regle['de']
        cible = app / regle.get('vers', regle['de'])
        for motif in regle.get('motifs', ['**/*']):
            for fichier in source.glob(motif):
                if fichier.is_file():
                    destination = cible / fichier.relative_to(source)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    if regle.get('decompresser') and fichier.suffix.lower() == '.zip':
                        deployer_zip(fichier, destination.parent)
                    else:
                        shutil.copy2(fichier, destination)
                        if regle.get('executable'):
                            destination.chmod(destination.stat().st_mode | 0o755)
    # kit.json dit a updater.py ou chercher les versions : sans lui, le depot
    # de distribution est vide et aucune mise a jour n'est jamais trouvee.
    # build_package.py (Windows) le copiait deja ; ici, il manquait.
    shutil.copy2(ROOT / 'kit.json', app / 'kit.json')
    log(f'application copiee ({sum(1 for _ in app.rglob("*"))} entrees)')


# Dossier reel du lanceur, liens symboliques suivis (~/.local/bin/app ->
# .../App.sh, et lien de lien) : `dirname "$0"` seul donnait le dossier du
# LIEN, et l'application ne trouvait plus python/ ni app/. Sans `readlink -f`,
# absent de macOS avant 12.3 : `readlink` simple, en boucle (Coupole, Tutti).
SUIVRE_LIENS = (
    'CIBLE="$0"\n'
    'while [ -L "$CIBLE" ]; do\n'
    '    LIEN=$(readlink "$CIBLE")\n'
    '    case "$LIEN" in\n'
    '        /*) CIBLE="$LIEN" ;;\n'
    '        *) CIBLE="$(dirname "$CIBLE")/$LIEN" ;;\n'
    '    esac\n'
    'done\n')


def texte_lanceur(relatif: str = '.') -> str:
    """Le lanceur shell ; `relatif` : python/ et app/ vus du dossier du lanceur."""
    ici = ('$(cd "$(dirname "$CIBLE")" && pwd)' if relatif == '.'
           else '$(cd "$(dirname "$CIBLE")/%s" && pwd)' % relatif)
    return ('#!/bin/sh\n'
            '# Lanceur : tout est relatif au dossier du paquet, rien n\'est\n'
            '# installe dans le systeme.\n'
            + SUIVRE_LIENS +
            f'ICI={ici}\n'
            f'exec "$ICI/python/bin/python3" "$ICI/app/{POINT_ENTREE}" "$@"\n')


def step_lanceur():
    """Un script shell, et sous macOS le bundle .app qui va autour."""
    sh = PKG / f'{NOM}.sh'
    sh.write_text(texte_lanceur(), encoding='utf-8')
    sh.chmod(sh.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    log(f'lanceur : {sh.name}')
    if KIT.get('passerelle_pyinstaller') and plateforme() == 'linux':
        # L'ancien paquet Linux PyInstaller en dossier se mettait a jour en
        # remplacant son dossier par celui de l'archive .tar.gz, a condition
        # d'y trouver un executable <Nom> (sans extension), qu'il relancait.
        # Ce second lanceur fait passer ces installations au paquet du kit.
        nu = PKG / NOM
        nu.write_text(texte_lanceur(), encoding='utf-8')
        nu.chmod(0o755)
        log(f'lanceur des anciens paquets : {nu.name}')

    if plateforme() == 'macos':
        # Un bundle .app : c'est ce qu'un utilisateur macOS attend de pouvoir
        # glisser dans Applications. Il enveloppe le paquet tel quel, ce qui
        # laisse `app/` a la meme place relative et l'updater inchange.
        bundle = DIST / f'{NOM}.app'
        if bundle.exists():
            shutil.rmtree(bundle)
        macos = bundle / 'Contents' / 'MacOS'
        resources = bundle / 'Contents' / 'Resources'
        macos.mkdir(parents=True)
        resources.mkdir(parents=True)
        icone = _icone_macos(resources)
        (bundle / 'Contents' / 'Info.plist').write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict>\n'
            f'  <key>CFBundleName</key><string>{NOM}</string>\n'
            f'  <key>CFBundleDisplayName</key><string>{NOM_AFFICHE}</string>\n'
            f'  <key>CFBundleIdentifier</key><string>io.github.arp273-rose.{NOM_TECHNIQUE}</string>\n'
            f'  <key>CFBundleExecutable</key><string>{NOM}</string>\n'
            f'  <key>CFBundleVersion</key><string>{_version_courante()}</string>\n'
            f'  <key>CFBundleShortVersionString</key><string>{_version_courante()}</string>\n'
            + (f'  <key>CFBundleIconFile</key><string>{icone}</string>\n'
               if icone else '') +
            '  <key>CFBundlePackageType</key><string>APPL</string>\n'
            '  <key>CFBundleDevelopmentRegion</key><string>en</string>\n'
            '  <key>CFBundleLocalizations</key><array><string>en</string>'
            '<string>fr</string></array>\n'
            '  <key>NSHighResolutionCapable</key><true/>\n'
            '  <key>LSMinimumSystemVersion</key><string>11.0</string>\n'
            '</dict></plist>\n', encoding='utf-8')
        lanceur = macos / NOM
        lanceur.write_text(texte_lanceur('../Resources'), encoding='utf-8')
        lanceur.chmod(0o755)
        for entree in ('python', 'app'):
            shutil.move(str(PKG / entree), str(resources / entree))
        shutil.rmtree(PKG, ignore_errors=True)
        log(f'bundle : {bundle.name}')

    if plateforme() == 'linux':
        # Modele d'entree de menu, rempli par installer.sh avec le dossier
        # d'installation reel (une entree .desktop exige des chemins absolus)
        (PKG / f'{NOM_TECHNIQUE}.desktop').write_text(
            '[Desktop Entry]\n'
            'Type=Application\n'
            f'Name={NOM_AFFICHE}\n'
            f'Name[fr]={NOM_FR}\n'
            f'Name[en]={NOM_EN}\n'
            + (f'Comment={DESCRIPTION_EN}\n' if DESCRIPTION_EN else '')
            + (f'Comment[fr]={DESCRIPTION_FR}\n' if DESCRIPTION_FR else '')
            + 'Exec="__ICI__/' + NOM + '.sh"\n'
            + ('Icon=__ICI__/app/' + ICONE_PNG + '\n' if ICONE_PNG else '')
            + 'Terminal=false\n'
            f'Categories={CATEGORIES}\n',
            encoding='utf-8')
        installeur = PKG / 'installer.sh'
        installeur.write_text(INSTALLER_SH.replace('__NOM__', NOM)
                              .replace('__TECH__', NOM_TECHNIQUE),
                              encoding='utf-8')
        installeur.chmod(0o755)
        log('installer.sh et entree de menu')


#: Installation sous Linux dans le profil de l'utilisateur : ni sudo, ni
#: gestionnaire de paquets, comme l'installeur Windows. Les messages sont
#: dans les deux langues, la locale n'etant pas forcement fiable en console.
INSTALLER_SH = r"""#!/bin/sh
# Installe __NOM__ dans le profil de l'utilisateur, sans sudo.
# Installs __NOM__ into the user's profile, without sudo.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
NOM_APP=__NOM__
TECH=__TECH__
DONNEES="${XDG_DATA_HOME:-$HOME/.local/share}"
CIBLE="$DONNEES/$TECH"
echo "Installation dans / Installing into: $CIBLE"
mkdir -p "$CIBLE"
# Les donnees de l'utilisateur (reglages, rapports) vivent ailleurs, dans
# $DONNEES/__NOM__ : elles ne sont jamais touchees ici.
rm -rf "$CIBLE/python" "$CIBLE/app"
cp -R "$ICI/python" "$ICI/app" "$ICI/$NOM_APP.sh" "$CIBLE/"
chmod +x "$CIBLE/$NOM_APP.sh" "$CIBLE/python/bin/"python3*
APPS="$DONNEES/applications"
mkdir -p "$APPS"
sed -e "s|__ICI__|$CIBLE|g" "$ICI/$TECH.desktop" > "$APPS/$TECH.desktop"
chmod +x "$APPS/$TECH.desktop"
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APPS" >/dev/null 2>&1 || true
echo "Termine. Lancez « $NOM_APP » depuis le menu des applications, ou :"
echo "Done. Start \"$NOM_APP\" from the applications menu, or run:"
echo "  $CIBLE/$NOM_APP.sh"
"""


def _icone_macos(resources: Path) -> str:
    """Construit l'icone .icns avec les outils du systeme (sips, iconutil).
    Facultatif : sans icone, le bundle fonctionne tout de meme."""
    # Une icone .icns fournie (kit.json « icone_icns », produite depuis la
    # meme source SVG que les autres) l'emporte : rien a reconstruire.
    icns = KIT.get('icone_icns') or ''
    if icns and (ROOT / icns).is_file():
        shutil.copy2(ROOT / icns, resources / 'icone.icns')
        log('icone macOS : ' + icns)
        return 'icone.icns'
    src = ROOT / ICONE_GRANDE if ICONE_GRANDE else None
    if src is None or not src.exists() or not shutil.which('iconutil') or not shutil.which('sips'):
        return ''
    jeu = DIST / 'icone.iconset'
    shutil.rmtree(jeu, ignore_errors=True)
    jeu.mkdir(parents=True)
    try:
        for taille in (16, 32, 128, 256, 512):
            for echelle in (1, 2):
                px = taille * echelle
                if px > 1024:
                    continue
                nom = f'icon_{taille}x{taille}{"@2x" if echelle == 2 else ""}.png'
                subprocess.run(['sips', '-z', str(px), str(px), str(src),
                                '--out', str(jeu / nom)], check=True,
                               capture_output=True)
        subprocess.run(['iconutil', '-c', 'icns', str(jeu), '-o',
                        str(resources / 'icone.icns')], check=True,
                       capture_output=True)
        log('icone macOS : icone.icns')
        return 'icone.icns'
    except (subprocess.SubprocessError, OSError) as exc:
        log(f'icone macOS non construite ({exc}) : bundle sans icone')
        return ''
    finally:
        shutil.rmtree(jeu, ignore_errors=True)


def racine_paquet() -> Path:
    """Ou vivent `python/` et `app/` : le paquet, ou les Resources du bundle."""
    bundle = DIST / f'{NOM}.app' / 'Contents' / 'Resources'
    return bundle if bundle.exists() else PKG


#: Modules Qt retires, comme dans build_package.py (paquet Windows) : une
#: application QtWidgets ne charge ni QML, ni Quick, ni WebEngine... kit.json
#: « qt_elaguer » a false les garde tous (QtWebEngine d'une liseuse).
QT_ELAGUES = (
    'Qt6Quick', 'Qt6Qml', 'Qt6WebEngine', 'Qt6WebView', 'Qt6WebSockets',
    'Qt6WebChannel', 'Qt6Charts', 'Qt6DataVisualization', 'Qt6Designer',
    'Qt6Help', 'Qt6Test', 'Qt6Bluetooth', 'Qt6Nfc', 'Qt6SerialPort',
    'Qt6SerialBus', 'Qt6Sensors', 'Qt63D', 'Qt6Pdf', 'Qt6Sql',
    'Qt6RemoteObjects', 'Qt6Scxml', 'Qt6StateMachine', 'Qt6SpatialAudio',
    'Qt6TextToSpeech', 'Qt6VirtualKeyboard', 'Qt6Location', 'Qt6Positioning',
    'Qt6ShaderTools', 'Qt6LabsAnimation', 'Qt6Quick3D',
)
QT_GREFFONS_ELAGUES = (
    'sqldrivers', 'sceneparsers', 'assetimporters', 'renderers', 'qmlls',
    'qmllint', 'geometryloaders', 'position', 'webview', 'designer',
    'texttospeech', 'virtualkeyboard', 'sensors', 'canbus', 'help',
)
PYQT_ELAGUES = (
    'QtQml', 'QtQuick', 'QtQuick3D', 'QtQuickWidgets', 'QtWebEngineCore',
    'QtWebEngineWidgets', 'QtWebEngineQuick', 'QtWebChannel', 'QtWebSockets',
    'QtCharts', 'QtDataVisualization', 'QtDesigner', 'QtHelp', 'QtTest',
    'QtBluetooth', 'QtNfc', 'QtSerialPort', 'QtSensors', 'Qt3DCore',
    'Qt3DRender', 'Qt3DInput', 'Qt3DLogic', 'Qt3DAnimation', 'Qt3DExtras',
    'QtPdf', 'QtPdfWidgets', 'QtSql', 'QtRemoteObjects', 'QtScxml',
    'QtStateMachine', 'QtSpatialAudio', 'QtTextToSpeech', 'QtPositioning',
    'QtLocation', 'QtMultimediaWidgets',
)


def _elaguer_qt(site: Path):
    """Le meme elagage que sous Windows : Linux (libQt6Quick.so.6) et macOS
    (QtQuick.framework)."""
    pyqt = site / 'PyQt6'
    qt = pyqt / 'Qt6'
    if not qt.is_dir():
        return
    prefixes = QT_ELAGUES + tuple(p.replace('Qt6', 'Qt', 1) for p in QT_ELAGUES)
    for d in (qt / 'lib', qt / 'bin', qt / 'libexec'):
        if not d.is_dir():
            continue
        for f in list(d.iterdir()):
            nom = f.name[3:] if f.name.startswith('lib') else f.name
            if any(nom.startswith(p) for p in prefixes):
                if f.is_dir() and not f.is_symlink():
                    shutil.rmtree(f, ignore_errors=True)
                else:
                    f.unlink(missing_ok=True)
    for nom in QT_GREFFONS_ELAGUES:
        shutil.rmtree(qt / 'plugins' / nom, ignore_errors=True)
    shutil.rmtree(qt / 'qml', ignore_errors=True)
    for nom in PYQT_ELAGUES:
        for f in pyqt.glob(nom + '.*'):
            f.unlink(missing_ok=True)
    tr = qt / 'translations'
    if tr.is_dir():
        for f in tr.iterdir():
            if f.is_file() and not any(tag in f.name for tag in ('_fr', '_en')):
                f.unlink(missing_ok=True)
    shutil.rmtree(pyqt / 'bindings', ignore_errors=True)
    shutil.rmtree(qt / 'include', ignore_errors=True)


def step_elaguer():
    """Retire ce qui ne sert pas a l'execution."""
    base = racine_paquet()
    avant = sum(f.stat().st_size for f in base.rglob('*') if f.is_file())
    for chemin in list(base.rglob('__pycache__')):
        if chemin.is_dir():
            shutil.rmtree(chemin, ignore_errors=True)
    # Bibliotheque standard seulement : un dossier « tests » de site-packages
    # peut etre un module importe par son paquet (astropy importe
    # astropy.tests a son chargement ; le retirer cassait l'application).
    for stdlib in (base / 'python' / 'lib').glob('python3*'):
        for nom in ('test', 'idlelib', 'tkinter', 'turtledemo', 'lib2to3',
                    'ensurepip'):
            shutil.rmtree(stdlib / nom, ignore_errors=True)
        site = stdlib / 'site-packages'
        if KIT.get('qt_elaguer', True) is not False:
            _elaguer_qt(site)
        # pip n'a plus rien a installer une fois le paquet construit
        for f in list(site.glob('pip')) + list(site.glob('pip-*.dist-info')):
            shutil.rmtree(f, ignore_errors=True)
        # Tests de numpy : inutiles a l'execution, comme sous Windows.
        numpy = stdlib / 'site-packages' / 'numpy'
        if numpy.is_dir():
            for chemin in list(numpy.rglob('tests')):
                if chemin.is_dir():
                    shutil.rmtree(chemin, ignore_errors=True)
    for chemin in list(base.rglob('*.pyc')):
        chemin.unlink(missing_ok=True)
    # Tcl/Tk (tkinter est deja retire) et lanceurs pip
    for motif in ('lib/tcl*', 'lib/tk*', 'lib/libtcl*', 'lib/libtk*', 'lib/itcl*',
                  'lib/thread*', 'bin/pip*', 'bin/idle*', 'bin/2to3*'):
        for f in (base / 'python').glob(motif):
            if f.is_dir() and not f.is_symlink():
                shutil.rmtree(f, ignore_errors=True)
            else:
                f.unlink(missing_ok=True)
    # Sous Linux, libpython de python-build-standalone garde ses symboles de
    # debogage : 219 Mo, dont l'essentiel ne sert qu'a un debogueur. On ne
    # retire QUE ceux-la (--strip-debug), jamais la table des symboles
    # dynamiques dont depend le chargement des modules compiles.
    if plateforme() == 'linux' and shutil.which('strip'):
        for lib in (base / 'python' / 'lib').glob('libpython*.so*'):
            if lib.is_file() and not lib.is_symlink():
                subprocess.run(['strip', '--strip-debug', str(lib)], check=False)
    apres = sum(f.stat().st_size for f in base.rglob('*') if f.is_file())
    log(f'elagage : {avant/1e6:.0f} Mo -> {apres/1e6:.0f} Mo')


def step_verifier(version):
    """L'application doit au moins s'importer avec l'interpreteur embarque."""
    base = racine_paquet()
    exe = base / 'python' / 'bin' / 'python3'
    modules = KIT.get('verification_import', [])
    if not modules:
        return
    code = 'import sys; sys.path.insert(0, "app")\n' + \
           '\n'.join(f'import {m}' for m in modules) + '\nprint("ok")'
    # -B : sans cela la verification recree des .pyc dans app/ — apres
    # l'elagage, qui les avait retires — et ils partent dans le paquet.
    r = subprocess.run([str(exe), '-B', '-c', code], cwd=base,
                       capture_output=True, text=True,
                       env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
    if r.returncode != 0:
        raise RuntimeError('Le paquet ne s\'importe pas :\n' + r.stderr[-2000:])
    log('verification d\'import : ok')
    # La mise a jour doit savoir ou chercher, et reconnaitre le paquet.
    controle = ('import sys; sys.path.insert(0, "app"); import updater; '
                'assert updater.REPO, "depot de distribution vide"; '
                'assert updater.is_packaged(), "paquet non reconnu"; print("ok")')
    r = subprocess.run([str(exe), '-B', '-c', controle], cwd=base, capture_output=True, text=True,
                       env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
    if r.returncode != 0:
        raise RuntimeError('Mise a jour inoperante dans le paquet :\n' + r.stderr[-2000:])
    log('verification de la mise a jour : ok')
    # Le paquet doit annoncer la version qu'on publie : sinon il proposerait
    # sans fin une mise a jour deja installee.
    vue = (base / 'app' / KIT.get('fichier_version', 'VERSION')).read_text(
        encoding='utf-8').strip()
    if vue != version:
        raise RuntimeError(f'Le paquet annonce {vue!r}, le tag dit {version!r}')
    log(f'version annoncee : {vue}')


def step_archive(version):
    """L'archive applicative — le contenu de app/, ce que l'updater telecharge."""
    # kit.json « archive_par_systeme » : app/ embarque des binaires propres a
    # ce systeme, l'archive porte son nom (prefixe distinct, cf. updater.py)
    if KIT.get('archive_par_systeme'):
        nom = f'{NOM_TECHNIQUE}-maj-{plateforme()}-{architecture()}-{version}.zip'
    else:
        nom = f'{NOM_TECHNIQUE}-app-{version}.zip'
    sortie = ROOT / nom
    if sortie.exists():
        sortie.unlink()
    app = racine_paquet() / 'app'
    # ce qui appartient a l'utilisateur ne part jamais dans l'archive
    exclus = set(KIT.get('exclus_de_la_maj', []) or []) | set(KIT.get('fichiers_proteges') or [])
    with zipfile.ZipFile(sortie, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(app.rglob('*')):
            rel = f.relative_to(app)
            if rel.parts and rel.parts[0] in exclus:
                continue
            if '__pycache__' in rel.parts:
                continue
            if f.is_file():
                info = zipfile.ZipInfo(str(rel))
                info.external_attr = (f.stat().st_mode & 0xFFFF) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, f.read_bytes())
    log(f'archive applicative : {nom} ({sortie.stat().st_size/1e6:.1f} Mo)')
    return sortie


def step_paquet_complet(version):
    """Le paquet complet, a telecharger la premiere fois.

    Linux : une archive .tar.gz (dossier + installer.sh). macOS : rien ici,
    l'image disque .dmg est faite par le workflow avec hdiutil.
    """
    if plateforme() == 'macos':
        return None
    nom = f'{NOM}-{version}-linux-{architecture()}.tar.gz'
    sortie = ROOT / nom
    if sortie.exists():
        sortie.unlink()
    with tarfile.open(sortie, 'w:gz') as t:
        t.add(PKG, arcname=NOM)
    log(f'paquet complet : {nom} ({sortie.stat().st_size/1e6:.0f} Mo)')
    if KIT.get('passerelle_pyinstaller') and architecture() == 'x86_64':
        step_passerelle(version, sortie)
    return sortie


#: Passerelle des anciens paquets Linux PyInstaller (kit.json
#: « passerelle_pyinstaller ») : leur mise a jour automatique telechargeait
#: « <Nom>-X-linux.AppImage » et le posait A LA PLACE de l'AppImage installee.
#: Ce fichier-ci porte ce nom mais n'est pas une AppImage : c'est un script
#: auto-extractible. Lance (par l'ancienne application qui se relance, puis a
#: chaque ouverture depuis l'ancien emplacement), il installe le paquet du kit
#: dans le profil comme installer.sh s'il est absent ou plus ancien, puis
#: lance la copie installee — qui se met a jour seule ensuite.
PASSERELLE_SH = r"""#!/bin/sh
# __NOM__ __VERSION__ : passerelle de l'ancien paquet AppImage vers le paquet
# installe dans le profil (mise a jour automatique). Bridge from the former
# AppImage to the self-updating package installed in the user's profile.
VERSION=__VERSION__
NOM_APP=__NOM__
TECH=__TECH__
DONNEES="${XDG_DATA_HOME:-$HOME/.local/share}"
CIBLE="$DONNEES/$TECH"
INSTALLEE=""
if [ -f "$CIBLE/app/__FICHIER_VERSION__" ]; then
    INSTALLEE=$(tr -d ' 
' < "$CIBLE/app/__FICHIER_VERSION__")
fi
PLUS_RECENTE=$(printf '%s
%s
' "$VERSION" "$INSTALLEE" | sort -V | tail -n 1)
if [ ! -x "$CIBLE/$NOM_APP.sh" ] || [ -z "$INSTALLEE" ] ||    { [ "$PLUS_RECENTE" = "$VERSION" ] && [ "$VERSION" != "$INSTALLEE" ]; }; then
    TMP=$(mktemp -d) || exit 1
    LIGNE=$(awk '/^__ARCHIVE_SUIT__$/ { print NR + 1; exit 0 }' "$0")
    if ! tail -n +"$LIGNE" "$0" | tar xzf - -C "$TMP" ||        ! sh "$TMP/$NOM_APP/installer.sh" >/dev/null; then
        rm -rf "$TMP"
        echo "Installation impossible / Installation failed: $CIBLE" >&2
        exit 1
    fi
    rm -rf "$TMP"
fi
exec "$CIBLE/$NOM_APP.sh" "$@"
__ARCHIVE_SUIT__
"""


def step_passerelle(version, archive: Path):
    nom = f'{NOM}-{version}-linux.AppImage'
    sortie = ROOT / nom
    texte = (PASSERELLE_SH.replace('__NOM__', NOM).replace('__TECH__', NOM_TECHNIQUE)
             .replace('__VERSION__', version)
             .replace('__FICHIER_VERSION__', KIT.get('fichier_version', 'VERSION')))
    with open(sortie, 'wb') as f:
        f.write(texte.encode('utf-8'))
        with open(archive, 'rb') as a:
            shutil.copyfileobj(a, f)
    sortie.chmod(0o755)
    log(f'passerelle des anciens paquets : {nom}')
    return sortie


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', default=None)
    args = ap.parse_args()
    version = args.version or (ROOT / KIT.get('fichier_version', 'VERSION')).read_text().strip()

    print(f'== {NOM_AFFICHE} {version} — paquet {plateforme()} ==')
    if PKG.exists():
        shutil.rmtree(PKG)
    PKG.mkdir(parents=True)

    exe = step_python()
    step_deps(exe)
    step_app()
    step_lanceur()
    step_elaguer()
    step_verifier(version)
    step_archive(version)
    step_paquet_complet(version)
    print('== termine ==')


if __name__ == '__main__':
    main()
