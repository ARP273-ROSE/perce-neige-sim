"""
Perce-Neige Simulator — Grande Motte funicular simulation (Tignes, France).

Accurate PC remake of the TI-84 FUNIC program. Real specs sourced from
Wikipedia (FR/EN), remontees-mecaniques.net and CFD (rolling stock maker):
  - Length along slope : 3474 m (cockpit counter reference)
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

Author : ARP273-ROSE (original TI-Basic FUNIC), PyQt6 port 2026.
"""

from __future__ import annotations

import locale
import math
import os
import sqlite3
import tempfile
import random
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, time as dtime
from pathlib import Path
from typing import Any

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
    QWheelEvent,
)
from PyQt6.QtWidgets import (
    QApplication,
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QToolTip,
    QVBoxLayout,
    QWidget,
)

try:
    from PyQt6.QtMultimedia import QAudioOutput, QMediaPlayer
    _QTMULTIMEDIA_OK = True
except ImportError:
    _QTMULTIMEDIA_OK = False

VERSION = "1.8.1"
APP_NAME = "Perce-Neige Simulator"


# ---------------------------------------------------------------------------
# Resource paths — handle PyInstaller frozen mode transparently
# ---------------------------------------------------------------------------

def _resource_path(rel: str) -> Path:
    """Return absolute path to a bundled read-only resource.

    In PyInstaller frozen mode, data files are unpacked into the
    temporary directory exposed via ``sys._MEIPASS``.  Otherwise we
    resolve relative to this source file.
    """
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return Path(base) / rel
    return Path(__file__).resolve().parent / rel


def _writable_dir() -> Path:
    """Directory where the app may write data (crash reports, logs).

    - Frozen .exe : next to the executable
    - Source      : project directory
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

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
# Slope length calibrated against the real cockpit-display reading at
# arrival in Grande Motte (3474 m on the on-board distance counter,
# direct observation from funiculaire_cabine_hd.mp4 at 9:37). Previous
# value 3491 m came from public sources but is the published nominal
# length of the route ; the counter's zero reference is offset a few
# metres inside the lower station, producing the difference.
LENGTH = 3474.0             # slope length (m) — cockpit counter reference
# Square cut-and-cover sections at both ends of the tunnel. The middle
# is bored with a TBM (round cross-section) ; the first ~257 m out of
# Val Claret and the last ~54 m into Grande Motte are concrete-lined
# rectangular galleries. Transitions observed at the exact cockpit
# distance counter values t=2:25 (257 m outbound, tunnel becomes round)
# and t=7:43 (tunnel returns to square, ≈ 54 m before platform stop).
SQUARE_SECTION_LOW_END = 257.0
SQUARE_SECTION_HIGH_START = 3420.0
ALT_LOW = 2111.0            # lower station altitude (m)
ALT_HIGH = 3032.0           # upper station altitude (m)
DROP = ALT_HIGH - ALT_LOW   # 921 m

# Regulator cap is 12 m/s — the published Von Roll mechanical limit.
# In the reference cockpit video the driver runs at a speed_cmd of
# ~84 %, producing a cruise of 10.1 m/s ; that's the speed used below
# to map the observed timestamps to slope-distance landmarks, but the
# simulator itself still lets the driver push all the way to 12 m/s.
V_MAX = 12.0                # hard cap regulator (m/s) — real value
# Acceleration profile calibrated from video analysis of a real 12 m/s
# run (YouTube FUNI284, 414 s total, filmed at upper station Aug 2013).
# The run shows a cosine-ramp accel over ~64 s (2→12 m/s) with peak
# ~0.245 m/s^2, and a sine-ramp decel over ~50 s (12→1 m/s) with peak
# ~0.34 m/s^2. Approach creep lasts ~30 s.
# Accel target calibrated from cockpit observation : the train covers
# 257 m between departure (1:43) and tunnel-shape change (2:25) = 42 s,
# which fits a trapezoidal velocity profile with ~33 s of acceleration
# to the observed cruise of 10.1 m/s (covering 167 m) followed by 9 s
# of cruise (covering 91 m) → 258 m, matching the observation to 1 m.
# That places the programmed accel ramp at 10.1 / 33 ≈ 0.306 m/s² — a
# property of the regulator independent of the target setpoint.
A_TARGET = 0.30             # programmed accel target (m/s^2)
A_MAX_REG = 0.32            # hard cap on motor-induced accel
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
# Real Von Roll / Perce-Neige procedure: the train stops with ≈ 10 m
# clearance between the leading cabin nose and the concrete bumper
# wall. Never docks flush — leaves room for cable slack, emergency
# inspection, AND the visual perspective the driver expects (with
# only 3 m eye setback from the nose, a 5 m clearance gave only 8 m
# of forward view at arrival, collapsing the perspective). 10 m ≈
# real sight distance seen in Perce-Neige cab videos at Grande Motte
# and Val Claret termini (back wall visible a comfortable way off).
BUMPER_CLEAR = 10.0
START_S = TRAIN_HALF + BUMPER_CLEAR     # back of train 10 m past s=0
STOP_S = LENGTH - TRAIN_HALF - BUMPER_CLEAR  # front 10 m before s=LENGTH

# Approach profile — the train decelerates to CREEP_V and maintains it
# from CREEP_START up to STOP_S, entering the station quietly.
CREEP_V = 0.5                   # creep speed on platform approach (m/s)
                                # Real Von Roll procedural creep is 0.3-0.5
                                # m/s — platform docking always < 1 m/s.
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

# Cable elasticity rebound — visible cable-stretch release + residual damped
# oscillation when the train stops. Derived from cable stiffness physics :
# Fatzer 52 mm, E ≈ 100 GPa, A ≈ π·26² mm² = 2124 mm², L = 3491 m → k ≈ 60.8
# kN/m. A 58 t loaded train creates ~16.5 kN of travel-direction force on
# the cable at 30 % grade, so the cable is stretched ~0.27 m under that load.
# During the approach + brake phase, the load shifts — the bull-wheel motor
# pulls up to ~100 kN peak, adding ~1.0 m of additional stretch. When the
# train stops and the motor shuts off, the stretch is released over ~1-2 s,
# causing the OPPOSITE train (ghost counterweight) to creep forward along
# the cable by a visible amount — measured at ≈1.1 m over 2 s on video.
# Model : x(t) = A_creep · (1 - exp(-t/τ)) + A_osc · exp(-ζωt) · sin(ωt)
REBOUND_GHOST_AMP = 1.10         # m — release creep for opposite train
REBOUND_MAIN_AMP = 0.22          # m — residual creep on the main train
REBOUND_TAU = 0.70               # s — creep time constant (1/e); ~95 % at 2 s
REBOUND_OSC_AMP = 0.10           # m — residual oscillation amplitude
REBOUND_OMEGA = 2.40             # rad/s — natural frequency (T ≈ 2.6 s)
REBOUND_ZETA = 0.10              # damping ratio (2-3 visible oscillations)

# Passing loop (middle section where tunnel splits in two) ~222 m long.
# Positions calibrated from the real cockpit video : the loop entry is
# at t=4:38 (175 s after departure) and exit at t=5:00 (197 s), which
# at the cruise speed of 10.1 m/s places them at s=1601 m and s=1823 m.
PASSING_START = 1611.0
PASSING_END = 1813.0

# Slope profile : (slope distance in m, gradient as fraction).
# Technical sources: "pente douce" at start, "montée plus raide" in middle,
# max gradient 30 %, average 26.7 %, altitude gain 932 m (2100→3032 m).
# Integrates to 932 m ± 1 m.
SLOPE_PROFILE: list[tuple[float, float]] = [
    # Profile calibrated from direct cockpit observation
    # (funiculaire_cabine_hd.mp4), with event timestamps mapped to
    # slope-distance via the known cruise speed of 10.1 m/s :
    #   t=0:00  (s=0)     — departure, gentle gradient in square section
    #   t=2:25  (s=257)   — tunnel becomes round (TBM) ; gradient still
    #                       modest, ramp-up starts shortly after
    #   t=2:50  (s=510)   — "la pente augmente" : ramp-up to max begins
    #   t=3:30  (s=914)   — max sustained gradient reached
    #   t=7:29  (s=3328)  — "la diminution de pente finale commence"
    #   t=7:43  (s=3420)  — gradient reduction ends, tunnel becomes
    #                       square again
    #   t=9:37  (s=3474)  — arrival at Grande Motte platform
    # Peak gradient 30 %, altitude rise integrates to ~921 m.
    (0.0,    0.08),    # Val Claret portal (square tunnel), gentle start
    (120.0,  0.12),
    (257.0,  0.16),    # square→round transition
    (400.0,  0.22),
    (510.0,  0.25),    # "la pente augmente" (t=2:50)
    (700.0,  0.28),
    (914.0,  0.295),   # max sustained gradient (t=3:30)
    (2400.0, 0.295),
    (3000.0, 0.29),
    (3200.0, 0.28),
    (3328.0, 0.27),    # "diminution de pente finale commence" (t=7:29)
    (3380.0, 0.18),
    (3420.0, 0.10),    # "tunnel redevient carré" (t=7:43)
    (3474.0, 0.06),    # Grande Motte platform (square tunnel)
]

# Horizontal route plan : (slope distance, bearing in degrees).
# GPS coordinates : Val Claret 45.4578°N 6.9014°E → Grande Motte
# 45.4354°N 6.9020°E ; straight-line bearing ≈ 179° (due S).
# Two right curves separated by a straight section through the passing
# loop (remontees-mecaniques.net technical description confirmed).
# Net heading change ≈ 48° right (155° → 203°).
CURVE_PROFILE: list[tuple[float, float]] = [
    # Curve positions calibrated from cockpit video : at 10.1 m/s cruise,
    # t=4:08 → 4:32 maps curve 1 to s=1297..1541 m, t=5:06 → 5:54 maps
    # curve 2 to s=1884..2369 m. The straight passing-loop segment sits
    # in between (PASSING_START=1601, PASSING_END=1823).
    (0.0,    155.0),   # SSE out of Val Claret station
    (1297.0, 155.0),   # straight lower section (t=0..4:08)
    (1420.0, 165.0),   # curve 1 midpoint — peak curvature
    (1541.0, 175.0),   # end of curve 1 (t=4:32, ≈ due S)
    (1601.0, 175.0),   # entering passing loop (straight)
    (1823.0, 175.0),   # exiting passing loop (straight)
    (1884.0, 175.0),   # start of curve 2 (t=5:06)
    (2125.0, 189.0),   # curve 2 midpoint — peak curvature
    (2369.0, 203.0),   # end of curve 2 (t=5:54, SSW)
    (3474.0, 203.0),   # straight into upper station
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
# Square cut-and-cover at both ends, round (TBM bore) in the middle.
# Transition distances observed directly from the cockpit video (user
# read the distance counter at the shape change) : round section runs
# from s=257 m to s=3420 m.
TUNNEL_SECTIONS: list[tuple[float, str]] = [
    (0.0,                       "horseshoe"),  # square cut-and-cover
    (SQUARE_SECTION_LOW_END,    "circular"),   # TBM round bore (t=2:25)
    (SQUARE_SECTION_HIGH_START, "horseshoe"),  # square again (t=7:43)
    (LENGTH,                    "horseshoe"),
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


def slope_angle_at(s: float) -> float:
    """Slope ANGLE (radians) at distance s. Positive = uphill."""
    return math.atan(gradient_at(s))


def slope_curvature_at(s: float) -> float:
    """Vertical curvature = d(angle)/ds in rad/m at distance s.

    Positive = track pitches UP relative to current heading (compression
    of a valley → hill transition). Negative = pitches DOWN (crest).
    Used in the F4 cabin view so the tunnel ahead visibly tilts up or
    down as the real Perce-Neige slope profile changes from 15 % near
    Val Claret → 30 % mid-tunnel → 12 % easing into Grande Motte.
    """
    ds = 5.0
    return (slope_angle_at(s + ds) - slope_angle_at(s - ds)) / (2.0 * ds)


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
    # Slew-limited "effective" setpoint actually followed by the regulator.
    # Real Von Roll drives ramp the internal setpoint at ~0.25 m/s² when the
    # driver turns the speed-command knob — you never get an instantaneous
    # velocity change no matter how fast the knob is spun. speed_cmd_eff
    # tracks speed_cmd at a fixed rate so abrupt knob movements produce a
    # realistic smooth deceleration/acceleration instead of a hard "pile".
    speed_cmd_eff: float = 0.0
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
    regen_kw: float = 0.0        # recovered generator power on descent
    inrush_timer: float = 0.0    # remaining time (s) of startup inrush boost
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
    # --- Fault simulation state (persistent, modified by maybe_random_event
    # and cleared by _reset_trip). Each field describes *how* a fault
    # currently affects the live simulation, so the gauges/physics
    # actually move when a fault is announced.
    tension_fault_dan: float = 0.0    # extra daN added on cable tension (surge)
    thermal_derate: float = 1.0       # motor power multiplier (1.0 = nominal)
    motor_count: int = 3              # 3 active motors by default; 2 = degraded
    motor_id_down: int = 0            # which motor group (1/2/3) is down; 0=none
    speed_fault_cap: float = 999.0    # dynamic v_limit (m/s); high = no cap
    slack_fault_dan: float = 0.0      # daN *subtracted* from cable tension
    aux_power_fault: bool = False     # 400 V auxiliaries lost → motor cut
    overspeed_tripped: bool = False   # latched after v > 1.1·V_MAX
    overspeed_level: int = 0          # 0 none / 1 service / 2 secours / 3 parachute
    door_fault: bool = False          # door sensor fault — must stop at station
    parking_stuck: bool = False       # parking brake release failure
    fault_timer: float = 0.0          # seconds until current fault auto-clears
    # --- Enriched faults (post-research_failures.md audit 2026-04-14)
    cable_rupture: bool = False       # tractor cable broken — catastrophic
    service_brake_fail: float = 1.0   # 1.0 nominal, <1 = service brake fade
    flood_tunnel: bool = False        # tunnel water intrusion — speed cap 4 m/s
    comms_loss: bool = False          # PA + GSM tunnel lost — narrative only
    switch_abt_fault: bool = False    # Abt crossing misalignment — hold before siding
    fire_vent_fail: bool = False      # tunnel vent/desenfumage HS during fire
    # --- Cable cumulative fatigue (Palmgren-Miner, ISO 4309 / DIN EN 12927-6)
    fatigue_cycles: int = 0           # completed aller+retour round-trips
    cable_wear_pct: float = 0.0       # 0..100 — percent of usable wire section

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
    # Pending mid-tunnel incident : set when an abnormal stop is
    # engaged while the cabin is still rolling. Once the train comes
    # to a halt, the "tech_incident" announcement fires and the trip
    # is formally suspended (trip_started → False) so the driver has
    # to go through READY → DEPART again to resume.
    pending_incident: bool = False
    # Which announcement to play once the cabin has come to rest :
    # "" → generic tech_incident, "fire" → dim_light + evac, etc.
    pending_incident_kind: str = ""
    score_time: float = 0.0
    score_comfort: float = 100.0
    score_energy: float = 0.0
    events: list[Event] = field(default_factory=list)
    event_cooldown: float = 0.0
    run_mode: str = "normal"    # normal | challenge | panne
    panne_active: bool = False
    panne_kind: str = ""
    panne_auto: bool = True     # when False, fault scheduler is paused
                                # (driver picks faults manually via F dialog)
    finished: bool = False
    rebound_timer: float = 0.0  # cable elasticity rebound (after arrival)
    rebound_amp_m: float = 0.0  # actual cable stretch (m) captured at arrival
    best_time: float | None = None
    # Trip direction selection from the title screen.
    # direction = +1 (Val Claret → Glacier, climb) or -1 (Glacier → Val Claret).
    # train_choice selects which cabin (1 or 2) the player drives — purely
    # a label + colour cue since both are mechanically identical.
    selected_direction: int = +1
    selected_train: int = 1
    vigilance_enabled: bool = False  # dead-man vigilance off by default
    # Announcement language for the F2 console — one of fr / en / it / de / es.
    # Independent from the UI language so the driver can play any translation
    # of any announcement on demand.
    ann_lang: str = "fr"


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
        # Dynamic speed cap : wet rails (condensation/ingress), degraded
        # mode on 2/3 motors, or any other fault lowers the operational
        # ceiling.
        v_limit = min(V_MAX, tr.speed_fault_cap)

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
        # Effective motor power after thermal derate and motor-count
        # degradation (real Von Roll drive has 3 × 800 kW groups ; losing
        # one leaves 1 600 kW = 67 % of nominal).
        p_eff = P_MAX * tr.thermal_derate * (tr.motor_count / 3.0)
        # Startup inrush : DC drives typically draw ~4.5× nominal during
        # the first ~1.2 s of acceleration from standstill while the
        # armature magnetizes and shaft inertia is overcome. Re-arm only
        # when the train is effectively stopped and the driver commands
        # traction — prevents a second spike mid-trip.
        if abs(tr.v) < 0.2 and tr.throttle > 0.2 and tr.inrush_timer <= 0.0:
            tr.inrush_timer = 1.2
        if tr.inrush_timer > 0.0:
            tr.inrush_timer = max(0.0, tr.inrush_timer - dt)
            # Boost tapers from 4.5× down to 1.0× as the timer expires.
            boost = 1.0 + 3.5 * (tr.inrush_timer / 1.2)
            p_eff *= boost
        f_motor_power_cap = p_eff / v_eff             # P = F v
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

        # Auxiliary 400 V power failure : main drive contactor drops out.
        # Parking brake hydraulics cut back in — train coasts / held.
        if tr.aux_power_fault:
            f_motor = 0.0

        # Parking brake mechanical release failure : motor can still pull
        # but the drum brake keeps the drive pulley locked.
        if tr.parking_stuck:
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
        #
        # Physics note — the emergency brake force here is the PARACHUTE
        # friction on the rail head (approximately constant). The NET
        # deceleration felt by the driver is NOT constant because gravity
        # works with or against the brake :
        #   - ascending main : gravity + brake decelerate together → fast
        #     stop (~10 m on 30 % grade)
        #   - descending main : gravity fights the brake → slow stop
        #     (~30 m on 30 % grade)
        # The cable-linked counterweight (ghost) naturally absorbs part
        # of the energy when it is intact, which is why a real funicular
        # with intact cable stops markedly faster than the "cable rupture"
        # calculation in the manual. A_BRAKE_EMERGENCY = 5 m/s² matches
        # the STRMTG passenger-comfort ceiling (RM5 §2.4).
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
            # Emergency parachute (Belleville) still works even on cable
            # rupture / service-brake fade — that is the whole point of a
            # cable-independent rail brake (RM5 requirement).
            a_brk = tr.emergency_ramp * A_BRAKE_EMERGENCY
        elif tr.brake > 0:
            # Service brake can fade to 15–25 % of nominal when the
            # hydraulic circuit loses pressure (Glória 2025 pattern).
            a_brk = tr.brake * A_BRAKE_NORMAL * tr.service_brake_fail
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

        # Final creep kill : ONLY snap below 3 cm/s to avoid the visible
        # "everything freezes" jolt that used to happen around 0.2 m/s.
        # The regulator + cable elasticity take the train from ~1 m/s
        # down to a few cm/s smoothly ; this is just a floor to kill
        # numerical jitter once the train is mechanically at rest.
        if a_brk > 0 and abs(tr.v) < 0.03:
            tr.v = 0.0
            a = 0.0

        # Integrate — tr.v is SIGNED in the +s direction. Going up the
        # slope, v > 0. Going down, v < 0. tr.direction is ±1 and tells
        # the regulator / motor what sign to push the throttle force in.
        new_v = tr.v + a * dt
        # Cap |v| at v_limit in the travel direction (coasting past is
        # fine — the motor is off — but we still don't let the physics
        # blow up if something goes wrong).
        # Soft over-speed bleed-off : when the train exceeds v_limit
        # (wet-rail cap suddenly activated, etc.) don't snap the velocity to
        # the cap — that caused the visible "pile" glitch. Instead bleed
        # off the excess at ≤ 1.5 m/s² so the train glides down to the
        # new ceiling over a couple of seconds. The regulator's slewed
        # setpoint already handles the general case ; this is a safety
        # net that only kicks in if something forces |v| above v_limit.
        if new_v * tr.direction > v_limit and f_motor == 0:
            excess = new_v * tr.direction - v_limit
            bleed = min(excess, 1.5 * dt)
            new_v -= bleed * tr.direction
        if new_v * tr.direction < -v_limit:
            excess = -v_limit - new_v * tr.direction
            bleed = min(excess, 1.5 * dt)
            new_v += bleed * tr.direction
        tr.s += ((tr.v + new_v) / 2.0) * dt
        tr.v = new_v
        # Train centre clamped between station stop points. Only kill v
        # when we're actively trying to push PAST the platform end (so
        # the cable-elasticity rebound can still move the cabin a few
        # cm forward/backward in its damped oscillation after arrival).
        # Soft position-clamp : if the train would push past the stop
        # point, don't snap the velocity to zero (that's what caused the
        # old "instant stop" at arrival). Apply a strong-but-finite buffer
        # deceleration of 2 m/s² — the train dissipates any residual
        # energy over ~0.1 s without a visible jolt. The regulator's new
        # quadratic-taper approach already brings |v| below 0.1 m/s by
        # the time s reaches the threshold, so this is just a safety net.
        # After arrival we relax the clamp by the rebound headroom so
        # the cable-elastic bounce is visible instead of being instantly
        # crushed back to the stop point. During the normal approach
        # (not finished) we hard-clamp so physics can't drift outside.
        clamp_lo = START_S - (1.2 if st.finished else 0.0)
        clamp_hi = STOP_S + (1.2 if st.finished else 0.0)
        if tr.s >= clamp_hi:
            tr.s = clamp_hi
            if tr.v > 0.0:
                tr.v = max(0.0, tr.v - 2.0 * dt)
                a = -2.0
        elif tr.s <= clamp_lo:
            tr.s = clamp_lo
            if tr.v < 0.0:
                tr.v = min(0.0, tr.v + 2.0 * dt)
                a = 2.0
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
        # Apply persistent fault offsets so the gauge actually moves
        # when a cable surge or slack fault is announced.
        tr.tension_dan += tr.tension_fault_dan
        tr.tension_dan -= tr.slack_fault_dan
        if tr.cable_rupture:
            # Tractor cable severed : residual tension is only the parking
            # anchor + parachute reaction. Gauge drops to near zero.
            tr.tension_dan = min(tr.tension_dan, 1500.0)
        if tr.tension_dan < 0.0:
            tr.tension_dan = 0.0
        # Cable wear model (Palmgren-Miner simplified) — ISO 4309, DIN EN
        # 12927-6. Every tick the cumulative section-loss grows with the
        # ratio (tension / tension_ref) squared, integrated over time.
        # Reference : real Perce-Neige cable replaced in 1999 after 6 years
        # (~36 000 round-trips) ≈ rebut threshold reached.
        T_REF = 22500.0  # daN nominal
        if tr.v != 0.0:
            stress_ratio = max(0.0, tr.tension_dan) / T_REF
            tr.cable_wear_pct += stress_ratio * stress_ratio * dt * 0.0002
            if tr.cable_wear_pct > 100.0:
                tr.cable_wear_pct = 100.0

        # Overspeed cascade — three thresholds aligned with the Perce-Neige
        # Poma-style interlock chain (patent EP0392938A1, STRMTG RM5) :
        #   +10 % V_MAX → service brake trip (electrical command)
        #   +12 % V_MAX → secondary / emergency brake automatic closure
        #   +20 % V_MAX → parachute Belleville mechanical trip (centrifugal)
        # Each stage is latched and strictly cumulative : once level N is
        # reached, physics may still escalate to N+1 but cannot regress.
        v_abs = abs(tr.v)
        if v_abs > 1.20 * V_MAX and tr.overspeed_level < 3:
            tr.overspeed_level = 3
            tr.overspeed_tripped = True
            tr.emergency = True
            # Force parachute to full engagement immediately — it bypasses
            # the normal emergency ramp (mechanical flyball governor).
            tr.emergency_ramp = 1.0
            tr.speed_cmd = 0.0
            tr.throttle = 0.0
            tr.ready = False
            st.ghost_ready = False
            st.ghost_ready_timer = 0.0
            st.ghost_ready_delay = 0.0
            st.departure_buzzer_remaining = 0.0
            add_event(
                st, "overspeed3",
                "PARACHUTE BRAKE ! mechanical centrifugal trip (+20 %).",
                "FREIN PARACHUTE ! déclenchement centrifuge mécanique (+20 %).",
                "alarm",
            )
        elif v_abs > 1.12 * V_MAX and tr.overspeed_level < 2:
            tr.overspeed_level = 2
            tr.overspeed_tripped = True
            tr.emergency = True
            tr.speed_cmd = 0.0
            tr.throttle = 0.0
            tr.ready = False
            st.ghost_ready = False
            st.ghost_ready_timer = 0.0
            st.ghost_ready_delay = 0.0
            st.departure_buzzer_remaining = 0.0
            add_event(
                st, "overspeed2",
                "OVERSPEED +12 % ! secondary emergency brake closed.",
                "SURVITESSE +12 % ! frein de secours fermé automatiquement.",
                "alarm",
            )
        elif v_abs > 1.10 * V_MAX and tr.overspeed_level < 1:
            tr.overspeed_level = 1
            tr.overspeed_tripped = True
            tr.emergency = True
            tr.speed_cmd = 0.0
            tr.throttle = 0.0
            tr.ready = False
            st.ghost_ready = False
            st.ghost_ready_timer = 0.0
            st.ghost_ready_delay = 0.0
            st.departure_buzzer_remaining = 0.0
            add_event(
                st, "overspeed",
                "OVERSPEED TRIP ! service brake + emergency engaged.",
                "SURVITESSE ! frein de service + urgence engagés.",
                "alarm",
            )
        # Power flow at the motor : positive when the motor pulls the
        # cable (traction), negative when gravity drives the wheel and
        # the motor acts as a generator (regenerative braking on loaded
        # descent — real Perce-Neige recovers ~42 kWh per full loaded
        # descent according to the CFD datasheet). We track both signs
        # but display only the positive side on the gauge.
        power_signed_kw = (f_motor * tr.v) / 1000.0
        if power_signed_kw >= 0.0:
            tr.power_kw = power_signed_kw
            tr.regen_kw = 0.0
        else:
            tr.power_kw = 0.0
            # Efficiency chain : bull wheel → DC machine → inverter → grid
            # is roughly 0.80 round-trip at full load.
            tr.regen_kw = -power_signed_kw * 0.80
        # Smoothed display values — EMA with τ ≈ 0.3 s avoids flicker
        alpha = min(1.0, dt / 0.3)
        tr.tension_dan_disp += (tr.tension_dan - tr.tension_dan_disp) * alpha
        tr.power_kw_disp += (tr.power_kw - tr.power_kw_disp) * alpha

        # Ghost train position : symmetric on the cable.
        # Cable elasticity rebound — two-stage relaxation after arrival :
        #   (1) release-creep : exponential return to equilibrium as the
        #       motor unloads and ~1 m of cable stretch shortens back,
        #       pushing the ghost (counterweight) forward along the cable.
        #   (2) residual oscillation : small damped sine around the new
        #       equilibrium until internal friction dissipates the energy.
        # Sign convention : rebound is applied in the TRAVEL direction of
        # the arrival (positive = train would continue past the platform),
        # which means the ghost at the opposite terminus creeps BACKWARDS
        # from its stop point into the tunnel — exactly what you see in
        # footage of the opposite wagon "sliding" after a stop.
        base_ghost_s = LENGTH - tr.s
        if st.finished:
            st.rebound_timer += dt
            t_r = st.rebound_timer
            creep = 1.0 - math.exp(-t_r / REBOUND_TAU)
            osc = (math.exp(-REBOUND_ZETA * REBOUND_OMEGA * t_r)
                   * math.sin(REBOUND_OMEGA * t_r))
            # The motor / bull wheel is at the UPPER station. Only the
            # cabin sitting at the LOWER (Val Claret) terminus is attached
            # to a long stretched cable (~3.5 km) that stores enough
            # elastic energy to visibly rebound. The cabin at the UPPER
            # terminus is right beside the bull wheel — ~0 m of cable
            # between it and the fixed pulley, no stretch, no rebound.
            main_is_upper = tr.s > LENGTH * 0.5
            # Physical stretch released = snapshot at arrival, clamped
            # so aberrant huge values (fault conditions) don't drive the
            # rebound off-screen.
            amp = min(max(st.rebound_amp_m, 0.3), 5.0)
            osc_amp = min(REBOUND_OSC_AMP, amp * 0.15)
            if main_is_upper:
                # Main at top — the loaded span is ~0 m so there's no
                # cable elastic rebound, BUT the DC motor shaft + gear
                # reducer + bull-wheel assembly still has a finite
                # torsional compliance. When the brake clamps, the
                # stored strain in the drive train springs back a few
                # cm, producing a small damped oscillation on the main
                # cabin — just enough to feel the "settle" instead of
                # an instant stop. Amplitude ~ 8 cm, same natural
                # frequency as the cable rebound (drive-line is stiffer
                # but inertia is similar).
                DRIVE_TRAIN_AMP = 0.08   # m
                main_amp_top = DRIVE_TRAIN_AMP
                osc_amp_top = DRIVE_TRAIN_AMP * 0.6
                # Direction: arriving train overshoots forward first,
                # then settles back (classic elastic bounce).
                main_disp_top = tr.direction * (
                    main_amp_top * creep + osc_amp_top * osc
                )
                tr.s += main_disp_top * dt * 2.5
                # Ghost at bottom also rebounds by the full cable stretch.
                ghost_disp = (-tr.direction) * (amp * creep + osc_amp * osc)
                base_ghost_s += ghost_disp
            else:
                # Main at bottom — it rebounds. Ghost at top is static.
                main_amp = amp * 0.20   # 20 % of stretch felt on main
                main_disp = (tr.direction) * (
                    main_amp * creep + (osc_amp * 0.5) * osc
                )
                tr.s += main_disp * dt * 2.5
                d_creep_dt = (main_amp / REBOUND_TAU) * math.exp(-t_r / REBOUND_TAU)
                d_osc_dt = (osc_amp * 0.5) * (
                    REBOUND_OMEGA * math.exp(-REBOUND_ZETA * REBOUND_OMEGA * t_r)
                    * math.cos(REBOUND_OMEGA * t_r)
                    - REBOUND_ZETA * REBOUND_OMEGA
                    * math.exp(-REBOUND_ZETA * REBOUND_OMEGA * t_r)
                    * math.sin(REBOUND_OMEGA * t_r)
                )
                tr.v = tr.direction * (d_creep_dt + d_osc_dt)
        st.ghost_s = max(START_S, min(LENGTH - START_S, base_ghost_s))

        if st.trip_started:
            st.trip_time += dt

        # Net energy = traction consumed minus regen recovered.
        st.score_energy += (tr.power_kw - tr.regen_kw) * dt / 3600.0
        st.score_comfort = max(0.0, 100.0 - tr.jerk_sum * 0.015)

        # Arrival detection : direction-aware. Silent : no popup, no
        # announcement, no event banner — a discreet line in the log is
        # enough. The driver stays in the cabin and prepares the return
        # trip at their own pace via the standard D / V / Z protocol.
        # The threshold must be TIGHT (|v| < 0.08 m/s and tr.s within
        # 0.08 m of the terminus) so the quadratic-taper final approach
        # is allowed to finish naturally. Firing too early would engage
        # the parking drum brake while the train still has 0.4 m/s and
        # 2 m to go — that's the "instant stop" the driver saw.
        if not st.finished and abs(tr.v) < 0.08:
            arrived = False
            if tr.direction > 0 and tr.s >= STOP_S - 0.08:
                st.finished = True
                arrived = True
                st.score_time = st.trip_time
                tr.fatigue_cycles += 1
                add_event(
                    st, "arrive",
                    "At Grande Motte (3032 m) — press V when ready to depart",
                    "À la Grande Motte (3032 m) — V quand prêt au départ", "info",
                )
            elif tr.direction < 0 and tr.s <= START_S + 0.08:
                st.finished = True
                arrived = True
                st.score_time = st.trip_time
                tr.fatigue_cycles += 1
                add_event(
                    st, "arrive",
                    "At Val Claret (2111 m) — press V when ready to depart",
                    "À Val Claret (2111 m) — V quand prêt au départ", "info",
                )
            # On arrival, relax the speed command and release the
            # service/emergency brakes, then engage the parking drum
            # brake. Because the detection window is now |v| < 0.08
            # m/s (tight), snapping v to 0 at this point is visually
            # imperceptible — much better than the old 0.4 m/s threshold
            # which felt like an instant stop.
            if arrived:
                tr.speed_cmd = 0.0
                tr.throttle = 0.0
                tr.brake = 0.0
                tr.emergency = False
                tr.maint_brake = True
                # Snapshot the physical cable stretch at the moment of
                # arrival — this is what will be released during the
                # rebound. Formula : Δl = F·L / (A·E) on the Fatzer
                # rope. Only meaningful when main is at the LOWER
                # terminus (long loaded span) ; at the upper terminus
                # the loaded span is ~0 and stretch ≈ 0.
                A_cable = 2.12e-3
                E_cable = 1.05e11
                L_loaded = LENGTH - tr.s if tr.direction > 0 else tr.s
                F_peak = tr.tension_dan * 10.0
                st.rebound_amp_m = max(0.0, F_peak * L_loaded
                                       / (A_cable * E_cable))

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
        # a MILD service brake only what's needed to track a gentle decel.
        # No rail brakes — the train coasts to a halt smoothly.
        if tr.electric_stop or tr.dead_man_fault:
            # Drop the commanded setpoint progressively (not instantly)
            # so releasing electric stop doesn't kick the regulator.
            tr.speed_cmd = max(0.0, tr.speed_cmd - 0.5 * dt)
            tr.speed_cmd_eff = max(0.0, tr.speed_cmd_eff - 0.5 * dt)
            tr.throttle = 0.0
            # "Arrêt simple" (service stop) — Von Roll doctrine : motor
            # cut + regenerative braking. Real decel target ≈ 0.4 m/s²
            # (passengers standing barely notice). From 12 m/s that's
            # 30 s and 180 m — very gentle, very long. The key is to
            # NEVER let the brake slam on : it must ramp in over 3–4 s
            # like the DC drive current ramping down.
            TARGET_DECEL = 0.4  # m/s² — Von Roll service stop comfort
            # Engagement ramp limiter : brake command can rise at most
            # 0.05/s (fully engaged in ~5 s, matching real hydraulic
            # service-brake engagement) and fall freely. This is the
            # dominant shape when the driver first hits the button.
            BRAKE_RAMP_UP = 0.05       # per second
            BRAKE_RAMP_DOWN = 0.25     # per second
            BRAKE_CAP = 0.30           # max brake in service mode
            # Nearly-stopped regime — settle to a gentle hold at 0.20.
            if abs(tr.v) < 0.5:
                hold = 0.20
                err_b = hold - tr.brake
                step = max(-BRAKE_RAMP_DOWN * dt,
                           min(BRAKE_RAMP_UP * dt, err_b))
                tr.brake = max(0.0, min(BRAKE_CAP, tr.brake + step))
                return
            # Cruising regime — closed-loop around TARGET_DECEL.
            # obs_decel > 0 when the train is actually slowing down.
            obs_decel = -math.copysign(tr.a, tr.v)
            err = TARGET_DECEL - obs_decel
            # Small proportional nudge per frame, well under the ramp
            # cap so the brake rises SMOOTHLY with time, not in jumps.
            p_gain = 0.12
            raw_step = err * p_gain * dt
            step = max(-BRAKE_RAMP_DOWN * dt,
                       min(BRAKE_RAMP_UP * dt, raw_step))
            tr.brake = max(0.0, min(BRAKE_CAP, tr.brake + step))
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

        # --- Setpoint slewing ---------------------------------------------
        # Real Von Roll speed-command knob is not directly tracked by the
        # motor : an internal ramp limiter accelerates / decelerates the
        # effective setpoint at a fixed rate. Accel up  → ~0.35 m/s² (so
        # 0→12 m/s takes ~35 s with feed-forward). Decel down → ~0.25 m/s²
        # (gentle service deceleration — matches what the driver feels on
        # a real Perce-Neige trip). This is what prevents an abrupt knob
        # movement from kicking the brake hard.
        RAMP_UP = 0.35          # m/s per s when raising the setpoint
        RAMP_DOWN = 0.25        # m/s per s when lowering the setpoint
        driver_target = tr.speed_cmd * V_MAX
        # Speed-cap faults (wet rails, motor degraded, thermal, …)
        # also clamp the effective driver setpoint : this way the slew
        # limiter brings the train down to the new ceiling smoothly over
        # ~30 s instead of the physics engine slamming v to the cap
        # (the old behaviour felt like an instant "pile" from 12 to 4 m/s).
        if tr.speed_fault_cap < V_MAX:
            driver_target = min(driver_target, tr.speed_fault_cap)
        de = driver_target - tr.speed_cmd_eff
        if de > 0.0:
            tr.speed_cmd_eff = min(driver_target,
                                   tr.speed_cmd_eff + RAMP_UP * dt)
        elif de < 0.0:
            tr.speed_cmd_eff = max(driver_target,
                                   tr.speed_cmd_eff - RAMP_DOWN * dt)
        # Use the slewed setpoint as the regulator's true target.
        target_v = min(tr.speed_cmd_eff, v_envelope)
        envelope_active = v_envelope < tr.speed_cmd_eff - 0.05

        # Creep zone : last CREEP_DIST metres crawl at CREEP_V, then
        # taper smoothly to zero over the final ~6 m using a square-root
        # profile v = √(2·a·d) with a very gentle deceleration (0.04 m/s²
        # — roughly a 20 s final docking, as seen on video). That kills
        # the old "instant stop at threshold" where the train would snap
        # from CREEP_V straight to 0 when dist_to_stop crossed 0.5 m.
        if dist_to_stop < CREEP_DIST:
            PARK_DECEL = 0.04         # m/s² final-docking decel
            FINAL_DIST = 6.0          # m over which the taper applies
            if dist_to_stop > FINAL_DIST:
                target_v = CREEP_V
            else:
                v_park = math.sqrt(2.0 * PARK_DECEL
                                   * max(dist_to_stop, 0.001))
                target_v = min(CREEP_V, v_park)
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
    # Length cap (40) AND age cap (5 min) — prevents unbounded growth
    # during long sessions and keeps the log focused on recent activity.
    if len(st.events) > 40:
        st.events.pop(0)
    min_ts = st.trip_time - 300.0
    while st.events and st.events[0].timestamp < min_ts:
        st.events.pop(0)


def clear_fault(st: GameState) -> None:
    """Clear every persistent fault effect on the active train.

    Called when a fault's duration expires, when the driver resets the
    overspeed trip, or when a new trip starts. Keeps latched safety
    states (overspeed_tripped) in sync with the event log.
    """
    tr = st.train
    tr.tension_fault_dan = 0.0
    tr.thermal_derate = 1.0
    tr.motor_count = 3
    tr.motor_id_down = 0
    tr.speed_fault_cap = 999.0
    tr.slack_fault_dan = 0.0
    tr.aux_power_fault = False
    tr.door_fault = False
    tr.parking_stuck = False
    tr.cable_rupture = False
    tr.service_brake_fail = 1.0
    tr.flood_tunnel = False
    tr.comms_loss = False
    tr.switch_abt_fault = False
    tr.fire_vent_fail = False
    tr.fault_timer = 0.0
    st.panne_active = False
    st.panne_kind = ""


def maybe_random_event(st: GameState, dt: float) -> None:
    """Fault scheduler — runs only in the 'panne' game mode.

    Each tick the active fault's duration counts down and clears its
    persistent effects when it expires. If no fault is currently active
    we roll a small chance of starting a new one, with realistic
    per-scenario parameters so every announced fault actually moves
    the simulation (cable gauge jumps, motor power drops, speed caps
    lower, etc.).
    """
    if st.run_mode != "panne":
        return
    tr = st.train

    # Decay of active fault ---------------------------------------------
    if st.panne_active and tr.fault_timer > 0.0:
        tr.fault_timer -= dt
        if tr.fault_timer <= 0.0:
            cleared = st.panne_kind
            add_event(
                st,
                "fault_cleared",
                f"Fault cleared : {cleared}.",
                f"Panne résolue : {cleared}.",
                "info",
            )
            clear_fault(st)

    # Don't roll another fault while one is still active or latched
    # by the overspeed trip.
    if st.panne_active or tr.overspeed_tripped:
        return

    # Manual mode : the scheduler is disabled and the driver uses the
    # F dialog to trigger faults on demand.
    if not st.panne_auto:
        return

    st.event_cooldown -= dt
    if st.event_cooldown > 0:
        return
    if random.random() > 0.0025:   # ~1 chance / 400 ticks at 60 Hz
        return
    st.event_cooldown = 10.0

    # Weighted pool : common faults stay common, catastrophic ones rare.
    # Weights are calibrated from research_failures.md §2 — aux_power and
    # thermal dominate real funiculars, cable_rupture is Glória-class rare
    # but must be represented in "panne" mode to make the scenario
    # pedagogically complete.
    kind_pool = [
        ("tension",          4),
        ("door",             4),
        ("thermal",          5),
        ("fire",             3),
        ("wet_rail",         4),
        ("motor_degraded",   4),
        ("slack",            4),
        ("aux_power",        5),
        ("parking_stuck",    4),
        ("cable_rupture",    1),   # Glória 2025 — catastrophic, rare
        ("service_brake_fail", 2), # Glória double-failure pattern
        ("flood_tunnel",     2),   # glacier melt / vault seepage
        ("comms_loss",       3),   # Kaprun lesson — narrative only
        ("switch_abt_fault", 2),   # Perce-Neige specific (Abt crossing)
        ("fire_vent_fail",   2),   # amplifier of fire (desenfumage HS)
    ]
    choices, weights = zip(*kind_pool)
    kind = random.choices(choices, weights=weights, k=1)[0]
    trigger_fault(st, kind)


# All known fault kinds — used by the manual picker dialog + the weighted
# random pool. Order = display order in the dialog.
FAULT_KINDS = [
    "tension", "door", "thermal", "fire", "wet_rail", "motor_degraded",
    "slack", "aux_power", "parking_stuck", "cable_rupture",
    "service_brake_fail", "flood_tunnel", "comms_loss",
    "switch_abt_fault", "fire_vent_fail",
]


def fault_label(kind: str, lang: str) -> str:
    """Bilingual human-readable label for a fault kind (UI dialog)."""
    labels = {
        "tension":          ("Cable tension spike",     "Pic tension câble"),
        "door":             ("Door sensor fault",       "Défaut capteur porte"),
        "thermal":          ("Motor overheat",          "Surchauffe moteur"),
        "fire":             ("Smoke / fire",            "Fumée / feu"),
        "wet_rail":         ("Wet rails",               "Rails humides"),
        "motor_degraded":   ("Motor group fault",       "Groupe moteur HS"),
        "slack":            ("Cable slack",             "Mou de câble"),
        "aux_power":        ("400 V auxiliaries lost",  "Auxiliaires 400 V perdus"),
        "parking_stuck":    ("Parking brake stuck",     "Frein parking bloqué"),
        "cable_rupture":    ("Cable rupture (Glória)",  "Rupture câble (Glória)"),
        "service_brake_fail": ("Service brake fade",    "Frein service inop."),
        "flood_tunnel":     ("Tunnel flooding",         "Inondation tunnel"),
        "comms_loss":       ("PA / radio lost",         "PA / radio perdus"),
        "switch_abt_fault": ("Abt crossing misalign.",  "Aiguillage Abt désaligné"),
        "fire_vent_fail":   ("Fire + vent failure",     "Feu + désenfumage HS"),
    }
    en, fr = labels.get(kind, (kind, kind))
    return fr if lang == "fr" else en


def trigger_fault(st: GameState, kind: str) -> None:
    """Activate a specific fault. Used by the random scheduler AND by the
    manual F-dialog picker. Caller guarantees no other fault is active.
    """
    tr = st.train
    st.panne_active = True
    st.panne_kind = kind

    if kind == "tension":
        # +6 500 daN surge (≈ 30 % of nominal) — pushes the gauge into
        # the warning band and trips the "Câble" warning light.
        tr.tension_fault_dan = 6500.0
        tr.fault_timer = 22.0
        add_event(
            st, "tension",
            "Cable tension spike +6 500 daN — reduce throttle.",
            "Pic de tension câble +6 500 daN — réduire la puissance.",
            "warn",
        )
    elif kind == "door":
        tr.door_fault = True
        tr.fault_timer = 35.0
        add_event(
            st, "door",
            "Door sensor fault — stop at next station.",
            "Défaut capteur porte — arrêt station suivante.",
            "warn",
        )
    elif kind == "thermal":
        # Motor windings 85 → 105 °C : protection derates to 55 % power.
        tr.thermal_derate = 0.55
        tr.speed_fault_cap = 8.0
        tr.fault_timer = 80.0
        add_event(
            st, "thermal",
            "Motor over-temperature — power 55 %, v≤8 m/s.",
            "Surchauffe moteur — puissance 55 %, v≤8 m/s.",
            "warn",
        )
    elif kind == "fire":
        tr.emergency = True
        tr.fault_timer = 60.0
        add_event(
            st, "fire",
            "Smoke detected in tunnel ! EMERGENCY STOP.",
            "Fumée dans le tunnel ! ARRÊT D'URGENCE.",
            "alarm",
        )
    elif kind == "wet_rail":
        # Fully-enclosed tunnel under 900 m of rock : ice is impossible,
        # but seasonal thaw water seeps from the vault and condensation
        # on the cold upper section (still 0–4 °C year-round) leaves a
        # wet film on the rails. Adhesion drops, the regulator caps
        # speed to 6 m/s until the train wipes the rails clear.
        tr.speed_fault_cap = 6.0
        tr.fault_timer = 35.0
        add_event(
            st, "wet_rail",
            "Wet rails — reduced adhesion, speed capped at 6 m/s.",
            "Rails humides — adhérence réduite, vitesse limitée à 6 m/s.",
            "warn",
        )
    elif kind == "motor_degraded":
        # One of the three 800 kW DC motor groups dropped out — service
        # continues on 2/3 motors (real Von Roll redundancy design).
        # Sassi-Superga precedent : specific motor named (M1/M2/M3).
        tr.motor_count = 2
        tr.motor_id_down = random.choice([1, 2, 3])
        tr.speed_fault_cap = 9.0
        tr.fault_timer = 90.0
        mid = tr.motor_id_down
        add_event(
            st, "motor_degraded",
            f"Motor group M{mid} fault — degraded mode 2/3, v≤9 m/s.",
            f"Groupe moteur M{mid} HS — mode dégradé 2/3, v≤9 m/s.",
            "warn",
        )
    elif kind == "slack":
        # Cable slack detected : momentary drop of tension (can happen
        # when the heavier train decelerates abruptly and the elastic
        # 3.5 km of 52 mm Fatzer unloads). Safety : if it persists the
        # slack-cable switch trips the emergency.
        tr.slack_fault_dan = 8000.0
        tr.fault_timer = 12.0
        add_event(
            st, "slack",
            "Cable slack detected −8 000 daN — brake smoothly.",
            "Mou du câble détecté −8 000 daN — freiner doucement.",
            "warn",
        )
    elif kind == "aux_power":
        # Loss of 400 V auxiliaries : traction contactor drops, drum
        # brake clamps. Train coasts then stops. Self-resolves when the
        # backup feeder picks up.
        tr.aux_power_fault = True
        tr.fault_timer = 25.0
        add_event(
            st, "aux_power",
            "400 V auxiliaries lost — traction cut, brake held.",
            "Auxiliaires 400 V perdus — traction coupée, frein serré.",
            "alarm",
        )
    elif kind == "parking_stuck":
        # Parking (drum) brake release failure : motor can't move the
        # pulley until the driver resets via the emergency-stop cycle.
        tr.parking_stuck = True
        tr.fault_timer = 18.0
        add_event(
            st, "parking_stuck",
            "Parking brake release failure — cycle emergency stop.",
            "Défaut déverrouillage frein parking — cycler arrêt d'urgence.",
            "warn",
        )
    elif kind == "cable_rupture":
        # Catastrophic : tractor cable severed (Glória Lisbon 2025, 16 deaths).
        # Tension collapses, service brake useless (Glória pattern : cable
        # rupture also killed the pneumatic service brake). Only the
        # parachute Belleville (emergency rail brake) can hold the cabin.
        tr.cable_rupture = True
        tr.service_brake_fail = 0.15
        tr.slack_fault_dan = 18000.0
        tr.emergency = True
        tr.fault_timer = 120.0
        add_event(
            st, "cable_rupture",
            "CABLE RUPTURE ! parachute brake only — Glória-class event.",
            "RUPTURE CÂBLE ! frein parachute seul — événement type Glória.",
            "alarm",
        )
    elif kind == "service_brake_fail":
        # Hydraulic service brake fade — driver commanded brake % is
        # only partly effective. Emergency parachute still works.
        tr.service_brake_fail = 0.25
        tr.fault_timer = 45.0
        add_event(
            st, "service_brake_fail",
            "Service brake fade — use emergency to stop.",
            "Frein de service inopérant — utiliser l'urgence pour arrêter.",
            "alarm",
        )
    elif kind == "flood_tunnel":
        # Water ingress in tunnel (glacier-fed section). Adhesion collapses
        # far below wet_rail — cap at 4 m/s.
        tr.flood_tunnel = True
        tr.speed_fault_cap = 4.0
        tr.fault_timer = 60.0
        add_event(
            st, "flood_tunnel",
            "Tunnel water ingress — adhesion critical, v≤4 m/s.",
            "Inondation tunnel — adhérence critique, v≤4 m/s.",
            "warn",
        )
    elif kind == "comms_loss":
        # PA + GSM relays lost (narrative — Kaprun lesson). No physics
        # effect but scores down driver's situational awareness.
        tr.comms_loss = True
        tr.fault_timer = 40.0
        add_event(
            st, "comms_loss",
            "Tunnel PA + radio lost — passengers isolated.",
            "PA + radio tunnel perdus — passagers isolés.",
            "warn",
        )
    elif kind == "switch_abt_fault":
        # Abt crossing (siding at mid-length) misalignment — train must
        # hold before the siding point until the interlock clears.
        tr.switch_abt_fault = True
        tr.speed_fault_cap = 2.0
        tr.fault_timer = 50.0
        add_event(
            st, "switch_abt_fault",
            "Abt crossing misaligned — crawl to siding, v≤2 m/s.",
            "Aiguillage Abt désaligné — marche au pas vers l'évitement, v≤2 m/s.",
            "warn",
        )
    elif kind == "fire_vent_fail":
        # Fire + tunnel vent (desenfumage) failed — the single worst
        # compound fault documented (Kaprun class). Extended timer.
        tr.emergency = True
        tr.fire_vent_fail = True
        tr.fault_timer = 120.0
        add_event(
            st, "fire_vent_fail",
            "FIRE + VENT FAILURE — evacuate, desenfumage offline.",
            "FEU + DÉSENFUMAGE HS — évacuation, ventilation coupée.",
            "alarm",
        )


# ---------------------------------------------------------------------------
# HUD and rendering
# ---------------------------------------------------------------------------

COLOR_BG_TOP = QColor(12, 20, 34)
COLOR_BG_BOT = QColor(34, 48, 72)
COLOR_MOUNT_1 = QColor(58, 50, 45)
COLOR_MOUNT_2 = QColor(86, 76, 68)
COLOR_MOUNT_FAR = QColor(108, 118, 140)   # atmospheric haze (distant ridges)
COLOR_MOUNT_MID = QColor(74, 72, 78)      # mid-distance ridge
COLOR_GLACIER = QColor(232, 240, 252)
COLOR_GLACIER_SHADE = QColor(186, 202, 226)
COLOR_PINE = QColor(32, 58, 42)
COLOR_PINE_HILIGHT = QColor(56, 92, 64)
COLOR_PYLON = QColor(120, 110, 104)
COLOR_CLOUD = QColor(235, 238, 245, 200)
COLOR_CLOUD_SHADE = QColor(190, 200, 215, 170)
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

# Ghost wagon cylindrical bands — 7 horizontal slices shaded bottom→top
# for a 3D cylinder look. Hoisted to module scope so QColors are built
# once instead of 60×/s while the ghost is on screen.
_GHOST_BANDS = (
    (0.00, 0.35,  QColor(18, 16, 14, 240)),    # undercarriage
    (0.35, 0.55,  QColor(60, 48, 22, 235)),    # bogie fairing
    (0.55, 1.20,  QColor(150, 120, 38, 230)),  # lower body (shadow)
    (1.20, 2.05,  QColor(185, 150, 48, 230)),  # window band base
    (2.05, 2.70,  QColor(220, 185, 68, 230)),  # upper body (lit)
    (2.70, 3.05,  QColor(205, 168, 55, 230)),  # shoulder
    (3.05, 3.20,  QColor(120, 95, 30, 230)),   # roof curve cap
)


# ---------------------------------------------------------------------------
# Sound system — plays the real Perce-Neige on-board announcements
# ---------------------------------------------------------------------------

def _plan_ambient_paths(dest_dir: Path) -> dict[str, Path]:
    """Return the full set of WAV paths without generating any content.
    Used to populate the SoundSystem dict synchronously so consumers
    can guard on `.exists()` while the heavy synthesis runs in a
    background thread on first launch.
    """
    out: dict[str, Path] = {
        "rumble": dest_dir / "ambient_rumble.wav",
        "motor": dest_dir / "motor_hum.wav",
        "buzzer": dest_dir / "departure_buzzer.wav",
        "horn": dest_dir / "horn_v3.wav",
    }
    for key, name in (
        ("ambient_real", "ambient_real.wav"),
        ("buzzer_real", "departure_buzzer_real.wav"),
        ("buzzer_bas", "departure_buzzer_bas.wav"),
        ("departure_ambient", "departure_ambient.wav"),
    ):
        out[key] = dest_dir / name
    # Real cabin-interior ambient segments extracted from the
    # 10-minute HD cabin recording. Shipped inside the .exe under
    # sons/ambients/, loaded here by _resolve_bundled_ambients
    # later — the Path values below are placeholders that the
    # resolver will overwrite with the real bundled locations.
    out["ambient_cruise"] = dest_dir / "ambient_cruise.wav"
    out["ambient_slow"] = dest_dir / "ambient_slow.wav"
    return out


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
    # Horn WAV : industrial two-tone pneumatic funicular horn, seamless
    # 1 s loop (no envelope so setLoops(Infinite) doesn't click). Two
    # dissonant fundamentals (220/277 Hz — a major third) with strong
    # sawtooth-like harmonic stack for brass bite, pressurised-air
    # hiss overlay, and a slow beat to feel alive. Peak-limited to
    # just below full scale for max loudness without clipping.
    horn = dest_dir / "horn_v3.wav"
    if not horn.exists():
        dur_h = 1.0
        n_h = int(sample_rate * dur_h)
        data_h = bytearray()
        f1_h, f2_h = 220.0, 277.0  # major-third dyad, loud & dissonant
        prev_n = 0.0
        for i in range(n_h):
            t_h = i / sample_rate
            # Sawtooth-approximated brass via summed harmonics 1..8
            s_h = 0.0
            for k in range(1, 9):
                amp = 1.0 / k
                s_h += _m.sin(2 * _m.pi * f1_h * k * t_h) * amp * 0.55
                s_h += _m.sin(2 * _m.pi * f2_h * k * t_h) * amp * 0.50
            # Subharmonic for chest-punch
            s_h += _m.sin(2 * _m.pi * (f1_h * 0.5) * t_h) * 0.25
            # Pressurised-air hiss (band-passed white noise, low-level)
            white = _r.uniform(-1.0, 1.0)
            prev_n = prev_n * 0.75 + white * 0.25
            s_h += prev_n * 0.18
            # Slight 5 Hz tremolo to feel like a mechanical horn
            s_h *= 0.82 + 0.08 * _m.sin(2 * _m.pi * 5.0 * t_h)
            # Soft clip — keeps perceived loudness high without harsh clip
            s_h = _m.tanh(s_h * 0.55) * 0.80
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
        self._seq_on_complete = None
        self._close_seq_active = False
        self._crossing_active = False
        self._crossing_level = 0.0
        self._player = None
        self._audio = None
        self._horn_player = None
        self._horn_audio = None
        # Generate procedural ambient/buzzer WAVs (cached in temp dir)
        wav_dir = Path(tempfile.gettempdir()) / "perce_neige_wav"
        # Plan paths synchronously (cheap), defer heavy synthesis to a
        # daemon thread so first launch doesn't freeze the GUI. Every
        # consumer already guards with `.exists()`, so calls before the
        # thread finishes simply no-op. On subsequent launches the files
        # exist and the thread returns almost instantly.
        try:
            wav_dir.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
        self._ambient_wavs = _plan_ambient_paths(wav_dir)
        # Real cabin-ambient segments (cruise + slow) are shipped inside
        # the application (sons/ambients/) rather than synthesised. Point
        # the dict entries at their bundled location if present.
        bundled_amb_dir = project_dir / "sons" / "ambients"
        for key, filename in (("ambient_cruise", "ambient_cruise.wav"),
                              ("ambient_slow", "ambient_slow.wav"),
                              ("door_buzzer_real", "door_buzzer.wav"),
                              ("door_motion_real", "door_motion.wav"),
                              ("crossing_real", "crossing.wav"),
                              ("buzzer_real", "buzzer_upper.wav")):
            candidate = bundled_amb_dir / filename
            if candidate.exists():
                self._ambient_wavs[key] = candidate
        self._wav_gen_thread = threading.Thread(
            target=_generate_ambient_wavs,
            args=(wav_dir,),
            daemon=True,
        )
        self._wav_gen_thread.start()
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
            self._horn_audio.setVolume(0.70)
            self._horn_player.setAudioOutput(self._horn_audio)
            self._horn_player.setLoops(QMediaPlayer.Loops.Infinite)
            # Horn source is set lazily on first play() so we don't
            # block here if WAV generation is still running on the
            # background thread.
            self._horn_loaded = False
            # Two parallel ambient loops (slow + cruise) — crossfaded
            # by update_ambient so the mix matches the current speed
            # instead of a single 11-second loop heard over and over.
            # Each loop has its own QMediaPlayer + QAudioOutput.
            self._amb_player = QMediaPlayer()          # slow/approach loop
            self._amb_audio = QAudioOutput()
            self._amb_audio.setVolume(0.0)
            self._amb_player.setAudioOutput(self._amb_audio)
            self._amb_player.setLoops(QMediaPlayer.Loops.Infinite)
            self._amb2_player = QMediaPlayer()         # cruise loop
            self._amb2_audio = QAudioOutput()
            self._amb2_audio.setVolume(0.0)
            self._amb2_player.setAudioOutput(self._amb2_audio)
            self._amb2_player.setLoops(QMediaPlayer.Loops.Infinite)
            self._amb_playing = False
            self._amb2_playing = False
            self._amb_vol_target = 0.0
            self._amb2_vol_target = 0.0
            self._amb_loaded_path: str | None = None
            self._amb2_loaded_path: str | None = None
            self._fx_loaded_path: str | None = None
            # Dedicated player for door-warning buzzer + door-motion SFX
            # so they can overlap the announcement without ducking the
            # departure buzzer on _fx_player.
            self._door_player = QMediaPlayer()
            self._door_audio = QAudioOutput()
            self._door_audio.setVolume(0.80)
            self._door_player.setAudioOutput(self._door_audio)
            self._door_loaded_path: str | None = None
            # Dedicated player for the passing-loop crossing whoosh —
            # one-shot, plays over the ambient loops without ducking.
            self._cross_player = QMediaPlayer()
            self._cross_audio = QAudioOutput()
            self._cross_audio.setVolume(1.0)
            self._cross_player.setAudioOutput(self._cross_audio)
            self._cross_loaded_path: str | None = None
        except Exception:
            self.enabled = False

    # ----- public ----------------------------------------------------------

    def play(self, group: str, lang: str = "fr", cooldown: float = 30.0,
             strict: bool = False) -> None:
        """Queue an announcement. Per-group cooldown avoids spam.

        strict: if True, skip silently when the requested language is not
        available for this group (no fallback to another language).
        """
        if not self.enabled or self.muted:
            return
        if self._cooldowns.get(group, 0.0) > 0:
            return
        f = self._pick(group, lang, strict=strict)
        if f is None:
            return
        self._cooldowns[group] = cooldown
        self._queue.append(f)
        if self._player is None:
            return
        if self._player.playbackState() != QMediaPlayer.PlaybackState.PlayingState:
            self._play_next()

    def play_doors_close_sequence(self, lang: str = "fr",
                                  on_complete=None) -> None:
        """Chain the full doors-close sequence in series :
        announcement → door-warning buzzer → door-motion sound. Each
        clip waits for the previous one to finish. The optional
        *on_complete* callback fires when the motion sound ends —
        used by auto-exploitation to arm READY only after the doors
        have actually finished closing audibly.
        """
        def _wrap_done():
            self._close_seq_active = False
            if on_complete:
                on_complete()
        if not self.enabled or self.muted:
            _wrap_done()
            return
        if self._cooldowns.get("doors_close", 0.0) > 0:
            # Already playing very recently — skip but still run the
            # completion callback so the state machine doesn't stall.
            _wrap_done()
            return
        steps: list[Path] = []
        ann = self._pick("doors_close", lang)
        if ann is not None:
            steps.append(ann)
        buz = self._ambient_wavs.get("door_buzzer_real")
        if buz is not None and buz.exists():
            steps.append(buz)
        mot = self._ambient_wavs.get("door_motion_real")
        if mot is not None and mot.exists():
            steps.append(mot)
        if not steps or self._player is None:
            _wrap_done()
            return
        self._cooldowns["doors_close"] = 60.0
        # Push remaining steps into the queue so _on_status advances
        # through them automatically after each EndOfMedia. The
        # close-sequence-active flag blocks V (READY) until the final
        # motion sound finishes, so the driver can't depart before the
        # doors are audibly shut.
        self._close_seq_active = True
        self._queue = list(steps[1:])
        self._seq_on_complete = _wrap_done
        self._player.setSource(QUrl.fromLocalFile(str(steps[0])))
        self._player.play()

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
        if self._player is None:
            return
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
        spath = str(path)
        if self._fx_loaded_path != spath:
            self._fx_player.setSource(QUrl.fromLocalFile(spath))
            self._fx_loaded_path = spath
        self._fx_player.setLoops(1)
        self._fx_player.play()

    def play_door_buzzer(self) -> None:
        """Play the door-warning buzzer heard just before the leaves
        start closing (real cabin recording, t=1:08→1:15 of the HD
        ascent). Falls back silently if the extract is missing.
        """
        if not self.enabled or self.muted:
            return
        path = self._ambient_wavs.get("door_buzzer_real")
        if path is None or not path.exists():
            return
        spath = str(path)
        if self._door_loaded_path != spath:
            self._door_player.setSource(QUrl.fromLocalFile(spath))
            self._door_loaded_path = spath
        self._door_player.setLoops(1)
        self._door_player.play()

    def play_door_motion(self) -> None:
        """Play the door-motion sound (hydraulic whoosh + mechanical
        clunk) heard as the leaves actually close — real cabin recording
        t=1:15→1:22 of the HD ascent.
        """
        if not self.enabled or self.muted:
            return
        path = self._ambient_wavs.get("door_motion_real")
        if path is None or not path.exists():
            return
        spath = str(path)
        if self._door_loaded_path != spath:
            self._door_player.setSource(QUrl.fromLocalFile(spath))
            self._door_loaded_path = spath
        self._door_player.setLoops(1)
        self._door_player.play()

    def play_crossing(self) -> None:
        """Play the full 20-s passing-loop crossing ambience (real
        cabin recording, 4:40→5:00 of the HD ascent = exactly the
        switch-to-switch transit at 10.1 m/s). Ducks the main ambient
        loops so the crossing's distinctive rattle + airflow shift is
        actually audible instead of drowning under the cruise rumble.
        """
        if not self.enabled or self.muted:
            return
        path = self._ambient_wavs.get("crossing_real")
        if path is None or not path.exists():
            return
        spath = str(path)
        if self._cross_loaded_path != spath:
            self._cross_player.setSource(QUrl.fromLocalFile(spath))
            self._cross_loaded_path = spath
        self._cross_player.setLoops(1)
        # Flag picked up by update_ambient to ramp the crossing overlay
        # in smoothly and duck the main loops in sync. Cleared early by
        # update_ambient when the clip is near its end, or by the
        # EndOfMedia status signal as a safety net.
        self._crossing_active = True
        self._crossing_level = 0.0
        try:
            self._cross_audio.setVolume(0.0)
        except Exception:
            pass
        try:
            self._cross_player.mediaStatusChanged.disconnect(
                self._on_crossing_status)
        except Exception:
            pass
        self._cross_player.mediaStatusChanged.connect(
            self._on_crossing_status)
        self._cross_player.play()

    def _on_crossing_status(self, status) -> None:
        if status == QMediaPlayer.MediaStatus.EndOfMedia:
            self._crossing_active = False

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
        spath = str(path)
        if self._fx_loaded_path != spath:
            self._fx_player.setSource(QUrl.fromLocalFile(spath))
            self._fx_loaded_path = spath
        self._fx_player.play()

    def start_horn(self) -> None:
        """Start playing the horn (looped while held)."""
        if not self.enabled or self.muted:
            return
        if self._horn_player is None:
            return
        if not self._horn_loaded:
            horn_path = self._ambient_wavs.get("horn")
            if horn_path and horn_path.exists():
                self._horn_player.setSource(
                    QUrl.fromLocalFile(str(horn_path)))
                self._horn_loaded = True
            else:
                return  # WAV synth still running — silent this time
        # Duck announcement + fx channels while the horn sounds so the
        # OS mixer doesn't clip. Ambient ducking is handled inside
        # update_ambient (it runs every frame and would otherwise undo
        # the snapshot here). Snapshot so we can restore exactly.
        self._ducked = True
        try:
            self._pre_duck_audio = self._audio.volume()
            self._audio.setVolume(self._pre_duck_audio * 0.30)
        except Exception:
            pass
        try:
            self._pre_duck_fx = self._fx_audio.volume()
            self._fx_audio.setVolume(self._pre_duck_fx * 0.30)
        except Exception:
            pass
        self._horn_player.play()

    def stop_horn(self) -> None:
        """Stop the horn sound."""
        if self._horn_player is not None:
            self._horn_player.stop()
        if getattr(self, "_ducked", False):
            self._ducked = False
            try:
                self._audio.setVolume(self._pre_duck_audio)
            except Exception:
                pass
            try:
                self._fx_audio.setVolume(self._pre_duck_fx)
            except Exception:
                pass
            # Ambient targets are re-asserted by update_ambient on the
            # next tick (the _ducked flag is now False, so the 0.25
            # multiplier disappears on its own).

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
        """Crossfade real-cabin ambient loops based on speed.

        Two parallel loops run : a 25-second slow/approach segment and
        a 60-second steady-cruise segment, both extracted from the real
        10-minute HD cabin recording. The mix is driven by the current
        speed so that low speeds sound like the start-up/arrival phases
        and cruise sounds exactly like cruise, instead of hearing the
        same 11-second clip on repeat.

        Volume model (both loops summed, then scaled by |v|) :
          - |v| below 1 m/s      → both fade to zero (stationary silence)
          - |v| between 1..6 m/s → slow loop dominant, cruise fades in
          - |v| above 6 m/s      → cruise dominant, slow fades out
          - Peak ceiling ~0.95 so it actually feels like being inside the
            cabin (the old 0.35 ceiling was the weak-ambient complaint).
        """
        if not self.enabled or self.muted:
            if self._amb_playing:
                self._amb_player.stop()
                self._amb_playing = False
            if self._amb2_playing:
                self._amb2_player.stop()
                self._amb2_playing = False
            return
        v = abs(speed)
        # Cruise-dominance factor : 0 at v=1 m/s, 1 at v=7 m/s and above.
        lo, hi = 1.0, 7.0
        cruise_mix = 0.0 if v <= lo else (
            1.0 if v >= hi else (v - lo) / (hi - lo))
        # Overall scale from speed : silent when halted, full at V_MAX.
        v_norm = min(v / 10.0, 1.0)
        overall = v_norm * 0.95  # new ceiling (was 0.35)
        # Duck ambient hard while the horn is sounding — update_ambient
        # runs every frame so it would otherwise undo start_horn()'s
        # snapshot-based ducking the very next tick.
        if getattr(self, "_ducked", False):
            overall *= 0.25
        # Passing-loop crossing : smooth cross-fade on entry AND exit.
        # _crossing_level ramps 0→1 while active, 1→0 once we near the
        # end of the clip (or EndOfMedia fires). Applied both to the
        # ambient duck and to the crossing overlay volume so the switch
        # rattle comes in and out with a proper fade, not a hard swap.
        active = getattr(self, "_crossing_active", False)
        if active:
            try:
                pos = self._cross_player.position()
                dur = self._cross_player.duration()
                if dur > 0 and dur - pos < 1500:
                    self._crossing_active = False
                    active = False
            except Exception:
                pass
        target_lvl = 1.0 if active else 0.0
        diff_lvl = target_lvl - self._crossing_level
        if abs(diff_lvl) > 0.005:
            self._crossing_level += diff_lvl * 0.08
        else:
            self._crossing_level = target_lvl
        if self._crossing_level > 0.001:
            overall *= (1.0 - 0.60 * self._crossing_level)
            try:
                self._cross_audio.setVolume(self._crossing_level)
            except Exception:
                pass
        elif not active:
            try:
                self._cross_audio.setVolume(0.0)
            except Exception:
                pass
        # Individual targets. A small overlap floor (0.12) on the slow
        # loop when cruising adds grit so the cruise isn't clinical.
        slow_mix = (1.0 - cruise_mix) + 0.12 * cruise_mix
        self._amb_vol_target = overall * slow_mix
        self._amb2_vol_target = overall * cruise_mix

        slow_path = self._ambient_wavs.get("ambient_slow")
        cruise_path = self._ambient_wavs.get("ambient_cruise")
        # Legacy fallback if bundled extracts are missing
        if not (slow_path and slow_path.exists()):
            slow_path = self._ambient_wavs.get("ambient_real")
        if not (slow_path and slow_path.exists()):
            slow_path = self._ambient_wavs.get("rumble")
        if not (cruise_path and cruise_path.exists()):
            cruise_path = slow_path

        moving = v_norm > 0.02

        # Start / stop slow loop
        if moving and not self._amb_playing:
            if slow_path and slow_path.exists():
                spath = str(slow_path)
                if self._amb_loaded_path != spath:
                    self._amb_player.setSource(QUrl.fromLocalFile(spath))
                    self._amb_loaded_path = spath
                self._amb_player.play()
                self._amb_playing = True
        elif not moving and self._amb_playing:
            self._amb_player.stop()
            self._amb_playing = False

        # Start / stop cruise loop
        if moving and not self._amb2_playing:
            if cruise_path and cruise_path.exists():
                spath = str(cruise_path)
                if self._amb2_loaded_path != spath:
                    self._amb2_player.setSource(QUrl.fromLocalFile(spath))
                    self._amb2_loaded_path = spath
                self._amb2_player.play()
                self._amb2_playing = True
        elif not moving and self._amb2_playing:
            self._amb2_player.stop()
            self._amb2_playing = False

        # Smooth volume ramps (~150 ms to target at 60 fps)
        for audio, target in ((self._amb_audio, self._amb_vol_target),
                              (self._amb2_audio, self._amb2_vol_target)):
            cur = audio.volume()
            diff = target - cur
            if abs(diff) > 0.005:
                audio.setVolume(cur + diff * 0.15)

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
            self._amb2_player.stop()
            self._amb_playing = False
            self._amb2_playing = False
            self._queue.clear()
        return self.muted

    def stop(self) -> None:
        self._queue.clear()
        if self._player is not None:
            self._player.stop()
            self._fx_player.stop()
            self._horn_player.stop()
            self._amb_player.stop()
            self._amb2_player.stop()
            self._amb_playing = False
            self._amb2_playing = False

    def reset(self) -> None:
        self._queue.clear()
        self._cooldowns.clear()
        if self._player is not None:
            self._player.stop()
            self._fx_player.stop()
            self._horn_player.stop()
            self._amb_player.stop()
            self._amb2_player.stop()
            self._amb_playing = False
            self._amb2_playing = False

    # ----- internals -------------------------------------------------------

    def _pick(self, group: str, lang: str,
              strict: bool = False) -> Path | None:
        rng = self.GROUPS.get(group)
        if rng is None:
            return None
        start, end = rng
        offset = self.LANG_OFFSET.get(lang, 0)
        target = start + offset
        # Strict mode : only return the exact requested language, no
        # fallback. Used by the F2 manual announcement menu so choosing
        # Italian never plays French instead.
        if strict:
            if start <= target <= end and target in self._files_by_num:
                return self._files_by_num[target]
            return None
        # Lenient mode : try requested, then FR, then EN, then any.
        for candidate in (target, start, start + 1):
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
            if self._queue:
                self._play_next()
            elif self._seq_on_complete is not None:
                cb = self._seq_on_complete
                self._seq_on_complete = None
                try:
                    cb()
                except Exception:
                    pass


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


class AutoOps:
    """Background-mode operations simulator.

    Drives the full day of service automatically : boarding, doors
    close, buzzer, trip, arrival, doors open, turnaround, next trip.
    Respects real published operating hours, switches between peak and
    off-peak cruise speeds, varies passenger loads by time-of-day, and
    logs every trip to `exploitation.db` so you can browse the day
    later. Meant to be run in the background for ambient sound.

    Phases of the state machine :
      IDLE            — outside operating hours, doors closed, parked.
      PRE_OPEN        — waiting for first departure time.
      BOARDING        — doors open at a terminus, passengers load for
                        `dwell_s` seconds (60 s default).
      CLOSING         — doors closing chime + motion SFX.
      READY_WAIT      — driver arms READY, waits for ghost READY.
      DEPARTING       — buzzer countdown before trip_started flips True.
      TRANSIT         — train rolling between termini at the current
                        cruise setpoint.
      ARRIVING        — final approach + full stop at the far platform.
      DOORS_OPENING   — doors open, prepare for next cycle / reversal.
    """

    PHASE_IDLE = "IDLE"
    PHASE_PRE_OPEN = "PRE_OPEN"
    PHASE_BOARDING = "BOARDING"
    PHASE_CLOSING = "CLOSING"
    PHASE_READY_WAIT = "READY_WAIT"
    PHASE_DEPARTING = "DEPARTING"
    PHASE_TRANSIT = "TRANSIT"
    PHASE_ARRIVING = "ARRIVING"
    PHASE_DOORS_OPENING = "DOORS_OPENING"

    def __init__(self, widget: "GameWidget") -> None:
        self.w = widget
        self.enabled = False
        # When True, ignore published opening/closing hours and keep
        # ascents allowed — lets the user run the line 24/7 for testing
        # or ambient replay outside real Perce-Neige service windows.
        self.force_any_hours = False
        self.phase = self.PHASE_IDLE
        self.phase_t = 0.0          # seconds in current phase
        self.station_dwell_s = 20.0 # 20 s doors-open at each terminus
        # Published Perce-Neige operating hours (winter reference).
        # Ski season: 08:45 lower → 16:45 upper return. Last ascent
        # leaves the lower station at 16:30 so all passengers make it
        # back before the line shuts.
        self.open_h = 8
        self.open_m = 45
        self.close_h = 16
        self.close_m = 45
        self.last_ascent_h = 16
        self.last_ascent_m = 30
        # Peak windows (2h morning rush + 2h late-afternoon descent).
        # During these, cruise setpoint is 100 % (12 m/s). Off-peak
        # runs at 86 % ≈ 10.3 m/s, matching the real 7:54 trip time.
        self.peak_windows = [
            ((9, 0), (12, 0)),
            ((14, 0), (16, 0)),
        ]
        self.peak_cmd = 1.00
        self.offpeak_cmd = 10.3 / V_MAX
        # Daily counters (reset at midnight or when the mode flips on
        # a new calendar day).
        self.day_key = ""
        self.day_trips = 0
        self.day_pax = 0
        self.day_distance_m = 0.0
        self.day_started_at: datetime | None = None
        # Current leg tracking (for trip log).
        self._leg_depart_ts: datetime | None = None
        self._leg_depart_s = 0.0
        self._leg_direction = 0
        self._leg_pax = 0
        self._leg_peak = False
        self._leg_incidents = 0
        # True once the full doors-close audio chain finishes.
        self._sequence_done = False
        # Init logger DB
        self._log = AutoOpsLogger()
        self._log.ensure_schema()
        self._refresh_day_counters()

    # ---------- public API ----------------------------------------------

    def toggle(self) -> bool:
        self.enabled = not self.enabled
        if self.enabled:
            self._refresh_day_counters()
            self.phase_t = 0.0
            # Auto-exploitation needs a live simulation : jump out of
            # the title / over / paused screens into MODE_RUN so the
            # physics, door timers and sound tick run. Also clear any
            # latched emergency / electric stop left from a previous
            # trip — otherwise the door-close sequence stalls forever
            # and the cabin stays stuck with brakes biting.
            state = self.w.state
            tr = state.train
            if state.mode != MODE_RUN:
                state.mode = MODE_RUN
            tr.emergency = False
            tr.electric_stop = False
            tr.dead_man_fault = False
            tr.overspeed_tripped = False; tr.overspeed_level = 0
            tr.brake = 0.0
            state.pending_incident = False
            # Pick the right phase based on where the train actually is
            # so enabling auto-ops mid-trip resumes the run instead of
            # parking in IDLE until the next terminus arrival.
            at_terminus = ((tr.s <= START_S + 5.0)
                           or (tr.s >= STOP_S - 5.0))
            if state.trip_started and not state.finished:
                # Mid-tunnel takeover : skip straight to TRANSIT and let
                # the regulator keep driving.
                tr.maint_brake = False
                # Re-assert a sensible cruise setpoint (real clock picks
                # peak vs off-peak).
                peak = self._is_peak(now := datetime.now())
                tr.speed_cmd = self.peak_cmd if peak else self.offpeak_cmd
                self._leg_peak = peak
                if self._leg_depart_ts is None:
                    self._leg_depart_ts = now
                    self._leg_depart_s = tr.s
                    self._leg_direction = tr.direction
                    self._leg_pax = tr.pax
                    self._leg_incidents = 0
                tr.lights_head = True
                self.phase = self.PHASE_TRANSIT
            elif state.finished or at_terminus:
                # At a terminus with doors open/closed : begin boarding.
                # Stale trip_started flags from a just-finished manual
                # trip are cleared so the IDLE branch can begin boarding
                # (otherwise IDLE's at_terminus/trip_started guard blocks
                # the handoff and the state machine sits forever).
                tr.maint_brake = False
                state.finished = False
                state.trip_started = False
                state.ghost_ready = False
                state.ghost_ready_timer = 0.0
                state.ghost_ready_delay = 0.0
                state.departure_buzzer_remaining = 0.0
                self.phase = self.PHASE_IDLE
            else:
                # Stopped mid-tunnel (e.g. after an incident). Launch a
                # fresh departure sequence : pre-arm ready + buzzer.
                tr.maint_brake = False
                tr.ready = True
                state.ghost_ready_timer = 0.0
                state.ghost_ready_delay = random.uniform(2.0, 4.0)
                self.phase = self.PHASE_READY_WAIT
            add_event(state, "ops",
                      "Auto-exploitation ENABLED",
                      "Exploitation auto ACTIVÉE", "info")
        else:
            # Disabling mid-cycle must not leave the train armed for
            # departure. Only cancel the arming if we're still in a
            # pre-departure phase — a mid-trip disable leaves the
            # physics trip alone so the cabin can coast to its stop.
            state = self.w.state
            tr = state.train
            pre_departure = self.phase in (
                self.PHASE_IDLE, self.PHASE_PRE_OPEN,
                self.PHASE_BOARDING, self.PHASE_CLOSING,
                self.PHASE_READY_WAIT, self.PHASE_DEPARTING,
            )
            if pre_departure and not state.trip_started:
                tr.ready = False
                state.ghost_ready = False
                state.ghost_ready_timer = 0.0
                state.ghost_ready_delay = 0.0
                state.departure_buzzer_remaining = 0.0
                tr.speed_cmd = 0.0
            self.phase = self.PHASE_IDLE
            self.phase_t = 0.0
            add_event(self.w.state, "ops",
                      "Auto-exploitation disabled",
                      "Exploitation auto désactivée", "info")
        return self.enabled

    def tick(self, dt: float) -> None:
        if not self.enabled:
            return
        now = datetime.now()
        day_key = now.strftime("%Y-%m-%d")
        if day_key != self.day_key:
            self._refresh_day_counters()
        self.phase_t += dt
        state = self.w.state
        tr = state.train
        # Safety net : the AI driver never engages emergency or
        # electric stop on its own. If something latched one — stray
        # Shift keystroke, overspeed trip, etc. — release it now so
        # the state machine doesn't stall mid-cycle while the brake
        # announcement loops on top.
        if tr.emergency or tr.electric_stop or tr.overspeed_tripped:
            tr.emergency = False
            tr.electric_stop = False
            tr.overspeed_tripped = False; tr.overspeed_level = 0
            tr.maint_brake = False
            tr.brake = 0.0
        # During any pre-departure phase the drum must stay engaged so
        # the regulator can't accidentally pull the train out of the
        # platform between doors-closed and buzzer-end. Released by the
        # buzzer-end logic (line ~3337) when trip_started flips True —
        # so we only force the drum on while trip_started is still
        # False (otherwise we'd re-clamp it after the buzzer expired
        # and the train would never leave).
        if (not state.trip_started
                and self.phase in (self.PHASE_BOARDING,
                                   self.PHASE_CLOSING,
                                   self.PHASE_READY_WAIT,
                                   self.PHASE_DEPARTING)):
            tr.maint_brake = True
        in_hours = self._within_operating_hours(now)
        allow_new_ascent = self._allow_new_ascent(now)

        # ---- State machine ------------------------------------------
        if self.phase == self.PHASE_IDLE:
            # Park with doors shut. When opening time is reached,
            # unlock the platform and move to BOARDING.
            if tr.doors_open and tr.doors_cmd:
                pass  # already open, decide below
            if in_hours:
                # Open doors at terminus for boarding.
                at_terminus = (tr.s <= START_S + 5.0) or (tr.s >= STOP_S - 5.0)
                if at_terminus and not state.trip_started and not state.finished:
                    self._begin_boarding(now)
                elif state.finished:
                    self._begin_boarding(now)
            return

        elif self.phase == self.PHASE_BOARDING:
            # Ensure doors are open (they usually are at arrival).
            if not tr.doors_cmd:
                tr.doors_cmd = True
                tr.doors_timer = DOOR_OPEN_TIME
                self.w.sounds.play_door_motion()
            if self.phase_t >= self.station_dwell_s:
                # If it's past the last-ascent cutoff and we're at the
                # lower terminus, end the day instead of sending another
                # ascent. The last descent still runs naturally once the
                # upper train returns.
                if (not allow_new_ascent and tr.direction > 0
                        and tr.s <= START_S + 5.0):
                    self._enter_idle("Last ascent cutoff — ending service",
                                     "Fin de service — dernière montée passée")
                    return
                if not in_hours:
                    self._enter_idle("Operating hours ended",
                                     "Fin des horaires d'exploitation")
                    return
                self._set_phase(self.PHASE_CLOSING)
                add_event(state, "ops",
                          "Auto : closing doors",
                          "Auto : fermeture des portes", "info")
                # Trigger the real doors-close sequence : announcement
                # → warning buzzer → door-motion sound, each waiting
                # for the previous to finish. When the motion clip
                # ends, arm READY via the callback.
                tr.doors_cmd = False
                tr.doors_timer = DOOR_CLOSE_TIME
                self._sequence_done = False
                def _on_doors_shut() -> None:
                    self._sequence_done = True
                self.w.sounds.play_doors_close_sequence(
                    lang=state.ann_lang, on_complete=_on_doors_shut)

        elif self.phase == self.PHASE_CLOSING:
            # Wait until both the physical doors-close timer AND the
            # full audio sequence (announcement → buzzer → motion)
            # have finished, then arm READY.
            physical_ok = (not tr.doors_open and tr.doors_timer <= 0.0)
            if physical_ok and getattr(self, "_sequence_done", False):
                tr.ready = True
                state.ghost_ready = False
                state.ghost_ready_timer = 0.0
                state.ghost_ready_delay = random.uniform(2.0, 4.0)
                self._set_phase(self.PHASE_READY_WAIT)
                add_event(state, "ops",
                          "Auto : READY armed — waiting ghost cabin",
                          "Auto : PRÊT armé — attente autre rame",
                          "info")

        elif self.phase == self.PHASE_READY_WAIT:
            # Backup ghost-ready countdown : the authoritative one lives
            # in the MODE_RUN branch of MainWindow._tick (physics step),
            # but we replicate it here so auto-exploitation can never
            # stall in READY_WAIT if that branch is gated out (pause,
            # alternate modes, etc.). Safe because both sites guard on
            # "not ghost_ready".
            if (tr.ready and not state.ghost_ready
                    and state.ghost_ready_delay > 0.0):
                state.ghost_ready_timer += dt
                if state.ghost_ready_timer >= state.ghost_ready_delay:
                    state.ghost_ready = True
                    add_event(state, "ready",
                              "Second cabin reports ready",
                              "Autre rame prête",
                              "info")
            # If the delay was zeroed by a previous incident path,
            # re-prime it now so the sequence can actually advance.
            if tr.ready and state.ghost_ready_delay <= 0.0 and not state.ghost_ready:
                state.ghost_ready_timer = 0.0
                state.ghost_ready_delay = random.uniform(2.0, 4.0)
            if state.ghost_ready:
                # Both ready → fire departure buzzer + set speed_cmd.
                # Peak/off-peak decision driven by real clock.
                peak = self._is_peak(now)
                tr.speed_cmd = self.peak_cmd if peak else self.offpeak_cmd
                self._leg_peak = peak
                # Replicate the Key_Z path without requiring the key.
                at_upper = tr.direction == -1
                at_station = ((tr.s <= START_S + 5.0)
                              or (tr.s >= STOP_S - 5.0))
                if at_station:
                    BUZZER_DURATION = 6.5 if at_upper else 8.0
                    state.departure_buzzer_remaining = BUZZER_DURATION
                    self.w.sounds.play_buzzer(upper_station=at_upper)
                else:
                    state.departure_buzzer_remaining = 1.5
                self._leg_depart_ts = now
                self._leg_depart_s = tr.s
                self._leg_direction = tr.direction
                self._leg_pax = self._sample_pax_load(now, tr.direction)
                tr.pax_car1 = self._leg_pax // 2
                tr.pax_car2 = self._leg_pax - tr.pax_car1
                # tr.pax and tr.mass_kg are computed properties
                # (pax_car1 + pax_car2), so they update automatically.
                self._leg_incidents = 0
                self._set_phase(self.PHASE_DEPARTING)
                add_event(state, "ops",
                          "Auto : departure buzzer",
                          "Auto : buzzer de départ", "info")

        elif self.phase == self.PHASE_DEPARTING:
            if state.trip_started:
                tr.lights_head = True
                self._set_phase(self.PHASE_TRANSIT)
                add_event(state, "ops",
                          "Auto : departing — in transit",
                          "Auto : en voie", "info")

        elif self.phase == self.PHASE_TRANSIT:
            # Small panic actions : if autopilot flagged an incident,
            # count it for the log. Otherwise the physics/regulator
            # runs the trip.
            if state.panne_active:
                self._leg_incidents += 1
            # Direction-aware approach detection. ARRIVING is only
            # meaningful when the train is nearing its actual
            # destination, not when it has just left the opposite
            # terminus (which would both fire the 120 m proximity
            # check otherwise and lock the state machine before the
            # regulator has even ramped speed_cmd_eff above 1 m/s).
            near_dest = (
                (tr.direction > 0 and tr.s >= STOP_S - 120.0)
                or (tr.direction < 0 and tr.s <= START_S + 120.0)
            )
            # Extinguish headlights a short distance before the
            # platform, as a real driver does.
            if near_dest and tr.lights_head:
                tr.lights_head = False
            if state.finished:
                self._set_phase(self.PHASE_ARRIVING)
            elif abs(tr.v) < 1.0 and state.trip_started and near_dest:
                self._set_phase(self.PHASE_ARRIVING)

        elif self.phase == self.PHASE_ARRIVING:
            if state.finished and abs(tr.v) < 0.05:
                self._finalize_leg(now)
                # Open doors at this terminus and start the next cycle
                # by reversing the direction.
                self.w.reverse_trip(silent=True)
                self._set_phase(self.PHASE_DOORS_OPENING)
                add_event(state, "ops",
                          "Auto : arrived — opening doors & turnaround",
                          "Auto : arrivé — ouverture portes & demi-tour",
                          "info")

        elif self.phase == self.PHASE_DOORS_OPENING:
            # reverse_trip already set doors_open=True at a terminus.
            # Wait a beat so the announcements play, then begin next
            # boarding cycle.
            if self.phase_t >= 3.0:
                self._begin_boarding(now)
                add_event(state, "ops",
                          "Auto : boarding new leg",
                          "Auto : embarquement nouveau trajet",
                          "info")

    # ---------- internals -----------------------------------------------

    def _set_phase(self, phase: str) -> None:
        self.phase = phase
        self.phase_t = 0.0

    def _enter_idle(self, msg_en: str, msg_fr: str) -> None:
        add_event(self.w.state, "ops", msg_en, msg_fr, "info")
        self._set_phase(self.PHASE_IDLE)

    def _begin_boarding(self, now: datetime) -> None:
        self._set_phase(self.PHASE_BOARDING)
        tr = self.w.state.train
        # Boarding must start with the cabin absolutely parked :
        # drum engaged, setpoint at 0, otherwise as soon as the doors
        # finish closing in CLOSING the regulator would see a live
        # setpoint (reverse_trip/new_trip leave it at 100 %) and pull
        # the train out of the platform on its own — before READY +
        # buzzer. The drum is released by the buzzer-end logic when
        # trip_started flips True.
        tr.maint_brake = True
        tr.speed_cmd = 0.0
        tr.speed_cmd_eff = 0.0
        tr.throttle = 0.0
        tr.brake = 0.0
        # Doors open if they aren't already
        if not tr.doors_cmd:
            tr.doors_cmd = True
            tr.doors_timer = DOOR_OPEN_TIME
            self.w.sounds.play_door_motion()

    def _within_operating_hours(self, now: datetime) -> bool:
        if self.force_any_hours:
            return True
        t = now.time()
        open_t = dtime(self.open_h, self.open_m)
        close_t = dtime(self.close_h, self.close_m)
        return open_t <= t <= close_t

    def _allow_new_ascent(self, now: datetime) -> bool:
        if self.force_any_hours:
            return True
        t = now.time()
        return t < dtime(self.last_ascent_h, self.last_ascent_m)

    def _is_peak(self, now: datetime) -> bool:
        t = now.time()
        for (h1, m1), (h2, m2) in self.peak_windows:
            if dtime(h1, m1) <= t < dtime(h2, m2):
                return True
        return False

    def _is_summer_ski_season(self, now: datetime) -> bool:
        """Grande Motte glacier summer-ski window.

        Historically mid-June to end of July (exact dates vary with
        snow cover and operator). We use June 15 → July 31 as a
        reasonable ballpark. Session runs in the morning and closes
        around midday when the snow softens.
        """
        m, d = now.month, now.day
        if m == 6 and d >= 15:
            return True
        if m == 7:
            return True
        return False

    def _sample_pax_load(self, now: datetime, direction: int) -> int:
        """Return a pseudo-random passenger count tied to time of day.

        Ski-season reality : skiers only *go up* by funicular and come
        back down on skis, so ascents carry the full load (rush in
        late morning) while descents are almost always empty. The
        single exception is summer ski on the Grande Motte glacier
        (mid-June → end of July) : the session closes around midday
        when the snow softens, so descents become heavy right when
        the glacier shuts for the day.
        """
        hr = now.hour + now.minute / 60.0
        summer = self._is_summer_ski_season(now)
        if direction > 0:   # ascending — skiers going up
            if summer:
                # Summer : early-morning rush (session opens ~07:30),
                # peak around 08:30, then fades out before noon close.
                frac = max(0.0, 1.0 - abs(hr - 8.5) / 2.5)
            else:
                # Winter : broader mid-morning peak around 10:15.
                frac = max(0.0, 1.0 - abs(hr - 10.25) / 3.0)
            base = 0.15 + 0.80 * frac
            base *= random.uniform(0.80, 1.15)
            base = max(0.0, min(0.95, base))
        else:               # descending
            if summer:
                # Summer : glacier session closes ~12:00, so descents
                # peak around 11:30-12:30.
                frac = max(0.0, 1.0 - abs(hr - 12.0) / 2.0)
                base = 0.10 + 0.75 * frac
                base *= random.uniform(0.80, 1.15)
                base = max(0.0, min(0.90, base))
            else:
                # Winter : skiers ski back down. Only staff, non-skiers,
                # late glacier visitors ride down — 0-10 % of capacity.
                base = random.uniform(0.0, 0.10)
        return int(334 * base)

    def _finalize_leg(self, now: datetime) -> None:
        tr = self.w.state.train
        if self._leg_depart_ts is None:
            return
        dist = abs(tr.s - self._leg_depart_s)
        duration = (now - self._leg_depart_ts).total_seconds()
        cruise = self.peak_cmd * V_MAX if self._leg_peak else self.offpeak_cmd * V_MAX
        self._log.write_trip(
            day=now.strftime("%Y-%m-%d"),
            depart_ts=self._leg_depart_ts,
            arrival_ts=now,
            direction=self._leg_direction,
            pax=self._leg_pax,
            cruise_m_s=cruise,
            distance_m=dist,
            duration_s=duration,
            incidents=self._leg_incidents,
            peak=self._leg_peak,
        )
        self.day_trips += 1
        self.day_pax += self._leg_pax
        self.day_distance_m += dist
        self._log.upsert_daily(
            day=now.strftime("%Y-%m-%d"),
            trips=self.day_trips,
            pax=self.day_pax,
            distance_m=self.day_distance_m,
        )

    def _refresh_day_counters(self) -> None:
        now = datetime.now()
        self.day_key = now.strftime("%Y-%m-%d")
        stats = self._log.read_daily(self.day_key)
        if stats is None:
            self.day_trips = 0
            self.day_pax = 0
            self.day_distance_m = 0.0
            self.day_started_at = now
        else:
            self.day_trips = stats["trips"]
            self.day_pax = stats["pax"]
            self.day_distance_m = stats["distance_m"]
            self.day_started_at = now


class AutoOpsLogger:
    """Thread-safe SQLite logger for the exploitation mode.

    Lives next to the project root so a single DB persists across
    sessions. WAL mode for concurrent read-while-write. TRUNCATE
    checkpoint on explicit close so the -wal/-shm side-files don't
    grow unbounded.
    """

    def __init__(self) -> None:
        self.db_path = _writable_dir() / "exploitation.db"
        self._lock = threading.Lock()

    def _connect(self) -> sqlite3.Connection:
        c = sqlite3.connect(str(self.db_path), timeout=5.0,
                            check_same_thread=False)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("PRAGMA synchronous=NORMAL")
        return c

    def ensure_schema(self) -> None:
        with self._lock, self._connect() as c:
            c.executescript("""
            CREATE TABLE IF NOT EXISTS trips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                day TEXT NOT NULL,
                depart_ts TEXT NOT NULL,
                arrival_ts TEXT NOT NULL,
                direction INTEGER NOT NULL,
                pax INTEGER NOT NULL,
                cruise_m_s REAL NOT NULL,
                distance_m REAL NOT NULL,
                duration_s REAL NOT NULL,
                incidents INTEGER NOT NULL,
                peak INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS ix_trips_day ON trips(day);
            CREATE TABLE IF NOT EXISTS daily_stats (
                day TEXT PRIMARY KEY,
                trips INTEGER NOT NULL,
                pax INTEGER NOT NULL,
                distance_m REAL NOT NULL
            );
            """)

    def write_trip(self, **k: Any) -> None:
        with self._lock, self._connect() as c:
            c.execute("""
                INSERT INTO trips (day, depart_ts, arrival_ts, direction,
                    pax, cruise_m_s, distance_m, duration_s,
                    incidents, peak)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            """, (
                k["day"],
                k["depart_ts"].isoformat(),
                k["arrival_ts"].isoformat(),
                int(k["direction"]),
                int(k["pax"]),
                float(k["cruise_m_s"]),
                float(k["distance_m"]),
                float(k["duration_s"]),
                int(k["incidents"]),
                1 if k["peak"] else 0,
            ))

    def upsert_daily(self, day: str, trips: int, pax: int,
                     distance_m: float) -> None:
        with self._lock, self._connect() as c:
            c.execute("""
                INSERT INTO daily_stats(day, trips, pax, distance_m)
                VALUES (?,?,?,?)
                ON CONFLICT(day) DO UPDATE SET
                    trips=excluded.trips,
                    pax=excluded.pax,
                    distance_m=excluded.distance_m
            """, (day, trips, pax, distance_m))

    def read_daily(self, day: str) -> dict | None:
        with self._lock, self._connect() as c:
            row = c.execute(
                "SELECT trips, pax, distance_m FROM daily_stats WHERE day=?",
                (day,)).fetchone()
            if row is None:
                return None
            return dict(row)

    def read_recent_trips(self, limit: int = 100) -> list[dict]:
        with self._lock, self._connect() as c:
            rows = c.execute("""
                SELECT day, depart_ts, arrival_ts, direction, pax,
                       cruise_m_s, distance_m, duration_s, incidents, peak
                FROM trips ORDER BY id DESC LIMIT ?
            """, (int(limit),)).fetchall()
            return [dict(r) for r in rows]

    def read_recent_daily(self, limit: int = 60) -> list[dict]:
        with self._lock, self._connect() as c:
            rows = c.execute("""
                SELECT day, trips, pax, distance_m
                FROM daily_stats ORDER BY day DESC LIMIT ?
            """, (int(limit),)).fetchall()
            return [dict(r) for r in rows]

    def checkpoint_truncate(self) -> None:
        try:
            with self._lock, self._connect() as c:
                c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        except Exception:
            pass


class DocsDownloadDialog(QDialog):
    """Downloads manuel_perce_neige.pdf and guide_theorique.pdf from the
    GitHub repo into the user's Downloads folder (or opens them if already
    bundled next to the EXE). Useful in the frozen EXE where the PDFs are
    not bundled — the user can grab the latest versions on demand."""

    REPO_BASE = "https://github.com/ARP273-ROSE/perce-neige-sim/raw/main"
    DOCS = [
        ("manuel_perce_neige.pdf",
         "Manuel utilisateur", "User manual"),
        ("guide_theorique.pdf",
         "Guide théorique (formules + sources)", "Theory guide (formulas + sources)"),
    ]

    def __init__(self, lang: str = "fr", parent: QWidget | None = None):
        super().__init__(parent)
        self._lang = lang
        self.setWindowTitle(
            "Documents PDF" if lang == "fr" else "PDF documents")
        self.setModal(True)
        self.setMinimumWidth(520)

        lay = QVBoxLayout(self)
        intro = QLabel(
            "<b>Documents</b><br>Téléchargez la dernière version du manuel "
            "et du guide théorique depuis GitHub. Le fichier s'enregistre "
            "dans votre dossier Téléchargements et s'ouvre automatiquement."
            if lang == "fr" else
            "<b>Documents</b><br>Download the latest manual and theory "
            "guide from GitHub. The file is saved to your Downloads folder "
            "and opened automatically."
        )
        intro.setWordWrap(True)
        lay.addWidget(intro)

        self._status = QLabel("")
        self._status.setWordWrap(True)
        lay.addWidget(self._status)

        for filename, fr_label, en_label in self.DOCS:
            btn = QPushButton(
                f"{'Télécharger' if lang == 'fr' else 'Download'} — "
                f"{fr_label if lang == 'fr' else en_label}",
                self
            )
            btn.setToolTip(f"{self.REPO_BASE}/{filename}")
            btn.clicked.connect(
                lambda _=False, f=filename: self._download(f))
            lay.addWidget(btn)

        close = QPushButton(
            "Fermer" if lang == "fr" else "Close", self)
        close.clicked.connect(self.accept)
        lay.addWidget(close)

    def _download(self, filename: str) -> None:
        import urllib.request, os
        url = f"{self.REPO_BASE}/{filename}"
        downloads = Path.home() / "Downloads"
        downloads.mkdir(exist_ok=True)
        dest = downloads / filename
        self._status.setText(
            (f"Téléchargement de {filename}…" if self._lang == "fr" else
             f"Downloading {filename}…")
        )
        QApplication.processEvents()
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": f"PerceNeige/{VERSION}"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            if len(data) < 1024:
                raise ValueError("file too small — check URL")
            dest.write_bytes(data)
            self._status.setText(
                (f"✓ Enregistré : {dest}" if self._lang == "fr" else
                 f"✓ Saved : {dest}")
            )
            # Open it in the default PDF viewer
            if os.name == "nt":
                os.startfile(str(dest))  # noqa: S606
            else:
                import subprocess
                opener = "open" if sys.platform == "darwin" else "xdg-open"
                subprocess.Popen([opener, str(dest)])  # noqa: S603
        except Exception as e:
            self._status.setText(
                (f"✗ Échec : {e}" if self._lang == "fr" else
                 f"✗ Failed : {e}")
            )


class FaultPickerDialog(QDialog):
    """Manual fault picker used in 'panne' mode. Lists every fault kind
    with a button, plus a toggle for the auto-scheduler. Fires the chosen
    fault immediately via trigger_fault()."""

    def __init__(self, state: GameState, parent: QWidget | None = None):
        super().__init__(parent)
        self._state = state
        lang = state.lang
        self.setWindowTitle("Pannes / Faults")
        self.setModal(True)
        self.setMinimumWidth(420)

        lay = QVBoxLayout(self)

        lbl = QLabel(
            "<b>Mode Pannes</b> — sélectionnez une panne à déclencher "
            "immédiatement, ou activez l'auto-scheduler."
            if lang == "fr" else
            "<b>Fault mode</b> — pick a fault to trigger now, or enable "
            "the auto-scheduler."
        )
        lbl.setWordWrap(True)
        lay.addWidget(lbl)

        # Auto-mode toggle
        self._auto_btn = QPushButton(self)
        self._refresh_auto_btn_label()
        self._auto_btn.clicked.connect(self._toggle_auto)
        self._auto_btn.setToolTip(
            "Activé : pannes aléatoires. Désactivé : manuel seulement."
            if lang == "fr" else
            "On: random faults. Off: manual only."
        )
        lay.addWidget(self._auto_btn)

        sep = QLabel("—" * 30)
        sep.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(sep)

        # Fault grid : 2 columns
        grid = QHBoxLayout()
        col_a, col_b = QVBoxLayout(), QVBoxLayout()
        for i, kind in enumerate(FAULT_KINDS):
            btn = QPushButton(fault_label(kind, lang), self)
            btn.setToolTip(
                f"Déclencher immédiatement : {kind}"
                if lang == "fr" else
                f"Trigger now : {kind}"
            )
            btn.clicked.connect(lambda _=False, k=kind: self._fire(k))
            (col_a if i % 2 == 0 else col_b).addWidget(btn)
        grid.addLayout(col_a)
        grid.addLayout(col_b)
        lay.addLayout(grid)

        close = QPushButton(
            "Fermer (F)" if lang == "fr" else "Close (F)", self)
        close.clicked.connect(self.accept)
        lay.addWidget(close)

    def _refresh_auto_btn_label(self) -> None:
        on = self._state.panne_auto
        lang = self._state.lang
        if lang == "fr":
            self._auto_btn.setText(
                f"Auto-scheduler : {'ACTIVÉ' if on else 'OFF (manuel)'}")
        else:
            self._auto_btn.setText(
                f"Auto-scheduler : {'ON' if on else 'OFF (manual)'}")

    def _toggle_auto(self) -> None:
        self._state.panne_auto = not self._state.panne_auto
        self._refresh_auto_btn_label()

    def _fire(self, kind: str) -> None:
        st = self._state
        if st.panne_active or st.train.overspeed_tripped:
            # Don't stack — inform + close
            add_event(
                st, "fault_busy",
                "A fault is already active — wait for it to clear.",
                "Une panne est déjà active — attendre sa résolution.",
                "warn",
            )
        else:
            trigger_fault(st, kind)
        self.accept()


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
        # Bilingual tooltips keyed by Qt.Key — shown on hover over any
        # clickable hit zone. Text is picked at display time from the
        # current LANG so the language toggle (L) flips tooltips live.
        K = Qt.Key
        self._key_tooltips: dict[int, tuple[str, str]] = {
            int(K.Key_Up): (
                "Raise speed command (+%) — regulator tracks smoothly",
                "Augmenter la consigne de vitesse (+%) — le régulateur suit",
            ),
            int(K.Key_Down): (
                "Lower speed command (−%) — regulator tracks smoothly",
                "Baisser la consigne de vitesse (−%) — le régulateur suit",
            ),
            int(K.Key_0): (
                "Cut speed command to 0 % (coast to stop under brake envelope)",
                "Mettre la consigne à 0 % (ralentissement sous le frein)",
            ),
            int(K.Key_Space): (
                "Service brake (hold) — 2.5 m/s² normal deceleration",
                "Frein de service (maintenu) — décélération 2.5 m/s²",
            ),
            int(K.Key_Shift): (
                "Emergency brake (hold) — 5 m/s² rail brakes",
                "Frein d'urgence (maintenu) — 5 m/s², freins de rail",
            ),
            int(K.Key_3): (
                "Electric stop — latched service stop, full abnormal-stop protocol",
                "Arrêt électrique — verrouillé, protocole d'arrêt anormal complet",
            ),
            int(K.Key_4): (
                "Emergency stop (red mushroom) — latched rail brakes",
                "Arrêt d'urgence (coup-de-poing) — freins de rail verrouillés",
            ),
            int(K.Key_G): (
                "Dead-man vigilance acknowledge — press before 20 s timeout",
                "Acquit veille automatique — appuyer avant 20 s",
            ),
            int(K.Key_W): (
                "Vigilance system disabled — click to re-enable",
                "Système de veille désactivé — cliquer pour réactiver",
            ),
            int(K.Key_H): (
                "Headlights on / off — gates tunnel visibility in cabin view",
                "Phares marche / arrêt — conditionnent la visibilité en vue cabine",
            ),
            int(K.Key_C): (
                "Cabin lights on / off — dims the ride atmosphere",
                "Éclairage cabine marche / arrêt — ambiance tamisée",
            ),
            int(K.Key_K): (
                "Horn (hold) — warning signal",
                "Klaxon (maintenu) — signal d'avertissement",
            ),
            int(K.Key_D): (
                "Doors open / close — only allowed at a full standstill",
                "Portes ouvrir / fermer — uniquement à l'arrêt total",
            ),
            int(K.Key_A): (
                "Autopilot toggle — programmed station-to-station run",
                "Pilote automatique — trajet programmé de gare à gare",
            ),
            int(K.Key_N): (
                "Mute / unmute on-board announcements and ambient sound",
                "Couper / rétablir les annonces et l'ambiance sonore",
            ),
            int(K.Key_V): (
                "READY — latch own cabin ready; START authorises when both ready",
                "PRÊT — verrouille la cabine prête ; DÉPART autorisé quand les deux prêtes",
            ),
            int(K.Key_Z): (
                "START — fire departure buzzer and release parking drum",
                "DÉPART — déclenche le buzzer et libère le frein de parking",
            ),
            int(K.Key_I): (
                "Reverse direction — only at a full standstill",
                "Inverser le sens — uniquement à l'arrêt total",
            ),
            int(K.Key_R): (
                "New trip — reset to title screen after arrival",
                "Nouveau trajet — retour à l'écran-titre après l'arrivée",
            ),
        }
        # Mouse tracking + tooltip delay so Qt delivers QEvent.ToolTip
        # over any hit zone without needing a click.
        self.setMouseTracking(True)
        # Title-screen click zones — each entry is (rect, direction,
        # train_number). Populated by _draw_title_overlay and consumed
        # by mousePressEvent when st.mode == MODE_TITLE.
        self._title_zones: list[tuple[QRectF, int, int]] = []
        # Cached paint resources — recreating QPen/QFont/QLinearGradient
        # every frame burned noticeable CPU in paintEvent. These static
        # ones are built once and reused.
        self._pen_version = QPen(COLOR_TEXT_DIM)
        self._font_version = QFont("Consolas", 9)
        self._cached_bg_grad: tuple[int, QLinearGradient] | None = None
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
        self.sounds = SoundSystem(_resource_path(""))
        # Auto-exploitation mode (background operations simulator).
        # Disabled by default — toggled with the X key.
        self.auto_ops = AutoOps(self)
        self._last_panne_kind: str = ""
        self._welcome_played = False
        self._arrival_played = False
        self._crossing_triggered = False
        # Mid-tunnel stop tracking — drives the "remise en route"
        # announcement when the driver restarts from an unplanned stop.
        self._was_stopped_mid_tunnel = False
        self._mid_tunnel_stop_timer = 0.0
        self._show_annmenu = False       # F2 announcement console
        self._cabin_view = False         # F4 cabin/tunnel first-person view
        self._tunnel_scroll = 0.0        # accumulated tunnel texture offset
        # Side-view zoom factor. 1.0 = default 850 m window, 0.35 ≈ ~300 m
        # tight, 4.2 ≈ full 3491 m trip. Driver adjusts with +/- or wheel.
        self._profile_zoom = 1.0
        # Dead-man vigilance : real funiculars require a release-then-press
        # cycle on the vigilance pedal — you can't wedge a stone on it. We
        # track the previous "any_action" state so only a rising edge
        # resets the dead-man timer. Holding a key does NOT qualify.
        self._prev_any_action: bool = False
        self.new_trip(first=True)

    # ----- lifecycle -------------------------------------------------------

    def reverse_trip(self, silent: bool = False) -> None:
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
        # Speed setpoint kept at 100 % — matches new_trip() and the real
        # Perce-Neige departure procedure : the consigne de vitesse is
        # always dialed at V_MAX by default. Traction is gated by the
        # ready / buzzer / start interlock, not by the setpoint value.
        tr.speed_cmd = 1.0
        tr.speed_cmd_eff = 0.0    # slewed from 0 so the train ramps up
        tr.throttle = 0.0
        tr.brake = 0.0
        # Parking brake and drum hold re-applied so the train cannot
        # drift under gravity while the reversal protocol runs.
        tr.maint_brake = True
        tr.ready = False
        tr.dead_man_timer = 0.0
        tr.dead_man_fault = False
        # Clear any latched overspeed trip from the previous leg —
        # otherwise the train can't depart again.
        tr.overspeed_tripped = False; tr.overspeed_level = 0
        st.ghost_ready = False
        st.ghost_ready_timer = 0.0
        st.ghost_ready_delay = 0.0
        st.trip_started = False
        st.trip_time = 0.0
        st.finished = False
        st.rebound_timer = 0.0
        st.departure_buzzer_remaining = 0.0
        # Doors : open ONLY when reversing at a terminus (passengers
        # can board). Reversing mid-tunnel keeps the doors shut — no
        # one is getting on in the tunnel, and opening them into a
        # 3 m bore is obviously wrong.
        at_terminus = (tr.s <= START_S + 5.0) or (tr.s >= STOP_S - 5.0)
        if at_terminus:
            tr.doors_open = True
            tr.doors_cmd = True
            tr.doors_timer = 0.0
            # Passenger turnover : at a terminus everyone exits and a
            # new load boards for the return leg. Perce-Neige skier
            # traffic is asymmetric — almost all trips go UP with skis
            # and everyone comes back DOWN on skis, so the descending
            # direction is nearly empty while the ascending one is
            # heavily loaded. Mirror exactly the new_trip() logic.
            half = PAX_MAX // 2
            if tr.direction > 0:
                tr.pax_car1 = random.randint(90, half)
                tr.pax_car2 = random.randint(90, half)
                st.ghost_pax = random.randint(0, 12)
            else:
                tr.pax_car1 = random.randint(0, 8)
                tr.pax_car2 = random.randint(0, 8)
                st.ghost_pax = random.randint(90, PAX_MAX - 20)
        else:
            tr.doors_open = False
            tr.doors_cmd = False
            tr.doors_timer = 0.0
        self._welcome_played = False
        self._arrival_played = False
        self._was_stopped_mid_tunnel = False
        # Trigger the real "return to station" announcement over the
        # on-board PA — but only when reversing mid-tunnel (abnormal
        # situation). Reversing at a terminus is the normal turnaround
        # and silently flips the direction.
        self.sounds.stop_announcements()
        if not at_terminus and not silent:
            self.sounds.play("return_station", lang=st.ann_lang, cooldown=5.0)
        dest_en = "Val Claret (2111 m)" if tr.direction < 0 else "Grande Motte (3032 m)"
        if not silent:
            add_event(st, "reverse",
                      f"Reversing — return toward {dest_en}",
                      f"Inversion du sens — retour vers {dest_en}",
                      "warn")
        else:
            add_event(st, "reverse",
                      f"Preparing return trip toward {dest_en}",
                      f"Préparation du retour vers {dest_en}",
                      "info")

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
        tr.speed_cmd_eff = 0.0    # slewed from 0 so the train ramps up
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
        # Reset persistent fault effects so a new trip starts clean.
        tr.tension_fault_dan = 0.0
        tr.thermal_derate = 1.0
        tr.motor_count = 3
        tr.speed_fault_cap = 999.0
        tr.slack_fault_dan = 0.0
        tr.aux_power_fault = False
        tr.overspeed_tripped = False; tr.overspeed_level = 0
        tr.door_fault = False
        tr.parking_stuck = False
        tr.fault_timer = 0.0
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
        # Real wall-clock dt — hardcoding 0.016 made the sim run slower
        # than realtime whenever the QTimer fell behind (Windows default
        # timer granularity is ~15.6 ms, and rendering + audio routinely
        # push per-frame cost to 20-30 ms). The counter and every physics
        # integration now advance at true elapsed time, so 12 m/s on the
        # speedometer actually moves the train 12 m per real second.
        # Clamp to 0.1 s (10 Hz) so a single long pause or GC hitch
        # can't teleport the train through the creep zone.
        now_t = time.monotonic()
        last = getattr(self, "_last_tick_t", None)
        if last is None:
            dt = 0.016
        else:
            dt = min(0.1, max(0.001, now_t - last))
        self._last_tick_t = now_t
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
        # Auto-exploitation state machine (no-op when disabled)
        self.auto_ops.tick(dt)
        # Passing-loop crossing whoosh : the real cabin recording spans
        # 20 s (4:40 → 5:00 of the HD ascent = 202 m at 10.1 m/s, i.e.
        # the full switch-to-switch transit). Fire the clip the moment
        # the train's head enters the loop so the ambient stays aligned
        # with the rails for the whole crossing. Reset after exiting so
        # the next round-trip re-triggers it.
        in_loop = PASSING_START <= st.train.s <= PASSING_END
        if not self._crossing_triggered:
            if in_loop and abs(st.train.v) > 1.0:
                self.sounds.play_crossing()
                self._crossing_triggered = True
        elif not in_loop:
            self._crossing_triggered = False

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
            # Pending mid-tunnel incident : engaged when the driver
            # pulled a latched stop (E-stop, emergency, vigilance loss)
            # while rolling. Wait for the cabin to fully come to rest,
            # then announce the incident and suspend the trip so the
            # driver has to go through READY + buzzer to restart.
            if st.pending_incident and abs(st.train.v) < 0.1:
                st.pending_incident = False
                kind = st.pending_incident_kind
                st.pending_incident_kind = ""
                if kind == "fire":
                    self.sounds.play("dim_light",
                                     lang=st.ann_lang, cooldown=45.0)
                    self.sounds.play("evac",
                                     lang=st.ann_lang, cooldown=60.0)
                else:
                    self.sounds.play("tech_incident",
                                     lang=st.ann_lang, cooldown=30.0)
                st.trip_started = False
                # Engage the parking drum so the cabin can't drift under
                # gravity while the driver releases the latched stop,
                # dials the speed setpoint back up, etc. The drum only
                # releases when DEPART (Z) finishes its buzzer and flips
                # trip_started back to True — so raising speed_cmd after
                # releasing the stop no longer auto-starts the train.
                st.train.maint_brake = True
                self._was_stopped_mid_tunnel = True
                add_event(st, "incident",
                          "Train halted — incident announcement",
                          "Arrêt de la rame — annonce incident",
                          "warn")
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
            # The 35 m platform + 20 m creep-in zone is a very slow 55 m
            # final approach (~55 s at creep speed). The arrival "welcome
            # to the ski zone" announcement must wait until the train is
            # almost fully stopped — not when it's still 220 m away at
            # 6 m/s — otherwise the message is over long before the
            # passengers can actually exit. Trigger when |v| < 1 m/s.
            if (st.trip_started and not self._welcome_played
                    and tr_welcome.direction > 0
                    and dist_remain_welcome < 220.0
                    and abs(tr_welcome.v) < 1.0):
                self.sounds.play("welcome", lang=st.ann_lang, cooldown=600.0)
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
                self.sounds.play("brake_noise", lang=st.ann_lang, cooldown=20.0)
            # Fault announcements — pick the matching message bilingually.
            # Suppressed entirely once the train has arrived so a resolved
            # emergency never leaks evac / restart messages onto the
            # station platform.
            if not st.finished:
                if st.panne_active and st.panne_kind != self._last_panne_kind:
                    self._last_panne_kind = st.panne_kind
                    # Category of fault drives which (if any) announcement
                    # plays. Silent-advisory faults (wet-rail cap, minor
                    # tension/slack readings) don't interrupt the cabin
                    # with a PA — they stay on the event log / gauge only.
                    # Faults that actually stop or degrade service play a
                    # matching announcement once at onset.
                    stopping_kind = st.panne_kind in (
                        "door", "thermal", "motor_degraded",
                        "aux_power", "parking_stuck", "fire",
                    )
                    at_term_p = ((st.train.s <= START_S + 5.0)
                                 or (st.train.s >= STOP_S - 5.0))
                    if stopping_kind:
                        # Safety chain : a service-stopping fault disarms
                        # READY exactly like a manual emergency / electric
                        # stop would. The driver has to re-arm once the
                        # fault clears and the train has halted.
                        tr_f = st.train
                        tr_f.ready = False
                        st.ghost_ready = False
                        st.ghost_ready_timer = 0.0
                        st.ghost_ready_delay = 0.0
                        st.departure_buzzer_remaining = 0.0
                        # Mid-tunnel stopping fault : defer the PA until
                        # the cabin actually halts (pending_incident). At
                        # the terminus the train isn't rolling anyway, so
                        # the message can play straight away.
                        if not at_term_p and st.trip_started:
                            st.pending_incident = True
                            st.pending_incident_kind = st.panne_kind
                        elif st.panne_kind == "fire":
                            self.sounds.play("dim_light",
                                             lang=st.ann_lang, cooldown=45.0)
                            self.sounds.play("evac",
                                             lang=st.ann_lang, cooldown=60.0)
                        else:
                            self.sounds.play("tech_incident",
                                             lang=st.ann_lang, cooldown=45.0)
                    # "tension", "wet_rail", "slack" : no PA, just dashboard.
                elif not st.panne_active and self._last_panne_kind:
                    # A fault has just been cleared. Only play the
                    # "Remise en route" announcement if the train actually
                    # stopped in the tunnel because of the fault (real
                    # Perce-Neige rule : passengers are told service is
                    # resuming only when they felt it halt). A silent-
                    # advisory fault that was managed without a stop gets
                    # a brief log line and no PA.
                    resolved_kind = self._last_panne_kind
                    self._last_panne_kind = ""
                    was_stopping_kind = resolved_kind in (
                        "door", "thermal", "motor_degraded",
                        "aux_power", "parking_stuck", "fire",
                    )
                    if was_stopping_kind and self._was_stopped_mid_tunnel:
                        self.sounds.play("restart",
                                         lang=st.ann_lang, cooldown=30.0)
                        self._was_stopped_mid_tunnel = False
            # Arrival : no automatic announcement. The driver stays in the
            # cabin, opens the doors manually (D), and can trigger any
            # announcement on demand via the F2 console. We simply stop
            # whatever was playing so residual fault messages (evac, tech
            # incident, restart…) don't leak onto the station platform.
            if st.finished and not self._arrival_played:
                self._arrival_played = True
                self.sounds.stop_announcements()
                self._last_panne_kind = ""
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
                # Whenever the doors physically open, the driver's "ready
                # to depart" lamp must drop : the departure interlock is
                # cleared so the next leg requires a fresh ready-press
                # after closing the doors again. Matches real Von Roll
                # cab logic (ready lamp is wired via door-closed contact).
                if tr.doors_open:
                    tr.ready = False
                    st.ghost_ready = False
        active = self._key_state | self._mouse_hold
        up = Qt.Key.Key_Up in active
        down = Qt.Key.Key_Down in active
        brake_key = (Qt.Key.Key_Space in active) or (Qt.Key.Key_B in active)
        # Up/Down adjust the driver's speed command (percentage of V_MAX).
        # Regulator takes care of realistic accel/decel to track it.
        # Available at any time — the departure interlock is enforced by
        # the ready / buzzer / start sequence on the traction side, not
        # by locking the setpoint itself.
        any_action = False
        if up:
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
        # Rising-edge detection : only a press-AFTER-release counts as
        # acknowledgement (you cannot wedge the pedal down permanently).
        action_edge = any_action and not self._prev_any_action
        self._prev_any_action = any_action
        if st.vigilance_enabled:
            DEAD_MAN_LIMIT = 20.0
            if abs(tr.v) > 0.2 and not tr.dead_man_fault:
                if action_edge:
                    tr.dead_man_timer = 0.0
                else:
                    tr.dead_man_timer += dt
                if tr.dead_man_timer > DEAD_MAN_LIMIT:
                    tr.dead_man_fault = True
                    tr.ready = False
                    st.ghost_ready = False
                    st.ghost_ready_timer = 0.0
                    st.ghost_ready_delay = 0.0
                    st.departure_buzzer_remaining = 0.0
                    add_event(st, "dead_man",
                              "Dead-man vigilance failed — automatic stop",
                              "Veille automatique perdue — arrêt automatique",
                              "alarm")
                    at_term_dm = ((tr.s <= START_S + 5.0)
                                  or (tr.s >= STOP_S - 5.0))
                    if not at_term_dm and st.trip_started:
                        st.pending_incident = True
            else:
                tr.dead_man_timer = 0.0
        else:
            tr.dead_man_timer = 0.0
            tr.dead_man_fault = False

    # ----- keyboard --------------------------------------------------------

    def _open_fault_picker(self) -> None:
        dlg = FaultPickerDialog(self.state, self)
        dlg.exec()

    def _open_docs_download(self) -> None:
        dlg = DocsDownloadDialog(self.state.lang, self)
        dlg.exec()

    def keyPressEvent(self, ev: QKeyEvent) -> None:  # noqa: N802
        st = self.state
        k = ev.key()
        self._key_state.add(k)
        # Auto-exploitation input lockout : when the AI driver is
        # running the line, manual driving keys (speed, brake, doors,
        # ready, reverse, etc.) are ignored so the human can't fight
        # the state machine mid-cycle. Only a small whitelist of
        # meta keys is still accepted : X (toggle auto), F-keys (menus
        # & log viewer), language / pause / escape / help / ann menu.
        if (getattr(self, "auto_ops", None) is not None
                and self.auto_ops.enabled
                and not self._show_annmenu):
            _allowed = {
                Qt.Key.Key_X, Qt.Key.Key_Escape, Qt.Key.Key_P,
                Qt.Key.Key_L, Qt.Key.Key_N, Qt.Key.Key_Backspace,
                Qt.Key.Key_F1, Qt.Key.Key_F2, Qt.Key.Key_F3,
                Qt.Key.Key_F4, Qt.Key.Key_F5,
                Qt.Key.Key_Plus, Qt.Key.Key_Equal, Qt.Key.Key_Minus,
            }
            if k not in _allowed:
                ev.accept()
                return
        # Announcement console hotkeys (only when menu is visible).
        # Ignore auto-repeat so holding the key doesn't cascade the same
        # announcement dozens of times into the queue.
        if self._show_annmenu and not ev.isAutoRepeat():
            # Language selector hotkeys : F/E/I/D/S pick the announcement
            # language played by the next selection. Independent of the
            # UI language (L) so the driver can queue any translation.
            lang_keys = {
                Qt.Key.Key_F: "fr",
                Qt.Key.Key_E: "en",
                Qt.Key.Key_I: "it",
                Qt.Key.Key_G: "de",  # G for German (D is the doors key)
                Qt.Key.Key_S: "es",
            }
            if k in lang_keys:
                st.ann_lang = lang_keys[k]
                add_event(st, "ann_lang",
                          f"Announcement language → {st.ann_lang.upper()}",
                          f"Langue des annonces → {st.ann_lang.upper()}",
                          "info")
                return
            for entry_k, group, _lbl, en, fr in ANNOUNCEMENT_MENU:
                if k == entry_k:
                    # Interrupt any announcement currently playing — a
                    # new command always takes over, no cascading queue.
                    self.sounds.stop_announcements()
                    self.sounds._cooldowns.pop(group, None)
                    # Check the file exists for the requested language
                    # BEFORE playing — if not, warn the driver instead of
                    # falling back to another language silently.
                    available = self.sounds._pick(group, st.ann_lang, strict=True)
                    if available is None:
                        add_event(st, "ann",
                                  f"Announcement [{st.ann_lang.upper()}] not available : {en}",
                                  f"Annonce [{st.ann_lang.upper()}] indisponible : {fr}",
                                  "warn")
                    else:
                        self.sounds.play(group, lang=st.ann_lang,
                                         cooldown=5.0, strict=True)
                        add_event(st, "ann",
                                  f"Announcement [{st.ann_lang.upper()}] : {en}",
                                  f"Annonce [{st.ann_lang.upper()}] : {fr}",
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
            # Already on the title screen : Esc quits the app.
            if st.mode == MODE_TITLE:
                self.window().close()
                return
            # Anywhere else (RUN, PAUSED, OVER) : bail back to the
            # main menu seen at launch. Stops all sounds, cancels the
            # current trip, returns to the title so the user can pick
            # a new direction / train / mode.
            self.sounds.stop_announcements()
            self.sounds.reset()
            if getattr(self, "auto_ops", None) is not None \
                    and self.auto_ops.enabled:
                self.auto_ops.toggle()
            st.mode = MODE_TITLE
            st.finished = False
            self._show_help = False
            return
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
        elif k == Qt.Key.Key_Home:
            # Return to the main title screen at any time — the driver
            # can start a fresh simulation (different direction / train)
            # or simply quit with Esc.
            self.sounds.stop_announcements()
            self.sounds.reset()
            st.mode = MODE_TITLE
            st.finished = False
            return
        elif k == Qt.Key.Key_I:
            # Reverse direction — allowed whenever the train is at rest
            # (|v| < 0.1 m/s), whether that's at a terminus after arrival
            # OR mid-tunnel after an unscheduled stop. Real Perce-Neige
            # plays the "retour en gare" announcement in that case.
            if abs(st.train.v) < 0.1:
                self.reverse_trip()
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
        elif k == Qt.Key.Key_F5:
            self._open_trip_log_viewer()
        elif k == Qt.Key.Key_F6:
            self._open_docs_download()
        elif k in (Qt.Key.Key_Plus, Qt.Key.Key_Equal):
            # Side-view zoom in (narrower window, more detail)
            self._profile_zoom = max(0.35, self._profile_zoom / 1.25)
        elif k == Qt.Key.Key_Minus:
            # Side-view zoom out (up to whole trip in one view)
            self._profile_zoom = min(4.2, self._profile_zoom * 1.25)
        elif k == Qt.Key.Key_0 and not self._show_annmenu:
            # Reset zoom
            self._profile_zoom = 1.0
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
        elif k == Qt.Key.Key_F:
            # Fault picker dialog — only useful in "panne" mode
            if st.run_mode == "panne":
                self._open_fault_picker()
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
                    self.sounds.play_door_motion()
                    add_event(st, "doors",
                              "Opening doors", "Ouverture des portes",
                              "info")
                else:
                    tr.doors_timer = DOOR_CLOSE_TIME
                    # Real door sequence in series : announcement
                    # first, then the warning buzzer when it finishes,
                    # then the hydraulic door-motion whoosh.
                    self.sounds.play_doors_close_sequence(
                        lang=st.ann_lang)
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
                tr.ready = False
                st.ghost_ready = False
                st.ghost_ready_timer = 0.0
                st.ghost_ready_delay = 0.0
                st.departure_buzzer_remaining = 0.0
                at_term = ((tr.s <= START_S + 5.0)
                           or (tr.s >= STOP_S - 5.0))
                if not at_term and st.trip_started:
                    st.pending_incident = True
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
                self.sounds.play("brake_noise", lang=st.ann_lang, cooldown=30.0)
                tr.ready = False
                st.ghost_ready = False
                st.ghost_ready_timer = 0.0
                st.ghost_ready_delay = 0.0
                st.departure_buzzer_remaining = 0.0
                at_term = ((tr.s <= START_S + 5.0)
                           or (tr.s >= STOP_S - 5.0))
                if not at_term and st.trip_started:
                    st.pending_incident = True
            elif abs(tr.v) < 0.1:
                tr.emergency = False
                tr.maint_brake = False
                # Cycling the emergency also clears the overspeed latch
                # and resets a stuck parking brake release.
                if tr.overspeed_tripped:
                    tr.overspeed_tripped = False; tr.overspeed_level = 0
                    add_event(st, "overspeed_reset",
                              "Overspeed trip acknowledged and reset.",
                              "Survitesse acquittée et réarmée.", "info")
                if tr.parking_stuck:
                    tr.parking_stuck = False
                    clear_fault(st)
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
                self.sounds.play("dim_light", lang=st.ann_lang, cooldown=60.0)
        elif k == Qt.Key.Key_K:
            st.train.horn = True
            self.sounds.start_horn()
        elif k == Qt.Key.Key_X:
            # Toggle background auto-exploitation : full day of service
            # ran by an AI driver — boarding, buzzer, trip, arrival,
            # reversal, next cycle. Logs every trip to exploitation.db.
            # Shift+X flips the "run outside published hours" override.
            if ev.modifiers() & Qt.KeyboardModifier.ShiftModifier:
                self.auto_ops.force_any_hours = \
                    not self.auto_ops.force_any_hours
                add_event(st, "ops",
                          ("24/7 mode ON"
                           if self.auto_ops.force_any_hours
                           else "Published hours restored"),
                          ("Mode 24/7 activé"
                           if self.auto_ops.force_any_hours
                           else "Horaires officiels rétablis"),
                          "info")
            else:
                self.auto_ops.toggle()
        elif k == Qt.Key.Key_Backspace:
            # Abort the running announcement + clear the queue.
            self.sounds.stop_announcements()
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
            if st.trip_started:
                return
            # After arrival : first V press silently flips the travel
            # direction and re-arms the departure sequence. The F4 view,
            # ghost position and HUD heading all update automatically.
            # The driver then goes through the normal D → V → Z cycle.
            if st.finished:
                self.reverse_trip(silent=True)
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
                elif getattr(self.sounds, "_close_seq_active", False):
                    reason_en = "doors-close chime still sounding"
                    reason_fr = "séquence sonore de fermeture en cours"
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
                    self.sounds.play("restart", lang=st.ann_lang, cooldown=30.0)
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
                self.sounds.play_doors_close_sequence(
                    lang=st.ann_lang)
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

    def event(self, ev):  # type: ignore[override]
        # Bilingual hover tooltips over every clickable hit zone. Qt
        # delivers QEvent.Type.ToolTip after ~700 ms of mouse hover;
        # we hit-test in reverse (top-most drawn wins) just like clicks,
        # then look up the (en, fr) tuple in _key_tooltips and pick the
        # current-language string.
        if ev.type() == QEvent.Type.ToolTip:
            pos = ev.pos() if hasattr(ev, "pos") else None
            if pos is not None:
                posf = QPointF(pos)
                for rect, qk, _hold in reversed(self._hit_zones):
                    if rect.contains(posf):
                        tip = self._key_tooltips.get(qk)
                        if tip is not None:
                            QToolTip.showText(
                                ev.globalPos(),
                                T(tip[0], tip[1]), self,
                            )
                            return True
                QToolTip.hideText()
                ev.ignore()
                return True
        return super().event(ev)

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
                # Mouse clicks on cockpit buttons are filtered through
                # the same auto-ops lockout as the keyboard path.
                if (self.auto_ops.enabled
                        and qk not in (int(Qt.Key.Key_X),
                                       int(Qt.Key.Key_P),
                                       int(Qt.Key.Key_N),
                                       int(Qt.Key.Key_L),
                                       int(Qt.Key.Key_Backspace),
                                       int(Qt.Key.Key_F1),
                                       int(Qt.Key.Key_F2),
                                       int(Qt.Key.Key_F3),
                                       int(Qt.Key.Key_F4),
                                       int(Qt.Key.Key_F5))):
                    ev.accept()
                    return
                if hold:
                    self._mouse_hold.add(qk)
                self._sim_press(qk)
                ev.accept()
                return

    def wheelEvent(self, ev: QWheelEvent) -> None:  # noqa: N802
        # Mouse wheel zooms the side-view (F4 off). Ignored in cabin view.
        if self._cabin_view:
            return
        delta = ev.angleDelta().y()
        if delta == 0:
            return
        factor = 0.85 if delta > 0 else 1.18
        self._profile_zoom = max(0.35, min(4.2, self._profile_zoom * factor))
        ev.accept()

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

        # Reserve the bottom-right corner for the auto-exploitation
        # panel when the ops simulator is running — otherwise the event
        # log can use the full width.
        ops_panel_w = 300 if self.auto_ops.enabled else 0
        log_w = w - 40 - (ops_panel_w + 12 if ops_panel_w else 0)
        log_rect = QRectF(20, h - 230, log_w, 210)
        self._draw_eventlog(p, log_rect)
        if self.auto_ops.enabled:
            ops_rect = QRectF(w - 20 - ops_panel_w, h - 230,
                              ops_panel_w, 210)
            self._draw_auto_ops_panel(p, ops_rect)

        if self.state.mode == MODE_TITLE:
            self._draw_title_overlay(p, w, h)
        elif self.state.mode == MODE_PAUSED:
            self._draw_paused_overlay(p, w, h)
        # No "trip completed" overlay — the driver simply stays in the
        # cabin, doors open, ready to prepare the return trip on demand.

        if self._show_help:
            self._draw_help_overlay(p, w, h)

        if self._show_info:
            self._draw_info_overlay(p, w, h)

        if self._show_annmenu:
            self._draw_ann_menu(p, w, h)

        # Version + fps
        p.setPen(self._pen_version)
        p.setFont(self._font_version)
        p.drawText(
            QRectF(w - 140, h - 18, 130, 16),
            int(Qt.AlignmentFlag.AlignRight),
            f"v{VERSION}  {self._fps:.0f} fps",
        )
        # Persistent wall-clock overlay — always drawn last so it's
        # visible above every screen (title, run, paused, menus).
        self._draw_clock_badge(p, w, h)
        p.end()

    def _draw_clock_badge(self, p: QPainter, w: int, h: int) -> None:
        """Small top-centre pill showing the real wall clock. Drawn in
        every mode so the driver always knows the time without hunting
        for the auto-ops panel."""
        now = datetime.now()
        if LANG == "fr":
            days = ["lundi", "mardi", "mercredi", "jeudi",
                    "vendredi", "samedi", "dimanche"]
            months = ["janvier", "février", "mars", "avril", "mai",
                      "juin", "juillet", "août", "septembre",
                      "octobre", "novembre", "décembre"]
            date_txt = (f"{days[now.weekday()]} {now.day} "
                        f"{months[now.month - 1]} {now.year}")
        else:
            days = ["Monday", "Tuesday", "Wednesday", "Thursday",
                    "Friday", "Saturday", "Sunday"]
            months = ["January", "February", "March", "April", "May",
                      "June", "July", "August", "September",
                      "October", "November", "December"]
            date_txt = (f"{days[now.weekday()]} {now.day} "
                        f"{months[now.month - 1]} {now.year}")
        time_txt = now.strftime("%H:%M:%S")
        pad = 10
        pill_w = 196
        pill_h = 32
        pill = QRectF(w / 2 - pill_w / 2, 6, pill_w, pill_h)
        grad = QLinearGradient(pill.x(), pill.y(),
                               pill.x(), pill.y() + pill.height())
        grad.setColorAt(0.0, QColor(14, 20, 32, 220))
        grad.setColorAt(1.0, QColor(4, 8, 16, 220))
        p.setBrush(QBrush(grad))
        p.setPen(QPen(QColor(120, 180, 240, 180), 1.2))
        p.drawRoundedRect(pill, 10, 10)
        p.setPen(QPen(QColor(190, 220, 255)))
        p.setFont(QFont("Consolas", 13, QFont.Weight.Bold))
        p.drawText(QRectF(pill.x(), pill.y() + 2,
                          pill.width(), pill.height() / 2 + 2),
                   int(Qt.AlignmentFlag.AlignCenter), time_txt)
        p.setPen(QPen(QColor(150, 180, 220)))
        p.setFont(QFont("Segoe UI", 8))
        p.drawText(QRectF(pill.x(), pill.y() + pill.height() / 2,
                          pill.width(), pill.height() / 2 - 2),
                   int(Qt.AlignmentFlag.AlignCenter), date_txt)

    # ----- background ------------------------------------------------------

    def _draw_background(self, p: QPainter, w: int, h: int) -> None:
        # Gradient only depends on height — cache keyed on h to avoid
        # rebuilding QLinearGradient every frame.
        cache = self._cached_bg_grad
        if cache is None or cache[0] != h:
            grad = QLinearGradient(0, 0, 0, h)
            grad.setColorAt(0, COLOR_BG_TOP)
            grad.setColorAt(1, COLOR_BG_BOT)
            self._cached_bg_grad = (h, grad)
        else:
            grad = cache[1]
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
        # _profile_zoom: 1.0 = 850 m window (default), 0.35 ≈ tight close-up,
        # ≥ 4.2 shows the whole 3491 m trip in one frame.
        cam_width_m = 850.0 * self._profile_zoom
        cabin_x_m, cabin_y_m = geom_at(tr.s)
        cam_x_m = max(0.0, min(max(H_MAX - cam_width_m, 0),
                               cabin_x_m - cam_width_m * 0.48))

        # Y span must scale LINEARLY with cam_width_m so the world→screen
        # aspect ratio stays identical across zooms — otherwise the slope
        # would appear steeper or gentler as the driver zooms in/out, which
        # is both wrong and disorienting. Reference ratio 850 : 350 m matches
        # the view_w : view_h aspect and gives a realistic visual slope.
        y_span = cam_width_m * (350.0 / 850.0)
        y_mid = max(ALT_LOW + y_span / 2,
                    min(ALT_HIGH - y_span / 2 + 40, cabin_y_m + 40))
        y_top_m = y_mid + y_span / 2
        y_bot_m = y_mid - y_span / 2

        def world_to_screen(xm: float, ym: float) -> QPointF:
            px = view_x + (xm - cam_x_m) / cam_width_m * view_w
            py = view_y + (y_top_m - ym) / (y_top_m - y_bot_m) * view_h
            return QPointF(px, py)

        # === Distant hazy ridges (atmospheric perspective) ===
        # Two silhouette layers behind the main massif give the scene
        # depth. Each ridge is a shallow sine-noise profile parallax-offset
        # so far ridges scroll slowly relative to the train's position.
        for layer_idx, (color, top_off, parallax, freq) in enumerate((
            (COLOR_MOUNT_FAR, 560.0, 0.35, 0.0025),
            (COLOR_MOUNT_MID, 380.0, 0.65, 0.0041),
        )):
            ridge = QPolygonF()
            ridge.append(QPointF(view_x, view_y + view_h))
            for i in range(0, 61):
                fx = view_x + (view_w * i / 60.0)
                # parallax: far ridges move slower as cam pans
                world_x = cam_x_m * parallax + (i / 60.0) * cam_width_m
                y_noise = (
                    top_off
                    + 90.0 * math.sin(world_x * freq + layer_idx * 1.3)
                    + 45.0 * math.sin(world_x * freq * 2.1 + layer_idx * 2.7)
                    + 22.0 * math.sin(world_x * freq * 4.3)
                )
                # Base of ridge sits near tunnel altitude
                base_ym = ALT_LOW + 400 + y_noise
                py = view_y + (y_top_m - base_ym) / (y_top_m - y_bot_m) * view_h
                ridge.append(QPointF(fx, py))
            ridge.append(QPointF(view_x + view_w, view_y + view_h))
            p.setBrush(QBrush(color))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawPolygon(ridge)

        # === Drifting clouds high in the sky ===
        # Large soft ellipses at ~3100–3300 m, also parallax-offset so
        # they appear to float independently of the foreground.
        for cx_off, cy_off, rad_x, rad_y, cshade in (
            (  0.0, 3280.0, 160.0, 22.0, False),
            (620.0, 3210.0, 210.0, 30.0, True),
            (1320.0, 3305.0, 140.0, 18.0, False),
            (2100.0, 3240.0, 240.0, 26.0, True),
            (2900.0, 3280.0, 180.0, 22.0, False),
        ):
            cx = cx_off - cam_x_m * 0.45
            pt = world_to_screen(cx, cy_off)
            if -260 < pt.x() - view_x < view_w + 260:
                p.setBrush(QBrush(COLOR_CLOUD_SHADE if cshade else COLOR_CLOUD))
                p.setPen(Qt.PenStyle.NoPen)
                # horizontal width in pixels depends on zoom
                rx_px = rad_x * (view_w / cam_width_m) * 0.8
                ry_px = rad_y * (view_h / (y_top_m - y_bot_m)) * 0.9
                p.drawEllipse(pt, rx_px, ry_px)

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
        grad_snow = QLinearGradient(0, view_y, 0, view_y + view_h * 0.6)
        grad_snow.setColorAt(0.0, COLOR_GLACIER)
        grad_snow.setColorAt(1.0, COLOR_GLACIER_SHADE)
        p.setBrush(QBrush(grad_snow))
        p.setPen(Qt.PenStyle.NoPen)
        p.drawPolygon(snow_poly)

        # === Pine tree line at alt 2200–2500 m ===
        # Draw small conifer silhouettes scattered along the slope.
        # Deterministic placement (hashed by segment index) so trees don't
        # flicker frame-to-frame.
        tree_step_m = 60.0
        s_start = max(0.0, cam_x_m - 50.0)
        s_end = min(H_MAX, cam_x_m + cam_width_m + 50.0)
        # Walk in slope-s space so trees follow tunnel curvature.
        s_m = 0.0
        tree_idx = 0
        while s_m < LENGTH:
            xm, ym = geom_at(s_m)
            if s_start <= xm <= s_end and ym < 2550.0:
                # Pseudo-random per-segment offset + size
                h_off = ((tree_idx * 131) % 17) * 2.0
                v_off = ((tree_idx * 53) % 11) * 1.4
                size_px = 6.0 + ((tree_idx * 37) % 7)
                base_pt = world_to_screen(xm + h_off, ym + 30 + v_off)
                # Draw triangle (conifer)
                tri = QPolygonF()
                tri.append(QPointF(base_pt.x(), base_pt.y() - size_px))
                tri.append(QPointF(base_pt.x() - size_px * 0.55, base_pt.y()))
                tri.append(QPointF(base_pt.x() + size_px * 0.55, base_pt.y()))
                # Alternate shade for variation
                p.setBrush(QBrush(COLOR_PINE_HILIGHT if tree_idx & 1 else COLOR_PINE))
                p.setPen(Qt.PenStyle.NoPen)
                p.drawPolygon(tri)
            s_m += tree_step_m
            tree_idx += 1

        # === Rock outcrops on bare mountain (above tree line, below snow) ===
        # Small darker patches to break up the flat rock color.
        p.setBrush(QBrush(QColor(46, 40, 38)))
        p.setPen(Qt.PenStyle.NoPen)
        for seed in range(8):
            xw = cam_x_m + (seed * 137.0 % cam_width_m)
            xm_seed, ym_seed = xw, 0.0
            # Get rock-surface altitude at that x (approx: linearly between track ends)
            frac = xw / max(1.0, H_MAX)
            ym_seed = ALT_LOW + (ALT_HIGH - ALT_LOW) * frac + 90
            if ym_seed < 2650.0:
                pt = world_to_screen(xw, ym_seed)
                p.drawEllipse(pt, 14.0, 4.0)

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
        # Zoom indicator (+/− or wheel to zoom, 0 to reset)
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 9))
        p.drawText(
            QRectF(view_x + view_w - 180, view_y + 22, 170, 14),
            int(Qt.AlignmentFlag.AlignRight),
            T(f"zoom {1.0 / self._profile_zoom:4.2f}×  (+/− 0)",
              f"zoom {1.0 / self._profile_zoom:4.2f}×  (+/− 0)"),
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

        # Plan view (bird's eye) inset — middle-left of world view
        # (vertically centred on the side-view window so it doesn't
        # overlap the bottom motor-room inset and leaves breathing
        # room for distance markers along the base).
        plan_w = 260.0
        plan_h = 148.0
        plan_rect = QRectF(
            view_x + 8,
            view_y + (view_h - plan_h) / 2.0,
            plan_w, plan_h,
        )
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
            # Extended from 100 m → 260 m so the driver can actually SEE
            # the tunnel curving up/down when approaching a slope break
            # (e.g. the 30 %→12 % transition on the last 400 m before
            # Grande Motte). Fog / exponential dim still swallows anything
            # past ~120 m so realism is preserved.
            max_depth = 180.0
            head_reach = 28.0  # exponential decay length (m)
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
        # Driver's eye is inside the front cabin, not at tr.s (which
        # tracks the train centre). Shift by (TRAIN_HALF − EYE_BACK) in
        # the travel direction : the nose of the train is at TRAIN_HALF,
        # the driver's seat sits EYE_BACK ≈ 3 m back from the nose so
        # when stopped flush at a terminus there is still a few metres
        # of platform visible forward (otherwise bumper + eye are the
        # exact same point and the platform is entirely behind us).
        EYE_BACK = 3.0
        view_s = tr.s + (TRAIN_HALF - EYE_BACK) * tr.direction
        # Distance from the driver's eye to the nearest tunnel end in the
        # travel direction. Past this distance there is a concrete bumper
        # wall — no more rings to draw.
        if tr.direction > 0:
            d_to_end = max(0.0, LENGTH - view_s)
        else:
            d_to_end = max(0.0, view_s)
        ring_limit = min(max_depth, d_to_end)
        ring_depths: list[float] = []
        d_cur = d0
        while d_cur <= ring_limit:
            ring_depths.append(d_cur)
            d_cur += ring_spacing

        # Vertical pitch of the tunnel ahead relative to the cabin's
        # current attitude. The cabin floor is always aligned with the
        # LOCAL slope (driver sees a level platform), so a ring AHEAD
        # appears vertically offset by (angle_ahead - angle_here) × d,
        # projected to screen via the focal length. Positive delta →
        # ring centre moves UP on screen (track steepens uphill); we
        # flip sign on descent so "steeper ahead" still reads correctly.
        local_slope_rad = slope_angle_at(tr.s)

        # --- Abt passing-loop separation factor -------------------------
        # Real Perce-Neige has a 203 m Abt passing loop between
        # PASSING_START and PASSING_END — a passive double-track section
        # where the single bore widens, two parallel tracks run 3 m
        # apart, the trains cross, and the rails rejoin via a symmetric
        # switch at the far end. No moving parts : Abt switch uses
        # asymmetric wheel flanges so each wagon biases to its own side.
        # Render : linear ramp over the real switch transition length
        # (~15 m of actual rail divergence) at both ends.
        TRACK_SEP_M = 3.0         # centre-to-centre track separation (m)
        # Abt switch divergence zone. Real turnouts use a lead curve +
        # clothoid transition so lateral acceleration ramps up and down
        # smoothly. We emulate that with a 5th-order smootherstep
        # (6t⁵-15t⁴+10t³) which is C² continuous — zero first AND second
        # derivative at both ends — so the train has no jerk at the
        # switch entry / exit.
        SWITCH_RAMP_M = 22.0
        # Own side sign : physical side the main train takes through the
        # Abt loop. Defined early (also used later for rail drawing) so
        # _plan_local can shift the driver onto his own track — otherwise
        # the cabin sits on the bore centerline and looks like it's
        # straddling both tracks during the passing manoeuvre.
        own_side_sign = -1 if ((tr.number == 1) == (tr.direction > 0)) else +1

        def _smootherstep(t: float) -> float:
            if t <= 0.0:
                return 0.0
            if t >= 1.0:
                return 1.0
            return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

        def _loop_sep(ts: float) -> float:
            # Full divergence only in the flat core of the loop ; the
            # switch transition is centered on each loop end, half inside
            # and half outside, so the rail curve enters the loop already
            # parallel to the centerline and stays parallel throughout.
            half = SWITCH_RAMP_M * 0.5
            if ts <= PASSING_START - half:
                return 0.0
            if ts < PASSING_START + half:
                return _smootherstep(
                    (ts - (PASSING_START - half)) / SWITCH_RAMP_M)
            if ts <= PASSING_END - half:
                return 1.0
            if ts < PASSING_END + half:
                return _smootherstep(
                    1.0 - (ts - (PASSING_END - half)) / SWITCH_RAMP_M)
            return 0.0

        # --- True plan-view pinhole projection for curves ---------------
        # Instead of the old linear "½ f κ d" chord approximation (which
        # fails badly once curvature changes along the view — produces
        # stray off-centre "dark circles" in the distance and a visible
        # kink where a curve meets a straight), project every track
        # point through the real plan geometry. For each target s we
        # fetch its world (px, py) from _GEOM, transform to the driver's
        # local frame (forward along his heading, lateral to his right),
        # and apply the standard pinhole x/z = focal · lateral / forward.
        # Driver eye is at view_s (front cab) ; his heading equals the
        # tunnel bearing at that s, flipped 180° when running in reverse.
        p0x, p0y = plan_at(view_s)
        h0_deg = heading_at(view_s)
        if tr.direction < 0:
            h0_deg += 180.0
        h0_rad = math.radians(h0_deg)
        sin_h0 = math.sin(h0_rad)
        cos_h0 = math.cos(h0_rad)
        # Driver's own-track lateral offset from the bore centerline.
        # Inside the Abt passing loop the two tracks sit 3 m apart centre
        # to centre ; the driver is on HIS side, not on the bore axis.
        # Subtracting this offset from every projected point effectively
        # moves the camera onto the own-track centerline, so the cabin
        # follows its actual rails and the opposing track + ghost wagon
        # appear offset to the opposite side — exactly how it looks from
        # the real Perce-Neige driver's seat during the crossing.
        own_eye_offset = own_side_sign * (TRACK_SEP_M * 0.5) * _loop_sep(view_s)

        def _plan_local(s_target: float) -> tuple[float, float]:
            """Return (forward_m, lateral_m) of track point at slope s in
            the driver's local frame. forward > 0 = ahead, lateral > 0
            = to the driver's right."""
            px, py = plan_at(s_target)
            dx = px - p0x
            dy = py - p0y
            # Driver heading unit vector : (sin h0, cos h0) in (east, north).
            fwd = dx * sin_h0 + dy * cos_h0
            lat = dx * cos_h0 - dy * sin_h0
            # Shift the camera onto the own-track centerline during the
            # passing loop : everything world-referenced appears laterally
            # offset by −own_eye_offset.
            return fwd, lat - own_eye_offset

        # === True 3-axis pinhole projection ===============================
        # _plan_local gives bird's-eye (fwd_plan, lat). To render vertical
        # slope curvature EXACTLY (symmetric to horizontal curves), we also
        # need the integrated altitude delta relative to the driver — pulled
        # from geom_at (which holds the fully integrated tunnel profile) —
        # and we rotate the (fwd_plan, dz) pair by the driver's pitch to
        # obtain the true camera-frame (forward, up) axes. This replaces the
        # old 1st-order `tan(slope_ahead − slope_here)` approximation that
        # collapsed when slope varied sharply along view depth (e.g. the
        # 30 %→2 % break at Grande Motte platform approach).
        local_pitch = local_slope_rad * tr.direction
        sin_pitch = math.sin(local_pitch)
        cos_pitch = math.cos(local_pitch)
        _driver_alt = geom_at(view_s)[1]

        def _proj_local(s_target: float) -> tuple[float, float, float]:
            """Return (fwd_cam, lat, up_cam) — camera-frame coordinates in
            metres. fwd_cam is straight-line 3D distance along the driver's
            look axis, up_cam the perpendicular vertical offset. Both
            horizontal (plan) and vertical (altitude) track curvature are
            integrated via _GEOM so the projection is physically exact."""
            fwd_plan, lat = _plan_local(s_target)
            dz = geom_at(s_target)[1] - _driver_alt
            fwd_cam = fwd_plan * cos_pitch + dz * sin_pitch
            up_cam = -fwd_plan * sin_pitch + dz * cos_pitch
            return fwd_cam, lat, up_cam

        def _ring_xyr(d: float) -> tuple[float, float, float, float, float]:
            """Project ring at depth d. Returns (cx, cy, r_px, ts, near_f).

            Uses true plan projection so curved tunnels render correctly
            through their whole depth — no stray ring silhouettes, no
            kink at curve/straight transitions."""
            ts = max(0.0, min(LENGTH, view_s + d * tr.direction))
            fwd, lat, up = _proj_local(ts)
            fwd = max(fwd, 0.35)
            cxp = eye_x + focal * lat / fwd
            # True 3D pinhole projection : vertical offset comes from the
            # integrated altitude delta (geom_at) rotated into the driver's
            # pitched camera frame — renders sharp slope breaks correctly.
            cyp = eye_y - focal * up / fwd
            r_raw = focal * R_t / fwd
            r_px = min(r_raw, effective_view_w * 1.25)
            near_f = min(1.0, 3.0 / max(d, 3.0))
            return cxp, cyp, r_px, ts, near_f

        # === Pass 1: tunnel walls (near → far) =========================
        # Cull rings whose centre lies more than 1.5 viewports off-axis
        # — those are "behind the curve" and contribute only phantom
        # dark circles at the horizon. Keep a generous margin so rings
        # partially inside the frame still render correctly.
        cull_x = effective_view_w * 1.5
        # Collect ring envelope points so we can draw continuous floor /
        # ceiling / sidewall-arch polylines between passes. Connecting the
        # edges of successive rings is what perceptually reveals tunnel
        # curvature — lateral (turns) AND vertical (slope breaks) — as
        # a smooth bending surface instead of a stack of isolated discs.
        floor_pts: list[tuple[QPointF, float]] = []   # (pt, near_f)
        ceil_pts: list[tuple[QPointF, float]] = []
        arch_l_pts: list[tuple[QPointF, float]] = []  # side arch (wall-height)
        arch_r_pts: list[tuple[QPointF, float]] = []
        # Paint far → near so the nearer walls correctly occlude anything
        # further down the tunnel. With near → far (the previous order)
        # the far rings painted on top of the near ones, which in a
        # curve meant the next section of tunnel punched visibly through
        # the sidewall — exactly the "on voit la suite à travers la
        # paroi" artefact reported on the 1 297 m and 1 884 m bends.
        for d in reversed(ring_depths):
            cx, cy, r_px, track_s_c, near_f = _ring_xyr(d)
            if abs(cx - eye_x) > cull_x + r_px:
                continue
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
            # Widen the tunnel cross-section in the passing loop : the
            # real cavern holds two 1.2 m-gauge tracks 3 m apart plus
            # clearance ≈ 7-8 m overall width, i.e. ~2.3 × the running
            # bore. Horizontal radius scales linearly with sep.
            sep = _loop_sep(track_s_c)
            fwd_d = max(d, 0.35)
            px_per_m_d = focal / fwd_d
            # Half-separation between the two parallel tracks in px at
            # this depth.
            track_half_px = (TRACK_SEP_M * 0.5) * px_per_m_d * sep
            rx_px = r_px + sep * (TRACK_SEP_M * 0.5 + 0.8) * px_per_m_d
            ry_px = r_px + sep * 0.6 * px_per_m_d  # slight vertical rise
            # Silhouette outline — drawn at ALL distances so the driver
            # can still read the tunnel *shape* (circular TBM vs. square
            # cut-and-cover) far ahead, where diffuse wall shading alone
            # turns uniformly grey. Intensity is independent of near_f
            # so distant rings keep a crisp outline against the tunnel
            # dark interior.
            silhouette_col = QColor(12, 10, 8, 230)
            hi_col = QColor(210, 205, 195, int(120 + 100 * near_f))
            if shape == "circular":
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(wc))
                p.drawEllipse(QPointF(cx, cy), rx_px, ry_px)
                p.setBrush(QBrush(dark_c))
                p.drawEllipse(QPointF(cx, cy),
                              rx_px * 0.96, ry_px * 0.92)
                # Hard outer silhouette (reads as "where rock ends")
                p.setBrush(Qt.BrushStyle.NoBrush)
                p.setPen(QPen(silhouette_col, max(1.2 * near_f + 0.6, 0.8)))
                p.drawEllipse(QPointF(cx, cy), rx_px, ry_px)
                p.setPen(Qt.PenStyle.NoPen)
                # Rock asperities — small deterministic dark/light blotches
                # around the inner wall so the bore looks like drilled rock
                # instead of a smooth concrete pipe. Position + size are
                # phase-locked to the ring's s-coordinate so they don't
                # flicker between frames.
                # Rock blotches are visible only at mid-depth ; skip
                # when the ring is too close (would cover the cockpit)
                # or too far (invisible anyway). Sizes are capped in
                # absolute pixels so a near ring doesn't paint a
                # giant grey spot across the view.
                if 10.0 < r_px < 110.0 and 0.10 < near_f < 0.85:
                    s_seed = track_s_c * 0.37
                    n_rocks = 5
                    for ki in range(n_rocks):
                        ang = ((s_seed + ki * 1.9) % (2.0 * math.pi))
                        if -0.9 < math.sin(ang) < 0.2 and math.cos(ang) < 0:
                            continue
                        rx = math.cos(ang) * rx_px * 0.90
                        ry_o = math.sin(ang) * ry_px * 0.80
                        sz_w = max(0.8, min(rx_px * 0.08
                                  * (0.7 + 0.5 * math.sin(s_seed + ki)), 6.0))
                        sz_h = max(0.6, min(ry_px * 0.06
                                  * (0.8 + 0.4 * math.cos(s_seed - ki)), 5.0))
                        shade = 0.65 + 0.35 * math.sin(s_seed * 1.3 + ki)
                        tone = int(wall_bright * max(0.35, shade * 0.75))
                        p.setBrush(QBrush(QColor(tone, int(tone * 1.02),
                                                 int(tone * 0.94),
                                                 int(150 * near_f + 40))))
                        p.drawEllipse(QPointF(cx + rx, cy + ry_o),
                                      sz_w, sz_h)
                    # Thin segment ring marks (TBM ring joints) every ~1.5 m
                    joint_alpha = int(min(140, 40 + 90 * near_f))
                    p.setPen(QPen(QColor(22, 18, 14, joint_alpha),
                                  max(0.8 * near_f, 0.4)))
                    p.setBrush(Qt.BrushStyle.NoBrush)
                    p.drawEllipse(QPointF(cx, cy),
                                  rx_px * 0.98, ry_px * 0.94)
                    p.setPen(Qt.PenStyle.NoPen)
            else:
                hw = rx_px * 1.2
                hh = ry_px * 1.1
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
                # Hard outer silhouette — the square cut-and-cover
                # cross-section should read as visibly rectangular at
                # any depth, not blur into a grey disc like the TBM.
                p.setBrush(Qt.BrushStyle.NoBrush)
                p.setPen(QPen(silhouette_col, max(1.2 * near_f + 0.6, 0.8)))
                p.drawPath(path)
                p.setPen(Qt.PenStyle.NoPen)
            # Central median : in the Abt passing loop there is a
            # low concrete divider (≈ 40 cm high) between the two
            # tracks, carrying the cable-guide pulleys. Draw as a
            # thin dark bar at rail level, shrinking to nothing at the
            # switch transitions.
            if sep > 0.15 and r_px > 3.0:
                med_h_px = focal * 0.40 / fwd_d
                med_w_px = max(1.2, focal * 0.30 / fwd_d)
                med_rail_y = cy + ry_px * 0.72
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(QColor(75, 72, 68,
                                         int(120 + 120 * sep * near_f))))
                p.drawRect(QRectF(cx - med_w_px * 0.5,
                                  med_rail_y - med_h_px,
                                  med_w_px, med_h_px))
            # Wall cables (only visible when nearby)
            if r_px > 12 and near_f > 0.15:
                cable_alpha = int(min(200, 60 + 140 * near_f))
                p.setPen(QPen(QColor(40, 40, 45, cable_alpha),
                              max(2.0 * near_f, 0.5)))
                for off in (0.35, 0.55, 0.75):
                    p.drawPoint(QPointF(cx - r_px * 0.88,
                                        cy - r_px * off + r_px * 0.3))
            # Collect envelope points — ceiling (top of bore), floor
            # (bottom of bore at ballast), and the two side arches at
            # wall-mid height — for continuous polylines drawn between
            # passes. These reveal BOTH horizontal and vertical tunnel
            # curvature as a bending surface, matching how the real eye
            # perceives a tube.
            floor_pts.append((QPointF(cx, cy + ry_px), near_f))
            ceil_pts.append((QPointF(cx, cy - ry_px), near_f))
            arch_l_pts.append(
                (QPointF(cx - rx_px * 0.92, cy - ry_px * 0.35), near_f))
            arch_r_pts.append(
                (QPointF(cx + rx_px * 0.92, cy - ry_px * 0.35), near_f))

        # === Pass 1.5: tunnel envelope polylines ========================
        # Continuous floor / ceiling / arch lines traced through the
        # collected ring-edge points. Stroked with near-to-far alpha
        # ramping so distant parts fade into the dark, and with slight
        # thickening near the camera for a natural perspective feel.
        def _draw_envelope(pts: list[tuple[QPointF, float]],
                           base_color: QColor,
                           width_near: float,
                           width_far: float) -> None:
            if len(pts) < 2:
                return
            for i in range(len(pts) - 1):
                a, nfa = pts[i]
                b, nfb = pts[i + 1]
                nf = 0.5 * (nfa + nfb)
                alpha = int(min(230, 60 + 170 * nf))
                pen_w = width_far + (width_near - width_far) * nf
                col = QColor(base_color.red(), base_color.green(),
                             base_color.blue(), alpha)
                p.setPen(QPen(col, pen_w))
                p.drawLine(a, b)

        # Floor (dark, wider) — dominant visual cue for slope dip / rise.
        _draw_envelope(floor_pts, QColor(24, 20, 16), 4.0, 1.2)
        # Ceiling (medium) — reveals pitch symmetry.
        _draw_envelope(ceil_pts, QColor(60, 52, 42), 2.5, 0.8)
        # Side arches (subtle) — give tube a sense of walls, reveal turns.
        _draw_envelope(arch_l_pts, QColor(55, 48, 40), 2.0, 0.6)
        _draw_envelope(arch_r_pts, QColor(55, 48, 40), 2.0, 0.6)

        # === Pass 2: rails, ties, chevrons (far → near) ================
        # Cable visibility rules (single loop around upper bull wheel):
        #   climbing  — before loop: 1 cable (center)
        #             — past loop:   2 cables (2nd offset toward own side:
        #                            Train 1 → right of 1st, Train 2 → left)
        #   descending — before loop (above loop): 1 cable
        #              — past loop (below loop):   0 cables
        # The "own side" for the second cable is the physical side of the
        # track the train runs on through the Abt switch — flips in F4
        # driver POV when direction reverses (east/west stays absolute, but
        # left/right on screen inverts).
        # (own_side_sign is defined earlier so _plan_local can use it.)
        # Second-cable side when climbing past loop (user spec):
        # Train 1 climbing → right of 1st, Train 2 climbing → left of 1st.
        # On descent past loop no second cable is drawn so side unused.
        second_cable_side = +1 if tr.number == 1 else -1
        # Cable count transitions EXACTLY when the main train passes the
        # opposing wagon (not when crossing a static loop boundary). The
        # ghost centre at tr.s means the two trains are alongside ; the
        # n_cables rule flips the frame the ghost crosses our eye plane.
        ghost_ahead_m = (st.ghost_s - tr.s) * tr.direction
        has_crossed = ghost_ahead_m < 0.0
        if tr.direction > 0:
            n_cables_main = 2 if has_crossed else 1
        else:
            n_cables_main = 0 if has_crossed else 1
        prev_pts: dict[str, QPointF | None] = {
            'lr': None, 'rr': None, 'cg1': None, 'cg2': None,
            # Opposing track rails (only drawn inside the passing loop)
            'olr': None, 'orr': None,
        }
        for d in reversed(ring_depths):
            cx, cy, r_px, track_s_c, near_f = _ring_xyr(d)
            if r_px < 1.0:
                continue
            if abs(cx - eye_x) > cull_x + r_px:
                prev_pts = {'lr': None, 'rr': None,
                            'cg1': None, 'cg2': None,
                            'olr': None, 'orr': None}
                continue
            # Passing loop : shift own track toward own_side_sign by
            # ½·TRACK_SEP and draw opposing rails at the mirrored
            # position. `sep` ramps 0→1 through the Abt switch so the
            # rails visibly fan out / rejoin.
            sep_r = _loop_sep(track_s_c)
            fwd_d = max(d, 0.35)
            track_half_px_r = (TRACK_SEP_M * 0.5) * (focal / fwd_d) * sep_r
            own_cx = cx + own_side_sign * track_half_px_r
            opp_cx = cx - own_side_sign * track_half_px_r
            gauge_px = r_px * 0.35
            rail_y = cy + r_px * 0.75
            left_rail = QPointF(own_cx - gauge_px, rail_y)
            right_rail = QPointF(own_cx + gauge_px, rail_y)
            # Ballast gravel band — continuous dark-gray fill between
            # the outer edges of the sleeper bed, with deterministic
            # lighter speckles for crushed-stone texture. Drawn under
            # the sleeper so the tie appears to rest on the ballast.
            if 4.0 < r_px < 260.0 and near_f > 0.06:
                # Cap ballast half-width in absolute pixels so near rings
                # don't drop a giant dark slab over the cockpit view.
                bhw = min(gauge_px * 1.35, 90.0)
                if sep_r > 0.05:
                    bhw_total_lo = own_cx - bhw
                    bhw_total_hi = opp_cx + bhw
                    if bhw_total_lo > bhw_total_hi:
                        bhw_total_lo, bhw_total_hi = bhw_total_hi, bhw_total_lo
                    bal_lo, bal_hi = bhw_total_lo, bhw_total_hi
                else:
                    bal_lo = own_cx - bhw
                    bal_hi = own_cx + bhw
                bal_h = max(1.0, min(r_px * 0.05, 4.0))
                bal_alpha = int(min(200, 60 + 140 * near_f))
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(QColor(42, 38, 32, bal_alpha)))
                p.drawRect(QRectF(bal_lo, rail_y - bal_h * 0.5,
                                  bal_hi - bal_lo, bal_h * 1.6))
                # Speckled lighter chips (crushed stone) — deterministic.
                if near_f > 0.25 and r_px > 12:
                    chip_alpha = int(min(220, 80 + 140 * near_f))
                    p.setBrush(QBrush(QColor(130, 122, 108, chip_alpha)))
                    s_seed_b = track_s_c * 0.53
                    for ki in range(6):
                        frac = (math.sin(s_seed_b + ki * 1.7) * 0.5 + 0.5)
                        chip_x = bal_lo + frac * (bal_hi - bal_lo)
                        chip_dy = (math.cos(s_seed_b * 0.7 + ki) * 0.45
                                   * bal_h)
                        chip_sz = max(0.8, r_px * 0.012
                                      * (0.8 + 0.4 * math.sin(ki + s_seed_b)))
                        p.drawEllipse(QPointF(chip_x,
                                              rail_y + chip_dy),
                                      chip_sz, chip_sz * 0.7)
            n_cables = n_cables_main
            # Cable-guide positioning :
            #   - Outside the loop (sep_r ≈ 0) : cable 1 runs down the
            #     bore centerline (centered on climb, shifted left on
            #     descent), cable 2 sits slightly off to second_cable_side.
            #   - Inside the loop (sep_r > 0) : the traction cables split
            #     onto their own tracks — cable 1 on OWN track centerline,
            #     cable 2 on OPPOSING track centerline — so the visual
            #     match the real Abt loop where each wagon is pulled by
            #     its own side of the figure-8 rope.
            # Because track_half_px_r already scales with sep_r, own_cx
            # and opp_cx collapse onto cx outside the loop, so the
            # transition is smooth without an explicit blend.
            fade_straight = 1.0 - sep_r
            cable1_x = (own_cx
                        + (-gauge_px * 0.45 if tr.direction < 0 else 0.0)
                          * fade_straight)
            cable1 = QPointF(cable1_x, rail_y - r_px * 0.03)
            cable2_x = opp_cx + second_cable_side * gauge_px * 0.45 * fade_straight
            cable2 = QPointF(cable2_x, rail_y - r_px * 0.03)
            # Rails : three-layer stroke (shadow below, steel body,
            # bright running surface on top) drawn as simple lines so
            # near rings can't inflate a polygon into a screen-filling
            # slab. Widths are capped in absolute pixels.
            rail_alpha = int(min(245, 100 + 160 * near_f))
            body_w = max(1.4, min(2.6 * near_f, 3.8))
            top_w = max(0.6, min(1.2 * near_f, 1.8))
            shadow_w = max(0.8, min(1.8 * near_f, 2.4))
            # Vertical lift from rail_y for the head highlight (rail
            # head sits ~2 px above the foot when close).
            lift = max(0.6, min(1.6 * near_f, 2.8))
            rail_body_col = QColor(165, 168, 158, rail_alpha)
            rail_top_col = QColor(240, 240, 230, rail_alpha)
            rail_shadow_col = QColor(30, 27, 22, int(rail_alpha * 0.85))
            for side_key, pt_new in (('lr', left_rail), ('rr', right_rail)):
                pt_prev = prev_pts[side_key]
                if pt_prev is not None:
                    xp, yp = pt_prev.x(), pt_prev.y()
                    xn, yn = pt_new.x(), pt_new.y()
                    # Shadow cast on ballast just below rail
                    p.setPen(QPen(rail_shadow_col, shadow_w))
                    p.drawLine(QPointF(xp, yp + lift * 0.5),
                               QPointF(xn, yn + lift * 0.5))
                    # Steel body — main rail line
                    p.setPen(QPen(rail_body_col, body_w))
                    p.drawLine(QPointF(xp, yp - lift * 0.4),
                               QPointF(xn, yn - lift * 0.4))
                    # Polished running surface on top
                    p.setPen(QPen(rail_top_col, top_w))
                    p.drawLine(QPointF(xp, yp - lift),
                               QPointF(xn, yn - lift))
                prev_pts[side_key] = pt_new
            cable_w = max(0.8, min(1.6 * near_f, 2.2))
            p.setPen(QPen(QColor(100, 105, 95, rail_alpha), cable_w))
            if n_cables >= 1:
                if prev_pts['cg1'] is not None:
                    p.drawLine(prev_pts['cg1'], cable1)
                prev_pts['cg1'] = cable1
            else:
                prev_pts['cg1'] = None
            if n_cables >= 2:
                if prev_pts['cg2'] is not None:
                    p.drawLine(prev_pts['cg2'], cable2)
                prev_pts['cg2'] = cable2
            else:
                prev_pts['cg2'] = None
            # Opposing-track rails inside the passing loop.
            if sep_r > 0.02:
                opp_left = QPointF(opp_cx - gauge_px, rail_y)
                opp_right = QPointF(opp_cx + gauge_px, rail_y)
                p.setPen(QPen(QColor(150, 155, 145, rail_alpha), body_w))
                if prev_pts['olr'] is not None:
                    p.drawLine(prev_pts['olr'], opp_left)
                prev_pts['olr'] = opp_left
                if prev_pts['orr'] is not None:
                    p.drawLine(prev_pts['orr'], opp_right)
                prev_pts['orr'] = opp_right
            else:
                prev_pts['olr'] = None
                prev_pts['orr'] = None
            # Sleeper + central cable-guide bolt. Inside the passing
            # loop the sleeper extends across BOTH tracks — real Abt
            # loops use continuous ties from one rail set to the other.
            # Sleepers : concrete ties with a lighter top face, darker
            # side shadow beneath, and bright bolt plates where each
            # rail sits on them. Much richer than the old flat dark
            # rectangle — reads as real infrastructure at cruise speed.
            tie_alpha = int(min(230, 70 + 160 * near_f))
            tie_h = max(3.0 * near_f, 1.0)
            p.setPen(Qt.PenStyle.NoPen)
            if sep_r > 0.05:
                tie_x_lo = min(own_cx, opp_cx) - gauge_px * 1.15
                tie_x_hi = max(own_cx, opp_cx) + gauge_px * 1.15
            else:
                tie_x_lo = own_cx - gauge_px * 1.15
                tie_x_hi = own_cx + gauge_px * 1.15
            tie_w_total = tie_x_hi - tie_x_lo
            # Shadow underneath sleeper (offset down by tie_h)
            p.setBrush(QBrush(QColor(18, 14, 10,
                                     int(tie_alpha * 0.9))))
            p.drawRect(QRectF(tie_x_lo + tie_h * 0.3,
                              rail_y + tie_h * 0.5,
                              tie_w_total, tie_h * 0.55))
            # Main concrete tie body
            p.setBrush(QBrush(QColor(78, 74, 68, tie_alpha)))
            p.drawRect(QRectF(tie_x_lo, rail_y - tie_h * 0.5,
                              tie_w_total, tie_h))
            # Lighter top face (weathered-concrete highlight)
            p.setBrush(QBrush(QColor(118, 112, 100,
                                     int(tie_alpha * 0.75))))
            p.drawRect(QRectF(tie_x_lo + tie_h * 0.2,
                              rail_y - tie_h * 0.5,
                              tie_w_total - tie_h * 0.4,
                              tie_h * 0.35))
            # Rail-fastening plates where each rail crosses the tie —
            # small dark squares, give the track its "bolt every sleeper"
            # feel (Pandrol-style clip bases).
            plate_alpha = int(min(240, 110 + 140 * near_f))
            plate_w = max(gauge_px * 0.22, 1.2)
            plate_h = max(tie_h * 1.25, 1.2)
            plate_col = QColor(30, 27, 22, plate_alpha)
            p.setBrush(QBrush(plate_col))
            if r_px > 3.0:
                for rail_cx in (own_cx - gauge_px, own_cx + gauge_px):
                    p.drawRect(QRectF(rail_cx - plate_w * 0.5,
                                      rail_y - plate_h * 0.5,
                                      plate_w, plate_h))
                if sep_r > 0.05:
                    for rail_cx in (opp_cx - gauge_px, opp_cx + gauge_px):
                        p.drawRect(QRectF(rail_cx - plate_w * 0.5,
                                          rail_y - plate_h * 0.5,
                                          plate_w, plate_h))
            # Central cable-guide bolt — only drawn when there actually
            # IS a cable running above it. In descent past the passing
            # loop both traction cables are behind the driver, so no
            # guide infrastructure is visible ahead (the bore centreline
            # is empty).
            if n_cables >= 1:
                bolt_w = max(2.0 * near_f, 0.7)
                p.setBrush(QBrush(QColor(140, 135, 120,
                                         int(tie_alpha * 0.8))))
                p.drawRect(QRectF(own_cx - bolt_w, rail_y - tie_h * 0.7,
                                  bolt_w * 2.0, tie_h * 1.4))
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

        # === Fluorescent tubes on the tunnel wall ======================
        # Real Perce-Neige tunnel : VERTICAL fluorescent tubes (~1.2 m
        # long), mounted on the left wall in the climbing direction at
        # a constant spacing. They are present the WHOLE length of the
        # tunnel — no gaps, no dark sections from the driver's POV
        # (the earlier "intermittent" look was a brightness-analysis
        # artifact, not real installation geometry).
        NEON_SPACING = 8.0              # ~8 m between tubes (constant)
        NEON_LENGTH = 1.2               # vertical tube length (m)
        neon_side = -1.0 if tr.direction > 0 else +1.0
        neon_max_depth = 90.0 if tr.lights_head else 40.0

        def _proj_wall_point(d: float, h_above_rail: float
                             ) -> tuple[float, float, float]:
            """Project a point on the side wall at depth d, height h
            above rail level (metres). Returns screen (x, y, near_f).
            The lateral offset follows the real circular bore :
            lat = sqrt(R_t² − y_center²). So a point near the floor
            sits far from the axis, while a point near the crown sits
            close to it — the neon tubes naturally lean outward at the
            bottom and inward at the top, exactly as they do bolted to
            a round rock wall."""
            ts = max(0.0, min(LENGTH, view_s + d * tr.direction))
            fwd, lat, up = _proj_local(ts)
            fwd = max(fwd, 0.35)
            cxw = eye_x + focal * lat / fwd
            cyw = eye_y - focal * up / fwd
            rw_raw = focal * R_t / fwd
            rw = min(rw_raw, effective_view_w * 1.25)
            # Rail sits 0.75·R_t below the tunnel axis (see ring drawing)
            y_center = h_above_rail - 0.75 * R_t
            y_clamp = max(-R_t * 0.985, min(R_t * 0.985, y_center))
            lat_half_m = math.sqrt(R_t * R_t - y_clamp * y_clamp)
            lat_half_px = focal * lat_half_m / fwd
            # Clip against the drawn ellipse so the tube stays visibly
            # on the wall even when the paraxial scale clamps rw.
            lat_half_px = min(lat_half_px, rw * (lat_half_m / R_t))
            wall_x = cxw + neon_side * lat_half_px
            rail_y = cyw + rw * 0.75
            wall_y = rail_y - (focal * h_above_rail / fwd)
            nf = min(1.0, 3.0 / max(d, 3.0))
            return wall_x, wall_y, nf

        # Tube geometry : mounted 1.5-2.7 m above rail, vertical span 1.2 m.
        NEON_Y_BOTTOM = 1.5              # m above rail
        NEON_Y_TOP = NEON_Y_BOTTOM + NEON_LENGTH

        k_span = int(neon_max_depth / NEON_SPACING) + 3
        # Anchor the tube positions to absolute slope metres so they
        # don't wobble as the train moves (phase-locked to s=0).
        k_center = int(view_s / NEON_SPACING)
        for k in range(k_center - k_span, k_center + k_span + 1):
            neon_s = k * NEON_SPACING
            if neon_s < 0.0 or neon_s > LENGTH:
                continue
            depth_c = (neon_s - view_s) * tr.direction
            if depth_c < 1.0 or depth_c > neon_max_depth:
                continue
            xb, yb, nf = _proj_wall_point(depth_c, NEON_Y_BOTTOM)
            xt, yt, _ = _proj_wall_point(depth_c, NEON_Y_TOP)
            halo_w = max(11.0 * nf, 3.0)
            mid_w = max(5.5 * nf, 1.8)
            core_w = max(2.6 * nf, 1.0)
            alpha_halo = int(min(180, 80 + 100 * nf))
            alpha_mid = int(min(230, 120 + 110 * nf))
            alpha_core = int(min(255, 180 + 75 * nf))
            p.setPen(QPen(QColor(170, 200, 255, alpha_halo), halo_w))
            p.drawLine(QPointF(xb, yb), QPointF(xt, yt))
            p.setPen(QPen(QColor(220, 235, 255, alpha_mid), mid_w))
            p.drawLine(QPointF(xb, yb), QPointF(xt, yt))
            p.setPen(QPen(QColor(255, 255, 245, alpha_core), core_w))
            p.drawLine(QPointF(xb, yb), QPointF(xt, yt))

        # === Opposing wagon at the passing loop =========================
        # When both trains are near the Abt passing loop, the opposing
        # wagon is physically alongside us on the parallel track (203 m
        # long, ~3 m lateral separation). Draw a cylindrical silhouette
        # with windows on the opposing side of the tunnel, projected at
        # the slope-s range occupied by the opposing train.
        opposing_side_sign = -own_side_sign
        ghost_d_front = (st.ghost_s + TRAIN_HALF - view_s) * tr.direction
        ghost_d_back = (st.ghost_s - TRAIN_HALF - view_s) * tr.direction
        ghost_d_lo, ghost_d_hi = sorted((ghost_d_front, ghost_d_back))
        show_ghost = (
            (is_passing_loop(tr.s) or is_passing_loop(st.ghost_s))
            and ghost_d_hi > 1.0 and ghost_d_lo < max_depth
        )
        if show_ghost:
            # Ghost track half-separation from bore centerline : 1.5 m, but
            # ramps with _loop_sep so the ghost swings laterally across the
            # switch frog like a real Abt wagon (no hard jump from centre).
            # Combined with own_eye_offset (driver on his own track), the
            # NET lateral separation seen from the cabin is ≈ 3 m centre
            # to centre while inside the loop — matching the real passing
            # loop geometry.
            GHOST_HALF = TRACK_SEP_M * 0.5     # 1.5 m
            CAB_R = 1.80                        # cabin radius (m)
            CAB_TOP = 3.20                      # cabin roof height above rail
            CAB_BOT = 0.00                      # underframe bottom
            # Vertical layering for a cylindrical side-view with 3D shading.
            # Each tuple is (h_lo, h_hi, fill_color). From bottom up :
            # undercarriage (bogie shadow), lower cylinder face (self-shadow),
            # window band (light interior behind frames), upper cylinder
            # face (direct highlight), roof curve (top cap with darker
            # gradient). Values chosen so the wagon reads as a cylinder
            # lit from above (tunnel neons are on the opposite wall which
            # from the ghost cabin's view is its OWN side, so the side
            # facing us is mostly in shadow with a highlight just below
            # the roof curve).
            BANDS = _GHOST_BANDS

            def _proj_ghost(s_slope: float, h_above_rail: float
                            ) -> tuple[float, float, float] | None:
                d = (s_slope - view_s) * tr.direction
                if d < 0.8 or d > max_depth:
                    return None
                ts = max(0.0, min(LENGTH, s_slope))
                fwd, lat, up = _proj_local(ts)
                fwd = max(fwd, 0.35)
                sep_g = _loop_sep(ts)
                lat_g = lat + opposing_side_sign * GHOST_HALF * sep_g
                cxw = eye_x + focal * lat_g / fwd
                cyw = eye_y - focal * up / fwd
                rw = focal * R_t / fwd
                rail_y = cyw + rw * 0.75
                y = rail_y - focal * h_above_rail / fwd
                return cxw, y, min(1.0, 4.0 / max(d, 4.0))

            # Sample 28 points along the opposing train in slope-s space.
            # (2 cars × 16 m = 32 m, so one sample per ≈ 1.1 m.)
            n_samples = 28
            s_start = st.ghost_s - TRAIN_HALF
            s_end = st.ghost_s + TRAIN_HALF
            # Build a table : for every sampled s_m, project every band
            # height in BANDS to an (x, y) screen point.
            band_rows: list[list[QPointF | None]] = [
                [] for _ in BANDS
            ]          # band_rows[band_idx][sample_idx]
            # Plus a supplementary row at window-centre height (1.55 m)
            # so we can place window glass rectangles anchored to the
            # actual geometry rather than rely on a separate projection.
            win_row_top: list[tuple[float, float, float] | None] = []
            win_row_bot: list[tuple[float, float, float] | None] = []
            sample_s: list[float] = []
            for i in range(n_samples + 1):
                s_m = s_start + (s_end - s_start) * (i / n_samples)
                sample_s.append(s_m)
                # Skip samples behind the driver — projection undefined.
                d_m = (s_m - view_s) * tr.direction
                if d_m < 0.6:
                    for row in band_rows:
                        row.append(None)
                    win_row_top.append(None)
                    win_row_bot.append(None)
                    continue
                for bi, (h_lo, h_hi, _col) in enumerate(BANDS):
                    # Store the UPPER edge point (h_hi) ; lower edge of
                    # band N = upper edge of band N−1 so we don't double
                    # sample. For band 0 we need the floor separately.
                    pt = _proj_ghost(s_m, h_hi)
                    if pt is None:
                        band_rows[bi].append(None)
                    else:
                        band_rows[bi].append(QPointF(pt[0], pt[1]))
                pt_floor = _proj_ghost(s_m, BANDS[0][0])
                # Window row : upper/lower frame for lit glass.
                pt_wt = _proj_ghost(s_m, 2.00)
                pt_wb = _proj_ghost(s_m, 1.25)
                win_row_top.append(pt_wt)
                win_row_bot.append(pt_wb)

            # Draw each band as a quad strip from lower edge to upper edge
            # (far-to-near painter order already by sample s order — but
            # correct left-to-right draw ordering is what matters for
            # alpha compositing).
            # Build a "floor" row = projection at h = BANDS[0][0].
            floor_row: list[QPointF | None] = []
            for s_m in sample_s:
                pt = _proj_ghost(s_m, BANDS[0][0])
                if pt is None:
                    floor_row.append(None)
                else:
                    floor_row.append(QPointF(pt[0], pt[1]))

            def _band_pairs(idx: int):
                """Yield (lower_pt, upper_pt) for band idx across samples."""
                lower_row = floor_row if idx == 0 else band_rows[idx - 1]
                upper_row = band_rows[idx]
                return list(zip(lower_row, upper_row))

            p.setPen(Qt.PenStyle.NoPen)
            for bi, (h_lo, h_hi, col) in enumerate(BANDS):
                pairs = _band_pairs(bi)
                # Split into continuous segments (None breaks the strip).
                seg: list[tuple[QPointF, QPointF]] = []
                for lp, up in pairs:
                    if lp is None or up is None:
                        if len(seg) >= 2:
                            path = QPainterPath()
                            path.moveTo(seg[0][0])  # first lower
                            for _lp, _up in seg:
                                path.lineTo(_lp)
                            for _lp, _up in reversed(seg):
                                path.lineTo(_up)
                            path.closeSubpath()
                            p.setBrush(QBrush(col))
                            p.drawPath(path)
                        seg = []
                    else:
                        seg.append((lp, up))
                if len(seg) >= 2:
                    path = QPainterPath()
                    path.moveTo(seg[0][0])
                    for _lp, _up in seg:
                        path.lineTo(_lp)
                    for _lp, _up in reversed(seg):
                        path.lineTo(_up)
                    path.closeSubpath()
                    p.setBrush(QBrush(col))
                    p.drawPath(path)

            # Windows : 6 per car (two cars), drawn as bright panels with
            # dark frame. Use a window every ~2.5 m along the car length.
            # s_start → s_end spans the full train ; cars meet at ghost_s.
            car_joint = st.ghost_s
            for win_i in range(12):
                # Window centre position along the train. Skip the 2-m
                # region around the car joint where the gangway goes.
                frac = (win_i + 0.5) / 12.0
                s_w = s_start + (s_end - s_start) * frac
                if abs(s_w - car_joint) < 1.0:
                    continue
                pt_t = _proj_ghost(s_w, 2.00)
                pt_b = _proj_ghost(s_w, 1.25)
                pt_c = _proj_ghost(s_w, 1.62)
                if pt_t is None or pt_b is None or pt_c is None:
                    continue
                # Frame geometry : horizontal window, ~1.2 m wide along
                # the train. Use the pair s_w ± 0.6 m for width.
                pt_l_t = _proj_ghost(s_w - 0.55, 2.00)
                pt_l_b = _proj_ghost(s_w - 0.55, 1.25)
                pt_r_t = _proj_ghost(s_w + 0.55, 2.00)
                pt_r_b = _proj_ghost(s_w + 0.55, 1.25)
                if any(v is None for v in (pt_l_t, pt_l_b, pt_r_t, pt_r_b)):
                    continue
                # Deep window recess : darker outer frame, then glass.
                wf = pt_c[2]
                frame = QPainterPath()
                frame.moveTo(QPointF(pt_l_t[0], pt_l_t[1]))
                frame.lineTo(QPointF(pt_r_t[0], pt_r_t[1]))
                frame.lineTo(QPointF(pt_r_b[0], pt_r_b[1]))
                frame.lineTo(QPointF(pt_l_b[0], pt_l_b[1]))
                frame.closeSubpath()
                p.setBrush(QBrush(QColor(18, 14, 10, 235)))
                p.drawPath(frame)
                # Inset glass — shrink 25 % toward centre.
                def _shrink(px, py, tx, ty, k=0.25):
                    return (px + (tx - px) * k, py + (ty - py) * k)
                gl_lt = _shrink(pt_l_t[0], pt_l_t[1], pt_c[0], pt_c[1])
                gl_rt = _shrink(pt_r_t[0], pt_r_t[1], pt_c[0], pt_c[1])
                gl_rb = _shrink(pt_r_b[0], pt_r_b[1], pt_c[0], pt_c[1])
                gl_lb = _shrink(pt_l_b[0], pt_l_b[1], pt_c[0], pt_c[1])
                glass = QPainterPath()
                glass.moveTo(QPointF(*gl_lt))
                glass.lineTo(QPointF(*gl_rt))
                glass.lineTo(QPointF(*gl_rb))
                glass.lineTo(QPointF(*gl_lb))
                glass.closeSubpath()
                glass_col = QColor(205, 220, 245, int(180 + 60 * wf))
                p.setBrush(QBrush(glass_col))
                p.drawPath(glass)

            # Inter-car gangway : dark band between the two cars.
            pt_j_t = _proj_ghost(car_joint, CAB_TOP - 0.10)
            pt_j_b = _proj_ghost(car_joint, CAB_BOT)
            pt_j_lt = _proj_ghost(car_joint - 0.60, CAB_TOP - 0.10)
            pt_j_lb = _proj_ghost(car_joint - 0.60, CAB_BOT)
            pt_j_rt = _proj_ghost(car_joint + 0.60, CAB_TOP - 0.10)
            pt_j_rb = _proj_ghost(car_joint + 0.60, CAB_BOT)
            if all(v is not None for v in (pt_j_lt, pt_j_lb, pt_j_rt, pt_j_rb)):
                gang = QPainterPath()
                gang.moveTo(QPointF(pt_j_lt[0], pt_j_lt[1]))
                gang.lineTo(QPointF(pt_j_rt[0], pt_j_rt[1]))
                gang.lineTo(QPointF(pt_j_rb[0], pt_j_rb[1]))
                gang.lineTo(QPointF(pt_j_lb[0], pt_j_lb[1]))
                gang.closeSubpath()
                p.setBrush(QBrush(QColor(30, 24, 18, 230)))
                p.drawPath(gang)

            # Dark outline along top + bottom for silhouette crispness.
            p.setPen(QPen(QColor(35, 28, 18, 230), 1.4))
            top_row = band_rows[-1]
            prev_t = None
            for pt in top_row:
                if pt is not None and prev_t is not None:
                    p.drawLine(prev_t, pt)
                prev_t = pt
            prev_b = None
            for pt in floor_row:
                if pt is not None and prev_b is not None:
                    p.drawLine(prev_b, pt)
                prev_b = pt

            # Cylindrical rounded end caps — on the leading end of the
            # ghost relative to the driver, build a hemispherical nose
            # cap from 5 nested shaded ellipses so the wagon reads as
            # a 3D cylinder with a domed face, not a flat silhouette.
            # Do the same for the trailing end so when the ghost passes,
            # both noses look correctly rounded.
            for lead_idx, cap_sign in ((0, -1), (n_samples, +1)):
                lead_s = sample_s[lead_idx]
                pt_lead_top = _proj_ghost(lead_s, CAB_TOP)
                pt_lead_bot = _proj_ghost(lead_s, CAB_BOT)
                pt_lead_mid = _proj_ghost(lead_s, (CAB_TOP + CAB_BOT) * 0.5)
                if (pt_lead_top is None or pt_lead_bot is None
                        or pt_lead_mid is None):
                    continue
                d_lead = (lead_s - view_s) * tr.direction
                if d_lead <= 1.0:
                    continue
                cap_h = abs(pt_lead_top[1] - pt_lead_bot[1])
                cap_w = max(2.0, focal * CAB_R * 0.5 / max(d_lead, 0.35))
                cap_cx = pt_lead_mid[0]
                cap_cy = pt_lead_mid[1]
                p.setPen(Qt.PenStyle.NoPen)
                # Build 5 shaded rings from rim (dark) to centre (bright
                # highlight offset up-left, as if lit by tunnel neons on
                # the opposite bore wall). Each ring shrinks by 20 %.
                rings = 5
                for ri in range(rings):
                    frac = 1.0 - ri / float(rings)
                    # Colour ramps from rim (dark brown, #2a1f10) to
                    # highlight (warm amber, #d2a548) along the normal.
                    t = ri / float(rings - 1)
                    r_col = int(42 + (210 - 42) * t)
                    g_col = int(32 + (165 - 32) * t)
                    b_col = int(18 + (72 - 18) * t)
                    a = int(230 - 30 * t)
                    # Shift highlight up-left for 3D lit-dome illusion
                    shift_x = -cap_w * 0.15 * t
                    shift_y = -cap_h * 0.08 * t
                    p.setBrush(QBrush(QColor(r_col, g_col, b_col, a)))
                    p.drawEllipse(
                        QPointF(cap_cx + shift_x, cap_cy + shift_y),
                        cap_w * frac,
                        cap_h * 0.5 * frac,
                    )
                # Rim outline for silhouette crispness
                p.setPen(QPen(QColor(25, 20, 12, 230), 1.2))
                p.setBrush(Qt.BrushStyle.NoBrush)
                p.drawEllipse(QPointF(cap_cx, cap_cy), cap_w, cap_h * 0.5)
            # Keep lead_s defined for the headlight block below
            lead_idx = 0 if ghost_d_front < ghost_d_back else n_samples
            lead_s = sample_s[lead_idx]

            # Headlights on the leading end if ghost is heading towards us
            # and close enough (< 40 m). Pair of bright warm LEDs near
            # the front of the cap at 2.3 m height.
            ghost_travel_sign = (1 if st.ghost_s < tr.s else -1) * tr.direction
            if ghost_travel_sign * (lead_s - st.ghost_s) > 0:
                d_lead = (lead_s - view_s) * tr.direction
                if 1.0 < d_lead < 40.0:
                    for side in (-0.4, +0.4):
                        pt_h = _proj_ghost(lead_s + side, 2.30)
                        if pt_h is None:
                            continue
                        hx, hy, hf = pt_h
                        hr = max(3.0, focal * 0.12 / max(d_lead, 0.35))
                        p.setPen(Qt.PenStyle.NoPen)
                        p.setBrush(QBrush(QColor(255, 220, 150,
                                                  int(200 * hf + 40))))
                        p.drawEllipse(QPointF(hx, hy), hr, hr * 0.7)

        # === Station platforms (only visible near a terminus) ===========
        # Both sides have a real platform — Perce-Neige cabins open on
        # both sides at the termini so passengers flow through. Draw a
        # proper 3D platform : top deck (light concrete), vertical face
        # (darker concrete with recessed lip shadow), tactile yellow edge
        # stripe, coping bar, and structural columns every 6 m supporting
        # the ceiling. Ceiling line above each platform hints at the
        # wider station vault.
        PLAT_LEN = 32.0
        PLAT_HEIGHT = 0.55       # above rail (m)
        PLAT_DEPTH = 3.2         # back from cabin side to wall (m)
        PLAT_Y_LIP = 0.06        # shadow lip thickness (m)
        # Platform centre on each terminus — aligned with the train's
        # STOPPED centre position (not flush with the bumper). Train
        # spans ± TRAIN_HALF around START_S / STOP_S, and the platform
        # matches that span, so when the driver looks forward at
        # departure there is still ~ BUMPER_CLEAR + a few m of platform
        # visible ahead rather than a blank black tunnel.
        plat_centres_s = [
            START_S,                        # Val Claret (lower)
            STOP_S,                         # Grande Motte (upper)
        ]

        def _plat_pt(s_slope: float, lateral: float, h: float
                     ) -> tuple[QPointF, float]:
            """Project a point on the platform at absolute slope s,
            lateral offset `lateral` m from the tunnel centreline
            (positive = right in driver frame), at height `h` m above
            rail. Uses plan-projection for correct curve handling."""
            ts2 = max(0.0, min(LENGTH, s_slope))
            fwd, lat, up = _proj_local(ts2)
            fwd = max(fwd, 0.35)
            cxp2 = eye_x + focal * lat / fwd
            cyp2 = eye_y - focal * up / fwd
            rail_y2 = cyp2 + focal * R_t * 0.75 / fwd
            px_per_m = focal / fwd
            x = cxp2 + lateral * px_per_m
            y = rail_y2 - h * px_per_m
            return QPointF(x, y), fwd

        for pc_s in plat_centres_s:
            d_centre = (pc_s - view_s) * tr.direction
            if d_centre > neon_max_depth + PLAT_LEN or d_centre < -PLAT_LEN:
                continue
            step_s = 1.0
            s_lo = pc_s - PLAT_LEN * 0.5
            s_hi = pc_s + PLAT_LEN * 0.5
            k_lo = int(math.ceil(s_lo / step_s))
            k_hi = int(math.floor(s_hi / step_s))
            # Platforms on BOTH sides. Edge must sit INSIDE the tunnel
            # bore radius (R_t = 1.55 m) otherwise it is hidden behind
            # the cylindrical wall render. Real stations widen to a
            # vault but we approximate by keeping the platform edge
            # just clear of the loading gauge, at 62 % of the bore
            # radius (matches the old single-side rendering).
            EDGE_M = R_t * 0.62       # ≈ 0.96 m lateral
            BACK_M = EDGE_M + 1.4     # back wall ~ 2.4 m lateral
            CEIL_M = R_t * 1.05       # vault above, just above bore top
            for side in (-1, +1):
                edge_top: list[QPointF] = []
                edge_bot: list[QPointF] = []
                back_top: list[QPointF] = []
                ceil_line: list[QPointF] = []
                for k in range(k_lo, k_hi + 1):
                    s_plat = k * step_s
                    dd = (s_plat - view_s) * tr.direction
                    if dd < 0.6 or dd > neon_max_depth + 1.0:
                        continue
                    et, _ = _plat_pt(s_plat, side * EDGE_M, PLAT_HEIGHT)
                    eb, _ = _plat_pt(s_plat, side * EDGE_M, 0.0)
                    bt, _ = _plat_pt(s_plat, side * BACK_M, PLAT_HEIGHT)
                    ce, _ = _plat_pt(s_plat, side * EDGE_M, CEIL_M)
                    edge_top.append(et)
                    edge_bot.append(eb)
                    back_top.append(bt)
                    ceil_line.append(ce)
                if len(edge_top) < 2:
                    continue
                # 1. Top deck (light concrete, slightly warm) — quad strip.
                p.setPen(Qt.PenStyle.NoPen)
                p.setBrush(QBrush(QColor(190, 186, 176)))
                for i in range(len(edge_top) - 1):
                    poly = QPolygonF([edge_top[i], back_top[i],
                                      back_top[i + 1], edge_top[i + 1]])
                    p.drawPolygon(poly)
                # 2. Vertical face (darker concrete) between edge_top and
                # rail level, with a narrow recessed lip above the rail.
                p.setBrush(QBrush(QColor(145, 140, 132)))
                face = QPainterPath()
                face.moveTo(edge_top[0])
                for pt in edge_top[1:]:
                    face.lineTo(pt)
                for pt in reversed(edge_bot):
                    face.lineTo(pt)
                face.closeSubpath()
                p.drawPath(face)
                # 3. Lip shadow along the bottom of the face.
                p.setPen(QPen(QColor(60, 58, 54), 1.8))
                for i in range(len(edge_bot) - 1):
                    p.drawLine(edge_bot[i], edge_bot[i + 1])
                # 4. Dark coping bar along the edge top (structural lip).
                p.setPen(QPen(QColor(70, 68, 62), 2.5))
                for i in range(len(edge_top) - 1):
                    p.drawLine(edge_top[i], edge_top[i + 1])
                # 5. Yellow tactile safety stripe set back ~25 cm.
                stripe_top: list[QPointF] = []
                for k in range(k_lo, k_hi + 1):
                    s_plat = k * step_s
                    dd = (s_plat - view_s) * tr.direction
                    if dd < 0.6 or dd > neon_max_depth + 1.0:
                        continue
                    st_pt, _ = _plat_pt(s_plat, side * (EDGE_M + 0.25),
                                        PLAT_HEIGHT + 0.002)
                    stripe_top.append(st_pt)
                p.setPen(QPen(QColor(245, 210, 55), 4.0))
                for i in range(len(stripe_top) - 1):
                    p.drawLine(stripe_top[i], stripe_top[i + 1])
                # 6. Structural columns every 6 m between platform back
                # and ceiling (hints at the widened station vault).
                col_step = 6.0
                col_k_lo = int(math.ceil(s_lo / col_step))
                col_k_hi = int(math.floor(s_hi / col_step))
                p.setPen(Qt.PenStyle.NoPen)
                for kc in range(col_k_lo, col_k_hi + 1):
                    s_col = kc * col_step
                    dd = (s_col - view_s) * tr.direction
                    if dd < 0.8 or dd > neon_max_depth:
                        continue
                    base, _ = _plat_pt(s_col, side * BACK_M, PLAT_HEIGHT)
                    top, _ = _plat_pt(s_col, side * BACK_M, CEIL_M)
                    col_w_px = max(2.5, focal * 0.30 / dd)
                    p.setBrush(QBrush(QColor(120, 115, 108)))
                    p.drawRect(QRectF(base.x() - col_w_px * 0.5,
                                      top.y(),
                                      col_w_px,
                                      base.y() - top.y()))
                # 7. Thin warm-white ceiling line just above platform
                # (station vault lighting hint).
                if len(ceil_line) >= 2:
                    p.setPen(QPen(QColor(220, 210, 175, 130), 2.0))
                    for i in range(len(ceil_line) - 1):
                        p.drawLine(ceil_line[i], ceil_line[i + 1])

        # === Tunnel-end bumper (butoir) ================================
        # Real Perce-Neige termini have a classic rail bumper : concrete
        # back-wall closes the tunnel, two heavy rail-mounted bumper
        # posts stand in front with red/white caution stripes, a cross
        # beam, and a flashing red warning beacon on top that's visible
        # from a long way out. Bumper is inside the lit station vault
        # (last 100 m) so it's always fully visible regardless of
        # headlights — override the tunnel max_depth here so the driver
        # can see it well before arrival.
        bumper_max = 180.0  # real sight distance in a lit station vault
        # Line-of-sight test : the driver's tangent ray from the eye
        # heads along the *local* slope. If the tunnel floor ahead
        # crests above that ray at any intermediate distance, the
        # bumper + beacon are hidden behind the hump and must NOT be
        # drawn (otherwise they appear to float through the mountain,
        # which is exactly the artefact reported on approach to the
        # Glacier terminus where the grade eases from 30 % to 6 %).
        los_clear = True
        if d_to_end > 0.0:
            alt0 = geom_at(view_s)[1]
            eps = 1.0  # metres, slope delta for finite-diff
            # Local tangent dalt/ds at the eye position (signed along
            # travel direction). Matches heading, not ground gradient.
            s_ahead_for_slope = max(0.0, min(LENGTH,
                                             view_s + eps * tr.direction))
            slope0 = ((geom_at(s_ahead_for_slope)[1] - alt0)
                      / max(abs(s_ahead_for_slope - view_s), 1e-3))
            # Sample intermediate floor altitudes ; if any crests above
            # the tangent line (by more than driver eye half-height ~ 1 m
            # to tolerate minor numerical ripple), mark occluded.
            n_samples = 30
            for i_s in range(1, n_samples):
                ds = d_to_end * i_s / n_samples
                s_i = view_s + ds * tr.direction
                alt_i = geom_at(s_i)[1]
                alt_tangent = alt0 + ds * slope0 * tr.direction
                # Ascending : occlusion if actual alt exceeds tangent.
                # Descending : symmetric — actual alt falls below tangent.
                if tr.direction > 0:
                    crest = alt_i - alt_tangent
                else:
                    crest = alt_tangent - alt_i
                if crest > 1.0:
                    los_clear = False
                    break
            # Horizontal curve occlusion : if the tunnel plan bends
            # enough between eye and bumper that the end point slides
            # outside the tunnel bore relative to the driver's straight
            # sightline, the bumper is hidden behind the sidewall. Use
            # the same local-frame projection as the rings.
            if los_clear:
                for i_s in range(1, n_samples):
                    ds = d_to_end * i_s / n_samples
                    s_i = view_s + ds * tr.direction
                    fwd_i, lat_i = _plan_local(s_i)
                    # Only consider points actually ahead of the eye.
                    if fwd_i <= 0.35:
                        continue
                    # If the tunnel centerline lateral offset exceeds
                    # the bore radius plus a margin, the bumper is
                    # behind a curved sidewall.
                    if abs(lat_i) > R_t * 1.0:
                        los_clear = False
                        break
        if los_clear and 0.0 < d_to_end <= bumper_max:
            dE = d_to_end
            cxE, cyE, rE, _tsE, _nfE = _ring_xyr(dE)
            # Fully opaque wall — a concrete barrier doesn't fade with
            # distance the way suspended dust does.
            p.setPen(Qt.PenStyle.NoPen)
            p.setBrush(QBrush(QColor(88, 82, 74)))
            p.drawEllipse(QPointF(cxE, cyE), rE * 0.98, rE * 0.98)
            # Darker base shadow.
            p.setBrush(QBrush(QColor(32, 30, 28)))
            rail_yE = cyE + rE * 0.75
            p.drawRect(QRectF(cxE - rE * 0.55, rail_yE - rE * 0.04,
                              rE * 1.10, rE * 0.08))
            # Posts — bigger + zebra stripes (real OSJD / UIC pattern).
            post_h_px = focal * 1.20 / max(dE, 0.35)
            post_w_px = max(3.0, focal * 0.25 / max(dE, 0.35))
            gauge_px_E = rE * 0.35
            for side in (-1, +1):
                px_c = cxE + side * gauge_px_E
                # Red base
                p.setBrush(QBrush(QColor(215, 40, 40)))
                p.drawRect(QRectF(px_c - post_w_px * 0.5,
                                  rail_yE - post_h_px,
                                  post_w_px, post_h_px))
                # Five-band zebra (red/white alternating, 45° hint by
                # offsetting bands at slight slant not worth at pixel
                # scale — keep horizontal).
                p.setBrush(QBrush(QColor(240, 235, 225)))
                for k_band in (0.15, 0.45, 0.75):
                    p.drawRect(QRectF(px_c - post_w_px * 0.5,
                                      rail_yE - post_h_px * (1.0 - k_band),
                                      post_w_px, post_h_px * 0.10))
            # Cross-beam linking the two posts at ~0.8 m above rail
            beam_y = rail_yE - focal * 0.80 / max(dE, 0.35)
            beam_h = max(2.0, focal * 0.15 / max(dE, 0.35))
            p.setBrush(QBrush(QColor(60, 55, 50)))
            p.drawRect(QRectF(cxE - gauge_px_E, beam_y - beam_h * 0.5,
                              gauge_px_E * 2, beam_h))
            # Red flashing warning beacon on top centre of the cross-beam.
            # 1 Hz sine flash so it's catches the eye at long range.
            flash = 0.5 + 0.5 * math.sin(self._tunnel_scroll * 2.0 * math.pi
                                          / max(12.0, 1.0))
            beac_y = beam_y - max(4.0, focal * 0.40 / max(dE, 0.35))
            beac_r = max(3.0, focal * 0.18 / max(dE, 0.35))
            glow_r = beac_r * (2.5 + 1.2 * flash)
            # Outer halo
            p.setBrush(QBrush(QColor(255, 40, 40,
                                     int(90 + 120 * flash))))
            p.drawEllipse(QPointF(cxE, beac_y), glow_r, glow_r)
            # Bright core
            p.setBrush(QBrush(QColor(255, 120, 100,
                                     int(200 + 55 * flash))))
            p.drawEllipse(QPointF(cxE, beac_y), beac_r, beac_r)
            # "STOP" label visible from far (scaled with distance).
            if dE < 80.0:
                label_h = max(7.0, focal * 0.40 / max(dE, 1.0))
                f_stop = p.font()
                f_stop.setPixelSize(int(label_h))
                f_stop.setBold(True)
                p.setFont(f_stop)
                p.setPen(QPen(QColor(245, 230, 120), 1))
                p.drawText(QRectF(cxE - gauge_px_E,
                                  beam_y - label_h * 1.6,
                                  gauge_px_E * 2, label_h * 1.3),
                           int(Qt.AlignmentFlag.AlignCenter),
                           "STOP")

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
        if half_d < cable_r * 1.01:
            return
        alpha = math.acos(max(-1.0, min(1.0, cable_r / half_d)))
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
        # each clickable control. .clear() reuses the list (no realloc).
        self._hit_zones.clear()
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
        # Live cable elongation — Hooke's law on the Fatzer 52 mm rope.
        # A = π·(0.052)² / 4 ≈ 2.12e-3 m²,  E ≈ 105 GPa (locked coil).
        # The loaded span is the slope length between the main train and
        # the bull wheel at the top station.
        cable_len = max(50.0, LENGTH - tr.s if tr.direction > 0 else tr.s)
        stretch_m = (tr.tension_dan_disp * 10.0 * cable_len) / (2.12e-3 * 1.05e11)
        # Tucked inside the gauge's bottom rim (was overlapping the
        # brake bar's "URG!" / % text just below the gauge).
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.setFont(QFont("Consolas", 8))
        p.drawText(
            QRectF(ten_rect.x(), ten_rect.y() + ten_rect.height() - 14,
                   ten_rect.width(), 11),
            int(Qt.AlignmentFlag.AlignHCenter),
            T(f"stretch {stretch_m:.2f} m",
              f"allong. {stretch_m:.2f} m"),
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
        # Distance travelled from the driver's own departure terminus (not
        # raw slope-s which starts at 26 m because of bumper clearance +
        # train half-length). Direction-aware so the readout counts UP
        # from 0 to the effective travel length in both climbing and
        # descending trips.
        # The real cockpit counter shows the full 3474 m slope length at
        # arrival, not the 3422 m between train-centre start and stop —
        # it measures the tunnel itself, not the usable travel span. We
        # rescale so the readout runs from 0 to LENGTH exactly.
        usable = STOP_S - START_S
        if tr.direction > 0:
            raw = max(0.0, tr.s - START_S)
            alt_start = geom_at(START_S)[1]
            alt_end = geom_at(STOP_S)[1]
        else:
            raw = max(0.0, STOP_S - tr.s)
            alt_start = geom_at(STOP_S)[1]
            alt_end = geom_at(START_S)[1]
        travel_total_m = LENGTH
        travel_done_m = min(LENGTH, raw * LENGTH / usable)
        alt_total = alt_end - alt_start               # +921 climb / −921 down
        alt_done = cabin_y_m - alt_start               # same sign as alt_total
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
             f"{travel_done_m:6.1f} / {travel_total_m:.0f} m"),
            (T("Elevation", "Dénivelé"),
             f"{alt_done:+5.1f} / {alt_total:+.0f} m"),
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

    # ----- trip log viewer -------------------------------------------------

    def _open_trip_log_viewer(self) -> None:
        """Pop a modal dialog listing trips + daily stats from
        exploitation.db. Accessed with F5 or from the Help menu."""
        dlg = QDialog(self)
        dlg.setWindowTitle(T("Auto-exploitation — trip log",
                             "Exploitation auto — journal des trajets"))
        dlg.resize(900, 560)
        lay = QVBoxLayout(dlg)
        tabs = QTabWidget(dlg)
        lay.addWidget(tabs)

        # ---- Trips tab -------------------------------------------------
        trips_tbl = QTableWidget(0, 9, dlg)
        trips_tbl.setHorizontalHeaderLabels([
            T("Day", "Jour"),
            T("Depart", "Départ"),
            T("Arrival", "Arrivée"),
            T("Dir", "Sens"),
            T("Pax", "Pax"),
            T("Cruise m/s", "Vitesse m/s"),
            T("Distance m", "Distance m"),
            T("Duration s", "Durée s"),
            T("Incidents", "Incidents"),
        ])
        trips_tbl.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.ResizeToContents)
        trips_tbl.verticalHeader().setVisible(False)
        tabs.addTab(trips_tbl,
                    T("Trips (last 100)", "Trajets (100 derniers)"))

        rows = self.auto_ops._log.read_recent_trips(100)
        trips_tbl.setRowCount(len(rows))
        for i, r in enumerate(rows):
            dep = r["depart_ts"].replace("T", " ")[:19]
            arr = r["arrival_ts"].replace("T", " ")[:19]
            dir_s = ("↑" if r["direction"] > 0 else "↓")
            vals = [
                r["day"], dep, arr, dir_s, str(r["pax"]),
                f"{r['cruise_m_s']:.2f}",
                f"{r['distance_m']:.0f}",
                f"{r['duration_s']:.1f}",
                str(r["incidents"]),
            ]
            for j, v in enumerate(vals):
                trips_tbl.setItem(i, j, QTableWidgetItem(v))

        # ---- Daily tab -------------------------------------------------
        daily_tbl = QTableWidget(0, 4, dlg)
        daily_tbl.setHorizontalHeaderLabels([
            T("Day", "Jour"),
            T("Trips", "Trajets"),
            T("Pax", "Pax"),
            T("Distance km", "Distance km"),
        ])
        daily_tbl.horizontalHeader().setSectionResizeMode(
            QHeaderView.ResizeMode.ResizeToContents)
        daily_tbl.verticalHeader().setVisible(False)
        tabs.addTab(daily_tbl,
                    T("Daily stats", "Stats journalières"))

        drows = self.auto_ops._log.read_recent_daily(60)
        daily_tbl.setRowCount(len(drows))
        for i, r in enumerate(drows):
            vals = [
                r["day"], str(r["trips"]), str(r["pax"]),
                f"{r['distance_m'] / 1000.0:.2f}",
            ]
            for j, v in enumerate(vals):
                daily_tbl.setItem(i, j, QTableWidgetItem(v))

        # ---- Footer ----------------------------------------------------
        foot = QHBoxLayout()
        db_lbl = QLabel(
            T("Database: ", "Base de données : ")
            + str(self.auto_ops._log.db_path))
        db_lbl.setStyleSheet("color:#888")
        foot.addWidget(db_lbl, 1)
        close_btn = QPushButton(T("Close", "Fermer"))
        close_btn.clicked.connect(dlg.accept)
        foot.addWidget(close_btn)
        lay.addLayout(foot)

        dlg.exec()

    # ----- auto-ops side panel --------------------------------------------

    def _draw_auto_ops_panel(self, p: QPainter, rect: QRectF) -> None:
        """Compact side panel at the bottom-right that mirrors the
        auto-exploitation state : wall clock, published hours, current
        phase, peak/off-peak band, per-day counters. Warm amber palette
        so it reads as "control room" next to the neutral event log."""
        ao = self.auto_ops
        now = datetime.now()
        peak_now = ao._is_peak(now)
        in_hrs = ao._within_operating_hours(now)
        forced = ao.force_any_hours

        # --- Frame -------------------------------------------------------
        bg = QLinearGradient(rect.x(), rect.y(),
                             rect.x(), rect.y() + rect.height())
        bg.setColorAt(0.0, QColor(42, 30, 14, 235))
        bg.setColorAt(1.0, QColor(22, 16, 8, 235))
        p.setBrush(QBrush(bg))
        border_col = (QColor(120, 220, 120) if in_hrs
                      else QColor(220, 130, 60))
        p.setPen(QPen(border_col, 2))
        p.drawRoundedRect(rect, 10, 10)

        # --- Header ------------------------------------------------------
        hdr = QRectF(rect.x(), rect.y(), rect.width(), 26)
        p.setBrush(QBrush(QColor(80, 55, 20, 220)))
        p.setPen(Qt.PenStyle.NoPen)
        path = QPainterPath()
        path.moveTo(rect.x(), rect.y() + 10)
        path.arcTo(rect.x(), rect.y(), 20, 20, 180, -90)
        path.lineTo(rect.x() + rect.width() - 10, rect.y())
        path.arcTo(rect.x() + rect.width() - 20, rect.y(),
                   20, 20, 90, -90)
        path.lineTo(rect.x() + rect.width(), rect.y() + 26)
        path.lineTo(rect.x(), rect.y() + 26)
        path.closeSubpath()
        p.drawPath(path)
        p.setPen(QPen(QColor(255, 220, 140)))
        p.setFont(QFont("Segoe UI", 11, QFont.Weight.Bold))
        p.drawText(QRectF(rect.x() + 10, rect.y() + 4,
                          rect.width() - 20, 18),
                   int(Qt.AlignmentFlag.AlignLeft),
                   T("Auto-exploitation", "Exploitation auto"))
        # Status pill on the right of the header
        pill_w = 58
        pill = QRectF(rect.x() + rect.width() - pill_w - 8,
                      rect.y() + 6, pill_w, 14)
        if forced:
            pill_col = QColor(200, 120, 255)
            pill_txt = "24/7"
        elif in_hrs:
            pill_col = QColor(90, 200, 120)
            pill_txt = T("OPEN", "OUVERT")
        else:
            pill_col = QColor(180, 90, 60)
            pill_txt = T("CLOSED", "FERMÉ")
        p.setBrush(QBrush(pill_col))
        p.setPen(QPen(QColor(10, 8, 4), 1))
        p.drawRoundedRect(pill, 6, 6)
        p.setPen(QPen(QColor(10, 8, 4)))
        p.setFont(QFont("Consolas", 8, QFont.Weight.Bold))
        p.drawText(pill, int(Qt.AlignmentFlag.AlignCenter), pill_txt)

        # --- Rows --------------------------------------------------------
        km = ao.day_distance_m / 1000.0
        sched = (f"{ao.open_h:02d}:{ao.open_m:02d}"
                 f"→{ao.close_h:02d}:{ao.close_m:02d}")
        # Phase text with countdown when the state machine is waiting
        # on a fixed timer — boarding dwell is the big one (20 s), but
        # DOORS_OPENING also has a 3 s wait. Showing "BOARDING 12/20 s"
        # is the difference between "stuck" and "almost there".
        phase_labels = {
            ao.PHASE_IDLE:          T("IDLE",          "INACTIF"),
            ao.PHASE_PRE_OPEN:      T("PRE-OPEN",      "PRÉ-OUVERTURE"),
            ao.PHASE_BOARDING:      T("BOARDING",      "EMBARQUEMENT"),
            ao.PHASE_CLOSING:       T("CLOSING",       "FERMETURE"),
            ao.PHASE_READY_WAIT:    T("READY-WAIT",    "ATTENTE PRÊT"),
            ao.PHASE_DEPARTING:     T("DEPARTING",     "DÉPART"),
            ao.PHASE_TRANSIT:       T("TRANSIT",       "EN VOIE"),
            ao.PHASE_ARRIVING:      T("ARRIVING",      "ARRIVÉE"),
            ao.PHASE_DOORS_OPENING: T("DOORS OPENING", "OUVERTURE PORTES"),
        }
        phase_txt = phase_labels.get(ao.phase, ao.phase)
        if ao.phase == ao.PHASE_BOARDING:
            remain = max(0.0, ao.station_dwell_s - ao.phase_t)
            phase_txt = f"{phase_txt}  {int(remain):>2d} s"
        elif ao.phase == ao.PHASE_DOORS_OPENING:
            remain = max(0.0, 3.0 - ao.phase_t)
            phase_txt = f"{phase_txt}  {remain:.1f} s"
        rows = [
            (T("Clock",    "Heure"),    now.strftime("%H:%M:%S")),
            (T("Schedule", "Horaires"), sched),
            (T("Phase",    "Phase"),    phase_txt),
            (T("Rush",     "Affluence"),
             T("peak 12 m/s", "pointe 12 m/s") if peak_now
             else T("off-peak 10.3 m/s", "creuse 10.3 m/s")),
            (T("Trips",    "Trajets"),  f"{ao.day_trips}"),
            (T("Pax",      "Pax"),      f"{ao.day_pax}"),
            (T("Distance", "Distance"), f"{km:.2f} km"),
        ]
        p.setFont(QFont("Consolas", 10))
        row_y = rect.y() + 32
        for k_lbl, v_lbl in rows:
            p.setPen(QPen(QColor(220, 180, 120)))
            p.drawText(int(rect.x() + 12), int(row_y + 12), k_lbl)
            p.setPen(QPen(QColor(255, 235, 190)))
            p.drawText(int(rect.x() + 120), int(row_y + 12), v_lbl)
            row_y += 16

        # --- Footer hint -------------------------------------------------
        p.setPen(QPen(QColor(200, 170, 110, 200)))
        p.setFont(QFont("Segoe UI", 8))
        foot = QRectF(rect.x() + 10,
                      rect.y() + rect.height() - 34,
                      rect.width() - 20, 28)
        hint = T(
            "Shift+X : 24/7   •   F5 : trip log   •   X : stop",
            "Maj+X : 24/7   •   F5 : journal   •   X : stop",
        )
        p.drawText(foot,
                   int(Qt.AlignmentFlag.AlignLeft
                       | Qt.AlignmentFlag.AlignVCenter),
                   hint)

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
        """Overlay panel listing every on-board announcement, with a
        language selector at the top so the driver can play any of the
        five bundled translations (FR / EN / IT / DE / ES) of any message.
        """
        panel_w = 540
        panel_h = 480
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
            T("Click a language, then a message — Esc / F2 to close",
              "Choisir une langue puis un message — Esc / F2 pour fermer"),
        )
        # STOP button — aborts the announcement currently playing (and
        # clears the queue). X was repurposed for auto-exploitation so
        # the STOP hotkey is now Backspace.
        stop_rect = QRectF(x + panel_w - 166, y + 30, 150, 22)
        self._draw_touch_button(
            p, stop_rect,
            T("⏹ STOP [⌫]", "⏹ STOP [⌫]"),
            QColor(220, 120, 80), font_pt=9,
        )
        self._hit_zones.append(
            (stop_rect, int(Qt.Key.Key_Backspace), False))
        # Language selector row — 5 clickable pills, the current one
        # highlighted. Pressing F/E/I/G/S also switches.
        st_for_lang = self.state
        lang_row_y = y + 58
        p.setFont(QFont("Segoe UI", 9))
        p.setPen(QPen(COLOR_TEXT_DIM))
        p.drawText(QPointF(x + 16, lang_row_y + 14),
                   T("Language :", "Langue :"))
        lang_entries = [
            ("FR", "fr", Qt.Key.Key_F),
            ("EN", "en", Qt.Key.Key_E),
            ("IT", "it", Qt.Key.Key_I),
            ("DE", "de", Qt.Key.Key_G),
            ("ES", "es", Qt.Key.Key_S),
        ]
        pill_w = 52
        pill_h = 22
        lx = x + 96
        for lbl, code, hk in lang_entries:
            rect = QRectF(lx, lang_row_y, pill_w, pill_h)
            selected = (st_for_lang.ann_lang == code)
            if selected:
                col = QColor(80, 220, 140)
                text_col = QColor(15, 25, 15)
            else:
                col = QColor(50, 70, 100)
                text_col = COLOR_TEXT
            p.setBrush(QBrush(col))
            p.setPen(QPen(QColor(120, 170, 220), 1))
            p.drawRoundedRect(rect, 6, 6)
            p.setPen(QPen(text_col))
            p.setFont(QFont("Consolas", 10, QFont.Weight.Bold))
            p.drawText(rect, int(Qt.AlignmentFlag.AlignCenter),
                       f"{lbl} [{chr(hk).upper()}]")
            self._hit_zones.append((rect, int(hk), False))
            lx += pill_w + 8
        # Entries — each row is also a click target that triggers the
        # announcement exactly like pressing its hotkey.
        p.setFont(QFont("Consolas", 11))
        list_top = y + 92
        for i, (entry_k, group, label, en, fr) in enumerate(ANNOUNCEMENT_MENU):
            row_y = list_top + i * 22
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
        box_h = 720
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
                ("X", T("auto-exploitation on / off (takes over any time)",
                        "exploitation auto on / off (reprend à tout moment)")),
                (T("Shift+X", "Maj+X"),
                 T("24/7 override : ignore published hours",
                   "mode 24/7 : ignorer les horaires officiels")),
                ("N", T("sound mute / unmute",
                        "couper / remettre le son")),
                (T("Backspace", "Retour arrière"),
                 T("abort current announcement",
                   "couper l'annonce en cours")),
            ]),
            (T("System", "Système"), [
                ("P / Esc", T("pause / resume", "pause / reprise")),
                ("M", T("mode : normal / challenge / faults",
                        "mode : normal / défi / pannes")),
                ("F", T("fault picker (only in faults mode)",
                        "sélecteur de panne (mode pannes seulement)")),
                ("L", T("language FR / EN", "langue FR / EN")),
                ("F1", T("toggle this help", "ouvrir/fermer cette aide")),
                ("F2", T("announcement console",
                         "console d'annonces")),
                ("F3", T("real machine info + links",
                         "infos machine réelle + liens")),
                ("F4", T("cabin / side view toggle",
                         "vue cabine / vue latérale")),
                ("F5", T("auto-exploitation trip log",
                         "journal des trajets auto")),
                ("F6", T("download PDF manual + theory guide",
                         "télécharger manuel PDF + guide théorique")),
                ("+ / −  /  0", T("side-view zoom in/out / reset",
                                  "zoom vue latérale +/− / reset")),
                (T("Mouse wheel", "Molette souris"),
                 T("zoom side-view", "zoom vue latérale")),
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

        # Tips box at the bottom — sized to fit all 9 tips without overflow
        tips_box_h = 200
        tips_y = box.y() + box_h - tips_box_h - 26
        tips_box = QRectF(box.x() + 30, tips_y, box_w - 60, tips_box_h)
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
            T("• Any latched stop (3/4/dead-man/fault) in tunnel suspends the trip : release + READY + DEPART to resume",
              "• Tout arrêt verrouillé (3/4/veille/panne) en tunnel suspend le trajet : relâcher + PRÊT + DÉPART pour repartir"),
            T("• X activates auto-mode from any state (terminus, mid-trip, mid-tunnel stop) — Shift+X for 24/7",
              "• X active le mode auto depuis n'importe où (terminus, en route, arrêt tunnel) — Maj+X pour 24/7"),
            T("• Hover any cockpit button with the mouse — bilingual tooltips describe every control",
              "• Survolez un bouton du cockpit à la souris — les tooltips bilingues décrivent chaque commande"),
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
                   T("Simulation © 2026 ARP273-ROSE — data from public sources",
                     "Simulation © 2026 ARP273-ROSE — données de sources publiques"))

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
        ico = _resource_path("logo.ico")
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

    def closeEvent(self, ev) -> None:  # noqa: N802
        try:
            self.game.auto_ops._log.checkpoint_truncate()
        except Exception:
            pass
        super().closeEvent(ev)

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
            f"Version <b>{info.version}</b> is available.<br><br>"
            "Install now?",
            f"La version <b>{info.version}</b> est disponible.<br><br>"
            "Installer maintenant ?")
        msg.setText(text)
        if info.body:
            msg.setDetailedText(info.body[:4000])
        btn_ok = msg.addButton(
            self._tr("Install", "Installer"),
            QMessageBox.ButtonRole.AcceptRole)
        msg.addButton(
            self._tr("Later", "Plus tard"),
            QMessageBox.ButtonRole.RejectRole)
        msg.exec()
        if msg.clickedButton() is not btn_ok:
            return
        try:
            autoupdate.download_and_install(info, _writable_dir())
        except Exception as e:
            QMessageBox.critical(
                self,
                self._tr("Update failed", "Échec de la mise à jour"),
                self._tr(f"Error : {e}", f"Erreur : {e}"))
            return
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
        project_dir = _writable_dir()
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
        bugreport.install_crash_handler(_writable_dir(), VERSION)
    except Exception:
        pass
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
