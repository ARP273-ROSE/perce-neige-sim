"""Verification of update signatures (Ed25519, RFC 8032), in pure Python.

The packaged Python carries no cryptography library, and verifying one
signature per update does not need one: the reference arithmetic of RFC 8032
takes a few tens of milliseconds.

Why: the update installs code. HTTPS and GitHub's SHA-256 prove the archive
is the one published on the repository, not that its author published it: a
stolen GitHub token could publish anything. The release workflow signs a
manifest (version + SHA-256 of each archive) with a private key kept outside
GitHub's reach of a token (an encrypted Actions secret); the application only
installs an archive whose SHA-256 appears in a manifest signed by that key.
The public key is in kit.json ("cle_publique_maj").
"""
import base64
import hashlib
import json

_P = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_I = pow(2, (_P - 1) // 4, _P)


def _inv(x):
    return pow(x, _P - 2, _P)


def _xrecover(y, signe):
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inv(_D * y * y + 1) % _P
    if x2 == 0:
        return None if signe else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P:
        x = x * _I % _P
    if (x * x - x2) % _P:
        return None
    if (x & 1) != signe:
        x = _P - x
    return x


def _add(a, b):
    # Extended coordinates (X, Y, Z, T), formula of RFC 8032 section 5.1.4.
    A = (a[1] - a[0]) * (b[1] - b[0]) % _P
    B = (a[1] + a[0]) * (b[1] + b[0]) % _P
    C = 2 * a[3] * b[3] * _D % _P
    D = 2 * a[2] * b[2] % _P
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % _P, G * H % _P, F * G % _P, E * H % _P)


def _mul(s, pt):
    q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            q = _add(q, pt)
        pt = _add(pt, pt)
        s >>= 1
    return q


def _egal(a, b):
    return ((a[0] * b[2] - b[0] * a[2]) % _P == 0
            and (a[1] * b[2] - b[1] * a[2]) % _P == 0)


def _point(octets):
    if len(octets) != 32:
        return None
    y = int.from_bytes(octets, 'little')
    signe = y >> 255
    y &= (1 << 255) - 1
    x = _xrecover(y, signe)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


_GY = 4 * _inv(5) % _P
_GX = _xrecover(_GY, 0)
_G = (_GX, _GY, 1, _GX * _GY % _P)


def verifier(cle_publique: bytes, message: bytes, signature: bytes) -> bool:
    """True if `signature` is a valid Ed25519 signature of `message`."""
    try:
        if len(cle_publique) != 32 or len(signature) != 64:
            return False
        a = _point(cle_publique)
        r = _point(signature[:32])
        if a is None or r is None:
            return False
        s = int.from_bytes(signature[32:], 'little')
        if s >= _L:
            return False
        h = int.from_bytes(hashlib.sha512(signature[:32] + cle_publique + message).digest(),
                           'little') % _L
        return _egal(_mul(s, _G), _add(r, _mul(h, a)))
    except Exception:
        return False


def lire_manifeste(document: bytes, cle_publique_b64: str) -> dict:
    """The signed manifest {"version": ..., "fichiers": {name: sha256}}.

    `document` is the JSON published next to the archives:
    {"manifeste": "<json text>", "signature": "<base64>"}. Raises ValueError
    if the signature does not come from the key."""
    enveloppe = json.loads(document.decode('utf-8'))
    texte = enveloppe['manifeste']
    signature = base64.b64decode(enveloppe['signature'])
    cle = base64.b64decode(cle_publique_b64)
    if not verifier(cle, texte.encode('utf-8'), signature):
        raise ValueError("Signature de mise a jour invalide")
    manifeste = json.loads(texte)
    if not isinstance(manifeste.get('fichiers'), dict):
        raise ValueError("Manifeste de mise a jour illisible")
    return manifeste
