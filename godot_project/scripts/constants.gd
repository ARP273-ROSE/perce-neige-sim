class_name PNConstants
extends Node
## Constantes physiques et géométriques du funiculaire Perce-Neige.
## Portées directement de perce_neige_sim.py — sources : Wikipedia (FR/EN),
## remontees-mecaniques.net, CFD, observations directes du cockpit video.

# ---------------------------------------------------------------------------
# Physique de base
# ---------------------------------------------------------------------------

const G: float = 9.80665  # m/s²

# Tampon de build, affiché sur l'écran de choix du scénario. Il est
# réécrit automatiquement par deploy_web.sh au moment de l'export (date +
# heure), puis remis à "dev" — il sert à voir D'UN COUP D'OEIL si la PWA
# tourne bien sur la dernière version ou sur une copie encore en cache
# dans le service worker (retour d'essai iPad 2026-08-21 : « pas de son de
# crash » = c'était l'ancien build qui tournait).
const BUILD_TAG: String = "dev"


# Safari (iPad/iPhone/macOS) : la lecture audio « Sample » des exports web
# (défaut Godot ≥ 4.3) est muette puis fait planter la page sous WebKit
# (godot#116750) — le contournement documenté est le mode « Stream ».
# Chrome/Android marche très bien en Sample → bascule à l'EXÉCUTION,
# uniquement quand l'UA est un vrai Safari (WebKit sans Chrome/Android).
## Position de l'autre rame quand celle-ci est à s (miroir des points
## d'arrêt, cf. MIROIR_S).
static func miroir(s_: float) -> float:
	return MIROIR_S - s_


## Compteur de distance du pupitre (fait de Kevin, 06/10/2026) : 0 m au
## départ, 3 474 m à l'arrivée, quels que soient le sens et la rame — la
## distance réellement parcourue depuis l'arrêt de départ (STOP_S −
## START_S = PARCOURS ; même calcul que distance_compteur du PC).
static func distance_compteur(s_: float, direction: int) -> float:
	var raw: float = (s_ - START_S) if direction > 0 else (STOP_S - s_)
	return clampf(raw, 0.0, PARCOURS)


static func safari_web() -> bool:
	if not OS.has_feature("web"):
		return false
	var ua: Variant = JavaScriptBridge.eval("navigator.userAgent", true)
	if not (ua is String):
		return false
	var s: String = ua
	return s.contains("Safari") and not s.contains("Chrome") \
		and not s.contains("CriOS") and not s.contains("Chromium") \
		and not s.contains("Android") and not s.contains("Edg") \
		and not s.contains("FxiOS")

# ---------------------------------------------------------------------------
# Géométrie du funiculaire (specs réelles Von Roll / CFD 1993)
# ---------------------------------------------------------------------------

# Longueur de la voie, du butoir bas au butoir haut. Le PARCOURS d'un
# trajet, d'arrêt à arrêt, fait 3 474 m (fait de Kevin, 06/10/2026 : « la
# distance parcourue réelle de chaque trajet c'est 3 474 m ») : la voie
# fait donc 40,52 m de plus — rallongée par deux tronçons neutres (pente
# constante, ligne droite) de 20,26 m de part et d'autre de l'évitement,
# à 1 571 m et à 1 853,5 m de l'ancien tracé (SlopeProfile).
const PARCOURS: float = 3474.0           # trajet d'arrêt à arrêt (compteur du pupitre)
const LENGTH: float = 3514.52            # voie le long de la pente (m) = START_S + PARCOURS + 17,96
const ALT_LOW: float = 2111.0            # altitude Val Claret (m)
const ALT_HIGH: float = 3032.0           # altitude Glacier (m)
const DROP: float = 921.0                # dénivelé (m)

const SQUARE_SECTION_LOW_END: float = 257.0    # transition carré→rond bas
const SQUARE_SECTION_HIGH_START: float = 3460.52  # transition rond→carré haut (3420 + 40,52)

# Vitesse — régulateur Von Roll plafonné à 12 m/s
const V_MAX: float = 12.0                # m/s (43.2 km/h)
const V_CRUISE_PEAK: float = 12.0        # heure de pointe
const V_CRUISE_OFFPEAK: float = 10.3     # hors pointe
const V_CREEP: float = 0.75              # vitesse creep (fait terrain : entrée en gare à 0,75 m/s)

# Accélération — profil calibré vidéo FUNI284 (2→12 m/s en ~33 s)
const A_TARGET: float = 0.30             # accel programmée (m/s²)
const A_MAX_REG: float = 0.32            # cap dur accel moteur
const A_START: float = 0.12              # accel initiale à v=0
const V_SOFT_RAMP: float = 2.0           # vitesse où cap atteint A_MAX_REG
const A_NATURAL_UP: float = 0.25         # décel coast en montée
const A_BRAKE_NORMAL: float = 2.5        # frein service (m/s²)
# Frein d'urgence : ALIGNÉ SUR LE SIM PYTHON (audit décélérations 2026-07-06,
# sources RM5/POMA/STRMTG) : le bouton rouge = frein de sécurité sur la
# POULIE motrice, câble intact → 1,25 m/s² (norme passagers debout). Le
# parachute Belleville 3,6 m/s² n'existe qu'en survitesse +20 % / rupture
# câble (pas modélisé dans le port 3D). Répond aussi au retour d'essai
# 2026-07-12 « arrêt d'urgence trop brutal » (5,0 = plafond réglementaire
# absolu appliqué à tort).
const A_BRAKE_EMERGENCY: float = 1.25    # frein urgence commandé (m/s²)
const A_BRAKE_EMERG_RAMP: float = 8.0    # rampe frein urgence (1/s) — idem PC
# Rupture du câble (retour du 01/10/2026 : « la machinerie doit s'arrêter,
# là elle s'emballe ») : la chaîne de sécurité coupe l'entraînement et les
# freins des roues motrices arrêtent la machinerie, déchargée — décélération
# à la jante (audit_physique/rupture_cable.sage).
const A_DRIVE_TRIP: float = 2.0
const MU_ROLL: float = 0.0025            # frottement roulement

# Moteurs — 3 × 800 kW DC
const P_MAX: float = 2_400_000.0         # puissance totale (W)
const F_STALL: float = 260_000.0         # force max moteur (N)

# Câble Fatzer 52 mm.
# T_NOMINAL = tension de SERVICE normale (la jauge vit autour de cette
# valeur toute la journée — ce n'est PAS un seuil d'alerte) ; l'alerte ne
# commence qu'à T_WARN, le rouge à T_RED. La rupture (191 200 daN, facteur
# de sécurité ~8,5) est très au-delà de l'échelle affichable.
const T_NOMINAL_DAN: float = 22500.0
const T_WARN_DAN: float = 28000.0
const T_RED_DAN: float = 35000.0         # zone rouge de la jauge (affichage)
const T_GAUGE_MAX_DAN: float = 42000.0   # pleine échelle de la jauge (affichage)
const T_BREAK_DAN: float = 191200.0
const CABLE_DIAM_MM: float = 52.0
# Masse linéique du câble (≈ 38 t sur la ligne) — le poids du brin entre la
# rame lourde et la poulie motrice pèse jusqu'à ~9 900 daN sur la jauge de
# tension quand la rame est en bas (port du modèle Python, audit 2026-07-06).
const CABLE_KG_M: float = 11.0
# --- Audit physique 2026-09-26 (port du PC) -------------------------------
# Poids propre du câble dans le bilan des forces, résistance des galets,
# traînée d'air en tunnel (tube unique / évitement), rendement électrique.
# Détail et justification : AUDIT_PHYSIQUE_VOYAGES.md à la racine du dépôt.
const ROPE_MASS_KG: float = CABLE_KG_M * LENGTH   # ~38 t en mouvement
const CABLE_ROLLER_C: float = 0.015      # résistance câble/galets (fraction charge normale)
const DRIVE_EFF: float = 0.90            # réseau → jante (traction)
const DRIVE_CU_LOSS_FRAC: float = 0.04   # pertes cuivre au courant nominal (fraction de P_MAX)
const DRIVE_FIELD_KW: float = 15.0       # excitation + auxiliaires du drive engagé
const REGEN_EFF: float = 0.80            # jante → réseau (génératrice)
const AERO_BLOCKAGE: float = 0.65        # β = section bloquée / section d'air libre
const AERO_BED_H_M: float = 0.5          # radier béton dans le tube
const AERO_LAMBDA: float = 0.025         # Darcy, béton + peau de la rame
const AERO_K_IN: float = 0.4             # contraction au nez
const AERO_LOOP_LEN_M: float = 203.0     # longueur du second tube

# Tunnel
const TUNNEL_DIAM_M: float = 3.9         # diamètre min
const TUNNEL_RADIUS: float = 1.95
const GAUGE_MM: float = 1200.0           # écartement rails

# Train — 2 voitures couplées
const TRAIN_EMPTY_KG: float = 32300.0
const TRAIN_MAX_KG: float = 58800.0
const PAX_KG: float = 75.0
const PAX_MAX: int = 334
const CAR_COUNT: int = 2
const DOORS_PER_CAR: int = 3
const CAR_LEN_M: float = 16.0
const TRAIN_LEN: float = 32.0
const TRAIN_HALF: float = 16.0
const CAR_DIAM_M: float = 3.60

# Plateformes / stations
const PLATFORM_LEN: float = 35.0
# Points d'arrêt (fait de Kevin, 06/10/2026 : « en haut on s'arrête à
# 1,5 m du butoir ; en bas à 4 ou 5 m, pour la marge d'oscillation et
# d'allongement »), comptés depuis la face des têtes en bois des butoirs
# (stations_builder._build_bumper) : audit_physique/arrets_gares.sage.
const BUTOIR_BAS_S: float = 2.06         # face du butoir bas (socle à 2,0 m)
const BUTOIR_HAUT_S: float = 3514.06     # face du butoir haut (socle à LENGTH − 0,4)
const JEU_BUTOIR_BAS: float = 4.5        # arrière de la rame ↔ butoir bas
const JEU_BUTOIR_HAUT: float = 1.5       # nez de la rame ↔ butoir haut
const START_S: float = 22.56             # BUTOIR_BAS_S + JEU_BUTOIR_BAS + TRAIN_HALF
const STOP_S: float = 3496.56            # BUTOIR_HAUT_S − JEU_BUTOIR_HAUT − TRAIN_HALF = START_S + PARCOURS
# Les deux rames sont liées par le câble : l'autre rame est au MIROIR des
# points d'arrêt, MIROIR_S − s — quand l'une est à STOP_S, l'autre est à
# START_S. Le câble entre elles fait 2·LENGTH − MIROIR_S = 3 469,4 m :
# 4,6 m de moins que la voie (avec LENGTH − s, la rame d'en face finissait
# 1 m DANS le butoir bas quand on arrivait en haut).
const MIROIR_S: float = 3519.12          # START_S + STOP_S
# Quais (fait de Kevin, 06/10/2026 : « en bas le quai se prolonge de 4 m
# vers le haut après le haut de la rame ; en haut de 3 m après le bas de la
# rame ») — rame arrêtée en START_S / STOP_S. Le galet n° 1 est juste après
# le quai bas, le n° 238 à l'entrée du quai haut, où la pente de la gare
# haute est atteinte (SlopeProfile, track_builder.SUPPORT_S*).
const QUAI_BAS_DEBUT_S: float = 3.0
const QUAI_BAS_FIN_S: float = 42.56      # START_S + TRAIN_HALF + 4
const QUAI_HAUT_DEBUT_S: float = 3477.56 # STOP_S − TRAIN_HALF − 3
const QUAI_HAUT_FIN_S: float = 3513.52   # LENGTH − 1
const CREEP_DIST: float = 55.0           # 20 + PLATFORM_LEN
const CREEP_START_S: float = 3441.56     # STOP_S − CREEP_DIST

# Portes
const DOOR_CLOSE_TIME: float = 3.0
const DOOR_OPEN_TIME: float = 2.0

# Élasticité câble — rebond après arrêt
const REBOUND_GHOST_AMP: float = 1.10    # m (creep wagon opposé)
const REBOUND_MAIN_AMP: float = 0.22     # m (creep train principal)
const REBOUND_TAU: float = 0.70          # s (constante temps)
const REBOUND_OSC_AMP: float = 0.10      # m
const REBOUND_OMEGA: float = 2.40        # rad/s
const REBOUND_ZETA: float = 0.10         # amortissement

# Boucle de croisement — positions calibrées vidéo cockpit
const PASSING_START: float = 1631.26    # 1611 + 20,26 (tronçon neutre aval)
const PASSING_END: float = 1833.26      # 1813 + 20,26

# ---------------------------------------------------------------------------
# Mode de jeu
# ---------------------------------------------------------------------------

enum Mode {
	TITLE,
	RUN,
	PAUSED,
	OVER,
}

enum ViewMode {
	FIRST_PERSON,
	SIDE_PROFILE,
	EXTERIOR,
}

enum Direction {
	UP = 1,    # Val Claret → Glacier
	DOWN = -1, # Glacier → Val Claret
}

# Portes — calage sur les enregistrements réels (2026-09-27). La fermeture
# est une séquence EN SÉRIE : annonce → buzzer (door_buzzer.wav, 7,0 s) →
# clip de fermeture (door_motion.wav, 7,0 s). Dans ce clip, les vantaux
# partent à 1,3 s et butent à 5,3 s (le « clac » de fin de course, lisible
# dans l'enveloppe du son). Même calage côté PC (perce_neige_sim.py).
const DOOR_BUZZER_S: float = 7.0
const DOOR_CLIP_S: float = 7.0
const DOOR_MOTION_LEAD: float = 1.3
const DOOR_MOTION_S: float = 4.0
