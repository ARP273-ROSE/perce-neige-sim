## Piques du skieur de nuit (19/11/2026) : [français, anglais]. Lues par PNQuips.liste (même tirage sans
## répétition rapprochée que les autres piques), affichées par CommandesSkieur.pique.
class_name PiquesNuit
extends RefCounted

## À ski sur une piste, la nuit (pistes fermées de 17 h 30 au matin).
const NUIT_PISTE_FERMEE: Array = [
	["Piste fermée. Mais vous, visiblement, vous êtes ouvert à tout.",
	 "Piste closed. You, on the other hand, are clearly open to anything."],
	["Les pistes ferment à 17 h 30. Vous les avez rouvertes, rien que pour vous. Généreux.",
	 "Pistes close at 5:30 pm. You reopened them, just for yourself. Generous."],
	["Il fait nuit, la piste dort, les pisteurs dînent. Il ne manquait que vous.",
	 "It's dark, the piste is asleep, the patrollers are having dinner. Only you were missing."],
	["Ski nocturne : le même ski, sans voir les bosses. Le progrès.",
	 "Night skiing: same skiing, minus seeing the bumps. Progress."],
	["Les panneaux « fermé » brillent dans le noir. Vous aussi, apparemment.",
	 "The \"closed\" signs glow in the dark. Apparently, so do you."],
	["Belle nuit pour une descente que personne ne verra. Sauf le dameur. Surtout le dameur.",
	 "Lovely night for a run nobody will see. Except the groomer driver. Especially him."],
	["Les étoiles sont magnifiques. Regardez-les plutôt que la piste, ce sera plus court.",
	 "The stars are gorgeous. Look at them instead of the piste, it'll be quicker."],
]

## Près d'une dameuse en marche.
const NUIT_DAMEUSE: Array = [
	["Une dameuse. Douze tonnes, une fraise à l'arrière, et vous en anorak. Match équilibré.",
	 "A groomer. Twelve tonnes, a tiller at the back, and you in a ski jacket. Fair fight."],
	["Le dameur vous a vu. Il fait semblant que non, pour la paperasse.",
	 "The groomer driver saw you. He's pretending he didn't, for the paperwork."],
	["Restez derrière la fraise : la neige y est parfaite. Le reste de vous un peu moins.",
	 "Stay behind the tiller: the snow there is perfect. The rest of you, less so."],
	["Les gyrophares orange ne sont pas une invitation à danser.",
	 "The orange beacons are not an invitation to dance."],
	["Ce velours côtelé derrière la machine ? C'est pour demain matin. Pas pour vos traces de ce soir.",
	 "That corduroy behind the machine? It's for tomorrow morning. Not for your tracks tonight."],
	["Dépasser une dameuse en descente : techniquement possible, administrativement passionnant.",
	 "Overtaking a groomer downhill: technically possible, administratively fascinating."],
]

## Près d'un câble de treuil tendu.
const NUIT_CABLE_PRES: Array = [
	["Ce trait noir dans la neige, c'est un câble de treuil tendu. Il n'est pas là pour la déco.",
	 "That dark line in the snow is a tensioned winch cable. It's not decoration."],
	["Câble de treuil : invisible la nuit, inoubliable de près.",
	 "Winch cable: invisible at night, unforgettable up close."],
	["La dameuse est attachée en haut. Vous, vous êtes attaché à rien. Contournez.",
	 "The groomer is tied off at the top. You're tied to nothing. Go around."],
	["Un câble d'acier qui balaie la pente : l'obstacle préféré des skieurs nocturnes. Le dernier, souvent.",
	 "A steel cable sweeping the slope: night skiers' favourite obstacle. Often their last."],
]

## Touché le câble (chute).
const NUIT_CABLE_TOUCHE: Array = [
	["Vous avez trouvé le câble. Le câble vous a trouvé aussi.",
	 "You found the cable. The cable found you right back."],
	["Le treuil gagne aux points. Et par K.-O.",
	 "The winch wins on points. And by knockout."],
	["Câble 1, skieur 0. Rechaussez, l'arbitre ne regarde pas.",
	 "Cable 1, skier 0. Put your skis back on, the referee isn't looking."],
	["Voilà pourquoi on ne skie pas pendant le damage. La démonstration était parfaite.",
	 "That's why you don't ski during grooming. Flawless demonstration."],
]

## Percuté une dameuse.
const NUIT_DAMEUSE_TOUCHE: Array = [
	["Vous avez embrassé une dameuse. Elle ne rappellera pas.",
	 "You kissed a groomer. It won't call back."],
	["Contact avec la lame. La lame va bien, merci.",
	 "Contact with the blade. The blade is fine, thanks."],
	["Douze tonnes contre soixante-quinze kilos : le calcul était vite fait.",
	 "Twelve tonnes versus seventy-five kilos: the maths was quick."],
]
