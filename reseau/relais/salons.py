"""Logique du relais du mode réseau, sans réseau : salons, schéma strict des messages, limites de débit.

Le relais ne calcule rien du jeu : il reçoit l'état de chaque joueur d'un salon et le redistribue aux autres,
avec une horloge commune. Tout message est validé champ par champ (types, bornes, longueurs) et reconstruit :
rien de ce qu'envoie un client n'est renvoyé tel quel. Ce module est testé seul (tests/test_reseau_relais.py).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import math
import re
import secrets
import time

# alphabet des codes de salon : sans 0/O, 1/I/L, ni voyelles ambiguës à l'oral
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LONGUEUR_CODE = 8
JOUEURS_MAX = 8
SALONS_MAX = 200
EXPIRATION_VIDE_S = 600.0
TAILLE_MAX = 1024              # octets par message
DEBIT_PAR_S = 20.0             # messages par seconde (seau de jetons)
RAFALE = 30.0
NOM_MAX = 16
LIGNES_MAX = 16                # lignes par message d'état des remontées (1 Ko au plus)
PILOTES_MAX = 24               # lignes par message des pilotes
# commandes d'une remontée partagées avec le salon (21/11/2026 : l'arrêt d'un joueur doit être vu de tous)
ORDRES = ("demarrer", "arreter", "urgence", "rearmer", "cran")
LISTE_MAX = 20                 # salons ouverts donnés à qui demande la liste (rejoindre sans clavier, 21/11/2026)
LISTES_PAR_CONNEXION = 400     # demandes de liste avant d'entrer dans un salon (une toutes les 3 s : 20 min)
EXTRA_MAX = 8                  # nombres propres au genre de ligne (va-et-vient, funiculaire)
BORNE_XZ = 40000.0             # m (le domaine fait ~20 km)
BORNE_Y = (-500.0, 6000.0)
VITESSE_MAX = 80.0             # m/s
DECALAGE_MAX = 40.0            # m, place dans un véhicule (rames de funiculaire : ~30 m)
FILE_MAX = 8                   # joueurs dans une file de descente à la corde
CORDE_MAX = 400.0              # m, longueur de corde / hauteur sous l'ancrage
POSTURES = range(0, 6)         # 0 ski, 1 à pied, 2 assis à bord, 3 debout à bord, 4 chute, 5 échelle
_RE_LIGNE = re.compile(r"^[a-z0-9_]{1,40}$")
_RE_CODE = re.compile(r"^[%s]{%d}$" % (ALPHABET, LONGUEUR_CODE))
_RE_JETON = re.compile(r"^[0-9a-f]{32}$")


class Refus(Exception):
    """Message invalide : le relais le rejette (et compte le rejet)."""


def nouveau_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(LONGUEUR_CODE))


def jeton(cle: bytes, code: str) -> str:
    return hmac.new(cle, code.encode("ascii"), hashlib.sha256).hexdigest()[:32]


def jeton_valide(cle: bytes, code: str, j: str) -> bool:
    return isinstance(j, str) and bool(_RE_JETON.match(j)) and hmac.compare_digest(jeton(cle, code), j)


def _nombre(v, lo: float, hi: float) -> float:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise Refus("nombre attendu")
    f = float(v)
    if not math.isfinite(f) or f < lo or f > hi:
        raise Refus("nombre hors bornes")
    return round(f, 3)


def _vec3(v, lo, hi) -> list:
    if not isinstance(v, list) or len(v) != 3:
        raise Refus("vecteur attendu")
    los = lo if isinstance(lo, (list, tuple)) else (lo, lo, lo)
    his = hi if isinstance(hi, (list, tuple)) else (hi, hi, hi)
    return [_nombre(v[k], los[k], his[k]) for k in range(3)]


def nom_propre(v) -> str:
    """Nom affiché : lettres (accents compris), chiffres, espace, - _ ' ; 16 caractères au plus."""
    if not isinstance(v, str):
        raise Refus("nom attendu")
    s = "".join(c for c in v if c.isalnum() or c in " -_'")
    s = " ".join(s.split())[:NOM_MAX]
    return s or "Skieur"


def couleur(v) -> list:
    return _vec3(v, 0.0, 1.0)


def valider(brut: str | bytes) -> dict:
    """Message d'un client → dictionnaire reconstruit (seuls les champs connus, bornés), ou Refus."""
    if isinstance(brut, (bytes, bytearray)):
        if len(brut) > TAILLE_MAX:
            raise Refus("trop gros")
        try:
            brut = bytes(brut).decode("utf-8")
        except UnicodeDecodeError as e:
            raise Refus("pas de l'UTF-8") from e
    if not isinstance(brut, str) or len(brut.encode("utf-8")) > TAILLE_MAX:
        raise Refus("trop gros")
    try:
        m = json.loads(brut)
    except (ValueError, RecursionError) as e:
        raise Refus("JSON invalide") from e
    if not isinstance(m, dict):
        raise Refus("objet attendu")
    t = m.get("t")
    if t == "etat":
        o = {"t": "etat",
             "p": _vec3(m.get("p"), (-BORNE_XZ, BORNE_Y[0], -BORNE_XZ), (BORNE_XZ, BORNE_Y[1], BORNE_XZ)),
             "cap": _nombre(m.get("cap"), -10.0, 10.0),
             "v": _vec3(m.get("v"), -VITESSE_MAX, VITESSE_MAX),
             "po": int(_nombre(m.get("po"), 0, max(POSTURES))),
             "tc": _nombre(m.get("tc"), 0.0, 1e11)}
        ligne = m.get("l", "")
        if ligne not in ("", None):
            if not isinstance(ligne, str) or not _RE_LIGNE.match(ligne):
                raise Refus("ligne invalide")
            o["l"] = ligne
            o["i"] = int(_nombre(m.get("i"), 0, 2000))
            o["s"] = _nombre(m.get("s"), 0.0, 100000.0)
            o["o"] = _vec3(m.get("o"), -DECALAGE_MAX, DECALAGE_MAX)
        return o
    if t == "horloge":
        return {"t": "horloge", "c": _nombre(m.get("c"), 0.0, 1e11)}
    if t == "lignes":
        d = m.get("d")
        if not isinstance(d, list) or len(d) > LIGNES_MAX:
            raise Refus("lignes invalides")
        out = []
        for e in d:
            # [ligne, abscisse, vitesse, régime, état (0 marche, 1 arrêt demandé, 2 arrêt, 3 urgence), cran,
            #  plafond d'exploitation, [nombres propres au genre de ligne]]
            if not isinstance(e, list) or len(e) != 8 or not isinstance(e[0], str) or not _RE_LIGNE.match(e[0]):
                raise Refus("ligne invalide")
            x = e[7]
            if not isinstance(x, list) or len(x) > EXTRA_MAX:
                raise Refus("ligne invalide")
            out.append([e[0], _nombre(e[1], -100000.0, 100000.0), _nombre(e[2], -40.0, 40.0),
                        _nombre(e[3], 0.0, 1.5), int(_nombre(e[4], 0, 3)), int(_nombre(e[5], 0, 9)),
                        _nombre(e[6], 0.0, 1.5), [_nombre(v, -100000.0, 100000.0) for v in x]])
        return {"t": "lignes", "d": out, "tc": _nombre(m.get("tc"), 0.0, 1e11)}
    if t == "cmd":
        # demande de pilotage d'une remontée (0 : prendre / garder la main, 1 : la rendre) ; l'hôte arbitre.
        # 2 : commande faite au poste (ordre parmi ORDRES, cran 0 à 9), exécutée par chaque joueur
        ligne = m.get("l")
        if not isinstance(ligne, str) or not _RE_LIGNE.match(ligne):
            raise Refus("ligne invalide")
        a = int(_nombre(m.get("a"), 0, 2))
        if a != 2:
            return {"t": "cmd", "l": ligne, "a": a}
        ordre = m.get("o")
        if not isinstance(ordre, str) or ordre not in ORDRES:
            raise Refus("ordre invalide")
        return {"t": "cmd", "l": ligne, "a": 2, "o": ordre, "k": int(_nombre(m.get("k", 0), 0, 9)),
                "tc": _nombre(m.get("tc"), 0.0, 1e11)}
    if t == "pilotes":
        # pilote de chaque remontée pilotée (décidé par l'hôte) : [[ligne, identifiant du joueur]]
        d = m.get("d")
        if not isinstance(d, list) or len(d) > PILOTES_MAX:
            raise Refus("pilotes invalides")
        out = []
        for e in d:
            if not isinstance(e, list) or len(e) != 2 or not isinstance(e[0], str) or not _RE_LIGNE.match(e[0]):
                raise Refus("pilote invalide")
            out.append([e[0], int(_nombre(e[1], 0, 1e9))])
        return {"t": "pilotes", "d": out}
    if t == "corde":
        # descente à la corde (21/11/2026, « chacun son tour ») : [ligne, abscisse du véhicule, phase (0 attend,
        # 1 descend, 2 au sol)] ; en descente, ancrage, position, rotation sur soi, longueur de corde ; au sol, le
        # bilan (tours, balancement le plus fort en degrés) pour les comparaisons
        ligne = m.get("l")
        if not isinstance(ligne, str) or not _RE_LIGNE.match(ligne):
            raise Refus("ligne invalide")
        ph = int(_nombre(m.get("ph"), 0, 2))
        o = {"t": "corde", "l": ligne, "s": _nombre(m.get("s"), 0.0, 100000.0), "ph": ph,
             "tc": _nombre(m.get("tc"), 0.0, 1e11)}
        if ph == 1:
            bas = (-BORNE_XZ, BORNE_Y[0], -BORNE_XZ)
            haut = (BORNE_XZ, BORNE_Y[1], BORNE_XZ)
            o["a"] = _vec3(m.get("a"), bas, haut)
            o["p"] = _vec3(m.get("p"), bas, haut)
            o["psi"] = _nombre(m.get("psi"), -1000.0, 1000.0)
            o["lc"] = _nombre(m.get("lc"), 0.0, CORDE_MAX)
        elif ph == 2:
            o["tr"] = _nombre(m.get("tr", 0.0), 0.0, 1000.0)
            o["am"] = _nombre(m.get("am", 0.0), 0.0, 90.0)
        return o
    if t == "file":
        # (de l'hôte seulement) file de descente d'un groupe de véhicules d'une ligne : identifiants dans l'ordre
        ligne = m.get("l")
        if not isinstance(ligne, str) or not _RE_LIGNE.match(ligne):
            raise Refus("ligne invalide")
        d = m.get("d")
        if not isinstance(d, list) or len(d) > FILE_MAX:
            raise Refus("file invalide")
        return {"t": "file", "l": ligne, "d": [int(_nombre(v, 0, 1e9)) for v in d]}
    if t == "creer":
        return {"t": "creer", "nom": nom_propre(m.get("nom", "")), "c": couleur(m.get("c", [0.8, 0.2, 0.2]))}
    if t == "rejoindre":
        code = m.get("code")
        if not isinstance(code, str):
            raise Refus("code attendu")
        code = code.strip().upper().replace("-", "").replace(" ", "")
        if not _RE_CODE.match(code):
            raise Refus("code invalide")
        o = {"t": "rejoindre", "code": code, "nom": nom_propre(m.get("nom", "")),
             "c": couleur(m.get("c", [0.8, 0.2, 0.2]))}
        j = m.get("jeton")
        if isinstance(j, str) and _RE_JETON.match(j):
            o["jeton"] = j
        return o
    if t == "quitter":
        return {"t": "quitter"}
    if t == "liste":
        # salons ouverts (avant d'entrer) : rejoindre d'un bouton, sans taper de code (retour d'utilisateur du
        # 21/11/2026 : « impossible de rentrer le code, fais un truc simple »)
        return {"t": "liste"}
    raise Refus("type inconnu")


class Seau:
    """Limite de débit : seau de jetons (DEBIT_PAR_S, rafale RAFALE)."""

    def __init__(self, debit: float = DEBIT_PAR_S, rafale: float = RAFALE, horloge=time.monotonic):
        self.debit = debit
        self.rafale = rafale
        self.h = horloge
        self.niveau = rafale
        self.t = horloge()

    def prendre(self) -> bool:
        now = self.h()
        self.niveau = min(self.rafale, self.niveau + (now - self.t) * self.debit)
        self.t = now
        if self.niveau < 1.0:
            return False
        self.niveau -= 1.0
        return True


class Salon:
    def __init__(self, code: str, horloge=time.monotonic):
        self.code = code
        self.membres: dict = {}        # id → {"nom", "c", "envoi"}
        self.ordre: list = []          # ids par ordre d'arrivée (le premier est l'hôte)
        self.h = horloge
        self.cree = horloge()
        self.vide_depuis: float | None = horloge()

    @property
    def hote(self):
        return self.ordre[0] if self.ordre else None

    def entrer(self, ident, nom: str, c: list, envoi, hote: bool = False) -> None:
        if len(self.membres) >= JOUEURS_MAX:
            raise Refus("salon plein")
        self.membres[ident] = {"nom": nom, "c": c, "envoi": envoi}
        if hote:
            self.ordre.insert(0, ident)
        else:
            self.ordre.append(ident)
        self.vide_depuis = None

    def sortir(self, ident) -> None:
        self.membres.pop(ident, None)
        if ident in self.ordre:
            self.ordre.remove(ident)
        if not self.membres:
            self.vide_depuis = self.h()

    def liste(self) -> list:
        return [{"id": i, "nom": self.membres[i]["nom"], "c": self.membres[i]["c"]} for i in self.ordre]

    def autres(self, ident):
        return [m["envoi"] for i, m in self.membres.items() if i != ident]


class Registre:
    """Tous les salons ; création, entrée, expiration."""

    def __init__(self, cle: bytes, horloge=time.monotonic):
        self.cle = cle
        self.h = horloge
        self.salons: dict = {}

    def creer(self) -> Salon:
        self.purger()
        if len(self.salons) >= SALONS_MAX:
            raise Refus("trop de salons")
        for _ in range(20):
            code = nouveau_code()
            if code not in self.salons:
                s = Salon(code, self.h)
                self.salons[code] = s
                return s
        raise Refus("aucun code libre")

    def trouver(self, code: str) -> Salon:
        self.purger()
        s = self.salons.get(code)
        if s is None:
            raise Refus("salon inconnu")
        return s

    def ouverts(self) -> list:
        """Salons où l'on peut entrer (au moins un joueur, pas pleins), les plus récents d'abord : code, nom de
        l'hôte, nombre de joueurs — rien d'autre."""
        self.purger()
        out = [s for s in self.salons.values() if s.membres and len(s.membres) < JOUEURS_MAX]
        out.sort(key=lambda s: s.cree, reverse=True)
        return [{"code": s.code, "hote": s.membres[s.hote]["nom"] if s.hote in s.membres else "?",
                 "n": len(s.membres)} for s in out[:LISTE_MAX]]

    def purger(self) -> int:
        now = self.h()
        morts = [c for c, s in self.salons.items()
                 if s.vide_depuis is not None and now - s.vide_depuis > EXPIRATION_VIDE_S]
        for c in morts:
            del self.salons[c]
        return len(morts)


def sortant(m: dict, ident: int) -> str:
    """Message validé d'un joueur → texte relayé aux autres (avec son identifiant)."""
    o = dict(m)
    o["id"] = ident
    return json.dumps(o, separators=(",", ":"), ensure_ascii=False)
