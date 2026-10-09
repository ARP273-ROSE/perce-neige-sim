## Vérifie la banque de piques/avis (pn_quips.gd + pn_quips_extra.gd) :
## listes fusionnées, tirage sans répétition rapprochée.
##   godot --headless --path godot_project -s test_piques.gd
extends SceneTree

func _initialize() -> void:
	var ok: bool = true
	for nom in ["CRASH", "CRASH_LENT", "CRASH_VIOLENT", "DERAIL", "CABIN", "REVERSE", "DOORS_OPEN",
			"SKIEUR_HORS_PISTE", "SKIEUR_RATE", "SKIEUR_EVACUATION", "SKIEUR_VOIE", "SKIEUR_SORTIE",
			"REVIEWS_GREAT", "REVIEWS_ROUGH", "REVIEWS_DISASTER"]:
		var l: Array = PNQuips.liste(nom)
		print("%s : %d" % [nom, l.size()])
		if l.size() < 3:
			ok = false
		if nom.begins_with("REVIEWS"):
			continue
		var vus: Array = []
		for i in range(l.size() / 2):
			var t: String = PNQuips.pique(nom, "fr")
			if t in vus or t == "":
				ok = false
				print("  répétition / vide : ", t)
			vus.append(t)
	for tier in ["great", "rough", "disaster"]:
		var r: Dictionary = PNQuips.pick_review(tier, "en")
		print("  ", r["who"], " — ", r["native"], " — ", r["text"])
	print("TEST_PIQUES " + ("OK" if ok else "ECHEC"))
	quit(0 if ok else 1)
