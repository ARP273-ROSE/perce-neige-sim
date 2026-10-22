class_name VehiculeRemontee
extends Node3D
## Véhicule de remontée (siège ou cabine) avec sa pince, par famille de
## constructeur — l'échantillon à poser ensuite sur toutes les lignes.
##
## Repère local : origine sur l'AXE DU CÂBLE, −Z vers l'amont (sens de
## marche), X vers l'extérieur de la voie (côté opposé au fût des pylônes),
## Y vers le haut. Le véhicule pend sous le câble.
##
## Pièces animées (fonctions publiques, t ∈ [0, 1]) :
##   ouvrir_pince(t)   0 = mâchoires serrées sur le câble, 1 = ouvertes (gare)
##   garde_corps(t)    0 = relevé (embarquement), 1 = baissé (en ligne)
##   bulle(t)          0 = ouverte (relevée sur le dossier), 1 = fermée
##   portes(t)         0 = fermées, 1 = ouvertes (cabines)
##
## La pince : corps posé sur le câble, mâchoire fixe et mâchoire mobile
## serrées par des ressorts ; en gare, une CAME pousse le galet du levier, le
## levier comprime les ressorts et la mâchoire mobile s'écarte — le véhicule
## roule alors sur le RAIL par ses galets de roulement, et les PNEUS de la
## gare l'entraînent par sa plaque de friction.

@export var famille: String = "siege_doppelmayr_e98_6"

var _machoire: Node3D
var _levier: Node3D
var _ressorts: Array = []
var _ressort_l0: float = 0.32
var _gc: Node3D
var _bulle: Node3D
var _portes: Array = []        # [nœud, position fermée, déplacement à l'ouverture]
var places: int = 6
var cabine: bool = false
## Dessus de la plaque de friction de la pince débrayable, au-dessus de
## l'axe du câble (les pneus du lanceur y appuient), et son décalage latéral.
const Y_PLAQUE: float = 0.40
const X_PLAQUE: float = 0.28
## Partie SUSPENDUE (suspente + siège / caisse) : un pendule articulé sous la
## pince, en `pivot` (repère du véhicule). Balancement longitudinal (φ) et
## transversal (ψ) entretenu par les accélérations de la pince — freinage et
## lancement en gare, changements de pente aux pylônes, demi-tour sur la
## poulie — et amorti selon la masse (articulation, air).
var pivot: Vector3 = Vector3.ZERO
var masse: float = 650.0
var longueur_pendule: float = 2.6
var _susp: Node3D = null
var _pince: Node3D = null
var phi: float = 0.0
var psi: float = 0.0
var _dphi: float = 0.0
var _dpsi: float = 0.0
var _p_prec: Vector3 = Vector3.ZERO
var _v_prec: Vector3 = Vector3.ZERO
var _a_f: Vector3 = Vector3.ZERO
var _n_mes: int = 0

const DESCRIPTIONS: Dictionary = {
	"siege_doppelmayr_e98_6": ["Doppelmayr / Études de Transports E98, 6 places", 6, "doppelmayr"],
	"siege_doppelmayr_e98_4": ["Doppelmayr / Études de Transports E98, 4 places", 4, "doppelmayr"],
	"siege_doppelmayr_e98_4_bulle": ["E98 4 places à bulle (Lanches)", 4, "doppelmayr"],
	"siege_poma_ocr6": ["Poma OCR, 6 places", 6, "poma"],
	"siege_poma_arceau4": ["Poma « Arceau », 4 places", 4, "poma"],
	"siege_garaventa_sk6": ["Garaventa SK6, 6 places", 6, "garaventa"],
	"siege_bartholet_6": ["BMF-Bartholet, 6 places", 6, "bartholet"],
	"siege_leitner_4": ["Leitner, 4 places", 4, "leitner"],
	"siege_fixe_4": ["4 places à pince fixe", 4, "fixe"],
	"siege_fixe_3": ["3 places à pince fixe", 3, "fixe"],
	"cabine_omega4": ["CWA Omega IV, 8-10 places (pince Doppelmayr)", 10, "doppelmayr"],
	"cabine_diamond": ["Sigma Diamond EVO, 10 places (pince Poma)", 10, "poma"],
	"cabine_symphony": ["Sigma Symphony, 10 places (pince Poma)", 10, "poma"],
	"cabine_3s": ["CWA Zeta, 30 places (3S Doppelmayr)", 30, "3s"],
	"cabine_tph": ["Cabine de téléphérique va-et-vient (Von Roll), 80-115 places", 80, "tph"],
	"perche_enrouleur": ["Perche à enrouleur (téléski TKE)", 1, "fixe"],
	"perche_tbar": ["Perche biplace en T à enrouleur", 2, "fixe"],
	"perche_debrayable": ["Perche à assiette débrayable (TKD)", 1, "tkd"],
}


var _construit: bool = false


## Construit à l'entrée dans l'arbre seulement si personne ne l'a fait : un
## appel explicite à construire() juste après add_child() le refaisait (tout
## en double, et des pièces effacées restaient dans les listes).
func _ready() -> void:
	if not _construit:
		construire()


func constructeur() -> String:
	return DESCRIPTIONS.get(famille, ["", 6, "doppelmayr"])[2]


func construire() -> void:
	_construit = true
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_ressorts.clear()
	_portes.clear()
	places = DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	cabine = famille.begins_with("cabine")
	var fixe: bool = constructeur() == "fixe"
	if famille.begins_with("perche"):
		_perche()
	elif famille == "cabine_3s" or famille == "cabine_tph":
		_grande_cabine()
	else:
		if fixe:
			_pince_fixe()
		else:
			_pince_debrayable()
		if cabine:
			_cabine()
		else:
			_siege()
	# partie suspendue sous le pivot
	_pince = get_node_or_null("Pince") as Node3D
	_susp = Node3D.new()
	_susp.name = "Suspendu"
	_susp.position = pivot
	var enfants: Array = get_children()
	add_child(_susp)
	for c in enfants:
		if c == _pince or not (c is Node3D):
			continue
		remove_child(c)
		_susp.add_child(c)
		(c as Node3D).position -= pivot
	# masse à vide (pince comprise) et longueur du pendule jusqu'au centre de gravité
	if cabine or famille == "cabine_3s" or famille == "cabine_tph":
		masse = 850.0 if cabine else (2950.0 if famille == "cabine_3s" else 9000.0)
		longueur_pendule = 2.3 if cabine else 3.5
	elif famille.begins_with("perche"):
		masse = 25.0
		longueur_pendule = 1.6
	else:
		masse = 95.0 * places + 80.0
		longueur_pendule = _haut_suspente() + 0.75
	ouvrir_pince(0.0)
	garde_corps(1.0)
	bulle(1.0)
	portes(0.0)
	_fusionner()


## Fusion des pièces fixes (un appel de dessin par matériau) ; les pièces
## animées restent à part, chacune fusionnée en elle-même.
func _fusionner() -> void:
	var garder: Array = []
	for n in [_machoire, _levier, _gc, _bulle, _corde, _perche_tige]:
		if n != null:
			garder.append(n)
	for r in _ressorts:
		garder.append(r)
	for p in _portes:
		garder.append(p[0])
	if _pince != null:
		MeshMerge.merge(_pince, garder, "Pince")
	MeshMerge.merge(_susp, garder, "Vehicule")
	for n in garder:
		MeshMerge.merge(n, [], "Piece")


# --- pinces ---------------------------------------------------------------------

func _couleur_ressorts() -> String:
	match constructeur():
		"bartholet":
			return "jaune_ressort"       # « deux ressorts jaunes » (K3)
		"garaventa":
			return "bleu_ressort"        # « deux ressorts bleus » (AK 460)
		"poma":
			return "acier_noir"
		_:
			return "rouge_ressort"


## Pince débrayable, d'après les pinces Doppelmayr D-Line et A108 (photos de
## maquettes à l'échelle 1) : un corps en aluminium coulé qui enserre le câble
## par-dessus, prolongé aux deux bouts par des gaines noires coniques ; deux
## paquets de gros ressorts hélicoïdaux (un à chaque bout, deux ressorts
## côte à côte) qui serrent les mâchoires ; le bras du levier d'ouverture et
## son galet ; deux galets de roulement en polyuréthane blanc (rail de gare),
## un galet de guidage ; la longue plaque de friction noire crantée sur
## laquelle appuient les pneus de la gare. La suspente part du côté
## extérieur (X+). Couleurs des ressorts selon le constructeur.
func _pince_debrayable() -> void:
	var p: Node3D = Node3D.new()
	p.name = "Pince"
	add_child(p)
	var poma: bool = constructeur() == "poma"
	var corps_m: String = "acier_noir" if poma else "alu_pince"
	var L: float = 0.62                                   # longueur du corps le long du câble
	# corps : selle qui chevauche le câble, flancs, nervures
	RemonteeKit.boite_en(p, Vector3(0.13, 0.07, L), Vector3(0.0, 0.055, 0), corps_m)
	RemonteeKit.boite_en(p, Vector3(0.035, 0.11, L * 0.92), Vector3(-0.055, 0.0, 0), corps_m)   # mâchoire fixe
	for k in [-1.0, 0.0, 1.0]:
		RemonteeKit.boite_en(p, Vector3(0.14, 0.012, 0.03), Vector3(0.0, 0.092, k * L * 0.33), corps_m)
	# gaines coniques noires aux deux bouts (guident le câble à l'entrée des pneus)
	# … qui s'amincissent jusqu'à ZÉRO au bout (rayon du câble) : la pince
	# passe ainsi sous les galets de compression et sur les supports sans choc
	for sz in [-1.0, 1.0]:
		RemonteeKit.cylindre(p, 0.055, 0.0245, 0.34, Transform3D(Basis(Vector3.RIGHT, -sz * PI * 0.5), Vector3(0, 0.0, sz * (L * 0.5 + 0.17))),
			"noir_mat", 14)
	# mâchoire MOBILE (côté extérieur), pivot parallèle au câble
	_machoire = Node3D.new()
	_machoire.name = "MachoireMobile"
	_machoire.position = Vector3(0.07, 0.07, 0)
	p.add_child(_machoire)
	RemonteeKit.boite_en(_machoire, Vector3(0.035, 0.12, L * 0.92), Vector3(-0.018, -0.075, 0), corps_m)
	# bras porteur : du corps vers l'extérieur et le haut, où sont les ressorts
	RemonteeKit.poutre(p, Vector3(0.05, 0.07, 0), Vector3(0.24, 0.20, 0), 0.10, 0.07, corps_m, Vector3.BACK)
	RemonteeKit.boite_en(p, Vector3(0.16, 0.06, 0.46), Vector3(0.28, 0.19, 0), corps_m)
	# paquets de ressorts : deux ressorts côte à côte à chaque bout, axe vers le haut
	var rc: String = _couleur_ressorts()
	if rc == "rouge_ressort":
		rc = "ressort_gris"          # Doppelmayr récents : ressorts gris (rouges = ET/A108 anciens)
	# (ressorts plus courts : la plaque de friction, au-dessus, reste au plus
	# près du câble, et les pneus du lanceur aussi — retour d'utilisateur, 22/10/2026)
	var l_r: float = Y_PLAQUE - 0.022 - 0.025 - 0.22
	for sz in [-1.0, 1.0]:
		for sx in [-0.045, 0.045]:
			var r: Node3D = Node3D.new()
			r.position = Vector3(0.28 + sx, 0.22, sz * 0.15)
			p.add_child(r)
			RemonteeKit.ressort(r, Vector3.ZERO, Vector3.UP, l_r, 0.042, 0.011, 5, rc)
			_ressorts.append(r)
		# coupelle haute des ressorts
		RemonteeKit.boite_en(p, Vector3(0.16, 0.025, 0.10), Vector3(0.28, 0.22 + l_r + 0.012, sz * 0.15), corps_m)
	# levier d'ouverture et son galet (attaqué par la came de gare)
	_levier = Node3D.new()
	_levier.name = "Levier"
	_levier.position = Vector3(0.36, 0.20, 0)
	p.add_child(_levier)
	RemonteeKit.poutre(_levier, Vector3.ZERO, Vector3(0.12, 0.06, 0), 0.06, 0.05, corps_m, Vector3.BACK)
	RemonteeKit.cylindre(_levier, 0.055, 0.055, 0.05, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.14, 0.07, 0)), "polyurethane", 16)
	# galets de roulement (rail de gare), en tête et en queue, axe en travers
	for sz in [-1.0, 1.0]:
		RemonteeKit.cylindre(p, 0.016, 0.016, 0.12, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.20, 0.11, sz * 0.24)), "acier_noir", 8)
		RemonteeKit.cylindre(p, 0.065, 0.065, 0.055, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.25, 0.11, sz * 0.24)), "polyurethane", 18)
	# galet de guidage (sous le bras, axe vertical)
	RemonteeKit.cylindre(p, 0.05, 0.05, 0.05, Transform3D(Basis.IDENTITY, Vector3(0.20, -0.02, 0)), "polyurethane", 16)
	# plaque de friction crantée, À PLAT sur le dessus (posée sur les coupelles
	# des ressorts) : les pneus du lanceur, au-dessus, appuient dessus et
	# entraînent la pince pendant qu'elle roule sur le rail (retour d'utilisateur, 22/10/2026)
	RemonteeKit.boite_en(p, Vector3(0.17, 0.022, 0.84), Vector3(0.28, Y_PLAQUE - 0.011, 0), "noir_mat")
	var z: float = -0.40
	while z <= 0.40:
		RemonteeKit.boite_en(p, Vector3(0.15, 0.008, 0.014), Vector3(0.28, Y_PLAQUE + 0.004, z), "noir_mat")
		z += 0.04
	# numéro du véhicule sur la tranche de la plaque
	var lab: Label3D = Label3D.new()
	lab.text = "%03d" % (randi() % 120 + 1)
	lab.font_size = 40
	lab.pixel_size = 0.0016
	lab.position = Vector3(0.37, Y_PLAQUE - 0.011, 0.25)
	lab.rotation.y = PI * 0.5
	lab.modulate = Color(1, 1, 1)
	p.add_child(lab)


func _pince_fixe() -> void:
	var p: Node3D = Node3D.new()
	p.name = "Pince"
	add_child(p)
	# monopince fixe : un corps serré par boulons, pas de galets de roulement
	RemonteeKit.boite_en(p, Vector3(0.16, 0.14, 0.32), Vector3(0.07, 0.05, 0), "galva")
	for sz in [-0.10, 0.0, 0.10]:
		RemonteeKit.cylindre(p, 0.018, 0.018, 0.20, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.07, -0.01, sz)), "acier", 6)
	_machoire = Node3D.new()
	p.add_child(_machoire)


## 0 : serrée sur le câble ; 1 : ouverte (en gare, levier poussé par la came).
func ouvrir_pince(t: float) -> void:
	if _machoire != null:
		_machoire.rotation.z = -0.45 * clampf(t, 0.0, 1.0)
	if _levier != null:
		_levier.rotation.z = -0.55 * clampf(t, 0.0, 1.0)
	for r in _ressorts:
		(r as Node3D).scale = Vector3(1, 1.0 - 0.22 * clampf(t, 0.0, 1.0), 1)


# --- suspente et siège -------------------------------------------------------------

## Hauteur du câble au-dessus du quai d'embarquement : l'assise arrive à
## 0,48 m du sol (siège), le plancher au niveau du quai (cabine).
static func hauteur_cable_gare(fam: String) -> float:
	if fam.begins_with("cabine"):
		return 1.15 + 0.10 + 2.25 - 0.07 + 0.02
	var pl: int = DESCRIPTIONS.get(fam, ["", 6, ""])[1]
	var hs: float = 2.35 if pl >= 6 else 2.05
	return hs + 0.12 + 0.98 - 0.045 + 0.48


## Point du repère du véhicule (au repos) porté par la partie suspendue,
## en coordonnées monde (suit le balancement).
func vers_monde(p: Vector3) -> Vector3:
	if _susp == null:
		return global_transform * p
	return _susp.global_transform * (p - pivot)


## La pince suit la pente du câble (rad, > 0 : le câble monte vers −Z).
func inclinaison(a: float) -> void:
	if _pince != null:
		_pince.rotation.x = a


## Remet le pendule au repos (véhicule posé, nouvelle ligne).
func pendule_repos() -> void:
	phi = 0.0
	psi = 0.0
	_dphi = 0.0
	_dpsi = 0.0
	_n_mes = 0
	if _susp != null:
		_susp.rotation = Vector3.ZERO


## Un pas du pendule. L'accélération de la pince est mesurée sur sa
## trajectoire (dérivée seconde de la position, lissée) ; dans le repère du
## véhicule : φ'' = −(g'/L) sin φ − (a_avant/L) cos φ − 2ζω₀ φ', idem en
## travers ; g' = g + accélération verticale. Amortissement réduit ζ ∝ 1/masse
## (le frottement de l'articulation et l'air pèsent moins sur un véhicule
## lourd) ; `en_gare` : véhicule guidé, fortement amorti.
func balancer(dt: float, en_gare: bool) -> void:
	if _susp == null:
		return
	# repère de la LIGNE (parent) : immobile, et tourné seulement autour de
	# la verticale — la gravité y reste selon −Y
	var p: Vector3 = position
	if dt <= 0.0 or _n_mes == 0:
		_p_prec = p
		_n_mes = 1
		return
	var v: Vector3 = (p - _p_prec) / dt
	_p_prec = p
	if _n_mes == 1:
		_v_prec = v
		_n_mes = 2
		return
	var a: Vector3 = ((v - _v_prec) / dt).limit_length(25.0)
	_v_prec = v
	_a_f = _a_f.lerp(a, minf(1.0, dt * 15.0))
	var la: Vector3 = transform.basis.inverse() * _a_f
	var g2: float = 9.81 + _a_f.y
	var L: float = longueur_pendule
	var w0: float = sqrt(9.81 / L)
	var zeta: float = 0.7 if en_gare else clampf(90.0 / masse, 0.03, 0.30)
	var n: int = maxi(1, int(ceil(dt / 0.008)))
	var h: float = dt / n
	for k in range(n):
		var ddphi: float = -(g2 / L) * sin(phi) - (-la.z / L) * cos(phi) - 2.0 * zeta * w0 * _dphi
		var ddpsi: float = -(g2 / L) * sin(psi) - (la.x / L) * cos(psi) - 2.0 * zeta * w0 * _dpsi
		_dphi += ddphi * h
		_dpsi += ddpsi * h
		phi += _dphi * h
		psi += _dpsi * h
	phi = clampf(phi, -0.6, 0.6)
	psi = clampf(psi, -0.6, 0.6)
	_susp.rotation = Vector3(phi, 0.0, psi)


## Où poser le skieur assis (repère du véhicule) : origine aux pieds, 0,42 m
## devant le bassin (convention de SkieurJoueur.asseoir), tourné vers −Z.
## Siège : place `i` ; cabine : banquette arrière, face à l'amont.
## `avant` : banquette avant d'une cabine, face à l'arrière (+Z).
func place_assise(i: int = -1, avant: bool = false) -> Vector3:
	if cabine:
		var hs: float = 1.15
		var y_banc: float = -hs - 0.10 - 2.25 + 0.15 + 0.46
		var xi: float = clampf(float(i if i >= 0 else 2) - 2.0, -2.0, 2.0) * 0.46
		var zs: float = BANC_Z + 0.04 - 0.42
		return Vector3(xi, y_banc - 0.45, -zs if avant else zs)
	var W: float = _largeur_siege()
	var k: int = i if i >= 0 else maxi(0, places / 2 - 1)
	var cx: float = -W * 0.5 + 0.10 + 0.50 * (k + 0.5)
	var y_assise: float = -_haut_suspente() - 0.12 - 0.98 + 0.045
	return Vector3(cx, y_assise - 0.45, -0.42)


## Formes de collision (repère NON MIROIR du véhicule, extérieur de la
## boucle du côté `cote_ext` = ±1 en x) : assise et dossier d'un siège ;
## plancher, toit et parois d'une cabine, la paroi côté portes à part (on
## l'active portes fermées). [[taille, centre, est_porte]…]
func formes_collision(cote_ext: float) -> Array:
	var f: Array = []
	if famille.begins_with("perche") or famille == "cabine_3s" or famille == "cabine_tph":
		return f
	if cabine:
		var hs: float = 1.15
		var yb: float = -hs - 0.10 - 2.25
		f.append([Vector3(2.3, 0.15, 1.5), Vector3(0, yb + 0.075, 0), false])           # plancher
		f.append([Vector3(2.0, 0.10, 1.0), Vector3(0, -hs - 0.15, 0), false])           # toit
		f.append([Vector3(2.3, 2.2, 0.06), Vector3(0, yb + 1.15, -0.80), false])        # face avant
		f.append([Vector3(2.3, 2.2, 0.06), Vector3(0, yb + 1.15, 0.80), false])         # face arrière
		f.append([Vector3(0.06, 2.2, 1.6), Vector3(-cote_ext * 1.17, yb + 1.15, 0), false])  # côté plein
		f.append([Vector3(0.06, 2.2, 1.6), Vector3(cote_ext * 1.17, yb + 1.15, 0), true])    # côté portes
		f.append([Vector3(2.2, 0.45, 0.40), Vector3(0, yb + 0.37, BANC_Z), false])      # banquettes
		f.append([Vector3(2.2, 0.45, 0.40), Vector3(0, yb + 0.37, -BANC_Z), false])
		return f
	var W: float = _largeur_siege()
	var y_s: float = -_haut_suspente() - 0.12 - 0.98
	f.append([Vector3(W, 0.12, 0.50), Vector3(0, y_s, -0.08), false])
	f.append([Vector3(W, 0.60, 0.08), Vector3(0, y_s + 0.36, 0.22), false])
	return f


func _largeur_siege() -> float:
	return 0.50 * places + 0.20


func _haut_suspente() -> float:
	return 2.35 if places >= 6 else 2.05


func _siege() -> void:
	var fixe: bool = constructeur() == "fixe"
	var x0: float = 0.10 if not fixe else 0.07     # attache de la suspente sous la pince
	var hs: float = _haut_suspente()
	var sus_m: String = "acier_noir" if constructeur() in ["poma", "leitner"] else "galva"
	# suspente : sort de la pince vers l'extérieur, descend, puis revient au
	# droit du câble au-dessus du dossier (le véhicule pend sous le câble)
	var pts: PackedVector3Array = PackedVector3Array()
	# attache sous le bras de la pince (débrayable) ou sous la monopince (fixe)
	var x_att: float = 0.30 if not fixe else x0 + 0.10
	var y_att: float = 0.14 if not fixe else 0.02
	pivot = Vector3(x_att, y_att, 0)
	pts.append(Vector3(x_att, y_att, 0))
	pts.append(Vector3(0.46, y_att - 0.04, 0))
	pts.append(Vector3(0.52, -0.25, 0))
	pts.append(Vector3(0.50, -hs + 0.70, 0))
	for p in RemonteeKit.arc(Vector3(0.10, -hs + 0.70, 0), Vector3.RIGHT, Vector3.DOWN, 0.40, 0.0, PI * 0.5, 8):
		pts.append(p)
	RemonteeKit.tube(self, pts, 0.045, sus_m, 10)
	var siege: Node3D = Node3D.new()
	siege.name = "Siege"
	siege.position = Vector3(0.0, -hs - 0.12, 0)
	add_child(siege)
	var W: float = _largeur_siege()
	# arceau supérieur (barre transversale qui porte le siège)
	RemonteeKit.barre(siege, Vector3(-W * 0.5, 0.10, 0.20), Vector3(W * 0.5, 0.10, 0.20), 0.04, sus_m, 10)
	RemonteeKit.barre(siege, Vector3(0.10, 0.10, 0.20), Vector3(0.10, 0.40, 0.20), 0.045, sus_m, 10)
	# montants latéraux
	for sx in [-1.0, 1.0]:
		var x: float = sx * W * 0.5
		# montant : de l'arceau au bord de l'assise, en suivant le dossier
		RemonteeKit.tube(siege, PackedVector3Array([Vector3(x, 0.10, 0.20), Vector3(x, -0.30, 0.26),
			Vector3(x, -0.92, 0.20), Vector3(x, -0.98, 0.10), Vector3(x, -1.02, -0.30)]), 0.03, sus_m, 8)
	# assise et dossier rembourrés, place par place (couleurs selon la
	# famille), sur un bac d'assise et une coque de dossier qui courent sur
	# toute la largeur (retour d'utilisateur, 23/10/2026 : « un beau design de siège »)
	var assises: Array = _couleurs_assise()
	var dossier_h: float = 0.42 if famille == "siege_poma_ocr6" else 0.62
	var t_assise: Basis = Basis(Vector3.RIGHT, 0.10)
	var t_dos: Basis = Basis(Vector3.RIGHT, -0.18)
	var y_dos: float = -0.98 + dossier_h * 0.5 + 0.06
	RemonteeKit.coussin(siege, Vector3(W - 0.02, 0.05, 0.52), Transform3D(t_assise, Vector3(0, -1.035, -0.07)), "coque_siege", 0.02)
	RemonteeKit.coussin(siege, Vector3(W - 0.02, dossier_h + 0.08, 0.05), Transform3D(t_dos, Vector3(0, y_dos, 0.255)), "coque_siege", 0.022)
	for i in range(places):
		var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
		var m: String = assises[i % assises.size()]
		var a: MeshInstance3D = RemonteeKit.coussin(siege, Vector3(0.47, 0.085, 0.48),
			Transform3D(t_assise, Vector3(cx, -0.975, -0.08)), m, 0.035)
		a.name = "Assise%d" % i
		RemonteeKit.coussin(siege, Vector3(0.47, dossier_h, 0.08), Transform3D(t_dos, Vector3(cx, y_dos, 0.20)), m, 0.035)
	# attaches du dossier sous l'arceau
	var y_haut_dos: float = -0.98 + dossier_h + 0.08
	for sx in [-1.0, 1.0]:
		var xs: float = sx * W * 0.25
		RemonteeKit.barre(siege, Vector3(xs, 0.10, 0.20), Vector3(xs, y_haut_dos, 0.21 + (y_haut_dos + 0.98) * 0.18), 0.03, sus_m, 8)
	# poutre sous l'assise et accoudoirs garnis aux deux bouts
	RemonteeKit.poutre(siege, Vector3(-W * 0.5 + 0.05, -1.10, 0.02), Vector3(W * 0.5 - 0.05, -1.10, 0.02), 0.07, 0.09, sus_m)
	for sx in [-1.0, 1.0]:
		var xa: float = sx * (W * 0.5 - 0.02)
		RemonteeKit.barre(siege, Vector3(xa, -0.70, 0.18), Vector3(xa, -0.70, -0.25), 0.022, sus_m, 8)
		RemonteeKit.barre(siege, Vector3(xa, -0.70, -0.25), Vector3(xa, -0.98, -0.28), 0.022, sus_m, 8)
		RemonteeKit.coussin(siege, Vector3(0.07, 0.045, 0.40), Transform3D(Basis.IDENTITY, Vector3(xa, -0.67, -0.04)), "coque_siege", 0.02)
	_garde_corps(siege, W, sus_m)
	if famille.ends_with("_bulle"):
		_bulle_siege(siege, W)


func _couleurs_assise() -> Array:
	match famille:
		"siege_poma_ocr6":
			return ["assise_bleue", "assise_noire"]
		"siege_garaventa_sk6":
			return ["assise_bleue"]
		"siege_bartholet_6":
			return ["assise_noire"]
		"siege_doppelmayr_e98_6":
			return ["assise_noire", "assise_bleue"]
		"siege_fixe_4", "siege_fixe_3":
			return ["assise_grise"]
		_:
			return ["assise_noire"]


## Garde-corps : pivote autour d'un axe transversal au-dessus de l'arceau ;
## relevé il passe au-dessus des têtes, baissé il tombe devant le ventre
## avec ses repose-pieds (et les tenons de sécurité des Poma OCR).
func _garde_corps(siege: Node3D, W: float, m: String) -> void:
	_gc = Node3D.new()
	_gc.name = "GardeCorps"
	_gc.position = Vector3(0, 0.10, 0.20)          # axe sur l'arceau
	siege.add_child(_gc)
	# géométrie dessinée en position BAISSÉE (repère du pivot) : bras vers
	# l'avant et le bas, barre ventrale devant le ventre, repose-pieds sous
	# les chaussures ; relevé = rotation de 2,4 rad autour de l'axe
	var ventre: Vector3 = Vector3(0, -0.73, -0.75)
	var pied: Vector3 = Vector3(0, -1.50, -0.62)
	var xe: float = W * 0.5 - 0.06
	for sx in [-1.0, 1.0]:
		RemonteeKit.tube(_gc, PackedVector3Array([Vector3(sx * xe, 0, 0), Vector3(sx * xe, -0.20, -0.42),
			Vector3(sx * xe, ventre.y, ventre.z)]), 0.022, m, 8)
	RemonteeKit.barre(_gc, Vector3(-xe, ventre.y, ventre.z), Vector3(xe, ventre.y, ventre.z), 0.025, m, 8)
	for sx in [-1.0, 1.0]:
		var x: float = sx * W * 0.22
		RemonteeKit.barre(_gc, Vector3(x, ventre.y, ventre.z), Vector3(x, pied.y, pied.z), 0.02, m, 6)
	RemonteeKit.barre(_gc, Vector3(-W * 0.5 + 0.15, pied.y, pied.z), Vector3(W * 0.5 - 0.15, pied.y, pied.z), 0.022, m, 8)
	RemonteeKit.boite_en(_gc, Vector3(W - 0.4, 0.02, 0.16), Vector3(0, pied.y - 0.01, pied.z + 0.04), "caoutchouc")
	# tenons de sécurité (un par place, devant chaque assise)
	if famille in ["siege_poma_ocr6", "siege_bartholet_6", "siege_doppelmayr_e98_6"]:
		for i in range(places):
			var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
			RemonteeKit.barre(_gc, Vector3(cx, ventre.y, ventre.z), Vector3(cx, ventre.y - 0.30, ventre.z + 0.05), 0.016, m, 6)


## 0 : relevé (au-dessus des têtes) ; 1 : baissé.
func garde_corps(t: float) -> void:
	if _gc != null:
		_gc.rotation.x = lerpf(2.40, 0.0, clampf(t, 0.0, 1.0))


## Bulle (Lanches) : coque de polycarbonate en quart de cylindre, pivotant
## sur l'arceau ; ouverte elle se range au-dessus du dossier.
func _bulle_siege(siege: Node3D, W: float) -> void:
	_bulle = Node3D.new()
	_bulle.name = "Bulle"
	_bulle.position = Vector3(0, 0.18, 0.22)
	siege.add_child(_bulle)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R: float = 1.30
	var n: int = 16
	for i in range(n):
		var a0: float = lerpf(-0.05, PI * 0.62, float(i) / n)
		var a1: float = lerpf(-0.05, PI * 0.62, float(i + 1) / n)
		var p0: Vector3 = Vector3(0, -sin(a0) * R, -cos(a0) * R)
		var p1: Vector3 = Vector3(0, -sin(a1) * R, -cos(a1) * R)
		var xa: float = -W * 0.5 - 0.05
		var xb: float = W * 0.5 + 0.05
		var n0: Vector3 = Vector3(0, -sin(a0), -cos(a0))
		for v in [[Vector3(xa, p0.y, p0.z), n0], [Vector3(xb, p0.y, p0.z), n0], [Vector3(xb, p1.y, p1.z), n0],
				[Vector3(xa, p0.y, p0.z), n0], [Vector3(xb, p1.y, p1.z), n0], [Vector3(xa, p1.y, p1.z), n0]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, RemonteeKit.mat("bulle"))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Coque"
	_bulle.add_child(mi)
	# flasques latérales et logo (cadre)
	for sx in [-1.0, 1.0]:
		RemonteeKit.tube(_bulle, RemonteeKit.arc(Vector3(sx * (W * 0.5 + 0.05), 0, 0), Vector3.FORWARD, Vector3.DOWN, R, -0.05, PI * 0.62, 12),
			0.02, "acier_noir", 6)
	RemonteeKit.tube(_bulle, PackedVector3Array([Vector3(-W * 0.5 - 0.05, -sin(PI * 0.62) * R, -cos(PI * 0.62) * R),
		Vector3(W * 0.5 + 0.05, -sin(PI * 0.62) * R, -cos(PI * 0.62) * R)]), 0.025, "acier_noir", 6)


## 0 : ouverte (relevée sur le dossier) ; 1 : fermée devant les passagers.
func bulle(t: float) -> void:
	if _bulle != null:
		_bulle.rotation.x = lerpf(2.1, 0.0, clampf(t, 0.0, 1.0))


# --- cabines -------------------------------------------------------------------------

func _cabine() -> void:
	pivot = Vector3(0.30, 0.14, 0)
	var sus_m: String = "acier_noir" if famille != "cabine_omega4" else "galva"
	var hs: float = 1.15
	# suspente (plans CWA de l'Omega V, Wikimedia Commons) : de la pince elle
	# descend à l'extérieur, se cintre vers l'intérieur et finit en poutre
	# horizontale posée sur le toit par deux pieds
	var arc: PackedVector3Array = PackedVector3Array()
	var p0: Vector3 = Vector3(0.30, 0.14, 0)
	var p1: Vector3 = Vector3(0.66, -0.10, 0)
	var p2: Vector3 = Vector3(0.70, -hs + 0.05, 0)
	var p3: Vector3 = Vector3(0.22, -hs + 0.10, 0)
	for k in range(17):
		var t: float = float(k) / 16.0
		var u: float = 1.0 - t
		arc.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	RemonteeKit.tube(self, arc, 0.058, sus_m, 12)
	RemonteeKit.poutre(self, Vector3(0.26, -hs + 0.10, 0), Vector3(-0.42, -hs + 0.12, 0), 0.12, 0.07, sus_m)
	for xp in [-0.30, 0.14]:
		RemonteeKit.boite_en(self, Vector3(0.07, 0.20, 0.10), Vector3(xp, -hs + 0.0, 0), sus_m)
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hs - 0.10, 0)
	add_child(cab)
	var H: float = _CAB_H
	var mailles: Dictionary = _maillage_cabine(famille)
	for cle in ["coque", "vitres"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = cle.capitalize()
		mi.mesh = mailles[cle]
		cab.add_child(mi)
	# portes : deux vantaux découpés dans la face en œuf, qui coulissent
	# vers l'extérieur par-dessus les panneaux fixes
	for sz in [-1.0, 1.0]:
		var v: Node3D = Node3D.new()
		v.name = "Vantail%s" % ("Avant" if sz < 0 else "Arriere")
		cab.add_child(v)
		for cle in ["porte_coque", "porte_vitre"]:
			var mi2: MeshInstance3D = MeshInstance3D.new()
			mi2.mesh = mailles[cle + ("_p" if sz > 0 else "_m")]
			v.add_child(mi2)
		# poignée verticale près de la jonction des vantaux
		RemonteeKit.barre(v, Vector3(1.28, -H + 0.95, sz * 0.07), Vector3(1.28, -H + 1.45, sz * 0.07), 0.016, "acier", 8)
		_portes.append([v, Vector3.ZERO, Vector3(0.06, 0, sz * PORTE_DEMI)])
	# tampons de caoutchouc aux quatre angles, à hauteur du bas des vitres
	for sx in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var tp: Vector3 = Vector3(sx * 1.24, -1.12, sz2 * 0.66)
			RemonteeKit.coussin(cab, Vector3(0.10, 0.42, 0.16), Transform3D(Basis.IDENTITY, tp), "noir_mat", 0.045)
	# intérieur : plancher, deux banquettes de 5 places (46 cm) face à face,
	# dossiers contre les faces longues, plafonnier
	var yp: float = -H + 0.15
	# (le fond se resserre : plancher et pieds de banquettes restent dans la coque)
	RemonteeKit.boite_en(cab, Vector3(2.00, 0.03, 0.95), Vector3(0, yp + 0.005, 0), "noir_mat")
	for k in range(-3, 4):
		RemonteeKit.boite_en(cab, Vector3(1.90, 0.012, 0.02), Vector3(0, yp + 0.025, k * 0.14), "acier")
	var sieges: String = "assise_grise" if famille != "cabine_diamond" else "assise_noire"
	for sz in [-1.0, 1.0]:
		var zb: float = sz * BANC_Z
		RemonteeKit.boite_en(cab, Vector3(2.00, 0.34, 0.20), Vector3(0, yp + 0.18, sz * 0.40), "noir_mat")
		for i in range(5):
			var xi: float = (i - 2) * 0.46
			RemonteeKit.coussin(cab, Vector3(0.44, 0.09, 0.42), Transform3D(Basis(Vector3.RIGHT, -sz * 0.06), Vector3(xi, yp + 0.41, zb)), sieges, 0.035)
			RemonteeKit.coussin(cab, Vector3(0.44, 0.50, 0.07), Transform3D(Basis(Vector3.RIGHT, sz * 0.12), Vector3(xi, yp + 0.76, sz * (BANC_Z + 0.22))), sieges, 0.03)
	RemonteeKit.boite_en(cab, Vector3(1.20, 0.02, 0.50), Vector3(0, -0.22, 0), "blanc_plaque")
	if famille == "cabine_diamond":
		# porte-skis extérieurs sur la face opposée aux portes : deux paniers
		for sz in [-1.0, 1.0]:
			var zp: float = sz * 0.45
			for yk in [-H + 0.62, -H + 1.62]:
				RemonteeKit.boite_en(cab, Vector3(0.20, 0.06, 0.30), Vector3(-1.36, yk, zp), "acier_noir")
			for dz in [-0.12, 0.12]:
				RemonteeKit.barre(cab, Vector3(-1.45, -H + 0.62, zp + dz), Vector3(-1.45, -H + 1.62, zp + dz), 0.015, "acier_noir", 6)


## Caisse d'après les plans CWA de l'Omega V (Wikimedia Commons, CC BY-SA) et
## des photos de cabines (Méribel, Orelle) : 2,46 m en travers du câble
## (banquettes de 5 places de 46 cm), 1,68 m dans le sens du câble, 2,25 m
## de haut ; face des portes en œuf, faces longues en trapèze arrondi ;
## grand vitrage de 0,30 à 1,35 m sous le toit ; porte de 0,90 m.
const PORTE_DEMI: float = 0.45          # demi-largeur de la baie de porte
const _CAB_H: float = 2.25
const BANC_Z: float = 0.50              # milieu des assises (de part et d'autre)


## Anneaux du toit au fond : [profondeur sous le toit, demi-largeur x
## (travers du câble), demi-longueur z (sens du câble), bande jusqu'à
## l'anneau suivant]. Les demi-dimensions sont lues sur les plans.
static func _profil_cabine(fam: String) -> Array:
	var anneaux: Array = []
	var cotes: Array = [
		# d,    a,    b,    bande
		[0.00, 0.80, 0.40, "toit"],
		[0.07, 0.90, 0.45, "liseré"],
		[0.13, 0.97, 0.48, "cadre"],
		[0.19, 1.00, 0.50, "vitre"],
		[0.30, 1.06, 0.58, "cadre"],
		[0.34, 1.08, 0.61, "vitre"],
		[0.60, 1.14, 0.70, "vitre"],
		[0.97, 1.19, 0.84, "vitre"],
		[1.33, 1.23, 0.84, "cadre"],
		[1.38, 1.23, 0.84, "caisse"],
		[1.66, 1.20, 0.80, "caisse"],
		[1.84, 1.16, 0.70, "caisse"],
		[1.97, 1.12, 0.62, "caisse"],
		[2.13, 1.06, 0.49, "caisse"],
		[2.25, 0.98, 0.41, ""],
	]
	if fam == "cabine_diamond" or fam == "cabine_symphony":
		# Sigma : vitrage plus bas (photos de Méribel)
		cotes[9][3] = "vitre"
		cotes[10][3] = "cadre"
	for c in cotes:
		var a: float = c[1]
		var b: float = c[2]
		anneaux.append([-float(c[0]), a, b, minf(0.34, b * 0.55), c[3]])
	return anneaux


## Points du contour (rectangle à coins arrondis), toujours dans le même
## ordre : [point, côté X+ ?, abscisse réduite s sur le côté X+ (−1…1),
## arête (milieu d'un angle) ?].
static func _contour(a: float, b: float, r: float) -> Array:
	var out: Array = []
	# subdivisions fines aux bords de la baie de porte (s = ±0,75) et au
	# milieu (jonction des vantaux)
	var cotes: Array = [-1.0, -0.86, -0.75, -0.70, -0.40, -0.06, 0.0, 0.06, 0.40, 0.70, 0.75, 0.86]
	var nc: int = 8
	var ca: Array = [[1.0, 1.0, 0.0], [-1.0, 1.0, PI * 0.5], [-1.0, -1.0, PI], [1.0, -1.0, PI * 1.5]]
	for c in range(4):
		for sv in cotes:
			var p: Vector3
			match c:
				0:
					p = Vector3(a, 0, sv * (b - r))
				1:
					p = Vector3(-sv * (a - r), 0, b)
				2:
					p = Vector3(-a, 0, -sv * (b - r))
				3:
					p = Vector3(sv * (a - r), 0, -b)
			out.append([p, c == 0, sv, false])
		var cx: float = ca[c][0] * (a - r)
		var cz: float = ca[c][1] * (b - r)
		for k in range(nc):
			var th: float = ca[c][2] + PI * 0.5 * float(k) / nc
			out.append([Vector3(cx + r * cos(th), 0, cz + r * sin(th)), false, 0.0, k == 3 or k == 4])
	return out


static var _cache_cabines: Dictionary = {}


## Couleurs : caisse (bas), cadre (pourtour noir), toit, liseré.
static func _mat_cabine(nom: String, fam: String) -> Material:
	var cle: String = nom + "|" + fam
	if _cache_cabines.has(cle):
		return _cache_cabines[cle]
	var base: String = nom
	match nom:
		"caisse":
			base = {"cabine_diamond": "cabine_noire", "cabine_symphony": "cabine_blanche"}.get(fam, "cabine_rouge")
		"liseré":
			base = {"cabine_diamond": "acier", "cabine_symphony": "cabine_bleue"}.get(fam, "cabine_rouge")
		"toit", "cadre":
			base = "cabine_noire"
		"vitre":
			base = "vitre_teintee"
	var m: Material = RemonteeKit.mat(base)
	if nom != "vitre":
		# double face : on voit l'intérieur de la caisse à travers les vitres
		var m2: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = m2
	_cache_cabines[cle] = m
	return m


## Maillages (partagés par famille) de la caisse, de son vitrage et des deux
## vantaux : surfaces lissées par anneaux, bande par bande.
static func _maillage_cabine(fam: String) -> Dictionary:
	if _cache_cabines.has(fam):
		return _cache_cabines[fam]
	var prof: Array = _profil_cabine(fam)
	var H: float = _CAB_H
	var y_haut_porte: float = -0.19
	var y_bas_porte: float = -H + 0.12
	var anneaux: Array = []
	for r in prof:
		anneaux.append(_contour(r[1], r[2], r[3]))
	var n: int = anneaux[0].size()
	var st: Dictionary = {}
	var st_porte: Dictionary = {1.0: {}, -1.0: {}}
	var quad = func(dico: Dictionary, mat: String, q: Array, dx: float) -> void:
		if not dico.has(mat):
			var s0: SurfaceTool = SurfaceTool.new()
			s0.begin(Mesh.PRIMITIVE_TRIANGLES)
			s0.set_smooth_group(0)
			dico[mat] = s0
		var s1: SurfaceTool = dico[mat]
		var d: Vector3 = Vector3(dx, 0, 0)
		for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			s1.add_vertex(v + d)
	# le fond est redécoupé : anneau supplémentaire au plancher pour la porte
	for i in range(prof.size() - 1):
		var mat_bande: String = prof[i][4]
		var y0: float = prof[i][0]
		var y1: float = prof[i + 1][0]
		for k in range(n):
			var k2: int = (k + 1) % n
			var a0: Array = anneaux[i][k]
			var a1: Array = anneaux[i][k2]
			var b0: Array = anneaux[i + 1][k]
			var b1: Array = anneaux[i + 1][k2]
			var q: Array = [(a0[0] as Vector3) + Vector3(0, y0, 0), (b0[0] as Vector3) + Vector3(0, y1, 0),
				(b1[0] as Vector3) + Vector3(0, y1, 0), (a1[0] as Vector3) + Vector3(0, y0, 0)]
			var mat: String = mat_bande
			# arêtes verticales : le cadre fait le tour de la caisse
			if mat == "vitre" and a0[3] and a1[3]:
				mat = "cadre"
			# baie de porte : face X+ (en œuf), |s| < 0,75, du plancher au haut des vitres
			var s_mid: float = (float(a0[2]) + float(a1[2])) * 0.5
			var dans_baie: bool = a0[1] and a1[1] and absf(s_mid) < 0.75 and y0 <= y_haut_porte + 0.001 \
				and y1 >= y_bas_porte - 0.001
			if dans_baie:
				var cote: float = 1.0 if s_mid > 0.0 else -1.0
				var mp: String = "vitre" if y1 > -H + 0.45 else "cadre"
				# montants des vantaux : bords de la baie et jonction centrale
				if absf(s_mid) > 0.70 or absf(s_mid) < 0.06:
					mp = "cadre"
				quad.call(st_porte[cote], mp, q, 0.03)
				continue
			quad.call(st, mat, q, 0.0)
	# fond et toit fermés en éventail
	for bout in [[0, 1.0, "toit"], [prof.size() - 1, -1.0, "caisse"]]:
		var i3: int = bout[0]
		var y3: float = prof[i3][0]
		var c: Vector3 = Vector3(0, y3 + 0.03 * float(bout[1]), 0)
		for k in range(n):
			var p0: Vector3 = (anneaux[i3][k][0] as Vector3) + Vector3(0, y3, 0)
			var p1: Vector3 = (anneaux[i3][(k + 1) % n][0] as Vector3) + Vector3(0, y3, 0)
			quad.call(st, bout[2], [p0, p0.lerp(c, 0.5), c, p1] if bout[1] > 0.0 else [p0, p1, c, p0.lerp(c, 0.5)], 0.0)
	var res: Dictionary = {}
	res["coque"] = _assembler(st, fam, false)
	res["vitres"] = _assembler(st, fam, true)
	res["porte_coque_p"] = _assembler(st_porte[1.0], fam, false)
	res["porte_vitre_p"] = _assembler(st_porte[1.0], fam, true)
	res["porte_coque_m"] = _assembler(st_porte[-1.0], fam, false)
	res["porte_vitre_m"] = _assembler(st_porte[-1.0], fam, true)
	_cache_cabines[fam] = res
	return res


static func _assembler(dico: Dictionary, fam: String, vitres: bool) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	for mat in dico.keys():
		if (mat == "vitre") != vitres:
			continue
		var s: SurfaceTool = dico[mat]
		var copie: SurfaceTool = SurfaceTool.new()
		copie.create_from_arrays(s.commit_to_arrays())
		copie.set_smooth_group(0)
		copie.index()
		copie.generate_normals()
		copie.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_cabine(mat, fam))
	return mesh


func portes(t: float) -> void:
	for p in _portes:
		(p[0] as Node3D).position = (p[1] as Vector3) + (p[2] as Vector3) * clampf(t, 0.0, 1.0)


# --- téléskis ----------------------------------------------------------------------

var _corde: Node3D               # enrouleur : corde et perche (s'étirent en montée)
var _perche_tige: Node3D


## Perche de téléski. Enrouleur (TKE) : boîtier à tambour serré sur le câble,
## corde qui se déroule jusqu'au skieur, perche à rondelle (ou barre en T
## biplace). Débrayable (TKD) : douille auto-coinçante sur le câble, perche
## rigide télescopique à assiette.
func _perche() -> void:
	if famille == "perche_debrayable":
		# douille auto-coinçante + perche télescopique
		RemonteeKit.boite_en(self, Vector3(0.10, 0.12, 0.22), Vector3(0, 0.02, 0), "galva")
		RemonteeKit.cylindre(self, 0.03, 0.03, 0.10, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.10, 0.06)), "caoutchouc", 10)
		_perche_tige = Node3D.new()
		_perche_tige.name = "Perche"
		add_child(_perche_tige)
		RemonteeKit.barre(_perche_tige, Vector3(0, -0.05, 0), Vector3(0, -1.7, 0), 0.026, "acier", 8)
		RemonteeKit.barre(_perche_tige, Vector3(0, -1.7, 0), Vector3(0, -3.4, 0), 0.020, "galva", 8)
		RemonteeKit.cylindre(_perche_tige, 0.035, 0.035, 0.30, Transform3D(Basis.IDENTITY, Vector3(0, -1.65, 0)), "acier_noir", 10)
		RemonteeKit.cylindre(_perche_tige, 0.13, 0.13, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -3.45, 0)), "jaune_securite", 18)
		return
	# enrouleur : boîtier + tambour + pince fixe
	RemonteeKit.boite_en(self, Vector3(0.12, 0.10, 0.26), Vector3(0, 0.03, 0), "galva")
	RemonteeKit.boite_en(self, Vector3(0.30, 0.42, 0.34), Vector3(0, -0.24, 0), "peinture_gris")
	RemonteeKit.cylindre(self, 0.15, 0.15, 0.32, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.24, 0)), "acier_noir", 18)
	_corde = Node3D.new()
	_corde.name = "Corde"
	_corde.position = Vector3(0, -0.45, 0)
	add_child(_corde)
	RemonteeKit.barre(_corde, Vector3.ZERO, Vector3(0, -1.0, 0), 0.008, "acier_noir", 6)
	_perche_tige = Node3D.new()
	_perche_tige.name = "Perche"
	add_child(_perche_tige)
	RemonteeKit.barre(_perche_tige, Vector3(0, 0, 0), Vector3(0, -1.10, 0), 0.02, "jaune_securite", 8)
	if famille == "perche_tbar":
		RemonteeKit.barre(_perche_tige, Vector3(-0.50, -1.10, 0), Vector3(0.50, -1.10, 0), 0.03, "jaune_securite", 8)
		RemonteeKit.cylindre(_perche_tige, 0.035, 0.035, 1.0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -1.10, 0)), "caoutchouc", 10)
	else:
		RemonteeKit.cylindre(_perche_tige, 0.12, 0.12, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -1.12, 0)), "assise_noire", 18)
	deroule(0.0)


## Enrouleur : 0 = corde rentrée (perche contre le boîtier), 1 = déroulée
## (skieur tracté, perche ~4 m sous le câble).
func deroule(t: float) -> void:
	if _corde == null:
		return
	var l: float = lerpf(0.25, 3.6, clampf(t, 0.0, 1.0))
	_corde.scale = Vector3(1, l, 1)
	_perche_tige.position = Vector3(0, -0.45 - l, 0)


# --- grandes cabines : 3S et téléphérique -----------------------------------------

## Chariot roulant sur les câbles porteurs (galets en ligne), suspente
## rigide, grande caisse. 3S : cabine CWA Zeta 30 places (24 assises),
## chariot de 2 × 4 galets sur DEUX porteurs, pince sur le tracteur.
## Téléphérique : cabine de 80-115 places avec poste du conducteur, chariot
## de 8 galets par porteur.
func _grande_cabine() -> void:
	var tph: bool = famille == "cabine_tph"
	var e_porteurs: float = 0.60 if not tph else 0.70     # écart des deux porteurs
	var n_g: int = 4 if not tph else 8
	var lc: float = 0.55 * n_g + 0.6
	# chariot : deux trains de galets (un par porteur) reliés par un châssis
	for sx in [-0.5, 0.5]:
		for k in range(n_g):
			RemonteeKit.galet(self, Vector3(sx * e_porteurs, -0.05 - 0.21 * 0.0 + 0.23, -lc * 0.5 + 0.3 + k * 0.55), 0.20, 0.08)
		RemonteeKit.boite_en(self, Vector3(0.06, 0.40, lc), Vector3(sx * e_porteurs + signf(sx) * 0.10, 0.25, 0), "galva")
	RemonteeKit.boite_en(self, Vector3(e_porteurs + 0.4, 0.22, lc * 0.7), Vector3(0, 0.58, 0), "acier_noir" if not tph else "peinture_gris")
	# pince / attache sur le câble tracteur (sous le chariot)
	RemonteeKit.boite_en(self, Vector3(0.18, 0.16, 0.6), Vector3(0, -0.25, 0), "acier")
	# suspente : deux bras jusqu'au toit
	var hc: float = 2.6 if not tph else 3.2
	for sz in [-1.0, 1.0]:
		RemonteeKit.tube(self, PackedVector3Array([Vector3(0, 0.5, sz * lc * 0.25), Vector3(0.0, -0.3, sz * lc * 0.25),
			Vector3(0, -hc + 0.2, sz * 0.8)]), 0.07, "acier_noir", 10)
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hc, 0)
	add_child(cab)
	var L: float = 3.6 if not tph else 6.0
	var Wc: float = 2.4 if not tph else 3.0
	var H: float = 2.5 if not tph else 2.6
	var c: String = "cabine_bleue" if not tph else "cabine_rouge"
	RemonteeKit.boite_en(cab, Vector3(Wc, 0.16, L), Vector3(0, -H, 0), c)
	RemonteeKit.boite_en(cab, Vector3(Wc, 0.20, L), Vector3(0, 0.0, 0), c)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			RemonteeKit.boite_en(cab, Vector3(0.12, H, 0.12), Vector3(sx * (Wc * 0.5 - 0.06), -H * 0.5, sz * (L * 0.5 - 0.06)), c)
	var yv: float = -H + 0.95
	var hv: float = -0.10 - yv
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(cab, Vector3(0.04, yv + H, L - 0.24), Vector3(sx * (Wc * 0.5 - 0.02), (-H + yv) * 0.5, 0), c)
		RemonteeKit.boite_en(cab, Vector3(0.02, hv, L - 0.24), Vector3(sx * (Wc * 0.5 - 0.02), yv + hv * 0.5, 0), "vitre")
	for sz in [-1.0, 1.0]:
		RemonteeKit.boite_en(cab, Vector3(Wc - 0.24, yv + H, 0.04), Vector3(0, (-H + yv) * 0.5, sz * (L * 0.5 - 0.02)), c)
		RemonteeKit.boite_en(cab, Vector3(Wc - 0.24, hv, 0.02), Vector3(0, yv + hv * 0.5, sz * (L * 0.5 - 0.02)), "vitre")
	# portes : 3S une large porte coulissante de chaque côté ; TPH portes battantes côté quai
	for sx in [-1.0, 1.0]:
		var v: Node3D = Node3D.new()
		v.name = "Porte%s" % ("Droite" if sx > 0 else "Gauche")
		v.position = Vector3(sx * (Wc * 0.5 + 0.03), 0, 0)
		cab.add_child(v)
		RemonteeKit.boite_en(v, Vector3(0.03, H - 0.25, 1.2), Vector3(0, -H * 0.5 + 0.02, 0), c)
		RemonteeKit.boite_en(v, Vector3(0.02, hv, 1.05), Vector3(0.012 * sx, yv + hv * 0.5, 0), "vitre")
		_portes.append([v, v.position, Vector3(0.06 * sx, 0, 1.15)])
	# bancs (3S : 24 assises en deux banquettes face à face)
	if not tph:
		for sz in [-1.0, 1.0]:
			RemonteeKit.boite_en(cab, Vector3(Wc - 0.3, 0.08, 0.45), Vector3(0, -H + 0.55, sz * (L * 0.5 - 0.35)), "assise_noire")
			RemonteeKit.boite_en(cab, Vector3(Wc - 0.3, 0.5, 0.06), Vector3(0, -H + 0.85, sz * (L * 0.5 - 0.12)), "assise_noire")
	else:
		# poste du conducteur à l'avant, barres de maintien
		RemonteeKit.boite_en(cab, Vector3(0.9, 1.0, 0.5), Vector3(0, -H + 0.6, -L * 0.5 + 0.4), "peinture_anthracite")
		for k in range(4):
			RemonteeKit.barre(cab, Vector3(-Wc * 0.4, -0.45, -L * 0.3 + k * 1.0), Vector3(Wc * 0.4, -0.45, -L * 0.3 + k * 1.0), 0.02, "acier", 6)
