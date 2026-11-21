## Pendule de la descente à la corde (retour d'utilisateur du 21/11/2026 : « rajoute du réalisme avec calculs
## physiques pour la descente à la corde, oscillation, balancement, tournoiement sur soi-même »).
##
## L'évacué (assis dans le triangle d'évacuation, au bout d'une corde statique qui se dévide au descendeur) est une
## masse ponctuelle M suspendue à un ancrage mobile (le siège ou la trappe de la cabine) par un ressort-amortisseur
## qui ne travaille qu'en traction :
##   - corde statique (EN 1891) : allongement ~3 % sous le poids d'une personne → raideur k = EA / L, EA tiré de là ;
##     petit rebond vertical quand le dévidage s'arrête (mode axial, période 2π·√(M·L/EA) ≈ 1 s à 10 m) ;
##   - balancement dans les deux plans : pendule de période 2π·√(L/g) (6,3 s à 10 m), lancé par le mou au départ du
##     siège (l'évacué glisse du bord, avec la vitesse du véhicule qui balance encore) et entretenu par le vent ;
##     amorti par la traînée de l'air (½·ρ·Cx·S·|v|·v, ρ = 1,0 en altitude) et par l'amortissement propre de la corde ;
##   - tournoiement sur soi-même : pendule de torsion, couple de rappel de la corde vrillée κ = GJ / L, inertie du
##     corps assis autour de la verticale ; vrillage initial au départ, couple du vent ; amorti (ζ ≈ 6 %).
## Intégration d'Euler semi-implicite à pas fixe (1/240 s), indépendante de la cadence d'affichage (30 ou 60 i/s,
## accélérations de temps des bancs) : pas de divergence, mêmes trajectoires partout. GDScript seul (la PWA n'a pas
## le module C++).
class_name PenduleCorde
extends RefCounted

const G: float = 9.81
const M: float = 80.0                     # kg, évacué équipé (triangle compris)
const ALLONGEMENT_POIDS: float = 0.03     # corde statique : 3 % d'allongement sous le poids d'une personne
const EA: float = M * G / ALLONGEMENT_POIDS   # N, rigidité axiale de la corde (~26 kN)
const ZETA_AXIAL: float = 0.12            # amortissement interne de la corde (mode axial)
const RHO_AIR: float = 1.0                # kg/m³ vers 2000 m
const CX_S: float = 0.55                  # m², Cx·S d'un corps assis dans le triangle
const C_LIN: float = 4.0                  # N·s/m, frottements à basse vitesse (corde dans le descendeur, vêtements)
const I_ROT: float = 2.2                  # kg·m², inertie du corps assis autour de la verticale
const GJ: float = 9.0                     # N·m²/rad, rigidité de torsion de la corde (période ~10 s à 10 m)
const ZETA_ROT: float = 0.06              # amortissement du tournoiement
const K_VENT_ROT: float = 0.06            # m, bras de levier du vent sur le corps dissymétrique (couple de vrille)
const PAS: float = 1.0 / 240.0            # s, pas d'intégration fixe
const MOU_DEPART: float = 0.25            # m de mou quand l'évacué quitte le siège (chute courte, puis la corde prend)

var p: Vector3 = Vector3.ZERO             # position de l'évacué (point d'attache du triangle)
var v: Vector3 = Vector3.ZERO
var l0: float = 1.0                       # longueur de corde dévidée, sans charge (m)
var psi: float = 0.0                      # rotation sur soi-même autour de la verticale (rad)
var omega: float = 0.0                    # rad/s
var tension: float = 0.0                  # N, dernière tension calculée
var vent: Vector3 = Vector3.ZERO          # m/s, vent au point de l'évacué (rempli par l'appelant)
var _reste: float = 0.0


## Départ : l'évacué quitte le siège à `pos`, avec la vitesse du véhicule `v0` ; `l_dev` = corde déjà dévidée entre
## l'ancrage et lui ; `vrille` = rotation initiale de la corde (rad).
func lancer(ancrage: Vector3, pos: Vector3, v0: Vector3, vrille: float, vitesse_rot: float) -> void:
	p = pos
	v = v0
	l0 = maxf(ancrage.distance_to(pos) + MOU_DEPART, 0.3)
	psi = vrille
	omega = vitesse_rot
	_reste = 0.0


## Avance de `delta` s. `v_devidage` (m/s) : vitesse à laquelle le descendeur laisse filer la corde.
## `sol` : altitude du sol sous l'évacué (il s'y pose : la corde se détend).
func avancer(delta: float, ancrage: Vector3, v_devidage: float, sol: float) -> void:
	_reste += delta
	var n: int = 0
	while _reste >= PAS and n < 2000:
		_reste -= PAS
		n += 1
		_pas(PAS, ancrage, v_devidage, sol)


func _pas(h: float, a: Vector3, v_dev: float, sol: float) -> void:
	l0 += v_dev * h
	var d: Vector3 = p - a
	var lg: float = d.length()
	var f: Vector3 = Vector3(0.0, -M * G, 0.0)
	tension = 0.0
	if lg > 1e-4:
		var u: Vector3 = d / lg
		var etir: float = lg - l0
		if etir > 0.0:
			var k: float = EA / maxf(l0, 0.3)
			var c: float = 2.0 * ZETA_AXIAL * sqrt(k * M)
			var vr: float = v.dot(u) - v_dev       # vitesse d'allongement de la corde
			tension = maxf(k * etir + c * vr, 0.0)  # une corde ne pousse pas
			f -= u * tension
	# air : traînée quadratique dans le vent relatif, et frottements linéaires
	var vrel: Vector3 = v - vent
	f -= vrel * (0.5 * RHO_AIR * CX_S * vrel.length()) + v * C_LIN
	v += f / M * h
	p += v * h
	if p.y < sol:
		p.y = sol
		v = Vector3(v.x * 0.5, maxf(v.y, 0.0), v.z * 0.5)
	# tournoiement : rappel de la corde vrillée, amortissement, couple du vent
	var kap: float = GJ / maxf(l0, 0.3)
	var c_rot: float = 2.0 * ZETA_ROT * sqrt(kap * I_ROT)
	var vh: Vector3 = Vector3(vrel.x, 0.0, vrel.z)
	var couple_vent: float = 0.5 * RHO_AIR * CX_S * vh.length_squared() * K_VENT_ROT * sin(2.0 * (atan2(vh.x, vh.z) - psi))
	omega += (-kap * psi - c_rot * omega + couple_vent) / I_ROT * h
	psi += omega * h


## Angle de la corde avec la verticale (rad), pour les bancs et les piques.
func angle(ancrage: Vector3) -> float:
	var d: Vector3 = ancrage - p
	return acos(clampf(d.y / maxf(d.length(), 1e-4), -1.0, 1.0))
