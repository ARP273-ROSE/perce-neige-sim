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
var _drive_buttons: Array = []  # boutons de conduite, grisés quand AUTO actif
var _sync_accum: float = 0.0
var _fault_tap_time: float = -10.0   # double-tap PANNE (anti fausse manip)
var _announce_menu: Control = null   # panneau des annonces audio (diffusion manuelle)

# Menu des annonces diffusables à la demande : clé de groupe → libellé FR.
# (Ordre = ordre d'exploitation logique. brake_noise exclu : pas de MP3.)
const ANNOUNCE_MENU: Array = [
	["doors_close",     "Fermeture des portes"],
	["welcome",         "Accueil zone glacier"],
	["exit_left",       "Sortie côté gauche"],
	["exit_upstream",   "Sortie amont (Grande Motte)"],
	["exit_downstream", "Sortie aval (Val Claret)"],
	["minor_incident",  "Incident mineur (5-10 min)"],
	["tech_incident",   "Incident technique"],
	["long_repair",     "Réparation prolongée"],
	["stop_10min",      "Arret de 10 minutes"],
	["restart",         "Remise en route"],
	["dim_light",       "Diminution de l'eclairage"],
	["return_station",  "Retour en gare"],
	["evac",            "Evacuation du vehicule"],
	["evac_car2",       "Evacuation 2e wagon"],
]


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
		var auto_on: bool = _main.auto_operator.enabled
		_b_auto.set_pressed_no_signal(auto_on)
		# En AUTO, l'automate écrase la consigne chaque frame → les
		# boutons de conduite sont sans effet : les griser pour que ce
		# soit lisible (retour d'essai iPad : « les contrôles vitesse ne
		# marchent pas » — AUTO était actif).
		for b: Button in _drive_buttons:
			b.disabled = auto_on
			b.modulate.a = 0.35 if auto_on else 0.92


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
	_drive_buttons.append(b_up)

	var b_dn: Button = _mk_button("-\nVITESSE", "Réduire la consigne (maintenir)", true)
	b_dn.custom_minimum_size = Vector2(132, 112)
	_bind_hold(b_dn, "speed_down")
	left.add_child(b_dn)
	_drive_buttons.append(b_dn)

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
	_drive_buttons.append(b_brake)

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
	# PRÊT / DÉPART reste ACTIF même en mode auto : sans clavier (« Entrée »),
	# c'est le seul moyen de forcer le départ sans attendre les 30 s d'arrêt
	# en gare. L'automate détecte la séquence lancée et embraye (cf.
	# AutoOperator.WAITING_AT_STATION). → volontairement PAS dans _drive_buttons.

	# --- Rangée haut-droite : boutons secondaires -------------------------
	var top: HBoxContainer = HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-4 - 6 * 112, 10)
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)

	# INVERSER : demi-tour sur place (rame à l'arrêt total, à quai ou en
	# plein tunnel — cas panne : on redescend chercher la gare). Appel
	# direct de main.do_reverse(), qui joue l'annonce « retour en gare ».
	var b_rev: Button = _mk_button("INVERSER",
		"Inverser le sens de marche (rame à l'arrêt) — retour vers la gare")
	b_rev.custom_minimum_size = Vector2(112, 56)
	b_rev.pressed.connect(func() -> void:
		if _main != null:
			_main.do_reverse())
	top.add_child(b_rev)

	var b_lights: Button = _mk_button("PHARES", "Phares avant")
	b_lights.custom_minimum_size = Vector2(102, 56)
	_bind_tap(b_lights, "toggle_headlights")
	top.add_child(b_lights)

	var b_view: Button = _mk_button("VUE", "Vue FPV / extérieure")
	b_view.custom_minimum_size = Vector2(102, 56)
	_bind_tap(b_view, "toggle_view")
	top.add_child(b_view)

	# ANNONCES : ouvre/ferme le menu des annonces audio à diffuser à la
	# demande (appel direct du système d'annonces, pas de synthèse clavier).
	var b_ann: Button = _mk_button("ANNONCES", "Diffuser une annonce audio")
	b_ann.custom_minimum_size = Vector2(120, 56)
	b_ann.pressed.connect(_toggle_announce_menu)
	top.add_child(b_ann)

	# AUTO : appel DIRECT du jeu (pas de synthèse clavier — plus fiable
	# sur web) ; vrai bouton à bascule, vert quand l'exploitation
	# automatique est active.
	_b_auto = _mk_button("AUTO",
		"Exploitation automatique : embarquement ~30 s puis départ, " +
		"trajets enchaînés. Vert = actif.")
	_b_auto.custom_minimum_size = Vector2(102, 56)
	_b_auto.toggle_mode = true
	_b_auto.toggled.connect(func(_on: bool) -> void:
		if _main != null and _main.auto_operator != null:
			_main.auto_operator.toggle())
	top.add_child(_b_auto)

	# PANNE : isolé en HAUT-GAUCHE, loin d'AUTO — un doigt qui ratait
	# AUTO déclenchait une panne (dont l'annonce « évacuation », retour
	# d'essai iPad 2026-07-12) ; et DOUBLE-TAP requis (< 1,5 s) pour
	# déclencher, un seul tap suffit pour la lever.
	var b_fault: Button = _mk_button("PANNE",
		"DOUBLE-TAP : déclencher une panne aléatoire — un tap : la lever")
	b_fault.custom_minimum_size = Vector2(102, 56)
	b_fault.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b_fault.position = Vector2(320, 10)   # à droite du panneau status
	b_fault.pressed.connect(func() -> void:
		if _main == null or _main.fault_manager == null:
			return
		if _main.fault_manager.is_active():
			_main.fault_manager.clear_active()
			return
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _fault_tap_time < 1.5:
			_main.fault_manager.trigger_random()
			_fault_tap_time = -10.0
		else:
			_fault_tap_time = now)
	root.add_child(b_fault)

	# Menu des annonces (masqué par défaut, superposé au centre)
	_build_announce_menu(root)


# ---------------------------------------------------------------------------
# Menu des annonces audio — diffusion manuelle à la demande.
# ---------------------------------------------------------------------------

func _build_announce_menu(root: Control) -> void:
	# Voile semi-opaque plein écran + panneau centré avec un bouton par
	# annonce. Chaque bouton appelle Announcements.play_now(clé) → coupe
	# l'annonce en cours et diffuse tout de suite (pas de cooldown).
	var overlay: Panel = Panel.new()
	overlay.name = "AnnounceMenu"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var ov_style: StyleBoxFlat = StyleBoxFlat.new()
	ov_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.add_theme_stylebox_override("panel", ov_style)
	root.add_child(overlay)
	_announce_menu = overlay

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 620)
	panel.position = Vector2(-280, -310)
	var p_style: StyleBoxFlat = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.11, 0.17, 0.97)
	p_style.border_color = Color(0.55, 0.75, 1.0, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(16)
	p_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", p_style)
	overlay.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "ANNONCES AUDIO"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Liste défilante des annonces
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(528, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for entry: Array in ANNOUNCE_MENU:
		var key: String = entry[0]
		var label: String = entry[1]
		var b: Button = _mk_button(label, "Diffuser : " + label)
		b.custom_minimum_size = Vector2(508, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_play_announcement.bind(key))
		list.add_child(b)

	# Pied : STOP (couper) + FERMER
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	var b_stop: Button = _mk_button("STOP", "Couper l'annonce en cours")
	b_stop.custom_minimum_size = Vector2(240, 56)
	var sb_stop: StyleBoxFlat = b_stop.get_theme_stylebox("normal").duplicate()
	sb_stop.bg_color = Color(0.45, 0.20, 0.08, 0.75)
	sb_stop.border_color = Color(1.0, 0.60, 0.30, 0.9)
	b_stop.add_theme_stylebox_override("normal", sb_stop)
	b_stop.pressed.connect(func() -> void:
		if _main != null and _main.announcements != null:
			_main.announcements.stop_all())
	footer.add_child(b_stop)

	var b_close: Button = _mk_button("FERMER", "Fermer le menu")
	b_close.custom_minimum_size = Vector2(240, 56)
	b_close.pressed.connect(_toggle_announce_menu)
	footer.add_child(b_close)


func _toggle_announce_menu() -> void:
	if _announce_menu != null:
		_announce_menu.visible = not _announce_menu.visible


func _play_announcement(key: String) -> void:
	if _main != null and _main.announcements != null:
		_main.announcements.play_now(key)
