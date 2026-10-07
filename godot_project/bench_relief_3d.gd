## Banc de la vue extérieure (07/10/2026) : le relief est affiché, le sol
## est translucide au-dessus du tunnel sur toute la ligne et opaque loin de
## lui, le trait du tunnel va d'un bout à l'autre, et la caméra passe sous
## la voie.
##   godot --headless --path godot_project -s bench_relief_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _etape: int = 0
var _attente: int = 0


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
	var relief: ReliefBuilder = _main.get("relief")
	var cab: Cabin = _main.get("cabin")
	if ph == null or relief == null or cab == null:
		return
	if not relief.pret:
		if _f > 3000:
			_verif("relief prêt", false)
			_fin()
		return
	ph.s = 1500.0
	ph.s_prev_step = 1500.0
	ph.v = 0.0
	if _etape == 0:
		cab.set_view(Cabin.ViewMode.EXTERIOR)
		cab.orbit_yaw = 1.6
		cab.orbit_pitch = -0.8          # sous la voie
		cab.orbit_dist = 40.0
		_etape = 1
		_attente = 5
		return
	_attente -= 1
	if _attente > 0:
		return
	var tun: TunnelBuilder = _main.get("tunnel")
	# 1. relief affiché, caméra sous la voie
	var c: Vector3 = cab.global_position
	var cam: Vector3 = cab.camera_ext.global_position
	_verif("relief affiché en vue extérieure", relief.visible)
	_verif("caméra sous la voie (site −0,8 rad)", cam.y < c.y - 20.0,
		"caméra %.0f m sous la rame" % (c.y - cam.y))
	# 2. couloir translucide sur toute la ligne, opaque loin du tunnel
	var pire: float = 0.0
	var loin: float = 1.0
	var s: float = 0.0
	while s <= PNConstants.LENGTH:
		var xf: Transform3D = tun.transform_at(s)
		var p: Vector3 = xf.origin
		pire = maxf(pire, relief.opacite(p.x, p.z))
		var cote: Vector3 = xf.basis.x
		cote.y = 0.0
		var q: Vector3 = p + cote.normalized() * 2000.0
		loin = minf(loin, relief.opacite(q.x, q.z))
		s += 50.0
	_verif("sol translucide à l'aplomb du tunnel, de bout en bout", pire < 0.3,
		"opacité maximale %.2f" % pire)
	_verif("sol opaque à 2 km du tunnel", loin > 0.99, "opacité minimale %.2f" % loin)
	# 3. trait du tunnel de bout en bout
	var ruban: MeshInstance3D = relief.get_node_or_null("TraitTunnel")
	var aabb: AABB = ruban.get_aabb() if ruban != null else AABB()
	var a0: Vector3 = tun.transform_at(0.0).origin
	var a1: Vector3 = tun.transform_at(PNConstants.LENGTH).origin
	_verif("trait du tunnel d'un bout à l'autre", ruban != null
		and aabb.grow(1.0).has_point(a0) and aabb.grow(1.0).has_point(a1),
		"boîte %s" % str(aabb))
	_fin()


func _fin() -> void:
	print("BENCH_RELIEF " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
