## Banc du relief fin : réservé au cran 0 sur PC, et un seul sol, sans marche entre la
## grille fine et le relief à 25 m.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_relief_fin_3d.gd -- --mode=normal --relief-fin
extends SceneTree

var _main: Node = null
var _echecs: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	_suite()


func _check(nom: String, ok: bool, detail: String) -> void:
	print("[%s] %s — %s" % ["OK" if ok else "ECHEC", nom, detail])
	if not ok:
		_echecs += 1


func _suite() -> void:
	while _main.relief == null or not _main.relief.pret:
		await process_frame
	var rel: ReliefBuilder = _main.relief
	# (sans --relief-fin, un banc sans écran part au cran 1 : rien à vérifier, le relief reste à 25 m)
	if not "--relief-fin" in OS.get_cmdline_user_args():
		_check("relief à 25 m hors du cran 0", _main.relief.fin == null, "sans grille fine")
		print("BENCH_RELIEF_FIN %s" % ("OK" if _echecs == 0 else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if _echecs == 0 else 1)
		return
	var rf: ReliefFin = rel.fin
	_check("réservé au cran 0", ReliefFin.voulu(0) and not ReliefFin.voulu_sans_forcer(1) and not ReliefFin.voulu_sans_forcer(3),
		"cran 0 %s, cran 1 %s, cran 3 %s" % [str(ReliefFin.voulu(0)), str(ReliefFin.voulu_sans_forcer(1)), str(ReliefFin.voulu_sans_forcer(3))])
	_check("grille fine chargée", rf != null and rf.pret, "fin %s" % str(rf != null))
	if rf == null:
		print("BENCH_RELIEF_FIN ECHEC")
		FinBanc.quitter(self, _main, 1)
		return
	# bords communs entre une maille fine et une maille à 25 m : aucune marche
	var marche: float = 0.0
	var bords: int = 0
	var pas_x: float = ReliefFin.K * ReliefFin.PX
	var pas_z: float = ReliefFin.K * ReliefFin.PZ
	for ci in range(ReliefFin.NCZ):
		for cj in range(ReliefFin.NCX - 1):
			var xb: float = ReliefFin.X0 + (cj + 1) * pas_x
			var z: float = ReliefFin.Z0 + (ci + 0.37) * pas_z
			var a: bool = rf.fine_ici(xb - 0.01, z)
			var b: bool = rf.fine_ici(xb + 0.01, z)
			if a != b:
				bords += 1
				marche = maxf(marche, absf(rel._hauteur_tri(xb - 0.001, z) - rel._hauteur_tri(xb + 0.001, z)))
	_check("pas de marche au raccord", bords > 0 and marche < 0.02, "%d bords, marche max %.4f m" % [bords, marche])
	# hauteur_sol suit les triangles de la grille fine
	var ecart: float = 0.0
	var n: int = 0
	var alea: RandomNumberGenerator = RandomNumberGenerator.new()
	alea.seed = 7
	for k in range(20000):
		var x: float = alea.randf_range(rf.zone.position.x, rf.zone.end.x)
		var z2: float = alea.randf_range(rf.zone.position.y, rf.zone.end.y)
		if not rf.fine_ici(x, z2):
			continue
		var j: int = int((x - ReliefFin.X0) / ReliefFin.PX)
		var i: int = int((z2 - ReliefFin.Z0) / ReliefFin.PZ)
		var pa: Vector3 = rf.noeud(i, j)
		var u: float = (x - ReliefFin.X0) / ReliefFin.PX - j   # (pas pa.x : Vector3 en 32 bits, 1 mm près à 15 km)
		var v: float = (z2 - ReliefFin.Z0) / ReliefFin.PZ - i
		var h: float
		if u + v <= 1.0:
			h = pa.y + (rf.noeud(i, j + 1).y - pa.y) * u + (rf.noeud(i + 1, j).y - pa.y) * v
		else:
			var pd: float = rf.noeud(i + 1, j + 1).y
			h = pd + (rf.noeud(i + 1, j).y - pd) * (1.0 - u) + (rf.noeud(i, j + 1).y - pd) * (1.0 - v)
		ecart = maxf(ecart, absf(rel._hauteur_tri(x, z2) - h))
		n += 1
	_check("un seul sol", n > 1000 and ecart < 0.001, "%d points, écart max %.5f m" % [n, ecart])
	await _regulateur(rel, rf)
	print("BENCH_RELIEF_FIN %s" % ("OK" if _echecs == 0 else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _echecs == 0 else 1)


## Le jeu de hauteurs suit le relief chargé, pas le cran : quand le régulateur change de cran,
## ni le sol, ni les têtes de pylônes, ni le câble ne bougent.
func _regulateur(rel: ReliefBuilder, rf: ReliefFin) -> void:
	_main.basculer_skieur()
	for _i in range(60):
		await process_frame
	var pm: Node = _main.perf_manager
	var fines: Dictionary = _main.remontees._geometrie_fin()
	var pts: PackedVector2Array = PackedVector2Array()
	var alea: RandomNumberGenerator = RandomNumberGenerator.new()
	alea.seed = 11
	for k in range(5000):
		pts.append(Vector2(alea.randf_range(rf.zone.position.x, rf.zone.end.x), alea.randf_range(rf.zone.position.y, rf.zone.end.y)))
	# Référence une fois les lignes proches construites : pendant leur première construction, y_cable
	# bouge normalement (cherché le 03/11/2026, sans lien avec le cran ni le relief) : Fresse cale sa
	# période et son espacement (60 → 59,66 m, donc la chaînette), Col des Vés gagne ses raccords de
	# pylônes (_preparer_raccords : explication lue dans le code, non isolée à l'exécution), 4 cm au plus
	# sur les points relevés ici.
	await _etat(rel, pts)
	for _i in range(30):
		await process_frame
	var etat: Array = await _etat(rel, pts)
	var appliquees: int = 0
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		for x in fines.get(String(lg.name), []):
			for p in lg.pylones:
				var meme: bool = int(p.get("k", -1)) == int(x["k"]) if (x as Dictionary).has("k") 					else (p.has("croisement") and absf(float(p["d"]) - float(x["croisement_d"])) < 1.0)
				if meme and absf(float(p["h"]) - float(x["h"])) < 0.001:
					appliquees += 1
	var n_f: int = 0
	for v in fines.values():
		n_f += (v as Array).size()
	_check("hauteurs du relief fin appliquées", appliquees == n_f, "%d sur %d" % [appliquees, n_f])
	var pire: float = 0.0
	var pire_t: float = 0.0
	var pire_c: float = 0.0
	for c in [1, 3, 0, 2, 0]:
		pm._appliquer(c, "banc")
		for _i in range(5):
			await process_frame
		var e2: Array = await _etat(rel, pts)
		for k in range((e2[0] as PackedFloat32Array).size()):
			pire = maxf(pire, absf(e2[0][k] - etat[0][k]))
		for k in range((e2[1] as PackedFloat32Array).size()):
			pire_t = maxf(pire_t, absf(e2[1][k] - etat[1][k]))
		for k in range((e2[2] as PackedFloat32Array).size()):
			pire_c = maxf(pire_c, absf(e2[2][k] - etat[2][k]))
	_check("changer de cran ne change ni le sol ni le câble", rel.fin == rf and pire == 0.0 and pire_t == 0.0 and pire_c == 0.0,
		"sol %.4f m, têtes %.4f m, câble %.4f m (%d têtes, %d points de câble)" % [pire, pire_t, pire_c, (etat[1] as PackedFloat32Array).size(), (etat[2] as PackedFloat32Array).size()])


func _etat(rel: ReliefBuilder, pts: PackedVector2Array) -> Array:
	var sol: PackedFloat32Array = PackedFloat32Array()
	for q in pts:
		sol.append(rel.hauteur_sol(q.x, q.y))
	var tetes: PackedFloat32Array = PackedFloat32Array()
	var cable: PackedFloat32Array = PackedFloat32Array()
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if lg.tricable() or lg.vaetvient():
			continue
		lg.progressif = false
		lg.H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(lg.famille)
		lg.l_gare = lg.l_gare_pour(lg.famille)
		await lg._calculer_tetes()
		lg._preparer_nez()
		for t in lg._tetes:
			tetes.append(t)
		for f in [0.2, 0.5, 0.8]:
			cable.append(lg.y_cable(lg.longueur_h() * f))
	return [sol, tetes, cable]

