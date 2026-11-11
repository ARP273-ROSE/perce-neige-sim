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
## Gare aval déjà bâtie (Grande Motte : bâtiment de la gare du funiculaire) :
## seul un quai est posé dedans.
var gare_aval_existante: bool = false
const T_QUAI: float = 45.0             # attente à quai (embarquement), s
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


## Tension horizontale d'une voie (deux porteurs, contrepoids aval) : 1,2 MN donnent une flèche de 4 à 6 %
## de la portée, cabine chargée à mi-portée, comme sur les photos ; ajustée sur le profil en long des montées
## enregistrées (traces GPS barométriques d'avril 2026) : Grande Motte 1,3 MN (4 montées, écart moyen 2,7 m,
## pylône recalé de 28 m vers l'amont sur la cassure de pente), Fornet 1,1 MN (une montée ; 1,0 MN collait
## mieux mais laissait 1,8 m sous l'éperon amont du relief).
func tension_h() -> float:
	return 1300000.0 if String(name) == "tph_grande_motte" else 1100000.0


## Places d'une cabine (fiches) : 80 au Fornet, 115 à la Grande Motte.
func places_cabine() -> int:
	return 80 if String(name) == "tph_fornet" else 115


## Poids d'une cabine en ligne (N), 60 % de passagers.
func poids_cabine() -> float:
	return (masse_vehicule() + 80.0 * places_cabine() * 0.6) * 9.81


## Chaînette à vide d'une voie (retour d'utilisateur, 11/11/2026 : « physique pas bonne ») : ce sont les
## DEUX porteurs clos qui portent la cabine (Fornet 44 mm, Grande Motte 50 mm ; ~0,0056·d² kg/m chacun),
## pas un câble de 47 mm chargé de véhicules répartis. Le poids de la cabine est une charge ponctuelle
## (_charges_ponctuelles), que le chariot suit comme le câble dessiné.
func _parametres_chainette() -> void:
	var dp: float = 44.0 if String(name) == "tph_fornet" else 50.0
	var w: float = 2.0 * 0.0056 * dp * dp * 9.81
	_a_montee = tension_h() / w
	_a_descente = _a_montee


## Sabot de gare (photos du Fornet : grande poutre-caisson cintrée en porte-à-faux au nez du quai) : les
## porteurs quittent l'horizontale du quai sur un arc de rayon R_SABOT_GARE et rejoignent la pente de la
## ligne au bout du sabot — plus de cassure au nez, où le chariot basculait d'un coup.
const R_SABOT_GARE: float = 24.0


func _preparer_nez() -> void:
	_h_nez = [0.0, 0.0]
	var L: float = longueur_h()
	var p_a: float = (_y_chainette(0.5, true) - _y_chainette(0.0, true)) / 0.5
	var p_b: float = (_y_chainette(L, true) - _y_chainette(L - 0.5, true)) / 0.5
	_h_nez = [absf(p_a) * R_SABOT_GARE * 0.5, absf(p_b) * R_SABOT_GARE * 0.5]


func regime() -> float:
	return 1.0



func _boucle_standard() -> bool:
	return false

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
	_portillons_tph.clear()              # (nœuds de la construction précédente, libérés avec elle)
	_lest.clear()
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
	# Grande Motte : 9 m (photos d'utilisateur du 11/11/2026 : tête du pylône ~9,7 m de large, arrêtée sous les
	# porteurs extérieurs ; fût de ~9,5 m au pied, entre les deux passages de cabine) ; Fornet : 8 m
	voie = 9.0 if String(name) == "tph_grande_motte" else VOIE_TPH
	espacement = longueur_h() * 4.0
	H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(famille)
	contenu_prepare = false
	_noyau_fil = false
	xf_monde = global_transform if is_inside_tree() else transform
	if construction_en_fond and progressif and _fil_possible():
		# comme les autres lignes : contenu construit sur un autre fil, hors
		# de la scène, puis rattaché par paquets (LigneRemontee._fil_fini)
		_chantier = Node3D.new()
		_tache = WorkerThreadPool.add_task(_construire_fil, false, "ligne " + String(name))
		return
	await _construire_corps()
	await _finir_construction()


func _construire_corps() -> void:
	await _calculer_tetes()
	_preparer_nez()
	for aval in [true, false]:
		if gare_aval_existante:
			await _gares_grande_motte(aval)
		elif String(name) == "tph_fornet":
			_gare_fornet(aval)
		else:
			_gare_tph(aval)
		await _pause("téléphérique : gare")
	await _poser_pylones_treillis()
	await _cables_tph()
	await _pause("téléphérique : câbles")
	for k in range(2):
		var v: VehiculeRemontee = VehiculeRemontee.new()
		# (construite ici, par étapes : à l'entrée dans l'arbre, elle l'était déjà une première fois)
		v.construit_par_la_ligne = true
		v.famille = famille
		v.numero = k + 1
		if String(name) == "tph_fornet":
			v.style_tph = "fornet"
		v.cote_tph = signf(_x_brin(k == 0))           # fût de la suspente vers l'extérieur de la ligne
		_enfant(v)
		await v.construire_par_tranches(_pause.bind("téléphérique : cabine"))
		_vehicules.append([v, 0.0])
		await _pause("téléphérique : cabine")
	_s = _x_quai(true)
	_poser_lest()
	_maj_positions()
	_portillons_quai()
	for i2 in range(2):
		_maj_portillons_tph(i2)
	if avec_collisions:
		_collisions_tph()
		await _pause("téléphérique : collisions")
		for i in range(2):
			_corps_vehicule(i)


func _finir_construction() -> void:
	pret = true
	roule = true
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
	_maj_lest()


func _process_corps(delta: float) -> void:
	if not pret:
		return
	delta = _tic_lod(delta)
	if delta < 0.0:
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
		# vitesse permise : consigne, profil relevé au GPS (position de la cabine qui monte), freinage
		# jusqu'au quai puis entrée en gare au pas
		var pr: Dictionary = _profil()
		var v_max: float = minf(vitesse * CRANS[cran], _v_profil(_vehicules[0 if _sens > 0.0 else 1][1], pr))
		var reste: float = absf(but - _s)
		var a_f: float = float(pr["a_frein"])
		v_max = minf(v_max, sqrt(pow(float(pr["v_pas"]), 2.0) + 2.0 * a_f * maxf(reste - float(pr["d_pas"]), 0.0)))
		v_max = minf(v_max, maxf(sqrt(2.0 * 0.3 * maxf(reste - 0.05, 0.0)), 0.08))
		if etat != "marche":
			v_max = 0.0
		var a_frein: float = A_URGENCE if etat == "urgence" else maxf(a_f, A_ROUTE)
		var va: float = absf(_v)
		va = move_toward(va, v_max, (float(pr["a_dem"]) if v_max > va else a_frein) * delta)
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


## Marche relevée au GPS (traces du 26 au 28/04/2026, 4 montées à la Grande Motte, 1 au Fornet ; retour
## d'utilisateur du 11/11/2026 : « courbe de vitesse de la trace GPS pas respectée »), puis relevée à la demande
## (« roule à 10 m/s les deux et accélère un peu le mouvement à l'entrée en gare ») : 10 m/s de bout en bout,
## sans ralenti au pylône ; démarrage et freinage plus francs que ceux relevés (0,45 / 0,31 m/s² à la Grande
## Motte, 0,30 / 0,23 au Fornet), et seulement les derniers mètres au pas. Vitesse (m/s) selon la fraction de
## la ligne parcourue par la cabine qui monte.
const PROFILS: Dictionary = {
	"tph_grande_motte": {"pts": [[0.0, 10.0], [1.0, 10.0]], "a_dem": 0.60, "a_frein": 0.55, "v_pas": 1.2, "d_pas": 8.0},
	"tph_fornet": {"pts": [[0.0, 10.0], [1.0, 10.0]], "a_dem": 0.60, "a_frein": 0.55, "v_pas": 1.2, "d_pas": 8.0},
}
const PROFIL_DEFAUT: Dictionary = {"pts": [[0.0, 10.0], [1.0, 10.0]], "a_dem": A_ROUTE, "a_frein": A_ROUTE, "v_pas": 0.6, "d_pas": 15.0}


func _profil() -> Dictionary:
	return PROFILS.get(String(name), PROFIL_DEFAUT)


## Vitesse du profil quand la cabine qui monte est en d.
func _v_profil(d: float, pr: Dictionary) -> float:
	var f: float = clampf(d / maxf(longueur_h(), 1.0), 0.0, 1.0)
	var pts: Array = pr["pts"]
	for k in range(pts.size() - 1):
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		if f <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), clampf((f - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6), 0.0, 1.0))
	return float(pts[pts.size() - 1][1])


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
		v.masse = m0 + 80.0 * places_cabine() * 0.6
		v.balancer(_dt, zone_vehicule(i) != "ligne")
		v.masse = m0
	var porte: float = 0.0
	if _phase == "quai" and zone_vehicule(i) != "ligne":
		porte = clampf(minf(T_QUAI - _t_quai, _t_quai) / 1.5, 0.0, 1.0)
	v.portes(porte)
	_porte_i = porte
	if collisions_actives and i < _corps.size() and _corps[i] != null:
		var pv: Vector3 = v.pivot
		var bal: Transform3D = Transform3D(Basis.from_euler(Vector3(v.phi, 0.0, v.psi)), pv) * Transform3D(Basis.IDENTITY, -pv)
		(_corps[i][0] as Node3D).transform = Transform3D(b, p) * bal
		for cs in _corps[i][1]:
			(cs as CollisionShape3D).disabled = porte > 0.5
	_maj_portillons_tph(i, _porte_i)


## Portillons de quai (demande d'utilisateur du 07/11/2026, après la sonde des chutes) : on tombait de 5 à
## 10 m dans la baie vide de la Grande Motte, ou par l'avant du quai amont du Fornet. Barrière galvanisée à
## deux lisses le long de chaque bord de baie (Grande Motte) ou en travers de la baie au nez du quai
## (Fornet, amont) ; collision active cabine absente, ouverte (collision coupée, barrière effacée) quand la
## cabine de la voie est à moins de D_QUAI + 4 m de sa place à quai. Avant du quai amont du Fornet hors des
## baies : garde-corps fixe.
var _portillons_tph: Array = []          # [montée ?, aval ?, formes de collision, visuel, ouverture, coulissant ?]
var _porte_i: float = 0.0


func _portillons_quai() -> void:
	_portillons_tph.clear()
	var racine: Node3D = Node3D.new()
	racine.name = "Portillons"
	_enfant(racine)
	var corps: StaticBody3D = null
	if avec_collisions:
		corps = StaticBody3D.new()
		corps.name = "CollisionsPortillons"
		corps.collision_layer = CollisionsJeu.COUCHE_DECOR
		corps.collision_mask = 0
		_enfant(corps)
	var L: float = longueur_h()
	var h: float = 1.1
	for aval in [true, false]:
		var y_q: float = terrain(0.0 if aval else L)
		for montee in [true, false]:
			var xv: float = _x_brin(montee)
			var segs: Array = []            # [a, b] dans le repère de la ligne, au niveau du quai
			if gare_aval_existante:
				# Grande Motte : portillon coulissant devant la porte de la cabine à quai (côté +x de la caisse) ;
				# les barrières fixes le long des baies sont du plan du quai (TphGrandeMotte.plan_quai)
				var z_g: float = TphGrandeMotte.Z_NEZ if aval else -L
				var z_c: float = ((-TphGrandeMotte.Z_NEZ + D_QUAI) if aval else -D_QUAI) + z_g
				var xg: float = xv + TphGrandeMotte.DEMI_BAIE + TphGrandeMotte.RETRAIT_BARRIERE + 0.08   # (côté quai de la barrière fixe)
				segs.append([Vector3(xg, y_q, z_c - TphGrandeMotte.DEMI_PORTE), Vector3(xg, y_q, z_c + TphGrandeMotte.DEMI_PORTE)])
			elif String(name) == "tph_fornet":
				# Fornet : portillon coulissant devant la porte, comme à la Grande Motte
				var z_cf: float = (D_QUAI) if aval else (-L - D_QUAI)
				var xgf: float = xv + TphGrandeMotte.DEMI_BAIE + TphGrandeMotte.RETRAIT_BARRIERE + 0.08
				segs.append([Vector3(xgf, y_q, z_cf - TphGrandeMotte.DEMI_PORTE), Vector3(xgf, y_q, z_cf + TphGrandeMotte.DEMI_PORTE)])
			if segs.is_empty():
				continue
			var vis: Node3D = Node3D.new()
			racine.add_child(vis)
			var formes: Array = []
			for sg in segs:
				var a: Vector3 = sg[0]
				var b: Vector3 = sg[1]
				for yy in [0.55, h]:
					RemonteeKit.barre(vis, a + Vector3(0, yy, 0), b + Vector3(0, yy, 0), 0.025, "galva", 6)
				var n: int = maxi(1, int(a.distance_to(b) / 2.5))
				for k in range(n + 1):
					var q: Vector3 = a.lerp(b, float(k) / n)
					RemonteeKit.barre(vis, q, q + Vector3(0, h, 0), 0.03, "galva", 6)
				if corps != null:
					var cs: CollisionShape3D = CollisionShape3D.new()
					var bx: BoxShape3D = BoxShape3D.new()
					var lg2: float = a.distance_to(b)
					bx.size = Vector3(0.12, h + 0.6, lg2) if absf(b.z - a.z) > absf(b.x - a.x) else Vector3(lg2, h + 0.6, 0.12)
					cs.shape = bx
					cs.position = (a + b) * 0.5 + Vector3(0, (h + 0.6) * 0.5, 0)
					corps.add_child(cs)
					formes.append(cs)
			_portillons_tph.append([montee, aval, formes, vis, -1.0, gare_aval_existante or String(name) == "tph_fornet"])


## Portillons de la voie de la cabine i. Grande Motte : ils coulissent avec les portes de la cabine (`porte`,
## 0 fermées → 1 ouvertes ; retour d'utilisateur du 11/11/2026 : « en face des portes des cabines, des barrières
## coulissantes qui se ferment et s'ouvrent avec les portes ») ; ailleurs, ouverts quand la cabine est à quai.
func _maj_portillons_tph(i: int, porte: float = 0.0) -> void:
	var montee: bool = i == 0
	var d: float = _vehicules[i][1]
	var zn: String = zone_vehicule(i)
	for p in _portillons_tph:
		if bool(p[0]) != montee or not is_instance_valid(p[3]):
			continue
		var t: float
		if bool(p[5]):
			var ici: bool = (zn == "gare_aval") == bool(p[1]) and zn != "ligne"
			t = porte if ici else 0.0
		else:
			t = 1.0 if absf(d - _x_quai(bool(p[1]))) < D_QUAI + 4.0 else 0.0
		if absf(t - float(p[4])) < 0.002:
			continue
		p[4] = t
		if bool(p[5]):
			# le vantail glisse le long de la barrière fixe, vers l'avant du quai
			(p[3] as Node3D).position = Vector3(0, 0, -(2.0 * TphGrandeMotte.DEMI_PORTE - 0.1) * t * (1.0 if bool(p[1]) else -1.0))
		else:
			(p[3] as Node3D).visible = t < 0.5
		for cs in p[2]:
			(cs as CollisionShape3D).disabled = t > 0.5


## Fornet : câble tracteur inférieur (lest, 29 mm, fiche RM.net), du bout aval du chariot de chaque cabine à la
## poulie de tension de la gare aval ; peu tendu, il pend sous la ligne. Un tube léger par voie, refait quand
## la cabine a avancé de plus de 4 m (2 à 3 fois par seconde à pleine vitesse).
var _lest: Array = []                # [MeshInstance3D, montée ?, d au dernier tracé]
const R_LEST: float = 0.0145


func _poser_lest() -> void:
	_lest.clear()
	if String(name) != "tph_fornet":
		return
	for montee in [true, false]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Lest"
		mi.mesh = ArrayMesh.new()
		mi.material_override = RemonteeKit.mat("cable")
		mi.set_meta(MeshMerge.SANS_FUSION, true)
		mi.set_meta("sans_collision", true)
		_enfant(mi)
		_lest.append([mi, montee, INF])


func _maj_lest() -> void:
	for e in _lest:
		var mi: MeshInstance3D = e[0]
		if not is_instance_valid(mi):
			continue
		var montee: bool = e[1]
		var d: float = _vehicules[0 if montee else 1][1]
		if absf(d - float(e[2])) < 4.0:
			continue
		e[2] = d
		var m: ArrayMesh = mi.mesh
		m.clear_surfaces()
		var da: float = -D_QUAI - 4.0                 # poulie de tension, au fond de la gare aval
		var db: float = d - 2.6                       # bout aval du chariot
		if db - da < 2.0:
			continue
		var x: float = _x_brin(montee)
		var y_gare: float = terrain(0.0) + H_CABLE_GARE - 1.3
		var pts: PackedVector3Array = PackedVector3Array()
		var n: int = clampi(int((db - da) / 8.0), 4, 60)
		var span: float = db - da
		for k in range(n + 1):
			var u: float = float(k) / n
			var dd: float = lerpf(da, db, u)
			var y0: float = y_gare if dd <= 0.0 else _y_chariot(dd, montee) - 1.25
			# flèche : 2 % de la portée au milieu, sans descendre à moins de 1,5 m du sol
			var y: float = y0 - 0.02 * span * 4.0 * u * (1.0 - u)
			y = maxf(y, _sol(x, -dd) + 1.5)
			pts.append(Vector3(x, y, -dd))
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _tube_lest(pts))


## Tube à 6 pans le long de pts (tableaux d'une surface).
static func _tube_lest(pts: PackedVector3Array) -> Array:
	var v: PackedVector3Array = PackedVector3Array()
	var nv: PackedVector3Array = PackedVector3Array()
	var ix: PackedInt32Array = PackedInt32Array()
	var seg: int = 6
	for k in range(pts.size()):
		var t: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var a: Vector3 = t.cross(Vector3.UP).normalized()
		if a.length_squared() < 0.5:
			a = Vector3.RIGHT
		var b: Vector3 = t.cross(a).normalized()
		for s in range(seg):
			var th: float = TAU * s / seg
			var n3: Vector3 = a * cos(th) + b * sin(th)
			v.append(pts[k] + n3 * R_LEST)
			nv.append(n3)
	for k2 in range(pts.size() - 1):
		for s2 in range(seg):
			var i0: int = k2 * seg + s2
			var i1: int = k2 * seg + (s2 + 1) % seg
			ix.append_array([i0, i0 + seg, i1, i1, i0 + seg, i1 + seg])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nv
	arr[Mesh.ARRAY_INDEX] = ix
	return arr


## Charges : une cabine par voie (60 % de passagers).
func _charges_ponctuelles() -> void:
	if _mat_cable == null or _n_appuis < 2:
		return
	var listes: Array = [[], []]
	for i in range(2):
		var d: float = _vehicules[i][1]
		if d > 0.0 and d < longueur_h():
			listes[i].append(Vector2(d, poids_cabine() / _tension))
	_charges = listes
	# même flèche pour le chariot (_fleche) que pour le câble dessiné (nuanceur) : les cabines flottaient
	# jusqu'à 24 m au-dessus des porteurs à mi-portée (retour d'utilisateur, 11/11/2026)
	_charges_portee = [{}, {}]
	for k3 in range(2):
		for c in listes[k3]:
			var ip: int = _portee_de((c as Vector2).x)
			if ip < 0:
				continue
			if not _charges_portee[k3].has(ip):
				_charges_portee[k3][ip] = []
			_charges_portee[k3][ip].append(c)
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


## Câbles (fiches RM.net) : DEUX porteurs lisses par voie (ancrés en gare ; Fornet 44 mm), le tracteur à
## torons 0,45 m sous eux, entre les deux, et des cavaliers qui le portent (Fornet 4 par voie, Grande
## Motte 8).
func _cables_tph() -> void:
	var c: Node3D = Node3D.new()
	c.name = "Cable"
	_enfant(c)
	var fornet: bool = String(name) == "tph_fornet"
	_mat_cable = RemonteeKit.materiau_cable_tracteur(30.0 if fornet else 40.0)
	_mat_porteurs = RemonteeKit.materiau_cable_tracteur(44.0 if fornet else 50.0)
	_mat_porteurs.set_shader_parameter("lisse", true)
	var r_por: float = 0.022 if fornet else 0.025
	var e2: float = VehiculeRemontee.E_PORTEURS_TPH * 0.5
	var n_cav: int = 4 if fornet else 8
	var L: float = longueur_h()
	for montee in [true, false]:
		var x0: float = _x_brin(montee)
		var por: PackedVector3Array = PackedVector3Array()
		var tra: PackedVector3Array = PackedVector3Array()
		var d: float = -D_QUAI - 6.0
		while d <= L + D_QUAI + 6.0:
			var dd: float = clampf(d, 0.0, L)
			var y: float = y_cable(dd, montee) if d > 0.0 and d < L else terrain(0.0 if d <= 0.0 else L) + H_CABLE_GARE
			por.append(Vector3(0, y, -d))
			tra.append(Vector3(x0, y - 0.45, -d))
			d += 1.0 if d < 30.0 or d > L - 30.0 else 5.0
		for sx in [-1.0, 1.0]:
			var p2: PackedVector3Array = PackedVector3Array()
			for q in por:
				p2.append(Vector3(x0 + sx * e2, q.y, q.z))
			RemonteeKit.tube(c, p2, r_por, "cable", 8, _mat_porteurs)
		RemonteeKit.tube(c, tra, 0.015 if fornet else 0.020, "cable", 8, _mat_cable)
		# (une tranche pour les câbles d'un brin, une pour ses cavaliers : 11 ms d'un bloc, relevé du 07/11/2026)
		await _pause("téléphérique : câbles")
		# cavaliers
		for k in range(n_cav):
			var dc: float = L * (k + 0.5) / float(n_cav)
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
			# cavalier (photos des reportages) : sabot serré sur chaque porteur, traverse entre eux, deux bras
			# en V qui descendent au milieu, galet du tracteur à la pointe
			for sx2 in [-1.0, 1.0]:
				RemonteeKit.boite_en(cv, Vector3(0.16, 0.16, 0.55), Vector3(sx2 * e2, 0.02, 0), "galva_pylone")
			RemonteeKit.boite_en(cv, Vector3(2.0 * e2, 0.10, 0.12), Vector3(0, -0.02, 0), "galva_pylone")
			for sz in [-1.0, 1.0]:
				RemonteeKit.poutre(cv, Vector3(0.0, -0.05, sz * 0.22), Vector3(0.0, -0.62, 0.0), 0.05, 0.08, "galva_pylone")
			RemonteeKit.cylindre(cv, 0.035, 0.035, 0.22, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.60, 0)), "acier_noir", 8)
			RemonteeKit.galet(cv, Vector3(0, -0.45 - 0.02 - 0.12, 0), 0.12)
		await _pause("téléphérique : câbles")
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
	_enfant(g)
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
		lab.text = nom_ligne.to_upper()        # (gare générique : celle du Fornet portait le nom de la Grande Motte)
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


## Gares du Fornet (reportage RM.net, photos de 2017 ; cotes estimées d'après la voie de 8 m).
## Aval (1944 m, motrice et tensions) : quai à l'étage, au-dessus d'un rez-de-chaussée vitré à poteaux
## blancs sur socle de pierre (bar-restaurant) ; par voie, un portique de deux grands piliers gris reliés
## en tête, plate-forme et garde-corps au sommet ; une charpente noire inclinée ramène les porteurs vers
## les contrepoids ; grands tubes cintrés de part et d'autre ; balcons latéraux ; derrière, le bâtiment
## bardé anthracite de la machinerie, enseigne blanche côté route.
## Amont (2327 m, sur un éperon rocheux) : quai en porte-à-faux sur une structure de béton, tour de béton
## clair au fond, bâtiment bas bardé à côté (accolé à la gare du Vallon).
func _gare_fornet(aval: bool) -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAval" if aval else "GareAmont"
	var L: float = longueur_h()
	var y0: float = terrain(0.0 if aval else L)
	g.position = Vector3(0, y0, 0)
	_enfant(g)
	var sg: float = 1.0 if aval else -1.0               # vers le fond de la gare
	var z0: float = 0.0 if aval else -L
	var hx: float = voie * 0.5 + 3.0
	var lq: float = 2.0 * D_QUAI + 2.0
	var zq: float = z0 + sg * lq * 0.5
	var sol := func(x: float, z: float) -> float:
		return _sol(x, z) - y0
	# sol le plus bas sous l'emprise du quai (rez-de-chaussée ou voiles jusque-là)
	var bas: float = 0.0
	for xi in [-hx, 0.0, hx]:
		for k in range(5):
			bas = minf(bas, float(sol.call(float(xi), z0 + sg * lq * float(k) / 4.0)))
	bas = maxf(bas, -30.0) - 0.5
	var PQ: Dictionary = _plan_quai_fornet(aval)
	for r in PQ["dalles"]:
		var rc: Rect2 = r
		RemonteeKit.boite_en(g, Vector3(rc.size.x, 0.5, rc.size.y), Vector3(rc.get_center().x, -0.25, rc.get_center().y), "beton")
	for e in PQ["garde_corps"]:
		_dessin_gc(g, e[0], e[1], 1.1, "peinture_gris")
	for e2 in PQ["barrieres"]:
		_dessin_gc(g, e2[0], e2[1], 1.2, "galva")
	if aval:
		# rez-de-chaussée : socle de pierre, poteaux blancs, vitrages, bandeau de bois sous le quai
		var h_rdc: float = maxf(-bas - 0.5, 3.2)
		var y_rdc: float = -0.5 - h_rdc
		RemonteeKit.boite_en(g, Vector3(2.0 * hx, 1.2, lq), Vector3(0, y_rdc + 0.6, zq), "pierre")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx - 0.6, h_rdc - 1.2, lq - 0.6), Vector3(0, y_rdc + 1.2 + (h_rdc - 1.2) * 0.5, zq), "vitrage_sombre")
		for xp in [-hx + 0.3, -hx * 0.33, hx * 0.33, hx - 0.3]:
			RemonteeKit.boite_en(g, Vector3(0.6, h_rdc, 0.6), Vector3(xp, y_rdc + h_rdc * 0.5, z0 + 0.3), "blanc_plaque")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 0.4, 0.35, lq + 0.4), Vector3(0, -0.68, zq), "bois_fonce")
		# sabots des porteurs sur poteaux noirs à consoles grises (photos de la gare actuelle)
		_sabots_fornet(g, true, y0, "peinture_gris", "peinture_anthracite")
		# (balcons latéraux et garde-corps : plan du quai)
		# bâtiment de la machinerie, bardé anthracite, derrière le quai
		var lb: float = 20.0
		var zb: float = z0 + lq + lb * 0.5
		var hb: float = 11.0
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 6.0, hb - bas, lb), Vector3(0, bas + (hb - bas) * 0.5, zb), "peinture_anthracite")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 6.2, 1.2, lb + 0.2), Vector3(0, bas + 0.6, zb), "pierre")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx + 6.4, 0.3, lb + 0.4), Vector3(0, hb + 0.15, zb), "noir_mat")
		_facade_fornet(g, z0 + lq + lb, 2.0 * hx + 6.0, hb, float(sol.call(0.0, z0 + lq + lb + 3.0)))
	else:
		# quai en porte-à-faux : voiles de béton jusqu'au rocher, sous le fond du quai seulement
		for sx4 in [-1.0, 1.0]:
			var xv: float = sx4 * (hx - 0.4)
			var zf: float = z0 + sg * (lq - 2.0)
			var yb: float = float(sol.call(xv, zf)) - 0.5
			RemonteeKit.boite_en(g, Vector3(0.6, maxf(-yb, 0.5), 5.0), Vector3(xv, yb * 0.5 - 0.5, zf), "beton")
			RemonteeKit.poutre(g, Vector3(xv, -0.6, z0 + sg * 1.0), Vector3(xv, yb * 0.6, zf - sg * 2.5), 0.5, 0.7, "beton")
		RemonteeKit.boite_en(g, Vector3(2.0 * hx, 1.2, lq), Vector3(0, -1.1, zq), "beton")
		# sabots des porteurs : poutres-caissons gris-bleu cintrées en porte-à-faux au-delà du quai (photos)
		_sabots_fornet(g, false, y0, "bleu_ardoise", "bleu_ardoise")
		# tour de béton clair au fond, bâtiment bas bardé à côté
		var zt: float = z0 + sg * (lq + 4.0)
		var yt: float = minf(float(sol.call(0.0, zt)), 0.0) - 0.5
		RemonteeKit.boite_en(g, Vector3(9.0, 15.0 - yt, 8.0), Vector3(-2.0, yt + (15.0 - yt) * 0.5, zt), "crepi")
		RemonteeKit.boite_en(g, Vector3(9.2, 0.4, 8.2), Vector3(-2.0, 15.2, zt), "noir_mat")
		RemonteeKit.boite_en(g, Vector3(6.0, 1.6, 0.1), Vector3(-2.0, 11.0, zt - sg * 4.02), "vitrage_sombre")
		# bâtiment accolé (photos) : bardage de bois gris sur trois niveaux, fenêtres carrées à cadre clair,
		# toit plat à garde-corps rouges ; bande vitrée verticale sur la tour
		var hn: float = 10.0
		RemonteeKit.boite_en(g, Vector3(14.0, hn - yt, 10.0), Vector3(10.0, yt + (hn - yt) * 0.5, zt + sg * 1.0), "bois_grise")
		RemonteeKit.boite_en(g, Vector3(14.4, 0.3, 10.4), Vector3(10.0, hn + 0.15, zt + sg * 1.0), "noir_mat")
		var zfa: float = zt + sg * 1.0 - sg * 5.03
		for niv in range(3):
			var yn: float = 1.6 + niv * 3.0
			if yn < yt + 0.8:
				continue
			for kf in range(5):
				var xf2: float = 4.6 + kf * 2.7
				RemonteeKit.boite_en(g, Vector3(1.25, 1.35, 0.06), Vector3(xf2, yn, zfa), "blanc_plaque")
				RemonteeKit.boite_en(g, Vector3(1.0, 1.1, 0.08), Vector3(xf2, yn, zfa - sg * 0.01), "vitrage_sombre")
		for kr in range(8):
			var xr: float = 3.2 + kr * 1.95
			RemonteeKit.barre(g, Vector3(xr, hn + 0.3, zfa), Vector3(xr, hn + 1.3, zfa), 0.03, "cabine_rouge", 6)
		RemonteeKit.barre(g, Vector3(3.2, hn + 1.3, zfa), Vector3(16.8, hn + 1.3, zfa), 0.035, "cabine_rouge", 6)
		RemonteeKit.boite_en(g, Vector3(1.4, 12.0, 0.1), Vector3(-4.6, 7.0, zt - sg * 4.03), "vitrage_sombre")
		RemonteeKit.boite_en(g, Vector3(2.6, 0.9, 0.1), Vector3(-0.2, 13.2, zt - sg * 4.05), "noir_mat")
	MeshMerge.merge(g, [], "Gare")


## Plan du quai du Fornet, repère de la ligne (même règle que TphGrandeMotte.plan_quai ; retours d'utilisateur
## du 11/11/2026 sur les quais : trous, barrières des baies, portillons coulissants, pas de jour quai / cabine).
## u : distance au nez, vers le fond de la gare ; baies ajustées à la caisse depuis le nez jusque derrière la
## cabine à quai ; aval : balcons latéraux sur les 60 % avant ; le fond du quai reste ouvert (accès).
func _plan_quai_fornet(aval: bool) -> Dictionary:
	var L: float = longueur_h()
	var sg: float = 1.0 if aval else -1.0
	var z0: float = 0.0 if aval else -L
	var x0: float = absf(_x_brin(true))
	var W: float = voie * 0.5 + 3.0
	var lq: float = 2.0 * D_QUAI + 2.0
	var db: float = TphGrandeMotte.DEMI_BAIE
	var bi: float = x0 - db
	var be: float = x0 + db
	var u_ar: float = D_QUAI + TphGrandeMotte.DEMI_CAISSE_LONG + 0.05
	var R := func(xa: float, xb: float, ua: float, ub: float) -> Rect2:
		var za: float = z0 + sg * ua
		var zb: float = z0 + sg * ub
		return Rect2(minf(xa, xb), minf(za, zb), absf(xb - xa), absf(zb - za))
	var V := func(x: float, u: float) -> Vector2:
		return Vector2(x, z0 + sg * u)
	var dalles: Array = [R.call(-W, W, u_ar, lq), R.call(-bi, bi, 0.0, u_ar)]
	var gc: Array = [[V.call(-bi, 0.0), V.call(bi, 0.0)]]
	var lbal: float = lq * 0.6
	for sx in [-1.0, 1.0]:
		dalles.append(R.call(sx * be, sx * W, 0.0, u_ar))
		if aval:
			dalles.append(R.call(sx * W, sx * (W + 2.4), 0.0, lbal))
			gc.append([V.call(sx * be, 0.0), V.call(sx * (W + 2.4), 0.0)])
			gc.append([V.call(sx * (W + 2.4), 0.0), V.call(sx * (W + 2.4), lbal)])
			gc.append([V.call(sx * W, lbal), V.call(sx * (W + 2.4), lbal)])
			gc.append([V.call(sx * W, lbal), V.call(sx * W, lq)])
		else:
			gc.append([V.call(sx * be, 0.0), V.call(sx * W, 0.0)])
			gc.append([V.call(sx * W, 0.0), V.call(sx * W, lq)])
	var bar: Array = []
	var port: Array = []
	var dp: float = TphGrandeMotte.DEMI_PORTE
	for montee in [true, false]:
		var xv: float = _x_brin(montee)
		for sb in [-1.0, 1.0]:
			var xb: float = xv + sb * (db + TphGrandeMotte.RETRAIT_BARRIERE)
			if sb > 0.0:
				bar.append([V.call(xb, 0.0), V.call(xb, D_QUAI - dp)])
				bar.append([V.call(xb, D_QUAI + dp), V.call(xb, u_ar)])
				port.append([xb, z0 + sg * D_QUAI])
			else:
				bar.append([V.call(xb, 0.0), V.call(xb, u_ar)])
		var ur: float = u_ar + TphGrandeMotte.RETRAIT_BARRIERE
		bar.append([V.call(xv - db - TphGrandeMotte.RETRAIT_BARRIERE, ur), V.call(xv + db + TphGrandeMotte.RETRAIT_BARRIERE, ur)])
	return {"dalles": dalles, "garde_corps": gc, "barrieres": bar, "portillons": port, "W": W, "lq": lq}


## Garde-corps d'un plan de quai (dessin) : deux lisses et des potelets, ou trois lisses (barrières de baie).
func _dessin_gc(g: Node3D, a: Vector2, b: Vector2, h: float, m: String) -> void:
	var pa: Vector3 = Vector3(a.x, 0, a.y)
	var pb: Vector3 = Vector3(b.x, 0, b.y)
	for yy in [h * 0.5, h]:
		RemonteeKit.barre(g, pa + Vector3(0, yy, 0), pb + Vector3(0, yy, 0), 0.03, m, 6)
	var n: int = maxi(1, int(pa.distance_to(pb) / 1.2))
	for k in range(n + 1):
		var q: Vector3 = pa.lerp(pb, float(k) / n)
		RemonteeKit.barre(g, q, q + Vector3(0, h, 0), 0.025, m, 6)


## Sabots de gare du Fornet (photos Commons ; retour d'utilisateur du 11/11/2026 : « design des supports de
## câble en gare pas bon ») : sous CHAQUE porteur, une poutre-caisson garnie d'un sabot orange où il repose ;
## plate dans la gare, elle se cintre au nez et suit les porteurs jusqu'au bout de l'arc (R_SABOT_GARE),
## en porte-à-faux au-dessus du vide. Les deux poutres d'une voie restent séparées par le vide où passe la
## tête de la suspente : chacune est tenue par l'extérieur, par des consoles sur deux poteaux, au nez et au
## fond du quai, que relie une traverse haute au-dessus du chariot.
func _sabots_fornet(g: Node3D, aval: bool, y0: float, m_poutre: String, m_poteau: String) -> void:
	_sabots_tph(g, aval, y0, 0.0, 2.0 * D_QUAI + 2.0, m_poutre, m_poteau, true)


## Sabots des porteurs en gare (retours d'utilisateur du 11/11/2026 : « design des supports de câble en gare
## pas bon » ; « le support se fixe au droit du chariot […] sinon ça ne passe pas le pylône ») : sous chaque
## porteur une garniture (le porteur y repose) qui suit le câble du fond du quai au bout du sabot cintré, sur
## un caisson unique sous la paire de porteurs ; le côté EXTÉRIEUR reste libre pour le bras de suspente, le
## caisson est tenu par des consoles du côté intérieur, sur des poteaux reliés en tête au-dessus du chariot (au
## fond du quai, au nez, et au bout du sabot quand il s'avance hors de la gare). `z_g` : z de g dans le repère
## de la ligne ; `lq` : du nez au fond des rails ; `galet` : poulie de renvoi du tracteur au fond du quai.
func _sabots_tph(g: Node3D, aval: bool, y0: float, z_g: float, lq: float, m_poutre: String, m_poteau: String,
		galet: bool) -> void:
	var L: float = longueur_h()
	var e2: float = VehiculeRemontee.E_PORTEURS_TPH * 0.5
	var hn: float = float(_h_nez[0 if aval else 1])
	var t_bout: float = 2.0 * hn + 0.3
	var h_p: float = 0.75                                   # hauteur du caisson
	var y_rail := func(t: float, montee: bool) -> float:
		var d: float = t if aval else L - t
		return (y_cable(clampf(d, 0.0, L), montee) if t > 0.0 else terrain(0.0 if aval else L) + H_CABLE_GARE) - y0
	var z_loc := func(t: float) -> float:
		return -(t if aval else L - t) - z_g
	for montee in [true, false]:
		var x0: float = _x_brin(montee)
		var dedans: float = -signf(x0)                          # côté intérieur de la ligne
		var pts: Array = []
		for k in range(25):
			var t: float = lerpf(-lq, t_bout, float(k) / 24.0)
			pts.append(Vector3(x0, float(y_rail.call(t, montee)), float(z_loc.call(t))))
		for i in range(pts.size() - 1):
			var pa: Vector3 = pts[i]
			var pb: Vector3 = pts[i + 1]
			for side in [-1.0, 1.0]:
				var o: Vector3 = Vector3(side * e2, -0.10, 0)
				RemonteeKit.poutre(g, pa + o, pb + o, 0.13, 0.10, "orange_sabot")
			var oc: Vector3 = Vector3(0, -0.15 - h_p * 0.5, 0)
			RemonteeKit.poutre(g, pa + oc, pb + oc, 2.0 * e2 + 0.24, h_p, m_poutre)
		# portiques : fond du quai, nez, bout du sabot s'il s'avance de plus de 4 m
		var ts: Array = [-(lq - 0.6), -0.6]
		if t_bout > 4.0:
			ts.append(t_bout - 0.4)
		for t2 in ts:
			var z: float = float(z_loc.call(t2))
			var yr: float = float(y_rail.call(t2, montee))
			var y_t: float = yr + 1.9                              # traverse haute, au-dessus du chariot
			for side2 in [-1.0, 1.0]:
				var xp: float = x0 + side2 * 2.15
				var yb: float = minf(0.0, _sol(xp, z + z_g) - y0) if t2 > 0.0 else 0.0
				RemonteeKit.boite_en(g, Vector3(0.55, y_t + 0.3 - yb, 0.55), Vector3(xp, (y_t + 0.3 + yb) * 0.5, z), m_poteau)
				if yb < -0.5:
					RemonteeKit.boite_en(g, Vector3(1.1, 0.5, 1.1), Vector3(xp, yb - 0.1, z), "beton")
			# console : du poteau intérieur au caisson
			var xpi: float = x0 + dedans * 2.15
			var xci: float = x0 + dedans * (e2 + 0.12)
			RemonteeKit.boite_en(g, Vector3(absf(xpi - xci), 0.45, 0.40), Vector3((xpi + xci) * 0.5, yr - 0.15 - h_p * 0.5, z), m_poutre)
			RemonteeKit.boite_en(g, Vector3(4.85, 0.50, 0.50), Vector3(x0, y_t, z), m_poutre)
		# poulie de renvoi du tracteur au fond du quai, derrière le chariot à quai
		if galet:
			RemonteeKit.galet(g, Vector3(x0, H_CABLE_GARE - 0.45 - 0.25, float(z_loc.call(-(lq + 0.5)))), 0.25)


## Façade côté route de la gare aval du Fornet (photos de la gare actuelle, Wikimedia Commons) :
## bardage de planches noires, socle de pierre, grand vitrage derrière un treillis de mélèze en
## branches d'arbres, entrée en retrait à cadre de bois, enseigne blanche, pastille rouge de la
## station ; devant, barrières de rondins, lampadaire et mât.
func _facade_fornet(g: Node3D, zf: float, wf: float, hb: float, yr: float) -> void:
	var z: float = zf + 0.02
	var y0: float = yr + 1.2                       # au-dessus du socle de pierre
	var hv: float = 4.6
	var xg: float = -wf * 0.5 + 0.8
	var xd: float = wf * 0.5 - 0.8
	# planches horizontales du bardage, au-dessus du vitrage
	var yb: float = y0 + hv + 0.2
	while yb < hb - 0.2:
		RemonteeKit.boite_en(g, Vector3(wf + 0.02, 0.025, 0.04), Vector3(0, yb, z + 0.01), "noir_mat")
		yb += 0.32
	RemonteeKit.boite_en(g, Vector3(xd - xg, hv, 0.08), Vector3((xg + xd) * 0.5, y0 + hv * 0.5, z + 0.02), "vitrage_sombre")
	# entrée en retrait, cadre de bois doré
	var xe: float = wf * 0.18
	var le: float = 5.6
	var he: float = 3.2
	RemonteeKit.boite_en(g, Vector3(le, he, 0.12), Vector3(xe, yr + he * 0.5, z + 0.05), "noir_mat")
	for sxe in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.35, he + 0.35, 0.9), Vector3(xe + sxe * (le * 0.5 + 0.17), yr + (he + 0.35) * 0.5, z + 0.45), "bois_meleze")
	RemonteeKit.boite_en(g, Vector3(le + 0.7, 0.35, 0.9), Vector3(xe, yr + he + 0.17, z + 0.45), "bois_meleze")
	# treillis : meneaux de mélèze et branches (motif fixe, tiré du sinus pour rester stable)
	var n_b: int = int((xd - xg) / 1.15)
	for k in range(n_b + 1):
		var x: float = xg + k * (xd - xg) / float(n_b)
		if absf(x - xe) < le * 0.5 + 0.3:
			continue
		RemonteeKit.boite_en(g, Vector3(0.10, hv, 0.10), Vector3(x, y0 + hv * 0.5, z + 0.10), "bois_meleze")
		if k == n_b:
			continue
		var xm: float = x + (xd - xg) / float(n_b) * 0.5
		if absf(xm - xe) < le * 0.5 + 0.5:
			continue
		var r1: float = sin(k * 12.9898) * 0.5
		var tronc_h: float = y0 + 1.2 + absf(r1)
		RemonteeKit.barre(g, Vector3(xm + r1 * 0.2, y0, z + 0.12), Vector3(xm, tronc_h, z + 0.12), 0.05, "bois_fonce", 5)
		for sb in [-1.0, 1.0]:
			var bx: float = xm + sb * (0.40 + 0.1 * r1)
			RemonteeKit.barre(g, Vector3(xm, tronc_h, z + 0.12), Vector3(bx, y0 + hv - 0.3 - 0.6 * absf(r1 + sb * 0.3), z + 0.12), 0.03, "bois_fonce", 5)
			RemonteeKit.barre(g, Vector3(xm + sb * 0.18, tronc_h + 0.9, z + 0.12), Vector3(xm + sb * 0.05, y0 + hv - 0.15, z + 0.12), 0.02, "bois_fonce", 5)
	# enseigne : texte blanc, pastille blanche à gauche, plaque rouge de la station à droite
	var ye: float = minf(y0 + hv + 1.4, hb - 1.0)
	var ens: MeshInstance3D = RemonteeKit.texte_fige(g, "Téléphérique du Fornet", 120, 0.0105, Color(0.96, 0.96, 0.96))
	ens.position = Vector3(0.6, ye, z + 0.08)
	ens.visibility_range_end = 300.0
	RemonteeKit.cylindre(g, 0.55, 0.55, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-wf * 0.5 + 1.5, ye, z + 0.06)), "blanc_plaque", 20)
	RemonteeKit.boite_en(g, Vector3(1.3, 1.9, 0.08), Vector3(wf * 0.5 - 1.4, ye - 0.1, z + 0.06), "cabine_rouge")
	var vi: MeshInstance3D = RemonteeKit.texte_fige(g, "Val d'Isère", 60, 0.006, Color(0.97, 0.97, 0.97))
	vi.position = Vector3(wf * 0.5 - 1.4, ye - 0.5, z + 0.11)
	vi.visibility_range_end = 120.0
	# devant : barrières de rondins (deux rondins sur deux poteaux), lampadaire noir, mât blanc
	for kb in range(4):
		var xb: float = -wf * 0.5 + 2.5 + kb * (wf - 5.0) / 3.0
		var zb: float = z + 7.5 + 1.5 * sin(kb * 3.7)
		var yg: float = _sol(xb, zb) - g.position.y
		for yl in [0.25, 0.62]:
			RemonteeKit.cylindre(g, 0.17, 0.17, 2.6, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(xb, yg + yl, zb)), "bois_grise", 10)
		for sp in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(0.16, 0.95, 0.16), Vector3(xb + sp * 0.95, yg + 0.47, zb), "bois_fonce")
	var xl: float = wf * 0.5 + 1.5
	var yl2: float = _sol(xl, z + 2.0) - g.position.y
	RemonteeKit.barre(g, Vector3(xl, yl2, z + 2.0), Vector3(xl, yl2 + 5.0, z + 2.0), 0.07, "noir_mat", 8)
	RemonteeKit.boite_en(g, Vector3(0.40, 0.55, 0.40), Vector3(xl - 0.45, yl2 + 4.7, z + 2.0), "noir_mat")
	RemonteeKit.barre(g, Vector3(xl, yl2 + 5.0, z + 2.0), Vector3(xl - 0.45, yl2 + 5.0, z + 2.0), 0.03, "noir_mat", 6)
	var xm2: float = -wf * 0.1
	var ym: float = _sol(xm2, z + 3.0) - g.position.y
	RemonteeKit.barre(g, Vector3(xm2, ym, z + 3.0), Vector3(xm2, ym + 9.0, z + 3.0), 0.06, "blanc_plaque", 8)


## Gares de la Grande Motte (TphGrandeMotte, d'après les photos) : à l'aval,
## la tête en acier contre le bâtiment existant, le plancher de l'étage et
## l'escalier extérieur côté funiculaire ; à l'amont, la gare ouverte.
## Le profil place le quai (terrain(0), terrain(L)) à son niveau réel.
var emprise_batiment: PackedVector2Array = PackedVector2Array()   # coins (x, z) du bâtiment, repère de la ligne


func _gares_grande_motte(aval: bool) -> void:
	var L: float = longueur_h()
	var g: Node3D = Node3D.new()
	g.name = "GareAval" if aval else "GareAmont"
	var y_q: float = terrain(0.0 if aval else L)
	# repère de la gare : z = 0 à la façade du bâtiment (aval), au nez (amont)
	var z_g: float = TphGrandeMotte.Z_NEZ if aval else -L
	g.position = Vector3(0, y_q, z_g)
	_enfant(g)
	var sol := func(x: float, z: float) -> float:
		return _sol(x, z + z_g) - y_q
	if aval:
		TphGrandeMotte.tete_aval(self, g, H_CABLE_GARE, sol)
		await _pause("téléphérique : gare")
		# plancher de l'étage dans le bâtiment, au niveau du quai
		if emprise_batiment.size() == 4:
			var c: Vector2 = Vector2.ZERO
			var emp: PackedVector2Array = PackedVector2Array()
			for v0 in emprise_batiment:
				emp.append(v0 - Vector2(0.0, z_g))      # repère de la gare
			for v in emp:
				c += v
			c /= 4.0
			var poly: PackedVector2Array = PackedVector2Array()
			for v2 in emp:
				poly.append(c + (v2 - c) * 0.96)
			var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in range(idx.size()):
				var q: Vector2 = poly[idx[k]]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q.x, -0.02, q.y))
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = MeshMerge.valider(st)
			mi.material_override = RemonteeKit.mat("beton")
			g.add_child(mi)
			# (escalier d'entrée : grand escalier central de la façade, posé avec le bâtiment par GareAmont)
	else:
		TphGrandeMotte.gare_amont(self, g, H_CABLE_GARE, sol)
	_sabots_tph(g, aval, y_q, z_g, (TphGrandeMotte.Z_NEZ - 0.6) if aval else (TphGrandeMotte.L_BAIE + 1.0),
		"galva_pylone", "galva_pylone", aval)
	# (en tranches : la gare d'un bloc, fusion comprise, faisait 13,5 ms sans fil, relevé du 10/11/2026)
	await _pause("téléphérique : gare")
	await MeshMerge.merge_par_tranches(g, [], "Gare", false, _pause.bind("téléphérique : gare, fusion"))


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
	_enfant(corps)
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
		if gare_aval_existante:
			_collisions_grande_motte(corps, aval)
			continue
		if String(name) == "tph_fornet":
			var PQ: Dictionary = _plan_quai_fornet(aval)
			for r in PQ["dalles"]:
				var rc: Rect2 = r
				boite.call(Vector3(rc.size.x, 0.4, rc.size.y), Vector3(rc.get_center().x, y0 - 0.2, rc.get_center().y))
			boite.call(Vector3(2.0 * hx, 6.0, lq), Vector3(0, y0 - 0.5 - 3.0, z0 + sg * lq * 0.5))     # fond des baies
			for e in PQ["garde_corps"] + PQ["barrieres"]:
				var a2: Vector2 = e[0]
				var b2: Vector2 = e[1]
				var u2: Vector2 = b2 - a2
				if u2.length() < 0.05:
					continue
				var cs2: CollisionShape3D = CollisionShape3D.new()
				var bx2: BoxShape3D = BoxShape3D.new()
				bx2.size = Vector3(0.12, 1.3, u2.length() + 0.1)
				cs2.shape = bx2
				cs2.transform = Transform3D(Basis(Vector3.UP, atan2(u2.x, u2.y)), Vector3((a2.x + b2.x) * 0.5, y0 + 0.65, (a2.y + b2.y) * 0.5))
				corps.add_child(cs2)
			continue
		boite.call(Vector3(2.0 * hx, 6.0, lq), Vector3(0, y0 - 3.0, z0 + sg * lq * 0.5))
	for i in range(pylones.size()):
		var d: float = float(pylones[i]["d"])
		var t: float = terrain(d)
		var h: float = _tetes[i] - t - 3.0
		boite.call(Vector3(clampf(h * 0.22, 4.0, 12.0), h, clampf(h * 0.22, 4.0, 12.0) * 0.6), Vector3(0, t + h * 0.5, -d))


## Collisions des gares de la Grande Motte : quais (bandes), plancher de
## l'étage, rampes à la place des escaliers.
func _collisions_grande_motte(corps: StaticBody3D, aval: bool) -> void:
	var L: float = longueur_h()
	var y_q: float = terrain(0.0 if aval else L)
	var z_g: float = TphGrandeMotte.Z_NEZ if aval else -L
	var boite := func(taille: Vector3, centre: Vector3, b: Basis = Basis.IDENTITY) -> void:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var bx: BoxShape3D = BoxShape3D.new()
		bx.size = taille
		cs.shape = bx
		cs.transform = Transform3D(b, centre + Vector3(0, y_q, z_g))
		corps.add_child(cs)
	# quai d'après son plan (TphGrandeMotte.plan_quai, le même que le dessin) : dalles, garde-corps et
	# barrières de baie en murs de 1,3 m, rampes des escaliers avec leur garde-corps extérieur
	var P: Dictionary = TphGrandeMotte.plan_quai(aval, [_x_brin(true), _x_brin(false)] if _x_brin(true) < 0.0 else [_x_brin(false), _x_brin(true)],
		(-TphGrandeMotte.Z_NEZ + D_QUAI) if aval else -D_QUAI)
	for r in P["dalles"]:
		var rc: Rect2 = r
		boite.call(Vector3(rc.size.x, 0.4, rc.size.y), Vector3(rc.get_center().x, -0.2, rc.get_center().y))
	for e in P["garde_corps"] + P["barrieres"]:
		var a2: Vector2 = e[0]
		var b2: Vector2 = e[1]
		var u2: Vector2 = b2 - a2
		if u2.length() < 0.05:
			continue
		var m2: Vector2 = (a2 + b2) * 0.5
		boite.call(Vector3(0.12, 1.3, u2.length() + 0.1), Vector3(m2.x, 0.65, m2.y), Basis(Vector3.UP, atan2(u2.x, u2.y)))
	for es in P["escaliers"]:
		var x_e: float = es[0]
		var z_h: float = es[1]
		var sens: float = es[2]
		var z_b: float = z_h + sens * 9.0
		var y_b: float = _sol(x_e, z_b + z_g) - y_q
		var pente: float = atan2(-y_b, 9.0)
		var b_r: Basis = Basis(Vector3.RIGHT, pente * sens)     # (+z vers le bas si l'escalier descend vers +z)
		boite.call(Vector3(1.4, 0.2, sqrt(81.0 + y_b * y_b)), Vector3(x_e, y_b * 0.5 - 0.1, (z_h + z_b) * 0.5), b_r)
		var x_ext: float = x_e + signf(x_e) * 0.75
		boite.call(Vector3(0.12, 1.3, sqrt(81.0 + y_b * y_b)), Vector3(x_ext, y_b * 0.5 + 0.55, (z_h + z_b) * 0.5), b_r)
	if aval:
		if emprise_batiment.size() == 4:
			var emp: PackedVector2Array = PackedVector2Array()
			for v0 in emprise_batiment:
				emp.append(v0 - Vector2(0.0, z_g))
			var c: Vector2 = Vector2.ZERO
			for v in emp:
				c += v
			c /= 4.0
			var a: Vector2 = emp[2]
			var b2: Vector2 = emp[3]
			var m: Vector2 = (a + b2) * 0.5
			var dehors: Vector2 = (m - c).normalized()
			var long_b: float = (emp[1] - emp[2]).length()
			var larg_b: float = (emp[0] - emp[1]).length()
			var rot: Basis = Basis(Vector3.UP, atan2(dehors.x, dehors.y))
			boite.call(Vector3(larg_b + 0.2, 0.4, long_b + 0.2), Vector3(c.x, -0.2, c.y), rot)
			# murs du bâtiment : les deux côtés, et la façade de la porte hors de son ouverture (on sortait du
			# plancher par le côté et l'on tombait de 9 m)
			var mur := func(a3: Vector2, b3: Vector2) -> void:
				var u3: Vector2 = b3 - a3
				var r3: Basis = Basis(Vector3.UP, atan2(u3.x, u3.y))
				var m3: Vector2 = (a3 + b3) * 0.5
				boite.call(Vector3(0.25, 2.6, u3.length()), Vector3(m3.x, 1.3, m3.y), r3)
			mur.call(emp[1], emp[2])
			mur.call(emp[3], emp[0])
			var dir_p: Vector2 = (emp[3] - emp[2]).normalized()
			mur.call(emp[2], m - dir_p * 0.9)
			mur.call(m + dir_p * 0.9, emp[3])
			# grand escalier central de la façade d'entrée (GareAmont._telepherique) : palier de 2 m devant la
			# porte, puis 31 marches de 0,178 × 0,29 m jusqu'au sol du bâtiment
			var rot_e: Basis = Basis(Vector3.UP, atan2(dehors.x, dehors.y))
			var palier: Vector2 = m + dehors * 1.0
			boite.call(Vector3(4.2, 0.2, 2.0), Vector3(palier.x, -0.1, palier.y), rot_e)
			var h_e: float = TphGrandeMotte.H_QUAI_AVAL
			var run: float = 0.29 * ceilf(h_e / 0.178)
			var cen: Vector2 = m + dehors * (2.0 + run * 0.5)
			var pente: float = atan2(h_e, run)
			boite.call(Vector3(4.0, 0.2, sqrt(run * run + h_e * h_e)), Vector3(cen.x, -h_e * 0.5 - 0.1, cen.y), rot_e * Basis(Vector3.RIGHT, pente))



## Puissance au câble (kW) : la cabine qui monte contre celle qui descend
## (même charge : seules la pente et les pertes comptent ici).
func puissance_kw() -> float:
	var L: float = longueur_h()
	var dh: float = terrain(L) - terrain(0.0)
	var p_nom: float = (masse_vehicule() + 115.0 * 80.0) * 9.81 * dh / L * vitesse
	return 0.15 * p_nom * absf(_v) / maxf(vitesse, 0.1) / 1000.0
