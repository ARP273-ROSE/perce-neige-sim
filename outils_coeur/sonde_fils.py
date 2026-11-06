#!/usr/bin/env python3
"""Occupation de chaque cœur et des fils du processus du jeu, toutes les 2 s (psutil).

    python outils_coeur/sonde_fils.py SORTIE.csv NOM_PROCESSUS

fil1..fil4 : les quatre fils les plus chargés (% d'un cœur), fils_tous : leur somme. GPU : nvidia-smi
s'il existe, sinon gpu_busy_percent d'amdgpu sous Linux, sinon vide.
"""
import csv
import glob
import shutil
import subprocess
import sys
import time

import psutil


def gpu():
    if shutil.which('nvidia-smi'):
        g = subprocess.run(['nvidia-smi', '--query-gpu=utilization.gpu,memory.used', '--format=csv,noheader,nounits'],
                           capture_output=True, text=True).stdout.strip().split(',')
        return g[0].strip(), (g[1].strip() if len(g) > 1 else '')
    for f in glob.glob('/sys/class/drm/card*/device/gpu_busy_percent'):
        try:
            v = open(f).read().strip()
            m = open(f.replace('gpu_busy_percent', 'mem_info_vram_used')).read().strip()
            return v, str(int(m) // 1048576)
        except OSError:
            pass
    return '', ''


sortie, nom = sys.argv[1], sys.argv[2].lower()
proc = None
fils_prec = {}
psutil.cpu_percent(percpu=True)
with open(sortie, 'w', newline='') as fh:
    w = csv.writer(fh, delimiter=';')
    n = psutil.cpu_count()
    w.writerow(['t', 'gpu_pct', 'vram_mo', 'ram_sys_mo', 'rss_mo', 'nb_fils', 'fil1', 'fil2', 'fil3', 'fil4', 'fils_tous']
               + ['c%d' % i for i in range(n)])
    t_prec = time.time()
    while True:
        time.sleep(2.0)
        t = time.time()
        if proc is None or not proc.is_running():
            proc = None
            for p in psutil.process_iter(['name']):
                if (p.info['name'] or '').lower() == nom:
                    proc = p
                    break
        c = psutil.cpu_percent(percpu=True)
        g = gpu()
        rss = 0
        pct = []
        if proc is not None:
            try:
                rss = proc.memory_info().rss // 1048576
                cur = {}
                for f in proc.threads():
                    cur[f.id] = f.user_time + f.system_time
                    pct.append(100.0 * (cur[f.id] - fils_prec.get(f.id, cur[f.id])) / (t - t_prec))
                fils_prec = cur
            except psutil.Error:
                proc = None
        t_prec = t
        pct.sort(reverse=True)
        h = (pct + [0, 0, 0, 0])[:4]
        w.writerow([round(t, 1), g[0], g[1], psutil.virtual_memory().used // 1048576, rss, len(pct)]
                   + ['%.0f' % x for x in h] + ['%.0f' % sum(pct)] + c)
        fh.flush()
