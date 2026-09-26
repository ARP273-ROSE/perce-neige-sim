# Banc de PARITÉ PC ↔ PWA : voyages complets, mêmes cas que
# tests/bench_voyages.py. Sort des lignes CSV sur stdout (préfixe ROW,)
# que tests/parite_pwa.py confronte aux séries Python.
# Exécution : godot --headless --path godot_project -s bench_voyages_3d.gd
extends SceneTree


func _make(direction: int, pax: int, gpax: int) -> TrainPhysics:
	var ph := TrainPhysics.new()
	ph.direction = direction
	ph.s = PNConstants.START_S if direction > 0 else PNConstants.STOP_S
	ph.v = 0.0
	ph.speed_cmd = 1.0
	ph.speed_cmd_eff = 0.0
	ph.doors_open = false
	ph.maint_brake = false
	ph.trip_started = true
	ph.pax_car1 = pax / 2
	ph.pax_car2 = pax - pax / 2
	ph.ghost_pax = gpax
	return ph


func _voyage(nom: String, direction: int, pax: int, gpax: int) -> void:
	var ph := _make(direction, pax, gpax)
	var dt := 1.0 / 60.0
	var t := 0.0
	var next_log := 0.0
	var p_max := 0.0
	var r_max := 0.0
	var t_max := 0.0
	var e_trac := 0.0
	var e_regen := 0.0
	while not ph.finished and t < 900.0:
		ph.step(dt)
		t += dt
		e_trac += ph.power_kw * dt / 3600.0
		e_regen += ph.regen_kw * dt / 3600.0
		p_max = maxf(p_max, ph.power_kw)
		r_max = maxf(r_max, ph.regen_kw)
		t_max = maxf(t_max, ph.tension_dan)
		if t >= next_log:
			next_log += 0.5
			print("ROW,%s,%.3f,%.3f,%.3f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f" % [
				nom, t, ph.s, ph.ghost_s_phys(), ph.v, ph.power_kw,
				ph.regen_kw, ph.tension_dan, ph.throttle, ph.regen_level])
	print("SUM,%s,%s,%.0f,%.0f,%.0f,%.1f,%.1f,%.0f" % [
		nom, "oui" if ph.finished else "NON", t, p_max, r_max, e_trac,
		e_regen, t_max])


func _initialize() -> void:
	print("aero tube 12 m/s : %.0f N ; évitement : %.0f N ; galets : %.0f N ; câble s=26 : %.0f N" % [
		TrainPhysics.aero_drag_side_n(1000.0, 12.0),
		TrainPhysics.aero_drag_side_n(1700.0, 12.0),
		TrainPhysics.rope_rollers_n(),
		TrainPhysics.rope_weight_force_n(26.0)])
	_voyage("montee_vide_vide", 1, 0, 0)
	_voyage("montee_pleine_vide", 1, 334, 0)
	_voyage("descente_vide_pleine", -1, 0, 334)
	_voyage("descente_pleine_vide", -1, 334, 0)
	_voyage("montee_pleine_pleine", 1, 334, 334)
	quit(0)
