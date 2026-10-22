## Banc « aller à une remontée » (retour d'utilisateur, 22/10/2026 : « mais j'y vais
## comment, à ces deux remontées de démo ? ») : à pied, on ouvre la carte,
## on dézoome, on touche chaque remontée — le skieur doit être déposé au pied
## de sa gare aval, sur la neige, et y rester (pas de chute).
##   godot --headless --fixed-fps 60 --path godot_project -s bench_aller_remontee_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _i: int = 0
var _t: float = 0.0
var _ok: bool = true
var _lg: LigneRemontee = null


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
	if _f < _t0 + 90:
		return
	var cs: CommandesSkieur = _main.commandes_skieur
	var carte: CartePistes = cs.carte
	var lignes: Array = _main.remontees.lignes
	if _i == 0 and _t == 0.0:
		_verif("à pied : bouton CARTE disponible", cs._b_carte.visible)
		cs._b_carte.button_pressed = true
		_verif("à pied : la carte s'ouvre", carte.visible)
		carte.echelle = CartePistes.ECHELLE_MIN
	if _i >= lignes.size():
		print("BENCH_ALLER_REMONTEE " + ("OK" if _ok else "ECHEC"))
		quit(0 if _ok else 1)
		return
	var sk: SkieurJoueur = _main.skieur
	if _t == 0.0:
		_lg = lignes[_i][0]
		# toucher la gare aval de la ligne, sur la carte
		var c: Vector2 = Vector2(sk.global_position.x, sk.global_position.z)
		var a3: Vector3 = _lg.global_transform.origin
		var pos: Vector2 = carte._carte(Vector2(a3.x, a3.z), c, CartePistes.TAILLE * 0.5)
		var ev: InputEventScreenTouch = InputEventScreenTouch.new()
		ev.pressed = true
		ev.position = pos
		carte._gui_input(ev)
	_t += 1.0 / 60.0
	if _t > 3.0:
		var d: float = Vector2(sk.global_position.x - _lg.global_transform.origin.x,
			sk.global_position.z - _lg.global_transform.origin.z).length()
		var sol: float = _main.relief.hauteur_sol(sk.global_position.x, sk.global_position.z)
		_verif("touché %s : déposé au pied de la gare aval, debout sur la neige" % _lg.nom_ligne,
			d < 15.0 and absf(sk.global_position.y - sol) < 1.0 and sk.is_on_floor(),
			"%.1f m de la gare, %.2f m au-dessus du sol, au sol %s" % [d, sk.global_position.y - sol, sk.is_on_floor()])
		_t = 0.0
		_i += 1
