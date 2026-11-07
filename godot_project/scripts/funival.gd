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
const A_FUNI: float = 0.6               # accélération / freinage de service (m/s², estimé)
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


## Profil de la voie : dehors, le sol + 1,8 m lissé sur ±30 m (la poutre suit le terrain sur piles courtes) ; au
## portail, 4 m sous le terrain ; dans le tunnel, une droite jusqu'au quai amont ; raccords lissés.
func _preparer_voie() -> void:
	var L: float = longueur_h()
	_y_aval = terrain(0.0)
	_y_amont = terrain(L)
	_y_portail = terrain(portail_d) - PROF_PORTAIL
	var n: int = int(ceil(L / PAS_PROFIL)) + 1
	var cible: PackedFloat32Array = PackedFloat32Array()
	cible.resize(n)
	for k in range(n):
		var d: float = minf(float(k) * PAS_PROFIL, L)
		if d < portail_d:
			var y: float = _sol(0.0, -d) + DESSOUS_POUTRE
			# gare aval : voie en fosse entre les quais, au niveau du sol
			if d < 75.0:
				y = lerpf(_sol(0.0, -d) + 0.4, y, smoothstep(45.0, 75.0, d))
			# approche du portail : rejoint la cote d'entrée du tunnel
			y = lerpf(y, _y_portail, smoothstep(portail_d - 80.0, portail_d, d))
			cible[k] = y
		else:
			cible[k] = _y_portail + (_y_amont - _y_portail) * (d - portail_d) / (L - portail_d)
	# lissage (deux passes de ±30 m dehors, ±15 m dans le tunnel), bouts tenus
	for passe in range(2):
		var l2: PackedFloat32Array = cible.duplicate()
		for k in range(1, n - 1):
			var d2: float = float(k) * PAS_PROFIL
			var r: int = int((30.0 if d2 < portail_d + 40.0 else 15.0) / PAS_PROFIL)
			var s: float = 0.0
			var c: int = 0
			for j in range(maxi(0, k - r), mini(n, k + r + 1)):
				s += cible[j]
				c += 1
			l2[k] = s / float(c)
		l2[0] = _sol(0.0, 0.0) + 0.4
		l2[n - 1] = _y_amont
		cible = l2
	_prof = cible


# --- matériaux ----------------------------------------------------------------------------

## Matériaux propres au Funival. « cuit » : sans éclairage, couleur des sommets (tunnel, gare souterraine : la
## lumière du ciel n'y entre pas ; les lampes sont peintes dans les couleurs).
static func mat_funi(nom: String) -> Material:
	RemonteeKit.verrou.lock()
	var m: StandardMaterial3D = _mats_funi.get(nom)
	RemonteeKit.verrou.unlock()
	if m != null:
		return m
	m = StandardMaterial3D.new()
	match nom:
		"cuit":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			# (le brouillard volumétrique clair du jeu remplissait le tunnel, d'autant plus que la section est large :
			# évitement voilé de gris clair, rails compris — captures du 08/11/2026)
			m.disable_fog = true
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
	return 0.07 + flaque * (0.30 + 0.45 * clampf(cote_lampes, 0.0, 1.0))


## Teinte de la paroi : béton projeté gris-beige, tronçons de roche sombre, un tronçon à cintres et planches ocre.
## (Emplacements des tronçons ESTIMÉS : les photos les montrent sans dire où ils sont.)
func _teinte_paroi(d: float, k_anneau: int) -> Color:
	var L: float = longueur_h()
	var u: float = (d - portail_d) / (L - portail_d)
	if (u > 0.30 and u < 0.36) or (u > 0.72 and u < 0.80):
		return Color(0.42, 0.40, 0.37)                     # roche
	if u > 0.12 and u < 0.15:
		return Color(0.62, 0.45, 0.25) if k_anneau % 2 == 0 else Color(0.32, 0.24, 0.15)    # planches et cintres
	return Color(0.66, 0.65, 0.61)                          # béton projeté


# --- construction -----------------------------------------------------------------------

func construire() -> void:
	vitesse = V_FUNI
	await super.construire()


func _construire_corps() -> void:
	_preparer_voie()
	voie = 0.0
	H_CABLE_GARE = 0.0
	_voie_et_ouvrages()
	await _pause("funival : voie")
	_tunnel()
	await _pause("funival : tunnel")
	_gare_aval()
	await _pause("funival : gare aval")
	_gare_amont()
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
	var tun: MeshInstance3D = _maillage(st, mat_funi("cuit"), "Tunnel", false)
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
	for k in range(n):
		var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
		var y: float = VehiculeFunival.y_plancher_monde(self, d)
		for sx in [-1.0, 1.0]:
			var larg: float = 6.0 if sx < 0.0 else 3.5
			var x: float = sx * (W + larg * 0.5)
			# sol sous le gradin (pour la première contremarche)
			var sol: float = minf(_sol(x - larg * 0.4, -d), _sol(x + larg * 0.4, -d)) - 0.3
			var hm: float = maxf(y - sol, 0.2)
			# marche mince au niveau du plancher du compartiment, contremarche jusqu'à la marche du dessous (ou au sol),
			# garde-corps en tubes (photos : caillebotis à claire-voie, marches basses)
			var y_prec: float = VehiculeFunival.y_plancher_monde(self, d - lc) if k > 0 else sol
			var marche: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(larg, 0.12, lc + 0.04), Vector3(x, y - 0.06, -d), "acier_noir")
			marche.material_override = mat_funi("caillebotis_sombre")
			bardage.append(marche)
			var hc: float = maxf(y - minf(y_prec, sol + hm), 0.1)
			var cm: MeshInstance3D = RemonteeKit.boite_en(g, Vector3(larg, hc, 0.06), Vector3(x, y - hc * 0.5, -d + lc * 0.5), "acier_noir")
			cm.material_override = mat_funi("caillebotis_sombre")
			bardage.append(cm)
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
		# quai en escalier de béton (droite), caillebotis à rampe rouge (gauche)
		var sol: float = y_voie(d) - 0.5
		RemonteeKit.boite_en(g, Vector3(4.0, y - sol, lc + 0.04), Vector3(W + 2.0, sol + (y - sol) * 0.5, -d), "beton")
		RemonteeKit.boite_en(g, Vector3(2.4, 0.10, lc + 0.04), Vector3(-(W + 1.2), y - 0.05, -d), "caillebotis")
		RemonteeKit.boite_en(g, Vector3(0.05, 0.05, lc), Vector3(-(W + 2.4), y + 1.0, -d), "rouge_val")
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
	MeshMerge.merge(g, [w1, w2, ens, carre, moel], "Gare")


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
			var lg: float = 6.0 if aval else 4.0
			var ld: float = 3.5 if aval else 2.4
			boite.call(Vector3(lg, 0.4, lc + 0.05), Vector3(-(W + lg * 0.5), y - 0.2, -d))
			boite.call(Vector3(ld, 0.4, lc + 0.05), Vector3(W + ld * 0.5, y - 0.2, -d))
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
	if collisions_actives and i < _corps.size() and _corps[i] != null:
		(_corps[i][0] as Node3D).transform = Transform3D(b, p)
		for cs in _corps[i][1]:
			(cs as CollisionShape3D).disabled = porte > 0.5


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


func puissance_kw() -> float:
	var L: float = longueur_h()
	var p_nom: float = (masse_vehicule() + 272.0 * 80.0) * 9.81 * (_y_amont - _y_aval) / L * V_FUNI
	return 0.12 * p_nom * absf(_v) / V_FUNI / 1000.0
