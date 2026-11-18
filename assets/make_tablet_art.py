from PIL import Image, ImageDraw, ImageFilter
import math
S=4; C=128; B=C*S
def cell(): return Image.new('RGBA',(B,B),(0,0,0,0))
def finish(im): return im.resize((C,C),Image.LANCZOS)

def mine(im, cx=B/2, cy=B/2, r=B*0.27):
    d=ImageDraw.Draw(im)
    for k in range(8):
        a=k*math.pi/4
        L=r*1.55 if k%2==0 else r*1.38
        w=int(r*0.26)
        d.line([(cx-math.cos(a)*L,cy-math.sin(a)*L),(cx+math.cos(a)*L,cy+math.sin(a)*L)],fill=(22,24,30,255),width=w)
        for sgn in (1,-1):
            ex,ey=cx+sgn*math.cos(a)*L,cy+sgn*math.sin(a)*L
            d.ellipse([ex-w*0.55,ey-w*0.55,ex+w*0.55,ey+w*0.55],fill=(22,24,30,255))
    d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=(30,32,40,255))
    # body shading
    sh=Image.new('RGBA',im.size,(0,0,0,0)); sd=ImageDraw.Draw(sh)
    for i in range(30):
        t=i/30; rr=r*(1-t*0.9)
        c=int(30+60*t)
        sd.ellipse([cx-rr-r*0.25*t,cy-rr-r*0.25*t,cx+rr-r*0.25*t,cy+rr-r*0.25*t],fill=(c,c+4,c+14,255))
    mask=Image.new('L',im.size,0); ImageDraw.Draw(mask).ellipse([cx-r,cy-r,cx+r,cy+r],fill=255)
    im.paste(sh,(0,0),mask)
    d=ImageDraw.Draw(im)
    hr=r*0.28
    d.ellipse([cx-r*0.45-hr,cy-r*0.45-hr,cx-r*0.45+hr,cy-r*0.45+hr],fill=(235,240,255,230))

def flag(im, cx=B/2, cy=B/2, s=1.0):
    d=ImageDraw.Draw(im)
    px=cx+B*0.06*s
    top=cy-B*0.33*s; bot=cy+B*0.26*s
    # base
    d.rounded_rectangle([cx-B*0.24*s,bot,cx+B*0.24*s,bot+B*0.08*s],radius=int(B*0.03*s),fill=(28,30,38,255))
    d.rounded_rectangle([cx-B*0.13*s,bot-B*0.05*s,cx+B*0.13*s,bot+B*0.02*s],radius=int(B*0.02*s),fill=(40,42,52,255))
    # pole
    d.rounded_rectangle([px-B*0.025*s,top,px+B*0.025*s,bot],radius=int(B*0.02*s),fill=(52,54,64,255))
    # flag cloth (wavy triangle)
    pts=[(px,top+B*0.01*s),(px-B*0.36*s,top+B*0.15*s),(px,top+B*0.30*s)]
    d.polygon(pts,fill=(232,52,58,255))
    d.polygon([(px,top+B*0.01*s),(px-B*0.36*s,top+B*0.15*s),(px-B*0.18*s,top+B*0.12*s)],fill=(255,96,96,255))

def cross(im):
    d=ImageDraw.Draw(im); w=int(B*0.08)
    m=B*0.18
    d.line([(m,m),(B-m,B-m)],fill=(255,70,60,255),width=w)
    d.line([(B-m,m),(m,B-m)],fill=(255,70,60,255),width=w)

def burst(im):
    d=ImageDraw.Draw(im); cx=cy=B/2
    pts=[]
    for k in range(24):
        a=k*math.pi/12; r=B*(0.48 if k%2==0 else 0.3)
        pts.append((cx+math.cos(a)*r,cy+math.sin(a)*r))
    d.polygon(pts,fill=(255,120,40,255))
    pts=[]
    for k in range(24):
        a=k*math.pi/12+0.13; r=B*(0.38 if k%2==0 else 0.22)
        pts.append((cx+math.cos(a)*r,cy+math.sin(a)*r))
    d.polygon(pts,fill=(255,214,80,255))

def face(im, kind):
    d=ImageDraw.Draw(im); cx=cy=B/2; r=B*0.42
    d.ellipse([cx-r-B*0.02,cy-r-B*0.02,cx+r+B*0.02,cy+r+B*0.02],fill=(40,30,10,255))
    d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=(255,206,60,255))
    d.ellipse([cx-r*0.8,cy-r*0.9,cx+r*0.5,cy+r*0.2],fill=(255,226,120,255))
    d.ellipse([cx-r*0.85,cy-r*0.85,cx+r*0.85,cy+r*0.85],outline=None)
    ink=(50,34,10,255); w=int(B*0.035)
    ex=r*0.36; ey=-r*0.2
    if kind=='happy':
        for sx in(-1,1):
            d.ellipse([cx+sx*ex-r*0.1,cy+ey-r*0.14,cx+sx*ex+r*0.1,cy+ey+r*0.14],fill=ink)
        d.arc([cx-r*0.5,cy-r*0.25,cx+r*0.5,cy+r*0.55],20,160,fill=ink,width=w)
    elif kind=='dead':
        for sx in(-1,1):
            x=cx+sx*ex; y=cy+ey; k=r*0.13
            d.line([(x-k,y-k),(x+k,y+k)],fill=ink,width=w); d.line([(x+k,y-k),(x-k,y+k)],fill=ink,width=w)
        d.arc([cx-r*0.4,cy+r*0.25,cx+r*0.4,cy+r*0.8],200,340,fill=ink,width=w)
    elif kind=='cool':
        d.rounded_rectangle([cx-r*0.72,cy+ey-r*0.16,cx-r*0.08,cy+ey+r*0.2],radius=int(r*0.12),fill=(20,20,26,255))
        d.rounded_rectangle([cx+r*0.08,cy+ey-r*0.16,cx+r*0.72,cy+ey+r*0.2],radius=int(r*0.12),fill=(20,20,26,255))
        d.line([(cx-r*0.1,cy+ey-r*0.08),(cx+r*0.1,cy+ey-r*0.08)],fill=(20,20,26,255),width=w)
        d.line([(cx-r*0.72,cy+ey-r*0.1),(cx-r*0.95,cy+ey-r*0.2)],fill=(20,20,26,255),width=w)
        d.line([(cx+r*0.72,cy+ey-r*0.1),(cx+r*0.95,cy+ey-r*0.2)],fill=(20,20,26,255),width=w)
        d.ellipse([cx-r*0.6,cy+ey-r*0.1,cx-r*0.45,cy+ey+r*0.02],fill=(140,160,200,255))
        d.arc([cx-r*0.5,cy-r*0.2,cx+r*0.5,cy+r*0.6],20,160,fill=ink,width=w)
    elif kind=='wow':
        for sx in(-1,1):
            d.ellipse([cx+sx*ex-r*0.11,cy+ey-r*0.15,cx+sx*ex+r*0.11,cy+ey+r*0.15],fill=ink)
        d.ellipse([cx-r*0.14,cy+r*0.22,cx+r*0.14,cy+r*0.56],fill=ink)

def appbg(im, c1, c2):
    g=Image.new('RGBA',(B,B))
    gd=ImageDraw.Draw(g)
    for y in range(B):
        t=y/B; gd.line([(0,y),(B,y)],fill=tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3))+(255,))
    mask=Image.new('L',(B,B),0); ImageDraw.Draw(mask).rounded_rectangle([B*0.02,B*0.02,B*0.98,B*0.98],radius=int(B*0.23),fill=255)
    # gloss
    gl=Image.new('RGBA',(B,B),(255,255,255,0)); gld=ImageDraw.Draw(gl)
    gld.ellipse([-B*0.3,-B*0.9,B*1.3,B*0.45],fill=(255,255,255,40))
    g.alpha_composite(gl)
    im.paste(g,(0,0),mask)

def stopwatch(im):
    d=ImageDraw.Draw(im); cx,cy=B/2,B*0.55; r=B*0.33; w=int(B*0.07)
    d.rounded_rectangle([cx-B*0.08,B*0.08,cx+B*0.08,B*0.16],radius=int(B*0.03),fill=(230,234,245,255))
    d.rectangle([cx-B*0.03,B*0.14,cx+B*0.03,cy-r+4],fill=(230,234,245,255))
    d.ellipse([cx-r,cy-r,cx+r,cy+r],outline=(230,234,245,255),width=w)
    d.line([(cx,cy),(cx,cy-r*0.6)],fill=(230,234,245,255),width=int(w*0.8))
    d.line([(cx,cy),(cx+r*0.45,cy+r*0.1)],fill=(230,234,245,255),width=int(w*0.8))

def bag(im):
    d=ImageDraw.Draw(im); cx=B/2
    d.arc([cx-B*0.16,B*0.16,cx+B*0.16,B*0.48],180,360,fill=(255,255,255,255),width=int(B*0.05))
    d.rounded_rectangle([cx-B*0.27,B*0.3,cx+B*0.27,B*0.82],radius=int(B*0.07),fill=(255,255,255,255))
    d.rounded_rectangle([cx-B*0.27,B*0.3,cx+B*0.27,B*0.4],radius=int(B*0.05),fill=(255,232,220,255))
    for sx in(-1,1):
        d.ellipse([cx+sx*B*0.14-B*0.03,B*0.43,cx+sx*B*0.14+B*0.03,B*0.49],fill=(238,82,120,255))
    d.arc([cx-B*0.14,B*0.32,cx+B*0.14,B*0.62],0,180,fill=(238,82,120,255),width=int(B*0.035))

cells=[]
im=cell(); mine(im); cells.append(im)                       # 0 mine
im=cell(); flag(im); cells.append(im)                       # 1 flag
im=cell(); mine(im); cross(im); cells.append(im)            # 2 wrong flag
im=cell(); burst(im); mine(im,r=B*0.22); cells.append(im)   # 3 exploded
for k in ('happy','dead','cool','wow'):                     # 4..7 faces
    im=cell(); face(im,k); cells.append(im)
# row 2
im=cell(); appbg(im,(96,110,150),(40,46,70))
# little tiles
d=ImageDraw.Draw(im)
for i in range(3):
    for j in range(3):
        x=B*0.17+i*B*0.23; y=B*0.17+j*B*0.23
        col=(150,165,200,255) if (i+j)%2==0 else (120,136,175,255)
        d.rounded_rectangle([x,y,x+B*0.2,y+B*0.2],radius=int(B*0.04),fill=col)
mine(im,cx=B*0.5,cy=B*0.5,r=B*0.15)
flag(im,cx=B*0.73,cy=B*0.29,s=0.3)
cells.append(im)                                            # 8 minesweeper app
im=cell(); appbg(im,(196,148,92),(110,70,36))
kn=Image.open('assets/chess-pieces.png').crop((3*128,0,4*128,128)).resize((int(B*0.82),int(B*0.82)),Image.LANCZOS)
sh=kn.copy(); sh=Image.merge('RGBA',(*[Image.new('L',sh.size,0)]*3,sh.split()[3].point(lambda a:a*0.35))).filter(ImageFilter.GaussianBlur(B*0.02))
im.alpha_composite(sh,(int(B*0.11),int(B*0.13))); im.alpha_composite(kn,(int(B*0.09),int(B*0.08)))
cells.append(im)                                            # 9 chess app
im=cell(); appbg(im,(255,159,67),(238,82,120)); bag(im); cells.append(im)  # 10 shop app
im=cell(); stopwatch(im); cells.append(im)                  # 11 stopwatch
im=cell(); flag(im); cells.append(im)                       # 12 (flag again for mode button)
for _ in range(3): cells.append(cell())
sheet=Image.new('RGBA',(C*8,C*2),(0,0,0,0))
for i,c in enumerate(cells):
    sheet.alpha_composite(finish(c),((i%8)*C,(i//8)*C))
sheet.save('tablet-art.png')
p=Image.new('RGBA',sheet.size,(60,66,84,255)); p.alpha_composite(sheet); p.convert('RGB').save('preview.png')
