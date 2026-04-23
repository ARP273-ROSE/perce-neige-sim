![Perce-Neige Simulator](logo.png)

# Perce-Neige Simulator

![Python](https://img.shields.io/badge/python-3.9+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)

**Drive the longest funicular in France — 3 474 m of underground tunnel from Val Claret (2 111 m) to the Grande Motte glacier (3 032 m) in Tignes, France.**

An accurate PyQt6 simulation of the *Perce-Neige* underground funicular (built 1989–1991, opened 14 April 1993 by Von Roll / CFD). Distant descendant of the author's 2006 TI-84 `FUNIC` program — same spirit, real physics, proper graphics.

---

## Features

### Real-world fidelity
- **Slope length** 3 474 m (cockpit counter reference), **vertical drop** 921 m, altitudes 2 111 m → 3 032 m
- **Gradient profile** from 8 % (gentle square-section start) to 30 % (steepest sustained middle), eases to 6 % at the upper square-section platform — calibrated directly against the real cockpit video
- **Square cut-and-cover** at both ends (s < 257 m and s > 3 420 m), **round TBM bore** through the middle — exact transition distances read from the on-board counter
- **Passing loop** s=1 601 → 1 823 m, curves at s=1 297 → 1 541 m and s=1 884 → 2 369 m
- **Speed** capped at 12 m/s (43.2 km/h) — the Von Roll regulator limit. In the reference cockpit video the driver cruises at ~10.1 m/s (speed_cmd ≈ 84 %), giving the real 7 min 54 s Val Claret → Grande Motte trip time ; you can push to full 12 m/s in the sim.
- **Train** : two coupled cylindrical cars, ∅ 3.60 m, 32 t empty, up to 334 passengers (58.8 t max)
- **Motors** 3 × 800 kW DC at the upper drive station, below the *Panoramic* restaurant
- **Cable** 52 mm Fatzer, nominal 22 500 daN, breaking 191 200 daN

### Physics
- Variable-gradient integration with position-dependent slope
- Mass-aware gravity, rolling resistance, motor force with `P = F·v` envelope
- Normal brake (2.5 m/s²) and emergency brake (5 m/s²)
- Live **cable tension** estimate with nominal / warning / breaking bands
- **Comfort score** via jerk integration
- **Energy score** in kWh
- **Honest real-time integration** : every physics step advances by the
  actual wall-clock delta measured via `time.monotonic()` (clamped to
  [1 ms, 100 ms]). Earlier builds used a hardcoded 16 ms assumption —
  under Windows timer granularity and typical render load the real
  frame cost reaches 20–30 ms, so the sim used to drift down to ~48 %
  of real time. Now 12 m/s on the speedometer moves the train 12 m per
  real second

### Interface
- Faux-3D side view with yellow cylindrical cabins, coupled cars, windowed body, highlight strip, rounded end caps
- Animated **drive station cutaway** at the upper platform — three DC motors feeding a rotating drive pulley, cable visibly wrapping
- **Mini-map** across the top showing both trains' positions and the passing loop
- **Analog speedometer** in m/s (with km/h sub-label) + **tension gauge** in daN, both with green/yellow/red bands
- **Bar gauges** for speed command (% of V_MAX), brake, and motor power
- **Realistic cockpit button panel** — illuminated push-buttons for electric stop, emergency stop (red mushroom), dead-man vigilance, headlights, cabin lights, horn, doors, autopilot and sound
- Warning lights: doors, brake, cable, fault, speed limit
- **Scrolling snow** across the view, cosmic gradient sky
- **Event log** with FR/EN messages
- Fully **bilingual FR / EN**, auto-detected from system locale (toggle with `L`)
- **Bilingual hover tooltips** on every cockpit button and clickable HUD zone — describe the action, the keyboard shortcut and the physical semantics (e.g. 2.5 m/s² service brake vs. 5 m/s² rail brakes). Text flips instantly when you toggle the language

### Realistic driving regulator
- The driver sets a **speed command** (percentage of V_MAX = 12 m/s) with `↑` / `↓` — the regulator smoothly tracks it with a realistic accel/decel envelope, exactly like the real Von Roll speed programmer
- **Programmed station approach** : the envelope automatically clamps the setpoint so the train always has enough distance to reach the creep zone before the platform
- **Creep zone** : when the front is 20 m before the platform, the train crawls at 1 m/s through the 20 m approach and the 35 m platform, stopping flush at the platform end
- **Counterweight wagon** : the descending train *is* the counterweight — mechanically linked by the cable. In real operation the down-going wagon is almost always empty because skiers go *up* by funicular and come *back down on skis*; only the summer glacier season sees a handful of passengers coming down. The ascending train therefore has to lift close to a full load of net imbalance
- **Cable elasticity rebound** : after the main train stops at the upper station, the counterweight wagon at Val Claret creeps up ~1.2 m over 2 seconds because the long cable relaxes (motor is at the top)
- **Dead-man vigilance** : the driver must touch a control at least once every 20 s, otherwise the system triggers an automatic electric stop (press `G` to acknowledge)

### Cabin first-person view (F4)
> **NEW in v1.10.0** — F4 now launches the **standalone Godot 3D viewer**
> in a separate window (bundled binary, nothing to install). The Python
> sim drives the physics over UDP at 60 Hz and the 3D viewer renders the
> real cockpit perspective with full Phase 4-10 features : tunnel TBM
> with chamber, Abt switch passing loop, machine room, animated cable,
> 3D dashboard, animated passengers, voice announcements. If the bundled
> binary isn't found (custom build), F4 falls back silently to the
> built-in procedural cabin view documented below.

#### Built-in procedural cabin view (fallback)
- **Real pinhole-camera perspective** — `screen_r = focal · R_tunnel / d`
  with a 72° horizontal FOV, matching the wide driver windshield and the
  tight 3.1 m TBM bore
- TBM segment pitch 1.5 m : at 12 m/s, 8 rings stream past every second,
  with the correct 1/d size falloff that makes near walls fill the view
- **Wall fluorescents** : long horizontal tubes (~1.6 m, spaced 12 m)
  on the left wall while climbing / right wall while descending —
  layered halo + mid-glow + bright core, exactly like the HD footage
- **Headlights gate visibility** : off → you barely see a few metres of
  concrete and only the wall neons as beacons ; on → the beam reaches
  ~260 m with Beer-Lambert exponential falloff, far enough to actually
  *see* the tunnel curving up or down through the gradient breaks
- Sleepers drawn one per ring with a central cable-guide bolt, rails +
  cable guide connect smoothly between consecutive rings
- Correct handling of curves (lateral offset `½·focal·κ·d`) and passing
  loop double-bore on the opposite wall
- **Exact 3D vertical curvature** — every tunnel ring, wall panel,
  platform edge and ghost-wagon vertex is projected through a true
  pinhole camera frame (forward + altitude difference rotated by the
  local slope pitch), so a gradient break ahead is rendered with the
  same geometric fidelity as a horizontal turn
- **Continuous floor / ceiling / arch envelope polylines** drawn across
  successive rings give vertical curvature the same visual clarity that
  rail continuity gives to horizontal turns

### Side-profile view (default)
- **Researched gradient profile** — 15 % at Val Claret ramp-up, 30 %
  sustained in the mid-tunnel main climb, 12 % easing out onto the
  Grande Motte glacier platform, pronounced break at ~3 180 m
- **Mouse-wheel zoom** (or `+` / `-` / `0` to reset) with an aspect-ratio
  lock : the visual slope angle is exactly the real slope angle at any
  zoom level — zooming reveals more detail without distorting steepness
- **Distance + elevation readout** : `travel / total m` and `Δalt / total m`
  are trip-relative (0 at departure platform, full span at arrival),
  direction-aware for descending trips

### Game modes
- **Normal** — just drive a trip
- **Challenge** — optimise time + comfort + energy
- **Faults** — 15 incident types, sourced from real documented funicular
  failures (STRMTG RM5, BEA-TT Glória Lisboa 2025, Kaprun 2000, Carmelit,
  Perce-Neige 2008 outage, Montmartre 2006, Sassi-Superga, M2 Lausanne).
  Random weighted scheduler by default; press **F** to open the manual
  picker dialog (choose a specific fault or toggle auto/manual scheduler)

### Fault catalogue (press F in Faults mode)
Common operational faults : `tension`, `door`, `thermal`, `fire`,
`wet_rail`, `motor_degraded` (M1/M2/M3 named, Sassi-Superga precedent),
`slack`, `aux_power` (Perce-Neige 2008 pattern), `parking_stuck`.
Severe / catastrophic : `cable_rupture` (Glória Lisboa 2025 class),
`service_brake_fail` (Glória double-failure), `flood_tunnel`,
`comms_loss` (Kaprun lesson), `switch_abt_fault` (Abt crossing interlock),
`fire_vent_fail` (fire + désenfumage down, Kaprun class).

Physics realism : overspeed cascade in three stages per EP0392938A1
POMA + STRMTG RM5 — +10 % service brake, +12 % secondary emergency,
+20 % mechanical Belleville parachute centrifugal trip. Cable cumulative
fatigue counter (Palmgren-Miner, ISO 4309 / DIN EN 12927-6) tracks
round-trip cycles and `cable_wear_pct` for each trip.

### Fault realism — recovery state machine (v1.9.0 / v1.9.1)
Faults are now classified by **severity** and have realistic recovery paths :

- **Advisory** (`tension`, `wet_rail`, `slack`, `comms_loss`) — dashboard
  warning only, no operational impact, auto-clears
- **Operational** (`door`, `thermal`, `motor_degraded`, `flood_tunnel`) —
  degraded mode (speed cap, power derate), trip continues, auto-clears on
  timer
- **Stopping** (`aux_power`, `parking_stuck`, `switch_abt_fault`) — train
  must stop, then **READY (V) + DEPART (Z)** required to resume — releasing
  the brake alone never auto-restarts the trip
- **Catastrophic** (`cable_rupture`, `fire`, `fire_vent_fail`,
  `service_brake_fail`) — trip is **TERMINATED**. The phase machine runs :
  `active` → `intervention_called` (tech_incident PA) → `evacuating`
  (dim_light + evac PA, cabin lights dimmed, passengers evacuated) →
  `out_of_service`. READY/DEPART are blocked permanently — **press R for a
  new trip** from the menu sequence (the only way out of a Glória / Kaprun
  class event)

A persistent **on-screen panel** (top-left of the world view) tells the
driver in real time : what's happening, what to do, what's blocked, and —
for catastrophic faults — a 5-stage phase indicator and the explicit
"Press R for new trip" hint once evacuation has begun.

**v1.9.1 patch** — announcement queue hardening : every PA in the
catastrophic chain (`tech_incident` → `dim_light` → `evac`) now waits
for the previous one to fully finish before the next one fires, so no
message is ever cut off. The emergency brake squeal (`brake_noise`)
no longer loops forever once the cabin is parked out of service.

### Documentation download (F6)
Press **F6** to open the docs dialog : downloads the latest
`manuel_perce_neige.pdf` (user manual) and `guide_theorique.pdf`
(theory guide with full formula derivations, regulatory sources, audio
calibration validation) from the GitHub repo into your Downloads folder
and opens them in the default PDF viewer — handy when running the
standalone EXE which doesn't bundle the PDFs.

### Auto-update (GitHub)
- Background check on startup (3 s after launch) — silent unless an
  update is available
- Manual check via **Help → Check for updates**
- Downloads the release zipball from GitHub, validates size, rejects
  path-traversal and symlinks, copies a whitelist of files and restarts
- User data (venv, CLAUDE.md, `.git`, `crash_reports/`) is never touched

### Bug reports (anonymous)
- `sys.excepthook` writes an anonymized JSON crash report into
  `crash_reports/` if the app ever crashes
- Next launch offers to open a **pre-filled GitHub issue** — paths and
  user names are stripped before anything leaves your machine
- Manual report via **Help → Report a bug** : form with description +
  steps ; opens the same pre-filled issue URL in your browser
- **No telemetry** : nothing is sent automatically, nothing contacts a
  server without your explicit click

### Real cabin ambient sound
- Two long loops extracted from the real 10-minute HD cabin recording :
  a 25 s slow/approach segment and a 60 s steady-cruise segment,
  loudness-matched and crossfaded live based on the train's current
  speed — stops sound like stops, cruise sounds like cruise, no more
  11-second clip heard on repeat
- Volume ceiling lifted to ~95 % so the tunnel rumble actually feels
  like being inside the car

### Auto-exploitation mode (ambient)
- Press `X` to hand the line over to the simulator : boarding,
  doors-close chime, trip, passing-loop crossing, arrival,
  turnaround — round after round, from the published opening time
  (08:45) to the last scheduled descent (16:45)
- **Activate from any state** : at a terminus auto-ops begins a new
  boarding cycle, mid-tunnel it takes over the current trip, and
  after an incident halt it pre-arms READY and fires the buzzer
  automatically — no need to be at a station to hand over
- **`Shift+X` : 24/7 override** — ignore the published opening hours
  and let the line run continuously (useful for ambient background
  play outside the ski season window)
- **Live side panel** (bottom-right, next to the event log) :
  wall-clock, schedule, current phase with countdown, peak/off-peak
  band, day counters (trips, pax, distance). Green border inside
  hours, orange outside, purple pill when 24/7 is armed. Phase
  labels localise fully — in French the panel reads *EMBARQUEMENT*,
  *FERMETURE*, *ATTENTE PRÊT*, *DÉPART*, *EN VOIE*, *ARRIVÉE*,
  *OUVERTURE PORTES*, *INACTIF* instead of the raw English state
  names
- **`F5` : trip log viewer** — opens a dialog with the last 100
  round-trips and the last 60 daily-stat rows straight from
  `exploitation.db`
- **Peak vs off-peak cruise** : 12 m/s during the morning-rush and
  late-afternoon return windows, 10.3 m/s off-peak — the regulator
  picks the setpoint from the real clock
- **Passenger load varies with time of day** : morning ascents are
  heavy (skiers going up), late-afternoon descents are heavy
  (skiers returning) — the load samples feed the mass-aware physics
  so the cable tension reflects a realistic day
- **Input lockout while auto is running** : cockpit buttons and most
  keys are masked (only `X`, `P`, `N`, `L`, `F1`–`F5`, `Backspace`,
  `Esc` pass through) so you can't accidentally fight the state
  machine
- **Exploitation log** in `exploitation.db` (SQLite, WAL) : every
  round-trip records departure/arrival timestamps, direction,
  passenger count, cruise speed, distance, duration and incident
  count. A `daily_stats` table keeps the running km/pax/trips for
  the current day
- Meant to be left running in the background : you hear the cabin
  ambient, the buzzers, the announcements, the crossing whoosh
  exactly like a real day on the line

### Abnormal-stop sequence (Von Roll safety-chain fidelity)
- Any latched stop engaged **while rolling in the tunnel** — manual
  electric stop (`3`), emergency stop (`4`), overspeed auto-trip,
  dead-man vigilance loss, or a service-stopping fault (door,
  thermal, motor degraded, aux power, parking drum stuck, fire)
  — now triggers the full real-world abnormal-stop protocol :
  1. READY / ghost-ready / departure buzzer cleared immediately
  2. Cabin decelerates to a stop under its own physics
  3. Once `|v| < 0.1 m/s` the **incident announcement** plays
     (`tech_incident`, or `dim_light + evac` for fire), not at the
     moment the button is pressed
  4. `trip_started` flips back to `False` (trip formally suspended)
  5. **Parking drum engages** — raising the speed setpoint no longer
     moves the cabin on its own
  6. Driver releases the latched stop, presses READY (triggers the
     "Remise en route" announcement), then DEPART (buzzer, drum
     releases, trip resumes)
- At the termini the sequence short-circuits : messages play
  instantly and the drum doesn't need engaging since the doors-open
  parking state already holds the cabin still
- Silent-advisory faults (cable tension, wet rail, slack cable) are
  unchanged — dashboard only, no PA, no forced stop

### Real on-board announcements
- Authentic recordings from the actual Perce-Neige cabins, bundled under
  `sons/Funiculaire perce neige/`
- Played automatically at the right moment : doors closing, welcome,
  minor/technical incident, 10 min stop, restart, evacuation, upstream
  passenger exit, dimmed lighting, brake noise, etc.
- 5 languages per message (FR / EN / IT / DE / ES) — the game picks the
  current UI language (FR or EN) and queues FR then EN like the real train.
- Press `N` at any time to mute / unmute.
- Press `F2` to open the manual announcement console : a 15-entry panel
  with hotkeys to trigger any message (doors closing, welcome, incident,
  evacuation, brake noise, …) on demand.

---

## Installation

**For everyone (recommended, no Python required)** — go to the [latest release](https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest), download **`PerceNeigeSimulator-windows.exe`** and double-click it. Done. The app updates itself automatically when a new version is published on GitHub.

### From source (developers)

Windows :
```cmd
launch.bat
```

Linux / macOS :
```bash
./launch.sh
```

Both launchers create a local venv outside the project folder, install PyQt6 + Pillow, and launch the game.

Manual install :
```bash
pip install -r requirements.txt
python perce_neige_sim.py
```

### Building the standalone executable yourself

```bash
pip install pyinstaller pillow
python make_logo.py
pyinstaller perce_neige.spec
# → dist/PerceNeigeSimulator(.exe)
```

A GitHub Actions workflow (`.github/workflows/build.yml`) builds the Windows `.exe` automatically and attaches it to every tagged release.

---

## Controls

**Driving**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `↑` / `W`        | Speed command + (raise setpoint %)                |
| `↓` / `S`        | Speed command − (lower setpoint %)                |
| `Space` / `B`    | Service brake (hold)                              |
| `Shift`          | Emergency brake (hold)                            |
| `3`              | **Electric stop** — latched service stop          |
| `4`              | **Emergency stop** — latched rail brakes          |
| `G`              | Dead-man vigilance acknowledge                    |

**Cockpit**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `H`              | Headlights on / off                               |
| `C`              | Cabin lights on / off (dims the ride)             |
| `K`              | Horn (hold)                                       |
| `D`              | Doors open / close (only at a stop)               |
| `A`              | Autopilot toggle (programmed run)                 |
| `X`              | Auto-exploitation on / off (full-service ambient) |
| `Shift+X`        | 24/7 override — ignore published opening hours    |
| `N`              | Mute / unmute on-board announcements              |
| `Backspace`      | Abort the running announcement                    |

**System**

| Key              | Action                                            |
|------------------|---------------------------------------------------|
| `P`              | Pause / resume                                    |
| `M`              | Cycle mode : Normal → Challenge → Faults          |
| `L`              | Language FR / EN                                  |
| `F1`             | Help overlay on / off                             |
| `F2`             | On-board announcement console (manual trigger)    |
| `F3`             | Real machine info overlay (specs + source links)  |
| `F5`             | Auto-exploitation trip log viewer                 |
| `R`              | New trip (after arrival)                          |
| `Enter`          | Start (from title screen)                         |
| `Esc`            | Pause / menu / quit                               |

---

## Specs used

Sourced from Wikipedia (FR + EN), `remontees-mecaniques.net`, and CFD's official page on the rolling stock :

| Property                  | Value             |
|---------------------------|-------------------|
| Length (along slope)      | 3 474 m           |
| Vertical drop             | 921 m             |
| Lower station             | Val Claret 2 111 m |
| Upper station             | Glacier 3 032 m   |
| Max gradient              | 30 %              |
| Max speed                 | 12 m/s (cruise ≈ 10.1 m/s) |
| Trains                    | 2 × 2 coupled cars |
| Capacity                  | 334 pax + 1 conductor |
| Empty / loaded mass       | 32.3 t / 58.8 t   |
| Motor power (total)       | 3 × 800 kW DC = 2 400 kW |
| Cable diameter            | 52 mm             |
| Cable nominal / breaking  | 22 500 / 191 200 daN |
| Tunnel diameter (min)     | 3.9 m             |
| Track gauge               | 1 200 mm          |
| Passing loop length       | ~200 m            |
| Built by                  | Von Roll / CFD    |
| Opened                    | 14 April 1993     |

---

## License

MIT. Author : ARP273-ROSE — 2006 TI-Basic original, 2026 PyQt6 port.
