# -*- coding: utf-8 -*-
"""Apparence figée et vrais explorateurs de fichiers — module commun du kit.

Deux exigences du standard des applications (14/10/2026), identiques d'une
application à l'autre, d'où un module commun posé par `poser_le_kit.py` :

1. **Style figé.** L'application impose son style Qt (« Fusion »), une
   palette COMPLÈTE (tous les rôles, y compris l'état désactivé) et ses
   polices embarquées. Rien ne dépend du thème clair/sombre du système, de sa
   couleur d'accentuation ni de ses polices : une palette partielle laissait
   Qt compléter les rôles manquants avec ceux du système, et une boîte de
   dialogue pouvait sortir blanche sur une interface sombre. Seule la mise à
   l'échelle (125 %, 150 %…) reste celle du système : la neutraliser rendrait
   le texte minuscule sur un écran 4K.

2. **Vrai explorateur de fichiers.** Sous Linux, la boîte « native » passe
   souvent par le portail XDG et se réduit à une liste sans barre latérale ni
   arborescence. On y impose la boîte complète de Qt (DontUseNativeDialog),
   avec les emplacements usuels dans la barre latérale : dossier personnel,
   Bureau, Documents, Images, Téléchargements, racine, supports montés. Sous
   Windows et macOS, la boîte du système est complète : on la garde.
   `installer_dialogues_fichiers()` remplace les quatre fonctions statiques
   de QFileDialog, si bien que TOUS les appels existants en profitent, sans
   toucher à chacun d'eux.

Usage, juste après la création de QApplication :

    import interface_kit
    interface_kit.appliquer_style(app, COULEURS, polices=Path(...)/'polices')
    interface_kit.installer_dialogues_fichiers()
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

#: rôles de palette attendus dans le dictionnaire de couleurs ; une clé absente
#: prend la valeur de la clé indiquée (repli), jamais celle du système
REPLIS = {
    'fenetre': None,             # Window
    'texte': None,               # WindowText, Text
    'base': 'fenetre',           # champs de saisie, listes
    'base_alt': 'base',          # lignes alternées
    'bouton': 'fenetre',
    'texte_bouton': 'texte',
    'selection': None,
    'texte_selection': 'texte',
    'lien': 'selection',
    'infobulle': 'base',
    'texte_infobulle': 'texte',
    'desactive': None,           # texte des éléments désactivés
    'clair': 'base',             # Light, Midlight
    'moyen': 'desactive',        # Mid
    'sombre': 'fenetre',         # Dark, Shadow
}


def _couleur(couleurs: dict, cle: str) -> str:
    vu = set()
    while cle is not None and cle not in couleurs:
        if cle in vu:
            break
        vu.add(cle)
        cle = REPLIS.get(cle)
    if cle is None or cle not in couleurs:
        raise KeyError(f"couleur manquante pour le style figé : {cle}")
    return couleurs[cle]


def palette(couleurs: dict):
    """Palette Qt complète (groupes actif, inactif ET désactivé)."""
    from PyQt6.QtGui import QColor, QPalette
    R, G = QPalette.ColorRole, QPalette.ColorGroup
    c = lambda cle: QColor(_couleur(couleurs, cle))          # noqa: E731
    p = QPalette()
    roles = {
        R.Window: 'fenetre', R.WindowText: 'texte', R.Base: 'base',
        R.AlternateBase: 'base_alt', R.Text: 'texte', R.Button: 'bouton',
        R.ButtonText: 'texte_bouton', R.Highlight: 'selection',
        R.HighlightedText: 'texte_selection', R.Link: 'lien',
        R.LinkVisited: 'lien', R.ToolTipBase: 'infobulle',
        R.ToolTipText: 'texte_infobulle', R.PlaceholderText: 'desactive',
        R.BrightText: 'texte', R.Light: 'clair', R.Midlight: 'clair',
        R.Mid: 'moyen', R.Dark: 'sombre', R.Shadow: 'sombre',
    }
    for groupe in (G.Active, G.Inactive, G.Disabled):
        for role, cle in roles.items():
            p.setColor(groupe, role, c(cle))
    for role in (R.WindowText, R.Text, R.ButtonText, R.HighlightedText):
        p.setColor(G.Disabled, role, c('desactive'))
    return p


def charger_polices(dossier) -> list[str]:
    """Charge les polices .otf/.ttf d'un dossier ; renvoie les familles."""
    from PyQt6.QtGui import QFontDatabase
    familles: list[str] = []
    if not dossier:
        return familles
    for f in sorted(Path(dossier).glob('*.[ot]tf')):
        ident = QFontDatabase.addApplicationFont(str(f))
        if ident >= 0:
            for fam in QFontDatabase.applicationFontFamilies(ident):
                if fam not in familles:
                    familles.append(fam)
    return familles


def appliquer_style(app, couleurs: dict, polices=None, famille: str | None = None,
                    taille: float = 10.0, feuille: str = '', sombre: bool | None = None):
    """Impose Fusion, la palette complète, la police embarquée et la feuille de
    style de l'application. `sombre` : schéma annoncé à Qt (6.8+) pour que les
    éléments dessinés par la plateforme suivent l'application, pas le système ;
    par défaut, déduit de la clarté de la couleur de fenêtre."""
    from PyQt6.QtGui import QColor, QFont
    app.setStyle('Fusion')
    if sombre is None:
        sombre = QColor(_couleur(couleurs, 'fenetre')).lightness() < 128
    try:
        from PyQt6.QtCore import Qt
        schema = Qt.ColorScheme.Dark if sombre else Qt.ColorScheme.Light
        app.styleHints().setColorScheme(schema)
    except Exception:
        pass                                   # Qt < 6.8 : sans objet
    app.setPalette(palette(couleurs))
    familles = charger_polices(polices)
    choix = famille if (famille and famille in familles) else (familles[0] if familles else None)
    if choix:
        police = QFont(choix)
        police.setPointSizeF(taille)
        app.setFont(police)
    if feuille:
        app.setStyleSheet(feuille)
    return choix


# ---------------------------------------------------------------------------
# Dialogues de fichiers
# ---------------------------------------------------------------------------

def dialogue_qt_impose() -> bool:
    """Vrai là où la boîte du système est réduite : Linux (portail XDG).
    KIT_DIALOGUES=qt / systeme force l'un ou l'autre (dépannage, tests)."""
    choix = os.environ.get('KIT_DIALOGUES', '').strip().lower()
    if choix in ('qt', 'systeme', 'système'):
        return choix == 'qt'
    return sys.platform.startswith('linux')


def emplacements() -> list[str]:
    """Barre latérale : dossier personnel, Bureau, Documents, Images,
    Téléchargements, racine, puis les supports montés (/media, /run/media,
    /mnt, /Volumes)."""
    from PyQt6.QtCore import QStandardPaths
    L = QStandardPaths.StandardLocation
    sortie: list[str] = []
    for lieu in (L.HomeLocation, L.DesktopLocation, L.DocumentsLocation,
                 L.PicturesLocation, L.DownloadLocation):
        p = QStandardPaths.writableLocation(lieu)
        if p and os.path.isdir(p) and p not in sortie:
            sortie.append(p)
    if os.name != 'nt':
        sortie.append('/')
    for racine in ('/media', f'/run/media/{os.environ.get("USER", "")}', '/mnt', '/Volumes'):
        try:
            for nom in sorted(os.listdir(racine)):
                p = os.path.join(racine, nom)
                if os.path.isdir(p) and p not in sortie:
                    sortie.append(p)
        except OSError:
            continue
    return sortie


def _depart(depart: str) -> str:
    """Dossier de départ existant (le plus proche parent existant) ; un nom de
    fichier proposé à l'enregistrement est conservé."""
    if not depart:
        return os.path.expanduser('~')
    p = os.path.abspath(os.path.expanduser(depart))
    if os.path.isdir(p) or os.path.isdir(os.path.dirname(p)):
        return p
    while p and not os.path.isdir(p):
        parent = os.path.dirname(p)
        if parent == p:
            return os.path.expanduser('~')
        p = parent
    return p


def _boite(parent, titre, depart, filtre, mode, options=None):
    from PyQt6.QtCore import QUrl
    from PyQt6.QtWidgets import QDialog, QFileDialog
    d = QFileDialog(parent, titre or '', _depart(depart or ''), filtre or '')
    if options is not None:
        d.setOptions(options)
    d.setOption(QFileDialog.Option.DontUseNativeDialog, True)
    if mode == 'dossier':
        d.setFileMode(QFileDialog.FileMode.Directory)
        d.setOption(QFileDialog.Option.ShowDirsOnly, True)
    elif mode == 'ouvrir':
        d.setFileMode(QFileDialog.FileMode.ExistingFile)
    elif mode == 'ouvrir_plusieurs':
        d.setFileMode(QFileDialog.FileMode.ExistingFiles)
    else:
        d.setAcceptMode(QFileDialog.AcceptMode.AcceptSave)
        d.setFileMode(QFileDialog.FileMode.AnyFile)
    d.setSidebarUrls([QUrl.fromLocalFile(p) for p in emplacements()])
    try:
        if d.exec() != QDialog.DialogCode.Accepted:
            return [], ''
        return d.selectedFiles(), d.selectedNameFilter()
    finally:
        d.deleteLater()


def _args(args, kwargs, noms):
    valeurs = dict(zip(noms, args))
    valeurs.update(kwargs)
    return valeurs


_ORIGINAUX: dict = {}


def installer_dialogues_fichiers() -> bool:
    """Remplace les fonctions statiques de QFileDialog par la boîte complète
    de Qt, là où la boîte du système est réduite. Renvoie True si installé."""
    from PyQt6.QtWidgets import QFileDialog
    if not dialogue_qt_impose():
        return False
    if _ORIGINAUX:
        return True
    noms_fichier = ('parent', 'caption', 'directory', 'filter', 'initialFilter', 'options')
    noms_dossier = ('parent', 'caption', 'directory', 'options')

    def ouvrir(*a, **k):
        v = _args(a, k, noms_fichier)
        f, filtre = _boite(v.get('parent'), v.get('caption'), v.get('directory'),
                           v.get('filter'), 'ouvrir', v.get('options'))
        return (f[0] if f else ''), filtre

    def ouvrir_plusieurs(*a, **k):
        v = _args(a, k, noms_fichier)
        return _boite(v.get('parent'), v.get('caption'), v.get('directory'),
                      v.get('filter'), 'ouvrir_plusieurs', v.get('options'))

    def enregistrer(*a, **k):
        v = _args(a, k, noms_fichier)
        f, filtre = _boite(v.get('parent'), v.get('caption'), v.get('directory'),
                           v.get('filter'), 'enregistrer', v.get('options'))
        return (f[0] if f else ''), filtre

    def dossier(*a, **k):
        v = _args(a, k, noms_dossier)
        f, _ = _boite(v.get('parent'), v.get('caption'), v.get('directory'),
                      '', 'dossier', v.get('options'))
        return f[0] if f else ''

    for nom, fn in (('getOpenFileName', ouvrir), ('getOpenFileNames', ouvrir_plusieurs),
                    ('getSaveFileName', enregistrer), ('getExistingDirectory', dossier)):
        _ORIGINAUX[nom] = getattr(QFileDialog, nom)
        setattr(QFileDialog, nom, staticmethod(fn))
    return True


# ---------------------------------------------------------------------------
# Manuel PDF
# ---------------------------------------------------------------------------

def ouvrir_manuel(dossiers, langue: str, nom: str = 'manuel-{langue}.pdf') -> bool:
    """Ouvre le manuel PDF dans la langue de l'interface (repli : l'autre
    langue) avec la visionneuse du système. Renvoie False s'il est absent."""
    from PyQt6.QtCore import QUrl
    from PyQt6.QtGui import QDesktopServices
    autres = [lg for lg in ('fr', 'en') if lg != langue]
    for lg in [langue] + autres:
        for d in dossiers:
            chemin = Path(d) / nom.format(langue=lg)
            if chemin.is_file():
                return bool(QDesktopServices.openUrl(QUrl.fromLocalFile(str(chemin))))
    return False
