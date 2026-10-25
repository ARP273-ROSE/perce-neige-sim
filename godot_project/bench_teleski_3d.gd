## Banc des téléskis (retour d'utilisateur, 24/10/2026 : « fais les 3 » — les
## téléskis posés et qu'on puisse les prendre) : skieur chaussé au départ,
## juste après la poulie → la perche suivante l'emmène, skis sur la trace
## (au sol, pas en l'air), la perche se déroule jusqu'à lui → en haut, il la
## lâche avant la poulie et repart à ski.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_teleski_3d.gd -- --mode=normal
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _ok: bool = true
var _phase: int = 0
var _t: float = 0.0
var _lg: LigneRemontee = null
var _y0: float = 0.0
var _au_sol: bool = true
var _ecart_max: float = 0.0
var _perche_ok: bool = false
var CLE: String = "tke_legettaz"     # autre ligne : -- cle (ex. tkd_3000, en virage)


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
	print("BENCH_TELESKI " + ("OK" if _ok else "ECHEC"))
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
				if (e[0] as Node).name == CLE:
					_lg = e[0]
			if _lg == null:
				_verif("téléski %s posé" % CLE, false)
				_fin()
				return
			_main.aller_a_remontee(_lg)
			_main.collisions.assurer_autour(_lg.global_transform.origin)
			_phase = 1
		1:
			if not _lg.pret:
				return
			_verif("téléski : gare courte, sans lanceurs ni quai", _lg.fixe() and _lg.l_gare < 10.0 and _lg._pneus.is_empty()
				and _lg.find_child("Terrassement", true, false) == null,
				"gare %.1f m, %d pneus" % [_lg.l_gare, _lg._pneus.size()])
			if _lg.famille == "perche_debrayable":
				var n_mag: int = 0
				for k in range(_lg._au_magasin.size()):
					if _lg._au_magasin[k] >= 0.0:
						n_mag += 1
				_verif("TKD : perches rangées au magasin", n_mag >= 15, "%d au magasin" % n_mag)
			# à PIED, 2,5 m derrière le tapis de départ (retour d'utilisateur,
			# 25/10/2026 : « à pied rien ne se passe »)
			var q: Vector3 = _lg.global_transform * (_lg.point_embarquement(true) + Vector3(0, 0, 2.5))
			q.y = _main.relief.hauteur_sol(q.x, q.z)
			sk.activer(q + Vector3(0, 0.1, 0), 0.0)
			if sk.chausse:
				sk.basculer_ski(false)
			sk.dernier_sol = q
			_phase = 2
			_t = 0.0
		2:
			if not rm.a_bord.is_empty():
				_verif("téléski : arrivé à pied, chaussé d'office, perche prise au tapis", sk.chausse and sk.embarque and not sk.assis and rm.a_bord.size() > 5,
					"%.1f s d'attente" % _t)
				_y0 = sk.global_position.y
				_phase = 3
				_t = 0.0
			if _t > 30.0 and _phase == 2:
				_verif("téléski : perche prise au départ", false, "rien en 30 s")
				_fin()
		3:
			if not rm.a_bord.is_empty():
				# skis sur la trace : à moins de 30 cm du relief
				var p: Vector3 = sk.global_position
				var e2: float = absf(p.y - _main.relief.hauteur_sol(p.x, p.z))
				var loc: Vector3 = _lg.global_transform.affine_inverse() * p
				if -loc.z > 15.0 and -loc.z < _lg.longueur_h() - 15.0:
					_ecart_max = maxf(_ecart_max, e2)
				# perche déroulée jusqu'au skieur
				var v: VehiculeRemontee = _lg.vehicule(rm.a_bord[1])
				# enrouleur : la corde se déroule ; TKD : la perche télescopique s'allonge
				if (v._corde != null and v._corde.scale.y > 1.0) or (v._corde == null and v._perche_tige != null and absf(v._perche_tige.scale.y - 1.0) > 0.05):
					_perche_ok = true
			else:
				var haut: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(_lg.longueur_h()), -_lg.longueur_h())
				var d: float = Vector2(sk.global_position.x - haut.x, sk.global_position.z - haut.z).length()
				_verif("téléski : tracté skis au sol", _ecart_max < 0.6, "écart maxi au relief %.2f m" % _ecart_max)
				_verif("téléski : la perche se déroule jusqu'au skieur", _perche_ok)
				_verif("téléski : perche lâchée en haut", not sk.embarque and d < 20.0 and sk.global_position.y > _y0 + 20.0,
					"%.0f s de trajet, %.1f m de la gare amont, +%.0f m" % [_t, d, sk.global_position.y - _y0])
				_phase = 4
				_t = 0.0
			if _t > 400.0 and _phase == 3:
				_verif("téléski : perche lâchée en haut", false, "toujours tracté après 400 s")
				_fin()
		4:
			if _t > 6.0:
				_verif("téléski : repart à ski, chaussé, debout", sk.chausse and not sk.embarque and sk.actif)
				# lâché au pas sur l'arrivée : il ne dévale pas l'autre versant
				# (au 3000, il passait la crête — retour d'utilisateur, 25/10/2026)
				var L2: float = _lg.longueur_h()
				var haut2: Vector3 = _lg.global_transform * Vector3(0, _lg.terrain(L2), -L2)
				haut2.y = _main.relief.hauteur_sol(haut2.x, haut2.z)        # sol réel au nez de la gare
				var d2: float = Vector2(sk.global_position.x - haut2.x, sk.global_position.z - haut2.z).length()
				_verif("téléski : reste sur l'arrivée après le lâcher", d2 < 30.0 and sk.global_position.y > haut2.y - 6.0,
					"%.1f m de la gare amont, %.1f m sous elle après 6 s" % [d2, haut2.y - sk.global_position.y])
				_fin()
