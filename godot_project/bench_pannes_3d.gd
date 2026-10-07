# Banc headless : valide les portages de l'audit physique v1.12.21 côté 3D.
# Exécution : godot --headless --path godot_project -s bench_pannes_3d.gd
extends SceneTree


func _make(direction: int, s0: float, v0: float) -> TrainPhysics:
	var ph := TrainPhysics.new()
	ph.direction = direction
	ph.s = s0
	ph.v = v0
	ph.speed_cmd = 1.0
	ph.speed_cmd_eff = absf(v0)
	ph.doors_open = false
	ph.maint_brake = false
	ph.trip_started = true
	ph.pax_car1 = 125
	ph.pax_car2 = 125
	ph.ghost_pax = 8
	return ph


func _run(ph: TrainPhysics, t_max: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var t := 0.0
	var v_prev := ph.v
	var decel_pk := 0.0
	while t < t_max:
		ph.step(dt)
		var a := (ph.v - v_prev) / dt
		decel_pk = maxf(decel_pk, -a * float(ph.direction))
		v_prev = ph.v
		t += dt
		if absf(ph.v) < 0.02 and t > 5.0:
			break
	return {"v": ph.v, "t": t, "s": ph.s, "decel_pk": decel_pk}


func _initialize() -> void:
	var ok := true

	# 1. Cap de panne 6 m/s depuis 10 m/s : rampe douce, pas de pic > 1
	var ph := _make(1, 1200.0, 10.0)
	ph.speed_cap_external = 6.0
	var r := _run(ph, 30.0)
	print("cap 6 m/s : v_fin=%.2f decel_pk=%.2f" % [r["v"], r["decel_pk"]])
	if absf(r["v"] - 6.0) > 0.5 or r["decel_pk"] > 1.0:
		print("  ECHEC cap"); ok = false

	# 2. cap_over : cap 6 mais frein neutralisé ? — simulé en forçant la
	# consigne haute chaque frame (le régulateur veut rester à 10).
	ph = _make(1, 600.0, 10.0)
	ph.speed_cap_external = 6.0
	var dt := 1.0 / 60.0
	var tripped := false
	for i in range(60 * 40):
		ph.speed_cmd_eff = 10.0   # sabotage : consigne re-forcée à 10
		ph.step(dt)
		if ph.emergency:
			tripped = true
			print("cap_over : urgence auto à t=%.1f s" % (float(i) / 60.0))
			break
	if not tripped:
		print("  ECHEC cap_over jamais déclenché"); ok = false

	# 3. abt_hold : la rame doit s'arrêter AVANT PASSING_START
	ph = _make(1, 1300.0, 8.0)
	ph.abt_hold = true
	ph.speed_cap_external = 4.0
	r = _run(ph, 240.0)
	print("abt_hold : arrêt à s=%.0f v=%.2f (aiguillage à %.0f)"
		% [r["s"], r["v"], PNConstants.PASSING_START])
	if r["s"] > PNConstants.PASSING_START - 5.0 or absf(r["v"]) > 0.5:
		print("  ECHEC abt_hold"); ok = false

	# 4. Arrivée avec consigne BAISSÉE pendant l'approche (mode auto) :
	# v ne doit jamais plonger sous le creep puis réaccélérer (retour
	# PWA gare haute 2026-07-24 : creux à 0,1 m/s puis remontée à 0,75).
	ph = _make(1, PNConstants.STOP_S - 400.0, 10.0)
	var dt2 := 1.0 / 60.0
	var v_min_creep := 99.0
	var t2 := 0.0
	while t2 < 240.0:
		var dist: float = PNConstants.STOP_S - ph.s
		# Profil du mode auto : réduction progressive puis 0,15 puis 0
		if dist > 200.0:
			ph.speed_cmd = 1.0
		elif dist > 50.0:
			ph.speed_cmd = lerpf(0.3, 1.0, (dist - 50.0) / 150.0)
		elif dist > 8.0:
			ph.speed_cmd = 0.15
		else:
			ph.speed_cmd = 0.0
		ph.step(dt2)
		if dist > 3.0 and dist < 40.0:
			v_min_creep = minf(v_min_creep, absf(ph.v))
		t2 += dt2
		if ph.finished:
			break
	print("arrivée consigne auto : v_min zone creep=%.2f fini=%s"
		% [v_min_creep, str(ph.finished)])
	if v_min_creep < 0.55 or not ph.finished:
		print("  ECHEC creux d'arrivée"); ok = false

	ok = _effets_de_panne() and ok

	print("BENCH_3D " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)


func _check(label: String, cond: bool, detail: String) -> bool:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	return cond


# Audit fonctionnel 07/10/2026 : les effets de panne portés par la
# physique (parité PC) — traction coupée, déclassement, jauge, survitesse.
func _effets_de_panne() -> bool:
	var ok := true
	var dt := 1.0 / 60.0

	# 5. Perte 400 V : urgence, puis PRÊT/DÉPART la relâche — la rame ne
	# doit PAS repartir tant que la panne tient (traction coupée) ; levée,
	# elle repart.
	var fm := FaultManager.new()
	var ph := _make(1, 1200.0, 8.0)
	fm.physics = ph
	fm.trigger("aux_power")
	var t := 0.0
	while t < 60.0 and absf(ph.v) > 0.02:
		ph.step(dt); fm._process(dt); t += dt
	ph.release_emergency()
	ph.speed_cmd = 1.0
	var s0: float = ph.s
	for i in range(60 * 20):
		ph.step(dt)
	ok = _check("perte 400 V : urgence relâchée, la rame ne repart pas (traction coupée)",
		ph.traction_coupee and absf(ph.v) < 0.05 and absf(ph.s - s0) < 0.5,
		"v=%.3f derive=%.2f m" % [ph.v, ph.s - s0]) and ok
	fm.clear_active()
	for i in range(60 * 20):
		ph.step(dt)
	ok = _check("400 V rétabli : la rame repart", not ph.traction_coupee and absf(ph.v) > 1.0,
		"v=%.2f" % ph.v) and ok

	# 6. Surchauffe : puissance déclassée à 55 % (plafond 8 m/s à part)
	ph = _make(1, 1200.0, 7.0)
	fm.physics = ph
	fm.trigger("thermal")
	ok = _check("surchauffe : déclassement 55 %", is_equal_approx(ph.power_derate, 0.55),
		"power_derate=%.2f" % ph.power_derate) and ok
	fm.clear_active()
	fm.trigger("motor_degraded")
	ok = _check("2/3 moteurs : déclassement 67 %", absf(ph.power_derate - 2.0 / 3.0) < 1e-6,
		"power_derate=%.3f" % ph.power_derate) and ok
	# levée à l'ARRIVÉE (durée 0, non catastrophique) — avant, jamais levée
	ph.finished = true
	fm._process(dt)
	ok = _check("2/3 moteurs : levée à l'arrivée", not fm.is_active(), "active=%s" % fm.is_active()) and ok

	# 7. Pic de tension : la jauge monte de 6 500 daN
	ph = _make(1, 1200.0, 8.0)
	fm.physics = ph
	for i in range(60 * 5):
		ph.step(dt)
	var t_avant: float = ph.tension_dan
	fm.trigger("tension")
	ph.step(dt)
	ok = _check("pic de tension : jauge +6 500 daN", absf(ph.tension_dan - t_avant - 6500.0) < 300.0,
		"%.0f → %.0f daN" % [t_avant, ph.tension_dan]) and ok
	fm.clear_active()

	# 8. Mou de câble : un coup de frein de service brutal déclenche
	# l'interrupteur de mou → urgence
	ph = _make(1, 1200.0, 10.0)
	fm.physics = ph
	fm.trigger("slack")
	ph.manual_brake_held = true
	for i in range(60 * 4):
		ph.step(dt)
	ok = _check("mou de câble + freinage brutal : interrupteur de mou → urgence", ph.emergency,
		"urgence=%s" % ph.emergency) and ok
	ph.manual_brake_held = false
	fm.clear_active()

	# 9. Défaut porte / inondation : OPÉRATIONNELS, pas d'arrêt d'urgence
	ph = _make(1, 1200.0, 10.0)
	fm.physics = ph
	fm.trigger("door")
	ph.step(dt)
	ok = _check("défaut porte : on continue (pas d'urgence), départ verrouillé",
		not ph.emergency and ph.panne_porte and is_equal_approx(fm.get_speed_cap(), PNConstants.V_MAX),
		"urgence=%s cap=%.0f" % [ph.emergency, fm.get_speed_cap()]) and ok
	fm.clear_active()
	fm.trigger("flood_tunnel")
	ok = _check("inondation : on continue au pas, plafond 4 m/s", not ph.emergency
		and is_equal_approx(fm.get_speed_cap(), 4.0), "cap=%.1f" % fm.get_speed_cap()) and ok
	fm.clear_active()

	# 10. Pas d'empilement : une 2e panne manuelle est refusée
	fm.trigger("wet_rail")
	ok = _check("pas d'empilement de pannes", not fm.trigger("thermal") and fm.get_active_id() == "wet_rail",
		fm.dernier_refus) and ok
	fm.clear_active()

	# 11. Catastrophe : LEVER refusé (R seulement), PRÊT/DÉPART refusé ;
	# séquence incident → lumières → évacuation à l'arrêt
	ph = _make(1, 1200.0, 10.0)
	fm.physics = ph
	fm.trigger("fire")
	fm.clear_active()
	ok = _check("feu : « lever » refusé sans R", fm.is_active() and fm.is_active_catastrophic(),
		fm.dernier_refus) and ok
	t = 0.0
	while t < 120.0 and fm.get_phase() != "out_of_service":
		ph.step(dt); fm._process(dt); t += dt
	ok = _check("feu : à l'arrêt, incident → lumières baissées → évacuation, cabine vidée",
		fm.get_phase() == "out_of_service" and not ph.lights_cabin and ph.pax() == 0
			and not ph.trip_started, "phase=%s lumières=%s pax=%d t=%.0f s"
			% [fm.get_phase(), ph.lights_cabin, ph.pax(), t]) and ok
	ph.speed_cmd = 1.0
	ok = _check("feu : PRÊT/DÉPART refusé", ph.request_depart() != "", "") and ok
	fm.clear_active(true)
	ok = _check("R : remise en service, lumières rallumées", not fm.is_active() and ph.lights_cabin, "") and ok

	# 12. Survitesse hors Défi : +20 % → urgence + parachute 3,6 m/s²
	ph = _make(-1, 2000.0, -14.5)
	ph.pax_car1 = 167
	ph.pax_car2 = 167
	ph.ghost_pax = 0
	var decel_pk := 0.0
	var v_prev: float = ph.v
	for i in range(60 * 30):
		ph.step(dt)
		decel_pk = maxf(decel_pk, (absf(v_prev) - absf(ph.v)) / dt)
		v_prev = ph.v
		if absf(ph.v) < 0.05:
			break
	ok = _check("survitesse +20 % hors Défi : parachute, arrêtée", ph.overspeed_level == 3
		and ph.parachute_engaged and absf(ph.v) < 0.05 and decel_pk > 2.0,
		"niveau=%d parachute=%s v=%.2f décél pic=%.2f" % [ph.overspeed_level, ph.parachute_engaged, ph.v, decel_pk]) and ok

	# 13. Collision au butoir hors Défi (mode normal) : rame décrochée en
	# descente, sans frein — elle dévale sur le butoir bas (en montée elle
	# s'arrêterait et redescendrait)
	ph = _make(-1, PNConstants.START_S + 60.0, -8.0)
	ph.speed_cmd = 1.0
	var crashes: Array = []      # (une lambda capture par valeur : tableau)
	ph.crash_occurred.connect(func(kind: String, _v: float) -> void: crashes.append(kind))
	ph.cable_rupture = true      # plus de retenue : elle file sur le butoir
	ph.ghost_locked_s = 3000.0
	for i in range(60 * 30):
		ph.step(dt)
		if ph.crashed:
			break
	ok = _check("butoir à pleine vitesse hors Défi : collision", crashes == ["buffer"] and ph.crashed,
		"crash=%s kind=%s v=%.1f" % [ph.crashed, ph.crash_kind, ph.crash_speed_ms]) and ok
	fm.free()
	return ok
