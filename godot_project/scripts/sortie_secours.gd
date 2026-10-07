class_name SortieSecours
extends Node3D
## Sortie de secours du tunnel, de la chambre du galet 145 jusqu'à la
## piste (Kevin, 07/10/2026 : « tu peux percer la sortie de secours dans le
## tunnel, et sortir sur la piste ; sur la piste la sortie est circulaire
## comme le tunnel, je t'ai mis sa position » — Google Earth : 45°26′04,26″ N
## 6°54′02,60″ E, entre les pistes Double M et Face).
##
## Le débouché est posé sur le relief du jeu à cette position
## (audit_physique/sortie_secours.sage : x 135,95, z 1 933,54). Google Earth
## y donne 2 655,89 m, le relief IGN du jeu 2 643,5 m : la galerie DESCEND
## donc de la chambre (sol à 2 661 m) vers le portail.
##
## Galerie (valeurs du simulateur, aucune donnée sur la vraie) : tube
## circulaire de 3 m de diamètre, sol plat de 1,9 m, 8 m perpendiculaires à
## la paroi droite puis tout droit vers le portail ; le sol suit le relief
## 4,3 m dessous, en rampe de 36 % au plus, sans jamais remonter, jusqu'au
## niveau du portail ; là où le relief ne couvre plus le tube (les derniers
## 40 m, plats), un remblai le couvre (ReliefBuilder « remblais ») et
## une aire plane le reçoit devant le portail (« plats »). Lampes tous les
## 12 m. Portail : mur de tête en béton percé d'un cercle.

const PORTAIL_XZ: Vector2 = Vector2(135.95, 1933.54)
const R_GAL: float = 1.50                 # rayon du tube
const H_AXE: float = 1.15                 # axe à 1,15 m au-dessus du sol (sol plat de 1,93 m)
const COUVERTURE: float = 4.30            # sol de la galerie sous le relief (tube 2,65 m + 1,65 m)
const PENTE_MAX: float = 0.36
const PERP: float = 8.0                   # premier tronçon, perpendiculaire à la paroi
const PAS: float = 2.0
const PAS_LAMPE: float = 12.0
const L_TETE: float = 5.0                 # mur de tête : largeur, hauteur, épaisseur
const H_TETE: float = 4.6
const E_TETE: float = 0.5
const Y_OUVERTURE: float = -1.48          # sol de la galerie = dessus de la passerelle (repère du tunnel)

var pret: bool = false
var sol: PackedVector3Array = PackedVector3Array()   # points du sol de la galerie
var portail: Vector3 = Vector3.ZERO                  # sol au milieu du mur de tête
var _dir_fin: Vector3 = Vector3.FORWARD              # direction de sortie (horizontale)
var _tun: TunnelBuilder = null
var _lampes: Array = []
var _xf_chambre: Transform3D = Transform3D.IDENTITY
var _r_tunnel: float = 1.95


func construire(tun: TunnelBuilder, relief: ReliefBuilder) -> void:
	_tun = tun
	var xf: Transform3D = tun.transform_at(TunnelBuilder.SORTIE_SECOURS_S)
	_xf_chambre = xf
	_r_tunnel = tun.tunnel_radius
	# le sol part de la paroi du tunnel à sa hauteur (le tube est rond : la
	# paroi est à x = √(R² − y²) à cette hauteur, pas à R)
	var x_paroi: float = sqrt(_r_tunnel * _r_tunnel - Y_OUVERTURE * Y_OUVERTURE)
	var f0: Vector3 = xf.origin + xf.basis.x * x_paroi + xf.basis.y * Y_OUVERTURE
	var d1: Vector3 = Vector3(xf.basis.x.x, 0.0, xf.basis.x.z).normalized()
	var p1: Vector3 = f0 + d1 * PERP
	var y_port: float = relief.hauteur(PORTAIL_XZ.x, PORTAIL_XZ.y)
	portail = Vector3(PORTAIL_XZ.x, y_port, PORTAIL_XZ.y)
	var d2: Vector3 = Vector3(portail.x - p1.x, 0.0, portail.z - p1.z)
	var l2: float = d2.length()
	d2 /= l2
	_dir_fin = d2
	# sol : premier tronçon plat, puis descente contrainte par le relief
	sol.clear()
	sol.append(f0)
	sol.append(p1)
	var y: float = p1.y
	var n: int = int(ceil(l2 / PAS))
	for i in range(1, n + 1):
		var u: float = minf(float(i) * PAS, l2)
		var q: Vector3 = p1 + d2 * u
		var reste: float = l2 - u
		var cible: float = minf(y, relief.hauteur(q.x, q.z) - COUVERTURE)
		cible = maxf(cible, y - PENTE_MAX * PAS)
		cible = maxf(cible, y_port)
		y = cible if reste > 0.01 else y_port
		sol.append(Vector3(q.x, y, q.z))
	_construire_tube()
	_construire_tete()
	pret = true


# --- maillages ---------------------------------------------------------------------

func _beton(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _repere(i: int) -> Array:
	var a: Vector3 = sol[maxi(i - 1, 0)]
	var b: Vector3 = sol[mini(i + 1, sol.size() - 1)]
	var t: Vector3 = (b - a).normalized()
	var r: Vector3 = Vector3(t.z, 0.0, -t.x).normalized()
	if r.length() < 0.5:
		r = Vector3.RIGHT
	var up: Vector3 = r.cross(t).normalized()
	return [t, r, up]


func _construire_tube() -> void:
	var paroi: StandardMaterial3D = _beton(Color(0.58, 0.58, 0.56))
	var dalle: StandardMaterial3D = _beton(Color(0.42, 0.42, 0.41))
	var ns: int = 20
	var st: SurfaceTool = null
	var debut: int = 0
	var lampe_mesh: BoxMesh = BoxMesh.new()
	lampe_mesh.size = Vector3(0.12, 0.08, 0.9)
	var lampe_mat: StandardMaterial3D = StandardMaterial3D.new()
	lampe_mat.albedo_color = Color(0.95, 0.95, 0.90)
	lampe_mat.emission_enabled = true
	lampe_mat.emission = Color(1.0, 0.98, 0.90)
	lampe_mat.emission_energy_multiplier = 2.5
	lampe_mesh.material = lampe_mat
	var depuis_lampe: float = PAS_LAMPE * 0.5
	var anneaux: Array = []
	for i in range(sol.size()):
		var rep: Array = _repere(i)
		var c: Vector3 = sol[i] + Vector3.UP * H_AXE
		var ring: PackedVector3Array = PackedVector3Array()
		for k in range(ns):
			var a: float = TAU * float(k) / float(ns)
			ring.append(_hors_du_tunnel(c + (rep[1] as Vector3) * (R_GAL * cos(a)) + (rep[2] as Vector3) * (R_GAL * sin(a))))
		anneaux.append(ring)
		# sol plat : dalle entre deux points
		if i > 0:
			var seg: Vector3 = sol[i] - sol[i - 1]
			var l: float = seg.length()
			if l > 1e-3:
				var mi: MeshInstance3D = MeshInstance3D.new()
				var bm: BoxMesh = BoxMesh.new()
				bm.size = Vector3(1.96, 0.30, l + 0.04)
				bm.material = dalle
				mi.mesh = bm
				var t: Vector3 = seg / l
				var r: Vector3 = Vector3(t.z, 0.0, -t.x).normalized()
				mi.transform = Transform3D(Basis(r, r.cross(t).normalized(), -t),
					(sol[i] + sol[i - 1]) * 0.5 - Vector3.UP * 0.15)
				mi.name = "DalleGalerie"
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				depuis_lampe += l
				if depuis_lampe >= PAS_LAMPE and i < sol.size() - 2:
					depuis_lampe = 0.0
					var lm: MeshInstance3D = MeshInstance3D.new()
					lm.mesh = lampe_mesh
					lm.transform = Transform3D(Basis(r, Vector3.UP, -t), c + Vector3.UP * (R_GAL - 0.10))
					lm.name = "LampeGalerie"
					lm.set_meta("sans_collision", true)
					add_child(lm)
					var ol: OmniLight3D = OmniLight3D.new()
					ol.light_color = Color(1.0, 0.97, 0.88)
					ol.light_energy = 1.1
					ol.omni_range = 9.0
					ol.omni_attenuation = 1.4
					ol.shadow_enabled = false
					ol.position = c + Vector3.UP * (R_GAL - 0.35)
					add_child(ol)
					_lampes.append(ol)
	# tube en tronçons de 12 anneaux (quota de lampes par objet en rendu web)
	for i in range(1, anneaux.size()):
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			debut = i
		var r0: PackedVector3Array = anneaux[i - 1]
		var r1: PackedVector3Array = anneaux[i]
		for k in range(ns):
			var k1: int = (k + 1) % ns
			st.set_uv(Vector2(float(k) / ns, 0.0))
			st.add_vertex(r0[k])
			st.add_vertex(r1[k])
			st.add_vertex(r1[k1])
			st.add_vertex(r0[k])
			st.add_vertex(r1[k1])
			st.add_vertex(r0[k1])
		if i - debut >= 12 or i == anneaux.size() - 1:
			st.generate_normals()
			st.set_material(paroi)
			var mi2: MeshInstance3D = MeshInstance3D.new()
			mi2.mesh = st.commit()
			mi2.name = "Galerie"
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi2)
			st = null


## Un point du tube de la galerie qui tomberait DANS le tunnel (premiers
## anneaux, près de la paroi) est ramené sur la paroi : la galerie se
## raccorde au tube rond sans dépasser dedans.
func _hors_du_tunnel(p: Vector3) -> Vector3:
	var l: Vector3 = _xf_chambre.affine_inverse() * p
	if l.x <= 0.0 or l.x > _r_tunnel + 0.02 or absf(l.y) >= _r_tunnel:
		return p
	var x_paroi: float = sqrt(_r_tunnel * _r_tunnel - l.y * l.y)
	if l.x < x_paroi:
		l.x = x_paroi + 0.01
		return _xf_chambre * l
	return p


## Mur de tête vertical, percé d'un cercle, au débouché.
func _construire_tete() -> void:
	var c: Vector3 = portail + Vector3.UP * H_AXE
	var t: Vector3 = _dir_fin
	var r: Vector3 = Vector3(t.z, 0.0, -t.x).normalized()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ns: int = 24
	var rc: float = R_GAL + 0.04
	var bas: float = -H_AXE - 0.2                      # sous le sol
	for face in [-1.0, 1.0]:
		var o: Vector3 = c + t * (face * E_TETE * 0.5)
		for k in range(ns):
			var a0: float = TAU * float(k) / ns
			var a1: float = TAU * float(k + 1) / ns
			var pc0: Vector3 = o + r * (rc * cos(a0)) + Vector3.UP * (rc * sin(a0))
			var pc1: Vector3 = o + r * (rc * cos(a1)) + Vector3.UP * (rc * sin(a1))
			var pe0: Vector3 = o + r * _bord(a0).x + Vector3.UP * _bord(a0).y
			var pe1: Vector3 = o + r * _bord(a1).x + Vector3.UP * _bord(a1).y
			for v in [pc0, pe0, pe1, pc0, pe1, pc1]:
				st.add_vertex(v)
		# le cadre descend sous le sol : bas plein
		var g0: Vector3 = o + r * (-L_TETE * 0.5) + Vector3.UP * bas
		var g1: Vector3 = o + r * (L_TETE * 0.5) + Vector3.UP * bas
		var h0: Vector3 = o + r * (-L_TETE * 0.5) + Vector3.UP * (-H_AXE + 0.0)
		var h1: Vector3 = o + r * (L_TETE * 0.5) + Vector3.UP * (-H_AXE + 0.0)
		for v in [g0, g1, h1, g0, h1, h0]:
			st.add_vertex(v)
	# chants du mur (haut et côtés) et du trou
	var coins: Array = []
	for e in [[-1.0, bas], [-1.0, H_TETE - H_AXE], [1.0, H_TETE - H_AXE], [1.0, bas]]:
		coins.append(c + r * (e[0] * L_TETE * 0.5) + Vector3.UP * e[1])
	for k in range(3):
		var a: Vector3 = coins[k]
		var b: Vector3 = coins[k + 1]
		for v in [a - t * (E_TETE * 0.5), b - t * (E_TETE * 0.5), b + t * (E_TETE * 0.5),
				a - t * (E_TETE * 0.5), b + t * (E_TETE * 0.5), a + t * (E_TETE * 0.5)]:
			st.add_vertex(v)
	for k in range(ns):
		var a0: float = TAU * float(k) / ns
		var a1: float = TAU * float(k + 1) / ns
		var q0: Vector3 = c + r * (rc * cos(a0)) + Vector3.UP * (rc * sin(a0))
		var q1: Vector3 = c + r * (rc * cos(a1)) + Vector3.UP * (rc * sin(a1))
		for v in [q0 - t * (E_TETE * 0.5), q1 - t * (E_TETE * 0.5), q1 + t * (E_TETE * 0.5),
				q0 - t * (E_TETE * 0.5), q1 + t * (E_TETE * 0.5), q0 + t * (E_TETE * 0.5)]:
			st.add_vertex(v)
	st.generate_normals()
	st.set_material(_beton(Color(0.66, 0.66, 0.63)))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "MurDeTete"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Point du bord du mur de tête (repère r, haut) à l'angle a du cercle.
func _bord(a: float) -> Vector2:
	var hx: float = L_TETE * 0.5
	var hy_h: float = H_TETE - H_AXE
	var hy_b: float = -H_AXE - 0.2
	var dx: float = cos(a)
	var dy: float = sin(a)
	var kx: float = INF if absf(dx) < 1e-6 else hx / absf(dx)
	var ky: float = INF if absf(dy) < 1e-6 else (hy_h if dy > 0.0 else -hy_b) / absf(dy)
	var k: float = minf(kx, ky)
	return Vector2(dx * k, dy * k)


# --- pour le relief, les collisions, le skieur -----------------------------------------

## Aménagements du relief : aire plane devant le portail, remblai sur le
## tube là où le relief ne le couvre pas.
func amenagement_relief(relief: ReliefBuilder) -> Dictionary:
	var t: Vector3 = _dir_fin
	var r: Vector3 = Vector3(t.z, 0.0, -t.x).normalized()
	var xz := func(p: Vector3) -> Vector2:
		return Vector2(p.x, p.z)
	# aire : 16 m de large, du mur de tête (0,5 m derrière) à 14 m devant,
	# 5 cm sous le sol du tube ; derrière le mur, le relief est RETIRÉ dans
	# l'emprise du tube sur 4 m (« trou », comme sous un bâtiment) : tout
	# fondu du relief y passait dans le tube
	var aire: PackedVector2Array = PackedVector2Array([
		xz.call(portail - t * 0.5 - r * 8.0), xz.call(portail - t * 0.5 + r * 8.0),
		xz.call(portail + t * 14.0 + r * 8.0), xz.call(portail + t * 14.0 - r * 8.0)])
	var tranchee: PackedVector2Array = PackedVector2Array([
		xz.call(portail - t * 4.5 - r * 1.7), xz.call(portail - t * 4.5 + r * 1.7),
		xz.call(portail - t * 0.3 + r * 1.7), xz.call(portail - t * 0.3 - r * 1.7)])
	var remblais: Array = []
	var i: int = 2
	while i < sol.size() - 1:
		var j: int = mini(i + 5, sol.size() - 1)
		var a: Vector3 = sol[i]
		var b: Vector3 = sol[j]
		var seg: Vector3 = b - a
		var fin: bool = j == sol.size() - 1
		if fin:
			b = b - seg.normalized() * 2.0            # s'arrête 2 m avant le mur de tête (fondu 1,5 m)
			seg = b - a
		var l: float = seg.length()
		if l > 0.5:
			var tt: Vector3 = seg / l
			var rr: Vector3 = Vector3(tt.z, 0.0, -tt.x).normalized()
			var y_tube: float = maxf(a.y, b.y) + H_AXE + R_GAL + 1.2
			var couvert: bool = true
			for kk in range(i, j + 1):
				var q: Vector3 = sol[kk]
				if relief.hauteur(q.x, q.z) < y_tube:
					couvert = false
			if not couvert:
				remblais.append([PackedVector2Array([xz.call(a - rr * 4.5), xz.call(a + rr * 4.5),
					xz.call(b + rr * 4.5), xz.call(b - rr * 4.5)]), y_tube, 1.5 if fin else 5.0])
		i = j
	var bb: Rect2 = Rect2(Vector2(portail.x, portail.z), Vector2.ZERO)
	for p in sol:
		bb = bb.expand(Vector2(p.x, p.z))
	return {"rect": bb.grow(60.0), "trous": [tranchee], "plats": [[aire, portail.y - 0.05, 3.0]], "remblais": remblais}


## Zone des collisions : chambre et galerie.
func zone_aabb() -> AABB:
	var ab: AABB = AABB(sol[0], Vector3.ZERO)
	for p in sol:
		ab = ab.expand(p)
	return ab.grow(22.0)


## Rectangle (x, z) du relief à mettre en collision autour du portail.
func rect_terrain() -> Rect2:
	return Rect2(portail.x - 90.0, portail.z - 90.0, 180.0, 180.0)


## Points de passage du sol, de la chambre au-delà du portail (banc, AUTO).
func chemin_sortie() -> Array:
	var out: Array = []
	var acc: float = 99.0
	for i in range(sol.size()):
		if i > 0:
			acc += sol[i].distance_to(sol[i - 1])
		if acc >= 8.0 or i == sol.size() - 1:
			out.append(sol[i] + Vector3.UP * 0.05)
			acc = 0.0
	out.append(portail + _dir_fin * 7.0 + Vector3.UP * 0.05)
	return out


## Point sur la passerelle du tunnel, à `ds` de la chambre (banc, AUTO).
func point_passerelle(track: TrackBuilder, ds: float = 0.0) -> Vector3:
	var xf: Transform3D = _tun.transform_at(TunnelBuilder.SORTIE_SECOURS_S + ds)
	return xf.origin + xf.basis.x * (track.walkway_side * track.walkway_x) \
		+ xf.basis.y * (track.floor_y_local + track.slab_thickness + 0.12) + Vector3.UP * 0.2
