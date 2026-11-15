# -*- coding: utf-8 -*-
"""Pupitre des remontées (hors Perce-Neige) : modèle côté PC de la télémesure envoyée par la vue 3D,
commandes à lui renvoyer, et un faux émetteur pour travailler sans la 3D.

Protocole (W:/_cuites/chantier_pupitres/SPEC.md) :
- 3D → PC, ~5 fois/s : {"remontee": {...}} ou {"remontee": null} quand on s'éloigne de toute ligne ;
  catalogue des pannes ({id, nom, gravite}, catalogue_v), journal "evts" [[n, t, genre, texte]] (8 derniers),
  "ack" : dernier numéro de commande traité pour cette ligne.
- PC → 3D, dans le paquet d'état : "remontee_cmd": [[id, n, commande, argument], ...] ; le PC renvoie
  ses commandes tant qu'elles ne sont pas acquittées (1,5 s au plus).

Aucune dépendance à Qt : le dessin du pupitre est dans perce_neige_sim.py (style du pupitre du PN).
"""
from __future__ import annotations

import json
import math
import random
import time

GROUPES = ("tsd", "tsf", "tcd", "tk", "tkd", "tph", "3s", "funival")
# commandes « de conduite » : elles passent la ligne en manuel (la 3D le fait ; le PC l'affiche tout de suite)
COMMANDES_CONDUITE = ("demarrer", "arreter", "cran", "secours", "portes", "evacuer")


def groupe_a_portes(g: str) -> bool:
    return g in ("tcd", "tph", "3s", "funival")


def groupe_va_et_vient(g: str) -> bool:
    return g in ("tph", "funival")


def groupe_evacuation(g: str) -> bool:
    return g not in ("tk", "tkd")


class ModeleRemontee:
    """Dernière télémesure reçue, journal, commandes en attente d'acquittement."""

    PERIME_S = 2.0          # sans paquet depuis : plus de pupitre de remontée
    RENVOI_S = 1.5          # une commande non acquittée est renvoyée jusque-là

    def __init__(self) -> None:
        self.d: dict | None = None
        self.t_recu = -1e9
        self.catalogue: dict[str, list] = {}      # id de ligne → [{id, nom, gravite}]
        self.catalogue_v: dict[str, object] = {}
        self._evts_vus: dict[str, int] = {}       # id de ligne → dernier n journalisé
        self._n = int(time.time() * 10) % 1_000_000   # numéros croissants, propres à la séance
        self._attente: list[list] = []            # [id, n, cmd, arg, t]
        self.paquets = 0
        self.octets_max = 0
        self.version = 0                          # avance quand ce qui est affiché peut avoir changé

    # --- réception ---
    def recevoir(self, d: dict | None, maintenant: float | None = None, octets: int = 0) -> list:
        """Télémesure reçue ; rend les événements nouveaux du journal [(genre, texte, nom de la ligne)]."""
        maintenant = time.monotonic() if maintenant is None else maintenant
        self.paquets += 1
        self.octets_max = max(self.octets_max, octets)
        if not isinstance(d, dict) or not d.get("id"):
            if self.d is not None:
                self.version += 1
            self.d = None
            return []
        if d != self.d:
            # (paquet identique au précédent : rien à redessiner)
            self.version += 1
        self.d = d
        self.t_recu = maintenant
        lid = str(d["id"])
        if isinstance(d.get("catalogue"), list):
            self.catalogue[lid] = [c for c in d["catalogue"] if isinstance(c, dict) and c.get("id")]
            self.catalogue_v[lid] = d.get("catalogue_v")
        ack = d.get("ack")
        if isinstance(ack, (int, float)):
            self._attente = [c for c in self._attente if not (c[0] == lid and c[1] <= int(ack))]
        nouveaux = []
        vu = self._evts_vus.get(lid)
        evts = [e for e in (d.get("evts") or []) if isinstance(e, (list, tuple)) and len(e) >= 4]
        evts.sort(key=lambda e: e[0])
        if vu is None:
            # arrivée sur la ligne : on ne rejoue pas son passé, sauf le tout dernier événement
            self._evts_vus[lid] = int(evts[-1][0]) if evts else 0
            return []
        for e in evts:
            if int(e[0]) > vu:
                nouveaux.append((str(e[2]), str(e[3]), str(d.get("nom", lid))))
                vu = int(e[0])
        self._evts_vus[lid] = vu
        return nouveaux

    def actif(self, maintenant: float | None = None) -> bool:
        maintenant = time.monotonic() if maintenant is None else maintenant
        return self.d is not None and maintenant - self.t_recu < self.PERIME_S

    def catalogue_courant(self) -> list:
        return self.catalogue.get(str(self.d["id"]), []) if self.d else []

    # --- commandes ---
    def commander(self, cmd: str, arg=None, maintenant: float | None = None) -> None:
        if not self.d:
            return
        maintenant = time.monotonic() if maintenant is None else maintenant
        self._n += 1
        self._attente.append([str(self.d["id"]), self._n, cmd, arg, maintenant])
        self.version += 1
        # retour immédiat à l'écran (la télémesure confirmera)
        if cmd in COMMANDES_CONDUITE:
            self.d["mode"] = "manuel"
        elif cmd == "mode":
            self.d["mode"] = arg

    def a_envoyer(self, maintenant: float | None = None) -> list:
        maintenant = time.monotonic() if maintenant is None else maintenant
        self._attente = [c for c in self._attente if maintenant - c[4] < self.RENVOI_S]
        return [[c[0], c[1], c[2], c[3]] for c in self._attente]

    def en_attente(self) -> int:
        return len(self._attente)


# ---------------------------------------------------------------------------------------------------
# Faux émetteur : une ligne simulée, au protocole de la SPEC, pour développer sans la 3D.
# ---------------------------------------------------------------------------------------------------

_LIGNES = {
    "tsd": ("tsd6_bollin", "Bollin", "Doppelmayr 6 places débrayable", 6, 92, 5.0, ["PETITE", "MOYENNE", "GRANDE"], 700),
    "tsf": ("tsf4_rosset", "Rosset", "Poma 4 places à pince fixe", 4, 46, 2.3, ["LENTE", "NORMALE"], 250),
    "tcd": ("tcd10_solaise", "Solaise", "Doppelmayr 10 places", 10, 95, 6.0, ["PETITE", "MOYENNE", "GRANDE"], 900),
    "tk": ("tke_legettaz", "Le Gettaz", "Téléski à enrouleurs", 1, 56, 3.0, ["LENTE", "NORMALE"], 90),
    "tkd": ("tkd_col_du_palet", "Col du Palet", "Téléski débrayable", 1, 70, 3.5, ["LENTE", "NORMALE", "RAPIDE"], 120),
    "tph": ("tph_fornet", "Fornet", "Téléphérique va-et-vient 2 × 80", 80, 2, 10.0, ["PETITE", "MOYENNE", "GRANDE"], 1100),
    "3s": ("olympique", "Olympique 3S", "Tricâble débrayable 30 places", 30, 24, 7.0, ["PETITE", "MOYENNE", "GRANDE"], 1500),
    "funival": ("funival", "Funival", "Funiculaire 2 × 270 places", 270, 2, 12.0, ["PETITE", "MOYENNE", "GRANDE"], 2400),
}

# id, gravité, groupes (None = tous), nom, quoi, à faire, interdit
_PANNES = [
    ("vent_fort", "degrade", None, "Vent fort",
     "Rafales au-delà du seuil en ligne : vitesse plafonnée.",
     "Réduire au petit cran, surveiller l'anémomètre, fermer si le vent monte encore.",
     "Ne pas repasser au grand cran tant que le voyant VENT est allumé."),
    ("deraillement_cable", "arret", None, "Déraillement du câble",
     "Le câble est sorti d'un galet au pylône 7 (détecteur de sécurité de ligne).",
     "Arrêt, reposer le câble avec l'équipe de ligne, réarmer la sécurité, puis redémarrer.",
     "Ne pas redémarrer avant le contrôle visuel du pylône."),
    ("defaut_pince", "arret", ("tsd", "tcd", "tkd", "3s"), "Défaut de pince",
     "Effort de serrage insuffisant mesuré au contrôle de pince en gare.",
     "Arrêt, sortir le véhicule en garage, réarmer, redémarrer.",
     "Ne pas faire repartir le véhicule en ligne."),
    ("coupure_reseau", "arret", None, "Coupure du réseau",
     "Plus de tension sur le moteur principal.",
     "Basculer sur le moteur thermique de secours (SECOURS), vider la ligne à petite vitesse.",
     "Ne pas embarquer de nouveaux passagers."),
    ("portes", "arret", ("tcd", "tph", "3s", "funival"), "Défaut de portes",
     "Une porte n'est pas verrouillée au départ.",
     "Rouvrir puis refermer les portes, vérifier le verrouillage, réarmer.",
     "Ne pas forcer le départ portes ouvertes."),
    ("frein_urgence", "grave", None, "Frein d'urgence déclenché",
     "Le frein d'urgence est tombé sur survitesse de la poulie.",
     "Arrêt d'urgence maintenu : évacuer la ligne, ligne hors service jusqu'à la nouvelle exploitation.",
     "Ne pas réarmer sans l'expertise du frein."),
    ("moteur_chaud", "avis", None, "Moteur chaud",
     "Température du moteur principal élevée.",
     "Surveiller, passer au cran inférieur si elle monte encore.",
     "Ne pas couper la ventilation."),
    ("perche_coincee", "arret", ("tk", "tkd"), "Perche coincée",
     "Une perche ne s'est pas enroulée à l'arrivée.",
     "Arrêt, dégager la perche, réarmer, redémarrer.",
     "Ne pas redémarrer avec la perche en travers de la trace."),
]


class FauxEmetteur:
    """Une ligne simulée de la famille `groupe`. tick(dt, commandes) → télémesure (dict, déjà passée par JSON)."""

    def __init__(self, groupe: str, lang: str = "fr", graine: int = 7) -> None:
        self.g = groupe if groupe in _LIGNES else "tsd"
        self.lang = lang
        self.rng = random.Random(graine)
        lid, nom, desc, places, nveh, vnom, crans, kwmax = _LIGNES[self.g]
        self.lid, self.nom, self.desc, self.places, self.nveh = lid, nom, desc, places, nveh
        self.v_nom, self.crans, self.kw_max = vnom, crans, kwmax
        self.mode = "auto"
        self.etat = "marche"
        self.cran = len(crans) - 1
        self.v = vnom
        self.secours = False
        self.portes = "fermees" if groupe_a_portes(self.g) else None
        self.pannes: list[dict] = []
        self.hors_service = False
        self.evts: list[list] = []
        self._n_evt = 0
        self.ack = 0
        self.t = 0.0
        self.vent = 4.0
        self._t_redemarrage = -1.0
        self._t_cat = 99.0
        self.catalogue = [{"id": p[0], "nom": p[3], "gravite": p[1]} for p in _PANNES
                          if p[2] is None or self.g in p[2]]
        self.catalogue_v = 1
        # va-et-vient : position de la cabine 1 sur la ligne (0..1), la 2 en face
        self.x = 0.15
        self.sens = 1
        self.portes_pilotables = groupe_va_et_vient(self.g)
        self.a_quai = False
        self.refus = ""
        self._quai_t = 0.0

    # --- journal ---
    def _evt(self, genre: str, texte: str) -> None:
        self._n_evt += 1
        self.evts.append([self._n_evt, round(self.t, 1), genre, texte])
        self.evts = self.evts[-8:]

    # --- commandes ---
    def _commande(self, cmd: str, arg) -> None:
        conduite = cmd in COMMANDES_CONDUITE
        if conduite and self.mode != "manuel":
            self.mode = "manuel"
            self._evt("commande", "Passage en conduite manuelle")
        if cmd == "mode":
            self.mode = "auto" if arg == "auto" else "manuel"
            self._evt("commande", "Mode automatique" if self.mode == "auto" else "Mode manuel")
        elif cmd == "demarrer":
            if self.portes_pilotables and self.portes == "ouvertes":
                self.refus = "portes ouvertes"
                self._evt("alerte", "Départ refusé : portes ouvertes")
            elif self.hors_service:
                self._evt("alerte", "Démarrage refusé : ligne hors service")
            elif self.etat in ("urgence",) or any(p["gravite"] in ("arret", "grave") and p["phase"] == "active" for p in self.pannes):
                self._evt("alerte", "Démarrage refusé : défaut non réarmé")
            else:
                self.refus = ""
                if self.a_quai and groupe_va_et_vient(self.g):
                    self.sens = 1 if self.x <= 0.0 else -1
                    self.x += self.sens * 0.001
                self.etat = "marche"
                self._evt("commande", "Démarrage")
        elif cmd == "arreter":
            if self.etat == "marche":
                self.etat = "arret_normal"
                self._evt("commande", "Arrêt normal")
        elif cmd == "urgence":
            self.etat = "urgence"
            self._evt("alerte", "ARRÊT D'URGENCE")
        elif cmd == "rearmer":
            actives = [p for p in self.pannes if p["phase"] == "active"]
            if any(p["gravite"] == "grave" for p in actives):
                self._evt("alerte", "Réarmement refusé : panne grave (évacuation, puis nouvelle exploitation)")
            elif any(p["gravite"] == "arret" for p in actives):
                self._evt("alerte", "Réarmement refusé : traiter d'abord la panne")
            else:
                if self.etat in ("urgence", "arret"):
                    self.etat = "arret_normal"
                self._evt("info", "Sécurités réarmées")
        elif cmd == "cran":
            try:
                self.cran = max(0, min(len(self.crans) - 1, int(arg)))
            except (TypeError, ValueError):
                return
            self._evt("commande", f"Vitesse : {self.crans[self.cran]}")
        elif cmd == "panne":
            self._declencher(str(arg))
        elif cmd == "panne_hasard":
            self._declencher(self.rng.choice(self.catalogue)["id"])
        elif cmd == "acquitter":
            for p in self.pannes:
                if p["id"] == arg and p["phase"] == "active" and p["gravite"] != "grave":
                    p["phase"] = "traitee"
                    self._evt("fin_panne", f"Panne traitée : {p['nom']}")
            self.pannes = [p for p in self.pannes if p["phase"] == "active"]
        elif cmd == "portes" and self.portes is not None:
            if not self.portes_pilotables:
                self._evt("alerte", "Portes automatiques : pas de commande")
            elif not self.a_quai or self.v > 0.05:
                self._evt("alerte", "Portes : véhicule hors quai")
            else:
                self.portes = "ouvertes" if arg == "ouvrir" else "fermees"
                self._evt("commande", "Portes ouvertes" if self.portes == "ouvertes" else "Portes fermées")
        elif cmd == "secours":
            self.secours = not self.secours
            self._evt("commande", "Moteur de secours en service" if self.secours else "Retour au moteur principal")
        elif cmd == "evacuer":
            self._evt("alerte", "Évacuation de la ligne lancée")
        elif cmd == "remise_service":
            self.hors_service = False
            self.pannes = []
            self.etat = "arret_normal"
            self._evt("info", "Nouvelle exploitation : ligne remise en service")

    def _declencher(self, pid: str) -> None:
        for p in _PANNES:
            if p[0] == pid:
                if any(q["id"] == pid for q in self.pannes):
                    return
                self.pannes.append({"id": p[0], "gravite": p[1], "nom": p[3], "quoi": p[4], "faire": p[5],
                                    "interdit": p[6], "phase": "active", "t": round(self.t, 1)})
                self._evt("panne", f"Panne : {p[3]}")
                if p[1] == "arret":
                    self.etat = "arret"
                elif p[1] == "grave":
                    self.etat = "urgence"
                    self.hors_service = True
                if p[0] == "vent_fort":
                    self.vent = 17.0
                return

    # --- pas de temps ---
    def tick(self, dt: float, commandes: list) -> dict:
        self.t += dt
        for c in commandes:
            if len(c) >= 4 and c[0] == self.lid and int(c[1]) > self.ack:
                self.ack = int(c[1])
                self._commande(str(c[2]), c[3])
        # mode auto : réarme et redémarre seul une panne « arrêt » (délai), pannes rares au hasard
        if self.mode == "auto":
            actives = [p for p in self.pannes if p["phase"] == "active"]
            if self.etat in ("arret", "arret_normal") and not self.hors_service:
                if self._t_redemarrage < 0:
                    self._t_redemarrage = self.t + 8.0
                elif self.t >= self._t_redemarrage:
                    for p in actives:
                        if p["gravite"] == "arret":
                            p["phase"] = "traitee"
                            self._evt("fin_panne", f"Panne traitée (auto) : {p['nom']}")
                    self.pannes = [p for p in self.pannes if p["phase"] == "active"]
                    self.etat = "marche"
                    self._evt("info", "Redémarrage automatique")
                    self._t_redemarrage = -1.0
            else:
                self._t_redemarrage = -1.0
            if self.rng.random() < dt / 900.0:
                self._declencher(self.rng.choice(self.catalogue)["id"])
            if any(p["id"] == "coupure_reseau" and p["phase"] == "active" for p in self.pannes) and not self.secours:
                self.secours = True
                self._evt("info", "Bascule automatique sur le moteur de secours")
        # vitesse
        plafond = self.v_nom * (0.5 + 0.5 * self.cran / max(1, len(self.crans) - 1))
        if any(p["gravite"] == "degrade" and p["phase"] == "active" for p in self.pannes):
            plafond = min(plafond, self.v_nom * 0.5)
        if self.secours:
            plafond = min(plafond, self.v_nom * 0.3)
        cible = plafond if self.etat == "marche" else 0.0
        acc = 0.4 if self.etat in ("marche", "arret_normal") else 1.2
        self.v += max(-acc * dt, min(acc * dt, cible - self.v))
        self.v = max(0.0, self.v)
        self.vent += (self.rng.uniform(-0.6, 0.6) + (5.0 - self.vent) * 0.02) * dt * 5
        vv = None
        if groupe_va_et_vient(self.g):
            self.x += self.sens * self.v * dt / 2000.0
            quai = [self.x <= 0.0 or self.x >= 1.0, self.x <= 0.0 or self.x >= 1.0]
            self.a_quai = quai[0]
            if self.x >= 1.0 or self.x <= 0.0:
                self.x = min(1.0, max(0.0, self.x))
                if self.mode != "auto" and self.etat == "marche":
                    # manuel : arrivé à quai, le véhicule attend, portes fermées
                    self.etat = "arret_normal"
                    self.v = 0.0
                if self.mode == "auto" and self.etat == "marche":
                    self._quai_t += dt
                    self.portes = "ouvertes" if 3.0 < self._quai_t < 15.0 else "fermees"
                    if self._quai_t > 18.0:
                        self.sens = -self.sens
                        self.x += self.sens * 0.001
                        self._quai_t = 0.0
            vv = {"pos": [round(self.x, 4), round(1.0 - self.x, 4)], "v": [round(self.v * self.sens, 2), round(-self.v * self.sens, 2)],
                  "quai": quai, "sens": self.sens, "portes": [self.portes, self.portes]}
        actives = [p for p in self.pannes if p["phase"] == "active"]
        ids = {p["id"] for p in actives}
        d = {
            "id": self.lid, "nom": self.nom, "groupe": self.g, "desc": self.desc, "places": self.places,
            "vehicules": self.nveh, "v_nom": self.v_nom, "v": round(self.v, 2),
            "v_consigne": round(cible, 2), "cran": self.cran, "crans": self.crans,
            "etat": self.etat, "mode": self.mode, "kw": round(self.kw_max * 0.15 + self.kw_max * 0.7 * self.v / self.v_nom),
            "kw_max": 0, "portes_pilotables": self.portes_pilotables, "a_quai": self.a_quai,
            "refus_depart": self.refus, "frein_service": self.etat != "marche" and self.v < 0.05,
            "frein_urgence": self.etat == "urgence", "vent": round(self.vent, 1), "portes": self.portes,
            "a_bord": False, "secours": self.secours, "hors_service": self.hors_service,
            "voyants": {"cable": "deraillement_cable" in ids, "pince": "defaut_pince" in ids,
                        "vent": self.vent > 12.0, "secu_ligne": "deraillement_cable" in ids or "perche_coincee" in ids,
                        "moteur": "moteur_chaud" in ids or "coupure_reseau" in ids, "frein": "frein_urgence" in ids,
                        "portes": "portes" in ids},
            "pannes": [{**{k: p[k] for k in ("id", "gravite", "nom", "quoi", "faire", "interdit", "phase", "t")},
                        "acquittable": p["phase"] == "active" and p["gravite"] != "grave", "reste": -1}
                       for p in self.pannes],
            "secours_possible": "coupure_reseau" in ids or self.secours,
            "va_et_vient": vv, "evts": self.evts, "ack": self.ack,
        }
        self._t_cat += dt
        if self._t_cat >= 5.0:
            self._t_cat = 0.0
            d["catalogue"] = self.catalogue
            d["catalogue_v"] = self.catalogue_v
        # (le vrai chemin : une ligne JSON, au plus 8 Ko)
        brut = json.dumps({"remontee": d}, ensure_ascii=False, separators=(",", ":"))
        self.octets = len(brut.encode("utf-8"))
        return json.loads(brut)["remontee"]
