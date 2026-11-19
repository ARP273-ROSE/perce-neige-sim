class_name ScenarioPanel
extends CanvasLayer
## Sélecteur de scénario au démarrage (retour d'essai iPad 2026-07-12 :
## « avant de mettre prêt départ on devrait pouvoir choisir rame 1 ou 2
## et montée ou descente »).
##
## Trois choix :
##   - gare de départ : BASSE (montée) / HAUTE (descente)
##   - rame : 1 (voie gauche dans l'évitement) / 2 (voie droite)
##   - mode de jeu : NORMAL / DÉFI / PANNES (comme la version PC)
## COMMENCER émet `chosen` puis le panneau disparaît. Tout est en ASCII
## sûr (pas de glyphes hors police par défaut mobile).

signal chosen(from_top: bool, rame2: bool, mode: String)

var _from_top: bool = false
var _rame2: bool = false
var _mode: String = "normal"    # normal | challenge | panne

var _b_low: Button = null
var _b_high: Button = null
var _b_r1: Button = null
var _b_r2: Button = null
var _b_mode: Dictionary = {}    # mode → Button
var _mode_hint: Label = null
# Heure de jeu (19/11/2026) : réelle ou choisie (date, heure, accélération), gardée d'une partie à l'autre
var _heure_choisie: bool = false
var _b_reelle: Button = null
var _b_choisie: Button = null
var _champs: Dictionary = {}    # jour, mois, annee, heure, minute → SpinBox
var _acc: OptionButton = null
var _ligne_heure: HBoxContainer = null

const MODE_HINTS: Dictionary = {
	"normal": "Exploitation normale : enveloppe Von Roll, arret automatique en gare.",
	"challenge": "DEFI : plus aucun filet. Vous freinez vous-meme, vous vous arretez\nau repere, et le trajet est NOTE a l'arrivee. Trop vite au butoir = collision.",
	"panne": "PANNES : conduite manuelle, incidents tires au sort (ou choisis) en\nligne. Le panneau vous dit quoi faire ; a vous de ramener la rame.",
}


func _ready() -> void:
	layer = 95
	_build()


func _mk_toggle(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, 64)
	b.add_theme_font_size_override("font_size", 20)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.20, 0.9)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.20, 0.65, 0.30, 0.95)   # vert = sélectionné
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover_pressed", sbp)
	return b


func _mk_label(text: String, size_pt: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_pt)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _build() -> void:
	# Voile plein écran qui absorbe les taps derrière le panneau
	var veil: ColorRect = ColorRect.new()
	veil.color = Color(0.0, 0.0, 0.0, 0.60)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	veil.add_child(box)

	box.add_child(_mk_label("FUNICULAIRE PERCE-NEIGE", 30))
	box.add_child(_mk_label("Choisissez votre scenario", 16))
	# Tampon de build : permet de verifier que la PWA tourne bien sur la
	# derniere version deployee et pas sur une copie du service worker.
	var build: Label = _mk_label("build " + PNConstants.BUILD_TAG, 11)
	build.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	box.add_child(build)

	box.add_child(_mk_label("GARE DE DEPART", 14))
	var row1: HBoxContainer = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 14)
	box.add_child(row1)
	_b_low = _mk_toggle("BASSE (montee)")
	_b_high = _mk_toggle("HAUTE (descente)")
	_b_low.button_pressed = true
	_b_low.toggled.connect(func(on: bool) -> void: _pick_station(not on))
	_b_high.toggled.connect(func(on: bool) -> void: _pick_station(on))
	row1.add_child(_b_low)
	row1.add_child(_b_high)

	box.add_child(_mk_label("RAME", 14))
	var row2: HBoxContainer = HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 14)
	box.add_child(row2)
	_b_r1 = _mk_toggle("RAME 1 (voie gauche)")
	_b_r2 = _mk_toggle("RAME 2 (voie droite)")
	_b_r1.button_pressed = true
	_b_r1.toggled.connect(func(on: bool) -> void: _pick_rame(not on))
	_b_r2.toggled.connect(func(on: bool) -> void: _pick_rame(on))
	row2.add_child(_b_r1)
	row2.add_child(_b_r2)

	box.add_child(_mk_label("MODE DE JEU", 14))
	var row3: HBoxContainer = HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.add_theme_constant_override("separation", 14)
	box.add_child(row3)
	for entry: Array in [["normal", "NORMAL"], ["challenge", "DEFI"],
			["panne", "PANNES"]]:
		var mid: String = entry[0]
		var b: Button = _mk_toggle(entry[1])
		b.custom_minimum_size = Vector2(160, 60)
		b.button_pressed = (mid == _mode)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_pick_mode(mid)
			else:
				# Un mode reste toujours sélectionné (radio, pas case à cocher)
				b.set_pressed_no_signal(mid == _mode))
		_b_mode[mid] = b
		row3.add_child(b)

	_mode_hint = _mk_label(MODE_HINTS["normal"], 13)
	_mode_hint.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	box.add_child(_mode_hint)

	_construire_heure(box)

	var go: Button = _mk_toggle("COMMENCER")
	go.toggle_mode = false
	go.custom_minimum_size = Vector2(300, 76)
	go.add_theme_font_size_override("font_size", 24)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_child(go)
	box.add_child(margin)
	go.pressed.connect(func() -> void:
		_appliquer_heure()
		chosen.emit(_from_top, _rame2, _mode)
		queue_free())


func _pick_station(from_top: bool) -> void:
	_from_top = from_top
	_b_low.set_pressed_no_signal(not from_top)
	_b_high.set_pressed_no_signal(from_top)


func _pick_rame(rame2: bool) -> void:
	_rame2 = rame2
	_b_r1.set_pressed_no_signal(not rame2)
	_b_r2.set_pressed_no_signal(rame2)


func _pick_mode(mode: String) -> void:
	_mode = mode
	for mid: String in _b_mode.keys():
		(_b_mode[mid] as Button).set_pressed_no_signal(mid == mode)
	if _mode_hint != null:
		_mode_hint.text = MODE_HINTS.get(mode, "")


## Heure de jeu : HEURE REELLE (Tignes, l'heure de maintenant) ou CHOISIE (date et heure de départ, puis le temps
## passe normalement, ou plus vite). Page haut / Page bas en jeu : une heure de plus ou de moins.
func _construire_heure(box: VBoxContainer) -> void:
	box.add_child(_mk_label("HEURE DE JEU (soleil, nuit, affluence)", 14))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_b_reelle = _mk_toggle("HEURE REELLE")
	_b_choisie = _mk_toggle("CHOISIE")
	for b in [_b_reelle, _b_choisie]:
		(b as Button).custom_minimum_size = Vector2(200, 50)
	_b_reelle.toggled.connect(func(on: bool) -> void: _pick_heure(not on))
	_b_choisie.toggled.connect(func(on: bool) -> void: _pick_heure(on))
	row.add_child(_b_reelle)
	row.add_child(_b_choisie)
	_ligne_heure = HBoxContainer.new()
	_ligne_heure.alignment = BoxContainer.ALIGNMENT_CENTER
	_ligne_heure.add_theme_constant_override("separation", 6)
	box.add_child(_ligne_heure)
	var d: Dictionary = HeureJeu.maintenant()
	for e: Array in [["jour", 1, 31, int(d["day"]), ""], ["mois", 1, 12, int(d["month"]), "/"],
			["annee", 2000, 2100, int(d["year"]), "/"], ["heure", 0, 23, int(d["hour"]), "   "],
			["minute", 0, 59, int(d["minute"]), "h"]]:
		if String(e[4]) != "":
			var sep: Label = _mk_label(String(e[4]), 18)
			_ligne_heure.add_child(sep)
		var sb: SpinBox = SpinBox.new()
		sb.min_value = float(e[1])
		sb.max_value = float(e[2])
		sb.step = 1.0
		sb.value = float(e[3])
		sb.rounded = true
		sb.allow_greater = false
		sb.custom_minimum_size = Vector2(96 if String(e[0]) == "annee" else 76, 44)
		sb.get_line_edit().add_theme_font_size_override("font_size", 18)
		_champs[e[0]] = sb
		_ligne_heure.add_child(sb)
	_acc = OptionButton.new()
	_acc.focus_mode = Control.FOCUS_NONE
	_acc.add_theme_font_size_override("font_size", 18)
	_acc.custom_minimum_size = Vector2(110, 44)
	for a in HeureJeu.ACCELERATIONS:
		_acc.add_item("x%d" % int(a))
	_acc.selected = maxi(HeureJeu.ACCELERATIONS.find(HeureJeu.acceleration), 0)
	_ligne_heure.add_child(_mk_label("  temps", 14))
	_ligne_heure.add_child(_acc)
	_pick_heure(HeureJeu.choisie)


func _pick_heure(choisie: bool) -> void:
	_heure_choisie = choisie
	_b_reelle.set_pressed_no_signal(not choisie)
	_b_choisie.set_pressed_no_signal(choisie)
	if _ligne_heure != null:
		_ligne_heure.modulate = Color(1, 1, 1, 1.0 if choisie else 0.45)
		for c in _ligne_heure.get_children():
			if c is SpinBox:
				(c as SpinBox).editable = choisie
			elif c is OptionButton:
				(c as OptionButton).disabled = not choisie


func _appliquer_heure() -> void:
	if not _heure_choisie:
		HeureJeu.revenir_reelle()
		return
	HeureJeu.regler(int(_champs["annee"].value), int(_champs["mois"].value), int(_champs["jour"].value),
		int(_champs["heure"].value), int(_champs["minute"].value),
		float(HeureJeu.ACCELERATIONS[clampi(_acc.selected, 0, HeureJeu.ACCELERATIONS.size() - 1)]))
