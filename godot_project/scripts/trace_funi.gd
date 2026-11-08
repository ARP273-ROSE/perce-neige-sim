class_name TraceFuni
extends RefCounted
## Tracé d'un funiculaire pour TunnelBuilder et TrackBuilder : longueur, évitement, profil (pente, cap), sections,
## options. Par défaut, celui du Perce-Neige (PNConstants, SlopeProfile) : les deux constructeurs en sont tirés et
## donnent exactement le même résultat. Le Funival en fournit un autre (Funival.trace()), pour reprendre la même
## voie, les mêmes traverses, galets, poulies et câble (demande d'utilisateur, 08/11/2026 : « les mêmes rails que
## Perce-Neige, les mêmes traverses, le même tunnel et les mêmes galets, avec toutes leurs fonctionnalités »).

var longueur: float = PNConstants.LENGTH
var evit_debut: float = PNConstants.PASSING_START
var evit_fin: float = PNConstants.PASSING_END
var carre_bas_fin: float = PNConstants.SQUARE_SECTION_LOW_END
var carre_haut_debut: float = PNConstants.SQUARE_SECTION_HIGH_START
## Perce-Neige : salles de gare, sortie de secours, porte Génépy, salle des machines, supports numérotés, deux tubes
## fusionnés à l'évitement. Faux pour une autre ligne : seul le tube courant, la voie et ses équipements.
var perce_neige: bool = true
## Évitement en deux tubes séparés qui fusionnent (Perce-Neige) ; faux : une seule section élargie, sans mur entre
## les voies (Funival, demande d'utilisateur du 08/11/2026).
var deux_tubes: bool = true
var decal_evitement: float = 3.50          # décalage latéral maximal de chaque voie dans l'évitement (m)
## Chambre unique (deux_tubes faux) : rayon = rayon du tube + |décalage d'une voie| × ce facteur.
var elargissement_chambre: float = 1.0
## Le tube n'est construit qu'à partir de cette abscisse (Funival : portail ; avant, la voie est dehors).
var tube_debut: float = 0.0
## Profil : fonctions (s) → valeur. Par défaut, SlopeProfile.
var _pente: Callable = Callable()          # angle de pente (rad)
var _cap: Callable = Callable()            # cap (degrés)
var _points: Callable = Callable()         # (pas) → Array[Vector3] du tracé, repère de la ligne
var _decal: Callable = Callable()          # (s) → décalage d'une voie dans l'évitement (m, ≥ 0) ; défaut : sin²


static func perce_neige_defaut() -> TraceFuni:
	return TraceFuni.new()


func pente_angle(s: float) -> float:
	return float(_pente.call(s)) if _pente.is_valid() else SlopeProfile.slope_angle_at(s)


func pente_courbure(s: float) -> float:
	var ds: float = 5.0
	return (pente_angle(s + ds) - pente_angle(s - ds)) / (2.0 * ds)


func cap(s: float) -> float:
	return float(_cap.call(s)) if _cap.is_valid() else SlopeProfile.heading_at(s)


func points(pas: float) -> Array:
	return _points.call(pas) if _points.is_valid() else SlopeProfile.build_path_points(pas)


func dans_evitement(s: float) -> bool:
	return evit_debut <= s and s <= evit_fin


## Décalage d'une voie dans l'évitement (m, ≥ 0), ou -INF si le tracé n'en fournit pas (forme sin² du Perce-Neige,
## calculée par TunnelBuilder).
func decalage(s: float) -> float:
	return float(_decal.call(s)) if _decal.is_valid() else -INF
