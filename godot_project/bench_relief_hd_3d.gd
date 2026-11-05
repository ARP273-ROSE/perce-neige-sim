## Banc du sol au mètre (pack haute définition) : les ouvrages restent sur le sol réglé.
## Compare hauteur_sol au sol à 5 m le long de chaque ligne et sur chaque aménagement, décode le pack
## et le raccord, et mesure le relevé au large.
##   godot --headless --path godot_project -s bench_relief_hd_3d.gd -- --mode=normal --relief-fin --garder-reference --pack-hd=DOSSIER
## Sans pack : rien à vérifier, le relief reste celui d'avant.
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


func _quantile(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b: PackedFloat32Array = a.duplicate()
	b.sort()
	return b[mini(int(q * b.size()), b.size() - 1)]


func _suite() -> void:
	while _main.relief == null or not _main.relief.pret:
		await process_frame
	var rel: ReliefBuilder = _main.relief
	if rel.fin == null or not rel.fin.hd:
		_check("sans pack : grille d'avant", rel.fin == null or ReliefFin.K == ReliefFin.KF, "K = %d" % ReliefFin.K)
		print("BENCH_RELIEF_HD %s" % ("OK" if _echecs == 0 else "ECHEC"))
		FinBanc.quitter(self, _main, 0 if _echecs == 0 else 1)
		return
	var niveau: int = rel.fin.niveau_pose
	_check("grille du niveau %d" % niveau, ReliefFin.K == (25 if niveau == 2 else 10) and ReliefFin.NJ == 843 * ReliefFin.K + 1 and ReliefFin.NI == 690 * ReliefFin.K + 1, "K = %d, %d × %d" % [ReliefFin.K, ReliefFin.NJ, ReliefFin.NI])
	# le pack se relit : altitudes plausibles, aucune hors de ce que relève l'IGN sur le domaine
	var g: PackedFloat32Array = rel.fin.noeuds_grille()
	var mi: float = INF
	var ma: float = -INF
	for k in range(0, g.size(), 997):
		mi = minf(mi, g[k])
		ma = maxf(ma, g[k])
	_check("altitudes du pack", mi > 1300.0 and ma < 3900.0, "%.0f à %.0f m (un nœud sur 997)" % [mi, ma])
	# référence : le relief au sol à 25 m recalé, et la grille à 5 m recalculée à part
	var ref: ReliefFin = ReliefFin.reference_5m(rel)
	_check("grille à 5 m de référence", ref != null, "")
	if ref == null:
		print("BENCH_RELIEF_HD ECHEC")
		FinBanc.quitter(self, _main, 1)
		return
	# couloirs : pieds de pylônes, gares, sol sous les véhicules
	var ecarts: PackedFloat32Array = PackedFloat32Array()
	var pire: float = 0.0
	var pire_nom: String = ""
	var large: PackedFloat32Array = PackedFloat32Array()
	for D in RemonteesDonnees.LIGNES:
		var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
		var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
		var L: float = a.distance_to(b)
		if L < 10.0:
			continue
		var u: Vector2 = (b - a) / L
		var lat: Vector2 = Vector2(-u.y, u.x)
		var demi: float = float(D["voie"]) * 0.5 + 5.0
		var t: float = -40.0
		while t <= L + 40.0:
			for x in [-demi, 0.0, demi]:
				var p: Vector2 = a + u * t + lat * x
				var e: float = absf(rel.fin.hauteur_grille(p.x, p.y) - ref.hauteur_grille(p.x, p.y))
				ecarts.append(e)
				if e > pire:
					pire = e
					pire_nom = String(D["cle"])
			# hors du couloir : le relevé
			var q: Vector2 = a + u * t + lat * (float(D["voie"]) * 0.5 + 60.0)
			large.append(absf(rel.fin.hauteur_grille(q.x, q.y) - ref.hauteur_grille(q.x, q.y)))
			t += 10.0
	_check("sol des lignes inchangé", pire < 0.02, "max %.3f m (%s), %d points" % [pire, pire_nom, ecarts.size()])
	_check("le relevé compte au large", _quantile(large, 0.5) > 0.02, "écart médian %.2f m, p99 %.2f m" % [_quantile(large, 0.5), _quantile(large, 0.99)])
	# aménagements (gares du funiculaire, galerie de secours)
	var pire_am: float = 0.0
	var n_am: int = 0
	for am in rel.amenagements:
		var r: Rect2 = am["rect"]
		var pire_r: float = 0.0
		for i in range(21):
			for j in range(21):
				var x2: float = r.position.x + r.size.x * j / 20.0
				var z2: float = r.position.y + r.size.y * i / 20.0
				pire_r = maxf(pire_r, absf(rel.fin.hauteur_grille(x2, z2) - ref.hauteur_grille(x2, z2)))
		print("  aménagement %s : %.3f m" % [str(r), pire_r])
		# (le tunnel à ski, à Pissaillas, est posé après coup, sur le sol affiché : il le suit)
		if not (r.position.x > 9000.0):
			pire_am = maxf(pire_am, pire_r)
			n_am += 1
	_check("sol des gares inchangé", pire_am < 0.02, "max %.3f m sur %d (le tunnel à ski suit le sol affiché)" % [pire_am, n_am])
	# pas de marche entre deux nœuds voisins dans les raccords : la pente reste celle du terrain
	var saut: float = 0.0
	var nj: int = ReliefFin.NJ
	for i in range(0, ReliefFin.NI - 1, 40):
		for j in range(0, nj - 1, 7):
			saut = maxf(saut, absf(g[i * nj + j + 1] - g[i * nj + j]))
	_check("pas de nœud aberrant", saut < 60.0, "plus grand écart entre voisins %.2f m (1 m de maille ; barres rocheuses comprises)" % saut)
	# collisions à pied, hors des couloirs : rayons contre le sol affiché
	_main.basculer_skieur()
	while not _main.mode_skieur or _main.collisions == null:
		await process_frame
	var col: CollisionsJeu = _main.collisions
	var pire_col: float = 0.0
	var manques: int = 0
	var nb_col: int = 0
	var espace: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	for centre in [Vector2(1800.0, 1500.0), Vector2(5000.0, -1000.0), Vector2(400.0, 1800.0), Vector2(-2000.0, 2000.0)]:
		var p0: Vector3 = Vector3(centre.x, rel.hauteur_sol(centre.x, centre.y), centre.y)
		col._sol_centre = Vector2i(-1073741824, 0)
		col.assurer_autour(p0)
		for i in range(6):
			await physics_frame
		espace = _main.get_world_3d().direct_space_state
		for a2 in range(-25, 26, 4):
			for b2 in range(-25, 26, 4):
				var x3: float = centre.x + a2 + 0.37
				var z3: float = centre.y + b2 + 0.61
				var h3: float = rel.hauteur_sol(x3, z3)
				var rq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x3, h3 + 5.0, z3), Vector3(x3, h3 - 5.0, z3), CollisionsJeu.COUCHE_RELIEF)
				var hit: Dictionary = espace.intersect_ray(rq)
				nb_col += 1
				if hit.is_empty():
					manques += 1
				else:
					pire_col = maxf(pire_col, absf((hit["position"] as Vector3).y - h3))
	_check("à pied, les collisions sont le sol affiché", manques == 0 and pire_col < 0.01, "écart max %.4f m, %d rayons, %d sans sol" % [pire_col, nb_col, manques])
	print("BENCH_RELIEF_HD %s" % ("OK" if _echecs == 0 else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _echecs == 0 else 1)
