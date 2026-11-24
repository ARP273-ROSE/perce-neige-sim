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
var _b_auto: Button
var _b_secours: Button
var _b_remise: Button
var _b_reparer: Button
var _b_portes: Button
var _panne: Label
var _journal: Label
var _trajet: Label
var _d_prec: float = NAN
var _descend: bool = false
var _long_cache: Dictionary = {}     # [ligne, montée] → abscisses et longueurs cumulées le long du câble


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
	_trajet = _texte(col, 18, Color(1.0, 0.92, 0.55), true)
	# référence de vitesse
	var l_c: HBoxContainer = HBoxContainer.new()
	l_c.add_theme_constant_override("separation", 8)
	col.add_child(l_c)
	for k in range(LigneRemontee.CRANS.size()):
		var b: Button = _bouton(l_c, LigneRemontee.NOMS_CRANS[k], Color(0.20, 0.45, 0.75))
		b.toggle_mode = true
		var kk: int = k
		b.pressed.connect(func() -> void:
			_cmd("cran", kk))
		_crans.append(b)
	# marche / arrêt
	var l_m: HBoxContainer = HBoxContainer.new()
	l_m.add_theme_constant_override("separation", 8)
	col.add_child(l_m)
	_bouton(l_m, "DÉMARRER", Color(0.15, 0.55, 0.25)).pressed.connect(func() -> void:
		_cmd("demarrer"))
	_bouton(l_m, "ARRÊT", Color(0.75, 0.50, 0.05)).pressed.connect(func() -> void:
		_cmd("arreter"))
	var l_u: HBoxContainer = HBoxContainer.new()
	l_u.add_theme_constant_override("separation", 8)
	col.add_child(l_u)
	var b_u: Button = _bouton(l_u, "ARRÊT D'URGENCE", Color(0.80, 0.08, 0.08))
	b_u.custom_minimum_size = Vector2(240, 64)
	b_u.pressed.connect(func() -> void:
		_cmd("urgence"))
	_b_rearmer = _bouton(l_u, "RÉARMER", Color(0.35, 0.35, 0.40))
	_b_rearmer.pressed.connect(func() -> void:
		_cmd("rearmer"))
	# exploitation : auto / manuel, panne au hasard, secours, remise en service (15/11/2026)
	var l_e: HBoxContainer = HBoxContainer.new()
	l_e.add_theme_constant_override("separation", 8)
	col.add_child(l_e)
	_b_auto = _bouton(l_e, "AUTO", Color(0.20, 0.45, 0.75))
	_b_auto.toggle_mode = true
	_b_auto.pressed.connect(func() -> void:
		_cmd("mode", "auto" if _b_auto.button_pressed else "manuel"))
	_bouton(l_e, "PANNE", Color(0.55, 0.30, 0.05)).pressed.connect(func() -> void:
		_cmd("panne_hasard"))
	_b_secours = _bouton(l_e, "SECOURS", Color(0.45, 0.35, 0.10))
	_b_secours.pressed.connect(func() -> void:
		_cmd("secours"))
	_b_remise = _bouton(l_e, "REMISE EN SERVICE", Color(0.15, 0.40, 0.30))
	_b_remise.pressed.connect(func() -> void:
		_cmd("remise_service"))
	# un seul bouton pour tout solder et repartir (« c'est la galère pour réarmer les pannes », 16/11/2026)
	_b_reparer = _bouton(col, "TOUT RÉPARER ET REPARTIR", Color(0.10, 0.50, 0.25))
	_b_reparer.custom_minimum_size = Vector2(240, 64)
	_b_reparer.pressed.connect(func() -> void:
		_cmd("depanner"))
	# portes à la main (téléphériques, Funival : à quai, en manuel)
	_b_portes = _bouton(l_e, "PORTES", Color(0.25, 0.35, 0.55))
	_b_portes.pressed.connect(func() -> void:
		if ligne != null and is_instance_valid(ligne) and ligne.has_method("ouverture_portes"):
			_cmd("portes", "fermer" if float(ligne.call("ouverture_portes")) > 0.5 else "ouvrir"))
	_panne = _texte(col, 15, Color(1.0, 0.80, 0.55), true)
	_journal = _texte(col, 14, Color(0.75, 0.82, 0.92), true)


func _cmd(nom: String, arg: Variant = null) -> void:
	if ligne != null and is_instance_valid(ligne):
		ligne.exploitation().commande(nom, arg)


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


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("poste_remontee", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(_delta: float) -> void:
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
	_trajet.text = _texte_trajet()
	_freins.text = "Frein de service : %s · Frein de poulie : %s" % ["SERRÉ" if fs or ligne.etat == "arret_normal" else "desserré",
		"SERRÉ" if fp else "desserré"]
	for k in range(_crans.size()):
		(_crans[k] as Button).set_pressed_no_signal(k == ligne.cran)
	_b_rearmer.disabled = not (ligne.etat == "urgence" and v <= 0.0)
	var ex: ExploitationRemontee = ligne.exploitation()
	_b_auto.set_pressed_no_signal(ex.mode == "auto")
	_b_auto.text = "AUTO" if ex.mode == "auto" else "MANUEL"
	_b_secours.visible = _a_coupure(ex) and not ex.secours
	_b_remise.visible = ex.hors_service()
	_b_reparer.visible = not ex.pannes.is_empty() or (ex.mode == "manuel" and ligne.etat != "marche")
	_b_reparer.text = "TOUT RÉPARER ET REPARTIR" if not ex.pannes.is_empty() else "REPARTIR EN AUTO"
	_b_portes.visible = ligne.has_method("ouverture_portes")
	if _b_portes.visible:
		_b_portes.text = "FERMER PORTES" if float(ligne.call("ouverture_portes")) > 0.5 else "OUVRIR PORTES"
	var t_p: String = ""
	for p in ex.pannes:
		var dp: Dictionary = PannesRemontees.P.get(p["id"], {})
		if dp.is_empty():
			continue
		t_p += "⚠ %s — %s\n%s\n" % [ex._tr(dp["nom"]), ex._tr(PannesRemontees.LIBELLES_GRAVITE[dp["grav"]]), ex._tr(dp["faire"])]
		var rs: float = ex._reste(p)
		if ex.mode == "auto" and rs > 0.0:
			t_p += "   (auto : réglé dans %d s)\n" % ceili(rs)
	if ex.secours:
		t_p += "Moteur de secours : 30 %\n"
	_panne.text = t_p.strip_edges()
	_panne.visible = t_p != ""
	_journal.text = String(ex._evts[-1][3]) if not ex._evts.is_empty() else ""


func _a_coupure(ex: ExploitationRemontee) -> bool:
	for p in ex.pannes:
		if PannesRemontees.P.get(p["id"], {}).get("secours", false) and not p["resolue"]:
			return true
	return false


## Trajet pour la télémesure du PC (son pupitre remplace ce poste) : "" sans ligne.
func texte_trajet() -> String:
	return _texte_trajet() if ligne != null and is_instance_valid(ligne) else ""


## Distance parcourue et restante sur la remontée, le long du câble, d'après notre position (demande d'utilisateur du
## 19/11/2026) : à bord, celle du véhicule ; à pied ou à ski, le skieur projeté sur l'axe de la ligne.
func _texte_trajet() -> String:
	var dom: Node = ligne.get_parent()
	var sk: Node3D = dom.get("skieur") if dom != null else null
	var L: float = ligne.longueur_h()
	if L < 1.0:
		return ""
	var d: float = NAN
	var montee: bool = true
	var ab: Array = dom.get("a_bord") if dom != null else []
	if not ab.is_empty() and ab[0] == ligne and int(ab[1]) < ligne.nombre_vehicules():
		if ligne.vaetvient():
			# (va-et-vient : abscisse du véhicule = d ; le sens, d'après son déplacement)
			d = float(ligne._vehicules[int(ab[1])][1])
			if not is_nan(_d_prec) and absf(d - _d_prec) > 0.01:
				_descend = d < _d_prec
			_d_prec = d
			montee = not _descend
		else:
			var p: Vector3 = ligne.point(float(ligne._vehicules[int(ab[1])][1]))[0]
			d = -p.z
			montee = signf(p.x) == signf(ligne._x_brin(true))
	elif sk != null:
		var q: Vector3 = ligne.to_local(sk.global_position)
		if absf(q.x) > 60.0 or -q.z < -60.0 or -q.z > L + 60.0:
			return "Trajet : %s le long du câble" % _m(_longueur(true, L))
		d = -q.z
	if is_nan(d) or not is_finite(d):
		return ""
	d = clampf(d, 0.0, L)
	var brin: bool = true if ligne.vaetvient() else montee
	var fait: float = _longueur(brin, d)
	var tout: float = _longueur(brin, L)
	if not montee:
		fait = tout - fait
	return "Parcouru %s · reste %s (sur %s)" % [_m(fait), _m(maxf(tout - fait, 0.0)), _m(tout)]


func _m(x: float) -> String:
	return ("%d m" % roundi(x)) if x < 1000.0 else ("%.2f km" % (x / 1000.0)).replace(".", ",")


## Longueur de câble de la gare aval jusqu'à l'abscisse horizontale d (brin montant ou descendant), par pas de 5 m.
func _longueur(montee: bool, d: float) -> float:
	var cle: String = "%d|%s" % [ligne.get_instance_id(), montee]
	if not _long_cache.has(cle):
		var L: float = ligne.longueur_h()
		var cum: PackedFloat32Array = PackedFloat32Array([0.0])
		var y0: float = ligne.y_cable(0.0, montee)
		var x: float = 0.0
		while x < L:
			var x1: float = minf(x + 5.0, L)
			var y1: float = ligne.y_cable(x1, montee)
			cum.append(cum[cum.size() - 1] + Vector2(x1 - x, y1 - y0).length())
			x = x1
			y0 = y1
		_long_cache[cle] = cum
	var c: PackedFloat32Array = _long_cache[cle]
	var f: float = clampf(d / 5.0, 0.0, float(c.size() - 1))
	var i: int = mini(int(f), c.size() - 2)
	return lerpf(c[i], c[i + 1], f - i) if c.size() > 1 else 0.0
