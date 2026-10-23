## Banc du 3S de l'Olympique : la ligne se construit au pied de Val d'Isère,
## les cabines Zeta roulent sur les porteurs, on monte à bord à pied (assis
## d'office), on est emporté jusqu'à la gare amont et l'on sort portes
## ouvertes.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_3s_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _y0: float = 0.0
var _cab: int = -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_3S " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


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
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "olympique":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				if _t > 120.0:
					_verif("3S : ligne construite", false)
					_fin()
				return
			var n_l: int = 0
			var ecart: float = 0.0
			for i in range(_lg.nombre_vehicules()):
				var s: float = _lg._vehicules[i][1]
				if _lg.zone(s)[0] != "ligne":
					continue
				n_l += 1
			_verif("3S : ligne construite, véhicules en ligne", n_l >= 6, "%d véhicules, %d en ligne" % [_lg.nombre_vehicules(), n_l])
			_phase = 2
			_t = 0.0
		2:
			for i in range(_lg._vehicules.size()):
				var z: Array = _lg.zone(_lg._vehicules[i][1])
				if z[0] == "gare_aval" and _lg._corps[i] != null and (_lg._corps[i][1][0] as CollisionShape3D).disabled \
						and rm._repos <= 0.0:
					var x: float = z[1]
					if x > LigneRemontee.L_FREIN + 4.0 and x < z[2] - LigneRemontee.L_FREIN - 6.0:
						_cab = i
						var v: VehiculeRemontee = _lg.vehicule(i)
						var dedans: Vector3 = v.global_transform * (v.place_assise(2) + Vector3(0, 0.05, 0))
						sk.activer(dedans, 0.0)
						_y0 = dedans.y
						_phase = 3
						_t = 0.0
						return
			if _t > 200.0:
				_verif("3S : une cabine à quai, portes ouvertes", false)
				_fin()
		3:
			if _t > 1.0 and _t < 1.0 + 1.0 / 60.0:
				_verif("3S : assis d'office dans la Zeta", not rm.a_bord.is_empty() and sk.assis and rm.a_bord[0] == _lg)
			if _t > 1.5 and rm.a_bord.is_empty():
				var haut: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(_lg.longueur_h()), -_lg.longueur_h())
				var d: float = Vector2(sk.global_position.x - haut.x, sk.global_position.z - haut.z).length()
				_verif("3S : emporté jusqu'en haut, sorti portes ouvertes", not sk.embarque and d < 40.0
					and sk.global_position.y > _y0 + 700.0, "%.0f s de trajet, %.1f m de la gare amont, +%.0f m" % [_t, d, sk.global_position.y - _y0])
				_fin()
			elif _t > 700.0:
				_verif("3S : emporté jusqu'en haut", false, "toujours à bord après 700 s")
				_fin()
