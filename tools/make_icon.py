#!/usr/bin/env python3
"""Draws the app icon (ghost with a broom inside a disk ring, on green) into Resources/AppIcon.iconset.
The broom is the flat "Broom" emoji from Microsoft Fluent UI Emoji (MIT), tools/assets/broom_flat.svg.
Flat layers only: on macOS 26 the system adds the glass highlight and shadow itself."""
import math, os, io, re
import numpy as np
import cairosvg   # pip install cairosvg numpy pillow
from PIL import Image, ImageDraw
S=4096; k=S/1024
def q(v): return int(round(v*k))
def vgrad(size, top, bottom):
    w,h=size; g=Image.new("RGB",(1,h))
    for y in range(h):
        t=y/(h-1); g.putpixel((0,y),tuple(int(top[i]+(bottom[i]-top[i])*t) for i in range(3)))
    return g.resize((w,h))
def bez(p0,p1,p2,p3,n=40):
    o=[]
    for i in range(n+1):
        t=i/n; a,b,c,e=(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3
        o.append((a*p0[0]+b*p1[0]+c*p2[0]+e*p3[0],a*p0[1]+b*p1[1]+c*p2[1]+e*p3[1]))
    return o
def ghost_pts(ox,oy,s,rot=0,cx=512,cy=512):
    def p(x,y):
        X,Y=ox+x*s,oy+y*s
        if rot:
            a=math.radians(rot); dx,dy=X-cx,Y-cy
            X,Y=cx+dx*math.cos(a)-dy*math.sin(a), cy+dx*math.sin(a)+dy*math.cos(a)
        return (X,Y)
    pts=[p(4,22),p(4,10)]+bez(p(4,10),p(4,5.58),p(7.58,2),p(12,2))[1:]+bez(p(12,2),p(16.42,2),p(20,5.58),p(20,10))[1:]
    pts+=[p(20,22),p(17,19),p(14.5,21.5),p(12,19),p(9.5,21.5),p(7,19)]
    return pts,p
def poly(d,pts,fill): d.polygon([(q(x),q(y)) for x,y in pts],fill=fill)
def ell(d,c,rx,ry,fill): d.ellipse((q(c[0]-rx),q(c[1]-ry),q(c[0]+rx),q(c[1]+ry)),fill=fill)
def star(d,c,r,fill):
    pts=[]
    for i in range(8):
        a=math.pi/4*i-math.pi/2; rr=r if i%2==0 else r*0.28
        pts.append((c[0]+rr*math.cos(a),c[1]+rr*math.sin(a)))
    poly(d,pts,fill)
def point_on(A,B,t): return (A[0]+(B[0]-A[0])*t, A[1]+(B[1]-A[1])*t)
MASK=None
def squircle():
    global MASK
    if MASK is None:
        MASK=Image.new("L",(S,S),0); ImageDraw.Draw(MASK).rounded_rectangle((q(100),q(100),q(924),q(924)),radius=q(185),fill=255)
    return MASK
def base(top,bottom):
    bg=vgrad((S,S),top,bottom).convert("RGBA")
    layer=Image.new("RGBA",(S,S),(0,0,0,0))
    return bg,layer
def finish(bg,layer):
    bg.alpha_composite(layer)
    out=Image.new("RGBA",(S,S),(0,0,0,0)); out.paste(bg,(0,0),squircle()); return out
EYE=(11,77,60,255)
def eyes(d,p,s,look=-0.6,mouth=True):
    for ex in (9,15):
        c=p(ex+look,10.2); ell(d,c,1.2*s,1.6*s,EYE)
    if mouth:
        a=p(11+look,12.6); b=p(13+look,14.6)
        d.chord((q(a[0]),q(a[1]),q(b[0]),q(b[1])),start=0,end=180,fill=EYE)
K=S/1024
TOP=(712,458)          # where the handle ends, upper right of the ghost
LENGTH=505             # handle top → farthest bristle, in 1024 units
ANGLE=48               # handle angle above horizontal, degrees

def render(svg,px,recolor=None):
    data=open(svg).read()
    if recolor: data=re.sub(r'<svg ',f'<svg fill="{recolor}" ',data,count=1)
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=data.encode(),output_width=px,output_height=px))).convert('RGBA')

def axis(im,color,tol=45):
    a=np.asarray(im).astype(int)
    m=(a[...,3]>200)&(np.abs(a[...,0]-color[0])<tol)&(np.abs(a[...,1]-color[1])<tol)&(np.abs(a[...,2]-color[2])<tol)
    ys,xs=np.nonzero(m); pts=np.stack([xs,ys],1).astype(float); c=pts.mean(0)
    _,_,vt=np.linalg.svd(pts-c,full_matrices=False); v=vt[0]
    if v[1]>0: v=-v
    pr=(pts-c)@v
    return c+v*pr.max(), c+v*pr.min(), v

def prepared(svg,color,recolor=None):
    im=render(svg,1600,recolor)
    top,bot,v=axis(im,color)
    cur=math.degrees(math.atan2(-v[1],v[0]))      # angle of the handle, up = positive
    im=im.rotate(ANGLE-cur,resample=Image.BICUBIC,expand=True)
    top,bot,v=axis(im,color)
    a=np.asarray(im)[...,3]; ys,xs=np.nonzero(a>40)
    far=np.max(np.hypot(xs-top[0],ys-top[1]))
    sc=LENGTH*K/far
    im=im.resize((int(im.width*sc),int(im.height*sc)),Image.LANCZOS)
    return im, top*sc, bot*sc

def mitten(d,c,ang):
    ux,uy=math.cos(math.radians(ang)),-math.sin(math.radians(ang)); nx,ny=-uy,ux
    def oval(cx,cy,a,b,fill):
        pts=[(cx+ux*a*math.cos(t)+nx*b*math.sin(t), cy+uy*a*math.cos(t)+ny*b*math.sin(t)) for t in [i*math.pi/30 for i in range(60)]]
        poly(d,pts,fill)
    oval(c[0]+1.5,c[1]+2.5,17,27,(206,222,216,255))   # soft edge so the hand reads on the white body
    oval(c[0],c[1],16,25,(255,255,255,255))

def make(svg,color,recolor=None,hands=(0.1,0.5),ring=True):
    bg,img=base((100,210,168),(15,143,110)); d=ImageDraw.Draw(img)
    if ring:
        r,w=312,31; box=(q(512-r),q(512-r),q(512+r),q(512+r))
        d.arc(box,start=-90,end=-90+360*0.72,fill=(255,255,255,255),width=q(w))
        d.arc(box,start=-90+360*0.745,end=-90+360*0.975,fill=(255,214,10,255),width=q(w))
    s=19; pts,p=ghost_pts(512-12*s+20,505-12*s,s)
    poly(d,pts,(255,255,255,255)); eyes(d,p,s,look=-0.7)
    im,top,bot=prepared(svg,color,recolor)
    ox,oy=TOP[0]*K-top[0], TOP[1]*K-top[1]
    img.alpha_composite(im,(int(round(ox)),int(round(oy))))
    d=ImageDraw.Draw(img)
    T=((top[0]+ox)/K,(top[1]+oy)/K); B=((bot[0]+ox)/K,(bot[1]+oy)/K)
    for t in hands: mitten(d,(T[0]+(B[0]-T[0])*t, T[1]+(B[1]-T[1])*t),ANGLE)
    star(d,(194,706),24,(255,255,255,255)); star(d,(812,820),16,(255,255,255,230))
    return finish(bg,img)


HERE = os.path.dirname(os.path.abspath(__file__))
img = make(os.path.join(HERE, "assets", "broom_flat.svg"), (124, 68, 50))
out = os.path.join(HERE, "..", "Resources", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
for base_px in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base_px * scale
        name = f"icon_{base_px}x{base_px}" + ("@2x" if scale == 2 else "") + ".png"
        img.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
img.resize((1024, 1024), Image.LANCZOS).save("/tmp/poltergeist-icon.png")
print("icon written")
