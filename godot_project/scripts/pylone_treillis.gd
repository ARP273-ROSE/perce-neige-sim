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


func construire() -> void:
	for c in get_children():
		c.queue_free()
	if va_et_vient:
		_construire_vav()
		return
	# (retour d'utilisateur, 25/10/2026 : « la charpente est trop large par rapport
	# aux sabots, la cabine rentre dedans ; pylônes trop petits ; le pylône du
	# haut de la montée est très grand, plusieurs pylônes accolés » — photos
	# Commons de l'Olympique depuis la Tête du Solaise) : le caisson de tête
	# reste ENTRE les deux files de cabines, les sabots sont portés par des
	# consoles en treillis au-dessus du toit des cabines ; un sabot de plus
	# de 15 m est porté par trois tours accolées le long de la ligne.
	var m: String = "peinture_gris"
	var yp: float = hauteur_porteurs()
	var kappa: float = maxf(deviation, 0.004) / maxf(l_sabot, 1.0)
	var zs: Array = [0.0] if l_sabot < 15.0 else [-l_sabot * 0.33, 0.0, l_sabot * 0.33]
	for zk in zs:
		# hauteur du dessous des porteurs au droit de la tour, et sol sous elle
		var y_s: float = yp - float(zk) * sin(pente) - kappa * float(zk) * float(zk) * 0.5
		var y_sol: float = float(sol_z.call(zk)) if sol_z.is_valid() else 0.0
		_tour(float(zk), y_sol, y_s - (yp - hauteur), m, zs.size() > 1)
	# sabots, passerelles et galets : inclinés sur la pente des porteurs,
	# cintrés selon leur déviation (le porteur se couche dans la gorge)
	var sab: Node3D = Node3D.new()
	sab.name = "Sabots"
	sab.position = Vector3(0, yp, 0)
	sab.rotation.x = pente
	add_child(sab)
	var y1: float = -(yp - hauteur) + HT_CAISSON                # dessus du caisson (repère du sabot)
	for sx in [-1.0, 1.0]:
		var x0: float = sx * voie * 0.5
		var ls: float = l_sabot
		var n_s: int = maxi(16, int(ls * 2.0))
		for k in range(porteurs_par_voie):
			var x: float = x0 + (float(k) - (porteurs_par_voie - 1) * 0.5) * ecart_porteurs
			var pts: PackedVector3Array = PackedVector3Array()
			for i2 in range(n_s + 1):
				var z: float = lerpf(-ls * 0.5, ls * 0.5, float(i2) / n_s)
				pts.append(Vector3(x, -PyloneRemontee.R_CABLE - 0.04 - kappa * z * z * 0.5, z))
			RemonteeKit.tube(sab, pts, 0.07, "acier_noir", 8)
		# poutre de sabot cintrée sous les deux porteurs, d'un bout à l'autre
		var nb: int = maxi(6, int(ls / 1.5))
		for i3 in range(nb):
			var za: float = lerpf(-ls * 0.5 + 0.3, ls * 0.5 - 0.3, float(i3) / nb)
			var zb: float = lerpf(-ls * 0.5 + 0.3, ls * 0.5 - 0.3, float(i3 + 1) / nb)
			RemonteeKit.poutre(sab, Vector3(x0, -0.36 - kappa * za * za * 0.5, za), Vector3(x0, -0.36 - kappa * zb * zb * 0.5, zb), 0.9, 0.40, m)
		# passerelle côté intérieur, garde-corps
		var xc: float = x0 - sx * 1.0
		RemonteeKit.boite_en(sab, Vector3(0.9, 0.04, ls - 0.6), Vector3(xc, -0.48, 0), "caillebotis")
		RemonteeKit.barre(sab, Vector3(xc - sx * 0.45, 0.55, -ls * 0.5 + 0.4), Vector3(xc - sx * 0.45, 0.55, ls * 0.5 - 0.4), 0.025, "galva", 6)
		var n_g: int = int(ls / 1.2)
		for k2 in range(n_g + 1):
			var z2: float = lerpf(-ls * 0.5 + 0.4, ls * 0.5 - 0.4, float(k2) / n_g)
			RemonteeKit.barre(sab, Vector3(xc - sx * 0.45, -0.46, z2), Vector3(xc - sx * 0.45, 0.55, z2), 0.02, "galva", 6)
		# galets du câble tracteur, sous les porteurs
		var ng2: int = maxi(3, int(ls / 4.0))
		for k4 in range(ng2):
			var sz2: float = lerpf(-ls * 0.35, ls * 0.35, float(k4) / maxf(ng2 - 1, 1))
			RemonteeKit.galet(sab, Vector3(x0, VehiculeRemontee.Y_TRACTEUR_3S - 0.03 - 0.21 - kappa * sz2 * sz2 * 0.5, sz2), 0.21)


const HT_CAISSON: float = 2.2
## Demi-largeur libre de tout acier au niveau des cabines : la file de
## cabines commence à voie/2 − 1,55 m (demi-largeur de la Zeta).
func _x_interieur() -> float:
	return voie * 0.5 - 1.55 - 0.45


## Une tour : fût en treillis du sol (y_sol) au caisson (dessous à y_c),
## caisson entre les files de cabines, consoles jusqu'aux sabots.
func _tour(z: float, y_sol: float, y_c: float, m: String, accolee: bool) -> void:
	var h: float = y_c - y_sol
	var xi: float = _x_interieur()
	var b1: float = minf(3.0, 2.0 * xi)
	var b0: float = clampf(h * 0.30, 6.0, 16.0) if not accolee else clampf(h * 0.22, 4.5, 9.0)
	var o: Vector3 = Vector3(0, y_sol, z)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.boite_en(self, Vector3(1.6, 0.9, 1.6), o + Vector3(sx * b0 * 0.5, -0.2, sz * b0 * 0.5 * (0.6 if accolee else 1.0)), "beton")
			RemonteeKit.poutre(self, o + Vector3(sx * b0 * 0.5, 0.2, sz * b0 * 0.5 * (0.6 if accolee else 1.0)), o + Vector3(sx * b1 * 0.5, h, sz * b1 * 0.5), 0.34, 0.34, m)
	var n_p: int = maxi(3, int(h / 4.5))
	for i in range(n_p):
		var ya: float = 0.2 + (h - 0.2) * float(i) / n_p
		var yb: float = 0.2 + (h - 0.2) * float(i + 1) / n_p
		for face in range(4):
			var a: float = PI * 0.5 * face
			var u: Vector3 = Vector3(cos(a), 0, sin(a))
			var v: Vector3 = Vector3(-sin(a), 0, cos(a))
			var kz: float = 0.6 if accolee else 1.0
			var ba: Vector2 = Vector2(lerpf(b0, b1, ya / h), lerpf(b0 * kz, b1, ya / h)) * 0.5
			var bb: Vector2 = Vector2(lerpf(b0, b1, yb / h), lerpf(b0 * kz, b1, yb / h)) * 0.5
			var p1: Vector3 = o + Vector3((u.x + v.x) * ba.x, ya, (u.z + v.z) * ba.y)
			var p2: Vector3 = o + Vector3((u.x - v.x) * ba.x, ya, (u.z - v.z) * ba.y)
			var p3: Vector3 = o + Vector3((u.x + v.x) * bb.x, yb, (u.z + v.z) * bb.y)
			var p4: Vector3 = o + Vector3((u.x - v.x) * bb.x, yb, (u.z - v.z) * bb.y)
			RemonteeKit.poutre(self, p1, p4, 0.14, 0.14, m)
			RemonteeKit.poutre(self, p2, p3, 0.14, 0.14, m)
			RemonteeKit.poutre(self, p3, p4, 0.16, 0.16, m)
	# caisson de tête en treillis, entre les files de cabines
	var y0: float = y_sol + h
	var y1: float = y0 + HT_CAISSON
	var zt: float = 1.2
	for sz in [-zt, zt]:
		for y in [y0, y1]:
			RemonteeKit.poutre(self, Vector3(-xi, y, z + sz), Vector3(xi, y, z + sz), 0.20, 0.20, m)
		var n_m: int = int(ceil(2.0 * xi / 1.5))
		for k in range(n_m + 1):
			var x: float = -xi + 2.0 * xi * float(k) / n_m
			RemonteeKit.poutre(self, Vector3(x, y0, z + sz), Vector3(x, y1, z + sz), 0.12, 0.12, m)
			if k < n_m:
				var x2: float = -xi + 2.0 * xi * float(k + 1) / n_m
				RemonteeKit.poutre(self, Vector3(x, y0 if k % 2 == 0 else y1, z + sz), Vector3(x2, y1 if k % 2 == 0 else y0, z + sz), 0.10, 0.10, m)
	for sx in [-1.0, 1.0]:
		for y in [y0, y1]:
			RemonteeKit.poutre(self, Vector3(sx * xi, y, z - zt), Vector3(sx * xi, y, z + zt), 0.16, 0.16, m)
		# console jusqu'au sabot, au-dessus du toit des cabines : membrure
		# haute au niveau du caisson, membrure basse remontée, treillis
		var x0: float = sx * voie * 0.5
		var xe: float = x0 + sx * 0.55
		var yb2: float = y1 - 0.9
		for sz in [-zt, zt]:
			RemonteeKit.poutre(self, Vector3(sx * xi, y1, z + sz), Vector3(xe, y1, z + sz), 0.18, 0.18, m)
			RemonteeKit.poutre(self, Vector3(sx * xi, yb2, z + sz), Vector3(xe, y1 - 0.3, z + sz), 0.14, 0.14, m)
			RemonteeKit.poutre(self, Vector3(sx * xi, y0 + 0.2, z + sz), Vector3(sx * xi, yb2, z + sz), 0.12, 0.12, m)
			var nk: int = 3
			for k3 in range(nk):
				var xa: float = lerpf(sx * xi, xe, float(k3) / nk)
				var xb: float = lerpf(sx * xi, xe, float(k3 + 1) / nk)
				RemonteeKit.poutre(self, Vector3(xa, lerpf(yb2, y1 - 0.3, float(k3) / nk), z + sz), Vector3(xb, y1, z + sz), 0.08, 0.08, m)
	# passerelle centrale sur le caisson
	RemonteeKit.boite_en(self, Vector3(2.0 * xi, 0.04, 2.0 * zt), Vector3(0, y1 + 0.13, z), "caillebotis")


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
		var pts: PackedVector3Array = PackedVector3Array()
		for i2 in range(13):
			var z: float = lerpf(-ls * 0.5, ls * 0.5, float(i2) / 12.0)
			pts.append(Vector3(x0, -PyloneRemontee.R_CABLE - 0.05 - kappa * z * z * 0.5, z))
		RemonteeKit.tube(sab, pts, 0.08, "acier_noir", 8)
		RemonteeKit.poutre(sab, Vector3(x0, -0.40, -ls * 0.45), Vector3(x0, -0.40, ls * 0.45), 0.30, 0.55, m)
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
