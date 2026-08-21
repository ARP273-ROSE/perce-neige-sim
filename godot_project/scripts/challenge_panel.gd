class_name ChallengePanel
extends CanvasLayer
## Interface du mode DÉFI :
##   - bandeau permanent (haut) : record + confort courant ;
##   - bandeau de résultat à l'arrivée (score, sous-scores, avis passager) ;
##   - écran de GAME-OVER après une collision : pique sarcastique, avis
##     passager 1 étoile, bouton NOUVEAU VOYAGE.
##
## Tout en Latin-1 : la police par défaut des exports web/mobile ne
## contient ni étoiles ni emoji (retour d'essai iPad : carrés).

signal restart_requested

var challenge: Challenge = null

var _live: Label = null
var _banner: PanelContainer = null
var _banner_title: Label = null
var _banner_body: Label = null
var _banner_review: Label = null
var _over: Control = null
var _over_title: Label = null
var _over_quip: Label = null
var _over_review: Label = null


func setup(ch: Challenge) -> void:
	challenge = ch
	challenge.result_ready.connect(_on_result)
	challenge.crashed.connect(_on_crash)


func _ready() -> void:
	layer = 96
	_build()
	set_process(true)


func _t(fr: String, en: String) -> String:
	if challenge != null and challenge.lang == "en":
		return en
	return fr


func _mk_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	return sb


func _mk_label(size_pt: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size_pt)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build() -> void:
	var root: Control = Control.new()
	root.name = "ChallengeRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Bandeau permanent (sous le panneau de panne, haut centre) --------
	_live = _mk_label(15, Color(1.0, 0.85, 0.30))
	_live.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_live.position = Vector2(-260, 86)
	_live.size = Vector2(520, 24)
	root.add_child(_live)

	# --- Bandeau de résultat ---------------------------------------------
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.custom_minimum_size = Vector2(760, 0)
	_banner.position = Vector2(-380, -220)
	_banner.add_theme_stylebox_override("panel",
		_mk_style(Color(0.06, 0.10, 0.16, 0.94), Color(0.35, 0.85, 0.45, 0.95)))
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_banner.add_child(vb)
	_banner_title = _mk_label(30, Color(0.60, 1.0, 0.70))
	vb.add_child(_banner_title)
	_banner_body = _mk_label(17, Color(0.88, 0.94, 1.0))
	vb.add_child(_banner_body)
	_banner_review = _mk_label(15, Color(1.0, 0.90, 0.60))
	_banner_review.custom_minimum_size = Vector2(720, 0)
	vb.add_child(_banner_review)

	# --- Écran de game-over (collision) -----------------------------------
	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.visible = false
	root.add_child(_over)

	var veil: ColorRect = ColorRect.new()
	veil.color = Color(0.12, 0.0, 0.0, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_over.add_child(veil)

	var box: PanelContainer = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(820, 0)
	box.position = Vector2(-410, -240)
	box.add_theme_stylebox_override("panel",
		_mk_style(Color(0.10, 0.04, 0.04, 0.97), Color(1.0, 0.30, 0.20, 0.95)))
	veil.add_child(box)

	var ov: VBoxContainer = VBoxContainer.new()
	ov.add_theme_constant_override("separation", 12)
	box.add_child(ov)

	_over_title = _mk_label(32, Color(1.0, 0.35, 0.25))
	ov.add_child(_over_title)
	_over_quip = _mk_label(19, Color(1.0, 0.92, 0.80))
	_over_quip.custom_minimum_size = Vector2(780, 0)
	ov.add_child(_over_quip)
	_over_review = _mk_label(15, Color(1.0, 0.85, 0.55))
	_over_review.custom_minimum_size = Vector2(780, 0)
	ov.add_child(_over_review)

	var btn: Button = Button.new()
	btn.text = _t("NOUVEAU VOYAGE", "NEW TRIP")
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(320, 72)
	btn.add_theme_font_size_override("font_size", 24)
	var bsb: StyleBoxFlat = _mk_style(Color(0.12, 0.16, 0.24, 0.95),
		Color(0.55, 0.75, 1.0, 0.9))
	btn.add_theme_stylebox_override("normal", bsb)
	btn.add_theme_stylebox_override("hover", bsb)
	var bsp: StyleBoxFlat = bsb.duplicate()
	bsp.bg_color = Color(0.20, 0.65, 0.30, 0.95)
	btn.add_theme_stylebox_override("pressed", bsp)
	btn.pressed.connect(func() -> void:
		_over.visible = false
		restart_requested.emit())
	var center: HBoxContainer = HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(btn)
	ov.add_child(center)


func _process(_delta: float) -> void:
	if challenge == null or not challenge.enabled:
		_live.visible = false
		_banner.visible = false
		_over.visible = false
		return
	# L'écran de collision suit l'état du mode : il disparaît dès que la
	# collision est effacée (bouton NOUVEAU VOYAGE, touche R, ou passage
	# dans un autre mode).
	if _over.visible and not challenge.crash_active:
		_over.visible = false
	_live.visible = not _over.visible
	var comfort: float = 100.0
	if challenge.physics != null:
		comfort = maxf(0.0, 100.0 - challenge.physics.jerk_sum)
	_live.text = _t("DEFI   confort %.0f / 100   record %.0f",
		"CHALLENGE   comfort %.0f / 100   best %.0f") % [comfort, challenge.best]
	_banner.visible = challenge.result_t > 0.0 and not _over.visible


func _on_result(data: Dictionary) -> void:
	if data.get("quip_only", false):
		# Pique « portes ouvertes » : pas de score, juste le message.
		_banner_title.text = _t("PORTES OUVERTES", "DOORS OPEN")
		_banner_body.text = challenge.result_lines[0] if not challenge.result_lines.is_empty() else ""
		_banner_review.text = ""
		return
	var score: float = float(data.get("score", 0.0))
	_banner_title.text = "%s  %.0f / 100  %s" % [
		_t("DEFI", "CHALLENGE"), score, PNQuips.stars_ascii(score)]
	_banner_body.text = "\n".join(PackedStringArray(challenge.result_lines))
	var rev: Dictionary = data.get("review", {})
	_banner_review.text = _format_review(rev)


func _on_crash(data: Dictionary) -> void:
	_over_title.text = challenge.crash_title()
	var speed_kmh: float = float(data.get("speed", 0.0)) * 3.6
	_over_quip.text = "%.0f km/h\n\n%s" % [speed_kmh, data.get("msg", "")]
	_over_review.text = _format_review(data.get("review", {}), "[*....]")
	_over.visible = true


func _format_review(rev: Dictionary, stars: String = "") -> String:
	if rev.is_empty():
		return ""
	var head: String = rev.get("who", "")
	if stars != "":
		head = "%s  %s" % [stars, head]
	var native: String = rev.get("native", "")
	if native != "":
		return "%s\n%s\n(%s)" % [head, native, rev.get("text", "")]
	return "%s\n%s" % [head, rev.get("text", "")]
