class_name EcranProface
extends Control
## Écran tactile du pupitre de conduite (terminal Pro-face), reproduit
## d'après la photo d'un utilisateur 20260426_094305 (page « VOITURE AVAL ») et la
## vidéo de descente de 2013 (page « CONDUITE VÉHICULE 1 ») — demande du
## 06/10/2026 : « reproduire fidèlement le poste de commande, les bons
## boutons, les bons noms, et l'écran LCD qui marche et affiche les bonnes
## infos en direct ».
##
## Mise en page (480 × 284 px, comme la dalle) :
##   - bandeau du haut : date et heure, voyants ARRÊT FREIN DE SERVICE,
##     ARRÊT ÉLEC., Alarmes, trois voyants verts (libellés illisibles sur
##     les photos : laissés sans texte), cartouche blanc ;
##   - titre de page et corps ;
##   - bandeau du bas : VITESSE VÉHICULE (m/s, au centième), DISTANCE (m),
##     bouton DÉFAUTS (rouge s'il y a un défaut), flèche de navigation.
## Pages : « CONDUITE VÉHICULE n » en marche, « VOITURE AVAL » (les six
## portes de la voiture) à l'arrêt en gare.
## Rien n'est inventé : les petits textes illisibles des photos (centre de
## la page VOITURE AVAL, bouton sous la liste des états) sont dessinés sans
## libellé.

const L: float = 480.0
const H: float = 284.0
const C_FOND: Color = Color(0.86, 0.90, 0.94)
const C_BLEU: Color = Color(0.20, 0.62, 0.92)
const C_BLEU_F: Color = Color(0.36, 0.50, 0.70)
const C_GRIS: Color = Color(0.62, 0.66, 0.72)
const C_TEXTE: Color = Color(0.95, 0.96, 0.98)
const C_SOMBRE: Color = Color(0.12, 0.12, 0.14)
const C_JAUNE: Color = Color(0.98, 0.84, 0.20)
const C_VERT: Color = Color(0.35, 0.92, 0.40)
const C_ETEINT: Color = Color(0.32, 0.20, 0.22)

# état affiché (rempli par PupitreConduite)
var vitesse: float = 0.0
var distance: float = 0.0
var vehicule: int = 1
var page_portes: bool = false
var portes_ouvertes: bool = false
var arret_frein_service: bool = false
var arret_elec: bool = false
var alarme: bool = false
var pret_motrice: bool = true
var pret_autre: bool = true
var marche: bool = false
var autorisation_portes: bool = false
var frein_voie_leve: bool = true
var ralentisseur_leve: bool = true
var portes_secours_fermees: bool = true
var vitesse_reduite: bool = false
var pupitre_avant: bool = true
## Couches (performance PWA, 07/10/2026) : le FOND (cadres, libellés,
## voyants) n'est redessiné que lorsqu'il change — un voyant, la page — et
## les VALEURS (date et heure, vitesse, distance) jusqu'à 30 fois par
## seconde par-dessus : ~170 appels de dessin à chaque rafraîchissement
## devenaient une dizaine.
enum Couche { TOUT, FOND, VALEURS }
var couche: Couche = Couche.TOUT

var _police: Font = null
## Textes en VECTORIEL (09/10/2026) : au lieu d'être dessinés dans l'image de
## l'écran, ils sont relevés ([position, texte, taille, couleur, largeur,
## alignement]) et le pupitre les pose en Label3D (police MSDF) sur la dalle —
## nets à toutes les distances et dans la loupe. Les formes restent dans
## l'image.
var textes_3d: bool = false
var textes: Array = []
signal textes_prets


func _ready() -> void:
	size = Vector2(L, H)
	_police = ThemeDB.fallback_font


func _texte(pos: Vector2, t: String, taille: int, c: Color, larg: float = -1.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if textes_3d:
		textes.append([pos, t, taille, c, larg, align])
		return
	draw_string(_police, pos, t, align, larg, taille, c)


func _voyant(c: Vector2, r: float, allume: bool, couleur: Color) -> void:
	draw_circle(c, r + 1.0, C_SOMBRE)
	draw_circle(c, r, couleur if allume else C_ETEINT)
	if allume:
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, couleur.lightened(0.5))


## Signature de ce que montre le fond : il est redessiné quand elle change.
func signature_fond() -> String:
	return "%d%d%d%d%d%d%d%d%d%d%d%d%d%d|%d" % [int(page_portes),
		int(portes_ouvertes), int(arret_frein_service), int(arret_elec), int(alarme),
		int(pret_motrice), int(pret_autre), int(marche), int(autorisation_portes),
		int(frein_voie_leve), int(ralentisseur_leve), int(portes_secours_fermees),
		int(vitesse_reduite), int(pupitre_avant), vehicule]


## Signature des valeurs : date et heure à la seconde, vitesse, distance.
func signature_valeurs() -> String:
	var dt: Dictionary = PNConstants.heure_locale()
	return "%02d%02d%04d%02d%02d%02d|%.2f|%d" % [dt.day, dt.month, dt.year, dt.hour,
		dt.minute, dt.second, vitesse, int(round(distance))]


func _draw() -> void:
	textes.clear()
	_dessiner()
	if textes_3d:
		textes_prets.emit()


func _dessiner() -> void:
	if couche == Couche.VALEURS:
		_valeurs()
		return
	draw_rect(Rect2(0, 0, L, H), C_BLEU)
	draw_rect(Rect2(4, 4, L - 8, H - 8), C_FOND)
	_bandeau_haut()
	if page_portes:
		_page_voiture()
	else:
		_page_conduite()
	_bandeau_bas()


func _bandeau_haut() -> void:
	draw_rect(Rect2(4, 4, L - 8, 36), C_BLEU)
	# date et heure (fond sombre, chiffres jaunes)
	# heure LOCALE de l'appareil, à la seconde (PNConstants.heure_locale)
	draw_rect(Rect2(8, 7, 70, 30), Color(0.30, 0.30, 0.30))
	# voyants d'état
	var cases: Array = [["ARRÊT\nFREIN DE\nSERVICE", arret_frein_service, Color(0.95, 0.15, 0.15)],
		["ARRÊT\nÉLEC.", arret_elec, Color(0.95, 0.15, 0.15)],
		["Alarmes", alarme, Color(1.0, 0.55, 0.10)]]
	var x: float = 132.0
	for c in cases:
		draw_rect(Rect2(x, 7, 66, 30), C_BLEU_F)
		_voyant(Vector2(x + 10, 22), 6.0, c[1], c[2])
		var lignes: PackedStringArray = (c[0] as String).split("\n")
		for k in range(lignes.size()):
			_texte(Vector2(x + 19, 16 + 9 * k - 4 * (lignes.size() - 3) - 4 * int(lignes.size() == 1)),
				lignes[k], 8, C_TEXTE)
		x += 70.0
	# trois voyants verts (libellés illisibles sur les photos)
	draw_rect(Rect2(x, 7, 60, 30), C_BLEU_F)
	for k in range(3):
		_voyant(Vector2(x + 8, 12 + 9 * k), 3.2, true, C_VERT)
		draw_rect(Rect2(x + 15, 10 + 9 * k, 38, 4), Color(0.80, 0.86, 0.94, 0.5))
	# cartouche blanc (logo)
	draw_rect(Rect2(L - 62, 8, 54, 28), Color(0.96, 0.97, 0.98))


func _titre(t: String) -> void:
	draw_rect(Rect2(14, 44, L - 28, 16), C_GRIS)
	_texte(Vector2(14, 57), t, 12, C_TEXTE, L - 28, HORIZONTAL_ALIGNMENT_CENTER)


func _page_conduite() -> void:
	_titre("CONDUITE VÉHICULE %d" % vehicule)
	# états de gauche
	draw_rect(Rect2(70, 66, 150, 104), C_BLEU_F)
	var gauche: Array = [["PRÊT MOTRICE", pret_motrice], ["PRÊT VÉHICULE %d" % (3 - vehicule), pret_autre],
		["TEST EN COURS", false], ["MARCHE", marche], ["AUTORISATION\nOUVERTURE PORTES", autorisation_portes]]
	var y: float = 76.0
	for e in gauche:
		_voyant(Vector2(80, y), 5.0, e[1], C_VERT)
		var lignes: PackedStringArray = (e[0] as String).split("\n")
		for k in range(lignes.size()):
			_texte(Vector2(90, y + 4 + 9 * k), lignes[k], 9, C_TEXTE)
		y += 18.0 if lignes.size() == 1 else 26.0
	# pupitre avant
	draw_rect(Rect2(70, 176, 150, 34), C_BLEU_F)
	_texte(Vector2(78, 192), "PUPITRE AVANT", 9, C_TEXTE)
	_voyant(Vector2(200, 199), 5.0, pupitre_avant, C_VERT)
	# états de droite
	draw_rect(Rect2(258, 66, 168, 112), C_BLEU_F)
	var droite: Array = [["FREIN DE VOIE LEVÉ", frein_voie_leve, C_VERT],
		["RALENTISSEUR LEVÉ", ralentisseur_leve, C_VERT],
		["PORTES FERMÉES", not portes_ouvertes, C_VERT],
		["PORTES SECOURS FERMÉES", portes_secours_fermees, C_VERT]]
	y = 78.0
	for e in droite:
		_voyant(Vector2(268, y), 5.0, e[1], e[2])
		_texte(Vector2(278, y + 4), e[0], 9, C_TEXTE)
		y += 20.0
	_voyant(Vector2(268, y + 8), 5.0, vitesse_reduite, Color(0.95, 0.15, 0.15))
	_texte(Vector2(278, y + 12), "VITESSE RÉDUITE", 9, C_TEXTE)
	# bouton sans libellé lisible
	draw_rect(Rect2(300, 190, 86, 16), Color(0.92, 0.94, 0.97))
	draw_rect(Rect2(300, 190, 86, 16), C_GRIS, false, 1.0)


func _page_voiture() -> void:
	_titre("VOITURE AVAL")
	# caisse (accolades jaunes) et six portes, trois de chaque côté
	draw_arc(Vector2(40, 140), 70.0, PI * 0.62, PI * 1.38, 16, Color(0.95, 0.75, 0.25), 3.0)
	draw_arc(Vector2(L - 40, 140), 70.0, -PI * 0.38, PI * 0.38, 16, Color(0.95, 0.75, 0.25), 3.0)
	for rangee in [0, 1]:
		for k in range(3):
			var cx: float = 110.0 + 130.0 * k
			var cy: float = 92.0 if rangee == 0 else 192.0
			var bar_y: float = cy - 24.0 if rangee == 0 else cy + 18.0
			draw_rect(Rect2(cx - 28, bar_y, 56, 7),
				Color(0.95, 0.30, 0.20) if portes_ouvertes else C_VERT)
			draw_rect(Rect2(cx - 14, cy - 14, 28, 28), Color(0.97, 0.97, 0.98))
			draw_rect(Rect2(cx - 14, cy - 14, 28, 28), C_GRIS, false, 1.0)
			draw_circle(Vector2(cx, cy), 9.0, C_SOMBRE)
			draw_circle(Vector2(cx, cy), 6.5, Color(0.97, 0.97, 0.98))
			draw_line(Vector2(cx - 7, cy - 7), Vector2(cx + 7, cy + 7), C_SOMBRE, 3.0)
	# deux cartouches centraux (petits textes illisibles sur la photo)
	for k in range(2):
		var cx2: float = 175.0 + 130.0 * k
		draw_rect(Rect2(cx2 - 52, 122, 104, 44), Color(0.80, 0.84, 0.90))
		draw_rect(Rect2(cx2 - 52, 122, 104, 9), C_GRIS)
		draw_rect(Rect2(cx2 - 11, 134, 22, 22), Color(0.97, 0.97, 0.98))
		draw_circle(Vector2(cx2, 145), 7.0, C_SOMBRE)
	# passage à l'autre voiture
	draw_rect(Rect2(L - 74, 128, 28, 24), Color(0.40, 0.52, 0.66))
	draw_colored_polygon(PackedVector2Array([Vector2(L - 68, 134), Vector2(L - 56, 134),
		Vector2(L - 56, 130), Vector2(L - 49, 140), Vector2(L - 56, 150), Vector2(L - 56, 146),
		Vector2(L - 68, 146)]), Color(0.95, 0.96, 0.98))


func _bandeau_bas() -> void:
	var y0: float = H - 36.0
	draw_rect(Rect2(4, y0, L - 8, 32), C_BLEU)
	draw_rect(Rect2(8, y0 + 3, 60, 26), C_BLEU_F)
	_texte(Vector2(8, y0 + 14), "VITESSE", 9, C_TEXTE, 60, HORIZONTAL_ALIGNMENT_CENTER)
	_texte(Vector2(8, y0 + 25), "VÉHICULE", 9, C_TEXTE, 60, HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(72, y0 + 3, 96, 26), C_SOMBRE)
	_texte(Vector2(140, y0 + 23), "m/s", 9, C_JAUNE)
	draw_rect(Rect2(174, y0 + 3, 66, 26), C_BLEU_F)
	_texte(Vector2(174, y0 + 21), "DISTANCE", 9, C_TEXTE, 66, HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(244, y0 + 3, 96, 26), C_SOMBRE)
	_texte(Vector2(322, y0 + 23), "m", 9, C_JAUNE)
	if couche == Couche.TOUT:
		_valeurs()
	draw_rect(Rect2(346, y0 + 3, 90, 26), Color(0.95, 0.30, 0.25) if alarme else Color(0.92, 0.94, 0.97))
	_texte(Vector2(346, y0 + 20), "DÉFAUTS", 9, C_TEXTE if alarme else C_GRIS, 90,
		HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(440, y0 + 3, 32, 26), Color(0.40, 0.52, 0.66))
	draw_rect(Rect2(448, y0 + 9, 16, 14), Color(0.95, 0.96, 0.98), false, 2.0)


## Date et heure (heure LOCALE de l'appareil, à la seconde :
## PNConstants.heure_locale), vitesse (m/s, au centième) et distance (m).
func _valeurs() -> void:
	var dt: Dictionary = PNConstants.heure_locale()
	_texte(Vector2(10, 19), "%02d/%02d/%04d" % [dt.day, dt.month, dt.year], 10, C_JAUNE, 66,
		HORIZONTAL_ALIGNMENT_CENTER)
	_texte(Vector2(10, 33), "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second], 11, C_JAUNE, 66,
		HORIZONTAL_ALIGNMENT_CENTER)
	var y0: float = H - 36.0
	_texte(Vector2(74, y0 + 23), "%.2f" % vitesse, 17, C_JAUNE, 62, HORIZONTAL_ALIGNMENT_RIGHT)
	_texte(Vector2(246, y0 + 23), "%d" % int(round(distance)), 17, C_JAUNE, 72, HORIZONTAL_ALIGNMENT_RIGHT)
