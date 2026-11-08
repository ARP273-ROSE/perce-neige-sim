# Empreinte du tunnel et de la voie du Funival (TunnelPN + VoiePN, TunnelBuilder et TrackBuilder sur son tracé) : une
# somme SHA-256 par maillage et par MultiMesh, comme bench_empreinte_pn.gd. Sert à prouver que le module C++
# (OutilsVoie, ExtrusionVoie) et son repli GDScript construisent la même voie, sommet pour sommet.
#   godot --headless --path godot_project -s bench_empreinte_funival.gd -- [sortie.txt] [--sans-cpp]
extends SceneTree

var _main: Node = null
var _f: int = 0
var _etat: int = 0
var _lg: Funival = null
var _sortie: String = ""
var _racine: Node = null


func _initialize() -> void:
	_sortie = OS.get_temp_dir().path_join("empreinte_funival.txt")
	for a in OS.get_cmdline_user_args():
		if a == "--sans-cpp":
			ExtrusionVoie.cpp_desactive = true
		elif not a.begins_with("--"):
			_sortie = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	match _etat:
		0:
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.skieur != null and _main.skieur.actif:
				for e in _main.remontees.lignes:
					if String(e[0].name) == "funival":
						_lg = e[0]
				_main.aller_a_remontee(_lg)
				_etat = 2
		2:
			if _lg.pret:
				var lignes: Array = []
				for n in [_lg.tunnel_pn, _lg.voie_pn]:
					_racine = n
					_parcourir(n, lignes, String(n.name))
				lignes.sort()
				var tout: String = "\n".join(lignes)
				var fa: FileAccess = FileAccess.open(_sortie, FileAccess.WRITE)
				fa.store_string(tout + "\n")
				fa.close()
				print("EMPREINTE_FUNIVAL %d lignes, globale %s, module %s → %s" % [lignes.size(), _sha(tout.to_utf8_buffer()),
					"non" if ExtrusionVoie.cpp_desactive or not ClassDB.class_exists("OutilsVoie") else "oui", _sortie])
				_etat = 3
				FinBanc.quitter(self, _main, 0)


func _parcourir(n: Node, lignes: Array, pre: String) -> void:
	var chemin: String = pre + "/" + str(_racine.get_path_to(n))
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		lignes.append("%s %s %s" % [chemin, _sha(var_to_bytes((n as Node3D).transform)), _sha_mesh((n as MeshInstance3D).mesh)])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		lignes.append("%s %s mm%d %s %s" % [chemin, _sha(var_to_bytes((n as Node3D).transform)), mm.instance_count,
			_sha(mm.buffer.to_byte_array()), _sha_mesh(mm.mesh) if mm.mesh != null else "-"])
	for c in n.get_children():
		_parcourir(c, lignes, pre)


func _sha_mesh(m: Mesh) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in range(m.get_surface_count()):
		for a in m.surface_get_arrays(i):
			if a != null:
				var b: PackedByteArray = var_to_bytes(a)
				if b.size() > 0:
					ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)


func _sha(b: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if b.size() > 0:
		ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)
