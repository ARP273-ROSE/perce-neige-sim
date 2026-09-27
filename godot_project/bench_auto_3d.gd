## Dry run PWA (2026-09-27) : exploitation automatique — arrivée puis départ,
## dans les DEUX sens ; journal des transitions portes / vantaux / trajet.
## v1.15.21 : les portes n'ouvrent qu'à la stabilisation du câble (enveloppe
## du rebond < 2 cm, 3 s mini, 30 s maxi) — on imprime l'attente et
## l'enveloppe à l'ouverture.
##   godot --headless --path godot_project -s bench_auto_3d.gd
extends SceneTree


func _initialize() -> void:
	for direction in [1, -1]:
		print("\n===== ARRIVÉE %s =====" % ("EN HAUT (montée)" if direction > 0 else "EN BAS (descente)"))
		_run(direction)
	quit(0)


func _run(direction: int) -> void:
	var ph := TrainPhysics.new()
	ph.direction = direction
	ph.s = (PNConstants.STOP_S - 300.0) if direction > 0 else (PNConstants.START_S + 300.0)
	ph.v = 12.0 * direction
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
	var t_arret := -1.0
	var excursion := 0.0
	while t < 420.0:
		ph.step(dt)
		ao._process(dt)
		t += dt
		if t_arret < 0.0 and ph.finished:
			t_arret = t
		if t_arret >= 0.0 and not ph.doors_open:
			excursion = maxf(excursion, absf(ph.rebound_offset()))
		var cur := "open=%s vantaux=%s trip=%s fin=%s etat=%d ann=%.0f porte=%.0f buzz=%.0f" % [
			ph.doors_open, ph.door_leaves_open, ph.trip_started, ph.finished, ao.state,
			ceilf(ph.announce_phase_remaining), ceilf(ph.door_phase_remaining), ceilf(ph.departure_buzzer_remaining)]
		if cur != prev:
			print("t=%6.1f s=%7.1f v=%5.2f | %s" % [t, ph.s, ph.v, cur])
			if ph.doors_open and prev != "" and not prev.begins_with("open=true"):
				print("   → portes ouvertes %.1f s après l'arrêt, enveloppe du rebond %.1f cm, excursion max vue %.1f cm"
					% [t - t_arret, ph.rebound_envelope() * 100.0, excursion * 100.0])
			prev = cur
		var parti_haut := direction > 0 and ph.s < PNConstants.STOP_S - 100.0
		var parti_bas := direction < 0 and ph.s > PNConstants.START_S + 100.0
		if ph.trip_started and t > 120.0 and (parti_haut or parti_bas):
			print("… reparti, fin du dry run")
			break
