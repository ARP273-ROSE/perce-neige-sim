## Banc du double tapis de Solaise : à pied puis à skis, posé au bas de Pim, on est monté à la vitesse de la bande ;
## posé 6 m avant le haut, on est déposé sur la neige après le peigne.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_tapis_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _tp: TapisRoulant = null
var _s0: float = 0.0
var _y0: float = 0.0
var _ski: bool = false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_TAPIS " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, get("_main"), 0 if _ok else 1)


func _s_de(p: Vector3) -> float:
	return (Vector2(p.x, p.z) - _tp.a).dot(_tp._u)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			_tp = rm.get_node_or_null("Tapis_Pim")
			if _tp == null:
				_verif("tapis posés", false)
				_fin()
				return
			# skieur posé à 1,5 m du bas, sur la bande
			var p: Vector3 = _tp._point(1.5, 0.0)
			sk.activer(p + Vector3(0, 0.3, 0), 0.0)
			_phase = 1
			_t = 0.0
		1:
			# le relief fin et la bande se construisent autour de lui ; on le repose dessus
			if _t > 4.0:
				if not _tp._construit:
					_verif("tapis construit près du skieur", false)
					_fin()
					return
				if _ski and not sk.chausse:
					sk.basculer_ski(true)
				sk.global_position = _tp._point(1.5, 0.0) + Vector3(0, 0.02, 0)
				_tp._porte = false
				_s0 = 1.5
				_y0 = sk.global_position.y
				_phase = 2
				_t = 0.0
		2:
			sk.entree = Vector2.ZERO
			if _t > 20.0:
				var s: float = _s_de(sk.global_position)
				var dy: float = sk.global_position.y - _tp.y_bande(s)
				_verif("%s : monté par la bande" % ("à skis" if _ski else "à pied"), absf(s - _s0 - TapisRoulant.VITESSE * 20.0) < 1.5 and absf(dy) < 0.25,
					"%.1f m en 20 s (bande : %.1f), %.2f m au-dessus du caoutchouc, %.1f m de dénivelé" % [s - _s0, TapisRoulant.VITESSE * 20.0, dy, sk.global_position.y - _y0])
				# 6 m avant le haut
				sk.global_position = _tp._point(_tp._long - 6.0, 0.0) + Vector3(0, 0.02, 0)
				_tp._porte = false
				_phase = 3
				_t = 0.0
		3:
			if _t > 14.0:
				var s2: float = _s_de(sk.global_position)
				var sol: float = relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
				_verif("%s : déposé au bout" % ("à skis" if _ski else "à pied"), s2 > _tp._long + 0.3 and absf(sk.global_position.y - sol) < 0.6,
					"%.1f m après le haut de la bande, %.2f m au-dessus de la neige" % [s2 - _tp._long, sk.global_position.y - sol])
				if _ski:
					_fin()
					return
				_ski = true
				_phase = 0
				_t = 0.0
