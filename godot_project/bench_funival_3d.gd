## Banc du Funival : la ligne se construit, la voie reste au-dessus du sol dehors et sous la roche dans le tunnel,
## les deux véhicules se croisent dans l'évitement sans se toucher, un trajet dure environ 5 min (fiche), et le
## skieur entré dans un compartiment à quai en gare aval est emporté debout jusqu'à la gare amont.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_funival_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: Funival = null
var _y0: float = 0.0
var _ecart_min: float = INF
var _t_depart: float = -1.0
var _y_prec: float = 0.0
var _chute_max: float = 0.0
var _yaw_amont: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_FUNIVAL " + ("OK" if _ok else "ECHEC"))
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
	if not sk.actif:
		return
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "funival":
					_lg = e[0]
			_verif("Funival : ligne présente dans le domaine", _lg != null)
			if _lg == null:
				_fin()
				return
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				if _t > 180.0:
					_verif("Funival : ligne construite", false, "étape %s" % _lg.derniere_etape)
					_fin()
				return
			var L: float = _lg.longueur_h()
			_verif("Funival : deux véhicules", _lg.nombre_vehicules() == 2)
			# dehors : voie au-dessus du sol (poutre sur piles) ; tunnel : sous la roche
			var pire_dehors: float = INF
			var pire_roche: float = INF
			var d: float = 5.0
			while d < L - 5.0:
				var y: float = _lg.y_voie(d)
				var sol: float = _lg._sol(0.0, -d)
				if d > 80.0 and d < _lg.portail_d - 30.0:      # (gare aval : voie en fosse)
					pire_dehors = minf(pire_dehors, y - 1.0 - sol)
				elif d > _lg.portail_d + 30.0 and d < L - 60.0:
					pire_roche = minf(pire_roche, sol - (y + 2.0 * Funival.R_TUNNEL))
				d += 2.0
			print("FUNIVAL L=%.0f m, portail %.0f, voie aval %.1f amont %.1f portail %.1f (repère ligne)" % [L, _lg.portail_d, _lg.y_voie(0.0), _lg.y_voie(L), _lg.y_voie(_lg.portail_d)])
			_verif("Funival : poutre dehors au-dessus du sol (≥ -1,5 m : déblais courts admis)", pire_dehors > -1.5, "%.2f m" % pire_dehors)
			_verif("Funival : tunnel sous la roche", pire_roche > 0.0, "couverture mini %.2f m" % pire_roche)
			_phase = 2
			_t = 0.0
		2:
			# un aller : départ, croisement, arrivée
			var d0: float = _lg._vehicules[0][1]
			var d1: float = _lg._vehicules[1][1]
			if _t_depart < 0.0 and _lg._phase == "route":
				_t_depart = _t
			if absf(d0 - d1) < VehiculeFunival.DEMI_L * 2.0 + 2.0:
				var p0: Vector3 = (_lg.vehicule(0) as Node3D).position
				var p1: Vector3 = (_lg.vehicule(1) as Node3D).position
				_ecart_min = minf(_ecart_min, absf(p0.x - p1.x))
			if _t_depart >= 0.0 and _lg._phase == "quai":
				var duree: float = _t - _t_depart
				_verif("Funival : croisement dans l'évitement sans contact", _ecart_min > VehiculeFunival.DEMI_LARGEUR * 2.0 + 0.1,
					"entraxe mini %.2f m" % _ecart_min)
				_verif("Funival : trajet de 4 min 40 à 5 min 20 (vidéo de la montée ≈ 304 s ; RM.net 5 min), ralenti dans l'évitement", duree > 280.0 and duree < 320.0, "%.0f s" % duree)
				var cm: Mesh = _lg._cables.mesh if _lg._cables != null else null
				_verif("Funival : câbles tracteur et inférieur posés", cm != null and cm.get_surface_count() > 0 and (cm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 100)
				_phase = 3
				_t = 0.0
			elif _t > 700.0:
				_verif("Funival : un trajet complet", false, "phase %s, d0 %.0f" % [_lg._phase, d0])
				_fin()
		3:
			# skieur posé dans le compartiment 4 du véhicule à quai en gare aval, portes ouvertes
			for i in range(2):
				if _lg.zone_vehicule(i) == "gare_aval" and _lg._phase == "quai" and _lg._t_quai < Telepherique.T_QUAI - 3.0 \
						and _lg._t_quai > 8.0 and rm._repos <= 0.0:
					var v: VehiculeFunival = _lg.vehicule(i)
					var dedans: Vector3 = v.global_transform * (v.place_assise(4) + Vector3(0, 0.05, 0))
					sk.activer(dedans, 0.0)
					_y0 = dedans.y
					_phase = 4
					_t = 0.0
					return
			if _t > 700.0:
				_verif("Funival : un véhicule à quai en gare aval", false)
				_fin()
		4:
			if _t > 1.0 and _t < 1.0 + 1.0 / 60.0:
				_verif("Funival : à bord, debout dans un compartiment", not rm.a_bord.is_empty() and rm.a_bord[0] == _lg,
					"a_bord %s" % str(not rm.a_bord.is_empty()))
				if rm.a_bord.is_empty():
					_fin()
					return
			if _t > 1.5 and rm.a_bord.is_empty():
				_verif("Funival : emporté jusqu'en haut, sorti portes ouvertes", not sk.embarque and sk.global_position.y > _y0 + 800.0,
					"%.0f s, +%.0f m" % [_t, sk.global_position.y - _y0])
				# il tient debout sur le quai quelques secondes après (pas de chute dans la fosse)
				_phase = 5
				_t = 0.0
			elif _t > 700.0:
				_verif("Funival : arrivé en haut", false, "toujours à bord")
				_fin()
		5:
			if _t > 4.0:
				_verif("Funival : debout sur le quai amont après la sortie", sk.global_position.y > _y0 + 795.0,
					"+%.0f m" % (sk.global_position.y - _y0))
				_fin()
