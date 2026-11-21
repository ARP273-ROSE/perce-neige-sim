## Banc de la carte bornée au domaine (retour d'utilisateur du 21/11/2026 : « la carte ne doit pas pouvoir être
## déplacée ni dézoomée au-delà du périmètre du domaine ») : dézoom arrêté quand l'emprise des remontées remplit la
## carte, glissement (souris ou doigt) ramené dans l'emprise, toutes les remontées dans l'emprise.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_carte_bornee_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _glisser(c: CartePistes, depl: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = CartePistes.TAILLE * 0.5
	c._gui_input(ev)
	var m := InputEventMouseMotion.new()
	m.position = ev.position + depl
	m.relative = depl
	c._gui_input(m)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = m.position
	c._gui_input(up)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur or _main.remontees == null or not _main.remontees.pret:
		return
	var c: CartePistes = _main.commandes_skieur.carte
	var e: Rect2 = c.emprise()
	var dedans: bool = true
	for r in c._remontees():
		dedans = dedans and e.has_point(r[1]) and e.has_point(r[2])
	_verif("toutes les remontées dans l'emprise", dedans, "%.1f × %.1f km" % [e.size.x / 1000.0, e.size.y / 1000.0])
	for k in range(40):
		c.zoomer(1.0 / 1.4)
	var vue: Vector2 = CartePistes.TAILLE / c.echelle
	_verif("dézoom arrêté à l'emprise", vue.x <= e.size.x + 1.0 and vue.y <= e.size.y + 1.0 and (vue.x >= e.size.x - 1.0 or vue.y >= e.size.y - 1.0),
		"vue %.0f × %.0f m pour %.0f × %.0f m" % [vue.x, vue.y, e.size.x, e.size.y])
	for k2 in range(6):
		c.zoomer(1.4)
	for d in [Vector2(5000, 0), Vector2(-9000, 0), Vector2(0, 7000), Vector2(0, -9000)]:
		for k3 in range(10):
			_glisser(c, d / 10.0)
		var demi: Vector2 = CartePistes.TAILLE * 0.5 / c.echelle
		var cc: Vector2 = c._centre()
		var vr: Rect2 = Rect2(cc - demi, demi * 2.0)
		_verif("glissement %s : la vue reste dans le domaine" % str(d), e.grow(1.0).encloses(vr),
			"vue %s, emprise %s" % [str(vr), str(e)])
	print("BENCH_CARTE_BORNEE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
	_f = -1000000
