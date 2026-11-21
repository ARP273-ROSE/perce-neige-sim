## Banc des galets du 3S, avec le module C++ (PC) : voir bench_galets_3s_3d.gd.
extends "res://bench_galets_3s_3d.gd"


func _initialize() -> void:
	OS.set_environment("NOYAU", "1")
	super._initialize()
