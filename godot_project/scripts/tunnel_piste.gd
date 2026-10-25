class_name TunnelPiste
extends Node3D
## Tunnel de la piste noire du Tunnel (Val d'Isère, Pissaillas) : percé dans
## l'arête au départ du TKD du 3000, il passe de la face ouest à la face est
## (tracé OpenStreetMap : 63 m, sol presque plat vers 2 941 m). Retour
## d'utilisateur, 24/10/2026 : « la piste noire du Tunnel, avec un tunnel dans la
## montagne » — « ben creuse ».
## Tête de chaque côté là où l'arête couvre la voûte d'au moins 1 m ;
## au-delà, tranchée d'accès rabotée au niveau du sol ; près des têtes, le
## relief est retiré au-dessus du tube (« trou » de la pièce fine).
## D'après une vidéo de la piste (retour d'utilisateur, 25/10/2026) : un tube
## étroit, rond (≈ 3,2 m), cerclé d'acier rouillé tous les 80 cm, garni de
## tôles ondulées près des bouches, la roche nue boulonnée et grillagée au
## milieu ; en haut (bouche est, à l'arrivée du TKD du 3000), un cadre d'acier
## à deux portes ouvertes ; en bas (bouche ouest), la dernière cerce dépasse
## dans une tranchée de neige, coiffée d'une bâche orange ; sol de neige.

const A_LL: Vector2 = Vector2(45.4187081, 7.0199413)    # bouche ouest (lat, lon) : sortie
const B_LL: Vector2 = Vector2(45.4186695, 7.0207474)    # bouche est : entrée, portes
const R_TUBE: float = 1.6         # rayon du tube
const Y_CENTRE: float = 1.15      # centre du cercle au-dessus du sol de neige
const DEMI: float = 1.1           # demi-largeur du sol (corde du cercle)
const H_PIED: float = Y_CENTRE    # (repère du centre de la voûte)
const H_CLE: float = Y_CENTRE + R_TUBE
const PAS_CERCE: float = 0.8
const L_TOLE: float = 14.0        # tôles ondulées depuis chaque bouche
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
	var w: float = R_TUBE + 0.8
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
		trous.append(PackedVector2Array([xz.call(q0 - r * (R_TUBE + 0.4)), xz.call(q0 + r * (R_TUBE + 0.4)),
			xz.call(q1 + r * (R_TUBE + 0.4)), xz.call(q1 - r * (R_TUBE + 0.4))]))
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


## Section : le cercle, du sol à gauche au sol à droite par la voûte.
func _section() -> Array:
	var pts: Array = []
	var n: int = 20
	# de l'angle du sol gauche (sous l'horizontale) à celui du sol droit, en passant par le haut
	var ag: float = PI + asin(Y_CENTRE / R_TUBE)
	var ad: float = -asin(Y_CENTRE / R_TUBE)
	for k in range(n + 1):
		var ang: float = lerpf(ag, ad, float(k) / n)
		pts.append(Vector2(R_TUBE * cos(ang), Y_CENTRE + R_TUBE * sin(ang)))
	return pts


func _mat(c: Color, rugo: float, metal: float = 0.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rugo
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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
	var st_t: SurfaceTool = SurfaceTool.new()
	st_t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var us: Array = []
	var uu: float = u_a - 0.3
	while true:
		us.append(uu)
		if uu >= u_b + 0.3:
			break
		uu = minf(uu + PAS, u_b + 0.3)
	for i in range(1, anneaux.size()):
		var r0: Array = anneaux[i - 1]
		var r1: Array = anneaux[i]
		var um: float = (float(us[i - 1]) + float(us[i])) * 0.5
		var tole: bool = um - u_a < L_TOLE or u_b - um < L_TOLE
		var cible: SurfaceTool = st_t if tole else st
		var ax: Vector3 = _axe(um) + Vector3.UP * Y_CENTRE
		for k in range(sec.size() - 1):
			# normale vers l'intérieur : on voit la voûte du dedans
			var m: Vector3 = (r0[k] + r1[k + 1]) * 0.5
			var nn: Vector3 = ax - m
			nn = (nn - t * nn.dot(t)).normalized()
			_tri(cible, r0[k], r1[k], r1[k + 1], nn)
			_tri(cible, r0[k], r1[k + 1], r0[k + 1], nn)
	st.set_material(_roche())
	var tube: MeshInstance3D = MeshInstance3D.new()
	tube.name = "Voute"
	tube.mesh = st.commit()
	add_child(tube)
	st_t.set_material(_mat(Color(0.42, 0.24, 0.14), 0.75, 0.35))       # tôle ondulée rouillée
	var tole_mi: MeshInstance3D = MeshInstance3D.new()
	tole_mi.name = "Toles"
	tole_mi.mesh = st_t.commit()
	add_child(tole_mi)
	# cerces d'acier tous les 80 cm, un peu en dedans de la paroi
	var cerces: Node3D = Node3D.new()
	cerces.name = "Cerces"
	add_child(cerces)
	var u2: float = u_a + 0.2
	while u2 < u_b:
		var c0: Vector3 = _axe(u2) + Vector3.UP * Y_CENTRE
		var pts: PackedVector3Array = PackedVector3Array()
		for s in sec:
			var q: Vector2 = (s as Vector2) - Vector2(0, Y_CENTRE)
			pts.append(c0 + r * (q.x * 0.95) + Vector3.UP * (q.y * 0.95))
		RemonteeKit.tube(cerces, pts, 0.06, "rouille", 6)
		u2 += PAS_CERCE
	MeshMerge.merge(cerces, [], "Cerces")
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
	# têtes : sortie ouest sous une bâche, entrée est par des portes
	_sortie(_axe(u_a), -1.0)
	_entree(_axe(u_b), 1.0)
	# éclairage : une lampe tous les 15 m
	var n: int = maxi(1, int((u_b - u_a) / 15.0))
	for k in range(n):
		var ol: OmniLight3D = OmniLight3D.new()
		ol.light_color = Color(1.0, 0.95, 0.85)
		ol.light_energy = 0.6
		ol.omni_range = 9.0
		ol.shadow_enabled = false
		ol.position = _axe(lerpf(u_a, u_b, (k + 0.5) / n)) + Vector3.UP * (H_CLE - 0.3)
		add_child(ol)


## Entrée (bouche est, en haut) : cadre d'acier rectangulaire noir, deux
## portes ouvertes rabattues contre la neige, bracons de bois.
func _entree(p: Vector3, sens: float) -> void:
	var g: Node3D = Node3D.new()
	g.name = "Entree"
	g.transform = Transform3D(Basis(r, Vector3.UP, t * sens), p + t * (sens * 0.4))
	add_child(g)
	var w: float = 1.2
	var h: float = 2.5
	# cadre (montants, linteau) et tôle de fermeture entre cadre et tube
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.18, h, 0.25), Vector3(sx * (w + 0.09), h * 0.5, 0), "noir_mat")
	RemonteeKit.boite_en(g, Vector3(2.0 * w + 0.36, 0.25, 0.25), Vector3(0, h + 0.12, 0), "noir_mat")
	RemonteeKit.boite_en(g, Vector3(2.0 * w + 1.6, 1.2, 0.08), Vector3(0, h + 0.85, -0.1), "noir_mat")
	for sx2 in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.8, h + 1.4, 0.08), Vector3(sx2 * (w + 0.58), (h + 1.4) * 0.5, -0.1), "noir_mat")
	# deux battants ouverts vers l'extérieur (≈ 110°), panneau blanc sur l'un
	for sx3 in [-1.0, 1.0]:
		var bat: Node3D = Node3D.new()
		bat.position = Vector3(sx3 * w, 0, 0.13)
		bat.rotation.y = sx3 * deg_to_rad(-110.0)
		g.add_child(bat)
		RemonteeKit.boite_en(bat, Vector3(w, h - 0.05, 0.06), Vector3(-sx3 * w * 0.5, h * 0.5, 0), "noir_mat")
		if sx3 > 0.0:
			RemonteeKit.boite_en(bat, Vector3(0.6, 0.8, 0.01), Vector3(-w * 0.5, 1.5, 0.04), "blanc_plaque")
		# bracon de bois qui la tient ouverte
		RemonteeKit.barre(g, Vector3(sx3 * (w + 0.6), 0.0, 1.2), Vector3(sx3 * (w + 0.3), 1.6, 0.6), 0.04, "bois_meleze", 6)


## Sortie (bouche ouest, en bas) : la dernière cerce dépasse dans une tranchée
## de neige, coiffée d'une bâche orange tendue sur des arceaux.
func _sortie(p: Vector3, sens: float) -> void:
	var g: Node3D = Node3D.new()
	g.name = "Sortie"
	g.transform = Transform3D(Basis(r, Vector3.UP, t * sens), p)
	add_child(g)
	var sec: Array = _section()
	for k3 in range(3):
		var z: float = 0.3 + k3 * 0.8
		var pts: PackedVector3Array = PackedVector3Array()
		for s in sec:
			pts.append(Vector3((s as Vector2).x, (s as Vector2).y, z))
		RemonteeKit.tube(g, pts, 0.09, "rouille", 6)
	# bâche : demi-cylindre orange au-dessus des arceaux, qui retombe sur les côtés
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 14
	var rb: float = R_TUBE + 0.12
	for k in range(n):
		var a0: float = lerpf(PI * 0.05, PI * 0.95, float(k) / n)
		var a1: float = lerpf(PI * 0.05, PI * 0.95, float(k + 1) / n)
		var p0: Vector3 = Vector3(rb * cos(a0), Y_CENTRE + rb * sin(a0), 0.0)
		var p1: Vector3 = Vector3(rb * cos(a1), Y_CENTRE + rb * sin(a1), 0.0)
		var q0: Vector3 = p0 + Vector3(0, -0.15, 2.4)
		var q1: Vector3 = p1 + Vector3(0, -0.15, 2.4)
		var nn: Vector3 = Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0)
		_tri(st, p0, q0, q1, nn)
		_tri(st, p0, q1, p1, nn)
	var mb: StandardMaterial3D = _mat(Color(0.95, 0.38, 0.08), 0.85)
	mb.emission_enabled = true                 # bâche translucide au soleil
	mb.emission = Color(0.35, 0.12, 0.02)
	st.set_material(mb)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Bache"
	mi.mesh = st.commit()
	g.add_child(mi)
	# sangles vertes
	for z2 in [0.6, 1.4, 2.2]:
		RemonteeKit.tube(g, RemonteeKit.arc(Vector3(0, Y_CENTRE, z2), Vector3.RIGHT, Vector3.UP, rb + 0.03, PI * 0.05, PI * 0.95, 12), 0.015, "vert_treillis", 4)


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
