class_name LigneRemontee
extends Node3D
## Ligne complète de télésiège / télécabine débrayable : gares, pylônes,
## câble en boucle et véhicules qui circulent — l'échantillon « qui marche »
## des remontées, à poser ensuite sur toutes les lignes du domaine.
##
## Repère local : origine au sol de la gare AVAL, sur l'axe de la ligne ; la
## ligne monte vers −Z ; brin montée en x = +voie/2 si le sens de montée est
## « Droite » (vu de l'aval). `profil` : terrain sous l'axe, [d horizontal
## depuis l'aval, altitude relative au sol de la gare aval].
##
## Hauteur des pylônes : aucune source ouverte ne la publie ; elle est
## calculée pour que le câble chargé (flèche parabolique entre les têtes)
## reste partout à ≥ GARDE m au-dessus du terrain — les pieds des passagers
## passent alors à ~3 m de la neige, comme sur les lignes réelles.
##
## Gare : le véhicule DÉBRAYE à l'entrée (la pince s'ouvre sur la came, il
## roule sur le rail), les pneus le freinent jusqu'à la vitesse
## d'embarquement, il contourne la poulie, puis ils le réaccélèrent et la
## pince se referme sur le câble à la sortie. Toutes les pièces sont animées
## d'après la position du véhicule sur la boucle.

var profil: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1500, 560)])
var pylones: Array = []          # [{d, montee:[[n,"S"],…], descente:[…]}]
var voie: float = 6.1
var vitesse: float = 5.25
var v_embarquement: float = 1.0
var famille: String = "siege_doppelmayr_e98_6"
var espacement: float = 47.25
var sens_droite: bool = true
var nom_ligne: String = ""

var H_CABLE_GARE: float = 3.9        # câble au-dessus du quai (selon le véhicule)
const GARDE: float = 6.5              # câble ≥ terrain + GARDE en ligne
const L_GARE: float = 16.0            # du nez de gare à l'axe de la poulie
const L_FREIN: float = 11.0           # zone de freinage / d'accélération
## Chaînette : y = a·cosh((x − x0)/a) + c entre deux appuis, a = H / w
## (tension horizontale / poids linéique). Câble Ø 47 mm ≈ 8,6 kg/m ;
## véhicules (et passagers sur le brin montée) répartis à l'espacement.
var diametre_cable: float = 47.0      # mm
var _a_montee: float = 800.0          # paramètre de chaînette (m), brin chargé
var _a_descente: float = 1200.0       # brin à vide

var _boucle: PackedVector3Array = PackedVector3Array()   # chemin des véhicules
var _cumul: PackedFloat32Array = PackedFloat32Array()
var _zones: Array = []          # [s0, s1, "gare_aval"/"gare_amont"] sur la boucle
var _vehicules: Array = []      # [VehiculeRemontee, s]
var _tetes: Array = []          # hauteur (absolue locale) de la tête de chaque pylône
var longueur_boucle: float = 0.0


func terrain(d: float) -> float:
	if profil.size() == 0:
		return 0.0
	if d <= profil[0].x:
		return profil[0].y
	for i in range(1, profil.size()):
		if d <= profil[i].x:
			var a: Vector2 = profil[i - 1]
			var b: Vector2 = profil[i]
			return lerpf(a.y, b.y, (d - a.x) / maxf(b.x - a.x, 0.001))
	return profil[profil.size() - 1].y


func longueur_h() -> float:
	return profil[profil.size() - 1].x


func construire() -> void:
	for c in get_children():
		c.queue_free()
	_vehicules.clear()
	H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(famille)
	_calculer_tetes()
	_gare(true)
	_gare(false)
	_poser_pylones()
	_construire_boucle()
	_cable()
	_peupler()
	if not (famille.begins_with("cabine") or famille.begins_with("perche")):
		_portillons(true)
		_portillons(false)
	if avec_collisions:
		_collisions_fixes()
		for i in range(_vehicules.size()):
			_corps_vehicule(i)


# --- géométrie du câble ---------------------------------------------------------

func _points_appui() -> Array:
	# [d, y] des points d'appui du câble : gare aval, têtes, gare amont
	var pts: Array = [[0.0, terrain(0.0) + H_CABLE_GARE]]
	for i in range(pylones.size()):
		pts.append([float(pylones[i]["d"]), _tetes[i]])
	var L: float = longueur_h()
	pts.append([L, terrain(L) + H_CABLE_GARE])
	return pts


## Paramètres de chaînette des deux brins. Tension horizontale ~300 kN pour
## un câble de 47 mm, à l'échelle de la section ; poids : câble + véhicules
## (+ 80 kg par place sur le brin montée), répartis à l'espacement.
func _parametres_chainette() -> void:
	var g: float = 9.81
	var w_cable: float = 0.0039 * diametre_cable * diametre_cable * g      # N/m
	var cab: bool = famille.begins_with("cabine")
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	var m_v: float = (850.0 if cab else 95.0 * places + 80.0)              # kg à vide, pince comprise
	var e: float = maxf(espacement, 8.0)
	var w_desc: float = w_cable + m_v * g / e
	var w_mont: float = w_desc + 80.0 * places * g / e
	var H: float = 300000.0 * pow(diametre_cable / 47.0, 2.0)
	_a_montee = H / w_mont
	_a_descente = H / w_desc


## Hauteur de la chaînette de paramètre a passant par (x1, y1) et (x2, y2), en x.
static func chainette(x: float, x1: float, y1: float, x2: float, y2: float, a: float) -> float:
	var L: float = maxf(x2 - x1, 0.01)
	var sh: float = sinh(L / (2.0 * a))
	var xm: float = (x1 + x2) * 0.5 - a * asinh((y2 - y1) / (2.0 * a * maxf(sh, 1e-9)))
	var c: float = y1 - a * cosh((x1 - xm) / a)
	return a * cosh((x - xm) / a) + c


func _calculer_tetes() -> void:
	_parametres_chainette()
	_tetes.clear()
	for p in pylones:
		_tetes.append(terrain(float(p["d"])) + 9.0)
	for it in range(80):
		var pts: Array = _points_appui()
		var change: bool = false
		for i in range(pts.size() - 1):
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			var pire: float = 0.0
			for k in range(1, 20):
				var u: float = float(k) / 20.0
				var d: float = lerpf(a[0], b[0], u)
				# brin montée (chargé) : la flèche la plus forte
				var yc: float = chainette(d, a[0], a[1], b[0], b[1], _a_montee)
				pire = maxf(pire, terrain(d) + GARDE - yc)
			if pire > 0.05:
				# on relève la ou les têtes de la portée (pas les gares)
				if i > 0:
					_tetes[i - 1] += pire * (0.6 if i < pts.size() - 2 else 1.0)
				if i < pts.size() - 2:
					_tetes[i] += pire * (0.6 if i > 0 else 1.0)
				change = true
		if not change:
			break
	for i in range(_tetes.size()):
		var t: float = terrain(float(pylones[i]["d"]))
		_tetes[i] = clampf(_tetes[i], t + 6.5, t + 32.0)


## Hauteur du câble (chaînette) à la distance d, brin montée ou descente.
func y_cable(d: float, montee: bool = true) -> float:
	var pts: Array = _points_appui()
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if d <= b[0] or i == pts.size() - 2:
			return chainette(clampf(d, a[0], b[0]), a[0], a[1], b[0], b[1], _a_montee if montee else _a_descente)
	return 0.0


func _x_brin(montee: bool) -> float:
	return (1.0 if montee == sens_droite else -1.0) * voie * 0.5


# --- boucle des véhicules ----------------------------------------------------------

func _construire_boucle() -> void:
	_boucle = PackedVector3Array()
	_zones.clear()
	var L: float = longueur_h()
	var xm: float = _x_brin(true)
	var xd: float = _x_brin(false)
	var ya: float = terrain(0.0) + H_CABLE_GARE
	var yb: float = terrain(L) + H_CABLE_GARE
	var R: float = voie * 0.5
	# 1. gare aval : du nez de gare (brin descente) autour de la poulie au nez (brin montée)
	var s0: float = 0.0
	_ajouter(Vector3(xd, ya, 0.0))
	_ajouter(Vector3(xd, ya, L_GARE))
	for k in range(1, 24):
		var a: float = PI * float(k) / 24.0
		# demi-tour par l'arrière de la gare (+Z), de xd vers xm
		_ajouter(Vector3(-cos(a) * R * signf(xm), ya, L_GARE + sin(a) * R))
	_ajouter(Vector3(xm, ya, L_GARE))
	_ajouter(Vector3(xm, ya, 0.0))
	_zones.append([s0, _longueur(), "gare_aval"])
	# 2. brin montée
	var d: float = 3.0
	while d < L:
		_ajouter(Vector3(xm, y_cable(d), -d))
		d += 3.0
	_ajouter(Vector3(xm, yb, -L))
	# 3. gare amont
	var s1: float = _longueur()
	_ajouter(Vector3(xm, yb, -L - L_GARE))
	for k in range(1, 24):
		var a2: float = PI * float(k) / 24.0
		_ajouter(Vector3(cos(a2) * R * signf(xm), yb, -L - L_GARE - sin(a2) * R))
	_ajouter(Vector3(xd, yb, -L - L_GARE))
	_ajouter(Vector3(xd, yb, -L))
	_zones.append([s1, _longueur(), "gare_amont"])
	# 4. brin descente, jusqu'au nez de la gare aval (le point de départ)
	d = L - 3.0
	while d > 0.0:
		_ajouter(Vector3(xd, y_cable(d, false), -d))
		d -= 3.0
	longueur_boucle = _longueur() + Vector3(xd, y_cable(1.5, false), -1.5).distance_to(Vector3(xd, ya, 0.0))


func _ajouter(p: Vector3) -> void:
	if _boucle.size() > 0:
		_cumul.append(_cumul[_cumul.size() - 1] + _boucle[_boucle.size() - 1].distance_to(p))
	else:
		_cumul = PackedFloat32Array([0.0])
	_boucle.append(p)


func _longueur() -> float:
	return _cumul[_cumul.size() - 1] if _cumul.size() > 0 else 0.0


## Point et direction (horizontale) de la boucle à l'abscisse s, pour un
## véhicule : le câble lui-même ne plonge pas (voir `_plongee`).
func point(s: float) -> Array:
	var r: Array = _point_cable(s)
	var dy: float = _plongee(s)
	if dy != 0.0:
		r[0] = (r[0] as Vector3) + Vector3(0, dy, 0)
	return r


## Embarquement des télésièges, comme dans les vraies gares : on attend
## derrière les PORTILLONS, ils s'ouvrent après le passage d'un siège, on
## avance jusqu'à la LIGNE D'ARRÊT et le siège suivant arrive par derrière.
## Pour passer au-dessus des portillons fermés, les sièges contournent la
## poulie 0,85 m plus haut et « plongent » à hauteur d'assise juste après
## eux (retour d'utilisateur, 22/10/2026).
const PLONGEE: float = 0.85


func x_arret(l: float) -> float:
	return l - L_FREIN - 2.0          # ligne d'arrêt, encore à vitesse d'embarquement


func x_portillons(l: float) -> float:
	return x_arret(l) - 2.2


func _plongee(s: float) -> float:
	if famille.begins_with("cabine") or famille.begins_with("perche"):
		return 0.0
	var z: Array = zone(s)
	if z[0] == "ligne":
		return 0.0
	var x: float = z[1]
	var l: float = z[2]
	var monte: float = smoothstep(L_FREIN + 2.0, L_FREIN + 4.5, x)        # après le débarquement
	var descend: float = 1.0 - smoothstep(x_portillons(l) + 0.4, x_arret(l) - 0.5, x)
	return PLONGEE * monte * descend


func _point_cable(s: float) -> Array:
	s = fposmod(s, longueur_boucle)
	var n: int = _boucle.size()
	if s >= _cumul[n - 1]:
		var a: Vector3 = _boucle[n - 1]
		var b: Vector3 = _boucle[0]
		var u: float = (s - _cumul[n - 1]) / maxf(longueur_boucle - _cumul[n - 1], 0.001)
		return [a.lerp(b, u), (b - a)]
	var lo: int = 0
	var hi: int = n - 1
	while hi - lo > 1:
		var m: int = (lo + hi) / 2
		if _cumul[m] <= s:
			lo = m
		else:
			hi = m
	var u2: float = (s - _cumul[lo]) / maxf(_cumul[hi] - _cumul[lo], 0.001)
	return [_boucle[lo].lerp(_boucle[hi], u2), _boucle[hi] - _boucle[lo]]


## Dans quelle gare (et où) se trouve l'abscisse s : [zone, x depuis l'entrée, longueur de zone].
func zone(s: float) -> Array:
	s = fposmod(s, longueur_boucle)
	for z in _zones:
		if s >= z[0] and s <= z[1]:
			return [z[2], s - float(z[0]), float(z[1]) - float(z[0])]
	return ["ligne", 0.0, 0.0]


## Vitesse à l'abscisse s : pleine vitesse en ligne ; en gare, freinage à
## décélération constante jusqu'à la vitesse d'embarquement, puis
## accélération avant la sortie.
func vitesse_en(s: float) -> float:
	var z: Array = zone(s)
	if z[0] == "ligne":
		return vitesse
	var x: float = z[1]
	var l: float = z[2]
	var a: float = (vitesse * vitesse - v_embarquement * v_embarquement) / (2.0 * L_FREIN)
	var depuis_bord: float = minf(x, l - x)
	return sqrt(minf(vitesse * vitesse, v_embarquement * v_embarquement + 2.0 * a * maxf(depuis_bord, 0.0)))


# --- gares, pylônes, câble ----------------------------------------------------------

func _gare(aval: bool) -> void:
	var g: Node3D = Node3D.new()
	g.name = "GareAval" if aval else "GareAmont"
	var L: float = longueur_h()
	var y0: float = terrain(0.0 if aval else L)
	var zc: float = L_GARE if aval else -L - L_GARE     # axe de la poulie
	var znez: float = 0.0 if aval else -L
	g.position = Vector3(0, y0, 0)
	add_child(g)
	var dz: float = zc - znez
	var zm: float = (zc + znez) * 0.5 + signf(dz) * 1.5
	var long_g: float = absf(dz) + voie * 0.5 + 3.5
	# dalle et quais
	RemonteeKit.boite_en(g, Vector3(voie + 4.0, 0.4, long_g), Vector3(0, -0.2, zm), "beton")
	# charpente : quatre poteaux, deux longerons, toiture
	for sx in [-1.0, 1.0]:
		for k in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(0.30, H_CABLE_GARE + 2.4, 0.30),
				Vector3(sx * (voie * 0.5 + 1.6), (H_CABLE_GARE + 2.4) * 0.5, zm + k * long_g * 0.35), "peinture_gris")
		RemonteeKit.boite_en(g, Vector3(0.35, 0.6, long_g), Vector3(sx * (voie * 0.5 + 1.6), H_CABLE_GARE + 2.1, zm), "peinture_gris")
	RemonteeKit.boite_en(g, Vector3(voie + 4.2, 0.12, long_g + 0.6), Vector3(0, H_CABLE_GARE + 2.5, zm), "peinture_anthracite")
	# poulie horizontale (motrice en amont, retour-tension en aval) et son bâti
	var R: float = voie * 0.5
	RemonteeKit.cylindre(g, R + 0.05, R + 0.05, 0.25, Transform3D(Basis.IDENTITY, Vector3(0, H_CABLE_GARE, zc)), "acier", 48)
	RemonteeKit.cylindre(g, R - 0.35, R - 0.35, 0.28, Transform3D(Basis.IDENTITY, Vector3(0, H_CABLE_GARE, zc)), "peinture_anthracite", 48)
	for k in range(6):
		var a: float = TAU * k / 6.0
		RemonteeKit.poutre(g, Vector3(0, H_CABLE_GARE, zc), Vector3(cos(a) * (R - 0.3), H_CABLE_GARE, zc + sin(a) * (R - 0.3)), 0.12, 0.20, "acier")
	RemonteeKit.cylindre(g, 0.45, 0.45, 1.6, Transform3D(Basis.IDENTITY, Vector3(0, H_CABLE_GARE + 0.9, zc)), "peinture_gris", 20)
	RemonteeKit.boite_en(g, Vector3(2.2, 1.0, 2.6), Vector3(0, H_CABLE_GARE + 1.9, zc), "peinture_gris")
	# rail des véhicules débrayés : le long des deux voies et autour de la poulie
	# rail sous les galets de roulement de la pince (x +0,25, y +0,11, r 0,065)
	var y_rail: float = H_CABLE_GARE + 0.11 - 0.065 - 0.06
	for sx in [-1.0, 1.0]:
		var x_rail: float = sx * (R + 0.25)
		RemonteeKit.poutre(g, Vector3(x_rail, y_rail, znez - signf(dz) * 1.0), Vector3(x_rail, y_rail, zc), 0.08, 0.12, "acier")
		# rangée de pneus (freinage / lancement), sous la plaque de friction
		var z: float = znez + signf(dz) * 1.5
		while absf(z - znez) < absf(dz) - 0.8:
			# pneus contre la plaque de friction (x +0,37, y +0,20), axe vertical
			RemonteeKit.cylindre(g, 0.21, 0.21, 0.14, Transform3D(Basis.IDENTITY, Vector3(sx * (R + 0.39 + 0.21), H_CABLE_GARE + 0.20, z)), "caoutchouc", 16)
			z += signf(dz) * 0.62
		# came d'ouverture / de fermeture des pinces, au nez de la gare
		RemonteeKit.poutre(g, Vector3(sx * (R + 0.42), H_CABLE_GARE + 0.40, znez), Vector3(sx * (R + 0.46), H_CABLE_GARE + 0.30, znez + signf(dz) * 3.0), 0.06, 0.05, "jaune_securite")
	var pts: PackedVector3Array = RemonteeKit.arc(Vector3(0, y_rail, zc), Vector3.RIGHT, Vector3.BACK * signf(dz), R + 0.25, 0.0, PI, 24)
	RemonteeKit.tube(g, pts, 0.06, "acier", 6)
	# portique d'entrée (l'arche que l'on voit depuis la ligne)
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.25, H_CABLE_GARE + 1.6, 0.25), Vector3(sx * (voie * 0.5 + 1.0), (H_CABLE_GARE + 1.6) * 0.5, znez), "peinture_gris")
	RemonteeKit.boite_en(g, Vector3(voie + 2.4, 0.4, 0.4), Vector3(0, H_CABLE_GARE + 1.6, znez), "peinture_gris")
	# ligne d'embarquement (bande jaune) côté montée en aval, côté descente en amont
	var xb: float = _x_brin(aval)
	RemonteeKit.boite_en(g, Vector3(voie * 0.5 + 0.8, 0.02, 0.12), Vector3(xb * 0.6, 0.01, znez + signf(dz) * (L_FREIN + 2.5)), "jaune_securite")
	MeshMerge.merge(g, [], "Gare")


## Collisions fixes : pylônes (massif, fût, traverse) et gares (dalle,
## poteaux, bâti de poulie) ; les véhicules portent la leur.
var avec_collisions: bool = false


func _collisions_fixes() -> void:
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsLigne"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	add_child(corps)
	var boite := func(taille: Vector3, centre: Vector3) -> void:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = taille
		cs.shape = b
		cs.position = centre
		corps.add_child(cs)
	for i in range(pylones.size()):
		var d: float = float(pylones[i]["d"])
		var t: float = terrain(d)
		var h: float = _tetes[i] - t - PyloneRemontee.DESSUS_TRAVERSE_CABLE
		boite.call(Vector3(2.4, 0.7, 2.4), Vector3(0, t - 0.15, -d))
		var cs2: CollisionShape3D = CollisionShape3D.new()
		var cy: CylinderShape3D = CylinderShape3D.new()
		cy.radius = 0.45 + h * 0.003
		cy.height = h
		cs2.shape = cy
		cs2.position = Vector3(0, t + h * 0.5, -d)
		corps.add_child(cs2)
		boite.call(Vector3(voie + 0.30, 0.55, 0.5), Vector3(0, t + h - 0.275, -d))
	var L: float = longueur_h()
	for aval in [true, false]:
		var y0: float = terrain(0.0 if aval else L)
		var zc: float = L_GARE if aval else -L - L_GARE
		var znez: float = 0.0 if aval else -L
		var dz: float = zc - znez
		var zm: float = (zc + znez) * 0.5 + signf(dz) * 1.5
		var long_g: float = absf(dz) + voie * 0.5 + 3.5
		boite.call(Vector3(voie + 4.0, 0.4, long_g), Vector3(0, y0 - 0.2, zm))
		for sx in [-1.0, 1.0]:
			for k in [-1.0, 1.0]:
				boite.call(Vector3(0.30, H_CABLE_GARE + 2.4, 0.30),
					Vector3(sx * (voie * 0.5 + 1.6), y0 + (H_CABLE_GARE + 2.4) * 0.5, zm + k * long_g * 0.35))
		boite.call(Vector3(2.2, 1.0, 2.6), Vector3(0, y0 + H_CABLE_GARE + 1.9, zc))


## Corps de collision d'un véhicule : À PART du véhicule (qui peut être en
## miroir, ce que la physique ne supporte pas), posé à chaque image avec une
## base directe. C'est lui que le skieur prend pour support (meta « vehicule ») :
## dans une cabine, il est emporté comme dans une rame du funiculaire.
var _corps: Array = []          # par véhicule : [StaticBody3D, [CollisionShape3D des portes]]


func _corps_vehicule(i: int) -> void:
	var v: VehiculeRemontee = _vehicules[i][0]
	var formes: Array = v.formes_collision(1.0 if sens_droite else -1.0)
	if formes.is_empty():
		_corps.append(null)
		return
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "Corps_%d" % i
	corps.collision_layer = CollisionsJeu.COUCHE_VEHICULE
	corps.collision_mask = 0
	corps.set_meta("vehicule", corps)
	add_child(corps)
	var portes: Array = []
	for f in formes:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = f[0]
		cs.shape = b
		cs.position = f[1]
		corps.add_child(cs)
		if f[2]:
			portes.append(cs)
	while _corps.size() < i:
		_corps.append(null)
	_corps.append([corps, portes])
	_placer(i)


# --- portillons ---------------------------------------------------------------------

var _portillons_gares: Array = []      # [aval, [vantaux], [formes de collision], t depuis passage, x précédent]


## Portillons à travers la voie d'embarquement, un vantail par paire de
## places, pivotant sur un poteau ; ligne d'arrêt jaune devant.
func _portillons(aval: bool) -> void:
	var l: float = longueur_zone(aval)
	var a: Array = _point_cable(s_gare(aval, x_portillons(l)))
	var p: Vector3 = a[0]
	var dirh: Vector3 = a[1]
	dirh.y = 0.0
	dirh = dirh.normalized()
	var y0: float = terrain(0.0 if aval else longueur_h())
	var g: Node3D = Node3D.new()
	g.name = "Portillons" + ("Aval" if aval else "Amont")
	g.transform = Transform3D(Basis.looking_at(dirh, Vector3.UP), Vector3(p.x, y0, p.z))
	add_child(g)
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	var W: float = 0.50 * places + 0.20
	var n: int = maxi(1, places / 2)
	var lv: float = W / n
	var vantaux: Array = []
	var formes: Array = []
	var corps: StaticBody3D = StaticBody3D.new()
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	g.add_child(corps)
	for k in range(n + 1):
		var x: float = -W * 0.5 + k * lv
		RemonteeKit.cylindre(g, 0.04, 0.04, 1.05, Transform3D(Basis.IDENTITY, Vector3(x, 0.525, 0)), "acier", 8)
	for k in range(n):
		var x0: float = -W * 0.5 + k * lv
		var v: Node3D = Node3D.new()
		v.position = Vector3(x0 + 0.05, 0, 0)
		g.add_child(v)
		RemonteeKit.boite_en(v, Vector3(lv - 0.12, 0.05, 0.04), Vector3((lv - 0.12) * 0.5, 0.95, 0), "jaune_securite")
		RemonteeKit.boite_en(v, Vector3(lv - 0.12, 0.05, 0.04), Vector3((lv - 0.12) * 0.5, 0.55, 0), "jaune_securite")
		RemonteeKit.boite_en(v, Vector3(0.04, 0.45, 0.04), Vector3(lv - 0.14, 0.75, 0), "jaune_securite")
		vantaux.append(v)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = Vector3(lv - 0.10, 1.0, 0.08)
		cs.shape = b
		cs.position = Vector3(x0 + lv * 0.5, 0.5, 0)
		corps.add_child(cs)
		formes.append(cs)
	# ligne d'arrêt (jaune) au sol
	var q: Vector3 = point_embarquement(aval)
	var ls: Node3D = Node3D.new()
	ls.transform = Transform3D(Basis.looking_at(dirh, Vector3.UP), Vector3(q.x, y0 + 0.01, q.z))
	add_child(ls)
	RemonteeKit.boite_en(ls, Vector3(W, 0.02, 0.12), Vector3.ZERO, "jaune_securite")
	RemonteeKit.boite_en(ls, Vector3(W, 0.02, 0.05), Vector3(0, 0, 0.25), "joint")
	_portillons_gares.append([aval, vantaux, formes, 99.0, 0.0])


## Ouverts 0,3 à 3 s après le passage d'un siège à la ligne d'arrêt.
func _maj_portillons(delta: float) -> void:
	for pg in _portillons_gares:
		var aval: bool = pg[0]
		var l: float = longueur_zone(aval)
		var xa: float = x_arret(l)
		pg[3] = float(pg[3]) + delta
		for e in _vehicules:
			var z: Array = zone(e[1])
			if z[0] == ("gare_aval" if aval else "gare_amont"):
				var x: float = z[1]
				if x >= xa and x - vitesse_en(e[1]) * delta < xa:
					pg[3] = 0.0
		var t: float = pg[3]
		var ouv: float = clampf(minf((t - 0.3) / 0.5, (3.0 - t) / 0.5), 0.0, 1.0)
		for v in pg[1]:
			(v as Node3D).rotation.y = -1.45 * ouv
		for cs in pg[2]:
			(cs as CollisionShape3D).disabled = ouv > 0.5


# --- embarquement ------------------------------------------------------------------

## Le véhicule (indice) qui passe au point d'embarquement de la gare (aval
## ou amont), juste après le demi-tour, encore à vitesse d'embarquement.
func vehicule_a_embarquer(aval: bool) -> int:
	var nom: String = "gare_aval" if aval else "gare_amont"
	for i in range(_vehicules.size()):
		var z: Array = zone(_vehicules[i][1])
		if z[0] == nom:
			var x: float = z[1]
			var l: float = z[2]
			if x > x_arret(l) - 1.4 and x < x_arret(l) + 0.6:
				return i
	return -1


## Abscisse (boucle) d'un point de la gare : x depuis l'entrée de sa zone.
func s_gare(aval: bool, x: float) -> float:
	var z: Array = _zones[0] if aval else _zones[1]
	return float(z[0]) + x


func longueur_zone(aval: bool) -> float:
	var z: Array = _zones[0] if aval else _zones[1]
	return float(z[1]) - float(z[0])


## Le véhicule i vient d'arriver en gare (après le freinage) : [gare aval ?] ou [].
func arrivee(i: int) -> Array:
	var z: Array = zone(_vehicules[i][1])
	if z[0] == "ligne":
		return []
	var x: float = z[1]
	if x > L_FREIN and x < L_FREIN + 2.0:
		return [z[0] == "gare_aval"]
	return []


func vehicule(i: int) -> VehiculeRemontee:
	return _vehicules[i][0]


## Point (local) de la ligne d'arrêt : sur le quai, au droit du passage
## des véhicules, là où l'on attend le siège.
func point_embarquement(aval: bool) -> Vector3:
	var p: Vector3 = _point_cable(s_gare(aval, x_arret(longueur_zone(aval))))[0]
	return Vector3(p.x, terrain(0.0 if aval else longueur_h()) + 0.05, p.z)


## Point (local) de débarquement : sur le quai, à côté du véhicule arrêté.
func point_debarquement(aval: bool) -> Vector3:
	var L: float = longueur_h()
	var x: float = _x_brin(not aval)
	var z: float = (L_FREIN + 1.0) if aval else (-L - L_FREIN - 1.0)
	return Vector3(x + signf(x) * 1.6, terrain(0.0 if aval else L) + 0.05, z)


func _poser_pylones() -> void:
	for i in range(pylones.size()):
		var p: Dictionary = pylones[i]
		var d: float = float(p["d"])
		var t: float = terrain(d)
		var py: PyloneRemontee = PyloneRemontee.new()
		py.numero = i + 1
		py.voie = voie
		py.sens_montee_droite = sens_droite
		py.hauteur = _tetes[i] - t - PyloneRemontee.DESSUS_TRAVERSE_CABLE
		py.compo_montee = p.get("montee", [[8, "S"]])
		py.compo_descente = p.get("descente", [[8, "S"]])
		var e: float = 4.0
		py.pente = atan2(y_cable(d + e) - y_cable(d - e), 2.0 * e)
		py.position = Vector3(0, t, -d)
		py.name = "P%d" % (i + 1)
		add_child(py)
		py.construire()
		MeshMerge.merge(py, [], "Pylone")


func _cable() -> void:
	# câble de la boucle (en gare il suit la poulie, en ligne la flèche)
	var pts: PackedVector3Array = PackedVector3Array()
	for p in _boucle:
		pts.append(p)
	pts.append(_boucle[0])
	var c: Node3D = Node3D.new()
	c.name = "Cable"
	add_child(c)
	RemonteeKit.tube(c, pts, PyloneRemontee.R_CABLE, "cable", 6)


func _peupler() -> void:
	# un véhicule toutes les `espacement / vitesse` secondes : on parcourt la
	# boucle avec le profil de vitesse et l'on en dépose un à chaque intervalle
	var dt_v: float = espacement / vitesse
	var s: float = 0.0
	var t: float = 0.0
	var prochain: float = 0.0
	var garde: int = 0
	while s < longueur_boucle and garde < 200000:
		if t >= prochain:
			_ajouter_vehicule(s)
			prochain += dt_v
		var v: float = vitesse_en(s)
		s += v * 0.05
		t += 0.05
		garde += 1


func _ajouter_vehicule(s: float) -> void:
	var v: VehiculeRemontee = VehiculeRemontee.new()
	v.famille = famille
	add_child(v)
	v.construire()
	_vehicules.append([v, s])
	_placer(_vehicules.size() - 1)


func nombre_vehicules() -> int:
	return _vehicules.size()


func _process(delta: float) -> void:
	_maj_portillons(delta)
	for i in range(_vehicules.size()):
		var s: float = _vehicules[i][1]
		_vehicules[i][1] = fposmod(s + vitesse_en(s) * delta, longueur_boucle)
		_placer(i)


func _placer(i: int) -> void:
	var v: VehiculeRemontee = _vehicules[i][0]
	var s: float = _vehicules[i][1]
	var pt: Array = point(s)
	var dirh: Vector3 = pt[1]
	dirh.y = 0.0
	if dirh.length() < 0.001:
		dirh = Vector3.FORWARD
	var b: Basis = Basis.looking_at(dirh.normalized(), Vector3.UP)
	# la suspente est toujours à l'EXTÉRIEUR de la boucle : à droite du
	# véhicule si la ligne monte à droite, à gauche sinon (véhicule en
	# miroir) — avant, sur les lignes « Gauche » (Boisses, Marmottes), elle
	# passait côté pylône, dans les balanciers (retour d'utilisateur, 22/10/2026)
	if i < _corps.size() and _corps[i] != null:
		(_corps[i][0] as Node3D).transform = Transform3D(b, pt[0])
	if not sens_droite:
		b = b * Basis.from_scale(Vector3(-1, 1, 1))
	v.transform = Transform3D(b, pt[0])
	# pièces animées selon la place dans la gare
	var z: Array = zone(s)
	var ouverture: float = 0.0
	var gc: float = 1.0
	if z[0] != "ligne":
		var x: float = z[1]
		var l: float = z[2]
		ouverture = clampf(minf(x, l - x) / 1.2, 0.0, 1.0)            # pince : 1,2 m pour s'ouvrir
		gc = 0.0
	else:
		# garde-corps : baissé ~10 s après la sortie, relevé 25 m avant l'arrivée
		var d_sortie: float = _distance_depuis_sortie(s)
		var d_entree: float = _distance_avant_entree(s)
		gc = clampf((d_sortie - 40.0) / 15.0, 0.0, 1.0) * clampf((d_entree - 20.0) / 10.0, 0.0, 1.0)
	v.ouvrir_pince(ouverture)
	v.garde_corps(gc)
	v.bulle(gc)
	if v.cabine:
		var porte: float = 0.0
		if z[0] != "ligne":
			var x2: float = z[1]
			var l2: float = z[2]
			porte = clampf((minf(x2, l2 - x2) - L_FREIN) / 2.0, 0.0, 1.0)
		v.portes(porte)
		if i < _corps.size() and _corps[i] != null:
			for cs in _corps[i][1]:
				(cs as CollisionShape3D).disabled = porte > 0.5


func _distance_depuis_sortie(s: float) -> float:
	var best: float = INF
	for z in _zones:
		best = minf(best, fposmod(s - float(z[1]), longueur_boucle))
	return best


func _distance_avant_entree(s: float) -> float:
	var best: float = INF
	for z in _zones:
		best = minf(best, fposmod(float(z[0]) - s, longueur_boucle))
	return best
