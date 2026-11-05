## Contrôle avant publication : tous les scripts analysés et les nuanceurs des chemins de rendu compilés,
## ce que les bancs sans écran ne font pas. Le jugement (erreurs dans le journal) est dans
## tools_controle_nuanceurs.py, qui lance ce banc avec et sans pack, aux crans 0 et 4.
##   godot --path godot_project -s bench_nuanceurs_3d.gd -- --mode=normal --cran=4 --allege --attendu=sans_hd
extends SceneTree

const MOTS_LIGNES: Array = ["tcd10_toviere", "tsd6_bollin", "tsf4_grand_huit", "tsd6_leissieres", "tph_grande_motte", "olympique"]
const ATTENTE_MAX_S: float = 300.0

var _main: Node = null
var _attendu: String = ""
var _ecarts: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("NUANCEURS_ECHEC il faut un écran : sans lui, rien n'est compilé")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--attendu="):
			_attendu = a.trim_prefix("--attendu=")
	_charger_scripts("res://scripts")
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_suite()


## Analyse de tous les scripts, même ceux qu'aucune vue ne charge.
func _charger_scripts(dossier: String) -> void:
	var n: int = 0
	for f in DirAccess.get_files_at(dossier):
		if f.ends_with(".gd"):
			n += 1
			var s: Script = load(dossier.path_join(f)) as Script
			if s == null or not s.can_instantiate():
				_ecarts.append("script non analysé : " + f)
	print("[Nuanceurs] %d scripts analysés" % n)


func _images(n: int) -> void:
	for i in n:
		await process_frame


func _attendre(condition: Callable, quoi: String) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not bool(condition.call()):
		if float(Time.get_ticks_msec() - t0) / 1000.0 > ATTENTE_MAX_S:
			_ecarts.append("attente dépassée : " + quoi)
			return false
		await process_frame
	return true


func _suite() -> void:
	await process_frame
	await _attendre(func() -> bool: return _main.relief != null and _main.relief.pret, "relief")
	var rel: ReliefBuilder = _main.relief
	# vues du funiculaire
	for mode in [Cabin.ViewMode.FPV, Cabin.ViewMode.EXTERIOR, Cabin.ViewMode.MACHINES]:
		_main.cabin.set_view(mode)
		await _images(30)
	_main.cabin.set_view(Cabin.ViewMode.FPV)
	# skieur, domaine, remontées
	_main.basculer_skieur()
	await _attendre(func() -> bool: return _main.mode_skieur and _main.skieur != null, "skieur")
	var hd: bool = rel.fin != null and rel.fin.hd
	if hd:
		await _attendre(func() -> bool: return rel.fin.anneaux != null and rel.fin.anneaux._installe, "anneaux")
		if rel.fin.foret != null:
			await _attendre(func() -> bool: return rel.fin.foret._pas_prepa >= 3, "forêt")
	_verifier_chemin(rel, hd)
	var sk: CharacterBody3D = _main.skieur
	var points: Array = []
	for D in RemonteesDonnees.LIGNES:
		for m in MOTS_LIGNES:
			if String(D["cle"]) == m or (String(D["cle"]).contains(m) and points.size() < 8):
				points.append(_main.remontees.monde(float(D["aval"][0]), float(D["aval"][1])))
				break
	for p: Vector2 in points:
		sk.global_position = Vector3(p.x + 20.0, rel.hauteur_sol(p.x + 20.0, p.y) + 0.1, p.y)
		sk.velocity = Vector3.ZERO
		await _images(120)
	_main.basculer_ski()
	await _images(30)
	await _images(60)
	print("[Nuanceurs] %d points de remontées vus ; hd %s ; allégé %s ; cran %d" % [points.size(), hd, PerfManager.allege, PerfManager.cran_courant])
	for e in _ecarts:
		print("NUANCEURS_ECHEC " + e)
	print("NUANCEURS_FIN" if _ecarts.is_empty() else "NUANCEURS_ECHEC %d écarts" % _ecarts.size())
	quit(0 if _ecarts.is_empty() else 1)


## Un chemin de rendu resté inactif ne prouverait rien.
func _verifier_chemin(rel: ReliefBuilder, hd: bool) -> void:
	if _attendu == "hd" and not hd:
		_ecarts.append("pack attendu, sol sans pack")
	if _attendu == "sans_hd" and hd:
		_ecarts.append("sol sans pack attendu, pack en service")
	if _attendu == "sans_hd" and not rel._detail_seul and ClassDB.class_exists("ReliefHD"):
		_ecarts.append("détail de neige sans pack inactif")
	if "--allege" in OS.get_cmdline_user_args() and not PerfManager.allege:
		_ecarts.append("profil allégé demandé, inactif")
