class_name PerfManager
extends Node
## Réglages graphiques selon la machine, puis ajustés EN DIRECT pour rester
## fluide (demande de Kevin du 04/10/2026 : « détecter la config du PC —
## CPU, cœurs, GPU, RAM — et adapter les réglages pour que ça reste fluide »,
## « détecter les saccades en direct pour t'adapter en live »).
##
## 1. Au lancement : processeur, cœurs, mémoire vive, carte graphique (nom,
##    fabricant, intégrée / dédiée / logicielle), pilote, écran → un CRAN de
##    départ (0 = tout, 6 = minimum).
## 2. En jeu, par fenêtres de 2 s : durée de CHAQUE image (pas seulement la
##    moyenne), à-coups (image ≥ 1,9 × le budget, une image vsync sautée),
##    1 % des pires images, et temps de rendu réel de la carte graphique
##    quand le pilote le donne. Saccades → on retire un effet ; marge
##    durable → on en remet un, sans retenter de sitôt un cran qui a échoué.
##
## Crans (chacun = un état complet, on peut monter et descendre) :
##   0 tout : SDFGI, brouillard volumétrique, SSR, MSAA (×4), rendu 100 %
##   1 sans SDFGI (éclairage indirect)
##   2 + sans brouillard volumétrique ni SSR
##   3 + sans MSAA, rendu 3D à 85 %
##   4 rendu à 70 %
##   5 rendu à 60 %, sans halo (glow)
##   6 cadence verrouillée à 30 i/s (régulière plutôt que 40-55 en dents de scie)
## Le rendu OpenGL (PWA, PC sans Vulkan) n'a ni SDFGI, ni brouillard
## volumétrique, ni SSR : il démarre au moins au cran 2.

const CRAN_MAX: int = 6
const FENETRE_S: float = 2.0
const CHAUFFE_S: float = 6.0        # compilation des shaders, chargement
const APRES_CHANGEMENT_S: float = 2.5
const MONTEE_BONNES_FENETRES: int = 10   # 20 s de marge avant de remonter
const ECHEC_INTERDIT_S: float = 180.0    # un cran qui a échoué : pas avant 3 min

var main: Node = null
var mode: String = "auto"           # auto | high | medium | low
var cran: int = 0
var cran_min: int = 0               # plafond de qualité (rendu OpenGL, web)
var machine: Dictionary = {}
var _env: Environment = null
var _rd: bool = true                # renderer RenderingDevice (Forward+/Mobile)
var _web: bool = false

var _t_chauffe: float = CHAUFFE_S
var _t_fen: float = 0.0
var _durees: PackedFloat32Array = []
var _bonnes: int = 0
var _derniere_montee_t: float = -1e9
var _cran_avant_montee: int = -1
var _echecs: Dictionary = {}         # cran → instant jusqu'auquel il est interdit
var _horloge: float = 0.0
var _t_prec_us: int = 0
var _vp_rid: RID
var _mesure_gpu: bool = false
var _msaa_origine: int = Viewport.MSAA_4X   # réglage du projet (anti_aliasing/quality/msaa_3d)
var dernier_bilan: String = ""


func setup(p_main: Node, p_env: Environment, p_mode: String) -> void:
	main = p_main
	_env = p_env
	mode = p_mode if p_mode in ["auto", "high", "medium", "low"] else "auto"
	_web = OS.has_feature("web")
	var methode: String = RenderingServer.get_current_rendering_method()
	_rd = methode != "gl_compatibility"
	if main.get_viewport() != null:
		_vp_rid = main.get_viewport().get_viewport_rid()
		_msaa_origine = main.get_viewport().msaa_3d
	# sans écran (bancs --headless) le serveur de rendu n'a pas de viewport
	_mesure_gpu = _vp_rid.is_valid() and DisplayServer.get_name() != "headless"
	if _mesure_gpu:
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	machine = _detecter()
	cran_min = 0 if _rd else 2
	if _web:
		cran_min = 4          # PWA : réglage bas + rendu 60 % (mesuré sur iPad)
	var depart: int = _cran_de_depart()
	# --cran=N : cran imposé, sans adaptation (captures de contrôle)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cran="):
			depart = int(a.substr(7))
			mode = "high"     # mode fixe : _evaluer ne touche plus à rien
	_appliquer(depart, "profil de départ")
	_log("[Perf] machine : %s" % _resume_machine())


func set_mode(p_mode: String) -> void:
	if p_mode == mode or not p_mode in ["auto", "high", "medium", "low"]:
		return
	mode = p_mode
	_echecs.clear()
	_appliquer(_cran_de_depart(), "réglage « %s »" % mode)


# --- Détection -----------------------------------------------------------

func _detecter() -> Dictionary:
	var mem: Dictionary = OS.get_memory_info()
	var ram_go: float = float(mem.get("physical", 0)) / 1.0e9
	var nom: String = RenderingServer.get_video_adapter_name()
	var vendeur: String = RenderingServer.get_video_adapter_vendor()
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if is_nan(hz) or hz <= 0.0:
		hz = 60.0
	return {
		"cpu": OS.get_processor_name(),
		"coeurs": OS.get_processor_count(),
		"ram_go": snappedf(ram_go, 0.1),
		"gpu": nom,
		"fabricant": vendeur,
		"type": _type_gpu(nom, vendeur),
		"rendu": "%s / %s" % [RenderingServer.get_current_rendering_method(),
			RenderingServer.get_current_rendering_driver_name()],
		"ecran": DisplayServer.screen_get_size(),
		"hz": hz,
	}


## dedie / integre / apple / logiciel / inconnu
func _type_gpu(nom: String, vendeur: String) -> String:
	var n: String = (nom + " " + vendeur).to_lower()
	if n.contains("llvmpipe") or n.contains("swiftshader") or n.contains("softpipe") \
			or n.contains("microsoft basic render"):
		return "logiciel"
	if _rd:
		match RenderingServer.get_video_adapter_type():
			RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
				return "dedie"
			RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
				return "apple" if n.contains("apple") else "integre"
			RenderingDevice.DEVICE_TYPE_CPU:
				return "logiciel"
	# OpenGL : le type n'est pas fourni, on le lit dans le nom
	if n.contains("apple"):
		return "apple"
	if n.contains("nvidia") or n.contains("geforce") or n.contains("quadro") \
			or n.contains("radeon rx") or n.contains("radeon pro") or n.contains("arc a"):
		return "dedie"
	if n.contains("intel") or n.contains("radeon(tm) graphics") or n.contains("radeon graphics") \
			or n.contains("vega") or (n.contains("radeon") and n.contains("m graphics")) \
			or n.contains("adreno") or n.contains("mali"):
		return "integre"
	if n.contains("radeon") and (n.ends_with("m") or n.contains("m ")):
		return "integre"      # Radeon 680M / 740M / 780M (APU)
	return "inconnu"


func _cran_de_depart() -> int:
	match mode:
		"high":
			return maxi(0, cran_min)
		"medium":
			return maxi(2, cran_min)
		"low":
			return maxi(4, cran_min)
	var t: String = machine.get("type", "inconnu")
	var ram: float = machine.get("ram_go", 0.0)
	var coeurs: int = machine.get("coeurs", 4)
	var c: int = 1
	match t:
		"dedie":
			c = 0
		"apple":
			c = 1
		"integre":
			c = 1 if (ram >= 15.0 and coeurs >= 8) else 2
			if ram > 0.0 and ram < 7.5:
				c = 3
		"logiciel":
			c = 5
		_:
			c = 1
	# écran très défini (> 2560 × 1600) : rendu 3D réduit d'office
	var ecran: Vector2i = machine.get("ecran", Vector2i(1920, 1080))
	if ecran.x * ecran.y > 2560 * 1600:
		c = maxi(c, 3)
	return clampi(maxi(c, cran_min), 0, CRAN_MAX)


# --- Application d'un cran ------------------------------------------------

func _appliquer(c: int, pourquoi: String) -> void:
	cran = clampi(maxi(c, cran_min), 0, CRAN_MAX)
	if _env != null and _rd:
		_env.sdfgi_enabled = cran <= 0
		_env.volumetric_fog_enabled = cran <= 1
		_env.ssr_enabled = cran <= 1
	if _env != null:
		_env.glow_enabled = cran <= 4
	Engine.max_fps = 30 if cran >= 6 else 0
	var vp: Viewport = main.get_viewport() if main != null else null
	if vp != null:
		if not _web:
			vp.msaa_3d = _msaa_origine if cran <= 2 else Viewport.MSAA_DISABLED
		var echelle: float = [1.0, 1.0, 1.0, 0.85, 0.7, 0.6, 0.6][cran]
		if _web:
			echelle = minf(echelle, 0.6)    # réglage mesuré sur iPad (v1.15.37)
		if echelle < 0.999:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if _rd \
				else Viewport.SCALING_3D_MODE_BILINEAR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = echelle
	_t_chauffe = maxf(_t_chauffe, APRES_CHANGEMENT_S)
	_durees.clear()
	_t_fen = 0.0
	_bonnes = 0
	_log("[Perf] cran %d/%d (%s)%s" % [cran, CRAN_MAX, pourquoi,
		(" — " + dernier_bilan) if dernier_bilan != "" else ""])


# --- Mesure en direct -------------------------------------------------------

func _process(_delta: float) -> void:
	if main == null:
		return
	var t_us: int = Time.get_ticks_usec()
	if _t_prec_us == 0:
		_t_prec_us = t_us
		return
	var dt: float = float(t_us - _t_prec_us) / 1.0e6
	_t_prec_us = t_us
	_horloge += dt
	if _t_chauffe > 0.0:
		_t_chauffe -= dt
		return
	_durees.append(dt)
	_t_fen += dt
	if _t_fen < FENETRE_S:
		return
	_evaluer()
	_durees.clear()
	_t_fen = 0.0


func _evaluer() -> void:
	var n: int = _durees.size()
	if n < 10:
		return
	var cible_ips: float = 30.0 if cran >= 6 else minf(60.0, machine.get("hz", 60.0))
	var budget: float = 1.0 / cible_ips
	var tri: PackedFloat32Array = _durees.duplicate()
	tri.sort()
	var ips: float = float(n) / _t_fen
	var p99: float = tri[mini(n - 1, int(n * 0.99))]
	var acoups: int = 0
	for d in _durees:
		if d >= 1.9 * budget:
			acoups += 1
	var taux: float = float(acoups) / float(n)
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid) \
		if _mesure_gpu else 0.0
	dernier_bilan = "%.0f i/s, à-coups %.1f %%, 1 %% pires %.0f ms%s" % [ips, taux * 100.0,
		p99 * 1000.0, (", GPU %.1f ms" % gpu_ms) if gpu_ms > 0.0 else ""]
	if mode != "auto":
		return
	var mauvais: bool = ips < 0.83 * cible_ips or taux > 0.03 or p99 > 3.0 * budget
	if mauvais:
		_bonnes = 0
		if cran < CRAN_MAX:
			# le cran qu'on venait de gagner n'a pas tenu : interdit 3 min
			if _cran_avant_montee >= 0 and _horloge - _derniere_montee_t < 20.0:
				_echecs[cran] = _horloge + ECHEC_INTERDIT_S
				_cran_avant_montee = -1
			_appliquer(cran + 1, "saccades")
		return
	var bon: bool = ips >= 0.95 * cible_ips and taux < 0.005
	if not bon:
		_bonnes = 0
		return
	_bonnes += 1
	if cran <= cran_min or _bonnes < MONTEE_BONNES_FENETRES:
		return
	# marge réelle : sans temps GPU, on exige deux fois plus de patience
	if gpu_ms > 0.0:
		if gpu_ms > 0.55 * budget * 1000.0:
			return
	elif _bonnes < 2 * MONTEE_BONNES_FENETRES:
		return
	var vise: int = cran - 1
	if _echecs.get(vise, -1.0) > _horloge:
		return
	_cran_avant_montee = cran
	_derniere_montee_t = _horloge
	_appliquer(vise, "marge")


func _resume_machine() -> String:
	# le navigateur ne donne ni le nom du processeur ni la mémoire
	var cpu: String = str(machine.get("cpu", ""))
	var ram: float = float(machine.get("ram_go", 0.0))
	return "%s, %d cœurs, %s — %s (%s) — %s — écran %dx%d @ %.0f Hz → mode %s" % [
		cpu if cpu != "" else "processeur ?", machine.get("coeurs", 0),
		("%.1f Go" % ram) if ram > 0.0 else "mémoire ?",
		machine.get("gpu", "?"), machine.get("type", "?"), machine.get("rendu", "?"),
		machine.get("ecran", Vector2i.ZERO).x, machine.get("ecran", Vector2i.ZERO).y,
		machine.get("hz", 60.0), mode]


func resume() -> String:
	return "%s ; cran %d/%d ; %s" % [_resume_machine(), cran, CRAN_MAX, dernier_bilan]


# stderr : c'est le seul canal que le sim PC recueille (journal du viewer)
func _log(msg: String) -> void:
	printerr(msg)
