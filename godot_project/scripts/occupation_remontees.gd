## Occupation des remontées (16/11/2026, retour d'utilisateur : « on met des gens que dans le funi Perce-Neige et
## nulle part ailleurs sur d'autres remontées ou pistes. Change et respecte physique complète du poids et logique
## d'utilisation »).
## Part des places occupées selon l'heure, le sens et le genre de ligne, d'après la loi du Perce-Neige
## (AutoOperator.charge_pax) : les skieurs MONTENT par les remontées et redescendent à ski — montée chargée le
## matin (pic vers 10 h 15 l'hiver, 8 h 30 l'été), creux à midi, reprise l'après-midi, rien hors des heures
## d'ouverture ; descente presque vide, sauf aux téléphériques et funiculaires (piétons, fin de journée) et au
## glacier l'été quand il ferme vers midi. Chaque véhicule tire son nombre de passagers au départ de la gare,
## sans hasard d'une partie à l'autre (même heure, mêmes cabines).
class_name OccupationRemontees
extends RefCounted

const PAX_KG: float = 80.0                 # skieur équipé (75 kg au Perce-Neige, sans les skis)
const OUVERTURE: float = 8.75              # 8 h 45
const FERMETURE: float = 16.75             # 16 h 45 (les dernières montées vers 16 h 30)
## Heure forcée (bancs, captures) : négative = horloge du système.
static var heure_forcee: float = -1.0


static func heure() -> float:
	if heure_forcee >= 0.0:
		return heure_forcee
	var hl: Dictionary = PNConstants.heure_locale()
	return float(int(hl.get("hour", 0))) + float(int(hl.get("minute", 0))) / 60.0


static func ete() -> bool:
	return AutoOperator.saison_ete(PNConstants.heure_locale()) if heure_forcee < 0.0 else false


## Genre de ligne pour la loi de charge.
static func genre(lg: Node) -> String:
	if lg is Funival or (lg is LigneRemontee and (lg as LigneRemontee).vaetvient()):
		return "vaetvient"
	if lg is LigneRemontee and (lg as LigneRemontee).tricable():
		return "3s"
	if lg is LigneRemontee and (lg as LigneRemontee).teleski():
		return "teleski"
	return "telesiege"


## Écart propre à la ligne (±15 %), stable : les lignes ne se remplissent pas toutes pareil.
static func _facteur_ligne(lg: Node) -> float:
	return 0.85 + 0.30 * float(hash(String(lg.name)) & 0xFFFF) / 65535.0


## Part des places occupées (0..1), en moyenne, dans le sens montant ou descendant, à l'heure h.
static func taux(lg: Node, montee: bool, h: float = -1.0) -> float:
	if h < 0.0:
		h = heure()
	if h < OUVERTURE - 0.25 or h > FERMETURE + 0.25:
		return 0.0
	var g: String = genre(lg)
	var f: float = _facteur_ligne(lg)
	if montee:
		var pic: float = 8.5 if ete() else 10.25
		var matin: float = maxf(0.0, 1.0 - absf(h - pic) / 3.0)
		# reprise de l'après-midi, plus faible (déjeuner en haut ou en bas, puis dernières descentes)
		var apres: float = 0.55 * maxf(0.0, 1.0 - absf(h - 14.0) / 1.8)
		var t: float = 0.15 + 0.80 * maxf(matin, apres)
		if g == "teleski":
			t = minf(1.0, t * 1.05)
		return clampf(t * f, 0.0, 0.95)
	# descente : piétons des téléphériques et funiculaires (retour en fin de journée), glacier l'été
	if g == "vaetvient" or g == "3s":
		var soir: float = maxf(0.0, 1.0 - absf(h - 16.0) / 1.0)
		var t2: float = 0.04 + 0.30 * soir
		if ete():
			t2 = maxf(t2, 0.10 + 0.75 * maxf(0.0, 1.0 - absf(h - 12.0) / 2.0))
		return clampf(t2 * f, 0.0, 0.90)
	if g == "telesiege":
		return 0.02 * f               # quelques piétons ou débutants qui redescendent
	return 0.0                        # téléski : personne sur le brin retour


## Passagers d'un véhicule (0..places), tirés au départ de la gare : `tour` change à chaque passage en gare,
## de sorte qu'un même véhicule n'a pas toujours la même charge ; sans hasard (mêmes valeurs à chaque partie).
static func occupants(lg: Node, places: int, idx: int, tour: int, montee: bool, h: float = -1.0) -> int:
	var t: float = taux(lg, montee, h)
	if t <= 0.0 or places <= 0:
		return 0
	# tirage binomial déterministe : une graine par véhicule et par tour
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(lg.name), idx, tour, montee])
	if places <= 12:
		var n: int = 0
		for _k in range(places):
			if rng.randf() < t:
				n += 1
		return n
	# grandes cabines : loi normale de même moyenne et variance
	var m: float = float(places) * t
	var sd: float = sqrt(float(places) * t * (1.0 - t))
	return clampi(int(round(m + sd * rng.randfn())), 0, places)


## Masse moyenne de passagers par véhicule (kg) dans un sens.
static func charge_kg(lg: Node, places: int, montee: bool, h: float = -1.0) -> float:
	return PAX_KG * float(places) * taux(lg, montee, h)
