## Studio des cabines (Omega IV, Diamond, Symphony) : trois-quarts, côté
## portes ouvertes, intérieur.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_cabines.gd -- préfixe
extends SceneTree
var _f: int = 0
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0
var _pre: String = "/tmp/cabines"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	var racine: Node3D = Node3D.new()
	get_root().add_child(racine)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	var ciel: Sky = Sky.new()
	ciel.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = ciel
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	racine.add_child(env)
	var sol: DirectionalLight3D = DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-38, 35, 0)
	sol.shadow_enabled = true
	racine.add_child(sol)
	var neige: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var mn: StandardMaterial3D = StandardMaterial3D.new()
	mn.albedo_color = Color(0.93, 0.95, 0.98)
	pm.material = mn
	neige.mesh = pm
	racine.add_child(neige)
	var fams: Array = ["cabine_omega4", "cabine_diamond", "cabine_symphony"]
	var y_c: float = 5.0
	RemonteeKit.barre(racine, Vector3(-6, y_c, 0), Vector3(12, y_c, 0), PyloneRemontee.R_CABLE, "cable", 8)
	for i in range(fams.size()):
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = fams[i]
		v.position = Vector3(i * 4.5, y_c, 0)
		v.rotation.y = PI * 0.5            # câble selon X du monde
		racine.add_child(v)
		v.construire()
		if i == 0:
			v.portes(1.0)
	_cam = Camera3D.new()
	_cam.fov = 45
	racine.add_child(_cam)
	_cam.make_current()
	_vues = [
		["chauffe", Vector3(-4.5, 4.2, 5.5), Vector3(1.5, 3.0, 0)],
		["trois_quarts", Vector3(-4.5, 4.2, 5.5), Vector3(1.5, 3.0, 0)],
		["omega_portes", Vector3(0.6, 3.2, 4.2), Vector3(0, 2.9, 0)],
		["omega_dos", Vector3(-2.5, 3.6, -4.0), Vector3(0, 3.0, 0)],
		["interieur", Vector3(0.0, 3.0, 1.6), Vector3(0, 2.3, -0.5)],
		["dessus", Vector3(2.0, 9.0, 4.0), Vector3(4.5, 4.0, 0)],
	]
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _f < 20:
		return
	if _i >= _vues.size():
		quit(0)
		return
	var v: Array = _vues[_i]
	if _f % 6 == 0:
		_cam.global_position = v[1]
		_cam.look_at(v[2], Vector3.UP)
	elif _f % 6 == 5:
		get_root().get_texture().get_image().save_png("%s_%s.png" % [_pre, v[0]])
		_i += 1
