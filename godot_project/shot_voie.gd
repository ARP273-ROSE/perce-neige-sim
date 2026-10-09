# Vue plongeante sur la voie depuis le nez (comme les photos d'un utilisateur du
# 26/04/2026) : caméra cabine inclinée, poste de conduite masqué.
#   xvfb-run -a godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1376x1032 -s shot_voie.gd -- [s=1000] [incl=28] [noir] préfixe
# `noir` : éclairage du tunnel coupé (seuls les phares : reflets des numéros).
# (Ajouter --quality=high après « -- » : sinon la qualité adaptative —
#  PerfManager — baisse le rendu en rendu logiciel.)
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/voie"
var _s: float = 1000.0
var _incl: float = 28.0
var _noir: bool = false
var _magenta: bool = false   # fond magenta : révèle les trous


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a.begins_with("incl="):
			_incl = float(a.substr(5))
		elif a == "magenta":
			_magenta = true
		elif a == "noir":
			_noir = true
		elif not a.begins_with("--"):
			_prefix = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var ph = _main.get("physics")
	if ph == null:
		return
	if _f == 5:
		ph.s = _s
		ph.s_prev_step = _s
		ph.lights_head = _noir           # néons seuls, ou phares seuls tunnel éteint
		_main.set_tunnel_lights(not _noir)
		# caméra libre devant le nez, à hauteur de vitre, inclinée vers la voie
		var tun = _main.get("tunnel")
		var s_nez: float = _s + PNConstants.TRAIN_HALF + 0.6
		var xf: Transform3D = tun.transform_at(s_nez)
		var cam := Camera3D.new()
		cam.fov = 70.0
		get_root().add_child(cam)
		var pos: Vector3 = xf.origin + xf.basis.y * -0.2
		var cible: Vector3 = tun.transform_at(s_nez + 6.0).origin + tun.transform_at(s_nez + 6.0).basis.y * -1.6
		cam.look_at_from_position(pos, cible, xf.basis.y)
		cam.current = true
		if _magenta:
			var env: Environment = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(1, 0, 1)
			env.fog_enabled = false
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f > 6 and _main.get("track") != null:
		_main.get("track").set_retro(1.0)   # caméra au nez : comme en vue cabine
	if _f == 90:
		var img: Image = get_root().get_texture().get_image()
		var nom := "%s_s%d%s%s.png" % [_prefix, int(_s), "_noir" if _noir else "", "_magenta" if _magenta else ""]
		img.save_png(nom)
		print("VOIE ", nom)
		quit(0)
