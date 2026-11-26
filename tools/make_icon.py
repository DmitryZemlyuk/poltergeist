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
def broom(d,A,B,length_b=132,w0=44,w1=132):
    """Classic flat 'corn' broom, as in the 🧹 emoji: stitched head, straws along it, fringed edge."""
    dx,dy=B[0]-A[0],B[1]-A[1]; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L; nx,ny=-uy,ux
    def at(along,across): return (B[0]+ux*along+nx*across, B[1]+uy*along+ny*across)
    def width(t): return w0+(w1-w0)*t
    # Handle (flat, as in the first version).
    hw=13
    poly(d,[(A[0]+nx*hw,A[1]+ny*hw),at(0,hw),at(0,-hw),(A[0]-nx*hw,A[1]-ny*hw)],(201,138,75,255))
    ell(d,A,hw,hw,(201,138,75,255))
    # Head with a fringed bottom edge.
    teeth=14
    edge=[]
    for i in range(teeth*2+1):
        f=i/(teeth*2)*2-1
        edge.append(at(length_b+(9 if i%2 else 0),(w1/2)*f))
    head=[at(0,-w0/2)]+edge+[at(0,w0/2)]
    poly(d,head,(242,194,92,255))
    # Straws along the head.
    for i in range(1,12):
        f=i/12*2-1
        d.line([(q(at(4,(w0/2)*f*0.9)[0]),q(at(4,(w0/2)*f*0.9)[1])),
                (q(at(length_b-2,(w1/2)*f*0.95)[0]),q(at(length_b-2,(w1/2)*f*0.95)[1]))],
               fill=(214,158,62,255),width=q(3))
    # Two rows of stitching across the head.
    for t in (0.28,0.5):
        h=width(t)/2-6
        a,b=at(length_b*t,-h),at(length_b*t,h)
        d.line([(q(a[0]),q(a[1])),(q(b[0]),q(b[1]))],fill=(176,62,46,255),width=q(4))
        for k in range(5):
            c=at(length_b*t,-h+2*h*(k+0.5)/5)
            poly(d,[(c[0]+ux*6+nx*2,c[1]+uy*6+ny*2),(c[0]-ux*6+nx*2,c[1]-uy*6+ny*2),
                    (c[0]-ux*6-nx*2,c[1]-uy*6-ny*2),(c[0]+ux*6-nx*2,c[1]+uy*6-ny*2)],(176,62,46,255))
    # Collar where the handle goes in.
    poly(d,[at(-16,w0/2-6),at(4,w0/2+2),at(4,-w0/2-2),at(-16,-w0/2+6)],(224,82,64,255))
    return (ux,uy,nx,ny,at(length_b,0))
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
    A=(720,470); B=(412,748)
    broom(d,A,B,length_b=124,w0=36,w1=118)
    for t in (0.12,0.5):
        c=point_on(A,B,t); ell(d,c,27,24,(255,255,255,255))
    star(d,(196,712),24,(255,255,255,255)); star(d,(440,872),14,(255,255,255,230))
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
