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

# Resté à bord en gare pour repartir dans l'autre sens (retour d'utilisateur, 02/11/2026).
const RESTE_COMMUN: Array = [
	["Vous êtes arrivé. Ah non, finalement, vous repartez.", "You've arrived. Oh wait, no, you're leaving again."],
	["Le but d'une remontée, c'est d'en descendre. Dernier rappel.", "The point of a lift is getting off it. Final reminder."],
	["Vous n'avez rien oublié là-haut, à part d'y aller.", "You left nothing up there, except actually going there."],
	["Forfait journée rentabilisé au kilomètre, sans une seule piste.", "Getting your day pass's worth by the kilometre, without a single run."],
	["Faire demi-tour au sommet : l'alpinisme sans la partie pénible.", "Turning around at the summit: mountaineering minus the hard part."],
	["La neige est dehors, au cas où.", "The snow is outside, just so you know."],
	["L'opérateur vous a vu. Il a choisi de ne rien dire. C'est pire.", "The operator saw you. He chose to say nothing. That's worse."],
	["Retour au point de départ. Votre journée, résumée.", "Back where you started. Your day, in a nutshell."],
]
const RESTE_TC: Array = [
	["Les portes se sont ouvertes, puis refermées. Vous, vous n'avez pas bougé.", "The doors opened, then closed. You didn't move."],
	["Vous restez dans la cabine. Vous avez trouvé la banquette à votre goût ?", "Staying in the gondola. Found the bench to your liking?"],
	["Tour de manège offert par la poulie. Pas de peluche à la sortie.", "A free spin round the bullwheel. No teddy bear at the end."],
	["Huit places, de la buée et personne pour vous juger. Sauf nous.", "Eight seats, foggy windows and nobody to judge you. Except us."],
	["Pour le prix d'un forfait, une navette sans fin. La RATP est jalouse.", "For the price of a pass, an endless shuttle. The Paris metro is jealous."],
	["Vos skis sont restés sur la porte. Eux aussi auraient aimé descendre.", "Your skis stayed on the door. They'd have liked to get off too."],
	["Vous repartez dans la même cabine. Elle commence à s'attacher.", "Leaving in the same gondola. It's starting to get attached."],
	["Une télécabine, ça se quitte aussi. C'est prévu, il y a des portes.", "You can leave a gondola too. It's designed for it: there are doors."],
]
const RESTE_TPH: Array = [
	["Aller-retour sans mettre un pied dehors. Le touriste japonais salue la méthode.", "A round trip without setting foot outside. Tourists everywhere salute you."],
	["Le cabinier refait son annonce pour vous tout seul. Il ne l'oubliera pas.", "The cabin attendant repeats his announcement just for you. He won't forget this."],
	["Vous étiez déjà là il y a cinq minutes. La cabine s'en souvient.", "You were here five minutes ago. The cabin remembers."],
	["Tout ce câble et ces tonnes d'acier pour vous ramener où vous étiez.", "All that cable and tons of steel to take you back where you were."],
	["Un téléphérique, ça a deux sens. Vous tenez à vérifier les deux, c'est sérieux.", "A cable car goes both ways. You're checking both, very thorough."],
	["Le sommet était pourtant juste là, derrière la porte.", "The summit was right there, just past the door."],
	["Vous gardez votre place près de la vitre. Personne ne vous la disputait.", "Keeping your spot by the window. Nobody was fighting you for it."],
	["Soixante places, et vous êtes le seul à ne pas être sorti. Remarqué.", "Sixty places, and you're the only one who stayed on. Noticed."],
]
const RESTE_TS: Array = [
	["Vous aviez débarqué. C'était presque réussi. Et vous revoilà assis.", "You had unloaded. Nearly a success. And now you're sitting down again."],
	["Reprendre le siège en sens inverse : la piste vous a regardé de travers ?", "Taking the chair back down: did the run give you a funny look?"],
	["Le préposé vous a vu faire le tour de la gare pour vous rasseoir. Il a tout noté.", "The attendant watched you circle the station to sit back down. He took notes."],
	["Sur le siège en descente, jambes pendantes, face au vide. Beau programme.", "On the chair going down, legs dangling, facing the void. Great plan."],
	["Tout le monde descend à ski. Vous, vous saluez ceux qui montent.", "Everyone skis down. You wave at the people coming up."],
	["Vous passez devant tous ceux qui montent. Ils ont des questions.", "You're passing everyone on their way up. They have questions."],
	["Le télésiège, ça se prend une fois par montée. D'habitude.", "A chairlift is usually taken once per climb. Usually."],
]

# Arrivée à la gare du bas (descendu en remontée) : les piques d'ARRIVEE parlent du sommet.
const ARRIVEE_BAS_COMMUN: Array = [
	["De retour en bas. Sans une seule piste, c'est plus reposant.", "Back at the bottom. Without a single run: much more restful."],
	["En bas. Vos skis n'ont toujours pas touché la neige.", "At the bottom. Your skis still haven't touched the snow."],
	["Descente terminée, zéro virage, zéro chute. Performance intacte.", "Descent complete: zero turns, zero falls. A flawless record."],
	["Arrivé en bas par le chemin des gens prudents.", "Reached the bottom the cautious way."],
	["La gare du bas vous accueille. Elle ne pose pas de questions, elle.", "The bottom station welcomes you. It, at least, asks no questions."],
	["Vous voilà où tout le monde arrive à ski, avec moins de mérite.", "You're where everyone ends up on skis, with less merit."],
]

## Pannes et situations d'exploitation (retour d'utilisateur du 16/11/2026 : « un stock de phrases sarcastiques pour
## toutes les nouvelles situations et pannes sur les remontées ») : une liste par panne du catalogue
## (PANNE_<identifiant>, repli sur PANNE), puis reprise automatique, moteur de secours, remise en service, dépannage
## d'un bouton, départ refusé, intervention, évacuation, hors service, descente à la corde, véhicule qui attend.
const PANNE_COMMUN: Array = [
	["Une panne. Le voyant est rouge, l'ambiance aussi.", "A fault. The light is red, and so is the mood."],
	["Ça clignote au poste. Ce n'est pas Noël.", "Something's flashing in the hut. It isn't Christmas."],
	["La remontée fait un caprice. Elle a le droit, elle a quarante ans.", "The lift is throwing a tantrum. Fair enough, it's forty."],
	["Défaut signalé. Le technicien soupire déjà, on l'entend d'ici.", "Fault reported. You can hear the technician sighing from here."],
	["Un capteur s'est vexé. On négocie.", "A sensor took offence. Negotiations are under way."],
	["Panne. Le mot que le service commercial appelle « aléa d'exploitation ».", "A breakdown. Marketing calls it an 'operational variance'."],
	["La machine a dit non. Poliment, mais non.", "The machine said no. Politely, but no."],
	["Incident technique. Votre forfait, lui, continue de tourner.", "Technical incident. Your pass, however, keeps running."],
]
const PANNE_VENT_FORT_COMMUN: Array = [
	["Vent fort : on roule à moitié. Deux fois plus de temps pour avoir deux fois plus froid.", "Strong wind: half speed. Twice the time to get twice as cold."],
	["Ça souffle. La ligne ralentit, vos convictions aussi.", "It's blowing. The line slows down, and so does your resolve."],
	["Vent fort. Tenez votre bonnet, personne n'ira le chercher.", "Strong wind. Hold on to your hat, nobody's fetching it."],
	["L'anémomètre s'affole. Lui, au moins, il fait du sport.", "The anemometer is going wild. At least something's getting exercise."],
]
const PANNE_VENT_FORT_TS: Array = [
	["Vent fort sur le siège : ça balance, c'est gratuit, c'est le manège.", "Strong wind on the chair: it swings, it's free, it's a fairground ride."],
	["Le siège penche. C'est le vent, pas votre voisin. Enfin, pas seulement.", "The chair is leaning. It's the wind, not your neighbour. Not only, anyway."],
]
const PANNE_TEMPETE_COMMUN: Array = [
	["Seuil de vent dépassé : tout s'arrête. Éole a gagné, comme d'habitude.", "Wind limit exceeded: everything stops. The wind wins, as usual."],
	["Tempête. La remontée est fermée, votre bouche devrait l'être aussi : ça givre.", "Storm. The lift is closed; your mouth should be too, it's freezing in."],
	["Arrêt pour vent. Le drapeau de la gare est à l'horizontale, et il a peur.", "Stopped for wind. The station flag is horizontal, and frightened."],
	["On ne discute pas avec une rafale à 90. On attend, et on fait semblant d'aimer ça.", "You don't argue with a 90 km/h gust. You wait and pretend to enjoy it."],
]
const PANNE_COUPURE_RESEAU_COMMUN: Array = [
	["Coupure de courant. Quelqu'un en vallée a branché un grille-pain de trop.", "Power cut. Someone in the valley plugged in one toaster too many."],
	["Plus de réseau. La montagne redevient ce qu'elle était : haute et sans moteur.", "Mains gone. The mountain is back to what it was: tall and engineless."],
	["Le réseau est tombé. Le diesel de secours tousse, il arrive.", "The grid is down. The back-up diesel is coughing its way over."],
	["Panne d'électricité. Pour les réclamations, écrire à la foudre.", "Power failure. Complaints may be addressed to the lightning."],
]
const PANNE_VARIATEUR_COMMUN: Array = [
	["Défaut du variateur. Il variait, il ne varie plus.", "Drive fault. It used to vary. It no longer does."],
	["Le variateur boude. Une armoire électrique a ses humeurs.", "The drive is sulking. Electrical cabinets have moods."],
	["Variateur en défaut : on éteint, on rallume. Oui, comme votre box.", "Drive fault: off, then on again. Yes, like your router."],
]
const PANNE_SURCHAUFFE_COMMUN: Array = [
	["Le réducteur chauffe. Il est le seul à avoir chaud ici.", "The gearbox is overheating. It's the only thing here that's warm."],
	["Surchauffe : on lève le pied. La mécanique transpire pour vous.", "Overheating: easing off. The machinery is sweating on your behalf."],
	["Ça sent l'huile chaude au local. Vitesse réduite, nez bouchés.", "Smells of hot oil in the machine room. Reduced speed, pinched noses."],
]
const PANNE_FREIN_SERVICE_COMMUN: Array = [
	["Défaut du frein de service. Rassurez-vous : il a freiné. C'est après que ça se complique.", "Service brake fault. Relax, it braked. It's afterwards that gets complicated."],
	["Le frein a serré tout seul. Il est consciencieux, lui.", "The brake applied itself. Conscientious little thing."],
	["Frein en défaut. On ne repart pas tant qu'il n'a pas présenté ses excuses.", "Brake fault. We're not leaving until it apologises."],
]
const PANNE_SECU_LIGNE_COMMUN: Array = [
	["La boucle de sécurité s'est ouverte. Quelque part, un fil s'ennuie.", "The safety circuit opened. Somewhere, a wire got bored."],
	["Sécurité de ligne : un pylône a quelque chose à dire. On l'écoute.", "Line safety: a tower has something to say. We're listening."],
	["Un capteur de pylône a déclenché. C'est peut-être un corbeau. C'est souvent un corbeau.", "A tower sensor tripped. Could be a crow. It's often a crow."],
]
const PANNE_GIVRE_COMMUN: Array = [
	["Givre sur le câble. C'est joli, ça brille, ça ralentit.", "Rime on the rope. Pretty, sparkly, slow."],
	["Le câble a mis son manteau blanc. On roule doucement pour ne pas le froisser.", "The rope put its white coat on. We go gently so as not to crease it."],
	["Givre : les galets patinent, vous patientez.", "Rime: the sheaves slip, you wait."],
]
const PANNE_TENSION_COMMUN: Array = [
	["Le contrepoids est en bout de course. Quinze tonnes de béton qui disent stop.", "The counterweight ran out of travel. Fifteen tonnes of concrete saying stop."],
	["Tension du câble hors limite. Il s'est détendu ; vous, non.", "Rope tension out of range. It relaxed. You didn't."],
	["Course du contrepoids : le câble a pris un centimètre, la direction un cachet.", "Counterweight travel: the rope gained an inch, management took an aspirin."],
]
const PANNE_SORTIE_CABLE_COMMUN: Array = [
	["Le câble est sorti des galets. Ce n'est pas prévu au programme. Ni au forfait.", "The rope left the sheaves. Not on the programme. Nor in the pass."],
	["Déraillement. Le mot que personne ne voulait lire aujourd'hui.", "Deropement. The word nobody wanted to read today."],
	["Câble déraillé : on ne bouge plus, on ne saute pas, on attend la corde.", "Rope off the sheaves: don't move, don't jump, wait for the rescue rope."],
	["Le rattrape-câble a fait son travail. C'est le seul aujourd'hui.", "The rope catcher did its job. The only one that did today."],
]
const PANNE_DERAILLEMENT_TPH_COMMUN: Array = [
	["Le chariot a quitté son câble porteur. Les secouristes ont posé leur café.", "The carriage left its track rope. The rescuers have put their coffee down."],
	["Déraillement du chariot. La cabine ne tombe pas : le frein tient. La conversation, moins.", "Carriage derailed. The cabin isn't falling: the brake holds. The conversation doesn't."],
	["Immobilisés entre deux gares. Le cabinier relit la notice, à voix haute, pour rassurer.", "Stuck between stations. The attendant is reading the manual aloud, to reassure."],
]
const PANNE_SORTIE_CABLE_TK_COMMUN: Array = [
	["Le câble du téléski a déraillé. Lâchez la perche, la descente est offerte.", "The drag lift rope came off. Let go of the pole, the run down is on the house."],
	["Déraillement : la perche ne tire plus. Vos cuisses reprennent le service.", "Rope off: the pole stopped pulling. Your thighs are back on duty."],
	["Plus de câble, plus de montée. Il reste la pente, et elle est dans le bon sens.", "No rope, no uphill. There's still the slope, and it points the right way."],
]
const PANNE_PINCE_COMMUN: Array = [
	["Contrôle de pince : une pince a un doute. On ne part pas avec une pince qui doute.", "Grip check: one grip has doubts. We don't leave with a doubting grip."],
	["La pince n'a pas serré comme il faut. Elle repassera l'examen.", "The grip didn't clamp properly. It will resit the exam."],
	["Défaut de pince. Une pièce de quinze kilos tient votre vie ; on la laisse se concentrer.", "Grip fault. A fifteen-kilo part holds your life; let it concentrate."],
]
const PANNE_ESPACEMENT_COMMUN: Array = [
	["Défaut d'espacement : deux véhicules se suivent de trop près. Comme sur l'autoroute, mais en l'air.", "Spacing fault: two carriers too close. Like the motorway, but airborne."],
	["Les sièges se collent. On remet de la distance, comme en 2020.", "The chairs are bunching up. Back to distancing, 2020 style."],
	["Espacement hors tolérance. La gare recompte ses moutons.", "Spacing out of tolerance. The station is recounting its sheep."],
]
const PANNE_PORTES_COMMUN: Array = [
	["Porte non verrouillée. Quelqu'un a encore voulu monter avec son sac à dos de l'Everest.", "Door not locked. Someone tried to board with an Everest rucksack again."],
	["Une porte bâille. On ne part pas la bouche ouverte.", "A door is yawning. We don't leave with our mouth open."],
	["Porte mal fermée. Le cabinier pousse, la porte résiste, le public commente.", "Door ajar. The attendant pushes, the door resists, the audience comments."],
]
const PANNE_CHUTE_COMMUN: Array = [
	["Chute à l'embarquement. Applaudissements dans la file.", "Fall at loading. Applause from the queue."],
	["Quelqu'un s'est assis à côté du siège. C'est une technique. Mauvaise.", "Someone sat down next to the chair. It's a technique. A bad one."],
	["Chute au départ : un ski ici, un ski là, la dignité plus loin.", "Fall at the start: one ski here, one there, dignity further off."],
]
const PANNE_CHUTE_TK: Array = [
	["Chute au téléski : il a lâché la perche, la perche ne l'a pas regretté.", "Drag lift fall: he let go of the pole. The pole had no regrets."],
	["Un débutant en travers de la trace. On arrête, on le ramasse, on recommence.", "A beginner across the track. Stop, scoop, start again."],
]
const PANNE_DEPASSEMENT_COMMUN: Array = [
	["Sécurité de dépassement : quelqu'un a oublié de descendre. Il visite la poulie.", "Overrun safety: someone forgot to get off. They're touring the bullwheel."],
	["Il n'a pas lâché à l'arrivée. La barrette de sécurité, elle, a lâché.", "He didn't let go at the top. The safety gate did."],
	["Dépassement en gare amont. Le perchman lève les yeux au ciel, qui est tout près.", "Overrun at the top. The operator rolls his eyes to heaven, which is close by."],
]
const PANNE_ENROULEUR_COMMUN: Array = [
	["Un enrouleur est bloqué : une perche pend, molle, vexée.", "A retractor jammed: one pole hangs limp and offended."],
	["Enrouleur coincé. Prenez la perche suivante, celle-ci fait grève.", "Retractor stuck. Take the next pole, this one is on strike."],
	["La perche ne remonte plus. Elle traîne, comme vous en fin de journée.", "The pole won't retract. It drags, like you at the end of the day."],
]
const PANNE_FREIN_PORTEUR_COMMUN: Array = [
	["Frein sur câble porteur serré. La cabine est accrochée comme une moule à son rocher.", "Track rope brake applied. The cabin clings like a mussel to its rock."],
	["Le frein de chariot a mordu le porteur. Il ne lâchera pas. C'est sa seule qualité.", "The carriage brake bit the track rope. It won't let go. Its only virtue."],
	["Frein de secours déclenché. On ne tombera pas. On ne montera pas non plus.", "Emergency brake tripped. We won't fall. We won't go up either."],
]
const PANNE_F_TENSION_COMMUN: Array = [
	["Pic de tension du câble. Il s'est tendu, comme tout le monde à bord.", "Rope tension spike. It tensed up, like everyone on board."],
	["Le câble a eu un sursaut. Rien de grave : lui aussi a ses nerfs.", "The rope flinched. Nothing serious: it has nerves too."],
]
const PANNE_F_PORTE_COMMUN: Array = [
	["Capteur de porte : une porte se croit ouverte. Elle est fermée. Elle insiste.", "Door sensor: a door thinks it's open. It's shut. It insists."],
	["Une porte en défaut. Trois cents personnes regardent la même porte.", "One door at fault. Three hundred people staring at the same door."],
]
const PANNE_F_THERMIQUE_COMMUN: Array = [
	["Surchauffe moteur. Sous terre, à 3 000 m, il a trouvé le moyen d'avoir chaud.", "Motor overheating. Underground at 3,000 m, and it managed to get hot."],
	["Le moteur demande une pause. On monte aux deux tiers, il souffle.", "The motor wants a break. Two-thirds speed while it catches its breath."],
]
const PANNE_F_RAIL_MOUILLE_COMMUN: Array = [
	["Rail mouillé : on roule à mi-vitesse. Le tunnel suinte, la rame se méfie.", "Wet rail: half speed. The tunnel drips, the train is wary."],
	["De l'eau sur le rail. Un funiculaire qui patine, ça ferait désordre.", "Water on the rail. A skidding funicular would look untidy."],
]
const PANNE_F_MOTEUR_COMMUN: Array = [
	["Un groupe moteur est hors service. Il en reste. On compte dessus.", "One drive unit is out. There are others. We're counting on them."],
	["Moteur en moins : on monte, mais sans se vanter.", "One motor down: we're climbing, just not bragging."],
]
const PANNE_F_ALIM_COMMUN: Array = [
	["Perte des auxiliaires. La lumière baisse, les voix aussi.", "Auxiliaries lost. The lights dim, and so do the voices."],
	["Plus d'auxiliaires : arrêt en tunnel. C'est le moment de se découvrir un voisin.", "No auxiliaries: stopped in the tunnel. Time to meet your neighbour."],
]
const PANNE_F_FREIN_PARKING_COMMUN: Array = [
	["Frein de parking collé. La rame veut bien partir ; le frein, non.", "Parking brake stuck. The train is willing; the brake isn't."],
	["On ne part pas : le frein de parking s'accroche à la gare. Il s'y plaît.", "Not leaving: the parking brake is clinging to the station. It likes it here."],
]
const PANNE_F_RUPTURE_COMMUN: Array = [
	["Rupture du câble tracteur. Les freins sur rail ont serré. C'est pour ça qu'on les a mis.", "Haul rope failure. The rail brakes clamped. That's what they're for."],
	["Le câble a lâché, les freins non. Respirez. Puis attendez longtemps.", "The rope let go; the brakes didn't. Breathe. Then wait a long time."],
]
const PANNE_F_FREIN_SERVICE_COMMUN: Array = [
	["Frein de service défaillant. Il en reste deux autres. La redondance, ça rassure après coup.", "Service brake failed. Two more remain. Redundancy is comforting in hindsight."],
	["Le frein de service a rendu son tablier. Arrêt d'urgence, par principe.", "The service brake resigned. Emergency stop, on principle."],
]
const PANNE_F_INONDATION_COMMUN: Array = [
	["De l'eau dans le tunnel. On avance au pas, comme dans une cave inondée, mais en pente.", "Water in the tunnel. Crawling, like a flooded cellar, only steeper."],
	["Infiltration : le glacier nous rend visite par le plafond.", "Seepage: the glacier is dropping in through the ceiling."],
]
const PANNE_F_COMMS_COMMUN: Array = [
	["Plus de communications. Le conducteur parle tout seul ; ça ne change pas grand-chose.", "Communications lost. The driver is talking to himself. Not much has changed."],
	["Liaison perdue avec la gare. On se fait signe par la pensée.", "Link to the station lost. We're signalling by thought."],
]
const PANNE_F_AIGUILLAGE_COMMUN: Array = [
	["Aiguillage de l'évitement en défaut. Deux rames, une voie : on réfléchit avant.", "Passing loop switch fault. Two trains, one track: think first."],
	["L'aiguillage hésite. À cet endroit précis, on préfère qu'il soit sûr de lui.", "The switch is hesitating. At that exact spot, we'd rather it were sure."],
]
const PANNE_F_INCENDIE_COMMUN: Array = [
	["Détection de fumée. Ce n'est pas la raclette. Évacuation.", "Smoke detected. It isn't the raclette. Evacuate."],
	["Fumée en tunnel : on arrête tout et on sort à pied. Le sarcasme reprendra dehors.", "Smoke in the tunnel: stop everything, walk out. Sarcasm resumes outside."],
]
const REPRISE_COMMUN: Array = [
	["Ça repart tout seul. L'automate a plus de sang-froid que vous.", "It restarted by itself. The controller is calmer than you are."],
	["Redémarrage automatique. Ne remerciez personne, c'est un logiciel.", "Automatic restart. Thank nobody, it's software."],
	["Et ça remonte. Comme si de rien n'était. La montagne oublie vite.", "And up we go. As if nothing happened. Mountains forget quickly."],
	["Reprise. Le silence gêné à bord peut cesser.", "Moving again. The awkward silence on board may end."],
	["La ligne redémarre. Vos doigts de pied, plus tard.", "The line restarts. Your toes, later."],
	["C'est reparti. Jusqu'à la prochaine fois, c'est-à-dire bientôt.", "Off we go. Until next time, which is soon."],
]
const SECOURS_COMMUN: Array = [
	["Moteur thermique de secours : 30 % de la vitesse, 100 % de l'odeur de gasoil.", "Back-up diesel: 30 % of the speed, 100 % of the diesel smell."],
	["On finit au diesel. C'est lent, ça fume, mais ça ramène tout le monde.", "Finishing on diesel. Slow, smoky, but it gets everyone home."],
	["Secours en marche. À cette allure, vous auriez le temps de lire le règlement.", "Back-up drive running. At this pace you could read the regulations."],
	["Le thermique ronronne. Enfin, il tousse. Mais il tourne.", "The diesel is purring. Well, coughing. But it's turning."],
	["Marche de secours : le paysage défile au ralenti, pour une fois qu'on a le temps.", "Rescue drive: the scenery in slow motion, now that we have the time."],
]
const REMISE_COMMUN: Array = [
	["Remise en service. La ligne revient d'entre les pannes.", "Back in service. The line returns from the land of faults."],
	["C'est réparé. Le technicien range ses clés et son air supérieur.", "It's fixed. The technician packs his spanners and his superior look."],
	["Ligne rouverte. Les premiers de la file font semblant de ne pas avoir attendu.", "Line reopened. The front of the queue pretends they never waited."],
	["Remise en service : essais à vide réussis. Maintenant on essaie avec vous.", "Back in service: empty runs passed. Now we try with you."],
	["De nouveau en service. On ne dit pas « comme neuve », on dit « comme avant ».", "In service again. Not 'good as new'. 'Same as before'."],
]
const DEPANNAGE_COMMUN: Array = [
	["Tout réparé d'un seul bouton. Si seulement c'était comme ça en vrai.", "Everything fixed with one button. If only real life worked like that."],
	["Dépannage express. Un mécanicien, quelque part, vient de perdre son emploi.", "Express repair. Somewhere a mechanic just lost his job."],
	["Réparé. Vous n'avez même pas sali vos gants.", "Repaired. You didn't even get your gloves dirty."],
	["Un clic, plus de panne. Le constructeur aimerait connaître votre secret.", "One click, no more fault. The manufacturer would love to know your secret."],
	["Tout est réarmé, remis, relancé. La baguette magique n'est pas fournie avec le forfait.", "All reset, restored, restarted. Magic wand not included in the pass."],
	["La ligne repart. Trois heures de procédure résumées en un doigt.", "The line restarts. Three hours of procedure summed up in one finger."],
]
const REFUS_COMMUN: Array = [
	["Départ refusé. La machine a lu la notice ; elle.", "Start refused. The machine has read the manual. Unlike some."],
	["Ça ne part pas. Il y a une raison, elle est affichée, elle est en rouge.", "It won't start. There's a reason, it's displayed, it's in red."],
	["Non. Pas tant que ce défaut est là. On ne force pas un automate de sécurité.", "No. Not with that fault up. You don't bully a safety controller."],
	["Refus de départ. Appuyer plus fort ne change rien, on a vérifié.", "Start refused. Pressing harder doesn't help; we checked."],
	["Le bouton vert reste sourd. Le rouge, lui, vous écoute toujours.", "The green button is deaf. The red one always listens."],
]
const REFUS_TPH: Array = [
	["On ne part pas portes ouvertes. Même en simulation, même pour rire.", "We don't leave with the doors open. Not even in a simulator. Not even for fun."],
	["Portes ouvertes, départ refusé. La cabine tient à ses passagers.", "Doors open, start refused. The cabin likes to keep its passengers."],
]
const INTERVENTION_COMMUN: Array = [
	["Les secouristes sont en route. À pied, dans la neige, avec cent mètres de corde. Soyez aimable.", "Rescuers are on their way. On foot, in snow, with 100 m of rope. Be nice."],
	["Intervention en cours. Restez assis : vous n'êtes pas le plus pressé de tomber.", "Intervention under way. Stay seated: you're in no hurry to fall."],
	["On vient vous chercher. Par en dessous. C'est original.", "They're coming for you. From underneath. How novel."],
	["Les pisteurs grimpent au pylône. Ils ont l'air de savoir. Espérons.", "Patrollers are climbing the tower. They look like they know. Let's hope."],
]
const EVACUATION_COMMUN: Array = [
	["Évacuation verticale. Le mot « verticale » est important.", "Vertical evacuation. The word 'vertical' matters."],
	["On descend tout le monde à la corde. Quinze minutes par siège. Vous êtes le quarante-deuxième.", "Everyone comes down by rope. Fifteen minutes per chair. You're number forty-two."],
	["Évacuation en cours. Souriez, quelqu'un filme forcément.", "Evacuation under way. Smile, someone is bound to be filming."],
	["Les passagers descendent un par un, comme des jambons.", "Passengers are being lowered one by one, like hams."],
	["Évacuation : trois heures et demie au plus, dit le règlement. Il fait moins douze, dit le thermomètre.", "Evacuation: three and a half hours at most, say the rules. Minus twelve, says the thermometer."],
]
const EVACUATION_TK: Array = [
	["Évacuation du téléski : lâchez la perche et skiez. C'est le plan. Il est simple.", "Drag lift evacuation: let go and ski down. That's the plan. It's simple."],
	["Tout le monde redescend à ski. Vous êtes venu pour ça, non ?", "Everybody skis down. That's what you came for, isn't it?"],
]
const HORS_SERVICE_COMMUN: Array = [
	["Ligne hors service. Le panneau lumineux l'annonce avec une joie mal dissimulée.", "Line out of service. The sign announces it with ill-concealed glee."],
	["Fermé. Il reste les autres remontées, la marche, et la philosophie.", "Closed. That leaves the other lifts, walking, and philosophy."],
	["Hors service jusqu'à nouvel ordre. L'ordre n'est pas pressé.", "Out of service until further notice. The notice is in no hurry."],
	["Tous les passagers sont au sol. La remontée, elle, est au tapis.", "All passengers on the ground. The lift is down for the count."],
]
const CORDE_COMMUN: Array = [
	["Descente à la corde. Asseyez-vous dans le triangle et ne regardez pas en bas. Trop tard.", "Rope descent. Sit in the triangle and don't look down. Too late."],
	["Vous voilà pendu à dix millimètres de polyamide. Ils tiennent deux tonnes. Vous, moins.", "There you hang from ten millimetres of nylon. It holds two tonnes. You weigh less."],
	["La corde file. Le secouriste gère. Vous, contentez-vous d'être un colis.", "The rope pays out. The rescuer has it. Your job is to be a parcel."],
	["Descente verticale. C'est la seule piste noire sans bosses.", "Vertical descent. The only black run with no moguls."],
	["Suspendu comme un jambon de Savoie. La dignité attendra en bas.", "Dangling like a cured ham. Dignity will be waiting at the bottom."],
	["On vous descend. Doucement. Si ça va vite, ce n'est pas la corde.", "You're being lowered. Slowly. If it's fast, that's not the rope."],
	["Vous avez demandé la corde. Dans la vraie vie, on appelle ça une très longue journée.", "You asked for the rope. In real life that's called a very long day."],
	["Le triangle d'évacuation : un fauteuil sans fond, sans dossier et sans vue rassurante.", "The rescue triangle: a seat with no bottom, no back and no reassuring view."],
]
const CORDE_SOL_COMMUN: Array = [
	["Au sol. Les jambes tremblent : c'est le froid. On dira que c'est le froid.", "On the ground. Legs shaking: it's the cold. We'll say it's the cold."],
	["Posé. Rendez le triangle, gardez le souvenir.", "Down. Return the triangle, keep the memory."],
	["Vous touchez la neige. Elle ne vous a jamais paru aussi sympathique.", "You touch the snow. It has never seemed so friendly."],
	["Arrivé en bas par le chemin le plus court. Et le plus étroit.", "Reached the bottom by the shortest route. And the narrowest."],
	["Sain et sauf. La remontée, elle, n'a toujours pas bougé.", "Safe and sound. The lift still hasn't moved."],
]
## Descente à la corde, sur les grandeurs du pendule (21/11/2026 : « des phrases sarcastiques pour la corde qui
## bouge ») : balancement, tournoiement, rebond au palier, vent, temps passé suspendu (PenduleCorde).
const CORDE_BALANCE_COMMUN: Array = [
	["Vous balancez. Un pendule de Foucault, en moins scientifique et en plus inquiet.", "You're swinging. A Foucault pendulum, less scientific and more worried."],
	["Période d'environ six secondes : la physique est ponctuelle. Votre estomac, moins.", "A period of about six seconds: physics is punctual. Your stomach, less so."],
	["Gauche, droite, gauche. Le secouriste compte les allers-retours, pas vous.", "Left, right, left. The rescuer counts the swings, you don't have to."],
	["Ne gigotez pas : chaque coup de jambe relance le pendule. Oui, celui-là aussi.", "Stop wriggling: every kick restarts the pendulum. Yes, that one too."],
]
const CORDE_TOURNE_COMMUN: Array = [
	["Vous tournez sur vous-même. La corde se dévrille, vous vous émerveillez.", "You're spinning. The rope unwinds; you get the panoramic tour."],
	["Visite panoramique à 360° offerte par la torsion de la corde. Sans supplément.", "A 360° panoramic tour, courtesy of rope twist. No extra charge."],
	["La corde vrillée vous ramène face à la pente. Puis de dos. Puis face. Choisissez.", "The twisted rope turns you back to the slope. Then away. Then back. Pick one."],
	["Toupie humaine homologuée EN 1891. Le vertige, lui, n'est pas certifié.", "Human spinning top, EN 1891 approved. The dizziness isn't certified."],
]
const CORDE_REBOND_COMMUN: Array = [
	["Le descendeur bloque, la corde s'étire, vous rebondissez. Trois pour cent d'allongement, cent pour cent de surprise.", "The descender locks, the rope stretches, you bounce. Three per cent stretch, a hundred per cent surprise."],
	["Petit rebond au palier : c'est la corde qui respire. Pas vous, visiblement.", "A little bounce at the stop: that's the rope breathing. Clearly not you."],
	["Arrêt net. La corde encaisse une fois et demie votre poids, en silence. Vous, moins.", "Sudden stop. The rope takes one and a half times your weight, silently. Unlike you."],
]
const CORDE_VENT_COMMUN: Array = [
	["Le vent vous pousse comme un drapeau. Un drapeau très mal fixé.", "The wind pushes you like a flag. A very badly fastened flag."],
	["Rafale : vous découvrez la traînée aérodynamique d'un corps assis. Elle est médiocre.", "Gust: you're discovering the drag of a seated body. It's mediocre."],
	["Avec ce vent, la verticale devient une opinion.", "In this wind, vertical becomes a matter of opinion."],
]
const CORDE_LONG_COMMUN: Array = [
	["Une minute suspendu. Vous connaissez désormais chaque fibre de cette corde.", "A minute hanging. You now know every fibre of this rope."],
	["Le temps passe lentement au bout d'une corde. Surtout pour celui qui est au bout.", "Time passes slowly at the end of a rope. Especially for whoever is on the end."],
	["Toujours là-haut. Le secouriste dit « on y est presque ». Il le dit à tout le monde.", "Still up there. The rescuer says 'nearly there'. He says it to everyone."],
]
const ATTENTE_COMMUN: Array = [
	["La cabine vous attend, portes ouvertes. Quarante personnes vous regardent arriver.", "The cabin is waiting, doors open. Forty people are watching you arrive."],
	["On vous attend. Ne courez pas en chaussures de ski, c'est ridicule. Si, courez.", "They're waiting. Don't run in ski boots, it looks silly. Actually, run."],
	["Le cabinier tient la porte. Il compte dans sa tête. Il en est à douze.", "The attendant is holding the door. Counting in his head. He's at twelve."],
	["Départ retardé pour vous. Dans la vraie vie, la porte se ferme sous votre nez.", "Departure held for you. In real life, the door shuts in your face."],
	["Prenez votre temps. Non, je plaisante : ils ont un horaire.", "Take your time. Just kidding: they have a timetable."],
	["Le véhicule patiente. Vous êtes officiellement « le client qu'on attend ».", "The vehicle is waiting. You are officially 'that passenger'."],
]
const EVENEMENTS_EXPLOITATION: Array = ["PANNE", "REPRISE", "SECOURS", "REMISE", "DEPANNAGE", "REFUS", "INTERVENTION", "EVACUATION", "HORS_SERVICE", "CORDE", "CORDE_SOL", "ATTENTE",
	"CORDE_BALANCE", "CORDE_TOURNE", "CORDE_REBOND", "CORDE_VENT", "CORDE_LONG"]
const EVENEMENTS: Array = ["ARRET", "FRAUDE", "CHAUSSE", "PIETON", "LOUPE", "SAUT", "DESCENTE", "ARRIVEE", "RESTE", "ARRIVEE_BAS"]


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
	var p: Array = pique_paire(evt, lg)
	if p.is_empty():
		return ""
	return String(p[1]) if lang == "en" else String(p[0])


## La pique tirée, dans les deux langues [français, anglais] ; [] sans pique pour cet évènement. Le pupitre du PC
## l'affiche dans sa propre langue, qui peut différer de celle de la vue 3D.
static func pique_paire(evt: String, lg: LigneRemontee) -> Array:
	_charger()
	var fam: String = famille(lg)
	var l: Array = _liste(evt, fam)
	if l.is_empty() and evt.begins_with("PANNE_"):
		evt = "PANNE"                    # panne sans liste à elle : piques communes aux pannes
		l = _liste(evt, fam)
	if l.is_empty():
		return []
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
	return [String(l[k][0]), String(l[k][1])]


## Seuils des piques de la descente à la corde (grandeurs de PenduleCorde) ; chacune une seule fois par descente,
## pas pendant les premières secondes (la pique CORDE vient d'être affichée), au moins ECART_CORDE_S entre deux.
const CORDE_ANGLE: float = 0.09           # rad (5°) d'inclinaison de la corde : ça balance
const CORDE_OMEGA: float = 0.30           # rad/s de tournoiement
const CORDE_SURTENSION: float = 1.30      # tension / poids : rebond au palier
const CORDE_VENT_MS: float = 7.0          # m/s de vent au point de l'évacué
const CORDE_LONG_S: float = 60.0
const CORDE_DEBUT_S: float = 3.0
const ECART_CORDE_S: float = 8.0


## o : {"t", "angle", "omega", "tension", "poids", "vent"} ; deja : {genre: true, "_t": instant de la dernière}
## (tenu par l'appelant, un par descente). Rend le genre d'événement (« CORDE_… ») ou "".
static func evenement_corde(o: Dictionary, deja: Dictionary) -> String:
	var t: float = float(o.get("t", 0.0))
	if t < CORDE_DEBUT_S or t - float(deja.get("_t", -1e9)) < ECART_CORDE_S:
		return ""
	var poids: float = maxf(float(o.get("poids", 785.0)), 1.0)
	var ev: String = ""
	if float(o.get("tension", 0.0)) > CORDE_SURTENSION * poids:
		ev = "CORDE_REBOND"
	elif absf(float(o.get("omega", 0.0))) > CORDE_OMEGA:
		ev = "CORDE_TOURNE"
	elif float(o.get("angle", 0.0)) > CORDE_ANGLE:
		ev = "CORDE_BALANCE"
	elif float(o.get("vent", 0.0)) > CORDE_VENT_MS:
		ev = "CORDE_VENT"
	elif t > CORDE_LONG_S:
		ev = "CORDE_LONG"
	if ev == "" or deja.has(ev):
		return ""
	deja[ev] = true
	deja["_t"] = t
	return ev
