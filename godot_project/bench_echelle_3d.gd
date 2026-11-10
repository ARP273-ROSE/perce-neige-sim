## Banc de l'échelle des pylônes (demande d'utilisateur, 03/11/2026) : déchaussé au pied d'un pylône
## des Leissières, GRIMPER monte jusqu'à la tête ; de nouveau : redescend, lâche, sans chute.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_echelle_3d.gd -- --mode=normal
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _p: int = 0
var _lg: LigneRemontee = null
var _py: PyloneRemontee = null
var _t: float = 0.0
func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)
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
	var sk: SkieurJoueur = _main.skieur
	if _p == 0:
		for e in _main.remontees.lignes:
			if (e[0] as Node).name == "tsd6_leissieres":
				_lg = e[0]
		_main.aller_a_remontee(_lg)
		_p = 1
		return
	if _p == 1 and _lg.pret:
		_py = _lg._pyl[6][0]
		var yy: float = relief.hauteur_sol(_py.global_position.x, _py.global_position.z)
		var b: Vector3 = _py.echelle_a_hauteur(yy)
		sk.global_position = Vector3(b.x + 1.0, relief.hauteur_sol(b.x + 1.0, b.z), b.z)
		sk.velocity = Vector3.ZERO
		if sk.chausse:
			sk.basculer_ski()
		_main.basculer_echelle()
		if not sk.sur_echelle():
			print("BENCH_ECHELLE ECHEC prise")
			FinBanc.quitter(self, _main, 1)
			return
		_p = 2
		return
	if _p == 2:
		_t += 1.0 / 60.0
		if sk.echelle_en_haut():
			print("ECH en haut t=%.1f pos=%s tete=%s bouton=%s" % [_t, sk.global_position, _py.global_transform * Vector3(0, _py.hauteur, 0), _main.commandes_skieur._b_echelle.text])
			_main.basculer_echelle()
			_p = 3
		elif _t > 40:
			print("ECH ECHEC monte"); FinBanc.quitter(self, _main, 1)
		return
	if _p == 3:
		_t += 1.0 / 60.0
		if not sk.sur_echelle():
			print("ECH redescendu t=%.1f pos=%s embarque=%s" % [_t, sk.global_position, sk.embarque])
			_p = 4
			_t = 0
		elif _t > 90:
			print("ECH ECHEC descend"); FinBanc.quitter(self, _main, 1)
		return
	if _p == 4:
		_t += 1.0 / 60.0
		if _t > 2.0:
			var ok: bool = absf(sk.global_position.y - relief.hauteur_sol(sk.global_position.x, sk.global_position.z)) < 0.3 and sk._chute_t <= 0.0
			print("BENCH_ECHELLE " + ("OK" if ok else "ECHEC"))
			FinBanc.quitter(self, _main, 0 if ok else 1)
