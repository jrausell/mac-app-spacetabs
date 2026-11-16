from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from html import escape
import math, json, textwrap

OUT=Path(__file__).resolve().parent
FONT='/System/Library/Fonts/SFNS.ttf'
BOLD=FONT
SYMBOL='/System/Library/Fonts/Supplemental/Arial Unicode.ttf'
BG='#f6f7fb'; PANEL='#ffffff'; EDGE='#dce0e9'; INK='#263044'; MUTED='#788195'
Z={'A':'#f7b545','B':'#6495f5','C':'#42c5a2'}
APPS={'Browser':'#93c5fd','Editor':'#c4b5fd','Notes':'#fbbf24','Terminal':'#6ee7b7','Finder':'#80c9f7','Messages':'#a5e0b6','Preview':'#efb1c6'}

class Canvas:
 def __init__(self,w,h,bg=BG):
  self.w=w;self.h=h;self.parts=[];self.im=Image.new('RGB',(w,h),bg);self.d=ImageDraw.Draw(self.im);self.rect(0,0,w,h,bg)
 def rect(self,x,y,w,h,fill,stroke=None,r=0,sw=1,dash=False):
  x,y,w,h=map(float,(x,y,w,h)); attr=f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
  if dash:attr+=' stroke-dasharray="6 5"'
  self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or "none"}"{attr}/>')
  self.d.rounded_rectangle((x,y,x+w,y+h),radius=r,fill=fill,outline=stroke,width=sw)
 def text(self,x,y,t,size=16,color=INK,bold=False,anchor='start'):
  self.parts.append(f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" font-weight="{700 if bold else 400}" text-anchor="{anchor}">{escape(str(t))}</text>')
  f=ImageFont.truetype(BOLD if bold else FONT,size)
  if any(ord(ch)>8000 for ch in str(t)):f=ImageFont.truetype(SYMBOL,size)
  a={'start':'ls','middle':'ms','end':'rs'}[anchor]
  self.d.text((x,y),str(t),font=f,fill=color,anchor=a)
 def line(self,x1,y1,x2,y2,color=EDGE,sw=2,dash=False):
  self.parts.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{sw}"'+(' stroke-dasharray="6 5"' if dash else '')+'/>')
  if dash:
   n=max(1,int(math.hypot(x2-x1,y2-y1)/8))
   for i in range(0,n,2):self.d.line((x1+(x2-x1)*i/n,y1+(y2-y1)*i/n,x1+(x2-x1)*min(i+1,n)/n,y1+(y2-y1)*min(i+1,n)/n),fill=color,width=sw)
  else:self.d.line((x1,y1,x2,y2),fill=color,width=sw)
 def poly(self,pts,fill,stroke=None):
  self.parts.append(f'<polygon points="'+ ' '.join(f'{x},{y}' for x,y in pts)+f'" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')
  self.d.polygon(pts,fill=fill,outline=stroke)
 def arrow(self,x1,y1,x2,y2,color=INK,sw=3):
  self.line(x1,y1,x2,y2,color,sw)
  a=math.atan2(y2-y1,x2-x1);r=10
  self.poly([(x2,y2),(x2-r*math.cos(a-.5),y2-r*math.sin(a-.5)),(x2-r*math.cos(a+.5),y2-r*math.sin(a+.5))],color)
 def cursor(self,x,y):
  self.poly([(x,y),(x+6,y+26),(x+12,y+18),(x+23,y+20)],INK,BG)
 def pill(self,x,y,w,text,color=INK,fill='#23364a',size=14):
  self.rect(x,y,w,28,fill,EDGE,7);self.text(x+w/2,y+19,text,size,color,True,'middle')
 def svg(self,title):
  return f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}" role="img" aria-labelledby="title"><title id="title">{escape(title)}</title><g font-family="Arial, Helvetica, sans-serif">'+''.join(self.parts)+'</g></svg>'

SCREEN_W = 720
SCREEN_H = 405
MENU_H = 24
DOCK_TOP = 371
GUTTER = 6


def arc(c,cx,cy,r,start,end,color=INK,sw=1):
 points=[(cx+r*math.cos(math.radians(start+(end-start)*i/20)),cy+r*math.sin(math.radians(start+(end-start)*i/20))) for i in range(21)]
 for a,b in zip(points,points[1:]):c.line(*a,*b,color,sw)


def status_icons(c):
 # A small monochrome system-status row keeps the desktop unmistakably macOS.
 c.rect(482,7,14,10,None,INK,2)
 c.line(487,7,487,17,INK,1)
 c.line(482,12,487,12,INK,1)
 x=515
 for a,b in [((x,6),(x,19)),((x,6),(x+5,10)),((x+5,10),(x-4,16)),((x-4,8),(x+5,15)),((x+5,15),(x,19))]:c.line(*a,*b,INK,1)
 for r in (4,7,10):arc(c,545,17,r,225,315,INK,.9)
 c.rect(544,16,2,2,INK,None,1)
 c.rect(568,8,18,9,None,INK,2)
 c.rect(570,10,11,5,INK,None,1)
 c.rect(587,10,2,5,INK,None,1)
 for yy,knob in [(7,605),(14,611)]:
  c.rect(601,yy,15,5,None,INK,3)
  c.rect(knob,yy+1,3,3,INK,None,2)
 arc(c,639,11,4,0,360,INK,1)
 c.line(642,14,646,18,INK,1)
 c.text(705,17,'9:41',9,INK,anchor='end')


def desktop(c):
 # A quiet peach-to-lavender desktop, drawn locally without stock artwork.
 for yy in range(SCREEN_H):
  t=yy/SCREEN_H
  color=tuple(round(a+(b-a)*t) for a,b in zip((248,210,190),(186,196,230)))
  c.rect(0,yy,SCREEN_W,1,color)
 c.rect(0,0,SCREEN_W,MENU_H,'#f2e5e4')
 c.line(0,MENU_H,SCREEN_W,MENU_H,'#ffffff',.5)
 c.text(13,19,'\uf8ff',15,INK)
 c.text(38,17,'SpaceTabs',10,INK,True)
 c.text(98,17,'File    Edit    View    Window    Help',9,INK)
 status_icons(c)
 c.rect(244,371,232,29,'#e7e4ee','#f9f7fb',9,.6)
 for i,app in enumerate(['Finder','Browser','Notes','Editor','Terminal','Messages','SpaceTabs']):
  xx=254+i*31
  icon(c,app,xx,376,21)
  c.rect(xx+9,399,2,2,'#727787',None,1)


def icon(c,app,x,y,size):
 colors={'Finder':'#55b4f5','Browser':'#218aff','Notes':'#ffbf16','Editor':'#597cf3','Terminal':'#292c35','Messages':'#a34bea','SpaceTabs':'#5778e8'}
 c.rect(x,y,size,size,colors.get(app,'#d57aa4'),None,size*.25)
 if app=='SpaceTabs':
  c.rect(x+size*.19,y+size*.2,size*.22,size*.25,'#ffc65d',None,1)
  c.rect(x+size*.19,y+size*.54,size*.22,size*.25,'#5cdec0',None,1)
  c.rect(x+size*.5,y+size*.2,size*.31,size*.59,'#ffffff',None,1)
 elif app=='Notes':
  for i in range(3):c.line(x+size*.25,y+size*(.38+i*.15),x+size*.75,y+size*(.38+i*.15),'#745c22',1)
 elif app=='Browser':
  arc(c,x+size/2,y+size/2,size*.34,0,360,'#ffffff',1)
  c.poly([(x+size*.64,y+size*.28),(x+size*.42,y+size*.57),(x+size*.32,y+size*.72),(x+size*.59,y+size*.48)],'#ffffff')
 elif app=='Messages':
  c.rect(x+size*.22,y+size*.23,size*.56,size*.43,'#ffffff',None,2)
  c.poly([(x+size*.3,y+size*.6),(x+size*.3,y+size*.8),(x+size*.48,y+size*.6)],'#ffffff')
 else:c.text(x+size/2,y+size*.69,'>_' if app=='Terminal' else '<>' if app=='Editor' else ':)',round(size*.43),'#ffffff',True,'middle')


def content(c,app,x,y,w,h):
 # Abstract app content stays recognizable at video size without fake fine print.
 if w<35 or h<22:return
 pad=min(14,w*.07);left=x+pad;top=y+pad;usable=w-2*pad
 if app=='Terminal':
  c.rect(x,y,w,h,'#202229')
  size=min(10,w/25)
  for i,(text,color) in enumerate([('~/project > swift build','#f3c35e'),('Building SpaceTabs…','#b7bdc9'),('Build complete.','#58d4ac'),('~/project > _','#f3c35e')]):
   if pad+14+i*20<h-6:c.text(left,top+14+i*20,text,round(size),color)
 elif app=='Editor':
  sidebar=min(65,w*.21)
  c.rect(x,y,sidebar,h,'#f0f1f6')
  for i in range(min(6,int((h-22)/17))):
   c.rect(x+8,y+12+i*17,sidebar-16,6,'#c9d0e0' if i else '#b9cef8',None,3)
  palette=['#b16af0','#5d97fa','#f4b534','#2bc6a3','#fa678f']
  xx=x+sidebar+14;available=w-sidebar-28
  for row in range(min(10,int((h-22)/18))):
   if row in [4,8]:continue
   indent=10 if row%4 in [1,2] else 0
   c.rect(xx+indent,y+14+row*18,available*(.32 if row%3==0 else .46),7,palette[row%5],None,4)
   if available>100:c.rect(xx+indent+available*.5,y+14+row*18,available*.3,7,palette[(row+1)%5],None,4)
 elif app=='Notes':
  c.rect(left,top,28,13,'#ffc629',None,3)
  c.rect(left+38,top+3,usable*.46,7,'#777b84',None,3)
  for i in range(min(5,int((h-42)/15))):
   c.rect(left,top+29+i*15,usable*(.95-i*.09),5,'#d7d9df',None,3)
 elif app=='Finder':
  sidebar=w*.24;c.rect(x,y,sidebar,h,'#f1f3f8')
  for i in range(min(4,int((h-12)/19))):c.rect(x+8,y+12+i*19,sidebar-16,5,'#cbd2df',None,2)
  for i in range(6):
   xx=x+sidebar+16+(i%3)*(w-sidebar-25)/3;yy=y+17+(i//3)*49
   if yy+30>y+h:break
   c.rect(xx,yy-3,11,5,'#82c9fa',None,2);c.rect(xx,yy,27,21,'#67b9f2',None,3)
   c.rect(xx,yy+29,25,3,'#bec7d5',None,2)
 elif app=='Browser':
  c.rect(left,top,usable,13,'#f0f2f7',None,5)
  c.rect(left+usable*.25,top+5,usable*.5,3,'#c2cad9',None,2)
  hh=min(65,h*.32)
  c.rect(left,top+24,usable,hh,'#e9edff',None,5)
  c.rect(left+12,top+37,usable*.58,8,'#7993d9',None,4)
  if hh>35:c.rect(left+12,top+55,usable*.76,5,'#bcc8eb',None,3)
  for i in range(3):
   yy=top+hh+37+i*15
   if yy+5<y+h-9:c.rect(left,yy,usable*(.94-i*.13),5,'#d5dae4',None,3)
 elif app=='Preview':
  pw=min(w*.57,h*.63);ph=min(h-20,pw*1.25);px=x+(w-pw)/2;py=y+10
  c.rect(px+2,py+3,pw,ph,'#e4e7ee',None,3);c.rect(px,py,pw,ph,'#f7f5f1','#e0e2e8',3)
  c.rect(px+pw*.14,py+ph*.13,pw*.72,ph*.34,'#b9c7f1',None,3)
  for i in range(3):c.rect(px+pw*.14,py+ph*.59+i*8,pw*(.68-i*.1),3,'#c4c8d0',None,1)
 else:
  sidebar=min(40,w*.22);c.rect(x,y,sidebar,h,'#73538f')
  for i in range(min(5,int((h-20)/30))):
   yy=y+12+i*30
   c.rect(x+8,yy,sidebar-16,7,'#9b71c0',None,3)
   xx=x+sidebar+12
   c.rect(xx,yy,12,12,['#5d97fa','#ffb239','#2bc6a3'][i%3],None,4)
   c.rect(xx+20,yy, max(4,(w-sidebar-40)*.52),6,'#9296a0',None,3)
   c.rect(xx+20,yy+11,max(4,(w-sidebar-40)*.85),4,'#d8dbe2',None,2)


def appwin(c,app,x,y,w,h,selected=False):
 # Low-contrast layered shadows keep overlapping windows easy to read.
 c.rect(x-1,y+3,w+2,h,'#c8c7d5',None,9)
 c.rect(x,y,w,h,'#ffffff','#dce0e8',9,.6)
 if h>50:content(c,app,x+1,y+24,w-2,h-27)
 c.rect(x+.5,y+.5,w-1,23,'#f7f7f9',None,8)
 c.rect(x+1,y+14,w-2,9,'#f7f7f9')
 c.line(x+1,y+23,x+w-1,y+23,'#e4e6ec',.5)
 for i,color in enumerate(['#ff625b','#ffbd36','#2aca48']):c.rect(x+10+i*11,y+8,6,6,color,None,3)
 c.text(x+w/2,y+16,app,10,'#626772',False,'middle')


RECTS={'A':(6,30,216,164),'C':(6,200,216,165),'B':(228,30,486,335)}
TWO={'A':(6,30,216,335),'B':(228,30,486,335)}

def workspace(c,layout='split',apps=None,active=None,bars=True,empty=False):
 desktop(c)
 rs=RECTS if layout=='split' else TWO
 apps=apps or {'A':['Notes','Finder'],'C':['Terminal','Messages'],'B':['Editor','Browser','Preview']}
 active=active or {'A':'Notes','C':'Terminal','B':'Editor'}
 for z,(x,y,w,h) in rs.items():
  c.rect(x,y,w,h,'#192b3e',Z[z],7)
  if bars:
   c.rect(x+1,y+1,w-2,27,'#263a4f',None,6)
   c.rect(x+5,y+5,20,18,Z[z],None,4);c.text(x+15,y+18,z,11,BG,True,'middle')
   xx=x+33
   for app in apps.get(z,[]):
    label=app;tw=57 if app in ['Terminal','Messages','Browser'] else 48
    if xx+tw>x+w-25:break
    sel=active.get(z)==app
    if sel:c.rect(xx,y+4,tw,20,Z[z],None,4)
    c.text(xx+tw/2,y+18,label,10,BG if sel else '#d1deeb',sel,'middle');xx+=tw+3
   c.text(x+w-12,y+20,'+',18,MUTED,anchor='middle')
  if not empty and active.get(z) and active[z] in apps.get(z,[]):
   yy=y+32 if bars else y+4
   appwin(c,active[z],x+4,yy,w-8,h-(yy-y)-4)
  elif empty or not apps.get(z):
   c.text(x+w/2,y+h/2+15,z,40,'#36526c',True,'middle')
 return rs

def label(c,txt):c.pill(190,377,340,txt,size=14)
