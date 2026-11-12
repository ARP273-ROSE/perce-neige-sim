class_name Funival
extends Telepherique
## Funival (Val d'Isère, La Daille → Bellevarde ; Montaval sous licence Waagner-Biró, 1987 ; véhicules Cwa) :
## funiculaire à deux véhicules de 272 places, câble tracteur, gare motrice amont. D'après la fiche technique et
## les photos du reportage remontees-mecaniques.net (fiche de cotes : _cuites/funival/FICHE_PHOTOS.md, cotes
## estimées sur photo) et le tracé OSM :
## - de la gare aval au portail : ~496 m en plan, voie dans une poutre en U de béton sur piles courtes (27 %) ;
## - du portail à la gare amont : tunnel circulaire rectiligne (48 %), évitement à mi-ligne (deux voies) ;
## - gare amont creusée sous le rocher de Bellevarde, débouchant dans un bâtiment bardé en surface.
## Le mouvement (quai, route, poste de commande) est celui du téléphérique va-et-vient.
##
## d : distance horizontale depuis la gare aval ; −Z vers l'amont, comme les autres lignes.

const V_FUNI: float = 12.0              # m/s (fiche)
## Accélération et freinage de service : 0,18 m/s² en moyenne de 0 à 10 m/s, mesurés sur la trace GPS d'un
## passage réel (26/04/2026, départ de La Daille : 56 s pour atteindre 10 m/s ; calcul Sage
## « trace.sage » du Funival). Freinage pris égal (non mesuré : tunnel sans GPS).
const A_FUNI: float = 0.18
## Marche en ligne à V_FUNI (12 m/s de la fiche), ralentie à V_EVIT pour attaquer le croisement, reprise à V_FUNI une fois
## le véhicule sorti des aiguillages, puis ralentie pour arriver à V_QUAI au début du quai (consigne d'utilisateur du
## 10/11/2026, qui prime sur le calage sur la durée de la vidéo de la montée).
const V_EVIT: float = 8.0
const V_QUAI: float = 1.0
## Accostage au dernier mètre.
const A_ACCOSTAGE: float = 0.30
## Courbe de freinage tracée à 85 % du freinage de service : à 100 %, le véhicule la suivait en retard.
const K_COURBE: float = 0.85
## Attente à quai : 45 s (téléphérique), prolongée tant que le skieur marche dans le véhicule ou sur ses quais, portes
## ouvertes, jusqu'à T_QUAI_MAX (« le funi part trop vite quand on monte l'escalier en gare aval, pas le temps d'aller
## jusqu'en tête », 09/11/2026).
const T_QUAI_MAX: float = 150.0
const ECARTEMENT: float = 1.20          # m (OSM, Wikipédia)
const E_VOIES: float = 2.35             # entraxe : rails intérieurs à ~1,15 m, au plus l'écartement (1,20 m), un peu moins (utilisateur, à l'œil sur la vidéo de descente, 08/11/2026)
## Évitement mesuré sur la vidéo de la montée en cabine de conduite (KxhTv7cGK-I, demande d'utilisateur du 09/11/2026 :
## « l'évitement est beaucoup trop long ») : aiguillage du bas à 2:26,5, voies parallèles de 2:32 à 2:41,5, aiguillage
## du haut à 2:43, à 6 m/s → 99 m d'aiguillage à aiguillage (290 avant).
const L_EVITEMENT: float = 57.0         # m, voies parallèles (9,5 s à 6 m/s)
const L_RACCORD: float = 21.0           # m, aiguillage passif et courbe en S (3,5 s à 6 m/s)
const R_TUNNEL: float = 2.65            # m (retour d'utilisateur du 09/11/2026 : tube trop petit pour le véhicule ; 3,89 m de hauteur libre au-dessus des rails pour 3,65 de caisse)
const R_TUNNEL_EVIT: float = 3.90       # m (section élargie à deux voies)
const PROF_PORTAIL: float = 4.0         # voie sous le terrain au droit du portail (m)
const DESSOUS_POUTRE: float = 2.8       # dessus des rails au-dessus du sol dehors (dessous de la poutre à 1,5-2 m du sol sur photo)
const PAS_PROFIL: float = 5.0
const PAS_TUNNEL: float = 2.5           # anneaux du tunnel (l'éclairage est cuit aux sommets)
const ECART_LAMPES: float = 20.0        # 15-25 m sur photo
const L_HALL: float = 40.0              # gare amont souterraine (quai d'un véhicule de 32 m, marge)
const FOSSE_AVAL: float = 1.0           # rails sous le plus haut du terrain en gare aval (planchers au niveau du sol)

var portail_d: float = 496.2            # (données ; OSM : bout du pont, début du tunnel)
var _y_portail: float = 0.0
var _y_amont: float = 0.0
var _y_aval: float = 0.0
var _prof: PackedFloat32Array = PackedFloat32Array()      # dessus des rails tous les PAS_PROFIL m
static var _mats_funi: Dictionary = {}


func masse_vehicule() -> float:
	return 21840.0                      # plaque Cwa


func tension_h() -> float:
	return 200000.0


## Distance entre le centre du véhicule et son point d'arrêt quand le nez atteint le début du quai.
func longueur_quai_nez() -> float:
	return VehiculeFunival.DEMI_L * 2.0 + 2.0


func _x_quai(aval: bool) -> float:
	return VehiculeFunival.DEMI_L + 1.0 if aval else longueur_h() - VehiculeFunival.DEMI_L - 1.0


func zone_vehicule(i: int) -> String:
	var d: float = _vehicules[i][1]
	if d <= _x_quai(true) + 1.0:
		return "gare_aval"
	if d >= _x_quai(false) - 1.0:
		return "gare_amont"
	return "ligne"


## Véhicules à quai, portes ouvertes (on peut entrer et sortir).
func portes_ouvertes() -> bool:
	return _phase == "quai" and T_QUAI - _t_quai > 1.5 and _t_quai > 1.5


func demi_interieur() -> Vector2:
	return Vector2(VehiculeFunival.DEMI_LARGEUR - 0.15, VehiculeFunival.DEMI_L - 0.4)


## Compartiment (0 en bas) qui contient l'abscisse z du repère du véhicule.
func compartiment(z: float) -> int:
	return VehiculeFunival.compartiment(z)


# --- voie -------------------------------------------------------------------------------

## Hauteur du dessus des rails en d (repère de la ligne).
func y_voie(d: float) -> float:
	if _prof.is_empty():
		return terrain(clampf(d, 0.0, longueur_h()))
	var u: float = clampf(d, 0.0, longueur_h()) / PAS_PROFIL
	var k: int = mini(int(u), _prof.size() - 2)
	return lerpf(_prof[k], _prof[k + 1], u - float(k))


func pente_voie(d: float) -> float:
	return (y_voie(d + 2.5) - y_voie(d - 2.5)) / 5.0


## Décalage latéral de la voie du véhicule i (0 : monte à gauche dans l'évitement) en d.
func x_voie(d: float, i: int) -> float:
	return (-1.0 if i == 0 else 1.0) * E_VOIES * 0.5 * _t_evit(d)


## 0 hors évitement, 1 dedans, raccord en S.
func _t_evit(d: float) -> float:
	var e: float = absf(d - longueur_h() * 0.5)
	var h: float = L_EVITEMENT * 0.5
	var t: float = 1.0 - smoothstep(h, h + L_RACCORD, e)
	return t * t * (3.0 - 2.0 * t)


func dans_tunnel(d: float) -> bool:
	return d > portail_d


## Profil de la voie, courbe régulière :
## - dehors, une parabole ajustée sur la trace GPS altimétrique d'un passage réel (26/04/2026, 68 points projetés sur
##   l'axe, résidu ≤ 4,3 m ; calcul Sage du Funival rampe.sage) : 20,8 % au départ, 29,7 % au portail ; le
##   viaduc ne suit pas le terrain, il est porté par des piles (photos : hautes et fines) ;
## - dans le tunnel, la pente monte progressivement jusqu'au maximum de la fiche (53 %, funiculaires-france.fr), s'y
##   tient, et se réduit seulement à la toute fin, en gare amont, où elle reste prononcée (comme au Perce-Neige ;
##   utilisateur, 08/11/2026) ; pente en gare ESTIMÉE (45 %) ; la longueur de la montée vers 53 % se déduit de
##   l'altitude de la gare amont.
## Calée à l'aval sur le haut du terrain de la gare (planchers au niveau du sol, voie en fosse).
const RAMPE_S0: float = 0.207756          # pente au départ (trace GPS)
const RAMPE_K: float = 8.985184e-05       # y = s0·d + k·d²
const RACCORD_TUNNEL: float = 150.0
const PENTE_MAX: float = 0.53             # fiche (funiculaires-france.fr)
## En gare amont, les marches des compartiments et celles des quais sont horizontales (photos, utilisateur 08/11/2026) :
## la pente en gare est celle pour laquelle les compartiments sont de niveau (VehiculeFunival.PENTE_GRADINS) —
## une seule valeur : 30 % (utilisateur, 08/11/2026).
const PENTE_GARE_AMONT: float = VehiculeFunival.PENTE_GRADINS
const L_QUAI_AMONT: float = 35.0          # en plan, à PENTE_GARE_AMONT
## Haut du tracé : MÊME DÉRIVÉE de pente que le haut du Perce-Neige (SlopeProfile.SLOPE_PROFILE : sous le quai de la
## gare haute, 10 % → 18 % sur 57,01 m puis 18 % → 27 % sur 52 m le long de la pente), depuis la sortie du quai amont,
## taux prolongé jusqu'à 53 % (demande d'utilisateur, 08/11/2026) : 144 m. Contrôle : calcul Sage du Funival haut2.sage.
const TAUX_HAUT_PN: Array = [[0.08 / 57.01, 57.01], [0.09 / 52.0, 52.0]]   # [points par mètre de pente, longueur]
var _pente_haut: PackedFloat32Array = PackedFloat32Array()   # pente tous les 1 m en plan sous le quai amont
var _rampe_bas: float = 0.0                                   # montée 29,7 % → 53 % depuis le portail (m en plan)
var _d53_fin: float = 0.0                                     # fin du palier à 53 % (début de la variation du haut)
var _s1: float = 0.0
var _murs_bat: Array = []
var _perron_col: Array = []      # perrons du bâtiment [taille, Transform3D], pour les collisions        # murs du bâtiment de Bellevarde [taille, centre], pour les collisions


## Sol du rez-de-chaussée du bâtiment de Bellevarde : au niveau du haut de la rampe des escaliers (le plancher du
## dernier compartiment la dépassait de 0,14 m — ressaut mesuré par le PC, lot 13).
func sol_batiment() -> float:
	return VehiculeFunival.y_plancher_monde(self, longueur_h() - 1.0) - 0.14


## Pente de la voie dans le tunnel et en gare amont, en d (plan).
func _pente_tunnel_en_d(d: float) -> float:
	var L: float = longueur_h()
	if d >= L - L_QUAI_AMONT:
		return PENTE_GARE_AMONT
	if d >= _d53_fin:
		var k: int = clampi(int(L - L_QUAI_AMONT - d), 0, _pente_haut.size() - 1)
		return _pente_haut[k]
	if d >= portail_d + _rampe_bas:
		return PENTE_MAX
	return lerpf(_s1, PENTE_MAX, (d - portail_d) / maxf(_rampe_bas, 1.0))


func _preparer_voie() -> void:
	var L: float = longueur_h()
	_y_aval = terrain(0.0)
	_y_amont = terrain(L)
	var W0: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	# ancrage aval : le plancher du compartiment le plus enterré au niveau du terrain (quais compris)
	var dep: float = -INF
	var dd: float = 0.0
	while dd <= 2.0 * VehiculeFunival.DEMI_L + 2.0:
		for xs in [-(W0 + LARG_GRADINS[0]), -(W0 + LARG_GRADINS[0] * 0.5), 0.0, W0 + LARG_GRADINS[1] * 0.5, W0 + LARG_GRADINS[1]]:
			dep = maxf(dep, _sol(float(xs), -dd) - (RAMPE_S0 * dd + RAMPE_K * dd * dd))
		dd += 1.0
	var y0_g: float = dep - FOSSE_AVAL
	var y0: float = y0_g
	# portail : là où la poutre touche le terrain (rails à 0,3 m sous le sol) ; l'anneau sort alors de ~4 m, dans sa
	# boîte de béton (photos) ; calé sur « haut de l'anneau à fleur », il ne sortait que de 0,5 m et la poutre
	# plongeait 8 m dans la neige avant (captures du PC, lots 12 et 13) ; deux passes, la rampe dépendant de la
	# longueur dehors
	var dp: float = portail_d
	for passe in range(2):
		y0 = y0_g
		# la poutre (dessous à 1 m sous les rails) jamais sous le terrain le long de la rampe
		var d2: float = 60.0
		while d2 < dp - 20.0:
			y0 = maxf(y0, _sol(0.0, -d2) + 0.2 - (RAMPE_S0 * d2 + RAMPE_K * d2 * d2))
			d2 += 5.0
		var dc: float = 300.0
		while dc < portail_d + 60.0:
			if _sol(0.0, -dc) >= y0 + RAMPE_S0 * dc + RAMPE_K * dc * dc - 0.3:
				break
			dc += 1.0
		dp = dc
	portail_d = dp
	var yp: float = y0 + RAMPE_S0 * dp + RAMPE_K * dp * dp
	_s1 = RAMPE_S0 + 2.0 * RAMPE_K * dp
	_y_portail = yp
	# variation du haut, descendue depuis le bas du quai amont : pente tous les 1 m en plan, et dénivelé
	_pente_haut = PackedFloat32Array()
	var pt: float = PENTE_GARE_AMONT
	var u: float = 0.0
	var chute: float = PENTE_GARE_AMONT * L_QUAI_AMONT
	var k_t: int = 0
	var reste_t: float = float(TAUX_HAUT_PN[0][1])
	var u_suiv: float = 0.0
	while pt < PENTE_MAX:
		var r_t: float = float(TAUX_HAUT_PN[mini(k_t, TAUX_HAUT_PN.size() - 1)][0])
		reste_t -= 0.25
		if reste_t <= 0.0 and k_t + 1 < TAUX_HAUT_PN.size():
			k_t += 1
			reste_t = float(TAUX_HAUT_PN[k_t][1])
		var du: float = 0.25 / sqrt(1.0 + pt * pt)
		while u >= u_suiv:
			_pente_haut.append(pt)
			u_suiv += 1.0
		u += du
		chute += pt * du
		pt = minf(pt + r_t * 0.25, PENTE_MAX)
	_d53_fin = L - L_QUAI_AMONT - u
	# montée basse 29,7 % → 53 % depuis le portail, longueur telle que le profil rejoigne la sortie connue
	var y53_fin: float = _y_amont - chute
	var montee: float = y53_fin - yp
	var lg53: float = _d53_fin - dp
	_rampe_bas = clampf((PENTE_MAX * lg53 - montee) * 2.0 / (PENTE_MAX - _s1), RACCORD_TUNNEL, lg53)
	var n: int = int(ceil(L / PAS_PROFIL)) + 1
	var prof: PackedFloat32Array = PackedFloat32Array()
	prof.resize(n)
	var y_t: float = yp
	for k in range(n):
		var d: float = minf(float(k) * PAS_PROFIL, L)
		var y: float
		if d <= dp:
			y = y0 + RAMPE_S0 * d + RAMPE_K * d * d
			y_t = yp
		else:
			# intégration de la pente par pas de PAS_PROFIL (trapèzes)
			var da: float = maxf(d - PAS_PROFIL, dp)
			y_t += (_pente_tunnel_en_d(da) + _pente_tunnel_en_d(d)) * 0.5 * (d - da)
			y = y_t
		prof[k] = y
	_prof = prof


# --- matériaux ----------------------------------------------------------------------------

## Matériaux propres au Funival. « cuit » : sans éclairage, couleur des sommets (tunnel, gare souterraine : la
## lumière du ciel n'y entre pas ; les lampes sont peintes dans les couleurs).
static var _mat_cuit: ShaderMaterial = null
## Matériau « cuit » : la couleur des sommets (lumière des lampes peinte, teintes d'écran en sRGB) est rendue telle
## quelle ; la surface reçoit en plus les seules lumières locales — les phares des véhicules (vidéos : parois
## jaune-beige très éclairées devant le véhicule) —, ni soleil, ni ciel, ni brouillard.
const NUANCEUR_CUIT: String = """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, fog_disabled, specular_disabled;
varying vec3 lin;
vec3 vers_lineaire(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
void fragment() {
	lin = vers_lineaire(COLOR.rgb);
	EMISSION = lin;
	// paroi sous les phares : béton gris (photos), à peine teinté de la couleur cuite, réflectance 0,5
	vec3 n = lin / max(max(lin.r, lin.g), max(lin.b, 0.002));
	ALBEDO = mix(vec3(dot(n, vec3(0.333))), n, 0.3) * 0.5;
	ROUGHNESS = 0.95;
}
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += abs(dot(NORMAL, LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
"""
## Rendu de compatibilité (PWA, OpenGL) : l'émission d'un nuanceur à light() personnalisé n'y passe pas (tunnel
## entièrement noir, captures OpenGL du PC du 08/11/2026) ; on y garde la seule lumière cuite, sans phares.
const NUANCEUR_CUIT_COMPAT: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
"""


static func mat_funi(nom: String) -> Material:
	if nom == "cuit":
		RemonteeKit.verrou.lock()
		if _mat_cuit == null:
			var sh: Shader = Shader.new()
			var compat: bool = String(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")) == "gl_compatibility" \
				or OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility"
			sh.code = NUANCEUR_CUIT_COMPAT if compat else NUANCEUR_CUIT
			_mat_cuit = ShaderMaterial.new()
			_mat_cuit.shader = sh
		RemonteeKit.verrou.unlock()
		return _mat_cuit
	RemonteeKit.verrou.lock()
	var m: StandardMaterial3D = _mats_funi.get(nom)
	RemonteeKit.verrou.unlock()
	if m != null:
		return m
	m = StandardMaterial3D.new()
	match nom:
		"lampe":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.97, 0.88)
			m.disable_fog = true
		"beton_clair":
			# poutre, piles (gris clair froid sur photo ; plus chaud, il virait au beige) : béton banché
			_matiere(m, _tex("beton_clair"), 2.5, 0.95)
		"beton_banche":
			_matiere(m, _tex("beton_banche"), 2.5, 0.95)
		"bois_gris":
			# bardage de bois gris patiné (gare aval) : lames verticales de 12 cm, veinées
			_matiere(m, _tex("bois_gris"), 0.96, 0.9)
		"bardage_anthracite":
			# bâtiment de Bellevarde : bac acier anthracite, nervures tous les 30 cm
			_matiere(m, _tex("bardage_anthracite"), 1.2, 0.55)
			m.metallic = 0.35
		"acier_galva":
			_matiere(m, _tex("acier_galva"), 0.6, 0.45)
			m.metallic = 0.65
		"caillebotis_sombre":
			m.albedo_color = Color(0.22, 0.23, 0.24)
			m.roughness = 0.75
			m.metallic = 0.4
		"caillebotis_galva":
			# marches des quais de La Daille : caillebotis galvanisé gris clair (vidéos de la montée et de la descente :
			# plats porteurs serrés, on voit au travers), une période tous les 0,36 m
			_matiere(m, _tex("caillebotis"), 0.36, 0.55)
			m.metallic = 0.55
		"rocher":
			_matiere(m, _tex("rocher"), 6.0, 1.0)
		"moellons":
			# maçonnerie de pierre grise (gare amont) : moellons irréguliers, joints de mortier clair
			_matiere(m, _tex("moellons"), 2.0, 1.0)
		"jour":
			# fenêtres vues de dedans : jour clair, sans lumière ni brouillard
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.86, 0.91, 0.97)
			m.disable_fog = true
		"verre_porte":
			m.albedo_color = Color(0.55, 0.62, 0.66, 0.30)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
			m.metallic_specular = 0.8
		"voyant_vert":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.1, 0.95, 0.3)
		"ardoise":
			# mur de plaquettes de pierre sombre du quai de Bellevarde (photos de l'utilisateur)
			_matiere(m, _tex("ardoise"), 1.4, 0.9)
		_:
			m.albedo_color = Color(1, 0, 1)
	RemonteeKit.verrou.lock()
	_mats_funi[nom] = m
	RemonteeKit.verrou.unlock()
	return m


## --- Matières procédurales (gares, viaduc, portail ; demande d'utilisateur du 08/11/2026 : « dessins grossiers par
## rapport au Perce-Neige ») : textures calculées, plaquées en triplanaire (les boîtes n'ont pas d'UV en mètres),
## une période de texture tous les `periode` m.
static func _matiere(m: StandardMaterial3D, tex: Texture2D, periode: float, rugosite: float) -> void:
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / periode
	m.roughness = rugosite
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## (calculées dans des tableaux d'octets : en set_pixel, les 7 textures prenaient 132 ms au PC — relevé du lot 19)
static func _bruit(graine: int, freq: float, taille: int) -> PackedByteArray:
	var fn: FastNoiseLite = FastNoiseLite.new()
	fn.seed = graine
	fn.frequency = freq
	fn.fractal_octaves = 4
	var img: Image = fn.get_seamless_image(taille, taille)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## Textures du Funival : recette (sorte, paramètres) par nom ; calculées une fois, gardées pour toutes les lignes.
const TEXTURES: Dictionary = {
	"beton_clair": ["beton", [Color(0.60, 0.63, 0.67), 11]],
	"beton_banche": ["beton", [Color(0.56, 0.57, 0.57), 23]],
	"bois_gris": ["lames", [Color(0.64, 0.62, 0.58), Color(0.30, 0.29, 0.27), 8, 0.12, 31]],
	"bardage_anthracite": ["lames", [Color(0.21, 0.22, 0.23), Color(0.09, 0.09, 0.10), 4, 0.06, 7]],
	"acier_galva": ["bruit", [Color(0.58, 0.60, 0.61), 0.06, 0.08, 5]],
	"rocher": ["bruit", [Color(0.40, 0.39, 0.37), 0.22, 0.02, 13]],
	"moellons": ["moellons", [Color(0.46, 0.47, 0.47), Color(0.66, 0.65, 0.62), 17]],
	"caillebotis": ["grille", [Color(0.66, 0.68, 0.69), Color(0.10, 0.10, 0.11), 12, 4, 0.30]],
	"ardoise": ["moellons", [Color(0.27, 0.27, 0.28), Color(0.12, 0.12, 0.13), 29]],
}
## Lignes de pixels par tranche quand on les calcule par bandes (256 lignes de moellons d'un bloc : 72 ms au NAS)
const BANDE_TEX: int = 32
static var _textures: Dictionary = {}


static func _tex(nom: String) -> ImageTexture:
	RemonteeKit.verrou.lock()
	var t: ImageTexture = _textures.get(nom)
	RemonteeKit.verrou.unlock()
	if t != null:
		return t
	var r: Array = _recette(nom)
	for e in r[2]:
		(e as Callable).call()
	var px: PackedByteArray = (r[1] as Callable).call(0, int(r[0]))
	return _garder(nom, int(r[0]), px)


## Les textures calculées par bandes de BANDE_TEX lignes, une pause entre deux (chemin sans fil, PWA).
static func cuire_textures(pause: Callable) -> void:
	for nom in TEXTURES:
		RemonteeKit.verrou.lock()
		var deja: bool = _textures.has(nom)
		RemonteeKit.verrou.unlock()
		if deja:
			continue
		var r: Array = _recette(nom)
		await pause.call()
		for e in r[2]:
			(e as Callable).call()
			await pause.call()
		var n: int = int(r[0])
		var px: PackedByteArray = PackedByteArray()
		var y: int = 0
		while y < n:
			px.append_array((r[1] as Callable).call(y, mini(y + BANDE_TEX, n)))
			y += BANDE_TEX
			await pause.call()
		_garder(nom, n, px)
		await pause.call()


static func _garder(nom: String, n: int, px: PackedByteArray) -> ImageTexture:
	var t: ImageTexture = _texture(n, px)
	RemonteeKit.verrou.lock()
	if _textures.has(nom):
		t = _textures[nom]
	else:
		_textures[nom] = t
	RemonteeKit.verrou.unlock()
	return t


## [taille, bande(y0, y1) → octets RGB des lignes y0 à y1 − 1, étapes préalables] ; les étapes s'appellent d'abord,
## puis les bandes dans l'ordre (tirages aléatoires en séquence).
static func _recette(nom: String) -> Array:
	var r: Array = TEXTURES[nom]
	var a: Array = r[1]
	match String(r[0]):
		"beton":
			return _r_beton(a[0], a[1]) + [[]]
		"lames":
			return _r_lames(a[0], a[1], a[2], a[3], a[4]) + [[]]
		"bruit":
			return _r_bruit(a[0], a[1], a[2], a[3]) + [[]]
		"grille":
			return _r_grille(a[0], a[1], a[2], a[3], a[4]) + [[]]
		_:
			return _r_moellons(a[0], a[1], a[2])


static func _texture(n: int, px: PackedByteArray) -> ImageTexture:
	var img: Image = Image.create_from_data(n, n, false, Image.FORMAT_RGB8, px)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _poser(px: PackedByteArray, i: int, c: Color, k: float) -> void:
	px[i * 3] = clampi(int(c.r * k * 255.0), 0, 255)
	px[i * 3 + 1] = clampi(int(c.g * k * 255.0), 0, 255)
	px[i * 3 + 2] = clampi(int(c.b * k * 255.0), 0, 255)


static func _bande(n: int, y0: int, y1: int) -> PackedByteArray:
	var px: PackedByteArray = PackedByteArray()
	px.resize((y1 - y0) * n * 3)
	return px


## Teinte bruitée : ±amp à grande échelle, ±grain au pixel.
static func _r_bruit(c: Color, amp: float, grain: float, graine: int) -> Array:
	var n: int = 128
	var b: PackedByteArray = _bruit(graine, 0.02, n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = graine
	return [n, func(y0: int, y1: int) -> PackedByteArray:
		var px: PackedByteArray = _bande(n, y0, y1)
		for i in range(y0 * n, y1 * n):
			_poser(px, i - y0 * n, c, 1.0 + (float(b[i]) / 255.0 - 0.5) * 2.0 * amp + rng.randf_range(-grain, grain))
		return px]


## Béton banché : nuances, banches de 2,5 × 1,25 m aux joints sombres, trous d'entretoise (une période = 2,5 m).
static func _r_beton(c: Color, graine: int) -> Array:
	var n: int = 256
	var b: PackedByteArray = _bruit(graine, 0.015, n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = graine
	return [n, func(y0: int, y1: int) -> PackedByteArray:
		var px: PackedByteArray = _bande(n, y0, y1)
		for y in range(y0, y1):
			for x in range(n):
				var i: int = y * n + x
				var k: float = 1.0 + (float(b[i]) / 255.0 - 0.5) * 0.14 + rng.randf_range(-0.03, 0.03)
				if y % 128 < 2 or x < 2:
					k *= 0.80                                   # joints de banche
				if absi((x + 32) % 64 - 32) < 2 and absi((y + 32) % 64 - 32) < 2:
					k *= 0.70                                   # trous d'entretoise
				_poser(px, i - y0 * n, c, k)
		return px]


## Lames verticales : n_lames par période, joint de la teinte `joint` sur la fraction `joint_f`, veinage léger.
static func _r_lames(c: Color, joint: Color, n_lames: int, joint_f: float, graine: int) -> Array:
	var n: int = 128
	var b: PackedByteArray = _bruit(graine, 0.05, n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = graine
	var teintes: Array = []
	for _i in range(n_lames):
		teintes.append(rng.randf_range(0.93, 1.06))
	var w: float = float(n) / float(n_lames)
	return [n, func(y0: int, y1: int) -> PackedByteArray:
		var px: PackedByteArray = _bande(n, y0, y1)
		for y in range(y0, y1):
			for x in range(n):
				var li: int = int(float(x) / w)
				if fmod(float(x), w) / w < joint_f:
					_poser(px, (y - y0) * n + x, joint, 1.0)
				else:
					_poser(px, (y - y0) * n + x, c, float(teintes[li]) * (1.0 + (float(b[y * n + li * 7 % n]) / 255.0 - 0.5) * 0.08))
		return px]


## Caillebotis : plats porteurs (nx par période) et entretoises (ny), vides sombres entre eux.
static func _r_grille(c: Color, vide: Color, nx: int, ny: int, f: float) -> Array:
	var n: int = 128
	var wx: float = float(n) / float(nx)
	var wy: float = float(n) / float(ny)
	return [n, func(y0: int, y1: int) -> PackedByteArray:
		var px: PackedByteArray = _bande(n, y0, y1)
		for y in range(y0, y1):
			var barre_y: bool = fmod(float(y), wy) / wy < f * 0.5
			for x in range(n):
				if barre_y or fmod(float(x), wx) / wx < f:
					_poser(px, (y - y0) * n + x, c, 1.0 - 0.10 * float(barre_y))
				else:
					_poser(px, (y - y0) * n + x, vide, 1.0)
		return px]


## Moellons : cellules de Voronoï, joints de mortier là où deux cellules se touchent (une période = 2 m). Les deux
## bruits cellulaires en deux étapes (16 ms chacun au NAS).
static func _r_moellons(c: Color, mortier: Color, graine: int) -> Array:
	var n: int = 256
	var bruits: Dictionary = {}
	var cellulaire := func(sorte: int, cle: String) -> void:
		var fn: FastNoiseLite = FastNoiseLite.new()
		fn.seed = graine
		fn.noise_type = FastNoiseLite.TYPE_CELLULAR
		fn.frequency = 0.035
		fn.cellular_return_type = sorte
		var im: Image = fn.get_seamless_image(n, n)
		im.convert(Image.FORMAT_L8)
		bruits[cle] = im.get_data()
	var etapes: Array = [cellulaire.bind(FastNoiseLite.RETURN_DISTANCE2_SUB, "j"), cellulaire.bind(FastNoiseLite.RETURN_CELL_VALUE, "v")]
	return [n, func(y0: int, y1: int) -> PackedByteArray:
		var j: PackedByteArray = bruits["j"]
		var v: PackedByteArray = bruits["v"]
		var px: PackedByteArray = _bande(n, y0, y1)
		for i in range(y0 * n, y1 * n):
			if j[i] < 15:
				_poser(px, i - y0 * n, mortier, 1.0)
			else:
				_poser(px, i - y0 * n, c, 0.80 + float(v[i]) / 255.0 * 0.40)
		return px, etapes]


## Habillage : les matières unies de RemonteeKit (partagées par toutes les lignes) remplacées, sur les pièces du
## Funival, par ses matières procédurales.
const HABILLAGE: Dictionary = {
	"remontee_peinture_anthracite": "bardage_anthracite",
	"remontee_beton": "beton_banche",
	"remontee_galva": "acier_galva",
	"remontee_galva_sombre": "acier_galva",
	"remontee_pierre": "moellons",
}


func _habiller(racine: Node) -> void:
	for mi in racine.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
			var me: Mesh = (mi as MeshInstance3D).mesh
			for k in range(me.get_surface_count()):
				var sm: Material = me.surface_get_material(k)
				if sm != null and HABILLAGE.has(sm.resource_name):
					(mi as MeshInstance3D).set_surface_override_material(k, mat_funi(HABILLAGE[sm.resource_name]))


## Éclairage cuit du tunnel en (d, angle autour de l'axe ; π = paroi gauche en montant) : un faible fond, et une
## flaque autour de chaque lampe, plus forte du côté des lampes.
func _lumiere_tunnel(d: float, cote_lampes: float) -> float:
	var k: float = fposmod(d - portail_d - 10.0, ECART_LAMPES)
	var dl: float = minf(k, ECART_LAMPES - k)
	var flaque: float = exp(-pow(dl / 5.5, 2.0))
	return 0.17 + flaque * (0.30 + 0.45 * clampf(cote_lampes, 0.0, 1.0))


## Teinte de la paroi : béton projeté gris-beige, tronçons de roche sombre, un tronçon à cintres et planches ocre.
## (Emplacements des tronçons ESTIMÉS : les photos les montrent sans dire où ils sont.)
func _teinte_paroi(d: float, k_anneau: int) -> Color:
	var L: float = longueur_h()
	var u: float = (d - portail_d) / (L - portail_d)
	if (u > 0.30 and u < 0.36) or (u > 0.72 and u < 0.80):
		return Color(0.42, 0.40, 0.37)                     # roche
	if u > 0.12 and u < 0.15:
		return Color(0.62, 0.45, 0.25) if k_anneau % 2 == 0 else Color(0.32, 0.24, 0.15)    # planches et cintres
	return Color(0.66, 0.58, 0.44)                          # béton projeté sous un éclairage chaud (vidéo de la montée)


# --- construction -----------------------------------------------------------------------

func construire() -> void:
	actif = self
	vitesse = V_FUNI
	await super.construire()


func _construire_corps() -> void:
	_preparer_voie()
	voie = 0.0
	H_CABLE_GARE = 0.0
	await _pause("funival : tracé")
	# textures calculées des matières (viaduc, portail, gares), par bandes : d'un bloc, 160 ms sans fil au NAS
	await cuire_textures(_pause.bind("funival : matières"))
	_voie_et_ouvrages()
	await _pause("funival : voie")
	await _tunnel()
	await _pause("funival : tunnel")
	_gare_aval()
	await _pause("funival : gare aval")
	await _gare_amont()
	_butoir_et_poulie()
	await _pause("funival : gare amont")
	# terrain de la gare amont (fil principal : il crée une pièce du relief)
	_amenager_relief_amont.call_deferred()
	_habiller(_chantier if _chantier != null else self)
	await _pause("funival : habillage")
	for k in range(2):
		var v: VehiculeFunival = VehiculeFunival.new()
		v.construit_par_la_ligne = true
		v.famille = famille
		v.numero = k + 1
		_enfant(v)
		await v.construire_par_tranches(_pause.bind("funival : véhicule"))
		_vehicules.append([v, 0.0])
		await _pause("funival : véhicule")
	_s = _x_quai(true)
	_maj_positions()
	if avec_collisions:
		_collisions_funi()
		await _pause("funival : collisions")
		for i in range(2):
			_corps_vehicule(i)


## Bande extrudée le long de la voie : profil (x, y) en travers, posé tous les `pas` m de d0 à d1. `teinte` (d, j) →
## couleur des sommets (matériau cuit), sinon blanc. `interieur` : faces tournées vers l'axe.
func _extruder(st: SurfaceTool, profil: PackedVector2Array, d0: float, d1: float, pas: float, i_voie: int = -1,
		ferme: bool = false, teinte: Callable = Callable(), interieur: bool = false) -> void:
	var n: int = maxi(1, int(ceil((d1 - d0) / pas)))
	var np: int = profil.size()
	var prec: PackedVector3Array = PackedVector3Array()
	var cprec: PackedColorArray = PackedColorArray()
	for k in range(n + 1):
		var d: float = d0 + (d1 - d0) * float(k) / float(n)
		var x0: float = x_voie(d, i_voie) if i_voie >= 0 else 0.0
		var y0: float = y_voie(d)
		var cour: PackedVector3Array = PackedVector3Array()
		var ccour: PackedColorArray = PackedColorArray()
		for j0 in range(np):
			var q: Vector2 = profil[j0]
			cour.append(Vector3(x0 + q.x, y0 + q.y, -d))
			ccour.append(teinte.call(d, j0) if teinte.is_valid() else Color.WHITE)
		if k > 0:
			for j in range(np - 1 + (1 if ferme else 0)):
				var j2: int = (j + 1) % np
				var tri: Array = [[prec[j], cprec[j]], [prec[j2], cprec[j2]], [cour[j2], ccour[j2]],
					[prec[j], cprec[j]], [cour[j2], ccour[j2]], [cour[j], ccour[j]]]
				if interieur:
					tri = [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]
				for e in tri:
					st.set_color(e[1])
					st.add_vertex(e[0])
		prec = cour
		cprec = ccour


func _maillage(st: SurfaceTool, m: Material, nom: String, ombre: bool = true) -> MeshInstance3D:
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.set_meta("portee_loin", true)       # (voie et tunnel : vus de loin, pas des détails à 250 m)
	mi.set_meta(MeshMerge.SANS_FUSION, true)
	# (pas de collision en maillage par CollisionsJeu : voie, tunnel et câbles hors d'atteinte ; gradins et salle
	# ont les leurs, en boîtes)
	mi.set_meta("sans_collision", true)
	if not ombre:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_enfant(mi)
	return mi


func _rail_profil(xr: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(xr - 0.035, -0.15), Vector2(xr - 0.035, 0.0), Vector2(xr + 0.035, 0.0),
		Vector2(xr + 0.035, -0.15)])


## --- Voie du Perce-Neige sur le tracé du Funival ---
## Dessus des rails sous l'axe du tube de TunnelBuilder (TrackBuilder : dalle −1,85 + 0,25, blochet 0,20 − 0,01,
## rail UIC 0,172).
const RAIL_SUR_CENTRE: float = 1.238
var _s_par_m: PackedFloat32Array = PackedFloat32Array()     # abscisse le long des rails, tous les 1 m en plan
var tunnel_pn: TunnelBuilder = null
var voie_pn: TrackBuilder = null
var lumieres_pn: TunnelLights = null


## (longueur de la courbe de l'axe du tube, décalée de RAIL_SUR_CENTRE sur la normale aux rails : c'est elle que
## TunnelBuilder paramètre ; celle des rails donnait jusqu'à 1,1 m d'écart le long de la voie)
func _table_s() -> void:
	var n: int = int(ceil(longueur_h())) + 3
	_s_par_m.resize(n)
	_s_par_m[0] = 0.0
	var prec: Vector2 = _axe_tube(0.0)
	for k in range(1, n):
		var q: Vector2 = _axe_tube(float(k))
		_s_par_m[k] = _s_par_m[k - 1] + q.distance_to(prec)
		prec = q


## Axe du tube au droit de la distance en plan d : (z, y) dans le repère de la ligne.
func _axe_tube(d: float) -> Vector2:
	var a: float = atan(pente_voie(d))
	return Vector2(-d + RAIL_SUR_CENTRE * sin(a), y_voie(d) + RAIL_SUR_CENTRE * cos(a))


## Abscisse le long des rails (TraceFuni, TrackBuilder) de la distance en plan d.
func s_de_d(d: float) -> float:
	var dc: float = clampf(d, 0.0, float(_s_par_m.size()) - 1.001)
	var k: int = int(dc)
	return lerpf(_s_par_m[k], _s_par_m[k + 1], dc - float(k))


func d_de_s(s: float) -> float:
	var k: int = clampi(_s_par_m.bsearch(s) - 1, 0, _s_par_m.size() - 2)
	var a: float = _s_par_m[k]
	var b: float = _s_par_m[k + 1]
	return float(k) + clampf((s - a) / maxf(b - a, 1e-6), 0.0, 1.0)


## Tracé du Funival pour TunnelBuilder et TrackBuilder : toute la ligne (le tube à partir du portail), droit en
## plan, profil de y_voie, évitement en une chambre sans mur, décalage des voies de x_voie.
func trace_voie() -> TraceFuni:
	var t: TraceFuni = TraceFuni.new()
	var L: float = longueur_h()
	t.perce_neige = false
	t.deux_tubes = false
	t.longueur = s_de_d(L)
	t.tube_debut = s_de_d(portail_d - 1.0)
	t.tube_fin = s_de_d(L - L_HALL + 1.0)          # (ensuite, la salle de Bellevarde)
	var c: float = L * 0.5
	var h: float = L_EVITEMENT * 0.5 + L_RACCORD
	t.evit_debut = s_de_d(c - h)
	t.evit_fin = s_de_d(c + h)
	t.decal_evitement = E_VOIES * 0.5
	t.elargissement_chambre = (R_TUNNEL_EVIT - R_TUNNEL) / (E_VOIES * 0.5)
	t.carre_bas_fin = t.tube_debut
	t.carre_haut_debut = s_de_d(L - L_HALL)
	t.miroir_s = s_de_d(_x_quai(true)) + s_de_d(_x_quai(false))
	t.attache_ds = VehiculeFunival.DEMI_L
	t.caisse_y = -RAIL_SUR_CENTRE + VehiculeFunival.Y_FOND      # (tirant du culot jusqu'au fond de caisse)
	# supports numérotés (relevé d'utilisateur du 08/11/2026) : 003 au bout du quai aval, côté amont ; 200 à l'entrée du
	# quai amont ; 204, le dernier avant la roue motrice, au bout du quai amont. 001 et 002 sur le quai aval, au pas du
	# quai amont (4 intervalles sur sa longueur).
	var lq: float = 2.0 * VehiculeFunival.DEMI_L + 2.0
	var s3: float = s_de_d(lq)
	var s200: float = s_de_d(L - lq)
	var s204: float = s_de_d(L - 1.0)
	var pas_q: float = (s204 - s200) / 4.0
	t.galets_reperes = [[1, s3 - 2.0 * pas_q], [3, s3], [200, s200], [204, s204]]
	t.galets_debut = s3 - 2.0 * pas_q
	t.galets_fin = s204
	t._decal = func(s: float) -> float: return E_VOIES * 0.5 * _t_evit(d_de_s(s))
	t._pente = func(s: float) -> float: return atan(pente_voie(d_de_s(s)))
	t._cap = func(_s: float) -> float: return 0.0
	# (longueur lue avant : capturer `t` dans sa propre lambda faisait un cycle jamais libéré — fuite, et plantage à
	# la fermeture sur le PC, bissection du 08/11/2026)
	var lg_t: float = t.longueur
	t._points = func(pas: float) -> Array:
		var pts: Array = []
		var n: int = int(lg_t / pas)
		for k in range(n + 1):
			var q: Vector2 = _axe_tube(d_de_s(float(k) * pas))
			pts.append(Vector3(0.0, q.y, q.x))
		# dernier point au bout exact (la courbe précuite est ramenée à trace.longueur : tronquée au pas, elle
		# étirait toute la voie)
		if lg_t - float(n) * pas > 0.01:
			var qf: Vector2 = _axe_tube(d_de_s(lg_t))
			pts.append(Vector3(0.0, qf.y, qf.x))
		return pts
	return t


## Voie et tunnel du Perce-Neige : vus de loin (pas des détails à 250 m), sans collision en maillage.
func _marquer_voie(n: Node) -> void:
	n.set_meta("portee_loin", true)
	n.set_meta(MeshMerge.SANS_FUSION, true)
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		c.set_meta("sans_collision", true)
		c.set_meta(MeshMerge.SANS_FUSION, true)


## Dehors : poutre en U de béton gris clair sur piles courtes à chevêtre, passerelle de service en caillebotis
## d'un côté, main courante. (Dans le tunnel, rails et radier sont dans le maillage cuit.)
func _voie_et_ouvrages() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# (rails, blochets, dalle et galets : TrackBuilder, dans _tunnel ; poutre plus profonde pour la fosse des galets)
	var u: PackedVector2Array = PackedVector2Array([Vector2(-1.75, 0.55), Vector2(-1.75, -1.3), Vector2(1.75, -1.3),
		Vector2(1.75, 0.55), Vector2(1.6, 0.55), Vector2(1.6, -1.15), Vector2(-1.6, -1.15), Vector2(-1.6, 0.55)])
	_extruder(st, u, 30.0, portail_d + 2.0, PAS_PROFIL, -1, true)
	_maillage(st, mat_funi("beton_clair"), "Poutre")
	# longrines sous les rails, du fond de la poutre au patin (photos : « deux rails sur longrines, pas de traverses
	# visibles à l'extérieur » ; les blochets du tunnel y faisaient de gros blocs noirs — retour d'utilisateur du 10/11/2026)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hr: float = 0.172 + 0.005
	for sxl in [-1.0, 1.0]:
		var xc: float = sxl * ECARTEMENT * 0.5
		_extruder(st, PackedVector2Array([Vector2(xc - 0.20, -hr), Vector2(xc - 0.24, -1.15), Vector2(xc + 0.24, -1.15),
			Vector2(xc + 0.20, -hr)]), 30.0, portail_d + 1.0, PAS_PROFIL, -1, true)
	_maillage(st, mat_funi("beton_banche"), "Longrines")
	var ouv: Node3D = Node3D.new()
	ouv.name = "Ouvrages"
	ouv.set_meta("portee_loin", true)
	_enfant(ouv)
	var d: float = 45.0
	while d < portail_d - 15.0:
		var y: float = y_voie(d) - 1.0
		var sol: float = _sol(0.0, -d)
		if y - sol > 0.2:
			# chevalet sombre : deux jambes fines écartées vers le bas, entretoise, chevêtre (photos)
			# en A franc : écart au pied ≈ moitié de la hauteur (photo), entretoises sur les hautes piles
			var h: float = y - sol + 0.6
			var e: float = maxf(0.9, h * 0.25)
			for sx in [-1.0, 1.0]:
				RemonteeKit.poutre(ouv, Vector3(sx * e, sol - 0.6, -d), Vector3(sx * 0.85, y - 0.4, -d), 0.32, 0.45, "peinture_anthracite")
			var n_e: int = 0 if h < 5.0 else (1 if h < 9.0 else 2)
			for ke in range(n_e):
				var fy: float = float(ke + 1) / float(n_e + 1)
				var ye: float = lerpf(sol - 0.6, y - 0.4, fy)
				var xe: float = lerpf(e, 0.85, fy)
				RemonteeKit.poutre(ouv, Vector3(-xe, ye, -d), Vector3(xe, ye, -d), 0.18, 0.25, "peinture_anthracite")
			RemonteeKit.boite_en(ouv, Vector3(2.6, 0.45, 0.8), Vector3(0, y - 0.22, -d), "peinture_anthracite")
		d += 18.0
	MeshMerge.merge(ouv, [], "Ouvrage")
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_extruder(st, PackedVector2Array([Vector2(1.75, 0.05), Vector2(2.55, 0.05), Vector2(2.55, -0.02), Vector2(1.75, -0.02)]),
		30.0, portail_d, 10.0)
	_maillage(st, RemonteeKit.mat("caillebotis"), "Passerelle")
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_extruder(st, PackedVector2Array([Vector2(2.52, 1.05), Vector2(2.56, 1.05), Vector2(2.56, 1.0), Vector2(2.52, 1.0)]),
		30.0, portail_d, 10.0)
	_maillage(st, RemonteeKit.mat("galva"), "MainCourante")


## Tunnel, vu de l'intérieur seulement (de dehors, sous la roche, rien) : paroi, radier, rails, passerelle et chemin
## de câbles à gauche, poulies entre les rails, lampes — tout dans un maillage cuit (sans éclairage, couleurs aux
## sommets). Section élargie dans l'évitement. Anneau de béton au portail, dans un front de rocher.
func _tunnel() -> void:
	var L: float = longueur_h()
	# tube, dalle, blochets, rails, galets numérotés, câble toronné : ceux du Perce-Neige (TunnelBuilder et
	# TrackBuilder sur le tracé du Funival, demande d'utilisateur du 08/11/2026 : « les mêmes rails, les mêmes
	# traverses, le même tunnel et les mêmes galets, avec toutes leurs fonctionnalités »)
	_table_s()
	var t: TraceFuni = trace_voie()
	tunnel_pn = TunnelBuilder.new()
	tunnel_pn.name = "TunnelPN"
	tunnel_pn.trace = t
	tunnel_pn.ring_spacing = 3.0
	tunnel_pn.ring_segments = 20
	tunnel_pn.tunnel_radius = R_TUNNEL
	tunnel_pn.passing_offset_max = E_VOIES * 0.5
	tunnel_pn.wall_cable_x_local = -(R_TUNNEL - 0.11)
	# câbles de paroi dans le seul tube : par défaut (bornes du Perce-Neige), ils flottaient au-dessus du viaduc et
	# traversaient en diagonale l'escalier de la salle amont
	tunnel_pn.station_low_end = t.tube_debut
	tunnel_pn.station_high_start = s_de_d(longueur_h() - L_HALL)
	# (hors de l'arbre : sur le fil de construction ; sans fil — PWA —, une pause par tronçon de tube)
	await tunnel_pn.build_par_etapes(_pause.bind("funival : tunnel"))
	voie_pn = TrackBuilder.new()
	voie_pn.name = "VoiePN"
	voie_pn.trace = t
	voie_pn.pit_low_end = 0.0
	voie_pn.pit_high_start = t.longueur
	voie_pn.walkway_side = -1.0            # passerelle-escalier à gauche en montant (vidéos)
	voie_pn.walkway_s0 = t.tube_debut
	voie_pn.sleepers_s0 = t.tube_debut          # (dehors : longrines, posées avec la poutre)
	voie_pn.walkway_s1 = s_de_d(L - L_HALL)     # (dans la salle amont, une lame blanche le long de la voie entre les escaliers)
	await voie_pn.build_par_etapes(tunnel_pn, _pause.bind("funival : voie"))
	# éclairage du Perce-Neige (TunnelLights : luminaires émissifs et lumières autour des véhicules), en hublots
	# chauds tous les ECART_LAMPES m sur la paroi gauche, à 1,7 m au-dessus des rails (vidéo de la montée) ; sans
	# lui, le tube était noir à ambiance égale (protocole du PC, 08/11/2026)
	lumieres_pn = TunnelLights.new()
	lumieres_pn.name = "TunnelLightsPN"
	lumieres_pn.spacing_m = ECART_LAMPES
	lumieres_pn.un_sur = 1
	lumieres_pn.neon_color = Color(1.0, 0.86, 0.62)
	lumieres_pn.neon_taille = Vector3(0.06, 0.20, 0.70)
	lumieres_pn.wall_offset = R_TUNNEL - 0.10
	lumieres_pn.height_offset = 1.7 - RAIL_SUR_CENTRE
	lumieres_pn.light_energy = 4.0          # (tous allumés : à 8 comme au PN, un sur deux, le tube était 1,8 fois plus clair)
	lumieres_pn.build(tunnel_pn)
	await _pause("funival : tunnel")
	for n in [tunnel_pn, voie_pn, lumieres_pn]:
		_marquer_voie(n)
		_enfant(n)
	await _pause("funival : tunnel")
	await _pause("funival : tunnel")
	# portail : front de rocher percé, anneau de béton en saillie (huit voussoirs)
	var por: Node3D = Node3D.new()
	por.name = "Portail"
	por.set_meta("portee_loin", true)
	_enfant(por)
	var yc: float = y_voie(portail_d) - 0.45 + R_TUNNEL * 0.62
	var pente: float = atan(pente_voie(portail_d))
	var rot: Basis = Basis(Vector3.RIGHT, pente)
	var c3: Vector3 = Vector3(0, yc, -portail_d)
	for k2 in range(10):
		var a2: float = PI * float(k2) / 9.0 - PI * 0.05
		var r2: float = R_TUNNEL + 0.35
		var pv: Vector3 = Vector3(cos(a2) * r2, sin(a2) * r2, 0.0)
		RemonteeKit.boite(por, Vector3(1.6, 0.7, 2.4), Transform3D(rot * Basis(Vector3.BACK, a2 + PI * 0.5), c3 + rot * pv),
			"beton")
	# front de rocher : blocs posés autour de l'anneau, enfoncés dans la pente (la falaise des photos ; le relief
	# du jeu reste lisse), teinte de roche sombre
	var roches: Array = []
	var blocs: Array = [[-4.6, 0.5, 6.0, 7.0, 0.25], [4.8, 0.2, 6.5, 6.5, -0.2], [-1.5, 4.6, 7.5, 4.0, 0.1], [2.8, 4.2, 6.0, 4.5, -0.15],
		[-7.5, -1.0, 5.0, 6.0, 0.4], [8.0, -1.2, 5.5, 5.5, -0.35]]
	for b0 in blocs:
		var mi_r: MeshInstance3D = RemonteeKit.boite(por, Vector3(b0[2], b0[3], 8.0),
			Transform3D(rot * Basis(Vector3.BACK, b0[4]) * Basis(Vector3.UP, b0[4] * 0.5), c3 + rot * Vector3(b0[0], b0[1], -4.2)), "pierre")
		mi_r.material_override = mat_funi("rocher")
		roches.append(mi_r)
	# boîte de béton du portail (photos : anneau « STVI » dans une boîte carrée) : couvre le tube sur 12 m là où la
	# roche est mince ; le tube n'a que des faces intérieures
	var lb: float = 12.0
	var cb: Vector3 = Vector3(0, y_voie(portail_d + lb * 0.5) - 0.45 + R_TUNNEL * 0.62, -(portail_d + lb * 0.5))
	var lgb: float = lb / cos(pente) + 0.2
	var cote: float = 2.0 * (R_TUNNEL + 0.7)
	for f in [[Vector3(cote, 0.5, lgb), Vector3(0, R_TUNNEL + 0.45, 0)], [Vector3(0.5, cote, lgb), Vector3(-(R_TUNNEL + 0.45), -0.35, 0)],
			[Vector3(0.5, cote, lgb), Vector3(R_TUNNEL + 0.45, -0.35, 0)]]:
		RemonteeKit.boite(por, f[0], Transform3D(rot, cb + rot * (f[1] as Vector3)), "beton")
	MeshMerge.merge(por, roches, "Portail")


const LARG_GRADINS: Array = [6.0, 3.5]     # gare aval : attente (gauche en montant), sortie (droite)
const LARG_AMONT: Array = [2.4, 4.0]       # gare amont : escaliers de béton des deux côtés (vidéos)
const MARCHE: float = 0.18                 # hauteur des petites marches entre paliers (0,15-0,20 m sur photo)
const GIRON: float = 0.28


## Gradins d'un côté de la gare aval, en boîtes [taille, centre] (repère de la ligne) : pour chaque compartiment,
## un palier au niveau de son plancher, devant la porte, et du côté aval une volée de petites marches qui monte du
## palier précédent (du sol pour le premier).
func _gradins(sx: float, rampes: bool = false, aval: bool = true) -> Array:
	var r: Array = []
	var dq: float = _x_quai(aval)
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = VehiculeFunival.l_comp()      # (pas des portes et des paliers du véhicule)
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	var larg: float = (LARG_GRADINS[0] if sx < 0.0 else LARG_GRADINS[1]) if aval else (LARG_AMONT[0] if sx < 0.0 else LARG_AMONT[1])
	var x: float = sx * (W + larg * 0.5)
	var y_prec: float = minf(_sol(x - larg * 0.4, -(dq - lq * 0.5)), _sol(x + larg * 0.4, -(dq - lq * 0.5)))
	if not aval:
		# salle amont : escalier de béton à PENTE CONSTANTE le long de la caisse (photos), du plancher du compartiment
		# du bas à celui du haut, prolongé jusqu'au bâtiment ; marches de MARCHE (ou une rampe pour les collisions)
		var d0: float = dq - lq * 0.5
		var d1: float = longueur_h() - 0.5
		var y0: float = VehiculeFunival.y_plancher_monde(self, dq - lq * 0.5 + lc * 0.5) - (lc * 0.5) * pente_voie(dq)
		var y1: float = VehiculeFunival.y_plancher_monde(self, longueur_h() - 1.0)
		if rampes:
			var lr: float = Vector2(d1 - d0, y1 - y0).length()
			var a0: float = atan2(y1 - y0, d1 - d0)
			var c0: Vector3 = Vector3(x, (y0 + y1) * 0.5, -(d0 + d1) * 0.5) + Vector3(0, -0.1 * cos(a0), -0.1 * sin(a0))
			r.append([Vector3(larg, 0.2, lr + 0.05), c0, a0])
			return r
		var nm: int = int(ceil((y1 - y0) / MARCHE))
		var giron: float = (d1 - d0) / float(nm)
		for j0 in range(nm):
			var haut0: float = y0 + (y1 - y0) * float(j0 + 1) / float(nm)
			var bas0: float = y0 + (y1 - y0) * float(j0) / float(nm) - 0.3
			r.append([Vector3(larg, haut0 - bas0, giron + 0.01), Vector3(x, (haut0 + bas0) * 0.5, -(d0 + giron * (float(j0) + 0.5)))])
		return r
	for k in range(n):
		var d: float = dq - VehiculeFunival.z_comp(k)
		var d_bas: float = d - lc * 0.5
		var y: float = VehiculeFunival.y_plancher_monde(self, d)
		if k == 0 and aval:
			# premier gradin : la volée part du sol AVANT le bout du quai, assez longue pour rester sous 30°
			var lf0: float = clampf(absf(y - y_prec) / 0.55, 0.5, 8.0)
			y_prec = minf(_sol(x - larg * 0.4, -(d_bas - lf0)), _sol(x + larg * 0.4, -(d_bas - lf0)))
			lf0 = clampf(absf(y - y_prec) / 0.55, 0.5, 8.0)
			d_bas -= lf0
		var h: float = y - y_prec
		var ns: int = clampi(int(ceil(absf(h) / MARCHE)), 0, 40)
		var lf: float = minf(float(ns) * GIRON, lc * 0.5 - 0.6)
		if k == 0 and aval:
			lf = d - lc * 0.5 - d_bas
		if rampes and ns > 0:
			# [taille, centre, angle] : dalle inclinée du palier précédent au palier du compartiment
			var lr: float = Vector2(lf, h).length()
			var a: float = atan2(h, lf)
			var c: Vector3 = Vector3(x, (y_prec + y) * 0.5, -(d_bas + lf * 0.5)) + Vector3(0, -0.1 * cos(a), -0.1 * sin(a))
			r.append([Vector3(larg, 0.2, lr + 0.05), c, a])
		else:
			for j in range(ns):
				var haut: float = y_prec + h * float(j + 1) / float(ns)
				var bas: float = minf(y_prec, haut) - 0.12
				var prof: float = lf / float(ns)
				r.append([Vector3(larg, haut - bas, prof + 0.01), Vector3(x, (haut + bas) * 0.5, -(d_bas + prof * (float(j) + 0.5)))])
		var lp: float = (d + lc * 0.5) - (d_bas + lf)
		r.append([Vector3(larg, 0.12, lp + 0.02), Vector3(x, y - 0.06, -(d_bas + lf + lp * 0.5))])
		y_prec = y
	return r


## Boîte ombrée dans un maillage cuit (sans éclairage) : dessus de la teinte c, faces en long un peu plus sombres,
## faces en travers (contremarches) plus sombres encore, dessous sombre — le relief se lit sans lumière.
static func _boite_ombree(st: SurfaceTool, taille: Vector3, c: Vector3, col: Color) -> void:
	var h: Vector3 = taille * 0.5
	var faces: Array = [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 0.86], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 0.86],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), 1.0], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.55],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), 0.70], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.80]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var k: float = f[3]
		st.set_color(Color(col.r * k, col.g * k, col.b * k))
		var o: Vector3 = c + nrm * h
		var du: Vector3 = u * h
		var dv: Vector3 = v * h
		var p: Array = [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for q in [p[0], p[2], p[1], p[0], p[3], p[2]]:
			st.add_vertex(q)


## Boîte pleine ajoutée à un SurfaceTool (six faces, sommets non partagés).
static func _boite_st(st: SurfaceTool, taille: Vector3, c: Vector3) -> void:
	var h: Vector3 = taille * 0.5
	var faces: Array = [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o: Vector3 = c + nrm * h
		var du: Vector3 = u * h
		var dv: Vector3 = v * h
		var p: Array = [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for q in [p[0], p[2], p[1], p[0], p[3], p[2]]:
			st.add_vertex(q)


## Gare aval (La Daille), à l'air libre : voie en fosse entre deux vastes quais en gradins de caillebotis sombre
## (attente à gauche en montant, sortie à droite), garde-corps en tubes ; bâtiment bas à toit plat débordant, bardé
## de bois gris patiné, enseigne « Funival », bornes de contrôle sous l'auvent.
func _gare_aval() -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAval"
	_enfant(g)
	var dq: float = _x_quai(true)
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = VehiculeFunival.l_comp()      # (pas des portes et des paliers du véhicule)
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	var bardage: Array = []
	# gradins : palier devant chaque porte, volée de petites marches de caillebotis entre deux paliers (photos)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stn: SurfaceTool = SurfaceTool.new()
	stn.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1.0, 1.0]:
		for b in _gradins(sx):
			_boite_st(st, b[0], b[1])
			# nez de marche : cornière claire au bord aval de chaque marche et palier (vidéos : arêtes blanches)
			var t: Vector3 = b[0]
			var c: Vector3 = b[1]
			_boite_st(stn, Vector3(t.x, 0.05, 0.06), Vector3(c.x, c.y + t.y * 0.5 - 0.02, c.z + t.z * 0.5 - 0.025))
	var gr: MeshInstance3D = _maillage(st, mat_funi("caillebotis_galva"), "Gradins")
	gr.reparent(g, false)          # (hors de l'arbre pendant la construction : pas de transformation globale)
	bardage.append(gr)
	var nz: MeshInstance3D = _maillage(stn, RemonteeKit.mat("cabine_blanche"), "NezMarches")
	nz.reparent(g, false)
	bardage.append(nz)
	for k in range(n):
		var d: float = dq - VehiculeFunival.z_comp(k)
		var y: float = VehiculeFunival.y_plancher_monde(self, d)
		for sx in [-1.0, 1.0]:
			var larg: float = LARG_GRADINS[0] if sx < 0.0 else LARG_GRADINS[1]
			var xg: float = sx * (W + larg - 0.05)
			RemonteeKit.boite_en(g, Vector3(0.05, 0.05, lc), Vector3(xg, y + 1.05, -d), "galva")
			RemonteeKit.boite_en(g, Vector3(0.05, 0.05, lc), Vector3(xg, y + 0.55, -d), "galva")
			RemonteeKit.boite_en(g, Vector3(0.05, 1.05, 0.05), Vector3(xg, y + 0.52, -d - lc * 0.5), "galva")
	# bâtiment : à gauche de l'entrée des quais, toit plat débordant
	var yb: float = VehiculeFunival.y_plancher_monde(self, 3.0)
	var zb: float = -(dq - lq * 0.5) + 6.0
	var xb: float = -(W + 6.0 + 7.5)
	RemonteeKit.boite_en(g, Vector3(15.0, 3.2, 11.0), Vector3(xb, yb + 1.6, zb), "beton")
	var bois: Material = mat_funi("bois_gris")
	for f in [[Vector3(15.1, 2.6, 0.06), Vector3(xb, yb + 1.9, zb + 5.53)], [Vector3(0.06, 2.6, 11.0), Vector3(xb - 7.53, yb + 1.9, zb)],
			[Vector3(0.06, 2.6, 11.0), Vector3(xb + 7.53, yb + 1.9, zb)]]:
		var mi: MeshInstance3D = RemonteeKit.boite_en(g, f[0], f[1], "beton")
		mi.material_override = bois
		bardage.append(mi)
	RemonteeKit.boite_en(g, Vector3(18.0, 0.35, 14.0), Vector3(xb, yb + 3.35, zb + 1.0), "peinture_anthracite")
	RemonteeKit.boite_en(g, Vector3(8.0, 1.2, 0.08), Vector3(xb + 2.0, yb + 1.4, zb + 5.6), "vitrage_sombre")
	for kb in range(5):
		RemonteeKit.boite_en(g, Vector3(0.25, 1.0, 0.5), Vector3(xb + 4.0 + kb * 1.0, yb + 0.5, zb + 7.5), "peinture_gris")
	var ens: MeshInstance3D = RemonteeKit.texte_fige(g, "Funival", 96, 0.012, Color(0.85, 0.86, 0.87))
	ens.position = Vector3(xb - 3.0, yb + 2.6, zb + 5.60)
	MeshMerge.merge(g, [ens] + bardage, "Gare")


## Butoir rouge au bout de la voie de la gare aval, poulie motrice bleue au bout de la salle amont (vidéo de la
## descente : grande roue bleue à pièces rouges derrière un garde-corps galvanisé).
func _butoir_et_poulie() -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareMachines"
	_enfant(g)
	RemonteeKit.boite_en(g, Vector3(1.8, 0.9, 0.7), Vector3(0, y_voie(0.3) + 0.45, -0.3), "rouge_val")
	var L: float = longueur_h()
	# poulie de renvoi en fosse au bout de la voie, sous le plancher du bâtiment : à 3,2 m au-dessus des rails, son
	# disque bleu sortait dans le bâtiment de surface, au milieu du pignon (PC, lot 16)
	# dressée dans le plan de la voie (axe transversal) : le câble arrive dans l'axe par-dessus et repart par-dessous
	# (remarque du PC, lot 17) ; centre 2,6 m au-delà du bout de la voie, sous le bâtiment, jeu ≥ 0,5 m avec le nez
	var yp: float = y_voie(L) - 2.2
	var zp: float = -(L + 2.4)
	var axe: Basis = Basis(Vector3.BACK, PI * 0.5)
	RemonteeKit.cylindre(g, 2.6, 2.6, 0.35, Transform3D(axe, Vector3(0, yp, zp)), "bleu_doppelmayr", 32)
	RemonteeKit.cylindre(g, 0.55, 0.55, 0.7, Transform3D(axe, Vector3(0, yp, zp)), "rouge_val", 16)
	for k in range(6):
		var a2: float = TAU * float(k) / 6.0
		RemonteeKit.boite(g, Vector3(0.2, 2.2, 0.22), Transform3D(Basis(Vector3.RIGHT, a2), Vector3(0.25, yp, zp) + Basis(Vector3.RIGHT, a2) * Vector3(0, 1.3, 0)), "bleu_doppelmayr")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.06, 1.1, 0.06), Vector3(sx * 2.8, y_voie(L) + 0.55, zp + 1.6), "galva")
	RemonteeKit.boite_en(g, Vector3(5.6, 0.05, 0.05), Vector3(0, y_voie(L) + 1.1, zp + 1.6), "galva")
	MeshMerge.merge(g, [], "Machines")


## Gare amont (Bellevarde) : la voie arrive dans une salle creusée sous le rocher (quai en escalier de béton d'un
## côté, escalier en caillebotis à rampe rouge de l'autre, plafond blanc, mur de pierre « WELCOME TO BELLEVARDE »),
## qui débouche en haut dans le bâtiment de surface : bardage anthracite, deux volumes à pignon, bandeau vitré,
## volume de pierre accolé. (Une pause entre les grandes pièces : d'un bloc, 68 ms sans fil au NAS.)
func _gare_amont() -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAmont"
	_enfant(g)
	var L: float = longueur_h()
	var dq: float = _x_quai(false)
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = VehiculeFunival.l_comp()      # (pas des portes et des paliers du véhicule)
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	# salle : boîte cuite vue de l'intérieur, de la fin du tunnel au bâtiment
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx: float = W + 4.2
	var salle: PackedVector2Array = PackedVector2Array([Vector2(hx, -0.6), Vector2(hx, 6.5), Vector2(-hx, 6.5), Vector2(-hx, -0.6)])
	var clair := func(_d: float, j: int) -> Color:
		return Color(0.80, 0.80, 0.78) if j == 1 or j == 2 else Color(0.62, 0.61, 0.58)
	_extruder(st, salle, L - L_HALL, L, 2.5, -1, false, clair, true)      # (fermée par le pignon du bâtiment, à L)
	# voile d'about : ferme la salle autour de la bouche du tube (on voyait le ciel et la neige autour — PC, lot 19).
	# Coupe verticale du tube incliné : ellipse de demi-axes R et R / cos(pente), centrée RAIL_SUR_CENTRE / cos au-dessus
	# des rails.
	var d0: float = L - L_HALL
	var a0: float = atan(pente_voie(d0))
	var y0r: float = y_voie(d0)
	var yc: float = y0r + RAIL_SUR_CENTRE / cos(a0)
	var rv: float = R_TUNNEL / cos(a0)
	var n_v: int = 40
	var bord := func(th: float) -> Vector2:
		var dx: float = cos(th)
		var dy: float = sin(th)
		var t: float = INF
		if absf(dx) > 1e-5:
			t = minf(t, hx / absf(dx))
		if dy > 1e-5:
			t = minf(t, (y0r + 6.5 - yc) / dy)
		elif dy < -1e-5:
			t = minf(t, (yc - (y0r - 0.6)) / -dy)
		return Vector2(dx * t, yc + dy * t)
	var dedans := func(th: float) -> Vector2:
		return Vector2(cos(th) * R_TUNNEL, maxf(yc + sin(th) * rv, y0r - 0.6))
	st.set_color(Color(0.62, 0.61, 0.58))
	for k in range(n_v):
		var th0: float = TAU * float(k) / float(n_v)
		var th1: float = TAU * float(k + 1) / float(n_v)
		var e0: Vector2 = bord.call(th0)
		var e1: Vector2 = bord.call(th1)
		var i0: Vector2 = dedans.call(th0)
		var i1: Vector2 = dedans.call(th1)
		for tri in [[i0, e0, e1], [i0, e1, i1], [i0, e1, e0], [i0, i1, e1]]:
			for v in tri:
				st.add_vertex(Vector3((v as Vector2).x, (v as Vector2).y, -d0))
	# (dalle, blochets et rails : TrackBuilder, jusqu'au bout de la voie)
	_maillage(st, mat_funi("cuit"), "SalleAmont", false)
	await _pause("funival : gare amont")
	# escaliers de béton clair des deux côtés, à pente constante (photos de l'utilisateur) : marches ombrées dans le
	# maillage cuit (dessus clair, contremarche plus sombre, nez de marche gris foncé — d'une seule teinte, on ne
	# distinguait pas les marches : « finesse du dessin ultra basique », 10/11/2026) ; le long de la voie, jupes rouges
	# à la pente de l'escalier (vidéos : voie bordée de rouge ; en marches d'un compartiment, elles faisaient des
	# dents de scie) ; plafond blanc à poutres en travers, poteaux noirs, main courante rouge (photos)
	var st2: SurfaceTool = SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e_d0: float = dq - lq * 0.5
	var e_d1: float = L - 0.5
	var e_y0: float = VehiculeFunival.y_plancher_monde(self, dq - lq * 0.5 + lc * 0.5) - (lc * 0.5) * pente_voie(dq)
	var e_y1: float = VehiculeFunival.y_plancher_monde(self, L - 1.0)
	var y_esc := func(d: float) -> float:
		return lerpf(e_y0, e_y1, clampf((d - e_d0) / (e_d1 - e_d0), 0.0, 1.0))
	# en haut à droite, le long du nez à quai : escalier en caillebotis galvanisé à rampe rouge (photo de l'utilisateur
	# « nez_escalier_metal »)
	var stc: SurfaceTool = SurfaceTool.new()
	stc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d_metal: float = L - 9.0
	for sx2 in [-1.0, 1.0]:
		var larg2: float = LARG_AMONT[0] if sx2 < 0.0 else LARG_AMONT[1]
		var xm: float = sx2 * (W + larg2 * 0.5)
		for b in _gradins(sx2, false, false):
			var t: Vector3 = b[0]
			var c: Vector3 = b[1]
			if sx2 > 0.0 and -c.z > d_metal:
				# marche de caillebotis mince sur limons, nez clair
				_boite_st(stc, Vector3(t.x, 0.05, t.z), Vector3(c.x, c.y + t.y * 0.5 - 0.025, c.z))
				_boite_ombree(st2, Vector3(t.x, 0.03, 0.04), Vector3(c.x, c.y + t.y * 0.5 - 0.01, c.z + t.z * 0.5 - 0.02), Color(0.85, 0.85, 0.83))
				continue
			_boite_ombree(st2, t, c, Color(0.78, 0.77, 0.74))
			# nez de marche : bande sombre au bord aval du giron
			_boite_ombree(st2, Vector3(t.x, 0.035, 0.05), Vector3(c.x, c.y + t.y * 0.5 - 0.012, c.z + t.z * 0.5 - 0.03), Color(0.36, 0.36, 0.35))
		# jupe rouge : du radier au bord de l'escalier, à sa pente
		var xj: float = sx2 * (W + 0.06)
		var dj: float = e_d0
		while dj < e_d1 - 0.01:
			var dj2: float = minf(dj + 2.0, e_d1)
			var q: Array = [Vector3(xj, y_voie(dj) - 0.4, -dj), Vector3(xj, y_esc.call(dj) - 0.02, -dj),
				Vector3(xj, y_esc.call(dj2) - 0.02, -dj2), Vector3(xj, y_voie(dj2) - 0.4, -dj2)]
			for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
				st2.set_color(Color(0.52, 0.07, 0.06))
				for iv in tri:
					st2.add_vertex(q[iv])
			dj = dj2
		# poteaux noirs contre le mur, tous les 6 m, de la marche au plafond
		var dp: float = e_d0 + 3.0
		while dp < e_d1 - 1.0:
			var yb2: float = y_esc.call(dp)
			var yh2: float = y_voie(dp) + 6.5
			RemonteeKit.boite_en(g, Vector3(0.35, yh2 - yb2, 0.35), Vector3(sx2 * (hx - 0.25), (yb2 + yh2) * 0.5, -dp), "peinture_anthracite")
			dp += 6.0
	# main courante rouge le long du mur droit, à 0,9 m de l'escalier, sur potelets tous les 3 m
	var xr: float = hx - 0.6
	RemonteeKit.poutre(g, Vector3(xr, e_y0 + 0.9, -e_d0), Vector3(xr, e_y1 + 0.9, -e_d1), 0.05, 0.05, "rouge_val")
	var dpo: float = e_d0 + 1.5
	while dpo < e_d1:
		RemonteeKit.boite_en(g, Vector3(0.04, 0.9, 0.04), Vector3(xr, y_esc.call(dpo) + 0.45, -dpo), "rouge_val")
		dpo += 3.0
	# dalle de béton gris sous les escaliers et devant la bouche du tube, de part et d'autre de la voie (le fond de la
	# salle paraissait blanc comme la neige)
	var dsl: float = L - L_HALL
	st2.set_color(Color(0.50, 0.50, 0.48))
	while dsl < L - 0.01:
		var dsl2: float = minf(dsl + 2.0, L)
		for sxs in [-1.0, 1.0]:
			var qs: Array = [Vector3(sxs * W, y_voie(dsl) - 0.4, -dsl), Vector3(sxs * hx, y_voie(dsl) - 0.4, -dsl),
				Vector3(sxs * hx, y_voie(dsl2) - 0.4, -dsl2), Vector3(sxs * W, y_voie(dsl2) - 0.4, -dsl2)]
			for iv in [0, 1, 2, 0, 2, 3]:
				st2.add_vertex(qs[iv])
		dsl = dsl2
	# poutres blanches du plafond, en travers, tous les 2,5 m (photos : plafond blanc à poutres)
	var dbp: float = L - L_HALL + 1.25
	while dbp < L:
		var yp: float = y_voie(dbp) + 6.5 - 0.30
		_boite_ombree(st2, Vector3(2.0 * hx, 0.55, 0.40), Vector3(0.0, yp, -dbp), Color(0.93, 0.93, 0.91))
		# tube d'éclairage sous une poutre sur deux
		if int((dbp - (L - L_HALL)) / 2.5) % 2 == 0:
			for sxl in [-1.0, 1.0]:
				_boite_ombree(st2, Vector3(1.6, 0.06, 0.10), Vector3(sxl * (W + 1.6), yp - 0.31, -dbp), Color(1.0, 0.98, 0.92))
		dbp += 2.5
	var esc: MeshInstance3D = _maillage(st2, mat_funi("cuit"), "EscaliersAmont", false)
	esc.reparent(g, false)
	var escm: MeshInstance3D = _maillage(stc, mat_funi("caillebotis_galva"), "EscalierMetal", false)
	escm.reparent(g, false)
	# limons de l'escalier métallique et rampe rouge côté véhicule, sur potelets
	var yq0: float = y_esc.call(d_metal)
	var yq1: float = y_esc.call(e_d1)
	for xl in [W + 0.08, W + LARG_AMONT[1] - 0.08]:
		RemonteeKit.poutre(g, Vector3(xl, yq0 - 0.25, -d_metal), Vector3(xl, yq1 - 0.25, -e_d1), 0.06, 0.25, "galva")
	var xv: float = W + 0.35
	RemonteeKit.poutre(g, Vector3(xv, yq0 + 1.0, -d_metal), Vector3(xv, yq1 + 1.0, -e_d1), 0.05, 0.05, "rouge_val")
	RemonteeKit.poutre(g, Vector3(xv, yq0 + 0.5, -d_metal), Vector3(xv, yq1 + 0.5, -e_d1), 0.04, 0.04, "rouge_val")
	var dpm: float = d_metal
	while dpm <= e_d1:
		RemonteeKit.boite_en(g, Vector3(0.05, 1.0, 0.05), Vector3(xv, y_esc.call(dpm) + 0.5, -dpm), "rouge_val")
		dpm += 2.2
	await _pause("funival : gare amont")
	# mur de pierre en plaquettes sombres sur tout le mur droit (photos : « WELCOME TO BELLEVARDE » en lettres
	# métalliques), et bannière « Respirez » suspendue au plafond au-dessus des portes
	var dm: float = dq
	var ym: float = VehiculeFunival.y_plancher_monde(self, dm)
	var d_m0: float = L - L_HALL + 2.0
	var p_m: float = (y_voie(L) - y_voie(d_m0)) / (L - d_m0)
	var mur_p: MeshInstance3D = RemonteeKit.boite(g, Vector3(0.25, 6.2, (L - d_m0) * sqrt(1.0 + p_m * p_m)),
		Transform3D(Basis(Vector3.RIGHT, atan(p_m)), Vector3(hx - 0.14, (y_voie(d_m0) + y_voie(L)) * 0.5 + 3.4, -(d_m0 + L) * 0.5)), "pierre")
	mur_p.material_override = mat_funi("ardoise")
	mur_p.set_meta(MeshMerge.SANS_FUSION, true)
	var w1: MeshInstance3D = RemonteeKit.texte_fige(g, "WELCOME TO BELLEVARDE", 64, 0.010, Color(0.80, 0.80, 0.78))
	w1.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hx - 0.30, ym + 2.8, -dm))
	# (au niveau du plafond EN CET ENDROIT : calée sur le milieu du quai, 9 m plus bas, elle traversait l'escalier)
	var db: float = dm + 6.0
	var yb3: float = y_voie(db) + 6.5 - 1.05
	var ban: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(0.03, 0.9, 6.0), Vector3(-(W + 0.35), yb3, -db), "crepi")
	ban.set_meta(MeshMerge.SANS_FUSION, true)
	var w2: MeshInstance3D = RemonteeKit.texte_fige(g, "Respirez, vous êtes à 2690 m !", 48, 0.008, Color(0.10, 0.10, 0.10))
	w2.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-(W + 0.37), yb3 + 0.15, -db))
	var w3: MeshInstance3D = RemonteeKit.texte_fige(g, "Breath, you are at 2690m!", 40, 0.006, Color(0.80, 0.08, 0.08))
	w3.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-(W + 0.37), yb3 - 0.2, -db))
	await _pause("funival : gare amont")
	# bâtiment de surface au débouché (photos ; ~38 m de long, estimé) : volume haut à pignon au-dessus de la salle,
	# bandeau de fenêtres sous le toit, aile basse à pignon, vitrage en bandeau au rez-de-chaussée, volume de pierre
	var ys: float = y_voie(L)
	var ys_sol: float = sol_batiment()
	_murs_bat.clear()
	var toits: Array = []
	# bâtiment creux (murs, plafond, toit) ; dans le pignon aval (+z), une baie de 3 m de haut au débouché de chaque
	# escalier et un trumeau plein devant la voie (captures du PC, lot 13 : la porte unique était dans l'axe de la
	# voie, les escaliers butaient sur le mur) ; murs avec collisions (_murs_bat), dalle au niveau du haut des escaliers
	var W2: float = W + 0.1
	var baies: Array = [[-(W + LARG_AMONT[0] + 0.2), -W2], [W2, W + LARG_AMONT[1] + 0.2]]
	var mur := func(taille: Vector3, centre: Vector3, mat: String, solide: bool) -> void:
		RemonteeKit.boite_en(g, taille, centre, mat)
		if solide:
			_murs_bat.append([taille, centre])
	# une face de mur le long de x (pignons) ou de z (long-pans), percée d'ouvertures [début, fin] de 3 m de haut
	var face := func(le_long_x: bool, fixe: float, a0: float, a1: float, ouv: Array, h: float, y0: float, mat: String, solide: bool) -> void:
		var ep: float = 0.3
		var seg := func(u0: float, u1: float, yb: float, yh: float) -> void:
			if u1 - u0 < 0.01 or yh - yb < 0.01:
				return
			var t: Vector3 = Vector3(u1 - u0, yh - yb, ep) if le_long_x else Vector3(ep, yh - yb, u1 - u0)
			var c: Vector3 = Vector3((u0 + u1) * 0.5, (yb + yh) * 0.5, fixe) if le_long_x else Vector3(fixe, (yb + yh) * 0.5, (u0 + u1) * 0.5)
			mur.call(t, c, mat, solide)
		var u: float = a0
		var ybaie: float = maxf(y0, ys_sol + 3.0)
		for o in ouv:
			seg.call(u, float(o[0]), y0, y0 + h)
			seg.call(float(o[0]), float(o[1]), ybaie, y0 + h)      # linteau
			u = float(o[1])
		seg.call(u, a1, y0, y0 + h)
	# porte : baies au débouché des escaliers dans le pignon aval (trumeau plein devant la voie), et deux portes vers
	# les pistes (pignon du fond, long-pan gauche) — sans elles on ne ressortait plus (PC, lot 14)
	var murs := func(cx: float, cz: float, larg: float, long_: float, h: float, y0: float, mat: String, porte: bool) -> void:
		var ep: float = 0.3
		var solide: bool = mat != "vitrage_sombre"
		var xg: float = cx - larg * 0.5
		var xd: float = cx + larg * 0.5
		var zf: float = cz + long_ * 0.5
		var zb: float = cz - long_ * 0.5
		var av: Array = []
		var fond: Array = []
		var gauche: Array = []
		if porte:
			for b2 in baies:
				av.append([cx + float(b2[0]), cx + float(b2[1])])
			fond = [[cx - 1.5, cx + 1.5]]
			gauche = [[cz - 1.5, cz + 1.5]]
		face.call(true, zf - ep * 0.5, xg, xd, av, h, y0, mat, solide)
		face.call(true, zb + ep * 0.5, xg, xd, fond, h, y0, mat, solide)
		face.call(false, xg + ep * 0.5, zb + ep, zf - ep, gauche, h, y0, mat, solide)
		face.call(false, xd - ep * 0.5, zb + ep, zf - ep, [], h, y0, mat, solide)
	var pignon := func(cx: float, cz: float, larg: float, long_: float, h: float, haut_toit: float, porte: bool) -> void:
		murs.call(cx, cz, larg, long_, h, ys - 0.5, "peinture_anthracite", porte)
		# grand bandeau vitré au rez-de-chaussée (photos ok-4 à ok-7 : ~1,6 m, cadres gris clair)
		murs.call(cx, cz, larg + 0.1, long_ + 0.1, 1.6, ys + 0.6, "vitrage_sombre", porte)
		RemonteeKit.boite_en(g, Vector3(larg, 0.25, long_), Vector3(cx, ys + h - 0.62, cz), "peinture_anthracite")   # plafond
		var a: float = atan2(haut_toit, larg * 0.5)
		var pan: float = sqrt(larg * larg * 0.25 + haut_toit * haut_toit) + 0.8
		for sx2 in [-1.0, 1.0]:
			var b_t: Basis = Basis(Vector3.BACK, -sx2 * a)
			var c_t: Vector3 = Vector3(cx + sx2 * larg * 0.25, ys + h - 0.5 + haut_toit * 0.5, cz)
			var mi_t: MeshInstance3D = RemonteeKit.boite(g, Vector3(pan, 0.22, long_ + 1.6), Transform3D(b_t, c_t), "galva_sombre")
			toits.append(mi_t)
			# neige sur le pan (photos d'hiver) et rive blanche au bas du pan
			RemonteeKit.boite(g, Vector3(pan - 0.5, 0.28, long_ + 1.2), Transform3D(b_t, c_t + b_t * Vector3(-sx2 * 0.15, 0.24, 0)), "neige_damee")
			RemonteeKit.boite(g, Vector3(0.12, 0.30, long_ + 1.6), Transform3D(b_t, c_t + b_t * Vector3(sx2 * pan * 0.5, -0.02, 0)), "cabine_blanche")
		# rives blanches des pignons
		for sz3 in [-1.0, 1.0]:
			for sx3 in [-1.0, 1.0]:
				RemonteeKit.boite(g, Vector3(sqrt(larg * larg * 0.25 + haut_toit * haut_toit) + 0.8, 0.30, 0.10), Transform3D(Basis(Vector3.BACK, -sx3 * a),
					Vector3(cx + sx3 * larg * 0.25, ys + h - 0.5 + haut_toit * 0.5, cz + sz3 * (long_ * 0.5 + 0.8))), "cabine_blanche")
		# pignons pleins (triangles approchés par deux boîtes)
		for sz2 in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(larg * 0.6, haut_toit * 0.6, 0.2), Vector3(cx, ys + h - 0.5 + haut_toit * 0.3, cz + sz2 * long_ * 0.5), "peinture_anthracite")
	# (au débouché de l'escalier : plus bas, son volume descendait dans la salle et faisait plafond sur le quai)
	# pignon aval 1 m au-delà du bout de la voie : le nez arrondi du véhicule à quai dépassait dans le bâtiment (PC, lot 14)
	var zs: float = -(L + 11.0)
	# dalle du rez-de-chaussée (le sol était la neige du relief)
	RemonteeKit.boite_en(g, Vector3(2.0 * hx + 1.4, 0.3, 21.7), Vector3(0, ys_sol - 0.15, zs), "beton")
	pignon.call(0.0, zs, 2.0 * hx + 2.0, 22.0, 8.0, 3.2, true)
	murs.call(0.0, zs, 2.0 * hx + 2.1, 22.1, 0.9, ys + 5.75, "vitrage_sombre", false)     # bandeau sous le toit
	pignon.call(hx + 7.0, zs - 12.0, 12.0, 16.0, 4.5, 2.2, false)
	# volume de pierre sur deux niveaux (photos ok-4, ok-5 : aussi haut que l'avant-toit du bâtiment)
	var moel: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(6.0, 5.6, 7.0), Vector3(-(hx + 4.0), ys + 2.3, zs + 6.0), "pierre")
	moel.material_override = mat_funi("moellons")
	moel.set_meta(MeshMerge.SANS_FUSION, true)
	var ens: MeshInstance3D = RemonteeKit.texte_fige(g, "Funival", 120, 0.016, Color(0.95, 0.95, 0.95))
	ens.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hx + 1.06, ys + 4.6, zs))
	var carre: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(0.05, 1.4, 1.4), Vector3(hx + 1.04, ys + 4.6, zs + 5.5), "rouge_val")
	carre.set_meta(MeshMerge.SANS_FUSION, true)
	await _pause("funival : gare amont")
	# perrons de béton devant les deux portes vers les pistes, jusqu'au terrain (porte du fond : 1,5 à 1,9 m de
	# marche, on ne pouvait plus rentrer — PC, lot 15)
	_perron_col.clear()
	var stp: SurfaceTool = SurfaceTool.new()
	stp.begin(Mesh.PRIMITIVE_TRIANGLES)
	_perron(stp, Vector3(0.0, ys_sol, zs - 11.0), Vector3(0, 0, -1), 3.4)
	_perron(stp, Vector3(-(hx + 1.0), ys_sol, zs), Vector3(-1, 0, 0), 3.4)
	var per: MeshInstance3D = _maillage(stp, mat_funi("cuit"), "Perrons", false)
	per.reparent(g, false)
	await _pause("funival : gare amont")
	var garder: Array = _amenager_batiment(g, ys, ys_sol, zs, hx, W)
	await _pause("funival : gare amont")
	MeshMerge.merge(g, [w1, w2, w3, ban, mur_p, ens, carre, moel, esc, escm] + garder, "Gare")


## Bâtiment de Bellevarde, dedans et aux portes (retour d'utilisateur du 11/11/2026 : « le design quand on quitte le
## quai pour traverser le bâtiment pour sortir dehors c'est 0 ») : d'après les photos du quai et de la fiche —
## soubassement clair, bandeaux de fenêtres, charpente métallique noire à contrefiches sous un plafond sombre, tubes
## lumineux, portes vitrées à cadre noir, portillons de contrôle pour la descente (à gauche ; la sortie reste libre à
## droite), râteliers à skis, bancs, panneaux Sortie / Descente ; dehors, marquises et enseignes au-dessus des portes,
## volume de pierre couvert avec sa porte. Rend les textes, à garder hors de la fusion.
func _amenager_batiment(g: Node3D, ys: float, ys_sol: float, zs: float, hx: float, W: float) -> Array:
	var garder: Array = []
	var xi: float = hx + 1.0 - 0.32            # face intérieure des longs-pans
	var zf: float = zs - 11.0 + 0.32           # face intérieure du pignon du fond (sortie)
	var za: float = zs + 11.0 - 0.32           # face intérieure du pignon aval (escaliers)
	var y0: float = ys_sol
	var jour: Material = mat_funi("jour")
	var lampe: Material = mat_funi("lampe")
	var b := func(t: Vector3, c: Vector3, m: String) -> MeshInstance3D:
		return RemonteeKit.boite_en(g, t, c, m)
	var bm := func(t: Vector3, c: Vector3, m: Material) -> void:
		var mi: MeshInstance3D = RemonteeKit.boite_en(g, t, c, "crepi")
		mi.material_override = m
		mi.set_meta(MeshMerge.SANS_FUSION, true)
		garder.append(mi)
	# murs : segments [début, fin] le long de chaque face, ouvertures ôtées
	var faces: Array = [
		[true, zf, -xi, xi, [[-1.7, 1.7]], 1.0],                                   # fond, porte de sortie
		[true, za, -xi, xi, [[-(W + LARG_AMONT[0] + 0.3), W + LARG_AMONT[1] + 0.3]], -1.0],   # aval, débouché des escaliers
		[false, -xi, zf, za, [[zs - 1.7, zs + 1.7]], 1.0],                         # long-pan gauche, porte
		[false, xi, zf, za, [], -1.0]]
	for f in faces:
		var lx: bool = f[0]
		var fixe: float = f[1]
		var u: float = f[2]
		var trous: Array = f[4]
		var nrm: float = f[5]
		var segs: Array = []
		for o in trous:
			segs.append([u, float(o[0])])
			u = float(o[1])
		segs.append([u, f[3]])
		for sg in segs:
			var u0: float = sg[0]
			var u1: float = sg[1]
			if u1 - u0 < 0.1:
				continue
			var um: float = (u0 + u1) * 0.5
			var lu: float = u1 - u0
			var pos := func(y: float, off: float) -> Vector3:
				return Vector3(um, y, fixe + nrm * off) if lx else Vector3(fixe + nrm * off, y, um)
			var tl := func(h: float, e: float) -> Vector3:
				return Vector3(lu, h, e) if lx else Vector3(e, h, lu)
			# plinthe noire, fenêtres basses (jour), soubassement clair au-dessus jusqu'à 3 m, bandeau haut (jour)
			b.call(tl.call(0.12, 0.03), pos.call(y0 + 0.06, 0.03), "noir_mat")
			bm.call(tl.call(1.5, 0.02), pos.call(y0 + 0.85, 0.02), jour)
			b.call(tl.call(1.3, 0.03), pos.call(y0 + 2.3, 0.03), "crepi")
			b.call(tl.call(0.06, 0.05), pos.call(y0 + 1.62, 0.05), "acier_noir")
			bm.call(tl.call(0.8, 0.02), pos.call(ys + 6.2, 0.02), jour)
			# montants des fenêtres, tous les 1,5 m
			var k: float = u0 + 0.75
			while k < u1 - 0.3:
				var pm: Vector3 = Vector3(k, 0, fixe + nrm * 0.04) if lx else Vector3(fixe + nrm * 0.04, 0, k)
				b.call(Vector3(0.06, 1.5, 0.05) if lx else Vector3(0.05, 1.5, 0.06), pm + Vector3(0, y0 + 0.85, 0), "acier_noir")
				b.call(Vector3(0.06, 0.8, 0.05) if lx else Vector3(0.05, 0.8, 0.06), pm + Vector3(0, ys + 6.2, 0), "acier_noir")
				k += 1.5
	# charpente : poutres en travers tous les 3 m sous le plafond, contrefiches vers les murs, tubes lumineux
	var yp: float = ys + 7.38 - 0.13
	var zc: float = zs - 9.5
	while zc < zs + 10.0:
		b.call(Vector3(2.0 * xi, 0.40, 0.20), Vector3(0, yp - 0.20, zc), "acier_noir")
		for sxc in [-1.0, 1.0]:
			RemonteeKit.poutre(g, Vector3(sxc * (xi - 0.1), ys + 5.4, zc), Vector3(sxc * (xi - 2.0), yp - 0.35, zc), 0.12, 0.12, "acier_noir")
			bm.call(Vector3(1.4, 0.05, 0.12), Vector3(sxc * 3.0, yp - 0.45, zc), lampe)
		zc += 3.0
	for sxl in [-1.0, 0.0, 1.0]:
		b.call(Vector3(0.12, 0.25, 21.0), Vector3(sxl * (xi - 3.5), yp - 0.55, zs), "acier_noir")     # pannes
	# sol : chemin de sortie en caoutchouc noir, des escaliers aux deux portes
	b.call(Vector3(3.0, 0.02, 21.0), Vector3(0, y0 + 0.01, zs), "toit_bardeaux")
	b.call(Vector3(xi, 0.02, 3.0), Vector3(-xi * 0.5, y0 + 0.012, zs), "toit_bardeaux")
	# portes vitrées à cadre noir (ouvertes : cadres, imposte et vantaux repliés contre les tableaux)
	var porte := func(c: Vector3, le_long_x: bool, larg: float) -> void:
		var ax: Vector3 = Vector3.RIGHT if le_long_x else Vector3.BACK
		for sp in [-1.0, 1.0]:
			b.call(Vector3(0.10, 3.0, 0.10), c + ax * (sp * larg * 0.5) + Vector3(0, 1.5, 0), "acier_noir")
			# vantail ouvert, perpendiculaire au mur
			var nv: Vector3 = Vector3.BACK if le_long_x else Vector3.RIGHT
			var cv: Vector3 = c + ax * (sp * (larg * 0.5 - 0.05)) + nv * 0.48 + Vector3(0, 1.1, 0)
			b.call((Vector3(0.05, 2.2, 0.9) if le_long_x else Vector3(0.9, 2.2, 0.05)), cv, "acier_noir")
			bm.call((Vector3(0.02, 1.9, 0.75) if le_long_x else Vector3(0.75, 1.9, 0.02)), cv, mat_funi("verre_porte"))
		b.call((Vector3(larg, 0.12, 0.12) if le_long_x else Vector3(0.12, 0.12, larg)), c + Vector3(0, 2.25, 0), "acier_noir")
	porte.call(Vector3(0, y0, zf - 0.15), true, 3.0)
	porte.call(Vector3(-xi + 0.15, y0, zs), false, 3.0)
	# portillons de contrôle pour la descente, à gauche en allant vers les escaliers ; couloirs à lisses galvanisées
	var zp: float = zs + 6.5
	for kp in range(5):
		var xp: float = -xi + 1.2 + float(kp) * 1.15
		b.call(Vector3(0.28, 1.0, 0.55), Vector3(xp, y0 + 0.5, zp), "peinture_gris")
		b.call(Vector3(0.20, 0.14, 0.02), Vector3(xp, y0 + 0.92, zp - 0.28), "noir_mat")
		bm.call(Vector3(0.05, 0.05, 0.02), Vector3(xp + 0.07, y0 + 1.03, zp - 0.28), mat_funi("voyant_vert"))
		RemonteeKit.poutre(g, Vector3(xp + 0.14, y0 + 0.85, zp - 0.05), Vector3(xp + 0.60, y0 + 0.85, zp - 0.05), 0.03, 0.03, "galva")
		b.call(Vector3(0.05, 1.0, 2.6), Vector3(xp - 0.45, y0 + 0.5, zp + 1.0), "galva")
	# panneaux suspendus : « Sortie / Exit » au-dessus des portes, « Descente / Way down » vers les escaliers
	var panneau := func(texte: String, c: Vector3, rot: float, fond: String, coul: Color, larg: float) -> void:
		var pb: MeshInstance3D = RemonteeKit.boite(g, Vector3(larg, 0.45, 0.04), Transform3D(Basis(Vector3.UP, rot), c), fond)
		pb.set_meta(MeshMerge.SANS_FUSION, true)
		garder.append(pb)
		var tx: MeshInstance3D = RemonteeKit.texte_fige(g, texte, 48, 0.0055, coul)
		tx.transform = Transform3D(Basis(Vector3.UP, rot), c + Basis(Vector3.UP, rot) * Vector3(0, -0.02, 0.03))
		garder.append(tx)
	panneau.call("SORTIE  ·  EXIT", Vector3(0, y0 + 2.9, zf + 0.3), 0.0, "vert_sortie", Color(0.97, 0.97, 0.97), 2.4)
	panneau.call("SORTIE  ·  EXIT", Vector3(-xi + 0.3, y0 + 2.9, zs), PI * 0.5, "vert_sortie", Color(0.97, 0.97, 0.97), 2.4)
	panneau.call("DESCENTE  ·  WAY DOWN", Vector3(-(W + 1.4), y0 + 3.3, za - 0.4), PI, "plaque_bleue", Color(0.97, 0.97, 0.97), 3.0)
	var logo: MeshInstance3D = RemonteeKit.texte_fige(g, "Funival", 120, 0.014, Color(0.93, 0.93, 0.93))
	logo.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(xi - 0.05, y0 + 3.7, zs))
	garder.append(logo)
	var alt: MeshInstance3D = RemonteeKit.texte_fige(g, "Rocher de Bellevarde · 2690 m", 48, 0.006, Color(0.80, 0.08, 0.08))
	alt.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(xi - 0.05, y0 + 3.0, zs))
	garder.append(alt)
	# râteliers à skis de part et d'autre de la porte de sortie, bancs contre le mur droit
	for sxr in [-1.0, 1.0]:
		var xr0: float = sxr * 3.2
		b.call(Vector3(2.6, 0.05, 0.05), Vector3(xr0, y0 + 1.15, zf + 0.6), "galva")
		b.call(Vector3(2.6, 0.05, 0.05), Vector3(xr0, y0 + 0.45, zf + 0.6), "galva")
		for kr in range(9):
			b.call(Vector3(0.03, 1.2, 0.03), Vector3(xr0 - 1.2 + kr * 0.3, y0 + 0.6, zf + 0.6), "galva")
	for zbn in [zs - 6.0, zs - 1.0]:
		b.call(Vector3(0.45, 0.07, 2.2), Vector3(xi - 0.35, y0 + 0.46, zbn), "bois_meleze")
		for dzb in [-0.9, 0.9]:
			b.call(Vector3(0.40, 0.42, 0.06), Vector3(xi - 0.35, y0 + 0.21, zbn + dzb), "acier_noir")
	# extincteurs
	for ze in [zs + 9.5, zs - 9.5]:
		b.call(Vector3(0.16, 0.5, 0.16), Vector3(-xi + 0.12, y0 + 1.05, ze), "rouge_val")
	# dehors : marquises et enseignes au-dessus des portes, lampes
	b.call(Vector3(5.0, 0.16, 2.2), Vector3(0, y0 + 3.45, zs - 11.0 - 1.1), "peinture_anthracite")
	b.call(Vector3(2.2, 0.16, 5.0), Vector3(-(hx + 1.0) - 1.1, y0 + 3.45, zs), "peinture_anthracite")
	var ext1: MeshInstance3D = RemonteeKit.texte_fige(g, "DESCENTE  ·  WAY DOWN", 64, 0.008, Color(0.95, 0.95, 0.95))
	ext1.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, y0 + 4.1, zs - 11.0 - 0.17))
	garder.append(ext1)
	var ext2: MeshInstance3D = RemonteeKit.texte_fige(g, "DESCENTE  ·  WAY DOWN", 64, 0.008, Color(0.95, 0.95, 0.95))
	ext2.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-(hx + 1.0) - 0.17, y0 + 4.1, zs))
	garder.append(ext2)
	for xl in [-2.0, 2.0]:
		bm.call(Vector3(0.3, 0.06, 0.3), Vector3(xl, y0 + 3.36, zs - 11.0 - 1.6), lampe)
	# volume de pierre : toit à deux pans à forte avancée, rives de bois, porte sombre, petite fenêtre (photos)
	var xv: float = -(hx + 4.0)
	for svt in [-1.0, 1.0]:
		var bvt: Basis = Basis(Vector3.RIGHT, svt * 0.38)
		RemonteeKit.boite(g, Vector3(7.0, 0.2, 4.6), Transform3D(bvt, Vector3(xv, ys + 5.85, zs + 6.0 + svt * 1.95)), "galva_sombre")
		RemonteeKit.boite(g, Vector3(6.4, 0.25, 4.0), Transform3D(bvt, Vector3(xv, ys + 6.05, zs + 6.0 + svt * 1.85)), "neige_damee")
		RemonteeKit.boite(g, Vector3(7.1, 0.25, 0.12), Transform3D(bvt, Vector3(xv, ys + 5.8, zs + 6.0 + svt * 4.2)), "bois_fonce")
	b.call(Vector3(0.06, 2.3, 1.2), Vector3(xv - 3.03, y0 + 1.15, zs + 6.0), "acier_noir")
	b.call(Vector3(0.06, 0.9, 0.9), Vector3(xv - 3.03, y0 + 3.4, zs + 7.8), "vitrage_sombre")
	# cadres gris clair du bandeau vitré, dehors, tous les 1,2 m (longs-pans et pignon du fond, portes ôtées)
	var xe: float = hx + 1.0 + 0.10
	for sxe in [-1.0, 1.0]:
		var zk: float = zs - 10.4
		while zk < zs + 10.6:
			if not (sxe < 0.0 and absf(zk - zs) < 1.8):
				b.call(Vector3(0.07, 1.6, 0.08), Vector3(sxe * xe, ys + 1.4, zk), "galva")
			zk += 1.2
		b.call(Vector3(0.08, 0.08, 21.6), Vector3(sxe * xe, ys + 2.2, zs), "galva")
	var xk: float = -(hx + 0.4)
	while xk < hx + 0.6:
		if absf(xk) > 1.8:
			b.call(Vector3(0.08, 1.6, 0.07), Vector3(xk, ys + 1.4, zs - 11.0 - 0.10), "galva")
		xk += 1.2
	# skis posés contre la façade près de la porte du fond (ok-7)
	for ks in range(7):
		var xs2: float = 2.6 + float(ks) * 0.35
		RemonteeKit.boite(g, Vector3(0.08, 1.75, 0.02), Transform3D(Basis(Vector3.RIGHT, -0.22) * Basis(Vector3.BACK, (float(ks % 3) - 1.0) * 0.06),
			Vector3(xs2, y0 + 0.86, zs - 11.0 - 0.38)), ["rouge_val", "noir_mat", "cabine_blanche", "bleu_doppelmayr"][ks % 4])
	return garder


## Terrain de la gare amont (remarques d'utilisateur, iPad du 08/11/2026 : « en gare du haut une plaque grise coupe
## la gare en deux », « le bâtiment de la gare supérieure est en lévitation totale ») : au sommet, le relief n'est qu'à
## 4,6 m au-dessus du quai pour une salle de 6,5 m de haut, et descend à 3,7 m sous le plancher du bâtiment. Une pièce
## fine du relief (ReliefBuilder) : terrain raboté sous le plancher de la salle là où elle sort du sol (elle est alors
## habillée de bardage), remonté au niveau du plancher autour du bâtiment.
func _amenager_relief_amont() -> void:
	var rel: ReliefBuilder = relief_trous
	if rel == null or not is_instance_valid(rel) or not is_inside_tree() or rel.has_meta("funival_amont"):
		return
	rel.set_meta("funival_amont", true)
	var xf: Transform3D = global_transform
	var monde := func(pts: Array) -> PackedVector2Array:
		var out: PackedVector2Array = PackedVector2Array()
		for v in pts:
			var w: Vector3 = xf * Vector3((v as Vector2).x, 0.0, (v as Vector2).y)
			out.append(Vector2(w.x, w.z))
		return out
	var rect := func(cx: float, cz: float, lx: float, lz: float) -> Array:
		return [Vector2(cx - lx * 0.5, cz - lz * 0.5), Vector2(cx + lx * 0.5, cz - lz * 0.5),
			Vector2(cx + lx * 0.5, cz + lz * 0.5), Vector2(cx - lx * 0.5, cz + lz * 0.5)]
	var L: float = longueur_h()
	var hx: float = VehiculeFunival.DEMI_LARGEUR + 0.05 + 4.2
	var zs: float = -(L + 11.0)
	var y0: float = xf.origin.y
	# salle rasée sur TOUTE sa longueur, couverte par son habillage (retour d'utilisateur du 10/11/2026 : « sur le quai
	# amont sans cabine, les rails s'arrêtent à l'entrée du tunnel, on voit rien après ») : rasée seulement là où elle
	# sortait du terrain, le relief, champ de hauteurs, redescendait du dessus du plafond au-dessous du plancher en
	# travers de la salle, mur de neige à 16 m de la bouche du tube. La marche est maintenant au voile d'about, derrière
	# lui, et l'habillage monte jusqu'au terrain d'origine (relevé ici avant le rabotage).
	var rabots: Array = []
	_haut_orig.clear()
	var d: float = L - L_HALL
	while d < L - 0.01:
		var d2: float = minf(d + 4.0, L)
		var dm: float = (d + d2) * 0.5
		var h_max: float = -INF
		for sx in [-1.0, 0.0, 1.0]:
			for dd in [d, d2]:
				var c: Vector3 = xf * Vector3(sx * (hx + 2.6), 0.0, -dd)
				h_max = maxf(h_max, rel.hauteur_sol(c.x, c.z) - y0)
		_haut_orig.append(h_max)
		# (jusque sous les murs épais de l'habillage : plus étroit, les triangles du relief entre sommets rasés et non
		# rasés pointaient dans la salle, pointes de neige le long des parois)
		rabots.append([monde.call(rect.call(0.0, -dm, 2.0 * hx + 5.0, d2 - d)), y0 + y_voie(d) - 1.0, 2.0])
		d = d2
	_salle_emerge_d = L - L_HALL
	var bat: Array = [rect.call(0.0, zs, 2.0 * hx + 3.0, 23.0), rect.call(hx + 7.0, zs - 12.0, 13.0, 17.0),
		rect.call(-(hx + 4.0), zs + 6.0, 7.0, 8.0)]
	var remblais: Array = []
	# trou au-dessus de la bouche du tube : le talus du rabotage, de la salle rasée au terrain d'origine, traversait
	# le tube et le bouchait (vu du quai : un disque de neige) ; caché dessus par la dalle de l'habillage
	# (de 3,4 m sous la bouche à 3 m dans la salle : la grille du relief, 2 m alignés sur le monde et non sur la
	# ligne, a des triangles qui portent le talus jusqu'à 2,8 m plus loin — pointes de neige devant la bouche)
	var trous: Array = [monde.call(rect.call(0.0, -(L - L_HALL - 0.2), 2.0 * hx + 9.0, 6.4))]
	for r2 in bat:
		remblais.append([monde.call(r2), y0 + sol_batiment() - 0.05, 10.0])
	var bb: Rect2 = Rect2()
	var prem: bool = true
	for r3 in rabots.map(func(x): return x[0]) + remblais.map(func(x): return x[0]):
		for v in r3:
			if prem:
				bb = Rect2(v, Vector2.ZERO)
				prem = false
			else:
				bb = bb.expand(v)
	rel._build_piece({"rect": bb.grow(14.0), "trous": trous, "remblais": remblais, "rabots": rabots})
	rel._poser_trous()
	_habiller_salle()


## Début (d) de la partie de la salle amont qui sort du terrain (INF : enterrée).
var _salle_emerge_d: float = INF
## Terrain d'origine (le plus haut, sur l'emprise élargie de 2,6 m) au-dessus de chaque tranche de 4 m de la salle,
## en hauteur de la ligne, relevé avant le rabotage.
var _haut_orig: Array = []


## Habillage de la salle amont là où elle sort du terrain : murs et toit de bardage anthracite, comme le bâtiment.
func _habiller_salle() -> void:
	if _salle_emerge_d == INF:
		return
	var L: float = longueur_h()
	var hx: float = VehiculeFunival.DEMI_LARGEUR + 0.05 + 4.2
	var d0: float = L - L_HALL
	var g: Node3D = Node3D.new()
	g.name = "HabillageSalle"
	add_child(g)
	var bard: Material = mat_funi("bardage_anthracite")
	var beton: Material = mat_funi("beton_banche")
	# par tranches de 4 m qui suivent la voie (d'un bloc, le toit plongeait dans la salle où la pente change) ; la
	# première déborde de 4 m vers l'aval sur le tube (trou du relief au-dessus de sa bouche, talus du rabotage).
	# Murs épais de 2,4 m (ils couvrent le talus du rabotage) et toit montés jusqu'au terrain d'origine : bardage là
	# où la salle sort du sol, béton là où elle était enterrée.
	var d: float = d0 - 4.0
	while d < L - 0.01:
		var d2: float = minf(d + 4.0, L) if d >= d0 else d0 + 2.0
		var dm: float = (d + d2) * 0.5
		var p: float = (y_voie(d2) - y_voie(d)) / (d2 - d)
		var b_p: Basis = Basis(Vector3.RIGHT, atan(p))
		var lg_t: float = (d2 - d) * sqrt(1.0 + p * p) + 0.05
		var yv: float = y_voie(dm)
		var h_o: float = float(_haut_orig[clampi(int((dm - d0) / 4.0), 0, _haut_orig.size() - 1)]) if not _haut_orig.is_empty() else -INF
		var haut: float = maxf(yv + 7.05, h_o + 0.3)
		var enterre: bool = h_o > yv + 7.6
		var pieces: Array = []
		for sx in [-1.0, 1.0]:
			pieces.append(RemonteeKit.boite(g, Vector3(2.4, haut - (yv - 1.55), lg_t), Transform3D(b_p, Vector3(sx * (hx + 1.45), (haut + yv - 1.55) * 0.5, -dm)), "beton"))
		var h_toit: float = maxf(0.35, haut - (yv + 6.78))
		pieces.append(RemonteeKit.boite(g, Vector3(2.0 * hx + 5.2, h_toit, lg_t), Transform3D(b_p, Vector3(0, yv + 6.78 + h_toit * 0.5, -dm)), "beton"))
		for mi in pieces:
			(mi as MeshInstance3D).material_override = beton if enterre else bard
		d = d2
	MeshMerge.merge(g, [], "HabillageSalle")


## Perron d'une porte : marches de 0,18 × 0,30 m depuis le seuil (repère de la ligne) dans la direction dir
## (horizontale, selon un axe), jusqu'au terrain ; les blocs descendent sous le sol. Collisions : les marches et une
## rampe inclinée par-dessus (le giron est plus court que le pas du skieur, comme aux gradins).
func _perron(st: SurfaceTool, seuil: Vector3, dir: Vector3, larg: float) -> void:
	var rise: float = 0.18
	var run: float = 0.30
	var lat: Vector3 = Vector3(dir.z, 0.0, -dir.x)
	var axe: Vector3 = Vector3(absf(dir.x), 0.0, absf(dir.z))
	var axe_l: Vector3 = Vector3(absf(lat.x), 0.0, absf(lat.z))
	var n: int = 0
	for k in range(1, 30):
		var top: float = seuil.y - rise * float(k)
		var c: Vector3 = seuil + dir * (run * (float(k) - 0.5))
		var t: float = maxf(_sol(c.x + lat.x * larg * 0.5, c.z + lat.z * larg * 0.5), _sol(c.x - lat.x * larg * 0.5, c.z - lat.z * larg * 0.5))
		if top < t - 0.02:
			break
		var bas: float = minf(t, top) - 0.6
		var taille: Vector3 = axe * run + axe_l * larg + Vector3(0, top - bas, 0)
		var centre: Vector3 = Vector3(c.x, (top + bas) * 0.5, c.z)
		st.set_color(Color(0.74, 0.73, 0.70))
		_boite_st(st, taille, centre)
		_perron_col.append([taille, Transform3D(Basis(), centre)])
		n = k
	if n == 0:
		return
	var fin: Vector3 = seuil + dir * (run * float(n)) - Vector3(0, rise * float(n), 0)
	var f: Vector3 = (fin - seuil).normalized()
	var y_ax: Vector3 = f.cross(lat)
	# (pas de débord côté seuil : relevée par la pente, la rampe y faisait une bordure de 0,1 m où l'on butait)
	var lg: float = seuil.distance_to(fin) + 0.3
	_perron_col.append([Vector3(larg, 0.1, lg), Transform3D(Basis(lat, y_ax, f), (seuil + fin) * 0.5 + f * 0.15 - y_ax * 0.06)])


func _collisions_funi() -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsLigne"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR | COUCHE_SOUTERRAIN
	corps.collision_mask = 0
	_enfant(corps)
	var boite := func(taille: Vector3, centre: Vector3) -> void:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var bx: BoxShape3D = BoxShape3D.new()
		bx.size = taille
		cs.shape = bx
		cs.position = centre
		corps.add_child(cs)
	var L: float = longueur_h()
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = VehiculeFunival.l_comp()      # (pas des portes et des paliers du véhicule)
	for aval in [true, false]:
		var dq: float = _x_quai(aval)
		for k in range(n):
			var d: float = dq - VehiculeFunival.z_comp(k)
			var y: float = VehiculeFunival.y_plancher_monde(self, d)
			if not aval:
				# jupe le long de la voie (on ne glisse pas sous le véhicule)
				for sxj in [-1.0, 1.0]:
					boite.call(Vector3(0.1, 2.5, lc + 0.05), Vector3(sxj * (W + 0.02), y - 1.3, -d))
	for sx4 in [-1.0, 1.0]:
		for b in _gradins(sx4, true, false):
			if b.size() > 2:
				var cs2: CollisionShape3D = CollisionShape3D.new()
				var bx2: BoxShape3D = BoxShape3D.new()
				bx2.size = b[0]
				cs2.shape = bx2
				cs2.transform = Transform3D(Basis(Vector3.RIGHT, b[2]), b[1])
				corps.add_child(cs2)
			else:
				boite.call(b[0], b[1])
	for sx3 in [-1.0, 1.0]:
		for b in _gradins(sx3, true):
			if b.size() > 2:
				# rampe sous une volée (les marches de 0,18 m ont un giron plus court que le pas du skieur)
				var cs: CollisionShape3D = CollisionShape3D.new()
				var bx: BoxShape3D = BoxShape3D.new()
				bx.size = b[0]
				cs.shape = bx
				cs.transform = Transform3D(Basis(Vector3.RIGHT, b[2]), b[1])
				corps.add_child(cs)
			else:
				boite.call(b[0], b[1])
		# garde-corps extérieur et jupe côté fosse, sur toute la longueur des gradins
		var larg3: float = LARG_GRADINS[0] if sx3 < 0.0 else LARG_GRADINS[1]
		var dq3: float = _x_quai(true)
		for k3 in range(n):
			var d3: float = dq3 - VehiculeFunival.z_comp(k3)
			var y3: float = VehiculeFunival.y_plancher_monde(self, d3)
			# garde-corps : du sol au-dessus de la main courante (on passait dessous depuis une volée)
			var xg3: float = sx3 * (W + larg3 - 0.05)
			var sol3: float = minf(_sol(xg3, -(d3 - lc * 0.5)), _sol(xg3, -(d3 + lc * 0.5))) - 0.5
			boite.call(Vector3(0.3, y3 + 1.1 - sol3, lc + 0.05), Vector3(xg3 + sx3 * 0.1, (y3 + 1.1 + sol3) * 0.5, -d3))
			boite.call(Vector3(0.1, 2.5, lc + 0.05), Vector3(sx3 * (W + 0.02), y3 - 1.3, -d3))
	# tunnel : parois pour la caméra seule (à la 3e personne, elle sortait du tube et filmait le relief par-dessous —
	# capture WebKit du 08/11/2026) ; tronçons de 30 m suivant la pente, plus larges dans l'évitement
	var cam: StaticBody3D = StaticBody3D.new()
	cam.name = "CameraTunnel"
	cam.collision_layer = CollisionsJeu.COUCHE_CAMERA
	cam.collision_mask = 0
	_enfant(cam)
	var dt: float = portail_d + 2.0
	while dt < L - 2.0:
		var dt2: float = minf(dt + 30.0, L - 2.0)
		var ya: float = y_voie(dt)
		var yb2: float = y_voie(dt2)
		var a5: float = atan2(yb2 - ya, dt2 - dt)
		var lg5: float = Vector2(dt2 - dt, yb2 - ya).length() + 0.5
		var tm: float = maxf(_t_evit(dt), _t_evit(dt2))
		var rx5: float = lerpf(R_TUNNEL, R_TUNNEL_EVIT, tm) - 0.15
		var ry5: float = lerpf(R_TUNNEL, R_TUNNEL * 1.2, tm)
		var c5: Vector3 = Vector3(0, (ya + yb2) * 0.5, -(dt + dt2) * 0.5)
		var rot5: Basis = Basis(Vector3.RIGHT, a5)
		var hmur: float = ry5 * 1.6 + 0.5
		for f5 in [[Vector3(0.3, hmur, lg5), Vector3(-rx5 - 0.15, hmur * 0.5 - 0.5, 0)], [Vector3(0.3, hmur, lg5), Vector3(rx5 + 0.15, hmur * 0.5 - 0.5, 0)],
				[Vector3(2.0 * rx5 + 0.6, 0.3, lg5), Vector3(0, -0.45 + ry5 * 1.62 + 0.15, 0)],
				# plancher : à 48 %, la caméra placée derrière le skieur passait sous le radier (capture WebKit)
				[Vector3(2.0 * rx5 + 0.6, 0.3, lg5), Vector3(0, -0.65, 0)]]:
			var cs5: CollisionShape3D = CollisionShape3D.new()
			var bx5: BoxShape3D = BoxShape3D.new()
			bx5.size = f5[0]
			cs5.shape = bx5
			cs5.transform = Transform3D(rot5, c5 + rot5 * (f5[1] as Vector3))
			cam.add_child(cs5)
		dt = dt2
	# salle amont : parois, et plancher du bâtiment au débouché
	var hx: float = W + 4.2
	for sx in [-1.0, 1.0]:
		var dmil: float = L - L_HALL * 0.5
		boite.call(Vector3(0.4, 14.0, L_HALL), Vector3(sx * (hx + 0.2), y_voie(dmil) + 3.0, -dmil))
	boite.call(Vector3(2.0 * hx + 1.4, 0.4, 22.6), Vector3(0, sol_batiment() - 0.2, -(L + 10.5)))     # (de L − 0,8 à L + 21,8 ; le bâtiment va de L à L + 22)
	for m in _murs_bat:
		boite.call(m[0], m[1])
	for pc in _perron_col:
		var csp: CollisionShape3D = CollisionShape3D.new()
		var bxp: BoxShape3D = BoxShape3D.new()
		bxp.size = pc[0]
		csp.shape = bxp
		csp.transform = pc[1]
		corps.add_child(csp)


## Véhicule sur sa voie, incliné comme elle ; portes et collisions des parois.
func _placer(i: int) -> void:
	var v: VehiculeRemontee = _vehicules[i][0]
	var d: float = _vehicules[i][1]
	var p: Vector3 = Vector3(x_voie(d, i), y_voie(d), -d)
	var a: float = atan(pente_voie(d))
	var b: Basis = Basis(Vector3.RIGHT, a)
	v.transform = Transform3D(b, p)
	var porte: float = 0.0
	if _phase == "quai" and zone_vehicule(i) != "ligne":
		porte = clampf(minf(T_QUAI - _t_quai, _t_quai) / 1.5, 0.0, 1.0)
	v.portes(porte)
	(v as VehiculeFunival).tourner_roues(s_de_d(d) if not _s_par_m.is_empty() else d)
	# phares vers l'avant du mouvement ; à quai, vers la ligne
	var monte: bool = (_v * (1.0 if i == 0 else -1.0)) > 0.05 or (absf(_v) <= 0.05 and zone_vehicule(i) == "gare_aval")
	(v as VehiculeFunival).phares(monte, zone_vehicule(i) == "ligne" or absf(_v) <= 0.05)
	if collisions_actives and i < _corps.size() and _corps[i] != null:
		(_corps[i][0] as Node3D).transform = Transform3D(b, p)
		for cs in _corps[i][1]:
			(cs as CollisionShape3D).disabled = porte > 0.5


## Le Funival du domaine (un seul) : main._skieur_en_tunnel l'interroge pour masquer le relief quand la caméra est
## dans son tube ou sa salle amont (couverture d'une dizaine de mètres : le relief grossier de la PWA traversait le
## tube — capture WebKit du 08/11/2026).
static var actif: Funival = null


## Dans le souterrain (salle amont, dont le haut est à moins de 2 m sous la surface : le terrain descend vers la gare
## quand la voie monte), le relief faisait plafond sur l'escalier : le corps du skieur l'ignore tant qu'il y est
## (l'escalier et la salle ont leurs collisions ; le relief y est déjà masqué à l'écran).
var _relief_ote: bool = false
var _masque_avant: int = 0
## Couche propre aux collisions du Funival (quais, escaliers, salle) : dans le souterrain, le corps du skieur ne voit
## qu'elle et les véhicules — le relief, et les pièces fines du terrain des gares (corps Decor), y faisaient plafond.
const COUCHE_SOUTERRAIN: int = 64


func _maj_corps_skieur() -> void:
	if not is_inside_tree():
		return
	# (scène principale : current_scene en jeu ; dans les bancs, ajoutée à la racine sous le nom « Main »)
	var mn: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root.get_node_or_null("Main")
	var sk: Node = mn.get("skieur") if mn != null else null
	if sk == null or not (sk is CharacterBody3D):
		return
	var dedans: bool = souterrain((sk as Node3D).global_position)
	var cb: CharacterBody3D = sk
	_garde_plancher(cb)
	_masquer_voisines()
	if dedans and not _relief_ote:
		_masque_avant = cb.collision_mask
		cb.collision_mask = COUCHE_SOUTERRAIN | CollisionsJeu.COUCHE_VEHICULE
		_relief_ote = true
	elif not dedans and _relief_ote:
		cb.collision_mask = _masque_avant
		_relief_ote = false


var _t_quai_tot: float = 0.0


## Skieur qui marche dans une gare (quais, escaliers) ou dans un véhicule à quai.
func _skieur_marche_en_gare() -> bool:
	if not is_inside_tree():
		return false
	var mn: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root.get_node_or_null("Main")
	var sk: Node = mn.get("skieur") if mn != null else null
	if sk == null or not (sk is CharacterBody3D):
		return false
	var cb: CharacterBody3D = sk
	if Vector2(cb.velocity.x, cb.velocity.z).length() < 0.3:
		return false
	var loc: Vector3 = global_transform.affine_inverse() * cb.global_position
	var d: float = -loc.z
	var lq: float = VehiculeFunival.DEMI_L + 8.0
	for aval in [true, false]:
		if absf(d - _x_quai(aval)) < lq and absf(loc.x) < 12.0 and absf(loc.y - y_voie(clampf(d, 0.0, longueur_h()))) < 8.0:
			return true
	return false


## À bord (on y marche librement, porté comme dans le Perce-Neige) : dans la caisse d'un véhicule, le skieur a toujours
## ce véhicule pour support dès qu'il roule, et n'en traverse jamais le plancher (à 12 m/s, un à-coup d'images sur iPad
## suffisait — essai du 08/11/2026).
func _garde_plancher(cb: CharacterBody3D) -> void:
	if not collisions_actives or not cb.get("actif"):
		return
	for i in range(mini(_corps.size(), _vehicules.size())):
		if _corps[i] == null:
			continue
		var v: VehiculeFunival = _vehicules[i][0]
		var loc: Vector3 = v.global_transform.affine_inverse() * cb.global_position
		if absf(loc.x) > VehiculeFunival.DEMI_LARGEUR - 0.02 or absf(loc.z) > VehiculeFunival.DEMI_L - 0.2:
			continue
		var y_pl: float = VehiculeFunival.y_plancher(loc.z)
		if loc.y < y_pl - 1.5 or loc.y > y_pl + 3.0:
			continue
		if loc.y < y_pl - 0.25:
			loc.y = y_pl + 0.03
			cb.global_position = v.global_transform * loc
			cb.velocity = Vector3.ZERO
		var corps: Node3D = _corps[i][0]
		if absf(_v) > 0.01 and cb.get("support") != corps:
			cb.set("support", corps)
			cb.set("_support_xf", corps.global_transform)
		return


## Caméra dans le souterrain : le relief y est masqué (main._skieur_en_tunnel), pas les gares des lignes voisines : celle
## de l'arrivée du Marmottes Express, au-dessus de la salle, la coupait en deux (« une plaque grise », iPad 08-09/11/2026).
var _voisines_cachees: Array = []


func _masquer_voisines() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var sous: bool = cam != null and souterrain(cam.global_position)
	if sous == not _voisines_cachees.is_empty() or get_parent() == null:
		return
	if sous:
		for n in get_parent().get_children():
			if n != self and n is Node3D and (n as Node3D).visible:
				(n as Node3D).visible = false
				_voisines_cachees.append(n)
	else:
		for n2 in _voisines_cachees:
			if is_instance_valid(n2):
				(n2 as Node3D).visible = true
		_voisines_cachees.clear()


## Caméra sous la roche (masque le relief) : pas dans la partie de la salle qui sort du versant, dont le terrain est raboté
## sous le plancher — sinon le décor disparaissait en sortant par le haut des escaliers (09/11/2026).
func sous_la_roche(p: Vector3) -> bool:
	if not souterrain(p):
		return false
	return -(global_transform.affine_inverse() * p).z < _salle_emerge_d + 2.0


## Le point p (monde) est dans la caisse d'un véhicule : le skieur y est porté, la ligne doit tourner à pleine cadence, collisions comprises.
func skieur_dedans(p: Vector3) -> bool:
	if not pret:
		return false
	for e in _vehicules:
		var loc: Vector3 = (e[0] as Node3D).global_transform.affine_inverse() * p
		if absf(loc.x) < VehiculeFunival.DEMI_LARGEUR + 0.1 and absf(loc.z) < VehiculeFunival.DEMI_L and loc.y > 0.0 and loc.y < VehiculeFunival.H_TOIT:
			return true
	return false


func souterrain(p: Vector3) -> bool:
	if not pret or not is_inside_tree():
		return false
	var loc: Vector3 = global_transform.affine_inverse() * p
	var d: float = -loc.z
	var demi: float = lerpf(R_TUNNEL, R_TUNNEL_EVIT, _t_evit(d)) + 3.0
	if d > longueur_h() - L_HALL - 2.0:
		demi = VehiculeFunival.DEMI_LARGEUR + 0.05 + 4.2 + 1.0       # salle amont, murs compris
	return d > portail_d + 3.0 and d < longueur_h() + 1.0 and absf(loc.x) < demi and absf(loc.y - y_voie(d) - 1.0) < 8.0


## Mouvement : celui du téléphérique, mais la vitesse s'entend LE LONG DE LA VOIE (12 m/s sur une pente de 27 à 48 %) ;
## d avance de v·cos(pente).
func _process_corps(delta: float) -> void:
	if not pret:
		return
	delta = _tic_lod(delta)
	if delta < 0.0:
		return
	_dt = delta
	var but: float = _x_quai(false) if _sens > 0.0 else _x_quai(true)
	if _phase == "quai":
		_v = 0.0
		vitesse_reelle = 0.0
		if etat == "marche":
			_t_quai_tot += delta
			# (portes encore ouvertes et skieur qui marche à quai ou à bord : on l'attend)
			if not (_t_quai - delta < 2.0 and _t_quai_tot < T_QUAI_MAX and _skieur_marche_en_gare()):
				_t_quai -= delta
			if _t_quai <= 0.0:
				_phase = "route"
				_t_quai_tot = 0.0
	else:
		var v_max: float = vitesse * CRANS[cran]
		# évitement : on y entre à V_EVIT, freinage anticipé (les deux véhicules y entrent ensemble)
		var c_ev: float = longueur_h() * 0.5
		# (tant qu'une partie du véhicule est sur les aiguillages)
		var h_ev: float = L_EVITEMENT * 0.5 + L_RACCORD + VehiculeFunival.DEMI_L
		var hors: float = maxf(absf(_s - c_ev) - h_ev, 0.0) * sqrt(1.0 + pow(pente_voie(_s), 2.0))
		var vers: bool = (_s < c_ev) == (_sens > 0.0) or hors <= 0.0
		if vers:
			v_max = minf(v_max, sqrt(V_EVIT * V_EVIT + 2.0 * A_FUNI * hors))
		# distance restante le long de la voie : freinage jusqu'à V_QUAI au début du quai (nez du véhicule), au pas le long
		# du quai, accostage au dernier mètre
		var k_p: float = sqrt(1.0 + pow(pente_voie(_s), 2.0))
		var reste: float = absf(but - _s) * k_p
		var avant_quai: float = maxf(absf(but - _s) - longueur_quai_nez(), 0.0) * k_p
		var v_gare: float = sqrt(V_QUAI * V_QUAI + 2.0 * A_FUNI * K_COURBE * avant_quai)
		v_gare = minf(v_gare, maxf(sqrt(2.0 * A_ACCOSTAGE * maxf(reste - 0.05, 0.0)), 0.12))
		v_max = minf(v_max, v_gare)
		if etat != "marche":
			v_max = 0.0
		var a_frein: float = A_URGENCE if etat == "urgence" else A_FUNI
		var va: float = absf(_v)
		va = move_toward(va, v_max, (A_FUNI if v_max > va else a_frein) * delta)
		_v = va * _sens
		_s += _v * delta / sqrt(1.0 + pow(pente_voie(_s), 2.0))
		if (_sens > 0.0 and _s >= but) or (_sens < 0.0 and _s <= but):
			_s = but
			_v = 0.0
			_phase = "quai"
			_t_quai = T_QUAI
			_sens = -_sens
		if etat == "arret_normal" and va <= 0.0:
			etat = "arret"
	vitesse_reelle = absf(_v)
	_maj_positions()
	_maj_corps_skieur()
	_dt = 0.0


## Câbles, d'après le principe du funiculaire à deux véhicules (et la remarque de l'utilisateur du 08/11/2026 : un
## petit câble de retour à l'aval, qui empêche l'élasticité du câble) : le tracteur va du bout amont de chaque
## véhicule à la poulie motrice de la gare amont ; le câble inférieur, plus fin, du bout aval de chaque véhicule à
## la poulie de tension de la gare aval. Ils courent sur les poulies entre les rails ; au-dessus du véhicule du
## haut, deux brins du tracteur côte à côte, sous celui du bas, deux brins du câble inférieur.
## Refaits quand un véhicule a avancé de plus de 3 m (deux maillages, une centaine de sommets).
var _cables: MeshInstance3D = null
var _d_cables: float = -1000.0
var _mat_cables: StandardMaterial3D = null
const D_TRACTEUR: float = 0.052        # diamètre (estimé ; non publié)
## Attache du câble inférieur sous le châssis (au-dessus des rails, estimé) et paramètre de sa chaînette T/w : ~15 kN
## sur ~2,6 kg/m (25 mm), estimés.
const H_ATTACHE_INF: float = 0.12
const A_CHAINETTE_INF: float = 600.0
const D_INFERIEUR: float = 0.025       # câble tracteur aval 25 mm, 42 870 daN, Tréfileurope 1987 (funiculaires-france.fr)


func _maj_positions() -> void:
	super._maj_positions()
	_maj_voie_pn(_dt)
	if absf(_s - _d_cables) > 3.0:
		_d_cables = _s
		_refaire_cables()


## Câble tracteur et galets du Perce-Neige : brins coupés à l'attache de chaque véhicule (nez amont), torons qui
## défilent, galets qui tournent autour de la caméra.
func _maj_voie_pn(delta: float) -> void:
	if voie_pn == null or _s_par_m.is_empty() or _vehicules.size() < 2:
		return
	var s0: float = s_de_d(_vehicules[0][1])
	var s1: float = s_de_d(_vehicules[1][1])
	if lumieres_pn != null:
		lumieres_pn.update_light_culling(s0, NAN, s1)
	voie_pn.update_cable_visibility(s0, s1)
	voie_pn.update_cable_phase(s0, s1, -1.0)
	# câble de retour : du bout aval de chaque véhicule à la gare aval, dans la gorge des galets
	voie_pn.retour_jusqua[-1] = s_de_d(_vehicules[0][1] - VehiculeFunival.DEMI_L)
	voie_pn.retour_jusqua[1] = s_de_d(_vehicules[1][1] - VehiculeFunival.DEMI_L)
	var s_cam: float = s0
	if _chantier != null or OS.get_thread_caller_id() != OS.get_main_thread_id():
		return                      # (pendant la construction, sur son fil : ni caméra ni maillages vivants)
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam != null and is_inside_tree():
		s_cam = s_de_d(-to_local(cam.global_position).z)
	voie_pn.update_galets_rames(s0, s1, s_cam, delta)


func _refaire_cables() -> void:
	if _mat_cables == null:
		_mat_cables = StandardMaterial3D.new()
		_mat_cables.albedo_color = Color(0.22, 0.22, 0.23)
		_mat_cables.roughness = 0.5
		_mat_cables.metallic = 0.8
		_mat_cables.cull_mode = BaseMaterial3D.CULL_DISABLED
	var L: float = longueur_h()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(2):
		var d: float = _vehicules[i][1]
		_ruban_galets(st, 1.0, d - VehiculeFunival.DEMI_L, i)
	var mesh: ArrayMesh = st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _mat_cables)
	if _cables == null:
		_cables = MeshInstance3D.new()
		_cables.name = "CablesFuni"
		_cables.set_meta("portee_loin", true)
		_cables.set_meta(MeshMerge.SANS_FUSION, true)
		_cables.set_meta("sans_collision", true)
		_cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_enfant(_cables)
	_cables.mesh = mesh


## Câble de retour du véhicule i, de d0 à d1 : dans la gorge des galets de son brin (VoiePN), au fond comme le
## câble tracteur (son centre plus bas de la différence des rayons) ; ruban en croix entre deux galets.
func _ruban_galets(st: SurfaceTool, d0: float, d1: float, i: int) -> void:
	if voie_pn == null or d1 - d0 < 0.5:
		_ruban(st, d0, d1, i, (-1.0 if i == 0 else 1.0) * 0.07, D_INFERIEUR, -0.07)
		return
	var pts: Array = voie_pn.strand_vertices(-1 if i == 0 else 1)
	var s0: float = s_de_d(d0)
	var s1: float = s_de_d(d1)
	var xf: Transform3D = voie_pn.transform
	var r: float = D_INFERIEUR * 0.5
	var bas: float = voie_pn.cable_radius - r
	var chemin: PackedVector3Array = PackedVector3Array()
	for v in pts:
		var s: float = float(v.s)
		if s < s0 or s > s1:
			continue
		var p: Vector3 = v.p
		if v.has("basis"):
			p -= (v.basis as Basis).y.normalized() * bas
		var pw: Vector3 = xf * p
		if pw.y - y_voie(-pw.z) > 0.35:
			# le brin du tracteur quitte la voie vers la poulie motrice, sous le plafond de la gare amont : le câble
			# inférieur, lui, reste sur les galets (retour d'utilisateur du 12/11/2026 : « le câble fin retour va au
			# plafond » — il suivait ce tracé jusqu'à 2,3 m au-dessus des rails) : sommet sauté
			continue
		chemin.append(pw)
	if chemin.size() < 2:
		_ruban(st, d0, d1, i, (-1.0 if i == 0 else 1.0) * 0.07, D_INFERIEUR, -0.07)
		return
	# tronçon libre, du dernier galet à l'attache sous le bout aval du véhicule : une chaînette, comme le câble du
	# Perce-Neige (TrackBuilder.chainette_y ; demande d'utilisateur du 09/11/2026)
	var dern: Vector3 = chemin[chemin.size() - 1]
	var att: Vector3 = Vector3(dern.x, y_voie(d1) + H_ATTACHE_INF, -d1)
	var portee: float = Vector2(att.x - dern.x, att.z - dern.z).length()
	if portee > 0.05:
		# (hauteurs prises au-dessus des rails : la voie est courbe en long, une corde droite sur des dizaines de
		# mètres passait 0,8 à 1,3 m au-dessus d'eux)
		var h0: float = dern.y - y_voie(-dern.z)
		var h1: float = att.y - y_voie(-att.z)
		var n_l: int = clampi(int(portee / 3.0), 8, 200)
		for k in range(1, n_l + 1):
			var t: float = float(k) / n_l
			var q: Vector3 = dern.lerp(att, t)
			var plat: float = TrackBuilder.chainette_y(t * portee, portee, h1 - h0, A_CHAINETTE_INF) - (h1 - h0) * t
			q.y = y_voie(-q.z) + lerpf(h0, h1, t) + plat
			chemin.append(q)
	for k in range(1, chemin.size()):
		var a: Vector3 = chemin[k - 1]
		var b2: Vector3 = chemin[k]
		for o in [Vector3(r, 0, 0), Vector3(0, r, 0)]:
			for q in [a - o, a + o, b2 + o, a - o, b2 + o, b2 - o]:
				st.add_vertex(q)


## Ruban (deux faces en croix) le long de la voie du véhicule i, de d0 à d1, au-dessus des poulies.
func _ruban(st: SurfaceTool, d0: float, d1: float, i: int, dx: float, diam: float, dy: float) -> void:
	if d1 - d0 < 0.5:
		return
	var n: int = maxi(1, int(ceil((d1 - d0) / 6.0)))
	var r: float = diam * 0.5
	var prec: Vector3 = Vector3.INF
	for k in range(n + 1):
		var d: float = d0 + (d1 - d0) * float(k) / float(n)
		var p: Vector3 = Vector3(x_voie(d, i) + dx, y_voie(d) + dy, -d)
		if k > 0:
			for o in [Vector3(r, 0, 0), Vector3(0, r, 0)]:
				for q in [prec - o, prec + o, p + o, prec - o, p + o, p - o]:
					st.add_vertex(q)
		prec = p


## Corps de collision d'un véhicule : planchers en gradins, cloisons, flancs (coupés portes ouvertes), toit.
func _corps_vehicule(i: int) -> void:
	var v: VehiculeFunival = _vehicules[i][0]
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "Corps_%d" % i
	corps.collision_layer = 0 if construction_cachee else CollisionsJeu.COUCHE_VEHICULE
	corps.collision_mask = 0
	corps.set_meta("vehicule", corps)
	corps.set_meta("funival", true)
	_enfant(corps)
	var portes: Array = []
	for f in v.formes_funi():
		var cs: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = f[0]
		cs.shape = b
		cs.transform = f[1]
		corps.add_child(cs)
		if f[2]:
			portes.append(cs)
	while _corps.size() < i:
		_corps.append(null)
	_corps.append([corps, portes])
	_placer(i)


## Moteur à courant continu de 484 kW (funiculaires-france.fr) : puissance au prorata de la vitesse.
const P_MOTEUR_KW: float = 484.0


func puissance_kw() -> float:
	return P_MOTEUR_KW * clampf(absf(_v) / V_FUNI, 0.0, 1.0)
