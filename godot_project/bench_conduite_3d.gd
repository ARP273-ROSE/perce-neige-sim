## Banc de conduite du skieur au doigt et au clavier (retour d'utilisateur, 16/11/2026, iPad : « c'est la merde
## totale à diriger. Quand je pivote à l'arrêt la caméra ne suit pas, au bout d'un moment j'avance de travers avec la
## caméra qui regarde pas où va le skieur, du coup je me prends des murs ou j'arrive pas à monter des escaliers »).
## Les doigts passent par le vrai chemin (Input.parse_input_event → CommandesSkieur) : pouce du joystick flottant à
## gauche, doigt de la vue à droite. On mesure :
##  - PIVOT : pouce poussé de côté à l'arrêt — la vue doit revenir derrière la marche (écart final < 20°) ;
##  - DIAGONALE : pouce tenu à 45° — vue derrière la marche, cap stable (pas de spirale) ;
##  - VUE PUIS AVANT : vue tournée au doigt, lâchée, puis pouce vers l'avant — il part où regarde la vue ;
##  - SKI À L'ARRÊT : skis pivotés au pouce — la vue suit le cap des skis ;
##  - ESCALIER : de la place, pouce vers l'avant — il monte l'escalier de la gare du funi jusqu'au palier ;
## en 3e et en 1re personne.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_conduite_3d.gd -- --mode=normal [--mesure]
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _mesure: bool = false
var _sc: int = -1
var _t: float = 0.0
var _etat: Dictionary = {}

const SCENARIOS: Array = [
	["pied_pivot", false], ["pied_pivot", true], ["pied_diagonale", false], ["pied_vue_puis_avant", false],
	["ski_pivot_arret", false], ["escalier", false], ["escalier", true], ["escalier_biais", false],
]


func _initialize() -> void:
	_mesure = "--mesure" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	if _mesure:
		print("[MESURE] %s — %s" % [label, detail])
		return
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


## Doigt `idx` (0 : pouce du joystick, 1 : vue) en coordonnées de la vue.
func _toucher(idx: int, pos_vue: Vector2, appuye: bool) -> void:
	var ft: Transform2D = get_root().get_final_transform()
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = idx
	t.position = ft * pos_vue
	t.pressed = appuye
	Input.parse_input_event(t)


func _glisser(idx: int, pos_vue: Vector2, rel: Vector2) -> void:
	var ft: Transform2D = get_root().get_final_transform()
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = idx
	d.position = ft * pos_vue
	d.relative = ft.basis_xform(rel)
	Input.parse_input_event(d)


func _taille() -> Vector2:
	return get_root().get_visible_rect().size


func _pouce_centre() -> Vector2:
	return Vector2(_taille().x * 0.22, _taille().y * 0.7)


## Pouce posé puis tiré dans la direction `a` (0 haut, + droite), à fond.
var _pouce_pose: bool = false


func _pouce(a: float) -> void:
	# (posé une seule fois, comme un vrai pouce : un deuxième appui sans lever devenait le doigt de la vue)
	var c: Vector2 = _pouce_centre()
	if not _pouce_pose:
		_toucher(0, c, true)
		_pouce_pose = true
	var p: Vector2 = c + Vector2(sin(a), -cos(a)) * 90.0
	_glisser(0, p, p - c)


func _lacher_pouce() -> void:
	_toucher(0, _pouce_centre(), false)
	_pouce_pose = false


static func _deg(a: float) -> float:
	return rad_to_deg(absf(wrapf(a, -PI, PI)))


func _poser(sk: SkieurJoueur, ski: bool, pos: Vector3, cap: float, premiere: bool) -> void:
	_lacher_pouce()
	_toucher(1, Vector2(_taille().x * 0.75, _taille().y * 0.5), false)
	sk.entree = Vector2.ZERO
	sk.touches_ext = 0
	sk._pouce_tenu = false
	sk.chemin.clear()
	if sk.chausse:
		_main.basculer_ski()
	sk.activer(pos, cap)
	sk.cam_yaw = cap
	sk._cap = cap
	sk._vue_libre = 99.0
	if sk.premiere_personne != premiere and _main.get("commandes_skieur") != null:
		_main.commandes_skieur.basculer_vue()
	sk.premiere_personne = premiere
	if ski:
		_main.basculer_ski()
		sk._cap_ski = cap
		sk._v_ski = Vector3.ZERO
	_t = 0.0
	_etat = {"p0": sk.global_position, "cap0": cap, "caps": []}


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / 60.0
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		return
	var sk: SkieurJoueur = _main.get("skieur")
	if _sc < 0:
		if sk == null or not sk.actif:
			if _f % 30 == 0:
				_main.basculer_skieur()
			return
		# panneau de scénario fermé : il prendrait les doigts
		var sp: Node = _main.get("scenario_panel") as Node
		if sp != null and sp is CanvasItem:
			(sp as CanvasItem).visible = false
		_sc = 0
		_debut(sk)
		return
	_t += dt
	var nom: String = SCENARIOS[_sc][0]
	var prem: bool = SCENARIOS[_sc][1]
	var tag: String = nom + (" (1re pers.)" if prem else " (3e pers.)")
	var vh: Vector3 = Vector3(sk.velocity.x, 0.0, sk.velocity.z)
	var cap_marche: float = atan2(-vh.x, -vh.z) if vh.length() > 0.3 else sk._cap
	match nom:
		"pied_pivot":
			if _f % 6 == 0:
				_pouce(-PI * 0.5)
			if _t > 4.0:
				var ecart: float = _deg(sk.cam_yaw - cap_marche)
				_verif("%s : pouce à gauche à l'arrêt, la vue revient derrière la marche" % tag, ecart < 20.0,
					"écart vue / marche %.0f° après 4 s, %.1f m faits" % [ecart, (sk.global_position - _etat["p0"]).length()])
				_suivant(sk)
		"pied_diagonale":
			if _f % 6 == 0:
				_pouce(PI * 0.25)
			if _t > 2.0:
				(_etat["caps"] as Array).append(cap_marche)
			if _t > 6.0:
				var caps: Array = _etat["caps"]
				var derive: float = _deg(caps[caps.size() - 1] - caps[0])
				var ecart: float = _deg(sk.cam_yaw - cap_marche)
				_verif("%s : pouce à 45°, vue derrière, cap stable" % tag, ecart < 15.0 and derive < 10.0,
					"écart vue / marche %.0f°, dérive du cap %.0f° sur 4 s" % [ecart, derive])
				_suivant(sk)
		"pied_vue_puis_avant":
			var c1: Vector2 = Vector2(_taille().x * 0.6, _taille().y * 0.25)
			if _t < 1.0:
				if _f % 2 == 0:
					if not _etat.has("vue_pose"):
						_toucher(1, c1, true)
						_etat["vue_pose"] = true
						_etat["x"] = c1.x
					_etat["x"] += 8.0
					if _mesure and int(_t * 60.0) % 20 == 0:
						var cs: Node = _main.get("commandes_skieur")
						print("   vue : doigt_vue=%s doigt_joy=%s cam=%.0f° visible=%s taille=%s" % [str(cs.get("_doigt_vue")), str(cs.get("_doigt_joy")), rad_to_deg(sk.cam_yaw), str(cs.visible), str(_taille())])
					_glisser(1, Vector2(_etat["x"], c1.y), Vector2(8.0, 0.0))
			elif _t < 1.2:
				if _etat.has("vue_pose"):
					_toucher(1, Vector2(_etat["x"], c1.y), false)
					_etat.erase("vue_pose")
					_etat["cam_lache"] = sk.cam_yaw
			else:
				if _f % 6 == 0:
					_pouce(0.0)
				if _t > 4.2:
					var e_dep: float = _deg(cap_marche - float(_etat["cam_lache"]))
					var tourne: float = _deg(float(_etat["cam_lache"]) - float(_etat["cap0"]))
					_verif("%s : vue tournée au doigt puis pouce vers l'avant, il part où regarde la vue" % tag,
						e_dep < 10.0 and tourne > 30.0, "vue tournée de %.0f°, marche à %.0f° de la vue" % [tourne, e_dep])
					_suivant(sk)
		"ski_pivot_arret":
			if _f % 6 == 0:
				_pouce(PI * 0.5)
			if _t > 3.5:
				var ecart: float = _deg(sk.cam_yaw - sk._cap_ski)
				var pivot: float = _deg(sk._cap_ski - float(_etat["cap0"]))
				_verif("%s : skis pivotés au pouce à l'arrêt, la vue suit" % tag, ecart < 30.0 and pivot > 30.0,
					"skis tournés de %.0f°, écart vue / skis %.0f°" % [pivot, ecart])
				_suivant(sk)
		"escalier", "escalier_biais":
			if _f % 6 == 0:
				_pouce(0.0 if nom == "escalier" else 0.0)
			if _mesure and int(_t * 60.0) % 60 == 0:
				print("   t=%.0f pos=%s entree=%s cam=%.0f° cap=%.0f° v=%s" % [_t, str(sk.global_position.snapped(Vector3.ONE * 0.01)), str(sk.entree), rad_to_deg(sk.cam_yaw), rad_to_deg(sk._cap), str(vh.snapped(Vector3.ONE * 0.01))])
			if _t > 12.0:
				var monte: float = sk.global_position.y - (_etat["p0"] as Vector3).y
				var h: float = float(_etat.get("h_escalier", 1.0))
				var ecart: float = _deg(sk.cam_yaw - cap_marche)
				_verif("%s : de la place, pouce vers l'avant, il monte l'escalier de la gare du funi" % tag,
					monte > h - 0.4, "monté de %.2f m sur %.2f m, écart vue / marche %.0f°" % [monte, h, ecart])
				_suivant(sk)


func _debut(sk: SkieurJoueur) -> void:
	var nom: String = SCENARIOS[_sc][0]
	var prem: bool = SCENARIOS[_sc][1]
	var gare: Node = _main.station_halls.gare_aval if _main.get("station_halls") != null else null
	var dep: Array = gare.point_depart() if gare != null else [sk.global_position, 0.0]
	var pos: Vector3 = dep[0]
	var cap: float = dep[1]
	match nom:
		"escalier":
			_poser(sk, false, pos, cap, prem)
		"escalier_biais":
			# face 40° à côté de l'escalier : on tourne la vue au doigt vers lui, puis pouce vers l'avant
			_poser(sk, false, pos, cap + deg_to_rad(40.0), prem)
			sk.cam_yaw = cap
			sk._vue_libre = 0.0
		_:
			# sur la place, dos à l'escalier : de la place devant soi
			_poser(sk, nom == "ski_pivot_arret", pos, cap + PI, prem)
	if nom.begins_with("escalier") and gare != null:
		_etat["h_escalier"] = float(gare.get("_o").y) - GareAval.H_PLACE_ABS - 0.4


func _suivant(sk: SkieurJoueur) -> void:
	_lacher_pouce()
	_sc += 1
	if _sc >= SCENARIOS.size():
		print("BENCH_CONDUITE " + ("OK" if _ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if _ok else 1)
		return
	_debut(sk)
