## Banc de l'embarquement aux remontées (retour d'utilisateur, 22/10/2026 : « j'ai
## pas réussi à monter dedans et je suis passé à travers tout » ; « pour les
## sièges, l'embarquement avec les portillons : on avance jusqu'au stop et
## ça s'assoit tout seul quand le siège arrive » ; « on monte en marchant
## comme le funi »).
##  1. télésiège (Marmottes Express) : portillons qui s'ouvrent, skieur à la
##     ligne d'arrêt → assis par le siège suivant → emporté → levé sur le
##     quai d'arrivée ;
##  2. télécabine (Boisses) : entré à pied, portes ouvertes → emporté par la
##     cabine (support = son corps de collision) jusqu'en haut.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_embarquement_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _portillons_vus_ouverts: bool = false
var _y0: float = 0.0
var _cab: int = -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _ligne(cle: String) -> LigneRemontee:
	for e in _main.remontees.lignes:
		if (e[0] as Node).name == cle:
			return e[0]
	return null


func _fin() -> void:
	print("BENCH_EMBARQUEMENT " + ("OK" if _ok else "ECHEC"))
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
			_lg = _ligne("tsd6_marmottes_express")
			_main.aller_a_remontee(_lg)
			_main.collisions.assurer_autour(_lg.global_transform.origin)
			_phase = 10
		10:
			if not _lg.pret:
				return            # construite à l'arrivée du skieur, par tranches
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.dernier_sol = q
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				_t = 0.0
				return
			for pg in _lg._portillons_gares:
				if pg[0] and (pg[2][0] as CollisionShape3D).disabled:
					_portillons_vus_ouverts = true
			if not rm.a_bord.is_empty():
				_verif("télésiège : assis par le siège arrivé à la ligne d'arrêt", sk.embarque and sk.assis,
					"%.1f s d'attente, place %d" % [_t, rm.a_bord[2]])
				_y0 = sk.global_position.y
				_phase = 2
				_t = 0.0
			elif _t > 30.0:
				_verif("télésiège : assis par le siège arrivé à la ligne d'arrêt", false, "rien en 30 s")
				_fin()
		2:
			for pg in _lg._portillons_gares:
				if pg[0] and (pg[2][0] as CollisionShape3D).disabled:
					_portillons_vus_ouverts = true
			if rm.a_bord.is_empty():
				_verif("télésiège : portillons ouverts après le passage de chaque siège", _portillons_vus_ouverts)
				var amont: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(_lg.longueur_h()), -_lg.longueur_h())
				var d: float = Vector2(sk.global_position.x - amont.x, sk.global_position.z - amont.z).length()
				_verif("télésiège : emporté puis levé sur le quai d'arrivée", not sk.embarque and d < 40.0
					and sk.global_position.y > _y0 + 200.0, "%.0f s de trajet, %.1f m de la gare amont, +%.0f m" % [_t, d, sk.global_position.y - _y0])
				_phase = 3
				_t = 0.0
			elif _t > 400.0:
				_verif("télésiège : emporté puis levé sur le quai d'arrivée", false, "toujours assis après 400 s")
				_fin()
		3:
			if _t > 3.0:
				var sol: float = _main.relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
				_verif("télésiège : debout à l'arrivée (pas de chute)", sk.is_on_floor() or absf(sk.global_position.y - sol) < 1.5,
					"au sol %s" % sk.is_on_floor())
				_lg = _ligne("tcd10_boisses")
				_main.aller_a_remontee(_lg)
				_phase = 4
				_t = 0.0
		4:
			if not _lg.pret:
				return            # construite à l'approche du skieur, par tranches
			# une cabine en gare aval, portes ouvertes : on y entre à pied
			var porte_ouverte: bool = false
			for i in range(_lg._vehicules.size()):
				var z: Array = _lg.zone(_lg._vehicules[i][1])
				if z[0] == "gare_aval" and _lg._corps[i] != null and (_lg._corps[i][1][0] as CollisionShape3D).disabled:
					var x: float = z[1]
					if x > LigneRemontee.L_FREIN + 4.0 and x < z[2] - LigneRemontee.L_FREIN - 6.0:
						_cab = i
						porte_ouverte = true
						break
			if porte_ouverte:
				var corps: Node3D = _lg._corps[_cab][0]
				var dedans: Vector3 = corps.global_transform * Vector3(0, -1.15 - 0.10 - 2.25 + 0.20, 0)
				sk.activer(dedans, 0.0)
				_y0 = dedans.y
				_phase = 5
				_t = 0.0
			elif int(_t * 60) % 600 == 0:
				var zs: Array = []
				for i2 in range(_lg._vehicules.size()):
					var z2: Array = _lg.zone(_lg._vehicules[i2][1])
					if z2[0] != "ligne":
						zs.append("%s %.1f/%.1f" % [z2[0], z2[1], z2[2]])
				print("  t=%.0f process=%s corps=%d %s sk=%s lg=%s actif=%s" % [_t, _lg.is_processing(), _lg._corps.size(), str(zs), sk.global_position, _lg.global_transform.origin, sk.actif])
			if _t > 200.0 and _phase == 4:
				_verif("télécabine : une cabine à quai, portes ouvertes", false)
				_fin()
		5:
			if _t >= 1.0 and _t < 1.0 + 1.0 / 60.0:
				_verif("télécabine : à bord, la cabine le porte", sk.support == _lg._corps[_cab][0],
					"support %s" % [sk.support])
			if _t > 240.0:
				var corps2: Node3D = _lg._corps[_cab][0]
				var loc: Vector3 = corps2.global_transform.affine_inverse() * sk.global_position
				_verif("télécabine : emporté à bord (pas passé à travers)", absf(loc.x) < 1.0 and absf(loc.z) < 1.0
					and sk.global_position.y > _y0 + 150.0, "repère cabine (%.2f ; %.2f ; %.2f), +%.0f m" % [loc.x, loc.y, loc.z, sk.global_position.y - _y0])
				_fin()
