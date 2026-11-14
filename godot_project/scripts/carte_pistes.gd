class_name CartePistes
extends Control
## Carte des pistes en surimpression, semi-transparente, comme dans les jeux
## (retour d'utilisateur, 11/10/2026 : « si je chausse, fais-moi une carte du plan
## des pistes avec une opacité pas à 100 %, pour repérer les pistes, leurs
## couleurs, leur nom et leurs tracés autour de moi, avec zoom / dézoom »).
## Nord en haut, centrée sur le skieur (flèche = sa direction) ; gares du
## funiculaire marquées. Zoom : boutons + / −, molette, touches + / −.
## Glisser déplace la carte ; le bouton ◎ la ramène sur le skieur.
## Tracés : © contributeurs OpenStreetMap (ODbL), via PistesDonnees.

const TAILLE: Vector2 = Vector2(340, 340)
const ECHELLE_MIN: float = 0.02          # px par mètre (≈ 17 km sur la carte)
const ECHELLE_MAX: float = 1.6           # ≈ 210 m sur la carte
const NOM_MIN_PX: float = 70.0           # tracé assez long à l'écran pour porter son nom

var domaine: DomaineSkiable = null
var skieur: SkieurJoueur = null
var gares: Array = []                    # [Vector3 gare basse, Vector3 gare haute]
## Tracé réel du funiculaire (x, z tous les 25 m, posé par main.gd) — avant :
## une ligne droite entre les gares (retour d'utilisateur, 12/10/2026) — et les rames
## en direct, lues sur main (cabin, cabin_ghost)
var trace_funi: PackedVector2Array = PackedVector2Array()
var main: Node = null
var echelle: float = 0.18
var _t: float = 0.0
var _police: Font = null
## Décalage du centre de la carte par rapport au skieur, en mètres (glisser).
var decalage: Vector2 = Vector2.ZERO
var _appui: bool = false                 # bouton ou doigt posé sur la carte
var _glisse: bool = false                # le geste en cours est un glissement
var _pos_appui: Vector2 = Vector2.ZERO
const SEUIL_GLISSE: float = 8.0          # px avant qu'un toucher devienne un glissement
var _b_centre: Button = null


func _ready() -> void:
	custom_minimum_size = TAILLE
	size = TAILLE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_police = ThemeDB.fallback_font
	for k in range(2):
		var b: Button = Button.new()
		b.text = "+" if k == 0 else "−"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, 40)
		b.add_theme_font_size_override("font_size", 24)
		b.position = Vector2(TAILLE.x - 46, 6 + 46 * k)
		b.size = Vector2(40, 40)
		b.pressed.connect(zoomer.bind(1.4 if k == 0 else 1.0 / 1.4))
		add_child(b)
	# ramener la carte sur le skieur après l'avoir déplacée
	_b_centre = Button.new()
	_b_centre.text = "◎"
	_b_centre.tooltip_text = "Revenir au skieur"
	_b_centre.focus_mode = Control.FOCUS_NONE
	_b_centre.custom_minimum_size = Vector2(40, 40)
	_b_centre.add_theme_font_size_override("font_size", 22)
	_b_centre.position = Vector2(TAILLE.x - 46, 6 + 46 * 2)
	_b_centre.size = Vector2(40, 40)
	_b_centre.visible = false
	_b_centre.pressed.connect(recentrer)
	add_child(_b_centre)


func recentrer() -> void:
	decalage = Vector2.ZERO
	_b_centre.visible = false
	queue_redraw()


## Centre de la carte, en mètres (x, z monde).
func _centre() -> Vector2:
	if skieur == null:
		return decalage
	return Vector2(skieur.global_position.x, skieur.global_position.z) + decalage


func zoomer(f: float) -> void:
	echelle = clampf(echelle * f, ECHELLE_MIN, ECHELLE_MAX)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	# appui : on attend de savoir si c'est un toucher (« aller à ») ou un
	# glissement (déplacer la carte, retour d'utilisateur, 14/11/2026 : « la carte
	# est bloquée sur le skieur au centre »). Un doigt arrive deux fois (toucher
	# et souris émulée) : le toucher décide de « aller à », la souris émulée ne
	# sert qu'au glissement.
	var doigt: bool = ev is InputEventScreenTouch and ev.index == 0
	var souris: bool = ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT
	if doigt or souris:
		var emulee: bool = souris and ev.device == InputEvent.DEVICE_ID_EMULATION
		if ev.pressed:
			if not (_appui and emulee):
				_appui = true
				_glisse = false
				_pos_appui = ev.position
		elif not emulee and _appui:
			_appui = false
			if not _glisse:
				# « aller à » : un toucher ou un clic sur une remontée dépose le
				# skieur au pied de sa gare aval (retour d'utilisateur, 22/10/2026)
				var lg: LigneRemontee = remontee_sous(ev.position)
				if lg != null and main != null and main.has_method("aller_a_remontee"):
					main.aller_a_remontee(lg)
					recentrer()
			_glisse = false
		accept_event()
		return
	var depl: Vector2 = Vector2.ZERO
	if ev is InputEventMouseMotion and _appui:
		depl = ev.relative
	if depl != Vector2.ZERO:
		if not _glisse and ev.position.distance_to(_pos_appui) > SEUIL_GLISSE:
			_glisse = true
			depl = ev.position - _pos_appui      # le bout de geste avant le seuil
		if _glisse:
			decalage -= depl / echelle
			_b_centre.visible = true
			queue_redraw()
		accept_event()
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomer(1.15)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomer(1.0 / 1.15)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_MIDDLE or ev.button_index == MOUSE_BUTTON_RIGHT:
			recentrer()
			accept_event()
	elif ev is InputEventMagnifyGesture:
		zoomer(ev.factor)
		accept_event()


func _notification(what: int) -> void:
	# la souris quitte la carte bouton tenu : le relâché n'arrivera pas ici
	if what == NOTIFICATION_MOUSE_EXIT and _appui and _glisse:
		_appui = false
		_glisse = false


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("carte_pistes", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		queue_redraw()


## Remontées posées dans le monde : [ligne, aval (x, z), amont (x, z)].
func _remontees() -> Array:
	var out: Array = []
	if main == null:
		return out
	var rm: Node = main.get("remontees")
	if rm == null:
		return out
	for e in rm.get("lignes"):
		var lg: LigneRemontee = e[0]
		var xf: Transform3D = lg.global_transform
		var b: Vector3 = xf * Vector3(0, 0, -lg.longueur_h())
		out.append([lg, Vector2(xf.origin.x, xf.origin.z), Vector2(b.x, b.z)])
	return out


## La remontée sous le point `pos` de la carte (à 18 px près), ou null.
## Plusieurs remontées sous le doigt (gares voisines, téléskis jumeaux, carte
## dézoomée) : un nouveau toucher au même endroit passe à la suivante —
## sinon le petit téléski au pied d'une grande ligne était inaccessible.
var _dernier_toucher: Vector2 = Vector2(-999, -999)
var _rang_toucher: int = 0


func remontee_sous(pos: Vector2) -> LigneRemontee:
	if skieur == null:
		return null
	var c: Vector2 = _centre()
	var o: Vector2 = TAILLE * 0.5
	var cands: Array = []
	for r in _remontees():
		var a: Vector2 = _carte(r[1], c, o)
		var b: Vector2 = _carte(r[2], c, o)
		var d: float = Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
		d = minf(d, a.distance_to(pos) - 6.0)
		if d < 18.0:
			cands.append([d, r[0]])
	if cands.is_empty():
		_dernier_toucher = Vector2(-999, -999)
		return null
	cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	# même endroit : la suivante parmi celles qui sont sous le doigt (à 12 px
	# près de la meilleure)
	var proches: Array = cands.filter(func(x: Array) -> bool: return float(x[0]) < float(cands[0][0]) + 12.0)
	if pos.distance_to(_dernier_toucher) < 12.0 and proches.size() > 1:
		_rang_toucher = (_rang_toucher + 1) % proches.size()
	else:
		_rang_toucher = 0
	_dernier_toucher = pos
	return proches[_rang_toucher][1]


func _carte(q: Vector2, c: Vector2, o: Vector2) -> Vector2:
	return o + (q - c) * echelle


## Tout ce qui ne bouge pas (pistes, remontées, tracé du funiculaire) dans un seul maillage, refait au
## changement de zoom : tracé à la main, chaque trait, cercle ou piste recréait ses tampons graphiques
## à chaque dessin (3 900 tampons créés et détruits par seconde, carte ouverte, essai du 04/11/2026).
var _fond: ArrayMesh = null
var _cle_fond: String = ""
var _noms_pistes: Array = []            # [cadre, nom, milieu (monde), couleur]


func _ajouter_trait(v: PackedVector2Array, cols: PackedColorArray, a: Vector2, b: Vector2, l: float, col: Color) -> void:
	var d: Vector2 = b - a
	if d.length_squared() < 0.0001:
		return
	var n: Vector2 = d.normalized().orthogonal() * l * 0.5
	var e: Vector2 = d.normalized() * l * 0.25       # recouvrement aux coudes
	for q in [a - e + n, b + e + n, b + e - n, a - e + n, b + e - n, a - e - n]:
		v.append(q)
		cols.append(col)


func _ajouter_disque(v: PackedVector2Array, cols: PackedColorArray, c: Vector2, r: float, col: Color) -> void:
	const N: int = 12
	for i in range(N):
		v.append(c)
		v.append(c + Vector2.from_angle(TAU * i / N) * r)
		v.append(c + Vector2.from_angle(TAU * (i + 1) / N) * r)
		for _k in range(3):
			cols.append(col)


## Sommets en pixels de carte, l'origine du monde en (0, 0).
func _refaire_fond(remontees: Array) -> void:
	var v: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	_noms_pistes.clear()
	var l_piste: float = clampf(PistesDonnees.LARGEUR * echelle * 0.35, 2.0, 7.0)
	for k in range(domaine._axes.size()):
		var coul: int = PistesDonnees.PISTES[k][1]
		var col: Color = DomaineSkiable.COULEURS[coul] if coul >= 0 else Color(0.8, 0.8, 0.8)
		col.a = 0.92
		var pts: PackedVector2Array = domaine._axes[k]
		var long_px: float = 0.0
		for i in range(1, pts.size()):
			_ajouter_trait(v, cols, pts[i - 1] * echelle, pts[i] * echelle, l_piste, col)
			long_px += pts[i].distance_to(pts[i - 1]) * echelle
		var nom: String = PistesDonnees.PISTES[k][0]
		if nom != "" and long_px > NOM_MIN_PX and pts.size() >= 2:
			_noms_pistes.append([domaine._cadres[k], nom, pts[pts.size() / 2], col])
	for r in remontees:
		var a: Vector2 = r[1] * echelle
		var b: Vector2 = r[2] * echelle
		_ajouter_trait(v, cols, a, b, 4.5, Color(1, 1, 1, 0.8))
		_ajouter_trait(v, cols, a, b, 2.5, Color(0.08, 0.08, 0.10, 0.95))
		_ajouter_disque(v, cols, a, 6.5, Color(1, 1, 1, 0.95))
		_ajouter_disque(v, cols, a, 5.0, Color(0.78, 0.06, 0.18, 1.0))
		_ajouter_disque(v, cols, b, 3.5, Color(0.08, 0.08, 0.10, 0.95))
	if trace_funi.size() >= 2:
		# en souterrain : tireté noir et jaune le long du vrai tracé
		for i in range(trace_funi.size() - 1):
			_ajouter_trait(v, cols, trace_funi[i] * echelle, trace_funi[i + 1] * echelle, 4.0, Color(0.05, 0.05, 0.05, 0.85))
		for i in range(trace_funi.size() - 1):
			if (i / 2) % 2 == 0:
				_ajouter_trait(v, cols, trace_funi[i] * echelle, trace_funi[i + 1] * echelle, 2.5, Color(1.0, 0.85, 0.1, 0.95))
	var ta: Array = []
	ta.resize(Mesh.ARRAY_MAX)
	ta[Mesh.ARRAY_VERTEX] = v
	ta[Mesh.ARRAY_COLOR] = cols
	_fond = ArrayMesh.new()
	if not v.is_empty():
		_fond.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, TAILLE), Color(0.05, 0.07, 0.10, 0.55))
	HUD.contour(self, Rect2(Vector2.ZERO, TAILLE), Color(1, 1, 1, 0.35), 2.0)
	if domaine == null or skieur == null:
		return
	var p: Vector3 = skieur.global_position
	var c: Vector2 = _centre()
	var o: Vector2 = TAILLE * 0.5
	var demi: Vector2 = TAILLE * 0.5 / echelle
	var vue: Rect2 = Rect2(c - demi, demi * 2.0).grow(PistesDonnees.LARGEUR)
	var remontees: Array = _remontees()
	var cle: String = "%f|%d|%d" % [echelle, remontees.size(), trace_funi.size()]
	if cle != _cle_fond:
		_cle_fond = cle
		_refaire_fond(remontees)
	draw_mesh(_fond, null, Transform2D(0.0, o - c * echelle))
	var noms: Array = []
	for np in _noms_pistes:
		if (np[0] as Rect2).intersects(vue):
			noms.append([np[1], _carte(np[2], c, o), np[3]])
	# un toucher sur une remontée y emmène le skieur
	for r in remontees:
		var a: Vector2 = _carte(r[1], c, o)
		if Rect2(Vector2.ZERO, TAILLE).has_point(a):
			noms.append([(r[0] as LigneRemontee).nom_ligne + " »", a + Vector2(0, -12), Color(1, 1, 1)])
	# gares du funiculaire
	for g in gares:
		var gp: Vector2 = _carte(Vector2((g as Vector3).x, (g as Vector3).z), c, o)
		draw_rect(Rect2(gp - Vector2(6, 6), Vector2(12, 12)), Color(1.0, 0.85, 0.1, 0.95))
		HUD.contour(self, Rect2(gp - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.9), 1.5)
	if trace_funi.size() < 2 and gares.size() == 2:
		var a: Vector2 = _carte(Vector2(gares[0].x, gares[0].z), c, o)
		var b: Vector2 = _carte(Vector2(gares[1].x, gares[1].z), c, o)
		var t: float = 0.0
		var lg_t: float = a.distance_to(b)
		while t < lg_t:
			HUD.segment(self, a.lerp(b, t / maxf(lg_t, 1.0)), a.lerp(b, minf(t + 8.0, lg_t) / maxf(lg_t, 1.0)), Color(1.0, 0.85, 0.1, 0.8), 2.0)
			t += 16.0
	# les deux rames, en direct
	if main != null:
		for r in [[main.get("cabin"), "1"], [main.get("cabin_ghost"), "2"]]:
			var cab: Node3D = r[0]
			if cab == null:
				continue
			var num: String = str((cab as Cabin).train_number) if cab is Cabin else r[1]
			var gp: Vector3 = cab.global_position
			var rp: Vector2 = _carte(Vector2(gp.x, gp.z), c, o)
			if not Rect2(Vector2.ZERO, TAILLE).grow(-4.0).has_point(rp):
				continue
			HUD.disque(self, rp, 7.5, Color(0.0, 0.0, 0.0, 0.9))
			HUD.disque(self, rp, 6.0, Color(1.0, 0.85, 0.1, 1.0))
			draw_string(_police, rp + Vector2(-3.5, 4.5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0))
	# noms par-dessus les tracés
	for n in noms:
		var pos: Vector2 = n[1]
		if not Rect2(Vector2.ZERO, TAILLE).has_point(pos):
			continue
		draw_string_outline(_police, pos + Vector2(4, -4), n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4,
			Color(0, 0, 0, 0.85))
		draw_string(_police, pos + Vector2(4, -4), n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
	# le skieur : flèche dans sa direction (avant = −z local), à sa place sur
	# la carte déplacée ; hors cadre, un repère sur le bord montre où il est
	var cap: float = skieur._visuel.global_rotation.y if skieur.get("_visuel") != null else 0.0
	var av: Vector2 = Vector2(-sin(cap), -cos(cap))
	var dr: Vector2 = Vector2(-av.y, av.x)
	var ps: Vector2 = _carte(Vector2(p.x, p.z), c, o)
	var cadre: Rect2 = Rect2(Vector2.ZERO, TAILLE).grow(-12.0)
	if cadre.has_point(ps):
		var fl: PackedVector2Array = PackedVector2Array([ps + av * 11.0, ps - av * 7.0 + dr * 7.0,
			ps - av * 3.0, ps - av * 7.0 - dr * 7.0])
		draw_colored_polygon(fl, Color(1.0, 0.25, 0.15, 1.0))
		for i in range(4):
			HUD.segment(self, fl[i], fl[(i + 1) % 4], Color(1, 1, 1), 1.5)
	else:
		var u: Vector2 = (ps - o).normalized()
		var k: float = minf(absf(cadre.size.x * 0.5 / maxf(absf(u.x), 1e-4)),
			absf(cadre.size.y * 0.5 / maxf(absf(u.y), 1e-4)))
		var q: Vector2 = o + u * k
		var n: Vector2 = Vector2(-u.y, u.x)
		var tri: PackedVector2Array = PackedVector2Array([q + u * 8.0, q - u * 6.0 + n * 7.0, q - u * 6.0 - n * 7.0])
		draw_colored_polygon(tri, Color(1.0, 0.25, 0.15, 1.0))
		for i in range(3):
			HUD.segment(self, tri[i], tri[(i + 1) % 3], Color(1, 1, 1), 1.5)
	# échelle
	var m: float = 100.0
	for cand in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		m = cand
		if cand * echelle > 60.0:
			break
	var y: float = TAILLE.y - 12.0
	HUD.segment(self, Vector2(10, y), Vector2(10 + m * echelle, y), Color(1, 1, 1, 0.9), 2.0)
	draw_string(_police, Vector2(10, y - 5), ("%d m" % m) if m < 1000.0 else ("%d km" % int(m / 1000.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
	draw_string(_police, Vector2(TAILLE.x * 0.5 - 4, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
