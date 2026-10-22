## Vitrine des modèles de remontées (pylônes, véhicules) : captures pour
## contrôle visuel.
##   xvfb-run godot --path godot_project --rendering-driver opengl3 \
##     --resolution 1400x900 -s shot_vitrine_remontees.gd -- préfixe [vue]
extends SceneTree

var _f: int = 0
var _pre: String = "/tmp/vitrine"
var _vues: Array = []
var _cam: Camera3D
var _i: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_pre = a
	var racine: Node3D = Node3D.new()
	get_root().add_child(racine)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.45, 0.80)
	sm.sky_horizon_color = Color(0.75, 0.82, 0.92)
	sm.ground_horizon_color = Color(0.85, 0.88, 0.92)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_exposure = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	racine.add_child(env)
	var sol: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var ms: StandardMaterial3D = StandardMaterial3D.new()
	ms.albedo_color = Color(0.93, 0.95, 0.98)
	ms.roughness = 0.9
	pm.material = ms
	sol.mesh = pm
	racine.add_child(sol)
	var soleil: DirectionalLight3D = DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-38, 35, 0)
	soleil.light_energy = 0.95
	soleil.shadow_enabled = true
	racine.add_child(soleil)
	# pylônes : compositions réelles du domaine
	var compos: Array = [
		["P1 Tufs 16C/16C", [[16, "C"]], [[16, "C"]], 9.0],
		["P2 Tufs 10S/8S", [[10, "S"]], [[8, "S"]], 11.0],
		["P4 Tufs 4SC/4SC", [[4, "SC"]], [[4, "SC"]], 13.0],
		["Col des Vés 2S+12C+2S", [[2, "S"], [12, "C"], [2, "S"]], [[16, "C"]], 10.0],
	]
	for i in range(compos.size()):
		var p: PyloneRemontee = PyloneRemontee.new()
		p.numero = i + 1
		p.hauteur = compos[i][3]
		p.compo_montee = compos[i][1]
		p.compo_descente = compos[i][2]
		p.position = Vector3(i * 14.0, 0, 0)
		racine.add_child(p)
		p.construire()
		# un bout de câble pour lire la tête de ligne
		for montee in [true, false]:
			var a: Vector3 = p.position + p.point_cable(montee)
			RemonteeKit.barre(racine, a + Vector3(0, 0, 9), a + Vector3(0, 0, -9), PyloneRemontee.R_CABLE, "cable", 8)
	# véhicules : une rangée par famille, pendus à un câble à 5 m du sol
	var fams: Array = ["siege_doppelmayr_e98_6", "siege_poma_ocr6", "siege_garaventa_sk6", "siege_bartholet_6",
		"siege_poma_arceau4", "siege_doppelmayr_e98_4_bulle", "siege_fixe_4", "cabine_omega4", "cabine_diamond", "cabine_symphony"]
	var y_c: float = 5.2
	RemonteeKit.barre(racine, Vector3(-4, y_c, 60), Vector3(4 + fams.size() * 5.0, y_c, 60), PyloneRemontee.R_CABLE, "cable", 8)
	for i in range(fams.size()):
		var v: VehiculeRemontee = VehiculeRemontee.new()
		v.famille = fams[i]
		# tournés de 90° : on les voit de face (le câble court le long de X)
		v.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(i * 5.0, y_c, 60))
		racine.add_child(v)
		v.construire()
		if fams[i].begins_with("cabine"):
			v.portes(1.0 if i % 2 == 0 else 0.0)
		elif fams[i].ends_with("_bulle"):
			v.bulle(0.0)
			v.garde_corps(0.0)
		elif i == 1:
			v.garde_corps(0.0)
	# gros plan pinces : fermée et ouverte
	for k in range(2):
		var v2: VehiculeRemontee = VehiculeRemontee.new()
		v2.famille = "siege_bartholet_6"
		v2.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-20 + k * 3.0, y_c, 80))
		racine.add_child(v2)
		v2.construire()
		v2.ouvrir_pince(float(k))
		RemonteeKit.barre(racine, Vector3(-22 + k * 3.0, y_c, 80), Vector3(-18 + k * 3.0, y_c, 80), PyloneRemontee.R_CABLE, "cable", 8)
	# téléski : pylône à potence, perches à enrouleur (déroulée / rentrée), T, assiette
	var tk: PyloneRemontee = PyloneRemontee.new()
	tk.style = "teleski"
	tk.hauteur = 6.5
	tk.voie = 2.6
	tk.compo_montee = [[4, "S"]]
	tk.compo_descente = [[2, "S"]]
	tk.position = Vector3(0, 0, 110)
	racine.add_child(tk)
	tk.construire()
	for montee in [true, false]:
		var a2: Vector3 = tk.position + Vector3(tk.voie * 0.5 * (1.0 if montee else -1.0), tk.hauteur + 0.35 + 0.165, 0)
		RemonteeKit.barre(racine, a2 + Vector3(0, 0, 12), a2 + Vector3(0, 0, -12), 0.009, "cable", 6)
	var pk: Array = [["perche_enrouleur", 1.3, 5.0, 1.0], ["perche_tbar", 1.3, -5.0, 1.0], ["perche_enrouleur", -1.3, 5.0, 0.0],
		["perche_debrayable", -1.3, -5.0, 0.0]]
	for q in pk:
		var vv: VehiculeRemontee = VehiculeRemontee.new()
		vv.famille = q[0]
		vv.position = Vector3(q[1], tk.hauteur + 0.35 + 0.165, 110 + q[2])
		racine.add_child(vv)
		vv.construire()
		vv.deroule(q[3])
	# 3S et téléphérique : pylône en treillis, cabines sous les porteurs
	var tr: PyloneTreillis = PyloneTreillis.new()
	tr.hauteur = 22.0
	tr.position = Vector3(40, 0, 140)
	racine.add_child(tr)
	tr.construire()
	for sx in [-1.0, 1.0]:
		for k in range(2):
			var xp: float = 40 + sx * 5.0 + (k - 0.5) * 0.6
			RemonteeKit.barre(racine, Vector3(xp, tr.hauteur_porteurs(), 110), Vector3(xp, tr.hauteur_porteurs(), 170), 0.028, "cable", 6)
	var c3: VehiculeRemontee = VehiculeRemontee.new()
	c3.famille = "cabine_3s"
	c3.position = Vector3(45, tr.hauteur_porteurs() - 0.1, 128)
	racine.add_child(c3)
	c3.construire()
	var ct: VehiculeRemontee = VehiculeRemontee.new()
	ct.famille = "cabine_tph"
	ct.position = Vector3(65, 8.5, 140)
	racine.add_child(ct)
	ct.construire()
	ct.portes(1.0)
	_cam = Camera3D.new()
	_cam.fov = 50
	racine.add_child(_cam)
	_vues = [
		["ensemble", Vector3(21, 9, 30), Vector3(21, 7, 0)],
		["tete_compression", Vector3(-6.5, 11.5, 5.5), Vector3(-3.05, 9.9, 0)],
		["tete_support", Vector3(19.0, 12.6, 6.0), Vector3(17.05, 11.9, 0)],
		["tete_sc", Vector3(32.5, 14.4, 5.0), Vector3(31.05, 13.9, 0)],
		["col_des_ves", Vector3(38.0, 11.8, 7.0), Vector3(45.05, 10.9, 0)],
		["pied", Vector3(4, 3, 8), Vector3(0, 2.5, 0)],
		["e98_6_face", Vector3(-5.5, 3.6, 63.5), Vector3(0, 3.3, 60)],
		["ocr6_releve", Vector3(-0.5, 3.6, 63.5), Vector3(5, 3.6, 60)],
		["garaventa_sk6", Vector3(4.5, 3.6, 63.5), Vector3(10, 3.3, 60)],
		["bartholet_6", Vector3(9.5, 3.6, 63.5), Vector3(15, 3.3, 60)],
		["arceau4", Vector3(14.5, 3.6, 63.0), Vector3(20, 3.3, 60)],
		["bulle_ouverte", Vector3(19.5, 3.8, 63.0), Vector3(25, 3.5, 60)],
		["fixe4", Vector3(24.5, 3.6, 63.0), Vector3(30, 3.3, 60)],
		["omega_portes", Vector3(31.0, 3.2, 64.0), Vector3(35, 2.8, 60)],
		["diamond", Vector3(36.0, 3.2, 64.0), Vector3(40, 2.8, 60)],
		["symphony_portes", Vector3(41.0, 3.2, 64.0), Vector3(45, 2.8, 60)],
		["pince_fermee", Vector3(-20.9, 5.75, 81.15), Vector3(-20.0, 5.25, 80)],
		["pince_ouverte", Vector3(-17.9, 5.75, 81.15), Vector3(-17.0, 5.25, 80)],
		["siege_profil", Vector3(2.0, 3.6, 66.0), Vector3(0, 3.6, 60)],
		["teleski", Vector3(7.5, 4.0, 121), Vector3(0, 4.2, 110)],
		["treillis_3s", Vector3(22, 14, 112), Vector3(42, 17, 135)],
		["cabine_3s", Vector3(51, 19.5, 120), Vector3(45, 19, 128)],
		["cabine_tph", Vector3(73, 6.0, 131), Vector3(65, 5.5, 140)],
	]
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _i >= _vues.size():
		quit(0)
		return
	var v: Array = _vues[_i]
	if _f % 6 == 1:
		_cam.position = v[1]
		_cam.look_at(v[2], Vector3.UP)
	elif _f % 6 == 0:
		var f: String = "%s_%s.png" % [_pre, v[0]]
		get_root().get_texture().get_image().save_png(f)
		print("SHOT ", f)
		_i += 1
