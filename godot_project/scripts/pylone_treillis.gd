class_name PyloneTreillis
extends Node3D
## Pylône en treillis d'acier pour 3S et téléphérique va-et-vient : quatre
## membrures qui s'effilent, croisillons en X par panneau, chevêtre en tête
## portant les SABOTS des câbles porteurs (le câble y repose dans une gorge)
## et les poulies du câble tracteur. Repère : X en travers, −Z vers l'amont.

@export var hauteur: float = 30.0
@export var voie: float = 10.0             # 3S Olympique : 10 m ; téléphérique ~ 8 m
@export var porteurs_par_voie: int = 2     # 3S : 2 ; téléphérique : 1 ou 2
@export var ecart_porteurs: float = 0.60
@export var numero: int = 1
@export var l_sabot: float = 7.0         # longueur des sabots (porteurs) dans l'axe
@export var pente: float = 0.0           # pente des porteurs au pylône (rad, > 0 : monte vers −Z)
@export var deviation: float = 0.0       # déviation des porteurs (rad, > 0 : convexe)
## Téléphérique va-et-vient (Grande Motte, photos) : fût élancé à base
## étroite, élargi en tête jusqu'à la voie (évasement), un sabot court par
## voie posé directement sur la tête, portique de levage au-dessus.
@export var va_et_vient: bool = false
## Sol sous un point (0, ?, z) du pylône, relatif à sa base (tours accolées
## d'un long sabot, sur la crête) ; posé par la ligne.
var sol_z: Callable = Callable()
## 3S, posés par la ligne : forme ("ouvrage", "plots", "plots_bas"), câble (z, montée) et sol (x, z) relatifs à la
## base, abscisse du brin montant, longueurs de poutre vers l'amont (−z) et vers l'aval (+z).
var forme: String = "plots_bas"
var cable_y: Callable = Callable()
var sol_xz: Callable = Callable()
var x_montee: float = 1.0
var l_amont: float = 6.0
var l_aval: float = 6.0


func construire() -> void:
	for f in _debut_construction():
		(f as Callable).call()


## construire() en étapes (sabots, rangs ou fût, têtes), `pause` attendue entre deux : un pylône du 3S faisait 21 ms
## en moyenne d'un bloc, 42 au pire (relevé du 07/11/2026).
func construire_par_tranches(pause: Callable) -> void:
	for f in _debut_construction():
		(f as Callable).call()
		await pause.call()


func _debut_construction() -> Array:
	for c in get_children():
		c.queue_free()
	if va_et_vient:
		return [_construire_vav]
	return _phases_3s()


## Pylônes du 3S. Commun : deux poutres de sabot, une par voie, qui suivent le câble (le porteur repose dessus
## sur toute leur longueur, sans lévitation), tête en T au-dessus du toit des cabines, portique de levage.
## Ouvrage du haut : longues poutres cintrées sur quatre rangées de deux pieds, porte-à-faux plongeant à l'aval.
## P1 : quatre montants sur de gros plots ronds, base rouge. P2 : tour élancée sur plots bas.
## Cotes estimées sur photo, d'après la voie de 10 m (±15 %).
func _phases_3s() -> Array:
	var m: String = "galva_pylone"
	var y_c := func(z: float, montee: bool = true) -> float:
		return float(cable_y.call(z, montee)) if cable_y.is_valid() else hauteur_porteurs() - z * sin(pente)
	var ouvrage: bool = forme == "ouvrage"
	var rangs: Array = RANGS_OUVRAGE if ouvrage else [-1.2, 1.2]
	var ph: Array = []
	for sx in [-1.0, 1.0]:
		ph.append(func() -> void: _poutre_sabot(sx, y_c, m))
	if ouvrage:
		for z in rangs:
			ph.append(func() -> void: _rang_ouvrage(float(z), y_c, m))
		ph.append(func() -> void:
			for k in range(rangs.size() - 1):
				_entre_rangs(float(rangs[k]), float(rangs[k + 1]), y_c, m))
		ph.append(func() -> void:
			for z2 in [rangs[0], rangs[2]]:
				_tete(float(z2), y_c, m)
			_escalier(float(rangs[1]) + 2.5, y_c, m))
	else:
		ph.append(func() -> void: _fut_3s(y_c, m))
		ph.append(func() -> void:
			for z3 in rangs:
				_tete(float(z3), y_c, m))
	# plate-forme centrale, sous le portique
	ph.append(func() -> void:
		var zp: float = float(rangs[0])
		RemonteeKit.boite_en(self, Vector3(3.2, 0.04, 2.6), Vector3(0, float(y_c.call(zp)) - 0.95, zp), "caillebotis"))
	return ph


const RANGS_OUVRAGE: Array = [-1.0, 6.0, 13.0, 20.0]
const X_PIED: float = 2.4
const X_TETE: float = 1.5
## Dessous de la poutre de sabot, sous le câble. Plus bas : la suspente passe sous elle vers le toit de la cabine.
const DESSOUS_POUTRE: float = 1.85


func _sol(x: float, z: float) -> float:
	if sol_xz.is_valid():
		return float(sol_xz.call(x, z))
	return float(sol_z.call(z)) if sol_z.is_valid() else 0.0


func _poutre_sabot(sx: float, y_c: Callable, m: String) -> void:
	var montee: bool = signf(sx) == signf(x_montee)
	var x0: float = sx * voie * 0.5
	var z0: float = -l_amont
	var z1: float = l_aval
	var n: int = maxi(6, int((z1 - z0) / 1.5))
	var dessus: Array = [PackedVector3Array(), PackedVector3Array()]
	var rampe: PackedVector3Array = PackedVector3Array()
	var prec: Array = []
	for i in range(n + 1):
		var z: float = lerpf(z0, z1, float(i) / n)
		var y: float = float(y_c.call(z, montee))
		for k in range(2):
			(dessus[k] as PackedVector3Array).append(Vector3(x0 + (k - 0.5) * ecart_porteurs, y - 0.0285 - 0.05, z))
		var c: Vector3 = Vector3(x0, y - 1.40, z)
		var p: Vector3 = Vector3(x0 - sx * 1.0, y - 0.98, z)
		rampe.append(Vector3(x0 - sx * 1.42, y + 0.10, z))
		if i > 0:
			RemonteeKit.poutre(self, prec[0], c, 0.60, 0.85, m)
			RemonteeKit.poutre(self, prec[1], p, 0.90, 0.04, "caillebotis")
		if i % 2 == 0:
			# montants sous les porteurs, garde-corps
			for k3 in [-0.5, 0.5]:
				RemonteeKit.boite_en(self, Vector3(0.07, 0.86, 0.10), Vector3(x0 + k3 * ecart_porteurs, y - 0.54, z), m)
			RemonteeKit.barre(self, Vector3(x0 - sx * 1.42, y - 0.98, z), Vector3(x0 - sx * 1.42, y + 0.10, z), 0.02, "galva", 5)
		prec = [c, p]
	for k2 in range(2):
		RemonteeKit.tube(self, dessus[k2], 0.05, "acier_noir", 6)
	RemonteeKit.tube(self, rampe, 0.022, "galva", 5)
	# galets du tracteur, sous lui, à pas régulier le long du sabot (son arc, pas sa projection)
	var zs: PackedFloat32Array = PackedFloat32Array()
	var ls: PackedFloat32Array = PackedFloat32Array()
	var lt: float = 0.0
	var ns: int = 120
	for j in range(ns + 1):
		var zj: float = lerpf(z0 + 0.6, z1 - 0.6, float(j) / ns)
		if j > 0:
			lt += Vector2(zj - zs[j - 1], float(y_c.call(zj, montee)) - float(y_c.call(zs[j - 1], montee))).length()
		zs.append(zj)
		ls.append(lt)
	var ng: int = maxi(3, int(lt / 2.4) + 1)
	var jj: int = 0
	for k4 in range(ng):
		var lk: float = lt * float(k4) / (ng - 1)
		while jj < ns - 1 and ls[jj + 1] < lk:
			jj += 1
		var zg: float = lerpf(zs[jj], zs[jj + 1], clampf((lk - ls[jj]) / maxf(ls[jj + 1] - ls[jj], 1e-6), 0.0, 1.0))
		RemonteeKit.galet(self, Vector3(x0, float(y_c.call(zg, montee)) + VehiculeRemontee.Y_TRACTEUR_3S - 0.03 - 0.21, zg), 0.21)


## Tête en T : traverse sous les poutres, centre qui monte au portique, haubans jusqu'à son bout.
func _tete(z: float, y_c: Callable, m: String) -> void:
	var y: float = float(y_c.call(z))
	var xe: float = voie * 0.5 + 0.7
	RemonteeKit.poutre(self, Vector3(-xe + 0.4, y - DESSOUS_POUTRE - 0.15, z), Vector3(xe - 0.4, y - DESSOUS_POUTRE - 0.15, z), 0.30, 0.20, m)
	for sx in [-1.0, 1.0]:
		var bas: Vector3 = Vector3(sx * X_TETE, y - DESSOUS_POUTRE, z)
		var haut: Vector3 = Vector3(sx * X_TETE, y + 2.5, z)
		RemonteeKit.poutre(self, bas, haut, 0.18, 0.18, m)
		RemonteeKit.poutre(self, Vector3(sx * X_TETE, y - 0.8, z), Vector3(sx * (voie * 0.5 - 1.40), y + 2.5, z), 0.10, 0.10, m)
		RemonteeKit.poutre(self, Vector3(sx * X_TETE, y + 0.6, z), Vector3(-sx * X_TETE, y + 2.5, z), 0.08, 0.08, m)
	RemonteeKit.poutre(self, Vector3(-xe, y + 2.55, z), Vector3(xe, y + 2.55, z), 0.26, 0.22, m)


## Deux pieds d'une rangée de l'ouvrage, croisillons dans son plan.
func _rang_ouvrage(z: float, y_c: Callable, m: String) -> void:
	var y_t: float = float(y_c.call(z)) - DESSOUS_POUTRE - 0.25
	var pieds: Array = []
	for sx in [-1.0, 1.0]:
		var y_b: float = _sol(sx * X_PIED, z)
		RemonteeKit.boite_en(self, Vector3(1.2, 0.8, 1.2), Vector3(sx * X_PIED, y_b, z), "beton")
		var a: Vector3 = Vector3(sx * X_PIED, y_b + 0.4, z)
		var b: Vector3 = Vector3(sx * X_TETE, y_t, z)
		RemonteeKit.poutre(self, a, b, 0.24, 0.24, m)
		pieds.append([a, b])
		# hauban de la traverse, sous la poutre et hors du passage des cabines
		RemonteeKit.poutre(self, a.lerp(b, 0.72), Vector3(sx * (voie * 0.5 - 1.75), y_t, z), 0.12, 0.12, m)
	var n: int = maxi(2, int((y_t - (pieds[0][0] as Vector3).y) / 4.0))
	for k in range(n):
		var u0: float = float(k) / n
		var u1: float = float(k + 1) / n
		var g0: Vector3 = (pieds[0][0] as Vector3).lerp(pieds[0][1], u0)
		var g1: Vector3 = (pieds[0][0] as Vector3).lerp(pieds[0][1], u1)
		var d0: Vector3 = (pieds[1][0] as Vector3).lerp(pieds[1][1], u0)
		var d1: Vector3 = (pieds[1][0] as Vector3).lerp(pieds[1][1], u1)
		RemonteeKit.poutre(self, g0, d1, 0.09, 0.09, m)
		RemonteeKit.poutre(self, d0, g1, 0.09, 0.09, m)
		RemonteeKit.poutre(self, g1, d1, 0.11, 0.11, m)


## Entre deux rangées : longrine haute et grand croisillon de tubes, de chaque côté.
func _entre_rangs(z0: float, z1: float, y_c: Callable, m: String) -> void:
	for sx in [-1.0, 1.0]:
		var y0: float = float(y_c.call(z0)) - DESSOUS_POUTRE - 0.25
		var y1: float = float(y_c.call(z1)) - DESSOUS_POUTRE - 0.25
		var b0: float = _sol(sx * X_PIED, z0) + 0.4
		var b1: float = _sol(sx * X_PIED, z1) + 0.4
		var hb: Vector3 = Vector3(sx * lerpf(X_PIED, X_TETE, 0.45), lerpf(b0, y0, 0.45), z0)
		var hc: Vector3 = Vector3(sx * lerpf(X_PIED, X_TETE, 0.45), lerpf(b1, y1, 0.45), z1)
		RemonteeKit.poutre(self, Vector3(sx * X_TETE, y0, z0), Vector3(sx * X_TETE, y1, z1), 0.14, 0.14, m)
		RemonteeKit.poutre(self, hb, hc, 0.11, 0.11, m)
		RemonteeKit.poutre(self, hb, Vector3(sx * X_TETE, y1, z1), 0.10, 0.10, m)
		RemonteeKit.poutre(self, Vector3(sx * X_TETE, y0, z0), hc, 0.10, 0.10, m)
		RemonteeKit.poutre(self, hb, Vector3(sx * X_PIED, b1, z1), 0.10, 0.10, m)
		RemonteeKit.poutre(self, Vector3(sx * X_PIED, b0, z0), hc, 0.10, 0.10, m)


## Escalier en zigzag, entre les pieds d'une travée.
func _escalier(z: float, y_c: Callable, m: String) -> void:
	var y_b: float = _sol(0.0, z) + 0.2
	var y_t: float = float(y_c.call(z)) - 1.0
	var n: int = maxi(2, int((y_t - y_b) / 2.6))
	for k in range(n):
		var ya: float = lerpf(y_b, y_t, float(k) / n)
		var yb: float = lerpf(y_b, y_t, float(k + 1) / n)
		var s: float = 1.0 if k % 2 == 0 else -1.0
		RemonteeKit.poutre(self, Vector3(0.45 * s, ya, z - s * 1.1), Vector3(0.45 * s, yb, z + s * 1.1), 0.70, 0.05, "caillebotis")
		RemonteeKit.boite_en(self, Vector3(1.7, 0.04, 0.8), Vector3(0, yb, z + s * 1.4), "caillebotis")
		RemonteeKit.barre(self, Vector3(0.82 * s, ya + 1.0, z - s * 1.1), Vector3(0.82 * s, yb + 1.0, z + s * 1.1), 0.02, "galva", 5)
		RemonteeKit.barre(self, Vector3(0.82 * s, yb, z + s * 1.4), Vector3(0.82 * s, yb + 1.0, z + s * 1.1), 0.02, "galva", 5)


## P1 et P2 : fût à quatre montants, sur ses plots.
func _fut_3s(y_c: Callable, m: String) -> void:
	var b0: float = 5.5
	var y_t: float = float(y_c.call(0.0)) - DESSOUS_POUTRE - 0.25
	var plots: bool = forme == "plots"
	var pieds: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var x: float = sx * b0 * 0.5
			var z: float = sz * b0 * 0.5
			var y_b: float = _sol(x, z)
			var y_h: float = y_b + 0.5
			if plots:
				# gros plot de béton, et autour de son pied le matelas de protection contre lequel un skieur
				# qui sort de la piste viendrait s'écraser
				RemonteeKit.cylindre(self, 0.72, 0.72, 4.3, Transform3D(Basis.IDENTITY, Vector3(x, y_b + 1.65, z)), "beton", 14)
				RemonteeKit.cylindre(self, 0.86, 0.86, 2.3, Transform3D(Basis.IDENTITY, Vector3(x, y_b + 0.65, z)), "matelas_piste", 14)
				y_h = y_b + 3.8
			else:
				RemonteeKit.cylindre(self, 0.75, 0.75, 1.0, Transform3D(Basis.IDENTITY, Vector3(x, y_b, z)), "beton", 12)
			var a: Vector3 = Vector3(x, y_h, z)
			var b: Vector3 = Vector3(sx * X_TETE, y_t, sz * 1.2)
			RemonteeKit.poutre(self, a, b, 0.22, 0.22, m)
			pieds.append([a, b])
	# ordre des faces autour du fût : 0 (−,−), 1 (−,+), 3 (+,+), 2 (+,−)
	var tour: Array = [0, 1, 3, 2]
	var y_moy: float = ((pieds[0][0] as Vector3).y + (pieds[3][0] as Vector3).y) * 0.5
	var n: int = maxi(3, int((y_t - y_moy) / 4.0))
	for f in range(4):
		var pa: Array = pieds[tour[f]]
		var pb: Array = pieds[tour[(f + 1) % 4]]
		for k in range(n):
			var a0: Vector3 = (pa[0] as Vector3).lerp(pa[1], float(k) / n)
			var a1: Vector3 = (pa[0] as Vector3).lerp(pa[1], float(k + 1) / n)
			var b0p: Vector3 = (pb[0] as Vector3).lerp(pb[1], float(k) / n)
			var b1p: Vector3 = (pb[0] as Vector3).lerp(pb[1], float(k + 1) / n)
			RemonteeKit.poutre(self, a0, b1p, 0.09, 0.09, m)
			RemonteeKit.poutre(self, b0p, a1, 0.09, 0.09, m)
			RemonteeKit.poutre(self, a1, b1p, 0.11, 0.11, m)


## Fût en treillis carré de b0 (base) à b1 (sommet), sur une hauteur h.
func _fut(b0: float, b1: float, h: float, m: String) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.boite_en(self, Vector3(1.4, 0.8, 1.4), Vector3(sx * b0 * 0.5, -0.2, sz * b0 * 0.5), "beton")
			RemonteeKit.poutre(self, Vector3(sx * b0 * 0.5, 0.2, sz * b0 * 0.5), Vector3(sx * b1 * 0.5, h, sz * b1 * 0.5), 0.24, 0.24, m)
	var n_p: int = maxi(3, int(h / 4.0))
	for i in range(n_p):
		var ya: float = 0.2 + (h - 0.2) * float(i) / n_p
		var yb: float = 0.2 + (h - 0.2) * float(i + 1) / n_p
		var ba: float = lerpf(b0, b1, ya / h) * 0.5
		var bb: float = lerpf(b0, b1, yb / h) * 0.5
		for face in range(4):
			var a: float = PI * 0.5 * face
			var u: Vector3 = Vector3(cos(a), 0, sin(a))
			var v: Vector3 = Vector3(-sin(a), 0, cos(a))
			var p1: Vector3 = (u + v) * ba + Vector3(0, ya, 0)
			var p2: Vector3 = (u - v) * ba + Vector3(0, ya, 0)
			var p3: Vector3 = (u + v) * bb + Vector3(0, yb, 0)
			var p4: Vector3 = (u - v) * bb + Vector3(0, yb, 0)
			RemonteeKit.poutre(self, p1, p4, 0.09, 0.09, m)
			RemonteeKit.poutre(self, p2, p3, 0.09, 0.09, m)
			RemonteeKit.poutre(self, p3, p4, 0.11, 0.11, m)


## Pylône de téléphérique va-et-vient (photos de la Grande Motte) : fût
## carré élancé (base 0,15 h), évasement en tête jusqu'à la voie, poutre de
## tête en caisson, un sabot par voie avec ses galets de tracteur, échelle,
## plate-forme et portique de levage au-dessus des sabots.
func _construire_vav() -> void:
	var m: String = "galva_pylone"
	var he: float = 5.0                              # hauteur de l'évasement
	var hf: float = maxf(hauteur - he, 6.0)
	var b0: float = clampf(hauteur * 0.15, 3.5, 9.0)
	var b1: float = 2.4
	_fut(b0, b1, hf, m)
	var xe: float = voie * 0.5 + 0.6
	var y1: float = hauteur
	# évasement : quatre membrures du sommet du fût aux bouts de la tête
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.poutre(self, Vector3(sx * b1 * 0.5, hf, sz * b1 * 0.5), Vector3(sx * xe, y1, sz * 0.9), 0.20, 0.20, m)
			RemonteeKit.poutre(self, Vector3(-sx * b1 * 0.5, hf, sz * b1 * 0.5), Vector3(sx * xe * 0.5, y1, sz * 0.9), 0.10, 0.10, m)
		RemonteeKit.poutre(self, Vector3(sx * b1 * 0.5, hf, -b1 * 0.5), Vector3(sx * b1 * 0.5, hf, b1 * 0.5), 0.14, 0.14, m)
	# poutre de tête (deux caissons) et sabots
	for sz in [-0.9, 0.9]:
		RemonteeKit.poutre(self, Vector3(-xe, y1, sz), Vector3(xe, y1, sz), 0.30, 0.50, m)
	var yp: float = hauteur_porteurs()
	var sab: Node3D = Node3D.new()
	sab.position = Vector3(0, yp, 0)
	sab.rotation.x = pente
	add_child(sab)
	var ls: float = l_sabot
	var kappa: float = maxf(deviation, 0.004) / maxf(ls, 1.0)
	for sx in [-1.0, 1.0]:
		var x0: float = sx * voie * 0.5
		# un sabot (gorge) sous chaque porteur de la voie
		for kp in range(porteurs_par_voie):
			var xp: float = x0 + (kp - (porteurs_par_voie - 1) * 0.5) * ecart_porteurs
			var pts: PackedVector3Array = PackedVector3Array()
			for i2 in range(13):
				var z: float = lerpf(-ls * 0.5, ls * 0.5, float(i2) / 12.0)
				pts.append(Vector3(xp, -PyloneRemontee.R_CABLE - 0.05 - kappa * z * z * 0.5, z))
			RemonteeKit.tube(sab, pts, 0.08, "acier_noir", 8)
		RemonteeKit.poutre(sab, Vector3(x0, -0.40, -ls * 0.45), Vector3(x0, -0.40, ls * 0.45), 0.30 + (porteurs_par_voie - 1) * ecart_porteurs, 0.55, m)
		RemonteeKit.poutre(sab, Vector3(x0, -0.75, -ls * 0.30), Vector3(x0, y1 - yp, -0.9), 0.14, 0.14, m)
		RemonteeKit.poutre(sab, Vector3(x0, -0.75, ls * 0.30), Vector3(x0, y1 - yp, 0.9), 0.14, 0.14, m)
		for sz2 in [-ls * 0.25, ls * 0.25]:
			RemonteeKit.galet(sab, Vector3(x0, -0.45 - 0.03 - 0.20 - kappa * sz2 * sz2 * 0.5, sz2), 0.20)
		# portique de levage au-dessus du sabot (photos)
		for sz3 in [-1.0, 1.0]:
			RemonteeKit.poutre(sab, Vector3(x0 - sx * 0.6, -0.1, sz3 * 1.2), Vector3(x0, 2.6, sz3 * 0.5), 0.10, 0.10, m)
		RemonteeKit.poutre(sab, Vector3(x0, 2.6, -0.6), Vector3(x0, 2.6, 0.6), 0.16, 0.16, m)
	RemonteeKit.poutre(sab, Vector3(-voie * 0.5, 2.6, 0), Vector3(voie * 0.5, 2.6, 0), 0.14, 0.14, m)
	# plate-forme et garde-corps sur la tête
	RemonteeKit.boite_en(self, Vector3(2.0 * xe, 0.04, 2.6), Vector3(0, y1 + 0.27, 0), "caillebotis")
	for sz4 in [-1.3, 1.3]:
		RemonteeKit.barre(self, Vector3(-xe, y1 + 1.3, sz4), Vector3(xe, y1 + 1.3, sz4), 0.025, "galva", 6)
	# échelle le long d'une membrure
	RemonteeKit.barre(self, Vector3(b0 * 0.5 + 0.3, 0.3, b0 * 0.5), Vector3(b1 * 0.5 + 0.3, hf, b1 * 0.5), 0.03, "galva", 6)


## Hauteur (locale) d'appui des porteurs.
func hauteur_porteurs() -> float:
	if va_et_vient:
		return hauteur + 0.25 + 0.95
	return hauteur + 2.2 + 0.24 + 0.55
