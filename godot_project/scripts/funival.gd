class_name Funival
extends Telepherique
## Funival (Val d'Isère, La Daille → Bellevarde ; Montaval sous licence Waagner-Biró, 1987 ; véhicules Cwa) :
## funiculaire à deux véhicules de 272 places, câble tracteur, gare motrice amont. D'après la fiche technique et
## les photos du reportage remontees-mecaniques.net (fiche de cotes : _cuites/funival/FICHE_PHOTOS.md, cotes
## estimées sur photo) et le tracé OSM :
## - de la gare aval au portail : ~496 m en plan, voie dans une poutre en U de béton sur piles courtes (27 %) ;
## - du portail à la gare amont : tunnel circulaire rectiligne (48 %), évitement à mi-ligne (deux voies).
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
const H_RAIL: float = 0.0               # dessus des rails au niveau de la voie
const PROF_PORTAIL: float = 4.0         # voie sous le terrain au droit du portail (m)
const DESSOUS_POUTRE: float = 1.7       # garde sous la poutre extérieure (1,5-2 m sur photo)

var portail_d: float = 496.2            # (données ; OSM : bout du pont, début du tunnel)
var _y_portail: float = 0.0
var _y_amont: float = 0.0
var _y_aval: float = 0.0
var _mat_tunnel: StandardMaterial3D = null
var _mat_lampe: StandardMaterial3D = null


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
	var L: float = longueur_h()
	d = clampf(d, 0.0, L)
	var raccord: float = 40.0           # changement de pente au portail, en arc
	var ye: float = _y_aval + (_y_portail - _y_aval) * d / portail_d
	var yt: float = _y_portail + (_y_amont - _y_portail) * (d - portail_d) / (L - portail_d)
	if absf(d - portail_d) >= raccord:
		return ye if d < portail_d else yt
	# raccord parabolique entre les deux pentes
	var p0: float = (_y_portail - _y_aval) / portail_d
	var p1: float = (_y_amont - _y_portail) / (L - portail_d)
	var u: float = d - (portail_d - raccord)
	var y0: float = _y_portail - p0 * raccord
	return y0 + p0 * u + (p1 - p0) * u * u / (4.0 * raccord)


func pente_voie(d: float) -> float:
	return (y_voie(d + 1.0) - y_voie(d - 1.0)) / 2.0


## Décalage latéral de la voie du véhicule i (0 : monte à gauche dans l'évitement) en d.
func x_voie(d: float, i: int) -> float:
	var c: float = longueur_h() * 0.5
	var e: float = absf(d - c)
	var h: float = L_EVITEMENT * 0.5
	var t: float = 1.0 if e <= h else (0.0 if e >= h + L_RACCORD else 1.0 - (e - h) / L_RACCORD)
	t = t * t * (3.0 - 2.0 * t)
	return (-1.0 if i == 0 else 1.0) * E_VOIES * 0.5 * t


func dans_tunnel(d: float) -> bool:
	return d > portail_d


func _preparer_voie() -> void:
	var L: float = longueur_h()
	_y_aval = terrain(0.0)
	_y_amont = terrain(L)
	_y_portail = terrain(portail_d) - PROF_PORTAIL


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
	for aval in [true, false]:
		_gare_funi(aval)
		await _pause("funival : gare")
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


## Maillage d'une bande extrudée le long de la voie : profil (x, y) en travers, posé tous les `pas` m de d0 à d1.
func _extruder(st: SurfaceTool, profil: PackedVector2Array, d0: float, d1: float, pas: float, i_voie: int = -1,
		ferme: bool = false) -> void:
	var n: int = maxi(1, int(ceil((d1 - d0) / pas)))
	var np: int = profil.size()
	var prec: PackedVector3Array = PackedVector3Array()
	for k in range(n + 1):
		var d: float = d0 + (d1 - d0) * float(k) / float(n)
		var x0: float = x_voie(d, i_voie) if i_voie >= 0 else 0.0
		var y0: float = y_voie(d)
		var cour: PackedVector3Array = PackedVector3Array()
		for q in profil:
			cour.append(Vector3(x0 + q.x, y0 + q.y, -d))
		if k > 0:
			for j in range(np - 1 + (1 if ferme else 0)):
				var j2: int = (j + 1) % np
				var a: Vector3 = prec[j]
				var b: Vector3 = prec[j2]
				var c: Vector3 = cour[j2]
				var e: Vector3 = cour[j]
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
				st.add_vertex(a)
				st.add_vertex(c)
				st.add_vertex(e)
		prec = cour


func _maillage(st: SurfaceTool, m: Material, nom: String) -> MeshInstance3D:
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.set_meta("portee_loin", true)       # (voie et tunnel : vus de loin, pas des détails à 250 m)
	_enfant(mi)
	return mi


## Rails (deux voies dans l'évitement), poutre en U de béton et piles à l'extérieur, passerelle de service.
func _voie_et_ouvrages() -> void:
	var L: float = longueur_h()
	var c: float = L * 0.5
	var h: float = L_EVITEMENT * 0.5 + L_RACCORD
	# rails : un profil en I aplati par file
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := func(xr: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(xr - 0.035, -0.15), Vector2(xr - 0.035, 0.0), Vector2(xr + 0.035, 0.0),
			Vector2(xr + 0.035, -0.15)])
	for xr in [-ECARTEMENT * 0.5, ECARTEMENT * 0.5]:
		_extruder(st, rail.call(xr), 0.0, c - h, 5.0)
		_extruder(st, rail.call(xr), c + h, L, 5.0)
		for iv in [0, 1]:
			_extruder(st, rail.call(xr), c - h, c + h, 4.0, iv)
	_maillage(st, RemonteeKit.mat("acier"), "Rails")
	# longrine / radier sous les rails (béton), dans le tunnel et dehors
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radier: PackedVector2Array = PackedVector2Array([Vector2(-1.1, -0.45), Vector2(-1.1, -0.15), Vector2(1.1, -0.15),
		Vector2(1.1, -0.45)])
	_extruder(st, radier, 0.0, c - h, 10.0)
	_extruder(st, radier, c + h, L, 10.0)
	for iv2 in [0, 1]:
		_extruder(st, radier, c - h, c + h, 8.0, iv2)
	# poutre en U à l'extérieur : fond et deux parapets bas
	var u: PackedVector2Array = PackedVector2Array([Vector2(-1.75, 0.55), Vector2(-1.75, -1.0), Vector2(1.75, -1.0),
		Vector2(1.75, 0.55), Vector2(1.55, 0.55), Vector2(1.55, -0.45), Vector2(-1.55, -0.45), Vector2(-1.55, 0.55)])
	_extruder(st, u, 0.0, portail_d, 10.0, -1, true)
	_maillage(st, RemonteeKit.mat("beton"), "Poutre")
	# piles courtes jusqu'au sol (toutes les 20 m), passerelle caillebotis côté droit en montant
	var ouv: Node3D = Node3D.new()
	ouv.name = "Ouvrages"
	ouv.set_meta("portee_loin", true)
	_enfant(ouv)
	var d: float = 20.0
	while d < portail_d - 10.0:
		var y: float = y_voie(d) - 1.0
		var sol: float = _sol(0.0, -d)
		if y - sol > 0.3:
			RemonteeKit.boite_en(ouv, Vector3(2.4, y - sol + 1.0, 0.8), Vector3(0, sol + (y - sol + 1.0) * 0.5 - 1.0, -d), "beton")
		d += 20.0
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_extruder(st, PackedVector2Array([Vector2(1.75, 0.05), Vector2(2.55, 0.05), Vector2(2.55, -0.02), Vector2(1.75, -0.02)]),
		0.0, portail_d, 10.0)
	_maillage(st, RemonteeKit.mat("caillebotis"), "Passerelle")
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_extruder(st, PackedVector2Array([Vector2(2.52, 1.05), Vector2(2.56, 1.05), Vector2(2.56, 1.0), Vector2(2.52, 1.0)]),
		0.0, portail_d, 10.0)
	_maillage(st, RemonteeKit.mat("galva"), "MainCourante")
	MeshMerge.merge(ouv, [], "Ouvrage")


## Tube du tunnel, vu de l'intérieur seulement (faces tournées vers l'axe : de dehors, sous la roche, rien),
## section élargie dans l'évitement, lampes sur la paroi gauche en montant, anneau de béton au portail.
func _tunnel() -> void:
	var L: float = longueur_h()
	var c: float = L * 0.5
	if _mat_tunnel == null:
		_mat_tunnel = StandardMaterial3D.new()
		_mat_tunnel.albedo_color = Color(0.62, 0.60, 0.55)       # béton projeté beige-gris (photos)
		_mat_tunnel.roughness = 0.95
		_mat_lampe = StandardMaterial3D.new()
		_mat_lampe.albedo_color = Color(1.0, 0.98, 0.92)
		_mat_lampe.emission_enabled = true
		_mat_lampe.emission = Color(1.0, 0.96, 0.86)
		_mat_lampe.emission_energy_multiplier = 3.0
		_mat_lampe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cotes: int = 12
	var pas: float = 10.0
	var d0: float = portail_d - 2.0
	var n: int = int(ceil((L - 6.0 - d0) / pas))
	var prec: PackedVector3Array = PackedVector3Array()
	for k in range(n + 1):
		var d: float = d0 + (L - 6.0 - d0) * float(k) / float(n)
		var e: float = absf(d - c)
		var hh: float = L_EVITEMENT * 0.5
		var t: float = 1.0 if e <= hh else (0.0 if e >= hh + L_RACCORD else 1.0 - (e - hh) / L_RACCORD)
		t = t * t * (3.0 - 2.0 * t)
		var rx: float = lerpf(R_TUNNEL, R_TUNNEL_EVIT, t)
		var ry: float = lerpf(R_TUNNEL, R_TUNNEL * 1.15, t)
		var y0: float = y_voie(d) - 0.45 + ry * 0.62          # axe : radier plat sous les rails
		var cour: PackedVector3Array = PackedVector3Array()
		for j in range(cotes):
			var a: float = TAU * float(j) / float(cotes)
			cour.append(Vector3(cos(a) * rx, y0 + sin(a) * ry, -d))
		if k > 0:
			for j in range(cotes):
				var j2: int = (j + 1) % cotes
				# ordre inverse de l'extérieur : faces avant vers l'axe
				st.add_vertex(prec[j])
				st.add_vertex(cour[j2])
				st.add_vertex(prec[j2])
				st.add_vertex(prec[j])
				st.add_vertex(cour[j])
				st.add_vertex(cour[j2])
		prec = cour
	_maillage(st, _mat_tunnel, "Tunnel").set_meta(MeshMerge.SANS_FUSION, true)
	# lampes : un hublot tous les 20 m sur la paroi gauche (en montant), à mi-hauteur
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d2: float = portail_d + 10.0
	while d2 < L - 20.0:
		var e2: float = absf(d2 - c)
		var rx2: float = R_TUNNEL_EVIT if e2 < L_EVITEMENT * 0.5 else R_TUNNEL
		var p: Vector3 = Vector3(-rx2 + 0.12, y_voie(d2) + 1.6, -d2)
		for q in [[Vector3(0, -0.12, -0.5), Vector3(0, 0.12, -0.5), Vector3(0, 0.12, 0.5)],
				[Vector3(0, -0.12, -0.5), Vector3(0, 0.12, 0.5), Vector3(0, -0.12, 0.5)]]:
			for v in q:
				st.add_vertex(p + v)
		d2 += 20.0
	var lampes: MeshInstance3D = _maillage(st, _mat_lampe, "Lampes")
	lampes.set_meta(MeshMerge.SANS_FUSION, true)
	lampes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# portail : anneau de béton en saillie dans la falaise
	var por: Node3D = Node3D.new()
	por.name = "Portail"
	por.set_meta("portee_loin", true)
	_enfant(por)
	var yp: float = y_voie(portail_d) - 0.45 + R_TUNNEL * 0.62
	var pente: float = atan(pente_voie(portail_d))
	RemonteeKit.cylindre(por, R_TUNNEL + 0.5, R_TUNNEL + 0.5, 3.0,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + pente), Vector3(0, yp, -portail_d + 1.0)), "beton", 20)
	MeshMerge.merge(por, [], "Portail")


## Gares (lot 1 : quai en gradins de caillebotis de chaque côté de la voie, bâtiment simple). Détail au lot 2.
func _gare_funi(aval: bool) -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAval" if aval else "GareAmont"
	_enfant(g)
	var L: float = longueur_h()
	var dq: float = _x_quai(aval)
	var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
	var n: int = VehiculeFunival.N_COMP
	var lc: float = lq / float(n)
	for k in range(n):
		var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
		var y: float = VehiculeFunival.y_plancher_monde(self, d)
		var sol: float = _sol(3.0, -d)
		for sx in [-1.0, 1.0]:
			var x: float = sx * (VehiculeFunival.DEMI_LARGEUR + 0.05 + 1.5)
			var haut: float = maxf(y - sol, 0.3) + 0.2
			RemonteeKit.boite_en(g, Vector3(3.0, haut, lc + 0.05), Vector3(x, y - haut * 0.5, -d), "caillebotis" if aval else "beton")
	# bâtiment : aval bas bardé de bois gris, amont bardé anthracite (photos) ; au-dessus de la voie à l'amont
	var yb: float = terrain(0.0 if aval else L)
	if aval:
		RemonteeKit.boite_en(g, Vector3(14.0, 3.4, 9.0), Vector3(-9.0, yb + 1.7, -(dq - 4.0)), "bois_fonce")
		RemonteeKit.boite_en(g, Vector3(15.0, 0.35, 10.0), Vector3(-9.0, yb + 3.55, -(dq - 4.0)), "peinture_anthracite")
	else:
		RemonteeKit.boite_en(g, Vector3(12.0, 7.0, lq + 6.0), Vector3(0, y_voie(dq) + 6.0, -dq), "peinture_anthracite")
		RemonteeKit.boite_en(g, Vector3(12.1, 1.2, lq + 6.1), Vector3(0, y_voie(dq) + 5.0, -dq), "vitrage_sombre")
	MeshMerge.merge(g, [], "Gare")


func _collisions_funi() -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsLigne"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	_enfant(corps)
	for aval in [true, false]:
		var dq: float = _x_quai(aval)
		var lq: float = VehiculeFunival.DEMI_L * 2.0 + 2.0
		var n: int = VehiculeFunival.N_COMP
		var lc: float = lq / float(n)
		for k in range(n):
			var d: float = dq - lq * 0.5 + lc * (float(k) + 0.5)
			var y: float = VehiculeFunival.y_plancher_monde(self, d)
			for sx in [-1.0, 1.0]:
				var cs: CollisionShape3D = CollisionShape3D.new()
				var bx: BoxShape3D = BoxShape3D.new()
				bx.size = Vector3(3.0, 0.4, lc + 0.05)
				cs.shape = bx
				cs.position = Vector3(sx * (VehiculeFunival.DEMI_LARGEUR + 0.05 + 1.5), y - 0.2, -d)
				corps.add_child(cs)


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
