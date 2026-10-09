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
var _t_sortie: float = -1.0
var _bascule_faite: bool = false


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
		# --rame-en-haut : la rame pilotée part d'en haut, c'est la rame d'en
		# face qui attend en bas (retour d'utilisateur, 09/10/2026 : « si le skieur monte dans
		# la rame non pilotée, la boucle ne marche pas »)
		if "--rame-en-haut" in OS.get_cmdline_user_args():
			_main._apply_scenario(true, false, "normal")
			print("  rame pilotée en haut : le skieur prendra la rame d'en face")
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
	# quitter la vue skieur (changer de vue) pendant la boucle : elle doit
	# continuer en coulisse, et le retour le retrouve où il en est (retour d'utilisateur,
	# 09/10/2026 : « le mode boucle se désactive si je quitte le mode skieur »)
	if not _bascule_faite and _t_sortie < 0.0 and sa.etape == SkieurAuto.Etape.A_BORD:
		_main.basculer_skieur()
		_t_sortie = _t
		_verif("vue skieur quittée pendant la boucle : elle continue en coulisse, skieur actif et visible",
			not _main.mode_skieur and _main.skieur_auto != null and sk.actif and sk.visible,
			"vue skieur %s, boucle %s, actif %s" % [_main.mode_skieur, _main.skieur_auto != null, sk.actif])
	elif _t_sortie >= 0.0 and _t - _t_sortie > 5.0:
		_main.basculer_skieur()
		_bascule_faite = true
		_t_sortie = -1.0
		_verif("retour en vue skieur : boucle toujours active, skieur à sa place à bord",
			_main.mode_skieur and _main.skieur_auto != null and sk.actif and sk.support != null,
			"vue skieur %s, boucle %s, support %s" % [_main.mode_skieur, _main.skieur_auto != null,
				sk.support.name if sk.support else "aucun"])
	# --rame-en-haut : on va jusqu'à la 2e montée (la rame d'en face doit
	# avoir été prise au moins une fois en bas)
	var fini: bool = sa.boucles >= 1
	if "--rame-en-haut" in OS.get_cmdline_user_args():
		fini = sa.boucles >= 1 and sa.etape == SkieurAuto.Etape.VERS_SORTIE
	if fini or _t > 2600.0:
		_verif("salle et rame atteintes", _vus.has(SkieurAuto.Etape.VERS_RAME) and _vus.has(SkieurAuto.Etape.A_BORD))
		_verif("arrivé en haut, porte Génépy, à pied au départ de la trace", _vus.has(SkieurAuto.Etape.VERS_SORTIE) and _vus.has(SkieurAuto.Etape.VERS_DEPART))
		_verif("chaussé et descendu à ski", _vus.get("ski_chausse", false) and _vus.has(SkieurAuto.Etape.VERS_GARE))
		_verif("boucle bouclée", sa.boucles >= 1, "%s" % DomaineSkiable._mmss(_t))
		_fin()
