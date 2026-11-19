## Banc du chantier « nuit » (19/11/2026) : heure de jeu, Soleil, Lune et étoiles, jour et nuit, éclairages,
## frontales, dameuses et câble de treuil, piques.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_nuit_3d.gd
## 1. HeureJeu : date et heure choisies (heure d'été et d'hiver à Tignes), avance normale et accélérée,
##    retour à l'heure réelle, affluence et exploitation qui suivent l'heure de jeu.
## 2. AstroCiel : Soleil et Lune contre une éphéméride JPL (skyfield + DE421, valeurs relevées le 19/11/2026 :
##    écart Soleil ≤ 0,05°, Lune ≤ 0,3°), étoiles (Sirius, Véga, Polaire) ≤ 0,05°, phase de la Lune.
## 3. CycleJour : plein jour = couleurs d'avant ; aube, crépuscule, nuit ; étoiles et éclairages.
## 4. En vue skieur, la nuit : voûte étoilée affichée, frontale allumée, lampes du décor publiées, candélabres
##    construits, dameuse posée sur une piste raide et treuillée, câble qui fait tomber le skieur (avec sa pique),
##    skieurs nocturnes avec frontale. De jour : rien de tout ça (aucune lumière ni ombre en plus).
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _etape: int = 0
var _t: int = 0
var _lg: LigneRemontee = null
var _dam: Dictionary = {}
var _chutes: int = 0
var _piques: Array = []

## [date UTC, azimut et hauteur du Soleil, azimut et hauteur de la Lune, fraction éclairée] — skyfield, DE421,
## site 45,45189 °N 6,89898 °E, sans réfraction.
const REF: Array = [
	["2026-01-15T08:30:00", 135.22, 10.48, 0.113],
	["2026-02-15T12:00:00", 183.89, 31.89, 0.046],
	["2026-03-20T17:45:00", 270.97, -0.88, 0.035],
	["2026-06-21T11:30:00", 177.42, 67.97, 0.464],
	["2026-07-14T19:20:00", 302.86, -1.02, 0.002],
	["2026-09-23T07:00:00", 107.52, 16.35, 0.875],
	["2026-11-19T10:00:00", 160.12, 22.68, 0.691],
	["2026-12-21T13:00:00", 201.57, 18.16, 0.908],
	["2027-02-01T21:00:00", 295.76, -45.29, 0.192],
	["2026-12-24T02:00:00", 66.28, -52.84, 0.999],
]
## Lune (skyfield) : [date, azimut, hauteur].
const REF_LUNE: Array = [
	["2026-01-15T08:30:00", 175.06, 15.72],
	["2026-03-20T17:45:00", 265.87, 20.08],
	["2026-06-21T11:30:00", 93.09, 2.34],
	["2026-09-23T07:00:00", 312.46, -52.86],
	["2026-11-19T22:00:00", 230.89, 31.79],
	["2026-12-24T02:00:00", 250.61, 55.21],
]

func _initialize() -> void:
	_tests_purs()
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", label, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


static func _ecart(az1: float, h1: float, az2: float, h2: float) -> float:
	var a1: float = deg_to_rad(az1)
	var b1: float = deg_to_rad(h1)
	var a2: float = deg_to_rad(az2)
	var b2: float = deg_to_rad(h2)
	var c: float = sin(b1) * sin(b2) + cos(b1) * cos(b2) * cos(a1 - a2)
	return rad_to_deg(acos(clampf(c, -1.0, 1.0)))


func _tests_purs() -> void:
	# --- 1. heure de jeu ---
	HeureJeu.regler(2026, 2, 15, 21, 30, 1.0, false)
	var d: Dictionary = HeureJeu.maintenant()
	_verif("heure choisie (hiver, UTC+1)", int(d["hour"]) == 21 and int(d["minute"]) == 30 and int(d["day"]) == 15,
		"%02d:%02d le %d" % [d["hour"], d["minute"], d["day"]])
	_verif("instant UTC en hiver", is_equal_approx(HeureJeu.unix_utc(),
		float(Time.get_unix_time_from_datetime_string("2026-02-15T20:30:00"))) or absf(HeureJeu.unix_utc()
		- float(Time.get_unix_time_from_datetime_string("2026-02-15T20:30:00"))) < 2.0)
	HeureJeu.regler(2026, 7, 14, 12, 0, 1.0, false)
	_verif("heure d'été (UTC+2)", absf(HeureJeu.unix_utc() - float(Time.get_unix_time_from_datetime_string("2026-07-14T10:00:00"))) < 2.0)
	_verif("changement d'heure : 29/03/2026 et 25/10/2026", HeureJeu.decalage_paris(
		float(Time.get_unix_time_from_datetime_string("2026-03-29T00:59:00"))) == 3600 and HeureJeu.decalage_paris(
		float(Time.get_unix_time_from_datetime_string("2026-03-29T01:00:00"))) == 7200 and HeureJeu.decalage_paris(
		float(Time.get_unix_time_from_datetime_string("2026-10-25T00:59:00"))) == 7200 and HeureJeu.decalage_paris(
		float(Time.get_unix_time_from_datetime_string("2026-10-25T01:00:00"))) == 3600)
	HeureJeu.regler(2026, 2, 15, 16, 59, 60.0, false)
	var h0: float = HeureJeu.heure()
	HeureJeu._ms_ref -= 2000                  # 2 s réelles = 2 min de jeu à ×60
	var h1: float = HeureJeu.heure()
	_verif("accélération ×60", absf((h1 - h0) * 60.0 - 2.0) < 0.05, "%.3f min" % ((h1 - h0) * 60.0))
	_verif("texte", HeureJeu.regler_texte("2026-02-15T21:30", 1.0, false) and int(HeureJeu.maintenant()["hour"]) == 21)
	OccupationRemontees.heure_forcee = -1.0
	HeureJeu.regler(2026, 2, 15, 10, 30, 1.0, false)
	var aff_jour: float = OccupationRemontees.affluence_pistes()
	var pointe: bool = AutoOperator.heure_de_pointe()
	HeureJeu.regler(2026, 2, 15, 22, 0, 1.0, false)
	_verif("affluence et exploitation suivent l'heure de jeu", aff_jour > 0.4 and pointe
		and OccupationRemontees.affluence_pistes() == 0.0 and not AutoOperator.heure_de_pointe(),
		"affluence 10 h 30 %.2f, 22 h %.2f" % [aff_jour, OccupationRemontees.affluence_pistes()])
	_verif("horloge du portique à l'heure de jeu", PortiqueEntree._heure() == "22:00", PortiqueEntree._heure())
	HeureJeu.revenir_reelle(false)
	_verif("retour à l'heure réelle", not HeureJeu.choisie and absf(HeureJeu.unix_utc() - Time.get_unix_time_from_system()) < 1.0)
	# --- 2. astronomie ---
	var emax_s: float = 0.0
	for r in REF:
		var t: float = float(Time.get_unix_time_from_datetime_string(r[0]))
		var s: Vector2 = AstroCiel.az_haut(AstroCiel.dir_soleil(t))
		emax_s = maxf(emax_s, _ecart(s.x, s.y, float(r[1]), float(r[2])))
		_verif("phase de la Lune %s" % r[0], absf(AstroCiel.phase_lune(t) - float(r[3])) < 0.02,
			"%.3f / %.3f" % [AstroCiel.phase_lune(t), r[3]])
	_verif("Soleil ≤ 0,05° de l'éphéméride JPL", emax_s <= 0.05, "écart max %.3f°" % emax_s)
	var emax_l: float = 0.0
	for r2 in REF_LUNE:
		var t2: float = float(Time.get_unix_time_from_datetime_string(r2[0]))
		var l: Vector2 = AstroCiel.az_haut(AstroCiel.dir_lune(t2))
		emax_l = maxf(emax_l, _ecart(l.x, l.y, float(r2[1]), float(r2[2])))
	_verif("Lune ≤ 0,3° de l'éphéméride JPL", emax_l <= 0.3, "écart max %.3f°" % emax_l)
	var t3: float = float(Time.get_unix_time_from_datetime_string("2026-02-15T21:00:00"))
	var emax_e: float = 0.0
	for st in [[101.28715533, -16.71611586, 186.69, 27.55], [279.23473479, 38.78368896, 6.51, -5.42],
			[37.95456067, 89.26410897, 359.22, 45.75]]:
		var ra: float = deg_to_rad(st[0])
		var de: float = deg_to_rad(st[1])
		var w: Vector3 = AstroCiel.base_equateur(t3) * (AstroCiel.precession(t3) * Vector3(cos(de) * cos(ra), cos(de) * sin(ra), sin(de)))
		var a: Vector2 = AstroCiel.az_haut(w)
		emax_e = maxf(emax_e, _ecart(a.x, a.y, float(st[2]), float(st[3])))
	_verif("étoiles (Sirius, Véga, Polaire) ≤ 0,05°", emax_e <= 0.05, "écart max %.3f°" % emax_e)
	var oct: PackedByteArray = Marshalls.base64_to_raw(EtoilesDonnees.DONNEES)
	_verif("catalogue : 5 080 étoiles jusqu'à la magnitude 6", oct.size() / 8 == EtoilesDonnees.N and EtoilesDonnees.N > 5000
		and float(oct.decode_u16(4)) / 1000.0 - 2.0 < -1.4, "%d étoiles, la plus brillante V = %.2f" % [oct.size() / 8,
		float(oct.decode_u16(4)) / 1000.0 - 2.0])
	# --- 3. jour et nuit ---
	var midi: Dictionary = CycleJour.etat(float(Time.get_unix_time_from_datetime_string("2026-02-15T11:00:00")))
	_verif("plein jour : couleurs d'avant", (midi["decor"] as Color).is_equal_approx(Color(1, 1, 1))
		and (midi["ciel_haut"] as Color).is_equal_approx(CycleJour.CIEL_HAUT_JOUR) and float(midi["nuit"]) == 0.0
		and float(midi["eclairage"]) == 0.0 and is_equal_approx(float(midi["energie_soleil"]), 1.2))
	var crep: Dictionary = CycleJour.etat(float(Time.get_unix_time_from_datetime_string("2026-02-15T17:00:00")))
	_verif("crépuscule (17 h 00 UTC, Soleil sous l'horizon)", float(crep["h_soleil"]) < 0.0 and float(crep["h_soleil"]) > -8.0
		and (crep["lueur"] as Color).r > 0.1 and (crep["decor"] as Color).r < 0.7, "h %.1f°" % crep["h_soleil"])
	var nuit: Dictionary = CycleJour.etat(float(Time.get_unix_time_from_datetime_string("2026-02-15T22:00:00")))
	_verif("nuit noire : étoiles, éclairages, décor sombre", float(nuit["nuit"]) > 0.9 and float(nuit["eclairage"]) == 1.0
		and (nuit["decor"] as Color).g < 0.1 and float(nuit["energie_soleil"]) == 0.0)
	var aube: Dictionary = CycleJour.etat(float(Time.get_unix_time_from_datetime_string("2026-02-15T06:15:00")))
	_verif("aube (7 h 15 à Tignes) : entre nuit et jour", float(aube["h_soleil"]) < 0.0 and float(aube["nuit"]) < 0.9
		and (aube["decor"] as Color).g > (nuit["decor"] as Color).g, "h %.1f°" % aube["h_soleil"])
	var pleine: Dictionary = CycleJour.etat(float(Time.get_unix_time_from_datetime_string("2026-12-24T02:00:00")))
	_verif("clair de pleine Lune", float(pleine["energie_lune"]) > 0.1 and (pleine["decor"] as Color).b > (nuit["decor"] as Color).b)
	_verif("damage : 17 h 30 → 8 h", CycleJour.heure_damage(22.0) and CycleJour.heure_damage(6.0)
		and not CycleJour.heure_damage(12.0))
	# piques
	for nom in ["NUIT_PISTE_FERMEE", "NUIT_DAMEUSE", "NUIT_CABLE_PRES", "NUIT_CABLE_TOUCHE", "NUIT_DAMEUSE_TOUCHE"]:
		_verif("piques %s" % nom, PNQuips.liste(nom).size() >= 3 and PNQuips.pique(nom, "fr") != "" and PNQuips.pique(nom, "en") != "")


func _fin() -> void:
	HeureJeu.revenir_reelle(false)
	HeureJeu.regler_texte(HeureJeu.DEFAUT_BANC, 1.0, false)
	print("BENCH_NUIT " + ("OK" if _ok else "ECHEC"))
	FinBanc.quitter(self, get("_main"), 0 if _ok else 1)


func _tick() -> void:
	_f += 1
	if _f > 60 * 600:
		_verif("délai", false)
		_fin()
		return
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	match _etape:
		0:
			HeureJeu.regler(2026, 2, 15, 11, 0, 1.0, false)
			_main.basculer_skieur()
			_etape = 1
		1:
			if _main.remontees == null or not _main.remontees.pret or not _main.mode_skieur:
				return
			for e in _main.remontees.lignes:
				if (e[0] as Node).name == "tcd10_toviere":
					_lg = e[0]
			_main.aller_a_remontee(_lg)
			_etape = 2
			_t = _f
		2:
			if not _lg.pret or _f - _t < 120:
				return
			# de jour : rien de la nuit
			var ej: Dictionary = _main.etat_jour
			_verif("de jour : pas de voûte, pas de frontale, pas de dameuse, pas de lampes",
				(_main._voute == null or not _main._voute.visible) and (_main._frontale == null or not _main._frontale.visible)
				and (_main.dameuses == null or _main.dameuses.engins.is_empty()) and LampesDecor._publiees <= 0
				and (_main.eclairages_nuit == null or not _main.eclairages_nuit.visible),
				"h_soleil %.1f°" % ej.get("h_soleil", 0.0))
			_verif("de jour : lumière du Soleil réel, énergie d'avant", is_equal_approx(_main._lumiere_dehors, 1.2))
			var pj: Vector3 = _main.pn_jour
			_verif("de jour : décor non assombri (pn_jour = 1)", pj.is_equal_approx(Vector3.ONE))
			# la nuit
			HeureJeu.regler(2026, 2, 15, 22, 0, 1.0, false)
			_main._t_jour = 0.0
			_etape = 3
			_t = _f
		3:
			if _f - _t < 90:
				return
			var en: Dictionary = _main.etat_jour
			_verif("la nuit : voûte étoilée affichée", _main._voute != null and _main._voute.visible and _main._voute.n_etoiles > 5000)
			var pj2: Vector3 = _main.pn_jour
			_verif("la nuit : décor assombri", pj2.y < 0.1, str(pj2))
			_verif("la nuit : frontale du skieur allumée", _main._frontale != null and _main._frontale.visible
				or not _main.skieur.dehors(_main.relief), "dehors %s" % str(_main.skieur.dehors(_main.relief)))
			_verif("la nuit : candélabres des gares", _main.eclairages_nuit != null and _main.eclairages_nuit.tetes.size() > 50
				and _main.eclairages_nuit.visible, "%d" % (_main.eclairages_nuit.tetes.size() if _main.eclairages_nuit != null else 0))
			_verif("la nuit : lampes du décor publiées", LampesDecor._publiees > 0, "%d" % LampesDecor._publiees)
			_verif("la nuit : vraies lumières plafonnées", _main.eclairages_nuit != null
				and _main.eclairages_nuit._lumieres.size() <= EclairagesNuit.lumieres_max())
			# dameuse treuillée sur la piste la plus raide près du skieur
			var dm: Dameuses = _main.dameuses
			_verif("la nuit : dameuses actives", dm != null and dm.actives)
			if dm == null:
				_fin()
				return
			var pr: Array = dm.piste_raide_pres(_main.skieur.global_position, 2500.0)
			_verif("piste raide trouvée", not pr.is_empty(), str(pr))
			if pr.is_empty():
				_fin()
				return
			var sens: float = -1.0 if dm.pente(int(pr[0]), float(pr[1])) > 0.0 else 1.0
			_dam = dm.forcer(int(pr[0]), float(pr[1]), sens)
			_etape = 4
			_t = _f
		4:
			if _f - _t < 30:
				return
			var dm2: Dameuses = _main.dameuses
			_verif("dameuse treuillée sur la pente raide", bool(_dam["treuil"]) and (_dam["pts"] as PackedVector3Array).size() > 2,
				"pente %.2f" % absf(dm2.pente(int(_dam["i"]), float(_dam["s"]))))
			_verif("ancrage en amont", (_dam["ancre"] as Vector3).y > (_dam["noeud"] as Node3D).global_position.y)
			# le skieur posé au milieu du câble : il tombe, avec la pique
			var pts: PackedVector3Array = _dam["pts"]
			var milieu: Vector3 = pts[pts.size() / 2]
			_main.skieur.chausse = true
			_main.skieur.global_position = milieu - Vector3(0.0, 0.06, 0.0)
			_main.skieur.velocity = Vector3.ZERO
			_main._pique_attente = 0.0
			_main.skieur.chute.connect(func() -> void: _chutes += 1)
			_main._maj_nuit(0.016, true)
			_verif("câble touché : chute", _chutes >= 1 and _main.skieur.a_terre())
			var txt: String = _main.commandes_skieur._pique.text if _main.commandes_skieur._pique != null else ""
			_verif("câble touché : pique", txt != "", txt)
			# skieurs nocturnes avec frontale
			_main.domaine.skieurs.nocturnes_forces = 2
			_main.domaine.skieurs._t_maj = 0.0
			_main.domaine.skieurs.nuit = 1.0
			_etape = 5
			_t = _f
		5:
			if _f - _t < 240:
				return
			var sp: SkieursPistes = _main.domaine.skieurs
			var nf: int = 0
			for fr in sp._frontales:
				if (fr as Frontale).visible:
					nf += 1
			_verif("skieurs nocturnes avec frontale", sp._agents.size() >= 1 and nf >= 1,
				"%d skieurs, %d frontales" % [sp._agents.size(), nf])
			sp.nocturnes_forces = -1
			# retour au jour : tout s'éteint
			HeureJeu.regler(2026, 2, 16, 11, 0, 1.0, false)
			_main._t_jour = 0.0
			_etape = 6
			_t = _f
		6:
			if _f - _t < 240:
				return
			_verif("retour du jour : voûte cachée, éclairages éteints, dameuses rentrées",
				not _main._voute.visible and not _main.eclairages_nuit.visible and _main.dameuses.engins.is_empty()
				and LampesDecor._publiees == 0 and (_main._frontale == null or not _main._frontale.visible),
				"%d dameuses" % _main.dameuses.engins.size())
			_fin()
