"""Forever CDM Advanced logo: an ability-icon frame with a cooldown sweep.
All original vector drawing (no game art). Drawn at 4x and downsampled for clean edges."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
S = 4                      # supersample factor
N = 1024 * S               # working canvas
ORANGE = (210, 98, 31)     # the addon's chat colour, d2621f
AMBER = (255, 176, 84)
INK = (14, 11, 9)

img = Image.new("RGB", (N, N), INK)

# soft radial glow behind the icon
glow = Image.new("L", (N, N), 0)
g = ImageDraw.Draw(glow)
g.ellipse([N * 0.10, N * 0.10, N * 0.90, N * 0.90], fill=150)
glow = glow.filter(ImageFilter.GaussianBlur(N * 0.11))
img = Image.composite(Image.new("RGB", (N, N), (70, 34, 14)), img, glow)

d = ImageDraw.Draw(img, "RGBA")
cx = cy = N // 2
half = int(N * 0.335)
box = [cx - half, cy - half, cx + half, cy + half]
radius = int(N * 0.07)

# icon face: warm vertical gradient clipped to a rounded square
face = Image.new("RGB", (N, N))
fd = ImageDraw.Draw(face)
for y in range(box[1], box[3]):
    t = (y - box[1]) / (box[3] - box[1])
    fd.line([(box[0], y), (box[2], y)], fill=(int(250 - 95 * t), int(150 - 85 * t), int(52 - 30 * t)))
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
img.paste(face, (0, 0), mask)

# cooldown sweep: the dark wedge that covers the part still "on cooldown".
# 0 deg is 12 o'clock; the wedge runs clockwise from the hand back round to 12.
HAND = 118                 # degrees clockwise from 12 o'clock
sweep = Image.new("L", (N, N), 0)
big = int(half * 1.6)
ImageDraw.Draw(sweep).pieslice([cx - big, cy - big, cx + big, cy + big], start=-90 + HAND, end=270, fill=175)
sweep = Image.composite(sweep, Image.new("L", (N, N), 0), mask)   # clip to the icon
img = Image.composite(Image.new("RGB", (N, N), (10, 8, 8)), img, sweep)

d = ImageDraw.Draw(img, "RGBA")
# bright leading edge of the sweep, and the fixed 12 o'clock edge
def edge(deg, colour, width):
    a = math.radians(deg - 90)
    # extend to the frame, then the frame stroke tidies the end
    r = half * 1.45
    d.line([(cx, cy), (cx + r * math.cos(a), cy + r * math.sin(a))], fill=colour, width=width)
edge(0, (255, 225, 170, 120), int(N * 0.006))
edge(HAND, (255, 236, 190, 255), int(N * 0.011))

# re-clip anything that ran past the icon, by repainting outside the mask
outside = Image.composite(Image.new("RGB", (N, N), INK), img, Image.eval(mask, lambda v: 255 - v))
bg = Image.new("RGB", (N, N), INK)
bg = Image.composite(Image.new("RGB", (N, N), (70, 34, 14)), bg, glow)
img = Image.composite(img, bg, mask)

d = ImageDraw.Draw(img, "RGBA")
# frame: dark outer keyline, orange bevel, thin amber inner highlight
d.rounded_rectangle(box, radius, outline=(0, 0, 0, 255), width=int(N * 0.030))
inset = int(N * 0.006)
d.rounded_rectangle([box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset], radius - inset,
                    outline=ORANGE + (255,), width=int(N * 0.017))
inset2 = int(N * 0.025)
d.rounded_rectangle([box[0] + inset2, box[1] + inset2, box[2] - inset2, box[3] - inset2], radius - inset2,
                    outline=AMBER + (150,), width=int(N * 0.004))

# countdown numeral, the way a cooldown reads in game
num_font = ImageFont.truetype(r"C:\Windows\Fonts\bahnschrift.ttf", int(N * 0.30))
try:
    num_font.set_variation_by_name("Bold")
except Exception:
    pass
txt = "12"
tb = d.textbbox((0, 0), txt, font=num_font)
tx, ty = cx - (tb[2] + tb[0]) / 2, cy - (tb[3] + tb[1]) / 2
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(shadow).text((tx, ty + N * 0.008), txt, font=num_font, fill=(0, 0, 0, 230))
shadow = shadow.filter(ImageFilter.GaussianBlur(N * 0.008))
img.paste(shadow, (0, 0), shadow)
d = ImageDraw.Draw(img, "RGBA")
d.text((tx, ty), txt, font=num_font, fill=(255, 248, 232, 255),
       stroke_width=int(N * 0.006), stroke_fill=(30, 14, 4, 255))

# wordmark under the icon
word_font = ImageFont.truetype(r"C:\Windows\Fonts\bahnschrift.ttf", int(N * 0.060))
try:
    word_font.set_variation_by_name("SemiBold")
except Exception:
    pass
word = "FOREVER CDM ADV"
wb = d.textbbox((0, 0), word, font=word_font)
d.text((cx - (wb[2] + wb[0]) / 2, box[3] + N * 0.045), word, font=word_font, fill=AMBER + (255,))

img = img.resize((1024, 1024), Image.LANCZOS)
img.save(OUT, optimize=True)
img.resize((400, 400), Image.LANCZOS).save(OUT.replace(".png", "_400.png"), optimize=True)
img.resize((64, 64), Image.LANCZOS).save(OUT.replace(".png", "_64.png"))
print("saved", OUT)
