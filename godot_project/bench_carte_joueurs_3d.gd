## Banc de la carte : joueurs du réseau et skieurs automatiques (retour d'utilisateur du 21/11/2026 : « rajoute
## position autres skieurs sur la carte ») : points des skieurs des pistes relus (au plus PNJ_MAX), joueurs du réseau
## acceptés avec leur cap, dessin sans erreur (dans le cadre et hors cadre), et rendu : la carte, dessinée, porte la
## couleur d'un joueur posé au centre. Captures si DOS est donné (vrai rendu).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_carte_joueurs_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _n: int = 0
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var c: CartePistes = _main.commandes_skieur.carte
	_n += 1
	if _n == 1:
		c.visible = true
		var sk: Vector3 = _main.skieur.global_position
		c.distants = [[Vector2(sk.x + 30.0, sk.z - 40.0), Color(0.1, 0.9, 0.2), "Proche", 0.8],
			[Vector2(sk.x + 90000.0, sk.z), Color(0.2, 0.4, 1.0), "Hors cadre", 0.0]]
		return
	if _n < 240:
		return
	var sp: Node = c.domaine.get("skieurs") if c.domaine != null else null
	var n_sp: int = (sp.get("positions") as PackedVector3Array).size() if sp != null else -1
	_verif("skieurs des pistes relus pour la carte (%d dessinés, %d sur la carte, plafond %d)" % [n_sp, c.pnj.size(),
		CartePistes.PNJ_MAX], n_sp < 0 or (c.pnj.size() == mini(n_sp, CartePistes.PNJ_MAX)))
	_verif("joueurs du réseau gardés avec leur cap", c.distants.size() == 2 and (c.distants[0] as Array).size() == 4)
	var dos: String = OS.get_environment("DOS")
	if dos != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(dos)
		get_root().get_texture().get_image().save_png(dos + "/carte.png")
		print("SHOT carte")
	print("BENCH_CARTE_JOUEURS " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
