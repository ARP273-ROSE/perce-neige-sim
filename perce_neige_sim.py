"""
Perce-Neige Simulator — Grande Motte funicular simulation (Tignes, France).

Accurate PC remake of the TI-84 FUNIC program. Real specs sourced from
Wikipedia (FR/EN), remontees-mecaniques.net and CFD (rolling stock maker):
  - Length along slope : 3491 m
  - Altitudes          : 2111 m (Val Claret) -> 3032 m (Glacier)
  - Vertical drop      : 921 m
  - Gradient           : 18% min, 30% max, ~27% average
  - Max speed          : 12 m/s (43.2 km/h)
  - Trains             : 2 x 2 cars, 334 pax + 1 conductor each
  - Empty / full mass  : 32.3 t / 58.8 t
  - Motors             : 3 DC, total 2400 kW
  - Cable              : Fatzer, 52 mm, nominal 22500 daN, breaking 191200 daN
  - Tunnel             : fully underground, min 3.9 m, 1200 mm gauge
  - Passing loop       : ~200 m middle section with twin tunnels
  - Built by           : Von Roll / CFD. Opened 14 April 1993.

Author : Kevin Guion (original TI-Basic FUNIC), PyQt6 port 2026.
"""

from __future__ import annotations

import locale
import math
import os
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PyQt6.QtCore import QEvent, QPointF, QRectF, Qt, QTimer, QUrl
from PyQt6.QtGui import (
    QBrush,
    QColor,
    QConicalGradient,
    QDesktopServices,
    QFont,
    QIcon,
    QKeyEvent,
    QLinearGradient,
    QMouseEvent,
    QPainter,
    QPainterPath,
    QPen,
    QPolygonF,
    QRadialGradient,
    QTransform,
)
from PyQt6.QtWidgets import (
    QApplication,
    QDialog,
    QDialogButtonBox,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QVBoxLayout,
    QWidget,
)

try:
    from PyQt6.QtMultimedia import QAudioOutput, QMediaPlayer
    _QTMULTIMEDIA_OK = True
except ImportError:
    _QTMULTIMEDIA_OK = False

VERSION = "1.1.0"
APP_NAME = "Perce-Neige Simulator"

# ---------------------------------------------------------------------------
# I18N — bilingual FR / EN, auto-detected from system locale
# ---------------------------------------------------------------------------

def _detect_lang() -> str:
    try:
        lang = (locale.getdefaultlocale()[0] or "").lower()
    except Exception:
        lang = ""
    return "fr" if lang.startswith("fr") else "en"


LANG = _detect_lang()


def T(en: str, fr: str) -> str:
    return fr if LANG == "fr" else en


# ---------------------------------------------------------------------------
# Physical constants and real funicular specifications
# ---------------------------------------------------------------------------

G = 9.80665                 # m/s^2
LENGTH = 3491.0             # slope length (m) — Wikipedia / remontées-mec.
ALT_LOW = 2111.0            # lower station altitude (m)
ALT_HIGH = 3032.0           # upper station altitude (m)
DROP = ALT_HIGH - ALT_LOW   # 921 m

V_MAX = 12.0                # hard cap regulator (m/s) — real value
# Acceleration profile calibrated from video analysis of a real 12 m/s
# run (YouTube FUNI284, 414 s total, filmed at upper station Aug 2013).
# The run shows a cosine-ramp accel over ~64 s (2→12 m/s) with peak
# ~0.245 m/s^2, and a sine-ramp decel over ~50 s (12→1 m/s) with peak
# ~0.34 m/s^2. Approach creep lasts ~30 s.
A_TARGET = 0.22             # programmed accel target (m/s^2) — video-calibrated
A_MAX_REG = 0.30            # hard cap on motor-induced accel
# Soft-start profile — real Von Roll speed programmer.
# The train creeps out of the station at A_START then ramps up once
# clear of the platform. Calibrated from yellow-pixel tracking of
# the departure sequence: 16 s platform transit at ~0.12 m/s^2.
A_START = 0.12              # initial comfort accel at v=0 (m/s^2)
V_SOFT_RAMP = 2.0           # speed at which cap reaches A_MAX_REG (m/s)
# Gravity-natural coast decel : on the climbing funicular, cutting the
# motor lets gravity imbalance + rolling friction decelerate the train.
# The real drivers don't touch the service brake on approach — the
# regulator gradually reduces motor force, letting net gravity decel
# the train at about 0.25 m/s^2. Calibrated from the audio RMS curve
# of the deceleration phase (t=340-390 in the reference video).
A_NATURAL_UP = 0.25         # expected coast decel on ascending trip (m/s^2)
P_MAX = 2_400_000.0         # total motor power (W) — 3 × 800 kW
F_STALL = 260_000.0         # hard cap on motor force (N)

T_NOMINAL_DAN = 22_500.0    # nominal cable tension (daN)
T_WARN_DAN = 28_000.0       # warning threshold
T_BREAK_DAN = 191_200.0     # breaking strength (daN)

CABLE_DIAM_MM = 52.0
TUNNEL_DIAM_M = 3.9
GAUGE_MM = 1200.0

TRAIN_EMPTY_KG = 32_300.0       # empty train mass (two coupled cars)
TRAIN_MAX_KG = 58_800.0         # max loaded — matches real spec
PAX_KG = 75.0
PAX_MAX = 334                   # 334 + 1 conductor per train
CAR_COUNT = 2                   # cars per train
DOORS_PER_CAR = 3               # 3 doors per side per car
CAR_LEN_M = 16.0                # single car length (m)
TRAIN_LEN = CAR_COUNT * CAR_LEN_M   # total train length — 32 m
TRAIN_HALF = TRAIN_LEN / 2.0        # centre-to-end — 16 m
CAR_DIAM_M = 3.60               # cylindrical diameter

# Platform / station geometry
PLATFORM_LEN = 35.0             # platform slope length (m)
# Positions of the train *centre* at rest in each station :
START_S = TRAIN_HALF            # back of train flush with s=0
STOP_S = LENGTH - TRAIN_HALF    # front of train flush with s=LENGTH

# Approach profile — the train decelerates to CREEP_V and maintains it
# from CREEP_START up to STOP_S, entering the station quietly.
CREEP_V = 1.0                   # creep speed on platform approach (m/s)
# Front reaches 1 m/s when 20 m before the platform start, then rolls
# at 1 m/s through the 20 m approach + 35 m platform = 55 m.
CREEP_DIST = 20.0 + PLATFORM_LEN        # 55 m measured in centre-position
CREEP_START_S = STOP_S - CREEP_DIST     # centre position at creep entry

A_BRAKE_NORMAL = 2.5            # m/s^2
A_BRAKE_EMERGENCY = 5.0         # m/s^2 — full emergency deceleration
A_BRAKE_EMERG_RAMP = 8.0        # ramp rate (1/s) : emergency brake reaches
                                # full effect in ~0.4 s instead of instantly.
MU_ROLL = 0.0025                # rail rolling resistance

# Door transition durations — closing is longer than opening because
# the announcement chime plays first, THEN the leaves swing shut.
DOOR_CLOSE_TIME = 3.0           # s (fermeture)
DOOR_OPEN_TIME = 2.0            # s (ouverture)

# Cable elasticity rebound — damped oscillation when the train stops.
# Measured from video imkfB1YDoAA (arrival at Val Claret) and validated
# by cable stretch physics (E≈100 GPa, L=3491 m, A=π×26² mm²).
# Model : x(t) = A·exp(-ζωt)·sin(ωt)   (spring-damper)
REBOUND_AMP = 0.04              # m — initial oscillation amplitude (~4 cm)
REBOUND_OMEGA = 1.6             # rad/s — natural frequency (T ≈ 3.9 s)
REBOUND_ZETA = 0.05             # damping ratio (3-4 visible oscillations)

# Passing loop (middle section where tunnel splits in two) ~200 m long
PASSING_START = 1640.0
PASSING_END = 1843.0

# Slope profile : (slope distance in m, gradient as fraction).
# Technical sources: "pente douce" at start, "montée plus raide" in middle,
# max gradient 30 %, average 26.7 %, altitude gain 932 m (2100→3032 m).
# Integrates to 932 m ± 1 m.
SLOPE_PROFILE: list[tuple[float, float]] = [
    (0.0,    0.15),    # gentle release from Val Claret station
    (150.0,  0.20),    # transition to steeper climb
    (400.0,  0.24),
    (800.0,  0.28),
    (1250.0, 0.29),
    (1500.0, 0.29),    # entering first right curve
    (1640.0, 0.29),    # entering passing loop
    (1843.0, 0.29),    # exiting passing loop
    (2000.0, 0.29),    # entering second right curve
    (2400.0, 0.30),    # steepest section
    (2800.0, 0.30),
    (3100.0, 0.26),    # easing toward upper station
    (3300.0, 0.20),
    (3491.0, 0.12),    # slow approach to Panoramic station
]

# Horizontal route plan : (slope distance, bearing in degrees).
# GPS coordinates : Val Claret 45.4578°N 6.9014°E → Grande Motte
# 45.4354°N 6.9020°E ; straight-line bearing ≈ 179° (due S).
# Two right curves separated by a straight section through the passing
# loop (remontees-mecaniques.net technical description confirmed).
# Net heading change ≈ 48° right (155° → 203°).
CURVE_PROFILE: list[tuple[float, float]] = [
    (0.0,    155.0),   # SSE out of Val Claret station
    (600.0,  155.0),   # straight lower section
    (850.0,  165.0),   # curve 1 : right, peak curvature
    (1100.0, 175.0),   # continuing curve 1
    (1580.0, 179.0),   # end of curve 1 — entering straight (≈ due S)
    (1640.0, 179.0),   # entering passing loop (straight)
    (1843.0, 179.0),   # exiting passing loop (straight)
    (2000.0, 179.0),   # start of curve 2
    (2300.0, 189.0),   # curve 2 : right, peak curvature
    (2650.0, 203.0),   # end of curve 2
    (3491.0, 203.0),   # straight into upper station (SSW)
]

# Tunnel lighting zones — (start_m, end_m) of DARK sections identified from
# high-resolution brightness analysis (ceiling ROI, 1-second sampling).
# Fluorescent tube spacing ≈ 32 m.  Passing loop is well-lit.
TUNNEL_DARK_ZONES: list[tuple[float, float]] = [
    (166.0,   198.0),   # 32 m semi-dark (brightness 83)
    (318.0,   401.0),   # 83 m dark (brightness 45)
    (561.0,   745.0),   # 185 m major dark zone (brightness 50)
    (1408.0, 1465.0),   # 57 m semi-dark before passing loop
    (1586.0, 1605.0),   # 19 m brief dark at passing loop entry
    (2102.0, 2236.0),   # 134 m major dark zone (brightness 57)
    (2746.0, 2784.0),   # 38 m dark (brightness 63)
    (2981.0, 3109.0),   # 127 m major dark zone (brightness 47)
    (3217.0, 3249.0),   # 32 m dark near upper station (brightness 39)
]

# Tunnel cross-section transitions — (start_m, shape)
# "horseshoe" near stations, "circular" (TBM bore) in the middle
TUNNEL_SECTIONS: list[tuple[float, str]] = [
    (0.0,    "horseshoe"),  # station exit
    (100.0,  "circular"),   # TBM section begins (video t=110)
    (3400.0, "horseshoe"),  # upper station approach (video t=460)
    (3491.0, "horseshoe"),
]


def _interp(table: list[tuple[float, float]], s: float) -> float:
    if s <= table[0][0]:
        return table[0][1]
    if s >= table[-1][0]:
        return table[-1][1]
    for i in range(len(table) - 1):
        s0, v0 = table[i]
        s1, v1 = table[i + 1]
        if s0 <= s <= s1:
            k = (s - s0) / max(s1 - s0, 1e-6)
            return v0 + k * (v1 - v0)
    return table[-1][1]


def gradient_at(s: float) -> float:
    return _interp(SLOPE_PROFILE, s)


def heading_at(s: float) -> float:
    """Bearing in degrees (0 = north, 90 = east) at slope distance s."""
    return _interp(CURVE_PROFILE, s)


def curvature_at(s: float) -> float:
    """Signed curvature in deg/m at slope distance *s*.

    Positive = turning right, negative = turning left.
    Computed as the derivative of heading_at(s).
    """
    ds = 5.0  # finite difference step
    return (heading_at(s + ds) - heading_at(s - ds)) / (2.0 * ds)


def tunnel_lit_at(s: float) -> bool:
    """Return True if the tunnel is lit at slope distance *s*."""
    for dark_start, dark_end in TUNNEL_DARK_ZONES:
        if dark_start <= s <= dark_end:
            return False
    return True


def tunnel_shape_at(s: float) -> str:
    """Return 'circular' or 'horseshoe' at slope distance *s*."""
    shape = "circular"
    for sec_s, sec_shape in TUNNEL_SECTIONS:
        if s >= sec_s:
            shape = sec_shape
    return shape


def is_passing_loop(s: float) -> bool:
    """Return True if front of train is inside the passing loop."""
    return PASSING_START <= s <= PASSING_END


# Pre-computed geometry : for every slope distance s we store the side-view
# position (along-slope horizontal projection, altitude) AND the plan-view
# position (bird's-eye px, py in metres, with 0,0 at the Val Claret portal).
_GEOM_DS = 2.0
_GEOM: list[tuple[float, float, float, float, float]] = []


def _build_geometry() -> None:
    global _GEOM
    s = 0.0
    # Side view: horizontal-projection x, altitude y
    sx = 0.0
    sy = ALT_LOW
    # Plan view: px, py in metres (ground plane)
    px = 0.0
    py = 0.0
    rows: list[tuple[float, float, float, float, float]] = [
        (s, sx, sy, px, py)
    ]
    n = int(LENGTH / _GEOM_DS)
    for _ in range(n):
        s_new = s + _GEOM_DS
        s_mid = (s + s_new) / 2.0
        g = gradient_at(s_mid)
        theta = math.atan(g)
        # Side view : horizontal projection is ds * cos(theta), altitude
        # is ds * sin(theta).
        dx_side = _GEOM_DS * math.cos(theta)
        dy_side = _GEOM_DS * math.sin(theta)
        sx += dx_side
        sy += dy_side
        # Plan view : consume the horizontal projection along the bearing.
        bearing_deg = heading_at(s_mid)
        bearing = math.radians(bearing_deg)
        # 0° = north (py+), 90° = east (px+)
        px += dx_side * math.sin(bearing)
        py += dx_side * math.cos(bearing)
        s = s_new
        rows.append((s, sx, sy, px, py))
    # Rescale altitude so the total drop is exactly DROP (921 m)
    computed_drop = rows[-1][2] - rows[0][2]
    if computed_drop > 0:
        scale = DROP / computed_drop
        rows = [
            (s_, sx_, ALT_LOW + (sy_ - ALT_LOW) * scale, px_, py_)
            for (s_, sx_, sy_, px_, py_) in rows
        ]
    _GEOM = rows


_build_geometry()


def geom_at(s: float) -> tuple[float, float]:
    """Return (side-view horizontal x, altitude y) at slope distance s."""
    s = max(0.0, min(LENGTH, s))
    idx = int(s / _GEOM_DS)
    if idx >= len(_GEOM) - 1:
        r = _GEOM[-1]
        return r[1], r[2]
    s0, sx0, sy0, _, _ = _GEOM[idx]
    s1, sx1, sy1, _, _ = _GEOM[idx + 1]
    k = (s - s0) / max(s1 - s0, 1e-6)
    return sx0 + k * (sx1 - sx0), sy0 + k * (sy1 - sy0)


def plan_at(s: float) -> tuple[float, float]:
    """Return (plan px, plan py) in metres at slope distance s."""
    s = max(0.0, min(LENGTH, s))
    idx = int(s / _GEOM_DS)
    if idx >= len(_GEOM) - 1:
        r = _GEOM[-1]
        return r[3], r[4]
    s0, _, _, px0, py0 = _GEOM[idx]
    s1, _, _, px1, py1 = _GEOM[idx + 1]
    k = (s - s0) / max(s1 - s0, 1e-6)
    return px0 + k * (px1 - px0), py0 + k * (py1 - py0)


H_MAX = _GEOM[-1][1]           # side-view horizontal extent in metres
PLAN_BOUNDS = (
    min(r[3] for r in _GEOM),
    max(r[3] for r in _GEOM),
    min(r[4] for r in _GEOM),
    max(r[4] for r in _GEOM),
)


# ---------------------------------------------------------------------------
# Game state + physics
# ---------------------------------------------------------------------------

MODE_TITLE = 0
MODE_RUN = 1
MODE_PAUSED = 2
MODE_OVER = 3


@dataclass
class Train:
    name: str = "Rame 1"
    number: int = 1
    s: float = 0.0              # slope distance from lower station (m)
    v: float = 0.0              # velocity along slope (m/s)
    a: float = 0.0              # last accel (m/s^2) — for jerk / comfort
    direction: int = +1         # +1 up, -1 down
    # speed_cmd is the driver's speed setpoint as a fraction of V_MAX
    # (0.0 = 0 m/s, 1.0 = 12 m/s). The internal motor throttle is derived
    # from this by the regulator so the train smoothly tracks the setpoint.
    speed_cmd: float = 0.0      # 0..1 — driver's commanded speed percentage
    throttle: float = 0.0       # 0..1 — internal motor demand (set by regulator)
    brake: float = 0.0          # 0..1 normal
    emergency: bool = False
    # Emergency brake ramp (0..1) : real funicular rail brakes clamp hard
    # but still over ~0.3–0.4 s, not instantly. This tracks that engagement.
    emergency_ramp: float = 0.0
    doors_open: bool = True
    # Door animation — doors_open is the physical "are they open" state.
    # doors_cmd is the commanded target and doors_timer counts down the
    # transition (closing ~3 s, opening ~2 s). The physical state only
    # flips once the timer reaches zero — that is how the real Perce-Neige
    # doors work : chime plays, then they mechanically swing shut.
    doors_cmd: bool = True
    doors_timer: float = 0.0
    pax_car1: int = 0           # pax in lower car
    pax_car2: int = 0           # pax in upper car
    # Cockpit state (realistic funicular driver station)
    lights_cabin: bool = True    # interior cabin lighting
    lights_head: bool = False    # front tunnel headlights (driver turns on)
    horn: bool = False           # momentary audible warning
    electric_stop: bool = False  # latched service stop — motor off + brake
    dead_man_timer: float = 0.0  # seconds since last driver action
    dead_man_fault: bool = False # dead-man vigilance failure (forces stop)
    # Departure protocol — real cable cars / funiculars require BOTH
    # drivers to confirm "ready to depart" before the motor is released.
    # `ready` is our main driver's confirmation ; the other wagon's ready
    # state is tracked in GameState.ghost_ready with a small random delay
    # simulating the other driver's acknowledgement.
    ready: bool = False
    # Cached values
    tension_dan: float = 0.0
    power_kw: float = 0.0
    # Smoothed display values (EMA τ ≈ 0.3 s) to avoid flicker
    tension_dan_disp: float = 0.0
    power_kw_disp: float = 0.0
    jerk_sum: float = 0.0       # integrated jerk for comfort score
    autopilot: bool = True      # on by default; press A to toggle
    # Drum-mounted parking (maintenance) brake — engaged at start of
    # every trip and whenever the driver pulls the emergency. It
    # releases automatically when the trip starts (buzzer ends) or when
    # the emergency brake is released while stopped.
    maint_brake: bool = True

    @property
    def pax(self) -> int:
        return self.pax_car1 + self.pax_car2

    @property
    def mass_kg(self) -> float:
        return TRAIN_EMPTY_KG + self.pax * PAX_KG


@dataclass
class Event:
    key: str
    message_en: str
    message_fr: str
    severity: str = "info"      # info | warn | alarm
    timestamp: float = 0.0


@dataclass
class GameState:
    mode: int = MODE_TITLE
    lang: str = LANG
    pilot: str = "Pilote"
    train: Train = field(default_factory=Train)
    # Opposing train (counterweight — bound by cable, moves symmetrically)
    ghost_s: float = LENGTH     # starts at top, comes down
    ghost_pax: int = 0          # passengers in the counterweight train
    trip_time: float = 0.0
    trip_started: bool = False
    # Departure buzzer countdown: sounds for 6.5 s (upper) or 8 s (lower)
    # (includes 1.5 s pre-ambient fade-in). While > 0, train must NOT move.
    departure_buzzer_remaining: float = 0.0
    # Departure protocol : ghost (opposite wagon) auto-confirms ready
    # after a short random delay simulating the other driver's response.
    ghost_ready: bool = False
    ghost_ready_timer: float = 0.0
    ghost_ready_delay: float = 0.0
    score_time: float = 0.0
    score_comfort: float = 100.0
    score_energy: float = 0.0
    events: list[Event] = field(default_factory=list)
    event_cooldown: float = 0.0
    run_mode: str = "normal"    # normal | challenge | panne
    panne_active: bool = False
    panne_kind: str = ""
    finished: bool = False
    rebound_timer: float = 0.0  # cable elasticity rebound (after arrival)
    best_time: float | None = None
    # Trip direction selection from the title screen.
    # direction = +1 (Val Claret → Glacier, climb) or -1 (Glacier → Val Claret).
    # train_choice selects which cabin (1 or 2) the player drives — purely
    # a label + colour cue since both are mechanically identical.
    selected_direction: int = +1
    selected_train: int = 1
    vigilance_enabled: bool = False  # dead-man vigilance off by default


class Physics:
    """Balanced counterweight model for the Perce-Neige funicular.

    Both trains are bound to the same cable so they move symmetrically :
    when the main train goes up by ds, the ghost train goes down by ds.
    Net gravity along slope is proportional to the mass *imbalance* between
    the two trains (minus cable friction). Player-controlled throttle is
    soft-capped so the resulting motor-induced acceleration never exceeds
    the operational programmed rate (~1 m/s²) — this is how the real
    Von Roll regulator behaves : a programmed trapezoidal velocity profile,
    not a raw throttle.
    """

    def __init__(self, state: GameState) -> None:
        self.state = state

    def step(self, dt: float) -> None:
        st = self.state
        tr = st.train
        if st.mode != MODE_RUN:
            return

        # Both trains on the cable. "Main" train is the one the player drives
        # (goes up this trip). Ghost mirrors it downward.
        m_up = tr.mass_kg
        m_down = TRAIN_EMPTY_KG + st.ghost_pax * PAX_KG
        m_total = m_up + m_down
        # Mass imbalance felt on the cable
        dm = m_up - m_down

        # Slope at the main train's position — the ghost train is at (L - s)
        # but for simplicity we take the local slope of the up train ; in a
        # balanced cable system this is slightly asymmetric but visually fine.
        g_slope = gradient_at(tr.s)
        theta = math.atan(g_slope)
        sint = math.sin(theta)
        cost = math.cos(theta)

        # Single hard speed limit — the real Perce-Neige passes the loop
        # at full 12 m/s, the loop is just a widening of the tunnel.
        v_limit = V_MAX

        # --- Speed command regulator ---------------------------------------
        # The driver sets a speed setpoint (speed_cmd, 0..1 = 0..V_MAX).
        # The regulator computes the actual motor throttle to track it,
        # respecting the station-approach envelope (creep zone + programmed
        # deceleration) so the train always stops cleanly at STOP_S.
        # Autopilot no longer forces the setpoint to 100 %. The driver
        # is always responsible for dialing in the speed command — the
        # regulator takes care of smooth acceleration, station approach
        # and creep-zone deceleration regardless of the autopilot flag.
        self._regulator(tr, dt)

        # --- Motor force ----------------------------------------------------
        # Physical caps only : stall torque and power envelope. The
        # comfort accel cap (A_MAX_REG) is applied AFTER summing all
        # forces so the motor can overcome gravity at steep gradients
        # and the train can actually reach V_MAX on the cruise section.
        v_eff = max(abs(tr.v), 0.8)
        f_motor_power_cap = P_MAX / v_eff             # P = F v
        f_motor_max = min(F_STALL, f_motor_power_cap)
        f_motor = tr.throttle * f_motor_max * tr.direction

        # Don't pump power if already at limit.
        if tr.v * tr.direction >= v_limit and f_motor * tr.direction > 0:
            f_motor = 0.0

        # Door interlock : no traction while the doors are physically open.
        # Real Perce-Neige : the drive contactor is wired to the door-closed
        # relay, the driver can command speed but nothing moves until the
        # leaves are shut. The parking brake is applied further down so the
        # train can't drift backwards under the gravity imbalance.
        if tr.doors_open:
            f_motor = 0.0

        # --- Gravity imbalance ---------------------------------------------
        # Net gravity along +s on the main train, counted in the +s
        # direction (up the slope). The ghost at (L - s) contributes via
        # the cable : its weight along its own downhill pulls the cable,
        # which on the main side becomes a +s force. Result :
        #     f_grav_s = -(m_main - m_ghost) * g * sin = -dm * g * sin
        # This sign is in absolute +s, independent of which direction
        # the main train happens to be travelling — gravity doesn't care.
        f_grav_net = -dm * G * sint

        # --- Rolling friction (both trains) ---------------------------------
        f_roll_mag = MU_ROLL * m_total * G * cost
        f_roll = -math.copysign(f_roll_mag, tr.v) if abs(tr.v) > 0.05 else 0.0

        # --- Brakes ---------------------------------------------------------
        # Emergency brake ramps over ~0.4 s so it's brutal but not an
        # instantaneous jerk step (real rail brakes engage mechanically
        # but still through a pneumatic/spring release delay).
        if tr.emergency:
            tr.emergency_ramp = min(
                1.0, tr.emergency_ramp + A_BRAKE_EMERG_RAMP * dt
            )
        else:
            tr.emergency_ramp = max(
                0.0, tr.emergency_ramp - A_BRAKE_EMERG_RAMP * dt
            )
        a_brk = 0.0
        if tr.emergency_ramp > 0.0:
            a_brk = tr.emergency_ramp * A_BRAKE_EMERGENCY
        elif tr.brake > 0:
            a_brk = tr.brake * A_BRAKE_NORMAL
        f_brake = -math.copysign(a_brk * m_total, tr.v) if abs(tr.v) > 0.05 else 0.0

        # Sum and integrate on the total cable-bound mass
        net = f_motor + f_grav_net + f_roll + f_brake
        a = net / m_total

        # Comfort accel cap : clamp motor-driven acceleration (never reduce
        # brake decel). Active only when the driver isn't asking for an
        # emergency stop. Uses a soft-start profile so the train pulls out
        # gently from standstill and ramps to full A_MAX_REG progressively,
        # matching the Von Roll S-curve launch logic.
        if not tr.emergency and tr.brake < 0.05:
            v_abs = abs(tr.v)
            soft_cap = A_START + (A_MAX_REG - A_START) * min(
                1.0, v_abs / V_SOFT_RAMP
            )
            if a > soft_cap:
                a = soft_cap
            elif a < -soft_cap:
                a = -soft_cap

        # If brakes kill the last sliver of motion, snap to zero.
        if a_brk > 0 and abs(tr.v) < 0.2:
            tr.v = 0.0
            a = 0.0

        # Integrate — tr.v is SIGNED in the +s direction. Going up the
        # slope, v > 0. Going down, v < 0. tr.direction is ±1 and tells
        # the regulator / motor what sign to push the throttle force in.
        new_v = tr.v + a * dt
        # Cap |v| at v_limit in the travel direction (coasting past is
        # fine — the motor is off — but we still don't let the physics
        # blow up if something goes wrong).
        if new_v * tr.direction > v_limit and f_motor == 0:
            new_v = v_limit * tr.direction
        if new_v * tr.direction < -v_limit:
            new_v = -v_limit * tr.direction
        tr.s += ((tr.v + new_v) / 2.0) * dt
        tr.v = new_v
        # Train centre clamped between station stop points. When hitting a
        # terminus with residual velocity (regulator hasn't fully killed
        # motion yet), snap v to 0 so the train doesn't "grind" against
        # the stop while reporting a stale speed readout.
        if tr.s >= STOP_S:
            tr.s = STOP_S
            if tr.v > 0:
                tr.v = 0.0
                a = 0.0
        elif tr.s <= START_S:
            tr.s = START_S
            if tr.v < 0:
                tr.v = 0.0
                a = 0.0
        # Parking (drum / maintenance) brake. The real funicular has a
        # mechanical drum brake on the bull wheel that holds the train
        # absolutely still when engaged — this is what makes the cabin
        # rock-solid on the platform with the doors open. It engages :
        #   - automatically whenever the doors are open (station stop)
        #   - alongside the emergency brake (so the train can't drift
        #     if the driver just stamped the emergency button)
        #   - on demand, tracked via tr.maint_brake
        # It releases automatically the instant trip_started flips True
        # (motors take the load) OR when the driver clears the emergency
        # brake while the train is stationary.
        parked = tr.maint_brake or tr.doors_open
        if parked:
            tr.v = 0.0
            a = 0.0

        # Comfort / jerk
        jerk = abs(a - tr.a) / max(dt, 1e-3)
        tr.jerk_sum += jerk * dt
        tr.a = a

        # Cable tension (N) — proper funicular model.
        # On a counterweighted funicular the drive cable between the top
        # bull-wheel and the HEAVIER (usually ascending, loaded) train is
        # where maximum tension develops. That cable segment must carry
        # the full weight component of the heavy side along the slope
        # (gravity), plus rolling friction on that side, plus the motor's
        # pulling force when it is accelerating the train in the travel
        # direction. Deceleration via the service brake (train wheels) or
        # natural gravity coast does NOT add cable tension — the brake
        # absorbs the deceleration force directly on the rail, so the
        # cable "unloads" rather than loads.
        #
        # Reference : Fatzer 52 mm, nominal 22 500 daN on Perce-Neige,
        # breaking 191 200 daN. A 58 t fully loaded train at 30 % grade
        # yields ~16 500 daN, well within the nominal envelope.
        m_heavy = max(m_up, m_down)
        # Acceleration in the travel direction : +: accelerating,
        # -: decelerating (motor easing off or braking).
        a_travel = a * tr.direction
        t_gravity = m_heavy * G * sint
        t_friction = MU_ROLL * m_heavy * G * cost
        # Only add inertia when the motor is pulling harder than gravity
        # (accelerating in the travel direction). During deceleration or
        # braking the cable is NOT the force path, so tension does not
        # rise — the wheel brake or natural gravity coast absorb it.
        t_inertia = max(0.0, m_heavy * a_travel)
        tension_n = t_gravity + t_friction + t_inertia
        tr.tension_dan = tension_n / 10.0
        tr.power_kw = max(0.0, (f_motor * tr.v) / 1000.0)
        # Smoothed display values — EMA with τ ≈ 0.3 s avoids flicker
        alpha = min(1.0, dt / 0.3)
        tr.tension_dan_disp += (tr.tension_dan - tr.tension_dan_disp) * alpha
        tr.power_kw_disp += (tr.power_kw - tr.power_kw_disp) * alpha

        # Ghost train position : symmetric on the cable.
        # Cable elasticity rebound : damped oscillation after stopping.
        # Measured from arrival video — the wagon oscillates ~4 cm with
        # period ≈ 3.9 s and damps out over 3-4 cycles (ζ ≈ 0.05).
        base_ghost_s = LENGTH - tr.s
        if st.finished:
            st.rebound_timer += dt
            t_r = st.rebound_timer
            rebound = (REBOUND_AMP
                       * math.exp(-REBOUND_ZETA * REBOUND_OMEGA * t_r)
                       * math.sin(REBOUND_OMEGA * t_r))
            if tr.direction > 0:
                # Main arrived at top → ghost at bottom oscillates
                base_ghost_s += rebound
            else:
                # Main arrived at bottom → main train oscillates
                tr.s += rebound * 0.3  # attenuated visual effect
        st.ghost_s = max(START_S, min(LENGTH - START_S, base_ghost_s))

        if st.trip_started:
            st.trip_time += dt

        st.score_energy += tr.power_kw * dt / 3600.0
        st.score_comfort = max(0.0, 100.0 - tr.jerk_sum * 0.015)

        # Arrival detection : direction-aware.
        if not st.finished and abs(tr.v) < 0.4:
            arrived = False
            if tr.direction > 0 and tr.s >= STOP_S - 0.3:
                st.finished = True
                arrived = True
                st.score_time = st.trip_time
                add_event(
                    st, "arrive",
                    "Arrived at Grande Motte glacier — 3032 m",
                    "Arrivée à la Grande Motte — 3032 m", "info",
                )
            elif tr.direction < 0 and tr.s <= START_S + 0.3:
                st.finished = True
                arrived = True
                st.score_time = st.trip_time
                add_event(
                    st, "arrive",
                    "Arrived at Val Claret — 2111 m",
                    "Arrivée à Val Claret — 2111 m", "info",
                )
            # On arrival, relax the speed command and release the
            # service/emergency brakes so the driver can command door
            # opening (D) manually, just like before departure.
            if arrived:
                tr.speed_cmd = 0.0
                tr.throttle = 0.0
                tr.brake = 0.0
                tr.emergency = False

    def _regulator(self, tr: Train, dt: float) -> None:
        """Speed-command regulator — always active, direction-aware.

        The driver sets `tr.speed_cmd` (0..1 = 0..V_MAX, magnitude in
        the travel direction). Internally we work in *travel-direction
        magnitude* (v_t = tr.v * tr.direction, always positive while
        moving normally) so the same logic handles both the climbing
        and the descending trip.

        Arrival envelope is built around the gravity-natural coast decel
        (A_NATURAL_UP, ~0.45 m/s²) on the climbing trip — this matches
        the real Perce-Neige drivers who simply cut throttle a few
        hundred metres before the platform and let gravity do the job.
        On the descending trip we fall back to A_TARGET since gravity
        accelerates a loaded main and the envelope must actively brake.
        """
        # Hard stop override : driver emergency-braking stays in control.
        if tr.emergency:
            return

        # Electric stop (latched service-stop button) : kill motor, apply
        # a steady service brake until the driver releases the button.
        # No rail brakes — the train coasts to a halt smoothly.
        if tr.electric_stop or tr.dead_man_fault:
            tr.speed_cmd = 0.0
            tr.throttle = 0.0
            target = 0.35 if abs(tr.v) > 0.5 else 0.5
            db = max(-4.0 * dt, min(4.0 * dt, target - tr.brake))
            tr.brake = max(0.0, min(1.0, tr.brake + db))
            return

        # Distance remaining along travel direction (always positive).
        if tr.direction > 0:
            dist_to_stop = max(0.0, STOP_S - tr.s)
        else:
            dist_to_stop = max(0.0, tr.s - START_S)

        # Travel-direction velocity magnitude.
        v_travel = tr.v * tr.direction

        # --- Gravity-along-travel sign --------------------------------------
        # We need to know whether gravity currently HELPS or OPPOSES the
        # travel direction. On a classic ascent (heavy main climbing),
        # gravity opposes and the motor has to pull. On a descent with a
        # heavy main (typical after a mid-tunnel reversal), gravity
        # already accelerates the train downhill and the motor must stay
        # OFF — the brake is what holds the speed.
        m_main_r = tr.mass_kg
        m_ghost_r = TRAIN_EMPTY_KG + self.state.ghost_pax * PAX_KG
        m_total_r = m_main_r + m_ghost_r
        dm_r = m_main_r - m_ghost_r
        g_slope_r = gradient_at(tr.s)
        theta_r = math.atan(g_slope_r)
        # f_grav_s : net +s force on main from gravity imbalance.
        f_grav_s = -dm_r * G * math.sin(theta_r)
        # Projected onto travel direction : >0 means gravity accelerates
        # the train in the direction it's trying to go.
        f_grav_travel = f_grav_s * tr.direction
        gravity_helps = f_grav_travel > 200.0   # N threshold

        # --- Speed envelope : adaptive to whether gravity helps or not --
        d_to_creep = max(0.0, dist_to_stop - CREEP_DIST)
        if gravity_helps:
            # Gravity is pushing us toward the platform (heavy main
            # descending — most commonly after a mid-tunnel reversal).
            # Envelope must actively brake : use a conservative decel so
            # the train actually slows down before the creep zone.
            a_env = A_TARGET
        elif tr.direction > 0:
            # Classic climb — pure coast, gravity opposes travel.
            a_env = A_NATURAL_UP
        else:
            # Classic descent with empty main + heavy ghost : gravity
            # opposes travel too (ghost counterweight pulls main up),
            # so a gentle coast envelope suffices.
            a_env = A_NATURAL_UP
        v_envelope = math.sqrt(CREEP_V * CREEP_V + 2.0 * a_env * d_to_creep)

        driver_target = tr.speed_cmd * V_MAX
        target_v = min(driver_target, v_envelope)
        envelope_active = v_envelope < driver_target - 0.05

        # Creep zone : last CREEP_DIST metres crawl at CREEP_V
        if dist_to_stop < CREEP_DIST:
            target_v = CREEP_V
            envelope_active = True
        # Final 50 cm : full stop
        if dist_to_stop < 0.5:
            target_v = 0.0
            envelope_active = True

        # --- Unified control law ------------------------------------------
        # Single continuous P-controller (no branch-switching) so the
        # brake and throttle commands vary smoothly with the tracking
        # error. A feed-forward term cancels the steady-state gravity
        # + rolling-friction load at the current speed target, so the
        # proportional term only has to fight transient error — no
        # more "bang-bang" oscillation between the heavy-brake branch
        # and the hold branch during a gravity-assisted descent.
        err = target_v - v_travel
        slew = 1.5 * dt          # up to 150 %/s throttle rate of change
        v_eff = max(abs(tr.v), 0.8)
        f_motor_max = min(F_STALL, P_MAX / v_eff)

        # Feed-forward : force along TRAVEL direction required to hold
        # the train at target_v. Positive → motor must pull ; negative
        # → brake must resist gravity.
        f_ff = (-f_grav_travel
                + MU_ROLL * m_total_r * G * math.cos(theta_r))
        ff_throttle = max(0.0, f_ff) / max(f_motor_max, 1.0)
        ff_brake = max(0.0, -f_ff) / (A_BRAKE_NORMAL * m_total_r)

        if target_v < 0.01 and v_travel < 0.4:
            # Arrived — kill motor, hold with brake
            demand_throttle = 0.0
            demand_brake = 0.5
        else:
            # P-controller around the feed-forward bias.
            # err > 0 : need more forward force (more motor / less brake)
            # err < 0 : need less forward force (less motor / more brake)
            k_p = 0.18  # brake/throttle per m/s error
            demand_throttle = max(0.0, min(1.0, ff_throttle + err * k_p))
            demand_brake = max(0.0, min(1.0, ff_brake - err * k_p))
            # Resolve conflict : if both are non-zero (shouldn't happen
            # algebraically but keep a safety net) the larger wins and
            # the other collapses to zero so the control authority isn't
            # wasted fighting itself.
            if demand_throttle > 0.0 and demand_brake > 0.0:
                if demand_throttle > demand_brake:
                    demand_throttle -= demand_brake
                    demand_brake = 0.0
                else:
                    demand_brake -= demand_throttle
                    demand_throttle = 0.0

        # Throttle slew — unchanged, smooth motor ramp.
        dth = max(-slew, min(slew, demand_throttle - tr.throttle))
        tr.throttle = max(0.0, min(1.0, tr.throttle + dth))
        # Brake slew — slightly slower than before (2.5/s vs 4/s) to
        # iron out any residual jitter in the displayed % value, still
        # fast enough for a 2.5 m/s² service brake to respond cleanly.
        db = max(-2.5 * dt, min(2.5 * dt, demand_brake - tr.brake))
        tr.brake = max(0.0, min(1.0, tr.brake + db))


# ---------------------------------------------------------------------------
# Events and random incidents
# ---------------------------------------------------------------------------

def add_event(st: GameState, key: str, en: str, fr: str, severity: str = "info") -> None:
    ev = Event(key=key, message_en=en, message_fr=fr, severity=severity,
               timestamp=st.trip_time)
    st.events.append(ev)
    if len(st.events) > 40:
        st.events.pop(0)


def maybe_random_event(st: GameState, dt: float) -> None:
    if st.run_mode != "panne":
        return
    st.event_cooldown -= dt
    if st.event_cooldown > 0:
        return
    if random.random() > 0.0025:   # ~1 chance / 400 ticks at 60 Hz
        return
    st.event_cooldown = 8.0
    tr = st.train
    kind = random.choice(["tension", "door", "thermal", "fire", "ice"])
    st.panne_active = True
    st.panne_kind = kind
    if kind == "tension":
        add_event(st, "tension",
                  "Cable tension spike ! reduce throttle.",
                  "Pic de tension câble ! réduire la puissance.", "warn")
        tr.tension_dan += 6000
    elif kind == "door":
        add_event(st, "door",
                  "Door sensor fault — stop at next station.",
                  "Défaut capteur porte — arrêt station suivante.", "warn")
    elif kind == "thermal":
        add_event(st, "thermal",
                  "Motor over-temperature — power reduced.",
                  "Surchauffe moteur — puissance réduite.", "warn")
    elif kind == "fire":
        add_event(st, "fire",
                  "Smoke detected in tunnel ! EMERGENCY STOP.",
                  "Fumée dans le tunnel ! ARRÊT D'URGENCE.", "alarm")
        tr.emergency = True
    elif kind == "ice":
        add_event(st, "ice",
                  "Ice on upper rails — speed reduced.",
                  "Givre sur voie haute — vitesse réduite.", "warn")


# ---------------------------------------------------------------------------
# HUD and rendering
# ---------------------------------------------------------------------------

COLOR_BG_TOP = QColor(12, 20, 34)
COLOR_BG_BOT = QColor(34, 48, 72)
COLOR_MOUNT_1 = QColor(58, 50, 45)
COLOR_MOUNT_2 = QColor(86, 76, 68)
COLOR_GLACIER = QColor(232, 240, 252)
COLOR_TUNNEL = QColor(24, 24, 30)
COLOR_TUNNEL_WALL = QColor(72, 72, 86)
COLOR_CABIN = QColor(255, 210, 60)
COLOR_CABIN_EDGE = QColor(120, 80, 0)
COLOR_GHOST = QColor(180, 120, 60)
COLOR_HUD_BG = QColor(20, 24, 32, 230)
COLOR_HUD_BORDER = QColor(80, 130, 180)
COLOR_TEXT = QColor(220, 230, 245)
COLOR_TEXT_DIM = QColor(140, 160, 180)
COLOR_GOOD = QColor(80, 220, 120)
COLOR_WARN = QColor(240, 180, 40)
COLOR_ALARM = QColor(240, 80, 80)
COLOR_NEEDLE = QColor(255, 230, 80)


# ---------------------------------------------------------------------------
# Sound system — plays the real Perce-Neige on-board announcements
# ---------------------------------------------------------------------------

def _generate_ambient_wavs(dest_dir: Path) -> dict[str, Path]:
    """Create small procedural loops used for the moving-train ambient.

    Two short WAVs are synthesised on first launch (tunnel rumble + motor
    hum). They are cached next to the venv so we don't rewrite them on
    every start. Pure-Python, no external deps — uses `wave` + `struct`.
    """
    import math as _m
    import random as _r
    import struct
    import wave

    dest_dir.mkdir(parents=True, exist_ok=True)
    out: dict[str, Path] = {}
    sample_rate = 44100
    # ---- Tunnel rumble : 2 s loop of filtered pink-ish noise + low sine.
    rumble = dest_dir / "ambient_rumble.wav"
    if not rumble.exists():
        dur = 2.0
        n = int(sample_rate * dur)
        data = bytearray()
        prev = 0.0
        for i in range(n):
            white = _r.uniform(-1.0, 1.0)
            # one-pole low-pass for brown-ish noise
            prev = prev * 0.985 + white * 0.015
            bass = _m.sin(2 * _m.pi * 42.0 * i / sample_rate) * 0.35
            mid = _m.sin(2 * _m.pi * 110.0 * i / sample_rate) * 0.1
            # Smooth fade at the boundaries so the loop is seamless.
            env = 1.0
            fade = int(sample_rate * 0.05)
            if i < fade:
                env = i / fade
            elif i > n - fade:
                env = (n - i) / fade
            s = (prev * 6.0 + bass + mid) * env * 0.55
            s = max(-1.0, min(1.0, s))
            data += struct.pack("<h", int(s * 32767))
        with wave.open(str(rumble), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            w.writeframes(bytes(data))
    out["rumble"] = rumble
    # ---- Motor hum : 1 s loop tuned to the real 197 Hz cruise fundamental
    # (calibrated from spectral analysis of YouTube FUNI284, cruise phase
    # t=120-300 s, bandpass 60-300 Hz centroid = 196.9 Hz at 12 m/s).
    motor = dest_dir / "ambient_motor.wav"
    if not motor.exists():
        dur = 1.0
        n = int(sample_rate * dur)
        data = bytearray()
        f0 = 197.0     # real cruise fundamental
        for i in range(n):
            t = i / sample_rate
            # Stacked harmonics for a DC-motor whine (real fundamental)
            s = (
                _m.sin(2 * _m.pi * (f0 * 0.5) * t) * 0.15
                + _m.sin(2 * _m.pi * f0 * t) * 0.30
                + _m.sin(2 * _m.pi * (f0 * 2) * t) * 0.18
                + _m.sin(2 * _m.pi * (f0 * 3) * t) * 0.06
            )
            env = 1.0
            fade = int(sample_rate * 0.03)
            if i < fade:
                env = i / fade
            elif i > n - fade:
                env = (n - i) / fade
            s *= env * 0.5
            s = max(-1.0, min(1.0, s))
            data += struct.pack("<h", int(s * 32767))
        with wave.open(str(motor), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            w.writeframes(bytes(data))
    out["motor"] = motor
    # ---- Departure buzzer : ~12 s tone at 1077 Hz + sub-harmonic 556 Hz.
    # Precisely measured from interior cabin audio (video A_oxDO8jtXo,
    # FFT at 0.5 Hz resolution): fundamental 1077 Hz, sub-harmonic 556 Hz
    # (amp 0.52), harmonics at 2149/3252/4281 Hz.  AM pulsation at 1.88 Hz.
    # Duration measured 12.3 s (t=36.0→48.3), onset/offset abrupt (~50 ms).
    buzzer = dest_dir / "departure_buzzer.wav"
    if not buzzer.exists():
        dur = 12.3
        n = int(sample_rate * dur)
        data = bytearray()
        freq = 1077.0
        for i in range(n):
            t = i / sample_rate
            # Full harmonic content matching interior cabin recording
            s = (
                _m.sin(2 * _m.pi * 556.0 * t) * 0.22     # sub-harmonic
                + _m.sin(2 * _m.pi * freq * t) * 0.50     # fundamental
                + _m.sin(2 * _m.pi * 2149.0 * t) * 0.09   # 2nd harmonic
                + _m.sin(2 * _m.pi * 3252.0 * t) * 0.06   # 3rd harmonic
                + _m.sin(2 * _m.pi * 4281.0 * t) * 0.05   # 4th harmonic
            )
            # Envelope: abrupt 50 ms attack/release
            env = 1.0
            att = int(sample_rate * 0.05)
            rel = int(sample_rate * 0.05)
            if i < att:
                env = i / att
            elif i > n - rel:
                env = (n - i) / rel
            # AM pulsation at 1.88 Hz (measured from audio modulation)
            env *= 1.0 - 0.12 * _m.sin(2 * _m.pi * 1.88 * t)
            s *= env * 0.40
            s = max(-1.0, min(1.0, s))
            data += struct.pack("<h", int(s * 32767))
        with wave.open(str(buzzer), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            w.writeframes(bytes(data))
    out["buzzer"] = buzzer
    # Horn WAV (generated procedurally if missing)
    horn = dest_dir / "horn.wav"
    if not horn.exists():
        dur_h = 0.8
        n_h = int(sample_rate * dur_h)
        data_h = bytearray()
        f1_h, f2_h = 280.0, 350.0
        for i in range(n_h):
            t_h = i / sample_rate
            s_h = (_m.sin(2 * _m.pi * f1_h * t_h) * 0.40
                   + _m.sin(2 * _m.pi * f2_h * t_h) * 0.35
                   + _m.sin(2 * _m.pi * f1_h * 2 * t_h) * 0.10
                   + _m.sin(2 * _m.pi * f2_h * 2 * t_h) * 0.08)
            env_h = 1.0
            att_h = int(sample_rate * 0.02)
            rel_h = int(sample_rate * 0.02)
            if i < att_h:
                env_h = i / att_h
            elif i > n_h - rel_h:
                env_h = (n_h - i) / rel_h
            s_h *= env_h * 0.65
            s_h = max(-1.0, min(1.0, s_h))
            data_h += struct.pack("<h", int(s_h * 32767))
        with wave.open(str(horn), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sample_rate)
            w.writeframes(bytes(data_h))
    out["horn"] = horn
    # Real audio extracted from video (if available)
    ambient_real = dest_dir / "ambient_real.wav"
    if ambient_real.exists():
        out["ambient_real"] = ambient_real
    buzzer_real = dest_dir / "departure_buzzer_real.wav"
    if buzzer_real.exists():
        out["buzzer_real"] = buzzer_real       # upper station (industrial)
    buzzer_bas = dest_dir / "departure_buzzer_bas.wav"
    if buzzer_bas.exists():
        out["buzzer_bas"] = buzzer_bas         # lower station (bell/ring)
    dep_amb = dest_dir / "departure_ambient.wav"
    if dep_amb.exists():
        out["departure_ambient"] = dep_amb     # interior ramp-up (both stations)
    return out


class SoundSystem:
    """Real on-board announcements recorded from the actual funicular.

    The `sons/Funiculaire perce neige/` folder contains numbered mp3 files,
    grouped by topic and by language (FR, ANG=EN, ITAL, ALLEM, ESP).
    Each announcement group is a contiguous range of 5 files ; the first
    is French, the second English, etc. Some groups are shorter (e.g. 01
    doors-closing is FR only, 11 is the welcome jingle).
    """

    LANG_OFFSET = {"fr": 0, "en": 1, "it": 2, "de": 3, "es": 4}

    # (start, end) inclusive file numbers for each announcement key.
    GROUPS: dict[str, tuple[int, int]] = {
        "doors_close":     (1, 1),     # 01 FR only
        "exit_left":       (6, 10),    # 06 FR .. 10 ESP (08 ITAL missing)
        "welcome":         (11, 11),   # 11 FR only — long zone message
        "minor_incident":  (12, 16),   # 12-16 FR/EN/IT/DE/ES
        "tech_incident":   (17, 21),
        "long_repair":     (22, 26),
        "stop_10min":      (27, 31),
        "restart":         (32, 36),
        "evac":            (37, 41),
        "exit_upstream":   (42, 46),
        "exit_downstream": (47, 51),
        "evac_car2":       (52, 56),
        "dim_light":       (57, 61),
        "return_station":  (62, 66),
        "brake_noise":     (67, 71),
    }

    def __init__(self, project_dir: Path) -> None:
        self.project_dir = project_dir
        self.sons_dir = project_dir / "sons" / "Funiculaire perce neige"
        self.enabled = _QTMULTIMEDIA_OK and self.sons_dir.exists()
        self.muted = False
        self._files_by_num: dict[int, Path] = {}
        self._queue: list[Path] = []
        self._cooldowns: dict[str, float] = {}
        self._player = None
        self._audio = None
        self._horn_player = None
        self._horn_audio = None
        # Generate procedural ambient/buzzer WAVs (cached in temp dir)
        wav_dir = Path(os.environ.get("TEMP", "/tmp")) / "perce_neige_wav"
        self._ambient_wavs = _generate_ambient_wavs(wav_dir)
        if not self.enabled:
            return
        for f in sorted(self.sons_dir.iterdir()):
            if f.suffix.lower() != ".mp3":
                continue
            head = f.name.split(" ", 1)[0]
            try:
                self._files_by_num[int(head)] = f
            except ValueError:
                pass
        # Separate players for parallel audio:
        # _player       → announcements (doors_close, welcome, etc.)
        # _fx_player    → buzzer (plays alongside announcements)
        # _amb_player   → ambient loop (motor hum / rumble while moving)
        try:
            self._player = QMediaPlayer()
            self._audio = QAudioOutput()
            self._audio.setVolume(0.85)
            self._player.setAudioOutput(self._audio)
            self._player.mediaStatusChanged.connect(self._on_status)
            # FX player for buzzer
            self._fx_player = QMediaPlayer()
            self._fx_audio = QAudioOutput()
            self._fx_audio.setVolume(0.70)
            self._fx_player.setAudioOutput(self._fx_audio)
            # Horn player (dedicated — loops while key held)
            self._horn_player = QMediaPlayer()
            self._horn_audio = QAudioOutput()
            self._horn_audio.setVolume(0.80)
            self._horn_player.setAudioOutput(self._horn_audio)
            self._horn_player.setLoops(QMediaPlayer.Loops.Infinite)
            # Pre-load horn source so play() is instant on key press
            horn_path = self._ambient_wavs.get("horn")
            if horn_path and horn_path.exists():
                self._horn_player.setSource(
                    QUrl.fromLocalFile(str(horn_path)))
            # Ambient player (loops motor hum while train moves)
            self._amb_player = QMediaPlayer()
            self._amb_audio = QAudioOutput()
            self._amb_audio.setVolume(0.0)  # faded in/out dynamically
            self._amb_player.setAudioOutput(self._amb_audio)
            self._amb_player.setLoops(QMediaPlayer.Loops.Infinite)
            self._amb_playing = False
            self._amb_vol_target = 0.0
        except Exception:
            self.enabled = False

    # ----- public ----------------------------------------------------------

    def play(self, group: str, lang: str = "fr", cooldown: float = 30.0) -> None:
        """Queue an announcement. Per-group cooldown avoids spam."""
        if not self.enabled or self.muted:
            return
        if self._cooldowns.get(group, 0.0) > 0:
            return
        f = self._pick(group, lang)
        if f is None:
            return
        self._cooldowns[group] = cooldown
        self._queue.append(f)
        if self._player.playbackState() != QMediaPlayer.PlaybackState.PlayingState:
            self._play_next()

    def play_bilingual(self, group: str, cooldown: float = 30.0) -> None:
        """Queue FR then EN versions back to back, like the real train."""
        if not self.enabled or self.muted:
            return
        if self._cooldowns.get(group, 0.0) > 0:
            return
        fr = self._pick(group, "fr")
        en = self._pick(group, "en")
        if fr is None and en is None:
            return
        self._cooldowns[group] = cooldown
        if fr is not None:
            self._queue.append(fr)
        if en is not None and en != fr:
            self._queue.append(en)
        if self._player.playbackState() != QMediaPlayer.PlaybackState.PlayingState:
            self._play_next()

    def play_buzzer(self, upper_station: bool = False) -> None:
        """Play the departure buzzer/bell.

        *upper_station*: True → industrial buzzer (gare du haut / Barrage),
                         False → bell/ring (gare du bas / Lac).
        Falls back to the synthesized buzzer if real extracts are missing.
        """
        if not self.enabled or self.muted:
            return
        if upper_station:
            path = self._ambient_wavs.get("buzzer_real")
        else:
            path = self._ambient_wavs.get("buzzer_bas")
        # Fallback chain: real → synthesized
        if path is None or not path.exists():
            path = self._ambient_wavs.get("buzzer")
        if path is None or not path.exists():
            return
        self._fx_player.setSource(QUrl.fromLocalFile(str(path)))
        self._fx_player.play()

    def play_departure_ambient(self) -> None:
        """Play the interior departure ramp-up sound (single shot).

        Played right after the buzzer ends, bridges the gap between
        the buzzer and the cruise ambient loop.  Same sound for both
        stations (real cabin interior recording).
        """
        if not self.enabled or self.muted:
            return
        path = self._ambient_wavs.get("departure_ambient")
        if path is None or not path.exists():
            return
        self._fx_player.setLoops(1)
        self._fx_player.setSource(QUrl.fromLocalFile(str(path)))
        self._fx_player.play()

    def start_horn(self) -> None:
        """Start playing the horn (looped while held)."""
        if not self.enabled or self.muted:
            return
        if self._horn_player is None:
            return
        # Source already pre-loaded at init; just play
        self._horn_player.play()

    def stop_horn(self) -> None:
        """Stop the horn sound."""
        if self._horn_player is not None:
            self._horn_player.stop()

    def stop_announcements(self) -> None:
        """Interrupt any announcement currently playing and clear the queue.

        Called when the driver triggers a new announcement manually (we
        don't want the new one to queue *behind* a previous one that's
        still chaining through its translations) or when Esc is pressed.
        """
        self._queue.clear()
        if self._player is not None:
            self._player.stop()

    def update_ambient(self, speed: float) -> None:
        """Fade real ambient sound in/out based on train speed."""
        if not self.enabled or self.muted:
            if self._amb_playing:
                self._amb_player.stop()
                self._amb_playing = False
            return
        # Target volume proportional to speed (silent at stop, max at V_MAX)
        v_norm = min(abs(speed) / 10.0, 1.0)
        self._amb_vol_target = v_norm * 0.35  # max 35% volume
        # Start looping ambient if not already
        if v_norm > 0.02 and not self._amb_playing:
            # Prefer real audio extracted from video
            real = self._ambient_wavs.get("ambient_real")
            path = real if (real and real.exists()) else self._ambient_wavs.get("rumble")
            if path and path.exists():
                self._amb_player.setSource(QUrl.fromLocalFile(str(path)))
                self._amb_player.play()
                self._amb_playing = True
        elif v_norm <= 0.01 and self._amb_playing:
            self._amb_player.stop()
            self._amb_playing = False
        # Smooth volume ramp
        cur = self._amb_audio.volume()
        diff = self._amb_vol_target - cur
        if abs(diff) > 0.005:
            self._amb_audio.setVolume(cur + diff * 0.15)

    def tick(self, dt: float) -> None:
        for k in list(self._cooldowns.keys()):
            self._cooldowns[k] = max(0.0, self._cooldowns[k] - dt)

    def toggle_mute(self) -> bool:
        self.muted = not self.muted
        if self.muted and self._player is not None:
            self._player.stop()
            self._fx_player.stop()
            self._horn_player.stop()
            self._amb_player.stop()
            self._amb_playing = False
            self._queue.clear()
        return self.muted

    def stop(self) -> None:
        self._queue.clear()
        if self._player is not None:
            self._player.stop()
            self._fx_player.stop()
            self._horn_player.stop()
            self._amb_player.stop()
            self._amb_playing = False

    def reset(self) -> None:
        self._queue.clear()
        self._cooldowns.clear()
        if self._player is not None:
            self._player.stop()
            self._fx_player.stop()
            self._horn_player.stop()
            self._amb_player.stop()
            self._amb_playing = False

    # ----- internals -------------------------------------------------------

    def _pick(self, group: str, lang: str) -> Path | None:
        rng = self.GROUPS.get(group)
        if rng is None:
            return None
        start, end = rng
        offset = self.LANG_OFFSET.get(lang, 0)
        # Try requested language first, then FR, then any file in range.
        for candidate in (start + offset, start, start + 1):
            if start <= candidate <= end and candidate in self._files_by_num:
                return self._files_by_num[candidate]
        for n in range(start, end + 1):
            if n in self._files_by_num:
                return self._files_by_num[n]
        return None

    def _play_next(self) -> None:
        if not self._queue or self._player is None:
            return
        nxt = self._queue.pop(0)
        self._player.setSource(QUrl.fromLocalFile(str(nxt)))
        self._player.play()

    def _on_status(self, status) -> None:
        if status == QMediaPlayer.MediaStatus.EndOfMedia:
            self._play_next()


# Key → (announcement group, EN label, FR label). Order matters for menu.
ANNOUNCEMENT_MENU: list[tuple[int, str, str, str, str]] = [
    (Qt.Key.Key_1, "doors_close",     "1", "Doors closing",            "Fermeture des portes"),
    (Qt.Key.Key_2, "welcome",         "2", "Zone boarding announcement", "Zone — annonce embarquement"),
    (Qt.Key.Key_3, "brake_noise",     "3", "Brake noise (normal)",     "Bruit des freins (normal)"),
    (Qt.Key.Key_4, "minor_incident",  "4", "Minor incident 5–10 min",  "Incident mineur 5–10 min"),
    (Qt.Key.Key_5, "tech_incident",   "5", "Technical incident",       "Incident technique"),
    (Qt.Key.Key_6, "long_repair",     "6", "Repairs extended",         "Rallongement des réparations"),
    (Qt.Key.Key_7, "stop_10min",      "7", "10 minute stop",           "Arrêt de 10 minutes"),
    (Qt.Key.Key_8, "restart",         "8", "Resuming service",         "Remise en route"),
    (Qt.Key.Key_9, "dim_light",       "9", "Lighting reduction",       "Diminution de l'éclairage"),
    (Qt.Key.Key_0, "return_station",  "0", "Return to station",        "Retour en gare"),
    (Qt.Key.Key_Q, "evac",            "Q", "Vehicle evacuation",       "Évacuation du véhicule"),
    (Qt.Key.Key_W, "evac_car2",       "W", "Second car evacuation",    "Évacuation 2e wagon"),
    (Qt.Key.Key_E, "exit_upstream",   "E", "Upstream exit — 1st car",  "Sortie amont — 1re voiture"),
    (Qt.Key.Key_T, "exit_downstream", "T", "Downstream exit — 1st car", "Sortie aval — 1re voiture"),
    (Qt.Key.Key_Y, "exit_left",       "Y", "Exit on the left",         "Sortie côté gauche"),
]


class GameWidget(QWidget):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.state = GameState()
        self.physics = Physics(self.state)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMinimumSize(1280, 900)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.timer.start(16)       # ~60 Hz
        self._last_time = 0.0
        self._frame_count = 0
        self._fps = 0.0
        self._fps_acc = 0.0
        self._show_help = True
        self._show_info = False
        self._board_animation = 0.0
        self._key_state: set[int] = set()
        # Mouse-held virtual keys — same semantics as _key_state. Used to
        # expose hold-type controls (speed cmd up/down, brake, horn,
        # emergency) to point-and-click users. Unioned with _key_state in
        # the polling loop and in emergency/horn handlers.
        self._mouse_hold: set[int] = set()
        # Clickable hit zones rebuilt every _draw_hud() frame. Each entry
        # is (rect, key_to_simulate, hold_flag). A click hit-tests this
        # list and dispatches the corresponding key press / release.
        self._hit_zones: list[tuple[QRectF, int, bool]] = []
        # Title-screen click zones — each entry is (rect, direction,
        # train_number). Populated by _draw_title_overlay and consumed
        # by mousePressEvent when st.mode == MODE_TITLE.
        self._title_zones: list[tuple[QRectF, int, int]] = []
        self._pulley_angle = 0.0          # radians — animated drive pulley
        self._cloud_offset = 0.0          # slow scroll for sky
        self._snowflakes: list[list[float]] = []   # [x, y, vy, size]
        for _ in range(60):
            self._snowflakes.append([
                random.uniform(0, 1280),
                random.uniform(0, 820),
                random.uniform(12, 30),
                random.uniform(1.0, 2.6),
            ])
        # Real on-board announcements
        self.sounds = SoundSystem(Path(__file__).resolve().parent)
        self._last_panne_kind: str = ""
        self._welcome_played = False
        self._arrival_played = False
        # Mid-tunnel stop tracking — drives the "remise en route"
        # announcement when the driver restarts from an unplanned stop.
        self._was_stopped_mid_tunnel = False
        self._mid_tunnel_stop_timer = 0.0
        self._show_annmenu = False       # F2 announcement console
        self._cabin_view = False         # F4 cabin/tunnel first-person view
        self._tunnel_scroll = 0.0        # accumulated tunnel texture offset
        self.new_trip(first=True)

    # ----- lifecycle -------------------------------------------------------

    def reverse_trip(self) -> None:
        """Flip the travel direction and re-arm the departure sequence in
        place — works both at a terminus (after arrival) AND mid-tunnel
        if the driver has brought the train to a stop and decides to go
        back the way they came. The real Perce-Neige has a dedicated
        "retour en gare" announcement for exactly this scenario.

        The train keeps its current slope position ``tr.s`` — no teleport.
        The driver must press READY (V) then START (Z) to set off again.
        """
        st = self.state
        tr = st.train
        tr.direction = -tr.direction
        st.selected_direction = tr.direction
        # Ghost mirrors main position on the cable.
        st.ghost_s = LENGTH - tr.s
        # Reset trip-state flags so the driver can re-run the ready /
        # buzzer / start sequence and head back. We deliberately KEEP
        # the current brake configuration (service brake, emergency
        # rail brake, drum parking brake) — if the driver stamped the
        # emergency before reversing, they must release it manually
        # before arming READY. The motor / ready state are zeroed.
        tr.v = 0.0
        tr.a = 0.0
        tr.speed_cmd = 1.0
        tr.throttle = 0.0
        tr.ready = False
        tr.dead_man_timer = 0.0
        tr.dead_man_fault = False
        st.ghost_ready = False
        st.ghost_ready_timer = 0.0
        st.ghost_ready_delay = 0.0
        st.trip_started = False
        st.trip_time = 0.0
        st.finished = False
        st.rebound_timer = 0.0
        st.departure_buzzer_remaining = 0.0
        self._welcome_played = False
        self._arrival_played = False
        self._was_stopped_mid_tunnel = False
        # Trigger the real "return to station" announcement over the
        # on-board PA — but only when reversing mid-tunnel (abnormal
        # situation). Reversing at a terminus is the normal turnaround
        # and silently flips the direction.
        self.sounds.stop_announcements()
        at_terminus = (tr.s <= START_S + 5.0) or (tr.s >= STOP_S - 5.0)
        if not at_terminus:
            self.sounds.play_bilingual("return_station", cooldown=5.0)
        dest_en = "Val Claret (2111 m)" if tr.direction < 0 else "Grande Motte (3032 m)"
        add_event(st, "reverse",
                  f"Reversing — return toward {dest_en}",
                  f"Inversion du sens — retour vers {dest_en}",
                  "warn")

    def new_trip(self, first: bool = False) -> None:
        st = self.state
        tr = st.train
        direction = st.selected_direction if not first else +1
        tr.direction = direction
        # Start position depends on direction : climbing trip starts at
        # Val Claret (s = START_S), descent starts at Grande Motte
        # (s = STOP_S). The destination is always the OTHER end.
        tr.s = START_S if direction > 0 else STOP_S
        tr.v = 0.0
        tr.a = 0.0
        # Speed setpoint at 100 % by default — matches the real-life
        # departure where the driver already has the throttle dialed up
        # and the train pulls out at full cruise speed once the motors
        # take the load. Driver can still lower it manually mid-trip.
        tr.speed_cmd = 1.0
        tr.throttle = 0.0
        tr.brake = 0.0
        tr.emergency = False
        tr.emergency_ramp = 0.0
        # Drum parking brake engaged at the start of every trip (cabin
        # held on the platform while passengers board).
        tr.maint_brake = True
        tr.doors_open = True
        tr.doors_cmd = True
        tr.doors_timer = 0.0
        tr.lights_cabin = True
        tr.lights_head = False
        tr.horn = False
        tr.electric_stop = False
        tr.dead_man_timer = 0.0
        tr.dead_man_fault = False
        tr.ready = False
        # Passenger loading — realistic : heavy in the climbing direction,
        # nearly empty in the descending direction (skiers come back on skis).
        half = PAX_MAX // 2
        if direction > 0:
            tr.pax_car1 = random.randint(90, half)
            tr.pax_car2 = random.randint(90, half)
            st.ghost_pax = random.randint(0, 12)
        else:
            tr.pax_car1 = random.randint(0, 8)
            tr.pax_car2 = random.randint(0, 8)
            st.ghost_pax = random.randint(90, PAX_MAX - 20)
        tr.number = st.selected_train if not first else random.choice([1, 2])
        tr.name = T("Train", "Rame") + f" {tr.number}"
        tr.tension_dan = 0.0
        tr.power_kw = 0.0
        tr.tension_dan_disp = 0.0
        tr.power_kw_disp = 0.0
        tr.jerk_sum = 0.0
        # Autopilot enabled by default — smooth soft-start ramp while
        # the driver can still fine-tune the speed setpoint manually
        # and hit STOP whenever needed.
        tr.autopilot = True
        # Counterweight (ghost) starts at the opposite station.
        st.ghost_s = LENGTH - tr.s
        st.trip_time = 0.0
        st.trip_started = False
        st.departure_buzzer_remaining = 0.0
        st.ghost_ready = False
        st.ghost_ready_timer = 0.0
        st.ghost_ready_delay = 0.0
        st.score_time = 0.0
        st.score_comfort = 100.0
        st.score_energy = 0.0
        st.events = []
        st.event_cooldown = 5.0
        st.panne_active = False
        st.panne_kind = ""
        st.finished = False
        st.rebound_timer = 0.0
        self._last_panne_kind = ""
        self._welcome_played = False
        self._arrival_played = False
        self._was_stopped_mid_tunnel = False
        self._mid_tunnel_stop_timer = 0.0
        if hasattr(self, "sounds"):
            self.sounds.reset()
        if first:
            st.mode = MODE_TITLE
        else:
            st.mode = MODE_RUN
        dep_en = "Val Claret (2111 m)" if direction > 0 else "Grande Motte (3032 m)"
        dep_fr = dep_en
        add_event(st, "board",
                  f"{tr.pax} passengers boarding train {tr.number} at "
                  f"{dep_en} ({tr.pax_car1}+{tr.pax_car2})",
                  f"{tr.pax} passagers embarquent rame {tr.number} à "
                  f"{dep_fr} ({tr.pax_car1}+{tr.pax_car2})",
                  "info")

    # ----- game tick -------------------------------------------------------

    def _tick(self) -> None:
        dt = 0.016
        st = self.state
        self._fps_acc += dt
        self._frame_count += 1
        if self._fps_acc >= 0.5:
            self._fps = self._frame_count / self._fps_acc
            self._frame_count = 0
            self._fps_acc = 0.0
        self._board_animation += dt
        self._cloud_offset = (self._cloud_offset + dt * 4.0) % 10000.0
        # Bull wheel rotates at cable linear speed. Real Von Roll drive
        # sheave on Perce-Neige is ⌀ 4.2 m (radius 2.1 m), giving ω = v/r.
        # At V_MAX = 12 m/s this yields ~54.5 rpm, matching the real
        # regulator cap and the 3 × 800 kW motor speeds after reduction.
        # Positive v (climbing) → clockwise rotation in the profile view.
        # QPainter.rotate(degrees) with screen-Y-down: positive = CW.
        self._pulley_angle += (self.state.train.v / 2.1) * dt
        # Tunnel scroll for cabin view — accumulate travel-direction
        # distance so the rings always approach the driver, whether the
        # train is climbing (+1) or descending (-1).
        self._tunnel_scroll += (
            self.state.train.v * self.state.train.direction * dt
        )
        # Advance snowflakes
        for fl in self._snowflakes:
            fl[1] += fl[2] * dt
            fl[0] += math.sin(fl[1] * 0.02) * 0.4
            if fl[1] > 820:
                fl[0] = random.uniform(0, 1280)
                fl[1] = -5
                fl[2] = random.uniform(12, 30)
                fl[3] = random.uniform(1.0, 2.6)

        self.sounds.tick(dt)
        # Ambient motor/rumble: fades with speed
        self.sounds.update_ambient(st.train.v)

        if st.mode == MODE_RUN:
            self._apply_keys(dt)
            self.physics.step(dt)
            maybe_random_event(st, dt)
            # Ghost driver ready countdown : once the main driver has
            # pressed READY, the other wagon's driver confirms after a
            # small random delay (2–4 s) — real cable-car protocol.
            if (st.train.ready and not st.ghost_ready
                    and st.ghost_ready_delay > 0.0):
                st.ghost_ready_timer += dt
                if st.ghost_ready_timer >= st.ghost_ready_delay:
                    st.ghost_ready = True
                    add_event(st, "ready",
                              "Second cabin reports ready",
                              "Autre rame prête",
                              "info")
            # Departure sequence — the buzzer must finish sounding before
            # the trip actually starts. The Z key sets
            # departure_buzzer_remaining = BUZZER_DURATION, and we count
            # it down here. When it reaches 0 → trip_started = True.
            if st.departure_buzzer_remaining > 0.0:
                st.departure_buzzer_remaining = max(
                    0.0, st.departure_buzzer_remaining - dt)
                if st.departure_buzzer_remaining <= 0.0:
                    st.trip_started = True
                    # Motors take the load — release the driver's service
                    # brake and the drum parking brake automatically.
                    # The regulator will now manage throttle and braking
                    # on its own, matching the real Perce-Neige logic
                    # where the drum releases as the drive contactor
                    # closes.
                    st.train.brake = 0.0
                    st.train.maint_brake = False
                    # Interior departure ambient — smooth ramp from
                    # silence to cruise, bridges buzzer → ambient loop.
                    self.sounds.play_departure_ambient()
                    if st.train.direction > 0:
                        add_event(st, "dep",
                                  "Departing Val Claret — 2111 m",
                                  "Départ Val Claret — 2111 m", "info")
                    else:
                        add_event(st, "dep",
                                  "Departing Grande Motte — 3032 m",
                                  "Départ Grande Motte — 3032 m", "info")
                    self._welcome_played = False
            # File 11 "Le funiculaire vous emmène en zone..." — arrival
            # message broadcast in the last ~220 m as the train rolls
            # quietly into the destination platform. Works for either
            # direction (climb or descent).
            tr_welcome = st.train
            dist_remain_welcome = (
                STOP_S - tr_welcome.s
                if tr_welcome.direction > 0
                else tr_welcome.s - START_S
            )
            # Only at the upper station (Grande Motte, direction > 0).
            # When reversing back down to Val Claret we do not broadcast
            # the "zone de ski" welcome message.
            if (st.trip_started and not self._welcome_played
                    and tr_welcome.direction > 0
                    and dist_remain_welcome < 220.0
                    and abs(tr_welcome.v) < 6.5):
                self.sounds.play("welcome", lang="fr", cooldown=600.0)
                self._welcome_played = True
            # Mid-tunnel stop tracking : flag is set after the train
            # has been stationary away from a terminus for ~3 s. The
            # "Remise en route" announcement itself is now fired when
            # the driver rearms READY (see keyPressEvent Key_V) so the
            # passengers hear it BEFORE the buzzer / start sequence.
            tr_r = st.train
            in_tunnel = (START_S + 40.0 < tr_r.s < STOP_S - 40.0)
            if (st.trip_started and not st.finished and in_tunnel
                    and abs(tr_r.v) < 0.1):
                self._mid_tunnel_stop_timer += dt
                if self._mid_tunnel_stop_timer > 3.0:
                    self._was_stopped_mid_tunnel = True
            else:
                self._mid_tunnel_stop_timer = 0.0
            # Brake squeal when emergency brake engaged
            if st.train.emergency:
                self.sounds.play_bilingual("brake_noise", cooldown=20.0)
            # Fault announcements — pick the matching message bilingually.
            # Suppressed entirely once the train has arrived so a resolved
            # emergency never leaks evac / restart messages onto the
            # station platform.
            if not st.finished:
                if st.panne_active and st.panne_kind != self._last_panne_kind:
                    self._last_panne_kind = st.panne_kind
                    if st.panne_kind in ("tension", "ice"):
                        self.sounds.play_bilingual("minor_incident", cooldown=45.0)
                    elif st.panne_kind in ("door", "thermal"):
                        self.sounds.play_bilingual("tech_incident", cooldown=45.0)
                    elif st.panne_kind == "fire":
                        self.sounds.play_bilingual("dim_light", cooldown=45.0)
                        self.sounds.play_bilingual("evac", cooldown=60.0)
                elif not st.panne_active and self._last_panne_kind:
                    # Panne resolved — play "restart"
                    self._last_panne_kind = ""
                    self.sounds.play_bilingual("restart", cooldown=30.0)
            # Arrival announcement — upstream exit at Grande Motte (upper)
            # or downstream exit at Val Claret (lower). Plays once per
            # arrival. Both stations get the generic "exit on the left"
            # message queued right after.
            if st.finished and not self._arrival_played:
                self._arrival_played = True
                # Normal arrival overrides any residual fault broadcast
                # (evac, tech_incident, restart…) queued during the trip.
                self.sounds.stop_announcements()
                self._last_panne_kind = ""
                if st.train.direction > 0:
                    # Arrived at Grande Motte (3032 m, upper)
                    self.sounds.play_bilingual("exit_upstream", cooldown=120.0)
                else:
                    # Arrived at Val Claret (2111 m, lower)
                    self.sounds.play_bilingual("exit_downstream", cooldown=120.0)
                self.sounds.play_bilingual("exit_left", cooldown=120.0)
        self.update()

    def _apply_keys(self, dt: float) -> None:
        tr = self.state.train
        st = self.state
        # Door transition — counts down while doors_cmd != doors_open.
        # Physical doors_open only flips at the end of the timer so the
        # closing chime plays *before* the leaves actually shut.
        if tr.doors_cmd != tr.doors_open and tr.doors_timer > 0.0:
            tr.doors_timer = max(0.0, tr.doors_timer - dt)
            if tr.doors_timer <= 0.0:
                tr.doors_open = tr.doors_cmd
        active = self._key_state | self._mouse_hold
        up = Qt.Key.Key_Up in active
        down = Qt.Key.Key_Down in active
        brake_key = (Qt.Key.Key_Space in active) or (Qt.Key.Key_B in active)
        # Up/Down adjust the driver's speed command (percentage of V_MAX).
        # Regulator takes care of realistic accel/decel to track it.
        # Interlock : speed_cmd is LOCKED until the departure sequence
        # is complete (both cabins ready, doors closed, trip_started).
        any_action = False
        if up and st.trip_started:
            tr.speed_cmd = min(1.0, tr.speed_cmd + 0.35 * dt)
            any_action = True
        if down:
            tr.speed_cmd = max(0.0, tr.speed_cmd - 0.35 * dt)
            any_action = True
        # Emergency-style manual brake override : while held, forces the
        # regulator off and commands full brake.
        if brake_key:
            tr.speed_cmd = max(0.0, tr.speed_cmd - 0.8 * dt)
            tr.brake = min(1.0, tr.brake + 1.4 * dt)
            any_action = True

        # --- Dead-man vigilance (optional, off by default) : driver must
        # touch any control at least once every DEAD_MAN_LIMIT seconds
        # while moving, otherwise the system triggers an automatic stop.
        if st.vigilance_enabled:
            DEAD_MAN_LIMIT = 20.0
            if abs(tr.v) > 0.2 and not tr.dead_man_fault:
                if any_action:
                    tr.dead_man_timer = 0.0
                else:
                    tr.dead_man_timer += dt
                if tr.dead_man_timer > DEAD_MAN_LIMIT:
                    tr.dead_man_fault = True
                    add_event(st, "dead_man",
                              "Dead-man vigilance failed — automatic stop",
                              "Veille automatique perdue — arrêt automatique",
                              "alarm")
            else:
                tr.dead_man_timer = 0.0
        else:
            tr.dead_man_timer = 0.0
            tr.dead_man_fault = False

    # ----- keyboard --------------------------------------------------------

    def keyPressEvent(self, ev: QKeyEvent) -> None:  # noqa: N802
        st = self.state
        k = ev.key()
        self._key_state.add(k)
        # Announcement console hotkeys (only when menu is visible).
        # Ignore auto-repeat so holding the key doesn't cascade the same
        # announcement dozens of times into the queue.
        if self._show_annmenu and not ev.isAutoRepeat():
            for entry_k, group, _lbl, en, fr in ANNOUNCEMENT_MENU:
                if k == entry_k:
                    # Interrupt any announcement currently playing — a
                    # new command always takes over, no cascading queue.
                    self.sounds.stop_announcements()
                    self.sounds._cooldowns.pop(group, None)
                    self.sounds.play_bilingual(group, cooldown=5.0)
                    add_event(st, "ann",
                              f"Announcement : {en}",
                              f"Annonce : {fr}",
                              "info")
                    return
        if k == Qt.Key.Key_F2:
            self._show_annmenu = not self._show_annmenu
            return
        if k == Qt.Key.Key_Escape:
            if self._show_annmenu:
                # Closing the menu also stops any announcement still in
                # flight — driver's "abort" path.
                self.sounds.stop_announcements()
                self._show_annmenu = False
                return
            if st.mode == MODE_RUN:
                st.mode = MODE_PAUSED
            elif st.mode == MODE_PAUSED:
                st.mode = MODE_RUN
            elif st.mode == MODE_TITLE:
                self.window().close()
        elif k == Qt.Key.Key_Return or k == Qt.Key.Key_Enter:
            if st.mode == MODE_TITLE:
                # Default trip : Train 1, climbing direction. Mouse
                # users can pick any of the 4 options on the title.
                st.selected_direction = +1
                st.selected_train = 1
                self._show_help = False
                self.new_trip()
            elif st.mode == MODE_OVER:
                self.new_trip()
        elif k == Qt.Key.Key_R:
            if st.finished or st.mode == MODE_OVER:
                self.new_trip()
        elif k == Qt.Key.Key_I:
            # Reverse direction — allowed whenever the train is at rest
            # (|v| < 0.1 m/s), whether that's at a terminus after arrival
            # OR mid-tunnel after an unscheduled stop. Real Perce-Neige
            # plays the "retour en gare" announcement in that case.
            if abs(st.train.v) < 0.1:
                self.reverse_trip()
        elif k == Qt.Key.Key_X:
            # Abort any announcement currently playing (and drop whatever
            # is still queued behind it).
            self.sounds.stop_announcements()
        elif k == Qt.Key.Key_F1:
            self._show_help = not self._show_help
            if self._show_help:
                self._show_info = False
        elif k == Qt.Key.Key_F3:
            self._show_info = not self._show_info
            if self._show_info:
                self._show_help = False
        elif k == Qt.Key.Key_F4:
            self._cabin_view = not self._cabin_view
        elif k == Qt.Key.Key_L:
            global LANG
            LANG = "en" if LANG == "fr" else "fr"
            st.lang = LANG
        elif k == Qt.Key.Key_P:
            if st.mode == MODE_RUN:
                st.mode = MODE_PAUSED
            elif st.mode == MODE_PAUSED:
                st.mode = MODE_RUN
        elif k == Qt.Key.Key_M:
            # Mode rotation : normal -> challenge -> panne -> normal
            order = ["normal", "challenge", "panne"]
            idx = order.index(st.run_mode) if st.run_mode in order else 0
            st.run_mode = order[(idx + 1) % len(order)]
        elif k == Qt.Key.Key_Shift:
            st.train.emergency = True
            st.train.maint_brake = True
        elif k == Qt.Key.Key_D:
            tr = st.train
            # Interlocks : can't operate the doors while moving or while
            # a previous transition is still running, and can't OPEN them
            # unless the train is parked at one of the two stations. The
            # "at station" window is START_S±5 m or STOP_S±5 m so door
            # ops never fire while the train is mid-tunnel.
            at_station = (tr.s <= START_S + 5.0) or (tr.s >= STOP_S - 5.0)
            if abs(tr.v) >= 0.2:
                add_event(st, "doors",
                          "Cannot operate doors while moving",
                          "Portes verrouillées — train en marche",
                          "warn")
            elif tr.doors_timer > 0.0:
                pass  # transition already in progress
            elif not tr.doors_cmd and not at_station:
                # Trying to open but we're in the tunnel — forbidden.
                add_event(st, "doors",
                          "Cannot open doors outside a station",
                          "Ouverture impossible hors station",
                          "warn")
            else:
                new_cmd = not tr.doors_cmd
                tr.doors_cmd = new_cmd
                if new_cmd:
                    tr.doors_timer = DOOR_OPEN_TIME
                    add_event(st, "doors",
                              "Opening doors", "Ouverture des portes",
                              "info")
                else:
                    tr.doors_timer = DOOR_CLOSE_TIME
                    self.sounds.play("doors_close", lang="fr", cooldown=60.0)
                    add_event(st, "doors",
                              "Doors closing...",
                              "Fermeture des portes...", "info")
        elif k == Qt.Key.Key_A:
            tr = st.train
            tr.autopilot = not tr.autopilot
            add_event(st, "auto",
                      f"Autopilot {'ON' if tr.autopilot else 'OFF'}",
                      f"Pilote auto {'ON' if tr.autopilot else 'OFF'}",
                      "info")
        elif k == Qt.Key.Key_N:
            muted = self.sounds.toggle_mute()
            add_event(st, "mute",
                      f"Sound {'muted' if muted else 'on'}",
                      f"Son {'coupé' if muted else 'actif'}",
                      "info")
        elif k == Qt.Key.Key_3:
            # Electric stop — latched. Press once to engage, again to release.
            tr = st.train
            tr.electric_stop = not tr.electric_stop
            if tr.electric_stop:
                add_event(st, "estop", "Electric stop engaged",
                          "Arrêt électrique engagé", "warn")
            else:
                add_event(st, "estop", "Electric stop released",
                          "Arrêt électrique relâché", "info")
                tr.dead_man_timer = 0.0
                tr.dead_man_fault = False
        elif k == Qt.Key.Key_4:
            # Emergency stop — latched rail-brake. Pressing it also
            # drops the drum parking brake so the cabin can't drift on
            # a slope once it's been immobilised. Press again to release
            # while stopped : both brakes come off together and gravity
            # / motor take over again. This mirrors the real machinery
            # where the safety chain cuts the drive and bolts the drum.
            tr = st.train
            if not tr.emergency:
                tr.emergency = True
                tr.maint_brake = True
                add_event(st, "eurg",
                          "EMERGENCY STOP — rail + drum brakes",
                          "ARRÊT D'URGENCE — freins rail + tambour",
                          "alarm")
                self.sounds.play_bilingual("brake_noise", cooldown=30.0)
            elif abs(tr.v) < 0.1:
                tr.emergency = False
                tr.maint_brake = False
                add_event(st, "eurg",
                          "Emergency released — drum brake off",
                          "Urgence relâchée — frein tambour desserré",
                          "info")
        elif k == Qt.Key.Key_H:
            tr = st.train
            tr.lights_head = not tr.lights_head
            add_event(st, "head",
                      f"Headlights {'ON' if tr.lights_head else 'OFF'}",
                      f"Phares {'allumés' if tr.lights_head else 'éteints'}",
                      "info")
        elif k == Qt.Key.Key_C:
            tr = st.train
            tr.lights_cabin = not tr.lights_cabin
            add_event(st, "cab",
                      f"Cabin lights {'ON' if tr.lights_cabin else 'OFF'}",
                      f"Éclairage cabine {'allumé' if tr.lights_cabin else 'éteint'}",
                      "info")
            if not tr.lights_cabin:
                # Real announcement when dimming the cabin
                self.sounds.play_bilingual("dim_light", cooldown=60.0)
        elif k == Qt.Key.Key_K:
            st.train.horn = True
            self.sounds.start_horn()
        elif k == Qt.Key.Key_0:
            # Speed cmd → 0 quick cut. Not bound to a keyboard shortcut by
            # default, but reachable via the on-screen STOP click pad.
            st.train.speed_cmd = 0.0
        elif k == Qt.Key.Key_G:
            if st.vigilance_enabled:
                # Dead-man vigilance acknowledge — driver proves they're awake
                tr = st.train
                tr.dead_man_timer = 0.0
                if tr.dead_man_fault:
                    tr.dead_man_fault = False
                    add_event(st, "dm", "Vigilance restored",
                              "Veille rétablie", "info")
        elif k == Qt.Key.Key_W:
            # Toggle dead-man vigilance on/off
            st.vigilance_enabled = not st.vigilance_enabled
            if st.vigilance_enabled:
                add_event(st, "vigil",
                          "Vigilance enabled (20 s)",
                          "Veille activée (20 s)", "info")
            else:
                add_event(st, "vigil",
                          "Vigilance disabled",
                          "Veille désactivée", "info")
        elif k == Qt.Key.Key_V:
            # READY to depart — driver confirms the cabin is ready. The
            # other wagon's driver then auto-confirms after 2-4 s. Only
            # valid at standstill in a station, with the doors still
            # open (departure sequence hasn't started).
            tr = st.train
            if st.trip_started or st.finished:
                return
            # Interlocks : the ready button is wired through the safety
            # chain of the real Perce-Neige. Arming READY is only
            # possible when every condition below is satisfied. Canceling
            # (tr.ready → False) is always allowed.
            if not tr.ready:
                at_terminus_v = ((tr.s <= START_S + 5.0)
                                 or (tr.s >= STOP_S - 5.0))
                reason_en = ""
                reason_fr = ""
                # Interlocks that ALWAYS apply (terminus or mid-tunnel) :
                # doors must be closed, no electric stop, no vigilance
                # fault, no active fault.
                if tr.doors_open or tr.doors_cmd or tr.doors_timer > 0.0:
                    reason_en = "doors not fully closed"
                    reason_fr = "portes pas totalement fermées"
                elif tr.electric_stop:
                    reason_en = "electric stop engaged"
                    reason_fr = "arrêt électrique engagé"
                elif tr.dead_man_fault:
                    reason_en = "vigilance fault — acknowledge first"
                    reason_fr = "défaut veille — acquittement requis"
                elif st.panne_active:
                    reason_en = "fault active — clear it first"
                    reason_fr = "panne en cours — à résoudre d'abord"
                # Interlocks that apply AT A TERMINUS only. Mid-tunnel
                # restart is an abnormal situation : the driver may
                # pre-arm READY while the emergency brake is still on
                # so the "Remise en route" announcement plays BEFORE
                # they release the emergency and the cabin starts
                # drifting under gravity.
                elif at_terminus_v and (tr.emergency
                                        or tr.emergency_ramp > 0.0):
                    reason_en = "emergency brake engaged"
                    reason_fr = "freins d'urgence engagés"
                elif at_terminus_v and abs(tr.v) > 0.1:
                    reason_en = "train still moving"
                    reason_fr = "train encore en mouvement"
                if reason_en:
                    add_event(st, "ready",
                              f"Cannot arm READY — {reason_en}",
                              f"Prêt impossible — {reason_fr}",
                              "warn")
                    return
            tr.ready = not tr.ready
            if tr.ready:
                st.ghost_ready = False
                st.ghost_ready_timer = 0.0
                st.ghost_ready_delay = random.uniform(2.0, 4.0)
                # Abnormal-situation restart : arming READY mid-tunnel
                # (i.e. NOT at one of the two termini) triggers the
                # real funicular's "Remise en route" announcement
                # (file #8) so passengers know the service is resuming.
                at_terminus_v = ((tr.s <= START_S + 5.0)
                                 or (tr.s >= STOP_S - 5.0))
                if not at_terminus_v:
                    self.sounds.stop_announcements()
                    self.sounds.play_bilingual("restart", cooldown=30.0)
                    add_event(st, "ready",
                              "Mid-tunnel restart — 'Resuming service' announcement",
                              "Reprise en tunnel — annonce 'Remise en route'",
                              "info")
                    self._was_stopped_mid_tunnel = False
                add_event(st, "ready",
                          "Ready to depart — waiting for second cabin",
                          "Prêt au départ — attente autre rame",
                          "info")
            else:
                st.ghost_ready = False
                st.ghost_ready_timer = 0.0
                st.ghost_ready_delay = 0.0
                add_event(st, "ready",
                          "Ready cancelled",
                          "Annulation prêt au départ",
                          "info")
        elif k == Qt.Key.Key_Z:
            # START / DEPART — triggers the departure sequence:
            # 1) doors close  2) buzzer sounds 12.3 s  3) trip_started
            tr = st.train
            if st.trip_started or st.finished:
                return
            if st.departure_buzzer_remaining > 0.0:
                return  # already sounding
            if not (tr.ready and st.ghost_ready):
                add_event(st, "dep",
                          "Cannot start — both cabins must be ready",
                          "Départ impossible — les deux rames doivent être prêtes",
                          "warn")
                return
            # Traction interlocks : don't fire the buzzer / doors chime
            # if the train physically can't accelerate once the buzzer
            # ends. Buzzing at the platform while the train stays put
            # would be misleading for the passengers.
            reason_en = ""
            reason_fr = ""
            if tr.emergency or tr.emergency_ramp > 0.0:
                reason_en = "emergency brake engaged"
                reason_fr = "freins d'urgence engagés"
            elif tr.electric_stop:
                reason_en = "electric stop engaged"
                reason_fr = "arrêt électrique engagé"
            elif tr.dead_man_fault:
                reason_en = "vigilance fault — acknowledge first"
                reason_fr = "défaut veille — acquittement requis"
            elif st.panne_active:
                reason_en = "fault active — clear it first"
                reason_fr = "panne en cours — à résoudre d'abord"
            elif tr.speed_cmd < 0.01:
                reason_en = "speed setpoint at 0 — dial it up first"
                reason_fr = "consigne de vitesse à 0 — la monter d'abord"
            if reason_en:
                add_event(st, "dep",
                          f"Cannot start — {reason_en}",
                          f"Départ impossible — {reason_fr}",
                          "warn")
                return
            # Close the doors (3 s transition) — play the closing chime
            # only if they were actually open. Skipping this avoids the
            # spurious "attention fermeture" announcement when restarting
            # from a mid-tunnel stop or after a direction reversal where
            # the doors never reopened in the first place.
            if tr.doors_cmd:
                tr.doors_cmd = False
                tr.doors_timer = DOOR_CLOSE_TIME
                self.sounds.play("doors_close", lang="fr", cooldown=60.0)
            # Departure signal: different sound per station.
            # Each WAV includes ~1.5 s of pre-buzzer ambient for a
            # smooth fade-in, so the countdown matches the full WAV.
            # Upper (Glacier, direction=-1): ambient + industrial buzzer
            # Lower (Val Claret, direction=+1): ambient + bell/ring
            # Buzzers are physical speakers on the station platforms —
            # they are only audible when the train is actually at one
            # of the termini. Mid-tunnel restarts skip the buzzer.
            at_upper = tr.direction == -1
            at_station = (tr.s <= START_S + 5.0) or (tr.s >= STOP_S - 5.0)
            if at_station:
                BUZZER_DURATION = 6.5 if at_upper else 8.0
                st.departure_buzzer_remaining = BUZZER_DURATION
                self.sounds.play_buzzer(upper_station=at_upper)
                secs = int(BUZZER_DURATION)
                add_event(st, "doors",
                          f"Buzzer — departure in {secs} s",
                          f"Buzzer — départ dans {secs} s",
                          "info")
            else:
                # Short silent delay before the trip resumes — no buzzer
                # because we're out in the tunnel, far from the platform
                # speakers.
                st.departure_buzzer_remaining = 1.5
                add_event(st, "dep",
                          "Resuming mid-tunnel — no buzzer",
                          "Reprise en tunnel — pas de buzzer",
                          "info")

    def keyReleaseEvent(self, ev: QKeyEvent) -> None:  # noqa: N802
        k = ev.key()
        self._key_state.discard(k)
        if k == Qt.Key.Key_Shift:
            # Shift is the hold-to-emergency override. Only clear emergency
            # if it wasn't latched via the dedicated button (4). The drum
            # parking brake is released alongside so the train can move
            # again if gravity / motor take over.
            if self.state.train.emergency and abs(self.state.train.v) < 0.1:
                self.state.train.emergency = False
                self.state.train.maint_brake = False
        if k == Qt.Key.Key_K:
            self.state.train.horn = False
            self.sounds.stop_horn()

    # ----- mouse -----------------------------------------------------------
    #
    # The cockpit panel, speed command bar and overlay buttons all register
    # themselves in self._hit_zones every _draw_hud() frame. A click hit-
    # tests that list and synthesises a key press so the same code path
    # runs for keyboard and mouse input. Hold-type controls (speed up/down,
    # brake, horn, emergency) also add their key to self._mouse_hold so the
    # polling loop sees them as "held" until the button is released.

    def _sim_press(self, qk: int) -> None:
        self.keyPressEvent(
            QKeyEvent(QEvent.Type.KeyPress, qk, Qt.KeyboardModifier.NoModifier)
        )

    def _sim_release(self, qk: int) -> None:
        self.keyReleaseEvent(
            QKeyEvent(QEvent.Type.KeyRelease, qk, Qt.KeyboardModifier.NoModifier)
        )

    def mousePressEvent(self, ev: QMouseEvent) -> None:  # noqa: N802
        if ev.button() != Qt.MouseButton.LeftButton:
            return
        pos = ev.position()
        st = self.state
        if st.mode == MODE_TITLE:
            # Match a title-screen trip-selection zone.
            for rect, direction, train_num in self._title_zones:
                if rect.contains(pos):
                    st.selected_direction = direction
                    st.selected_train = train_num
                    self._show_help = False
                    self.new_trip()
                    ev.accept()
                    return
            # Click outside any zone on the title screen — ignore.
            return
        # Reverse-iterate so later buttons win (none overlap currently, but
        # future overlays might be drawn on top).
        for rect, qk, hold in reversed(self._hit_zones):
            if rect.contains(pos):
                if hold:
                    self._mouse_hold.add(qk)
                self._sim_press(qk)
                ev.accept()
                return

    def mouseReleaseEvent(self, ev: QMouseEvent) -> None:  # noqa: N802
        if ev.button() != Qt.MouseButton.LeftButton:
            return
        if not self._mouse_hold:
            return
        to_clear = list(self._mouse_hold)
        self._mouse_hold.clear()
        for qk in to_clear:
            self._sim_release(qk)
        ev.accept()

    # ----- painting --------------------------------------------------------

    def paintEvent(self, _ev) -> None:  # noqa: N802
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        p.setRenderHint(QPainter.RenderHint.TextAntialiasing, True)
        w, h = self.width(), self.height()

        self._draw_background(p, w, h)
        view_rect = QRectF(20, 20, w - 440, h - 260)
        if self._cabin_view and self.state.mode == MODE_RUN:
            self._draw_cabin_view(p, view_rect)
        else:
            self._draw_world(p, view_rect)

        hud_rect = QRectF(w - 410, 20, 390, h - 260)
        self._draw_hud(p, hud_rect)

        log_rect = QRectF(20, h - 230, w - 40, 210)
        self._draw_eventlog(p, log_rect)

        if self.state.mode == MODE_TITLE:
            self._draw_title_overlay(p, w, h)
        elif self.state.mode == MODE_PAUSED:
            self._draw_paused_overlay(p, w, h)
        elif self.state.finished:
            self._draw_finished_overlay(p, w, h)

        if self._show_help:
            self._draw_help_overlay(p, w, h)

        if self._show_info:
            self._draw_info_overlay(p, w, h)

        if self._show_annmenu:
            self._draw_ann_menu(p, w, h)

        # Version + fps
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 9))
        p.drawText(
            QRectF(w - 140, h - 18, 130, 16),
            int(Qt.AlignmentFlag.AlignRight),
            f"v{VERSION}  {self._fps:.0f} fps",
        )
        p.end()

    # ----- background ------------------------------------------------------

    def _draw_background(self, p: QPainter, w: int, h: int) -> None:
        grad = QLinearGradient(0, 0, 0, h)
        grad.setColorAt(0, COLOR_BG_TOP)
        grad.setColorAt(1, COLOR_BG_BOT)
        p.fillRect(0, 0, w, h, QBrush(grad))

    # ----- main world view -------------------------------------------------

    def _draw_world(self, p: QPainter, rect: QRectF) -> None:
        st = self.state
        tr = st.train
        p.save()
        p.setClipRect(rect)

        # Title
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 14, QFont.Weight.DemiBold))
        p.drawText(
            QRectF(rect.x(), rect.y(), rect.width(), 22),
            int(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignVCenter),
            T("Perce-Neige funicular — side view",
              "Funiculaire Perce-Neige — vue en coupe"),
        )

        view_h = rect.height() - 40
        view_y = rect.y() + 28
        view_x = rect.x() + 10
        view_w = rect.width() - 20

        # Determine camera in horizontal metres. Narrower = more zoom.
        cam_width_m = 850.0
        cabin_x_m, cabin_y_m = geom_at(tr.s)
        cam_x_m = max(0.0, min(max(H_MAX - cam_width_m, 0),
                               cabin_x_m - cam_width_m * 0.48))

        # Y range: follow the cabin vertically so we stay close to the track
        y_span = 350.0
        y_mid = max(ALT_LOW + y_span / 2,
                    min(ALT_HIGH - y_span / 2 + 40, cabin_y_m + 40))
        y_top_m = y_mid + y_span / 2
        y_bot_m = y_mid - y_span / 2

        def world_to_screen(xm: float, ym: float) -> QPointF:
            px = view_x + (xm - cam_x_m) / cam_width_m * view_w
            py = view_y + (y_top_m - ym) / (y_top_m - y_bot_m) * view_h
            return QPointF(px, py)

        # Draw mountain outline as filled polygon from the tunnel line up
        # to the top of the view, thickened upward for the mountain body.
        n_points = 180
        mountain: list[QPointF] = []
        tunnel_line: list[QPointF] = []
        for i in range(n_points + 1):
            s_ = i / n_points * LENGTH
            xm, ym = geom_at(s_)
            tunnel_line.append(world_to_screen(xm, ym))
            # Mountain top : add a rugged cap
            top_y = ym + 160 + 30 * math.sin(s_ * 0.008) + 20 * math.sin(s_ * 0.021)
            mountain.append(world_to_screen(xm, top_y))

        # Sky-to-rock gradient
        poly_mountain = QPolygonF()
        for pt in mountain:
            poly_mountain.append(pt)
        for pt in reversed(tunnel_line):
            poly_mountain.append(pt)
        grad_rock = QLinearGradient(0, view_y, 0, view_y + view_h)
        grad_rock.setColorAt(0.0, COLOR_MOUNT_2)
        grad_rock.setColorAt(1.0, COLOR_MOUNT_1)
        p.setBrush(QBrush(grad_rock))
        p.setPen(QPen(QColor(20, 20, 20), 1))
        p.drawPolygon(poly_mountain)

        # Snow line : everything above alt 2700 gets a white mantle
        snow_poly = QPolygonF()
        snow_top: list[QPointF] = []
        for i, pt in enumerate(mountain):
            snow_top.append(pt)
        snow_bot: list[QPointF] = []
        for i in range(n_points + 1):
            s_ = i / n_points * LENGTH
            xm, ym = geom_at(s_)
            ym_snow = max(ym, 2700.0)
            snow_bot.append(world_to_screen(xm, ym_snow))
        for pt in snow_top:
            snow_poly.append(pt)
        for pt in reversed(snow_bot):
            snow_poly.append(pt)
        p.setBrush(QBrush(COLOR_GLACIER))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawPolygon(snow_poly)

        # Draw tunnel as a darker tube along the slope
        pen_tunnel = QPen(COLOR_TUNNEL, 10)
        pen_tunnel.setCapStyle(Qt.PenCapStyle.RoundCap)
        p.setPen(pen_tunnel)
        path = QPainterPath()
        path.moveTo(tunnel_line[0])
        for pt in tunnel_line[1:]:
            path.lineTo(pt)
        p.drawPath(path)
        pen_rail = QPen(COLOR_TUNNEL_WALL, 2)
        p.setPen(pen_rail)
        p.drawPath(path)

        # Passing loop : a slightly wider section with twin tubes
        p_s = max(0.0, min(LENGTH, PASSING_START))
        p_e = max(0.0, min(LENGTH, PASSING_END))
        loop_pts_up = []
        loop_pts_dn = []
        for i in range(30):
            s_ = p_s + (p_e - p_s) * i / 29
            xm, ym = geom_at(s_)
            loop_pts_up.append(world_to_screen(xm, ym + 3))
            loop_pts_dn.append(world_to_screen(xm, ym - 3))
        p.setPen(QPen(COLOR_TUNNEL_WALL, 6))
        path_up = QPainterPath()
        path_up.moveTo(loop_pts_up[0])
        for pt in loop_pts_up[1:]:
            path_up.lineTo(pt)
        path_dn = QPainterPath()
        path_dn.moveTo(loop_pts_dn[0])
        for pt in loop_pts_dn[1:]:
            path_dn.lineTo(pt)
        p.drawPath(path_up)
        p.drawPath(path_dn)

        # Stations : small buildings at base and top
        base_x, base_y = geom_at(0.0)
        top_x, top_y = geom_at(LENGTH)
        self._draw_station(p, world_to_screen(base_x, base_y), "Val Claret", "2111 m", up=False)
        self._draw_station(p, world_to_screen(top_x, top_y), "Grande Motte", "3032 m", up=True)

        # Altitude markers
        p.setPen(QPen(COLOR_TEXT_DIM, 1, Qt.PenStyle.DotLine))
        p.setFont(QFont("Consolas", 9))
        for alt in range(2100, 3101, 100):
            y_scr = view_y + (y_top_m - alt) / (y_top_m - y_bot_m) * view_h
            p.drawLine(int(view_x), int(y_scr), int(view_x + view_w), int(y_scr))
            p.drawText(int(view_x + 4), int(y_scr - 2), f"{alt} m")

        # Distance markers every 500 m along the slope
        p.setPen(QPen(COLOR_TEXT_DIM, 1))
        for s_m in range(0, int(LENGTH) + 1, 500):
            xm, ym = geom_at(float(s_m))
            pos = world_to_screen(xm, ym - 40)
            p.drawText(int(pos.x() - 20), int(pos.y()), f"{s_m} m")

        # Draw the counterweight (ghost) train at st.ghost_s, orange
        ghost_xm, ghost_ym = geom_at(st.ghost_s)
        self._draw_cabin(p, world_to_screen, ghost_xm, ghost_ym,
                         st.ghost_s, COLOR_GHOST, "RAME 2" if tr.number == 1 else "RAME 1")
        # Draw main cabin
        self._draw_cabin(p, world_to_screen, cabin_x_m, cabin_y_m,
                         tr.s, COLOR_CABIN, tr.name.upper())

        # Current slope display
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Consolas", 10))
        grad_now = gradient_at(tr.s) * 100
        ang = math.degrees(math.atan(gradient_at(tr.s)))
        p.drawText(
            QRectF(view_x + view_w - 180, view_y + 4, 170, 18),
            int(Qt.AlignmentFlag.AlignRight),
            T(f"slope  {grad_now:4.1f}%  ({ang:4.1f}°)",
              f"pente  {grad_now:4.1f}%  ({ang:4.1f}°)"),
        )

        # Snowflakes drifting across the view (falls inside the clip)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QBrush(QColor(240, 248, 255, 200)))
        for fl in self._snowflakes:
            if view_x <= fl[0] <= view_x + view_w and view_y <= fl[1] <= view_y + view_h:
                p.drawEllipse(QPointF(fl[0], fl[1]), fl[3], fl[3])

        # Motor room inset at BOTTOM-right of the world view (used to be
        # at the top-right but masked the upper station — the user asked
        # for it to move down where there's free space next to the plan
        # view).
        motor_rect = QRectF(
            view_x + view_w - 288,
            view_y + view_h - 168,
            280, 156,
        )
        self._draw_motor_room(p, motor_rect)

        # Mini-map bar along the top
        mini_rect = QRectF(view_x + 4, view_y + 2, view_w - 220, 32)
        self._draw_minimap(p, mini_rect)

        # Plan view (bird's eye) inset — bottom-left of world view
        plan_rect = QRectF(view_x + 8, view_y + view_h - 150, 240, 138)
        self._draw_planview(p, plan_rect)

        p.restore()

    # ----- cabin first-person view ----------------------------------------

    def _draw_cabin_view(self, p: QPainter, rect: QRectF) -> None:
        """First-person view from the driver's cab looking up the tunnel.

        Draws a procedural 3D perspective of the circular TBM tunnel bore
        with rails, cable guide, wall cables, fluorescent lighting strips,
        and curve effects (vanishing point shift).  Based on HD frame
        analysis of YouTube video A_oxDO8jtXo (interior montée FUNI284).

        The tunnel sections scroll toward the viewer as the train moves.
        Dark zones, the passing loop, and station approach are rendered.
        """
        p.save()
        p.setClipRect(rect)
        st = self.state
        tr = st.train
        vx = rect.x()
        vy = rect.y()
        vw = rect.width()
        vh = rect.height()

        # --- Background: dark tunnel interior ---
        p.fillRect(rect, QColor(18, 20, 22))

        # Visible windshield area (cabin wall covers right 22%, left frame 48px)
        cabin_wall_w = vw * 0.22
        frame_left = 48.0
        visible_cx = vx + (frame_left + (vw - cabin_wall_w)) / 2.0
        visible_cy = vy + vh * 0.48

        # === Real pinhole-camera perspective ===
        # True geometric projection: screen_r = focal * R_tunnel / d.
        # This makes near walls fill the screen and far rings shrink
        # rapidly (hyperbolic falloff), matching human eye optics and
        # giving correct motion-parallax speed perception.
        #
        #   FOV 72° horizontal matches the driver's wide windshield.
        #   The effective viewport excludes the left frame and the
        #   right-hand cabin wall.
        fov_h = 72.0 * math.pi / 180.0
        frame_left_px = 48.0
        effective_view_w = max(200.0, vw - cabin_wall_w - frame_left_px)
        focal = (effective_view_w * 0.5) / math.tan(fov_h * 0.5)
        R_t = 1.55  # real TBM bore radius (~ 3.1 m diameter)

        eye_x = visible_cx
        eye_y = visible_cy

        # --- Visibility depth, gated by the headlights -----------------
        # Headlights OFF: the driver barely sees a few metres of concrete
        #   past the windshield — only the wall fluorescents glow as
        #   beacons in the dark.
        # Headlights ON: the beam reaches ~50 m before the concrete dust
        #   swallows it, with exponential falloff (Beer-Lambert-ish).
        if tr.lights_head:
            max_depth = 100.0
            head_reach = 38.0  # exponential decay length (m)
        else:
            max_depth = 14.0
            head_reach = 0.0

        # Real TBM segment pitch ~ 1.5 m. Ring depths are generated from
        # the accumulated scroll so rings "flow" at exactly the physical
        # train speed.
        ring_spacing = 1.5
        phase_m = self._tunnel_scroll % ring_spacing
        d0 = ring_spacing - phase_m
        if d0 < 0.8:
            d0 += ring_spacing
        ring_depths: list[float] = []
        d_cur = d0
        while d_cur <= max_depth:
            ring_depths.append(d_cur)
            d_cur += ring_spacing

        def _ring_xyr(d: float) -> tuple[float, float, float, float, float]:
            """Project ring at depth d. Returns (cx, cy, r_px, ts, near_f)."""
            ts = max(0.0, min(LENGTH, tr.s + d * tr.direction))
            curv_d = curvature_at(ts) * tr.direction
            # Ring-centre lateral offset from accumulated curvature
            # (chord ≈ ½·κ·d² → projected screen offset ≈ ½·f·κ·d)
            cxp = eye_x + 0.5 * focal * curv_d * d
            cyp = eye_y
            # Pinhole radius, clamped so near rings stay on-canvas
            r_raw = focal * R_t / max(d, 0.35)
            r_px = min(r_raw, effective_view_w * 1.25)
            # Nearness factor for alpha / line widths (1 at d=3, 0.1 at d=30)
            near_f = min(1.0, 3.0 / max(d, 3.0))
            return cxp, cyp, r_px, ts, near_f

        # === Pass 1: tunnel walls (near → far) =========================
        for d in ring_depths:
            cx, cy, r_px, track_s_c, near_f = _ring_xyr(d)
            lit = tunnel_lit_at(track_s_c)
            near_station = track_s_c < 100 or track_s_c > LENGTH - 100
            head_boost = (115.0 * math.exp(-d / head_reach)
                          if head_reach > 0 else 0.0)
            if near_station:
                base_b = 140
            elif lit:
                base_b = 48
            else:
                base_b = 6
            wall_bright = int(min(220, base_b + head_boost))
            wc = QColor(wall_bright,
                        int(wall_bright * 1.02),
                        int(wall_bright * 0.96))
            dark_c = QColor(max(wall_bright - 30, 4),
                            max(wall_bright - 28, 4),
                            max(wall_bright - 32, 4))
            shape = tunnel_shape_at(track_s_c)
            if shape == "circular":
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(wc))
                p.drawEllipse(QPointF(cx, cy), r_px, r_px)
                p.setBrush(QBrush(dark_c))
                p.drawEllipse(QPointF(cx, cy), r_px * 0.92, r_px * 0.92)
            else:
                hw = r_px * 1.2
                hh = r_px * 1.1
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(wc))
                path = QPainterPath()
                path.addRoundedRect(cx - hw, cy - hh * 0.8,
                                    hw * 2, hh * 1.8,
                                    r_px * 0.5, r_px * 0.5)
                p.drawPath(path)
                p.setBrush(QBrush(dark_c))
                path2 = QPainterPath()
                path2.addRoundedRect(cx - hw * 0.9, cy - hh * 0.72,
                                     hw * 1.8, hh * 1.62,
                                     r_px * 0.4, r_px * 0.4)
                p.drawPath(path2)
            # Wall cables (only visible when nearby)
            if r_px > 12 and near_f > 0.15:
                cable_alpha = int(min(200, 60 + 140 * near_f))
                p.setPen(QPen(QColor(40, 40, 45, cable_alpha),
                              max(2.0 * near_f, 0.5)))
                for off in (0.35, 0.55, 0.75):
                    p.drawPoint(QPointF(cx - r_px * 0.88,
                                        cy - r_px * off + r_px * 0.3))

        # === Pass 2: rails, ties, chevrons (far → near) ================
        prev_pts: dict[str, QPointF | None] = {
            'lr': None, 'rr': None, 'cg': None,
        }
        for d in reversed(ring_depths):
            cx, cy, r_px, track_s_c, near_f = _ring_xyr(d)
            if r_px < 1.0:
                continue
            gauge_px = r_px * 0.35
            rail_y = cy + r_px * 0.75
            left_rail = QPointF(cx - gauge_px, rail_y)
            right_rail = QPointF(cx + gauge_px, rail_y)
            cable_guide = QPointF(cx, rail_y - r_px * 0.03)
            pen_w = max(2.0 * near_f, 0.5)
            rail_alpha = int(min(220, 70 + 150 * near_f))
            p.setPen(QPen(QColor(160, 165, 155, rail_alpha), pen_w))
            if prev_pts['lr'] is not None:
                p.drawLine(prev_pts['lr'], left_rail)
            prev_pts['lr'] = left_rail
            if prev_pts['rr'] is not None:
                p.drawLine(prev_pts['rr'], right_rail)
            prev_pts['rr'] = right_rail
            p.setPen(QPen(QColor(100, 105, 95, rail_alpha), pen_w * 0.8))
            if prev_pts['cg'] is not None:
                p.drawLine(prev_pts['cg'], cable_guide)
            prev_pts['cg'] = cable_guide
            # Sleeper + central cable-guide bolt
            tie_alpha = int(min(230, 70 + 160 * near_f))
            tie_w = gauge_px * 1.05
            tie_h = max(3.0 * near_f, 1.0)
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(QColor(55, 48, 38, tie_alpha)))
            p.drawRect(QRectF(cx - tie_w, rail_y - tie_h * 0.5,
                              tie_w * 2.0, tie_h))
            bolt_w = max(2.0 * near_f, 0.7)
            p.setBrush(QBrush(QColor(140, 135, 120,
                                     int(tie_alpha * 0.8))))
            p.drawRect(QRectF(cx - bolt_w, rail_y - tie_h * 0.7,
                              bolt_w * 2.0, tie_h * 1.4))
            # Passing loop
            if is_passing_loop(track_s_c) and r_px > 10:
                loop_alpha = int(min(150, 40 + 110 * near_f))
                loop_r = r_px * 0.55
                loop_cx = cx - r_px * 1.25
                loop_cy = cy + r_px * 0.05
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(QColor(55, 60, 50, loop_alpha)))
                p.drawEllipse(QPointF(loop_cx, loop_cy), loop_r, loop_r)
                p.setBrush(QBrush(QColor(18, 20, 16, loop_alpha)))
                p.drawEllipse(QPointF(loop_cx, loop_cy),
                              loop_r * 0.85, loop_r * 0.85)
            # Curve chevrons
            sign_curv = curvature_at(track_s_c)
            if abs(sign_curv) > 0.003 and r_px > 8:
                chev_alpha = int(min(200, 40 + 160 * near_f))
                chev_x = cx + r_px * 0.85 if sign_curv > 0 else cx - r_px * 0.85
                chev_y = cy
                chev_sz = r_px * 0.12
                p.setPen(QPen(QColor(240, 200, 40, chev_alpha),
                              max(1.5 * near_f, 0.6)))
                if sign_curv > 0:
                    p.drawLine(QPointF(chev_x, chev_y - chev_sz),
                               QPointF(chev_x - chev_sz * 0.5, chev_y))
                    p.drawLine(QPointF(chev_x - chev_sz * 0.5, chev_y),
                               QPointF(chev_x, chev_y + chev_sz))
                else:
                    p.drawLine(QPointF(chev_x, chev_y - chev_sz),
                               QPointF(chev_x + chev_sz * 0.5, chev_y))
                    p.drawLine(QPointF(chev_x + chev_sz * 0.5, chev_y),
                               QPointF(chev_x, chev_y + chev_sz))

        # === Neon tubes on the upper wall ==============================
        # Installed on the left wall in the climbing direction → on the
        # driver's right when the cabin is turned for the return trip.
        # They emit their own light and remain visible as beacons even
        # with headlights off.
        NEON_SPACING = 12.0
        NEON_LENGTH = 1.6
        neon_side = -1.0 if tr.direction > 0 else +1.0
        neon_max_depth = 55.0 if tr.lights_head else 28.0

        def _proj_wall(d: float) -> tuple[float, float, float]:
            ts = max(0.0, min(LENGTH, tr.s + d * tr.direction))
            curv_w = curvature_at(ts) * tr.direction
            cxw = eye_x + 0.5 * focal * curv_w * d
            cyw = eye_y
            rw_raw = focal * R_t / max(d, 0.35)
            rw = min(rw_raw, effective_view_w * 1.25)
            wall_x = cxw + neon_side * rw * 0.85
            wall_y = cyw - rw * 0.45
            nf = min(1.0, 3.0 / max(d, 3.0))
            return wall_x, wall_y, nf

        k_span = int(neon_max_depth / NEON_SPACING) + 3
        k_center = int(tr.s / NEON_SPACING)
        for k in range(k_center - k_span, k_center + k_span + 1):
            neon_s = k * NEON_SPACING
            if neon_s < 0.0 or neon_s > LENGTH:
                continue
            if not tunnel_lit_at(neon_s):
                continue
            depth_c = (neon_s - tr.s) * tr.direction
            if depth_c < 1.0 or depth_c > neon_max_depth:
                continue
            d_near = max(0.5, depth_c - NEON_LENGTH * 0.5)
            d_far = min(neon_max_depth, depth_c + NEON_LENGTH * 0.5)
            x1, y1, nf = _proj_wall(d_near)
            x2, y2, _ = _proj_wall(d_far)
            halo_w = max(14.0 * nf, 4.0)
            mid_w = max(7.0 * nf, 2.2)
            core_w = max(3.2 * nf, 1.2)
            alpha_halo = int(min(180, 80 + 100 * nf))
            alpha_mid = int(min(230, 120 + 110 * nf))
            alpha_core = int(min(255, 180 + 75 * nf))
            p.setPen(QPen(QColor(170, 200, 255, alpha_halo), halo_w))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))
            p.setPen(QPen(QColor(220, 235, 255, alpha_mid), mid_w))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))
            p.setPen(QPen(QColor(255, 255, 245, alpha_core), core_w))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))

        # --- Cabin frame overlay (beige interior, windshield frame) ---
        # Windshield border — dark frame around the tunnel view
        frame_w = 18
        frame_col = QColor(55, 52, 48)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QBrush(frame_col))
        # Top frame
        p.drawRect(QRectF(vx, vy, vw, frame_w + 10))
        # Left frame
        p.drawRect(QRectF(vx, vy, frame_w + 30, vh))
        # Right frame — thicker (cabin wall, reuses cabin_wall_w from above)
        cabin_grad = QLinearGradient(vx + vw - cabin_wall_w, 0,
                                     vx + vw, 0)
        cabin_grad.setColorAt(0.0, QColor(55, 52, 48))
        cabin_grad.setColorAt(0.15, QColor(185, 175, 162))  # beige interior
        cabin_grad.setColorAt(1.0, QColor(170, 160, 148))
        p.setBrush(QBrush(cabin_grad))
        p.drawRect(QRectF(vx + vw - cabin_wall_w, vy, cabin_wall_w, vh))

        # Cabin window on right wall (looking out at tunnel wall)
        win_x = vx + vw - cabin_wall_w + 30
        win_y = vy + vh * 0.15
        win_w = cabin_wall_w - 50
        win_h = vh * 0.45
        if win_w > 30 and win_h > 30:
            p.setPen(QPen(QColor(40, 38, 35), 2))
            p.setBrush(QBrush(QColor(45, 50, 55, 180)))
            p.drawRoundedRect(QRectF(win_x, win_y, win_w, win_h), 8, 8)
            # Blue-grey tunnel wall visible through window
            tw_col = QColor(60, 65, 80)
            if tunnel_lit_at(tr.s):
                tw_col = QColor(80, 85, 95)
            p.setBrush(QBrush(tw_col))
            p.drawRoundedRect(QRectF(win_x + 4, win_y + 4,
                                     win_w - 8, win_h - 8), 6, 6)
            # Golden stripe on tunnel wall (visible in video)
            stripe_y = win_y + win_h * 0.45
            p.setPen(QPen(QColor(190, 170, 90), 3))
            p.drawLine(QPointF(win_x + 6, stripe_y),
                       QPointF(win_x + win_w - 6, stripe_y))

        # Bottom frame — console area
        console_h = vh * 0.22
        console_grad = QLinearGradient(0, vy + vh - console_h, 0, vy + vh)
        console_grad.setColorAt(0.0, QColor(55, 52, 48))
        console_grad.setColorAt(0.3, QColor(70, 68, 62))
        console_grad.setColorAt(1.0, QColor(50, 48, 42))
        p.setBrush(QBrush(console_grad))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawRect(QRectF(vx, vy + vh - console_h, vw, console_h))

        # Cylindrical structural tube (right of console) — visible in video
        tube_x = vx + vw * 0.58
        tube_w = 28
        tube_grad = QLinearGradient(tube_x, 0, tube_x + tube_w, 0)
        tube_grad.setColorAt(0.0, QColor(140, 135, 128))
        tube_grad.setColorAt(0.4, QColor(180, 175, 165))
        tube_grad.setColorAt(1.0, QColor(120, 115, 108))
        p.setBrush(QBrush(tube_grad))
        p.drawRect(QRectF(tube_x, vy + vh * 0.35, tube_w,
                          vh * 0.65))

        # --- Driver's console panel ---
        self._draw_console_panel(p, vx + 20, vy + vh - console_h + 12,
                                 min(vw * 0.40, 320),
                                 console_h - 24)

        # --- Status text overlays ---
        p.setPen(QPen(QColor(200, 210, 220)))
        p.setFont(QFont("Consolas", 10))
        # Speed
        v_text = f"{abs(tr.v):.1f} m/s  ({abs(tr.v)*3.6:.0f} km/h)"
        p.drawText(QRectF(vx + vw * 0.62, vy + 15, 200, 20),
                   int(Qt.AlignmentFlag.AlignRight), v_text)
        # Position
        alt = ALT_LOW + (tr.s / LENGTH) * DROP
        pos_text = f"{tr.s:.0f}/{LENGTH:.0f} m  alt {alt:.0f} m"
        p.drawText(QRectF(vx + vw * 0.62, vy + 33, 200, 20),
                   int(Qt.AlignmentFlag.AlignRight), pos_text)
        # View mode label
        p.setPen(QPen(QColor(180, 190, 200, 160)))
        p.setFont(QFont("Consolas", 9))
        p.drawText(QRectF(vx + 55, vy + 5, 200, 16),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("CABIN VIEW [F4]", "VUE CABINE [F4]"))

        p.restore()

    def _draw_console_panel(self, p: QPainter, x: float, y: float,
                            pw: float, ph: float) -> None:
        """Draw the Von Roll driver's console panel.

        Based on HD frames of the real console (t=88-490 of FUNI284 montée):
        - Red mushroom E-STOP button (far left)
        - Colour LCD screen showing track schematic
        - ~10 illuminated push-buttons in 2 rows (green LEDs)
        - Rotary speed-command knob
        """
        st = self.state
        tr = st.train

        # Panel background
        p.setPen(QPen(QColor(30, 30, 30), 1))
        p.setBrush(QBrush(QColor(25, 25, 28)))
        p.drawRoundedRect(QRectF(x, y, pw, ph), 4, 4)

        # Metallic bezel
        p.setPen(QPen(QColor(90, 88, 82), 1.5))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawRoundedRect(QRectF(x - 1, y - 1, pw + 2, ph + 2), 5, 5)

        # --- E-STOP mushroom button (left) ---
        estop_x = x + 14
        estop_y = y + ph * 0.35
        estop_r = min(ph * 0.22, 14)
        # Yellow ring
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QBrush(QColor(180, 170, 30)))
        p.drawEllipse(QPointF(estop_x, estop_y), estop_r + 3, estop_r + 3)
        # Red mushroom cap
        estop_active = tr.emergency
        cap_col = QColor(220, 40, 30) if not estop_active else QColor(140, 20, 15)
        grad_e = QRadialGradient(estop_x - 2, estop_y - 2, estop_r)
        grad_e.setColorAt(0, cap_col.lighter(140))
        grad_e.setColorAt(1, cap_col)
        p.setBrush(QBrush(grad_e))
        p.drawEllipse(QPointF(estop_x, estop_y), estop_r, estop_r)

        # --- LCD screen (track position schematic) ---
        lcd_x = x + 36
        lcd_y = y + 6
        lcd_w = min(pw * 0.30, 90)
        lcd_h = ph - 12
        # Screen bezel
        p.setPen(QPen(QColor(50, 50, 50), 1))
        p.setBrush(QBrush(QColor(15, 25, 40)))
        p.drawRect(QRectF(lcd_x, lcd_y, lcd_w, lcd_h))

        # Draw track position on LCD
        if lcd_w > 30 and lcd_h > 20:
            p.setPen(QPen(QColor(80, 180, 80), 1))
            # Track line (vertical on LCD = slope)
            track_x = lcd_x + lcd_w * 0.5
            track_top = lcd_y + 4
            track_bot = lcd_y + lcd_h - 4
            p.drawLine(QPointF(track_x, track_top),
                       QPointF(track_x, track_bot))
            # Train position marker
            frac = tr.s / LENGTH
            marker_y = track_bot - frac * (track_bot - track_top)
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(QColor(255, 220, 50)))
            p.drawRect(QRectF(track_x - 4, marker_y - 2, 8, 4))
            # Passing loop marker
            loop_frac = (PASSING_START + PASSING_END) / 2 / LENGTH
            loop_y = track_bot - loop_frac * (track_bot - track_top)
            p.setPen(QPen(QColor(80, 180, 80), 1))
            p.drawLine(QPointF(track_x - 6, loop_y),
                       QPointF(track_x + 6, loop_y))
            # Speed text
            p.setPen(QPen(QColor(60, 200, 60)))
            p.setFont(QFont("Consolas", 7))
            p.drawText(QRectF(lcd_x + 2, lcd_y + 2, lcd_w - 4, 12),
                       int(Qt.AlignmentFlag.AlignLeft),
                       f"{abs(tr.v):.1f} m/s")

        # --- Push-buttons (2 rows × 4-5 buttons) ---
        btn_area_x = lcd_x + lcd_w + 8
        btn_area_w = pw - (btn_area_x - x) - 10
        if btn_area_w > 40:
            btn_cols = 4
            btn_rows = 2
            btn_size = min(btn_area_w / btn_cols - 3,
                          (ph - 16) / btn_rows - 3, 14)
            btn_gap = btn_size + 3

            # Button states (green = active, grey = inactive)
            btn_states = [
                tr.v > 0.1,                     # traction
                True,                            # system OK
                not tr.electric_stop,            # no E-stop
                not tr.doors_open,               # doors closed
                tr.lights_head,                  # headlights
                tr.lights_cabin,                 # cabin lights
                not tr.emergency,                # no emergency
                st.trip_started,                 # trip active
            ]

            for row in range(btn_rows):
                for col in range(btn_cols):
                    idx = row * btn_cols + col
                    bx = btn_area_x + col * btn_gap
                    by = y + 8 + row * btn_gap
                    active = btn_states[idx] if idx < len(btn_states) else False

                    # Button body
                    p.setPen(QPen(QColor(60, 60, 60), 0.5))
                    p.setBrush(QBrush(QColor(45, 45, 48)))
                    p.drawRoundedRect(QRectF(bx, by, btn_size, btn_size), 2, 2)
                    # LED indicator
                    led_r = btn_size * 0.25
                    led_cx = bx + btn_size / 2
                    led_cy = by + btn_size / 2
                    if active:
                        led_grad = QRadialGradient(led_cx, led_cy, led_r)
                        led_grad.setColorAt(0, QColor(140, 255, 140))
                        led_grad.setColorAt(0.6, QColor(50, 200, 50))
                        led_grad.setColorAt(1, QColor(30, 120, 30))
                        p.setBrush(QBrush(led_grad))
                    else:
                        p.setBrush(QBrush(QColor(35, 40, 35)))
                    p.setPen(Qt.PenStyle.NoPen)
                    p.drawEllipse(QPointF(led_cx, led_cy), led_r, led_r)

        # --- Rotary speed-command knob ---
        knob_x = btn_area_x + btn_area_w * 0.5 if btn_area_w > 40 else x + pw - 25
        knob_y = y + ph - 18
        knob_r = 8
        # Knob body
        knob_grad = QRadialGradient(knob_x, knob_y, knob_r)
        knob_grad.setColorAt(0, QColor(90, 88, 82))
        knob_grad.setColorAt(1, QColor(50, 48, 42))
        p.setBrush(QBrush(knob_grad))
        p.setPen(QPen(QColor(30, 30, 30), 1))
        p.drawEllipse(QPointF(knob_x, knob_y), knob_r, knob_r)
        # Knob pointer (shows speed command %)
        cmd_frac = st.speed_cmd if hasattr(st, 'speed_cmd') else 0.0
        angle = -140 + cmd_frac * 280  # degrees
        rad = math.radians(angle - 90)
        ptr_len = knob_r * 0.7
        p.setPen(QPen(QColor(220, 220, 220), 1.5))
        p.drawLine(QPointF(knob_x, knob_y),
                   QPointF(knob_x + ptr_len * math.cos(rad),
                           knob_y + ptr_len * math.sin(rad)))

    # ----- motor room inset -----------------------------------------------

    def _draw_motor_room(self, p: QPainter, rect: QRectF) -> None:
        """Cutaway view of the drive machinery at the upper station.

        Real layout : 3 × 800 kW DC motors drive, through a gear reducer,
        a pair of yellow Von Roll bull wheels — the drive sheave and a
        deflection sheave — around which the 52 mm Fatzer haul cable is
        wrapped in an omega pattern for maximum adhesion. Real sheave
        diameter ≈ 4.2 m (radius 2.1 m), producing ~54.5 rpm at the
        12 m/s regulator cap. Both wheels are painted Von Roll signal
        yellow in reality.

        The drawing rotates both wheels at the correct angular velocity
        ω = v / r and reverses on descent — it is the same single cable
        pulling one train up while the other slides down, so the two
        wheels always turn in step.
        """
        p.save()
        p.setBrush(QBrush(QColor(22, 28, 42, 240)))
        p.setPen(QPen(COLOR_HUD_BORDER, 2))
        p.drawRoundedRect(rect, 10, 10)
        p.setClipRect(rect)

        # Subtle interior backlight (concrete wall feel)
        bg = QLinearGradient(rect.x(), rect.y(),
                             rect.x(), rect.y() + rect.height())
        bg.setColorAt(0.0, QColor(32, 38, 54, 140))
        bg.setColorAt(1.0, QColor(12, 16, 24, 0))
        p.setBrush(QBrush(bg))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawRoundedRect(rect.adjusted(2, 16, -2, -2), 8, 8)

        # Header
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
        p.drawText(QRectF(rect.x() + 8, rect.y() + 4,
                          rect.width() - 16, 14),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Drive station — 3032 m",
                     "Machinerie — 3032 m"))
        p.drawText(QRectF(rect.x() + 8, rect.y() + 4,
                          rect.width() - 16, 14),
                   int(Qt.AlignmentFlag.AlignRight),
                   "3 × 800 kW DC")

        # --- Readouts: wheel diameter / RPM / cable speed -----------------
        # Placed right under the title so they stay readable — the
        # machinery drawing below never obscures them.
        v_abs = abs(self.state.train.v)
        rpm = v_abs / (2.0 * math.pi * 2.1) * 60.0
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 8))
        p.drawText(
            QRectF(rect.x() + 8, rect.y() + 18,
                   rect.width() - 16, 12),
            int(Qt.AlignmentFlag.AlignLeft),
            f"⌀ 4.2 m   {rpm:5.1f} rpm   v {v_abs:4.1f} m/s",
        )

        # Machinery floor
        floor_y = rect.y() + rect.height() - 16
        p.setBrush(QBrush(QColor(48, 52, 64)))
        p.setPen(QPen(QColor(18, 18, 22), 1))
        p.drawRect(QRectF(rect.x() + 4, floor_y, rect.width() - 8, 12))
        # Floor hatching (concrete)
        p.setPen(QPen(QColor(70, 74, 86), 1))
        for i in range(10):
            x = rect.x() + 6 + i * (rect.width() - 12) / 10
            p.drawLine(QPointF(x, floor_y + 2), QPointF(x + 4, floor_y + 10))

        # Load-tinted motor housing colour (blue → red as power rises)
        load = min(1.0, self.state.train.power_kw / (P_MAX / 1000.0))
        motor_body = QColor(
            int(70 + 150 * load),
            int(110 - 55 * load),
            int(155 - 90 * load),
        )

        # --- 3 DC motors on the left (stacked side-by-side) --------------
        m_w = 16
        m_h = 36
        for i in range(3):
            mx = rect.x() + 10 + i * (m_w + 4)
            my = floor_y - m_h
            # Shadow
            p.setBrush(QBrush(QColor(6, 8, 12, 170)))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawRoundedRect(QRectF(mx + 1, my + 2, m_w, m_h), 3, 3)
            # Body gradient (round motor casing)
            mg = QLinearGradient(mx, my, mx + m_w, my)
            mg.setColorAt(0.0, motor_body.darker(150))
            mg.setColorAt(0.5, motor_body.lighter(125))
            mg.setColorAt(1.0, motor_body.darker(165))
            p.setBrush(QBrush(mg))
            p.setPen(QPen(QColor(15, 15, 20), 1))
            p.drawRoundedRect(QRectF(mx, my, m_w, m_h), 3, 3)
            # Cooling fins
            p.setPen(QPen(QColor(18, 18, 22), 1))
            for k in range(5):
                fy = my + 4 + k * 6
                p.drawLine(QPointF(mx + 2, fy),
                           QPointF(mx + m_w - 2, fy))
            # Shaft cap at top
            p.setBrush(QBrush(QColor(190, 190, 200)))
            p.setPen(QPen(QColor(30, 30, 35), 1))
            p.drawEllipse(QPointF(mx + m_w / 2, my + 1), 3, 3)

        # --- Reduction gearbox -------------------------------------------
        gx = rect.x() + 74
        gy = floor_y - 30
        gw = 30
        gh = 30
        gg = QLinearGradient(gx, gy, gx, gy + gh)
        gg.setColorAt(0.0, QColor(110, 112, 126))
        gg.setColorAt(1.0, QColor(55, 58, 70))
        p.setBrush(QBrush(gg))
        p.setPen(QPen(QColor(18, 18, 22), 1.2))
        p.drawRoundedRect(QRectF(gx, gy, gw, gh), 3, 3)
        # Gear housing ribs
        p.setPen(QPen(QColor(25, 25, 30), 1))
        for k in range(4):
            p.drawLine(QPointF(gx + 4, gy + 5 + k * 7),
                       QPointF(gx + gw - 4, gy + 5 + k * 7))
        # Label plate
        p.setBrush(QBrush(QColor(230, 200, 60)))
        p.setPen(QPen(QColor(60, 40, 0), 0.8))
        p.drawRect(QRectF(gx + 6, gy + gh - 8, gw - 12, 6))

        # Thick motor-shaft coupling from gearbox to drive sheave
        shaft_y = gy + gh / 2 + 2
        p.setPen(QPen(QColor(150, 150, 160), 4))
        p.drawLine(QPointF(gx + gw, shaft_y),
                   QPointF(gx + gw + 26, shaft_y))

        # --- Two yellow Von Roll bull wheels ------------------------------
        # Real sheave: ⌀ 4.2 m. Spacing between axes ≈ 2.6 × R.
        R = 32.0
        cx1 = rect.x() + 152
        cx2 = cx1 + int(R * 2.6)   # ≈ cx1 + 83
        cy = floor_y - 52

        # Draw the drive shaft behind P1 first
        p.setPen(QPen(QColor(90, 92, 105), 5))
        p.drawLine(QPointF(gx + gw + 22, shaft_y),
                   QPointF(cx1 - R * 0.15, cy))
        p.setBrush(QBrush(QColor(60, 60, 70)))
        p.setPen(QPen(QColor(20, 20, 24), 1))
        p.drawRoundedRect(QRectF(gx + gw + 18, shaft_y - 4, 10, 10), 2, 2)

        # --- Axle support pedestals (behind wheels) -------------------------
        for cx in (cx1, cx2):
            ped = QRectF(cx - 18, cy + R * 0.1, 36, floor_y - (cy + R * 0.1))
            pg = QLinearGradient(ped.x(), ped.y(),
                                  ped.x(), ped.y() + ped.height())
            pg.setColorAt(0.0, QColor(80, 84, 100))
            pg.setColorAt(1.0, QColor(40, 44, 58))
            p.setBrush(QBrush(pg))
            p.setPen(QPen(QColor(20, 20, 24), 1))
            p.drawRect(ped)
            p.setBrush(QBrush(QColor(180, 180, 190)))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawEllipse(QPointF(cx - 12, ped.y() + ped.height() - 4), 1.5, 1.5)
            p.drawEllipse(QPointF(cx + 12, ped.y() + ped.height() - 4), 1.5, 1.5)

        # --- Haul cable figure-of-eight ---
        # Drawn as a single continuous QPainterPath so the joints between
        # the arcs and the tangent lines are smooth (no visible seams).
        cable_r = R + 2.0  # cable hugs the wheel rim closely
        angle = self._pulley_angle

        cable_shadow = QPen(QColor(5, 5, 10, 200), 5.0,
                            Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap,
                            Qt.PenJoinStyle.RoundJoin)
        cable_core = QPen(QColor(215, 218, 228), 2.4,
                          Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap,
                          Qt.PenJoinStyle.RoundJoin)

        # Internal tangent geometry — tangent lines connect the two
        # cable circles smoothly (same direction as the arc at the
        # tangent points, so no seam).
        half_d = (cx2 - cx1) / 2.0
        alpha = math.acos(cable_r / half_d)
        alpha_deg = math.degrees(alpha)
        cos_a = math.cos(alpha)
        sin_a = math.sin(alpha)

        # Tangent points on P1 (right side, facing P2)
        p1_up = QPointF(cx1 + cable_r * cos_a, cy - cable_r * sin_a)
        p1_dn = QPointF(cx1 + cable_r * cos_a, cy + cable_r * sin_a)
        # Tangent points on P2 (left side, facing P1)
        p2_up = QPointF(cx2 - cable_r * cos_a, cy - cable_r * sin_a)
        p2_dn = QPointF(cx2 - cable_r * cos_a, cy + cable_r * sin_a)

        r1 = QRectF(cx1 - cable_r, cy - cable_r, cable_r * 2, cable_r * 2)
        r2 = QRectF(cx2 - cable_r, cy - cable_r, cable_r * 2, cable_r * 2)

        # Single continuous path : P1 outer arc → CROSS 1 → P2 outer
        # arc → CROSS 2 → back to start (closed figure-8 loop).
        arc_span = -(360.0 - 2.0 * alpha_deg)  # CW
        figure8 = QPainterPath()
        figure8.moveTo(p1_dn)
        figure8.arcTo(r1, -alpha_deg, arc_span)                       # P1 CW
        figure8.lineTo(p2_dn)                                         # CROSS 1
        figure8.arcTo(r2, 180.0 + alpha_deg, -arc_span)               # P2 CCW
        figure8.lineTo(p1_dn)                                         # CROSS 2
        figure8.closeSubpath()

        # Draw figure-8 loop (behind wheels — cable hugs the rim)
        p.setBrush(Qt.BrushStyle.NoBrush)
        for pen in (cable_shadow, cable_core):
            p.setPen(pen)
            p.drawPath(figure8)

        # Draw bull wheels on top — cover the interior part of the loop,
        # leaving only the outer 2 px crescent visible (the cable on
        # the rim).  Tangent crosses are outside both wheels so they
        # stay fully visible.
        self._draw_bullwheel(p, cx1, cy, R, angle, drive=True)
        self._draw_bullwheel(p, cx2, cy, R, -angle, drive=False)

        # Entry and exit cables — vertical strands from floor to the
        # bottom of each cable circle (tangent 270° point, on the arc).
        for pen in (cable_shadow, cable_core):
            p.setPen(pen)
            p.drawLine(QPointF(cx1, floor_y + 1),
                       QPointF(cx1, cy + cable_r))
            p.drawLine(QPointF(cx2, cy + cable_r),
                       QPointF(cx2, floor_y + 1))

        # --- Moving mark on the cable ---
        # Advances along the figure-8 loop at cable speed = ω × cable_r.
        # Makes it visually obvious the cable is moving (and which way).
        path_len = figure8.length()
        if path_len > 0:
            dist = self._pulley_angle * cable_r
            t = (dist % path_len) / path_len
            mark_pt = figure8.pointAtPercent(t)
            p.setBrush(QBrush(QColor(20, 20, 28)))
            p.setPen(QPen(QColor(240, 240, 245), 0.8))
            p.drawEllipse(mark_pt, 3.0, 3.0)

        # Power LED — green → red with load
        led_col = QColor(
            int(100 + 155 * load),
            int(220 - 160 * load),
            80,
        )
        p.setBrush(QBrush(led_col))
        p.setPen(QPen(QColor(10, 10, 10), 1))
        p.drawEllipse(
            QPointF(rect.x() + rect.width() - 12, rect.y() + 12), 3.5, 3.5,
        )

        p.restore()

    def _draw_bullwheel(
        self,
        p: QPainter,
        cx: float,
        cy: float,
        r: float,
        angle_rad: float,
        drive: bool = False,
    ) -> None:
        """Draw a single Von Roll signal-yellow bull wheel (spoked sheave).

        The wheel is a disc with a darker sheave groove ring on its rim,
        a bright yellow plate face, 6 rotating spokes and a central hub.
        When *drive* is True a short protruding axle stub is drawn on the
        left edge to suggest the motor shaft coupling.
        """
        p.save()

        # Drop shadow
        p.setBrush(QBrush(QColor(0, 0, 0, 150)))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawEllipse(QPointF(cx + 1.5, cy + 3), r + 1, r + 1)

        # Outer rim (darker yellow edge with sheave groove suggestion)
        rim_grad = QRadialGradient(
            QPointF(cx - r * 0.30, cy - r * 0.32), r * 1.7,
        )
        rim_grad.setColorAt(0.0, QColor(255, 230, 90))
        rim_grad.setColorAt(0.55, QColor(225, 170, 25))
        rim_grad.setColorAt(1.0, QColor(120, 82, 0))
        p.setBrush(QBrush(rim_grad))
        p.setPen(QPen(QColor(60, 42, 0), 1.5))
        p.drawEllipse(QPointF(cx, cy), r, r)

        # Sheave groove — concentric darker line
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.setPen(QPen(QColor(110, 75, 0), 1.3))
        p.drawEllipse(QPointF(cx, cy), r - 2.6, r - 2.6)
        p.setPen(QPen(QColor(60, 42, 0), 0.8))
        p.drawEllipse(QPointF(cx, cy), r - 5.0, r - 5.0)

        # Inner plate (bright yellow face)
        plate_grad = QRadialGradient(
            QPointF(cx - r * 0.25, cy - r * 0.25), r,
        )
        plate_grad.setColorAt(0.0, QColor(255, 225, 75))
        plate_grad.setColorAt(1.0, QColor(195, 145, 15))
        p.setBrush(QBrush(plate_grad))
        p.setPen(QPen(QColor(90, 60, 5), 1))
        p.drawEllipse(QPointF(cx, cy), r * 0.82, r * 0.82)

        # Rotating spokes + hub — rotate coordinate frame here
        p.save()
        p.translate(cx, cy)
        p.rotate(math.degrees(angle_rad))
        # Five spokes (odd count avoids aliasing illusions at high speed)
        for k in range(5):
            ang = k * (2.0 * math.pi / 5.0)
            cosA, sinA = math.cos(ang), math.sin(ang)
            x1 = cosA * (r * 0.18)
            y1 = sinA * (r * 0.18)
            x2 = cosA * (r * 0.78)
            y2 = sinA * (r * 0.78)
            # Spoke body
            p.setPen(QPen(QColor(140, 95, 0), 4,
                          Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))
            # Highlight
            p.setPen(QPen(QColor(255, 220, 60), 1.5,
                          Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))
            # Red tip on first spoke — rotation direction reference
            if k == 0:
                p.setPen(QPen(QColor(220, 60, 40), 3.5,
                              Qt.PenStyle.SolidLine,
                              Qt.PenCapStyle.RoundCap))
                p.drawPoint(QPointF(x2, y2))
        # Central hub
        p.setBrush(QBrush(QColor(75, 78, 92)))
        p.setPen(QPen(QColor(18, 18, 22), 1.5))
        p.drawEllipse(QPointF(0, 0), r * 0.19, r * 0.19)
        p.setBrush(QBrush(QColor(200, 200, 210)))
        p.setPen(QPen(QColor(40, 40, 45), 0.8))
        p.drawEllipse(QPointF(0, 0), r * 0.08, r * 0.08)
        p.restore()

        # Protruding drive axle stub on the drive wheel (static, outside rot.)
        if drive:
            p.setBrush(QBrush(QColor(160, 160, 170)))
            p.setPen(QPen(QColor(25, 25, 30), 1))
            p.drawRect(QRectF(cx - r - 4, cy - 3, 6, 6))

        p.restore()

    # ----- mini-map --------------------------------------------------------

    def _draw_minimap(self, p: QPainter, rect: QRectF) -> None:
        """Full-length mini-map showing both trains' positions."""
        st = self.state
        tr = st.train
        p.save()
        p.setBrush(QBrush(QColor(18, 24, 36, 220)))
        p.setPen(QPen(COLOR_HUD_BORDER, 1))
        p.drawRoundedRect(rect, 4, 4)

        # Track line
        pad = 8
        track_y = rect.y() + rect.height() / 2
        track_x0 = rect.x() + pad
        track_x1 = rect.x() + rect.width() - pad
        track_w = track_x1 - track_x0
        p.setPen(QPen(QColor(140, 150, 170), 2))
        p.drawLine(QPointF(track_x0, track_y), QPointF(track_x1, track_y))

        # Passing loop zone
        ps = track_x0 + track_w * (PASSING_START / LENGTH)
        pe = track_x0 + track_w * (PASSING_END / LENGTH)
        p.setPen(QPen(QColor(255, 200, 80), 3))
        p.drawLine(QPointF(ps, track_y - 3), QPointF(pe, track_y - 3))
        p.drawLine(QPointF(ps, track_y + 3), QPointF(pe, track_y + 3))

        # Stations
        p.setBrush(QBrush(COLOR_TEXT))
        p.setPen(QPen(QColor(40, 40, 40), 1))
        p.drawRect(QRectF(track_x0 - 3, track_y - 5, 6, 10))
        p.drawRect(QRectF(track_x1 - 3, track_y - 5, 6, 10))

        # Main train
        mx = track_x0 + track_w * (tr.s / LENGTH)
        p.setBrush(QBrush(COLOR_CABIN))
        p.setPen(QPen(QColor(60, 40, 0), 1))
        p.drawEllipse(QPointF(mx, track_y), 5, 5)
        # Ghost train
        gx = track_x0 + track_w * (st.ghost_s / LENGTH)
        p.setBrush(QBrush(COLOR_GHOST))
        p.drawEllipse(QPointF(gx, track_y), 5, 5)

        # Labels
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 8))
        p.drawText(QPointF(track_x0 - 4, rect.y() + 10), "2111")
        p.drawText(QPointF(track_x1 - 18, rect.y() + 10), "3032")
        p.restore()

    def _draw_planview(self, p: QPainter, rect: QRectF) -> None:
        """Bird's-eye plan view of the tunnel route with curves and trains."""
        st = self.state
        tr = st.train
        p.save()
        p.setBrush(QBrush(QColor(18, 24, 36, 220)))
        p.setPen(QPen(COLOR_HUD_BORDER, 1))
        p.drawRoundedRect(rect, 6, 6)
        p.setClipRect(rect)

        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
        p.drawText(QRectF(rect.x() + 6, rect.y() + 2, rect.width() - 12, 14),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Plan view — tunnel route", "Vue en plan — tracé du tunnel"))

        # Compute plan bounds and a scale that fits with margin
        px_min, px_max, py_min, py_max = PLAN_BOUNDS
        span_x = max(px_max - px_min, 1.0)
        span_y = max(py_max - py_min, 1.0)
        pad = 14
        avail_w = rect.width() - 2 * pad
        avail_h = rect.height() - 24 - pad
        scale = min(avail_w / span_x, avail_h / span_y)
        # Centre in rect
        used_w = span_x * scale
        used_h = span_y * scale
        origin_x = rect.x() + pad + (avail_w - used_w) / 2
        origin_y = rect.y() + 20 + (avail_h - used_h) / 2

        def to_screen(px: float, py: float) -> QPointF:
            return QPointF(
                origin_x + (px - px_min) * scale,
                origin_y + (py_max - py) * scale,   # flip Y (north up)
            )

        # Route polyline — sample every ~20 m
        route = QPolygonF()
        step = max(1, int(20.0 / _GEOM_DS))
        for i in range(0, len(_GEOM), step):
            r = _GEOM[i]
            route.append(to_screen(r[3], r[4]))
        route.append(to_screen(_GEOM[-1][3], _GEOM[-1][4]))

        # Tunnel shadow
        p.setPen(QPen(QColor(60, 70, 90), 6, Qt.PenStyle.SolidLine,
                      Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        p.drawPolyline(route)
        # Tunnel inner
        p.setPen(QPen(QColor(150, 160, 185), 3, Qt.PenStyle.SolidLine,
                      Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        p.drawPolyline(route)

        # Passing loop: draw the two parallel tracks as a small bump offset
        # perpendicular to the route around PASSING_START..PASSING_END
        ploop = []
        for i, r in enumerate(_GEOM):
            if PASSING_START - 10 <= r[0] <= PASSING_END + 10:
                ploop.append(r)
        if len(ploop) >= 2:
            loop_poly_a = QPolygonF()
            loop_poly_b = QPolygonF()
            for j, r in enumerate(ploop):
                if j == 0:
                    nxt = ploop[1]
                elif j == len(ploop) - 1:
                    nxt = ploop[j]
                    prv = ploop[j - 1]
                    dxp = nxt[3] - prv[3]
                    dyp = nxt[4] - prv[4]
                else:
                    nxt = ploop[j + 1]
                if j == 0:
                    dxp = ploop[1][3] - ploop[0][3]
                    dyp = ploop[1][4] - ploop[0][4]
                elif j < len(ploop) - 1:
                    dxp = ploop[j + 1][3] - ploop[j - 1][3]
                    dyp = ploop[j + 1][4] - ploop[j - 1][4]
                ln = math.hypot(dxp, dyp) or 1.0
                perp_x = -dyp / ln
                perp_y = dxp / ln
                off_m = 6.0   # 6 m lateral separation in plan view
                loop_poly_a.append(to_screen(r[3] + perp_x * off_m,
                                             r[4] + perp_y * off_m))
                loop_poly_b.append(to_screen(r[3] - perp_x * off_m,
                                             r[4] - perp_y * off_m))
            p.setPen(QPen(QColor(255, 200, 80), 2))
            p.drawPolyline(loop_poly_a)
            p.drawPolyline(loop_poly_b)

        # Stations
        low = _GEOM[0]
        high = _GEOM[-1]
        p.setBrush(QBrush(QColor(220, 220, 230)))
        p.setPen(QPen(QColor(40, 40, 50), 1))
        for r, tag in ((low, "V"), (high, "G")):
            pt = to_screen(r[3], r[4])
            p.drawRect(QRectF(pt.x() - 4, pt.y() - 4, 8, 8))
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.setFont(QFont("Consolas", 7))
            p.drawText(QPointF(pt.x() + 6, pt.y() + 3), tag)
            p.setPen(QPen(QColor(40, 40, 50), 1))

        # Trains
        tp = plan_at(tr.s)
        gp = plan_at(st.ghost_s)
        pt_m = to_screen(tp[0], tp[1])
        pt_g = to_screen(gp[0], gp[1])
        p.setBrush(QBrush(COLOR_CABIN))
        p.setPen(QPen(QColor(60, 40, 0), 1))
        p.drawEllipse(pt_m, 4, 4)
        p.setBrush(QBrush(COLOR_GHOST))
        p.drawEllipse(pt_g, 4, 4)

        # North indicator
        nx = rect.x() + rect.width() - 16
        ny = rect.y() + 26
        p.setPen(QPen(QColor(220, 230, 255), 1.4))
        p.drawLine(QPointF(nx, ny + 8), QPointF(nx, ny - 8))
        p.drawLine(QPointF(nx, ny - 8), QPointF(nx - 3, ny - 4))
        p.drawLine(QPointF(nx, ny - 8), QPointF(nx + 3, ny - 4))
        p.setFont(QFont("Consolas", 7))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QPointF(nx - 3, ny + 18), "N")
        p.restore()

    def _draw_station(self, p: QPainter, pos: QPointF, name: str, alt: str, up: bool) -> None:
        w = 70
        h = 36
        x = pos.x() - w / 2
        y = pos.y() - h
        p.setBrush(QBrush(QColor(140, 150, 170)))
        p.setPen(QPen(QColor(40, 40, 50), 1))
        p.drawRect(QRectF(x, y, w, h))
        p.setBrush(QBrush(QColor(90, 60, 40)))
        roof = QPolygonF([QPointF(x - 4, y), QPointF(x + w + 4, y), QPointF(x + w / 2, y - 14)])
        p.drawPolygon(roof)
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
        p.drawText(QPointF(x, y + h + 14), f"{name}  {alt}")

    def _draw_cabin(
        self,
        p: QPainter,
        world_to_screen,
        xm: float,
        ym: float,
        s_pos: float,
        color: QColor,
        label: str,
    ) -> None:
        """Draw a faux-3D cylindrical funicular train (2 coupled cars).

        The Perce-Neige trains are 31.6 m long, cylindrical Ø 3.60 m, with
        two articulated cars — yellow "space capsule" look.
        """
        g = gradient_at(max(0.0, min(LENGTH, s_pos)))
        theta = math.atan(g)
        # Visual exaggeration: real train is 31.6 m but at the profile's
        # scale that would be ~26 px — invisible detail. Draw 1.6× larger.
        total_len_m = 50.0
        car_len_m = total_len_m / 2.0

        def slope_pt(offset_m: float) -> QPointF:
            x = xm + offset_m * math.cos(theta)
            y = ym + offset_m * math.sin(theta)
            return world_to_screen(x, y)

        centers = [
            slope_pt(-car_len_m / 2 - car_len_m / 2 + car_len_m / 2),   # = -car/2
            slope_pt(+car_len_m / 2),
        ]
        # Actually just draw 2 cars:
        centers = [slope_pt(-car_len_m / 2), slope_pt(+car_len_m / 2)]

        # Compute axis direction on screen from first to last point
        p_head = slope_pt(-total_len_m / 2)
        p_tail = slope_pt(+total_len_m / 2)
        dx = p_tail.x() - p_head.x()
        dy = p_tail.y() - p_head.y()
        length_px = math.hypot(dx, dy)
        if length_px < 2:
            return
        ux, uy = dx / length_px, dy / length_px
        nx, ny = -uy, ux                   # normal (perpendicular) to axis

        car_len_px = length_px / 2.0
        thickness = max(10.0, length_px * 0.35)   # faux-3D height, scaled

        # Cable visible between cars along the tunnel
        p.setPen(QPen(QColor(200, 200, 210), 1.2))
        p.drawLine(p_head, p_tail)

        # Draw each car
        for idx, c in enumerate(centers):
            self._draw_cylinder_car(p, c, ux, uy, nx, ny,
                                    car_len_px * 0.92, thickness, color,
                                    car_index=idx)

        # Coupling between the two cars
        p.setPen(QPen(QColor(40, 40, 40), 2))
        p.drawLine(
            QPointF(centers[0].x() + ux * car_len_px * 0.48,
                    centers[0].y() + uy * car_len_px * 0.48),
            QPointF(centers[1].x() - ux * car_len_px * 0.48,
                    centers[1].y() - uy * car_len_px * 0.48),
        )

        # Label above
        mid = QPointF((p_head.x() + p_tail.x()) / 2,
                      (p_head.y() + p_tail.y()) / 2)
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Consolas", 8, QFont.Weight.Bold))
        p.drawText(QPointF(mid.x() + nx * 22 - 28,
                           mid.y() + ny * 22 - 4), label)

    def _draw_cylinder_car(
        self,
        p: QPainter,
        center: QPointF,
        ux: float, uy: float,
        nx: float, ny: float,
        length_px: float,
        thickness: float,
        color: QColor,
        car_index: int = 0,
    ) -> None:
        """Draw one clean cylindrical car matching the logo style.

        Clean yellow cylindrical body, prominent dome end caps, a row of
        blue rectangular windows, and a highlight strip — no structural
        arches.  Doors and headlights preserved for game mechanics.
        """
        half = length_px / 2.0
        t = thickness
        # Front / back of car along axis
        p0 = QPointF(center.x() - ux * half, center.y() - uy * half)
        p1 = QPointF(center.x() + ux * half, center.y() + uy * half)

        # Cylindrical body — uniform thickness (logo style, not ovoid)
        body = QPolygonF([
            QPointF(p0.x() + nx * t, p0.y() + ny * t),
            QPointF(p1.x() + nx * t, p1.y() + ny * t),
            QPointF(p1.x() - nx * t, p1.y() - ny * t),
            QPointF(p0.x() - nx * t, p0.y() - ny * t),
        ])
        # Shading gradient perpendicular to axis (light on top, shadow below)
        top = QPointF(center.x() + nx * t, center.y() + ny * t)
        bot = QPointF(center.x() - nx * t, center.y() - ny * t)
        grad = QLinearGradient(top, bot)
        grad.setColorAt(0.0, color.lighter(140))
        grad.setColorAt(0.40, color)
        grad.setColorAt(1.0, color.darker(160))
        p.setBrush(QBrush(grad))
        p.setPen(QPen(QColor(120, 80, 0), 1.5))
        p.drawPolygon(body)

        # End caps (prominent dome ellipses — logo style)
        cap_rx = max(3.0, t * 0.55)
        cap_ry = t
        for pt in (p0, p1):
            cap = QRectF(pt.x() - cap_rx, pt.y() - cap_ry,
                         cap_rx * 2, cap_ry * 2)
            grad_cap = QLinearGradient(
                QPointF(pt.x() + nx * t, pt.y() + ny * t),
                QPointF(pt.x() - nx * t, pt.y() - ny * t))
            grad_cap.setColorAt(0.0, color.lighter(125))
            grad_cap.setColorAt(1.0, color.darker(170))
            p.setBrush(QBrush(grad_cap))
            p.setPen(QPen(QColor(100, 60, 0), 1.2))
            p.drawEllipse(cap)

        # Highlight reflection strip along top of body (logo style)
        hl_offset = t * 0.55
        hl0 = QPointF(p0.x() + nx * hl_offset + ux * 4,
                      p0.y() + ny * hl_offset + uy * 4)
        hl1 = QPointF(p1.x() + nx * hl_offset - ux * 4,
                      p1.y() + ny * hl_offset - uy * 4)
        p.setPen(QPen(QColor(255, 255, 220, 180), max(1.4, t * 0.06)))
        p.drawLine(hl0, hl1)

        # Headlight on the outer end of each car
        outer_pt = p0 if car_index == 0 else p1
        hl_cx = outer_pt.x() + nx * (t * 0.3)
        hl_cy = outer_pt.y() + ny * (t * 0.3)
        if self.state.train.lights_head:
            p.setBrush(QBrush(QColor(255, 255, 200)))
        else:
            p.setBrush(QBrush(QColor(80, 80, 70)))
        p.setPen(QPen(QColor(40, 40, 30), 0.6))
        p.drawEllipse(QPointF(hl_cx, hl_cy), 1.8, 1.8)

        # Window strip — 5 clean blue windows (logo style)
        n_windows = 5
        win_h = t * 0.7
        win_spacing = length_px / (n_windows + 1)
        win_w_px = win_spacing * 0.6
        for i in range(n_windows):
            frac = (i + 1.0) / (n_windows + 1.0)
            cx = p0.x() + ux * length_px * frac
            cy = p0.y() + uy * length_px * frac
            corners = [
                QPointF(cx + ux * (-win_w_px / 2) + nx * (-win_h / 2),
                        cy + uy * (-win_w_px / 2) + ny * (-win_h / 2)),
                QPointF(cx + ux * (+win_w_px / 2) + nx * (-win_h / 2),
                        cy + uy * (+win_w_px / 2) + ny * (-win_h / 2)),
                QPointF(cx + ux * (+win_w_px / 2) + nx * (+win_h / 2),
                        cy + uy * (+win_w_px / 2) + ny * (+win_h / 2)),
                QPointF(cx + ux * (-win_w_px / 2) + nx * (+win_h / 2),
                        cy + uy * (-win_w_px / 2) + ny * (+win_h / 2)),
            ]
            p.setBrush(QBrush(QColor(120, 200, 240)))
            p.setPen(QPen(QColor(20, 20, 30), 0.8))
            p.drawPolygon(QPolygonF(corners))

        # Doors — vertical sliding, located at 1/3 and 2/3 of car length
        tr_d = self.state.train
        doors_open = tr_d.doors_open
        door_transitioning = tr_d.doors_timer > 0.0
        if door_transitioning:
            door_color = QColor(240, 180, 40)
            door_edge = QColor(70, 45, 0)
        else:
            door_color = QColor(80, 200, 120) if doors_open else QColor(210, 140, 20)
            door_edge = QColor(30, 60, 20) if doors_open else QColor(60, 30, 0)
        dw = win_spacing * 0.5
        dh = t * 1.35
        for di in range(DOORS_PER_CAR):
            frac = (di + 1) / (DOORS_PER_CAR + 1)
            door_cx = p0.x() + ux * length_px * frac
            door_cy = p0.y() + uy * length_px * frac
            door = QPolygonF([
                QPointF(door_cx + ux * (-dw / 2) + nx * (-dh / 2),
                        door_cy + uy * (-dw / 2) + ny * (-dh / 2)),
                QPointF(door_cx + ux * (+dw / 2) + nx * (-dh / 2),
                        door_cy + uy * (+dw / 2) + ny * (-dh / 2)),
                QPointF(door_cx + ux * (+dw / 2) + nx * (+dh / 2),
                        door_cy + uy * (+dw / 2) + ny * (+dh / 2)),
                QPointF(door_cx + ux * (-dw / 2) + nx * (+dh / 2),
                        door_cy + uy * (-dw / 2) + ny * (+dh / 2)),
            ])
            p.setBrush(QBrush(door_color))
            p.setPen(QPen(door_edge, 1.0))
            p.drawPolygon(door)
            # Vertical split line for the double door
            p.setPen(QPen(door_edge, 0.8))
            p.drawLine(
                QPointF(door_cx + nx * (-dh / 2),
                        door_cy + ny * (-dh / 2)),
                QPointF(door_cx + nx * (+dh / 2),
                        door_cy + ny * (+dh / 2)),
            )

    # ----- HUD -------------------------------------------------------------

    def _draw_hud(self, p: QPainter, rect: QRectF) -> None:
        st = self.state
        tr = st.train
        # Reset hit zones for this frame — repopulated below as we draw
        # each clickable control.
        self._hit_zones = []
        p.setBrush(QBrush(COLOR_HUD_BG))
        p.setPen(QPen(COLOR_HUD_BORDER, 2))
        p.drawRoundedRect(rect, 10, 10)

        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 13, QFont.Weight.DemiBold))
        p.drawText(QRectF(rect.x() + 14, rect.y() + 10, rect.width() - 28, 22),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Control panel", "Pupitre de conduite"))

        # Speedometer (top) — main unit m/s, sub-label shows km/h equivalent
        speed_rect = QRectF(rect.x() + 20, rect.y() + 40, 160, 160)
        self._draw_gauge(
            p, speed_rect,
            value=abs(tr.v),
            maxv=15.0,
            label=f"m/s  ({abs(tr.v) * 3.6:4.1f} km/h)",
            big_text=f"{abs(tr.v):4.1f}",
            warn=V_MAX,
            crit=V_MAX + 1.0,
        )

        # Tension gauge
        ten_rect = QRectF(rect.x() + 200, rect.y() + 40, 160, 160)
        self._draw_gauge(
            p, ten_rect,
            value=tr.tension_dan_disp,
            maxv=40000.0,
            label="daN",
            big_text=f"{tr.tension_dan_disp:6.0f}",
            warn=T_NOMINAL_DAN,
            crit=T_WARN_DAN,
            title=T("Cable", "Câble"),
        )

        # Vertical bars : speed command, brake, power
        bar_y = rect.y() + 210
        speed_bar_rect = QRectF(rect.x() + 20, bar_y, 110, 22)
        brake_bar_rect = QRectF(rect.x() + 140, bar_y, 110, 22)
        self._draw_bar(p, rect.x() + 20, bar_y, 110, 22,
                       tr.speed_cmd, 1.0, T("Speed cmd", "Consigne"),
                       COLOR_GOOD, f"{int(tr.speed_cmd * 100):3d}%")
        self._draw_bar(p, rect.x() + 140, bar_y, 110, 22,
                       tr.brake, 1.0, T("Brake", "Frein"),
                       COLOR_WARN if not tr.emergency else COLOR_ALARM,
                       "URG!" if tr.emergency else f"{int(tr.brake * 100):3d}%")
        self._draw_bar(p, rect.x() + 260, bar_y, 110, 22,
                       tr.power_kw_disp, P_MAX / 1000.0, T("Power", "Puissance"),
                       QColor(120, 180, 240), f"{int(tr.power_kw_disp):4d} kW")

        # --- Click controls for the speed command + brake (mouse only) ----
        # Small ▼ − / + ▲ arrow buttons under the speed bar, and a BRAKE
        # hold button under the brake bar. Click-and-hold for realistic
        # ramped behaviour (same as keyboard).
        click_y = bar_y + 24
        click_h = 22
        self._draw_touch_button(
            p, QRectF(rect.x() + 20, click_y, 30, click_h),
            "−", QColor(120, 180, 255),
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 20, click_y, 30, click_h),
             int(Qt.Key.Key_Down), True)
        )
        self._draw_touch_button(
            p, QRectF(rect.x() + 52, click_y, 30, click_h),
            "+", QColor(120, 220, 160),
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 52, click_y, 30, click_h),
             int(Qt.Key.Key_Up), True)
        )
        # STOP quick-cut button : click zeroes the speed setpoint.
        self._draw_touch_button(
            p, QRectF(rect.x() + 84, click_y, 46, click_h),
            T("STOP", "ARRÊT"), QColor(220, 180, 80),
            font_pt=9,
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 84, click_y, 46, click_h),
             int(Qt.Key.Key_0), False)
        )
        # BRAKE hold button under the brake bar.
        self._draw_touch_button(
            p, QRectF(rect.x() + 140, click_y, 110, click_h),
            T("BRAKE hold", "FREIN maintenu"),
            QColor(240, 160, 80) if not tr.brake > 0.02 else QColor(255, 120, 80),
            font_pt=9,
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 140, click_y, 110, click_h),
             int(Qt.Key.Key_Space), True)
        )
        # Emergency-shift hold under the power bar.
        self._draw_touch_button(
            p, QRectF(rect.x() + 260, click_y, 110, click_h),
            T("E-BRAKE hold", "URGENCE maintenu"),
            QColor(255, 80, 80),
            font_pt=9,
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 260, click_y, 110, click_h),
             int(Qt.Key.Key_Shift), True)
        )

        # --- Departure protocol pads (READY / START) ----------------------
        # A second click row dedicated to the start-up sequence.
        dep_y = click_y + click_h + 4
        dep_h = 22
        # READY [V] — latches the "own cabin ready" flag. Colour changes
        # with the state machine: dim when idle, amber while waiting for
        # the other cabin, green once both cabins are ready.
        if tr.ready and st.ghost_ready:
            ready_col = QColor(80, 220, 120)
            ready_lbl = T("READY [V] ✓✓", "PRÊT [V] ✓✓")
        elif tr.ready:
            ready_col = QColor(240, 200, 60)
            ready_lbl = T("READY [V] …", "PRÊT [V] …")
        else:
            ready_col = QColor(140, 160, 190)
            ready_lbl = T("READY [V]", "PRÊT [V]")
        self._draw_touch_button(
            p, QRectF(rect.x() + 20, dep_y, 170, dep_h),
            ready_lbl, ready_col, font_pt=10,
        )
        self._hit_zones.append(
            (QRectF(rect.x() + 20, dep_y, 170, dep_h),
             int(Qt.Key.Key_V), False)
        )
        # START [Z] — greyed while the two-cabin handshake is incomplete
        # or the trip already began, green and active once authorised.
        start_enabled = (tr.ready and st.ghost_ready
                         and not st.trip_started and not st.finished)
        if start_enabled:
            start_col = QColor(80, 220, 120)
        elif st.trip_started:
            start_col = QColor(100, 160, 120)
        else:
            start_col = QColor(90, 100, 120)
        self._draw_touch_button(
            p, QRectF(rect.x() + 200, dep_y, 170, dep_h),
            T("START [Z]", "DÉPART [Z]"), start_col, font_pt=10,
        )
        if start_enabled:
            self._hit_zones.append(
                (QRectF(rect.x() + 200, dep_y, 170, dep_h),
                 int(Qt.Key.Key_Z), False)
            )

        # REVERSE [I] — appears whenever the train is at a full standstill
        # (|v| < 0.1 m/s), both at termini AND mid-tunnel after an
        # unscheduled stop. Lets the driver head back the way they came,
        # triggering the real "retour en gare" PA announcement.
        rev_y = dep_y + dep_h + 4
        rev_can = abs(tr.v) < 0.1
        rev_col = (QColor(120, 200, 240) if rev_can
                   else QColor(80, 90, 110))
        rev_rect_hud = QRectF(rect.x() + 20, rev_y, 350, dep_h)
        self._draw_touch_button(
            p, rev_rect_hud,
            T("↔ REVERSE DIRECTION [I]", "↔ INVERSER LE SENS [I]"),
            rev_col, font_pt=10,
        )
        if rev_can:
            self._hit_zones.append(
                (rev_rect_hud, int(Qt.Key.Key_I), False)
            )

        # --- Cockpit control buttons (realistic panel) --------------------
        # Three rows × three columns of real buttons the driver uses.
        # Shifted down 26 px to clear the REVERSE button added above.
        btn_y = rect.y() + 314
        btn_w = 115
        btn_h = 36
        gap = 8
        col0 = rect.x() + 20
        col1 = col0 + btn_w + gap
        col2 = col1 + btn_w + gap
        row0 = btn_y
        row1 = btn_y + btn_h + gap
        row2 = btn_y + (btn_h + gap) * 2
        # Row 0 : safety stops + vigilance
        self._draw_button(p, col0, row0, btn_w, btn_h,
                          T("ELEC. STOP [3]", "ARRÊT ÉLEC. [3]"),
                          tr.electric_stop, QColor(255, 190, 40),
                          QColor(70, 50, 0))
        self._hit_zones.append(
            (QRectF(col0, row0, btn_w, btn_h), int(Qt.Key.Key_3), False)
        )
        self._draw_button(p, col1, row0, btn_w, btn_h,
                          T("EMERGENCY [4]", "URGENCE [4]"),
                          tr.emergency, QColor(255, 60, 60),
                          QColor(80, 10, 10), mushroom=True)
        self._hit_zones.append(
            (QRectF(col1, row0, btn_w, btn_h), int(Qt.Key.Key_4), False)
        )
        if st.vigilance_enabled:
            dm_warn = tr.dead_man_timer > 12.0 or tr.dead_man_fault
            blink = int(self._board_animation * 3) % 2 == 0
            dm_on = tr.dead_man_fault or (dm_warn and blink)
            self._draw_button(p, col2, row0, btn_w, btn_h,
                              T("VIGIL. [G]", "VEILLE [G]"),
                              dm_on, QColor(255, 80, 80) if tr.dead_man_fault
                              else QColor(240, 180, 40),
                              QColor(40, 20, 0))
            self._hit_zones.append(
                (QRectF(col2, row0, btn_w, btn_h), int(Qt.Key.Key_G), False)
            )
        else:
            # Vigilance off — show a dim inactive button
            self._draw_button(p, col2, row0, btn_w, btn_h,
                              T("VIGIL. OFF [W]", "VEILLE OFF [W]"),
                              False, QColor(80, 80, 80),
                              QColor(40, 40, 40))
            self._hit_zones.append(
                (QRectF(col2, row0, btn_w, btn_h), int(Qt.Key.Key_W), False)
            )
        # Row 1 : lights + horn
        self._draw_button(p, col0, row1, btn_w, btn_h,
                          T("HEADLT. [H]", "PHARES [H]"),
                          tr.lights_head, QColor(255, 240, 160),
                          QColor(70, 60, 10))
        self._hit_zones.append(
            (QRectF(col0, row1, btn_w, btn_h), int(Qt.Key.Key_H), False)
        )
        self._draw_button(p, col1, row1, btn_w, btn_h,
                          T("CABIN [C]", "CABINE [C]"),
                          tr.lights_cabin, QColor(255, 230, 120),
                          QColor(70, 60, 0))
        self._hit_zones.append(
            (QRectF(col1, row1, btn_w, btn_h), int(Qt.Key.Key_C), False)
        )
        self._draw_button(p, col2, row1, btn_w, btn_h,
                          T("HORN [K]", "KLAXON [K]"),
                          tr.horn, QColor(120, 200, 255),
                          QColor(10, 30, 70))
        # Horn is hold-type.
        self._hit_zones.append(
            (QRectF(col2, row1, btn_w, btn_h), int(Qt.Key.Key_K), True)
        )
        # Row 2 : doors + autopilot + mute
        if tr.doors_timer > 0.0:
            doors_lbl = T("DOORS ...", "PORTES ...")
            doors_on = True
            doors_col = QColor(240, 180, 40)
        else:
            doors_lbl = T("DOORS [D]", "PORTES [D]")
            doors_on = tr.doors_open
            doors_col = QColor(80, 220, 120)
        self._draw_button(p, col0, row2, btn_w, btn_h,
                          doors_lbl,
                          doors_on, doors_col,
                          QColor(10, 60, 20))
        self._hit_zones.append(
            (QRectF(col0, row2, btn_w, btn_h), int(Qt.Key.Key_D), False)
        )
        self._draw_button(p, col1, row2, btn_w, btn_h,
                          T("AUTO [A]", "AUTO [A]"),
                          tr.autopilot, QColor(180, 140, 255),
                          QColor(30, 10, 60))
        self._hit_zones.append(
            (QRectF(col1, row2, btn_w, btn_h), int(Qt.Key.Key_A), False)
        )
        self._draw_button(p, col2, row2, btn_w, btn_h,
                          T("SOUND [N]", "SON [N]"),
                          not self.sounds.muted, QColor(160, 220, 255),
                          QColor(10, 30, 60))
        self._hit_zones.append(
            (QRectF(col2, row2, btn_w, btn_h), int(Qt.Key.Key_N), False)
        )

        # Info block (compact, left column of rows below the buttons).
        # Row 2 bottom = btn_y + 2*(btn_h+gap) + btn_h = 314 + 88 + 36 = 438.
        # Keep a 10 px margin below the buttons so the info rows never
        # overlap the AUTO / DOORS / SOUND row.
        ox = rect.x() + 20
        oy = rect.y() + 450
        p.setFont(QFont("Consolas", 10))
        p.setPen(QPen(COLOR_TEXT))
        cabin_x_m, cabin_y_m = geom_at(tr.s)
        rows = [
            (T("Pilot",     "Pilote"),      st.pilot),
            (T("Mode",      "Mode"),
             T({"normal": "Normal", "challenge": "Challenge", "panne": "Faults"}[st.run_mode],
               {"normal": "Normal", "challenge": "Défi",      "panne": "Pannes"}[st.run_mode])),
            (T("Train",     "Rame"),
             f"{tr.number}   Pax {tr.pax_car1}+{tr.pax_car2}"),
            (T("Mass",      "Masse"),       f"{tr.mass_kg / 1000:5.1f} t"),
            (T("Cmd",       "Consigne"),
             f"{tr.speed_cmd * V_MAX:4.1f} m/s  ({int(tr.speed_cmd * 100):3d}%)"),
            (T("Distance",  "Distance"),
             f"{tr.s:7.1f}/{LENGTH:.0f}  alt {cabin_y_m:4.0f}"),
            (T("Time",      "Temps"),       f"{st.trip_time:6.1f} s"),
            (T("Comfort",   "Confort"),
             f"{st.score_comfort:5.1f}  {st.score_energy:4.2f} kWh"),
        ]
        for i, (k, v) in enumerate(rows):
            y = oy + i * 14
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.drawText(int(ox), int(y + 11), k)
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(int(ox + 95), int(y + 11), v)

        # --- Warning indicator strip (bottom) -----------------------------
        lights = [
            (T("Doors", "Portes"), tr.doors_open, QColor(100, 180, 255)),
            (T("Brake", "Frein"),  tr.brake > 0.02 or tr.emergency,
             COLOR_ALARM if tr.emergency else COLOR_WARN),
            (T("Cable", "Câble"),  tr.tension_dan > T_NOMINAL_DAN, COLOR_WARN),
            (T("Fault", "Panne"),  st.panne_active, COLOR_ALARM),
            (T("Limit", "Limite"), abs(tr.v) >= V_MAX - 0.1, QColor(120, 220, 255)),
        ]
        lx = rect.x() + 20
        ly = rect.y() + rect.height() - 38
        p.setFont(QFont("Consolas", 9))
        for i, (name, on, c) in enumerate(lights):
            x = lx + i * 72
            col = c if on else QColor(40, 46, 60)
            p.setBrush(QBrush(col))
            p.setPen(QPen(QColor(20, 20, 20), 1))
            p.drawRoundedRect(QRectF(x, ly, 64, 22), 6, 6)
            p.setPen(QPen(COLOR_TEXT if on else COLOR_TEXT_DIM))
            p.drawText(QRectF(x, ly, 64, 22),
                       int(Qt.AlignmentFlag.AlignCenter), name)

    def _draw_touch_button(
        self,
        p: QPainter,
        r: QRectF,
        label: str,
        color: QColor,
        font_pt: int = 13,
    ) -> None:
        """Small click-only pad used for mouse controls (±, stop, brake)."""
        grad = QLinearGradient(r.x(), r.y(), r.x(), r.y() + r.height())
        grad.setColorAt(0.0, color.lighter(135))
        grad.setColorAt(0.5, color)
        grad.setColorAt(1.0, color.darker(150))
        p.setBrush(QBrush(grad))
        p.setPen(QPen(QColor(14, 16, 20), 1.4))
        p.drawRoundedRect(r, 5, 5)
        p.setPen(QPen(QColor(0, 0, 0)))
        p.setFont(QFont("Segoe UI", font_pt, QFont.Weight.Bold))
        p.drawText(r, int(Qt.AlignmentFlag.AlignCenter), label)

    def _draw_button(
        self,
        p: QPainter,
        x: float, y: float, w: float, h: float,
        label: str,
        on: bool,
        on_color: QColor,
        dark_color: QColor,
        mushroom: bool = False,
    ) -> None:
        """Illuminated cockpit button — lit when `on`, dark otherwise.

        Mushroom style adds a raised red dome look (for emergency stops).
        """
        r = QRectF(x, y, w, h)
        # Body
        if on:
            grad = QLinearGradient(x, y, x, y + h)
            grad.setColorAt(0.0, on_color.lighter(140))
            grad.setColorAt(0.5, on_color)
            grad.setColorAt(1.0, on_color.darker(130))
            p.setBrush(QBrush(grad))
        else:
            grad = QLinearGradient(x, y, x, y + h)
            grad.setColorAt(0.0, QColor(60, 66, 80))
            grad.setColorAt(1.0, QColor(28, 32, 42))
            p.setBrush(QBrush(grad))
        p.setPen(QPen(QColor(14, 16, 20), 1.5))
        p.drawRoundedRect(r, 6, 6)
        # Mushroom highlight — red dome for the emergency stop
        if mushroom:
            dome = QRectF(x + w / 2 - 9, y + 3, 18, 14)
            dg = QRadialGradient(
                QPointF(x + w / 2, y + 6),
                12,
            )
            if on:
                dg.setColorAt(0.0, QColor(255, 240, 230))
                dg.setColorAt(1.0, QColor(200, 20, 20))
            else:
                dg.setColorAt(0.0, QColor(220, 80, 80))
                dg.setColorAt(1.0, QColor(110, 10, 10))
            p.setBrush(QBrush(dg))
            p.setPen(QPen(QColor(60, 0, 0), 1))
            p.drawEllipse(dome)
        # Label
        p.setFont(QFont("Segoe UI", 9, QFont.Weight.Bold))
        p.setPen(QPen(dark_color if on else COLOR_TEXT_DIM))
        rt = QRectF(x, y + (h - 14) - (6 if mushroom else 0), w, 14)
        p.drawText(rt, int(Qt.AlignmentFlag.AlignCenter), label)

    def _draw_gauge(
        self,
        p: QPainter,
        rect: QRectF,
        value: float,
        maxv: float,
        label: str,
        big_text: str,
        warn: float,
        crit: float,
        title: str | None = None,
    ) -> None:
        cx = rect.center().x()
        cy = rect.center().y() + 6
        radius = min(rect.width(), rect.height()) / 2 - 8
        # Dial background
        grad = QRadialGradient(QPointF(cx, cy), radius)
        grad.setColorAt(0, QColor(40, 48, 62))
        grad.setColorAt(1, QColor(14, 18, 28))
        p.setBrush(QBrush(grad))
        p.setPen(QPen(COLOR_HUD_BORDER, 1))
        p.drawEllipse(QPointF(cx, cy), radius, radius)
        # Arc tick marks
        start_ang = 220   # degrees, left
        end_ang = -40     # degrees, right  (sweeps 260° clockwise)
        sweep = end_ang - start_ang
        n_ticks = 10
        p.save()
        for i in range(n_ticks + 1):
            ang = math.radians(start_ang + sweep * i / n_ticks)
            x1 = cx + math.cos(ang) * (radius - 4)
            y1 = cy - math.sin(ang) * (radius - 4)
            x2 = cx + math.cos(ang) * (radius - 14)
            y2 = cy - math.sin(ang) * (radius - 14)
            p.setPen(QPen(COLOR_TEXT_DIM, 2))
            p.drawLine(QPointF(x1, y1), QPointF(x2, y2))
        # Color bands (green / yellow / red)
        def arc(v_from: float, v_to: float, color: QColor) -> None:
            f0 = max(0.0, min(1.0, v_from / maxv))
            f1 = max(0.0, min(1.0, v_to / maxv))
            a0 = start_ang + sweep * f0
            a1 = start_ang + sweep * f1
            rect_arc = QRectF(cx - radius + 2, cy - radius + 2,
                              (radius - 2) * 2, (radius - 2) * 2)
            p.setPen(QPen(color, 6))
            p.drawArc(rect_arc, int(a0 * 16), int((a1 - a0) * 16))
        arc(0, warn, COLOR_GOOD)
        arc(warn, crit, COLOR_WARN)
        arc(crit, maxv, COLOR_ALARM)
        # Needle
        v_clamped = max(0.0, min(maxv, value))
        f = v_clamped / maxv
        ang = math.radians(start_ang + sweep * f)
        nx = cx + math.cos(ang) * (radius - 18)
        ny = cy - math.sin(ang) * (radius - 18)
        p.setPen(QPen(COLOR_NEEDLE, 3))
        p.drawLine(QPointF(cx, cy), QPointF(nx, ny))
        p.setBrush(QBrush(COLOR_NEEDLE))
        p.drawEllipse(QPointF(cx, cy), 4, 4)
        p.restore()
        # Big text
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Consolas", 14, QFont.Weight.Bold))
        p.drawText(QRectF(rect.x(), cy + 8, rect.width(), 20),
                   int(Qt.AlignmentFlag.AlignHCenter), big_text)
        p.setFont(QFont("Segoe UI", 9))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(rect.x(), cy + 28, rect.width(), 16),
                   int(Qt.AlignmentFlag.AlignHCenter), label)
        if title:
            p.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(QRectF(rect.x(), rect.y() - 2, rect.width(), 14),
                       int(Qt.AlignmentFlag.AlignHCenter), title)

    def _draw_bar(
        self,
        p: QPainter,
        x: float,
        y: float,
        w: float,
        h: float,
        value: float,
        maxv: float,
        label: str,
        color: QColor,
        text: str,
    ) -> None:
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Segoe UI", 9))
        p.drawText(QRectF(x, y - 14, w, 12),
                   int(Qt.AlignmentFlag.AlignLeft), label)
        p.setBrush(QBrush(QColor(28, 32, 42)))
        p.setPen(QPen(COLOR_HUD_BORDER, 1))
        p.drawRoundedRect(QRectF(x, y, w, h), 4, 4)
        f = max(0.0, min(1.0, value / maxv))
        p.setBrush(QBrush(color))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawRoundedRect(QRectF(x + 2, y + 2, (w - 4) * f, h - 4), 3, 3)
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Consolas", 9, QFont.Weight.Bold))
        p.drawText(QRectF(x, y, w, h),
                   int(Qt.AlignmentFlag.AlignCenter), text)

    # ----- event log -------------------------------------------------------

    def _draw_eventlog(self, p: QPainter, rect: QRectF) -> None:
        p.setBrush(QBrush(COLOR_HUD_BG))
        p.setPen(QPen(COLOR_HUD_BORDER, 2))
        p.drawRoundedRect(rect, 10, 10)
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 11, QFont.Weight.DemiBold))
        p.drawText(QRectF(rect.x() + 14, rect.y() + 8, rect.width() - 28, 18),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Event log", "Journal de bord"))
        # Events (oldest first, scroll bottom)
        evs = self.state.events[-10:]
        p.setFont(QFont("Consolas", 10))
        for i, ev in enumerate(evs):
            y = rect.y() + 30 + i * 18
            col = {
                "info": COLOR_TEXT_DIM,
                "warn": COLOR_WARN,
                "alarm": COLOR_ALARM,
            }.get(ev.severity, COLOR_TEXT)
            p.setPen(QPen(col))
            msg = ev.message_fr if LANG == "fr" else ev.message_en
            p.drawText(int(rect.x() + 16), int(y + 12),
                       f"[{ev.timestamp:6.1f}] {msg}")

    # ----- overlays --------------------------------------------------------

    def _draw_title_overlay(self, p: QPainter, w: int, h: int) -> None:
        self._title_zones = []
        p.fillRect(0, 0, w, h, QColor(0, 0, 0, 180))
        box_w = 820
        box_h = 560
        box = QRectF(w / 2 - box_w / 2, h / 2 - box_h / 2, box_w, box_h)
        p.setBrush(QBrush(QColor(20, 26, 40, 240)))
        p.setPen(QPen(COLOR_HUD_BORDER, 3))
        p.drawRoundedRect(box, 16, 16)

        # Title header
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 30, QFont.Weight.Bold))
        p.drawText(QRectF(box.x(), box.y() + 18, box.width(), 50),
                   int(Qt.AlignmentFlag.AlignHCenter), "PERCE-NEIGE")
        p.setFont(QFont("Segoe UI", 13))
        p.drawText(QRectF(box.x(), box.y() + 64, box.width(), 22),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Grande Motte funicular simulator",
                     "Simulateur Funiculaire Grande Motte"))
        p.setFont(QFont("Segoe UI", 10))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(box.x(), box.y() + 90, box.width(), 18),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Tignes, France  —  2111 m → 3032 m  —  3491 m underground  —  12 m/s",
                     "Tignes, France  —  2111 m → 3032 m  —  3491 m sous terre  —  12 m/s"))

        # --- Trip selection — 4 big buttons (Train 1/2 × Up/Down) --------
        sel_title_y = box.y() + 128
        p.setFont(QFont("Segoe UI", 12, QFont.Weight.Bold))
        p.setPen(QPen(COLOR_NEEDLE))
        p.drawText(QRectF(box.x(), sel_title_y, box.width(), 20),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Choose your trip — click a cabin",
                     "Choisissez votre trajet — cliquez une cabine"))

        btn_w = 360
        btn_h = 72
        gap_x = 20
        gap_y = 14
        grid_x0 = box.x() + (box.width() - (btn_w * 2 + gap_x)) / 2
        grid_y0 = sel_title_y + 32
        configs = [
            (0, 0, +1, 1,
             T("Train 1  —  Val Claret → Grande Motte",
               "Rame 1  —  Val Claret → Grande Motte"),
             T("climb  •  3491 m  •  2111 m → 3032 m",
               "montée  •  3491 m  •  2111 m → 3032 m")),
            (1, 0, +1, 2,
             T("Train 2  —  Val Claret → Grande Motte",
               "Rame 2  —  Val Claret → Grande Motte"),
             T("climb  •  3491 m  •  2111 m → 3032 m",
               "montée  •  3491 m  •  2111 m → 3032 m")),
            (0, 1, -1, 1,
             T("Train 1  —  Grande Motte → Val Claret",
               "Rame 1  —  Grande Motte → Val Claret"),
             T("descent  •  3491 m  •  3032 m → 2111 m",
               "descente  •  3491 m  •  3032 m → 2111 m")),
            (1, 1, -1, 2,
             T("Train 2  —  Grande Motte → Val Claret",
               "Rame 2  —  Grande Motte → Val Claret"),
             T("descent  •  3491 m  •  3032 m → 2111 m",
               "descente  •  3491 m  •  3032 m → 2111 m")),
        ]
        for col, row, direction, num, title_txt, sub_txt in configs:
            bx = grid_x0 + col * (btn_w + gap_x)
            by = grid_y0 + row * (btn_h + gap_y)
            rect_btn = QRectF(bx, by, btn_w, btn_h)
            # Direction-tinted gradient
            if direction > 0:
                c0 = QColor(80, 180, 110)
                c1 = QColor(30, 90, 60)
            else:
                c0 = QColor(100, 160, 230)
                c1 = QColor(30, 60, 120)
            grad = QLinearGradient(bx, by, bx, by + btn_h)
            grad.setColorAt(0.0, c0)
            grad.setColorAt(1.0, c1)
            p.setBrush(QBrush(grad))
            p.setPen(QPen(COLOR_HUD_BORDER, 2))
            p.drawRoundedRect(rect_btn, 10, 10)
            # Cabin number pill (left)
            pill = QRectF(bx + 14, by + 14, 40, 44)
            p.setBrush(QBrush(QColor(255, 220, 80)))
            p.setPen(QPen(QColor(80, 50, 0), 1.5))
            p.drawRoundedRect(pill, 6, 6)
            p.setPen(QPen(QColor(40, 20, 0)))
            p.setFont(QFont("Segoe UI", 20, QFont.Weight.Bold))
            p.drawText(pill, int(Qt.AlignmentFlag.AlignCenter), str(num))
            # Direction arrow
            arrow_x = bx + btn_w - 40
            arrow_y = by + btn_h / 2
            p.setPen(QPen(QColor(255, 255, 255), 3))
            if direction > 0:
                p.drawLine(QPointF(arrow_x, arrow_y + 14),
                           QPointF(arrow_x + 16, arrow_y - 14))
                p.drawLine(QPointF(arrow_x + 16, arrow_y - 14),
                           QPointF(arrow_x + 10, arrow_y - 10))
                p.drawLine(QPointF(arrow_x + 16, arrow_y - 14),
                           QPointF(arrow_x + 16, arrow_y - 6))
            else:
                p.drawLine(QPointF(arrow_x, arrow_y - 14),
                           QPointF(arrow_x + 16, arrow_y + 14))
                p.drawLine(QPointF(arrow_x + 16, arrow_y + 14),
                           QPointF(arrow_x + 10, arrow_y + 10))
                p.drawLine(QPointF(arrow_x + 16, arrow_y + 14),
                           QPointF(arrow_x + 16, arrow_y + 6))
            # Labels
            p.setPen(QPen(QColor(255, 255, 255)))
            p.setFont(QFont("Segoe UI", 11, QFont.Weight.Bold))
            p.drawText(QRectF(bx + 66, by + 14, btn_w - 120, 20),
                       int(Qt.AlignmentFlag.AlignLeft), title_txt)
            p.setFont(QFont("Segoe UI", 9))
            p.setPen(QPen(QColor(220, 230, 245)))
            p.drawText(QRectF(bx + 66, by + 36, btn_w - 120, 18),
                       int(Qt.AlignmentFlag.AlignLeft), sub_txt)
            # Hover-hint keyboard shortcut
            p.setFont(QFont("Consolas", 8))
            p.setPen(QPen(QColor(200, 220, 255)))
            p.drawText(QRectF(bx + 66, by + 52, btn_w - 120, 14),
                       int(Qt.AlignmentFlag.AlignLeft),
                       T("click to start", "cliquez pour démarrer"))
            # Click zone
            self._title_zones.append((rect_btn, direction, num))

        # Hint + shortcuts
        p.setFont(QFont("Segoe UI", 9))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(box.x(), box.y() + box_h - 52, box.width(), 16),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Enter starts a default trip (Train 1, climb)  •  F1 help  •  F3 real machine info",
                     "Entrée lance un trajet par défaut (Rame 1, montée)  •  F1 aide  •  F3 infos machine"))
        # Blinking prompt
        p.setFont(QFont("Segoe UI", 11, QFont.Weight.Bold))
        p.setPen(QPen(COLOR_NEEDLE))
        blink = int(self._board_animation * 2) % 2 == 0
        if blink:
            p.drawText(QRectF(box.x(), box.y() + box_h - 30,
                              box.width(), 22),
                       int(Qt.AlignmentFlag.AlignHCenter),
                       T("— pick a cabin above or press ENTER —",
                         "— choisissez une cabine ci-dessus ou ENTRÉE —"))

    def _draw_paused_overlay(self, p: QPainter, w: int, h: int) -> None:
        p.fillRect(0, 0, w, h, QColor(0, 0, 0, 140))
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 32, QFont.Weight.Bold))
        p.drawText(QRectF(0, h / 2 - 40, w, 60),
                   int(Qt.AlignmentFlag.AlignCenter),
                   T("-- PAUSED --", "-- PAUSE --"))
        p.setFont(QFont("Segoe UI", 12))
        p.drawText(QRectF(0, h / 2 + 24, w, 22),
                   int(Qt.AlignmentFlag.AlignCenter),
                   T("Press P or Esc to resume",
                     "Appuyez sur P ou Échap pour reprendre"))

    def _draw_finished_overlay(self, p: QPainter, w: int, h: int) -> None:
        p.fillRect(0, 0, w, h, QColor(0, 0, 0, 160))
        box = QRectF(w / 2 - 280, h / 2 - 180, 560, 360)
        p.setBrush(QBrush(QColor(20, 26, 40, 240)))
        p.setPen(QPen(COLOR_HUD_BORDER, 3))
        p.drawRoundedRect(box, 16, 16)
        st = self.state
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 24, QFont.Weight.Bold))
        p.drawText(QRectF(box.x(), box.y() + 20, box.width(), 36),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("TRIP COMPLETED", "TRAJET TERMINÉ"))
        p.setFont(QFont("Consolas", 13))
        score_total = (
            max(0.0, 100.0 - max(0.0, st.score_time - 420.0) * 0.5)
            + st.score_comfort
            - st.score_energy * 4.0
        )
        rows = [
            (T("Time",    "Durée"),    f"{st.score_time:7.1f} s"),
            (T("Comfort", "Confort"),  f"{st.score_comfort:7.1f} / 100"),
            (T("Energy",  "Énergie"),  f"{st.score_energy:7.2f} kWh"),
            ("",                       ""),
            (T("Total",   "Total"),    f"{score_total:7.1f} pts"),
        ]
        for i, (k, v) in enumerate(rows):
            y = box.y() + 90 + i * 26
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.drawText(int(box.x() + 120), int(y), k)
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(int(box.x() + 260), int(y), v)
        # --- On-screen buttons : reverse direction / new trip ---------
        # The simulation stays live : the driver can open/close doors,
        # fire announcements, toggle lights, and then pick one of these
        # two buttons to continue.
        btn_y = box.y() + box.height() - 78
        btn_w = 230
        btn_h = 40
        rev_rect = QRectF(box.x() + 20, btn_y, btn_w, btn_h)
        new_rect = QRectF(box.x() + box.width() - btn_w - 20, btn_y, btn_w, btn_h)
        # Reverse button (I) — primary action, green
        self._draw_touch_button(
            p, rev_rect,
            T("↔ REVERSE [I]", "↔ INVERSER [I]"),
            QColor(80, 220, 140), font_pt=11,
        )
        self._hit_zones.append((rev_rect, int(Qt.Key.Key_I), False))
        # New trip button (R) — full reset, amber
        self._draw_touch_button(
            p, new_rect,
            T("↻ NEW TRIP [R]", "↻ NOUVEAU [R]"),
            QColor(240, 200, 80), font_pt=11,
        )
        self._hit_zones.append((new_rect, int(Qt.Key.Key_R), False))
        p.setFont(QFont("Segoe UI", 9))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(box.x(), box.y() + box.height() - 28, box.width(), 16),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Doors, lights, announcements remain available",
                     "Portes, éclairage, annonces restent disponibles"))

    def _draw_ann_menu(self, p: QPainter, w: int, h: int) -> None:
        """Overlay panel listing the 15 on-board announcements.

        Each line shows its hotkey ; pressing it plays the announcement
        in FR then EN just like the real train. Esc or F2 closes.
        """
        panel_w = 520
        panel_h = 430
        x = (w - panel_w) / 2
        y = (h - panel_h) / 2
        # Dim background
        p.fillRect(0, 0, w, h, QBrush(QColor(0, 0, 0, 130)))
        # Panel box
        p.setBrush(QBrush(QColor(18, 24, 36, 245)))
        p.setPen(QPen(COLOR_HUD_BORDER, 2))
        p.drawRoundedRect(QRectF(x, y, panel_w, panel_h), 12, 12)
        # Title
        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 14, QFont.Weight.DemiBold))
        p.drawText(
            QRectF(x + 16, y + 12, panel_w - 32, 22),
            int(Qt.AlignmentFlag.AlignLeft),
            T("On-board announcement console",
              "Console des annonces embarquées"),
        )
        p.setFont(QFont("Consolas", 9))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(
            QRectF(x + 16, y + 34, panel_w - 190, 16),
            int(Qt.AlignmentFlag.AlignLeft),
            T("Press a key to trigger — Esc / F2 to close",
              "Appuyer sur une touche pour déclencher — Esc / F2 pour fermer"),
        )
        # STOP button — aborts the announcement currently playing (and
        # clears the queue). Bound to X key as well.
        stop_rect = QRectF(x + panel_w - 166, y + 30, 150, 22)
        self._draw_touch_button(
            p, stop_rect,
            T("⏹ STOP [X]", "⏹ STOP [X]"),
            QColor(220, 120, 80), font_pt=9,
        )
        self._hit_zones.append((stop_rect, int(Qt.Key.Key_X), False))
        # Entries — each row is also a click target that triggers the
        # announcement exactly like pressing its hotkey.
        p.setFont(QFont("Consolas", 11))
        for i, (entry_k, group, label, en, fr) in enumerate(ANNOUNCEMENT_MENU):
            row_y = y + 66 + i * 22
            row_rect = QRectF(x + 14, row_y - 2, panel_w - 28, 22)
            # Row hover background (always subtle) + click zone
            p.setBrush(QBrush(QColor(40, 60, 90, 120)))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawRoundedRect(row_rect, 4, 4)
            self._hit_zones.append((row_rect, int(entry_k), False))
            # Hot key pill
            p.setBrush(QBrush(QColor(60, 100, 160)))
            p.setPen(QPen(QColor(120, 170, 220), 1))
            p.drawRoundedRect(QRectF(x + 18, row_y, 22, 18), 4, 4)
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(QRectF(x + 18, row_y, 22, 18),
                       int(Qt.AlignmentFlag.AlignCenter), label)
            # Text
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(QPointF(x + 48, row_y + 14), T(en, fr))
            # Group key dim on the right
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.setFont(QFont("Consolas", 9))
            p.drawText(QPointF(x + panel_w - 150, row_y + 14), group)
            p.setFont(QFont("Consolas", 11))
        # Mute indicator
        if self.sounds.muted:
            p.setPen(QPen(COLOR_ALARM))
            p.setFont(QFont("Consolas", 10, QFont.Weight.Bold))
            p.drawText(
                QRectF(x + 16, y + panel_h - 24, panel_w - 32, 18),
                int(Qt.AlignmentFlag.AlignRight),
                T("SOUND MUTED — press N to unmute",
                  "SON COUPÉ — appuyer sur N pour réactiver"),
            )
        elif not self.sounds.enabled:
            p.setPen(QPen(COLOR_WARN))
            p.setFont(QFont("Consolas", 10))
            p.drawText(
                QRectF(x + 16, y + panel_h - 24, panel_w - 32, 18),
                int(Qt.AlignmentFlag.AlignRight),
                T("Audio backend unavailable (QtMultimedia)",
                  "Backend audio indisponible (QtMultimedia)"),
            )

    def _draw_help_overlay(self, p: QPainter, w: int, h: int) -> None:
        """Full in-game help panel : goal + all controls."""
        p.fillRect(0, 0, w, h, QColor(0, 0, 0, 170))
        box_w = 780
        box_h = 620
        box = QRectF(w / 2 - box_w / 2, h / 2 - box_h / 2, box_w, box_h)
        p.setBrush(QBrush(QColor(20, 26, 40, 245)))
        p.setPen(QPen(COLOR_HUD_BORDER, 3))
        p.drawRoundedRect(box, 14, 14)

        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 22, QFont.Weight.Bold))
        p.drawText(QRectF(box.x(), box.y() + 16, box.width(), 36),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Help — Controls", "Aide — Commandes"))
        p.setFont(QFont("Segoe UI", 10))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(box.x(), box.y() + 54, box.width(), 18),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Press F1 to close — F3 for real machine info",
                     "F1 pour fermer — F3 pour les infos machine réelle"))

        groups = [
            (T("Driving", "Conduite"), [
                (T("Up / Down", "Haut / Bas"),
                 T("speed command +/- (% of V_MAX = 12 m/s)",
                   "consigne vitesse +/- (% de V_MAX = 12 m/s)")),
                (T("Space / B", "Espace / B"),
                 T("service brake (hold)", "frein de service (maintenir)")),
                (T("Shift", "Shift"),
                 T("EMERGENCY brake (hold, rail brakes)",
                   "frein d'URGENCE (maintenir, freins rail)")),
                ("3", T("ELECTRIC stop — latched service stop",
                        "ARRÊT ÉLECTRIQUE — arrêt service verrouillé")),
                ("4", T("EMERGENCY stop — latched rail brakes",
                        "ARRÊT URGENCE — freins sur rail verrouillés")),
                ("W", T("vigilance on / off (off by default)",
                        "veille on / off (désactivée par défaut)")),
                ("G", T("dead-man vigilance acknowledge",
                        "acquittement veille automatique")),
            ]),
            (T("Cockpit", "Cabine"), [
                ("H", T("headlights on / off", "phares on / off")),
                ("C", T("cabin lights on / off", "éclairage cabine on / off")),
                ("K", T("horn (hold)", "klaxon (maintenir)")),
                ("D", T("doors open / close (only at a stop)",
                        "portes (à l'arrêt uniquement)")),
                ("A", T("autopilot toggle", "pilote auto on / off")),
                ("N", T("sound mute / unmute",
                        "couper / remettre le son")),
            ]),
            (T("System", "Système"), [
                ("P / Esc", T("pause / resume", "pause / reprise")),
                ("M", T("mode : normal / challenge / faults",
                        "mode : normal / défi / pannes")),
                ("L", T("language FR / EN", "langue FR / EN")),
                ("F1", T("toggle this help", "ouvrir/fermer cette aide")),
                ("F2", T("announcement console",
                         "console d'annonces")),
                ("F3", T("real machine info + links",
                         "infos machine réelle + liens")),
                ("F4", T("cabin / side view toggle",
                         "vue cabine / vue latérale")),
                ("R / Enter", T("new trip (after arrival)",
                                "nouveau trajet (après arrivée)")),
            ]),
        ]

        col_w = (box_w - 60) / 3
        col_x = [box.x() + 30 + i * col_w for i in range(3)]
        for ci, (title, entries) in enumerate(groups):
            x = col_x[ci]
            y = box.y() + 92
            p.setFont(QFont("Segoe UI", 12, QFont.Weight.Bold))
            p.setPen(QPen(COLOR_NEEDLE))
            p.drawText(QRectF(x, y, col_w - 10, 20),
                       int(Qt.AlignmentFlag.AlignLeft), title)
            y += 26
            p.setFont(QFont("Consolas", 10))
            for key, desc in entries:
                p.setPen(QPen(COLOR_TEXT))
                p.drawText(QRectF(x, y, col_w - 10, 16),
                           int(Qt.AlignmentFlag.AlignLeft), key)
                p.setPen(QPen(COLOR_TEXT_DIM))
                p.drawText(QRectF(x, y + 15, col_w - 10, 16),
                           int(Qt.AlignmentFlag.AlignLeft), desc)
                y += 34

        # Tips box at the bottom
        tips_y = box.y() + box_h - 146
        tips_box = QRectF(box.x() + 30, tips_y, box_w - 60, 120)
        p.setBrush(QBrush(QColor(30, 38, 56, 220)))
        p.setPen(QPen(COLOR_HUD_BORDER, 1))
        p.drawRoundedRect(tips_box, 8, 8)
        p.setPen(QPen(COLOR_NEEDLE))
        p.setFont(QFont("Segoe UI", 11, QFont.Weight.Bold))
        p.drawText(QRectF(tips_box.x() + 12, tips_box.y() + 8,
                          tips_box.width() - 24, 18),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Driving tips", "Conseils de conduite"))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 9))
        tips = [
            T("• Ramp the speed command gradually — accel is capped at ~1 m/s², the regulator handles the rest",
              "• Augmentez la consigne progressivement — l'accél. est plafonnée ~1 m/s², le régulateur fait le reste"),
            T("• The station approach envelope auto-brakes to 1 m/s over the last 55 m — just hold 100 %",
              "• L'enveloppe d'arrêt freine auto à 1 m/s sur les 55 derniers m — maintenez 100 %"),
            T("• Electric stop [3] is a latched service stop : motor off + normal brake, no rail damage",
              "• L'arrêt électrique [3] est verrouillé : moteur off + frein service, sans friction rail"),
            T("• Emergency [4 or Shift] engages rail brakes (5 m/s²) — use only if you really have to",
              "• L'urgence [4 ou Shift] engage les freins rail (5 m/s²) — réservez aux vrais cas"),
            T("• Vigilance [W] : optional, off by default — once enabled, touch a control every 20 s",
              "• Veille [W] : optionnelle, désactivée par défaut — si activée, touchez une commande toutes les 20 s"),
            T("• Help menu : check GitHub for updates, or send an anonymous bug report (opens pre-filled issue)",
              "• Menu Aide : vérifier les MAJ GitHub, ou signaler un bug anonymement (ticket pré-rempli)"),
        ]
        for i, line in enumerate(tips):
            p.drawText(QRectF(tips_box.x() + 12, tips_box.y() + 30 + i * 16,
                              tips_box.width() - 24, 16),
                       int(Qt.AlignmentFlag.AlignLeft), line)

    def _draw_info_overlay(self, p: QPainter, w: int, h: int) -> None:
        """Real Perce-Neige funicular facts, specs and source links."""
        p.fillRect(0, 0, w, h, QColor(0, 0, 0, 180))
        box_w = 820
        box_h = 680
        box = QRectF(w / 2 - box_w / 2, h / 2 - box_h / 2, box_w, box_h)
        p.setBrush(QBrush(QColor(20, 26, 40, 245)))
        p.setPen(QPen(COLOR_HUD_BORDER, 3))
        p.drawRoundedRect(box, 14, 14)

        p.setPen(QPen(COLOR_TEXT))
        p.setFont(QFont("Segoe UI", 22, QFont.Weight.Bold))
        p.drawText(QRectF(box.x(), box.y() + 16, box.width(), 36),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("The real Perce-Neige funicular",
                     "Le vrai Funiculaire Perce-Neige"))
        p.setFont(QFont("Segoe UI", 10))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QRectF(box.x(), box.y() + 52, box.width(), 18),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Tignes, Savoie, France — press F3 to close",
                     "Tignes, Savoie, France — F3 pour fermer"))

        # Intro paragraph
        p.setFont(QFont("Segoe UI", 10))
        p.setPen(QPen(COLOR_TEXT))
        intro = T(
            "Longest underground funicular in France. Opened 14 April 1993 by "
            "Von Roll / CFD to replace the old cable car to the Grande Motte "
            "glacier. Two symmetric coupled trains run on a single track with "
            "a passing loop at the midpoint. Used by skiers year-round to "
            "access summer skiing on the glacier (3032 m).",
            "Le plus long funiculaire souterrain de France. Inauguré le 14 avril "
            "1993 par Von Roll / CFD pour remplacer l'ancien téléphérique du "
            "glacier de la Grande Motte. Deux rames couplées circulent en "
            "symétrie sur une voie unique avec évitement au milieu. Utilisé "
            "toute l'année pour accéder au ski d'été sur le glacier (3032 m).",
        )
        # Word-wrap manually
        self._draw_wrapped(p, intro,
                           QRectF(box.x() + 30, box.y() + 80,
                                  box.width() - 60, 60),
                           QFont("Segoe UI", 10))

        # Two columns of specs
        col_y = box.y() + 148
        col_w = (box.width() - 70) / 2
        left_x = box.x() + 30
        right_x = left_x + col_w + 10

        left_specs = [
            (T("Operator",  "Exploitant"),  "CFD / STGM"),
            (T("Manufacturer", "Constructeur"), "Von Roll (Suisse)"),
            (T("Opened",    "Mise en service"), "14 avril 1993"),
            (T("Construction", "Construction"),    "1989 – 1991"),
            (T("Type",      "Type"),
             T("Underground funicular, 2 trains",
               "Funiculaire souterrain, 2 rames")),
            (T("Route",     "Tracé"),
             "Val Claret ↔ Grande Motte"),
            (T("Lower alt.", "Alt. gare basse"), "2 111 m"),
            (T("Upper alt.", "Alt. gare haute"), "3 032 m"),
            (T("Vert. drop", "Dénivelé"),        "921 m"),
            (T("Length",    "Longueur"),          "3 491 m"),
            (T("Max grade", "Pente max"),         "30 %"),
            (T("Track gauge","Écartement"),       "1 200 mm"),
            (T("Tunnel ⌀ min","⌀ tunnel min"),    "3.9 m"),
            (T("Passing loop","Évitement"),       "~200 m"),
        ]
        right_specs = [
            (T("Max speed", "Vitesse max"),       "12 m/s (43.2 km/h)"),
            (T("Trip time", "Durée trajet"),      "~6 min"),
            (T("Capacity/h","Débit horaire"),     "~3 000 pax/h"),
            (T("Trains",    "Rames"),
             T("2 × 2 coupled cars", "2 × 2 voitures couplées")),
            (T("Pax / train","Pax / rame"),       "334 + 1"),
            (T("Empty mass","Masse vide"),        "32.3 t"),
            (T("Loaded mass","Masse PC"),         "58.8 t"),
            (T("Car Ø",     "⌀ voiture"),         "3.60 m"),
            (T("Doors/car", "Portes/voiture"),    "3 (chaque côté)"),
            (T("Motors",    "Motorisation"),      "3 × 800 kW DC"),
            (T("Total power","Puissance tot."),   "2 400 kW"),
            (T("Drive loc.","Emplac. treuil"),
             T("Upper station (Panoramic)",
               "Gare haute (Panoramique)")),
            (T("Cable Ø",   "⌀ câble"),           "52 mm Fatzer"),
            (T("Cable T nom","T nom. câble"),     "22 500 daN"),
            (T("Cable T break","Rupture câble"),  "191 200 daN"),
        ]

        p.setFont(QFont("Consolas", 10))
        for i, (k, v) in enumerate(left_specs):
            y = col_y + i * 18
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.drawText(int(left_x), int(y + 14), k)
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(int(left_x + 135), int(y + 14), v)
        for i, (k, v) in enumerate(right_specs):
            y = col_y + i * 18
            p.setPen(QPen(COLOR_TEXT_DIM))
            p.drawText(int(right_x), int(y + 14), k)
            p.setPen(QPen(COLOR_TEXT))
            p.drawText(int(right_x + 135), int(y + 14), v)

        # Sources
        sources_y = box.y() + box_h - 160
        p.setFont(QFont("Segoe UI", 11, QFont.Weight.Bold))
        p.setPen(QPen(COLOR_NEEDLE))
        p.drawText(QRectF(box.x() + 30, sources_y, box.width() - 60, 18),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Sources & further reading",
                     "Sources et pour en savoir plus"))
        p.setFont(QFont("Consolas", 9))
        p.setPen(QPen(QColor(140, 190, 240)))
        sources = [
            "Wikipedia FR  : https://fr.wikipedia.org/wiki/Funiculaire_du_Perce-Neige",
            "Wikipedia EN  : https://en.wikipedia.org/wiki/Funiculaire_du_Perce-Neige",
            "CFD rolling stock : https://www.cfd.group/rolling-stock/tignes-funicular",
            "Remontées-mécaniques.net : https://www.remontees-mecaniques.net",
            "Tignes resort : https://en.tignes.net/discover/ski-resort/grande-motte-glacier",
        ]
        for i, s in enumerate(sources):
            p.drawText(QRectF(box.x() + 30, sources_y + 24 + i * 16,
                              box.width() - 60, 14),
                       int(Qt.AlignmentFlag.AlignLeft), s)

        p.setPen(QPen(COLOR_TEXT_DIM))
        footer_font = QFont("Segoe UI", 9)
        footer_font.setItalic(True)
        p.setFont(footer_font)
        p.drawText(QRectF(box.x(), box.y() + box_h - 26, box.width(), 18),
                   int(Qt.AlignmentFlag.AlignHCenter),
                   T("Simulation © 2026 Kevin Guion — data from public sources",
                     "Simulation © 2026 Kevin Guion — données de sources publiques"))

    def _draw_wrapped(self, p: QPainter, text: str, rect: QRectF,
                      font: QFont) -> None:
        p.setFont(font)
        p.setPen(QPen(COLOR_TEXT))
        metrics = p.fontMetrics()
        words = text.split()
        line = ""
        y = rect.y() + metrics.ascent()
        line_h = metrics.height()
        for word in words:
            test = (line + " " + word).strip()
            if metrics.horizontalAdvance(test) > rect.width() - 8:
                p.drawText(QPointF(rect.x(), y), line)
                y += line_h
                if y > rect.y() + rect.height():
                    return
                line = word
            else:
                line = test
        if line:
            p.drawText(QPointF(rect.x(), y), line)


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"{APP_NAME}  v{VERSION}")
        self.resize(1360, 940)
        self.game = GameWidget(self)
        self.setCentralWidget(self.game)
        ico = Path(__file__).parent / "logo.ico"
        if ico.exists():
            self.setWindowIcon(QIcon(str(ico)))
        # Help menu — auto-update + bug report entries
        try:
            self._install_help_menu()
        except Exception:
            pass
        # Background update check, 3 s after launch
        QTimer.singleShot(3000, self._bg_check_update)
        # Check for pending crash reports from a previous run
        QTimer.singleShot(1500, self._offer_pending_crash_reports)

    # ------------------------------------------------------------------
    # Help menu / auto-update / bug report
    # ------------------------------------------------------------------
    def _lang(self) -> str:
        try:
            return self.game.state.lang
        except Exception:
            return "en"

    def _tr(self, en: str, fr: str) -> str:
        return fr if self._lang() == "fr" else en

    def _install_help_menu(self) -> None:
        bar = self.menuBar()
        menu = bar.addMenu(self._tr("&Help", "&Aide"))
        act_upd = menu.addAction(
            self._tr("Check for updates…", "Vérifier les mises à jour…"))
        act_upd.triggered.connect(self._manual_check_update)
        act_bug = menu.addAction(
            self._tr("Report a bug…", "Signaler un bug…"))
        act_bug.triggered.connect(self._manual_bug_report)
        menu.addSeparator()
        act_about = menu.addAction(self._tr("About", "À propos"))
        act_about.triggered.connect(self._show_about)

    def _show_about(self) -> None:
        QMessageBox.about(
            self,
            self._tr("About", "À propos"),
            f"<b>{APP_NAME}</b> v{VERSION}<br>"
            + self._tr(
                "Accurate simulator of the Tignes underground funicular.",
                "Simulateur fidèle du funiculaire souterrain de Tignes.")
            + "<br><br>"
            + self._tr(
                "Repository : ", "Dépôt : ")
            + "<a href='https://github.com/"
            + f"{autoupdate_mod_owner()}/{autoupdate_mod_repo()}'>GitHub</a>"
            + "<br>"
            + self._tr("License : MIT", "Licence : MIT"))

    def _bg_check_update(self) -> None:
        try:
            import autoupdate
        except Exception:
            return
        owner = autoupdate_mod_owner()
        repo = autoupdate_mod_repo()
        thread = autoupdate.UpdateCheckThread(
            owner, repo, self._on_update_check_result)
        thread.start()
        self._upd_thread = thread  # keep ref

    def _on_update_check_result(self, info) -> None:
        # Called from a worker thread — bounce back to the GUI thread
        QTimer.singleShot(
            0, lambda: self._show_update_if_newer(info, silent=True))

    def _show_update_if_newer(self, info, silent: bool) -> None:
        try:
            import autoupdate
        except Exception:
            return
        if info is None:
            if not silent:
                QMessageBox.warning(
                    self,
                    self._tr("Update check", "Mise à jour"),
                    self._tr(
                        "Could not reach GitHub. Check your connection.",
                        "Impossible de joindre GitHub. Vérifiez la connexion."))
            return
        if not autoupdate.is_newer(info.version, VERSION):
            if not silent:
                QMessageBox.information(
                    self,
                    self._tr("Up to date", "À jour"),
                    self._tr(
                        f"You already run the latest version (v{VERSION}).",
                        f"Vous utilisez déjà la dernière version (v{VERSION})."))
            return
        self._prompt_update_dialog(info)

    def _prompt_update_dialog(self, info) -> None:
        import autoupdate
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Icon.Information)
        msg.setWindowTitle(self._tr("Update available", "Mise à jour disponible"))
        text = self._tr(
            f"Version <b>{info.version}</b> is available.<br>"
            f"You run v{VERSION}.<br><br>Download and install now?",
            f"La version <b>{info.version}</b> est disponible.<br>"
            f"Vous utilisez v{VERSION}.<br><br>"
            "Télécharger et installer maintenant ?")
        msg.setText(text)
        if info.body:
            msg.setDetailedText(info.body[:4000])
        btn_ok = msg.addButton(
            self._tr("Install && restart", "Installer && redémarrer"),
            QMessageBox.ButtonRole.AcceptRole)
        msg.addButton(
            self._tr("Skip", "Ignorer"),
            QMessageBox.ButtonRole.RejectRole)
        msg.exec()
        if msg.clickedButton() is not btn_ok:
            return
        try:
            autoupdate.download_and_install(
                info, Path(__file__).resolve().parent)
        except Exception as e:
            QMessageBox.critical(
                self,
                self._tr("Update failed", "Échec de la mise à jour"),
                self._tr(f"Error : {e}", f"Erreur : {e}"))
            return
        QMessageBox.information(
            self,
            self._tr("Update installed", "Mise à jour installée"),
            self._tr(
                "The application will restart now.",
                "L'application va redémarrer."))
        autoupdate.relaunch_app()

    def _manual_check_update(self) -> None:
        try:
            import autoupdate
        except Exception:
            QMessageBox.warning(self, "Update", "autoupdate module missing")
            return
        info = autoupdate.check_latest_release(
            autoupdate_mod_owner(), autoupdate_mod_repo())
        self._show_update_if_newer(info, silent=False)

    # --- Bug / crash reporting ----------------------------------------
    def _offer_pending_crash_reports(self) -> None:
        try:
            import bugreport
        except Exception:
            return
        project_dir = Path(__file__).resolve().parent
        reports = bugreport.list_pending_reports(project_dir)
        if not reports:
            return
        latest = reports[-1]
        data = bugreport.load_report(latest)
        if data is None:
            return
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Icon.Warning)
        msg.setWindowTitle(self._tr("Crash detected", "Plantage détecté"))
        exc_t = data.get("exception_type", "")
        ts = data.get("timestamp", "")
        msg.setText(self._tr(
            f"A crash was recorded at {ts} ({exc_t}).<br>"
            "Open a pre-filled (anonymous) GitHub issue now?",
            f"Un plantage a été enregistré à {ts} ({exc_t}).<br>"
            "Ouvrir un ticket GitHub pré-rempli (anonyme) maintenant ?"))
        msg.setDetailedText(bugreport.format_crash_body(data)[:4000])
        btn_send = msg.addButton(
            self._tr("Send (opens browser)", "Envoyer (ouvre navigateur)"),
            QMessageBox.ButtonRole.AcceptRole)
        btn_del = msg.addButton(
            self._tr("Delete", "Supprimer"),
            QMessageBox.ButtonRole.DestructiveRole)
        msg.addButton(
            self._tr("Keep", "Garder"),
            QMessageBox.ButtonRole.RejectRole)
        msg.exec()
        clicked = msg.clickedButton()
        if clicked is btn_send:
            title = f"Crash {exc_t} @ v{data.get('system', {}).get('app_version', '')}"
            url = bugreport.make_issue_url(title, bugreport.format_crash_body(data))
            QDesktopServices.openUrl(QUrl(url))
            bugreport.delete_report(latest)
        elif clicked is btn_del:
            bugreport.delete_report(latest)

    def _manual_bug_report(self) -> None:
        try:
            import bugreport
        except Exception:
            return
        dlg = QDialog(self)
        dlg.setWindowTitle(self._tr("Report a bug", "Signaler un bug"))
        dlg.resize(520, 420)
        form = QVBoxLayout(dlg)
        lbl_desc = QLabel(self._tr(
            "Short description :", "Description courte :"))
        ed_title = QLineEdit()
        lbl_body = QLabel(self._tr(
            "What happened ?", "Que s'est-il passé ?"))
        ed_body = QPlainTextEdit()
        lbl_steps = QLabel(self._tr(
            "Steps to reproduce :", "Étapes de reproduction :"))
        ed_steps = QPlainTextEdit()
        note = QLabel(self._tr(
            "<i>This opens a pre-filled GitHub issue. No data is sent "
            "automatically. Paths are anonymized.</i>",
            "<i>Ceci ouvre un ticket GitHub pré-rempli. Rien n'est envoyé "
            "automatiquement. Les chemins sont anonymisés.</i>"))
        note.setWordWrap(True)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok
            | QDialogButtonBox.StandardButton.Cancel)
        btns.button(QDialogButtonBox.StandardButton.Ok).setText(
            self._tr("Open issue", "Ouvrir le ticket"))
        form.addWidget(lbl_desc)
        form.addWidget(ed_title)
        form.addWidget(lbl_body)
        form.addWidget(ed_body)
        form.addWidget(lbl_steps)
        form.addWidget(ed_steps)
        form.addWidget(note)
        form.addWidget(btns)
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        body = bugreport.format_manual_body(
            ed_body.toPlainText(),
            ed_steps.toPlainText(),
            VERSION)
        url = bugreport.make_issue_url(ed_title.text(), body)
        QDesktopServices.openUrl(QUrl(url))


def autoupdate_mod_owner() -> str:
    return "ARP273-ROSE"


def autoupdate_mod_repo() -> str:
    return "perce-neige-sim"


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(VERSION)
    # Install anonymous crash handler — writes a JSON report if the app
    # crashes so the next launch can offer to open a GitHub issue.
    try:
        import bugreport
        bugreport.install_crash_handler(
            Path(__file__).resolve().parent, VERSION)
    except Exception:
        pass
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
