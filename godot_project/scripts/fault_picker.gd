class_name FaultPicker
extends CanvasLayer
## Sélecteur de panne du mode PANNES (équivalent du dialogue F du sim PC).
##
## Liste les 15 pannes, colorées par sévérité, avec pour chacune un rappel
## de ce qu'elle impose. Trois commandes en pied de panneau :
##   - PANNE ALEATOIRE : tirage pondéré (mêmes poids que le PC) ;
##   - LEVER LA PANNE  : résolution immédiate (maintenance) ;
##   - TIRAGE AUTO     : bascule le planificateur (1 incident / 5-6 min).

var fault_manager: FaultManager = null
var _overlay: Control = null
var _b_auto: Button = null
var _detail: Label = null


func setup(fm: FaultManager) -> void:
	fault_manager = fm
	_refresh_auto()


func _ready() -> void:
	layer = 94
	_build()


func toggle() -> void:
	if _overlay != null:
		_overlay.visible = not _overlay.visible
		_refresh_auto()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func _lang() -> String:
	return fault_manager.lang if fault_manager != null else "fr"


func _t(fr: String, en: String) -> String:
	return en if _lang() == "en" else fr


func _mk_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	return sb


func _mk_button(text: String, border: Color) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sb: StyleBoxFlat = _mk_style(Color(0.10, 0.13, 0.20, 0.92), border)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.20, 0.65, 0.30, 0.92)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover_pressed", sbp)
	return b


func _build() -> void:
	_overlay = Control.new()
	_overlay.name = "FaultPickerRoot"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var veil: ColorRect = ColorRect.new()
	veil.color = Color(0.0, 0.0, 0.0, 0.55)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(veil)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(700, 700)
	panel.position = Vector2(-350, -350)
	panel.add_theme_stylebox_override("panel",
		_mk_style(Color(0.07, 0.10, 0.16, 0.97), Color(1.0, 0.55, 0.20, 0.9)))
	veil.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = _t("DECLENCHER UNE PANNE", "TRIGGER A FAULT")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for fid: String in FaultProfiles.ORDER:
		var b: Button = _mk_button("…", Color(0.55, 0.75, 1.0, 0.8))
		b.custom_minimum_size = Vector2(640, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("fault_id", fid)
		b.pressed.connect(_on_pick.bind(fid))
		list.add_child(b)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", Color(0.80, 0.88, 0.98))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(660, 46)
	_detail.text = _t("Choisissez une panne : elle se declenche immediatement.",
		"Pick a fault : it triggers immediately.")
	vbox.add_child(_detail)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	var b_rand: Button = _mk_button(_t("ALEATOIRE", "RANDOM"),
		Color(1.0, 0.70, 0.20, 0.9))
	b_rand.custom_minimum_size = Vector2(160, 54)
	b_rand.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_rand.pressed.connect(func() -> void:
		if fault_manager != null:
			fault_manager.trigger(FaultProfiles.weighted_pick())
		_close())
	footer.add_child(b_rand)

	var b_clear: Button = _mk_button(_t("LEVER", "CLEAR"),
		Color(0.40, 0.95, 0.55, 0.9))
	b_clear.custom_minimum_size = Vector2(150, 54)
	b_clear.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_clear.pressed.connect(func() -> void:
		if fault_manager != null:
			fault_manager.clear_active()
		_close())
	footer.add_child(b_clear)

	_b_auto = _mk_button(_t("TIRAGE AUTO", "AUTO ROLL"),
		Color(0.55, 0.75, 1.0, 0.9))
	_b_auto.custom_minimum_size = Vector2(190, 54)
	_b_auto.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_b_auto.toggle_mode = true
	_b_auto.toggled.connect(func(on: bool) -> void:
		if fault_manager != null:
			fault_manager.scheduler_enabled = on)
	footer.add_child(_b_auto)

	var b_close: Button = _mk_button(_t("FERMER", "CLOSE"),
		Color(0.75, 0.80, 0.88, 0.8))
	b_close.custom_minimum_size = Vector2(150, 54)
	b_close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_close.pressed.connect(_close)
	footer.add_child(b_close)

	_populate_labels(list)


func _populate_labels(list: VBoxContainer) -> void:
	# Les libellés dependent de la langue detectee par le FaultManager, qui
	# n'est branche qu'apres _ready() : on repasse dessus a l'ouverture.
	set_process(true)
	_labels_node = list


var _labels_node: VBoxContainer = null
var _labels_done: bool = false


func _process(_delta: float) -> void:
	if _labels_done or fault_manager == null or _labels_node == null:
		return
	_labels_done = true
	for child in _labels_node.get_children():
		var b: Button = child as Button
		if b == null:
			continue
		var fid: String = str(b.get_meta("fault_id"))
		b.text = "%s   [%s]" % [fault_manager.label_of(fid),
			fault_manager.SEVERITY_LABEL[fault_manager.FAULTS[fid]["severity"]][_lang()]]
		var sb: StyleBoxFlat = (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
		sb.border_color = fault_manager.severity_color_of(fid)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)


func _on_pick(fault_id: String) -> void:
	if fault_manager != null:
		fault_manager.trigger(fault_id)
	_close()


func _close() -> void:
	if _overlay != null:
		_overlay.visible = false


func _refresh_auto() -> void:
	if _b_auto != null and fault_manager != null:
		_b_auto.set_pressed_no_signal(fault_manager.scheduler_enabled)
