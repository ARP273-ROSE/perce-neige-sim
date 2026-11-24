## Commandes du véhicule où l'on est et touches des jeux (audit d'intégration du 24/11/2026 : « les boutons phares ou
## éclairage cabine doivent agir sur ce où je suis — Funival, cabine, téléphérique — pas le Perce-Neige quand je n'y
## suis pas » ; « courir à 16 km/h, activé par défaut » ; E agir, M carte, PILOTER) :
##   - course par défaut à pied, 16 km/h ; schuss à part (pas de schuss par défaut à ski) ;
##   - Funival : PHARES forcés éteints / allumés puis ÉCLAIRAGE, état relu ; télésiège : refusé (pas de phares) ;
##   - commande hors de tout véhicule : message, rien ne change ; M : carte affichée / cachée ;
##   - pas de commande de véhicule proposée au pupitre quand on n'est pas à bord.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_commandes_vehicule_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _etat: int = 0
var _fu: Funival = null
var _tsf: LigneRemontee = null
var _ok: bool = true
var _t: int = 0
var _p_course: Vector3 = Vector3.ZERO


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	_etat = 99
	print("BENCH_COMMANDES_VEHICULE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)


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
			if sk == null or not sk.actif:
				return
			_verif("course par défaut à pied", sk.course and not sk.schuss)
			_verif("course à 16 km/h", absf(SkieurJoueur.V_COURSE * 3.6 - 16.0) < 0.01, "%.1f km/h" % (SkieurJoueur.V_COURSE * 3.6))
			for e in _main.remontees.lignes:
				if e[0] is Funival:
					_fu = e[0]
				elif (e[0] as LigneRemontee).exploitation().groupe == "tsf" and _tsf == null:
					_tsf = e[0]
			_main.aller_a_remontee(_fu)
			_t = _f
			_etat = 2
		2:
			if _fu == null or not _fu.pret:
				if _f - _t > 3000:
					_verif("Funival construit", false)
					_fin()
				return
			var ex: ExploitationRemontee = _fu.exploitation()
			_verif("Funival : phares, éclairage, klaxon proposés", ex.commandes_vehicule() == ["phares", "eclairage", "klaxon"])
			var avant: bool = _fu.phares_allumes()
			_verif("PHARES accepté", ex.commande("phares") == "")
			_verif("PHARES forcés à l'inverse", ex.phares_force == (0 if avant else 1))
			_t = _f
			_etat = 3
		3:
			if _f - _t < 5:
				return
			var ex3: ExploitationRemontee = _fu.exploitation()
			_verif("phares du Funival suivent le pupitre", _fu.phares_allumes() == (ex3.phares_force == 1))
			var e0: float = ex3.eclairage_effectif(EclairagesNuit.niveau_courant)
			_verif("ÉCLAIRAGE accepté", ex3.commande("eclairage") == "")
			_verif("éclairage intérieur inversé", (ex3.eclairage_effectif(EclairagesNuit.niveau_courant) > 0.02) != (e0 > 0.02))
			var tel: Dictionary = ex3.etat_pupitre(false, false)
			_verif("pas à bord : aucune commande de véhicule au pupitre", (tel.get("cmd_vehicule", []) as Array).is_empty())
			_verif("pas à bord : télémesure avec l'état des phares", tel.has("phares_on") and tel.has("eclairage_on"))
			_verif("à bord : commandes au pupitre", (ex3.etat_pupitre(true, false).get("cmd_vehicule", []) as Array).size() == 3)
			if _tsf != null:
				_verif("télésiège : phares refusés", _tsf.exploitation().commande("phares") != "")
				_verif("télésiège : aucune commande de véhicule", _tsf.exploitation().commandes_vehicule().is_empty())
			# hors de tout véhicule et loin du Perce-Neige : rien ne change, pas d'erreur
			var f_av: int = ex3.phares_force
			_main.commande_vehicule("phares")
			_verif("hors véhicule : le Funival n'est pas touché", ex3.phares_force == f_av)
			# M : carte
			var cs: CommandesSkieur = _main.commandes_skieur
			var c_av: bool = cs.carte.visible
			cs.basculer_carte()
			_verif("M : carte basculée", cs.carte.visible != c_av)
			cs.basculer_carte()
			_verif("bouton PILOTER caché hors poste et hors va-et-vient", not cs.pilotage_possible())
			_main.agir()          # E : ici, rien d'autre à faire que chausser
			_verif("E : chausse les skis à l'écart de tout", sk.chausse)
			if sk.chausse:
				_main.basculer_ski()
			# course à 16 km/h sur la neige : posé sur le relief à l'écart de tout, touche avancer tenue
			var r: ReliefBuilder = _main.relief
			var p0: Vector3 = sk.global_position + Vector3(70.0, 0.0, 70.0)
			sk.global_position = Vector3(p0.x, r.hauteur(p0.x, p0.z) + 0.6, p0.z)
			sk.velocity = Vector3.ZERO
			if _main.get("collisions") != null:
				_main.collisions.assurer_autour(sk.global_position)
			_t = _f
			_etat = 4
		4:
			sk.touches_ext = 1                 # (Z / flèche haut relayée par le PC : course par défaut)
			if _f - _t == 120:
				_p_course = sk.global_position
			if _f - _t == 180:
				var d: Vector3 = sk.global_position - _p_course
				d.y = 0.0
				var v: float = d.length()          # (sur 1 s)
				sk.touches_ext = 0
				_verif("sur la neige : court à ~16 km/h", v > 3.6 and v < 4.7 and sk.sol_terrain,
					"%.1f km/h, sol %s (%s), support %s, chausse %s" % [v * 3.6, "relief" if sk.sol_terrain else "bâti", sk.nom_sol, str(sk.support), str(sk.chausse)])
				_fin()
