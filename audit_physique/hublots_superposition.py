import math,sys
from PIL import Image, ImageDraw
R,YC,YF=1.72,0.20,-0.95
T0,T1=float(sys.argv[1]),float(sys.argv[2]); W=float(sys.argv[3]); NH,NB=float(sys.argv[4]),float(sys.argv[5])
cx=float(sys.argv[6]) if len(sys.argv)>6 else 848
w0,w1=R*math.radians(T0),R*math.radians(T1)
a,b,c=W/2,(w1-w0)/2,(w0+w1)/2
sx=345/0.7772             # px/m horizontal (pas du panneau)
sy=840/2.161              # px/m vertical (baie de porte)
y_sol=1150                # seuil de la baie, photo 2
im=Image.open('photo_rame_2.jpeg').convert('RGB'); d=ImageDraw.Draw(im)
pts=[]
for i in range(200):
    ang=2*math.pi*i/200; ca,sa=math.cos(ang),math.sin(ang)
    ex=NH if sa<0 else NB
    u=a*math.copysign(abs(ca)**(2/ex),ca); w=c+b*math.copysign(abs(sa)**(2/ex),sa)
    h=YC+R*math.cos(w/R)-YF
    pts.append((cx+u*sx, y_sol-h*sy))
d.line(pts+[pts[0]],fill=(0,255,0),width=3)
im.crop((650,330,1100,1230)).save('superpose.png')
