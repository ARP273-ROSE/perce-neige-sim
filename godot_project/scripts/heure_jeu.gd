## Heure de jeu (19/11/2026, demande d'un utilisateur : « un réglage de l'heure de jeu et de la date »).
## Tout ce que le jeu décide selon l'heure passe par ici : affluence des pistes et des remontées, exploitation,
## horloges affichées, soleil, étoiles, dameuses.
##  - par défaut, l'heure RÉELLE, exprimée à Tignes (Europe/Paris, heure d'été comprise) : le soleil et les
##    horloges restent d'accord, où que soit l'appareil ;
##  - sinon, une date et une heure choisies, qui avancent ensuite normalement (×1) ou en accéléré.
## Le choix est gardé dans user://heure_jeu.cfg. En ligne de commande (bancs, captures, PC) :
##   --heure-jeu=2026-02-15T21:30  --acceleration=60  --heure-jeu=reelle
## Bancs sans écran : une heure fixe de jour (DEFAUT_BANC), pour des résultats qui ne dépendent pas de l'heure
## à laquelle on les lance.
class_name HeureJeu
extends RefCounted

const FICHIER: String = "user://heure_jeu.cfg"
## Site : pied du Perce-Neige (origine du repère du jeu, IGN), altitude du lac de Tignes.
const LATITUDE: float = 45.45188591
const LONGITUDE: float = 6.89898136
## Bancs sans écran : 15 février 2026, 11 h à Tignes.
const DEFAUT_BANC: String = "2026-02-15T11:00"
const ACCELERATIONS: Array = [1.0, 10.0, 60.0, 360.0]

static var choisie: bool = false
static var acceleration: float = 1.0
## Date et heure choisies, à Tignes (« AAAA-MM-JJTHH:MM »), point de départ à chaque lancement.
static var depart_local: String = ""
static var _unix_ref: float = 0.0           # instant de jeu (UTC, s) à _ms_ref
static var _ms_ref: int = 0
static var _pret: bool = false


static func _init_une_fois() -> void:
	if _pret:
		return
	_pret = true
	var cl: String = ""
	var acc: float = -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--heure-jeu="):
			cl = a.trim_prefix("--heure-jeu=")
		elif a.begins_with("--acceleration="):
			acc = maxf(float(a.trim_prefix("--acceleration=")), 0.0)
	if cl == "reelle":
		revenir_reelle(false)
	elif cl != "":
		regler_texte(cl, acc if acc > 0.0 else 1.0, false)
	elif DisplayServer.get_name() == "headless":
		regler_texte(DEFAUT_BANC, 1.0, false)
	else:
		charger()
		if acc > 0.0 and choisie:
			acceleration = acc


## Instant de jeu, en secondes UTC depuis 1970.
static func unix_utc() -> float:
	_init_une_fois()
	if not choisie:
		return Time.get_unix_time_from_system()
	return _unix_ref + float(Time.get_ticks_msec() - _ms_ref) * 0.001 * acceleration


## Décalage de l'heure de Tignes sur UTC (s) à l'instant t : +1 h, +2 h du dernier dimanche de mars (1 h UTC)
## au dernier dimanche d'octobre (1 h UTC), règle européenne.
static func decalage_paris(t: float) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(t))
	var an: int = int(d["year"])
	var debut: int = _dernier_dimanche(an, 3) + 3600
	var fin: int = _dernier_dimanche(an, 10) + 3600
	return 7200 if (t >= debut and t < fin) else 3600


static func _dernier_dimanche(an: int, mois: int) -> int:
	var t: int = Time.get_unix_time_from_datetime_dict({"year": an, "month": mois, "day": 31, "hour": 0, "minute": 0, "second": 0})
	var jour: int = int(Time.get_datetime_dict_from_unix_time(t)["weekday"])   # 0 = dimanche
	return t - jour * 86400


## Date et heure de jeu à Tignes (mêmes clés que Time.get_datetime_dict_from_system).
static func maintenant() -> Dictionary:
	var t: float = unix_utc()
	return Time.get_datetime_dict_from_unix_time(int(t) + decalage_paris(t))


## Heure de jeu à Tignes, en heures décimales (0..24).
static func heure() -> float:
	var t: float = unix_utc()
	var loc: float = t + float(decalage_paris(t))
	return fposmod(loc, 86400.0) / 3600.0


## Règle la date et l'heure de jeu (à Tignes) ; elles avancent ensuite à `acc` fois le temps réel.
static func regler(an: int, mois: int, jour: int, h: int, mn: int, acc: float = 1.0, sauver_: bool = true) -> void:
	_pret = true
	# (31 février choisi dans l'écran : ramené au dernier jour du mois)
	mois = clampi(mois, 1, 12)
	var j_max: int = [31, 29 if (an % 4 == 0 and (an % 100 != 0 or an % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31,
		30, 31, 30, 31][mois - 1]
	jour = clampi(jour, 1, j_max)
	var loc: int = Time.get_unix_time_from_datetime_dict({"year": an, "month": mois, "day": jour,
		"hour": h, "minute": mn, "second": 0})
	# l'heure locale vaut UTC + décalage ; le décalage dépend de l'instant UTC (deux essais suffisent)
	var t: int = loc - 3600
	t = loc - decalage_paris(float(t))
	choisie = true
	acceleration = maxf(acc, 0.0)
	depart_local = "%04d-%02d-%02dT%02d:%02d" % [an, mois, jour, h, mn]
	_unix_ref = float(t)
	_ms_ref = Time.get_ticks_msec()
	if sauver_:
		sauver()


## « AAAA-MM-JJTHH:MM » (ou « AAAA-MM-JJ HH:MM ») ; faux si illisible.
static func regler_texte(s: String, acc: float = 1.0, sauver_: bool = true) -> bool:
	var p: PackedStringArray = s.strip_edges().replace(" ", "T").split("T")
	if p.size() != 2:
		return false
	var dj: PackedStringArray = p[0].split("-")
	var hm: PackedStringArray = p[1].split(":")
	if dj.size() != 3 or hm.size() < 2:
		return false
	regler(int(dj[0]), clampi(int(dj[1]), 1, 12), clampi(int(dj[2]), 1, 31), clampi(int(hm[0]), 0, 23),
		clampi(int(hm[1]), 0, 59), acc, sauver_)
	return true


static func revenir_reelle(sauver_: bool = true) -> void:
	_pret = true
	choisie = false
	acceleration = 1.0
	if sauver_:
		sauver()


## Saute de `s` secondes de jeu (touches de réglage rapide, bancs).
static func avancer(s: float) -> void:
	_init_une_fois()
	if not choisie:
		var d: Dictionary = maintenant()
		regler(int(d["year"]), int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"]), 1.0, false)
	_unix_ref += s


static func sauver() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var c := ConfigFile.new()
	c.set_value("heure", "choisie", choisie)
	c.set_value("heure", "depart", depart_local)
	c.set_value("heure", "acceleration", acceleration)
	c.save(FICHIER)


static func charger() -> void:
	var c := ConfigFile.new()
	if c.load(FICHIER) != OK:
		return
	var dep: String = str(c.get_value("heure", "depart", ""))
	if bool(c.get_value("heure", "choisie", false)) and dep != "":
		regler_texte(dep, float(c.get_value("heure", "acceleration", 1.0)), false)


## Libellé court pour l'interface : « heure réelle » ou « 15/02/2026 21:30 ×60 ».
static func libelle() -> String:
	var d: Dictionary = maintenant()
	var s: String = "%02d/%02d/%04d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]
	if not choisie:
		return "heure réelle (%s)" % s
	return s + ("" if is_equal_approx(acceleration, 1.0) else " ×%d" % int(acceleration))
