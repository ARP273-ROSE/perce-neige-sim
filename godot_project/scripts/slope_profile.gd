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
	# (au-delà de 1 571 m et de 1 853,5 m : +20,26 m par tronçon neutre
	# inséré de part et d'autre de l'évitement, cf. PNConstants.LENGTH)
	[2440.52, 0.295],
	[3040.52, 0.29],
	[3240.52, 0.28],
	[3368.52, 0.27],   # diminution pente finale commence (t=7:29)
	[3420.52, 0.18],
	[3477.53, 0.10],   # pente de la gare haute atteinte au galet n° 238, à
	                   # l'entrée du quai (fait de Kevin, 06/10/2026 ; la
	                   # vidéo la plaçait où le tunnel redevient carré)
	[3514.52, 0.06],   # Grande Motte plateforme
]

# ---------------------------------------------------------------------------
# Plan horizontal : (distance, bearing degrés — 0 = Nord, 90 = Est)
# Gares (IGN BD TOPO) : Val Claret 45,45189 °N 6,89898 °E → Grande Motte
# 45,42352 °N 6,89146 °E (3 029 m). Positions des courbes : vidéo cockpit ;
# angles et caps : ajustés sur le tracé IGN (audit_physique/trace_ign.sage,
# 06/10/2026 : écart moyen 2 m, max 11 m, précision IGN 10 m).
# ---------------------------------------------------------------------------

const CURVE_PROFILE: Array = [
	[0.0,    169.7],   # SSE en sortie Val Claret
	[1297.0, 169.7],   # rectiligne section basse
	[1419.0, 177.95],  # courbe 1 milieu — courbure max
	[1541.0, 186.2],   # fin courbe 1 (16,5° à droite)
	[1621.26, 186.2],  # entrée boucle croisement (tronçon neutre de 20,26 m inséré avant)
	[1843.26, 186.2],  # sortie boucle croisement
	[1924.52, 186.2],  # début courbe 2 (tronçon neutre de 20,26 m inséré avant)
	[2167.02, 200.35], # courbe 2 milieu — courbure max
	[2409.52, 214.5],  # fin courbe 2 (28,3° à droite, SO)
	[3514.52, 214.5],  # rectiligne jusqu'à station haute
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
	[1606.26, 1625.26],
	[2142.52, 2276.52],   # 134 m zone sombre majeure
	[2786.52, 2824.52],
	[3021.52, 3149.52],   # 127 m zone sombre majeure
	[3257.52, 3289.52],
]

# ---------------------------------------------------------------------------
# Sections tunnel : (start_m, shape)
# "horseshoe" = carré cut-and-cover, "circular" = rond TBM
# ---------------------------------------------------------------------------

const TUNNEL_SECTIONS: Array = [
	[0.0,     "horseshoe"],
	[257.0,   "circular"],
	[3472.56, "horseshoe"],   # PNConstants.SQUARE_SECTION_HIGH_START
	[3514.52, "horseshoe"],
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


# Gradient pour la PHYSIQUE — interpolation LINÉAIRE, comme gradient_at()
# du sim Python : c'est ce qui rend les valeurs (gravité nette, tension,
# puissance) exactement raccord avec le programme PC. Le smoothstep de
# gradient_at() reste réservé à la GÉOMÉTRIE 3D (continuité de courbure,
# sinon les rails tressautent aux points de contrôle) — l'écart entre les
# deux est < 0,5 % de pente, invisible à l'œil mais mesurable sur la jauge.
static func gradient_phys_at(s: float) -> float:
	return interp(SLOPE_PROFILE, s)


# ---------------------------------------------------------------------------
# Altitude (m) à la distance-pente s — équivalent du geom_at()[1] du sim
# Python. Intègre le gradient par pas de 2 m puis NORMALISE pour atteindre
# exactement DROP = 921 m (même correction que build_path_points). Table
# calculée une fois (static var) : lookup lerp O(1) ensuite. Utilisé par la
# tension câble (poids du brin = ρ·g·(ALT_HIGH − alt(s_rame_lourde))).
# ---------------------------------------------------------------------------

const _ALT_DS: float = 2.0
static var _alt_table: PackedFloat32Array = PackedFloat32Array()


static func _build_alt_table() -> void:
	var n: int = int(PNConstants.LENGTH / _ALT_DS)
	_alt_table.resize(n + 1)
	var y: float = PNConstants.ALT_LOW
	_alt_table[0] = y
	var s: float = 0.0
	for i in range(n):
		# Interp linéaire (gradient_phys_at) : même intégration que le
		# _build_geometry du PC → altitudes identiques au dm près.
		var g: float = gradient_phys_at(s + _ALT_DS * 0.5)
		y += _ALT_DS * sin(atan(g))
		s += _ALT_DS
		_alt_table[i + 1] = y
	# Normalisation du dénivelé intégré sur DROP exact
	var drop_raw: float = _alt_table[n] - PNConstants.ALT_LOW
	if drop_raw > 0.0:
		var k: float = PNConstants.DROP / drop_raw
		for i in range(n + 1):
			_alt_table[i] = PNConstants.ALT_LOW \
				+ (_alt_table[i] - PNConstants.ALT_LOW) * k


static func altitude_at(s: float) -> float:
	if _alt_table.is_empty():
		_build_alt_table()
	var fidx: float = clampf(s, 0.0, PNConstants.LENGTH) / _ALT_DS
	var i0: int = clampi(int(fidx), 0, _alt_table.size() - 1)
	var i1: int = mini(i0 + 1, _alt_table.size() - 1)
	return lerpf(_alt_table[i0], _alt_table[i1], fidx - float(i0))


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


static func tunnel_lit_at(_s: float) -> bool:
	# Retour d'exploitation (2026-07) : le tunnel est éclairé UNIFORMÉMENT
	# tout du long — pas de sections éteintes. Les « zones sombres »
	# venaient de l'exposition caméra de la vidéo de calibration.
	# TUNNEL_DARK_ZONES conservé en archive, plus utilisé.
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
