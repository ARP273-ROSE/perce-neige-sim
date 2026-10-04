# Banc du PerfManager (04/10/2026) : réglages selon la machine et
# ajustement en direct contre les saccades, sur des durées d'image
# synthétiques (pas de rendu). Exécution :
#   godot --headless --path godot_project -s bench_perf_3d.gd
extends SceneTree

var _ok := true


func _check(nom: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[FAIL]", nom, detail])
	_ok = _ok and cond


func _fenetre(pm: PerfManager, ips: float, acoups: int) -> void:
	# une fenêtre de 2 s à `ips` images/s dont `acoups` images doublées
	pm._durees.clear()
	var n: int = int(2.0 * ips)
	for i in range(n):
		pm._durees.append(2.1 / 60.0 if i < acoups else 1.0 / ips)
	pm._t_fen = 2.0
	pm._horloge += 2.0
	pm._evaluer()


func _initialize() -> void:
	var env := Environment.new()
	var pm := PerfManager.new()
	get_root().add_child(pm)
	pm.setup(get_root(), env, "auto")
	pm.machine["hz"] = 60.0

	# 1. Profils de départ
	pm._rd = true
	pm.cran_min = 0
	var cas := {"dedie": 0, "integre": 2, "logiciel": 5, "apple": 1}
	for t in cas:
		pm.machine["type"] = t
		pm.machine["ram_go"] = 8.0
		pm.machine["coeurs"] = 4
		pm.machine["ecran"] = Vector2i(1920, 1080)
		_check("départ « %s »" % t, pm._cran_de_depart() == cas[t], "cran %d" % pm._cran_de_depart())
	pm.machine["type"] = "integre"
	pm.machine["ram_go"] = 32.0
	pm.machine["coeurs"] = 12
	_check("intégrée costaude", pm._cran_de_depart() == 1, "cran %d" % pm._cran_de_depart())
	pm.machine["type"] = "dedie"
	pm.machine["ecran"] = Vector2i(3840, 2160)
	_check("écran 4K : rendu réduit", pm._cran_de_depart() == 3, "cran %d" % pm._cran_de_depart())
	pm.machine["ecran"] = Vector2i(1920, 1080)

	# 2. Saccades → un cran de moins
	pm._appliquer(1, "test")
	_fenetre(pm, 60.0, 0)
	_check("fluide : on garde", pm.cran == 1, pm.dernier_bilan)
	_fenetre(pm, 58.0, 8)        # 8 à-coups sur 116 images (7 %)
	_check("à-coups : un cran de moins", pm.cran == 2, pm.dernier_bilan)
	_check("effets coupés au cran 2", not env.volumetric_fog_enabled and not env.ssr_enabled
		and not env.sdfgi_enabled, "fog=%s ssr=%s" % [env.volumetric_fog_enabled, env.ssr_enabled])
	_fenetre(pm, 38.0, 0)
	_check("trop lent : encore un cran", pm.cran == 3, pm.dernier_bilan)

	# 3. Marge durable → on remonte (sans temps GPU : 20 fenêtres = 40 s)
	for i in range(19):
		_fenetre(pm, 60.0, 0)
	_check("pas de remontée trop tôt", pm.cran == 3, "après 38 s")
	_fenetre(pm, 60.0, 0)
	_check("remontée après 40 s fluides", pm.cran == 2, pm.dernier_bilan)

	# 4. Le cran regagné ne tient pas → retour, et interdit 3 min
	_fenetre(pm, 40.0, 0)
	_check("échec de la remontée", pm.cran == 3, pm.dernier_bilan)
	for i in range(40):
		_fenetre(pm, 60.0, 0)
	_check("cran échoué non retenté avant 3 min", pm.cran == 3, "après 80 s fluides")
	for i in range(60):
		_fenetre(pm, 60.0, 0)
	_check("retenté après 3 min", pm.cran == 2, "cran %d" % pm.cran)

	# 5. Mode forcé : pas d'ajustement
	pm.set_mode("high")
	_check("mode haute : cran 0", pm.cran == 0, "cran %d" % pm.cran)
	_fenetre(pm, 20.0, 30)
	_check("mode forcé : pas de baisse", pm.cran == 0, pm.dernier_bilan)
	pm.set_mode("auto")

	# 6. Cadence verrouillée au dernier cran
	pm._appliquer(6, "test")
	_check("cran 6 : 30 i/s", Engine.max_fps == 30, "max_fps %d" % Engine.max_fps)
	pm._appliquer(2, "test")
	_check("retour : cadence libre", Engine.max_fps == 0, "max_fps %d" % Engine.max_fps)

	print("BENCH_PERF %s" % ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
