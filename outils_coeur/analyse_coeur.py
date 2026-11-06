#!/usr/bin/env python3
"""Résumé d'un relevé du cœur : par phase, durées d'image (moyenne, p50, p95, p99, max), à-coups,
appels et objets ; occupation des cœurs et des fils ; temps par système en ms par image ; pics.

    python outils_coeur/analyse_coeur.py DOSSIER ETIQ
"""
import csv,sys,collections,os
O=os.path.join(sys.argv[1],'');E=sys.argv[2]
R=list(csv.DictReader(open(O+E+'_images.csv',encoding='utf8'),delimiter=';'))
print(E,len(R),'images, t fin',R[-1]['t_s'])
ph=collections.OrderedDict()
for r in R: ph.setdefault(r['phase'],[]).append(r)
def q(v,p):
    v=sorted(v);return v[min(len(v)-1,int(len(v)*p))]
C=['image_ms','principal_ms','physique_ms','dessin_ms','rendu_cpu_ms','gpu_ms']
for k,L in ph.items():
    print('\n==',k,len(L),'images, %.0f s'%(float(L[-1]['t_s'])-float(L[0]['t_s'])),'cran',sorted(set(x['cran'] for x in L)),'detail',sorted(set(x['detail'] for x in L)))
    for c in C:
        v=[float(x[c]) for x in L]
        print('  %-13s moy %6.2f p50 %6.2f p95 %6.2f p99 %6.2f max %7.1f'%(c,sum(v)/len(v),q(v,.5),q(v,.95),q(v,.99),max(v)))
    im=[float(x['image_ms']) for x in L]
    print('  >17.5: %d  >25: %d (%.2f%%) >33: %d >50: %d >100: %d'%(sum(i>17.5 for i in im),sum(i>25 for i in im),100*sum(i>25 for i in im)/len(im),sum(i>33 for i in im),sum(i>50 for i in im),sum(i>100 for i in im)))
    for c in ['appels','objets','primitives','vram_mo','noeuds']:
        v=[float(x[c]) for x in L];print('  %-11s med %.0f max %.0f'%(c,q(v,.5),max(v)))
try:
    S=list(csv.DictReader(open(O+E+'_sonde.csv'),delimiter=';'))
    cs=[k for k in S[0] if k[0]=='c' and k[1:].isdigit()]
    S=S[5:]
    print('\nSONDE',len(S),'ech.')
    for k in ['gpu_pct','vram_mo','ram_sys_mo','rss_mo','nb_fils','fil1','fil2','fil3','fil4','fils_tous']:
        v=[float(x[k] or 0) for x in S];print('  %-10s med %.0f p95 %.0f max %.0f'%(k,q(v,.5),q(v,.95),max(v)))
    print('  coeurs moy:',' '.join('%.0f'%(sum(float(x[c]) for x in S)/len(S)) for c in cs))
    print('  CPU global moy %.1f%%'%(sum(float(x[c]) for x in S for c in cs)/len(S)/len(cs)))
except Exception as e: print('sonde',e)
P=collections.defaultdict(dict)
for l in open(O+E+'_prof.txt',encoding='utf8'):
    a,b,c=l.strip().split(';');P[a][b]=int(c)
for k,d in P.items():
    if k not in ph: continue
    n=len(ph[k]);print('\nPROF',k,'ms/image:',', '.join('%s %.2f'%(a,b/1000/n) for a,b in sorted(d.items(),key=lambda x:-x[1])[:12]))
pics=[l.strip().split(';') for l in open(O+E+'_pics.csv',encoding='utf8')]
pics=sorted(pics,key=lambda x:-float(x[2]))
print('\nPICS',len(pics))
for p in pics[:25]: print('  ',';'.join(p)[:170])
