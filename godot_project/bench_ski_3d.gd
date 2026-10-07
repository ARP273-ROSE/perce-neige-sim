## Banc du ski (07/10/2026) : le skieur chausse en haut, sur la neige au pied
## de la gare du glacier, et descend jusqu'à Val Claret en suivant la
## trace d'une descente réelle de Kevin (pilote à ski) ; le fantôme de
## cette descente part avec lui.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_ski_3d.gd -- --mode=normal
## Vérifie : refus de chausser dans la rame ; hiver, pistes balisées ; à ski,
## toujours sur le sol affiché, vitesse plausible ; arrivée à Val Claret,
## chrono contre le fantôme ; déchaussé, il marche.
extends SceneTree

const DESCENTE: int = 3                 # descente n° 4 (départ au pied de la gare)

var _main: Node = null
var _f: int = 0
var _phase: int = 0
var _t: float = 0.0
var _ok: bool = true
var _v_max: float = 0.0
var _ecart_max: float = 0.0
var _nan: bool = false
var _chausse5: bool = false
var _resultat: String = ""


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_SKI " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / 60.0
	_t += dt
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	var sk: SkieurJoueur = _main.get("skieur")
	match _phase:
		0:
			_main._depart_haut = true
			_main.basculer_skieur()
			_phase = 1
			_t = 0.0
		1:
			if _t < 1.0:
				return
			sk = _main.skieur
			# dans la rame : refusé
			var r: Array = []
			var cab: Cabin = _main.cabin
			var v: Node3D = cab._interior_cars[1]
			sk.global_position = v.global_transform * Vector3(0.0, TrainBodyBuilder.Y_FLOOR + 0.3, 0.0)
			sk.support = v
			var refus: String = sk.basculer_ski()
			_verif("chausser dans la rame : refusé", not sk.chausse and refus != "", refus)
			sk.support = null
			# au départ de la descente : sur la neige
			var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			var p0: Vector2 = pts[0]
			sk.global_position = Vector3(p0.x, relief.hauteur_sol(p0.x, p0.y) + 0.05, p0.y)
			var d: Vector2 = pts[8] - pts[0]
			sk._cap = atan2(-d.x, -d.y)
			_phase = 2
			_t = 0.0
		2:
			if _t < 0.5:
				return
			_main.basculer_ski()
			var dom: DomaineSkiable = _main.domaine
			var jalons: int = 0
			for c in dom.get_children():
				if c is MultiMeshInstance3D:
					jalons += (c as MultiMeshInstance3D).multimesh.instance_count
			_verif("chaussé sur la neige, hiver, pistes balisées, panneaux nommés",
				sk.chausse and relief._hiver > 0.99 and jalons > 500 and dom.n_panneaux > 100,
				"chaussé %s, hiver %.1f, %d jalons, %d panneaux" % [sk.chausse, relief._hiver, jalons, dom.n_panneaux])
			sk.chemin = dom.chemin_descente(DESCENTE, 3)
			sk.vitesse_pilote = 12.0
			_phase = 3
			_t = 0.0
		3:
			var p: Vector3 = sk.global_position
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				_nan = true
			else:
				_ecart_max = maxf(_ecart_max, absf(p.y - relief.hauteur_sol(p.x, p.z)))
			_v_max = maxf(_v_max, sk.vitesse_ski())
			var dom3: DomaineSkiable = _main.domaine
			if dom3.resultat != "":
				_resultat = dom3.resultat
			# (le message est consommé par main.gd : on le garde ici aussi)
			if _f % 600 == 0:
				print("  t %.0f  chrono %.1f  fantôme %s  v %.1f  d0 %.0f" % [_t, dom3.chrono,
					dom3.fantome.actif if dom3.fantome != null else false, sk.vitesse_ski(), Vector2(p.x, p.z).length()])
			var arrive: bool = Vector2(p.x, p.z).length() < DomaineSkiable.R_ARRIVEE
			if (sk.chemin.is_empty() and arrive) or _t > 1500.0 or _nan:
				if _resultat == "":
					_resultat = str(_main.commandes_skieur._msg.text)
				_verif("descente jusqu'à Val Claret, posé sur le sol",
					arrive and not _nan and _ecart_max < 0.05,
					"%s, %.0f s, écart au sol max %.3f m, %.0f m de la gare" % [
						DomaineSkiable._mmss(_t), _t, _ecart_max, Vector2(p.x, p.z).length()])
				_verif("vitesse plausible", _v_max > 8.0 and _v_max < 28.0, "max %.1f m/s (%.0f km/h)" % [_v_max, _v_max * 3.6])
				_verif("course contre le fantôme : chrono à l'arrivée", _resultat.begins_with("Arrivée"), _resultat)
				_main.basculer_ski()
				sk.chemin = [sk.global_position + Vector3(4.0, 0.0, 0.0)]
				_phase = 4
				_t = 0.0
		4:
			if _t > 4.0:
				_verif("déchaussé : il marche", not sk.chausse and sk.is_on_floor(),
					"au sol %s" % sk.is_on_floor())
				# chute : lancé à 9 m/s contre la façade de la gare de Val Claret
				var ga: GareAval = _main.station_halls.gare_aval
				var tv: Vector2 = (GareAval.FACADE_B - GareAval.FACADE_A).normalized()
				var de: Vector2 = Vector2(-tv.y, tv.x)
				var mil0: Vector2 = (GareAval.FACADE_A + GareAval.FACADE_B) * 0.5
				if Geometry2D.is_point_in_polygon(mil0 + de, PackedVector2Array(GareAval.HALL)):
					de = -de
				# à 5 m du milieu : au milieu c'est la porte d'entrée automatique,
				# qui s'ouvre devant lui (il entrait dans le hall en skiant)
				mil0 += tv * 5.0
				var p5: Vector3 = ga._p2(mil0 + de * 9.0)
				sk.global_position = Vector3(p5.x, relief.hauteur_sol(p5.x, p5.z) + 0.05, p5.z)
				sk.velocity = Vector3.ZERO
				sk.support = null
				sk.chemin.clear()
				_main.basculer_ski()
				var vers: Vector3 = (ga._p2(mil0) - p5)
				vers.y = 0.0
				vers = vers.normalized()
				sk._cap_ski = atan2(-vers.x, -vers.z)
				sk._cap = sk._cap_ski
				sk._v_ski = vers * 9.0
				_chausse5 = sk.chausse
				_phase = 5
				_t = 0.0
		5:
			if _t > 3.0 or sk.a_terre():
				_verif("lancé contre la façade à 9 m/s : chute, skis déchaussés, à terre",
					_chausse5 and not sk.chausse and sk.a_terre(),
					"chaussé avant %s, après %s, à terre %s, %.1f s" % [_chausse5, sk.chausse, sk.a_terre(), _t])
				_phase = 6
				_t = 0.0
		6:
			if _t > 3.0:
				var refus: String = sk.basculer_ski()
				_verif("relevé, E rechausse", not sk.a_terre() and sk.chausse and refus == "",
					"à terre %s, chaussé %s, %s" % [sk.a_terre(), sk.chausse, refus])
				_fin()
