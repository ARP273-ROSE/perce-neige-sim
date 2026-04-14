"""Generate logo.png / logo.ico / logo_64.png for Perce-Neige Simulator."""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

HERE = Path(__file__).parent

SIZE = 1024  # draw at 2x target (512), downscale LANCZOS for anti-aliasing


def draw_logo() -> Image.Image:
    W = H = SIZE
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded-square dark background (cosmic deep blue)
    bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(bg)
    r = int(W * 0.14)
    db.rounded_rectangle((20, 20, W - 20, H - 20), radius=r,
                         fill=(12, 22, 42, 255))
    # Subtle cosmic gradient
    for y in range(20, H - 20):
        k = (y - 20) / (H - 40)
        col = (
            int(12 + 16 * k),
            int(22 + 24 * k),
            int(42 + 30 * k),
            255,
        )
        db.line((22, y, W - 22, y), fill=col)
    db.rounded_rectangle((20, 20, W - 20, H - 20), radius=r, outline=(80, 130, 200, 255), width=6)
    img.alpha_composite(bg)

    # Mountain silhouette (dark grey) — simple triangle range
    mountain = [
        (80, 760),
        (300, 420),
        (470, 560),
        (620, 320),
        (780, 520),
        (940, 620),
        (940, 940),
        (80, 940),
    ]
    d.polygon(mountain, fill=(60, 66, 80, 255))
    # Snow caps — lighter triangles above key peaks
    d.polygon([(300, 420), (250, 520), (370, 520)], fill=(232, 240, 252, 255))
    d.polygon([(620, 320), (555, 440), (700, 440)], fill=(232, 240, 252, 255))

    # Tunnel line diagonal across the mountain
    tunnel_start = (140, 820)
    tunnel_end = (880, 320)
    d.line([tunnel_start, tunnel_end], fill=(20, 20, 30, 255), width=34)
    d.line([tunnel_start, tunnel_end], fill=(50, 55, 70, 255), width=24)

    # Drive station at top of tunnel (box)
    ds_x, ds_y = tunnel_end
    d.rectangle((ds_x - 70, ds_y - 90, ds_x + 70, ds_y + 20),
                fill=(140, 150, 170, 255), outline=(30, 30, 40, 255), width=4)
    # Drive pulley (circle with spokes)
    pr = 46
    cx, cy = ds_x, ds_y - 35
    d.ellipse((cx - pr, cy - pr, cx + pr, cy + pr),
              fill=(180, 180, 190, 255), outline=(30, 30, 40, 255), width=4)
    d.ellipse((cx - pr * 0.4, cy - pr * 0.4, cx + pr * 0.4, cy + pr * 0.4),
              fill=(220, 220, 230, 255), outline=(30, 30, 40, 255), width=3)
    for k in range(6):
        import math
        ang = k * math.pi / 3
        d.line(
            (cx + math.cos(ang) * 8, cy + math.sin(ang) * 8,
             cx + math.cos(ang) * (pr - 6), cy + math.sin(ang) * (pr - 6)),
            fill=(40, 40, 50, 255), width=5,
        )

    # Yellow cylindrical cabin on the slope (midway)
    import math
    t_dx = tunnel_end[0] - tunnel_start[0]
    t_dy = tunnel_end[1] - tunnel_start[1]
    t_len = math.hypot(t_dx, t_dy)
    ux, uy = t_dx / t_len, t_dy / t_len
    nx, ny = -uy, ux

    # Cabin center at 55% along tunnel
    cx = tunnel_start[0] + ux * t_len * 0.55
    cy = tunnel_start[1] + uy * t_len * 0.55

    cab_len = 220
    cab_half = cab_len / 2
    cab_thick = 48

    p0 = (cx - ux * cab_half, cy - uy * cab_half)
    p1 = (cx + ux * cab_half, cy + uy * cab_half)

    # Cabin body polygon
    cabin_poly = [
        (p0[0] + nx * cab_thick, p0[1] + ny * cab_thick),
        (p1[0] + nx * cab_thick, p1[1] + ny * cab_thick),
        (p1[0] - nx * cab_thick, p1[1] - ny * cab_thick),
        (p0[0] - nx * cab_thick, p0[1] - ny * cab_thick),
    ]
    d.polygon(cabin_poly, fill=(255, 210, 60, 255),
              outline=(120, 80, 0, 255))

    # Highlight along the top
    hl0 = (p0[0] + nx * (cab_thick * 0.55), p0[1] + ny * (cab_thick * 0.55))
    hl1 = (p1[0] + nx * (cab_thick * 0.55), p1[1] + ny * (cab_thick * 0.55))
    d.line([hl0, hl1], fill=(255, 255, 220, 220), width=6)

    # End caps (domes) — draw ellipses
    cap_r = cab_thick
    for pt in (p0, p1):
        d.ellipse((pt[0] - cap_r * 0.55, pt[1] - cap_r,
                   pt[0] + cap_r * 0.55, pt[1] + cap_r),
                  fill=(255, 200, 50, 255), outline=(100, 60, 0, 255), width=3)

    # Windows — 5 small rectangles along axis
    n_win = 5
    win_w = cab_len / (n_win + 1) * 0.55
    win_h = cab_thick * 0.7
    for i in range(n_win):
        f = (i + 1) / (n_win + 1)
        wx = tunnel_start[0] + ux * t_len * (0.55 - 0.5) + ux * cab_len * (f - 0.5)
        wy = tunnel_start[1] + uy * t_len * (0.55 - 0.5) + uy * cab_len * (f - 0.5)
        wx = cx + ux * cab_len * (f - 0.5)
        wy = cy + uy * cab_len * (f - 0.5)
        win_poly = [
            (wx + ux * (-win_w / 2) + nx * (-win_h / 2),
             wy + uy * (-win_w / 2) + ny * (-win_h / 2)),
            (wx + ux * (+win_w / 2) + nx * (-win_h / 2),
             wy + uy * (+win_w / 2) + ny * (-win_h / 2)),
            (wx + ux * (+win_w / 2) + nx * (+win_h / 2),
             wy + uy * (+win_w / 2) + ny * (+win_h / 2)),
            (wx + ux * (-win_w / 2) + nx * (+win_h / 2),
             wy + uy * (-win_w / 2) + ny * (+win_h / 2)),
        ]
        d.polygon(win_poly, fill=(120, 200, 240, 255),
                  outline=(20, 20, 30, 255))

    # Title text at bottom
    try:
        from PIL import ImageFont
        try:
            font = ImageFont.truetype("arialbd.ttf", 78)
        except OSError:
            font = ImageFont.load_default()
    except Exception:
        font = None
    if font is not None:
        text = "PERCE-NEIGE"
        tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, 60), text,
               fill=(255, 220, 80, 255), font=font,
               stroke_width=3, stroke_fill=(40, 30, 0, 255))

    return img


def main() -> None:
    big = draw_logo()
    # 512 PNG
    png512 = big.resize((512, 512), Image.Resampling.LANCZOS)
    png512.save(HERE / "logo.png")
    # 64 PNG for status bar
    big.resize((64, 64), Image.Resampling.LANCZOS).save(HERE / "logo_64.png")
    # ICO with multiple sizes
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    big.save(HERE / "logo.ico", format="ICO", sizes=sizes)
    print("wrote logo.png, logo_64.png, logo.ico")


if __name__ == "__main__":
    main()
