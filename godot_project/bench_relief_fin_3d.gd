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
	print("BENCH_RELIEF_FIN %s" % ("OK" if _echecs == 0 else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _echecs == 0 else 1)
