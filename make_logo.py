"""Icône du Perce-Neige Simulator : la FACE AVANT de la rame, dans le rond
du tunnel — même géométrie que la caisse 3D (train_body_builder.gd) :
calotte jaune coupée à plat, grand pare-brise arrondi, deux portes
d'évacuation en D, lettrage TIGNES, bandeau sombre à deux phares halogènes
ronds, tampons aux coins. Refonte du 2026-09-27 (« reprends à zéro le
design de l'icône »).

UNE SEULE SOURCE (standard des applications, 14/10/2026) : ce script écrit
`logo.svg` (et `logo_carre.svg`, la variante sur carré arrondi des icônes
web), puis en tire TOUTES les images par le rendu SVG de Qt — jamais deux
logos différents selon l'endroit :

    logo.svg            source vectorielle (aussi dans l'application)
    logo_1024.png       grande icône (macOS, manuel)
    logo.png (512)      entrée de menu Linux, « À propos »
    logo_64.png         petite icône
    logo.ico            Windows, 16 → 256 px
    logo.icns           macOS
    godot_project/pwa_icon_{144,180,512}.png   version Web (carré arrondi)

Les lettrages sont convertis en tracés depuis la police embarquée
(polices/selawkb.ttf) : le SVG ne dépend d'aucune police du système.

    python make_logo.py          (PyQt6, Pillow, fontTools)
"""
from __future__ import annotations

import io
from pathlib import Path

HERE = Path(__file__).resolve().parent
S = 1024                      # canevas de travail
CX, CY = 512, 512             # centre de la face
R = 400                       # rayon de la calotte (= R_BODY 1,72 m)
M = R / 1.72                  # pixels par mètre
CUT = 1.01 * M                # la calotte est coupée à plat 1,01 m sous l'axe

YELLOW = (236, 214, 38)
YELLOW_DARK = (196, 168, 18)
YELLOW_EDGE = (150, 124, 8)
NAVY = (16, 22, 36)
RING = (206, 210, 216)
POLICE = HERE / "polices" / "selawkb.ttf"


def rgb(c) -> str:
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in c[:3])


def f(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def face_y(y_real: float) -> float:
    """Ordonnée réelle (axe = 0, apex 1,78) → pixels, comme _face_y() du
    builder (échelle 2,93 / 3,10 depuis l'apex)."""
    y_rel = 1.72 - (1.78 - y_real) * (2.93 / 3.10)
    return CY - y_rel * M


def rrect(x0, y0, x1, y1, r, **attrs) -> str:
    """Rectangle arrondi (coordonnées de boîte, comme ImageDraw)."""
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return (f'<rect x="{f(x0)}" y="{f(y0)}" width="{f(x1 - x0)}" height="{f(y1 - y0)}" '
            f'rx="{f(r)}" ry="{f(r)}" {extra}/>')


def arc_coupe(r: float) -> str:
    """Arc du cercle de rayon r au-dessus de la corde y = CY + CUT."""
    import math
    dx = math.sqrt(max(r * r - CUT * CUT, 0.0))
    y = CY + CUT
    return f"M {f(CX - dx)} {f(y)} A {f(r)} {f(r)} 0 1 1 {f(CX + dx)} {f(y)}"


def calotte_coupee(r: float) -> str:
    """Disque de rayon r coupé à plat par la corde y = CY + CUT."""
    return arc_coupe(r) + " Z"


def segment_dans_cercle(x0, y0, x1, y1, r):
    """Le segment arrêté au cercle (CX, CY, r) : (x0,y0) est dedans."""
    import math
    dx, dy = x1 - x0, y1 - y0
    ax, ay = x0 - CX, y0 - CY
    a = dx * dx + dy * dy
    b = 2 * (ax * dx + ay * dy)
    c = ax * ax + ay * ay - r * r
    t = (-b + math.sqrt(b * b - 4 * a * c)) / (2 * a)
    t = min(1.0, t)
    return x0, y0, x0 + t * dx, y0 + t * dy


def contour_rrect(x0, y0, x1, y1, r, pas: int = 24):
    """Contour fermé d'un rectangle arrondi, en points (sens horaire)."""
    import math
    coins = ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180))
    pts = []
    for cx, cy, a0 in coins:
        for i in range(pas + 1):
            a = math.radians(a0 + 90 * i / pas)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts.append(pts[0])
    return pts


def polylignes_dans(pts, rayon):
    """Les morceaux du contour qui restent dans le cercle (CX, CY, rayon),
    arrêtés exactement au cercle."""
    import math

    def dedans(p):
        return math.hypot(p[0] - CX, p[1] - CY) <= rayon

    def croisement(a, b):
        lo, hi = 0.0, 1.0                      # dichotomie : a dedans, b dehors
        for _ in range(40):
            m = (lo + hi) / 2
            q = (a[0] + m * (b[0] - a[0]), a[1] + m * (b[1] - a[1]))
            lo, hi = (m, hi) if dedans(q) else (lo, m)
        return (a[0] + lo * (b[0] - a[0]), a[1] + lo * (b[1] - a[1]))

    # on part d'un point extérieur pour ne pas couper un morceau en deux
    debut = next((i for i, p in enumerate(pts[:-1]) if not dedans(p)), None)
    if debut is None:
        return [pts]
    tour = pts[debut:-1] + pts[:debut + 1]
    lignes, courante = [], []
    for a, b in zip(tour, tour[1:]):
        if dedans(a) and dedans(b):
            courante.append(b)
        elif dedans(a) and not dedans(b):
            courante.append(croisement(a, b))
            lignes.append(courante)
            courante = []
        elif not dedans(a) and dedans(b):
            courante = [croisement(b, a), b]
    if courante:
        lignes.append(courante)
    return [l for l in lignes if len(l) >= 2]


def texte_en_traces(txt: str, cx: float, cy: float, taille: float, couleur) -> str:
    """Texte centré (ancre « mm » de Pillow) converti en tracés."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.ttLib import TTFont
    police = TTFont(str(POLICE))
    glyphes = police.getGlyphSet()
    cmap = police.getBestCmap()
    upm = police["head"].unitsPerEm
    hhea = police["hhea"]
    k = taille / upm
    noms = [cmap.get(ord(c), ".notdef") for c in txt]
    largeur = sum(glyphes[n].width for n in noms) * k
    base = cy + (hhea.ascent + hhea.descent) / 2 * k
    x = cx - largeur / 2
    morceaux = []
    for n in noms:
        stylo = SVGPathPen(glyphes)
        glyphes[n].draw(stylo)
        d = stylo.getCommands()
        if d:
            morceaux.append(f'<path transform="translate({f(x)} {f(base)}) scale({k:.5f} {-k:.5f})" '
                            f'd="{d}"/>')
        x += glyphes[n].width * k
    return f'<g fill="{rgb(couleur)}">' + "".join(morceaux) + "</g>"


def svg_face() -> str:
    """La face de la rame (calotte, portes, pare-brise, lettrage, phares)."""
    out = []
    cut_y = CY + CUT
    # --- calotte : dégradé radial jaune, clair vers le haut à gauche
    stops = []
    for i in range(0, 11):
        t = i / 10
        col = tuple(YELLOW[c] * (1 - 0.55 * t * t) + YELLOW_DARK[c] * 0.55 * t * t for c in range(3))
        stops.append(f'<stop offset="{t:.2f}" stop-color="{rgb(col)}"/>')
    out.append(f'<radialGradient id="calotte" gradientUnits="userSpaceOnUse" cx="{CX}" cy="{CY}" '
               f'r="{R}" fx="{CX - 40}" fy="{CY - 60}">' + "".join(stops) + "</radialGradient>")
    out.append(f'<linearGradient id="vitre" gradientUnits="userSpaceOnUse" x1="0" y1="{f(face_y(1.50))}" '
               f'x2="0" y2="{f(face_y(-0.38))}"><stop offset="0" stop-color="{rgb((56, 86, 140))}"/>'
               f'<stop offset="1" stop-color="{rgb((26, 40, 70))}"/></linearGradient>')
    out.append('<radialGradient id="halo"><stop offset="0" stop-color="#ffe6a0" stop-opacity="0.47"/>'
               '<stop offset="0.45" stop-color="#ffe6a0" stop-opacity="0.38"/>'
               '<stop offset="1" stop-color="#ffe6a0" stop-opacity="0"/></radialGradient>')
    defs = "".join(out)
    out = []
    # Aucune découpe (clipPath) : le rendu SVG de Qt ne les applique pas, et
    # le logo doit sortir identique partout. Les formes sont donc découpées
    # géométriquement : calotte = disque coupé par sa corde.
    calotte = calotte_coupee(R)
    out.append(f'<path d="{calotte}" fill="url(#calotte)"/>')
    out.append(f'<path d="{arc_coupe(R - 3)}" fill="none" stroke="{rgb(YELLOW_EDGE)}" '
               f'stroke-width="6"/>')
    # --- portes d'évacuation en D (contours + poignées), rabattues sur la lisière
    x0 = 0.98 * M
    door_top = face_y(1.02)
    door_bot = min(face_y(-1.15), cut_y - 14)
    corner = 0.24 * M
    portes = []
    lisiere = 1.64 * M
    for sx in (-1, 1):
        xa = CX + sx * x0
        xb = CX + sx * (1.62 * M + 20)
        bx0, bx1 = min(xa, xb), max(xa, xb)
        # les portes suivent la lisière (rho ≤ 1,64 m) : leurs contours
        # s'arrêtent au cercle, côté extérieur ouvert comme sur la caisse 3D
        for inset, rayon, trait, attrs in (
                (3.5, corner - 3.5, 7, f'stroke="{rgb(YELLOW_EDGE)}"'),
                (10.5, corner - 9.5, 3, 'stroke="#ffec78" stroke-opacity="0.35"')):
            pts = contour_rrect(bx0 + inset, door_top + inset, bx1 - inset, door_bot - inset, rayon)
            for ligne in polylignes_dans(pts, lisiere):
                portes.append('<polyline points="' + " ".join(f"{f(x)},{f(y)}" for x, y in ligne)
                              + f'" fill="none" {attrs} stroke-width="{trait}" '
                              'stroke-linejoin="round"/>')
        hx = CX + sx * 1.22 * M
        for yr in (-0.30, 0.15):
            hy = face_y(yr)
            portes.append(rrect(hx - 18, hy - 8, hx + 18, hy + 8, 4, fill=rgb((60, 58, 50))))
    out.extend(portes)

    # --- pare-brise : joint noir, vitre bleu nuit dégradée, reflet
    hw = 0.76 * M
    top = face_y(1.50)
    bot = face_y(-0.38)
    rad = 0.20 * M
    gasket = 0.075 * M
    out.append(rrect(CX - hw - gasket, top - gasket, CX + hw + gasket, bot + gasket, rad + gasket,
                     fill=rgb((22, 22, 26))))
    out.append(rrect(CX - hw, top, CX + hw, bot, rad, fill="url(#vitre)"))
    pts = [(CX - hw + 20, top + 30), (CX - hw + 130, top + 30),
           (CX - hw + 60, bot - 40), (CX - hw + 20, bot - 40)]
    out.append('<polygon points="' + " ".join(f"{f(x)},{f(y)}" for x, y in pts)
               + '" fill="#ffffff" fill-opacity="0.13"/>')
    # plaque blanche « PERCE NEIGE 1 » en bas du pare-brise
    py = face_y(-0.34)
    pw, ph = 0.45 * M, 0.12 * M
    out.append(rrect(CX - pw / 2, py - ph / 2, CX + pw / 2, py + ph / 2, 6, fill=rgb((244, 244, 240))))
    out.append(texte_en_traces("PERCE NEIGE 1", CX, py - 1, 14, (24, 40, 105)))

    # --- lettrage TIGNES, argenté avec ombre
    ty = face_y(-0.74)
    out.append(texte_en_traces("TIGNES", CX + 3, ty + 4, 70, (70, 60, 20)))
    out.append(texte_en_traces("TIGNES", CX, ty, 70, (222, 222, 228)))

    # --- bandeau sombre et deux phares halogènes ronds
    by = min(face_y(-1.20), cut_y - 0.12 * M)
    bw, bh = 1.10 * M, 0.17 * M
    out.append(rrect(CX - bw / 2, by - bh / 2, CX + bw / 2, by + bh / 2, 8, fill=rgb((30, 30, 34))))
    for sx in (-1, 1):
        hx = CX + sx * 0.30 * M
        out.append(f'<ellipse cx="{f(hx)}" cy="{f(by)}" rx="60" ry="{f(cut_y - by)}" '
                   'fill="url(#halo)"/>')
    for sx in (-1, 1):
        hx = CX + sx * 0.30 * M
        r_ring, r_lamp = 0.085 * M, 0.072 * M
        out.append(f'<circle cx="{f(hx)}" cy="{f(by)}" r="{f(r_ring)}" fill="{rgb((120, 124, 134))}"/>')
        out.append(f'<circle cx="{f(hx)}" cy="{f(by)}" r="{f(r_lamp)}" fill="{rgb((255, 246, 214))}"/>')
        out.append(f'<circle cx="{f(hx)}" cy="{f(by)}" r="{f(r_lamp * 0.45)}" '
                   f'fill="{rgb((255, 255, 250))}"/>')

    # --- tampons ronds aux coins bas
    ty2 = min(face_y(-1.25), cut_y - 0.16 * M)
    for sx in (-1, 1):
        bx = CX + sx * 1.02 * M
        rb = 0.13 * M
        out.append(f'<circle cx="{f(bx)}" cy="{f(ty2)}" r="{f(rb - 2)}" fill="{rgb((112, 116, 126))}" '
                   f'stroke="{rgb((60, 62, 70))}" stroke-width="4"/>')
        out.append(f'<circle cx="{f(bx)}" cy="{f(ty2)}" r="{f(rb * 0.45)}" fill="{rgb((80, 84, 94))}"/>')

    return defs, "".join(out)


def svg_logo(carre: bool = False) -> str:
    """Icône complète : tunnel (rond ou carré arrondi), rails, ombre, face."""
    defs_face, face = svg_face()
    fond = (rrect(0, 0, S, S, 200, fill=rgb(NAVY)) if carre else
            f'<circle cx="{CX}" cy="{CY}" r="496" fill="{rgb(NAVY)}"/>'
            f'<circle cx="{CX}" cy="{CY}" r="483" fill="none" stroke="{rgb(RING)}" stroke-width="26"/>')
    anneaux = (f'<circle cx="{CX}" cy="{CY}" r="444" fill="none" stroke="{rgb((74, 82, 100))}" '
               f'stroke-width="16"/>'
               f'<circle cx="{CX}" cy="{CY}" r="423" fill="none" stroke="{rgb((52, 60, 78))}" '
               f'stroke-width="10"/>')
    rails = ""
    for sx in (-1, 1):
        a, b, c, d = segment_dans_cercle(CX + sx * 70, CY + 120, CX + sx * 330, S, 420)
        rails += (f'<line x1="{f(a)}" y1="{f(b)}" x2="{f(c)}" y2="{f(d)}" '
                  f'stroke="{rgb((170, 176, 186))}" stroke-width="10"/>')
    rails += (f'<line x1="{CX}" y1="{CY + 120}" x2="{CX}" y2="{CY + 420}" '
              f'stroke="{rgb((120, 124, 134))}" stroke-width="6"/>')
    ombre = (f'<radialGradient id="ombre" gradientUnits="userSpaceOnUse" cx="{CX}" cy="{CY + 40}" r="470">'
             '<stop offset="0" stop-color="#000" stop-opacity="0.59"/>'
             '<stop offset="0.80" stop-color="#000" stop-opacity="0.55"/>'
             '<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>')
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="{S}" height="{S}" '
            f'viewBox="0 0 {S} {S}">\n'
            '<title>Perce-Neige Simulator</title>\n'
            f'<defs>{defs_face}{ombre}</defs>\n'
            f'{fond}{anneaux}{rails}'
            f'<circle cx="{CX}" cy="{CY + 40}" r="470" fill="url(#ombre)"/>\n{face}\n</svg>\n')


def rendre(svg: str, taille: int):
    """Rendu du SVG par Qt (QtSvg) en image Pillow RGBA."""
    from PIL import Image
    from PyQt6.QtCore import QBuffer, QByteArray, QIODevice, Qt
    from PyQt6.QtGui import QGuiApplication, QImage, QPainter
    from PyQt6.QtSvg import QSvgRenderer
    _app = QGuiApplication.instance() or QGuiApplication(["make_logo"])  # noqa: F841
    rendu = QSvgRenderer(QByteArray(svg.encode("utf-8")))
    assert rendu.isValid(), "SVG illisible par Qt"
    img = QImage(taille, taille, QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(Qt.GlobalColor.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
    rendu.render(p)
    p.end()
    tampon = QBuffer()
    tampon.open(QIODevice.OpenModeFlag.WriteOnly)
    img.save(tampon, "PNG")
    return Image.open(io.BytesIO(bytes(tampon.data()))).convert("RGBA")


def main() -> None:
    import os
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PIL import Image
    rond, carre = svg_logo(), svg_logo(carre=True)
    (HERE / "logo.svg").write_text(rond, encoding="utf-8")
    (HERE / "logo_carre.svg").write_text(carre, encoding="utf-8")
    grand = rendre(rond, 2048).resize((1024, 1024), Image.Resampling.LANCZOS)
    grand.save(HERE / "logo_1024.png")
    grand.resize((512, 512), Image.Resampling.LANCZOS).save(HERE / "logo.png")
    grand.resize((64, 64), Image.Resampling.LANCZOS).save(HERE / "logo_64.png")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    grand.save(HERE / "logo.ico", format="ICO", sizes=sizes)
    grand.save(HERE / "logo.icns", format="ICNS")
    sq = rendre(carre, 1024)
    for px in (144, 180, 512):
        sq.resize((px, px), Image.Resampling.LANCZOS).save(
            HERE / "godot_project" / f"pwa_icon_{px}.png")
    print("écrit : logo.svg, logo_carre.svg, logo_1024.png, logo.png, logo_64.png, "
          "logo.ico, logo.icns, pwa_icon_144/180/512.png")


if __name__ == "__main__":
    main()
