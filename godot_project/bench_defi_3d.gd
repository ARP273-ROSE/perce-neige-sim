# Banc headless du mode DÉFI (chaos) et du mode PANNES côté 3D/web.
# Exécution : godot --headless --path godot_project -s bench_defi_3d.gd
#
# Vérifie, sans rendu :
#   1. consigne à fond en Défi → la rame DÉPASSE V_MAX (surrégime moteur) ;
#   2. la même consigne en mode normal reste plafonnée à ~12 m/s ;
#   3. arrivée trop rapide au butoir → collision (crash_occurred, kind
#      "buffer") ;
#   4. survitesse > +20 % → câble rompu + frein de service dégradé ;
#   5. franchissement de l'évitement > 13,5 m/s → déraillement ;
#   6. en Défi, consigne 0 sans frein → la rame N'EST PAS maintenue ;
#   7. arrêt propre au repère → score élevé ; arrêt à 3 m → score plus bas.
extends SceneTree

var _crashes: Array = []


func _make(challenge: bool, direction: int, s0: float, v0: float) -> TrainPhysics:
	var ph := TrainPhysics.new()
	ph.challenge_mode = challenge
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
	ph.crash_occurred.connect(func(kind: String, speed: float) -> void:
		_crashes.append({"kind": kind, "speed": speed}))
	return ph


func _run(ph: TrainPhysics, t_max: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var t := 0.0
	var v_pk := 0.0
	while t < t_max:
		ph.step(dt)
		v_pk = maxf(v_pk, absf(ph.v))
		t += dt
		if ph.crashed:
			break
	return {"v": ph.v, "s": ph.s, "t": t, "v_pk": v_pk}


func _check(label: String, cond: bool, detail: String) -> bool:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	return cond


func _initialize() -> void:
	var ok := true

	# 1. Surrégime en Défi : consigne à fond dépasse V_MAX
	var ph := _make(true, 1, 600.0, 8.0)
	var r := _run(ph, 90.0)
	ok = _check("defi surregime", r["v_pk"] > PNConstants.V_MAX + 0.5,
		"v_pk=%.2f (attendu > %.1f)" % [r["v_pk"], PNConstants.V_MAX]) and ok

	# 2. Mode normal : plafonné à V_MAX
	_crashes.clear()
	ph = _make(false, 1, 600.0, 8.0)
	r = _run(ph, 60.0)
	ok = _check("normal plafonne", r["v_pk"] <= PNConstants.V_MAX + 0.4,
		"v_pk=%.2f" % r["v_pk"]) and ok

	# 3. Collision au butoir : arrivée à pleine vitesse, aucun freinage
	_crashes.clear()
	ph = _make(true, 1, PNConstants.STOP_S - 220.0, 10.0)
	r = _run(ph, 60.0)
	var hit_buffer: bool = _crashes.size() > 0 and str(_crashes[0]["kind"]) == "buffer"
	ok = _check("collision butoir", hit_buffer,
		"crashes=%s s=%.1f" % [str(_crashes), r["s"]]) and ok

	# 4. Cascade de survitesse : +20 % → câble rompu
	_crashes.clear()
	ph = _make(true, -1, 2600.0, -12.0)   # descente chargée, consigne pleine
	ph.pax_car1 = 160
	ph.pax_car2 = 160
	ph.ghost_pax = 4
	r = _run(ph, 120.0)
	ok = _check("cascade survitesse", ph.cable_rupture and ph.service_brake_fail < 0.5,
		"rupture=%s frein=%.2f v_pk=%.2f" % [ph.cable_rupture,
			ph.service_brake_fail, r["v_pk"]]) and ok

	# 5. Déraillement à l'évitement au-delà de 13,5 m/s
	_crashes.clear()
	ph = _make(true, 1, PNConstants.PASSING_START - 5.0, 14.0)
	r = _run(ph, 10.0)
	var derailed: bool = _crashes.size() > 0 and str(_crashes[0]["kind"]) == "derail"
	ok = _check("deraillement Abt", derailed, "crashes=%s" % str(_crashes)) and ok

	# 6. Consigne 0 sans frein en Défi : la rame n'est PAS maintenue
	_crashes.clear()
	ph = _make(true, 1, 900.0, 0.0)
	ph.speed_cmd = 0.0
	ph.speed_cmd_eff = 0.0
	r = _run(ph, 25.0)
	ok = _check("defi pas de maintien", absf(r["v"]) > 0.5,
		"v=%.2f apres 25 s consigne 0" % r["v"]) and ok

	# 7. Notation : le score chute avec l'écart au repère
	var s_perfect := _score(0.05, 0.0, false, false, false)
	var s_off := _score(3.0, 0.0, false, false, false)
	var s_emerg := _score(0.05, 0.0, true, false, false)
	ok = _check("score precision", s_perfect > s_off + 30.0,
		"pile=%.1f, 3 m=%.1f" % [s_perfect, s_off]) and ok
	ok = _check("score urgence", s_emerg < s_perfect - 10.0,
		"sans urgence=%.1f, avec=%.1f" % [s_perfect, s_emerg]) and ok

	ok = _test_pannes() and ok

	print("\n%s" % ["TOUS LES TESTS PASSENT" if ok else "ECHECS — voir ci-dessus"])
	quit(0 if ok else 1)


# Reproduit la formule de notation de Challenge (0,40 confort + 0,35
# précision + 0,25 régularité) sans instancier de Node.
func _score(err: float, jerk: float, emerg: bool, fault: bool,
		unsafe: bool) -> float:
	var precision := clampf(100.0 * (1.0 - (err - 0.10) / 1.90), 0.0, 100.0)
	var reg := 100.0
	if emerg:
		reg -= 60.0
	if fault:
		reg -= 40.0
	if unsafe:
		reg -= 50.0
	reg = maxf(0.0, reg)
	var comfort := maxf(0.0, 100.0 - jerk)
	return 0.40 * comfort + 0.35 * precision + 0.25 * reg


# --- Mode PANNES : profils, effets physiques, planificateur --------------
func _test_pannes() -> bool:
	var ok := true
	var fm := FaultManager.new()
	var ph := _make(false, 1, 1200.0, 9.0)
	fm.physics = ph
	fm.lang = "fr"

	# a. Chaque panne a bien un profil complet (quoi / que faire / bloqué)
	var missing: Array = []
	for fid: String in FaultProfiles.ORDER:
		for field: String in ["what", "do", "blocked"]:
			if FaultProfiles.get_field(fid, field, "fr") == "" \
					or FaultProfiles.get_field(fid, field, "en") == "":
				missing.append("%s/%s" % [fid, field])
	ok = _check("profils complets", missing.is_empty(),
		"manquants=%s (15 pannes x 3 champs x 2 langues)" % str(missing)) and ok

	# b. Une panne à plafond borne bien la vitesse
	fm.trigger("wet_rail")
	ok = _check("plafond de panne", is_equal_approx(fm.get_speed_cap(), 6.0),
		"wet_rail cap=%.1f m/s, texte=\"%s\"" % [fm.get_speed_cap(),
			fm.get_active_do().substr(0, 40)]) and ok
	fm.clear_active()

	# c. Rupture de câble : effets mécaniques posés sur la physique
	fm.trigger("cable_rupture")
	ok = _check("rupture cable", ph.cable_rupture and ph.service_brake_fail < 0.5
			and ph.ghost_locked_s >= 0.0,
		"rupture=%s frein=%.2f ghost_fige=%.0f m" % [ph.cable_rupture,
			ph.service_brake_fail, ph.ghost_locked_s]) and ok
	fm.clear_active()
	ok = _check("levee de panne", not ph.cable_rupture
			and is_equal_approx(ph.service_brake_fail, 1.0)
			and ph.ghost_locked_s < 0.0, "etat rendu nominal") and ok

	# d. Planificateur : ~1 panne / 5-6 min, jamais à quai
	fm.scheduler_enabled = true
	fm._cooldown = 0.0
	ph.trip_started = false
	for i in range(600):
		fm._scheduler_tick(1.0 / 60.0)
	ok = _check("pas de panne a quai", not fm.is_active(),
		"trip_started=false pendant 10 s") and ok

	ph.trip_started = true
	var triggers := 0
	var minutes := 0.0
	for i in range(60 * 60 * 30):          # 30 minutes simulées
		fm._scheduler_tick(1.0 / 60.0)
		minutes += 1.0 / 3600.0
		if fm.is_active():
			triggers += 1
			fm.clear_active()
			fm._cooldown = FaultManager.COOLDOWN_S
	ok = _check("frequence des pannes", triggers >= 1 and triggers <= 12,
		"%d incidents en 30 min (attendu 3-8)" % triggers) and ok
	fm.free()
	return ok
