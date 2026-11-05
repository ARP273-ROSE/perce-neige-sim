# Allège chaque type de véhicule : L1 et L2, une surface, couleurs par sommet (sRGB).
import sys,os,json,glob,time
S=os.path.dirname(os.path.abspath(__file__))
import numpy as np
from scipy.ndimage import binary_dilation
from scipy.spatial import ConvexHull
import fast_simplification as fs
from PIL import Image,ImageDraw
import concurrent.futures as cf
U=os.environ['APPDATA'].replace(chr(92),'/')+'/Godot/app_userdata/Perce-Neige Simulator 3D/'
METAL=0.0
FOND=(.5,.55,.62)              # valeur moyenne vue à travers une vitre
BUD={'L1':1500,'L2':320}
CELL={'L1':0.02,'L2':0.05}
PETIT={'L1':0.05,'L2':0.14}   # m : pièce plus petite que ça, ôtée

def dirs():
    n=62;i=np.arange(n)+.5;phi=np.arccos(1-2*i/n);th=np.pi*(1+5**.5)*i
    return np.c_[np.cos(th)*np.sin(phi),np.cos(phi),np.sin(th)*np.sin(phi)]
def base(d):
    a=np.array([0,1,0]) if abs(d[1])<.9 else np.array([1,0,0])
    u=np.cross(a,d);u/=np.linalg.norm(u);v=np.cross(d,u)
    return u,v
def raster_id(P,F,d,res,c,r):
    # peintre : du plus loin au plus près ; image des numéros de face (+1)
    u,v=base(d);Q=P-c
    x=(Q@u/r*.5+.5)*res;y=(Q@v/r*.5+.5)*res;z=Q@d
    o=np.argsort(z[F].mean(1))
    im=Image.new('I',(res,res),0);D=ImageDraw.Draw(im)
    xy=np.stack([x[F],y[F]],2)
    for k in o:
        t=xy[k];D.polygon([tuple(t[0]),tuple(t[1]),tuple(t[2])],fill=int(k)+1)
    return np.asarray(im)
def lit(T):
    PP=[];FF=[];CC=[];DD=[];NN=[];n=0
    for p in T['pieces']:
        v=np.array(p['v'],dtype=np.float64).reshape(-1,3)
        f=np.array(p['i'],dtype=np.int64).reshape(-1,3)
        if len(f)==0 or p['mat'].get('unshaded'): continue     # lettres et numéros posés à plat
        m=p['mat'];c=np.array(m.get('tex_c',m.get('c',[.5,.5,.5,1])),dtype=float)
        if m.get('transp'):
            a=c[3];c=c.copy();c[:3]=c[:3]*a+np.array(FOND)*(1-a)
        c=c.copy();c[:3]=c[:3]*(1-METAL*float(m.get('metal',0)))
        col=np.tile(c[:3],(len(f),1))
        if p['col'] and m.get('vc'):
            vc=np.array(p['col']).reshape(-1,3);col=col*vc[f].mean(1)
        PP.append(v);FF.append(f+n);CC.append(col);DD.append(np.full(len(f),p['detail']));NN.append(np.full(len(f),'/Pince' in ('/'+p['chemin'])));n+=len(v)
    return np.vstack(PP),np.vstack(FF),np.vstack(CC),np.concatenate(DD),np.concatenate(NN)
def soude(P,F,eps=2e-3):
    q=np.round(P/eps).astype(np.int64)
    u,inv=np.unique(q,axis=0,return_inverse=True);inv=inv.ravel()
    Pn=np.zeros((len(u),3));np.add.at(Pn,inv,P);Pn/=np.bincount(inv)[:,None]
    Fn=inv[F];ok=(Fn[:,0]!=Fn[:,1])&(Fn[:,1]!=Fn[:,2])&(Fn[:,0]!=Fn[:,2])
    return Pn,Fn,ok
def comps(F,nv):
    p=np.arange(nv)
    def fd(a):
        while p[a]!=a:
            p[a]=p[p[a]];a=p[a]
        return a
    for a,b,c in F:
        ra,rb,rc=fd(a),fd(b),fd(c)
        p[rb]=ra;p[fd(rc)]=ra
    return np.array([fd(a) for a in F[:,0]])
def aires(P,F):
    return .5*np.linalg.norm(np.cross(P[F[:,1]]-P[F[:,0]],P[F[:,2]]-P[F[:,0]]),axis=1)
def boite(p):
    # boîte orientée d'un nuage (12 triangles)
    c=p.mean(0);_,_,vt=np.linalg.svd(p-c,full_matrices=False)
    q=(p-c)@vt.T;lo=q.min(0);hi=q.max(0)
    b=np.array([[x,y,z] for x in (lo[0],hi[0]) for y in (lo[1],hi[1]) for z in (lo[2],hi[2])])@vt+c
    f=np.array([[0,1,3],[0,3,2],[4,6,7],[4,7,5],[0,4,5],[0,5,1],[2,3,7],[2,7,6],[0,2,6],[0,6,4],[1,5,7],[1,7,3]])
    return b,f
def prisme(p):
    # pièce longue et fine : prisme à 3 faces sans bouts (6 triangles)
    c=p.mean(0);_,_,vt=np.linalg.svd(p-c,full_matrices=False)
    q=(p-c)@vt.T;lo=q.min(0);hi=q.max(0);ra=max(hi[1]-lo[1],hi[2]-lo[2])*.62;my=(hi[1]+lo[1])/2;mz=(hi[2]+lo[2])/2
    a=[(my+ra*np.cos(t),mz+ra*np.sin(t)) for t in (0,2.094,4.189)]
    b=np.array([[x,y,z] for x in (lo[0],hi[0]) for y,z in a])@vt+c
    f=np.array([[0,3,1],[0,2,3],[2,5,3],[2,4,5],[4,1,5],[4,0,1]])
    return b,f
def chaine(p,f,k):
    # k tronçons le long de la pièce (distance sur le maillage), un prisme par morceau connexe
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    e=np.vstack([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]);w=np.linalg.norm(p[e[:,0]]-p[e[:,1]],axis=1)+1e-6
    G=coo_matrix((w,(e[:,0],e[:,1])),shape=(len(p),len(p))).tocsr();G=G+G.T
    d0=dijkstra(G,indices=0);d0[~np.isfinite(d0)]=0;a=int(np.argmax(d0))
    d=dijkstra(G,indices=a);d[~np.isfinite(d)]=0
    # les longs tronçons droits n'ont de sommets qu'à leurs bouts : on échantillonne le long des arêtes
    L=[p];Ld=[d]
    for x,y in e:
        l=np.linalg.norm(p[x]-p[y]);n=int(l/.04)
        if n>=1:
            t=(np.arange(1,n+1)/(n+1))[:,None]
            L.append(p[x]*(1-t)+p[y]*t);Ld.append(d[x]*(1-t[:,0])+d[y]*t[:,0])
    Q=np.vstack(L);Qd=np.concatenate(Ld);dm=max(d.max(),1e-6)
    V=[];I=[];n=0
    for i in range(k):
        lo=i/k*dm-.01;hi=(i+1)/k*dm+.01
        q=Q[(Qd>=lo)&(Qd<=hi)]
        if len(q)<4: continue
        pb,fb=prisme(q)
        V.append(pb);I.append(fb+n);n+=len(pb)
    if not V: return None
    return np.vstack(V),np.vstack(I)
def allonge(p):
    c=p.mean(0);_,_,vt=np.linalg.svd(p-c,full_matrices=False)
    q=(p-c)@vt.T;e=np.ptp(q,axis=0)
    return e[0]/max(e[1],1e-3),e
def droit(p):
    # le nuage suit-il une droite ? (écart transversal petit devant la longueur)
    c=p.mean(0);_,_,vt=np.linalg.svd(p-c,full_matrices=False)
    q=(p-c)@vt.T;x=q[:,0];k=np.argsort(x);e=np.ptp(x)
    b=np.linspace(x.min(),x.max(),7);m=[]
    for i in range(6):
        w=(x>=b[i])&(x<=b[i+1])
        if w.any(): m.append(q[w,1:].mean(0))
    m=np.array(m)
    return np.ptp(m,axis=0).max()<max(.03,.03*e)
def plein(P,f):
    # volume fermé de la pièce / volume de sa boîte
    p=P[np.unique(f)];o=p.mean(0);a,b,c=P[f[:,0]]-o,P[f[:,1]]-o,P[f[:,2]]-o
    v=abs((a*np.cross(b,c)).sum())/6
    return v>=.45*vol_boite(p) and np.linalg.norm(np.ptp(p,axis=0))<1.6
def vol_boite(p):
    e=np.maximum(np.ptp(p,axis=0),.02)
    return float(e.prod())
def fusion_boites(cand):
    # coussins et plaques voisins de même couleur, bien remplis par leur boîte commune : une seule pièce
    ok=True
    while ok:
        ok=False
        for a in range(len(cand)):
            for b in range(a+1,len(cand)):
                A,B=cand[a],cand[b]
                if np.abs(A['col']-B['col']).sum()>1e-3 or A['diag']>2.5 or B['diag']>2.5: continue
                if not (A.get('plein') and B.get('plein')): continue
                u=np.vstack([A['pts'],B['pts']])
                if vol_boite(u)<=1.3*(vol_boite(A['pts'])+vol_boite(B['pts'])):
                    cand[a]=dict(f=np.vstack([A['f'],B['f']]),col=A['col'],diag=float(np.linalg.norm(np.ptp(u,axis=0))),a=A['a']+B['a'],n=A['n']+B['n'],pts=u,bloc=True,plein=True)
                    cand.pop(b);ok=True;break
            if ok: break
    return cand
VUES=None
def vues6():
    global VUES
    if VUES is None:
        VUES=[]
        for az,el in ((0,10),(90,10),(45,25),(135,25),(0,80),(20,-50)):
            d=np.array([np.cos(np.radians(az))*np.cos(np.radians(el)),np.sin(np.radians(el)),np.sin(np.radians(az))*np.cos(np.radians(el))])
            VUES.append(base(d))
    return VUES
def masques(p,f,c,cell,res):
    o=[]
    for u,v in vues6():
        Q=p-c;x=(Q@u)/cell+res/2;y=(Q@v)/cell+res/2
        im=Image.new('1',(res,res),0);D=ImageDraw.Draw(im)
        for t in f:
            D.polygon([(x[t[0]],y[t[0]]),(x[t[1]],y[t[1]]),(x[t[2]],y[t[2]])],fill=1)
        o.append(np.asarray(im))
    return o
def grille(p,f,cell):
    # regroupement de sommets : robuste sur les coques ouvertes et les doubles parois
    q=np.round((p-p.min(0))/cell).astype(np.int64)
    u,inv=np.unique(q,axis=0,return_inverse=True);inv=inv.ravel()
    P=np.zeros((len(u),3));np.add.at(P,inv,p);P/=np.bincount(inv)[:,None]
    F=inv[f];ok=(F[:,0]!=F[:,1])&(F[:,1]!=F[:,2])&(F[:,0]!=F[:,2]);F=F[ok]
    if len(F)==0: return None
    # triangles en double (mêmes 3 sommets)
    _,k=np.unique(np.sort(F,axis=1),axis=0,return_index=True)
    return P,F[np.sort(k)]
def echelle(c,lvl,Pw):
    # options d'une pièce : (triangles, erreur de silhouette en m², sommets, faces)
    cell=CELL[lvl]
    vs,inv=np.unique(c['f'],return_inverse=True);p=Pw[vs];f=inv.reshape(-1,3)
    ctr=(p.min(0)+p.max(0))/2
    res=int(min(max(16,np.linalg.norm(np.ptp(p,axis=0))*1.15/cell),512))
    cl=max(cell,np.linalg.norm(np.ptp(p,axis=0))*1.15/res)
    ref=masques(p,f,ctr,cl,res)
    refd=[binary_dilation(m) for m in ref]
    sur=sum(int(m.sum()) for m in ref)
    k=c.get('poids',1.0)*cl*cl
    op=[(0,sur*k,None,None)]
    def essai(q):
        if q is None or len(q[1])<2: return
        m=masques(q[0],q[1],ctr,cl,res)
        e=sum(int((x&~binary_dilation(y)).sum())+int((y&~xd).sum()) for x,y,xd in zip(ref,m,refd))*k
        op.append((len(q[1]),e,q[0],q[1]))
    essai(boite(p))
    if allonge(p)[0]>3: essai(prisme(p))
    if allonge(p)[0]>2.5 or c['diag']>.8:
        for nk in (2,3,4,6,8,12):
            if 6*nk<len(f): essai(chaine(p,f,nk))
    if True:
        vus=set()
        for t in (8,12,16,24,32,48,64,96,128,192,256,384,512):
            if t>=len(f): break
            pz,fz=fs.simplify(p.astype(np.float32),f.astype(np.int32),target_count=t,agg=8)
            if len(fz) in vus or len(fz)==0: continue
            vus.add(len(fz));essai((pz.astype(float),fz))
        dg=np.linalg.norm(np.ptp(p,axis=0))
        # enveloppe convexe : fermée, se simplifie bien (coques, toits, vitrages)
        if len(p)>=8 and np.ptp(p,axis=0).min()>.01:
            try:
                H=ConvexHull(p);hv,hi=np.unique(H.simplices,return_inverse=True);hp=p[hv];hf=hi.reshape(-1,3)
                essai((hp,hf))
                for t in (12,16,20,24,32,40,48,64,80,96,128,160):
                    if t>=len(hf): break
                    pz,fz=fs.simplify(hp.astype(np.float32),hf.astype(np.int32),target_count=t,agg=7)
                    if len(fz)>=8: essai((pz.astype(float),fz))
            except Exception as ex:
                print('ENV ERREUR',c['n'],repr(ex)[:150],flush=True)
        for dv in (2.5,3.5,5,7,10,14,20,28,40,56):
            r=grille(p,f,dg/dv)
            if r is not None and 4<=len(r[1])<len(f): essai(r)
        op.append((len(f),0.0,p,f))
    op.sort(key=lambda o:(o[0],o[1]))
    g=[op[0]]
    for o in op[1:]:
        if o[1]<g[-1][1]-1e-9: g.append(o)
    return g
def oriente(p,f,convexe):
    # normales (produit vectoriel) vers l'extérieur
    f=np.asarray(f).copy()
    if len(f)==0: return f
    a,b,c=p[f[:,0]],p[f[:,1]],p[f[:,2]];n=np.cross(b-a,c-a)
    if convexe:
        o=p.mean(0);inv=((a+b+c)/3-o)*n
        m=inv.sum(1)<0
        f[m]=f[m][:,[0,2,1]]
        return f
    o=p.mean(0);vol=((a-o)*np.cross(b-o,c-o)).sum()/6
    ar=np.linalg.norm(n,axis=1).sum()/2;ep=np.ptp(p,axis=0).min()
    if abs(vol)<ar*max(ep,1e-3)*.02:
        return f[:,[0,2,1]]     # plaque : sens d'origine (Godot : horaire)
    return f if vol>0 else f[:,[0,2,1]]
def niveau(P,F,C,D,PN,vis,lvl,B=None,PX=None,PXM=1.0):
    B=B or BUD[lvl]
    keep=vis.copy()
    Pw,Fw,ok=soude(P,F);keep&=ok
    Fk=Fw[keep];Ck=C[keep];Dk=D[keep];Nk=PN[keep];Xk=PX[keep]
    cq=np.round(Ck*64).astype(int);cu,cid=np.unique(cq,axis=0,return_inverse=True);cid=cid.ravel()
    cand=[]
    for ic in range(len(cu)):
        idx=np.where(cid==ic)[0]
        f=Fk[idx];lab=comps(f,len(Pw))
        col=Ck[idx].mean(0)
        for l in np.unique(lab):
            m=lab==l
            g=f[m];vs=np.unique(g);diag=float(np.linalg.norm(np.ptp(Pw[vs],axis=0)));a=float(aires(Pw,g).sum())
            det=bool(Dk[idx][m].mean()>.5);pc=bool(Nk[idx][m].mean()>.5)
            # plaque cachée : presque jamais vue de l'extérieur (une face vue d'une moitié des 62 directions vaudrait ~10 fois son aire)
            if Xk[idx][m].sum()*PXM < .25*a and not pc: continue
            if lvl=='L2' and det and diag<.2 and not pc: continue
            if diag<PETIT[lvl]: continue
            cand.append(dict(f=g,col=col,diag=diag,a=a,n=len(g),pts=Pw[vs],bloc=False,poids=(4.0 if pc else (2.5 if np.ptp(col)>.25 else 1.0)),plein=plein(Pw,g)))
    if lvl=='L2': cand=fusion_boites(cand)
    E=[echelle(c,lvl,Pw) for c in cand]
    cur=[0]*len(E);tot=0
    # seuls forcés : le bras (pièce fine de plus grande hauteur) et les 2 plus grosses pièces de pince
    fines=[i for i,c in enumerate(cand) if c['diag']>1.0 and allonge(c['pts'])[0]>3 and np.ptp(c['pts'][:,1])>.7*c['diag']]
    bras=sorted(fines,key=lambda i:-np.ptp(cand[i]['pts'][:,1]))[:1]
    pinces=sorted([i for i,c in enumerate(cand) if c.get('poids',1)>=4 and i not in bras],key=lambda i:-cand[i]['a'])[:2]
    # le bras : chaîne de tronçons posée d'office (6 en L2, 12 en L1), hors sélection
    for i in bras:
        bons=[j for j,o in enumerate(E[i]) if 0<o[0]<=max(36,.1*B)]
        if bons:
            j=min(bons,key=lambda j:E[i][j][1]);cur[i]=j;tot+=E[i][j][0]
    for i in pinces:
        if len(E[i])>1:
            bons=[j for j,o in enumerate(E[i]) if 0<o[0]<=max(18,.12*B)]
            if not bons: continue
            j=min(bons,key=lambda j:E[i][j][1]);cur[i]=j;tot+=E[i][j][0]
    while True:
        best=None;br=0
        for i,o in enumerate(E):
            a0=o[cur[i]]
            for j in range(cur[i]+1,len(o)):
                dt=o[j][0]-a0[0]
                if dt<=0 or tot+dt>B: continue
                r=(a0[1]-o[j][1])/dt
                if r>br: br=r;best=(i,j,dt)
        if best is None or br<=0: break
        cur[best[0]]=best[1];tot+=best[2]
    if os.environ.get('VEH_DEBUG'):
        for i in sorted(range(len(cand)),key=lambda i:-cand[i]['a'])[:14]:
            c=cand[i];print(lvl,'%.2f m2 diag %.2f n %d col %s choisi %d/%s'%(c['a'],c['diag'],c['n'],np.round(c['col'],2),E[i][cur[i]][0],[(o[0],round(o[1],3)) for o in E[i]][:9]))
    V=[];I=[];Col=[];n=0;faits=0
    for c,o,k in zip(cand,E,cur):
        if o[k][0]==0: continue
        t,_,p,f=o[k];faits+=1
        f=oriente(p,f,t in (6,12) and len(p) in (6,8))
        V.append(p);I.append(np.asarray(f)+n);Col.append(np.tile(c['col'],(len(f),1)));n+=len(p)
    return np.vstack(V).astype(float),np.vstack(I),np.vstack(Col)
def sortie(P,F,C):
    # sommets séparés par couleur et par arête vive (45°), normales lissées dans chaque groupe
    a=P[F[:,1]]-P[F[:,0]];b=P[F[:,2]]-P[F[:,0]];N=np.cross(a,b);A=np.linalg.norm(N,axis=1,keepdims=True);N=N/np.maximum(A,1e-12)
    V={};vp=[];vn=[];vc=[];I=[]
    for fa,na,ar,co in zip(F,N,A[:,0],C):
        for w in fa:
            lst=V.setdefault(int(w),[])
            for e in lst:
                if e[1]@na>.7 and np.abs(e[2]-co).sum()<1e-3:
                    e[3]=e[3]+na*ar;I.append(e[0]);break
            else:
                i=len(vp);vp.append(P[w]);vc.append(co);lst.append([i,na.copy(),co,na*ar]);I.append(i);vn.append(None)
    for lst in V.values():
        for e in lst:
            n=e[3];l=np.linalg.norm(n);vn[e[0]]=n/l if l>0 else e[1]
    I=np.array(I,dtype=np.int32).reshape(-1,3)[:,[0,2,1]].ravel()
    return np.array(vp),np.array(vn),np.array(vc),I
SOLEIL=(0.40, 0.78, 0.48)
def s2l(c):
    c=np.asarray(c);return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
def l2s(c):
    c=np.clip(c,0,None);return np.where(c<=.0031308,c*12.92,1.055*np.power(c,1/2.4)-.055)
def cuire(co,n,B=None):
    # lumière dans les couleurs, comme web_loin ; sans orientation connue (véhicules) : moyenne sur 8 caps
    s=np.array(SOLEIL);s=s/np.linalg.norm(s)
    if B is not None:
        d=np.maximum(0,(n@np.asarray(B).T)@s)
    else:
        d=0
        for az in np.radians(np.arange(0,360,45)):
            ca,sa=np.cos(az),np.sin(az)
            nr=np.c_[n[:,0]*ca+n[:,2]*sa,n[:,1],-n[:,0]*sa+n[:,2]*ca]
            d=d+np.maximum(0,nr@s)
        d=d/8
    k=(.55+.60*d)[:,None]
    return np.clip(l2s(s2l(co)*k),0,1)
def vues(P,F,c,r,res=384):
    o=[]
    for az in range(0,360,45):
        d=np.array([np.cos(np.radians(az))*np.cos(np.radians(15)),np.sin(np.radians(15)),np.sin(np.radians(az))*np.cos(np.radians(15))])
        o.append(raster_id(P,F,d,res,c,r)>0)
    return o
def traite(i):
    T=json.load(open(U+'veh_dump/%d.json'%i,encoding='utf8'))
    P,F,C,D,PN=lit(T)
    c=(P.min(0)+P.max(0))/2;r=float(np.linalg.norm(P.max(0)-P.min(0)))*.55
    t0=time.time()
    px=np.zeros(len(F),np.int64)
    for d in dirs():
        im=raster_id(P,F,d,1024,c,r)
        ids,nb=np.unique(im,return_counts=True);m=ids>0;px[ids[m]-1]+=nb[m]
    seen=px>=4
    PXM=(r*2/1024)**2
    R={'cle':T['cle'],'pivot':T['pivot'],'n0':len(F),'vus':int(seen.sum()),'lignes':T['lignes']}
    ref=vues(P,F,c,r)
    for lvl in BUD:
        pz,fz,cz=niveau(P,F,C,D,PN,seen,lvl,(400 if lvl=='L2' and T['famille'].startswith('cabine') else None),px,PXM)
        v,n,co,ix=sortie(pz,fz,cz)
        m=vues(v,ix.reshape(-1,3),c,r)
        iou=[float((a&b).sum())/max(1,(a|b).sum()) for a,b in zip(ref,m)]
        co=cuire(co,n)
        R[lvl]={'v':v.round(4).tolist(),'c':co.round(4).tolist(),'i':ix.tolist(),'tri':len(ix)//3,'som':len(v),'iou_min':min(iou),'iou_moy':sum(iou)/len(iou)}
    R['s']=time.time()-t0
    json.dump(R,open(U+'veh_lod/%d.json'%i,'w',encoding='utf8'))
    return i,T['cle'],R['n0'],R['vus'],R['L1']['tri'],R['L1']['iou_moy'],R['L1']['iou_min'],R['L2']['tri'],R['L2']['iou_moy'],R['L2']['iou_min'],R['s']
if __name__=='__main__':
    os.makedirs(U+'veh_lod',exist_ok=True)
    L=[int(a) for a in sys.argv[1].split(',')] if len(sys.argv)>1 else sorted(int(os.path.basename(f)[:-5]) for f in glob.glob(U+'veh_dump/*.json'))
    with cf.ProcessPoolExecutor(min(16,len(L))) as ex:
        for r in ex.map(traite,L):
            print('%2d %-44s %6d vus %6d | L1 %5d iou %.2f/%.2f | L2 %4d iou %.2f/%.2f | %.0fs'%r,flush=True)
