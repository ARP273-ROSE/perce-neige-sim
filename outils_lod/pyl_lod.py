# Allège les pylônes (mêmes méthodes que veh_lod.py) : L1 et L2 par pylône, puis JSON par ligne.
import sys,os,json,glob,time
import veh_lod as V, numpy as np
import concurrent.futures as cf
V.BUD.update({'L1':1200,'L2':280})
V.CELL.update({'L1':0.03,'L2':0.07})
V.PETIT.update({'L1':0.08,'L2':0.25})
GROS={'olympique','tph_grande_motte'}
def un(T,ligne):
    P,F,C,D,PN=V.lit(T)
    c=(P.min(0)+P.max(0))/2;r=float(np.linalg.norm(P.max(0)-P.min(0)))*.55
    px=np.zeros(len(F),np.int64)
    for d in V.dirs()[::2]:
        im=V.raster_id(P,F,d,1400,c,r)
        ids,nb=np.unique(im,return_counts=True);m=ids>0;px[ids[m]-1]+=nb[m]
    seen=px>=2;PXM=(r*2/1400)**2*2
    ref=V.vues(P,F,c,r,512)
    R={'nom':T['nom'],'rang':T['rang'],'n0':len(F),'vus':int(seen.sum())}
    for lvl in V.BUD:
        pz,fz,cz=V.niveau(P,F,C,D,PN,seen,lvl,({'L1':2000,'L2':800}[lvl] if ligne in GROS else None),px,PXM)
        v,n,co,ix=V.sortie(pz,fz,cz)
        m=V.vues(v,ix.reshape(-1,3),c,r,512)
        iou=[float((a&b).sum())/max(1,(a|b).sum()) for a,b in zip(ref,m)]
        co=V.cuire(co,n,T['basis'])
        R[lvl]={'v':v.round(3).tolist(),'c':co.round(3).tolist(),'i':ix.tolist(),'tri':len(ix)//3,'iou':sum(iou)/len(iou)}
    return R
def ligne(a):
    rel,l=a
    t0=time.time()
    D=json.load(open(V.U+'pyl_dump/%s/%s.json'%(rel,l),encoding='utf8'))
    O=[]
    for T in D['pylones']:
        try:
            if T['tri']>0: O.append(un(T,l))
        except Exception as e:
            print('ERREUR',l,T['nom'],repr(e)[:160],flush=True)
    os.makedirs(V.U+'pyl_lod/'+rel,exist_ok=True)
    json.dump({'ligne':l,'pylones':O},open(V.U+'pyl_lod/%s/%s.json'%(rel,l),'w',encoding='utf8'))
    if not O: return l,0,0,0,0,0,time.time()-t0
    return l,len(O),sum(x['n0'] for x in O)/len(O),max(x['L2']['tri'] for x in O),sum(x['L1']['iou'] for x in O)/len(O),sum(x['L2']['iou'] for x in O)/len(O),time.time()-t0
if __name__=='__main__':
    rel=sys.argv[1]
    L=sys.argv[2].split(',') if len(sys.argv)>2 else [os.path.basename(f)[:-5] for f in glob.glob(V.U+'pyl_dump/%s/*.json'%rel)]
    with cf.ProcessPoolExecutor(min(22,len(L))) as ex:
        for r in ex.map(ligne,[(rel,l) for l in L]):
            print('%-26s %3d pylones, moy %6.0f tri, L2 max %3d, iou L1 %.2f L2 %.2f, %.0fs'%r,flush=True)
    print('FINI')
