# Sources used for Perce-Neige Simulator

This file lists every public source referenced during the technical
research, physics calibration and manual writing. It distinguishes
**directly verified** facts (published specs, observed cockpit video,
builder documentation) from **extrapolated** values (values that had to
be inferred from comparable Swiss / French tunnel funiculars because
the Perce-Neige originals were never publicly disclosed).

Honesty note: the research was carried out progressively across many
sessions — this document compiles everything that is cited or implicitly
relied upon in the code, the LaTeX manual and the research memory file.
It is exhaustive to the best of what is present in the project; if
anything is missing it was not recorded in a traceable place.

---

## Primary sources (directly verified)

### Wikipedia
- **Funiculaire du Perce-Neige (FR)** — https://fr.wikipedia.org/wiki/Funiculaire_du_Perce-Neige
- **Funiculaire du Perce-Neige (EN)** — https://en.wikipedia.org/wiki/Funiculaire_du_Perce-Neige

Key facts extracted: slope length 3 474–3 491 m, vertical drop 921 m,
lower station 2 111 m, upper station 3 032 m, max gradient 30 %, opened
14 April 1993, built by Von Roll (civil engineering) and CFD (rolling
stock), 2 trains × 2 coupled cars, 334 passengers + 1 conductor.

### Remontées-mécaniques.net
- **Reportage FUNI-334 (technical report)** — https://www.remontees-mecaniques.net/bdd/reportage-funi-334-de-la-grande-motte-perce-neige-von-roll-6174.html
- Base site — https://www.remontees-mecaniques.net

Key facts extracted: passing loop 203 m with Abt switch (no moving
parts), 3 × 800 kW DC motors by SICME, 3 hydraulic motors + 3 thermal
motors as backup, hydraulic-only speed cap 1.35 m/s, trip time
4 min 51 s (technical) / 6–7 min (commercial), bull wheel Ø 4 160 mm
(~55 rpm at 12 m/s), train length 31.6 m, cabin Ø 3.60 m, empty
32 300 kg, loaded 58 800 kg.

### CFD Group (rolling-stock manufacturer)
- **Tignes Funicular page** — https://www.cfd.group/rolling-stock/tignes-funicular (formerly cfd.group/machines/tignes-funicular-perce-neige)

Key facts extracted: rolling-stock specifications (cabin geometry,
coupling, interior layout).

### Funiculaires-France.fr
- **Tignes entry** — https://funiculaires-france.fr/tignes

Key facts extracted: route geometry, station altitudes, opening date
corroboration.

### Tignes resort (official)
- **Grande Motte glacier** — https://en.tignes.net/discover/ski-resort/grande-motte-glacier

Key facts extracted: operating hours (ski season 08:45 → 16:45 last
descent), touristic context, ski operations.

### Mon Séjour en Montagne
- **« Un métro pour skieurs »** (article on the Perce-Neige)

Key facts extracted: operational narrative and historical context.

### Fatzer (cable manufacturer)
- **Structural ropes — engineering data** (locked-coil haul cables)

Key facts extracted: 52 mm 6×26 WS Lang's lay rope, UTS 191 200 daN,
nominal 22 500 daN working tension, E ≈ 100–105 GPa effective modulus
for locked-coil construction, cross-section A ≈ π·26² mm² = 2 124 mm².

### STRMTG (French guided-transport regulator)
- **Réglementation des funiculaires** — reference specifications:
  passenger-comfort deceleration ceiling (RM5 §2.4), rail brake
  deceleration ≤ 5 m/s², overspeed auto-trip requirement on revenue
  funiculars.

### Patents
- **EP0392938A1** — Frein de sécurité pour funiculaire (safety brake
  mechanism for funicular railways).

### Reference cockpit video (local, not distributed)
- `funiculaire_cabine_hd.mp4` — 10-minute HD on-board recording,
  observed frame-by-frame to calibrate:
  - Slope-counter reading at arrival → **3 474 m**
  - Cruise speed_cmd setpoint ≈ 84 % → **~10.1 m/s observed**
  - Deceleration phase at t=340–390 s
  - Transition distances between square cut-and-cover and TBM bore
    (s < 257 m and s > 3 420 m)
  - Passing-loop entry s = 1 601 → 1 823 m
  - Curves at s = 1 297 → 1 541 m and s = 1 884 → 2 369 m
  - Gradient-break positions (pronounced break at ~3 180 m)

This video was extracted from YouTube HD footage of a passenger-side
trip. It is **not redistributed** with the simulator — only the
sub-clips extracted into `sons/ambients/` (ambient cabin audio) are
shipped in the binary.

---

## Extrapolated values (inferred from comparable funiculars)

Where Perce-Neige specifications are not public, values were derived
from comparable Swiss and French tunnel funiculars of the same era
(1989–2017) and same technology class:

| Value                            | Inferred from                               |
|----------------------------------|---------------------------------------------|
| Platform length 32 m ±3          | Stoos, Sassi–Superga, Val d'Isère Daille    |
| Platform height 55 cm ±5         | Same, one-sided platform class              |
| Effective cable E = 105 GPa      | Fatzer datasheet, locked-coil construction  |
| Static cable stretch 3.5–4.5 m   | Hooke's law on 3 491 m × 52 mm Fatzer       |
| Motor no-load RPM 1 450          | SICME DC motor family typical               |
| Motor full-load RPM 1 180 (18 %) | Same (typical DC droop)                     |
| Regen per loaded descent ~42 kWh | Energy balance on ΔH 921 m, 58.8 t          |
| Inrush 4.5× nominal, 1.2 s       | SICME DC starter characteristic             |
| Rail brake real decel 3.6 m/s²   | STRMTG spec ≤ 5, typical 3.2–4.1 on 30 %    |
| Passing-loop clearance ~40 cm    | Common tunnel-funicular standard            |
| Loop illumination 300–500 lux    | Station-type illumination                   |
| Dead-man = pedal                 | Von Roll 1990s standard (not push-button)   |
| Creep speed 0.3–0.5 m/s          | Typical Von Roll station approach           |

These are marked clearly in the source as extrapolations.

---

## Not publicly documented (educated guesses)

The following parameters are not findable in any public source and are
set in the simulator using plausible engineering values; they may not
match the real machine exactly:

- Exact platform edge clearance (mm)
- Cabin axle count and wheel diameter
- Motor-to-bull-wheel gear ratio
- Departure buzzer duration
- Door-close timing profile (ramp vs. step)

---

## Sound assets

Cabin ambient, announcements and buzzers in `sons/` were extracted from
the same reference cockpit video (or from other public passenger-side
recordings of the same funicular). Loudness-matched, cross-faded and
re-encoded as WAV/mp3. Not original copyrighted soundtrack — ambient
cabin noise and PA announcements recorded in a public transport
vehicle. No redistribution of the original video.

---

## Source priority (highest first)

When two sources disagreed, the order used for resolution was:
1. Direct observation of `funiculaire_cabine_hd.mp4` (slope counter,
   speed command, transitions)
2. remontees-mecaniques.net FUNI-334 technical report
3. Wikipedia FR / EN (Funiculaire_du_Perce-Neige)
4. funiculaires-france.fr/tignes
5. Fatzer engineering data (cable mechanical properties)
6. CFD.group (rolling stock page)

---

## Local memory file

A condensed version of this research lives in my personal memory
system (not committed to the repo):

- `~/.claude/projects/C--Users-kevin-Documents-GitHub/memory/perce_neige_research.md`
