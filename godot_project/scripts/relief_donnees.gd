class_name ReliefDonnees
extends RefCounted
## GÉNÉRÉ par tools_relief3d.py — relief IGN RGE ALTI + orthophoto IGN
## (Licence Ouverte Etalab 2.0). Ne pas éditer à la main.
##
## Emprise dans le repère du jeu (x vers l'est, z vers le sud, origine au
## pied de la voie) ; la ligne 0 de relief_hauteurs.png est au NORD (z_nord).

const NX: int = 844
const NZ: int = 691
const X_OUEST: float = -6167.80
const X_EST: float = 14917.00
const Z_NORD: float = -8695.66
const Z_SUD: float = 8558.94
const H_BASE: float = 1300.0
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
	["Les Brévières", 1574.2, -6537.2, 0],
	["Le Lavachet", 1127.5, -2110.0, 0],
	["Val d'Isère", 6228.5, 258.9, 0],
	["La Daille", 5150.1, -923.3, 0],
	["Le Fornet", 8752.4, 174.3, 0],
	["Rocher de Bellevarde", 4070.0, 745.4, 2826],
	["Tête du Solaise", 7357.7, 2250.4, 2551],
	["Col de l'Iseran", 10297.9, 3871.3, 2764],
	["Signal de l'Iseran", 11113.1, 2174.7, 3237],
	["Glacier du Pissaillas", 12183.8, 5998.6, 0],
	["Pointe de la Sana", 1442.3, 7437.9, 3435],
	["Aiguille de la Grande Sassière", 7876.2, -5912.7, 3747],
	["Tsanteleina", 11479.4, -3076.2, 3601],
]
