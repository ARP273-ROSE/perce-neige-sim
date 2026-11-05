## Banc du 3S de l'Olympique : la ligne se construit au pied de Val d'Isère,
## les cabines Zeta roulent sur les porteurs, on monte à bord à pied (assis
## d'office), on est emporté jusqu'à la gare amont et l'on sort portes
## ouvertes.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_3s_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _sons_vus: Dictionary = {}
var _t: float = 0.0
var _lg: LigneRemontee = null
var _y0: float = 0.0
var _cab: int = -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


## Balancement le plus fort admis (0,2 rad : guide RM2 cité sur un forum, source indirecte).
const BALANCEMENT_PIRE: float = 0.2
## Près des gares la cabine est guidée et descend vers le quai : pas de balancement compté.
const SANS_BALANCEMENT: float = 30.0
## Garde voulue en ligne (demande du 05/11/2026), pas celle de la dernière approche du quai.
const GARDE_LIGNE: float = 3.0


## Plus petite garde (m) entre le dessous de la caisse et le sol affiché, coins de la caisse, sur toute la ligne
## hors gares et dans les deux sens, cabine chargée, balancée de `th` en long et en travers. [garde, d, sens]
static func garde_detail(lg: LigneRemontee, th: float, hors_gares: float = 0.0) -> Array:
	var pv: Vector3 = Vector3(VehiculeRemontee.X_PIVOT_3S, VehiculeRemontee.Y_PIVOT_3S, 0)
	var bas: float = -(VehiculeRemontee.H_SUSP_3S + 0.08 + VehiculeRemontee._h_cab("cabine_3s"))
	var coins: Array = []
	for sx in [-1.47, 1.47]:
		for sz in [-1.42, 1.42]:
			coins.append(Vector3(sx, bas, sz))
	var bases: Array = [Basis.IDENTITY]
	if th > 0.0:
		bases = [Basis(Vector3.BACK, th), Basis(Vector3.BACK, -th), Basis(Vector3.RIGHT, th), Basis(Vector3.RIGHT, -th)]
	var L: float = lg.longueur_h()
	var pire: Array = [INF, 0.0, true]
	for montee in [true, false]:
		var x0: float = lg._x_brin(montee)
		var cote: float = signf(x0) if lg.sens_droite else -signf(x0)
		var d: float = maxf(LigneRemontee.NEZ_3S, hors_gares)
		while d < L - maxf(LigneRemontee.NEZ_3S, hors_gares):
			var y: float = lg.y_cable(d, montee)
			var pres: bool = minf(d, L - d) < SANS_BALANCEMENT
			for b in ([Basis.IDENTITY] if pres else bases):
				for c in coins:
					var q: Vector3 = (b as Basis) * ((c as Vector3) - pv) + pv
					var g: float = y + q.y - lg._sol(x0 + q.x * cote, -d - q.z)
					if g < float(pire[0]):
						pire = [g, d, montee]
			d += 2.0
	return pire


static func garde_pire(lg: LigneRemontee, th: float) -> float:
	return float(garde_detail(lg, th)[0])


static func garde_rapport(lg: LigneRemontee) -> Array:
	var o: Array = []
	var fin: bool = (lg.get_tree().current_scene if lg.get_tree().current_scene != null else lg.get_tree().root.get_node("Main")).relief.fin != null
	for th in [0.0, BALANCEMENT_PIRE]:
		var r: Array = garde_detail(lg, th)
		o.append("GARDE_3S relief %s, balancement %.1f : %.2f m à d=%.0f, %s" % ["fin" if fin else "25 m", th, r[0], r[1], "montée" if r[2] else "descente"])
	for d2 in [691.4, 1090.0, 1433.7, 1570.0, 1770.0, 1790.0]:
		o.append("GARDE_3S d=%.0f : câble %.1f m, sol %.1f m" % [d2, lg.y_cable(d2) + lg.y_origine, lg.terrain(d2) + lg.y_origine])
	return o


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _fin() -> void:
	print("BENCH_3S " + ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)


func _tick() -> void:
	_f += 1
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if _f < _t0 + 60:
		return
	var sk: SkieurJoueur = _main.skieur
	var rm: RemonteesDomaine = _main.remontees
	_t += 1.0 / 60.0
	match _phase:
		0:
			for e in rm.lignes:
				if (e[0] as Node).name == "olympique":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_phase = 1
			_t = 0.0
		1:
			if not _lg.pret:
				if _t > 120.0:
					_verif("3S : ligne construite", false)
					_fin()
				return
			var n_l: int = 0
			var ecart: float = 0.0
			for i in range(_lg.nombre_vehicules()):
				var s: float = _lg._vehicules[i][1]
				if _lg.zone(s)[0] != "ligne":
					continue
				n_l += 1
			for ligne_g in garde_rapport(_lg):
				print(ligne_g)
			var g_pire: float = garde_pire(_lg, BALANCEMENT_PIRE)
			var g_ligne: float = float(garde_detail(_lg, BALANCEMENT_PIRE, SANS_BALANCEMENT)[0])
			_verif("3S : au moins %.0f m sous la cabine hors abords des gares" % GARDE_LIGNE, g_ligne >= GARDE_LIGNE, "%.2f m" % g_ligne)
			_verif("3S : cabine au-dessus du sol, deux sens, balancement %.1f rad" % BALANCEMENT_PIRE, g_pire >= 0.0, "%.2f m" % g_pire)
			_verif("3S : ligne construite, véhicules en ligne", n_l >= 6, "%d véhicules, %d en ligne" % [_lg.nombre_vehicules(), n_l])
			_phase = 2
			_t = 0.0
		2:
			for i in range(_lg._vehicules.size()):
				var z: Array = _lg.zone(_lg._vehicules[i][1])
				if z[0] == "gare_aval" and _lg._corps[i] != null and (_lg._corps[i][1][0] as CollisionShape3D).disabled \
						and rm._repos <= 0.0:
					var x: float = z[1]
					if x > LigneRemontee.L_FREIN + 4.0 and x < z[2] - LigneRemontee.L_FREIN - 6.0:
						_cab = i
						var v: VehiculeRemontee = _lg.vehicule(i)
						var dedans: Vector3 = v.global_transform * (v.place_assise(2) + Vector3(0, 0.05, 0))
						sk.activer(dedans, 0.0)
						_y0 = dedans.y
						_phase = 3
						_t = 0.0
						return
			if _t > 200.0:
				_verif("3S : une cabine à quai, portes ouvertes", false)
				_fin()
		3:
			# sons réels du 3S : on note ce qui a été joué pendant le trajet
			var so: SonsRemontees = rm.sons
			if so != null:
				# (deux joueurs : un coup peut partir sur le second)
				for jo in [so._coup3s, so._coup3s_b]:
					if jo.playing and jo.stream != null:
						for nom in ["3s_lanceur_acc", "3s_pylone", "3s_lanceur_dec"]:
							if jo.stream == so._sons[nom]:
								_sons_vus[nom] = true
			if so != null and so._ligne.playing and so._ligne.stream == so._sons["3s_ligne"]:
				_sons_vus["3s_ligne"] = true
			if _t > 1.0 and _t < 1.0 + 1.0 / 60.0:
				_verif("3S : assis d'office dans la Zeta", not rm.a_bord.is_empty() and sk.assis and rm.a_bord[0] == _lg)
			if _t > 1.5 and rm.a_bord.is_empty():
				var haut: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(_lg.longueur_h()), -_lg.longueur_h())
				var d: float = Vector2(sk.global_position.x - haut.x, sk.global_position.z - haut.z).length()
				_verif("3S : sons réels — accélération, ligne, pylône, freinage",
					_sons_vus.size() == 4, str(_sons_vus.keys()))
				_verif("3S : emporté jusqu'en haut, sorti portes ouvertes", not sk.embarque and d < 40.0
					and sk.global_position.y > _y0 + 700.0, "%.0f s de trajet, %.1f m de la gare amont, +%.0f m" % [_t, d, sk.global_position.y - _y0])
				_fin()
			elif _t > 700.0:
				_verif("3S : emporté jusqu'en haut", false, "toujours à bord après 700 s")
				_fin()
