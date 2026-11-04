class_name VehiculesLod
extends RefCounted
## Véhicules vus de loin : maillages très allégés, cuits une fois pour toutes
## (data/remontees/vehicules_lod.cuit). Une seule surface et un seul matériau par type et par niveau :
## un MultiMesh par ligne, donc un appel de dessin, au lieu de milliers de triangles par véhicule.

const FICHIER: String = "res://data/remontees/vehicules_lod.cuit"
const DES_L1: float = 60.0              # m : en deçà, le véhicule complet
const DES_L2: float = 150.0

static var _types: Dictionary = {}
static var _lu: bool = false
static var _maillages: Dictionary = {}
static var _materiau: StandardMaterial3D = null


static func _lire() -> void:
	_lu = true
	var f: FileAccess = FileAccess.open(FICHIER, FileAccess.READ)
	if f == null:
		return
	var n: int = f.get_32()
	var z: PackedByteArray = f.get_buffer(f.get_length() - 4)
	f.close()
	var d: Variant = bytes_to_var(z.decompress(n, FileAccess.COMPRESSION_ZSTD))
	if d is Dictionary and int((d as Dictionary).get("version", 0)) == 2:
		_types = d["types"]


static func materiau() -> StandardMaterial3D:
	if _materiau == null:
		_materiau = StandardMaterial3D.new()
		_materiau.resource_name = "vehicules_lod"
		_materiau.vertex_color_use_as_albedo = true
		_materiau.vertex_color_is_srgb = true
		# (lumière déjà dans les couleurs, comme les lignes cuites)
		_materiau.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materiau.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _materiau


## Maillage du niveau `niveau` ("L1", "L2") pour ce type de véhicule, ou null s'il n'a pas été cuit.
static func maillage(cle: String, niveau: String, miroir: bool) -> ArrayMesh:
	if not _lu:
		_lire()
	if not _types.has(cle):
		return null
	var k: String = "%s|%s|%s" % [cle, niveau, str(miroir)]
	if _maillages.has(k):
		return _maillages[k]
	var s: Dictionary = _types[cle][niveau]
	var v: PackedVector3Array = s["v"]
	var ix: PackedInt32Array = s["i"]
	if miroir:
		v = v.duplicate()
		ix = ix.duplicate()
		for i in range(v.size()):
			v[i].x = -v[i].x
		for t in range(0, ix.size() - 2, 3):
			var q: int = ix[t + 1]
			ix[t + 1] = ix[t + 2]
			ix[t + 2] = q
	var ta: Array = []
	ta.resize(Mesh.ARRAY_MAX)
	ta[Mesh.ARRAY_VERTEX] = v
	ta[Mesh.ARRAY_COLOR] = s["c"]
	ta[Mesh.ARRAY_INDEX] = ix
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	m.surface_set_material(0, materiau())
	_maillages[k] = m
	return m


# --- pylônes vus de loin -------------------------------------------------------------------
const FICHIER_PYLONES: String = "res://data/remontees/pylones_lod_25.web.cuit"
const PYLONE_DES: float = 150.0         # m : au-delà, le pylône allégé (portée posée sur le vrai)
static var _pylones: Dictionary = {}
static var _pylones_lu: bool = false


static func _lire_pylones() -> void:
	_pylones_lu = true
	var f: FileAccess = FileAccess.open(FICHIER_PYLONES, FileAccess.READ)
	if f == null:
		return
	var n: int = f.get_32()
	var z: PackedByteArray = f.get_buffer(f.get_length() - 4)
	f.close()
	var d: Variant = bytes_to_var(z.decompress(n, FileAccess.COMPRESSION_ZSTD))
	if d is Dictionary and int((d as Dictionary).get("version", 0)) == 2:
		_pylones = d["lignes"]


## Maillage allégé du pylône `nom` de la ligne `ligne`, ou null.
static func pylone(ligne: String, nom: String) -> ArrayMesh:
	if not _pylones_lu:
		_lire_pylones()
	if not _pylones.has(ligne):
		return null
	for e in _pylones[ligne]:
		if String(e["nom"]) == nom and e.get("L2") != null:
			var s: Dictionary = e["L2"]
			var ta: Array = []
			ta.resize(Mesh.ARRAY_MAX)
			ta[Mesh.ARRAY_VERTEX] = s["v"]
			ta[Mesh.ARRAY_COLOR] = s["c"]
			ta[Mesh.ARRAY_INDEX] = s["i"]
			var m: ArrayMesh = ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
			m.surface_set_material(0, materiau())
			return m
	return null
