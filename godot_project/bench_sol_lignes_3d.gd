## Lignes et sol : pieds de pylônes, câble au-dessus du sol réel, gares, comparés entre le
## relief à 25 m et le relief fin (même géométrie précalculée). Ne juge pas : il écrit les
## écarts, ligne par ligne, dans user://sol_lignes_<mode>.csv.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_sol_lignes_3d.gd -- --mode=normal [--relief-fin]
extends SceneTree

var _main: Node = null
var _f: int = 0
var _f0: int = 0
var _fait: bool = false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if _fait or relief == null or not relief.pret or _f < 30:
		return
	if _f0 == 0:
		_f0 = _f
		_main.basculer_skieur()
		return
	if _f < _f0 + 60:
		return
	_fait = true
	_mesurer()


func _mesurer() -> void:
	var fine: bool = _main.relief.fin != null
	var lignes: PackedStringArray = PackedStringArray(["ligne;famille;pylones;pied_max;pied_coin_max;pied_pire;garde_outil_min;sous_garde;garde_reelle_min;d_reelle;sol_axe_ecart_max;tete_min;tete_max;dev_max;gare_aval_haut;gare_aval_bas;gare_amont_haut;gare_amont_bas"])
	var detail: PackedStringArray = PackedStringArray(["ligne;h0;d;y_abs;sol_g;sol_d;garde"])
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if lg.tricable() or lg.vaetvient():
			continue
		lg.progressif = false
		lg.H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(lg.famille)
		lg.l_gare = lg.l_gare_pour(lg.famille)
		await lg._calculer_tetes()
		lg._preparer_nez()
		lignes.append(_ligne(lg))
		detail.append(_detail(lg))
	var nom: String = "user://sol_lignes_%s.csv" % ("fin" if fine else "25m")
	var fd := FileAccess.open(nom.replace(".csv", "_detail.csv"), FileAccess.WRITE)
	fd.store_string("
".join(detail) + "
")
	fd.close()
	var f := FileAccess.open(nom, FileAccess.WRITE)
	f.store_string("\n".join(lignes) + "\n")
	f.close()
	print("BENCH_SOL_LIGNES OK %s %d lignes" % ["fin" if fine else "25m", lignes.size() - 1])
	FinBanc.quitter(self, _main, 0)


func _ligne(lg: LigneRemontee) -> String:
	var L: float = lg.longueur_h()
	# pied : le pylône est posé à terrain(d) (profil tous les 10 m), le sol réel est _sol
	var pied: float = 0.0
	var pied_coin: float = 0.0
	var pire: String = ""
	var tmin: float = INF
	var tmax: float = -INF
	var dev: float = 0.0
	for i in range(lg.pylones.size()):
		var d: float = float(lg.pylones[i]["d"])
		var t: float = lg.terrain(d)
		var ec: float = absf(t - lg._sol(0.0, -d))
		if ec > pied:
			pied = ec
			pire = "P%d" % (i + 1)
		for c in [Vector2(1.5, 1.5), Vector2(-1.5, 1.5), Vector2(1.5, -1.5), Vector2(-1.5, -1.5)]:
			pied_coin = maxf(pied_coin, absf(t - lg._sol(c.x, -d + c.y)))
		var ha: float = lg.y_cable(d) - t
		tmin = minf(tmin, ha)
		tmax = maxf(tmax, ha)
		if not lg.teleski():
			dev = maxf(dev, absf(lg.deviation_pylone(i, true)))
	# câble : l'outil (profil), puis le vrai sol sous les deux brins, tous les 2 m
	var gout: float = INF
	var sous: int = 0
	if not lg.teleski():
		for k in range(lg.pylones.size() + 1):
			var g: float = lg._garde_portee(k)
			gout = minf(gout, g)
			if g < -0.3:
				sous += 1
	var greel: float = INF
	var dreel: float = 0.0
	var axe: float = 0.0
	var dv: float = 20.0
	while dv < L - 20.0:
		var y: float = lg.y_cable(dv)
		axe = maxf(axe, absf(lg.terrain(dv) - lg._sol(0.0, -dv)))
		for x in [-lg.voie * 0.5, lg.voie * 0.5]:
			var m: float = y - lg._sol(x, -dv) - lg._garde_exigee(dv)
			if m < greel:
				greel = m
				dreel = dv
		dv += 2.0
	# gare : sol sous l'emprise, par rapport au niveau de la gare (terrain au bout de ligne)
	var ga: Array = _gare(lg, 0.0, 1.0)
	var gb: Array = _gare(lg, L, -1.0)
	return "%s;%s;%d;%.2f;%.2f;%s;%.2f;%d;%.2f;%.0f;%.2f;%.1f;%.1f;%.2f;%.2f;%.2f;%.2f;%.2f" % [lg.name, lg.famille, lg.pylones.size(), pied, pied_coin, pire, gout, sous, greel, dreel, axe, tmin, tmax, rad_to_deg(dev), ga[0], ga[1], gb[0], gb[1]]


func _gare(lg: LigneRemontee, d0: float, sens: float) -> Array:
	var niveau: float = lg.terrain(d0)
	var demi: float = lg.voie * 0.5 + 1.5
	var haut: float = -INF
	var bas: float = INF
	var t: float = 0.0
	while t <= lg.l_gare:
		for x in [-demi, -demi * 0.5, 0.0, demi * 0.5, demi]:
			var s: float = lg._sol(x, -(d0 - sens * t)) - niveau
			haut = maxf(haut, s)
			bas = minf(bas, s)
		t += 2.0
	return [haut, bas]


## Câble en altitude absolue et sol sous les deux brins, tous les 2 m ; capacité des galets par pylône.
func _detail(lg: LigneRemontee) -> String:
	var h0: float = lg.transform.origin.y
	var L: float = lg.longueur_h()
	var o: PackedStringArray = PackedStringArray()
	var dv: float = 20.0
	while dv < L - 20.0:
		o.append("%s;%.3f;%.0f;%.3f;%.3f;%.3f;%.2f" % [lg.name, h0, dv, lg.y_cable(dv) + h0, lg._sol(-lg.voie * 0.5, -dv) + h0, lg._sol(lg.voie * 0.5, -dv) + h0, lg._garde_exigee(dv)])
		dv += 2.0
	if not lg.teleski():
		for i in range(lg.pylones.size()):
			var cap: Array = lg._capacite(lg.pylones[i])
			var bo: Array = [LigneRemontee.DEVIATION_MIN, float(cap[0])] if float(cap[1]) <= 0.0 else ([-float(cap[1]), -0.002] if float(cap[0]) <= 0.0 else [-float(cap[1]), float(cap[0])])
			var e: float = 0.0
			for m in [true, false]:
				var dd: float = lg.deviation_pylone(i, m)
				e = maxf(e, maxf(float(bo[0]) - dd, dd - float(bo[1])))
			o.append("%s;%.3f;P%d;%.3f;%.3f;%.3f;%.3f" % [lg.name, h0, i + 1, rad_to_deg(maxf(e, 0.0)), rad_to_deg(lg.deviation_pylone(i, true)), lg.terrain(float(lg.pylones[i]["d"])) + h0, lg.y_cable(float(lg.pylones[i]["d"])) + h0])
	return "
".join(o)
