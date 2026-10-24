class_name TunnelPiste
extends Node3D
## Tunnel de la piste noire du Tunnel (Val d'Isère, Pissaillas) : percé dans
## l'arête au départ du TKD du 3000, il passe de la face ouest à la face est
## (tracé OpenStreetMap : 63 m, sol presque plat vers 2 941 m). Retour
## d'utilisateur, 24/10/2026 : « la piste noire du Tunnel, avec un tunnel dans la
## montagne » — « ben creuse ».
## Tête de chaque côté là où l'arête couvre la voûte d'au moins 1 m ;
## au-delà, tranchée d'accès rabotée au niveau du sol ; près des têtes, le
## relief est retiré au-dessus du tube (« trou » de la pièce fine). Section :
## sol de 5 m, piédroits de 2 m, voûte en plein cintre (4,5 m sous clé).

const A_LL: Vector2 = Vector2(45.4187081, 7.0199413)    # bouche ouest (lat, lon)
const B_LL: Vector2 = Vector2(45.4186695, 7.0207474)    # bouche est
const DEMI: float = 2.5           # demi-largeur du sol
const H_PIED: float = 2.0         # hauteur des piédroits
const H_CLE: float = DEMI + H_PIED
const COUVERTURE: float = 1.0     # roche au-dessus de la clé aux têtes
const PAS: float = 1.0

var relief: ReliefBuilder = null
var a: Vector3                    # sol à la bouche ouest
var b: Vector3                    # sol à la bouche est
var t: Vector3                    # direction ouest → est (horizontale)
var r: Vector3                    # travers
var longueur: float = 0.0
var u_a: float = 0.0              # têtes (abscisses le long de l'axe, depuis a)
var u_b: float = 0.0


func _axe(u: float) -> Vector3:
	var p: Vector3 = a + t * u
	p.y = lerpf(a.y, b.y, clampf(u / longueur, 0.0, 1.0))
	return p


## Relief au-dessus de l'axe, à l'abscisse u.
func _dessus(u: float) -> float:
	var p: Vector3 = a + t * u
	return relief.hauteur(p.x, p.z)


## Aménagement du relief (appelé quand hauteur() répond) ; construit le tube.
func amenagement_relief(rel: ReliefBuilder) -> Dictionary:
	relief = rel
	var pa: Vector2 = RemonteesDomaine.monde(A_LL.x, A_LL.y)
	var pb: Vector2 = RemonteesDomaine.monde(B_LL.x, B_LL.y)
	if not relief.dans_le_bloc(pa.x, pa.y) or not relief.dans_le_bloc(pb.x, pb.y):
		return {}
	a = Vector3(pa.x, relief.hauteur(pa.x, pa.y), pa.y)
	b = Vector3(pb.x, relief.hauteur(pb.x, pb.y), pb.y)
	var d: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	longueur = d.length()
	t = d / longueur
	r = Vector3(t.z, 0.0, -t.x).normalized()
	# têtes : là où l'arête couvre la clé d'au moins COUVERTURE
	var seuil := func(u: float) -> bool:
		return _dessus(u) >= _axe(u).y + H_CLE + COUVERTURE
	u_a = longueur * 0.5
	var u: float = 0.0
	while u < longueur * 0.5:
		if seuil.call(u):
			u_a = u
			break
		u += 0.25
	u_b = longueur * 0.5
	u = longueur
	while u > longueur * 0.5:
		if seuil.call(u):
			u_b = u
			break
		u -= 0.25
	_construire()
	var xz := func(p: Vector3) -> Vector2:
		return Vector2(p.x, p.z)
	var w: float = DEMI + 0.6
	# tranchées d'accès : rabotées au niveau du sol, mètre par mètre
	var rabots: Array = []
	for bout in [[-10.0, u_a], [u_b, longueur + 10.0]]:
		var u0: float = bout[0]
		while u0 < float(bout[1]) - 0.05:
			var u1: float = minf(u0 + 1.0, bout[1])
			var p0: Vector3 = a + t * u0
			var p1: Vector3 = a + t * u1
			rabots.append([PackedVector2Array([xz.call(p0 - r * w), xz.call(p0 + r * w),
				xz.call(p1 + r * w), xz.call(p1 - r * w)]), _axe(clampf(u0, 0.0, longueur)).y - 0.05, 1.5])
			u0 = u1
	# relief retiré au-dessus du tube près des têtes (là où le fondu du
	# rabot et la pente de l'arête passeraient dans la voûte)
	var trous: Array = []
	for tete in [[u_a, 1.0], [u_b, -1.0]]:
		var u0b: float = tete[0]
		var sens: float = tete[1]
		var u_toit: float = u0b
		var uu: float = u0b
		while absf(uu - u0b) < longueur * 0.5:
			if _dessus(uu) >= _axe(uu).y + H_CLE + 2.5:
				u_toit = uu
				break
			uu += 0.25 * sens
		var q0: Vector3 = a + t * (u0b - sens * 0.3)
		var q1: Vector3 = a + t * (u_toit + sens * 2.5)
		trous.append(PackedVector2Array([xz.call(q0 - r * (DEMI + 0.3)), xz.call(q0 + r * (DEMI + 0.3)),
			xz.call(q1 + r * (DEMI + 0.3)), xz.call(q1 - r * (DEMI + 0.3))]))
	var bb: Rect2 = Rect2(xz.call(a), Vector2.ZERO).expand(xz.call(b))
	print("[TunnelPiste] %.0f m, têtes à %.1f et %.1f m, sol %.1f → %.1f m" % [longueur, u_a, u_b, a.y, b.y])
	return {"rect": bb.grow(40.0), "trous": trous, "rabots": rabots}


## Triangle posé avec sa normale, dans le sens horaire vu du côté de la
## normale (face avant pour Godot : sinon, en double face, la normale est
## retournée et la face sort noire).
static func _tri(st: SurfaceTool, p: Vector3, q: Vector3, w: Vector3, n: Vector3) -> void:
	var ordre: Array = [p, q, w] if (q - p).cross(w - p).dot(n) < 0.0 else [p, w, q]
	for v in ordre:
		st.set_normal(n)
		st.add_vertex(v)


func _roche() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.35, 0.33)
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Section : demi-profil puis l'autre moitié (piédroit gauche, voûte, piédroit droit).
func _section() -> Array:
	var pts: Array = [Vector2(-DEMI, 0.0), Vector2(-DEMI, H_PIED)]
	for k in range(1, 12):
		var ang: float = PI - PI * float(k) / 12.0
		pts.append(Vector2(DEMI * cos(ang), H_PIED + DEMI * sin(ang)))
	pts.append(Vector2(DEMI, H_PIED))
	pts.append(Vector2(DEMI, 0.0))
	return pts


func _construire() -> void:
	var sec: Array = _section()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u: float = u_a - 0.3
	var anneaux: Array = []
	while true:
		var p: Vector3 = _axe(u)
		var ring: Array = []
		for s in sec:
			ring.append(p + r * (s as Vector2).x + Vector3.UP * (s as Vector2).y)
		anneaux.append(ring)
		if u >= u_b + 0.3:
			break
		u = minf(u + PAS, u_b + 0.3)
	for i in range(1, anneaux.size()):
		var r0: Array = anneaux[i - 1]
		var r1: Array = anneaux[i]
		var ax: Vector3 = (r0[0] + r0[r0.size() - 1]) * 0.5 + Vector3.UP * H_PIED     # centre de la voûte
		for k in range(sec.size() - 1):
			# normale vers l'intérieur : on voit la voûte du dedans
			var m: Vector3 = (r0[k] + r1[k + 1]) * 0.5
			var nn: Vector3 = ax - m
			nn = (nn - t * nn.dot(t)).normalized()
			_tri(st, r0[k], r1[k], r1[k + 1], nn)
			_tri(st, r0[k], r1[k + 1], r0[k + 1], nn)
	st.set_material(_roche())
	var tube: MeshInstance3D = MeshInstance3D.new()
	tube.name = "Voute"
	tube.mesh = st.commit()
	add_child(tube)
	# sol damé
	var neige: StandardMaterial3D = StandardMaterial3D.new()
	neige.albedo_color = Color(0.86, 0.87, 0.90)
	neige.roughness = 0.9
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsTunnel"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	add_child(corps)
	var lg: float = u_b - u_a + 0.6
	var c: Vector3 = (_axe(u_a) + _axe(u_b)) * 0.5
	var pente: float = (_axe(u_b).y - _axe(u_a).y) / maxf(u_b - u_a, 0.1)
	var tt: Vector3 = (t + Vector3.UP * pente).normalized()
	var bas: Basis = Basis.looking_at(tt, Vector3.UP)
	var boite := func(taille: Vector3, centre: Vector3, mat: Material) -> void:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var bs: BoxShape3D = BoxShape3D.new()
		bs.size = taille
		cs.shape = bs
		cs.transform = Transform3D(bas, centre)
		corps.add_child(cs)
		if mat != null:
			var mi: MeshInstance3D = MeshInstance3D.new()
			var bm: BoxMesh = BoxMesh.new()
			bm.size = taille
			bm.material = mat
			mi.mesh = bm
			mi.transform = Transform3D(bas, centre)
			add_child(mi)
	boite.call(Vector3(DEMI * 2.0, 0.4, lg), c - Vector3.UP * 0.2, neige)
	for sx in [-1.0, 1.0]:
		boite.call(Vector3(0.3, H_PIED, lg), c + r * (sx * (DEMI + 0.15)) + Vector3.UP * (H_PIED * 0.5), null)
	# têtes : murs de béton percés de la voûte
	for tete in [[u_a, -1.0], [u_b, 1.0]]:
		_tete(_axe(tete[0]), tete[1])
	# éclairage : une lampe tous les 15 m
	var n: int = maxi(1, int((u_b - u_a) / 15.0))
	for k in range(n):
		var ol: OmniLight3D = OmniLight3D.new()
		ol.light_color = Color(1.0, 0.95, 0.85)
		ol.light_energy = 1.4
		ol.omni_range = 12.0
		ol.shadow_enabled = false
		ol.position = _axe(lerpf(u_a, u_b, (k + 0.5) / n)) + Vector3.UP * (H_CLE - 0.3)
		add_child(ol)


## Mur de tête vertical (béton) percé de la section, côté `sens` (−1 ouest, +1 est).
func _tete(p: Vector3, sens: float) -> void:
	var beton: StandardMaterial3D = StandardMaterial3D.new()
	beton.albedo_color = Color(0.70, 0.69, 0.66)
	beton.roughness = 0.9
	# (face à l'ouest ou à l'est dans sa tranchée, le mur n'a que le ciel
	# pour lumière : un peu d'émission pour qu'il ne sorte pas noir)
	beton.emission_enabled = true
	beton.emission = Color(0.20, 0.20, 0.19)
	beton.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L: float = 5.0           # demi-largeur du mur
	var H: float = H_CLE + 2.5
	var o: Vector3 = p + t * (sens * 0.3)
	var sec: Array = _section()
	# bandes entre le contour de l'ouverture et le bord du mur (par rayons)
	var c: Vector3 = o + Vector3.UP * H_PIED
	for k in range(sec.size() - 1):
		var s0: Vector2 = sec[k]
		var s1: Vector2 = sec[k + 1]
		var e0: Vector2 = _bord_mur(s0, L, H)
		var e1: Vector2 = _bord_mur(s1, L, H)
		var w3 := func(q: Vector2) -> Vector3:
			return o + r * q.x + Vector3.UP * q.y
		_tri(st, w3.call(s0), w3.call(e0), w3.call(e1), t * sens)
		_tri(st, w3.call(s0), w3.call(e1), w3.call(s1), t * sens)
	# pied du mur sous le sol (raccord avec la tranchée)
	var g0: Vector3 = o + r * -L + Vector3.DOWN
	var g1: Vector3 = o + r * L + Vector3.DOWN
	_tri(st, g0, g1, o + r * L, t * sens)
	_tri(st, g0, o + r * L, o + r * -L, t * sens)
	st.set_material(beton)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Tete"
	mi.mesh = st.commit()
	add_child(mi)
	# bandeau au nom de la piste, au-dessus de l'ouverture
	var lab: Label3D = Label3D.new()
	lab.text = "TUNNEL"
	lab.font_size = 96
	lab.pixel_size = 0.006
	lab.modulate = Color(0.10, 0.10, 0.12)
	lab.outline_size = 0
	# (Label3D lisible de son +Z : tourné vers l'extérieur du tunnel)
	lab.transform = Transform3D(Basis.looking_at(-t * sens, Vector3.UP), o + t * (sens * 0.05) + Vector3.UP * (H_CLE + 1.1))
	add_child(lab)


## Point du bord du mur (rectangle 2L × H) dans la direction du point s de
## l'ouverture vu depuis le centre de la voûte.
func _bord_mur(s: Vector2, L: float, H: float) -> Vector2:
	var c: Vector2 = Vector2(0.0, H_PIED)
	var d: Vector2 = s - c
	if d.length() < 1e-4:
		return Vector2(0.0, H)
	var k: float = INF
	if absf(d.x) > 1e-5:
		k = minf(k, L / absf(d.x))
	if d.y > 1e-5:
		k = minf(k, (H - c.y) / d.y)
	elif d.y < -1e-5:
		k = minf(k, c.y / -d.y)
	return c + d * k
