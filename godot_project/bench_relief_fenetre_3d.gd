## Banc de la fenêtre fine du relief (PWA, maille à 50 m) : sans écran, au cran 5 (maille à 50 m comme sur le web).
## Sans --relief-fenetre : triangles du bloc de référence. Avec --relief-fenetre=R : fenêtre posée au pied des pistes,
## puis déplacée de 1 km ; relevés : pire temps d'une image de reconstruction, nombre d'images, triangles du bloc ;
## sol au centre = grille à 25 m, sol loin de la fenêtre = sol de référence.
##   godot --headless --path godot_project -s bench_relief_fenetre_3d.gd -- --cran=5 [--relief-fenetre=1500]
extends SceneTree

var _main: Node = null
var _f: int = 0
var _etat: int = 0
var _ok: bool = true
var _t0: int = 0
var _loin: Vector2 = Vector2(5000.0, -3000.0)


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _tri_bloc(r: ReliefBuilder) -> int:
	var n: int = 0
	for c in r.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh and (c as MeshInstance3D).material_override == null:
			var m: ArrayMesh = (c as MeshInstance3D).mesh
			if m.get_surface_count() > 0 and m.surface_get_material(0) == r._mat_terrain:
				n += m.surface_get_array_index_len(0) / 3
	return n


func _tick() -> void:
	_f += 1
	var r: ReliefBuilder = _main.get("relief")
	if r == null or not r.pret:
		if _f > 60 * 600:
			_verif("relief prêt", false)
			_fin()
		return
	match _etat:
		0:
			print("[Relief] maille %d m, fenêtre %.0f m" % [25 * r._pas, ReliefBuilder.FENETRE])
			var h_loin: float = r.hauteur_sol(_loin.x, _loin.y)
			_main.set_meta("h_loin", h_loin)
			print("BANC triangles du bloc (référence ou fenêtre initiale) : %d" % _tri_bloc(r))
			if ReliefBuilder.FENETRE <= 0.0 or r._pas < 2:
				_fin()
				return
			# domaine skiable (jalons, panneaux) posé comme à l'entrée en skieur, puis la fenêtre
			_main._poser_domaine()
			_etat = 3
		3:
			var dom0: Node = _main.get("domaine")
			if dom0 == null or dom0.get("_racine_numeros") == null:
				return
			ReliefBuilder.cible_fenetre = Vector3(-134.0, 0.0, 534.0)      # pied des pistes (Val Claret)
			_t0 = Time.get_ticks_msec()
			_etat = 1
		1, 2:
			if not r._f_job.is_empty() or r._f_centre == Vector2.INF:
				return
			var dom: Node = _main.get("domaine")
			if dom != null and not (dom.get("_repose") as Array).is_empty():
				return
			var c: Vector2 = r._f_centre
			var st: Dictionary = r.fenetre_stats
			# jalons dans la fenêtre : pied sur le sol affiché
			if dom != null:
				var pire: float = 0.0
				var n_j: int = 0
				for lot in dom.get("_lots_sol"):
					if not (lot[0] as Rect2).has_area():
						continue
					# (sans écran, le MultiMesh ne se relit pas : la position que la repose y écrit, d'après l'origine gardée)
					for xf in lot[2]:
						var o: Vector3 = (dom.call("_decale", xf) as Transform3D).origin
						if Vector2(o.x, o.z).distance_to(c) > ReliefBuilder.FENETRE + 100.0:
							continue
						n_j += 1
						pire = maxf(pire, absf(o.y - DomaineSkiable.H_JALON * 0.5 - r.hauteur_sol(o.x, o.z)))
				_verif("fenêtre %d : jalons posés sur le sol affiché" % _etat, pire < 0.05 and n_j > 0,
					"%d jalons dans la fenêtre, pire écart %.3f m, repose pire tranche %.2f ms" % [n_j, pire, float(dom.get("repose_max_us")) / 1000.0])
			print("BANC fenêtre %d : %s" % [_etat, str(st)])
			_verif("fenêtre %d : reconstruction par tranches (pire image ≤ 4 ms sur ce PC)" % _etat, float(st["pire_ms"]) <= 4.0,
				"pire %.1f ms, %d images, %d tuiles, %d mailles" % [st["pire_ms"], st["images"], st["tuiles"], st["mailles"]])
			var h: float = r.hauteur_sol(c.x + 7.0, c.y + 11.0)
			var h25: float = r._tri_sur(r._h25, c.x + 7.0, c.y + 11.0, 1)
			_verif("fenêtre %d : sol au centre = grille à 25 m" % _etat, absf(h - h25) < 0.01, "écart %.3f m" % absf(h - h25))
			var hl: float = r.hauteur_sol(_loin.x, _loin.y)
			_verif("fenêtre %d : sol loin de la fenêtre inchangé" % _etat, absf(hl - float(_main.get_meta("h_loin"))) < 0.001,
				"écart %.4f m" % absf(hl - float(_main.get_meta("h_loin"))))
			# sous les lignes : pylônes calculés sur hauteur_ligne (grille à 25 m) ; dans la fenêtre, le sol affiché les rejoint
			var pire_l: float = 0.0
			var rr: float = ReliefBuilder.FENETRE - ReliefBuilder.FENETRE_FONDU - 30.0
			for gx in range(-20, 21):
				for gz in range(-20, 21):
					var q: Vector2 = c + Vector2(gx, gz) * (rr / 20.0)
					if q.distance_to(c) <= rr:
						pire_l = maxf(pire_l, absf(r.hauteur_sol(q.x, q.y) - r.hauteur_ligne(q.x, q.y)))
			_verif("fenêtre %d : sol affiché = sol des lignes (pieds de pylône)" % _etat, pire_l < 0.05, "pire écart %.3f m" % pire_l)
			print("BANC triangles du bloc : %d" % _tri_bloc(r))
			if _etat == 1:
				ReliefBuilder.cible_fenetre = Vector3(-134.0 + 1000.0, 0.0, 534.0)
				_etat = 2
			else:
				_fin()


func _fin() -> void:
	print("BENCH_RELIEF_FENETRE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
