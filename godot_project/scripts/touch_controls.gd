class_name TouchControls
extends CanvasLayer
## Contrôles tactiles pour l'export Web / tablette (iPad PWA).
##
## Chaque bouton émet les MÊMES actions d'entrée que le clavier via
## Input.action_press / action_release (et parse_input_event pour les
## touches F1-F3) → aucune modification de la logique de jeu. Construit
## uniquement quand un écran tactile est détecté (cf. main.gd).

const PANEL_ALPHA := 0.55
const BTN_FONT := 22

# [libellé, action_ou_keycode, maintien(bool), infobulle]
# Colonne gauche : consigne de vitesse. Colonne droite : freins.
var _btn_font_big: int = 30


func _ready() -> void:
	layer = 90
	_build()


func _mk_button(text: String, tip: String, big: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",
		_btn_font_big if big else BTN_FONT)
	b.modulate = Color(1, 1, 1, 0.92)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.20, PANEL_ALPHA)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	b.add_theme_stylebox_override("normal", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.25, 0.45, 0.80, 0.85)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	return b


# Bouton "maintien" → action maintenue tant que le doigt est posé.
func _bind_hold(b: Button, action: String) -> void:
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))


# Bouton "impulsion" → un front pressé/relâché (just_pressed côté jeu).
func _bind_tap(b: Button, action: String) -> void:
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))


# Touches F1-F3 (pannes / exploitation auto) : synthèse d'un InputEventKey
# — elles sont gérées par keycode dans main._unhandled_input.
func _bind_key(b: Button, keycode: Key) -> void:
	b.pressed.connect(func() -> void:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = true
		Input.parse_input_event(ev))


func _build() -> void:
	var root: Control = Control.new()
	root.name = "TouchRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Colonne GAUCHE : consigne de vitesse (maintien) -----------------
	var left: VBoxContainer = VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.position = Vector2(14, -170)
	left.add_theme_constant_override("separation", 18)
	root.add_child(left)

	var b_up: Button = _mk_button("▲\nVITESSE", "Augmenter la consigne", true)
	b_up.custom_minimum_size = Vector2(128, 110)
	_bind_hold(b_up, "speed_up")
	left.add_child(b_up)

	var b_dn: Button = _mk_button("▼\nVITESSE", "Réduire la consigne", true)
	b_dn.custom_minimum_size = Vector2(128, 110)
	_bind_hold(b_dn, "speed_down")
	left.add_child(b_dn)

	# --- Colonne DROITE : freins -----------------------------------------
	var right: VBoxContainer = VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right.position = Vector2(-142, -170)
	right.add_theme_constant_override("separation", 18)
	root.add_child(right)

	var b_brake: Button = _mk_button("FREIN", "Frein de service (maintenir)", true)
	b_brake.custom_minimum_size = Vector2(128, 110)
	_bind_hold(b_brake, "brake")
	right.add_child(b_brake)

	var b_emerg: Button = _mk_button("URGENCE", "Arrêt d'urgence", true)
	b_emerg.custom_minimum_size = Vector2(128, 110)
	var sbr: StyleBoxFlat = b_emerg.get_theme_stylebox("normal").duplicate()
	sbr.bg_color = Color(0.45, 0.08, 0.08, 0.70)
	sbr.border_color = Color(1.0, 0.35, 0.30, 0.9)
	b_emerg.add_theme_stylebox_override("normal", sbr)
	_bind_tap(b_emerg, "emergency")
	right.add_child(b_emerg)

	# --- Centre bas : PRÊT / DÉPART (au-dessus du panneau HUD ~200 px) ----
	var b_go: Button = _mk_button("PRÊT / DÉPART",
		"Armer puis lancer le départ (relâche aussi l'urgence)", true)
	b_go.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b_go.custom_minimum_size = Vector2(240, 76)
	b_go.position = Vector2(-120, -300)
	_bind_tap(b_go, "ready_depart")
	root.add_child(b_go)

	# --- Rangée haut-droite : boutons secondaires -------------------------
	var top: HBoxContainer = HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-4 - 4 * 108, 10)
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)

	var b_lights: Button = _mk_button("PHARES", "Phares avant")
	b_lights.custom_minimum_size = Vector2(98, 56)
	_bind_tap(b_lights, "toggle_headlights")
	top.add_child(b_lights)

	var b_view: Button = _mk_button("VUE", "Vue FPV / extérieure")
	b_view.custom_minimum_size = Vector2(98, 56)
	_bind_tap(b_view, "toggle_view")
	top.add_child(b_view)

	var b_fault: Button = _mk_button("PANNE", "Déclencher une panne aléatoire (F1) — F2 pour lever")
	b_fault.custom_minimum_size = Vector2(98, 56)
	_bind_key(b_fault, KEY_F1)
	top.add_child(b_fault)

	var b_auto: Button = _mk_button("AUTO", "Exploitation automatique (F3)")
	b_auto.custom_minimum_size = Vector2(98, 56)
	_bind_key(b_auto, KEY_F3)
	top.add_child(b_auto)
