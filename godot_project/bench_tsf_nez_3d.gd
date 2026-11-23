## Banc des sorties de gare des TSF (retour d'utilisateur, 23/11/2026 : « le premier pylône n'était pas compression mais
## support et était trop loin, donc un angle fantôme après le départ ») : sur chaque télésiège à pinces fixes, aux deux
## gares, avec un pylône de nez, le câble sort à l'horizontale (avant : 5 à 9° de pente sans un galet) ; là où la ligne
## monte, ce pylône est une COMPRESSION collée à la gare (≤ 16 m), en angle creux ; un porteur, en angle saillant.
## Sans pylône de nez, la batterie de galets du nez de gare fait le raccord.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_tsf_nez_3d.gd
extends SceneTree

var _main: Node = null
var _f: int = 0
var _f0: int = 0
var _fait: bool = false
var _ok: bool = true


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


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
	var n: int = 0
	for e in _main.remontees.lignes:
		var lg: LigneRemontee = e[0]
		if not lg.famille.begins_with("siege_fixe"):
			continue
		n += 1
		lg.progressif = false
		lg.H_CABLE_GARE = VehiculeRemontee.hauteur_cable_gare(lg.famille)
		lg.l_gare = lg.l_gare_pour(lg.famille)
		await lg._calculer_tetes()
		lg._preparer_nez()
		lg._compressions_appuyees()
		var L: float = lg.longueur_h()
		for aval in [true, false]:
			var i: int = 0 if aval else lg.pylones.size() - 1
			var p: Dictionary = lg.pylones[i]
			var c: bool = lg._compression(p)
			var dist: float = float(p["d"]) if aval else L - float(p["d"])
			var dev: float = maxf(lg.deviation_pylone(i, true), lg.deviation_pylone(i, false)) if c \
				else minf(lg.deviation_pylone(i, true), lg.deviation_pylone(i, false))
			var sortie: float = rad_to_deg(atan(lg._pente_nez(aval, true)))
			var nom: String = "%s %s" % [lg.name, "aval" if aval else "amont"]
			if not lg._nez_par_pylone[0 if aval else 1] or lg._h_nez[0 if aval else 1] > 0.0:
				# (pas de pylône de nez : la batterie du nez de gare fait le raccord, en compression si la ligne monte)
				_verif("%s : batterie de nez de gare" % nom, lg._h_nez[0 if aval else 1] > 0.0 or absf(sortie) < 1.0,
					"P%d à %.0f m, pente de sortie %.1f°" % [i + 1, dist, sortie])
				continue
			# pylône de nez : le câble sort de la gare à l'horizontale (pas d'angle hors des galets) ; compression
			# collée à la gare et en angle creux, ou porteur en angle saillant
			_verif("%s : sortie à l'horizontale, %s à %.1f m, angle %s" % [nom, "compression" if c else "porteur", dist,
				"creux" if c else "saillant"], absf(sortie) < 1.5 and ((dev < 0.0 and dist <= LigneRemontee.NEZ_TSF_C + 1.0)
				if c else dev > 0.0), "pente de sortie %.1f°, déviation %.1f°" % [sortie, rad_to_deg(dev)])
	_verif("TSF trouvés", n >= 10, str(n))
	print("BENCH_TSF_NEZ " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if _ok else 1)
