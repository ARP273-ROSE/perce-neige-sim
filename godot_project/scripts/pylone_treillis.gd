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


func construire() -> void:
	for c in get_children():
		c.queue_free()
	var h: float = hauteur
	var b0: float = clampf(h * 0.22, 4.0, 12.0)     # côté à la base
	var b1: float = 2.2                             # côté en tête
	var m: String = "peinture_gris"
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.boite_en(self, Vector3(1.4, 0.8, 1.4), Vector3(sx * b0 * 0.5, -0.2, sz * b0 * 0.5), "beton")
			RemonteeKit.poutre(self, Vector3(sx * b0 * 0.5, 0.2, sz * b0 * 0.5), Vector3(sx * b1 * 0.5, h, sz * b1 * 0.5), 0.22, 0.22, m)
	var n_p: int = maxi(3, int(h / 5.0))
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
			RemonteeKit.poutre(self, p3, p4, 0.10, 0.10, m)
	# tête (photos des pylônes du 3S de l'Olympique) : poutre-caisson en
	# treillis sur toute la largeur, à chaque voie un long sabot en
	# porte-à-faux dans l'axe de la ligne, avec sa passerelle et son
	# garde-corps ; les porteurs reposent dans les gorges des sabots, le
	# tracteur roule sur des galets en dessous
	var xe: float = voie * 0.5 + 1.3
	var ht: float = 2.2                 # hauteur du caisson
	var zt: float = 1.0                 # demi-profondeur du caisson
	var y0: float = h
	var y1: float = h + ht
	for sz in [-zt, zt]:
		for y in [y0, y1]:
			RemonteeKit.poutre(self, Vector3(-xe, y, sz), Vector3(xe, y, sz), 0.16, 0.16, m)
		var n_m: int = int(ceil(2.0 * xe / 1.6))
		for k in range(n_m + 1):
			var x: float = -xe + 2.0 * xe * float(k) / n_m
			RemonteeKit.poutre(self, Vector3(x, y0, sz), Vector3(x, y1, sz), 0.10, 0.10, m)
			if k < n_m:
				var x2: float = -xe + 2.0 * xe * float(k + 1) / n_m
				RemonteeKit.poutre(self, Vector3(x, y0 if k % 2 == 0 else y1, sz), Vector3(x2, y1 if k % 2 == 0 else y0, sz), 0.08, 0.08, m)
	for sx in [-1.0, 1.0]:
		for y in [y0, y1]:
			RemonteeKit.poutre(self, Vector3(sx * xe, y, -zt), Vector3(sx * xe, y, zt), 0.14, 0.14, m)
		# goussets entre le fût et le caisson
		RemonteeKit.poutre(self, Vector3(sx * b1 * 0.5, h - 2.5, 0), Vector3(sx * (b1 * 0.5 + 2.2), y0, 0), 0.14, 0.14, m)
	var yp: float = hauteur_porteurs()
	# sabots, passerelles et galets : inclinés sur la pente des porteurs,
	# cintrés selon leur déviation (le porteur se couche dans la gorge)
	var sab: Node3D = Node3D.new()
	sab.name = "Sabots"
	sab.position = Vector3(0, yp, 0)
	sab.rotation.x = pente
	add_child(sab)
	var kappa: float = maxf(deviation, 0.004) / maxf(l_sabot, 1.0)
	for sx in [-1.0, 1.0]:
		var x0: float = sx * voie * 0.5
		var ls: float = l_sabot
		# longeron du sabot, en porte-à-faux, extrémités relevées en arc
		for k in range(porteurs_par_voie):
			var x: float = x0 + (float(k) - (porteurs_par_voie - 1) * 0.5) * ecart_porteurs
			var pts: PackedVector3Array = PackedVector3Array()
			var n_s: int = 16
			for i2 in range(n_s + 1):
				var z: float = lerpf(-ls * 0.5, ls * 0.5, float(i2) / n_s)
				pts.append(Vector3(x, -PyloneRemontee.R_CABLE - 0.04 - kappa * z * z * 0.5, z))
			RemonteeKit.tube(sab, pts, 0.07, "acier_noir", 8)
			# âme du sabot jusqu'au caisson
			RemonteeKit.poutre(sab, Vector3(x, -0.30, -ls * 0.42), Vector3(x, -0.30, ls * 0.42), 0.10, 0.36, m)
		# poutre de sabot sous les deux porteurs, et bracons jusqu'au caisson
		RemonteeKit.poutre(sab, Vector3(x0, y1 - yp, -ls * 0.5 + 0.4), Vector3(x0, y1 - yp, ls * 0.5 - 0.4), 0.9, 0.24, m)
		for sz in [-1.0, 1.0]:
			RemonteeKit.poutre(sab, Vector3(x0, y1 - yp - 0.1, sz * (ls * 0.5 - 0.6)), Vector3(x0 - sx * 0.6, y0 - yp, sz * zt), 0.12, 0.12, m)
		# passerelle côté intérieur, garde-corps
		var xc: float = x0 - sx * 1.0
		RemonteeKit.boite_en(sab, Vector3(0.9, 0.04, ls - 0.6), Vector3(xc, y1 - yp + 0.13, 0), "caillebotis")
		for zz in [-1.0, 1.0]:
			pass
		RemonteeKit.barre(sab, Vector3(xc - sx * 0.45, y1 - yp + 1.15, -ls * 0.5 + 0.4), Vector3(xc - sx * 0.45, y1 - yp + 1.15, ls * 0.5 - 0.4), 0.025, "galva", 6)
		var n_g: int = int(ls / 1.2)
		for k2 in range(n_g + 1):
			var z2: float = lerpf(-ls * 0.5 + 0.4, ls * 0.5 - 0.4, float(k2) / n_g)
			RemonteeKit.barre(sab, Vector3(xc - sx * 0.45, y1 - yp + 0.15, z2), Vector3(xc - sx * 0.45, y1 - yp + 1.15, z2), 0.02, "galva", 6)
		# galets du câble tracteur, sous les porteurs
		for sz2 in [-ls * 0.3, 0.0, ls * 0.3]:
			RemonteeKit.galet(sab, Vector3(x0, VehiculeRemontee.Y_TRACTEUR_3S - 0.03 - 0.21 - kappa * sz2 * sz2 * 0.5, sz2), 0.21)
	# passerelle centrale sur le caisson
	RemonteeKit.boite_en(self, Vector3(2.0 * xe, 0.04, 2.0 * zt), Vector3(0, y1 + 0.13, 0), "caillebotis")


## Hauteur (locale) d'appui des porteurs.
func hauteur_porteurs() -> float:
	return hauteur + 2.2 + 0.24 + 0.55
