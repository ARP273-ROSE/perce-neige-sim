class_name TouchControls
extends CanvasLayer
## Contrôles tactiles pour l'export Web / tablette (iPad, Android).
##
## Les boutons de conduite émettent les MÊMES actions d'entrée que le
## clavier via Input.action_press / action_release → aucune modification
## de la logique de jeu. AUTO et PANNE appellent directement main (retour
## d'essai Android : la synthèse d'InputEventKey ne donnait aucun retour
## d'état — AUTO est maintenant un vrai bouton à bascule qui reflète
## l'état réel de l'exploitation automatique).
##
## Placement calé sur le HUD standalone : bande cockpit en bas (~210 px),
## panneau salle des machines à droite (~330 px) → la colonne des freins
## est décalée vers l'intérieur pour ne pas être recouverte.

const PANEL_ALPHA := 0.55
const BTN_FONT := 22
const BTN_FONT_BIG := 26

var _main: Node = null          # référence à Main (AUTO / PANNE / état)
var _b_auto: Button = null
var _sync_accum: float = 0.0


func setup(main_node: Node) -> void:
	_main = main_node


func _ready() -> void:
	layer = 90
	_build()


func _process(delta: float) -> void:
	# Reflète l'état réel de l'auto-exploitation sur le bouton AUTO
	# (il peut aussi être basculé au clavier F3).
	_sync_accum += delta
	if _sync_accum < 0.25:
		return
	_sync_accum = 0.0
	if _b_auto != null and _main != null and _main.auto_operator != null:
		_b_auto.set_pressed_no_signal(_main.auto_operator.enabled)


func _mk_button(text: String, tip: String, big: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",
		BTN_FONT_BIG if big else BTN_FONT)
	b.modulate = Color(1, 1, 1, 0.92)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.20, PANEL_ALPHA)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	b.add_theme_stylebox_override("normal", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.20, 0.65, 0.30, 0.90)   # vert = actif/pressé
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


func _build() -> void:
	var root: Control = Control.new()
	root.name = "TouchRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Colonne GAUCHE : consigne de vitesse (maintien) -----------------
	# (Libellés ASCII : les glyphes ▲▼ manquent de la police par défaut
	# et s'affichaient en carrés sur Android.)
	var left: VBoxContainer = VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.position = Vector2(14, -180)
	left.add_theme_constant_override("separation", 18)
	root.add_child(left)

	var b_up: Button = _mk_button("+\nVITESSE", "Augmenter la consigne (maintenir)", true)
	b_up.custom_minimum_size = Vector2(132, 112)
	_bind_hold(b_up, "speed_up")
	left.add_child(b_up)

	var b_dn: Button = _mk_button("-\nVITESSE", "Réduire la consigne (maintenir)", true)
	b_dn.custom_minimum_size = Vector2(132, 112)
	_bind_hold(b_dn, "speed_down")
	left.add_child(b_dn)

	# --- Colonne DROITE : freins — décalée à GAUCHE du panneau salle des
	# machines (~330 px) qui recouvrait les boutons au bord droit.
	var right: VBoxContainer = VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right.position = Vector2(-490, -180)
	right.add_theme_constant_override("separation", 18)
	root.add_child(right)

	var b_brake: Button = _mk_button("FREIN", "Frein de service (maintenir)", true)
	b_brake.custom_minimum_size = Vector2(132, 112)
	_bind_hold(b_brake, "brake")
	right.add_child(b_brake)

	var b_emerg: Button = _mk_button("URGENCE", "Arrêt d'urgence", true)
	b_emerg.custom_minimum_size = Vector2(132, 112)
	var sbr: StyleBoxFlat = b_emerg.get_theme_stylebox("normal").duplicate()
	sbr.bg_color = Color(0.45, 0.08, 0.08, 0.70)
	sbr.border_color = Color(1.0, 0.35, 0.30, 0.9)
	b_emerg.add_theme_stylebox_override("normal", sbr)
	_bind_tap(b_emerg, "emergency")
	right.add_child(b_emerg)

	# --- Centre bas : PRÊT / DÉPART (au-dessus du bandeau HUD) -----------
	var b_go: Button = _mk_button("PRÊT / DÉPART",
		"Fermer les portes et partir (relâche aussi l'urgence)", true)
	b_go.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b_go.custom_minimum_size = Vector2(250, 78)
	b_go.position = Vector2(-125, -300)
	_bind_tap(b_go, "ready_depart")
	root.add_child(b_go)

	# --- Rangée haut-droite : boutons secondaires -------------------------
	var top: HBoxContainer = HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-4 - 4 * 112, 10)
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)

	var b_lights: Button = _mk_button("PHARES", "Phares avant")
	b_lights.custom_minimum_size = Vector2(102, 56)
	_bind_tap(b_lights, "toggle_headlights")
	top.add_child(b_lights)

	var b_view: Button = _mk_button("VUE", "Vue FPV / extérieure")
	b_view.custom_minimum_size = Vector2(102, 56)
	_bind_tap(b_view, "toggle_view")
	top.add_child(b_view)

	# PANNE / AUTO : appel DIRECT du jeu (pas de synthèse clavier — plus
	# fiable sur web) ; AUTO est un vrai bouton à bascule, vert quand
	# l'exploitation automatique est active.
	var b_fault: Button = _mk_button("PANNE",
		"Déclencher une panne aléatoire — nouvel appui : lever la panne")
	b_fault.custom_minimum_size = Vector2(102, 56)
	b_fault.pressed.connect(func() -> void:
		if _main == null or _main.fault_manager == null:
			return
		if _main.fault_manager.is_active():
			_main.fault_manager.clear_active()
		else:
			_main.fault_manager.trigger_random())
	top.add_child(b_fault)

	_b_auto = _mk_button("AUTO",
		"Exploitation automatique : embarquement ~30 s puis départ, " +
		"trajets enchaînés. Vert = actif.")
	_b_auto.custom_minimum_size = Vector2(102, 56)
	_b_auto.toggle_mode = true
	_b_auto.toggled.connect(func(_on: bool) -> void:
		if _main != null and _main.auto_operator != null:
			_main.auto_operator.toggle())
	top.add_child(_b_auto)
