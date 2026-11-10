## Charge excentrée et guide d'entrée de gare : un passager assis au bout du véhicule, sur un siège et dans une
## cabine (l'une des deux lignes en miroir). En ligne le véhicule se stabilise autour de psi0 ; dans le guide,
## l'inclinaison reste sous la limite et revient vers zéro avant le débrayage ; en sortie, elle repart vers psi0.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_charge_excentree_3d.gd -- --mode=normal [--sans-noyau]
extends SceneTree

const CAS: Array = [["tsd6_merles", 5], ["tcd10_boisses", 4]]
const ERREUR_MAX: float = 0.4        # part de psi0 tolérée sur la moyenne en ligne (pylônes, vent de cabine)

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _i_cas: int = 0
var _lg: LigneRemontee = null
var _v: VehiculeRemontee = null
var _iv: int = -1
var _etat: int = 0
var _t: float = 0.0
var _somme: Array = []
var _psi0: float = 0.0
var _pire_guide: float = -INF
var _entree: float = -1.0
var _pire_lanceur: float = 0.0


func _initialize() -> void:
	LigneRemontee.noyau_desactive = "--sans-noyau" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _d_gare(s: float) -> float:
	var z: Array = _lg._zones[1]
	return fposmod(float(z[0]) - s, _lg.longueur_boucle)


func _choisir() -> void:
	var meil: int = -1
	var e: float = INF
	for i in range(_lg._vehicules.size()):
		var v: VehiculeRemontee = _lg._vehicules[i][0]
		var d: float = _d_gare(float(_lg._vehicules[i][1]))
		if signf(v.position.x) == signf(_lg._x_brin(true)) and _lg.zone_vehicule(i) == "ligne" and d > 150.0 and d < e:
			e = d
			meil = i
	_iv = meil
	_v = _lg._vehicules[meil][0]
	var k: int = CAS[_i_cas][1]
	_lg.regler_charge(_iv, k, false, true)
	_psi0 = _v.psi0_joueur
	print("%s véhicule %d à %.0f m de la gare ; masse %.0f kg, L %.2f m, x %.2f m ; psi0 attendu %.2f° ; à bord du module : %s" % [_lg.name, _iv, e, _v.masse, _v.longueur_pendule, _v.place_assise(k).x, rad_to_deg(_psi0), str(_lg._noyau_valide())])
	_somme = []
	_pire_guide = -INF
	_entree = -1.0
	_pire_lanceur = 0.0
	_t = 0.0


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
	var dt: float = 1.0 / 60.0
	match _etat:
		0:
			for e in _main.remontees.lignes:
				if String((e[0] as Node).name) == CAS[_i_cas][0]:
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_etat = 1
			_t = 0.0
		1:
			_t += dt
			if _lg.pret and _t > 3.0:
				_tirage()
				_choisir()
				_etat = 2
		_:
			_suivre(dt)


func _tirage() -> void:
	var n: int = 0
	var somme: float = 0.0
	var pire: float = 0.0
	for e in _lg._vehicules:
		var v: VehiculeRemontee = e[0]
		if v.psi0_tire != 0.0:
			n += 1
		somme += absf(v.psi0_tire)
		pire = maxf(pire, absf(v.psi0_tire))
	print("%s tirage : %d/%d véhicules inclinés, moyenne %.2f°, maxi %.2f°" % [_lg.name, n, _lg._vehicules.size(), rad_to_deg(somme / maxi(1, _lg._vehicules.size())), rad_to_deg(pire)])


func _suivre(dt: float) -> void:
	_t += dt
	var s: float = fposmod(float(_lg._vehicules[_iv][1]), _lg.longueur_boucle)
	var z: Array = _lg.zone(s)
	var lim: float = _lg.limite_guide(s)
	# point de vue sur le véhicule : au loin, le module ne fait plus balancer
	_main.skieur.global_position = _v.global_position + Vector3(8, 2, 0)
	if _lg.get("point_vue") != null:
		_lg.point_vue = _v.position
	match _etat:
		2:
			var d: float = _d_gare(s)
			if d < 60.0 and d > 10.0 and _t > 8.0:
				_somme.append(_v.psi)
			if d <= _lg.GUIDE_L + 1.0:
				var moy: float = 0.0
				for p in _somme:
					moy += p
				moy /= maxi(1, _somme.size())
				print("%s en ligne : psi moyen %.2f° (attendu %.2f°, %d mesures)" % [_lg.name, rad_to_deg(moy), rad_to_deg(_psi0), _somme.size()])
				_verif("%s équilibre autour de psi0" % _lg.name, _somme.size() > 30 and absf(moy - _psi0) <= ERREUR_MAX * absf(_psi0))
				_etat = 3
		3:
			if lim < INF:
				_pire_guide = maxf(_pire_guide, absf(_v.psi) - lim)
			if z[0] != "ligne":
				_entree = absf(_v.psi)
				print("%s entrée de gare : psi %.3f° (roulement %.1f mm) ; dépassement maxi du guide %.4f°" % [_lg.name, rad_to_deg(_entree), 1000.0 * sin(_entree) * (VehiculeRemontee.A108_X_ROULEMENT - VehiculeRemontee.A108_PIVOT.x), rad_to_deg(_pire_guide)])
				_verif("%s psi rendu à zéro à l'entrée" % _lg.name, _entree <= _lg.GUIDE_GORGE / (VehiculeRemontee.A108_X_ROULEMENT - VehiculeRemontee.A108_PIVOT.x) + 0.002)
				_verif("%s dans le guide" % _lg.name, _pire_guide < 0.002)
				_etat = 4
				_t = 0.0
		4:
			_pire_guide = maxf(_pire_guide, 0.0)
			# (sur les lanceurs, droits ; la poulie entre les deux fait balancer, comme la gare l'a toujours fait)
			if z[0] != "ligne" and (float(z[1]) < _lg.L_FREIN or float(z[1]) > float(z[2]) - _lg.L_FREIN):
				_pire_lanceur = maxf(_pire_lanceur, absf(_v.psi) if float(z[1]) > 8.0 and float(z[1]) < float(z[2]) - 8.0 else 0.0)
			if z[0] == "ligne" and _t > 2.0:
				print("%s lanceurs : psi maxi %.2f°" % [_lg.name, rad_to_deg(_pire_lanceur)])
				_verif("%s droit sur les lanceurs" % _lg.name, _pire_lanceur < 0.03)
				_etat = 5
				_t = 0.0
				_somme = []
		5:
			# sortie : le véhicule repart et retrouve l'équilibre du joueur toujours à bord
			if _t > 22.0:
				var moy2: float = 0.0
				for p in _somme:
					moy2 += p
				moy2 /= maxi(1, _somme.size())
				print("%s après la sortie : psi moyen %.2f° (attendu %.2f°)" % [_lg.name, rad_to_deg(moy2), rad_to_deg(_psi0)])
				_verif("%s repart vers psi0" % _lg.name, absf(moy2 - _psi0) <= 0.6 * absf(_psi0))
				_lg.regler_charge(_iv, 0, false, false)
				_i_cas += 1
				if _i_cas >= CAS.size():
					print("BENCH_CHARGE " + ("OK" if _ok else "ECHEC"))
					FinBanc.quitter(self, _main, 0 if _ok else 1)
					return
				_etat = 0
			elif _t > 12.0:
				_somme.append(_v.psi)
