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
	var peint: String = "peinture_anthracite" if style == "poma" else "peinture_gris"
	var h: float = hauteur
	# --- massif et platine
	RemonteeKit.boite_en(self, Vector3(2.4, 0.7, 2.4), Vector3(0, -0.15, 0), "beton")
	RemonteeKit.cylindre(self, 0.78, 0.78, 0.06, Transform3D(Basis.IDENTITY, Vector3(0, 0.23, 0)), "acier", 24)
	for k in range(8):
		var a: float = TAU * k / 8.0
		RemonteeKit.cylindre(self, 0.025, 0.025, 0.14, Transform3D(Basis.IDENTITY,
			Vector3(cos(a) * 0.68, 0.30, sin(a) * 0.68)), "galva", 6)
	# --- fût conique en tronçons de ~6 m, brides boulonnées
	var r0: float = 0.55 + h * 0.012
	var r1: float = 0.36
	var y_tete: float = h - 0.55
	var n_tr: int = maxi(1, int(ceil(y_tete / 6.0)))
	for i in range(n_tr):
		var ya: float = 0.26 + (y_tete - 0.26) * float(i) / n_tr
		var yb: float = 0.26 + (y_tete - 0.26) * float(i + 1) / n_tr
		var ra: float = lerpf(r0, r1, ya / y_tete)
		var rb: float = lerpf(r0, r1, yb / y_tete)
		RemonteeKit.cylindre(self, ra, rb, yb - ya, Transform3D(Basis.IDENTITY, Vector3(0, (ya + yb) * 0.5, 0)), peint, 20)
		if i > 0:
			RemonteeKit.cylindre(self, ra + 0.05, ra + 0.05, 0.05, Transform3D(Basis.IDENTITY, Vector3(0, ya, 0)), peint, 20)
	# --- échelle à crinoline, côté aval du fût
	var z_ech: float = r0 + 0.30
	var y_ech0: float = 2.4                  # anti-escalade : on démarre à 2,4 m
	for sx in [-0.22, 0.22]:
		RemonteeKit.barre(self, Vector3(sx, y_ech0, lerpf(r0, r1, y_ech0 / y_tete) + 0.30),
			Vector3(sx, y_tete - 0.6, r1 + 0.30), 0.022, "galva", 6)
	var y: float = y_ech0 + 0.15
	while y < y_tete - 0.7:
		var zz: float = lerpf(r0, r1, y / y_tete) + 0.30
		RemonteeKit.barre(self, Vector3(-0.22, y, zz), Vector3(0.22, y, zz), 0.014, "galva", 6)
		y += 0.30
	var yc: float = y_ech0 + 2.2
	while yc < y_tete - 0.8:
		var zc: float = lerpf(r0, r1, yc / y_tete) + 0.30
		RemonteeKit.tube(self, RemonteeKit.arc(Vector3(0, yc, zc), Vector3.RIGHT, Vector3.BACK, 0.38, 0.0, PI, 10), 0.012, "galva", 5)
		yc += 0.9
	for k in range(3):
		var a2: float = PI * (0.25 + 0.25 * k)
		var zb: float = 0.30
		RemonteeKit.barre(self, Vector3(cos(a2) * 0.38, y_ech0 + 2.2, lerpf(r0, r1, (y_ech0 + 2.2) / y_tete) + zb + sin(a2) * 0.38),
			Vector3(cos(a2) * 0.38, y_tete - 0.8, r1 + zb + sin(a2) * 0.38), 0.011, "galva", 5)
	# --- palier de tête (sous la traverse)
	RemonteeKit.boite_en(self, Vector3(1.6, 0.05, 1.6), Vector3(0, y_tete - 0.55, 0), "caillebotis")
	_garde_corps_carre(Vector3(0, y_tete - 0.55, 0), 1.6, 1.6, "galva")
	# --- traverse caisson, perpendiculaire à la ligne
	# la traverse s'arrête au droit du câble (+ 15 cm) : au-delà passent la
	# pince et la suspente, à l'extérieur du train de galets — elle dépassait
	# de 65 cm, en plein dans leur chemin (vu le 22/10/2026)
	var lt: float = voie + 0.30
	RemonteeKit.boite_en(self, Vector3(lt, 0.55, 0.50), Vector3(0, h - 0.275, 0), peint)
	# goussets fût / traverse
	for s in [-1.0, 1.0]:
		RemonteeKit.poutre(self, Vector3(s * r1, y_tete - 1.6, 0), Vector3(s * 1.6, h - 0.55, 0), 0.10, 0.40, peint, Vector3.BACK)
	# passerelles des deux côtés de la traverse, garde-corps extérieur
	for sz in [-1.0, 1.0]:
		var zp: float = sz * 0.65
		RemonteeKit.boite_en(self, Vector3(lt - 0.2, 0.04, 0.70), Vector3(0, h - 0.56, zp), "caillebotis")
		var zr: float = sz * 1.0
		for xi in range(-int(lt / 2.0), int(lt / 2.0) + 1):
			var xx: float = clampf(float(xi) * 1.0, -lt * 0.5 + 0.1, lt * 0.5 - 0.1)
			RemonteeKit.barre(self, Vector3(xx, h - 0.56, zr), Vector3(xx, h + 0.55, zr), 0.02, "galva", 6)
		RemonteeKit.barre(self, Vector3(-lt * 0.5 + 0.1, h + 0.55, zr), Vector3(lt * 0.5 - 0.1, h + 0.55, zr), 0.022, "galva", 6)
		RemonteeKit.barre(self, Vector3(-lt * 0.5 + 0.1, h, zr), Vector3(lt * 0.5 - 0.1, h, zr), 0.016, "galva", 6)
	# --- têtes de ligne : montée et descente
	for montee in [true, false]:
		var x: float = _x_brin(montee)
		var compo: Array = compo_montee if montee else compo_descente
		_tete(Vector3(x, 0, 0), compo, peint, montee)
	# --- plaque du numéro, face aval du fût
	var yp: float = minf(4.5, h * 0.4)
	RemonteeKit.boite_en(self, Vector3(0.55, 0.42, 0.02), Vector3(0, yp, lerpf(r0, r1, yp / y_tete) + 0.02), "blanc_plaque")
	var lab: Label3D = Label3D.new()
	lab.text = str(numero)
	lab.font_size = 96
	lab.pixel_size = 0.0028
	lab.modulate = Color(0.05, 0.05, 0.05)
	lab.outline_size = 0
	lab.position = Vector3(0, yp, lerpf(r0, r1, yp / y_tete) + 0.035)
	lab.name = "Numero"
	add_child(lab)
	# --- paratonnerre
	RemonteeKit.barre(self, Vector3(0, h, 0), Vector3(0, h + 2.2, 0), 0.012, "acier", 6)


func _garde_corps_carre(c: Vector3, lx: float, lz: float, m: String) -> void:
	var y1: float = c.y + 1.05
	var coins: Array = [Vector3(-lx, 0, -lz), Vector3(lx, 0, -lz), Vector3(lx, 0, lz), Vector3(-lx, 0, lz)]
	for i in range(4):
		var a: Vector3 = c + coins[i] * 0.5
		var b: Vector3 = c + coins[(i + 1) % 4] * 0.5
		RemonteeKit.barre(self, Vector3(a.x, y1, a.z), Vector3(b.x, y1, b.z), 0.02, m, 6)
		RemonteeKit.barre(self, a, Vector3(a.x, y1, a.z), 0.02, m, 6)


## Tête de ligne à l'extrémité x de la traverse : support de balancier,
## balancier (groupes S / C / SC), portique de levage, ramasse-câble.
func _tete(base: Vector3, compo: Array, peint: String, montee: bool) -> void:
	var tete: Node3D = Node3D.new()
	tete.name = "TeteMontee" if montee else "TeteDescente"
	tete.position = Vector3(base.x, hauteur_cable(), 0)
	tete.rotation.x = pente                     # le balancier suit la pente du câble
	add_child(tete)
	var n_tot: int = 0
	var a_dessus: bool = false
	var a_dessous: bool = false
	for g in compo:
		var n: int = int(g[0]) if g[0] != null else 2
		n_tot += n if String(g[1]) != "SC" else n / 2
		if String(g[1]) in ["C", "SC"]:
			a_dessus = true
		if String(g[1]) in ["S", "SC"]:
			a_dessous = true
	var L: float = maxf(1, n_tot - 1) * PAS_GALET
	# galets, groupe par groupe le long du câble (z de +L/2 vers −L/2 : aval → amont)
	var z: float = L * 0.5
	var pos_dessous: Array = []
	var pos_dessus: Array = []
	for g in compo:
		var n: int = int(g[0]) if g[0] != null else 2
		var nat: String = String(g[1])
		var k_n: int = n if nat != "SC" else n / 2
		for k in range(k_n):
			if nat in ["S", "SC"]:
				pos_dessous.append(z)
			if nat in ["C", "SC"]:
				pos_dessus.append(z)
			z -= PAS_GALET
	var dy: float = R_GALET + R_CABLE
	for zz in pos_dessous:
		RemonteeKit.galet(tete, Vector3(0, -dy, zz), R_GALET)
	for zz in pos_dessus:
		RemonteeKit.galet(tete, Vector3(0, dy, zz), R_GALET)
	# balanciers : bogies de 2 galets, puis poutres de niveau supérieur
	for liste in [[pos_dessous, -1.0], [pos_dessus, 1.0]]:
		var zs: Array = liste[0]
		var s: float = liste[1]
		if zs.is_empty():
			continue
		var y_b: float = s * dy
		# flasques des bogies (de chaque côté du galet)
		var i: int = 0
		while i < zs.size():
			var za: float = zs[i]
			var zb: float = zs[mini(i + 1, zs.size() - 1)]
			for sx in [-0.075, 0.075]:
				RemonteeKit.poutre(tete, Vector3(sx, y_b + s * 0.02, za + 0.12), Vector3(sx, y_b + s * 0.02, zb - 0.12),
					0.018, 0.16, "galva")
			RemonteeKit.boite_en(tete, Vector3(0.20, 0.10, 0.12), Vector3(0, y_b + s * (R_GALET * 0.5 + 0.12), (za + zb) * 0.5), "galva")
			i += 2
		# poutre maîtresse du train, côté opposé au câble
		var y_p: float = y_b + s * (R_GALET + 0.22)
		RemonteeKit.boite_en(tete, Vector3(0.16, 0.18, absf(zs[0] - zs[zs.size() - 1]) + 0.3),
			Vector3(0, y_p, (float(zs[0]) + float(zs[zs.size() - 1])) * 0.5), "galva")
		# niveaux intermédiaires (balanciers de 4, 8…) : petits palonniers
		var pas: int = 4
		while pas <= zs.size():
			var j: int = 0
			while j < zs.size():
				var zz0: float = zs[j]
				var zz1: float = zs[mini(j + pas - 1, zs.size() - 1)]
				RemonteeKit.boite_en(tete, Vector3(0.12, 0.10, absf(zz0 - zz1) * 0.8), Vector3(0, y_b + s * (R_GALET * 0.5 + 0.20), (zz0 + zz1) * 0.5), "galva")
				j += pas
			pas *= 2
		# ramasse-câble à l'extérieur du train (côté vide, à l'opposé du fût)
		var sx2: float = signf(base.x) if base.x != 0.0 else 1.0
		RemonteeKit.poutre(tete, Vector3(sx2 * 0.30, -dy - 0.15, float(zs[0]) + 0.1),
			Vector3(sx2 * 0.30, -dy - 0.15, float(zs[zs.size() - 1]) - 0.1), 0.03, 0.10, "jaune_securite")
	# support : du balancier à la traverse
	var y_traverse: float = hauteur - hauteur_cable()      # dessus de traverse, dans le repère de la tête
	if a_dessous:
		RemonteeKit.boite_en(tete, Vector3(0.30, absf(y_traverse) - dy - R_GALET - 0.20, 0.36),
			Vector3(0, (y_traverse - dy - R_GALET - 0.22) * 0.5 - 0.0, 0), peint)
		RemonteeKit.cylindre(tete, 0.09, 0.09, 0.42, Transform3D(Basis(Vector3.FORWARD, PI * 0.5),
			Vector3(0, -dy - R_GALET - 0.22, 0)), "acier", 12)     # axe du balancier
	# portique de levage (U renversé), qui porte aussi les trains de compression
	var hp: float = 1.45 if a_dessus else 1.15
	var demi: float = maxf(0.6, L * 0.5 + 0.35)
	for sz in [-1.0, 1.0]:
		RemonteeKit.poutre(self, Vector3(base.x - 0.45 * signf(base.x), hauteur, 0),
			Vector3(base.x, hauteur_cable() + hp, sz * minf(demi, 1.2)), 0.12, 0.12, peint)
	RemonteeKit.poutre(tete, Vector3(0, hp, -minf(demi, 1.2) - 0.1), Vector3(0, hp, minf(demi, 1.2) + 0.1), 0.14, 0.16, peint)
	if a_dessus:
		RemonteeKit.boite_en(tete, Vector3(0.14, hp - dy - R_GALET - 0.32, 0.20), Vector3(0, (hp + dy + R_GALET + 0.32) * 0.5, 0), peint)


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
