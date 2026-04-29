class_name MachineRoomPanel
extends Control
## Panneau "salle des machines" — colonne de droite (260×600).
## Schéma visuel temps réel de l'installation Von Roll en gare amont :
##   - Poulie motrice ∅4160mm (rotation animée)
##   - Câble Fatzer ∅52mm (2 brins, tension affichée)
##   - 3 moteurs DC 800kW (groupe 1/2/3, état + puissance par groupe)
##   - Indicateurs : ω rad/s, V cabine, T daN, P_total kW

@export var panel_width: float = 260.0
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 0.92)
@export var bezel_color: Color = Color(0.45, 0.42, 0.35)
@export var label_color: Color = Color(0.85, 0.88, 0.92)

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var _pulley_angle: float = 0.0


func _ready() -> void:
	# Ancre à droite, en haut, jusqu'à ~80% de la hauteur (pour laisser place
	# au cockpit panel en bas)
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -panel_width
	offset_top = 80.0
	offset_right = 0.0
	offset_bottom = -220.0   # laisse 200px pour le cockpit panel + 20px de marge


func setup(p: TrainPhysics, fm: FaultManager) -> void:
	physics = p
	fault_manager = fm


func _process(delta: float) -> void:
	if physics != null:
		# Anime la poulie motrice : ω = v / r_pulley (radius 2.08m)
		var omega: float = physics.v / 2.08
		_pulley_angle += omega * delta * float(physics.direction)
	queue_redraw()


func _draw() -> void:
	if physics == null:
		return
	var w: float = size.x
	var h: float = size.y

	# Fond + bezel
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bezel_color, false, 2.0)
	# Header doré
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, 28.0)), Color(0.18, 0.16, 0.10, 0.92), true)
	_draw_text_center(Vector2(w * 0.5, 18.0), "SALLE DES MACHINES", 12, Color(0.95, 0.85, 0.25))
	_draw_text_center(Vector2(w * 0.5, 36.0), "PANORAMIC — GRANDE MOTTE", 9, Color(0.75, 0.78, 0.82))

	# 1. Poulie motrice (top, ∅4160mm)
	var pulley_cx: float = w * 0.50
	var pulley_cy: float = 100.0
	var pulley_r: float = 50.0
	_draw_pulley(pulley_cx, pulley_cy, pulley_r)

	# 2. Câble (2 brins descendants depuis la poulie)
	var cable_top_y: float = pulley_cy + pulley_r
	var cable_bot_y: float = h - 200.0
	var cable_left_x: float = pulley_cx - 18.0
	var cable_right_x: float = pulley_cx + 18.0
	var t_cur: float = physics.tension_dan_disp
	var t_warn: float = PNConstants.T_WARN_DAN
	var t_break: float = PNConstants.T_BREAK_DAN
	var cable_color: Color = Color(0.55, 0.55, 0.55)
	if t_cur >= t_warn:
		cable_color = Color(1.0, 0.30, 0.20)
	elif t_cur >= PNConstants.T_NOMINAL_DAN:
		cable_color = Color(1.0, 0.80, 0.30)
	# Ligne brin gauche (vers cabine 1)
	draw_line(Vector2(cable_left_x, cable_top_y), Vector2(cable_left_x, cable_bot_y), cable_color, 4.0)
	# Ligne brin droite (vers cabine 2)
	draw_line(Vector2(cable_right_x, cable_top_y), Vector2(cable_right_x, cable_bot_y), cable_color, 4.0)
	# Annotation tension
	_draw_text(Vector2(pulley_cx + 30.0, (cable_top_y + cable_bot_y) * 0.5),
		"Câble Ø52", 10, label_color)
	_draw_text(Vector2(pulley_cx + 30.0, (cable_top_y + cable_bot_y) * 0.5 + 15.0),
		"%.0f daN" % t_cur, 11, cable_color)

	# 3. Bloc des 3 moteurs DC en bas
	_draw_motor_bank(10.0, h - 195.0, w - 20.0, 130.0)

	# 4. Stats résumées (encart bas)
	var stats_y: float = h - 60.0
	_draw_text(Vector2(10.0, stats_y), "ω poulie  :", 10, label_color)
	var omega: float = physics.v / 2.08
	_draw_text(Vector2(110.0, stats_y), "%.2f rad/s  (%.1f tr/min)" %
		[absf(omega), absf(omega) * 60.0 / TAU], 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 14.0), "V câble   :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 14.0), "%.2f m/s" % absf(physics.v), 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 28.0), "Trip      :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 28.0),
		"%.0f s" % physics.trip_time, 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 42.0), "Pax tot   :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 42.0),
		"%d / %d" % [physics.pax(), PNConstants.PAX_MAX], 10, Color(0.85, 0.95, 1.0))


func _draw_pulley(cx: float, cy: float, r: float) -> void:
	# Hub central (axe)
	draw_circle(Vector2(cx, cy), r * 0.16, Color(0.12, 0.12, 0.12))
	# Disque principal
	draw_circle(Vector2(cx, cy), r, Color(0.30, 0.30, 0.32))
	# Bord brillant
	draw_circle(Vector2(cx, cy), r, Color(0.85, 0.85, 0.90), false, 2.0)
	# Disque intérieur plus sombre
	draw_circle(Vector2(cx, cy), r * 0.85, Color(0.18, 0.18, 0.20))
	# 6 rayons (rotation animée)
	for i in range(6):
		var ang: float = _pulley_angle + float(i) * TAU / 6.0
		var p1: Vector2 = Vector2(cx + cos(ang) * r * 0.20, cy + sin(ang) * r * 0.20)
		var p2: Vector2 = Vector2(cx + cos(ang) * r * 0.85, cy + sin(ang) * r * 0.85)
		draw_line(p1, p2, Color(0.55, 0.55, 0.58), 3.0)
	# Marqueur de rotation (dot rouge sur la jante)
	var marker_ang: float = _pulley_angle
	draw_circle(Vector2(cx + cos(marker_ang) * r * 0.85, cy + sin(marker_ang) * r * 0.85), 5.0, Color(1.0, 0.30, 0.10))
	# Label dimensions
	_draw_text_center(Vector2(cx, cy + r + 14.0), "POULIE MOTRICE", 10, label_color)
	_draw_text_center(Vector2(cx, cy + r + 26.0), "Ø 4160 mm", 9, Color(0.65, 0.70, 0.75))


func _draw_motor_bank(x: float, y: float, w: float, h: float) -> void:
	# Cadre
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text(Vector2(x + 6, y + 14), "GROUPES MOTEURS", 11, label_color)
	_draw_text(Vector2(x + 6, y + 28), "3 × DC 800 kW (Von Roll)", 9, Color(0.75, 0.78, 0.82))

	# Détecte si une panne dégrade un moteur
	var motor_degraded: bool = false
	var motor_thermal: bool = false
	if fault_manager != null:
		var fid: String = fault_manager.get_active_id()
		motor_degraded = (fid == "motor_degraded")
		motor_thermal = (fid == "thermal")

	# 3 moteurs côte à côte
	var p_total: float = physics.power_kw_disp
	# Répartition entre 3 groupes (égal sauf si dégradé : 2/3 actifs uniquement)
	var p_per_motor: Array = [p_total / 3.0, p_total / 3.0, p_total / 3.0]
	if motor_degraded:
		# Le 3ème moteur est HS, les 2 autres compensent
		p_per_motor = [p_total * 0.5, p_total * 0.5, 0.0]

	var motor_w: float = (w - 24.0) / 3.0
	for i in range(3):
		var mx: float = x + 8.0 + float(i) * (motor_w + 4.0)
		var my: float = y + 44.0
		var mh: float = h - 50.0
		# Corps moteur (vert Von Roll)
		var motor_col: Color = Color(0.20, 0.45, 0.25)
		if (motor_degraded and i == 2) or (motor_thermal and i == 0):
			motor_col = Color(0.45, 0.20, 0.20)   # rouge si HS
		draw_rect(Rect2(Vector2(mx, my), Vector2(motor_w, mh * 0.55)), motor_col, true)
		draw_rect(Rect2(Vector2(mx, my), Vector2(motor_w, mh * 0.55)), bezel_color, false, 1.0)

		# Label (M1/M2/M3)
		_draw_text_center(Vector2(mx + motor_w * 0.5, my + 14), "M%d" % (i + 1), 11, Color(0.95, 1.0, 0.95))

		# LED état
		var led_col: Color = Color(0.20, 0.85, 0.35) if p_per_motor[i] > 0.0 else Color(0.18, 0.18, 0.20)
		if (motor_degraded and i == 2):
			led_col = Color(1.0, 0.20, 0.18)
		draw_circle(Vector2(mx + motor_w * 0.5, my + mh * 0.40), 4.5, led_col)

		# Mini bar de puissance verticale en bas
		var bar_y: float = my + mh * 0.55 + 4.0
		var bar_h: float = mh * 0.40
		draw_rect(Rect2(Vector2(mx, bar_y), Vector2(motor_w, bar_h)), Color(0.10, 0.10, 0.12), true)
		var p_norm: float = clampf(p_per_motor[i] / 800.0, 0.0, 1.0)
		var fill_col: Color = Color(0.20, 0.85, 0.35)
		if p_norm > 0.85:
			fill_col = Color(1.0, 0.30, 0.20)
		elif p_norm > 0.65:
			fill_col = Color(1.0, 0.80, 0.20)
		draw_rect(Rect2(Vector2(mx + 1.0, bar_y + bar_h * (1.0 - p_norm)),
			Vector2(motor_w - 2.0, bar_h * p_norm)), fill_col, true)
		draw_rect(Rect2(Vector2(mx, bar_y), Vector2(motor_w, bar_h)), Color(0.55, 0.60, 0.65), false, 1.0)

		# Lecture kW
		_draw_text_center(Vector2(mx + motor_w * 0.5, bar_y + bar_h - 4.0),
			"%.0f" % p_per_motor[i], 10, Color(1.0, 1.0, 1.0))


func _draw_text(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)


func _draw_text_center(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt)
	draw_string(font, pos - Vector2(sz.x * 0.5, -sz.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)
