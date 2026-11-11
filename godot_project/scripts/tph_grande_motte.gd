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
##    rails-sabots des porteurs sur consoles (Telepherique._sabots_tph), une
##    entretoise en treillis côté façade avec sa flèche de levage ;
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


# --- plan des quais (dessin, collisions et portillons en sont tirés) ----------------

## Demi-largeur des baies : la caisse fait ±1,52 m, 4 cm de jeu (retour d'utilisateur du 11/11/2026 : « pas
## d'espace entre le quai et la cabine en gare, sinon je me tords la cheville »).
const DEMI_BAIE: float = 1.56
const RETRAIT_BARRIERE: float = 0.15    # barrières en retrait du bord : les vantaux coulissent devant
const DEMI_CAISSE_LONG: float = 2.80
const DEMI_PORTE: float = 0.85          # portillon devant la porte (vantaux de 2 × 0,75 m)


## Plan du quai d'une gare de la Grande Motte, repère de la gare (y = 0 au quai). `xs` : abscisses des deux
## voies ; `z_cab` : z du milieu de la cabine à quai. Retour d'utilisateur du 11/11/2026 : « en gare il y a des
## trous partout, je peux tomber tout le temps », « même autour du quai, quand je prends l'escalier latéral,
## je peux tomber partout en haut sur les côtés » ; « pour protéger les baies il y a des barrières, et en face
## des portes des barrières coulissantes ». Renvoie :
##  dalles : Rect2 (x, z) pleins ; garde_corps : [Vector2 a, Vector2 b] (bords du quai et des paliers, sauf
##  les départs d'escalier) ; barrieres : [a, b] le long des baies ; portillons : [x, z0, z1, voie] (devant
##  la porte, côté +x de la cabine) ; escaliers : [x, z_haut, sens (−1 : vers −z)].
static func plan_quai(aval: bool, xs: Array, z_cab: float) -> Dictionary:
	var xv: float = absf(float(xs[0]))
	var bi: float = xv - DEMI_BAIE
	var be: float = xv + DEMI_BAIE
	var W: float = be + (1.6 if aval else 1.4)
	var z_nez: float = -Z_NEZ if aval else 0.0
	var z_fond: float = (0.0 if aval else -L_BAIE - 3.4)       # fond du quai (façade, ou bout amont)
	var z_ar: float = z_cab + DEMI_CAISSE_LONG + 0.05            # bout des baies, derrière la cabine à quai
	if not aval:
		z_ar = z_cab - DEMI_CAISSE_LONG - 0.05
	var zlo: float = minf(z_nez, z_ar)
	var zhi: float = maxf(z_nez, z_ar)
	var dalles: Array = []
	# partie pleine derrière les baies, bandes entre et hors des baies
	if aval:
		dalles.append(Rect2(-W, z_ar, 2.0 * W, z_fond - z_ar))
		dalles.append(Rect2(-6.3, z_fond, 12.6, 1.0))        # sous le bâtiment (façade en biais, 12,9 m de large)
	else:
		dalles.append(Rect2(-W, z_fond, 2.0 * W, z_ar - z_fond))
	dalles.append(Rect2(-bi, zlo, 2.0 * bi, zhi - zlo))
	for sx in [-1.0, 1.0]:
		dalles.append(Rect2(minf(sx * be, sx * W), zlo, W - be, zhi - zlo))
	# escaliers latéraux et leurs paliers (aval : deux, contre la façade ; amont : un, au fond, à gauche)
	var esc: Array = []
	var gc: Array = []
	var ouv: Array = []                 # [x du bord, z0, z1] : départs d'escalier, sans garde-corps
	if aval:
		for sx2 in [-1.0, 1.0]:
			dalles.append(Rect2(minf(sx2 * W, sx2 * (W + 1.6)), -2.2, 1.6, 2.2))
			esc.append([sx2 * (W + 0.8), -2.2, -1.0])
			ouv.append([sx2 * W, -2.2, 0.0])
	else:
		dalles.append(Rect2(-W - 1.6, z_fond, 1.6, 2.2))
		esc.append([-W - 0.8, z_fond + 2.2, 1.0])
		ouv.append([-W, z_fond, z_fond + 2.2])
	# garde-corps : bords latéraux (moins les ouvertures), bord avant hors des baies, bord du fond hors du
	# bâtiment (aval) ; paliers : bord extérieur et bout
	for sx3 in [-1.0, 1.0]:
		var za: float = minf(z_nez, z_fond)
		var zb: float = maxf(z_nez, z_fond)
		var coupe: Array = [za, zb]
		for o in ouv:
			if signf(float(o[0])) == sx3:
				coupe = [za, float(o[1]), float(o[2]), zb] if float(o[1]) > za else [float(o[2]), zb]
		for k in range(0, coupe.size(), 2):
			if float(coupe[k + 1]) - float(coupe[k]) > 0.05:
				gc.append([Vector2(sx3 * W, float(coupe[k])), Vector2(sx3 * W, float(coupe[k + 1]))])
		gc.append([Vector2(sx3 * be, z_nez), Vector2(sx3 * W, z_nez)])
	gc.append([Vector2(-bi, z_nez), Vector2(bi, z_nez)])
	if not aval:
		gc.append([Vector2(-W, z_fond), Vector2(W, z_fond)])
	else:
		for sx4 in [-1.0, 1.0]:
			gc.append([Vector2(sx4 * 6.3, z_fond), Vector2(sx4 * W, z_fond)])     # hors de la façade (12,9 m)
			gc.append([Vector2(sx4 * 6.3, z_fond), Vector2(sx4 * 6.3, z_fond + 1.0)])
	for o2 in ouv:
		var xo: float = float(o2[0])
		var sxo: float = signf(xo)
		var xe2: float = xo + sxo * 1.6
		gc.append([Vector2(xe2, float(o2[1])), Vector2(xe2, float(o2[2]))])
		# bout du palier opposé au départ de l'escalier
		var z_bout: float = float(o2[2]) if aval else float(o2[1])
		gc.append([Vector2(xo, z_bout), Vector2(xe2, z_bout)])
	# barrières le long des baies, portillons devant les portes (côté +x de chaque cabine)
	var bar: Array = []
	var port: Array = []
	for i in range(2):
		var x0: float = float(xs[i])
		for sb in [-1.0, 1.0]:
			var xb: float = x0 + sb * (DEMI_BAIE + RETRAIT_BARRIERE)
			if sb > 0.0:
				bar.append([Vector2(xb, zlo), Vector2(xb, minf(z_cab - DEMI_PORTE, zhi))])
				bar.append([Vector2(xb, z_cab + DEMI_PORTE), Vector2(xb, zhi)])
				port.append([xb, z_cab - DEMI_PORTE, z_cab + DEMI_PORTE, i])
			else:
				bar.append([Vector2(xb, zlo), Vector2(xb, zhi)])
		# fond de baie, derrière la cabine
		var zr: float = z_ar + (RETRAIT_BARRIERE if aval else -RETRAIT_BARRIERE)
		bar.append([Vector2(x0 - DEMI_BAIE - RETRAIT_BARRIERE, zr), Vector2(x0 + DEMI_BAIE + RETRAIT_BARRIERE, zr)])
	return {"dalles": dalles, "garde_corps": gc, "barrieres": bar, "portillons": port, "escaliers": esc,
		"W": W, "bi": bi, "be": be, "z_nez": z_nez, "z_fond": z_fond}


## Dessin d'un quai d'après son plan : planchers en caillebotis sur poutres, poteaux et croix sous le
## plancher, garde-corps, barrières de baie, escaliers vers le sol.
static func _quai_dessin(g: Node3D, P: Dictionary, sol: Callable) -> void:
	for r in P["dalles"]:
		var rc: Rect2 = r
		_plancher(g, rc.position.x, rc.end.x, rc.position.y, rc.end.y, 0.0)
		for cx in [rc.position.x + 0.2, rc.end.x - 0.2]:
			for cz in [rc.position.y + 0.2, rc.end.y - 0.2]:
				_poteau(g, cx, cz, float(sol.call(cx, cz)), -0.36, 0.26)
	for e in P["garde_corps"]:
		_garde_corps(g, Vector3((e[0] as Vector2).x, 0, (e[0] as Vector2).y), Vector3((e[1] as Vector2).x, 0, (e[1] as Vector2).y))
	for e2 in P["barrieres"]:
		_garde_corps(g, Vector3((e2[0] as Vector2).x, 0, (e2[0] as Vector2).y), Vector3((e2[1] as Vector2).x, 0, (e2[1] as Vector2).y), 1.2)
	for es in P["escaliers"]:
		var x: float = es[0]
		var z_h: float = es[1]
		var sens: float = es[2]
		var haut: Vector3 = Vector3(x, -0.02, z_h)
		var lg_: float = 9.0
		var bas: Vector3 = Vector3(x, float(sol.call(x, z_h + sens * lg_)) + 0.05, z_h + sens * lg_)
		_escalier(g, haut, bas, 1.4)


# --- gare aval ---------------------------------------------------------------------

## Tête en acier côté ligne. `lg` : la ligne (voie, câble) ; `sol` : y du sol
## (repère de g) sous (x, z) ; `hc` : câble porteur au-dessus du quai ;
## z = 0 : façade du bâtiment, la tête s'avance vers −Z.
static func tete_aval(lg: LigneRemontee, g: Node3D, hc: float, sol: Callable) -> void:
	var xv: float = lg.voie * 0.5
	var zf: float = -2.2 - L_BAIE       # avant du quai
	var P: Dictionary = plan_quai(true, [-xv, xv], -Z_NEZ + Telepherique.D_QUAI)
	_quai_dessin(g, P, sol)
	# porteurs en gare : rails-sabots sur consoles latérales, posés par la ligne (Telepherique._sabots_tph ;
	# retour d'utilisateur du 11/11/2026 : l'ancienne charpente en treillis SOUS le câble et le portique en Λ
	# barraient le passage de la tête de suspente, qui file entre les deux porteurs)
	# entretoise côté façade seulement (devant, les suspentes passent)
	_treillis(g, Vector3(-xv, hc - 2.35, 0.0), Vector3(xv, hc - 2.35, 0.0), 1.8)
	# flèche de levage, au-dessus du bâtiment, qui s'avance vers la ligne
	var b0: Vector3 = Vector3(-xv - 0.5, hc + 3.0, 0.0)
	var b1: Vector3 = Vector3(-xv - 0.3, hc + 6.5, zf - 6.0)
	RemonteeKit.poutre(g, Vector3(-xv - 0.5, 0.0, 0.3), b0, 0.30, 0.30, M)
	_treillis(g, b0, b1, 0.9)
	RemonteeKit.cylindre(g, 0.35, 0.35, 0.12, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), b1 + Vector3(0, 0.9, 0)), "acier_noir", 16)


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
	var zf: float = -L_BAIE - 1.0         # fond des baies
	# (pas de massif d'un bloc : sur la pente du sommet il sortait de la neige ;
	# poteaux, chevalets et rampant ont chacun leur semelle)
	var y_sol: float = float(sol.call(0.0, -10.0))
	var P: Dictionary = plan_quai(false, [-xv, xv], -Telepherique.D_QUAI)
	_quai_dessin(g, P, sol)
	# porteurs en gare : rails-sabots posés par la ligne (Telepherique._sabots_tph)
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
		for sp in [-0.5, 0.5]:
			var xe: float = sp * VehiculeRemontee.E_PORTEURS_TPH
			RemonteeKit.barre(g, Vector3(s6 * xv + xe, hc, zf), c2 + b * Vector3(xe, 0.4, 3.0), 0.03, "cable", 6)
	# poste de vigie sous les tambours
	var pv: Vector3 = Vector3(0, float(sol.call(0.0, zt + 3.5)), zt + 3.5)
	RemonteeKit.boite_en(g, Vector3(3.2, 2.6, 2.8), pv + Vector3(0, 1.3, 0), "blanc_plaque")
	RemonteeKit.boite_en(g, Vector3(3.25, 1.0, 2.85), pv + Vector3(0, 1.7, 0), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(3.5, 0.15, 3.1), pv + Vector3(0, 2.68, 0), "peinture_anthracite")
