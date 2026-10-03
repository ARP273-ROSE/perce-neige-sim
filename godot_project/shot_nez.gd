# Capture de la face avant d'une rame (lettrage « TIGNES », phares, feux) :
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1200x900 -s shot_nez.gd -- sortie.png [arriere]
extends SceneTree

var _f: int = 0
var _out: String = "/tmp/nez.png"


func _initialize() -> void:
	var arriere: bool = false
	for a in OS.get_cmdline_user_args():
		if a == "arriere":
			arriere = true
		elif a.ends_with(".png"):
			_out = a
	var root: Node3D = Node3D.new()
	get_root().add_child(root)
	TrainBodyBuilder.build_train(root, 32.0, 2)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.30)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(20.0), 0.0)
	root.add_child(sun)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	var z_nez: float = 16.0 if arriere else -16.0
	var sens: float = 1.0 if arriere else -1.0
	cam.look_at_from_position(Vector3(0.0, 0.1, z_nez + sens * 5.5),
		Vector3(0.0, -0.35, z_nez), Vector3.UP)
	cam.current = true
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _f == 40:
		get_root().get_texture().get_image().save_png(_out)
		print("capture ", _out)
		quit(0)
