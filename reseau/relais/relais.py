"""Relais WebSocket du mode réseau (skier à plusieurs, PWA et PC).

    python relais.py --hote 0.0.0.0 --port 8790

Variables d'environnement :
    RESEAU_CLE        clé HMAC des jetons de salon (hex) ; absente : tirée au démarrage
    RESEAU_ORIGINES   origines web admises, séparées par des virgules (vide : toutes) ; les clients
                      natifs (sans en-tête Origin) sont toujours admis
    RESEAU_PROXY      1 : derrière un mandataire de confiance, l'adresse du client est lue dans
                      CF-Connecting-IP / X-Forwarded-For (limite de connexions par adresse)
    RESEAU_CLIENTS_MAX, RESEAU_PAR_IP   connexions au total / par adresse

Ne journalise que des compteurs (aucune adresse, aucun nom, aucun code de salon).
"""
from __future__ import annotations

import argparse
import asyncio
import itertools
import json
import os
import secrets
import time

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

import salons as S

CLIENTS_MAX = int(os.environ.get("RESEAU_CLIENTS_MAX", "400"))
PAR_IP = int(os.environ.get("RESEAU_PAR_IP", "8"))
DELAI_ENTREE_S = 10.0
COMPTEURS = {"connexions": 0, "refus": 0, "coupures_debit": 0, "messages": 0, "salons_crees": 0}
_par_ip: dict = {}
_ids = itertools.count(1)


def _adresse(ws) -> str:
    if os.environ.get("RESEAU_PROXY") == "1":
        h = ws.request.headers
        a = h.get("CF-Connecting-IP") or (h.get("X-Forwarded-For") or "").split(",")[0].strip()
        if a:
            return a[:64]
    ra = ws.remote_address
    return str(ra[0]) if ra else "?"


def _horloge() -> float:
    return time.time()


async def _envoyer(ws, texte: str) -> None:
    try:
        await ws.send(texte)
    except ConnectionClosed:
        pass


def _diffuser(dests, texte: str) -> None:
    for d in dests:
        asyncio.ensure_future(_envoyer(d, texte))


async def gerer(ws, registre: S.Registre) -> None:
    COMPTEURS["connexions"] += 1
    ip = _adresse(ws)
    if sum(_par_ip.values()) >= CLIENTS_MAX or _par_ip.get(ip, 0) >= PAR_IP:
        COMPTEURS["refus"] += 1
        await ws.close(1013, "plein")
        return
    _par_ip[ip] = _par_ip.get(ip, 0) + 1
    ident = next(_ids)
    salon = None
    seau = S.Seau()
    try:
        # premier message : créer ou rejoindre, dans le délai
        try:
            brut = await asyncio.wait_for(ws.recv(), DELAI_ENTREE_S)
            m = S.valider(brut)
        except (asyncio.TimeoutError, S.Refus):
            COMPTEURS["refus"] += 1
            await ws.close(1008, "entree")
            return
        if m["t"] == "creer":
            try:
                salon = registre.creer()
            except S.Refus as e:
                COMPTEURS["refus"] += 1
                await _envoyer(ws, json.dumps({"t": "erreur", "raison": str(e)}))
                await ws.close(1013, "plein")
                return
            COMPTEURS["salons_crees"] += 1
            salon.entrer(ident, m["nom"], m["c"], ws, hote=True)
        elif m["t"] == "rejoindre":
            try:
                salon = registre.trouver(m["code"])
                hote = S.jeton_valide(registre.cle, salon.code, m.get("jeton", ""))
                salon.entrer(ident, m["nom"], m["c"], ws, hote=hote)
            except S.Refus as e:
                COMPTEURS["refus"] += 1
                await _envoyer(ws, json.dumps({"t": "erreur", "raison": str(e)}))
                await ws.close(1008, "salon")
                salon = None
                return
        else:
            COMPTEURS["refus"] += 1
            await ws.close(1008, "entree")
            return
        moi = salon.membres[ident]
        await ws.send(json.dumps({"t": "bienvenue", "code": salon.code, "id": ident,
                                  "jeton": S.jeton(registre.cle, salon.code) if salon.hote == ident else "",
                                  "hote": salon.hote, "membres": salon.liste(), "ts": _horloge()}))
        _diffuser(salon.autres(ident), json.dumps({"t": "arrivee", "id": ident, "nom": moi["nom"], "c": moi["c"],
                                                   "hote": salon.hote}))
        async for brut in ws:
            if not seau.prendre():
                COMPTEURS["coupures_debit"] += 1
                await ws.close(1008, "debit")
                break
            try:
                m = S.valider(brut)
            except S.Refus:
                COMPTEURS["refus"] += 1
                await ws.close(1008, "message")
                break
            COMPTEURS["messages"] += 1
            t = m["t"]
            if t == "horloge":
                await ws.send(json.dumps({"t": "horloge", "c": m["c"], "s": _horloge()}))
            elif t == "etat":
                _diffuser(salon.autres(ident), S.sortant(m, ident))
            elif t in ("lignes", "cmd"):
                # (état des remontées : publié par le pilote de chacune, l'hôte par défaut ; chacun ne retient que
                # celui du pilote — le relais ne fait que redistribuer)
                _diffuser(salon.autres(ident), S.sortant(m, ident))
            elif t == "pilotes":
                if salon.hote == ident:
                    _diffuser(salon.autres(ident), S.sortant(m, ident))
            elif t == "quitter":
                break
            else:
                # (créer / rejoindre une seconde fois : refusé)
                COMPTEURS["refus"] += 1
                await ws.close(1008, "message")
                break
    except ConnectionClosed:
        pass
    finally:
        _par_ip[ip] = _par_ip.get(ip, 1) - 1
        if _par_ip[ip] <= 0:
            _par_ip.pop(ip, None)
        if salon is not None and ident in salon.membres:
            salon.sortir(ident)
            _diffuser(salon.autres(ident), json.dumps({"t": "depart", "id": ident, "hote": salon.hote}))


async def _compteurs(registre: S.Registre) -> None:
    while True:
        await asyncio.sleep(300)
        registre.purger()
        print("[relais] salons %d · clients %d · %s" % (len(registre.salons), sum(_par_ip.values()),
              " · ".join("%s %d" % kv for kv in COMPTEURS.items())), flush=True)


async def principal(hote: str, port: int) -> None:
    cle_hex = os.environ.get("RESEAU_CLE", "")
    cle = bytes.fromhex(cle_hex) if cle_hex else secrets.token_bytes(32)
    registre = S.Registre(cle)
    origines = [o.strip() for o in os.environ.get("RESEAU_ORIGINES", "").split(",") if o.strip()]
    kw = {}
    if origines:
        kw["origins"] = origines + [None]
    async with serve(lambda ws: gerer(ws, registre), hote, port, max_size=S.TAILLE_MAX, max_queue=16,
                     ping_interval=20, ping_timeout=20, close_timeout=5, compression=None, **kw):
        print("[relais] à l'écoute sur %s:%d" % (hote, port), flush=True)
        await _compteurs(registre)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--hote", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8790)
    a = ap.parse_args()
    asyncio.run(principal(a.hote, a.port))
