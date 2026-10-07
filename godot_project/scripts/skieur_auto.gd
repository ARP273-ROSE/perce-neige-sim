class_name SkieurAuto
extends RefCounted
## Le skieur en mode AUTO (Kevin, 07/10/2026 : « il peut boucler la boucle
## et remonter ») : la boucle complète tout seul — de la place de Val
## Claret à la rame, le trajet, la sortie en haut par la porte de la piste
## Génépy, à pied jusqu'au départ d'une vraie descente de Kevin (au pied de
## la gare), chausser, la descente sur sa trace, déchausser à Val Claret,
## retour à la gare, et on recommence.
##
## Chaque étape pose des points de passage (SkieurJoueur.chemin, suivi à
## pied ou à ski par le pilote) et attend un état (rame à quai, portes
## ouvertes, arrivée). Une étape trop longue (bloqué) : il est reposé au
## point suivant.

enum Etape { VERS_SALLE, VERS_RAME, A_BORD, VERS_SORTIE, VERS_DEPART, SKI, VERS_GARE }

const DESCENTE: int = 3                  # trace n° 4 : part au pied de la gare du glacier
const DELAI_MAX: Dictionary = {Etape.VERS_SALLE: 90.0, Etape.VERS_RAME: 120.0, Etape.A_BORD: 900.0,
	Etape.VERS_SORTIE: 120.0, Etape.VERS_DEPART: 120.0, Etape.SKI: 1200.0, Etape.VERS_GARE: 180.0}

var main: Node = null
var etape: int = Etape.VERS_SALLE
var t: float = 0.0
var boucles: int = 0
var _attente: bool = false                # attend la rame sur le palier
var _compte: float = 0.0                  # vantaux : temps d'ouverture écoulé


func demarrer(m: Node) -> void:
	main = m
	var sk: SkieurJoueur = main.skieur
	if sk.chausse:
		main.basculer_ski()
	# d'où l'on part : en haut (dans la rame ou dehors) ou en bas
	var p: Vector3 = sk.global_position
	var xf_h: Transform3D = main.tunnel.transform_at(PNConstants.LENGTH)
	if sk.support != null:
		_poser(Etape.A_BORD)
	elif p.distance_to(xf_h.origin) < 400.0:
		_poser(Etape.VERS_SORTIE if main._skieur_en_gare() else Etape.VERS_DEPART)
	else:
		_poser(Etape.VERS_SALLE)


## Il veut descendre de la rame à quai : l'automate l'attend.
func descend() -> bool:
	return etape == Etape.VERS_SORTIE and main.skieur.support != null


func arreter() -> void:
	if main != null and main.skieur != null:
		main.skieur.chemin.clear()


func tick(delta: float) -> void:
	var sk: SkieurJoueur = main.skieur
	var ph: TrainPhysics = main.physics
	t += delta
	match etape:
		Etape.VERS_SALLE:
			if sk.chemin.is_empty():
				_poser(Etape.VERS_RAME)
		Etape.VERS_RAME:
			# il attend sur le palier que la rame soit à quai, portes ouvertes
			var a_quai: bool = ph.doors_open and ph.s < PNConstants.START_S + 5.0 and absf(ph.v) < 0.1
			if _attente and a_quai:
				_attente = false
				sk.chemin = _chemin_voiture()
			elif sk.chemin.is_empty():
				if sk.support != null:
					_poser(Etape.A_BORD)
				elif not _attente:
					_attente = true
			if _attente and t > DELAI_MAX[Etape.VERS_RAME]:
				t = 0.0               # la rame met du temps : on attend encore
		Etape.A_BORD:
			# à quai en haut, portes ouvertes : les vantaux mettent 4 s à
			# s'ouvrir, on les laisse finir
			if ph.doors_open and ph.door_leaves_open and ph.s > PNConstants.STOP_S - 5.0 \
					and absf(ph.v) < 0.1 and sk.support != null:
				_compte += delta
				if _compte > 6.0:
					_poser(Etape.VERS_SORTIE)
			else:
				_compte = 0.0
		Etape.VERS_SORTIE:
			if sk.chemin.is_empty():
				_poser(Etape.VERS_DEPART)
		Etape.VERS_DEPART:
			if sk.chemin.is_empty():
				_poser(Etape.SKI)
		Etape.SKI:
			var q: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
			if sk.chemin.is_empty() or (q.length() < DomaineSkiable.R_ARRIVEE and sk.chemin.size() <= 2):
				_poser(Etape.VERS_GARE)
		Etape.VERS_GARE:
			if sk.chemin.is_empty():
				boucles += 1
				_poser(Etape.VERS_SALLE)
	if t > DELAI_MAX[etape]:
		_debloquer()


## Points de passage de l'étape, comme le banc du skieur.
func _poser(e: int) -> void:
	etape = e
	t = 0.0
	_attente = false
	_compte = 0.0
	var sk: SkieurJoueur = main.skieur
	var ga: GareAval = main.station_halls.gare_aval
	var cab: Cabin = main.cabin
	var tun: TunnelBuilder = main.tunnel
	match e:
		Etape.VERS_SALLE:
			var tv: Vector2 = (GareAval.FACADE_B - GareAval.FACADE_A).normalized()
			var de: Vector2 = Vector2(-tv.y, tv.x)
			if Geometry2D.is_point_in_polygon((GareAval.FACADE_A + GareAval.FACADE_B) * 0.5 + de, PackedVector2Array(GareAval.HALL)):
				de = -de
			var mil: Vector2 = (GareAval.FACADE_A + GareAval.FACADE_B) * 0.5 + tv * GareAval.ARCHE_DECALAGE
			var mil0: Vector2 = (GareAval.FACADE_A + GareAval.FACADE_B) * 0.5
			sk.chemin = [ga._p2(mil + de * 16.0 + tv * 1.4), ga._p2(mil + de * 9.0 + tv * 1.4),
				ga._p2(mil0 + de * 2.0), ga._p2(mil0 - de * 2.5), ga._p2(Vector2(-3.55, 6.0)), ga._p2(Vector2(-3.55, 2.0))]
		Etape.VERS_RAME:
			var ph: TrainPhysics = main.physics
			if ph.doors_open and ph.s < PNConstants.START_S + 5.0 and absf(ph.v) < 0.1:
				sk.chemin = _chemin_voiture()
			else:
				sk.chemin = [ga._p2(Vector2(-3.55, 2.0))]
				_attente = true
		Etape.A_BORD:
			sk.chemin.clear()
		Etape.VERS_SORTIE:
			# par la porte la plus proche de lui (celle où il est monté : les
			# porte-skis barrent l'allée, on ne traverse pas la voiture), vers
			# le quai gauche et la porte de la piste Génépy, comme le banc
			var v: Node3D = cab._interior_cars[1]
			var r: Array = _porte(_porte_proche(v))
			var sc: float = (StationsBuilder.PORTE_GENEPY.x + StationsBuilder.PORTE_GENEPY.y) * 0.5
			var xg: Transform3D = tun.transform_at(sc)
			# la porte du côté gauche de la voie (la rame n'est retournée qu'au
			# départ : ce côté est +x ou −x dans le repère de la voiture)
			var x0: Transform3D = tun.transform_at(PNConstants.LENGTH)
			var droite: Vector3 = v.global_transform * Vector3(2.4, r[1], r[2])
			var xp: float = -2.4 if (droite - x0.origin).dot(x0.basis.x) > 0.0 else 2.4
			# d'abord l'allée centrale jusqu'au droit de la porte (les bancs
			# des panneaux à fenêtre bordent l'allée à 0,70 m de l'axe), puis
			# l'embrasure, le quai, la porte Génépy
			sk.chemin = [v.global_transform * Vector3(0.9 * signf(xp), r[1], r[2]), v.global_transform * Vector3(xp, r[1], r[2])]
			for la in [-3.0, -4.4, -6.0, -7.8, -12.0]:
				sk.chemin.append(xg.origin + xg.basis.x * la)
		Etape.VERS_DEPART:
			# à pied, de la neige de la Génépy au départ de la trace, de
			# l'autre côté de la voie (48 m à droite en regardant vers le haut,
			# 19 m en aval de la porte, au-dessus du tunnel). Depuis le seuil,
			# d'abord 19 m en aval à 5 m de l'axe : tout droit, on butait sur
			# le coin de la bouche du tunnel et l'on glissait dans le vide sous
			# le plancher de la gare (le relief y est troué — carte du
			# 07/10/2026, pièces fines de 2,5 m)
			var pts0: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			var p0: Vector2 = pts0[0]
			var q: Vector3 = sk.global_position
			var sc2: float = (StationsBuilder.PORTE_GENEPY.x + StationsBuilder.PORTE_GENEPY.y) * 0.5
			var xg2: Transform3D = tun.transform_at(sc2)
			var seuil: Vector3 = xg2.origin + xg2.basis.x * -12.0
			sk.chemin = []
			if Vector2(q.x - seuil.x, q.z - seuil.z).length() < 6.0:
				var aval: Vector3 = xg2.origin + xg2.basis.x * -5.0 + xg2.basis.z * 19.0
				sk.chemin.append(Vector3(aval.x, 0.0, aval.z))
				q = aval
			var m: Vector3 = (q + Vector3(p0.x, 0.0, p0.y)) * 0.5
			sk.chemin.append_array([Vector3(m.x, 0.0, m.z), Vector3(p0.x, 0.0, p0.y)])
		Etape.SKI:
			if not sk.chausse:
				main.basculer_ski()
			if not sk.chausse:
				_poser(Etape.VERS_DEPART)
				return
			var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			var d: Vector2 = pts[8] - pts[0]
			sk._cap_ski = atan2(-d.x, -d.y)
			sk.vitesse_pilote = 11.0
			sk.chemin = main.domaine.chemin_descente(DESCENTE, 3)
		Etape.VERS_GARE:
			if sk.chausse:
				main.basculer_ski()
			var dep: Array = ga.point_depart()
			sk.chemin = [dep[0]]


func _chemin_voiture() -> Array:
	var ga: GareAval = main.station_halls.gare_aval
	var cab: Cabin = main.cabin
	var v: Node3D = cab._interior_cars[1]
	var r: Array = _porte(7)
	var xf: Transform3D = v.global_transform
	var y: float = r[1]
	var zc: float = r[2]
	return [ga._p2(Vector2(-3.55, -1.6)), xf * Vector3(2.6, y, zc + 3.0), xf * Vector3(2.4, y, zc),
		xf * Vector3(0.9, y, zc), xf * Vector3(0.3, y, zc)]


## Panneau de porte de la voiture 2 le plus proche du skieur (le long de la
## voiture).
func _porte_proche(v: Node3D) -> int:
	var z: float = (v.global_transform.affine_inverse() * main.skieur.global_position).z
	var meilleur: int = 7
	var d_min: float = INF
	for k in range(10):
		if TrainBodyBuilder.KINDS[k] != "door":
			continue
		var d: float = absf(float(_porte(k)[2]) - z)
		if d < d_min:
			d_min = d
			meilleur = k
	return meilleur


## [voiture 2, y, z] de la porte au panneau k.
func _porte(k: int) -> Array:
	var cab: Cabin = main.cabin
	var v: Node3D = cab._interior_cars[1]
	var car_len: float = cab.train_length / float(cab.car_count)
	var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
	var zc: float = cab._panel_center(1, k) - z_c - (0.35 if k == 5 else 0.0)
	return [v, TrainBodyBuilder.Y_FLOOR + 0.3, zc]


## Bloqué : reposé au dernier point de l'étape, ou à l'étape suivante.
func _debloquer() -> void:
	var sk: SkieurJoueur = main.skieur
	print("[SkieurAuto] étape %d trop longue : on repose le skieur" % etape)
	match etape:
		Etape.VERS_SALLE, Etape.VERS_GARE:
			var ga: GareAval = main.station_halls.gare_aval
			sk.activer(ga._p2(Vector2(-3.55, 2.0)) + Vector3.UP * 0.1, sk.cam_yaw)
			_poser(Etape.VERS_RAME)
		Etape.VERS_RAME:
			_poser(Etape.VERS_RAME)
		Etape.A_BORD:
			t = 0.0
		Etape.VERS_SORTIE, Etape.VERS_DEPART:
			var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			var p0: Vector2 = pts[0]
			sk.activer(Vector3(p0.x, main.relief.hauteur_sol(p0.x, p0.y) + 0.1, p0.y), sk.cam_yaw)
			sk.support = null
			_poser(Etape.SKI)
		Etape.SKI:
			var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			var fin: Vector2 = pts[pts.size() - 1]
			if sk.chausse:
				main.basculer_ski()
			sk.activer(Vector3(fin.x, main.relief.hauteur_sol(fin.x, fin.y) + 0.1, fin.y), sk.cam_yaw)
			_poser(Etape.VERS_GARE)
