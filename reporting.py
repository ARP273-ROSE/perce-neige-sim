"""Rapports d'incident — module commun aux applications de Kevin.

L'application est installée sur des postes que personne ne peut examiner : si
elle plante, gèle ou refuse de démarrer, il n'existe aucun moyen de le savoir
autrement. Ce module ramasse ce qui s'est passé et le dépose sur un point de
collecte, ou, à défaut de réseau, dans un fichier que l'utilisateur peut
envoyer à la main.

Ce qui est couvert :

  installation   première ouverture réussie, avec ce que la machine offre
  demarrage      preuve de vie, au plus une fois par jour
  plantage       exception Python non rattrapée (sys.excepthook)
  crash_natif    mort brutale côté Qt/C, récupérée via faulthandler
  gel            interface figée plus de N secondes, avec les piles des threads
  manuel         l'utilisateur décrit lui-même ce qui ne va pas

Trois règles gouvernent tout le module :

1. **Rien ne part sans accord.** Le consentement est demandé au premier
   lancement et peut être retiré ; sans lui, les rapports restent en local.
2. **Rien ne bloque l'application.** Tout envoi part dans un fil de fond avec
   un délai court. Un point de collecte injoignable ne doit jamais retarder le
   démarrage ni figer une fenêtre.
3. **Rien ne se perd.** Un envoi qui échoue est mis en file d'attente et
   repart au démarrage suivant. C'est indispensable : le rapport le plus
   précieux — celui d'un plantage — naît au pire moment pour le réseau.

Le module ne connaît ni PyQt ni la base de données : il doit pouvoir servir
avant que l'un ou l'autre ne soit prêt, et pendant qu'ils meurent.
"""

from __future__ import annotations

import json
import logging
import os
import platform
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request
from pathlib import Path

log = logging.getLogger(__name__)

# Point de collecte. Il est greffé sur un domaine qui a déjà son certificat et
# son passage par Cloudflare.
#
# Aucune clé secrète n'accompagne les envois, et c'est délibéré : tout secret
# embarqué dans une application téléchargeable cesse d'en être un dès la
# première installation. L'en-tête ci-dessous ne fait qu'annoncer d'où vient
# la requête, pour écarter le balayage automatique. Le serveur se protège
# autrement — il n'expose aucune lecture, borne la taille et plafonne le débit.
ENDPOINT = 'https://fenice.giff.re/rapports/collecte.php'
DELAI = 8  # secondes

# Renseignes par init() depuis kit.json : le point de collecte range les
# rapports par application, et l'en-tete X-App porte ce nom.
APPLICATION = 'application'
VERSION_APP = ''

# Au-delà, une file d'attente n'a plus de valeur de diagnostic et ne fait que
# grossir : on préfère jeter les plus vieux que remplir le disque de quelqu'un.
FILE_MAX = 50
AGE_MAX = 30 * 86400

_dossier: Path | None = None
_reglages_path: Path | None = None
_reglages: dict = {}
_verrou = threading.Lock()


# ---------------------------------------------------------------------------
# Installation du module
# ---------------------------------------------------------------------------

def init(data_dir, application=None, version=None) -> None:
    """Prépare le module. À appeler le plus tôt possible au démarrage.

    `data_dir` est le dossier de données de l'application : c'est là que vivent
    la file d'attente et le consentement. On ne passe pas par la base, qui peut
    très bien être justement ce qui ne s'ouvre pas.

    `application` et `version` sont lus dans kit.json quand on ne les fournit
    pas. Ce fichier accompagne le module dans le paquet installé ; c'est lui
    qui distingue un rapport d'AstroManager d'un rapport de MusicOthèque.
    """
    global _dossier, _reglages_path, _reglages, APPLICATION, VERSION_APP
    fiche = _lire_kit()
    APPLICATION = application or fiche.get('nom_technique') or 'application'
    VERSION_APP = version or _lire_version_fichier() or ''
    base = Path(data_dir)
    _dossier = base / '_rapports'
    _reglages_path = base / 'reglages_rapports.json'
    try:
        _dossier.mkdir(parents=True, exist_ok=True)
    except Exception:
        log.warning("File d'attente des rapports indisponible", exc_info=True)
    _reglages = _lire_reglages()


def _lire_kit() -> dict:
    """Fiche d'identite de l'application, posee a cote du module."""
    try:
        chemin = Path(__file__).resolve().parent / 'kit.json'
        return json.loads(chemin.read_text(encoding='utf-8'))
    except Exception:
        return {}


def _lire_version_fichier() -> str:
    try:
        chemin = Path(__file__).resolve().parent / 'VERSION'
        return chemin.read_text(encoding='utf-8').strip()
    except Exception:
        return ''


def _lire_reglages() -> dict:
    if _reglages_path is None or not _reglages_path.exists():
        return {}
    try:
        return json.loads(_reglages_path.read_text(encoding='utf-8'))
    except Exception:
        return {}


def _ecrire_reglages() -> None:
    if _reglages_path is None:
        return
    try:
        _reglages_path.write_text(
            json.dumps(_reglages, indent=2, ensure_ascii=False), encoding='utf-8')
    except Exception:
        log.warning("Réglages des rapports non enregistrés", exc_info=True)


def consentement() -> bool | None:
    """True, False, ou None tant que la question n'a pas été posée."""
    return _reglages.get('envoi_autorise')


def definir_consentement(accepte: bool) -> None:
    _reglages['envoi_autorise'] = bool(accepte)
    _reglages['consentement_date'] = time.strftime('%Y-%m-%d %H:%M:%S')
    _ecrire_reglages()
    log.info("Envoi des rapports %s", "autorisé" if accepte else "refusé")


# ---------------------------------------------------------------------------
# Anonymisation
# ---------------------------------------------------------------------------

def anonymiser(texte: str | None) -> str:
    """Retire ce qui identifie la machine et son propriétaire.

    Le dossier personnel devient `~`, et tout ce qui ressemble à un chemin de
    bibliothèque musicale est réduit à sa racine : les titres de morceaux d'un
    utilisateur ne regardent personne, pas même celui qui reçoit le rapport.
    """
    if not texte:
        return ''
    import re
    home = str(Path.home())
    for variante in (home.replace('\\', '/'), home, home.lower()):
        if variante:
            texte = texte.replace(variante, '~')
    # C:\Musique\Artiste\Album\03 Titre.mp3  ->  C:\Musique\…\03 Titre.mp3
    texte = re.sub(r'([A-Za-z]:\\[^\\\n"\']{1,30})(\\[^\\\n"\']{1,60}){2,}\\',
                   r'\1\\…\\', texte)
    texte = re.sub(r'(/(?:home|Users|mnt|media)/[^/\n"\']{1,30})(/[^/\n"\']{1,60}){2,}/',
                   r'\1/…/', texte)
    return texte


def _machine() -> dict:
    """Le strict nécessaire pour reproduire un problème."""
    infos = {
        'poste': platform.node() or '?',
        'os': f"{platform.system()} {platform.release()}",
        'os_detail': platform.version(),
        'arch': platform.machine(),
        'python': platform.python_version(),
    }
    infos['application'] = APPLICATION
    infos['version'] = VERSION_APP or '?'
    return infos


def extraits_journal(chemin, lignes_max: int = 40) -> str:
    """Les dernières lignes ennuyeuses du journal, anonymisées.

    On ne remonte pas le journal entier : il contient surtout des titres de
    morceaux et du bruit de lecture. Seuls les niveaux WARNING et au-delà
    disent quelque chose d'un incident.
    """
    try:
        chemin = Path(chemin)
        if not chemin.exists():
            return ''
        lignes = chemin.read_text(encoding='utf-8', errors='replace').splitlines()
    except Exception:
        return ''
    retenues = [l for l in lignes
                if any(n in l for n in ('WARNING', 'ERROR', 'CRITICAL', 'Traceback'))]
    if not retenues:
        retenues = lignes[-10:]
    return anonymiser('\n'.join(retenues[-lignes_max:]))[:6000]


# ---------------------------------------------------------------------------
# Envoi
# ---------------------------------------------------------------------------

def _poster(charge: bytes) -> bool:
    requete = urllib.request.Request(
        ENDPOINT, data=charge, method='POST',
        headers={
            'Content-Type': 'application/json; charset=utf-8',
            'X-App': f"{APPLICATION}/{VERSION_APP or '?'}",
            'User-Agent': 'rapports-kit-windows',
        })
    try:
        with urllib.request.urlopen(requete, timeout=DELAI) as r:
            return 200 <= r.status < 300
    except urllib.error.HTTPError as e:
        # 4xx : le serveur a compris et refuse. Réessayer n'y changera rien,
        # sauf pour 429 (trop de rapports cette heure-ci), qui est temporaire.
        if e.code == 429 or e.code >= 500:
            return False
        log.info("Rapport refusé par le serveur (%s)", e.code)
        return True  # inutile de le garder en file
    except Exception as e:
        log.info("Rapport non transmis : %s", e)
        return False


def _mettre_en_file(rapport: dict) -> None:
    if _dossier is None:
        return
    try:
        nom = f"{time.strftime('%Y%m%dT%H%M%S')}-{rapport.get('genre', 'autre')}-{os.getpid()}.json"
        (_dossier / nom).write_text(
            json.dumps(rapport, ensure_ascii=False), encoding='utf-8')
    except Exception:
        log.warning("Rapport perdu : mise en file impossible", exc_info=True)


def envoyer(genre: str, **champs) -> dict:
    """Constitue un rapport et le transmet, sans jamais bloquer l'appelant.

    Renvoie le rapport constitué — utile pour le repli par fichier quand
    l'utilisateur veut l'envoyer lui-même.
    """
    rapport = _machine()
    rapport['genre'] = genre
    rapport['horodatage'] = time.strftime('%Y-%m-%d %H:%M:%S')
    for cle, valeur in champs.items():
        if isinstance(valeur, str):
            valeur = anonymiser(valeur)
        rapport[cle] = valeur

    if consentement() is not True:
        # Pas d'accord : on garde quand même une trace locale, pour que le
        # bouton « Signaler un problème » ait de quoi constituer un envoi
        # manuel, et pour que rien ne soit perdu si l'accord vient plus tard.
        _mettre_en_file(rapport)
        return rapport

    charge = json.dumps(rapport, ensure_ascii=False).encode('utf-8')

    def tache():
        if not _poster(charge):
            _mettre_en_file(rapport)

    threading.Thread(target=tache, name='rapport', daemon=True).start()
    return rapport


def vider_file() -> int:
    """Renvoie les rapports restés en attente. À appeler au démarrage.

    Le réseau manque rarement au bon moment : un plantage coupe souvent
    l'application avant que l'envoi n'aboutisse. Cette reprise est donc le
    chemin normal, pas un cas dégradé.
    """
    if _dossier is None or consentement() is not True:
        return 0

    try:
        fichiers = sorted(_dossier.glob('*.json'))
    except Exception:
        return 0

    # Les plus vieux d'abord, mais on ne garde que les plus récents.
    limite = time.time() - AGE_MAX
    for vieux in fichiers[:-FILE_MAX] if len(fichiers) > FILE_MAX else []:
        vieux.unlink(missing_ok=True)
    fichiers = sorted(_dossier.glob('*.json'))

    envoyes = 0
    for f in fichiers:
        try:
            if f.stat().st_mtime < limite:
                f.unlink(missing_ok=True)
                continue
            charge = f.read_bytes()
        except Exception:
            continue
        if _poster(charge):
            f.unlink(missing_ok=True)
            envoyes += 1
        else:
            break  # réseau absent : inutile d'insister sur les suivants
    if envoyes:
        log.info("%d rapport(s) en attente transmis", envoyes)
    return envoyes


def reprendre_file_en_fond() -> None:
    """Vide la file dans un fil de fond : le démarrage ne doit rien attendre."""
    threading.Thread(target=vider_file, name='rapports-file', daemon=True).start()


# ---------------------------------------------------------------------------
# Genres particuliers
# ---------------------------------------------------------------------------

def signaler_demarrage(premier: bool = False, **champs) -> None:
    """Preuve de vie, au plus une fois par jour.

    Sans elle, le silence est ambigu : une application qui ne dit rien peut
    aussi bien tourner sans incident que ne plus démarrer du tout.
    """
    aujourdhui = time.strftime('%Y-%m-%d')
    if premier:
        envoyer('installation', **champs)
        _reglages['dernier_demarrage'] = aujourdhui
        _reglages['installee_le'] = aujourdhui
        _ecrire_reglages()
        return
    if _reglages.get('dernier_demarrage') == aujourdhui:
        return
    _reglages['dernier_demarrage'] = aujourdhui
    _ecrire_reglages()
    envoyer('demarrage', **champs)


def signaler_plantage(tb_texte: str, **champs) -> dict:
    resume = ''
    for ligne in reversed(tb_texte.strip().splitlines()):
        if ligne.strip():
            resume = ligne.strip()[:200]
            break
    return envoyer('plantage', traceback=tb_texte, resume=resume, **champs)


def relever_crash_natif(chemin_faulthandler) -> bool:
    """Ramasse la trace laissée par un crash côté C/Qt, s'il y en a une.

    Une faute de segmentation dans Qt ne passe pas par `sys.excepthook` :
    l'application disparaît, et l'utilisateur ne peut rien raconter d'autre que
    « ça s'est fermé tout seul ». `faulthandler` écrit la pile avant la mort ;
    on la retrouve au démarrage suivant.
    """
    chemin = Path(chemin_faulthandler)
    try:
        if not chemin.exists() or chemin.stat().st_size == 0:
            return False
        texte = chemin.read_text(encoding='utf-8', errors='replace')
    except Exception:
        return False
    try:
        chemin.unlink(missing_ok=True)
    except Exception:
        pass
    if not texte.strip():
        return False
    envoyer('crash_natif', trace=anonymiser(texte)[:8000],
            resume=texte.strip().splitlines()[0][:200])
    return True


# ---------------------------------------------------------------------------
# Surveillance des gels
# ---------------------------------------------------------------------------

class Vigie:
    """Détecte une interface figée et raconte ce qui la retenait.

    Le principe : le fil graphique fait battre un compteur à intervalle
    régulier. Un fil de fond, lui, regarde l'heure. Si le battement s'arrête,
    c'est que la boucle d'événements ne tourne plus — donc que la fenêtre est
    figée. On capture alors la pile de TOUS les fils : celle du fil graphique
    dit exactement quelle opération n'a pas été déportée.

    Un rapport par épisode, jamais plus : un gel de trois minutes ne doit pas
    produire trente rapports identiques.
    """

    def __init__(self, seuil: float = 10.0, periode: float = 2.0):
        self.seuil = seuil
        self.periode = periode
        self._dernier = time.monotonic()
        self._signale = False
        self._debut_gel = 0.0
        self._actif = False
        self._fil_gui = threading.get_ident()

    def battre(self) -> None:
        """À appeler depuis le fil graphique, à intervalle régulier."""
        maintenant = time.monotonic()
        if self._signale:
            duree = maintenant - self._debut_gel
            log.warning("Interface de nouveau réactive après %.0f s", duree)
            envoyer('gel', resume=f"fin du gel après {duree:.0f} s",
                    duree_s=round(duree, 1), phase='fin')
            self._signale = False
        self._dernier = maintenant

    def demarrer(self, fil_gui: int | None = None) -> None:
        self._fil_gui = fil_gui or threading.get_ident()
        self._actif = True
        threading.Thread(target=self._boucle, name='vigie', daemon=True).start()

    def arreter(self) -> None:
        self._actif = False

    def _boucle(self) -> None:
        while self._actif:
            time.sleep(self.periode)
            retard = time.monotonic() - self._dernier
            if retard >= self.seuil and not self._signale:
                self._signale = True
                self._debut_gel = self._dernier
                try:
                    envoyer('gel', resume=f"interface figée depuis {retard:.0f} s",
                            retard_s=round(retard, 1), phase='debut',
                            piles=self._piles())
                except Exception:
                    log.warning("Rapport de gel impossible", exc_info=True)

    def _piles(self) -> str:
        """Pile de chaque fil, celle du fil graphique en premier."""
        morceaux = []
        try:
            cadres = sys._current_frames()
        except Exception:
            return ''
        noms = {t.ident: t.name for t in threading.enumerate()}
        ordre = sorted(cadres, key=lambda i: i != self._fil_gui)
        for ident in ordre:
            nom = noms.get(ident, '?')
            etiquette = 'FIL GRAPHIQUE' if ident == self._fil_gui else f'fil {nom}'
            pile = ''.join(traceback.format_stack(cadres[ident])[-12:])
            morceaux.append(f"--- {etiquette} ({ident}) ---\n{pile}")
        return anonymiser('\n'.join(morceaux))[:8000]


# ---------------------------------------------------------------------------
# Repli : un fichier que l'utilisateur envoie lui-même
# ---------------------------------------------------------------------------

def paquet_local(rapport: dict, journal=None) -> Path | None:
    """Écrit un .zip sur le Bureau et renvoie son chemin.

    C'est la porte de sortie quand le point de collecte est injoignable, ou
    quand l'envoi automatique a été refusé : l'utilisateur a alors un fichier
    unique à joindre à un message, plutôt qu'une chasse au journal.
    """
    import zipfile
    bureau = Path.home() / 'Desktop'
    if not bureau.is_dir():
        bureau = Path.home() / 'Bureau'
    if not bureau.is_dir():
        bureau = Path.home()

    cible = bureau / f"{APPLICATION}-rapport-{time.strftime('%Y%m%d-%H%M%S')}.zip"
    try:
        with zipfile.ZipFile(cible, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('rapport.json',
                       json.dumps(rapport, indent=2, ensure_ascii=False))
            if journal:
                extrait = extraits_journal(journal, lignes_max=200)
                if extrait:
                    z.writestr('journal.txt', extrait)
        return cible
    except Exception:
        log.warning("Paquet local impossible", exc_info=True)
        return None
