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
## /mnt/apps_pool/sage/funival/trace.sage). Freinage pris égal (non mesuré : tunnel sans GPS).
const A_FUNI: float = 0.18
## Vitesse dans l'évitement (aiguillages passifs et courbes en S) : ralentissement signalé par l'utilisateur
## (08/11/2026), valeur NON SOURCÉE, calée pour que le trajet retrouve la durée d'une vidéo de la montée en cabine de
## conduite (départ de La Daille → arrêt à Bellevarde ≈ 304 s ; fiche RM.net 5 min) avec l'accélération mesurée :
## 6 m/s → 296 s.
const V_EVIT: float = 6.0
const ECARTEMENT: float = 1.20          # m (OSM, Wikipédia)
const E_VOIES: float = 3.75             # entraxe des deux voies dans l'évitement (estimé sur photo : 0,8-1 m entre les caisses de 2,8 m)
const L_EVITEMENT: float = 200.0        # m (estimé, 150-250 sur les photos)
const L_RACCORD: float = 45.0           # m, aiguillage passif et courbe en S
const R_TUNNEL: float = 2.20            # m (diamètre estimé 4-4,5 m)
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
	var t: float = 1.0 if e <= h else (0.0 if e >= h + L_RACCORD else 1.0 - (e - h) / L_RACCORD)
	return t * t * (3.0 - 2.0 * t)


func dans_tunnel(d: float) -> bool:
	return d > portail_d


## Profil de la voie, courbe régulière :
## - dehors, une parabole ajustée sur la trace GPS altimétrique d'un passage réel (26/04/2026, 68 points projetés sur
##   l'axe, résidu ≤ 4,3 m ; calcul /mnt/apps_pool/sage/funival/rampe.sage) : 20,8 % au départ, 29,7 % au portail ; le
##   viaduc ne suit pas le terrain, il est porté par des piles (photos : hautes et fines) ;
## - dans le tunnel, la pente monte progressivement jusqu'au maximum de la fiche (53 %, funiculaires-france.fr), s'y
##   tient, et se réduit seulement à la toute fin, en gare amont, où elle reste prononcée (comme au Perce-Neige ;
##   utilisateur, 08/11/2026) ; pente en gare ESTIMÉE (45 %) ; la longueur de la montée vers 53 % se déduit de
##   l'altitude de la gare amont.
## Calée à l'aval sur le haut du terrain de la gare (planchers au niveau du sol, voie en fosse).
const RAMPE_S0: float = 0.207756          # pente au départ (trace GPS)
const RAMPE_K: float = 8.985184e-05       # y = s0·d + k·d²
const RACCORD_TUNNEL: float = 150.0
const PENTE_MAX: float = 0.53             # fiche
const PENTE_GARE_AMONT: float = 0.45      # ESTIMÉE : « reste prononcée » (utilisateur) ; non mesurable sur les vidéos
const L_REDUCTION: float = 50.0           # réduction courte, en toute fin (ESTIMÉE)
var _pente_tunnel: PackedFloat32Array = PackedFloat32Array()   # [d0, a, h, b, s1] : pente par morceaux dans le tunnel


## Pente dans le tunnel en u = d − portail : s1 → PENTE_MAX sur a, palier sur h, → PENTE_GARE_AMONT sur b.
func _pente_tunnel_en(u: float) -> float:
	var a: float = _pente_tunnel[1]
	var h: float = _pente_tunnel[2]
	var b: float = _pente_tunnel[3]
	var s1: float = _pente_tunnel[4]
	if u <= a:
		return lerpf(s1, PENTE_MAX, u / a)
	if u <= a + h:
		return PENTE_MAX
	return lerpf(PENTE_MAX, PENTE_GARE_AMONT, clampf((u - a - h) / maxf(b, 1.0), 0.0, 1.0))


func _preparer_voie() -> void:
	var L: float = longueur_h()
	_y_aval = terrain(0.0)
	_y_amont = terrain(L)
	# ancrage aval : le plancher du compartiment le plus enterré au niveau du terrain (quais compris)
	var W0: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	var dep: float = -INF
	var dd: float = 0.0
	while dd <= 2.0 * VehiculeFunival.DEMI_L + 2.0:
		for xs in [-(W0 + LARG_GRADINS[0]), -(W0 + LARG_GRADINS[0] * 0.5), 0.0, W0 + LARG_GRADINS[1] * 0.5, W0 + LARG_GRADINS[1]]:
			dep = maxf(dep, _sol(float(xs), -dd) - (RAMPE_S0 * dd + RAMPE_K * dd * dd))
		dd += 1.0
	var y0: float = dep - FOSSE_AVAL
	var dp: float = portail_d
	var yp: float = y0 + RAMPE_S0 * dp + RAMPE_K * dp * dp
	var s1: float = RAMPE_S0 + 2.0 * RAMPE_K * dp
	# montée a (s1 → 53 %), palier h, réduction b = L_REDUCTION ; a tel que l'aire sous la pente = dénivelé restant
	var reste: float = L - dp
	var b: float = L_REDUCTION
	var dh: float = _y_amont - yp
	var a: float = (PENTE_MAX * (reste - b) + (PENTE_MAX + PENTE_GARE_AMONT) * 0.5 * b - dh) / (PENTE_MAX - (s1 + PENTE_MAX) * 0.5)
	a = clampf(a, RACCORD_TUNNEL, reste - b)
	_pente_tunnel = PackedFloat32Array([dp, a, reste - b - a, b, s1])
	_y_portail = yp
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
			var u0: float = maxf(d - PAS_PROFIL, dp) - dp
			var u1: float = d - dp
			y_t += (_pente_tunnel_en(u0) + _pente_tunnel_en(u1)) * 0.5 * (u1 - u0)
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
			m.albedo_color = Color(0.60, 0.63, 0.67)      # poutre, piles (gris clair froid sur photo ; plus chaud, il virait au beige)
			m.roughness = 0.95
		"bois_gris":
			m.albedo_color = Color(0.64, 0.62, 0.58)      # bardage de bois gris patiné (gare aval)
			m.roughness = 0.9
		"caillebotis_sombre":
			m.albedo_color = Color(0.22, 0.23, 0.24)
			m.roughness = 0.75
			m.metallic = 0.4
		"rocher":
			m.albedo_color = Color(0.40, 0.39, 0.37)
			m.roughness = 1.0
		"moellons":
			m.albedo_color = Color(0.46, 0.47, 0.47)      # maçonnerie de pierre grise (gare amont)
			m.roughness = 1.0
		_:
			m.albedo_color = Color(1, 0, 1)
	RemonteeKit.verrou.lock()
	_mats_funi[nom] = m
	RemonteeKit.verrou.unlock()
	return m


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
	_voie_et_ouvrages()
	await _pause("funival : voie")
	await _tunnel()
	await _pause("funival : tunnel")
	_gare_aval()
	await _pause("funival : gare aval")
	_gare_amont()
	_butoir_et_poulie()
	await _pause("funival : gare amont")
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


## Dehors : rails, poutre en U de béton gris clair sur piles courtes à chevêtre, passerelle de service en caillebotis
## d'un côté, main courante. (Dans le tunnel, rails et radier sont dans le maillage cuit.)
func _voie_et_ouvrages() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for xr in [-ECARTEMENT * 0.5, ECARTEMENT * 0.5]:
		_extruder(st, _rail_profil(xr), 0.0, portail_d + 2.0, PAS_PROFIL)
	_maillage(st, RemonteeKit.mat("acier"), "Rails")
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u: PackedVector2Array = PackedVector2Array([Vector2(-1.75, 0.55), Vector2(-1.75, -1.0), Vector2(1.75, -1.0),
		Vector2(1.75, 0.55), Vector2(1.55, 0.55), Vector2(1.55, -0.45), Vector2(-1.55, -0.45), Vector2(-1.55, 0.55)])
	_extruder(st, u, 30.0, portail_d + 2.0, PAS_PROFIL, -1, true)
	_maillage(st, mat_funi("beton_clair"), "Poutre")
	var ouv: Node3D = Node3D.new()
	ouv.name = "Ouvrages"
	ouv.set_meta("portee_loin", true)
	_enfant(ouv)
	var d: float = 45.0
	while d < portail_d - 15.0:
		var y: float = y_voie(d) - 1.0
		var sol: float = _sol(0.0, -d)
		if y - sol > 0.2:
			var h: float = y - sol + 0.6
			RemonteeKit.boite_en(ouv, Vector3(0.9, h, 0.7), Vector3(0, sol - 0.6 + h * 0.5, -d), "beton")
			RemonteeKit.boite_en(ouv, Vector3(3.3, 0.45, 1.0), Vector3(0, y - 0.22, -d), "beton")
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
	var d0: float = portail_d - 1.0
	var d1: float = L - L_HALL + 2.0
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# paroi : anneau elliptique à 14 côtés, radier plat
	var cotes: int = 14
	var n: int = int(ceil((d1 - d0) / PAS_TUNNEL))
	var prec: PackedVector3Array = PackedVector3Array()
	var cprec: PackedColorArray = PackedColorArray()
	for k in range(n + 1):
		var d: float = d0 + (d1 - d0) * float(k) / float(n)
		var t: float = _t_evit(d)
		var rx: float = lerpf(R_TUNNEL, R_TUNNEL_EVIT, t)
		var ry: float = lerpf(R_TUNNEL, R_TUNNEL * 1.2, t)
		var y0: float = y_voie(d) - 0.45 + ry * 0.62
		var base: Color = _teinte_paroi(d, k)
		var cour: PackedVector3Array = PackedVector3Array()
		var ccour: PackedColorArray = PackedColorArray()
		for j in range(cotes):
			var a: float = TAU * float(j) / float(cotes)
			var p: Vector3 = Vector3(cos(a) * rx, maxf(y0 + sin(a) * ry, y_voie(d) - 0.45), -d)
			cour.append(p)
			ccour.append(base * _lumiere_tunnel(d, -cos(a)))
		if k > 0:
			for j in range(cotes):
				var j2: int = (j + 1) % cotes
				for e in [[prec[j], cprec[j]], [cour[j2], ccour[j2]], [prec[j2], cprec[j2]],
						[prec[j], cprec[j]], [cour[j], ccour[j]], [cour[j2], ccour[j2]]]:
					st.set_color(e[1])
					st.add_vertex(e[0])
		prec = cour
		cprec = ccour
		# (par tranches : sur le fil principal — PWA, sans écran — le tunnel faisait 50 ms d'un bloc, relevé du PC
		# du 08/11/2026)
		if k % 80 == 79:
			await _pause("funival : tunnel")
	await _pause("funival : tunnel")
	var gris_rail: Color = Color(0.55, 0.56, 0.58)
	var radier: Color = Color(0.40, 0.39, 0.37)
	var teinte := func(c: Color) -> Callable:
		return func(d2: float, _j: int) -> Color: return c * (_lumiere_tunnel(d2, 0.4) * 1.3)
	var c_ev: float = L * 0.5
	var h_ev: float = L_EVITEMENT * 0.5 + L_RACCORD
	var troncons: Array = [[d0, c_ev - h_ev, -1], [c_ev + h_ev, d1, -1], [c_ev - h_ev, c_ev + h_ev, 0], [c_ev - h_ev, c_ev + h_ev, 1]]
	for tr in troncons:
		for xr in [-ECARTEMENT * 0.5, ECARTEMENT * 0.5]:
			_extruder(st, _rail_profil(xr), tr[0], tr[1], 5.0, tr[2], false, teinte.call(gris_rail))
		_extruder(st, PackedVector2Array([Vector2(-1.0, -0.16), Vector2(1.0, -0.16)]), tr[0], tr[1], 5.0, tr[2], false,
			teinte.call(radier))
	await _pause("funival : tunnel")
	# passerelle-escalier de service le long de la paroi gauche, chemin de câbles au-dessus
	var cail: Color = Color(0.45, 0.46, 0.47)
	_extruder(st, PackedVector2Array([Vector2(-R_TUNNEL + 0.15, 0.55), Vector2(-R_TUNNEL + 0.95, 0.55)]), d0, c_ev - h_ev, 5.0,
		-1, false, teinte.call(cail))
	_extruder(st, PackedVector2Array([Vector2(-R_TUNNEL + 0.15, 0.55), Vector2(-R_TUNNEL + 0.95, 0.55)]), c_ev + h_ev, d1, 5.0,
		-1, false, teinte.call(cail))
	_extruder(st, PackedVector2Array([Vector2(-R_TUNNEL + 0.25, 2.3), Vector2(-R_TUNNEL + 0.25, 2.5)]), d0, c_ev - h_ev, 5.0,
		-1, false, teinte.call(Color(0.12, 0.12, 0.12)))
	_extruder(st, PackedVector2Array([Vector2(-R_TUNNEL + 0.25, 2.3), Vector2(-R_TUNNEL + 0.25, 2.5)]), c_ev + h_ev, d1, 5.0,
		-1, false, teinte.call(Color(0.12, 0.12, 0.12)))
	# poulies du câble entre les rails, toutes les 12 m (hors évitement)
	var dp: float = d0 + 6.0
	while dp < d1:
		if absf(dp - c_ev) > h_ev:
			var yp: float = y_voie(dp)
			var c2: Color = Color(0.30, 0.30, 0.31) * (_lumiere_tunnel(dp, 0.4) * 1.3)
			for q in [[Vector3(-0.18, -0.15, 0.0), Vector3(-0.18, 0.05, 0.0), Vector3(0.18, 0.05, 0.0)],
					[Vector3(-0.18, -0.15, 0.0), Vector3(0.18, 0.05, 0.0), Vector3(0.18, -0.15, 0.0)]]:
				for v in q:
					st.set_color(c2)
					st.add_vertex(Vector3(v.x, yp + v.y, -dp))
		dp += 12.0
	await _pause("funival : tunnel")
	var tun: MeshInstance3D = _maillage(st, mat_funi("cuit"), "Tunnel", false)
	await _pause("funival : tunnel")
	tun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# lampes : un hublot tous les ECART_LAMPES m sur la paroi gauche (en montant), à mi-hauteur
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d2: float = portail_d + 10.0
	while d2 < d1 - 5.0:
		var rx2: float = lerpf(R_TUNNEL, R_TUNNEL_EVIT, _t_evit(d2))
		var p: Vector3 = Vector3(-rx2 + 0.10, y_voie(d2) + 1.7, -d2)
		for q in [[Vector3(0, -0.10, -0.35), Vector3(0, 0.10, 0.35), Vector3(0, 0.10, -0.35)],
				[Vector3(0, -0.10, -0.35), Vector3(0, -0.10, 0.35), Vector3(0, 0.10, 0.35)]]:
			for v in q:
				st.add_vertex(p + v)
		d2 += ECART_LAMPES
	_maillage(st, mat_funi("lampe"), "Lampes", false)
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
	var lc: float = lq / float(n)
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
		var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
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
	var lc: float = lq / float(n)
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	var bardage: Array = []
	# gradins : palier devant chaque porte, volée de petites marches de caillebotis entre deux paliers (photos)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1.0, 1.0]:
		for b in _gradins(sx):
			_boite_st(st, b[0], b[1])
	var gr: MeshInstance3D = _maillage(st, mat_funi("caillebotis_sombre"), "Gradins")
	gr.reparent(g, false)          # (hors de l'arbre pendant la construction : pas de transformation globale)
	bardage.append(gr)
	for k in range(n):
		var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
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
	var yp: float = y_voie(L) + 3.2
	var zp: float = -(L + 0.6)
	var axe: Basis = Basis(Vector3.RIGHT, PI * 0.5)
	RemonteeKit.cylindre(g, 2.6, 2.6, 0.35, Transform3D(axe, Vector3(0, yp, zp)), "bleu_doppelmayr", 32)
	RemonteeKit.cylindre(g, 0.55, 0.55, 0.7, Transform3D(axe, Vector3(0, yp, zp)), "rouge_val", 16)
	for k in range(6):
		var a2: float = TAU * float(k) / 6.0
		RemonteeKit.boite(g, Vector3(0.22, 2.2, 0.2), Transform3D(Basis(Vector3.BACK, a2), Vector3(0, yp, zp + 0.25) + Basis(Vector3.BACK, a2) * Vector3(0, 1.3, 0)), "bleu_doppelmayr")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.06, 1.1, 0.06), Vector3(sx * 2.8, y_voie(L) + 0.55, zp + 1.6), "galva")
	RemonteeKit.boite_en(g, Vector3(5.6, 0.05, 0.05), Vector3(0, y_voie(L) + 1.1, zp + 1.6), "galva")
	MeshMerge.merge(g, [], "Machines")


## Gare amont (Bellevarde) : la voie arrive dans une salle creusée sous le rocher (quai en escalier de béton d'un
## côté, escalier en caillebotis à rampe rouge de l'autre, plafond blanc, mur de pierre « WELCOME TO BELLEVARDE »),
## qui débouche en haut dans le bâtiment de surface : bardage anthracite, deux volumes à pignon, bandeau vitré,
## volume de pierre accolé.
func _gare_amont() -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAmont"
	_enfant(g)
	var L: float = longueur_h()
	var dq: float = _x_quai(false)
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = lq / float(n)
	var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
	# salle : boîte cuite vue de l'intérieur, de la fin du tunnel au bâtiment
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx: float = W + 4.2
	var salle: PackedVector2Array = PackedVector2Array([Vector2(hx, -0.6), Vector2(hx, 6.5), Vector2(-hx, 6.5), Vector2(-hx, -0.6)])
	var clair := func(_d: float, j: int) -> Color:
		return Color(0.80, 0.80, 0.78) if j == 1 or j == 2 else Color(0.62, 0.61, 0.58)
	_extruder(st, salle, L - L_HALL, L + 1.0, 2.5, -1, false, clair, true)
	_extruder(st, PackedVector2Array([Vector2(-1.0, -0.16), Vector2(1.0, -0.16)]), L - L_HALL, L, 5.0, -1, false,
		func(_d: float, _j: int) -> Color: return Color(0.38, 0.37, 0.35))
	for xr in [-ECARTEMENT * 0.5, ECARTEMENT * 0.5]:
		_extruder(st, _rail_profil(xr), L - L_HALL, L, 5.0, -1, false, func(_d: float, _j: int) -> Color: return Color(0.55, 0.56, 0.58))
	_maillage(st, mat_funi("cuit"), "SalleAmont", false)
	for k in range(n):
		var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
		var y: float = VehiculeFunival.y_plancher_monde(self, d)
		# main courante rouge à gauche (photos)
		RemonteeKit.boite_en(g, Vector3(0.05, 0.05, lc), Vector3(-(W + LARG_AMONT[0]), y + 1.0, -d), "rouge_val")
	# escaliers de béton clair des deux côtés (paliers et volées, comme à La Daille) et jupes rouges le long de la
	# voie (vidéos : voie bordée d'une structure rouge), dans le maillage cuit de la salle
	var st2: SurfaceTool = SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx2 in [-1.0, 1.0]:
		for b in _gradins(sx2, false, false):
			st2.set_color(Color(0.80, 0.79, 0.76))
			_boite_st(st2, b[0], b[1])
		for k2 in range(n):
			var d2: float = dq - lq * 0.5 + lc * (float(k2) + 0.5)
			var y2: float = VehiculeFunival.y_plancher_monde(self, d2)
			var yb: float = y_voie(d2) - 0.4
			st2.set_color(Color(0.72, 0.10, 0.08))
			_boite_st(st2, Vector3(0.12, y2 - yb, lc + 0.02), Vector3(sx2 * (W + 0.06), (y2 + yb) * 0.5, -d2))
	var esc: MeshInstance3D = _maillage(st2, mat_funi("cuit"), "EscaliersAmont", false)
	esc.reparent(g, false)
	# mur de pierre et enseignes, à droite, au milieu du quai
	var dm: float = dq
	var ym: float = VehiculeFunival.y_plancher_monde(self, dm)
	RemonteeKit.boite_en(g, Vector3(0.3, 4.0, 14.0), Vector3(hx - 0.2, ym + 2.0, -dm), "pierre")
	var w1: MeshInstance3D = RemonteeKit.texte_fige(g, "WELCOME TO BELLEVARDE", 64, 0.010, Color(0.80, 0.80, 0.78))
	w1.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hx - 0.37, ym + 2.8, -dm))
	var w2: MeshInstance3D = RemonteeKit.texte_fige(g, "Respirez, vous êtes à 2690 m !", 48, 0.008, Color(0.85, 0.10, 0.10))
	w2.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hx - 0.37, ym + 3.6, -dm + 9.0))
	# bâtiment de surface au débouché (photos ; ~38 m de long, estimé) : volume haut à pignon au-dessus de la salle,
	# bandeau de fenêtres sous le toit, aile basse à pignon, vitrage en bandeau au rez-de-chaussée, volume de pierre
	var ys: float = y_voie(L)
	var toits: Array = []
	var pignon := func(cx: float, cz: float, larg: float, long_: float, h: float, haut_toit: float) -> void:
		RemonteeKit.boite_en(g, Vector3(larg, h, long_), Vector3(cx, ys + h * 0.5 - 0.5, cz), "peinture_anthracite")
		RemonteeKit.boite_en(g, Vector3(larg + 0.1, 1.0, long_ + 0.1), Vector3(cx, ys + 1.2, cz), "vitrage_sombre")
		var a: float = atan2(haut_toit, larg * 0.5)
		var pan: float = sqrt(larg * larg * 0.25 + haut_toit * haut_toit) + 0.8
		for sx2 in [-1.0, 1.0]:
			var mi_t: MeshInstance3D = RemonteeKit.boite(g, Vector3(pan, 0.22, long_ + 1.6), Transform3D(Basis(Vector3.BACK, -sx2 * a),
				Vector3(cx + sx2 * larg * 0.25, ys + h - 0.5 + haut_toit * 0.5, cz)), "galva_sombre")
			toits.append(mi_t)
		# pignons pleins (triangles approchés par deux boîtes)
		for sz2 in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(larg * 0.6, haut_toit * 0.6, 0.2), Vector3(cx, ys + h - 0.5 + haut_toit * 0.3, cz + sz2 * long_ * 0.5), "peinture_anthracite")
	var zs: float = -(L - 8.0)
	pignon.call(0.0, zs, 2.0 * hx + 2.0, 22.0, 8.0, 3.2)
	RemonteeKit.boite_en(g, Vector3(2.0 * hx + 2.1, 0.9, 22.1), Vector3(0, ys + 6.2, zs), "vitrage_sombre")     # bandeau sous le toit
	pignon.call(hx + 7.0, zs - 12.0, 12.0, 16.0, 4.5, 2.2)
	var moel: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(6.0, 3.6, 7.0), Vector3(-(hx + 4.0), ys + 1.3, zs + 6.0), "pierre")
	moel.material_override = mat_funi("moellons")
	moel.set_meta(MeshMerge.SANS_FUSION, true)
	var ens: MeshInstance3D = RemonteeKit.texte_fige(g, "Funival", 120, 0.016, Color(0.95, 0.95, 0.95))
	ens.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hx + 1.06, ys + 4.6, zs))
	var carre: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(0.05, 1.4, 1.4), Vector3(hx + 1.04, ys + 4.6, zs + 5.5), "rouge_val")
	carre.set_meta(MeshMerge.SANS_FUSION, true)
	MeshMerge.merge(g, [w1, w2, ens, carre, moel, esc], "Gare")


func _collisions_funi() -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsLigne"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
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
	var lc: float = lq / float(n)
	for aval in [true, false]:
		var dq: float = _x_quai(aval)
		for k in range(n):
			var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
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
			var d3: float = dq3 - lq * 0.5 + lc * (float(k3) + 0.5)
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
	boite.call(Vector3(2.0 * hx, 0.4, 10.0), Vector3(0, VehiculeFunival.y_plancher_monde(self, L - 1.0) - 0.2, -(L + 4.0)))


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


func souterrain(p: Vector3) -> bool:
	if not pret or not is_inside_tree():
		return false
	var loc: Vector3 = global_transform.affine_inverse() * p
	var d: float = -loc.z
	return d > portail_d + 3.0 and d < longueur_h() + 1.0 \
		and absf(loc.x) < lerpf(R_TUNNEL, R_TUNNEL_EVIT, _t_evit(d)) + 3.0 and absf(loc.y - y_voie(d) - 1.0) < 6.0


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
			_t_quai -= delta
			if _t_quai <= 0.0:
				_phase = "route"
	else:
		var v_max: float = vitesse * CRANS[cran]
		# évitement : on y entre à V_EVIT, freinage anticipé (les deux véhicules y entrent ensemble)
		var c_ev: float = longueur_h() * 0.5
		var h_ev: float = L_EVITEMENT * 0.5 + L_RACCORD
		var hors: float = maxf(absf(_s - c_ev) - h_ev, 0.0) * sqrt(1.0 + pow(pente_voie(_s), 2.0))
		var vers: bool = (_s < c_ev) == (_sens > 0.0) or hors <= 0.0
		if vers:
			v_max = minf(v_max, sqrt(V_EVIT * V_EVIT + 2.0 * A_FUNI * hors))
		# distance restante le long de la voie (freinage jusqu'au quai)
		var reste: float = absf(but - _s) * sqrt(1.0 + pow(pente_voie(_s), 2.0))
		v_max = minf(v_max, maxf(sqrt(2.0 * A_FUNI * maxf(reste - 0.3, 0.0)), 0.35))
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
const D_INFERIEUR: float = 0.025       # câble tracteur aval 25 mm, 42 870 daN, Tréfileurope 1987 (funiculaires-france.fr)


func _maj_positions() -> void:
	super._maj_positions()
	if absf(_s - _d_cables) > 3.0:
		_d_cables = _s
		_refaire_cables()


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
		var dx: float = (-1.0 if i == 0 else 1.0) * 0.07
		_ruban(st, d + VehiculeFunival.DEMI_L, L - 1.0, i, dx, D_TRACTEUR, -0.05)
		_ruban(st, 1.0, d - VehiculeFunival.DEMI_L, i, dx, D_INFERIEUR, -0.07)
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
