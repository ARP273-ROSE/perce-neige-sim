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
var poste: PosteRemontee = null
var _b_poste: Button = null
## Remontée du pupitre (celle où l'on est, ou la plus proche) : lue par main.gd pour la télémesure du PC.
var ligne_suivie: LigneRemontee = null
var _t_poste: float = 0.0
var _racine: Control = null
var _joy: Control = null
var _centre: Vector2 = Vector2.ZERO
var _doigt_joy: int = -1
var _doigt_vue: int = -1
var _doigt_zoom: int = -1
var _pos_zoom: Vector2 = Vector2.ZERO
var _doigts: Dictionary = {}             # doigts posés (index)
var _pos_vue: Vector2 = Vector2.ZERO
var _bouton_pos: Vector2 = Vector2.ZERO
var _pos_joy_defaut: Vector2 = Vector2.ZERO   # base du joystick au repos (bas à gauche)
var _b_conduire: Button = null
var _b_courir: Button = null
var _b_vue: Button = null
var _b_vue_ligne: Button = null         # vues de la remontée (touche T), à bord seulement
var _b_ski: Button = null
var _b_echelle: Button = null
var _b_mesure: Button = null
var _b_auto: Button = null
var _b_evac: Button = null
var _b_corde: Button = null
var _b_exploit: Button = null
var _boutons: Array = []
var _info: Label = null                 # vitesse et piste, à ski
var _msg: Label = null                  # message passager (refus, chrono)
var _pique: Label = null                # pique sarcastique : sa propre ligne, jamais écrasée
var _t_pique: float = 0.0
var _t_msg: float = 0.0
var carte: CartePistes = null           # carte des pistes (à ski)
var _carte_masquee: bool = false
## À pied : la carte n'est montrée que si on la demande (bouton CARTE) — elle
## sert à rejoindre une remontée (« aller à », retour d'utilisateur, 22/10/2026)
var _carte_a_pied: bool = false
var _chausse: bool = false
var _b_carte: Button = null
var _b_quitter: Button = null           # caché sur le PC : la barre de la fenêtre a CONDUIRE (même geste)


func _ready() -> void:
	# (commandes masquées : les doigts posés ne seront pas vus se lever)
	visibility_changed.connect(func() -> void:
		if not visible:
			oublier_doigts())
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
	# joystick seulement sur écran tactile (PC à la souris : ZQSD, retour d'utilisateur du 24/11/2026) ; un premier
	# toucher le fait paraître (PC à écran tactile mal détecté)
	_joy.visible = DisplayServer.is_touchscreen_available()
	_racine.add_child(_joy)
	# colonne de boutons en bas à droite, qui passe sur une 2e colonne (à sa gauche) quand la hauteur manque : une
	# seule colonne grandissait vers le haut et sortait de l'écran, CORDE en tête (retour d'utilisateur du 24/11/2026)
	var col: VFlowContainer = VFlowContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = -174.0
	col.offset_right = -24.0
	col.offset_top = 112.0               # (sous la barre du haut et la ligne d'info)
	col.offset_bottom = -24.0
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.alignment = FlowContainer.ALIGNMENT_END          # chaque colonne calée en bas
	col.set("reverse_fill", true)                        # la 1re colonne à droite
	col.add_theme_constant_override("v_separation", 14)
	col.add_theme_constant_override("h_separation", 14)
	_racine.add_child(col)
	_b_conduire = _bouton("CONDUIRE", "S'asseoir au poste et conduire la rame")
	_b_conduire.visible = false
	_b_conduire.pressed.connect(func() -> void:
		if skieur != null:
			skieur.conduite_demandee.emit())
	col.add_child(_b_conduire)
	_b_evac = _bouton("ÉVACUER", "Rame arrêtée en tunnel : enlever les issues de secours de la face et descendre sur la voie (touche U)")
	_b_evac.visible = false
	_b_evac.pressed.connect(func() -> void:
		if main != null:
			main.evacuer())
	col.add_child(_b_evac)
	_b_corde = _bouton("CORDE", "Remontée à l'arrêt en ligne : descendre à la corde du siège ou de la cabine jusqu'au sol")
	_b_corde.visible = false
	_b_corde.pressed.connect(func() -> void:
		var rm_c: RemonteesDomaine = main.get("remontees") if main != null else null
		if rm_c != null:
			rm_c.descendre_corde())
	col.add_child(_b_corde)
	_b_exploit = _bouton("EXPLOIT.", "EXPLOITATION AUTO : tout le service du funiculaire (embarquements, départs enchaînés), marche / arrêt, même en skieur (touche X ; Web : aussi F3 ou EXPLOIT. du tableau de bord)")
	_b_exploit.toggle_mode = true
	_b_exploit.toggled.connect(func(on: bool) -> void:
		if main != null:
			main.basculer_exploitation(on))
	col.add_child(_b_exploit)
	# carte des pistes en surimpression (à ski), en haut à droite
	carte = CartePistes.new()
	carte.name = "CartePistes"
	carte.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	carte.visible = false
	_racine.add_child(carte)
	# à gauche de la colonne de boutons, qu'elle recouvrait, CARTE compris : une fois
	# ouverte, plus moyen de la fermer (retour d'utilisateur, 02/11/2026)
	var placer_carte: Callable = func() -> void:
		var bord: float = col.size.x + 24.0 + 12.0
		carte.offset_left = -CartePistes.TAILLE.x - bord
		carte.offset_right = -bord
		carte.offset_top = 96.0
		carte.offset_bottom = 96.0 + CartePistes.TAILLE.y
	col.resized.connect(placer_carte)
	placer_carte.call()
	_b_carte = _bouton("CARTE", "Carte des pistes autour de soi : + / − ou molette pour zoomer ; toucher une remontée pour y aller")
	_b_carte.toggle_mode = true
	_b_carte.button_pressed = true
	_b_carte.visible = false
	_b_carte.toggled.connect(func(on: bool) -> void:
		if _chausse:
			_carte_masquee = not on
		else:
			_carte_a_pied = on
		_maj_carte())
	col.add_child(_b_carte)
	_b_ski = _bouton("CHAUSSER", "Chausser ou déchausser les skis, dehors sur la neige ; sur une perche de téléski, la lâcher (touche E)")
	_b_ski.pressed.connect(func() -> void:
		if main != null:
			main.basculer_ski())
	col.add_child(_b_ski)
	_b_echelle = _bouton("GRIMPER", "Monter à l'échelle du pylône, déchaussé ; de nouveau pour repartir dans l'autre sens (touche G ; joystick : haut, bas)")
	_b_echelle.visible = false
	_b_echelle.pressed.connect(func() -> void:
		if main != null:
			main.basculer_echelle())
	col.add_child(_b_echelle)
	_b_auto = _bouton("BOUCLE", "BOUCLE : le skieur fait la boucle tout seul — gare, rame, terrasse, ski, retour (touche B) ; il enclenche l'exploitation auto pour son trajet")
	_b_auto.toggle_mode = true
	_b_auto.toggled.connect(func(on: bool) -> void:
		if main != null and (main.skieur_auto != null) != on:
			main.basculer_skieur_auto())
	col.add_child(_b_auto)
	_b_courir = _bouton("COURIR", "Courir (touche Maj) ; à ski : schuss")
	_b_courir.toggle_mode = true
	_b_courir.toggled.connect(func(on: bool) -> void:
		if skieur != null:
			skieur.course = on)
	col.add_child(_b_courir)
	# poste de commande de la remontée où l'on est (ou de la plus proche)
	_b_poste = _bouton("POSTE", "Poste de commande de la remontée : marche, arrêt, arrêt d'urgence, vitesse")
	_b_poste.toggle_mode = true
	_b_poste.visible = false
	_b_poste.toggled.connect(func(on: bool) -> void:
		poste.visible = on)
	col.add_child(_b_poste)
	poste = PosteRemontee.new()
	poste.name = "PosteRemontee"
	poste.set_anchors_preset(Control.PRESET_TOP_LEFT)
	poste.position = Vector2(16.0, 140.0)
	poste.visible = false
	_racine.add_child(poste)
	# déplaçable, borné à l'écran, et un seul poste de conduite à la fois sur le PC (retour d'utilisateur du
	# 19/11/2026, plein écran 4K : « tu me mets deux postes de conduite, les fenêtres je peux pas les déplacer ») :
	# ouvert, il replie le pupitre en surimpression du PC ; déplier celui-ci le ferme (fermer_poste)
	GlisserPanneau.activer(poste)
	poste.visibility_changed.connect(_poste_affiche)
	_b_mesure = _bouton("MESURE", "Relevé de fluidité : une minute de mesures (images par seconde, à-coups), envoyé au développeur pour optimiser le jeu sur cet appareil (touche F10)")
	_b_mesure.pressed.connect(func() -> void:
		var pm: Node = main.get("perf_manager") if main != null else null
		if pm != null:
			pm.call("releve"))
	col.add_child(_b_mesure)
	# heure de jeu, en jeu (retour d'essai du 19/11/2026 : sur iPad, pas de clavier pour Page haut / Page bas)
	var b_h: Button = _bouton("HEURE", "Heure de jeu : heure réelle ou choisie, jour, accélération ; −1 h / +1 h (touches Page haut / Page bas)")
	b_h.pressed.connect(func() -> void:
		PanneauHeure.ouvrir(self, func() -> void:
			if main != null:
				main.set("_t_jour", 0.0)
				message("Heure de jeu : " + HeureJeu.libelle(), 3.0)))
	col.add_child(b_h)
	# mode réseau : skier à plusieurs (PWA et PC dans le même salon)
	var b_r: Button = _bouton("RÉSEAU", "Skier à plusieurs : créer un salon (un code à donner) ou en rejoindre un")
	b_r.pressed.connect(func() -> void:
		if main != null:
			PanneauReseau.ouvrir(self, main.reseau_client()))
	col.add_child(b_r)
	_b_vue = _bouton("1re PERS.", "Vue à la première ou à la troisième personne (touche V)")
	_b_vue.pressed.connect(basculer_vue)
	col.add_child(_b_vue)
	_b_vue_ligne = _bouton("VUE LIGNE", "À bord d'une remontée : vue orbitale, depuis le pylône, depuis la gare, travelling, drone (touche T) ; glisser et molette en orbite")
	_b_vue_ligne.visible = false
	_b_vue_ligne.pressed.connect(func() -> void:
		if main != null:
			main.basculer_vue_ligne())
	col.add_child(_b_vue_ligne)
	var b_q: Button = _bouton("QUITTER", "Revenir à la conduite")
	_b_quitter = b_q
	b_q.pressed.connect(func() -> void:
		if main != null:
			main.basculer_skieur())
	col.add_child(b_q)
	for k in range(2):
		var l: Label = Label.new()
		l.set_anchors_preset(Control.PRESET_CENTER_TOP if k == 0 else Control.PRESET_CENTER)
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.offset_top = 18.0 if k == 0 else -120.0
		l.add_theme_font_size_override("font_size", 26 if k == 0 else 30)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_racine.add_child(l)
		if k == 0:
			# sous la barre de boutons du haut (elle descend à ~66) et sur un
			# fond sombre : il passait par-dessus les boutons, illisible
			# (retour d'utilisateur, 23/10/2026)
			l.offset_top = 76.0
			var fond: StyleBoxFlat = StyleBoxFlat.new()
			fond.bg_color = Color(0.05, 0.07, 0.10, 0.55)
			fond.set_corner_radius_all(10)
			fond.content_margin_left = 14.0
			fond.content_margin_right = 14.0
			fond.content_margin_top = 4.0
			fond.content_margin_bottom = 4.0
			l.add_theme_stylebox_override("normal", fond)
			_info = l
		else:
			_msg = l
	# ligne des piques, sous les messages (09/10/2026 : une seule pique vue
	# pendant toute une descente — les messages d'état l'effaçaient)
	_pique = Label.new()
	_pique.set_anchors_preset(Control.PRESET_CENTER)
	_pique.offset_left = -520.0
	_pique.offset_right = 520.0
	_pique.offset_top = -70.0
	_pique.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pique.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pique.add_theme_font_size_override("font_size", 24)
	_pique.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_pique.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_pique.add_theme_constant_override("outline_size", 6)
	_pique.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_racine.add_child(_pique)


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


## Bouton EXPLOIT. enfoncé ou non (état de l'exploitation automatique).
func set_exploitation(on: bool) -> void:
	if _b_exploit != null and _b_exploit.button_pressed != on:
		_b_exploit.set_pressed_no_signal(on)


## Bouton AUTO enfoncé ou non (sans rappeler main).
func set_auto(on: bool) -> void:
	if _b_auto != null and _b_auto.button_pressed != on:
		_b_auto.set_pressed_no_signal(on)


## Chaussé ou pas : libellés CHAUSSER / DÉCHAUSSER, COURIR / SCHUSS.
func chausse_affiche() -> bool:
	return _chausse


func set_chausse(oui: bool) -> void:
	_chausse = oui
	_maj_carte()
	_b_ski.text = "DÉCHAUSSER" if oui else "CHAUSSER"
	_b_courir.text = "SCHUSS" if oui else "COURIR"
	if not oui:
		_info.text = ""
		_info.visible = false


func _maj_carte() -> void:
	if carte != null:
		carte.visible = (_chausse and not _carte_masquee) or (not _chausse and _carte_a_pied)
	if _b_carte != null:
		_b_carte.visible = true
		_b_carte.set_pressed_no_signal(carte != null and carte.visible)


## Ligne du haut, à ski : vitesse et piste.
func set_info(t: String) -> void:
	if _info != null and _info.text != t:
		_info.text = t
		_info.visible = t != ""        # pas de fond vide


## Message au milieu de l'écran pendant `duree` secondes.
func message(t: String, duree: float = 3.0) -> void:
	if _msg != null:
		_msg.text = t
		_t_msg = duree


## Pique sarcastique, sur sa propre ligne.
func pique(t: String, duree: float = 6.0) -> void:
	if _pique != null:
		_pique.text = t
		_t_pique = duree


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("commandes_skieur", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(delta: float) -> void:
	# poste de remontée : la remontée où l'on est, ou la plus proche (à
	# moins de 400 m d'une gare) ; le pupitre suit quand on en change
	_t_poste -= delta
	if _t_poste <= 0.0 and _b_poste != null and main != null and skieur != null:
		_t_poste = 0.5
		var rm: RemonteesDomaine = main.get("remontees")
		var lg: LigneRemontee = rm.ligne_courante(skieur.global_position) if rm != null else null
		# au Perce-Neige (gare ou rame), pas à bord d'une autre remontée : c'est lui, pas la voisine
		if lg != null and rm.a_bord.is_empty() and bool(main.call("skieur_au_perce_neige")):
			lg = null
		# PC : le pupitre de la fenêtre du simulateur est LE poste (cadrans, pannes au choix, évacuation) ; ce poste-ci
		# faisait doublon (retour d'utilisateur du 24/11/2026) — il reste suivi pour le trajet de la télémesure
		_b_poste.visible = lg != null and not bool(main.get("client_mode"))
		poste.ligne = lg
		# ligne suivie : pannes au hasard, télémesure vers le pupitre du PC
		if lg != ligne_suivie:
			if ligne_suivie != null and is_instance_valid(ligne_suivie):
				ligne_suivie.exploitation().suivie = false
			ligne_suivie = lg
			if lg != null:
				lg.exploitation().suivie = true
		var sur_e: bool = skieur.sur_echelle()
		_b_echelle.visible = sur_e or (rm != null and not skieur.chausse and not skieur.embarque and rm.echelle_proche(skieur.global_position) != null)
		if _b_echelle.visible:
			_b_echelle.text = ("DESCENDRE" if skieur._echelle_auto >= 0.0 or skieur.echelle_en_haut() else "GRIMPER") if sur_e else "GRIMPER"
		# MESURE : décompte pendant le relevé
		var pm2: Node = main.get("perf_manager")
		if pm2 != null and _b_mesure != null:
			var t_m: String = "MESURE…" if bool(pm2.call("releve_en_cours")) else "MESURE"
			if _b_mesure.text != t_m:
				_b_mesure.text = t_m
		_b_corde.visible = rm != null and rm.corde_possible()
		# sur une perche, CHAUSSER devient LÂCHER (lâcher la perche en ligne)
		var perche: bool = rm != null and rm.sur_perche()
		var t_ski: String = "LÂCHER" if perche else ("DÉCHAUSSER" if _chausse else "CHAUSSER")
		if _b_ski.text != t_ski:
			_b_ski.text = t_ski
		if lg == null and poste.visible:
			poste.visible = false
			_b_poste.set_pressed_no_signal(false)
		if poste.visible:
			GlisserPanneau.borner(poste)       # (écran retaillé, plein écran)
		# boutons en double sur le PC (retour d'utilisateur du 19/11/2026) : QUITTER = CONDUIRE de la barre du PC
		if _b_quitter != null and _b_quitter.visible == bool(main.get("client_mode")):
			_b_quitter.visible = not bool(main.get("client_mode"))
	if _t_pique > 0.0:
		_t_pique -= delta
		if _t_pique <= 0.0 and _pique != null:
			_pique.text = ""
	if _t_msg > 0.0:
		_t_msg -= delta
		if _t_msg <= 0.0 and _msg != null:
			_msg.text = ""


## Le bouton ÉVACUER n'apparaît que dans une rame arrêtée en tunnel.
## Bouton VUE LIGNE : nom de la vue en cours, caché hors remontée ("").
func set_vue_ligne(nom: String) -> void:
	if _b_vue_ligne == null:
		return
	var oui: bool = nom != ""
	if _b_vue_ligne.visible != oui:
		_b_vue_ligne.visible = oui
	var t: String = "VUE LIGNE" if nom == "" or nom == "SKIEUR" else nom
	if oui and _b_vue_ligne.text != t:
		_b_vue_ligne.text = t


func set_evacuation_possible(oui: bool) -> void:
	if _b_evac != null and _b_evac.visible != oui:
		_b_evac.visible = oui


## Le bouton CONDUIRE n'apparaît qu'à côté du poste de pilotage.
func set_conduite_possible(oui: bool) -> void:
	if _b_conduire != null and _b_conduire.visible != oui:
		_b_conduire.visible = oui


## Poste montré ou caché : première fois placé en haut à gauche (sur le PC, sous la rangée de boutons de la fenêtre
## du simulateur), borné à l'écran ; le PC en est averti (un seul poste de conduite à la fois).
func _poste_affiche() -> void:
	var pc: bool = main != null and bool(main.get("client_mode"))
	if poste.visible:
		if not poste.has_meta("place"):
			poste.set_meta("place", true)
			poste.position = Vector2(16.0, 72.0 if pc else 140.0)
		(func() -> void: GlisserPanneau.borner(poste)).call_deferred()
	if pc and main.get("state_receiver") != null:
		main.state_receiver.envoyer({"poste_skieur": poste.visible})


## Le PC a déplié son pupitre en surimpression : notre poste se ferme.
func fermer_poste() -> void:
	if poste != null and poste.visible:
		poste.visible = false
		if _b_poste != null:
			_b_poste.set_pressed_no_signal(false)


func _dessiner_joy() -> void:
	var c: Vector2 = Vector2(R_BASE, R_BASE)
	_joy.draw_circle(c, R_BASE, Color(0.10, 0.13, 0.20, 0.35))
	_joy.draw_arc(c, R_BASE, 0.0, TAU, 48, Color(0.55, 0.75, 1.0, 0.7), 3.0)
	_joy.draw_circle(c + _bouton_pos, R_BOUTON, Color(0.55, 0.75, 1.0, 0.55))


func _sur_un_bouton(p: Vector2) -> bool:
	# panneau en plein écran ouvert (RÉSEAU, heure) : tous ses doigts sont pour lui — un doigt sur la moitié gauche
	# faisait naître le joystick et le bouton ou le champ dessous ne recevait rien (21/11/2026 : « impossible de rentrer
	# le code »)
	for c in get_children():
		if c is CanvasLayer and (c.name == "PanneauReseau" or c.name == "ReglageHeure"):
			return true
	# la carte se glisse au doigt : elle ne doit pas tourner la vue en même temps
	if carte != null and carte.is_visible_in_tree() and carte.get_global_rect().has_point(p):
		return true
	# le poste aussi (ses boutons, et on le tire par son fond) : un doigt posé dessus, à gauche, faisait naître le
	# joystick
	if poste != null and poste.is_visible_in_tree() and poste.get_global_rect().has_point(p):
		return true
	for b in _boutons:
		if (b as Button).visible and (b as Button).get_global_rect().has_point(p):
			return true
	return false


## Doigt levé : son emplacement (joystick, vue, pincement) est libéré.
func _lacher(i: int) -> void:
	_doigts.erase(i)
	if skieur != null:
		skieur.doigts = _doigts.size()
	if i == _doigt_joy:
		_doigt_joy = -1
		_bouton_pos = Vector2.ZERO
		if skieur != null:
			skieur.entree = Vector2.ZERO
		if _pos_joy_defaut != Vector2.ZERO:
			_joy.position = _pos_joy_defaut
		_joy.queue_redraw()
	elif i == _doigt_vue:
		_doigt_vue = _doigt_zoom
		_pos_vue = _pos_zoom
		_doigt_zoom = -1
	elif i == _doigt_zoom:
		_doigt_zoom = -1


## Tous les doigts oubliés (commandes masquées : on ne verra pas leur relâché).
func oublier_doigts() -> void:
	for i in _doigts.keys():
		_lacher(int(i))
	for i in [_doigt_joy, _doigt_vue, _doigt_zoom]:
		if i >= 0:
			_lacher(i)
	_doigts.clear()
	if skieur != null:
		skieur.doigts = 0


func _input(event: InputEvent) -> void:
	# (vue figée, retour d'utilisateur du 16/11/2026 : « au bout d'un certain temps impossible d'orienter la vue, elle
	# est restée figée à un angle ») : un doigt levé pendant que les commandes étaient masquées (remontée, carte, vue
	# changée) ou le skieur inactif n'était jamais vu — sa place « vue » restait prise, chaque doigt suivant devenait
	# le second d'un pincement et ne tournait plus la vue, et le skieur ignorait la souris (doigts > 0). Le relâché
	# est donc toujours pris en compte, et un doigt « reposé » sans avoir été levé repart de zéro.
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		if (event as InputEventScreenTouch).index in _doigts or (event as InputEventScreenTouch).index in [_doigt_joy, _doigt_vue, _doigt_zoom]:
			if skieur == null or not skieur.actif or not visible:
				_lacher((event as InputEventScreenTouch).index)
				return
	if skieur == null or not skieur.actif or not visible:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var ir: int = (event as InputEventScreenTouch).index
		if ir in _doigts or ir in [_doigt_joy, _doigt_vue, _doigt_zoom]:
			_lacher(ir)
	if event is InputEventScreenTouch and not _joy.visible:
		_joy.visible = true
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# le skieur ignore la « souris » tant qu'un doigt est posé (iPad :
		# le pouce du joystick arrivait aussi en souris et tournait la vue)
		skieur.tactile_t = Time.get_ticks_msec() / 1000.0
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_doigts[t.index] = true
		skieur.doigts = _doigts.size()
		# comme dans les jeux (retour d'utilisateur, 08/10/2026 : « ça fait tourner la vue
		# en même temps, c'est le bazar ») : joystick FLOTTANT — il naît là
		# où le pouce se pose dans la moitié gauche de l'écran ; tout doigt
		# posé sur la moitié droite tourne la vue ; un doigt sur un bouton ne
		# fait ni l'un ni l'autre
		var moitie: float = get_viewport().get_visible_rect().size.x * 0.5
		if t.pressed:
			if _sur_un_bouton(t.position):
				return
			if _doigt_joy < 0 and t.position.x < moitie:
				_doigt_joy = t.index
				if _pos_joy_defaut == Vector2.ZERO:
					_pos_joy_defaut = _joy.position
				var ecran: Vector2 = get_viewport().get_visible_rect().size
				var centre: Vector2 = Vector2(clampf(t.position.x, R_BASE, ecran.x - R_BASE),
					clampf(t.position.y, R_BASE, ecran.y - R_BASE))
				_joy.position = centre - Vector2(R_BASE, R_BASE) - _racine.global_position
				_centre = centre
				_maj_joy(t.position)
				get_viewport().set_input_as_handled()
			elif _doigt_vue < 0:
				_doigt_vue = t.index
				_pos_vue = t.position
			elif _doigt_zoom < 0:
				# deuxième doigt sur la vue : pincer zoome la 3e personne
				_doigt_zoom = t.index
				_pos_zoom = t.position
		else:
			var etait_joy: bool = t.index == _doigt_joy
			_lacher(t.index)
			if etait_joy:
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _doigt_joy:
			_maj_joy(d.position)
			get_viewport().set_input_as_handled()
		elif _doigt_zoom >= 0 and (d.index == _doigt_vue or d.index == _doigt_zoom):
			var avant: float = _pos_vue.distance_to(_pos_zoom)
			if d.index == _doigt_vue:
				_pos_vue = d.position
			else:
				_pos_zoom = d.position
			var apres: float = _pos_vue.distance_to(_pos_zoom)
			if avant > 10.0 and apres > 10.0:
				skieur.zoomer(avant / apres)      # écarter les doigts rapproche
		elif d.index == _doigt_vue:
			skieur.tourner_vue((d.position - _pos_vue) * 1.3)
			_pos_vue = d.position


func _maj_joy(p: Vector2) -> void:
	# la base SUIT le pouce quand il dépasse le cercle (joystick « dynamique »
	# des jeux mobiles) : on ne perd jamais le contrôle en glissant trop loin
	var d: Vector2 = p - _centre
	if d.length() > R_BASE:
		_centre += d - d.limit_length(R_BASE)
		_joy.position = _centre - Vector2(R_BASE, R_BASE) - _racine.global_position
		d = p - _centre
	_bouton_pos = d
	var v: Vector2 = d / R_BASE
	# zone morte de 12 %, puis réponse progressive
	var n: float = v.length()
	if n < 0.12:
		skieur.entree = Vector2.ZERO
	else:
		var k: float = (n - 0.12) / 0.88
		skieur.entree = Vector2(v.x, -v.y) / n * (0.12 + 0.88 * k)
	_joy.queue_redraw()
