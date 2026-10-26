class_name Prof
extends RefCounted
## Décompte du temps par système pendant un relevé de fluidité (bouton MESURE,
## touche F10) : chaque _process passe par une enveloppe qui, relevé en cours,
## chronomètre son corps. Hors relevé, le coût est un test de booléen.
## (Relevés du PC du 26/10/2026 : 35 ms de fil principal en jeu, 15 au banc —
## il fallait savoir qui, sur la vraie machine.)

static var actif: bool = false
static var t: Dictionary = {}         # système → µs cumulées pendant le relevé


static func ajouter(nom: String, t0: int) -> void:
	t[nom] = int(t.get(nom, 0)) + Time.get_ticks_usec() - t0
