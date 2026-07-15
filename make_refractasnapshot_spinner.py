#!/usr/bin/env python3
"""Generate the animated turning-cog spinner GIF used by refractasnapshot-gui's
"Please wait, working..." dialog (patch v6, build 10.4.3.6+).

Why this exists: yad 0.40 animates images passed to --image (it loads them via
gdk_pixbuf_animation_new_from_file / gtk_image_set_from_animation), but a GIF is
binary and a `patch -p1` unified diff cannot carry binary files. So the spinner
is a committed build-dir asset, and this script is the reproducible source for
it. Requires Pillow (python3-pil).

Usage:
    python3 make_refractasnapshot_spinner.py [output.gif]
Default output: ./refractasnapshot_patched/<newest build>/spinner.gif is NOT
assumed — it writes ./spinner.gif next to this script unless a path is given.

Design:
  * 8-tooth Breeze-accent-blue (#3daee9) gear with a darker hub/outline so it
    reads on BOTH light and dark dialog backgrounds.
  * Transparent OUTSIDE the gear (no visible box). The transparent region's RGB
    is filled with the body colour so anti-aliased downscaling never leaves a
    dark fringe.
  * 8 teeth => a 45 deg turn is one full tooth period, so the 0..45 deg frame
    set loops with no visible jump.
"""
import math
import os
import sys
from PIL import Image, ImageDraw

SIZE    = 96          # final px
SS      = 4           # supersample factor
S       = SIZE * SS
C       = S / 2.0
TEETH   = 8
R_OUT   = 0.46 * S    # tooth tip
R_ROOT  = 0.35 * S    # base of teeth (gear body edge)
R_HUB   = 0.20 * S    # outer hub ring
R_HOLE  = 0.11 * S    # inner hub circle
BODY    = (61, 174, 233, 255)    # #3daee9  Breeze accent blue
OUTLINE = (28, 111, 160, 255)    # darker blue
FRAMES  = 20                     # frames spread across one 45 deg period
DUR_MS  = 55                     # per-frame duration


def gear_silhouette(rot_deg):
    pts = []
    sector = 360.0 / TEETH
    tip_frac, flank_frac = 0.42, 0.12
    for t in range(TEETH):
        base = rot_deg + t * sector
        seg = [
            (0.0,                            R_ROOT),
            (0.5 - tip_frac / 2 - flank_frac, R_ROOT),
            (0.5 - tip_frac / 2,             R_OUT),
            (0.5 + tip_frac / 2,             R_OUT),
            (0.5 + tip_frac / 2 + flank_frac, R_ROOT),
            (1.0,                            R_ROOT),
        ]
        for frac, r in seg:
            ang = math.radians(base + sector * frac)
            pts.append((C + r * math.cos(ang), C + r * math.sin(ang)))
    return pts


def make_frame(rot_deg):
    color = Image.new("RGBA", (S, S), BODY)
    d = ImageDraw.Draw(color)
    d.ellipse([C - R_HUB, C - R_HUB, C + R_HUB, C + R_HUB], fill=OUTLINE)
    d.ellipse([C - R_HOLE, C - R_HOLE, C + R_HOLE, C + R_HOLE], fill=BODY)
    poly = gear_silhouette(rot_deg)
    d.line(poly + [poly[0]], fill=OUTLINE, width=SS * 2, joint="curve")

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)

    color_small = color.resize((SIZE, SIZE), Image.LANCZOS)
    mask_small = mask.resize((SIZE, SIZE), Image.LANCZOS)
    color_small.putalpha(mask_small)
    return color_small


def to_p(frame):
    alpha = frame.getchannel("A")
    p = frame.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=255)
    p.paste(255, alpha.point(lambda a: 255 if a <= 128 else 0))
    p.info["transparency"] = 255
    return p


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "spinner.gif")
    frames = [to_p(make_frame(45.0 * i / FRAMES)) for i in range(FRAMES)]
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=DUR_MS,
                   loop=0, disposal=2, transparency=255, optimize=False)
    print("wrote", out, "(%d frames, %dx%d)" % (len(frames), SIZE, SIZE))


if __name__ == "__main__":
    main()
