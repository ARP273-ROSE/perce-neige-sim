class_name ReliefDonnees
extends RefCounted
## GÉNÉRÉ par tools_relief3d.py — relief IGN RGE ALTI + orthophoto IGN
## (Licence Ouverte Etalab 2.0). Ne pas éditer à la main.
##
## Emprise dans le repère du jeu (x vers l'est, z vers le sud, origine au
## pied de la voie) ; la ligne 0 de relief_hauteurs.png est au NORD (z_nord).

const NX: int = 345
const NZ: int = 411
const X_OUEST: float = -4762.15
const X_EST: float = 3827.96
const Z_NORD: float = -3908.90
const Z_SUD: float = 6332.54
const H_BASE: float = 1700.0
const H_ECHELLE: float = 0.1     # altitude = H_BASE + (256·R + G) × H_ECHELLE

## Lieux nommés (OpenStreetMap) : [nom, x, z, altitude affichée (0 = aucune)]
const LIEUX: Array = [
	["Lac de Tignes", 388.8, -1536.7, 0],
	["Tignes le Lac", 672.3, -1986.4, 0],
	["Val Claret", 77.2, -492.5, 0],
	["Grande Motte", -2272.6, 4574.8, 3653],
	["Dôme de Pramecou", -1630.7, 1949.9, 3081],
	["Pointe de Pramecou", -2356.9, 1625.9, 3009],
	["Rochers de la Grande Balme", -1080.1, 971.4, 2882],
	["Col de la Leisse", 712.1, 3047.5, 2761],
	["La Tovière", 1637.5, -475.8, 2696],
	["Lac du Chevril", 3395.3, -3364.5, 0],
	["Grand Lac de Chardonet", -1245.7, -1535.6, 0],
	["Aiguille Percée", -688.1, -3520.4, 2748],
]
