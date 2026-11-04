## Cuisson de l'orthophoto du pack haute définition : les tuiles JPEG de tools_relief_hd.py en un
## fichier de couches BC7 prêtes pour un tableau de textures (ReliefAnneaux).
##   godot --headless --path godot_project -s cuisson_ortho_hd.gd -- --ortho=DOSSIER/ortho --sortie=DOSSIER/ortho.pnhd
## Format, petit-boutiste : 'PNOH', u32 version, u32 colonnes, u32 lignes, u32 nœuds par tuile (2000),
## u32 texels par couche (2048), u32 marge (24), u32 format d'Image. Puis, ligne par ligne, 16 octets
## par couche : u64 position dans le corps, u32 taille compressée, u32 taille brute. Corps juste après
## l'index, couches compressées zstd. Le texel (marge, marge) est le nœud (ti, tj).
extends SceneTree

const TUILE: int = 2000
const TAILLE: int = 2048
const MARGE: int = 24
const NI: int = 17251
const NJ: int = 21076
var _cache: Dictionary = {}
var _dossier: String = ""


func _tuile(ti: int, tj: int) -> Image:
	var cle: Vector2i = Vector2i(ti, tj)
	if not _cache.has(cle):
		var p: String = "%s/%05d_%05d.jpg" % [_dossier, ti, tj]
		var img: Image = null
		if FileAccess.file_exists(p):
			img = Image.new()
			img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(p))
			img.convert(Image.FORMAT_RGB8)
		_cache[cle] = img
	return _cache[cle]


## La couche : sa tuile, ses marges prises aux voisines, le bord du domaine répété.
func _couche(ti: int, tj: int) -> Image:
	var o: Image = Image.create_empty(TAILLE, TAILLE, false, Image.FORMAT_RGB8)
	for a in [-1, 0, 1]:
		for b in [-1, 0, 1]:
			var v: Image = _tuile(ti + a * TUILE, tj + b * TUILE) if ti + a * TUILE >= 0 and tj + b * TUILE >= 0 else null
			if v != null:
				o.blit_rect(v, Rect2i(0, 0, v.get_width(), v.get_height()), Vector2i(MARGE + b * TUILE, MARGE + a * TUILE))
	# nœuds hors du domaine : le dernier connu
	var ni_ok: int = mini(NI - ti + MARGE, TAILLE)
	var nj_ok: int = mini(NJ - tj + MARGE, TAILLE)
	if ti == 0:
		var l: Image = o.get_region(Rect2i(0, MARGE, TAILLE, 1))
		l.resize(TAILLE, MARGE, Image.INTERPOLATE_NEAREST)
		o.blit_rect(l, Rect2i(0, 0, TAILLE, MARGE), Vector2i.ZERO)
	if ni_ok < TAILLE:
		var l: Image = o.get_region(Rect2i(0, ni_ok - 1, TAILLE, 1))
		l.resize(TAILLE, TAILLE - ni_ok, Image.INTERPOLATE_NEAREST)
		o.blit_rect(l, Rect2i(0, 0, TAILLE, TAILLE - ni_ok), Vector2i(0, ni_ok))
	if tj == 0:
		var c: Image = o.get_region(Rect2i(MARGE, 0, 1, TAILLE))
		c.resize(MARGE, TAILLE, Image.INTERPOLATE_NEAREST)
		o.blit_rect(c, Rect2i(0, 0, MARGE, TAILLE), Vector2i.ZERO)
	if nj_ok < TAILLE:
		var c: Image = o.get_region(Rect2i(nj_ok - 1, 0, 1, TAILLE))
		c.resize(TAILLE - nj_ok, TAILLE, Image.INTERPOLATE_NEAREST)
		o.blit_rect(c, Rect2i(0, 0, TAILLE - nj_ok, TAILLE), Vector2i(nj_ok, 0))
	return o


func _initialize() -> void:
	var sortie: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ortho="):
			_dossier = a.trim_prefix("--ortho=")
		if a.begins_with("--sortie="):
			sortie = a.trim_prefix("--sortie=")
	var nl: int = (NI - 1 + TUILE - 1) / TUILE
	var nc: int = (NJ - 1 + TUILE - 1) / TUILE
	var corps: PackedByteArray = PackedByteArray()
	var index: PackedByteArray = PackedByteArray()
	index.resize(nl * nc * 16)
	var fmt: int = 0
	var t0: int = Time.get_ticks_msec()
	var f_corps: FileAccess = FileAccess.open(sortie + ".corps", FileAccess.WRITE)
	var pos: int = 0
	for l in range(nl):
		for c in range(nc):
			var img: Image = _couche(l * TUILE, c * TUILE)
			img.generate_mipmaps()
			var e: int = img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
			if e != OK or not img.is_compressed():
				print("ECHEC compression ", l, " ", c)
				quit(1)
				return
			fmt = img.get_format()
			var brut: PackedByteArray = img.get_data()
			var z: PackedByteArray = brut.compress(FileAccess.COMPRESSION_ZSTD)
			f_corps.store_buffer(z)
			var q: int = (l * nc + c) * 16
			index.encode_u64(q, pos)
			index.encode_u32(q + 8, z.size())
			index.encode_u32(q + 12, brut.size())
			pos += z.size()
			print("couche %d,%d : %.1f Mo, %.1f Mo zstd, %.0f s" % [l, c, brut.size() / 1048576.0, z.size() / 1048576.0, (Time.get_ticks_msec() - t0) / 1000.0])
		# les voisines de la ligne précédente ne servent plus
		for k in _cache.keys():
			if (k as Vector2i).x < l * TUILE:
				_cache.erase(k)
	f_corps.close()
	var f: FileAccess = FileAccess.open(sortie, FileAccess.WRITE)
	f.store_buffer("PNOH".to_ascii_buffer())
	for v in [1, nc, nl, TUILE, TAILLE, MARGE, fmt]:
		f.store_32(v)
	f.store_buffer(index)
	var fc: FileAccess = FileAccess.open(sortie + ".corps", FileAccess.READ)
	while fc.get_position() < fc.get_length():
		f.store_buffer(fc.get_buffer(1 << 26))
	fc.close()
	f.close()
	DirAccess.remove_absolute(sortie + ".corps")
	print("CUISSON_OK %d couches, format %d, %.0f Mo, %.0f s" % [nl * nc, fmt, pos / 1048576.0, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
