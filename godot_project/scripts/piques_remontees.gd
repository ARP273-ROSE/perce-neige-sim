class_name PiquesRemontees
extends Object
## Piques sarcastiques des remontées (retour d'utilisateur, 25/10/2026 : « une grosse
## liste de messages sarcastiques adaptés à chaque type de remontée, quand on
## s'arrête au milieu, qu'on coupe le chemin sans valider le forfait, qu'on
## embarque chaussé au lieu de déchausser et inversement, qu'on loupe la
## cabine ou le siège… et une bonne base pour ne pas avoir tout le temps les
## mêmes »).
##
## Événements × familles (ts : télésiège, tc : télécabine, tk : téléski,
## tph : téléphérique et 3S) ; chaque tirage puise dans la liste de la
## famille ET dans la liste commune de l'événement. Les derniers tirés ne
## ressortent pas, même d'une partie à l'autre (user://piques_remontees.json).
## Format : [fr, en].

const ARRET_COMMUN: Array = [
	["Quelqu'un a encore perdu ses skis au départ. Ou à l'arrivée. Ou les deux.", "Someone lost their skis at the bottom again. Or at the top. Or both."],
	["Chute en gare d'arrivée. L'opérateur a appuyé sur stop avec la rapidité de l'habitude.", "A fall at the top station. The operator hit stop with practised speed."],
	["Arrêt en ligne. Profitez de la vue, c'est compris dans le forfait.", "Stopped mid-line. Enjoy the view, it's included in the pass."],
	["Le conducteur a vu un truc. Ou il a éternué sur le bouton.", "The operator saw something. Or sneezed on the button."],
	["Pause imprévue. Le câble a besoin de réfléchir.", "Unscheduled pause. The cable needs a moment to think."],
	["Immobile au-dessus du vide. Le moment idéal pour faire le point sur sa vie.", "Motionless above the void. Perfect time to reflect on your life choices."],
	["Ça s'est arrêté. Personne ne sait pourquoi. Tradition alpine.", "It stopped. Nobody knows why. Alpine tradition."],
	["Quelqu'un a encore raté le débarquement, en haut.", "Someone botched the unloading up top. Again."],
	["Arrêt technique. Technique, c'est le mot qu'on utilise quand on ne sait pas.", "Technical stop. 'Technical' is what we say when we don't know."],
	["Le vent souffle, le câble se balance, et vous, vous attendez.", "The wind blows, the cable sways, and you wait."],
	["Restez calme : la remontée est prévue pour redémarrer. Un jour.", "Stay calm: the lift is designed to restart. Eventually."],
	["Le gars du poste prend son café. C'est son droit.", "The lift operator is having his coffee. He's entitled to it."],
	["Arrêt. Le silence. Puis quelqu'un, trois sièges plus loin, qui siffle.", "Stopped. Silence. Then someone three chairs down starts whistling."],
	["Bonne nouvelle : vous ne pouvez pas tomber plus bas. Enfin, si, mais non.", "Good news: you can't fall any further. Well, you can, but don't."],
]
const ARRET_TS: Array = [
	["Arrêt : quelqu'un a encore perdu un ski au départ. Il est sous le siège. Et lui, dessus.", "Stopped: someone lost a ski at the bottom again. It's under the chair. He's on it."],
	["Un ski est tombé à l'embarquement. Son propriétaire part sans lui. Ils se retrouveront en haut, ou pas.", "A ski dropped at loading. Its owner left without it. They may meet again up top. Or not."],
	["Quelqu'un est tombé au débarquement. Ils sont trois maintenant, empilés sur la rampe.", "Someone fell at unloading. Now there are three of them, piled on the ramp."],
	["Chute à l'arrivée : il s'est levé trop tard, le siège l'a raccompagné.", "Fall at the top: he stood up too late, the chair escorted him back."],
	["Arrêt : un siège est parti garde-corps levé. Le perchman a hurlé. Tout le monde a entendu.", "Stopped: a chair left with the bar up. The operator yelled. Everyone heard."],
	["Le garde-corps, ça se baisse. Pas pour le décor, pour vous.", "The safety bar goes down. Not for decoration. For you."],
	["Quelqu'un a relevé le garde-corps cinquante mètres trop tôt. On arrête tout, on respire.", "Someone lifted the bar fifty metres too early. Everything stops, everyone breathes."],
	["Un bâton coincé dans le siège. Le bâton a gagné, la remontée a perdu.", "A pole jammed in the chair. The pole won, the lift lost."],
	["Arrêt : un enfant de six ans n'a pas réussi à s'asseoir. Il a été hissé comme un sac de patates.", "Stopped: a six-year-old couldn't sit down. He was hoisted like a sack of potatoes."],
	["Départ raté pour la famille d'à côté : un ski par terre, un bâton en l'air, un papa qui jure.", "Botched start for the family next door: one ski down, one pole flying, one dad swearing."],
	["Quelqu'un est resté debout devant le siège. Le siège n'a pas négocié.", "Someone stayed standing in front of the chair. The chair didn't negotiate."],
	["Gant tombé du siège. Il est là, en dessous, posé sur la neige. Il vous nargue.", "Glove dropped from the chair. There it lies on the snow below. Mocking you."],
	["Bloqué sur un siège, les skis qui pendent. Le grand frisson du pauvre.", "Stuck on a chair, skis dangling. The budget thrill."],
	["Le siège se balance. Votre voisin aussi, mais lui c'est le vin chaud.", "The chair is swinging. So is your neighbour, but that's the mulled wine."],
	["Garde-corps baissé, j'espère ? Parce que là, c'est le moment où on vérifie.", "Safety bar down, I hope? Because now's when you find out."],
	["Les pieds gèlent, le siège grince, et la gare est toujours aussi loin.", "Feet freezing, chair creaking, and the station is just as far away."],
	["Un télésiège à l'arrêt, c'est un banc public très mal placé.", "A stopped chairlift is a very badly placed park bench."],
	["Ne lâchez pas les bâtons. Personne ne viendra les chercher.", "Don't drop your poles. Nobody is going down there to get them."],
	["Le siège d'à côté chante. Faux. Pour au moins dix minutes.", "The next chair is singing. Badly. For at least ten minutes."],
	["Arrêt pile au-dessus de la bosse où vous êtes tombé ce matin. Les gens regardent.", "Stopped right over the mogul you fell on this morning. People are looking."],
	["Le siège oscille doucement. Votre estomac, moins doucement.", "The chair sways gently. Your stomach, less gently."],
	["Bienvenue sur le banc le plus cher de la station.", "Welcome to the most expensive bench in the resort."],
]
const ARRET_TC: Array = [
	["Arrêt : quelqu'un a coincé ses bâtons dans la porte. La porte a gagné.", "Stopped: someone jammed poles in the door. The door won."],
	["Des skis tombés du porte-skis en gare. Le gars court derrière. La cabine, non.", "Skis fell off the rack in the station. The guy runs after them. The cabin doesn't."],
	["Une famille entière a voulu monter dans la même cabine. Avec la poussette.", "A whole family tried to fit in one cabin. With the stroller."],
	["Cabine immobile. Huit inconnus, un silence gênant et quelqu'un qui sent la fondue.", "Gondola stopped. Eight strangers, awkward silence and someone smelling of fondue."],
	["La cabine se balance. C'est normal. C'est ce qu'ils disent tous.", "The cabin is swinging. It's normal. That's what they all say."],
	["Arrêt en cabine : la seule pièce sans issue où personne ne parle de la météo.", "Stopped in a gondola: the only room with no exit where nobody discusses the weather. Kidding, they do."],
	["Les vitres s'embuent. Votre patience aussi.", "The windows fog up. So does your patience."],
	["Quelqu'un a appuyé sur un bouton de la cabine. Il n'y a pas de bouton. Et pourtant.", "Someone pressed a button in the cabin. There is no button. And yet."],
	["Huit places, dix skieurs, zéro mouvement.", "Eight seats, ten skiers, zero movement."],
	["L'enfant en face vous fixe. Vous êtes là pour un moment.", "The kid opposite is staring at you. You'll be here a while."],
	["Cabine arrêtée : le meilleur endroit pour découvrir que votre téléphone n'a plus de batterie.", "Stopped gondola: the best place to discover your phone is dead."],
	["Même la musique d'ascenseur aurait été un progrès.", "Even elevator music would be an improvement."],
]
const ARRET_TK: Array = [
	["Quelqu'un est tombé au départ. La perche est repartie seule, toute fière.", "Someone fell at the start. The bar went up alone, very proud of itself."],
	["Chute au départ : la perche a tiré, les skis ont suivi, le skieur un peu moins.", "Fall at the start: the bar pulled, the skis followed, the skier less so."],
	["Arrêt : un ski perdu dans la trace. Tout le monde l'enjambe. Personne ne le ramasse.", "Stopped: a ski lost in the track. Everyone steps over it. Nobody picks it up."],
	["Quelqu'un est tombé à l'arrivée et n'a pas lâché la perche. Il a fait un tour de poulie, presque.", "Someone fell at the top and didn't let go. He nearly went round the bull-wheel."],
	["Il s'est assis sur la perche. Comme sur une chaise. Le téléski n'est pas un télésiège.", "He sat on the bar. Like a chair. A drag lift is not a chairlift."],
	["Chute en ligne devant vous. Le ballet commence : on se pousse, on lâche, on remonte à pied.", "Someone fell ahead of you. The ballet begins: step aside, let go, hike back up."],
	["Le snowboarder devant vous a tenté la perche en marche arrière. Arrêt.", "The snowboarder ahead tried the bar backwards. Stopped."],
	["Le téléski s'arrête. Vous, non : la perche vous lâche en pleine pente. Bonne chance.", "The drag lift stops. You don't: the bar lets go mid-slope. Good luck."],
	["Arrêt du téléski. Vous voilà debout, en pente, avec un bout de ferraille entre les jambes.", "Drag lift stopped. Here you are, on a slope, with a lump of metal between your legs."],
	["Le moment de vérité du téléski : tenir sur ses carres en attendant que ça reparte.", "The drag lift moment of truth: hold your edges until it moves again."],
	["Pas de siège, pas de vue, juste une perche et vos cuisses qui brûlent.", "No seat, no view, just a bar and burning thighs."],
	["Si vous reculez, vous emportez tout le monde. Pas de pression.", "If you slide back you'll take everyone out. No pressure."],
	["La perche détendue vous regarde. Elle aussi attend.", "The slack bar is looking at you. It's waiting too."],
]
const ARRET_TPH: Array = [
	["Cent personnes, une cabine, zéro mouvement. Le métro de 18 h, en plus haut.", "A hundred people, one cabin, zero movement. Rush-hour subway, but higher."],
	["Arrêt en pleine portée. On voit très bien le fond. Très, très bien.", "Stopped mid-span. You can see the bottom really well. Really, really well."],
	["La cabine oscille sous le câble. Les habitués font semblant de ne rien sentir.", "The cabin sways under the rope. The regulars pretend not to notice."],
	["Le conducteur de cabine sourit. C'est pire que s'il ne souriait pas.", "The cabin attendant is smiling. That's worse than if he wasn't."],
	["Suspendu à des centaines de mètres par quelques câbles. Ils ont été contrôlés. Probablement.", "Hanging hundreds of metres up from a few ropes. They were inspected. Probably."],
	["Immobile entre deux pylônes. Le chariot, lui, a l'air serein.", "Motionless between towers. The carriage looks perfectly calm about it."],
]

const FRAUDE_COMMUN: Array = [
	["« WHOUUUU ! » Trente minutes de queue, et vous passez devant. La file a de la voix.", "\"BOOOOO!\" Thirty minutes of queueing, and you cut in. The queue has a voice."],
	["Deux cents skieurs vous huent en chœur. Jamais vous n'aviez été aussi populaire.", "Two hundred skiers booing in chorus. You've never been so popular."],
	["Ils attendent depuis 9 h 10. Vous, depuis neuf secondes. Ils l'ont remarqué.", "They've been waiting since 9:10. You, for nine seconds. They noticed."],
	["La file entière se retourne. Le silence, puis la bronca.", "The whole queue turns around. Silence, then the jeering."],
	["Un papa vous montre du bâton à ses enfants : « Voilà ce qu'il ne faut pas faire. »", "A dad points you out with his pole: \"That's what not to do, kids.\""],
	["La mamie au bonnet à pompon : « Taborniau ! » (en savoyard : espèce d'imbécile).", "The granny in the bobble hat: \"Taborniau!\" (Savoyard for \"you idiot!\")."],
	["« Eh, bobet ! Y'a la queue, là ! » (bobet : nigaud, en savoyard). La mamie ne plaisante pas.", "\"Oi, bobet! There's a queue here!\" (bobet: Savoyard for nitwit). Granny isn't joking."],
	["« Bon Diou, quel bedan ! » (Bon Dieu, quel abruti !) — la mamie, du fond de la file.", "\"Bon Diou, what a bedan!\" (Good Lord, what a blockhead!) — granny, from the back of the queue."],
	["« Adieu, le resquilleur ! » En Savoie, adieu veut dire bonjour. Là, ça voulait plutôt dire adieu.", "\"Adieu, cheater!\" In Savoie 'adieu' means hello. This time it rather meant goodbye."],
	["La mamie : « Te y crois, toi, que t'as le droit ? » (en savoyard, on met des y partout : tu crois que tu as le droit ?)", "Granny: \"Te y crois, toi?\" (Savoyards put 'y' everywhere: you really think you're allowed?)"],
	["« Tavan ! » siffle la mamie (le taon, en savoyard : la bestiole qui pique et qu'on chasse).", "\"Tavan!\" hisses granny (Savoyard for horsefly: the pest that bites and gets swatted)."],
	["« Grand crétin des Alpes ! » La mamie connaît ses classiques. Et vous, maintenant, aussi.", "\"You great Alpine cretin!\" Granny knows her classics. Now so do you."],
	["« Va donc manger tes diots ailleurs ! » (les diots : saucisses de Savoie). La mamie a la rancune charcutière.", "\"Go eat your diots somewhere else!\" (diots: Savoy sausages). Granny's grudges come cured."],
	["Vous avez gagné trente minutes et perdu trois cents amis.", "You gained thirty minutes and lost three hundred friends."],
	["Les huées vous suivent jusqu'au premier pylône. Le vent les porte bien.", "The boos follow you to the first tower. The wind carries them nicely."],
	["La queue, c'est un contrat social. Vous venez de le déchirer, devant témoins.", "A queue is a social contract. You just tore it up, in front of witnesses."],
	["Le moniteur ESF a sorti son sifflet. Ses douze élèves aussi.", "The ski instructor got his whistle out. So did his twelve pupils."],
	["Vous avez contourné le portique. Le forfait, c'est comme le casque : on le valide.", "You went round the gate. Your pass is like your helmet: you use it."],
	["Pas de bip, pas de remontée. Enfin, en théorie.", "No beep, no lift. In theory."],
	["Le contrôleur vous a vu. Il prend des notes. Mentalement. Pour l'instant.", "The inspector saw you. He's taking notes. Mentally. For now."],
	["Couper par le filet : économie de trois mètres, perte de toute dignité.", "Cutting under the net: three metres saved, all dignity lost."],
	["Le portique était là, en grand, avec des lumières. Vous l'avez vu, avouez.", "The gate was right there, big, with lights. You saw it, admit it."],
	["Resquilleur détecté. Le télésiège vous emmène quand même : il n'est pas rancunier.", "Fare-dodger detected. The lift takes you anyway: it doesn't hold grudges."],
	["Votre forfait à 70 € par jour vous remercie de l'avoir laissé au fond de la poche.", "Your €70-a-day pass thanks you for leaving it in your pocket."],
	["La file d'attente vous déteste. Unanimement.", "The queue hates you. Unanimously."],
	["Passer à côté du portique, c'est comme sonner chez le voisin pour entrer chez soi.", "Skipping the gate is like ringing next door to get into your own house."],
	["Validation : manquée. Regards noirs : validés.", "Validation: skipped. Dirty looks: validated."],
	["Vous avez coupé la file des 6 places. On note.", "You cut the six-seater queue. Noted."],
]

const FRAUDE_TS: Array = [
	["Les portillons s'ouvrent pour tout le monde. Même pour ceux qui n'ont rien validé. Injuste.", "The gates open for everyone. Even those who didn't scan. Unfair."],
	["Vous avez enjambé la file du télésiège. Le moniteur et ses douze élèves vous ont vu.", "You hopped the chairlift queue. The instructor and his twelve pupils saw you."],
	["Le bip du portique, c'est le petit plaisir du matin. Vous vous en privez.", "The gate's beep is the little morning treat. You're missing out."],
]

const CHAUSSE_COMMUN: Array = [
	["En cabine avec les skis aux pieds. Les sept autres passagers apprécient vos carres.", "In the gondola with your skis on. The seven other passengers love your edges."],
	["On déchausse avant de monter. Les porte-skis ne sont pas décoratifs.", "You take your skis off before boarding. The ski racks aren't decorative."],
	["Chaussé dans une cabine : vous venez d'inventer le ski de salon.", "Skis on in a cabin: you've just invented living-room skiing."],
	["Le plancher de la cabine porte désormais votre autographe. En rayures.", "The cabin floor now bears your autograph. In scratches."],
	["Vous essayez de vous asseoir avec 1,70 m de skis aux pieds. C'est du yoga.", "You're trying to sit down with 1.70 m of skis attached. That's yoga."],
	["Le pisteur a vu ça. Il va en parler au briefing de demain.", "The patroller saw that. It'll come up at tomorrow's briefing."],
	["En cabine, chaussé : le contorsionniste du jour, c'est vous.", "Skis on, in a cabin: today's contortionist is you."],
	["Les portes se ferment sur vos spatules. C'était prévisible.", "The doors close on your ski tips. Predictable."],
]
const CHAUSSE_TPH: Array = [
	["Cent places, et c'est vous qui prenez la place de trois avec vos skis aux pieds.", "A hundred spaces, and you take three of them with your skis on."],
	["Dans un téléphérique, on tient ses skis à la main. Pas aux pieds. Jamais.", "In a cable car you hold your skis. Not wear them. Ever."],
	["Le conducteur de cabine a soupiré. Il soupire rarement.", "The cabin attendant sighed. He rarely sighs."],
]

const PIETON_COMMUN: Array = [
	["Un télésiège à pied. Vous comptiez descendre en courant ?", "A chairlift on foot. Were you planning to run back down?"],
	["Oubli des skis : le classique. Heureusement, on vous les a chaussés.", "Forgot the skis: a classic. Luckily someone put them on for you."],
	["Monter sans skis sur un télésiège, c'est comme aller à la piscine en manteau.", "Riding a chairlift without skis is like going swimming in a coat."],
	["À pied dans le couloir des skieurs. Les perchmen ont des yeux partout.", "On foot in the skiers' lane. The lift staff see everything."],
	["Vous avez chaussé au portillon. Avec la grâce d'une girafe sur une patinoire.", "You clicked in at the gate. With the grace of a giraffe on ice."],
	["Les skis étaient sur l'épaule. Ils devaient être aux pieds. Petit détail.", "Skis on the shoulder. They were meant to be on the feet. Small detail."],
]
const PIETON_TK: Array = [
	["Un téléski, à pied. Ambitieux. Très ambitieux.", "A drag lift on foot. Ambitious. Very ambitious."],
	["La perche ne tire pas les piétons. Elle les traîne. Nuance.", "The bar doesn't tow pedestrians. It drags them. Subtle difference."],
	["Chaussez d'abord, accrochez ensuite. L'ordre compte.", "Skis first, bar second. Order matters."],
]

const LOUPE_COMMUN: Array = [
	["Raté. Le suivant arrive. Il ne vous attendra pas non plus.", "Missed it. The next one's coming. It won't wait either."],
	["Le siège est passé, vous êtes resté. C'est une forme de méditation.", "The chair left, you stayed. A form of meditation."],
	["Il fallait avancer jusqu'à la ligne. La ligne jaune. Celle qui est jaune.", "You had to move up to the line. The yellow line. The one that's yellow."],
	["Dix secondes d'hésitation, un siège vide de plus. L'opérateur compte.", "Ten seconds of hesitation, one more empty chair. The operator is counting."],
	["La file derrière vous apprécie votre sens du suspense.", "The queue behind you appreciates your sense of suspense."],
	["Le portillon s'est ouvert, puis refermé. Comme une opportunité.", "The gate opened, then closed. Just like an opportunity."],
	["Vous aviez une mission : vous asseoir. Mission échouée.", "You had one job: sit down. Job failed."],
	["On ne monte pas au regard. Il faut aussi bouger.", "You don't board by staring at it. You also have to move."],
]
const LOUPE_TS: Array = [
	["Le siège vous a frôlé les mollets et il est reparti. Il voulait juste dire bonjour.", "The chair brushed your calves and left. It just wanted to say hi."],
	["Six places libres, zéro passager. Le siège repart déçu.", "Six empty seats, zero passengers. The chair leaves disappointed."],
	["Il fallait s'asseoir quand le siège arrive. Pas lui faire un signe de la main.", "You sit when the chair arrives. You don't wave at it."],
	["Le siège est parti. Votre voisin de file, lui, est bien assis. Il vous fait coucou.", "The chair left. Your queue buddy made it, though. He's waving at you."],
	["Le tapis vous a amené au bon endroit. Le reste, c'était à vous.", "The conveyor brought you to the right spot. The rest was up to you."],
]
const LOUPE_TC: Array = [
	["La cabine est repartie sans vous. Elle avait les portes ouvertes, pourtant.", "The gondola left without you. Doors were wide open, too."],
	["Les portes se sont fermées pile devant votre nez. Le timing parfait. À l'envers.", "The doors closed right in front of you. Perfect timing. Backwards."],
	["Une cabine vide qui part, c'est une cabine qui se moque de vous.", "An empty cabin leaving is a cabin laughing at you."],
	["Il fallait entrer. C'est le principe d'une cabine.", "You were supposed to get in. That's the whole point of a cabin."],
]
const LOUPE_TK: Array = [
	["La perche est passée. Vous êtes resté planté. Comme un piquet de slalom.", "The bar went by. You stayed put. Like a slalom pole."],
	["Rater une perche, c'est un art. Vous êtes un maître.", "Missing a drag-lift bar is an art. You're a master."],
	["La perche suivante, c'est dans une dizaine de secondes. Préparez les fesses.", "Next bar in about ten seconds. Get your bum ready."],
]
const LOUPE_TPH: Array = [
	["Le téléphérique est parti. Le prochain, c'est dans un quart d'heure. Bon courage.", "The cable car left. Next one's in a quarter of an hour. Good luck."],
	["Les portes du téléphérique se sont refermées. Cent personnes vous ont vu rater ça.", "The cable car doors closed. A hundred people watched you miss it."],
]

const SAUT_COMMUN: Array = [
	["Descendre en marche. Audacieux. Interdit, mais audacieux.", "Getting off while moving. Bold. Forbidden, but bold."],
	["Vous avez quitté la remontée en pleine ligne. Les pisteurs adorent ça. Non.", "You left the lift mid-line. Ski patrol loves that. No they don't."],
	["Un débarquement non prévu au programme. Le programme n'est pas d'accord.", "An unscheduled exit. The schedule disagrees."],
	["Évacuation volontaire réussie. Personne ne vous l'avait demandé.", "Voluntary evacuation successful. Nobody asked."],
	["La gare d'arrivée, c'était là-haut. Juste pour info.", "The top station was up there. Just so you know."],
]
const SAUT_TK: Array = [
	["Lâcher la perche avant le haut : la descente commence plus tôt que prévu.", "Letting go of the bar early: the descent starts sooner than planned."],
	["Vous avez lâché. Tout le téléski vous a vu lâcher. Tout.", "You let go. The whole drag lift saw you let go. All of it."],
	["Lâcher en pleine montée, puis remonter à pied. La stratégie du jour.", "Let go halfway, then walk up. Today's strategy."],
]

const DESCENTE_COMMUN: Array = [
	["Descendre en remontée. Les genoux vous disent merci, la fierté non.", "Riding the lift down. Your knees say thanks, your pride doesn't."],
	["Pris dans le mauvais sens : la piste était trop dure, ou la fondue trop bonne ?", "Going down the wrong way: was the run too hard, or the fondue too good?"],
	["La descente en télésiège : vue imprenable sur ceux qui descendent à ski.", "Riding down: a great view of everyone actually skiing it."],
	["Vous redescendez par la remontée. Le Mont-Blanc a fait pareil, c'est ce qu'il dit.", "Riding the lift back down. Even pros do it. That's what they say."],
]

const ARRIVEE_COMMUN: Array = [
	["Arrivé en haut. Maintenant, il faut redescendre. C'est le principe.", "Made it to the top. Now you have to go back down. That's the idea."],
	["Débarquement réussi. On ne l'aurait pas parié.", "Unloaded successfully. Wouldn't have bet on it."],
	["En haut ! La vue est belle, la piste est noire, bon courage.", "At the top! Great view, black run, good luck."],
	["Remontée terminée sans incident. Notez la date.", "Lift ride finished without incident. Mark the date."],
	["Vous êtes en haut. Vos cuisses aussi, mais elles ne sont pas contentes.", "You're at the top. So are your thighs, but they're not happy."],
]
const ARRIVEE_TK: Array = [
	["Perche lâchée au bon endroit. Le moniteur de l'ESF verse une larme.", "Bar released at the right spot. The ski instructor sheds a tear."],
	["Arrivé au bout de la perche sans tomber. L'exploit du jour.", "Made it to the top of the drag lift without falling. Today's feat."],
]

const EVENEMENTS: Array = ["ARRET", "FRAUDE", "CHAUSSE", "PIETON", "LOUPE", "SAUT", "DESCENTE", "ARRIVEE"]


## Famille de piques d'une ligne : ts, tc, tk, tph.
static func famille(lg: LigneRemontee) -> String:
	if lg.teleski():
		return "tk"
	if lg.tricable() or lg.vaetvient() or lg.famille == "cabine_tph":
		return "tph"
	if lg.famille.begins_with("cabine"):
		return "tc"
	return "ts"


static func _liste(evt: String, fam: String) -> Array:
	var c: Dictionary = (load("res://scripts/piques_remontees.gd") as Script).get_script_constant_map()
	var l: Array = []
	if c.has(evt + "_COMMUN"):
		l.append_array(c[evt + "_COMMUN"])
	var cle: String = evt + "_" + fam.to_upper()
	if c.has(cle):
		l.append_array(c[cle])
	return l


static var _vus: Dictionary = {}
static var _charge: bool = false
const FICHIER: String = "user://piques_remontees.json"


static func _charger() -> void:
	if _charge:
		return
	_charge = true
	if FileAccess.file_exists(FICHIER):
		# (fichier vide ou en cours d'écriture par un autre lancement : on
		# repart de zéro, sans erreur)
		var j: JSON = JSON.new()
		if j.parse(FileAccess.get_file_as_string(FICHIER)) == OK and j.data is Dictionary:
			_vus = j.data


static func _sauver() -> void:
	var f: FileAccess = FileAccess.open(FICHIER, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_vus))


## Une pique pour l'événement `evt` sur la ligne `lg` (langue "fr"/"en") :
## les deux tiers des dernières tirées de cette liste ne ressortent pas.
static func pique(evt: String, lg: LigneRemontee, lang: String = "fr") -> String:
	_charger()
	var fam: String = famille(lg)
	var l: Array = _liste(evt, fam)
	if l.is_empty():
		return ""
	var cle: String = evt + "_" + fam
	var vus: Array = _vus.get(cle, [])
	var libres: Array = []
	for i in range(l.size()):
		if not (float(i) in vus or i in vus):
			libres.append(i)
	if libres.is_empty():
		libres = range(l.size())
	var k: int = libres.pick_random()
	vus.append(k)
	while vus.size() > l.size() * 2 / 3:
		vus.pop_front()
	_vus[cle] = vus
	_sauver()
	return l[k][1] if lang == "en" else l[k][0]
