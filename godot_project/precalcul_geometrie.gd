## Géométrie des lignes calculée UNE FOIS (demande d'un utilisateur, 28/10/2026 :
## « tu fais les calculs une fois pour toute, ensuite le jeu fait juste les
## calculs de mouvement ») : hauteur des têtes de pylônes réglée pour toute la
## ligne à la fois — capacité des galets relevés (LigneRemontee._capacite),
## sens des balanciers (support saillant, compression creuse), garde au sol,
## hauteurs de 6,5 à 36 m, au plus près du calcul de départ (qui tient compte
## des traces GPS). Écrit data/remontees/geometrie.json ; exporter_jeu.py
## (dossier des remontées) le reporte dans scripts/remontees_donnees.gd.
##   godot --headless --path godot_project -s precalcul_geometrie.gd -- --mode=normal
## En parallèle : `--part=k/N` (k de 1 à N) ne traite qu'une ligne sur N et écrit
## data/remontees/geometrie_k.json ; on réunit ensuite les morceaux.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _f0: int = 0
var _fait: bool = false

const POIDS_DEV: float = 1.0e4          # (rad²) : 0,1 rad de trop → 100
const POIDS_GARDE: float = 10.0         # (m²) : 1 m sous la garde → 10
const POIDS_ECART: float = 0.002        # (m²) : 10 m d'écart au départ → 0,2


func _initialize() -> void:
	LigneRemontee.ignorer_precalcul = true
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
	_calculer()


func _calculer() -> void:
	var k_part: int = 0
	var n_part: int = 1
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--part="):
			var t: PackedStringArray = String(a).substr(7).split("/")
			k_part = int(t[0]) - 1
			n_part = maxi(int(t[1]), 1)
	var rang: int = -1
	var sortie: Dictionary = {}
	var bilan: Array = [0, 0, 0, 0]     # [pylônes hors limites avant, après, portées sous la garde avant, après]
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if lg.teleski() or lg.tricable() or lg.vaetvient():
			continue
		rang += 1
		if rang % n_part != k_part:
			continue
		lg.progressif = false
		lg.H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(lg.famille)
		lg.l_gare = lg.l_gare_pour(lg.famille)
		await lg._calculer_tetes()
		lg._preparer_nez()
		var av: Array = _defauts(lg)
		_optimiser(lg)
		var ap: Array = _defauts(lg)
		bilan[0] += av[0]
		bilan[1] += ap[0]
		bilan[2] += av[1]
		bilan[3] += ap[1]
		var l: Array = []
		for i in range(lg.pylones.size()):
			var p: Dictionary = lg.pylones[i]
			var q: Dictionary = {"k": int(p["k"]), "h": snappedf(lg._tetes[i] - lg.terrain(float(p["d"])), 0.01)}
			if lg.balanciers_estimes:
				q["montee"] = p.get("montee")
				q["descente"] = p.get("descente")
			l.append(q)
		sortie[String(lg.name)] = l
		print("%-26s pylônes hors limites %2d → %2d · portées sous la garde %2d → %2d" % [lg.name, av[0], ap[0], av[1], ap[1]])
	var nom: String = "geometrie.json" if n_part == 1 else "geometrie_%d.json" % (k_part + 1)
	var f := FileAccess.open("res://data/remontees/" + nom, FileAccess.WRITE)
	f.store_string(JSON.stringify(sortie, " ", true))
	print("BILAN pylônes hors limites %d → %d · portées sous la garde %d → %d" % bilan)
	quit(0)


## Bornes de déviation (rad) d'un pylône : [mini, maxi].
func _bornes(lg: LigneRemontee, i: int) -> Array:
	var cap: Array = lg._capacite(lg.pylones[i])
	if float(cap[1]) <= 0.0:
		return [LigneRemontee.DEVIATION_MIN, float(cap[0])]         # support
	if float(cap[0]) <= 0.0:
		return [-float(cap[1]), -0.002]                              # compression
	return [-float(cap[1]), float(cap[0])]                           # support/compression


func _pen_dev(lg: LigneRemontee, i: int) -> float:
	if i < 0 or i >= lg.pylones.size():
		return 0.0
	var b: Array = _bornes(lg, i)
	var v: float = 0.0
	for m in [true, false]:
		var d: float = lg.deviation_pylone(i, m)
		v += pow(maxf(0.0, float(b[0]) - d), 2.0) + pow(maxf(0.0, d - float(b[1])), 2.0)
	return POIDS_DEV * v


func _pen_garde(lg: LigneRemontee, k: int) -> float:
	if k < 0 or k > lg.pylones.size():
		return 0.0
	return POIDS_GARDE * pow(maxf(0.0, -lg._garde_portee(k)), 2.0)


func _cout_local(lg: LigneRemontee, i: int, h0: Array) -> float:
	return _pen_dev(lg, i - 1) + _pen_dev(lg, i) + _pen_dev(lg, i + 1) \
		+ _pen_garde(lg, i) + _pen_garde(lg, i + 1) \
		+ POIDS_ECART * pow(float(lg._tetes[i]) - float(h0[i]), 2.0)


## Descente coordonnée : chaque tête bouge de ±pas tant que le coût local
## baisse, pas de 8 m à 0,25 m.
func _optimiser(lg: LigneRemontee) -> void:
	var n: int = lg.pylones.size()
	var h0: Array = lg._tetes.duplicate()
	var lo: Array = []
	var hi: Array = []
	for i in range(n):
		var p: Dictionary = lg.pylones[i]
		var t: float = lg.terrain(float(p["d"]))
		lo.append(t + float(p.get("h_min", 6.5)))
		hi.append(t + float(p.get("h_max", 36.0)))
	for pas in [8.0, 4.0, 2.0, 1.0, 0.5, 0.25]:
		for balayage in range(60):
			var mieux: bool = false
			for i in range(n):
				var base: float = _cout_local(lg, i, h0)
				var h: float = lg._tetes[i]
				for s in [pas, -pas]:
					var hn: float = clampf(h + s, lo[i], hi[i])
					if absf(hn - h) < 1e-4:
						continue
					lg._tetes[i] = hn
					var c: float = _cout_local(lg, i, h0)
					if c < base - 1e-9:
						base = c
						h = hn
						mieux = true
					else:
						lg._tetes[i] = h
			if not mieux:
				break
		lg._preparer_nez()


## [pylônes hors de leurs bornes de déviation, portées sous la garde].
func _defauts(lg: LigneRemontee) -> Array:
	var hors: int = 0
	for i in range(lg.pylones.size()):
		if _pen_dev(lg, i) > POIDS_DEV * pow(0.0026, 2.0):          # (0,15° de tolérance)
			hors += 1
	var sous: int = 0
	for k in range(lg.pylones.size() + 1):
		if lg._garde_portee(k) < -0.3:
			sous += 1
	return [hors, sous]
