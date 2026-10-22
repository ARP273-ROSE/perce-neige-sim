## Banc de la dynamique des remontées (retour d'utilisateur, 22/10/2026 : « les galets
## mobiles en fonction de la courbe du câble et du passage des sièges ; les
## supports noirs s'amincissent jusqu'à 0 ; accélération et décélération
## continues et régulières sur toute la longueur du lanceur ; la cabine ou le
## siège se balance et s'amortit selon sa masse, les variations de vitesse et
## de pente »). Mesures sur le TSD6 Marmottes Express et la TCD10 des Boisses :
##  - lanceur : accélération maxi, saut d'accélération maxi d'une image à l'autre ;
##  - balancement : amplitude à la sortie du lanceur, demi-vie de l'amortissement,
##    siège (léger) contre cabine (lourde) ;
##  - galets : déplacement maxi d'une paire au passage d'une pince ; retour au repos.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_remontee_dynamique_3d.gd
extends SceneTree

var _ok: bool = true


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _ligne(cle: String) -> LigneRemontee:
	var D: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/remontees/%s.json" % cle))
	var lg: LigneRemontee = LigneRemontee.new()
	var prof: PackedVector2Array = PackedVector2Array()
	for p in D["profil"]:
		prof.append(Vector2(float(p[0]), float(p[1])))
	lg.profil = prof
	lg.pylones = D["pylones"]
	lg.voie = float(D["voie"])
	lg.vitesse = float(D["vitesse"])
	lg.espacement = float(D["espacement"])
	lg.famille = String(D["famille"])
	lg.sens_droite = bool(D["sens_droite"])
	get_root().add_child(lg)
	lg.construire()
	lg.set_process(false)
	return lg


func _initialize() -> void:
	var dt: float = 1.0 / 60.0
	for cle in ["tsd6_marmottes_express", "tcd10_boisses"]:
		var lg: LigneRemontee = _ligne(cle)
		print("== ", cle)
		# 1. lanceur : profil de vitesse en gare aval (à pas de 1 cm)
		var l: float = lg.longueur_zone(true)
		var s0: float = lg.s_gare(true, 0.0)
		var a_max: float = 0.0
		var j_max: float = 0.0
		var a_prec: float = 0.0
		var t: float = 0.0
		var s: float = s0 - 20.0
		var v_prec: float = lg.vitesse_en(s)
		while s < s0 + l + 20.0:
			var v: float = lg.vitesse_en(s)
			s += v * dt
			t += dt
			var v2: float = lg.vitesse_en(s)
			var a: float = (v2 - v) / dt
			a_max = maxf(a_max, absf(a))
			j_max = maxf(j_max, absf(a - a_prec))
			a_prec = a
		_verif("lanceur : accélération continue, sans à-coup", a_max < 1.6 and j_max < 0.05,
			"|a| maxi %.2f m/s², saut maxi %.3f m/s² par image (%.0f m de lanceur)" % [a_max, j_max, LigneRemontee.L_FREIN])
		# 2. balancement : un véhicule de la sortie de gare aval à 300 m
		var i: int = 0
		lg._vehicules[i][1] = s0 + l - LigneRemontee.L_FREIN - 3.0
		var v0: VehiculeRemontee = lg.vehicule(i)
		v0.pendule_repos()
		lg._dt = 0.0
		lg._placer(i)
		var amp: float = 0.0
		var t_sortie: float = -1.0
		var phis: Array = []
		var tt: float = 0.0
		while tt < 70.0:
			var sv: float = lg._vehicules[i][1]
			lg._vehicules[i][1] = sv + lg.vitesse_en(sv) * dt
			lg._dt = dt
			lg._placer(i)
			tt += dt
			if t_sortie < 0.0 and lg.zone(lg._vehicules[i][1])[0] == "ligne":
				t_sortie = tt
			if t_sortie >= 0.0:
				phis.append(v0.phi)
				if tt - t_sortie < 8.0:
					amp = maxf(amp, absf(v0.phi))
		# demi-vie : amplitude sur [20 s, 30 s] après la sortie vs [0, 10 s]
		var a1: float = 0.0
		var a2: float = 0.0
		for k in range(phis.size()):
			var tk: float = k * dt
			if tk < 10.0:
				a1 = maxf(a1, absf(phis[k]))
			elif tk > 20.0 and tk < 30.0:
				a2 = maxf(a2, absf(phis[k]))
		print("  balancement : %.1f° à la sortie du lanceur, %.2f° 20 s plus tard (masse %.0f kg)" % [rad_to_deg(amp), rad_to_deg(a2), v0.masse])
		_verif("balancement : le véhicule balance à la sortie du lanceur, puis s'amortit", amp > deg_to_rad(0.8) and a2 < a1 * 0.7,
			"%.1f° → %.2f°" % [rad_to_deg(a1), rad_to_deg(a2)])
		# 3. galets : une pince au droit d'un pylône
		var q: Array = lg._pyl[3]
		var py: PyloneRemontee = q[0]
		var mob: Node3D = py.mobiles[0]
		var base: Vector3 = mob.position
		var dmax: float = 0.0
		var u: float = 3.0
		while u > -3.0:
			py.passage(true, u)
			for e in py._paires[true]:
				dmax = maxf(dmax, ((e[0] as Node3D).position - (e[1] as Vector3)).length())
			u -= 0.02
		py.repos(true)
		_verif("galets : les paires bougent au passage de la pince, puis reviennent au repos",
			dmax > 0.01 and dmax < 0.05 and mob.position.distance_to(base) < 1e-4, "déplacement maxi %.1f mm" % (dmax * 1000.0))
		lg.queue_free()
	print("BENCH_REMONTEE_DYNAMIQUE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
