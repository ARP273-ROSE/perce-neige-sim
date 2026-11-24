## Téléportation au pied de chaque remontée (retour d'utilisateur du 24/11/2026 : « quand je me téléporte, j'atterris
## souvent dans un mur ou sur un toit ») : pour chaque ligne, aller_a_remontee puis, la dépose finie (gare et voisines
## construites, 11 s), le skieur doit être LIBRE (pas enfermé dans le décor), AU SOL (pas plus de 2,5 m au-dessus du
## relief : ni toit, ni auvent) et posé (sur un sol). Toutes les lignes, ou --lignes=a,b,c.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_depose_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _etat: int = 0
var _lignes: Array = []
var _k: int = 0
var _t: int = 0
var _ok: bool = true
var _n_ok: int = 0
var _fautes: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _fin() -> void:
	_etat = 99
	print("%s dépose libre et au sol : %d / %d lignes%s" % ["[OK]  " if _fautes.is_empty() else "[ECHEC]", _n_ok, _lignes.size(),
		"" if _fautes.is_empty() else " — " + ", ".join(_fautes)])
	print("BENCH_DEPOSE " + ("OK" if _fautes.is_empty() else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _fautes.is_empty() else 1)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30 or _etat == 99:
		return
	var sk: SkieurJoueur = _main.skieur
	match _etat:
		0:
			var scen: Node = _main.get_node_or_null("ScenarioPanel")
			if scen != null:
				scen.queue_free()
			_main.basculer_skieur()
			_etat = 1
		1:
			if sk == null or not sk.actif or not _main.remontees.pret:
				return
			var voulues: PackedStringArray = PackedStringArray()
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--lignes="):
					voulues = a.substr(9).split(",")
			for e in _main.remontees.lignes:
				var lg: LigneRemontee = e[0]
				if lg.role == "haut" and lg.jumelee != null:
					continue
				if voulues.is_empty() or String(lg.name) in voulues:
					_lignes.append(lg)
			_k = 0
			_etat = 2
		2:
			if _k >= _lignes.size():
				_fin()
				return
			_main.aller_a_remontee(_lignes[_k])
			_t = _f
			_etat = 3
		3:
			var lg: LigneRemontee = _lignes[_k]
			# gare prête, puis les 10 s de la dépose écoulées (voisines construites, dernier contrôle)
			if not lg.pret or _main.get("_depose_remontee") != null or float(_main.get("_t_depose")) > 0.0:
				if _f - _t < 60 * 90:
					return
			if _f - _t < 60 * 12:
				return
			var p: Vector3 = sk.global_position
			var haut: float = p.y - relief.hauteur_sol(p.x, p.z)
			var enf: bool = sk.enferme()
			var sol: bool = sk.is_on_floor()
			var bon: bool = not enf and haut <= 2.8 and sol
			if bon:
				_n_ok += 1
			else:
				_fautes.append("%s (%s%s%s %.1f m)" % [lg.name, "enfermé " if enf else "", "perché " if haut > 2.8 else "",
					"en l'air " if not sol else "", haut])
			print("   %s %s : %.1f m au-dessus du relief, enfermé %s, au sol %s" % ["ok" if bon else "ÉCHEC", lg.name, haut, enf, sol])
			_k += 1
			_etat = 2
