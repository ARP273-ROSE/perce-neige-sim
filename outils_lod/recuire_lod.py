#!/usr/bin/env python3
"""Recuit les versions allégées des remontées, à lancer après un changement de géométrie :
vehicules_lod.cuit et pylones_lod_25.web.cuit (data/remontees), puis les lignes lointaines de la PWA.

  python outils_lod/recuire_lod.py --godot GODOT_CONSOLE --travail DOSSIER --web-loin DOSSIER_SORTIE [--etapes veh,pyl,loin]

Il faut numpy, scipy, Pillow et fast_simplification. Tout user:// est écrit sous DOSSIER (APPDATA remplacé).
"""
import argparse
import concurrent.futures as cf
import glob
import os
import shutil
import subprocess
import sys
import time

a = argparse.ArgumentParser()
a.add_argument('--godot', required=True)
a.add_argument('--travail', required=True)
a.add_argument('--web-loin', required=True)
a.add_argument('--etapes', default='veh,pyl,loin')
a.add_argument('--fils', type=int, default=14)
A = a.parse_args()
RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJET = os.path.join(RACINE, 'godot_project')
DONNEES = os.path.join(PROJET, 'data', 'remontees')
ENV = dict(os.environ, APPDATA=os.path.abspath(A.travail), PYTHONIOENCODING='utf8')
os.makedirs(A.travail, exist_ok=True)
U = os.path.join(os.path.abspath(A.travail), 'Godot', 'app_userdata', 'Perce-Neige Simulator 3D')
os.makedirs(U, exist_ok=True)
ETAPES = A.etapes.split(',')
T0 = time.time()


def godot(script, *args, delai=900, fixe=False):
    c = [A.godot, '--headless'] + (['--fixed-fps', '60'] if fixe else []) + ['--path', PROJET, '-s', script, '--'] + list(args)
    r = subprocess.run(c, capture_output=True, timeout=delai, env=ENV)
    return r.returncode, (r.stdout + r.stderr).decode('utf8', 'replace').splitlines()


def journal(*t):
    print('[%5.0f s]' % (time.time() - T0), *t, flush=True)


def python(script, *args):
    r = subprocess.run([sys.executable, os.path.join(RACINE, 'outils_lod', script)] + list(args), env=ENV, capture_output=True)
    for l in (r.stdout + r.stderr).decode('utf8', 'replace').splitlines():
        print('   ', l[:150], flush=True)
    if r.returncode != 0:
        sys.exit('%s : code %d' % (script, r.returncode))


LIGNES = [l for l in godot('cuisson_lod_pyl_dump.gd', '--liste', delai=120)[1] if l.startswith('LIGNES ')][0][7:].split(',')
journal(len(LIGNES), 'lignes')

if 'veh' in ETAPES:
    code, o = godot('cuisson_lod_veh_dump.gd', '--mode=normal', '--sans-relief-fin', delai=600)
    journal('véhicules :', [l for l in o if l.startswith('DUMP_OK')] or o[-5:])
    python('veh_lod.py')
    code, o = godot('cuisson_lod_veh_cuit.gd', '--cuit-seul', '--sortie=x', delai=300)
    journal([l[:90] for l in o if l.startswith('CUIT')])
    shutil.copy(os.path.join(U, 'veh_lod', 'vehicules_lod.cuit'), os.path.join(DONNEES, 'vehicules_lod.cuit'))

if 'pyl' in ETAPES:
    def un(l):
        code, o = godot('cuisson_lod_pyl_dump.gd', '--mode=normal', '--sans-relief-fin', '--ligne=' + l)
        e = [x for x in o if x.startswith('PYL_OK')]
        return e[0] if e else l + ' RIEN ' + ' | '.join(x[:120] for x in o if 'SCRIPT ERROR' in x)[:300]
    with cf.ThreadPoolExecutor(A.fils) as ex:
        R = list(ex.map(un, LIGNES))
    journal('pylônes : %d lignes' % sum('PYL_OK' in r for r in R))
    for r in R:
        if 'PYL_OK' not in r:
            print('   ', r[:200], flush=True)
    python('pyl_lod.py', '25')
    sortie = os.path.join(DONNEES, 'pylones_lod_25.web.cuit')
    code, o = godot('cuisson_lod_pyl_cuit.gd', '--rel=25', '--web', '--sortie=' + sortie, delai=300)
    journal([l[:90] for l in o if l.startswith('CUIT_PYL')])

if 'loin' in ETAPES:
    arg = ['--mode=normal', '--web', '--loin', '--sans-relief-fin', '--indexer', '--palette', '--partage-rames', '--sortie=user://cuites_loin']

    def un2(c):
        code, o = godot('cuisson_ligne.gd', *arg, '--ligne=' + c, fixe=True)
        return c, code, [l for l in o if l.startswith(('LOIN', 'SCRIPT ERROR'))]
    with cf.ThreadPoolExecutor(A.fils) as ex:
        R = list(ex.map(un2, LIGNES))
    ok = [r for r in R if r[1] == 0 and any(l.startswith('LOIN') for l in r[2])]
    journal('lointaines : %d lignes sur %d' % (len(ok), len(LIGNES)))
    for r in R:
        if r not in ok:
            print('    ECHEC', r[0], r[1], r[2][:2], flush=True)
    godot('cuisson_ligne.gd', '--materiaux', '--web', '--sortie=user://cuites_loin', delai=120)
    F = glob.glob(os.path.join(U, 'cuites_loin', '*.web.cuit'))
    os.makedirs(A.web_loin, exist_ok=True)
    for f in F:
        shutil.copy(f, A.web_loin)
    journal('copiés : %d fichiers, %.1f Mo' % (len(F), sum(os.path.getsize(f) for f in F) / 1048576))
journal('FINI')
