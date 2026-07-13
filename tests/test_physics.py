"""Tests anti-régression de la physique du Perce-Neige.

Ces tests figent les comportements calibrés/vérifiés au banc en juillet
2026 (sessions d'audit) : profil altimétrique, enveloppe de vitesse,
tension du câble (avec poids propre du câble), distances d'arrêt par type
de frein, cascade de survitesse, rebond élastique à l'arrêt, banques de
sifflement moteur. Toute modification de la physique qui casse une de ces
invariantes doit être un choix EXPLICITE (mettre à jour la borne avec la
justification), jamais un accident.

Exécution : QT_QPA_PLATFORM=offscreen pytest tests/ -v
(PyQt6 requis pour importer le module ; aucune fenêtre créée.)
"""
import math
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perce_neige_sim as pn  # noqa: E402

DT = 1.0 / 60.0


def _make(direction, s0, pax, gpax, v0=0.0, cmd=1.0):
    st = pn.GameState()
    st.mode = pn.MODE_RUN
    tr = st.train
    tr.pax_car1 = pax // 2
    tr.pax_car2 = pax - pax // 2
    st.ghost_pax = gpax
    tr.direction = direction
    tr.s = s0
    tr.v = v0
    tr.doors_open = False
    tr.maint_brake = False
    tr.trip_started = True
    st.trip_started = True
    tr.speed_cmd = cmd
    return st, pn.Physics(st)


def _stop_distance(st, ph, setup, tmax=130.0):
    """Applique `setup` au train lancé, retourne (distance, durée, décél pic)."""
    tr = st.train
    setup(tr)
    s0, t, peak = tr.s, 0.0, 0.0
    while abs(tr.v) > 0.05 and t < tmax:
        v_prev = tr.v
        ph.step(DT)
        t += DT
        peak = max(peak, abs((tr.v - v_prev) / DT))
    return abs(tr.s - s0), t, peak


# ---------------------------------------------------------------------------
# Profil de la ligne
# ---------------------------------------------------------------------------

def test_denivele_exact():
    drop = pn.geom_at(pn.LENGTH)[1] - pn.geom_at(0.0)[1]
    assert abs(drop - 921.0) < 0.05, f"dénivelé {drop} ≠ 921 m"


def test_altitude_monotone():
    prev = pn.geom_at(0.0)[1]
    for s in range(50, int(pn.LENGTH), 50):
        alt = pn.geom_at(float(s))[1]
        assert alt >= prev - 0.01, f"altitude non monotone à s={s}"
        prev = alt


def test_evitement_decale_aval():
    # Le croisement des rames (milieu de ligne) doit être EN AMONT du
    # centre de l'évitement : la rame montante entre dans son tube avant
    # la descendante (protection rupture côté descente).
    centre_loop = (pn.PASSING_START + pn.PASSING_END) * 0.5
    croisement = pn.LENGTH * 0.5
    assert croisement - centre_loop > 15.0, "évitement plus décalé vers l'aval"


# ---------------------------------------------------------------------------
# Trajet complet — enveloppe vitesse / temps / tension
# ---------------------------------------------------------------------------

def test_montee_complete_chargee():
    st, ph = _make(1, pn.START_S, 265, 20)
    t, vmax, tmax_tension = 0.0, 0.0, 0.0
    while not st.finished and t < 900:
        ph.step(DT)
        t += DT
        vmax = max(vmax, abs(st.train.v))
        tmax_tension = max(tmax_tension, st.train.tension_dan)
    assert st.finished, "la montée n'aboutit pas en 15 min"
    assert 5.0 < t / 60.0 < 10.0, f"durée {t/60:.1f} min hors [5, 10]"
    assert vmax <= 12.06, f"vmax {vmax:.2f} > V_MAX"
    # Tension : pic au départ bas chargé (gravité + câble + inrush),
    # nominal 22 500 daN — le pic doit rester dans l'enveloppe réaliste.
    assert 20000 < tmax_tension < 27000, f"tension pic {tmax_tension:.0f} daN"
    # Arrivée en haut, modèle DEUX BRINS : le brin de la rame pleine en
    # haut est quasi nul, mais celui du contrepoids (vide, en bas) porte
    # ses 3,4 km de câble (~9 900 daN) + son poids sur la pente du bas →
    # le max affiché reste ~11-14 000 daN. (L'ancien modèle mono-brin
    # « rame lourde » attendait < 7 000 : il ignorait le brin bas.)
    assert 10000 < st.train.tension_dan < 15000, \
        f"tension arrivée haut {st.train.tension_dan:.0f} daN"


# ---------------------------------------------------------------------------
# Décélérations par type d'arrêt (zone 30 %, 12 m/s, 265 pax)
# ---------------------------------------------------------------------------

def test_frein_service_montee():
    st, ph = _make(1, 1500.0, 265, 0, v0=12.0)
    d, t, _ = _stop_distance(st, ph, lambda tr: (
        setattr(tr, "brake", 1.0), setattr(tr, "speed_cmd", 0.0)))
    assert t < 15 and d < 60, f"service montée : {d:.0f} m / {t:.0f} s"


def test_urgence_commandee_descente():
    # Bouton rouge = frein POULIE 1,25 m/s² (pas le parachute) : en
    # descente la gravité s'y oppose → arrêt long mais borné.
    st, ph = _make(-1, 1500.0, 265, 0, v0=-12.0)
    d, t, peak = _stop_distance(st, ph, lambda tr: setattr(tr, "emergency", True))
    assert t < 30 and 60 < d < 160, f"urgence descente : {d:.0f} m / {t:.0f} s"
    assert peak < 1.6, f"décél pic {peak:.2f} > confort passagers debout"


def test_parachute_descente():
    st, ph = _make(-1, 1500.0, 265, 0, v0=-12.0)
    d, t, _ = _stop_distance(st, ph, lambda tr: (
        setattr(tr, "emergency", True),
        setattr(tr, "parachute_engaged", True)))
    assert t < 8 and d < 40, f"parachute descente : {d:.0f} m / {t:.0f} s"


def test_rupture_cable_descente():
    # Pire cas Glória : descente chargée, câble rompu, parachute seul.
    st, ph = _make(-1, 1500.0, 265, 0, v0=-12.0)
    tr = st.train
    tr.cable_rupture = True
    tr.emergency = True
    tr.parachute_engaged = True
    tr.service_brake_fail = 0.15
    d, t, _ = _stop_distance(st, ph, lambda _tr: None)
    assert t < 30 and d < 130, f"rupture câble : {d:.0f} m / {t:.0f} s"


def test_cascade_survitesse():
    # Emballement réel : drive hors tension + frein de service HS en
    # descente chargée à 30 % → la cascade doit tirer (le bleed numérique
    # ne doit PAS écrêter la vitesse quand le chemin de force est mort).
    st, ph = _make(-1, 1000.0, 265, 0, v0=-12.0)
    tr = st.train
    tr.aux_power_fault = True
    tr.service_brake_fail = 0.0
    t, vpeak = 0.0, 12.0
    while t < 180:
        ph.step(DT)
        t += DT
        vpeak = max(vpeak, abs(tr.v))
        if tr.overspeed_level >= 1 and abs(tr.v) < 0.05:
            break
    assert tr.overspeed_level >= 1, "cascade de survitesse jamais déclenchée"
    assert vpeak > 13.15, f"v pic {vpeak:.2f} — seuil +10 % jamais franchi"
    assert abs(tr.v) < 0.1, "emballement non arrêté"


def test_entree_en_gare_a_075():
    # Retour d'essai exploitant (2026-07) : l'entrée en gare se fait à
    # ~0,75 m/s. L'ancien réglage (0,04 m/s² sur 6 m) rampait à 0,2 m/s
    # à l'aller et calait quasi à l'arrêt au retour.
    for direction, s0 in ((1, pn.STOP_S - 400.0), (-1, pn.START_S + 400.0)):
        st, ph = _make(direction, s0, 100, 0, v0=8.0 * direction, cmd=1.0)
        t, v_at_5m = 0.0, None
        while not st.finished and t < 300:
            ph.step(DT)
            t += DT
            dist = ((pn.STOP_S - st.train.s) if direction > 0
                    else (st.train.s - pn.START_S))
            if v_at_5m is None and dist < 5.0:
                v_at_5m = abs(st.train.v)
        assert st.finished, f"pas arrivé (dir={direction}, t={t:.0f}s)"
        assert v_at_5m is not None and 0.55 < v_at_5m < 0.95, \
            f"v à 5 m du quai = {v_at_5m} (dir={direction}, attendu ~0,75)"
        assert t < 200, f"approche trop lente ({t:.0f} s, dir={direction})"


# ---------------------------------------------------------------------------
# Rebond élastique à l'arrêt (k = EA/L → visible en bas, pas en haut)
# ---------------------------------------------------------------------------

def _rebond(direction, s0):
    st, ph = _make(direction, s0, 100, 0,
                   v0=3.0 * direction, cmd=0.9)
    t = 0.0
    while not st.finished and t < 300:
        ph.step(DT)
        t += DT
    assert st.finished
    s_arr = st.train.s
    amp, final = 0.0, 0.0
    for i in range(int(25.0 / DT)):
        ph.step(DT)
        final = st.train.s - s_arr
        amp = max(amp, abs(final))
    return amp, abs(final)


def test_rebond_gare_basse_visible():
    amp, final = _rebond(-1, pn.START_S + 60.0)
    assert 0.05 < amp < 0.50, f"rebond bas {amp*100:.0f} cm hors [5, 50]"
    assert final < 0.06, f"ne revient pas au point d'arrêt ({final*100:.0f} cm)"


def test_rebond_gare_haute_invisible():
    amp, _ = _rebond(1, pn.STOP_S - 60.0)
    assert amp < 0.02, f"rebond haut {amp*1000:.0f} mm — devrait être ~mm"


# ---------------------------------------------------------------------------
# Banques de sifflement moteur (hauteur vs vitesse)
# ---------------------------------------------------------------------------

def test_motor_banques():
    prev_centroid = -1.0
    for v in [0.0, 2.0, 5.0, 8.0, 10.1, 12.0, 15.0]:
        w = pn._motor_bank_weights(v)
        assert abs(sum(w) - 1.0) < 1e-9
        assert sum(1 for x in w if x > 0.001) <= 2
        centroid = sum(k * x for k, x in enumerate(w))
        assert centroid >= prev_centroid - 1e-9
        prev_centroid = centroid
    # Point de calibration : 197 Hz à 10,1 m/s (± 1,5 Hz)
    w = pn._motor_bank_weights(10.1)
    f = sum(pn.MOTOR_F_BANKS[k] * x for k, x in enumerate(w))
    assert abs(f - 197.0) < 1.5, f"{f:.1f} Hz à 10,1 m/s (attendu ~197)"


# ---------------------------------------------------------------------------
# Auto-update : sélection du bon asset (le sim, jamais le viewer 3D)
# ---------------------------------------------------------------------------

def test_update_picks_sim_not_viewer():
    import autoupdate as au

    def _mk(names):
        assets = [au.ReleaseAsset(name=n, url="https://x/" + n, size=100)
                  for n in names]
        return au.ReleaseInfo(tag="v9.9.9", version="9.9.9", name="", body="",
                              zipball_url="", html_url="", assets=assets)

    order_a = ["PerceNeigeSimulator-windows.exe", "perce_neige_3d-windows.exe"]
    order_b = ["perce_neige_3d-windows.exe", "PerceNeigeSimulator-windows.exe"]
    orig = au.sys.platform
    try:
        au.sys.platform = "win32"
        for order in (order_a, order_b):
            a = au._pick_binary_asset(_mk(order))
            assert a is not None and a.name == "PerceNeigeSimulator-windows.exe", \
                f"mauvais asset choisi pour l'ordre {order}: {a and a.name}"
    finally:
        au.sys.platform = orig


def test_update_version_compare():
    import autoupdate as au
    assert au.is_newer("1.12.4", "1.12.0")
    assert au.is_newer("1.12.10", "1.12.9")   # comparaison numérique, pas lexicale
    assert not au.is_newer("1.12.0", "1.12.0")
    assert not au.is_newer("1.11.9", "1.12.0")


def test_pas_de_depart_sans_sequence():
    # Bug terrain (2026-07) : « le funiculaire s'est mis en route quand
    # j'ai fermé les portes » — départ gare amont, sans PRÊT(V)+buzzer(Z).
    # Même avec un état incohérent (frein tambour desserré, consigne à
    # 100 %, portes fermées), la rame ne doit PAS bouger tant que
    # trip_started est faux, et le tambour doit se réengager seul.
    st, ph = _make(-1, pn.STOP_S, 5, 100, v0=0.0, cmd=1.0)
    st.trip_started = False
    tr = st.train
    tr.trip_started = False
    tr.maint_brake = False      # état incohérent volontaire
    tr.doors_open = False       # portes fermées
    for _ in range(int(10.0 / DT)):
        ph.step(DT)
    assert abs(tr.v) < 0.01, f"la rame bouge sans séquence de départ (v={tr.v})"
    assert abs(tr.s - pn.STOP_S) < 0.1, f"la rame a dérivé (s={tr.s})"
    assert tr.maint_brake, "le tambour ne s'est pas réengagé"
