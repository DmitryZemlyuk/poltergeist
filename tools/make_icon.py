#!/usr/bin/env python3
"""Draws the app icon (ghost with a broom inside a disk ring, on green) into Resources/AppIcon.iconset.
Flat layers only: on macOS 26 the system adds the glass highlight and shadow itself."""
import math, os
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
def broom(d,A,B,length_b=150,w0=36,w1=120):
    import random
    rnd=random.Random(7)
    dx,dy=B[0]-A[0],B[1]-A[1]; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L; nx,ny=-uy,ux
    def at(P,along,across): return (P[0]+ux*along+nx*across, P[1]+uy*along+ny*across)
    # Wooden handle: base tone, a lit side and a shaded side.
    hw=12
    poly(d,[at(A,0,hw),at(B,0,hw),at(B,0,-hw),at(A,0,-hw)],(170,108,56,255))
    poly(d,[at(A,0,-hw),at(B,0,-hw),at(B,0,-hw*0.25),at(A,0,-hw*0.25)],(206,146,86,255))
    poly(d,[at(A,0,hw*0.55),at(B,0,hw*0.55),at(B,0,hw),at(A,0,hw)],(140,86,42,255))
    ell(d,A,hw,hw,(170,108,56,255)); ell(d,at(A,0,-hw*0.45),hw*0.45,hw*0.45,(206,146,86,255))
    # Neck of tied straw, then the fanned bristles made of single straws.
    neck=34
    E=at(B,neck+length_b,0)
    tip_shift=10  # bristles bent a little, as if sweeping
    poly(d,[at(B,0,w0/2),at(B,neck,w0/2+2),at(E,0,w1/2+tip_shift),at(E,0,-w1/2+tip_shift),at(B,neck,-w0/2-2),at(B,0,-w0/2)],(214,158,58,255))
    tones=[(244,204,104),(226,172,72),(205,146,52),(250,220,132),(186,128,44)]
    n=58
    for i in range(n):
        f=i/(n-1)*2-1
        jitter=rnd.uniform(-0.03,0.03)
        start=at(B,rnd.uniform(0,neck*0.6),(w0/2)*(f+jitter))
        length=length_b+neck+rnd.uniform(-22,6)
        end=at(B,length,(w1/2)*(f+jitter)+tip_shift*(0.6+0.4*abs(f)))
        col=tones[rnd.randrange(len(tones))]
        d.line([(q(start[0]),q(start[1])),(q(end[0]),q(end[1]))],fill=col+(255,),width=q(rnd.choice((3,4,4,5))))
    # Shadow under the ties and two twine bands with stitches.
    poly(d,[at(B,neck,w0/2+2),at(B,neck+16,w0/2+7),at(B,neck+16,-w0/2-7),at(B,neck,-w0/2-2)],(178,122,40,255))
    for off in (6,neck-4):
        bw=9
        poly(d,[at(B,off-bw/2,w0/2+4),at(B,off+bw/2,w0/2+4),at(B,off+bw/2,-w0/2-4),at(B,off-bw/2,-w0/2-4)],(176,58,44,255))
        for k in range(5):
            c=at(B,off,(k-2)*w0/5)
            ell(d,c,2.2,2.2,(120,36,28,255))
    return (ux,uy,nx,ny,E)
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
def variant_a():
    bg,img=base((100,210,168),(15,143,110)); d=ImageDraw.Draw(img)
    r,w=312,31; ring=(q(512-r),q(512-r),q(512+r),q(512+r))
    d.arc(ring,start=-90,end=-90+360*0.72,fill=(255,255,255,255),width=q(w))
    d.arc(ring,start=-90+360*0.745,end=-90+360*0.975,fill=(255,214,10,255),width=q(w))
    s=19; pts,p=ghost_pts(512-12*s+20,505-12*s,s)
    poly(d,pts,(255,255,255,255)); eyes(d,p,s,look=-0.7)
    A=(720,470); B=(430,732)
    broom(d,A,B,length_b=104,w0=32,w1=116)
    for t in (0.12,0.5):
        c=point_on(A,B,t); ell(d,c,27,24,(255,255,255,255))
    star(d,(232,796),24,(255,255,255,255)); star(d,(335,888),13,(255,255,255,230))
    return finish(bg,img)

img = variant_a()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base * scale
        name = f"icon_{base}x{base}" + ("@2x" if scale == 2 else "") + ".png"
        img.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
img.resize((1024, 1024), Image.LANCZOS).save("/tmp/poltergeist-icon.png")
print("icon written")
