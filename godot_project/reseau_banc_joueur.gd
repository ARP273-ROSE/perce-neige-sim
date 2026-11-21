## Joueur du banc du mode réseau (lancé par bench_reseau_3d.gd, pas seul) :
##   godot --headless --path . -s reseau_banc_joueur.gd -- --role=A|B --url=ws://… --sortie=DOSSIER [--code=…]
##   [--sans-noyau]
## A crée le salon (écrit son code), skie en ligne droite à 10 m/s, puis s'assied sur un siège qui part ; il note
## sa vraie position en temps commun. B rejoint, regarde A et note où il le dessine (et dans quel véhicule).
extends SceneTree

const LIGNE: String = "tsd6_grattalu"
const DUREE_SKI: float = 14.0
const DUREE_ASSIS: float = 45.0

var _main: Node = null
var _f: int = 0
var _role: String = "A"
var _url: String = ""
var _sortie: String = "/tmp/reseau_banc"
var _code: String = ""
var _lg: LigneRemontee = null
var _rc: ReseauClient = null
var _phase: String = "charge"
var _t: float = 0.0
var _p0: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.ZERO
var _notes: Array = []
var _t_total: float = 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
		elif a.begins_with("--url="):
			_url = a.trim_prefix("--url=")
		elif a.begins_with("--sortie="):
			_sortie = a.trim_prefix("--sortie=")
		elif a.begins_with("--code="):
			_code = a.trim_prefix("--code=")
		elif a == "--sans-noyau":
			LigneRemontee.noyau_desactive = true
	HeureJeu.regler(2026, 2, 15, 12, 0, 1.0, false)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _ecrire(nom: String, contenu: String) -> void:
	var f := FileAccess.open(_sortie.path_join(nom), FileAccess.WRITE)
	if f != null:
		f.store_string(contenu)
		f.close()


func _fin(ok: bool) -> void:
	_ecrire("%s.json" % _role, JSON.stringify({"notes": _notes, "calages": _rc.calages if _rc != null else 0,
		"ok": ok, "decalage": _rc.decalage if _rc != null else 0.0}))
	print("RESEAU_JOUEUR %s fini (%d notes)" % [_role, _notes.size()])
	if _rc != null:
		_rc.quitter()
	quit(0)


func _tick() -> void:
	_f += 1
	var dt: float = get_root().get_process_delta_time() if get_root() != null else 0.016
	_t_total += dt
	if _t_total > 900.0:
		_fin(false)
		return
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if not _main.mode_skieur:
		_main.basculer_skieur()
		return
	if _main.remontees == null or not _main.remontees.pret:
		return
	if _lg == null:
		_lg = _main.remontees._ligne_nommee(LIGNE)
		_main.aller_a_remontee(_lg)
		return
	if not _lg.pret:
		return
	var sk: SkieurJoueur = _main.skieur
	match _phase:
		"charge":
			_rc = _main.reseau_client()
			_rc.url = _url
			_rc.nom = "Banc" + _role
			_rc.couleur = Color(0.9, 0.1, 0.1) if _role == "A" else Color(0.1, 0.3, 0.9)
			if _role == "A":
				_rc.creer()
			else:
				_rc.rejoindre(_code)
			_phase = "salon"
		"salon":
			if not _rc.connecte:
				return
			if _role == "A":
				_ecrire("code.txt", _rc.code)
				if _rc.pairs.is_empty():
					return
			_t += dt
			if _t < 3.0:
				return
			_t = 0.0
			if _role == "A":
				_p0 = sk.global_position
				_dir = Vector3(1, 0, 0.3).normalized()
				sk.set_physics_process(false)
				_phase = "ski"
			else:
				_phase = "regarde"
		"ski":
			_t += dt
			var p: Vector3 = _p0 + _dir * 10.0 * _t
			p.y = relief.hauteur_sol(p.x, p.z)
			sk.global_position = p
			sk.velocity = _dir * 10.0
			sk._visuel.rotation.y = atan2(-_dir.x, -_dir.z)
			_notes.append([_rc.maintenant(), p.x, p.y, p.z, "ski"])
			if _t > DUREE_SKI:
				# s'asseoir sur le premier siège en ligne parti de la gare aval
				var best: int = -1
				var smin: float = INF
				for i in range(_lg._vehicules.size()):
					var s: float = float(_lg._vehicules[i][1])
					if _lg.zone_vehicule(i) == "ligne" and s < smin:
						smin = s
						best = i
				sk.set_physics_process(true)
				var v: VehiculeRemontee = _lg.vehicule(best)
				_main.remontees.a_bord = [_lg, best, 0, true, false]
				sk.support = null
				sk.embarque = true
				sk.asseoir(_main.remontees._cap(v), true)
				print("RESEAU_JOUEUR A assis sur le véhicule %d (s %.1f)" % [best, smin])
				_t = 0.0
				_phase = "assis"
		"assis":
			_t += dt
			var p2: Vector3 = sk.global_position
			_notes.append([_rc.maintenant(), p2.x, p2.y, p2.z, "assis"])
			if _t > DUREE_ASSIS or _main.remontees.a_bord.is_empty():
				_fin(not _main.remontees.a_bord.is_empty())
		"regarde":
			_t += dt
			for id in _rc.pairs:
				var e: Dictionary = _rc.pairs[id]["rendu"]
				if e.is_empty():
					continue
				var p3: Vector3 = e["p"]
				# (à bord, posé dans NOTRE véhicule tel qu'il est maintenant : comparé au temps présent)
				var bord: bool = bool(e.get("bord", false))
				_notes.append([_rc.maintenant() - (0.0 if bord else ReseauClient.DELAI_RENDU), p3.x, p3.y, p3.z,
					int(e["po"]), bord])
			if _t > DUREE_SKI + DUREE_ASSIS + 30.0 or (_t > 10.0 and _rc.pairs.is_empty()):
				_fin(true)
