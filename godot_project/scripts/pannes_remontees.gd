class_name PannesRemontees
extends RefCounted
## Catalogue des pannes des remontées autres que le Perce-Neige (demande d'utilisateur du 15/11/2026 : « pour toutes
## les remontées, avec mode auto de base » ; « les mêmes pannes, les mêmes boutons, les mêmes effets pour le Funival
## que le Perce-Neige »). Même échelle de gravité que les FAULT_PROFILES du sim PC :
##   avis     : voyant seul, aucune restriction ;
##   degrade  : vitesse plafonnée (cap = fraction de la vitesse nominale) ;
##   arret    : arrêt (normal ou d'urgence), reprise après traitement (duree s) ;
##   grave    : arrêt d'urgence, intervention, évacuation, ligne hors service jusqu'à la remise en service.
## Groupes : tsd, tsf, tcd, tk, tkd, tph, 3s, funival (ExploitationRemontee.groupe_de). Pannes du Funival reprises
## de celles du Perce-Neige (même constructeur de principe : funiculaire à deux véhicules, tunnel, évitement), aux
## vitesses du Funival (12 m/s nominal).
##
## Champs : g (groupes), grav, cap (1 = sans plafond), stop ("" | "normal" | "urgence"), duree (s, 0 = jamais seule),
## voyant, poids (tirage au hasard ; 0 = jamais au hasard), bloque (départ interdit tant qu'elle dure),
## quoi / faire / interdit : [fr, en].

const CABLES: Array = ["tsd", "tsf", "tcd", "tk", "tkd", "tph", "3s"]
const AERIENS: Array = ["tsd", "tsf", "tcd", "tph", "3s"]
const DEBRAYABLES: Array = ["tsd", "tcd", "tkd", "3s"]
const VA_ET_VIENT: Array = ["tph", "funival"]

const GRAVITES: Array = ["avis", "degrade", "arret", "grave"]
const LIBELLES_GRAVITE: Dictionary = {
	"avis": ["AVIS", "ADVISORY"], "degrade": ["MODE DÉGRADÉ", "DEGRADED"],
	"arret": ["ARRÊT", "STOP"], "grave": ["GRAVE — ÉVACUATION", "CRITICAL — EVACUATION"]}

const P: Dictionary = {
	# --- toutes les remontées à câble ---------------------------------------------------------------------------
	"vent_fort": {"g": ["tsd", "tsf", "tcd", "tph", "3s", "tk", "tkd"], "grav": "degrade", "cap": 0.5, "stop": "", "duree": 90.0, "voyant": "vent",
		"poids": 3.0, "nom": ["Vent fort", "Strong wind"],
		"quoi": ["Anémomètre de ligne au-dessus du seuil de ralentissement : rafales qui font balancer les véhicules.",
			"Line anemometer above the slow-down threshold: gusts are swinging the carriers."],
		"faire": ["Réduire à petite vitesse ; surveiller l'anémomètre, arrêter si le seuil d'arrêt est atteint.",
			"Drop to low speed; watch the anemometer, stop if the stop threshold is reached."],
		"interdit": ["Vitesse supérieure à la moitié du nominal.", "Speed above half the rated speed."]},
	"tempete": {"g": AERIENS, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 150.0, "voyant": "vent",
		"poids": 1.0, "nom": ["Seuil d'arrêt du vent", "Wind stop threshold"],
		"quoi": ["Rafales au-delà du seuil d'arrêt : la ligne est arrêtée, véhicules en ligne.",
			"Gusts beyond the stop threshold: the line is stopped with carriers on the rope."],
		"faire": ["Attendre l'accalmie, puis redémarrer à petite vitesse pour vider la ligne.",
			"Wait for the lull, then restart at low speed to empty the line."],
		"interdit": ["Redémarrage tant que le vent dépasse le seuil.", "Restart while the wind exceeds the threshold."]},
	"coupure_reseau": {"g": CABLES, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 180.0, "voyant": "moteur",
		"poids": 1.5, "secours": true, "nom": ["Coupure du réseau", "Mains power loss"],
		"quoi": ["Plus de courant EDF : le frein de service a arrêté la ligne. Le moteur thermique de secours est prêt.",
			"Mains power lost: the service brake stopped the line. The diesel back-up drive is ready."],
		"faire": ["Basculer sur le moteur de secours (SECOURS), puis DÉMARRER : la ligne se vide à 30 % de la vitesse.",
			"Switch to the back-up drive (BACK-UP), then START: the line empties at 30 % speed."],
		"interdit": ["Vitesse au-delà de 30 % sur le secours.", "Speed above 30 % on the back-up drive."]},
	"variateur": {"g": CABLES, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 45.0, "voyant": "moteur",
		"poids": 1.5, "nom": ["Défaut du variateur", "Drive fault"],
		"quoi": ["Le variateur du moteur principal s'est mis en défaut : arrêt sur le frein de service.",
			"The main motor drive tripped: stop on the service brake."],
		"faire": ["Attendre le diagnostic du mécanicien, RÉARMER puis DÉMARRER.", "Wait for the mechanic's check, RESET then START."],
		"interdit": ["Démarrage avant le réarmement.", "Start before the reset."]},
	"surchauffe": {"g": CABLES, "grav": "degrade", "cap": 0.7, "stop": "", "duree": 120.0, "voyant": "moteur",
		"poids": 1.5, "nom": ["Surchauffe du réducteur", "Gearbox overheating"],
		"quoi": ["Huile du réducteur à 95 °C : la protection plafonne la vitesse à 70 %.",
			"Gearbox oil at 95 °C: protection caps speed at 70 %."],
		"faire": ["Continuer en mode dégradé, le réducteur refroidit.", "Carry on in degraded mode while the gearbox cools."],
		"interdit": ["Vitesse au-delà de 70 %.", "Speed above 70 %."]},
	"frein_service": {"g": CABLES, "grav": "arret", "cap": 0.0, "stop": "urgence", "duree": 60.0, "voyant": "frein",
		"poids": 0.8, "nom": ["Défaut du frein de service", "Service brake fault"],
		"quoi": ["Usure ou pression du frein de service hors tolérance : le frein de poulie (urgence) a pris le relais.",
			"Service brake wear or pressure out of tolerance: the bull-wheel (emergency) brake took over."],
		"faire": ["Contrôle du frein par le mécanicien, RÉARMER, puis DÉMARRER.", "Brake checked by the mechanic, RESET, then START."],
		"interdit": ["Démarrage avant le contrôle.", "Start before the check."]},
	"secu_ligne": {"g": ["tsd", "tsf", "tcd", "tk", "tkd", "3s"], "grav": "arret", "cap": 0.0, "stop": "urgence",
		"duree": 75.0, "voyant": "secu_ligne", "poids": 1.5, "nom": ["Boucle de sécurité de ligne", "Line safety circuit"],
		"quoi": ["Un détecteur de position du câble s'est ouvert sur un pylône : arrêt d'urgence.",
			"A rope-position detector opened on a tower: emergency stop."],
		"faire": ["Inspection du pylône par un agent, câble en place : RÉARMER puis DÉMARRER à petite vitesse.",
			"An attendant inspects the tower, rope in place: RESET then START at low speed."],
		"interdit": ["Réarmement avant l'inspection.", "Reset before the inspection."]},
	"givre": {"g": AERIENS, "grav": "avis", "cap": 0.8, "stop": "", "duree": 120.0, "voyant": "cable",
		"poids": 1.0, "nom": ["Givre sur le câble", "Rime on the rope"],
		"quoi": ["Givre sur le câble et les galets : patinage, vibrations aux balanciers.",
			"Rime on the rope and sheaves: slipping and vibration at the sheave trains."],
		"faire": ["Rouler à 80 % : le passage des pinces dégivre le câble.", "Run at 80 %: the grips scrape the rime off."],
		"interdit": ["Aucune restriction au-delà de 80 %.", "No restriction beyond 80 %."]},
	"tension": {"g": CABLES, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 60.0, "voyant": "cable",
		"poids": 0.8, "nom": ["Course du contrepoids", "Tension carriage travel"],
		"quoi": ["Le chariot de tension arrive en fin de course : la tension du câble n'est plus garantie.",
			"The tension carriage reached its end stop: rope tension is no longer guaranteed."],
		"faire": ["Recaler le vérin de tension, RÉARMER puis DÉMARRER.", "Reset the tension ram, RESET then START."],
		"interdit": ["Démarrage avant le recalage.", "Start before the reset."]},
	# Déraillement (question d'utilisateur du 15/11/2026 : « si TS, TC, TPH ou 3S déraille, il faut descendre à la
	# corde ») : un câble hors de ses galets interdit toute marche de récupération ou de secours (conditions du plan
	# d'évacuation : ligne sans déraillement, câble et pinces intacts) ; reste l'évacuation verticale. Binôme de
	# secouristes : l'un monte au pylône, se longe au câble sur un chariot à galets et rejoint les véhicules, l'autre
	# assure du sol ; chaque passager est équipé d'un triangle d'évacuation et descendu à la corde, environ 15 min par
	# siège de deux en comptant l'accès ; décision dans les 30 min, tout le monde au sol en 3 h 30 au plus.
	# (remontees-mecaniques.net, dossier « L'évacuation » ; fiche secouriste « évacuation télésiège » ; Petzl, procédure
	# du téléphérique du Pic du Midi.) Les durées du jeu sont comprimées (ExploitationRemontee.T_*).
	"sortie_cable": {"g": ["tsd", "tsf", "tcd", "3s"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0,
		"voyant": "cable", "poids": 0.0, "evac": "corde", "nom": ["Déraillement du câble", "Rope derailment"],
		"quoi": ["Le câble a quitté les galets d'un pylône et repose sur le ramasse-câble : aucune marche de récupération possible.",
			"The rope left a tower's sheaves and rests on the catcher: no recovery run is possible."],
		"faire": ["1) Ne pas redémarrer  2) Annonce aux passagers : rester assis, barre baissée  3) Évacuation verticale : secouristes au pylône, chariot sur le câble, triangle d'évacuation, descente à la corde  4) Remise en service après réparation.",
			"1) Do not restart  2) Announce: stay seated, bar down  3) Vertical evacuation: rescuers up the tower, trolley on the rope, evacuation triangle, lowered on a rope  4) Back in service after repair."],
		"interdit": ["Toute remise en marche, même de récupération.", "Any restart, even a recovery run."]},
	"deraillement_tph": {"g": ["tph"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "cable",
		"poids": 0.0, "evac": "corde", "nom": ["Déraillement du chariot", "Carriage derailment"],
		"quoi": ["Des galets du chariot ont quitté le câble porteur : cabine immobilisée en ligne, pas de rapatriement possible.",
			"Carriage wheels left the track rope: cabin stuck on the line, it cannot be brought back."],
		"faire": ["1) Ne pas redémarrer  2) Annonce aux passagers  3) Évacuation verticale : secouristes sur la cabine, passagers équipés un par un et descendus à la corde (hélicoptère en appoint de jour)  4) Remise en service après expertise.",
			"1) Do not restart  2) Passenger announcement  3) Vertical evacuation: rescuers on the cabin, passengers harnessed one by one and lowered on a rope (helicopter as a back-up by day)  4) Back in service after inspection."],
		"interdit": ["Tout mouvement de la cabine.", "Any cabin movement."]},
	"sortie_cable_tk": {"g": ["tk", "tkd"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "cable",
		"poids": 0.0, "evac": "ski", "nom": ["Déraillement du câble", "Rope derailment"],
		"quoi": ["Le câble a quitté les galets d'un pylône : ligne bloquée.", "The rope left a tower's sheaves: line blocked."],
		"faire": ["1) Ne pas redémarrer  2) Les skieurs lâchent la perche et redescendent à ski hors de la trace  3) Remise en service après réparation.",
			"1) Do not restart  2) Skiers let go of the bar and ski down away from the track  3) Back in service after repair."],
		"interdit": ["Tout redémarrage.", "Any restart."]},
	# --- débrayables ----------------------------------------------------------------------------------------------
	"pince": {"g": DEBRAYABLES, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 45.0, "voyant": "pince",
		"poids": 2.0, "nom": ["Contrôle de pince", "Grip test"],
		"quoi": ["Le contrôle de serrage au départ a refusé une pince : arrêt avant l'embrayage.",
			"The grip-force test at departure rejected a grip: stop before it clamps the rope."],
		"faire": ["Garer le véhicule en voie de garage, RÉARMER puis DÉMARRER.", "Park the carrier on the storage rail, RESET then START."],
		"interdit": ["Départ du véhicule refusé.", "Dispatching the rejected carrier."]},
	"espacement": {"g": DEBRAYABLES, "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 30.0, "voyant": "pince",
		"poids": 1.5, "nom": ["Défaut d'espacement", "Spacing fault"],
		"quoi": ["Deux véhicules trop proches à la sortie du lanceur : la gare a arrêté la ligne.",
			"Two carriers too close leaving the launcher: the station stopped the line."],
		"faire": ["Laisser le lanceur recaler l'espacement, puis DÉMARRER.", "Let the launcher restore the spacing, then START."],
		"interdit": ["Démarrage avant le recalage.", "Start before the reset."]},
	"portes": {"g": ["tcd", "3s", "tph"], "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 30.0, "voyant": "portes",
		"poids": 2.0, "bloque": true, "nom": ["Porte non verrouillée", "Door not locked"],
		"quoi": ["Une porte de cabine n'est pas verrouillée à la sortie de gare : arrêt.",
			"A cabin door is not locked leaving the station: stop."],
		"faire": ["Faire refermer la porte par l'agent, puis DÉMARRER.", "Have the attendant close the door, then START."],
		"interdit": ["Départ tant que la porte est ouverte.", "Departure while the door is open."]},
	# --- télésièges et téléskis ------------------------------------------------------------------------------------
	"chute": {"g": ["tsd", "tsf", "tk", "tkd"], "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 25.0,
		"voyant": "secu_ligne", "poids": 3.0, "nom": ["Chute à l'embarquement", "Fall at boarding"],
		"quoi": ["Un skieur est tombé à l'embarquement : l'agent a arrêté la ligne.",
			"A skier fell at boarding: the attendant stopped the line."],
		"faire": ["Aider le skieur à dégager la zone, puis DÉMARRER.", "Help the skier clear the area, then START."],
		"interdit": ["Démarrage tant que la zone n'est pas libre.", "Start while the area is not clear."]},
	"depassement": {"g": ["tsd", "tsf", "tk", "tkd"], "grav": "arret", "cap": 0.0, "stop": "urgence", "duree": 30.0,
		"voyant": "secu_ligne", "poids": 1.5, "nom": ["Sécurité de dépassement", "Overrun safety"],
		"quoi": ["Un skieur n'a pas débarqué et a coupé la sécurité de dépassement à l'arrivée : arrêt d'urgence.",
			"A skier did not unload and tripped the overrun safety at the top: emergency stop."],
		"faire": ["Faire descendre le skieur, RÉARMER puis DÉMARRER.", "Get the skier off, RESET then START."],
		"interdit": ["Réarmement avant que la zone soit libre.", "Reset before the area is clear."]},
	"enrouleur": {"g": ["tk"], "grav": "avis", "cap": 1.0, "stop": "", "duree": 60.0, "voyant": "pince",
		"poids": 1.5, "nom": ["Enrouleur bloqué", "Stuck recoil box"],
		"quoi": ["Une perche ne s'enroule plus : elle traîne au sol.", "A bar no longer recoils: it drags on the snow."],
		"faire": ["Continuer ; l'agent la retire au passage en gare.", "Carry on; the attendant removes it at the station."],
		"interdit": ["Aucune restriction.", "No restriction."]},
	# --- va-et-vient aériens ----------------------------------------------------------------------------------------
	"frein_porteur": {"g": ["tph", "3s"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "frein",
		"poids": 0.0, "nom": ["Frein sur câble porteur", "Track-rope brake"],
		"quoi": ["Le frein de chariot s'est serré sur le câble porteur : cabine immobilisée en ligne.",
			"The carriage brake clamped the track rope: cabin stuck on the line."],
		"evac": "corde",
		"faire": ["1) Ne pas redémarrer  2) Annonce aux passagers  3) Évacuation verticale à la corde (ou nacelle de secours si l'installation en a une)  4) Remise en service après contrôle.",
			"1) Do not restart  2) Passenger announcement  3) Vertical evacuation on a rope (or rescue nacelle where fitted)  4) Back in service after inspection."],
		"interdit": ["Tout redémarrage.", "Any restart."]},
	# --- Funival (repris du Perce-Neige) -------------------------------------------------------------------------
	"f_tension": {"g": ["funival"], "grav": "avis", "cap": 1.0, "stop": "", "duree": 25.0, "voyant": "cable", "poids": 2.0,
		"nom": ["Pic de tension du câble", "Rope tension surge"],
		"quoi": ["Pic de tension transitoire sur le câble tracteur : le régulateur l'amortit déjà.",
			"Transient haul-rope tension surge: the regulator is already damping it."],
		"faire": ["Réduire un peu la consigne jusqu'à ce que le voyant Câble s'éteigne.", "Ease the setpoint until the Rope light goes out."],
		"interdit": ["Aucune restriction.", "No restriction."]},
	"f_porte": {"g": ["funival"], "grav": "arret", "cap": 1.0, "stop": "", "duree": 0.0, "voyant": "portes", "poids": 2.0,
		"bloque": true, "cycle_portes": true, "nom": ["Capteur de porte", "Door sensor"],
		"quoi": ["Capteur de porte défectueux : la sécurité interdit le départ tant que les portes n'ont pas été cyclées.",
			"Faulty door sensor: the safety chain blocks departure until the doors are cycled."],
		"faire": ["À quai, ouvrir puis refermer les portes (PORTES), puis DÉMARRER.", "At the platform, open then close the doors (DOORS), then START."],
		"interdit": ["Départ tant que les portes ne sont pas cyclées.", "Departure until the doors are cycled."]},
	"f_thermique": {"g": ["funival"], "grav": "degrade", "cap": 0.67, "stop": "", "duree": 150.0, "voyant": "moteur", "poids": 1.5,
		"nom": ["Surchauffe moteur", "Motor overheating"],
		"quoi": ["Bobinages à 105 °C : la protection déclasse la puissance et plafonne à 8 m/s.",
			"Windings at 105 °C: protection derates power and caps at 8 m/s."],
		"faire": ["Continuer en mode dégradé jusqu'au terminus.", "Limp to the terminus in degraded mode."],
		"interdit": ["Vitesse au-delà de 8 m/s.", "Speed above 8 m/s."]},
	"f_rail_mouille": {"g": ["funival"], "grav": "avis", "cap": 0.5, "stop": "", "duree": 120.0, "voyant": "cable", "poids": 1.5,
		"nom": ["Rail mouillé", "Wet rail"],
		"quoi": ["Suintement dans le tunnel : adhérence réduite, plafond à 6 m/s.", "Seepage in the tunnel: reduced grip, capped at 6 m/s."],
		"faire": ["Continuer doucement, la protection se relève seule.", "Carry on gently, the protection resets on its own."],
		"interdit": ["Vitesse au-delà de 6 m/s.", "Speed above 6 m/s."]},
	"f_moteur": {"g": ["funival"], "grav": "degrade", "cap": 0.75, "stop": "", "duree": 0.0, "voyant": "moteur", "poids": 1.0,
		"nom": ["Groupe moteur hors service", "Motor set out of service"],
		"quoi": ["Un groupe moteur hors service : service sur les groupes restants, plafond 9 m/s.",
			"One motor set out of service: running on the others, capped at 9 m/s."],
		"faire": ["Continuer en mode dégradé ; réparation en fin de service.", "Carry on degraded; repair after service."],
		"interdit": ["Vitesse au-delà de 9 m/s.", "Speed above 9 m/s."]},
	"f_alim": {"g": ["funival"], "grav": "arret", "cap": 0.0, "stop": "urgence", "duree": 25.0, "voyant": "moteur", "poids": 1.0,
		"nom": ["Perte des auxiliaires", "Auxiliary power loss"],
		"quoi": ["Perte du 400 V auxiliaire : contacteur de traction ouvert, frein à manque de courant serré.",
			"Auxiliary 400 V lost: traction contactor open, fail-safe brake applied."],
		"faire": ["Attendre le secours (~25 s), RÉARMER, puis DÉMARRER.", "Wait for the back-up (~25 s), RESET, then START."],
		"interdit": ["Traction et départ tant que le 400 V n'est pas revenu.", "Traction and departure until 400 V returns."]},
	"f_frein_parking": {"g": ["funival"], "grav": "arret", "cap": 0.0, "stop": "", "duree": 0.0, "voyant": "frein", "poids": 1.0,
		"bloque": true, "cycle_urgence": true, "nom": ["Frein de parking collé", "Parking brake stuck"],
		"quoi": ["Le frein de parking refuse de se relâcher : le véhicule ne peut pas partir.",
			"The parking brake will not release: the car cannot depart."],
		"faire": ["À l'arrêt, cycler l'ARRÊT D'URGENCE puis RÉARMER, puis DÉMARRER.", "At standstill, cycle the EMERGENCY STOP then RESET, then START."],
		"interdit": ["Toute traction tant que le frein ne se libère pas.", "Any traction until the brake releases."]},
	"f_rupture": {"g": ["funival"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "cable", "poids": 0.0,
		"nom": ["Rupture du câble tracteur", "Haul-rope rupture"],
		"quoi": ["RUPTURE DU CÂBLE TRACTEUR : les freins sur rail ont saisi les deux véhicules.",
			"HAUL-ROPE RUPTURE: the rail brakes have gripped both cars."],
		"faire": ["1) Maintenir à l'arrêt  2) Annonce incident puis évacuation  3) Évacuer par le passage de service  4) Service terminé.",
			"1) Keep stopped  2) Incident then evacuation announcement  3) Evacuate via the service walkway  4) Service over."],
		"interdit": ["Tout redémarrage. Service terminé.", "Any restart. Service over."]},
	"f_frein_service": {"g": ["funival"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "frein", "poids": 0.0,
		"nom": ["Frein de service défaillant", "Service brake failure"],
		"quoi": ["Frein de service hydraulique à 25 % d'efficacité : la chaîne de sécurité arrête tout.",
			"Hydraulic service brake at 25 % efficiency: the safety chain stops everything."],
		"faire": ["1) Arrêt d'urgence (auto)  2) Annonce incident  3) Évacuer  4) Service terminé.",
			"1) Emergency stop (auto)  2) Incident announcement  3) Evacuate  4) Service over."],
		"interdit": ["Tout redémarrage.", "Any restart."]},
	"f_inondation": {"g": ["funival"], "grav": "degrade", "cap": 0.33, "stop": "", "duree": 180.0, "voyant": "cable", "poids": 0.8,
		"nom": ["Eau dans le tunnel", "Water in the tunnel"],
		"quoi": ["Eau stagnante dans le tunnel : adhérence critique, plafond à 4 m/s.", "Standing water in the tunnel: critical grip, capped at 4 m/s."],
		"faire": ["Continuer au pas jusqu'au terminus.", "Crawl on to the terminus."],
		"interdit": ["Vitesse au-delà de 4 m/s.", "Speed above 4 m/s."]},
	"f_comms": {"g": ["funival"], "grav": "avis", "cap": 1.0, "stop": "", "duree": 90.0, "voyant": "secu_ligne", "poids": 1.0,
		"nom": ["Perte des communications", "Communications loss"],
		"quoi": ["Sonorisation et radio du tunnel perdues : passagers et machinerie isolés.",
			"PA and tunnel radio lost: passengers and machine room isolated."],
		"faire": ["Continuer, surveiller les autres systèmes de près.", "Carry on, watch the other systems closely."],
		"interdit": ["Annonces dans le tunnel.", "Tunnel announcements."]},
	"f_aiguillage": {"g": ["funival"], "grav": "arret", "cap": 0.0, "stop": "normal", "duree": 60.0, "voyant": "secu_ligne", "poids": 1.0,
		"nom": ["Aiguillage de l'évitement", "Passing-loop switch"],
		"quoi": ["Défaut de position à l'évitement : arrêt avant les aiguillages jusqu'au verrouillage.",
			"Position fault at the passing loop: stop before the switches until locked."],
		"faire": ["Attendre la remise en place, RÉARMER si besoin, puis DÉMARRER.", "Wait for it to be reset, RESET if needed, then START."],
		"interdit": ["Franchir l'évitement.", "Crossing the passing loop."]},
	"f_incendie": {"g": ["funival"], "grav": "grave", "cap": 0.0, "stop": "urgence", "duree": 0.0, "voyant": "secu_ligne", "poids": 0.0,
		"nom": ["Détection de fumée", "Smoke detection"],
		"quoi": ["DÉTECTION DE FUMÉE en véhicule ou en tunnel : frein d'urgence engagé.",
			"SMOKE DETECTED in a car or the tunnel: emergency brake applied."],
		"faire": ["1) Arrêt complet  2) Annonce d'évacuation  3) Évacuer par le passage de service  4) Service terminé.",
			"1) Full stop  2) Evacuation announcement  3) Evacuate via the service walkway  4) Service over."],
		"interdit": ["Tout redémarrage. Service terminé.", "Any restart. Service over."]},
}


## Pannes possibles pour un groupe (ordre du catalogue = ordre du menu).
static func du_groupe(groupe: String) -> Array:
	var out: Array = []
	for id in P:
		if groupe in (P[id]["g"] as Array):
			out.append(id)
	return out


## Tirage pondéré parmi les pannes du groupe (jamais les graves).
static func au_hasard(groupe: String) -> String:
	var ids: Array = []
	var tot: float = 0.0
	for id in du_groupe(groupe):
		var w: float = float(P[id].get("poids", 0.0))
		if w > 0.0 and P[id]["grav"] != "grave":
			ids.append([id, w])
			tot += w
	if ids.is_empty():
		return ""
	var r: float = randf() * tot
	for e in ids:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return ids[-1][0]
