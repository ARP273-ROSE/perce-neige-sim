"""Ouverture d'adresses HTTPS qui marche sur toutes les machines.

Retours d'utilisateurs (09 et 11/10/2026) : sous Manjaro, « [SSL:
CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate » (le
Python embarqué ne trouvait pas les racines de la distribution) ; sous
Windows, « certificate has expired » sur une chaîne pourtant valide (le
magasin du système proposait un chemin passant par un certificat périmé).

La cascade (magasin du système, racines de la distribution, puis certifi et
les racines ISRG embarquées, `racines_isrg.pem`) vit désormais dans le kit
commun (`reporting.ouvrir_url`, kit.json « racines_tls »), que la mise à
jour automatique utilise aussi. Ce module n'en est que le point d'entrée
pour le reste du programme (téléchargement de la musique, ancien
`autoupdate.py`). Jamais de vérification désactivée.
"""


def urlopen(req, timeout: float = 30.0):
    """urllib.request.urlopen avec le contexte du système, puis, si la
    vérification du certificat échoue, avec les racines de secours."""
    from reporting import ouvrir_url
    return ouvrir_url(req, timeout=timeout)
