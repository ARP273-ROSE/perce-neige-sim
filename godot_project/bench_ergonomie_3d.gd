## Banc d'ergonomie des commandes du skieur (retour d'utilisateur, 12/10/2026 :
## « c'est infernal de diriger le skieur, avec en plus une vue qui bouge à
## chaque mouvement de joystick ou de virage »). Un joueur simulé tient le
## joystick ou les touches comme un humain et l'on mesure :
##  - DÉRIVE : de combien le cap des skis tourne quand le pouce reste
##    immobile (une visée fixe doit donner un cap fixe, pas une spirale) ;
##  - ERREUR : écart entre le cap visé (par rapport à la vue au moment où
##    l'on pose le pouce) et le cap obtenu ;
##  - VUE : vitesse de rotation de la caméra (p95 et maxi, °/s) — au-delà
##    de ~90 °/s, une rotation qu'on n'a pas commandée donne le tournis ;
##  - À PIED : la direction de marche ne doit pas changer quand on tourne la
##    vue sans bouger le pouce.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_ergonomie_3d.gd -- --mode=normal
## --mesure : affiche sans juger (comparaison avant / après).
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t: float = 0.0
var _ok: bool = true
var _mesure: bool = false
var _sc: int = -1
var _t_sc: float = 0.0
var _p0: Vector3 = Vector3.ZERO
var _cap0: float = 0.0
var _cam_prec: float = 0.0
var _taux: Array = []
var _caps: Array = []
var _err: Array = []
var _dir_marche: Array = []
var _ref: float = 0.0
var _pitch0: float = 0.0
var _pos0: Vector3 = Vector3.ZERO


## Un doigt sur l'écran, comme Safari sur iPad : l'événement tactile, et la
## « souris » que le navigateur en tire (périphérique 0, bouton gauche).
func _doigt(pos_vue: Vector2, appuye: bool, glisse_vue: Vector2 = Vector2.ZERO) -> void:
	# l'événement arrive en coordonnées de FENÊTRE ; Godot le ramène à
	# l'échelle du rendu (étirement du contenu)
	var ft: Transform2D = get_root().get_final_transform()
	var pos: Vector2 = ft * pos_vue
	var glisse: Vector2 = ft.basis_xform(glisse_vue)
	if glisse == Vector2.ZERO:
		var t: InputEventScreenTouch = InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = appuye
		Input.parse_input_event(t)
	else:
		var d: InputEventScreenDrag = InputEventScreenDrag.new()
		d.index = 0
		d.position = pos
		d.relative = glisse
		Input.parse_input_event(d)
		var m: InputEventMouseMotion = InputEventMouseMotion.new()
		m.device = 0
		m.position = pos
		m.relative = glisse
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)

const SCENARIOS: Array = ["visee_15", "visee_90", "slalom", "clavier", "pied_vue", "pied_tactile", "pied_clavier_souris"]


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


func _fin() -> void:
	print("BENCH_ERGONOMIE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _pente(sk: SkieurJoueur) -> float:
	# cap de la ligne de plus grande pente (vers l'aval)
	var n: Vector3 = _main.relief.normale_sol(sk.global_position.x, sk.global_position.z)
	return atan2(-n.x, -n.z) + PI


func _poser(sk: SkieurJoueur, ski: bool) -> void:
	sk.entree = Vector2.ZERO
	sk.touches_ext = 0
	sk.chemin.clear()
	if sk.chausse:
		_main.basculer_ski()
	var relief: ReliefBuilder = _main.relief
	sk.activer(Vector3(_p0.x, relief.hauteur_sol(_p0.x, _p0.z) + 0.1, _p0.z), 0.0)
	var cap: float = _pente(sk)
	sk.cam_yaw = cap
	sk._cap = cap
	if ski:
		_main.basculer_ski()
		sk._cap_ski = cap
		sk._v_ski = Vector3(-sin(cap), 0.0, -cos(cap)) * 6.0
	_cap0 = cap
	_ref = cap
	_cam_prec = sk.cam_yaw
	_taux.clear()
	_caps.clear()
	_err.clear()
	_dir_marche.clear()
	_t_sc = 0.0


static func _p(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)]


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / 60.0
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret or _main.get("domaine") == null and _f < 20000:
		if _f == 1:
			pass
		if relief == null or not relief.pret:
			return
	var sk: SkieurJoueur = _main.get("skieur")
	if _sc < 0:
		if sk == null or not sk.actif:
			if _f % 30 == 0:
				_main.basculer_skieur()
			return
		var pts: PackedVector2Array = FantomesDonnees.points(3)
		var q: Vector2 = pts[int(pts.size() * 0.45)]
		_p0 = Vector3(q.x, 0.0, q.y)
		_sc = 0
		_poser(sk, true)
		return
	_t_sc += dt
	var nom: String = SCENARIOS[_sc]
	# vitesse de rotation de la vue (°/s)
	var dy: float = rad_to_deg(absf(wrapf(sk.cam_yaw - _cam_prec, -PI, PI))) / dt
	_cam_prec = sk.cam_yaw
	if _t_sc > 0.5:
		_taux.append(dy)
	var duree: float = 12.0
	match nom:
		"visee_15", "visee_90":
			var a: float = deg_to_rad(15.0 if nom == "visee_15" else 90.0)
			sk.entree = Vector2(sin(a), cos(a)) * 0.9
			_caps.append(sk._cap_ski)
			if _t_sc > 6.0:
				_err.append(rad_to_deg(absf(wrapf(sk._cap_ski - (_ref - a), -PI, PI))))
		"slalom":
			# virages de ±45° toutes les 2,5 s, pouce relevé 0,3 s entre deux
			var ph: float = fmod(_t_sc, 2.5)
			var cote: float = 1.0 if int(_t_sc / 2.5) % 2 == 0 else -1.0
			if ph < 0.3:
				sk.entree = Vector2.ZERO
				_ref = sk.cam_yaw
			else:
				var a2: float = deg_to_rad(45.0) * cote
				sk.entree = Vector2(sin(a2), cos(a2)) * 0.9
				if ph > 1.8:
					_err.append(rad_to_deg(absf(wrapf(sk._cap_ski - (_ref - a2), -PI, PI))))
			duree = 15.0
		"clavier":
			# D 1,5 s, rien 2 s, Q 1,5 s, rien 2 s…
			var ph2: float = fmod(_t_sc, 7.0)
			sk.touches_ext = 8 if ph2 < 1.5 else (4 if (ph2 > 3.5 and ph2 < 5.0) else 0)
			duree = 14.0
		"pied_tactile":
			# pouce posé en bas à gauche, glissé de 80 px vers le haut et tenu
			var base: Vector2 = Vector2(150.0, get_root().get_visible_rect().size.y - 150.0)
			if _t_sc < 0.05:
				if _pos0 == Vector3.ZERO:
					_pitch0 = sk.cam_pitch
					_pos0 = sk.global_position
					_doigt(base, true)
			elif _t_sc < 0.6:
				_doigt(base - Vector2(0.0, 80.0 * _t_sc / 0.6), true, Vector2(0.0, -80.0 * dt / 0.6))
			elif _t_sc < 3.5:
				_doigt(base - Vector2(0.0, 80.0), true, Vector2(0.0, -0.5))
			elif _t_sc < 3.6:
				_doigt(base - Vector2(0.0, 80.0), false)
			duree = 4.0
		"pied_clavier_souris":
			# PC : Z tenu, la souris tourne la vue de 90° en 1 s — il doit
			# aller là où l'on regarde (retour d'utilisateur, 15/10/2026)
			sk.touches_ext = 1
			if _t_sc > 2.0 and _t_sc < 3.0:
				sk.tourner_vue(Vector2(-deg_to_rad(90.0) / 0.006 * dt, 0.0))
			var v2: Vector3 = Vector3(sk.velocity.x, 0.0, sk.velocity.z)
			if v2.length() > 0.5:
				_dir_marche.append(atan2(-v2.x, -v2.z))
			duree = 5.0
		"pied_vue":
			# pouce en haut, et l'autre doigt tourne la vue de 90° en 1 s
			sk.entree = Vector2(0.0, 0.9)
			if _t_sc > 2.0 and _t_sc < 3.0:
				sk.tourner_vue(Vector2(-deg_to_rad(90.0) / 0.006 * dt, 0.0))
			var v: Vector3 = Vector3(sk.velocity.x, 0.0, sk.velocity.z)
			if v.length() > 0.5:
				_dir_marche.append(atan2(-v.x, -v.z))
			duree = 5.0
	if _t_sc < duree:
		return
	sk.entree = Vector2.ZERO
	sk.touches_ext = 0
	var p95: float = _p(_taux, 0.95)
	var mx: float = _p(_taux, 1.0)
	match nom:
		"visee_15", "visee_90":
			var n: int = _caps.size()
			var derive: float = rad_to_deg(absf(wrapf(_caps[n - 1] - _caps[n / 2], -PI, PI)))
			var em: float = 0.0
			for e in _err:
				em += e
			em /= maxf(1.0, _err.size())
			_verif("pouce immobile à %s : cap stable (pas de spirale)" % ("15°" if nom == "visee_15" else "90°"),
				derive < 15.0 and em < 15.0,
				"dérive %.0f° sur 6 s, erreur moyenne %.0f°, vue p95 %.0f °/s, maxi %.0f °/s" % [derive, em, p95, mx])
		"slalom":
			var em2: float = 0.0
			for e in _err:
				em2 += e
			em2 /= maxf(1.0, _err.size())
			_verif("slalom au pouce : la vue suit sans donner le tournis",
				em2 < 20.0 and p95 < 60.0 and mx < 120.0,
				"erreur moyenne %.0f°, vue p95 %.0f °/s, maxi %.0f °/s" % [em2, p95, mx])
		"clavier":
			_verif("clavier Q/D : vue douce", p95 < 60.0 and mx < 120.0,
				"vue p95 %.0f °/s, maxi %.0f °/s" % [p95, mx])
		"pied_tactile":
			var av: float = (sk.global_position - _pos0).dot(Vector3(-sin(_cap0), 0.0, -cos(_cap0)))
			_verif("iPad : pouce du joystick vers l'avant — il avance, la vue ne bouge pas",
				av > 2.0 and absf(sk.cam_pitch - _pitch0) < 0.02,
				"avancé de %.1f m, vue levée de %.0f°" % [av, rad_to_deg(sk.cam_pitch - _pitch0)])
		"pied_clavier_souris":
			var dm2: float = 0.0
			if _dir_marche.size() > 2:
				dm2 = rad_to_deg(absf(wrapf(_dir_marche[_dir_marche.size() - 1] - _dir_marche[0], -PI, PI)))
			_verif("PC : Z tenu, vue tournée de 90° à la souris — il suit la vue", absf(dm2 - 90.0) < 15.0,
				"cap de marche changé de %.0f°" % dm2)
		"pied_vue":
			var dm: float = 0.0
			if _dir_marche.size() > 2:
				dm = rad_to_deg(absf(wrapf(_dir_marche[_dir_marche.size() - 1] - _dir_marche[0], -PI, PI)))
			_verif("à pied, vue tournée sans lâcher le pouce : il garde son cap", dm < 10.0,
				"cap de marche changé de %.0f°" % dm)
	_sc += 1
	if _sc >= SCENARIOS.size():
		_fin()
		return
	_poser(sk, not SCENARIOS[_sc].begins_with("pied"))
