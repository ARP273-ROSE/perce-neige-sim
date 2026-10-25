## Banc des piques des remontées (retour d'utilisateur, 25/10/2026) :
## 1. la banque : chaque événement × famille a des piques, en deux langues,
##    et un tirage ne ressort pas une pique récente ;
## 2. au jeu : embarquer sans passer sous le portique → FRAUDE et huées de la
##    file ; quitter le siège en ligne → SAUT ; les Leissières, prises à
##    l'amont, ne valent pas la pique « à la descente ».
##   godot --headless --fixed-fps 60 --path godot_project -s bench_piques_remontees_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _lz: LigneRemontee = null
var _piques: Array = []
const CLE: String = "tsd6_madeleine"
const CLE_2: String = "tsd6_leissieres"


func _initialize() -> void:
	_banque()
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_PIQUES_REMONTEES " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _banque() -> void:
	var c: Dictionary = (load("res://scripts/piques_remontees.gd") as Script).get_script_constant_map()
	var n: int = 0
	var mal: Array = []
	for k in c:
		if c[k] is Array and k != "EVENEMENTS":
			for q in c[k]:
				n += 1
				if not (q is Array and q.size() == 2 and String(q[0]) != "" and String(q[1]) != ""):
					mal.append(k)
	_verif("banque : %d piques, toutes en français et en anglais" % n, mal.is_empty() and n > 120, str(mal))
	var vides: Array = []
	var redites: int = 0
	for fam in ["siege_doppelmayr_e98_6", "siege_fixe_4", "cabine_omega4", "perche_enrouleur", "cabine_3s", "cabine_tph"]:
		var lg: LigneRemontee = LigneRemontee.new()
		lg.famille = fam
		for evt in PiquesRemontees.EVENEMENTS:
			var l: Array = PiquesRemontees._liste(evt, PiquesRemontees.famille(lg))
			if l.is_empty():
				vides.append("%s/%s" % [evt, fam])
				continue
			var tires: Array = []
			for _i in range(l.size() * 2):
				var p: String = PiquesRemontees.pique(evt, lg, "fr")
				var fen: int = l.size() * 2 / 3
				if tires.slice(maxi(0, tires.size() - fen)).has(p):
					redites += 1
				tires.append(p)
			if PiquesRemontees.pique(evt, lg, "en") == "":
				vides.append("%s/%s en" % [evt, fam])
		lg.free()
	_verif("chaque événement a des piques pour chaque famille", vides.is_empty(), str(vides))
	_verif("pas de redite récente au tirage", redites == 0, "%d redites" % redites)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		(_main.remontees as RemonteesDomaine).pique.connect(func(e: String, _l: LigneRemontee) -> void: _piques.append(e))
		return
	if _f < _t0 + 60:
		return
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == CLE:
					_lg = e[0]
				if (e[0] as Node).name == CLE_2:
					_lz = e[0]
			if _lg == null or _lz == null:
				_verif("lignes posées", false)
				_fin()
				return
			var p: Vector3 = _lg.global_transform * Vector3(_lg._x_brin(true) * 2.0, 0.0, 8.0)
			p.y = _main.relief.hauteur_sol(p.x, p.z) + 0.1
			_main.collisions.assurer_autour(p)
			sk.activer(p, 0.0)
			sk.dernier_sol = p
			_phase = 1
		1:
			if not _lg.pret or _t < 2.0:
				return
			# à la ligne d'arrêt sans être passé sous le portique ; on oublie
			# la dépose (sinon pas de pique : il n'a pas choisi d'y être)
			var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.basculer_ski(true)
			sk.dernier_sol = q
			rm._p_prec = sk.global_position
			rm._t_depose = -1000.0
			rm._valide.clear()
			_piques.clear()
			_phase = 2
			_t = 0.0
		2:
			rm._t_depose = -1000.0
			if not rm.a_bord.is_empty():
				var s: SonsRemontees = rm.sons
				var hue: bool = s != null and ((s._coup3s.playing and s._coup3s.stream == s._sons["file_huees"])
					or (s._coup3s_b.playing and s._coup3s_b.stream == s._sons["file_huees"]))
				var txt: String = _main.commandes_skieur._pique.text if _main.commandes_skieur._pique != null else ""
				_verif("portique contourné : pique FRAUDE, affichée, et huées de la file", _piques.has("FRAUDE") and hue and txt != "",
					"%s, huées %s, « %s »" % [str(_piques), str(hue), txt])
				_phase = 3
				_t = 0.0
			elif _t > 40.0:
				_verif("assis au télésiège", false, "rien en 40 s")
				_fin()
		3:
			if rm.a_bord.is_empty():
				_verif("en ligne", false, "débarqué")
				_fin()
			elif _lg.zone_vehicule(rm.a_bord[1]) == "ligne" and _t > 3.0:
				_piques.clear()
				rm.quitter()
				_verif("quitter le siège en ligne : pique SAUT", _piques.has("SAUT"), str(_piques))
				var L: float = _lz.longueur_h()
				var p: Vector3 = _lz.global_transform * Vector3(_lz._x_brin(false) * 2.0, _lz.terrain(L), -L - 6.0)
				p.y = _main.relief.hauteur_sol(p.x, p.z) + 0.1
				_main.collisions.assurer_autour(p)
				sk.activer(p, 0.0)
				sk.dernier_sol = p
				_phase = 4
				_t = 0.0
			elif _t > 60.0:
				_verif("en ligne", false, "toujours en gare après 60 s")
				_fin()
		4:
			if not _lz.pret or _t < 2.0:
				return
			var q: Vector3 = _lz.global_transform * _lz.point_embarquement(false)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			sk.basculer_ski(true)
			sk.dernier_sol = q
			rm._repos = 0.0
			_piques.clear()
			_phase = 5
			_t = 0.0
		5:
			if not rm.a_bord.is_empty():
				_verif("Leissières prise à l'amont : pas de pique « à la descente »", not _piques.has("DESCENTE"), str(_piques))
				_fin()
			elif _t > 40.0:
				_verif("assis aux Leissières (amont)", false, "rien en 40 s")
				_fin()
