## Banc des piques du mode réseau et de la corde, et de l'identification du skieur du réseau (21/11/2026) :
##   - banques RESEAU_* : bilingues, {nom} remplacé, tirage sans redite rapprochée ;
##   - GuetReseau : chaque déclencheur sort sur son passage de seuil, une seule fois tant qu'il dure, écart entre deux
##     piques, répit par genre, file des événements ponctuels (et péremption) ;
##   - PiquesRemontees.evenement_corde : seuils sur les grandeurs du pendule, une fois par descente, espacement, et
##     sur une vraie descente simulée (PenduleCorde) au moins le balancement et le rebond, sans avalanche ;
##   - SkieursDistants : graine « joueur » distincte des PNJ, étiquette nom + distance, chevron, balise au loin,
##     anneau au sol, indicateur au bord de l'écran hors champ (et seulement hors champ).
##   godot --headless --path godot_project -s bench_piques_reseau.gd
extends SceneTree

var _ok: bool = true
var _f: int = 0
var _sd: SkieursDistants = null
var _cam: Camera3D = null


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _initialize() -> void:
	_banques()
	_guet()
	_corde()
	_file_corde()
	_identification_statique()
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), Vector3(0, 2, 0))
	_cam.current = true
	_sd = SkieursDistants.new()
	get_root().add_child(_sd)
	process_frame.connect(_tick)


func _banques() -> void:
	var c: Dictionary = (load("res://scripts/piques_reseau.gd") as Script).get_script_constant_map()
	var n: int = 0
	var mal: Array = []
	for k in c:
		if c[k] is Array:
			for q in c[k]:
				n += 1
				if not (q is Array and q.size() == 2 and String(q[0]) != "" and String(q[1]) != ""
						and String(q[0]).count("{nom}") == String(q[1]).count("{nom}")):
					mal.append(k)
	_verif("banque réseau : %d piques bilingues, mêmes champs dans les deux langues" % n, mal.is_empty() and n >= 45, str(mal))
	for g in GuetReseau.REPIT:
		_verif("liste RESEAU_%s présente (≥ 2 variantes)" % g, PNQuips.liste("RESEAU_" + String(g)).size() >= 2)
	var t: String = PiquesReseau.texte("RESEAU_LOIN", "fr", "Zoé", 4200.0)
	_verif("champs remplacés : " + t, t.find("{") < 0 and (t.find("Zoé") >= 0 or t.find("4.2 km") >= 0))
	var vus: Array = []
	var redites: int = 0
	var l: Array = PNQuips.liste("RESEAU_FROLE")
	for _i in range(l.size() * 3):
		var p: String = PiquesReseau.texte("RESEAU_FROLE", "fr", "Zoé")
		if vus.slice(maxi(0, vus.size() - l.size() / 2)).has(p):
			redites += 1
		vus.append(p)
	_verif("tirage sans redite rapprochée", redites == 0, "%d redites" % redites)


func _o(pairs: Array, extra: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"connecte": true, "latence": 0.05, "seul_s": 0.0, "ma_vitesse": 5.0, "a_bord": false,
		"pairs": pairs, "pilote_ici": "", "urgence_ici": ""}
	o.merge(extra, true)
	return o


func _guet() -> void:
	var g: GuetReseau = GuetReseau.new()
	var calme: Array = [{"nom": "Zoé", "dist": 50.0, "v_rel": 1.0, "vitesse": 6.0, "skie": true, "bord": false}]
	_verif("rien à dire quand tout est calme", g.observer(0.0, _o(calme)).is_empty())
	# événements ponctuels : en file, lâchés en respectant l'écart
	g.signaler("ARRIVEE", 1.0, "Zoé")
	g.signaler("HOTE_AUTRE", 1.0, "Zoé")
	var r1: Array = g.observer(1.0, _o(calme))
	_verif("arrivée annoncée avec le nom", r1.size() == 4 and r1[0] == "ARRIVEE" and r1[1] == "Zoé", str(r1))
	_verif("deuxième événement retenu pendant l'écart", g.observer(2.0, _o(calme)).is_empty())
	var r2: Array = g.observer(1.0 + GuetReseau.ECART_S, _o(calme))
	_verif("deuxième événement lâché après l'écart", r2.size() == 4 and r2[0] == "HOTE_AUTRE", str(r2))
	g.signaler("DEPART", 20.0, "Zoé")
	_verif("événement trop vieux jeté", g.observer(20.0 + GuetReseau.AGE_MAX_FILE + 1.0, _o(calme)).is_empty())
	# frôlement : sur le passage de seuil, pas tant qu'il dure
	var t0: float = 100.0
	var frole: Array = [{"nom": "Zoé", "dist": 1.5, "v_rel": 8.0, "vitesse": 12.0, "skie": true, "bord": false}]
	var rf: Array = g.observer(t0, _o(frole))
	_verif("frôlement détecté", rf.size() == 4 and rf[0] == "FROLE", str(rf))
	_verif("pas de seconde pique tant qu'il dure", g.observer(t0 + 20.0, _o(frole)).is_empty())
	var lent: Array = [{"nom": "Zoé", "dist": 1.5, "v_rel": 1.0, "vitesse": 1.0, "skie": true, "bord": false}]
	_verif("côte à côte lentement : pas de frôlement", g.observer(t0 + 60.0, _o(lent)).is_empty())
	g.observer(t0 + 61.0, _o(calme))
	var rf2: Array = g.observer(t0 + 62.0, _o(frole))
	_verif("frôlement de nouveau après réarmement et répit", rf2.size() == 4 and rf2[0] == "FROLE", str(rf2))
	# même véhicule
	var t1: float = 300.0
	var bord: Array = [{"nom": "Zoé", "dist": 0.9, "v_rel": 0.2, "vitesse": 5.0, "skie": false, "bord": true}]
	var rm: Array = g.observer(t1, _o(bord, {"a_bord": true}))
	_verif("même véhicule détecté", rm.size() == 4 and rm[0] == "MEME_VEHICULE", str(rm))
	# loin
	var loin: Array = [{"nom": "Zoé", "dist": 5200.0, "v_rel": 1.0, "vitesse": 5.0, "skie": true, "bord": false}]
	var rl: Array = g.observer(t1 + 20.0, _o(loin))
	_verif("très loin : pique avec la distance", rl.size() == 4 and rl[0] == "LOIN" and float(rl[2]) > 5000.0, str(rl))
	# beaucoup plus vite, il faut que ça dure RAPIDE_DUREE
	var g2: GuetReseau = GuetReseau.new()
	var vite: Array = [{"nom": "Zoé", "dist": 80.0, "v_rel": 15.0, "vitesse": 20.0, "skie": true, "bord": false}]
	var vu_vite: bool = false
	var t: float = 0.0
	while t < 2.0:
		vu_vite = vu_vite or not g2.observer(t, _o(vite, {"ma_vitesse": 5.0})).is_empty()
		t += 0.5
	_verif("vitesse : pas avant %.0f s" % GuetReseau.RAPIDE_DUREE, not vu_vite)
	var r_v: Array = []
	while t < 5.0 and r_v.is_empty():
		r_v = g2.observer(t, _o(vite, {"ma_vitesse": 5.0}))
		t += 0.5
	_verif("vitesse : pique « plus rapide » avec sa vitesse", r_v.size() == 4 and r_v[0] == "PLUS_RAPIDE"
		and float(r_v[3]) == 20.0, str(r_v))
	# latence, seul, pilote, urgence
	var g3: GuetReseau = GuetReseau.new()
	var rlat: Array = g3.observer(0.0, _o(calme, {"latence": 0.9}))
	_verif("latence élevée", rlat.size() == 4 and rlat[0] == "LATENCE", str(rlat))
	var rs: Array = g3.observer(20.0, _o([], {"seul_s": GuetReseau.SEUL_S + 1.0}))
	_verif("seul trop longtemps", rs.size() == 4 and rs[0] == "SEUL", str(rs))
	var rp: Array = g3.observer(40.0, _o(calme, {"pilote_ici": "Zoé"}))
	_verif("l'autre pilote la remontée où l'on est", rp.size() == 4 and rp[0] == "PILOTE" and rp[1] == "Zoé", str(rp))
	var ru: Array = g3.observer(60.0, _o(calme, {"pilote_ici": "Zoé", "urgence_ici": "Zoé"}))
	_verif("arrêt d'urgence de l'autre", ru.size() == 4 and ru[0] == "URGENCE", str(ru))
	_verif("hors réseau : ni latence ni solitude", GuetReseau.new().observer(0.0, _o([], {"connecte": false,
		"latence": 2.0, "seul_s": 500.0})).is_empty())


func _corde() -> void:
	var deja: Dictionary = {}
	var poids: float = PenduleCorde.M * PenduleCorde.G
	_verif("corde : rien les premières secondes", PiquesRemontees.evenement_corde(
		{"t": 1.0, "angle": 0.5, "omega": 2.0, "tension": 3.0 * poids, "poids": poids}, deja) == "")
	var e1: String = PiquesRemontees.evenement_corde({"t": 5.0, "angle": 0.2, "poids": poids}, deja)
	_verif("corde : balancement au-delà de %.0f°" % rad_to_deg(PiquesRemontees.CORDE_ANGLE), e1 == "CORDE_BALANCE", e1)
	_verif("corde : écart entre deux piques", PiquesRemontees.evenement_corde({"t": 7.0, "omega": 1.0,
		"poids": poids}, deja) == "")
	_verif("corde : tournoiement", PiquesRemontees.evenement_corde({"t": 14.0, "omega": 1.0, "poids": poids},
		deja) == "CORDE_TOURNE")
	_verif("corde : pas deux fois le même", PiquesRemontees.evenement_corde({"t": 30.0, "angle": 0.3, "poids": poids},
		deja) == "")
	_verif("corde : rebond (surtension)", PiquesRemontees.evenement_corde({"t": 40.0, "tension": 1.6 * poids,
		"poids": poids}, deja) == "CORDE_REBOND")
	for evt in ["CORDE_BALANCE", "CORDE_TOURNE", "CORDE_REBOND", "CORDE_VENT", "CORDE_LONG"]:
		_verif("banque %s ≥ 3 piques" % evt, PiquesRemontees._liste(evt, "ts").size() >= 3)
	# une vraie descente de 12 m, profil du secouriste (tenue, filée, arrêt près du sol, pose), avec du vent
	var pc: PenduleCorde = PenduleCorde.new()
	var a: Vector3 = Vector3(0, 12, 0)
	pc.lancer(a, a + Vector3(0, -0.9, 0), Vector3(0.45, -0.2, 0), 0.5, 0.35)
	var dj: Dictionary = {}
	var sortis: Array = []
	var t: float = 0.0
	var dt: float = 1.0 / 30.0
	var arret: float = 0.0
	while t < 60.0 and pc.p.y > 0.001:
		var vd: float = 0.9 if t > 1.2 else 0.0
		if pc.p.y < 1.2:
			if arret < 0.7:
				arret += dt
				vd = 0.0
			else:
				vd = 0.5
		pc.vent = Vector3(4.0 * sin(t * 0.3), 0, 2.0)
		pc.avancer(dt, a, vd, 0.0)
		t += dt
		var ev: String = PiquesRemontees.evenement_corde({"t": t, "angle": pc.angle(a), "omega": pc.omega,
			"tension": pc.tension, "poids": poids, "vent": Vector2(pc.vent.x, pc.vent.z).length()}, dj)
		if ev != "":
			sortis.append([snappedf(t, 0.1), ev])
	_verif("descente simulée : des piques sur la physique, espacées, pas d'avalanche", sortis.size() >= 1
		and sortis.size() <= 5, str(sortis))


## File de descente à la corde (FileCorde) : ordre, groupes de véhicules voisins, départ, oubli des muets.
func _file_corde() -> void:
	var f: FileCorde = FileCorde.new()
	f.noter(7, "tsd6_grattalu", 500.0, 0, 10.0)
	f.noter(3, "tsd6_grattalu", 505.0, 0, 10.0)        # même instant : l'identifiant le plus petit d'abord
	f.noter(9, "tsd6_grattalu", 520.0, 0, 9.0)         # demande plus ancienne : devant
	f.noter(4, "tsd6_grattalu", 900.0, 0, 8.0)         # autre groupe (véhicule loin)
	f.noter(5, "tph_fornet", 100.0, 0, 8.0)
	var fl: Array = f.calculer(10.5)
	var par: Dictionary = {}
	for e in fl:
		par["%s:%s" % [e[0], str(e[1][0])]] = e[1]
	_verif("corde : trois files (deux groupes sur Grattalu, une au Fornet)", fl.size() == 3, str(fl))
	_verif("corde : ordre de demande puis identifiant", par.get("tsd6_grattalu:9", []) == [9, 3, 7],
		str(par.get("tsd6_grattalu:9", [])))
	f.noter(7, "tsd6_grattalu", 500.0, 1, 11.0)        # 7 descend : en tête
	fl = f.calculer(11.0)
	var g: Array = []
	for e in fl:
		if (e[1] as Array).has(7):
			g = e[1]
	_verif("corde : celui qui descend en tête", g == [7, 9, 3], str(g))
	f.noter(7, "tsd6_grattalu", 500.0, 2, 30.0)        # au sol : sorti
	fl = f.calculer(12.0)
	g = []
	for e in fl:
		if (e[1] as Array).has(9):
			g = e[1]
	_verif("corde : au sol, sorti de la file", g == [9, 3], str(g))
	var fd: FileCorde = FileCorde.new()
	fd.noter(1, "tsd6_grattalu", 500.0, 1, 0.0)
	fd.noter(2, "tsd6_grattalu", 501.0, 0, 0.0)
	fd.noter(2, "tsd6_grattalu", 501.0, 0, 9.0)
	var fl2: Array = fd.calculer(10.0)                 # 1 muet 10 s en pleine descente (image figée) : gardé
	_verif("corde : celui qui descend n'est pas oublié sur un silence court", fl2.size() == 1 and fl2[0][1] == [1, 2],
		str(fl2))
	fl = f.calculer(16.5)                               # 9, 3, 4, 5 muets depuis plus de OUBLI_S
	_verif("corde : demandes muettes oubliées (joueur parti)", fl.is_empty(), str(fl))
	f.noter(1, "tsd6_grattalu", 500.0, 0, 20.0)
	f.noter(2, "tsd6_grattalu", 501.0, 1, 20.0)
	f.oublier(2)                                        # départ du salon pendant sa descente
	fl = f.calculer(20.2)
	_verif("corde : la file passe au suivant si celui qui descend part", fl.size() == 1 and fl[0][1] == [1], str(fl))
	_verif("corde : rang", FileCorde.rang([4, 8, 2], 2) == 2 and FileCorde.rang([4], 9) == -1)
	# piques de la corde à plusieurs : genres connus du guet, sortent espacés de ECART_CORDE_S
	var gu: GuetReseau = GuetReseau.new()
	gu.signaler("CORDE_FILE_APRES", 100.0, "Zoé")
	gu.signaler("CORDE_AUTRE_DESCEND", 100.5, "Zoé")
	var r1: Array = gu.observer(101.0, _o([]))
	var r2: Array = gu.observer(102.0, _o([]))
	var r3: Array = gu.observer(105.5, _o([]))
	_verif("corde : piques à plusieurs en file, espacées de %.0f s" % GuetReseau.ECART_CORDE_S,
		not r1.is_empty() and String(r1[0]) == "CORDE_FILE_APRES" and r2.is_empty() and not r3.is_empty()
		and String(r3[0]) == "CORDE_AUTRE_DESCEND", "%s / %s / %s" % [r1, r2, r3])
	var tx: String = PiquesReseau.texte("RESEAU_CORDE_AUTRE_TOURNE", "fr", "Zoé")
	_verif("corde : texte « il tourne » avec le nom : " + tx, tx.find("Zoé") >= 0 and tx.find("{") < 0)


func _identification_statique() -> void:
	var gj: Color = SkieursDistants.graine_joueur(Color(0.2, 0.6, 0.9))
	_verif("graine joueur : drapeau en alpha négatif (PNJ : alpha 1)", gj.a < -0.5)
	var code: String = (load("res://scripts/skieur.gdshader") as Shader).code
	_verif("nuanceur des skieurs : tenue du joueur à sa couleur", code.find("INSTANCE_CUSTOM.a < -0.5") >= 0)
	_verif("chevron grossi au loin", SkieursDistants.echelle_chevron(10.0) == 1.0
		and SkieursDistants.echelle_chevron(400.0) >= 10.0)
	var tl: Vector2 = Vector2(1668, 1194)
	_verif("dans le champ : pas d'indicateur", SkieursDistants.bord_ecran(Vector2(800, 600), false, tl).is_empty())
	var r: Array = SkieursDistants.bord_ecran(Vector2(3000, 600), false, tl)
	_verif("à droite hors champ : indicateur sur le bord droit", not r.is_empty() and (r[0] as Vector2).x > tl.x - 60.0
		and (r[0] as Vector2).x <= tl.x, str(r))
	var r2: Array = SkieursDistants.bord_ecran(Vector2(1000, 600), true, tl)
	_verif("derrière : indicateur au bord, du côté opposé à la projection", not r2.is_empty()
		and (r2[0] as Vector2).x < tl.x * 0.5, str(r2))


func _tick() -> void:
	_f += 1
	if _f == 2:
		_sd.poser([
			[Vector3(0, 0, -12), 0.0, 0, Color(0.9, 0.2, 0.2), "Près"],
			[Vector3(0, 0, -200), 0.0, 0, Color(0.2, 0.8, 0.3), "Loin"],
			[Vector3(0, 0, 30), 0.0, 1, Color(0.2, 0.4, 0.9), "Derrière"]])
		return
	if _f < 4:
		return
	var noms: Array = _sd._noms
	_verif("étiquettes : nom et distance", (noms[0] as Label3D).visible and String((noms[0] as Label3D).text).begins_with("Près")
		and String((noms[0] as Label3D).text).find(" m") > 0, String((noms[0] as Label3D).text))
	_verif("étiquette lisible à toute distance (taille fixe à l'écran, sans test de profondeur)",
		(noms[1] as Label3D).fixed_size and (noms[1] as Label3D).no_depth_test)
	_verif("chevron de chacun visible", (_sd._chevrons[0] as Node3D).visible and (_sd._chevrons[1] as Node3D).visible)
	_verif("balise au loin seulement", not (_sd._balises[0] as Node3D).visible and (_sd._balises[1] as Node3D).visible)
	_verif("anneau au sol à ski", (_sd._anneaux[0] as Node3D).visible)
	_verif("indicateur hors champ : seulement celui de derrière", _sd.hors_champ == [2], str(_sd.hors_champ))
	_verif("places libres cachées", not (_sd._noms[3] as Node3D).visible and not (_sd._chevrons[3] as Node3D).visible)
	_sd.vider()
	_verif("vider : plus rien", not (_sd._noms[0] as Node3D).visible and _sd.hors_champ.is_empty()
		and not (_sd._bords[2] as Control).visible)
	print("BENCH_PIQUES_RESEAU " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
