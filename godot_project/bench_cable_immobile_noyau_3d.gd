## Banc du câble immobile, avec le module C++ (PC) : voir bench_cable_immobile_3d.gd.
extends "res://bench_cable_immobile_3d.gd"


func _initialize() -> void:
	OS.set_environment("NOYAU", "1")
	super._initialize()
