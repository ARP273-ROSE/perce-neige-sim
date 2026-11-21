## Panneau RÉSEAU (mode réseau, ReseauClient) : nom, couleur, CRÉER un salon (affiche son code), REJOINDRE (saisie
## du code), QUITTER LE SALON ; au PC, l'adresse du relais si elle n'est pas réglée. Même allure que PanneauHeure.
class_name PanneauReseau
extends RefCounted

const COULEURS: Array = [Color(0.85, 0.15, 0.12), Color(0.10, 0.35, 0.85), Color(0.95, 0.75, 0.10),
	Color(0.15, 0.60, 0.25), Color(0.90, 0.45, 0.05), Color(0.55, 0.20, 0.65), Color(0.92, 0.92, 0.90)]


static func _champ(texte: String, indice: String, largeur: float) -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.text = texte
	e.placeholder_text = indice
	e.custom_minimum_size = Vector2(largeur, 52)
	e.add_theme_font_size_override("font_size", 22)
	e.virtual_keyboard_enabled = true
	return e


static func ouvrir(parent: Node, client: ReseauClient) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "PanneauReseau"
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
	boite.add_theme_constant_override("separation", 12)
	voile.add_child(boite)
	boite.add_child(PanneauHeure.etiquette("SKIER À PLUSIEURS (PC et tablette dans le même salon)", 16))
	var etat: Label = PanneauHeure.etiquette(client.statut, 22)
	etat.add_theme_color_override("font_color", Color(1, 1, 1))
	boite.add_child(etat)
	var l_nom: HBoxContainer = HBoxContainer.new()
	l_nom.alignment = BoxContainer.ALIGNMENT_CENTER
	l_nom.add_theme_constant_override("separation", 8)
	boite.add_child(l_nom)
	l_nom.add_child(PanneauHeure.etiquette("Nom", 18))
	var e_nom: LineEdit = _champ(client.nom, "votre nom", 260)
	e_nom.max_length = 16
	l_nom.add_child(e_nom)
	for col in COULEURS:
		var bc: Button = PanneauHeure.bouton("", Vector2(40, 40))
		bc.toggle_mode = false
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(20)
		sb.border_color = Color(1, 1, 1)
		sb.set_border_width_all(3 if col.is_equal_approx(client.couleur) else 0)
		bc.add_theme_stylebox_override("normal", sb)
		bc.add_theme_stylebox_override("hover", sb)
		bc.pressed.connect(func() -> void:
			client.couleur = col
			for b2 in l_nom.get_children():
				if b2 is Button:
					var s2: StyleBoxFlat = (b2 as Button).get_theme_stylebox("normal")
					s2.set_border_width_all(3 if s2.bg_color.is_equal_approx(col) else 0))
		l_nom.add_child(bc)
	var e_url: LineEdit = null
	if not OS.has_feature("web") or client.url == "":
		var l_url: HBoxContainer = HBoxContainer.new()
		l_url.alignment = BoxContainer.ALIGNMENT_CENTER
		l_url.add_theme_constant_override("separation", 8)
		boite.add_child(l_url)
		l_url.add_child(PanneauHeure.etiquette("Relais", 18))
		e_url = _champ(client.url, "wss://…/reseau", 520)
		l_url.add_child(e_url)
	var l_code: HBoxContainer = HBoxContainer.new()
	l_code.alignment = BoxContainer.ALIGNMENT_CENTER
	l_code.add_theme_constant_override("separation", 12)
	boite.add_child(l_code)
	var e_code: LineEdit = _champ(ReseauClient.code_lisible(client.code), "code du salon", 240)
	e_code.max_length = 9
	var regler := func() -> void:
		client.nom = e_nom.text.strip_edges().substr(0, 16)
		var u: String = e_url.text.strip_edges() if e_url != null else ""
		if u != "":
			client.url = u
		client.garder_reglages(u)
	var b_creer: Button = PanneauHeure.bouton("CRÉER", Vector2(170, 56))
	b_creer.toggle_mode = false
	b_creer.pressed.connect(func() -> void:
		regler.call()
		client.quitter()
		client.creer())
	l_code.add_child(b_creer)
	l_code.add_child(e_code)
	var b_rej: Button = PanneauHeure.bouton("REJOINDRE", Vector2(190, 56))
	b_rej.toggle_mode = false
	b_rej.pressed.connect(func() -> void:
		regler.call()
		client.quitter()
		client.rejoindre(e_code.text))
	l_code.add_child(b_rej)
	var bas: HBoxContainer = HBoxContainer.new()
	bas.alignment = BoxContainer.ALIGNMENT_CENTER
	bas.add_theme_constant_override("separation", 14)
	boite.add_child(bas)
	var b_q: Button = PanneauHeure.bouton("QUITTER LE SALON", Vector2(250, 56))
	b_q.toggle_mode = false
	b_q.pressed.connect(func() -> void:
		client.quitter())
	bas.add_child(b_q)
	var b_f: Button = PanneauHeure.bouton("FERMER", Vector2(170, 56))
	b_f.toggle_mode = false
	b_f.pressed.connect(func() -> void:
		regler.call()
		cl.queue_free())
	bas.add_child(b_f)
	var maj := func(t: String) -> void:
		if is_instance_valid(etat):
			etat.text = t
		if is_instance_valid(e_code) and client.code != "":
			e_code.text = ReseauClient.code_lisible(client.code)
	client.change.connect(maj)
	cl.tree_exiting.connect(func() -> void:
		if client.change.is_connected(maj):
			client.change.disconnect(maj))
	parent.add_child(cl)
	return cl
