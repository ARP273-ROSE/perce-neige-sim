## Profil du câble de toutes les lignes : déviation à chaque pylône (signe et nature), régularité le long
## d'une crête, angle fantôme (cassure hors de tout train de galets) et entrée en gare.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_profil_lignes_3d.gd -- --mode=normal [--csv=chemin]
extends SceneTree

const FANTOME_MAX: float = 1.5        # degrés sur 1 m, hors galets
## Seuils : au-delà, le banc échoue. L'état connu (voir CHANGELOG) les atteint sans les dépasser.
const SIGNES_MAX: int = 6             # pylônes dont la déviation contredit la nature (> 1°)
const CREUX_MAX: int = 9              # support bien plus plat que ses voisins (crête en dents de scie)
const ENTREE_MAX: float = 18.0        # degrés, pente du câble à l'entrée d'une gare (18 depuis la tension variable du 14/11/2026 : la portée basse, moins tendue, fléchit plus — Grand Pré 17,6°)

var _main: Node = null
var _f: int = 0
var _i: int = -1
var _lg: LigneRemontee = null
var _t: float = 0.0
var _rangs: Array = []
var _lignes: PackedStringArray = PackedStringArray(["ligne;pylone;d;h;nature;dev_deg;fantome_deg"])
var _csv: String = ""
var _pylones_mauvais_signe: int = 0
var _fantomes: int = 0
var _creux: Array = []
var _signes: Array = []
var _entrees: Array = []


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
	if _f == 40:
		_main.basculer_skieur()
	if _f < 100:
		return
	_t += 1.0 / 60.0
	if _lg == null or _lg.pret or _t > 120.0:
		if _lg != null and _lg.pret:
			_mesurer(_lg)
		_i += 1
		var l: Array = _main.remontees.lignes
		if _i >= l.size():
			_finir()
			return
		_lg = l[_i][0]
		_main.aller_a_remontee(_lg)
		_t = 0.0


func _nature(p: Dictionary) -> String:
	var n: String = ""
	for g in p.get("montee", []):
		n += String(g[1])
	return n


func _angle(lg: LigneRemontee, d: float, e: float, montee: bool) -> float:
	return rad_to_deg(atan2(lg.y_cable(d + e, montee) - lg.y_cable(d, montee), e))


func _mesurer(lg: LigneRemontee) -> void:
	if lg.teleski() or lg.tricable() or lg.vaetvient() or lg.pylones.is_empty():
		return
	var L: float = lg.longueur_h()
	var n: int = lg.pylones.size()
	var devs: Array = []
	var mauvais: int = 0
	for i in range(n):
		var d: float = float(lg.pylones[i]["d"])
		var p: Dictionary = lg.pylones[i]
		var e: float = 12.0
		var dv: float = _angle(lg, d - e, e, true) - _angle(lg, d, e, true)
		devs.append(dv)
		var nat: String = _nature(p)
		var sup: bool = nat.begins_with("S") and not nat.contains("C")
		var cmp: bool = nat.begins_with("C") and not nat.contains("S")
		if (sup and dv < -0.2) or (cmp and dv > 0.2):
			mauvais += 1
		if (sup and dv < -1.0) or (cmp and dv > 1.0):
			_signes.append("%s P%d %.1f" % [lg.name, i + 1, dv])
		_lignes.append("%s;P%d;%.0f;%.1f;%s;%.2f;" % [lg.name, i + 1, d, lg._tetes[i] - lg.terrain(d), nat, dv])
	_pylones_mauvais_signe += mauvais
	# rupture de régularité : un pylône dont la déviation s'écarte fort de ses voisins porteurs
	var rupt: float = 0.0
	var ou_r: int = -1
	for i in range(1, n - 1):
		var moy: float = (float(devs[i - 1]) + float(devs[i + 1])) * 0.5
		var r: float = absf(float(devs[i]) - moy)
		if r > rupt:
			rupt = r
			ou_r = i
	# angle fantôme : cassure sur 1 m hors de tout train
	var pire: float = 0.0
	var ou: float = 0.0
	var d2: float = 0.5
	var trains: Array = []
	for i in range(n):
		trains.append(float(lg.pylones[i]["d"]))
	while d2 < L - 0.5:
		var loin: bool = true
		for t in trains:
			if absf(d2 - float(t)) < 7.0:
				loin = false
				break
		if loin and d2 > 2.5 * lg._h_nez[0] + 1.0 and L - d2 > 2.5 * lg._h_nez[1] + 1.0:
			var a: float = absf(_angle(lg, d2 - 1.0, 1.0, true) - _angle(lg, d2, 1.0, true))
			if a > pire:
				pire = a
				ou = d2
		d2 += 0.5
	for i in range(1, n - 1):
		if _nature(lg.pylones[i]).begins_with("S") and not _nature(lg.pylones[i]).contains("C") and _nature(lg.pylones[i - 1]).begins_with("S") and _nature(lg.pylones[i + 1]).begins_with("S"):
			var moy2: float = (float(devs[i - 1]) + float(devs[i + 1])) * 0.5
			if moy2 > 6.0 and float(devs[i]) < 0.25 * moy2:
				_creux.append("%s P%d %.1f (voisins %.1f)" % [lg.name, i + 1, devs[i], moy2])
	var nez_a: float = _angle(lg, 0.0, 6.0, true)
	var nez_b: float = -_angle(lg, L - 6.0, 6.0, true)
	var dern: float = float(devs[n - 1])
	if maxf(absf(nez_a), absf(nez_b)) > ENTREE_MAX:
		_entrees.append("%s %.1f / %.1f" % [lg.name, nez_a, nez_b])
	if pire > FANTOME_MAX:
		_fantomes += 1
	_rangs.append([rupt, String(lg.name), ou_r + 1, pire, ou, mauvais, nez_a, nez_b, float(devs[0]), dern, n])


func _finir() -> void:
	if _csv != "":
		var f: FileAccess = FileAccess.open(_csv, FileAccess.WRITE)
		f.store_string("\n".join(_lignes))
		f.close()
	_rangs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	print("PROFIL %d lignes ; pylônes de mauvais signe : %d ; lignes à angle fantôme > %.1f° : %d" % [_rangs.size(), _pylones_mauvais_signe, FANTOME_MAX, _fantomes])
	print("ligne ; pire rupture de déviation (°) au pylône ; pire cassure hors galets (°) à d ; mauvais signes ; pente sortie aval, arrivée amont (°) ; dév. P1, dernier")
	for r in _rangs:
		print("   %-26s %5.1f P%-3d %5.2f à %5.0f  %d  %5.1f %5.1f  %5.1f %5.1f  (%d)" % [r[1], r[0], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]])
	print("SEUILS signes %d/%d : %s" % [_signes.size(), SIGNES_MAX, ", ".join(_signes)])
	print("SEUILS creux %d/%d : %s" % [_creux.size(), CREUX_MAX, ", ".join(_creux)])
	print("SEUILS entrées > %.0f° : %s" % [ENTREE_MAX, ", ".join(_entrees)])
	var ok: bool = _signes.size() <= SIGNES_MAX and _creux.size() <= CREUX_MAX and _entrees.is_empty() and _fantomes == 0
	print("BENCH_PROFIL_LIGNES " + ("OK" if ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if ok else 1)
