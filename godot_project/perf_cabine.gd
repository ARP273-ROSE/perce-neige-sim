# Banc de fluidité de la vue cabine (2026-09-30) : charge la vraie scène en
# conduite d'essai, relève à chaque image la durée, le temps de script, les
# appels de dessin et la régularité de la position rendue de la rame.
#   xvfb-run godot --path godot_project --rendering-driver opengl3 \
#     --resolution 960x540 -s perf_cabine.gd -- --drivetest --quality=low sortie.csv
extends SceneTree

var _main: Node = null
var _last: int = 0
var _rows: Array = []
var _t_trip: float = -1.0
var _out: String = "/tmp/perf_cabine.csv"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".csv"):
			_out = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_last = Time.get_ticks_usec()
	process_frame.connect(_tick)


func _tick() -> void:
	var now: int = Time.get_ticks_usec()
	var dt: float = float(now - _last) / 1e6
	_last = now
	var ph = _main.get("physics")
	if ph == null:
		return
	if ph.trip_started and _t_trip < 0.0:
		_t_trip = float(now) / 1e6
	_rows.append("%.6f,%.6f,%.5f,%.4f,%.3f,%d,%d,%d" % [
		float(now) / 1e6, dt, ph.s_render, ph.v,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if _t_trip > 0.0 and float(now) / 1e6 - _t_trip > 70.0:
		var f: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
		f.store_line("t,dt,s_render,v,process_ms,draw_calls,objects,primitives")
		for r in _rows:
			f.store_line(r)
		f.close()
		print("PERF écrit : ", _out, " (", _rows.size(), " images)")
		quit(0)
