## Contre un simple mur de gare, à pied, avec de vraies touches : il bute ou il glisse, mais ne
## se retrouve jamais ailleurs en une image (sur le toit d'une gare, 6 m plus haut, en 11/2026).
## Les murs sont trouvés au rayon depuis le quai ; le filet ne doit pas se déclencher.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_mur_3d.gd
extends SceneTree

const SAUT_MAX: float = 1.3      # rebord hissé hors des gares : GRIMPE_MAX, 1,25 m

var _main: Node = null
var _ok: bool = true
var _essais: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_suite()


func _touche(k: int, on: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = on
	Input.parse_input_event(e)


func _attend(n: int) -> void:
	for i in n:
		await process_frame


func _essai(sk: SkieurJoueur, nom: String, dep: Vector3, cap: float) -> void:
	if sk.chausse:
		sk.basculer_ski(true)
	sk.global_position = dep
	sk.velocity = Vector3.ZERO
	await _attend(40)
	sk.cam_yaw = cap
	var prec: Vector3 = sk.global_position
	var saut: float = 0.0
	var d0: int = sk.degagements
	_touche(KEY_W, true)
	for i in 300:
		await process_frame
		sk.cam_yaw = cap
		saut = maxf(saut, sk.global_position.distance_to(prec))
		prec = sk.global_position
	_touche(KEY_W, false)
	_essais += 1
	var bon: bool = saut <= SAUT_MAX and sk.degagements == d0
	_ok = _ok and bon
	print("%s %s cap %d : plus grand saut %.2f m, filet %d" % ["[OK]  " if bon else "[ECHEC]", nom, int(rad_to_deg(cap)), saut, sk.degagements - d0])


func _suite() -> void:
	while _main.relief == null or not _main.relief.pret:
		await process_frame
	await _attend(120)
	_main.basculer_skieur()
	while _main.get("skieur") == null:
		await process_frame
	await _attend(120)
	var sk: SkieurJoueur = _main.skieur
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if not String(lg.name) in ["tsd6_leissieres", "tcd10_toviere", "tsf4_grand_huit"]:
			continue
		_main.aller_a_remontee(lg)
		var n: int = 0
		while not lg.pret and n < 7200:
			await process_frame
			n += 1
		for aval in [true, false]:
			var q: Vector3 = lg.global_transform * lg.point_embarquement(aval) + Vector3.UP * 0.3
			sk.global_position = q
			sk.velocity = Vector3.ZERO
			await _attend(120)
			var esp: PhysicsDirectSpaceState3D = sk.get_world_3d().direct_space_state
			for k in 24:
				var a: float = TAU * k / 24.0
				var dir: Vector3 = Vector3(sin(a), 0, cos(a))
				var o: Vector3 = q + Vector3.UP * 1.2
				var h: Dictionary = esp.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + dir * 30.0, sk.collision_mask, [sk.get_rid()]))
				if not h or absf(h.normal.y) > 0.3 or h.position.distance_to(o) < 3.0:
					continue
				var dep: Vector3 = h.position - dir * 2.5
				var bas: Dictionary = esp.intersect_ray(PhysicsRayQueryParameters3D.create(dep + Vector3.UP * 3.0, dep + Vector3.DOWN * 60.0, sk.collision_mask, [sk.get_rid()]))
				if not bas or absf(bas.position.y - q.y) > 4.0:
					continue
				dep.y = bas.position.y + 0.2
				await _essai(sk, String(lg.name) + (" aval" if aval else " amont"), dep, atan2(-dir.x, -dir.z))
	if _essais < 3:
		_ok = false
		print("[ECHEC] seulement %d murs trouvés" % _essais)
	print("%d murs essayés" % _essais)
	print("BENCH_MUR " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
