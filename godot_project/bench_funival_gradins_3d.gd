## Banc des gradins du Funival (essai à pied du 08/11/2026) : on monte et l'on redescend les gradins de La Daille
## sans être bloqué ni tomber, et l'on sort à pied d'un véhicule à quai avant son départ.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_funival_gradins_3d.gd -- --mode=normal
##
## (Banc du Funival : la ligne se construit, la voie reste au-dessus du sol dehors et sous la roche dans le tunnel,
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
var _yaw_aval: float = 0.0
var _cote: float = -1.0           # gradins de gauche (attente), puis de droite (sortie)


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_FUNIVAL_GRADINS " + ("OK" if _ok else "ECHEC"))
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
	if _f < _t0 + 60 or not _main.mode_skieur:
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
			_phase = 6
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
				_verif("Funival : trajet de 3 min 20 à 5 min 30 (2 270 m à 12 m/s : 3 min 30 ; fiche : 5 min, Wikipédia : 4 min 47)", duree > 200.0 and duree < 330.0, "%.0f s" % duree)
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
					_phase = 6        # (le trajet à bord : bench_funival_3d)
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
				_phase = 6
				_t = 0.0
		6:
			# ramené à La Daille par le jeu (relief et collisions chargés autour), puis posé au pied des gradins
			var W: float = VehiculeFunival.DEMI_LARGEUR + 0.05
			var xc: float = _cote * (W + (3.0 if _cote < 0.0 else 1.75))
			var p0: Vector3 = _lg.global_transform * Vector3(xc, _lg._sol(xc, 6.0) + 0.3, 6.0)
			if sk.global_position.distance_to(p0) > 150.0 or _t < 5.0:
				if _t > 120.0:
					_verif("Funival : retour à La Daille pour l'essai à pied", false)
					_fin()
				return
			if sk.chausse:
				sk.basculer_ski()
			sk.activer(p0, 0.0)
			sk.dernier_sol = p0
			var amont: Vector3 = _lg.global_transform.basis * Vector3(0, 0, -1)
			sk.cam_yaw = atan2(-amont.x, -amont.z)
			_yaw_amont = sk.cam_yaw
			_y0 = p0.y
			_y_prec = p0.y
			_chute_max = 0.0
			rm._repos = 60.0
			_phase = 7
			_t = 0.0
		7:
			sk.touches_ext = 1
			sk.cam_yaw = _yaw_amont           # (le jeu réoriente la vue en route : la direction est tenue)
			if _t > 0.5:          # (la première image suit la téléportation)
				_chute_max = maxf(_chute_max, _y_prec - sk.global_position.y)
			_y_prec = sk.global_position.y
			if _t > 20.0:
				var gain: float = sk.global_position.y - _y0
				_verif("Funival : on monte les gradins de %s de La Daille à pied" % ("gauche" if _cote < 0.0 else "droite"), gain > 4.0, "+%.1f m en 20 s" % gain)
				_verif("Funival : sans chute en montant", _chute_max < 0.25, "plus forte descente par image %.2f m" % _chute_max)
				_chute_max = 0.0
				_phase = 8
				_t = 0.0
		8:
			sk.touches_ext = 2
			sk.cam_yaw = _yaw_amont           # (le jeu réoriente la vue en route : la direction est tenue)
			_chute_max = maxf(_chute_max, _y_prec - sk.global_position.y)
			_y_prec = sk.global_position.y
			if _t > 20.0:
				sk.touches_ext = 0
				_verif("Funival : on redescend les gradins sans chute", _chute_max < 0.25 and sk.global_position.y < _y0 + 1.5,
					"plus forte descente par image %.2f m, %.1f m au-dessus du départ" % [_chute_max, sk.global_position.y - _y0])
				if _cote < 0.0:
					_cote = 1.0
					_phase = 6
					_t = 0.0
					return
				rm._repos = 0.0
				_phase = 9
				_t = 0.0
		9:
			# à bord d'un véhicule à quai en gare aval, portes ouvertes : quelques pas, et l'on est dehors
			for i2 in range(2):
				if _lg.zone_vehicule(i2) == "gare_aval" and _lg.portes_ouvertes() and _lg._t_quai > 12.0 and rm._repos <= 0.0:
					var v2: VehiculeFunival = _lg.vehicule(i2)
					sk.activer(v2.global_transform * (v2.place_assise(2) + Vector3(0, 0.05, 0)), 0.0)
					_phase = 10
					_t = 0.0
					return
			if _t > 700.0:
				_verif("Funival : véhicule à quai pour l'essai de sortie", false)
				_fin()
		10:
			if _t > 2.5 and _t < 4.0:
				sk.touches_ext = 8
			elif _t >= 4.0:
				sk.touches_ext = 0
				_verif("Funival : sortie à pied avant le départ", rm.a_bord.is_empty() and not sk.embarque,
					"a_bord %s" % str(not rm.a_bord.is_empty()))
				_phase = 11
				_t = 0.0
		11:
			# gare amont : posé en bas des escaliers de droite (deux fois, le temps que les collisions se chargent)
			var W2: float = VehiculeFunival.DEMI_LARGEUR + 0.05
			var dq2: float = _lg._x_quai(false) - VehiculeFunival.DEMI_L + 1.0
			var p2: Vector3 = _lg.global_transform * Vector3(W2 + 2.0, VehiculeFunival.y_plancher_monde(_lg, dq2) + 0.3, -dq2)
			if _t < 1.5 / 60.0 or (_t > 8.0 and _t < 8.0 + 1.5 / 60.0):
				sk.activer(p2, 0.0)
				sk.dernier_sol = p2
				rm._repos = 60.0
			if _t > 9.0:
				_y0 = sk.global_position.y
				_y_prec = _y0
				_chute_max = 0.0
				var amont2: Vector3 = _lg.global_transform.basis * Vector3(0, 0, -1)
				_yaw_amont = atan2(-amont2.x, -amont2.z)
				_phase = 12
				_t = 0.0
		12:
			sk.touches_ext = 1
			sk.cam_yaw = _yaw_amont
			if _t > 0.5:
				_chute_max = maxf(_chute_max, _y_prec - sk.global_position.y)
			_y_prec = sk.global_position.y
			if _t > 42.0:
				sk.touches_ext = 0
				var g2: float = sk.global_position.y - _y0
				var loc2: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
				var haut2: float = (_lg.global_transform * Vector3(0, VehiculeFunival.y_plancher_monde(_lg, _lg.longueur_h() - 1.0), 0)).y - _y0
				_verif("Funival : on monte le quai de Bellevarde à pied, jusqu'en haut", g2 > haut2 - 1.5,
					"+%.1f m en 30 s (haut du quai +%.1f), arrêté à d=%.0f x=%.1f, %s" % [g2, haut2, -loc2.z, loc2.x, sk.debug_marche])
				_verif("Funival : du haut des escaliers, on entre dans le bâtiment", -loc2.z > _lg.longueur_h() + 2.0, "d=%.1f (L=%.1f)" % [-loc2.z, _lg.longueur_h()])
				_verif("Funival : sans chute sur le quai amont", _chute_max < 0.25, "plus forte descente par image %.2f m" % _chute_max)
				_phase = 13
				_t = 0.0
		13:
			# du milieu du bâtiment de Bellevarde, on sort à pied vers les pistes par la porte du pignon du fond
			var L3: float = _lg.longueur_h()
			var p3: Vector3 = _lg.global_transform * Vector3(0.0, _lg.sol_batiment() + 0.3, -(L3 + 11.0))
			if _t < 1.5 / 60.0:
				sk.activer(p3, 0.0)
				sk.dernier_sol = p3
				rm._repos = 60.0
			if _t > 2.0:
				sk.touches_ext = 1
				sk.cam_yaw = _yaw_amont
			if _t > 14.0:
				sk.touches_ext = 0
				var loc3: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
				_verif("Funival : on sort du bâtiment de Bellevarde par la porte du fond", -loc3.z > L3 + 23.0,
					"arrêté à d=%.1f (fond à %.1f) x=%.1f" % [-loc3.z, L3 + 22.0, loc3.x])
				_phase = 14
				_t = 0.0
		14:
			# et on rentre par le perron (avant : marche de 1,5 à 1,9 m, bloqué au pied du seuil)
			var L4: float = _lg.longueur_h()
			if _t < 1.5 / 60.0:
				var q: Vector3 = _lg.global_transform.basis * Vector3(0, 0, 1)
				sk.cam_yaw = atan2(-q.x, -q.z)
				_yaw_aval = sk.cam_yaw
			sk.touches_ext = 1
			sk.cam_yaw = _yaw_aval
			if _t > 12.0:
				sk.touches_ext = 0
				var loc4: Vector3 = _lg.global_transform.affine_inverse() * sk.global_position
				var h4: float = (_lg.global_transform.affine_inverse() * sk.global_position).y - _lg.sol_batiment()
				_verif("Funival : on rentre dans le bâtiment de Bellevarde par le perron du fond", -loc4.z < L4 + 20.0 and absf(h4) < 0.5,
					"arrêté à d=%.1f x=%.1f, %.2f m / sol du bâtiment" % [-loc4.z, loc4.x, h4])
				_fin()
