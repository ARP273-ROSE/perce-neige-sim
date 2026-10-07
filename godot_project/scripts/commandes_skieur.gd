class_name CommandesSkieur
extends CanvasLayer
## Commandes à l'écran du skieur jouable (PWA, iPad) : un joystick en bas à
## gauche pour marcher, le doigt glissé sur le reste de l'écran pour tourner
## la vue, et des boutons en bas à droite (COURIR, VUE 1re/3e personne,
## CONDUIRE près du poste de pilotage, QUITTER). Plusieurs doigts à la
## fois : on marche en tournant la vue. Au clavier : ZQSD / flèches, Maj,
## souris (SkieurJoueur).

const R_BASE: float = 92.0
const R_BOUTON: float = 40.0

var skieur: SkieurJoueur = null
var main: Node = null
var _racine: Control = null
var _joy: Control = null
var _centre: Vector2 = Vector2.ZERO
var _doigt_joy: int = -1
var _doigt_vue: int = -1
var _pos_vue: Vector2 = Vector2.ZERO
var _bouton_pos: Vector2 = Vector2.ZERO
var _b_conduire: Button = null
var _b_courir: Button = null
var _b_vue: Button = null
var _boutons: Array = []


func _ready() -> void:
	layer = 91
	_racine = Control.new()
	_racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	_racine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_racine)
	_joy = Control.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joy.position = Vector2(40, -40 - 2.0 * R_BASE)
	_joy.size = Vector2(2.0 * R_BASE, 2.0 * R_BASE)
	_joy.draw.connect(_dessiner_joy)
	_racine.add_child(_joy)
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_right = -24.0
	col.offset_bottom = -24.0
	col.add_theme_constant_override("separation", 14)
	_racine.add_child(col)
	_b_conduire = _bouton("CONDUIRE", "S'asseoir au poste et conduire la rame")
	_b_conduire.visible = false
	_b_conduire.pressed.connect(func() -> void:
		if skieur != null:
			skieur.conduite_demandee.emit())
	col.add_child(_b_conduire)
	_b_courir = _bouton("COURIR", "Courir (touche Maj)")
	_b_courir.toggle_mode = true
	_b_courir.toggled.connect(func(on: bool) -> void:
		if skieur != null:
			skieur.course = on)
	col.add_child(_b_courir)
	_b_vue = _bouton("1re PERS.", "Vue à la première ou à la troisième personne (touche V)")
	_b_vue.pressed.connect(basculer_vue)
	col.add_child(_b_vue)
	var b_q: Button = _bouton("QUITTER", "Revenir à la conduite")
	b_q.pressed.connect(func() -> void:
		if main != null:
			main.basculer_skieur())
	col.add_child(b_q)


func _bouton(texte: String, aide: String) -> Button:
	var b: Button = Button.new()
	b.text = texte
	b.tooltip_text = aide
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 64)
	b.add_theme_font_size_override("font_size", 22)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.20, 0.55)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.20, 0.65, 0.30, 0.90)
	b.add_theme_stylebox_override("pressed", sbp)
	_boutons.append(b)
	return b


func basculer_vue() -> void:
	if skieur == null:
		return
	skieur.premiere_personne = not skieur.premiere_personne
	_b_vue.text = "3e PERS." if skieur.premiere_personne else "1re PERS."


## Le bouton CONDUIRE n'apparaît qu'à côté du poste de pilotage.
func set_conduite_possible(oui: bool) -> void:
	if _b_conduire != null and _b_conduire.visible != oui:
		_b_conduire.visible = oui


func _dessiner_joy() -> void:
	var c: Vector2 = Vector2(R_BASE, R_BASE)
	_joy.draw_circle(c, R_BASE, Color(0.10, 0.13, 0.20, 0.35))
	_joy.draw_arc(c, R_BASE, 0.0, TAU, 48, Color(0.55, 0.75, 1.0, 0.7), 3.0)
	_joy.draw_circle(c + _bouton_pos, R_BOUTON, Color(0.55, 0.75, 1.0, 0.55))


func _sur_un_bouton(p: Vector2) -> bool:
	for b in _boutons:
		if (b as Button).visible and (b as Button).get_global_rect().has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	if skieur == null or not skieur.actif or not visible:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		var r: Rect2 = _joy.get_global_rect().grow(60.0)
		if t.pressed:
			if _doigt_joy < 0 and r.has_point(t.position):
				_doigt_joy = t.index
				_centre = _joy.get_global_rect().get_center()
				_maj_joy(t.position)
				get_viewport().set_input_as_handled()
			elif _doigt_vue < 0 and not _sur_un_bouton(t.position):
				_doigt_vue = t.index
				_pos_vue = t.position
		else:
			if t.index == _doigt_joy:
				_doigt_joy = -1
				_bouton_pos = Vector2.ZERO
				skieur.entree = Vector2.ZERO
				_joy.queue_redraw()
				get_viewport().set_input_as_handled()
			elif t.index == _doigt_vue:
				_doigt_vue = -1
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _doigt_joy:
			_maj_joy(d.position)
			get_viewport().set_input_as_handled()
		elif d.index == _doigt_vue:
			skieur.tourner_vue((d.position - _pos_vue) * 1.3)
			_pos_vue = d.position


func _maj_joy(p: Vector2) -> void:
	var v: Vector2 = (p - _centre).limit_length(R_BASE)
	_bouton_pos = v
	skieur.entree = Vector2(v.x, -v.y) / R_BASE
	_joy.queue_redraw()
