class_name PNConstants
extends Node
## Constantes physiques et géométriques du funiculaire Perce-Neige.
## Portées directement de perce_neige_sim.py — sources : Wikipedia (FR/EN),
## remontees-mecaniques.net, CFD, observations directes du cockpit video.

# ---------------------------------------------------------------------------
# Physique de base
# ---------------------------------------------------------------------------

const G: float = 9.80665  # m/s²

# ---------------------------------------------------------------------------
# Géométrie du funiculaire (specs réelles Von Roll / CFD 1993)
# ---------------------------------------------------------------------------

const LENGTH: float = 3474.0             # longueur le long de la pente (m)
const ALT_LOW: float = 2111.0            # altitude Val Claret (m)
const ALT_HIGH: float = 3032.0           # altitude Glacier (m)
const DROP: float = 921.0                # dénivelé (m)

const SQUARE_SECTION_LOW_END: float = 257.0    # transition carré→rond bas
const SQUARE_SECTION_HIGH_START: float = 3420.0  # transition rond→carré haut

# Vitesse — régulateur Von Roll plafonné à 12 m/s
const V_MAX: float = 12.0                # m/s (43.2 km/h)
const V_CRUISE_PEAK: float = 12.0        # heure de pointe
const V_CRUISE_OFFPEAK: float = 10.3     # hors pointe
const V_CREEP: float = 0.5               # vitesse creep sur plateforme

# Accélération — profil calibré vidéo FUNI284 (2→12 m/s en ~33 s)
const A_TARGET: float = 0.30             # accel programmée (m/s²)
const A_MAX_REG: float = 0.32            # cap dur accel moteur
const A_START: float = 0.12              # accel initiale à v=0
const V_SOFT_RAMP: float = 2.0           # vitesse où cap atteint A_MAX_REG
const A_NATURAL_UP: float = 0.25         # décel coast en montée
const A_BRAKE_NORMAL: float = 2.5        # frein service (m/s²)
const A_BRAKE_EMERGENCY: float = 5.0     # frein urgence (m/s²)
const A_BRAKE_EMERG_RAMP: float = 8.0    # rampe frein urgence (1/s)
const MU_ROLL: float = 0.0025            # frottement roulement

# Moteurs — 3 × 800 kW DC
const P_MAX: float = 2_400_000.0         # puissance totale (W)
const F_STALL: float = 260_000.0         # force max moteur (N)

# Câble Fatzer 52 mm
const T_NOMINAL_DAN: float = 22500.0
const T_WARN_DAN: float = 28000.0
const T_BREAK_DAN: float = 191200.0
const CABLE_DIAM_MM: float = 52.0

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
const BUMPER_CLEAR: float = 4.0          # marge cabine ↔ tampon en bas (réaliste)
const START_S: float = 20.0              # TRAIN_HALF + BUMPER_CLEAR (= 16 + 4)
# En haut, on s'arrête plus court (cabine 1m du tampon) — gare terminus serrée
const STOP_S: float = 3457.0             # LENGTH − TRAIN_HALF − 1 → cabine_front = 3473 m
const CREEP_DIST: float = 55.0           # 20 + PLATFORM_LEN
const CREEP_START_S: float = 3402.0      # STOP_S − CREEP_DIST

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
const PASSING_START: float = 1611.0
const PASSING_END: float = 1813.0

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
