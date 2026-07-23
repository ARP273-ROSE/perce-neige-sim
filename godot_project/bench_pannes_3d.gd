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

	# 3. abt_hold : la rame doit s'arrêter AVANT PASSING_START (1611)
	ph = _make(1, 1300.0, 8.0)
	ph.abt_hold = true
	ph.speed_cap_external = 4.0
	r = _run(ph, 240.0)
	print("abt_hold : arrêt à s=%.0f v=%.2f (aiguillage à 1611)"
		% [r["s"], r["v"]])
	if r["s"] > 1611.0 - 5.0 or absf(r["v"]) > 0.5:
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

	print("BENCH_3D " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)
