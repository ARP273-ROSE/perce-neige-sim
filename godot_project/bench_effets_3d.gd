## Effets graphiques au cran 0, un à la fois, sur des vues fixes : temps de la carte graphique
## et captures. Avec écran seulement, rien d'autre ne doit tourner.
##   godot --fullscreen --path godot_project -s bench_effets_3d.gd -- --sortie=C:/chemin/ [--effets=base,ombres]
extends SceneTree

const IMAGES_CALME: int = 150        # l'éclairage indirect et les caches se posent
const IMAGES_MESURE: int = 120
const SOLEIL_RASANT: Vector3 = Vector3(0.75, 0.25, 0.60)

var _main: Node = null
var _out: String = "user://effets/"
var _filtre: PackedStringArray = PackedStringArray()
var _filtre_vues: String = ""
var _cam: Camera3D
var _env: Environment
var _lum: DirectionalLight3D
var _vp: Viewport
var _vues: Array = []                # [nom, position caméra, cible, position du skieur]
var _res: Array = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("BENCH_EFFETS sauté : il faut un écran")
		FinBanc.quitter(self, get("_main"), 0)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			_out = a.substr(9)
		if a.begins_with("--vues="):
			_filtre_vues = a.substr(7)
		if a.begins_with("--effets="):
			_filtre = a.substr(9).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_suite()


func _attend(n: int) -> void:
	for i in n:
		await process_frame


func _cacher(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_cacher(c)


func _ligne(c: String) -> LigneRemontee:
	for e in _main.remontees.lignes:
		if e[0].name == c:
			return e[0]
	return null


func _au_sol(p: Vector3, h: float) -> Vector3:
	return Vector3(p.x, _main.relief.hauteur_sol(p.x, p.z) + h, p.z)


func _ombres(portee: float) -> Callable:
	return func():
		_main.ombres_relief_permises = true
		_main._soleil_relief.directional_shadow_max_distance = portee


func _sans_ombres() -> void:
	_main.ombres_relief_permises = false
	_main._soleil_relief.directional_shadow_max_distance = 600.0


## Le relief porte aussi son ombre (portée longue : montagnes).
func _montagnes(on: bool) -> void:
	for c in _main.relief.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _soleil(dir: Vector3) -> void:
	var b: Basis = Basis.looking_at(-dir.normalized(), Vector3.UP)
	_main._soleil_relief.basis = b
	_lum.basis = b
	for m in _main.relief._mats_hiver:
		(m as ShaderMaterial).set_shader_parameter("soleil", dir.normalized())


func _effets() -> Array:
	return [
		["base", func(): pass, func(): pass],
		["ombres_600", _ombres(600.0), _sans_ombres],
		["ombres_300", _ombres(300.0), _sans_ombres],
		["ombres_1500", _ombres(1500.0), _sans_ombres],
		["ombres_objets", func():
			_main.ombres_relief_permises = true
			_lum.shadow_enabled = true
			_lum.directional_shadow_max_distance = 600.0
			_lum.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
			func():
				_sans_ombres()
				_lum.shadow_enabled = false],
		["ombres_montagnes", func():
			_ombres(6000.0).call()
			_montagnes(true),
			func():
				_montagnes(false)
				_sans_ombres()],
		["soleil_rasant", func():
			_ombres(6000.0).call()
			_montagnes(true)
			_soleil(SOLEIL_RASANT),
			func():
				_soleil(GareAmont.SOLEIL)
				_montagnes(false)
				_sans_ombres()],
		["ssao", func(): _env.ssao_enabled = true, func(): _env.ssao_enabled = false],
		["ssil", func(): _env.ssil_enabled = true, func(): _env.ssil_enabled = false],
		["lod_fin", func(): _vp.mesh_lod_threshold = 0.25, func(): _vp.mesh_lod_threshold = 1.0],
		["aniso16", func(): _vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X,
			func(): _vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X],
		["msaa8", func(): _vp.msaa_3d = Viewport.MSAA_8X, func(): _vp.msaa_3d = Viewport.MSAA_4X],
		["sans_sdfgi", func(): _env.sdfgi_enabled = false, func(): _env.sdfgi_enabled = true],
		["sans_volum", func(): _env.volumetric_fog_enabled = false, func(): _env.volumetric_fog_enabled = true],
		["sans_ssr", func(): _env.ssr_enabled = false, func(): _env.ssr_enabled = true],
	]


func _quantile(a: PackedFloat32Array, q: float) -> float:
	var b: Array = Array(a)
	b.sort()
	return float(b[int(q * (b.size() - 1))]) if not b.is_empty() else 0.0


func _suite() -> void:
	while _main.relief == null or not _main.relief.pret:
		await process_frame
	await _attend(120)
	_main.basculer_skieur()
	while _main.get("skieur") == null:
		await process_frame
	await _attend(240)
	_main.perf_manager.mode = "fige"
	_main.ombres_relief_permises = false
	_env = _main._env
	_lum = _main._ext_light
	_vp = get_root().get_viewport()
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	_cam = Camera3D.new()
	_cam.far = 8000.0
	_cam.fov = 60.0
	get_root().add_child(_cam)
	var sk: SkieurJoueur = _main.skieur
	for c in ["tsd4_lanches", "tcd10_toviere"]:
		var lg: LigneRemontee = _ligne(c)
		_main.aller_a_remontee(lg)
		var n: int = 0
		while not lg.pret and n < 7200:
			await process_frame
			n += 1
		var pm: PyloneRemontee = lg._pyl[int(lg._pyl.size() / 2)][0]
		var t: Vector3 = pm.global_position + Vector3.UP * pm.hauteur
		var x: Vector3 = pm.global_transform.basis.x
		var z: Vector3 = pm.global_transform.basis.z
		var pied: Vector3 = _au_sol(pm.global_position + x * 25.0, 0.5)
		var q: Vector3 = lg.global_transform * lg.point_embarquement(true)
		var bx: Vector3 = lg.global_transform.basis.x
		var bz: Vector3 = lg.global_transform.basis.z
		var pres_gare: Vector3 = _au_sol(q + bx * 20.0, 0.5)
		# sous-bois du pylône, neige rasante, bas de façade, relief au loin
		_vues.append([c + "_sous_pylone", _au_sol(pm.global_position + x * 6.0 + z * 5.0, 1.5), t, pied, lg])
		_vues.append([c + "_neige_rasante", _au_sol(pm.global_position + x * 14.0, 0.6), _au_sol(pm.global_position - x * 80.0 + z * 20.0, 0.0), pied, lg])
		_vues.append([c + "_facade", _au_sol(q + bx * 24.0 + bz * 12.0, 1.6), q + Vector3.UP * 2.0, pres_gare, lg])
		_vues.append([c + "_loin", _au_sol(q + bx * 40.0 + bz * 30.0, 2.0), q + Vector3.UP * 60.0 - bz * 900.0, pres_gare, lg])
	var lg2: LigneRemontee = _ligne("tcd10_toviere")
	var q2: Vector3 = lg2.global_transform * lg2.point_embarquement(true)
	_vues.append(["toviere_quai_gauche", q2 + Vector3.UP * 1.7, q2 + Vector3.UP * 2.2 + lg2.global_transform.basis.x * -10.0, q2 + Vector3.UP * 0.1, lg2])
	_vues.append(["toviere_quai_droite", q2 + Vector3.UP * 1.7, q2 + Vector3.UP * 2.2 + lg2.global_transform.basis.z * 10.0, q2 + Vector3.UP * 0.1, lg2])
	# surfaces qui reflètent : hall et rails de la gare basse du funiculaire
	var depart: Array = _main.station_halls.gare_aval.point_depart()
	var hall: Vector3 = depart[0]
	_vues.append(["funi_place_vitres", hall + Vector3.UP * 1.6, hall + Vector3.UP * 3.0 + Vector3(-sin(float(depart[1])), 0, -cos(float(depart[1]))) * 20.0, hall, null])
	_vues.append(["funi_quai_rails", Vector3(4.2, 2112.0, 5.5), Vector3(-5.0, 2110.0, -25.0), Vector3(4.2, 2110.5, 5.5), null])
	# bas de la descente : là où le GPU plafonne (relevé 4K, 02/11/2026)
	for k in 3:
		var a_p: Vector3 = [Vector3(-134, 0, 534), Vector3(-121, 0, 375), Vector3(-49, 0, 220)][k]
		var b_p: Vector3 = [Vector3(-121, 0, 375), Vector3(-49, 0, 220), Vector3(-20, 0, 60)][k]
		_vues.append(["pied_pistes_%d" % k, _au_sol(a_p, 2.0), _au_sol(b_p, 1.0), _au_sol(a_p, 0.5), null])
	if not _filtre_vues.is_empty():
		_vues = _vues.filter(func(v): return String(v[0]).begins_with(_filtre_vues))
	for v in _vues:
		print("EFFETS vue ", v[0], " cam ", v[1])
	_cacher(get_root())
	_cam.make_current()
	# (le skieur reste là pour que le jeu construise autour de lui, mais sa tête masquait la vue)
	sk.visible = false
	for e in _effets():
		if not _filtre.is_empty() and not _filtre.has(String(e[0])):
			continue
		e[1].call()
		for v in _vues:
			# (les lignes proches se construisent et les lointaines se démolissent : scène stable d'abord)
			var calme: int = 0
			var attente: int = 0
			while calme < IMAGES_CALME and attente < 3600:
				sk.global_position = v[3]
				sk.velocity = Vector3.ZERO
				_cam.global_position = v[1]
				_cam.look_at(v[2], Vector3.UP)
				await process_frame
				attente += 1
				calme = 0 if _main.remontees.get("_en_cours") != null or (v[4] != null and not (v[4] as LigneRemontee).pret) else calme + 1
				# véhicules arrêtés : mêmes images d'un effet à l'autre
				for e2 in _main.remontees.lignes:
					(e2[0] as LigneRemontee).roule = false
			var g: PackedFloat32Array = PackedFloat32Array()
			var r: PackedFloat32Array = PackedFloat32Array()
			for i in IMAGES_MESURE:
				sk.global_position = v[3]
				sk.velocity = Vector3.ZERO
				await process_frame
				g.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid()))
				r.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp.get_viewport_rid()))
			var prim: float = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			var app: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			print("EFFETS %s %s : gpu med %.2f p95 %.2f max %.2f ; rendu med %.2f ; primitives %.0f appels %.0f video %.0f Mo" % [e[0], v[0], _quantile(g, 0.5), _quantile(g, 0.95), _quantile(g, 1.0), _quantile(r, 0.5), prim, app, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
			var im: Image = _vp.get_texture().get_image()
			im.save_jpg(_out + "%s__%s.jpg" % [v[0], e[0]], 0.95)
		e[2].call()
	print("BENCH_EFFETS FIN")
	FinBanc.quitter(self, _main, 0)
