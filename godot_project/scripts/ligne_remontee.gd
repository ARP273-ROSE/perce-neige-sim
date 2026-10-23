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
const L_GARE: float = 24.0            # du nez de gare à l'axe de la poulie
const L_FREIN: float = 18.0           # longueur du lanceur (freinage / accélération)
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
var _h_nez: Array = [0.0, 0.0]  # demi-longueur de la batterie de galets au nez [aval, amont]
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


## Construction progressive (jeu, surtout la PWA) : on rend la main au
## moteur dès que l'image a consommé `budget_ms` — avant, les deux lignes se
## construisaient d'un bloc (2 s ici, beaucoup plus sur iPad) au premier
## passage en vue skieur, et l'écran restait figé (retour d'utilisateur, 23/10/2026).
## Hors progressif (bancs, captures) : tout d'un bloc, comme avant.
var progressif: bool = false
var budget_ms: float = 6.0
var pret: bool = false
var _t_tranche: int = 0
signal construite


func _pause() -> void:
	if not progressif:
		return
	if Time.get_ticks_usec() - _t_tranche > int(budget_ms * 1000.0):
		await get_tree().process_frame
		_t_tranche = Time.get_ticks_usec()


func construire() -> void:
	_poulies.clear()
	pret = false
	_t_tranche = Time.get_ticks_usec()
	set_process(false)
	for c in get_children():
		c.queue_free()
	_vehicules.clear()
	_pyl.clear()
	_pyl_touches.clear()
	H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(famille)
	# vitesse d'embarquement : 1 m/s aux sièges, 0,25 m/s aux cabines (on y
	# entre à pied) — les véhicules se resserrent d'autant dans la partie
	# lente : au moins deux dans le demi-tour, d'autres dans les lanceurs
	# (retour d'utilisateur, 22/10/2026)
	v_embarquement = 0.25 if famille.begins_with("cabine") else 1.0
	_calculer_tetes()
	_preparer_nez()
	_gare(true)
	await _pause()
	_gare(false)
	await _pause()
	await _poser_pylones()
	_construire_boucle()
	_cable()
	await _pause()
	await _lanceurs()
	await _peupler()
	if not (famille.begins_with("cabine") or famille.begins_with("perche")):
		_portillons(true)
		_portillons(false)
	if avec_collisions:
		_collisions_fixes()
		for i in range(_vehicules.size()):
			_corps_vehicule(i)
			await _pause()
	pret = true
	set_process(true)
	construite.emit()


# --- géométrie du câble ---------------------------------------------------------

func _points_appui() -> Array:
	# [d, y] des points d'appui du câble : gare aval, têtes, gare amont
	# (la gare est prolongée jusqu'au milieu de la batterie du nez : c'est
	# là que se croisent l'horizontale de la gare et la pente de la ligne)
	var pts: Array = [[_h_nez[0], terrain(0.0) + H_CABLE_GARE]]
	for i in range(pylones.size()):
		pts.append([float(pylones[i]["d"]), _tetes[i]])
	var L: float = longueur_h()
	pts.append([L - _h_nez[1], terrain(L) + H_CABLE_GARE])
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
				# garde pleine en ligne, réduite près des gares où le câble
				# rejoint la hauteur du quai (sinon le dernier pylône était
				# relevé jusqu'à la butée de 32 m — retour d'utilisateur, 23/10/2026)
				var g: float = lerpf(H_CABLE_GARE - 0.5, GARDE, smoothstep(0.0, 40.0, minf(d, longueur_h() - d)))
				pire = maxf(pire, terrain(d) + g - yc)
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
	# pylônes de COMPRESSION (balancier côté montée en C) : le câble doit y
	# passer SOUS les galets, la ligne y est concave — tête abaissée sous la
	# corde de ses voisins (sinon le câble décollerait des galets)
	for it2 in range(30):
		var bouge: bool = false
		var pts2: Array = _points_appui()
		for i in range(pylones.size()):
			if not _compression(pylones[i]):
				continue
			var a: Array = pts2[i]
			var b: Array = pts2[i + 2]
			var d: float = float(pylones[i]["d"])
			var corde: float = lerpf(a[1], b[1], (d - a[0]) / maxf(b[0] - a[0], 0.01))
			var t2: float = terrain(d) + 6.5
			if corde - 0.8 < t2:
				# le terrain empêche d'abaisser la tête : on relève la corde en
				# remontant le voisin amont (ou aval, au dernier pylône)
				var manque: float = t2 + 0.8 - corde
				if i + 1 < pylones.size():
					_tetes[i + 1] += manque * (b[0] - a[0]) / maxf(d - a[0], 0.01)
				elif i > 0:
					_tetes[i - 1] += manque * (b[0] - a[0]) / maxf(b[0] - d, 0.01)
				bouge = true
				continue
			if _tetes[i] > corde - 0.8 + 0.05:
				_tetes[i] = corde - 0.8
				bouge = true
		if not bouge:
			break


func _compression(p: Dictionary) -> bool:
	var n_c: int = 0
	var n_s: int = 0
	for g in p.get("montee", []):
		var n: int = int(g[0]) if g[0] != null else 2
		if String(g[1]) == "C":
			n_c += n
		elif String(g[1]) == "S":
			n_s += n
	return n_c > n_s


## Batteries de galets des nez de gare : le câble passe de l'horizontale
## de la gare à la pente de la ligne en suivant l'arc des galets (avant, il
## faisait un angle au nez et traversait les galets — retour d'utilisateur,
## 22/10/2026). La batterie compte 2 galets par 2° de déviation (4 à 16) ;
## l'horizontale de la gare et la ligne se croisent en son milieu.
func _preparer_nez() -> void:
	_h_nez = [0.0, 0.0]
	var L: float = longueur_h()
	var e: float = 6.0
	var p_a: float = atan2(y_cable(e) - y_cable(0.0), e)
	var p_b: float = atan2(y_cable(L) - y_cable(L - e), e)
	_h_nez = [_demi_batterie(p_a), _demi_batterie(p_b)]


func _galets_batterie(dev: float) -> int:
	return clampi(2 * int(ceil(rad_to_deg(absf(dev)) / 2.0)), 4, 16)


func _demi_batterie(dev: float) -> float:
	if absf(dev) < deg_to_rad(0.8):
		return 0.0
	return (_galets_batterie(dev) - 1) * PyloneRemontee.PAS_GALET * 0.5


## Pente (m/m) de la ligne en quittant la gare (aval ou amont), au
## croisement avec l'horizontale de la gare.
func _pente_nez(aval: bool, montee: bool) -> float:
	var L: float = longueur_h()
	if aval:
		return (_y_chainette(_h_nez[0] + 0.5, montee) - (terrain(0.0) + H_CABLE_GARE)) / 0.5
	return (_y_chainette(L - _h_nez[1] - 0.5, montee) - (terrain(L) + H_CABLE_GARE)) / 0.5


## Hauteur du câble (chaînette) à la distance d, brin montée ou descente ;
## aux nez, raccord parabolique sur 2 h (l'arc de la batterie de galets).
func y_cable(d: float, montee: bool = true) -> float:
	var L: float = longueur_h()
	var h: float = _h_nez[0]
	if h > 0.0 and d < 2.0 * h:
		var dd: float = maxf(d, 0.0)
		return terrain(0.0) + H_CABLE_GARE + _pente_nez(true, montee) * dd * dd / (4.0 * h)
	h = _h_nez[1]
	if h > 0.0 and L - d < 2.0 * h:
		var t: float = maxf(L - d, 0.0)
		return terrain(L) + H_CABLE_GARE + _pente_nez(false, montee) * t * t / (4.0 * h)
	return _y_chainette(d, montee)


func _y_chainette(d: float, montee: bool = true) -> float:
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
	var d: float = _pas_ligne(0.0)
	while d < L:
		_ajouter(Vector3(xm, y_cable(d), -d))
		d += _pas_ligne(d)
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
	d = L - _pas_ligne(L)
	while d > 0.0:
		_ajouter(Vector3(xd, y_cable(d, false), -d))
		d -= _pas_ligne(d)
	longueur_boucle = _longueur() + _boucle[_boucle.size() - 1].distance_to(_boucle[0])


## Pas d'échantillonnage du câble en ligne : fin dans les raccords des nez.
func _pas_ligne(d: float) -> float:
	var L: float = longueur_h()
	return 0.5 if d < 2.0 * _h_nez[0] + 1.0 or d > L - 2.0 * _h_nez[1] - 1.0 else 3.0


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
## (plus de « plongée » : le rail reste au même niveau sur toute la gare,
## poulie comprise — retour d'utilisateur, 22/10/2026)
const PLONGEE: float = 0.0
## Le câble tourne sur une poulie un peu plus petite que la voie : rentré par
## les galets de déviation, il laisse passer les pinces débrayées autour.
const RETRAIT_POULIE: float = 0.45
const Z_DEVIATION: float = 2.5


func rayon_poulie() -> float:
	return voie * 0.5 - RETRAIT_POULIE


func x_arret(l: float) -> float:
	return l - L_FREIN - 2.0          # ligne d'arrêt, encore à vitesse d'embarquement


func x_portillons(l: float) -> float:
	return x_arret(l) - 2.2


func _plongee(s: float) -> float:
	if PLONGEE == 0.0 or famille.begins_with("cabine") or famille.begins_with("perche"):
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
	# sur toute la longueur du lanceur, la vitesse suit une courbe « smootherstep »
	# (6t⁵ − 15t⁴ + 10t³) : dérivée nulle aux deux bouts, donc accélération
	# nulle à l'entrée et à la sortie, continue et régulière entre les deux —
	# pas d'à-coup à l'entrée du lanceur ni à l'embrayage (retour d'utilisateur, 22/10/2026)
	var x: float = z[1]
	var l: float = z[2]
	# (profil sur l'énergie cinétique v² : la décélération est la plus forte
	# au milieu du lanceur, pas près de l'entrée où la vitesse est grande)
	var t: float = clampf(minf(x, l - x) / L_FREIN, 0.0, 1.0)
	var lisse: float = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	return sqrt(vitesse * vitesse - (vitesse * vitesse - v_embarquement * v_embarquement) * lisse)


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
	var zm: float = (zc + znez) * 0.5 + signf(dz) * 4.0
	var long_g: float = absf(dz) + voie * 0.5 + 3.5 + 5.0      # + aire d'attente derrière la poulie
	# dalle et quais
	# plate-forme : la gare est posée au plus haut du terrain sous son
	# emprise ; un talus de neige damée descend en pente douce jusqu'au sol
	# là où il est plus bas (un socle de béton faisait un bloc sombre)
	g.add_child(_talus(_points_talus(Vector2(voie + 10.0, long_g), Vector3(0, 0, zm)), Vector3(0, 0, zm)))
	# rampe d'accès côté portillons : la piste arrive à niveau du quai
	var lr: float = float(rampes[0 if aval else 1])
	if lr > 0.5:
		var pr: PackedVector3Array = _points_rampe(aval, lr)
		g.add_child(_talus(pr, (pr[0] + pr[2]) * 0.5 + Vector3(0, -1.0, 0)))
	# carénage en gélule sur colonnes, cabine du conducteur (photos des
	# gares BMF du Marmottes Express, retour d'utilisateur, 23/10/2026)
	_capot(g, znez, zc, aval)
	_cabine_conducteur(g, znez, dz, aval)
	# poulie de demi-tour (motrice en amont, retour-tension en aval)
	var R: float = voie * 0.5
	# la roue tourne (nœud à part) ; arbre et bâti restent dans la gare
	var cp: Vector3 = Vector3(0, H_CABLE_GARE, zc)
	var roue: Node3D = Node3D.new()
	roue.name = "Poulie"
	roue.position = cp
	g.add_child(roue)
	_poulie(roue, Vector3.ZERO, rayon_poulie(), aval)
	var fixes: Array = roue.get_children().slice(_coupe_poulie)
	for n in fixes:
		roue.remove_child(n)
		g.add_child(n)
		(n as Node3D).position += cp
	MeshMerge.merge(roue, [], "Roue")
	# vitesse du câble en ligne, au rayon de la gorge ; sens de la boucle
	_poulies.append([roue, signf(_x_brin(true)) * vitesse / rayon_poulie()])
	# galets de déviation (axe vertical) : ils rentrent le câble de la voie
	# de ligne au diamètre de la poulie, juste après le nez de la gare
	for sx in [-1.0, 1.0]:
		for k in range(3):
			var zd: float = znez + signf(dz) * (Z_DEVIATION + 0.7 * k)
			var xd: float = sx * (_x_rentre(Z_DEVIATION + 0.7 * k) - 0.21 - PyloneRemontee.R_CABLE)
			RemonteeKit.galet(g, Vector3(xd, H_CABLE_GARE, zd), 0.21)
			(g.get_child(g.get_child_count() - 1) as Node3D).transform.basis = Basis(Vector3.FORWARD, 0.0).scaled(Vector3.ONE * 0.21 / RollerMesh.R_BANDE)
			RemonteeKit.boite_en(g, Vector3(0.22, 0.04, 0.30), Vector3(xd, H_CABLE_GARE + 0.16, zd), "galva_pylone")
			RemonteeKit.boite_en(g, Vector3(0.10, 1.4, 0.10), Vector3(xd, H_CABLE_GARE + 0.86, zd), "galva_pylone")
	# came d'ouverture / de fermeture des pinces, au nez de la gare
	for sx in [-1.0, 1.0]:
		RemonteeKit.poutre(g, Vector3(sx * (R + 0.40), H_CABLE_GARE + 0.40, znez), Vector3(sx * (R + 0.44), H_CABLE_GARE + 0.30, znez + signf(dz) * 3.0), 0.06, 0.05, "jaune_securite")
	# ligne d'embarquement (bande jaune) côté montée en aval, côté descente en amont
	var xb: float = _x_brin(aval)
	RemonteeKit.boite_en(g, Vector3(voie * 0.5 + 0.8, 0.02, 0.12), Vector3(xb * 0.6, 0.01, znez + signf(dz) * (L_FREIN + 2.5)), "jaune_securite")
	MeshMerge.merge(g, [g.get_node("Poulie")], "Gare")


# --- plate-forme de gare -----------------------------------------------------------

const H_TALUS: float = 6.4          # profondeur du talus (jusque sous le terrain)
const PENTE_RAMPE: float = 0.10     # rampe d'accès côté portillons (10 %)
## Longueur de la rampe d'accès derrière chaque gare [aval, amont] : posée
## par RemonteesDomaine d'après le relief, pour que la piste arrive à
## niveau du quai côté portillons (retour d'utilisateur, 23/10/2026).
var rampes: Array = [0.0, 0.0]


## Distance du nez de la gare au bout du quai, côté portillons.
func bout_quai() -> float:
	var long_g: float = L_GARE + voie * 0.5 + 8.5
	return (L_GARE * 0.5 + 4.0) + long_g * 0.5


## Sommets de la rampe (repère de la gare, dessus du quai à y = 0), même
## ordre que le talus : dessus (4), puis base (4).
func _points_rampe(aval: bool, lr: float) -> PackedVector3Array:
	var sg: float = 1.0 if aval else -1.0
	var znez: float = 0.0 if aval else -longueur_h()
	var ze: float = znez + sg * bout_quai()
	var zf: float = ze + sg * lr
	var hw: float = (voie + 10.0) * 0.5
	var yf: float = -lr * PENTE_RAMPE
	var e: float = H_TALUS * PENTE_TALUS
	var pts: PackedVector3Array = PackedVector3Array([
		Vector3(-hw, 0.0, ze), Vector3(hw, 0.0, ze), Vector3(hw, yf, zf), Vector3(-hw, yf, zf),
		Vector3(-hw - e, -H_TALUS, ze), Vector3(hw + e, -H_TALUS, ze), Vector3(hw + e, yf - H_TALUS, zf + sg * e), Vector3(-hw - e, yf - H_TALUS, zf + sg * e)])
	return pts
const PENTE_TALUS: float = 1.6      # base / hauteur (environ 32°)


## Sommets du talus (tronc de pyramide) : dessus `taille` centré en `c`.
func _points_talus(taille: Vector2, c: Vector3) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	for niv in [[0.0, 0.0], [-H_TALUS, H_TALUS * PENTE_TALUS]]:
		var hx: float = taille.x * 0.5 + float(niv[1])
		var hz: float = taille.y * 0.5 + float(niv[1])
		for q in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			pts.append(c + Vector3(q.x, float(niv[0]), q.y))
	return pts


## Talus de neige damée (ou rampe) : dessus, quatre flancs en pente ; `p`
## = dessus (4) puis base (4), `c` = un point intérieur.
func _talus(p: PackedVector3Array, c: Vector3) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array = [[0, 1, 2, 3]]
	for k in range(4):
		faces.append([k, k + 4, (k + 1) % 4 + 4, (k + 1) % 4])
	for fc in faces:
		var a: Vector3 = p[fc[0]]
		var b: Vector3 = p[fc[1]]
		var cc: Vector3 = p[fc[2]]
		var d: Vector3 = p[fc[3]]
		var n: Vector3 = (b - a).cross(cc - a).normalized()
		if n.y < -0.01 or (absf(n.y) <= 0.01 and n.dot(a - c) < 0.0):
			n = -n
		for v in [a, b, cc, a, cc, d]:
			st.set_normal(n)
			st.add_vertex(v)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Talus"
	var m: StandardMaterial3D = (RemonteeKit.mat("neige_damee") as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


# --- carénage de gare ------------------------------------------------------------

## Dessous du carénage au-dessus du câble (au-dessus de la poutre des pneus).
const Y_CAPOT: float = 1.25
const H_CAPOT: float = 2.9          # du dessous au faîte
const D_CAPOT: float = 1.35         # débord du carénage au-delà de la voie des véhicules


## Profil du carénage : [r, h] du bas extérieur au faîte (superellipse :
## flancs presque droits, toit bombé, comme une gélule).
func _profil_capot(Ro: float) -> Array:
	var out: Array = []
	var n: int = 14
	for i in range(n + 1):
		var a: float = PI * 0.5 * float(i) / n
		var c: float = pow(cos(a), 2.0 / 3.2)
		var sn: float = pow(sin(a), 2.0 / 3.2)
		out.append([Ro * c, H_CAPOT * sn])
	return out


static var _mats_capot: Dictionary = {}


func _mat_capot(nom: String) -> Material:
	if _mats_capot.has(nom):
		return _mats_capot[nom]
	var m: StandardMaterial3D = (RemonteeKit.mat(nom) as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats_capot[nom] = m
	return m


## Carénage BMF : coque blanche en gélule du nez de la gare jusqu'au-delà de
## la poulie, bout arrondi (en plan) vitré de grandes vitres sombres, flancs
## percés de hublots, nom de la ligne ; dessous plat avec la fente où
## passent les suspentes ; posé sur deux colonnes rondes, l'une sous la
## poulie (arbre vertical), l'autre au milieu du quai.
func _capot(g: Node3D, znez: float, zc: float, aval: bool) -> void:
	var sg: float = signf(zc - znez)
	var R: float = voie * 0.5
	var Ro: float = R + D_CAPOT
	var y0: float = H_CABLE_GARE + Y_CAPOT
	var z0: float = znez - sg * 0.6
	var prof: Array = _profil_capot(Ro)
	var st: Dictionary = {}
	var quad := func(mat: String, q: Array) -> void:
		if not st.has(mat):
			var s0: SurfaceTool = SurfaceTool.new()
			s0.begin(Mesh.PRIMITIVE_TRIANGLES)
			s0.set_smooth_group(0)
			st[mat] = s0
		var s1: SurfaceTool = st[mat]
		for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			s1.add_vertex(v)
	var h_vitre0: float = 0.18
	var h_vitre1: float = H_CAPOT * 0.74
	# partie droite : la section balayée de z0 à zc, flancs blancs
	for sx in [-1.0, 1.0]:
		for i in range(prof.size() - 1):
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			quad.call("blanc_plaque", [Vector3(sx * a[0], y0 + a[1], z0), Vector3(sx * b[0], y0 + b[1], z0),
				Vector3(sx * b[0], y0 + b[1], zc), Vector3(sx * a[0], y0 + a[1], zc)])
	# bout arrondi : le profil tourne de 180° autour de l'axe de la poulie ;
	# grande verrière sombre sur la bande centrale
	var nphi: int = 28
	for k in range(nphi):
		var p0: float = PI * float(k) / nphi
		var p1: float = PI * float(k + 1) / nphi
		for i in range(prof.size() - 1):
			var a2: Array = prof[i]
			var b2: Array = prof[i + 1]
			var pt := func(r: float, h: float, phi: float) -> Vector3:
				return Vector3(r * cos(phi), y0 + h, zc + sg * r * sin(phi))
			var hm: float = (float(a2[1]) + float(b2[1])) * 0.5
			var mat: String = "vitre_teintee" if hm > h_vitre0 and hm < h_vitre1 and k > 1 and k < nphi - 2 else "blanc_plaque"
			quad.call(mat, [pt.call(a2[0], a2[1], p0), pt.call(b2[0], b2[1], p0), pt.call(b2[0], b2[1], p1), pt.call(a2[0], a2[1], p1)])
	# dessous : bord extérieur (au-delà de la fente des suspentes) et
	# plafond intérieur ; la fente suit la boucle des véhicules
	var r_in: float = R - 0.55
	var r_out: float = R + 0.60
	for sx in [-1.0, 1.0]:
		quad.call("blanc_plaque", [Vector3(sx * r_out, y0, z0), Vector3(sx * Ro, y0, z0), Vector3(sx * Ro, y0, zc), Vector3(sx * r_out, y0, zc)])
	quad.call("blanc_plaque", [Vector3(-r_in, y0, z0), Vector3(r_in, y0, z0), Vector3(r_in, y0, zc), Vector3(-r_in, y0, zc)])
	for k in range(nphi):
		var p0b: float = PI * float(k) / nphi
		var p1b: float = PI * float(k + 1) / nphi
		var c0: Vector3 = Vector3(cos(p0b), 0, sg * sin(p0b))
		var c1: Vector3 = Vector3(cos(p1b), 0, sg * sin(p1b))
		var o: Vector3 = Vector3(0, y0, zc)
		quad.call("blanc_plaque", [o + c0 * r_out, o + c0 * Ro, o + c1 * Ro, o + c1 * r_out])
		quad.call("blanc_plaque", [o, o + c0 * r_in, o + c1 * r_in, o])
	var mesh: ArrayMesh = ArrayMesh.new()
	for mat in st.keys():
		var s2: SurfaceTool = st[mat]
		s2.index()
		s2.generate_normals()
		s2.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_capot(mat))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Capot"
	mi.mesh = mesh
	g.add_child(mi)
	# montants de la verrière, lisse basse et bandeau sous le toit
	var r_at := func(h: float) -> float:
		for i in range(prof.size() - 1):
			if h <= float(prof[i + 1][1]):
				var t: float = (h - float(prof[i][1])) / maxf(float(prof[i + 1][1]) - float(prof[i][1]), 0.001)
				return lerpf(float(prof[i][0]), float(prof[i + 1][0]), t)
		return 0.0
	for k in range(8):
		var phi: float = PI * (0.08 + 0.84 * float(k) / 7.0)
		var pts: PackedVector3Array = PackedVector3Array()
		for j in range(7):
			var h: float = lerpf(h_vitre0, h_vitre1, float(j) / 6.0)
			var r: float = r_at.call(h) + 0.02
			pts.append(Vector3(r * cos(phi), y0 + h, zc + sg * r * sin(phi)))
		RemonteeKit.tube(g, pts, 0.035, "blanc_plaque", 6)
	# hublots sombres et bandeau du nom le long des flancs
	var hh: float = 1.55
	var rh: float = r_at.call(hh)
	var lz: float = absf(zc - z0)
	var n_h: int = int(lz / 3.2)
	for sx in [-1.0, 1.0]:
		for k in range(n_h):
			var zh: float = z0 + sg * (2.0 + 3.2 * k)
			RemonteeKit.boite_en(g, Vector3(0.04, 0.42, 0.95), Vector3(sx * (rh + 0.005), y0 + hh, zh), "noir_mat")
		var rb: float = r_at.call(0.55)
		RemonteeKit.boite_en(g, Vector3(0.03, 0.30, lz * 0.55), Vector3(sx * (rb + 0.01), y0 + 0.55, (z0 + zc) * 0.5), "plaque_bleue")
		if nom_ligne == "":
			continue
		var lab: Label3D = Label3D.new()
		lab.text = nom_ligne.to_upper()
		lab.font_size = 96
		lab.pixel_size = 0.0028
		lab.modulate = Color(1, 1, 1)
		lab.outline_size = 0
		lab.position = Vector3(sx * (rb + 0.03), y0 + 0.55, (z0 + zc) * 0.5)
		lab.rotation.y = sx * PI * 0.5           # lisible de l'extérieur
		g.add_child(lab)
	# bord de l'ouverture côté ligne : un cadre qui suit le profil
	var cadre: PackedVector3Array = PackedVector3Array()
	for i in range(prof.size()):
		cadre.append(Vector3(float(prof[i][0]), y0 + float(prof[i][1]), z0))
	for i in range(prof.size() - 2, -1, -1):
		cadre.append(Vector3(-float(prof[i][0]), y0 + float(prof[i][1]), z0))
	RemonteeKit.tube(g, cadre, 0.06, "blanc_plaque", 6)
	# colonnes rondes évasées en tête : sous la poulie, et au milieu du quai
	for zcol in [zc, (znez + zc) * 0.5 - sg * 1.0]:
		var hcol: float = (H_CABLE_GARE - 0.35) if zcol == zc else y0
		RemonteeKit.cylindre(g, 0.50, 0.50, hcol - 0.8, Transform3D(Basis.IDENTITY, Vector3(0, (hcol - 0.8) * 0.5, zcol)), "blanc_plaque", 24)
		RemonteeKit.cylindre(g, 0.50, 0.95, 0.8, Transform3D(Basis.IDENTITY, Vector3(0, hcol - 0.4, zcol)), "blanc_plaque", 24)


## Cabine du conducteur en pierre (photos des deux gares) : à côté du quai
## d'embarquement, côté extérieur, toit à deux pans en bardeaux sombres.
func _cabine_conducteur(g: Node3D, znez: float, dz: float, aval: bool) -> void:
	var sg: float = signf(dz)
	var xb: float = signf(_x_brin(aval))
	var c: Vector3 = _pos_cabine_conducteur(aval) - Vector3(0, 0, 0)
	c.y = 0.0
	RemonteeKit.boite_en(g, Vector3(3.0, 2.5, 3.6), c + Vector3(0, 1.25, 0), "pierre")
	for sz in [-1.0, 1.0]:
		var pan: Transform3D = Transform3D(Basis(Vector3.FORWARD, -xb * sz * 0.0) * Basis(Vector3.BACK, sz * 0.48), c + Vector3(sz * 0.80, 2.88, 0))
		RemonteeKit.boite(g, Vector3(1.95, 0.10, 4.0), pan, "toit_bardeaux")
	# grande vitre côté quai, porte côté aval
	RemonteeKit.boite_en(g, Vector3(0.05, 1.0, 2.2), c + Vector3(-xb * 1.52, 1.45, 0), "vitre_teintee")
	RemonteeKit.boite_en(g, Vector3(0.9, 2.0, 0.05), c + Vector3(0, 1.0, sg * -1.82), "peinture_anthracite")


func _pos_cabine_conducteur(aval: bool) -> Vector3:
	var L: float = longueur_h()
	var znez: float = 0.0 if aval else -L
	var sg: float = 1.0 if aval else -1.0
	var xb: float = signf(_x_brin(aval))
	return Vector3(xb * (voie * 0.5 + D_CAPOT + 1.8), terrain(0.0 if aval else L), znez + sg * (L_FREIN + 3.0))


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
		var h: float = _tetes[i] - t - _dessus_traverse()
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
		var zm: float = (zc + znez) * 0.5 + signf(dz) * 4.0
		var long_g: float = absf(dz) + voie * 0.5 + 3.5 + 5.0      # + aire d'attente derrière la poulie
		var tal: CollisionShape3D = CollisionShape3D.new()
		var cv: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		cv.points = _points_talus(Vector2(voie + 10.0, long_g), Vector3(0, y0, zm))
		tal.shape = cv
		corps.add_child(tal)
		var lr: float = float(rampes[0 if aval else 1])
		if lr > 0.5:
			var ram: CollisionShape3D = CollisionShape3D.new()
			var cv2: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			var pr: PackedVector3Array = _points_rampe(aval, lr)
			for k in range(pr.size()):
				pr[k] += Vector3(0, y0, 0)
			cv2.points = pr
			ram.shape = cv2
			corps.add_child(ram)
		# colonnes du carénage et cabine du conducteur
		boite.call(Vector3(1.0, H_CABLE_GARE, 1.0), Vector3(0, y0 + H_CABLE_GARE * 0.5, zc))
		boite.call(Vector3(1.0, H_CABLE_GARE + Y_CAPOT, 1.0), Vector3(0, y0 + (H_CABLE_GARE + Y_CAPOT) * 0.5, (znez + zc) * 0.5 - signf(dz) * 1.0))
		boite.call(Vector3(3.0, 2.5, 3.6), _pos_cabine_conducteur(aval) + Vector3(0, 1.25, 0))
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
## Position des portillons (repère de la ligne, au sol) : dans l'axe du
## brin de départ, DERRIÈRE la poulie, à 2 m au-delà de l'extrémité
## extérieure du siège qui fait demi-tour (retour d'utilisateur, 22/10/2026) — on
## y attend hors du passage des sièges, puis on traverse jusqu'à l'arrêt.
func position_portillons(aval: bool) -> Vector3:
	var L: float = longueur_h()
	var zc: float = L_GARE if aval else -L - L_GARE
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	var W: float = 0.50 * places + 0.20
	var recul: float = voie * 0.5 + W * 0.5 + 2.0
	return Vector3(_x_brin(aval), terrain(0.0 if aval else L), zc + (recul if aval else -recul))


func _portillons(aval: bool) -> void:
	var l: float = longueur_zone(aval)
	var q0: Vector3 = position_portillons(aval)
	var p: Vector3 = q0
	# face à la ligne d'arrêt (vers le nez de la gare)
	var dirh: Vector3 = Vector3(0, 0, -1) if aval else Vector3(0, 0, 1)
	var y0: float = q0.y
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
		# ouverts quand un siège termine son demi-tour (il est alors passé
		# devant eux) : on traverse derrière lui jusqu'à la ligne d'arrêt
		var xa: float = L_GARE + PI * voie * 0.5
		pg[3] = float(pg[3]) + delta
		for e in _vehicules:
			var z: Array = zone(e[1])
			if z[0] == ("gare_aval" if aval else "gare_amont"):
				var x: float = z[1]
				if x >= xa and x - vitesse_en(e[1]) * delta < xa:
					pg[3] = 0.0
		var t: float = pg[3]
		var ouv: float = clampf(minf((t - 0.3) / 0.5, (3.5 - t) / 0.5), 0.0, 1.0)

		# ils s'ouvrent vers l'avant, vers la ligne d'arrêt (retour
		# d'utilisateur, 23/10/2026) : le repère regarde le nez de la gare (−Z)
		for v in pg[1]:
			(v as Node3D).rotation.y = 1.45 * ouv
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


## Gare où se trouve le véhicule i : "gare_aval", "gare_amont" ou "ligne".
func zone_vehicule(i: int) -> String:
	return zone(_vehicules[i][1])[0]


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


## Poulie de demi-tour, d'après photo (Wikimedia Commons, « Chairlift
## bullwheel ») : grande roue horizontale, jante en U garnie de caoutchouc
## au fond de la gorge (le câble y repose), huit rayons en caisson avec
## leurs semelles, anneau raidisseur, gros moyeu sur arbre vertical ; au-
## dessus, le bâti (réducteur et moteur en amont, chariot de tension en aval).
var _coupe_poulie: int = 0
var _poulies: Array = []        # [roue, vitesse angulaire (rad/s)]


func _poulie(g: Node3D, c: Vector3, R: float, aval: bool) -> void:
	if not VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[2] == "fixe":
		_poulie_debrayable(g, c, R, aval)
		return
	var m: String = "jaune_poulie"
	var n: int = 48
	# gorge garnie (là où passe le câble) et ailes de la jante
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.RIGHT, Vector3.BACK, R + 0.03, 0.0, TAU, n), 0.045, "caoutchouc", 8)
	for dy in [-0.11, 0.11]:
		RemonteeKit.tube(g, RemonteeKit.arc(c + Vector3(0, dy, 0), Vector3.RIGHT, Vector3.BACK, R + 0.07, 0.0, TAU, n), 0.025, m, 6)
	for k in range(n):
		var a0: float = TAU * k / n
		var a1: float = TAU * (k + 1) / n
		var p0: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * (R + 0.12)
		var p1: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * (R + 0.12)
		RemonteeKit.poutre(g, p0, p1, 0.02, 0.24, m)                                   # âme de la jante
	# huit rayons en caisson : semelles haute et basse, deux âmes, trous d'allègement
	for k in range(8):
		var a: float = TAU * (k + 0.5) / 8.0
		var d3: Vector3 = Vector3(cos(a), 0, sin(a))
		var t3: Vector3 = Vector3(-sin(a), 0, cos(a))
		var p_in: Vector3 = c + d3 * 0.48
		var p_out: Vector3 = c + d3 * (R + 0.10)
		for dy in [-0.16, 0.16]:
			RemonteeKit.poutre(g, p_in + Vector3(0, dy, 0), p_out + Vector3(0, dy * 0.6, 0), 0.24, 0.02, m)
		for sx in [-0.10, 0.10]:
			RemonteeKit.poutre(g, p_in + t3 * sx, p_out + t3 * sx * 0.8, 0.015, 0.30, m, t3)
		for f in [0.35, 0.55, 0.75]:
			RemonteeKit.cylindre(g, 0.06, 0.06, 0.24, Transform3D(Basis(d3, PI * 0.5), c + d3 * (0.48 + (R - 0.38) * f)),
				"acier_noir", 10)
	# anneau raidisseur à mi-rayon
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.RIGHT, Vector3.BACK, R * 0.55, 0.0, TAU, 32), 0.05, m, 6)
	# moyeu, arbre et bâti
	RemonteeKit.cylindre(g, 0.48, 0.48, 0.50, Transform3D(Basis.IDENTITY, c), m, 24)
	_coupe_poulie = g.get_child_count()          # la suite (arbre, bâti) ne tourne pas
	RemonteeKit.cylindre(g, 0.20, 0.20, 0.30, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.38, 0)), "acier", 16)
	RemonteeKit.cylindre(g, 0.55, 0.55, 0.20, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.62, 0)), "galva_pylone", 24)
	RemonteeKit.boite_en(g, Vector3(2.0, 0.9, 2.2), c + Vector3(0, 1.17, 0), "galva_pylone")
	if aval:
		# chariot de tension : glissières et vérin vers l'arrière de la gare
		for sx in [-0.8, 0.8]:
			RemonteeKit.poutre(g, c + Vector3(sx, 1.65, -1.8), c + Vector3(sx, 1.65, 2.6), 0.18, 0.22, "galva_pylone")
		RemonteeKit.cylindre(g, 0.09, 0.09, 1.6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 1.30, 1.9)), "acier", 12)
	else:
		# réducteur et moteur
		RemonteeKit.boite_en(g, Vector3(1.4, 1.0, 1.4), c + Vector3(0, 2.1, 0), "peinture_anthracite")
		RemonteeKit.cylindre(g, 0.45, 0.45, 1.6, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c + Vector3(1.4, 2.1, 0)), "peinture_anthracite", 20)


## Poulie d'une gare DÉBRAYABLE (retour d'utilisateur, 22/10/2026 : la roue à rayons
## « c'est pour un TS à pince fixe ») : disque plein en deux flasques soudées
## avec trous d'allègement, jante à gorge garnie, gros moyeu, enfermée sous
## la charpente de la gare sur son bâti (chariot de tension en aval,
## réducteur et moteur en amont) — les pinces débrayées passent en dehors,
## sur le rail.
func _poulie_debrayable(g: Node3D, c: Vector3, R: float, aval: bool) -> void:
	var m: String = "peinture_anthracite"
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.RIGHT, Vector3.BACK, R + 0.03, 0.0, TAU, 56), 0.045, "caoutchouc", 8)
	for dy in [-0.10, 0.10]:
		RemonteeKit.tube(g, RemonteeKit.arc(c + Vector3(0, dy, 0), Vector3.RIGHT, Vector3.BACK, R + 0.07, 0.0, TAU, 56), 0.025, m, 6)
		RemonteeKit.cylindre(g, R, R - 0.25, 0.02, Transform3D(Basis.IDENTITY, c + Vector3(0, dy * 1.4, 0)), m, 56)
	# trous d'allègement (deux couronnes), vus comme des disques sombres sur les flasques
	for couronne in [[0.62, 10, 0.32], [0.36, 6, 0.20]]:
		for k in range(int(couronne[1])):
			var a: float = TAU * (k + 0.5) / float(couronne[1])
			var q: Vector3 = c + Vector3(cos(a), 0, sin(a)) * R * float(couronne[0])
			for dy2 in [-0.155, 0.155]:
				RemonteeKit.cylindre(g, couronne[2], couronne[2], 0.006, Transform3D(Basis.IDENTITY, q + Vector3(0, dy2, 0)), "noir_mat", 18)
	RemonteeKit.cylindre(g, 0.50, 0.50, 0.46, Transform3D(Basis.IDENTITY, c), m, 24)
	for k in range(12):
		var a2: float = TAU * k / 12.0
		RemonteeKit.cylindre(g, 0.025, 0.025, 0.50, Transform3D(Basis.IDENTITY, c + Vector3(cos(a2), 0, sin(a2)) * 0.40), "acier", 6)
	_coupe_poulie = g.get_child_count()          # la suite (arbre, bâti) ne tourne pas
	RemonteeKit.cylindre(g, 0.20, 0.20, 0.30, Transform3D(Basis.IDENTITY, c + Vector3(0, 0.38, 0)), "acier", 16)
	RemonteeKit.boite_en(g, Vector3(1.8, 0.7, 2.0), c + Vector3(0, 0.88, 0), "galva_pylone")
	if aval:
		for sx in [-0.8, 0.8]:
			RemonteeKit.poutre(g, c + Vector3(sx, 1.30, -1.6), c + Vector3(sx, 1.30, 2.6), 0.18, 0.22, "galva_pylone")
		RemonteeKit.cylindre(g, 0.09, 0.09, 1.6, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 1.0, 1.9)), "acier", 12)
	else:
		RemonteeKit.boite_en(g, Vector3(1.4, 0.9, 1.4), c + Vector3(0, 1.68, 0), "peinture_anthracite")
		RemonteeKit.cylindre(g, 0.42, 0.42, 1.5, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c + Vector3(1.3, 1.68, 0)), "peinture_anthracite", 20)


# --- lanceurs : rail et pneus -----------------------------------------------------

var _pneus: Array = []      # [nœud, abscisse sur la boucle, base au repos, angle]
const R_PNEU: float = 0.21


## Dehors de la boucle (horizontal) à l'abscisse s : en ligne droite le
## côté du brin, sur la poulie la direction radiale.
func _dehors(s: float) -> Vector3:
	var p: Vector3 = _point_cable(s)[0]
	var L: float = longueur_h()
	for z in [[L_GARE, true], [-L - L_GARE, false]]:
		var zc: float = z[0]
		var dans_tour: bool = (p.z > zc) if z[1] else (p.z < zc)
		if dans_tour and absf(p.z - zc) < voie:
			var r: Vector3 = Vector3(p.x, 0, p.z - zc)
			if r.length() > 0.01:
				return r.normalized()
	return Vector3(signf(p.x) if p.x != 0.0 else 1.0, 0, 0)


## Rail des pinces débrayées et lanceur de pneus au-dessus, sur toute la
## zone de gare (lanceurs, demi-tour, partie lente). Chaque pneu tourne à
## la vitesse du véhicule à SA position : rapides à l'entrée, lents au
## milieu, rapides à la sortie (retour d'utilisateur, 22/10/2026).
func _lanceurs() -> void:
	_pneus.clear()
	if famille.begins_with("perche"):
		return
	var y_rail: float = 0.11 - 0.065 - 0.035
	for aval in [true, false]:
		var s0: float = s_gare(aval, 0.0)
		var l: float = longueur_zone(aval)
		var rail: PackedVector3Array = PackedVector3Array()
		var poutre_haut: PackedVector3Array = PackedVector3Array()
		var x: float = -1.0
		while x <= l + 1.0:
			var s: float = s0 + x
			var p: Vector3 = point(s)[0]
			var o: Vector3 = _dehors(s)
			rail.append(p + o * 0.25 + Vector3(0, y_rail, 0))
			poutre_haut.append(p + o * VehiculeRemontee.X_PLAQUE + Vector3(0, VehiculeRemontee.Y_PLAQUE + 2.0 * R_PNEU + 0.16, 0))
			x += 0.5
		var r_node: Node3D = Node3D.new()
		r_node.name = "Rail" + ("Aval" if aval else "Amont")
		add_child(r_node)
		RemonteeKit.tube(r_node, rail, 0.045, "acier", 6)
		RemonteeKit.tube(r_node, poutre_haut, 0.07, "galva_pylone", 6)
		# suspentes du lanceur à la charpente, tous les 3 m
		var k: int = 0
		while k < poutre_haut.size():
			var l_s: float = Y_CAPOT - (VehiculeRemontee.Y_PLAQUE + 2.0 * R_PNEU + 0.16)
			RemonteeKit.barre(r_node, poutre_haut[k], poutre_haut[k] + Vector3(0, l_s, 0), 0.035, "galva_pylone", 6)
			k += 6
		MeshMerge.merge(r_node, [], "Rail")
		# pneus au pas de 0,62 m
		x = 0.3
		while x < l - 0.3:
			var s2: float = s0 + x
			var pt: Array = point(s2)
			var p2: Vector3 = pt[0]
			var o2: Vector3 = _dehors(s2)
			var t2: Vector3 = (pt[1] as Vector3)
			t2.y = 0.0
			t2 = t2.normalized()
			var c: Vector3 = p2 + o2 * VehiculeRemontee.X_PLAQUE + Vector3(0, VehiculeRemontee.Y_PLAQUE + R_PNEU, 0)
			# axe du pneu = dehors (horizontal, en travers) ; il tourne dans le plan vertical de la marche
			var base: Basis = Basis(t2, o2, t2.cross(o2)).orthonormalized()
			var pn: Node3D = Node3D.new()
			pn.transform = Transform3D(base, c)
			add_child(pn)
			RemonteeKit.cylindre(pn, R_PNEU, R_PNEU, 0.14, Transform3D.IDENTITY, "caoutchouc", 18)
			RemonteeKit.cylindre(pn, 0.12, 0.12, 0.16, Transform3D.IDENTITY, "galva_pylone", 12)
			for b in range(5):
				var a2: float = TAU * b / 5.0
				RemonteeKit.cylindre(pn, 0.012, 0.012, 0.17, Transform3D(Basis.IDENTITY, Vector3(cos(a2) * 0.08, 0, sin(a2) * 0.08)), "acier_noir", 6)
			# fourche : deux flasques jusqu'à la poutre haute
			for sy in [-0.09, 0.09]:
				RemonteeKit.poutre(self, c + o2 * sy, c + o2 * sy + Vector3(0, R_PNEU + 0.16, 0), 0.05, 0.012, "galva_pylone", o2)
			MeshMerge.merge(pn, [], "Pneu")
			_pneus.append([pn, s2, base, 0.0])
			x += 0.62
			await _pause()


func _tourner_pneus(delta: float) -> void:
	for e in _pneus:
		var w: float = vitesse_en(e[1]) / R_PNEU
		e[3] = fposmod(float(e[3]) + w * delta, TAU)
		(e[0] as Node3D).transform.basis = (e[2] as Basis) * Basis(Vector3.UP, e[3])


func _dessus_traverse() -> float:
	return PyloneRemontee.DESSUS_TRAVERSE_CABINE if famille.begins_with("cabine") else PyloneRemontee.DESSUS_TRAVERSE_CABLE


func _poser_pylones() -> void:
	for i in range(pylones.size()):
		var p: Dictionary = pylones[i]
		var d: float = float(p["d"])
		var t: float = terrain(d)
		var py: PyloneRemontee = PyloneRemontee.new()
		py.numero = i + 1
		py.voie = voie
		py.sens_montee_droite = sens_droite
		py.dessus_traverse = _dessus_traverse()
		py.hauteur = _tetes[i] - t - py.dessus_traverse
		py.compo_montee = p.get("montee", [[8, "S"]])
		py.compo_descente = p.get("descente", [[8, "S"]])
		var e: float = 4.0
		py.pente = atan2(y_cable(d + e) - y_cable(d - e), 2.0 * e)
		# déviation : pente côté aval − pente côté amont (> 0 : convexe)
		py.deviation = atan2(y_cable(d) - y_cable(d - e), e) - atan2(y_cable(d + e) - y_cable(d), e)
		py.position = Vector3(0, t, -d)
		py.name = "P%d" % (i + 1)
		add_child(py)
		py.construire()
		MeshMerge.merge(py, py.mobiles, "Pylone")
		for m in py.mobiles:
			MeshMerge.merge(m, [], "Paire")
		_pyl.append([py, d])
		await _pause()
	# batteries de galets aux nez des gares (le câble y change de pente)
	for aval in [true, false]:
		_batterie_gare(aval)


func _batterie_gare(aval: bool) -> void:
	var L: float = longueur_h()
	var h: float = _h_nez[0] if aval else _h_nez[1]
	if h <= 0.0:
		return
	# au milieu de la batterie : le raccord y a la moitié de la pente de la
	# ligne, et passe h·q/4 au-dessus de l'horizontale de la gare
	var d: float = h if aval else L - h
	var q: float = _pente_nez(aval, true)
	var y_c: float = terrain(0.0 if aval else L) + H_CABLE_GARE + q * h * 0.25
	var pente_ligne: float = atan(q) if aval else -atan(q)      # > 0 : monte vers −Z
	# déviation = pente aval − pente amont ; la gare est horizontale
	var dev: float = -pente_ligne if aval else pente_ligne
	var nat: String = "C" if dev < 0.0 else "S"
	var n: int = _galets_batterie(dev)
	var py: PyloneRemontee = PyloneRemontee.new()
	py.style = "gare"
	py.voie = voie
	py.sens_montee_droite = sens_droite
	py.hauteur = y_c - terrain(d) - PyloneRemontee.DESSUS_TRAVERSE_CABLE
	py.compo_montee = [[n, nat]]
	py.compo_descente = [[n, nat]]
	py.pente = pente_ligne * 0.5
	py.deviation = dev
	py.position = Vector3(0, terrain(d), -d)
	py.name = "Batterie%s" % ("Aval" if aval else "Amont")
	add_child(py)
	py.construire()
	MeshMerge.merge(py, py.mobiles, "Batterie")
	for m in py.mobiles:
		MeshMerge.merge(m, [], "Paire")
	_pyl.append([py, d])


## Demi-écartement du câble à `dz` m du nez, en gare : de la voie de ligne
## au diamètre de la poulie (les galets de déviation suivent la même courbe).
func _x_rentre(dz: float) -> float:
	return lerpf(voie * 0.5, rayon_poulie(), smoothstep(2.0, Z_DEVIATION + 1.4, dz))


func _cable() -> void:
	# câble de la boucle (en gare il suit la poulie, en ligne la flèche)
	# en gare, le câble quitte la voie des véhicules : rentré après le nez
	# (galets de déviation), il contourne la plus petite poulie
	var pts: PackedVector3Array = PackedVector3Array()
	var L: float = longueur_h()
	var Rp: float = rayon_poulie()
	# les tronçons droits des gares (deux points seulement) sont redécoupés
	# pour que le câble suive la courbe des galets de déviation
	var source: PackedVector3Array = PackedVector3Array()
	for i in range(_boucle.size()):
		var a: Vector3 = _boucle[i]
		var b: Vector3 = _boucle[(i + 1) % _boucle.size()]
		source.append(a)
		if absf(a.y - b.y) < 1e-4 and absf(a.x - b.x) < 1e-4 and a.distance_to(b) > 1.0:
			var nb: int = int(ceil(a.distance_to(b) / 0.5))
			for k in range(1, nb):
				source.append(a.lerp(b, float(k) / nb))
	for p in source:
		var q: Vector3 = p
		for st in [[0.0, L_GARE], [-L, -L - L_GARE]]:
			var znez: float = st[0]
			var zc: float = st[1]
			var dz: float = zc - znez
			var u: float = (q.z - znez) / dz
			if u > 0.0 and absf(q.z - znez) <= absf(dz) + 0.01:
				q.x = signf(q.x) * _x_rentre(absf(q.z - znez)) if absf(q.x) > 0.01 else q.x
			elif u > 1.0:
				var r: Vector3 = Vector3(q.x, 0, q.z - zc)
				if r.length() > 0.01:
					r = r.normalized() * Rp
					q = Vector3(r.x, q.y, zc + r.z)
		pts.append(q)
	pts.append(pts[0])
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
			await _pause()
		var v: float = vitesse_en(s)
		s += v * 0.05
		t += 0.05
		garde += 1


func _ajouter_vehicule(s: float) -> void:
	var v: VehiculeRemontee = VehiculeRemontee.new()
	v.famille = famille
	v.miroir = not sens_droite
	add_child(v)
	v.construire()
	_vehicules.append([v, s])
	_placer(_vehicules.size() - 1)


func nombre_vehicules() -> int:
	return _vehicules.size()


var _dt: float = 0.0
var _pyl: Array = []            # [PyloneRemontee, d]
var _pyl_touches: Dictionary = {}


func _process(delta: float) -> void:
	if not pret:
		return
	_maj_portillons(delta)
	_dt = delta
	for i in range(_vehicules.size()):
		var s: float = _vehicules[i][1]
		_vehicules[i][1] = fposmod(s + vitesse_en(s) * delta, longueur_boucle)
		_placer(i)
	_dt = 0.0
	_galets()
	_tourner_pneus(delta)
	for pl in _poulies:
		(pl[0] as Node3D).rotation.y = fposmod((pl[0] as Node3D).rotation.y + float(pl[1]) * delta, TAU)


## Galets mobiles : la pince qui passe sur un train de galets fait descendre
## (support) ou monter (compression) chaque paire selon sa surépaisseur.
func _galets() -> void:
	var touches: Dictionary = {}
	var xm: float = _x_brin(true)
	for e in _vehicules:
		var s: float = e[1]
		var p: Vector3 = _point_cable(s)[0]
		if absf(absf(p.x) - voie * 0.5) > 0.3:
			continue                  # sur la poulie : loin des batteries
		var d: float = -p.z
		var montee: bool = signf(p.x) == signf(xm)
		for q in _pyl:
			var u: float = float(q[1]) - d
			if absf(u) < 6.0:
				(q[0] as PyloneRemontee).passage(montee, u)
				touches[[q[0], montee]] = true
	for k in _pyl_touches:
		if not touches.has(k):
			(k[0] as PyloneRemontee).repos(k[1])
	_pyl_touches = touches


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
	var bv: Basis = b
	if not sens_droite:
		bv = b * Basis.from_scale(Vector3(-1, 1, 1))
	v.transform = Transform3D(bv, pt[0])
	var z: Array = zone(s)
	# la pince suit la pente du câble ; la partie suspendue balance
	var d3: Vector3 = pt[1]
	v.inclinaison(atan2(d3.y, Vector2(d3.x, d3.z).length()))
	var montee_v: bool = signf((pt[0] as Vector3).x) == signf(_x_brin(true))
	var charge: float = 80.0 * v.places * 0.7 if (montee_v and not v.cabine) else 0.0
	if _dt > 0.0:
		var m0: float = v.masse
		v.masse = m0 + charge
		v.balancer(_dt, z[0] != "ligne")
		v.masse = m0
	# corps de collision (base directe) : suit aussi le balancement
	if i < _corps.size() and _corps[i] != null:
		var sx: float = 1.0 if sens_droite else -1.0
		var pv: Vector3 = Vector3(v.pivot.x * sx, v.pivot.y, v.pivot.z)
		var bal: Transform3D = Transform3D(Basis.from_euler(Vector3(v.phi, 0.0, v.psi * sx)), pv) * Transform3D(Basis.IDENTITY, -pv)
		(_corps[i][0] as Node3D).transform = Transform3D(b, pt[0]) * bal
	# pièces animées selon la place dans la gare
	var ouverture: float = 0.0
	var gc: float = 1.0
	if z[0] != "ligne":
		var x: float = z[1]
		var l: float = z[2]
		ouverture = clampf(minf(x, l - x) / 1.2, 0.0, 1.0)            # pince : 1,2 m pour s'ouvrir
		# garde-corps automatique : relevé à la fin de la décélération, baissé
		# au début du lanceur d'accélération (retour d'utilisateur, 23/10/2026)
		gc = 1.0 - clampf((x - (L_FREIN - 2.0)) / 2.0, 0.0, 1.0) * clampf((l - L_FREIN - x) / 2.0, 0.0, 1.0)
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
