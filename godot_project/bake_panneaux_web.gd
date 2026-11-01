extends SceneTree
## Fabrique textures/web/panneaux_atlas.png : les faces des panneaux de piste de la
## PWA, dessinées une fois pour toutes. En jeu, une SubViewport et une relecture par
## piste, à l'entrée en mode skieur, faisaient perdre le contexte WebGL sur iPad.
## xvfb-run godot --path godot_project --rendering-driver opengl3 -s bake_panneaux_web.gd

const COLONNES: int = 16
const PX: int = 128

var _images: int = 0
var _sv: SubViewport


func _initialize() -> void:
	var n: int = PistesDonnees.PISTES.size()
	var dernier: int = 0
	for ip in range(n):
		if PistesDonnees.PISTES[ip][1] >= 0 and PistesDonnees.PISTES[ip][0] != "":
			dernier = ip
	var lignes: int = dernier / COLONNES + 1
	_sv = SubViewport.new()
	_sv.size = Vector2i(COLONNES * PX, lignes * PX)
	_sv.disable_3d = true
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sv)
	for ip in range(n):
		var c: int = PistesDonnees.PISTES[ip][1]
		var nom: String = PistesDonnees.PISTES[ip][0]
		if c < 0 or nom == "":
			continue
		var f: PanneauPiste = PanneauPiste.new()
		f.nom = nom
		f.couleur = DomaineSkiable.COULEURS[c]
		f.station = "VAL D'ISÈRE" if StationsPistes.VAL_DISERE.has(ip) else "TIGNES"
		f.position = Vector2((ip % COLONNES) * PX, (ip / COLONNES) * PX)
		f.size = Vector2(PX, PX)
		var fond: ColorRect = ColorRect.new()
		fond.color = Color(0.94, 0.94, 0.92)
		fond.position = f.position
		fond.size = f.size
		_sv.add_child(fond)
		_sv.add_child(f)
	print("atlas : %d pistes, %d × %d" % [n, _sv.size.x, _sv.size.y])


func _process(_d: float) -> bool:
	_images += 1
	if _images < 5:
		return false
	var img: Image = _sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var e: int = img.save_png("res://textures/web/panneaux_atlas.png")
	print("enregistré : ", error_string(e))
	return true
