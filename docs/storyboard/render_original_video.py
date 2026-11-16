"""Render the approved SpaceTabs design as a QHD presentation for a 27-inch 16:9 display."""
import argparse
from functools import lru_cache
import json
import math
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from PIL import Image, ImageDraw
import render_concept as art
from render_video import write_audio

ROOT = art.ROOT
OUT = ROOT / '.local/presentation-original'
FPS, DURATION = 30, 70
SIZE = (2560, 1440)
S = art.S
TIMES = [0, 5, 10, 15, 21, 27, 31, 37, 43, 49, 56, 66, 70]
CHAPTERS = ['SpaceTabs for macOS', 'A little room to think', 'Choose your layout',
            'Give your browser a place', 'Keep your notes nearby', 'Build your workspace',
            'Switch B. Keep A and C.', 'Your usual Mac workflow', 'Show tabs when you need them',
            'Move a window between zones', 'A few useful shortcuts', 'Your windows. Your zones.']
RECTS = {'A': (744, 215, 398, 294), 'C': (744, 533, 398, 294), 'B': (1166, 215, 670, 612)}
KINDS = {'Notes':'notes','Terminal':'terminal','Editor':'editor','Browser':'browser'}
TABS = {'A':['Notes','Finder'], 'B':['Editor','Browser'], 'C':['Terminal']}


def ease(p):
    p = max(0, min(1, p))
    return p*p*(3-2*p)


def lerp(a,b,p):
    return a+(b-a)*ease(p)


def frame():
    f = art.Frame()
    f.logo(74,52,58)
    f.text(146,69,'SpaceTabs',28,bold=True)
    f.text(146,108,'FOR macOS',13,art.MUTED)
    f.text(88,989,'COMMUNITY / OPEN SOURCE',14,art.MUTED)
    f.text(1455,989,'Your windows. Your zones.',18,art.MUTED)
    return f


def copy_frame(image):
    f = art.Frame.__new__(art.Frame)
    f.im = image.copy()
    f.d = ImageDraw.Draw(f.im)
    return f


def caption(f, title, lines=(), beat='', detail=''):
    for i,line in enumerate(title):
        f.text(84,305+i*82,line,65,bold=True)
    for i,line in enumerate(lines):
        f.text(88,511+i*41,line,25,art.MUTED)
    f.box(88,702,42,3,art.BLUE,1)
    if beat: f.text(88,738,beat,15,art.BLUE,True)
    if detail: f.text(88,778,detail,21)


@lru_cache(maxsize=1)
def opening():
    f=art.Frame()
    f.logo(195,276,300)
    f.text(578,344,'SpaceTabs',116,bold=True)
    f.text(588,494,'Your windows. Your zones. One desktop.',35,art.MUTED)
    f.box(588,604,64,4,art.BLUE,2)
    f.text(588,646,'A native workspace for macOS.',24)
    f.text(90,990,'COMMUNITY / OPEN SOURCE',14,art.MUTED)
    return f.im


@lru_cache(maxsize=20)
def surface(zone, app, panel=False, width=0, height=0, rich=True):
    _,_,w,h=RECTS[zone]
    w,h=width or w,height or h
    f=art.Frame.__new__(art.Frame)
    # Draw the independent surfaces with transparent surroundings at native supersampled resolution.
    f.im=Image.new('RGBA',(art.W*S,art.H*S),(0,0,0,0))
    f.d=ImageDraw.Draw(f.im)
    tabs=list(TABS[zone]) if rich else [app]
    if app not in tabs:tabs.insert(0,app)
    art.tab_group(f,24,24,w,h,zone,tabs,app,KINDS[app],panel=panel,app_window=not panel)
    top=24 if panel else 90
    bottom=77 if panel else 24+h
    return f.im.crop((12*S,(top-12)*S,(w+36)*S,(bottom+16)*S))


def paste(f,layer,x,y,opacity=1):
    if opacity<=0:return
    if opacity<1:
        layer=layer.copy()
        layer.putalpha(layer.getchannel('A').point(lambda a:round(a*opacity)))
    f.im.paste(layer,(round(x*S),round(y*S)),layer)
    f.d=ImageDraw.Draw(f.im)


def app(f,zone,name,rect=None,opacity=1):
    x,y,w,h=rect or RECTS[zone]
    layer=surface(zone,name)
    ow,oh=RECTS[zone][2:]
    if (w,h)!=(ow,oh):
        layer=layer.resize((round((w+24)*S),round((h-66+28)*S)),Image.Resampling.LANCZOS)
    paste(f,layer,x-12,y+54,opacity)


def panel(f,zone,name,opacity=1,rich=True):
    x,y,_,_=RECTS[zone]
    paste(f,surface(zone,name,True,rich=rich),x-12,y-12,opacity)


@lru_cache(maxsize=14)
def workspace(selected='Editor', bars=True):
    f=frame()
    for zone,name in [('A','Notes'),('C','Terminal'),('B',selected)]:
        app(f,zone,name)
        if bars:panel(f,zone,name)
    return f.im


def pointer(f,x,y,pulse=0):
    if pulse:
        r=8+16*pulse
        f.d.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),outline='#70adff',width=2*S)
    pts=[(x,y),(x,y+24),(x+6,y+18),(x+13,y+30),(x+18,y+27),(x+11,y+15),(x+23,y+15)]
    f.d.polygon([(a*S,b*S) for a,b in pts],fill='#ffffff',outline='#20252c',width=2*S)


def ghost(f,rect,zone):
    x,y,w,h=rect
    color={'A':'#ffbf47','B':'#70adff','C':'#55e3ad'}[zone]
    f.d.rounded_rectangle((x*S,(y+66)*S,(x+w)*S,(y+h)*S),radius=11*S,outline=color,width=3*S)


def scene(i,t):
    if i==0:return opening().copy()
    if i==1:
        f=frame()
        caption(f,['Too many windows?'],['Give each task a place.','Keep your desktop yours.'], 'A LITTLE ROOM TO THINK')
        for n,(zone,name,rect) in enumerate([
            ('B','Editor',(951,181,670,612)),('A','Notes',(768,306,398,294)),
            ('B','Browser',(1111,273,670,612)),('C','Terminal',(864,494,398,294))]):
            x,y,w,h=rect
            app(f,zone,name,(x,lerp(y+24,y,t-n*.15),w,h),ease((t-n*.15)/.6))
        return f.im
    if i==2:
        f=frame();caption(f,['A place for','every window.'],['Two columns, or three zones.','Choose the layout that fits.'],'YOUR LAYOUT. YOUR CHOICE.')
        # Grow the second left-hand zone, keeping B in place.
        p=ease((t-.8)/1.4)
        for zone,name in [('A','Notes'),('B','Editor')]:panel(f,zone,name,rich=False)
        x,y,w,_=RECTS['C']
        paste(f,surface('C','Terminal',True,rich=False),x-12,lerp(215,y,p)-12,p)
        return f.im
    if i in (3,4):
        f=frame();second=i==4
        caption(f,['Keep notes nearby.'] if second else ['Your browser,','right here.'],
                ['The app keeps its own window.','SpaceTabs adds an independent bar.'],
                'CONTROL + RIGHT-DRAG','Release to assign the window.')
        for zone,name in [('A','Notes'),('B','Browser'),('C','Terminal')]:panel(f,zone,name,rich=False)
        if second:app(f,'B','Browser')
        z,name=('A','Notes') if second else ('B','Browser')
        dest=RECTS[z];src=(1000,340,398,294) if second else (850,330,620,440)
        p=ease((t-1.2)/2.5)
        if t<4:
            app(f,z,name,src)
            if t>1.2:ghost(f,tuple(a+(b-a)*p for a,b in zip(src,dest)),z)
        else:
            app(f,z,name,tuple(lerp(a,b,(t-4)/.5) for a,b in zip(src,dest)))
        pointer(f,lerp(src[0]+140,dest[0]+150,p),lerp(src[1]+190,dest[1]+175,p))
        return f.im
    if i==5:
        f=frame();caption(f,['Find your rhythm.'],['Notes beside your work.','A terminal within reach.','Real windows. Independent tab bars.'],'ADD WINDOWS. KEEP THE STRUCTURE.')
        for zone,name in [('A','Notes'),('B','Editor'),('C','Terminal')]:
            alpha=ease((t-({'A':0,'B':.6,'C':1.4}[zone]))/.6)
            app(f,zone,name,opacity=alpha);panel(f,zone,name,alpha)
        return f.im
    if i==6:
        name='Browser' if 1.4<=t<4 else 'Editor'
        f=copy_frame(workspace(name));caption(f,['One desktop.','Your own rhythm.'],['Notes beside your work.','A terminal within reach.','Real windows. Independent tab bars.'],'SWITCH B. KEEP A AND C.','Browser comes forward.' if name=='Browser' else 'Choose a tab in your main zone.')
        x=lerp(1378,1262,(t-3.3)/.6) if t>3.3 else lerp(1580,1378,(t-.3)/1)
        pointer(f,x,244,.5 if abs(t-1.4)<.15 or abs(t-4)<.15 else 0)
        return f.im
    if i==7:
        f=copy_frame(workspace());caption(f,['Still your Mac.'],['Switch apps as usual.','Return to your selected workspace.'],'COMMAND + TAB','Choose SpaceTabs to restore all zones.')
        if 1<t<4:
            app(f,'B','Browser',(1020,285,670,612),ease((t-1)/.3)*(1-ease((t-3.5)/.4)))
        return f.im
    if i==8:
        f=copy_frame(workspace(bars=False));caption(f,['There when','you need them.'],['Let the tab bars step aside.','Reveal them with one hand.'],'CONTROL + OPTION + COMMAND','Tap together, then release.')
        opacity=1-ease((t-.7)/.6) if t<3.6 else ease((t-3.6)/.35)
        for z,n in [('A','Notes'),('B','Editor'),('C','Terminal')]:panel(f,z,n,opacity)
        return f.im
    if i==9:
        f=copy_frame(workspace('Browser'))
        caption(f,['Change the task.','Keep your place.'],['A preview follows your pointer.','The window moves on release.'],'CONTROL + RIGHT-DRAG','Move Browser from B to C.')
        p=ease((t-1.2)/3.2);src,dst=RECTS['B'],RECTS['C']
        if 1.2<t<4.7:ghost(f,tuple(a+(b-a)*p for a,b in zip(src,dst)),'C')
        if t>=4.7:
            app(f,'B','Editor');panel(f,'B','Editor',rich=False)
            app(f,'C','Browser');panel(f,'C','Browser')
        pointer(f,lerp(1510,945,p),lerp(550,720,p))
        return f.im
    if i==10:
        f=copy_frame(workspace('Browser' if t>=3 else 'Editor'))
        if t<3:
            caption(f,['A few keys.','More flow.'],['Focus the main zone.'],'CONTROL + OPTION + 2','Focus B.')
        elif t<6:
            caption(f,['A few keys.','More flow.'],['Switch the active zone’s tab.'],'CONTROL + OPTION + RIGHT','The other groups stay selected.')
        else:
            caption(f,['A few keys.','More flow.'],['Zoom the focused window.','Press again to restore it.'],'CONTROL + OPTION + RETURN')
            p=ease((t-6.4)/.4)*(1-ease((t-8.4)/.4))
            if p:
                src=RECTS['B'];dst=(744,215,1092,612)
                app(f,'B','Browser',tuple(a+(b-a)*p for a,b in zip(src,dst)))
        return f.im
    f=copy_frame(opening())
    f.text(588,738,'github.com/jrausell/mac-app-spacetabs',24,art.MUTED)
    return f.im


def frame_at(t):
    i=next((i for i in range(12) if t<TIMES[i+1]),11)
    local=t-TIMES[i]
    im=scene(i,local)
    if i and local<.35:
        im=Image.blend(scene(i-1,TIMES[i]-TIMES[i-1]-.001),im,ease(local/.35))
    return im.resize(SIZE,Image.Resampling.LANCZOS)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview-only',action='store_true')
    args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    samples=[0,7,13,18,24,30,34,41,47.5,54.5,63,68]
    for n,t in enumerate(samples):frame_at(t).save(OUT/f'video-{n+1:02d}.png')
    if args.preview_only:return
    raw=OUT/'original-video-only.mp4';final=OUT/'SpaceTabs-Community-QHD.mp4'
    command=['ffmpeg','-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s','2560x1440',
             '-r',str(FPS),'-i','pipe:0','-an','-c:v','libx264','-preset','fast','-crf','16','-pix_fmt','yuv420p',str(raw)]
    process=subprocess.Popen(command,stdin=subprocess.PIPE)
    try:
        for n in range(DURATION*FPS):
            process.stdin.write(frame_at(n/FPS).tobytes())
            if n%(FPS*5)==0:print(f'Rendered {n/FPS:.0f} / {DURATION}s',flush=True)
        process.stdin.close()
        if process.wait():raise RuntimeError('Encoding failed')
    except BaseException:
        process.kill();process.wait();raise
    audio=OUT/'original-soundtrack.wav';write_audio(audio)
    subprocess.run(['ffmpeg','-y','-v','error','-i',str(raw),'-i',str(audio),'-c:v','copy','-c:a','aac','-b:a','160k','-t','70','-movflags','+faststart',str(final)],check=True)
    raw.unlink();audio.unlink()
    manifest={'width':SIZE[0],'height':SIZE[1],'fps':FPS,'duration':DURATION,'displayReference':'27-inch QHD, 16:9',
              'chapters':[{'start':t,'title':title} for t,title in zip(TIMES,CHAPTERS)]}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    buttons=''.join(f'<button data-time="{t}">{title}</button>' for t,title in zip(TIMES,CHAPTERS))
    (OUT/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SpaceTabs Community</title><style>body{max-width:1440px;margin:40px auto;padding:0 24px;background:#f4f3ef;color:#20252c;font:18px system-ui}video{width:100%;margin:24px 0}nav{display:flex;flex-wrap:wrap;gap:8px}button{padding:10px;border:1px solid #ddd;background:white;border-radius:6px;cursor:pointer}a{color:#396de5}</style><h1>SpaceTabs Community</h1><p>27-inch QHD reference · 2560 × 1440 · 30 fps · Illustrated presentation</p><video controls playsinline preload="metadata" poster="video-01.png" src="SpaceTabs-Community-QHD.mp4"></video><p><a href="SpaceTabs-Community-QHD.mp4" download>Download video</a></p><nav>'''+buttons+'''</nav><script>const v=document.querySelector('video');document.querySelectorAll('button').forEach(b=>b.onclick=()=>{v.currentTime=Number(b.dataset.time);v.play()})</script></html>''')
    print(f'Finished: {final}',flush=True)


if __name__=='__main__':main()
