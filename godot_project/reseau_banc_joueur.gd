## Joueur du banc du mode réseau (lancé par bench_reseau_3d.gd, pas seul) :
##   godot --headless --path . -s reseau_banc_joueur.gd -- --role=A|B --url=ws://… --sortie=DOSSIER [--code=…]
##   [--sans-noyau]
## A crée le salon (écrit son code), skie en ligne droite à 10 m/s, puis s'assied sur un siège qui part ; il note
## sa vraie position en temps commun. B rejoint, regarde A et note où il le dessine (et dans quel véhicule).
extends SceneTree

const LIGNE: String = "tsd6_grattalu"
const DUREE_SKI: float = 14.0
const DUREE_ASSIS: float = 45.0
const DUREE_LIGNES: float = 40.0
## Remontées comparées entre les deux jeux (« cale tout ») : tenues construites et actives (RemonteesDomaine.forcees).
const SUIVIES: Array = ["tsd6_grattalu", "tsd6_bollin", "tsd6_fresse", "funival", "tph_grande_motte"]
const T_URGENCE: float = 8.0           # A (hôte) : arrêt d'urgence de Grattalu, 8 s après le début de « lignes »
const T_ARRET_B: float = 15.0          # B : arrêt du TPH (il en demande la main), 15 s après la fin du siège de A

var _main: Node = null
var _f: int = 0
var _role: String = "A"
var _url: String = ""
var _sortie: String = "/tmp/reseau_banc"
var _code: String = ""
var _par_liste: bool = false          # B entre par la liste des salons ouverts, sans code (21/11/2026)
var _rejoint_par_liste: String = ""   # code du salon pris dans la liste
var _lg: LigneRemontee = null
var _rc: ReseauClient = null
var _phase: String = "charge"
var _t: float = 0.0
var _p0: Vector3 = Vector3.ZERO
var _dir: Vector3 = Vector3.ZERO
var _notes: Array = []
var _t_total: float = 0.0
var _lignes: Array = []                # [clé de temps commun (½ s), {remontée : [...]}]
var _k_prec: int = -1
var _evts: Dictionary = {}             # événement → clé de temps commun
# scénario « corde » (21/11/2026) : évacuation à la corde chacun son tour ; « coupe » : A se déconnecte en descente
var _scenario: String = ""
var _ph_corde: String = ""
var _transitions: Array = []           # [temps commun, phase]
var _vrai: Array = []                  # (A) [temps commun, x, y, z] pendant sa descente
var _vu: Array = []                    # (B) [temps commun, x, y, z] de la corde de A telle que dessinée
var _quitte: float = -1.0
# scénarios des commandes (21/11/2026) : « arret_a », « arret_b » (arrêt d'une remontée par B, vu par A), « perche »
# (A et B sur la même perche d'un téléski biplace : chacun voit l'autre à sa place, côte à côte)
var _ligne: String = LIGNE
var _perche: Array = []                # [temps commun, écart au point attendu (m), écart latéral (m), même véhicule]
var _t_depart: float = -1.0


var _rame2: bool = false          # mène la rame 2 du funiculaire (l'autre joueur la 1) : repère commun


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
		elif a.begins_with("--scenario="):
			_scenario = a.trim_prefix("--scenario=")
		elif a == "--par-liste":
			_par_liste = true
		elif a == "--sans-noyau":
			LigneRemontee.noyau_desactive = true
		elif a == "--rame2":
			_rame2 = true
	HeureJeu.regler(2026, 2, 15, 12, 0, 1.0, false)
	RemonteesDomaine.forcees = PackedStringArray(SUIVIES)
	match _scenario:
		"arret_a":
			_ligne = "tcd10_daille"
		"arret_b":
			# A loin de la Daille (pas construite chez lui), B à la Daille
			_ligne = "tcd10_daille" if _role == "B" else "tsd6_grattalu"
		"perche":
			_ligne = "tke2_montet"
	if _scenario in ["arret_a", "arret_b", "perche"]:
		RemonteesDomaine.forcees = PackedStringArray([_ligne])
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _ecrire(nom: String, contenu: String) -> void:
	var f := FileAccess.open(_sortie.path_join(nom), FileAccess.WRITE)
	if f != null:
		f.store_string(contenu)
		f.close()


func _fin(ok: bool) -> void:
	var pil: Dictionary = {}
	if _rc != null:
		for n in SUIVIES:
			pil[n] = _rc.pilote_de(n)
	_ecrire("%s.json" % _role, JSON.stringify({"notes": _notes, "calages": _rc.calages if _rc != null else 0,
		"ok": ok, "decalage": _rc.decalage if _rc != null else 0.0, "lignes": _lignes, "evts": _evts,
		"id": _rc.mon_id if _rc != null else -1, "pilotes": pil}))
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
	if _rame2 and not _main._scenario_rame2:
		_main.apply_rame(true)
	if not _main.mode_skieur:
		_main.basculer_skieur()
		return
	if _main.remontees == null or not _main.remontees.pret:
		return
	if _lg == null:
		_lg = _main.remontees._ligne_nommee(_ligne)
		_main.aller_a_remontee(_lg)
		return
	if not _lg.pret:
		return
	var sk: SkieurJoueur = _main.skieur
	if _scenario in ["corde", "coupe"]:
		_tick_corde(dt, sk)
		return
	if _scenario != "":
		_tick_cmd(dt, sk)
		return
	_relever_lignes()
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
				if _main.remontees.a_bord.is_empty():
					_fin(false)
					return
				# rame du funiculaire posée au milieu de la voie : B doit la voir là
				_main.physics.s = 900.0
				_main.physics.s_prev_step = 900.0
				_t = 0.0
				_phase = "lignes"
				# Funival à quai en bas, départ dans 3 s : B doit suivre sa courbe d'accélération (funival_v)
				var fv: Telepherique = _main.remontees._ligne_nommee("funival")
				if fv != null and fv.pret:
					fv._s = fv._x_quai(true)
					fv._sens = 1.0
					fv._v = 0.0
					fv.set("_a", 0.0)
					fv._phase = "quai"
					fv._t_quai = 3.0
					fv._t_quai_tot = 0.0
		"lignes":
			_t += dt
			if _t > T_URGENCE and not _evts.has("urgence_A"):
				_main.remontees._ligne_nommee("tsd6_grattalu").exploitation().commande("urgence")
				_evts["urgence_A"] = int(_rc.maintenant() * 2.0)
				# commandes du funiculaire partagées : A coupe l'éclairage du tunnel et les phares
				_main.set_tunnel_lights(false)
				_main.physics.lights_head = false
				_evts["drap_A"] = int(_rc.maintenant() * 2.0)
				print("RESEAU_JOUEUR A arrêt d'urgence de Grattalu")
			if _t > DUREE_LIGNES:
				_fin(true)
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
			if _t > DUREE_SKI + DUREE_ASSIS + T_ARRET_B and not _evts.has("arret_B"):
				var tph: LigneRemontee = _main.remontees._ligne_nommee("tph_grande_motte")
				if tph != null and tph.pret:
					tph.exploitation().commande("arreter")
					_evts["arret_B"] = int(_rc.maintenant() * 2.0)
					print("RESEAU_JOUEUR B arrêt du TPH (demande de la main)")
			if _t > DUREE_SKI + DUREE_ASSIS + DUREE_LIGNES + 8.0 or (_t > 10.0 and _rc.pairs.is_empty()):
				_fin(true)


## Relevé, sur une grille de temps commun (½ s), de l'état des remontées suivies chez ce joueur.
func _relever_lignes() -> void:
	if _rc == null or not _rc.connecte:
		return
	var k: int = int(_rc.maintenant() * 2.0)
	if k == _k_prec:
		return
	_k_prec = k
	var d: Dictionary = {}
	for n in SUIVIES:
		var lg: LigneRemontee = _main.remontees._ligne_nommee(n)
		if lg == null or not lg.pret or lg._vehicules.is_empty():
			continue
		if lg is Telepherique:
			var t: Telepherique = lg
			d[n] = [lg.etat, t._s, t._phase, t._sens]
			if n == "funival":
				d["funival_v"] = [t._phase, t._v]
		else:
			var kr: int = ReseauClient._reference(lg)
			if kr < 0:
				continue
			d[n] = [lg.etat, fposmod(float(lg._vehicules[kr][1]), lg.espacement), lg.espacement, lg.regime()]
	# (abscisse de la RAME 1, quelle que soit la rame menée ici)
	var s_pn: float = PNConstants.MIROIR_S - _main.physics.s if _main._scenario_rame2 else _main.physics.s
	d["perce_neige"] = [str(_main.physics.emergency), s_pn, str(_main.physics.doors_open), _main.pn_drapeaux()]
	_lignes.append([k, d])


# --- scénarios de la corde -----------------------------------------------------------------------------------

func _fin_corde(ok: bool) -> void:
	_ecrire("%s.json" % _role, JSON.stringify({"ok": ok, "ph": _transitions, "vrai": _vrai, "vu": _vu,
		"quitte": _quitte, "id": _rc.mon_id if _rc != null else -1}))
	print("RESEAU_JOUEUR %s corde fini (%d transitions, %d vrai, %d vu)" % [_role, _transitions.size(), _vrai.size(),
		_vu.size()])
	if _rc != null and _quitte < 0.0:
		_rc.quitter()
	quit(0)


func _noter_phase() -> void:
	var rd: RemonteesDomaine = _main.remontees
	var ph: String = "bord"
	if not rd._corde.is_empty():
		ph = "descente"
	elif rd._corde_attente != null:
		ph = "attente"
	elif rd.a_bord.is_empty() and _ph_corde in ["descente", "sol"]:
		ph = "sol"
	if ph != _ph_corde:
		_ph_corde = ph
		_transitions.append([_rc.maintenant(), ph])
		print("RESEAU_JOUEUR %s phase %s" % [_role, ph])


func _s_de(i: int) -> float:
	return fposmod(float(_lg._vehicules[i][1]), _lg.longueur_boucle)


func _asseoir(i: int, place: int, sk: SkieurJoueur) -> void:
	sk.set_physics_process(true)
	var v: VehiculeRemontee = _lg.vehicule(i)
	_main.remontees.a_bord = [_lg, i, place, true, false]
	sk.support = null
	sk.embarque = true
	sk.asseoir(_main.remontees._cap(v), true)


func _tick_corde(dt: float, sk: SkieurJoueur) -> void:
	if _t_total > 600.0:
		_fin_corde(false)
		return
	match _phase:
		"charge":
			_rc = _main.reseau_client()
			_rc.url = _url
			_rc.nom = "Banc" + _role
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
			# (le temps que B cale ses sièges sur ceux de l'hôte)
			if _t < 25.0:
				return
			_t = 0.0
			if _role == "A":
				_lg.exploitation().commande("urgence")
				print("RESEAU_JOUEUR A arrêt d'urgence de %s" % LIGNE)
			_phase = "arret"
		"arret":
			_t += dt
			if _t < 5.0 or _lg.vitesse_reelle > 0.01:
				return
			if _role == "A":
				# le véhicule en ligne le plus haut au-dessus du sol
				var best: int = -1
				var hmax: float = -INF
				for i in range(_lg._vehicules.size()):
					if _lg.zone_vehicule(i) != "ligne":
						continue
					var p: Vector3 = _lg.vehicule(i).global_position
					var h: float = p.y - _main.relief.hauteur_sol(p.x, p.z)
					if h > hmax and h < 30.0:
						hmax = h
						best = i
				_asseoir(best, 0, sk)
				_ecrire("cible.txt", str(_s_de(best)))
				print("RESEAU_JOUEUR A assis sur %d (s %.1f, %.1f m)" % [best, _s_de(best), hmax])
				_t = 0.0
				_phase = "attend_b"
			else:
				if not FileAccess.file_exists(_sortie.path_join("cible.txt")):
					return
				var cible: float = float(FileAccess.get_file_as_string(_sortie.path_join("cible.txt")))
				var best2: int = -1
				var dmin: float = INF
				for i2 in range(_lg._vehicules.size()):
					var d: float = absf(wrapf(_s_de(i2) - cible, -_lg.longueur_boucle * 0.5, _lg.longueur_boucle * 0.5))
					if d < dmin:
						dmin = d
						best2 = i2
				_asseoir(best2, 1, sk)
				_ecrire("b_assis.txt", "1")
				print("RESEAU_JOUEUR B assis sur %d (écart %.2f m)" % [best2, dmin])
				_t = 0.0
				_phase = "b_attend"
		"attend_b":
			_t += dt
			if not FileAccess.file_exists(_sortie.path_join("b_assis.txt")) or _t < 2.0:
				return
			_main.remontees.descendre_corde()
			_t = 0.0
			_phase = "evac"
		"b_attend":
			_t += dt
			if _t < 3.5:
				return
			_main.remontees.descendre_corde()
			_t = 0.0
			_phase = "evac"
		"evac":
			_t += dt
			_noter_phase()
			var rd: RemonteesDomaine = _main.remontees
			if _role == "A" and not rd._corde.is_empty():
				var p2: Vector3 = sk.global_position
				_vrai.append([_rc.maintenant(), p2.x, p2.y, p2.z])
				if _scenario == "coupe" and float(rd._corde["t"]) > 4.0 and _quitte < 0.0:
					_quitte = _rc.maintenant()
					print("RESEAU_JOUEUR A se déconnecte en pleine descente")
					_rc.quitter()
					_fin_corde(true)
					return
			if _role == "B":
				var tr: float = _rc.maintenant() - ReseauClient.DELAI_RENDU
				for id in _rc.cordes:
					var cd: Dictionary = _rc.corde_pair(id, tr)
					if not cd.is_empty():
						var pc: Vector3 = cd["p"]
						_vu.append([tr, pc.x, pc.y, pc.z])
			if _ph_corde == "sol" and _t > 3.0:
				_t2_fin += dt
				if _t2_fin > 6.0:
					_fin_corde(true)
			if _t > 240.0:
				_fin_corde(false)


var _t2_fin: float = 0.0



# --- scénarios des commandes et de la perche partagée (21/11/2026) --------------------------------------------

const DAILLE: String = "tcd10_daille"


func _fin_cmd(ok: bool) -> void:
	_ecrire("%s.json" % _role, JSON.stringify({"ok": ok, "lignes": _lignes, "evts": _evts, "perche": _perche,
		"id": _rc.mon_id if _rc != null else -1, "par_liste": _rejoint_par_liste,
		"code": _rc.code if _rc != null else ""}))
	print("RESEAU_JOUEUR %s %s fini (%d relevés, %d perche)" % [_role, _scenario, _lignes.size(), _perche.size()])
	if _rc != null:
		_rc.quitter()
	quit(0)


## Relevé, au temps commun de la grille (½ s), de l'état de la remontée suivie et de la phase de ses véhicules
## (abscisse d'un véhicule en ligne modulo l'espacement, ramenée à l'instant de la grille).
func _relever_cmd(n: String) -> void:
	if _rc == null or not _rc.connecte:
		return
	var k: int = int(_rc.maintenant() * 2.0)
	if k == _k_prec:
		return
	_k_prec = k
	var lg: LigneRemontee = _main.remontees._ligne_nommee(n)
	if lg == null:
		return
	var ph: float = -1.0
	if lg.pret and not lg._vehicules.is_empty():
		var kr: int = ReseauClient._reference(lg)
		if kr >= 0:
			var sk_: float = float(lg._vehicules[kr][1]) - lg.vitesse_reelle * (_rc.maintenant() - k * 0.5)
			ph = fposmod(sk_, lg.espacement)
	_lignes.append([k, lg.etat, ph, lg.espacement, lg.regime() if lg.pret else -1.0, lg.pret])


func _tick_cmd(dt: float, sk: SkieurJoueur) -> void:
	if _t_total > 800.0:
		_fin_cmd(false)
		return
	match _phase:
		"charge":
			_rc = _main.reseau_client()
			_rc.url = _url
			_rc.nom = "Banc" + _role
			if _role == "A":
				_rc.creer()
			elif _par_liste:
				# comme au panneau RÉSEAU : la liste des salons ouverts, puis le bouton du salon de A — rien de tapé
				_rc.liste_recue.connect(func(salons: Array) -> void:
					for e in salons:
						if String(e["hote"]) == "BancA" and _rejoint_par_liste == "":
							_rejoint_par_liste = String(e["code"])
							print("RESEAU_JOUEUR B rejoint par la liste : salon de %s (%d joueur)" % [e["hote"], e["n"]])
							_rc.rejoindre_salon(_rejoint_par_liste))
				_rc.lister()
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
			# (le temps que B cale ses véhicules sur ceux de l'hôte ; à la perche, on la prend aussitôt arrivés, comme en
			# vrai — le Montet venait d'être construit chez chacun, ses perches pas encore calées)
			if _t < (3.0 if _scenario == "perche" else 25.0):
				return
			_t = 0.0
			_phase = "jeu"
			if _scenario == "perche" and _role == "A":
				_t_depart = _rc.maintenant() + 4.0
				_ecrire("depart.txt", str(_t_depart))
		"jeu":
			_t += dt
			match _scenario:
				"arret_a":
					_jeu_arret_a()
				"arret_b":
					_jeu_arret_b()
				"perche":
					_jeu_perche(sk)


func _jeu_arret_a() -> void:
	_relever_cmd(DAILLE)
	var ex: ExploitationRemontee = _lg.exploitation()
	if _role == "A" and not _evts.has("geste_A"):
		# A touche au poste de la Daille (la main lui reste une minute)
		ex.commande("mode", "manuel")
		_evts["geste_A"] = _rc.maintenant()
		print("RESEAU_JOUEUR A geste au poste de la Daille")
	if _role == "B" and _t > 5.0 and not _evts.has("arret_B"):
		ex.commande("arreter")
		_evts["arret_B"] = _rc.maintenant()
		print("RESEAU_JOUEUR B arrêt de la Daille")
	if _role == "B" and _t > 35.0 and not _evts.has("depart_B"):
		var r: String = ex.commande("demarrer")
		_evts["depart_B"] = _rc.maintenant()
		print("RESEAU_JOUEUR B départ de la Daille (%s)" % ("fait" if r == "" else r))
	if _t > 62.0:
		_fin_cmd(true)


func _jeu_arret_b() -> void:
	_relever_cmd(DAILLE)
	if _role == "B":
		if _t > 2.0 and not _evts.has("arret_B"):
			_lg.exploitation().commande("arreter")
			_evts["arret_B"] = _rc.maintenant()
			print("RESEAU_JOUEUR B arrêt de la Daille (A est loin)")
		if _t > 150.0:
			_fin_cmd(true)
		return
	# A : loin, puis à la Daille plus d'une minute après (la main de B a expiré)
	if _t > 75.0 and not _evts.has("vers_daille_A"):
		_evts["vers_daille_A"] = _rc.maintenant()
		var fo: PackedStringArray = RemonteesDomaine.forcees
		fo.append(DAILLE)
		RemonteesDomaine.forcees = fo
		_lg = _main.remontees._ligne_nommee(DAILLE)
		_main.aller_a_remontee(_lg)
		print("RESEAU_JOUEUR A part vers la Daille")
	if _evts.has("vers_daille_A") and not _evts.has("daille_A") and _lg.pret:
		_evts["daille_A"] = _rc.maintenant()
		print("RESEAU_JOUEUR A : Daille construite (%s)" % _lg.etat)
	if _evts.has("daille_A") and _rc.maintenant() - float(_evts["daille_A"]) > 20.0:
		_fin_cmd(true)
	if _t > 400.0:
		_fin_cmd(false)


func _jeu_perche(sk: SkieurJoueur) -> void:
	var rd: RemonteesDomaine = _main.remontees
	if _t_depart < 0.0:
		var pth: String = _sortie.path_join("depart.txt")
		if FileAccess.file_exists(pth):
			_t_depart = float(FileAccess.get_file_as_string(pth))
		return
	if not _evts.has("au_depart") and _rc.maintenant() >= _t_depart:
		_evts["au_depart"] = _rc.maintenant()
		var q: Vector3 = _lg.global_transform * _lg.point_embarquement(true)
		sk.set_physics_process(true)
		sk.global_position = q + Vector3.UP * 0.05
		sk.velocity = Vector3.ZERO
		print("RESEAU_JOUEUR %s au départ du Montet" % _role)
		return
	if rd.a_bord.is_empty():
		if _evts.has("perche") or _t > 120.0:
			_fin_cmd(_evts.has("perche"))
		return
	if not _evts.has("perche"):
		_evts["perche"] = _rc.maintenant()
		_evts["veh"] = int(rd.a_bord[1])
		print("RESEAU_JOUEUR %s perche %d prise" % [_role, int(rd.a_bord[1])])
	var tb: float = _rc.maintenant() - float(_evts["perche"])
	if tb < 8.0:
		return
	if tb > 28.0:
		_fin_cmd(true)
		return
	# l'autre, tel que dessiné ici, à sa place sur NOTRE perche : même recul que nous, sa place en travers
	var v: VehiculeRemontee = _lg.vehicule(int(rd.a_bord[1]))
	var inv: Transform3D = v.global_transform.affine_inverse()
	var moi: Vector3 = inv * sk.global_position
	for id in _rc.pairs:
		var e: Dictionary = _rc.pairs[id]["rendu"]
		if e.is_empty():
			continue
		var lui: Vector3 = inv * (e["p"] as Vector3)
		var attendu: Vector3 = Vector3(rd.x_place_perche(_lg, 1 - rd.place_perche()) if rd.has_method("x_place_perche") else moi.x, lui.y, moi.z)
		var ec: float = Vector2(lui.x - attendu.x, lui.z - attendu.z).length()
		_perche.append([_rc.maintenant(), ec, lui.x - moi.x, lui.z - moi.z,
			int(_rc.pairs[id].get("veh", -1)) == int(rd.a_bord[1])])
