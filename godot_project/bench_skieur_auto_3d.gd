## Banc du skieur en AUTO (07/10/2026) : parti de la place de Val Claret, il
## fait la boucle tout seul — salle, rame, trajet, terrasse, escalier, ski
## jusqu'à Val Claret, retour à la gare.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_skieur_auto_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t: float = 0.0
var _ok: bool = true
var _lance: bool = false
var _vus: Dictionary = {}
var _etape_prec: int = -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_SKIEUR_AUTO " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief: ReliefBuilder = _main.get("relief")
	if relief == null or not relief.pret:
		if _f > 20000:
			_verif("relief prêt", false)
			_fin()
		return
	_t += 1.0 / 60.0
	if not _lance:
		_lance = true
		_main.basculer_skieur()
		_main.basculer_skieur_auto()
		_verif("AUTO lancé", _main.skieur_auto != null)
		_t = 0.0
		return
	var sa: SkieurAuto = _main.skieur_auto
	if sa == null:
		_verif("AUTO toujours actif", false)
		_fin()
		return
	if sa.etape != _etape_prec:
		_etape_prec = sa.etape
		_vus[sa.etape] = _t
		print("  %s : étape %d" % [DomaineSkiable._mmss(_t), sa.etape])
	var sk: SkieurJoueur = _main.skieur
	if sa.etape == SkieurAuto.Etape.SKI and sk.chausse:
		_vus["ski_chausse"] = true
	if sa.boucles >= 1 or _t > 1700.0:
		_verif("salle et rame atteintes", _vus.has(SkieurAuto.Etape.VERS_RAME) and _vus.has(SkieurAuto.Etape.A_BORD))
		_verif("arrivé en haut, porte Génépy, à pied au départ de la trace", _vus.has(SkieurAuto.Etape.VERS_SORTIE) and _vus.has(SkieurAuto.Etape.VERS_DEPART))
		_verif("chaussé et descendu à ski", _vus.get("ski_chausse", false) and _vus.has(SkieurAuto.Etape.VERS_GARE))
		_verif("boucle bouclée", sa.boucles >= 1, "%s" % DomaineSkiable._mmss(_t))
		_fin()
