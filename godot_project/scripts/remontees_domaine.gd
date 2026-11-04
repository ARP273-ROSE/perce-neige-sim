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
const GALETS_JUSQUA: float = 150.0
const PORTEES_PIECES_PYLONE: Dictionary = {
	"remontee_plaque_bleue": 200.0, "remontee_blanc_plaque": 200.0,
	"remontee_caillebotis": 300.0, "remontee_mousse_rouge": 300.0,
	"remontee_beton": 500.0, "remontee_acier_noir": 500.0,
}
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
## Cabine dont les portes viennent de s'ouvrir : [ligne, véhicule, gare d'arrivée = aval].
## S'il y reste quand elle repart, il se rassoit (il restait debout, le temps d'attente
## d'après débarquement passant après le départ — retour d'utilisateur, 02/11/2026).
var _reste_cabine: Array = []
const TSF_DEBUTANTS: Array = ["tsf4_rosset", "tsf3_panoramic", "tsf4_village", "tsf4_almes", "tsf4_cema"]
## Siège : [ligne, instant d'arrivée] pour reconnaître qui reprend aussitôt le siège en sens inverse.
var _arrivee_siege: Array = []
var _sous_terre: bool = false    # caméra sous terre (funiculaire) : remontées cachées
var _f_lod: float = 0.6 if OS.has_feature("web") else 1.0     # distances du niveau de détail
## Niveau de détail des remontées (0 = tout, 2 = minimum), posé par le
## PerfManager quand c'est le fil principal ou le fil de rendu qui sature :
## portées plus courtes, lignes lointaines simulées moins souvent.
var niveau_detail: int = 0
var _portees_base: Array = []


## PC à carte intégrée, dernier cran du régulateur : portées de la PWA.
## Véhicules plus loin au cran 0 du PC (1 400 m contre 700) : suivi du régulateur,
## appliqué par tranches comme tout changement de détail.
const VEHICULES_CRAN_0: float = 1400.0
const VEHICULES_PC: float = 700.0
var _portee_cran_0: bool = false


func _suivre_cran() -> void:
	if OS.has_feature("web"):
		return
	var oui: bool = PerfManager.cran_courant <= 0 and not _portees_pc_reduites
	if oui == _portee_cran_0:
		return
	_portee_cran_0 = oui
	if _portees_base.is_empty():
		_portees_base = [VEHICULES_JUSQUA, DETAILS_JUSQUA, _f_lod]
	_portees_base[0] = VEHICULES_CRAN_0 if oui else VEHICULES_PC
	var n: int = niveau_detail
	niveau_detail = -1
	set_niveau_detail(n)


var _portees_pc_reduites: bool = false


func set_portees_reduites(oui: bool) -> void:
	_portees_pc_reduites = oui
	_portee_cran_0 = false
	CONSTRUIRE_JUSQUA = 1200.0 if oui else 2000.0
	DEMOLIR_AU_DELA = 2200.0 if oui else 3500.0
	# les portées de base : set_niveau_detail en repart, à n'importe quel niveau
	var f_lod: float = float(_portees_base[2]) if not _portees_base.is_empty() else _f_lod
	_portees_base = [450.0 if oui else 700.0, 180.0 if oui else 250.0, f_lod]
	var n: int = 2 if oui else niveau_detail
	niveau_detail = -1
	set_niveau_detail(n)


## Sous terre, tout est caché : ligne par ligne, la plus proche montrée en premier. Le domaine
## entier d'un coup prenait 48 ms en sortant du tunnel, 24 ms en y entrant (relevé 4K, 02/11/2026).
var _lignes_montrees: bool = true
var _file_visibilite: Array = []
const BUDGET_VISIBILITE_US: int = 1500


func _montrer_lignes(oui: bool, p: Vector3) -> void:
	_lignes_montrees = oui
	_file_visibilite.clear()
	for c in get_children():
		if c is Node3D and (c as Node3D).visible != oui:
			_file_visibilite.append(c)
	# (file lue par la fin : la plus lointaine au début)
	_file_visibilite.sort_custom(func(a, b): return (a as Node3D).global_position.distance_squared_to(p) > (b as Node3D).global_position.distance_squared_to(p))


func _avancer_visibilite() -> void:
	var t0: int = Time.get_ticks_usec()
	while not _file_visibilite.is_empty() and Time.get_ticks_usec() - t0 < BUDGET_VISIBILITE_US:
		var n: Variant = _file_visibilite.pop_back()
		if is_instance_valid(n):
			(n as Node3D).visible = _lignes_montrees


var _portees_a_revoir: Array = []
var _file_portees: Array = []
const BUDGET_PORTEES_US: int = 1500


func _revoir_portees() -> void:
	if _portees_a_revoir.is_empty() and _file_portees.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < BUDGET_PORTEES_US:
		if _file_portees.is_empty():
			if _portees_a_revoir.is_empty():
				return
			var lg_p: Variant = _portees_a_revoir.pop_back()
			if is_instance_valid(lg_p):
				_portees_amorce(lg_p, _file_portees)
				(lg_p as LigneRemontee).regler_portee_vehicules(VEHICULES_JUSQUA)
			continue
		var e: Array = _file_portees.pop_back()
		if is_instance_valid(e[0]) and is_instance_valid(e[1]):
			_portee_noeud(e, _file_portees)


func set_niveau_detail(n: int) -> void:
	n = clampi(n, 0, 2)
	if n == niveau_detail:
		return
	if _portees_base.is_empty():
		_portees_base = [VEHICULES_JUSQUA, DETAILS_JUSQUA, _f_lod]
	niveau_detail = n
	VEHICULES_JUSQUA = float(_portees_base[0]) * [1.0, 0.7, 0.5][n]
	DETAILS_JUSQUA = float(_portees_base[1]) * [1.0, 0.7, 0.5][n]
	_f_lod = float(_portees_base[2]) * [1.0, 0.75, 0.5][n]
	# par petites tranches : toutes les lignes d'un coup faisaient une image de 72 à 103 ms à
	# chaque changement de détail, et une ligne seule jusqu'à 26 ms (relevé 4K, 02/11/2026)
	_portees_a_revoir.clear()
	_file_portees.clear()
	for e in lignes:
		if (e[0] as LigneRemontee).pret:
			_portees_a_revoir.append(e[0])
signal message(texte: String)
## Pique sarcastique (PiquesRemontees) : événement, remontée.
signal pique(evt: String, lg: LigneRemontee)


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
## Gares amont reculées vers l'aval (m) : la gare du haut de Fontaine Froide
## était dans le bâtiment de l'Olympique à Bellevarde (retour d'utilisateur,
## 27/10/2026 ; emprises : 3S x 4059-4103 / z 983-1009, Fontaine Froide
## z 987-1020).
## Distance au nez d'un pylône dont la position tombe dans une gare déplacée.
const PYLONE_SORTIE_GARE: float = 12.0
const RECULS_AMONT: Dictionary = {"tsd6_fontaine_froide": 28.0, "tcd8_brevieres": 32.0}
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
	# hauteur précalculée (precalcul_geometrie.gd), retrouvée par la position
	for e in lg.get_meta("h_croisements", []):
		if absf(float(e[0]) - d) < 1.0:
			n["h"] = float(e[1])
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


## Hauteurs des pylônes sur le relief fin (precalcul_geometrie.gd sur ce sol-là), par-dessus
## celles des données, ligne par ligne. Suit le relief chargé, jamais le cran courant : le
## régulateur peut changer de cran sans que le câble bouge. Sans relief fin ou sans fichier :
## les hauteurs des données.
const GEOMETRIE_FIN: String = "res://data/remontees/geometrie_fin.json"
var _geo_fin: Variant = null
static var sans_geometrie_fin: bool = false    # (l'outil de précalcul part des hauteurs des données)


func _geometrie_fin() -> Dictionary:
	if _geo_fin == null:
		_geo_fin = {}
		if not sans_geometrie_fin and relief != null and relief.fin != null and FileAccess.file_exists(GEOMETRIE_FIN):
			var lu: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRIE_FIN))
			if lu is Dictionary:
				_geo_fin = lu
	return _geo_fin


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
	var rc: float = float(RECULS_AMONT.get(String(D["cle"]), 0.0))
	if rc > 0.0:
		b -= dirh * rc
		L -= rc
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
	# (sous le QUAI et la poulie seulement : en comptant aussi 12 m d'aire
	# d'attente derrière et 5 m de chaque côté, une gare sur un versant était
	# perchée sur des terrassements immenses — retour d'utilisateur, 27/10/2026 :
	# « terrassements surdimensionnés »)
	var lat: Vector2 = Vector2(-dirh.y, dirh.x)
	var demi: float = float(D["voie"]) * 0.5 + 1.5
	var long_g: float = LigneRemontee.l_gare_pour(String(D["famille"])) + 2.0
	var demi_r: float = float(D["voie"]) * 0.5 + 5.0
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
			for xl in [-demi_r, -demi_r * 0.5, 0.0, demi_r * 0.5, demi_r]:
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
	# 4 galets au moins : télécabines et télésièges, sauf les fixes pour débutants ;
	# téléskis non concernés (retour d'utilisateur, 02/11/2026)
	var cle_l: String = String(D["cle"])
	var mini_galets: bool = cle_l.begins_with("tcd") or cle_l.begins_with("tsd") \
			or (cle_l.begins_with("tsf") and not cle_l in TSF_DEBUTANTS)
	var fines: Dictionary = {}
	var croisements_fins: Array = []
	for e_f in _geometrie_fin().get(cle_l, []):
		if (e_f as Dictionary).has("k"):
			fines[int(e_f["k"])] = float(e_f["h"])
		else:
			croisements_fins.append([float(e_f["croisement_d"]), float(e_f["h"])])
	var reportes_aval: int = 0
	for kp in range((D["pylones"] as Array).size()):
		var p: Dictionary = D["pylones"][kp]
		var q: Dictionary = p.duplicate()
		q["k"] = kp                     # (rang dans les données : géométrie précalculée)
		if fines.has(kp):
			q["h"] = float(fines[kp])
		if mini_galets:
			for sens in ["montee", "descente"]:
				if q.has(sens):
					q[sens] = PyloneRemontee.compo_mini(q[sens])
		var w: Vector2 = a0 + u0 * (float(p["d"]) * L0 / maxf(Ld, 1.0))
		q["d"] = (w - a).dot(dirh)
		# tombé dans une gare reportée : gardé juste au sortir de celle-ci, sinon le pylône manque et tout
		# le schéma de la ligne glisse d'un cran (retour d'utilisateur, 04/11/2026 : P1 du Vallon)
		if float(q["d"]) < PYLONE_SORTIE_GARE:
			q["d"] = PYLONE_SORTIE_GARE + 12.0 * reportes_aval
			reportes_aval += 1
		elif float(q["d"]) > L - PYLONE_SORTIE_GARE:
			q["d"] = L - PYLONE_SORTIE_GARE
		py.append(q)
	# (plusieurs reportés côté amont : espacés depuis le dernier)
	for ip in range(py.size() - 2, -1, -1):
		if float(py[ip]["d"]) > float(py[ip + 1]["d"]) - 12.0 and float(py[ip + 1]["d"]) >= L - PYLONE_SORTIE_GARE - 60.0:
			py[ip]["d"] = float(py[ip + 1]["d"]) - 12.0
	lg.pylones = py
	# hauteurs mesurées (traces GPS) : même projection que les pylônes
	var hm: PackedVector2Array = PackedVector2Array()
	for g in D.get("gps", []):
		var wg: Vector2 = a0 + u0 * float(g[0])
		var dg: float = (wg - a).dot(dirh)
		if dg > 0.0 and dg < L:
			hm.append(Vector2(dg, float(g[1])))
	lg.hauteurs_mesurees = hm
	lg.set_meta("h_croisements", croisements_fins if not croisements_fins.is_empty() else D.get("h_croisements", []))
	var ru: PackedFloat32Array = PackedFloat32Array()
	for dr in D.get("ruisseaux", []):
		var wr: Vector2 = a0 + u0 * (float(dr) * L0 / maxf(Ld, 1.0))
		var drl: float = (wr - a).dot(dirh)
		if drl > 0.0 and drl < L:
			ru.append(drl)
	lg.ruisseaux = ru
	lg.voie = float(D["voie"])
	lg.vitesse = float(D["vitesse"])
	lg.espacement = float(D["espacement"])
	lg.famille = String(D["famille"])
	lg.sens_droite = bool(D["sens_droite"])
	lg.numeros_inverses = bool(D.get("numeros_inverses", false))
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
	# construite sur un autre fil : portées et couche posées sur le contenu
	# avant son entrée dans la scène, sur ce fil-là (sur le fil principal, ces
	# milliers d'appels au rendu coûtaient 15 à 35 ms d'un bloc)
	lg.prepa_contenu = func(racine: Node) -> void:
		_portees(racine)
		Cabin.tag_layer(racine, Cabin.LAYER_VOIE)
	lg.construite.connect(func() -> void:
		if lg.contenu_prepare:
			for c in lg.get_children():
				if c is MultiMeshInstance3D:           # (véhicules lointains, posés à la fin)
					Cabin.tag_layer(c, Cabin.LAYER_VOIE)
		else:
			_portees(lg)
			Cabin.tag_layer(lg, Cabin.LAYER_VOIE)
		_en_cours = null)
	var m: Vector2 = (a + b) * 0.5
	lignes.append([lg, Vector3(m.x, relief.hauteur_sol(m.x, m.y), m.y)])


## Distances de visibilité : véhicules proches seulement, pylônes et câble loin.
## (`racine` : la ligne, ou le contenu en construction hors de la scène)
func _portees(racine: Node) -> void:
	var file: Array = []
	_portees_amorce(racine, file)
	while not file.is_empty():
		_portee_noeud(file.pop_back(), file)


func _portees_amorce(racine: Node, file: Array) -> void:
	for c in racine.get_children():
		# (véhicules lointains en MultiMesh : leur portée est gérée par le noyau,
		# instance par instance — mesurée d'ici, depuis la gare aval, une portée
		# les faisait disparaître à 250 m de la gare)
		if c is MultiMeshInstance3D and (String(c.name).begins_with("VehiculesLoin") or String(c.name).begins_with("VehiculesLod")):
			continue
		if String(c.name).begins_with("PyloneLod_"):
			continue
		var portee: float = VEHICULES_JUSQUA if c is VehiculeRemontee else PYLONES_JUSQUA
		if c.has_meta("lod_loin"):
			portee = VehiculesLod.PYLONE_DES
		# pneus, rails et portillons des gares : détails de près seulement
		# (les pylônes en treillis du 3S ne sont pas des PyloneRemontee : ils
		# disparaissaient à 250 m — retour d'utilisateur, 26/10/2026 : « le pylône
		# qui se matérialise 20 s avant d'y arriver »)
		if not (c is VehiculeRemontee or c is PyloneRemontee or c is PyloneTreillis) and not String(c.name).begins_with("Gare") \
				and String(c.name) != "Cable" and not (c is StaticBody3D):
			portee = DETAILS_JUSQUA
		file.append([c, c, portee])


## Une pièce : sa portée, puis ses enfants dans la file.
func _portee_noeud(e: Array, file: Array) -> void:
	var c: Node = e[0]
	var n: Node = e[1]
	var pn: float = e[2]
	# pièces de détail des véhicules, plaques des pylônes : de près seulement
	if n.has_meta("detail") or n is Label3D:
		pn = minf(pn, DETAILS_JUSQUA)
	# paires de galets des pylônes (un objet chacune, pour s'animer au
	# passage des pinces) : 7 800 objets visibles jusqu'à 3 km au pied
	# des pistes (relevés de l'iPad du 27/10/2026) — à 150 m un galet ne
	# se distingue plus
	if String(n.name).begins_with("Paire"):
		pn = minf(pn, GALETS_JUSQUA)
	# pylônes : au loin, le fût et la tête seulement — plaques, caillebotis,
	# massif et petites pièces de détail (1 850 objets pour 278 pylônes
	# jusqu'à 3 km, un par matériau)
	if c is PyloneRemontee and n is MeshInstance3D and (n as MeshInstance3D).mesh != null \
			and (n as MeshInstance3D).mesh.get_surface_count() > 0:
		var mt: Material = (n as MeshInstance3D).mesh.surface_get_material(0)
		if mt != null and PORTEES_PIECES_PYLONE.has(mt.resource_name):
			pn = minf(pn, float(PORTEES_PIECES_PYLONE[mt.resource_name]))
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = pn
		(n as GeometryInstance3D).visibility_range_end_margin = pn * 0.05
	for k in n.get_children():
		file.append([c, k, pn])


func _ready() -> void:
	if not OS.has_feature("web") and PerfManager.cran_courant >= PerfManager.CRAN_MAX_PC:
		set_portees_reduites(true)
	if OS.has_feature("web"):
		# (l'iPad se présente en Mac : on le reconnaît au tactile. WebGL y a lâché à 265 Mo, puis à 199 Mo
		# en secours 1, au Lac de Tignes, le 03/11/2026)
		var telephone: bool = bool(JavaScriptBridge.eval("/Mobile|Android/.test(navigator.userAgent)||(/Macintosh/.test(navigator.userAgent)&&navigator.maxTouchPoints>1)", true))
		# (sommets soudés et tampons 2D réduits, 03/11/2026 : base skieur ~50 Mo au lieu de 145 ; à budget
		# égal, on construisait davantage de lignes, donc davantage de tampons)
		_budget_tampons_mo = [100.0 if telephone else 300.0, 75.0 if telephone else 130.0, 60.0 if telephone else 90.0][clampi(PerfManager.secours_web, 0, 2)]
		if telephone and PerfManager.secours_web > 0:
			# (secours 2 : seule la ligne où l'on arrive ; perte à 160 Mo le 03/11/2026)
			_budget_proche = 250.0 if PerfManager.secours_web == 1 else 120.0
	if PerfManager.secours_web > 0:
		var fort: bool = PerfManager.secours_web >= 2 or _budget_proche < BUDGET_PROCHE
		CONSTRUIRE_JUSQUA = 500.0 if fort else 800.0
		DEMOLIR_AU_DELA = 900.0 if fort else 1400.0
		VEHICULES_JUSQUA = 200.0 if fort else 300.0
		DETAILS_JUSQUA = 80.0 if fort else 120.0
	# après les lignes (véhicules déjà déplacés), avant le skieur (priorité 100)
	process_priority = 50


## Construction à la demande : la ligne non construite la plus proche du
## skieur (à moins de CONSTRUIRE_JUSQUA m), une à la fois, par tranches.
var CONSTRUIRE_JUSQUA: float = 1200.0 if OS.has_feature("web") else 2000.0
## Au-delà, une ligne construite est démontée (mémoire) ; écart avec la
## distance de construction pour ne pas battre.
var DEMOLIR_AU_DELA: float = 2200.0 if OS.has_feature("web") else 3500.0
## PWA : plafond des tampons de la carte graphique. Sur téléphone Android, WebGL
## s'est perdu à 325 Mo (47 775 tampons) après 368 s (02/11/2026) ; en un même lieu,
## sans bouger, le total monte en 200 s jusqu'à 285 Mo puis ne bouge plus (mesure
## à 824×384) : c'est le nombre de lignes construites, pas une fuite.
var _budget_tampons_mo: float = 0.0
const BUDGET_PROCHE: float = 400.0
var _budget_proche: float = BUDGET_PROCHE
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
		# (tronçons jumelés : l'un ne tourne pas sans l'autre, construits ensemble ; l'embarquement est en bas)
		if lg.jumelee != null and _a_cuit(lg):
			d = minf(d, _distance_ligne(lg.jumelee, p))
		if d < _construire_jusqua(lg) and d < d_best:
			d_best = d
			best = lg
	if best != null and _budget_tampons_mo > 0.0 \
			and Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0 > _budget_tampons_mo:
		# budget atteint : on ne construit plus que la ligne où l'on arrive,
		# en démontant d'abord la plus lointaine
		if d_best > _budget_proche or not _poubelle.is_empty() or _faire_place(p, d_best):
			return
	if best != null:
		_en_cours = best
		best.set_meta("lancee", true)
		best.construire()


## Démonte la ligne construite la plus lointaine, à 200 m au moins au-delà de
## d_min ; faux s'il n'y en a pas (la ligne proche passe alors quand même).
func _faire_place(p: Vector3, d_min: float) -> bool:
	var loin: LigneRemontee = null
	var d_loin: float = d_min + 200.0
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret or lg == _en_cours or (not a_bord.is_empty() and (a_bord[0] == lg or a_bord[0] == lg.jumelee)):
			continue
		var d: float = _distance_ligne(lg, p)
		if lg.jumelee != null:
			d = minf(d, _distance_ligne(lg.jumelee, p))
		if d > d_loin:
			d_loin = d
			loin = lg
	if loin == null:
		return false
	loin.demolir(_poubelle)
	loin.set_meta("lancee", false)
	return true


var _poubelle: Array = []


## Lignes démontées : leurs nœuds libérés par paquets, 1,5 ms par image au plus.
func _vider_poubelle() -> void:
	var t0: int = Time.get_ticks_usec()
	while not _poubelle.is_empty() and Time.get_ticks_usec() - t0 < 1500:
		# (sans type : un nœud déjà libéré avec son parent ferait une erreur dès l'affectation)
		var n: Variant = _poubelle.pop_back()
		if is_instance_valid(n):
			(n as Node).free()


# --- lignes cuites : vues de loin sans nœud --------------------------------------
## De loin, le fichier écrit par cuisson_ligne.gd (LigneCuite) ; de près, la ligne construite, seule à
## porter le jeu : collisions, embarquement, portes. Une ligne cuite reste « non construite » pour tout
## le reste. Sans fichier, ou sans --cuit : les seuils habituels.
const CUIT_PROCHE: float = 450.0
const CUIT_DEMOLIR: float = 650.0
## PWA : la mémoire compte, une ligne construite libère sa version cuite, reprise avant la démolition
## (rechargée au-delà de CUIT_RECHARGER, encore cachée tant que la ligne construite est là).
const CUIT_LIBERER: float = 500.0
const CUIT_RECHARGER: float = 560.0
static var dossier_cuites: String = "user://cuites"
var _cuit_actif: bool = "--cuit" in OS.get_cmdline_user_args() or OS.has_feature("web")
var _cuit_http: HTTPRequest = null
var _cuit_attente: bool = false
var _fichiers_cuits: Dictionary = {}
var _cuites: Dictionary = {}                # clé → LigneCuite posée
var _cuit_tache: int = -1
var _cuit_en_cours: LigneCuite = null
var _cuit_ligne: LigneRemontee = null
var _cuit_scenario: RID
var _t_cuit: float = 0.0
var _t_cuit_veh: float = 0.0
var _t_cuit_dist: float = 0.0
var _cuit_sous_terre: bool = false


var _communs_faits: bool = false


func _preparer_communs() -> void:
	_communs_faits = true
	var t0: int = Time.get_ticks_usec()
	var n: int = LigneCuite.preparer_communs(dossier_cuites, OS.has_feature("web"))
	print("[Cuites] %d matériaux préparés en %.1f ms" % [n, (Time.get_ticks_usec() - t0) / 1000.0])


func _a_cuit(lg: LigneRemontee) -> bool:
	if not _cuit_actif:
		return false
	var nom: String = String(lg.name)
	if OS.has_feature("web"):
		return _fichiers_cuits.get(nom, true)     # (sur le serveur ; faux dès qu'un téléchargement échoue)
	if not _fichiers_cuits.has(nom):
		_fichiers_cuits[nom] = FileAccess.file_exists(LigneCuite.chemin(dossier_cuites, nom, OS.has_feature("web")))
	return _fichiers_cuits[nom]


func _construire_jusqua(lg: LigneRemontee) -> float:
	return minf(CUIT_PROCHE, CONSTRUIRE_JUSQUA) if _a_cuit(lg) else CONSTRUIRE_JUSQUA


func _demolir_au_dela(lg: LigneRemontee) -> float:
	return minf(CUIT_DEMOLIR, DEMOLIR_AU_DELA) if _a_cuit(lg) else DEMOLIR_AU_DELA


func _point_cuit() -> Variant:
	if skieur != null and skieur.actif:
		return skieur.global_position
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.global_position if cam != null else null


## Une pose à la fois, sur un fil de travail ; montrées tant que la ligne construite n'est pas prête.
func _gerer_cuites(delta: float) -> void:
	if not _cuit_actif:
		return
	if not _communs_faits:
		_preparer_communs()
	if _cuit_tache >= 0 and WorkerThreadPool.is_task_completed(_cuit_tache):
		WorkerThreadPool.wait_for_task_completion(_cuit_tache)
		_cuit_tache = -1
		if _cuit_en_cours != null and _cuit_en_cours.cle != "":
			_cuites[_cuit_en_cours.cle] = _cuit_en_cours
		_cuit_en_cours = null
	var pv: Variant = _point_cuit()
	if pv == null:
		return
	var p: Vector3 = pv
	_t_cuit_veh += delta
	var bouge: bool = _t_cuit_veh >= 0.066
	var dt_veh: float = _t_cuit_veh
	if bouge:
		_t_cuit_veh = 0.0
	var montrer_tout: bool = not _sous_terre
	for e in lignes:
		var lg: LigneRemontee = e[0]
		var nom: String = String(lg.name)
		if not _cuites.has(nom):
			continue
		var lc: LigneCuite = _cuites[nom]
		lc.montrer(montrer_tout and not lg.pret)
		if bouge and montrer_tout and not lg.pret and _distance_ligne(lg, p) < VEHICULES_JUSQUA + 50.0:
			lc.avancer(dt_veh)
	_t_cuit_dist -= delta
	if _t_cuit_dist > 0.0:
		return
	_t_cuit_dist = 0.25
	if _cuit_tache >= 0 or _cuit_attente:
		return
	var web: bool = OS.has_feature("web")
	var best: LigneRemontee = null
	var d_best: float = INF
	for e in lignes:
		var lg: LigneRemontee = e[0]
		var nom: String = String(lg.name)
		if not _a_cuit(lg):
			continue
		var d: float = _distance_ligne(lg, p)
		if _cuites.has(nom):
			if d > DEMOLIR_AU_DELA or (web and lg.pret and d < CUIT_LIBERER):
				(_cuites[nom] as LigneCuite).liberer()
				_cuites.erase(nom)
		elif d < CONSTRUIRE_JUSQUA and d < d_best and (not web or not lg.pret or d > CUIT_RECHARGER):
			d_best = d
			best = lg
	if best != null:
		_cuit_en_cours = LigneCuite.new()
		_cuit_ligne = best
		_cuit_scenario = get_world_3d().scenario
		_cuit_en_cours.preparer_chemin(LigneCuite.chemin(dossier_cuites, String(best.name), OS.has_feature("web")))
		if OS.has_feature("web"):
			_telecharger_cuite(String(best.name))
		elif LigneRemontee._fil_possible():
			_cuit_tache = WorkerThreadPool.add_task(_poser_cuite, false, "ligne cuite")
		else:
			# (PWA sans fils : d'un bloc sur le fil principal, une ligne à la fois, 25 + 22 ms à Tovière sous
			# WebKit. Bancs sans écran aussi : leur rendu factice ne crée pas de maillages depuis un autre fil)
			_cuit_en_cours.charger(_cuit_scenario, false)
			if _cuit_en_cours.cle != "":
				_cuites[_cuit_en_cours.cle] = _cuit_en_cours
			_cuit_en_cours = null


## PWA : le fichier vient du serveur, une ligne à la fois, à la version près ; si ça échoue (hors
## ligne, fichier absent) la ligne reprend les seuils de construction habituels.
func _telecharger_cuite(nom: String) -> void:
	if _cuit_http == null:
		_cuit_http = HTTPRequest.new()
		add_child(_cuit_http)
		_cuit_http.request_completed.connect(_cuite_recue)
	var base: String = str(JavaScriptBridge.eval("new URL('cuites/',location.href).href", true))
	_cuit_attente = true
	if _cuit_http.request("%s%s.web.cuit?v=%s" % [base, nom, PNConstants.VERSION_APP]) != OK:
		_cuit_attente = false
		_fichiers_cuits[nom] = false
		_cuit_en_cours = null


func _cuite_recue(resultat: int, code: int, _entetes: PackedStringArray, corps: PackedByteArray) -> void:
	_cuit_attente = false
	var lc: LigneCuite = _cuit_en_cours
	_cuit_en_cours = null
	if lc == null or _cuit_ligne == null:
		return
	var nom: String = String(_cuit_ligne.name)
	if resultat != HTTPRequest.RESULT_SUCCESS or code != 200 or not lc.lire_octets(corps):
		_fichiers_cuits[nom] = false
		return
	lc.poser(get_world_3d().scenario, false)
	if lc.cle != "":
		_cuites[lc.cle] = lc


func _poser_cuite() -> void:
	_cuit_en_cours.charger(_cuit_scenario, true)


func _exit_tree() -> void:
	if _cuit_tache >= 0:
		if _cuit_en_cours != null:
			_cuit_en_cours.abandon = true        # (le fil n'attend plus les images : il finit d'un trait)
		LigneRemontee.attendre_fil(_cuit_tache)
		_cuit_tache = -1
		if _cuit_en_cours != null and _cuit_en_cours.cle != "":
			_cuites[_cuit_en_cours.cle] = _cuit_en_cours
		_cuit_en_cours = null
	for k in _cuites:
		(_cuites[k] as LigneCuite).liberer()
	_cuites.clear()
	VehiculeRemontee.vider_modeles()
	MeshMerge.vider_partages()
	RemonteeKit.vider_primitives()


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("remontees_domaine", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(delta: float) -> void:
	_suivre_cran()
	_gerer_cuites(delta)
	_revoir_portees()
	_avancer_visibilite()
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
		if _lignes_montrees:
			_montrer_lignes(false, p)
			for e in lignes:
				(e[0] as LigneRemontee).set_process(false)
		return
	if not _lignes_montrees:
		_montrer_lignes(true, p)
	# niveau de détail par ligne, selon la distance à la LIGNE (segment
	# gare aval – gare amont) : véhicules invisibles au-delà de
	# VEHICULES_JUSQUA → ligne figée ; au-delà de 300 m, une image sur
	# trois ; la ligne où l'on est assis, toujours à pleine cadence
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if lg.pret and lg != _en_cours and (a_bord.is_empty() or (a_bord[0] != lg and a_bord[0] != lg.jumelee)) \
				and _distance_ligne(lg, p) > _demolir_au_dela(lg) \
				and (lg.jumelee == null or _distance_ligne(lg.jumelee, p) > _demolir_au_dela(lg.jumelee)):
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
## Piques (retour d'utilisateur, 25/10/2026) : forfait validé sous le portique,
## dépose depuis la carte (pas de pique pour ce qu'on n'a pas choisi), siège ou
## cabine qui part sans lui.
var _t: float = 0.0
var _valide: Dictionary = {}       # id de la ligne → instant du passage sous le portique
var _t_depose: float = -1000.0     # dernier saut de position (dépose depuis la carte)
var _p_prec: Vector3 = Vector3.INF
var _guet: Array = []              # [ligne, véhicule] qui peut partir sans lui
var _t_loupe: float = -1000.0
var _etat_bord: String = "marche"


## Remontées qui se prennent dans les deux sens : pas de pique « à la descente »
## (retour d'utilisateur, 25/10/2026).
const DEUX_SENS: Array = ["tsd6_leissieres"]


func _piquer(evt: String, lg: LigneRemontee) -> void:
	if not is_instance_valid(lg):
		return
	if evt == "DESCENTE" and String(lg.name) in DEUX_SENS:
		return
	# resquille : la file d'attente proteste (« whouuu »)
	if evt == "FRAUDE" and sons != null:
		sons._coup(lg, "file_huees")
	pique.emit(evt, lg)


func _depose_recente() -> bool:
	return _t - _t_depose < 120.0


func _portiques(lg: LigneRemontee) -> Array:
	var l: Array = lg.get_meta("portiques", [])
	for n in l:
		if not is_instance_valid(n):
			l = []
			break
	if l.is_empty() and float(lg.get_meta("t_portiques", -10.0)) < _t - 5.0:
		lg.set_meta("t_portiques", _t)
		l = lg.find_children("Portique", "Node3D", true, false)
		lg.set_meta("portiques", l)
	return l


## Fraude : l'embarquement a un portique et il n'est pas passé dessous.
func _fraude(lg: LigneRemontee, aval: bool) -> bool:
	if _depose_recente() or _t - float(_valide.get(lg.get_instance_id(), -1000.0)) < 90.0:
		return false
	var q: Vector3 = lg.global_transform * lg.point_embarquement(aval)
	for n in _portiques(lg):
		if (n as Node3D).global_position.distance_to(q) < 25.0:
			return true
	return false


func _surveiller_approche(p: Vector3) -> void:
	if _p_prec != Vector3.INF and p.distance_to(_p_prec) > 8.0:
		_t_depose = _t
	_p_prec = p
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret or not lg.is_processing():
			continue
		for n in _portiques(lg):
			var c: Vector3 = (n as Node3D).global_position
			if Vector2(p.x - c.x, p.z - c.z).length() < 1.8 and absf(p.y - c.y) < 3.0:
				_valide[lg.get_instance_id()] = _t
	# siège ou cabine guetté : parti sans lui
	if not _guet.is_empty():
		var lg: LigneRemontee = _guet[0]
		if not is_instance_valid(lg) or not lg.pret or int(_guet[1]) >= lg.nombre_vehicules():
			_guet = []
		elif lg.famille.begins_with("cabine") or lg.tricable() or lg.vaetvient():
			var v: VehiculeRemontee = lg.vehicule(_guet[1])
			if v.global_position.distance_to(p) > 8.0:
				_guet = []
			elif lg.zone_vehicule(_guet[1]) == "ligne":
				_loupe(lg)
		elif lg.vehicule_a_embarquer(_guet[2]) != int(_guet[1]):
			var q: Vector3 = lg.global_transform * lg.point_embarquement(_guet[2])
			if p.distance_to(q) < 2.5:
				_loupe(lg)
			_guet = []


func _loupe(lg: LigneRemontee) -> void:
	_guet = []
	if _t - _t_loupe > 25.0 and lg.regime() > 0.3:
		_t_loupe = _t
		_piquer("LOUPE", lg)


func _embarquement() -> void:
	if skieur == null or not skieur.actif:
		return
	_t += get_process_delta_time()
	if a_bord.is_empty() and _attente_tk == null:
		_surveiller_approche(skieur.global_position)
	else:
		_p_prec = skieur.global_position
	if not a_bord.is_empty():
		_suivre_siege()
		return
	if _attente_tk != null:
		_attendre_perche()
		return
	_surveiller_reste_cabine()
	if not a_bord.is_empty():
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
			if p.distance_to(q) < 2.5 and (_guet.is_empty() or _guet[0] != lg):
				_guet = [lg, i, aval]
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
				var evt: String = "FRAUDE" if _fraude(lg, aval) else ""
				if not skieur.chausse:
					skieur.basculer_ski(true)
					if evt == "" and not _depose_recente():
						evt = "PIETON"
				if evt == "" and not aval:
					evt = "RESTE" if not _arrivee_siege.is_empty() and _arrivee_siege[0] == lg \
							and _t - float(_arrivee_siege[1]) < 90.0 else "DESCENTE"
				_guet = []
				a_bord = [lg, i, k, aval, false]
				_etat_bord = lg.etat
				skieur.support = null
				skieur.embarque = true
				skieur.asseoir(_cap(v), true)
				_suivre_siege()
				var dest: String = lg.jumelee.nom_ligne if (aval and lg.role == "bas" and lg.traverse(i)) else lg.nom_ligne
				message.emit("Assis — %s" % dest)
				if evt != "":
					_piquer(evt, lg)
				return


## Pylône dont l'échelle est à portée de main (demande d'utilisateur, 03/11/2026), sinon null.
func echelle_proche(p: Vector3) -> PyloneRemontee:
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if not lg.pret:
			continue
		for q in lg._pyl:
			var py: PyloneRemontee = q[0]
			if not py.a_echelle:
				continue
			var b: Vector3 = py.echelle_a_hauteur(p.y)
			if Vector2(p.x - b.x, p.z - b.z).length() < 1.8 and absf(p.y - b.y) < 4.0:
				return py
	return null


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


## Resté dans la cabine au-delà de la gare : assis pour le retour, avec le commentaire de rigueur.
func _surveiller_reste_cabine() -> void:
	if _reste_cabine.is_empty():
		return
	var lg: LigneRemontee = _reste_cabine[0]
	if not is_instance_valid(lg) or not lg.pret:
		_reste_cabine = []
		return
	var i: int = _reste_cabine[1]
	var v: VehiculeRemontee = lg.vehicule(i)
	# tant qu'il ne bouge pas, il suit la cabine (rien ne le portait : elle partait sans
	# lui, ou le poussait sur le quai) ; au premier pas, il est libre de sortir
	# (clavier ou joystick : sur iPad, le joystick n'était pas vu et le skieur restait prisonnier de la cabine)
	if skieur._clavier() != Vector2.ZERO or skieur.entree.length() > 0.12:
		_reste_cabine = []
		skieur.embarque = false
		return
	var xf: Transform3D = v.global_transform
	if _reste_cabine.size() < 4:
		_reste_cabine.append(xf.affine_inverse() * skieur.global_position)
		skieur.embarque = true
	var loc: Vector3 = _reste_cabine[3]
	skieur.global_position = xf * loc
	if lg.zone_vehicule(i) != "ligne":
		return
	var aval: bool = _reste_cabine[2]
	var k: int = clampi(int(round(loc.x / 0.40 + 2.5)), 0, 5) if lg.tricable() else clampi(int(round(loc.x / 0.46)) + 2, 0, 4)
	if lg.vaetvient():
		k = clampi(int(round(loc.z / 1.0)) + 2, 0, 4)
	_reste_cabine = []
	_guet = []
	_etat_bord = lg.etat
	v.porte_skis(false)
	a_bord = [lg, i, k, aval, not aval]
	skieur.support = null
	skieur.embarque = true
	if not lg.vaetvient():
		skieur.asseoir(_cap(v, not aval), true)
	else:
		skieur.velocity = Vector3.ZERO
	skieur._skis.visible = false
	_suivre_siege()
	_piquer("RESTE", lg)


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
			if _guet.is_empty() and Vector2(loc.x, loc.z).length() < maxf(lim.x, lim.y) + 2.5 \
					and absf(loc.y - y_pl) < 2.0 and lg.regime() > 0.3:
				_guet = [lg, i, zn == "gare_aval"]
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
		_guet = []
		_etat_bord = lg.etat
		var evt: String = "CHAUSSE" if skis else ("DESCENTE" if zn == "gare_amont" and not lg.vaetvient() else "")
		if not _reste_cabine.is_empty() and _reste_cabine[0] == lg and _reste_cabine[1] == i:
			evt = "RESTE"
		_reste_cabine = []
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
		if evt != "":
			_piquer(evt, lg)
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
	if is_instance_valid(lg) and lg.zone_vehicule(a_bord[1]) == "ligne":
		_piquer("SAUT", lg)
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
		if not _depose_recente():
			_piquer("PIETON", lg)
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
			_etat_bord = lg.etat
			_suivre_perche()
			message.emit("Perche prise — %s" % lg.nom_ligne)
			return
	if _t_attente > 90.0:
		_attente_tk = null
		skieur.embarque = false
		_repos = 5.0
		message.emit("Pas de perche — %s est-il en marche ?" % lg.nom_ligne)


const RECUL_PERCHE: float = 2.2


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
	# 2,2 m derrière la pince : corde et perche en biais jusqu'à lui (vidéo
	# du Montet, retour d'utilisateur, 25/10/2026 — il était presque sous le câble,
	# perche verticale et archet devant lui)
	var pos: Vector3 = pc + arriere * RECUL_PERCHE
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
	# archet sous les fesses, rondelle entre les jambes
	v.tendre_perche(v.to_local(pos + Vector3.UP * (0.62 if lg.famille == "perche_tbar" else 0.72)))
	# en haut, on lâche la perche avant la poulie et l'on s'écarte en
	# traversée lente, sans élan vers l'avant : lancé à 2 m/s vers l'avant, au
	# 3000 il passait la crête et dévalait dans le vallon de l'Iseran sans
	# pouvoir prendre le tunnel (retour d'utilisateur, 25/10/2026) ; lâché à
	# l'arrêt plus bas, il repartait en arrière dans la pente
	var arr: Array = lg.arrivee(i)
	if not arr.is_empty() and not bool(arr[0]):
		_lacher_perche(false)


## Lâcher la perche : en haut, à l'aire de lâcher ; en pleine ligne, quand le
## skieur le décide (touche E ou bouton LÂCHER — retour d'utilisateur, 26/10/2026 :
## « on fait comment pour descendre en pleine ligne d'un tk ? »), un pas de
## côté hors de la trace pour la perche suivante. À l'arrêt, skis EN TRAVERS
## de la pente (les carres le retiennent), tournés vers l'extérieur ;
## chasse-neige tant qu'il ne commande rien.
func _lacher_perche(en_ligne: bool) -> void:
	var lg: LigneRemontee = a_bord[0]
	var v: VehiculeRemontee = lg.vehicule(a_bord[1])
	v.longueur_perche(0.0)
	skieur.embarque = false
	var dehors: Vector3 = lg.global_transform.basis.x * signf(lg._x_brin(true))
	if en_ligne:
		var p: Vector3 = skieur.global_position + dehors * 1.8
		if relief != null:
			p.y = relief.hauteur_sol(p.x, p.z) + 0.02
		skieur.global_position = p
		skieur.dernier_sol = p
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
	if en_ligne:
		_piquer("SAUT", lg)
	elif randf() < 0.33:
		_piquer("ARRIVEE", lg)
	a_bord = []
	_repos = 4.0


## Tiré par une perche, en ligne : on peut la lâcher.
func sur_perche() -> bool:
	return a_bord.size() > 5 and is_instance_valid(a_bord[0])


func lacher_perche() -> void:
	if sur_perche():
		_lacher_perche(true)


func _suivre_siege() -> void:
	var lg0: LigneRemontee = a_bord[0]
	if is_instance_valid(lg0):
		if lg0.etat != "marche" and _etat_bord == "marche" and lg0.zone_vehicule(a_bord[1]) == "ligne":
			_piquer("ARRET", lg0)
		_etat_bord = lg0.etat
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
	# il balance avec le siège ou la cabine (assis bien droit, sa tête entrait dans la vitre)
	var penche: Basis = v.balancement_monde()
	skieur._visuel.basis = penche * Basis(Vector3.UP, cap)
	skieur._visuel.position = penche * (Vector3(sin(cap), 0.0, cos(cap)) * SkieurJoueur.RECUL_ASSIS) if skieur.assis else Vector3.ZERO
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
			_t_loupe = _t          # en sortant, les cabines qui repartent ne sont pas « loupées »
			if randf() < 0.33:
				_piquer("ARRIVEE_BAS" if aval_arr else "ARRIVEE", lg)
			_reste_cabine = [lg, i, aval_arr]
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
		_t_loupe = _t
		if randf() < 0.33:
			_piquer("ARRIVEE_BAS" if aval_arr else "ARRIVEE", lg)
		_arrivee_siege = [lg, _t]
		a_bord = []
		_repos = 6.0
