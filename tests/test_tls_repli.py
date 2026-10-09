"""Repli certifi (09/10/2026, retour d'utilisateur sous Windows : « certificate verify
failed: certificate has expired » sur le serveur de la musique, à la chaîne
pourtant valide) : si la vérification échoue avec le magasin du système, on
réessaie avec le seul magasin certifi — jamais sans vérification."""
import os
import ssl
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import contexte_tls  # noqa: E402


def test_repli_certifi(monkeypatch):
    vus = []

    def faux_urlopen(req, timeout=0, context=None):
        vus.append(context)
        if len(vus) == 1:
            raise urllib.error.URLError(ssl.SSLCertVerificationError(
                1, "[SSL: CERTIFICATE_VERIFY_FAILED] certificate has expired"))
        return "ok"

    monkeypatch.setattr(urllib.request, "urlopen", faux_urlopen)
    assert contexte_tls.urlopen("https://exemple", timeout=1) == "ok"
    assert len(vus) == 2
    assert vus[1] is not None and vus[1].verify_mode == ssl.CERT_REQUIRED


def test_autre_erreur_pas_de_repli(monkeypatch):
    def faux_urlopen(req, timeout=0, context=None):
        raise urllib.error.URLError("Name or service not known")

    monkeypatch.setattr(urllib.request, "urlopen", faux_urlopen)
    try:
        contexte_tls.urlopen("https://exemple", timeout=1)
    except urllib.error.URLError as e:
        assert "Name or service" in str(e)
    else:
        raise AssertionError("erreur réseau avalée")
