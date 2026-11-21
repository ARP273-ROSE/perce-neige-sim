## Piques du mode réseau (retour d'utilisateur du 21/11/2026 : « rajoute des phrases sarcastiques pour le réseau ») :
## [français, anglais]. « {nom} » est remplacé par le nom de l'autre joueur. Lues par PNQuips.liste (préfixe
## RESEAU_, même tirage sans répétition rapprochée que les autres piques) ; déclenchées par GuetReseau, affichées
## par CommandesSkieur.pique.
class_name PiquesReseau
extends RefCounted

const RESEAU_ARRIVEE: Array = [
	["{nom} vient d'arriver. Fini de skier comme si personne ne regardait.",
	 "{nom} just showed up. No more skiing like nobody's watching."],
	["{nom} rejoint le salon. Le domaine compte désormais deux experts autoproclamés.",
	 "{nom} joined the lobby. The resort now has two self-appointed experts."],
	["Bienvenue à {nom}. Les excuses pour les chutes sont désormais à préparer à l'avance.",
	 "Welcome, {nom}. Excuses for falls must now be prepared in advance."],
	["{nom} est là. Quelqu'un va enfin voir vos virages. Désolé.",
	 "{nom} is here. Someone will finally see your turns. Sorry."],
	["Connexion de {nom}. Le relais a vérifié son forfait. Pas son niveau.",
	 "{nom} connected. The relay checked their pass. Not their skill."],
]
const RESEAU_DEPART: Array = [
	["{nom} a quitté le salon. Sans dire au revoir, comme au télésiège.",
	 "{nom} left the lobby. Without a goodbye, just like on the chairlift."],
	["{nom} est parti. Vous pouvez de nouveau dire que vous avez tout descendu en schuss.",
	 "{nom} is gone. You can go back to claiming you straight-lined everything."],
	["Plus de {nom}. Le domaine vous appartient. Les dameuses aussi, en principe.",
	 "No more {nom}. The resort is all yours. The groomers too, in theory."],
	["{nom} s'est déconnecté. Probablement parti au vin chaud. Sans vous.",
	 "{nom} disconnected. Probably off for mulled wine. Without you."],
]
const RESEAU_COUPURE: Array = [
	["Liaison perdue. Internet a pris une remontée sans vous.",
	 "Connection lost. The internet took a lift without you."],
	["Coupure réseau. Votre camarade continue de skier, vous, vous continuez d'attendre.",
	 "Network down. Your friend keeps skiing; you keep waiting."],
	["Le relais ne répond plus. Comme le téléphone du pisteur un jour de poudreuse.",
	 "The relay stopped answering. Like the patroller's phone on a powder day."],
	["Signal perdu. À 3 000 m, c'est presque une tradition.",
	 "Signal lost. At 3,000 m it's practically a tradition."],
]
const RESEAU_RECONNEXION: Array = [
	["Reconnecté. Personne n'a rien vu. Enfin, presque.",
	 "Reconnected. Nobody saw a thing. Well, almost."],
	["Le réseau est revenu. Vos excuses aussi, j'espère.",
	 "The network is back. Hopefully so are your excuses."],
	["Liaison rétablie. Vous pouvez reprendre là où vous aviez arrêté de vous voir.",
	 "Link restored. You can pick up where you stopped seeing each other."],
]
const RESEAU_LATENCE: Array = [
	["Latence élevée. {nom} est ici, mais avec un peu de retard. Comme d'habitude, en somme.",
	 "High latency. {nom} is here, just a bit late. As usual, really."],
	["Le réseau rame. Votre camarade avance par petits bonds, tel un chamois en hésitation.",
	 "The network is crawling. Your friend moves in little hops, like an undecided chamois."],
	["Ping au plafond. Les messages prennent le télésiège à pince fixe.",
	 "Ping through the roof. Messages are taking the fixed-grip chair."],
]
const RESEAU_LOIN: Array = [
	["{nom} est à {dist}. Vous skiez ensemble, mais en version très libre.",
	 "{nom} is {dist} away. You're skiing together, in a very loose sense."],
	["{dist} entre vous et {nom}. Le mode réseau, c'est aussi savoir se perdre.",
	 "{dist} between you and {nom}. Multiplayer also means getting lost."],
	["{nom} est à l'autre bout du domaine. Rendez-vous au vin chaud, à la fermeture.",
	 "{nom} is at the far end of the resort. Meet at the mulled wine, at closing time."],
]
const RESEAU_FROLE: Array = [
	["{nom} est passé à quelques centimètres. Le casque, c'était une bonne idée.",
	 "{nom} passed within inches. The helmet was a good call."],
	["Frôlé par {nom}. Dans la vraie vie, ça s'appelle un constat.",
	 "Brushed by {nom}. In real life, that's called an insurance claim."],
	["Collision évitée de justesse avec {nom}. Le relais, lui, a eu peur.",
	 "Near miss with {nom}. The relay was terrified."],
	["{nom} vous a coupé la trace. Le code du skieur le réprouve, la physique l'autorise.",
	 "{nom} cut across your line. The skier's code frowns on it; physics allows it."],
]
const RESEAU_MEME_VEHICULE: Array = [
	["Vous voilà dans le même véhicule que {nom}. Silence gêné garanti.",
	 "Same vehicle as {nom}. Awkward silence guaranteed."],
	["Côte à côte avec {nom}. Le moment idéal pour critiquer les virages de l'autre.",
	 "Side by side with {nom}. The perfect time to critique each other's turns."],
	["{nom} est assis avec vous. Ne touchez pas au garde-corps, c'est {nom} qui décide.",
	 "{nom} is sitting with you. Don't touch the safety bar, {nom} is in charge."],
	["Remontée partagée avec {nom}. Le relais a calé le siège au centimètre près. La conversation, non.",
	 "Sharing the lift with {nom}. The relay synced the seat to the centimetre. Not the conversation."],
]
const RESEAU_PILOTE: Array = [
	["C'est {nom} qui conduit cette remontée. Accrochez-vous.",
	 "{nom} is driving this lift. Hold on."],
	["{nom} a pris les commandes. Vous êtes désormais un passager à sa merci.",
	 "{nom} took the controls. You are now a passenger at their mercy."],
	["Au pupitre : {nom}. Les pisteurs ont été prévenus. Ils prient.",
	 "At the console: {nom}. The patrol has been notified. They're praying."],
]
const RESEAU_URGENCE: Array = [
	["Arrêt d'urgence signé {nom}. Une pure coïncidence, évidemment.",
	 "Emergency stop, courtesy of {nom}. Pure coincidence, obviously."],
	["{nom} a appuyé sur le gros bouton rouge. Il était là, il était rouge, il fallait.",
	 "{nom} pressed the big red button. It was there, it was red, it had to be done."],
	["Arrêt brutal ordonné par {nom}. Les sièges tanguent, l'amitié aussi.",
	 "Hard stop ordered by {nom}. The chairs sway; so does the friendship."],
	["Merci {nom} pour l'arrêt d'urgence. Le câble, lui, ne remercie pas.",
	 "Thanks, {nom}, for the emergency stop. The cable isn't thankful."],
]
const RESEAU_PLUS_RAPIDE: Array = [
	["{nom} file à {vit}. Vous, vous profitez du paysage. C'est voulu, bien sûr.",
	 "{nom} is doing {vit}. You're enjoying the view. On purpose, of course."],
	["{nom} va beaucoup plus vite que vous. Le réseau transmet la vitesse, pas le talent.",
	 "{nom} is much faster than you. The network sends speed, not talent."],
	["À cette allure, {nom} sera en bas avant que vous ayez fini de chausser.",
	 "At that pace, {nom} will be at the bottom before you've clicked in."],
]
const RESEAU_SEUL: Array = [
	["Salon ouvert, personne dedans. Un salon de thé un lundi de mai.",
	 "Lobby open, nobody inside. A tea room on a Monday in May."],
	["Toujours seul dans le salon. Donnez le code, c'est le principe.",
	 "Still alone in the lobby. Share the code, that's the idea."],
	["Mode réseau, un joueur. Techniquement du multijoueur, philosophiquement non.",
	 "Multiplayer, one player. Technically multiplayer, philosophically not."],
	["Vous attendez quelqu'un. Le relais aussi. Il trouve le temps long.",
	 "You're waiting for someone. So is the relay. It's getting bored."],
]
const RESEAU_HOTE_MOI: Array = [
	["Vous êtes désormais l'hôte. Les remontées vous obéissent. Le relief, non.",
	 "You are now the host. The lifts obey you. The terrain doesn't."],
	["Promotion : vous voilà hôte du salon. Aucune augmentation n'est prévue.",
	 "Promotion: you're the lobby host now. No pay rise included."],
]
const RESEAU_HOTE_AUTRE: Array = [
	["{nom} devient l'hôte. Les remontées changent de maître, pas d'humeur.",
	 "{nom} is the host now. The lifts change masters, not moods."],
	["Hôte : {nom}. Toute réclamation est à adresser au relais, qui s'en moque.",
	 "Host: {nom}. Complaints go to the relay, which doesn't care."],
]


# --- descente à la corde à plusieurs, chacun son tour (21/11/2026) ---
const RESEAU_CORDE_FILE_PREMIER: Array = [
	["File d'évacuation : vous passez avant {nom}. À vous l'honneur, et le vide.",
	 "Evacuation queue: you go before {nom}. After you — into the void."],
	["Vous descendez en premier. {nom} regardera comment il ne faut pas faire.",
	 "You go first. {nom} gets to watch how not to do it."],
	["Premier à la corde. {nom} vous remercie de tester le matériel.",
	 "First on the rope. {nom} thanks you for testing the gear."],
]
const RESEAU_CORDE_FILE_APRES: Array = [
	["{nom} passe d'abord. Vous, vous gardez le siège au chaud.",
	 "{nom} goes first. You keep the seat warm."],
	["Chacun son tour : {nom} descend, vous patientez. Comme au guichet, mais en l'air.",
	 "One at a time: {nom} goes down, you wait. Like a ticket queue, but airborne."],
	["File d'attente à la corde. {nom} est devant. La politesse, à 15 m du sol.",
	 "Rope queue. {nom} is ahead. Courtesy, 15 m off the ground."],
]
const RESEAU_CORDE_AUTRE_DESCEND: Array = [
	["{nom} descend à la corde. Regardez bien : c'est votre tour juste après.",
	 "{nom} is going down the rope. Watch closely: you're next."],
	["{nom} quitte le siège avec la grâce d'un sac de pommes de terre.",
	 "{nom} leaves the seat with the grace of a sack of potatoes."],
	["Et voilà {nom} au bout de la corde. Prenez des notes, pas des photos.",
	 "And there goes {nom} on the rope. Take notes, not photos."],
]
const RESEAU_CORDE_AUTRE_TOURNE: Array = [
	["{nom} tourne sur lui-même. La corde n'avait rien demandé.",
	 "{nom} is spinning. The rope didn't ask for this."],
	["{nom} fait la toupie. Dix sur dix pour l'artistique, zéro pour la dignité.",
	 "{nom} is doing the spinning top. Ten for artistry, zero for dignity."],
	["{nom} visite le panorama à 360°. Gratuitement.",
	 "{nom} is enjoying a free 360° panorama."],
]
const RESEAU_CORDE_AUTRE_BALANCE: Array = [
	["{nom} se balance comme un pendule. Galilée serait fier, le secouriste un peu moins.",
	 "{nom} swings like a pendulum. Galileo would be proud, the rescuer less so."],
	["{nom} fait de la balançoire. Le pylône n'est pas un trampoline.",
	 "{nom} is on a swing. The tower is not a trampoline."],
	["Gros balancement pour {nom}. Le vent a choisi son camp.",
	 "Big swing for {nom}. The wind has picked a side."],
]
const RESEAU_CORDE_AUTRE_SOL: Array = [
	["{nom} a touché le sol. Il prétendra qu'il n'a pas eu peur.",
	 "{nom} touched down. They'll claim they weren't scared."],
	["{nom} est en bas, entier. La barre est placée bas, mais placée.",
	 "{nom} is down, in one piece. The bar is low, but it's set."],
	["Atterrissage de {nom} réussi. Applaudissements polis du télésiège.",
	 "{nom} landed. Polite applause from the chairlift."],
]
const RESEAU_CORDE_MON_TOUR: Array = [
	["À vous. {nom} a survécu, statistiquement c'est encourageant.",
	 "Your turn. {nom} survived — statistically encouraging."],
	["Votre tour. Essayez de ne pas faire mieux que {nom}, ce serait vexant.",
	 "Your turn. Try not to outdo {nom}, it'd be awkward."],
	["C'est à vous. La corde est encore tiède.",
	 "You're up. The rope is still warm."],
]
const RESEAU_CORDE_TRAINE: Array = [
	["{nom} hésite à se lancer. Le siège est confortable, on sait.",
	 "{nom} is hesitating. The seat is comfy, we know."],
	["On attend {nom}. Le secouriste regarde sa montre, puis le ciel.",
	 "Waiting for {nom}. The rescuer checks his watch, then the sky."],
	["{nom} prend son temps. Il négocie peut-être avec la corde.",
	 "{nom} is taking their time. Maybe negotiating with the rope."],
]
const RESEAU_CORDE_DERNIER: Array = [
	["Dernier dans le siège. Seul, en l'air, avec une corde. Ambiance.",
	 "Last one on the seat. Alone, in the air, with a rope. Lovely."],
	["Tout le monde est en bas sauf vous. {nom} vous fait signe d'en bas.",
	 "Everyone's down but you. {nom} is waving from below."],
	["Vous êtes le dernier. Le capitaine quitte le navire en dernier, paraît-il.",
	 "You're last. The captain leaves the ship last, they say."],
]
const RESEAU_CORDE_COMPARE_TOURS_LUI: Array = [
	["{nom} a fait plus de tours sur lui-même que vous. Une victoire dont personne ne veut.",
	 "{nom} spun more than you. A victory nobody wants."],
	["Bilan : {nom} a tourné davantage. Vous gagnez à la dignité.",
	 "Result: {nom} spun more. You win on dignity."],
]
const RESEAU_CORDE_COMPARE_TOURS_MOI: Array = [
	["Vous avez fait plus de tours que {nom}. Record du salon, catégorie toupie.",
	 "You spun more than {nom}. Lobby record, spinning-top category."],
	["Plus de rotations que {nom}. Vous avez visiblement plus de panorama à voir.",
	 "More spins than {nom}. You clearly had more view to see."],
]
const RESEAU_CORDE_COMPARE_BALANCE: Array = [
	["Descente comparable à celle de {nom}. Deux pendules, zéro talent.",
	 "Pretty much the same descent as {nom}. Two pendulums, zero talent."],
	["Match nul avec {nom} à la corde. Les juges sont partis boire un vin chaud.",
	 "A draw with {nom} on the rope. The judges went for mulled wine."],
]


## Texte d'une pique `nom_liste` (« RESEAU_… ») où {nom}, {dist} et {vit} sont remplacés.
static func texte(nom_liste: String, lang: String, nom: String = "", dist_m: float = 0.0, vit_ms: float = 0.0) -> String:
	var t: String = PNQuips.pique(nom_liste, lang)
	if t == "":
		return ""
	var dist: String = ("%.1f km" % (dist_m / 1000.0)) if dist_m >= 1000.0 else ("%d m" % roundi(dist_m))
	return t.replace("{nom}", nom if nom != "" else ("someone" if lang == "en" else "quelqu'un")) \
		.replace("{dist}", dist).replace("{vit}", "%d km/h" % roundi(vit_ms * 3.6))
