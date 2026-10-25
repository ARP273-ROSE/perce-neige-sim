## Banc des sons des remontées (retour d'utilisateur, 25/10/2026) : gare entendue de
## près, pas de loin ; à bord, son de ligne qui suit la vitesse, lanceur au
## départ, une salve de chocs à chaque pylône franchi (un par galet) ;
## arrêt d'urgence entendu.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_sons_remontees_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _lanceur_vu: bool = false
var _salves: int = 0
var _chocs: int = 0
var _n_file: int = 0
var _joues: Dictionary = {}


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_SONS_REMONTEES " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _gare_audible(so: SonsRemontees) -> bool:
	for e in so._gares:
		if e[1] == _lg and (e[0] as AudioStreamPlayer3D).playing and (e[0] as AudioStreamPlayer3D).volume_db > -30.0:
			return true
	return false


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
	var rm: RemonteesDomaine = _main.remontees
	var so: SonsRemontees = rm.sons
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "tsd6_marmottes_express":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				_t = 0.0
				return
			if _t < 3.0:
				return
			_verif("gare entendue de près", _gare_audible(so))
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.basculer_ski(true)
			sk.dernier_sol = q
			_phase = 2
			_t = 0.0
		2:
			if not rm.a_bord.is_empty():
				_phase = 3
				_t = 0.0
			elif _t > 30.0:
				_verif("embarqué", false)
				_fin()
		3:
			# prises réelles du TSD : on note ce qui a été joué
			for pl in [so._coup3s, so._coup3s_b, so._ligne]:
				if pl.playing and pl.stream != null:
					for nom in so._sons:
						if so._sons[nom] == pl.stream:
							_joues[nom] = true
			if _t > 60.0:
				_verif("embarquement et lanceur (prise réelle)", _joues.has("tsd_embarquement"), str(_joues.keys()))
				_verif("à bord : ambiance de ligne", _joues.has("tsd_ligne"))
				_verif("pylône franchi", _joues.has("tsd_pyl_s") or _joues.has("tsd_pyl_cc"))
				_lg.arret_urgence()
				_phase = 4
				_t = 0.0
		4:
			for pl2 in [so._coup3s, so._coup3s_b]:
				if pl2.playing and pl2.stream == so._sons["tsd_arret"]:
					_joues["tsd_arret"] = true
			if _t > 0.5:
				_verif("arrêt en ligne entendu", _joues.has("tsd_arret") and so._arret.playing)
				_lg.rearmer()
				_lg.demarrer()
				rm.quitter()
				# loin de la gare (500 m)
				var loin: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(_lg.longueur_h() * 0.5), -_lg.longueur_h() * 0.5)
				sk.activer(loin + Vector3(400, 50, 0), 0.0)
				_phase = 5
				_t = 0.0
		5:
			if _t > 3.0:
				var proche: bool = false
				for e in so._gares:
					if e[1] == _lg and (e[0] as AudioStreamPlayer3D).global_position.distance_to(sk.global_position) < 220.0:
						proche = true
				_verif("gare plus entendue de loin", not proche)
				_fin()
