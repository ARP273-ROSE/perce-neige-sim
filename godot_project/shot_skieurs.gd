# Studio des skieurs (06/10/2026) : chaque attitude et coiffe en rang,
# avec leur matériel, pour régler les maillages hors du jeu.
#   xvfb-run -a godot --path godot_project --rendering-driver vulkan \
#     --resolution 1600x900 -s shot_skieurs.gd -- [vue=face|dos|cote|proche|loin] préfixe
extends SceneTree

var _f: int = 0
var _prefix: String = "/tmp/skieurs"
var _vue: String = "face"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vue="):
			_vue = a.substr(4)
		elif not a.begins_with("--"):
			_prefix = a
	var racine := Node3D.new()
	get_root().add_child(racine)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.60, 0.68)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	racine.add_child(env)
	var soleil := DirectionalLight3D.new()
	soleil.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(150.0), 0.0)
	soleil.light_energy = 1.4
	soleil.shadow_enabled = true
	racine.add_child(soleil)
	var sol := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.35, 0.36, 0.38)
	pm.material = smat
	sol.mesh = pm
	racine.add_child(sol)

	var mat: ShaderMaterial = SkieurMesh.materiau()
	var x: float = -4.2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gear_skis: Array = []
	var gear_bat: Array = []
	var gear_surf: Array = []
	var sacs: Dictionary = {}
	for pose in ["skis", "libre", "telephone", "enfant", "assis"]:
		for coiffe in ["casque", "bonnet"]:
			var mesh: ArrayMesh = SkieurMesh.passager(pose, coiffe, mat)
			var xf := Transform3D(Basis.IDENTITY, Vector3(x, 0.0, 0.0))
			_mm(racine, mesh, [xf], rng)
			if coiffe == "casque" and pose != "enfant":
				if not sacs.has(pose):
					sacs[pose] = []
				(sacs[pose] as Array).append(xf)
			if pose == "skis":
				if coiffe == "casque":
					gear_skis.append(xf * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SKIS))
					gear_bat.append(xf * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_BATONS))
				else:
					gear_surf.append(xf * Transform3D(Basis.IDENTITY, SkieurMesh.ANCRE_SURF))
			if pose == "assis":
				var siege := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.45, 0.04, 0.40)
				siege.mesh = bm
				siege.position = Vector3(x, 0.50, 0.0)
				racine.add_child(siege)
			x += 0.95
	for pose in sacs:
		_mm(racine, SkieurMesh.sac(pose, mat), sacs[pose], rng)
	_mm(racine, SkieurMesh.skis(mat), gear_skis, rng)
	_mm(racine, SkieurMesh.batons(mat), gear_bat, rng)
	_mm(racine, SkieurMesh.surf(mat), gear_surf, rng)

	var cam := Camera3D.new()
	cam.fov = 40.0
	racine.add_child(cam)
	match _vue:
		"dos":
			cam.look_at_from_position(Vector3(0.0, 1.5, 7.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
		"cote":
			cam.look_at_from_position(Vector3(-9.0, 1.4, -1.5), Vector3(-2.0, 0.9, 0.0), Vector3.UP)
		"proche":
			cam.fov = 30.0
			cam.look_at_from_position(Vector3(-3.4, 1.55, -2.2), Vector3(-3.95, 1.1, 0.0), Vector3.UP)
		"tete":
			cam.fov = 18.0
			cam.look_at_from_position(Vector3(-3.6, 1.66, -1.5), Vector3(-3.95, 1.58, 0.0), Vector3.UP)
		"loin":
			cam.look_at_from_position(Vector3(0.0, 2.5, -24.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
		_:
			cam.look_at_from_position(Vector3(0.0, 1.5, -7.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	cam.current = true
	process_frame.connect(_tick)


func _mm(racine: Node3D, mesh: Mesh, xfs: Array, rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	racine.add_child(mi)


func _tick() -> void:
	_f += 1
	if _f == 30:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_%s.png" % [_prefix, _vue]
		img.save_png(nom)
		print("SKIEURS ", nom)
		quit(0)
