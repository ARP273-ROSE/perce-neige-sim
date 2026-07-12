class_name HUD
extends CanvasLayer
## HUD principal — assemble :
##   - CockpitPanel (bandeau bas, console Von Roll style)
##   - MachineRoomPanel (colonne droite, schéma cable + poulies + 3 moteurs)
##   - Panneau panne (haut droit, sur transition couleur sévérité)
##   - Status texte minimal en haut gauche (mode vue, langue, temps trip)
##   - Help bar (raccourcis)
## Bilingue FR/EN via OS locale.

var physics: TrainPhysics = null
var fault_manager: FaultManager = null
var lang: String = "fr"

@onready var _status_label: Label
@onready var _help_label: Label
@onready var _fault_panel: Panel
@onready var _fault_label: Label
@onready var _fault_severity_label: Label
@onready var _fault_timer_label: Label
@onready var _cockpit: CockpitPanel
@onready var _machine_room: MachineRoomPanel


func _ready() -> void:
	_detect_lang()
	_build_ui()
	set_process(true)


func _detect_lang() -> void:
	var loc: String = OS.get_locale().to_lower()
	lang = "fr" if loc.begins_with("fr") else "en"


func _t(en: String, fr: String) -> String:
	return fr if lang == "fr" else en


func _build_ui() -> void:
	# --- Console cockpit (bandeau bas, full-width) ---
	_cockpit = CockpitPanel.new()
	_cockpit.name = "CockpitPanel"
	add_child(_cockpit)

	# --- Panneau salle des machines (colonne droite) ---
	_machine_room = MachineRoomPanel.new()
	_machine_room.name = "MachineRoomPanel"
	add_child(_machine_room)

	# --- Petit status label haut-gauche (titre + état trip succinct) ---
	var top_panel: Panel = Panel.new()
	top_panel.name = "TopStatus"
	top_panel.position = Vector2(16, 16)
	top_panel.size = Vector2(280, 64)
	var top_style: StyleBoxFlat = StyleBoxFlat.new()
	top_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	top_style.border_color = Color(0.95, 0.85, 0.20)
	top_style.border_width_left = 2
	top_style.border_width_top = 2
	top_style.border_width_right = 2
	top_style.border_width_bottom = 2
	top_style.corner_radius_top_left = 6
	top_style.corner_radius_top_right = 6
	top_style.corner_radius_bottom_left = 6
	top_style.corner_radius_bottom_right = 6
	top_panel.add_theme_stylebox_override("panel", top_style)
	add_child(top_panel)

	var top_vbox: VBoxContainer = VBoxContainer.new()
	top_vbox.position = Vector2(10, 6)
	top_vbox.size = Vector2(260, 50)
	top_vbox.add_theme_constant_override("separation", 2)
	top_panel.add_child(top_vbox)

	var title: Label = Label.new()
	title.text = "PERCE-NEIGE SIM 3D"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	title.add_theme_font_size_override("font_size", 14)
	top_vbox.add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_status_label.add_theme_font_size_override("font_size", 12)
	top_vbox.add_child(_status_label)

	# --- Help bar (raccourcis) ---
	_help_label = Label.new()
	_help_label.text = _t(
		"↑/↓ Setpoint · Space Brake · Shift Emerg · H Phares · V View · Enter Depart · F1 Fault · F2 Clear · F3 Auto-op",
		"↑/↓ Consigne · Espace Frein · Shift Urgence · H Phares · V Vue · Entrée Départ · F1 Panne · F2 Clear · F3 Auto-exploit"
	)
	_help_label.position = Vector2(20, 218)
	_help_label.size = Vector2(1560, 22)
	_help_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.90))
	_help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_help_label.add_theme_constant_override("outline_size", 3)
	_help_label.add_theme_font_size_override("font_size", 11)
	add_child(_help_label)

	# --- Panneau panne (haut droit, masqué par défaut) ---
	_fault_panel = Panel.new()
	_fault_panel.name = "FaultPanel"
	_fault_panel.position = Vector2(310, 16)
	_fault_panel.size = Vector2(680, 64)
	var fault_style: StyleBoxFlat = StyleBoxFlat.new()
	fault_style.bg_color = Color(0.10, 0.05, 0.05, 0.92)
	fault_style.border_color = Color(1.0, 0.30, 0.10)
	fault_style.border_width_left = 3
	fault_style.border_width_top = 3
	fault_style.border_width_right = 3
	fault_style.border_width_bottom = 3
	fault_style.corner_radius_top_left = 6
	fault_style.corner_radius_top_right = 6
	fault_style.corner_radius_bottom_left = 6
	fault_style.corner_radius_bottom_right = 6
	_fault_panel.add_theme_stylebox_override("panel", fault_style)
	_fault_panel.visible = false
	add_child(_fault_panel)

	var fault_vbox: VBoxContainer = VBoxContainer.new()
	fault_vbox.position = Vector2(12, 6)
	fault_vbox.size = Vector2(656, 50)
	fault_vbox.add_theme_constant_override("separation", 2)
	_fault_panel.add_child(fault_vbox)

	_fault_severity_label = Label.new()
	_fault_severity_label.add_theme_font_size_override("font_size", 16)
	_fault_severity_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.10))
	_fault_severity_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fault_severity_label.add_theme_constant_override("outline_size", 3)
	fault_vbox.add_child(_fault_severity_label)

	_fault_label = Label.new()
	_fault_label.add_theme_font_size_override("font_size", 14)
	_fault_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	fault_vbox.add_child(_fault_label)

	_fault_timer_label = Label.new()
	_fault_timer_label.add_theme_font_size_override("font_size", 11)
	_fault_timer_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	fault_vbox.add_child(_fault_timer_label)


func set_physics(p: TrainPhysics) -> void:
	physics = p
	if _cockpit != null:
		_cockpit.setup(p, fault_manager)
	if _machine_room != null:
		_machine_room.setup(p, fault_manager)


func set_fault_manager(fm: FaultManager) -> void:
	fault_manager = fm
	if _cockpit != null and physics != null:
		_cockpit.setup(physics, fm)
	if _machine_room != null and physics != null:
		_machine_room.setup(physics, fm)


func _process(_delta: float) -> void:
	if physics == null:
		return
	_status_label.text = _status_text()
	_update_fault_panel()


func _status_text() -> String:
	if physics.emergency or physics.emergency_brake:
		return _t("EMERGENCY BRAKE", "FREIN URGENCE")
	if physics.finished:
		return _t("ARRIVED", "ARRIVÉ")
	if not physics.trip_started:
		return _t("READY — press Enter to depart", "PRÊT — Entrée pour départ")
	if absf(physics.v) < 0.1:
		return _t("Stopped at station", "Arrêté en gare")
	if physics.direction > 0:
		return _t("Climbing → Glacier", "Montée → Glacier")
	return _t("Descending → Val Claret", "Descente → Val Claret")


func _update_fault_panel() -> void:
	if fault_manager == null or not fault_manager.is_active():
		_fault_panel.visible = false
		return
	_fault_panel.visible = true
	var sev_color: Color = fault_manager.get_active_severity_color()
	var style: StyleBoxFlat = _fault_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.border_color = sev_color
	_fault_severity_label.text = "[%s] %s" % [fault_manager.get_active_severity_label(), fault_manager.get_active_id().to_upper()]
	_fault_severity_label.add_theme_color_override("font_color", sev_color)
	_fault_label.text = fault_manager.get_active_label()
	var rem: float = fault_manager.get_active_remaining()
	if is_inf(rem) or rem <= 0.0:
		_fault_timer_label.text = _t("Manual intervention required (R for new trip)",
			"Intervention requise (R pour nouveau voyage)")
	else:
		_fault_timer_label.text = _t("Auto-clear in %.0fs", "Auto-clear dans %.0fs") % rem
