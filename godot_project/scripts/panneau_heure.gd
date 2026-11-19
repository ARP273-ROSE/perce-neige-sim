## Réglage de l'heure de jeu (HeureJeu) : HEURE RÉELLE ou CHOISIE (jour, mois, année, heure, minute, accélération).
## Dans l'écran de choix du scénario, et en jeu (bouton HEURE du skieur, retour d'essai du 19/11/2026 : sur iPad, pas
## de clavier pour Page haut / Page bas) : PanneauHeure.ouvrir(parent) affiche un panneau avec −1 h / +1 h,
## APPLIQUER et FERMER. Tout en ASCII sûr (police par défaut des mobiles).
class_name PanneauHeure
extends VBoxContainer

signal ferme

var choisie: bool = false
var _b_reelle: Button = null
var _b_choisie: Button = null
var _champs: Dictionary = {}
var _acc: OptionButton = null
var _ligne: HBoxContainer = null
var _etat: Label = null


static func bouton(texte: String, taille: Vector2 = Vector2(200, 50)) -> Button:
	var b: Button = Button.new()
	b.text = texte
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = taille
	b.add_theme_font_size_override("font_size", 20)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.20, 0.9)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.20, 0.65, 0.30, 0.95)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover_pressed", sbp)
	return b


static func etiquette(texte: String, taille: int) -> Label:
	var l: Label = Label.new()
	l.text = texte
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _init() -> void:
	name = "PanneauHeure"
	add_theme_constant_override("separation", 10)
	add_child(etiquette("HEURE DE JEU (soleil, nuit, affluence)", 14))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_b_reelle = bouton("HEURE REELLE")
	_b_choisie = bouton("CHOISIE")
	_b_reelle.toggled.connect(func(on: bool) -> void: choisir(not on))
	_b_choisie.toggled.connect(func(on: bool) -> void: choisir(on))
	row.add_child(_b_reelle)
	row.add_child(_b_choisie)
	_ligne = HBoxContainer.new()
	_ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	_ligne.add_theme_constant_override("separation", 6)
	add_child(_ligne)
	for e: Array in [["jour", 1, 31, ""], ["mois", 1, 12, "/"], ["annee", 2000, 2100, "/"], ["heure", 0, 23, "   "],
			["minute", 0, 59, "h"]]:
		if String(e[3]) != "":
			_ligne.add_child(etiquette(String(e[3]), 18))
		var sb: SpinBox = SpinBox.new()
		sb.min_value = float(e[1])
		sb.max_value = float(e[2])
		sb.step = 1.0
		sb.rounded = true
		sb.custom_minimum_size = Vector2(96 if String(e[0]) == "annee" else 76, 44)
		sb.get_line_edit().add_theme_font_size_override("font_size", 18)
		_champs[e[0]] = sb
		_ligne.add_child(sb)
	_acc = OptionButton.new()
	_acc.focus_mode = Control.FOCUS_NONE
	_acc.add_theme_font_size_override("font_size", 18)
	_acc.custom_minimum_size = Vector2(110, 44)
	for a in HeureJeu.ACCELERATIONS:
		_acc.add_item("x%d" % int(a))
	_ligne.add_child(etiquette("  temps", 14))
	_ligne.add_child(_acc)
	relire()


## Reprend l'heure de jeu courante dans les champs.
func relire() -> void:
	var d: Dictionary = HeureJeu.maintenant()
	_champs["jour"].value = float(d["day"])
	_champs["mois"].value = float(d["month"])
	_champs["annee"].value = float(d["year"])
	_champs["heure"].value = float(d["hour"])
	_champs["minute"].value = float(d["minute"])
	_acc.selected = maxi(HeureJeu.ACCELERATIONS.find(HeureJeu.acceleration), 0)
	choisir(HeureJeu.choisie)


func choisir(oui: bool) -> void:
	choisie = oui
	_b_reelle.set_pressed_no_signal(not oui)
	_b_choisie.set_pressed_no_signal(oui)
	_ligne.modulate = Color(1, 1, 1, 1.0 if oui else 0.45)
	for c in _ligne.get_children():
		if c is SpinBox:
			(c as SpinBox).editable = oui
		elif c is OptionButton:
			(c as OptionButton).disabled = not oui


## Décale les champs d'une heure (en passant en heure choisie).
func decaler(h: int) -> void:
	choisir(true)
	var t: int = Time.get_unix_time_from_datetime_dict({"year": int(_champs["annee"].value), "month": int(_champs["mois"].value),
		"day": int(_champs["jour"].value), "hour": int(_champs["heure"].value), "minute": int(_champs["minute"].value),
		"second": 0}) + h * 3600
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(t)
	_champs["jour"].value = float(d["day"])
	_champs["mois"].value = float(d["month"])
	_champs["annee"].value = float(d["year"])
	_champs["heure"].value = float(d["hour"])
	_champs["minute"].value = float(d["minute"])


func appliquer() -> void:
	if not choisie:
		HeureJeu.revenir_reelle()
		return
	HeureJeu.regler(int(_champs["annee"].value), int(_champs["mois"].value), int(_champs["jour"].value),
		int(_champs["heure"].value), int(_champs["minute"].value),
		float(HeureJeu.ACCELERATIONS[clampi(_acc.selected, 0, HeureJeu.ACCELERATIONS.size() - 1)]))


## Panneau en jeu (calque au-dessus de tout) : réglage, −1 h, +1 h, APPLIQUER, FERMER. Rend le calque créé.
static func ouvrir(parent: Node, apres: Callable = Callable()) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "ReglageHeure"
	cl.layer = 96
	var voile: ColorRect = ColorRect.new()
	voile.color = Color(0.0, 0.0, 0.0, 0.55)
	voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	voile.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(voile)
	var boite: VBoxContainer = VBoxContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boite.grow_vertical = Control.GROW_DIRECTION_BOTH
	boite.add_theme_constant_override("separation", 14)
	voile.add_child(boite)
	var p: PanneauHeure = PanneauHeure.new()
	boite.add_child(p)
	var bas: HBoxContainer = HBoxContainer.new()
	bas.alignment = BoxContainer.ALIGNMENT_CENTER
	bas.add_theme_constant_override("separation", 14)
	boite.add_child(bas)
	var fermer := func() -> void:
		cl.queue_free()
		p.ferme.emit()
	for e: Array in [["-1 h", -1], ["+1 h", 1]]:
		var b: Button = bouton(String(e[0]), Vector2(110, 56))
		b.toggle_mode = false
		var dh: int = e[1]
		b.pressed.connect(func() -> void:
			p.decaler(dh)
			p.appliquer()
			if apres.is_valid():
				apres.call())
		bas.add_child(b)
	var ok: Button = bouton("APPLIQUER", Vector2(190, 56))
	ok.toggle_mode = false
	ok.pressed.connect(func() -> void:
		p.appliquer()
		if apres.is_valid():
			apres.call()
		fermer.call())
	bas.add_child(ok)
	var non: Button = bouton("FERMER", Vector2(150, 56))
	non.toggle_mode = false
	non.pressed.connect(fermer)
	bas.add_child(non)
	parent.add_child(cl)
	return cl
