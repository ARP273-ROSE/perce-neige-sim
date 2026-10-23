class_name Telepherique
extends LigneRemontee
## Téléphérique va-et-vient (Grande Motte, Von Roll 1975 ; fiche et photos du
## reportage remontees-mecaniques.net) : deux cabines, une par voie, chacune
## sur son câble porteur ; un câble tracteur sans fin les relie, l'une monte
## pendant que l'autre descend. Cycle : quai (portes ouvertes), départ,
## pleine vitesse (10 m/s), 5,2 m/s au passage du pylône, arrivée en
## douceur, quai. Le poste de commande de la classe mère s'y applique
## (marche, arrêt, urgence, vitesse).
##
## Les véhicules : _vehicules[i] = [VehiculeRemontee, d] avec d la distance
## horizontale depuis le nez de la gare aval (négative dans la gare aval,
## au-delà de L dans la gare amont).

const D_QUAI: float = 7.0              # du nez de gare au centre de la cabine à quai
const T_QUAI: float = 45.0             # attente à quai (embarquement), s
const V_PYLONE: float = 5.2            # vitesse au passage du pylône (fiche)
const A_ROUTE: float = 0.6             # accélération / freinage de service (m/s²)
const VOIE_TPH: float = 8.0            # écart des deux voies (photos du pylône)

var _sens: float = 1.0                 # +1 : la cabine 0 monte
var _s: float = 0.0                    # position de la cabine 0 (d)
var _v: float = 0.0                    # vitesse signée de la cabine 0 (m/s)
var _phase: String = "quai"            # quai, route
var _t_quai: float = 20.0
var _mat_tracteurs: ShaderMaterial = null


func vaetvient() -> bool:
	return true


func masse_vehicule() -> float:
	return 4500.0                       # caisse Swoboda, chariot et suspente


func tension_h() -> float:
	return 900000.0                     # porteur de la Grande Motte, contrepoids aval


func regime() -> float:
	return 1.0


func vitesse_en(_s2: float) -> float:
	return absf(_v)


func _x_quai(aval: bool) -> float:
	return -D_QUAI if aval else longueur_h() + D_QUAI


func zone_vehicule(i: int) -> String:
	var d: float = _vehicules[i][1]
	if d <= 0.0:
		return "gare_aval"
	if d >= longueur_h():
		return "gare_amont"
	return "ligne"


func zone(s: float) -> Array:
	return ["ligne", 0.0, 0.0]


## Cabine i arrivée à quai, portes ouvertes : [gare aval ?] ou [].
func arrivee_cabine(i: int) -> Array:
	if _phase != "quai" or T_QUAI - _t_quai < 2.0:
		return []
	var zn: String = zone_vehicule(i)
	if zn == "ligne":
		return []
	return [zn == "gare_aval"]


func demi_interieur() -> Vector2:
	return Vector2(1.45, 2.70)


func construire() -> void:
	_poulies.clear()
	_terrassements.clear()
	_mat_porteurs = null
	pret = false
	_t_tranche = Time.get_ticks_usec()
	set_process(false)
	for c in get_children():
		c.queue_free()
	_vehicules.clear()
	_corps.clear()
	_pyl.clear()
	voie = VOIE_TPH
	espacement = longueur_h() * 4.0
	H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(famille)
	_calculer_tetes()
	_preparer_nez()
	for aval in [true, false]:
		_gare_tph(aval)
		await _pause()
	await _poser_pylones_treillis()
	_cables_tph()
	for k in range(2):
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = famille
		v.numero = k + 1
		add_child(v)
		v.construire()
		_vehicules.append([v, 0.0])
		await _pause()
	_s = _x_quai(true)
	_maj_positions()
	if avec_collisions:
		_collisions_tph()
		for i in range(2):
			_corps_vehicule(i)
	pret = true
	set_process(true)
	construite.emit()


## Positions : cabine 0 sur la voie de montée à _s, cabine 1 en face.
func _maj_positions() -> void:
	var a: float = _x_quai(true)
	var b: float = _x_quai(false)
	_vehicules[0][1] = _s
	_vehicules[1][1] = a + b - _s
	_charges_ponctuelles()
	for i in range(2):
		_placer(i)


func _process(delta: float) -> void:
	if not pret:
		return
	_dt = delta
	var a: float = _x_quai(true)
	var b: float = _x_quai(false)
	var but: float = b if _sens > 0.0 else a
	if _phase == "quai":
		_v = 0.0
		vitesse_reelle = 0.0
		if etat == "marche":
			_t_quai -= delta
			if _t_quai <= 0.0:
				_phase = "route"
	else:
		# vitesse permise : consigne, pylône (si l'une des cabines y passe),
		# distance de freinage jusqu'au quai
		var v_max: float = vitesse * CRANS[cran]
		var d1: float = _vehicules[0][1]
		var d2: float = _vehicules[1][1]
		# (freinage anticipé : 5,2 m/s atteints à 45 m du pylône, pour les
		# deux cabines qui le croisent en même temps sur leurs voies)
		for p in pylones:
			var dp: float = float(p["d"])
			for dc in [absf(d1 - dp), absf(d2 - dp)]:
				var marge: float = maxf(float(dc) - 45.0, 0.0)
				v_max = minf(v_max, sqrt(V_PYLONE * V_PYLONE + 2.0 * A_ROUTE * marge))
		var reste: float = absf(but - _s)
		v_max = minf(v_max, maxf(sqrt(2.0 * A_ROUTE * maxf(reste - 0.3, 0.0)), 0.35))
		if etat != "marche":
			v_max = 0.0
		var a_frein: float = A_URGENCE if etat == "urgence" else A_ROUTE
		var va: float = absf(_v)
		va = move_toward(va, v_max, (A_ROUTE if v_max > va else a_frein) * delta)
		_v = va * _sens
		_s += _v * delta
		if (_sens > 0.0 and _s >= but) or (_sens < 0.0 and _s <= but):
			_s = but
			_v = 0.0
			_phase = "quai"
			_t_quai = T_QUAI
			_sens = -_sens
		if etat == "arret_normal" and va <= 0.0:
			etat = "arret"
	vitesse_reelle = absf(_v)
	_maj_positions()
	if _mat_cable != null:
		_phase_cable = fposmod(_phase_cable + _v * delta, 0.45)
		_mat_cable.set_shader_parameter("cable_phase", _phase_cable)
	_dt = 0.0


## Hauteur du chariot (le porteur, sous la charge) en d sur une voie.
func _y_chariot(d: float, montee: bool) -> float:
	var L: float = longueur_h()
	if d <= 0.0:
		return terrain(0.0) + H_CABLE_GARE
	if d >= L:
		return terrain(L) + H_CABLE_GARE
	return y_cable(d, montee) - _fleche(d, montee)


func _placer(i: int) -> void:
	var v: VehiculeRemontee = _vehicules[i][0]
	var d: float = _vehicules[i][1]
	var montee: bool = i == 0
	var x: float = _x_brin(montee)
	var p: Vector3 = Vector3(x, _y_chariot(d, montee), -d)
	var b: Basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	v.transform = Transform3D(b, p)
	var pente: float = atan2(_y_chariot(d + 2.0, montee) - _y_chariot(d - 2.0, montee), 4.0)
	v.inclinaison(pente)
	if _dt > 0.0:
		var m0: float = v.masse
		v.masse = m0 + 115.0 * 80.0 * 0.6
		v.balancer(_dt, zone_vehicule(i) != "ligne")
		v.masse = m0
	var porte: float = 0.0
	if _phase == "quai" and zone_vehicule(i) != "ligne":
		porte = clampf(minf(T_QUAI - _t_quai, _t_quai) / 1.5, 0.0, 1.0)
	v.portes(porte)
	if i < _corps.size() and _corps[i] != null:
		var pv: Vector3 = v.pivot
		var bal: Transform3D = Transform3D(Basis.from_euler(Vector3(v.phi, 0.0, v.psi)), pv) * Transform3D(Basis.IDENTITY, -pv)
		(_corps[i][0] as Node3D).transform = Transform3D(b, p) * bal
		for cs in _corps[i][1]:
			(cs as CollisionShape3D).disabled = porte > 0.5


## Charges : une cabine par voie (60 % de passagers).
func _charges_ponctuelles() -> void:
	if _mat_cable == null or _n_appuis < 2:
		return
	var listes: Array = [[], []]
	for i in range(2):
		var d: float = _vehicules[i][1]
		if d > 0.0 and d < longueur_h():
			listes[i].append(Vector2(d, (masse_vehicule() + 115.0 * 80.0 * 0.6) * 9.81 / _tension))
	_charges = listes
	for k in range(2):
		var packs: Array = []
		var l2: Array = listes[k]
		for j in range(32):
			var q: Vector2 = l2[j * 2] if j * 2 < l2.size() else Vector2.ZERO
			packs.append(Vector4(q.x, q.y, 0.0, 0.0))
		for m in _mats_charges():
			m.set_shader_parameter("charges_m" if k == 0 else "charges_d", PackedVector4Array(packs))
			m.set_shader_parameter("n_charges_m" if k == 0 else "n_charges_d", l2.size())


func _mats_charges() -> Array:
	var r: Array = []
	for m in [_mat_cable, _mat_porteurs]:
		if m != null:
			r.append(m)
	return r


## Câbles : un porteur lisse par voie (ancré en gare), le tracteur à torons
## 0,45 m sous lui, et 8 cavaliers par voie qui le portent.
func _cables_tph() -> void:
	var c: Node3D = Node3D.new()
	c.name = "Cable"
	add_child(c)
	_mat_cable = RemonteeKit.materiau_cable_tracteur(40.0)
	_mat_porteurs = RemonteeKit.materiau_cable_tracteur(50.0)
	_mat_porteurs.set_shader_parameter("lisse", true)
	var L: float = longueur_h()
	for montee in [true, false]:
		var x0: float = _x_brin(montee)
		var por: PackedVector3Array = PackedVector3Array()
		var tra: PackedVector3Array = PackedVector3Array()
		var d: float = -D_QUAI - 6.0
		while d <= L + D_QUAI + 6.0:
			var dd: float = clampf(d, 0.0, L)
			var y: float = y_cable(dd, montee) if d > 0.0 and d < L else terrain(0.0 if d <= 0.0 else L) + H_CABLE_GARE
			por.append(Vector3(x0, y, -d))
			tra.append(Vector3(x0, y - 0.45, -d))
			d += 1.0 if d < 30.0 or d > L - 30.0 else 5.0
		RemonteeKit.tube(c, por, 0.025, "cable", 8, _mat_porteurs)
		RemonteeKit.tube(c, tra, 0.020, "cable", 8, _mat_cable)
		# cavaliers
		for k in range(8):
			var dc: float = L * (k + 0.5) / 8.0
			var ok: bool = true
			for p in pylones:
				if absf(dc - float(p["d"])) < 30.0:
					ok = false
			if not ok:
				dc += 40.0
			var cv: Node3D = Node3D.new()
			cv.position = Vector3(x0, y_cable(dc, montee), -dc)
			cv.rotation.x = atan2(y_cable(dc + 2.0, montee) - y_cable(dc - 2.0, montee), 4.0)
			c.add_child(cv)
			RemonteeKit.boite_en(cv, Vector3(0.12, 0.14, 0.40), Vector3(0, 0.0, 0), "galva_pylone")
			RemonteeKit.poutre(cv, Vector3(0.10, -0.05, 0), Vector3(0.10, -0.55, 0), 0.06, 0.06, "galva_pylone")
			RemonteeKit.boite_en(cv, Vector3(0.24, 0.05, 0.30), Vector3(0.02, -0.55, 0), "galva_pylone")
			RemonteeKit.galet(cv, Vector3(0, -0.45 - 0.02 - 0.12, 0), 0.12)
	_preparer_charges()


## Gares : quai de béton à hauteur du plancher des cabines, deux baies.
## Aval (photos) : bâtiment à bardage gris, passerelle et escalier, grand
## portique en A au-dessus des baies ; amont : quai ouvert, portique en
## treillis, tambours d'ancrage des porteurs inclinés, poste de vigie.
func _gare_tph(aval: bool) -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAval" if aval else "GareAmont"
	var L: float = longueur_h()
	g.position = Vector3(0, terrain(0.0 if aval else L), 0)
	add_child(g)
	var sg: float = 1.0 if aval else -1.0               # vers le fond de la gare
	var z0: float = 0.0 if aval else -L
	var hx: float = voie * 0.5 + 3.0
	var lq: float = 2.0 * D_QUAI + 2.0
	# quai : dalle de béton sur un remblai de neige damée jusqu'au terrain le
	# plus bas sous elle (il flottait sur la pente)
	var prof: float = _profondeur_quai(aval) + 0.6
	RemonteeKit.boite_en(g, Vector3(2.0 * hx, 0.5, lq), Vector3(0, -0.25, z0 + sg * lq * 0.5), "beton")
	RemonteeKit.boite_en(g, Vector3(2.0 * hx + 1.0, prof, lq + 1.0), Vector3(0, -0.5 - prof * 0.5, z0 + sg * lq * 0.5), "neige_damee")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.06, 1.0, lq), Vector3(sx * hx, 0.5, z0 + sg * lq * 0.5), "galva_pylone")
	# portique en A au-dessus des baies (il dévie porteurs et tracteur)
	var hp: float = H_CABLE_GARE + 6.0
	for sx in [-1.0, 1.0]:
		var xb: float = sx * voie * 0.5
		for sz in [-1.0, 1.0]:
			RemonteeKit.poutre(g, Vector3(xb + sx * 1.8, 0, z0 + sg * D_QUAI + sz * 3.5), Vector3(xb, hp, z0 + sg * D_QUAI), 0.30, 0.30, "galva_pylone")
		RemonteeKit.boite_en(g, Vector3(0.9, 0.9, 2.4), Vector3(xb, hp + 0.3, z0 + sg * D_QUAI), "galva_pylone")
		RemonteeKit.galet(g, Vector3(xb, H_CABLE_GARE - 0.45 - 0.25, z0 + sg * 1.0), 0.25)
	RemonteeKit.poutre(g, Vector3(-voie * 0.5, hp, z0 + sg * D_QUAI), Vector3(voie * 0.5, hp, z0 + sg * D_QUAI), 0.6, 0.5, "galva_pylone")
	if aval:
		# bâtiment à bardage gris derrière le quai, bandeau vitré, enseigne
		var zb: float = z0 + sg * (lq + 9.0)
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 4.0, 12.0, 18.0), Vector3(0, 6.0 - 3.0, zb), "galva_pylone")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 4.1, 1.6, 18.1), Vector3(0, 6.5, zb), "vitre_teintee")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 4.6, 0.4, 18.6), Vector3(0, 9.2, zb), "peinture_anthracite")
		var lab: Label3D = Label3D.new()
		lab.text = "TÉLÉPHÉRIQUE DE LA GRANDE MOTTE"
		lab.font_size = 120
		lab.pixel_size = 0.004
		lab.modulate = Color(0.1, 0.12, 0.16)
		lab.outline_size = 0
		lab.position = Vector3(0, 8.4, zb + 9.06)
		g.add_child(lab)
		# escalier d'accès sur le côté
		for k in range(10):
			RemonteeKit.boite_en(g, Vector3(2.0, 0.18, 0.35), Vector3(-hx - 1.2, -2.8 + k * 0.3, z0 + sg * (4.0 + k * 0.35)), "galva_pylone")
	else:
		# tambours d'ancrage des porteurs, inclinés, et poste de vigie
		var za: float = z0 + sg * (lq + 6.0)
		for sx in [-1.0, 1.0]:
			RemonteeKit.cylindre(g, 2.2, 2.2, 0.9, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(sx * voie * 0.5, 1.6, za)), "peinture_anthracite", 32)
			RemonteeKit.cylindre(g, 0.4, 0.4, 1.0, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(sx * voie * 0.5, 1.6, za)), "acier", 16)
		RemonteeKit.boite_en(g, Vector3(2.0 * hx, 1.2, 8.0), Vector3(0, -0.6, za), "beton")
		RemonteeKit.boite_en(g, Vector3(3.0, 2.6, 3.0), Vector3(hx - 1.5, 1.3, z0 + sg * (lq - 2.0)), "galva_pylone")
		RemonteeKit.boite_en(g, Vector3(3.05, 0.8, 3.05), Vector3(hx - 1.5, 2.0, z0 + sg * (lq - 2.0)), "vitre_teintee")
	MeshMerge.merge(g, [], "Gare")


## Profondeur du terrain le plus bas sous le quai (m sous la dalle).
func _profondeur_quai(aval: bool) -> float:
	var L: float = longueur_h()
	var y0: float = terrain(0.0 if aval else L)
	var sg: float = 1.0 if aval else -1.0
	var z0: float = 0.0 if aval else -L
	var hx: float = voie * 0.5 + 3.0
	var lq: float = 2.0 * D_QUAI + 2.0
	var bas: float = 0.0
	for xi in [-hx, 0.0, hx]:
		for k in range(5):
			var z: float = z0 + sg * lq * float(k) / 4.0
			bas = maxf(bas, y0 - _sol(float(xi), z))
	return clampf(bas, 1.0, 40.0)


func _collisions_tph() -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsLigne"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	add_child(corps)
	var L: float = longueur_h()
	var boite := func(taille: Vector3, centre: Vector3) -> void:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var bx: BoxShape3D = BoxShape3D.new()
		bx.size = taille
		cs.shape = bx
		cs.position = centre
		corps.add_child(cs)
	var hx: float = voie * 0.5 + 3.0
	var lq: float = 2.0 * D_QUAI + 2.0
	for aval in [true, false]:
		var sg: float = 1.0 if aval else -1.0
		var z0: float = 0.0 if aval else -L
		var y0: float = terrain(0.0 if aval else L)
		boite.call(Vector3(2.0 * hx, 6.0, lq), Vector3(0, y0 - 3.0, z0 + sg * lq * 0.5))
	for i in range(pylones.size()):
		var d: float = float(pylones[i]["d"])
		var t: float = terrain(d)
		var h: float = _tetes[i] - t - 3.0
		boite.call(Vector3(clampf(h * 0.22, 4.0, 12.0), h, clampf(h * 0.22, 4.0, 12.0) * 0.6), Vector3(0, t + h * 0.5, -d))


## Puissance au câble (kW) : la cabine qui monte contre celle qui descend
## (même charge : seules la pente et les pertes comptent ici).
func puissance_kw() -> float:
	var L: float = longueur_h()
	var dh: float = terrain(L) - terrain(0.0)
	var p_nom: float = (masse_vehicule() + 115.0 * 80.0) * 9.81 * dh / L * vitesse
	return 0.15 * p_nom * absf(_v) / maxf(vitesse, 0.1) / 1000.0
