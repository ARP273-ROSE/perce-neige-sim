## Effets graphiques au cran 0, un à la fois, sur des vues fixes : temps de la carte graphique
## et captures. Avec écran seulement, rien d'autre ne doit tourner.
##   godot --fullscreen --path godot_project -s bench_effets_3d.gd -- --sortie=C:/chemin/ [--effets=base,ombres]
## Mode cran par cran (relevés d'une machine à l'autre) : --crans=0-5 [--etiq=machine] ; chaque cran du jeu appliqué
## tel quel (PerfManager), mêmes vues, médianes GPU, rendu CPU et image ; tableau court dans <sortie>/crans_<etiq>.txt.
## Mode effet par effet : --decoupe [--etiq=machine] ; part du cran 0 et coupe les effets un à un, en cumulant, dans
## l'ordre du régulateur (éclairage indirect, brouillard, anti-crénelage, néons, pare-brise, nuages, halo), puis une
## seconde chaîne qui coupe l'anti-crénelage AVANT le brouillard ; gain de chaque coupure dans <sortie>/decoupe_<etiq>.txt.
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
var _crans: Array = []               # mode cran par cran : crans à relever
var _etiq: String = "machine"
var _decoupe: bool = false
var _groupes: bool = false
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
		if a.begins_with("--crans="):
			var bornes: PackedStringArray = a.substr(8).split("-")
			for c in range(int(bornes[0]), int(bornes[bornes.size() - 1]) + 1):
				_crans.append(c)
		if a.begins_with("--etiq="):
			_etiq = a.substr(7)
		if a == "--decoupe":
			_decoupe = true
		if a == "--groupes":
			_groupes = true
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


func _lointains(on: bool) -> void:
	for e in _main.remontees.lignes:
		for c in (e[0] as Node).get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("VehiculesLoin"):
				(c as Node3D).visible = on


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
		["sans_glow", func(): _env.glow_enabled = false, func(): _env.glow_enabled = true],
		# (plafond du gain sur les véhicules lointains : tous masqués ; mesure seulement)
		["sans_loin", func(): _lointains(false), func(): _lointains(true)],
		["ombres_objets_sans_loin", func():
			_main.ombres_relief_permises = true
			_lum.shadow_enabled = true
			_lum.directional_shadow_max_distance = 600.0
			_lum.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_lointains(false),
			func():
				_lointains(true)
				_sans_ombres()
				_lum.shadow_enabled = false],
		["sans_msaa", func(): _vp.msaa_3d = Viewport.MSAA_DISABLED, func(): _vp.msaa_3d = Viewport.MSAA_4X],
		["sans_sdfgi", func(): _env.sdfgi_enabled = false, func(): _env.sdfgi_enabled = true],
		["sans_volum", func(): _env.volumetric_fog_enabled = false, func(): _env.volumetric_fog_enabled = true],
		["sans_ssr", func(): _env.ssr_enabled = false, func(): _env.ssr_enabled = true],
	]


## Scène stable (constructions finies), puis IMAGES_MESURE images : [gpu méd, gpu p95, gpu max, rendu CPU méd,
## image méd (ms entre deux images), primitives, appels].
func _mesurer_vue(sk: SkieurJoueur, v: Array) -> Array:
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
	var im: PackedFloat32Array = PackedFloat32Array()
	var t: int = Time.get_ticks_usec()
	for i in IMAGES_MESURE:
		sk.global_position = v[3]
		sk.velocity = Vector3.ZERO
		await process_frame
		var t2: int = Time.get_ticks_usec()
		im.append((t2 - t) / 1000.0)
		t = t2
		g.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid()))
		r.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp.get_viewport_rid()))
	return [_quantile(g, 0.5), _quantile(g, 0.95), _quantile(g, 1.0), _quantile(r, 0.5), _quantile(im, 0.5),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]


## Crans du jeu un à un (PerfManager._appliquer), mêmes vues : tableau court, comparable d'une machine à l'autre.
func _releve_crans(sk: SkieurJoueur) -> void:
	var pm: Node = _main.perf_manager
	var cran0: int = int(pm.get("cran"))
	# sans vsync : l'intervalle entre deux images est celui de la machine, pas celui de l'écran
	var vsync0: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var res: Dictionary = {}       # cran → vue → [gpu, cpu, image, prim, appels]
	for c in _crans:
		pm.call("_appliquer", int(c), "banc cran par cran")
		for v in _vues:
			var m: Array = await _mesurer_vue(sk, v)
			print("CRAN %d %s : gpu med %.2f ; rendu cpu %.2f ; image %.2f ; primitives %.0f appels %.0f" % [c, v[0], m[0], m[3], m[4], m[5], m[6]])
			if not res.has(c):
				res[c] = {}
			res[c][v[0]] = [m[0], m[3], m[4], m[5], m[6]]
	pm.call("_appliquer", cran0, "fin du banc")
	DisplayServer.window_set_vsync_mode(vsync0)
	var vs: Vector2i = DisplayServer.window_get_size()
	var o: PackedStringArray = PackedStringArray()
	o.append("# relevé cran par cran — %s — %s, %d cœurs — %s — %s — fenêtre %dx%d — %s" % [_etiq, OS.get_processor_name(),
		OS.get_processor_count(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		vs.x, vs.y, Time.get_datetime_string_from_system()])
	o.append("# médianes sur %d images par vue, sans vsync ; gpu = temps de la carte, cpu = rendu côté processeur, image = intervalle entre deux images (ms) ; cran 5 = 30 i/s imposées" % IMAGES_MESURE)
	var ligne: String = "%-28s" % "vue"
	for c in _crans:
		ligne += " | cran %d gpu   cpu  image" % c
	o.append(ligne)
	for v in _vues:
		ligne = "%-28s" % v[0]
		for c in _crans:
			var x: Array = res[c][v[0]]
			ligne += " | %8.2f %5.2f %6.2f" % [x[0], x[1], x[2]]
		o.append(ligne)
	ligne = "%-28s" % "médiane des vues"
	for c in _crans:
		var gg: PackedFloat32Array = PackedFloat32Array()
		var cc: PackedFloat32Array = PackedFloat32Array()
		var ii: PackedFloat32Array = PackedFloat32Array()
		for v in _vues:
			gg.append(res[c][v[0]][0])
			cc.append(res[c][v[0]][1])
			ii.append(res[c][v[0]][2])
		ligne += " | %8.2f %5.2f %6.2f" % [_quantile(gg, 0.5), _quantile(cc, 0.5), _quantile(ii, 0.5)]
	o.append(ligne)
	var f: FileAccess = FileAccess.open(_out.path_join("crans_%s.txt" % _etiq), FileAccess.WRITE)
	f.store_string("\n".join(o) + "\n")
	f.close()
	for l in o:
		print(l)


## Coupures du régulateur une à une (mêmes réglages que PerfManager._appliquer), cumulées.
func _coupures() -> Dictionary:
	var st: Node = _main.get("stations") as Node
	var sky_mat: ShaderMaterial = _env.sky.sky_material as ShaderMaterial if _env.sky != null else null
	return {
		"eclairage_indirect": func(): _env.sdfgi_enabled = false,
		"brouillard": func(): _env.volumetric_fog_enabled = false,
		"msaa_vers_smaa": func():
			_vp.msaa_3d = Viewport.MSAA_DISABLED
			_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA,
		"neons_alleges": func():
			if st != null and st.has_method("set_neons_alleges"):
				st.call("set_neons_alleges", true),
		"pare_brise_simple": func():
			for nom in ["cabin", "cabin_ghost"]:
				var r: Node = _main.get(nom) as Node
				if r != null and r.has_method("set_pare_brise_simple"):
					r.call("set_pare_brise_simple", true),
		"nuages": func():
			if sky_mat != null:
				sky_mat.set_shader_parameter("nuages", 0.0),
		"halo": func(): _env.glow_enabled = false,
	}


func _releve_decoupe(sk: SkieurJoueur) -> void:
	var pm: Node = _main.perf_manager
	var cran0: int = int(pm.get("cran"))
	var vsync0: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cp: Dictionary = _coupures()
	var chaines: Array = [
		["regulateur", ["eclairage_indirect", "brouillard", "msaa_vers_smaa", "neons_alleges", "pare_brise_simple", "nuages", "halo"]],
		["msaa_avant_brouillard", ["eclairage_indirect", "msaa_vers_smaa", "brouillard"]],
	]
	var o: PackedStringArray = PackedStringArray()
	var vs: Vector2i = DisplayServer.window_get_size()
	o.append("# relevé effet par effet — %s — %s, %d cœurs — %s — %s — fenêtre %dx%d — %s" % [_etiq, OS.get_processor_name(),
		OS.get_processor_count(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
		vs.x, vs.y, Time.get_datetime_string_from_system()])
	o.append("# médianes sur %d images par vue, sans vsync ; coupures cumulées depuis le cran 0 ; gpu en ms ; gain = gpu avant − gpu après (ms et %% du cran 0)" % IMAGES_MESURE)
	for ch in chaines:
		pm.call("_appliquer", 0, "banc effet par effet")
		var etapes: Array = ["cran0"] + ch[1]
		var res: Dictionary = {}     # étape → vue → gpu
		for i in etapes.size():
			if i > 0:
				(cp[etapes[i]] as Callable).call()
			res[etapes[i]] = {}
			for v in _vues:
				var m: Array = await _mesurer_vue(sk, v)
				res[etapes[i]][v[0]] = m[0]
				print("DECOUPE %s %s %s : gpu med %.2f ; rendu cpu %.2f ; image %.2f ; primitives %.0f appels %.0f" % [ch[0], etapes[i], v[0], m[0], m[3], m[4], m[5], m[6]])
		o.append("")
		o.append("## chaîne %s" % ch[0])
		var ligne: String = "%-28s" % "vue"
		for e in etapes:
			ligne += " | %18s" % e
		o.append(ligne)
		var lignes_vues: Array = []
		for v in _vues:
			lignes_vues.append(v[0])
		lignes_vues.append("médiane des vues")
		for nv in lignes_vues:
			ligne = "%-28s" % nv
			var prec: float = 0.0
			var base: float = 0.0
			for i in etapes.size():
				var g: float = 0.0
				if nv == "médiane des vues":
					var gg: PackedFloat32Array = PackedFloat32Array()
					for v in _vues:
						gg.append(res[etapes[i]][v[0]])
					g = _quantile(gg, 0.5)
				else:
					g = res[etapes[i]][nv]
				if i == 0:
					base = g
					ligne += " | %18s" % ("%.2f" % g)
				else:
					ligne += " | %18s" % ("%.2f (−%.2f %3.0f%%)" % [g, prec - g, 100.0 * (prec - g) / maxf(base, 0.001)])
				prec = g
			o.append(ligne)
		pm.call("_appliquer", cran0, "fin de chaîne")
		# (le régulateur ne remet pas les néons, le pare-brise ni les nuages au cran 0 s'ils n'ont pas changé)
		var st: Node = _main.get("stations") as Node
		if st != null and st.has_method("set_neons_alleges"):
			st.call("set_neons_alleges", false)
		for nom in ["cabin", "cabin_ghost"]:
			var r: Node = _main.get(nom) as Node
			if r != null and r.has_method("set_pare_brise_simple"):
				r.call("set_pare_brise_simple", false)
	DisplayServer.window_set_vsync_mode(vsync0)
	var f: FileAccess = FileAccess.open(_out.path_join("decoupe_%s.txt" % _etiq), FileAccess.WRITE)
	f.store_string("\n".join(o) + "\n")
	f.close()
	for l in o:
		print(l)


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
	# premier plan forcé : sous weston headless la fenêtre n'a jamais le focus, le jeu se bridait à
	# 20 i/s (arrière-plan) et la puce restait à sa fréquence basse : temps GPU gonflés (15/11/2026)
	_main.perf_manager.banc = true
	_main.perf_manager.set("_retrait", 0)
	_main.perf_manager.call("_appliquer_ips")
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
	if _groupes:
		await _releve_groupes(sk)
		print("BENCH_EFFETS FIN")
		FinBanc.quitter(self, _main, 0)
		return
	if _decoupe:
		await _releve_decoupe(sk)
		print("BENCH_EFFETS FIN")
		FinBanc.quitter(self, _main, 0)
		return
	if not _crans.is_empty():
		await _releve_crans(sk)
		print("BENCH_EFFETS FIN")
		FinBanc.quitter(self, _main, 0)
		return
	for e in _effets():
		if not _filtre.is_empty() and not _filtre.has(String(e[0])):
			continue
		e[1].call()
		for v in _vues:
			var m: Array = await _mesurer_vue(sk, v)
			print("EFFETS %s %s : gpu med %.2f p95 %.2f max %.2f ; rendu med %.2f ; primitives %.0f appels %.0f video %.0f Mo" % [e[0], v[0], m[0], m[1], m[2], m[3], m[5], m[6], Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
			var im: Image = _vp.get_texture().get_image()
			im.save_jpg(_out + "%s__%s.jpg" % [v[0], e[0]], 0.95)
		e[2].call()
	print("BENCH_EFFETS FIN")
	FinBanc.quitter(self, _main, 0)


## Mode par groupe : --groupes [--crans=N] [--vues=préfixe] ; au cran N (7 par défaut), chaque groupe de la scène
## (enfants 3D de main, et ceux du relief : anneaux, forêt…) caché à son tour : ce qu'il coûte en GPU, primitives, appels.
func _releve_groupes(sk: SkieurJoueur) -> void:
	var pm: Node = _main.perf_manager
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	pm.call("_appliquer", int(_crans[0]) if not _crans.is_empty() else 7, "banc par groupe")
	var groupes: Array = []
	for c in _main.get_children():
		if c is Node3D and (c as Node3D).visible and c != _main.relief:
			groupes.append(c)
	for c in _main.relief.get_children():
		if c is Node3D and (c as Node3D).visible:
			groupes.append(c)
	var o: PackedStringArray = PackedStringArray()
	o.append("# par groupe — %s — %s — cran %d — gpu ms (gain si caché), primitives, appels" % [_etiq,
		RenderingServer.get_video_adapter_name(), int(pm.get("cran"))])
	for v in _vues:
		var m0: Array = await _mesurer_vue(sk, v)
		o.append("%s : tout %.2f ms, %.0fk prim, %d appels" % [v[0], m0[0], m0[5] / 1000.0, int(m0[6])])
		print("GROUPES ", o[o.size() - 1])
		for g in groupes:
			var n3: Node3D = g
			n3.visible = false
			var m: Array = await _mesurer_vue(sk, v)
			n3.visible = true
			var l: String = "   %-28s −%.2f ms  −%.0fk prim  −%d appels" % [String(n3.name), m0[0] - m[0], (m0[5] - m[5]) / 1000.0, int(m0[6] - m[6])]
			if m0[0] - m[0] > 0.15 or m0[5] - m[5] > 20000.0 or m0[6] - m[6] > 30:
				o.append(l)
				print("GROUPES ", l)
	var f: FileAccess = FileAccess.open(_out.path_join("groupes_%s.txt" % _etiq), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(o) + "\n")
