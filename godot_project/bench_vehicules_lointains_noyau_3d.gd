## Banc des véhicules lointains AVEC le module C++ (PC) : sièges de Bollin restés dessinés et figés sur une ligne au
## repos (set_lointains les remontrait après la mise au repos, retour d'essai PC du 20/11/2026). Même banc que
## bench_vehicules_lointains_3d.gd, chemin du noyau.
extends "res://bench_vehicules_lointains_3d.gd"


func _initialize() -> void:
	OS.set_environment("NOYAU", "1")
	super._initialize()
