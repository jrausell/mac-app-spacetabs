#!/usr/bin/env python3
"""Render the approved schematic presentation with Pillow and local FFmpeg.

Requires Python 3, Pillow, and FFmpeg. No desktop capture, app automation,
network assets, or changes to the running SpaceTabs configuration are used.
"""
from __future__ import annotations

import argparse
from array import array
from functools import lru_cache
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import time
import wave

sys.dont_write_bytecode = True

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import video_drawing as ui

ROOT = Path(__file__).resolve().parents[2]
W, H = 1920, 1080
SCALE = 3
FPS = 30
DURATION = 70
BACKGROUND = '#f6f7fb'
TIMES = [0, 5, 10, 15, 21, 27, 31, 37, 43, 49, 56, 66, 70]
TITLES = ['A familiar kind of clutter', 'A place for every window', 'Arrange it your way',
          'Your browser, right here', 'Your notes, beside your work',
          'More apps. The same clear desktop.', 'Change one space. Keep the rest.',
          'Your usual app switching still works.', 'Prefer your tab bars out of sight?',
          'Hold Control. Right-drag. Drop.', 'Less reaching. More doing.',
          'Your windows. Your zones. One desktop.']
DEFAULT_APPS = (('A', ('Notes', 'Finder')), ('B', ('Editor', 'Browser', 'Preview')), ('C', ('Terminal', 'Messages')))
DEFAULT_ACTIVE = (('A', 'Notes'), ('B', 'Editor'), ('C', 'Terminal'))


def clamp(t): return max(0.0, min(1.0, t))
def ease(t):
    t = clamp(t)
    return t*t*(3-2*t)
def mix(a, b, t): return a+(b-a)*ease(t)
def tuple_map(d): return tuple((k, tuple(v) if isinstance(v, list) else v) for k, v in d.items())


@lru_cache(maxsize=128)
def font(size, bold=False):
    result = ImageFont.truetype(ui.FONT, round(size))
    result.set_variation_by_name(b'Semibold' if bold else b'Regular')
    return result


class ScaledDraw:
    def __init__(self, im): self.draw = ImageDraw.Draw(im)
    def rounded_rectangle(self, xy, radius=0, fill=None, outline=None, width=1):
        self.draw.rounded_rectangle(tuple(v*SCALE for v in xy), radius=radius*SCALE,
                                    fill=fill, outline=outline, width=max(1, round(width*SCALE)))
    def polygon(self, pts, fill=None, outline=None):
        self.draw.polygon([(x*SCALE,y*SCALE) for x,y in pts], fill=fill, outline=outline)
    def line(self, xy, fill=None, width=1):
        self.draw.line(tuple(v*SCALE for v in xy), fill=fill, width=max(1,round(width*SCALE)))


class Canvas(ui.Canvas):
    def __init__(self, w=720, h=405, bg=ui.BG):
        self.w=w; self.h=h; self.parts=[]
        self.im=Image.new('RGBA',(round(w*SCALE),round(h*SCALE)), bg or (0,0,0,0))
        self.d=ScaledDraw(self.im)
    def text(self,x,y,t,size=16,color=ui.INK,bold=False,anchor='start'):
        f=font(size*SCALE,bold)
        if t == '\uf8ff':
            f=apple_font(size*SCALE)
        elif any(ord(ch)>8000 for ch in str(t)):
            f=symbol_font(size*SCALE)
        ImageDraw.Draw(self.im).text((x*SCALE,y*SCALE),str(t),font=f,fill=color,
                                    anchor={'start':'ls','middle':'ms','end':'rs'}[anchor])


@lru_cache(maxsize=16)
def apple_font(size):
    return ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',size)


@lru_cache(maxsize=32)
def symbol_font(size): return ImageFont.truetype(ui.SYMBOL,size)


def alpha_paste(im, layer, xy=(0,0), opacity=1):
    if opacity <= 0: return
    if opacity < 1:
        layer=layer.copy()
        layer.putalpha(layer.getchannel('A').point(lambda v: round(v*clamp(opacity))))
    im.alpha_composite(layer,(round(xy[0]),round(xy[1])))


def overlay(im, draw, opacity=1):
    c=Canvas(bg=None); draw(c); alpha_paste(im,c.im,opacity=opacity)


def bar(c,z,rect,apps,active):
    x,y,w,h=rect
    c.rect(x+1,y+1,w-2,23,'#f5f6fa',None,6)
    c.rect(x+5,y+4,18,17,ui.Z[z],None,4)
    c.text(x+14,y+17,z,10,'#102235',True,'middle')
    xx=x+30
    for app in apps:
        tw=59 if app in ['Terminal','Messages','Browser'] else 48
        if xx+tw>x+w-22: break
        selected=active==app
        if selected:c.rect(xx,y+3,tw,19,ui.Z[z],None,5)
        c.text(xx+tw/2,y+17,app,9,'#102235' if selected else '#717c91',selected,'middle')
        xx+=tw+3
    c.text(x+w-12,y+17,'+',15,ui.MUTED,anchor='middle')


def content_rect(z):
    x,y,w,h=ui.RECTS[z]
    return x+1,y+28,w-2,h-29


def draw_workspace(rects, apps, active, bars='fixed'):
    c=Canvas();ui.desktop(c)
    for z,rect in rects.items():
        x,y,w,h=rect
        if h<2: continue
        c.rect(x,y,w,h,'#eef1f8',ui.Z[z],7,.6)
        if bars=='fixed' and h>24:bar(c,z,rect,apps.get(z,()),active.get(z))
        app=active.get(z)
        if app and app in apps.get(z,()):
            yy=y+28 if bars=='fixed' else y+1
            ui.appwin(c,app,x+1,yy,w-2,h-(yy-y)-1)
        elif h>65:
            c.text(x+w/2,y+h/2+12,z,30,'#b9c3d7',True,'middle')
    if bars=='floating':
        for z,rect in rects.items():bar(c,z,rect,apps.get(z,()),active.get(z))
    return c.im

@lru_cache(maxsize=72)
def workspace(apps=DEFAULT_APPS,active=DEFAULT_ACTIVE,bars='fixed',two=False):
    return draw_workspace(ui.TWO if two else ui.RECTS,dict(apps),dict(active),bars)


@lru_cache(maxsize=32)
def sprite(app,w,h):
    c=Canvas(w,h,None);ui.appwin(c,app,0,0,w,h,True)
    return c.im


def window(im,app,x,y,w,h,opacity=1):
    # Fixed sprites stay crisp while their placement animates.
    source=sprite(app,round(w),round(h))
    alpha_paste(im,source,(x*SCALE,y*SCALE),opacity)


def cursor(im,x,y,pressed=False,pulse=0):
    def draw(c):
        if pulse>0:
            radius=4+12*pulse
            c.rect(x-radius,y-radius,2*radius,2*radius,None,ui.Z['B'],radius,.65)
        # A compact native-shaped pointer, rather than a large presentation arrow.
        c.poly([(x,y),(x,y+16),(x+4,y+12),(x+8,y+20),(x+11,y+18),(x+7,y+11),(x+14,y+11)],
               '#f5f8fc','#07111d')
    overlay(im,draw)


def click_pulse(im,x,y,t):
    if 0<t<.5:
        p=t/.5
        def ring(c):
            r=4+13*ease(p)
            ui.arc(c,x,y,r,0,360,ui.Z['B'],1)
        overlay(im,ring,1-p)


def ghost(im,rect,z='B',opacity=1):
    x,y,w,h=rect
    def outline(c):
        c.rect(x,y,w,h,None,ui.Z[z],5,1)
        for xx,yy in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)]:
            c.rect(xx-1,yy-1,2,2,ui.Z[z],None,1)
    overlay(im,outline,opacity)


def glide(t):
    p=clamp(t)
    return 1-(1-p)**4


def pointer_path(a,b,p,bend=-16):
    p=glide(p)
    return a[0]+(b[0]-a[0])*p, a[1]+(b[1]-a[1])*p+math.sin(p*math.pi)*bend

def blend(a,b,t):return Image.blend(a,b,ease(t))


def assignment(t,second=False):
    before_apps=(('A',()),('B',('Browser',) if second else ()),('C',()))
    before_active=(('B','Browser'),) if second else ()
    after_apps=(('A',('Notes',) if second else ()),('B',('Browser',)),('C',()))
    after_active=(('A','Notes'),('B','Browser')) if second else (('B','Browser'),)
    app='Notes' if second else 'Browser';z='A' if second else 'B'
    base=workspace(before_apps,before_active).copy()
    source=(303,106,245,161) if second else (100,103,259,173)
    target=ui.RECTS[z];target_window=content_rect(z)
    drag=glide((t-1.3)/2.4)
    release=4.0
    if t<release:
        window(base,app,*source,ease(t/.5))
        if t>1.0:
            initial=(source[0],source[1],source[2],source[3])
            rect=tuple(a+(b-a)*drag for a,b in zip(initial,target_window))
            ghost(base,rect,z,ease((t-1)/.25))
        sx,sy=source[0]+source[2]*.55,source[1]+source[3]*.5
        tx,ty=target_window[0]+target_window[2]*.5,target_window[1]+target_window[3]*.5
        cursor(base,sx+(tx-sx)*drag,sy+(ty-sy)*drag-9*math.sin(drag*math.pi),t>1.1)
        click_pulse(base,sx,sy,t-1.1)
    elif t<release+.5:
        progress=(t-release)/.5
        rect=tuple(mix(a,b,progress) for a,b in zip(source,target_window))
        window(base,app,*rect)
    else:
        base=workspace(after_apps,after_active).copy()
    return base,'Control + right-drag  ·  release to assign'


def scene(index,t):
    hint=''
    if index==0:
        c=Canvas();ui.desktop(c);im=c.im
        clutter=[('Browser',43,62,335,205),('Editor',261,82,390,208),('Notes',115,140,278,174),('Terminal',383,181,290,145),('Finder',61,201,250,124)]
        for i,(app,x,y,w,h) in enumerate(clutter):
            p=ease((t-i*.22)/.55)
            window(im,app,x,y+18*(1-p),w,h,p)
        return im,''
    if index==1:
        c=Canvas();ui.desktop(c)
        structured=workspace((('A',()),('B',())),(),two=True)
        im=blend(c.im,structured,(t-1.2)/1.1)
        return im,'An empty desktop. Then a little structure.'
    if index==2:
        p=ease((t-.8)/1.8)
        ay=ui.TWO['A'][1]
        ah=mix(ui.TWO['A'][3],ui.RECTS['A'][3],p)
        cy=ay+ah+ui.GUTTER
        rects={'A':(6,ay,216,ah),'B':ui.RECTS['B']}
        if cy<365:rects['C']=(6,cy,216,365-cy)
        im=draw_workspace(rects,{'A':[],'B':[],'C':[]},{})
        return im,'Two columns → Split left'
    if index in (3,4):return assignment(t,index==4)
    if index==5:
        steps=[({'A':['Notes'],'B':['Browser'],'C':[]},{'A':'Notes','B':'Browser'}),
               ({'A':['Notes'],'B':['Editor','Browser'],'C':[]},{'A':'Notes','B':'Editor'}),
               ({'A':['Notes','Finder'],'B':['Editor','Browser','Preview'],'C':[]},{'A':'Notes','B':'Editor'}),
               ({'A':['Notes','Finder'],'B':['Editor','Browser','Preview'],'C':['Terminal']},{'A':'Notes','B':'Editor','C':'Terminal'}),
               (dict(DEFAULT_APPS),dict(DEFAULT_ACTIVE))]
        position=clamp(t/3.1)*4;step=min(3,int(position));p=position-step
        a=workspace(tuple_map(steps[step][0]),tuple_map(steps[step][1]));b=workspace(tuple_map(steps[step+1][0]),tuple_map(steps[step+1][1]))
        return blend(a,b,min(1,p*2)), 'Several real windows. Independent tabs in every zone.'
    if index==6:
        a=workspace();b=workspace(active=(('A','Notes'),('B','Browser'),('C','Terminal')))
        if t<1.4:im=a.copy()
        elif t<3.9:im=blend(a,b,(t-1.4)/.16)
        else:im=blend(b,a,(t-3.9)/.16)
        browser=(339,43);editor=(282,43)
        if t<1.25:xy=pointer_path((504,217),browser,(t-.25)/1.0)
        elif t<3.3:xy=browser
        else:xy=pointer_path(browser,editor,(t-3.3)/.55,-4)
        click_pulse(im,*browser,t-1.4)
        click_pulse(im,*editor,t-3.9)
        cursor(im,*xy)
        return im,'Notes in A and Terminal in C stay selected.'
    if index==7:
        im=workspace().copy()
        if t<2.4:
            overlay(im,lambda c:c.rect(*ui.RECTS['C'],None,ui.Z['C'],7,1),ease(t/.3))
            selected=1
            hint='Command + Tab  ·  switch apps as usual'
        else:
            window(im,'Finder',139,86,438,235,ease((t-2.4)/.3)*(1-ease((t-4.35)/.4)))
            selected=2
            hint='Command + Tab → SpaceTabs  ·  restore your workspace'
        if .4<t<1.9 or 3.2<t<4.5:
            def switcher(c):
                c.rect(156,134,408,129,'#e8e7ef','#ffffff',16)
                for j,(name,col) in enumerate([('Browser',ui.Z['B']),('Terminal',ui.Z['C']),('SpaceTabs','#c4b5fd')]):
                    x=184+j*129
                    if j==selected:c.rect(x-9,145,118,105,'#d0d3e2',None,10)
                    ui.icon(c,name,x+23,157,48)
                    c.text(x+47,229,name,13,ui.INK,True,'middle')
            overlay(im,switcher)
        return im,hint
    if index==8:
        shown=workspace(bars='floating');hidden=workspace(bars='hidden')
        if t<1.3:im=blend(workspace(),shown,t/.65)
        elif t<3.8:im=blend(shown,hidden,(t-1.3)/.7)
        else:im=blend(hidden,shown,(t-3.8)/.35)
        return im,'Auto-hide on  ·  Tap Control + Option + Command to reveal the bars'
    if index==9:
        selected=(('A','Notes'),('B','Preview'),('C','Terminal'))
        im=blend(workspace(),workspace(active=selected),t/.4)
        source=content_rect('B');target=content_rect('C')
        p=ease((t-1.6)/2.8)
        if 1.1<t<4.8:
            rect=tuple(a+(b-a)*p for a,b in zip(source,target))
            ghost(im,rect,'C',ease((t-1.1)/.3))
            cursor(im,468+(114-468)*p,177+(276-177)*p,True)
        after_apps=(('A',('Notes','Finder')),('B',('Editor','Browser')),('C',('Preview','Terminal','Messages')))
        after_active=(('A','Notes'),('B','Editor'),('C','Preview'))
        if t>=4.8:im=blend(im,workspace(after_apps,after_active),(t-4.8)/.35)
        def mouse(c):
            c.pill(484,291,84,'Control',fill='#ffffff',size=13)
            c.rect(584,279,38,53,'#ffffff',ui.INK,16)
            c.line(603,280,603,303,ui.INK,1)
            c.rect(605,282,13,19,ui.Z['C'] if 1.1<t<4.8 else '#63798d',None,5)
        overlay(im,mouse,1-ease((t-5.7)/.4))
        return im,'The outline previews the move. The window moves on release.'
    if index==10:
        apps=(('A',('Notes','Finder')),('B',('Editor','Browser')),('C',('Preview','Terminal','Messages')))
        act=(('A','Notes'),('B','Editor'),('C','Preview'))
        a=workspace(apps,act)
        browser=workspace(apps,(('A','Notes'),('B','Browser'),('C','Preview')))
        if t<3.0:
            im=a.copy();hint='Control + Option + 2  ·  focus B'
            overlay(im,lambda c:c.rect(*ui.RECTS['B'],None,ui.Z['B'],7,1),ease((t-.5)/.25))
        elif t<6.0:
            im=blend(a,browser,(t-3.4)/.25);hint='Control + Option + →  ·  next tab'
        else:
            im=browser.copy();hint='Control + Option + Return  ·  zoom / restore'
            zoom=ease((t-6.5)/.4)*(1-ease((t-8.5)/.4))
            if zoom>0:
                # Expand the focused Browser, then put it back in its own zone.
                src=content_rect('B');dest=(6,30,708,335)
                rect=tuple(a+(b-a)*zoom for a,b in zip(src,dest))
                window(im,'Browser',*rect)
        key = 'Control + Option + 2' if t<3 else 'Control + Option + →' if t<6 else 'Control + Option + Return'
        overlay(im,lambda c:c.pill(348,324,310,key,fill='#ffffff',size=13),ease(t/.3))
        return im,hint
    apps=(('A',('Notes','Finder')),('B',('Editor','Browser')),('C',('Preview','Terminal','Messages')))
    im=workspace(apps,(('A','Notes'),('B','Browser'),('C','Preview'))).filter(ImageFilter.GaussianBlur(1.6*SCALE))
    overlay(im,lambda c:c.rect(0,0,720,405,ui.BG),.6*ease(t/.5))
    def end(c):
        logo=brand_icon(88*SCALE)
        c.im.alpha_composite(logo,(round(179*SCALE),round(117*SCALE)))
        c.text(291,177,'SpaceTabs',48,ui.INK,True)
        c.text(291,205,'for macOS',18,ui.MUTED)
        c.text(360,247,'Your windows. Your zones. One desktop.',23,ui.INK,True,'middle')
        c.text(360,280,'github.com/jrausell/mac-app-spacetabs',14,ui.MUTED,anchor='middle')
    overlay(im,end,ease(t/.5))
    return im,''


@lru_cache(maxsize=8)
def brand_icon(size):
    with Image.open(ROOT/'Resources/icon-main-transparent.png') as source:
        return source.convert('RGBA').resize((size,size),Image.Resampling.LANCZOS)


@lru_cache(maxsize=1)
def monitor_furniture():
    out=Image.new('RGB',(W,H),BACKGROUND)
    shadow=Image.new('RGBA',(W,H),(0,0,0,0))
    ImageDraw.Draw(shadow).rounded_rectangle((161,82,1759,981),radius=34,fill=(74,69,103,45))
    shadow=shadow.filter(ImageFilter.GaussianBlur(22))
    out.paste(shadow,(0,0),shadow)
    d=ImageDraw.Draw(out)
    d.rounded_rectangle((158,68,1762,972),radius=28,fill='#e2e1e9',outline='#dbdce6',width=2)
    return out


@lru_cache(maxsize=1)
def monitor_mask():
    mask=Image.new('L',(1600,900),0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,1599,899),radius=24,fill=255)
    return mask


@lru_cache(maxsize=1)
def opening_card():
    out=Image.new('RGB',(W,H),'#ffffff')
    d=ImageDraw.Draw(out)
    logo=brand_icon(190)
    out.paste(logo,(865,245),logo)
    d.text((960,548),'SpaceTabs',font=font(96,True),fill=ui.INK,anchor='ms')
    d.text((960,608),'Your windows. Your zones. One desktop.',font=font(32),fill=ui.MUTED,anchor='ms')
    d.text((960,693),'FOR macOS',font=font(19,True),fill='#8590a5',anchor='ms')
    for x,col in [(910,ui.Z['A']),(960,ui.Z['B']),(1010,ui.Z['C'])]:
        d.rounded_rectangle((x-13,744,x+13,749),radius=3,fill=col)
    return out


def frame_at(t):
    # Brand is fully visible on frame zero; never open or close on a black frame.
    if t<=1.5:return opening_card().copy()
    index=max(0,min(11,next((i for i in range(12) if t<TIMES[i+1]),11)))
    local=t-TIMES[index]
    im,hint=scene(index,local)
    if index and local<.22:
        previous,_=scene(index-1,TIMES[index]-TIMES[index-1]-.001)
        im=blend(previous,im,local/.22)
    out=monitor_furniture().copy()
    stage=im.convert('RGB').resize((1600,900),Image.Resampling.LANCZOS)
    out.paste(stage,(160,70),monitor_mask())
    d=ImageDraw.Draw(out)
    logo=brand_icon(26);out.paste(logo,(122,17),logo)
    d.text((158,39),'SpaceTabs',font=font(23,True),fill=ui.INK,anchor='ls')
    d.text((1800,37),'WINDOWS, WITH A LITTLE MORE ROOM.',font=font(14,True),fill=ui.MUTED,anchor='rs')
    title='A little room to think.' if index==0 else TITLES[index]
    d.text((W/2,1025),title,font=font(30,True),fill=ui.INK,anchor='ms')
    if hint:d.text((W/2,1060),hint,font=font(19),fill=ui.MUTED,anchor='ms')
    if t<2.5:out=Image.blend(opening_card(),out,ease((t-1.5)/1.0))
    return out


def write_audio(path):
    """Original quiet synthesized accompaniment and short interaction cues."""
    rate=22050
    chords=[(130.8128,164.8138,195.9977),(110,130.8128,164.8138),
            (87.3071,130.8128,174.6141),(97.9989,146.8324,195.9977)]
    cues=[16.3,19.0,22.3,25.0,28.0,28.7,29.4,30.1,32.4,34.9,37.5,40.5,46.8,50.1,53.8,56.6,59.5,62.5,64.5]
    samples=array('h')
    for n in range(rate*DURATION):
        t=n/rate;segment=int(t/8);phase=(t%8)/8
        chord=chords[segment%4];next_chord=chords[(segment+1)%4]
        cross=ease((phase-.82)/.18)
        value=0
        for j,f in enumerate(chord):
            tone=math.sin(2*math.pi*f*t)+.18*math.sin(2*math.pi*f*2*t)
            following=math.sin(2*math.pi*next_chord[j]*t)+.18*math.sin(2*math.pi*next_chord[j]*2*t)
            value+=(tone*(1-cross)+following*cross)*.012
        value*=ease(t/2)*(1-ease((t-67)/3))*(.8+.2*math.sin(t*.4)**2)
        for cue in cues:
            dt=t-cue
            if 0<=dt<.055:value+=.045*math.exp(-dt*100)*math.sin(2*math.pi*1050*dt)
        samples.append(round(max(-1,min(1,value))*32767))
    if sys.byteorder!='little':samples.byteswap()
    with wave.open(str(path),'wb') as output:
        output.setparams((1,2,rate,0,'NONE','not compressed'));output.writeframes(samples.tobytes())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'.local/presentation')
    parser.add_argument('--preview-only',action='store_true')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    frame_at(0).save(args.output/'opening.jpg',quality=95)
    for number,t in enumerate([3.0,8.5,13.5,18,24,30.5,33.5,41,45.5,52.5,61,68],1):
        frame_at(t).save(args.output/f'preview-{number:02d}.jpg',quality=88)
    if args.preview_only:return
    ffmpeg=shutil.which('ffmpeg')
    if not ffmpeg:raise SystemExit('FFmpeg is required.')
    raw_video=args.output/'video-only.mp4'
    command=[ffmpeg,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24',
             '-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-an','-c:v','libx264','-preset','fast',
             '-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(raw_video)]
    encoder=subprocess.Popen(command,stdin=subprocess.PIPE)
    started=time.monotonic()
    try:
        for number in range(DURATION*FPS):
            encoder.stdin.write(frame_at(number/FPS).tobytes())
            if number%(FPS*5)==0:
                print(f'Rendered {number/FPS:04.1f} / {DURATION}s · elapsed {time.monotonic()-started:.0f}s',flush=True)
        encoder.stdin.close()
        if encoder.wait()!=0:raise RuntimeError('Video encoding failed')
    except BaseException:
        encoder.kill();encoder.wait();raise
    print('Composing original quiet audio…',flush=True)
    audio=args.output/'soundtrack.wav';write_audio(audio)
    final=args.output/'SpaceTabs-for-macOS-refined.mp4'
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(raw_video),'-i',str(audio),
                    '-c:v','copy','-c:a','aac','-b:a','128k','-t',str(DURATION),'-movflags','+faststart',str(final)],check=True)
    raw_video.unlink();audio.unlink()
    manifest={'title':'SpaceTabs for macOS','durationSeconds':DURATION,'width':W,'height':H,'fps':FPS,
              'style':'Schematic animation; no real desktop footage','audio':'Original synthesized accompaniment; no narration',
              'chapters':[{'start':TIMES[i],'title':TITLES[i]} for i in range(12)]}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    links=''.join(f'<button data-time="{TIMES[i]}">{TIMES[i]//60}:{TIMES[i]%60:02d} · {TITLES[i]}</button>' for i in range(12))
    player='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SpaceTabs for macOS</title><style>body{margin:0;background:#f6f7fb;color:#263044;font:16px -apple-system,BlinkMacSystemFont,sans-serif;padding:32px;max-width:1500px;margin-inline:auto}h1{font-size:30px;margin-bottom:8px}p{color:#788195}video{width:100%;border-radius:16px;background:#ffffff;margin:20px 0}a{color:#416ad0}nav{display:flex;flex-wrap:wrap;gap:10px}button{border:1px solid #dce0e9;color:#263044;background:#ffffff;padding:10px 14px;border-radius:7px;cursor:pointer}</style><h1>SpaceTabs for macOS</h1><p>70 seconds · 1080p / 30 fps · Schematic animation · Original quiet audio · No narration</p><video controls playsinline preload="metadata" poster="opening.jpg" src="SpaceTabs-for-macOS-refined.mp4"></video><p><a href="SpaceTabs-for-macOS-refined.mp4" download>Download the MP4</a></p><nav>'''+links+'''</nav><script>const v=document.querySelector('video');document.querySelectorAll('button').forEach(b=>b.onclick=()=>{v.currentTime=Number(b.dataset.time);v.play()});</script></html>'''
    (args.output/'index.html').write_text(player)
    print(f'Finished: {final} ({final.stat().st_size/1024/1024:.1f} MiB)',flush=True)


if __name__=='__main__':main()
