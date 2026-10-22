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
	# chevêtre et sabots
	RemonteeKit.boite_en(self, Vector3(voie + 2.4, 0.9, 1.6), Vector3(0, h + 0.45, 0), m)
	for sx in [-1.0, 1.0]:
		var x0: float = sx * voie * 0.5
		for k in range(porteurs_par_voie):
			var x: float = x0 + (float(k) - (porteurs_par_voie - 1) * 0.5) * ecart_porteurs
			# sabot : longue selle cintrée (la gorge où repose le porteur)
			var pts: PackedVector3Array = RemonteeKit.arc(Vector3(x, h + 0.9 - 8.0, 0), Vector3.UP, Vector3.FORWARD, 8.0, -0.22, 0.22, 10)
			RemonteeKit.tube(self, pts, 0.10, "acier", 8)
			RemonteeKit.boite_en(self, Vector3(0.16, 0.5, 3.4), Vector3(x, h + 0.65, 0), "acier_noir")
		# poulies du câble tracteur, sous les sabots
		for sz in [-0.8, 0.8]:
			RemonteeKit.galet(self, Vector3(x0, h - 0.1, sz), 0.30, 0.10)
	# passerelle de visite en tête + garde-corps
	RemonteeKit.boite_en(self, Vector3(voie + 2.4, 0.04, 2.6), Vector3(0, h + 0.02, 0), "caillebotis")
	for sz in [-1.3, 1.3]:
		RemonteeKit.barre(self, Vector3(-voie * 0.5 - 1.2, h + 1.1, sz), Vector3(voie * 0.5 + 1.2, h + 1.1, sz), 0.025, "galva", 6)


## Hauteur (locale) d'appui des porteurs.
func hauteur_porteurs() -> float:
	return hauteur + 0.95
