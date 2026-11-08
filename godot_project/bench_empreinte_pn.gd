# Empreinte du tunnel et de la voie du Perce-Neige (TunnelBuilder + TrackBuilder) : une somme SHA-256 par maillage
# (sommets, normales, UV, couleurs, index, matériaux) et par MultiMesh (tampon des instances), plus une somme
# globale. Sert à prouver que la généralisation des constructeurs (Funival, 08/11/2026) ne change pas un sommet du
# Perce-Neige : empreinte avant, empreinte après, comparaison ligne à ligne.
#   godot --headless --path godot_project -s bench_empreinte_pn.gd -- [sortie.txt]
extends SceneTree

var _tunnel: TunnelBuilder
var _root: Node3D


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_tunnel = TunnelBuilder.new()
	_tunnel.ring_spacing = 3.0
	_tunnel.ring_segments = 20
	_tunnel.tunnel_radius = PNConstants.TUNNEL_RADIUS
	_root.add_child(_tunnel)
	process_frame.connect(_suite, CONNECT_ONE_SHOT)


func _suite() -> void:
	var out_path: String = OS.get_temp_dir().path_join("empreinte_pn.txt")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	var tr: TrackBuilder = TrackBuilder.new()
	tr.keep_instance_xforms = true
	_root.add_child(tr)
	tr.build(_tunnel)
	var lignes: Array = []
	_parcourir(_root, lignes)
	lignes.sort()
	# sondes du tracé (transform_at, décalage d'évitement, points du câble)
	var sondes: PackedFloat32Array = PackedFloat32Array()
	var s: float = 0.0
	while s <= PNConstants.LENGTH:
		var xf: Transform3D = _tunnel.transform_at(s)
		sondes.append_array([xf.origin.x, xf.origin.y, xf.origin.z, xf.basis.x.x, xf.basis.y.y,
			_tunnel.passing_loop_offset(s, 1.0)])
		for side_i in [-1, 1]:
			var q: Vector3 = tr.strand_point(side_i, s)
			sondes.append_array([q.x, q.y, q.z])
		s += 7.0
	lignes.append("sondes " + _sha(sondes.to_byte_array()))
	var tout: String = "\n".join(lignes)
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(tout + "\n")
	f.close()
	print("EMPREINTE %d lignes, globale %s → %s" % [lignes.size(), _sha(tout.to_utf8_buffer()), out_path])
	quit(0)


func _parcourir(n: Node, lignes: Array) -> void:
	var chemin: String = str(_root.get_path_to(n))
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = n
		lignes.append("%s %s %s" % [chemin, _sha(var_to_bytes(mi.transform)), _sha_mesh(mi.mesh)])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		lignes.append("%s %s mm%d %s %s" % [chemin, _sha(var_to_bytes((n as Node3D).transform)), mm.instance_count,
			_sha(mm.buffer.to_byte_array()), _sha_mesh(mm.mesh) if mm.mesh != null else "-"])
	elif n is Node3D:
		lignes.append("%s %s" % [chemin, _sha(var_to_bytes((n as Node3D).transform))])
	for c in n.get_children():
		_parcourir(c, lignes)


func _sha_mesh(m: Mesh) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in range(m.get_surface_count()):
		var arr: Array = m.surface_get_arrays(i)
		for a in arr:
			if a != null:
				var b: PackedByteArray = var_to_bytes(a)
				if b.size() > 0:
					ctx.update(b)
		var mat: Material = m.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat
			ctx.update(var_to_bytes([sm.albedo_color, sm.roughness, sm.metallic, sm.emission_enabled, sm.emission]))
	return ctx.finish().hex_encode().substr(0, 16)


func _sha(b: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if b.size() > 0:
		ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)
