class_name PosteRemontee
extends PanelContainer
## Poste de commande d'une remontée (retour d'utilisateur, 23/10/2026 : « un poste
## de conduite spécifique à chaque remontée qui change quand on en change,
## avec des arrêts et redémarrages possibles, réglage petite, moyenne, grande
## vitesse, grande par défaut ») — d'après les pupitres réels : vitesse du
## câble, puissance, freins de service et de poulie, marche, arrêt, arrêt
## d'urgence, réarmement, référence de vitesse.

var ligne: LigneRemontee = null
var _titre: Label
var _sous_titre: Label
var _vitesse: Label
var _jauge: ProgressBar
var _etat: Label
var _puissance: Label
var _freins: Label
var _crans: Array = []
var _b_rearmer: Button


func _ready() -> void:
	var fond: StyleBoxFlat = StyleBoxFlat.new()
	fond.bg_color = Color(0.06, 0.08, 0.11, 0.88)
	fond.border_color = Color(0.55, 0.75, 1.0, 0.8)
	fond.set_border_width_all(2)
	fond.set_corner_radius_all(14)
	fond.set_content_margin_all(14)
	add_theme_stylebox_override("panel", fond)
	custom_minimum_size = Vector2(430, 0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_titre = _texte(col, 24, Color(1, 1, 1), true)
	_sous_titre = _texte(col, 16, Color(0.75, 0.82, 0.92), true)
	var l_v: HBoxContainer = HBoxContainer.new()
	col.add_child(l_v)
	_vitesse = _texte(l_v, 40, Color(0.55, 1.0, 0.65))
	_vitesse.custom_minimum_size = Vector2(190, 0)
	var droite: VBoxContainer = VBoxContainer.new()
	droite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_v.add_child(droite)
	_etat = _texte(droite, 20, Color(1, 1, 1))
	_puissance = _texte(droite, 16, Color(0.85, 0.88, 0.95))
	_jauge = ProgressBar.new()
	_jauge.min_value = 0.0
	_jauge.max_value = 1.0
	_jauge.show_percentage = false
	_jauge.custom_minimum_size = Vector2(0, 14)
	col.add_child(_jauge)
	_freins = _texte(col, 16, Color(0.85, 0.88, 0.95), true)
	# référence de vitesse
	var l_c: HBoxContainer = HBoxContainer.new()
	l_c.add_theme_constant_override("separation", 8)
	col.add_child(l_c)
	for k in range(LigneRemontee.CRANS.size()):
		var b: Button = _bouton(l_c, LigneRemontee.NOMS_CRANS[k], Color(0.20, 0.45, 0.75))
		b.toggle_mode = true
		var kk: int = k
		b.pressed.connect(func() -> void:
			if ligne != null:
				ligne.regler_cran(kk))
		_crans.append(b)
	# marche / arrêt
	var l_m: HBoxContainer = HBoxContainer.new()
	l_m.add_theme_constant_override("separation", 8)
	col.add_child(l_m)
	_bouton(l_m, "DÉMARRER", Color(0.15, 0.55, 0.25)).pressed.connect(func() -> void:
		if ligne != null:
			ligne.demarrer())
	_bouton(l_m, "ARRÊT", Color(0.75, 0.50, 0.05)).pressed.connect(func() -> void:
		if ligne != null:
			ligne.arreter())
	var l_u: HBoxContainer = HBoxContainer.new()
	l_u.add_theme_constant_override("separation", 8)
	col.add_child(l_u)
	var b_u: Button = _bouton(l_u, "ARRÊT D'URGENCE", Color(0.80, 0.08, 0.08))
	b_u.custom_minimum_size = Vector2(240, 64)
	b_u.pressed.connect(func() -> void:
		if ligne != null:
			ligne.arret_urgence())
	_b_rearmer = _bouton(l_u, "RÉARMER", Color(0.35, 0.35, 0.40))
	_b_rearmer.pressed.connect(func() -> void:
		if ligne != null:
			ligne.rearmer())


static func _fini(x: float) -> float:
	return clampf(x, -1e7, 1e7) if is_finite(x) else 0.0


func _texte(parent: Control, taille: int, couleur: Color, retour: bool = false) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	if retour:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _bouton(parent: Control, texte: String, couleur: Color) -> Button:
	var b: Button = Button.new()
	b.text = texte
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = couleur.darkened(0.25)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = couleur.lightened(0.15)
	sbp.border_color = Color(1, 1, 1, 0.9)
	sbp.set_border_width_all(2)
	b.add_theme_stylebox_override("pressed", sbp)
	parent.add_child(b)
	return b


func _process(_delta: float) -> void:
	if not visible or ligne == null or not is_instance_valid(ligne):
		return
	_titre.text = "Poste — %s" % ligne.nom_ligne
	var desc: Array = VehiculeRemontee.DESCRIPTIONS.get(ligne.famille, ["", 0, ""])
	_sous_titre.text = "%s · %.1f m/s nominal · %d véhicules" % [desc[0], ligne.vitesse, ligne.nombre_vehicules()]
	# (une valeur non finie convertie en entier fait planter la version web :
	# tout est borné avant affichage)
	var v: float = _fini(maxf(ligne.vitesse_reelle, 0.0))
	_vitesse.text = "%.1f m/s" % v
	_jauge.value = v / maxf(ligne.vitesse, 0.01)
	var etats: Dictionary = {"marche": ["EN MARCHE", Color(0.55, 1.0, 0.65)],
		"arret_normal": ["ARRÊT EN COURS", Color(1.0, 0.75, 0.25)],
		"arret": ["ARRÊTÉE", Color(0.85, 0.85, 0.85)],
		"urgence": ["ARRÊT D'URGENCE", Color(1.0, 0.30, 0.30)]}
	var e: Array = etats.get(ligne.etat, ["?", Color.WHITE])
	_etat.text = e[0]
	_etat.add_theme_color_override("font_color", e[1])
	_puissance.text = "Consigne %s (%.1f m/s)\n%d kW au câble" % [LigneRemontee.NOMS_CRANS[ligne.cran],
		ligne.vitesse * LigneRemontee.CRANS[ligne.cran], roundi(_fini(ligne.puissance_kw()))]
	var fs: bool = ligne.etat != "marche" and v <= 0.0
	var fp: bool = ligne.etat == "urgence"
	_freins.text = "Frein de service : %s · Frein de poulie : %s" % ["SERRÉ" if fs or ligne.etat == "arret_normal" else "desserré",
		"SERRÉ" if fp else "desserré"]
	for k in range(_crans.size()):
		(_crans[k] as Button).set_pressed_no_signal(k == ligne.cran)
	_b_rearmer.disabled = not (ligne.etat == "urgence" and v <= 0.0)
