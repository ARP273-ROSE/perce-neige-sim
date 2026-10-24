class_name TphGrandeMotte
extends RefCounted
## Gares du téléphérique de la Grande Motte (Von Roll 1975, bicâble va-et-vient),
## refaites d'après la fiche et les photos du reportage remontees-mecaniques.net
## (consultées comme référence, retour d'utilisateur du 24/10/2026 : « reprends-le
## de zéro, refais tout le design consciencieusement ») :
##  - gare aval (3034 m, motrice, tension des porteurs par contrepoids) : le
##    bâtiment à bardage gris de la gare du funiculaire, salle d'attente vitrée
##    à l'étage, grand escalier extérieur côté funiculaire ; côté ligne, une
##    TÊTE EN ACIER posée sur poteaux : quai surélevé au niveau de la salle,
##    deux baies où accostent les cabines, escaliers métalliques vers la neige,
##    un grand portique en Λ par voie sous le porteur (sabot en tête), une
##    charpente en treillis au-dessus avec sa flèche de levage, des cornes qui
##    guident la suspente à l'entrée ;
##  - gare amont (3456 m, retour, ancrage des porteurs) : ouverte au sommet,
##    massif de béton portant les deux tambours d'ancrage inclinés côte à côte,
##    portique à deux tours en A portant en tête les poulies de retour du
##    tracteur, quai en caillebotis, poste de vigie sous les tambours.
## Repère : celui de la gare (GareAval / GareAmont) : y = 0 au niveau du quai,
## −Z vers l'amont, X en travers.

const H_QUAI_AVAL: float = 5.5        # quai au-dessus du sol du bâtiment (étage vitré)
const H_QUAI_AMONT: float = 1.6       # quai au-dessus du sommet
const L_BAIE: float = 10.4            # longueur des baies d'accostage
## Du bâtiment au nez de la ligne (avant du quai, portiques en Λ) : la ligne
## part de là, les cabines accostent derrière, dans les baies.
const Z_NEZ: float = 2.2 + L_BAIE + 0.4
const M: String = "galva_pylone"


static func _poteau(g: Node3D, x: float, z: float, y_bas: float, y_haut: float, c: float = 0.32) -> void:
	if y_haut - y_bas < 0.05:
		return
	RemonteeKit.boite_en(g, Vector3(c, y_haut - y_bas, c), Vector3(x, (y_bas + y_haut) * 0.5, z), M)
	RemonteeKit.boite_en(g, Vector3(c + 0.5, 0.4, c + 0.5), Vector3(x, y_bas - 0.1, z), "beton")


## Garde-corps : lisse haute, lisse intermédiaire, potelets tous les 1,5 m.
static func _garde_corps(g: Node3D, a: Vector3, b: Vector3, h: float = 1.1) -> void:
	RemonteeKit.barre(g, a + Vector3.UP * h, b + Vector3.UP * h, 0.03, "galva", 6)
	RemonteeKit.barre(g, a + Vector3.UP * h * 0.5, b + Vector3.UP * h * 0.5, 0.02, "galva", 6)
	var n: int = maxi(1, int(a.distance_to(b) / 1.5))
	for k in range(n + 1):
		var p: Vector3 = a.lerp(b, float(k) / n)
		RemonteeKit.barre(g, p, p + Vector3.UP * h, 0.025, "galva", 6)


## Escalier métallique droit de `haut` (palier) à `bas` (sol) : limons,
## marches en caillebotis, deux mains courantes. Renvoie la longueur.
static func _escalier(g: Node3D, haut: Vector3, bas: Vector3, larg: float) -> void:
	var d: Vector3 = bas - haut
	var dh: Vector3 = Vector3(d.x, 0, d.z)
	var lat: Vector3 = Vector3(dh.z, 0, -dh.x).normalized()
	var n: int = maxi(2, int(absf(d.y) / 0.19))
	for k in range(n):
		var t: float = (float(k) + 0.5) / n
		var p: Vector3 = haut + d * t
		var b: Basis = Basis.looking_at(dh.normalized(), Vector3.UP)
		RemonteeKit.boite(g, Vector3(larg, 0.04, absf(dh.length()) / n + 0.04), Transform3D(b, p), "caillebotis")
	for s in [-0.5, 0.5]:
		var o: Vector3 = lat * (s * larg)
		RemonteeKit.poutre(g, haut + o + Vector3.DOWN * 0.15, bas + o + Vector3.DOWN * 0.15, 0.06, 0.25, M)
		RemonteeKit.barre(g, haut + o + Vector3.UP * 1.0, bas + o + Vector3.UP * 1.0, 0.025, "bleu_doppelmayr", 6)
		RemonteeKit.barre(g, bas + o, bas + o + Vector3.UP * 1.0, 0.025, "galva", 6)


## Plancher en caillebotis sur poutres (rectangle x0..x1, z0..z1 au niveau y).
static func _plancher(g: Node3D, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var c: Vector3 = Vector3((x0 + x1) * 0.5, y - 0.03, (z0 + z1) * 0.5)
	RemonteeKit.boite_en(g, Vector3(absf(x1 - x0), 0.06, absf(z1 - z0)), c, "caillebotis")
	RemonteeKit.boite_en(g, Vector3(absf(x1 - x0), 0.30, 0.20), Vector3(c.x, y - 0.21, z0), M)
	RemonteeKit.boite_en(g, Vector3(absf(x1 - x0), 0.30, 0.20), Vector3(c.x, y - 0.21, z1), M)
	RemonteeKit.boite_en(g, Vector3(0.20, 0.30, absf(z1 - z0)), Vector3(x0, y - 0.21, c.z), M)
	RemonteeKit.boite_en(g, Vector3(0.20, 0.30, absf(z1 - z0)), Vector3(x1, y - 0.21, c.z), M)


## Poutre en treillis (deux membrures et diagonales) de a à b, hauteur h dans
## le plan vertical.
static func _treillis(g: Node3D, a: Vector3, b: Vector3, h: float, m: String = M) -> void:
	var up: Vector3 = Vector3.UP * h
	RemonteeKit.poutre(g, a, b, 0.16, 0.16, m)
	RemonteeKit.poutre(g, a + up, b + up, 0.16, 0.16, m)
	var n: int = maxi(2, int(a.distance_to(b) / maxf(h, 0.8)))
	for k in range(n):
		var p0: Vector3 = a.lerp(b, float(k) / n)
		var p1: Vector3 = a.lerp(b, float(k + 1) / n)
		RemonteeKit.poutre(g, p0 + (up if k % 2 == 0 else Vector3.ZERO), p1 + (Vector3.ZERO if k % 2 == 0 else up), 0.09, 0.09, m)
		RemonteeKit.poutre(g, p0, p0 + up, 0.08, 0.08, m)
	RemonteeKit.poutre(g, b, b + up, 0.08, 0.08, m)


## Sabot du porteur : poutre courbe à gorge, sur la tête d'un portique.
static func _sabot(g: Node3D, x: float, y_cable: float, zc: float, l: float) -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for k in range(11):
		var z: float = zc + lerpf(-l * 0.5, l * 0.5, float(k) / 10.0)
		var dz: float = z - zc
		pts.append(Vector3(x, y_cable - 0.08 - dz * dz * 0.006, z))
	RemonteeKit.tube(g, pts, 0.09, "acier_noir", 8)
	RemonteeKit.poutre(g, Vector3(x, y_cable - 0.45, zc - l * 0.45), Vector3(x, y_cable - 0.45, zc + l * 0.45), 0.28, 0.45, M)


# --- gare aval ---------------------------------------------------------------------

## Tête en acier côté ligne. `lg` : la ligne (voie, câble) ; `sol` : y du sol
## (repère de g) sous (x, z) ; `hc` : câble porteur au-dessus du quai ;
## z = 0 : façade du bâtiment, la tête s'avance vers −Z.
static func tete_aval(lg: LigneRemontee, g: Node3D, hc: float, sol: Callable) -> void:
	var xv: float = lg.voie * 0.5
	var bi: float = xv - 1.95           # bord intérieur des baies
	var be: float = xv + 1.95           # bord extérieur
	var W: float = be + 1.6             # bord du quai
	var zf: float = -2.2 - L_BAIE       # avant du quai
	# quai : bande le long de la façade, bande centrale entre les baies,
	# deux bandes extérieures ; les cabines accostent dans les baies
	_plancher(g, -W, W, 0.0, -2.2, 0.0)
	_plancher(g, -bi, bi, -2.2, zf, 0.0)
	for s in [-1.0, 1.0]:
		_plancher(g, s * be, s * W, -2.2, zf, 0.0)
	# poteaux et croix de Saint-André sous le quai
	for x in [-W + 0.2, -bi, 0.0, bi, W - 0.2]:
		for z in [-0.6, -2.2 - L_BAIE * 0.5, zf + 0.2]:
			var yb: float = float(sol.call(x, z))
			_poteau(g, x, z, yb, -0.36)
	for x2 in [-W + 0.2, W - 0.2]:
		var za: float = -0.6
		var zb: float = zf + 0.2
		var ya: float = float(sol.call(x2, za))
		var yb2: float = float(sol.call(x2, zb))
		RemonteeKit.poutre(g, Vector3(x2, ya + 0.3, za), Vector3(x2, -0.5, zb), 0.12, 0.12, M)
		RemonteeKit.poutre(g, Vector3(x2, -0.5, za), Vector3(x2, yb2 + 0.3, zb), 0.12, 0.12, M)
	# garde-corps : bords extérieurs, avant ; portillons le long des baies
	for s2 in [-1.0, 1.0]:
		_garde_corps(g, Vector3(s2 * W, 0, -0.2), Vector3(s2 * W, 0, zf))
		_garde_corps(g, Vector3(s2 * be, 0, zf), Vector3(s2 * W, 0, zf))
		for xb in [s2 * bi, s2 * be]:
			for zz in [-2.4, zf + 0.2]:
				RemonteeKit.barre(g, Vector3(xb, 0, zz), Vector3(xb, 1.1, zz), 0.03, "galva", 6)
	_garde_corps(g, Vector3(-bi, 0, zf), Vector3(bi, 0, zf))
	# escaliers métalliques vers la neige, le long des côtés
	for s3 in [-1.0, 1.0]:
		var haut: Vector3 = Vector3(s3 * (W + 0.75), -0.02, -1.2)
		var bas_z: float = -1.2 - 7.5
		var bas: Vector3 = Vector3(s3 * (W + 0.75), float(sol.call(s3 * (W + 0.75), bas_z)) + 0.05, bas_z)
		RemonteeKit.boite_en(g, Vector3(1.5, 0.06, 1.6), Vector3(haut.x, -0.03, -0.6), "caillebotis")
		_escalier(g, haut, bas, 1.3)
	# portiques en Λ sous les porteurs, à l'avant des baies (sabot en tête)
	for s4 in [-1.0, 1.0]:
		var x: float = s4 * xv
		var zl: float = zf - 0.4
		var apex: Vector3 = Vector3(x, hc - 0.55, zl)
		for dx in [-2.6, 2.6]:
			var pied: Vector3 = Vector3(x + dx, float(sol.call(x + dx, zl)), zl)
			RemonteeKit.poutre(g, pied, apex, 0.45, 0.45, M)
			RemonteeKit.boite_en(g, Vector3(1.0, 0.5, 1.0), pied + Vector3.DOWN * 0.1, "beton")
		RemonteeKit.poutre(g, Vector3(x - 1.3, hc * 0.45, zl), Vector3(x + 1.3, hc * 0.45, zl), 0.25, 0.25, M)
		_sabot(g, x, hc, zl, 4.5)
		# poulie de déviation du tracteur sous le sabot
		RemonteeKit.cylindre(g, 0.9, 0.9, 0.18, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, hc - 1.4, zl + 0.6)), "jaune_poulie", 24)
		# cornes de guidage de la suspente, de part et d'autre, évasées vers la ligne
		for s5 in [-1.0, 1.0]:
			var pts: PackedVector3Array = PackedVector3Array()
			for k in range(9):
				var t: float = float(k) / 8.0
				pts.append(Vector3(x + s5 * (0.75 + 1.6 * t * t), hc - 2.6 + 0.4 * t, zl + 0.6 - 6.5 * t))
			RemonteeKit.tube(g, pts, 0.10, M, 8)
			RemonteeKit.poutre(g, pts[0], Vector3(x + s5 * 2.6, hc * 0.45, zl), 0.10, 0.10, M)
	# charpente en treillis au-dessus des baies, de la façade au portique, et
	# flèche de levage qui s'avance vers la ligne
	var yt: float = hc + 1.6
	for s6 in [-1.0, 1.0]:
		_treillis(g, Vector3(s6 * (xv + 1.2), yt, 0.0), Vector3(s6 * (xv + 1.2), yt, zf - 0.4), 1.8)
		_treillis(g, Vector3(s6 * (xv - 1.2), yt, 0.0), Vector3(s6 * (xv - 1.2), yt, zf - 0.4), 1.8)
	for z3 in [0.0, -5.0, zf - 0.4]:
		_treillis(g, Vector3(-xv - 1.2, yt, z3), Vector3(xv + 1.2, yt, z3), 1.8)
	for x3 in [-xv - 1.2, xv + 1.2]:
		RemonteeKit.poutre(g, Vector3(x3, 0.0, -5.0), Vector3(x3, yt, -5.0), 0.30, 0.30, M)
	var b0: Vector3 = Vector3(-xv - 1.2, yt + 1.8, zf - 0.4)
	var b1: Vector3 = Vector3(-xv - 0.6, yt + 5.5, zf - 9.0)
	_treillis(g, b0, b1, 0.9)
	RemonteeKit.cylindre(g, 0.35, 0.35, 0.12, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), b1 + Vector3(0, 0.9, 0)), "acier_noir", 16)
	# caillebotis de service sur la charpente
	RemonteeKit.boite_en(g, Vector3(2.0 * xv + 2.4, 0.05, 1.2), Vector3(0, yt + 1.82, -2.5), "caillebotis")


## Escalier extérieur côté funiculaire (photo : grand escalier à rampes bleues
## le long de la façade, palier devant la porte de l'étage). `porte` : seuil
## (repère de g), `dehors` : direction horizontale vers l'extérieur ; il
## descend le long de la façade.
static func escalier_salle(g: Node3D, porte: Vector3, dehors: Vector3, sol: Callable) -> void:
	var lat: Vector3 = Vector3(dehors.z, 0, -dehors.x).normalized()
	var palier: Vector3 = porte + dehors * 1.4
	RemonteeKit.boite_en(g, Vector3(3.0, 0.08, 2.6), palier + Vector3.DOWN * 0.04, "caillebotis")
	_garde_corps(g, palier + dehors * 1.3 - lat * 1.5, palier + dehors * 1.3 + lat * 1.5)
	var depart: Vector3 = palier + lat * 1.5
	var y_bas: float = float(sol.call(depart.x + lat.x * 8.0, depart.z + lat.z * 8.0))
	var long: float = maxf(absf(porte.y - y_bas) / 0.62, 2.0)
	var bas: Vector3 = depart + lat * long
	bas.y = float(sol.call(bas.x, bas.z)) + 0.05
	_escalier(g, depart, bas, 2.2)
	for k in range(3):
		var p: Vector3 = depart.lerp(bas, float(k) / 3.0) + dehors * 1.0
		_poteau(g, p.x, p.z, float(sol.call(p.x, p.z)), p.y - 0.15, 0.16)
	for s in [-1.0, 1.0]:
		var p2: Vector3 = palier + lat * (s * 1.4) + dehors * 1.1
		_poteau(g, p2.x, p2.z, float(sol.call(p2.x, p2.z)), porte.y - 0.1, 0.18)


# --- gare amont --------------------------------------------------------------------

## Gare amont ouverte. z = 0 : nez, la gare s'étend vers −Z.
static func gare_amont(lg: LigneRemontee, g: Node3D, hc: float, sol: Callable) -> void:
	var xv: float = lg.voie * 0.5
	var bi: float = xv - 1.95
	var be: float = xv + 1.95
	var W: float = be + 1.4
	var zf: float = -L_BAIE - 1.0         # fond des baies
	# (pas de massif d'un bloc : sur la pente du sommet il sortait de la neige ;
	# poteaux, chevalets et rampant ont chacun leur semelle)
	var y_sol: float = float(sol.call(0.0, -10.0))
	# quai en caillebotis sur poteaux
	_plancher(g, -bi, bi, 0.0, zf, 0.0)
	for s in [-1.0, 1.0]:
		_plancher(g, s * be, s * W, 0.0, zf, 0.0)
	_plancher(g, -W, W, zf, zf - 2.4, 0.0)
	for x in [-W + 0.2, -bi, bi, W - 0.2]:
		for z in [-0.3, zf * 0.5, zf - 2.2]:
			_poteau(g, x, z, float(sol.call(x, z)), -0.36, 0.26)
	for s2 in [-1.0, 1.0]:
		_garde_corps(g, Vector3(s2 * W, 0, 0.0), Vector3(s2 * W, 0, zf - 2.4))
		_garde_corps(g, Vector3(s2 * be, 0, 0.0), Vector3(s2 * W, 0, 0.0))
	_garde_corps(g, Vector3(-bi, 0, 0.0), Vector3(bi, 0, 0.0))
	# escalier vers la piste (côté gauche)
	var haut: Vector3 = Vector3(-W - 0.7, -0.02, zf - 1.2)
	var bas: Vector3 = Vector3(-W - 0.7 - 0.0, float(sol.call(-W - 0.7, zf + 2.5)) + 0.05, zf + 2.5)
	_escalier(g, haut, bas, 1.3)
	# sabots des porteurs à l'entrée, sur un chevalet
	for s3 in [-1.0, 1.0]:
		var x: float = s3 * xv
		for dx in [-1.6, 1.6]:
			RemonteeKit.poutre(g, Vector3(x + dx, y_sol, 0.6), Vector3(x, hc - 0.55, 0.6), 0.35, 0.35, M)
		_sabot(g, x, hc, 0.6, 4.0)
	# portique de retour du tracteur : deux tours en A (pieds écartés dans
	# l'axe), poutre de tête, une grande poulie verticale par voie en tête
	var zp: float = zf - 1.2
	var yp: float = hc + 6.5
	for s4 in [-1.0, 1.0]:
		var xt: float = s4 * (xv + 2.4)
		for dz in [-2.4, 2.4]:
			RemonteeKit.poutre(g, Vector3(xt, y_sol, zp + dz), Vector3(xt, yp, zp), 0.40, 0.40, M)
		for k in range(1, 5):
			var y: float = y_sol + (yp - y_sol) * k / 5.0
			var e: float = 2.4 * (1.0 - float(k) / 5.0)
			RemonteeKit.poutre(g, Vector3(xt, y, zp - e), Vector3(xt, y, zp + e), 0.12, 0.12, M)
		# échelle
		RemonteeKit.barre(g, Vector3(xt + s4 * 0.4, y_sol, zp), Vector3(xt + s4 * 0.4, yp, zp), 0.03, "galva", 6)
	_treillis(g, Vector3(-xv - 2.6, yp, zp), Vector3(xv + 2.6, yp, zp), 1.4)
	for s5 in [-1.0, 1.0]:
		var c: Vector3 = Vector3(s5 * xv, yp + 0.7, zp)
		RemonteeKit.cylindre(g, 1.5, 1.5, 0.20, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c), "peinture_anthracite", 32)
		RemonteeKit.cylindre(g, 0.25, 0.25, 0.5, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c), "acier", 12)
		for k2 in range(6):
			var a: float = TAU * k2 / 6.0
			RemonteeKit.poutre(g, c, c + Vector3(0, sin(a), cos(a)) * 1.4, 0.06, 0.12, "peinture_anthracite")
		# le tracteur monte de la gare à la poulie et en redescend
		RemonteeKit.barre(g, Vector3(s5 * xv, hc - 0.45, 0.6), c + Vector3(0, 1.5, 0), 0.02, "cable", 6)
		RemonteeKit.barre(g, Vector3(s5 * xv, hc - 0.45, zf), c + Vector3(0, -1.5, 0), 0.02, "cable", 6)
	# tambours d'ancrage des porteurs : côte à côte, inclinés à 35° sur un
	# rampant de béton, le porteur enroulé de plusieurs tours
	var zt: float = zf - 9.0
	var yt: float = minf(float(sol.call(-xv, zt)), float(sol.call(xv, zt))) + 2.6
	var b_r: Basis = Basis(Vector3.RIGHT, 0.61)
	RemonteeKit.boite(g, Vector3(2.0 * xv + 7.0, 3.0, 9.0), Transform3D(b_r, Vector3(0, yt, zt) - b_r.y * 2.7), "beton")
	for s6 in [-1.0, 1.0]:
		var c2: Vector3 = Vector3(s6 * xv, yt, zt)
		var b: Basis = Basis(Vector3.RIGHT, 0.61)
		RemonteeKit.cylindre(g, 3.0, 3.0, 0.9, Transform3D(b, c2), "peinture_anthracite", 40)
		for k3 in range(5):
			RemonteeKit.cylindre(g, 3.05 - 0.0, 3.05, 0.08, Transform3D(b, c2 + b.y * (-0.3 + 0.15 * k3)), "cable", 40)
		RemonteeKit.cylindre(g, 0.5, 0.5, 1.1, Transform3D(b, c2), "acier", 16)
		# le porteur quitte le sabot, file au-dessus du quai et s'enroule
		RemonteeKit.barre(g, Vector3(s6 * xv, hc, 0.6), Vector3(s6 * xv, hc, zf), 0.03, "cable", 6)
		RemonteeKit.barre(g, Vector3(s6 * xv, hc, zf), c2 + b * Vector3(0, 0.4, 3.0), 0.03, "cable", 6)
	# poste de vigie sous les tambours
	var pv: Vector3 = Vector3(0, float(sol.call(0.0, zt + 3.5)), zt + 3.5)
	RemonteeKit.boite_en(g, Vector3(3.2, 2.6, 2.8), pv + Vector3(0, 1.3, 0), "blanc_plaque")
	RemonteeKit.boite_en(g, Vector3(3.25, 1.0, 2.85), pv + Vector3(0, 1.7, 0), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(3.5, 0.15, 3.1), pv + Vector3(0, 2.68, 0), "peinture_anthracite")
