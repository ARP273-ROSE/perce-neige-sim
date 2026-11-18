# -*- coding: utf-8 -*-
"""Signed updates: the application installs only an archive listed, with its
SHA-256, in a manifest signed by the publisher's key (kit.json
"cle_publique_maj")."""
import base64
import hashlib
import json
import sys
from pathlib import Path

import pytest

RACINE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RACINE))

import signature_maj  # noqa: E402
import updater  # noqa: E402


def test_vecteur_rfc8032():
    pk = bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
    sig = bytes.fromhex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555f'
                        'b8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')
    assert signature_maj.verifier(pk, b'', sig)
    assert not signature_maj.verifier(pk, b'x', sig)
    assert not signature_maj.verifier(pk, b'', bytes([sig[0] ^ 1]) + sig[1:])


def test_la_cle_publique_est_declaree():
    cle = json.loads((RACINE / 'kit.json').read_text(encoding='utf-8')).get('cle_publique_maj')
    assert cle and len(base64.b64decode(cle)) == 32
    assert 'signature_maj.py' in json.loads((RACINE / 'kit.json').read_text(encoding='utf-8'))['modules']


@pytest.fixture
def cle(monkeypatch):
    ed = pytest.importorskip('cryptography.hazmat.primitives.asymmetric.ed25519')
    from cryptography.hazmat.primitives import serialization as ser
    k = ed.Ed25519PrivateKey.generate()
    pub = base64.b64encode(k.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw)).decode()
    kit = dict(updater._kit())
    kit['cle_publique_maj'] = pub
    monkeypatch.setattr(updater, '_kit', lambda: kit)
    return k


def _document(k, version, fichiers):
    texte = json.dumps({'version': version, 'fichiers': fichiers}, sort_keys=True)
    return json.dumps({'manifeste': texte,
                       'signature': base64.b64encode(k.sign(texte.encode())).decode()}).encode()


class _Reponse:
    def __init__(self, data):
        self._d = data

    def read(self, n=-1):
        return self._d

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _maj(monkeypatch, document, version='9.9.9', nom='appli-app-9.9.9.zip'):
    monkeypatch.setattr(updater, '_open', lambda url: _Reponse(document))
    return {'version': version, 'nom': nom, 'signature_url': 'https://github.com/x'}


SHA = hashlib.sha256(b'archive').hexdigest()


@pytest.fixture
def archive(tmp_path):
    chemin = tmp_path / 'update.zip'
    chemin.write_bytes(b'archive')
    return chemin


def test_archive_signee_acceptee(cle, monkeypatch, archive):
    maj = _maj(monkeypatch, _document(cle, '9.9.9', {'appli-app-9.9.9.zip': SHA}))
    updater.verifier_signature(maj, archive)


def test_archive_modifiee_refusee(cle, monkeypatch, archive):
    maj = _maj(monkeypatch, _document(cle, '9.9.9', {'appli-app-9.9.9.zip': SHA}))
    with pytest.raises(RuntimeError):
        archive.write_bytes(b'autre')
        updater.verifier_signature(maj, archive)


def test_autre_cle_refusee(cle, monkeypatch, archive):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    pirate = Ed25519PrivateKey.generate()
    maj = _maj(monkeypatch, _document(pirate, '9.9.9', {'appli-app-9.9.9.zip': SHA}))
    with pytest.raises(RuntimeError):
        updater.verifier_signature(maj, archive)


def test_autre_version_refusee(cle, monkeypatch, archive):
    maj = _maj(monkeypatch, _document(cle, '9.9.8', {'appli-app-9.9.9.zip': SHA}))
    with pytest.raises(RuntimeError):
        updater.verifier_signature(maj, archive)


def test_sans_signature_refusee(cle, archive):
    with pytest.raises(RuntimeError):
        updater.verifier_signature({'version': '9.9.9', 'nom': 'x.zip', 'signature_url': ''}, archive)
