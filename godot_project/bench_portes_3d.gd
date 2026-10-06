## Banc portes (2026-09-27) : la séquence de départ de la PWA est en série
## (annonce 7,5 s → buzzer 7 s → clip 7 s → buzzer de quai 8 s → traction)
## et les vantaux partent 1,3 s après le début du clip.
##   godot --headless --path godot_project -s bench_portes_3d.gd
extends SceneTree


func _initialize() -> void:
	var ph := TrainPhysics.new()
	ph.direction = 1
	ph.s = PNConstants.START_S
	ph.doors_open = true
	ph.door_leaves_open = true
	ph.maint_brake = true
	ph.trip_started = false
	ph.request_depart()
	var dt := 1.0 / 60.0
	var t := 0.0
	var t_doors := -1.0
	var t_leaves := -1.0
	var t_trip := -1.0
	while t < 40.0 and t_trip < 0.0:
		ph.step(dt)
		t += dt
		if t_doors < 0.0 and not ph.doors_open:
			t_doors = t
		if t_leaves < 0.0 and not ph.door_leaves_open:
			t_leaves = t
		if t_trip < 0.0 and ph.trip_started:
			t_trip = t
	print("interlock fermé à %.2f s, vantaux partis à %.2f s, traction à %.2f s"
		% [t_doors, t_leaves, t_trip])
	var att_doors := TrainPhysics.ANNOUNCE_PHASE_S
	var att_leaves := att_doors + PNConstants.DOOR_BUZZER_S + PNConstants.DOOR_MOTION_LEAD
	var att_trip := att_doors + TrainPhysics.DOOR_PHASE_S + 8.0
	print("attendu : %.2f / %.2f / %.2f" % [att_doors, att_leaves, att_trip])
	var ok := absf(t_doors - att_doors) < 0.05 and absf(t_leaves - att_leaves) < 0.05 \
		and absf(t_trip - att_trip) < 0.05
	# réouverture à l'arrivée : les vantaux repartent 1,3 s après les portes
	ph.doors_open = true
	var t2 := 0.0
	var t_reopen := -1.0
	while t2 < 3.0 and t_reopen < 0.0:
		ph.step(dt)
		t2 += dt
		if ph.door_leaves_open:
			t_reopen = t2
	print("vantaux rouverts %.2f s après les portes (attendu %.2f)" % [t_reopen, PNConstants.DOOR_MOTION_LEAD])
	ok = ok and absf(t_reopen - PNConstants.DOOR_MOTION_LEAD) < 0.05
	# Sens du glissement (2026-09-27) : dans le MONDE, un vantail qui s'ouvre
	# part vers le BAS de la pente, quels que soient la rame et le sens de
	# marche — la caisse retournée (_xform_from) ne doit pas inverser ça.
	var tangent := Vector3(0.0, 0.0, -1.0)   # voie rectiligne, montée = −Z monde
	for ghost in [false, true]:
		for direction in [1, -1]:
			var cab := Cabin.new()
			cab.is_ghost = ghost
			var ph2 := TrainPhysics.new()
			ph2.direction = direction
			cab.physics = ph2
			var xf: Transform3D = cab._xform_from(Vector3.ZERO, tangent)
			var sgn: float = Cabin.door_slide_sign(direction, ghost)
			var d_world: Vector3 = xf.basis * Vector3(0.0, 0.0, sgn * TrainBodyBuilder.DOOR_SLIDE)
			var along: float = d_world.dot(tangent)     # > 0 = vers le haut
			var bas: bool = along < -0.5
			print("rame %d %s : vantail ouvert déplacé de %+.2f m le long de la montée → %s"
				% [2 if ghost else 1, "monte" if direction > 0 else "descend", along,
				"vers le BAS ✓" if bas else "vers le HAUT ✗"])
			ok = ok and bas
			cab.free()
	ok = _bouton_portes() and ok
	ok = _debarquement() and ok
	print("BENCH_PORTES " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)


func _verif(label: String, cond: bool, detail: String = "") -> bool:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	return cond


func _rame_a_quai() -> TrainPhysics:
	var ph := TrainPhysics.new()
	ph.direction = 1
	ph.s = PNConstants.START_S
	ph.s_prev_step = ph.s
	ph.doors_open = true
	ph.door_leaves_open = true
	ph.maint_brake = true
	ph.trip_started = false
	return ph


# Bouton PORTES de la PWA (06/10/2026) : fermeture sans départ, départ
# portes fermées = buzzer seul, verrous en marche et hors station.
func _bouton_portes() -> bool:
	var dt := 1.0 / 60.0
	var ok := true
	var ph := _rame_a_quai()
	ok = _verif("PORTES à quai : fermeture lancée", ph.toggle_doors() == "" and ph.announce_phase_remaining > 0.0) and ok
	var t := 0.0
	while t < 30.0:
		ph.step(dt)
		t += dt
	ok = _verif("fermeture seule : portes fermées, rame à quai, pas de buzzer",
		not ph.doors_open and not ph.trip_started and ph.departure_buzzer_remaining <= 0.0,
		"portes %s, buzzer %.1f s" % [ph.doors_open, ph.departure_buzzer_remaining]) and ok
	ph.request_depart()
	ok = _verif("PRÊT/DÉPART portes fermées : buzzer de quai seul (8 s en bas)",
		absf(ph.departure_buzzer_remaining - 8.0) < 1e-3 and ph.announce_phase_remaining <= 0.0) and ok
	t = 0.0
	while t < 9.0 and not ph.trip_started:
		ph.step(dt)
		t += dt
	ok = _verif("départ à la fin du buzzer", ph.trip_started, "%.1f s" % t) and ok
	# en marche : verrou
	ph.v = 3.0
	ok = _verif("en marche : portes verrouillées", ph.toggle_doors() != "" and not ph.doors_open) and ok
	# arrêt en plein tunnel : pas d'ouverture
	var pt := _rame_a_quai()
	pt.doors_open = false
	pt.s = 1500.0
	ok = _verif("hors station : ouverture refusée", pt.toggle_doors() != "" and not pt.doors_open) and ok
	# réouverture à quai, puis fermeture interrompue par PRÊT/DÉPART : on part
	var pr := _rame_a_quai()
	pr.doors_open = false
	ok = _verif("à quai, portes fermées : ouverture", pr.toggle_doors() == "" and pr.doors_open) and ok
	pr.toggle_doors()
	for i in range(60):
		pr.step(dt)
	pr.request_depart()
	t = 0.0
	while t < 40.0 and not pr.trip_started:
		pr.step(dt)
		t += dt
	ok = _verif("fermeture au bouton puis PRÊT/DÉPART : elle enchaîne sur le départ",
		pr.trip_started and not pr.doors_open, "%.1f s" % t) and ok
	return ok


# Arrivée : stabilisation, portes, TOUT LE MONDE DESCEND, puis la nouvelle
# charge monte (retour du 06/10/2026).
func _debarquement() -> bool:
	var dt := 1.0 / 60.0
	var ph := TrainPhysics.new()
	ph.direction = 1
	ph.pax_car1 = 150
	ph.pax_car2 = 140
	ph.pax_t_car1 = 150
	ph.pax_t_car2 = 140
	ph.s = PNConstants.STOP_S - 200.0
	ph.s_prev_step = ph.s
	ph.v = 6.0
	ph.doors_open = false
	ph.door_leaves_open = false
	ph.maint_brake = false
	ph.trip_started = true
	ph.speed_cmd = 0.5
	var t := 0.0
	var vide_vu := false
	var t_vide := -1.0
	var t_ouvert := -1.0
	var max_apres_vide := 0
	var compteur: float = -1.0
	while t < 200.0:
		ph.step(dt)
		t += dt
		if ph.finished and compteur < 0.0:
			compteur = PNConstants.distance_compteur(ph.s, ph.direction)
		if ph.doors_open and t_ouvert < 0.0:
			t_ouvert = t
		if t_ouvert > 0.0 and not vide_vu and ph.pax_car1 == 0 and ph.pax_car2 == 0:
			vide_vu = true
			t_vide = t
		if vide_vu:
			max_apres_vide = maxi(max_apres_vide, ph.pax_car1 + ph.pax_car2)
		if vide_vu and t > t_vide + 20.0:
			break
	var ok := _verif("compteur du pupitre à 3 474 m à l'arrivée (0 au départ)",
		roundf(compteur) == PNConstants.LENGTH
		and PNConstants.distance_compteur(PNConstants.START_S, 1) == 0.0,
		"%.1f m" % compteur)
	ok = _verif("arrivée en haut : portes ouvertes puis rame vidée", vide_vu,
		"ouverture à %.0f s, vide %.1f s après" % [t_ouvert, t_vide - t_ouvert]) and ok
	ok = _verif("puis embarquement de la descente (0 à 16 pax)", ph.direction < 0
		and ph.pax_car1 + ph.pax_car2 <= 16 and ph.pax_car1 == ph.pax_t_car1,
		"%d pax, cible %d" % [ph.pax_car1 + ph.pax_car2, ph.pax_t_car1 + ph.pax_t_car2]) and ok
	return ok
