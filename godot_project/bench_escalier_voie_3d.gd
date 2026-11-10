## Banc du petit escalier de la gare haute (retour d'utilisateur, 03/11/2026 : « on
## n'arrive pas à remonter de la voie au quai ») : de la dalle de voie, le skieur à
## pied gagne le quai par l'escalier, de chaque côté, et finit derrière la barrière.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_escalier_voie_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _cas: int = 0
var _t: float = 0.0
var _ok: bool = true
var _but: Vector3
const CAS: Array = [1.0, -1.0]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _monde(s: float, x: float, y: float) -> Vector3:
	var xf: Transform3D = _main.stations._xf_at(s)
	return xf.origin + xf.basis.x * x + xf.basis.y * y


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	var sk: SkieurJoueur = _main.skieur
	if sk == null or not sk.actif or _main.collisions == null or not _main.collisions.pret:
		if _f > 20000:
			print("[ECHEC] skieur ou collisions pas prêts")
			print("BENCH_ESCALIER_VOIE ECHEC")
			FinBanc.quitter(self, get("_main"), 1)
		return
	var side: float = CAS[_cas]
	var S0: float = StationsBuilder.ESC_VOIE_S0
	var S1: float = StationsBuilder.ESC_VOIE_S1
	var x_e: float = side * 1.12
	if _t == 0.0:
		sk.global_position = _monde(S1 + 0.0, x_e, StationsBuilder.FLOOR_Y_LOCAL + 0.25)
		sk.velocity = Vector3.ZERO
		_but = _monde(S0 + 0.3, side * 3.0, -1.10)
		sk.chemin = [_monde(S0 + 0.15, x_e, StationsBuilder.FLOOR_Y_LOCAL + 0.5), _but]
		print("départ %s, but %s" % [str(sk.global_position), str(_but)])
	_t += 1.0 / 60.0
	if _t > 10.0:
		var p: Vector3 = sk.global_position
		var d: float = Vector2(p.x - _but.x, p.z - _but.z).length()
		var bon: bool = d < 0.8 and absf(p.y - _but.y) < 0.5
		print("%s côté %+.0f : fin %s, à %.2f m du but, écart de hauteur %.2f m" % ["[OK]  " if bon else "[ECHEC]", side, str(p), d, p.y - _but.y])
		_ok = _ok and bon
		sk.chemin = []
		_t = 0.0
		_cas += 1
		if _cas >= CAS.size():
			print("BENCH_ESCALIER_VOIE " + ("OK" if _ok else "ECHEC"))
			FinBanc.quitter(self, _main, 0 if _ok else 1)
