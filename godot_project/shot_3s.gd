## Studio du 3S (cabine Zeta, chariot, pylône en treillis) et du téléphérique.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_3s.gd -- préfixe
extends SceneTree
var _f: int = 0
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0
var _pre: String = "/tmp/s3"


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
	pm.size = Vector2(200, 200)
	var mn: StandardMaterial3D = StandardMaterial3D.new()
	mn.albedo_color = Color(0.93, 0.95, 0.98)
	pm.material = mn
	neige.mesh = pm
	racine.add_child(neige)
	# un pylône, ses quatre porteurs (lisses) et le tracteur (à torons)
	var tr: PyloneTreillis = PyloneTreillis.new()
	tr.hauteur = 22.0
	racine.add_child(tr)
	tr.construire()
	var yp: float = tr.hauteur_porteurs()
	var tracteur: ShaderMaterial = RemonteeKit.materiau_cable_tracteur(52.5)
	for sx in [-1.0, 1.0]:
		for k in [-0.5, 0.5]:
			var xp: float = sx * tr.voie * 0.5 + k * VehiculeRemontee.E_PORTEURS_3S
			RemonteeKit.barre(racine, Vector3(xp, yp, 60), Vector3(xp, yp, -60), 0.0285, "cable", 8)
		var xt: float = sx * tr.voie * 0.5
		RemonteeKit.tube(racine, PackedVector3Array([Vector3(xt, yp + VehiculeRemontee.Y_TRACTEUR_3S, 60), Vector3(xt, yp + VehiculeRemontee.Y_TRACTEUR_3S, -60)]), 0.026, "cable", 8, tracteur)
	for k in range(2):
		var c3: VehiculeRemontee = VehiculeRemontee.new()
		c3.famille = "cabine_3s"
		c3.numero = 12 + k
		c3.position = Vector3(tr.voie * 0.5, yp, 9.0 + k * 9.0)
		racine.add_child(c3)
		c3.construire()
		if k == 1:
			c3.portes(1.0)
	_cam = Camera3D.new()
	_cam.fov = 45
	racine.add_child(_cam)
	_cam.make_current()
	var xc: float = tr.voie * 0.5
	_vues = [
		["chauffe", Vector3(xc + 9, yp - 2.0, 3.0), Vector3(xc, yp - 2.5, 9)],
		["cabine_34", Vector3(xc + 7.5, yp - 1.5, 3.0), Vector3(xc, yp - 2.6, 9)],
		["cabine_face", Vector3(xc, yp - 2.2, 1.0), Vector3(xc, yp - 2.4, 9)],
		["portes", Vector3(xc + 6.5, yp - 2.8, 18.0), Vector3(xc, yp - 3.0, 18)],
		["chariot", Vector3(xc + 2.0, yp + 0.8, 7.2), Vector3(xc, yp, 9)],
		["chariot_dessous", Vector3(xc + 1.2, yp - 1.6, 7.5), Vector3(xc, yp, 9)],
		["pylone", Vector3(24, 14, -26), Vector3(0, 16, 0)],
		["tete_pylone", Vector3(10, yp + 3.0, -9), Vector3(0, yp, 0)],
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
