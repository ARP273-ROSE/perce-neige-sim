"""Pack haute définition : téléchargé et installé tout seul, en arrière-plan.

Sol au mètre, photo et forêt du viewer 3D (819 Mo, données IGN, Licence Ouverte
Etalab 2.0). Il vit dans le dossier de données de l'utilisateur, hors de l'application :
les mises à jour ne le retouchent pas. Le fichier est joint à la dernière Release :
il faut donc le rejoindre à chaque nouvelle version (404 sinon, nouvel essai au lancement suivant).

Un téléchargement coupé reprend où il en était au lancement suivant. Rien n'est posé
tant que l'empreinte n'est pas vérifiée. Une panne n'empêche jamais de jouer : le viewer
garde alors son relief habituel. Le pack servira au prochain lancement du viewer.
"""
from __future__ import annotations

import hashlib
import logging
import os
import shutil
import threading
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

URL = ("https://github.com/ARP273-ROSE/perce-neige-sim/releases/latest/download/"
       "perce-neige-pack-hd.zip")
EMPREINTE = "8cbdc3ac81ff0b9d6078d556766026099c553ac86fd9043b99a602098a8171de"
TAILLE = 819410743
FICHIERS = ("relief.pnhd", "ortho.pnhd", "arbres.pnhd", "LISEZMOI.txt")
ESSAIS = 5
BLOC = 1 << 20
# en deçà, le viewer n'utilise pas le pack (voir ReliefFin.niveau_hd)
MEMOIRE_MINI_GO = 7.5
# zip + fichiers extraits, le temps de la décompression
PLACE_MINI = 2 * TAILLE + (200 << 20)


# État de l'installation, lu par le pupitre (fil de fond : valeurs simples, sans verrou)
etat: dict = {"phase": "", "fait": 0}


def texte_etat(deja_en_service: bool) -> str:
    """Ligne à afficher au pupitre, vide s'il n'y a rien à dire."""
    p = etat["phase"]
    if p == "telechargement":
        mo, total = etat["fait"] >> 20, TAILLE >> 20
        return f"Décor haute définition : téléchargement {100 * etat['fait'] // TAILLE} % ({mo} / {total} Mo)"
    if p == "pose":
        return "Décor haute définition : installation…"
    if p == "pret" and not deja_en_service:
        return "Décor haute définition prêt : relancez le simulateur pour en profiter"
    if p == "attente":
        return "Décor haute définition : téléchargement interrompu, nouvel essai au prochain lancement"
    return ""


def dossier(donnees: Path) -> Path:
    return Path(donnees) / "pack_hd"


def _marque(donnees: Path) -> Path:
    return dossier(donnees) / ".installe"


def dossier_si_pret(donnees: Path) -> Optional[Path]:
    """Le dossier du pack s'il est complet, sinon None."""
    try:
        if _marque(donnees).read_text(encoding="ascii").strip() == EMPREINTE:
            return dossier(donnees)
    except OSError:
        pass
    return None


def memoire_go() -> float:
    """Mémoire vive en Go, 0 si inconnue."""
    try:
        if os.name == "nt":
            import ctypes

            class Etat(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                            ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
            e = Etat()
            e.dwLength = ctypes.sizeof(Etat)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(e)):
                return e.ullTotalPhys / (1 << 30)
            return 0.0
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / (1 << 30)
    except (OSError, ValueError, AttributeError):
        return 0.0


def _ouvrir(requete: urllib.request.Request):
    from reporting import ouvrir_url
    return ouvrir_url(requete, timeout=60.0)


def _telecharger(partiel: Path) -> None:
    deja = partiel.stat().st_size if partiel.exists() else 0
    if deja > TAILLE:
        partiel.unlink()
        deja = 0
    if deja == TAILLE:
        return
    entetes = {"User-Agent": "perce-neige-sim"}
    if deja:
        entetes["Range"] = f"bytes={deja}-"
    with _ouvrir(urllib.request.Request(URL, headers=entetes)) as r:
        # (un serveur qui ignore la reprise renvoie tout le fichier : 200 et non 206)
        mode = "ab" if deja and r.status == 206 else "wb"
        etat["fait"] = deja if mode == "ab" else 0
        with open(partiel, mode) as f:
            while bloc := r.read(BLOC):
                f.write(bloc)
                etat["fait"] += len(bloc)


def _empreinte(chemin: Path) -> str:
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        while bloc := f.read(BLOC):
            h.update(bloc)
    return h.hexdigest()


def _poser(archive: Path, donnees: Path) -> None:
    final = dossier(donnees)
    provisoire = Path(donnees) / "pack_hd.tmp"
    shutil.rmtree(provisoire, ignore_errors=True)
    provisoire.mkdir(parents=True)
    with zipfile.ZipFile(archive) as z:
        for nom in FICHIERS:
            with z.open("pack_hd/" + nom) as src, open(provisoire / nom, "wb") as dst:
                shutil.copyfileobj(src, dst, BLOC)
    (provisoire / ".installe").write_text(EMPREINTE, encoding="ascii")
    shutil.rmtree(final, ignore_errors=True)
    os.replace(provisoire, final)


def installer(donnees: Path) -> bool:
    """Télécharge et pose le pack si besoin. Vrai si le pack est en place."""
    donnees = Path(donnees)
    if dossier_si_pret(donnees) is not None:
        return True
    memoire = memoire_go()
    if 0.0 < memoire < MEMOIRE_MINI_GO:
        log.info("Pack HD : pas d'installation, %.1f Go de mémoire", memoire)
        return False
    donnees.mkdir(parents=True, exist_ok=True)
    partiel = donnees / "pack_hd.zip.part"
    deja = partiel.stat().st_size if partiel.exists() else 0
    if shutil.disk_usage(donnees).free + deja < PLACE_MINI:
        log.info("Pack HD : pas d'installation, place insuffisante")
        return False
    etat["phase"] = "telechargement"
    etat["fait"] = deja
    for essai in range(ESSAIS):
        try:
            _telecharger(partiel)
        except (OSError, urllib.error.URLError) as e:
            log.info("Pack HD : téléchargement interrompu (essai %d) : %s", essai + 1, e)
            continue
        if partiel.stat().st_size < TAILLE:
            continue
        break
    else:
        etat["phase"] = "attente"
        return False
    etat["phase"] = "pose"
    if _empreinte(partiel) != EMPREINTE:
        log.warning("Pack HD : empreinte fausse, fichier retiré")
        partiel.unlink(missing_ok=True)
        etat["phase"] = "attente"
        return False
    try:
        _poser(partiel, donnees)
    except (OSError, zipfile.BadZipFile, KeyError) as e:
        log.warning("Pack HD : pose impossible : %s", e)
        etat["phase"] = "attente"
        return False
    partiel.unlink(missing_ok=True)
    etat["phase"] = "pret"
    log.info("Pack HD installé dans %s", dossier(donnees))
    return True


def demarrer(donnees: Path) -> None:
    """Lance l'installation en arrière-plan. Ne bloque jamais et n'échoue jamais."""
    def travail() -> None:
        try:
            installer(donnees)
        except Exception as e:  # une panne ici ne doit pas gêner le jeu
            etat["phase"] = "attente"
            log.warning("Pack HD : %s", e)
    threading.Thread(target=travail, name="pack-hd", daemon=True).start()
