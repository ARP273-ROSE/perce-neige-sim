## Positions du Soleil, de la Lune et du ciel étoilé pour l'heure de jeu (HeureJeu), au site de Tignes.
## Formules « basse précision » de l'Astronomical Almanac (Soleil ≈ 0,01°, Lune ≈ 0,3°), temps sidéral de
## l'IAU 1982. Vérifiées contre une éphéméride JPL (skyfield, DE421) : voir bench_ciel_nuit_3d.gd.
## Repère du jeu : x vers l'est, y vers le haut, z vers le sud (relief IGN posé sans rotation).
class_name AstroCiel
extends RefCounted

const J2000_UNIX: float = 946728000.0         # 2000-01-01 12:00 TT ≈ UT


static func _jours(t_unix: float) -> float:
	return (t_unix - J2000_UNIX) / 86400.0


## Temps sidéral local (rad) à l'instant t (UTC, s) et à la longitude lon (degrés est).
static func tsl(t_unix: float, lon: float = HeureJeu.LONGITUDE) -> float:
	var n: float = _jours(t_unix)
	var tc: float = n / 36525.0
	var gmst: float = 280.46061837 + 360.98564736629 * n + 0.000387933 * tc * tc
	return deg_to_rad(fposmod(gmst + lon, 360.0))


## Obliquité de l'écliptique (rad).
static func obliquite(t_unix: float) -> float:
	return deg_to_rad(23.439 - 0.0000004 * _jours(t_unix))


## Ascension droite et déclinaison du Soleil (rad, équinoxe de la date).
static func soleil_equatorial(t_unix: float) -> Vector2:
	var n: float = _jours(t_unix)
	var l: float = deg_to_rad(fposmod(280.460 + 0.9856474 * n, 360.0))
	var g: float = deg_to_rad(fposmod(357.528 + 0.9856003 * n, 360.0))
	var lam: float = l + deg_to_rad(1.915) * sin(g) + deg_to_rad(0.020) * sin(2.0 * g)
	var eps: float = obliquite(t_unix)
	return Vector2(atan2(cos(eps) * sin(lam), cos(lam)), asin(sin(eps) * sin(lam)))


## Longitude, latitude écliptiques (rad) et parallaxe horizontale (rad) de la Lune (géocentriques).
static func lune_ecliptique(t_unix: float) -> Vector3:
	var tc: float = _jours(t_unix) / 36525.0
	var lam: float = 218.32 + 481267.881 * tc \
		+ 6.29 * sin(deg_to_rad(135.0 + 477198.87 * tc)) - 1.27 * sin(deg_to_rad(259.3 - 413335.36 * tc)) \
		+ 0.66 * sin(deg_to_rad(235.7 + 890534.22 * tc)) + 0.21 * sin(deg_to_rad(269.9 + 954397.74 * tc)) \
		- 0.19 * sin(deg_to_rad(357.5 + 35999.05 * tc)) - 0.11 * sin(deg_to_rad(186.5 + 966404.03 * tc))
	var bet: float = 5.13 * sin(deg_to_rad(93.3 + 483202.02 * tc)) + 0.28 * sin(deg_to_rad(228.2 + 960400.89 * tc)) \
		- 0.28 * sin(deg_to_rad(318.3 + 6003.15 * tc)) - 0.17 * sin(deg_to_rad(217.6 - 407332.21 * tc))
	var par: float = 0.9508 + 0.0518 * cos(deg_to_rad(135.0 + 477198.87 * tc)) \
		+ 0.0095 * cos(deg_to_rad(259.3 - 413335.36 * tc)) + 0.0078 * cos(deg_to_rad(235.7 + 890534.22 * tc)) \
		+ 0.0028 * cos(deg_to_rad(269.9 + 954397.74 * tc))
	return Vector3(deg_to_rad(fposmod(lam, 360.0)), deg_to_rad(bet), deg_to_rad(par))


static func lune_equatorial(t_unix: float) -> Vector2:
	var e: Vector3 = lune_ecliptique(t_unix)
	var eps: float = obliquite(t_unix)
	var v: Vector3 = Vector3(cos(e.y) * cos(e.x), cos(e.y) * sin(e.x), sin(e.y))
	# écliptique → équateur : rotation de −ε autour de x
	var y: float = v.y * cos(eps) - v.z * sin(eps)
	var z: float = v.y * sin(eps) + v.z * cos(eps)
	return Vector2(atan2(y, v.x), asin(clampf(z, -1.0, 1.0)))


## Matrice équateur (de la date) → repère du jeu, à l'instant t, pour la latitude du site.
## Colonnes : images des axes équatoriaux (point vernal, 90° d'ascension droite, pôle nord céleste).
static func base_equateur(t_unix: float, lat: float = HeureJeu.LATITUDE, lon: float = HeureJeu.LONGITUDE) -> Basis:
	var th: float = tsl(t_unix, lon)
	var ph: float = deg_to_rad(lat)
	var st: float = sin(th)
	var ct: float = cos(th)
	var sp: float = sin(ph)
	var cp: float = cos(ph)
	return Basis(Vector3(-st, cp * ct, sp * ct), Vector3(ct, cp * st, sp * st), Vector3(0.0, sp, -cp))


## Précession depuis J2000 (rotation autour du pôle de l'écliptique, 50,29″ par an) : J2000 → équinoxe de la date.
static func precession(t_unix: float) -> Basis:
	var p: float = deg_to_rad(1.396971) * _jours(t_unix) / 36525.0
	var eps: float = deg_to_rad(23.4393)
	var vers_ecl: Basis = Basis(Vector3.RIGHT, -eps)      # équateur → écliptique
	return vers_ecl.inverse() * Basis(Vector3.BACK, p) * vers_ecl


static func _vecteur(ra: float, dec: float) -> Vector3:
	return Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))


## Direction du Soleil dans le repère du jeu (vecteur unitaire, centre géométrique sans réfraction).
static func dir_soleil(t_unix: float) -> Vector3:
	var e: Vector2 = soleil_equatorial(t_unix)
	return (base_equateur(t_unix) * _vecteur(e.x, e.y)).normalized()


## Direction de la Lune vue du site (parallaxe d'altitude comprise, ≈ 1° près de l'horizon).
static func dir_lune(t_unix: float) -> Vector3:
	var e: Vector2 = lune_equatorial(t_unix)
	var d: Vector3 = (base_equateur(t_unix) * _vecteur(e.x, e.y)).normalized()
	var par: float = lune_ecliptique(t_unix).z
	var h: float = asin(clampf(d.y, -1.0, 1.0))
	var h_topo: float = h - asin(sin(par) * cos(h))
	var hz: Vector2 = Vector2(d.x, d.z)
	if hz.length() < 1e-6:
		return d
	hz = hz.normalized() * cos(h_topo)
	return Vector3(hz.x, sin(h_topo), hz.y)


## Fraction éclairée du disque lunaire (0 nouvelle lune, 1 pleine lune).
static func phase_lune(t_unix: float) -> float:
	var s: Vector2 = soleil_equatorial(t_unix)
	var l: Vector2 = lune_equatorial(t_unix)
	var c: float = _vecteur(s.x, s.y).dot(_vecteur(l.x, l.y))
	return 0.5 * (1.0 - c)


## Azimut (degrés depuis le nord, vers l'est) et hauteur (degrés) d'une direction du repère du jeu.
static func az_haut(d: Vector3) -> Vector2:
	var az: float = rad_to_deg(atan2(d.x, -d.z))
	return Vector2(fposmod(az, 360.0), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))
