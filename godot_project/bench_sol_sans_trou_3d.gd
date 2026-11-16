## Banc : pas de trou dans le sol autour des gares (16/11/2026 : chute sans fin au pied du téléphérique de la Grande
## Motte, terrain percé sous un bâtiment sans plancher dessous). Pour chaque gare des remontées (aval et amont) et les
## deux gares du Perce-Neige : grille de rayons verticaux au pas de 0,25 m dans un disque de 35 m, de 40 m au-dessus du
## sol jusqu'à 80 m plus bas, masque de collision du skieur. Tous les rayons sans AUCUNE collision sont comptés ; échec
## s'il existe un trou praticable : un rayon perdu dont un voisin à 0,25 m est perdu aussi, en x ET en z (au moins
## 50 × 50 cm). Les rayons perdus isolés (fentes de moins de 25 cm au bord d'une emprise de bâtiment, au pas du masque)
## ne peuvent pas avaler la capsule du skieur (60 cm) : signalés, pas en échec.
## Sortie : nombre de rayons perdus et trous regroupés au mètre (monde et repère de la ligne), par gare.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_sol_sans_trou_3d.gd -- [--filtre=tph] [--pas=0.25]
extends SceneTree

const RAYON: float = 35.0
const PAR_IMAGE: int = 25000

var _main: Node
var _f: int = 0
var _ok: bool = true
var _pas: float = 0.25
var _filtre: String = ""
var _gares: Array = []          # [nom, ligne ou null, amont ?, centre monde]
var _ig: int = -1
var _etat: String = "attente"
var _att: int = 0
var _pts: PackedVector2Array = PackedVector2Array()
var _idx: Array = []
var _k: int = 0
var _trous: Dictionary = {}     # cellule de 1 m → nombre
var _n_trous: int = 0
var _y_haut: float = 0.0
var _total: int = 0
var _gares_ko: int = 0
var _perdus: Dictionary = {}    # indice du point de grille (Vector2i) → vrai
var _n_prat: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filtre="):
			_filtre = a.substr(9)
		elif a.begins_with("--pas="):
			_pas = float(a.substr(6))
	LigneRemontee.construction_en_fond = false
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	var r: float = -RAYON
	while r <= RAYON:
		var c: float = -RAYON
		while c <= RAYON:
			if r * r + c * c <= RAYON * RAYON:
				# (décalage d'un centième : pas de rayon pile sur une arête de maille)
				_pts.append(Vector2(c + 0.0137, r + 0.0091))
				_idx.append(Vector2i(roundi((c + RAYON) / _pas), roundi((r + RAYON) / _pas)))
			c += _pas
		r += _pas
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	if _main.get("perf_manager") != null:
		_main.perf_manager.banc = true
	if _main.get("relief") == null or not _main.relief.pret or _f < 30:
		return
	var sk: SkieurJoueur = _main.get("skieur")
	match _etat:
		"attente":
			_main.basculer_skieur()
			_etat = "liste"
		"liste":
			if sk == null or not sk.actif or _main.get("remontees") == null:
				return
			for s in [0.0, PNConstants.LENGTH]:
				_gares.append(["perce_neige_" + ("aval" if s == 0.0 else "amont"), null, s > 0.0, _main.tunnel.transform_at(s).origin])
			for e in _main.remontees.lignes:
				var lg: LigneRemontee = e[0]
				for am in [false, true]:
					_gares.append([String(lg.name) + ("_amont" if am else "_aval"), lg, am, Vector3.ZERO])
			if _filtre != "":
				_gares = _gares.filter(func(g): return String(g[0]).contains(_filtre))
			print("SOL %d gares, %d rayons par gare (pas %.2f m, rayon %.0f m)" % [_gares.size(), _pts.size(), _pas, RAYON])
			_suivante()
		"place":
			_att += 1
			var g: Array = _gares[_ig]
			var lg: LigneRemontee = g[1]
			var occupe: bool = _main.remontees._en_cours != null or not _main.collisions._taches.is_empty()
			if (_att < 180 or (lg != null and not lg.pret) or occupe) and _att < 6000:
				return
			if _att >= 6000:
				print("   (attente dépassée : %s)" % g[0])
			_y_haut = _main.relief.hauteur_sol(g[3].x, g[3].z) + 40.0
			_k = 0
			_trous = {}
			_n_trous = 0
			_perdus = {}
			_etat = "rayons"
		"rayons":
			var g: Array = _gares[_ig]
			var c: Vector3 = g[3]
			var sp: PhysicsDirectSpaceState3D = sk.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.new()
			q.exclude = [sk.get_rid()]
			q.collision_mask = sk.collision_mask
			var fin: int = mini(_k + PAR_IMAGE, _pts.size())
			while _k < fin:
				var p: Vector2 = _pts[_k]
				q.from = Vector3(c.x + p.x, _y_haut, c.z + p.y)
				q.to = q.from + Vector3.DOWN * 80.0
				if sp.intersect_ray(q).is_empty():
					_n_trous += 1
					_perdus[_idx[_k]] = true
					var cle: Vector2i = Vector2i(floori(c.x + p.x), floori(c.z + p.y))
					_trous[cle] = int(_trous.get(cle, 0)) + 1
				_k += 1
			if _k >= _pts.size():
				_bilan_gare()
				_suivante()


func _centre(g: Array) -> Vector3:
	var lg: LigneRemontee = g[1]
	if lg == null:
		return g[3]
	var xf: Transform3D = lg.global_transform
	var L: float = lg.longueur_h()
	var p: Vector3 = xf * (Vector3(0, 0, -L - 8.0) if bool(g[2]) else Vector3(0, 0, 8.0))
	p.y = _main.relief.hauteur_sol(p.x, p.z)
	return p


func _suivante() -> void:
	_ig += 1
	if _ig >= _gares.size():
		print("BILAN SOL : %d gare(s) avec des trous sur %d, %d rayons tirés" % [_gares_ko, _gares.size(), _total])
		print("BENCH_SOL_SANS_TROU " + ("OK" if _ok else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if _ok else 1)
		return
	var g: Array = _gares[_ig]
	g[3] = _centre(g)
	var sk: SkieurJoueur = _main.skieur
	var lg: LigneRemontee = g[1]
	if lg != null and not bool(g[2]):
		_main.aller_a_remontee(lg)
	else:
		var p: Vector3 = g[3] + Vector3(0, 0.5, 0)
		_main.remontees.quitter()
		sk.activer(p, 0.0)
		sk.support = null
		sk.refuge = p
		sk.dernier_sol = p
	# collisions du relief sur tout le disque
	for d in [Vector3.ZERO, Vector3(RAYON, 0, 0), Vector3(-RAYON, 0, 0), Vector3(0, 0, RAYON), Vector3(0, 0, -RAYON)]:
		_main.collisions.assurer_autour(g[3] + d)
	_att = 0
	_etat = "place"


func _bilan_gare() -> void:
	var g: Array = _gares[_ig]
	_total += _pts.size()
	if _n_trous == 0:
		print("[OK]   %s — 0 trou (%d rayons)" % [g[0], _pts.size()])
		return
	# trous praticables : un voisin perdu en x et un en z
	var prat: Dictionary = {}
	for i in _perdus:
		var v: Vector2i = i
		if (_perdus.has(v + Vector2i(1, 0)) or _perdus.has(v - Vector2i(1, 0))) \
				and (_perdus.has(v + Vector2i(0, 1)) or _perdus.has(v - Vector2i(0, 1))):
			prat[v] = true
	if prat.is_empty():
		print("[OK]   %s — %d rayon(s) perdu(s) isolé(s), aucun trou praticable" % [g[0], _n_trous])
		return
	_ok = false
	_gares_ko += 1
	print("   %s : %d point(s) de trou praticable" % [g[0], prat.size()])
	var lg: LigneRemontee = g[1]
	var cles: Array = _trous.keys()
	cles.sort_custom(func(a, b): return _trous[a] > _trous[b])
	var l: PackedStringArray = PackedStringArray()
	for cl in cles.slice(0, 8):
		var w: Vector3 = Vector3(cl.x + 0.5, _main.relief.hauteur_sol(cl.x + 0.5, cl.y + 0.5), cl.y + 0.5)
		var loc: String = ""
		if lg != null:
			var q: Vector3 = lg.global_transform.affine_inverse() * w
			loc = " ligne x %.1f z %.1f" % [q.x, q.z]
		l.append("(%d, %d)%s ×%d" % [cl.x, cl.y, loc, _trous[cl]])
	print("[ECHEC] %s — %d rayons sans collision, %d m² touchés : %s" % [g[0], _n_trous, _trous.size(), " ; ".join(l)])
