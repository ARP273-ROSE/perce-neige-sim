# Empreinte des maillages de six lignes construites (MeshMerge : pylônes, gares, véhicules, câbles…) : une somme
# SHA-256 par maillage (chemin dans la ligne, sommets, normales, UV, couleurs, index, matériaux) et une somme globale.
# Prouve que la fusion en C++ (OutilsMaillage.parcourir / collecter / retirer) donne les mêmes maillages que le
# GDScript : empreinte avec et sans --sans-cpp (ne coupe que le C++ de MeshMerge), comparaison ligne à ligne.
# Lignes : véhicules exclus (fusionnés par étapes après la construction, selon le temps), transformations non
# comptées, noms automatiques des nœuds (@Node3D@1234) normalisés. Véhicules : à part, toutes familles, livrées et
# teintes, en bloc et par tranches, graine fixe, transformations comprises (comme _diag_empreinte_veh du 10/11).
#   godot --headless --path godot_project -s bench_empreinte_fusion.gd -- [sortie.txt] [--sans-cpp]
extends SceneTree

const LIGNES: Array = ["tsd6_bollin", "olympique", "tke_legettaz", "tph_fornet", "tcd10_solaise", "tkd_col_du_palet"]
var _main: Node
var _f: int = 0
var _etat: int = 0
var _k: int = 0
var _lg: Node = null
var _sortie: String = ""
var _lignes: Array = []
var _t0: int = 0
var _re_nom: RegEx = RegEx.create_from_string("@([A-Za-z0-9]+)@[0-9]+|_([A-Z][A-Za-z0-9]+)_[0-9]+")


func _initialize() -> void:
	_sortie = OS.get_temp_dir().path_join("empreinte_fusion.txt")
	for a in OS.get_cmdline_user_args():
		if a == "--sans-cpp":
			MeshMerge.cpp_desactive = true
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
				_etat = 2
		2:
			if _k >= LIGNES.size():
				_etat = 8
				_vehicules()
				return
			_lg = null
			for e in _main.remontees.lignes:
				if String(e[0].name) == LIGNES[_k]:
					_lg = e[0]
			if _lg == null:
				push_error("ligne absente : " + LIGNES[_k])
				_k += 1
				return
			_main.aller_a_remontee(_lg)
			_t0 = Time.get_ticks_msec()
			_etat = 3
		3:
			if _lg.pret:
				var avant: int = _lignes.size()
				_parcourir(_lg, _lg, String(_lg.name))
				print("  %s : %d maillages" % [_lg.name, _lignes.size() - avant])
				_k += 1
				_etat = 2
			elif Time.get_ticks_msec() - _t0 > 120000:
				push_error("ligne pas prête en 120 s : " + LIGNES[_k])
				_k += 1
				_etat = 2


func _fin() -> void:
	_etat = 9
	_lignes.sort()
	var tout: String = "\n".join(_lignes)
	var fa: FileAccess = FileAccess.open(_sortie, FileAccess.WRITE)
	fa.store_string(tout + "\n")
	fa.close()
	print("EMPREINTE_FUSION %d lignes, globale %s, fusion C++ %s → %s" % [_lignes.size(), _sha(tout.to_utf8_buffer()),
		"non" if MeshMerge.cpp_desactive or not ClassDB.class_exists("OutilsMaillage") else "oui", _sortie])
	FinBanc.quitter(self, _main, 0)


func _parcourir(n: Node, racine: Node, pre: String) -> void:
	if n is VehiculeRemontee:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = n
		lignes_ajouter("%s/%s %s %d %.1f" % [pre, racine.get_path_to(n), _sha_mesh(mi.mesh), mi.cast_shadow, mi.visibility_range_end])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		lignes_ajouter("%s/%s mm%d %s" % [pre, racine.get_path_to(n), mm.instance_count, _sha_mesh(mm.mesh) if mm.mesh != null else "-"])
	for c in n.get_children():
		_parcourir(c, racine, pre)


func lignes_ajouter(l: String) -> void:
	_lignes.append(_re_nom.sub(l, "#", true))


func _vehicules() -> void:
	var n: int = 0
	for fam in VehiculeRemontee.DESCRIPTIONS.keys():
		for liv in ["", "Val d'Isère", "Tignes"]:
			for tei in ["", "noire"]:
				for mode in ["bloc", "tranches"]:
					seed(1234)
					var v: VehiculeRemontee = VehiculeRemontee.new()
					v.famille = fam
					v.numero = 17
					v.livree = liv
					v.teinte = tei
					get_root().add_child(v)
					if mode == "bloc":
						v.construire()
					else:
						await v.construire_par_tranches(func() -> void: pass)
					var ctx: HashingContext = HashingContext.new()
					ctx.start(HashingContext.HASH_SHA256)
					_h_veh(v, ctx, "")
					_lignes.append("vehicule %s|%s|%s|%s %s" % [fam, liv, tei, mode, ctx.finish().hex_encode().substr(0, 16)])
					v.free()
					VehiculeRemontee.vider_modeles()
					n += 1
	print("  véhicules : %d" % n)
	_fin()


func _h_veh(n: Node, ctx: HashingContext, chemin: String) -> void:
	ctx.update(("%s|%s|" % [chemin, n.get_class()]).to_utf8_buffer())
	if n is Node3D:
		ctx.update(var_to_bytes((n as Node3D).transform))
		ctx.update(var_to_bytes((n as Node3D).visible))
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		ctx.update(var_to_bytes(mi.cast_shadow))
		ctx.update(var_to_bytes(mi.visibility_range_end))
		if mi.mesh != null:
			ctx.update(_sha_mesh(mi.mesh).to_utf8_buffer())
		if mi.material_override != null:
			ctx.update(var_to_bytes(mi.material_override.resource_name + str(mi.material_override.get("albedo_color"))))
	var i: int = 0
	for c in n.get_children():
		_h_veh(c, ctx, chemin + "/" + str(i))
		i += 1


func _sha_mesh(m: Mesh) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in range(m.get_surface_count()):
		for a in MeshMerge.tableaux(m, i):
			if a != null:
				var b: PackedByteArray = var_to_bytes(a)
				if b.size() > 0:
					ctx.update(b)
		var mat: Material = m.surface_get_material(i)
		var dm: String = "-"
		if mat is BaseMaterial3D:
			var b3: BaseMaterial3D = mat
			dm = "%s %s %s %f %f %d %d" % [b3.resource_name, b3.albedo_color, b3.albedo_texture.resource_path if b3.albedo_texture != null else "",
				b3.roughness, b3.metallic, b3.cull_mode, int(b3.vertex_color_use_as_albedo)]
		elif mat != null:
			dm = mat.get_class() + ":" + mat.resource_name
		ctx.update(("|mat:" + dm).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


func _sha(b: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)
