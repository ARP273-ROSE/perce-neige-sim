## Carte des pistes au doigt (question d'utilisateur du 15/11/2026 : « le repositionnement en cliquant sur les
## points rouges de la carte ne marche plus, au moins sur la PWA ») : toucher simulé comme sur iPad (toucher
## + souris émulée), sur une remontée de la carte → le skieur est déposé à sa gare aval.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_carte_toucher_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _etat: int = 0
var _ok: bool = true
var _cible: LigneRemontee = null
var _p0: Vector3
var _n: int = 0
var _g: Vector2
const CAS: Array = [["doigt n° 0", 0], ["doigt Safari (n° 1234567)", 1234567], ["souris seule", -1]]
var _k: int = 0


func _initialize() -> void:
	Input.emulate_mouse_from_touch = true
	get_root().size = Vector2i(1920, 1080)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


## Comme Input le fait d'un doigt (emulate_mouse_from_touch) : la souris émulée d'abord, puis le toucher ;
## poussés au viewport (sans écran, Input ne les distribue pas).
func _toucher(pos: Vector2, appui: bool) -> void:
	var m: InputEventMouseButton = InputEventMouseButton.new()
	m.device = InputEvent.DEVICE_ID_EMULATION
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = pos
	m.global_position = pos
	m.pressed = appui
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if appui else 0
	if int(CAS[_k][1]) < 0:
		m.device = 0
		get_root().push_input(m, true)
		return
	get_root().push_input(m, true)
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = int(CAS[_k][1])
	t.position = pos
	t.pressed = appui
	get_root().push_input(t, true)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	if _t0 == 0:
		_t0 = _f
		# le menu de départ couvre l'écran (en jeu, on l'a fermé avant d'aller à ski)
		var scen: Node = _main.get_node_or_null("ScenarioPanel")
		if scen != null:
			scen.queue_free()
		_main.basculer_skieur()
		return
	if _f < _t0 + 120 or not _main.mode_skieur:
		return
	var cs = _main.commandes_skieur
	var carte: CartePistes = cs.carte
	match _etat:
		0:
			if cs._b_carte != null and not carte.is_visible_in_tree():
				cs._b_carte.button_pressed = true
				cs._b_carte.toggled.emit(true)
			carte.visible = true
			_n += 1
			if _n > 30:
				_etat = 1
		1:
			# la remontée la plus proche du centre de la carte, hors du skieur
			var c: Vector2 = carte._centre()
			var o: Vector2 = CartePistes.TAILLE * 0.5
			var best: float = 1e9
			var pos: Vector2
			for r in carte._remontees():
				var a: Vector2 = carte._carte(r[1], c, o)
				var dd: float = a.distance_to(o)
				if dd > 40.0 and dd < best and Rect2(Vector2(20, 20), CartePistes.TAILLE - Vector2(80, 40)).has_point(a):
					best = dd
					pos = a
					_cible = r[0]
			_verif("remontée visible sur la carte", _cible != null)
			if _cible == null:
				_fin()
				return
			_p0 = _main.skieur.global_position
			var g: Vector2 = carte.get_global_transform_with_canvas() * pos
			print("toucher ", _cible.name, " à ", g, " (carte ", carte.get_global_rect(), ")")
			var mm: InputEventMouseMotion = InputEventMouseMotion.new()
			mm.position = g
			mm.global_position = g
			mm.device = InputEvent.DEVICE_ID_EMULATION
			get_root().push_input(mm, true)
			_g = g
			_toucher(g, true)
			_n = 0
			_etat = 2
		2:
			_n += 1
			if _n == 2:
				var h: Control = get_root().gui_get_hovered_control()
				_verif("la carte est sous le doigt", h == carte, str(h.get_path()) if h != null else "rien")
			if _n == 4:
				var g2: Vector2 = carte.get_global_transform_with_canvas() * carte._carte(Vector2(_cible.global_transform.origin.x, _cible.global_transform.origin.z), carte._centre(), CartePistes.TAILLE * 0.5)
				_toucher(g2, false)
			if _n > 120:
				var q: Vector3 = _cible.global_transform.origin
				var d: float = Vector2(_main.skieur.global_position.x - q.x, _main.skieur.global_position.z - q.z).length()
				_verif(String(CAS[_k][0]) + " : la remontée touchée y dépose le skieur", d < 80.0, "%s : %.0f m de sa gare aval (déplacé de %.0f m)" % [_cible.name, d, _main.skieur.global_position.distance_to(_p0)])
				_k += 1
				if _k >= CAS.size():
					_fin()
				else:
					_cible = null
					_etat = 1


func _fin() -> void:
	_etat = 99
	print("BENCH_CARTE_TOUCHER " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


func _lister(n: Node, g: Vector2) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and (c as Control).get_global_rect().has_point(g):
			print("  couvre : ", c.get_path(), " filtre ", (c as Control).mouse_filter, " ", (c as Control).get_global_rect())
		_lister(c, g)
