# Banc de la rupture du câble (2026-10-01) — retour de Kevin : « quand le
# câble casse, il doit se détendre, casser quelque part et la machinerie
# doit s'arrêter, là elle s'emballe ». Vraie scène, pas fixe de 1/60 s,
# rame lancée en montée à 10 m/s :
#   A. panne « cable_rupture » (parachute serré) : la rame est retenue ;
#   B. rupture sans urgence (mode Défi) : la rame repart en arrière et
#      traîne son bout de câble.
#   godot --headless --path godot_project -s bench_rupture_3d.gd -- --mode=normal
extends SceneTree

const DT: float = 1.0 / 60.0

var _main: Node = null
var _f: int = 0
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _check(label: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	_ok = _ok and cond


func _pas(n: int) -> void:
	for i in range(n):
		_main._process(DT)


func _param(m: ShaderMaterial, nom: String) -> float:
	var v: Variant = m.get_shader_parameter(nom)
	if v == null:      # jamais posé : valeur par défaut du shader
		return {"gap_lo": -1.0, "gap_hi": -1.0, "slack": 0.0}.get(nom, 0.0)
	return float(v)


func _lancer(ph: TrainPhysics) -> void:
	ph.s = 800.0
	ph.s_prev_step = 800.0
	ph.direction = 1
	ph.v = 10.0
	ph.trip_started = true
	ph.doors_open = false
	ph.door_leaves_open = false
	ph.maint_brake = false
	ph.emergency = false
	ph.speed_cmd = 1.0
	_pas(30)


func _tick() -> void:
	_f += 1
	if _f < 5:
		return
	process_frame.disconnect(_tick)
	_main.set_process(false)
	var ph: TrainPhysics = _main.physics
	var track: TrackBuilder = _main.track
	var mr: MachineRoomBuilder = _main.machine_room
	var fm: FaultManager = _main.fault_manager
	# --- A. panne « cable_rupture » en pleine montée ----------------------
	_lancer(ph)
	var own: ShaderMaterial = track.cable_left_material
	var other: ShaderMaterial = track.cable_right_material
	_check("câble intact avant la rupture", _param(own, "gap_hi") <= _param(own, "gap_lo")
		and _param(own, "slack") == 0.0 and absf(ph.machine_v - ph.v) < 1e-6,
		"machinerie %.2f m/s, rame %.2f m/s" % [ph.machine_v, ph.v])

	fm.trigger("cable_rupture")
	var s_rupt: float = ph.s
	var mv0: float = ph.machine_v
	_pas(1)
	var ghost0: float = ph.ghost_s_render()
	var phase_autre0: float = _param(other, "cable_phase")
	var r: Dictionary = track.cable_rupture_state()
	_check("rupture sur le brin de la rame, devant elle", not r.is_empty()
		and float(r.s_b) > s_rupt + 20.0 and float(r.s_b) < s_rupt + 90.0,
		"brèche à s = %.1f m, rame à %.1f m" % [float(r.get("s_b", -1.0)), s_rupt])
	_pas(17)    # 0,3 s : chute du câble terminée
	_check("câble détendu sur la longrine (les deux brins)", _param(own, "slack") > 0.999
		and _param(other, "slack") > 0.999, "slack %.3f / %.3f" % [_param(own, "slack"), _param(other, "slack")])
	var gap0: float = _param(own, "gap_hi") - _param(own, "gap_lo")
	# la rame file encore et pousse son tronçon : il bute à 60 cm du bout haut
	_check("bouts séparés (poussé, le tronçon bute à 60 cm)",
		gap0 > TrackBuilder.RUPTURE_GAP_MIN_M - 1e-3, "brèche %.2f m après 0,3 s" % gap0)

	# la machinerie freine jusqu'à l'arrêt, quoi que fasse la rame
	var t_arret: float = -1.0
	var v_max_mach: float = absf(ph.machine_v)
	var angle_prec: float = mr._angle
	for i in range(int(20.0 / DT)):
		_pas(1)
		v_max_mach = maxf(v_max_mach, absf(ph.machine_v))
		if t_arret < 0.0 and absf(ph.machine_v) < 1e-6:
			t_arret = float(i + 18) * DT
	var t_theo: float = absf(mv0) / PNConstants.A_DRIVE_TRIP
	_check("la machinerie ne s'emballe pas", v_max_mach <= absf(mv0) + 1e-6,
		"maximum %.2f m/s (à la rupture %.2f)" % [v_max_mach, mv0])
	_check("la machinerie s'arrête", t_arret > 0.0 and absf(t_arret - t_theo) < 0.2,
		"arrêt en %.2f s (théorie v/a = %.2f s)" % [t_arret, t_theo])
	angle_prec = mr._angle
	_pas(30)
	_check("roues immobiles ensuite", absf(mr._angle - angle_prec) < 1e-9,
		"Δangle %.9f rad en 0,5 s" % absf(mr._angle - angle_prec))
	_check("rame d'en face figée", absf(ph.ghost_s_render() - ghost0) < 1e-6,
		"%.2f → %.2f m" % [ghost0, ph.ghost_s_render()])
	_check("son brin ne défile plus", absf(_param(other, "cable_phase") - phase_autre0) < 1e-3,
		"phase %.2f → %.2f" % [phase_autre0, _param(other, "cable_phase")])
	# la rame a continué de monter sur son élan avant d'être tenue : son
	# tronçon de câble a avancé avec elle (jusqu'au bout haut au plus)
	var lo_att: float = minf(float(r.s_b) - float(r.r_lo) + (ph.s_render - float(r.s0)),
		_param(own, "gap_hi") - TrackBuilder.RUPTURE_GAP_MIN_M)
	_check("rame retenue, son bout de câble a avancé avec elle", absf(ph.v) < 0.05
		and absf(_param(own, "gap_lo") - lo_att) < 0.05 and ph.s > s_rupt + 1.0,
		"rame %.1f → %.1f m, bout bas %.2f m (attendu %.2f)" % [s_rupt, ph.s,
			_param(own, "gap_lo"), lo_att])
	_check("câble de la salle des machines détendu", mr._slack_mr > 0.999
		and float(mr._cable_mat.get_shader_parameter("slack")) > 0.999,
		"slack %.3f" % mr._slack_mr)
	_check("bout haut immobile sur les roues", absf(_param(own, "phase_upper")
		- (float(r.ph0) + float(r.r_up))) < 1e-3, "phase %.3f" % _param(own, "phase_upper"))

	# fin de la panne (maintenance, nouveau voyage) : câble rétabli
	fm.clear_active()
	_pas(2)
	_check("câble rétabli après la panne", track.cable_rupture_state().is_empty()
		and _param(own, "slack") == 0.0 and _param(own, "gap_hi") <= _param(own, "gap_lo")
		and mr._slack_mr == 0.0,
		"slack %.1f, brèche [%.1f, %.1f]" % [_param(own, "slack"), _param(own, "gap_lo"), _param(own, "gap_hi")])

	# --- B. rupture sans urgence (Défi) : la rame repart en arrière -----
	_lancer(ph)
	ph.challenge_mode = true     # comme en Défi : pas de plafond de confort
	ph.cable_rupture = true
	ph.ghost_locked_s = PNConstants.LENGTH - ph.s
	# position RÉELLE de la rame (poulie + écart élastique du câble, 04/10)
	var s0b: float = ph.s + ph.el_x1
	_pas(1)
	var rb: Dictionary = track.cable_rupture_state()
	var lo_ini: float = float(rb.s_b)
	var s_max: float = ph.s
	var lo_max: float = -1.0
	var ecart_min: float = INF
	for i in range(int(12.0 / DT)):
		_pas(1)
		s_max = maxf(s_max, ph.s)
		lo_max = maxf(lo_max, _param(own, "gap_lo"))
		ecart_min = minf(ecart_min, _param(own, "gap_hi") - _param(own, "gap_lo"))
	var recul: float = s0b - ph.s
	var lo_b: float = _param(own, "gap_lo")
	_check("rame décrochée qui dévale", recul > 30.0 and ph.v < -5.0,
		"monte jusqu'à %.1f m puis redescend à %.1f m (%.1f m/s)" % [s_max, ph.s, ph.v])
	_check("le bout bas avance avec la rame sur son élan, sans passer le bout haut",
		lo_max > lo_ini + 0.5 and ecart_min > TrackBuilder.RUPTURE_GAP_MIN_M - 1e-3,
		"bout bas jusqu'à %.1f m (+%.1f, rame +%.1f m), écart mini %.2f m" % [lo_max,
			lo_max - lo_ini, s_max - s0b, ecart_min])
	_check("le bout bas suit la rame qui recule", absf((lo_ini - lo_b) - recul) < float(rb.r_lo) + 0.1,
		"bout bas %.1f → %.1f m (recul de la rame %.1f m)" % [lo_ini, lo_b, recul])
	_check("machinerie arrêtée malgré la rame qui dévale", absf(ph.machine_v) < 1e-6,
		"%.3f m/s, rame à %.1f m/s" % [ph.machine_v, ph.v])
	ph.cable_rupture = false
	ph.challenge_mode = false
	ph.ghost_locked_s = -1.0
	_pas(1)
	print("BENCH_RUPTURE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
