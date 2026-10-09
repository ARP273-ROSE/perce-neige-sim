## Banc du pupitre de la vue cabine (06/10/2026) : la face est tournée vers
## l'œil du conducteur (à moins de 40° du regard), chaque commande se trouve au clic à l'endroit où on
## la voit, et les appuis agissent (portes, éclairage, klaxon, page de
## l'écran).
##   godot --headless --path godot_project -s bench_pupitre_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _tick() -> void:
	_f += 1
	var ph: TrainPhysics = _main.get("physics")
	if ph == null:
		return
	if _f >= 5 and _f <= 40:
		ph.direction = 1
		ph.s = PNConstants.START_S
		ph.s_prev_step = ph.s
		ph.v = 0.0
	if _f != 50:
		return
	var cab: Cabin = _main.get("cabin")
	cab.set_view(Cabin.ViewMode.FPV)
	var p: PupitreConduite = cab._pupitre
	var cam: Camera3D = cab.camera_fpv
	# 1. face perpendiculaire au regard
	var face: Node3D = p._face
	var n: Vector3 = face.global_transform.basis.y.normalized()
	var vers_oeil: Vector3 = (cam.global_position - face.global_position).normalized()
	var ecart: float = rad_to_deg(acos(clampf(n.dot(vers_oeil), -1.0, 1.0)))
	_verif("face tournée vers le regard, lisible", ecart < 40.0, "écart %.1f°, inclinaison %.1f°"
		% [ecart, rad_to_deg(p.inclinaison)])
	# 2. chaque commande se trouve là où on la voit
	var taille: Vector2 = get_root().get_visible_rect().size
	for nom in p._commandes:
		var noeud: Node3D = p._commandes[nom][1]
		var pe: Vector2 = cam.unproject_position(noeud.global_position)
		var dedans: bool = Rect2(Vector2.ZERO, taille).has_point(pe)
		var trouve: String = cab.pupitre_commande_sous(pe)
		var attendu: String = "vite_plus" if nom == "vite" else nom   # pile au centre : moitié droite
		_verif("commande %s" % nom, dedans and trouve == attendu,
			"(%.0f, %.0f) → « %s »" % [pe.x, pe.y, trouve])
	var ecran_mi: Node3D = face.get_node_or_null("EcranProface")
	var pe_ecran: Vector2 = cam.unproject_position(ecran_mi.global_position)
	_verif("écran", cab.pupitre_commande_sous(pe_ecran) == "ecran")
	_verif("rien hors du pupitre", cab.pupitre_commande_sous(Vector2(taille.x * 0.5, 5.0)) == "")
	# 3. actions
	var pos_de := func(nom: String) -> Vector2:
		return cam.unproject_position((p._commandes[nom][1] as Node3D).global_position)
	var lum: bool = ph.lights_cabin
	_main._pupitre_clic(pos_de.call("compartiment"), true)
	_main._pupitre_clic(pos_de.call("compartiment"), false)
	_verif("COMPARTIMENT bascule l'éclairage", ph.lights_cabin != lum)
	_main._pupitre_clic(pos_de.call("cabine"), true)
	_main._pupitre_clic(pos_de.call("cabine"), false)
	_verif("CABINE le rebascule", ph.lights_cabin == lum)
	_main._pupitre_clic(pos_de.call("klaxon"), true)
	var tenu: bool = ph.horn
	var y_enf: float = (p._commandes["klaxon"][1] as Node3D).position.y
	_main._pupitre_clic(pos_de.call("klaxon"), false)
	_verif("KLAXON tenu puis relâché", tenu and not ph.horn, "enfoncé à y = %.4f" % y_enf)
	var sel: Node3D = p._commandes["vite"][1]
	var c_sel: Vector2 = pos_de.call("vite")
	_main._pupitre_clic(c_sel - Vector2(12.0, 0.0), true)
	var tourne: float = sel.rotation.y
	var tient: bool = Input.is_action_pressed("speed_down")
	_main._pupitre_clic(c_sel - Vector2(12.0, 0.0), false)
	_verif("−VITE : tourné à gauche tant qu'on le tient, consigne en baisse", tourne > 0.3 and tient
		and sel.rotation.y == 0.0 and not Input.is_action_pressed("speed_down"))
	_main._pupitre_clic(c_sel + Vector2(12.0, 0.0), true)
	tourne = sel.rotation.y
	tient = Input.is_action_pressed("speed_up")
	_main._pupitre_clic(c_sel + Vector2(12.0, 0.0), false)
	_verif("+VITE : tourné à droite, consigne en hausse, rappel à la verticale", tourne < -0.3 and tient
		and sel.rotation.y == 0.0)
	_verif("PRÊT n'est pas un bouton", not p._commandes.has("pret"))
	_main._pupitre_clic(pos_de.call("marche"), true)
	_main._pupitre_clic(pos_de.call("marche"), false)
	var coupe: bool = not p.en_marche
	_main._pupitre_clic(pos_de.call("montee"), true)
	var refuse: bool = not Input.is_action_pressed("ready_depart")
	_main._pupitre_clic(pos_de.call("montee"), false)
	_main._pupitre_clic(pos_de.call("marche"), true)
	_main._pupitre_clic(pos_de.call("marche"), false)
	_verif("EN MARCHE coupe le pupitre et refuse MONTÉE, puis le remet", coupe and refuse and p.en_marche)
	var page: bool = p.ecran.page_portes
	_main._pupitre_clic(pe_ecran, true)
	_main._pupitre_clic(pe_ecran, false)
	p.mettre_a_jour(ph, 0.0, 1, true)
	_verif("appui sur l'écran : change de page", p.ecran.page_portes != page)
	# portes par côté : 1 à 6 à gauche en regardant vers le haut, 7 à 12 à
	# droite ; dans les deux sens de marche, seules les bonnes bougent
	for sens in [1, -1]:
		ph.direction = sens
		ph.doors_open = true
		ph.door_leaves_open = true
		ph.portes_cotes = 1
		for k in range(8):
			cab._process(1.0)
		var xf: Transform3D = _main.tunnel.transform_at(ph.s)
		var haut: Vector3 = (_main.tunnel.transform_at(ph.s + 5.0).origin - xf.origin).normalized()
		var gauche: Vector3 = Vector3.UP.cross(haut)
		var bonnes: int = 0
		var fausses: int = 0
		for d in cab._doors:
			var cote_g: bool = (cab.global_transform.basis * Vector3(float(d["side"]), 0.0, 0.0)).dot(gauche) > 0.0
			var ouverte: bool = ((d["node"] as Node3D).position - (d["base"] as Vector3)).length() > 0.05
			if ouverte == cote_g:
				bonnes += 1
			else:
				fausses += 1
		_verif("rame %s : PORTES 1 à 6 ouvre le côté GAUCHE (vers le haut) seul"
			% ("montante" if sens > 0 else "descendante"), fausses == 0 and bonnes > 0,
			"%d bonnes, %d fausses" % [bonnes, fausses])
	ph.direction = 1
	ph.portes_cotes = 3
	ph.doors_open = true
	_main._pupitre_clic(pos_de.call("fermeture_0"), true)
	_main._pupitre_clic(pos_de.call("fermeture_0"), false)
	var un_cote: bool = ph.doors_open and ph.portes_cotes == 2 and ph.announce_phase_remaining <= 0.0
	_main._pupitre_clic(pos_de.call("fermeture_1"), true)
	_main._pupitre_clic(pos_de.call("fermeture_1"), false)
	_verif("FERMETURE 1 à 6 ferme la gauche seule, 7 à 12 lance la fermeture",
		un_cote and ph.announce_phase_remaining > 0.0)
	_main._pupitre_clic(pos_de.call("montee"), true)
	var tient_depart: bool = Input.is_action_pressed("ready_depart")
	_main._pupitre_clic(pos_de.call("montee"), false)
	_verif("MONTÉE lance le départ", tient_depart)
	# coups-de-poing : URGENCE (gros) et ARRÊT ÉLEC (petit)
	_main._pupitre_clic(pos_de.call("rouge_1"), true)
	var urg: bool = Input.is_action_pressed("emergency")
	_main._pupitre_clic(pos_de.call("rouge_1"), false)
	_verif("URGENCE (gros coup-de-poing) déclenche l'arrêt d'urgence", urg)
	_main._pupitre_clic(pos_de.call("rouge_2"), true)
	_main._pupitre_clic(pos_de.call("rouge_2"), false)
	var elec: bool = ph.arret_elec
	_main._pupitre_clic(pos_de.call("rouge_2"), true)
	_main._pupitre_clic(pos_de.call("rouge_2"), false)
	_verif("ARRÊT ÉLEC (petit) s'engage puis se relâche", elec and not ph.arret_elec)
	_arret_elec_physique()
	# inversion du sens : à quai, demi-tour normal et silencieux ; en plein
	# tunnel, annonce « retour en gare » (comme le PC)
	var ann: Node = _main.get("announcements")
	if ann != null:
		ph.arret_elec = false
		ph.emergency = false
		ph.s = PNConstants.STOP_S
		ph.v = 0.0
		ann.stop_all()
		_main.do_reverse()
		var silence: bool = not ann.is_announcing()
		ph.s = 1500.0
		ph.v = 0.0
		_main.do_reverse()
		var annonce: bool = ann.is_announcing()
		_verif("inversion à quai silencieuse, en plein tunnel annoncée", silence and annonce)
	# gare aval : les portes coulissantes de la cloison s'ouvrent pendant
	# l'embarquement, se referment au départ
	var halls: StationHalls = _main.get("station_halls")
	if halls != null and halls.gare_aval != null:
		var ga: GareAval = halls.gare_aval
		ph.s = PNConstants.START_S
		ph.direction = 1
		ph.v = 0.0
		ph.trip_started = false
		ph.doors_open = true
		for k in range(6):
			ga.mettre_a_jour(0.5, ph)
		# un seul vantail par porte, qui coulisse vers le MILIEU de la salle
		# (retour d'utilisateur, 07/10/2026) : celui de l'ouest (x < 0) vers l'est, celui de
		# l'est vers l'ouest
		var vers_milieu: bool = true
		var ouvert: float = INF
		for i in range(ga._vantaux.size()):
			var c: float = ga.course_vantail(i)
			ouvert = minf(ouvert, absf(c))
			if signf(c) != -signf(float(ga._vantaux[i][1])):
				vers_milieu = false
		ph.trip_started = true
		ph.doors_open = false
		for k in range(6):
			ga.mettre_a_jour(0.5, ph)
		var ferme: float = absf(ga.course_vantail(0)) + absf(ga.course_vantail(1))
		_verif("gare aval : un vantail par porte, tout le passage libre vers le milieu à l'embarquement, fermé au départ",
			ga._vantaux.size() == 2 and vers_milieu and ouvert > 2.0 and ferme < 0.01,
			"course %.2f m puis %.2f m" % [ouvert, ferme])
		# vraie séquence (retour d'utilisateur : « ferme-les avant le départ, ouvre-les
		# après l'arrivée ») : rame à quai portes ouvertes → séquence de
		# départ → elles sont fermées AVANT que la traction ne parte
		var ph2 := TrainPhysics.new()
		ph2.direction = 1
		ph2.s = PNConstants.START_S
		ph2.doors_open = true
		ph2.door_leaves_open = true
		ph2.maint_brake = true
		ph2.trip_started = false
		ph2.speed_cmd = 1.0     # PRÊT/DÉPART refuse une consigne à 0 (07/10/2026, parité PC)
		for k in range(8):
			ga.mettre_a_jour(0.5, ph2)
		var ouv0: float = absf(ga.course_vantail(0))
		ph2.request_depart()
		var t_ferme: float = -1.0
		var t_dep: float = -1.0
		var t: float = 0.0
		while t < 40.0 and t_dep < 0.0:
			ph2.step(1.0 / 30.0)
			ga.mettre_a_jour(1.0 / 30.0, ph2)
			t += 1.0 / 30.0
			var o: float = absf(ga.course_vantail(0))
			if t_ferme < 0.0 and o < 0.01:
				t_ferme = t
			if ph2.trip_started:
				t_dep = t
		_verif("gare aval : portes de la salle fermées avant le départ", ouv0 > 2.0 and t_ferme > 0.0
			and t_ferme < t_dep, "fermées à %.1f s, départ à %.1f s" % [t_ferme, t_dep])
		_verif("gare aval : panneau des départs renseigné", (ga._panneau[1] as Label3D).text.contains("FUNICULA"))
	print("BENCH_PUPITRE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


## Arrêt électrique en ligne (port du PC) : de 12 m/s, la consigne redescend
## à 0,45 m/s² → arrêt doux en ≈ 27 s, sans frein d'urgence ; départ refusé.
func _arret_elec_physique() -> void:
	var ph := TrainPhysics.new()
	ph.direction = 1
	ph.s = 600.0
	ph.s_prev_step = 600.0
	ph.trip_started = true
	ph.doors_open = false
	ph.door_leaves_open = false
	ph.maint_brake = false
	ph.speed_cmd = 1.0
	var dt := 1.0 / 60.0
	for k in range(60 * 60):
		ph.step(dt)
	var v0: float = absf(ph.v)
	ph.arret_elec = true
	var t := 0.0
	var a_max := 0.0
	var v_prec: float = v0
	while absf(ph.v) > 0.05 and t < 120.0:
		ph.step(dt)
		t += dt
		if absf(ph.v) > 0.15:          # (immobilisation : frein de maintien)
			a_max = maxf(a_max, (v_prec - absf(ph.v)) / dt)
		v_prec = absf(ph.v)
	_verif("ARRÊT ÉLEC à %.1f m/s : arrêt en %.1f s (≈ %.0f s attendues), décélération maxi %.2f m/s²"
		% [v0, t, v0 / 0.45, a_max], absf(t - v0 / 0.45) < 6.0 and a_max < 1.0 and not ph.emergency)
	ph.trip_started = false
	ph.request_depart()
	_verif("départ refusé tant que l'arrêt électrique est engagé",
		ph.announce_phase_remaining <= 0.0 and ph.departure_buzzer_remaining <= 0.0)
