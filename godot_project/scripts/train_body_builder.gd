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
## roulement (rail_head local = −1,08) : plus rien ne passe sous les rails.
## Le plancher intérieur (Y_FLOOR) est au niveau des quais-escaliers.

const R_BODY: float = 1.72          # rayon du tube
const Y_CENTER: float = 0.20        # axe du tube (monde +0,05)
# Voie descendue de 0,50 m dans l'alésage (2026-09-26, floor_y_local −1,85) :
# table de roulement à −1,23 monde = −1,08 cabine. Le fond plat est 7 cm
# au-dessus, le plancher 6 cm plus haut ; la face avant fait alors 2,93 m
# (réel 3,1) et le plancher est 2,4 m sous le plafond intérieur.
const Y_CUT: float = -1.01          # fond plat (monde −1,16)
const Y_FLOOR: float = -0.95        # plancher intérieur (monde −1,10 = quais)
const Y_RAIL_HEAD: float = -1.08    # table de roulement (monde −1,23)
const CAP_LEN: float = 1.00         # profondeur de la calotte bombée
const GAP: float = 0.50             # jeu entre les deux voitures
const RIB_W: float = 0.22           # largeur d'un anneau
const RIB_H: float = 0.035          # saillie d'un anneau
const PANEL_L: float = 1.63         # longueur d'un panneau (hublot ou porte)
const END_BLANK: float = 0.77       # tôle pleine aux extrémités du tube
const WELL_TOP: float = -0.60       # échancrures de la jupe au droit des bogies (y local)
const WELL_HALF: float = 1.40       # demi-longueur d'une échancrure
const BOGIE_OFFSET: float = 3.0     # bogies à 3 m des extrémités de voiture
const WHEEL_R: float = 0.30
const D_THETA_DEG: float = 5.0      # résolution angulaire du tube
const CAP_THETA_DEG: float = 2.0    # résolution angulaire de la calotte (découpes)
const CAP_N_T: int = 45             # anneaux de la calotte
const COL_L: float = 0.25           # résolution longitudinale
# Fenêtres : angle depuis le sommet du tube (°) ; hublots hauts et étroits
const WIN_T0: float = 28.0          # hublots : du haut de la courbe…
const WIN_T1: float = 100.0         # … jusqu'à ~0,85 m au-dessus du plancher
const WIN_MARGIN: float = 0.25      # marge longitudinale dans un panneau
# Face avant (photo 20260426_095511, 220 px/m) : la face réelle va de
# l'apex (+1,78) au fond plat (−1,33), soit 3,1 m ; dans le jeu la voie est
# plus haute dans le tube et la face n'a que 2,43 m (apex +1,72 → coupe
# −0,71). Les cotes verticales réelles sont donc COMPRIMÉES d'un facteur
# 0,78 depuis l'apex, les largeurs conservées. Coordonnées en projection
# frontale (x, y − Y_CENTER).
#   pare-brise réel 1,40 × 1,90 m (+1,43 → −0,47), plaque dedans en bas ;
#   baies des portes de secours : hautes et étroites CONTRE la lisière
#   (|x| ≥ 0,93 jusqu'au bord, +1,00 → −0,97) ; « TIGNES » sous le
#   pare-brise (−0,84), grille (−1,20) et feux ronds (±1,0 ; −1,25) en bas.
const FACE_SCALE: float = (R_BODY + (Y_CENTER - Y_CUT)) / 3.10   # 2,93 / 3,10
const WS_HALF_W: float = 0.70
const WS_TOP_REAL: float = 1.43
const WS_BOT_REAL: float = -0.47
const WS_CORNER: float = 0.20
const SIDE_X0: float = 0.93
const SIDE_RHO: float = 1.60        # lisière : ρ max des baies (bord en D)
const SIDE_TOP_REAL: float = 1.00
const SIDE_BOT_REAL: float = -0.97
const SIDE_CORNER: float = 0.22
const DOOR_X0: float = 0.80         # liseré des portes de secours
const DOOR_RHO: float = 1.67
const DOOR_TOP_REAL: float = 1.25
const GASKET_IN: float = 0.03       # joint caoutchouc : de −0,03 à +0,075
const GASKET_OUT: float = 0.075
const GLASS_INSET: float = 0.02


static func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	# Double face : la coque reste opaque quel que soit le sens des
	# triangles (le z-buffer garde la face la plus proche).
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		"yellow": _mat(Color(0.92, 0.82, 0.12), 0.42, 0.10),    # calottes (jaune citron)
		"rubber": _mat(Color(0.07, 0.07, 0.08), 0.85, 0.05),    # joints de vitres
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

## 🔴 Godot tient pour face AVANT l'enroulement HORAIRE (vu de devant). Les
## triangles sont construits avec (b−a)×(c−a) = normale sortante, c'est-à-dire
## anti-horaires vus de l'extérieur : on les émet donc RETOURNÉS. Sans ça, la
## coque était éliminée par le culling vue de dehors et l'on voyait
## l'intérieur (« les parois sont transparentes », retour 2026-09-26).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	st.set_normal(na); st.add_vertex(a)
	st.set_normal(nc); st.add_vertex(c)
	st.set_normal(nb); st.add_vertex(b)


## Quad a-b-c-d (sens trigonométrique vu de l'extérieur), normales lissées.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	_tri(st, a, b, c, na, nb, nc)
	_tri(st, a, c, d, na, nc, nd)


static func _quad_flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# les appelants donnent le fond plat avec (b−a)×(c−a) vers le HAUT : la
	# face visible est celle du dessous → ordre inversé, normale vers le bas
	var n: Vector3 = -(b - a).cross(c - a).normalized()
	_quad(st, a, d, c, b, n, n, n, n)


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

static func _in_well(z: float, wells: Array) -> bool:
	for w in wells:
		if absf(z - w) < WELL_HALF:
			return true
	return false


static func _build_tube(mesh: ArrayMesh, mats: Dictionary, z_a: float, z_b: float,
		yellow_a: bool = false, yellow_b: bool = false, wells: Array = []) -> void:
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
				# échancrure de bogie : la jupe s'arrête au-dessus des roues
				if Y_CENTER + r * cos(0.5 * (t0 + t1)) < WELL_TOP and _in_well(0.5 * (z0 + z1), wells):
					continue
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
	# Fond plat (châssis) entre les échancrures, et plafond des échancrures
	var xw: float = R_BODY * sin(th_cut)
	var cuts: Array = [z_a]
	for w in wells:
		cuts.append(w - WELL_HALF)
		cuts.append(w + WELL_HALF)
	cuts.append(z_b)
	for k in range(0, cuts.size() - 1, 2):
		var za: float = maxf(cuts[k], z_a)
		var zb: float = minf(cuts[k + 1], z_b)
		if zb > za:
			_quad_flat(st_dark, Vector3(-xw, Y_CUT, za), Vector3(-xw, Y_CUT, zb),
				Vector3(xw, Y_CUT, zb), Vector3(xw, Y_CUT, za))
	var xw_top: float = R_BODY * sin(acos(clampf((WELL_TOP - Y_CENTER) / R_BODY, -1.0, 1.0)))
	for w in wells:
		_quad_flat(st_dark, Vector3(-xw_top, WELL_TOP, w - WELL_HALF), Vector3(-xw_top, WELL_TOP, w + WELL_HALF),
			Vector3(xw_top, WELL_TOP, w + WELL_HALF), Vector3(xw_top, WELL_TOP, w - WELL_HALF))
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
			_tri(st, c, a, b, n, n, n)
		else:
			_tri(st, c, b, a, n, n, n)
	# triangle du fond plat
	var a2: Vector3 = _tube_pt(-th_cut, r, z)
	var b2: Vector3 = _tube_pt(th_cut, r, z)
	if dir_z < 0.0:
		_tri(st, c, b2, a2, n, n, n)
	else:
		_tri(st, c, a2, b2, n, n, n)
	st.set_material(mat)
	st.commit(mesh)


# --- calotte bombée jaune ----------------------------------------------------

## Ordonnée réelle (relative à l'axe) → ordonnée jeu, comprimée depuis l'apex.
static func _face_y(y_real: float) -> float:
	return R_BODY - (1.78 - y_real) * FACE_SCALE


## Contour d'un rectangle à coins arrondis (repère frontal, relatif à
## l'axe), échantillonné finement, puis rabattu radialement sur ρ ≤ rho_max
## (bord en D des baies latérales). Sens trigonométrique.
static func _rounded_outline(x0: float, x1: float, y0: float, y1: float, r: float,
		rho_max: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n_c: int = 10                 # points par coin
	var n_e: int = 10                 # points par bord droit
	r = minf(r, minf((x1 - x0) * 0.5, (y1 - y0) * 0.5) - 0.001)
	var corners: Array = [
		[Vector2(x1 - r, y0 + r), -PI * 0.5],   # bas droit
		[Vector2(x1 - r, y1 - r), 0.0],         # haut droit
		[Vector2(x0 + r, y1 - r), PI * 0.5],    # haut gauche
		[Vector2(x0 + r, y0 + r), PI],          # bas gauche
	]
	for k in range(4):
		var c: Vector2 = corners[k][0]
		var a0: float = corners[k][1]
		var prev: Vector2 = corners[(k + 3) % 4][0] + Vector2(cos(a0), sin(a0)) * r
		var first: Vector2 = c + Vector2(cos(a0), sin(a0)) * r
		# bord droit menant au coin k
		for j in range(n_e):
			pts.append(prev.lerp(first, float(j) / float(n_e)))
		for j in range(n_c + 1):
			var a: float = a0 + (PI * 0.5) * float(j) / float(n_c)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	# rabattement sur la lisière
	for i in range(pts.size()):
		var rho: float = pts[i].length()
		if rho > rho_max:
			pts[i] = pts[i] * (rho_max / rho)
	return pts


## Contour décalé de d (positif = vers l'extérieur) — approximation par le
## centroïde (les formes sont convexes et peu allongées).
static func _offset_outline(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var c: Vector2 = Vector2.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	var out: PackedVector2Array = PackedVector2Array()
	for q in pts:
		var v: Vector2 = q - c
		var l: float = v.length()
		out.append(c + v * ((l + d) / l) if l > 1e-6 else q)
	return out


## Les trois vitres de la face : [pare-brise, baie gauche, baie droite]
static func _face_windows() -> Array:
	var ws: PackedVector2Array = _rounded_outline(-WS_HALF_W, WS_HALF_W,
		_face_y(WS_BOT_REAL), _face_y(WS_TOP_REAL), WS_CORNER, 99.0)
	var side_r: PackedVector2Array = _rounded_outline(SIDE_X0, SIDE_RHO + 0.05,
		_face_y(SIDE_BOT_REAL), _face_y(SIDE_TOP_REAL), SIDE_CORNER, SIDE_RHO)
	var side_l: PackedVector2Array = PackedVector2Array()
	for i in range(side_r.size() - 1, -1, -1):
		side_l.append(Vector2(-side_r[i].x, side_r[i].y))
	return [ws, side_l, side_r]


## Point 3D sur l'ellipsoïde de la calotte pour (x, y_rel) frontal, décalé
## de `lift` le long de la normale.
static func _cap_pt(x: float, y_rel: float, z_join: float, dir_z: float, lift: float) -> Vector3:
	var rho: float = sqrt(x * x + y_rel * y_rel)
	var t: float = acos(clampf(rho / R_BODY, -1.0, 1.0))
	var p: Vector3 = Vector3(x, Y_CENTER + y_rel, z_join + dir_z * CAP_LEN * sin(t))
	return p + _cap_n(x, y_rel, dir_z) * lift


static func _cap_n(x: float, y_rel: float, dir_z: float) -> Vector3:
	var rho: float = sqrt(x * x + y_rel * y_rel)
	var t: float = acos(clampf(rho / R_BODY, -1.0, 1.0))
	return Vector3(x / (R_BODY * R_BODY), y_rel / (R_BODY * R_BODY),
		dir_z * sin(t) / CAP_LEN).normalized()


## Triangle orienté vers l'extérieur (normale de référence n_ref).
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var geo: Vector3 = (b - a).cross(c - a)
	if geo.dot(na + nb + nc) >= 0.0:
		_tri(st, a, b, c, na, nb, nc)
	else:
		_tri(st, a, c, b, na, nc, nb)


## Panneau plein (vitre) : éventail depuis le centroïde avec un anneau
## intermédiaire pour épouser la courbure.
static func _emit_pane(st: SurfaceTool, outline: PackedVector2Array, z_join: float,
		dir_z: float, lift: float) -> void:
	var c: Vector2 = Vector2.ZERO
	for q in outline:
		c += q
	c /= float(outline.size())
	var n: int = outline.size()
	var pc: Vector3 = _cap_pt(c.x, c.y, z_join, dir_z, lift)
	var nc: Vector3 = _cap_n(c.x, c.y, dir_z)
	for i in range(n):
		var q0: Vector2 = outline[i]
		var q1: Vector2 = outline[(i + 1) % n]
		var m0: Vector2 = c.lerp(q0, 0.5)
		var m1: Vector2 = c.lerp(q1, 0.5)
		var p0: Vector3 = _cap_pt(q0.x, q0.y, z_join, dir_z, lift)
		var p1: Vector3 = _cap_pt(q1.x, q1.y, z_join, dir_z, lift)
		var pm0: Vector3 = _cap_pt(m0.x, m0.y, z_join, dir_z, lift)
		var pm1: Vector3 = _cap_pt(m1.x, m1.y, z_join, dir_z, lift)
		var n0: Vector3 = _cap_n(q0.x, q0.y, dir_z)
		var n1: Vector3 = _cap_n(q1.x, q1.y, dir_z)
		var nm0: Vector3 = _cap_n(m0.x, m0.y, dir_z)
		var nm1: Vector3 = _cap_n(m1.x, m1.y, dir_z)
		_tri_out(st, pc, pm0, pm1, nc, nm0, nm1)
		_tri_out(st, pm0, p0, p1, nm0, n0, n1)
		_tri_out(st, pm0, p1, pm1, nm0, n1, nm1)


## Bande entre deux contours (joint caoutchouc, liseré de porte).
static func _emit_band(st: SurfaceTool, inner: PackedVector2Array, outer: PackedVector2Array,
		z_join: float, dir_z: float, lift: float) -> void:
	var n: int = inner.size()
	for i in range(n):
		var a: Vector2 = inner[i]
		var b: Vector2 = inner[(i + 1) % n]
		var c: Vector2 = outer[(i + 1) % n]
		var d: Vector2 = outer[i]
		var pa: Vector3 = _cap_pt(a.x, a.y, z_join, dir_z, lift)
		var pb: Vector3 = _cap_pt(b.x, b.y, z_join, dir_z, lift)
		var pcc: Vector3 = _cap_pt(c.x, c.y, z_join, dir_z, lift)
		var pd: Vector3 = _cap_pt(d.x, d.y, z_join, dir_z, lift)
		var na: Vector3 = _cap_n(a.x, a.y, dir_z)
		var nb: Vector3 = _cap_n(b.x, b.y, dir_z)
		var ncc: Vector3 = _cap_n(c.x, c.y, dir_z)
		var nd: Vector3 = _cap_n(d.x, d.y, dir_z)
		_tri_out(st, pa, pb, pcc, na, nb, ncc)
		_tri_out(st, pa, pcc, pd, na, ncc, nd)


## z_join = abscisse du raccord au tube ; dir_z = −1 pour l'avant (pointe
## vers −Z), +1 pour l'arrière. Tôle jaune DÉCOUPÉE aux vitres (cellules
## touchant une vitre retirées), joints caoutchouc qui recouvrent le
## crénelage de la découpe, vitres lissées à fleur de tôle, liserés des
## portes de secours ; `backboard` pose un fond sombre derrière les vitres
## (rame 2 : pas d'intérieur modélisé).
static func _build_cap(mesh: ArrayMesh, mats: Dictionary, z_join: float, dir_z: float,
		backboard: bool = false) -> void:
	var st_y: SurfaceTool = SurfaceTool.new()
	var st_g: SurfaceTool = SurfaceTool.new()
	var st_d: SurfaceTool = SurfaceTool.new()
	var st_r: SurfaceTool = SurfaceTool.new()
	for st in [st_y, st_g, st_d, st_r]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var windows: Array = _face_windows()
	var holes: Array = []
	for w in windows:
		holes.append(_offset_outline(w, 0.0))
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
		var v: Vector3 = Vector3(sin(theta) * cos(t) / R_BODY, cos(theta) * cos(t) / R_BODY,
			dir_z * sin(t) / CAP_LEN)
		return v.normalized()
	var frontal: Callable = func(theta: float, t: float) -> Vector2:
		var r: float = R_BODY * cos(t)
		return Vector2(r * sin(theta), r * cos(theta))

	for k in range(n_t):
		var t0: float = d_t * k
		var t1: float = t0 + d_t
		for i in range(n_th):
			var th0: float = -PI + d_th * i
			var th1: float = th0 + d_th
			var p00: Vector3 = pt.call(th0, t0)
			var p10: Vector3 = pt.call(th1, t0)
			var p11: Vector3 = pt.call(th1, t1)
			var p01: Vector3 = pt.call(th0, t1)
			if p00.y <= Y_CUT and p10.y <= Y_CUT and p11.y <= Y_CUT and p01.y <= Y_CUT:
				continue
			# découpe : la cellule touche-t-elle une vitre ?
			var cut: bool = false
			var corners: Array = [frontal.call(th0, t0), frontal.call(th1, t0),
				frontal.call(th1, t1), frontal.call(th0, t1)]
			for h in holes:
				for q in corners:
					if Geometry2D.is_point_in_polygon(q, h):
						cut = true
						break
				if cut:
					break
			if cut:
				continue
			var n00: Vector3 = nrm.call(th0, t0)
			var n10: Vector3 = nrm.call(th1, t0)
			var n11: Vector3 = nrm.call(th1, t1)
			var n01: Vector3 = nrm.call(th0, t1)
			if dir_z < 0.0:
				_quad(st_y, p00, p10, p11, p01, n00, n10, n11, n01)
			else:
				_quad(st_y, p10, p00, p01, p11, n10, n00, n01, n11)
	# vitres, joints et liserés
	for w in windows:
		_emit_band(st_r, _offset_outline(w, -GASKET_IN), _offset_outline(w, GASKET_OUT),
			z_join, dir_z, 0.010)
		_emit_pane(st_g, _offset_outline(w, -GLASS_INSET), z_join, dir_z, 0.016)
	for sx in [-1.0, 1.0]:
		var door: PackedVector2Array = _rounded_outline(DOOR_X0, DOOR_RHO + 0.05,
			Y_CUT - Y_CENTER + 0.05, _face_y(DOOR_TOP_REAL), 0.30, DOOR_RHO)
		if sx < 0.0:
			var m: PackedVector2Array = PackedVector2Array()
			for i in range(door.size() - 1, -1, -1):
				m.append(Vector2(-door[i].x, door[i].y))
			door = m
		_emit_band(st_r, _offset_outline(door, -0.008), _offset_outline(door, 0.008),
			z_join, dir_z, 0.004)
	# fond plat de la calotte
	var xw: float = R_BODY * sin(_theta_cut())
	var z_far: float = z_join + dir_z * CAP_LEN * 0.62
	if dir_z < 0.0:
		_quad_flat(st_d, Vector3(-xw * 0.8, Y_CUT, z_far), Vector3(-xw, Y_CUT, z_join),
			Vector3(xw, Y_CUT, z_join), Vector3(xw * 0.8, Y_CUT, z_far))
	else:
		_quad_flat(st_d, Vector3(-xw, Y_CUT, z_join), Vector3(-xw * 0.8, Y_CUT, z_far),
			Vector3(xw * 0.8, Y_CUT, z_far), Vector3(xw, Y_CUT, z_join))
	# fond sombre derrière les vitres (rame sans intérieur)
	if backboard:
		_build_end_disc(mesh, mats["dark"], z_join + dir_z * 0.12, dir_z, R_BODY - 0.04)
	st_y.set_material(mats["yellow"]); st_y.commit(mesh)
	st_d.set_material(mats["dark"]); st_d.commit(mesh)
	st_r.set_material(mats["rubber"]); st_r.commit(mesh)
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
	# feux ronds aux coins bas (réel : ±1,0 ; −1,25 → comprimé), à fleur de tôle
	var y_lamp: float = Y_CENTER + maxf(_face_y(-1.25), Y_CUT - Y_CENTER + 0.16)
	for sx in [-1.0, 1.0]:
		var p: Vector3 = cap_surface_point(sx * 1.02, y_lamp, z_join, dir_z)
		p.z += dir_z * 0.03
		var lamp: MeshInstance3D = _disc(parent, mats["lamp_off"], 0.13, 0.10, p, true,
			"Lamp%s%s" % ["F" if is_front else "R", "L" if sx < 0.0 else "R"])
		lamps.append(lamp)
	# grille de ventilation : fente noire horizontale entre les feux
	var pg: Vector3 = cap_surface_point(0.0, Y_CENTER + maxf(_face_y(-1.20), Y_CUT - Y_CENTER + 0.12), z_join, dir_z)
	pg.z += dir_z * 0.02
	_box(parent, mats["dark"], Vector3(1.10, 0.12, 0.06), pg, "Grille")
	# lettrage « TIGNES » en lettres argentées sous le pare-brise (photos),
	# à fleur de tôle ; Label3D regarde vers +Z par défaut → retourné à l'avant
	var lbl: Label3D = Label3D.new()
	lbl.text = "TIGNES"
	lbl.font_size = 72
	lbl.pixel_size = 0.0050
	lbl.modulate = Color(0.90, 0.90, 0.93)
	lbl.outline_modulate = Color(0.35, 0.35, 0.38)
	lbl.outline_size = 8
	lbl.shaded = true
	lbl.double_sided = false
	var pl: Vector3 = cap_surface_point(0.0, Y_CENTER + _face_y(-0.84), z_join, dir_z)
	pl.z += dir_z * 0.02
	lbl.position = pl
	lbl.rotation = Vector3(0.0, PI if dir_z < 0.0 else 0.0, 0.0)
	lbl.name = "Lettrage"
	parent.add_child(lbl)
	# plaque « FUNICULAIRE PERCE NEIGE 1 » : DANS le pare-brise, en bas au
	# centre (derrière la vitre, comme sur la photo)
	var pp: Vector3 = cap_surface_point(0.0, Y_CENTER + _face_y(-0.34), z_join, dir_z)
	pp.z += dir_z * 0.004
	_box(parent, mats["letters"], Vector3(0.45, 0.12, 0.01), pp, "Plaque")
	return lamps


## Bogie : châssis, deux essieux, quatre roues sur PIVOTS (retournés par
## cabin.gd à v/R) avec moyeu clair et barre radiale sur la face externe —
## une roue lisse qui tourne ne se voit pas. Retourne les pivots.
static func _build_bogie(parent: Node3D, mats: Dictionary, z_c: float) -> Array:
	var pivots: Array = []
	var y_axle: float = Y_RAIL_HEAD + WHEEL_R
	# longerons du châssis, au-dessus des roues, entre les échancrures
	for sx in [-0.95, 0.95]:
		_box(parent, mats["dark"], Vector3(0.12, 0.16, 2.4), Vector3(sx, WELL_TOP - 0.10, z_c), "Longeron")
	for dz in [-0.85, 0.85]:
		_box(parent, mats["dark"], Vector3(1.30, 0.07, 0.07), Vector3(0.0, y_axle, z_c + dz), "Essieu")
		# boîtes d'essieu
		for sx in [-0.72, 0.72]:
			_box(parent, mats["dark"], Vector3(0.14, 0.22, 0.26), Vector3(sx, y_axle + 0.02, z_c + dz), "Boite")
		for sx in [-0.60, 0.60]:
			var pivot: Node3D = Node3D.new()
			pivot.name = "Roue"
			pivot.position = Vector3(sx, y_axle, z_c + dz)
			parent.add_child(pivot)
			_disc(pivot, mats["wheel"], WHEEL_R, 0.09, Vector3.ZERO, false, "Disque")
			var outer: float = signf(sx) * 0.055
			_disc(pivot, mats["rib"], 0.09, 0.02, Vector3(outer, 0.0, 0.0), false, "Moyeu")
			_box(pivot, mats["rib"], Vector3(0.015, 0.50, 0.05), Vector3(outer, 0.0, 0.0), "Barre")
			_box(pivot, mats["rib"], Vector3(0.015, 0.05, 0.50), Vector3(outer, 0.0, 0.0), "Barre2")
			pivots.append(pivot)
	return pivots


## Construit la rame complète sous `root` : UN NŒUD PAR VOITURE
## (« CarRoot%d », géométrie centrée sur la voiture, posé à z = ±8 m au
## repos) que cabin.gd replace chaque frame sur la spline à sa propre
## abscisse — l'articulation en courbe (retour d'essai 2026-09-26 :
## « c'est qu'un bloc »). Retourne {car_roots, wheels, front_lamps,
## rear_lamps, mats}.
static func build_train(root: Node3D, train_length: float, car_count: int,
		backboard: bool = false) -> Dictionary:
	var mats: Dictionary = materials()
	var car_len: float = train_length / float(car_count)
	var front_lamps: Array = []
	var rear_lamps: Array = []
	var wheels: Array = []
	var car_roots: Array = []
	for i in range(car_count):
		var z_c: float = (float(i) - (car_count - 1) * 0.5) * car_len
		var car_root: Node3D = Node3D.new()
		car_root.name = "CarRoot%d" % (i + 1)
		car_root.position = Vector3(0.0, 0.0, z_c)
		root.add_child(car_root)
		car_roots.append(car_root)
		var z_front_end: float = -car_len * 0.5      # extrémité avant (−Z), repère voiture
		var z_rear_end: float = car_len * 0.5
		var is_first: bool = (i == 0)
		var is_last: bool = (i == car_count - 1)
		# le tube laisse la place à la calotte à l'extrémité de rame, et un
		# demi-jeu côté attelage
		var z_a: float = z_front_end + (CAP_LEN if is_first else GAP * 0.5)
		var z_b: float = z_rear_end - (CAP_LEN if is_last else GAP * 0.5)
		var wells: Array = [z_front_end + BOGIE_OFFSET, z_rear_end - BOGIE_OFFSET]
		var mesh: ArrayMesh = ArrayMesh.new()
		_build_tube(mesh, mats, z_a, z_b, is_first, is_last, wells)
		if is_first:
			_build_cap(mesh, mats, z_a, -1.0, backboard)
		else:
			_build_end_disc(mesh, mats["rib"], z_a, -1.0, R_BODY)
		if is_last:
			_build_cap(mesh, mats, z_b, 1.0, backboard)
		else:
			_build_end_disc(mesh, mats["rib"], z_b, 1.0, R_BODY)
		var car: MeshInstance3D = MeshInstance3D.new()
		car.name = "Car%d" % (i + 1)
		car.mesh = mesh
		car_root.add_child(car)
		if is_first:
			front_lamps = _build_cap_fittings(car_root, mats, z_a, -1.0, true)
		if is_last:
			rear_lamps = _build_cap_fittings(car_root, mats, z_b, 1.0, false)
		wheels.append_array(_build_bogie(car_root, mats, wells[0]))
		wheels.append_array(_build_bogie(car_root, mats, wells[1]))
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
			car_root.add_child(bellows)
	return {"car_roots": car_roots, "wheels": wheels,
		"front_lamps": front_lamps, "rear_lamps": rear_lamps, "mats": mats}
