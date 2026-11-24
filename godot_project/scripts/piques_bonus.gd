## Banque supplémentaire de piques (retour d'utilisateur du 24/11/2026 : « rajoute des phrases sarcastiques pour toutes
## les phases, réseau ou pas, les pannes et tout le reste […] on aime bien les films de De Funès et Raymond Devos, et
## puis le planté du bâton, le vin chaud, et le dépanneur qui a dit à distance qu'il ne fallait pas tout démonter »).
## Pastiches dans l'esprit, pas de citations. [français, anglais] ; les clés sont les noms des listes existantes
## (PiquesRemontees : « ARRET_COMMUN », « PANNE_COMMUN »… ; PNQuips : « RESEAU_… », « NUIT_… ») — ajoutées à leur
## tirage, même règle sans répétition rapprochée. « {nom}, {dist}, {vit} » : comme dans PiquesReseau.

extends RefCounted

const BONUS: Dictionary = {
	# --- remontées : arrêts ---------------------------------------------------------------------------------------
	"ARRET_COMMUN": [
		["Ça s'arrête. Quand ça s'arrête, c'est que ça ne marche plus. Et quand ça ne marche plus… on attend que ça remarche.",
		 "It stopped. When it stops, it's not working. And when it's not working… you wait for it to work."],
		["Arrêt. Au poste, le chef s'agite, rougit, fait « non, non, non… oh si ». C'était le bouton rouge.",
		 "Stopped. In the hut, the boss flaps, turns red, goes 'no, no, no… oh yes'. It was the red button."],
		["Immobile entre ciel et terre. Philosophiquement, vous n'êtes ni monté, ni descendu.",
		 "Motionless between earth and sky. Philosophically, you have neither gone up nor down."],
		["L'arrêt est momentané. Le moment, lui, peut durer.",
		 "The stop is momentary. The moment, however, may last."],
		["Pendant l'arrêt, révisez votre planté de bâton. Mentalement. Ne lâchez pas les bâtons.",
		 "While stopped, revise your pole plant. Mentally. Don't drop the poles."],
		["Arrêt en ligne. En bas, quelqu'un explique à un perchman qu'il n'a « rien fait ». Le perchman a tout vu.",
		 "Stopped mid-line. Down below, someone tells the attendant he 'didn't do anything'. The attendant saw everything."],
		["On ne bouge plus. Le vin chaud de l'arrivée, lui, refroidit. La vie est injuste.",
		 "Not moving. The mulled wine at the top is cooling down. Life is unfair."],
		["Arrêt. Le câble se repose. Il a beaucoup tourné, il a le tournis.",
		 "Stopped. The cable is resting. It's been going round in circles, it's dizzy."],
		["Le conducteur a appuyé sur stop « pour voir ». Il a vu.",
		 "The operator pressed stop 'just to see'. He saw."],
		["Arrêt. Ceux qui disaient « on va gagner du temps en prenant le télésiège » méditent.",
		 "Stopped. Those who said 'the chairlift will be quicker' are meditating."],
	],
	"ARRET_TS": [
		["Le siège se balance doucement. Vous aussi. Ne regardez pas les skis qui pendent, c'est hypnotique.",
		 "The chair sways gently. So do you. Don't look at your dangling skis, it's hypnotic."],
		["Arrêt. Votre voisin de siège commence à raconter sa saison 1987. Il en a pour longtemps.",
		 "Stopped. Your chair neighbour starts telling you about his 1987 season. It'll take a while."],
		["Un bâton vient de tomber du siège de devant. Il a fait un planté parfait. Dans la poudreuse, à 12 m plus bas.",
		 "A pole just fell from the chair ahead. Perfect plant. In the powder, 12 m below."],
	],
	"ARRET_TC": [
		["Cabine arrêtée. Huit inconnus, un silence, et quelqu'un qui a mangé de la tartiflette à midi.",
		 "Gondola stopped. Eight strangers, a silence, and someone who had tartiflette for lunch."],
		["Arrêt. La cabine oscille. Les conversations aussi.",
		 "Stopped. The cabin sways. So does the conversation."],
	],
	"ARRET_TK": [
		["Le téléski s'arrête. Vous, non : vous êtes à plat sur la neige, perche entre les jambes, l'air digne.",
		 "The T-bar stops. You don't: you're flat in the snow, bar between your legs, looking dignified."],
		["Arrêt du téléski. Remontez à pied, ou attendez. Le téléski ne vous attendra pas, lui.",
		 "T-bar stopped. Walk up, or wait. The T-bar won't wait for you."],
	],
	"ARRET_TPH": [
		["Cabine arrêtée au-dessus du vide. Le cabinier sort sa phrase rassurante. Il la dit très bien, il la dit souvent.",
		 "Cabin stopped above the void. The attendant delivers his reassuring line. He's very good at it. He says it a lot."],
		["Arrêt en ligne. Cent personnes regardent le même pylône. Le pylône ne dit rien.",
		 "Stopped mid-line. A hundred people stare at the same pylon. The pylon says nothing."],
	],
	"FRAUDE_COMMUN": [
		["Pas de forfait ? Au poste, quelqu'un s'étrangle d'indignation, comme un gendarme à qui l'on manque de respect.",
		 "No pass? In the hut, someone chokes with indignation, like an affronted gendarme."],
		["Vous passez sans valider. Le portillon, lui, a une excellente mémoire.",
		 "You walk through without scanning. The gate has an excellent memory."],
		["Resquiller, c'est monter sans payer. Redescendre, en revanche, est gratuit. Pour l'instant.",
		 "Sneaking on is going up without paying. Coming down is free. For now."],
	],
	"CHAUSSE_COMMUN": [
		["Avec les skis aux pieds ? Ah ben bravo. Ah ben c'est réussi.",
		 "With skis on? Oh well done. Oh that's just perfect."],
		["Chaussé dans une remontée où l'on se déchausse. Les autres passagers comptent vos carres.",
		 "Skis on in a lift where you take them off. The other passengers are counting your edges."],
	],
	"PIETON_COMMUN": [
		["À pied sur le domaine : c'est la randonnée, version chaussures de ski. Le podologue vous remercie.",
		 "On foot on the slopes: hiking, ski-boot edition. Your podiatrist thanks you."],
		["Vous marchez. Les skis, eux, se reposent. Inversion des rôles.",
		 "You're walking. The skis are resting. A role reversal."],
	],
	"LOUPE_COMMUN": [
		["Raté. Le siège est parti sans vous. Il ne vous en veut pas : il n'a pas remarqué.",
		 "Missed. The chair left without you. It's not offended: it didn't notice."],
		["Loupé ! Le suivant arrive. Lui aussi, vous pouvez le louper. Il y en a plein.",
		 "Missed! The next one's coming. You can miss that one too. There are plenty."],
		["Vous arrivez trop tard. Ou le siège trop tôt. Question de point de vue.",
		 "You arrived too late. Or the chair too early. It's a matter of perspective."],
	],
	"SAUT_COMMUN": [
		["Saut en marche. Spectaculaire. Le planté de bâton à l'arrivée, un peu moins.",
		 "Jumped off a moving lift. Spectacular. The pole plant on landing, less so."],
		["Vous sautez. La gravité, fidèle, vous rattrape. Toujours.",
		 "You jump. Gravity, ever loyal, catches you. Every time."],
	],
	"DESCENTE_COMMUN": [
		["Vous redescendez par la remontée. Un aller-retour pour rien, mais avec vue.",
		 "Riding the lift back down. A round trip for nothing, but with a view."],
		["Descendre en remontée : techniquement une descente, moralement une défaite.",
		 "Riding a lift down: technically a descent, morally a defeat."],
	],
	"ARRIVEE_COMMUN": [
		["Arrivé en haut. Le vin chaud est à droite, la piste à gauche. Choix cornélien.",
		 "Made it to the top. Mulled wine on the right, the slope on the left. A tough call."],
		["Arrivée. Levez-vous maintenant. Pas dans dix mètres. Maintenant.",
		 "Arrival. Stand up now. Not in ten metres. Now."],
		["En haut ! Ceux qui ont le vertige peuvent rouvrir les yeux.",
		 "At the top! Those afraid of heights may open their eyes."],
	],
	"RESTE_COMMUN": [
		["Vous restez à bord. Au tour suivant, vous serez un habitué.",
		 "You're staying on. Next lap, you'll be a regular."],
		["Pas descendu ? La remontée apprécie la fidélité, mais elle ne fait pas de carte.",
		 "Didn't get off? The lift appreciates loyalty, but there's no loyalty card."],
	],
	"ARRIVEE_BAS_COMMUN": [
		["Retour au point de départ. La boucle est bouclée. Comme le skieur.",
		 "Back where you started. Full circle. Like the skier."],
	],
	"ATTENTE_COMMUN": [
		["On vous attend. Avancez, avancez ! Plus vite ! Non, pas si vite !",
		 "They're waiting for you. Move, move! Faster! No, not that fast!"],
		["Le cabinier tapote sa montre. Elle ne lui a rien fait, pourtant.",
		 "The attendant taps his watch. It never did anything to him."],
	],
	# --- remontées : pannes et exploitation -----------------------------------------------------------------------
	"PANNE_COMMUN": [
		["Panne. Le dépanneur, au téléphone, a été très clair : surtout ne pas tout démonter pour essayer de réparer soi-même.",
		 "Breakdown. The repairman, on the phone, was very clear: do NOT take everything apart to fix it yourself."],
		["Panne. Quelqu'un au poste a sorti un tournevis. Le dépanneur, à distance, a dit « reposez ça ».",
		 "Breakdown. Someone in the hut got out a screwdriver. The repairman, remotely, said 'put that down'."],
		["Panne. Le chef d'exploitation crie, gesticule, fait « tss tss tss ». Le moteur reste de marbre.",
		 "Breakdown. The manager shouts, waves his arms, goes 'tut tut tut'. The motor is unmoved."],
		["Une panne, c'est quand ça ne marche pas. Deux pannes, c'est quand ça ne marche vraiment pas.",
		 "One breakdown is when it doesn't work. Two breakdowns is when it really doesn't work."],
		["Panne. Le dépanneur arrive. Il a dit « j'arrive » il y a vingt minutes. C'est le même « j'arrive ».",
		 "Breakdown. The repairman is coming. He said 'on my way' twenty minutes ago. Same 'on my way'."],
		["Panne. Au poste, on a essayé d'éteindre et de rallumer. Le dépanneur dit que ce n'était pas la peine de tout débrancher.",
		 "Breakdown. They tried turning it off and on again. The repairman says there was no need to unplug everything."],
		["Panne. Le dépanneur, par téléphone, demande « vous avez touché à quoi ? ». Silence gêné au poste.",
		 "Breakdown. The repairman, on the phone, asks 'what did you touch?'. Embarrassed silence in the hut."],
		["Panne. Une pièce est tombée par terre. Personne ne sait d'où. Le dépanneur dit de ne surtout pas la remettre au hasard.",
		 "Breakdown. A part fell on the floor. Nobody knows where from. The repairman says not to put it back at random."],
		["Panne. Ça tombe bien, il y a un vin chaud en gare. Ça tombe mal, vous êtes en ligne.",
		 "Breakdown. Good news: mulled wine at the station. Bad news: you're mid-line."],
	],
	"PANNE_VENT_FORT_COMMUN": [
		["Vent fort. La remontée ralentit, le vent, lui, n'a pas reçu la consigne.",
		 "High wind. The lift slows down; nobody told the wind."],
	],
	"PANNE_GIVRE_COMMUN": [
		["Givre sur le câble. Le dépanneur conseille de ne pas le gratter à l'ongle.",
		 "Ice on the cable. The repairman advises against scraping it with a fingernail."],
	],
	"PANNE_SURCHAUFFE_COMMUN": [
		["Surchauffe. Par −15 °C. Il fallait le faire. Le moteur l'a fait.",
		 "Overheating. At −15 °C. Takes talent. The motor has it."],
	],
	"PANNE_COUPURE_RESEAU_COMMUN": [
		["Coupure de courant. Au poste, quelqu'un cherche l'interrupteur à tâtons. Le dépanneur dit que ce n'est pas l'interrupteur.",
		 "Power cut. In the hut, someone gropes for the light switch. The repairman says it isn't the switch."],
	],
	"REPRISE_COMMUN": [
		["Ça repart ! Personne ne sait pourquoi ça s'était arrêté. Personne ne sait pourquoi ça repart. L'harmonie.",
		 "It's moving again! Nobody knows why it stopped. Nobody knows why it restarted. Harmony."],
		["Redémarrage. Le chef bombe le torse comme s'il avait tout réparé de ses mains.",
		 "Restarting. The boss puffs out his chest as if he fixed it with his own hands."],
	],
	"SECOURS_COMMUN": [
		["Moteur de secours. Il va doucement. Il a l'âge de ses responsabilités.",
		 "Backup motor. It goes slowly. It's earned the right."],
		["Secours enclenché. On avance au pas de sénateur. Profitez, c'est le tarif lent.",
		 "Backup engaged. Moving at a senator's pace. Enjoy, it's the slow rate."],
	],
	"REMISE_COMMUN": [
		["Remise en service. Le dépanneur repart avec ses outils… et la pièce qu'on avait démontée « pour voir ».",
		 "Back in service. The repairman leaves with his tools… and the part someone removed 'just to see'."],
	],
	"DEPANNAGE_COMMUN": [
		["Dépannage. Il a suffi de ne rien démonter. Comme quoi.",
		 "Repaired. All it took was not taking anything apart. Who knew."],
		["Réparé à distance. Le dépanneur a dit de tourner une molette. On l'a tournée. Dans le bon sens, cette fois.",
		 "Fixed remotely. The repairman said to turn a knob. We turned it. The right way, this time."],
	],
	"REFUS_COMMUN": [
		["Démarrage refusé. La machine dit non. Elle le dit poliment, mais fermement.",
		 "Start refused. The machine says no. Politely, but firmly."],
	],
	"INTERVENTION_COMMUN": [
		["Intervention en cours. Ne pas déranger le technicien. Surtout pas avec des conseils.",
		 "Repair in progress. Don't disturb the technician. Especially not with advice."],
	],
	"EVACUATION_COMMUN": [
		["Évacuation. On descend à la corde. Retenez votre bâton, pas votre souffle.",
		 "Evacuation. Down the rope. Hold on to your poles, not your breath."],
		["Évacuation : le seul moment où descendre d'une remontée est applaudi.",
		 "Evacuation: the only time getting off a lift earns applause."],
	],
	"HORS_SERVICE_COMMUN": [
		["Hors service. Comme le vin chaud à 16 h 59. Tout ferme, tout le monde râle.",
		 "Out of service. Like the mulled wine at 4:59 pm. Everything closes, everyone grumbles."],
	],
	"CORDE_COMMUN": [
		["Descente à la corde. Le harnais est réglé. Votre dignité, beaucoup moins.",
		 "Roping down. The harness is adjusted. Your dignity, less so."],
	],
	"CORDE_SOL_COMMUN": [
		["Au sol ! Vous voilà aussi bas que le moral du chef d'exploitation.",
		 "On the ground! As low as the operations manager's morale."],
	],
	"CORDE_LONG_COMMUN": [
		["Une minute à la corde. Le temps s'étire, la corde aussi, heureusement très peu.",
		 "A minute on the rope. Time stretches, so does the rope — very little, thankfully."],
	],
	# --- réseau -------------------------------------------------------------------------------------------------
	"RESEAU_ARRIVEE": [
		["{nom} entre dans le salon avec l'aisance d'un maître d'hôtel. Il va tout critiquer, poliment.",
		 "{nom} enters the lobby like a head waiter. He'll criticise everything, politely."],
		["{nom} est là. Vin chaud pour deux ?",
		 "{nom} is here. Mulled wine for two?"],
	],
	"RESEAU_DEPART": [
		["{nom} est parti. Sans dire au revoir. Les meilleurs partent comme ça. Les autres aussi.",
		 "{nom} left. Without a goodbye. The best ones leave like that. So do the others."],
	],
	"RESEAU_COUPURE": [
		["Liaison coupée. Le dépanneur, à distance, conseille de ne pas démonter la box.",
		 "Connection lost. The repairman, remotely, advises against taking the router apart."],
		["Plus de réseau. Vous êtes seul, comme un moniteur un jour de pluie.",
		 "No network. You're alone, like a ski instructor on a rainy day."],
	],
	"RESEAU_RECONNEXION": [
		["Reconnecté. Personne n'a rien démonté, et ça a marché. Retenez la leçon.",
		 "Reconnected. Nobody took anything apart, and it worked. Remember that."],
	],
	"RESEAU_LATENCE": [
		["Le réseau rame. {nom} vous voit avec un temps de retard. Comme d'habitude, en somme.",
		 "The network is lagging. {nom} sees you a beat late. Business as usual, then."],
	],
	"RESEAU_SEUL": [
		["Seul dans le salon. Vous êtes à la fois le meilleur et le pire skieur. Statistiquement imparable.",
		 "Alone in the lobby. You're both the best and the worst skier. Statistically unbeatable."],
	],
	"RESEAU_URGENCE": [
		["Arrêt d'urgence. Chez {nom} aussi. Vous êtes désormais deux à ne pas savoir pourquoi.",
		 "Emergency stop. For {nom} too. Now two people don't know why."],
	],
	"RESEAU_PILOTE": [
		["{nom} prend les commandes. Accrochez-vous, et prévoyez un vin chaud pour après.",
		 "{nom} takes the controls. Hold on, and plan a mulled wine for afterwards."],
	],
	"RESEAU_FROLE": [
		["{nom} vous frôle. Un planté de bâton de plus, et c'était dans votre ski.",
		 "{nom} brushes past. One more pole plant and it was in your ski."],
	],
	"RESEAU_MEME_VEHICULE": [
		["Même véhicule que {nom}. Discutez. Ou faites semblant de regarder le paysage, comme tout le monde.",
		 "Same vehicle as {nom}. Chat. Or pretend to admire the view, like everyone does."],
	],
	# --- nuit ---------------------------------------------------------------------------------------------------
	"NUIT_PISTE_FERMEE": [
		["Piste fermée la nuit. Le vin chaud aussi. Vous êtes le seul ouvert, et c'est bien le problème.",
		 "Slope closed at night. So is the mulled wine. You're the only thing open, which is the problem."],
	],
	"NUIT_DAMEUSE": [
		["Une dameuse. Elle pèse 12 tonnes et ne vous a pas vu. Faites-vous remarquer autrement qu'en dessous.",
		 "A snow groomer. It weighs 12 tonnes and hasn't seen you. Get noticed some other way than underneath."],
	],
}


## Liste `nom` de la banque (vide si rien).
static func liste(nom: String) -> Array:
	return BONUS.get(nom, [])
