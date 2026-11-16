## Banc de la direction du skieur (16/11/2026, retour d'utilisateur : « quand je demande à tourner avec le joystick
## ou le clavier, ça tourne mais de moins en moins jusqu'à aller tout droit alors que j'ai encore une instruction à
## tourner. Du coup quand je remets au neutre ça part en virage à l'envers, la vue fait n'importe quoi »).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_direction_skieur_3d.gd
## Pour chaque entrée (touches relayées par le PC, clavier de la 3D, joystick à l'écran), à ski puis à pied :
## « gauche » tenu 5 s — le cap croît sans fléchir (vitesse angulaire de la dernière seconde ≥ 70 % de celle de la
## deuxième, jamais de recul) ; puis neutre 3 s — le cap reste figé à ±1°, et la vue ne repart pas en sens inverse.
## Vue figée (retour d'utilisateur, 16/11/2026 : « au bout d'un certain temps impossible d'orienter la vue, elle est
## restée figée à un angle ») : un doigt posé sur la vue, les commandes masquées (changement de mode), le doigt levé,
## les commandes réaffichées — un nouveau doigt (même numéro ou non) doit encore tourner la vue.
extends SceneTree

const DESCENTE: int = 3
const T_TENU: float = 5.0
const T_NEUTRE: float = 3.0

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _t: float = 0.0
var _etape: int = -2
var _cas: Array = [
	["ski, touches du PC", true, "ext"],
	["ski, joystick", true, "joy"],
	["à pied, touches du PC", false, "ext"],
	["à pied, joystick", false, "joy"],
]
var _p0: Vector3 = Vector3.ZERO
var _cap0: float = 0.0
var _serie: Array = []          # [t, cap déroulé, vue déroulée]
var _cap_prec: float = 0.0
var _vue_prec: float = 0.0
var _cap_cum: float = 0.0
var _vue_cum: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_DIRECTION_SKIEUR " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, get("_main"), 0 if _ok else 1)


func _cap(sk: SkieurJoueur) -> float:
	return sk._cap_ski if sk.chausse else sk._cap


func _entree(sk: SkieurJoueur, mode: String, gauche: bool) -> void:
	sk.touches_ext = 4 if (gauche and mode == "ext") else 0
	sk.entree = Vector2(-1.0, 0.0) if (gauche and mode == "joy") else Vector2.ZERO


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 4000:
			_verif("relief prêt", false)
			_fin()
		return
	var dt: float = 1.0 / 60.0
	_t += dt
	if _main.get("perf_manager") != null:
		_main.perf_manager.banc = true
	var sk: SkieurJoueur = _main.get("skieur")
	if _etape == -2:
		_main._depart_haut = true
		_main.basculer_skieur()
		_etape = -1
		_t = 0.0
		return
	if _etape == -1:
		if _t < 1.0:
			return
		var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
		_p0 = Vector3(pts[0].x, relief.hauteur_sol(pts[0].x, pts[0].y) + 0.05, pts[0].y)
		var d: Vector2 = pts[8] - pts[0]
		_cap0 = atan2(-d.x, -d.y)
		_etape = 0
		_t = 99.0
		return
	if _etape >= _cas.size() * 3:
		_vue_apres_doigt_perdu(sk)
		return
	var c: Array = _cas[_etape / 3]
	var sous: int = _etape % 3
	if sous == 0:
		# mise en place : posé, chaussé ou non, lancé à 8 m/s à ski, la vue derrière
		if _t < 0.5:
			return
		if sk.chausse != bool(c[1]):
			_main.basculer_ski()
		sk.global_position = _p0
		sk.velocity = Vector3.ZERO
		sk.cam_yaw = _cap0
		sk._cap = _cap0
		sk._cap_ski = _cap0
		sk._cam_v = 0.0
		if sk.chausse:
			sk._v_ski = Vector3(-sin(_cap0), 0.0, -cos(_cap0)) * 8.0
		_entree(sk, String(c[2]), false)
		_serie.clear()
		_cap_prec = _cap(sk)
		_vue_prec = sk.cam_yaw
		_cap_cum = 0.0
		_vue_cum = 0.0
		_etape += 1
		_t = 0.0
		return
	# déroulés (pas de saut de ±π)
	_cap_cum += wrapf(_cap(sk) - _cap_prec, -PI, PI)
	_vue_cum += wrapf(sk.cam_yaw - _vue_prec, -PI, PI)
	_cap_prec = _cap(sk)
	_vue_prec = sk.cam_yaw
	if sous == 1:
		_entree(sk, String(c[2]), true)
		_serie.append([_t, _cap_cum, _vue_cum])
		if _t >= T_TENU:
			_entree(sk, String(c[2]), false)
			_etape += 1
			_t = 0.0
		return
	_serie.append([T_TENU + _t, _cap_cum, _vue_cum])
	if _t < T_NEUTRE:
		return
	_bilan(String(c[0]), sk)
	_etape += 1
	_t = 0.0


func _a(t: float) -> Array:
	var best: Array = _serie[0]
	for s in _serie:
		if absf(float(s[0]) - t) < absf(float(best[0]) - t):
			best = s
	return best


func _bilan(nom: String, sk: SkieurJoueur) -> void:
	var l: PackedStringArray = PackedStringArray()
	for k in range(0, 17):
		var s: Array = _a(float(k) * 0.5)
		l.append("%.1f:%+.0f/%+.0f" % [float(s[0]), rad_to_deg(float(s[1])), rad_to_deg(float(s[2]))])
	print("   %s — t : cap / vue (°) : %s" % [nom, "  ".join(l)])
	# tenu : croît sans fléchir
	var w2: float = float(_a(2.0)[1]) - float(_a(1.0)[1])
	var w5: float = float(_a(5.0)[1]) - float(_a(4.0)[1])
	var recul: float = 0.0
	var prec: float = 0.0
	for s in _serie:
		if float(s[0]) > T_TENU:
			break
		recul = maxf(recul, prec - float(s[1]))
		prec = maxf(prec, float(s[1]))
	_verif("%s : « gauche » tenu %.0f s, le cap tourne sans fléchir" % [nom, T_TENU],
		w2 > deg_to_rad(5.0) and w5 >= 0.7 * w2 and recul < deg_to_rad(0.5),
		"%.0f °/s à 1-2 s, %.0f °/s à 4-5 s, recul %.1f°" % [rad_to_deg(w2), rad_to_deg(w5), rad_to_deg(recul)])
	# neutre : cap figé, vue sans retour
	# (référence une image après le relâché : l'image du relâché tournait encore)
	var c_lache: float = float(_a(T_TENU + 0.04)[1])
	var ecart: float = 0.0
	var v_max_retour: float = 0.0
	var v_prec: float = float(_a(T_TENU)[2])
	var v_haut: float = v_prec
	for s in _serie:
		if float(s[0]) <= T_TENU + 0.04:
			continue
		ecart = maxf(ecart, absf(float(s[1]) - c_lache))
		v_haut = maxf(v_haut, float(s[2]))
		v_max_retour = maxf(v_max_retour, v_haut - float(s[2]))
	_verif("%s : au neutre, le cap reste figé (±1°) et la vue ne repart pas en arrière" % nom,
		ecart <= deg_to_rad(1.0) and v_max_retour < deg_to_rad(2.0),
		"écart du cap %.1f°, retour de la vue %.1f°" % [rad_to_deg(ecart), rad_to_deg(v_max_retour)])


var _vf: int = 0
var _vf_t: int = 0
var _vf_yaw: float = 0.0


func _doigt(i: int, p: Vector2, appui: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = i
	t.position = get_root().get_final_transform() * p
	t.pressed = appui
	Input.parse_input_event(t)


func _glisse(i: int, p: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = i
	d.position = get_root().get_final_transform() * p
	d.relative = rel
	Input.parse_input_event(d)


## Deux essais : le nouveau doigt porte un autre numéro (Safari), puis le même (numéros réutilisés).
func _vue_apres_doigt_perdu(sk: SkieurJoueur) -> void:
	var cs: CommandesSkieur = _main.commandes_skieur
	var ecran: Vector2 = get_root().get_visible_rect().size
	var p: Vector2 = ecran * Vector2(0.7, 0.45)
	_vf_t += 1
	var essai: int = _vf / 10
	if essai >= 2:
		_fin()
		return
	var perdu: int = 3 + essai * 10
	var nouveau: int = perdu + 1 if essai == 0 else perdu
	match _vf % 10:
		0:
			if sk.chausse:
				_main.basculer_ski()
			_entree(sk, "ext", false)
			_doigt(perdu, p, true)
			_vf += 1
		1:
			cs.visible = false
			_vf += 1
		2:
			_doigt(perdu, p, false)
			_vf += 1
		3:
			cs.visible = true
			_vf += 1
			_vf_t = 0
		4:
			if _vf_t < 30:
				return
			_vf_yaw = sk.cam_yaw
			_doigt(nouveau, p, true)
			_vf += 1
			_vf_t = 0
		5:
			_glisse(nouveau, p + Vector2(10.0 * _vf_t, 0.0), Vector2(10.0, 0.0))
			if _vf_t >= 6:
				_doigt(nouveau, p + Vector2(60.0, 0.0), false)
				_vf += 1
				_vf_t = 0
		_:
			if _vf_t < 10:
				return
			var dy: float = rad_to_deg(absf(wrapf(sk.cam_yaw - _vf_yaw, -PI, PI)))
			_verif("doigt levé pendant que les commandes étaient masquées, puis un %s doigt : la vue tourne encore" % ("autre" if essai == 0 else "même numéro de"),
				dy > 10.0, "vue tournée de %.0f° pour 60 px (doigts comptés %d)" % [dy, sk.doigts])
			_vf = (essai + 1) * 10

