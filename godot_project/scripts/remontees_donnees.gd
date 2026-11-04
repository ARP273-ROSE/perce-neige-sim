class_name RemonteesDonnees
extends RefCounted
## Lignes de remontées posées dans le jeu : données numériques (profil,
## pylônes et balanciers, vitesse, espacement, voie…) exportées du dossier
## des remontées (fiches techniques remontees-mecaniques.net, positions
## OpenStreetMap). Généré dans data/remontees/lignes.bin : un tableau de 0,5 Mo écrit en script
## coûtait 40 Mo de mémoire à la compilation, jamais rendus sur la PWA.

const FICHIER: String = "res://data/remontees/lignes.bin"
static var LIGNES: Array = _lire()


static func _lire() -> Array:
	var f: FileAccess = FileAccess.open(FICHIER, FileAccess.READ)
	if f == null:
		push_error("Remontées : %s introuvable" % FICHIER)
		return []
	var n: int = f.get_32()
	var z: PackedByteArray = f.get_buffer(f.get_length() - 4)
	f.close()
	return bytes_to_var(z.decompress(n, FileAccess.COMPRESSION_ZSTD))
