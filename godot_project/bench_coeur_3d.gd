## Relevé du cœur en vrai rendu (étape 1 de la réécriture du cœur), sans export : charge la scène et la
## sonde sonde_coeur.gd. À lancer en fenêtre, sans vsync, de préférence avec un export release (même sonde
## en autoload, voir outils_coeur/README.md) : l'éditeur ajoute son propre coût.
##   godot --path godot_project --resolution 3840x2160 -s bench_coeur_3d.gd -- --mode=normal --sortie=DOSSIER --etiq=x --duree=1500
extends SceneTree


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var m: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(m)
	current_scene = m
	var s: Node = load("res://sonde_coeur.gd").new()
	s.name = "SondeCoeur"
	get_root().add_child(s)
