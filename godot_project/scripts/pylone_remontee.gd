class_name PyloneRemontee
extends Node3D
## Pylône de télésiège / télécabine débrayable, paramétrable, à poser partout.
##
## Repère local : X en travers de la ligne (vers la voie MONTÉE si le sens de
## montée est « Droite »), Y vers le haut, −Z vers l'amont. Le câble passe à
## y = hauteur_cable(), aux deux extrémités de la traverse (x = ±voie/2).
##
## Ce qui est modélisé (d'après les photos de lignes Doppelmayr / Poma des
## années 1990-2020) : massif béton et platine, fût tubulaire conique en
## tronçons boulonnés, échelle à crinoline, palier sous la tête, traverse
## caisson, passerelles en caillebotis avec garde-corps, et à chaque bout la
## TÊTE DE LIGNE : balancier au nombre réel de galets — S support (le câble
## passe dessus), C compression (dessous), SC (les deux) —, portique de
## levage au-dessus, ramasse-câble à l'extérieur, plaque du numéro.
##
## `compo_montee` / `compo_descente` : liste de groupes [nombre, "S"|"C"|"SC"]
## dans l'ordre de la ligne (ex. Col des Vés « 2S+12C+2S » →
## [[2,"S"],[12,"C"],[2,"S"]]), comme les tableaux des reportages.

@export var hauteur: float = 12.0          # du sol au DESSUS de la traverse
@export var voie: float = 6.1              # entraxe des deux brins (m)
@export var numero: int = 1
@export var pente: float = 0.0             # pente moyenne du câble au pylône (rad, > 0 : monte vers −Z)
@export var style: String = "doppelmayr"   # doppelmayr | poma | fixe | teleski | gare
## Téléski : 0 = potence en T (les deux brins) ; 1 = montée seule ; −1 =
## descente seule (virage : les deux brins ont chacun leur potence).
var cote: int = 0
## Virage du brin montée (rad) et côté de la corde (±1 en x local) : galets
## horizontaux de ce côté-là.
var virage: float = 0.0
var cote_corde: float = 0.0
@export var sens_montee_droite: bool = true
var compo_montee: Array = [[8, "S"]]
var compo_descente: Array = [[8, "S"]]
## Déviation du câble au pylône (rad) : pente côté aval − pente côté amont
## (> 0 : ligne convexe, en support). Les paires de galets se posent sur
## l'arc du câble (tangentes et hauteurs) au lieu d'une ligne droite.
var deviation: float = 0.0
## Au moins 4 galets sous le câble et 4 au-dessus quand il y en a : un train de 2 n'existe
## pas (retour d'utilisateur, 02/11/2026 ; lignes concernées : remontees_domaine.gd). « SC » compte moitié de chaque côté, donc 8.
static func compo_mini(compo: Array) -> Array:
	var c: Array = []
	var dessous: int = 0
	var dessus: int = 0
	for g in compo:
		var n: int = int(g[0]) if g[0] != null else 2
		var nat: String = String(g[1])
		c.append([n, nat])
		dessous += n if nat == "S" else (n / 2 if nat == "SC" else 0)
		dessus += n if nat == "C" else (n / 2 if nat == "SC" else 0)
	for e in c:
		var nat: String = e[1]
		if nat == "S" and dessous > 0 and dessous < 4:
			e[0] += 4 - dessous
			dessous = 4
		elif nat == "C" and dessus > 0 and dessus < 4:
			e[0] += 4 - dessus
			dessus = 4
		elif nat == "SC" and ((dessous > 0 and dessous < 4) or (dessus > 0 and dessus < 4)):
			var plus: int = maxi(4 - dessous, 4 - dessus)
			e[0] += plus * 2
			dessous += plus
			dessus += plus
	return c


## Paires de galets mobiles (à garder hors de la fusion des maillages) ; par
## brin : [nœud, position de repos, rotation de repos, z galet aval, z galet amont, s]
var mobiles: Array = []
var _paires: Dictionary = {true: [], false: []}
## Par brin (true : montée) : le câble, comme pour caler(), posé par la ligne avant construire().
var cable_repos: Dictionary = {}

const R_GALET: float = 0.21                # Ø 420 mm, la norme des débrayables
const PAS_GALET: float = 0.52              # entraxe de deux galets d'un même balancier
const R_CABLE: float = 0.0235              # Ø 47 mm (Tufs)
const DESSUS_TRAVERSE_CABLE: float = 0.95  # du dessus de la traverse à l'axe du câble
const DESSUS_TRAVERSE_COMPRESSION: float = -0.35  # compression seule : le câble passe sous les galets, à hauteur de tête
const RETRAIT_TRAVERSE: float = 0.45       # bout de la traverse en dedans du câble
const H_PORTIQUE: float = 1.55             # poutre du portique au-dessus du câble
## Le pied est sur une piste : posé par la ligne avant construire().
var matelas: bool = false
## Modèle des retours photo d'un utilisateur (07/11/2026), pour les TCD, TSD et TSF : fût continu à
## embase raidie, échelle étroite à paliers, second étage de passerelles sous les trains relié par un cadre en
## trapèze ; rien au-dessus de la potence de tête (retour d'utilisateur, 07/11/2026 : « ya pas de haubanage ni de mât »).
var modele_2026: bool = false
## Télécabines : traverse remontée au pivot du train support — à 0,95 m,
## elle était à hauteur du toit et les cabines passaient au travers
## (retour d'utilisateur, 22/10/2026).
const DESSUS_TRAVERSE_CABINE: float = 0.62
var dessus_traverse: float = DESSUS_TRAVERSE_CABLE


var _construit: bool = false
## Fût incliné sur les fortes pentes, tête perpendiculaire au fût ; le massif, posé au sol,
## s'incline avec le fût ; le câble reste au même endroit. Règle ESTIMÉE sur une seule vue de côté (arête d'une ligne
## Garaventa, 3 pylônes : fût ≈ 0,8 à 1 × pente locale du câble) ; étendue à toutes les
## lignes à fût tubulaire, sans mesure sur les autres constructeurs.
const INCLI_FACTEUR: float = 0.9
const INCLI_MAX: float = deg_to_rad(25.0)
var inclinaison: float = 0.0      # rad ; > 0 : pied côté amont (−Z), tête côté aval
var pied: Vector3 = Vector3.ZERO  # pied du fût, au sol, dans le repère du pylône
var _n: Node3D = null             # conteneur des pièces en cours de pose
var _y_pied: float = 0.0          # pied du fût dans le repère du mât (y de la tête inchangé)
var _xf_tete: Transform3D = Transform3D.IDENTITY


static func inclinaison_pour(p_pente: float) -> float:
	return clampf(p_pente * INCLI_FACTEUR, -INCLI_MAX, INCLI_MAX)


## Construit à l'entrée dans l'arbre seulement si personne ne l'a fait : un
## appel explicite à construire() juste après add_child() le refaisait (tout
## en double, et des pièces effacées restaient dans les listes).
## La ligne le construit elle-même, après l'avoir posé : pas de construction à l'entrée dans l'arbre (sur le fil
## principal, chaque pylône de ligne était construit deux fois — 3,4 ms de perdues par pylône, relevé du 07/11/2026).
var construit_par_la_ligne: bool = false


func _ready() -> void:
	if not _construit and not construit_par_la_ligne:
		construire()


func hauteur_cable() -> float:
	return hauteur + dessus_traverse


## Position (locale) de l'axe du câble au droit du pylône, côté montée ou descente.
func point_cable(montee: bool) -> Vector3:
	return Vector3(_x_brin(montee), hauteur_cable(), 0.0)


func _x_brin(montee: bool) -> float:
	var s: float = 1.0 if montee == sens_montee_droite else -1.0
	return s * voie * 0.5


func construire() -> void:
	for f in _debut_construction():
		(f as Callable).call()


## construire() en phases, `pause` attendue entre deux (construction sur le fil principal : 3 à 7 ms par pylône
## d'un seul bloc, relevé du 07/11/2026).
func construire_par_tranches(pause: Callable) -> void:
	for f in _debut_construction():
		(f as Callable).call()
		await pause.call()


## Vide le pylône et pose ce qui est immédiat (téléski, nez de gare) ; pour un pylône de ligne, rend les
## phases qui restent à appeler dans l'ordre.
var _trains: Array = []     # (construction en phases) trains posés, en attente de leur structure


func _debut_construction() -> Array:
	_construit = true
	_trains.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_n = self
	mobiles.clear()
	_paires = {true: [], false: []}
	if style == "teleski":
		_construire_teleski()
		return []
	if style == "gare":
		# batterie de galets au nez d'une gare : le câble y passe de
		# l'horizontale de la gare à la pente de la ligne (retour d'utilisateur,
		# 22/10/2026 : « un angle entre la gare et le câble, et pas de
		# galets pour changer la pente »)
		# pylône de nez : comme en ligne, un fût central et une traverse qui
		# porte les deux trains (avant : un poteau sous chaque train, dans le
		# passage des sièges — retour d'utilisateur, 24/10/2026)
		# (compression comprise : sans poteau, ses galets restaient en lévitation au-dessus du sol)
		_massif(0.40)
		RemonteeKit.cylindre(self, 0.36, 0.32, hauteur - 0.4, Transform3D(Basis.IDENTITY, Vector3(0, (hauteur - 0.4) * 0.5, 0)), "peinture_gris", 18)
		RemonteeKit.boite_en(self, Vector3(voie + 0.55, 0.40, 0.42), Vector3(0, hauteur - 0.20, 0), "peinture_gris")
		for montee in [true, false]:
			_train(montee)
		return []
	var h: float = hauteur
	var r1: float = 0.40                              # rayon en tête
	var r0: float = r1 + 0.06 + h * 0.004             # tronçons plus gros vers le pied
	if modele_2026:
		# fût plus mince, à peine conique (photos)
		r1 = 0.34
		r0 = r1 + 0.03 + h * 0.002
	var y_tete: float = h - 0.75                      # dessous de la chaise de tête
	var base: Basis = Basis(Vector3.RIGHT, inclinaison)
	var haut: Vector3 = Vector3(0, h, 0)
	_xf_tete = Transform3D(base, haut - base * haut)
	_y_pied = h - pied.distance_to(haut) if inclinaison != 0.0 else 0.0
	var socle: Node3D = Node3D.new()
	socle.name = "Socle"
	socle.transform = Transform3D(base, pied)
	add_child(socle)
	var mat: Node3D = Node3D.new()
	mat.name = "Mat"
	mat.transform = _xf_tete
	add_child(mat)
	return [
		func() -> void:
			_n = socle
			_massif(r0)
			if matelas:
				# sur la piste : matelas de protection autour du pied
				RemonteeKit.cylindre(_n, r0 + 0.20, r0 + 0.20, 2.4, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0)), "matelas_piste", 14)
			_n = mat
			_fut(r0, r1, y_tete),
		func() -> void:
			_n = mat
			_echelle(r0, r1, y_tete),
		func() -> void:
			_n = mat
			_chaise_et_traverse(r1, y_tete),
		func() -> void:
			_n = self
			_trains.append(_train_galets(true)),
		func() -> void:
			_n = self
			_trains.append(_train_galets(false)),
		func() -> void:
			for t in _trains:
				_n = self
				_train_structure(t)
			_trains.clear(),
		func() -> void:
			_n = mat
			_portique()
			_plaques(r0, r1, y_tete)
			_n = self,
	]


## Massif béton affleurant, platine et tiges d'ancrage.
func _massif(r0: float) -> void:
	# En ligne, le béton descend plus bas : sur un dévers, un coin du massif se décolle du sol
	# (1,09 m au pire, mesuré sur toutes les lignes) ; la part enterrée ne se voit pas.
	var prof: float = 0.55 if style == "gare" else 1.75
	RemonteeKit.boite_en(_n, Vector3(2.0, 0.25 + prof, 2.0), Vector3(0, (0.25 - prof) * 0.5, 0), "beton")
	RemonteeKit.cylindre(_n, r0 + 0.28, r0 + 0.28, 0.06, Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)), "galva_pylone", 28)
	for k in range(12):
		var a: float = TAU * (k + 0.5) / 12.0
		var q: Vector3 = Vector3(cos(a) * (r0 + 0.18), 0.34, sin(a) * (r0 + 0.18))
		RemonteeKit.cylindre(_n, 0.022, 0.022, 0.14, Transform3D(Basis.IDENTITY, q), "galva_patine", 6)
		RemonteeKit.cylindre(_n, 0.038, 0.038, 0.035, Transform3D(Basis.IDENTITY, q + Vector3(0, -0.02, 0)), "galva_patine", 6)
		# goussets de pied entre les tiges
		if k % 3 == 0:
			var d: Vector3 = Vector3(cos(a), 0, sin(a))
			RemonteeKit.poutre(_n, d * (r0 + 0.10) + Vector3(0, 0.31, 0), d * (r0 + 0.07) + Vector3(0, 0.75, 0), 0.02, 0.20,
				"galva_pylone", d)


## Fût tubulaire galvanisé : manchon conique au pied, tronçons de ~6 m d'un diamètre chacun, plus gros vers le bas,
## reliés par une couronne boulonnée et un court chanfrein.
func _fut(r0: float, r1: float, y_tete: float) -> void:
	var y0: float = _y_pied + 0.31
	if modele_2026:
		# un seul tube légèrement conique, sans couronnes ; embase à raidisseurs triangulaires
		RemonteeKit.cylindre(_n, r0, r1, y_tete - y0, Transform3D(Basis.IDENTITY, Vector3(0, (y0 + y_tete) * 0.5, 0)), "galva_pylone", 24)
		for k in range(8):
			var a: float = TAU * (k + 0.5) / 8.0
			var d: Vector3 = Vector3(cos(a), 0, sin(a))
			RemonteeKit.poutre(_n, d * (r0 + 0.16) + Vector3(0, y0 + 0.02, 0), d * (r0 - 0.01) + Vector3(0, y0 + 0.62, 0), 0.025, 0.24, "galva_pylone", d)
		return
	var manchon: float = minf(1.6, (y_tete - y0) * 0.25)
	RemonteeKit.cylindre(_n, r0 + 0.10, r0, manchon, Transform3D(Basis.IDENTITY, Vector3(0, y0 + manchon * 0.5, 0)), "galva_pylone", 24)
	var y1: float = y0 + manchon
	var n: int = maxi(1, int(ceil((y_tete - y1) / 6.0)))
	for i in range(n):
		var ya: float = y1 + (y_tete - y1) * float(i) / n
		var yb: float = y1 + (y_tete - y1) * float(i + 1) / n
		var r: float = lerpf(r0, r1, float(i) / maxf(n - 1, 1))
		var r_bas: float = lerpf(r0, r1, float(i - 1) / maxf(n - 1, 1)) if i > 0 else r
		var ch: float = 0.18 if i > 0 else 0.0
		if ch > 0.0:
			RemonteeKit.cylindre(_n, r_bas, r, ch, Transform3D(Basis.IDENTITY, Vector3(0, ya + ch * 0.5, 0)), "galva_pylone", 24)
		RemonteeKit.cylindre(_n, r, r, yb - ya - ch, Transform3D(Basis.IDENTITY, Vector3(0, (ya + ch + yb) * 0.5, 0)), "galva_pylone", 24)
		RemonteeKit.cylindre(_n, r_bas + 0.035, r_bas + 0.035, 0.09, Transform3D(Basis.IDENTITY, Vector3(0, ya, 0)), "acier", 24)


## Échelle droite à montants (pas de crinoline sur les lignes récentes : un
## rail antichute), sur pattes boulonnées au fût, côté aval.
## Échelle praticable (bouton GRIMPER, déchaussé) : bas et haut, repère du pylône, et sa face (+Z du mât).
var a_echelle: bool = false
var echelle_bas: Vector3 = Vector3.ZERO
var echelle_haut: Vector3 = Vector3.ZERO


## Point de l'échelle, ou de son prolongement vers le pied du mât (fût incliné), à l'altitude y.
func echelle_a_hauteur(y: float) -> Vector3:
	var b: Vector3 = global_transform * echelle_bas
	var u: Vector3 = (global_transform * echelle_haut) - b
	return b + u * minf((y - b.y) / maxf(u.y, 0.01), 0.0)


func _echelle(r0: float, r1: float, y_tete: float) -> void:
	var y0: float = _y_pied + 1.9
	var y1: float = hauteur - 0.05
	var zr := func(y: float) -> float:
		return lerpf(r0, r1, clampf((y - _y_pied - 0.31) / (y_tete - _y_pied - 0.31), 0.0, 1.0)) + 0.24
	a_echelle = true
	echelle_bas = _xf_tete * Vector3(0, y0, zr.call(y0))
	echelle_haut = _xf_tete * Vector3(0, y1, zr.call(y1))
	var lx: float = 0.15 if modele_2026 else 0.21
	for sx in [-lx, lx]:
		RemonteeKit.poutre(_n, Vector3(sx, y0, zr.call(y0)), Vector3(sx, y1, zr.call(y1)), 0.06, 0.012, "galva_pylone", Vector3.BACK)
	var y: float = y0 + 0.14
	while y < y1 - 0.1:
		RemonteeKit.barre(_n, Vector3(-lx, y, zr.call(y)), Vector3(lx, y, zr.call(y)), 0.013, "galva_pylone", 6)
		y += 0.28
	if modele_2026:
		# paliers de repos tous les 6 m : plateau ajouré sur le côté de l'échelle, garde-corps en arceau
		var yq: float = y0 + 6.0
		while yq < y_tete - 2.0:
			var zq: float = zr.call(yq)
			_passerelle(Vector3(0.48, yq, zq - 0.05), Vector3(0.6, 0.0, 0.55))
			RemonteeKit.barre(_n, Vector3(0.78, yq, zq - 0.32), Vector3(0.78, yq + 1.0, zq - 0.32), 0.018, "galva_pylone", 6)
			RemonteeKit.barre(_n, Vector3(0.78, yq + 1.0, zq - 0.32), Vector3(0.78, yq + 1.0, zq + 0.22), 0.018, "galva_pylone", 6)
			RemonteeKit.barre(_n, Vector3(0.78, yq, zq + 0.22), Vector3(0.78, yq + 1.0, zq + 0.22), 0.018, "galva_pylone", 6)
			yq += 6.0
	# rail antichute au milieu
	RemonteeKit.poutre(_n, Vector3(0, y0, zr.call(y0) + 0.01), Vector3(0, y1, zr.call(y1) + 0.01), 0.035, 0.02, "galva_patine", Vector3.BACK)
	# pattes de fixation tous les 1,5 m
	var yp: float = y0 + 0.4
	while yp < y_tete:
		var rr: float = zr.call(yp) - 0.24
		for sx in [-0.21, 0.21]:
			RemonteeKit.poutre(_n, Vector3(sx * 0.6, yp, rr - 0.02), Vector3(sx, yp, zr.call(yp)), 0.04, 0.012, "galva_pylone")
		yp += 1.5


## Chaise de tête (caisson sur le fût) et traverse : deux poutres en I
## parallèles jusqu'au droit des câbles, caillebotis de part et d'autre,
## garde-corps en arceaux.
func _chaise_et_traverse(r1: float, y_tete: float) -> void:
	var h: float = hauteur
	# chaise cylindrique en haut du fût, sous la traverse
	RemonteeKit.cylindre(_n, r1 + 0.04, r1 + 0.04, 0.09, Transform3D(Basis.IDENTITY, Vector3(0, y_tete, 0)), "acier", 24)
	RemonteeKit.cylindre(_n, r1 + 0.02, r1 + 0.02, h - 0.40 - y_tete, Transform3D(Basis.IDENTITY, Vector3(0, (y_tete + h - 0.40) * 0.5, 0)), "galva_pylone", 24)
	# la traverse s'arrête en dedans des câbles : les trains de galets
	# pendent en porte-à-faux au-delà de ses bouts, sous leur console (photo
	# Commons « Laterns-Gapfohl … pylons », vue dans l'axe ; retour d'utilisateur,
	# 25/10/2026 : « les galets sont à l'extérieur des pylônes »)
	var xe: float = voie * 0.5 - RETRAIT_TRAVERSE
	# traverse en caisson, renforts en biseau de la chaise jusqu'au milieu de chaque bras
	RemonteeKit.boite_en(_n, Vector3(2.0 * xe, 0.42, 0.62), Vector3(0, h - 0.21, 0), "galva_pylone")
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(_n, Vector3(0.03, 0.46, 0.90), Vector3(sx * (xe + 0.015), h - 0.21, 0), "galva_pylone")
		RemonteeKit.poutre(_n, Vector3(sx * r1 * 0.6, y_tete + 0.10, 0), Vector3(sx * xe * 0.62, h - 0.42, 0), 0.50, 0.12, "galva_pylone", Vector3.UP)
	# caillebotis : bande centrale de part et d'autre de la traverse
	# (modèle 2026, compression : la traverse est au niveau des galets, sans garde-corps — trois étages de
	# garde-corps faisaient une cage autour du train ; on y travaille depuis le caillebotis sous le train)
	var rambardes: bool = not (modele_2026 and dessus_traverse < 0.0)
	for sz in [-1.0, 1.0]:
		_passerelle(Vector3(0, h + 0.02, sz * 0.80), Vector3(2.0 * xe - 1.2, 0.0, 0.72))
		if rambardes:
			_rambarde(Vector3(-xe + 0.6, h + 0.02, sz * 1.14), Vector3(xe - 0.6, h + 0.02, sz * 1.14))
	# garde-corps refermé aux deux bouts, échelle courte du caisson à la traverse (photos)
	for sx in [-1.0, 1.0]:
		if rambardes:
			_rambarde(Vector3(sx * (xe - 0.6), h + 0.02, -1.14), Vector3(sx * (xe - 0.6), h + 0.02, 1.14))
	for sx in [-0.17, 0.17]:
		RemonteeKit.barre(_n, Vector3(sx, y_tete, r1 + 0.05), Vector3(sx, h + 1.05, 1.18), 0.016, "galva_pylone", 6)


## Portique de levage sur toute la largeur : poutre haute au-dessus des câbles, deux jambes obliques jusqu'à la
## traverse, échelle au centre et plaque de numéro au milieu de la poutre.
func _portique() -> void:
	var xe: float = voie * 0.5 - RETRAIT_TRAVERSE
	var xb: float = voie * 0.5 + 0.25
	var yb: float = hauteur_cable() + H_PORTIQUE
	var h: float = hauteur
	RemonteeKit.poutre(_n, Vector3(-xb, yb, 0), Vector3(xb, yb, 0), 0.24, 0.20, "galva_pylone")
	for sx in [-1.0, 1.0]:
		RemonteeKit.poutre(_n, Vector3(sx * xe * 0.62, h, 0), Vector3(sx * xb * 0.84, yb - 0.08, 0), 0.14, 0.14, "galva_pylone", Vector3.BACK)
		RemonteeKit.barre(_n, Vector3(sx * 0.21, h, 0.33), Vector3(sx * 0.21, yb, 0.12), 0.022, "galva_pylone", 6)
	var y: float = h + 0.25
	while y < yb - 0.1:
		var z: float = lerpf(0.33, 0.12, (y - h) / (yb - h))
		RemonteeKit.barre(_n, Vector3(-0.21, y, z), Vector3(0.21, y, z), 0.012, "galva_pylone", 5)
		y += 0.30
	RemonteeKit.boite_en(_n, Vector3(0.44, 0.28, 0.02), Vector3(0, yb + 0.24, 0.0), "blanc_plaque")
	# (texte figé, calculé sur le fil de construction : un Label3D y renvoyait sa mise en forme au fil principal)
	var lab: MeshInstance3D = RemonteeKit.texte_fige(_n, "%02d" % numero, 90, 0.0024, Color(0.05, 0.05, 0.05))
	lab.position = Vector3(0, yb + 0.24, 0.012)
	lab.name = "NumeroPortique"


## Passerelle ajourée, à plat, dans le sens le plus long de `taille` : deux longerons et des
## barreaux. Une plaque pleine se voyait de loin comme un rectangle gris à côté des galets.
func _passerelle(c: Vector3, taille: Vector3) -> void:
	var sens_x: bool = taille.x >= taille.z
	var lo: float = taille.x if sens_x else taille.z
	var la: float = taille.z if sens_x else taille.x
	for k in [-0.5, 0.5]:
		var q: Vector3 = c + (Vector3(0, 0, k * la) if sens_x else Vector3(k * la, 0, 0))
		RemonteeKit.boite_en(_n, Vector3(lo, 0.05, 0.04) if sens_x else Vector3(0.04, 0.05, lo), q, "galva_pylone")
	var n: int = maxi(2, int(lo / 0.45))
	for i in range(n + 1):
		var u: float = (float(i) / n - 0.5) * lo
		var q2: Vector3 = c + (Vector3(u, 0, 0) if sens_x else Vector3(0, 0, u))
		RemonteeKit.boite_en(_n, Vector3(0.03, 0.03, la) if sens_x else Vector3(la, 0.03, 0.03), q2, "caillebotis")


## Poutre en I de a à b (âme verticale).
func _poutre_i(a: Vector3, b: Vector3, ht: float, larg: float) -> void:
	var m: String = "galva_pylone"
	RemonteeKit.poutre(_n, a + Vector3(0, ht * 0.5, 0), b + Vector3(0, ht * 0.5, 0), larg, 0.022, m)
	RemonteeKit.poutre(_n, a - Vector3(0, ht * 0.5, 0), b - Vector3(0, ht * 0.5, 0), larg, 0.022, m)
	RemonteeKit.poutre(_n, a, b, 0.016, ht, m)


## Garde-corps : montants, lisse haute et sous-lisse, arceaux aux bouts.
func _rambarde(a: Vector3, b: Vector3, ht: float = 1.05) -> void:
	var l: float = a.distance_to(b)
	var n: int = maxi(1, int(ceil(l / 1.1)))
	for k in range(n + 1):
		var p: Vector3 = a.lerp(b, float(k) / n)
		RemonteeKit.barre(_n, p, p + Vector3(0, ht, 0), 0.02, "galva_pylone", 6)
	RemonteeKit.barre(_n, a + Vector3(0, ht, 0), b + Vector3(0, ht, 0), 0.024, "galva_pylone", 8)
	RemonteeKit.barre(_n, a + Vector3(0, ht * 0.52, 0), b + Vector3(0, ht * 0.52, 0), 0.018, "galva_pylone", 6)
	# plinthe dans le sens de la rambarde (posée toujours en X, elle dépassait en travers des trains de galets)
	var en_x: bool = absf(b.x - a.x) >= absf(b.z - a.z)
	RemonteeKit.boite_en(_n, Vector3(l, 0.10, 0.01) if en_x else Vector3(0.01, 0.10, l), (a + b) * 0.5 + Vector3(0, 0.07, 0), "galva_pylone")


## Train de galets d'un brin, au nombre réel (groupes [n, "S"|"C"|"SC"]) :
## galets par paires entre deux flasques boulonnées sur les axes ; les
## paires s'articulent sur des palonniers, puis sur la poutre maîtresse qui
## pivote sur sa console (support : sous le câble, posée sur la traverse ;
## compression : au-dessus, pendue au portique). Ramasse-câbles le long, à
## l'extérieur ; portique de levage au-dessus ; caillebotis autour.
func _train(montee: bool) -> void:
	_train_structure(_train_galets(montee))


## Première moitié de _train (les paires de galets, posées sur le câble : le plus long) ; rend ce qu'il faut à
## _train_structure.
func _train_galets(montee: bool) -> Array:
	var x: float = _x_brin(montee)
	var compo: Array = compo_montee if montee else compo_descente
	var tete: Node3D = Node3D.new()
	tete.name = "TeteMontee" if montee else "TeteDescente"
	tete.position = Vector3(x, hauteur_cable(), 0)
	tete.rotation.x = pente
	add_child(tete)
	var dessous: Array = []     # z des galets sous le câble (support)
	var dessus: Array = []      # au-dessus (compression)
	var n_pos: int = 0
	for g in compo:
		var nat: String = String(g[1])
		var n: int = int(g[0]) if g[0] != null else 2
		n_pos += n if nat != "SC" else n / 2
	var L: float = maxf(1, n_pos - 1) * PAS_GALET
	var z: float = L * 0.5
	for g in compo:
		var nat: String = String(g[1])
		var n: int = int(g[0]) if g[0] != null else 2
		for k in range(n if nat != "SC" else n / 2):
			if nat in ["S", "SC"]:
				dessous.append(z)
			if nat in ["C", "SC"]:
				dessus.append(z)
			z -= PAS_GALET
	var dy: float = R_GALET + R_CABLE
	var ext: float = signf(x) if x != 0.0 else 1.0         # extérieur de la voie
	for liste in [[dessous, -1.0], [dessus, 1.0]]:
		var zs: Array = liste[0]
		var s: float = liste[1]
		if zs.is_empty():
			continue
		var y_axe: float = s * dy
		# paires de galets : chacune pivote sur son axe de palonnier, posée
		# sur l'arc du câble (courbure κ = déviation / longueur du train)
		var kappa: float = deviation / maxf(L, 0.5)
		var pivots: Array = []
		var k2: int = 0
		while k2 < zs.size():
			var za: float = zs[k2]
			var zb: float = zs[mini(k2 + 1, zs.size() - 1)]
			var zp: float = (za + zb) * 0.5
			var piv: Node3D = Node3D.new()
			piv.name = "Paire%s%d" % ["S" if s < 0.0 else "C", k2 / 2]
			var base_pos: Vector3 = Vector3(0, y_axe + s * 0.11 - kappa * zp * zp * 0.5, zp)
			var base_rot: float = kappa * zp
			# posée sur le câble lui-même quand la ligne le donne (les têtes sont penchées, et les deux
			# brins n'ont pas la même chaînette : l'arc ci-dessus s'en écartait jusqu'à 20 cm)
			var cable_brin: Callable = cable_repos.get(montee, Callable())
			if cable_brin.is_valid():
				var pose: Array = _pose_paire(tete.rotation.x, zp, s, cable_brin, absf(za - zb) * 0.5)
				base_pos = pose[0]
				base_rot = pose[1]
			piv.position = base_pos
			piv.rotation.x = base_rot
			tete.add_child(piv)
			# même écartement, même sens : même maillage, partagé (MeshMerge.poser_partage)
			if not MeshMerge.poser_partage(piv, "paire|%.1f|%.3f|%d" % [s, zb - za, int(modele_2026)]):
				RemonteeKit.galet(piv, Vector3(0, -s * 0.11, za - zp), R_GALET, 0.10, "moyeu", "garniture", modele_2026)
				if zb != za:
					RemonteeKit.galet(piv, Vector3(0, -s * 0.11, zb - zp), R_GALET, 0.10, "moyeu", "garniture", modele_2026)
				if modele_2026:
					_flasques_2026(piv, s, za - zp, zb - zp, "galva_sombre")
				else:
					# flasques de part et d'autre des joues (comme les fourches du funiculaire)
					var fy: float = RollerMesh.FLASQUE_Y * R_GALET / RollerMesh.R_BANDE
					for sx in [-fy, fy]:
						RemonteeKit.poutre(piv, Vector3(sx, -s * 0.11, za - zp + 0.14), Vector3(sx, -s * 0.11, zb - zp - 0.14), 0.016, 0.13, "galva_patine")
				RemonteeKit.cylindre(piv, 0.035, 0.035, 0.26, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), "acier_noir", 8)
			mobiles.append(piv)
			(_paires[montee] as Array).append([piv, base_pos, base_rot, za, zb, s])
			pivots.append(zp)
			k2 += 2
		_palonniers(tete, pivots, y_axe, s)
		if modele_2026 and s > 0.0:
			_details_compression(tete, zs, y_axe, s, ext)
		# ramasse-câbles : plaques échancrées à l'extérieur, entre les galets
		for k in range(0, zs.size() - 1, 2):
			var zm: float = (float(zs[k]) + float(zs[k + 1])) * 0.5
			RemonteeKit.boite_en(tete, Vector3(0.012, 0.30, 0.10), Vector3(ext * 0.15, y_axe + s * 0.02, zm), "galva_patine")
			RemonteeKit.boite_en(tete, Vector3(0.10, 0.012, 0.10), Vector3(ext * 0.20, y_axe - s * 0.13, zm), "galva_patine")
	return [x, tete, dessous, dessus, dy, ext, L]


## Seconde moitié de _train : console, suspente, passerelles et garde-corps.
func _train_structure(c: Array) -> void:
	var x: float = c[0]
	var tete: Node3D = c[1]
	var dessous: Array = c[2]
	var dessus: Array = c[3]
	var dy: float = c[4]
	var ext: float = c[5]
	var L: float = c[6]
	# console : de la traverse au pivot de la poutre maîtresse (support)
	var y_trav: float = hauteur - hauteur_cable()           # dessus de traverse, repère de la tête
	if not dessous.is_empty():
		# console en équerre : montant au bout de la traverse (côté intérieur),
		# bras jusqu'au pivot sous le câble
		var y_piv: float = -dy - 0.36
		var xc: float = -ext * (RETRAIT_TRAVERSE - 0.11)
		RemonteeKit.boite_en(tete, Vector3(0.22, absf(y_trav - y_piv) + 0.10, 0.30), Vector3(xc, (y_trav + y_piv) * 0.5, 0), "galva_pylone")
		RemonteeKit.poutre(tete, Vector3(xc, y_piv, 0), Vector3(ext * 0.05, y_piv, 0), 0.24, 0.30, "galva_pylone", Vector3.UP)
		RemonteeKit.poutre(tete, Vector3(xc, y_trav + 0.05, 0), Vector3(-ext * 0.05, y_piv - 0.10, 0), 0.10, 0.20, "galva_pylone")
		RemonteeKit.cylindre(tete, 0.07, 0.07, 0.36, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, y_piv, 0)), "acier_noir", 12)
	if style == "gare":
		# accroché à la charpente de la gare : suspente jusqu'au portique
		# (compression) ou console jusqu'au sol (support)
		if not dessus.is_empty():
			RemonteeKit.boite_en(tete, Vector3(0.16, 1.55 - dy - 0.42, 0.24), Vector3(0, (1.55 + dy + 0.42) * 0.5, 0), "galva_pylone")
			RemonteeKit.boite_en(tete, Vector3(0.40, 0.12, 0.40), Vector3(0, 1.62, 0), "galva_pylone")
		return
	var hp: float = H_PORTIQUE
	var demi: float = maxf(0.7, L * 0.5 + 0.25)
	if not dessus.is_empty():
		# suspente du train de compression au portique
		RemonteeKit.boite_en(tete, Vector3(0.16, hp - dy - 0.42, 0.24), Vector3(0, (hp + dy + 0.42) * 0.5, 0), "galva_pylone")
		RemonteeKit.cylindre(tete, 0.07, 0.07, 0.36, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, dy + 0.36, 0)), "acier_noir", 12)
	# caillebotis autour du train (côté intérieur), garde-corps côté fût
	var lc: float = 2.0 * demi + 0.6
	var mat_n: Node3D = get_node_or_null("Mat") as Node3D
	var xp: float = x - ext * 0.62
	_n = mat_n if mat_n != null else self
	var y_p: float = hauteur + 0.02
	var h_r: float = 1.05
	if modele_2026 and not dessus.is_empty():
		# compression : caillebotis SOUS le train, garde-corps bas ; posé au-dessus du câble, son garde-corps
		# enfermait les galets dans une cage (retour d'utilisateur, 07/11/2026, d'après ses photos du P1)
		y_p = hauteur_cable() - 0.85
		h_r = 0.75
	_passerelle(Vector3(xp, y_p, 0), Vector3(0.95, 0.0, lc))
	_rambarde(Vector3(xp - ext * 0.47, y_p, -lc * 0.5), Vector3(xp - ext * 0.47, y_p, lc * 0.5), h_r)
	if modele_2026:
		# second étage, plus bas, côté fût : à plus de 2 m en dedans du câble, hors du passage des sièges et des
		# cabines qui balancent (jusqu'à 3,2 m de large au 6 places) ; suspendu au premier par un cadre en trapèze
		var y2: float = hauteur - 1.6
		var xq: float = x - ext * 2.35
		# (ouvert, sans garde-corps : la passerelle haute et ses montants faisaient une cage vue de dessous —
		# retour d'utilisateur, 07/11/2026 : « les cages dessous les galets c'est pas bon »)
		_passerelle(Vector3(xq, y2, 0), Vector3(0.7, 0.0, lc))
		for sz in [-1.0, 1.0]:
			var z1: float = sz * lc * 0.5
			RemonteeKit.barre(_n, Vector3(xp - ext * 0.47, hauteur + 0.02, z1), Vector3(xq - ext * 0.35, y2, z1), 0.02, "galva_pylone", 6)
			RemonteeKit.barre(_n, Vector3(xp + ext * 0.47, hauteur + 0.02, z1), Vector3(xq + ext * 0.35, y2, z1), 0.02, "galva_pylone", 6)
	_n = self


## Train de compression du modèle 2026 (photos d'un utilisateur, P1 devant la gare) : selle en V entre deux paires (la
## pince y passe), corne relevée à chaque bout du train, plaque rattrape-câble pendue sous le câble aux bouts.
func _details_compression(tete: Node3D, zs: Array, y_axe: float, s: float, ext: float) -> void:
	var z_haut: float = float(zs[0]) + R_GALET + 0.08
	var z_bas: float = float(zs[zs.size() - 1]) - R_GALET - 0.08
	var y_c: float = y_axe - s * (R_GALET + R_CABLE)          # axe du câble, repère de la tête
	# selles en V entre les paires
	for k in range(1, zs.size() - 1, 2):
		var zm: float = (float(zs[k]) + float(zs[k + 1])) * 0.5
		for sz in [-1.0, 1.0]:
			RemonteeKit.poutre(tete, Vector3(0, y_c + s * 0.05, zm), Vector3(0, y_c + s * 0.24, zm + sz * 0.15), 0.10, 0.012, "galva_sombre", Vector3.RIGHT)
	for e in [[z_haut, 1.0], [z_bas, -1.0]]:
		var zb: float = e[0]
		var dz: float = e[1]
		# corne relevée : la pince entre et sort du train sans accrocher
		RemonteeKit.poutre(tete, Vector3(0, y_c + s * 0.06, zb), Vector3(0, y_c + s * 0.42, zb + dz * 0.32), 0.12, 0.014, "galva_sombre", Vector3.RIGHT)
		# rattrape-câble : plaque pendue sous le câble, côté extérieur
		RemonteeKit.boite_en(tete, Vector3(0.012, 0.32, 0.34), Vector3(ext * 0.07, y_c - s * 0.20, zb - dz * 0.10), "galva_sombre")
		RemonteeKit.boite_en(tete, Vector3(0.14, 0.012, 0.34), Vector3(0.0, y_c - s * 0.36, zb - dz * 0.10), "galva_sombre")


## Palonniers au-dessus des paires (2, 4, 8 paires…), jusqu'à la poutre
## maîtresse ; `s` = −1 pour un train support (structure sous les axes), +1
## pour une compression (au-dessus). `niveaux` : z des pivots des paires.
func _palonniers(tete: Node3D, niveaux: Array, y_axe: float, s: float) -> void:
	var y: float = y_axe + s * 0.11
	while niveaux.size() > 1:
		var suivants: Array = []
		var j: int = 0
		y += s * 0.13
		while j < niveaux.size():
			var a: float = niveaux[j]
			var b: float = niveaux[mini(j + 1, niveaux.size() - 1)]
			for sx in [-0.10, 0.10]:
				RemonteeKit.poutre(tete, Vector3(sx, y - s * 0.06, a + 0.06), Vector3(sx, y - s * 0.06, b - 0.06), 0.016, 0.16, "galva_pylone")
			var zp2: float = (a + b) * 0.5
			RemonteeKit.cylindre(tete, 0.04, 0.04, 0.26, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, y, zp2)), "acier_noir", 8)
			suivants.append(zp2)
			j += 2
		niveaux = suivants
	var y_piv: float = s * (R_GALET + R_CABLE + 0.36)
	RemonteeKit.boite_en(tete, Vector3(0.20, absf(y_piv - y) + 0.06, 0.24), Vector3(0, (y_piv + y) * 0.5, niveaux[0]), "galva_pylone")


# --- passage d'une pince --------------------------------------------------------

## Surépaisseur de la pince sur le câble à la distance u de son centre : le
## corps (0,03 m) puis les gaines noires qui s'amincissent jusqu'à ZÉRO à
## leur bout — c'est ce qui fait monter (compression) ou descendre (support)
## les galets en douceur.
static func surepaisseur(u: float) -> float:
	var a: float = absf(u)
	if a < 0.31:
		return 0.03
	if a < 0.65:
		return 0.03 * (0.65 - a) / 0.34
	return 0.0


## Une pince passe à la position u (le long du train, +z vers l'aval) sur le
## brin montée ou descente : chaque paire se déplace et bascule selon la
## surépaisseur sous ses deux galets.
func passage(montee: bool, u: float) -> void:
	_hors_repos[montee] = true
	for e in _paires[montee]:
		var sgn: float = e[5]
		var da: float = surepaisseur(float(e[3]) - u)
		var db: float = surepaisseur(float(e[4]) - u)
		# (paire déjà posée ainsi — le plus souvent au repos, la pince est loin :
		# rien à refaire ; un nouveau calage efface cet état)
		var etat: Vector2 = Vector2(da, db)
		if e.size() < 7:
			e.append(null)
		elif e[6] == etat:
			continue
		e[6] = etat
		var n: Node3D = e[0]
		var b: Array = _base_paire(e)
		n.position = (b[0] as Vector3) + Vector3(0, sgn * (da + db) * 0.5, 0)
		var dz: float = float(e[3]) - float(e[4])
		n.rotation.x = float(b[1]) - (sgn * (da - db) / dz if dz > 0.01 else 0.0)


## Plus de pince sur le brin : les paires reviennent au repos.
## (Rien à faire si elles y sont déjà et que le calage n'a pas bougé : la
## ligne appelle repos() à chaque image pour tous les pylônes calés.)
func repos(montee: bool) -> void:
	if not _hors_repos[montee]:
		return
	_hors_repos[montee] = false
	for e in _paires[montee]:
		var b: Array = _base_paire(e)
		(e[0] as Node3D).position = b[0]
		(e[0] as Node3D).rotation.x = b[1]
		if e.size() < 7:
			e.append(null)
		e[6] = Vector2.ZERO


## Paires d'un brin pas (ou plus) à leur position de repos : un passage, ou
## un nouveau calage, les en a écartées.
var _hors_repos: Dictionary = {true: true, false: true}


## Position et bascule d'une paire dont le pivot est au z `zp` de la tête, contre le câble. `cable` : recul
## horizontal le long de la ligne (+ vers l'aval) → hauteur du câble au-dessus de l'axe de la tête.
## La tête est penchée : son z n'est pas ce recul, l'écart valait le sinus de la pente sur tout le train.
func _pose_paire(pente_tete: float, zp: float, sgn: float, cable: Callable, demi: float) -> Array:
	var cp: float = cos(pente_tete)
	var sp: float = sin(pente_tete)
	var zw: float = zp * cp
	var yw: float = float(cable.call(zw))
	# point du câble dont le z, dans le repère de la tête, est celui de la paire
	for _i in range(3):
		zw = (zp + yw * sp) / maxf(cp, 0.2)
		yw = float(cable.call(zw))
	# la corde sous les deux galets de la paire : tous deux touchent, même sur un arc serré
	# (les galets sont à ± demi LE LONG de la paire : à l'horizontale, moins sur un câble raide)
	var e: float = maxf(demi, 0.05)
	var y1: float = float(cable.call(zw + e))
	var y2: float = float(cable.call(zw - e))
	for _j in range(2):
		var e2: float = maxf(demi, 0.05) * cos(atan2(y2 - y1, 2.0 * e))
		y1 = float(cable.call(zw + e2))
		y2 = float(cable.call(zw - e2))
		e = e2
	if demi > 0.05:
		yw = (y1 + y2) * 0.5
	var y_loc: float = yw * cp + zw * sp
	var pente_loc: float = atan2(y2 - y1, 2.0 * e) - pente_tete
	var dist: float = R_GALET + R_CABLE + 0.11
	return [Vector3(0, y_loc + sgn * dist * cos(pente_loc), zp + sgn * dist * sin(pente_loc)), pente_loc]


## Près du point de vue seulement : la roue de la paire devient un nœud qui tourne (loin, elle est fusionnée et
## fixe, ses bras cachés par un disque). 16 à 30 roues par pylône, moins de 3 pylônes à la fois.
static var _maillage_roue: ArrayMesh = null
static var _maillage_roue_ligne: ArrayMesh = null


## Flasques d'une paire, modèle 2026 (photos du 07/11/2026) : deux tôles sombres hautes, décalées du côté
## opposé au câble (elles couvrent les axes, le bas des galets reste à nu), bouts effilés au-delà des axes.
func _flasques_2026(n: Node3D, s: float, z0: float, z1: float, m: String) -> void:
	var yc: float = -s * 0.11 + s * 0.07
	for sx in [-0.105, 0.105]:          # (écartées pour les galets de 18 cm, RollerMesh.DEMI_LARG_LIGNE)
		RemonteeKit.poutre(n, Vector3(sx, yc, z0), Vector3(sx, yc, z1), 0.016, 0.22, m)
		RemonteeKit.poutre(n, Vector3(sx, yc + s * 0.03, z0), Vector3(sx, yc + s * 0.03, z0 - 0.17), 0.016, 0.12, m)
		RemonteeKit.poutre(n, Vector3(sx, yc + s * 0.03, z1), Vector3(sx, yc + s * 0.03, z1 + 0.17), 0.016, 0.12, m)
var _roues: Array = []                     # [nœud, sens de rotation autour de l'axe du galet]


func roues_tournantes(actif: bool) -> void:
	if actif != _roues.is_empty():
		return
	if modele_2026 and _maillage_roue_ligne == null:
		_maillage_roue_ligne = RollerMesh.build_galet_ligne(true)
	elif not modele_2026 and _maillage_roue == null:
		_maillage_roue = RollerMesh.build_galet(true)
	var k: float = R_GALET / RollerMesh.R_BANDE
	for montee in [true, false]:
		for e in _paires[montee]:
			var piv: Node3D = e[0]
			var s: float = e[5]
			var ancien: Node = piv.get_node_or_null("Roues")
			for c in piv.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).visible = not actif
			if not actif:
				if ancien != null:
					ancien.queue_free()
				continue
			var demi: float = (float(e[4]) - float(e[3])) * 0.5
			var n: Node3D = Node3D.new()
			n.name = "Roues"
			piv.add_child(n)
			# le cadre de la paire, sans ses roues
			var cadre: Node3D = Node3D.new()
			n.add_child(cadre)
			if not MeshMerge.poser_partage(cadre, "cadre|%.1f|%.3f|%d" % [s, demi, int(modele_2026)]):
				if modele_2026:
					_flasques_2026(cadre, s, -demi, demi, "galva_sombre")
				else:
					var fy: float = RollerMesh.FLASQUE_Y * R_GALET / RollerMesh.R_BANDE
					for sx in [-fy, fy]:
						RemonteeKit.poutre(cadre, Vector3(sx, -s * 0.11, -demi + 0.14), Vector3(sx, -s * 0.11, demi - 0.14), 0.016, 0.13, "acier_noir", Vector3.RIGHT)
				RemonteeKit.cylindre(cadre, 0.035, 0.035, 0.26, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), "acier_noir", 10)
				MeshMerge.fusion_partagee(cadre, "Cadre")
			for dz in ([-demi, demi] if demi > 0.0 else [0.0]):
				var mi: MeshInstance3D = MeshInstance3D.new()
				mi.mesh = _maillage_roue_ligne if modele_2026 else _maillage_roue
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(k, k, k)), Vector3(0, -s * 0.11, dz))
				n.add_child(mi)
				# le câble file vers l'amont (−Z) sur le brin montant, et touche le haut d'une roue dessous, le bas
				# d'une roue dessus
				_roues.append([mi, s if montee else -s])
	if not actif:
		_roues.clear()


## Le câble a parcouru R·dphi.
func tourner_roues(dphi: float) -> void:
	for r in _roues:
		(r[0] as Node3D).rotate_object_local(Vector3.UP, float(r[1]) * dphi)


## Paires calées sur le câble TEL QU'IL EST AFFICHÉ (flèche sous les
## véhicules, onde aux arrêts) : le câble rentrait dans les galets aux bouts
## des balanciers (retour d'utilisateur, 25/10/2026). `cable` : z local du
## train → hauteur du câble au-dessus de l'axe de la tête (repère du monde,
## m). Posé par la ligne, à chaque image près du point de vue.
var _cales: Dictionary = {}           # paire (Node3D) → [position, rotation]


func caler(montee: bool, cable: Callable) -> void:
	var tete: Node3D = get_node_or_null("TeteMontee" if montee else "TeteDescente")
	if tete == null:
		return
	for e in _paires[montee]:
		var n: Node3D = e[0]
		var pose: Array = _pose_paire(tete.rotation.x, (e[1] as Vector3).z, e[5], cable, absf(float(e[3]) - float(e[4])) * 0.5)
		_cales[n] = [pose[0], pose[1]]
		if e.size() >= 7:
			e[6] = null
	_hors_repos[montee] = true


## Calage venu du noyau C++ (LigneRemontee._caler_galets) : [y, z, pente] par paire, brin montant puis
## descendant, dans l'ordre de _paires ; même effet que caler().
func appliquer_calage(r: PackedFloat32Array) -> void:
	var o: int = 0
	for montee in [true, false]:
		var tete: Node3D = get_node_or_null("TeteMontee" if montee else "TeteDescente")
		if tete == null:
			o += 3 * _paires[montee].size()
			continue
		for e in _paires[montee]:
			if o + 2 >= r.size():
				return
			_cales[e[0]] = [Vector3(0, r[o], r[o + 1]), r[o + 2]]
			o += 3
			if e.size() >= 7:
				e[6] = null
		_hors_repos[montee] = true


func _base_paire(e: Array) -> Array:
	return _cales.get(e[0], [e[1], e[2]])


## Plaque bleue du numéro (comme sur les lignes Doppelmayr) et panneaux de
## consignes sous la tête, face aval.
func _plaques(r0: float, r1: float, y_tete: float) -> void:
	var yp: float = y_tete - 1.0
	var z: float = r1 + 0.012
	RemonteeKit.boite_en(_n, Vector3(0.36, 0.30, 0.02), Vector3(0.42, yp, z - 0.06), "plaque_bleue")
	var lab: MeshInstance3D = RemonteeKit.texte_fige(_n, str(numero), 110, 0.0022, Color(1, 1, 1))
	lab.position = Vector3(0.42, yp, z - 0.045)
	lab.name = "Numero"
	# panneau de consigne (pictogramme bleu sur fond blanc)
	var y2: float = y_tete - 2.2
	var r2: float = lerpf(r0, r1, (y2 - _y_pied - 0.31) / (y_tete - _y_pied - 0.31))
	RemonteeKit.boite_en(_n, Vector3(0.40, 0.45, 0.015), Vector3(-0.05, y2, r2 + 0.01), "blanc_plaque")
	RemonteeKit.cylindre(_n, 0.15, 0.15, 0.01, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.05, y2 + 0.03, r2 + 0.02)), "plaque_bleue", 20)


## Pylône de téléski en potence (photos Commons « Plan du Jeu POMA ») : fût
## tubulaire HORS de la trace, côté descente, bras horizontal au-dessus des
## deux brins avec sa jambe de force en triangle, trains de galets pendus
## sous le bras ; le câble roule sur les galets. Virage : potence d'un seul
## côté (cote ≠ 0). `hauteur` : du sol au dessus du bras.
var x_fut: float = 0.0          # position du fût (repère du pylône)
## Pylône en T (fût entre les deux brins, traverse des deux côtés) : téléskis
## autres que Poma (vidéos des Montets et du Col du Palet) ; sinon potence.
var en_t: bool = false
## Dernier pylône avant le départ d'un TKD : le train du brin retour est incliné (rad, autour de l'axe du câble)
## pour le rentrer vers la petite poulie motrice (LigneRemontee.decalage_descente).
var incline_descente: float = 0.0
## Pylône de TKD (photos du Chardonnet) : fût rond qui dépasse au-dessus du bras, bras en treillis, jambe de
## force, trains pendus sous le bras, mousse orange.
var tkd: bool = false
const DESSUS_BRAS_TELESKI: float = 0.75   # bras au-dessus du câble


const BRAS_TKD: float = 0.45      # hauteur du treillis du bras des TKD (membrure basse sous le dessus)


## Bras en treillis d'un pylône de TKD : membrures haute et basse en tubes carrés, montants aux bouts et
## au droit de chaque brin, diagonales en zigzag, jambe de force du fût au bras.
func _bras_treillis_tkd(h: float, bout: float, xs: Array) -> void:
	var m: String = "galva"
	var x0: float = x_fut + signf(bout - x_fut) * 0.15
	var yb: float = h - BRAS_TKD
	RemonteeKit.poutre(self, Vector3(x0, h - 0.04, 0), Vector3(bout, h - 0.04, 0), 0.08, 0.08, m)
	RemonteeKit.poutre(self, Vector3(x0, yb, 0), Vector3(bout, yb, 0), 0.08, 0.08, m)
	var montants: Array = [x0, bout]
	for x in xs:
		montants.append(float(x) - signf(float(x) - x_fut) * 0.12)
	montants.sort()
	for k in range(montants.size()):
		var xm: float = montants[k]
		RemonteeKit.poutre(self, Vector3(xm, yb, 0), Vector3(xm, h - 0.04, 0), 0.06, 0.06, m)
		if k > 0:
			var xp: float = montants[k - 1]
			if absf(xm - xp) > 0.3:
				var haut_gauche: bool = k % 2 == 0
				RemonteeKit.barre(self, Vector3(xp, yb if haut_gauche else h - 0.04, 0), Vector3(xm, h - 0.04 if haut_gauche else yb, 0), 0.025, m, 5)
	# jambe de force : du fût, 1,4 m sous le bras, aux deux tiers du bras
	var xj: float = lerpf(x_fut, bout, 0.65)
	RemonteeKit.poutre(self, Vector3(x_fut + signf(bout - x_fut) * 0.14, yb - 1.4, 0), Vector3(xj, yb, 0), 0.07, 0.07, m)
	# platines de fixation au fût
	for y in [yb, h - 0.04]:
		RemonteeKit.boite_en(self, Vector3(0.32, 0.14, 0.30), Vector3(x_fut, y, 0), m)


const R_POULIE_PYL_TKD: float = 0.40


## Grande poulie de pylône d'un TKD sous le câble (point d'appui `c`), dans le plan vertical de la ligne,
## inclinée de `tilt` autour du câble (rentrée du brin retour au premier pylône) ; chape jusqu'au bras en `y_bras`.
func _grande_poulie_tkd(c: Vector3, tilt: float, y_bras: float) -> void:
	var R: float = R_POULIE_PYL_TKD
	var n: Node3D = Node3D.new()
	n.name = "PoulieTKD"
	n.transform = Transform3D(Basis(Vector3.BACK, tilt), c)
	add_child(n)
	var o: Vector3 = Vector3(0, -R - 0.012, 0)          # centre : le câble repose au fond de la gorge
	RemonteeKit.tube(n, RemonteeKit.arc(o, Vector3.BACK, Vector3.UP, R, 0.0, TAU, 36), 0.03, "caoutchouc", 8)
	for dx in [-0.045, 0.045]:
		RemonteeKit.tube(n, RemonteeKit.arc(o + Vector3(dx, 0, 0), Vector3.BACK, Vector3.UP, R + 0.035, 0.0, TAU, 36), 0.018, "galva", 6)
	for k in range(6):
		var a: float = TAU * (k + 0.5) / 6.0
		RemonteeKit.barre(n, o + Vector3(0, sin(a), cos(a)) * 0.08, o + Vector3(0, sin(a), cos(a)) * (R - 0.02), 0.022, "galva", 5)
	RemonteeKit.cylindre(n, 0.08, 0.08, 0.13, Transform3D(Basis(Vector3.BACK, PI * 0.5), o), "galva", 14)
	RemonteeKit.cylindre(n, 0.025, 0.025, 0.30, Transform3D(Basis(Vector3.BACK, PI * 0.5), o), "acier_noir", 8)
	# chape : deux joues de part et d'autre, de l'axe au-dessus de la poulie, puis suspente jusqu'au bras
	var yh: float = 0.12
	for dx2 in [-0.13, 0.13]:
		RemonteeKit.boite_en(n, Vector3(0.02, yh - o.y, 0.14), Vector3(dx2, (yh + o.y) * 0.5, 0), "galva")
	RemonteeKit.boite_en(n, Vector3(0.30, 0.04, 0.14), Vector3(0, yh, 0), "galva")
	var haut: float = y_bras - c.y
	RemonteeKit.boite_en(self, Vector3(0.08, haut - yh, 0.10), c + Vector3(0, (haut + yh) * 0.5, 0), "galva")


func _construire_teleski() -> void:
	var h: float = hauteur
	var yc: float = h - DESSUS_BRAS_TELESKI        # câble
	if cote == 0 and not en_t:
		var xd: float = _x_brin(false)
		x_fut = xd + signf(xd) * 0.9
	else:
		x_fut = 0.0
	RemonteeKit.boite_en(self, Vector3(1.0, 0.5, 1.0), Vector3(x_fut, -0.1, 0), "beton")
	var h_fut: float = h + (1.7 if tkd else 0.0)
	RemonteeKit.cylindre(self, 0.17, 0.13, h_fut, Transform3D(Basis.IDENTITY, Vector3(x_fut, h_fut * 0.5, 0)), "galva", 14)
	if tkd:
		RemonteeKit.cylindre(self, 0.14, 0.14, 0.04, Transform3D(Basis.IDENTITY, Vector3(x_fut, h_fut + 0.02, 0)), "galva", 14)
		RemonteeKit.boite_en(self, Vector3(0.14, 0.14, 0.01), Vector3(x_fut, h - 1.3, -0.16), "jaune_securite")
	var y: float = 2.2
	while y < h - 0.4 and not tkd:
		RemonteeKit.barre(self, Vector3(x_fut - 0.18, y, 0.15), Vector3(x_fut + 0.18, y, 0.15), 0.012, "galva", 5)
		y += 0.32
	# bras jusqu'au-delà du brin le plus loin, jambe de force en triangle
	var xs: Array = []
	for montee in [true, false]:
		if cote == 0 or montee == (cote == 1):
			xs.append(_x_brin(montee))
	var x_loin: float = x_fut
	for x in xs:
		if absf(x - x_fut) > absf(x_loin - x_fut):
			x_loin = x
	# mousse de protection au pied du fût (vidéos de la ligne)
	if tkd:
		RemonteeKit.cylindre(self, 0.27, 0.27, 1.7, Transform3D(Basis.IDENTITY, Vector3(x_fut, 0.85, 0)), "mousse_orange", 14)
	else:
		RemonteeKit.cylindre(self, 0.26, 0.26, 1.8, Transform3D(Basis.IDENTITY, Vector3(x_fut, 0.9, 0)), "mousse_rouge", 14)
	if tkd:
		_bras_treillis_tkd(h, x_loin + signf(x_loin - x_fut) * 0.25, xs)
	elif cote == 0 and en_t:
		# traverse en T, des deux côtés du fût, au-delà des deux brins
		var xt: float = voie * 0.5 + 0.25
		RemonteeKit.boite_en(self, Vector3(2.0 * xt, 0.16, 0.16), Vector3(0, h - 0.08, 0), "galva")
		for sx in [-1.0, 1.0]:
			RemonteeKit.poutre(self, Vector3(0, h - 1.0, 0), Vector3(sx * xt * 0.6, h - 0.16, 0), 0.06, 0.06, "galva")
	else:
		var bout: float = x_loin + signf(x_loin - x_fut) * 0.25
		RemonteeKit.boite_en(self, Vector3(absf(bout - x_fut) + 0.15, 0.16, 0.16), Vector3((bout + x_fut) * 0.5, h - 0.08, 0), "galva")
		var lb: float = absf(bout - x_fut)
		RemonteeKit.poutre(self, Vector3(x_fut, h - 0.2 - lb * 0.75, 0), Vector3(lerpf(x_fut, bout, 0.8), h - 0.16, 0), 0.08, 0.08, "galva")
		RemonteeKit.poutre(self, Vector3(lerpf(x_fut, bout, 0.4), h - 0.16, 0), Vector3(x_fut, h - 0.2 - lb * 0.75 * 0.5, 0), 0.06, 0.06, "galva")
	for montee in [true, false]:
		if cote != 0 and montee != (cote == 1):
			continue
		var x: float = _x_brin(montee)
		if montee and virage > 0.02 and cote_corde != 0.0:
			# virage : galets à axe vertical côté corde, sur un arc ; le câble
			# s'appuie contre eux à la hauteur de la ligne
			var nv: int = clampi(int(virage / 0.04) + 2, 3, 10)
			var lv: float = (nv - 1) * 0.36
			var yv: float = h + dessus_traverse
			for k in range(nv):
				var z: float = lv * 0.5 - k * 0.36
				var c: Vector3 = Vector3(x + cote_corde * (0.14 + 0.03), yv, z)
				RemonteeKit.galet(self, c, 0.14, 0.06)
				var g: MeshInstance3D = get_child(get_child_count() - 1)
				g.transform.basis = Basis.IDENTITY.scaled(Vector3.ONE * 0.14 / RollerMesh.R_BANDE)
			RemonteeKit.boite_en(self, Vector3(0.10, 0.10, lv + 0.3), Vector3(x + cote_corde * 0.17, yv + 0.20, 0), "galva")
			RemonteeKit.boite_en(self, Vector3(0.10, yv + 0.25 - h, 0.10), Vector3(x + cote_corde * 0.17, h + (yv + 0.25 - h) * 0.5, 0), "galva")
			continue
		var compo: Array = compo_montee if montee else compo_descente
		var n: int = 0
		var dessus: bool = false
		for g in compo:
			n += int(g[0]) if g[0] != null else 2
			dessus = dessus or String(g[1]) == "C"
		n = maxi(n, 2)
		var Lt: float = (n - 1) * 0.36
		var yc2: float = h - DESSUS_BRAS_TELESKI
		# galets sous le câble (support) ; en compression, au-dessus
		var yg: float = yc2 + (0.14 if dessus else -0.14)
		var tilt: float = incline_descente if not montee else 0.0
		if tkd and not dessus:
			# TKD (photos du Chardonnet) : une grande poulie verticale par brin, chape pendue au bras
			_grande_poulie_tkd(Vector3(x, yc2, 0), tilt, h - BRAS_TKD)
			continue
		for k in range(n):
			var cg: Vector3 = Vector3(x, yg, Lt * 0.5 - k * 0.36)
			if tilt != 0.0:
				# galet incliné sous le câble : le point d'appui reste sous lui, la normale penche vers l'extérieur
				cg = Vector3(x, yc2, cg.z) - Vector3(-sin(tilt), cos(tilt), 0.0) * 0.14
			RemonteeKit.galet(self, cg, 0.14, 0.06)
			if tilt != 0.0:
				var gi: Node3D = get_child(get_child_count() - 1)
				gi.transform.basis = Basis(Vector3.BACK, tilt) * gi.transform.basis
		# flasques du train et suspente côté intérieur, jusqu'au bras
		var xi: float = x - signf(x - x_fut) * 0.12 if absf(x - x_fut) > 0.01 else x + 0.12
		RemonteeKit.boite_en(self, Vector3(0.04, 0.22, Lt + 0.3), Vector3(xi, yg, 0), "galva")
		var y_bras: float = h - BRAS_TKD if tkd else h - 0.16
		RemonteeKit.boite_en(self, Vector3(0.08, y_bras - (yg - 0.1), 0.10), Vector3(xi, (y_bras + yg - 0.1) * 0.5, 0), "galva")
	var lab: MeshInstance3D = RemonteeKit.texte_fige(self, str(numero), 64, 0.003, Color(0.05, 0.05, 0.05))
	lab.position = Vector3(x_fut, minf(3.0, h * 0.5), 0.18)
