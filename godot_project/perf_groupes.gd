# Répartition des triangles dessinés en vue cabine, par groupe de nœuds :
# on masque chaque groupe 3 images et on lit RENDER_TOTAL_PRIMITIVES.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     -s perf_groupes.gd -- --drivetest --quality=low
extends SceneTree

var _main: Node = null
var _groupes: Array = []    # [nom, [nœuds]]
var _i: int = -1
var _f: int = 0
var _base: int = 0
var _res: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _prim() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


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
	for c in _main.get_children():
		if c is Node3D and not (c in [_main.get("track"), _main.get("tunnel"), _main.get("lights"),
				_main.get("cabin"), _main.get("cabin_ghost"), _main.get("machine_room")]):
			_groupes.append(["main/" + String(c.name), [c]])


func _tick() -> void:
	var ph = _main.get("physics")
	if ph == null:
		return
	if _i < 0:
		if ph.v > 8.0 and ph.s_render > 900.0:
			_prepare()
			_i = 0
			_f = 0
		return
	_f += 1
	if _f == 3:
		_base = _prim()
		for n in _groupes[_i][1]:
			(n as Node3D).visible = false
	elif _f == 6:
		var sans: int = _prim()
		_res.append([_groupes[_i][0], _base - sans, _groupes[_i][1].size()])
		for n in _groupes[_i][1]:
			(n as Node3D).visible = true
		_i += 1
		_f = 0
		if _i >= _groupes.size():
			_res.sort_custom(func(a, b): return a[1] > b[1])
			print("s = %.0f m, total image %d triangles" % [ph.s_render, _base])
			for r in _res:
				if r[1] > 2000:
					print("  %-32s %9d triangles  (%d nœuds)" % [r[0], r[1], r[2]])
			quit(0)
