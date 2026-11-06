## Relevé du cœur, en vrai rendu : le jeu suit la boucle AUTO du skieur (salle, cabine, terrasse, ski,
## gare) et chronomètre chaque image : fil principal jusqu'au dessin, physique, dessin, rendu CPU et GPU
## mesurés par le moteur, appels, objets, cran ; temps par système (Prof) par phase ; pics > 25 ms.
## Écrit <etiq>_images.csv, <etiq>_pics.csv et <etiq>_prof.txt dans --sortie. Lancement : bench_coeur_3d.gd,
## ou en autoload dans un export release (override.cfg). --sortie=dossier --etiq=x [--duree=s] [--client]
extends Node
var _main: Node
var _sortie: String = "."
var _etiq: String = "x"
var _duree: float = 2400.0
var _f: int = 0
var _lance: bool = false
var _t0: int = 0
var _t_phys: int = 0
var _t_proc: int = 0
var _t_pre: int = 0
var _t_post: int = 0
var _lignes: PackedStringArray = PackedStringArray(["t_s;phase;image_ms;principal_ms;physique_ms;dessin_ms;rendu_cpu_ms;gpu_ms;appels;objets;primitives;cran;detail;x;y;z;vram_mo;noeuds;en_cours"])
var _pics: PackedStringArray = PackedStringArray()
var _phase: String = "chargement"
var _par_phase: Dictionary = {}
var _prof0: Dictionary = {}
var _vp: RID
var _fini: bool = false
var _boucle_vue: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			_sortie = a.trim_prefix("--sortie=")
		if a.begins_with("--etiq="):
			_etiq = a.trim_prefix("--etiq=")
		if a.begins_with("--duree="):
			_duree = float(a.trim_prefix("--duree="))
	_t0 = Time.get_ticks_usec()
	var arbre: SceneTree = get_tree()
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	Prof.actif = true
	arbre.physics_frame.connect(func() -> void:
		if _t_phys == 0:
			_t_phys = Time.get_ticks_usec())
	arbre.process_frame.connect(_tick)
	RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_fin_image)


func _tick() -> void:
	_t_proc = Time.get_ticks_usec()
	_f += 1
	if _main == null:
		_main = get_tree().current_scene
		return
	var r: Variant = _main.get("relief")
	if not _lance and r != null and r.pret and _f > 60:
		_lance = true
		print("PRET t=%.1f s" % (float(_t_proc - _t0) / 1e6))
		if not _client:
			_main.basculer_skieur()
	if not _lance:
		return
	if _client:
		_tick_client()
		return
	if _main.skieur_auto == null and _main.mode_skieur:
		_main.basculer_skieur_auto()
	var sa: Variant = _main.skieur_auto
	var ph: String = "?"
	if sa != null:
		ph = String(SkieurAuto.Etape.keys()[sa.etape])
	if ph != _phase:
		_changer(ph)
	var fin: bool = float(_t_proc - _t0) / 1e6 > _duree
	if ph == "VERS_GARE":
		_boucle_vue = true
	if _boucle_vue and ph == "VERS_SALLE":
		fin = true
	if fin and not _fini:
		_fini = true
		_changer("fin")
		_ecrire()
		print("JEU_OK")
		get_tree().quit(0)


var _client: bool = "--client" in OS.get_cmdline_user_args()
var _etape_client: int = 0
var _t_client: float = 0.0


## Mode --client : le programme PC (émetteur UDP) mène la rame et la bascule ; à la bascule, la descente.
func _tick_client() -> void:
	var ph: String = "CLIENT_CABINE"
	if _main.mode_skieur:
		ph = "CLIENT_SKIEUR"
		var sk: Variant = _main.skieur
		if sk != null:
			_t_client += get_process_delta_time()
			if _etape_client == 0 and _t_client > 3.0:
				var pts: PackedVector2Array = FantomesDonnees.points(3)
				sk.global_position = Vector3(pts[0].x, _main.relief.hauteur_sol(pts[0].x, pts[0].y) + 0.05, pts[0].y)
				var d: Vector2 = pts[8] - pts[0]
				sk._cap = atan2(-d.x, -d.y)
				sk.support = null
				_etape_client = 1
			elif _etape_client == 1 and _t_client > 4.0:
				_main.basculer_ski()
				sk.chemin = _main.domaine.chemin_descente(3, 3)
				sk.vitesse_pilote = 12.0
				_etape_client = 2
			if _etape_client == 2:
				ph = "CLIENT_SKI"
	if ph != _phase:
		_changer(ph)
	if float(_t_proc - _t0) / 1e6 > _duree and not _fini:
		_fini = true
		_changer("fin")
		_ecrire()
		print("JEU_OK")
		get_tree().quit(0)


func _changer(ph: String) -> void:
	var d: Dictionary = {}
	for k in Prof.t:
		d[k] = int(Prof.t[k]) - int(_prof0.get(k, 0))
	_par_phase[_phase] = _par_phase.get(_phase, {})
	for k in d:
		_par_phase[_phase][k] = int(_par_phase[_phase].get(k, 0)) + int(d[k])
	_prof0 = Prof.t.duplicate()
	print("PHASE %s -> %s t=%.1f s cran=%d" % [_phase, ph, float(_t_proc - _t0) / 1e6, PerfManager.cran_courant])
	_phase = ph


func _fin_image() -> void:
	var t: int = Time.get_ticks_usec()
	if _main != null and _t_post != 0 and _t_pre != 0:
		var debut: int = _t_phys if _t_phys != 0 else _t_proc
		var im: float = float(t - _t_post) / 1000.0
		var pr: float = float(_t_pre - debut) / 1000.0
		var ph: float = float(_t_proc - _t_phys) / 1000.0 if _t_phys != 0 else 0.0
		var de: float = float(t - _t_pre) / 1000.0
		var rcpu: float = RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		var pos: Vector3 = Vector3.ZERO
		var c: Camera3D = get_viewport().get_camera_3d()
		if c != null:
			pos = c.global_position
		var rm: Node = _main.get("remontees")
		var ec: Variant = rm.get("_en_cours") if rm != null else null
		_lignes.append("%.3f;%s;%.2f;%.2f;%.2f;%.2f;%.2f;%.2f;%d;%d;%d;%d;%d;%.0f;%.0f;%.0f;%.0f;%d;%s" % [
			float(t - _t0) / 1e6, _phase, im, pr, ph, de, rcpu, gpu,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			PerfManager.cran_courant, int(rm.get("niveau_detail")) if rm != null else 0,
			pos.x, pos.y, pos.z,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			str((ec as Node).name) if ec != null and is_instance_valid(ec) else ""])
		if im > 25.0 or pr > 12.0:
			var cles: Array = Prof.image.keys()
			cles.sort_custom(func(a: Variant, b: Variant) -> bool: return int(Prof.image[a]) > int(Prof.image[b]))
			var h: PackedStringArray = PackedStringArray()
			for k in cles.slice(0, 5):
				h.append("%s %.1f" % [k, float(Prof.image[k]) / 1000.0])
			_pics.append("%.2f;%s;%.1f;%.1f;%.1f;%.1f;%s;%s" % [float(t - _t0) / 1e6, _phase, im, pr, ph, de, LigneRemontee.derniere_etape, ",".join(h)])
	Prof.image.clear()
	_t_post = t
	_t_phys = 0


func _ecrire() -> void:
	var f: FileAccess = FileAccess.open("%s/%s_images.csv" % [_sortie, _etiq], FileAccess.WRITE)
	f.store_string("\n".join(_lignes))
	f.close()
	f = FileAccess.open("%s/%s_pics.csv" % [_sortie, _etiq], FileAccess.WRITE)
	f.store_string("\n".join(_pics))
	f.close()
	f = FileAccess.open("%s/%s_prof.txt" % [_sortie, _etiq], FileAccess.WRITE)
	for ph in _par_phase:
		var d: Dictionary = _par_phase[ph]
		var cles: Array = d.keys()
		cles.sort_custom(func(a: Variant, b: Variant) -> bool: return int(d[a]) > int(d[b]))
		for k in cles:
			f.store_line("%s;%s;%d" % [ph, k, d[k]])
	f.close()
