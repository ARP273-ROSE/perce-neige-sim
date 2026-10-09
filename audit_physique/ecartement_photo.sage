# Écartement de la voie du Perce-Neige mesuré sur photo (09/10/2026).
# Kevin : « essaie de mesurer sur une photo l'écart des rails ; 1435 c'est la
# voie standard, OSM l'a peut-être mis génériquement ».
# Photo : Wikimedia Commons « 2017-01 Funiculaire Du Perce-Neige Tignes 01.jpg »
# (1920 × 1280), rame à quai vue de face, voie visible sous le nez.
# Étalon : les deux tampons ronds bleus du nez, centres à ±1,02 m de l'axe
# (TrainBodyBuilder._build_cap_fittings, calé sur la photo 094104).
# Relevés en pixels de l'image d'origine (x), sur l'agrandissement rails.jpg :
# x_origine = 450 + x_affiché × 1,1 / 2.
def px(x_aff): return 450 + x_aff * 11/10 / 2
tampon_g, tampon_d = px(475), px(1395)
m_par_px = 2*1.02 / (tampon_d - tampon_g)
# files de rails (axe du champignon), là où elles sortent de sous le nez
# (même profondeur que la face) et en bas de l'image (plus près de l'objectif)
rail_haut = (px(745), px(1255))
rail_bas = (px(700), px(1330))
e_haut = (rail_haut[1] - rail_haut[0]) * m_par_px
e_bas = (rail_bas[1] - rail_bas[0]) * m_par_px
print("étalon : %.1f px pour 2,04 m → %.2f mm/px" % (tampon_d - tampon_g, 1000*m_par_px))
print("écartement à la profondeur du nez : %.3f m" % e_haut)
print("écartement en bas de l'image (plus près, donc surestimé) : %.3f m" % e_bas)
print("1,435 m donnerait %.0f px au niveau du nez, mesuré %.0f px" % (1.435/m_par_px, rail_haut[1]-rail_haut[0]))
print("1,200 m donnerait %.0f px au niveau du nez" % (1.200/m_par_px))
