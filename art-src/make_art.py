# Miles Installer and Updater, kit step 1: original 8-bit art (Keen STYLE only, EGA palette, our own sprites).
# Writes into ../launcher/art/: sprites_sheet.png (every sprite, big, labeled), scene_preview.png (one frame, 960x600),
# loading_scene.gif (the animated loading scene), plus each sprite as its own PNG for the PS1 window.
# Also writes ../launcher/sound/chiptune.wav (original 8 s loop, square + triangle waves).
# Run: python -I make_art.py   (Pillow needed; no network)
import os, math, wave, struct
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "launcher", "art")
SND = os.path.join(HERE, "..", "launcher", "sound")
os.makedirs(ART, exist_ok=True); os.makedirs(SND, exist_ok=True)

# EGA 16 plus two extras (peach skin, deep night) so faces read well
PAL = {"0": (0, 0, 0), "1": (0, 0, 170), "2": (0, 170, 0), "3": (0, 170, 170), "4": (170, 0, 0), "5": (170, 0, 170),
       "6": (170, 85, 0), "7": (170, 170, 170), "8": (85, 85, 85), "9": (85, 85, 255), "A": (85, 255, 85),
       "B": (85, 255, 255), "C": (255, 85, 85), "D": (255, 85, 255), "E": (255, 255, 85), "F": (255, 255, 255),
       "S": (255, 200, 150), "K": (0, 0, 0), "N": (10, 10, 40)}

PERSON = [
    "...HHHHHH...",
    "..HHHHHHHH..",
    ".HHHHHHHHHH.",
    ".HHSSSSSSHH.",
    ".HSSKSSKSSH.",
    ".HSSKSSKSSH.",
    ".HSSSSSSSSH.",
    ".HSSSKKSSSH.",
    "..SSSSSSSS..",
    "....SSSS....",
    "..TTTTTTTT..",
    ".TTTAAAATTT.",
    "STTTAAAATTTS",
    "S.TTTTTTTT.S",
    "..TTTTTTTT..",
    "..PPPPPPPP..",
    "..PPP..PPP..",
    "..PPP..PPP..",
    "..PPP..PPP..",
    ".BBBB..BBBB.",
]
CAST = {  # our animation cast: singer, villain, drummer
    "singer":  {"H": "D", "T": "5", "A": "E", "P": "1", "B": "0"},
    "villain": {"H": "8", "T": "4", "A": "0", "P": "0", "B": "4"},
    "drummer": {"H": "6", "T": "1", "A": "B", "P": "8", "B": "0"},
}
MIC = [".888..", "88888.", "88888.", ".888..", "..7...", "..7...", "..7...", "..7...", "..7...", "..7...",
       "..7...", "..7...", "..7...", "..7...", "..7...", "..7...", "..7...", "77777."]
NOTE = ["....FF..", "....F.F.", "....F..F", "....F...", "....F...", ".FFFF...", "FFFFF...", ".FFF...."]
CAT_TOP = ["..........K...K.", "..........KK.KK.", "K.........K777K.", ".K.KKKKKKKK7K7K.", "..K77777777777KC",
           "..K7777777777KK.", "..K7777777777K..", "...KKKKKKKKKKK.."]
CAT_A = CAT_TOP + ["...K.K....K.K...", "................"]
CAT_B = CAT_TOP + ["..K...K..K...K..", "................"]
RAINBOW = ["C", "6", "E", "A", "9", "D"]

FONT = {
    "W": ["X...X", "X...X", "X...X", "X.X.X", "X.X.X", "XX.XX", "X...X"],
    "E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
    "A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
    "R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
    "O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
    "N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X"],
    "V": ["X...X", "X...X", "X...X", "X...X", "X...X", ".X.X.", "..X.."],
    "I": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "XXXXX"],
    "C": [".XXXX", "X....", "X....", "X....", "X....", "X....", ".XXXX"],
    "L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
    "D": ["XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."],
    "G": [".XXXX", "X....", "X....", "X.XXX", "X...X", "X...X", ".XXX."],
    ".": [".....", ".....", ".....", ".....", ".....", ".XX..", ".XX.."],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}

def sprite(rows, subs=None):
    subs = subs or {}
    im = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == ".":
                continue
            ch = subs.get(ch, ch)
            im.putpixel((x, y), PAL[ch] + (255,))
    return im

def person(cast, mouth_open):
    rows = list(PERSON)
    if mouth_open:
        rows[7] = ".HSSSCCSSSH."
        rows[8] = "..SSSCCSSS.."
    return sprite(rows, CAST[cast])

def text_img(txt, px, top=(255, 255, 85), bottom=(255, 85, 85), outline=True, shadow=True):
    w = len(txt) * 6 * px; h = 7 * px
    im = Image.new("RGBA", (w + 4 * px // 2 + 4, h + 4), (0, 0, 0, 0))
    mask = Image.new("L", im.size, 0); md = ImageDraw.Draw(mask)
    for i, ch in enumerate(txt):
        g = FONT[ch]
        for y, r in enumerate(g):
            for x, c in enumerate(r):
                if c == "X":
                    md.rectangle([2 + (i * 6 + x) * px, 2 + y * px, 2 + (i * 6 + x + 1) * px - 1, 2 + (y + 1) * px - 1], fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    if shadow:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); sh.putalpha(mask)
        out.alpha_composite(Image.new("RGBA", im.size, PAL["5"] + (255,)).crop((0, 0) + im.size), (0, 0))
        out = Image.new("RGBA", im.size, (0, 0, 0, 0))
        dark = Image.new("RGBA", im.size, PAL["5"] + (255,)); dark.putalpha(mask)
        out.alpha_composite(dark, (2, 2)) if False else out.paste(dark, (2, 2), dark)
    if outline:
        k = Image.new("RGBA", im.size, (0, 0, 0, 255)); k.putalpha(mask)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            out.paste(k, (dx, dy), k)
    grad = Image.new("RGBA", im.size)
    for y in range(im.size[1]):
        t = max(0.0, min(1.0, (y - 2) / max(1, h - 1)))
        col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        ImageDraw.Draw(grad).line([(0, y), (im.size[0], y)], fill=col + (255,))
    grad.putalpha(mask)
    out.paste(grad, (0, 0), grad)
    return out

W, H = 320, 200
STARS = [((x * 73) % W, (x * 37) % 90) for x in range(1, 40)]

def background():
    bg = Image.new("RGBA", (W, H), PAL["N"] + (255,))
    d = ImageDraw.Draw(bg)
    for y in range(0, 120):
        t = y / 120
        d.line([(0, y), (W, y)], fill=(int(10 + 0 * t), int(10 + 0 * t), int(40 + 130 * t), 255))
    for i, (x, y) in enumerate(STARS):
        bg.putpixel((x, y), PAL["F" if i % 3 else "E"] + (255,))
    for x in range(W):  # back hills
        h1 = int(118 + 10 * math.sin(x / 23.0) + 6 * math.sin(x / 9.0))
        d.line([(x, h1), (x, H)], fill=PAL["2"] + (255,))
    for x in range(W):  # front hills with a light rim
        h2 = int(138 + 8 * math.sin(x / 31.0 + 1.3) + 4 * math.sin(x / 7.0))
        d.line([(x, h2), (x, H)], fill=PAL["A"] + (255,))
        bg.putpixel((x, h2), PAL["F"] + (255,))
    d.rectangle([60, 150, 260, 158], fill=PAL["6"] + (255,))   # stage
    d.line([(60, 150), (260, 150)], fill=PAL["E"] + (255,))
    d.rectangle([60, 159, 260, 166], fill=PAL["4"] + (255,))
    return bg

def big(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)

def frame(n, total):
    f = background()
    logo = text_img("WE ARE ONE VOICE", 3)
    bounce = int(round(3 * abs(math.sin(n / 3.0)))) if n < total else 0
    f.alpha_composite(logo, ((W - logo.width) // 2, 14 - bounce))
    active = (n // 6) % 3
    xs = {"singer": 100, "villain": 154, "drummer": 208}
    for k, (cast, x) in enumerate(xs.items()):
        open_ = (k == active) and (n % 2 == 0)
        hop = 1 if (k == active and n % 4 < 2) else 0
        f.alpha_composite(person(cast, open_), (x, 130 - hop))
        if k == active:
            f.alpha_composite(sprite(MIC), (x + 12, 132))
    note = sprite(NOTE)
    for j in range(3):
        y = 120 - ((n * 3 + j * 17) % 50)
        x = xs[list(xs)[active]] + 4 + int(6 * math.sin((n + j * 5) / 3.0)) + j * 7
        f.alpha_composite(note, (x, y))
    # loading bar
    d = ImageDraw.Draw(f)
    d.rectangle([40, 182, 280, 190], outline=PAL["F"] + (255,), fill=PAL["0"] + (255,))
    fill = 41 + int(238 * min(1.0, n / max(1, total - 1)))
    d.rectangle([41, 183, fill, 189], fill=PAL["3"] + (255,))
    for i, c in enumerate(RAINBOW):  # rainbow trail behind the cat
        wob = 1 if (n + i) % 4 < 2 else 0
        d.line([(max(41, fill - 60), 170 + i + wob), (fill - 6, 170 + i + wob)], fill=PAL[c] + (255,))
    f.alpha_composite(sprite(CAT_A if n % 2 == 0 else CAT_B), (min(fill - 8, 264), 166))
    lt = text_img("LOADING" + "." * (n % 4), 1, top=(255, 255, 255), bottom=(170, 170, 170), shadow=False)
    f.alpha_composite(lt, (40, 192 - lt.height // 2 - 2))
    return f

TOTAL = 36
frames = [big(frame(n, TOTAL), 3).convert("P", palette=Image.ADAPTIVE, colors=64) for n in range(TOTAL)]
frames[0].save(os.path.join(ART, "loading_scene.gif"), save_all=True, append_images=frames[1:], duration=120, loop=0)
big(frame(20, TOTAL), 3).save(os.path.join(ART, "scene_preview.png"))

# single sprites for the PS1 window (kept at pixel size; the window scales them with hard edges)
singles = {"logo": text_img("WE ARE ONE VOICE", 3), "mic": sprite(MIC), "note": sprite(NOTE),
           "cat_a": sprite(CAT_A), "cat_b": sprite(CAT_B)}
for c in CAST:
    singles[c + "_closed"] = person(c, False); singles[c + "_open"] = person(c, True)
for k, im in singles.items():
    im.save(os.path.join(ART, k + ".png"))

# sheet: every sprite at 8x with its name
items = [(k, v) for k, v in singles.items() if k != "logo"]
cell = 140
sheet = Image.new("RGBA", (cell * 6, cell * 2 + 140), PAL["8"] + (255,))
sd = ImageDraw.Draw(sheet)
for i, (k, im) in enumerate(items):
    s = big(im, 6 if im.height <= 20 else 5)
    cx, cy = (i % 6) * cell, (i // 6) * cell
    sheet.alpha_composite(s, (cx + (cell - s.width) // 2, cy + 8))
    sd.text((cx + 6, cy + cell - 16), k, fill=(255, 255, 255, 255))
lg = big(singles["logo"], 2)
sheet.alpha_composite(lg, ((sheet.width - lg.width) // 2, cell * 2 + 30))
sheet.save(os.path.join(ART, "sprites_sheet.png"))

# chiptune: original 8 s loop, square lead + triangle bass, 22050 Hz mono
RATE = 22050
def tone(freq, dur, kind, vol):
    n = int(RATE * dur); out = []
    for i in range(n):
        if freq <= 0:
            out.append(0.0); continue
        ph = (i * freq / RATE) % 1.0
        v = (1.0 if ph < 0.5 else -1.0) if kind == "sq" else (4 * abs(ph - 0.5) - 1)
        env = min(1.0, i / 200) * min(1.0, (n - i) / 400)
        out.append(v * vol * env)
    return out
def hz(note):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    return 440.0 * 2 ** ((names[note[0]] + 12 * (int(note[1]) - 4)) / 12)
lead = "E5 G5 A5 G5 E5 D5 C5 D5 E5 E5 G5 C6 B5 A5 G5 R E5 G5 A5 G5 E5 D5 C5 E5 D5 D5 E5 D5 C5 R C5 R".split()
bass = "C3 C3 A2 A2 F2 F2 G2 G2".split()
L = []
for nt in lead:
    L += tone(0 if nt == "R" else hz(nt), 0.25, "sq", 0.18)
B = []
for nt in bass:
    B += tone(hz(nt), 1.0, "tri", 0.30)
n = max(len(L), len(B)); L += [0.0] * (n - len(L)); B += [0.0] * (n - len(B))
with wave.open(os.path.join(SND, "chiptune.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, a + b)) * 32000)) for a, b in zip(L, B)))
print("ART", sorted(os.listdir(ART)))
print("SOUND", os.listdir(SND), round(n / RATE, 2), "s")
