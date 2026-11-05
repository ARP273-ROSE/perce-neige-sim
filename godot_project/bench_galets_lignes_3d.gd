## Écart câble-gorge de chaque galet de ligne, sur toutes les lignes et les deux brins : au repos
## (au loin, lignes cuites, PWA) et calé sur le câble (près du point de vue). Écart > 0 : le câble ne
## touche pas le galet ; < 0 : il y entre. Échoue au-delà de SEUIL.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_galets_lignes_3d.gd -- --mode=normal [--csv=chemin]
extends SceneTree

const SEUIL: float = 0.025           # m

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _i: int = -1
var _t: float = 0.0
var _lg: LigneRemontee = null
var _lignes: PackedStringArray = PackedStringArray(["ligne;pylone;nature;brin;galet;z;repos_mm;cale_mm;trace_mm"])
var _res: Array = []
var _csv: String = ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--csv="):
			_csv = a.trim_prefix("--csv=")
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60:
		return
	_t += 1.0 / 60.0
	if _lg == null or _lg.pret or _t > 120.0:
		if _lg != null and _lg.pret:
			_mesurer(_lg)
		elif _lg != null:
			print("[ECHEC] %s : pas construite" % _lg.name)
		_i += 1
		var l: Array = _main.remontees.lignes
		if _i >= l.size():
			_finir()
			return
		_lg = l[_i][0]
		_main.aller_a_remontee(_lg)
		_t = 0.0


## Hauteur du câble tel que tracé (segments de la boucle), au droit de d, sur le brin.
func _y_trace(lg: LigneRemontee, d: float, montee: bool) -> float:
	var x: float = lg._x_brin(montee)
	var b: PackedVector3Array = lg._boucle
	var n: int = b.size()
	for i in range(n):
		var a: Vector3 = b[i]
		var c: Vector3 = b[(i + 1) % n]
		if absf(a.x - c.x) > 0.5 or signf(a.x) != signf(x):
			continue
		var z0: float = minf(-a.z, -c.z)
		var z1: float = maxf(-a.z, -c.z)
		if d >= z0 and d <= z1 and z1 > z0:
			return lerpf(a.y, c.y, (d - (-a.z)) / ((-c.z) - (-a.z)))
	return lg.y_cable(d, montee)


func _ecart(lg: LigneRemontee, tete: Node3D, py: Node3D, pos: Vector3, rot: float, za: float, zp: float, s: float, montee: bool, trace: bool) -> float:
	var local: Vector3 = Vector3(0.0, -s * 0.11, za - zp)
	var xf_p: Transform3D = Transform3D(Basis(Vector3.RIGHT, rot), pos)
	var q: Vector3 = py.transform * (tete.transform * (xf_p * local))
	# distance vraie de l'axe du galet à la courbe du câble (sur un arc serré, la verticale la surestime)
	var d: float = -q.z
	var meilleur: float = INF
	var cote: float = 0.0
	for k in range(-60, 61):
		var dk: float = d + k * 0.02
		var yk: float = _y_trace(lg, dk, montee) if trace else lg.y_cable(dk, montee)
		var dist: float = Vector2(dk - d, yk - q.y).length()
		if dist < meilleur:
			meilleur = dist
			cote = yk - q.y
	# (s = -1, galet sous le câble : le câble doit être au-dessus de l'axe)
	return (meilleur if signf(cote) == -s else -meilleur) - PyloneRemontee.R_GALET - PyloneRemontee.R_CABLE


func _mesurer(lg: LigneRemontee) -> void:
	for q in lg._pyl:
		var py: PyloneRemontee = q[0]
		for montee in [true, false]:
			var tete: Node3D = py.get_node_or_null("TeteMontee" if montee else "TeteDescente")
			if tete == null:
				continue
			var d: float = q[1]
			var y_t: float = py.position.y + py.hauteur_cable()
			py.caler(montee, func(z: float) -> float:
				return lg.y_cable(d - z, montee) - y_t)
			var k: int = 0
			for e in py._paires[montee]:
				var s: float = e[5]
				var zp: float = (e[1] as Vector3).z
				var b: Array = py._base_paire(e)
				for za in [float(e[3]), float(e[4])]:
					if k > 0 and za == float(e[3]) and float(e[3]) == float(e[4]):
						continue
					var repos: float = _ecart(lg, tete, py, e[1], e[2], za, zp, s, montee, false)
					var cale: float = _ecart(lg, tete, py, b[0], b[1], za, zp, s, montee, false)
					var trace: float = _ecart(lg, tete, py, b[0], b[1], za, zp, s, montee, true)
					_res.append([repos, cale, trace, String(lg.name), String(py.name), s, montee, k])
					_lignes.append("%s;%s;%s;%s;%d;%.2f;%.0f;%.0f;%.0f" % [lg.name, py.name, "S" if s < 0.0 else "C", "montee" if montee else "descente", k, za, repos * 1000.0, cale * 1000.0, trace * 1000.0])
					k += 1


func _finir() -> void:
	if _csv != "":
		var f: FileAccess = FileAccess.open(_csv, FileAccess.WRITE)
		f.store_string("\n".join(_lignes))
		f.close()
	var n: int = _res.size()
	var ok: bool = true
	for k in [0, 1, 2]:
		var nom: String = ["repos", "calé", "tracé"][k]
		var v: Array = _res.map(func(r: Array) -> float: return absf(float(r[k])))
		v.sort()
		var pire: Array = _res.duplicate()
		pire.sort_custom(func(a: Array, b: Array) -> bool: return absf(float(a[k])) > absf(float(b[k])))
		var hors: int = v.filter(func(x: float) -> bool: return x > SEUIL).size()
		print("GALETS %s : %d galets, médiane %.0f mm, p95 %.0f, max %.0f mm ; %d au-delà de %.0f mm" % [nom, n, v[n / 2] * 1000.0, v[int(n * 0.95)] * 1000.0, v[n - 1] * 1000.0, hors, SEUIL * 1000.0])
		for p in pire.slice(0, 8):
			print("   %+.0f mm %s %s %s %s galet %d" % [float(p[k]) * 1000.0, p[3], p[4], "S" if float(p[5]) < 0.0 else "C", "montée" if p[6] else "descente", p[7]])
		if k != 0 and hors > 0:
			ok = false
	print("BENCH_GALETS_LIGNES " + ("OK" if ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if ok else 1)
