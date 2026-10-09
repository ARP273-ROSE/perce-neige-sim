class_name PolicesJeu
extends RefCounted
## Police VECTORIELLE de tous les textes en 3D (09/10/2026, Kevin : « tout
## passer en vectoriel pour que ça gère tous les types d'affichage et de
## zoom ») : Liberation Sans (SIL Open Font License 1.1, fonts/) importée en
## MSDF (champ de distance multicanal) — la forme des lettres est décrite,
## pas une image figée : le texte reste net à toutes les distances, à tous
## les zooms (loupe) et sur tous les écrans, du téléphone à la 4K.

static var _reguliere: Font = null
static var _grasse: Font = null


static func reguliere() -> Font:
	if _reguliere == null:
		_reguliere = load("res://fonts/LiberationSans-Regular.ttf") as Font
	return _reguliere


static func grasse() -> Font:
	if _grasse == null:
		_grasse = load("res://fonts/LiberationSans-Bold.ttf") as Font
	return _grasse


## Donne la police vectorielle à un Label3D qui n'en a pas.
static func equiper(l: Label3D) -> void:
	if l.font == null:
		l.font = reguliere()
	# MSDF : filtrage linéaire SANS mipmaps — les mipmaps d'un champ de
	# distance floutent les petits textes vus de loin (Kevin, 09/10/2026 :
	# « date et heure floues sur l'écran Pro-face »)
	if l.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS \
			or l.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
