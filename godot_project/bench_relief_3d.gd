## Banc de la vue extérieure (refonte du 07/10/2026) : sur toute la ligne
## et pour des cadrages variés, la visée caméra → rame ne traverse jamais la
## montagne (chaque point est au-dessus du relief, ou dans l'entaille et
## au-dessus de son fond), le relief reste affiché, et le fond de l'entaille
## est sous le tube.
##   godot --headless --path godot_project -s bench_relief_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _cas: Array = []
var _i: int = -1
var _attente: int = 0
const CADRAGES: Array = [[0.12, 0.38, 27.0], [1.6, 0.30, 80.0], [2.6, -0.10, 40.0],
	[1.6, 0.5, 600.0], [3.9, 0.45, 3000.0]]


func _initialize() -> void:
	for s in [23.0, 300.0, 1300.0, 2150.0, 3000.0, 3450.0]:
		for c in CADRAGES:
			_cas.append([s, c[0], c[1], c[2]])
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	if not cond or label.begins_with("—"):
		print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _tick() -> void:
	_f += 1
	var ph: TrainPhysics = _main.get("physics")
	var relief: ReliefBuilder = _main.get("relief")
	var cab: Cabin = _main.get("cabin")
	if ph == null or relief == null or cab == null:
		return
	if not relief.pret:
		if _f > 3000:
			_verif("relief prêt", false)
			_fin()
		return
	if _i < 0:
		cab.set_view(Cabin.ViewMode.EXTERIOR)
		_i = 0
		_poser()
		return
	_attente -= 1
	var cas: Array = _cas[_i]
	ph.s = cas[0]
	ph.s_prev_step = cas[0]
	ph.v = 0.0
	if _attente > 0:
		return
	_mesurer(cas, relief, cab)
	_i += 1
	if _i >= _cas.size():
		_fin()
		return
	_poser()


func _poser() -> void:
	var cas: Array = _cas[_i]
	var cab: Cabin = _main.get("cabin")
	cab.orbit_yaw = cas[1]
	cab.orbit_pitch = cas[2]
	cab.orbit_dist = cas[3]
	_attente = 4


func _mesurer(cas: Array, relief: ReliefBuilder, cab: Cabin) -> void:
	var c: Vector3 = cab.global_position
	var cam: Vector3 = cab.camera_ext.global_position
	var bouche: int = 0
	var pire: float = 0.0
	for k in range(1, 101):
		var q: Vector3 = c.lerp(cam, k / 100.0)
		var h: float = relief.hauteur_partout(q.x, q.z)
		if q.y >= h - 0.5:
			continue
		var d: Vector2 = Vector2(q.x - c.x, q.z - c.z)
		var dedans: bool = d.dot(relief._n) > -relief._off and d.length() < relief._r
		if dedans and q.y > relief.sol(q.x, q.z) - 0.5:
			continue
		bouche += 1
		pire = maxf(pire, h - q.y)
	var lab: String = "s %4.0f, lacet %.2f, site %+.2f, recul %4.0f m" % cas
	_verif(lab + " : visée dégagée", bouche == 0,
		"%d points dans la montagne (jusqu'à %.1f m sous la surface), entaille %.0f m" % [bouche, pire, relief._r])
	_verif(lab + " : relief affiché", relief.visible)
	# fond sous le tube, à l'aplomb de la rame
	var s_fond: float = relief.sol(c.x, c.z)
	_verif(lab + " : fond sous le tube", s_fond < c.y - 1.8 and s_fond > c.y - 6.0,
		"fond %.2f m sous l'axe" % (c.y - s_fond))
	print("  %s : entaille %.0f m, caméra à %.0f m au-dessus du fond" % [lab, relief._r,
		cam.y - relief.sol(cam.x, cam.z)])


func _fin() -> void:
	print("BENCH_RELIEF " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
