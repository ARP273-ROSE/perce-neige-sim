class_name PupitreConduite
extends Node3D
## Pupitre de conduite de la cabine, reproduit d'après les photos de Kevin
## du 26/04/2026 (094300, 094305, 094308, 094402) et la vidéo de descente de
## 2013 — demande du 06/10/2026 : « reproduire fidèlement le poste de
## commande avec les bons boutons, les bons noms et l'écran LCD qui marche
## et affiche les bonnes infos en direct ».
##
## Un caisson gris sur le tube transversal, avec :
##   - à gauche, sur un cadre noir : l'écran tactile Pro-face (EcranProface,
##     rendu en direct dans une texture, 30 fois par seconde) ;
##   - à droite, la plaque à boutons, disposée comme sur la photo :
##       PORTES 1 à 6 (côté gauche en regardant vers le haut) et PORTES
##       7 à 12 (côté droit) : OUVERTURE (blanc), FERMETURE (vert)
##       PRÊT (voyant vert) · MONTÉE · −VITE/+VITE · EN MARCHE (clé)
##       KLAXON        · ÉCLAIRAGE : CABINE (0/1), COMPARTIMENT, SECOURS
##     Deuxième rangée d'après Kevin (06/10/2026) : PRÊT n'est qu'un
##     voyant ; il s'allume quand on appuie sur MONTÉE (« ça veut dire qu'on
##     est prêt ») ; le sélecteur −VITE/+VITE revient seul à la verticale
##     et, tenu à gauche ou à droite, baisse ou monte la consigne de
##     vitesse ; le commutateur à clé EN MARCHE est le commutateur général
##     (sur arrêt : pupitre éteint, départ refusé).
## Les voyants suivent l'état réel de la rame : FERMETURE vert portes
## fermées, OUVERTURE blanc portes ouvertes, PRÊT vert rame prête,
## COMPARTIMENT blanc éclairage de la cabine, SECOURS toujours allumé,
## sélecteur CABINE sur 0 ou 1, KLAXON enfoncé quand on klaxonne.
## Repère : celui de l'intérieur de la cabine (avant = −Z).
##
## La face est redressée vers le conducteur (Kevin, 06/10/2026 : « incliner
## ce panneau pour être perpendiculaire à la ligne du regard, même si ce
## n'est pas exact, pour que je puisse bien voir ») — sur la rame elle est
## presque à plat. Perpendiculaire au regard (≈ 62°), elle paraissait
## « trop étirée en hauteur » et masquait la voie (07/10/2026) : elle est
## couchée à INCLINAISON_MAX, plus bas, et reste lisible (≈ 35° du regard).
## Les commandes s'actionnent au clic ou au doigt en vue cabine (« et
## faudrait pouvoir appuyer sur ces boutons ») : commande_sous() trouve la
## commande visée, appuyer() l'enfonce ; main.gd fait l'action.

const R_TUBE: float = 0.13
const LONG_TUBE: float = 1.10
const LEVEE: float = 0.005             # face posée devant le tube…
const AVANCEE: float = 0.05            # … et avancée vers le conducteur : la voie reste dégagée
const INCLINAISON_MAX: float = 0.49    # ≈ 28° : proportions et vue sur la voie
const R_COMMANDE: float = 0.028        # rayon de la zone d'appui (doigt)
const X_ECRAN: float = -0.10           # centre du cadre de l'écran
const X_PLAQUE: float = 0.21           # centre de la plaque à boutons
const X_GAUCHE: float = -0.35          # centre de la plaque de gauche (coups-de-poing rouges)
const PIXEL_ETIQUETTE: float = 0.00048  # plus gros qu'en vrai : lisible depuis le siège
## Textes du pupitre en haute définition (09/10/2026, Kevin : « ton panneau de
## conduite est pixélisé et pas net, un truc vectoriel et plus précis ? ») :
## une étiquette Label3D est une TEXTURE rendue à `font_size` pixels — 12 à
## 20 px, étirés sur 6 à 10 mm, puis filtrés en biais : flou garanti, sur
## n'importe quelle carte. On rend 6 fois plus fin (pixel_size 6 fois plus
## petit : même taille sur le pupitre), filtrage anisotrope ; l'écran
## Pro-face est rendu en 4× (2× sur le web). Coût nul en pratique.
const SURECHANTILLON: int = 1      # inutile depuis la police vectorielle (PolicesJeu, MSDF)
const NOMS_OUVERTURE: Array = ["ouverture_0", "ouverture_1"]   # (pas de "%d" % g chaque image)
const NOMS_FERMETURE: Array = ["fermeture_0", "fermeture_1"]
const NOMS_ROUGE: Array = ["rouge_1", "rouge_2"]
const L_GAUCHE: float = 0.20
const L_CADRE: float = 0.30
const L_PLAQUE: float = 0.31
const P_FACE: float = 0.22             # profondeur de la face
# dalle agrandie (Kevin, 07/10/2026 : « qu'il prenne quasi tout l'espace
# noir ») : 0,272 × 0,161 m, au rapport 480 × 284 de l'écran Pro-face
const ECRAN_L: float = 0.272
const ECRAN_H: float = 0.161
const Z_ECRAN: float = -0.012
const PERIODE_ECRAN: float = 1.0 / 30.0   # rafraîchi 30 fois par seconde (fluidité des chiffres)

var _face: Node3D = null
var _sv: SubViewport = null            # écran composé : fond + valeurs
var _mi_ecran: MeshInstance3D = null
var _textes_3d: Dictionary = {}         # EcranProface → [Label3D…]
var _sv_fond: SubViewport = null       # fond, redessiné quand il change
var ecran: EcranProface = null         # le fond (porte l'état affiché)
var _valeurs: EcranProface = null      # heure, vitesse, distance : 30 fois par seconde au plus
var _sig_fond: String = ""
var _sig_valeurs: String = ""
var _t_ecran: float = 0.0
var _voyants: Dictionary = {}          # nom → [matériau, couleur allumée]
var _cabine_bouton: Node3D = null
var _klaxon: Node3D = null
## Inclinaison de la face (rad) : vers l'œil du conducteur.
var inclinaison: float = 0.07
## Commandes actionnables : nom → [position sur la face, nœud qui bouge, y repos]
var _commandes: Dictionary = {}
var _enfoncee: String = ""
var _page_forcee: int = -1            # −1 auto, 0 CONDUITE, 1 VOITURE AVAL
## Commutateur général (clé EN MARCHE).
var en_marche: bool = true
var _mat_ecran: StandardMaterial3D = null
var _en_gare_prec: bool = false


## `oeil` : position de la caméra cabine dans le même repère.
func construire(z_console: float, y_top: float, lumieres: Array,
		oeil: Vector3 = Vector3(0.0, 0.85, INF)) -> void:
	var y_face: float = y_top + LEVEE
	var z_face: float = z_console + AVANCEE
	if oeil.z == INF:
		oeil.z = z_console + 0.65
	# normale de la face (0, cos a, sin a) tournée vers l'œil, sans dépasser
	# INCLINAISON_MAX
	inclinaison = minf(atan2(oeil.z - z_face, oeil.y - y_face), INCLINAISON_MAX)
	var gris: StandardMaterial3D = _mat(Color(0.70, 0.71, 0.72), 0.6, 0.1)
	var plaque_mat: StandardMaterial3D = _mat(Color(0.62, 0.62, 0.59), 0.75, 0.0)   # gris clair mat (photo)
	var noir: StandardMaterial3D = _mat(Color(0.07, 0.07, 0.08), 0.5, 0.2)
	var chrome: StandardMaterial3D = _mat(Color(0.70, 0.71, 0.73), 0.35, 0.75)
	var filet: StandardMaterial3D = _mat(Color(0.20, 0.20, 0.22), 0.7, 0.0)
	# tube transversal
	var tube: MeshInstance3D = _cylindre(gris, R_TUBE, LONG_TUBE, 28)
	tube.name = "PupitreTube"
	tube.position = Vector3(0.0, y_top - R_TUBE - 0.015, z_console)
	tube.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(tube)
	for xb in [-LONG_TUBE * 0.38, LONG_TUBE * 0.38]:
		_boite(_mat(Color(0.25, 0.25, 0.28), 0.45, 0.7), Vector3(0.024, y_top + 0.9, 0.024),
			Vector3(xb, (y_top - R_TUBE - 0.95) * 0.5, z_console + 0.04), self)
	# face inclinée : caisson sous la face, cadre noir, plaque à boutons
	_face = Node3D.new()
	_face.name = "FacePupitre"
	_face.position = Vector3(0.0, y_face, z_face)
	_face.rotation = Vector3(inclinaison, 0.0, 0.0)
	add_child(_face)
	var x0: float = X_GAUCHE - L_GAUCHE * 0.5
	var x1: float = X_PLAQUE + L_PLAQUE * 0.5
	# caisson juste assez haut pour rejoindre le tube sous les bords de la face
	_boite(gris, Vector3(x1 - x0 + 0.01, 0.055, P_FACE + 0.006),
		Vector3((x0 + x1) * 0.5, -0.0305, 0.0), _face)
	# pied : comble, vu du siège, l'espace entre le tube et la face redressée
	# (entièrement DERRIÈRE la face : son arête avant passe sous le bas de
	# la face)
	var y_pied: float = y_face - P_FACE * 0.5 * sin(inclinaison) - 0.006
	var y_tube: float = y_top - R_TUBE - 0.015
	var z_av: float = z_face + P_FACE * 0.5 * cos(inclinaison) - 0.008
	_boite(gris, Vector3(x1 - x0 - 0.02, y_pied - y_tube, 0.10),
		Vector3((x0 + x1) * 0.5, (y_pied + y_tube) * 0.5, z_av - 0.05), self)
	_boite(noir, Vector3(L_CADRE, 0.006, P_FACE), Vector3(X_ECRAN, 0.0, 0.0), _face)
	_boite(plaque_mat, Vector3(L_PLAQUE, 0.006, P_FACE), Vector3(X_PLAQUE, 0.0, 0.0), _face)
	_boite(plaque_mat, Vector3(L_GAUCHE, 0.006, P_FACE), Vector3(X_GAUCHE, 0.0, 0.0), _face)
	_construire_ecran()
	_etiquette("Pro-face", Vector2(X_ECRAN, 0.088), 20, Color(0.55, 0.56, 0.60))
	_construire_boutons(chrome, noir, filet)
	_construire_gauche(chrome, noir, filet)
	# éclairage doux de la face (fait partie de l'éclairage cabine)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0.0, y_face + 0.05, z_face + 0.18)
	fill.light_color = Color(0.92, 0.96, 1.0)
	fill.light_energy = 0.22
	fill.omni_range = 0.55
	fill.shadow_enabled = false
	fill.light_cull_mask = Cabin.LAYER_RAME
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	lumieres.append(fill)
	_fusionner()


## Performance (PWA, 07/10/2026 : « sur l'iPad le son a des micro-coupures
## tout le temps maintenant ») : sur la PWA le son est mixé sur le fil
## principal, entre deux images ; une image trop longue fait un trou. Le
## pupitre coûtait 88 appels de dessin par image (66 pièces + 22 libellés) :
## les pièces fixes sont fusionnées par matériau ; seules les commandes (qui
## s'enfoncent, tournent ou s'allument) et l'écran restent à part.
func _fusionner() -> void:
	var garder: Array = []
	for nom in _commandes:
		garder.append(_commandes[nom][1])
	for mi in _face.get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).name == "EcranProface":
			garder.append(mi)
	MeshMerge.merge(self, garder, "PupitreFixe")


func _construire_ecran() -> void:
	# rendu à deux fois la résolution de l'écran : net une fois agrandi.
	# Deux couches (cf. EcranProface.Couche) : le fond n'est redessiné que
	# lorsqu'il change, l'écran composé (fond + valeurs) quand une valeur
	# change, 30 fois par seconde au plus.
	_sv_fond = _nouvel_ecran()
	ecran = EcranProface.new()
	ecran.couche = EcranProface.Couche.FOND
	_sv_fond.add_child(ecran)
	_sv = _nouvel_ecran()
	var fond: TextureRect = TextureRect.new()
	fond.texture = _sv_fond.get_texture()
	fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fond.stretch_mode = TextureRect.STRETCH_SCALE
	fond.size = Vector2(EcranProface.L, EcranProface.H)
	_sv.add_child(fond)
	_valeurs = EcranProface.new()
	_valeurs.couche = EcranProface.Couche.VALEURS
	_sv.add_child(_valeurs)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _sv.get_texture()
	_mat_ecran = m
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(ECRAN_L, ECRAN_H)
	q.material = m
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "EcranProface"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# couché sur la face, haut de l'écran vers le pare-brise
	mi.position = Vector3(X_ECRAN, 0.0035, Z_ECRAN)
	mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_face.add_child(mi)
	# textes de l'écran en vectoriel, posés sur la dalle (cf. EcranProface)
	_mi_ecran = mi
	for e2 in [ecran, _valeurs]:
		(e2 as EcranProface).textes_3d = true
		(e2 as EcranProface).textes_prets.connect(_poser_textes.bind(e2))


func _construire_boutons(chrome: StandardMaterial3D, noir: StandardMaterial3D,
		filet: StandardMaterial3D) -> void:
	# grille : 4 colonnes, 3 rangées (z vers le conducteur)
	var cols: Array = [X_PLAQUE - 0.105, X_PLAQUE - 0.040, X_PLAQUE + 0.035, X_PLAQUE + 0.100]
	# (07/10/2026 : titres PORTES et ÉCLAIRAGE redescendus dans la plaque —
	# « ils sont dehors »)
	var rangs: Array = [-0.059, -0.003, 0.066]
	var lab_z: float = -0.0295            # libellés au-dessus des commandes
	var c_blanc: Color = Color(1.0, 0.98, 0.92)
	var c_vert: Color = Color(0.25, 1.0, 0.45)
	# rangée 1 : portes
	for g in range(2):
		var xa: float = cols[2 * g]
		var xb: float = cols[2 * g + 1]
		_cadre(filet, xa - 0.03, xb + 0.03, rangs[0] - 0.043, rangs[0] + 0.0215,
			"PORTES 1 à 6" if g == 0 else "PORTES 7 à 12")
		_lumineux(chrome, Vector2(xa, rangs[0]), "ouverture_%d" % g, c_blanc)
		_lumineux(chrome, Vector2(xb, rangs[0]), "fermeture_%d" % g, c_vert)
		_etiquette("OUVERTURE", Vector2(xa, rangs[0] + lab_z), 14, Color(0.06, 0.06, 0.07))
		_etiquette("FERMETURE", Vector2(xb, rangs[0] + lab_z), 14, Color(0.06, 0.06, 0.07))
	# rangée 2 : PRÊT, bouton noir, sélecteur, commutateur à clé
	_lumineux(chrome, Vector2(cols[0], rangs[1]), "pret", c_vert)
	_commandes.erase("pret")              # voyant, pas un bouton
	_etiquette("PRÊT", Vector2(cols[0], rangs[1] + lab_z), 16, Color(0.06, 0.06, 0.07))
	_commande("montee", Vector2(cols[1], rangs[1]), _poussoir_noir(chrome, noir, Vector2(cols[1], rangs[1])))
	_etiquette("MONTÉE", Vector2(cols[1], rangs[1] + lab_z), 14, Color(0.06, 0.06, 0.07))
	var sel: Node3D = _selecteur(chrome, noir, Vector2(cols[2], rangs[1]))
	_commande("vite", Vector2(cols[2], rangs[1]), sel)
	_etiquette("− VITE", Vector2(cols[2] - 0.021, rangs[1] + lab_z), 12, Color(0.06, 0.06, 0.07))
	_etiquette("+ VITE", Vector2(cols[2] + 0.021, rangs[1] + lab_z), 12, Color(0.06, 0.06, 0.07))
	var cle: Node3D = _cle(chrome, noir, Vector2(cols[3], rangs[1]))
	cle.rotation.y = PI * 0.5             # tournée : EN MARCHE
	_commande("marche", Vector2(cols[3], rangs[1]), cle)
	_etiquette("EN MARCHE", Vector2(cols[3], rangs[1] + lab_z), 13, Color(0.06, 0.06, 0.07))
	# rangée 3 : KLAXON, groupe ÉCLAIRAGE
	_klaxon = _poussoir_noir(chrome, noir, Vector2(cols[0], rangs[2]))
	_commande("klaxon", Vector2(cols[0], rangs[2]), _klaxon)
	_etiquette("KLAXON", Vector2(cols[0], rangs[2] + lab_z), 15, Color(0.06, 0.06, 0.07))
	_cadre(filet, cols[1] - 0.03, cols[3] + 0.03, rangs[2] - 0.041, rangs[2] + 0.024, "ÉCLAIRAGE")
	_cabine_bouton = _selecteur(chrome, noir, Vector2(cols[1], rangs[2]))
	_commande("cabine", Vector2(cols[1], rangs[2]), _cabine_bouton)
	_etiquette("CABINE", Vector2(cols[1], rangs[2] + lab_z), 14, Color(0.06, 0.06, 0.07))
	_etiquette("0", Vector2(cols[1] - 0.017, rangs[2] - 0.012), 12, Color(0.06, 0.06, 0.07))
	_etiquette("1", Vector2(cols[1] + 0.017, rangs[2] - 0.012), 12, Color(0.06, 0.06, 0.07))
	_lumineux(chrome, Vector2(cols[2], rangs[2]), "compartiment", c_blanc)
	_etiquette("COMPARTIMENT", Vector2(cols[2], rangs[2] + lab_z), 13, Color(0.06, 0.06, 0.07))
	_lumineux(chrome, Vector2(cols[3], rangs[2]), "secours", c_blanc)
	_etiquette("SECOURS", Vector2(cols[3], rangs[2] + lab_z), 14, Color(0.06, 0.06, 0.07))


## Plaque de gauche (photo 095119, ajout demandé par Kevin le 06/10/2026 :
## « à gauche de l'écran il y a les boutons rouges ») : cadre « ARRÊTS »,
## deux coups-de-poing rouges — URGENCE (le gros, au milieu) et ÉLECTRIQUE
## (le petit, à droite) — et, à gauche d'URGENCE, l'emplacement d'un bouton
## qui n'est pas monté (obturateur gris) ; dessous à gauche, une clé à
## étiquette rouge. Libellés : Kevin, 07/10/2026.
func _construire_gauche(chrome: StandardMaterial3D, noir: StandardMaterial3D,
		filet: StandardMaterial3D) -> void:
	var z_g: float = -0.030
	var xs: Array = [X_GAUCHE - 0.060, X_GAUCHE + 0.0, X_GAUCHE + 0.058]
	# libellés haut placés : les champignons les cacheraient depuis le siège
	_cadre(filet, xs[0] - 0.030, xs[2] + 0.034, z_g - 0.064, z_g + 0.032, "ARRÊTS")
	_etiquette("URGENCE", Vector2(xs[1], z_g - 0.047), 14, Color(0.06, 0.06, 0.07))
	_etiquette("ÉLECTRIQUE", Vector2(xs[2] + 0.004, z_g - 0.047), 13, Color(0.06, 0.06, 0.07))
	# emplacement vide : bague et obturateur à fleur, pas un bouton
	var gris: StandardMaterial3D = _mat(Color(0.80, 0.80, 0.76), 0.95, 0.0)
	_sur_face(_cylindre(chrome, 0.0175, 0.006), Vector2(xs[0], z_g), 0.003)
	_sur_face(_cylindre(gris, 0.0140, 0.004), Vector2(xs[0], z_g), 0.004)
	var rouge: StandardMaterial3D = _mat(Color(0.78, 0.07, 0.05), 0.4, 0.0)
	# au milieu le plus gros = URGENCE, à droite le plus petit = ÉLECTRIQUE
	# (Kevin, 07/10/2026) ; verrouillés enfoncés tant que l'arrêt dure
	for k in range(2):
		var p: Vector2 = Vector2(xs[1 + k], z_g)
		var r_tete: float = 0.024 if k == 0 else 0.018
		_sur_face(_cylindre(noir, r_tete + 0.002, 0.010), p, 0.005)
		# champignon : tige et tête bombée
		var tete: Node3D = Node3D.new()
		_sur_face(tete, p, 0.010)
		var tige: MeshInstance3D = _cylindre(rouge, 0.012, 0.012)
		tige.position.y = 0.004
		tete.add_child(tige)
		var dome: MeshInstance3D = MeshInstance3D.new()
		var sp: SphereMesh = SphereMesh.new()
		sp.radius = r_tete
		sp.height = r_tete * 0.95
		sp.is_hemisphere = true
		sp.radial_segments = 20
		sp.rings = 6
		sp.material = rouge
		dome.mesh = sp
		dome.position.y = 0.010
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tete.add_child(dome)
		_commande("rouge_%d" % (k + 1), p, tete)
	# clé à étiquette rouge, sous le cadre à gauche
	var pc: Vector2 = Vector2(X_GAUCHE - 0.055, 0.050)
	_commande("cle_gauche", pc, _cle(chrome, noir, pc))
	var etiq: MeshInstance3D = _boite(rouge, Vector3(0.022, 0.004, 0.030),
		Vector3(pc.x - 0.012, 0.012, pc.y + 0.030), _face)
	etiq.rotation = Vector3(0.0, 0.35, 0.0)


# --- appuis (vue cabine) ------------------------------------------------------

func _commande(nom: String, p: Vector2, n: Node3D) -> void:
	_commandes[nom] = [p, n, n.position.y]


## Commande sous le point d'écran `pos` vu par `cam` : "ouverture_0",
## "fermeture_1", "montee", "vite_moins", "vite_plus" (moitié gauche
## ou droite du sélecteur), "marche", "klaxon", "cabine",
## "compartiment", "secours", "rouge_1", "rouge_2", "cle_gauche",
## "ecran" ; "" si rien.
func commande_sous(cam: Camera3D, pos: Vector2) -> String:
	if _face == null or cam == null:
		return ""
	var o: Vector3 = cam.project_ray_origin(pos)
	var d: Vector3 = cam.project_ray_normal(pos)
	var xf: Transform3D = _face.global_transform
	var n: Vector3 = xf.basis.y.normalized()
	var den: float = n.dot(d)
	if absf(den) < 1e-4:
		return ""
	var t: float = n.dot(xf.origin - o) / den
	if t <= 0.0:
		return ""
	var loc: Vector3 = xf.affine_inverse() * (o + d * t)
	var q: Vector2 = Vector2(loc.x, loc.z)
	var meilleur: String = ""
	var d_min: float = R_COMMANDE
	for nom in _commandes:
		var dd: float = q.distance_to(_commandes[nom][0])
		if dd < d_min:
			d_min = dd
			meilleur = nom
	if meilleur == "vite":
		meilleur = "vite_moins" if q.x < (_commandes["vite"][0] as Vector2).x else "vite_plus"
	if meilleur == "" and absf(q.x - X_ECRAN) < ECRAN_L * 0.5 \
			and absf(q.y - Z_ECRAN) < ECRAN_H * 0.5:
		meilleur = "ecran"
	return meilleur


## Enfonce (ou relâche) la commande : poussoirs 3 mm, sélecteur et clé
## tournent d'un cran à l'appui.
func appuyer(nom: String, enfonce: bool) -> void:
	_enfoncee = nom if enfonce else ""
	if nom == "ecran":
		if enfonce:
			_page_forcee = 0 if (ecran != null and ecran.page_portes) else 1
			_t_ecran = 0.0
		return
	if nom.begins_with("vite_"):
		# à rappel : tourné tant qu'on le tient, vertical au repos
		var sel: Node3D = _commandes["vite"][1]
		sel.rotation.y = (0.6 if nom == "vite_moins" else -0.6) if enfonce else 0.0
		return
	var c: Array = _commandes.get(nom, [])
	if c.is_empty():
		return
	var n: Node3D = c[1]
	if nom == "marche" or nom == "cle_gauche":
		if enfonce:
			n.rotation.y = 0.0 if n.rotation.y != 0.0 else PI * 0.5
			if nom == "marche":
				en_marche = n.rotation.y != 0.0
				_t_ecran = 0.0
	elif nom != "cabine" and not nom.begins_with("rouge_"):
		n.position.y = (c[2] as float) - (0.003 if enfonce else 0.0)


## Met à jour voyants, commandes et écran depuis l'état de la rame.
func mettre_a_jour(ph: TrainPhysics, dt: float, vehicule: int, ecran_visible: bool, rame_en_face: bool = false) -> void:
	if ph == null:
		return
	var ouvertes: bool = ph.door_leaves_open or ph.doors_open
	# PRÊT : le conducteur a appuyé sur MONTÉE (séquence de départ lancée,
	# ou rame partie)
	var depart: bool = ph.trip_started or ph.departure_buzzer_remaining > 0.0 \
		or ph.confirmation_autre_remaining > 0.0 \
		or ((ph.announce_phase_remaining > 0.0 or ph.door_phase_remaining > 0.0)
			and not ph._fermeture_seule)
	var pret: bool = ph.pret_externe == 1 if ph.pret_externe >= 0 \
		else (depart and not ph.emergency and not ph.cable_rupture)
	# PORTES 1 à 6 = côté gauche en regardant vers le haut, 7 à 12 = droite
	for g in range(2):
		var cote: bool = ouvertes and (ph.portes_cotes & (1 << g)) != 0
		_allumer(NOMS_OUVERTURE[g], en_marche and cote)
		_allumer(NOMS_FERMETURE[g], en_marche and not cote)
	_allumer("pret", en_marche and pret)
	_allumer("compartiment", en_marche and ph.lights_cabin)
	_allumer("secours", en_marche)
	if _mat_ecran != null:
		# commutateur général sur arrêt : écran noir
		var tex: Texture2D = _sv.get_texture() if en_marche else null
		if _mat_ecran.albedo_texture != tex:
			_mat_ecran.albedo_texture = tex
			_mat_ecran.albedo_color = Color.WHITE if en_marche else Color(0.02, 0.02, 0.025)
	if _cabine_bouton != null:
		_cabine_bouton.rotation.y = -0.6 if ph.lights_cabin else 0.6
	# coups-de-poing verrouillés enfoncés : URGENCE, ARRÊT ÉLEC
	for k in range(2):
		var c: Array = _commandes.get(NOMS_ROUGE[k], [])
		if not c.is_empty():
			var engage: bool = ph.emergency if k == 0 else ph.arret_elec
			(c[1] as Node3D).position.y = (c[2] as float) - (0.006 if engage else 0.0)
	if _klaxon != null:
		_klaxon.position.y = 0.0025 if (ph.horn or _enfoncee == "klaxon") else 0.0055
	if not ecran_visible or ecran == null:
		return
	_t_ecran -= dt
	if _t_ecran > 0.0:
		return
	_t_ecran = PERIODE_ECRAN
	var e: EcranProface = ecran
	e.vitesse = absf(ph.vitesse_roues())
	# rame d'en face : sa position et son sens à elle (miroir de la poulie)
	e.distance = PNConstants.distance_compteur(ph.ghost_s_render(), -ph.direction) if rame_en_face \
		else PNConstants.distance_compteur(ph.s, ph.direction)
	e.vehicule = vehicule
	var en_gare: bool = absf(ph.v) < 0.05 and (ph.s < PNConstants.START_S + 3.0
		or ph.s > PNConstants.STOP_S - 3.0)
	# page : automatique (en gare → portes), sauf appui sur l'écran, qui
	# vaut jusqu'au prochain départ ou à la prochaine arrivée
	if en_gare != _en_gare_prec:
		_en_gare_prec = en_gare
		_page_forcee = -1
	e.page_portes = en_gare if _page_forcee < 0 else _page_forcee == 1
	e.portes_ouvertes = ouvertes
	e.arret_frein_service = ph.maint_brake or ph.brake > 0.5 or ph.manual_brake_held
	e.arret_elec = ph.arret_elec or ph.emergency
	e.alarme = ph.alarme_externe or ph.speed_cap_external < PNConstants.V_MAX or ph.cable_rupture
	e.pret_motrice = not ph.cable_rupture and not ph.emergency
	# PRÊT VÉHICULE de l'autre rame : confirmation simulée 2-4 s après la
	# fermeture des portes (buzzer en cours ou rame partie) — avant, le
	# voyant était allumé en permanence (audit 07/10/2026)
	e.pret_autre = ph.pret_autre_externe if ph.pret_externe >= 0 else ph.pret_autre_simule()
	e.marche = ph.trip_started and absf(ph.v) > 0.05
	e.autorisation_portes = en_gare and not ph.trip_started
	e.frein_voie_leve = not ph.cable_rupture and ph.overspeed_level < 3
	e.ralentisseur_leve = true
	e.portes_secours_fermees = true
	e.vitesse_reduite = ph.speed_cap_external < PNConstants.V_MAX
	var sig: String = e.signature_fond()
	var change: bool = sig != _sig_fond
	if change:
		_sig_fond = sig
		e.queue_redraw()
		_sv_fond.render_target_update_mode = SubViewport.UPDATE_ONCE
	_valeurs.vitesse = e.vitesse
	_valeurs.distance = e.distance
	var sig_v: String = _valeurs.signature_valeurs()
	if change or sig_v != _sig_valeurs:
		_sig_valeurs = sig_v
		_valeurs.queue_redraw()
		_sv.render_target_update_mode = SubViewport.UPDATE_ONCE


## Textes relevés par une couche de l'écran → Label3D vectoriels sur la
## dalle (repère du quad : x vers la droite, y vers le haut, +z = face).
func _poser_textes(e: EcranProface) -> void:
	if _mi_ecran == null:
		return
	if not _textes_3d.has(e):
		_textes_3d[e] = []
	var pool: Array = _textes_3d[e]
	var police: Font = PolicesJeu.reguliere()
	var m_px: float = ECRAN_L / EcranProface.L
	for i in range(e.textes.size()):
		var t: Array = e.textes[i]
		var l: Label3D = null
		if i < pool.size():
			l = pool[i]
		else:
			l = Label3D.new()
			l.font = police
			l.shaded = false
			l.double_sided = false
			l.outline_size = 0
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			l.render_priority = 1
			_mi_ecran.add_child(l)
			pool.append(l)
		var pos: Vector2 = t[0]
		var taille: int = t[2]
		var larg: float = t[4]
		var align: int = t[5]
		var x: float = pos.x
		if larg > 0.0 and align == HORIZONTAL_ALIGNMENT_CENTER:
			x += larg * 0.5
		elif larg > 0.0 and align == HORIZONTAL_ALIGNMENT_RIGHT:
			x += larg
		var y: float = pos.y + police.get_descent(taille)
		l.text = t[1]
		l.font_size = taille
		l.pixel_size = m_px
		l.modulate = t[3]
		l.horizontal_alignment = align
		l.position = Vector3(x * m_px - ECRAN_L * 0.5, ECRAN_H * 0.5 - y * m_px, 0.0004)
		l.visible = true
	for j in range(e.textes.size(), pool.size()):
		(pool[j] as Label3D).visible = false


func _nouvel_ecran() -> SubViewport:
	var sv: SubViewport = SubViewport.new()
	var k: int = 2     # formes seules : les textes de l'écran sont en vectoriel (Label3D MSDF)
	sv.size = Vector2i(int(EcranProface.L) * k, int(EcranProface.H) * k)
	sv.size_2d_override = Vector2i(int(EcranProface.L), int(EcranProface.H))
	sv.size_2d_override_stretch = true
	sv.transparent_bg = false
	sv.disable_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	return sv


# --- éléments ---------------------------------------------------------------

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _boite(m: Material, taille: Vector3, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = taille
	b.material = m
	mi.mesh = b
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cylindre(m: Material, r: float, h: float, seg: int = 18) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.material = m
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sur_face(n: Node3D, p: Vector2, y: float) -> Node3D:
	n.position = Vector3(p.x, y, p.y)
	_face.add_child(n)
	return n


## Bouton-poussoir lumineux : bague chromée et cabochon (s'allume).
func _lumineux(chrome: StandardMaterial3D, p: Vector2, nom: String, c: Color) -> void:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = _eteint(c)
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	_commande(nom, p, _sur_face(_cylindre(m, 0.0135, 0.011), p, 0.0065))
	_voyants[nom] = [m, c]


## Cabochon éteint : blanc laiteux grisé, vert presque noir (sur la photo
## le blanc éteint reste clair, le vert éteint est sombre).
func _eteint(c: Color) -> Color:
	return c.darkened(0.55) if c.g < 0.99 or c.r > 0.9 else c.darkened(0.88)


func _allumer(nom: String, on: bool) -> void:
	var v: Array = _voyants.get(nom, [])
	if v.is_empty():
		return
	var m: StandardMaterial3D = v[0]
	var e: float = 2.2 if on else 0.0
	if m.emission_energy_multiplier != e:
		m.emission_energy_multiplier = e
		m.albedo_color = (v[1] as Color) if on else _eteint(v[1])


func _poussoir_noir(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> Node3D:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	return _sur_face(_cylindre(noir, 0.0145, 0.008), p, 0.0055)


## Sélecteur rotatif : bouton noir et index blanc (tourne autour de y).
func _selecteur(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> Node3D:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	var pivot: Node3D = Node3D.new()
	_sur_face(pivot, p, 0.006)
	var corps: MeshInstance3D = _cylindre(noir, 0.0135, 0.010)
	pivot.add_child(corps)
	var index: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = Vector3(0.004, 0.016, 0.022)
	b.material = noir
	index.mesh = b
	index.position = Vector3(0.0, 0.010, 0.0)
	pivot.add_child(index)
	var blanc: MeshInstance3D = MeshInstance3D.new()
	var bb: BoxMesh = BoxMesh.new()
	bb.size = Vector3(0.0045, 0.002, 0.012)
	bb.material = _mat(Color(0.95, 0.95, 0.93), 0.4, 0.0)
	blanc.mesh = bb
	blanc.position = Vector3(0.0, 0.0185, -0.004)
	pivot.add_child(blanc)
	return pivot


func _cle(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> Node3D:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	_sur_face(_cylindre(chrome, 0.012, 0.014), p, 0.010)
	var cle: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = Vector3(0.003, 0.022, 0.016)
	b.material = noir
	cle.mesh = b
	return _sur_face(cle, p, 0.026)


## Cadre de groupe gravé, libellé au milieu du côté haut : le trait s'y
## interrompt (Kevin, 07/10/2026 : « le trait du cerclage s'interrompt pour
## le titre du box »).
func _cadre(filet: StandardMaterial3D, xa: float, xb: float, za: float, zb: float, titre: String) -> void:
	var e: float = 0.0012
	var cx: float = (xa + xb) * 0.5
	var demi: float = 0.0
	if titre != "":
		var police: Font = ThemeDB.fallback_font
		demi = police.get_string_size(titre, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x \
			* PIXEL_ETIQUETTE * 0.5 + 0.004
	for seg in [[xa, cx - demi], [cx + demi, xb]]:
		_boite(filet, Vector3(seg[1] - seg[0], 0.0008, e), Vector3((seg[0] + seg[1]) * 0.5, 0.0034, za), _face)
	_boite(filet, Vector3(xb - xa, 0.0008, e), Vector3(cx, 0.0034, zb), _face)
	for x in [xa, xb]:
		_boite(filet, Vector3(e, 0.0008, zb - za), Vector3(x, 0.0034, (za + zb) * 0.5), _face)
	if titre != "":
		_etiquette(titre, Vector2(cx, za), 18, Color(0.05, 0.05, 0.06))


## Libellé gravé, à plat sur la face, lisible depuis le siège.
func _etiquette(t: String, p: Vector2, taille: int, c: Color) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = t
	l.font_size = taille * SURECHANTILLON
	l.pixel_size = PIXEL_ETIQUETTE / float(SURECHANTILLON)
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_sur_face(l, p, 0.0036)
	return l
