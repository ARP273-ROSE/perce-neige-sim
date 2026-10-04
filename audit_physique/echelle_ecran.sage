# Facteur d'agrandissement de l'interface selon l'écran détecté
# (perce_neige_sim._decrire_ecran, v1.15.55). Vérification exacte.
#   distance de lecture d(cm) = 20 + 2,2·diag + 2,5·max(0, diag − 32)
#   cible : 1 px de maquette = 0,004·d mm  (≈ 1,4′ d'angle)
#   facteur = clamp(cible / (mm par px logique), 1, 2,5)
def facteur(lw, lh, mm_w, mm_h, dpr):
    diag = sqrt(mm_w^2 + mm_h^2) / 25.4
    mm_px = mm_w / lw
    dpi = 25.4 * dpr / mm_px
    d = 20 + 2.2*diag + 2.5*max(0, diag - 32)
    f = (0.004*d) / mm_px
    return diag, dpi, d, f, min(max(f, 1), 2.5)

ecrans = [
    ("24\" 1080p à 100 % (référence)", 1920, 1080, 531, 299, 1),
    ("27\" 1440p à 100 %",             2560, 1440, 597, 336, 1),
    ("27\" 4K à 150 %",                2560, 1440, 597, 336, 1.5),
    ("32\" 4K à 150 %",                2560, 1440, 708, 399, 1.5),
    ("34\" 21:9 3440×1440 à 100 %",    3440, 1440, 800, 335, 1),
    ("14\" 1080p à 125 % (portable)",  1536,  864, 310, 174, 1.25),
    ("15,6\" 1080p à 100 %",           1920, 1080, 344, 194, 1),
    ("13,3\" Mac 2560×1600 (1440×900)",1440,  900, 286, 179, 2),
    ("55\" 4K à 100 % (téléviseur)",   3840, 2160, 1210, 680, 1),
]
print("%-34s %6s %6s %7s %7s %7s" % ("écran", "diag", "ppp", "d (cm)", "brut", "retenu"))
for nom, lw, lh, mw, mh, dpr in ecrans:
    diag, dpi, d, f, r = facteur(lw, lh, mw, mh, dpr)
    print("%-34s %6.1f %6.0f %7.1f %7.3f %7.3f" % (nom, diag.n(), dpi.n(), d.n(), f.n(), r.n()))
# angle d'un px de maquette sur la référence (arcmin)
mm_px = 531/1920
print("angle réf. : %.3f′" % (atan((0.004*(20+2.2*sqrt(531^2+299^2)/25.4))/(10*(20+2.2*sqrt(531^2+299^2)/25.4)))*180/pi*60).n())
