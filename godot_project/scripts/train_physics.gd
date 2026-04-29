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

	var m_up: float = mass_kg()
	var m_down: float = ghost_mass_kg()
	var m_total: float = m_up + m_down
	var dm: float = m_up - m_down

	var g_slope: float = SlopeProfile.gradient_at(s)
	var theta: float = atan(g_slope)
	var sint: float = sin(theta)
	var cost: float = cos(theta)

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
	var f_grav_net: float = -dm * PNConstants.G * sint

	# --- Friction roulement ----------------------------------------------
	var f_roll_mag: float = PNConstants.MU_ROLL * m_total * PNConstants.G * cost
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

	# Intégration
	var new_v: float = v + acc * dt
	# Bleed-off survitesse
	if new_v * direction > v_limit and f_motor == 0.0:
		var excess: float = new_v * direction - v_limit
		var bleed: float = minf(excess, 1.5 * dt)
		new_v -= bleed * float(direction)

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
	elif s <= clamp_lo:
		s = clamp_lo
		if v < 0.0:
			v = minf(0.0, v + 2.0 * dt)
			acc = 2.0
		if direction < 0 and not finished:
			finished = true

	# Frein parking (drum) ou frein urgence (panne grave)
	if maint_brake or doors_open or emergency_brake:
		v = 0.0
		acc = 0.0

	a = acc

	# --- Tension câble ---------------------------------------------------
	var m_heavy: float = maxf(m_up, m_down)
	var a_travel: float = acc * float(direction)
	var t_gravity: float = m_heavy * PNConstants.G * sint
	var t_friction: float = PNConstants.MU_ROLL * m_heavy * PNConstants.G * cost
	var t_inertia: float = maxf(0.0, m_heavy * a_travel)
	tension_dan = (t_gravity + t_friction + t_inertia) / 10.0
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

	# Zone creep : dernière CREEP_DIST m à CREEP_V
	if dist_to_stop < PNConstants.CREEP_DIST:
		var park_decel: float = 0.04
		var final_dist: float = 6.0
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
