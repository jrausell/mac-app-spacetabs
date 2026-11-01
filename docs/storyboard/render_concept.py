"""Render full-resolution design review frames before animating a new presentation."""
from functools import lru_cache
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.local/presentation-original'
S = 2
W, H = 1920, 1080
INK = '#20252c'
MUTED = '#737a85'
BLUE = '#396de5'
PAPER = '#f4f3ef'


@lru_cache(maxsize=64)
def font(size, bold=False, mono=False):
    path = '/System/Library/Fonts/Menlo.ttc' if mono else '/System/Library/Fonts/SFNS.ttf'
    result = ImageFont.truetype(path, size * S)
    if not mono:
        result.set_variation_by_name(b'Semibold' if bold else b'Regular')
    return result


class Frame:
    def __init__(self):
        self.im = Image.new('RGB', (W*S, H*S), PAPER)
        self.d = ImageDraw.Draw(self.im)

    def box(self, x, y, w, h, fill, radius=0, stroke=None):
        self.d.rounded_rectangle((x*S, y*S, (x+w)*S, (y+h)*S), radius=radius*S,
                                 fill=fill, outline=stroke, width=S)

    def text(self, x, y, value, size=22, color=INK, bold=False, mono=False):
        self.d.text((x*S, y*S), value, fill=color, font=font(size, bold, mono), anchor='lt')

    def logo(self, x, y, size):
        with Image.open(ROOT/'Resources/icon-main-transparent.png') as source:
            mark = source.convert('RGBA').resize((size*S, size*S), Image.Resampling.LANCZOS)
        self.im.paste(mark, (x*S, y*S), mark)

    def save(self, name):
        # Supersample edges, then deliver exact 1920x1080 PNG frames without JPEG loss.
        self.im.resize((W,H), Image.Resampling.LANCZOS).save(OUT/name)


def tab_group(f, x, y, w, h, zone, tabs, active, kind, panel=True, app_window=True):
    shadow = Image.new('RGBA', f.im.size)
    sd = ImageDraw.Draw(shadow)
    # SpaceTabs owns the tab panel; the external app owns a separate window.
    if panel: sd.rounded_rectangle((x*S,(y+4)*S,(x+w)*S,(y+57)*S), radius=9*S, fill=(25,35,50,18))
    if app_window: sd.rounded_rectangle((x*S,(y+74)*S,(x+w)*S,(y+h+8)*S), radius=12*S, fill=(25,35,50,23))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12*S))
    f.im.paste(shadow,(0,0),shadow)
    f.d = ImageDraw.Draw(f.im)
    if panel:
        f.box(x,y,w,53,'#34373d',8,'#292c32')
        zone_color = {'A': '#ffbf47', 'B': '#70adff', 'C': '#55e3ad'}[zone]
        f.text(x+18,y+17,zone,20,zone_color,True)
        tx=x+55
        for tab in tabs:
            width=98 if tab != 'Terminal' else 116
            if tab==active:
                f.box(tx-8,y+10,width,34,'#555c69',6)
                f.box(tx-8,y+46,width,2,'#a9c3ff')
            f.text(tx,y+18,tab,17,'#ffffff' if tab==active else '#c7cbd3',tab==active)
            tx+=width+10
        f.text(x+w-30,y+15,'+',23,'#d5d9e1')
    if not app_window:
        return
    # The visible desktop gap and the window's own title bar prevent an embedded-app reading.
    window_y = y+66
    f.box(x,window_y,w,h-66,'#ffffff',11,'#d8dbdf')
    f.box(x+1,window_y+1,w-2,37,'#f7f7f8',10)
    f.box(x+1,window_y+22,w-2,16,'#f7f7f8')
    f.box(x+1,window_y+38,w-2,1,'#e3e5e9')
    for i,color in enumerate(['#ff6058','#ffbd2e','#28c840']):
        f.d.ellipse(((x+17+i*21)*S,(window_y+13)*S,
                     (x+29+i*21)*S,(window_y+25)*S),fill=color)
    title = {'notes':'Today — Notes', 'terminal':'Terminal',
             'editor':'Workspace.swift — Editor', 'browser':'Ideas — Browser'}[kind]
    title_width = f.d.textlength(title,font=font(15)) / S
    f.text(x+(w-title_width)/2,window_y+12,title,15,MUTED)
    y += 40
    h -= 40
    if kind=='notes':
        f.text(x+24,y+80,'A little room to think.',23,bold=True)
        f.text(x+24,y+122,'Today',16,MUTED)
        for i,label in enumerate(['Sketch the idea','Keep the useful parts','Make something yours']):
            yy=y+154+i*34
            f.box(x+24,yy,13,13,'#ffffff',3,'#bbc2cc')
            f.text(x+49,yy-2,label,17)
    elif kind=='terminal':
        f.box(x+12,y+66,w-24,h-78,'#252b35',7)
        f.text(x+30,y+91,'~/SpaceTabs',17,'#abb6c7',mono=True)
        f.text(x+30,y+128,'$ swift build',19,'#83d9b4',mono=True)
        f.text(x+30,y+170,'Build complete.',17,'#f0f3f8',mono=True)
        f.text(x+30,y+210,'$ _',19,'#83d9b4',mono=True)
    elif kind=='editor':
        f.text(x+26,y+80,'Workspace.swift',18,MUTED)
        code=[('01', 'let workspace = SpaceTabs()', '#5369c7'),
              ('02', '', INK),
              ('03', '// Keep each group independent.', '#89929f'),
              ('04', 'workspace.select(browser, in: .b)', '#2c333d'),
              ('05', '', INK),
              ('06', '// Notes and Terminal stay put.', '#89929f')]
        for i,(n,line,col) in enumerate(code):
            yy=y+131+i*38
            f.text(x+25,yy,n,15,'#a3aab5',mono=True)
            f.text(x+67,yy,line,17,col,mono=True)
        f.box(x+24,y+h-60,w-48,1,'#eceef2')
        f.text(x+28,y+h-41,'Swift',15,MUTED)
    else:
        if h < 400:
            f.text(x+24,y+82,'Ideas need space.',27,bold=True)
            f.text(x+24,y+126,'A quieter place for',17,MUTED)
            f.text(x+24,y+153,'your next project.',17,MUTED)
            return
        f.text(x+29,y+88,'Ideas need space.',39,bold=True)
        f.text(x+29,y+149,'A quieter place for your next project.',19,MUTED)
        f.box(x+29,y+204,w-58,182,'#eef2fa',8)
        f.text(x+54,y+230,'PROJECT JOURNAL',14,BLUE,True)
        f.text(x+54,y+269,'From a thought',28,bold=True)
        f.text(x+54,y+310,'to something real.',28,bold=True)
        f.text(x+29,y+h-83,'Read. Explore. Keep your place.',20,MUTED)


def workspace_frame(switched=False):
    f=Frame()
    f.logo(74,52,58)
    f.text(146,69,'SpaceTabs',28,bold=True)
    f.text(146,108,'FOR macOS',13,MUTED)
    f.text(84,305,'One desktop.',65,bold=True)
    f.text(84,387,'Your own rhythm.',65,bold=True)
    f.text(88,511,'Notes beside your work.',25,MUTED)
    f.text(88,552,'A terminal within reach.',25,MUTED)
    f.text(88,593,'Real windows. Independent tab bars.',25,MUTED)
    f.box(88,702,42,3,BLUE,1)
    f.text(88,738,'SWITCH B. KEEP A AND C.',15,BLUE,True)
    f.text(88,778,'Browser comes forward.' if switched else 'Choose a tab in your main zone.',21)
    # A compact, deliberately asymmetric arrangement is derived from our actual split-left layout.
    tab_group(f,744,215,398,294,'A',['Notes','Finder'],'Notes','notes')
    tab_group(f,744,533,398,294,'C',['Terminal'],'Terminal','terminal')
    tab_group(f,1166,215,670,612,'B',['Editor','Browser'],'Browser' if switched else 'Editor','browser' if switched else 'editor')
    f.text(88,989,'COMMUNITY / OPEN SOURCE',14,MUTED)
    f.text(1455,989,'Your windows. Your zones.',18,MUTED)
    return f


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    f=Frame()
    f.logo(195,276,300)
    f.text(578,344,'SpaceTabs',116,bold=True)
    f.text(588,494,'Your windows. Your zones. One desktop.',35,MUTED)
    f.box(588,604,64,4,BLUE,2)
    f.text(588,646,'A native workspace for macOS.',24)
    f.text(90,990,'COMMUNITY / OPEN SOURCE',14,MUTED)
    f.save('01-opening.png')
    workspace_frame().save('02-workspace.png')
    workspace_frame(True).save('03-switch.png')
    # Same asset on contrasting panels verifies transparency without changing the logo file.
    f=Frame();f.box(960,0,960,H,'#20252c')
    f.logo(280,300,400);f.logo(1240,300,400)
    f.text(295,750,'Light background',24)
    f.text(1255,750,'Dark background',24,'#ffffff')
    f.save('logo-background-check.png')


if __name__=='__main__':
    main()
