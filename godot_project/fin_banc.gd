## Fin d'un banc sans écran : les remontées s'y construisent en coroutines, et quitter
## pendant l'une d'elles faisait planter le moteur à la fermeture (code 139, fonctions en
## attente encore vivantes au nettoyage). On arrête d'en lancer, on laisse finir, on quitte.
class_name FinBanc


static func quitter(arbre: SceneTree, main: Node, code: int) -> void:
	for c in arbre.process_frame.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_object() == arbre:
			arbre.process_frame.disconnect(cb)
	var rm: Node = main.get("remontees") as Node if main != null else null
	if rm != null:
		rm.set_process(false)
		var n: int = 0
		while rm.get("_en_cours") != null and not rm.get("_en_cours").pret and n < 3000:
			await arbre.process_frame
			n += 1
	arbre.quit(code)
