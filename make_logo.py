"""Icône du Perce-Neige Simulator : la FACE AVANT de la rame, dans le rond
du tunnel — même géométrie que la caisse 3D (train_body_builder.gd) :
calotte jaune coupée à plat, grand pare-brise arrondi, deux portes
d'évacuation en D, lettrage TIGNES, bandeau sombre à deux phares halogènes
ronds, tampons aux coins. Refonte du 2026-09-27 (« reprends à zéro le
design de l'icône »).

Produit : logo.png (512), logo_64.png, logo.ico (16→256) et les icônes PWA
godot_project/pwa_icon_{144,180,512}.png (fond carré arrondi bleu nuit).

    python make_logo.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
S = 1024                      # canevas de travail (anti-crénelage par réduction)
CX, CY = 512, 512             # centre de la face
R = 400                       # rayon de la calotte (= R_BODY 1,72 m)
M = R / 1.72                  # pixels par mètre
CUT = 1.01 * M                # la calotte est coupée à plat 1,01 m sous l'axe

YELLOW = (236, 214, 38)
YELLOW_DARK = (196, 168, 18)
YELLOW_EDGE = (150, 124, 8)
NAVY = (16, 22, 36)
RING = (206, 210, 216)


def _font(size: int) -> ImageFont.FreeTypeFont:
    for cand in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "C:/Windows/Fonts/arialbd.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Bold.ttf"):
        try:
            return ImageFont.truetype(cand, size)
        except OSError:
            continue
    return ImageFont.load_default()


def face_y(y_real: float) -> float:
    """Ordonnée réelle (axe = 0, apex 1,78) → pixels, comme _face_y() du
    builder (échelle 2,93 / 3,10 depuis l'apex)."""
    y_rel = 1.72 - (1.78 - y_real) * (2.93 / 3.10)
    return CY - y_rel * M


def _face_mask() -> Image.Image:
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((CX - R, CY - R, CX + R, CY + R), fill=255)
    d.rectangle((0, CY + CUT, S, S), fill=0)
    return m


def draw_train_face(canvas: Image.Image) -> None:
    """Dessine la face de la rame sur `canvas` (RGBA, S×S)."""
    mask = _face_mask()
    face = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(face)

    # --- calotte : dégradé radial jaune (clair au centre-haut, sombre au bord)
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        col = tuple(int(YELLOW[k] * (1 - 0.55 * t * t) + YELLOW_DARK[k] * 0.55 * t * t) for k in range(3))
        rr = R * t
        d.ellipse((CX - rr - 40 * (1 - t), CY - rr - 60 * (1 - t), CX + rr - 40 * (1 - t), CY + rr - 60 * (1 - t)),
                  fill=col)
    d.rectangle((0, CY + CUT, S, S), fill=YELLOW_DARK)  # sous la coupe (sera masqué)
    # bord de la calotte
    d.ellipse((CX - R, CY - R, CX + R, CY + R), outline=YELLOW_EDGE, width=6)

    # --- portes d'évacuation en D (contours + poignées)
    x0 = 0.98 * M
    door_top = face_y(1.02)
    door_bot = min(face_y(-1.15), CY + CUT - 14)
    corner = 0.24 * M
    door_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(door_layer)
    for sx in (-1, 1):
        xa = CX + sx * x0
        xb = CX + sx * (1.62 * M + 20)
        box = (min(xa, xb), door_top, max(xa, xb), door_bot)
        dd.rounded_rectangle(box, radius=corner, outline=YELLOW_EDGE, width=7)
        dd.rounded_rectangle((box[0] + 9, box[1] + 9, box[2] - 9, box[3] - 9),
                             radius=corner - 8, outline=(255, 236, 120, 90), width=3)
        # poignée et serrure
        hx = CX + sx * 1.22 * M
        for yr in (-0.30, 0.15):
            hy = face_y(yr)
            dd.rounded_rectangle((hx - 18, hy - 8, hx + 18, hy + 8), radius=4, fill=(60, 58, 50))
    # les portes suivent la lisière : on les rabat sur rho ≤ 1,62 m
    lim = Image.new("L", (S, S), 0)
    ImageDraw.Draw(lim).ellipse((CX - 1.64 * M, CY - 1.64 * M, CX + 1.64 * M, CY + 1.64 * M), fill=255)
    door_layer.putalpha(Image.composite(door_layer.getchannel("A"), Image.new("L", (S, S), 0), lim))
    face.alpha_composite(door_layer)

    # --- pare-brise : joint noir, vitre bleu nuit dégradée, reflet
    hw = 0.76 * M
    top = face_y(1.50)
    bot = face_y(-0.38)
    rad = 0.20 * M
    gasket = 0.075 * M
    d.rounded_rectangle((CX - hw - gasket, top - gasket, CX + hw + gasket, bot + gasket),
                        radius=rad + gasket, fill=(22, 22, 26))
    glass = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glass)
    n = int(bot - top)
    for i in range(n):
        t = i / max(1, n - 1)
        col = (int(26 + 30 * (1 - t)), int(40 + 46 * (1 - t)), int(70 + 70 * (1 - t)), 255)
        gd.line((CX - hw, top + i, CX + hw, top + i), fill=col)
    gmask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gmask).rounded_rectangle((CX - hw, top, CX + hw, bot), radius=rad, fill=255)
    glass.putalpha(gmask)
    # reflet diagonal
    refl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(refl).polygon([(CX - hw + 20, top + 30), (CX - hw + 130, top + 30),
                                  (CX - hw + 60, bot - 40), (CX - hw + 20, bot - 40)],
                                 fill=(255, 255, 255, 34))
    refl.putalpha(Image.composite(refl.getchannel("A"), Image.new("L", (S, S), 0), gmask))
    glass.alpha_composite(refl)
    face.alpha_composite(glass)
    # plaque blanche « PERCE NEIGE 1 » en bas du pare-brise
    py = face_y(-0.34)
    pw, ph = 0.45 * M, 0.12 * M
    d.rounded_rectangle((CX - pw / 2, py - ph / 2, CX + pw / 2, py + ph / 2), radius=6, fill=(244, 244, 240))
    f_small = _font(12)
    d.text((CX, py - 4), "PERCE NEIGE 1", font=f_small, fill=(24, 40, 105), anchor="mm")

    # --- lettrage TIGNES, argenté avec ombre
    ty = face_y(-0.74)
    f_big = _font(64)
    for dx, dy, col in ((3, 4, (70, 60, 20)), (0, 0, (222, 222, 228))):
        d.text((CX + dx, ty + dy), "TIGNES", font=f_big, fill=col, anchor="mm")

    # --- bandeau sombre et deux phares halogènes ronds
    by = min(face_y(-1.20), CY + CUT - 0.12 * M)
    bw, bh = 1.10 * M, 0.17 * M
    d.rounded_rectangle((CX - bw / 2, by - bh / 2, CX + bw / 2, by + bh / 2), radius=8, fill=(30, 30, 34))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gl = ImageDraw.Draw(glow)
    for sx in (-1, 1):
        hx = CX + sx * 0.30 * M
        gl.ellipse((hx - 34, by - 34, hx + 34, by + 34), fill=(255, 230, 160, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    face.alpha_composite(glow)
    for sx in (-1, 1):
        hx = CX + sx * 0.30 * M
        r_ring, r_lamp = 0.085 * M, 0.072 * M
        d.ellipse((hx - r_ring, by - r_ring, hx + r_ring, by + r_ring), fill=(120, 124, 134))
        d.ellipse((hx - r_lamp, by - r_lamp, hx + r_lamp, by + r_lamp), fill=(255, 246, 214))
        d.ellipse((hx - r_lamp * 0.45, by - r_lamp * 0.45, hx + r_lamp * 0.45, by + r_lamp * 0.45),
                  fill=(255, 255, 250))

    # --- tampons ronds aux coins bas
    ty2 = min(face_y(-1.25), CY + CUT - 0.16 * M)
    for sx in (-1, 1):
        bx = CX + sx * 1.02 * M
        rb = 0.13 * M
        d.ellipse((bx - rb, ty2 - rb, bx + rb, ty2 + rb), fill=(112, 116, 126), outline=(60, 62, 70), width=4)
        d.ellipse((bx - rb * 0.45, ty2 - rb * 0.45, bx + rb * 0.45, ty2 + rb * 0.45), fill=(80, 84, 94))

    face.putalpha(Image.composite(face.getchannel("A"), Image.new("L", (S, S), 0), mask))
    canvas.alpha_composite(face)


def draw_logo(square: bool = False) -> Image.Image:
    """Icône complète : tunnel (rond ou carré arrondi), rails, ombre, face."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if square:
        d.rounded_rectangle((0, 0, S - 1, S - 1), radius=200, fill=NAVY)
    else:
        d.ellipse((16, 16, S - 16, S - 16), fill=NAVY)
        d.ellipse((16, 16, S - 16, S - 16), outline=RING, width=26)
    # anneau du tunnel (revêtement clair) derrière la rame
    d.ellipse((CX - 452, CY - 452, CX + 452, CY + 452), outline=(74, 82, 100), width=16)
    d.ellipse((CX - 428, CY - 428, CX + 428, CY + 428), outline=(52, 60, 78), width=10)
    # rails qui fuient sous la rame, arrêtés à l'anneau du tunnel
    rails = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rails)
    for sx in (-1, 1):
        rd.line((CX + sx * 70, CY + 120, CX + sx * 330, S), fill=(170, 176, 186), width=10)
    rd.line((CX, CY + 120, CX, S), fill=(120, 124, 134), width=6)   # câble
    rmask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rmask).ellipse((CX - 420, CY - 420, CX + 420, CY + 420), fill=255)
    rails.putalpha(Image.composite(rails.getchannel("A"), Image.new("L", (S, S), 0), rmask))
    img.alpha_composite(rails)
    # ombre portée
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((CX - R - 10, CY - R + 30, CX + R + 10, CY + R + 50), fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(26))
    img.alpha_composite(sh)
    draw_train_face(img)
    return img


def main() -> None:
    big = draw_logo()
    png512 = big.resize((512, 512), Image.Resampling.LANCZOS)
    png512.save(HERE / "logo.png")
    big.resize((64, 64), Image.Resampling.LANCZOS).save(HERE / "logo_64.png")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    png256 = big.resize((256, 256), Image.Resampling.LANCZOS)
    png256.save(HERE / "logo.ico", format="ICO", sizes=sizes)
    sq = draw_logo(square=True)
    for px in (144, 180, 512):
        sq.resize((px, px), Image.Resampling.LANCZOS).save(HERE / "godot_project" / f"pwa_icon_{px}.png")
    print("wrote logo.png, logo_64.png, logo.ico, pwa_icon_144/180/512.png")


if __name__ == "__main__":
    main()
