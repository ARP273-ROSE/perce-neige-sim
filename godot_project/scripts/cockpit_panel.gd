class_name CockpitPanel
extends Control
## Console cockpit Von Roll — bandeau bas de l'écran (1600×180).
## Inspiré de la vraie console du FUNI284 (Tignes, vidéo cockpit HD) :
##   - E-STOP rouge à champignon (gauche)
##   - Speedometer analogique (cadran central-gauche)
##   - Jauge tension câble horizontale avec seuils nominal/warning/breakage
##   - Jauge puissance moteur verticale (kW)
##   - Grille de 8 LEDs indicateurs (portes, phares, urgence, etc.)
##   - Mini-profil de ligne (altitude vs distance) à droite

@export var panel_height: float = 200.0
@export var bg_color: Color = Color(0.08, 0.08, 0.10, 0.95)
@export var bezel_color: Color = Color(0.45, 0.42, 0.35)
@export var label_color: Color = Color(0.85, 0.88, 0.92)

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var slope_profile_pts: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	# Le panel occupe toute la largeur en bas de l'écran
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = -panel_height
	offset_right = 0.0
	offset_bottom = 0.0
	# Construit la liste des points du profil pour le mini-graph altitude
	_build_slope_profile_points()


func setup(p: TrainPhysics, fm: FaultManager) -> void:
	physics = p
	fault_manager = fm


func _build_slope_profile_points() -> void:
	# Sample altitude tous les 50m
	var pts: PackedVector2Array = PackedVector2Array()
	var step: float = 50.0
	var s: float = 0.0
	var alt_low: float = PNConstants.ALT_LOW
	var alt_high: float = PNConstants.ALT_HIGH
	# La pente intégrée : on parcourt la spline et on prend le Y monde
	var path: Array = SlopeProfile.build_path_points(step)
	for pt in path:
		pts.append(Vector2(0.0, pt.y))   # x sera mappé plus tard
	# Map x au prorata de la distance le long du tracé
	for i in range(pts.size()):
		var s_i: float = float(i) * step
		pts[i] = Vector2(s_i / PNConstants.LENGTH, (pts[i].y - alt_low) / (alt_high - alt_low))
	slope_profile_pts = pts


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if physics == null:
		return
	var w: float = size.x
	var h: float = size.y
	# Fond + bezel métallique
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bezel_color, false, 2.0)
	# Ligne séparatrice du haut (bordure dorée style cockpit)
	draw_line(Vector2(0, 0), Vector2(w, 0), Color(0.95, 0.75, 0.20, 0.85), 2.5)

	# Layout horizontal : zones successives
	var pad: float = 14.0
	var x: float = pad

	# 1. E-STOP button (zone 90 px)
	x = _draw_estop(x + 30.0, h * 0.5) + 30.0

	# 2. Speedometer (zone 200 px)
	_draw_speedometer(x + 100.0, h * 0.5)
	x += 200.0

	# 3. Tension gauge horizontale (zone 280 px)
	_draw_tension_gauge(x + 10.0, pad, 270.0, h - 2.0 * pad)
	x += 290.0

	# 4. Power gauge verticale (zone 80 px)
	_draw_power_gauge(x + 10.0, pad, 70.0, h - 2.0 * pad)
	x += 90.0

	# 5. Status LEDs grid 4×2 (zone 240 px)
	_draw_status_leds(x + 10.0, pad, 220.0, h - 2.0 * pad)
	x += 240.0

	# 6. Setpoint + direction + altitude (zone 180 px)
	_draw_setpoint_panel(x + 10.0, pad, 170.0, h - 2.0 * pad)
	x += 190.0

	# 7. Profil de ligne (zone restante, max 320 px)
	var profile_w: float = clampf(w - x - pad, 200.0, 320.0)
	_draw_slope_profile(x + 10.0, pad, profile_w, h - 2.0 * pad)


# ---------------------------------------------------------------------------
# Composants
# ---------------------------------------------------------------------------

func _draw_estop(cx: float, cy: float) -> float:
	# Anneau jaune
	draw_circle(Vector2(cx, cy), 26.0, Color(0.85, 0.78, 0.18))
	# Champignon rouge — change de teinte si emergency engaged
	var active: bool = physics != null and physics.emergency_brake
	var col: Color = Color(0.50, 0.15, 0.10) if active else Color(0.85, 0.20, 0.15)
	draw_circle(Vector2(cx, cy), 22.0, col)
	# Reflet brillant (cercle clair en haut-gauche)
	draw_circle(Vector2(cx - 6, cy - 6), 8.0, Color(1.0, 0.55, 0.40, 0.55))
	# Label sous le bouton
	_draw_text_center(Vector2(cx, cy + 38), "E-STOP", 11, Color(0.85, 0.85, 0.85))
	return cx + 30.0


func _draw_speedometer(cx: float, cy: float) -> void:
	var radius: float = 70.0
	# Bezel extérieur
	draw_circle(Vector2(cx, cy), radius + 3.0, Color(0.35, 0.32, 0.28))
	# Cadran sombre
	draw_circle(Vector2(cx, cy), radius, Color(0.05, 0.06, 0.08))
	# Graduations 0 à 50 km/h (notre V_MAX = 12 m/s ≈ 43 km/h)
	var v_max_kmh: float = PNConstants.V_MAX * 3.6
	for i in range(11):
		var v_tick: float = float(i) * (v_max_kmh / 10.0)
		var ang: float = lerpf(-PI * 0.75, PI * 0.75, float(i) / 10.0)
		var p1: Vector2 = Vector2(cx + cos(ang) * (radius - 4.0), cy + sin(ang) * (radius - 4.0))
		var p2: Vector2 = Vector2(cx + cos(ang) * (radius - 14.0), cy + sin(ang) * (radius - 14.0))
		draw_line(p1, p2, Color(0.85, 0.88, 0.92), 1.8)
		# Chiffre tous les 2 ticks (0, 10, 20, 30, 40)
		if i % 2 == 0:
			var p_label: Vector2 = Vector2(cx + cos(ang) * (radius - 26.0), cy + sin(ang) * (radius - 22.0))
			_draw_text_center(p_label, "%.0f" % v_tick, 9, Color(0.85, 0.88, 0.92))
	# Aiguille
	var v_kmh: float = absf(physics.v) * 3.6
	var v_norm: float = clampf(v_kmh / v_max_kmh, 0.0, 1.0)
	var needle_ang: float = lerpf(-PI * 0.75, PI * 0.75, v_norm)
	var needle_end: Vector2 = Vector2(cx + cos(needle_ang) * (radius - 8.0), cy + sin(needle_ang) * (radius - 8.0))
	draw_line(Vector2(cx, cy), needle_end, Color(1.0, 0.30, 0.20), 3.0)
	draw_circle(Vector2(cx, cy), 5.0, Color(0.85, 0.88, 0.92))
	draw_circle(Vector2(cx, cy), 3.0, Color(0.10, 0.10, 0.10))
	# Lecture digitale au centre-bas
	_draw_text_center(Vector2(cx, cy + radius * 0.55), "%.1f m/s" % absf(physics.v), 13, Color(0.55, 1.0, 0.65))
	_draw_text_center(Vector2(cx, cy + radius * 0.78), "%.0f km/h" % v_kmh, 11, Color(0.85, 0.88, 0.92))
	# Label
	_draw_text_center(Vector2(cx, cy - radius - 12.0), "VITESSE", 11, label_color)


func _draw_tension_gauge(x: float, y: float, w: float, h: float) -> void:
	# Cadre
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	# Label
	_draw_text(Vector2(x + 6, y + 14), "TENSION CÂBLE", 11, label_color)
	# Bar : valeur courante / breakage. Seuils :
	#   0 → T_NOMINAL : zone verte
	#   T_NOMINAL → T_WARN : zone jaune
	#   T_WARN → T_BREAK : zone rouge
	var t_break: float = PNConstants.T_BREAK_DAN
	var t_nom: float = PNConstants.T_NOMINAL_DAN
	var t_warn: float = PNConstants.T_WARN_DAN
	var t_cur: float = physics.tension_dan_disp
	var bar_y: float = y + 30.0
	var bar_h: float = 24.0
	var bar_w: float = w - 12.0
	var bar_x: float = x + 6.0
	# Fond zones colorées (proportionnelles aux seuils)
	var x_nom: float = bar_x + bar_w * (t_nom / t_break)
	var x_warn: float = bar_x + bar_w * (t_warn / t_break)
	# Zone verte
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(x_nom - bar_x, bar_h)), Color(0.10, 0.45, 0.15, 0.7), true)
	# Zone jaune
	draw_rect(Rect2(Vector2(x_nom, bar_y), Vector2(x_warn - x_nom, bar_h)), Color(0.65, 0.50, 0.10, 0.7), true)
	# Zone rouge
	draw_rect(Rect2(Vector2(x_warn, bar_y), Vector2(bar_x + bar_w - x_warn, bar_h)), Color(0.65, 0.15, 0.10, 0.7), true)
	# Aiguille de la valeur courante
	var x_cur: float = bar_x + bar_w * clampf(t_cur / t_break, 0.0, 1.0)
	draw_line(Vector2(x_cur, bar_y - 3.0), Vector2(x_cur, bar_y + bar_h + 3.0), Color(1.0, 1.0, 1.0), 2.5)
	# Cadre bar
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	# Lecture sous la bar
	var col: Color = Color(0.55, 1.0, 0.65)
	if t_cur >= t_warn:
		col = Color(1.0, 0.30, 0.25)
	elif t_cur >= t_nom:
		col = Color(1.0, 0.85, 0.30)
	_draw_text(Vector2(bar_x, y + h - 38.0),
		"%.0f daN" % t_cur, 14, col)
	# Seuils en petit
	_draw_text(Vector2(bar_x, y + h - 18.0),
		"NOM %d   WARN %d   RUPT %d" % [int(t_nom), int(t_warn), int(t_break)],
		9, Color(0.65, 0.70, 0.75))


func _draw_power_gauge(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text_center(Vector2(x + w * 0.5, y + 14), "PUISSANCE", 10, label_color)
	# Bar verticale
	var bar_x: float = x + w * 0.30
	var bar_y: float = y + 28.0
	var bar_w: float = w * 0.40
	var bar_h: float = h - 50.0
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.10, 0.10, 0.12), true)
	var p_max: float = PNConstants.P_MAX / 1000.0   # kW
	var p_cur: float = physics.power_kw_disp
	var p_norm: float = clampf(p_cur / p_max, 0.0, 1.0)
	var fill_h: float = bar_h * p_norm
	# Couleur du remplissage
	var fill_col: Color = Color(0.20, 0.85, 0.35)
	if p_norm > 0.85:
		fill_col = Color(1.0, 0.30, 0.20)
	elif p_norm > 0.65:
		fill_col = Color(1.0, 0.80, 0.20)
	draw_rect(Rect2(Vector2(bar_x, bar_y + bar_h - fill_h), Vector2(bar_w, fill_h)), fill_col, true)
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	# Lecture
	_draw_text_center(Vector2(x + w * 0.5, y + h - 24.0), "%.0f kW" % p_cur, 12, Color(0.85, 1.0, 0.85))
	_draw_text_center(Vector2(x + w * 0.5, y + h - 8.0), "/ %d" % int(p_max), 9, Color(0.65, 0.70, 0.75))


func _draw_status_leds(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text(Vector2(x + 8, y + 14), "ÉTATS", 11, label_color)

	# 8 LEDs (4 colonnes × 2 lignes)
	# Format : [label, état_actuel, couleur_quand_actif]
	var leds: Array = []
	if physics != null:
		leds = [
			["TRACT", physics.trip_started and absf(physics.v) > 0.1, Color(0.20, 0.85, 0.35)],
			["PORTES", not physics.doors_open, Color(0.20, 0.85, 0.35)],
			["PHARES", physics.lights_head, Color(1.0, 0.95, 0.40)],
			["CABINE", physics.lights_cabin, Color(1.0, 0.95, 0.40)],
			["FREIN P", physics.maint_brake, Color(1.0, 0.55, 0.10)],
			["FREIN U", physics.emergency_brake or physics.emergency, Color(1.0, 0.20, 0.18)],
			["DIR↑" if physics.direction > 0 else "DIR↓", true, Color(0.30, 0.75, 1.0)],
			["VOYAGE", physics.trip_started, Color(0.85, 0.75, 0.30)],
		]
	var led_size: float = 12.0
	var spacing_x: float = (w - 16.0) / 4.0
	var spacing_y: float = (h - 38.0) / 2.0
	for i in range(8):
		var col_i: int = i % 4
		var row_i: int = i / 4
		var lx: float = x + 12.0 + col_i * spacing_x
		var ly: float = y + 30.0 + row_i * spacing_y + 8.0
		var led: Array = leds[i]
		var col: Color = led[2] if led[1] else Color(0.18, 0.18, 0.20)
		# Cercle LED
		draw_circle(Vector2(lx + led_size * 0.5, ly + led_size * 0.5), led_size * 0.5, col)
		# Reflet brillant
		if led[1]:
			draw_circle(Vector2(lx + led_size * 0.4, ly + led_size * 0.4), led_size * 0.18, Color(1, 1, 1, 0.5))
		# Label à droite
		_draw_text(Vector2(lx + led_size + 6.0, ly + led_size - 1.0), led[0], 10, label_color)


func _draw_setpoint_panel(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text(Vector2(x + 8, y + 14), "CONSIGNE", 11, label_color)

	# Bar horizontale 0-100%
	var bar_x: float = x + 8.0
	var bar_y: float = y + 30.0
	var bar_w: float = w - 16.0
	var bar_h: float = 18.0
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.10, 0.10, 0.12), true)
	var pct: float = physics.speed_cmd if physics != null else 0.0
	var fill_w: float = bar_w * pct
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(fill_w, bar_h)), Color(0.20, 0.65, 1.0), true)
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	_draw_text_center(Vector2(bar_x + bar_w * 0.5, bar_y + 14.0), "%d %%" % int(pct * 100.0), 11, Color(1, 1, 1))

	# Distance / altitude
	var alt_cur: float = PNConstants.ALT_LOW + (physics.s / PNConstants.LENGTH) * (PNConstants.ALT_HIGH - PNConstants.ALT_LOW)
	_draw_text(Vector2(x + 8, y + 70.0), "POSITION", 10, label_color)
	_draw_text(Vector2(x + 8, y + 88.0), "%.0f / %.0f m" % [physics.s, PNConstants.LENGTH], 12, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(x + 8, y + 106.0), "ALT %.0f m" % alt_cur, 11, Color(0.85, 0.95, 1.0))

	# Slope (pente locale)
	var grad: float = SlopeProfile.gradient_at(physics.s)
	_draw_text(Vector2(x + 8, y + 130.0), "PENTE %.1f %%" % (grad * 100.0), 11, Color(0.80, 0.85, 0.90))

	# Panne courante (si active)
	if fault_manager != null and fault_manager.is_active():
		var fid: String = fault_manager.get_active_id()
		_draw_text(Vector2(x + 8, y + 150.0), "PANNE: " + fid.to_upper(), 10, fault_manager.get_active_severity_color())


func _draw_slope_profile(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text(Vector2(x + 8, y + 14), "PROFIL DE LIGNE", 11, label_color)

	if slope_profile_pts.is_empty():
		return
	# Plot area
	var plot_x: float = x + 28.0
	var plot_y: float = y + 30.0
	var plot_w: float = w - 36.0
	var plot_h: float = h - 60.0
	draw_rect(Rect2(Vector2(plot_x, plot_y), Vector2(plot_w, plot_h)), Color(0.02, 0.04, 0.06), true)

	# Axes
	draw_line(Vector2(plot_x, plot_y + plot_h), Vector2(plot_x + plot_w, plot_y + plot_h), Color(0.5, 0.55, 0.60), 1.0)
	draw_line(Vector2(plot_x, plot_y), Vector2(plot_x, plot_y + plot_h), Color(0.5, 0.55, 0.60), 1.0)

	# Étiquettes altitudes
	_draw_text(Vector2(x + 2, plot_y - 2.0), "%dm" % int(PNConstants.ALT_HIGH), 9, Color(0.85, 0.88, 0.92))
	_draw_text(Vector2(x + 2, plot_y + plot_h - 4.0), "%dm" % int(PNConstants.ALT_LOW), 9, Color(0.85, 0.88, 0.92))

	# Trace la courbe d'altitude
	var prev: Vector2 = Vector2.ZERO
	for i in range(slope_profile_pts.size()):
		var sp: Vector2 = slope_profile_pts[i]
		var px: float = plot_x + sp.x * plot_w
		var py: float = plot_y + plot_h - sp.y * plot_h
		var p: Vector2 = Vector2(px, py)
		if i > 0:
			draw_line(prev, p, Color(0.85, 0.88, 0.92), 1.6)
		prev = p

	# Marqueur passing loop (zone jaune verticale)
	var loop_x_start: float = plot_x + (PNConstants.PASSING_START / PNConstants.LENGTH) * plot_w
	var loop_x_end: float = plot_x + (PNConstants.PASSING_END / PNConstants.LENGTH) * plot_w
	draw_rect(Rect2(Vector2(loop_x_start, plot_y), Vector2(loop_x_end - loop_x_start, plot_h)),
		Color(1.0, 0.85, 0.20, 0.20), true)

	# Position cabine
	if physics != null:
		var cabin_x: float = plot_x + clampf(physics.s / PNConstants.LENGTH, 0.0, 1.0) * plot_w
		var alt_norm: float = (PNConstants.ALT_LOW + (physics.s / PNConstants.LENGTH) * (PNConstants.ALT_HIGH - PNConstants.ALT_LOW) - PNConstants.ALT_LOW) / (PNConstants.ALT_HIGH - PNConstants.ALT_LOW)
		var cabin_y: float = plot_y + plot_h - alt_norm * plot_h
		# Trait vertical
		draw_line(Vector2(cabin_x, plot_y), Vector2(cabin_x, plot_y + plot_h), Color(1.0, 0.65, 0.10, 0.6), 1.2)
		# Dot
		draw_circle(Vector2(cabin_x, cabin_y), 5.0, Color(1.0, 0.65, 0.10))
		draw_circle(Vector2(cabin_x, cabin_y), 5.0, Color(1, 1, 1), false, 1.0)
		# Distance
		_draw_text(Vector2(plot_x, y + h - 16.0), "%.0f / %.0f m" % [physics.s, PNConstants.LENGTH], 10, Color(0.85, 0.88, 0.92))


# ---------------------------------------------------------------------------
# Helpers de rendu de texte
# ---------------------------------------------------------------------------

func _draw_text(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)


func _draw_text_center(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# Estimer la largeur pour centrer
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt)
	draw_string(font, pos - Vector2(sz.x * 0.5, -sz.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)
