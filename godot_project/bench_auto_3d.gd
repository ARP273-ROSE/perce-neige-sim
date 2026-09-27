## Dry run PWA (2026-09-27) : exploitation automatique — arrivée en haut puis
## départ ; journal des transitions portes / vantaux / trajet.
##   godot --headless --path godot_project -s bench_auto_3d.gd
extends SceneTree


func _initialize() -> void:
	var ph := TrainPhysics.new()
	ph.direction = 1
	ph.s = PNConstants.STOP_S - 300.0
	ph.v = 12.0
	ph.doors_open = false
	ph.door_leaves_open = false
	ph.maint_brake = false
	ph.trip_started = true
	ph.speed_cmd = 1.0
	var ao := AutoOperator.new()
	ao.set_physics(ph)
	ao.enabled = true
	ao._enter_initial_state()
	var dt := 1.0 / 60.0
	var t := 0.0
	var prev := ""
	while t < 420.0:
		ph.step(dt)
		ao._process(dt)
		t += dt
		var cur := "open=%s vantaux=%s trip=%s fin=%s etat=%d ann=%.0f porte=%.0f buzz=%.0f" % [
			ph.doors_open, ph.door_leaves_open, ph.trip_started, ph.finished, ao.state,
			ceilf(ph.announce_phase_remaining), ceilf(ph.door_phase_remaining), ceilf(ph.departure_buzzer_remaining)]
		if cur != prev:
			print("t=%6.1f s=%7.1f v=%5.2f | %s" % [t, ph.s, ph.v, cur])
			prev = cur
		if ph.trip_started and t > 120.0 and ph.s < PNConstants.STOP_S - 100.0:
			print("… reparti en descente, fin du dry run")
			break
	quit(0)
