class_name TeleskiGare
extends RefCounted
## Gares des téléskis (retour d'utilisateur, 25/10/2026 : « les téléskis, à
## refaire entièrement, deux familles »). Pas de quai ni de plate-forme : la
## gare est posée sur la neige, la trace part du sol réel.
##
## Débrayables (TKD, Poma et dérivés) — photos Commons « Plan du Jeu POMA »,
## « Platter lift machinery », « Arve téléski », « Platter lift final post » :
## un mât rond porte la poulie horizontale ; en aval, une potence au-dessus du
## départ tient le MAGASIN, rail incliné où les perches débrayées pendent
## côte à côte jusqu'au lanceur ; en amont, un anneau de guidage entoure la
## poulie. Contrepoids de tension pendu au bout de la potence.
##
## À enrouleurs (TKE, T-bar) — photo Commons « Hundseck Bühlertallift » :
## portique en treillis à deux jambes en A de chaque côté, poulie pendue
## sous la poutre ; les boîtiers à enrouleur font le tour sur le câble.
##
## Les deux : couloir de départ entre filets, tapis au point de départ,
## cabane du perchman, motoréducteur en amont.

var lg: LigneRemontee

const PAS_MAGASIN: float = 0.25       # entraxe des perches au magasin : un rideau (vidéos)


func _init(l: LigneRemontee) -> void:
	lg = l


## Sol réel sous (x, z) du repère de la ligne, dans le repère de la gare g.
func _gy(g: Node3D, x: float, z: float) -> float:
	return lg._sol(x, z) - g.position.y


func construire(g: Node3D, aval: bool, znez: float, zc: float) -> void:
	if lg.famille == "perche_debrayable":
		if aval:
			_tour_tkd(g, zc)
			_magasin(g, zc)
		else:
			_mat_poma(g, aval, zc)
			_anneau_guidage(g, zc)
	else:
		_gare_enrouleurs(g, aval, zc)
	_tension_ou_motrice(g, aval, zc)
	if aval:
		_depart(g, znez, zc)
	else:
		_arrivee(g, zc)


# --- structures ---------------------------------------------------------------------

## Tour de départ du TKD (vidéos des départs du Chardonnet, du Col du
## Palet, de la Combe Folle, du 3000, du Signal et du Pays Désert ; retour
## d'utilisateur, 25/10/2026 : « refaire de zéro la gare de départ d'un téléski
## débrayable ») : une tour carrée en treillis galvanisé porte la poulie
## horizontale à son sommet, sous une plate-forme à garde-corps où sont le
## moteur et le réducteur, échelle à crinoline côté arrière. Autour, le
## MAGASIN : un rail qui descend en hélice autour de la tour, du point de
## débrayage (brin descente) jusqu'au lanceur (brin montée), où les perches
## débrayées pendent serrées en rideau.
const R_HELICE: float = 2.3          # rayon du rail du magasin autour de la tour
const TOURS_HELICE: float = 1.5      # demi-tour de la boucle + un tour complet
const Y_HAUT_HELICE: float = 1.4     # au-dessus du câble au début du rail
const Y_BAS_HELICE: float = 0.15     # … au lanceur


func _tour_tkd(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var m: String = "galva"
	var b: float = 0.9                                # demi-côté de la tour
	var yt: float = H - 0.35                          # haut des montants (sous la poulie)
	var ys: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var y0: float = _gy(g, sx * b, zc + sz * b)
			ys.append(y0)
			RemonteeKit.boite_en(g, Vector3(0.7, 0.5, 0.7), Vector3(sx * b, y0 - 0.1, zc + sz * b), "beton")
			RemonteeKit.poutre(g, Vector3(sx * b, y0, zc + sz * b), Vector3(sx * b, yt, zc + sz * b), 0.12, 0.12, m)
	var y_bas: float = ys.min()
	# croisillons sur les quatre faces, ceintures
	var n: int = maxi(2, int((yt - y_bas) / 1.4))
	for f in range(4):
		var a: float = PI * 0.5 * f
		var u: Vector3 = Vector3(cos(a), 0, sin(a))
		var v: Vector3 = Vector3(-sin(a), 0, cos(a))
		for k2 in range(n):
			var ya: float = lerpf(y_bas + 0.3, yt, float(k2) / n)
			var yb: float = lerpf(y_bas + 0.3, yt, float(k2 + 1) / n)
			var c: Vector3 = Vector3(0, 0, zc) + u * b
			RemonteeKit.barre(g, c - v * b + Vector3(0, ya, 0), c + v * b + Vector3(0, yb, 0), 0.03, m, 5)
			RemonteeKit.barre(g, c + v * b + Vector3(0, ya, 0), c - v * b + Vector3(0, yb, 0), 0.03, m, 5)
			RemonteeKit.barre(g, c - v * b + Vector3(0, yb, 0), c + v * b + Vector3(0, yb, 0), 0.04, m, 5)
	# chevêtre sous la poulie : arbre et palier
	RemonteeKit.boite_en(g, Vector3(2.0 * b + 0.2, 0.25, 2.0 * b + 0.2), Vector3(0, yt, zc), m)
	# plate-forme au-dessus de la poulie, garde-corps, moteur et réducteur
	var yp: float = H + 0.55
	var hp: float = 1.8
	RemonteeKit.boite_en(g, Vector3(2.0 * hp, 0.06, 2.0 * hp), Vector3(0, yp, zc), "caillebotis")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.poutre(g, Vector3(sx * b, yt, zc + sz * b), Vector3(sx * hp, yp, zc + sz * hp), 0.08, 0.08, m)
	for f2 in range(4):
		var a2: float = PI * 0.5 * f2
		var u2: Vector3 = Vector3(cos(a2), 0, sin(a2))
		var v2: Vector3 = Vector3(-sin(a2), 0, cos(a2))
		var c2: Vector3 = Vector3(0, yp, zc) + u2 * hp
		RemonteeKit.barre(g, c2 - v2 * hp + Vector3(0, 1.0, 0), c2 + v2 * hp + Vector3(0, 1.0, 0), 0.025, m, 6)
		RemonteeKit.barre(g, c2 - v2 * hp + Vector3(0, 0.5, 0), c2 + v2 * hp + Vector3(0, 0.5, 0), 0.02, m, 6)
		for t in [-1.0, 0.0, 1.0]:
			RemonteeKit.barre(g, c2 + v2 * hp * t, c2 + v2 * hp * t + Vector3(0, 1.0, 0), 0.025, m, 6)
	RemonteeKit.boite_en(g, Vector3(1.1, 0.8, 1.4), Vector3(0.4, yp + 0.43, zc + 0.3), "peinture_gris")
	RemonteeKit.cylindre(g, 0.30, 0.30, 0.9, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.55, yp + 0.38, zc + 0.3)), "bleu_doppelmayr", 16)
	RemonteeKit.boite_en(g, Vector3(0.7, 1.4, 0.5), Vector3(-1.2, yp + 0.73, zc - 1.1), "peinture_gris")     # armoire
	# échelle à crinoline, face arrière
	var ze: float = zc + b + 0.25
	var ye: float = _gy(g, 0.0, ze)
	for sx2 in [-0.22, 0.22]:
		RemonteeKit.barre(g, Vector3(sx2, ye, ze), Vector3(sx2, yp + 1.0, ze), 0.02, m, 5)
	var y2: float = ye + 0.3
	while y2 < yp:
		RemonteeKit.barre(g, Vector3(-0.22, y2, ze), Vector3(0.22, y2, ze), 0.015, m, 4)
		y2 += 0.3
	var y3: float = ye + 2.3
	while y3 < yp + 1.0:
		RemonteeKit.tube(g, RemonteeKit.arc(Vector3(0, y3, ze + 0.35), Vector3.RIGHT, Vector3.BACK, 0.38, PI, TAU, 8), 0.012, m, 4)
		y3 += 0.8


## Magasin en hélice autour de la tour : rail, bras radiaux et suspentes.
func _magasin(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var pts: PackedVector3Array = PackedVector3Array()
	var s0: float = lg.S_DEBRAYAGE
	var s1: float = lg.s_lancement()
	var nb: int = 240
	for k in range(nb + 1):
		var s: float = lerpf(s0, s1, float(k) / nb)
		pts.append(rail_local(s) - Vector3(0, g.position.y, 0) + Vector3(0, 0.06, 0))
	RemonteeKit.tube(g, pts, 0.035, "acier_noir", 6)
	# bras radiaux depuis le haut de la tour, tous les 30° de l'hélice
	var yh: float = H + 0.40
	for k2 in range(0, nb + 1, 8):
		var p: Vector3 = pts[k2]
		var r: Vector2 = Vector2(p.x, p.z - zc)
		if r.length() < R_HELICE - 0.3 or r.length() > R_HELICE + 0.3:
			continue
		var pied: Vector3 = Vector3(r.normalized().x * 0.9, yh, zc + r.normalized().y * 0.9)
		RemonteeKit.barre(g, pied, Vector3(p.x, yh, p.z), 0.025, "galva", 5)
		RemonteeKit.barre(g, Vector3(p.x, yh, p.z), p + Vector3(0, 0.03, 0), 0.018, "galva", 5)
	# lanceur : boîtier jaune et bras au bout du rail
	var pl: Vector3 = rail_local(lg.s_lancement()) - Vector3(0, g.position.y, 0)
	RemonteeKit.boite_en(g, Vector3(0.30, 0.40, 0.55), pl + Vector3(0, 0.42, 0.25), "jaune_securite")
	RemonteeKit.barre(g, pl + Vector3(0, 0.25, 0.0), pl + Vector3(0, 0.05, -0.45), 0.03, "acier_noir", 6)


## Point du rail du magasin à l'abscisse s de la boucle (repère de la ligne) :
## du câble au point de débrayage, droit jusqu'à l'hélice, hélice descendante
## autour de la tour, droit jusqu'au câble au lanceur.
func rail_local(s: float) -> Vector3:
	var H: float = lg.H_CABLE_GARE + lg.terrain(0.0)
	var zc: float = lg.l_gare
	var s0: float = lg.S_DEBRAYAGE
	var s1: float = lg.s_lancement()
	var u: float = clampf((s - s0) / maxf(s1 - s0, 0.01), 0.0, 1.0)
	var sd: float = signf(lg._x_brin(false))
	var a0: float = 0.0 if sd > 0.0 else PI
	var a1: float = a0 + sd * PI * 2.0 * TOURS_HELICE
	var debut: Vector3 = Vector3(cos(a0) * R_HELICE, H + Y_HAUT_HELICE, zc + sin(a0) * R_HELICE)
	var fin: Vector3 = Vector3(cos(a1) * R_HELICE, H + Y_BAS_HELICE, zc + sin(a1) * R_HELICE)
	if u < 0.08:
		var c0: Vector3 = lg._point_cable(s0)[0]
		return c0.lerp(debut, smoothstep(0.0, 1.0, u / 0.08))
	if u > 0.92:
		var c1: Vector3 = lg._point_cable(s1)[0]
		return fin.lerp(c1, smoothstep(0.0, 1.0, (u - 0.92) / 0.08))
	var w: float = (u - 0.08) / 0.84
	var a: float = lerpf(a0, a1, w)
	return Vector3(cos(a) * R_HELICE, H + lerpf(Y_HAUT_HELICE, Y_BAS_HELICE, w), zc + sin(a) * R_HELICE)


## Mât Poma : fût rond sous la poulie, massif de béton, mousse jaune au pied.
func _mat_poma(g: Node3D, aval: bool, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var y0: float = _gy(g, 0.0, zc)
	var h: float = H - 0.30 - y0
	RemonteeKit.boite_en(g, Vector3(1.6, 0.6, 1.6), Vector3(0, y0 - 0.15, zc), "beton")
	RemonteeKit.cylindre(g, 0.30, 0.24, h, Transform3D(Basis.IDENTITY, Vector3(0, y0 + h * 0.5, zc)), "galva", 18)
	RemonteeKit.cylindre(g, 0.42, 0.42, 1.8, Transform3D(Basis.IDENTITY, Vector3(0, y0 + 0.9, zc)), "mousse_jaune", 16)
	# échelons soudés côté arrière
	var sg: float = 1.0 if aval else -1.0
	var y: float = y0 + 2.2
	while y < H - 0.6:
		RemonteeKit.barre(g, Vector3(-0.2, y, zc + sg * 0.30), Vector3(0.2, y, zc + sg * 0.30), 0.015, "galva", 5)
		y += 0.32
	# plate-forme de visite à claire-voie autour de la tête, garde-corps
	var yp: float = H + 0.78
	RemonteeKit.boite_en(g, Vector3(2.6, 0.06, 2.6), Vector3(0, yp, zc), "caillebotis")
	for k in range(4):
		var a: float = PI * 0.5 * k
		var u: Vector3 = Vector3(cos(a), 0, sin(a))
		var t: Vector3 = Vector3(-sin(a), 0, cos(a))
		RemonteeKit.barre(g, Vector3(0, yp + 1.0, zc) + u * 1.3 - t * 1.3, Vector3(0, yp + 1.0, zc) + u * 1.3 + t * 1.3, 0.025, "galva", 6)
		RemonteeKit.barre(g, Vector3(0, yp, zc) + u * 1.3 + t * 1.3, Vector3(0, yp + 1.0, zc) + u * 1.3 + t * 1.3, 0.025, "galva", 6)


## Anneau de guidage de la gare amont Poma : les perches tournent avec le
## câble autour de la poulie, l'anneau les tient à l'écart du mât.
func _anneau_guidage(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var c: Vector3 = Vector3(0, H - 0.9, zc)
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.RIGHT, Vector3.BACK, R + 0.55, 0.0, TAU, 48), 0.04, "galva", 8)
	for k in range(6):
		var a: float = TAU * k / 6.0
		var u: Vector3 = Vector3(cos(a), 0, sin(a))
		RemonteeKit.barre(g, c + u * (R + 0.55), Vector3(0, H + 0.6, zc) + u * 0.9, 0.03, "galva", 6)


## Gare d'un téléski à enrouleurs (vidéo du TKE2 du Montet) : deux colonnes-
## caissons en acier de part et d'autre de la poulie, une poutre en travers
## qui la porte, une plate-forme à garde-corps au-dessus ; en aval, le local
## blanc de la motrice sur la plate-forme ; mousses rouges au pied, échelle.
func _gare_enrouleurs(g: Node3D, aval: bool, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var xc: float = R + 0.9
	var yb: float = H + 0.55                          # dessous de la poutre
	for sx in [-1.0, 1.0]:
		var y0: float = _gy(g, sx * xc, zc)
		RemonteeKit.boite_en(g, Vector3(0.9, 0.5, 0.9), Vector3(sx * xc, y0 - 0.1, zc), "beton")
		RemonteeKit.boite_en(g, Vector3(0.42, yb + 0.5 - y0, 0.42), Vector3(sx * xc, (yb + 0.5 + y0) * 0.5, zc), "galva")
		RemonteeKit.boite_en(g, Vector3(0.62, 1.9, 0.62), Vector3(sx * xc, y0 + 0.95, zc), "mousse_rouge")
		# échelle sur la colonne côté extérieur
		var xe: float = sx * (xc + 0.32)
		for dz in [-0.22, 0.22]:
			RemonteeKit.barre(g, Vector3(xe, y0 + 2.0, zc + dz), Vector3(xe, yb + 1.6, zc + dz), 0.018, "galva", 5)
		var y2: float = y0 + 2.2
		while y2 < yb + 1.5:
			RemonteeKit.barre(g, Vector3(xe, y2, zc - 0.22), Vector3(xe, y2, zc + 0.22), 0.014, "galva", 4)
			y2 += 0.3
	# poutre en travers, palier de la poulie dessous
	RemonteeKit.boite_en(g, Vector3(2.0 * xc + 0.5, 0.5, 0.6), Vector3(0, yb + 0.25, zc), "galva")
	RemonteeKit.boite_en(g, Vector3(0.7, H + 0.55 - (H + 0.15), 0.7), Vector3(0, (yb + H + 0.15) * 0.5, zc), "acier_noir")
	# plate-forme et garde-corps
	var yp: float = yb + 0.55
	var lx: float = 2.0 * xc + 1.4
	var lz: float = 3.6
	RemonteeKit.boite_en(g, Vector3(lx, 0.06, lz), Vector3(0, yp, zc), "caillebotis")
	for c in [[Vector3(-lx * 0.5, 0, -lz * 0.5), Vector3(lx * 0.5, 0, -lz * 0.5)], [Vector3(lx * 0.5, 0, -lz * 0.5), Vector3(lx * 0.5, 0, lz * 0.5)],
			[Vector3(lx * 0.5, 0, lz * 0.5), Vector3(-lx * 0.5, 0, lz * 0.5)], [Vector3(-lx * 0.5, 0, lz * 0.5), Vector3(-lx * 0.5, 0, -lz * 0.5)]]:
		var a: Vector3 = (c[0] as Vector3) + Vector3(0, yp, zc)
		var b: Vector3 = (c[1] as Vector3) + Vector3(0, yp, zc)
		RemonteeKit.barre(g, a + Vector3(0, 1.05, 0), b + Vector3(0, 1.05, 0), 0.025, "galva", 6)
		RemonteeKit.barre(g, a + Vector3(0, 0.55, 0), b + Vector3(0, 0.55, 0), 0.02, "galva", 6)
		var n: int = maxi(1, int(a.distance_to(b) / 1.2))
		for k in range(n + 1):
			var q: Vector3 = a.lerp(b, float(k) / n)
			RemonteeKit.barre(g, q, q + Vector3(0, 1.05, 0), 0.022, "galva", 5)
	if aval:
		# local de la motrice : caisse blanche, vitres sombres, toit plat
		var c2: Vector3 = Vector3(0, yp, zc + 0.3)
		RemonteeKit.boite_en(g, Vector3(2.4, 2.1, 2.4), c2 + Vector3(0, 1.05, 0), "blanc_plaque")
		RemonteeKit.boite_en(g, Vector3(2.6, 0.12, 2.6), c2 + Vector3(0, 2.16, 0), "peinture_anthracite")
		for sx2 in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(0.03, 0.8, 1.6), c2 + Vector3(sx2 * 1.215, 1.35, 0), "vitrage_sombre")
		RemonteeKit.boite_en(g, Vector3(1.6, 0.8, 0.03), c2 + Vector3(0, 1.35, -1.215), "vitrage_sombre")


## Portique en treillis (enrouleurs) : poutre en long au-dessus de la poulie,
## deux jambes en A à chaque bout, hors de la boucle des perches.
func _portique(g: Node3D, aval: bool, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var m: String = "vert_treillis" if lg.constructeur.to_lower().contains("doppelmayr") else "galva"
	var yb: float = H + 1.0
	var z0: float = zc - (R + 1.2)
	var z1: float = zc + (R + 1.2)
	_poutre_treillis(g, Vector3(0, yb, z0), Vector3(0, yb, z1), 0.55, m)
	for z in [z0, z1]:
		for sx in [-1.0, 1.0]:
			var pied: Vector3 = Vector3(sx * (R + 1.0), _gy(g, sx * (R + 1.0), z), z)
			_poutre_treillis(g, pied, Vector3(sx * 0.15, yb - 0.3, z), 0.35, m, Vector3(0, 0, 1))
			RemonteeKit.boite_en(g, Vector3(0.7, 0.4, 0.7), pied + Vector3(0, -0.1, 0), "beton")
			RemonteeKit.cylindre(g, 0.20, 0.20, 1.2, Transform3D(Basis.IDENTITY, pied + Vector3(-sx * 0.10, 0.6, 0)), "mousse_rouge", 12)
		RemonteeKit.poutre(g, Vector3(-(R + 0.6), yb - 1.6, z), Vector3(R + 0.6, yb - 1.6, z), 0.10, 0.10, m)


## Poutre en treillis de a à b : deux membrures et des diagonales en zigzag
## dans le plan qui contient `plan` (vertical par défaut).
func _poutre_treillis(g: Node3D, a: Vector3, b: Vector3, h: float, m: String, plan: Vector3 = Vector3.UP) -> void:
	var t: Vector3 = (b - a).normalized()
	var n: Vector3 = (plan - t * plan.dot(t)).normalized() * h * 0.5
	RemonteeKit.poutre(g, a + n, b + n, 0.09, 0.09, m)
	RemonteeKit.poutre(g, a - n, b - n, 0.09, 0.09, m)
	var l: float = a.distance_to(b)
	var nb: int = maxi(int(l / (h * 1.1)), 1)
	for k in range(nb):
		var p0: Vector3 = a.lerp(b, float(k) / nb)
		var p1: Vector3 = a.lerp(b, float(k + 1) / nb)
		var sgn: float = 1.0 if k % 2 == 0 else -1.0
		RemonteeKit.barre(g, p0 + n * sgn, p1 - n * sgn, 0.025, m, 5)
		RemonteeKit.barre(g, p0 + n, p0 - n, 0.022, m, 5)


## Aval : contrepoids de tension pendu à une poulie verticale au bout de
## la gare ; amont : motoréducteur sur la tête (posé par la poulie).
func _tension_ou_motrice(g: Node3D, aval: bool, zc: float) -> void:
	if true:
		return       # (motrice en aval, tension en amont : pas de contrepoids au départ)
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var zt: float = zc + R + 1.3
	var c: Vector3 = Vector3(0, H + 0.95, zt)
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.BACK, Vector3.UP, 0.55, 0.0, TAU, 28), 0.05, "acier_noir", 6)
	for k in range(6):
		var a: float = TAU * k / 6.0
		RemonteeKit.barre(g, c, c + Vector3(0, sin(a), cos(a)) * 0.55, 0.02, "acier_noir", 5)
	RemonteeKit.poutre(g, Vector3(0, H + 1.2, zc), c + Vector3(0, 0.25, 0), 0.16, 0.16, "galva")
	# câble de tension et bloc de béton pendu, guidé par deux rails
	var yb: float = _gy(g, 0.0, zt + 0.55)
	var ybloc: float = yb + 1.4
	RemonteeKit.barre(g, c + Vector3(0, 0, 0.55), Vector3(0, ybloc + 0.6, zt + 0.55), 0.012, "cable", 5)
	RemonteeKit.boite_en(g, Vector3(0.9, 1.1, 0.9), Vector3(0, ybloc, zt + 0.55), "beton")
	for sx in [-0.55, 0.55]:
		RemonteeKit.barre(g, Vector3(sx, yb - 0.2, zt + 0.55), Vector3(sx, H + 0.6, zt + 0.55), 0.04, "galva", 6)


# --- abords -------------------------------------------------------------------------

## Départ : tapis au point de départ, couloir d'attente entre deux filets
## bleus derrière lui, panneau, cabane du perchman à côté.
func _depart(g: Node3D, znez: float, zc: float) -> void:
	var q: Vector3 = lg.point_depart_teleski()
	var xb: float = q.x
	var sx: float = signf(xb)
	var y: float = _gy(g, xb, q.z)
	# tapis de caoutchouc vert sous les skis
	RemonteeKit.boite_en(g, Vector3(1.0, 0.04, 2.2), Vector3(xb, y + 0.01, q.z + 0.6), "tapis_vert")
	# couloir : de 1 m avant le tapis à 9 m derrière
	for cote in [-1.0, 1.0]:
		var x: float = xb + cote * 1.0
		var za: float = q.z - 0.5
		var zb: float = q.z + 9.0
		var n: int = 6
		for k in range(n + 1):
			var z: float = lerpf(za, zb, float(k) / n)
			var yp: float = _gy(g, x, z)
			RemonteeKit.barre(g, Vector3(x, yp - 0.2, z), Vector3(x, yp + 1.15, z), 0.022, "jaune_securite", 5)
			if k < n:
				var z2: float = lerpf(za, zb, float(k + 1) / n)
				var y2: float = _gy(g, x, z2)
				var mid: Vector3 = Vector3(x, (yp + y2) * 0.5 + 0.6, (z + z2) * 0.5)
				var pan: Transform3D = Transform3D(Basis(Vector3.RIGHT, atan2(y2 - yp, -(z2 - z))), mid)
				RemonteeKit.boite(g, Vector3(0.02, 0.85, absf(z2 - z)), pan, "filet_bleu")
	# portillon de départ : poteau jaune et barre basculante au bord du tapis
	var yp2: float = _gy(g, xb + sx * 0.75, q.z + 1.4)
	RemonteeKit.cylindre(g, 0.08, 0.08, 1.0, Transform3D(Basis.IDENTITY, Vector3(xb + sx * 0.75, yp2 + 0.5, q.z + 1.4)), "mousse_jaune", 10)
	RemonteeKit.barre(g, Vector3(xb + sx * 0.75, yp2 + 0.6, q.z + 1.4), Vector3(xb - sx * 0.55, yp2 + 0.6, q.z + 1.4), 0.03, "rouge_val", 6)
	# feu vert / rouge et coup-de-poing d'arrêt sur un poteau au bord de la trace
	var xf: float = xb - sx * 1.1
	var zf: float = q.z - 0.8
	var yf: float = _gy(g, xf, zf)
	RemonteeKit.cylindre(g, 0.05, 0.05, 1.6, Transform3D(Basis.IDENTITY, Vector3(xf, yf + 0.8, zf)), "acier_noir", 8)
	RemonteeKit.boite_en(g, Vector3(0.16, 0.34, 0.14), Vector3(xf, yf + 1.75, zf), "noir_mat")
	RemonteeKit.boite_en(g, Vector3(0.10, 0.10, 0.02), Vector3(xf, yf + 1.83, zf + 0.08), "feu_vert")
	RemonteeKit.boite_en(g, Vector3(0.10, 0.10, 0.02), Vector3(xf, yf + 1.67, zf + 0.08), "rouge_val")
	RemonteeKit.boite_en(g, Vector3(0.22, 0.22, 0.16), Vector3(xf, yf + 1.15, zf), "jaune_securite")
	RemonteeKit.cylindre(g, 0.06, 0.06, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(xf, yf + 1.15, zf + 0.09)), "rouge_val", 12)
	# panneau « départ » sur le poteau du couloir
	var lab: Label3D = Label3D.new()
	lab.text = "DÉPART\n%s" % lg.nom_court()
	lab.font_size = 56
	lab.pixel_size = 0.004
	lab.outline_size = 8
	lab.modulate = Color(0.95, 0.95, 0.95)
	lab.outline_modulate = Color(0.08, 0.20, 0.55)
	lab.position = Vector3(xb + sx * 1.0, _gy(g, xb + sx * 1.0, q.z + 9.0) + 1.6, q.z + 9.0)
	lab.rotation.y = 0.0
	g.add_child(lab)
	_cabane(g, Vector3(xb + sx * 3.2, 0, q.z + 2.5), sx)


## Arrivée : fanions de l'aire de lâcher et panneau « lâchez la perche ».
func _arrivee(g: Node3D, zc: float) -> void:
	var L: float = lg.longueur_h()
	var xb: float = lg._x_brin(true)
	var z: float = -L - lg.x_debarquement() + 2.5
	for k in range(3):
		var zz: float = z + 3.0 * k
		var x: float = xb + signf(xb) * 1.4
		var yp: float = _gy(g, x, zz)
		RemonteeKit.barre(g, Vector3(x, yp - 0.2, zz), Vector3(x, yp + 1.6, zz), 0.022, "jaune_securite", 5)
		RemonteeKit.boite_en(g, Vector3(0.02, 0.30, 0.42), Vector3(x, yp + 1.4, zz - 0.21), "rouge_val")
	var lab: Label3D = Label3D.new()
	lab.text = "LÂCHEZ\nLA PERCHE"
	lab.font_size = 48
	lab.pixel_size = 0.004
	lab.outline_size = 8
	lab.modulate = Color(1, 1, 1)
	lab.outline_modulate = Color(0.65, 0.06, 0.08)
	lab.position = Vector3(xb + signf(xb) * 1.4, _gy(g, xb + signf(xb) * 1.4, z + 6.0) + 2.2, z + 6.0 + 0.1)
	g.add_child(lab)
	_cabane(g, Vector3(-signf(xb) * (lg.voie * 0.5 + 3.0), 0, zc + 3.0), -signf(xb))


## Cabane du perchman : planches vertes, grandes vitres, toit d'un pan.
func _cabane(g: Node3D, c: Vector3, cote: float) -> void:
	var y: float = _gy(g, c.x, c.z)
	var t: Vector3 = Vector3(2.0, 2.3, 2.4)
	var b: Vector3 = Vector3(c.x, y, c.z)
	RemonteeKit.boite_en(g, Vector3(t.x + 0.2, 0.3, t.z + 0.2), b + Vector3(0, 0.0, 0), "beton")
	RemonteeKit.boite_en(g, t, b + Vector3(0, t.y * 0.5 + 0.15, 0), "bois_vert")
	# vitres côté trace et vers l'amont
	RemonteeKit.boite_en(g, Vector3(0.04, 0.9, 1.6), b + Vector3(-cote * (t.x * 0.5 + 0.01), 1.55, 0), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(1.3, 0.9, 0.04), b + Vector3(0, 1.55, -(t.z * 0.5 + 0.01)), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(0.8, 1.9, 0.04), b + Vector3(0, 1.1, t.z * 0.5 + 0.01), "peinture_anthracite")
	var toit: Transform3D = Transform3D(Basis(Vector3.BACK, cote * 0.12), b + Vector3(0, t.y + 0.3, 0))
	RemonteeKit.boite(g, Vector3(t.x + 0.6, 0.10, t.z + 0.6), toit, "toit_noir")


## Emprises à protéger d'une collision (centres, tailles) dans le repère de
## la ligne : mât ou jambes, cabane.
func collisions(aval: bool) -> Array:
	var L: float = lg.longueur_h()
	var zc: float = lg.l_gare if aval else -L - lg.l_gare
	var R: float = lg.voie * 0.5
	var H: float = lg.H_CABLE_GARE
	var r: Array = []
	var y0: float = lg.terrain(0.0 if aval else L)
	if lg.famille == "perche_debrayable":
		var ys: float = lg._sol(0.0, zc)
		var lt: float = 2.0 if aval else 0.84           # tour du départ, mât à l'arrivée
		r.append([Vector3(lt, H - ys + y0, lt), Vector3(0, (ys + y0 + H) * 0.5, zc)])
	else:
		for sx in [-1.0, 1.0]:
			var ys2: float = lg._sol(sx * (R + 0.9), zc)
			r.append([Vector3(0.62, 2.4, 0.62), Vector3(sx * (R + 0.9), ys2 + 1.2, zc)])
	var c: Vector3
	var xb: float = lg._x_brin(true)
	if aval:
		var q: Vector3 = lg.point_depart_teleski()
		c = Vector3(q.x + signf(q.x) * 3.2, 0, q.z + 2.5)
	else:
		c = Vector3(-signf(xb) * (lg.voie * 0.5 + 3.0), 0, zc + 3.0)
	var yc: float = lg._sol(c.x, c.z)
	r.append([Vector3(2.0, 2.6, 2.4), Vector3(c.x, yc + 1.3, c.z)])
	return r
