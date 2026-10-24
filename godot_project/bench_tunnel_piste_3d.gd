## Banc du tunnel de la piste noire du Tunnel (retour d'utilisateur, 24/10/2026 :
## « ben creuse ») : le tunnel est percé (deux têtes, tube entre les deux),
## et un skieur poussé d'ouest en est le traverse SUR SON SOL — sans être
## remonté sur l'arête au-dessus — puis ressort sur la face est.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_tunnel_piste_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _tp: TunnelPiste = null
var _ecart_max: float = -INF
var _ecart_min: float = INF
var _dedans: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_TUNNEL_PISTE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _u(p: Vector3) -> float:
	return (p - _tp.a).dot(_tp.t)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60:
		return
	var sk: SkieurJoueur = _main.skieur
	_t += 1.0 / 60.0
	match _phase:
		0:
			_tp = _main.get("tunnel_piste")
			_verif("tunnel percé : deux têtes, tube entre les deux", _tp != null and _tp.u_b - _tp.u_a > 20.0,
				"" if _tp == null else "%.0f m, têtes à %.1f et %.1f m, %.1f m de roche au plus haut" % [_tp.longueur, _tp.u_a, _tp.u_b,
				_tp._dessus(_tp.longueur * 0.6) - _tp._axe(_tp.longueur * 0.6).y])
			if _tp == null:
				_fin()
				return
			var p0: Vector3 = _tp._axe(_tp.u_a - 6.0)
			sk.activer(p0 + Vector3(0, 0.3, 0), 0.0)
			sk.basculer_ski(true)
			sk.global_position = p0 + Vector3(0, 0.05, 0)
			sk.dernier_sol = p0
			_phase = 1
			_t = 0.0
		1:
			# poussé vers l'est à 6 m/s, sans conduite
			sk._v_ski = _tp.t * 6.0
			sk._cap_ski = atan2(-_tp.t.x, -_tp.t.z)
			var p: Vector3 = sk.global_position
			var u: float = _u(p)
			if u > _tp.u_a + 2.0 and u < _tp.u_b - 2.0:
				var e: float = p.y - _tp._axe(u).y
				_ecart_max = maxf(_ecart_max, e)
				_ecart_min = minf(_ecart_min, e)
				_dedans += 1
			if u > _tp.u_b + 6.0:
				_verif("skieur passé dans le tunnel, sur son sol", _dedans > 60 and _ecart_max < 0.6 and _ecart_min > -0.4,
					"%d images dedans, au-dessus du sol de %.2f à %.2f m" % [_dedans, _ecart_min, _ecart_max])
				var h: float = relief.hauteur_sol(p.x, p.z)
				_verif("ressorti sur la face est, sur la neige", absf(p.y - h) < 0.6, "%.2f m du relief" % (p.y - h))
				_fin()
			elif _t > 30.0:
				_verif("skieur passé dans le tunnel, sur son sol", false, "u = %.1f m après 30 s (y %.1f, sol %.1f, relief %.1f)" % [u, p.y, _tp._axe(clampf(u, 0.0, _tp.longueur)).y, relief.hauteur_sol(p.x, p.z)])
				_fin()
