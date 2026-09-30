# Banc de la salle des machines (2026-09-29) : construit le tunnel, les gares
# et la machinerie de la gare amont, vérifie les cotes clés et exporte les
# triangles de la fin de ligne (repère local : x, y, s) pour un rendu hors
# Godot (tests/rendu_salle_machines.py).
#   godot --headless --path godot_project -s bench_salle_machines_3d.gd [sortie.txt]
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D


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
	ok = _check("brin de sortie au niveau de la voie", absf(pente_s) < 0.01,
		"%.3f°, quitte la roue amont à y = %.3f (voie %.3f)" % [pente_s, p_ex.y, MachineRoomBuilder.Y_BRIN]) and ok
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
