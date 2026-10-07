class_name StationHalls
extends Node3D
## Bâtiments de gare aux portails du tunnel.
##
## - Val Claret (s = 0) : gare aval réaménagée en 2018 — salle d'attente,
##   cloison vitrée et portes coulissantes vers le quai, façade « DESTINATION
##   GLACIER », arches, auvent, escalier (GareAval, refonte du 07/10/2026 ;
##   remplace le hall béton générique et sa cage d'escalier vers la surface).
## - Grande Motte (s = LENGTH) : intérieur (quais, hall, mur de tête, salle
##   des machines) = MachineRoomBuilder ; extérieur (hall, façade de tête,
##   terrasse, restaurant, annexes, gare du téléphérique) = GareAmont
##   (07/10/2026).

var tunnel: TunnelBuilder = null
var gare_aval: GareAval = null
var gare_amont: GareAmont = null


func build(t: TunnelBuilder) -> void:
	tunnel = t
	gare_aval = GareAval.new()
	gare_aval.name = "GareAval"
	add_child(gare_aval)
	gare_aval.construire(t)


## Extérieur de la gare amont (après la salle des machines, dont il prend
## le repère).
func build_amont(mr: MachineRoomBuilder) -> void:
	gare_amont = GareAmont.new()
	gare_amont.name = "GareAmont"
	add_child(gare_amont)
	gare_amont.construire(tunnel, mr)


## Portes coulissantes et panneau des départs de la gare aval.
func mettre_a_jour(dt: float, ph: TrainPhysics) -> void:
	if gare_aval != null:
		gare_aval.mettre_a_jour(dt, ph)
