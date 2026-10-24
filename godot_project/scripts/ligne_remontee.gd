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
var constructeur: String = ""
var annee: int = 0
var station: String = ""              # « Tignes » ou « Val d'Isère » : livrée des gares
var quartier: String = ""             # secteur du domaine (portique d'entrée)
var altitude_aval: float = 0.0
var debit: float = 0.0                # personnes / heure

var H_CABLE_GARE: float = 3.9        # câble au-dessus du quai (selon le véhicule)
const GARDE: float = 6.5              # câble ≥ terrain + GARDE en ligne
const L_GARE: float = 24.0            # du nez de gare à l'axe de la poulie (débrayable)
## Télésiège à pinces FIXES : pas de lanceurs ni de pneus, les sièges font
## le tour de la poulie à la vitesse de la ligne ; la gare se réduit au nez
## et à la poulie (retour d'utilisateur, 24/10/2026 : « TSF ça veut dire
## télésiège fixe, pas débrayable, pas de lanceur »).
const L_GARE_FIXE: float = 8.0
const L_GARE_TELESKI: float = 5.0
var l_gare: float = L_GARE


static func l_gare_pour(fam: String) -> float:
	if fam.begins_with("perche"):
		return L_GARE_TELESKI
	return L_GARE_FIXE if fam.begins_with("siege_fixe") else L_GARE


## Pinces fixes : télésièges fixes et téléskis (perches toujours sur le câble).
func fixe() -> bool:
	return famille.begins_with("siege_fixe") or teleski()


func teleski() -> bool:
	return famille.begins_with("perche")
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
	_mat_porteurs = null
	_terrassements.clear()
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
	l_gare = l_gare_pour(famille)
	if fixe():
		v_embarquement = vitesse
	_calculer_tetes()
	_preparer_nez()
	_gare(true)
	await _pause()
	_gare(false)
	await _pause()
	await _poser_pylones()
	_construire_boucle()
	if tricable():
		_charpente_3s(true)
		_charpente_3s(false)
	_cable()
	await _pause()
	await _lanceurs()
	if not famille.begins_with("perche") and VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[2] != "fixe" \
			and famille != "cabine_3s" and famille != "cabine_tph":
		_rail_ouverture(true)
		_rail_ouverture(false)
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
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	var m_v: float = masse_vehicule()                                      # kg à vide, pince comprise
	var e: float = maxf(espacement, 8.0)
	var w_desc: float = w_cable + m_v * g / e
	var w_mont: float = w_desc + 80.0 * places * g / e
	var H: float = tension_h()
	if tricable():
		# les véhicules roulent sur les porteurs (57 mm, 2 par voie)
		w_desc = 2.0 * 0.0039 * 57.0 * 57.0 * g + m_v * g / e
		w_mont = w_desc + 80.0 * places * g / e
	_a_montee = H / w_mont
	_a_descente = H / w_desc


## Masse d'un véhicule à vide (kg), pince ou chariot compris.
func masse_vehicule() -> float:
	if tricable():
		return 2950.0                       # Zeta du 3S (fiche technique)
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	return 850.0 if famille.begins_with("cabine") else 95.0 * places + 80.0


## Tension horizontale (N) du câble qui porte les véhicules : le tracteur,
## ou au 3S les deux porteurs d'une voie (ancrages fixes, ~75 t chacun).
func tension_h() -> float:
	if tricable():
		return 1500000.0
	return 300000.0 * pow(diametre_cable / 47.0, 2.0)


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
		_tetes[i] = clampf(_tetes[i], t + 6.5, t + (90.0 if tricable() or vaetvient() else 32.0))
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
	if tricable() or vaetvient():
		return
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
	_ajouter(Vector3(xd, ya, l_gare))
	for k in range(1, 24):
		var a: float = PI * float(k) / 24.0
		# demi-tour par l'arrière de la gare (+Z), de xd vers xm
		_ajouter(Vector3(-cos(a) * R * signf(xm), ya, l_gare + sin(a) * R))
	_ajouter(Vector3(xm, ya, l_gare))
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
	_ajouter(Vector3(xm, yb, -L - l_gare))
	for k in range(1, 24):
		var a2: float = PI * float(k) / 24.0
		_ajouter(Vector3(cos(a2) * R * signf(xm), yb, -L - l_gare - sin(a2) * R))
	_ajouter(Vector3(xd, yb, -L - l_gare))
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
	if fixe():
		return voie * 0.5           # le câble porte les sièges : poulie = voie
	return voie * 0.5 - RETRAIT_POULIE


func x_arret(l: float) -> float:
	if fixe():
		return l_gare + PI * voie * 0.5 + 1.0   # juste après le demi-tour
	return l - L_FREIN - 2.0          # ligne d'arrêt, encore à vitesse d'embarquement


## Abscisse (dans la zone de gare) où l'on se lève du siège.
func x_debarquement() -> float:
	return l_gare - 3.0 if fixe() else L_FREIN + 1.0


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
	if z[0] == "ligne" or fixe():
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
	var zc: float = l_gare if aval else -L - l_gare     # axe de la poulie
	var znez: float = 0.0 if aval else -L
	g.position = Vector3(0, y0, 0)
	add_child(g)
	var dz: float = zc - znez
	var zm: float = (zc + znez) * 0.5 + signf(dz) * 4.0
	var long_g: float = absf(dz) + voie * 0.5 + 3.5 + 5.0      # + aire d'attente derrière la poulie
	# dalle et quais
	# plate-forme : quai (et rampe d'accès côté portillons) sur un
	# terrassement de neige damée dont chaque talus descend jusqu'au terrain
	# réel (retour d'utilisateur, 23/10/2026 : « le soubassement de toutes tes
	# gares, c'est n'importe quoi » — des troncs de pyramide de 6,4 m de
	# profondeur fixe, qui sortaient en surplomb quand le terrain plongeait)
	g.add_child(_mesh_terrassement(_terrassement(aval), y0))
	# carénage en gélule sur colonnes, cabine du conducteur (photos des
	# gares BMF du Marmottes Express, retour d'utilisateur, 23/10/2026)
	if tricable():
		_gare_3s(g, znez, zc, aval)
	elif style_gare() == "bmf":
		_capot(g, znez, zc, aval)
		_cabine_conducteur(g, znez, dz, aval)
	else:
		# carénage du constructeur (Doppelmayr, Poma, Garaventa, fixes…)
		var gc: GareCarenage = GareCarenage.new(self)
		gc.construire(g, znez, zc, style_gare())
		if famille.begins_with("cabine"):
			gc.batiment(g, aval)          # le bâtiment de la gare remplace la cabine du conducteur
		else:
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
	for sx in ([] if fixe() else [-1.0, 1.0]):
		for k in range(3):
			var zd: float = znez + signf(dz) * (Z_DEVIATION + 0.7 * k)
			# sous le câble, côté intérieur : là où il s'enroule (convexe)
			var xd: float = sx * (_x_rentre(Z_DEVIATION + 0.7 * k) - 0.21 - diametre_cable * 0.0005)
			RemonteeKit.galet(g, Vector3(xd, H_CABLE_GARE, zd), 0.21)
			(g.get_child(g.get_child_count() - 1) as Node3D).transform.basis = Basis(Vector3.FORWARD, 0.0).scaled(Vector3.ONE * 0.21 / RollerMesh.R_BANDE)
			RemonteeKit.boite_en(g, Vector3(0.22, 0.04, 0.30), Vector3(xd, H_CABLE_GARE + 0.16, zd), "galva_pylone")
			RemonteeKit.boite_en(g, Vector3(0.10, 1.4, 0.10), Vector3(xd, H_CABLE_GARE + 0.86, zd), "galva_pylone")
	# ligne d'embarquement (bande jaune) côté montée en aval, côté descente en amont
	var xb: float = _x_brin(aval)
	var l_th: float = 2.0 * l_gare + PI * voie * 0.5
	RemonteeKit.boite_en(g, Vector3(voie * 0.5 + 0.8, 0.02, 0.12), Vector3(xb * 0.6, 0.01, znez + signf(dz) * (l_th - x_arret(l_th) + 0.5)), "jaune_securite")
	MeshMerge.merge(g, [g.get_node("Poulie")], "Gare")


# --- plate-forme de gare -----------------------------------------------------------

const PENTE_RAMPE: float = 0.10     # rampe d'accès côté portillons (10 %)
## Longueur de la rampe d'accès derrière chaque gare [aval, amont] : posée
## par RemonteesDomaine d'après le relief, pour que la piste arrive à
## niveau du quai côté portillons (retour d'utilisateur, 23/10/2026).
var rampes: Array = [0.0, 0.0]


## Distance du nez de la gare au bout du quai, côté portillons.
func bout_quai() -> float:
	var long_g: float = l_gare + voie * 0.5 + 8.5
	return (l_gare * 0.5 + 4.0) + long_g * 0.5


## Bords du quai : [demi-largeur à gauche (x−), à droite (x+), pente du
## talus à gauche, à droite (base / hauteur)]. Télésiège : côté ARRIVÉE, le
## quai s'arrête 1,6 m après le couloir des sièges et descend en pente douce
## (1 pour 6) : le skieur qui se lève glisse dessus, hors du chemin du siège
## (retour d'utilisateur, 23/10/2026).
const PENTE_DEBARQUEMENT: float = 6.0
const L_DESCENTE: float = 4.0         # longueur de la descente de débarquement (m)


func _bords_quai(aval: bool) -> Array:
	var hw: float = (voie + 10.0) * 0.5
	var bq: Array = [hw, hw, PENTE_TALUS, PENTE_TALUS]
	if famille.begins_with("siege"):
		var cote: int = 1 if _x_brin(not aval) > 0.0 else 0
		bq[cote] = voie * 0.5 + 1.6
		bq[cote + 2] = PENTE_DEBARQUEMENT
	return bq
const PENTE_TALUS: float = 1.6      # base / hauteur (environ 32°)


## Sol réel sous un point (x, z) du repère de la ligne : posé par
## RemonteesDomaine (relief affiché) ; à défaut, le profil sous l'axe.
var sol_local: Callable = Callable()
var _terrassements: Dictionary = {}


func _sol(x: float, z: float) -> float:
	if sol_local.is_valid():
		return float(sol_local.call(x, z))
	return terrain(clampf(-z, 0.0, longueur_h()))


## Terrassement d'une gare (triangles, repère de la ligne) : dessus du quai
## et de la rampe d'accès, puis un talus le long de chaque bord, qui
## descend selon sa pente jusqu'à rencontrer le terrain (échantillonné tous
## les 50 cm) et s'y enfonce de 40 cm. Mis en cache : sert au maillage et
## à la collision.
func _terrassement(aval: bool) -> PackedVector3Array:
	if _terrassements.has(aval):
		return _terrassements[aval]
	var L: float = longueur_h()
	var y0: float = terrain(0.0 if aval else L)
	var zc: float = l_gare if aval else -L - l_gare
	var znez: float = 0.0 if aval else -L
	var dz: float = zc - znez
	var zm: float = (zc + znez) * 0.5 + signf(dz) * 4.0
	var long_g: float = absf(dz) + voie * 0.5 + 3.5 + 5.0
	var sgr: float = signf(dz)                         # vers l'arrière de la gare
	var z_av: float = zm - sgr * long_g * 0.5
	var z_ar: float = zm + sgr * long_g * 0.5
	var lr: float = float(rampes[0 if aval else 1])
	var bq: Array = _bords_quai(aval)
	var xg: float = -float(bq[0])
	var xd: float = float(bq[1])
	# abscisses le long de la gare, de l'avant au bout de la rampe
	var zs: Array = []
	var n_q: int = int(ceil(long_g))
	for k in range(n_q + 1):
		zs.append(z_av + sgr * long_g * float(k) / n_q)
	if lr > 0.5:
		var n_r: int = int(ceil(lr))
		for k in range(1, n_r + 1):
			zs.append(z_ar + sgr * lr * float(k) / n_r)
	var haut := func(z: float) -> float:
		var au_dela: float = (z - z_ar) * sgr
		return y0 - maxf(au_dela, 0.0) * PENTE_RAMPE
	# pente douce (débarquement) sur L_DESCENTE m au plus, puis talus normal :
	# sinon, sur un terrain plus raide qu'elle, elle ne le rejoignait jamais
	var pied := func(p: Vector3, n: Vector3, pente: float) -> Vector3:
		var l_douce: float = L_DESCENTE if pente > PENTE_TALUS else 0.0
		var t: float = 0.0
		var y: float = p.y
		while t < 60.0:
			var q: Vector3 = p + n * t
			y = p.y - minf(t, l_douce) / pente - maxf(t - l_douce, 0.0) / PENTE_TALUS
			var g: float = _sol(q.x, q.z)
			if y <= g:
				return Vector3(q.x, g - 0.4, q.z)
			t += 0.5
		var q2: Vector3 = p + n * t
		return Vector3(q2.x, y, q2.z)
	var tri: PackedVector3Array = PackedVector3Array()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tri.append_array(PackedVector3Array([a, b, c, a, c, d]))
	# dessus
	for k in range(zs.size() - 1):
		var z0: float = zs[k]
		var z1: float = zs[k + 1]
		quad.call(Vector3(xg, haut.call(z0), z0), Vector3(xd, haut.call(z0), z0), Vector3(xd, haut.call(z1), z1), Vector3(xg, haut.call(z1), z1))
	# talus latéraux
	var bords: Array = [[xg, Vector3.LEFT, float(bq[2])], [xd, Vector3.RIGHT, float(bq[3])]]
	var pieds_cote: Array = []
	for bd in bords:
		var pts: Array = []
		for z in zs:
			var p: Vector3 = Vector3(bd[0], haut.call(z), z)
			pts.append([p, pied.call(p, bd[1], bd[2])])
		for k in range(pts.size() - 1):
			quad.call(pts[k][0], pts[k + 1][0], pts[k + 1][1], pts[k][1])
		pieds_cote.append(pts)
	# talus des deux bouts (avant, bout de la rampe), et coins
	for bout in [[0, -sgr], [zs.size() - 1, sgr]]:
		var z: float = zs[bout[0]]
		var n: Vector3 = Vector3(0, 0, bout[1])
		var nx: int = int(ceil(xd - xg))
		var pts2: Array = []
		for k in range(nx + 1):
			var p: Vector3 = Vector3(lerpf(xg, xd, float(k) / nx), haut.call(z), z)
			pts2.append([p, pied.call(p, n, PENTE_TALUS)])
		for k in range(pts2.size() - 1):
			quad.call(pts2[k][0], pts2[k + 1][0], pts2[k + 1][1], pts2[k][1])
		# coins : du sommet aux pieds des deux talus voisins
		var g0: Array = pieds_cote[0][bout[0]]
		var d0: Array = pieds_cote[1][bout[0]]
		tri.append_array(PackedVector3Array([pts2[0][0], pts2[0][1], g0[1]]))
		tri.append_array(PackedVector3Array([pts2[pts2.size() - 1][0], pts2[pts2.size() - 1][1], d0[1]]))
	_terrassements[aval] = tri
	return tri


## Maillage du terrassement (neige damée, double face, normales vers le
## haut et l'extérieur), dans le repère de la gare (posée à y0).
func _mesh_terrassement(tri: PackedVector3Array, y0: float) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector3 = Vector3.ZERO
	for p in tri:
		c += p
	c /= maxf(tri.size(), 1)
	for k in range(0, tri.size(), 3):
		var a: Vector3 = tri[k]
		var b: Vector3 = tri[k + 1]
		var d: Vector3 = tri[k + 2]
		var n: Vector3 = (b - a).cross(d - a).normalized()
		var m: Vector3 = (a + b + d) / 3.0
		var ref: Vector3 = Vector3.UP + Vector3(m.x - c.x, 0, m.z - c.z).normalized() * 0.5
		if n.dot(ref) < 0.0:
			n = -n
		# Godot : face avant dans le sens HORAIRE vue de la normale — sinon la
		# face est vue de dos et sa normale retournée (talus noirs)
		var ordre: Array = [a, b, d] if (b - a).cross(d - a).dot(n) < 0.0 else [a, d, b]
		for v in ordre:
			st.set_normal(n)
			st.add_vertex(v - Vector3(0, y0, 0))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Terrassement"
	var m2: StandardMaterial3D = (RemonteeKit.mat("neige_damee") as StandardMaterial3D).duplicate()
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.mesh = st.commit()
	mi.material_override = m2
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


## Nom de la ligne sans le type (« TSD6 du Glacier (Glacier Express) » →
## « Glacier ») : celui des portiques et des carénages.
func nom_court() -> String:
	var re: RegEx = RegEx.create_from_string("^(TS|TC|TK|TPH)[A-Z0-9]*\\s+(de la |de l'|de l’|des |du |de )?")
	var t: String = re.sub(nom_ligne, "")
	var p: int = t.find(" (")
	if p > 0:
		t = t.substr(0, p)
	return t.strip_edges()


## Famille de carénage des gares, d'après le constructeur et l'année
## (photos des gares du domaine, reportages remontees-mecaniques.net).
func style_gare() -> String:
	return GareCarenage.style_pour(constructeur, annee, famille)


## Gare du 3S de l'Olympique (photos des deux gares, reportage
## remontees-mecaniques.net) : grand bâtiment rectangulaire, soubassement et
## piliers d'angle en pierre, grandes verrières sur les côtés et au fond,
## toit sombre débordant, bandeau noir au nom de la ligne ; ouvert côté
## ligne au-dessus des cabines ; dedans, la charpente rouge qui porte les
## rails et les lanceurs autour de la poulie.
func _emprise_3s(aval: bool) -> Array:
	var L: float = longueur_h()
	var znez: float = 0.0 if aval else -L
	var sg: float = 1.0 if aval else -1.0
	var zc: float = znez + sg * l_gare
	var z_av: float = znez - sg * 1.0
	var z_ar: float = zc + sg * (voie * 0.5 + 3.0)
	var hx: float = voie * 0.5 + 3.4
	var hr: float = H_CABLE_GARE + 3.4
	return [hx, z_av, z_ar, hr, sg]


func _gare_3s(g: Node3D, znez: float, zc: float, aval: bool) -> void:
	var e: Array = _emprise_3s(aval)
	var hx: float = e[0]
	var z_av: float = e[1]
	var z_ar: float = e[2]
	var hr: float = e[3]
	var sg: float = e[4]
	var zm: float = (z_av + z_ar) * 0.5
	var lz: float = absf(z_ar - z_av)
	# toit débordant, bandeau noir, enseigne
	RemonteeKit.boite_en(g, Vector3(2.0 * hx + 1.6, 0.35, lz + 1.6), Vector3(0, hr + 0.175, zm), "peinture_anthracite")
	RemonteeKit.boite_en(g, Vector3(2.0 * hx + 1.7, 0.9, 0.12), Vector3(0, hr - 0.45, z_av - sg * 0.86), "cabine_noire")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.12, 0.9, lz + 1.7), Vector3(sx * (hx + 0.86), hr - 0.45, zm), "cabine_noire")
	if nom_ligne != "":
		var lab: Label3D = Label3D.new()
		lab.text = "Téléphérique de l'Olympique" if nom_ligne.find("Olympique") >= 0 else nom_ligne
		lab.font_size = 140
		lab.pixel_size = 0.0045
		lab.modulate = Color(1, 1, 1)
		lab.outline_size = 0
		lab.position = Vector3(0, hr - 0.45, z_av - sg * 0.93)
		lab.rotation.y = 0.0 if sg < 0.0 else PI
		g.add_child(lab)
	# piliers d'angle et trumeaux en pierre, soubassement en pierre,
	# verrières entre eux (côtés et fond) ; ouvert côté ligne
	var piliers: Array = []
	for sx in [-1.0, 1.0]:
		var n_p: int = int(ceil(lz / 7.0))
		for k in range(n_p + 1):
			piliers.append(Vector3(sx * hx, 0, lerpf(z_av, z_ar, float(k) / n_p)))
	for k in range(1, 4):
		piliers.append(Vector3(lerpf(-hx, hx, float(k) / 4.0), 0, z_ar))
	for p in piliers:
		RemonteeKit.boite_en(g, Vector3(1.1, hr, 1.1), p + Vector3(0, hr * 0.5, 0), "pierre")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(g, Vector3(0.5, 1.0, lz), Vector3(sx * hx, 0.5, zm), "pierre")
		RemonteeKit.boite_en(g, Vector3(0.06, hr - 1.0, lz), Vector3(sx * hx, 1.0 + (hr - 1.0) * 0.5, zm), "vitre_teintee")
		var n_m: int = int(lz / 1.8)
		for k in range(n_m + 1):
			var zz: float = lerpf(z_av, z_ar, float(k) / n_m)
			RemonteeKit.boite_en(g, Vector3(0.10, hr - 1.0, 0.08), Vector3(sx * hx, 1.0 + (hr - 1.0) * 0.5, zz), "noir_mat")
		RemonteeKit.boite_en(g, Vector3(0.10, 0.10, lz), Vector3(sx * hx, 1.0 + (hr - 1.0) * 0.5, zm), "noir_mat")
	RemonteeKit.boite_en(g, Vector3(2.0 * hx, 1.0, 0.5), Vector3(0, 0.5, z_ar), "pierre")
	RemonteeKit.boite_en(g, Vector3(2.0 * hx, hr - 1.0, 0.06), Vector3(0, 1.0 + (hr - 1.0) * 0.5, z_ar), "vitre_teintee")
	# fronton côté ligne, au-dessus du passage des cabines
	var h_pass: float = H_CABLE_GARE + 1.6
	RemonteeKit.boite_en(g, Vector3(2.0 * hx, hr - h_pass, 0.5), Vector3(0, h_pass + (hr - h_pass) * 0.5, z_av), "pierre")
	# poteaux rouges de la poulie et du milieu de la gare
	var rouge: String = "cabine_rouge"
	for zz2 in [zc, (znez + zc) * 0.5]:
		RemonteeKit.boite_en(g, Vector3(0.9, H_CABLE_GARE - 0.4, 0.9), Vector3(0, (H_CABLE_GARE - 0.4) * 0.5, zz2), rouge)


## Charpente rouge du 3S : poutres-caissons autour de la boucle (elles
## portent les rails et les lanceurs), poteaux jusqu'au toit — après la
## boucle, qu'elles suivent.
func _charpente_3s(aval: bool) -> void:
	var g: Node3D = Node3D.new()
	g.name = "Charpente" + ("Aval" if aval else "Amont")
	g.position = Vector3(0, terrain(0.0 if aval else longueur_h()), 0)
	add_child(g)
	var hr: float = _emprise_3s(aval)[3]
	var rouge: String = "cabine_rouge"
	for dx in [-1.1, 1.1]:
		var pts: PackedVector3Array = PackedVector3Array()
		var s0: float = s_gare(aval, -1.0)
		var l: float = longueur_zone(aval)
		var x: float = 0.0
		while x <= l + 2.0:
			var s1: float = s0 + x
			var p: Vector3 = _point_cable(s1)[0]
			var o: Vector3 = _dehors(s1)
			pts.append(p + o * dx + Vector3(0, Y_CAPOT + 0.15 - terrain(0.0 if aval else longueur_h()), 0))
			x += 1.0
		for k in range(pts.size() - 1):
			RemonteeKit.poutre(g, pts[k], pts[k + 1], 0.35, 0.55, rouge)
		var k2: int = 0
		while k2 < pts.size():
			RemonteeKit.poutre(g, pts[k2], Vector3(pts[k2].x, hr, pts[k2].z), 0.22, 0.22, rouge)
			k2 += 6
	MeshMerge.merge(g, [], "Charpente")


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
	return Vector3(xb * (voie * 0.5 + D_CAPOT + 1.8), terrain(0.0 if aval else L), znez + sg * (minf(L_FREIN, l_gare * 0.4) + 3.0))


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
		if tricable():
			h = _tetes[i] - t - 3.0
			boite.call(Vector3(clampf(h * 0.22, 4.0, 12.0), h, clampf(h * 0.22, 4.0, 12.0) * 0.6), Vector3(0, t + h * 0.5, -d))
			continue
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
		var zc: float = l_gare if aval else -L - l_gare
		var znez: float = 0.0 if aval else -L
		var dz: float = zc - znez
		var zm: float = (zc + znez) * 0.5 + signf(dz) * 4.0
		var long_g: float = absf(dz) + voie * 0.5 + 3.5 + 5.0      # + aire d'attente derrière la poulie
		var tal: CollisionShape3D = CollisionShape3D.new()
		var cc: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		cc.set_faces(_terrassement(aval))
		cc.backface_collision = true
		tal.shape = cc
		corps.add_child(tal)
		if tricable():
			boite.call(Vector3(0.9, H_CABLE_GARE, 0.9), Vector3(0, y0 + H_CABLE_GARE * 0.5, zc))
			boite.call(Vector3(0.9, H_CABLE_GARE, 0.9), Vector3(0, y0 + H_CABLE_GARE * 0.5, (znez + zc) * 0.5))
			# (murs bas et verrières sans collision : on sort de la gare à pied
			# par les côtés, comme par les passerelles réelles)
			continue
		# colonnes du carénage et cabine du conducteur (téléski : portique
		# hors de la trace, pas de colonne)
		if not teleski():
			boite.call(Vector3(1.0, H_CABLE_GARE, 1.0), Vector3(0, y0 + H_CABLE_GARE * 0.5, zc))
			boite.call(Vector3(1.0, H_CABLE_GARE + Y_CAPOT, 1.0), Vector3(0, y0 + (H_CABLE_GARE + Y_CAPOT) * 0.5, GareCarenage.z_colonne(znez, zc)))
		if famille.begins_with("cabine") and style_gare() != "bmf":
			var e: Array = GareCarenage.emprise_batiment(self, aval)
			var t: Vector3 = e[1]
			boite.call(Vector3(t.x, t.y + 4.0, t.z), (e[0] as Vector3) + Vector3(0, y0 + (t.y - 4.0) * 0.5, 0))
		else:
			boite.call(Vector3(3.0, 2.5, 3.6), _pos_cabine_conducteur(aval) + Vector3(0, 1.25, 0))
		if not teleski():
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
	var zc: float = l_gare if aval else -L - l_gare
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
	# bornes de contrôle (photos : Palafour, Paquis) : piliers gris arrondis
	# avec lecteur de forfait et petit écran, une par couloir, et une en bout
	for k in range(n + 1):
		var x: float = -W * 0.5 + k * lv
		RemonteeKit.coussin(g, Vector3(0.22, 1.10, 0.36), Transform3D(Basis.IDENTITY, Vector3(x, 0.55, 0.12)), "alu_pince", 0.10)
		RemonteeKit.boite_en(g, Vector3(0.20, 0.12, 0.012), Vector3(x, 0.92, -0.065), "noir_mat")
		RemonteeKit.boite_en(g, Vector3(0.12, 0.06, 0.006), Vector3(x, 0.93, -0.073), "vitre_bleue")
		RemonteeKit.boite_en(g, Vector3(0.10, 0.10, 0.012), Vector3(x, 0.70, -0.065), "cabine_rouge")
	for k in range(n):
		var x0: float = -W * 0.5 + k * lv
		var v: Node3D = Node3D.new()
		v.position = Vector3(x0 + 0.12, 0, 0)
		g.add_child(v)
		# vantail : cadre en tube inox, deux lisses et un montant
		var lb: float = lv - 0.26
		RemonteeKit.barre(v, Vector3(0, 0.95, 0), Vector3(lb, 0.95, 0), 0.022, "acier", 8)
		RemonteeKit.barre(v, Vector3(0, 0.55, 0), Vector3(lb, 0.55, 0), 0.018, "acier", 8)
		RemonteeKit.barre(v, Vector3(lb, 0.55, 0), Vector3(lb, 0.95, 0), 0.018, "acier", 8)
		RemonteeKit.boite_en(v, Vector3(0.05, 0.08, 0.05), Vector3(lb, 0.95, 0), "jaune_securite")
		# plaque rouge « STOP » au milieu du vantail (photo de la Datcha)
		RemonteeKit.boite_en(v, Vector3(0.36, 0.15, 0.02), Vector3(lb * 0.5, 0.75, 0), "rouge_val")
		for sz in [-1.0, 1.0]:
			var stop: Label3D = Label3D.new()
			stop.text = "STOP"
			stop.font_size = 64
			stop.pixel_size = 0.0016
			stop.outline_size = 0
			stop.double_sided = false
			stop.position = Vector3(lb * 0.5, 0.75, sz * 0.012)
			stop.rotation.y = 0.0 if sz > 0.0 else PI
			v.add_child(stop)
		vantaux.append(v)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var b: BoxShape3D = BoxShape3D.new()
		b.size = Vector3(lv - 0.10, 1.0, 0.08)
		cs.shape = b
		cs.position = Vector3(x0 + lv * 0.5, 0.5, 0)
		corps.add_child(cs)
		formes.append(cs)
	# portique d'information à l'entrée de la file, 3 m derrière les
	# portillons (photos de la Madeleine, de la Fontaine Froide et de
	# l'Aiguille Percée : voir PortiqueEntree)
	var ent: Node3D = Node3D.new()
	ent.name = "Portique"
	ent.position = Vector3(0, 0, 3.0)
	g.add_child(ent)
	PortiqueEntree.construire(ent, self, W * 0.5 + 0.9)
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
		var xa: float = l_gare + PI * voie * 0.5
		pg[3] = float(pg[3]) + delta
		for e in _vehicules:
			var z: Array = zone(e[1])
			if z[0] == ("gare_aval" if aval else "gare_amont"):
				var x: float = z[1]
				if x >= xa and x - vitesse_en(e[1]) * regime() * delta < xa:
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
	var xd: float = x_debarquement()
	if x > xd - 1.0 and x < xd + 1.0:
		return [z[0] == "gare_aval"]
	return []


## Gare où se trouve le véhicule i : "gare_aval", "gare_amont" ou "ligne".
func zone_vehicule(i: int) -> String:
	return zone(_vehicules[i][1])[0]


## Cabine i arrivée en gare et portes OUVERTES (elles s'ouvrent sur les
## 2 m qui suivent le freinage) : [gare aval ?] ou [].
func arrivee_cabine(i: int) -> Array:
	var z: Array = zone(_vehicules[i][1])
	if z[0] == "ligne":
		return []
	var x: float = z[1]
	if x > L_FREIN + 2.3 and x < L_FREIN + 5.0:
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
	var z: float = x_debarquement() if aval else (-L - x_debarquement())
	return Vector3(x + signf(x) * 1.6, terrain(0.0 if aval else L) + 0.05, z)


## Poulie de demi-tour, d'après photo (Wikimedia Commons, « Chairlift
## bullwheel ») : grande roue horizontale, jante en U garnie de caoutchouc
## au fond de la gorge (le câble y repose), huit rayons en caisson avec
## leurs semelles, anneau raidisseur, gros moyeu sur arbre vertical ; au-
## dessus, le bâti (réducteur et moteur en amont, chariot de tension en aval).
var _coupe_poulie: int = 0
var _mat_cable: ShaderMaterial = null
# poids ponctuels sur le câble (voir cable_shader : fleche_points)
var _n_appuis: int = 0
var _appuis: PackedFloat32Array = PackedFloat32Array()
var _charges: Array = [[], []]        # [montée, descente] : Vector2(d, P/H)
var _w_veh: Array = [0.0, 0.0]        # charge répartie des véhicules / H (1/m)
var _tension: float = 300000.0        # tension horizontale H (N)
var _phase_cable: float = 0.0
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
	for z in [[l_gare, true], [-L - l_gare, false]]:
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
## Ouverture de la pince à x m de l'entrée d'une zone de gare de longueur
## l : le rail d'ouverture appuie progressivement sur le galet du levier
## sur les L_OUVERTURE premiers mètres (la pince lâche le câble au début de
## la décélération), et le relâche de même à la sortie.
const L_OUVERTURE: float = 2.5


func ouverture_pince(x: float, l: float) -> float:
	if fixe():
		return 0.0
	return smoothstep(0.0, L_OUVERTURE, minf(x, l - x))


## Centre du galet du levier dans le repère de la pince (x vers l'extérieur
## de la boucle, y vers le haut) pour une ouverture t — même géométrie que
## VehiculeRemontee._levier : pivot (0,36 ; 0,20), galet à (0,14 ; 0,07),
## rotation −0,55 rad quand la pince est ouverte.
static func galet_levier(t: float) -> Vector2:
	var a: float = -0.55 * t
	var g: Vector2 = Vector2(0.14, 0.07)
	return Vector2(0.36, 0.20) + Vector2(g.x * cos(a) - g.y * sin(a), g.x * sin(a) + g.y * cos(a))


## Rail d'ouverture des pinces (retour d'utilisateur, 23/10/2026) : un fer plat
## au-dessus du galet du levier, sur toute la zone de gare ; il descend
## en rampe à l'entrée (il appuie sur le levier, comprime les ressorts et
## ouvre la mâchoire) et remonte à la sortie. Suspendu au carénage.
func _rail_ouverture(aval: bool) -> void:
	var s0: float = s_gare(aval, 0.0)
	var l: float = longueur_zone(aval)
	var r_node: Node3D = Node3D.new()
	r_node.name = "RailOuverture" + ("Aval" if aval else "Amont")
	add_child(r_node)
	var pts: PackedVector3Array = PackedVector3Array()
	var x: float = -0.8
	while x <= l + 0.8:
		var s: float = s0 + x
		var p: Vector3 = point(s)[0]
		var o: Vector3 = _dehors(s)
		var gl: Vector2 = galet_levier(ouverture_pince(clampf(x, 0.0, l), l))
		# au-dessus du galet (rayon 0,055) ; un peu plus haut avant/après la
		# zone, là où le galet arrive et repart sans toucher
		var lev: float = 0.03 * (1.0 - clampf(minf(x, l - x) / 0.8 + 1.0, 0.0, 1.0))
		pts.append(p + o * gl.x + Vector3(0, gl.y + 0.055 + 0.012 + lev, 0))
		var dans_rampe: bool = minf(x, l - x) < L_OUVERTURE + 0.5
		x += 0.2 if dans_rampe else 1.0
	# fer plat : deux tubes fins côte à côte, comme une semelle
	RemonteeKit.tube(r_node, pts, 0.022, "acier", 6)
	var k: int = 0
	while k < pts.size():
		RemonteeKit.barre(r_node, pts[k], Vector3(pts[k].x, terrain(0.0 if aval else longueur_h()) + H_CABLE_GARE + Y_CAPOT, pts[k].z), 0.018, "galva_pylone", 6)
		k += 8
	MeshMerge.merge(r_node, [], "Rail")


## Appui des pneus du lanceur (repère du véhicule : dehors, haut) : la
## plaque de friction de la pince ; au 3S, le dessus du chariot.
func _x_plaque() -> float:
	return 0.0 if tricable() else VehiculeRemontee.X_PLAQUE


func _y_plaque() -> float:
	return 0.46 if tricable() else VehiculeRemontee.Y_PLAQUE


func _lanceurs() -> void:
	_pneus.clear()
	if famille.begins_with("perche") or fixe():
		return
	var y_rail: float = 0.11 - 0.065 - 0.035
	var x_rail: float = 0.25
	if tricable():
		# rail sous les galets de gare du chariot (de part et d'autre)
		y_rail = 0.36 - 0.09 - 0.045
		x_rail = 0.62
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
			rail.append(p + o * x_rail + Vector3(0, y_rail, 0))
			poutre_haut.append(p + o * _x_plaque() + Vector3(0, _y_plaque() + 2.0 * R_PNEU + 0.16, 0))
			x += 0.5
		var r_node: Node3D = Node3D.new()
		r_node.name = "Rail" + ("Aval" if aval else "Amont")
		add_child(r_node)
		RemonteeKit.tube(r_node, rail, 0.045, "acier", 6)
		if tricable():
			var rail2: PackedVector3Array = PackedVector3Array()
			for q in range(rail.size()):
				var s3: float = s0 - 1.0 + 0.5 * q
				rail2.append(rail[q] - _dehors(s3) * 2.0 * x_rail)
			RemonteeKit.tube(r_node, rail2, 0.045, "acier", 6)
		RemonteeKit.tube(r_node, poutre_haut, 0.07, "galva_pylone", 6)
		# suspentes du lanceur à la charpente, tous les 3 m
		var k: int = 0
		while k < poutre_haut.size():
			var l_s: float = Y_CAPOT - (_y_plaque() + 2.0 * R_PNEU + 0.16)
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
			var c: Vector3 = p2 + o2 * _x_plaque() + Vector3(0, _y_plaque() + R_PNEU, 0)
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


## Détails de gare visibles (posé par RemonteesDomaine : moins de 250 m).
var details_visibles: bool = true
## Point de vue (repère de la ligne) pour le niveau de détail des véhicules.
var point_vue: Vector3 = Vector3.ZERO
var vue_active: bool = false
var _tour: int = 0
var _corps_proche: bool = true
## Corps de collision des véhicules à jour (posé par RemonteesDomaine : ligne
## à moins de 120 m) ; sinon ils sont retirés de la physique.
var collisions_actives: bool = true:
	set(v):
		if v == collisions_actives:
			return
		collisions_actives = v
		for c in _corps:
			if c != null:
				(c[0] as StaticBody3D).collision_layer = CollisionsJeu.COUCHE_VEHICULE if v else 0


func _tourner_pneus(delta: float) -> void:
	if not details_visibles:
		return
	for e in _pneus:
		var w: float = vitesse_en(e[1]) * regime() / R_PNEU
		e[3] = fposmod(float(e[3]) + w * delta, TAU)
		(e[0] as Node3D).transform.basis = (e[2] as Basis) * Basis(Vector3.UP, e[3])


## Tricâble (3S) : pylônes en treillis, deux porteurs par voie, le
## véhicule roule sur les porteurs, le tracteur passe dessous.
func tricable() -> bool:
	return famille == "cabine_3s"


## Téléphérique va-et-vient (classe Telepherique).
func vaetvient() -> bool:
	return false


## Demi-dimensions intérieures (travers, long) d'une cabine, pour y entrer.
func demi_interieur() -> Vector2:
	return Vector2(1.30, 1.25) if tricable() else Vector2(1.15, 0.80)


func _dessus_traverse() -> float:
	return PyloneRemontee.DESSUS_TRAVERSE_CABINE if famille.begins_with("cabine") else PyloneRemontee.DESSUS_TRAVERSE_CABLE


func _poser_pylones() -> void:
	if tricable():
		await _poser_pylones_treillis()
		return
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
	if tricable():
		return
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
	# le câble arrive droit (voie de ligne), s'enroule sur les galets de
	# déviation (côté INTÉRIEUR : convexe), file en ligne droite et arrive
	# tangent à la poulie (convexe aussi) — la tangente commune aux deux
	# cercles (retour d'utilisateur, 23/10/2026 : la courbe en S faisait le câble
	# concave contre des galets du mauvais côté)
	if fixe():
		return voie * 0.5
	var t: Array = _tangente_deviation()
	var R: float = voie * 0.5
	var cA: Vector2 = t[0]
	var TA: Vector2 = t[2]
	var TB: Vector2 = t[3]
	if dz <= cA.x:
		return R
	if dz <= TA.x:
		return cA.y + sqrt(maxf(R_DEVIATION * R_DEVIATION - (dz - cA.x) * (dz - cA.x), 0.0))
	if dz <= TB.x:
		return lerpf(TA.y, TB.y, (dz - TA.x) / maxf(TB.x - TA.x, 1e-4))
	var Rp: float = rayon_poulie()
	return sqrt(maxf(Rp * Rp - (dz - l_gare) * (dz - l_gare), 0.0))


## Rayon de l'enroulement du câble sur la batterie de galets de déviation.
const R_DEVIATION: float = 1.5


## Géométrie de la déviation en gare, dans le plan (u = distance au nez,
## w = demi-écartement) : [centre A des galets, centre B de la poulie,
## point de départ TA sur A, point d'arrivée TB sur B] — tangente
## extérieure commune aux deux cercles, tous deux côté intérieur du câble.
func _tangente_deviation() -> Array:
	var R: float = voie * 0.5
	var Rp: float = rayon_poulie()
	var cA: Vector2 = Vector2(Z_DEVIATION, R - R_DEVIATION)
	var cB: Vector2 = Vector2(l_gare, 0.0)
	var d: Vector2 = cB - cA
	var D: float = d.length()
	var dn: Vector2 = d / D
	var perp: Vector2 = Vector2(-dn.y, dn.x)
	if perp.y < 0.0:
		perp = -perp
	var cphi: float = clampf((R_DEVIATION - Rp) / D, -1.0, 1.0)
	var n: Vector2 = dn * cphi + perp * sqrt(1.0 - cphi * cphi)
	return [cA, cB, cA + n * R_DEVIATION, cB + n * Rp]


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
		for st in [[0.0, l_gare], [-L, -L - l_gare]]:
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
	# câble à torons du funiculaire, au diamètre de la ligne, qui défile
	_mat_cable = RemonteeKit.materiau_cable_tracteur(diametre_cable)
	if tricable():
		# 3S : le tracteur passe sous les porteurs (la boucle suit le chariot)
		for k in range(pts.size()):
			pts[k] += Vector3(0, VehiculeRemontee.Y_TRACTEUR_3S, 0)
		_porteurs(c)
		_cavaliers(c)
	_preparer_charges()
	RemonteeKit.tube(c, pts, diametre_cable * 0.0005, "cable", 8, _mat_cable)


## Câbles porteurs du 3S : deux par voie, lisses et immobiles (retour
## d'utilisateur, 23/10/2026 : « un câble lisse immobile »), du nez d'une gare à
## l'autre, sur le profil de la ligne ; ils fléchissent sous chaque véhicule
## par le même calcul que le tracteur (shader du câble, sans torons).
var _mat_porteurs: ShaderMaterial = null


## Cavaliers du 3S (fiche : 2×10) : pièces serrées sur les deux porteurs
## d'une voie, à intervalles réguliers entre les pylônes, qui soutiennent le
## tracteur sur un galet (retour d'utilisateur, 23/10/2026). Le chariot roule
## par-dessus. Ils suivent la flèche moyenne des porteurs.
const N_CAVALIERS: int = 10


func _cavaliers(parent: Node3D) -> void:
	var L: float = longueur_h()
	var appuis: Array = [0.0]
	for p in pylones:
		appuis.append(float(p["d"]))
	appuis.append(L)
	for montee in [true, false]:
		var x0: float = _x_brin(montee)
		var e: float = VehiculeRemontee.E_PORTEURS_3S * 0.5
		for k in range(N_CAVALIERS):
			var d: float = L * (k + 0.5) / N_CAVALIERS
			var proche: bool = false
			for a in appuis:
				if absf(d - float(a)) < 25.0:
					proche = true
			if proche:
				d += 30.0
			var y: float = y_cable(d, montee)
			var c: Node3D = Node3D.new()
			c.position = Vector3(x0, y, -d)
			c.rotation.x = atan2(y_cable(d + 2.0, montee) - y_cable(d - 2.0, montee), 4.0)
			parent.add_child(c)
			# deux mâchoires serrées sur les porteurs, traverse et bras
			for sx in [-1.0, 1.0]:
				RemonteeKit.boite_en(c, Vector3(0.10, 0.12, 0.34), Vector3(sx * e, 0.0, 0), "galva_pylone")
				RemonteeKit.poutre(c, Vector3(sx * e, -0.05, 0), Vector3(sx * 0.10, VehiculeRemontee.Y_TRACTEUR_3S - 0.05, 0), 0.06, 0.06, "galva_pylone")
			RemonteeKit.boite_en(c, Vector3(0.24, 0.05, 0.30), Vector3(0, VehiculeRemontee.Y_TRACTEUR_3S - 0.08, 0), "galva_pylone")
			# galet du tracteur, sous lui (axe en travers)
			RemonteeKit.galet(c, Vector3(0, VehiculeRemontee.Y_TRACTEUR_3S - 0.03 - 0.12, 0), 0.12)


func _porteurs(parent: Node3D) -> void:
	_mat_porteurs = RemonteeKit.materiau_cable_tracteur(57.0)
	_mat_porteurs.set_shader_parameter("lisse", true)
	var L: float = longueur_h()
	for montee in [true, false]:
		var x0: float = _x_brin(montee)
		for k in [-0.5, 0.5]:
			var pts: PackedVector3Array = PackedVector3Array()
			var d: float = 0.0
			while d < L:
				pts.append(Vector3(x0 + k * VehiculeRemontee.E_PORTEURS_3S, y_cable(d, montee), -d))
				d += 0.5 if d < 30.0 or d > L - 30.0 else 4.0
			pts.append(Vector3(x0 + k * VehiculeRemontee.E_PORTEURS_3S, y_cable(L, montee), -L))
			RemonteeKit.tube(parent, pts, 0.0285, "cable", 8, _mat_porteurs)


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


## Niveau de détail (posé par RemonteesDomaine) : mise à jour une image sur
## `pas_lod`, avec le temps cumulé — les lignes lointaines coûtent moins.
var pas_lod: int = 1
var _lod_k: int = 0
var _lod_acc: float = 0.0


## Temps à simuler cette image, ou −1 : on saute (niveau de détail).
func _tic_lod(delta: float) -> float:
	_lod_acc += delta
	_lod_k += 1
	if _lod_k < pas_lod:
		return -1.0
	_lod_k = 0
	var d: float = minf(_lod_acc, 0.25)
	_lod_acc = 0.0
	return d


func _process(delta: float) -> void:
	if not pret:
		return
	delta = _tic_lod(delta)
	if delta < 0.0:
		return
	_regler_vitesse(delta)
	_maj_portillons(delta)
	_dt = delta
	for i in range(_vehicules.size()):
		var s: float = _vehicules[i][1]
		_vehicules[i][1] = fposmod(s + vitesse_en(s) * regime() * delta, longueur_boucle)
	_charges_ponctuelles()
	# niveau de détail par véhicule (point de vue posé par le domaine) :
	# invisible au-delà de 700 m → pas déplacé ; 250 à 700 m → une image sur
	# quatre, sans balancement ; près → chaque image
	_tour = (_tour + 1) % 4
	for i in range(_vehicules.size()):
		_corps_proche = true
		if vue_active:
			var q: Vector3 = _point_cable(_vehicules[i][1])[0]
			var d2: float = Vector2(q.x - point_vue.x, q.z - point_vue.z).length_squared()
			_corps_proche = d2 < 60.0 * 60.0
			if d2 > 700.0 * 700.0:
				continue
			if d2 > 250.0 * 250.0:
				if (i + _tour) % 4 != 0:
					continue
				var dt0: float = _dt
				_dt = 0.0
				_placer(i)
				_dt = dt0
				continue
		_placer(i)
	_dt = 0.0
	_galets()
	_tourner_pneus(delta)
	if _mat_cable != null:
		var pas: float = 0.45 * diametre_cable / 52.0
		_phase_cable = fposmod(_phase_cable + vitesse_reelle * delta, pas)
		_mat_cable.set_shader_parameter("cable_phase", _phase_cable)
	for pl in _poulies:
		(pl[0] as Node3D).rotation.y = fposmod((pl[0] as Node3D).rotation.y + float(pl[1]) * regime() * delta, TAU)


## Appuis du câble (nez des gares, têtes de pylônes) et charges moyennes,
## pour la flèche locale sous chaque véhicule (retour d'utilisateur, 23/10/2026 :
## « tenir compte du poids ponctuel et local de chaque siège et cabine »).
func _preparer_charges() -> void:
	_appuis = PackedFloat32Array()
	for p in _points_appui():
		_appuis.append(float(p[0]))
	_n_appuis = mini(_appuis.size(), 48)
	_tension = tension_h()
	var e: float = maxf(espacement, 8.0)
	_w_veh = [_poids_vehicule(true) / e / _tension, _poids_vehicule(false) / e / _tension]
	var packs: Array = []
	for k in range(12):
		var q: Vector4 = Vector4.ZERO
		for c in range(4):
			var j: int = k * 4 + c
			q[c] = _appuis[j] if j < _n_appuis else 0.0
		packs.append(q)
	for m in _mats_charges():
		m.set_shader_parameter("appuis", PackedVector4Array(packs))
		m.set_shader_parameter("n_appuis", _n_appuis)
		m.set_shader_parameter("signe_montee", signf(_x_brin(true)))
		m.set_shader_parameter("w_m", _w_veh[0])
		m.set_shader_parameter("w_d", _w_veh[1])


func _mats_charges() -> Array:
	return [_mat_cable] if _mat_porteurs == null else [_mat_cable, _mat_porteurs]


## Poids d'un véhicule (N), passagers compris en montée — mêmes charges
## que la chaînette (_parametres_chainette).
func _poids_vehicule(montee: bool) -> float:
	var places: int = VehiculeRemontee.DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	return (masse_vehicule() + (80.0 * places if montee else 0.0)) * 9.81


## Charges du moment : chaque véhicule en ligne, sur son brin.
func _charges_ponctuelles() -> void:
	if _mat_cable == null or _n_appuis < 2:
		return
	var xm: float = signf(_x_brin(true))
	var listes: Array = [[], []]
	for e in _vehicules:
		var s: float = e[1]
		if zone(s)[0] != "ligne":
			continue
		var p: Vector3 = _point_cable(s)[0]
		var montee: bool = signf(p.x) == xm
		var l: Array = listes[0 if montee else 1]
		if l.size() < 64:
			l.append(Vector2(-p.z, _poids_vehicule(montee) / _tension))
	_charges = listes
	# par portée : chaque véhicule ne tient compte que des charges de la
	# sienne (avant : toutes les charges du brin, pour chaque véhicule)
	_charges_portee = [{}, {}]
	for k3 in range(2):
		for c in listes[k3]:
			var ip: int = _portee_de((c as Vector2).x)
			if not _charges_portee[k3].has(ip):
				_charges_portee[k3][ip] = []
			_charges_portee[k3][ip].append(c)
	for k in range(2):
		var packs: Array = []
		var l2: Array = listes[k]
		for j in range(32):
			var a: Vector2 = l2[j * 2] if j * 2 < l2.size() else Vector2.ZERO
			var b: Vector2 = l2[j * 2 + 1] if j * 2 + 1 < l2.size() else Vector2.ZERO
			packs.append(Vector4(a.x, a.y, b.x, b.y))
		for m in _mats_charges():
			m.set_shader_parameter("charges_m" if k == 0 else "charges_d", PackedVector4Array(packs))
			m.set_shader_parameter("n_charges_m" if k == 0 else "n_charges_d", l2.size())


var _charges_portee: Array = [{}, {}]


## Indice de la portée (entre deux appuis) qui contient d, ou −1.
func _portee_de(d: float) -> int:
	for i in range(_n_appuis - 1):
		if d >= _appuis[i] and d <= _appuis[i + 1]:
			return i
	return -1


## Flèche locale (m, vers le bas) en d sur un brin : même calcul que le shader.
func _fleche(d: float, montee: bool) -> float:
	var n: int = _n_appuis
	if n < 2 or d <= _appuis[0] or d >= _appuis[n - 1]:
		return 0.0
	var ip: int = _portee_de(d)
	if ip < 0:
		return 0.0
	var x1: float = _appuis[ip]
	var x2: float = _appuis[ip + 1]
	var l: float = maxf(x2 - x1, 0.01)
	var f: float = -float(_w_veh[0 if montee else 1]) * (d - x1) * (x2 - d) * 0.5
	for c in _charges_portee[0 if montee else 1].get(ip, []):
		var a: float = (c as Vector2).x
		if a <= x1 or a >= x2:
			continue
		f += (c as Vector2).y * ((d - x1) * (x2 - a) if d < a else (a - x1) * (x2 - d)) / l
	return f


# --- exploitation : poste de commande ------------------------------------------------
## Pupitre (retour d'utilisateur, 23/10/2026 : « un poste de conduite spécifique à
## chaque remontée, arrêts et redémarrages, petite, moyenne, grande vitesse,
## grande par défaut ») : comme sur un pupitre réel, marche / arrêt sur le
## frein de service, arrêt d'urgence sur le frein de poulie (à réarmer),
## référence de vitesse. Tout le mouvement suit la vitesse du câble.
const CRANS: Array = [0.4, 0.7, 1.0]          # petite, moyenne, grande vitesse
const NOMS_CRANS: Array = ["PETITE", "MOYENNE", "GRANDE"]
const A_DEMARRAGE: float = 0.25                # m/s²
const A_ARRET: float = 0.4                     # frein de service
const A_URGENCE: float = 1.5                   # frein de poulie
var etat: String = "marche"                    # marche, arret_normal, arret, urgence
var cran: int = 2
var vitesse_reelle: float = -1.0               # m/s au câble (-1 : pas encore réglée)


func regime() -> float:
	return vitesse_reelle / maxf(vitesse, 0.01) if vitesse_reelle >= 0.0 else 1.0


func _regler_vitesse(delta: float) -> void:
	if vitesse_reelle < 0.0:
		vitesse_reelle = vitesse * CRANS[cran]
	var cible: float = vitesse * CRANS[cran] if etat == "marche" else 0.0
	var a: float = A_DEMARRAGE if cible > vitesse_reelle else (A_URGENCE if etat == "urgence" else A_ARRET)
	vitesse_reelle = move_toward(vitesse_reelle, cible, a * delta)
	if etat == "arret_normal" and vitesse_reelle <= 0.0:
		etat = "arret"


func demarrer() -> void:
	if etat == "arret" or etat == "arret_normal":
		etat = "marche"


func arreter() -> void:
	if etat == "marche":
		etat = "arret_normal"


func arret_urgence() -> void:
	etat = "urgence"


## Après un arrêt d'urgence : seulement une fois la ligne arrêtée.
func rearmer() -> bool:
	if etat == "urgence" and vitesse_reelle <= 0.0:
		etat = "arret"
		return true
	return false


func regler_cran(k: int) -> void:
	cran = clampi(k, 0, CRANS.size() - 1)


## Puissance mécanique au câble (kW) : remonter le surpoids du brin montée
## (véhicules et passagers) à la vitesse du câble, plus les pertes (un
## dixième de la puissance nominale à pleine vitesse).
func puissance_kw() -> float:
	var L: float = longueur_h()
	var dh: float = terrain(L) - terrain(0.0)
	var long_c: float = sqrt(L * L + dh * dh)
	var pm: float = 0.0
	var pd: float = 0.0
	for c in _charges[0]:
		pm += (c as Vector2).y * _tension
	for c in _charges[1]:
		pd += (c as Vector2).y * _tension
	var p_nom: float = (_poids_vehicule(true) - _poids_vehicule(false)) * (long_c / maxf(espacement, 8.0)) * dh / long_c * vitesse
	return ((pm - pd) * dh / long_c * vitesse_reelle + 0.1 * p_nom * regime()) / 1000.0


## Galets mobiles : la pince qui passe sur un train de galets fait descendre
## (support) ou monter (compression) chaque paire selon sa surépaisseur.
func _poser_pylones_treillis() -> void:
	for i in range(pylones.size()):
		var p: Dictionary = pylones[i]
		var d: float = float(p["d"])
		var t: float = terrain(d)
		var py: PyloneTreillis = PyloneTreillis.new()
		py.numero = i + 1
		py.voie = voie
		py.ecart_porteurs = VehiculeRemontee.E_PORTEURS_3S
		if vaetvient():
			py.porteurs_par_voie = 1
			py.va_et_vient = true
			py.l_sabot = 6.0
		# sabots : 7 m, plus longs sur un pylône à grande déviation (le P3
		# de l'Olympique porte 40 galets par voie)
		var n_g: int = int((p.get("montee", [[6, "S"]])[0] as Array)[0])
		py.l_sabot = 6.0 if vaetvient() else clampf(n_g * 0.45, 7.0, 22.0)
		py.hauteur = _tetes[i] - t - (py.hauteur_porteurs() - py.hauteur)
		py.position = Vector3(0, t, -d)
		var e: float = 6.0
		py.pente = atan2(y_cable(d + e) - y_cable(d - e), 2.0 * e)
		py.deviation = atan2(y_cable(d) - y_cable(d - e), e) - atan2(y_cable(d + e) - y_cable(d), e)
		py.name = "P%d" % (i + 1)
		add_child(py)
		py.construire()
		MeshMerge.merge(py, [], "Pylone")
		await _pause()


func _galets() -> void:
	if tricable():
		return
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
	# en ligne : la flèche locale sous le poids des véhicules de la portée
	if _n_appuis >= 2 and zone(s)[0] == "ligne":
		var p0: Vector3 = pt[0]
		pt[0] = p0 - Vector3(0, _fleche(-p0.z, signf(p0.x) == signf(_x_brin(true))), 0)
	# cap : corde de 3 m centrée sur le véhicule — sur l'arc de la poulie
	# c'est la tangente exacte, et elle tourne continûment ; la direction du
	# segment de la boucle (polygone de 24 côtés autour de la poulie) faisait
	# tourner la cabine par crans de 7,5° (retour d'utilisateur, 23/10/2026)
	var dirh: Vector3 = (point(s + 1.5)[0] as Vector3) - (point(s - 1.5)[0] as Vector3)
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
	# corps de collision (base directe) : suit aussi le balancement — sur les
	# lignes proches seulement (déplacer des centaines de corps à chaque
	# image coûtait plus que tout le reste)
	if collisions_actives and _corps_proche and i < _corps.size() and _corps[i] != null:
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
		ouverture = ouverture_pince(x, l)
		# garde-corps automatique : relevé à la fin de la décélération, baissé
		# au début du lanceur d'accélération (retour d'utilisateur, 23/10/2026)
		# (fixe : relevé avant le débarquement, baissé après l'embarquement)
		var x_haut: float = x_debarquement() - 3.0 if fixe() else L_FREIN - 2.0
		var x_bas: float = x_arret(l) + 2.0 if fixe() else l - L_FREIN
		gc = 1.0 - clampf((x - x_haut) / 2.0, 0.0, 1.0) * clampf((x_bas - x) / 2.0, 0.0, 1.0)
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
