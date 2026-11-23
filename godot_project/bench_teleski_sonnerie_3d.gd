## Banc des téléskis (retours d'utilisateur, 23/11/2026) : skieurs tirés seulement sur le brin MONTANT (« des skieurs
## auto en descente de TKE et TKD, pas possible de descendre avec ça » : leur filtre se fiait au signe de x, faux là où
## l'axe est décalé ou la poulie excentrée), et sonnerie de remise en route (« un buzzer dans les deux gares avant la
## remise en route ») : la ligne ne repart qu'au bout de LigneRemontee.T_SONNERIE, buzzer joué à la gare.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_teleski_sonnerie_3d.gd [-- tkd_3000]
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _ok: bool = true
var CLE: String = "tkd_3000"
var _d0: Dictionary = {}
var _n_mesures: int = 0
var _n_desc: int = 0
var _t_dem: float = 0.0
var _vu_sonnerie: bool = false
var _marche_pendant: bool = false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			CLE = a
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond

func _fin() -> void:
	print("BENCH_TELESKI_SONNERIE " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, get("_main"), 0 if _ok else 1)

func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60 or not _main.mode_skieur:
		return
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == CLE:
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret or _t < 3.0:
				return
			# skieur au milieu de la ligne, pour voir les perches des deux brins
			var L: float = _lg.longueur_h()
			var pm: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(L * 0.3) + 1.0, -L * 0.3)
			_main.skieur.global_position = pm
			_phase = 2
			_t = 0.0
		2:
			if _t < 2.0:
				return
			# abscisse le long de la ligne des véhicules tirés, deux fois à 0,5 s : elle doit croître (brin montant)
			if _d0.is_empty():
				for k in range(_lg.tires_indices.size()):
					var i: int = _lg.tires_indices[k]
					_d0[i] = -(_lg.to_local(_lg.vehicule(i).global_position)).z
				if _d0.is_empty() and _t > 8.0:
					_verif("skieurs tirés dessinés près du skieur", false)
					_phase = 3
				return
			if _t < 6.0:
				return
			for i in _d0:
				var d1: float = -(_lg.to_local(_lg.vehicule(i).global_position)).z
				_n_mesures += 1
				if d1 <= float(_d0[i]):
					_n_desc += 1
			var dd: Array = []
			for i in _d0:
				dd.append(snappedf(-(_lg.to_local(_lg.vehicule(i).global_position)).z - float(_d0[i]), 0.01))
			_verif("%s : skieurs tirés tous sur le brin montant" % CLE, _n_mesures > 0 and _n_desc == 0,
				"%d tirés, %d en descente — v %.2f, état %s, écarts %s" % [_n_mesures, _n_desc, _lg.vitesse_reelle, _lg.etat, str(dd)])
			_lg.exploitation().commande("arreter")
			_phase = 3
			_t = 0.0
		3:
			if _lg.vitesse_reelle > 0.0 or _t < 1.0:
				return
			# skieur au pied de la gare aval
			_main.skieur.global_position = _lg.global_transform * Vector3(4.0, _lg.terrain(0.0) + 1.0, 6.0)
			_lg.exploitation().commande("demarrer")
			_verif("sonnerie lancée au démarrage", _lg.sonnerie_t > 0.0 and _lg.etat == "arret", "sonnerie %.1f s, état %s" % [_lg.sonnerie_t, _lg.etat])
			_phase = 4
			_t = 0.0
		4:
			var sr: SonsRemontees = rm.get("sons") if rm.get("sons") != null else null
			if sr == null:
				for c in rm.get_children():
					if c is SonsRemontees:
						sr = c
			if sr != null:
				for e2 in sr._sonn:
					if (e2[0] as AudioStreamPlayer3D).playing:
						_vu_sonnerie = true
			if _lg.sonnerie_t >= 0.0 and _lg.etat == "marche":
				_marche_pendant = true
			if _lg.etat == "marche" or _t > 10.0:
				_verif("ligne repartie après la sonnerie", _lg.etat == "marche" and absf(_t - LigneRemontee.T_SONNERIE) < 0.5 and not _marche_pendant, "%.1f s" % _t)
				_verif("buzzer joué en gare", _vu_sonnerie)
				_fin()
