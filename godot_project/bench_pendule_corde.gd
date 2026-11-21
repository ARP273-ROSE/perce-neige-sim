## Banc de la physique de la descente à la corde (PenduleCorde, 21/11/2026) : période du balancement contre la théorie
## 2π·√(L/g) (±5 %), amortissement, tournoiement borné, rebond à l'arrêt du dévidage, même trajectoire à 30 et 60 i/s,
## aucune divergence (vent et accélération de temps ×4 compris).
##   godot --headless --path godot_project -s bench_pendule_corde.gd
extends SceneTree

var _ok: bool = true


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _initialize() -> void:
	var a: Vector3 = Vector3(0, 100, 0)
	# 1. période du balancement, corde de 10 m tenue (pas de dévidage), petite amplitude, sans vent
	for ips in [30.0, 60.0]:
		var pc: PenduleCorde = PenduleCorde.new()
		var l: float = 10.0
		pc.lancer(a, a + Vector3(0, -l * (1.0 + PenduleCorde.ALLONGEMENT_POIDS), 0), Vector3(0.4, 0, 0), 0.0, 0.0)
		pc.l0 = l
		var dt: float = 1.0 / ips
		var t: float = 0.0
		var passages: Array = []
		var x_prec: float = 0.0
		var pics: Array = []
		var vx_prec: float = pc.v.x
		while t < 60.0:
			pc.avancer(dt, a, 0.0, 0.0)
			t += dt
			if x_prec < 0.0 and pc.p.x >= 0.0:
				passages.append(t)
			if vx_prec > 0.0 and pc.v.x <= 0.0:
				pics.append(pc.p.x)
			x_prec = pc.p.x
			vx_prec = pc.v.x
		var periode: float = (passages[-1] - passages[0]) / float(passages.size() - 1) if passages.size() > 1 else 0.0
		var l_eff: float = a.y - (a.y - l * (1.0 + PenduleCorde.ALLONGEMENT_POIDS))
		var theorie: float = TAU * sqrt(l_eff / PenduleCorde.G)
		_verif("période à %d i/s ≈ 2π√(L/g)" % int(ips), absf(periode - theorie) / theorie < 0.05,
			"%.2f s mesurée, %.2f s théorique" % [periode, theorie])
		_verif("balancement amorti à %d i/s" % int(ips), pics.size() > 3 and float(pics[-1]) < float(pics[0]) * 0.95,
			"amplitude %.2f → %.2f m" % [float(pics[0]), float(pics[-1]) if pics.size() > 0 else 0.0])
	# 2. descente complète avec vent, départ vrillé, à 30 et 60 i/s, et à ×4 (pas de 1/15 s) : bornée, cohérente
	var fins: Array = []
	for dt2 in [1.0 / 30.0, 1.0 / 60.0, 4.0 / 60.0]:
		var pc2: PenduleCorde = PenduleCorde.new()
		pc2.lancer(a, a + Vector3(0, -1.0, 0), Vector3(0.45, -0.2, 0), 0.5, 0.35)
		var t2: float = 0.0
		var psi_max: float = 0.0
		var ang_max: float = 0.0
		var fini: bool = true
		while t2 < 40.0:
			pc2.vent = LigneRemontee.vent_monde(t2)
			pc2.avancer(dt2, a, 0.9 if t2 > 1.2 and t2 < 15.0 else 0.0, 0.0)
			t2 += dt2
			if not (is_finite(pc2.p.x) and is_finite(pc2.p.y) and is_finite(pc2.psi)):
				fini = false
				break
			psi_max = maxf(psi_max, absf(pc2.psi))
			ang_max = maxf(ang_max, pc2.angle(a))
		_verif("descente à pas %.3f s sans divergence" % dt2, fini)
		_verif("tournoiement borné (pas %.3f s)" % dt2, psi_max < 3.0, "%.2f rad au plus" % psi_max)
		_verif("balancement réaliste sous le vent (pas %.3f s)" % dt2, rad_to_deg(ang_max) < 20.0 and rad_to_deg(ang_max) > 0.5,
			"%.1f° au plus" % rad_to_deg(ang_max))
		fins.append(pc2.p)
	# (le pas d'intégration est fixe ; seuls le vent et la commande du descendeur sont lus une fois par image)
	_verif("même trajectoire à 30 et 60 i/s (à 5 cm près en 40 s)", (fins[0] as Vector3).distance_to(fins[1]) < 0.05,
		"écart %.4f m" % (fins[0] as Vector3).distance_to(fins[1]))
	# 3. rebond : dévidage à 0,9 m/s arrêté net → la tension dépasse le poids puis revient
	var pc3: PenduleCorde = PenduleCorde.new()
	pc3.lancer(a, a + Vector3(0, -3.0, 0), Vector3.ZERO, 0.0, 0.0)
	var t3: float = 0.0
	while t3 < 8.0:
		pc3.avancer(1.0 / 60.0, a, 0.9, 0.0)
		t3 += 1.0 / 60.0
	var t_max: float = 0.0
	var dernier: float = 0.0
	while t3 < 16.0:
		pc3.avancer(1.0 / 60.0, a, 0.0, 0.0)
		t3 += 1.0 / 60.0
		t_max = maxf(t_max, pc3.tension)
		dernier = pc3.tension
	var poids: float = PenduleCorde.M * PenduleCorde.G
	_verif("rebond à l'arrêt du dévidage", t_max > poids * 1.05 and t_max < poids * 2.5,
		"tension au plus %.0f N pour un poids de %.0f N" % [t_max, poids])
	_verif("rebond amorti", absf(dernier - poids) < poids * 0.03, "%.0f N au bout de 8 s" % dernier)
	print("BENCH_PENDULE_CORDE " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
