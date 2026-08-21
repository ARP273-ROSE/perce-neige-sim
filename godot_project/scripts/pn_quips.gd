class_name PNQuips
extends Object
## Piques sarcastiques + avis passagers — port des listes du sim PC
## (perce_neige_sim.py : CRASH_QUIPS, DERAIL_QUIPS, CABIN_QUIPS,
## REVERSE_QUIPS, DOORS_OPEN_QUIPS, PAX_REVIEWS).
##
## Adaptations WEB (export Godot) :
##   - pas d'emoji drapeau : la police par défaut des exports mobiles les
##     rend en carrés → code pays entre crochets ("[JP] Yuki, Osaka") ;
##   - la version ORIGINALE (VO) n'est affichée que si elle s'écrit en
##     alphabet latin (champ `latin`) : japonais, coréen, chinois et
##     cyrillique ne sont pas dans la police embarquée. La traduction
##     FR/EN, elle, est toujours affichée.
##
## Format des quips  : [fr, en]
## Format des avis   : [qui, VO, latin(bool), fr, en]

const CRASH: Array = [
	["Freiner, c'était une option. Vous avez choisi « non ».",
	 "Braking was optional. You chose 'no'."],
	["Le butoir vous remercie de l'avoir testé. Personnellement.",
	 "The buffer stop thanks you for testing it. Personally."],
	["Les 334 passagers ont adoré le mur. Vraiment.",
	 "All 334 passengers loved the wall. Truly."],
	["Nouveau record de décélération. Et de réclamations.",
	 "New deceleration record. And complaint record."],
	["À ce stade, ce n'est plus une gare, c'est une cible.",
	 "At this point it's not a station, it's a target."],
	["La physique : 1. Vous : 0.",
	 "Physics: 1. You: 0."],
	["Von Roll a mis un frein. Vous, une intention.",
	 "Von Roll fitted a brake. You brought good intentions."],
	["Le repère d'arrêt était à 3 mètres. Vous visiez le Val d'Isère.",
	 "The stop mark was 3 m away. You aimed for the next valley."],
	["Score de précision : oui. Précision de score : zéro.",
	 "Precision score: yes. Score precision: zero."],
	["Techniquement, vous VOUS êtes arrêté. Le mur a aidé.",
	 "Technically you did stop. The wall helped."],
	["Le frein de service vous fait dire bonjour. Il s'ennuyait.",
	 "The service brake says hi. It was getting bored."],
	["2 111 mètres de montée pour finir dans un butoir. Beau parcours.",
	 "2111 m of climb to end in a buffer stop. Nice run."],
	["On appelle ça « l'arrêt Kaprun ». On ne devrait pas.",
	 "We call this 'the Kaprun stop'. We shouldn't."],
	["Les freins existent depuis 1834. Vous, depuis quand ?",
	 "Brakes have existed since 1834. And you?"],
	["Rapport d'incident : conducteur convaincu d'être en descente libre.",
	 "Incident report: driver convinced they were free-riding."],
	["Le glacier a 10 000 ans. Votre patience à l'approche : 2 secondes.",
	 "The glacier is 10,000 years old. Your approach patience: 2 seconds."],
	["Von Roll : coefficient de sécurité 8,5. Vous : coefficient 0.",
	 "Von Roll: safety factor 8.5. You: factor 0."],
]

const DERAIL: Array = [
	["Un aiguillage, ça se prend au pas. Pas au sprint.",
	 "A switch is taken at a crawl. Not a sprint."],
	["Le système Abt vous salue depuis le fond du ravin.",
	 "The Abt system waves at you from the bottom of the ravine."],
	["Deux rails, deux directions, zéro dans la bonne.",
	 "Two rails, two directions, zero of them the right one."],
	["L'évitement s'appelle « évitement ». Pas « défonçage ».",
	 "The passing loop is for passing. Not for plowing through."],
	["La physique des courbes : un cours que vous avez séché.",
	 "Curve physics: a class you clearly skipped."],
]

const CABIN: Array = [
	["L'autre rame avait, elle, pensé à freiner. Quelle idée.",
	 "The other car had, unlike you, thought about braking. What a concept."],
	["Deux rames, un câble, zéro survivant à l'ego du conducteur.",
	 "Two cars, one cable, zero survivors to the driver's ego."],
	["Vous avez inventé le premier funiculaire à collision frontale.",
	 "You invented the first head-on funicular."],
	["La rame 2 déposera plainte. Elle a des témoins : 334.",
	 "Car 2 will press charges. It has witnesses: 334 of them."],
]

const REVERSE: Array = [
	["Demi-tour. Les passagers adorent refaire le trajet à l'envers.",
	 "U-turn. Passengers just love doing the whole trip backwards."],
	["Vous avez oublié quelque chose là-haut ? Un peu de jugeote ?",
	 "Forgot something up there? Your common sense, maybe?"],
	["Le funiculaire n'est pas un manège. Mais continuez.",
	 "A funicular isn't a fairground ride. But do go on."],
	["Retour à la case départ. Les skieurs vous remercient chaleureusement.",
	 "Back to square one. The skiers thank you warmly."],
	["Inversion du sens : parce que le premier trajet était trop réussi ?",
	 "Reversing: because the first trip went too well?"],
]

const DOORS_OPEN: Array = [
	["Portes ouvertes à 40 km/h. L'aération, version extrême.",
	 "Doors open at 40 km/h. Air conditioning, extreme edition."],
	["Un passager vient de découvrir le vide. En temps réel.",
	 "A passenger just discovered the void. In real time."],
	["Le règlement dit « portes fermées ». Le règlement pleure.",
	 "The rulebook says 'doors closed'. The rulebook is weeping."],
	["Comptez vos passagers à l'arrivée. Il en manquera.",
	 "Count your passengers at the top. Some will be missing."],
	["Rouler portes ouvertes : une première, un record, un procès.",
	 "Driving with the doors open: a first, a record, a lawsuit."],
]

# --- Avis passagers : voyage nickel --------------------------------------
const REVIEWS_GREAT: Array = [
	["[JP] Yuki, Osaka", "", false,
	 "Sugoi ! Arrêt parfait, pile au repère. Le conducteur a l'âme d'un maître du thé. Je reviendrai. Merci infiniment.",
	 "Sugoi! Perfect stop, right on the mark. The driver has the soul of a tea master. I'll be back. Thank you so much."],
	["[DE] Klaus, Stuttgart",
	 "Korrekt. Verzögerung innerhalb der Toleranz, Halt auf den Millimeter. Ich habe es gestoppt: tadellos. Fünf Sterne.", true,
	 "Korrekt. Décélération dans les tolérances, arrêt au millimètre. J'ai chronométré : irréprochable. Cinq étoiles, et ça ne m'arrive jamais.",
	 "Korrekt. Deceleration within tolerance, stop to the millimetre. I timed it: flawless. Five stars, which never happens to me."],
	["[CH] Heidi, Zürich",
	 "Pünktlich UND am Haltepunkt. Voilà. Meh bruchts nöd. Fascht so guet wie dihei.", true,
	 "À l'heure ET au repère. Voilà. Il n'en faut pas plus. Presque aussi bien qu'à la maison.",
	 "On time AND on the mark. Voilà. Nothing more needed. Almost as good as back home."],
	["[IT] Nonna Rosa, Napoli",
	 "Bravissimo ! Liscio come una gondola. Ho pure finito il caffè senza versarne una goccia. Tieni, mangia un cannolo.", true,
	 "Bravissimo ! Doux comme une gondole. J'ai même fini mon café sans en renverser une goutte. Tiens, mange un cannolo.",
	 "Bravissimo! Smooth as a gondola. I even finished my coffee without spilling a drop. Here, have a cannolo."],
	["[GB] Nigel, London",
	 "Frightfully smooth. Not a drop of tea disturbed. One almost forgets one is underground. Splendid. Carry on.", true,
	 "Remarquablement doux. Pas une goutte de thé renversée. On en oublierait presque qu'on est sous terre. Splendide. Continuez.",
	 "Frightfully smooth. Not a drop of tea disturbed. One almost forgets one is underground. Splendid. Carry on."],
	["[SE] Astrid, Göteborg",
	 "Lagom. Precis rätt fart, mjuk inbromsning, ingen dramatik. Precis så en resa ska vara. Tack så mycket.", true,
	 "Lagom. La vitesse juste comme il faut, freinage doux, aucun drame. Exactement ce qu'un trajet doit être. Merci beaucoup.",
	 "Lagom. Exactly the right speed, gentle braking, no drama. Exactly how a ride should be. Thank you very much."],
	["[NL] Sanne, Utrecht",
	 "Netjes op de meter gestopt. Geen gedoe, gewoon goed geregeld. Hier kan de NS nog wat van leren.", true,
	 "Arrêté pile au mètre. Aucun tracas, du travail bien fait. Les chemins de fer néerlandais pourraient en prendre de la graine.",
	 "Stopped right on the metre. No fuss, just well done. Our own railways could learn a thing or two here."],
	["[KR] Min-jun, Séoul", "", false,
	 "Parfait ! Pas une goutte de café renversée. Le conducteur, un vrai pro. Cinq étoiles. Le meilleur !",
	 "Perfect! Not a drop of coffee spilled. The driver is a real pro. Five stars. The best!"],
	["[US] Karen, Ohio",
	 "Honestly? I came ready to complain and I have NOTHING. Smooth, on time, spotless. Five stars.", true,
	 "Franchement ? Je venais pour râler et je n'ai RIEN. Doux, à l'heure, impeccable. Aussi surprise que vous. Cinq étoiles.",
	 "Honestly? I came ready to complain and I have NOTHING. Smooth, on time, spotless. I'm as shocked as you are. Five stars."],
	["[FR] Josiane, Roubaix", "", false,
	 "Alors là, rien à dire. Doux, pile à l'arrêt, propre. Pour une fois que je monte quelque part sans avoir peur. Bravo le petit.",
	 "Well, nothing to say. Smooth, stopped right on the mark, clean. For once I go up somewhere without being scared. Well done, lad."],
	["[RU] Dmitri, Novossibirsk", "", false,
	 "Doux. Régulier. Comme il faut. Chez nous, on ne sait pas faire. Je vous embauche comme conducteur en Sibérie. Cinq étoiles.",
	 "Smooth. Steady. As it should be. Back home they can't do this. I'm hiring you as a driver in Siberia. Five stars."],
]

# --- Avis passagers : arrivée brusque ------------------------------------
const REVIEWS_ROUGH: Array = [
	["[JP] Yuki, Osaka", "", false,
	 "Euh… un peu rapide, peut-être. Excusez-moi. Je ne veux pas déranger, mais mon thé s'est un peu renversé. C'est très bien quand même.",
	 "Um… a little fast, maybe. Excuse me. I don't want to be a bother, but my tea spilled a bit. It's fine, really."],
	["[GB] Nigel, London",
	 "Well. That was… spirited. Not complaining, obviously. It's merely that my hat has relocated three rows back. Regards.", true,
	 "Eh bien. C'était… vigoureux. Je ne me plains pas, évidemment. Simplement, mon chapeau a déménagé trois rangs plus loin. Cordialement.",
	 "Well. That was… spirited. Not complaining, obviously. It's merely that my hat has relocated three rows back. Regards."],
	["[DE] Klaus, Stuttgart",
	 "Die Verzögerung überschritt 2,5 m/s². Ich habe es gestoppt. Drei Sterne, und ich lege ein Diagramm bei.", true,
	 "La décélération a dépassé 2,5 m/s². J'ai chronométré. Je mets trois étoiles et je joins un graphique.",
	 "Deceleration exceeded 2.5 m/s². I timed it. Three stars, and I'm attaching a chart."],
	["[BR] Ana, Rio",
	 "Eita! Um sambinha involuntário na chegada. Minha caipirinha imaginária sofreu. Mas o clima, top demais.", true,
	 "Eita ! Un petit samba involontaire à l'arrivée. Ma caipirinha imaginaire a souffert. Mais l'ambiance, au top.",
	 "Eita! A little involuntary samba on arrival. My imaginary caipirinha suffered. But the vibe, top-notch."],
	["[CN] Wei, Shanghai", "", false,
	 "Freinage un peu brusque. Mon thé au lait a débordé un peu. Belle vue, mais chef, plus de douceur la prochaine fois. Trois étoiles.",
	 "Braking a touch abrupt. My bubble tea spilled a little. Nice view, but master, go gentler next time. Three stars."],
	["[DE] Helga, Bremen",
	 "Also. Der Kaffee war heiß. Jetzt ist er auf meiner Hose. Die Aussicht war schön, der Halt weniger. Na ja.", true,
	 "Bon. Le café était chaud. Il est maintenant sur mon pantalon. La vue était belle, l'arrêt moins. Enfin bref.",
	 "Well. The coffee was hot. It's now on my trousers. The view was lovely, the stop less so. Oh well."],
	["[US] Chad, Florida",
	 "Okay that stop had some SEND to it, not gonna lie. My buddy spilled his slushie. Still kinda fun tho. Three stars.", true,
	 "Ok, cet arrêt avait du PUNCH, faut l'avouer. Mon pote a renversé sa granita. C'était marrant quand même. Trois étoiles.",
	 "Okay that stop had some SEND to it, not gonna lie. My buddy spilled his slushie. Still kinda fun tho. Three stars."],
	["[IN] Priya, Mumbai",
	 "Arre! Thoda zyada jhatka tha, boss. Chai gir gayi. Par view first-class hai. Agli baar smooth chalao na. Teen star.", true,
	 "Arre ! Un peu trop de secousse, chef. Mon chai a coulé. Mais la vue est première classe. La prochaine fois, tout en douceur. Trois étoiles.",
	 "Arre! A bit too much of a jolt, boss. My chai spilled. But the view is first-class. Drive smooth next time. Three stars."],
	["[FR] Jean-Michel, Lyon", "", false,
	 "Bon, ça secoue un peu, hein. J'ai mordu dans mon sandwich au mauvais moment. Rien de grave, mais bon. Trois étoiles.",
	 "Well, it shakes a bit. I bit my sandwich at the wrong moment. Nothing serious, but still. Three stars."],
	["[PT] Tiago, Porto",
	 "Epá, travagem à bruta! O meu pastel de nata quase saltou. Paisagem linda, mas calma nas travagens, se faz favor.", true,
	 "Eh là, freinage à la dure ! Mon pastel de nata a failli sauter. Paysage magnifique, mais du calme au freinage, s'il vous plaît.",
	 "Whoa, brutal braking! My custard tart nearly jumped. Beautiful scenery, but easy on the brakes, please."],
]

# --- Avis passagers : catastrophe ----------------------------------------
const REVIEWS_DISASTER: Array = [
	["[JP] Yuki, Osaka", "", false,
	 "…Excusez-moi. Je crois que nous avons heurté quelque chose. Ce n'est pas grave. Enfin, si, un peu. Mon thé n'existe plus. Gomennasai.",
	 "…Excuse me. I believe we hit something. It's fine. Well, sort of. My tea no longer exists. Gomennasai."],
	["[DE] Klaus, Stuttgart",
	 "INAKZEPTABEL. Aufprallverzögerung nicht messbar — meine Stoppuhr ist zerbrochen. Ich verlange einen Bericht. Und eine neue Stoppuhr.", true,
	 "INAKZEPTABEL. Décélération d'impact non mesurable : mon chronomètre s'est brisé. J'exige un rapport. Et un nouveau chronomètre.",
	 "INAKZEPTABEL. Impact deceleration unmeasurable — my stopwatch shattered. I demand a report. And a new stopwatch."],
	["[US] Chad, Florida",
	 "BRO. That was like a roller coaster WITHOUT the rails?? 5 stars for the adrenaline, 1 for my pulverized Ray-Bans.", true,
	 "BRO. C'était genre une montagne russe SANS les rails ?? 5 étoiles pour l'adrénaline, 1 pour mes Ray-Ban pulvérisées.",
	 "BRO. That was like a roller coaster WITHOUT the rails?? 5 stars for the adrenaline, 1 for my pulverized Ray-Bans."],
	["[IT] Giulia, Napoli",
	 "MAMMA MIA! Ho urlato più forte che al Maradona! Il caffè, il vestito buono, TUTTO per terra! Vergogna!", true,
	 "MAMMA MIA ! J'ai crié plus fort qu'au stade Maradona ! Le café, le beau costume, TOUT par terre ! Vergogna !",
	 "MAMMA MIA! I screamed louder than at the Maradona stadium! The coffee, the good suit, EVERYTHING on the floor! Vergogna!"],
	["[FR] Jean-Michel, Lyon", "", false,
	 "Non mais c'est un scandale, hein. 40 euros pour finir dans le mur. J'écris au maire. Et à ma belle-mère, tant qu'à faire.",
	 "This is an absolute disgrace. 40 euros to end up in the wall. I'm writing to the mayor. And my mother-in-law, while I'm at it."],
	["[AU] Bruce, Sydney",
	 "Crikey! We were a satellite for two seconds there! Bloody memorable. But where the heck did my cap go, mate?", true,
	 "Crikey ! On est devenus un satellite pendant deux secondes ! Sacrément mémorable. Mais où est passée ma casquette, l'ami ?",
	 "Crikey! We were a satellite for two seconds there! Bloody memorable. But where the heck did my cap go, mate?"],
	["[CN] Wei, Shanghai", "", false,
	 "J'ai tout filmé. Déjà dans les tendances, 2 millions de vues. Le conducteur est célèbre. Pour de très mauvaises raisons.",
	 "I filmed everything. Already trending, 2 million views. The driver is famous now. For very bad reasons."],
	["[CH] Heidi, Zürich",
	 "In der Schweiz würde das nie passieren. Ich sag's ja nur. Ein Stern, und das ist grosszügig.", true,
	 "En Suisse, cela n'arriverait jamais. Je dis ça, je dis rien. Une étoile, et c'est généreux.",
	 "In Switzerland this would never happen. Just saying. One star, and that's generous."],
	["[ES] Rocío, Sevilla",
	 "¡Madre mía! ¡Ni en la Feria hay tanto meneo! Mi abanico por los aires y mi dignidad también. Olé tú.", true,
	 "¡Madre mía ! Même à la Feria on ne secoue pas autant ! Mon éventail en l'air, et ma dignité avec. Olé.",
	 "¡Madre mía! Not even at the Feria do we shake this much! My fan went flying, and so did my dignity. Olé."],
]


# --- Accès ----------------------------------------------------------------

## Tire une pique au hasard dans une des listes ci-dessus (langue = "fr"/"en").
static func pick_quip(list: Array, lang: String) -> String:
	if list.is_empty():
		return ""
	var q: Array = list.pick_random()
	return q[1] if lang == "en" else q[0]


## Tire un avis passager. `tier` ∈ {"great", "rough", "disaster"}.
## Retourne { "who": …, "native": …, "text": … } — `native` vide quand la
## VO n'est pas affichable avec la police embarquée.
static func pick_review(tier: String, lang: String) -> Dictionary:
	var pool: Array = REVIEWS_GREAT
	if tier == "rough":
		pool = REVIEWS_ROUGH
	elif tier == "disaster":
		pool = REVIEWS_DISASTER
	var r: Array = pool.pick_random()
	return {
		"who": r[0],
		"native": str(r[1]) if bool(r[2]) else "",
		"text": r[4] if lang == "en" else r[3],
	}


## Étoiles en ASCII : la police par défaut des exports mobiles ne contient
## pas U+2605 (retour d'essai iPad : glyphes en carrés).
static func stars_ascii(score: float) -> String:
	var n: int = 2
	if score >= 90.0:
		n = 5
	elif score >= 80.0:
		n = 4
	elif score >= 60.0:
		n = 3
	return "[" + "*".repeat(n) + ".".repeat(5 - n) + "]"
