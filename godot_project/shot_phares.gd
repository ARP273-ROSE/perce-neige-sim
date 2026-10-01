# Vue cabine dans le tunnel, phares allumés, pour régler le halo des phares
# (retour du 01/10 : « reflet aveuglant »).
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 1376x1032 -s shot_phares.gd -- --mode=normal [s=600] préfixe
extends SceneTree

var _main: Node = null
var _f: int = 0
var _prefix: String = "/tmp/phares"
var _s: float = 600.0
var _sans_glow: bool = false
var _params: PackedStringArray = []   # p=énergie,angle,att_cône,att_distance[,inclinaison °]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("s="):
			_s = float(a.substr(2))
		elif a == "sans-glow":
			_sans_glow = true
		elif a.begins_with("p="):
			_params = a.substr(2).split(",")
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
		ph.lights_head = true
		var cab = _main.get("cabin")
		if _sans_glow:
			(_main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
		if _params.size() >= 4:
			cab.head_energy = float(_params[0])
			cab.headlight_front.spot_angle = float(_params[1])
			cab.headlight_front.spot_angle_attenuation = float(_params[2])
			cab.headlight_front.spot_attenuation = float(_params[3])
			if _params.size() == 5:
				cab.headlight_front.rotation.x = deg_to_rad(float(_params[4]))
	if _f == 6 and _main.get("hud") != null:
		_main.get("hud").visible = false
	if _f == 90:
		get_root().get_texture().get_image().save_png("%s_s%d%s.png" % [_prefix, int(_s),
			(("_" + "_".join(_params)) if _params.size() >= 4 else "") + ("_sansglow" if _sans_glow else "")])
		print("capture s=", _s)
		quit(0)
