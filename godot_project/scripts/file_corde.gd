## File de descente à la corde du mode réseau (retour d'utilisateur du 21/11/2026 : « si on doit descendre à la corde
## en réseau, c'est chacun son tour ») : logique pure, testée seule (bench_piques_reseau).
## Chaque joueur qui attend ou descend se signale (ligne, abscisse de son véhicule, phase). L'hôte groupe les
## demandes d'une même ligne dont les véhicules sont voisins (une même équipe de secouristes, ECART_GROUPE_M) et
## fixe l'ordre : celui qui descend d'abord, puis les autres dans l'ordre de leur demande (à égalité, l'identifiant,
## donc l'ordre d'arrivée au salon). Une demande muette depuis OUBLI_S (joueur parti, coupé) sort de la file.
class_name FileCorde
extends RefCounted

const ECART_GROUPE_M: float = 60.0
const OUBLI_S: float = 4.0
const OUBLI_DESCENTE_S: float = 20.0

## id → {"l": ligne, "s": abscisse, "ph": 0 attend / 1 descend, "t": dernier signe (s), "t0": première demande}
var demandes: Dictionary = {}


## Signe d'un joueur (phase 2 : il est au sol, il sort de la file).
func noter(id: int, l: String, s: float, ph: int, t: float) -> void:
	if ph >= 2:
		demandes.erase(id)
		return
	var d: Dictionary = demandes.get(id, {})
	if d.is_empty() or String(d["l"]) != l:
		d = {"l": l, "t0": t}
	d["s"] = s
	d["ph"] = ph
	d["t"] = t
	demandes[id] = d


func oublier(id: int) -> void:
	demandes.erase(id)


## Files à l'instant t : [[ligne, [identifiants dans l'ordre]], …] (groupes de véhicules voisins).
func calculer(t: float) -> Array:
	for id in demandes.keys():
		# (celui qui descend : oublié seulement après OUBLI_DESCENTE_S de silence ; son départ du salon l'ôte aussitôt)
		var delai: float = OUBLI_DESCENTE_S if int(demandes[id]["ph"]) == 1 else OUBLI_S
		if t - float(demandes[id]["t"]) > delai:
			demandes.erase(id)
	var par_ligne: Dictionary = {}
	for id in demandes:
		var l: String = demandes[id]["l"]
		if not par_ligne.has(l):
			par_ligne[l] = []
		(par_ligne[l] as Array).append(id)
	var out: Array = []
	for l in par_ligne:
		var ids: Array = par_ligne[l]
		ids.sort_custom(func(a, b) -> bool: return float(demandes[a]["s"]) < float(demandes[b]["s"]))
		var groupe: Array = []
		var s_prec: float = -INF
		for id in ids:
			var s: float = float(demandes[id]["s"])
			if not groupe.is_empty() and s - s_prec > ECART_GROUPE_M:
				out.append([l, ordonner(groupe)])
				groupe = []
			groupe.append(id)
			s_prec = s
		if not groupe.is_empty():
			out.append([l, ordonner(groupe)])
	return out


## Ordre d'un groupe : qui descend d'abord, puis par demande la plus ancienne, puis par identifiant.
func ordonner(ids: Array) -> Array:
	var o: Array = ids.duplicate()
	o.sort_custom(func(a, b) -> bool:
		var da: Dictionary = demandes[a]
		var db: Dictionary = demandes[b]
		if int(da["ph"]) != int(db["ph"]):
			return int(da["ph"]) > int(db["ph"])
		if absf(float(da["t0"]) - float(db["t0"])) > 0.05:
			return float(da["t0"]) < float(db["t0"])
		return int(a) < int(b))
	return o


## Rang de `moi` dans une file (-1 : absent).
static func rang(file: Array, moi: int) -> int:
	return file.find(moi)
