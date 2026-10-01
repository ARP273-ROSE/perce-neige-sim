# Captures d'une rupture du câble (2026-10-01) : vue cabine en montée, puis
# vue extérieure orbitale tournée vers la brèche.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1376x1032 -s shot_rupture.gd -- --mode=normal préfixe
extends SceneTree

const DT: float = 1.0 / 60.0
var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/rupture"
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_prefix = a
	seed(7)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _shot(nom: String) -> void:
	get_root().get_texture().get_image().save_png("%s_%s.png" % [_prefix, nom])
	print("capture ", nom)


func _tick() -> void:
	_f += 1
	var ph = _main.get("physics")
	if ph == null:
		return
	if _f == 5:
		_main.set_process(false)
		if _main.get("hud") != null:
			_main.get("hud").visible = false
		ph.s = 900.0
		ph.s_prev_step = 900.0
		ph.direction = 1
		ph.v = 8.0
		ph.trip_started = true
		ph.doors_open = false
		ph.maint_brake = false
		for i in range(10):
			_main._process(DT)
		_main.fault_manager.trigger("cable_rupture")
		for i in range(90):
			_main._process(DT)
	if _f == 40:
		_shot("cabine")
		var cab = _main.get("cabin")
		cab.set_view(Cabin.ViewMode.EXTERIOR)
		# caméra orbitale : en avant de la rame, vers la brèche
		cab.orbit_yaw = 2.6
		cab.orbit_pitch = 0.18
		cab.orbit_dist = 30.0
	if _f > 5 and _f < 180:
		_main._process(0.0)
	if _f == 80:
		_shot("exterieur")
		# gros plan sur la brèche : caméra libre posée sur la voie, 3 m en
		# aval, à hauteur de genou
		var track = _main.get("track")
		var r: Dictionary = track.cable_rupture_state()
		var s_b: float = float(r.s_b)
		var tun = _main.get("tunnel")
		_main.get("cabin").set_view(Cabin.ViewMode.FPV)   # parois opaques
		var cam: Camera3D = Camera3D.new()
		cam.fov = 60.0
		cam.near = 0.02
		get_root().add_child(cam)
		var xf: Transform3D = tun.transform_at(s_b - 2.5)
		cam.global_position = xf.origin + xf.basis.y * -0.3 + xf.basis.x * 0.25
		cam.look_at(track.strand_point(-1, s_b + 0.8), xf.basis.y)
		cam.make_current()
		_cam = cam
	if _f == 110:
		_shot("breche")
		# câble détendu entre deux galets, près de la rame
		var track = _main.get("track")
		var tun = _main.get("tunnel")
		var ph2 = _main.get("physics")
		var s_v: float = ph2.s + 45.0
		var xf: Transform3D = tun.transform_at(s_v - 3.0)
		_cam.global_position = xf.origin + xf.basis.y * -0.3 + xf.basis.x * 0.6
		_cam.look_at(track.strand_point(-1, s_v + 5.0), xf.basis.y)
	if _f == 140:
		_shot("detendu")
		# salle des machines vue de côté : brins croisés pendants, tours
		# retombés sous les roues
		var cab = _main.get("cabin")
		cab.set_view(Cabin.ViewMode.MACHINES)
		var mc = cab.camera_machines
		mc.yaw = -1.57
		mc.pitch = 0.12
		mc.dist = 14.0
		mc.pan_y = -2.6
	if _f == 170:
		_shot("salle")
		quit(0)
