## Banc : à pied au col au nord de la piste du Montet (vers les gorges du Malpasset), configuration de la PWA (GDScript,
## maille à 50 m, fenêtre fine de 800 m), à 20 images/s, collisions à la demande étalées comme en jeu.
## Retour d'essai du 21/11/2026 (tablette) : à pied au col, le joueur « passe au travers » et finit téléporté.
## Cause : le sol de collision, posé sous le sol à 50 m, n'était pas refait quand la fenêtre fine arrivait — jusqu'à
## 37 m sous la neige affichée. Scénario : collisions du col posées fenêtre ailleurs, joueur déchaussé au col, la
## fenêtre arrive pendant qu'il marche. Échec : saut de plus de 5 m (rattrapage), pieds à plus de 1 m sous le sol
## affiché pendant plus de 0,5 s, plus de 1,5 s sans sol, ou sol de collision à plus de 0,7 m du sol affiché
## (rayons au pas de 5 m, 150 m autour du joueur) une fois la fenêtre posée.
##   godot --headless --fixed-fps 20 --path godot_project -s bench_col_malpasset_3d.gd
extends SceneTree

const COL: Vector2 = Vector2(12060.0, 2850.0)
const CHEMIN: Array = [Vector2(12010, 2720), Vector2(11960, 2600), Vector2(11910, 2470)]
const DUREE: float = 45.0

var _main: Node = null
var _f: int = 0
var _phase: String = "lancer"
var _t: float = 0.0
var _k: int = 0
var _prec: Vector3
var _sauts: int = 0
var _sous_t: float = 0.0
var _sous_max: float = 0.0
var _air: float = 0.0
var _air_max: float = 0.0
var _ecart_max: float = 0.0
var _vides: int = 0
var _fenetre_t: float = -1.0
var _refaits0: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not "--sans-noyau-decor" in args or not "--cran=6" in args:
		# relancé dans la configuration de la PWA (les options du banc sont lues au démarrage du jeu)
		var a: Array = ["--headless", "--fixed-fps", "20", "--path", ProjectSettings.globalize_path("res://"), "-s",
			"bench_col_malpasset_3d.gd", "--", "--sans-noyau-decor", "--cran=6", "--relief-fenetre=800"]
		var sortie: Array = []
		var code: int = OS.execute(OS.get_executable_path(), a, sortie, true)
		for l in String(sortie[0]).split("\n"):
			if l.begins_with("COL") or l.begins_with("BANC"):
				print(l)
		quit(code)
		return
	LigneRemontee.construction_en_fond = false
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	physics_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	var pm: Node = _main.get("perf_manager")
	if pm != null and not bool(pm.get("banc")):
		pm.set("banc", true)
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if not _main.mode_skieur:
		_main.basculer_skieur()
		return
	var sk: SkieurJoueur = _main.skieur
	var col: CollisionsJeu = _main.get("collisions")
	if col == null or not col.pret:
		return
	match _phase:
		"lancer":
			_k += 1
			if _k < 120:
				return
			# fenêtre fine loin d'ici : le col garde le sol à 50 m, et ses collisions sont posées dessus
			ReliefBuilder.cible_fenetre = Vector3(0, 0, 0)
			# (collisions du col posées tout de suite, comme après la descente à ski depuis le Montet)
			col.assurer_autour(Vector3(COL.x, relief.hauteur_sol(COL.x, COL.y), COL.y))
			col.synchrone_sans_ecran = false
			col.budget_us = 1000
			sk.activer(Vector3(COL.x, relief.hauteur_sol(COL.x, COL.y) + 0.1, COL.y), 0.0)
			if sk.chausse:
				sk.basculer_ski()
			_phase = "poser"
			_k = 0
		"poser":
			_k += 1
			if Vector2(sk.global_position.x, sk.global_position.z).distance_to(COL) > 20.0:
				print("COL ÉCART DE DÉPART %s" % sk.global_position)
				_finir(col)
				return
			# collisions du col posées, fenêtre à l'arrêt ailleurs
			if _k < 200 or not col._taches.is_empty() or not relief._f_job.is_empty():
				return
			_refaits0 = col.refaits
			var pts: Array = []
			for v in CHEMIN:
				pts.append(Vector3(v.x, relief.hauteur_sol(v.x, v.y), v.y))
			sk.chemin = pts
			_prec = sk.global_position
			_t = 0.0
			_phase = "marche"
			print("COL départ %s, sol de collision posé sous la maille à 50 m" % sk.global_position)
		"marche":
			_t += dt
			if _t > 3.0 and _fenetre_t < 0.0:
				ReliefBuilder.cible_fenetre = Vector3(COL.x, 0, COL.y)       # la fenêtre arrive en marchant
				_fenetre_t = _t
			var p: Vector3 = sk.global_position
			var hs: float = relief.hauteur_sol(p.x, p.z)
			if p.distance_to(_prec) > 5.0:
				_sauts += 1
				print("COL SAUT t=%.1f de %s à %s" % [_t, _prec, p])
			_prec = p
			if p.y < hs - 1.0:
				_sous_t += dt
				_sous_max = maxf(_sous_max, _sous_t)
			else:
				_sous_t = 0.0
			if sk.is_on_floor():
				_air = 0.0
			else:
				_air += dt
				_air_max = maxf(_air_max, _air)
			if _t > DUREE or (sk.chemin.is_empty() and _t > 20.0):
				_mesurer_ecart(relief, sk)
				_finir(col)


func _mesurer_ecart(relief: ReliefBuilder, sk: SkieurJoueur) -> void:
	var esp: PhysicsDirectSpaceState3D = sk.get_world_3d().direct_space_state
	var c: Vector3 = sk.global_position
	var x: float = c.x - 150.0
	while x <= c.x + 150.0:
		var z: float = c.z - 150.0
		while z <= c.z + 150.0:
			var hs: float = relief.hauteur_sol(x, z)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, hs + 30.0, z), Vector3(x, hs - 80.0, z), sk.collision_mask)
			var r: Dictionary = esp.intersect_ray(q)
			if r.is_empty():
				_vides += 1
			else:
				_ecart_max = maxf(_ecart_max, absf((r["position"] as Vector3).y - hs))
			z += 5.0
		x += 5.0


func _finir(col: CollisionsJeu) -> void:
	var ok: bool = _sauts == 0 and _sous_max <= 0.5 and _air_max <= 1.5 and _ecart_max <= 0.7 and _vides == 0 \
		and _fenetre_t >= 0.0
	print("COL fenêtre posée à t=%.1f s ; formes refaites %d ; joueur reposé %d fois ; sauts %d ; sous le sol %.2f s au plus ; sans sol %.2f s au plus ; sol de collision à %.2f m du sol affiché au plus, %d rayons sans sol" % [
		_fenetre_t, col.refaits - _refaits0, col.reposes, _sauts, _sous_max, _air_max, _ecart_max, _vides])
	print("BANC %s col au nord du Montet à pied (PWA, 20 i/s)" % ("OK" if ok else "ÉCHEC"))
	quit(0 if ok else 1)
