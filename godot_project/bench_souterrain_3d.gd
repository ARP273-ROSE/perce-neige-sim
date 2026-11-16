# Banc du souterrain caché vu des pistes (16/11/2026) : dehors, loin des deux gares du Perce-Neige, rames et
# tube du tunnel ne sont plus dessinés (rien n'en paraît au-delà de 35 m) ; aux abords d'une gare, tout reste là.
#   godot --headless --fixed-fps 60 --path godot_project -s bench_souterrain_3d.gd
extends SceneTree

var _main: Node
var _f: int = 0
var _etat: int = 0
var _att: int = 0
var _ok: bool = true
var _cas: Array = []      # [nom, sg, distance, rames et tunnel attendus visibles]
var _i: int = 0


func _check(nom: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", nom, detail])
	_ok = _ok and cond


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _main.get("relief") == null or not _main.relief.pret or _f < 30:
		if _f > 20000:
			_check("chargement", false, "relief jamais prêt")
			quit(1)
		return
	match _etat:
		0:
			_main.basculer_skieur()
			_etat = 1
		1:
			if _main.skieur == null or not _main.skieur.actif:
				return
			_cas = [["gare aval à 20 m", 0.0, 20.0, true], ["gare aval à 100 m", 0.0, 100.0, false],
				["gare amont à 20 m", PNConstants.LENGTH, 20.0, true], ["gare amont à 100 m", PNConstants.LENGTH, 100.0, false],
				["à 400 m des gares", 0.0, 400.0, false]]
			_etat = 2
		2:
			if _i >= _cas.size():
				print("BILAN %s" % ("OK" if _ok else "ÉCHEC"))
				quit(0 if _ok else 1)
				return
			var c: Array = _cas[_i]
			if _att == 0:
				var g: Vector3 = _main.tunnel.transform_at(c[1]).origin
				var g2: Vector3 = _main.tunnel.transform_at(c[1] + (60.0 if c[1] == 0.0 else -60.0)).origin
				# du côté opposé au tunnel : dehors, devant l'entrée
				var sortie: Vector3 = Vector3(g.x - g2.x, 0.0, g.z - g2.z).normalized()
				var q: Vector3 = g + sortie * float(c[2])
				q.y = _main.relief.hauteur_sol(q.x, q.z) + 0.1
				_main.remontees.quitter()
				_main.collisions.assurer_autour(q)
				_main.skieur.activer(q, atan2(sortie.x, sortie.z))
				_main.skieur.support = null
				_main.skieur.refuge = q
				_main.skieur.dernier_sol = q
			_att += 1
			if _att < 90:
				return
			var cam: Camera3D = get_root().get_camera_3d()
			var dehors: bool = cam != null and cam.global_position.y > _main.relief.hauteur_sol(cam.global_position.x, cam.global_position.z) - 1.0
			var vis: Array = [_main.cabin.visible, _main.cabin_ghost.visible, _main.tunnel.visible]
			var attendu: bool = c[3]
			# aux abords : chaque rame reste dessinée à moins de 150 m de la caméra (règle d'avant)
			var att: Array = [attendu and cam.global_position.distance_to(_main.cabin.global_position) <= 150.0,
				attendu and cam.global_position.distance_to(_main.cabin_ghost.global_position) <= 150.0, attendu]
			_check(c[0], dehors and vis == att,
				"caméra dehors %s ; rame, rame fantôme, tunnel visibles : %s (attendu %s)" % [dehors, vis, att])
			_i += 1
			_att = 0
