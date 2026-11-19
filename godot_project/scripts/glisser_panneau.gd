class_name GlisserPanneau
extends RefCounted
## Panneau déplaçable (retour d'utilisateur du 19/11/2026, PC en plein écran : « les fenêtres je peux pas les
## déplacer ») : on le tire par son fond ou son titre, à la souris ou au doigt (souris émulée du toucher, comme la
## carte des pistes) ; les boutons du panneau gardent leurs clics. Le panneau reste dans l'écran, et rétrécit
## (échelle) s'il est plus haut que l'écran.

const SEUIL: float = 6.0


static func activer(p: Control) -> void:
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void: _evenement(p, ev))
	p.resized.connect(func() -> void: borner(p))


## Pointeur de l'événement dans le repère du parent du panneau (le panneau peut être réduit par son échelle).
static func _dans_parent(p: Control, pos_locale: Vector2) -> Vector2:
	var parent: CanvasItem = p.get_parent() as CanvasItem
	var g: Vector2 = p.get_global_transform() * pos_locale
	return parent.get_global_transform().affine_inverse() * g if parent != null else g


static func _evenement(p: Control, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = ev
		if mb.pressed:
			p.set_meta("_glisser", [_dans_parent(p, mb.position), p.position, false])
		else:
			p.remove_meta("_glisser")
		p.accept_event()
	elif ev is InputEventMouseMotion and p.has_meta("_glisser"):
		var g: Array = p.get_meta("_glisser")
		var ici: Vector2 = _dans_parent(p, (ev as InputEventMouseMotion).position)
		var d: Vector2 = ici - (g[0] as Vector2)
		if not bool(g[2]) and d.length() > SEUIL:
			g[2] = true
		if bool(g[2]):
			p.position = (g[1] as Vector2) + d
			borner(p)
		p.accept_event()


## Échelle (s'il est plus haut que l'écran) et position bornées à l'écran (le parent couvre l'écran).
static func borner(p: Control) -> void:
	var parent: Control = p.get_parent() as Control
	var ecran: Vector2 = parent.size if parent != null else p.get_viewport_rect().size
	if ecran.x <= 0.0 or ecran.y <= 0.0 or p.size.y <= 0.0:
		return
	var k: float = clampf(minf((ecran.y - 16.0) / p.size.y, (ecran.x - 16.0) / p.size.x), 0.4, 1.0)
	if absf(p.scale.x - k) > 0.001:
		p.scale = Vector2(k, k)
	var t: Vector2 = p.size * k
	var x: float = clampf(p.position.x, 0.0, maxf(ecran.x - t.x, 0.0))
	var y: float = clampf(p.position.y, 0.0, maxf(ecran.y - t.y, 0.0))
	if x != p.position.x or y != p.position.y:
		p.position = Vector2(x, y)
