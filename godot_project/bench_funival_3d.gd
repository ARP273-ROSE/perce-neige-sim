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
var _d_pire: float = 0.0
var _t_quai_atteint: float = -1.0
var _v_quai: float = -1.0
var _v_croisement: float = -1.0
var _v_ligne_avant: float = 0.0
var _v_ligne_apres: float = 0.0
var _v_dans_croisement: float = 0.0
var _i_veh: int = 0
var _z_bord: float = 0.0
var _yaw_bord: float = 0.0
var _roule_vu: bool = false
var _t_marche: float = 0.0
var _y_sortie: float = 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _pente_max_voie() -> float:
	var m: float = 0.0
	var d: float = 5.0
	while d < _lg.longueur_h() - 5.0:
		m = maxf(m, _lg.pente_voie(d))
		d += 5.0
	return m


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
			var L: float = _lg.longueur_h()
			_verif("Funival : deux véhicules", _lg.nombre_vehicules() == 2)
			# dehors : voie au-dessus du sol (poutre sur piles) ; tunnel : sous la roche
			var pire_dehors: float = INF
			var pire_roche: float = INF
			var d: float = 5.0
			while d < L - 5.0:
				var y: float = _lg.y_voie(d)
				var sol: float = _lg._sol(0.0, -d)
				if d > 120.0 and d < _lg.portail_d - 30.0:     # (gare aval : voie en fosse, puis déblai de sortie de gare)
					if y - 1.0 - sol < pire_dehors:
						_d_pire = d
					pire_dehors = minf(pire_dehors, y - 1.0 - sol)
				elif d > _lg.portail_d + 30.0 and d < L - 60.0:
					pire_roche = minf(pire_roche, sol - (y + 2.0 * Funival.R_TUNNEL))
				d += 2.0
			print("FUNIVAL L=%.0f m, portail %.0f, voie aval %.1f amont %.1f (gare %.1f) portail %.1f ; montée basse %.0f m, 53 %% jusqu'à d=%.0f ; pente max %.1f %%" % [L, _lg.portail_d, _lg.y_voie(0.0), _lg.y_voie(L), _lg._y_amont, _lg.y_voie(_lg.portail_d), _lg._rampe_bas, _lg._d53_fin, 100.0 * _pente_max_voie()])
			_verif("Funival : poutre dehors au-dessus du sol (≥ -1,5 m : déblais courts admis)", pire_dehors > -1.5, "%.2f m à d=%.0f" % [pire_dehors, _d_pire])
			_verif("Funival : tunnel sous la roche", pire_roche > 0.0, "couverture mini %.2f m" % pire_roche)
			_phase = 2
			_t = 0.0
		2:
			# un aller : départ, croisement, arrivée
			var d0: float = _lg._vehicules[0][1]
			var d1: float = _lg._vehicules[1][1]
			if _t_depart < 0.0 and _lg._phase == "route":
				_t_depart = _t
			# nez au début du quai d'arrivée : instant et vitesse (Perce-Neige : V_CREEP)
			if _t_depart >= 0.0 and _t_quai_atteint < 0.0 and _lg._phase == "route":
				var but: float = _lg._x_quai(false) if _lg._sens > 0.0 else _lg._x_quai(true)
				# vitesses en ligne et à l'attaque du croisement
				var d_ev: float = absf(_lg._s - _lg.longueur_h() * 0.5) - (Funival.L_EVITEMENT * 0.5 + Funival.L_RACCORD + VehiculeFunival.DEMI_L)
				if d_ev <= 0.0:
					if _v_croisement < 0.0:
						_v_croisement = absf(_lg._v)
					_v_dans_croisement = maxf(_v_dans_croisement, absf(_lg._v))
				elif _v_croisement < 0.0:
					_v_ligne_avant = maxf(_v_ligne_avant, absf(_lg._v))
				else:
					_v_ligne_apres = maxf(_v_ligne_apres, absf(_lg._v))
				if absf(but - _lg._s) <= _lg.longueur_quai_nez():
					_t_quai_atteint = _t - _t_depart
					_v_quai = absf(_lg._v)
			if absf(d0 - d1) < VehiculeFunival.DEMI_L * 2.0 + 2.0:
				var p0: Vector3 = (_lg.vehicule(0) as Node3D).position
				var p1: Vector3 = (_lg.vehicule(1) as Node3D).position
				_ecart_min = minf(_ecart_min, absf(p0.x - p1.x))
			if _t_depart >= 0.0 and _lg._phase == "quai":
				var duree: float = _t - _t_depart
				_verif("Funival : croisement dans l'évitement sans contact", _ecart_min > VehiculeFunival.DEMI_LARGEUR * 2.0 + 0.1,
					"entraxe mini %.2f m" % _ecart_min)
				# consigne d'utilisateur du 10/11/2026 : 12 m/s, 8 m/s à l'attaque du croisement, retour à 12, 1 m/s au début du quai
				_verif("Funival : 12 m/s en ligne avant et après le croisement", _v_ligne_avant > 11.9 and _v_ligne_avant <= 12.01 and _v_ligne_apres > 11.9 and _v_ligne_apres <= 12.01,
					"%.2f puis %.2f m/s" % [_v_ligne_avant, _v_ligne_apres])
				_verif("Funival : croisement attaqué et parcouru à 8 m/s", absf(_v_croisement - 8.0) < 0.3 and _v_dans_croisement < 8.3,
					"attaque %.2f, maxi %.2f m/s" % [_v_croisement, _v_dans_croisement])
				_verif("Funival : début du quai à 1 m/s", absf(_v_quai - 1.0) < 0.15, "%.2f m/s" % _v_quai)
				print("FUNIVAL durée : début du quai %.0f s, arrêt %.0f s" % [_t_quai_atteint, duree])
				var cm: Mesh = _lg._cables.mesh if _lg._cables != null else null
				_verif("Funival : câble inférieur posé", cm != null and cm.get_surface_count() > 0 and (cm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 50)
				# voie du Perce-Neige : câble tracteur, galets, et rails de TrackBuilder sur ceux où roulent les véhicules
				var vp: TrackBuilder = _lg.voie_pn
				_verif("Funival : voie du Perce-Neige (câble toronné, galets)", vp != null and vp.cable_left_segments.size() > 10
					and vp.galets_count() > 50, "%d tronçons de câble, %d galets" % [vp.cable_left_segments.size() if vp != null else 0,
					vp.galets_count() if vp != null else 0])
				# supports numérotés (relevé d'utilisateur) : 003 au bout du quai aval, 200 à l'entrée du quai amont, 204 au
				# bout du quai amont
				var sts: Array = vp.station_list() if vp != null else []
				var lq3: float = 2.0 * VehiculeFunival.DEMI_L + 2.0
				var pos: Dictionary = {}
				for st in sts:
					if int(st.get("num", 0)) in [3, 200, 204]:
						pos[int(st.num)] = _lg.d_de_s(float(st.s))
				var Lh: float = _lg.longueur_h()
				_verif("Funival : supports 003, 200 et 204 aux bouts des quais, 204 au total", sts.size() == 204 and pos.size() == 3
					and absf(pos[3] - lq3) < 1.6 and absf(pos[200] - (Lh - lq3)) < 1.6 and absf(pos[204] - (Lh - 1.0)) < 1.6,
					"%d supports ; 003 à d=%.1f (quai %.1f), 200 à %.1f (%.1f), 204 à %.1f (%.1f)" % [sts.size(), pos.get(3, -1.0), lq3,
					pos.get(200, -1.0), Lh - lq3, pos.get(204, -1.0), Lh - 1.0])
				var ecart_rails: float = 0.0
				var dd: float = 5.0
				while dd < _lg.longueur_h() - 5.0:
					var xf: Transform3D = _lg.tunnel_pn.transform_at(_lg.s_de_d(dd))
					var pr: Vector3 = xf.origin - xf.basis.y * Funival.RAIL_SUR_CENTRE
					var er: Vector3 = pr - Vector3(0.0, _lg.y_voie(dd), -dd)
					ecart_rails = maxf(ecart_rails, er.length())
					dd += 10.0
				_verif("Funival : rails du Perce-Neige sous les roues (≤ 5 cm)", ecart_rails < 0.05, "écart maxi %.3f m" % ecart_rails)
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
					_i_veh = i
					_phase = 4
					_t = 0.0
					return
			if _t > 700.0:
				_verif("Funival : un véhicule à quai en gare aval", false)
				_fin()
		4:
			# à bord, on marche librement (porté par le véhicule, comme dans le Perce-Neige)
			var v4: VehiculeFunival = _lg.vehicule(_i_veh)
			var loc4: Vector3 = v4.global_transform.affine_inverse() * sk.global_position
			if _t > 1.0 and _t < 1.0 + 1.0 / 60.0:
				_z_bord = loc4.z
				var av4: Vector3 = v4.global_transform.basis.z * -1.0
				_yaw_bord = atan2(-av4.x, -av4.z)
			if _t > 1.0 and _t < 4.0:
				sk.touches_ext = 1
				sk.cam_yaw = _yaw_bord
			elif _t >= 4.0 and _t < 4.0 + 1.0 / 60.0:
				sk.touches_ext = 0
				_verif("Funival : on marche dans le véhicule à quai", absf(loc4.z - _z_bord) > 1.5, "%.1f m en 3 s" % absf(loc4.z - _z_bord))
				_verif("Funival : pas de place assignée", rm.a_bord.is_empty() and not sk.embarque)
			if _lg._phase == "route" and absf(_lg._v) > 5.0 and not _roule_vu:
				_roule_vu = true
				_z_bord = loc4.z
				_verif("Funival : porté par le véhicule qui roule", sk.support == _lg._corps[_i_veh][0], "support %s" % str(sk.support))
			if _roule_vu and _t_marche < 3.0 and _lg._phase == "route":
				_t_marche += 1.0 / 60.0
				sk.touches_ext = 2
				sk.cam_yaw = _yaw_bord
				if _t_marche >= 3.0:
					sk.touches_ext = 0
					_verif("Funival : on marche dans le véhicule en roulant", absf(loc4.z - _z_bord) > 1.5, "%.1f m en 3 s à %.1f m/s" % [absf(loc4.z - _z_bord), absf(_lg._v)])
			if _roule_vu and _lg._phase == "quai" and _lg.portes_ouvertes():
				var dy: float = loc4.y - VehiculeFunival.y_plancher(loc4.z)
				_verif("Funival : emporté jusqu'en haut, sur le plancher", sk.global_position.y > _y0 + 800.0 and absf(dy) < 0.4,
					"%.0f s, +%.0f m, %.2f m au-dessus du plancher" % [_t, sk.global_position.y - _y0, dy])
				var cote4: Vector3 = v4.global_transform.basis.x
				_yaw_bord = atan2(-cote4.x, -cote4.z)
				_y_sortie = sk.global_position.y
				_phase = 5
				_t = 0.0
			elif _t > 700.0:
				_verif("Funival : arrivé en haut", false, "phase %s" % _lg._phase)
				_fin()
		5:
			# sortie à pied, côté +x du véhicule : vers le quai, sans chute
			var v5: VehiculeFunival = _lg.vehicule(_i_veh)
			sk.touches_ext = 1 if _t < 4.0 else 0
			sk.cam_yaw = _yaw_bord
			if _t > 5.0:
				var loc5: Vector3 = v5.global_transform.affine_inverse() * sk.global_position
				_verif("Funival : sorti à pied sur le quai amont, sans chute", absf(loc5.x) > VehiculeFunival.DEMI_LARGEUR and sk.global_position.y > _y_sortie - 1.0,
					"x local %.2f, %.2f m sous la sortie" % [loc5.x, _y_sortie - sk.global_position.y])
				_fin()
