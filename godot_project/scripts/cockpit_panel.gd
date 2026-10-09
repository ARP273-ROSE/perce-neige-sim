class_name CockpitPanel
extends Control
## Instruments de conduite Von Roll — COLONNE DE DROITE, sous le panneau
## de la salle des machines (07/10/2026 ; avant : bandeau en bas de
## l'écran, 1600×200). Retour d'un utilisateur sur iPad : « la planche de commande
## est masquée par les données du bandeau inférieur, que tu peux déplacer
## à droite ; tu peux virer le panneau ÉTATS pour que ça rentre ».
## De haut en bas :
##   - cadran de VITESSE, voyant E-STOP, jauge de PUISSANCE / RÉGEN ;
##   - jauge de TENSION CÂBLE (seuils nominal / alerte, rupture hors échelle) ;
##   - CONSIGNE, position, altitude, pente, panne en cours ;
##   - mini-PROFIL DE LIGNE (altitude vs distance, les deux rames).
## Sur un écran bas (900 de haut), tout est réduit d'un même facteur ; sur
## un iPad, le profil prend la hauteur restante.

const LARGEUR: float = 260.0
const H_A: float = 160.0      # vitesse + puissance
const H_B: float = 92.0       # tension
const H_C: float = 100.0      # consigne
const H_D_MIN: float = 120.0  # profil
const H_D_MAX: float = 160.0  # ≈ 0,65 × sa largeur : pente lisible, pas étirée
const ECART: float = 6.0

@export var panel_height: float = 200.0
@export var bg_color: Color = Color(0.08, 0.08, 0.10, 0.95)
@export var bezel_color: Color = Color(0.45, 0.42, 0.35)
@export var label_color: Color = Color(0.85, 0.88, 0.92)

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var slope_profile_pts: PackedVector2Array = PackedVector2Array()
# Numéro de la rame pilotée (false = R1 sur voie gauche, true = R2 sur voie
# droite) — pour étiqueter correctement les 2 points du mini-profil.
var driver_is_rame2: bool = false


func _ready() -> void:
	# colonne de droite, sous la salle des machines, jusqu'en bas
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -LARGEUR
	offset_top = MachineRoomPanel.HAUT + MachineRoomPanel.HAUTEUR + 8.0
	offset_right = 0.0
	offset_bottom = -8.0
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


# Redraw à ~15 Hz : le _draw() complet (jauges, profil, aiguilles) est
# coûteux et 60 Hz n'apporte rien visuellement sur des instruments. Le
# panneau est rendu dans une SubViewport (HUD.cache_panel) qui n'est
# redessinée qu'à ces créneaux — décalés d'un demi-créneau avec la salle
# des machines pour ne pas charger la même image.
var _redraw_slot: int = -1
var _regen_mode: bool = false   # état hystérésis de la jauge puissance/régen


func _process(_delta: float) -> void:
	_redraw_slot = HUD.redraw_at_15hz(self, _redraw_slot, 0.0)


func _draw() -> void:
	if physics == null:
		return
	var w: float = size.x
	var h: float = size.y
	# Empilement vertical ; écran trop bas → tout réduit d'un même facteur.
	# Le profil ne dépasse pas 0,55 × sa largeur (il s'étirait en hauteur
	# sur iPad, « trop vertical, trop déformé ») : le panneau s'arrête là.
	var fixe: float = ECART * 5.0 + H_A + H_B + H_C
	var k: float = 1.0
	var h_d: float = minf(h - fixe, H_D_MAX)
	if h_d < H_D_MIN:
		k = h / (fixe + H_D_MIN)
		h_d = H_D_MIN
	var h_tot: float = (fixe + h_d) * k
	# Fond + bezel métallique, liseré doré en haut
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h_tot)), bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h_tot)), bezel_color, false, 2.0)
	draw_line(Vector2(0, 0), Vector2(w, 0), Color(0.95, 0.75, 0.20, 0.85), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var lw: float = w / k                 # largeur dans le repère réduit
	var y: float = ECART
	# 1. vitesse, E-STOP, puissance
	var g_w: float = 70.0
	_draw_speedometer((lw - g_w - ECART) * 0.5 + 4.0, y + 86.0, 58.0)
	_draw_estop(20.0, y + 18.0)
	_draw_power_gauge(lw - g_w - ECART, y, g_w, H_A)
	y += H_A + ECART
	# 2. tension du câble
	_draw_tension_gauge(ECART, y, lw - 2.0 * ECART, H_B)
	y += H_B + ECART
	# 3. consigne, position, pente
	_draw_setpoint_panel(ECART, y, lw - 2.0 * ECART, H_C)
	y += H_C + ECART
	# 4. profil de ligne
	_draw_slope_profile(ECART, y, lw - 2.0 * ECART, h_d)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------------------
# Composants
# ---------------------------------------------------------------------------

## Voyant E-STOP (champignon rouge, sombre quand l'urgence est engagée).
func _draw_estop(cx: float, cy: float) -> void:
	draw_circle(Vector2(cx, cy), 13.0, Color(0.85, 0.78, 0.18))
	var active: bool = physics != null and physics.emergency_brake
	var col: Color = Color(0.50, 0.15, 0.10) if active else Color(0.85, 0.20, 0.15)
	draw_circle(Vector2(cx, cy), 10.5, col)
	draw_circle(Vector2(cx - 3, cy - 3), 4.0, Color(1.0, 0.55, 0.40, 0.55))
	_draw_text_center(Vector2(cx, cy + 24), "E-STOP", 8, Color(0.85, 0.85, 0.85))


func _draw_speedometer(cx: float, cy: float, radius: float = 70.0) -> void:
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
	var v_roues: float = absf(physics.vitesse_roues())
	var v_kmh: float = v_roues * 3.6
	var v_norm: float = clampf(v_kmh / v_max_kmh, 0.0, 1.0)
	var needle_ang: float = lerpf(-PI * 0.75, PI * 0.75, v_norm)
	var needle_end: Vector2 = Vector2(cx + cos(needle_ang) * (radius - 8.0), cy + sin(needle_ang) * (radius - 8.0))
	draw_line(Vector2(cx, cy), needle_end, Color(1.0, 0.30, 0.20), 3.0)
	draw_circle(Vector2(cx, cy), 5.0, Color(0.85, 0.88, 0.92))
	draw_circle(Vector2(cx, cy), 3.0, Color(0.10, 0.10, 0.10))
	# Lecture digitale : m/s dans le cadran (zone libre sous le moyeu),
	# km/h SOUS le cadran — l'ancien placement à 0.78×R tombait sur les
	# graduations du bas (retour d'essai 2026-07-13 : valeurs confondues).
	# (cadran compact de la colonne : la lecture passe dessous, elle
	# chevauchait les chiffres 26 et 43)
	_draw_text_center(Vector2(cx, cy + radius + 16.0), "%.2f m/s · %.0f km/h" % [v_roues, v_kmh],
		11, Color(0.55, 1.0, 0.65))
	# Label
	_draw_text_center(Vector2(cx, cy - radius - 12.0), "VITESSE", 11, label_color)


func _draw_tension_gauge(x: float, y: float, w: float, h: float) -> void:
	# Cadre
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	# Label
	_draw_text(Vector2(x + 6, y + 14), "TENSION CÂBLE", 11, label_color)
	# Échelle de SERVICE 0 → T_GAUGE_MAX (42 000 daN), pas 0 → rupture :
	# à l'échelle de la rupture (191 200, facteur de sécurité ~8,5) le vert
	# faisait 12 % de la barre et le rouge 85 % — illisible et anxiogène.
	# Zones : VERT jusqu'à T_WARN (la tension NOMINALE 22 500 est une valeur
	# de service normale, pas un seuil d'alerte — repère blanc « NOM »),
	# ORANGE T_WARN → T_RED, ROUGE au-delà. La rupture est hors échelle.
	var t_max: float = PNConstants.T_GAUGE_MAX_DAN
	var t_nom: float = PNConstants.T_NOMINAL_DAN
	var t_warn: float = PNConstants.T_WARN_DAN
	var t_red: float = PNConstants.T_RED_DAN
	var t_cur: float = physics.tension_dan_disp
	var bar_y: float = y + 26.0
	var bar_h: float = 20.0
	var bar_w: float = w - 12.0
	var bar_x: float = x + 6.0
	# Fond zones colorées (proportionnelles aux seuils)
	var x_warn: float = bar_x + bar_w * (t_warn / t_max)
	var x_red: float = bar_x + bar_w * (t_red / t_max)
	# Zone verte (service normal, nominal inclus)
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(x_warn - bar_x, bar_h)), Color(0.10, 0.45, 0.15, 0.7), true)
	# Zone orange (alerte)
	draw_rect(Rect2(Vector2(x_warn, bar_y), Vector2(x_red - x_warn, bar_h)), Color(0.65, 0.50, 0.10, 0.7), true)
	# Zone rouge
	draw_rect(Rect2(Vector2(x_red, bar_y), Vector2(bar_x + bar_w - x_red, bar_h)), Color(0.65, 0.15, 0.10, 0.7), true)
	# Repère de la tension nominale (trait blanc pointillé + « NOM »)
	var x_nom: float = bar_x + bar_w * (t_nom / t_max)
	draw_dashed_line(Vector2(x_nom, bar_y - 2.0), Vector2(x_nom, bar_y + bar_h + 2.0),
		Color(1.0, 1.0, 1.0, 0.75), 1.5, 3.0)
	_draw_text(Vector2(x_nom - 12.0, bar_y - 5.0), "NOM", 8, Color(0.85, 0.88, 0.92))
	# Aiguille de la valeur courante
	var x_cur: float = bar_x + bar_w * clampf(t_cur / t_max, 0.0, 1.0)
	draw_line(Vector2(x_cur, bar_y - 3.0), Vector2(x_cur, bar_y + bar_h + 3.0), Color(1.0, 1.0, 1.0), 2.5)
	# Cadre bar
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	# Lecture sous la bar — les couleurs suivent les zones de la jauge
	var col: Color = Color(0.55, 1.0, 0.65)
	if t_cur >= t_red:
		col = Color(1.0, 0.30, 0.25)
	elif t_cur >= t_warn:
		col = Color(1.0, 0.85, 0.30)
	_draw_text(Vector2(bar_x, bar_y + bar_h + 20.0),
		"%.0f daN" % t_cur, 14, col)
	# Seuils en petit
	_draw_text(Vector2(bar_x, y + h - 8.0),
		"NOM %d · ALERTE %d · RUPT. %d" % [int(t_nom), int(t_warn), int(PNConstants.T_BREAK_DAN)],
		8, Color(0.65, 0.70, 0.75))


func _draw_power_gauge(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	# Mode RÉGEN : rame lourde retenue en descente → l'entraînement
	# fonctionne en génératrice. La jauge bascule (titre + barre cyan)
	# au lieu d'afficher une traction fantôme. HYSTÉRÉSIS : on entre en
	# RÉGEN à > 30 kW récupérés (traction < 15) et on n'en sort qu'en
	# dessous de 15 kW (ou traction > 30) — un seuil simple faisait
	# claquer le titre/la couleur au moindre frôlement.
	var regen: float = physics.regen_kw_disp
	if _regen_mode:
		if regen < 15.0 or physics.power_kw_disp > 30.0:
			_regen_mode = false
	else:
		if regen > 30.0 and physics.power_kw_disp < 15.0:
			_regen_mode = true
	var regen_mode: bool = _regen_mode
	_draw_text_center(Vector2(x + w * 0.5, y + 14),
		"RÉGEN" if regen_mode else "PUISSANCE", 10,
		Color(0.45, 0.85, 1.0) if regen_mode else label_color)
	# Bar verticale
	var bar_x: float = x + w * 0.30
	var bar_y: float = y + 28.0
	var bar_w: float = w * 0.40
	var bar_h: float = h - 50.0
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.10, 0.10, 0.12), true)
	var p_max: float = PNConstants.P_MAX / 1000.0   # kW
	var p_cur: float = regen if regen_mode else physics.power_kw_disp
	var p_norm: float = clampf(p_cur / p_max, 0.0, 1.0)
	var fill_h: float = bar_h * p_norm
	# Couleur du remplissage — cyan en régénération
	var fill_col: Color = Color(0.20, 0.65, 0.95) if regen_mode else Color(0.20, 0.85, 0.35)
	if not regen_mode:
		if p_norm > 0.85:
			fill_col = Color(1.0, 0.30, 0.20)
		elif p_norm > 0.65:
			fill_col = Color(1.0, 0.80, 0.20)
	draw_rect(Rect2(Vector2(bar_x, bar_y + bar_h - fill_h), Vector2(bar_w, fill_h)), fill_col, true)
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	# Lecture
	var read_col: Color = Color(0.55, 0.90, 1.0) if regen_mode else Color(0.85, 1.0, 0.85)
	_draw_text_center(Vector2(x + w * 0.5, y + h - 24.0),
		("-%.0f kW" if regen_mode else "%.0f kW") % p_cur, 12, read_col)
	_draw_text_center(Vector2(x + w * 0.5, y + h - 8.0), "/ %d" % int(p_max), 9, Color(0.65, 0.70, 0.75))


func _draw_setpoint_panel(x: float, y: float, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.04, 0.05, 0.07), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), bezel_color, false, 1.2)
	_draw_text(Vector2(x + 8, y + 14), "CONSIGNE", 11, label_color)

	# Bar horizontale 0-100%
	var bar_x: float = x + 8.0
	var bar_y: float = y + 22.0
	var bar_w: float = w - 16.0
	var bar_h: float = 16.0
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.10, 0.10, 0.12), true)
	var pct: float = physics.speed_cmd if physics != null else 0.0
	var fill_w: float = bar_w * pct
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(fill_w, bar_h)), Color(0.20, 0.65, 1.0), true)
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h)), Color(0.85, 0.88, 0.92), false, 1.0)
	_draw_text_center(Vector2(bar_x + bar_w * 0.5, bar_y + 12.5), "%d %%" % int(pct * 100.0), 11, Color(1, 1, 1))

	# Position, altitude, pente
	var alt_cur: float = SlopeProfile.altitude_at(physics.s)
	var grad: float = SlopeProfile.gradient_at(physics.s)
	_draw_text(Vector2(x + 8, y + 56.0), "POSITION  %.0f / %.0f m" % [
		PNConstants.distance_compteur(physics.s, physics.direction), PNConstants.PARCOURS], 11, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(x + 8, y + 74.0), "ALT %.0f m  ·  PENTE %.1f %%" % [alt_cur, grad * 100.0],
		11, Color(0.80, 0.88, 0.95))

	# Panne courante (si active)
	if fault_manager != null and fault_manager.is_active():
		var fid: String = fault_manager.get_active_id()
		_draw_text(Vector2(x + 8, y + 92.0), "PANNE: " + fid.to_upper(), 10, fault_manager.get_active_severity_color())


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

	# Position des DEUX rames — liées par le câble : s_opposée = LENGTH − s.
	# Les dots sont posés SUR la courbe d'altitude (échantillonnage des
	# points du profil, pas l'approximation linéaire d'avant qui flottait
	# au-dessus de la courbe en milieu de ligne).
	if physics != null:
		var frac: float = clampf(physics.s / PNConstants.LENGTH, 0.0, 1.0)
		var p_own: Vector2 = _profile_plot_point(frac, plot_x, plot_y, plot_w, plot_h)
		var p_opp: Vector2 = _profile_plot_point(1.0 - frac, plot_x, plot_y, plot_w, plot_h)
		# Étiquettes : la rame pilotée porte son vrai numéro (R2 si le
		# scénario « rame 2 » a été choisi), l'opposée l'autre.
		var own_lbl: String = "R2" if driver_is_rame2 else "R1"
		var opp_lbl: String = "R1" if driver_is_rame2 else "R2"
		# Rame opposée (bleu clair, plus petite)
		draw_line(Vector2(p_opp.x, plot_y), Vector2(p_opp.x, plot_y + plot_h), Color(0.45, 0.75, 1.0, 0.40), 1.0)
		draw_circle(p_opp, 4.0, Color(0.45, 0.75, 1.0))
		draw_circle(p_opp, 4.0, Color(1, 1, 1), false, 1.0)
		_draw_text(Vector2(p_opp.x - 8.0, p_opp.y - 8.0), opp_lbl, 9, Color(0.45, 0.75, 1.0))
		# Rame pilotée (orange)
		draw_line(Vector2(p_own.x, plot_y), Vector2(p_own.x, plot_y + plot_h), Color(1.0, 0.65, 0.10, 0.6), 1.2)
		draw_circle(p_own, 5.0, Color(1.0, 0.65, 0.10))
		draw_circle(p_own, 5.0, Color(1, 1, 1), false, 1.0)
		_draw_text(Vector2(p_own.x - 8.0, p_own.y - 8.0), own_lbl, 9, Color(1.0, 0.75, 0.35))
		# Distance
		_draw_text(Vector2(plot_x, y + h - 16.0), "%.0f / %.0f m" % [PNConstants.distance_compteur(physics.s, physics.direction), PNConstants.PARCOURS], 10, Color(0.85, 0.88, 0.92))


# Point (px) sur la courbe du mini-profil pour une fraction 0..1 de la ligne.
# Interpolation CONTINUE entre les échantillons de 50 m — l'ancien snap au
# point le plus proche faisait sauter les rames de ~4 px par à-coups
# (retour d'essai iPad 2026-07-12).
func _profile_plot_point(frac: float, plot_x: float, plot_y: float, plot_w: float, plot_h: float) -> Vector2:
	if slope_profile_pts.is_empty():
		return Vector2(plot_x + frac * plot_w, plot_y + plot_h)
	var fidx: float = clampf(frac, 0.0, 1.0) * float(slope_profile_pts.size() - 1)
	var i0: int = int(floor(fidx))
	var i1: int = mini(i0 + 1, slope_profile_pts.size() - 1)
	var sp: Vector2 = slope_profile_pts[i0].lerp(slope_profile_pts[i1], fidx - float(i0))
	return Vector2(plot_x + sp.x * plot_w, plot_y + plot_h - sp.y * plot_h)


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
