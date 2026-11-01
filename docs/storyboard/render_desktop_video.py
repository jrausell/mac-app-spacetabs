"""Action-led SpaceTabs presentation on an illustrated 27-inch 16:9 macOS desktop."""
from functools import lru_cache
from pathlib import Path
import argparse
import json
import math
import subprocess
import sys
import wave
sys.dont_write_bytecode=True
from PIL import Image, ImageDraw, ImageFilter
import desktop_art as ui
import render_concept as art

OUT=art.ROOT/'.local/presentation-desktop'
FPS=30
DURATION=70
SIZE=(2560,1440)
S=ui.S
TIMES=[0,5,10,15,21,27,31,37,43,49,56,66,70]
TITLES=['Your windows. Your zones. One desktop.','Give each task its own place.','Choose a layout. Make it yours.',
        'Assign a window. Keep its native controls.','Keep notes beside your work.','Several apps. One clear desktop.',
        'Switch B. Notes in A and Terminal in C stay put.','Your normal Mac workflow still works.',
        'Hide the bars. Bring them back with one hand.','Move windows between zones with a gesture.',
        'Focus. Switch. Zoom. Keep your flow.','SpaceTabs for macOS']
HINTS=['','Start with two independent tab groups.','Two columns → A/C on the left. Drag to adjust the split.',
       'Control + right-drag → release to assign.','The browser stays selected in B.',
       'Notes + Finder in A · Editor + Browser + Preview in B · Terminal + Messages in C',
       'One click changes only the selected zone.','Command-Tab normally; choose SpaceTabs to restore your selected workspace.',
       'Tap Control + Option + Command, then release.','Only the outline moves during the preview; the window moves on release.',
       'Global shortcuts stay close at hand.','Community · Open source · github.com/jrausell/mac-app-spacetabs']


def ease(p):
    p=max(0,min(1,p));return p*p*(3-2*p)


def mix(a,b,p):return a+(b-a)*ease(p)

def rect_mix(a,b,p):return tuple(mix(x,y,p) for x,y in zip(a,b))


def cursor_path(f,a,b,p,click=0):
    p=ease(p);ui.pointer(f,a[0]+(b[0]-a[0])*p,a[1]+(b[1]-a[1])*p-35*math.sin(math.pi*p),click)


def mouse_hint(f,held=True):
    ui.keycaps(f,'Control  +  right-drag')
    x,y=1315,884
    f.box(x,y,45,64,'#f5f7fb',19,'#596577')
    f.box(x+25,y+5,15,26,'#55e3ad' if held else '#bbc3d0',7)
    f.box(x+22,y+3,1,28,'#596577')


def empty(layout='split'):
    f=ui.copy(ui.desktop())
    for z,r in (ui.TWO if layout=='two' else ui.RECTS).items():
        ui.border(f,z,r)
        ui.panel(f,z,r)
        x,y,w,h=r
        tw=f.d.textlength(z,font=art.font(76,True))/S
        f.text(x+(w-tw)/2,y+h/2-10,z,76,'#7a8fa9',True)
    return f


@lru_cache(maxsize=1)
def clutter():
    f=ui.copy(ui.desktop('Browser'))
    for name,r in [('Editor',(180,102,1120,720)),('Finder',(1070,128,680,450)),
                   ('Browser',(480,190,1112,680)),('Notes',(80,450,700,430)),('Terminal',(1000,580,800,360))]:
        ui.app(f,name,r)
    return f.im


def assignment(t,second=False):
    f=empty()
    if second:
        ui.app(f,'Browser',ui.content_rect(ui.RECTS['B']))
        ui.panel(f,'B',ui.RECTS['B'],('Browser',),'Browser')
    name,z=('Notes','A') if second else ('Browser','B')
    src=(650,255,780,520) if second else (260,255,960,600)
    dest=ui.content_rect(ui.RECTS[z])
    p=ease((t-1.0)/2.6)
    if t<3.8:
        ui.app(f,name,src)
        if t>=1:
            ui.border(f,z,ui.RECTS[z],highlight=True)
            ui.ghost(f,tuple(a+(b-a)*p for a,b in zip(src,dest)),z)
    else:
        ui.app(f,name,rect_mix(src,dest,(t-3.8)/.5))
        if t>=4.3:ui.panel(f,z,ui.RECTS[z],(name,),name)
    cursor_path(f,(src[0]+src[2]*.5,src[1]+210),(dest[0]+dest[2]*.5,dest[1]+150),(t-1)/2.6)
    mouse_hint(f,1<=t<3.8)
    return f.im


def switcher(f,selected):
    # A recognizable Command-Tab overlay, kept separate from all app windows.
    x,y,w,h=610,414,700,212
    f.box(x,y,w,h,'#e4e8f0',24,'#ffffff')
    for i,name in enumerate(['Browser','Finder','SpaceTabs']):
        xx=x+70+i*210
        if i==selected:f.box(xx-22,y+21,156,168,'#c4cedd',16)
        ui.icon(f,name,xx+12,y+41,88)
        tw=f.d.textlength(name,font=art.font(21,True))/S
        f.text(xx+56-tw/2,y+151,name,21,art.INK,True)


def frame_scene(i,t):
    if i==0:return clutter().copy()
    if i==1:
        return empty('two').im
    if i==2:
        f=ui.copy(ui.desktop())
        p=ease((t-.5)/1.5)
        for z,r in [('A',rect_mix(ui.TWO['A'],ui.RECTS['A'],p)),('B',ui.RECTS['B'])]:
            ui.border(f,z,r);ui.panel(f,z,r)
        if p>.02:
            x,y,w,h=ui.RECTS['C'];r=(x,mix(966,y,p),w,max(2,h*p))
            ui.border(f,'C',r,p)
            if p>.8:ui.panel(f,'C',ui.RECTS['C'],opacity=(p-.8)*5)
        cursor_path(f,(320,930),(320,516),(t-.5)/1.5)
        if t>2.4:
            # A short ratio-handle drag makes the resize feature explicit.
            shift=54*math.sin(math.pi*ease((t-2.4)/2))
            f=empty()
            for z,name in [('A','Notes'),('C','Terminal')]:
                x,y,w,h=ui.RECTS[z]
                r=(x,y,w,h+shift) if z=='A' else (x,y+shift,w,h-shift)
                # Redraw only the left preview region to keep the right zone stable.
                if z=='A':
                    clean=ui.desktop();f.im.paste(clean.crop((0,41*S,634*S,980*S)),(0,41*S));f.d=ImageDraw.Draw(f.im)
                ui.border(f,z,r);ui.panel(f,z,r)
            f.box(284,511+shift,75,7,'#ffffff',3)
            ui.pointer(f,320,516+shift)
        return f.im
    if i in (3,4):return assignment(t,i==4)
    if i==5:
        f=empty()
        steps=[('B','Editor',0),('A','Notes',0),('C','Terminal',.6)]
        for z,name,start in steps:
            a=ease((t-start)/.5)
            ui.app(f,name,ui.content_rect(ui.RECTS[z]),a)
            tabs=ui.TABS[z][:max(1,min(len(ui.TABS[z]),int(t/.65)+1))]
            ui.panel(f,z,ui.RECTS[z],tabs,name)
        ui.pointer(f,mix(1360,320,t/3),90)
        return f.im
    if i==6:
        selected='Browser' if 1.1<=t<3.8 else 'Editor'
        f=ui.copy(ui.workspace(('Notes',selected,'Terminal')))
        # Both tab centers are derived from the actual panel's tab geometry.
        bx=ui.RECTS['B'][0]+8+55
        browser=(bx+108+38,99);editor=(bx+38,99)
        if t<2.7:
            cursor_path(f,(1400,450),browser,(t-.2)/.85,.5 if 1.1<=t<1.3 else 0)
        else:cursor_path(f,browser,editor,(t-2.8)/.85,.5 if 3.8<=t<4 else 0)
        for z in ['A','C']:
            x,y,w,h=ui.RECTS[z]
            f.box(x+w-143,y+18,120,29,'#2a3b35',6)
            f.text(x+w-133,y+25,'Unchanged',15,'#a0e2c4',True)
        return f.im
    if i==7:
        f=ui.copy(ui.workspace())
        if 1.1<=t<4.5:
            ui.app(f,'Finder',(400,160,1170,760))
        if .25<t<1.2:switcher(f,1)
        if 3.2<t<4.5:switcher(f,2)
        if 4.5<t<5.1:
            for z in ['A','C','B']:ui.border(f,z,ui.RECTS[z],highlight=True)
        return f.im
    if i==8:
        # First expand the windows for auto-hide; subsequent reveals only float the panels.
        if t<.6:
            a=ui.workspace();b=ui.workspace(bars=False,auto=True)
            f=ui.copy(Image.blend(a,b,ease(t/.6)))
        else:f=ui.copy(ui.workspace(bars=False,auto=True))
        if t>3:
            opacity=ease((t-3)/.28)
            for z,name in [('A','Notes'),('B','Editor'),('C','Terminal')]:ui.panel(f,z,ui.RECTS[z],ui.TABS[z],name,opacity)
        ui.keycaps(f,'Control  +  Option  +  Command','Show all tab bars')
        return f.im
    if i==9:
        f=ui.copy(ui.workspace(('Notes','Preview','Terminal')))
        src=ui.content_rect(ui.RECTS['B']);dest=ui.content_rect(ui.RECTS['C'])
        if 1<t<4.4:
            p=ease((t-1)/3)
            ui.ghost(f,tuple(a+(b-a)*p for a,b in zip(src,dest)),'C')
            ui.border(f,'C',ui.RECTS['C'],highlight=True)
        if t>=4.4:
            f=ui.copy(ui.workspace(('Notes','Editor','Preview'),moved=True))
        cursor_path(f,(1300,400),(330,730),(t-1)/3)
        mouse_hint(f,1<t<4.4)
        return f.im
    if i==10:
        f=ui.copy(ui.workspace(('Notes','Browser' if t>=3 else 'Editor','Preview'),moved=True))
        if t<3:
            ui.border(f,'B',ui.RECTS['B'],highlight=True)
            ui.keycaps(f,'Control  +  Option  +  2','Focus B')
        elif t<6:
            ui.keycaps(f,'Control  +  Option  +  Right','Next tab in B')
        else:
            p=ease((t-6.25)/.4)*(1-ease((t-8.2)/.4))
            src=ui.content_rect(ui.RECTS['B']);dest=(30,74,1860,884)
            if p:ui.app(f,'Browser',tuple(a+(b-a)*p for a,b in zip(src,dest)))
            ui.keycaps(f,'Control  +  Option  +  Return','Zoom the focused window' if t<8.2 else 'Restore its previous frame')
        return f.im
    return ui.workspace(('Notes','Browser','Preview'),moved=True).copy()


@lru_cache(maxsize=1)
def furniture():
    out=Image.new('RGB',SIZE,'#f4f3ef')
    shadow=Image.new('RGBA',SIZE,(0,0,0,0));d=ImageDraw.Draw(shadow)
    d.rounded_rectangle((207,104,2353,1312),radius=29,fill=(18,28,46,65))
    shadow=shadow.filter(ImageFilter.GaussianBlur(24));out.paste(shadow,(0,0),shadow)
    d=ImageDraw.Draw(out)
    d.rounded_rectangle((208,81,2352,1312),radius=25,fill='#242a34',outline='#555d6b',width=2)
    d.ellipse((1276,86,1283,93),fill='#131a26')
    d.polygon([(1253,1312),(1307,1312),(1330,1352),(1230,1352)],fill='#b8bdc7')
    d.rounded_rectangle((1132,1350,1428,1361),radius=5,fill='#cbd0d7')
    d.line((1142,1352,1418,1352),fill='#eff1f4',width=2)
    return out


@lru_cache(maxsize=1)
def screen_mask():
    mask=Image.new('L',(2112,1188),0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,2111,1187),radius=10,fill=255)
    return mask


@lru_cache(maxsize=1)
def intro():
    f=art.Frame();f.logo(420,330,220)
    f.text(710,374,'SpaceTabs',104,bold=True)
    f.text(718,510,'Your windows. Your zones. One desktop.',30,art.MUTED)
    f.text(718,600,'Independent tabs for your real Mac windows.',24)
    return f.im.resize(SIZE,Image.Resampling.LANCZOS)


def font(size,bold=False):return art.font(size,bold).font_variant(size=size)


def frame_at(t):
    if t<1.8:return intro().copy()
    i=next((j for j in range(12) if t<TIMES[j+1]),11);local=t-TIMES[i]
    im=frame_scene(i,local)
    if i and local<.22:
        prev=frame_scene(i-1,TIMES[i]-TIMES[i-1]-.001)
        im=Image.blend(prev,im,ease(local/.22))
    out=furniture().copy()
    screen=im.convert('RGB').resize((2112,1188),Image.Resampling.LANCZOS)
    out.paste(screen,(224,100),screen_mask())
    d=ImageDraw.Draw(out)
    mark=ui.logo(26).resize((32,32),Image.Resampling.LANCZOS);out.paste(mark,(225,22),mark)
    d.text((270,31),'SpaceTabs',font=font(25,True),fill=art.INK,anchor='lt')
    d.text((2336,31),f'{i+1:02d} / 12',font=font(20),fill=art.MUTED,anchor='rt')
    title=TITLES[i]
    d.text((1280,33),title,font=font(28,True),fill=art.INK,anchor='mt')
    d.text((1280,1390),HINTS[i],font=font(25),fill='#46536a',anchor='mt')
    if i==11:
        # Hold a branded close over the finished, visibly organized desktop.
        overlay=Image.new('RGBA',SIZE,(0,0,0,0));od=ImageDraw.Draw(overlay)
        od.rounded_rectangle((675,485,1885,925),radius=22,fill=(248,249,252,246),outline='#d6dce6',width=2)
        mark=ui.logo(120).resize((170,170),Image.Resampling.LANCZOS)
        overlay.alpha_composite(mark,(800,555))
        od.text((1030,577),'SpaceTabs',font=font(78,True),fill=art.INK)
        od.text((1035,687),'Your windows. Your zones. One desktop.',font=font(27),fill=art.MUTED)
        od.text((1280,818),'github.com/jrausell/mac-app-spacetabs',font=font(25),fill='#396de5',anchor='mt')
        if local<.5:overlay.putalpha(overlay.getchannel('A').point(lambda a:round(a*ease(local/.5))))
        out.paste(overlay,(0,0),overlay)
    if t<2.6:out=Image.blend(intro(),out,ease((t-1.8)/.8))
    return out


def write_audio(path):
    """Original upbeat plucked melody, bass, and light percussion at 112 BPM."""
    from array import array
    import random
    rate=22050;beat=60/112
    left=array('f',[0])*(rate*DURATION);right=array('f',[0])*(rate*DURATION)
    rng=random.Random(20261101)
    def put(start,tone,volume,pan=0):
        pos=int(start*rate);n=min(len(tone),len(left)-pos)
        for j in range(n):
            left[pos+j]+=tone[j]*volume*(1-pan*.35)
            right[pos+j]+=tone[j]*volume*(1+pan*.35)
    @lru_cache(maxsize=40)
    def note(midi,duration=.32):
        freq=440*2**((midi-69)/12);result=array('f')
        for j in range(int(duration*rate)):
            t=j/rate
            result.append((math.sin(2*math.pi*freq*t)+.28*math.sin(2*math.pi*freq*2*t)+.09*math.sin(2*math.pi*freq*3*t))*min(t/.006,1)*math.exp(-t*10))
        return result
    chords=[(50,[62,66,69,73]),(57,[61,64,69,71]),(59,[62,66,71,74]),(55,[62,67,69,74])]
    melody=[0,2,1,3,2,1,2,1]
    for b in range(int(DURATION/beat)+1):
        start=b*beat;root,tones=chords[(b//4)%4]
        if b%2==0:put(start,note(root,.45),.08,-.2)
        for sub in [0,.5]:
            idx=melody[(b*2+int(sub*2))%8]
            put(start+sub*beat,note(tones[idx]+12,.35),.035,-.6 if sub else .6)
        if b%4 in [0,2]:
            kick=[math.sin(2*math.pi*(55*(j/rate)+6*(1-math.exp(-(j/rate)*30))))*math.exp(-(j/rate)*30) for j in range(int(.16*rate))]
            put(start,kick,.065)
        if b%4 in [1,3]:
            clap=[rng.uniform(-1,1)*math.exp(-(j/rate)*55) for j in range(int(.08*rate))]
            put(start,clap,.022)
        for sub in [0,.5]:
            hat=[rng.uniform(-1,1)*math.exp(-(j/rate)*120) for j in range(int(.035*rate))]
            put(start+sub*beat,hat,.012,sub-.25)
    samples=array('h')
    for j in range(len(left)):
        t=j/rate;envelope=min(t/.35,1)*min((DURATION-t)/1.2,1)
        for channel in (left,right):samples.append(round(max(-.9,min(.9,channel[j]*envelope))*32767))
    if sys.byteorder!='little':samples.byteswap()
    with wave.open(str(path),'wb') as out:
        out.setparams((2,2,rate,0,'NONE','not compressed'));out.writeframes(samples.tobytes())


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--preview-only',action='store_true');args=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    for n,t in enumerate([0,7.5,13.8,18.2,24.2,30,33,40.8,47.5,52,63,68],1):
        frame_at(t).save(OUT/f'preview-{n:02d}.png')
    if args.preview_only:return
    raw=OUT/'desktop-video-only.mp4';final=OUT/'SpaceTabs-Desktop-QHD.mp4'
    proc=subprocess.Popen(['ffmpeg','-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s','2560x1440','-r','30','-i','pipe:0','-an','-c:v','libx264','-preset','fast','-crf','16','-pix_fmt','yuv420p',str(raw)],stdin=subprocess.PIPE)
    try:
        for n in range(FPS*DURATION):
            proc.stdin.write(frame_at(n/FPS).tobytes())
            if n%(FPS*5)==0:print(f'Rendered {n/FPS:.0f} / 70s',flush=True)
        proc.stdin.close()
        if proc.wait():raise RuntimeError('Video encoding failed')
    except BaseException:
        proc.kill();proc.wait();raise
    audio=OUT/'upbeat-soundtrack.wav';write_audio(audio)
    subprocess.run(['ffmpeg','-y','-v','error','-i',str(raw),'-i',str(audio),'-map','0:v','-map','1:a','-c:v','copy','-af','loudnorm=I=-19:TP=-1.5:LRA=7','-ar','44100','-c:a','aac','-b:a','192k','-t','70','-movflags','+faststart',str(final)],check=True)
    manifest={'width':2560,'height':1440,'fps':30,'duration':70,'screenAspectRatio':'16:9','displayReference':'27-inch QHD','audio':'Original plucked melody, bass, and percussion, 112 BPM','chapters':[{'start':t,'title':title} for t,title in zip(TIMES,TITLES)]}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    buttons=''.join(f'<button data-time="{t}">{title}</button>' for t,title in zip(TIMES,TITLES))
    (OUT/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SpaceTabs desktop demo</title><style>body{margin:32px auto;max-width:1600px;padding:0 24px;background:#f4f3ef;color:#20252c;font:17px system-ui}video{width:100%;margin:24px 0}nav{display:flex;flex-wrap:wrap;gap:8px}button{padding:10px;border:1px solid #d4dae3;background:white;border-radius:6px;cursor:pointer}a{color:#396de5}</style><h1>SpaceTabs — your windows, your zones</h1><p>Illustrated macOS desktop · 27-inch 16:9 display · QHD / 30 fps · Original rhythmic soundtrack</p><video controls playsinline preload="metadata" poster="preview-01.png" src="SpaceTabs-Desktop-QHD.mp4"></video><p><a href="SpaceTabs-Desktop-QHD.mp4" download>Download QHD video</a></p><nav>'''+buttons+'''</nav><script>const v=document.querySelector('video');document.querySelectorAll('button').forEach(b=>b.onclick=()=>{v.currentTime=Number(b.dataset.time);v.play()})</script></html>''')
    print(f'Finished: {final}',flush=True)


if __name__=='__main__':main()
