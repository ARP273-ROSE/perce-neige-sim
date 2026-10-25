class_name RemonteesDomaine
extends Node3D
## Remontées mécaniques du domaine posées dans le monde du jeu, à leur place
## réelle (positions OpenStreetMap), sur le relief affiché. Données :
## RemonteesDonnees (générées par le dossier des remontées).
##
## Économie (PWA) : véhicules invisibles au-delà de VEHICULES_JUSQUA m ; une
## ligne dont le milieu est à plus de ACTIVE_JUSQUA m de la caméra ne fait
## plus avancer ses véhicules.

const LAT_O: float = 45.45188591       # origine du monde : pied de la voie du funiculaire
const LON_O: float = 6.89898136        # (mêmes constantes que tools_relief3d.py)
const M_LAT: float = 111320.0
## (PWA : distances réduites — l'arrivée à Val Claret, au milieu de dizaines de
## lignes, saccadait sur iPad ; retour d'utilisateur, 24/10/2026)
var VEHICULES_JUSQUA: float = 450.0 if OS.has_feature("web") else 700.0
const PYLONES_JUSQUA: float = 3000.0
const ACTIVE_JUSQUA: float = 2500.0
var DETAILS_JUSQUA: float = 180.0 if OS.has_feature("web") else 250.0

var relief: ReliefBuilder = null
## Gare amont du funiculaire : la gare de départ du téléphérique de la Grande
## Motte y existe déjà (bâtiment BD TOPO) — posé par main.gd.
var gare_amont: GareAmont = null
var skieur: SkieurJoueur = null
var lignes: Array = []          # [LigneRemontee, milieu monde]
var _t_lod: float = 0.0
## À bord d'un siège : [ligne, indice du véhicule, place, gare de départ aval ?]
var a_bord: Array = []
var _repos: float = 0.0          # pas de nouvel embarquement juste après un débarquement
var _sous_terre: bool = false    # caméra sous terre (funiculaire) : remontées cachées
var _f_lod: float = 0.6 if OS.has_feature("web") else 1.0     # distances du niveau de détail
signal message(texte: String)


static func monde(lat: float, lon: float) -> Vector2:
	var m_lon: float = M_LAT * cos(deg_to_rad(LAT_O))
	return Vector2((lon - LON_O) * m_lon, -(lat - LAT_O) * M_LAT)


var sons: SonsRemontees = null


func construire(r: ReliefBuilder) -> void:
	relief = r
	# sons des remontées (gares, à bord, lanceurs, pylônes, arrêts)
	sons = SonsRemontees.new()
	sons.name = "Sons"
	sons.domaine = self
	add_child(sons)
	for D in RemonteesDonnees.LIGNES:
		_poser(D)
	_jumeler()
	_croisements()
	print("[Remontees] %d lignes posées" % lignes.size())


## Tronçons jumelés : [bas, haut]. Bollin–Fresse dans sa configuration
## d'avant 2019 (aiguillage à la gare intermédiaire, double embarquement en
## bas — retour d'utilisateur, 24/10/2026 : « je veux l'ancienne config »).
const JUMELAGES: Array = [["tsd6_bollin", "tsd6_fresse"]]


func _ligne_nommee(cle: String) -> LigneRemontee:
	for e in lignes:
		if (e[0] as Node).name == cle:
			return e[0]
	return null


## Gares avancées le long de leur axe (m) : le TCD10 du Vallon de l'Iseran part
## APRÈS l'arrivée du téléphérique du Fornet — les deux gares se
## confondaient (retour d'utilisateur, 25/10/2026 ; traces GPS : on descend du
## Fornet 2 m après le nez OSM du Vallon, on embarque au Vallon 22 à 36 m plus
## loin ; la gare du Fornet déborde de 26 m de son nez, celle du Vallon de 34 m
## derrière le sien).
const AVANCES_AVAL: Dictionary = {"tcd10_vallon_iseran": 42.0}
## Croisements [dessus, dessous] : un pylône à deux étages au point de
## croisement, la ligne du dessous plafonnée, celle du dessus au moins
## ECART_CROISEMENT m plus haut (retour d'utilisateur, 25/10/2026 : « Pyramides
## passe au-dessus du Vallon, pylône à deux étages au croisement »).
const CROISEMENTS: Array = [["tsd4_pyramides", "tcd10_vallon_iseran"]]
const H_MAX_DESSOUS: float = 12.0
const ECART_CROISEMENT: float = 7.0


func _croisements() -> void:
	for c in CROISEMENTS:
		var hi: LigneRemontee = _ligne_nommee(c[0])
		var lo: LigneRemontee = _ligne_nommee(c[1])
		if hi == null or lo == null:
			continue
		var a1: Vector2 = Vector2(hi.transform.origin.x, hi.transform.origin.z)
		var d1: Vector2 = Vector2(-hi.transform.basis.z.x, -hi.transform.basis.z.z).normalized()
		var a2: Vector2 = Vector2(lo.transform.origin.x, lo.transform.origin.z)
		var d2: Vector2 = Vector2(-lo.transform.basis.z.x, -lo.transform.basis.z.z).normalized()
		var den: float = d1.x * d2.y - d1.y * d2.x
		if absf(den) < 0.01:
			continue
		var w: Vector2 = a2 - a1
		var t: float = (w.x * d2.y - w.y * d2.x) / den
		var u: float = (w.x * d1.y - w.y * d1.x) / den
		if t < 20.0 or t > hi.longueur_h() - 20.0 or u < 20.0 or u > lo.longueur_h() - 20.0:
			continue
		_pylone_impose(lo, u, 0.0, H_MAX_DESSOUS)
		_pylone_impose(hi, t, H_MAX_DESSOUS + ECART_CROISEMENT, 999.0)


## Pylône imposé à d (porteur), hauteur de câble au-dessus du sol bornée ;
## les pylônes à moins de 25 m sont retirés.
func _pylone_impose(lg: LigneRemontee, d: float, h_min: float, h_max: float) -> void:
	var py: Array = []
	for p in lg.pylones:
		if absf(float(p["d"]) - d) >= 25.0:
			py.append(p)
	var n: Dictionary = {"d": d, "montee": [[8, "S"]], "descente": [[8, "S"]], "h_min": h_min, "h_max": h_max, "croisement": true}
	var j: int = 0
	while j < py.size() and float(py[j]["d"]) < d:
		j += 1
	py.insert(j, n)
	lg.pylones = py


func _jumeler() -> void:
	for j in JUMELAGES:
		var bas: LigneRemontee = _ligne_nommee(j[0])
		var haut: LigneRemontee = _ligne_nommee(j[1])
		if bas == null or haut == null:
			continue
		bas.jumelee = haut
		haut.jumelee = bas
		bas.role = "bas"
		haut.role = "haut"
		# un siège sur deux de Bollin monte à Fresse : Fresse au double de la
		# période ; chaque tronçon garde sa vitesse (4,6 et 5 m/s, fiche RM.net)
		haut.voie = bas.voie
		bas.periode_imposee = bas.espacement / bas.vitesse
		haut.periode_imposee = 2.0 * bas.periode_imposee
		haut.espacement = haut.periode_imposee * haut.vitesse
		haut.rampes = [0.0, haut.rampes[1]]


func _poser(D: Dictionary) -> void:
	var a: Vector2 = monde(float(D["aval"][0]), float(D["aval"][1]))
	var b: Vector2 = monde(float(D["amont"][0]), float(D["amont"][1]))
	var a0: Vector2 = a                       # gares des données (avant tout report)
	var b0: Vector2 = b
	# téléphérique de la Grande Motte : il part de sa gare existante, à côté
	# de la gare du funiculaire (le point OSM est 24 m plus au sud ; une
	# seconde gare y était construite — retour d'utilisateur, 24/10/2026)
	var quai_tph: Dictionary = {}
	if String(D["cle"]) == "tph_grande_motte" and gare_amont != null:
		quai_tph = gare_amont.tph_quai()
		var face: Vector2 = Vector2((quai_tph["nez"] as Vector3).x, (quai_tph["nez"] as Vector3).z)
		var sortie: Vector2 = (b - face).normalized()
		a = face + sortie * TphGrandeMotte.Z_NEZ          # nez : avant du quai de la tête en acier
	var dirh: Vector2 = b - a
	var L: float = dirh.length()
	if L < 10.0:
		return
	dirh /= L
	for j in JUMELAGES:
		# gare intermédiaire : chaque tronçon a sa partie, sa poulie à 7 m du coude
		if String(D["cle"]) == j[1]:
			var lh: float = LigneRemontee.L_GARE + 7.0
			a += dirh * lh
			L -= lh
		elif String(D["cle"]) == j[0]:
			var lb: float = LigneRemontee.L_GARE + LigneRemontee.ALLONGE_BAS + 7.0
			b -= dirh * lb
			L -= lb
	var av: float = float(AVANCES_AVAL.get(String(D["cle"]), 0.0))
	if av > 0.0:
		a += dirh * av
		L -= av
	var h0: float = relief.hauteur_sol(a.x, a.y)
	if not quai_tph.is_empty():
		h0 = (quai_tph["nez"] as Vector3).y
	# profil sous l'axe, pris sur le relief AFFICHÉ (pas l'IGN) : pylônes et
	# gares posés sur le sol que l'on voit
	var prof: PackedVector2Array = PackedVector2Array()
	var d: float = 0.0
	while d < L:
		var p: Vector2 = a + dirh * d
		prof.append(Vector2(d, relief.hauteur_sol(p.x, p.y) - h0))
		d += 10.0
	prof.append(Vector2(L, relief.hauteur_sol(b.x, b.y) - h0))
	# chaque gare au plus haut du terrain sous son emprise (quai, poulie,
	# largeur) : sur un versant, la gare amont était enterrée côté pente
	# (retour d'utilisateur, 23/10/2026)
	var lat: Vector2 = Vector2(-dirh.y, dirh.x)
	var demi: float = float(D["voie"]) * 0.5 + 5.0
	var long_g: float = LigneRemontee.l_gare_pour(String(D["famille"])) + float(D["voie"]) * 0.5 + 12.0
	for bout in [[0, a, -1.0], [prof.size() - 1, b, 1.0]]:
		var o: Vector2 = bout[1]
		var haut: float = prof[bout[0]].y
		var t: float = -2.0
		while t <= long_g:
			for x in [-demi, 0.0, demi]:
				var q2: Vector2 = o + dirh * (t * float(bout[2])) + lat * x
				haut = maxf(haut, relief.hauteur_sol(q2.x, q2.y) - h0)
			t += 3.0
		prof[bout[0]] = Vector2(prof[bout[0]].x, haut)
	# rampe d'accès derrière chaque gare (côté portillons) : jusqu'où faut-il
	# aller, en descendant de 10 %, pour retrouver la piste ?
	var bq: float = LigneRemontee.l_gare_pour(String(D["famille"])) + float(D["voie"]) * 0.25 + 8.25
	var rampes: Array = [0.0, 0.0]
	# (télésièges seulement : on monte en cabine à pied, sans portillons ;
	# 40 m au plus, au-delà le terrain plonge trop pour qu'on y arrive)
	for k in (range(2) if String(D["famille"]).begins_with("siege") else []):
		var o2: Vector2 = a if k == 0 else b
		var dirb: Vector2 = -dirh if k == 0 else dirh
		var y_q: float = prof[0 if k == 0 else prof.size() - 1].y
		var t2: float = 0.0
		while t2 < 40.0:
			# sur toute la largeur de la rampe : le terrain le plus bas décide
			var bas: float = INF
			for xl in [-demi, -demi * 0.5, 0.0, demi * 0.5, demi]:
				var q3: Vector2 = o2 + dirb * (bq + t2) + lat * xl
				bas = minf(bas, relief.hauteur_sol(q3.x, q3.y) - h0)
			if bas >= y_q - LigneRemontee.PENTE_RAMPE * t2:
				break
			t2 += 1.0
		rampes[k] = t2
	if not quai_tph.is_empty():
		# quais à leur niveau réel : l'étage du bâtiment à l'aval, le
		# caillebotis au-dessus du sommet à l'amont
		prof[0] = Vector2(0.0, TphGrandeMotte.H_QUAI_AVAL)
		prof[prof.size() - 1] = prof[prof.size() - 1] + Vector2(0.0, TphGrandeMotte.H_QUAI_AMONT)
	var lg: LigneRemontee = Telepherique.new() if String(D["famille"]) == "cabine_tph" else LigneRemontee.new()
	if not quai_tph.is_empty():
		(lg as Telepherique).gare_aval_existante = true
		# coins du bâtiment dans le repère de la ligne (origine au nez, −Z vers l'amont)
		var xf_l: Transform3D = Transform3D(Basis.looking_at(Vector3(dirh.x, 0.0, dirh.y), Vector3.UP), Vector3(a.x, h0, a.y)).affine_inverse()
		var coins: PackedVector2Array = PackedVector2Array()
		for w in quai_tph["coins"]:
			var l3: Vector3 = xf_l * (w as Vector3)
			coins.append(Vector2(l3.x, l3.z))
		(lg as Telepherique).emprise_batiment = coins
	lg.name = String(D["cle"])
	lg.profil = prof
	lg.rampes = rampes
	# sol réel sous la gare (terrassements) : relief affiché, repère de la ligne
	var xf0: Transform3D = Transform3D(Basis.looking_at(Vector3(dirh.x, 0.0, dirh.y), Vector3.UP), Vector3(a.x, h0, a.y))
	lg.relief_trous = relief
	lg.sol_local = func(x: float, z: float) -> float:
		var w: Vector3 = xf0 * Vector3(x, 0.0, z)
		return relief.hauteur_sol(w.x, w.z) - h0
	# pylônes : à leur place au sol (distance des données ramenée à la longueur
	# gare-à-gare des données), puis projetés sur la ligne posée. Avant, la
	# distance était mise à l'échelle de la ligne posée : quand une gare était
	# reportée (Fresse avancé de 24 m à l'intermédiaire, Bollin raccourci, le
	# téléphérique sur sa gare existante), chaque pylône glissait jusqu'à 24 m
	# de sa place, sur un terrain d'une autre altitude (retour d'utilisateur,
	# 25/10/2026 : « t'es sûr que le 13e pylône de Fresse, l'altitude est la bonne ? »)
	var Ld: float = float(D["profil"][D["profil"].size() - 1][0])
	var L0: float = (b0 - a0).length()
	var u0: Vector2 = (b0 - a0) / maxf(L0, 1.0)
	var py: Array = []
	for p in D["pylones"]:
		var q: Dictionary = (p as Dictionary).duplicate()
		var w: Vector2 = a0 + u0 * (float(p["d"]) * L0 / maxf(Ld, 1.0))
		q["d"] = (w - a).dot(dirh)
		if float(q["d"]) < 5.0 or float(q["d"]) > L - 5.0:
			continue                    # tombé dans une gare reportée
		py.append(q)
	lg.pylones = py
	# hauteurs mesurées (traces GPS) : même projection que les pylônes
	var hm: PackedVector2Array = PackedVector2Array()
	for g in D.get("gps", []):
		var wg: Vector2 = a0 + u0 * float(g[0])
		var dg: float = (wg - a).dot(dirh)
		if dg > 0.0 and dg < L:
			hm.append(Vector2(dg, float(g[1])))
	lg.hauteurs_mesurees = hm
	lg.voie = float(D["voie"])
	lg.vitesse = float(D["vitesse"])
	lg.espacement = float(D["espacement"])
	lg.famille = String(D["famille"])
	lg.sens_droite = bool(D["sens_droite"])
	lg.diametre_cable = float(D.get("diametre_cable", 47.0))
	lg.nom_ligne = String(D["nom"])
	lg.constructeur = String(D.get("constructeur", ""))
	lg.annee = int(str(D.get("annee", "0")))
	lg.station = String(D.get("station", ""))
	lg.balanciers_estimes = String(D.get("balanciers", "")) == "estimés"
	lg.quartier = String(D.get("quartier", ""))
	lg.altitude_aval = float(D.get("altitude_aval", 0.0))
	lg.debit = float(D.get("debit", 0.0))
	# repère : origine au sol de la gare aval, −Z local vers l'amont
	var fwd: Vector3 = Vector3(dirh.x, 0.0, dirh.y)
	lg.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(a.x, h0, a.y))
	lg.avec_collisions = true
	lg.progressif = true
	if OS.has_feature("web"):
		lg.budget_ms = 2.5                # construction plus étalée sur iPad
	lg.set_process(false)
	add_child(lg)
	# construite plus tard, quand le skieur approche (_construire_proches)
	lg.construite.connect(func() -> void:
		_portees(lg)
		Cabin.tag_layer(lg, Cabin.LAYER_VOIE)
		_en_cours = null)
	var m: Vector2 = (a + b) * 0.5
	lignes.append([lg, Vector3(m.x, relief.hauteur_sol(m.x, m.y), m.y)])


## Distances de visibilité : véhicules proches seulement, pylônes et câble loin.
func _portees(lg: LigneRemontee) -> void:
	for c in lg.get_children():
		var portee: float = VEHICULES_JUSQUA if c is VehiculeRemontee else PYLONES_JUSQUA
		# pneus, rails et portillons des gares : détails de près seulement
		if not (c is VehiculeRemontee or c is PyloneRemontee) and not String(c.name).begins_with("Gare") \
				and String(c.name) != "Cable" and not (c is StaticBody3D):
			portee = DETAILS_JUSQUA
		var pile: Array = [c]
		while not pile.is_empty():
			var n: Node = pile.pop_back()
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).visibility_range_end = portee
				(n as GeometryInstance3D).visibility_range_end_margin = portee * 0.05
			for k in n.get_children():
				pile.append(k)


func _ready() -> void:
	# après les lignes (véhicules déjà déplacés), avant le skieur (priorité 100)
	process_priority = 50


## Construction à la demande : la ligne non construite la plus proche du
## skieur (à moins de CONSTRUIRE_JUSQUA m), une à la fois, par tranches.
var CONSTRUIRE_JUSQUA: float = 1200.0 if OS.has_feature("web") else 2000.0
## Au-delà, une ligne construite est démontée (mémoire) ; écart avec la
## distance de construction pour ne pas battre.
var DEMOLIR_AU_DELA: float = 2200.0 if OS.has_feature("web") else 3500.0
var _en_cours: LigneRemontee = null


func _construire_proches() -> void:
	if _en_cours != null or skieur == null or not skieur.actif or _sous_terre:
		return
	var p: Vector3 = skieur.global_position
	var best: LigneRemontee = null
	var d_best: float = INF
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if lg.pret or lg.get_meta("lancee", false):
			continue
		# distance au TRACÉ (aval–amont), pas au milieu moins la demi-longueur :
		# celle-ci faisait passer les longues lignes voisines avant le petit
		# téléski au pied duquel on est (Slalom, Snow Park : pas construits
		# en 120 s, banc du 24/10/2026)
		var xf: Transform3D = lg.global_transform
		var a: Vector3 = xf.origin
		var b: Vector3 = xf * Vector3(0, 0, -lg.longueur_h())
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
		var d: float = q.distance_to(Vector2(p.x, p.z))
		if d < CONSTRUIRE_JUSQUA and d < d_best:
			d_best = d
			best = lg
	if best != null:
		_en_cours = best
		best.set_meta("lancee", true)
		best.construire()


var _poubelle: Array = []


## Lignes démontées : leurs nœuds libérés par paquets, 1,5 ms par image au plus.
func _vider_poubelle() -> void:
	var t0: int = Time.get_ticks_usec()
	while not _poubelle.is_empty() and Time.get_ticks_usec() - t0 < 1500:
		var n: Node = _poubelle.pop_back()
		if is_instance_valid(n):
			n.free()


func _process(delta: float) -> void:
	_vider_poubelle()
	_construire_proches()
	_embarquement()
	_t_lod -= delta
	if _t_lod > 0.0:
		return
	_t_lod = 0.25
	# distance au skieur quand il est là (sa caméra le suit), sinon à la caméra
	var p: Vector3
	if skieur != null and skieur.actif:
		p = skieur.global_position
	else:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam == null:
			return
		p = cam.global_position
	# sous terre (trajet en funiculaire, galerie) : rien des remontées n'est
	# visible — tout est caché et figé (le défilement du tunnel n'était pas
	# fluide sur la PWA, retour d'utilisateur, 24/10/2026)
	_sous_terre = relief != null and p.y < relief.hauteur_sol(p.x, p.z) - 6.0 and a_bord.is_empty()
	if _sous_terre:
		if visible:
			visible = false
			for e in lignes:
				(e[0] as LigneRemontee).set_process(false)
		return
	visible = true
	# niveau de détail par ligne, selon la distance à la LIGNE (segment
	# gare aval – gare amont) : véhicules invisibles au-delà de
	# VEHICULES_JUSQUA → ligne figée ; au-delà de 300 m, une image sur
	# trois ; la ligne où l'on est assis, toujours à pleine cadence
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if lg.pret and lg != _en_cours and (a_bord.is_empty() or (a_bord[0] != lg and a_bord[0] != lg.jumelee)) \
				and _distance_ligne(lg, p) > DEMOLIR_AU_DELA \
				and (lg.jumelee == null or _distance_ligne(lg.jumelee, p) > DEMOLIR_AU_DELA):
			lg.demolir(_poubelle)
			lg.set_meta("lancee", false)
			continue
		if not lg.roule:
			continue
		var d: float = _distance_ligne(lg, p)
		var a_bord_ici: bool = not a_bord.is_empty() and a_bord[0] == lg
		# tronçons jumelés : ils tournent ensemble, au même pas (sinon les
		# sièges qui passent de l'un à l'autre se décalent)
		var jm: LigneRemontee = lg.jumelee
		if jm != null and jm.roule:
			d = minf(d, _distance_ligne(jm, p))
			a_bord_ici = a_bord_ici or (not a_bord.is_empty() and a_bord[0] == jm)
			if lg.role == "haut" and not lg._synchro:
				lg.synchroniser()
		elif jm != null:
			lg.set_process(false)          # il attend son jumeau
			continue
		lg.set_process(a_bord_ici or d < VEHICULES_JUSQUA + 50.0)
		lg.pas_lod = 1 if (a_bord_ici or d < 150.0 * _f_lod) else (2 if d < 300.0 * _f_lod else 4)
		lg.details_visibles = d < DETAILS_JUSQUA + 50.0
		lg.collisions_actives = a_bord_ici or d < 120.0
		lg.point_vue = lg.global_transform.affine_inverse() * p
		lg.vue_active = not a_bord_ici


## Distance horizontale de p à l'axe de la ligne (segment entre les nez).
func _distance_ligne(lg: LigneRemontee, p: Vector3) -> float:
	var xf: Transform3D = lg.global_transform
	var a: Vector3 = xf.origin
	var b: Vector3 = xf * Vector3(0, 0, -lg.longueur_h())
	var ab: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var ap: Vector2 = Vector2(p.x - a.x, p.z - a.z)
	var t: float = clampf(ap.dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return (ap - ab * t).length()


# --- monter à bord d'un télésiège -----------------------------------------------------

## Le siège arrivant par derrière « ramasse » le skieur qui attend à la ligne
## d'arrêt : il s'assoit tout seul, se laisse emporter, et se lève à la
## gare d'arrivée. Dans une cabine on entre à pied, portes ouvertes, et
## l'on est assis d'office sur la banquette face à l'amont, porté par la
## cabine comme sur un siège : en physique, le skieur passait au travers du
## plancher dès que la cabine quittait la gare (retour d'utilisateur, 22/10/2026).
func _embarquement() -> void:
	if skieur == null or not skieur.actif:
		return
	if not a_bord.is_empty():
		_suivre_siege()
		return
	if _attente_tk != null:
		_attendre_perche()
		return
	_repos = maxf(0.0, _repos - get_process_delta_time())
	if _repos > 0.0:
		return
	var p: Vector3 = skieur.global_position
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret or not lg.is_processing():
			continue
		if lg.teleski():
			if _prendre_perche(lg, p):
				return
			continue
		if lg.famille.begins_with("cabine"):
			if _entrer_cabine(lg, p):
				return
			continue
		for aval in [true, false]:
			var q: Vector3 = lg.global_transform * lg.point_embarquement(aval)
			if p.distance_to(q) > 6.0:
				continue
			var i: int = lg.vehicule_a_embarquer(aval)
			if i < 0:
				continue
			var v: VehiculeRemontee = lg.vehicule(i)
			var loc: Vector3 = v.global_transform.affine_inverse() * p
			var place0: Vector3 = v.place_assise(0)
			var W: float = 0.50 * v.places + 0.20
			# le siège arrive par derrière : le skieur est devant l'assise
			if absf(loc.x) < W * 0.5 + 0.15 and loc.z > place0.z - 0.6 and loc.z < place0.z + 0.35 \
					and absf(loc.y - place0.y) < 1.2:
				var k: int = clampi(int(floor((absf(loc.x) * signf(loc.x) + W * 0.5 - 0.10) / 0.50)), 0, v.places - 1)
				# le télésiège se prend chaussé (retour d'utilisateur, 23/10/2026) :
				# à pied, on chausse au portillon
				if not skieur.chausse:
					skieur.basculer_ski(true)
				a_bord = [lg, i, k, aval, false]
				skieur.support = null
				skieur.embarque = true
				skieur.asseoir(_cap(v), true)
				_suivre_siege()
				var dest: String = lg.jumelee.nom_ligne if (aval and lg.role == "bas" and lg.traverse(i)) else lg.nom_ligne
				message.emit("Assis — %s" % dest)
				return


## Remontée « courante » pour le poste de commande : celle où l'on est
## assis, sinon celle dont une gare est la plus proche, à moins de 400 m.
func ligne_courante(p: Vector3) -> LigneRemontee:
	if not a_bord.is_empty():
		return a_bord[0]
	var best: LigneRemontee = null
	var dm: float = 400.0
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret:
			continue
		var xf: Transform3D = lg.global_transform
		for d in [0.0, lg.longueur_h()]:
			var g: Vector3 = xf * Vector3(0, lg.terrain(d), -d)
			var dd: float = g.distance_to(p)
			if dd < dm:
				dm = dd
				best = lg
	return best


func _cap(v: Node3D, avant: bool = false) -> float:
	var f: Vector3 = -v.global_transform.basis.z
	return atan2(-f.x, -f.z) + (PI if avant else 0.0)


## Skieur entré dans une cabine en gare : assis sur la banquette d'où l'on
## regarde vers l'amont, à la place la plus proche.
func _entrer_cabine(lg: LigneRemontee, p: Vector3) -> bool:
	for i in range(lg.nombre_vehicules()):
		var zn: String = lg.zone_vehicule(i)
		if zn == "ligne":
			continue
		var v: VehiculeRemontee = lg.vehicule(i)
		var loc: Vector3 = v.global_transform.affine_inverse() * p
		var y_pl: float = v.place_assise(0).y
		var lim: Vector2 = lg.demi_interieur()
		if absf(loc.x) > lim.x or absf(loc.z) > lim.y or loc.y < y_pl - 0.4 or loc.y > y_pl + 1.6:
			continue
		# la cabine roule vers son −Z : en montant (gare aval), la banquette
		# arrière regarde l'amont ; en descendant, la banquette avant
		var avant: bool = zn == "gare_amont"
		var k: int = clampi(int(round(loc.x / 0.40 + 2.5)), 0, 5) if lg.tricable() else clampi(int(round(loc.x / 0.46)) + 2, 0, 4)
		if lg.vaetvient():
			k = clampi(int(round(loc.z / 1.0)) + 2, 0, 4)
		# on monte en cabine à pied : chaussé, on déchausse et les skis vont
		# au porte-skis, sur les vantaux des portes (retour d'utilisateur, 23/10/2026)
		var skis: bool = skieur.chausse
		if skis:
			skieur.basculer_ski()
		v.porte_skis(skis)
		a_bord = [lg, i, k, zn == "gare_aval", avant]
		skieur.support = null
		skieur.embarque = true
		if not lg.vaetvient():
			skieur.asseoir(_cap(v, avant), true)
		else:
			skieur.velocity = Vector3.ZERO          # debout, à la barre
		skieur._skis.visible = false        # skis au porte-skis, ou à ses pieds
		_suivre_siege()
		message.emit(("Skis au porte-skis — assis — %s" if skis else "Assis — %s") % lg.nom_ligne)
		return true
	return false


## Assis dans un siège de Fresse sur le tronçon de Bollin : à la sortie de la
## gare intermédiaire, il continue dans le siège du tronçon haut qui en sort
## au même instant, au même endroit (les deux tronçons sont calés).
func _relais_jumele() -> void:
	var lg: LigneRemontee = a_bord[0]
	var i: int = a_bord[1]
	if lg.role != "bas" or not lg.traverse(i) or lg.jumelee == null:
		return
	var s: float = lg._vehicules[i][1]
	var fin: float = float(lg._zones[1][1])
	var x: float = fposmod(s - fin, lg.longueur_boucle)
	if x > 6.0:
		return                         # pas encore sorti de l'intermédiaire
	var h: LigneRemontee = lg.jumelee
	var sortie: float = float(h._zones[0][1])
	var best: int = -1
	var dmin: float = 8.0
	for j in range(h._vehicules.size()):
		var dx: float = fposmod(float(h._vehicules[j][1]) - sortie, h.longueur_boucle)
		if dx < dmin:
			dmin = dx
			best = j
	if best < 0:
		return
	a_bord = [h, best, a_bord[2], a_bord[3], a_bord[4]]
	h._placer(best)


## Quitter la remontée (aller à une autre depuis la carte) : on lâche la
## perche ou l'on se lève du siège sur place.
func quitter() -> void:
	if _attente_tk != null:
		_attente_tk = null
		if skieur != null:
			skieur.embarque = false
		_repos = 3.0
	if a_bord.is_empty():
		return
	var lg: LigneRemontee = a_bord[0]
	if a_bord.size() > 5:
		lg.vehicule(a_bord[1]).longueur_perche(0.0)
	if skieur != null:
		skieur.embarque = false
		skieur.lever()
		skieur._skis.visible = true
	a_bord = []
	_repos = 3.0


## Téléski : on entre dans le couloir de départ (à pied, on chausse
## d'office, comme au télésiège), on glisse jusqu'au tapis et l'on attend
## la perche — au TKD, le lanceur l'envoie dès qu'on est en place ; aux
## enrouleurs, on prend la suivante qui passe (retour d'utilisateur,
## 25/10/2026 : « impossible d'en prendre un, à pied rien ne se passe »).
var _attente_tk: LigneRemontee = null
var _t_attente: float = 0.0
const RAYON_DEPART: float = 3.5


func _prendre_perche(lg: LigneRemontee, p: Vector3) -> bool:
	var q: Vector3 = lg.global_transform * lg.point_embarquement(true)
	if Vector2(p.x - q.x, p.z - q.z).length() > RAYON_DEPART or absf(p.y - q.y) > 3.0:
		return false
	if lg.regime() < 0.3:
		return false
	if not skieur.chausse:
		skieur.basculer_ski(true)
	skieur.support = null
	skieur.embarque = true
	skieur.velocity = Vector3.ZERO
	skieur._v_ski = Vector3.ZERO
	_attente_tk = lg
	_t_attente = 0.0
	message.emit("Départ — %s : attendez la perche" % lg.nom_ligne)
	return true


func _attendre_perche() -> void:
	var lg: LigneRemontee = _attente_tk
	var dt: float = get_process_delta_time()
	if not is_instance_valid(lg) or not lg.roule:
		_attente_tk = null
		skieur.embarque = false
		return
	_t_attente += dt
	var q: Vector3 = lg.global_transform * lg.point_embarquement(true)
	var p: Vector3 = skieur.global_position
	var h: Vector2 = Vector2(p.x, p.z).move_toward(Vector2(q.x, q.z), 2.5 * dt)
	var y: float = q.y
	if relief != null:
		y = relief.hauteur_sol(h.x, h.y) + 0.02
	p = Vector3(h.x, y, h.y)
	skieur.global_position = p
	skieur.dernier_sol = p
	skieur.velocity = Vector3.ZERO
	skieur._v_ski = Vector3.ZERO
	var f: Vector3 = lg.global_transform.basis * Vector3(0, 0, -1)
	var cap: float = atan2(-f.x, -f.z)
	skieur._visuel.rotation = Vector3(0.0, cap, 0.0)
	skieur._cap = cap
	skieur._cap_ski = cap
	var en_place: bool = Vector2(p.x - q.x, p.z - q.z).length() < 0.3
	if en_place:
		lg.lancer_perche()
		var i: int = lg.vehicule_a_embarquer(true)
		if i >= 0:
			_attente_tk = null
			a_bord = [lg, i, 0, true, false, "perche"]
			_suivre_perche()
			message.emit("Perche prise — %s" % lg.nom_ligne)
			return
	if _t_attente > 90.0:
		_attente_tk = null
		skieur.embarque = false
		_repos = 5.0
		message.emit("Pas de perche — %s est-il en marche ?" % lg.nom_ligne)


func _suivre_perche() -> void:
	var lg: LigneRemontee = a_bord[0]
	var i: int = a_bord[1]
	var v: VehiculeRemontee = lg.vehicule(i)
	var pc: Vector3 = v.global_position
	var arriere: Vector3 = v.global_transform.basis.z
	arriere.y = 0.0
	arriere = arriere.normalized()
	# les skis sur la trace, 0,6 m derrière la pince : sol sous l'axe de la
	# ligne (profil du relief, quais des gares compris)
	var pos: Vector3 = pc + arriere * 0.6
	var loc: Vector3 = lg.global_transform.affine_inverse() * pos
	var yl: float = lg.terrain(clampf(-loc.z, 0.0, lg.longueur_h()))
	var y: float = (lg.global_transform * Vector3(loc.x, yl, loc.z)).y
	if relief != null:
		# en ligne, le relief sous les skis ; aux gares, le quai s'il est plus haut
		# (pas de quai aux téléskis : la neige partout)
		y = relief.hauteur_sol(pos.x, pos.z)
	pos.y = y + 0.02
	skieur.global_position = pos
	skieur.dernier_sol = pos
	skieur.velocity = Vector3.ZERO
	var cap: float = _cap(v)
	skieur._visuel.rotation = Vector3(0.0, cap, 0.0)
	skieur._cap = cap
	v.longueur_perche(pc.y - (y + 0.85))
	# en haut, on lâche la perche avant la poulie et l'on s'écarte en
	# traversée lente, sans élan vers l'avant : lancé à 2 m/s vers l'avant, au
	# 3000 il passait la crête et dévalait dans le vallon de l'Iseran sans
	# pouvoir prendre le tunnel (retour d'utilisateur, 25/10/2026) ; lâché à
	# l'arrêt plus bas, il repartait en arrière dans la pente
	var arr: Array = lg.arrivee(i)
	if not arr.is_empty() and not bool(arr[0]):
		v.longueur_perche(0.0)
		skieur.embarque = false
		var avant: Vector3 = -arriere
		var dehors: Vector3 = lg.global_transform.basis.x * signf(lg._x_brin(true))
		# à l'arrêt, skis EN TRAVERS de la pente (les carres le retiennent),
		# tournés du côté de la sortie ; chasse-neige tant qu'il ne commande rien
		var ns: Vector3 = relief.normale_sol(skieur.global_position.x, skieur.global_position.z) if relief != null else Vector3.UP
		var chute: Vector3 = Vector3(ns.x, 0.0, ns.z)
		var vit: Vector3 = dehors
		if chute.length() > 0.05:
			var trav: Vector3 = Vector3(-chute.z, 0.0, chute.x).normalized()
			vit = trav if trav.dot(dehors) >= 0.0 else -trav
		skieur._v_ski = Vector3.ZERO
		skieur.frein_auto = 4.0
		skieur._cap_ski = atan2(-vit.x, -vit.z)
		skieur._cap = skieur._cap_ski
		skieur.cam_yaw = skieur._cap_ski
		message.emit("Perche lâchée — %s" % lg.nom_ligne)
		a_bord = []
		_repos = 4.0


func _suivre_siege() -> void:
	if a_bord.size() > 5:
		_suivre_perche()
		return
	_relais_jumele()
	var lg: LigneRemontee = a_bord[0]
	var i: int = a_bord[1]
	var v: VehiculeRemontee = lg.vehicule(i)
	skieur.global_position = v.vers_monde(v.place_assise(a_bord[2], a_bord[4]))
	skieur.velocity = Vector3.ZERO
	var cap: float = _cap(v, a_bord[4])
	skieur._visuel.rotation = Vector3(0.0, cap, 0.0)
	skieur._visuel.position = Vector3(sin(cap), 0.0, cos(cap)) * SkieurJoueur.RECUL_ASSIS if skieur.assis else Vector3.ZERO
	# arrivée à l'autre gare : il se lève sur la rampe, devant le siège ;
	# en cabine, seulement portes ouvertes (il était éjecté avant —
	# retour d'utilisateur, 23/10/2026)
	var arr: Array = lg.arrivee(i) if not v.cabine else lg.arrivee_cabine(i)
	if not arr.is_empty() and bool(arr[0]) != bool(a_bord[3]):
		var aval_arr: bool = arr[0]
		var y_quai: float = (lg.global_transform * Vector3(0, lg.terrain(0.0 if aval_arr else lg.longueur_h()), 0)).y
		# hors du couloir des sièges (2,2 m à l'extérieur) : le siège continue,
		# remonte et contourne la poulie — posé devant lui, le skieur était
		# rattrapé, porté par l'assise et rassis pour la descente
		var loc: Vector3 = lg.global_transform.affine_inverse() * v.vers_monde(v.place_assise(a_bord[2], a_bord[4]))
		var cote: float = signf(lg._x_brin(not aval_arr))        # extérieur du brin d'arrivée
		if v.cabine:
			# portes ouvertes : il se lève dans la cabine et sort à pied
			# (retour d'utilisateur, 23/10/2026) ; skis rendus, à la main
			v.porte_skis(false)
			skieur.embarque = false
			skieur.lever()
			var pied: Vector3 = v.vers_monde(v.place_assise(a_bord[2], a_bord[4])) + Vector3(0, 0.05, 0)
			skieur.global_position = pied
			skieur.dernier_sol = pied
			skieur.support = null
			skieur._skis.visible = true
			message.emit("Portes ouvertes — %s" % lg.nom_ligne)
			a_bord = []
			_repos = 8.0          # le temps de sortir avant d'être rassis
			return
		var glisse: bool = skieur.chausse and not v.cabine
		if not glisse:
			loc.x = cote * (lg.voie * 0.5 + 2.2)
		var pos: Vector3 = lg.global_transform * loc
		pos.y = y_quai + (0.02 if glisse else 0.15)
		skieur.embarque = false
		skieur.lever()
		skieur.global_position = pos
		skieur.dernier_sol = pos
		skieur.support = null
		if glisse:
			# chaussé : il se lève à sa place et glisse en avant vers
			# l'extérieur, sur la pente de débarquement, pendant que le
			# siège continue et tourne autour de la poulie (retour
			# d'utilisateur, 23/10/2026 : « se lever du siège et glisser
			# doucement avec la petite descente qui va bien »)
			var avant: Vector3 = -v.global_transform.basis.z
			avant.y = 0.0
			avant = avant.normalized()
			var dehors: Vector3 = lg.global_transform.basis.x * cote
			var vit: Vector3 = avant * 2.2 + dehors * 1.6
			skieur._v_ski = vit
			skieur._cap_ski = atan2(-vit.x, -vit.z)
			skieur._cap = skieur._cap_ski
			skieur.cam_yaw = skieur._cap_ski
		message.emit("Arrivé — %s" % lg.nom_ligne)
		a_bord = []
		_repos = 6.0
