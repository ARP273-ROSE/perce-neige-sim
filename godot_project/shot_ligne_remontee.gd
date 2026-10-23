## Démonstration d'une ligne complète (données réelles exportées par le
## dossier des remontées) : captures fixes après quelques secondes de
## marche (véhicules en mouvement, pinces, garde-corps).
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_ligne_remontee.gd -- cle préfixe
extends SceneTree

var _f: int = 0
var _pre: String = "/tmp/ligne"
var _cle: String = "tsd6_marmottes_express"
var _ligne: LigneRemontee
var _cam: Camera3D
var _vues: Array = []
var _i: int = 0


func _initialize() -> void:
	var args: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			args.append(a)
	if args.size() > 0:
		_cle = args[0]
	if args.size() > 1:
		_pre = args[1]
	var D: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/remontees/%s.json" % _cle))
	var racine: Node3D = Node3D.new()
	get_root().add_child(racine)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.45, 0.80)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.92)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.8
	env.environment = e
	racine.add_child(env)
	var soleil: DirectionalLight3D = DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-35, 60, 0)
	soleil.light_energy = 0.95
	soleil.shadow_enabled = true
	soleil.directional_shadow_max_distance = 300
	racine.add_child(soleil)
	_ligne = LigneRemontee.new()
	var prof: PackedVector2Array = PackedVector2Array()
	for p in D["profil"]:
		prof.append(Vector2(float(p[0]), float(p[1])))
	_ligne.profil = prof
	_ligne.pylones = D["pylones"]
	_ligne.voie = float(D["voie"])
	_ligne.vitesse = float(D["vitesse"])
	_ligne.espacement = float(D["espacement"])
	_ligne.famille = String(D["famille"])
	_ligne.sens_droite = bool(D["sens_droite"])
	if D.has("diametre_cable"):
		_ligne.diametre_cable = float(D["diametre_cable"])
	racine.add_child(_ligne)
	_ligne.construire()
	print("LIGNE %s : %d véhicules, boucle %.0f m" % [D["nom"], _ligne.nombre_vehicules(), _ligne.longueur_boucle])
	_terrain(racine, prof)
	_cam = Camera3D.new()
	_cam.fov = 55
	_cam.far = 4000
	racine.add_child(_cam)
	var L: float = _ligne.longueur_h()
	var p3: Dictionary = D["pylones"][mini(3, D["pylones"].size() - 1)]
	var d3: float = float(p3["d"])
	var y3: float = _ligne.terrain(d3)
	_vues = [
		["vue_generale", Vector3(-L * 0.55, _ligne.terrain(L * 0.5) + L * 0.25, -L * 0.45), Vector3(0, _ligne.terrain(L * 0.5), -L * 0.5)],
		["gare_aval", Vector3(-14, 9, 8), Vector3(0, 4, 8)],
		["gare_aval_quai", Vector3(9, 2.0, -3), Vector3(0, 3.5, 12)],
		["portillons", Vector3(9.0, 4.5, 40.0), Vector3(-1.0, 1.0, 22.0)],
		["poulie", Vector3(-4.5, 3.0, 17.0), Vector3(0, 4.2, 25.0)],
		["pneus", Vector3(5.5, 3.6, 5.0), Vector3(3.0, 4.4, 9.0)],
		["nez_gare", Vector3(-10.0, 4.0, -9.0), Vector3(0, 4.5, 0.0)],
		["pylone", Vector3(-12, y3 + 10, -d3 + 14), Vector3(0, y3 + 12, -d3)],
		["en_ligne", Vector3(10, _ligne.y_cable(d3 + 40) - 2, -d3 - 40), Vector3(3, _ligne.y_cable(d3 + 10) - 2, -d3 - 10)],
		["gare_amont", Vector3(-16, _ligne.terrain(L) + 10, -L + 10), Vector3(0, _ligne.terrain(L) + 4, -L - 14)],
	]
	# batteries des nez : vues de côté, à hauteur du câble
	var ha: float = _ligne._h_nez[0]
	var hb: float = _ligne._h_nez[1]
	var xb: float = _ligne.voie * 0.5
	_vues.append(["deviation", Vector3(xb + 0.6, _ligne.H_CABLE_GARE + 2.2, 3.4), Vector3(xb - 0.3, _ligne.H_CABLE_GARE, 3.2)])
	_vues.append(["deviation_large", Vector3(xb - 1.0, _ligne.H_CABLE_GARE + 9.0, 12.0), Vector3(xb - 0.6, _ligne.H_CABLE_GARE, 12.0)])
	_vues.append(["batterie_aval", Vector3(-xb - 7.0, _ligne.y_cable(ha) + 0.8, -ha), Vector3(-xb, _ligne.y_cable(ha), -ha)])
	_vues.append(["batterie_aval_bis", Vector3(xb + 7.0, _ligne.y_cable(ha) + 0.8, -ha), Vector3(xb, _ligne.y_cable(ha), -ha)])
	_vues.append(["batterie_amont", Vector3(-xb - 7.0, _ligne.y_cable(L - hb) + 0.8, -L + hb), Vector3(-xb, _ligne.y_cable(L - hb), -L + hb)])
	process_frame.connect(_tick)


## Terrain sous la ligne : bande de 160 m de large suivant le profil.
func _terrain(racine: Node3D, prof: PackedVector2Array) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(prof.size() - 1):
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for q in [[-80.0, a], [80.0, a], [80.0, b], [-80.0, a], [80.0, b], [-80.0, b]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q[0], (q[1] as Vector2).y - 0.05, -(q[1] as Vector2).x))
	st.generate_normals()
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.95, 0.98)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	racine.add_child(mi)
	# plateformes autour des gares (pas de trou entre le terrain et la dalle)
	var sol: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(160, 60)
	pm.material = m
	sol.mesh = pm
	sol.position = Vector3(0, prof[0].y - 0.06, 25)
	racine.add_child(sol)


func _tick() -> void:
	_f += 1
	if _f < 120:
		return                    # 2 s de marche : véhicules en route
	if _i >= _vues.size():
		quit(0)
		return
	var v: Array = _vues[_i]
	if _f % 8 == 0:
		_cam.position = v[1]
		_cam.look_at(v[2], Vector3.UP)
	elif _f % 8 == 7:
		var f: String = "%s_%s.png" % [_pre, v[0]]
		get_root().get_texture().get_image().save_png(f)
		print("SHOT ", f)
		_i += 1
