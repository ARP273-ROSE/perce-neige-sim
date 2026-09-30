# Répartition des triangles, appels de dessin et objets dessinés en vue
# cabine, par groupe de nœuds : on masque chaque groupe 3 images et on lit
# RENDER_TOTAL_PRIMITIVES / DRAW_CALLS / OBJECTS.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     -s perf_groupes.gd -- --drivetest --quality=low
extends SceneTree

var _main: Node = null
var _groupes: Array = []    # [nom, [nœuds]]
var _i: int = -1
var _f: int = 0
var _base: Vector3i = Vector3i.ZERO
var _res: Array = []
var _s_min: float = 900.0   # --s=… : abscisse où l'on mesure (llvmpipe est lent)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--s="):
			_s_min = float(a.substr(4))
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _prim() -> Vector3i:
	return Vector3i(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))


func _prepare() -> void:
	var par_nom: Dictionary = {}
	var track: Node = _main.get("track")
	for c in track.get_children():
		var n: String = String(c.name)
		var k: String = n.rstrip("0123456789").trim_suffix("_").rstrip("0123456789").trim_suffix("_")
		if not par_nom.has(k):
			par_nom[k] = []
		par_nom[k].append(c)
	for k in par_nom:
		_groupes.append(["voie/" + k, par_nom[k]])
	for nm in ["tunnel", "lights", "cabin", "cabin_ghost", "machine_room"]:
		var nd = _main.get(nm)
		if nd != null:
			_groupes.append([nm, [nd]])
	# 2D : calques et panneaux du HUD (les objets et appels 2D comptent aussi)
	for c in _main.get_children():
		if c is CanvasLayer or c is Control:
			_groupes.append(["2d/" + String(c.name), [c]])
			for cc in c.get_children():
				if cc is CanvasItem:
					_groupes.append(["2d/" + String(c.name) + "/" + String(cc.name), [cc]])
	for c in _main.get_children():
		if c is Node3D and not (c in [_main.get("track"), _main.get("tunnel"), _main.get("lights"),
				_main.get("cabin"), _main.get("cabin_ghost"), _main.get("machine_room")]):
			_groupes.append(["main/" + String(c.name), [c]])


func _tick() -> void:
	var ph = _main.get("physics")
	if ph == null:
		return
	if _i < 0:
		if ph.v > minf(8.0, _s_min / 100.0) and ph.s_render > _s_min:
			_prepare()
			_i = 0
			_f = 0
		return
	_f += 1
	if _f == 3:
		_base = _prim()
		for n in _groupes[_i][1]:
			n.set("visible", false)
	elif _f == 6:
		var sans: Vector3i = _prim()
		var d: Vector3i = _base - sans
		_res.append([_groupes[_i][0], d.x, _groupes[_i][1].size(), d.y, d.z])
		for n in _groupes[_i][1]:
			n.set("visible", true)
		_i += 1
		_f = 0
		if _i >= _groupes.size():
			_res.sort_custom(func(a, b): return a[3] > b[3])
			print("s = %.0f m, total image %d triangles, %d appels, %d objets" % [
				ph.s_render, _base.x, _base.y, _base.z])
			for r in _res:
				if r[1] > 2000 or r[3] > 0 or r[4] > 0:
					print("  %-32s %9d triangles %4d appels %5d objets  (%d nœuds)" % [
						r[0], r[1], r[3], r[4], r[2]])
			quit(0)
