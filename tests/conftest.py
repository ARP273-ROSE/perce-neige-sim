"""Réglages communs de la suite.

`ssl` est importé AVANT PyQt6 : dans le conteneur python-lab (Python conda
+ PyQt6 du venv), Qt Multimedia charge d'abord la libssl du système, et le
module `_ssl` de conda refuse ensuite de se charger (« OPENSSL_3.3.0 not
found »). Les tests de mise à jour (urllib) échouaient alors selon l'ORDRE
des fichiers — pas selon le code.
"""
import ssl  # noqa: F401
