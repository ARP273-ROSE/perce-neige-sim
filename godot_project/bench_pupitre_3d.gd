## Banc du pupitre de la vue cabine (06/10/2026) : la face est tournée vers
## l'œil du conducteur, chaque commande se trouve au clic à l'endroit où on
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
	_verif("face perpendiculaire au regard", ecart < 3.0, "écart %.1f°, inclinaison %.1f°"
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
	var ouvertes: bool = ph.doors_open
	if ouvertes:
		_main._pupitre_clic(pos_de.call("fermeture_0"), true)
		_main._pupitre_clic(pos_de.call("fermeture_0"), false)
		_verif("FERMETURE lance la fermeture", ph.announce_phase_remaining > 0.0)
	else:
		_main._pupitre_clic(pos_de.call("ouverture_1"), true)
		_main._pupitre_clic(pos_de.call("ouverture_1"), false)
		_verif("OUVERTURE ouvre à quai", ph.doors_open)
	_main._pupitre_clic(pos_de.call("montee"), true)
	var tient_depart: bool = Input.is_action_pressed("ready_depart")
	_main._pupitre_clic(pos_de.call("montee"), false)
	_verif("MONTÉE lance le départ", tient_depart)
	print("BENCH_PUPITRE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
