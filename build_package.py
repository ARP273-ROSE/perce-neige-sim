# -*- coding: utf-8 -*-
"""Construit le paquet Windows autonome d'une application du kit.

Rien ici n'est propre a une application : tout ce qui varie est decrit dans
`kit.json`, a la racine du depot. Ce fichier est donc strictement identique
d'un projet a l'autre, et une correction se propage en le recopiant.

Le paquet n'est pas un executable compile : il embarque la distribution
« embeddable » officielle de Python, dont le python.exe est signe par la
Python Software Foundation. Un antivirus ne le confond donc pas avec un
logiciel malveillant, contrairement a un binaire produit par PyInstaller —
qui se fait regulierement mettre en quarantaine des mois apres l'installation.

Resultat : dist/<NomApp>/ contenant
    python/     interpreteur + dependances
    app/        le code de l'application
    bin/        binaires supplementaires eventuels (ffmpeg...)
    <NomApp>.bat et Diagnostic.bat

Usage :
    python build_package.py [--out DOSSIER] [--no-prune]
"""
import argparse
import compileall
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
# Le dossier de sortie est volontairement separable du depot : Windows refuse
# d'executer un .exe depuis un partage reseau, et ce depot vit sur un NAS.

def lire_kit():
    chemin = ROOT / 'kit.json'
    if not chemin.exists():
        raise SystemExit("kit.json introuvable : impossible de savoir quoi construire.")
    return json.loads(chemin.read_text(encoding='utf-8'))


KIT = lire_kit()
NOM = KIT['nom_fichier']              # sans accent ni espace : sert aux chemins
POINT_ENTREE = KIT['point_entree']

DIST = ROOT / 'dist'
PKG = DIST / NOM
CACHE = ROOT / '.build_cache'

PY_VERSION = '3.12.10'
PY_EMBED_URL = (f'https://www.python.org/ftp/python/{PY_VERSION}/'
                f'python-{PY_VERSION}-embed-amd64.zip')
GET_PIP_URL = 'https://bootstrap.pypa.io/get-pip.py'

# Ce qui entre dans le paquet est decrit explicitement plutot que copie en
# bloc : un depot contient aussi des scripts de maintenance, des rapports et
# des bases de travail qui n'ont rien a faire chez un utilisateur.
APP_MODULES = KIT.get('modules', [])       # fichiers .py a la racine
APP_PAQUETS = KIT.get('paquets', [])       # dossiers entiers (core/, gui/...)
APP_ASSETS = KIT.get('assets', [])         # icones, VERSION, donnees...
PIP_PAQUETS = KIT.get('pip', [])           # a defaut de requirements.txt
BINAIRES = KIT.get('binaires', [])         # [{'url':..., 'fichiers':[...]}]
COPIES = KIT.get('copies', [])             # dossiers copies par motifs

# Modules Qt inutilises : l'application n'importe que QtCore, QtGui,
# QtWidgets et QtMultimedia. Tout le reste est du poids mort.
QT_PRUNE_PREFIXES = [
    'Qt6Quick', 'Qt6Qml', 'Qt6WebEngine', 'Qt6WebView', 'Qt6WebSockets',
    'Qt6WebChannel', 'Qt6Charts', 'Qt6DataVisualization', 'Qt6Designer',
    'Qt6Help', 'Qt6Test', 'Qt6Bluetooth', 'Qt6Nfc', 'Qt6SerialPort',
    'Qt6SerialBus', 'Qt6Sensors', 'Qt63D', 'Qt6Pdf', 'Qt6Sql',
    'Qt6RemoteObjects', 'Qt6Scxml', 'Qt6StateMachine', 'Qt6SpatialAudio',
    'Qt6TextToSpeech', 'Qt6VirtualKeyboard', 'Qt6Location', 'Qt6Positioning',
    'Qt6ShaderTools', 'Qt6LabsAnimation', 'Qt6Quick3D',
]
QT_PRUNE_PLUGIN_DIRS = [
    'sqldrivers', 'sceneparsers', 'assetimporters', 'renderers', 'qmlls',
    'qmllint', 'geometryloaders', 'position', 'webview', 'designer',
    'texttospeech', 'virtualkeyboard', 'sensors', 'canbus', 'help',
]
PYQT_PRUNE_MODULES = [
    'QtQml', 'QtQuick', 'QtQuick3D', 'QtQuickWidgets', 'QtWebEngineCore',
    'QtWebEngineWidgets', 'QtWebEngineQuick', 'QtWebChannel', 'QtWebSockets',
    'QtCharts', 'QtDataVisualization', 'QtDesigner', 'QtHelp', 'QtTest',
    'QtBluetooth', 'QtNfc', 'QtSerialPort', 'QtSensors', 'Qt3DCore',
    'Qt3DRender', 'Qt3DInput', 'Qt3DLogic', 'Qt3DAnimation', 'Qt3DExtras',
    'QtPdf', 'QtPdfWidgets', 'QtSql', 'QtRemoteObjects', 'QtScxml',
    'QtStateMachine', 'QtSpatialAudio', 'QtTextToSpeech', 'QtPositioning',
    'QtLocation', 'QtMultimediaWidgets',
]


def log(msg):
    print(f'  {msg}', flush=True)


def fetch(url, dest):
    """Telecharge une seule fois, puis reutilise le cache."""
    CACHE.mkdir(exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        log(f'deja en cache : {dest.name}')
        return dest
    log(f'telechargement : {url}')
    req = urllib.request.Request(url, headers={'User-Agent': 'kit-windows-build'})
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, 'wb') as f:
        shutil.copyfileobj(r, f)
    log(f'recu {dest.stat().st_size / 1e6:.1f} Mo')
    return dest


def step_python():
    """Deplie la distribution embeddable et lui rend l'acces a site-packages."""
    py_dir = PKG / 'python'
    zip_path = fetch(PY_EMBED_URL, CACHE / f'python-{PY_VERSION}-embed.zip')
    py_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(py_dir)

    # La distribution embeddable desactive `import site` : sans cela, pip et
    # site-packages sont invisibles. On reactive, et on ajoute le dossier de
    # l'application au chemin d'import.
    pth = next(py_dir.glob('python*._pth'), None)
    if pth:
        lines = pth.read_text(encoding='utf-8').splitlines()
        out = []
        for line in lines:
            if line.strip() == '#import site':
                out.append('import site')
            else:
                out.append(line)
        if 'import site' not in out:
            out.append('import site')
        out.append('Lib/site-packages')
        out.append('../app')
        pth.write_text('\n'.join(out) + '\n', encoding='utf-8')
        log(f'{pth.name} ajuste (site actif, ../app dans le chemin)')

    exe = py_dir / 'python.exe'
    get_pip = fetch(GET_PIP_URL, CACHE / 'get-pip.py')
    log('installation de pip')
    subprocess.run([str(exe), str(get_pip), '--no-warn-script-location', '-q'],
                   check=True)

    # setuptools et wheel ne sont pas fournis par la distribution embeddable,
    # et get-pip n'installe que pip. Des qu'une dependance n'a pas de roue
    # precompilee pour cette version de Python, pip tente de la construire
    # depuis les sources et echoue sur « Cannot import setuptools.build_meta ».
    log('installation de setuptools et wheel')
    subprocess.run([str(exe), '-m', 'pip', 'install', '-q',
                    '--no-warn-script-location', 'setuptools', 'wheel'],
                   check=True)
    return exe


def step_deps(exe):
    reqs = ROOT / (KIT.get('requirements') or 'requirements.txt')
    if reqs.exists():
        log(f'installation depuis {reqs.name}')
        subprocess.run(
            [str(exe), '-m', 'pip', 'install', '-q', '--no-warn-script-location',
             '-r', str(reqs)], check=True)
    elif PIP_PAQUETS:
        log('installation de : ' + ', '.join(PIP_PAQUETS))
        subprocess.run(
            [str(exe), '-m', 'pip', 'install', '-q', '--no-warn-script-location',
             *PIP_PAQUETS], check=True)
    else:
        raise SystemExit("Ni requirements.txt ni liste « pip » dans kit.json.")


def step_app():
    app = PKG / 'app'
    app.mkdir(parents=True, exist_ok=True)
    missing = []
    for name in APP_MODULES + APP_ASSETS:
        src = ROOT / name
        if not src.exists():
            missing.append(name)
            continue
        shutil.copy2(src, app / name)
    # Dossiers entiers : une application structuree en paquets (core/, gui/,
    # modules/...) ne se decrit pas fichier par fichier.
    for nom in APP_PAQUETS:
        src = ROOT / nom
        if not src.is_dir():
            missing.append(nom + '/')
            continue
        shutil.copytree(src, app / nom, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc',
                                                      '.git', 'tests'))

    # Copies selectives : un dossier de donnees contient souvent bien plus que
    # ce qu'il faut livrer. Celui des sons de ce projet pese plusieurs
    # gigaoctets, dont seule une poignee de fichiers sert a l'application.
    for regle in COPIES:
        source = ROOT / regle['de']
        cible = app / regle.get('vers', regle['de'])
        retenus = 0
        for motif in regle.get('motifs', ['**/*']):
            for fichier in source.glob(motif):
                if not fichier.is_file():
                    continue
                destination = cible / fichier.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(fichier, destination)
                retenus += 1
        log(f"{regle['de']} : {retenus} fichier(s) retenu(s)")

    # La fiche d'identite voyage avec l'application : reporting.py et
    # updater.py la relisent pour savoir qui ils sont et d'ou viennent les
    # mises a jour.
    shutil.copy2(ROOT / 'kit.json', app / 'kit.json')

    if missing:
        log(f'ABSENTS (ignores) : {", ".join(missing)}')
    log(f'{len(APP_MODULES) + len(APP_ASSETS) + len(APP_PAQUETS)} elements applicatifs copies')
    return app


def step_binaires():
    """Binaires supplementaires declares par kit.json (ffmpeg, outils tiers).

    Chaque entree donne une archive a telecharger et les fichiers a en
    extraire ; ils atterrissent dans bin/. Une application qui n'en declare
    aucun saute simplement cette etape.
    """
    if not BINAIRES:
        log('aucun binaire supplementaire')
        return
    dest = PKG / 'bin'
    dest.mkdir(parents=True, exist_ok=True)
    for entree in BINAIRES:
        url = entree['url']
        voulus = entree.get('fichiers', [])
        archive = fetch(url, CACHE / url.rsplit('/', 1)[-1])
        with zipfile.ZipFile(archive) as z:
            for membre in z.namelist():
                base = Path(membre).name
                if base in voulus:
                    with z.open(membre) as src, open(dest / base, 'wb') as out:
                        shutil.copyfileobj(src, out)
                    log(f'{base} extrait')


def step_prune():
    """Retire les modules Qt que l'application n'utilise pas."""
    sp = PKG / 'python' / 'Lib' / 'site-packages'
    qt = sp / 'PyQt6' / 'Qt6'
    freed = 0

    def drop(path):
        nonlocal freed
        if not path.exists():
            return
        if path.is_dir():
            freed += sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
            shutil.rmtree(path, ignore_errors=True)
        else:
            freed += path.stat().st_size
            path.unlink(missing_ok=True)

    for d in (qt / 'bin', qt / 'lib'):
        if not d.is_dir():
            continue
        for f in d.iterdir():
            if any(f.name.startswith(p) for p in QT_PRUNE_PREFIXES):
                drop(f)

    for name in QT_PRUNE_PLUGIN_DIRS:
        drop(qt / 'plugins' / name)

    # QML n'est jamais charge par une application QtWidgets.
    drop(qt / 'qml')

    for name in PYQT_PRUNE_MODULES:
        drop(sp / 'PyQt6' / f'{name}.pyd')
        drop(sp / 'PyQt6' / f'{name}.pyi')

    # Traductions Qt : on ne garde que le francais et l'anglais.
    tr = qt / 'translations'
    if tr.is_dir():
        for f in tr.iterdir():
            if f.is_file() and not any(
                    tag in f.name for tag in ('_fr', '_en')):
                drop(f)

    # Entetes de developpement et bibliotheques d'edition de liens.
    for pattern in ('*.lib', '*.exp', '*.pdb'):
        for f in sp.rglob(pattern):
            drop(f)
    drop(sp / 'PyQt6' / 'bindings')
    drop(sp / 'PyQt6' / 'Qt6' / 'include')

    # Tests embarques dans numpy : inutiles a l'execution.
    drop(sp / 'numpy' / 'tests')
    for f in (sp / 'numpy').rglob('tests'):
        if f.is_dir():
            drop(f)

    log(f'elagage : {freed / 1e6:.0f} Mo retires')


def step_launcher():
    """Lanceur sans console, plus un lanceur de diagnostic qui la montre."""
    pyw = PKG / 'python' / 'pythonw.exe'
    (PKG / f'{NOM}.bat').write_text(
        '@echo off\r\n'
        f'start "" "%~dp0python\\pythonw.exe" "%~dp0app\\{POINT_ENTREE}" %*\r\n',
        encoding='ascii')

    # Quand rien ne demarre, c'est le seul moyen de voir l'erreur : elle
    # s'affiche et la fenetre reste ouverte.
    (PKG / 'Diagnostic.bat').write_text(
        '@echo off\r\n'
        f'title {NOM} - diagnostic\r\n'
        'echo Lancement avec la console visible. Les erreurs resteront affichees.\r\n'
        'echo.\r\n'
        f'"%~dp0python\\python.exe" "%~dp0app\\{POINT_ENTREE}" %*\r\n'
        'echo.\r\n'
        'pause\r\n',
        encoding='ascii')

    if not pyw.exists():
        log('ATTENTION : pythonw.exe absent, la console restera visible')
    log('lanceurs ecrits')


def step_precompile():
    """Pre-compile les .py : premier demarrage plus rapide chez l'utilisateur."""
    compileall.compile_dir(str(PKG / 'app'), quiet=2, force=True)
    log('bytecode pre-genere')


def folder_size(path):
    return sum(f.stat().st_size for f in path.rglob('*') if f.is_file())


def main():
    global DIST, PKG, CACHE
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', help="dossier de sortie (doit etre un disque local)")
    ap.add_argument('--no-prune', action='store_true')
    ap.add_argument('--skip-binaires', action='store_true')
    args = ap.parse_args()

    if args.out:
        DIST = Path(args.out).resolve()
        PKG = DIST / NOM
        CACHE = DIST / '.build_cache'
    elif str(ROOT).startswith('\\\\'):
        # Depot sur un partage UNC : Windows refuse d'executer un .exe depuis
        # un chemin reseau, on bascule donc sur un disque local.
        repli = Path(os.environ.get('LOCALAPPDATA', tempfile.gettempdir()))
        DIST = repli / f'{NOM}-build'
        PKG = DIST / NOM
        CACHE = DIST / '.build_cache'
        print(f'Depot sur un partage reseau : construction dans {DIST}')

    if sys.platform != 'win32':
        print('Ce paquet se construit sous Windows.')
        return 1

    print(f'Construction du paquet {NOM} dans {PKG}')
    if PKG.exists():
        shutil.rmtree(PKG)
    PKG.mkdir(parents=True)

    etapes = [
        ('Python embarque', lambda: globals().update(_exe=step_python())),
        ('Dependances', lambda: step_deps(globals()['_exe'])),
        ('Application', step_app),
        ('Binaires', (lambda: log('ignore')) if args.skip_binaires else step_binaires),
        ('Elagage', (lambda: log('ignore')) if args.no_prune else step_prune),
        ('Lanceurs', step_launcher),
        ('Pre-compilation', step_precompile),
    ]
    for i, (titre, action) in enumerate(etapes, 1):
        print(f'[{i}/{len(etapes)}] {titre}')
        action()

    taille = folder_size(PKG)
    print(f'\nTermine : {PKG}')
    print(f'Taille   : {taille / 1e6:.0f} Mo')
    return 0


if __name__ == '__main__':
    sys.exit(main())
