## Captures des remontées dont le nom contient un filtre (vue d'ensemble, gare aval, pylône, gare amont),
## chacune construite sur place (aller_a_remontee) : rendu réel, relief, forêt.
##   godot --path godot_project --resolution 1920x1080 -s shot_filtre_remontees.gd -- --filtre=tkd préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _pre: String = "/tmp/rf"
var _filtre: String = "tkd"
var _cam: Camera3D
var _lignes: Array = []
var _k: int = 0
var _etat: int = 0
var _att: int = 0
var _vues: Array = []
var _i: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filtre="):
			_filtre = a.substr(9)
		elif not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _vues_de(lg: LigneRemontee) -> Array:
	var xf: Transform3D = lg.global_transform
	var L: float = lg.longueur_h()
	var n: String = String(lg.name)
	var v: Array = []
	var c3: Vector3 = xf * Vector3(0, lg.terrain(8.0) + 2.5, -8.0)
	v.append([n + "_gare_aval", xf * Vector3(-14, lg.terrain(-12.0) + 5.0, 12.0), c3])
	var d: float = float(lg.pylones[mini(1, lg.pylones.size() - 1)]["d"]) if not lg.pylones.is_empty() else L * 0.3
	v.append([n + "_pylone", xf * Vector3(-22, lg.terrain(d + 25) + 4, -d - 25), xf * Vector3(0, lg.y_cable(d) - 3.0, -d)])
	v.append([n + "_ensemble", xf * Vector3(-L * 0.45, lg.terrain(L * 0.5) + L * 0.2, -L * 0.25),
		xf * Vector3(0, lg.terrain(L * 0.5) + 15, -L * 0.5)])
	v.append([n + "_gare_amont", xf * Vector3(16, lg.terrain(L - 30.0) + 6.0, -L + 30.0),
		xf * Vector3(0, lg.terrain(L - 5.0) + 2.5, -L + 5.0)])
	return v


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var rm: RemonteesDomaine = _main.remontees
	match _etat:
		0:
			for e in rm.lignes:
				if String(e[0].name).contains(_filtre):
					_lignes.append(e[0])
			print("SHOT lignes : ", _lignes.map(func(l): return String(l.name)))
			if _lignes.is_empty():
				quit(1)
				return
			_main.perf_manager.mode = "fige"
			_cam = Camera3D.new()
			_cam.fov = 55
			_cam.far = 8000
			_main.add_child(_cam)
			_etat = 1
		1:
			if _k >= _lignes.size():
				quit(0)
				return
			_main.aller_a_remontee(_lignes[_k])
			_att = 0
			_etat = 2
		2:
			_att += 1
			var lg: LigneRemontee = _lignes[_k]
			if (lg.pret and _att > 240) or _att > 3000:
				_vues = _vues_de(lg)
				_i = 0
				_cam.make_current()
				_att = 0
				_etat = 3
		3:
			if _i >= _vues.size():
				_k += 1
				_etat = 1
				return
			var v: Array = _vues[_i]
			if _att == 0:
				_cacher_interface(get_root())
				_cam.global_position = v[1]
				_cam.look_at(v[2], Vector3.UP)
			_att += 1
			if _att == 40:
				var f: String = "%s_%s.png" % [_pre, v[0]]
				get_root().get_texture().get_image().save_png(f)
				print("SHOT ", f)
				_i += 1
				_att = 0


## Interface masquée (menu de départ, HUD, boutons) : la vue seule.
func _cacher_interface(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Control:
			(c as Control).visible = false
		else:
			_cacher_interface(c)
