## Galets de ligne qui tournent à v/R près du point de vue, et plus du tout de loin : angle mesuré contre la vitesse
## réelle du câble, sens selon le brin et le côté du câble, aucun nœud de plus une fois le pylône quitté.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_galets_tournants_3d.gd -- --mode=normal
extends SceneTree

const LIGNE: String = "tsd6_merles"
const ECART_MAX: float = 0.02         # écart relatif toléré sur la vitesse de rotation

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _lg: LigneRemontee = null
var _py: PyloneRemontee = null
var _etat: int = 0
var _t: float = 0.0
var _depart: Array = []
var _n: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _vue(p: Vector3) -> void:
	_main.skieur.global_position = _lg.global_transform * p
	_lg.point_vue = p


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
	_t += 1.0 / 60.0
	match _etat:
		0:
			for e in _main.remontees.lignes:
				if String((e[0] as Node).name) == LIGNE:
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_main.skieur.process_mode = Node.PROCESS_MODE_DISABLED
			_etat = 1
			_t = 0.0
		1:
			if _lg.pret and _t > 3.0:
				_py = _lg._pyl[int(_lg._pyl.size() / 2)][0]
				_vue(_py.position + Vector3(6, 0, 0))
				_etat = 2
				_t = 0.0
		2:
			_vue(_py.position + Vector3(6, 0, 0))
			if _t > 0.5:
				_verif("roues créées près du pylône", not _py._roues.is_empty(), "%d roues" % _py._roues.size())
				if _py._roues.is_empty():
					_fin()
					return
				_depart = []
				_etat = 3
				_t = 0.0
		3:
			_vue(_py.position + Vector3(6, 0, 0))
			if _depart.is_empty():
				for r in _py._roues:
					_depart.append((r[0] as Node3D).basis)
				_n = 0
				return
			_n += 1
			if _n == 6:
				# sur 6 images : assez court pour ne pas faire de tour, assez long pour la mesure
				var attendu: float = _lg.vitesse_reelle * (_n / 60.0) / PyloneRemontee.R_GALET
				var pire: float = 0.0
				var sens_faux: int = 0
				for i in range(_py._roues.size()):
					var r: Array = _py._roues[i]
					var rel: Basis = ((_depart[i] as Basis).orthonormalized().inverse() * (r[0] as Node3D).basis.orthonormalized())
					var a: float = rel.get_rotation_quaternion().get_euler(EULER_ORDER_YXZ).y
					pire = maxf(pire, absf(absf(a) - attendu))
					if signf(a) != signf(float(r[1])):
						sens_faux += 1
				print("attendu %.3f rad pour %.2f m/s en 6 images (%.1f rad/s, %.0f° par image à 60 i/s)" % [attendu, _lg.vitesse_reelle, attendu * 10.0, rad_to_deg(attendu / 6.0)])
				_verif("v/R de chaque roue", attendu > 0.0 and pire <= ECART_MAX * attendu + 0.0005, "pire écart %.4f rad" % pire)
				_verif("sens de chaque roue", sens_faux == 0, "%d à l'envers" % sens_faux)
				_etat = 4
				_t = 0.0
		4:
			_vue(_py.position + Vector3(400, 0, 0))
			if _t > 0.6:
				_verif("roues retirées en s'éloignant", _py._roues.is_empty())
				_fin()


func _fin() -> void:
	print("BENCH_GALETS_TOURNANTS " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
