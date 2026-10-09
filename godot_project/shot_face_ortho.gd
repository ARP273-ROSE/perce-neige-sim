## Face de la rame en vue ORTHOGRAPHIQUE (contrôle par superposition à la
## photo frontale, 09/10/2026) : 250 px par mètre, axe du tube au centre.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1200x900 -s shot_face_ortho.gd -- sortie.png
extends SceneTree

var _f: int = 0
var _out: String = "/tmp/face_ortho.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".png"):
			_out = a
	var root: Node3D = Node3D.new()
	get_root().add_child(root)
	TrainBodyBuilder.build_train(root, 32.0, 2)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.30)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(180.0), 0.0)
	root.add_child(sun)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.6                       # 900 px de haut → 250 px/m
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, TrainBodyBuilder.Y_CENTER, -30.0),
		Vector3(0.0, TrainBodyBuilder.Y_CENTER, 0.0), Vector3.UP)
	cam.current = true
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _f == 30:
		get_root().get_texture().get_image().save_png(_out)
		print("capture ", _out)
		quit(0)
