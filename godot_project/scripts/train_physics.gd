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
var v: float = 0.0                       # vitesse signée (m/s)
var a: float = 0.0                       # dernière accel (m/s²)
var direction: int = 1                   # +1 montée, -1 descente

var speed_cmd: float = 0.0               # setpoint conducteur (0..1)
var speed_cmd_eff: float = 0.0           # setpoint effectif (slew-limited, m/s)
var throttle: float = 0.0                # demande moteur interne (0..1)
var brake: float = 0.0                   # frein service (0..1)
var emergency: bool = false              # frein urgence latché
var emergency_ramp: float = 0.0          # rampe engagement (0..1)

var doors_open: bool = true
var lights_cabin: bool = true
var lights_head: bool = false
var maint_brake: bool = true             # frein parking (drum)
var emergency_brake: bool = false        # frein urgence (panne grave)
var speed_cap_external: float = INF      # plafond vitesse imposé par panne (m/s)
var pax_car1: int = 0
var pax_car2: int = 0
var ghost_pax: int = 0                   # passagers wagon opposé

var tension_dan: float = 0.0
var tension_dan_disp: float = 0.0        # lissé pour affichage
var power_kw: float = 0.0
var power_kw_disp: float = 0.0
var regen_kw: float = 0.0
var inrush_timer: float = 0.0

var trip_started: bool = false
var trip_time: float = 0.0
var finished: bool = false
var dbg_f_grav_net: float = 0.0          # dernière gravité nette (banc de parité)

# --- Rebond élastique du câble à l'arrêt (port du Python _cable_bounce) --
# x(t) = A·e^(−ζωt)·sin(ωt) avec k = EA/L (L = câble entre la rame et la
# poulie motrice en GARE HAUTE) : en bas L ≈ 3,45 km → T ≈ 5-8 s, jusqu'à
# ±25 cm ; en haut L ≈ 25 m → millimétrique. L'asymétrie sort de la
# physique, rien n'est câblé en dur. Appliqué à s_render (visuel) : le s
# physique est tenu par le clamp + frein tambour.
const CABLE_EA_N: float = 1.25e8
const REBOUND_ZETA: float = 0.15
const REBOUND_GRAB_A: float = 0.35   # m/s² relâchés au serrage du tambour
var rebound_timer: float = -1.0      # < 0 = inactif
var rebound_anchor_s: float = 0.0
var rebound_dir: int = 1             # direction figée au serrage (le
                                     # demi-tour inverse `direction` alors
                                     # que l'oscillation court encore)

# Temporisation d'arrivée : la rame reste immobilisée portes fermées
# (rebond visible) avant l'ouverture des portes + inversion du sens.
const TURNAROUND_DELAY_S: float = 15.0
var turnaround_delay_remaining: float = 0.0

# --- Accesseurs -----------------------------------------------------------

func pax() -> int:
	return pax_car1 + pax_car2


func mass_kg() -> float:
	return PNConstants.TRAIN_EMPTY_KG + pax() * PNConstants.PAX_KG


func ghost_mass_kg() -> float:
	return PNConstants.TRAIN_EMPTY_KG + ghost_pax * PNConstants.PAX_KG


# --- Step principal -------------------------------------------------------

func step(dt: float) -> void:
	# Clamp dt pour éviter de casser la physique sur un gros hiccup
	dt = clampf(dt, 0.001, 0.1)
	s_prev_step = s

	# Séquence de départ en TROIS phases successives (retour d'essai iPad
	# 2026-07-12 : annonce, portes et buzzer se superposaient) :
	# annonce « fermeture des portes » (7,5 s, portes encore ouvertes) →
	# fermeture des portes (3,5 s) → buzzer 6-8 s → traction.
	if announce_phase_remaining > 0.0:
		announce_phase_remaining = maxf(0.0, announce_phase_remaining - dt)
		if announce_phase_remaining <= 0.0:
			doors_open = false
			door_phase_remaining = DOOR_PHASE_S
	elif door_phase_remaining > 0.0:
		door_phase_remaining = maxf(0.0, door_phase_remaining - dt)
		if door_phase_remaining <= 0.0:
			departure_buzzer_remaining = \
				8.0 if s < PNConstants.LENGTH * 0.5 else 6.0
	elif departure_buzzer_remaining > 0.0:
		departure_buzzer_remaining = maxf(0.0, departure_buzzer_remaining - dt)
		if departure_buzzer_remaining <= 0.0:
			start_trip()

	var m_up: float = mass_kg()
	var m_down: float = ghost_mass_kg()
	var m_total: float = m_up + m_down

	# Pente LOCALE de chaque rame (port du sim Python) : le profil n'est
	# pas symétrique (8 % au départ, 30 % au milieu, 6 % en haut), donc la
	# rame principale à s et le contrepoids à (L − s) sont rarement sur la
	# même pente — l'équilibre du câble dépend des DEUX sinus. L'ancien
	# port utilisait la pente de la rame pilotée pour les deux.
	var g_slope: float = SlopeProfile.gradient_phys_at(s)
	var theta: float = atan(g_slope)
	var sint: float = sin(theta)
	var cost: float = cos(theta)
	var theta_g: float = atan(SlopeProfile.gradient_phys_at(PNConstants.LENGTH - s))
	var sint_g: float = sin(theta_g)
	var cost_g: float = cos(theta_g)

	var v_limit: float = minf(PNConstants.V_MAX, speed_cap_external)

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
	var f_motor_max: float = minf(PNConstants.F_STALL, f_motor_power_cap)
	var f_motor: float = throttle * f_motor_max * float(direction)

	# Ne pas pomper de puissance si déjà à la limite
	if v * direction >= v_limit and f_motor * direction > 0.0:
		f_motor = 0.0

	# Interlock portes : pas de traction si portes ouvertes
	if doors_open:
		f_motor = 0.0

	# --- Gravité (déséquilibre cable) ------------------------------------
	# Chaque rame avec SA pente locale (comme le sim Python) :
	#   f_grav_s = −(m_main·sinθ_main − m_ghost·sinθ_ghost)·g
	var f_grav_net: float = -(m_up * sint - m_down * sint_g) * PNConstants.G
	dbg_f_grav_net = f_grav_net   # exposé pour le banc de parité PC↔3D

	# --- Friction roulement (les 2 rames, chacune sur sa pente) -----------
	var f_roll_mag: float = PNConstants.MU_ROLL * PNConstants.G \
		* (m_up * cost + m_down * cost_g)
	var f_roll: float = 0.0
	if absf(v) > 0.05:
		f_roll = -signf(v) * f_roll_mag

	# --- Freins ----------------------------------------------------------
	if emergency:
		emergency_ramp = minf(1.0, emergency_ramp + PNConstants.A_BRAKE_EMERG_RAMP * dt)
	else:
		emergency_ramp = maxf(0.0, emergency_ramp - PNConstants.A_BRAKE_EMERG_RAMP * dt)

	var a_brk: float = 0.0
	if emergency_ramp > 0.0:
		a_brk = emergency_ramp * PNConstants.A_BRAKE_EMERGENCY
	elif brake > 0.0:
		a_brk = brake * PNConstants.A_BRAKE_NORMAL

	var f_brake: float = 0.0
	if absf(v) > 0.05:
		f_brake = -signf(v) * a_brk * m_total

	# Somme et intégration
	var net: float = f_motor + f_grav_net + f_roll + f_brake
	var acc: float = net / m_total

	# Cap accel moteur (confort) — soft-start progressive
	if not emergency and brake < 0.05:
		var v_abs: float = absf(v)
		var soft_cap: float = PNConstants.A_START + \
			(PNConstants.A_MAX_REG - PNConstants.A_START) * \
			minf(1.0, v_abs / PNConstants.V_SOFT_RAMP)
		if acc > soft_cap:
			acc = soft_cap
		elif acc < -soft_cap:
			acc = -soft_cap

	# Kill creep final
	if a_brk > 0.0 and absf(v) < 0.03:
		v = 0.0
		acc = 0.0

	# Auto-park (chaîne de sécurité Von Roll, comme le PC) : train
	# immobilisé sous frein d'urgence → le tambour se réengage seul pour
	# qu'il ne reparte pas sur la pente.
	if emergency and absf(v) < 0.05 and not maint_brake:
		maint_brake = true

	# Intégration
	var new_v: float = v + acc * dt
	# Bleed-off survitesse (régénératif) — les DEUX sens, comme le PC
	if new_v * direction > v_limit and f_motor == 0.0:
		var excess: float = new_v * direction - v_limit
		var bleed: float = minf(excess, 1.5 * dt)
		new_v -= bleed * float(direction)
	if new_v * direction < -v_limit:
		var excess_r: float = -v_limit - new_v * direction
		var bleed_r: float = minf(excess_r, 1.5 * dt)
		new_v += bleed_r * float(direction)

	s += ((v + new_v) / 2.0) * dt
	v = new_v

	# Clamp position
	var clamp_lo: float = PNConstants.START_S
	var clamp_hi: float = PNConstants.STOP_S
	if s >= clamp_hi:
		s = clamp_hi
		if v > 0.0:
			v = maxf(0.0, v - 2.0 * dt)
			acc = -2.0
		if direction > 0 and not finished:
			finished = true
			_arrival_grab()
	elif s <= clamp_lo:
		s = clamp_lo
		if v < 0.0:
			v = minf(0.0, v + 2.0 * dt)
			acc = 2.0
		if direction < 0 and not finished:
			finished = true
			_arrival_grab()

	# Temporisation d'arrivée → demi-tour (portes + inversion)
	if turnaround_delay_remaining > 0.0:
		turnaround_delay_remaining = maxf(0.0, turnaround_delay_remaining - dt)
		if turnaround_delay_remaining <= 0.0:
			_terminus_turnaround()

	# Chrono du rebond élastique
	if rebound_timer >= 0.0:
		rebound_timer += dt

	# Frein parking (drum) ou frein urgence (panne grave)
	if maint_brake or doors_open or emergency_brake:
		v = 0.0
		acc = 0.0

	a = acc

	# --- Tension câble (port complet du modèle Python) --------------------
	# Le brin entre la poulie motrice (gare haute) et la rame LOURDE porte :
	#   - le poids de la rame lourde le long de SA pente locale (pas celle
	#     de la rame pilotée — elles diffèrent sur ce profil asymétrique)
	#   - le poids PROPRE du câble au-dessus d'elle : ρ·g·Δaltitude, exact
	#     quel que soit le profil (∫ρg·sinθ·ds = ρg·Δh) — ~9 900 daN quand
	#     la rame lourde est en bas, ~0 en haut. C'est CE terme qui fait
	#     évoluer la jauge le long du trajet (manquait dans le port 3D :
	#     les valeurs ne collaient pas avec le programme PC).
	#   - le frottement de roulement de la rame lourde
	#   - l'inertie de traction, uniquement en accélération (au freinage le
	#     câble se DÉCHARGE : le frein absorbe sur le rail).
	var m_heavy: float = maxf(m_up, m_down)
	var s_heavy: float = s if m_up >= m_down else (PNConstants.LENGTH - s)
	var theta_h: float = atan(SlopeProfile.gradient_phys_at(s_heavy))
	var a_travel: float = acc * float(direction)
	var t_gravity: float = m_heavy * PNConstants.G * sin(theta_h)
	var t_friction: float = PNConstants.MU_ROLL * m_heavy * PNConstants.G * cos(theta_h)
	var t_cable: float = PNConstants.CABLE_KG_M * PNConstants.G \
		* maxf(0.0, PNConstants.ALT_HIGH - SlopeProfile.altitude_at(s_heavy))
	var t_inertia: float = maxf(0.0, m_heavy * a_travel)
	tension_dan = (t_gravity + t_friction + t_cable + t_inertia) / 10.0
	if tension_dan < 0.0:
		tension_dan = 0.0

	# --- Puissance ------------------------------------------------------
	var power_signed_kw: float = (f_motor * v) / 1000.0
	if power_signed_kw >= 0.0:
		power_kw = power_signed_kw
		regen_kw = 0.0
	else:
		power_kw = 0.0
		regen_kw = -power_signed_kw * 0.80

	# Lissage affichage (EMA τ ≈ 0.3 s)
	var alpha: float = minf(1.0, dt / 0.3)
	tension_dan_disp += (tension_dan - tension_dan_disp) * alpha
	power_kw_disp += (power_kw - power_kw_disp) * alpha

	if trip_started:
		trip_time += dt


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
		return

	# Distance restante dans la direction de marche
	var dist_to_stop: float
	if direction > 0:
		dist_to_stop = maxf(0.0, PNConstants.STOP_S - s)
	else:
		dist_to_stop = maxf(0.0, s - PNConstants.START_S)

	var v_travel: float = v * float(direction)

	# Gravité projetée sur direction de voyage
	var dm_r: float = m_up - _m_down
	var f_grav_s: float = -dm_r * PNConstants.G * sin(theta)
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
	var driver_target: float = speed_cmd * PNConstants.V_MAX
	var de: float = driver_target - speed_cmd_eff
	if de > 0.0:
		speed_cmd_eff = minf(driver_target, speed_cmd_eff + ramp_up * dt)
	elif de < 0.0:
		speed_cmd_eff = maxf(driver_target, speed_cmd_eff - ramp_down * dt)

	var target_v: float = minf(speed_cmd_eff, v_envelope)

	# Zone creep : dernière CREEP_DIST m à CREEP_V, puis docking final en
	# ~4 s sur les 2,5 derniers mètres (0,15 m/s²) — ALIGNÉ sur le sim
	# Python v1.12.3 : l'ancien couple 0,04/6 m du port donnait une entrée
	# en gare interminable (~0,2 m/s pendant 20 s, constaté machine).
	if dist_to_stop < PNConstants.CREEP_DIST:
		var park_decel: float = 0.15
		var final_dist: float = 2.5
		if dist_to_stop > final_dist:
			target_v = PNConstants.V_CREEP
		else:
			var v_park: float = sqrt(2.0 * park_decel * maxf(dist_to_stop, 0.001))
			target_v = minf(PNConstants.V_CREEP, v_park)

	# Contrôleur P unifié avec feed-forward
	var err: float = target_v - v_travel
	var v_eff: float = maxf(absf(v), 0.8)
	var f_motor_max: float = minf(PNConstants.F_STALL, PNConstants.P_MAX / v_eff)

	var f_ff: float = -f_grav_travel + PNConstants.MU_ROLL * m_total * PNConstants.G * cos(theta)
	var ff_throttle: float = maxf(0.0, f_ff) / maxf(f_motor_max, 1.0)
	var ff_brake: float = maxf(0.0, -f_ff) / (PNConstants.A_BRAKE_NORMAL * m_total)

	var demand_throttle: float
	var demand_brake: float
	if target_v < 0.01 and v_travel < 0.4:
		demand_throttle = 0.0
		demand_brake = 0.5
	else:
		var k_p: float = 0.18
		demand_throttle = clampf(ff_throttle + err * k_p, 0.0, 1.0)
		demand_brake = clampf(ff_brake - err * k_p, 0.0, 1.0)
		if demand_throttle > 0.0 and demand_brake > 0.0:
			if demand_throttle > demand_brake:
				demand_throttle -= demand_brake
				demand_brake = 0.0
			else:
				demand_brake -= demand_throttle
				demand_throttle = 0.0

	# Slew throttle et brake
	var slew: float = 1.5 * dt
	var dth: float = clampf(demand_throttle - throttle, -slew, slew)
	throttle = clampf(throttle + dth, 0.0, 1.0)

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
	rebound_anchor_s = s
	rebound_dir = direction
	rebound_timer = 0.0
	turnaround_delay_remaining = TURNAROUND_DELAY_S
	print("[Physics] arrivée s=%.0f — frein tambour serré, rebond armé, portes dans %.0f s"
		% [s, TURNAROUND_DELAY_S])


# Arrivée au terminus, phase 2 (après TURNAROUND_DELAY_S) : demi-tour —
# portes rouvertes, direction inversée, séquences remises à zéro. Sans ça,
# en manuel, PRÊT/DÉPART ne refaisait JAMAIS rien après le premier trajet
# (trip_started restait vrai, portes fermées) → « plus de buzzer ni de
# son de portes au 2e départ » (retour d'essai Android 2026-07).
func _terminus_turnaround() -> void:
	doors_open = true
	announce_phase_remaining = 0.0
	departure_buzzer_remaining = 0.0
	door_phase_remaining = 0.0
	direction = -direction
	# Rotation passagers : tout le monde descend, une nouvelle charge
	# embarque pour le trajet retour (direction déjà inversée).
	roll_pax()


# Embarquement — port de la logique Python : le trafic skieur est
# asymétrique (on MONTE en funiculaire, on redescend à ski) → montée
# chargée (90..167 pax/voiture), descente quasi vide (0..8), et le
# contrepoids reçoit l'inverse. C'est ce déséquilibre dm qui pilote la
# gravité nette, la tension câble et la puissance — l'ancien port laissait
# TOUT à zéro (dm = 0 : sim parfaitement équilibrée, compteur pax à 0).
func roll_pax() -> void:
	var half: int = PNConstants.PAX_MAX / 2
	if direction > 0:
		pax_car1 = randi_range(90, half)
		pax_car2 = randi_range(90, half)
		ghost_pax = randi_range(0, 12)
	else:
		pax_car1 = randi_range(0, 8)
		pax_car2 = randi_range(0, 8)
		ghost_pax = randi_range(90, PNConstants.PAX_MAX - 20)


# Décalage visuel (m, signé le long de la pente) du rebond élastique.
# À ajouter à s_render — s'éteint tout seul (< 1 mm → coupé).
func rebound_offset() -> float:
	if rebound_timer < 0.0:
		return 0.0
	var span: float = maxf(PNConstants.LENGTH - rebound_anchor_s, 20.0)
	var k: float = CABLE_EA_N / span
	var m: float = mass_kg()
	var omega: float = sqrt(k / maxf(m, 1.0))
	var amp: float = minf(m * REBOUND_GRAB_A / k, 0.45)
	var x: float = amp * exp(-REBOUND_ZETA * omega * rebound_timer) \
		* sin(omega * rebound_timer)
	if amp * exp(-REBOUND_ZETA * omega * rebound_timer) < 0.001:
		rebound_timer = -1.0   # éteint — plus de calcul
		return 0.0
	return float(rebound_dir) * x


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
const DOOR_PHASE_S: float = 7.0
var announce_phase_remaining: float = 0.0
var departure_buzzer_remaining: float = 0.0
var door_phase_remaining: float = 0.0


func request_depart() -> void:
	if trip_started or announce_phase_remaining > 0.0 \
			or departure_buzzer_remaining > 0.0 \
			or door_phase_remaining > 0.0:
		return
	announce_phase_remaining = ANNOUNCE_PHASE_S


func start_trip() -> void:
	trip_started = true
	maint_brake = false
	doors_open = false
	finished = false
	rebound_timer = -1.0


func end_trip() -> void:
	trip_started = false
	maint_brake = true


func release_emergency() -> void:
	emergency = false
	emergency_ramp = 0.0
