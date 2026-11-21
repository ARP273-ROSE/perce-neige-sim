## Guet des piques du mode réseau (retour d'utilisateur du 21/11/2026) : décide QUAND une pique réseau sort, sans
## rien afficher (logique pure, testée par bench_piques_reseau). Deux sources :
##   - les événements ponctuels signalés par ReseauClient (arrivée, départ, coupure, reconnexion, changement d'hôte),
##     mis en file et lâchés dès que l'écart entre deux piques le permet (perdus après 30 s) ;
##   - l'observation périodique de la situation (latence, distance, frôlement, même véhicule, pilote, arrêt
##     d'urgence, vitesse, solitude), déclenchée sur un passage de seuil et non tant qu'il dure.
## Chaque genre a son propre délai de répit ; deux piques réseau sont séparées d'au moins ECART_S.
class_name GuetReseau
extends RefCounted

const ECART_S: float = 10.0
const AGE_MAX_FILE: float = 30.0
## Répit par genre (s) : pas deux fois la même pique de ce genre avant ce délai.
const REPIT: Dictionary = {
	"ARRIVEE": 0.0, "DEPART": 0.0, "COUPURE": 30.0, "RECONNEXION": 30.0, "HOTE_MOI": 60.0, "HOTE_AUTRE": 60.0,
	"LATENCE": 150.0, "LOIN": 300.0, "FROLE": 40.0, "MEME_VEHICULE": 180.0, "PILOTE": 120.0, "URGENCE": 30.0,
	"PLUS_RAPIDE": 120.0, "SEUL": 300.0,
}
const LATENCE_S: float = 0.6          # aller-retour au-delà duquel le réseau « rame »
const LOIN_M: float = 3500.0
const FROLE_M: float = 2.5
const FROLE_V_REL: float = 4.0        # m/s : il faut passer vite, pas attendre côte à côte au départ
const MEME_VEH_M: float = 3.0
const RAPIDE_V: float = 14.0          # m/s (50 km/h)
const RAPIDE_RAPPORT: float = 1.8
const RAPIDE_DUREE: float = 3.0
const SEUL_S: float = 120.0

var _file: Array = []                 # [genre, nom, t]
var _dernier: Dictionary = {}         # genre → instant de sa dernière pique
var _t_pique: float = -1e9
var _etats: Dictionary = {}           # drapeaux des passages de seuil (clé → bool)
var _rapide_t: Dictionary = {}        # nom → durée cumulée « beaucoup plus vite »


## Événement ponctuel (de ReseauClient).
func signaler(genre: String, t: float, nom: String = "") -> void:
	_file.append([genre, nom, t])


func _libre(genre: String, t: float) -> bool:
	return t - _t_pique >= ECART_S and t - float(_dernier.get(genre, -1e9)) >= float(REPIT.get(genre, 60.0))


func _sortir(genre: String, t: float, nom: String = "", dist: float = 0.0, vit: float = 0.0) -> Array:
	_dernier[genre] = t
	_t_pique = t
	return [genre, nom, dist, vit]


## Passage de seuil : vrai une seule fois quand `vrai` le devient (rearmé quand il redevient faux).
func _front(cle: String, vrai: bool) -> bool:
	var avant: bool = bool(_etats.get(cle, false))
	_etats[cle] = vrai
	return vrai and not avant


## Situation à l'instant t → [] ou [genre, nom, dist_m, vit_ms].
## o : {"connecte": bool, "latence": s, "seul_s": s, "ma_vitesse": m/s, "a_bord": bool,
##      "pairs": [{"nom", "dist", "v_rel", "vitesse", "skie": bool, "bord": bool}],
##      "pilote_ici": nom ou "", "urgence_ici": nom ou ""}
func observer(t: float, o: Dictionary, dt: float = 0.5) -> Array:
	# 1. événements en file (les plus anciens d'abord), jetés s'ils ont trop attendu
	while not _file.is_empty() and t - float(_file[0][2]) > AGE_MAX_FILE:
		_file.pop_front()
	for k in range(_file.size()):
		var e: Array = _file[k]
		if _libre(String(e[0]), t):
			_file.remove_at(k)
			return _sortir(String(e[0]), t, String(e[1]))
	# 2. situation : on met d'abord à jour tous les passages de seuil (pour ne pas déclencher en retard un état
	#    ancien), puis on tire la pique la plus intéressante qui soit libre
	var candidats: Array = []
	var connecte: bool = bool(o.get("connecte", false))
	var pairs: Array = o.get("pairs", [])
	if _front("latence", connecte and float(o.get("latence", 0.0)) > LATENCE_S):
		candidats.append(["LATENCE", pairs[0]["nom"] if not pairs.is_empty() else "", 0.0, 0.0])
	if _front("seul", connecte and pairs.is_empty() and float(o.get("seul_s", 0.0)) > SEUL_S):
		candidats.append(["SEUL", "", 0.0, 0.0])
	var u: String = String(o.get("urgence_ici", ""))
	if _front("urgence", u != ""):
		candidats.append(["URGENCE", u, 0.0, 0.0])
	var pi: String = String(o.get("pilote_ici", ""))
	if _front("pilote:" + pi, pi != ""):
		candidats.append(["PILOTE", pi, 0.0, 0.0])
	for pr in pairs:
		var n: String = String(pr.get("nom", ""))
		var d: float = float(pr.get("dist", 0.0))
		if _front("meme:" + n, bool(o.get("a_bord", false)) and bool(pr.get("bord", false)) and d < MEME_VEH_M):
			candidats.append(["MEME_VEHICULE", n, d, 0.0])
		if _front("frole:" + n, d < FROLE_M and float(pr.get("v_rel", 0.0)) > FROLE_V_REL
				and not bool(pr.get("bord", false)) and not bool(o.get("a_bord", false))):
			candidats.append(["FROLE", n, d, 0.0])
		if _front("loin:" + n, d > LOIN_M):
			candidats.append(["LOIN", n, d, 0.0])
		var vit: float = float(pr.get("vitesse", 0.0))
		var rapide: bool = bool(pr.get("skie", false)) and vit > RAPIDE_V \
			and vit > RAPIDE_RAPPORT * float(o.get("ma_vitesse", 0.0))
		_rapide_t[n] = float(_rapide_t.get(n, 0.0)) + dt if rapide else 0.0
		if _front("rapide:" + n, float(_rapide_t[n]) >= RAPIDE_DUREE):
			candidats.append(["PLUS_RAPIDE", n, d, vit])
	for c in candidats:
		if _libre(String(c[0]), t):
			return _sortir(String(c[0]), t, String(c[1]), float(c[2]), float(c[3]))
	return []
