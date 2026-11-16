## Audit du moteur : ips, temps CPU et carte, appels de dessin, primitives, objets, mémoire vidéo et nœuds
## aux 5 points de référence, avec variantes (ombres, effets, MSAA, échelle du rendu) et coût des scripts
## par ablation (process coupé script par script). Lancé sur l'exe exporté ou dans l'éditeur :
## Autoload ajouté seulement à l'export de mesure (le modèle release ignore -s) ; inerte sans --sonde :
##   perce_neige_3d.exe --resolution 2560x1440 -- --sonde --cran=0 --sortie=C:/…/mesures.json
##     [--echelle-base=1.5] (rendu 3D à 150 % : 3840 × 2160 dans une fenêtre 2560 × 1440)
##     [--points=val_claret,tignes_lac,toviere,solaise,cabine] [--variantes=base,ombres,…] [--scripts]
extends Node

const POINTS: Array = ["cabine", "val_claret", "tignes_lac", "toviere", "solaise"]
const VARIANTES: Array = ["base", "sans_ombres", "sans_effets", "sans_msaa", "echelle_50"]
const N_MESURE: int = 240
const N_CHAUFFE: int = 40

var _main: Node
var _f: int = 0
var _etat: String = "charge"
var _sortie: String = "user://sonde_moteur.json"
var _echelle_base: float = 1.0
var _points: Array = POINTS.duplicate()
var _variantes: Array = VARIANTES.duplicate()
var _scripts: bool = false
var _point_abl: String = "toviere"
var _noeuds_prec: int = 0
var _stable: int = 0
var _fin_node: Node
var _ip: int = -1
var _iv: int = 0
var _att: int = 0
var _ech: Dictionary = {}
var _res: Array = []
var _t_prec: int = 0
var _sauve: Array = []
var _lg: LigneRemontee
var _abl: Array = []          # [chemin du script, [nœuds]]
var _ia: int = -1
var _abl_res: Array = []
var _ref_abl: Dictionary = {}
var _cle: String = ""
var _t_proc0: int = 0
var _proc_ms: float = 0.0
var _t_phys0: int = 0
var _phys_acc: float = 0.0     # physique cumulée depuis la dernière image
var _phys_ms: float = 0.0


## Dernier nœud servi (process et physique) : arrête les chronos ouverts par les signaux du SceneTree.
class _Fin extends Node:
	var sonde
	func _ready() -> void:
		process_priority = 1 << 30
		process_physics_priority = 1 << 30
	func _process(_d: float) -> void:
		sonde._proc_ms = (Time.get_ticks_usec() - sonde._t_proc0) / 1000.0
	func _physics_process(_d: float) -> void:
		sonde._phys_acc += (Time.get_ticks_usec() - sonde._t_phys0) / 1000.0


func _ready() -> void:
	if not "--sonde" in OS.get_cmdline_user_args():
		queue_free()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			_sortie = a.substr(9)
		elif a.begins_with("--echelle-base="):
			_echelle_base = float(a.substr(15))
		elif a.begins_with("--points="):
			_points = Array(a.substr(9).split(","))
		elif a.begins_with("--variantes="):
			_variantes = Array(a.substr(12).split(","))
		elif a == "--scripts":
			_scripts = true
		elif a.begins_with("--ablation-a="):
			_scripts = true
			_point_abl = a.substr(13)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_priority = -(1 << 30)
	await get_tree().process_frame
	_main = get_tree().current_scene
	get_tree().process_frame.connect(_tick)
	get_tree().physics_frame.connect(func(): _t_phys0 = Time.get_ticks_usec())
	var fin := _Fin.new()
	fin.sonde = self
	get_tree().root.add_child(fin)
	_fin_node = fin
	_t_prec = Time.get_ticks_usec()


func _vp() -> Viewport:
	return get_tree().root


func _tick() -> void:
	var t: int = Time.get_ticks_usec()
	var dt: float = (t - _t_prec) / 1000.0
	_t_prec = t
	_t_proc0 = t
	_phys_ms = _phys_acc
	_phys_acc = 0.0
	_f += 1
	Engine.max_fps = 0
	if _main.get("perf_manager") != null and not _main.perf_manager.banc:
		_main.perf_manager.banc = true
		_main.perf_manager._retrait = 0
		_main.perf_manager._appliquer_ips()
	if _main.get("relief") == null or not _main.relief.pret or _f < 30:
		return
	match _etat:
		"charge":
			# fenêtre lancée sans le focus : pas de bridage « arrière-plan » (PerfManager.banc)
			_main.perf_manager.banc = true
			_main.perf_manager._retrait = 0
			_main.perf_manager._appliquer_ips()
			# menu de scénario du départ : choix par défaut (sinon il recouvre la 3D pendant toutes les mesures)
			var scen: Node = _main.find_child("ScenarioPanel", true, false)
			if scen != null:
				scen.emit_signal("chosen", false, false, "normal")
				scen.queue_free()
			RenderingServer.viewport_set_measure_render_time(_vp().get_viewport_rid(), true)
			_vp().scaling_3d_scale = _echelle_base
			_vp().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			print("SONDE prête à l'image %d (%.1f s), moteur %s" % [_f, Time.get_ticks_msec() / 1000.0,
				RenderingServer.get_current_rendering_method()])
			_point_suivant()
		"aller":
			if _main.get("remontees") == null or _main.skieur == null or not _main.skieur.actif:
				return
			for e in _main.remontees.lignes:
				if String(e[0].name) == _cle:
					_lg = e[0]
			if _lg == null:
				print("SONDE ligne absente ", _cle)
				_point_suivant()
				return
			_placer(_points[_ip])
			_att = 0
			_etat = "place"
		"place":
			_att += 1
			if _pret_au_point() or _att > 3600:
				_att = 0
				_iv = 0
				_etat = "variante"
				_appliquer(_variantes[_iv], true)
		"variante":
			_att += 1
			if _att == N_CHAUFFE:
				_ech = {"dt": [], "proc": [], "phys": [], "rcpu": [], "rgpu": [], "setup": []}
			elif _att > N_CHAUFFE:
				_echantillon(dt)
				if _att >= N_CHAUFFE + N_MESURE:
					_bilan(_points[_ip], _variantes[_iv])
					_appliquer(_variantes[_iv], false)
					_iv += 1
					_att = 0
					if _iv < _variantes.size():
						_appliquer(_variantes[_iv], true)
					elif _scripts and _points[_ip] == _point_abl:
						_preparer_ablation()
						_etat = "ablation"
					else:
						_point_suivant()
		"ablation":
			_pas_ablation(dt)


func _pret_au_point() -> bool:
	if _att < 240:
		return false
	var rm = _main.get("remontees")
	if rm != null and rm._en_cours != null:
		return false
	var co = _main.get("collisions")
	if co != null and not co._taches.is_empty():
		return false
	if _lg != null and not _lg.pret:
		return false
	# nombre de nœuds stable (± 0,5 %) sur 3 s : les lignes voisines ont fini de se construire
	var n: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if absi(n - _noeuds_prec) > maxi(50, _noeuds_prec / 200):
		_noeuds_prec = n
		_stable = 0
		return false
	_stable += 1
	return _att > 420 and _stable > 180


func _point_suivant() -> void:
	_ip += 1
	if _ip >= _points.size():
		_fin()
		return
	var nom: String = _points[_ip]
	_lg = null
	if nom == "cabine":
		# cabine du Perce-Neige en ligne : à mi-tunnel, en marche
		var ph = _main.physics
		ph.s = 1500.0
		ph.s_prev_step = 1500.0
	else:
		if not _main.mode_skieur:
			_main.basculer_skieur()
		_cle = {"val_claret": "funival", "tignes_lac": "tsd6_palafour", "toviere": "tcd10_toviere",
			"solaise": "tcd10_solaise", "gare_pn": "funival"}[nom]
		_att = 0
		_etat = "aller"
		return
	_att = 0
	_etat = "place"


func _placer(nom: String) -> void:
	if nom in ["val_claret", "tignes_lac"]:
		_main.aller_a_remontee(_lg)
		return
	if nom == "gare_pn":
		# devant la gare aval du Perce-Neige, à 80 m en aval de l'entrée du tunnel, regard vers elle
		var g: Vector3 = _main.tunnel.transform_at(0.0).origin
		var g2: Vector3 = _main.tunnel.transform_at(60.0).origin
		var amont_pn: Vector3 = Vector3(g2.x - g.x, 0.0, g2.z - g.z).normalized()
		var q: Vector3 = g - amont_pn * 80.0
		q.y = _main.relief.hauteur_sol(q.x, q.z) + 0.1
		_main.remontees.quitter()
		if _main.collisions != null:
			_main.collisions.assurer_autour(q)
		_main.skieur.activer(q, atan2(-amont_pn.x, -amont_pn.z))
		_main.skieur.support = null
		_main.skieur.refuge = q
		_main.skieur.dernier_sol = q
		return
	# sommets : à côté de la gare amont, regard vers la vallée (le long de la ligne)
	var xf: Transform3D = _lg.global_transform
	var L: float = _lg.longueur_h()
	var cote: float = signf(_lg._x_brin(true))
	var p: Vector3 = xf * Vector3(cote * (_lg.voie * 0.5 + 12.0), 0.0, -L + 10.0)
	p.y = _main.relief.hauteur_sol(p.x, p.z) + 0.1
	_main.remontees.quitter()
	if _main.collisions != null:
		_main.collisions.assurer_autour(p)
	var aval: Vector3 = xf.basis.z
	_main.skieur.activer(p, atan2(-aval.x, -aval.z))
	_main.skieur.support = null
	_main.skieur.refuge = p
	_main.skieur.dernier_sol = p
	_main._depose_remontee = _lg


func _echantillon(dt: float) -> void:
	var rid: RID = _vp().get_viewport_rid()
	_ech["dt"].append(dt)
	_ech["proc"].append(_proc_ms)
	_ech["phys"].append(_phys_ms)
	_ech["rcpu"].append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	_ech["rgpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_ech["setup"].append(RenderingServer.get_frame_setup_time_cpu())


static func _moy(a: Array) -> float:
	var s: float = 0.0
	for x in a:
		s += x
	return s / maxf(a.size(), 1)


static func _quant(a: Array, q: float) -> float:
	var b: Array = a.duplicate()
	b.sort()
	return b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)]


func _bilan(point: String, variante: String) -> void:
	var r: Dictionary = {
		"point": point, "variante": variante,
		"moteur": RenderingServer.get_current_rendering_method(),
		"taille": "%dx%d" % [_vp().size.x, _vp().size.y], "echelle_3d": _vp().scaling_3d_scale,
		"ips": 1000.0 / maxf(_moy(_ech["dt"]), 0.001),
		"image_ms": _moy(_ech["dt"]), "image_p50": _quant(_ech["dt"], 0.5), "image_p95": _quant(_ech["dt"], 0.95),
		"process_ms": _moy(_ech["proc"]), "physique_ms": _moy(_ech["phys"]),
		"time_process_max_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"time_physics_max_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"rendu_cpu_ms": _moy(_ech["rcpu"]), "rendu_gpu_ms": _moy(_ech["rgpu"]), "prepa_cpu_ms": _moy(_ech["setup"]),
		"appels": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objets": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"vram_mo": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mo": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"tampons_mo": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"noeuds": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objets_moteur": Performance.get_monitor(Performance.OBJECT_COUNT),
		"memoire_mo": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"cran": _main.perf_manager.cran if _main.get("perf_manager") != null else -1,
	}
	_res.append(r)
	print("MESURE ", JSON.stringify(r))
	if variante == "base":
		_vp().get_texture().get_image().save_png(_sortie.get_basename() + "_" + point + ".png")


func _appliquer(v: String, oui: bool) -> void:
	var vp: Viewport = _vp()
	if v.begins_with("masque="):
		if oui:
			_sauve = []
			for m in v.substr(7).split("+"):
				var n = _main.get(m)
				if n == null or not (n is Node):
					continue
				var liste: Array = (n as Node).find_children("*", "VisualInstance3D", true, false)
				if n is VisualInstance3D:
					liste.append(n)
				for vi in liste:
					_sauve.append([vi, (vi as VisualInstance3D).layers])
					(vi as VisualInstance3D).layers = 0
		else:
			for s in _sauve:
				if is_instance_valid(s[0]):
					s[0].layers = s[1]
		return
	match v:
		"sans_ombres":
			if oui:
				_sauve = []
				for l in get_tree().root.find_children("*", "Light3D", true, false):
					_sauve.append([l, (l as Light3D).shadow_enabled])
					(l as Light3D).shadow_enabled = false
			else:
				for s in _sauve:
					if is_instance_valid(s[0]):
						s[0].shadow_enabled = s[1]
		"sans_effets":
			if oui:
				_sauve = []
				for env in _environnements():
					_sauve.append([env, env.ssao_enabled, env.ssil_enabled, env.ssr_enabled, env.sdfgi_enabled,
						env.glow_enabled, env.fog_enabled, env.volumetric_fog_enabled])
					env.ssao_enabled = false
					env.ssil_enabled = false
					env.ssr_enabled = false
					env.sdfgi_enabled = false
					env.glow_enabled = false
					env.fog_enabled = false
					env.volumetric_fog_enabled = false
			else:
				for s in _sauve:
					var env: Environment = s[0]
					env.ssao_enabled = s[1]
					env.ssil_enabled = s[2]
					env.ssr_enabled = s[3]
					env.sdfgi_enabled = s[4]
					env.glow_enabled = s[5]
					env.fog_enabled = s[6]
					env.volumetric_fog_enabled = s[7]
		"ombres_300m", "ombres_2_tranches":
			if oui:
				_sauve = []
				for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
					var dl: DirectionalLight3D = l
					_sauve.append([dl, dl.directional_shadow_max_distance, dl.directional_shadow_mode])
					if v == "ombres_300m":
						dl.directional_shadow_max_distance = minf(dl.directional_shadow_max_distance, 300.0)
					else:
						dl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			else:
				for s in _sauve:
					s[0].directional_shadow_max_distance = s[1]
					s[0].directional_shadow_mode = s[2]
		"ombres_relief_seul":
			# seul le relief porte ombre (décor : gares, pylônes, arbres sans ombre portée)
			if oui:
				_sauve = []
				for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					var gi: GeometryInstance3D = g
					if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (gi.layers & Cabin.LAYER_RELIEF) == 0:
						_sauve.append([gi, gi.cast_shadow])
						gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				print("SONDE ombres coupées sur %d objets du décor" % _sauve.size())
			else:
				for s in _sauve:
					if is_instance_valid(s[0]):
						s[0].cast_shadow = s[1]
		"ciel_uni", "tonemap_lineaire", "sans_brouillard", "sans_ssao", "sans_halo":
			# part fixe : un poste de l'environnement à la fois
			if oui:
				_sauve = []
				for env in _environnements():
					_sauve.append([env, env.background_mode, env.tonemap_mode, env.fog_enabled, env.volumetric_fog_enabled,
						env.ssao_enabled, env.glow_enabled])
					match v:
						"ciel_uni":
							env.background_color = Color(0.55, 0.68, 0.85)
							env.background_mode = Environment.BG_COLOR
						"tonemap_lineaire":
							env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
						"sans_brouillard":
							env.fog_enabled = false
							env.volumetric_fog_enabled = false
						"sans_ssao":
							env.ssao_enabled = false
						"sans_halo":
							env.glow_enabled = false
			else:
				for s in _sauve:
					var env: Environment = s[0]
					env.background_mode = s[1]
					env.tonemap_mode = s[2]
					env.fog_enabled = s[3]
					env.volumetric_fog_enabled = s[4]
					env.ssao_enabled = s[5]
					env.glow_enabled = s[6]
		"sans_aa_ecran":
			if oui:
				_sauve = [vp.screen_space_aa]
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			else:
				vp.screen_space_aa = _sauve[0]
		"sans_2d":
			if oui:
				_sauve = []
				for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
					_sauve.append([c, (c as CanvasLayer).visible])
					(c as CanvasLayer).visible = false
			else:
				for s in _sauve:
					if is_instance_valid(s[0]):
						s[0].visible = s[1]
		"sans_msaa":
			if oui:
				_sauve = [vp.msaa_3d, vp.screen_space_aa]
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			else:
				vp.msaa_3d = _sauve[0]
				vp.screen_space_aa = _sauve[1]
		"echelle_50":
			vp.scaling_3d_scale = _echelle_base * 0.5 if oui else _echelle_base


func _environnements() -> Array:
	var envs: Array = []
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = (we as WorldEnvironment).environment
		if e != null and e not in envs:
			envs.append(e)
	for c in get_tree().root.find_children("*", "Camera3D", true, false):
		var e: Environment = (c as Camera3D).environment
		if e != null and e not in envs:
			envs.append(e)
	if _vp().world_3d != null and _vp().world_3d.environment != null and _vp().world_3d.environment not in envs:
		envs.append(_vp().world_3d.environment)
	return envs


# --- Coût des scripts : process et physique coupés, script par script -------------------------

func _preparer_ablation() -> void:
	var par: Dictionary = {}
	for n in get_tree().root.find_children("*", "", true, false):
		if n == _fin_node or not (n.is_processing() or n.is_physics_processing()):
			continue
		var sc: Script = n.get_script()
		var cle: String = sc.resource_path if sc != null else "(moteur) " + n.get_class()
		if sc != null and cle == "":
			cle = "(classe interne) " + String(n.get_parent().name) + "/" + String(n.name)
		if not par.has(cle):
			par[cle] = []
		par[cle].append(n)
	for k in par:
		_abl.append([k, par[k]])
	print("SONDE ablation : %d scripts ou classes avec process" % _abl.size())
	_ia = -1
	_att = 0
	_ech = {"proc": [], "phys": []}


## Alternance : 90 images de référence, 90 images sans le groupe ; on garde l'écart des moyennes.
func _pas_ablation(_dt: float) -> void:
	_att += 1
	var phase: int = (_att - 1) / 90
	var k: int = (_att - 1) % 90
	if phase == 0 and k == 0:
		_ech = {"proc": [], "phys": []}
	if k >= 30:
		_ech["proc"].append(_proc_ms)
		_ech["phys"].append(_phys_ms)
	if k == 89:
		if phase == 0:
			_ref_abl = {"proc": _moy(_ech["proc"]), "phys": _moy(_ech["phys"])}
			_ia += 1
			if _ia >= _abl.size():
				_abl_res.sort_custom(func(a, b): return a["ms"] > b["ms"])
				print("ABLATION ", JSON.stringify(_abl_res))
				_res.append({"ablation": _abl_res})
				_point_suivant()
				return
			_sauve = []
			for n in _abl[_ia][1]:
				if is_instance_valid(n):
					_sauve.append([n, n.is_processing(), n.is_physics_processing()])
					n.set_process(false)
					n.set_physics_process(false)
			_ech = {"proc": [], "phys": []}
		else:
			var dp: float = _ref_abl["proc"] - _moy(_ech["proc"])
			var dq: float = _ref_abl["phys"] - _moy(_ech["phys"])
			_abl_res.append({"script": _abl[_ia][0], "noeuds": _abl[_ia][1].size(), "process_ms": dp,
				"physique_ms": dq, "ms": dp + dq})
			for s in _sauve:
				if is_instance_valid(s[0]):
					s[0].set_process(s[1])
					s[0].set_physics_process(s[2])
			_att = 0


func _fin() -> void:
	var f := FileAccess.open(_sortie, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_res, "  "))
		f.close()
	print("SONDE fin, %d mesures → %s" % [_res.size(), _sortie])
	get_tree().quit()
