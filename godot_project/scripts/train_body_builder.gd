class_name TrainBodyBuilder
extends RefCounted
## Carrosserie des rames Perce-Neige — modèle procédural d'après les photos
## du 2026-04-26 (sons/photos) : tube Ø 3,44 m en tôle GRISE nervurée
## (anneaux circonférentiels tous les ~1,9 m), hublots hauts à coins
## arrondis alternés avec trois portes par face, extrémités JAUNES en
## calotte bombée (pare-brise rectangulaire centré, deux baies étroites de
## portes de secours, grille noire, deux feux ronds en bas), fond PLAT à
## ~80 % du diamètre juste au-dessus des rails, bogies apparents.
##
## Repère : LOCAL cabine (origine = centre tunnel − 0,15 m, cf. cabin.gd),
## forward = −Z. Le tube est concentrique au tunnel (rayon 1,72 dans un
## alésage de 1,95) ; il est COUPÉ à Y_CUT, 7 cm au-dessus de la table de
## roulement (rail_head local = −0,58) : plus rien ne passe sous les rails.
## Le plancher intérieur (Y_FLOOR) est au niveau des quais-escaliers.

const R_BODY: float = 1.72          # rayon du tube
const Y_CENTER: float = 0.20        # axe du tube (monde +0,05)
const Y_CUT: float = -0.51          # fond plat (monde −0,66 ; rails à −0,73)
const Y_FLOOR: float = -0.45        # plancher intérieur
const Y_RAIL_HEAD: float = -0.58    # table de roulement (monde −0,73)
const CAP_LEN: float = 1.00         # profondeur de la calotte bombée
const GAP: float = 0.50             # jeu entre les deux voitures
const RIB_W: float = 0.22           # largeur d'un anneau
const RIB_H: float = 0.035          # saillie d'un anneau
const PANEL_L: float = 1.63         # longueur d'un panneau (hublot ou porte)
const END_BLANK: float = 0.77       # tôle pleine aux extrémités du tube
const D_THETA_DEG: float = 5.0      # résolution angulaire du tube
const CAP_THETA_DEG: float = 2.5    # résolution angulaire de la calotte (bords des vitres)
const CAP_N_T: int = 36             # anneaux de la calotte
const COL_L: float = 0.25           # résolution longitudinale
# Fenêtres : angle depuis le sommet du tube (°) ; hublots hauts et étroits
const WIN_T0: float = 24.0
const WIN_T1: float = 76.0
const WIN_MARGIN: float = 0.25      # marge longitudinale dans un panneau
# Calotte : pare-brise et baies latérales définis en PROJECTION FRONTALE
# (x, y − Y_CENTER), comme on les voit sur les photos : rectangles à coins
# arrondis, pare-brise centré en haut, deux baies étroites de chaque côté.
const WS_HALF_W: float = 0.60       # demi-largeur du pare-brise
const WS_Y0: float = 0.50           # bas / haut du pare-brise (au-dessus de l'axe)
const WS_Y1: float = 1.32
const SIDE_X0: float = 0.92         # baies latérales (portes de secours)
const SIDE_X1: float = 1.36
const SIDE_Y0: float = 0.05
const SIDE_Y1: float = 1.15
const CAP_CORNER: float = 0.13      # rayon d'arrondi (par cellule)


static func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	return m


static func materials() -> Dictionary:
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.10, 0.14, 0.19, 0.62)
	glass.roughness = 0.08
	glass.metallic = 0.1
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.emission_enabled = true
	glass.emission = Color(0.55, 0.50, 0.38)
	glass.emission_energy_multiplier = 0.35
	var lamp_off: StandardMaterial3D = _mat(Color(0.12, 0.12, 0.12), 0.35, 0.2)
	var lamp_on: StandardMaterial3D = _mat(Color(1.0, 0.97, 0.85), 0.2, 0.0)
	lamp_on.emission_enabled = true
	lamp_on.emission = Color(1.0, 0.95, 0.80)
	lamp_on.emission_energy_multiplier = 4.0
	var tail_on: StandardMaterial3D = _mat(Color(0.9, 0.15, 0.10), 0.3, 0.0)
	tail_on.emission_enabled = true
	tail_on.emission = Color(1.0, 0.2, 0.12)
	tail_on.emission_energy_multiplier = 2.5
	return {
		"body": _mat(Color(0.60, 0.61, 0.60), 0.55, 0.45),      # tôle alu grise
		"door": _mat(Color(0.66, 0.67, 0.66), 0.50, 0.45),      # vantaux, un ton plus clair
		"rib": _mat(Color(0.40, 0.41, 0.42), 0.60, 0.50),       # anneaux
		"yellow": _mat(Color(0.94, 0.80, 0.08), 0.42, 0.10),    # calottes
		"glass": glass,
		"dark": _mat(Color(0.11, 0.11, 0.12), 0.75, 0.30),      # châssis, fond, soufflet
		"wheel": _mat(Color(0.22, 0.22, 0.23), 0.55, 0.70),
		"seam": _mat(Color(0.25, 0.25, 0.26), 0.70, 0.30),
		"lamp_off": lamp_off,
		"lamp_on": lamp_on,
		"tail_on": tail_on,
		"letters": _mat(Color(0.92, 0.92, 0.94), 0.45, 0.30),
	}


# --- petits outils SurfaceTool ------------------------------------------

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	st.set_normal(na); st.add_vertex(a)
	st.set_normal(nb); st.add_vertex(b)
	st.set_normal(nc); st.add_vertex(c)


## Quad a-b-c-d (sens trigonométrique vu de l'extérieur), normales lissées.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	_tri(st, a, b, c, na, nb, nc)
	_tri(st, a, c, d, na, nc, nd)


static func _quad_flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	_quad(st, a, b, c, d, n, n, n, n)


## Point du tube : θ depuis le sommet (rad, + vers +X), rayon r, abscisse z.
static func _tube_pt(theta: float, r: float, z: float) -> Vector3:
	return Vector3(r * sin(theta), Y_CENTER + r * cos(theta), z)


static func _tube_n(theta: float) -> Vector3:
	return Vector3(sin(theta), cos(theta), 0.0)


static func _theta_cut() -> float:
	return acos(clampf((Y_CUT - Y_CENTER) / R_BODY, -1.0, 1.0))


# --- plan des panneaux ----------------------------------------------------
# Retourne une liste de colonnes [{z0, z1, kind}] couvrant [z_a, z_b] ;
# kind ∈ blank | rib | win | door. Panneaux W D W D W D W entre anneaux.
static func _columns(z_a: float, z_b: float) -> Array:
	var cols: Array = []
	var kinds: Array = ["win", "door", "win", "door", "win", "door", "win"]
	var z: float = z_a
	cols.append({"z0": z, "z1": z + END_BLANK, "kind": "blank"})
	z += END_BLANK
	for k in kinds:
		cols.append({"z0": z, "z1": z + RIB_W, "kind": "rib"})
		z += RIB_W
		cols.append({"z0": z, "z1": z + PANEL_L, "kind": k})
		z += PANEL_L
	cols.append({"z0": z, "z1": z + RIB_W, "kind": "rib"})
	z += RIB_W
	cols.append({"z0": z, "z1": z_b, "kind": "blank"})
	return cols


## Une cellule (θ0..θ1, z0..z1) d'un panneau est-elle vitrée ?
static func _is_glass(kind: String, th_deg: float, u0: float, u1: float, plen: float) -> bool:
	if kind != "win" and kind != "door":
		return false
	var a: float = absf(th_deg)
	if a < WIN_T0 or a > WIN_T1:
		return false
	if u0 < WIN_MARGIN - 0.01 or u1 > plen - WIN_MARGIN + 0.01:
		return false
	# coins arrondis : on retire la cellule d'angle
	var near_edge_u: bool = u0 < WIN_MARGIN + COL_L * 0.5 or u1 > plen - WIN_MARGIN - COL_L * 0.5
	var near_edge_t: bool = a < WIN_T0 + D_THETA_DEG * 1.01 or a > WIN_T1 - D_THETA_DEG * 1.01
	return not (near_edge_u and near_edge_t)


# --- tube d'une voiture ------------------------------------------------------

static func _build_tube(mesh: ArrayMesh, mats: Dictionary, z_a: float, z_b: float,
		yellow_a: bool = false, yellow_b: bool = false) -> void:
	var th_cut: float = _theta_cut()
	var n_th: int = int(ceil(2.0 * rad_to_deg(th_cut) / D_THETA_DEG))
	var d_th: float = 2.0 * th_cut / float(n_th)
	var st_body: SurfaceTool = SurfaceTool.new()
	var st_door: SurfaceTool = SurfaceTool.new()
	var st_rib: SurfaceTool = SurfaceTool.new()
	var st_glass: SurfaceTool = SurfaceTool.new()
	var st_seam: SurfaceTool = SurfaceTool.new()
	var st_dark: SurfaceTool = SurfaceTool.new()
	var st_yellow: SurfaceTool = SurfaceTool.new()
	for st in [st_body, st_door, st_rib, st_glass, st_seam, st_dark, st_yellow]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cols: Array = _columns(z_a, z_b)
	for ci in range(cols.size()):
		var col: Dictionary = cols[ci]
		var kind: String = col["kind"]
		var z0c: float = col["z0"]
		var z1c: float = col["z1"]
		var plen: float = z1c - z0c
		# le jaune de la calotte déborde sur la tôle pleine d'extrémité
		# (photos : tout le premier tronçon, portes de secours comprises)
		var yellow_col: bool = kind == "blank" and ((ci == 0 and yellow_a) or (ci == cols.size() - 1 and yellow_b))
		var r: float = R_BODY + (RIB_H if kind == "rib" else 0.0)
		var n_sub: int = 1 if kind == "rib" or kind == "blank" else int(ceil(plen / COL_L))
		var dz: float = plen / float(n_sub)
		for j in range(n_sub):
			var z0: float = z0c + dz * j
			var z1: float = z0 + dz
			var u0: float = z0 - z0c
			var u1: float = z1 - z0c
			for i in range(n_th):
				var t0: float = -th_cut + d_th * i
				var t1: float = t0 + d_th
				var tm_deg: float = rad_to_deg(0.5 * (t0 + t1))
				var glass: bool = _is_glass(kind, tm_deg, u0, u1, plen)
				var st: SurfaceTool = st_glass if glass else (
					st_rib if kind == "rib" else (st_door if kind == "door" else (
						st_yellow if yellow_col else st_body)))
				var rr: float = r - (0.02 if glass else 0.0)
				# quad : (t0,z1) (t1,z1) (t1,z0) (t0,z0) → face vers l'extérieur
				_quad(st, _tube_pt(t0, rr, z1), _tube_pt(t1, rr, z1),
					_tube_pt(t1, rr, z0), _tube_pt(t0, rr, z0),
					_tube_n(t0), _tube_n(t1), _tube_n(t1), _tube_n(t0))
			# joint vertical des vantaux (deux battants) — fine bande sombre
			if kind == "door" and j == n_sub / 2:
				var zs: float = z0
				for i in range(n_th):
					var t0: float = -th_cut + d_th * i
					var t1: float = t0 + d_th
					var a_deg: float = absf(rad_to_deg(0.5 * (t0 + t1)))
					if a_deg < WIN_T0 - 2.0 or a_deg > WIN_T1 + 2.0:
						_quad(st_seam, _tube_pt(t0, r + 0.004, zs + 0.012),
							_tube_pt(t1, r + 0.004, zs + 0.012),
							_tube_pt(t1, r + 0.004, zs - 0.012),
							_tube_pt(t0, r + 0.004, zs - 0.012),
							_tube_n(t0), _tube_n(t1), _tube_n(t1), _tube_n(t0))
	# Fond plat (châssis) sur toute la longueur du tube
	var xw: float = R_BODY * sin(th_cut)
	_quad_flat(st_dark, Vector3(-xw, Y_CUT, z_a), Vector3(-xw, Y_CUT, z_b),
		Vector3(xw, Y_CUT, z_b), Vector3(xw, Y_CUT, z_a))
	# Parois d'extrémité côté attelage : disques gris fermant le tube
	st_body.set_material(mats["body"]); st_body.commit(mesh)
	st_yellow.set_material(mats["yellow"]); st_yellow.commit(mesh)
	st_door.set_material(mats["door"]); st_door.commit(mesh)
	st_rib.set_material(mats["rib"]); st_rib.commit(mesh)
	st_seam.set_material(mats["seam"]); st_seam.commit(mesh)
	st_dark.set_material(mats["dark"]); st_dark.commit(mesh)
	st_glass.set_material(mats["glass"]); st_glass.commit(mesh)


## Disque fermant le tube (section coupée) à l'abscisse z, normale vers dir_z.
static func _build_end_disc(mesh: ArrayMesh, mat: StandardMaterial3D, z: float, dir_z: float, r: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var th_cut: float = acos(clampf((Y_CUT - Y_CENTER) / r, -1.0, 1.0))
	var n_th: int = int(ceil(2.0 * rad_to_deg(th_cut) / D_THETA_DEG))
	var d_th: float = 2.0 * th_cut / float(n_th)
	var c: Vector3 = Vector3(0.0, Y_CENTER, z)
	var n: Vector3 = Vector3(0.0, 0.0, dir_z)
	for i in range(n_th):
		var t0: float = -th_cut + d_th * i
		var t1: float = t0 + d_th
		var a: Vector3 = _tube_pt(t0, r, z)
		var b: Vector3 = _tube_pt(t1, r, z)
		if dir_z < 0.0:
			_tri(st, c, b, a, n, n, n)
		else:
			_tri(st, c, a, b, n, n, n)
	# triangle du fond plat
	var a2: Vector3 = _tube_pt(-th_cut, r, z)
	var b2: Vector3 = _tube_pt(th_cut, r, z)
	if dir_z < 0.0:
		_tri(st, c, a2, b2, n, n, n)
	else:
		_tri(st, c, b2, a2, n, n, n)
	st.set_material(mat)
	st.commit(mesh)


# --- calotte bombée jaune ----------------------------------------------------
## z_join = abscisse du raccord au tube ; dir_z = −1 pour l'avant (pointe
## vers −Z), +1 pour l'arrière. Pare-brise et baies en verre.
static func _build_cap(mesh: ArrayMesh, mats: Dictionary, z_join: float, dir_z: float) -> void:
	var st_y: SurfaceTool = SurfaceTool.new()
	var st_g: SurfaceTool = SurfaceTool.new()
	var st_d: SurfaceTool = SurfaceTool.new()
	for st in [st_y, st_g, st_d]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_t: int = CAP_N_T
	var n_th: int = int(360.0 / CAP_THETA_DEG)
	var d_th: float = TAU / float(n_th)
	var d_t: float = (PI * 0.5) / float(n_t)

	var pt: Callable = func(theta: float, t: float) -> Vector3:
		var r: float = R_BODY * cos(t)
		var p: Vector3 = Vector3(r * sin(theta), Y_CENTER + r * cos(theta), z_join + dir_z * CAP_LEN * sin(t))
		if p.y < Y_CUT:
			p.y = Y_CUT
		return p
	var nrm: Callable = func(theta: float, t: float) -> Vector3:
		# normale de l'ellipsoïde (a=R_BODY radial, c=CAP_LEN axial)
		var v: Vector3 = Vector3(sin(theta) * cos(t) / R_BODY, cos(theta) * cos(t) / R_BODY,
			dir_z * sin(t) / CAP_LEN)
		return v.normalized()

	for k in range(n_t):
		var t0: float = d_t * k
		var t1: float = t0 + d_t
		var tm: float = rad_to_deg(0.5 * (t0 + t1))
		for i in range(n_th):
			var th0: float = -PI + d_th * i
			var th1: float = th0 + d_th
			var thm: float = rad_to_deg(0.5 * (th0 + th1))
			# cellule entièrement sous le fond plat → on la saute
			var p00: Vector3 = pt.call(th0, t0)
			var p10: Vector3 = pt.call(th1, t0)
			var p11: Vector3 = pt.call(th1, t1)
			var p01: Vector3 = pt.call(th0, t1)
			if p00.y <= Y_CUT and p10.y <= Y_CUT and p11.y <= Y_CUT and p01.y <= Y_CUT:
				continue
			# centre de la cellule en projection frontale
			var rm: float = R_BODY * cos(deg_to_rad(tm))
			var cx: float = absf(rm * sin(deg_to_rad(thm)))
			var cy: float = rm * cos(deg_to_rad(thm))       # au-dessus de l'axe
			var glass: bool = false
			if cx <= WS_HALF_W and cy >= WS_Y0 and cy <= WS_Y1:
				var corner: bool = (cx > WS_HALF_W - CAP_CORNER) \
					and (cy < WS_Y0 + CAP_CORNER or cy > WS_Y1 - CAP_CORNER)
				glass = not corner
			elif cx >= SIDE_X0 and cx <= SIDE_X1 and cy >= SIDE_Y0 and cy <= SIDE_Y1:
				var corner2: bool = (cx < SIDE_X0 + CAP_CORNER or cx > SIDE_X1 - CAP_CORNER) \
					and (cy < SIDE_Y0 + CAP_CORNER or cy > SIDE_Y1 - CAP_CORNER)
				glass = not corner2
			var st: SurfaceTool = st_g if glass else st_y
			var n00: Vector3 = nrm.call(th0, t0)
			var n10: Vector3 = nrm.call(th1, t0)
			var n11: Vector3 = nrm.call(th1, t1)
			var n01: Vector3 = nrm.call(th0, t1)
			if dir_z < 0.0:
				_quad(st, p00, p10, p11, p01, n00, n10, n11, n01)
			else:
				_quad(st, p10, p00, p01, p11, n10, n00, n01, n11)
	# fond plat de la calotte
	var xw: float = R_BODY * sin(_theta_cut())
	var z_far: float = z_join + dir_z * CAP_LEN * 0.62
	if dir_z < 0.0:
		_quad_flat(st_d, Vector3(-xw * 0.8, Y_CUT, z_far), Vector3(-xw, Y_CUT, z_join),
			Vector3(xw, Y_CUT, z_join), Vector3(xw * 0.8, Y_CUT, z_far))
	else:
		_quad_flat(st_d, Vector3(-xw, Y_CUT, z_join), Vector3(-xw * 0.8, Y_CUT, z_far),
			Vector3(xw * 0.8, Y_CUT, z_far), Vector3(xw, Y_CUT, z_join))
	st_y.set_material(mats["yellow"]); st_y.commit(mesh)
	st_d.set_material(mats["dark"]); st_d.commit(mesh)
	st_g.set_material(mats["glass"]); st_g.commit(mesh)


## Point de la calotte pour une cible (x, y) du plan frontal : sert à poser
## les feux, la grille et le lettrage à fleur de tôle.
static func cap_surface_point(x: float, y: float, z_join: float, dir_z: float) -> Vector3:
	var rho: float = sqrt(x * x + (y - Y_CENTER) * (y - Y_CENTER))
	var t: float = acos(clampf(rho / R_BODY, -1.0, 1.0))
	return Vector3(x, y, z_join + dir_z * CAP_LEN * sin(t))


static func _box(parent: Node3D, mat: StandardMaterial3D, size: Vector3, pos: Vector3, name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	mi.name = name
	parent.add_child(mi)
	return mi


static func _disc(parent: Node3D, mat: StandardMaterial3D, r: float, thick: float,
		pos: Vector3, axis_z: bool, name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = thick
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	# CylinderMesh a son axe en Y : axe Z (feux) ou X (roues)
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0) if axis_z else Vector3(0.0, 0.0, PI * 0.5)
	mi.name = name
	parent.add_child(mi)
	return mi


## Accessoires d'une extrémité : feux ronds, grille, bandeau du lettrage.
## Retourne les deux MeshInstance3D des feux (pour l'allumage).
static func _build_cap_fittings(parent: Node3D, mats: Dictionary, z_join: float, dir_z: float,
		is_front: bool) -> Array:
	var lamps: Array = []
	var y_lamp: float = Y_CUT + 0.30
	for sx in [-1.0, 1.0]:
		var p: Vector3 = cap_surface_point(sx * 1.05, y_lamp, z_join, dir_z)
		p.z += dir_z * 0.03
		var lamp: MeshInstance3D = _disc(parent, mats["lamp_off"], 0.15, 0.10, p, true,
			"Lamp%s%s" % ["F" if is_front else "R", "L" if sx < 0.0 else "R"])
		lamps.append(lamp)
	# grille de ventilation / trappe d'attelage : fente noire horizontale
	var pg: Vector3 = cap_surface_point(0.0, Y_CUT + 0.40, z_join, dir_z)
	pg.z += dir_z * 0.02
	_box(parent, mats["dark"], Vector3(1.05, 0.13, 0.06), pg, "Grille")
	# lettrage « TIGNES » en lettres argentées sous le pare-brise (photos),
	# à fleur de tôle ; Label3D regarde vers +Z par défaut → retourné à l'avant
	var lbl: Label3D = Label3D.new()
	lbl.text = "TIGNES"
	lbl.font_size = 72
	lbl.pixel_size = 0.0042
	lbl.modulate = Color(0.90, 0.90, 0.93)
	lbl.outline_modulate = Color(0.35, 0.35, 0.38)
	lbl.outline_size = 8
	lbl.shaded = true
	lbl.double_sided = false
	var pl: Vector3 = cap_surface_point(0.0, Y_CENTER - 0.02, z_join, dir_z)
	pl.z += dir_z * 0.02
	lbl.position = pl
	lbl.rotation = Vector3(0.0, PI if dir_z < 0.0 else 0.0, 0.0)
	lbl.name = "Lettrage"
	parent.add_child(lbl)
	# plaque « FUNICULAIRE PERCE-NEIGE » au-dessus du lettrage
	var pp: Vector3 = cap_surface_point(0.0, Y_CENTER + 0.30, z_join, dir_z)
	pp.z += dir_z * 0.015
	_box(parent, mats["letters"], Vector3(0.42, 0.12, 0.02), pp, "Plaque")
	return lamps


static func _build_bogie(parent: Node3D, mats: Dictionary, z_c: float) -> void:
	# châssis de bogie (surtout caché par le fond plat) + 4 roues
	_box(parent, mats["dark"], Vector3(2.0, 0.10, 2.1), Vector3(0.0, Y_CUT - 0.02, z_c), "Bogie")
	var y_axle: float = Y_RAIL_HEAD + 0.30
	for sx in [-0.60, 0.60]:
		for dz in [-0.85, 0.85]:
			_disc(parent, mats["wheel"], 0.30, 0.09, Vector3(sx, y_axle, z_c + dz), false, "Roue")
	# essieux
	for dz in [-0.85, 0.85]:
		_box(parent, mats["dark"], Vector3(1.30, 0.08, 0.08), Vector3(0.0, y_axle, z_c + dz), "Essieu")


## Construit la rame complète sous `root`. Retourne {front_lamps, rear_lamps}.
static func build_train(root: Node3D, train_length: float, car_count: int) -> Dictionary:
	var mats: Dictionary = materials()
	var car_len: float = train_length / float(car_count)
	var front_lamps: Array = []
	var rear_lamps: Array = []
	for i in range(car_count):
		var z_c: float = (float(i) - (car_count - 1) * 0.5) * car_len
		var z_front_end: float = z_c - car_len * 0.5      # extrémité avant (−Z)
		var z_rear_end: float = z_c + car_len * 0.5
		var is_first: bool = (i == 0)
		var is_last: bool = (i == car_count - 1)
		# le tube laisse la place à la calotte à l'extrémité de rame, et un
		# demi-jeu côté attelage
		var z_a: float = z_front_end + (CAP_LEN if is_first else GAP * 0.5)
		var z_b: float = z_rear_end - (CAP_LEN if is_last else GAP * 0.5)
		var mesh: ArrayMesh = ArrayMesh.new()
		_build_tube(mesh, mats, z_a, z_b, is_first, is_last)
		if is_first:
			_build_cap(mesh, mats, z_a, -1.0)
		else:
			_build_end_disc(mesh, mats["rib"], z_a, -1.0, R_BODY)
		if is_last:
			_build_cap(mesh, mats, z_b, 1.0)
		else:
			_build_end_disc(mesh, mats["rib"], z_b, 1.0, R_BODY)
		var car: MeshInstance3D = MeshInstance3D.new()
		car.name = "Car%d" % (i + 1)
		car.mesh = mesh
		root.add_child(car)
		if is_first:
			front_lamps = _build_cap_fittings(root, mats, z_a, -1.0, true)
		if is_last:
			rear_lamps = _build_cap_fittings(root, mats, z_b, 1.0, false)
		_build_bogie(root, mats, z_c - car_len * 0.5 + 3.0)
		_build_bogie(root, mats, z_c + car_len * 0.5 - 3.0)
		# soufflet d'intercirculation entre les deux voitures
		if not is_last:
			var bellows: MeshInstance3D = MeshInstance3D.new()
			var bm: ArrayMesh = ArrayMesh.new()
			_build_end_disc(bm, mats["dark"], z_b + GAP * 0.5, 1.0, R_BODY - 0.35)
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rb: float = R_BODY - 0.35
			var th_cut: float = acos(clampf((Y_CUT - Y_CENTER) / rb, -1.0, 1.0))
			var n_th: int = int(ceil(2.0 * rad_to_deg(th_cut) / D_THETA_DEG))
			var d_th: float = 2.0 * th_cut / float(n_th)
			for k in range(n_th):
				var t0: float = -th_cut + d_th * k
				var t1: float = t0 + d_th
				_quad(st, _tube_pt(t0, rb, z_b + GAP), _tube_pt(t1, rb, z_b + GAP),
					_tube_pt(t1, rb, z_b), _tube_pt(t0, rb, z_b),
					_tube_n(t0), _tube_n(t1), _tube_n(t1), _tube_n(t0))
			st.set_material(mats["dark"])
			st.commit(bm)
			bellows.mesh = bm
			bellows.name = "Soufflet"
			root.add_child(bellows)
	return {"front_lamps": front_lamps, "rear_lamps": rear_lamps, "mats": mats}
