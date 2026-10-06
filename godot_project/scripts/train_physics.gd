class_name TrainPhysics
extends RefCounted
## Physique du train Perce-Neige — modèle contrepoids équilibré.
## Port fidèle de la classe Physics de perce_neige_sim.py (v1.9.1).
##
## Les deux trains sont liés par le câble et se déplacent symétriquement.
## La gravité nette dépend du déséquilibre de masse entre les deux.
## Le régulateur Von Roll suit un setpoint (speed_cmd 0..1) via un
## contrôleur P avec feed-forward qui compense gravité + friction.

# --- État du train (équivalent dataclass Train + GameState) --------------
var s: float = PNConstants.START_S       # distance pente depuis portail bas
# Interpolation de rendu : la physique avance par quanta de 1/60 s alors
# que le rendu tourne à 60-120 Hz → sans interpolation, le défilement du
# monde saccade (retour d'essai iPad : rails saccadés, roue HUD fluide).
# s_prev_step = s au début du dernier step ; s_render = position lissée
# recalculée chaque frame par main.gd (lerp selon l'accumulateur).
var s_prev_step: float = PNConstants.START_S
var s_render: float = PNConstants.START_S
# Position rendue de la POULIE (codeur) : s_render sans l'écart élastique
# ni l'affaissement de la rame pilotée — le contrepoids en est le miroir.
var s_poulie_render: float = PNConstants.START_S
var v: float = 0.0                       # vitesse signée (m/s)
var a: float = 0.0                       # dernière accel (m/s²)
var direction: int = 1                   # +1 montée, -1 descente

var speed_cmd: float = 0.0               # setpoint conducteur (0..1)
var speed_cmd_eff: float = 0.0           # setpoint effectif (slew-limited, m/s)
var throttle: float = 0.0                # demande moteur interne (0..1)
var brake: float = 0.0                   # frein service à FRICTION (0..1)
var regen_level: float = 0.0             # freinage de l'ENTRAÎNEMENT en
                                         # génératrice (0..1) — vrai organe
                                         # de retenue de la descente, pas le
                                         # frein de service (audit 2026-07-24)
var emergency: bool = false              # frein urgence latché
var emergency_ramp: float = 0.0          # rampe engagement (0..1)
var manual_brake_held: bool = false      # frein de service TENU par le
                                         # conducteur (bouton FREIN) — le
                                         # régulateur le respecte : couple
                                         # coupé, frein plein (ne pas tirer
                                         # contre le frein)

var doors_open: bool = true
var lights_cabin: bool = true
var lights_head: bool = false
var maint_brake: bool = true             # frein parking (drum)
var emergency_brake: bool = false        # frein urgence (panne grave)
var speed_cap_external: float = INF      # plafond vitesse imposé par panne (m/s)
var abt_hold: bool = false               # aiguillage Abt désaligné → arrêt
                                         # imposé AVANT l'évitement
var cap_over_timer: float = 0.0          # s passées > plafond de panne + 1
                                         # sans décélération franche
var pax_car1: int = 0
var pax_car2: int = 0
var ghost_pax: int = 0                   # passagers wagon opposé

# Embarquement PROGRESSIF : roll_pax() fixe des CIBLES, les effectifs réels
# glissent vers elles pendant que les portes sont ouvertes (~12 pax/s et
# par voiture — 3 portes larges). L'échange instantané faisait sauter la
# masse (et donc la jauge de tension) d'une frame à l'autre au demi-tour.
# Si le conducteur part avant la fin, l'embarquement s'arrête là (réaliste).
const BOARDING_PAX_PER_S: float = 12.0
var pax_t_car1: int = 0                  # cibles d'embarquement
var pax_t_car2: int = 0
var ghost_pax_t: int = 0
var _pax1_f: float = 0.0                 # effectifs continus internes
var _pax2_f: float = 0.0
var _ghost_f: float = 0.0

var tension_dan: float = 0.0
var tension_dan_disp: float = 0.0        # lissé pour affichage
var power_kw: float = 0.0
var power_kw_disp: float = 0.0
var regen_kw: float = 0.0
var regen_kw_disp: float = 0.0           # lissé pour affichage
var inrush_timer: float = 0.0

var trip_started: bool = false
var trip_time: float = 0.0
var finished: bool = false
var dbg_f_grav_net: float = 0.0          # dernière gravité nette (banc de parité)
var _reg_hold: bool = true               # régulateur en maintien à l'arrêt
var _pretensioned: bool = false          # couple statique posé au décollage

# --- Élasticité du câble en marche (port de Physics._elastic_step) -------
# s / v = mouvement du câble À LA POULIE MOTRICE (codeur, régulateur). Chaque
# rame pend au bout de son brin, ressort k = EA/L (L = câble déroulé jusqu'à
# la poulie, en gare haute), et s'en écarte quand la poulie accélère :
#     m·x'' = −k·x − c·x' − m·a_poulie,   c = 2ζ√(k·m),
# m = rame + 1/3 de son brin. En bas (3,4 km) T ≈ 7 à 8,7 s et 58 cm de
# retard à 0,30 m/s² ; en haut (25 m) quelques mm (audit_physique/
# elasticite_cable.sage). Retour de Kevin du 04/10 : « la rame oscille déjà
# au ralenti quand elle rentre, et quand elle part du bas elle oscille
# aussi à l'accélération ». Le rebond après l'arrêt en découle.
const CABLE_EA_N: float = 1.25e8
const REBOUND_ZETA: float = 0.15
var el_x1: float = 0.0     # écart de la rame pilotée (m, + = vers l'amont)
var el_v1: float = 0.0
var el_x2: float = 0.0     # écart du contrepoids (le long de SA voie)
var el_v2: float = 0.0

# Temporisation d'arrivée : la rame reste immobilisée portes fermées
# (rebond visible) avant l'ouverture des portes + inversion du sens.
# Critère PHYSIQUE (v1.15.21, parité PC) : les portes s'ouvrent quand
# l'enveloppe du rebond A·e^(−ζωt) passe sous SETTLE_M — Sage
# (audit_physique/stabilisation_rebond.sage) : 17 s rame vide en bas,
# 26 s pleine, 0 s en haut. Bornes : TURNAROUND_MIN_S (clip d'arrêt) et
# TURNAROUND_DELAY_S = garde-fou (ouverture forcée). Retour d'essai
# 2026-09-27 : « attendre la fin des oscillations avant d'ouvrir ».
const TURNAROUND_DELAY_S: float = 30.0
const TURNAROUND_MIN_S: float = 3.0
const SETTLE_M: float = 0.02
var turnaround_delay_remaining: float = 0.0

# --- Affaissement d'embarquement (allongement élastique du brin) ---------
# À quai, tambour serré en gare haute, la rame pend à son brin : chaque
# passager qui monte allonge le câble de δ = Δm·g·sinθ·L/(EA). En gare
# BASSE (L ≈ 3,45 km) : ~1,6 mm/passager → jusqu'à ~37 cm pour une pleine
# charge, la rame « descend doucement » pendant l'embarquement. En gare
# haute (L ≈ 17 m) : invisible. Pendant le buzzer de départ,
# l'entraînement pré-tensionne et remonte la rame au repère (réel).
# Purement VISUEL : appliqué à s_render, le s physique est tenu au clamp.
const SAG_RETENSION_M_S: float = 0.08    # vitesse de rattrapage au buzzer
var _sag_ref_m_main: float = -1.0        # masse à l'ancrage (−1 = pas ancré)
var _sag_ref_m_ghost: float = -1.0
var _sag_main: float = 0.0               # affaissement courant (m, ≥ 0 vers le bas)
var _sag_ghost: float = 0.0

# --- Mode DÉFI (chaos) + collisions --------------------------------------
# Port du mode "challenge" du sim PC : tous les filets de sécurité
# automatiques tombent (enveloppe d'approche, creep, auto-dock, cap de
# confort, écrêtage à V_MAX, verrou de portes, chaînes de sécurité). Le
# moteur est surrégimé (×1,8) → consigne à fond = survitesse même en
# montée chargée, jusqu'à la cascade destructrice. À plus de 1,5 m/s au
# butoir : COLLISION. À plus de 13,5 m/s dans l'évitement : DÉRAILLEMENT.
signal crash_occurred(kind: String, speed: float)


# --- Audit physique 2026-09-26 : câble, galets, traînée en tunnel ----------
# Mêmes formules que perce_neige_sim.py (air_density_at, _aero_coefficients,
# aero_drag_side_n, rope_weight_force_n, ROPE_ROLLERS_N).
static var _aero_c_single: float = -1.0
static var _aero_c_loop: float = 0.0
static var _rope_rollers_n: float = -1.0


static func air_density_at(alt_m: float) -> float:
	return 1013e2 * exp(-PNConstants.G * alt_m / (287.05 * 278.0)) / (287.05 * 278.0)


static func _aero_init() -> void:
	var r_t: float = PNConstants.TUNNEL_DIAM_M / 2.0
	var h: float = PNConstants.AERO_BED_H_M
	var a_circ: float = PI * r_t * r_t
	var a_bed: float = r_t * r_t * acos((r_t - h) / r_t) \
		- (r_t - h) * sqrt(2.0 * r_t * h - h * h)
	var a_t: float = a_circ - a_bed
	var beta: float = PNConstants.AERO_BLOCKAGE
	var a_train: float = beta * a_t
	var a_ann: float = a_t - a_train
	var p_t: float = 2.0 * PI * r_t
	var p_train: float = 2.0 * PI * sqrt(a_train / PI)
	var d_h: float = 4.0 * a_ann / (p_t + p_train)
	var k_fric: float = PNConstants.AERO_LAMBDA * PNConstants.TRAIN_LEN / d_h
	var k: float = PNConstants.AERO_K_IN + k_fric + beta * beta
	var ratio: float = (2.0 - beta) / (1.0 - beta)
	_aero_c_single = 0.5 * ratio * ratio * (k * a_train + 0.5 * k_fric * a_ann)
	var k2: float = 1.5 + PNConstants.AERO_LAMBDA * PNConstants.AERO_LOOP_LEN_M \
		/ (4.0 * a_t / p_t)
	var lo: float = 0.0
	var hi: float = 1.0
	for _i in range(60):
		var mid: float = 0.5 * (lo + hi)
		var dp_a: float = k * pow(1.0 + mid * a_t / a_ann, 2.0)
		var dp_t: float = k2 * pow(1.0 - mid, 2.0)
		if dp_a > dp_t:
			hi = mid
		else:
			lo = mid
	var frac: float = 0.5 * (lo + hi)
	_aero_c_loop = 0.5 * k * pow(1.0 + frac * a_t / a_ann, 2.0) * a_train


static func aero_drag_side_n(s_pos: float, v_: float) -> float:
	if _aero_c_single < 0.0:
		_aero_init()
	var in_loop: bool = s_pos >= PNConstants.PASSING_START \
		and s_pos <= PNConstants.PASSING_END
	var c: float = _aero_c_loop if in_loop else _aero_c_single
	return c * air_density_at(SlopeProfile.altitude_at(s_pos)) * v_ * v_


static func aero_drag_n(s_pos: float, v_: float) -> float:
	return aero_drag_side_n(s_pos, v_) \
		+ aero_drag_side_n(PNConstants.miroir(s_pos), v_)


static func rope_weight_force_n(s_pos: float) -> float:
	return PNConstants.CABLE_KG_M * PNConstants.G \
		* (SlopeProfile.altitude_at(s_pos)
			- SlopeProfile.altitude_at(PNConstants.miroir(s_pos)))


static func rope_rollers_n() -> float:
	if _rope_rollers_n < 0.0:
		var acc: float = 0.0
		var n: int = 0
		var x: float = 0.0
		while x < PNConstants.LENGTH:
			acc += cos(atan(SlopeProfile.gradient_phys_at(x)))
			n += 1
			x += 10.0
		_rope_rollers_n = PNConstants.CABLE_ROLLER_C * PNConstants.CABLE_KG_M \
			* PNConstants.LENGTH * PNConstants.G * (acc / float(n))
	return _rope_rollers_n

const CHALLENGE_V_CMD_MAX: float = 15.0   # plage de consigne en Défi (m/s)
const CHAOS_MOTOR_OVERDRIVE: float = 1.8  # surrégime moteur autorisé
const CRASH_SPEED: float = 1.5            # m/s au-delà desquels ça percute
const SWITCH_DERAIL_V: float = 13.5       # survitesse déraillante à l'Abt
const CHALLENGE_ARR_WIN: float = 6.0      # fenêtre d'arrivée sans auto-dock

var challenge_mode: bool = false
var frozen: bool = false                  # physique figée (écran de crash)
var jerk_sum: float = 0.0                 # pénalité de confort intégrée
var crashed: bool = false
var crash_kind: String = ""
var crash_speed_ms: float = 0.0
var cable_rupture: bool = false           # câble rompu : plus de contrepoids
var service_brake_fail: float = 1.0       # efficacité frein service (0..1)
var overspeed_level: int = 0              # 0 = nominal, 1 = survitesse, 3 = rupture
var ghost_locked_s: float = -1.0          # position figée de la rame 2 (< 0 = libre)


# --- Accesseurs -----------------------------------------------------------

## Position de la rame 2 pour le rendu. Normalement symétrique (LENGTH − s) ;
## une fois le câble rompu, la rame 2 découplée a freiné et s'est
## immobilisée : sa position est figée (c'est ELLE que la rame emballée
## percute, pas un point théorique).
## Vitesse de la RAME 1 le long de la ligne (m/s, + = vers la gare haute),
## qui fixe le sens de rotation des roues motrices : son brin entre sur la
## roue aval quand elle monte. `v` est signé le long de s (s += v·dt) ; la
## rame pilotée est la rame 1 sauf si `rame2` (la rame 1 est alors en face,
## à LENGTH − s, et va en sens inverse). Retour du 30/09 : les roues
## tournaient avec v·direction, toujours positif en marche — faux en
## descente et en rame 2.
func v_rame1(rame2: bool) -> float:
	return -v if rame2 else v


## Vitesse du câble à la poulie motrice, même convention que v_rame1 :
## c'est elle qui fait tourner les roues de la salle des machines, le
## panneau du HUD et le son de la machinerie. Câble intact : elle suit la
## rame. Câble rompu : plus rien ne la lie aux rames — la chaîne de
## sécurité déclenche et les freins arrêtent la machinerie (A_DRIVE_TRIP)
## au lieu de la laisser suivre la rame qui dévale (retour du 01/10).
## Appelée à chaque image par main.gd (aussi en mode client, où step()
## ne tourne pas).
var machine_v: float = 0.0


func update_machine(rame2: bool, dt: float) -> void:
	if cable_rupture:
		machine_v = move_toward(machine_v, 0.0, PNConstants.A_DRIVE_TRIP * dt)
	else:
		machine_v = v_rame1(rame2)


func ghost_s_render() -> float:
	if ghost_locked_s >= 0.0:
		return ghost_locked_s
	# miroir de la POULIE (pas de la rame pilotée, qui oscille), plus son
	# propre écart élastique
	return PNConstants.miroir(s_poulie_render) + el_x2


func ghost_s_phys() -> float:
	if ghost_locked_s >= 0.0:
		return ghost_locked_s
	return PNConstants.miroir(s)


func pax() -> int:
	return pax_car1 + pax_car2


func mass_kg() -> float:
	return PNConstants.TRAIN_EMPTY_KG + pax() * PNConstants.PAX_KG


func ghost_mass_kg() -> float:
	return PNConstants.TRAIN_EMPTY_KG + ghost_pax * PNConstants.PAX_KG


# --- Step principal -------------------------------------------------------

func step(dt: float) -> void:
	# Physique figée après une collision (écran de game-over du mode Défi) :
	# plus rien ne bouge tant que le conducteur n'a pas relancé un voyage.
	if frozen:
		return
	# Clamp dt pour éviter de casser la physique sur un gros hiccup
	dt = clampf(dt, 0.001, 0.1)
	s_prev_step = s
	var v_entree: float = v      # accélération de la poulie (élasticité)

	# Rotation passagers progressive tant que les portes sont ouvertes
	# (le wagon opposé embarque en même temps dans SA gare). Portes
	# fermées : resynchro des effectifs continus sur les entiers
	# (affectations directes des bancs de test, mode client…).
	if doors_open:
		_pax1_f = move_toward(_pax1_f, float(pax_t_car1), BOARDING_PAX_PER_S * dt)
		_pax2_f = move_toward(_pax2_f, float(pax_t_car2), BOARDING_PAX_PER_S * dt)
		_ghost_f = move_toward(_ghost_f, float(ghost_pax_t), BOARDING_PAX_PER_S * dt)
		pax_car1 = int(roundf(_pax1_f))
		pax_car2 = int(roundf(_pax2_f))
		ghost_pax = int(roundf(_ghost_f))
		# Arrivée : tout le monde descend d'abord (cibles à 0), PUIS la
		# nouvelle charge monte (retour du 06/10/2026 : « aller jusqu'à
		# l'ouverture des portes et le débarquement des passagers »).
		# (pas avant le demi-tour : roll_pax tire la charge du trajet RETOUR)
		if _embarquement_apres_descente and pax_car1 == 0 and pax_car2 == 0 \
				and ghost_pax == 0 and turnaround_delay_remaining <= 0.0:
			_embarquement_apres_descente = false
			roll_pax()
	else:
		_pax1_f = float(pax_car1)
		_pax2_f = float(pax_car2)
		_ghost_f = float(ghost_pax)
		# portes refermées avant la fin de la descente : ceux qui
		# restent font le trajet
		_embarquement_apres_descente = false

	# Séquence de départ en TROIS phases successives (retour d'essai iPad
	# 2026-07-12 : annonce, portes et buzzer se superposaient) :
	# annonce « fermeture des portes » (7,5 s, portes encore ouvertes) →
	# fermeture des portes (buzzer 7 s PUIS clip 7 s, vantaux à 1,3 s du
	# clip — retour d'essai 2026-09-27) → buzzer 6-8 s → traction.
	if announce_phase_remaining > 0.0:
		announce_phase_remaining = maxf(0.0, announce_phase_remaining - dt)
		if announce_phase_remaining <= 0.0:
			doors_open = false
			door_phase_remaining = DOOR_PHASE_S
	elif door_phase_remaining > 0.0:
		door_phase_remaining = maxf(0.0, door_phase_remaining - dt)
		if door_phase_remaining <= 0.0:
			if _fermeture_seule:
				# fermeture commandée au bouton PORTES : la rame reste à
				# quai, portes fermées, jusqu'au PRÊT/DÉPART
				_fermeture_seule = false
			else:
				departure_buzzer_remaining = \
					8.0 if s < PNConstants.LENGTH * 0.5 else 6.0
	elif departure_buzzer_remaining > 0.0:
		departure_buzzer_remaining = maxf(0.0, departure_buzzer_remaining - dt)
		if departure_buzzer_remaining <= 0.0:
			start_trip()

	# Vantaux (visuel) : à l'ouverture, le clip joue tout de suite et les
	# vantaux partent à DOOR_MOTION_LEAD ; à la fermeture, le clip ne
	# commence qu'après le buzzer, donc les vantaux partent à
	# DOOR_BUZZER_S + DOOR_MOTION_LEAD du début de la phase portes.
	if doors_open and not _doors_open_prev:
		door_leaves_timer = PNConstants.DOOR_MOTION_LEAD
	_doors_open_prev = doors_open
	if doors_open:
		if not door_leaves_open:
			door_leaves_timer -= dt
			if door_leaves_timer <= 0.0:
				door_leaves_open = true
	elif door_phase_remaining > 0.0:
		if door_phase_remaining <= DOOR_PHASE_S - PNConstants.DOOR_BUZZER_S - PNConstants.DOOR_MOTION_LEAD:
			door_leaves_open = false
	else:
		door_leaves_open = false

	var m_up: float = mass_kg()
	var m_down: float = ghost_mass_kg()
	# Le câble (38 t) fait partie de la masse en mouvement (audit 2026-09-26).
	var m_total: float = m_up + m_down + PNConstants.ROPE_MASS_KG

	# Pente LOCALE de chaque rame (port du sim Python) : le profil n'est
	# pas symétrique (8 % au départ, 30 % au milieu, 6 % en haut), donc la
	# rame principale à s et le contrepoids à (L − s) sont rarement sur la
	# même pente — l'équilibre du câble dépend des DEUX sinus. L'ancien
	# port utilisait la pente de la rame pilotée pour les deux.
	var g_slope: float = SlopeProfile.gradient_phys_at(s)
	var theta: float = atan(g_slope)
	var sint: float = sin(theta)
	var cost: float = cos(theta)
	var theta_g: float = atan(SlopeProfile.gradient_phys_at(PNConstants.miroir(s)))
	var sint_g: float = sin(theta_g)
	var cost_g: float = cos(theta_g)

	# Affaissement d'embarquement : suit la masse tant que la rame est
	# ancrée (tambour/portes), Y COMPRIS pendant la séquence de départ —
	# l'allongement élastique PERSISTE tant que la charge est là, la rame
	# ne « remonte » pas au repère avant de partir (retour d'essai
	# 2026-07-13 : elle remontait au PRÊT/DÉPART, faux). Une fois en
	# marche, l'écart se fond dans le trajet (résorption lente,
	# imperceptible pendant que le paysage défile).
	if not trip_started and (maint_brake or doors_open):
		if _sag_ref_m_main < 0.0:
			_sag_ref_m_main = m_up
			_sag_ref_m_ghost = m_down
		var sag_t_main: float = maxf(0.0,
			(m_up - _sag_ref_m_main) * PNConstants.G * sint
			* (PNConstants.LENGTH - s) / CABLE_EA_N)
		var sag_t_ghost: float = maxf(0.0,
			(m_down - _sag_ref_m_ghost) * PNConstants.G * sint_g
			* (PNConstants.LENGTH - PNConstants.miroir(s)) / CABLE_EA_N)
		# Suit le flux d'embarquement (≈ 2 cm/s max — « doucement »)
		_sag_main = move_toward(_sag_main, sag_t_main, 0.03 * dt)
		_sag_ghost = move_toward(_sag_ghost, sag_t_ghost, 0.03 * dt)
	elif trip_started:
		_sag_ref_m_main = -1.0
		_sag_ref_m_ghost = -1.0
		# Résorption uniquement EN MARCHE (5 cm/s, invisible à 12 m/s) —
		# à l'arrêt traction collée mais immobile, l'affaissement tient.
		if absf(v) > 0.3:
			_sag_main = move_toward(_sag_main, 0.0, SAG_RETENSION_M_S * dt)
			_sag_ghost = move_toward(_sag_ghost, 0.0, SAG_RETENSION_M_S * dt)

	# AUDIT 2026-07-23 (port du PC v1.12.21) : le plafond DE PANNE ne
	# passe plus par v_limit (fondu moteur + bleed) — il est l'affaire du
	# régulateur (rampe 0,60 + feed-forward) et de la surveillance
	# cap_over_timer. v_limit = V_MAX machine uniquement.
	var v_limit: float = PNConstants.V_MAX

	# --- Régulateur (met à jour throttle et brake) ------------------------
	_regulator(dt, m_up, m_down, m_total, g_slope, theta)

	# --- Force moteur -----------------------------------------------------
	var v_eff: float = maxf(absf(v), 0.8)
	var p_eff: float = PNConstants.P_MAX

	# Inrush DC au démarrage (~4.5× nominal pendant 1.2 s)
	if absf(v) < 0.2 and throttle > 0.2 and inrush_timer <= 0.0:
		inrush_timer = 1.2
	if inrush_timer > 0.0:
		inrush_timer = maxf(0.0, inrush_timer - dt)
		var boost: float = 1.0 + 3.5 * (inrush_timer / 1.2)
		p_eff *= boost

	var f_motor_power_cap: float = p_eff / v_eff
	# CHAOS (mode Défi) : plus de bridage électronique — le conducteur
	# surrégime le moteur, la consigne pleine dépasse V_MAX MÊME en montée
	# chargée, jusqu'à la cascade de survitesse (+20 % → câble rompu).
	if challenge_mode:
		f_motor_power_cap *= CHAOS_MOTOR_OVERDRIVE
	var f_motor_max: float = minf(PNConstants.F_STALL, f_motor_power_cap)
	var f_motor: float = throttle * f_motor_max * float(direction)
	# Force de FREINAGE PAR L'ENTRAÎNEMENT (génératrice) : oppose la
	# marche, même enveloppe que la traction. Retient la descente
	# chargée (frein de service à ~0 %). Coupée si le chemin de force
	# est ouvert (drive_off) ou en urgence — voir plus bas.
	var f_regen: float = -regen_level * f_motor_max * float(direction)

	# Ne pas pomper de puissance à la limite — FONDU sur 0,25 m/s au-delà
	# de v_limit au lieu de la coupure sèche : l'ancien tout-ou-rien
	# hachait la force moteur à 60 Hz dès que v effleurait la limite
	# (flagrant sous plafond de panne : 910 sauts > 100 kW/frame mesurés
	# au banc) → à-coups de puissance sur la jauge et la tension.
	# En mode Défi, ce fondu est LEVÉ : c'est lui qui écrêtait la vitesse à
	# ~12,25 m/s consigne à fond. Sans lui, la rame s'emballe réellement.
	if f_motor * direction > 0.0 and not challenge_mode:
		f_motor *= clampf((v_limit + 0.25 - v * float(direction)) / 0.25, 0.0, 1.0)

	# Interlock portes : pas de traction si portes ouvertes. EXCEPTION mode
	# DÉFI une fois le voyage lancé : départ sauvage portes ouvertes
	# autorisé (ça se paiera au sous-score de régularité, et les passagers
	# le racontent dans leur avis).
	if doors_open and not (challenge_mode and trip_started):
		f_motor = 0.0

	# FREIN ENGAGÉ → COUPER LA TRACTION (tous les cas). Le moteur ne doit
	# JAMAIS tirer contre un frein serré : sinon il annule le freinage et
	# la décélération devient ridicule (retour d'essai 2026-07-23 : « dans
	# tous les modes il faut couper la puissance quand le frein est
	# déclenché »). Le frein de service manuel (bouton FREIN maintenu) ne
	# remet PAS la consigne à 0 → sans cette coupure, le régulateur
	# continuait de commander du couple pendant que le conducteur freinait.
	if emergency or emergency_ramp > 0.0 or manual_brake_held or brake > 0.05:
		f_motor = 0.0

	# --- Gravité (déséquilibre cable) ------------------------------------
	# Chaque rame avec SA pente locale (comme le sim Python) :
	#   f_grav_s = −(m_main·sinθ_main − m_ghost·sinθ_ghost)·g
	var f_grav_net: float = -(m_up * sint - m_down * sint_g) * PNConstants.G
	# Poids propre du câble (audit 2026-09-26) : ρ·g·(z_rame − z_contrepoids),
	# −99 kN au départ bas, +99 kN à l'arrivée haut, nul à mi-ligne. Il
	# était dans la jauge de tension mais pas dans la dynamique.
	f_grav_net += rope_weight_force_n(s)
	dbg_f_grav_net = f_grav_net   # exposé pour le banc de parité PC↔3D

	# CÂBLE ROMPU : la rame est découplée du contrepoids. Plus d'équilibre
	# — seule SA masse et SA pente comptent, et il n'y a plus rien pour la
	# retenir que le parachute Belleville sur rail. C'est l'emballement.
	var m_eff: float = m_total
	if cable_rupture:
		f_grav_net = -m_up * sint * PNConstants.G
		m_eff = m_up

	# --- Friction roulement (les 2 rames, chacune sur sa pente) -----------
	var f_roll_mag: float = PNConstants.MU_ROLL * PNConstants.G \
		* (m_up * cost + m_down * cost_g if not cable_rupture else m_up * cost) \
		+ (0.0 if cable_rupture else rope_rollers_n())
	var f_roll: float = 0.0
	if absf(v) > 0.05:
		f_roll = -signf(v) * f_roll_mag
	# Traînée d'air en tunnel (les DEUX rames, chacune dans son régime
	# tube unique / évitement) — audit 2026-09-26.
	var f_aero_mag: float = aero_drag_side_n(s, v) if cable_rupture \
		else aero_drag_n(s, v)
	var f_aero: float = 0.0
	if absf(v) > 0.05:
		f_aero = -signf(v) * f_aero_mag

	# --- Freins ----------------------------------------------------------
	if emergency:
		emergency_ramp = minf(1.0, emergency_ramp + PNConstants.A_BRAKE_EMERG_RAMP * dt)
	else:
		emergency_ramp = maxf(0.0, emergency_ramp - PNConstants.A_BRAKE_EMERG_RAMP * dt)

	var a_brk: float = 0.0
	if emergency_ramp > 0.0:
		# Câble rompu : le frein poulie n'a plus de chemin de force — seules
		# les pinces Belleville sur rail agissent (parachute, 3,6 m/s²),
		# et la gravité les combat en pente : l'arrêt est long.
		var a_full: float = 3.6 if cable_rupture else PNConstants.A_BRAKE_EMERGENCY
		a_brk = emergency_ramp * a_full
	elif brake > 0.0:
		# Le frein de service peut tomber à 15-25 % de son efficacité quand
		# le circuit hydraulique perd sa pression (pattern Glória 2025) —
		# service_brake_fail vaut 1,0 tant que tout va bien.
		a_brk = brake * PNConstants.A_BRAKE_NORMAL * service_brake_fail

	var f_brake: float = 0.0
	if absf(v) > 0.05:
		f_brake = -signf(v) * a_brk * m_eff
	# Urgence et parachute = freins de VOIE : chaque rame serre sur ses
	# rails, le câble ne transmet pas cet effort → il ne fait pas osciller
	# les rames (retour du 04/10, parité PC).
	var a_frein_voie: float = f_brake / m_eff if emergency_ramp > 0.0 else 0.0

	# Le freinage par l'entraînement partage le chemin de force du moteur :
	# coupé dès que celui-ci l'est (portes, hors trip, câble rompu) ou en
	# urgence (le frein de sécurité prend le relais).
	# (les pannes « stoppantes »/catastrophiques du 3D passent par
	# emergency → f_regen coupé ci-dessous, pas besoin d'un flag câble.)
	# En DÉFI, rouler portes ouvertes ne coupe PLUS l'entraînement (la
	# traction passe déjà) : sinon la RETENUE régénérative disparaissait et
	# réduire la consigne ne freinait plus rien. Symétrie traction/retenue.
	# Câble rompu : plus de chemin de force du tout.
	var chaos_doors_ok: bool = challenge_mode and trip_started
	var drive_off: bool = (doors_open and not chaos_doors_ok) \
		or not trip_started or cable_rupture
	if drive_off or emergency or emergency_ramp > 0.0:
		f_regen = 0.0
	if cable_rupture:
		f_motor = 0.0

	# Somme et intégration
	var net: float = f_motor + f_regen + f_grav_net + f_roll + f_aero + f_brake
	var acc: float = net / m_eff

	# Cap accel moteur (confort) — soft-start progressive. Retenue
	# délibérée = frein de service OU régén : sans inclure regen_level,
	# le cap bridait la décélération commandée (arrêt de service mou),
	# la retenue passant désormais par la régén (audit 2026-07-24).
	var braking_cmd: bool = brake >= 0.05 or regen_level >= 0.05
	if not emergency:
		var v_abs: float = absf(v)
		# Démarrage doux (creep de quai, calibré vidéo) SEULEMENT près d'un
		# terminus : en pleine voie, un redémarrage prend la rampe programmée
		# dès le décollage (2026-09-26 : « la puissance monte très
		# progressivement en pleine pente »).
		var pres_quai: bool = s < PNConstants.START_S + PNConstants.PLATFORM_LEN + 20.0 \
			or s > PNConstants.STOP_S - PNConstants.PLATFORM_LEN - 20.0
		var soft_cap: float = PNConstants.A_MAX_REG
		if pres_quai:
			soft_cap = PNConstants.A_START + \
				(PNConstants.A_MAX_REG - PNConstants.A_START) * \
				minf(1.0, v_abs / PNConstants.V_SOFT_RAMP)
		# Mode DÉFI : le cap de confort au lancement est LEVÉ — moteur à
		# fond, la rame peut réellement s'emballer.
		if acc > soft_cap and not challenge_mode:
			acc = soft_cap
		elif acc < -soft_cap and not braking_cmd and not challenge_mode:
			acc = -soft_cap

	# Kill creep final — UNIQUEMENT quand l'arrêt est voulu (régulateur en
	# maintien, urgence, ou gros frein manuel). L'ancien « tout frein +
	# quasi-arrêt → v=0 » gelait DÉFINITIVEMENT les départs à gravité
	# excédentaire : contrepoids chargé qui tire la rame vide vers le
	# haut → le régulateur en force module au FREIN (la rampe 0,30 <
	# accélération naturelle) → kill à chaque frame → « elle n'a jamais
	# voulu repartir » (retour d'essai 2026-07-13, inversion en descente).
	if a_brk > 0.0 and absf(v) < 0.03 \
			and (_reg_hold or emergency or brake > 0.5):
		v = 0.0
		acc = 0.0
	# Câble rompu : plus de tambour pour prendre le relais à l'arrêt, c'est
	# le parachute qui tient la rame — frein à friction = tenue STATIQUE dès
	# que sa force dépasse la charge (3,6 m/s² contre g·sinθ ≤ 2,8 m/s²).
	# Sans ça la zone morte de f_brake (|v| ≤ 5 cm/s) la laissait glisser
	# (parité PC 2026-09-28).
	elif cable_rupture and emergency_ramp > 0.0 and absf(v) < 0.1 \
			and a_brk * m_eff >= absf(net - f_brake):
		v = 0.0
		acc = 0.0

	# Auto-park (chaîne de sécurité Von Roll, comme le PC) : train
	# immobilisé sous frein d'urgence → le tambour se réengage seul pour
	# qu'il ne reparte pas sur la pente. (Relâché avec l'urgence par
	# release_emergency si le voyage est en cours — reprise en tunnel.)
	if emergency and absf(v) < 0.05 and not maint_brake:
		maint_brake = true
	# Ceinture + bretelles (verrou v1.12.6 du PC) : rame immobile HORS
	# séquence de voyage et hors urgence → tambour réengagé (le drum ne se
	# lève qu'au collage du contacteur, fin de buzzer).
	if not trip_started and not emergency and absf(v) < 0.05 and not maint_brake:
		maint_brake = true

	# Intégration
	var new_v: float = v + acc * dt
	# Bleed-off survitesse (régénératif) — les DEUX sens, comme le PC.
	# Seuil 1 000 N (et plus f_motor == 0.0 exact) : avec le fondu moteur
	# à la limite, f_motor traîne près de zéro sans jamais y être.
	# CHAOS (mode Défi) : ce bleed régénératif EST le plafond invisible qui
	# écrêtait la vitesse à V_MAX. Levé, la rame s'emballe pour de bon —
	# c'est au conducteur de freiner. Câble rompu : plus de chemin de force
	# pour le drive, donc plus de bleed non plus.
	var drive_path_ok: bool = not challenge_mode and not cable_rupture
	if new_v * direction > v_limit and f_motor * float(direction) <= 1000.0 \
			and drive_path_ok:
		var excess: float = new_v * direction - v_limit
		var bleed: float = minf(excess, 1.5 * dt)
		new_v -= bleed * float(direction)
	if new_v * direction < -v_limit and drive_path_ok:
		var excess_r: float = -v_limit - new_v * direction
		var bleed_r: float = minf(excess_r, 1.5 * dt)
		new_v += bleed_r * float(direction)

	s += ((v + new_v) / 2.0) * dt
	v = new_v

	# Clamp position. L'accélération ±2,0 posée ici est SYNTHÉTIQUE
	# (amortisseur numérique du butoir) : le flag l'exclut de l'inertie
	# de tension — c'est le butoir/rail qui absorbe, pas le câble. Sans
	# ça, la masse du brin (38 t) × 2 m/s² ajoutait ~18 000 daN fantômes
	# à la jauge au contact du point d'arrêt.
	var buffer_clamp: bool = false
	var clamp_lo: float = PNConstants.START_S
	var clamp_hi: float = PNConstants.STOP_S
	# En Défi, la rame qui ARRIVE TROP VITE doit rouler jusqu'au VRAI butoir
	# (nez ou arrière contre sa tête) avant de percuter — sinon le crash se
	# déclenche avant le mur et la visu ne montre rien.
	if challenge_mode and not finished:
		clamp_hi = PNConstants.STOP_S + PNConstants.JEU_BUTOIR_HAUT
		clamp_lo = PNConstants.START_S - PNConstants.JEU_BUTOIR_BAS
	_check_crash(clamp_lo, clamp_hi)
	if crashed:
		v = 0.0
		acc = 0.0
		buffer_clamp = true
		if crash_kind == "buffer":
			s = clampf(s, clamp_lo, clamp_hi)
	if s >= clamp_hi:
		s = clamp_hi
		if v > 0.0:
			v = maxf(0.0, v - 2.0 * dt)
			acc = -2.0
			buffer_clamp = true
	elif s <= clamp_lo:
		s = clamp_lo
		if v < 0.0:
			v = minf(0.0, v + 2.0 * dt)
			acc = 2.0
			buffer_clamp = true

	# Détection d'arrivée SERRÉE (port du PC v1.12.3) : le serrage du
	# tambour n'a lieu que quand le docking s'est achevé NATURELLEMENT
	# (|v| < 0,08 m/s ET à moins de 8 cm du point d'arrêt). L'ancien port
	# serrait au CONTACT du clamp, vitesse résiduelle comprise → les
	# ~0,25 m/s restants coupés en une frame = « l'arrêt en gare
	# supérieure est instantané » (retour d'essai 2026-07-13). Le clamp
	# ci-dessus reste un simple amortisseur de butoir (2 m/s²).
	# En DÉFI, plus de creep d'auto-alignement : le conducteur s'arrête où
	# il peut. La fenêtre d'arrivée est donc large (6 m) — sans ça, une
	# rame arrêtée à 1 m du repère ne « finissait » jamais son trajet et
	# n'était jamais notée. C'est le sous-score de précision qui reflète
	# l'écart exact.
	var arr_win: float = CHALLENGE_ARR_WIN if challenge_mode else 0.08
	var arr_v: float = 0.10 if challenge_mode else 0.08
	if not finished and trip_started and not crashed and absf(v) < arr_v:
		if direction > 0 and s >= PNConstants.STOP_S - arr_win:
			finished = true
			_arrival_grab()
		elif direction < 0 and s <= PNConstants.START_S + arr_win:
			finished = true
			_arrival_grab()

	# Temporisation d'arrivée → demi-tour (portes + inversion)
	if turnaround_delay_remaining > 0.0:
		turnaround_delay_remaining = maxf(0.0, turnaround_delay_remaining - dt)
		var elapsed: float = TURNAROUND_DELAY_S - turnaround_delay_remaining
		if elapsed >= TURNAROUND_MIN_S and rebound_envelope() < SETTLE_M:
			turnaround_delay_remaining = 0.0   # câble stabilisé : on ouvre
		if turnaround_delay_remaining <= 0.0:
			_terminus_turnaround()

	# Frein parking (drum) ou frein urgence (panne grave). Serrage
	# PROGRESSIF du résiduel (≤ 8 cm/s au moment du grab d'arrivée) :
	# v décroît à 1,2 m/s² au lieu d'être coupée en une frame — dernier
	# à-coup de l'arrêt en gare (retour d'essai 2026-07-13). La gravité
	# (≤ 0,7 m/s² intégrée juste avant) ne peut pas vaincre la rampe :
	# le tambour tient rigoureusement v = 0 une fois posé.
	# (portes ouvertes : en Défi, une fois le voyage lancé, elles ne
	# clouent plus la rame au sol — le départ sauvage est autorisé.)
	# CÂBLE ROMPU : le tambour serre la poulie motrice en gare haute, il n'a
	# plus aucun lien avec la rame — seuls ses freins embarqués (parachute,
	# frein de service dégradé) la tiennent. Sinon une rame dont on relâche
	# l'urgence restait clouée au lieu de redescendre (parité PC 2026-09-28).
	if ((maint_brake or (doors_open and not chaos_doors_ok)) and not cable_rupture) \
			or emergency_brake:
		v = move_toward(v, 0.0, 1.2 * dt)
		acc = 0.0
		# la position suit la vitesse RETENUE par le tambour (intégrée
		# avant lui, elle glissait de ~1 mm/s sous la pente, poulie serrée)
		if not buffer_clamp:
			s = s_prev_step + 0.5 * (v_entree + v) * dt

	# --- Confort passager (ISO 2631) — sert au score du mode Défi --------
	# Pénalité quadratique sur l'EXCÈS d'accélération au-delà du confort
	# debout (0,9 m/s²) + pénalité de jerk + forfait quand un arrêt
	# d'urgence est engagé à vitesse notable (les passagers non préparés
	# sont projetés). Port du modèle réactif du PC (audit 2026-07-24).
	var jerk: float = absf(acc - a) / maxf(dt, 1e-3)
	var a_excess: float = maxf(0.0, absf(acc) - 0.9)
	var pen: float = a_excess * a_excess * 4.0 + maxf(0.0, jerk - 0.8) * 0.05
	if emergency and absf(v) > 1.0:
		pen += 8.0
	jerk_sum += pen * dt

	a = acc

	# --- Cascade de survitesse (mode Défi : aucun filet automatique) -----
	# +10 % V_MAX : alarme seule. +20 % : le contrôle de survitesse du
	# moteur lâche, le CÂBLE CASSE — la rame est découplée du contrepoids
	# et le frein de service tombe à 15 %. Seule l'urgence (parachute)
	# peut encore l'arrêter avant le butoir.
	if challenge_mode and not cable_rupture:
		var v_abs2: float = absf(v)
		if v_abs2 > 1.20 * PNConstants.V_MAX:
			overspeed_level = 3
			cable_rupture = true
			service_brake_fail = 0.15
			ghost_locked_s = PNConstants.miroir(s)   # la rame 2 s'immobilise
			speed_cmd = 0.0
			throttle = 0.0
			print("[Chaos] SURVITESSE +20 % — moteur détruit, câble rompu")
		elif v_abs2 > 1.10 * PNConstants.V_MAX and overspeed_level < 1:
			overspeed_level = 1
			print("[Chaos] SURVITESSE — aucun filet en Défi, freinez")

	# Surveillance du plafond de panne (port du PC v1.12.21) : la rampe
	# du régulateur (0,60 m/s²) doit ramener v sous le cap ; si v reste
	# au-dessus de cap + 1 m/s plus de 12 s SANS décélération franche
	# (adhérence perdue, frein insuffisant…), l'urgence tombe toute
	# seule — la surveillance réelle ne laisse jamais rouler un défaut.
	if not emergency and trip_started and speed_cap_external < PNConstants.V_MAX:
		var decel_along: float = -acc * (1.0 if v > 0.0 else -1.0)
		if absf(v) > speed_cap_external + 1.0 and decel_along < 0.25:
			cap_over_timer += dt
			if cap_over_timer > 12.0:
				emergency = true
				print("[Physics] plafond de panne dépassé trop longtemps — urgence auto")
		else:
			cap_over_timer = 0.0
	else:
		cap_over_timer = 0.0

	# --- Tension câble : modèle DEUX BRINS, max à la poulie ----------------
	# Chaque brin, au niveau de la poulie motrice (gare haute), porte :
	#   - le poids de SA rame le long de SA pente locale,
	#   - le poids PROPRE du brin : ρ·g·Δaltitude jusqu'à la rame (exact
	#     quel que soit le profil : ∫ρg·sinθ·ds = ρg·Δh) — ~9 900 daN pour
	#     une rame en bas de ligne, ~0 en haut,
	#   - le frottement de roulement de SA rame,
	#   - l'inertie (rame + brin) SIGNÉE par SON accélération le long de
	#     SA pente (T = m·g·sinθ + m·a_s : une rame qui dévale DÉCHARGE
	#     son brin).
	# La jauge affiche le brin le plus chargé — presque toujours celui de
	# la rame BASSE (3,4 km de câble pendu). L'ancien modèle « brin de la
	# rame lourde » montrait ~3 000 daN à l'arrivée en haut à pleine
	# charge alors que le brin de la rame vide EN BAS portait ~12 700, et
	# sautait à ~14 000 à l'échange de passagers du demi-tour (retour
	# d'essai 2026-07-13). Avec le max des deux brins : 12 767 → 13 994,
	# transition continue.
	# Élasticité : accélération réelle de la poulie sur ce pas (tambour
	# compris), sauf l'amortisseur du butoir et un choc de collision.
	var a_poulie: float = (v - v_entree) / dt
	if buffer_clamp or crashed:
		a_poulie = 0.0
	# freins de voie serrés (urgence, parachute) : rame tenue par ses pinces
	_elastic_step(dt, a_poulie - a_frein_voie, emergency_ramp > 0.0)
	# Effort dynamique = allongement élastique de chaque brin (au lieu de
	# l'inertie rigide m·a : quasi statique, k·x = m·a).
	var km1: Vector2 = _brin_k_m(s, m_up)
	var km2: Vector2 = _brin_k_m(ghost_s_phys(), m_down)
	var dyn1: float = -km1.x * el_x1 - 2.0 * REBOUND_ZETA * sqrt(km1.x * km1.y) * el_v1
	var dyn2: float = -km2.x * el_x2 - 2.0 * REBOUND_ZETA * sqrt(km2.x * km2.y) * el_v2
	tension_dan = maxf(
		_side_tension_n(m_up, s, 0.0, v) + dyn1,
		_side_tension_n(m_down, PNConstants.miroir(s), 0.0, -v) + dyn2,
	) / 10.0
	tension_dan = maxf(tension_dan, 0.0)

	# --- Puissance ------------------------------------------------------
	# Traction : le moteur tire → puissance consommée. Régén :
	# l'entraînement freine en génératrice (f_regen) → puissance
	# récupérée = |F·v|·0,80 (roue → machine DC → réseau ; ~30 kWh par
	# descente pleine/vide, modèle sans chiffre publié). Vraie force du modèle désormais, plus une
	# heuristique — le frein de service reste à ~0 % en marche normale.
	# Puissance ÉLECTRIQUE : mécanique / rendement (audit 2026-09-26) +
	# PERTES du drive dès qu'il pousse : cuivre ∝ F² (4 % du nominal au
	# courant nominal) et excitation. Au décollage en pente, le couple est
	# là avant la vitesse : l'afficheur ne part plus de zéro.
	power_kw = maxf(0.0, (f_motor * v) / PNConstants.DRIVE_EFF / 1000.0)
	if trip_started and not drive_off and f_motor * float(direction) > 0.0:
		var f_rated: float = PNConstants.P_MAX / PNConstants.V_MAX
		power_kw += PNConstants.DRIVE_FIELD_KW \
			+ PNConstants.DRIVE_CU_LOSS_FRAC * PNConstants.P_MAX / 1000.0 \
				* pow(absf(f_motor) / f_rated, 2.0)
	regen_kw = absf(f_regen * v) * PNConstants.REGEN_EFF / 1000.0

	# Lissage affichage (EMA τ ≈ 0.3 s)
	var alpha: float = minf(1.0, dt / 0.3)
	tension_dan_disp += (tension_dan - tension_dan_disp) * alpha
	power_kw_disp += (power_kw - power_kw_disp) * alpha
	regen_kw_disp += (regen_kw - regen_kw_disp) * alpha

	if trip_started:
		trip_time += dt


# --- Collisions (mode Défi) ----------------------------------------------
# Trois issues possibles, dans cet ordre de priorité :
#   1. DÉRAILLEMENT — franchir l'évitement Abt à plus de 13,5 m/s (+12 %).
#      Le max certifié étant 12 m/s, l'évitement se prend à pleine vitesse
#      en exploitation normale : on ne déraille pas à 12,1 m/s.
#   2. COLLISION AVEC L'AUTRE RAME — câble rompu : la rame 2, découplée, a
#      freiné et s'est immobilisée. La vôtre la percute LÀ OÙ ELLE EST.
#   3. BUTOIR — atteindre le bout de voie à plus de 1,5 m/s.
func _check_crash(clamp_lo: float, clamp_hi: float) -> void:
	if crashed or not challenge_mode or finished or not trip_started:
		return
	var v_abs: float = absf(v)
	var in_switch: bool = s >= PNConstants.PASSING_START \
		and s <= PNConstants.PASSING_END
	if in_switch and v_abs > SWITCH_DERAIL_V:
		_fire_crash("derail", v_abs)
		return
	if cable_rupture:
		var gap: float = ghost_s_phys() - s
		if absf(gap) < 2.0 * PNConstants.TRAIN_HALF and v_abs > CRASH_SPEED \
				and gap * v > 0.0:
			_fire_crash("cabin", v_abs)
			return
	if (s >= clamp_hi and v > CRASH_SPEED) or (s <= clamp_lo and v < -CRASH_SPEED):
		_fire_crash("buffer", v_abs)


func _fire_crash(kind: String, speed: float) -> void:
	crashed = true
	crash_kind = kind
	crash_speed_ms = speed
	# À-coup dans le câble : la rame stoppe net mais le brin élastique
	# (3,4 km) encaisse l'énergie → la jauge bondit. Sauf si le câble est
	# déjà rompu : plus de brin à tendre.
	if not cable_rupture:
		tension_dan = minf(42000.0, tension_dan + 4000.0 + speed * 4500.0)
		tension_dan_disp = tension_dan
	crash_occurred.emit(kind, speed)


# Tension (N) d'UN brin au niveau de la poulie motrice : rame de masse m à
# la position s_pos, accélérée à a_s le long de sa pente (signe +s).
# Frottement et traînée SIGNÉS (audit 2026-09-26) : ils chargent le brin
# quand la rame va VERS la poulie, le déchargent quand elle s'en éloigne.
func _side_tension_n(m: float, s_pos: float, a_s: float, v_side: float) -> float:
	var theta_s: float = atan(SlopeProfile.gradient_phys_at(s_pos))
	var m_brin: float = PNConstants.CABLE_KG_M * maxf(PNConstants.LENGTH - s_pos, 0.0)
	var sgn: float = signf(v_side) if absf(v_side) > 0.05 else 0.0
	var t: float = m * PNConstants.G * sin(theta_s) \
		+ sgn * (PNConstants.MU_ROLL * m * PNConstants.G * cos(theta_s) \
			+ aero_drag_side_n(s_pos, v_side) + 0.5 * rope_rollers_n()) \
		+ PNConstants.CABLE_KG_M * PNConstants.G \
			* maxf(0.0, PNConstants.ALT_HIGH - SlopeProfile.altitude_at(s_pos)) \
		+ (m + m_brin) * a_s
	return maxf(t, 0.0)


# --- Régulateur Von Roll -------------------------------------------------

func _regulator(
	dt: float,
	m_up: float,
	_m_down: float,
	m_total: float,
	_g_slope: float,
	theta: float,
) -> void:
	# Si arrêt électrique ou emergency : couper moteur, laisser frein
	if emergency or not trip_started:
		speed_cmd = maxf(0.0, speed_cmd - 0.5 * dt)
		speed_cmd_eff = maxf(0.0, speed_cmd_eff - 0.5 * dt)
		throttle = 0.0
		regen_level = 0.0
		_reg_hold = true
		return

	# Distance restante dans la direction de marche
	var dist_to_stop: float
	if direction > 0:
		dist_to_stop = maxf(0.0, PNConstants.STOP_S - s)
	else:
		dist_to_stop = maxf(0.0, s - PNConstants.START_S)

	# Aiguillage Abt désaligné : le point d'arrêt de l'interlock (15 m
	# en amont de l'aiguillage d'entrée) DEVIENT la cible d'arrêt si la
	# rame est en amont — toute la machinerie d'approche (enveloppe,
	# feed-forward, creep, docking) s'applique alors naturellement au
	# point de hold. Un simple min() sur l'enveloppe sans ff faisait
	# dépasser l'aiguillage de ~175 m (mesuré au banc). Rame déjà dans
	# l'évitement : le cap de panne s'applique jusqu'à la sortie.
	# 🔴 Le hold TIENT même dépassé d'un millimètre (audit 2026-09-26) :
	# l'ancien « if d_hold > 0 » relâchait la cible dès que la rame
	# franchissait le point d'arrêt en rampant, et elle repartait au
	# plafond de panne (banc 3D). En amont de l'aiguillage, la cible reste
	# le point de hold (distance 0 = arrêt).
	if abt_hold:
		if direction > 0 and s < PNConstants.PASSING_START:
			dist_to_stop = minf(dist_to_stop,
				maxf(0.0, (PNConstants.PASSING_START - 15.0) - s))
		elif direction < 0 and s > PNConstants.PASSING_END:
			dist_to_stop = minf(dist_to_stop,
				maxf(0.0, s - (PNConstants.PASSING_END + 15.0)))

	var v_travel: float = v * float(direction)

	# Gravité projetée sur direction de voyage — avec la pente locale de
	# CHAQUE rame, comme la physique. L'ancien raccourci mono-pente
	# (−dm·g·sinθ_main) se trompait de SIGNE dès que l'asymétrie du profil
	# l'emportait sur l'écart de masse (rame chargée en bas à 22 % vs
	# contrepoids vide à 29 %) : le feed-forward coupait la traction à
	# tort et la rame dérivait vers l'équilibre au lieu de descendre.
	var theta_gr: float = atan(SlopeProfile.gradient_phys_at(PNConstants.miroir(s)))
	var f_grav_s: float = -(m_up * sin(theta) - _m_down * sin(theta_gr)) * PNConstants.G
	f_grav_s += rope_weight_force_n(s)   # poids propre du câble (audit 2026-09-26)
	var f_grav_travel: float = f_grav_s * float(direction)
	var gravity_helps: bool = f_grav_travel > 200.0

	# Enveloppe vitesse adaptée à la gravité
	var d_to_creep: float = maxf(0.0, dist_to_stop - PNConstants.CREEP_DIST)
	var a_env: float
	if gravity_helps:
		a_env = PNConstants.A_TARGET
	else:
		a_env = PNConstants.A_NATURAL_UP
	var v_envelope: float = sqrt(PNConstants.V_CREEP * PNConstants.V_CREEP + 2.0 * a_env * d_to_creep)

	# Setpoint slewing (ramp limiter Von Roll)
	var ramp_up: float = 0.35
	var ramp_down: float = 0.25
	# Mode DÉFI : la plage de consigne va AU-DELÀ de V_MAX (jusqu'à 15 m/s)
	# → consigne à fond = le drive pousse la machine en survitesse, même en
	# descente où la gravité s'oppose. Croisière normale ≈ 80 % de consigne.
	var v_cmd_max: float = CHALLENGE_V_CMD_MAX if challenge_mode \
		else PNConstants.V_MAX
	var driver_target: float = speed_cmd * v_cmd_max
	# Plafond de panne : borne la CIBLE et la rejoint par une rampe
	# DÉDIÉE de 0,60 m/s² (port du PC v1.12.21) — réduction franche de
	# type frein de service modulé, mais jamais la coupure sèche
	# d'avant l'audit (« le funi réduit sa vitesse quasi
	# instantanément »).
	if speed_cap_external < PNConstants.V_MAX and driver_target > speed_cap_external:
		driver_target = speed_cap_external
		ramp_down = 0.60
	# Mode DÉFI : la consigne suit le conducteur à une décélération de
	# service RÉALISTE (0,7 m/s² sur le setpoint). Depuis 12 m/s, l'arrêt
	# prend une centaine de mètres : il faut ANTICIPER le freinage, sinon
	# on percute le butoir — c'est tout l'intérêt du mode.
	if challenge_mode:
		ramp_down = 0.70
	# Feed-forward de la PENTE de consigne (port du PC v1.12.21) : sans
	# lui, le P (k_a = 0,35) doit accumuler ~1,7 m/s d'erreur pour tenir
	# une rampe de 0,6 — la rame traînait au-dessus du plafond et la
	# surveillance cap_over déclenchait à tort.
	var eff_prev: float = speed_cmd_eff
	var de: float = driver_target - speed_cmd_eff
	if de > 0.0:
		speed_cmd_eff = minf(driver_target, speed_cmd_eff + ramp_up * dt)
	elif de < 0.0:
		speed_cmd_eff = maxf(driver_target, speed_cmd_eff - ramp_down * dt)
	var a_cmd_ff: float = (speed_cmd_eff - eff_prev) / dt if dt > 0.0 else 0.0

	# Mode DÉFI : plus de filet d'auto-dock. Le régulateur suit la consigne
	# du CONDUCTEUR — pas d'enveloppe d'approche, pas de creep automatique.
	# C'est à lui de réduire la consigne / de freiner à temps.
	var challenge_drive: bool = challenge_mode
	var target_v: float = speed_cmd_eff if challenge_drive \
		else minf(speed_cmd_eff, v_envelope)

	# Zone creep : dernière CREEP_DIST m à CREEP_V, puis docking final en
	# ~5 s sur les 2,5 derniers mètres (0,15 m/s²) — ALIGNÉ sur le sim
	# Python v1.12.3 : l'ancien couple 0,04/6 m du port donnait une entrée
	# en gare interminable (~0,2 m/s pendant 20 s, constaté machine).
	# a_ff_env : décélération d'ENVELOPPE anticipée (feed-forward) — sans
	# elle, le contrôleur P doit accumuler ~0,4 m/s d'erreur pour commander
	# la rampe → la rame traînait 0,4 m/s au-dessus du profil et finissait
	# sur le butoir (« arrêt instantané », retour d'essai 2026-07-13).
	# Le ff = VRAIE dérivée de la cible : d(√(2ad))/dt = −a·(v/v_cible) —
	# plein quand on SUIT le profil, nul quand on est en dessous (un ff
	# constant créait un équilibre parasite : rame plantée 0,5 m avant le
	# quai, a_des ≤ 0 dès que v passait sous le profil).
	var a_ff_env: float = 0.0
	if not challenge_drive and v_envelope < speed_cmd_eff \
			and dist_to_stop >= PNConstants.CREEP_DIST:
		a_ff_env = -a_env * clampf(v_travel / maxf(v_envelope, 0.05), 0.0, 1.2)
	if not challenge_drive and dist_to_stop < PNConstants.CREEP_DIST:
		var park_decel: float = 0.15
		var final_dist: float = 2.5
		if dist_to_stop > final_dist:
			target_v = PNConstants.V_CREEP
			a_ff_env = 0.0
		else:
			var v_park: float = sqrt(2.0 * park_decel * maxf(dist_to_stop, 0.001))
			target_v = minf(PNConstants.V_CREEP, v_park)
			a_ff_env = -park_decel * clampf(v_travel / maxf(target_v, 0.05), 0.0, 1.2)

	# Contrôleur unifié en FORCE (2026-07-13). L'entraînement calcule :
	#   a_des  = accélération désirée (erreur de vitesse, bornée par la
	#            rampe programmée ±A_TARGET)
	#   F_req  = m_total·a_des + f_ff   (f_ff = charge statique : gravité
	#            nette 2 pentes + frottement des 2 rames)
	#   F_req > 0 → traction ; F_req < 0 → retenue (frein/génératrice).
	# Continu dans les QUATRE quadrants. L'« autorité » de la version
	# précédente coupait la traction dès que la gravité aidait, même
	# quand l'accélération commandée exigeait ENCORE du couple : au
	# départ gare basse, le contrepoids attaque sa section à 27-29 %
	# pendant que la rame chargée est sur les 8-16 % du bas → gravité
	# nette MOTRICE de s≈120 à ≈330 m (jusqu'à +21 kN pour 230 pax) →
	# puissance qui tombait à 0 en pleine accélération (retour d'essai
	# 2026-07-13). Avec F_req : le moteur fournit le complément exact
	# (m·0,30 − excédent), la puissance CREUSE sans jamais claquer à 0.
	var err: float = target_v - v_travel
	var v_eff: float = maxf(absf(v), 0.8)
	# Enveloppe de force vue par le régulateur = celle de la physique : en
	# Défi le moteur est surrégimé (×1,8). Calculée pour le moteur nominal,
	# la commande produisait 1,8 fois la force voulue au-dessus de ~8 m/s →
	# dépassement de consigne au bouton + et freinage trop sec au bouton −
	# (retour d'essai 2026-09-28, parité PC).
	var p_reg: float = PNConstants.P_MAX * (CHAOS_MOTOR_OVERDRIVE if challenge_mode else 1.0)
	var f_motor_max: float = minf(PNConstants.F_STALL, p_reg / v_eff)

	var f_ff: float = -f_grav_travel + PNConstants.MU_ROLL * PNConstants.G \
		* (m_up * cos(theta) + _m_down * cos(theta_gr)) \
		+ rope_rollers_n() + aero_drag_n(s, target_v)
	# Tenue à l'arrêt (consigne 0, rame quasi arrêtée) : roulement, galets
	# et traînée s'opposent au MOUVEMENT, ils ne poussent pas une rame
	# immobile — les compter faisait ramper le variateur (parité PC).
	if target_v < 0.01 and v_travel < 0.4:
		f_ff = -f_grav_travel

	var demand_throttle: float
	var demand_brake: float
	var demand_regen: float = 0.0
	# Mode DÉFI : pas d'enveloppe d'approche ni de rampement, mais la
	# consigne reste une CONSIGNE DE VITESSE pour le variateur 4 quadrants,
	# 0 compris : il freine en génératrice et tient la rame. Seul le
	# maintien au FROTTEMENT (_reg_hold, frein à 0,5) est levé.
	# PRÉ-TENSION (2026-09-26) : couple statique posé avant que le tambour
	# ne lâche (sinon recul de 2 cm au décollage en pente).
	if trip_started and not _pretensioned:
		_pretensioned = true
		if f_ff > 0.0 and not manual_brake_held:
			throttle = maxf(throttle, minf(1.0, f_ff / maxf(f_motor_max, 1.0)))
	elif not trip_started:
		_pretensioned = false
	var chaos_hold: bool = challenge_mode
	_reg_hold = not chaos_hold and target_v < 0.01 and v_travel < 0.4
	if manual_brake_held:
		# Frein de service manuel prioritaire : le régulateur NE tire PAS
		# contre lui. Couple coupé, frein plein tant que le bouton est tenu
		# (sinon il abaissait `brake` et remontait le throttle → le moteur
		# annulait le freinage, décél ridicule).
		demand_throttle = 0.0
		demand_brake = 1.0
		demand_regen = 0.0
	elif _reg_hold:
		demand_throttle = 0.0
		demand_brake = 0.5
	else:
		# Consigne 0 en Défi (2026-09-28, parité PC) : le variateur suit la
		# consigne jusqu'à 0 et TIENT la vitesse nulle — il ne lâche plus la
		# rame. L'ancienne roue libre à 0 datait d'avant le poids du câble
		# dans la dynamique : en fin de montée, les 3,4 km de câble du
		# contrepoids tirent ≈ 99 kN vers la gare haute → la rame
		# réaccélérait jusqu'au butoir (« au bout il réaccélère et boum »).
		var k_a: float = 0.35   # m/s² de correction par m/s d'erreur
		# Borne haute = rampe programmée (confort moteur) ; borne basse =
		# frein service plein (−2,5) : le régulateur doit pouvoir
		# commander un vrai freinage (consigne coupée à pleine vitesse),
		# pas seulement la décélération de croisière. a_ff_env anticipe la
		# pente de l'enveloppe (approche/docking) pour que le P ne serve
		# qu'aux transitoires.
		# Le feed-forward est la dérivée de la CIBLE ACTIVE, exclusivement :
		# consigne (a_cmd_ff) quand elle gouverne, enveloppe (a_ff_env)
		# quand l'approche/creep gouverne. Le min() des deux (v1.12.23)
		# cumulait les freinages à l'arrivée quand le mode auto baissait
		# la consigne PENDANT l'approche → v plongeait à ~0,1 m/s sous le
		# profil puis RÉACCÉLÉRAIT à 0,75 pour finir (retour d'essai PWA
		# gare haute 2026-07-24).
		var setpoint_binding: bool = (speed_cmd_eff <= v_envelope
			and dist_to_stop >= PNConstants.CREEP_DIST)
		# Feed-forward de la rampe de consigne dans les DEUX sens (2026-09-26,
		# comme le PC) : l'ancien minf(0, ·) laissait le seul terme P
		# accélérer (constante de temps ≈ 3 s).
		var a_ff_total: float = a_cmd_ff if setpoint_binding \
			else a_ff_env
		var a_des: float = clampf(a_ff_total + err * k_a,
			-PNConstants.A_BRAKE_NORMAL, PNConstants.A_TARGET)
		var f_req: float = m_total * a_des + f_ff
		if f_req >= 0.0:
			demand_throttle = clampf(f_req / maxf(f_motor_max, 1.0), 0.0, 1.0)
			demand_brake = 0.0
		elif challenge_drive and speed_cmd >= 0.95:
			# CHAOS (consigne à fond) : plus AUCUNE retenue automatique.
			# Sur une descente chargée, la gravité excède ce que le moteur
			# demande → la rame S'EMBALLE au-delà de V_MAX. C'est au
			# conducteur de serrer le frein ou l'urgence.
			demand_throttle = 0.0
			demand_regen = 0.0
			demand_brake = 0.0
		else:
			# Retenue : l'ENTRAÎNEMENT freine en génératrice (le vrai
			# organe de retenue en descente chargée, ~30 kWh/descente),
			# le frein de service à friction ne prend que le débordement
			# au-delà de l'enveloppe du drive (audit 2026-07-24).
			demand_throttle = 0.0
			var f_need: float = -f_req
			var f_regen_max: float = maxf(f_motor_max, 1.0)
			demand_regen = clampf(f_need / f_regen_max, 0.0, 1.0)
			var overflow: float = f_need - f_regen_max
			demand_brake = clampf(overflow / (PNConstants.A_BRAKE_NORMAL \
				* m_total), 0.0, 1.0) if overflow > 0.0 else 0.0

	# Slew throttle, regen et brake
	var slew: float = 1.5 * dt
	var dth: float = clampf(demand_throttle - throttle, -slew, slew)
	throttle = clampf(throttle + dth, 0.0, 1.0)

	var drg: float = clampf(demand_regen - regen_level, -slew, slew)
	regen_level = clampf(regen_level + drg, 0.0, 1.0)

	var db: float = clampf(demand_brake - brake, -2.5 * dt, 2.5 * dt)
	brake = clampf(brake + db, 0.0, 1.0)


# --- Actions conducteur --------------------------------------------------

# Arrivée au terminus, phase 1 : serrage immédiat du frein tambour —
# coupe la traction, déclenche le rebond élastique du câble (visible en
# gare basse) et arme la temporisation avant l'ouverture des portes.
func _arrival_grab() -> void:
	trip_started = false
	maint_brake = true
	speed_cmd = 0.0
	speed_cmd_eff = 0.0
	turnaround_delay_remaining = TURNAROUND_DELAY_S
	print("[Physics] arrivée s=%.0f — frein tambour serré, portes à la stabilisation du câble (< %.0f cm, %.0f s maxi)"
		% [s, SETTLE_M * 100.0, TURNAROUND_DELAY_S])


# Arrivée au terminus, phase 2 (après TURNAROUND_DELAY_S) : demi-tour —
# portes rouvertes, direction inversée, séquences remises à zéro. Sans ça,
# en manuel, PRÊT/DÉPART ne refaisait JAMAIS rien après le premier trajet
# (trip_started restait vrai, portes fermées) → « plus de buzzer ni de
# son de portes au 2e départ » (retour d'essai Android 2026-07).
func _terminus_turnaround() -> void:
	doors_open = true
	announce_phase_remaining = 0.0
	_fermeture_seule = false
	departure_buzzer_remaining = 0.0
	door_phase_remaining = 0.0
	direction = -direction
	# Rotation passagers : tout le monde descend, puis une nouvelle charge
	# embarque pour le trajet retour (direction déjà inversée) — cf. step.
	debarquement()


# Embarquement — port de la logique Python : le trafic skieur est
# asymétrique (on MONTE en funiculaire, on redescend à ski) → montée
# chargée (90..167 pax/voiture), descente quasi vide (0..8), et le
# contrepoids reçoit l'inverse. C'est ce déséquilibre dm qui pilote la
# gravité nette, la tension câble et la puissance — l'ancien port laissait
# TOUT à zéro (dm = 0 : sim parfaitement équilibrée, compteur pax à 0).
# Les DEUX rames tirent leur charge dans la MÊME loi (2 voitures de
# 90..half en montée, 2 voitures de 0..8 en descente) : l'installation est
# statistiquement identique quelle que soit la cabine pilotée — l'ancien
# tirage du contrepoids (90..PAX_MAX-20 en un seul jet, moyenne ~202 contre
# ~257) faisait afficher moins de puissance quand on pilotait la descente.
# Fixe des CIBLES (embarquement progressif portes ouvertes) ; `instant`
# force la bascule immédiate (initialisation, bancs de test).
func roll_pax(instant: bool = false) -> void:
	var half: int = PNConstants.PAX_MAX / 2
	if direction > 0:
		pax_t_car1 = randi_range(90, half)
		pax_t_car2 = randi_range(90, half)
		ghost_pax_t = randi_range(0, 8) + randi_range(0, 8)
	else:
		pax_t_car1 = randi_range(0, 8)
		pax_t_car2 = randi_range(0, 8)
		ghost_pax_t = randi_range(90, half) + randi_range(90, half)
	if instant:
		pax_car1 = pax_t_car1
		pax_car2 = pax_t_car2
		ghost_pax = ghost_pax_t
		_pax1_f = float(pax_car1)
		_pax2_f = float(pax_car2)
		_ghost_f = float(ghost_pax)


# Arrivée en gare : les passagers des deux rames descendent (cibles à 0) ;
# la nouvelle charge (roll_pax) monte une fois les rames vides.
var _embarquement_apres_descente: bool = false


func debarquement() -> void:
	pax_t_car1 = 0
	pax_t_car2 = 0
	ghost_pax_t = 0
	_embarquement_apres_descente = true


# Affaissement d'embarquement de la rame pilotée (m, signé le long de s :
# négatif = glisse vers le bas de la pente). À ajouter à s_render.
func boarding_sag_offset() -> float:
	return -_sag_main


# Affaissement du wagon opposé (même convention, appliqué à SA position).
func ghost_sag_offset() -> float:
	return -_sag_ghost


# Raideur et masse (Rayleigh : + 1/3 du brin) du brin d'une rame à s_rame.
func _brin_k_m(s_rame: float, m_rame: float) -> Vector2:
	var span: float = maxf(PNConstants.LENGTH - s_rame, 20.0)
	return Vector2(CABLE_EA_N / span, m_rame + PNConstants.CABLE_KG_M * span / 3.0)


# frein_voie : urgence ou parachute serrés — chaque rame est tenue par ses
# pinces sur les rails : ni excitée par la poulie (la coupure du moteur
# faisait osciller une rame pleine de 2,7 m en montée), ni libre
# d'osciller (amortissement critique). Retour du 04/10 (parité PC).
func _elastic_step(dt: float, a_poulie: float, frein_voie: bool = false) -> void:
	if cable_rupture:
		# plus de brin : la rame libérée part de sa position et de sa
		# vitesse RÉELLES (poulie + écart), puis plus d'écart du tout
		if el_x1 != 0.0 or el_v1 != 0.0:
			s += el_x1
			s_prev_step += el_x1   # interpolation du rendu continue
			v += el_v1
			if ghost_locked_s >= 0.0:
				ghost_locked_s += el_x2
		el_x1 = 0.0; el_v1 = 0.0; el_x2 = 0.0; el_v2 = 0.0
		return
	if frein_voie:
		a_poulie = 0.0
	var zeta: float = 1.0 if frein_voie else REBOUND_ZETA
	var cfg: Array = [[s, mass_kg(), a_poulie], [ghost_s_phys(), ghost_mass_kg(), -a_poulie]]
	for i in range(2):
		var km: Vector2 = _brin_k_m(cfg[i][0], cfg[i][1])
		var k: float = km.x
		var m: float = km.y
		var w: float = sqrt(k / m)
		var c: float = 2.0 * zeta * sqrt(k * m)
		var x: float = el_x1 if i == 0 else el_x2
		var vx: float = el_v1 if i == 0 else el_v2
		var n: int = maxi(1, ceili(w * dt / 0.15))
		var h: float = dt / float(n)
		var a_f: float = cfg[i][2]
		for _j in range(n):      # Euler semi-implicite, stable
			vx += (-k * x - c * vx) / m * h - a_f * h
			x += vx * h
		if i == 0:
			el_x1 = x; el_v1 = vx
		else:
			el_x2 = x; el_v2 = vx


# Amplitude de l'oscillation élastique en cours (m), rame pilotée ET
# contrepoids : √(x² + (x'/ω)²) — l'installation est stabilisée quand les
# deux le sont (parité PC).
func rebound_envelope() -> float:
	var km1: Vector2 = _brin_k_m(s, mass_kg())
	var km2: Vector2 = _brin_k_m(ghost_s_phys(), ghost_mass_kg())
	var e1: float = Vector2(el_x1, el_v1 / sqrt(km1.x / km1.y)).length()
	var e2: float = Vector2(el_x2, el_v2 / sqrt(km2.x / km2.y)).length()
	return maxf(e1, e2)


# Écart élastique de la rame pilotée (m, signé le long de la pente) : à
# ajouter à la position de la poulie pour la rendre.
func rebound_offset() -> float:
	return el_x1


# Séquence de départ réelle, en TROIS phases successives :
#   1. annonce « fermeture des portes » (7,5 s — durée du fichier 01,
#      portes encore OUVERTES)
#   2. fermeture des portes (7,0 s — durée MESURÉE de door_buzzer.wav ;
#      avec 3,5 s la moitié du son débordait sur le buzzer, retour
#      d'essai iPad 2026-07-12)
#   3. BUZZER de départ 6 s (gare haute) / 8 s (gare basse — durées des
#      enregistrements réels), traction à la FIN du buzzer seulement
#      (le frein tambour tient pendant toute la séquence).
const ANNOUNCE_PHASE_S: float = 7.5
const DOOR_PHASE_S: float = PNConstants.DOOR_BUZZER_S + PNConstants.DOOR_CLIP_S   # 14 s : buzzer PUIS clip
var announce_phase_remaining: float = 0.0
var departure_buzzer_remaining: float = 0.0
var door_phase_remaining: float = 0.0
# Vantaux (ce que dessine cabin.gd) : ils ne bougent qu'avec le clip de
# fermeture, 1,3 s après son début — pas au début de la phase portes.
var door_leaves_open: bool = true
var door_leaves_timer: float = 0.0
var _doors_open_prev: bool = true


# La rame est-elle à quai (fenêtre ±5 m autour des points d'arrêt) ?
# Sert aux interlocks portes/buzzer : les buzzers sont des haut-parleurs
# PHYSIQUES sur les quais — inaudibles (et sans objet) en plein tunnel.
func at_station() -> bool:
	return s <= PNConstants.START_S + 5.0 or s >= PNConstants.STOP_S - 5.0


func request_depart() -> void:
	if (announce_phase_remaining > 0.0 or door_phase_remaining > 0.0) \
			and _fermeture_seule:
		# fermeture déjà lancée au bouton PORTES : elle enchaîne sur le
		# buzzer de départ
		_fermeture_seule = false
		return
	if trip_started or announce_phase_remaining > 0.0 \
			or departure_buzzer_remaining > 0.0 \
			or door_phase_remaining > 0.0:
		return
	if doors_open:
		# Séquence complète : annonce → fermeture portes → buzzer.
		announce_phase_remaining = ANNOUNCE_PHASE_S
	elif at_station():
		# portes déjà fermées (bouton PORTES) : buzzer de quai seul
		departure_buzzer_remaining = 8.0 if s < PNConstants.LENGTH * 0.5 else 6.0
	else:
		# Reprise EN TUNNEL (après inversion de sens / arrêt anormal) :
		# portes déjà fermées, pas de buzzer de quai — courte tempo
		# silencieuse puis traction, comme le PC (« Resuming mid-tunnel —
		# no buzzer », 1,5 s).
		departure_buzzer_remaining = 1.5


# Portes à la demande (bouton PORTES, touche D — port de la touche D du
# PC, retour du 06/10/2026) : mêmes verrous — rame immobile (|v| < 0,2
# m/s), ouverture à quai seulement ; en Défi, aucun verrou (on ouvre en
# marche, en plein tunnel). Ouverture : clip et vantaux tout de suite (cf.
# audio.gd, door_leaves). Fermeture : la séquence réelle annonce → buzzer
# → clip, SANS le buzzer de départ ; PRÊT/DÉPART enchaîne ensuite sur le
# buzzer seul. Une ouverture à l'arrivée fait descendre les passagers.
# Renvoie le message à afficher ("" = fait).
var _fermeture_seule: bool = false


func toggle_doors() -> String:
	var chaos: bool = challenge_mode
	if frozen or crashed:
		return "Rame immobilisée"
	if absf(v) >= 0.2 and not chaos:
		return "Portes verrouillées : rame en marche"
	if announce_phase_remaining > 0.0 or door_phase_remaining > 0.0 \
			or departure_buzzer_remaining > 0.0:
		return "Séquence de portes en cours"
	if doors_open:
		_fermeture_seule = true
		announce_phase_remaining = ANNOUNCE_PHASE_S
		return ""
	if not at_station() and not chaos:
		return "Ouverture impossible hors station"
	doors_open = true
	if finished:
		debarquement()
	return ""


# Inversion du sens de marche — port de reverse_trip() du PC (touche I) :
# autorisé à l'ARRÊT TOTAL uniquement, à quai comme en plein tunnel (cas
# d'usage réel : panne en voie → on redescend chercher la gare). La rame
# garde sa position, le tambour se réengage le temps du protocole, et le
# conducteur relance par PRÊT/DÉPART (sans buzzer si en tunnel). Retourne
# true si l'inversion a eu lieu (l'appelant joue l'annonce « retour en
# gare » et log l'événement).
func reverse_trip() -> bool:
	if absf(v) >= 0.1:
		return false
	direction = -direction
	v = 0.0
	a = 0.0
	speed_cmd = 0.0
	speed_cmd_eff = 0.0
	throttle = 0.0
	regen_level = 0.0
	brake = 0.0
	maint_brake = true
	trip_started = false
	finished = false
	trip_time = 0.0
	turnaround_delay_remaining = 0.0
	announce_phase_remaining = 0.0
	_fermeture_seule = false
	departure_buzzer_remaining = 0.0
	door_phase_remaining = 0.0
	# Portes : ouvertes UNIQUEMENT si on inverse à quai (embarquement,
	# avec rotation passagers) ; en tunnel elles restent fermées — on
	# n'ouvre pas sur un tube de 3 m.
	if at_station():
		doors_open = true
		roll_pax()
	print("[Physics] inversion du sens — direction %d, s=%.0f" % [direction, s])
	return true


func start_trip() -> void:
	trip_started = true
	maint_brake = false
	doors_open = false
	finished = false


func end_trip() -> void:
	trip_started = false
	maint_brake = true


func release_emergency() -> void:
	emergency = false
	emergency_ramp = 0.0
	# Comme le PC (keyReleaseEvent Shift) : le tambour, réengagé par
	# l'auto-park pendant l'arrêt d'urgence, est relâché AVEC l'urgence
	# quand la rame est immobilisée EN VOIE (voyage en cours, portes
	# fermées) — le régulateur reprend la charge et la conduite peut
	# repartir. Sans ça : tambour serré à vie après un arrêt d'urgence
	# en tunnel, impossible de repartir (retour d'essai PWA 2026-07-12).
	# À quai hors voyage, le tambour RESTE serré : c'est la séquence
	# PRÊT/DÉPART (buzzer → start_trip) qui le lèvera.
	if trip_started and not doors_open and absf(v) < 0.1:
		maint_brake = false


# --- Nouveau voyage après un game-over (mode Défi) ------------------------
# Remet la rame à quai, dégèle la physique, efface la collision et les
# avaries de la cascade de survitesse (moteur détruit / câble rompu). La
# gare de reprise est celle vers laquelle on roulait : après un crash au
# butoir haut, on repart d'en haut, en descente.
func restart_after_crash() -> void:
	crashed = false
	crash_kind = ""
	crash_speed_ms = 0.0
	frozen = false
	cable_rupture = false
	service_brake_fail = 1.0
	overspeed_level = 0
	ghost_locked_s = -1.0
	jerk_sum = 0.0
	v = 0.0
	a = 0.0
	speed_cmd = 0.0
	speed_cmd_eff = 0.0
	throttle = 0.0
	regen_level = 0.0
	brake = 0.0
	emergency = false
	emergency_ramp = 0.0
	emergency_brake = false
	abt_hold = false
	speed_cap_external = INF
	cap_over_timer = 0.0
	trip_started = false
	finished = false
	trip_time = 0.0
	maint_brake = true
	doors_open = true
	el_x1 = 0.0; el_v1 = 0.0; el_x2 = 0.0; el_v2 = 0.0   # rames au repos
	turnaround_delay_remaining = 0.0
	announce_phase_remaining = 0.0
	_fermeture_seule = false
	departure_buzzer_remaining = 0.0
	door_phase_remaining = 0.0
	_sag_ref_m_main = -1.0
	_sag_ref_m_ghost = -1.0
	_sag_main = 0.0
	_sag_ghost = 0.0
	# On repart de la gare vers laquelle on allait, dans l'autre sens.
	if direction > 0:
		s = PNConstants.STOP_S
		direction = -1
	else:
		s = PNConstants.START_S
		direction = 1
	s_prev_step = s
	s_render = s
	_embarquement_apres_descente = false
	roll_pax(true)
	print("[Physics] nouveau voyage — gare %s" % ["haute" if direction < 0 else "basse"])
