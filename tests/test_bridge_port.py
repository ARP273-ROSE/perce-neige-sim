"""Port UDP du viewer 3D : un port occupé (viewer resté d'un plantage) ne doit pas priver le suivant d'état."""
import socket

from godot_bridge import GodotBridge

BASE = 47777


def _pont():
    b = GodotBridge(port=BASE)
    b._log = lambda _m: None
    return b


def _tenir(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", port))
    return s


def test_port_libre_garde():
    b = _pont()
    b._choisir_port()
    assert b.port == BASE and b._addr == ("127.0.0.1", BASE)


def test_port_occupe_evite():
    s = _tenir(BASE)
    try:
        b = _pont()
        b._choisir_port()
        assert b.port == BASE + 2 and b._addr == ("127.0.0.1", BASE + 2)
    finally:
        s.close()


def test_port_de_retour_occupe_evite():
    s = _tenir(BASE + 1)
    try:
        b = _pont()
        b._choisir_port()
        assert b.port == BASE + 2
    finally:
        s.close()
