class_name ScenarioPanel
extends CanvasLayer
## Sélecteur de scénario au démarrage (retour d'essai iPad 2026-07-12 :
## « avant de mettre prêt départ on devrait pouvoir choisir rame 1 ou 2
## et montée ou descente »).
##
## Deux choix :
##   - gare de départ : BASSE (montée) / HAUTE (descente)
##   - rame : 1 (voie gauche dans l'évitement) / 2 (voie droite)
## COMMENCER émet `chosen` puis le panneau disparaît. Tout est en ASCII
## sûr (pas de glyphes hors police par défaut mobile).

signal chosen(from_top: bool, rame2: bool)

var _from_top: bool = false
var _rame2: bool = false

var _b_low: Button = null
var _b_high: Button = null
var _b_r1: Button = null
var _b_r2: Button = null


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

	var go: Button = _mk_toggle("COMMENCER")
	go.toggle_mode = false
	go.custom_minimum_size = Vector2(300, 76)
	go.add_theme_font_size_override("font_size", 24)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_child(go)
	box.add_child(margin)
	go.pressed.connect(func() -> void:
		chosen.emit(_from_top, _rame2)
		queue_free())


func _pick_station(from_top: bool) -> void:
	_from_top = from_top
	_b_low.set_pressed_no_signal(not from_top)
	_b_high.set_pressed_no_signal(from_top)


func _pick_rame(rame2: bool) -> void:
	_rame2 = rame2
	_b_r1.set_pressed_no_signal(not rame2)
	_b_r2.set_pressed_no_signal(rame2)
