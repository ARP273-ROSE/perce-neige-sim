"""Contexte TLS qui marche sur toutes les machines (09/10/2026).

Kevin, sous Manjaro : « Musique : téléchargement impossible — [SSL:
CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate ». Le
Python EMBARQUÉ des paquets (PyInstaller, AppImage) cherche les certificats
racine là où ils étaient sur la machine de construction (Ubuntu de la CI) ;
Arch / Manjaro, Fedora, openSUSE les rangent ailleurs. On essaie donc le
magasin par défaut, puis les emplacements connus des distributions, puis
certifi s'il est embarqué. Jamais de vérification désactivée.
"""
import os
import ssl

_CANDIDATS = (
    "/etc/ssl/certs/ca-certificates.crt",                    # Debian, Ubuntu, Arch (lien)
    "/etc/ca-certificates/extracted/tls-ca-bundle.pem",      # Arch, Manjaro
    "/etc/ssl/cert.pem",                                     # Arch, Alpine, macOS
    "/etc/pki/tls/certs/ca-bundle.crt",                      # Fedora, RHEL
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",     # Fedora, RHEL
    "/etc/ssl/ca-bundle.pem",                                # openSUSE
)
_ctx = None


def contexte() -> ssl.SSLContext:
    global _ctx
    if _ctx is not None:
        return _ctx
    ctx = ssl.create_default_context()
    if not ctx.get_ca_certs() and os.name != "nt":
        for f in _CANDIDATS:
            if os.path.isfile(f):
                try:
                    ctx.load_verify_locations(cafile=f)
                    break
                except Exception:
                    pass
        else:
            try:
                import certifi
                ctx.load_verify_locations(cafile=certifi.where())
            except Exception:
                pass
    _ctx = ctx
    return ctx
