"""Relais du mode réseau : schéma strict, limites, salons (logique seule), puis un échange réel si `websockets`
est installé (deux clients dans un salon, rejets)."""
import asyncio
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reseau" / "relais"))
import salons as S  # noqa: E402


def _etat(**k):
    m = {"t": "etat", "p": [100.0, 2100.0, -50.0], "cap": 1.0, "v": [3.0, -1.0, 0.0], "po": 0, "tc": 1.7e9}
    m.update(k)
    return json.dumps(m)


def test_etat_valide_reconstruit():
    m = S.valider(_etat(extra="<script>", l="tsd6_bollin", i=3, s=120.5, o=[0.3, 0.5, 0.0]))
    assert "extra" not in m
    assert m["l"] == "tsd6_bollin" and m["i"] == 3 and m["o"] == [0.3, 0.5, 0.0]


@pytest.mark.parametrize("champ,val", [
    ("p", [1e9, 0, 0]), ("p", [0, 0]), ("p", ["a", 0, 0]), ("cap", float("nan")), ("cap", True),
    ("v", [500, 0, 0]), ("po", 9), ("l", "../etc"), ("l", "A" * 50), ("tc", -1)])
def test_etat_hors_bornes(champ, val):
    with pytest.raises(S.Refus):
        S.valider(_etat(**{champ: val, "i": 0, "s": 0, "o": [0, 0, 0]}) if champ == "l" else _etat(**{champ: val}))


def test_trop_gros_et_types():
    with pytest.raises(S.Refus):
        S.valider("x" * (S.TAILLE_MAX + 1))
    for b in ["[]", "1", "{\"t\":\"inconnu\"}", "{", "\"t\""]:
        with pytest.raises(S.Refus):
            S.valider(b)


def test_nom_filtre():
    assert S.nom_propre("  <b>Éq-1</b>  ;DROP  ") == "bÉq-1b DROP"
    assert S.nom_propre("a" * 40) == "a" * 16
    assert S.nom_propre("<<>>") == "Skieur"


def test_code_et_jeton():
    c = S.nouveau_code()
    assert len(c) == 8 and all(x in S.ALPHABET for x in c)
    cle = b"k" * 32
    j = S.jeton(cle, c)
    assert S.jeton_valide(cle, c, j) and not S.jeton_valide(cle, c, "0" * 32) and not S.jeton_valide(b"x" * 32, c, j)
    m = S.valider(json.dumps({"t": "rejoindre", "code": c.lower()[:4] + "-" + c.lower()[4:], "nom": "A"}))
    assert m["code"] == c
    with pytest.raises(S.Refus):
        S.valider(json.dumps({"t": "rejoindre", "code": "ABC"}))


def test_lignes():
    e = ["tsd6_bollin", 12.5, 5.0, 1.0, 0, 2, 1.0, []]
    m = S.valider(json.dumps({"t": "lignes", "tc": 5.0, "d": [e]}))
    assert m["d"][0][0] == "tsd6_bollin" and m["d"][0][4] == 0 and m["d"][0][7] == []
    # va-et-vient : état complet dans les nombres propres
    tph = ["tph_grande_motte", 812.3, -9.5, 0.9, 3, 2, 1.0, [812.3, -9.5, -1, 1, 0, 0, 0, 0]]
    m = S.valider(json.dumps({"t": "lignes", "tc": 5.0, "d": [tph]}))
    assert m["d"][0][4] == 3 and len(m["d"][0][7]) == 8
    with pytest.raises(S.Refus):
        S.valider(json.dumps({"t": "lignes", "tc": 5.0, "d": [e] * (S.LIGNES_MAX + 1)}))
    for mauvais in (e[:4], e[:7] + [[0] * (S.EXTRA_MAX + 1)], e[:4] + [7] + e[5:], e[:7] + ["x"],
                    e[:2] + [99.0] + e[3:], ["Bollin;"] + e[1:]):
        with pytest.raises(S.Refus):
            S.valider(json.dumps({"t": "lignes", "tc": 5.0, "d": [mauvais]}))


def test_cmd_et_pilotes():
    m = S.valider(json.dumps({"t": "cmd", "l": "tph_fornet", "a": 0, "x": "ignoré"}))
    assert m == {"t": "cmd", "l": "tph_fornet", "a": 0}
    # commande partagée (arrêt fait par un joueur, exécutée par tous)
    m2 = S.valider(json.dumps({"t": "cmd", "l": "tcd10_daille", "a": 2, "o": "arreter", "k": 3, "tc": 12.5, "z": 1}))
    assert m2 == {"t": "cmd", "l": "tcd10_daille", "a": 2, "o": "arreter", "k": 3, "tc": 12.5}
    for mauvais_o in ({"t": "cmd", "l": "tcd10_daille", "a": 2, "o": "panne", "tc": 1.0},
                      {"t": "cmd", "l": "tcd10_daille", "a": 2, "tc": 1.0},
                      {"t": "cmd", "l": "tcd10_daille", "a": 2, "o": "cran", "k": 12, "tc": 1.0},
                      {"t": "cmd", "l": "tcd10_daille", "a": 2, "o": ["arreter"], "tc": 1.0}):
        with pytest.raises(S.Refus):
            S.valider(json.dumps(mauvais_o))
    for mauvais in ({"t": "cmd", "l": "tph_fornet", "a": 5}, {"t": "cmd", "l": "../x", "a": 0},
                    {"t": "cmd", "a": 0}):
        with pytest.raises(S.Refus):
            S.valider(json.dumps(mauvais))
    m = S.valider(json.dumps({"t": "pilotes", "d": [["perce_neige", 3], ["tsd6_bollin", 1]]}))
    assert m["d"] == [["perce_neige", 3], ["tsd6_bollin", 1]]
    with pytest.raises(S.Refus):
        S.valider(json.dumps({"t": "pilotes", "d": [["a", 1]] * (S.PILOTES_MAX + 1)}))
    with pytest.raises(S.Refus):
        S.valider(json.dumps({"t": "pilotes", "d": [["a", -1]]}))


def test_corde_et_file():
    m = S.valider(json.dumps({"t": "corde", "l": "tsd6_grattalu", "s": 512.5, "ph": 0, "tc": 10.0, "x": 1}))
    assert m == {"t": "corde", "l": "tsd6_grattalu", "s": 512.5, "ph": 0, "tc": 10.0}
    m = S.valider(json.dumps({"t": "corde", "l": "tsd6_grattalu", "s": 512.5, "ph": 1, "tc": 10.0,
                              "a": [10.0, 2100.0, -5.0], "p": [10.2, 2090.0, -5.1], "psi": 1.5, "lc": 10.0}))
    assert m["p"] == [10.2, 2090.0, -5.1] and m["lc"] == 10.0 and m["psi"] == 1.5
    m = S.valider(json.dumps({"t": "corde", "l": "tsd6_grattalu", "s": 1.0, "ph": 2, "tc": 1.0, "tr": 2.5, "am": 12.0}))
    assert m["tr"] == 2.5 and m["am"] == 12.0 and "p" not in m
    for mauvais in ({"t": "corde", "l": "x", "s": 1.0, "ph": 3, "tc": 1.0},
                    {"t": "corde", "l": "../x", "s": 1.0, "ph": 0, "tc": 1.0},
                    {"t": "corde", "l": "x", "s": 1.0, "ph": 1, "tc": 1.0},           # descente sans pendule
                    {"t": "corde", "l": "x", "s": 1.0, "ph": 1, "tc": 1.0, "a": [0, 0, 0], "p": [0, 0, 0],
                     "psi": 0.0, "lc": 5000.0},
                    {"t": "corde", "l": "x", "s": 1.0, "ph": 2, "tc": 1.0, "am": 200.0}):
        with pytest.raises(S.Refus):
            S.valider(json.dumps(mauvais))
    m = S.valider(json.dumps({"t": "file", "l": "tsd6_grattalu", "d": [3, 1]}))
    assert m == {"t": "file", "l": "tsd6_grattalu", "d": [3, 1]}
    for mauvais in ({"t": "file", "l": "x", "d": list(range(S.FILE_MAX + 1))}, {"t": "file", "l": "x", "d": [-1]},
                    {"t": "file", "l": "x", "d": "1,2"}):
        with pytest.raises(S.Refus):
            S.valider(json.dumps(mauvais))


def test_seau():
    t = [0.0]
    s = S.Seau(horloge=lambda: t[0])
    assert sum(s.prendre() for _ in range(100)) == int(S.RAFALE)
    t[0] += 1.0
    assert sum(s.prendre() for _ in range(100)) == int(S.DEBIT_PAR_S)


def test_salons_plein_et_expiration():
    t = [0.0]
    r = S.Registre(b"k" * 32, horloge=lambda: t[0])
    s = r.creer()
    for i in range(S.JOUEURS_MAX):
        s.entrer(i, "n", [0, 0, 0], None)
    with pytest.raises(S.Refus):
        s.entrer(99, "n", [0, 0, 0], None)
    assert s.hote == 0
    for i in range(S.JOUEURS_MAX):
        s.sortir(i)
    t[0] += S.EXPIRATION_VIDE_S + 1
    with pytest.raises(S.Refus):
        r.trouver(s.code)
    for _ in range(S.SALONS_MAX):
        r.creer()
    with pytest.raises(S.Refus):
        r.creer()


def _module(nom):
    """Module du relais chargé par son chemin, sous un nom propre (aucun conflit avec d'autres tests)."""
    import importlib.util
    chemin = Path(__file__).resolve().parents[1] / "reseau" / "relais" / (nom + ".py")
    spec = importlib.util.spec_from_file_location("reseau_relais_" + nom, chemin)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _port_libre() -> int:
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as so:
        so.bind(("127.0.0.1", 0))
        return so.getsockname()[1]


@pytest.mark.timeout(30)
def test_echange_reel(monkeypatch):
    pytest.importorskip("websockets")
    # (plusieurs essais du simulateur figent time.monotonic pour toute la suite — pn.time.monotonic = horloge
    # simulée, jamais rendue : la boucle asyncio, qui s'en sert, n'avançait plus. Une vraie horloge, le temps de
    # cet essai.)
    import time as _time
    monkeypatch.setattr(_time, "monotonic", _time.perf_counter)
    sys.modules.setdefault("salons", S)
    R = _module("relais")
    from websockets.asyncio.client import connect

    D = 5.0          # délai de chaque attente (s) : jamais de blocage

    async def recv(ws):
        return await asyncio.wait_for(ws.recv(), D)

    async def ouvrir(url, **kw):
        return await asyncio.wait_for(connect(url, open_timeout=D, close_timeout=1, **kw), D)

    async def coupe(ws):
        """Le relais coupe la connexion : recv lève (ou rien n'arrive) dans le délai."""
        try:
            for _ in range(5):
                await recv(ws)
        except Exception:
            return True
        return False

    async def scenario():
        port = _port_libre()
        srv = asyncio.ensure_future(R.principal("127.0.0.1", port))
        try:
            url = "ws://127.0.0.1:%d" % port
            for _ in range(50):
                try:
                    (await ouvrir(url)).transport.close()
                    break
                except Exception:
                    await asyncio.sleep(0.1)
            a = await ouvrir(url)
            b = await ouvrir(url)
            try:
                await a.send(json.dumps({"t": "creer", "nom": "A"}))
                b1 = json.loads(await recv(a))
                assert b1["t"] == "bienvenue" and len(b1["jeton"]) == 32
                await b.send(json.dumps({"t": "rejoindre", "code": b1["code"], "nom": "B"}))
                b2 = json.loads(await recv(b))
                assert b2["hote"] == b1["id"] and len(b2["membres"]) == 2
                assert json.loads(await recv(a))["t"] == "arrivee"
                await a.send(_etat())
                e = json.loads(await recv(b))
                assert e["t"] == "etat" and e["id"] == b1["id"]
                # pilotage : la demande d'un joueur va à l'hôte ; seul l'hôte publie les pilotes ; l'état d'une
                # remontée est relayé de n'importe qui (chacun ne garde que celui du pilote)
                await b.send(json.dumps({"t": "cmd", "l": "tph_fornet", "a": 0}))
                c1 = json.loads(await recv(a))
                assert c1 == {"t": "cmd", "l": "tph_fornet", "a": 0, "id": b2["id"]}
                await b.send(json.dumps({"t": "pilotes", "d": [["tph_fornet", b2["id"]]]}))      # ignoré
                await a.send(json.dumps({"t": "pilotes", "d": [["tph_fornet", b2["id"]]]}))
                p1 = json.loads(await recv(b))
                assert p1["t"] == "pilotes" and p1["d"] == [["tph_fornet", b2["id"]]]
                await b.send(json.dumps({"t": "lignes", "tc": 2.0,
                                         "d": [["tph_fornet", 10.0, 2.0, 1.0, 0, 2, 1.0, [10.0, 2.0, 1, 1]]]}))
                l1 = json.loads(await recv(a))
                assert l1["t"] == "lignes" and l1["id"] == b2["id"]
                await b.send(json.dumps({"t": "horloge", "c": 1.0}))
                h = json.loads(await recv(b))
                assert h["t"] == "horloge" and h["s"] > 1e9
                # message trop gros : coupé
                await b.send("{" + " " * 2000 + "}")
                assert await coupe(b)
            finally:
                await a.close()
                await b.close()
            # mauvais code : refusé
            c = await ouvrir(url)
            try:
                await c.send(json.dumps({"t": "rejoindre", "code": "ZZZZZZZZ", "nom": "C"}))
                assert json.loads(await recv(c))["t"] == "erreur"
            finally:
                await c.close()
            # débit : coupé au-delà de la rafale
            d = await ouvrir(url)
            try:
                await d.send(json.dumps({"t": "creer", "nom": "D"}))
                await recv(d)
                try:
                    for _ in range(200):
                        await asyncio.wait_for(d.send(_etat()), D)
                except Exception:
                    pass
                assert await coupe(d)
            finally:
                await d.close()
        finally:
            srv.cancel()
            try:
                await asyncio.wait_for(srv, D)
            except BaseException:
                pass

    boucle = asyncio.new_event_loop()
    try:
        boucle.run_until_complete(asyncio.wait_for(scenario(), 25))
    finally:
        boucle.close()
