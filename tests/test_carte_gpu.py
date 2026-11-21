"""Carte graphique de la vue 3D (menu Affichage) : intégrée / dédiée / automatique → arguments du moteur."""
import godot_bridge
from godot_bridge import GodotBridge, indice_adaptateur, lister_adaptateurs_vulkan

RESUME_PORTABLE = """
Devices:
========
GPU0:
	apiVersion         = 1.3.280
	vendorID           = 0x10de
	deviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
	deviceName         = NVIDIA GeForce RTX 3070 Ti Laptop GPU
GPU1:
	apiVersion         = 1.3.270
	vendorID           = 0x8086
	deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
	deviceName         = Intel(R) Iris(R) Xe Graphics
GPU2:
	deviceType         = PHYSICAL_DEVICE_TYPE_CPU
	deviceName         = llvmpipe (LLVM 17.0.6, 256 bits)
"""


def test_liste_lue_dans_l_ordre():
    a = lister_adaptateurs_vulkan(RESUME_PORTABLE)
    assert [x[0] for x in a] == [0, 1, 2]
    assert a[1][1] == "INTEGRATED_GPU" and "Iris" in a[1][2]


def test_indices():
    a = lister_adaptateurs_vulkan(RESUME_PORTABLE)
    assert indice_adaptateur("INTEGRATED_GPU", a) == 1
    assert indice_adaptateur("DISCRETE_GPU", a) == 0
    # jamais le rendu logiciel
    assert indice_adaptateur("INTEGRATED_GPU", [(0, "CPU", "llvmpipe")]) is None


def _pont(monkeypatch, carte, sortie):
    monkeypatch.setattr(godot_bridge, "lister_adaptateurs_vulkan", lambda s=None: lister_adaptateurs_vulkan(sortie))
    b = GodotBridge(port=47790)
    b._log = lambda _m: None
    b.carte_gpu = carte
    return b


def test_integree_choisit_son_rang(monkeypatch):
    b = _pont(monkeypatch, "integree", RESUME_PORTABLE)
    assert b._args_carte() == ["--gpu-index", "1"]
    assert "--carte=integree" in b._args_utilisateur()


def test_dediee_et_auto(monkeypatch):
    assert _pont(monkeypatch, "dediee", RESUME_PORTABLE)._args_carte() == ["--gpu-index", "0"]
    b = _pont(monkeypatch, "auto", RESUME_PORTABLE)
    assert b._args_carte() == [] and "--carte=integree" not in b._args_utilisateur()


def test_integree_sans_liste_repli_opengl(monkeypatch):
    b = _pont(monkeypatch, "integree", "")
    assert b._args_carte() == ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]
    # pas de rendu logiciel imposé
    assert not any("llvmpipe" in x or "software" in x for x in b._args_carte())


def test_repli_opengl_du_lanceur_sans_gpu_index(monkeypatch):
    b = _pont(monkeypatch, "integree", RESUME_PORTABLE)
    b._platform_engine_args = lambda: []
    b._bundled_binary_path = lambda: godot_bridge.Path("/opt/jeu")
    cmd = b._resolve_command()
    assert cmd[1:3] == ["--gpu-index", "1"] and "--carte=integree" in cmd
    cmd2 = b._resolve_command(engine_args=["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"])
    assert "--gpu-index" not in cmd2
