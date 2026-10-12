class_name CartePistes
extends Control
## Carte des pistes en surimpression, semi-transparente, comme dans les jeux
## (retour d'utilisateur, 11/10/2026 : « si je chausse, fais-moi une carte du plan
## des pistes avec une opacité pas à 100 %, pour repérer les pistes, leurs
## couleurs, leur nom et leurs tracés autour de moi, avec zoom / dézoom »).
## Nord en haut, centrée sur le skieur (flèche = sa direction) ; gares du
## funiculaire marquées. Zoom : boutons + / −, molette, touches + / −.
## Tracés : © contributeurs OpenStreetMap (ODbL), via PistesDonnees.

const TAILLE: Vector2 = Vector2(340, 340)
const ECHELLE_MIN: float = 0.02          # px par mètre (≈ 17 km sur la carte)
const ECHELLE_MAX: float = 1.6           # ≈ 210 m sur la carte
const NOM_MIN_PX: float = 70.0           # tracé assez long à l'écran pour porter son nom

var domaine: DomaineSkiable = null
var skieur: SkieurJoueur = null
var gares: Array = []                    # [Vector3 gare basse, Vector3 gare haute]
var echelle: float = 0.18
var _t: float = 0.0
var _police: Font = null


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


func zoomer(f: float) -> void:
	echelle = clampf(echelle * f, ECHELLE_MIN, ECHELLE_MAX)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomer(1.15)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomer(1.0 / 1.15)
			accept_event()
	elif ev is InputEventMagnifyGesture:
		zoomer(ev.factor)
		accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		queue_redraw()


func _carte(q: Vector2, c: Vector2, o: Vector2) -> Vector2:
	return o + (q - c) * echelle


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, TAILLE), Color(0.05, 0.07, 0.10, 0.55))
	draw_rect(Rect2(Vector2.ZERO, TAILLE), Color(1, 1, 1, 0.35), false, 2.0)
	if domaine == null or skieur == null:
		return
	var p: Vector3 = skieur.global_position
	var c: Vector2 = Vector2(p.x, p.z)
	var o: Vector2 = TAILLE * 0.5
	var demi: Vector2 = TAILLE * 0.5 / echelle
	var vue: Rect2 = Rect2(c - demi, demi * 2.0).grow(PistesDonnees.LARGEUR)
	var noms: Array = []
	for k in range(domaine._axes.size()):
		if not (domaine._cadres[k] as Rect2).intersects(vue):
			continue
		var coul: int = PistesDonnees.PISTES[k][1]
		var col: Color = DomaineSkiable.COULEURS[coul] if coul >= 0 else Color(0.8, 0.8, 0.8)
		col.a = 0.92
		var pts: PackedVector2Array = domaine._axes[k]
		var ecran: PackedVector2Array = PackedVector2Array()
		var long_px: float = 0.0
		for i in range(pts.size()):
			ecran.append(_carte(pts[i], c, o))
			if i > 0:
				long_px += ecran[i].distance_to(ecran[i - 1])
		if ecran.size() >= 2:
			draw_polyline(ecran, col, clampf(PistesDonnees.LARGEUR * echelle * 0.35, 2.0, 7.0), true)
		var nom: String = PistesDonnees.PISTES[k][0]
		if nom != "" and long_px > NOM_MIN_PX:
			noms.append([nom, ecran[ecran.size() / 2], col])
	# gares du funiculaire
	for g in gares:
		var gp: Vector2 = _carte(Vector2((g as Vector3).x, (g as Vector3).z), c, o)
		draw_rect(Rect2(gp - Vector2(6, 6), Vector2(12, 12)), Color(1.0, 0.85, 0.1, 0.95))
		draw_rect(Rect2(gp - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.9), false, 1.5)
	if gares.size() == 2:
		var a: Vector2 = _carte(Vector2(gares[0].x, gares[0].z), c, o)
		var b: Vector2 = _carte(Vector2(gares[1].x, gares[1].z), c, o)
		draw_dashed_line(a, b, Color(1.0, 0.85, 0.1, 0.8), 2.0, 8.0)
	# noms par-dessus les tracés
	for n in noms:
		var pos: Vector2 = n[1]
		if not Rect2(Vector2.ZERO, TAILLE).has_point(pos):
			continue
		draw_string_outline(_police, pos + Vector2(4, -4), n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4,
			Color(0, 0, 0, 0.85))
		draw_string(_police, pos + Vector2(4, -4), n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
	# le skieur : flèche dans sa direction (avant = −z local)
	var cap: float = skieur._visuel.global_rotation.y if skieur.get("_visuel") != null else 0.0
	var av: Vector2 = Vector2(-sin(cap), -cos(cap))
	var dr: Vector2 = Vector2(-av.y, av.x)
	var fl: PackedVector2Array = PackedVector2Array([o + av * 11.0, o - av * 7.0 + dr * 7.0,
		o - av * 3.0, o - av * 7.0 - dr * 7.0])
	draw_colored_polygon(fl, Color(1.0, 0.25, 0.15, 1.0))
	draw_polyline(fl + PackedVector2Array([fl[0]]), Color(1, 1, 1), 1.5, true)
	# échelle
	var m: float = 100.0
	for cand in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]:
		m = cand
		if cand * echelle > 60.0:
			break
	var y: float = TAILLE.y - 12.0
	draw_line(Vector2(10, y), Vector2(10 + m * echelle, y), Color(1, 1, 1, 0.9), 2.0)
	draw_string(_police, Vector2(10, y - 5), ("%d m" % m) if m < 1000.0 else ("%d km" % int(m / 1000.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))
	draw_string(_police, Vector2(TAILLE.x * 0.5 - 4, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
