## Studio des sièges : trois-quarts avant, arrière, de près.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_sieges.gd -- préfixe
extends SceneTree
var _f: int = 0
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0
var _pre: String = "/tmp/sieges"


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
	var fams: Array = ["siege_bartholet_6", "siege_bartholet_6", "siege_poma_ocr6", "siege_doppelmayr_e98_4_bulle"]
	var y_c: float = 5.5
	RemonteeKit.barre(racine, Vector3(-6, y_c, 0), Vector3(22, y_c, 0), PyloneRemontee.R_CABLE, "cable", 8)
	for i in range(fams.size()):
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = fams[i]
		v.position = Vector3(i * 5.0, y_c, 0)
		v.rotation.y = PI * 0.5
		racine.add_child(v)
		v.construire()
		v.garde_corps(0.0 if i % 2 == 0 else 1.0)
		v.bulle(0.0)
	_cam = Camera3D.new()
	_cam.fov = 45
	racine.add_child(_cam)
	_cam.make_current()
	_vues = [
		["chauffe", Vector3(-4.5, 3.0, 6.0), Vector3(0, 2.4, 0)],
		["bartholet", Vector3(-3.0, 2.8, 4.5), Vector3(0, 2.3, 0)],
		["bartholet_pres", Vector3(-1.2, 2.6, 2.4), Vector3(0, 2.1, 0)],
		["dos", Vector3(-2.5, 3.2, -4.0), Vector3(0, 2.6, 0)],
		["bmf_face", Vector3(-4.2, 2.9, 1.2), Vector3(0, 2.7, 0)],
		["bmf_dessous", Vector3(-3.0, 1.2, 2.2), Vector3(0, 3.0, 0)],
		["bmf_pince", Vector3(-1.0, 5.9, 1.2), Vector3(0, 5.6, 0.3)],
		["bmf_baisse_dessous", Vector3(3.6, 1.6, 2.6), Vector3(5.0, 3.0, 0)],
		["bmf_baisse_face", Vector3(1.2, 2.9, 0.8), Vector3(5.0, 2.6, 0)],
		["bmf_profil_releve", Vector3(0.0, 3.0, -6.0), Vector3(0.0, 3.0, 0)],
		["bmf_profil_baisse", Vector3(5.0, 3.0, -6.0), Vector3(5.0, 3.0, 0)],
		["rangee", Vector3(-5.0, 3.5, 9.0), Vector3(7.5, 2.4, 0)],
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
