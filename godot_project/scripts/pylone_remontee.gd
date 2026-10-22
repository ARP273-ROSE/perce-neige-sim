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
@export var style: String = "doppelmayr"   # doppelmayr | poma | fixe
@export var sens_montee_droite: bool = true
var compo_montee: Array = [[8, "S"]]
var compo_descente: Array = [[8, "S"]]
## Déviation du câble au pylône (rad) : pente côté aval − pente côté amont
## (> 0 : ligne convexe, en support). Les paires de galets se posent sur
## l'arc du câble (tangentes et hauteurs) au lieu d'une ligne droite.
var deviation: float = 0.0
## Paires de galets mobiles (à garder hors de la fusion des maillages) ; par
## brin : [nœud, position de repos, rotation de repos, z galet aval, z galet amont, s]
var mobiles: Array = []
var _paires: Dictionary = {true: [], false: []}

const R_GALET: float = 0.21                # Ø 420 mm, la norme des débrayables
const PAS_GALET: float = 0.52              # entraxe de deux galets d'un même balancier
const R_CABLE: float = 0.0235              # Ø 47 mm (Tufs)
const DESSUS_TRAVERSE_CABLE: float = 0.95  # du dessus de la traverse à l'axe du câble


func _ready() -> void:
	if get_child_count() == 0:
		construire()


func hauteur_cable() -> float:
	return hauteur + DESSUS_TRAVERSE_CABLE


## Position (locale) de l'axe du câble au droit du pylône, côté montée ou descente.
func point_cable(montee: bool) -> Vector3:
	return Vector3(_x_brin(montee), hauteur_cable(), 0.0)


func _x_brin(montee: bool) -> float:
	var s: float = 1.0 if montee == sens_montee_droite else -1.0
	return s * voie * 0.5


func construire() -> void:
	for c in get_children():
		c.queue_free()
	if style == "teleski":
		_construire_teleski()
		return
	var h: float = hauteur
	var r1: float = 0.40                              # rayon en tête
	var r0: float = r1 + 0.05 + h * 0.003             # léger fruit vers le pied
	var y_tete: float = h - 0.75                      # dessous de la chaise de tête
	_massif(r0)
	_fut(r0, r1, y_tete)
	_echelle(r0, r1, y_tete)
	_chaise_et_traverse(r1, y_tete)
	for montee in [true, false]:
		_train(montee)
	_plaques(r0, r1, y_tete)


## Massif béton affleurant, platine et tiges d'ancrage.
func _massif(r0: float) -> void:
	RemonteeKit.boite_en(self, Vector3(2.0, 0.8, 2.0), Vector3(0, -0.15, 0), "beton")
	RemonteeKit.cylindre(self, r0 + 0.28, r0 + 0.28, 0.06, Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)), "galva_pylone", 28)
	for k in range(12):
		var a: float = TAU * (k + 0.5) / 12.0
		var q: Vector3 = Vector3(cos(a) * (r0 + 0.18), 0.34, sin(a) * (r0 + 0.18))
		RemonteeKit.cylindre(self, 0.022, 0.022, 0.14, Transform3D(Basis.IDENTITY, q), "galva_patine", 6)
		RemonteeKit.cylindre(self, 0.038, 0.038, 0.035, Transform3D(Basis.IDENTITY, q + Vector3(0, -0.02, 0)), "galva_patine", 6)
		# goussets de pied entre les tiges
		if k % 3 == 0:
			var d: Vector3 = Vector3(cos(a), 0, sin(a))
			RemonteeKit.poutre(self, d * r0 + Vector3(0, 0.31, 0), d * r0 + Vector3(0, 0.75, 0) + d * 0.01, 0.02, 0.20,
				"galva_pylone", d)


## Fût tubulaire galvanisé, tronçons de ~6 m (les brides sont intérieures :
## on ne voit qu'un cordon de soudure).
func _fut(r0: float, r1: float, y_tete: float) -> void:
	var n: int = maxi(1, int(ceil((y_tete - 0.31) / 6.0)))
	for i in range(n):
		var ya: float = 0.31 + (y_tete - 0.31) * float(i) / n
		var yb: float = 0.31 + (y_tete - 0.31) * float(i + 1) / n
		var ra: float = lerpf(r0, r1, (ya - 0.31) / (y_tete - 0.31))
		var rb: float = lerpf(r0, r1, (yb - 0.31) / (y_tete - 0.31))
		RemonteeKit.cylindre(self, ra, rb, yb - ya, Transform3D(Basis.IDENTITY, Vector3(0, (ya + yb) * 0.5, 0)), "galva_pylone", 28)
		if i > 0:
			RemonteeKit.cylindre(self, ra + 0.012, ra + 0.012, 0.03, Transform3D(Basis.IDENTITY, Vector3(0, ya, 0)), "galva_patine", 28)


## Échelle droite à montants (pas de crinoline sur les lignes récentes : un
## rail antichute), sur pattes boulonnées au fût, côté aval.
func _echelle(r0: float, r1: float, y_tete: float) -> void:
	var y0: float = 1.9
	var y1: float = hauteur - 0.05
	var zr := func(y: float) -> float:
		return lerpf(r0, r1, clampf((y - 0.31) / (y_tete - 0.31), 0.0, 1.0)) + 0.24
	for sx in [-0.21, 0.21]:
		RemonteeKit.poutre(self, Vector3(sx, y0, zr.call(y0)), Vector3(sx, y1, zr.call(y1)), 0.06, 0.012, "galva_pylone", Vector3.BACK)
	var y: float = y0 + 0.14
	while y < y1 - 0.1:
		RemonteeKit.barre(self, Vector3(-0.21, y, zr.call(y)), Vector3(0.21, y, zr.call(y)), 0.013, "galva_pylone", 6)
		y += 0.28
	# rail antichute au milieu
	RemonteeKit.poutre(self, Vector3(0, y0, zr.call(y0) + 0.01), Vector3(0, y1, zr.call(y1) + 0.01), 0.035, 0.02, "galva_patine", Vector3.BACK)
	# pattes de fixation tous les 1,5 m
	var yp: float = y0 + 0.4
	while yp < y_tete:
		var rr: float = zr.call(yp) - 0.24
		for sx in [-0.21, 0.21]:
			RemonteeKit.poutre(self, Vector3(sx * 0.6, yp, rr - 0.02), Vector3(sx, yp, zr.call(yp)), 0.04, 0.012, "galva_pylone")
		yp += 1.5


## Chaise de tête (caisson sur le fût) et traverse : deux poutres en I
## parallèles jusqu'au droit des câbles, caillebotis de part et d'autre,
## garde-corps en arceaux.
func _chaise_et_traverse(r1: float, y_tete: float) -> void:
	var h: float = hauteur
	RemonteeKit.cylindre(self, r1 + 0.04, r1 + 0.04, 0.05, Transform3D(Basis.IDENTITY, Vector3(0, y_tete, 0)), "galva_patine", 28)
	RemonteeKit.boite_en(self, Vector3(1.0, h - y_tete - 0.30, 0.80), Vector3(0, (y_tete + h - 0.30) * 0.5, 0), "galva_pylone")
	var xe: float = voie * 0.5 + 0.12
	for sz in [-0.34, 0.34]:
		_poutre_i(Vector3(-xe, h - 0.15, sz), Vector3(xe, h - 0.15, sz), 0.30, 0.18)
	# entretoises entre les deux poutres
	var x: float = -xe + 0.3
	while x < xe:
		RemonteeKit.boite_en(self, Vector3(0.08, 0.22, 0.60), Vector3(x, h - 0.15, 0), "galva_pylone")
		x += 1.2
	# jambes de force sous la traverse
	for sx in [-1.0, 1.0]:
		for sz in [-0.34, 0.34]:
			RemonteeKit.poutre(self, Vector3(sx * r1 * 0.9, y_tete - 1.4, sz * 0.7), Vector3(sx * xe * 0.55, h - 0.30, sz), 0.10, 0.10, "galva_pylone")
	# caillebotis : bande centrale de part et d'autre de la traverse
	for sz in [-1.0, 1.0]:
		RemonteeKit.boite_en(self, Vector3(2.0 * xe - 1.6, 0.035, 0.72), Vector3(0, h + 0.02, sz * 0.80), "caillebotis")
		_rambarde(Vector3(-xe + 0.85, h + 0.02, sz * 1.14), Vector3(xe - 0.85, h + 0.02, sz * 1.14))


## Poutre en I de a à b (âme verticale).
func _poutre_i(a: Vector3, b: Vector3, ht: float, larg: float) -> void:
	var m: String = "galva_pylone"
	RemonteeKit.poutre(self, a + Vector3(0, ht * 0.5, 0), b + Vector3(0, ht * 0.5, 0), larg, 0.022, m)
	RemonteeKit.poutre(self, a - Vector3(0, ht * 0.5, 0), b - Vector3(0, ht * 0.5, 0), larg, 0.022, m)
	RemonteeKit.poutre(self, a, b, 0.016, ht, m)


## Garde-corps : montants, lisse haute et sous-lisse, arceaux aux bouts.
func _rambarde(a: Vector3, b: Vector3) -> void:
	var l: float = a.distance_to(b)
	var n: int = maxi(1, int(ceil(l / 1.1)))
	for k in range(n + 1):
		var p: Vector3 = a.lerp(b, float(k) / n)
		RemonteeKit.barre(self, p, p + Vector3(0, 1.05, 0), 0.02, "galva_pylone", 6)
	RemonteeKit.barre(self, a + Vector3(0, 1.05, 0), b + Vector3(0, 1.05, 0), 0.024, "galva_pylone", 8)
	RemonteeKit.barre(self, a + Vector3(0, 0.55, 0), b + Vector3(0, 0.55, 0), 0.018, "galva_pylone", 6)
	RemonteeKit.boite_en(self, Vector3(l, 0.10, 0.01), (a + b) * 0.5 + Vector3(0, 0.07, 0), "galva_pylone")


## Train de galets d'un brin, au nombre réel (groupes [n, "S"|"C"|"SC"]) :
## galets par paires entre deux flasques boulonnées sur les axes ; les
## paires s'articulent sur des palonniers, puis sur la poutre maîtresse qui
## pivote sur sa console (support : sous le câble, posée sur la traverse ;
## compression : au-dessus, pendue au portique). Ramasse-câbles le long, à
## l'extérieur ; portique de levage au-dessus ; caillebotis autour.
func _train(montee: bool) -> void:
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
			piv.position = base_pos
			piv.rotation.x = base_rot
			tete.add_child(piv)
			RemonteeKit.galet(piv, Vector3(0, -s * 0.11, za - zp), R_GALET, 0.10, "moyeu", "garniture")
			if zb != za:
				RemonteeKit.galet(piv, Vector3(0, -s * 0.11, zb - zp), R_GALET, 0.10, "moyeu", "garniture")
			for sx in [-0.068, 0.068]:
				RemonteeKit.poutre(piv, Vector3(sx, -s * 0.11, za - zp + 0.14), Vector3(sx, -s * 0.11, zb - zp - 0.14), 0.014, 0.12, "galva_patine")
			RemonteeKit.cylindre(piv, 0.035, 0.035, 0.20, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), "acier_noir", 8)
			mobiles.append(piv)
			(_paires[montee] as Array).append([piv, base_pos, base_rot, za, zb, s])
			pivots.append(zp)
			k2 += 2
		_palonniers(tete, pivots, y_axe, s)
		# ramasse-câbles : plaques échancrées à l'extérieur, entre les galets
		for k in range(0, zs.size() - 1, 2):
			var zm: float = (float(zs[k]) + float(zs[k + 1])) * 0.5
			RemonteeKit.boite_en(tete, Vector3(0.012, 0.30, 0.10), Vector3(ext * 0.11, y_axe + s * 0.02, zm), "galva_patine")
			RemonteeKit.boite_en(tete, Vector3(0.10, 0.012, 0.10), Vector3(ext * 0.16, y_axe - s * 0.13, zm), "galva_patine")
	# console : de la traverse au pivot de la poutre maîtresse (support)
	var y_trav: float = hauteur - hauteur_cable()           # dessus de traverse, repère de la tête
	if not dessous.is_empty():
		var y_piv: float = -dy - 0.36
		RemonteeKit.boite_en(tete, Vector3(0.22, absf(y_trav - y_piv), 0.30), Vector3(-ext * 0.02, (y_trav + y_piv) * 0.5, 0), "galva_pylone")
		RemonteeKit.cylindre(tete, 0.07, 0.07, 0.36, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, y_piv, 0)), "acier_noir", 12)
	# portique de levage : deux jambes inclinées et une poutre haute avec œil
	var hp: float = 1.25 if dessus.is_empty() else 1.55
	var demi: float = maxf(0.7, L * 0.5 + 0.25)
	for sz in [-1.0, 1.0]:
		RemonteeKit.poutre(self, Vector3(x - ext * 0.55, hauteur, sz * minf(demi, 1.3)), Vector3(x, hauteur_cable() + hp, sz * minf(demi, 1.3) * 0.55),
			0.10, 0.10, "galva_pylone")
		RemonteeKit.poutre(self, Vector3(x - ext * 0.55, hauteur, sz * minf(demi, 1.3)), Vector3(x, hauteur_cable() + hp, 0), 0.06, 0.06, "galva_pylone")
	RemonteeKit.poutre(tete, Vector3(0, hp, -minf(demi, 1.3) * 0.55 - 0.15), Vector3(0, hp, minf(demi, 1.3) * 0.55 + 0.15), 0.14, 0.12, "galva_pylone")
	RemonteeKit.tube(tete, RemonteeKit.arc(Vector3(0, hp + 0.14, 0), Vector3.FORWARD, Vector3.UP, 0.07, 0.0, TAU, 12), 0.018, "galva_patine", 6)
	if not dessus.is_empty():
		# suspente du train de compression au portique
		RemonteeKit.boite_en(tete, Vector3(0.16, hp - dy - 0.42, 0.24), Vector3(0, (hp + dy + 0.42) * 0.5, 0), "galva_pylone")
		RemonteeKit.cylindre(tete, 0.07, 0.07, 0.36, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, dy + 0.36, 0)), "acier_noir", 12)
	# caillebotis autour du train (côté intérieur), garde-corps côté fût
	var lc: float = 2.0 * demi + 0.6
	RemonteeKit.boite_en(self, Vector3(0.95, 0.035, lc), Vector3(x - ext * 0.62, hauteur + 0.02, 0), "caillebotis")


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
	for e in _paires[montee]:
		var sgn: float = e[5]
		var da: float = surepaisseur(float(e[3]) - u)
		var db: float = surepaisseur(float(e[4]) - u)
		var n: Node3D = e[0]
		n.position = (e[1] as Vector3) + Vector3(0, sgn * (da + db) * 0.5, 0)
		var dz: float = float(e[3]) - float(e[4])
		n.rotation.x = float(e[2]) - (sgn * (da - db) / dz if dz > 0.01 else 0.0)


## Plus de pince sur le brin : les paires reviennent au repos.
func repos(montee: bool) -> void:
	for e in _paires[montee]:
		(e[0] as Node3D).position = e[1]
		(e[0] as Node3D).rotation.x = e[2]


## Plaque bleue du numéro (comme sur les lignes Doppelmayr) et panneaux de
## consignes sous la tête, face aval.
func _plaques(r0: float, r1: float, y_tete: float) -> void:
	var yp: float = y_tete - 1.0
	var z: float = r1 + 0.012
	RemonteeKit.boite_en(self, Vector3(0.36, 0.30, 0.02), Vector3(0.42, yp, z - 0.06), "plaque_bleue")
	var lab: Label3D = Label3D.new()
	lab.text = str(numero)
	lab.font_size = 110
	lab.pixel_size = 0.0022
	lab.modulate = Color(1, 1, 1)
	lab.outline_size = 0
	lab.position = Vector3(0.42, yp, z - 0.045)
	lab.name = "Numero"
	add_child(lab)
	# panneau de consigne (pictogramme bleu sur fond blanc)
	var y2: float = y_tete - 2.2
	var r2: float = lerpf(r0, r1, (y2 - 0.31) / (y_tete - 0.31))
	RemonteeKit.boite_en(self, Vector3(0.40, 0.45, 0.015), Vector3(-0.05, y2, r2 + 0.01), "blanc_plaque")
	RemonteeKit.cylindre(self, 0.15, 0.15, 0.01, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.05, y2 + 0.03, r2 + 0.02)), "plaque_bleue", 20)


## Pylône de téléski : fût tubulaire fin, échelons soudés, potence en T
## portant un petit train de galets de chaque côté (voie ~2,5 m).
func _construire_teleski() -> void:
	var h: float = hauteur
	RemonteeKit.boite_en(self, Vector3(1.2, 0.5, 1.2), Vector3(0, -0.1, 0), "beton")
	RemonteeKit.cylindre(self, 0.20, 0.15, h, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), "galva", 14)
	var y: float = 2.2
	while y < h - 0.4:
		RemonteeKit.barre(self, Vector3(-0.2, y, 0.17), Vector3(0.2, y, 0.17), 0.012, "galva", 5)
		y += 0.32
	RemonteeKit.boite_en(self, Vector3(voie + 0.5, 0.22, 0.22), Vector3(0, h - 0.11, 0), "galva")
	for montee in [true, false]:
		var x: float = _x_brin(montee)
		var compo: Array = compo_montee if montee else compo_descente
		var n: int = 0
		var dessus: bool = false
		for g in compo:
			n += int(g[0]) if g[0] != null else 2
			dessus = dessus or String(g[1]) == "C"
		n = maxi(n, 2)
		var Lt: float = (n - 1) * 0.36
		for k in range(n):
			RemonteeKit.galet(self, Vector3(x, h + 0.35 + (0.30 if dessus else 0.0), Lt * 0.5 - k * 0.36), 0.14, 0.06)
		RemonteeKit.boite_en(self, Vector3(0.10, 0.10, Lt + 0.3), Vector3(x, h + 0.12, 0), "galva")
		RemonteeKit.boite_en(self, Vector3(0.10, 0.26, 0.10), Vector3(x, h + 0.05, 0), "galva")
	var lab: Label3D = Label3D.new()
	lab.text = str(numero)
	lab.font_size = 64
	lab.pixel_size = 0.003
	lab.modulate = Color(0.05, 0.05, 0.05)
	lab.position = Vector3(0, minf(3.0, h * 0.5), 0.21)
	add_child(lab)
