class_name MachineRoomPanel
extends Control
## Panneau « salle des machines » — colonne de droite.
##
## Refonte 2026-09-27 (retour d'essai : « comme la représentation du PC,
## avec les deux roues jaunes qui tournent et tout ») : vue en coupe de la
## machinerie de la gare amont, portée de _draw_motor_room du programme PC —
## 3 moteurs DC teintés par la charge, réducteur, arbre, DEUX POULIES JAUNES
## Von Roll (motrice + déviation) qui tournent à ω = v / r et s'inversent à
## la descente, câble en huit qui les enlace avec un repère qui défile, LED de
## puissance, lectures ∅ / tr/min / vitesse câble. En dessous : les trois
## groupes moteurs avec leurs barres de puissance, puis rotation, vitesse
## câble, temps de trajet et passagers.

@export var panel_width: float = 260.0
const HAUT: float = 80.0
const HAUTEUR: float = 372.0          # vue de la machinerie, moteurs, lectures
@export var bg_color: Color = Color(0.06, 0.07, 0.10, 0.92)
@export var bezel_color: Color = Color(0.45, 0.42, 0.35)
@export var label_color: Color = Color(0.85, 0.88, 0.92)

const SHEAVE_R_M: float = 2.1          # rayon réel des poulies (∅ 4,2 m)
const ROOM_W_REF: float = 272.0        # largeur de référence du dessin PC
const ROOM_H_REF: float = 150.0        # hauteur de référence du dessin PC

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var _pulley_angle: float = 0.0
var driver_rame2: bool = false     # posé par le HUD (choix de rame)
var _redraw_slot: int = -1


func _ready() -> void:
	# Colonne de droite, en haut, à la hauteur de son contenu ; les
	# instruments de conduite (CockpitPanel) suivent dessous (07/10/2026)
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -panel_width
	offset_top = HAUT
	offset_right = 0.0
	offset_bottom = HAUT + HAUTEUR


func setup(p: TrainPhysics, fm: FaultManager) -> void:
	physics = p
	fault_manager = fm


# Redraw à ~15 Hz (cf. cockpit_panel) — l'angle de poulie continue de
# s'intégrer à chaque frame pour rester exact, seul l'affichage est throttlé.
func _process(delta: float) -> void:
	if physics != null:
		# Les deux poulies tournent à ω = v / r (r = 2,1 m), dans le sens
		# fixé par la rame 1, à la vitesse du câble à la poulie (même loi
		# que la 3D, cf. TrainPhysics.machine_v : arrêt si le câble rompt).
		_pulley_angle += physics.machine_v / SHEAVE_R_M * delta
	_redraw_slot = HUD.redraw_at_15hz(self, _redraw_slot, 0.5)


func _draw() -> void:
	if physics == null:
		return
	var w: float = size.x
	var h: float = size.y

	# Fond + bezel + bandeau doré
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), bezel_color, false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, 28.0)), Color(0.18, 0.16, 0.10, 0.92), true)
	_draw_text_center(Vector2(w * 0.5, 18.0), "SALLE DES MACHINES", 12, Color(0.95, 0.85, 0.25))

	# 1. Vue en coupe de la machinerie (portée du PC)
	var room_w: float = w - 8.0
	var room: Rect2 = Rect2(Vector2(4.0, 32.0), Vector2(room_w, ROOM_H_REF * room_w / ROOM_W_REF))
	_draw_room(room)

	# 2. Bloc des 3 groupes moteurs
	var y_bank: float = room.end.y + 8.0
	var bank_h: float = minf(130.0, maxf(90.0, h - y_bank - 90.0))
	_draw_motor_bank(10.0, y_bank, w - 20.0, bank_h)

	# 3. Lectures
	var stats_y: float = y_bank + bank_h + 16.0
	if stats_y + 44.0 > h:
		return
	var omega: float = absf(physics.machine_v) / SHEAVE_R_M
	_draw_text(Vector2(10.0, stats_y), "Rot. poulies :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y), "%.2f rad/s  (%.1f tr/min)" %
		[omega, omega * 60.0 / TAU], 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 14.0), "V câble   :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 14.0), "%.2f m/s" % absf(physics.machine_v), 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 28.0), "Trajet    :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 28.0), "%.0f s" % physics.trip_time, 10, Color(0.85, 0.95, 1.0))
	_draw_text(Vector2(10.0, stats_y + 42.0), "Pax tot   :", 10, label_color)
	_draw_text(Vector2(110.0, stats_y + 42.0),
		"%d / %d" % [physics.pax(), PNConstants.PAX_MAX], 10, Color(0.85, 0.95, 1.0))
	# Câble rompu : la chaîne de sécurité a déclenché, les freins des
	# roues arrêtent la machinerie (TrainPhysics.update_machine)
	if physics.cable_rupture and stats_y + 62.0 <= h:
		_draw_text(Vector2(10.0, stats_y + 62.0),
			"CÂBLE ROMPU — machinerie à l'arrêt" if absf(physics.machine_v) < 0.01
			else "CÂBLE ROMPU — freinage des roues", 10, Color(1.0, 0.35, 0.25))


## Vue en coupe de la machinerie : port fidèle de _draw_motor_room (PC),
## toutes les cotes à l'échelle k = largeur / 272.
func _draw_room(rect: Rect2) -> void:
	var k: float = rect.size.x / ROOM_W_REF
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	draw_rect(rect, Color(22.0 / 255.0, 28.0 / 255.0, 42.0 / 255.0, 0.94), true)
	draw_rect(rect, bezel_color, false, 1.5)
	# lueur de fond (mur de béton)
	draw_rect(Rect2(x0 + 2.0, y0 + 16.0, rect.size.x - 4.0, rect.size.y * 0.45),
		Color(32.0 / 255.0, 38.0 / 255.0, 54.0 / 255.0, 0.45), true)

	# En-tête et lectures
	var dim: Color = Color(0.62, 0.66, 0.72)
	_draw_text(Vector2(x0 + 8.0, y0 + 12.0), "Machinerie — 3032 m", 9, label_color)
	_draw_text_right(Vector2(rect.end.x - 8.0, y0 + 12.0), "3 × 800 kW DC", 9, label_color)
	var v_abs: float = absf(physics.machine_v)
	var rpm: float = v_abs / (TAU * SHEAVE_R_M) * 60.0
	_draw_text(Vector2(x0 + 8.0, y0 + 25.0), "∅ 4,2 m   %5.1f tr/min   v %4.1f m/s" % [rpm, v_abs], 8, dim)

	# Sol de la machinerie, hachuré
	var floor_y: float = rect.end.y - 16.0 * k
	draw_rect(Rect2(x0 + 4.0, floor_y, rect.size.x - 8.0, 12.0 * k), Color(48.0 / 255.0, 52.0 / 255.0, 64.0 / 255.0), true)
	draw_rect(Rect2(x0 + 4.0, floor_y, rect.size.x - 8.0, 12.0 * k), Color(18.0 / 255.0, 18.0 / 255.0, 22.0 / 255.0), false, 1.0)
	for i in range(10):
		var hx: float = x0 + 6.0 + float(i) * (rect.size.x - 12.0) / 10.0
		draw_line(Vector2(hx, floor_y + 2.0 * k), Vector2(hx + 4.0 * k, floor_y + 10.0 * k),
			Color(70.0 / 255.0, 74.0 / 255.0, 86.0 / 255.0), 1.0)

	# Charge → teinte des moteurs (bleu → rouge)
	var load: float = clampf(physics.power_kw_disp / (PNConstants.P_MAX / 1000.0), 0.0, 1.0)
	var motor_body: Color = Color((70.0 + 150.0 * load) / 255.0, (110.0 - 55.0 * load) / 255.0,
		(155.0 - 90.0 * load) / 255.0)

	# 3 moteurs DC côte à côte
	var m_w: float = 16.0 * k
	var m_h: float = 36.0 * k
	for i in range(3):
		var mx: float = x0 + 10.0 * k + float(i) * (m_w + 4.0 * k)
		var my: float = floor_y - m_h
		draw_rect(Rect2(mx + 1.0, my + 2.0, m_w, m_h), Color(6.0 / 255.0, 8.0 / 255.0, 12.0 / 255.0, 0.65), true)
		draw_rect(Rect2(mx, my, m_w, m_h), motor_body, true)
		draw_rect(Rect2(mx, my, m_w * 0.35, m_h), motor_body.darkened(0.30), true)
		draw_rect(Rect2(mx, my, m_w, m_h), Color(15.0 / 255.0, 15.0 / 255.0, 20.0 / 255.0), false, 1.0)
		for kk in range(5):
			var fy: float = my + 4.0 * k + float(kk) * 6.0 * k
			draw_line(Vector2(mx + 2.0, fy), Vector2(mx + m_w - 2.0, fy), Color(18.0 / 255.0, 18.0 / 255.0, 22.0 / 255.0), 1.0)
		draw_circle(Vector2(mx + m_w * 0.5, my + 1.0), 3.0 * k, Color(190.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0))

	# Réducteur
	var gx: float = x0 + 74.0 * k
	var gy: float = floor_y - 30.0 * k
	var gw: float = 30.0 * k
	var gh: float = 30.0 * k
	draw_rect(Rect2(gx, gy, gw, gh), Color(82.0 / 255.0, 85.0 / 255.0, 98.0 / 255.0), true)
	draw_rect(Rect2(gx, gy, gw, gh * 0.5), Color(110.0 / 255.0, 112.0 / 255.0, 126.0 / 255.0), true)
	draw_rect(Rect2(gx, gy, gw, gh), Color(18.0 / 255.0, 18.0 / 255.0, 22.0 / 255.0), false, 1.2)
	for kk in range(4):
		var ry: float = gy + 5.0 * k + float(kk) * 7.0 * k
		draw_line(Vector2(gx + 4.0 * k, ry), Vector2(gx + gw - 4.0 * k, ry), Color(25.0 / 255.0, 25.0 / 255.0, 30.0 / 255.0), 1.0)
	draw_rect(Rect2(gx + 6.0 * k, gy + gh - 8.0 * k, gw - 12.0 * k, 6.0 * k), Color(230.0 / 255.0, 200.0 / 255.0, 60.0 / 255.0), true)

	# Arbre réducteur → poulie motrice
	var shaft_y: float = gy + gh * 0.5 + 2.0 * k
	draw_line(Vector2(gx + gw, shaft_y), Vector2(gx + gw + 26.0 * k, shaft_y), Color(150.0 / 255.0, 150.0 / 255.0, 160.0 / 255.0), 4.0 * k)

	# Deux poulies jaunes Von Roll : motrice (P1) et déviation (P2)
	var R: float = 32.0 * k
	var cx1: float = x0 + 152.0 * k
	var cx2: float = cx1 + R * 2.6
	var cy: float = floor_y - 52.0 * k
	draw_line(Vector2(gx + gw + 22.0 * k, shaft_y), Vector2(cx1 - R * 0.15, cy), Color(90.0 / 255.0, 92.0 / 255.0, 105.0 / 255.0), 5.0 * k)
	draw_rect(Rect2(gx + gw + 18.0 * k, shaft_y - 4.0 * k, 10.0 * k, 10.0 * k), Color(60.0 / 255.0, 60.0 / 255.0, 70.0 / 255.0), true)

	# Paliers (derrière les roues)
	for cx in [cx1, cx2]:
		var ped: Rect2 = Rect2(cx - 18.0 * k, cy + R * 0.1, 36.0 * k, floor_y - (cy + R * 0.1))
		draw_rect(ped, Color(60.0 / 255.0, 64.0 / 255.0, 79.0 / 255.0), true)
		draw_rect(Rect2(ped.position, Vector2(ped.size.x, ped.size.y * 0.5)), Color(80.0 / 255.0, 84.0 / 255.0, 100.0 / 255.0), true)
		draw_rect(ped, Color(20.0 / 255.0, 20.0 / 255.0, 24.0 / 255.0), false, 1.0)
		for sx in [-1.0, 1.0]:
			draw_circle(Vector2(cx + sx * 12.0 * k, ped.end.y - 4.0 * k), 1.5 * k, Color(180.0 / 255.0, 180.0 / 255.0, 190.0 / 255.0))

	# Câble en huit : arc extérieur de P1, croisement, arc extérieur de P2,
	# croisement — une seule polyligne fermée, tangentes lisses.
	var cable_r: float = R + 2.0 * k
	var half_d: float = (cx2 - cx1) * 0.5
	var shadow: Color = Color(5.0 / 255.0, 5.0 / 255.0, 10.0 / 255.0, 0.8)
	var core: Color = Color(215.0 / 255.0, 218.0 / 255.0, 228.0 / 255.0)
	var t_cur: float = physics.tension_dan_disp
	if t_cur >= PNConstants.T_RED_DAN:
		core = Color(1.0, 0.30, 0.20)
	elif t_cur >= PNConstants.T_WARN_DAN:
		core = Color(1.0, 0.80, 0.30)
	var pts: PackedVector2Array = PackedVector2Array()
	if half_d > cable_r * 1.01:
		var alpha: float = acos(clampf(cable_r / half_d, -1.0, 1.0))
		var n: int = 40
		for i in range(n + 1):
			var th: float = alpha + (TAU - 2.0 * alpha) * float(i) / float(n)
			pts.append(Vector2(cx1 + cable_r * cos(th), cy + cable_r * sin(th)))
		for i in range(n + 1):
			var th2: float = (PI - alpha) - (TAU - 2.0 * alpha) * float(i) / float(n)
			pts.append(Vector2(cx2 + cable_r * cos(th2), cy + cable_r * sin(th2)))
		pts.append(pts[0])
		draw_polyline(pts, shadow, 5.0 * k, true)
		draw_polyline(pts, core, 2.4 * k, true)

	# Roues par-dessus (elles couvrent l'intérieur de la boucle, seul le
	# croissant du câble sur la jante reste visible) ; P2 tourne en sens
	# inverse, comme dans un huit.
	_draw_bullwheel(cx1, cy, R, _pulley_angle, true, k)
	_draw_bullwheel(cx2, cy, R, -_pulley_angle, false, k)

	# Brins d'entrée et de sortie, verticaux vers le tunnel (sous le sol)
	for col_w in [[shadow, 5.0 * k], [core, 2.4 * k]]:
		draw_line(Vector2(cx1, floor_y + 1.0), Vector2(cx1, cy + cable_r), col_w[0], col_w[1])
		draw_line(Vector2(cx2, cy + cable_r), Vector2(cx2, floor_y + 1.0), col_w[0], col_w[1])

	# Repère qui défile sur le câble à v = ω · r_câble
	if pts.size() > 2:
		var total: float = 0.0
		for i in range(pts.size() - 1):
			total += pts[i].distance_to(pts[i + 1])
		if total > 0.0:
			var d: float = fposmod(_pulley_angle * cable_r, total)
			var acc: float = 0.0
			var mark: Vector2 = pts[0]
			for i in range(pts.size() - 1):
				var seg: float = pts[i].distance_to(pts[i + 1])
				if acc + seg >= d:
					mark = pts[i].lerp(pts[i + 1], (d - acc) / maxf(seg, 0.001))
					break
				acc += seg
			draw_circle(mark, 3.0 * k, Color(20.0 / 255.0, 20.0 / 255.0, 28.0 / 255.0))
			draw_arc(mark, 3.0 * k, 0.0, TAU, 16, Color(240.0 / 255.0, 240.0 / 255.0, 245.0 / 255.0), 0.8, true)

	# LED de puissance : vert → rouge avec la charge
	draw_circle(Vector2(rect.end.x - 12.0 * k, y0 + 12.0 * k), 3.5 * k,
		Color((100.0 + 155.0 * load) / 255.0, (220.0 - 160.0 * load) / 255.0, 80.0 / 255.0))
	draw_arc(Vector2(rect.end.x - 12.0 * k, y0 + 12.0 * k), 3.5 * k, 0.0, TAU, 16, Color(10.0 / 255.0, 10.0 / 255.0, 10.0 / 255.0), 1.0, true)


## Une poulie Von Roll jaune signal : jante avec gorge, plateau clair,
## cinq rayons qui tournent (nombre impair contre l'illusion de stroboscope),
## moyeu ; un bout d'arbre à gauche sur la motrice.
func _draw_bullwheel(cx: float, cy: float, r: float, angle: float, drive: bool, k: float) -> void:
	var c: Vector2 = Vector2(cx, cy)
	draw_circle(Vector2(cx + 1.5 * k, cy + 3.0 * k), r + k, Color(0.0, 0.0, 0.0, 0.6))
	draw_circle(c, r, Color(225.0 / 255.0, 170.0 / 255.0, 25.0 / 255.0))
	draw_arc(c, r - 0.75, 0.0, TAU, 64, Color(60.0 / 255.0, 42.0 / 255.0, 0.0), 1.5, true)
	draw_arc(c, r - 2.6 * k, 0.0, TAU, 64, Color(110.0 / 255.0, 75.0 / 255.0, 0.0), 1.3, true)
	draw_arc(c, r - 5.0 * k, 0.0, TAU, 64, Color(60.0 / 255.0, 42.0 / 255.0, 0.0), 0.8, true)
	draw_circle(c, r * 0.82, Color(255.0 / 255.0, 225.0 / 255.0, 75.0 / 255.0))
	draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.45, Color(1.0, 0.95, 0.55, 0.35))
	draw_arc(c, r * 0.82, 0.0, TAU, 64, Color(90.0 / 255.0, 60.0 / 255.0, 5.0 / 255.0), 1.0, true)
	for kk in range(5):
		var ang: float = angle + float(kk) * TAU / 5.0
		var dirv: Vector2 = Vector2(cos(ang), sin(ang))
		var p1: Vector2 = c + dirv * (r * 0.18)
		var p2: Vector2 = c + dirv * (r * 0.78)
		draw_line(p1, p2, Color(140.0 / 255.0, 95.0 / 255.0, 0.0), 4.0 * k, true)
		draw_line(p1, p2, Color(255.0 / 255.0, 220.0 / 255.0, 60.0 / 255.0), 1.5 * k, true)
		if kk == 0:
			draw_circle(p2, 2.0 * k, Color(220.0 / 255.0, 60.0 / 255.0, 40.0 / 255.0))
	draw_circle(c, r * 0.19, Color(75.0 / 255.0, 78.0 / 255.0, 92.0 / 255.0))
	draw_arc(c, r * 0.19, 0.0, TAU, 32, Color(18.0 / 255.0, 18.0 / 255.0, 22.0 / 255.0), 1.5, true)
	draw_circle(c, r * 0.08, Color(200.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0))
	if drive:
		draw_rect(Rect2(cx - r - 4.0 * k, cy - 3.0 * k, 6.0 * k, 6.0 * k), Color(160.0 / 255.0, 160.0 / 255.0, 170.0 / 255.0), true)


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
		var my: float = y + 34.0
		var mh: float = h - 40.0
		# Corps moteur (vert Von Roll)
		var motor_col: Color = Color(0.20, 0.45, 0.25)
		if (motor_degraded and i == 2) or (motor_thermal and i == 0):
			motor_col = Color(0.45, 0.20, 0.20)   # rouge si HS
		draw_rect(Rect2(Vector2(mx, my), Vector2(motor_w, mh * 0.45)), motor_col, true)
		draw_rect(Rect2(Vector2(mx, my), Vector2(motor_w, mh * 0.45)), bezel_color, false, 1.0)

		# Label (M1/M2/M3)
		_draw_text_center(Vector2(mx + motor_w * 0.5, my + 13), "M%d" % (i + 1), 11, Color(0.95, 1.0, 0.95))

		# LED état
		var led_col: Color = Color(0.20, 0.85, 0.35) if p_per_motor[i] > 0.0 else Color(0.18, 0.18, 0.20)
		if (motor_degraded and i == 2):
			led_col = Color(1.0, 0.20, 0.18)
		draw_circle(Vector2(mx + motor_w * 0.5, my + mh * 0.33), 4.0, led_col)

		# Mini bar de puissance verticale en bas
		var bar_y: float = my + mh * 0.45 + 4.0
		var bar_h: float = mh * 0.50
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


func _draw_text_right(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt)
	draw_string(font, pos - Vector2(sz.x, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)


func _draw_text_center(pos: Vector2, text: String, size_pt: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt)
	draw_string(font, pos - Vector2(sz.x * 0.5, -sz.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_pt, color)
