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
	print("BENCH_PORTES " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)
