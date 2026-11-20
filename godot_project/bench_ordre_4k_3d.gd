## Banc de l'ordre des crans sur écran très défini (retour d'utilisateur du 20/11/2026, portable 4K : GTX 1050 Ti
## Max-Q 4 Go, écran 4K, parti au cran 5 à 30 i/s) : en 4K sur carte dédiée modeste, la résolution du rendu baisse
## avant les effets (85 % puis 70 %) ; ≤ 2560×1600, jamais sous 85 % avant le cran 6 ; carte puissante en 4K
## (RTX 5070 Ti 16 Go, PC fixe) : cran 0 à 100 %. Logique seule, machines simulées.
extends SceneTree
var _ok: bool = true


func _verif(nom: String, cond: bool) -> void:
	print("%s %s" % ["[OK]  " if cond else "[ECHEC]", nom])
	if not cond:
		_ok = false


func _machine(ecran: Vector2i, vram: float, web: bool = false) -> PerfManager:
	var pm: PerfManager = PerfManager.new()
	pm.machine = {"ecran": ecran, "hz": 60.0, "type": "dedie"}
	PerfManager.type_gpu = "dedie"
	pm._web = web
	pm._rd = true
	pm.vram_simulee = vram
	return pm


func _initialize() -> void:
	# portable : 4K, 4 Go
	var k: PerfManager = _machine(Vector2i(3840, 2160), 4.0)
	_verif("portable : ordre 4K", k.ordre_4k())
	var d: int = k._cran_carte_dediee()
	_verif("portable : départ au cran 2 (rendu 70 %%, tous les effets) — %d" % d, d == 2)
	_verif("portable : cran 1 = 85 %, effets intacts", is_equal_approx(k._echelle(1), 0.85) and k._cran_effets(1) == 0)
	_verif("portable : cran 2 = 70 %, effets intacts", is_equal_approx(k._echelle(2), 0.7) and k._cran_effets(2) == 0)
	_verif("portable : éclairage indirect coupé seulement au cran 3", k._cran_effets(3) == 1)
	_verif("portable : 30 i/s seulement au dernier cran", k._ips_30(7) and not k._ips_30(6))
	var echelles_ok: bool = true
	for c in range(8):
		echelles_ok = echelles_ok and k._echelle(c) >= 0.7 - 1e-6
	_verif("portable : jamais sous 70 %", echelles_ok)
	# PC fixe : 4K, 16 Go
	var a: PerfManager = _machine(Vector2i(3840, 2160), 16.0)
	_verif("PC fixe : départ au cran 0 à 100 %", a._cran_carte_dediee() == 0 and is_equal_approx(a._echelle(0), 1.0) and a._cran_effets(0) == 0)
	# 1440p, 4 Go : ordre habituel
	var q: PerfManager = _machine(Vector2i(2560, 1440), 4.0)
	_verif("1440p : ordre habituel", not q.ordre_4k() and q._cran_carte_dediee() == 3)
	var jamais: bool = true
	for c in range(6):
		jamais = jamais and is_equal_approx(q._echelle(c), 1.0)
	_verif("1440p : 100 % jusqu'au cran 5, 85 % au cran 6", jamais and is_equal_approx(q._echelle(6), 0.85) and q._ips_30(5) and not q._ips_30(4))
	# 2560×1600 pile : pas « très défini »
	_verif("2560×1600 : ordre habituel", not _machine(Vector2i(2560, 1600), 4.0).ordre_4k())
	# PWA : inchangée
	var w: PerfManager = _machine(Vector2i(3840, 2160), 4.0, true)
	_verif("PWA : ordre habituel, 30 i/s au cran 6", not w.ordre_4k() and w._ips_30(6) and not w._ips_30(5))
	for pm in [k, a, q, w]:
		pm.free()
	print("BENCH_ORDRE_4K " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
