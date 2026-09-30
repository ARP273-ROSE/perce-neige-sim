# Banc de l'aiguillage Abt et du câble tendu (2026-09-30) : construit le
# tunnel et la voie, vérifie les jeux câble / rails / galets dans les deux
# aiguillages et exporte les triangles de l'aiguillage bas (repère local de
# la fourche : x, y, s) pour tests/rendu_aiguillage.py.
#   godot --headless --path godot_project -s bench_aiguillage_3d.gd [sortie.txt]
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D
var _ok: bool = true


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_tunnel = TunnelBuilder.new()
	_tunnel.ring_spacing = 3.0
	_tunnel.ring_segments = 20
	_tunnel.tunnel_radius = PNConstants.TUNNEL_RADIUS
	_root.add_child(_tunnel)
	# le tracé n'existe qu'après le _ready du tunnel (première image)
	process_frame.connect(_suite, CONNECT_ONE_SHOT)


func _suite() -> void:
	var out_path: String = "/tmp/aiguillage.txt"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	var tr: TrackBuilder = TrackBuilder.new()
	tr.keep_instance_xforms = true
	_root.add_child(tr)
	tr.build(_tunnel)
	var abt: Dictionary = tr.abt_info()
	var s0: float = PNConstants.PASSING_START
	var s1: float = PNConstants.PASSING_END
	var hg: float = tr.gauge_m * 0.5
	var rc: float = tr.cable_radius
	var foot: float = tr.rail_foot_width * 0.5
	var web: float = tr.rail_web_width * 0.5

	print("cœurs en X à %.2f / %.2f, %d tronçons" % [abt.frog[0], abt.frog[1], abt.pieces.size()])
	_check("cœur en X à 27,5 m", absf(abt.frog[0] - s0 - 27.45) < 0.1,
		"%.2f m" % (abt.frog[0] - s0))
	_check("6 tronçons de rail intérieur (langue, rail, langue × 2)", abt.pieces.size() == 6,
		"%d" % abt.pieces.size())
	for g in abt.gaps:
		for z in ["lo", "hi"]:
			var ov: float = absf(g["a_end_" + z] - g["b_start_" + z])
			print("  lacune rail %+d (%s) : croisement %.2f, fin de langue %.2f, reprise %.2f, chevauchement %.2f m"
				% [g.rail, z, g["sc_" + z], g["a_end_" + z], g["b_start_" + z], ov])
			_check("chevauchement des bouts ≥ 0,5 m", ov >= 0.5, "%.2f m" % ov)
			# les deux bouts courent parallèlement au câble, à ±8 cm
			var dev: float = 0.0
			var s_lo2: float = minf(g["b_start_" + z], g["a_end_" + z])
			var s_hi2: float = maxf(g["b_start_" + z], g["a_end_" + z])
			var sv: float = s_lo2
			while sv <= s_hi2:
				var cx2: float = tr.strand_local_at(g.cable, sv).x
				for r in tr.inner_rails_at(sv):
					if r[2].rail == g.rail:
						dev = maxf(dev, absf(absf(r[0] - cx2) - TrackBuilder.ABT_CHANNEL))
				sv += 0.05
			_check("bouts parallèles au câble à 8 cm", dev < 0.002, "écart %.4f m" % dev)
			var coude: float = rad_to_deg(atan(absf(
				tr._wheel_cable_gap(g.rail, g["sc_" + z] + 0.5) - tr._wheel_cable_gap(g.rail, g["sc_" + z] - 0.5))))
			print("    coudes à %.2f et %.2f m du croisement, angle %.2f°" % [
				absf(g["bend_a_" + z] - g["sc_" + z]), absf(g["bend_b_" + z] - g["sc_" + z]), coude])
			var ds: float = absf(g["sc_" + z] - (s0 if z == "lo" else s1))
			_check("lacune près de 17 m de la fourche", absf(ds - 17.0) < 1.5, "%.2f" % ds)

	# 1. Roue plate toujours portée, ornière du boudin libre, câble dégagé
	var tread: float = TrackBuilder.FLAT_TREAD_HALF - tr.rail_head_width * 0.5 + 0.003
	var unsupported: int = 0
	var flange_hits: int = 0
	var cable_hits: int = 0
	var worst_outer: float = 99.0
	for zone in [[s0 - 6.0, s0 + 45.0], [s1 - 45.0, s1 + 6.0]]:
		var s: float = zone[0]
		while s <= zone[1]:
			var d: float = absf(_tunnel.passing_loop_offset(s, 1.0))
			var rails: Array = tr.inner_rails_at(s)
			for ri in [-1, 1]:
				# roue plate de la rame de la voie ri, sur la ligne x_f ;
				# son rail extérieur côté plat = celui de l'autre voie
				var xf: float = tr.inner_rail_x(ri, s)
				var outer_flat: float = -float(ri) * (d + hg)
				var ok_sup: bool = absf(xf - outer_flat) <= tread
				for r in rails:
					if absf(r[0] - xf) <= tread:
						ok_sup = true
				if not ok_sup:
					unsupported += 1
				# boudin intérieur de la rame guidée par le rail extérieur ri
				var flange: float = float(ri) * (d + hg) - float(ri) * 0.06
				for r in rails:
					if absf(r[0] - flange) < tr.rail_head_width * 0.5 + 0.01 + 0.005:
						flange_hits += 1
			for cable_i in [-1, 1]:
				var cx: float = tr.strand_local_at(cable_i, s).x
				for xo in [-d - hg, d + hg]:
					worst_outer = minf(worst_outer, absf(cx - xo) - foot - rc)
				for r in rails:
					if absf(cx - r[0]) < rc + r[1] + 0.004:
						cable_hits += 1
			s += 0.05
	_check("roue plate toujours portée (langue, rail, lacune)", unsupported == 0,
		"%d points sans appui" % unsupported)
	_check("ornière du boudin libre", flange_hits == 0, "%d contacts" % flange_hits)
	_check("câble dégagé de tous les tronçons", cable_hits == 0, "%d contacts" % cable_hits)
	_check("câble loin des rails extérieurs", worst_outer > 0.05, "jeu mini %.3f m" % worst_outer)

	# 2. Supports de galets et galets de déviation contre les rails
	var stations: Array = tr.station_list()
	var clash: int = 0
	var n_sheave: int = 0
	for k in range(stations.size()):
		var st: Dictionary = stations[k]
		if not ((st.s > s0 - 6.0 and st.s < s0 + 45.0) or (st.s > s1 - 45.0 and st.s < s1 + 6.0)):
			continue
		var d2: float = absf(_tunnel.passing_loop_offset(st.s, 1.0))
		var rails2: Array = [[-d2 - hg, foot], [d2 + hg, foot]]
		for r in tr.inner_rails_at(st.s):
			rails2.append([r[0], r[1]])
		var spans: Array = []
		if st.paired:
			spans.append(Vector2(-tr.base_plate_width * 0.5, tr.base_plate_width * 0.5))
		else:
			for side_i in [-1, 1]:
				var xn: float = _tunnel.passing_loop_offset(st.s, float(side_i)) + side_i * tr.pulley_pair_offset
				spans.append(Vector2(xn - 0.10, xn + 0.10))
		if st.sheave:
			var xf: Transform3D = _tunnel.transform_at(st.s)
			for side_i in [-1, 1]:
				var pts: Array = tr.strand_vertices(side_i)
				var v: Dictionary = pts[k + 1]
				var pull: Vector3 = ((pts[k + 2].p - v.p) as Vector3).normalized() \
					- ((v.p - pts[k].p) as Vector3).normalized()
				var inside: float = signf(pull.dot(xf.basis.x))
				if inside == 0.0:
					inside = -float(side_i)
				var beta: float = deg_to_rad(tr.sheave_incline_deg)
				var cxs: float = v.x + inside * cos(beta) * (tr.sheave_radius + rc)
				var ext: float = tr.sheave_radius * cos(beta) + tr.sheave_thickness * 0.5 * sin(beta)
				spans.append(Vector2(cxs - ext, cxs + ext))
				var y_low: float = v.y - sin(beta) * (tr.sheave_radius + rc) - tr.sheave_radius * sin(beta)
				var beam_top: float = tr.floor_y_local + tr.slab_thickness - 0.01 + tr.cable_beam_height
				if y_low < beam_top:
					clash += 1
					print("  galet de déviation dans la longrine à s = %.1f" % st.s)
				n_sheave += 1
		for sp in spans:
			for r2 in rails2:
				if sp.x < r2[0] + r2[1] and sp.y > r2[0] - r2[1]:
					clash += 1
					print("  conflit à s = %.1f : [%.3f ; %.3f] contre rail %.3f" % [st.s, sp.x, sp.y, r2[0]])
	_check("galets et galets de déviation hors des rails", clash == 0, "%d conflits" % clash)
	_check("galets de déviation posés", n_sheave == 12, "%d" % n_sheave)

	# 3. Câble tendu en courbe : écart de la corde à l'arc (courbe 1)
	var dev_max: float = 0.0
	var tilt_max: float = 0.0
	for side_i in [-1, 1]:
		var pts2: Array = tr.strand_vertices(side_i)
		for j in range(1, pts2.size() - 1):
			tilt_max = maxf(tilt_max, absf(pts2[j].tilt))
			var a: Dictionary = pts2[j]
			var b: Dictionary = pts2[j + 1]
			if a.s < 1297.0 or b.s > 1541.0:
				continue
			var sm: float = 0.5 * (a.s + b.s)
			var xf2: Transform3D = _tunnel.transform_at(sm)
			var mid: Vector3 = (a.p as Vector3).lerp(b.p, 0.5)
			var x_mid: float = (mid - xf2.origin).dot(xf2.basis.x)
			var x_ends: float = 0.5 * (a.x + b.x)
			dev_max = maxf(dev_max, absf(x_mid - x_ends))
	print("  courbe 1 : la corde passe à %.1f cm de l'arc à mi-portée ; inclinaison maxi %.1f°"
		% [dev_max * 100.0, rad_to_deg(tilt_max)])
	_check("corde droite visible en courbe (3 à 7 cm)", dev_max > 0.03 and dev_max < 0.07,
		"%.3f m" % dev_max)

	_export(tr, out_path, s0)
	print("BENCH_AIGUILLAGE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _in_window(abt: Dictionary, rail_i: int, s: float, part: String) -> bool:
	for w in abt.windows:
		if w.rail != rail_i:
			continue
		var iv: Vector2 = w[part]
		if s >= iv.x and s <= iv.y:
			return true
	return false


func _export(tr: TrackBuilder, out_path: String, s_ref: float) -> void:
	var xf: Transform3D = _tunnel.transform_at(s_ref)
	var inv: Transform3D = xf.affine_inverse()
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	var n_tri: int = 0
	var stack: Array = [tr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			var items: Array = []   # [mesh, transform global, material override]
			if c is MeshInstance3D:
				items.append([(c as MeshInstance3D).mesh, (c as Node3D).transform])
			elif c is MultiMeshInstance3D:
				var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null:
					print("  multimesh vide : ", c.name)
					continue
				var xfs: Array = c.get_meta("xforms", [])
				for t in xfs:
					var o: Vector3 = inv * t.origin
					if -o.z < -20.0 or -o.z > 60.0 or absf(o.x) > 4.0:
						continue
					items.append([mm.mesh, t])
			for it in items:
				var mesh: Mesh = it[0]
				if mesh == null:
					continue
				var gxf: Transform3D = it[1]
				for si in range(mesh.get_surface_count()):
					var mat: Material = mesh.surface_get_material(si)
					if mat == null and mesh is PrimitiveMesh:
						mat = (mesh as PrimitiveMesh).material
					var col: Color = Color(1, 0, 1)
					if mat is StandardMaterial3D:
						col = (mat as StandardMaterial3D).albedo_color
					elif mat is ShaderMaterial:
						col = Color(0.30, 0.30, 0.34)
					var arrays: Array = mesh.surface_get_arrays(si)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var idx: PackedInt32Array = PackedInt32Array()
					if arrays[Mesh.ARRAY_INDEX] != null:
						idx = arrays[Mesh.ARRAY_INDEX]
					var count: int = idx.size() if idx.size() > 0 else verts.size()
					for k in range(0, count, 3):
						var loc: Array = []
						var keep: bool = true
						for m in range(3):
							var vi: int = idx[k + m] if idx.size() > 0 else k + m
							var p: Vector3 = inv * (gxf * verts[vi])
							var q: Vector3 = Vector3(p.x, p.y, -p.z)
							if q.z < -20.0 or q.z > 60.0 or absf(q.x) > 4.0:
								keep = false
							loc.append(q)
						if not keep:
							continue
						var line: String = "%s %.3f %.3f %.3f %.2f" % [c.name, col.r, col.g, col.b, col.a]
						for q in loc:
							line += " %.4f %.4f %.4f" % [q.x, q.y, q.z]
						f.store_line(line)
						n_tri += 1
	f.close()
	print("triangles exportés : %d → %s" % [n_tri, out_path])


func _check(label: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", label, detail])
	if not cond:
		_ok = false
