"""Aucun texte affiché en dur : tout libellé de l'interface passe par T(),
_tr(), ou un choix explicite selon la langue (« … if fr else … »,
« if lang == "fr": … else: … »). Et aucun français dans l'interface anglaise.

Standard des applications (14/10/2026) : l'interface est bilingue FR/EN,
langue du système au premier lancement, choix retenu (touche L, menu
Affichage → Langue). Ce test lit le code (AST) : il attrape le libellé
ajouté sans traduction avant qu'un utilisateur anglophone ne le voie.

Exécution : pytest tests/test_textes_en_dur.py -v
"""
import ast
import re
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SOURCE = RACINE / "perce_neige_sim.py"

#: méthodes et constructeurs Qt qui AFFICHENT leur argument texte
AFFICHAGE = {
    "setText", "setWindowTitle", "addAction", "addMenu", "setToolTip",
    "setInformativeText", "setDetailedText", "addButton", "setPlaceholderText",
    "setLabelText", "drawText", "addTab", "setHorizontalHeaderLabels",
    "QLabel", "QPushButton", "QCheckBox", "QAction", "information", "warning",
    "question", "critical", "about", "QProgressDialog", "setStatusTip",
    "showMessage", "setTitle", "setHeaderLabels", "QGroupBox", "QTableWidgetItem",
}
TRADUCTION = {"T", "_tr"}

#: textes identiques dans les deux langues, ou reproductions de plaques et
#: d'écrans RÉELS de la machine (pupitre, écran Pro-face, livrée de la rame)
#: — le décor du simulateur, pas son interface
NEUTRES = {
    "STOP", "PERCE-NEIGE", "ALTITUDE EXPERIENCE", "💥 COLLISION",
    "VOITURE AVAL", "POSTE 1", "POSTE 2", "PORTES 1+8", "PORTES 7+10",
    "FREINS", "ÉCLAIRAGE", "Val Claret —  m", "v   fps", "⌀ 4.2 m    rpm   v  m/s",
    "<a href='https://github.com/", "/'>GitHub</a>",
    "<a href='https://funiculaire.giff.re'>funiculaire.giff.re</a>",
}

#: mots français admis dans un texte anglais : noms propres et libellés
#: d'origine de la machine réelle
FRANCAIS_ADMIS = {"Transtélé", "MONTÉE"}


def _nom(f):
    if isinstance(f, ast.Attribute):
        return f.attr
    return f.id if isinstance(f, ast.Name) else ""


def _selon_langue(test) -> bool:
    return bool(re.search(r"\bfr\b|LANG|lang", ast.unparse(test)))


def _litteraux(n):
    """Les chaînes littérales affichées telles quelles (hors traduction)."""
    if isinstance(n, ast.Call) and _nom(n.func) in TRADUCTION:
        return
    if isinstance(n, ast.IfExp) and _selon_langue(n.test):
        return
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
        yield n.value
        return
    if isinstance(n, ast.JoinedStr):
        yield "".join(v.value for v in n.values if isinstance(v, ast.Constant))
        return
    for c in ast.iter_child_nodes(n):
        yield from _litteraux(c)


def _lignes_selon_langue(arbre) -> set:
    """Lignes des blocs « if lang == "fr": … else: … »."""
    lignes = set()
    for n in ast.walk(arbre):
        if isinstance(n, ast.If) and _selon_langue(n.test):
            for bloc in (n.body, n.orelse):
                for s in bloc:
                    lignes.update(range(s.lineno, (s.end_lineno or s.lineno) + 1))
    return lignes


def test_aucun_texte_affiche_en_dur():
    arbre = ast.parse(SOURCE.read_text(encoding="utf-8"))
    bilingues = _lignes_selon_langue(arbre)
    fautes = []
    for n in ast.walk(arbre):
        if not (isinstance(n, ast.Call) and _nom(n.func) in AFFICHAGE):
            continue
        if n.lineno in bilingues:
            continue
        for arg in list(n.args) + [k.value for k in n.keywords]:
            for texte in _litteraux(arg):
                if re.search(r"[A-Za-zÀ-ÿ]{3,}", texte) and texte not in NEUTRES:
                    fautes.append(f"ligne {n.lineno} ({_nom(n.func)}) : {texte[:60]!r}")
    assert not fautes, "textes affichés sans traduction :\n" + "\n".join(fautes)


def _texte(n) -> str:
    return "".join(s.value for s in ast.walk(n)
                   if isinstance(s, ast.Constant) and isinstance(s.value, str))


def test_pas_de_francais_dans_l_anglais():
    """Premier argument de T()/_tr() (et texte anglais d'add_event) : pas
    d'accent ni de mot-outil français."""
    arbre = ast.parse(SOURCE.read_text(encoding="utf-8"))
    motif = re.compile(r"[éèàùçêâôîûÉÈÀÊ]|\b(le|la|les|des|une|du|et|pour|avec|vers|dans)\b")
    fautes = []
    for n in ast.walk(arbre):
        if not isinstance(n, ast.Call):
            continue
        anglais = None
        if _nom(n.func) in TRADUCTION and len(n.args) >= 2:
            anglais = _texte(n.args[0])
        elif _nom(n.func) == "add_event" and len(n.args) >= 3:
            anglais = _texte(n.args[1])
        if not anglais:
            continue
        for mot in FRANCAIS_ADMIS:
            anglais = anglais.replace(mot, "")
        if motif.search(anglais):
            fautes.append(f"ligne {n.lineno} : {anglais[:70]!r}")
    assert not fautes, "français dans l'interface anglaise :\n" + "\n".join(fautes)


def test_langue_retenue(monkeypatch):
    """Le choix de l'utilisateur l'emporte sur la langue du système."""
    import sys
    sys.path.insert(0, str(RACINE))
    import perce_neige_sim as pn
    monkeypatch.setattr(pn, "_lire_prefs", lambda: {"langue": "en"})
    monkeypatch.setenv("LANG", "fr_FR.UTF-8")
    assert pn._detect_lang() == "en"
    monkeypatch.setattr(pn, "_lire_prefs", lambda: {"langue": "fr"})
    monkeypatch.setenv("LANG", "en_US.UTF-8")
    assert pn._detect_lang() == "fr"
    monkeypatch.setattr(pn, "_lire_prefs", lambda: {})
    monkeypatch.setattr(pn.locale, "getlocale", lambda *a: ("fr_FR", "UTF-8"))
    assert pn._detect_lang() == "fr"
