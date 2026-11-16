## Captures des remontées dont le nom contient un filtre (vue d'ensemble, gare aval, pylône, gare amont),
## chacune construite sur place (aller_a_remontee) : rendu réel, relief, forêt.
##   godot --path godot_project --resolution 1920x1080 -s shot_filtre_remontees.gd -- --filtre=tkd préfixe
## --tour : six vues par ligne pour le tour des gares (gare aval des deux côtés, premier et dernier pylône, gare
##   amont de côté et de derrière) ; --filtre= vide : toutes les lignes ; --echelle=1.5 : rendu 3D à 150 %
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
## --vue=x,y,z,tx,ty,tz (repère de la ligne) : vues en plus, nommées <ligne>_vueN
var _plus: Array = []
var _tour: bool = false
var _echelle: float = 1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filtre="):
			_filtre = a.substr(9)
		elif a == "--tour":
			_tour = true
		elif a.begins_with("--echelle="):
			_echelle = float(a.substr(10))
		elif a.begins_with("--vue="):
			var t: PackedFloat64Array = a.substr(6).split_floats(",")
			if t.size() == 6:
				_plus.append(t)
		elif not a.begins_with("--"):
			_pre = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


## Tour des gares : gares vues des deux côtés et de derrière, premier et dernier pylône de trois quarts. Recul selon
## la taille de la gare (bâtiments des télécabines et téléphériques), caméra toujours au-dessus du sol affiché.
func _vues_tour(lg: LigneRemontee) -> Array:
	var xf: Transform3D = lg.global_transform
	var L: float = lg.longueur_h()
	var n: String = String(lg.name)
	var v: Array = []
	var grand: bool = lg.famille.begins_with("cabine") or lg is Telepherique or lg.tricable()
	var r: float = 42.0 if grand else 18.0
	var hz: float = 12.0 if grand else 5.0
	var c_av: Vector3 = xf * Vector3(0, lg.terrain(8.0) + 2.5, -8.0)
	v.append([n + "_1_gare_aval", _sur_sol(xf * Vector3(-r, lg.terrain(-r * 0.8) + hz, r * 0.8)), c_av])
	v.append([n + "_2_gare_aval_dos", _sur_sol(xf * Vector3(r, lg.terrain(-r * 0.6) + hz, r * 0.6)), c_av])
	if not lg.pylones.is_empty() and not (lg is Funival):
		var d0: float = float(lg.pylones[0]["d"])
		var c0: Vector3 = xf * Vector3(0, (lg.terrain(d0) + lg.y_cable(d0)) * 0.5, -d0)
		v.append([n + "_3_pylone_premier", _sur_sol(xf * Vector3(-24, lg.terrain(maxf(d0 - 20.0, 0.0)) + 4.0, -maxf(d0 - 20.0, 0.0))), c0])
		var d1: float = float(lg.pylones[lg.pylones.size() - 1]["d"])
		var c1: Vector3 = xf * Vector3(0, (lg.terrain(d1) + lg.y_cable(d1)) * 0.5, -d1)
		v.append([n + "_4_pylone_dernier", _sur_sol(xf * Vector3(24, lg.terrain(maxf(d1 - 30.0, 0.0)) + 5.0, -maxf(d1 - 30.0, 0.0))), c1])
	var c_am: Vector3 = xf * Vector3(0, lg.terrain(L - 5.0) + 2.5, -L + 5.0)
	v.append([n + "_5_gare_amont", _sur_sol(xf * Vector3(r, lg.terrain(L - r * 0.8) + hz, -L + r * 0.8)), c_am])
	v.append([n + "_6_gare_amont_dos", _sur_sol(xf * Vector3(-r * 0.5, lg.terrain(L + r) + hz, -L - r)), c_am])
	for j in range(_plus.size()):
		var t: PackedFloat64Array = _plus[j]
		v.append([n + "_vue%d" % j, xf * Vector3(t[0], t[1], t[2]), xf * Vector3(t[3], t[4], t[5])])
	return v


## Caméra au moins 2,5 m au-dessus du sol affiché (le profil de la ligne ne suit que son axe).
func _sur_sol(p: Vector3) -> Vector3:
	var rel = _main.get("relief")
	if rel != null:
		p.y = maxf(p.y, float(rel.hauteur_sol(p.x, p.z)) + 2.5)
	return p


func _vues_de(lg: LigneRemontee) -> Array:
	if _tour:
		return _vues_tour(lg)
	var xf: Transform3D = lg.global_transform
	var L: float = lg.longueur_h()
	var n: String = String(lg.name)
	var v: Array = []
	var c3: Vector3 = xf * Vector3(0, lg.terrain(8.0) + 2.5, -8.0)
	v.append([n + "_gare_aval", xf * Vector3(-14, lg.terrain(-12.0) + 5.0, 12.0), c3])
	var d: float = float(lg.pylones[mini(1, lg.pylones.size() - 1)]["d"]) if not lg.pylones.is_empty() else L * 0.3
	v.append([n + "_pylone", xf * Vector3(-22, lg.terrain(d + 25) + 4, -d - 25), xf * Vector3(0, lg.y_cable(d) - 3.0, -d)])
	# tête du dernier pylône : de dessus (comme du toit d'une cabine), de côté, et de dessous
	if not lg.pylones.is_empty():
		var dd: float = float(lg.pylones[lg.pylones.size() - 1]["d"])
		var yc: float = lg.y_cable(dd)
		v.append([n + "_tete_dessus", xf * Vector3(0.0, yc + 7.0, -dd + 11.0), xf * Vector3(0, yc - 1.0, -dd - 3.0)])
		v.append([n + "_tete_cote", xf * Vector3(-13.0, yc + 1.5, -dd + 3.0), xf * Vector3(0, yc - 0.5, -dd)])
		v.append([n + "_tete_voie", xf * Vector3(lg.voie * 0.5 + 0.2, yc + 1.2, -dd + 9.0), xf * Vector3(lg.voie * 0.5, yc - 0.3, -dd)])
	# va-et-vient : la cabine à quai, des deux côtés (portes), et son intérieur
	if lg is Telepherique and not (lg is Funival) and lg.nombre_vehicules() > 0:
		for i in range(lg.nombre_vehicules()):
			if lg.zone_vehicule(i) == "ligne":
				continue
			var cv: Vector3 = lg.vehicule(i).global_position + Vector3(0, -VehiculeRemontee.H_SUSP_TPH - 1.5, 0)
			var bx: Vector3 = lg.global_transform.basis.x
			var bz: Vector3 = lg.global_transform.basis.z
			v.append([n + "_cabine_droite", cv + bx * 7.5 + bz * 3.0 + Vector3(0, 1.0, 0), cv])
			v.append([n + "_cabine_gauche", cv - bx * 7.5 + bz * 3.0 + Vector3(0, 1.0, 0), cv])
			v.append([n + "_cabine_dedans", cv + bz * 2.3 + Vector3(0, 0.4, 0), cv - bz * 2.0 + bx * 0.8 - Vector3(0, 0.3, 0)])
			break
	v.append([n + "_ensemble", xf * Vector3(-L * 0.45, lg.terrain(L * 0.5) + L * 0.2, -L * 0.25),
		xf * Vector3(0, lg.terrain(L * 0.5) + 15, -L * 0.5)])
	v.append([n + "_gare_amont", xf * Vector3(16, lg.terrain(L - 30.0) + 6.0, -L + 30.0),
		xf * Vector3(0, lg.terrain(L - 5.0) + 2.5, -L + 5.0)])
	for j in range(_plus.size()):
		var t: PackedFloat64Array = _plus[j]
		v.append([n + "_vue%d" % j, xf * Vector3(t[0], t[1], t[2]), xf * Vector3(t[3], t[4], t[5])])
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
				if _filtre == "" or String(e[0].name).contains(_filtre):
					_lignes.append(e[0])
			print("SHOT lignes : ", _lignes.map(func(l): return String(l.name)))
			if _lignes.is_empty():
				quit(1)
				return
			_main.perf_manager.mode = "fige"
			_main.perf_manager.banc = true
			if _echelle != 1.0:
				get_root().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				get_root().scaling_3d_scale = _echelle
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
