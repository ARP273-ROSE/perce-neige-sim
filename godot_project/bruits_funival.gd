## Écrit data/remontees/funival_bruits.bin : les bruits des textures procédurales du Funival, calculés par la vraie
## cuisson (Funival.cuire_textures, en notant chaque bruit), pour ne pas les recalculer en jeu.
##   godot --headless --path godot_project -s bruits_funival.gd
extends SceneTree


func _initialize() -> void:
	_cuire()


func _cuire() -> void:
	Funival.enregistrer_bruits = true
	await Funival.cuire_textures(func() -> void: pass)
	var f := FileAccess.open(Funival.FICHIER_BRUITS, FileAccess.WRITE)
	var total: int = 0
	for cle in Funival.bruits_calcules:
		var k: PackedByteArray = String(cle).to_utf8_buffer()
		var o: PackedByteArray = Funival.bruits_calcules[cle]
		f.store_16(k.size())
		f.store_buffer(k)
		f.store_32(o.size())
		f.store_buffer(o)
		total += o.size()
	f.close()
	print("BRUITS_FUNIVAL %d bruits, %d octets" % [Funival.bruits_calcules.size(), total])
	quit(0)
