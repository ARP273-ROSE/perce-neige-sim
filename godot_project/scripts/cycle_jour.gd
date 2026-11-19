## Jour, aube, crépuscule et nuit (19/11/2026) : de la hauteur réelle du Soleil et de la Lune (AstroCiel) à
## l'heure de jeu (HeureJeu), les couleurs et intensités de la lumière, du ciel, du brouillard et de l'ambiante.
## Fonctions pures (testées au banc) ; main.gd les applique (_maj_jour).
## Repères : Soleil à +10° et plus = le jour d'avant (mêmes couleurs, même intensité) ; 0° coucher ; −6° fin du
## crépuscule civil (éclairages allumés) ; −12° nautique ; −15° et moins : nuit noire, étoiles au complet.
class_name CycleJour
extends RefCounted

const CIEL_HAUT_JOUR: Color = Color(0.13, 0.30, 0.66)
const CIEL_HORIZON_JOUR: Color = Color(0.62, 0.74, 0.90)
const AMBIANCE_CIEL_JOUR: Color = Color(0.13, 0.15, 0.18)
const LUMIERE_JOUR: Color = Color(1.0, 0.96, 0.88)
const LUMIERE_LUNE: Color = Color(0.62, 0.72, 1.0)
## Teinte des matériaux non éclairés (relief, forêt, gare du Perce-Neige, véhicules lointains) selon la hauteur
## du Soleil : [hauteur (°), couleur linéaire].
const CLES_DECOR: Array = [
	[-18.0, Color(0.030, 0.038, 0.070)],
	[-10.0, Color(0.045, 0.055, 0.100)],
	[-6.0, Color(0.16, 0.18, 0.30)],
	[-3.0, Color(0.34, 0.32, 0.44)],
	[0.0, Color(0.66, 0.54, 0.50)],
	[4.0, Color(0.88, 0.77, 0.66)],
	[10.0, Color(1.0, 1.0, 1.0)],
]
const CLES_HAUT: Array = [
	[-18.0, Color(0.003, 0.005, 0.012)],
	[-12.0, Color(0.008, 0.012, 0.032)],
	[-6.0, Color(0.03, 0.05, 0.13)],
	[-2.0, Color(0.07, 0.11, 0.27)],
	[2.0, Color(0.13, 0.25, 0.54)],
	[10.0, CIEL_HAUT_JOUR],
]
const CLES_HORIZON: Array = [
	[-18.0, Color(0.012, 0.015, 0.026)],
	[-12.0, Color(0.03, 0.036, 0.065)],
	[-6.0, Color(0.20, 0.16, 0.24)],
	[-2.0, Color(0.62, 0.40, 0.30)],
	[2.0, Color(0.86, 0.70, 0.55)],
	[10.0, CIEL_HORIZON_JOUR],
]


static func _cles(cles: Array, h: float) -> Color:
	if h <= float(cles[0][0]):
		return cles[0][1]
	for i in range(1, cles.size()):
		if h <= float(cles[i][0]):
			var t: float = (h - float(cles[i - 1][0])) / (float(cles[i][0]) - float(cles[i - 1][0]))
			return (cles[i - 1][1] as Color).lerp(cles[i][1], smoothstep(0.0, 1.0, t))
	return cles[cles.size() - 1][1]


## État complet pour l'instant t (UTC, s).
static func etat(t_unix: float) -> Dictionary:
	var ds: Vector3 = AstroCiel.dir_soleil(t_unix)
	var dl: Vector3 = AstroCiel.dir_lune(t_unix)
	var ph: float = AstroCiel.phase_lune(t_unix)
	return etat_depuis(ds, dl, ph)


static func etat_depuis(ds: Vector3, dl: Vector3, phase: float) -> Dictionary:
	var h: float = rad_to_deg(asin(clampf(ds.y, -1.0, 1.0)))
	var hl: float = rad_to_deg(asin(clampf(dl.y, -1.0, 1.0)))
	var e: Dictionary = {"h_soleil": h, "h_lune": hl, "dir_soleil": ds, "dir_lune": dl, "phase": phase}
	# lumière de la Lune (nuit seulement, selon sa phase et sa hauteur)
	var k_lune: float = phase * smoothstep(-1.0, 18.0, hl) * (1.0 - smoothstep(-8.0, -2.0, h))
	e["k_lune"] = k_lune
	# soleil direct : s'éteint en se couchant (il passe derrière la brume de l'horizon)
	var k_sol: float = smoothstep(-1.0, 8.0, h)
	e["k_soleil"] = k_sol
	var chaud: float = 1.0 - smoothstep(2.0, 22.0, h)
	e["couleur_soleil"] = LUMIERE_JOUR.lerp(Color(1.0, 0.56, 0.30), chaud * 0.85)
	e["energie_soleil"] = 1.2 * k_sol
	e["energie_lune"] = 0.20 * k_lune
	# direction de la lumière du décor : le Soleil (relevé à 3° au moins : rasant, l'ombrage n'a plus de sens),
	# la Lune la nuit, sinon une lumière haute
	var dir_s: Vector3 = Vector3(ds.x, maxf(ds.y, 0.0525), ds.z).normalized()
	var dir_l: Vector3 = Vector3(dl.x, maxf(dl.y, 0.0525), dl.z).normalized() if hl > -2.0 \
		else Vector3(0.30, 0.90, 0.32).normalized()
	var poids_s: float = smoothstep(-6.0, -1.0, h)
	e["dir_lumiere"] = dir_l.lerp(dir_s, poids_s).normalized()
	# teinte des matériaux non éclairés : clés + clair de lune
	var decor: Color = _cles(CLES_DECOR, h)
	decor += Color(0.10, 0.12, 0.17) * k_lune
	e["decor"] = decor
	# ciel
	var lune_ciel: Color = Color(0.012, 0.020, 0.045) * k_lune
	e["ciel_haut"] = _cles(CLES_HAUT, h) + lune_ciel
	e["ciel_horizon"] = _cles(CLES_HORIZON, h) + lune_ciel * 1.6
	# lueur du couchant, du côté du Soleil (0 en plein jour et en pleine nuit)
	var lueur: float = smoothstep(-10.0, -2.0, h) * (1.0 - smoothstep(3.0, 12.0, h))
	e["lueur"] = Color(1.0, 0.42, 0.16) * lueur * 0.9
	# ambiante (part non lue dans le ciel) et brouillard : suivent le décor, bleuies la nuit
	var lum: float = decor.r * 0.3 + decor.g * 0.59 + decor.b * 0.11
	e["k_ambiance"] = clampf(lum, 0.05, 1.0)
	e["ambiance_ciel"] = AMBIANCE_CIEL_JOUR * Color(decor.r, decor.g, decor.b)
	e["nuages"] = Color(decor.r, decor.g, decor.b).lerp(Color(1, 1, 1), 0.0)
	# étoiles : invisibles au-dessus de −4°, toutes à −15°, voilées par la pleine Lune haute
	e["nuit"] = (1.0 - smoothstep(-15.0, -4.0, h)) * (1.0 - 0.35 * k_lune)
	# éclairages (gares, cabines, frontales, dameuses) : allumés du coucher (+2°) au crépuscule civil (−6°)
	e["eclairage"] = 1.0 - smoothstep(-6.0, 2.0, h)
	return e


## Le soir et la nuit, après la fermeture des pistes (17 h 30) et jusqu'au matin (8 h) : heure des dameuses.
static func heure_damage(h: float) -> bool:
	return h >= 17.5 or h < 8.0
