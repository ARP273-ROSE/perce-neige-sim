# Banc de la salle des machines (2026-09-29) : construit le tunnel, les gares
# et la machinerie de la gare amont, vérifie les cotes clés et exporte les
# triangles de la fin de ligne (repère local : x, y, s) pour un rendu hors
# Godot (tests/rendu_salle_machines.py).
#   godot --headless --path godot_project -s bench_salle_machines_3d.gd [sortie.txt]
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D
var _track: TrackBuilder


func _initialize() -> void:
	var out_path: String = "/tmp/salle_machines.txt"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	_root = Node3D.new()
	get_root().add_child(_root)
	_tunnel = TunnelBuilder.new()
	_tunnel.ring_spacing = 3.0
	_tunnel.ring_segments = 20
	_tunnel.tunnel_radius = PNConstants.TUNNEL_RADIUS
	_root.add_child(_tunnel)
	# le tunnel ne calcule son tracé qu'à son _ready, qui n'a lieu qu'à la
	# première image : tout construire avant empilait la fin de ligne sur la
	# gare basse (transform_at renvoyait l'identité)
	process_frame.connect(_suite, CONNECT_ONE_SHOT)


func _suite() -> void:
	assert(_tunnel.path_points.size() > 0)
	var out_path: String = "/tmp/salle_machines.txt"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	_track = TrackBuilder.new()
	_root.add_child(_track)
	_track.build(_tunnel)
	var st: StationsBuilder = StationsBuilder.new()
	_root.add_child(st)
	st.build(_tunnel)
	var mr: MachineRoomBuilder = MachineRoomBuilder.new()
	_root.add_child(mr)
	mr.build(_tunnel)
	mr.update_rotation(3.0, 0.5)

	var xf: Transform3D = _tunnel.transform_at(PNConstants.LENGTH)
	var inv: Transform3D = xf.affine_inverse()
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	var n_tri: int = 0
	for holder in [mr, st]:
		var stack: Array = [holder]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
				if not (c is MeshInstance3D):
					continue
				var mi: MeshInstance3D = c
				var gxf: Transform3D = mi.transform
				var par: Node = mi.get_parent()
				while par != null and par != get_root():
					if par is Node3D:
						gxf = (par as Node3D).transform * gxf
					par = par.get_parent()
				var mesh: Mesh = mi.mesh
				if mesh == null:
					continue
				for si in range(mesh.get_surface_count()):
					var mat: Material = mesh.surface_get_material(si)
					var col: Color = Color(1, 0, 1)
					if mat is StandardMaterial3D:
						col = (mat as StandardMaterial3D).albedo_color
					elif mat is ShaderMaterial:
						col = Color(0.25, 0.25, 0.27)
					var arrays: Array = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var idx: PackedInt32Array = PackedInt32Array()
					if arrays[Mesh.ARRAY_INDEX] != null:
						idx = arrays[Mesh.ARRAY_INDEX]
					var tris: Array = []
					if idx.size() > 0:
						for k in range(0, idx.size(), 3):
							tris.append([idx[k], idx[k + 1], idx[k + 2]])
					else:
						for k in range(0, verts.size(), 3):
							tris.append([k, k + 1, k + 2])
					for t in tris:
						var loc: Array = []
						var keep: bool = true
						for vi in t:
							var p: Vector3 = inv * (gxf * verts[vi])
							# repère local : x, y, s = −z
							loc.append(Vector3(p.x, p.y, -p.z))
						for q in loc:
							if q.z < -12.0 or q.z > 16.0 or absf(q.x) > 7.0:
								keep = false
						if not keep:
							continue
						var line: String = "%s %.3f %.3f %.3f %.2f" % [mi.name, col.r, col.g, col.b, col.a]
						for q in loc:
							line += " %.4f %.4f %.4f" % [q.x, q.y, q.z]
						f.store_line(line)
						n_tri += 1
	f.close()
	print("triangles exportés : %d → %s" % [n_tri, out_path])

	# Cotes : sommet des joues de la roue aval entre les bras des butoirs, sous
	# la table de roulement, au-dessus de la dalle
	var ok: bool = true
	var top: float = MachineRoomBuilder.A_Y + MachineRoomBuilder.RF
	ok = _check("roue aval sous la table de roulement", top < StationsBuilder.RAIL_HEAD_Y,
		"sommet %.3f < %.3f" % [top, StationsBuilder.RAIL_HEAD_Y]) and ok
	ok = _check("roue aval dépasse de la dalle", top > MachineRoomBuilder.Y_HALL_FLOOR,
		"sommet %.3f > dalle %.3f" % [top, MachineRoomBuilder.Y_HALL_FLOOR]) and ok
	var h: float = MachineRoomBuilder.Y_HALL_FLOOR - MachineRoomBuilder.A_Y
	var demi: float = sqrt(MachineRoomBuilder.RF * MachineRoomBuilder.RF - h * h)
	var s0: float = MachineRoomBuilder.A_S - demi
	var s1: float = MachineRoomBuilder.A_S + demi
	# bras des butoirs : de LENGTH − 0,4 + 0,15 à LENGTH − 0,4 + 2,55 (stations_builder)
	ok = _check("roue aval entre les bras bleus", s0 >= -0.25 and s1 <= 2.15,
		"émerge de s = %.2f à %.2f (bras de −0,25 à 2,15)" % [s0, s1]) and ok
	var g: Dictionary = mr._geometry()
	# sommets des deux roues alignés sur la pente de la voie (Kevin, 30/09) :
	# le repère local suit la voie, donc même cote
	var dy: float = MachineRoomBuilder.B_Y - MachineRoomBuilder.A_Y
	var pente: float = rad_to_deg(atan2(dy, MachineRoomBuilder.B_S - MachineRoomBuilder.A_S))
	ok = _check("sommets des roues sur la pente de la voie", absf(pente) < 0.01,
		"pente A→B %.3f° dans le repère de la voie" % pente) and ok
	var p_ex: Vector2 = g["P_Bexit"]
	var p_k: Vector2 = g["P_Kin"]
	var pente_s: float = rad_to_deg(atan2(p_k.y - p_ex.y, p_ex.x - p_k.x))
	ok = _check("sortie par le haut de la roue amont", p_ex.y > MachineRoomBuilder.B_Y + MachineRoomBuilder.R - 0.01,
		"quitte la roue amont à y = %.3f, monte de %.2f° vers les galets" % [p_ex.y, pente_s]) and ok
	# roues alignées latéralement, gorges aux x des brins de la voie
	ok = _check("roues alignées latéralement", MachineRoomBuilder.A_GROOVES == MachineRoomBuilder.B_GROOVES
		and absf(float(MachineRoomBuilder.A_GROOVES[0]) - MachineRoomBuilder.LANE_L) < 1e-6
		and absf(float(MachineRoomBuilder.A_GROOVES[1]) - MachineRoomBuilder.LANE_R) < 1e-6,
		"gorges %s / %s" % [str(MachineRoomBuilder.A_GROOVES), str(MachineRoomBuilder.B_GROOVES)]) and ok
	# brin de la rame 2 au-dessus du sommet de la roue aval
	var jeu: float = MachineRoomBuilder.EXIT_Y - MachineRoomBuilder.R_CABLE \
		- (MachineRoomBuilder.A_Y + MachineRoomBuilder.RF)
	ok = _check("brin de sortie au-dessus de la roue aval", jeu > 0.02 and jeu < 0.10,
		"%.0f mm au-dessus des joues" % (jeu * 1000.0)) and ok
	var jeu_g: float = 99.0
	for s_g in MachineRoomBuilder.EXIT_ROLL_S:
		var yc: float = MachineRoomBuilder.EXIT_Y - MachineRoomBuilder.R_CABLE - MachineRoomBuilder.EXIT_ROLL_R
		for k in range(-9, 10):
			var ds: float = float(k) * MachineRoomBuilder.EXIT_ROLL_R / 10.0
			var s: float = float(s_g) + ds
			var y_g: float = yc - sqrt(MachineRoomBuilder.EXIT_ROLL_R ** 2 - ds * ds)
			var dA: float = s - MachineRoomBuilder.A_S
			var y_j: float = MachineRoomBuilder.A_Y + sqrt(maxf(MachineRoomBuilder.RF ** 2 - dA * dA, 0.0))
			jeu_g = minf(jeu_g, y_g - y_j)
	ok = _check("galets du brin de sortie au-dessus des joues", jeu_g > 0.015, "%.0f mm" % (jeu_g * 1000.0)) and ok
	# raccord : dernier galet du tunnel et hauteur du brin à la fin de voie
	var st_l: Array = _track.station_list()
	var s_last: float = float(st_l[-1].s) - PNConstants.LENGTH
	ok = _check("dernier galet du tunnel au bon endroit", absf(s_last - MachineRoomBuilder.S_LAST_TUNNEL_ROLLER) < 0.01,
		"%.3f m (constante %.3f)" % [s_last, MachineRoomBuilder.S_LAST_TUNNEL_ROLLER]) and ok
	var fin: Vector2 = _track.strand_local_at(1, PNConstants.LENGTH)
	ok = _check("brin de la rame 2 raccordé à la salle", absf(fin.y - MachineRoomBuilder.EXIT_Y_END) < 0.002
		and absf(fin.x - MachineRoomBuilder.LANE_R) < 0.002, "fin de voie x = %.3f, y = %.4f" % [fin.x, fin.y]) and ok
	# le câble de la salle défile avec les roues (il avait l'air figé)
	var ph0: float = float(mr._cable_mat.get_shader_parameter("cable_phase"))
	mr.update_rotation(2.0, 0.25)
	var ph1: float = float(mr._cable_mat.get_shader_parameter("cable_phase"))
	ok = _check("câble de la salle animé", absf(ph1 - ph0 - 0.5) < 1e-4,
		"phase %.3f → %.3f pour 2 m/s × 0,25 s" % [ph0, ph1]) and ok
	var hb: float = MachineRoomBuilder.Y_HALL_FLOOR - MachineRoomBuilder.B_Y
	var gr: float = MachineRoomBuilder.GUARD_R
	var e0: float = MachineRoomBuilder.B_S - sqrt(gr * gr - hb * hb)
	var e1: float = MachineRoomBuilder.B_S + sqrt(gr * gr - hb * hb)
	ok = _check("roue amont et carter dans la fosse", e0 > MachineRoomBuilder.PIT_S0 and e1 < MachineRoomBuilder.PIT_S1,
		"émergent de s = %.2f à %.2f (fosse jusqu'à %.2f, mur du fond %.2f)" % [e0, e1,
			MachineRoomBuilder.PIT_S1, MachineRoomBuilder.HALL_DEPTH]) and ok
	print("BENCH_SALLE_MACHINES " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)


func _check(label: String, cond: bool, detail: String) -> bool:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	return cond
