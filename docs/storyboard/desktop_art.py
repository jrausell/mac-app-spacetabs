"""Mac desktop illustration with independent tab panels and native app-window chrome."""
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import render_concept as art

S=art.S
COLORS={'A':'#ffbf47','B':'#70adff','C':'#55e3ad'}
RECTS={'A':(22,66,600,438),'B':(646,66,1252,900),'C':(22,528,600,438)}
TWO={'A':(22,66,600,900),'B':RECTS['B']}
TABS={'A':('Notes','Finder'),'B':('Editor','Browser','Preview'),'C':('Terminal','Messages')}
KINDS={'Notes':'notes','Finder':'finder','Editor':'editor','Browser':'browser','Preview':'preview','Terminal':'terminal','Messages':'messages'}


def canvas(transparent=False):
    f=art.Frame.__new__(art.Frame)
    f.im=Image.new('RGBA' if transparent else 'RGB',(1920*S,1080*S),(0,0,0,0) if transparent else '#dfe8f4')
    f.d=ImageDraw.Draw(f.im)
    return f


def copy(im):
    f=art.Frame.__new__(art.Frame);f.im=im.copy();f.d=ImageDraw.Draw(f.im);return f


@lru_cache(maxsize=16)
def logo(size):
    with Image.open(art.ROOT/'Resources/icon-main-transparent.png') as im:
        return im.convert('RGBA').resize((size*S,size*S),Image.Resampling.LANCZOS)


def paste(f,im,x,y,opacity=1):
    if opacity<=0:return
    if opacity<1:
        im=im.copy();im.putalpha(im.getchannel('A').point(lambda a:round(a*opacity)))
    f.im.paste(im,(round(x*S),round(y*S)),im);f.d=ImageDraw.Draw(f.im)


def icon(f,name,x,y,size=48):
    if name=='SpaceTabs':paste(f,logo(size),x,y);return
    colors={'Finder':'#47a7e8','Browser':'#2a7ee6','Notes':'#f4c34e','Editor':'#697de0','Terminal':'#292d35','Messages':'#49ba8d','Preview':'#a68bd6'}
    f.box(x,y,size,size,colors[name],size*.22)
    cx,cy=x+size/2,y+size/2
    if name=='Browser':
        f.d.ellipse(((x+8)*S,(y+8)*S,(x+size-8)*S,(y+size-8)*S),outline='#ffffff',width=2*S)
        f.d.polygon([(round(a*S),round(b*S)) for a,b in [(cx+9,cy-13),(cx+4,cy+5),(cx-9,cy+13),(cx-4,cy-5)]],fill='#ffffff')
    elif name=='Notes':
        f.box(x+9,y+12,size-18,size-23,'#fffbee',3)
        for i in range(3):f.box(x+14,y+20+i*7,size-28,2,'#b6aa86',1)
    elif name=='Messages':
        f.box(x+9,y+11,size-18,size-23,'#ffffff',8)
        f.d.polygon([((x+14)*S,(y+26)*S),((x+14)*S,(y+39)*S),((x+26)*S,(y+26)*S)],fill='#ffffff')
    elif name=='Preview':
        f.box(x+11,y+8,size-22,size-16,'#ffffff',2)
        f.box(x+15,y+13,size-30,13,'#97bad4',2)
    else:
        label='>_' if name=='Terminal' else '<>' if name=='Editor' else ':)'
        f.text(x+size*.19,y+size*.3,label,round(size*.37),'#ffffff',True,name=='Terminal')


@lru_cache(maxsize=8)
def desktop(owner='SpaceTabs'):
    f=canvas()
    # Cool, restrained wallpaper drawn from broad curves, independent of the reference imagery.
    f.d.ellipse((-680*S,230*S,2050*S,2390*S),fill='#c2d3e7')
    f.d.ellipse((540*S,-500*S,2800*S,1370*S),fill='#aebfd8')
    f.d.ellipse((950*S,-230*S,2700*S,1030*S),fill='#d3deed')
    f.box(0,0,1920,40,'#eef2f8')
    af=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',26*S)
    f.d.text((18*S,6*S),'\uf8ff',font=af,fill='#283245',anchor='lt')
    f.text(61,12,owner,19,'#253045',True)
    mx=max(180,84+len(owner)*12)
    f.text(mx,13,'File     Edit     View     Window     Help',17,'#354057')
    f.text(1534,13,'Wi-Fi',15,'#354057')
    f.box(1601,13,29,14,None,3,'#354057');f.box(1604,16,20,8,'#354057',1)
    f.box(1632,17,3,6,'#354057',1)
    f.text(1670,13,'Sun 9:41',17,'#354057')
    # SpaceTabs status symbol is a miniature of the three-zone arrangement.
    f.box(1464,11,24,18,None,3,'#354057')
    f.box(1469,15,5,4,'#354057',1);f.box(1469,22,5,4,'#354057',1);f.box(1477,15,7,11,'#354057',1)
    f.box(658,992,604,74,'#e8edf5',18,'#f8fafc')
    names=['Finder','Browser','Notes','Editor','Terminal','Messages','Preview','SpaceTabs']
    for i,name in enumerate(names):
        xx=675+i*72
        icon(f,name,xx,1002,49)
        f.d.ellipse(((xx+23)*S,1056*S,(xx+26)*S,1059*S),fill='#7c879b')
    return f.im


def border(f,zone,rect,opacity=1,highlight=False):
    if opacity<1:
        layer=canvas(True);border(layer,zone,rect,highlight=highlight);paste(f,layer.im,0,0,opacity);return
    x,y,w,h=rect
    f.d.rounded_rectangle((round(x*S),round(y*S),round((x+w)*S),round((y+h)*S)),radius=12*S,
                         outline=COLORS[zone],width=(4 if highlight else 2)*S)


def panel(f,zone,rect,tabs=(),active='',opacity=1):
    if opacity<1:
        layer=canvas(True);panel(layer,zone,rect,tabs,active);paste(f,layer.im,0,0,opacity);return
    x,y,w,_=rect;x+=8;y+=8;w-=16
    f.box(x,y,w,53,'#34373d',8,'#292c32')
    f.text(x+18,y+17,zone,20,COLORS[zone],True)
    xx=x+55
    for name in tabs:
        width=max(98,round(art.font(17,True).getlength(name)/S)+36)
        if name==active:
            f.box(xx-8,y+10,width,34,'#555c69',6)
            f.box(xx-8,y+46,width,2,COLORS[zone])
        f.text(xx,y+18,name,17,'#ffffff' if name==active else '#c7cbd3',name==active)
        xx+=width+10
    f.text(x+w-30,y+15,'+',23,'#d5d9e1')


def content_rect(rect,auto=False):
    x,y,w,h=rect
    top=8 if auto else 74
    return x+8,y+top,w-16,h-top-8


@lru_cache(maxsize=32)
def window(name,w,h):
    f=canvas(True)
    # Reuse the approved native-window treatment; crop away the unused tab-panel area.
    kind=KINDS[name]
    art.tab_group(f,16,0,w,h+66,'B',(),name,kind if kind in ['notes','terminal','editor','browser'] else 'editor',panel=False)
    if name in ['Finder','Preview','Messages']:
        x,y=17,105
        f.box(x,y,w-2,h-40,'#ffffff')
        if name=='Finder':
            f.box(x,y,160,h-40,'#f0f2f6')
            for i,label in enumerate(['Favorites','Desktop','Documents','Downloads']):f.text(x+15,y+23+i*35,label,17,art.MUTED,i==0)
            for i,label in enumerate(['Ideas','Design','Projects','Notes','Archive','Media']):
                xx=x+210+(i%3)*min(160,(w-200)/3);yy=y+40+(i//3)*110
                if yy+85>y+h-55:break
                f.box(xx,yy,64,45,'#78bbed',6);f.box(xx,yy-6,27,12,'#94cff7',4)
                f.text(xx,yy+59,label,17,art.MUTED)
        elif name=='Preview':
            pw=min(w*.58,(h-80)*.7);ph=pw*1.2;xx=x+(w-pw)/2;yy=y+20
            f.box(xx,yy,pw,ph,'#f7f5f1',4,'#dde1e8')
            f.text(xx+24,yy+28,'Project notes',24,bold=True)
            for i,label in enumerate(['A clearer workspace','A place for each task','Room to focus']):
                if yy+90+i*35<yy+ph-20:f.text(xx+24,yy+90+i*35,label,17,art.MUTED)
        else:
            f.box(x,y,130,h-40,'#efedf6')
            for i,label in enumerate(['Team','Design','Ideas']):f.text(x+18,y+28+i*42,label,17,art.MUTED)
            for i,label in enumerate(['How is the workspace coming along?','Much clearer. Everything has a place.','Ready to get back to it.']):
                if y+40+i*80<y+h-80:
                    f.box(x+160,y+30+i*80,w-190,56,'#eef2fa',8)
                    f.text(x+175,y+48+i*80,label,17,art.INK)
        # Correct the native title after drawing app-specific content.
        f.box(110,67,w-180,36,'#f7f7f8')
        tw=f.d.textlength(name,font=art.font(15))/S
        f.text(16+(w-tw)/2,78,name,15,art.MUTED)
    return f.im.crop((0,54*S,(w+32)*S,(h+80)*S))


def app(f,name,rect,opacity=1):
    x,y,w,h=rect
    # Quantization bounds the sprite cache while keeping eased movement continuous.
    ww=max(240,round(w/8)*8);hh=max(190,round(h/8)*8)
    paste(f,window(name,ww,hh),x-16,y-12,opacity)


@lru_cache(maxsize=14)
def workspace(active=('Notes','Editor','Terminal'),bars=True,auto=False,moved=False):
    f=copy(desktop(active[1]))
    for zone,name in zip(('A','B','C'),active):
        border(f,zone,RECTS[zone])
        app(f,name,content_rect(RECTS[zone],auto))
        if bars:
            tabs=TABS[zone]
            if moved and zone=='B':tabs=('Editor','Browser')
            if moved and zone=='C':tabs=('Preview','Terminal','Messages')
            panel(f,zone,RECTS[zone],tabs,name)
    return f.im


def pointer(f,x,y,click=0):
    if click:
        r=8+20*click
        f.d.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),outline='#ffffff',width=2*S)
    pts=[(x,y),(x,y+26),(x+6,y+19),(x+13,y+31),(x+19,y+28),(x+12,y+16),(x+24,y+16)]
    f.d.polygon([(round(a*S),round(b*S)) for a,b in pts],fill='#ffffff',outline='#222936',width=2*S)


def ghost(f,rect,zone):
    x,y,w,h=rect
    f.d.rounded_rectangle((round(x*S),round(y*S),round((x+w)*S),round((y+h)*S)),radius=11*S,outline=COLORS[zone],width=3*S)


def keycaps(f,label,note=''):
    tw=f.d.textlength(label,font=art.font(25,True))/S
    w=max(350,tw+64);x=(1920-w)/2;y=882
    f.box(x,y,w,68,'#292f3b',12,'#69758a')
    f.text(x+32,y+22,label,25,'#ffffff',True)
    if note:f.text(x+20,y-32,note,20,'#263044',True)
