class_name PortiqueEntree
extends RefCounted
## Portique d'information à l'entrée des files d'un télésiège, d'après les
## photos des reportages (consultées comme référence) :
##   Val d'Isère (Madeleine, Fontaine Froide, Datcha) : poteau noir au nom
##     du secteur avec pictogrammes, poteau rouge au nom de la station avec
##     la pendule à affichage lumineux et le plan des pistes, tous deux sur
##     un socle noir ; bandeau blanc au nom de la ligne, altitudes, débit,
##     vitesse et horaires d'ouverture et de fermeture ;
##   Tignes (Aiguille Percée) : bandeau noir — altitudes et horaires à
##     gauche, pendule rouge, nom de la ligne en grand à droite — sur deux
##     poteaux inox gainés de mousse rouge, totem « maîtrisez votre vitesse »
##     avec le plan des pistes.
## Repère du portique : X en travers, +Z vers le skieur qui arrive.

const OUVERTURE_VAL: String = "09:00"
const FERMETURE_VAL: String = "16:30"
const OUVERTURE_TIGNES: String = "09:15"
const FERMETURE_TIGNES: String = "16:40"


static func _txt(parent: Node3D, t: String, pos: Vector3, px: float, coul: Color,
		aligne: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, rot: float = 0.0, largeur: float = 0.0) -> Label3D:
	var lab: Label3D = Label3D.new()
	lab.text = t
	lab.font_size = 64
	lab.pixel_size = px
	# un nom trop long rétrécit pour tenir dans son cadre (largeur d'un
	# caractère ≈ 0,58 corps)
	if largeur > 0.0:
		var n: int = 0
		for ligne in t.split("\n"):
			n = maxi(n, ligne.length())
		lab.pixel_size = minf(px, largeur / maxf(n * 64.0 * 0.58, 1.0))
	lab.modulate = coul
	lab.outline_size = 0
	lab.double_sided = false
	lab.horizontal_alignment = aligne
	lab.position = pos
	lab.rotation.z = rot
	parent.add_child(lab)
	return lab


## Pendule lumineuse : l'heure (de l'appareil) mise à jour chaque seconde.
static func _pendule(parent: Node3D, pos: Vector3, px: float, coul: Color) -> void:
	var lab: Label3D = _txt(parent, "", pos, px, coul)
	lab.shaded = false
	var maj := func() -> void:
		var t: Dictionary = Time.get_time_dict_from_system()
		lab.text = "%02d:%02d" % [t["hour"], t["minute"]]
	maj.call()
	var tm: Timer = Timer.new()
	tm.wait_time = 1.0
	tm.autostart = true
	tm.timeout.connect(maj)
	parent.add_child(tm)


## Plan des pistes stylisé (panneau blanc, tracés de couleur).
static func _plan(parent: Node3D, c: Vector3, l: float, h: float) -> void:
	RemonteeKit.boite_en(parent, Vector3(l, h, 0.02), c, "blanc_plaque")
	var traits: Array = [["cabine_rouge", -0.30, 0.25, 0.20, -0.30], ["cabine_bleue", -0.10, 0.35, 0.35, -0.10],
		["noir_mat", 0.05, -0.35, 0.30, 0.30], ["jaune_securite", -0.35, -0.20, 0.10, 0.05]]
	for t in traits:
		var a: Vector3 = c + Vector3(float(t[1]) * l, float(t[2]) * h, 0.015)
		var b: Vector3 = c + Vector3(float(t[3]) * l, float(t[4]) * h, 0.015)
		RemonteeKit.poutre(parent, a, b, 0.025, 0.004, t[0], Vector3.BACK)


static func construire(ent: Node3D, lg: LigneRemontee, la: float) -> void:
	var L: float = lg.longueur_h()
	var alt0: float = lg.altitude_aval
	var alt1: float = alt0 + lg.terrain(L) - lg.terrain(0.0)
	var specs: String = "Alt. départ %d m · Alt. arrivée %d m · Débit %d pers/h · Vitesse %s m/s" % [
		roundi(alt0), roundi(alt1), roundi(lg.debit / 100.0) * 100, String.num(lg.vitesse, 1).replace(".", ",")]
	if lg.station.find("Val") >= 0:
		_val(ent, lg, la, specs)
	else:
		_tignes(ent, lg, la, roundi(alt0), roundi(alt1))


static func _val(ent: Node3D, lg: LigneRemontee, la: float, specs: String) -> void:
	var hp: float = 3.6
	var z: float = 0.30            # face avant des panneaux
	for sx in [-1.0, 1.0]:
		var x: float = sx * la
		RemonteeKit.boite_en(ent, Vector3(0.85, 0.95, 0.75), Vector3(x, 0.475, 0), "noir_mat")      # socle
		RemonteeKit.boite_en(ent, Vector3(0.70, hp - 0.95, 0.55), Vector3(x, 0.95 + (hp - 0.95) * 0.5, 0), "noir_mat" if sx < 0.0 else "rouge_val")
		# chant rouge du poteau noir, côté intérieur
		if sx < 0.0:
			RemonteeKit.boite_en(ent, Vector3(0.08, hp - 0.95, 0.56), Vector3(x - 0.36, 0.95 + (hp - 0.95) * 0.5, 0), "rouge_val")
	# poteau gauche : secteur à la verticale, pictogrammes
	var xg: float = -la
	_txt(ent, lg.quartier, Vector3(xg - 0.12, 2.45, z), 0.0042, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER, PI * 0.5, 2.3)
	for k in range(2):
		RemonteeKit.boite_en(ent, Vector3(0.20, 0.20, 0.02), Vector3(xg + 0.16, 2.55 - 0.28 * k, z), "plaque_bleue")
	# poteau droit : station, pendule, plan des pistes, pictogrammes
	var xd: float = la
	_txt(ent, "Val d'Isère", Vector3(xd, 3.25, z), 0.0030, Color(0.97, 0.97, 0.97), HORIZONTAL_ALIGNMENT_CENTER, 0.0, 0.62)
	RemonteeKit.boite_en(ent, Vector3(0.52, 0.20, 0.03), Vector3(xd, 2.82, z), "noir_mat")
	_pendule(ent, Vector3(xd, 2.82, z + 0.025), 0.0026, Color(1.0, 0.22, 0.15))
	_plan(ent, Vector3(xd, 2.20, z), 0.56, 0.75)
	for k in range(2):
		RemonteeKit.cylindre(ent, 0.09, 0.09, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(xd - 0.14 + 0.28 * k, 1.55, z)), "blanc_plaque", 16)
	# bandeau blanc (épais, toit enneigé) entre les poteaux
	var lb: float = 2.0 * la - 0.70
	var yb: float = hp - 0.45
	RemonteeKit.boite_en(ent, Vector3(lb, 0.90, 0.40), Vector3(0, yb, 0), "blanc_plaque")
	RemonteeKit.boite_en(ent, Vector3(lb + 0.1, 0.12, 0.46), Vector3(0, yb + 0.51, 0), "neige_damee")
	RemonteeKit.boite_en(ent, Vector3(lb * 0.30, 0.14, 0.02), Vector3(lb * 0.35, yb - 0.38, 0.21), "rouge_val")
	RemonteeKit.boite_en(ent, Vector3(lb * 0.22, 0.14, 0.02), Vector3(-lb * 0.37, yb - 0.38, 0.21), "noir_mat")
	_txt(ent, "école de ski / ski school ↓", Vector3(-lb * 0.37, yb - 0.38, 0.225), 0.0011, Color(0.95, 0.95, 0.95))
	# pictogramme du télésiège, nom, caractéristiques
	RemonteeKit.cylindre(ent, 0.17, 0.17, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-lb * 0.5 + 0.35, yb + 0.12, 0.21)), "noir_mat", 20)
	RemonteeKit.cylindre(ent, 0.14, 0.14, 0.022, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-lb * 0.5 + 0.35, yb + 0.12, 0.21)), "blanc_plaque", 20)
	_txt(ent, lg.nom_court(), Vector3(-lb * 0.5 + 0.62, yb + 0.12, 0.215), 0.0062, Color(0.20, 0.21, 0.24), HORIZONTAL_ALIGNMENT_LEFT, 0.0, lb - 2.0)
	_txt(ent, specs, Vector3(-lb * 0.5 + 0.62, yb - 0.17, 0.215), 0.0010, Color(0.30, 0.31, 0.34), HORIZONTAL_ALIGNMENT_LEFT, 0.0, lb - 2.0)
	# horaires
	var xh: float = lb * 0.5 - 0.42
	for k in range(2):
		var yh: float = yb + 0.18 - 0.26 * k
		RemonteeKit.boite_en(ent, Vector3(0.52, 0.18, 0.02), Vector3(xh, yh, 0.21), "noir_mat")
		_txt(ent, OUVERTURE_VAL if k == 0 else FERMETURE_VAL, Vector3(xh + 0.05, yh, 0.225), 0.0022, Color(0.97, 0.97, 0.97))
		_txt(ent, "ouvert / open" if k == 0 else "fermé / closed", Vector3(xh - 0.30, yh, 0.225), 0.0010, Color(0.25, 0.26, 0.30), HORIZONTAL_ALIGNMENT_RIGHT)
	_cordes(ent, la)


static func _tignes(ent: Node3D, lg: LigneRemontee, la: float, alt0: int, alt1: int) -> void:
	var hp: float = 3.3
	for sx in [-1.0, 1.0]:
		var x: float = sx * (la - 0.2)
		RemonteeKit.cylindre(ent, 0.09, 0.09, hp, Transform3D(Basis.IDENTITY, Vector3(x, hp * 0.5, 0)), "acier", 12)
		RemonteeKit.cylindre(ent, 0.24, 0.24, 1.8, Transform3D(Basis.IDENTITY, Vector3(x, 0.9, 0)), "mousse_rouge", 14)
	# bandeau noir
	var lb: float = 2.0 * la + 0.3
	var yb: float = hp - 0.15
	var z: float = 0.09
	RemonteeKit.boite_en(ent, Vector3(lb, 0.85, 0.16), Vector3(0, yb, 0), "noir_mat")
	RemonteeKit.boite_en(ent, Vector3(lb, 0.26, 0.10), Vector3(0, yb - 0.55, 0), "noir_mat")
	var x0: float = -lb * 0.5
	_txt(ent, "%d M\n%d M" % [alt1, alt0], Vector3(x0 + 0.12, yb + 0.05, z + 0.005), 0.0026, Color(0.96, 0.96, 0.96), HORIZONTAL_ALIGNMENT_LEFT)
	_txt(ent, "OUVERT  %s\nFERMÉ   %s" % [OUVERTURE_TIGNES.replace(":", "h"), FERMETURE_TIGNES.replace(":", "h")], Vector3(x0 + 0.95, yb + 0.15, z + 0.005), 0.0016, Color(0.55, 0.95, 0.45), HORIZONTAL_ALIGNMENT_LEFT)
	RemonteeKit.boite_en(ent, Vector3(0.48, 0.17, 0.02), Vector3(x0 + 1.25, yb - 0.20, z), "acier_noir")
	_pendule(ent, Vector3(x0 + 1.25, yb - 0.20, z + 0.015), 0.0024, Color(1.0, 0.18, 0.12))
	# pictogramme et nom en grand
	RemonteeKit.boite_en(ent, Vector3(0.40, 0.40, 0.02), Vector3(x0 + 1.95, yb + 0.03, z), "blanc_plaque")
	_txt(ent, lg.nom_court().to_upper(), Vector3(x0 + 2.25, yb + 0.03, z + 0.005), 0.0055, Color(0.97, 0.97, 0.97), HORIZONTAL_ALIGNMENT_LEFT, 0.0, lb - 2.4)
	_txt(ent, "➜  " + lg.quartier.to_upper(), Vector3(0, yb - 0.55, 0.055), 0.0016, Color(0.95, 0.95, 0.95))
	# totem à droite : maîtrisez votre vitesse, plan des pistes
	var xt: float = la + 0.75
	RemonteeKit.boite_en(ent, Vector3(0.95, 3.2, 0.22), Vector3(xt, 1.6, 0), "acier_noir")
	RemonteeKit.boite_en(ent, Vector3(0.80, 0.62, 0.02), Vector3(xt, 2.70, 0.115), "blanc_plaque")
	_txt(ent, "Maîtrisez\nvotre vitesse\n\nControl\nyour speed", Vector3(xt, 2.70, 0.13), 0.0011, Color(0.20, 0.15, 0.40))
	_plan(ent, Vector3(xt, 1.85, 0.115), 0.70, 0.80)
	_cordes(ent, la)


## Cordes noires de la file, des poteaux vers l'arrière.
static func _cordes(ent: Node3D, la: float) -> void:
	for sx in [-1.0, 1.0]:
		var a: Vector3 = Vector3(sx * la, 1.0, 0.3)
		var b: Vector3 = Vector3(sx * (la + 0.8), 0.95, 4.5)
		RemonteeKit.cylindre(ent, 0.05, 0.05, 1.1, Transform3D(Basis.IDENTITY, b - Vector3(0, 0.4, 0)), "noir_mat", 8)
		var pts: PackedVector3Array = PackedVector3Array()
		for k in range(9):
			var t: float = float(k) / 8.0
			pts.append(a.lerp(b, t) - Vector3(0, sin(PI * t) * 0.25, 0))
		RemonteeKit.tube(ent, pts, 0.018, "noir_mat", 5)
