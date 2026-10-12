## Banc du quai (retour d'utilisateur, 12/10/2026 : « quand le skieur sur le quai marche
## trop près du funi, il reste coincé contre ») : sur le quai de Val Claret,
## rame à quai portes fermées, le skieur longe la voiture 2 en poussant un
## peu vers elle, vers l'amont puis vers l'aval — il doit avancer (avant :
## 1,4 m en 8 s, arrêté devant chaque marche et au bord de chaque baie).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_quai_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _sc: int = 0
var _z0: float = 0.0
var _t: float = 0.0
var _ok: bool = true
const CAS: Array = [[1.0, 0.25], [-1.0, 0.25], [1.0, 0.5]]   # [vers l'amont / l'aval, poussée vers la rame]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


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
			print("BENCH_QUAI ECHEC")
			quit(1)
		return
	_main.physics.doors_open = false
	_main.physics.door_leaves_open = false
	if _f < _t0 + 400:
		return                      # vantaux refermés (4 s)
	var v: Node3D = _main.cabin._interior_cars[1]
	var ga: GareAval = _main.station_halls.gare_aval
	var cote: float = signf((v.global_transform.affine_inverse() * ga._p2(Vector2(-3.55, -1.6))).x)
	if _t == 0.0:
		var z_dep: float = 2.0 if float(CAS[_sc][0]) > 0.0 else -4.0
		sk.activer(v.global_transform * Vector3(cote * 2.3, TrainBodyBuilder.Y_FLOOR + 0.6, z_dep), 0.0)
		var av: Vector3 = -v.global_transform.basis.z
		sk.cam_yaw = atan2(-av.x, -av.z)
		_z0 = (v.global_transform.affine_inverse() * sk.global_position).z
	_t += 1.0 / 60.0
	var cas: Array = CAS[_sc]
	sk.entree = Vector2(-cote * float(cas[1]), float(cas[0])).normalized() * 0.9
	if _t > 8.0:
		var loc: Vector3 = v.global_transform.affine_inverse() * sk.global_position
		var fait: float = absf(loc.z - _z0)
		var bon: bool = fait > 6.0
		print("%s le long de la rame, %s, poussée %.2f vers elle : %.1f m en 8 s" % ["[OK]  " if bon else "[ECHEC]",
			"vers l'amont" if float(cas[0]) > 0.0 else "vers l'aval", float(cas[1]), fait])
		_ok = _ok and bon
		sk.entree = Vector2.ZERO
		_t = 0.0
		_sc += 1
		if _sc >= CAS.size():
			print("BENCH_QUAI " + ("OK" if _ok else "ECHEC"))
			quit(0 if _ok else 1)
