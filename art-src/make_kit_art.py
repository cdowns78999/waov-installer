"""make_kit_art.py - builds the launcher art and sound for the WAOV installer kit (2026-11-09).
Run:  python -I make_kit_art.py
Writes into ..\\launcher\\ :
  base.png          loading-base-1.png snapped to the EGA 16 colour palette (Chad's pick by default: image 1)
  cat-0..3.png      4 frame original pixel cat (ours, never Nyan Cat), 4x scaled
  trail.png         short rainbow trail tile, 4x scaled
  chiptune.wav      original ~8 s loop, square wave melody + triangle bass, 22050 Hz mono 16 bit
  beep.wav          short menu click beep
  waov.ico          copy of the icon
  contact-sheet.png everything on one sheet for Chad
"""
import math, os, shutil, struct, wave
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = r"C:\Users\chad\OneDrive\Documents\GitHub\00102-build\waov-comm-assets\i-install"   # base images and icon live here
OUT = os.path.join(HERE, "..", "launcher")
EGA = ["#000000", "#0000AA", "#00AA00", "#00AAAA", "#AA0000", "#AA00AA", "#AA5500", "#AAAAAA",
       "#555555", "#5555FF", "#55FF55", "#55FFFF", "#FF5555", "#FF55FF", "#FFFF55", "#FFFFFF"]
RAINBOW = ["#ff0040", "#ff8000", "#ffe000", "#00d040", "#00e0ff", "#0060ff", "#a000ff"]


def rgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def snap_base(src, dst):
    pal = Image.new("P", (1, 1))
    flat = []
    for h in EGA:
        flat += list(rgb(h))
    pal.putpalette(flat + [0, 0, 0] * (256 - 16))
    im = Image.open(src).convert("RGB")
    snapped = im.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
    snapped.save(dst)
    return snapped


# original cat, 16 x 11 cells: K outline, G grey body, W white, P pink, . empty ; legs differ per frame
CAT_BODY = [
    "..K.......K.....",
    ".KGK.....KGK....",
    ".KGGKKKKKGGK....",
    "KGGGGGGGGGGGK...",
    "KGWKGGGGWKGGK..K",
    "KGGGGPPGGGGGK.KG",
    "KGGGGGGGGGGGKKGK",
    ".KGGGGGGGGGGGGK.",
    "..KGGGGGGGGGGK..",
]
CAT_LEGS = [
    ["..KK..KK..KK.KK.", "..K...K....K..K."],
    ["...KK..KK..KK.KK", "....K...K..K...K"],
    ["..KK..KK.KK..KK.", ".K....K...K...K."],
    [".KK..KK..KK..KK.", ".K...K...K...K.."],
]
COL = {"K": (0, 0, 0, 255), "G": rgb("#AAAAAA") + (255,), "W": (255, 255, 255, 255), "P": rgb("#FF55FF") + (255,)}


def cat_frame(i, scale=4):
    rows = CAT_BODY + CAT_LEGS[i]
    im = Image.new("RGBA", (16, len(rows)), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in COL:
                im.putpixel((x, y), COL[ch])
    return im.resize((16 * scale, len(rows) * scale), Image.NEAREST)


def trail(scale=4):
    im = Image.new("RGBA", (8, 7), (0, 0, 0, 0))
    for y, h in enumerate(RAINBOW):
        for x in range(8):
            if (x + y) % 4 != 3:       # little gaps so it shimmers when it scrolls
                im.putpixel((x, y), rgb(h) + (255,))
    return im.resize((8 * scale, 7 * scale), Image.NEAREST)


def write_wav(path, samples, rate=22050):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))


def note_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def chiptune(rate=22050):
    # original 4 bar loop, 120 bpm, eighth notes; C major, upbeat. MIDI numbers, 0 = rest
    melody = [72, 76, 79, 76, 77, 76, 74, 0,  71, 74, 77, 74, 76, 74, 72, 0,
              69, 72, 76, 72, 74, 72, 71, 72, 74, 77, 79, 77, 76, 74, 72, 0]
    bass = [48, 48, 55, 55, 53, 53, 55, 55]  # one per half bar
    eighth = 0.25
    out = []
    for i, m in enumerate(melody):
        b = bass[i // 4]
        n = int(rate * eighth)
        for k in range(n):
            t = k / rate
            env = max(0.0, 1.0 - k / n * 0.9)
            s = 0.0
            if m:
                s += 0.22 * env * (1 if math.sin(2 * math.pi * note_hz(m) * t) >= 0 else -1)
            ph = (note_hz(b) * t) % 1.0
            s += 0.28 * (4 * abs(ph - 0.5) - 1)
            out.append(s)
    return out


def beep(rate=22050):
    n = int(rate * 0.06)
    return [0.25 * (1 if math.sin(2 * math.pi * 880 * k / rate) >= 0 else -1) * (1 - k / n) for k in range(n)]


def main():
    os.makedirs(OUT, exist_ok=True)
    base = snap_base(os.path.join(ASSETS, "loading-base-1.png"), os.path.join(OUT, "base.png"))
    frames = [cat_frame(i) for i in range(4)]
    for i, f in enumerate(frames):
        f.save(os.path.join(OUT, f"cat-{i}.png"))
    tr = trail(); tr.save(os.path.join(OUT, "trail.png"))
    write_wav(os.path.join(OUT, "chiptune.wav"), chiptune())
    write_wav(os.path.join(OUT, "beep.wav"), beep())
    shutil.copy(os.path.join(ASSETS, "icon", "waov.ico"), os.path.join(OUT, "waov.ico"))

    sheet = Image.new("RGB", (1376, 768 + 140), (85, 85, 85))
    sheet.paste(base, (0, 0))
    x = 20
    for f in frames:
        sheet.paste(f, (x, 790), f); x += 90
    for k in range(4):
        sheet.paste(tr, (x + k * 32, 800), tr)
    sheet.paste(frames[0], (x + 4 * 32, 790), frames[0])
    sheet.save(os.path.join(OUT, "contact-sheet.png"))
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
