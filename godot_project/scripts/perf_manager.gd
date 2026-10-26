class_name PerfManager
extends Node
## Réglages graphiques selon la machine, puis ajustés EN DIRECT pour rester
## fluide (demande d'un utilisateur du 04/10/2026 : « détecter la config du PC —
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
## Crans (chacun = un état complet, on peut monter et descendre).
## PC (08/10/2026, retour d'utilisateur : « sur le PC du père c'est super pixélisé, on ne
## peut pas lire les noms des boutons ni les chiffres de l'écran du
## cockpit ») : la RÉSOLUTION du rendu est le tout dernier recours, et
## jamais sous 85 % — avant elle, on coupe les effets puis on verrouille la
## cadence à 30 i/s, lisible :
##   0 tout : SDFGI, brouillard volumétrique, SSR, MSAA (×4), halo, rendu 100 %
##   1 sans SDFGI (éclairage indirect)
##   2 + sans brouillard volumétrique ni SSR
##   3 + sans MSAA
##   4 + sans halo (glow)
##   5 + cadence verrouillée à 30 i/s (régulière plutôt que 40-55 en dents de scie)
##   6 + rendu 3D à 85 % (FSR 2 en Forward+, FSR 1 en Mobile, bilinéaire en OpenGL)
## PWA (réglage mesuré sur iPad, v1.15.37, inchangé) :
##   3 sans MSAA, rendu 85 % · 4 rendu 70 % · 5 rendu 60 %, sans halo · 6 30 i/s
## Le rendu OpenGL (PWA, PC sans Vulkan) n'a ni SDFGI, ni brouillard
## volumétrique, ni SSR : il démarre au moins au cran 2.
##
## Économies hors de la vue (06/10/2026 : « un beau truc qui ne consomme pas
## énormément de ressources ») : fenêtre réduite → 5 images/s, fenêtre en
## arrière-plan → 20 images/s (version autonome ; la PWA, le navigateur s'en
## charge ; la 3D embarquée dans le PC, c'est le programme PC qui la
## pilote). Les mesures sont suspendues pendant ce temps.
## `cran_courant` : lu par les constructeurs (relief, panorama) pour choisir
## la taille des textures et la finesse des maillages.

const CRAN_MAX: int = 6
const IPS_REDUITE: int = 5
const IPS_ARRIERE_PLAN: int = 20
static var cran_courant: int = 0
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
## Les trois chronomètres de l'image (ms) : fil principal (logique du jeu),
## fil de rendu (tri, ordres de dessin), carte graphique — pour agir sur le
## bon levier.
var _t_princ: PackedFloat32Array = []
var _t_rendu: PackedFloat32Array = []
var _t_gpu: PackedFloat32Array = []
var cause: String = ""              # dernier goulot : gpu / rendu / principal / autre
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
var _retrait: int = 0                # 0 au premier plan, 1 arrière-plan, 2 réduite
var _t_retrait: float = 0.0


func setup(p_main: Node, p_env: Environment, p_mode: String) -> void:
	main = p_main
	# plafond passé au lancement (--max-fps, vue embarquée sous XWayland
	# sans V-Sync : 13/10/2026) — gardé : sans lui, la carte calculerait des
	# centaines d'images pour rien
	_ips_base = Engine.max_fps
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
	var plancher_web: int = 4  # PWA : départ au réglage bas (mesuré sur iPad)
	if _web:
		# la PWA DÉMARRE au cran 4 mais peut REMONTER jusqu'au rendu à 100 %
		# (cran 2) si l'appareil a de la marge — avant, elle restait à 70 %
		# au mieux et le pupitre était illisible (retour d'utilisateur, 09/10/2026)
		cran_min = 2
	var depart: int = maxi(_cran_de_depart(), plancher_web) if (_web and mode == "auto") else _cran_de_depart()
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
	# écran très défini (> 2560 × 1600) : rendu 3D réduit d'office — sauf carte
	# dédiée (relevés du 26/10/2026 : écran 4K + RTX 5070 Ti → cran 3, sans
	# éclairage indirect ni anti-crénelage, pour une carte à 1 ms par image)
	var ecran: Vector2i = machine.get("ecran", Vector2i(1920, 1080))
	if ecran.x * ecran.y > 2560 * 1600 and t != "dedie":
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
		_env.glow_enabled = cran <= (4 if _web else 3)
	cran_courant = cran
	_appliquer_ips()
	var vp: Viewport = main.get_viewport() if main != null else null
	if vp != null:
		if not _web:
			# MSAA ×4 garanti aux crans 0-2 (diagnostic du 08/10/2026 sur le
			# PC du père : « crénelage net au réglage haute ») — on ne se fie
			# plus à la valeur lue sur la fenêtre, on l'impose
			vp.msaa_3d = maxi(_msaa_origine, Viewport.MSAA_4X) if cran <= 2 else Viewport.MSAA_DISABLED
		var echelle: float = _echelle(cran)
		if echelle < 0.999:
			# FSR 2 (reconstruction temporelle) garde les textes nets ; FSR 1
			# en Mobile ; bilinéaire en OpenGL
			if RenderingServer.get_current_rendering_method() == "forward_plus":
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			elif _rd:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			else:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = echelle
	_t_chauffe = maxf(_t_chauffe, APRES_CHANGEMENT_S)
	_durees.clear()
	_t_fen = 0.0
	_bonnes = 0
	var aa: String = ""
	if vp != null:
		aa = [" ; MSAA –", " ; MSAA ×2", " ; MSAA ×4", " ; MSAA ×8"][clampi(vp.msaa_3d, 0, 3)] \
			+ " ; rendu %d %%" % int(round(vp.scaling_3d_scale * 100.0))
	_log("[Perf] cran %d/%d — %s (%s)%s%s" % [cran, CRAN_MAX, libelle(cran), pourquoi, aa,
		(" — " + dernier_bilan) if dernier_bilan != "" else ""])
	# le PC l'écrit dans son journal de bord (« c'est super pixélisé » :
	# on veut savoir où en est la 3D)
	if main != null:
		var sr: Node = main.get("state_receiver") as Node
		if sr != null and sr.has_method("envoyer"):
			sr.envoyer({"perf": cran, "perf_max": CRAN_MAX, "perf_txt": "%s (%s)%s%s" % [
				libelle(cran), pourquoi, aa, (" — " + dernier_bilan) if dernier_bilan != "" else ""]})


## Échelle du rendu 3D au cran `c` : PC jamais sous 85 %, PWA comme mesuré.
func _echelle(c: int) -> float:
	if _web:
		return [1.0, 1.0, 1.0, 0.85, 0.7, 0.6, 0.6][c]
	return [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.85][c]


## Ce que fait le cran `c`, en clair (journal, PC).
func libelle(c: int) -> String:
	if _web:
		return ["tout", "sans éclairage indirect", "sans brouillard ni reflets",
			"sans anti-crénelage, rendu 85 %", "rendu 70 %", "rendu 60 %, sans halo",
			"30 i/s"][c]
	return ["tout", "sans éclairage indirect", "sans brouillard ni reflets",
		"sans anti-crénelage", "sans halo", "30 i/s", "rendu à 85 %"][c]


## Plafond d'images par seconde : cran 6 (30 i/s) et retrait de la fenêtre.
var _ips_base: int = 0


func _appliquer_ips() -> void:
	var ips: int = 30 if cran >= (6 if _web else 5) else 0
	if _ips_base > 0:
		ips = _ips_base if ips == 0 else mini(ips, _ips_base)
	if _retrait == 2:
		ips = IPS_REDUITE
	elif _retrait == 1:
		ips = IPS_ARRIERE_PLAN if ips == 0 else mini(ips, IPS_ARRIERE_PLAN)
	Engine.max_fps = ips


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_verifier_retrait()


## Fenêtre réduite / en arrière-plan (version autonome seulement).
## Bancs de mesure avec fenêtre : pas de bridage quand la fenêtre perd le
## focus (relevés du PC à distance, 26/10/2026 : passe faussée à 20 i/s).
var banc: bool = false


func _verifier_retrait() -> void:
	if _web or main == null or bool(main.get("client_mode")) \
			or DisplayServer.get_name() == "headless" or banc:
		return
	var r: int = 0
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		r = 2
	elif not DisplayServer.window_is_focused():
		r = 1
	if r == _retrait:
		return
	_retrait = r
	_appliquer_ips()
	# les images au ralenti ne sont pas des saccades : on reprend les
	# mesures de zéro au retour
	_durees.clear()
	_t_fen = 0.0
	_t_chauffe = maxf(_t_chauffe, APRES_CHANGEMENT_S)
	_log("[Perf] fenêtre %s" % ["au premier plan", "en arrière-plan (%d i/s)" % IPS_ARRIERE_PLAN,
		"réduite (%d i/s)" % IPS_REDUITE][r])


# --- Mesure en direct -------------------------------------------------------

func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("perf_manager", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(_delta: float) -> void:
	if main == null:
		return
	var t_us: int = Time.get_ticks_usec()
	if _t_prec_us == 0:
		_t_prec_us = t_us
		return
	var dt: float = float(t_us - _t_prec_us) / 1.0e6
	_t_prec_us = t_us
	# image de plus d'une seconde : la 3D a calé. Embarquée sous Windows, sa
	# fenêtre est l'enfant de celle du simulateur, qui peut caler avec elle →
	# on l'écrit, heure comprise, pour la croiser avec les rapports de gel
	if dt > 1.0:
		_log("[Gel3D] image de %.1f s, finie à %s" % [dt, Time.get_time_string_from_system()])
	_horloge += dt
	_t_retrait += dt
	if _t_retrait >= 1.0:
		_t_retrait = 0.0
		_verifier_retrait()
	if _retrait != 0:
		return
	if _t_chauffe > 0.0:
		_t_chauffe -= dt
		return
	_durees.append(dt)
	_t_princ.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	# (une image sur quatre : avec un fil de rendu séparé, chaque lecture le
	# synchronise — relevés du PC du 26/10/2026)
	if _mesure_gpu and Engine.get_process_frames() % 4 == 0:
		_t_rendu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid))
		_t_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	_releve_image(dt)
	_t_fen += dt
	if _t_fen < FENETRE_S:
		return
	_evaluer()
	_durees.clear()
	_t_princ.clear()
	_t_rendu.clear()
	_t_gpu.clear()
	_t_fen = 0.0


func _evaluer() -> void:
	var n: int = _durees.size()
	if n < 10:
		return
	var cible_ips: float = 30.0 if cran >= (6 if _web else 5) else minf(60.0, machine.get("hz", 60.0))
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
	# les trois chronomètres, au 90e centile de la fenêtre (les pointes comptent)
	var princ_ms: float = _p90(_t_princ)
	var rendu_ms: float = _p90(_t_rendu)
	var gpu_ms: float = _p90(_t_gpu)
	var b_ms: float = budget * 1000.0
	dernier_bilan = "%.0f i/s, à-coups %.1f %%, 1 %% pires %.0f ms — principal %.1f / rendu %.1f / GPU %.1f ms" % [
		ips, taux * 100.0, p99 * 1000.0, princ_ms, rendu_ms, gpu_ms]
	if mode != "auto":
		return
	var mauvais: bool = ips < 0.83 * cible_ips or taux > 0.03 or p99 > 3.0 * budget
	var rm: Node = main.get("remontees") if main != null else null
	if mauvais:
		_bonnes = 0
		# le goulot : le plus chargé des trois (sans mesure, la carte, comme avant) —
		# 26/10/2026 : « il utilise à fond la carte graphique selon sa présence et ses
		# performances, et tous les cœurs » ; avant, GPU < 40 % du budget → rien,
		# sinon on retirait des effets même quand le processeur était la cause
		cause = "gpu"
		if gpu_ms > 0.0:
			if rendu_ms >= gpu_ms and rendu_ms >= princ_ms:
				cause = "rendu"
			elif princ_ms > gpu_ms:
				cause = "principal"
			if maxf(gpu_ms, maxf(rendu_ms, princ_ms)) < 0.5 * b_ms:
				cause = "autre"           # saccades sans chronomètre chargé : chargement, disque
		dernier_bilan += " → " + cause
		match cause:
			"gpu":
				if cran < CRAN_MAX:
					if _cran_avant_montee >= 0 and _horloge - _derniere_montee_t < 20.0:
						_echecs[cran] = _horloge + ECHEC_INTERDIT_S
						_cran_avant_montee = -1
					_appliquer(cran + 1, "saccades, carte graphique")
			"rendu", "principal":
				# moins d'objets à trier et à simuler ; le détail au minimum, les
				# effets (jamais le plafond à 30 i/s ni la résolution : sans effet ici)
				# (jamais les effets : la carte graphique n'y est pour rien — relevés
				# du PC du 26/10/2026 : cran 4 « sans halo » pour un GPU à 0,6 ms)
				if rm != null and int(rm.get("niveau_detail")) < 2:
					rm.call("set_niveau_detail", int(rm.get("niveau_detail")) + 1)
					_log("[Perf] remontées : détail %d/2 (saccades, fil %s)" % [int(rm.get("niveau_detail")), cause])
					_t_chauffe = maxf(_t_chauffe, APRES_CHANGEMENT_S)
		return
	var bon: bool = ips >= 0.95 * cible_ips and taux < 0.005
	if not bon:
		_bonnes = 0
		return
	_bonnes += 1
	if _bonnes < MONTEE_BONNES_FENETRES:
		return
	# marge durable : d'abord rendre le détail des remontées (si les deux fils
	# du processeur ont de la marge), ensuite seulement remettre un effet
	if rm != null and int(rm.get("niveau_detail")) > 0 and gpu_ms > 0.0 \
			and princ_ms < 0.5 * b_ms and rendu_ms < 0.5 * b_ms:
		rm.call("set_niveau_detail", int(rm.get("niveau_detail")) - 1)
		_log("[Perf] remontées : détail %d/2 (marge)" % int(rm.get("niveau_detail")))
		_bonnes = 0
		_t_chauffe = maxf(_t_chauffe, APRES_CHANGEMENT_S)
		return
	if cran <= cran_min:
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


func _p90(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var t: PackedFloat32Array = a.duplicate()
	t.sort()
	return t[mini(t.size() - 1, int(t.size() * 0.9))]


# --- relevé en jeu --------------------------------------------------------------
## Touche F10 : une minute d'enregistrement, image par image (les quatre temps,
## appels de dessin, objets, primitives, cran, détail, position du skieur),
## en CSV dans le dossier utilisateur + un résumé dans le journal — pour
## dimensionner les optimisations sur des chiffres réels (26/10/2026).
const RELEVE_S: float = 60.0
var _rel: PackedStringArray = PackedStringArray()
var _rel_t: float = -1.0


## Relevé en cours ? (le bouton MESURE l'affiche)
func releve_en_cours() -> bool:
	return _rel_t >= 0.0


func releve() -> void:
	if _rel_t >= 0.0:
		_finir_releve()
		return
	_rel_t = 0.0
	Prof.t.clear()
	Prof.actif = true
	_rel = PackedStringArray(["t_s;image_ms;principal_ms;rendu_ms;gpu_ms;appels;objets;primitives;cran;detail;x;y;z;construit"])
	_log("[Relevé] enregistrement %d s…" % int(RELEVE_S))
	if main != null and main.has_method("_flash"):
		main.call("_flash", "Relevé de fluidité : %d s — skiez, prenez une remontée…" % int(RELEVE_S))


func _releve_image(dt: float) -> void:
	if _rel_t < 0.0:
		return
	_rel_t += dt
	var sk: Node3D = main.get("skieur") as Node3D if main != null else null
	var p: Vector3 = sk.global_position if sk != null and sk.get("actif") else Vector3.ZERO
	var rm: Node = main.get("remontees") if main != null else null
	var ec: Node = rm.get("_en_cours") if rm != null else null
	_rel.append("%.3f;%.2f;%.2f;%.2f;%.2f;%d;%d;%d;%d;%d;%.0f;%.0f;%.0f;%s" % [
		_rel_t, dt * 1000.0, _t_princ[_t_princ.size() - 1] if not _t_princ.is_empty() else 0.0,
		_t_rendu[_t_rendu.size() - 1] if not _t_rendu.is_empty() else 0.0,
		_t_gpu[_t_gpu.size() - 1] if not _t_gpu.is_empty() else 0.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		cran, int(rm.get("niveau_detail")) if rm != null else 0, p.x, p.y, p.z,
		str(ec.name) if ec != null else ""])
	if _rel_t >= RELEVE_S:
		_finir_releve()


func _finir_releve() -> void:
	var n: int = _rel.size() - 1
	_rel_t = -1.0
	Prof.actif = false
	if n < 10:
		return
	var cols: Dictionary = {"image": [], "principal": [], "rendu": [], "gpu": [], "appels": [], "objets": []}
	for k in range(1, _rel.size()):
		var c: PackedStringArray = _rel[k].split(";")
		cols["image"].append(float(c[1]))
		cols["principal"].append(float(c[2]))
		cols["rendu"].append(float(c[3]))
		cols["gpu"].append(float(c[4]))
		cols["appels"].append(float(c[5]))
		cols["objets"].append(float(c[6]))
	var horo: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var base: String = "user://releve_perf_%s" % horo
	var f: FileAccess = FileAccess.open(base + ".csv", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_rel))
	var r: PackedStringArray = PackedStringArray()
	r.append("Relevé de fluidité — %s — %d images en %.0f s" % [_resume_machine(), n, RELEVE_S])
	r.append("cran %d/%d — %s" % [cran, CRAN_MAX, libelle(cran)])
	for nom in ["image", "principal", "rendu", "gpu"]:
		var a: Array = cols[nom]
		a.sort()
		var moy: float = 0.0
		for x in a:
			moy += x
		r.append("  %-10s moy %6.2f · médiane %6.2f · p95 %6.2f · p99 %6.2f · max %6.1f ms" % [
			nom, moy / a.size(), a[a.size() / 2], a[int(a.size() * 0.95)], a[int(a.size() * 0.99)], a[a.size() - 1]])
	var ap: Array = cols["appels"]
	ap.sort()
	var ob: Array = cols["objets"]
	ob.sort()
	r.append("  appels de dessin : médiane %d · max %d ; objets : médiane %d · max %d" % [
		ap[ap.size() / 2], ap[ap.size() - 1], ob[ob.size() / 2], ob[ob.size() - 1]])
	# temps par système (enveloppes des _process : voir Prof), ms par image
	var sys: Array = Prof.t.keys()
	sys.sort_custom(func(a, b): return Prof.t[a] > Prof.t[b])
	var somme: float = 0.0
	r.append("  par système (ms par image, fil principal) :")
	for k in sys:
		var ms: float = float(Prof.t[k]) / 1000.0 / n
		somme += ms
		if ms >= 0.05:
			r.append("    %-26s %6.2f" % [k, ms])
	var img: Array = cols["image"]
	var moy_img: float = 0.0
	for x in img:
		moy_img += x
	moy_img /= maxf(1.0, img.size())
	r.append("    %-26s %6.2f   (physique, rendu, moteur : image moyenne − scripts)" % ["(reste)", moy_img - somme])
	var fr: FileAccess = FileAccess.open(base + ".txt", FileAccess.WRITE)
	if fr != null:
		fr.store_string("\n".join(r))
	for l in r:
		_log("[Relevé] " + l)
	_log("[Relevé] fichiers : %s" % ProjectSettings.globalize_path(base + ".csv"))
	_envoyer_releve(r)


## Le relevé part au point de collecte des rapports (celui des erreurs de la
## PWA : plafonné, rangé hors du site, une alerte au NAS) — sur l'iPad on ne
## peut pas récupérer un fichier du dossier utilisateur (demande d'un
## utilisateur, 26/10/2026 : « ajoute le bouton »). Le résumé, et les images
## lentes (> 25 ms) image par image : tout tient sous 256 Kio.
const COLLECTE: String = "https://fenice.giff.re/rapports/collecte.php"


func _envoyer_releve(r: PackedStringArray) -> void:
	var lentes: PackedStringArray = PackedStringArray([_rel[0]])
	for k in range(1, _rel.size()):
		if float(_rel[k].split(";")[1]) > 25.0 and lentes.size() < 1500:
			lentes.append(_rel[k])
	var ua: String = ""
	if _web:
		ua = str(JavaScriptBridge.eval("navigator.userAgent", true))
	var rapport: Dictionary = {
		"genre": "releve_perf",
		"version": PNConstants.VERSION_APP,
		"poste": ("PWA " if _web else "PC ") + str(machine.get("gpu", "?")),
		"os": OS.get_name() + ((" — " + ua) if ua != "" else ""),
		"resume": "\n".join(r.slice(2, 7)),
		"releve": "\n".join(r),
		"images_lentes": "\n".join(lentes),
	}
	var corps: String = JSON.stringify(rapport)
	if corps.length() > 250000:
		rapport["images_lentes"] = "\n".join(lentes.slice(0, 400))
		corps = JSON.stringify(rapport)
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	req.timeout = 20.0
	req.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		req.queue_free()
		var ok: bool = code >= 200 and code < 300
		_log("[Relevé] envoi au NAS : %s (%d)" % ["fait" if ok else "échec", code])
		if main != null and main.has_method("_flash"):
			main.call("_flash", "Relevé de fluidité envoyé — merci !" if ok else "Relevé : envoi impossible (%d)" % code))
	var en_tetes: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"X-App: %s/%s" % ["funiculaire-pwa" if _web else "funiculaire-pc", PNConstants.VERSION_APP]])
	if req.request(COLLECTE, en_tetes, HTTPClient.METHOD_POST, corps) != OK:
		req.queue_free()
		if main != null and main.has_method("_flash"):
			main.call("_flash", "Relevé : envoi impossible")


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
