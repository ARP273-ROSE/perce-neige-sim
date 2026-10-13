"""Rapport de gel : le contexte fourni par l'application accompagne la pile.

Quand l'interface est bloquée dans du code natif (fenêtre 3D d'un autre
processus, pilote…), la pile Python ne montre que `app.exec()` ; le contexte
dit alors si la fenêtre 3D répondait encore."""
import time

import reporting


def _vigie(monkeypatch, contexte):
    envois = []
    # d'autres tests remplacent time.monotonic par une horloge figée
    monkeypatch.setattr(time, "monotonic", time.perf_counter)
    monkeypatch.setattr(reporting, "envoyer",
                        lambda genre, **champs: envois.append((genre, champs)))
    v = reporting.Vigie(seuil=0.2, periode=0.05)
    v.contexte = contexte
    v.demarrer()
    v.battre()
    time.sleep(0.6)
    v.arreter()
    return [c for g, c in envois if g == "gel" and c.get("phase") == "debut"]


def test_contexte_joint_au_debut_du_gel(monkeypatch):
    debuts = _vigie(monkeypatch, lambda: {"fenetre_3d_reactive": False})
    assert len(debuts) == 1
    assert debuts[0]["contexte"] == {"fenetre_3d_reactive": False}


def test_contexte_en_erreur_ne_bloque_pas_le_rapport(monkeypatch):
    def casse():
        raise RuntimeError("boum")
    debuts = _vigie(monkeypatch, casse)
    assert len(debuts) == 1
    assert "boum" in debuts[0]["contexte"]["erreur"]
