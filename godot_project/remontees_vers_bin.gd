## Écrit data/remontees/lignes.bin depuis le tableau généré par exporter_jeu.py.
##   godot --headless --path godot_project --script remontees_vers_bin.gd -- SOURCE.gd
extends SceneTree


func _init() -> void:
	var source: String = OS.get_cmdline_user_args()[0]
	var lignes: Array = (load(source) as GDScript).get_script_constant_map()["LIGNES"]
	var brut: PackedByteArray = var_to_bytes(lignes)
	var f: FileAccess = FileAccess.open(RemonteesDonnees.FICHIER, FileAccess.WRITE)
	f.store_32(brut.size())
	f.store_buffer(brut.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	print("%s : %d lignes" % [RemonteesDonnees.FICHIER, lignes.size()])
	quit()
