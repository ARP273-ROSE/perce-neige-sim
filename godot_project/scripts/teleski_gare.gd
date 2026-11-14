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

const PAS_MAGASIN: float = 0.12       # entraxe des perches à la glissière : un rideau serré (photos du Chardonnet)


func _init(l: LigneRemontee) -> void:
	lg = l


## Sol réel sous (x, z) du repère de la ligne, dans le repère de la gare g.
func _gy(g: Node3D, x: float, z: float) -> float:
	return lg._sol(x, z) - g.position.y


func construire(g: Node3D, aval: bool, znez: float, zc: float) -> void:
	if lg.famille == "perche_debrayable":
		if aval:
			_portique_tkd(g, zc)
			_glissiere(g, zc)
		elif lsp():
			_arrivee_lsp(g, zc)
			_anneau_guidage(g, zc)
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



## Téléskis Montaval (Signal, Montet, Savonnette…) : constructeur local, gares d'un autre dessin.
func montaval() -> bool:
	return lg.constructeur.to_lower().contains("montaval")


## TKD : tous à charpente et garage droit (reportages RM.net du Signal, du Chardonnet, du Col du Palet, de
## Combe Folle, du 3000 et du Pays Désert : charpente surélevée, perches en rideau au garage, poulie motrice
## en tête ; aucun n'a de tour à magasin en hélice).
func tkd() -> bool:
	return lg.famille == "perche_debrayable"


## Gare de départ (motrice) d'un TKD, refaite le 14/11/2026 d'après les photos du Chardonnet (reportage
## RM.net, copie locale), la gare motrice « glissière » de Wikimedia Commons (CC BY-SA 4.0) et les brevets Poma
## US 4 154 171 et Schippers US 3 868 907. Portique en tubes carrés galvanisés ; en tête, au-dessus de la poulie
## motrice horizontale (blanche, à rayons), une plate-forme à garde-corps qui porte le moteur (bleu) et le
## réducteur ; un tube-guide en demi-cercle tient les perches qui contournent la poulie ; côté montée, la
## glissière droite descend en pente douce vers l'avant, les perches y pendent en rideau serré jusqu'au
## déclencheur, au-dessus du skieur ; escalier incliné vers l'avant, échelle au poteau arrière, mousses
## orange. Cotes estimées sur photo (portique ~5,5 m, plate-forme ~3 × 4 m).
const H_PORTIQUE: float = 1.45       # longerons au-dessus du câble
const PENTE_GLISSIERE: float = 0.15  # pente de la glissière (brevets : 15 à 20 %)
const Y_GLISSIERE: float = 0.80      # haut de la glissière au-dessus du câble, au débrayage


func _portique_tkd(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var m: String = "galva"
	var xm: float = lg._x_brin(true)
	var sm: float = signf(xm)
	var xa: float = absf(xm) + 0.75
	var zb: float = zc + R + 0.6                # arrière, derrière la poulie
	var zf: float = 0.35                       # avant, devant le déclencheur
	var yl: float = H + H_PORTIQUE
	for sx in [-1.0, 1.0]:
		for z in [zf, zc - 1.6, zb]:
			var y0: float = _gy(g, sx * xa, z)
			RemonteeKit.boite_en(g, Vector3(0.55, 0.35, 0.55), Vector3(sx * xa, y0 - 0.12, z), "beton")
			RemonteeKit.poutre(g, Vector3(sx * xa, y0, z), Vector3(sx * xa, yl + 0.15, z), 0.18, 0.18, m)
			# mousse orange au pied, côté piste (photos)
			if z != zb:
				RemonteeKit.boite_en(g, Vector3(0.42, 1.7, 0.42), Vector3(sx * xa, y0 + 0.85, z), "mousse_orange")
		# longeron en tête, lisse à mi-hauteur, croix de Saint-André entre les poteaux
		RemonteeKit.poutre(g, Vector3(sx * xa, yl, zf), Vector3(sx * xa, yl, zb), 0.16, 0.22, m)
		var ym: float = H - 1.2
		RemonteeKit.poutre(g, Vector3(sx * xa, ym, zc - 1.6), Vector3(sx * xa, ym, zb), 0.10, 0.10, m)
		RemonteeKit.barre(g, Vector3(sx * xa, ym, zc - 1.6), Vector3(sx * xa, yl, zb), 0.035, m, 5)
		RemonteeKit.barre(g, Vector3(sx * xa, ym, zb), Vector3(sx * xa, yl, zc - 1.6), 0.035, m, 5)
	# traverses en tête
	for z2 in [zf, zc - 1.6, zc + 0.9, zb]:
		RemonteeKit.poutre(g, Vector3(-xa, yl, z2), Vector3(xa, yl, z2), 0.14, 0.20, m)
	# longeron de la glissière, au-dessus du brin montée
	RemonteeKit.poutre(g, Vector3(xm, yl - 0.05, zf), Vector3(xm, yl - 0.05, zc - 1.6), 0.12, 0.16, m)
	# arbre de la poulie, jusqu'au réducteur sur la plate-forme
	RemonteeKit.cylindre(g, 0.12, 0.12, yl - H, Transform3D(Basis.IDENTITY, Vector3(0, (yl + H) * 0.5, zc)), "acier", 12)
	# plate-forme au-dessus de la poulie : caillebotis, garde-corps tubulaire, moteur et réducteur
	var yp: float = yl + 0.18
	var z0: float = zc - 1.6
	var z1: float = zb + 0.25
	RemonteeKit.boite_en(g, Vector3(2.0 * xa + 0.5, 0.05, z1 - z0), Vector3(0, yp, (z0 + z1) * 0.5), "caillebotis")
	for sx2 in [-1.0, 1.0]:
		var xg: float = sx2 * (xa + 0.25)
		RemonteeKit.barre(g, Vector3(xg, yp + 1.05, z0), Vector3(xg, yp + 1.05, z1), 0.025, m, 6)
		RemonteeKit.barre(g, Vector3(xg, yp + 0.55, z0), Vector3(xg, yp + 0.55, z1), 0.018, m, 5)
		for k in range(4):
			var zz: float = lerpf(z0, z1, k / 3.0)
			RemonteeKit.barre(g, Vector3(xg, yp, zz), Vector3(xg, yp + 1.05, zz), 0.022, m, 5)
	RemonteeKit.barre(g, Vector3(-xa - 0.25, yp + 1.05, z1), Vector3(xa + 0.25, yp + 1.05, z1), 0.025, m, 6)
	RemonteeKit.boite_en(g, Vector3(0.75, 0.55, 0.9), Vector3(0, yp + 0.30, zc), "blanc_plaque")             # réducteur
	RemonteeKit.cylindre(g, 0.26, 0.26, 0.85, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-sm * 0.75, yp + 0.33, zc)), "bleu_doppelmayr", 16)
	RemonteeKit.boite_en(g, Vector3(0.5, 0.9, 0.35), Vector3(sm * (xa - 0.1), yp + 0.48, zb - 0.1), "blanc_plaque")  # armoire
	# tube-guide en demi-cercle derrière la poulie : les perches qui la contournent y glissent
	var c: Vector3 = Vector3(0, H - 0.55, zc)
	RemonteeKit.tube(g, RemonteeKit.arc(c, Vector3.RIGHT, Vector3.BACK, R + 0.55, -0.15, PI + 0.15, 24), 0.05, m, 8)
	for a in [0.2, PI * 0.5, PI - 0.2]:
		var q: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (R + 0.55)
		RemonteeKit.barre(g, q, Vector3(q.x, yl, q.z), 0.03, m, 5)
	# escalier incliné vers l'avant, côté descente, de la plate-forme à la neige ; mousse orange à son pied
	var xs: float = -sm * (xa + 0.65)
	var haut: Vector3 = Vector3(xs, yp, z0 + 0.2)
	var zpied: float = z0 + 0.2 - (yp - _gy(g, xs, z0 - 3.0)) * 0.85
	var bas: Vector3 = Vector3(xs, _gy(g, xs, zpied), zpied)
	for dx in [-0.35, 0.35]:
		RemonteeKit.poutre(g, bas + Vector3(dx, 0, 0), haut + Vector3(dx, 0, 0), 0.06, 0.16, m)
		RemonteeKit.barre(g, bas + Vector3(dx, 0.95, 0), haut + Vector3(dx, 0.95, 0), 0.022, m, 5)
	var n: int = int((haut.y - bas.y) / 0.24)
	for k2 in range(1, n):
		var q2: Vector3 = bas.lerp(haut, float(k2) / n)
		RemonteeKit.boite_en(g, Vector3(0.70, 0.03, 0.22), q2, "caillebotis")
	RemonteeKit.boite_en(g, Vector3(0.9, 1.7, 0.6), bas + Vector3(0, 0.85, -0.2), "mousse_orange")
	RemonteeKit.barre(g, haut, Vector3(-sm * xa, yp, z0 + 0.2), 0.05, m, 6)
	# échelle au poteau arrière, côté montée
	var xe: float = sm * (xa + 0.3)
	var ye: float = _gy(g, xe, zb)
	for dz in [-0.22, 0.22]:
		RemonteeKit.barre(g, Vector3(xe, ye, zb + dz), Vector3(xe, yp + 1.0, zb + dz), 0.02, m, 5)
	var y2: float = ye + 0.3
	while y2 < yp:
		RemonteeKit.barre(g, Vector3(xe, y2, zb - 0.22), Vector3(xe, y2, zb + 0.22), 0.015, m, 4)
		y2 += 0.3
	# panneau de la ligne sur le poteau avant, côté descente
	var lab: MeshInstance3D = RemonteeKit.texte_fige(g, lg.nom_court().to_upper(), 64, 0.004, Color(0.08, 0.20, 0.55))
	lab.position = Vector3(-sm * (xa + 0.12), H - 0.6, zf)
	lab.rotation = Vector3(0, PI * 0.5 * -sm, 0)


## Point de la glissière à u (0 : débrayage, à la sortie de la poulie ; 1 : déclencheur), repère de la ligne.
## Rampe d'entrée qui soulève la douille hors du câble, puis pente douce jusqu'au déclencheur, où la douille
## retombe sur le câble.
func _rail_glissiere(u: float, Hc: float, zc: float) -> Vector3:
	var xm: float = lg._x_brin(true)
	var zd: float = zc - 0.6
	var zl: float = 1.2
	var z: float = lerpf(zd, zl, u)
	var y_haut: float = Hc + Y_GLISSIERE
	var y_bas: float = Hc + 0.06
	var y: float
	if u < 0.12:
		y = lerpf(Hc, y_haut, smoothstep(0.0, 1.0, u / 0.12))
	else:
		y = lerpf(y_haut, y_bas, (u - 0.12) / 0.88)
	return Vector3(xm, y, z)


## Chalet du préposé Montaval : soubassement de pierre, bardage de mélèze, vitres, toit à deux pans enneigé.
func _chalet(g: Node3D, b: Vector3, t: Vector3, cote: float) -> void:
	RemonteeKit.boite_en(g, Vector3(t.x + 0.1, 1.0, t.z + 0.1), b + Vector3(0, 0.45, 0), "pierre")
	RemonteeKit.boite_en(g, Vector3(t.x, t.y - 0.9, t.z), b + Vector3(0, 0.95 + (t.y - 0.9) * 0.5, 0), "bois_meleze")
	RemonteeKit.boite_en(g, Vector3(0.04, 0.9, 1.6), b + Vector3(-cote * (t.x * 0.5 + 0.01), 1.55, 0), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(1.3, 0.9, 0.04), b + Vector3(0, 1.55, -(t.z * 0.5 + 0.01)), "vitrage_sombre")
	RemonteeKit.boite_en(g, Vector3(0.8, 1.9, 0.04), b + Vector3(0, 1.1, t.z * 0.5 + 0.01), "bois_fonce")
	for s in [-1.0, 1.0]:
		var pan: Transform3D = Transform3D(Basis(Vector3.BACK, -s * 0.45), b + Vector3(s * (t.x * 0.25 + 0.1), t.y + 0.30, 0))
		RemonteeKit.boite(g, Vector3(t.x * 0.62, 0.12, t.z + 0.7), pan, "toit_brun")
		RemonteeKit.boite(g, Vector3(t.x * 0.60, 0.14, t.z + 0.6), pan.translated_local(Vector3(0, 0.12, 0)), "neige_damee")


## Arrivées « lâcher sous poulie » à poulie flottante (reportages RM.net du Col du Palet et du Pays Désert) :
## la poulie de tension, sur un fût tubulaire blanc, est tirée vers l'arrière par des câbles qui montent au
## sommet d'un poussard (mât en treillis incliné vers elle) ; contrepoids cylindrique blanc au pied du
## poussard ; barres de protection rouges. Cotes estimées sur photo.
const LIGNES_LSP: Array = ["tkd_col_du_palet", "tkd_pays_desert"]


func lsp() -> bool:
	return String(lg.name) in LIGNES_LSP


func _arrivee_lsp(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var R: float = lg.voie * 0.5
	var y0: float = _gy(g, 0.0, zc)
	# fût blanc sous la poulie, mousse rouge au pied
	RemonteeKit.boite_en(g, Vector3(1.0, 0.4, 1.0), Vector3(0, y0 - 0.1, zc), "beton")
	RemonteeKit.cylindre(g, 0.17, 0.17, H - 0.3 - y0, Transform3D(Basis.IDENTITY, Vector3(0, (H - 0.3 + y0) * 0.5, zc)), "blanc_plaque", 14)
	RemonteeKit.cylindre(g, 0.30, 0.30, 1.6, Transform3D(Basis.IDENTITY, Vector3(0, y0 + 0.8, zc)), "mousse_rouge", 12)
	# poussard : deux montants et des barreaux, du sol (en arrière) jusqu'au-dessus de la poulie
	var zb: float = zc - (R + 3.5)
	var yb: float = _gy(g, 0.0, zb)
	var haut: Vector3 = Vector3(0, H + 3.0, zc - (R + 1.6))
	var bas: Vector3 = Vector3(0, yb, zb)
	for sx in [-0.28, 0.28]:
		RemonteeKit.barre(g, bas + Vector3(sx, 0, 0), haut + Vector3(sx * 0.6, 0, 0), 0.05, "galva", 6)
	var n: int = int(bas.distance_to(haut) / 0.45)
	for k in range(1, n):
		var q: Vector3 = bas.lerp(haut, float(k) / n)
		var e: float = lerpf(0.28, 0.17, float(k) / n)
		RemonteeKit.barre(g, q - Vector3(e, 0, 0), q + Vector3(e, 0, 0), 0.02, "galva", 4)
	RemonteeKit.boite_en(g, Vector3(1.0, 0.4, 1.0), Vector3(0, yb - 0.1, zb), "beton")
	# câbles de tension, du sommet du poussard au chevêtre de la poulie
	for sx2 in [-0.25, 0.25]:
		RemonteeKit.barre(g, haut + Vector3(sx2, 0, 0), Vector3(sx2, H + 0.5, zc - 0.4), 0.012, "cable", 5)
	# contrepoids cylindrique blanc au pied du poussard
	var xc: float = 1.1
	var yc: float = _gy(g, xc, zb + 0.4)
	RemonteeKit.cylindre(g, 0.45, 0.45, 2.4, Transform3D(Basis.IDENTITY, Vector3(xc, yc + 1.2, zb + 0.4)), "blanc_plaque", 18)
	RemonteeKit.barre(g, haut, Vector3(xc, yc + 2.4, zb + 0.4), 0.012, "cable", 5)
	# barres de protection rouges, couchées vers la poulie de part et d'autre
	for sx3 in [-1.0, 1.0]:
		var pied: Vector3 = Vector3(sx3 * (R + 1.6), _gy(g, sx3 * (R + 1.6), zc - 1.0), zc - 1.0)
		RemonteeKit.poutre(g, pied, pied + Vector3(-sx3 * 0.9, 1.6, 0.5), 0.24, 0.24, "mousse_rouge")


## Glissière des perches débrayées : deux fers plats en V (la douille y frotte), suspentes au longeron,
## déclencheur double au bout, au-dessus du skieur (boîtier et couteaux, poteau bleu jusqu'au sol).
func _glissiere(g: Node3D, zc: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var pts: PackedVector3Array = PackedVector3Array()
	var s0: float = lg.s_debrayage()
	var s1: float = lg.s_lancement()
	var nb: int = 60
	for k in range(nb + 1):
		var s: float = lerpf(s0, s1, float(k) / nb)
		pts.append(rail_local(s) - Vector3(0, g.position.y, 0) + Vector3(0, 0.10, 0))
	for dx in [-0.035, 0.035]:
		var pts2: PackedVector3Array = PackedVector3Array()
		for p in pts:
			pts2.append(p + Vector3(dx, 0, 0))
		RemonteeKit.tube(g, pts2, 0.018, "acier", 5)
	var yl: float = H + H_PORTIQUE - 0.05
	for k2 in range(6, nb + 1, 10):
		var p2: Vector3 = pts[k2]
		RemonteeKit.barre(g, p2 + Vector3(0, 0.03, 0), Vector3(p2.x, yl, p2.z), 0.014, "galva", 5)
	# déclencheur : boîtier sous le bout de la glissière, poteau jusqu'à la neige à côté du départ
	var pl: Vector3 = pts[nb]
	var sm: float = signf(lg._x_brin(true))
	RemonteeKit.boite_en(g, Vector3(0.22, 0.30, 0.40), pl + Vector3(sm * 0.20, 0.10, 0.0), "jaune_securite")
	RemonteeKit.barre(g, pl + Vector3(sm * 0.10, -0.02, 0.15), pl + Vector3(-sm * 0.05, -0.02, 0.15), 0.012, "acier_noir", 4)
	RemonteeKit.barre(g, pl + Vector3(sm * 0.10, -0.02, -0.12), pl + Vector3(-sm * 0.05, -0.02, -0.12), 0.012, "acier_noir", 4)
	var xp: float = pl.x + sm * 0.55
	var yp0: float = _gy(g, xp, pl.z)
	RemonteeKit.barre(g, Vector3(xp, yp0, pl.z), Vector3(xp, pl.y + 0.2, pl.z), 0.045, "bleu_doppelmayr", 8)
	RemonteeKit.barre(g, Vector3(xp, pl.y + 0.2, pl.z), pl + Vector3(sm * 0.30, 0.2, 0.0), 0.03, "bleu_doppelmayr", 6)


## Point de la glissière à l'abscisse s de la boucle (repère de la ligne), du débrayage au déclencheur.
func rail_local(s: float) -> Vector3:
	var Hc: float = lg.H_CABLE_GARE + lg.terrain(0.0)
	var s0: float = lg.s_debrayage()
	var s1: float = lg.s_lancement()
	return _rail_glissiere(clampf((s - s0) / maxf(s1 - s0, 0.01), 0.0, 1.0), Hc, lg.l_gare)


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
	if not aval and tkd():
		_jambe_et_contrepoids(g, zc, y0)
	# plate-forme de visite à claire-voie autour de la tête, garde-corps
	var yp: float = H + 0.78
	RemonteeKit.boite_en(g, Vector3(2.6, 0.06, 2.6), Vector3(0, yp, zc), "caillebotis")
	for k in range(4):
		var a: float = PI * 0.5 * k
		var u: Vector3 = Vector3(cos(a), 0, sin(a))
		var t: Vector3 = Vector3(-sin(a), 0, cos(a))
		RemonteeKit.barre(g, Vector3(0, yp + 1.0, zc) + u * 1.3 - t * 1.3, Vector3(0, yp + 1.0, zc) + u * 1.3 + t * 1.3, 0.025, "galva", 6)
		RemonteeKit.barre(g, Vector3(0, yp, zc) + u * 1.3 + t * 1.3, Vector3(0, yp + 1.0, zc) + u * 1.3 + t * 1.3, 0.025, "galva", 6)


## Gare amont des TKD (photos du Chardonnet, de Combe Folle, du 3000) : une jambe de force inclinée part du
## sol, en arrière de la poulie, jusqu'à un cadre en tête qui la relie au fût ; contrepoids de tension (bloc
## de béton entre deux glissières) le long du fût. Cotes estimées sur photo.
func _jambe_et_contrepoids(g: Node3D, zc: float, y0: float) -> void:
	var H: float = lg.H_CABLE_GARE
	var sg: float = -1.0                                # arrière de la gare amont (−z)
	var zj: float = zc + sg * (lg.voie * 0.5 + 3.5)
	var yj: float = _gy(g, 0.0, zj)
	var haut: Vector3 = Vector3(0, H + 0.75, zc + sg * 0.8)
	RemonteeKit.boite_en(g, Vector3(1.0, 0.5, 1.0), Vector3(0, yj - 0.1, zj), "beton")
	RemonteeKit.poutre(g, Vector3(0, yj, zj), haut, 0.32, 0.32, "galva")
	RemonteeKit.poutre(g, Vector3(0, H + 0.75, zc), haut, 0.22, 0.30, "galva")
	for sx in [-0.9, 0.9]:
		RemonteeKit.poutre(g, Vector3(sx, H + 0.75, zc - 0.9), Vector3(sx, H + 0.75, zc + 0.9), 0.14, 0.20, "galva")
	# contrepoids
	var xc: float = -0.75
	var yc: float = lerpf(y0, H, 0.45)
	for dz in [-0.32, 0.32]:
		RemonteeKit.barre(g, Vector3(xc, y0 + 0.4, zc + dz), Vector3(xc, H - 0.4, zc + dz), 0.035, "galva", 6)
	RemonteeKit.boite_en(g, Vector3(0.7, 1.5, 0.55), Vector3(xc, yc, zc), "beton")
	RemonteeKit.barre(g, Vector3(xc, yc + 0.75, zc), Vector3(xc, H - 0.3, zc), 0.012, "cable", 5)


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
	if montaval():
		if aval:
			_futs_montaval(g, zc, yb, xc)
		else:
			_colonnes_arrivee_montaval(g, zc, yb)
	for sx in ([] if montaval() else [-1.0, 1.0]):
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
		# local de la motrice : caisse blanche, vitres sombres, toit plat (Montaval : plus large, bandeau
		# vitré tout autour, photos du Montet)
		var c2: Vector3 = Vector3(0, yp, zc + 0.3)
		if montaval():
			RemonteeKit.boite_en(g, Vector3(2.0 * xc, 2.0, 2.6), c2 + Vector3(0, 1.0, 0), "blanc_plaque")
			RemonteeKit.boite_en(g, Vector3(2.0 * xc + 0.02, 0.7, 2.62), c2 + Vector3(0, 1.4, 0), "vitrage_sombre")
			RemonteeKit.boite_en(g, Vector3(2.0 * xc + 0.2, 0.10, 2.8), c2 + Vector3(0, 2.05, 0), "blanc_plaque")
		RemonteeKit.boite_en(g, Vector3(2.4, 2.1, 2.4), c2 + Vector3(0, 1.05, 0), "blanc_plaque")
		RemonteeKit.boite_en(g, Vector3(2.6, 0.12, 2.6), c2 + Vector3(0, 2.16, 0), "peinture_anthracite")
		for sx2 in [-1.0, 1.0]:
			RemonteeKit.boite_en(g, Vector3(0.03, 0.8, 1.6), c2 + Vector3(sx2 * 1.215, 1.35, 0), "vitrage_sombre")
		RemonteeKit.boite_en(g, Vector3(1.6, 0.8, 0.03), c2 + Vector3(0, 1.35, -1.215), "vitrage_sombre")


## TKE Montaval (photos du Montet) : trois fûts tubulaires galvanisés ancrés au rocher, deux à l'arrière et un
## seul à l'avant, vérins de réglage en tête des fûts, mousses rouges au pied, échelle au fût avant.
func _futs_montaval(g: Node3D, zc: float, yb: float, xc: float) -> void:
	for p in [Vector2(-xc, zc + 1.2), Vector2(xc, zc + 1.2), Vector2(0.0, zc - 1.4)]:
		var y0: float = _gy(g, p.x, p.y)
		RemonteeKit.boite_en(g, Vector3(0.9, 0.5, 0.9), Vector3(p.x, y0 - 0.1, p.y), "beton")
		RemonteeKit.cylindre(g, 0.26, 0.26, yb + 0.5 - y0, Transform3D(Basis.IDENTITY, Vector3(p.x, (yb + 0.5 + y0) * 0.5, p.y)), "galva", 16)
		RemonteeKit.cylindre(g, 0.36, 0.36, 1.9, Transform3D(Basis.IDENTITY, Vector3(p.x, y0 + 0.95, p.y)), "mousse_rouge", 14)
		RemonteeKit.cylindre(g, 0.12, 0.12, 0.9, Transform3D(Basis.IDENTITY, Vector3(p.x + 0.3, yb - 0.4, p.y)), "acier", 10)
	# poutres en long qui relient les fûts arrière au fût avant, sous la plate-forme
	for sx in [-1.0, 1.0]:
		RemonteeKit.poutre(g, Vector3(sx * xc, yb + 0.25, zc + 1.2), Vector3(0, yb + 0.25, zc - 1.4), 0.24, 0.4, "galva")
	var ya: float = _gy(g, 0.0, zc - 1.4)
	for dx in [-0.22, 0.22]:
		RemonteeKit.barre(g, Vector3(dx, ya + 2.0, zc - 1.75), Vector3(dx, yb + 1.6, zc - 1.75), 0.018, "galva", 5)
	var y2: float = ya + 2.2
	while y2 < yb + 1.5:
		RemonteeKit.barre(g, Vector3(-0.22, y2, zc - 1.75), Vector3(0.22, y2, zc - 1.75), 0.014, "galva", 4)
		y2 += 0.3


## Arrivée d'un TKE Montaval (photos de la gare amont du Montet) : deux colonnes galvanisées carrées dans l'axe,
## une à chaque bout du cadre, sans mousse ; portique en tête au-dessus de la plate-forme ; échelle sur la
## colonne arrière. Cotes estimées sur photo.
const Z_COLONNES_ARRIVEE: float = 1.9


func _colonnes_arrivee_montaval(g: Node3D, zc: float, yb: float) -> void:
	for sz in [-1.0, 1.0]:
		var z: float = zc + sz * Z_COLONNES_ARRIVEE
		var y0: float = _gy(g, 0.0, z)
		RemonteeKit.boite_en(g, Vector3(1.0, 0.5, 1.0), Vector3(0, y0 - 0.1, z), "beton")
		RemonteeKit.boite_en(g, Vector3(0.55, yb + 0.5 - y0, 0.55), Vector3(0, (yb + 0.5 + y0) * 0.5, z), "galva")
		# plats de renfort en tête de colonne
		RemonteeKit.boite_en(g, Vector3(0.75, 0.5, 0.75), Vector3(0, yb + 0.1, z), "galva")
	# poutre en long sous la plate-forme, d'une colonne à l'autre
	RemonteeKit.poutre(g, Vector3(0, yb + 0.25, zc - Z_COLONNES_ARRIVEE), Vector3(0, yb + 0.25, zc + Z_COLONNES_ARRIVEE), 0.4, 0.5, "galva")
	# portique en tête : deux montants et une traverse au-dessus de la plate-forme
	var yp: float = yb + 0.55
	for sx in [-1.4, 1.4]:
		RemonteeKit.poutre(g, Vector3(sx, yp, zc), Vector3(sx, yp + 2.6, zc), 0.16, 0.16, "galva")
	RemonteeKit.poutre(g, Vector3(-1.9, yp + 2.6, zc), Vector3(1.9, yp + 2.6, zc), 0.18, 0.24, "galva")
	# échelle sur la colonne arrière (côté opposé à la ligne : −z à l'amont)
	var ze: float = zc - Z_COLONNES_ARRIVEE - 0.35
	var ye: float = _gy(g, 0.0, ze)
	for dx in [-0.22, 0.22]:
		RemonteeKit.barre(g, Vector3(dx, ye, ze), Vector3(dx, yp + 1.0, ze), 0.018, "galva", 5)
	var y2: float = ye + 0.3
	while y2 < yp:
		RemonteeKit.barre(g, Vector3(-0.22, y2, ze), Vector3(0.22, y2, ze), 0.014, "galva", 4)
		y2 += 0.3


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
	# couloir : de 1 m avant le tapis à 9 m derrière (filets orange sur piquets noirs, photos du Signal et du
	# Montet)
	for cote in [-1.0, 1.0]:
		var x: float = xb + cote * 1.0
		var za: float = q.z - 0.5
		var zb: float = q.z + 9.0
		var n: int = 6
		for k in range(n + 1):
			var z: float = lerpf(za, zb, float(k) / n)
			var yp: float = _gy(g, x, z)
			RemonteeKit.barre(g, Vector3(x, yp - 0.2, z), Vector3(x, yp + 1.15, z), 0.022, "acier_noir", 5)
			if k < n:
				var z2: float = lerpf(za, zb, float(k + 1) / n)
				var y2: float = _gy(g, x, z2)
				var mid: Vector3 = Vector3(x, (yp + y2) * 0.5 + 0.6, (z + z2) * 0.5)
				var pan: Transform3D = Transform3D(Basis(Vector3.RIGHT, atan2(y2 - yp, -(z2 - z))), mid)
				RemonteeKit.boite(g, Vector3(0.02, 0.85, absf(z2 - z)), pan, "filet_orange")
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
	var lab: MeshInstance3D = RemonteeKit.texte_fige(g, "DÉPART\n%s" % lg.nom_court(), 56, 0.004, Color(0.08, 0.20, 0.55))
	lab.position = Vector3(xb + sx * 1.0, _gy(g, xb + sx * 1.0, q.z + 9.0) + 1.6, q.z + 9.0)
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
	var lab: MeshInstance3D = RemonteeKit.texte_fige(g, "LÂCHEZ\nLA PERCHE", 48, 0.004, Color(0.65, 0.06, 0.08))
	lab.position = Vector3(xb + signf(xb) * 1.4, _gy(g, xb + signf(xb) * 1.4, z + 6.0) + 2.2, z + 6.0 + 0.1)
	_cabane(g, Vector3(-signf(xb) * (lg.voie * 0.5 + 3.0), 0, zc + 3.0), -signf(xb))


## Cabane du perchman : planches vertes, grandes vitres, toit d'un pan. Montaval (photos du Signal et du
## Montet) : chalet de pierre jusqu'aux allèges, bardage de mélèze, toit à deux pans couvert de neige.
func _cabane(g: Node3D, c: Vector3, cote: float) -> void:
	var y: float = _gy(g, c.x, c.z)
	var t: Vector3 = Vector3(2.0, 2.3, 2.4)
	var b: Vector3 = Vector3(c.x, y, c.z)
	if montaval() or tkd():
		_chalet(g, b, t, cote)
		return
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
	if tkd() and aval:
		var xa: float = absf(lg._x_brin(true)) + 0.75
		for sx3 in [-1.0, 1.0]:
			for z3 in [0.35, zc - 1.6, zc + R + 0.6]:          # poteaux du portique (_portique_tkd)
				var ys3: float = lg._sol(sx3 * xa, z3)
				r.append([Vector3(0.5, H - ys3 + y0 + 2.0, 0.5), Vector3(sx3 * xa, (ys3 + y0 + H + 2.0) * 0.5, z3)])
	elif lg.famille != "perche_debrayable" and montaval():
		var pts3: Array = [Vector2(-(R + 0.9), zc + 1.2), Vector2(R + 0.9, zc + 1.2), Vector2(0.0, zc - 1.4)] if aval \
			else [Vector2(0.0, zc - Z_COLONNES_ARRIVEE), Vector2(0.0, zc + Z_COLONNES_ARRIVEE)]
		for p3 in pts3:
			var ys4: float = lg._sol(p3.x, p3.y)
			r.append([Vector3(0.75, 2.4, 0.75), Vector3(p3.x, ys4 + 1.2, p3.y)])
	elif lg.famille == "perche_debrayable":
		var ys: float = lg._sol(0.0, zc)
		var lt: float = 0.84                            # mât de l'arrivée (le départ : poteaux de la charpente, plus haut)
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
