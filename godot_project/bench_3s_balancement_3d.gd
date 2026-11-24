## Balancement de la cabine du 3S où le skieur est assis (vidéo iPad du 24/11/2026, Olympique : « oscillation verticale
## du câble qui se propage, suivie par le chariot ») : la cabine, lâchée penchée de 11° au bout du lanceur, balançait
## de ±14° pendant des minutes sous le chariot. Embarqué au quai aval, puis 10 s en ligne : |phi| < 1,5°.
## Sans le module C++ (chemin PWA) par défaut ; NOYAU=1 pour le garder.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_3s_balancement_3d.gd
extends SceneTree
var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ph: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _cab: int = -1
var _n: int = 0
var _s: String = ""
var _mx: float = 0.0
var _mx2: float = 0.0

func _initialize() -> void:
	if OS.get_environment("NOYAU") != "1":
		LigneRemontee.noyau_desactive = true
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)

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
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _ph:
		0:
			_lg = rm.ligne_par_id("olympique")
			_main.aller_a_remontee(_lg)
			_ph = 1
		1:
			if not _lg.pret:
				return
			for i in range(_lg._vehicules.size()):
				var z: Array = _lg.zone(_lg._vehicules[i][1])
				if z[0] == "gare_aval" and _lg._corps[i] != null and (_lg._corps[i][1][0] as CollisionShape3D).disabled and rm._repos <= 0.0:
					var x: float = z[1]
					if x > LigneRemontee.L_FREIN + 4.0 and x < z[2] - LigneRemontee.L_FREIN - 6.0:
						_cab = i
						var v: VehiculeRemontee = _lg.vehicule(i)
						sk.activer(v.global_transform * (v.place_assise(2) + Vector3(0, 0.05, 0)), 0.0)
						_ph = 2
						_t = 0.0
						return
		2:
			if _lg.zone(_lg._vehicules[_cab][1])[0] == "ligne" and _t > 30.0:
				_ph = 3
				_t = 0.0

				print("   embarqué : a_bord=%s assis=%s" % [str(not rm.a_bord.is_empty()), sk.assis])
		3:
			var v: VehiculeRemontee = _lg.vehicule(_cab)
			var autre: VehiculeRemontee = _lg.vehicule((_cab + 3) % _lg._vehicules.size())
			_mx = maxf(_mx, absf(rad_to_deg(v.phi)))
			_mx2 = maxf(_mx2, absf(rad_to_deg(autre.phi)))
			_n += 1
			if _n % 6 == 0:
				_s += "%.1f " % rad_to_deg(v.phi)
			if _n >= 600:
				print("   phi de la cabine occupée /0,1 s : ", _s)
				var ok: bool = _mx < 1.5
				print("%s cabine occupée en ligne : balancement maxi %.2f° (cabine vide %.2f°)" % ["[OK]  " if ok else "[ECHEC]", _mx, _mx2])
				print("BENCH_3S_BALANCEMENT " + ("OK" if ok else "ECHEC"))
				FinBanc.quitter(self, _main, 0 if ok else 1)
