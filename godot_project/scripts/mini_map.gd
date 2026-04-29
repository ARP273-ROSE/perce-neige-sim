class_name MiniMap
extends Control
## Mini-carte schématique du tracé Val Claret → Grande Motte.
## Affichée en bas-droite du HUD. Vue de dessus (X-Z monde projeté).
## Montre :
##   - Le tracé complet en polyline blanche
##   - Le passing loop en lentille jaune (segment 1611-1813)
##   - Les 2 stations (carrés verts en bas, rouge en haut)
##   - La position courante de la cabine (dot orange)
##   - La position du ghost (dot bleu)
##   - Distance progression : "1234 / 3474 m"

@export var map_size: Vector2 = Vector2(220, 320)
@export var padding: float = 14.0
@export var bg_color: Color = Color(0.03, 0.05, 0.08, 0.88)
@export var border_color: Color = Color(0.95, 0.85, 0.20, 0.85)

var physics: TrainPhysics = null
var path_points_2d: PackedVector2Array = PackedVector2Array()   # mappés à l'écran
var path_world_xz: PackedVector2Array = PackedVector2Array()    # bruts en monde
var loop_start_idx: int = 0
var loop_end_idx: int = 0


func _ready() -> void:
	custom_minimum_size = map_size
	size = map_size


func setup(p: TrainPhysics) -> void:
	physics = p
	# Construit les points du tracé une fois (XZ projeté en plan)
	var step: float = 8.0
	var pts: PackedVector2Array = PackedVector2Array()
	var s: float = 0.0
	while s <= PNConstants.LENGTH:
		var p3: Vector3 = SlopeProfile.build_path_points(step)[int(s / step) if s / step < SlopeProfile.build_path_points(step).size() else -1] if false else Vector3.ZERO
		s += step
	# La méthode ci-dessus est inefficace ; utilise build_path_points une seule fois
	var raw: Array = SlopeProfile.build_path_points(step)
	path_world_xz.clear()
	for v in raw:
		path_world_xz.append(Vector2(v.x, v.z))
	# Trouve les indices correspondant à PASSING_START / PASSING_END
	loop_start_idx = clampi(int(PNConstants.PASSING_START / step), 0, path_world_xz.size() - 1)
	loop_end_idx = clampi(int(PNConstants.PASSING_END / step), 0, path_world_xz.size() - 1)
	_build_screen_mapping()
	queue_redraw()


func _build_screen_mapping() -> void:
	# Mappe les coordonnées monde XZ vers les pixels écran avec préservation
	# de l'aspect ratio. La carte est portrait (haute), le tracé peut être
	# dans n'importe quelle orientation.
	if path_world_xz.is_empty():
		return
	var min_x: float = INF; var max_x: float = -INF
	var min_z: float = INF; var max_z: float = -INF
	for p in path_world_xz:
		min_x = minf(min_x, p.x); max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y); max_z = maxf(max_z, p.y)
	var span_x: float = max_x - min_x
	var span_z: float = max_z - min_z
	var avail_w: float = map_size.x - 2.0 * padding
	var avail_h: float = map_size.y - 2.0 * padding
	# Le tracé est beaucoup plus long que large (3km vs 130m). On l'oriente
	# verticalement (Z monde mappé en Y écran).
	var scale: float = minf(avail_w / maxf(span_x, 1.0), avail_h / maxf(span_z, 1.0))
	# Pour mieux remplir, on ne respecte PAS strictement le ratio :
	# X compressé pour rentrer dans la largeur disponible
	var sx: float = avail_w / maxf(span_x, 1.0)
	var sz: float = avail_h / maxf(span_z, 1.0)
	# On garde le ratio Z (longueur du parcours = priorité) et on étire X si besoin
	var s_uniform: float = sz
	# Plafond sur l'étirement X — sinon le passing loop prend toute la largeur
	var sx_cap: float = minf(sx, s_uniform * 4.0)
	path_points_2d.clear()
	for p in path_world_xz:
		var px: float = padding + (p.x - min_x) * sx_cap + (avail_w - span_x * sx_cap) * 0.5
		# Y inversé : Val Claret (bas Z) en BAS de la carte, Glacier (haut Z) en HAUT
		var py: float = padding + avail_h - (p.y - min_z) * s_uniform
		path_points_2d.append(Vector2(px, py))


func _draw() -> void:
	if path_points_2d.is_empty():
		return
	# Fond
	draw_rect(Rect2(Vector2.ZERO, map_size), bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, map_size), border_color, false, 2.0)

	# Titre
	var title_font: Font = ThemeDB.fallback_font
	if title_font != null:
		draw_string(title_font, Vector2(padding, padding + 4),
			"PERCE-NEIGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.95, 0.85, 0.25))

	# Tracé complet (polyline blanche fine)
	for i in range(path_points_2d.size() - 1):
		draw_line(path_points_2d[i], path_points_2d[i + 1], Color(0.78, 0.82, 0.88, 0.85), 1.4)

	# Section passing loop : surcoloration jaune
	for i in range(loop_start_idx, mini(loop_end_idx, path_points_2d.size() - 1)):
		draw_line(path_points_2d[i], path_points_2d[i + 1], Color(1.0, 0.85, 0.30, 0.90), 2.6)

	# Marqueur Val Claret (bas) — carré vert
	if path_points_2d.size() > 0:
		var p_low: Vector2 = path_points_2d[0]
		draw_rect(Rect2(p_low - Vector2(4, 4), Vector2(8, 8)), Color(0.30, 0.95, 0.40), true)
		_draw_label(p_low + Vector2(8, 4), "VAL CLARET", Color(0.30, 0.95, 0.40))

	# Marqueur Grande Motte (haut) — carré rouge
	if path_points_2d.size() > 0:
		var p_high: Vector2 = path_points_2d[path_points_2d.size() - 1]
		draw_rect(Rect2(p_high - Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.40, 0.30), true)
		_draw_label(p_high + Vector2(8, 4), "GRANDE MOTTE", Color(0.95, 0.40, 0.30))

	# Position cabine — dot orange
	if physics != null:
		var s_cabin: float = clampf(physics.s, 0.0, PNConstants.LENGTH)
		var idx_f: float = s_cabin / 8.0   # même step que dans setup()
		var idx: int = clampi(int(idx_f), 0, path_points_2d.size() - 2)
		var k: float = idx_f - float(idx)
		var p_cabin: Vector2 = path_points_2d[idx].lerp(path_points_2d[idx + 1], k)
		draw_circle(p_cabin, 5.0, Color(1.0, 0.65, 0.10))
		draw_circle(p_cabin, 5.0, Color.WHITE, false, 1.5)
		# Ghost (rame opposée) au point miroir
		var s_ghost: float = clampf(PNConstants.LENGTH - physics.s, 0.0, PNConstants.LENGTH)
		var idx_g_f: float = s_ghost / 8.0
		var idx_g: int = clampi(int(idx_g_f), 0, path_points_2d.size() - 2)
		var k_g: float = idx_g_f - float(idx_g)
		var p_ghost: Vector2 = path_points_2d[idx_g].lerp(path_points_2d[idx_g + 1], k_g)
		draw_circle(p_ghost, 4.0, Color(0.30, 0.65, 1.0))

		# Distance restante en bas
		var dist_text: String = "%.0f / %.0f m" % [physics.s, PNConstants.LENGTH]
		_draw_label(Vector2(padding, map_size.y - padding + 2), dist_text, Color(0.95, 0.95, 0.95))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw_label(pos: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func mini(a: int, b: int) -> int:
	return a if a < b else b
