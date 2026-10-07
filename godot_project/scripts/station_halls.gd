class_name StationHalls
extends Node3D
## Bâtiments de gare aux portails du tunnel.
##
## - Val Claret (s = 0) : gare aval réaménagée en 2018 — salle d'attente,
##   cloison vitrée et portes coulissantes vers le quai, façade « DESTINATION
##   GLACIER », arches, auvent, escalier (GareAval, refonte du 07/10/2026 ;
##   remplace le hall béton générique et sa cage d'escalier vers la surface).
## - Grande Motte (s = LENGTH) : plus de hall depuis le 06/10/2026 — la gare
##   se termine sur le mur vitré de la salle des machines, qui donne sur le
##   glacier (MachineRoomBuilder).

var tunnel: TunnelBuilder = null
var gare_aval: GareAval = null


func build(t: TunnelBuilder) -> void:
	tunnel = t
	gare_aval = GareAval.new()
	gare_aval.name = "GareAval"
	add_child(gare_aval)
	gare_aval.construire(t)


## Portes coulissantes et panneau des départs de la gare aval.
func mettre_a_jour(dt: float, ph: TrainPhysics) -> void:
	if gare_aval != null:
		gare_aval.mettre_a_jour(dt, ph)
