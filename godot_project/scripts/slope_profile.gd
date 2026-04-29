class_name SlopeProfile
extends RefCounted
## Profil du tracé — pente, courbes en plan, éclairage tunnel, section.
## Données calibrées sur la vidéo cockpit funiculaire_cabine_hd.mp4 avec
## timestamps mappés via la vitesse de croisière réelle de 10.1 m/s.

# ---------------------------------------------------------------------------
# Profil de pente : (distance le long de la pente en m, gradient en fraction)
# ---------------------------------------------------------------------------

const SLOPE_PROFILE: Array = [
	# Val Claret portail (tunnel carré) — départ doux
	[0.0,    0.08],
	[120.0,  0.12],
	[257.0,  0.16],    # transition carré → rond (TBM)
	[400.0,  0.22],
	[510.0,  0.25],    # "la pente augmente" (t=2:50)
	[700.0,  0.28],
	[914.0,  0.295],   # pente max soutenue (t=3:30)
	[2400.0, 0.295],
	[3000.0, 0.29],
	[3200.0, 0.28],
	[3328.0, 0.27],    # diminution pente finale commence (t=7:29)
	[3380.0, 0.18],
	[3420.0, 0.10],    # tunnel redevient carré (t=7:43)
	[3474.0, 0.06],    # Grande Motte plateforme
]

# ---------------------------------------------------------------------------
# Plan horizontal : (distance, bearing degrés — 0 = Nord, 90 = Est)
# Val Claret 45.4578°N 6.9014°E → Grande Motte 45.4354°N 6.9020°E
# ---------------------------------------------------------------------------

const CURVE_PROFILE: Array = [
	[0.0,    155.0],   # SSE en sortie Val Claret
	[1297.0, 155.0],   # rectiligne section basse
	[1420.0, 165.0],   # courbe 1 milieu — courbure max
	[1541.0, 175.0],   # fin courbe 1 (due sud)
	[1601.0, 175.0],   # entrée boucle croisement
	[1823.0, 175.0],   # sortie boucle croisement
	[1884.0, 175.0],   # début courbe 2
	[2125.0, 189.0],   # courbe 2 milieu — courbure max
	[2369.0, 203.0],   # fin courbe 2 (SSO)
	[3474.0, 203.0],   # rectiligne jusqu'à station haute
]

# ---------------------------------------------------------------------------
# Zones sombres du tunnel (pas de néons) — (start_m, end_m)
# Analyse brightness vidéo, espacement néons ~32 m hors zones sombres
# ---------------------------------------------------------------------------

const TUNNEL_DARK_ZONES: Array = [
	[166.0,   198.0],
	[318.0,   401.0],
	[561.0,   745.0],   # 185 m zone sombre majeure
	[1408.0, 1465.0],
	[1586.0, 1605.0],
	[2102.0, 2236.0],   # 134 m zone sombre majeure
	[2746.0, 2784.0],
	[2981.0, 3109.0],   # 127 m zone sombre majeure
	[3217.0, 3249.0],
]

# ---------------------------------------------------------------------------
# Sections tunnel : (start_m, shape)
# "horseshoe" = carré cut-and-cover, "circular" = rond TBM
# ---------------------------------------------------------------------------

const TUNNEL_SECTIONS: Array = [
	[0.0,     "horseshoe"],
	[257.0,   "circular"],
	[3420.0,  "horseshoe"],
	[3474.0,  "horseshoe"],
]

# ---------------------------------------------------------------------------
# Interpolation linéaire dans une table [[x, y], ...]
# ---------------------------------------------------------------------------

static func interp(table: Array, s: float) -> float:
	if s <= table[0][0]:
		return table[0][1]
	if s >= table[-1][0]:
		return table[-1][1]
	for i in range(table.size() - 1):
		var s0: float = table[i][0]
		var v0: float = table[i][1]
		var s1: float = table[i + 1][0]
		var v1: float = table[i + 1][1]
		if s0 <= s and s <= s1:
			var k: float = (s - s0) / maxf(s1 - s0, 1e-6)
			return v0 + k * (v1 - v0)
	return table[-1][1]


# Comme interp() mais avec un smoothstep cubique (3k² − 2k³) sur l'interpolant.
# Cela rend la courbure continue aux points de contrôle (vs interp() linéaire
# qui produit des cassures de courbure visibles comme du tressautement).
static func interp_smooth(table: Array, s: float) -> float:
	if s <= table[0][0]:
		return table[0][1]
	if s >= table[-1][0]:
		return table[-1][1]
	for i in range(table.size() - 1):
		var s0: float = table[i][0]
		var v0: float = table[i][1]
		var s1: float = table[i + 1][0]
		var v1: float = table[i + 1][1]
		if s0 <= s and s <= s1:
			var k: float = (s - s0) / maxf(s1 - s0, 1e-6)
			var k_smooth: float = smoothstep(0.0, 1.0, k)
			return v0 + k_smooth * (v1 - v0)
	return table[-1][1]


static func gradient_at(s: float) -> float:
	return interp_smooth(SLOPE_PROFILE, s)


static func slope_angle_at(s: float) -> float:
	return atan(gradient_at(s))


static func slope_curvature_at(s: float) -> float:
	var ds: float = 5.0
	return (slope_angle_at(s + ds) - slope_angle_at(s - ds)) / (2.0 * ds)


static func heading_at(s: float) -> float:
	return interp_smooth(CURVE_PROFILE, s)


static func curvature_at(s: float) -> float:
	var ds: float = 5.0
	return (heading_at(s + ds) - heading_at(s - ds)) / (2.0 * ds)


static func tunnel_lit_at(s: float) -> bool:
	for zone in TUNNEL_DARK_ZONES:
		if zone[0] <= s and s <= zone[1]:
			return false
	return true


static func tunnel_shape_at(s: float) -> String:
	var shape: String = "circular"
	for sec in TUNNEL_SECTIONS:
		if s >= sec[0]:
			shape = sec[1]
	return shape


static func is_passing_loop(s: float) -> bool:
	return PNConstants.PASSING_START <= s and s <= PNConstants.PASSING_END


# ---------------------------------------------------------------------------
# Construction de la géométrie 3D complète du tracé
# Retourne un tableau de Vector3 en coordonnées monde (Y = altitude)
# avec X/Z = position horizontale en plan (origine = portail Val Claret)
# ---------------------------------------------------------------------------

static func build_path_points(step_m: float = 2.0) -> Array:
	var points: Array = []
	var x: float = 0.0        # plan east
	var z: float = 0.0        # plan north (négatif car Godot Z+ = sud)
	var y: float = PNConstants.ALT_LOW
	points.append(Vector3(x, y, z))

	var s: float = 0.0
	var n: int = int(PNConstants.LENGTH / step_m)
	var accumulated_drop: float = 0.0

	for i in range(n):
		var s_mid: float = s + step_m * 0.5
		var g: float = gradient_at(s_mid)
		var theta: float = atan(g)
		var dx_slope: float = step_m * cos(theta)    # projection horizontale
		var dy: float = step_m * sin(theta)
		var bearing: float = deg_to_rad(heading_at(s_mid))
		# 0° = Nord (Z−), 90° = Est (X+)
		x += dx_slope * sin(bearing)
		z -= dx_slope * cos(bearing)   # Godot : Z+ = sud, donc bearing N = −Z
		y += dy
		accumulated_drop += dy
		s += step_m
		points.append(Vector3(x, y, z))

	# Normaliser le dénivelé pour atteindre exactement DROP = 921 m
	if accumulated_drop > 0.0:
		var scale: float = PNConstants.DROP / accumulated_drop
		for j in range(1, points.size()):
			var p: Vector3 = points[j]
			var corrected_y: float = PNConstants.ALT_LOW + (p.y - PNConstants.ALT_LOW) * scale
			points[j] = Vector3(p.x, corrected_y, p.z)

	return points
