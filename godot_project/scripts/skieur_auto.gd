class_name SkieurAuto
extends RefCounted
## Le skieur en mode AUTO (retour d'utilisateur, 07/10/2026 : « il peut boucler la boucle
## et remonter ») : la boucle complète tout seul — de la place de Val
## Claret à la rame, le trajet, la sortie en haut par la porte de la piste
## Génépy, à pied jusqu'au départ d'une vraie descente d'un utilisateur (au pied de
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
	Etape.VERS_SORTIE: 180.0, Etape.VERS_DEPART: 300.0, Etape.SKI: 1200.0, Etape.VERS_GARE: 180.0}

var main: Node = null
var etape: int = Etape.VERS_SALLE
var t: float = 0.0
var boucles: int = 0
var debloquages: int = 0                  # étapes trop longues (bancs)
var _attente: bool = false                # attend la rame sur le palier
var _compte: float = 0.0                  # vantaux : temps d'ouverture écoulé
## La rame qu'il prend : celle qui est à quai en bas, pilotée OU d'en face
## (09/10/2026, retour d'utilisateur : « si j'ai choisi de piloter la rame 2 mais que le
## skieur monte dans la 1, l'exploitation auto et la boucle ne marchent
## pas ») — avant, seule la rame pilotée comptait.
var _rame: Cabin = null
var _loc: Array = []                      # points d'embarquement, repère voiture
var _voiture: Node3D = null
var _banc: bool = false                   # file vers le banc (rame pas à quai)
## Banc de la salle d'attente face aux portes du quai (GareAval._mobilier :
## poutre de 1,9 m à (0 ; 12,5)) : il s'assoit devant, côté quai.
const BANC: Vector2 = Vector2(-0.4, 12.05)


func _s_de(c: Cabin) -> float:
	return main.physics.s_render if c == main.cabin else main.physics.ghost_s_render()


## Rame à quai en bas (gare_basse) ou en haut, ou null.
func _rame_a(gare_basse: bool) -> Cabin:
	for c in [main.cabin, main.cabin_ghost]:
		if c == null:
			continue
		var sc: float = _s_de(c)
		if (gare_basse and sc < PNConstants.START_S + 5.0) or (not gare_basse and sc > PNConstants.STOP_S - 5.0):
			return c
	return null


func _rame_du_skieur() -> Cabin:
	var r: Cabin = main._rame_du_skieur()
	if r != null:
		return r
	return _rame if _rame != null else main.cabin


func demarrer(m: Node) -> void:
	main = m
	var sk: SkieurJoueur = main.skieur
	sk.pilote_expert = true
	# d'où l'on part : dans une rame, dans la gare d'en bas (salle ou quai),
	# en haut (gare ou dehors), ou sur les pistes (retour d'utilisateur, 11/10/2026 : « il ne
	# chausse jamais dans la neige, il marche on ne sait vers où » ; « dans la
	# salle d'attente du bas, il ressort devant la gare et rerentre »)
	var p: Vector3 = sk.global_position
	var xf_h: Transform3D = main.tunnel.transform_at(PNConstants.LENGTH)
	var en_bas: bool = _dans_gare_basse(p)
	var sur_neige: bool = sk.support == null and not en_bas and sk.dehors(main.relief)
	var e: int = Etape.VERS_SALLE
	if sk.support != null:
		e = Etape.A_BORD
	elif en_bas:
		e = Etape.VERS_RAME
	elif main._skieur_en_gare() and p.distance_to(xf_h.origin) < 400.0:
		e = Etape.VERS_SORTIE
	elif p.distance_to(xf_h.origin) < 150.0:
		e = Etape.VERS_DEPART       # terrasse, abords de la gare du glacier
	elif sur_neige and _i_aval(p) >= 0:
		e = Etape.SKI               # sur les pistes : il chausse et descend
	if sk.chausse and e != Etape.SKI:
		main.basculer_ski()
	_poser(e)


## Il veut descendre de la rame à quai : l'automate l'attend.
func descend() -> bool:
	return etape == Etape.VERS_SORTIE and main.skieur.support != null


func arreter() -> void:
	if main != null and main.skieur != null:
		main.skieur.chemin.clear()
		main.skieur.pilote_expert = false
		main.skieur.course_auto = false
		main.skieur.lever()


## Point (x est, z nord) dans le repère de la gare basse.
func _local_aval(p: Vector3) -> Vector2:
	var ga: GareAval = main.station_halls.gare_aval
	var r: Vector3 = p - ga._o
	return Vector2(r.dot(ga._e), r.dot(ga._n))


## Dans la salle d'attente, ou sur le quai / le palier sous la cloison.
func _dans_gare_basse(p: Vector3) -> bool:
	var ga: GareAval = main.station_halls.gare_aval
	var q: Vector2 = _local_aval(p)
	var h: float = p.y - ga._o.y
	if Geometry2D.is_point_in_polygon(q, PackedVector2Array(GareAval.HALL)) and h > -2.0 and h < 4.0:
		return true
	return _sur_quai_bas(p)


## Sur le quai d'en bas (sous la cloison, le long de la rame).
func _sur_quai_bas(p: Vector3) -> bool:
	var ga: GareAval = main.station_halls.gare_aval
	var q: Vector2 = _local_aval(p)
	return q.y < 0.3 and q.y > -60.0 and absf(q.x) < 8.0 and absf(p.y - ga._o.y) < 12.0 \
		and main._gare_du_skieur() == 1


## Embarquement ouvert en bas : rame à quai, arrêtée, portes de la rame et
## porte du quai ouvertes (sur le PC, la rame peut ouvrir ses portes avant
## que la cloison ne s'ouvre : il se cognait à la porte fermée et faisait
## des allers-retours devant).
func _embarquement() -> bool:
	var ph: TrainPhysics = main.physics
	var ga: GareAval = main.station_halls.gare_aval
	var r: Cabin = _rame_a(true)
	if r == null or absf(ph.v) > 0.1 or ga._ouverture < 0.9:
		return false
	return ph.ghost_door_leaves_open() if r == main.cabin_ghost else ph.door_leaves_open


## Premier point de la descente, en aval du skieur et le plus proche
## (parti des pistes : il chausse et rejoint la trace), ou −1.
func _i_aval(p: Vector3) -> int:
	var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
	var meilleur: int = -1
	var d_min: float = 400.0
	for i in range(0, pts.size() - 20, 3):
		var h: float = main.relief.hauteur_sol(pts[i].x, pts[i].y)
		if h > p.y - 3.0:
			continue
		var d: float = Vector2(p.x, p.z).distance_to(pts[i])
		if d < d_min:
			d_min = d
			meilleur = i
	return meilleur


func tick(delta: float) -> void:
	var sk: SkieurJoueur = main.skieur
	var ph: TrainPhysics = main.physics
	t += delta
	match etape:
		Etape.VERS_SALLE:
			sk.course_auto = _embarquement()
			if sk.chemin.is_empty() or (_dans_gare_basse(sk.global_position) and sk.chemin.size() <= 2):
				_poser(Etape.VERS_RAME)
		Etape.VERS_RAME:
			if not _attente:
				_suivre_voiture()
			# il attend assis sur un banc (ou sur le quai s'il y est déjà) que
			# la rame soit à quai, portes ouvertes ; il y court
			if _attente and _embarquement():
				_attente = false
				_rame = _rame_a(true)
				sk.lever()
				sk.course_auto = true
				sk.chemin = _chemin_voiture()
				if not _sur_quai_bas(sk.global_position):
					sk.chemin.push_front(ga_point(Vector2(-3.55, 2.0)))
			elif not _attente and sk.support == null and sk.course_auto and not _embarquement():
				# embarquement fini sans lui (portes refermées, rame partie,
				# ou rattrapé loin après une chute) : il attend la suivante
				# — avant, il se cognait à la porte du quai fermée
				_poser(Etape.VERS_RAME if _dans_gare_basse(sk.global_position) else Etape.VERS_SALLE)
			elif sk.chemin.is_empty():
				if sk.support != null:
					_poser(Etape.A_BORD)
				elif not _attente:
					_attente = true
				elif not sk.assis and _banc and not _sur_quai_bas(sk.global_position):
					# calé pile devant le banc : le chemin s'arrête à 35 cm du
					# point, et il s'asseyait dans le vide devant la planche
					# (retour d'utilisateur, 13/10/2026 : « il n'arrive pas à
					# s'asseoir sur le banc, il rentre dedans »)
					var cible: Vector3 = main.station_halls.gare_aval._p2(BANC)
					var q: Vector3 = sk.global_position
					if Vector2(q.x - cible.x, q.z - cible.z).length() < 1.2:
						sk.global_position = Vector3(cible.x, q.y, cible.z)
						sk.velocity = Vector3.ZERO
					sk.asseoir(_cap_banc())
			if _attente and t > DELAI_MAX[Etape.VERS_RAME]:
				t = 0.0               # la rame met du temps : on attend encore
		Etape.A_BORD:
			# à quai en haut, portes ouvertes : les vantaux mettent 4 s à
			# s'ouvrir, on les laisse finir
			if ph.doors_open and ph.door_leaves_open and sk.support != null \
					and _s_de(_rame_du_skieur()) > PNConstants.STOP_S - 5.0 and absf(ph.v) < 0.1:
				_compte += delta
				if _compte > 6.0:
					_poser(Etape.VERS_SORTIE)
			else:
				_compte = 0.0
		Etape.VERS_SORTIE:
			if sk.chemin.is_empty():
				_poser(Etape.VERS_DEPART)
		Etape.VERS_DEPART:
			# il chausse dès la neige, au sortir de la porte Génépy ou au bas
			# de l'escalier de la terrasse (retour d'utilisateur, 12/10/2026 : « il chausse
			# très tard, il marche jusqu'à retrouver un fantôme ») ; il gagne
			# le départ de la trace à ski
			if not sk.chausse and sk.support == null and sk.dehors(main.relief) \
					and main._gare_du_skieur() == 0 and not _sur_terrasse(sk.global_position):
				var reste: Array = sk.chemin.duplicate()
				main.basculer_ski()
				if sk.chausse:
					sk.chemin = _densifier(reste, 3.0)
			if sk.chemin.is_empty():
				_poser(Etape.SKI)
		Etape.SKI:
			# au pied de la gare : il déchausse et court au guichet ; arrêté
			# 4 s sur le plat (plus de pente) près de Val Claret : pareil
			# (avant : il s'arrêtait 400 m avant et marchait à 2 km/h)
			var q: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
			var dep: Vector3 = main.station_halls.gare_aval.point_depart()[0]
			var d_gare: float = q.distance_to(Vector2(dep.x, dep.z))
			_compte = _compte + delta if (sk.vitesse_ski() < 0.8 and d_gare < 500.0) else 0.0
			if sk.chemin.is_empty() or d_gare < 12.0 or _compte > 4.0:
				_poser(Etape.VERS_GARE)
		Etape.VERS_GARE:
			if sk.chemin.is_empty():
				boucles += 1
				_poser(Etape.VERS_SALLE)
	if t > DELAI_MAX[etape]:
		_debloquer()


## Chemin rendu dense (un point tous les `pas` m, au sol du relief) : le
## pilote expert vise un point à distance donnée le long du tracé.
func _densifier(pts: Array, pas: float) -> Array:
	var out: Array = []
	if pts.is_empty():
		return out
	var rel: ReliefBuilder = main.relief
	for k in range(pts.size()):
		var a: Vector3 = pts[k]
		if k == 0:
			out.append(Vector3(a.x, rel.hauteur_sol(a.x, a.z), a.z))
			continue
		var b0: Vector3 = pts[k - 1]
		var l: float = Vector2(a.x - b0.x, a.z - b0.z).length()
		var n: int = maxi(1, int(ceil(l / pas)))
		for i in range(1, n + 1):
			var q: Vector3 = b0.lerp(a, float(i) / float(n))
			out.append(Vector3(q.x, rel.hauteur_sol(q.x, q.z), q.z))
	return out


## Sur la terrasse de la gare haute (ou son escalier) : on n'y chausse pas.
func _sur_terrasse(p: Vector3) -> bool:
	var gh: GareAmont = main.station_halls.gare_amont
	if gh == null:
		return false
	var rel: Vector3 = p - gh._o
	return rel.y > -1.5 and rel.length() < 65.0


func ga_point(v: Vector2) -> Vector3:
	return main.station_halls.gare_aval._p2(v)


## Regard vers le quai (−nord), assis sur le banc.
func _cap_banc() -> float:
	var n: Vector3 = main.station_halls.gare_aval._n
	return atan2(n.x, n.z)


## Points de passage de l'étape, comme le banc du skieur.
func _poser(e: int) -> void:
	etape = e
	t = 0.0
	_attente = false
	_banc = false
	_compte = 0.0
	var sk: SkieurJoueur = main.skieur
	sk.course_auto = false
	sk.tolerance_chemin = 0.35
	_loc = []
	_voiture = null
	if e != Etape.VERS_RAME:
		sk.lever()
	var ga: GareAval = main.station_halls.gare_aval
	var cab: Cabin = _rame_du_skieur()
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
			# déjà sur la place, au pied de l'escalier : on ne repasse pas
			# par le point le plus loin
			var q0: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
			while sk.chemin.size() > 4 and q0.distance_to(Vector2(sk.chemin[1].x, sk.chemin[1].z)) \
					< q0.distance_to(Vector2(sk.chemin[0].x, sk.chemin[0].z)):
				sk.chemin.pop_front()
		Etape.VERS_RAME:
			var quai: bool = _sur_quai_bas(sk.global_position)
			if _embarquement():
				_rame = _rame_a(true)
				sk.course_auto = true
				sk.chemin = _chemin_voiture()
				if not quai:
					sk.chemin.push_front(ga._p2(Vector2(-3.55, 2.0)))
			elif quai:
				sk.chemin.clear()          # sur le quai : il attend là
				_attente = true
			else:
				# porte du quai fermée : on va s'asseoir sur le banc
				sk.chemin = [ga._p2(BANC)]
				_attente = true
				_banc = true
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
			# la porte du côté gauche de la voie (+x ou −x dans le repère de
			# la voiture, lu sur la géométrie)
			var x0: Transform3D = tun.transform_at(PNConstants.LENGTH)
			var droite: Vector3 = v.global_transform * Vector3(2.4, r[1], r[2])
			var xp: float = -2.4 if (droite - x0.origin).dot(x0.basis.x) > 0.0 else 2.4
			# d'abord l'allée centrale jusqu'au droit de la porte (les bancs
			# des panneaux à fenêtre bordent l'allée à 0,70 m de l'axe), puis
			# l'embrasure, le quai, la porte Génépy
			sk.chemin = []
			if sk.support != null:
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
			# parti de la TERRASSE (départ d'en haut) : par l'escalier du bout,
			# jusqu'à la neige — tout droit, il butait contre le garde-corps et
			# faisait des allers-retours deux minutes (09/10/2026)
			var gh: GareAmont = main.station_halls.gare_amont
			if gh != null:
				var rel: Vector3 = q - gh._o
				if absf(rel.y) < 1.5 and rel.length() < 60.0:
					var ep: Array = gh.escalier_points()
					# par le grand côté de la terrasse : tout droit de la table à
					# l'escalier, on coupait l'échancrure sud et l'on tombait
					# sous le plancher (sur pilotis)
					# (x, d) dans le repère de la terrasse : on se lève de la table,
					# on longe le bord ouest entre garde-corps et tables, puis le
					# grand côté jusqu'à l'escalier
					for v in [Vector2(1.6, 14.0), Vector2(1.8, 30.0), Vector2(3.5, 42.0),
							Vector2(12.0, 48.0), Vector2(17.0, 49.5)]:
						sk.chemin.append(gh._p2(v, 0.05))
					sk.chemin.append_array([ep[0], ep[1]])
					# puis à l'est du restaurant (emprise x 10-42 m), vers l'aval,
					# jusqu'au départ de la trace : tout droit on butait sur le
					# mur du chalet
					for v2 in [Vector2(44.0, 52.0), Vector2(47.0, 20.0), Vector2(47.0, -20.0)]:
						sk.chemin.append(gh._p2(v2, 0.0) * Vector3(1, 0, 1))
					q = gh._p2(Vector2(47.0, -20.0))
			if Vector2(q.x - seuil.x, q.z - seuil.z).length() < 6.0:
				var aval: Vector3 = xg2.origin + xg2.basis.x * -5.0 + xg2.basis.z * 19.0
				sk.chemin.append(Vector3(aval.x, 0.0, aval.z))
				q = aval
			var m: Vector3 = (q + Vector3(p0.x, 0.0, p0.y)) * 0.5
			sk.chemin.append_array([Vector3(m.x, 0.0, m.z), Vector3(p0.x, 0.0, p0.y)])
		Etape.SKI:
			sk.pilote_expert = true
			if not sk.chausse:
				main.basculer_ski()
			if not sk.chausse and sk.support == null:
				# refusé (un bout de relief pris pour un toit) : sur la neige
				# de la trace, il chausse quand même — avant, il retournait à
				# pied au départ et recommençait sans fin
				sk.basculer_ski(true)
				main.commandes_skieur.set_chausse(sk.chausse)
			if not sk.chausse:
				_poser(Etape.VERS_DEPART)
				return
			var pts: PackedVector2Array = FantomesDonnees.points(DESCENTE)
			# du point de la trace le plus proche en aval (au départ : 0)
			var i0: int = _i_aval(sk.global_position + Vector3.UP * 3.5)
			if i0 < 0 or Vector2(sk.global_position.x, sk.global_position.z).distance_to(pts[0]) < 30.0:
				i0 = 0
			var d: Vector2 = pts[mini(i0 + 8, pts.size() - 1)] - pts[i0]
			sk._cap_ski = atan2(-d.x, -d.y)
			sk.vitesse_pilote = 11.0
			# la trace complète (tous ses points, densifiée à 3 m), puis jusqu'au
			# pied de l'escalier de la gare de Val Claret
			# itinéraire sur les PISTES balisées, de là où il est jusqu'au pied
			# de la gare de Val Claret (les traces GPS réelles sortent de nos
			# pistes de 34 à 58 % du temps) ; à défaut, la trace
			var dom: DomaineSkiable = main.domaine
			var dep_v: Vector3 = ga.point_depart()[0]
			var pos_sk: Vector3 = sk.global_position
			var t_it: int = Time.get_ticks_msec()
			var route: PackedVector2Array = dom.itineraire(Vector2(pos_sk.x, pos_sk.z), Vector2(dep_v.x, dep_v.z))
			print("[SkieurAuto] itinéraire sur les pistes : %d points, %d ms" % [route.size(), Time.get_ticks_msec() - t_it])
			var trace: Array = []
			if route.size() >= 2:
				trace.append(Vector3(pos_sk.x, 0.0, pos_sk.z))
				for q in route:
					trace.append(Vector3(q.x, 0.0, q.y))
			else:
				trace = main.domaine.chemin_descente(DESCENTE, 1).slice(i0)
				for k in range(trace.size()):
					var tp: Vector3 = trace[k]
					var sp: Vector2 = dom.sur_piste(Vector2(tp.x, tp.z), 80.0)
					trace[k] = Vector3(sp.x, 0.0, sp.y)
			for _passe in range(2):
				var lisse: Array = trace.duplicate()
				for k in range(2, trace.size() - 2):
					var acc: Vector3 = Vector3.ZERO
					for m in range(-2, 3):
						acc += trace[k + m]
					lisse[k] = acc / 5.0
				trace = lisse
			var dep_g: Vector3 = ga.point_depart()[0]
			trace.append(Vector3(dep_g.x, 0.0, dep_g.z))
			sk.chemin = _densifier(trace, 3.0)
		Etape.VERS_GARE:
			if sk.chausse:
				main.basculer_ski()
			var dep: Array = ga.point_depart()
			sk.chemin = [dep[0]]
			sk.course_auto = true            # en courant, pas à 2 km/h


func _chemin_voiture() -> Array:
	var ga: GareAval = main.station_halls.gare_aval
	var cab: Cabin = _rame if _rame != null else main.cabin
	var v: Node3D = cab._interior_cars[1]
	var r: Array = _porte(7)
	var xf: Transform3D = v.global_transform
	var y: float = r[1]
	var zc: float = r[2]
	# côté du quai où il attend, dans le repère de CETTE voiture (la rame
	# d'en face est tournée autrement)
	var palier: Vector3 = ga._p2(Vector2(-3.55, -1.6))
	var sx: float = signf((xf.affine_inverse() * palier).x)
	if sx == 0.0:
		sx = 1.0
	# dans l'axe de la porte avant d'entrer : la baie des 18 panneaux ne
	# laisse que 11 cm de chaque côté de la capsule, et un point visé à
	# 35 cm près le faisait buter contre le montant
	# (points serrés à 12 cm : SkieurJoueur.tolerance_chemin)
	main.skieur.tolerance_chemin = 0.12
	# points dans le repère de la voiture, recalés à chaque image
	# (_suivre_voiture) : en gare basse la rame recule jusqu'à 1 m pendant
	# l'embarquement (le brin s'allonge sous la charge) et les points figés
	# au monde tombaient sur le montant de la porte
	_loc = [Vector3(2.9 * sx, y, zc + 3.0), Vector3(2.9 * sx, y, zc + 0.8), Vector3(2.9 * sx, y, zc),
		Vector3(2.0 * sx, y, zc), Vector3(0.9 * sx, y, zc), Vector3(0.3 * sx, y, zc)]
	_voiture = v
	var r2: Array = [palier]
	for l in _loc:
		r2.append(xf * l)
	return r2


## Recale sur la voiture les points du chemin d'embarquement qui restent.
func _suivre_voiture() -> void:
	if _voiture == null or not is_instance_valid(_voiture) or _loc.is_empty():
		return
	var ch: Array = main.skieur.chemin
	var n: int = mini(ch.size(), _loc.size())
	var xf: Transform3D = _voiture.global_transform
	for i in range(n):
		ch[ch.size() - n + i] = xf * _loc[_loc.size() - n + i]


## Panneau de porte de la voiture 2 le plus proche du skieur (le long de la
## voiture).
func _porte_proche(v: Node3D) -> int:
	var z: float = (v.global_transform.affine_inverse() * main.skieur.global_position).z
	var meilleur: int = 7
	var d_min: float = INF
	for k in range(TrainBodyBuilder.N_PANNEAUX):
		if TrainBodyBuilder.KINDS[k] != "door":
			continue
		var d: float = absf(float(_porte(k)[2]) - z)
		if d < d_min:
			d_min = d
			meilleur = k
	return meilleur


## [voiture 2, y, z] de la porte au panneau k.
func _porte(k: int) -> Array:
	var cab: Cabin = _rame_du_skieur() if main.skieur.support != null else (_rame if _rame != null else main.cabin)
	var v: Node3D = cab._interior_cars[1]
	var car_len: float = cab.train_length / float(cab.car_count)
	var z_c: float = (1.0 - (cab.car_count - 1) * 0.5) * car_len
	var zc: float = cab._panel_center(1, k) - z_c
	return [v, TrainBodyBuilder.Y_FLOOR + 0.3, zc]


## Bloqué : reposé au dernier point de l'étape, ou à l'étape suivante.
func _debloquer() -> void:
	var sk: SkieurJoueur = main.skieur
	print("[SkieurAuto] étape %d trop longue : on repose le skieur" % etape)
	debloquages += 1
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
