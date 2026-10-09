class_name PanneauPiste
extends Control
## Face d'un panneau rond de bord de piste, dessinée une fois dans une
## texture (09/10/2026, retour d'utilisateur : « les panneaux des bords de piste sont nuls,
## ça ressemble à ça en vrai » — photo d'un panneau « Chamois 2 LES GRANDS
## MONTETS ») : disque de la couleur de la piste, liseré blanc, NOM de la
## piste en arc en haut, nom de la station en arc en bas (lettres
## blanches). Le numéro de balise, au centre, est un Label3D à part (il
## change d'un panneau à l'autre sur une même piste).

var nom: String = ""
var couleur: Color = Color.BLACK
var station: String = "TIGNES"


func _draw() -> void:
	var t: float = size.x
	var c: Vector2 = Vector2(t, t) * 0.5
	var r: float = t * 0.5
	draw_circle(c, r, Color(0.94, 0.94, 0.92))          # liseré
	draw_circle(c, r * 0.955, couleur)
	var police: Font = ThemeDB.fallback_font
	var blanc: Color = Color(1, 1, 1)
	_arc(police, nom, c, r * 0.74, true, blanc, int(t * 0.15), deg_to_rad(160.0))
	_arc(police, station, c, r * 0.76, false, blanc, int(t * 0.11), deg_to_rad(120.0))


## Texte en arc : en haut, lettres tête vers l'extérieur ; en bas, tête vers
## le centre — toujours lisible de gauche à droite.
func _arc(police: Font, texte: String, c: Vector2, rayon: float, haut: bool, col: Color,
		taille: int, ouverture_max: float) -> void:
	if texte == "":
		return
	var fs: int = taille
	var larg: float = police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if larg / rayon > ouverture_max:
		fs = maxi(8, int(fs * ouverture_max * rayon / larg))
		larg = police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ouverture: float = larg / rayon
	var a: float = (-PI * 0.5 - ouverture * 0.5) if haut else (PI * 0.5 + ouverture * 0.5)
	var sens: float = 1.0 if haut else -1.0
	var asc: float = police.get_ascent(fs)
	for ch in texte:
		var w: float = police.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var am: float = a + sens * (w * 0.5) / rayon
		var p: Vector2 = c + Vector2(cos(am), sin(am)) * rayon
		var rot: float = am + (PI * 0.5 if haut else -PI * 0.5)
		draw_set_transform(p, rot, Vector2.ONE)
		draw_char(police, Vector2(-w * 0.5, asc * 0.38), ch, fs, col)
		a += sens * w / rayon
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
