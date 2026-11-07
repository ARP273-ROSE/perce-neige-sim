## Banc des pylônes visibles : on va au pied de chaque ligne du domaine (mode skieur), on attend qu'elle soit
## construite, puis on vérifie que CHAQUE pylône a de la géométrie dessinée à son pied, vue de 15 m au-dessus :
## un maillage visible (pylône ou fusion lointaine PylonesLoin) qui a des sommets à moins de 8 m de son axe et
## dont la portée de visibilité, mesurée depuis le centre de sa boîte comme le fait le rendu, couvre ce point.
## Contrôle juste construite, puis après des changements de détail (2, puis 0) : la revue des portées
## ramenait PylonesLoin à la portée des détails (P1 et P3 du 3S invisibles, retour du 07/11/2026).
## Compte aussi les pylônes construits contre ceux du tracé, ligne par ligne.
##   godot --fixed-fps 60 --path godot_project -s bench_pylones_visibles_3d.gd -- --mode=normal [--lignes=olympique,…]
##   (avec écran : construction sur un autre fil et prepa_contenu ; --headless : par tranches sur le fil principal)
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _i: int = -1
var _t: float = 0.0
var _lg: LigneRemontee = null
var _phase: int = 0
var _filtre: PackedStringArray = PackedStringArray()
var _nb_lignes: int = 0
var _nb_pyl: int = 0
var _manquants: Array = []

const VUE_AU_DESSUS: float = 15.0
const RAYON_AXE: float = 8.0
const CASE: float = 4.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lignes="):
			_filtre = a.trim_prefix("--lignes=").split(",", false)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _rm() -> Node:
	return _main.remontees


func _portees_revues() -> bool:
	return (_rm()._portees_a_revoir as Array).is_empty() and (_rm()._file_portees as Array).is_empty()


## Pylônes de la ligne (batteries des gares comprises pour la visibilité, pas pour le compte).
static func pylones_de(lg: Node) -> Array:
	var r: Array = []
	for c in lg.get_children():
		if c is PyloneRemontee or c is PyloneTreillis:
			r.append(c)
	return r


## Maillages qui peuvent dessiner un pylône : sous les pylônes et sous la fusion lointaine.
static func maillages_pylones(lg: Node) -> Array:
	var r: Array = []
	for c in lg.get_children():
		if c is PyloneRemontee or c is PyloneTreillis or String(c.name).begins_with(LigneRemontee.PYLONES_LOIN):
			for mi in (c as Node).find_children("*", "MeshInstance3D", true, false):
				r.append(mi)
	return r


## Cases (x, z) de CASE m occupées par les sommets d'un maillage, dans le repère du monde.
static func _cases(mi: MeshInstance3D) -> Dictionary:
	var cases: Dictionary = {}
	var xf: Transform3D = mi.global_transform
	for si in range(mi.mesh.get_surface_count()):
		var a: Array = mi.mesh.surface_get_arrays(si)
		if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null:
			continue
		for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var g: Vector3 = xf * v
			cases[Vector2i(floori(g.x / CASE), floori(g.z / CASE))] = true
	return cases


## Pylônes sans géométrie dessinée vue de VUE_AU_DESSUS m au-dessus de leur pied : [nom, raison].
static func pylones_invisibles(lg: Node) -> Array:
	var mail: Array = []
	for mi0 in maillages_pylones(lg):
		var mi: MeshInstance3D = mi0
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var c: Dictionary = _cases(mi)
		if c.is_empty():
			continue
		mail.append([mi, c, (mi.global_transform * mi.get_aabb()).get_center()])
	var r: Array = []
	var nr: int = ceili(RAYON_AXE / CASE)
	for py0 in pylones_de(lg):
		var py: Node3D = py0
		if not py.is_visible_in_tree():
			r.append([String(py.name), "nœud caché"])
			continue
		var pied: Vector3 = py.global_position
		var vue: Vector3 = pied + Vector3(0, VUE_AU_DESSUS, 0)
		var k: Vector2i = Vector2i(floori(pied.x / CASE), floori(pied.z / CASE))
		var a_geo: bool = false
		var vu: bool = false
		for e in mail:
			var pres: bool = false
			for dx in range(-nr, nr + 1):
				for dz in range(-nr, nr + 1):
					if (e[1] as Dictionary).has(k + Vector2i(dx, dz)):
						pres = true
			if not pres:
				continue
			a_geo = true
			var mi2: MeshInstance3D = e[0]
			var d: float = vue.distance_to(e[2])
			if (mi2.visibility_range_end <= 0.0 or d < mi2.visibility_range_end) and d >= mi2.visibility_range_begin:
				vu = true
				break
		if not vu:
			r.append([String(py.name), "portée trop courte" if a_geo else "aucune géométrie"])
	return r


## Pylônes construits (distincts par leur abscisse, hors batteries des gares) contre ceux du tracé.
static func compte(lg: LigneRemontee) -> Vector2i:
	var d: Dictionary = {}
	for py in pylones_de(lg):
		if String(py.name).begins_with("Batterie"):
			continue
		d[roundi((py as Node3D).position.z * 10.0)] = true
	return Vector2i(d.size(), lg.pylones.size())


func _controle(etape: String) -> void:
	var inv: Array = pylones_invisibles(_lg)
	var n: Vector2i = compte(_lg)
	var ok: bool = inv.is_empty() and n.x == n.y
	_ok = _ok and ok
	if etape == "construite":
		_nb_lignes += 1
		_nb_pyl += n.x
	var txt: String = ""
	for e in inv:
		txt += " %s (%s)" % [e[0], e[1]]
	if not ok:
		_manquants.append("%s/%s :%s%s" % [_lg.name, etape, txt, "" if n.x == n.y else " compte %d/%d" % [n.x, n.y]])
	print("%s %-30s %-12s pylônes %3d/%3d détail %d%s" % ["[OK]   " if ok else "[ECHEC]", _lg.nom_ligne, etape, n.x, n.y,
		int(_rm().niveau_detail), "" if inv.is_empty() else " invisibles :" + txt])


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	# (avec écran, le décor du skieur prend quelques secondes : avant, le saut vers la ligne est ignoré)
	if _f < _t0 + 60 or _main.skieur == null or not _main.skieur.actif:
		return
	var lignes: Array = _rm().lignes
	_t += 1.0 / 60.0
	match _phase:
		0:
			_i += 1
			while _i < lignes.size() and not _filtre.is_empty() and not String(lignes[_i][0].name) in _filtre:
				_i += 1
			if _i >= lignes.size():
				print("BILAN %d lignes, %d pylônes ; %d contrôles en échec" % [_nb_lignes, _nb_pyl, _manquants.size()])
				for m in _manquants:
					print("  MANQUE " + m)
				if _nb_lignes == 0:
					_ok = false
				print("BENCH_PYLONES_VISIBLES " + ("OK" if _ok else "ECHEC"))
				FinBanc.quitter(self, _main, 0 if _ok else 1)
				return
			_lg = lignes[_i][0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if _lg.pret and _portees_revues():
				_controle("construite")
				_rm().set_niveau_detail(2 if int(_rm().niveau_detail) != 2 else 1)
				_phase = 2
				_t = 0.0
			elif _t > 180.0:
				print("[ECHEC] %s : pas construite en 180 s (prête %s, portées à revoir %d + %d, en cours %s)" % [_lg.nom_ligne,
					_lg.pret, (_rm()._portees_a_revoir as Array).size(), (_rm()._file_portees as Array).size(),
					str(_rm()._en_cours.name) if _rm()._en_cours != null else "-"])
				_ok = false
				_phase = 0
		2:
			if _t > 0.2 and _portees_revues():
				_controle("détail %d" % int(_rm().niveau_detail))
				_rm().set_niveau_detail(0)
				_phase = 3
				_t = 0.0
		3:
			if _t > 0.2 and _portees_revues():
				_controle("détail 0")
				_phase = 0
