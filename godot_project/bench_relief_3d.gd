## Banc de la vue extérieure (07/10/2026) : le relief est affiché (opaque),
## le tunnel se voit à travers lui (trait ambre, d'un bout à l'autre), les
## rames n'ont aucune silhouette, et la caméra passe sous la voie.
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
	# 2. tunnel vu à travers le relief (opaque) : passe « rayons X » du
	# trait sans test de profondeur ; pas de silhouette sur les rames
	var tr_m: ShaderMaterial = null
	var ruban0: MeshInstance3D = relief.get_node_or_null("TraitTunnel")
	if ruban0 != null:
		tr_m = ruban0.mesh.surface_get_material(0) as ShaderMaterial
	var rx: ShaderMaterial = tr_m.next_pass as ShaderMaterial if tr_m != null else null
	_verif("trait du tunnel : passe à travers la montagne", rx != null
		and rx.shader.code.contains("depth_test_disabled"))
	var traces: int = 0
	for cb in [cab, _main.get("cabin_ghost")]:
		if cb == null:
			continue
		for n in (cb as Cabin).mesh_root.find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).material_overlay != null:
				traces += 1
	_verif("aucune silhouette sur les rames (retirée le 07/10/2026)", traces == 0)
	# 3. trait du tunnel de bout en bout
	var ruban: MeshInstance3D = relief.get_node_or_null("TraitTunnel")
	var aabb: AABB = ruban.get_aabb() if ruban != null else AABB()
	var a0: Vector3 = tun.transform_at(0.0).origin
	var a1: Vector3 = tun.transform_at(PNConstants.LENGTH).origin
	_verif("trait du tunnel d'un bout à l'autre", ruban != null
		and aabb.grow(1.0).has_point(a0) and aabb.grow(1.0).has_point(a1),
		"boîte %s" % str(aabb))
	# 4. gares : quais souterrains recouverts, terrain retiré des halls
	var mini_cover: float = INF
	var pire_s: float = 0.0
	for s_q in [5.0, 15.0, 25.0, 35.0, 45.0, 3450.0, 3460.0, 3470.0, 3477.0]:
		var xq: Transform3D = tun.transform_at(s_q)
		var tp: Array = relief.terrain_piece(xq.origin.x, xq.origin.z)
		var sect: float = maxf(tun.tunnel_radius, tun._horseshoe_dims_at(s_q).y)
		var cover: float = float(tp[0]) - (xq.origin.y + sect)
		if is_nan(cover):
			cover = -99.0
		if cover < mini_cover:
			mini_cover = cover
			pire_s = s_q
	_verif("quais et tunnel recouverts (bas et haut)", mini_cover >= 0.75,
		"couverture minimale %.2f m (s = %.0f)" % [mini_cover, pire_s])
	var halls: StationHalls = _main.get("station_halls")
	var dedans: int = 0
	var total: int = 0
	for g in [halls.gare_aval, halls.gare_amont]:
		var am: Dictionary = g.amenagement_relief()
		var poly: PackedVector2Array = am["trous"][0]
		var ctr: Vector2 = Vector2.ZERO
		for v in poly:
			ctr += v
		ctr /= poly.size()
		for k in range(poly.size()):
			var q: Vector2 = ctr.lerp(poly[k], 0.85)
			if not Geometry2D.is_point_in_polygon(q, poly):
				continue                 # (emprise concave)
			total += 1
			if relief.terrain_piece(q.x, q.y)[1]:
				dedans += 1
	_verif("terrain retiré dans les halls des deux gares", dedans == total,
		"%d points sur %d" % [dedans, total])
	_fin()


func _fin() -> void:
	print("BENCH_RELIEF " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
