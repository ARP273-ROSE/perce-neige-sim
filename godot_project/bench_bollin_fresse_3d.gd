## Banc de Bollin–Fresse dans sa configuration d'avant 2019 (retour d'utilisateur,
## 24/10/2026 : « je veux l'ancienne config ») :
##  1. tronçons calés : Fresse au double de l'espacement, nombre pair de sièges
##     sur Bollin ;
##  2. à chaque siège de Fresse qui sort de l'intermédiaire sur le tronçon bas,
##     un siège du tronçon haut en sort au même instant ;
##  3. file de droite (Fresse) : assis en bas, on traverse l'intermédiaire
##     sans descendre et l'on arrive en haut de Fresse ;
##  4. file de gauche (Bollin) : on descend à l'intermédiaire.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_bollin_fresse_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _b: LigneRemontee = null
var _h: LigneRemontee = null
var _sorties: int = 0
var _sorties_ok: int = 0
var _prec: Dictionary = {}
var _relais: bool = false
var _y0: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_BOLLIN_FRESSE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _attendre_file(exterieur: bool) -> void:
	var sk: SkieurJoueur = _main.skieur
	var q: Vector3 = _b.point_embarquement(true)
	if exterieur:
		q += _b._dehors(_b.s_gare(true, _b.x_arret(_b.longueur_zone(true)))) * LigneRemontee.DECAL_CONTOUR
	var g: Vector3 = _b.global_transform * q
	sk.global_position = Vector3(g.x, sk.global_position.y, g.z)
	sk._v_ski = Vector3.ZERO
	sk.velocity = Vector3.ZERO


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
			_b = rm._ligne_nommee("tsd6_bollin")
			_h = rm._ligne_nommee("tsd6_fresse")
			_main.aller_a_remontee(_b)
			_phase = 1
		1:
			if not (_b.pret and _h.pret and _h._synchro):
				if _t > 180.0:
					_verif("tronçons construits et calés", false, "bas %s haut %s synchro %s" % [_b.pret, _h.pret, _h._synchro])
					_fin()
				return
			var n: int = _b.nombre_vehicules()
			_verif("tronçons calés : Fresse au double du pas de Bollin, sièges pairs sur Bollin",
				n % 2 == 0 and absf(_h.periode_imposee - 2.0 * _b.periode_imposee) < 1e-3
				and absf(_b.espacement / _b.vitesse - _b.periode_imposee) < 1e-3,
				"%d sièges sur Bollin, %d sur Fresse, %.2f / %.2f s, %.2f m/s" % [n, _h.nombre_vehicules(), _b.periode_imposee, _h.periode_imposee, _b.vitesse])
			_phase = 2
			_t = 0.0
		2:
			# sorties de l'intermédiaire : un siège de Fresse de chaque côté
			var fin_b: float = float(_b._zones[1][1])
			var sortie_h: float = float(_h._zones[0][1])
			for i in range(1, _b.nombre_vehicules(), 2):
				var x: float = fposmod(float(_b._vehicules[i][1]) - fin_b, _b.longueur_boucle)
				var avant: float = _prec.get(i, -1.0)
				_prec[i] = x
				if avant > _b.longueur_boucle * 0.5 and x < 5.0:
					_sorties += 1
					var dmin: float = INF
					for j in range(_h.nombre_vehicules()):
						dmin = minf(dmin, absf(fposmod(float(_h._vehicules[j][1]) - sortie_h + _h.longueur_boucle * 0.5, _h.longueur_boucle) - _h.longueur_boucle * 0.5 - x))
					if dmin < 1.5:
						_sorties_ok += 1
			if _t > 40.0:
				_verif("sièges de Fresse : relais au même instant à la sortie de l'intermédiaire",
					_sorties >= 3 and _sorties_ok == _sorties, "%d/%d sorties appariées" % [_sorties_ok, _sorties])
				_main.aller_a_remontee(_b)
				_phase = 3
				_t = 0.0
		3:
			if _t < 2.0:
				return
			if not sk.chausse:
				sk.basculer_ski(true)
			if rm.a_bord.is_empty():
				_attendre_file(true)
				if _t > 40.0:
					_verif("file Fresse : assis", false, "rien en 40 s")
					_fin()
				return
			_verif("file Fresse : assis dans un siège de Fresse", rm.a_bord[0] == _b and _b.traverse(rm.a_bord[1]))
			_y0 = sk.global_position.y
			_phase = 4
			_t = 0.0
		4:
			if not rm.a_bord.is_empty() and rm.a_bord[0] == _h:
				_relais = true
			if rm.a_bord.is_empty():
				var haut: Vector3 = _h.global_transform * Vector3(0, _h.terrain(_h.longueur_h()), -_h.longueur_h())
				var d: float = Vector2(sk.global_position.x - haut.x, sk.global_position.z - haut.z).length()
				_verif("file Fresse : traversé l'intermédiaire assis, levé en haut de Fresse", _relais and d < 40.0,
					"relais %s, %.0f m de la gare amont de Fresse, +%.0f m, %.0f s" % [_relais, d, sk.global_position.y - _y0, _t])
				_main.aller_a_remontee(_b)
				_phase = 5
				_t = 0.0
			elif _t > 700.0:
				_verif("file Fresse : arrivé en haut", false, "toujours assis après 700 s")
				_fin()
		5:
			if _t < 2.0:
				return
			if not sk.chausse:
				sk.basculer_ski(true)
			if rm.a_bord.is_empty():
				_attendre_file(false)
				if _t > 40.0:
					_verif("file Bollin : assis", false, "rien en 40 s")
					_fin()
				return
			_verif("file Bollin : assis dans un siège de Bollin", rm.a_bord[0] == _b and not _b.traverse(rm.a_bord[1]))
			_phase = 6
			_t = 0.0
		6:
			if rm.a_bord.is_empty():
				var mi: Vector3 = _b.global_transform * Vector3(0, _b.terrain(_b.longueur_h()), -_b.longueur_h())
				var d2: float = Vector2(sk.global_position.x - mi.x, sk.global_position.z - mi.z).length()
				_verif("file Bollin : levé à la gare intermédiaire", d2 < 40.0, "%.0f m de l'intermédiaire" % d2)
				_fin()
			elif _t > 300.0:
				_verif("file Bollin : levé à l'intermédiaire", false, "toujours assis")
				_fin()
