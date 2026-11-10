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
var _ressorts: Array = []
var _galets_roul: Array = []      # galets du chariot du 3S (axe local X)
## Rayon de roulement du galet, au fond de la gorge ; flasques à R_FLASQUE_CHARIOT (estimés sur photo).
const R_GALET_CHARIOT: float = 0.19
const R_FLASQUE_CHARIOT: float = 0.22


## Le chariot a avancé de `ds` m sur les porteurs : ses galets tournent.
func rouler(ds: float) -> void:
	if _galets_roul.is_empty() or ds == 0.0:
		return
	for g in _galets_roul:
		(g as Node3D).rotate_object_local(Vector3.RIGHT, -ds / R_GALET_CHARIOT)
var _ressort_l0: float = 0.32
var _gc: Node3D
## Véhicule posé en miroir sur sa ligne (ligne qui monte à gauche) : les
## numéros sont contre-inversés pour rester lisibles.
var miroir: bool = false
## Livrée de la station (« Val d'Isère » : aigle et nom sur les caisses des
## télécabines et du 3S — photo d'une cabine de l'Olympique, retour d'utilisateur,
## 25/10/2026). Posée par la ligne.
var livree: String = ""
var pince_a108: bool = false            # pince A-108 (Tommeuses, Bollin, Fresse)
var teinte: String = ""                # caisse propre à la ligne : "gris", "noire" (sinon, celle de la famille)
var _skis_ranges: Array = []
var _etat_anim: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])   # pince, garde-corps, bulle, portes    # skis au porte-skis des cabines (un par vantail)
var numero: int = 0
var _gc_releve: float = 2.40     # angle du garde-corps relevé (rad)
var _bulle: Node3D
var _portes: Array = []        # [nœud, position fermée, déplacement à l'ouverture]
var places: int = 6
var cabine: bool = false
## Dessus de la plaque de friction de la pince débrayable, au-dessus de
## l'axe du câble (les pneus du lanceur y appuient), et son décalage latéral.
## Partie SUSPENDUE (suspente + siège / caisse) : un pendule articulé sous la
## pince, en `pivot` (repère du véhicule). Balancement longitudinal (φ) et
## transversal (ψ) entretenu par les accélérations de la pince — freinage et
## lancement en gare, changements de pente aux pylônes, demi-tour sur la
## poulie — et amorti selon la masse (articulation, air).
var pivot: Vector3 = Vector3.ZERO
var masse: float = 650.0
var longueur_pendule: float = 2.6
## Pince → toit de la télécabine, mesuré en vidéo : Daille 1,46, Tovière 1,45, Solaise 1,65.
const H_SUSP_CABINE: float = 1.50
var _susp: Node3D = null
var _pince: Node3D = null
var phi: float = 0.0
var psi: float = 0.0
## Équilibre du balancement latéral sous une charge excentrée. Tirage : passagers du brin montant ;
## joueur : NAN s'il n'est pas à bord. psi0 et limite_psi sont posés par la ligne avant balancer().
var psi0_tire: float = 0.0
var psi0_joueur: float = NAN
var psi0: float = 0.0
var limite_psi: float = INF
var _dphi: float = 0.0
var _dpsi: float = 0.0
var _p_prec: Vector3 = Vector3.ZERO
var _v_prec: Vector3 = Vector3.ZERO
var _a_f: Vector3 = Vector3.ZERO
var _n_mes: int = 0

const DESCRIPTIONS: Dictionary = {
	"siege_doppelmayr_e98_6": ["Doppelmayr / Études de Transports E98, 6 places", 6, "doppelmayr"],
	"siege_doppelmayr_e98_8": ["Doppelmayr 8 places (Tommeuses)", 8, "doppelmayr"],
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
## La ligne le construit elle-même après l'avoir posé : pas de construction à l'entrée dans l'arbre (sur le fil
## principal, chaque véhicule était construit deux fois, relevé du 07/11/2026).
var construit_par_la_ligne: bool = false


func _ready() -> void:
	if not _construit and not construit_par_la_ligne:
		construire()


func constructeur() -> String:
	return DESCRIPTIONS.get(famille, ["", 6, "doppelmayr"])[2]


## Modèles : un véhicule coûtait ~33 ms à fabriquer (pièces, fusion des
## maillages) — une image entière, et des centaines à l'approche des lignes
## (audit de fluidité, 26/10/2026). Chaque type (famille, miroir, livrée) a
## VARIANTES modèles numérotés au hasard, fabriqués une fois ; les autres
## véhicules en sont des copies, qui partagent les maillages.
const VARIANTES: int = 8
static var _numeros: Dictionary = {}      # type → numéros des variantes
static var _modeles: Dictionary = {}      # type|numéro → [Node3D hors arbre, références, valeurs]
const REFS: Array = ["_machoire", "_gc", "_bulle", "_susp", "_pince", "_corde", "_perche_tige", "_bras"]
const LISTES: Array = ["_ressorts", "_galets_roul", "_skis_ranges"]
const VALEURS: Array = ["places", "cabine", "pivot", "masse", "longueur_pendule", "_gc_releve", "_ressort_l0", "_etat_anim"]


## Modèles libérés en quittant le jeu.
static func vider_modeles() -> void:
	for k in _modeles:
		((_modeles[k] as Array)[0] as Node).free()
	_modeles.clear()


func _type() -> String:
	return "%s|%s|%s|%s|%s|%s" % [famille, str(miroir), livree, teinte, str(pince_a108), style_tph]


func construire() -> void:
	var cle: String = _debut_construction()
	if cle == "":
		return
	for f in _phases_fabrication():
		(f as Callable).call()
	_modeles[cle] = _modele()


## construire() en étapes (pince, corps, fin et fusion), `pause` attendue entre deux : la fabrication d'un modèle
## faisait 7 à 11 ms d'un bloc sur le fil principal (relevé du 07/11/2026). Une copie de modèle reste d'un trait.
func construire_par_tranches(pause: Callable) -> void:
	var cle: String = _debut_construction()
	if cle == "":
		return
	for f in _phases_fabrication():
		(f as Callable).call()
		await pause.call()
	_modeles[cle] = _modele()


## Vide le véhicule, tire son numéro ; copie le modèle s'il existe (rend ""), sinon rend la clé du modèle à fabriquer.
func _debut_construction() -> String:
	_construit = true
	for c in get_children():
		remove_child(c)
		c.queue_free()
	# un seul numéro par véhicule, sur la pince comme sur le siège (la pince
	# en portait un autre — retour d'utilisateur, 23/10/2026 : « numéro fantôme »)
	if numero <= 0:
		var ty: String = _type()
		if not _numeros.has(ty):
			var l: Array = []
			for k in range(VARIANTES):
				l.append(randi() % {"siege_bartholet_6": 81, "cabine_3s": 24}.get(famille, 120) + 1)
			_numeros[ty] = l
		numero = (_numeros[ty] as Array).pick_random()
	var cle: String = "%s|%d" % [_type(), numero]
	if _modeles.has(cle):
		_copier(_modeles[cle])
		return ""
	return cle


## Copie détachée des pièces, et où retrouver les références.
func _modele() -> Array:
	var m: Node3D = Node3D.new()
	for c in get_children():
		m.add_child(c.duplicate())
	var refs: Dictionary = {}
	for r in REFS:
		var n: Node = get(r)
		if n != null:
			refs[r] = _indices(n)
	for r in LISTES:
		refs[r] = (get(r) as Array).map(func(n: Node) -> PackedInt32Array: return _indices(n))
	refs["_portes"] = _portes.map(func(e: Array) -> Array: return [_indices(e[0]), e[1], e[2]])
	var val: Dictionary = {}
	for r in VALEURS:
		val[r] = get(r)
	return [m, refs, val]


func _copier(md: Array) -> void:
	for c in (md[0] as Node3D).get_children():
		add_child(c.duplicate())
	var refs: Dictionary = md[1]
	for r in REFS:
		set(r, _par_indices(refs[r]) if refs.has(r) else null)
	for r in LISTES:
		set(r, (refs[r] as Array).map(func(ix: PackedInt32Array) -> Node: return _par_indices(ix)))
	_portes = (refs["_portes"] as Array).map(func(e: Array) -> Array: return [_par_indices(e[0]), e[1], e[2]])
	var val: Dictionary = md[2]
	for r in VALEURS:
		var x: Variant = val[r]
		set(r, (x as PackedFloat32Array).duplicate() if x is PackedFloat32Array else x)


## Place d'un nœud dans l'arbre du véhicule (rangs des enfants) : les nœuds
## sans nom en reçoivent un autre à chaque copie, les rangs restent.
func _indices(n: Node) -> PackedInt32Array:
	var ix: PackedInt32Array = PackedInt32Array()
	while n != self and n != null:
		ix.insert(0, n.get_index())
		n = n.get_parent()
	return ix


func _par_indices(ix: PackedInt32Array) -> Node:
	var n: Node = self
	for k in ix:
		n = n.get_child(k)
	return n


## Fabrication complète (le premier véhicule de chaque variante), en trois étapes : pince, corps, fin.
## (fusion en trois étapes, et la Zeta du 3S en deux : 24 ms d'un bloc pour sa fabrication, relevé du 08/11/2026)
func _phases_fabrication() -> Array:
	var corps: Array = [_zeta_chariot, _zeta_caisse] if famille == "cabine_3s" else [_fabriquer_corps]
	return [_fabriquer_pince] + _phases_caisse() + corps + [_fabriquer_fin, _fusion_pince, _fusion_suspendu, _fusion_pieces]


## Caches de la caisse calculés d'avance, chacun dans sa propre étape : maillage de la caisse, numéro, nom de la
## station, aigle. Le premier modèle d'une ligne les faisait dans la même tranche que la caisse (26,7 ms d'un bloc
## pour la première cabine de la Daille, relevé du 10/11/2026 ; un texte seul : 5 à 9 ms). Rien n'est posé ici :
## les pièces viennent ensuite des mêmes caches, à l'identique.
func _phases_caisse() -> Array:
	if not famille.begins_with("cabine") or famille == "cabine_tph":
		return []
	var ph: Array = [_maillage_cabine.bind(famille, teinte)]
	var px_no: float = 0.0034 if famille == "cabine_3s" else 0.0018
	ph.append(RemonteeKit.maillage_texte.bind(("%d" if famille == "cabine_3s" else "%02d") % numero, 56, px_no, 2.0))
	if livree != "Val d'Isère" and livree != "Tignes":
		return ph
	var nom: String = "TIGNES" if livree == "Tignes" else "Val d'Isère"
	for e in logo_elements(famille, livree, -1.0):
		if String(e[0]) == "nom":
			ph.append(RemonteeKit.maillage_texte.bind(nom, 64, _px_pour(nom, e[4]), 2.0))
		elif String(e[0]) == "aigle":
			ph.append(_aigle)
	return ph


func _fabriquer_pince() -> void:
	_ressorts.clear()
	_galets_roul.clear()
	_portes.clear()
	_skis_ranges.clear()
	_etat_anim = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	places = DESCRIPTIONS.get(famille, ["", 6, ""])[1]
	cabine = famille.begins_with("cabine")
	if famille.begins_with("perche") or famille == "cabine_3s" or famille == "cabine_tph":
		return
	if constructeur() == "fixe":
		_pince_fixe()
	else:
		_pince_debrayable()


func _fabriquer_corps() -> void:
	if famille.begins_with("perche"):
		_perche()
	elif famille == "cabine_3s" or famille == "cabine_tph":
		_grande_cabine()
	elif cabine:
		_cabine()
	else:
		_siege()


func _fabriquer_fin() -> void:
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
		masse = 2950.0 if famille == "cabine_3s" else (9000.0 if famille == "cabine_tph" else 850.0)
		longueur_pendule = 3.85 if famille == "cabine_3s" else (5.6 if famille == "cabine_tph" else 2.65)
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


## Pièces animées, gardées hors de la fusion des pièces fixes.
func _a_garder() -> Array:
	var garder: Array = []
	for n in [_machoire, _gc, _bulle, _corde, _perche_tige]:
		if n != null:
			garder.append(n)
	for r in _ressorts:
		garder.append(r)
	for g in _galets_roul:
		garder.append(g)
	for p in _portes:
		garder.append(p[0])
	return garder


## Fusion des pièces fixes (un appel de dessin par matériau) ; les pièces
## animées restent à part, chacune fusionnée en elle-même.
func _fusion_pince() -> void:
	if _pince != null:
		MeshMerge.merge(_pince, _a_garder(), "Pince", true)


func _fusion_suspendu() -> void:
	MeshMerge.merge(_susp, _a_garder(), "Vehicule", true)


func _fusion_pieces() -> void:
	for n in _a_garder():
		MeshMerge.merge(n, _skis_ranges, "Piece", true)      # skis rangés : affichés à la demande
	for n in _skis_ranges:
		MeshMerge.merge(n, [], "Skis", true)
	# pièces de détail, invisibles de loin (audit de fluidité, 26/10/2026 : 36 000
	# objets à dessiner au pied des pistes, 7 sur 10 par siège sont ces pièces) ;
	# les portes et la bulle restent : sans elles, la cabine serait trouée
	for n in [_machoire, _gc] + _ressorts + _galets_roul + _skis_ranges:
		if n != null:
			(n as Node).set_meta("detail", true)


# --- pinces ---------------------------------------------------------------------

func _couleur_ressorts() -> String:
	match constructeur():
		"bartholet":
			# pince BMF du Marmottes Express (2008) : un gros ressort rouge à
			# chaque bout (photos de la ligne) ; les K3 Bartholet récentes ont
			# deux ressorts jaunes
			return "rouge_ressort"
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
## Pince débrayable, sur le modèle de la Doppelmayr A-108 (toutes les lignes débrayables, sur demande de l'utilisateur, 03/11/2026), d'après les photos de l'utilisateur et
## son explication (02/11/2026) : corps gris COURT, qui ne descend pas sous le câble ; une pièce
## articulée en bas du corps pince le câble d'un côté et, de l'autre, remonte vers l'arrière où
## DEUX ressorts bleus, derrière le corps et sans le traverser, la poussent vers le haut.
## Repère : câble à l'origine le long de Z, suspente à X+, patin à A108_Y_PATIN (pneus du lanceur).
## Patin décalé vers les ressorts : au-dessus du câble, il passerait sous les galets de
## compression (retour d'utilisateur, 03/11/2026) ; assez haut pour rester au-dessus d'eux.
const A108_X_PATIN: float = 0.17
const A108_Y_PATIN: float = 0.26
## Galets de roulement sur le rail de gare, plus petits et plus bas, sous les ressorts.
const A108_X_GALET: float = 0.22
const A108_Y_GALET: float = 0.05
const A108_R_GALET: float = 0.065
## Articulation et roue de came, en position fermée (repère de la pince).
const A108_ARTICULATION: Vector2 = Vector2(0.10, 0.0)
const A108_ROUE: Vector3 = Vector3(0.2930, 0.3144, 0)    # 0,43 m le long du bras, depuis l'articulation
const A108_R_ROUE: float = 0.07
const A108_OUVERTURE: float = 0.45                        # rad
## Articulation du bras de suspente : à la hauteur du mors, du côté opposé. Au-dessus du rail de gare, qui
## passe entre elle et le corps : le siège et le rail ne bougent pas, seul le centre du balancement descend.
const A108_PIVOT: Vector3 = Vector3(0.30, 0.03, 0)
## Roulement au bout de la tige, derrière l'articulation : axe le long de la tige, il entre dans le guide
## évasé de l'entrée de gare, qui ramène le balancement latéral à zéro avant le débrayage.
const A108_X_ROULEMENT: float = 0.79
const A108_R_ROULEMENT: float = 0.08


func _pince_debrayable() -> void:
	var p: Node3D = Node3D.new()
	p.name = "Pince"
	add_child(p)
	var corps_m: String = "acier_noir" if constructeur() == "poma" else "alu_pince"
	var rc: String = "bleu_ressort" if pince_a108 else _couleur_ressorts()
	if rc == "rouge_ressort" and constructeur() != "bartholet":
		rc = "ressort_gris"
	var L: float = 0.30
	var travers: Basis = Basis(Vector3.FORWARD, PI * 0.5)
	# corps : au-dessus et derrière le câble, rien sous sa génératrice basse
	# au droit du câble, seulement les mors et une semelle mince : le gros du corps est à côté
	# (x > 0,09), hors de la largeur des galets de compression, qui appuient sur le câble
	RemonteeKit.boite_en(p, Vector3(0.08, 0.075, L), Vector3(0.13, 0.055, 0), corps_m)
	RemonteeKit.boite_en(p, Vector3(0.135, 0.016, 0.23), Vector3(0.0225, 0.034, 0), corps_m)
	RemonteeKit.boite_en(p, Vector3(0.02, 0.054, 0.23), Vector3(-0.037, 0.002, 0), corps_m)    # mors fixe
	for sz in [-1.0, 1.0]:
		RemonteeKit.demi_cone(p, Vector3(0, 0, sz * L * 0.5), Vector3(0, 0, sz * (L * 0.5 + 0.34)), 0.055, 0.0245, "noir_mat", 12)
	# pièce articulée en bas du corps : côté câble le mors mobile, côté arrière le bras
	# qui remonte entre les deux ressorts jusqu'au galet de came
	var h: Vector3 = Vector3(A108_ARTICULATION.x, A108_ARTICULATION.y, 0)
	RemonteeKit.cylindre(p, 0.018, 0.018, 0.26, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), h), "acier_noir", 10)
	_machoire = Node3D.new()
	_machoire.name = "MachoireMobile"
	_machoire.position = h
	p.add_child(_machoire)
	RemonteeKit.boite_en(_machoire, Vector3(0.02, 0.046, 0.23), Vector3(-0.063, 0.0, 0), corps_m)
	RemonteeKit.poutre(_machoire, Vector3(-0.06, 0.0, 0), Vector3(0.0, 0.0, 0), 0.04, 0.03, corps_m, Vector3.BACK)
	var dir: Vector3 = Vector3(0.68, 0.73, 0).normalized()
	var haut_bras: Vector3 = dir * 0.40
	RemonteeKit.poutre(_machoire, Vector3.ZERO, haut_bras, 0.04, 0.035, "galva_pylone", Vector3.BACK)
	# coupelle haute et galet de came Ø 160, sur la pièce articulée
	RemonteeKit.poutre(_machoire, haut_bras - Vector3(0, 0, 0.17), haut_bras + Vector3(0, 0, 0.17), 0.06, 0.02, corps_m, Vector3.UP)
	# au sommet, la roue cylindrique sur laquelle appuie le rail d'ouverture du lanceur ;
	# elle roule le long du câble (retour d'utilisateur, 02/11/2026)
	RemonteeKit.cylindre(_machoire, A108_R_ROUE, A108_R_ROUE, 0.11, Transform3D(travers, A108_ROUE), "polyurethane", 18)
	# deux ressorts bleus côte à côte, assis sur le dos du corps, parallèles au bras
	var pied: Vector3 = Vector3(0.175, 0.085, 0)
	RemonteeKit.poutre(p, pied - Vector3(0, 0, 0.17), pied + Vector3(0, 0, 0.17), 0.09, 0.02, corps_m, Vector3.UP)
	for sz in [-1.0, 1.0]:
		var r: Node3D = Node3D.new()
		r.position = pied + Vector3(0, 0, sz * 0.095)
		r.basis = Basis(dir.cross(Vector3.BACK).normalized(), dir, Vector3.BACK)
		p.add_child(r)
		RemonteeKit.ressort(r, Vector3.ZERO, Vector3.UP, 0.265, 0.062, 0.012, 9, rc)
		_ressorts.append(r)
	# chape du bras de suspente : du bas du corps à l'articulation, au niveau du mors et au-dessus du rail
	RemonteeKit.boite_en(p, Vector3(0.20, 0.05, 0.13), Vector3(0.20, A108_PIVOT.y, 0), "acier_noir")
	RemonteeKit.cylindre(p, 0.028, 0.028, 0.17, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), A108_PIVOT), "acier", 10)
	# galets de roulement sur le rail de gare, en tête et en queue
	for sz in [-1.0, 1.0]:
		RemonteeKit.cylindre(p, 0.016, 0.016, 0.12, Transform3D(travers, Vector3(A108_X_GALET - 0.05, A108_Y_GALET, sz * 0.19)), corps_m, 8)
		RemonteeKit.cylindre(p, A108_R_GALET, A108_R_GALET, 0.03, Transform3D(travers, Vector3(A108_X_GALET, A108_Y_GALET, sz * 0.19)), "polyurethane", 16)
	# patin noir au-dessus de la pince, le long du câble : les pneus du lanceur roulent dessus
	# et font avancer le siège (et non au-dessus des ressorts ; retour d'utilisateur, 02/11/2026)
	RemonteeKit.boite_en(p, Vector3(0.07, A108_Y_PATIN - 0.09, 0.05), Vector3(A108_X_PATIN, (A108_Y_PATIN + 0.09) * 0.5, 0.0), corps_m)
	RemonteeKit.boite_en(p, Vector3(0.10, 0.025, 0.72), Vector3(A108_X_PATIN, A108_Y_PATIN - 0.0125, 0), "noir_mat")
	for sz in [-1.0, 1.0]:
		RemonteeKit.poutre(p, Vector3(A108_X_PATIN, A108_Y_PATIN - 0.03, sz * 0.36), Vector3(A108_X_PATIN, 0.06, sz * 0.52), 0.07, 0.015, "noir_mat", Vector3.UP)


## Sur la partie suspendue : épaule du bras, tige galvanisée vers l'extérieur, peigne noir et roulement.
## Fusionnée avec le reste du véhicule : aucun objet à dessiner de plus.
func _tige_guidage() -> void:
	var t: Node3D = Node3D.new()
	t.name = "Tige"
	add_child(t)
	var y: float = A108_PIVOT.y
	var travers: Basis = Basis(Vector3.FORWARD, PI * 0.5)
	RemonteeKit.boite_en(t, Vector3(0.19, 0.17, 0.13), Vector3(0.45, y - 0.045, 0), "noir_mat")
	RemonteeKit.cylindre(t, 0.042, 0.03, 0.22, Transform3D(travers, Vector3(0.645, y, 0)), "galva_pylone", 10)
	RemonteeKit.cylindre(t, 0.056, 0.056, 0.025, Transform3D(travers, Vector3(0.555, y, 0)), "galva_pylone", 10)
	# peigne de contact, juste derrière le roulement : semelle et dents pointées vers le bas
	RemonteeKit.boite_en(t, Vector3(0.03, 0.05, 0.13), Vector3(0.735, y - 0.05, 0), "noir_mat")
	for k in range(5):
		RemonteeKit.boite_en(t, Vector3(0.016, 0.05, 0.012), Vector3(0.735, y - 0.10, -0.052 + k * 0.026), "noir_mat")
	RemonteeKit.cylindre(t, A108_R_ROULEMENT, A108_R_ROULEMENT, 0.06, Transform3D(travers, Vector3(A108_X_ROULEMENT, y, 0)), "polyurethane", 16)


## Numéro lisible À L'ENDROIT : une étiquette d'un seul côté (vue de dos,
## elle s'effaçait en miroir — retour d'utilisateur, 23/10/2026), contre-
## inversée sur les véhicules en miroir ; `rot` oriente sa face (autour de Y).
func _numero(parent: Node3D, texte: String, pos: Vector3, rot: float, taille: int, px: float, coul: Color, incl: float = 0.0) -> void:
	# maillage de texte (TextMesh), partagé par texte et taille, fusionné avec
	# le véhicule : des centaines de Label3D qui bougent coûtaient ~25 ms par
	# image au pied de Solaise
	# (figé en ArrayMesh sur le fil de construction : un TextMesh gardé renvoyait sa mise en forme au fil
	# principal, un appel différé par numéro, relevé du 07/11/2026)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = RemonteeKit.maillage_texte(texte, taille, px, 2.0)
	mi.material_override = _mat_texte(coul)
	mi.position = pos
	mi.rotation = Vector3(incl, rot, 0)
	if miroir:
		# le miroir du véhicule (x → −x) garde la face au bon endroit mais
		# inverse le texte : une seconde symétrie en x le remet à l'endroit
		mi.scale = Vector3(-1, 1, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Aigle héraldique (silhouette générique, ailes déployées) et nom de la
## station sur la caisse : face opposée aux portes et faces avant/arrière,
## au milieu du panneau sous les vitres.
static var _tex_aigle: ImageTexture = null


static func _aigle() -> ImageTexture:
	if _tex_aigle != null:
		return _tex_aigle
	var n: int = 128
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# polygones en coordonnées 0..1 (y vers le bas), symétriques
	var formes: Array = []
	var aile: PackedVector2Array = PackedVector2Array([Vector2(0.50, 0.30), Vector2(0.38, 0.22), Vector2(0.20, 0.12),
		Vector2(0.04, 0.10), Vector2(0.10, 0.20), Vector2(0.03, 0.24), Vector2(0.11, 0.32), Vector2(0.05, 0.38),
		Vector2(0.15, 0.44), Vector2(0.10, 0.50), Vector2(0.22, 0.54), Vector2(0.20, 0.60), Vector2(0.34, 0.60), Vector2(0.50, 0.55)])
	formes.append(aile)
	var miroir_aile: PackedVector2Array = PackedVector2Array()
	for q in aile:
		miroir_aile.append(Vector2(1.0 - q.x, q.y))
	formes.append(miroir_aile)
	# corps, tête et bec, queue en éventail, serres
	formes.append(PackedVector2Array([Vector2(0.44, 0.24), Vector2(0.56, 0.24), Vector2(0.58, 0.56), Vector2(0.50, 0.64), Vector2(0.42, 0.56)]))
	formes.append(PackedVector2Array([Vector2(0.45, 0.12), Vector2(0.53, 0.10), Vector2(0.60, 0.14), Vector2(0.56, 0.17), Vector2(0.55, 0.24), Vector2(0.45, 0.24)]))
	formes.append(PackedVector2Array([Vector2(0.44, 0.60), Vector2(0.56, 0.60), Vector2(0.64, 0.84), Vector2(0.56, 0.80), Vector2(0.50, 0.88), Vector2(0.44, 0.80), Vector2(0.36, 0.84)]))
	for sx in [-1.0, 1.0]:
		var x0: float = 0.5 + sx * 0.07
		formes.append(PackedVector2Array([Vector2(x0, 0.58), Vector2(x0 + sx * 0.10, 0.70), Vector2(x0 + sx * 0.14, 0.69), Vector2(x0 + sx * 0.05, 0.57)]))
	for j in range(n):
		for i in range(n):
			var q2: Vector2 = Vector2((i + 0.5) / n, (j + 0.5) / n)
			for f in formes:
				if Geometry2D.is_point_in_polygon(q2, f):
					img.set_pixel(i, j, Color.WHITE)
					break
	img.generate_mipmaps()
	_tex_aigle = ImageTexture.create_from_image(img)
	return _tex_aigle


## Panneau sous les vitres, au milieu du premier tronçon de caisse (repère de
## la caisse) : [demi-largeur x, demi-longueur z, y, pente x, pente z, rayon
## d'angle, hauteur du tronçon]. Les pentes font épouser la coque au logo.
static func _dims_panneau(fam: String, _H: float) -> Array:
	var profil: Array = _profil_cabine(fam)
	for i in range(profil.size() - 1):
		var r0: Array = profil[i]
		var r1: Array = profil[i + 1]
		if String(r0[4]) != "caisse":
			continue
		var y0: float = r0[0]
		var y1: float = r1[0]
		var dy: float = maxf(y0 - y1, 1e-4)
		return [(float(r0[1]) + float(r1[1])) * 0.5, (float(r0[2]) + float(r1[2])) * 0.5, (y0 + y1) * 0.5,
			(float(r0[1]) - float(r1[1])) / dy, (float(r0[2]) - float(r1[2])) / dy,
			(float(r0[3]) + float(r1[3])) * 0.5, dy]
	return [1.0, 1.0, -_CAB_H * 0.7, 0.0, 0.0, 0.3, 0.3]


## Largeur de pixel pour qu'un texte occupe `largeur` m (TextMesh de taille 64).
static var _px_textes: Dictionary = {}


static func _px_pour(texte: String, largeur: float) -> float:
	if not _px_textes.has(texte):
		var tm: TextMesh = TextMesh.new()
		tm.text = texte
		tm.font_size = 64
		tm.pixel_size = 0.01
		tm.depth = 0.0
		var l: float = tm.get_aabb().size.x
		_px_textes[texte] = l / 0.01 if l > 0.001 else 40.0 * texte.length()
	return largeur / float(_px_textes[texte])


## Emplacement de chaque élément du logo sur la coque : [genre, point, rotation
## y, inclinaison, largeur, hauteur]. Genres : "aigle", "nom", "plaque".
## La face sans portes est en x = fx ; le reste suit la coque.
static func logo_elements(fam: String, livree_: String, fx: float) -> Array:
	var dp: Array = _dims_panneau(fam, _h_cab(fam))
	var a: float = dp[0]
	var b: float = dp[1]
	var y: float = dp[2]
	var h: float = dp[6]
	var inc_x: float = atan(float(dp[3]))
	var inc_z: float = atan(float(dp[4]))
	var utile_x: float = 2.0 * maxf(b - float(dp[5]), 0.2) * 0.96     # partie droite de la face sans portes
	var utile_z: float = 2.0 * maxf(a - float(dp[5]), 0.2) * 0.96     # partie droite des bouts
	var rot_x: float = fx * PI * 0.5
	var el: Array = []
	if livree_ == "Tignes":
		var lp: float = minf(minf(utile_x, utile_z), 0.90)
		var hp: float = minf(h * 0.85, 0.22)
		var lt: float = minf(lp * 0.86, hp * 4.3)
		el.append(["plaque", Vector3(fx * (a + 0.004), y, 0), rot_x, inc_x, lp, hp])
		el.append(["nom", Vector3(fx * (a + 0.007), y, 0), rot_x, inc_x, lt, hp * 0.8])
		for sz in [1.0, -1.0]:
			var rot: float = 0.0 if sz > 0.0 else PI
			el.append(["plaque", Vector3(0, y, sz * (b + 0.004)), rot, inc_z, lp, hp])
			el.append(["nom", Vector3(0, y, sz * (b + 0.007)), rot, inc_z, lt, hp * 0.8])
		return el
	if livree_ == "Val d'Isère":
		var t: float = clampf(minf(utile_x * 0.30, h * 1.45), 0.16, 0.55)     # côté de l'aigle
		var ln: float = minf(utile_x - t - 0.03, t * 2.6)
		var w: float = t + 0.03 + ln
		el.append(["aigle", Vector3(fx * (a + 0.005), y, -fx * (w * 0.5 - t * 0.5)), rot_x, inc_x, t, t])
		el.append(["nom", Vector3(fx * (a + 0.006), y, fx * (w * 0.5 - ln * 0.5)), rot_x, inc_x, ln, ln * 0.2])
		for sz in [1.0, -1.0]:
			var rz: float = 0.0 if sz > 0.0 else PI
			if fam == "cabine_3s":
				# aigle et nom sur les bouts aussi (photo à quai)
				el.append(["aigle", Vector3(-sz * (w * 0.5 - t * 0.5), y, sz * (b + 0.005)), rz, inc_z, t, t])
				el.append(["nom", Vector3(sz * (w * 0.5 - ln * 0.5), y, sz * (b + 0.006)), rz, inc_z, ln, ln * 0.2])
			else:
				el.append(["nom", Vector3(0, y, sz * (b + 0.006)), rz, inc_z, minf(utile_z * 0.6, ln), ln * 0.2])
	return el


func _logo_station(cab: Node3D, face_portes: float) -> void:
	if livree != "Val d'Isère" and livree != "Tignes":
		return
	var nom: String = "TIGNES" if livree == "Tignes" else "Val d'Isère"
	# encre : rouge à Tignes ; à Val d'Isère, claire sur les caisses noires (photos de Solaise et de la Daille)
	var clair: bool = teinte == "noire" or famille == "cabine_diamond"
	var encre: Color = Color(0.82, 0.08, 0.07) if livree == "Tignes" else (Color(0.93, 0.93, 0.93) if clair else Color(0.05, 0.05, 0.06))
	for e in logo_elements(famille, livree, -face_portes):
		if String(e[0]) == "nom":
			_numero(cab, nom, e[1], e[2], 64, _px_pour(nom, e[4]), encre, e[3])
			continue
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.albedo_color = encre if String(e[0]) == "aigle" else Color(0.05, 0.05, 0.06)
		if String(e[0]) == "aigle":
			m.albedo_texture = _aigle()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = _quad_logo(Vector2(e[4], e[5]))
		mi.material_override = m
		mi.position = e[1]
		mi.rotation = Vector3(e[3], e[2], 0)
		if miroir:
			mi.scale = Vector3(-1, 1, 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cab.add_child(mi)


static var _quads: Dictionary = {}


## QuadMesh partagé par taille (une mise à jour différée par taille, plus une par élément de logo).
static func _quad_logo(t: Vector2) -> QuadMesh:
	var k: String = "%.4f|%.4f" % [t.x, t.y]
	RemonteeKit.verrou.lock()
	var q: QuadMesh = _quads.get(k)
	if q == null:
		q = QuadMesh.new()
		q.size = t
		_quads[k] = q
	RemonteeKit.verrou.unlock()
	return q
static var _mats_texte: Dictionary = {}


static func _mat_texte(c: Color) -> StandardMaterial3D:
	var k: String = c.to_html()
	if not _mats_texte.has(k):
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats_texte[k] = m
	return _mats_texte[k]


func _pince_fixe() -> void:
	var p: Node3D = Node3D.new()
	p.name = "Pince"
	add_child(p)
	# monopince fixe : un corps serré par boulons, pas de galets de roulement
	RemonteeKit.boite_en(p, Vector3(0.16, 0.14, 0.32), Vector3(0.07, 0.05, 0), "galva")
	# gaines comme sur les débrayables : demi-cônes ouverts par-dessous,
	# grand diamètre contre la pince (retour d'utilisateur, 23/10/2026)
	for sz in [-1.0, 1.0]:
		RemonteeKit.demi_cone(p, Vector3(0, 0, sz * 0.16), Vector3(0, 0, sz * (0.16 + 0.26)), 0.05, 0.0245, "noir_mat", 12)
	for sz in [-0.10, 0.0, 0.10]:
		RemonteeKit.cylindre(p, 0.018, 0.018, 0.20, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.07, -0.01, sz)), "acier", 6)
	_machoire = Node3D.new()
	p.add_child(_machoire)


## 0 : serrée sur le câble ; 1 : ouverte (en gare, levier poussé par la came).
func ouvrir_pince(t: float) -> void:
	# (rien à faire si rien ne bouge : des centaines de véhicules par image)
	if t == _etat_anim[0]:
		return
	_etat_anim[0] = t
	if _machoire != null:
		_machoire.rotation.z = -0.45 * clampf(t, 0.0, 1.0)
	for r in _ressorts:
		(r as Node3D).scale = Vector3(1, 1.0 - 0.22 * clampf(t, 0.0, 1.0), 1)


# --- suspente et siège -------------------------------------------------------------

## Hauteur du câble au-dessus du quai d'embarquement : l'assise arrive à
## 0,48 m du sol (siège), le plancher au niveau du quai (cabine).
static func hauteur_cable_gare(fam: String) -> float:
	if fam == "cabine_tph":
		return H_SUSP_TPH + 0.08 + 2.70 - 0.12
	if fam == "cabine_3s":
		# chariot → plancher de la Zeta (suspente, caisse, plancher à 0,20 m)
		# (+ quai de 25 cm : les cabines passent dans une tranchée, le quai est
		# au niveau de leur plancher — retour d'utilisateur, 25/10/2026)
		return H_SUSP_3S + 0.08 + _h_cab("cabine_3s") - 0.22 + Machinerie3S.H_QUAI
	if fam.begins_with("cabine"):
		return H_SUSP_CABINE + 0.10 + 2.25 - 0.07 + 0.02
	if fam.begins_with("perche"):
		return 4.2          # rondelle à ~2,4 m du sol, perche rentrée
	var pl: int = DESCRIPTIONS.get(fam, ["", 6, ""])[1]
	var hs: float = 2.85 if pl >= 8 else (2.35 if pl >= 6 else 2.05)
	return hs + 0.12 + 0.98 - 0.045 + 0.48


## Balancement de la partie suspendue, en repère monde (identité si elle n'existe pas).
func balancement_monde() -> Basis:
	if _susp == null:
		return Basis.IDENTITY
	var b: Basis = global_transform.basis.orthonormalized()
	return b * _susp.basis.orthonormalized() * b.inverse()


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
	# accélération lissée — davantage en gare : la boucle y est un polygone,
	# chaque sommet de l'arc de la poulie donnait une secousse au balancier
	_a_f = _a_f.lerp(a, minf(1.0, dt * (3.0 if en_gare else 15.0)))
	var la: Vector3 = transform.basis.inverse() * _a_f
	var g2: float = 9.81 + _a_f.y
	var L: float = longueur_pendule
	var w0: float = sqrt(9.81 / L)
	var zeta: float = 0.7 if en_gare else clampf(90.0 / masse, 0.03, 0.30)
	var n: int = maxi(1, int(ceil(dt / 0.008)))
	var h: float = dt / n
	for k in range(n):
		var ddphi: float = -(g2 / L) * sin(phi) - (-la.z / L) * cos(phi) - 2.0 * zeta * w0 * _dphi
		var ddpsi: float = -(g2 / L) * sin(psi - psi0) - (la.x / L) * cos(psi) - 2.0 * zeta * w0 * _dpsi
		_dphi += ddphi * h
		_dpsi += ddpsi * h
		phi += _dphi * h
		psi += _dpsi * h
	phi = clampf(phi, -0.6, 0.6)
	psi = clampf(psi, -0.6, 0.6)
	# le roulement touche le guide : il garde sa place, et sa vitesse tombe
	if absf(psi) > limite_psi:
		psi = clampf(psi, -limite_psi, limite_psi)
		_dpsi = 0.0
	_susp.rotation = Vector3(phi, 0.0, psi)


## Inclinaison d'équilibre pour `n` passagers de 80 kg dont la somme des abscisses vaut `somme_x` :
## le centre de gravité revient sous l'articulation, atan(m·x / ((M + m)·L)), du côté opposé à la charge.
func psi_charge(somme_x: float, n: int = 1) -> float:
	return -atan(80.0 * somme_x / ((masse + 80.0 * n) * longueur_pendule))


## Le joueur à la place k (pour un siège, sa moitié de banquette ; dans une cabine, là où il se tient).
func psi_place(k: int, avant: bool = false) -> float:
	return psi_charge(place_assise(k, avant).x)


## Passagers tirés au sort, de façon reproductible (mêmes chances que la charge moyenne de la ligne).
func tirer_charge(graine: int) -> void:
	if cabine or famille.begins_with("perche") or places <= 1:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = graine
	var somme: float = 0.0
	var n: int = 0
	for k in range(places):
		if rng.randf() < 0.7:
			somme += place_assise(k).x
			n += 1
	psi0_tire = psi_charge(somme, n) if n > 0 else 0.0


## Où poser le skieur assis (repère du véhicule) : origine aux pieds, 0,42 m
## devant le bassin (convention de SkieurJoueur.asseoir), tourné vers −Z.
## Siège : place `i` ; cabine : banquette arrière, face à l'amont.
## `avant` : banquette avant d'une cabine, face à l'arrière (+Z).
func place_assise(i: int = -1, avant: bool = false) -> Vector3:
	if famille == "cabine_tph":
		# debout, au milieu de la cabine (on tient la barre)
		var yp2: float = -H_SUSP_TPH - 0.08 - 2.70 + 0.12
		var zi: float = (clampf(float(i if i >= 0 else 2), 0.0, 4.0) - 2.0) * 1.0
		return Vector3(0.6, yp2, zi)
	if famille == "cabine_3s":
		# banquettes de 6 places face à face (z = ±0,95), plancher 0,20 m
		# au-dessus du bas de la caisse
		var yp: float = -H_SUSP_3S - 0.08 - _h_cab("cabine_3s") + 0.22
		var xi: float = (clampf(float(i if i >= 0 else 2), 0.0, 5.0) - 2.5) * 0.45
		var zs: float = 1.06 - 0.42
		return Vector3(xi, yp + 0.44 + 0.045 - 0.45, -zs if avant else zs)
	if cabine:
		var hs: float = H_SUSP_CABINE
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
	if famille.begins_with("perche"):
		return f
	if famille == "cabine_tph":
		var yt: float = -H_SUSP_TPH - 0.08 - 2.70 + 0.12
		f.append([Vector3(3.0, 0.15, 5.6), Vector3(0, yt - 0.075, 0), false])
		f.append([Vector3(3.0, 0.10, 5.6), Vector3(0, -H_SUSP_TPH - 0.12, 0), false])
		f.append([Vector3(3.0, 2.5, 0.06), Vector3(0, yt + 1.25, -2.79), false])
		f.append([Vector3(3.0, 2.5, 0.06), Vector3(0, yt + 1.25, 2.79), false])
		f.append([Vector3(0.06, 2.5, 5.6), Vector3(-cote_ext * 1.51, yt + 1.25, 0), false])
		f.append([Vector3(0.06, 2.5, 5.6), Vector3(cote_ext * 1.51, yt + 1.25, 0), true])
		return f
	if famille == "cabine_3s":
		var yb: float = -H_SUSP_3S - 0.08 - _h_cab("cabine_3s") + 0.22
		f.append([Vector3(2.9, 0.15, 2.8), Vector3(0, yb - 0.075, 0), false])           # plancher
		f.append([Vector3(2.8, 0.10, 2.7), Vector3(0, -H_SUSP_3S - 0.10, 0), false])    # toit
		f.append([Vector3(2.9, 2.45, 0.06), Vector3(0, yb + 1.22, -1.44), false])
		f.append([Vector3(2.9, 2.45, 0.06), Vector3(0, yb + 1.22, 1.44), false])
		f.append([Vector3(0.06, 2.45, 2.8), Vector3(-cote_ext * 1.50, yb + 1.22, 0), false])
		f.append([Vector3(0.06, 2.45, 2.8), Vector3(cote_ext * 1.50, yb + 1.22, 0), true])     # côté portes
		f.append([Vector3(2.7, 0.42, 0.40), Vector3(0, yb + 0.21, 1.09), false])
		f.append([Vector3(2.7, 0.42, 0.40), Vector3(0, yb + 0.21, -1.09), false])
		return f
	if cabine:
		var hs: float = H_SUSP_CABINE
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
	# pince → assise mesuré en vidéo : TSD4 3,1 m, TSD6 3,2 m, TSD8 3,9 m (±0,4)
	return 2.85 if places >= 8 else (2.35 if places >= 6 else 2.05)


func _siege() -> void:
	# un seul siège pour toutes les lignes : celui mis au point sur le
	# Marmottes Express (« le but de faire les tests sur Marmottes c'est
	# d'utiliser les mêmes sièges partout » — retour d'utilisateur, 24/10/2026) ;
	# seules les couleurs, le nombre de places et la bulle changent
	if famille.begins_with("siege"):
		_siege_bmf()
		if famille.ends_with("_bulle"):
			_bulle_siege(get_node("Siege"), _largeur_siege())
		return
	var fixe: bool = constructeur() == "fixe"
	var x0: float = 0.10 if not fixe else 0.07     # attache de la suspente sous la pince
	var hs: float = _haut_suspente()
	var sus_m: String = "acier_noir" if constructeur() in ["poma", "leitner"] else "galva"
	# suspente : sort de la pince vers l'extérieur, descend, puis revient au
	# droit du câble au-dessus du dossier (le véhicule pend sous le câble)
	var pts: PackedVector3Array = PackedVector3Array()
	# attache sous le bras de la pince (débrayable) ou sous la monopince (fixe)
	var x_att: float = A108_PIVOT.x if not fixe else x0 + 0.10
	var y_att: float = A108_PIVOT.y if not fixe else 0.02
	pivot = Vector3(x_att, y_att, 0)
	if not fixe:
		_tige_guidage()
	pts.append(Vector3(x_att, y_att, 0))
	pts.append(Vector3(0.46, y_att - 0.04, 0))
	pts.append(Vector3(0.52, -0.25, 0))
	pts.append(Vector3(0.50, -hs + 0.70, 0))
	for p in RemonteeKit.arc(Vector3(0.10, -hs + 0.70, 0), Vector3.RIGHT, Vector3.DOWN, 0.40, 0.0, PI * 0.5, 8):
		pts.append(p)
	RemonteeKit.tube(self, pts, 0.05 if not fixe else 0.045, sus_m, 12)
	var siege: Node3D = Node3D.new()
	siege.name = "Siege"
	siege.position = Vector3(0.0, -hs - 0.12, 0)
	add_child(siege)
	var W: float = _largeur_siege()
	_ossature_moderne(siege, W, sus_m)
	_garde_corps(siege, W, sus_m)
	if famille.ends_with("_bulle"):
		_bulle_siege(siege, W)


## Siège BMF 6 places du Marmottes Express, d'après les photos de la ligne
## (reportage remontees-mecaniques.net, 2011) : la suspente se cintre et
## tombe au milieu d'une POUTRE DE TÊTE en treillis qui court sur toute la
## largeur (numéro du siège dessus) ; à chaque bout, un gros cadre tubulaire
## descend derrière le dossier et se cintre en grand rayon sous l'assise ;
## dossier bas et peu incliné (« un angle du dossier et de l'assise moins
## incliné », la marque BMF) ; six coussins noirs sur un grand carénage
## aluminium sous l'assise. Mêmes cotes d'assise que les autres sièges.
func _siege_bmf() -> void:
	var hs: float = _haut_suspente()
	var m_alu: String = "alu_pince"
	var fixe: bool = constructeur() == "fixe"
	var x_att: float = A108_PIVOT.x if not fixe else 0.17      # bras de la pince, ou monopince
	var y_att: float = A108_PIVOT.y if not fixe else 0.02
	if not fixe:
		_tige_guidage()
	pivot = Vector3(x_att, y_att, 0)
	# siège à bulle (Lanches) : arceau à ~1,55 m au-dessus de l'assise (vidéos
	# de la ligne), la bulle ouverte se loge dessous → poutre remontée
	var dp: float = 0.55 if famille.ends_with("_bulle") else 0.0
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(x_att, y_att, 0))
	pts.append(Vector3(0.44, y_att - 0.06, 0))
	pts.append(Vector3(0.50, -0.30, 0))
	pts.append(Vector3(0.50, -hs + 0.75 + dp, 0))
	# (le bas revient vers l'arrière, jusque dans l'attache de la poutre de tête, posée à z = 0,18 derrière le
	# câble : tombé tout droit, le bras s'arrêtait 8 cm devant elle, sans la toucher)
	var arc_bas: PackedVector3Array = RemonteeKit.arc(Vector3(0.12, -hs + 0.75 + dp, 0), Vector3.RIGHT, Vector3.DOWN, 0.38, 0.0, PI * 0.5, 8)
	var z_att: float = 0.18
	for i in range(arc_bas.size()):
		var q: Vector3 = arc_bas[i]
		q.z = z_att * 0.6 * float(i) / (arc_bas.size() - 1)
		pts.append(q)
	pts.append(Vector3(0.0, -hs + 0.15 + dp, z_att))
	RemonteeKit.tube(self, pts, 0.05, m_alu, 12)
	var siege: Node3D = Node3D.new()
	siege.name = "Siege"
	siege.position = Vector3(0.0, -hs - 0.12, 0)
	add_child(siege)
	var W: float = _largeur_siege()
	var xb: float = W * 0.5 + 0.03
	# poutre de tête (gros plans de la ligne) : UNE tôle verticale, pleine au
	# milieu (attache de la suspente, plaque du numéro) et aux deux bouts,
	# ajourée de triangles entre les deux ; posée sur un longeron inférieur
	# en caisson, sous lequel sortent les cadres latéraux
	var yb0: float = 0.05 + dp
	var yb1: float = 0.21 + dp
	var zb: float = 0.18
	var ep: float = 0.022
	var hp: float = yb1 - yb0
	var plein_c: float = 0.36                   # demi-largeur pleine au milieu
	var plein_b: float = 0.30                   # longueur pleine à chaque bout
	# sièges Études de Transports (photos de Bollin-Fresse) : pas de treillis, une tôle
	# pleine sur toute la largeur, percée de quelques trous ronds de part et d'autre du numéro
	var et: bool = famille.begins_with("siege_doppelmayr_e98")
	# 8 places de Tommeuses (photos de la ligne) : fronton triangulaire ajouré sur la
	# poutre, dossier d'une pièce bleu marine percé de 7 lumières, assise bleue
	var d8: bool = famille == "siege_doppelmayr_e98_8"
	if d8:
		_fronton_d8(siege, xb, yb0, yb1, zb, ep, m_alu)
	elif et:
		RemonteeKit.boite_en(siege, Vector3(2.0 * xb, hp, ep), Vector3(0, (yb0 + yb1) * 0.5, zb), m_alu)
	else:
		RemonteeKit.boite_en(siege, Vector3(2.0 * plein_c, hp, ep), Vector3(0, (yb0 + yb1) * 0.5, zb), m_alu)
	for sx in [-1.0, 1.0]:
		if d8:
			pass
		elif et:
			for u in [0.38, 0.72]:
				RemonteeKit.cylindre(siege, 0.042, 0.042, ep + 0.004, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * xb * u, (yb0 + yb1) * 0.5, zb)), "noir_mat", 10)
		else:
			RemonteeKit.boite_en(siege, Vector3(plein_b, hp, ep), Vector3(sx * (xb - plein_b * 0.5), (yb0 + yb1) * 0.5, zb), m_alu)
			# zone ajourée : membrures haute et basse, diagonales en zigzag
			var xa: float = plein_c
			var xz: float = xb - plein_b
			for y in [yb1 - 0.02, yb0 + 0.02]:
				RemonteeKit.boite_en(siege, Vector3(xz - xa, 0.04, ep), Vector3(sx * (xa + xz) * 0.5, y, zb), m_alu)
			var nd: int = 5
			for k in range(nd):
				var x0: float = lerpf(xa, xz, float(k) / nd)
				var x1: float = lerpf(xa, xz, float(k + 1) / nd)
				var haut: bool = k % 2 == 0
				RemonteeKit.poutre(siege, Vector3(sx * x0, yb0 + 0.02 if haut else yb1 - 0.02, zb), Vector3(sx * x1, yb1 - 0.02 if haut else yb0 + 0.02, zb),
					0.045, ep, m_alu, Vector3.BACK)
		# boulons des chapes de bout
		for dy in [-0.04, 0.04]:
			RemonteeKit.cylindre(siege, 0.012, 0.012, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * (xb - 0.10), (yb0 + yb1) * 0.5 + dy, zb)), "acier", 6)
	# longeron inférieur en caisson, sur toute la largeur
	RemonteeKit.boite_en(siege, Vector3(2.0 * xb - 0.10, 0.06, 0.12), Vector3(0, yb0 - 0.03, zb + 0.01), m_alu)
	# plaque du numéro au milieu de la tôle, et attache de la suspente
	RemonteeKit.boite_en(siege, Vector3(0.20, 0.10, 0.01), Vector3(0.0, (yb0 + yb1) * 0.5, zb - ep * 0.5 - 0.006), "blanc_plaque")
	# (81 sièges sur la ligne) ; plaque des deux côtés de la tôle
	var no: String = str(numero)
	RemonteeKit.boite_en(siege, Vector3(0.20, 0.10, 0.01), Vector3(0.0, (yb0 + yb1) * 0.5, zb + ep * 0.5 + 0.006), "blanc_plaque")
	_numero(siege, no, Vector3(0.0, (yb0 + yb1) * 0.5, zb - ep * 0.5 - 0.013), PI, 64, 0.0018, Color(0.05, 0.05, 0.06))
	_numero(siege, no, Vector3(0.0, (yb0 + yb1) * 0.5, zb + ep * 0.5 + 0.013), 0.0, 64, 0.0018, Color(0.05, 0.05, 0.06))
	RemonteeKit.boite_en(siege, Vector3(0.16, 0.08, 0.10), Vector3(0.0, yb1 + 0.04, zb), m_alu)
	# cadres latéraux en tube rond : ils sortent horizontalement sous le bout
	# de la poutre, plongent en grand rayon derrière le dossier, puis se
	# cintrent sous l'assise
	for sx in [-1.0, 1.0]:
		var x: float = sx * xb
		var yc: float = yb0 - 0.09
		var cad: PackedVector3Array = PackedVector3Array([Vector3(sx * (xb - 0.42), yc, zb)])
		for p in RemonteeKit.arc(Vector3(sx * (xb - 0.16), yc - 0.16, zb), Vector3.UP, Vector3.RIGHT * sx, 0.16, 0.0, PI * 0.5, 6):
			cad.append(p)
		cad.append(Vector3(x, -0.20, 0.25))
		cad.append(Vector3(x, -0.66, 0.29))
		for p in RemonteeKit.arc(Vector3(x, -0.66, 0.02), Vector3.BACK, Vector3.DOWN, 0.27, 0.0, PI * 0.5, 8):
			cad.append(p)
		cad.append(Vector3(x, -0.93, -0.32))
		RemonteeKit.tube(siege, cad, 0.042, m_alu, 10)
		# collier qui serre le cadre sous le longeron
		RemonteeKit.boite_en(siege, Vector3(0.10, 0.07, 0.12), Vector3(sx * (xb - 0.36), yc + 0.02, zb), m_alu)
	# carénage aluminium sous l'assise, lèvre avant plus sombre
	var t_assise: Basis = Basis(Vector3.RIGHT, 0.06)
	RemonteeKit.coussin(siege, Vector3(2.0 * xb - 0.02, 0.12, 0.58), Transform3D(t_assise, Vector3(0, -1.08, -0.05)), m_alu, 0.045)
	RemonteeKit.coussin(siege, Vector3(2.0 * xb - 0.06, 0.05, 0.05), Transform3D(t_assise, Vector3(0, -1.06, -0.35)), "noir_mat", 0.02)
	# six coussins d'assise et un dossier bas, peu incliné, sur sa coque
	var dossier_h: float = 0.48
	var t_dos: Basis = Basis(Vector3.RIGHT, -0.10)
	var y_dos: float = -0.98 + dossier_h * 0.5 + 0.07
	if d8:
		_dossier_d8(siege, W, dossier_h + 0.08, Transform3D(t_dos, Vector3(0, y_dos, 0.235)))
		for sx in [-1.0, 1.0]:
			RemonteeKit.coussin(siege, Vector3(0.09, 0.14, 0.52), Transform3D(t_assise, Vector3(sx * (W * 0.5 + 0.0), -0.98, -0.07)), "noir_mat", 0.03)
	else:
		RemonteeKit.coussin(siege, Vector3(W - 0.02, dossier_h + 0.06, 0.05), Transform3D(t_dos, Vector3(0, y_dos, 0.245)), "coque_siege", 0.022)
	var couleurs: Array = _couleurs_assise()
	for i in range(places):
		var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
		var coul: String = couleurs[i % couleurs.size()]
		var a: MeshInstance3D = RemonteeKit.coussin(siege, Vector3(0.48, 0.085, 0.48),
			Transform3D(t_assise, Vector3(cx, -0.975, -0.08)), coul, 0.035)
		a.name = "Assise%d" % i
		if not d8:
			RemonteeKit.coussin(siege, Vector3(0.48, dossier_h, 0.08), Transform3D(t_dos, Vector3(cx, y_dos, 0.20)), coul, 0.035)
	# attaches du dossier sous la poutre
	for sx in [-1.0, 1.0]:
		RemonteeKit.barre(siege, Vector3(sx * W * 0.25, yb0, zb), Vector3(sx * W * 0.25, y_dos + dossier_h * 0.5, 0.25), 0.028, m_alu, 8)
	_garde_corps(siege, W, m_alu)


## Fronton du 8 places : tôle en triangle au-dessus de la poutre, deux grandes
## lumières triangulaires de part et d'autre de l'attache de la suspente.
func _fronton_d8(g: Node3D, xb: float, yb0: float, yb1: float, zb: float, ep: float, m: String) -> void:
	var y_sommet: float = yb1 + 0.20
	var x_pied: float = xb * 0.62
	RemonteeKit.boite_en(g, Vector3(2.0 * xb, 0.05, ep), Vector3(0, yb0 + 0.025, zb), m)
	RemonteeKit.boite_en(g, Vector3(0.44, y_sommet - yb0, ep), Vector3(0, (yb0 + y_sommet) * 0.5, zb), m)
	for sx in [-1.0, 1.0]:
		RemonteeKit.poutre(g, Vector3(sx * x_pied, yb0 + 0.03, zb), Vector3(sx * 0.18, y_sommet - 0.02, zb), 0.07, ep, m, Vector3.BACK)
		RemonteeKit.poutre(g, Vector3(sx * x_pied * 0.60, yb0 + 0.03, zb), Vector3(sx * 0.20, yb0 + 0.09, zb), 0.05, ep, m, Vector3.BACK)
		# bouts de la poutre
		RemonteeKit.boite_en(g, Vector3(0.14, 0.10, ep), Vector3(sx * (xb - 0.07), yb0 + 0.05, zb), m)


## Dossier d'une pièce du 8 places : 7 vraies lumières aux angles abattus.
func _dossier_d8(g: Node3D, W: float, h: float, xf: Transform3D) -> void:
	var d: Node3D = Node3D.new()
	d.name = "Dossier"
	d.transform = xf
	g.add_child(d)
	var mat: String = "assise_bleue"
	var e: float = 0.035
	var n: int = 7
	var pas: float = (W - 0.02) / float(n)
	var lt: float = pas * 0.50                # largeur d'une lumière
	var ht: float = minf(h * 0.32, 0.17)      # hauteur d'une lumière
	var y_t: float = h * 0.08
	var haut: float = h * 0.5 - (y_t + ht * 0.5)
	var bas: float = (y_t - ht * 0.5) + h * 0.5
	RemonteeKit.boite_en(d, Vector3(W - 0.02, haut, e), Vector3(0, h * 0.5 - haut * 0.5, 0), mat)
	RemonteeKit.boite_en(d, Vector3(W - 0.02, bas, e), Vector3(0, -h * 0.5 + bas * 0.5, 0), mat)
	var biais: ArrayMesh = RemonteeKit.maillage_boite(Vector3(0.05, 0.05, e), RemonteeKit.mat(mat))
	for i in range(n + 1):
		var xm: float = -(W - 0.02) * 0.5 + pas * i
		var l: float = pas - lt
		if i == 0 or i == n:
			l *= 0.5
			xm += (l * 0.5) * (1.0 if i == 0 else -1.0)
		RemonteeKit.boite_en(d, Vector3(l, ht, e), Vector3(xm, y_t, 0), mat)
	for i in range(n):
		var xc: float = -(W - 0.02) * 0.5 + pas * (i + 0.5)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var mi: MeshInstance3D = MeshInstance3D.new()
				mi.mesh = biais
				mi.position = Vector3(xc + sx * lt * 0.5, y_t + sy * ht * 0.5, 0)
				mi.rotation.z = PI * 0.25
				d.add_child(mi)


## Ossature des sièges débrayables et fixes récents, d'après les photos des
## lignes du domaine (reportages remontees-mecaniques.net : Palafour
## Doppelmayr, Marais Poma OCR, Laisinant Garaventa SK6, Almes GMM) :
## - poutre de tête en caisson sur toute la largeur, plaque du numéro ;
## - à chaque bout, un cadre latéral en boucle arrondie : il descend
##   derrière le dossier, passe sous l'assise, remonte à l'avant jusqu'à
##   l'accoudoir, qui revient vers l'arrière ;
## - assise rembourrée sur un carénage aluminium à grosse lèvre arrondie
##   (Doppelmayr, Garaventa), dossier en coques individuelles ajourées
##   (Doppelmayr) ou pleines, plus haut sur les sièges fixes ;
## - repose-pieds sur le garde-corps (voir _garde_corps).
func _ossature_moderne(siege: Node3D, W: float, m: String) -> void:
	var c: String = constructeur()
	var fixe: bool = c == "fixe"
	var xb: float = W * 0.5 + 0.03
	# poutre de tête : caisson, plaque du numéro au milieu
	var yh: float = 0.10
	var zh: float = 0.20
	RemonteeKit.coussin(siege, Vector3(2.0 * xb, 0.12, 0.16), Transform3D(Basis.IDENTITY, Vector3(0, yh, zh)), m, 0.03)
	RemonteeKit.boite_en(siege, Vector3(0.16, 0.30, 0.14), Vector3(0.10, yh + 0.18, zh), m)
	RemonteeKit.boite_en(siege, Vector3(0.18, 0.09, 0.01), Vector3(0.0, yh, zh - 0.085), "blanc_plaque")
	_numero(siege, str(numero), Vector3(0.0, yh, zh - 0.092), PI, 52, 0.0016, Color(0.05, 0.05, 0.06))
	_numero(siege, str(numero), Vector3(0.0, yh, zh + 0.092), 0.0, 52, 0.0016, Color(0.05, 0.05, 0.06))
	# cadres latéraux en boucle arrondie
	var r: float = 0.14
	for sx in [-1.0, 1.0]:
		var x: float = sx * xb
		var boucle: PackedVector3Array = PackedVector3Array([Vector3(x, yh, zh)])
		var y_bas: float = -1.07
		var z_ar: float = 0.27
		var z_av: float = -0.36
		var y_acc: float = -0.66
		boucle.append(Vector3(x, -0.25, z_ar))
		for p in RemonteeKit.arc(Vector3(x, y_bas + r, z_ar - r), Vector3.BACK, Vector3.DOWN, r, 0.0, PI * 0.5, 5):
			boucle.append(p)
		for p in RemonteeKit.arc(Vector3(x, y_bas + r, z_av + r), Vector3.DOWN, Vector3.FORWARD, r, 0.0, PI * 0.5, 5):
			boucle.append(p)
		for p in RemonteeKit.arc(Vector3(x, y_acc - r, z_av + r), Vector3.FORWARD, Vector3.UP, r, 0.0, PI * 0.5, 5):
			boucle.append(p)
		boucle.append(Vector3(x, y_acc, 0.10))
		boucle.append(Vector3(x, y_acc + 0.02, z_ar - 0.02))
		RemonteeKit.tube(siege, boucle, 0.032, m, 10)
		RemonteeKit.coussin(siege, Vector3(0.07, 0.045, 0.34), Transform3D(Basis.IDENTITY, Vector3(x - sx * 0.01, y_acc + 0.04, -0.07)), "coque_siege", 0.02)
	# assise : coussins sur un bac, lèvre avant arrondie (carénage alu)
	var assises: Array = _couleurs_assise()
	var t_assise: Basis = Basis(Vector3.RIGHT, 0.08)
	RemonteeKit.coussin(siege, Vector3(W, 0.07, 0.52), Transform3D(t_assise, Vector3(0, -1.04, -0.06)), "alu_pince" if not fixe else m, 0.03)
	if c in ["doppelmayr", "garaventa"]:
		RemonteeKit.cylindre(siege, 0.075, 0.075, W, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -1.03, -0.33)), "alu_pince", 18)
	var dossier_h: float = 0.42 if famille == "siege_poma_ocr6" else (0.70 if fixe else 0.56)
	var t_dos: Basis = Basis(Vector3.RIGHT, -0.16)
	var y_dos: float = -0.98 + dossier_h * 0.5 + 0.07
	for i in range(places):
		var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
		var mc: String = assises[i % assises.size()]
		var a: MeshInstance3D = RemonteeKit.coussin(siege, Vector3(0.47, 0.08, 0.46),
			Transform3D(t_assise, Vector3(cx, -0.975, -0.08)), mc, 0.035)
		a.name = "Assise%d" % i
		if c == "doppelmayr":
			# coque de dossier individuelle, ajourée (deux jours ovales)
			RemonteeKit.coussin(siege, Vector3(0.46, dossier_h, 0.06), Transform3D(t_dos, Vector3(cx, y_dos, 0.21)), "noir_mat", 0.04)
			RemonteeKit.coussin(siege, Vector3(0.40, dossier_h * 0.55, 0.05), Transform3D(t_dos, Vector3(cx, y_dos - dossier_h * 0.18, 0.18)), mc, 0.03)
			for dz in [-0.11, 0.11]:
				RemonteeKit.cylindre(siege, 0.05, 0.05, 0.065, Transform3D(t_dos * Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx + dz, y_dos + dossier_h * 0.28, 0.215)), "joint", 12)
		else:
			RemonteeKit.coussin(siege, Vector3(0.47, dossier_h, 0.07), Transform3D(t_dos, Vector3(cx, y_dos, 0.20)),
				"cabine_blanche" if fixe else mc, 0.03)
	# attaches du dossier sous la poutre de tête
	for sx2 in [-1.0, 1.0]:
		RemonteeKit.barre(siege, Vector3(sx2 * W * 0.25, yh, zh), Vector3(sx2 * W * 0.25, y_dos + dossier_h * 0.5, 0.26), 0.022, m, 8)


func _couleurs_assise() -> Array:
	match famille:
		"siege_poma_ocr6":
			return ["assise_bleue", "assise_noire"]
		"siege_garaventa_sk6":
			return ["assise_bleue"]
		"siege_bartholet_6":
			return ["assise_noire"]
		"siege_doppelmayr_e98_8":
			return ["assise_bleue"]
		"siege_doppelmayr_e98_6":
			return ["assise_noire", "assise_bleue"]
		"siege_fixe_4", "siege_fixe_3":
			return ["assise_bleue"]          # dossiers blancs (Almes)
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
	if famille.begins_with("siege"):
		_garde_corps_bmf(siege, W, m, xe)
		return
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
	if famille in ["siege_poma_ocr6", "siege_bartholet_6", "siege_doppelmayr_e98_6", "siege_doppelmayr_e98_8"]:
		for i in range(places):
			var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
			RemonteeKit.barre(_gc, Vector3(cx, ventre.y, ventre.z), Vector3(cx, ventre.y - 0.30, ventre.z + 0.05), 0.016, m, 6)


## Garde-corps BMF : son axe est juste au-dessus du dossier, en arrière, et
## il bascule vers le haut (retour d'utilisateur, 23/10/2026). Compact : bras
## courts au-dessus des accoudoirs, barre ventrale près du ventre ; trois
## repose-pieds (un pour deux places), chacun tenu par UNE seule tige
## (gros plans de la ligne) et terminé par un patin en T.
func _garde_corps_bmf(siege: Node3D, W: float, m: String, xe: float) -> void:
	# axe : au ras du haut du dossier (siège : y −0,43), derrière lui
	var axe: Vector3 = Vector3(0, -0.40, 0.31)
	_gc.position = axe
	_gc_releve = 1.40
	for sx in [-1.0, 1.0]:
		# chape de l'axe sur la coque du dossier
		RemonteeKit.boite_en(siege, Vector3(0.06, 0.10, 0.09), axe + Vector3(sx * (xe + 0.02), -0.02, -0.02), m)
		RemonteeKit.cylindre(siege, 0.03, 0.03, 0.08, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), axe + Vector3(sx * (xe + 0.02), 0, 0)), "acier_noir", 10)
	# repère de l'axe : barre ventrale 0,34 m au-dessus de l'assise, 0,32 m
	# devant son milieu ; patins 0,17 m sous l'assise, juste devant son nez
	var ventre: Vector3 = Vector3(0, -0.24, -0.71)
	# repose-skis au niveau des pieds du passager assis (0,45 m sous
	# l'assise) : les skis reposent dessus au lieu de pendre dessous
	var pied: Vector3 = Vector3(0, -1.06, -0.80)
	for sx in [-1.0, 1.0]:
		RemonteeKit.tube(_gc, PackedVector3Array([Vector3(sx * xe, 0, 0), Vector3(sx * xe, 0.02, -0.28),
			Vector3(sx * xe, -0.10, -0.56), Vector3(sx * xe, ventre.y, ventre.z)]), 0.022, m, 8)
	RemonteeKit.barre(_gc, Vector3(-xe, ventre.y, ventre.z), Vector3(xe, ventre.y, ventre.z), 0.026, m, 10)
	# 3 places (photos des lignes) : deux T séparés, symétriques, aux limites entre places, traverse noire de
	# 0,45 m (avec un repose-pieds pour deux places, le seul T tombait à 0,25 m de l'axe et la 3e place n'avait rien)
	var trois: bool = places == 3
	var demi_t: float = 0.225 if trois else 0.40
	var m_t: String = "noir_mat" if trois else m
	var centres: Array = [-W / 6.0, W / 6.0] if trois else []
	if not trois:
		for k in range(places / 2):
			centres.append(-W * 0.5 + 0.10 + 1.0 * (k + 0.5))
	for cx in centres:
		# une seule tige, légèrement coudée, de la barre au repose-pieds
		RemonteeKit.tube(_gc, PackedVector3Array([Vector3(cx, ventre.y, ventre.z), Vector3(cx, (ventre.y + pied.y) * 0.5, ventre.z - 0.10),
			Vector3(cx, pied.y, pied.z)]), 0.017, m, 6)
		# patin en T : traverse et semelle caoutchouc, pour deux paires de skis
		RemonteeKit.poutre(_gc, Vector3(cx - demi_t, pied.y, pied.z), Vector3(cx + demi_t, pied.y, pied.z), 0.05, 0.025, m_t)
		RemonteeKit.boite_en(_gc, Vector3(demi_t * 2.0 - 0.02, 0.02, 0.13), Vector3(cx, pied.y + 0.02, pied.z + 0.01), "caoutchouc")


## 0 : relevé (au-dessus des têtes) ; 1 : baissé.
func garde_corps(t: float) -> void:
	if t == _etat_anim[1]:
		return
	_etat_anim[1] = t
	if _gc != null:
		_gc.rotation.x = lerpf(_gc_releve, 0.0, clampf(t, 0.0, 1.0))


## Bulle des Lanches (sièges Études de Transports, pinces ET-106), refaite
## entièrement d'après les vidéos et les photos de la ligne (retours
## d'utilisateur, 28/10/2026 : « ton design de bulle c'est à refaire depuis
## 0 ») : 2,50 m de large ; de profil une coque en « D » ; de face un rectangle aux coins arrondis, extrémités en calottes
## bombées, face avant verticale et toit presque plat ; fermée,
## sommet à 1,15 m au-dessus de l'assise et bord ~0,12 m
## dessous ; moyeu de chaque côté à ~0,25 m au-dessus de l'assise, à
## l'aplomb du dossier ; elle bascule de 90° vers l'ARRIÈRE et se loge
## au-dessus et derrière le dossier. Bandeau bas sombre de 0,35 m portant
## une plaque blanche « TIGNES » (rouge) au milieu et un carré blanc au
## logo bleu à chaque bout, deux sangles noires de préhension ;
## polycarbonate fumé gris.
var _bulle_l: float = 2.50           # largeur hors tout (2,50 m mesurés ; selon le siège)
const BULLE_AVANT: float = 0.85      # moyeu → face avant, à plat (retour d'utilisateur, 02/11/2026 : « va moins loin devant »)
const BULLE_HAUT: float = 0.90       # moyeu → toit : assise + 1,15 m (le casque est à assise + 0,94 ; il dépassait du toit à + 0,90)
const BULLE_BAS: float = 0.37        # moyeu → bord du bandeau, en dessous (bord ~0,12 m sous l'assise)
const BULLE_S_FACE: float = 0.80     # abscisse s où commence la face avant droite
const BULLE_BANDEAU: float = 0.35


## Point de la coque (repère de la bulle : moyeu à l'origine, bulle fermée) ;
## s : de 0 (moyeu) à 1 (bord du bandeau) ; t : de -1 à 1 sur la largeur.
## Fermée, de profil : une arche du moyeu au haut de la face avant, puis une
## face avant VERTICALE, qui ne déverse pas (retour d'utilisateur, 02/11/2026).
func _bulle_point(s: float, t: float) -> Vector3:
	var p: Vector2                                                     # (z, y)
	if s < BULLE_S_FACE:
		# demi-superellipse : flancs raides, toit presque plat
		var th: float = PI * s / BULLE_S_FACE
		var cs: float = cos(th)
		var u: float = signf(cs) * pow(absf(cs), 2.0 / 3.5)
		p = Vector2(-BULLE_AVANT * 0.5 * (1.0 - u), BULLE_HAUT * pow(sin(th), 2.0 / 3.5))
	else:
		p = Vector2(-BULLE_AVANT, -BULLE_BAS * (s - BULLE_S_FACE) / (1.0 - BULLE_S_FACE))
	# calottes : le bombé tombe à zéro aux extrémités, sur la droite moyeu → bord
	var k: float = pow(maxf(0.0, 1.0 - pow(absf(t), 4.0)), 0.25)
	var corde: Vector2 = Vector2(-BULLE_AVANT, -BULLE_BAS) * s
	p = corde.lerp(p, k)
	return Vector3(t * _bulle_l * 0.5, p.y, p.x)


func _bulle_siege(siege: Node3D, W: float) -> void:
	_bulle = Node3D.new()
	_bulle.name = "Bulle"
	_bulle_l = W + 0.22
	# moyeu : ~0,25 m au-dessus de l'assise (-0,93), sur le coude du cadre
	# latéral, à l'aplomb du dossier
	_bulle.position = Vector3(0, -0.68, 0.27)
	siege.add_child(_bulle)
	var ns: int = 28
	var nt: int = 24
	# abscisse s du haut du bandeau (0,35 m de coque mesurés depuis le bord)
	var s_b: float = 1.0
	var l_: float = 0.0
	for i in range(200, 0, -1):
		var a: Vector3 = _bulle_point(float(i) / 200.0, 0.0)
		var b: Vector3 = _bulle_point(float(i - 1) / 200.0, 0.0)
		l_ += a.distance_to(b)
		if l_ >= BULLE_BANDEAU:
			s_b = float(i - 1) / 200.0
			break
	# coque (polycarbonate) et bandeau (blanc), même nappe
	for part in [[0.0, s_b, "bulle"], [s_b, 1.0, "acier_noir"]]:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n_: int = ns if part[2] == "bulle" else 6
		for i in range(n_):
			var s0: float = lerpf(part[0], part[1], float(i) / n_)
			var s1: float = lerpf(part[0], part[1], float(i + 1) / n_)
			for j in range(nt):
				var t0: float = lerpf(-1.0, 1.0, float(j) / nt)
				var t1: float = lerpf(-1.0, 1.0, float(j + 1) / nt)
				var q: Array = [_bulle_point(s0, t0), _bulle_point(s0, t1), _bulle_point(s1, t1), _bulle_point(s1, t0)]
				for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
					st.add_vertex(v)
		st.generate_normals()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = MeshMerge.valider(st)
		var m_: StandardMaterial3D = RemonteeKit.mat(part[2])
		if part[2] != "bulle":
			m_ = m_.duplicate()
			m_.cull_mode = BaseMaterial3D.CULL_DISABLED      # (nappe vue des deux côtés)
		mi.mesh.surface_set_material(0, m_)
		mi.name = "Coque" if part[2] == "bulle" else "Bandeau"
		_bulle.add_child(mi)
	# joncs : noir sur le haut du bandeau et le long du bord, alu sur les côtés
	var haut_b: PackedVector3Array = PackedVector3Array()
	var bord: PackedVector3Array = PackedVector3Array()
	for j in range(nt + 1):
		var t: float = lerpf(-1.0, 1.0, float(j) / nt)
		haut_b.append(_bulle_point(s_b, t))
		bord.append(_bulle_point(1.0, t))
	RemonteeKit.tube(_bulle, haut_b, 0.015, "alu_pince", 6)
	RemonteeKit.tube(_bulle, bord, 0.035, "noir_mat", 6)
	for sx in [-1.0, 1.0]:
		RemonteeKit.tube(_bulle, PackedVector3Array([_bulle_point(0.0, sx), _bulle_point(1.0, sx)]), 0.018, "alu_pince", 6)
		# moyeu (disque ~12 cm) sur le coude de la suspente
		RemonteeKit.cylindre(_bulle, 0.06, 0.06, 0.05, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * (W * 0.5 + 0.06), 0, 0)), "acier_noir", 12)
		# sangle noire de préhension, du polycarbonate vers le bandeau
		var sangle: PackedVector3Array = PackedVector3Array()
		for k in range(6):
			var pt: Vector3 = _bulle_point(lerpf(s_b - 0.30, s_b, float(k) / 5.0), sx * 0.42)
			sangle.append(pt + (pt - _bulle_point(s_b * 0.5, sx * 0.42)).normalized() * 0.012)
		RemonteeKit.tube(_bulle, sangle, 0.03, "noir_mat", 5)
	# décor du bandeau : « TIGNES » rouge au milieu, logo STGM (vague bleue) à chaque bout
	var sm: float = lerpf(s_b, 1.0, 0.5)
	for e in [["TIGNES", 0.0, 64, 0.0026, Color(0.78, 0.08, 0.08)], ["STGM", -0.76, 40, 0.0014, Color(0.10, 0.30, 0.65)], ["STGM", 0.76, 40, 0.0014, Color(0.10, 0.30, 0.65)]]:
		var p0: Vector3 = _bulle_point(sm, e[1])
		var nrm: Vector3 = (_bulle_point(sm, e[1] + 0.02) - _bulle_point(sm, e[1] - 0.02)).cross(_bulle_point(sm + 0.02, e[1]) - _bulle_point(sm - 0.02, e[1])).normalized()
		if nrm.dot(p0 - _bulle_point(s_b * 0.5, 0.0)) < 0.0:
			nrm = -nrm
		var mt: MeshInstance3D = MeshInstance3D.new()
		mt.mesh = RemonteeKit.maillage_texte(e[0], e[2], e[3])
		mt.material_override = _mat_texte(e[4])
		# le texte regarde le long de la normale, à l'endroit (axe x de la bulle)
		var z_: Vector3 = nrm
		var x_: Vector3 = Vector3.UP.cross(z_).normalized() if absf(z_.y) < 0.95 else Vector3.RIGHT
		var bs_: Basis = Basis(x_, z_.cross(x_), z_)
		mt.transform = Transform3D(bs_, p0 + nrm * 0.012 - bs_.y * (0.0 if e[0] == "TIGNES" else 0.06))
		# plaque blanche sous le texte (centre : 0,60 × 0,22 ; bouts : carré 0,28)
		var pl: MeshInstance3D = MeshInstance3D.new()
		pl.mesh = RemonteeKit.maillage_boite(Vector3(0.60, 0.22, 0.008) if e[0] == "TIGNES" else Vector3(0.28, 0.26, 0.008),
			RemonteeKit.mat("blanc_plaque"))
		pl.material_override = RemonteeKit.mat("blanc_plaque")
		pl.transform = Transform3D(bs_, p0 + nrm * 0.006)
		_bulle.add_child(pl)
		if miroir:
			mt.scale = Vector3(-1, 1, 1)
		mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bulle.add_child(mt)
		if e[0] == "STGM":
			# vague bleue au-dessus du sigle
			var w_: Vector3 = p0 + nrm * 0.012 + z_.cross(x_) * 0.04
			RemonteeKit.tube(_bulle, PackedVector3Array([w_ - x_ * 0.11, w_ - x_ * 0.04 + z_.cross(x_) * 0.03, w_ + x_ * 0.03, w_ + x_ * 0.11 + z_.cross(x_) * 0.03]), 0.012, "bleu_logo", 5)


## 0 : ouverte (relevée sur le dossier) ; 1 : fermée devant les passagers.
func bulle(t: float) -> void:
	if t == _etat_anim[2]:
		return
	_etat_anim[2] = t
	if _bulle != null:
		_bulle.rotation.x = lerpf(PI * 0.5, 0.0, clampf(t, 0.0, 1.0))   # bascule de 90° vers l'arrière


# --- cabines -------------------------------------------------------------------------

func _cabine() -> void:
	pivot = A108_PIVOT
	_tige_guidage()
	var sus_m: String = "acier_noir" if famille != "cabine_omega4" else "galva"
	var hs: float = H_SUSP_CABINE
	# suspente (plans CWA de l'Omega V, Wikimedia Commons) : de la pince elle
	# descend à l'extérieur, se cintre vers l'intérieur et finit en poutre
	# horizontale posée sur le toit par deux pieds
	var arc: PackedVector3Array = PackedVector3Array()
	var p0: Vector3 = A108_PIVOT
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
	var mailles: Dictionary = _maillage_cabine(famille, teinte)
	for cle in ["coque", "vitres"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = cle.capitalize()
		mi.mesh = mailles[cle]
		cab.add_child(mi)
	_logo_station(cab, 1.0)
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
		# porte-skis sur le vantail, à l'extérieur : deux berceaux en U et
		# la paire de skis du passager quand il l'y a rangée
		var zr: float = sz * 0.28
		for yk in [-H + 0.55, -H + 1.45]:
			RemonteeKit.boite_en(v, Vector3(0.14, 0.04, 0.22), Vector3(1.34, yk, zr), "acier_noir")
			for dz in [-0.10, 0.10]:
				RemonteeKit.boite_en(v, Vector3(0.02, 0.10, 0.02), Vector3(1.40, yk + 0.05, zr + dz), "acier_noir")
		var sk: Node3D = Node3D.new()
		sk.name = "SkisRanges"
		sk.visible = false
		v.add_child(sk)
		for dz2 in [-0.04, 0.04]:
			RemonteeKit.boite_en(sk, Vector3(0.03, 1.55, 0.075), Vector3(1.38, -H + 1.0, zr + dz2), "assise_bleue")
		_skis_ranges.append(sk)
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
	# numéro de la cabine (le même que sur la pince), en blanc dans le cadre
	# noir sous le toit, sur les quatre faces (retour d'utilisateur, 23/10/2026 :
	# « pas de numéro sur les cabines »)
	var no: String = "%02d" % numero
	# (cadre noir entre le toit et le haut des vitres, au-dessus des portes)
	for f in [[Vector3(0, -0.16, 0.515), 0.0], [Vector3(0, -0.16, -0.515), PI], [Vector3(1.005, -0.16, 0.0), PI * 0.5],
			[Vector3(-1.005, -0.16, 0.0), -PI * 0.5]]:
		_numero(cab, no, f[0], f[1], 56, 0.0018, Color(1, 1, 1))
	if famille == "cabine_diamond":
		# porte-skis extérieurs sur la face opposée aux portes : deux paniers
		for sz in [-1.0, 1.0]:
			var zp: float = sz * 0.45
			for yk in [-H + 0.62, -H + 1.62]:
				RemonteeKit.boite_en(cab, Vector3(0.20, 0.06, 0.30), Vector3(-1.36, yk, zp), "acier_noir")
			for dz in [-0.12, 0.12]:
				RemonteeKit.barre(cab, Vector3(-1.45, -H + 0.62, zp + dz), Vector3(-1.45, -H + 1.62, zp + dz), 0.015, "acier_noir", 6)


## Écart des deux câbles porteurs d'une voie du 3S (axe à axe) et hauteur
## du tracteur sous eux, dans le repère du chariot (origine : milieu des
## porteurs).
## Chariot du 3S : cotes estimées sur photo, d'après le Ø connu des porteurs (57 mm), incertitude ±15 %.
const E_PORTEURS_3S: float = 0.80
## Téléphériques va-et-vient (Fornet, Grande Motte) : deux porteurs par voie (fiches RM.net) ; écart estimé
## sur les photos du chariot (deux rangées de galets, une poutre entre elles).
const E_PORTEURS_TPH: float = 0.70
## Caisse du Fornet (CWA, photos) : bouts à trois pans, coins coupés (rayon de la Grande Motte + 0,60 m, estimé sur photo).
const PANS_FORNET: String = "pans_fornet"
const R_PANS_FORNET: float = 0.60
const ENTRAXE_GALETS_3S: float = 0.62
const Z_BALANCIER_3S: float = 0.80        # du milieu du chariot au milieu d'un balancier
const Y_POUTRES_3S: float = 0.40
const X_PIVOT_3S: float = 0.68
const Y_PIVOT_3S: float = -0.22
const Y_TRACTEUR_3S: float = -0.42
const Y_CORPS_3S: float = 0.13          # corps de la pince, au-dessus du tracteur
const H_SUSP_3S: float = 2.65        # du chariot au toit de la cabine (mesuré en vidéo : 2,6-2,7)


## Galet du chariot, axe X : deux flasques d'aluminium, bandage clair entre elles, moyeu, et de quoi le voir tourner.
func _galet_chariot(n: Node3D) -> void:
	var tr: Basis = Basis(Vector3.FORWARD, PI * 0.5)
	RemonteeKit.cylindre(n, R_GALET_CHARIOT, R_GALET_CHARIOT, 0.11, Transform3D(tr, Vector3.ZERO), "polyurethane", 20)
	for sx in [-1.0, 1.0]:
		RemonteeKit.cylindre(n, R_FLASQUE_CHARIOT, R_FLASQUE_CHARIOT, 0.016, Transform3D(tr, Vector3(sx * 0.063, 0, 0)), "alu_pince", 24)
		RemonteeKit.cylindre(n, 0.085, 0.085, 0.014, Transform3D(tr, Vector3(sx * 0.073, 0, 0)), "acier", 14)
		RemonteeKit.cylindre(n, 0.042, 0.042, 0.02, Transform3D(tr, Vector3(sx * 0.08, 0, 0)), "acier_noir", 10)
		# fenêtres sombres du moyeu, inégales : un motif symétrique se fige à l'écran
		for k in range(3):
			var a: float = TAU * k / 3.0
			var taille: float = 0.040 if k == 0 else 0.026
			RemonteeKit.boite_en(n, Vector3(0.006, taille, taille), Vector3(sx * 0.073, cos(a) * 0.15, sin(a) * 0.15), "noir_mat")


## Véhicule du 3S de l'Olympique (photos de la ligne, reportage
## remontees-mecaniques.net) : chariot de 2×4 galets alu sur balanciers bleus,
## un train par câble porteur ; pince du tracteur au milieu, sous eux, avec
## ses ressorts ; suspente unique en caisson gris foncé, coudée ; cabine
## CWA Zeta 30 places (24 assises), portes coulissantes côté quai.
func _cabine_zeta() -> void:
	_zeta_chariot()
	_zeta_caisse()


func _zeta_chariot() -> void:
	# le chariot roule sur les porteurs (nœud « Pince », fixe) ; suspente et cabine balancent autour de la
	# grosse articulation, sur le flanc du corps et sous le plan des porteurs
	pivot = Vector3(X_PIVOT_3S, Y_PIVOT_3S, 0)
	var ch: Node3D = Node3D.new()
	ch.name = "Pince"
	add_child(ch)
	var gris: String = "peinture_anthracite"
	var e: float = E_PORTEURS_3S * 0.5
	var y_axe: float = R_GALET_CHARIOT + 0.0285
	# quatre balanciers bleus de deux galets : un à chaque bout de chaque porteur
	for sx in [-1.0, 1.0]:
		var x: float = sx * e
		for bz in [-1.0, 1.0]:
			var zb: float = bz * Z_BALANCIER_3S
			for gz in [-0.5, 0.5]:
				var gn: Node3D = Node3D.new()
				gn.name = "GaletChariot"
				gn.position = Vector3(x, y_axe, zb + gz * ENTRAXE_GALETS_3S)
				ch.add_child(gn)
				_galet_chariot(gn)
				_galets_roul.append(gn)
			# bras du balancier, côté extérieur et plus mince côté intérieur, avec la plaque qui monte au corps
			var xb: float = x + sx * 0.105
			var tete: Vector3 = Vector3(xb, y_axe, zb + bz * ENTRAXE_GALETS_3S * 0.5 + bz * 0.20)
			var queue: Vector3 = Vector3(xb, y_axe, zb - bz * ENTRAXE_GALETS_3S * 0.5)
			RemonteeKit.poutre(ch, queue, Vector3(xb, y_axe + 0.03, zb), 0.03, 0.09, "bleu_doppelmayr")
			RemonteeKit.poutre(ch, Vector3(xb, y_axe + 0.03, zb), tete, 0.03, 0.09, "bleu_doppelmayr")
			RemonteeKit.poutre(ch, Vector3(x - sx * 0.105, y_axe, zb - ENTRAXE_GALETS_3S * 0.5), Vector3(x - sx * 0.105, y_axe, zb + ENTRAXE_GALETS_3S * 0.5), 0.02, 0.06, "bleu_doppelmayr")
			RemonteeKit.boite_en(ch, Vector3(0.03, Y_POUTRES_3S - y_axe, 0.14), Vector3(xb, (Y_POUTRES_3S + y_axe) * 0.5, zb), "bleu_doppelmayr")
			RemonteeKit.cylindre(ch, 0.025, 0.025, 0.26, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, y_axe, zb)), "acier", 8)
			# crosse d'extrémité rouge et blanche
			RemonteeKit.boite_en(ch, Vector3(0.20, 0.16, 0.035), tete + Vector3(-sx * 0.09, 0.0, bz * 0.02), "cabine_rouge")
			RemonteeKit.boite_en(ch, Vector3(0.11, 0.08, 0.012), tete + Vector3(-sx * 0.09, 0.0, bz * 0.043), "polyurethane")
			# traverse au-dessus du porteur, du corps au balancier
			RemonteeKit.boite_en(ch, Vector3(xb * sx - 0.10, 0.08, 0.12), Vector3(sx * (xb * sx + 0.10) * 0.5, Y_POUTRES_3S, zb), gris)
	# corps au-dessus du tracteur : rien ne descend sous lui que les mâchoires, à 3 cm sous son axe, la hauteur du
	# haut des galets des cavaliers et des pylônes (retour d'utilisateur du 06/11/2026 : la quille, 0,21 m sous le
	# câble, traversait les galets ; le câble n'est soulevé que de l'épaisseur des mâchoires)
	RemonteeKit.boite_en(ch, Vector3(0.26, 0.12, 1.10), Vector3(0, Y_TRACTEUR_3S + Y_CORPS_3S, 0), gris)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			RemonteeKit.poutre(ch, Vector3(sx * 0.15, Y_TRACTEUR_3S + Y_CORPS_3S, sz * 0.50), Vector3(sx * 0.15, Y_POUTRES_3S, sz * 0.50), 0.09, 0.20, gris, Vector3.BACK)
			# cale claire en bout de poutre
			RemonteeKit.boite_en(ch, Vector3(0.13, 0.10, 0.10), Vector3(sx * 0.15, Y_POUTRES_3S + 0.03, sz * 0.92), "polyurethane")
	# deux poutres carrées à semelle noire crantée : les pneus du lanceur roulent dessus
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(ch, Vector3(0.11, 0.09, 1.80), Vector3(sx * 0.15, Y_POUTRES_3S + 0.03, 0), "alu_pince")
		RemonteeKit.boite_en(ch, Vector3(0.11, 0.02, 1.10), Vector3(sx * 0.15, 0.45, 0), "noir_mat")
		for k in range(7):
			RemonteeKit.boite_en(ch, Vector3(0.11, 0.012, 0.05), Vector3(sx * 0.15, 0.462, -0.48 + k * 0.16), "noir_mat")
	# mâchoires empilées autour du tracteur, entre les deux porteurs
	for k in range(3):
		var zm: float = (k - 1.0) * 0.27
		RemonteeKit.boite_en(ch, Vector3(0.19, 0.08, 0.23), Vector3(0, Y_TRACTEUR_3S + 0.01, zm), "alu_pince")
		RemonteeKit.boite_en(ch, Vector3(0.09, 0.05, 0.20), Vector3(-0.055, Y_TRACTEUR_3S + 0.07, zm), "alu_pince")
	for sz in [-1.0, 1.0]:
		RemonteeKit.demi_cone(ch, Vector3(0, Y_TRACTEUR_3S, sz * 0.40), Vector3(0, Y_TRACTEUR_3S, sz * 0.68), 0.05, 0.028, "noir_mat", 12)
		# tige rouge en U autour du tracteur
		var u: PackedVector3Array = PackedVector3Array()
		for pt in [Vector3(-0.30, -0.02, 0), Vector3(-0.10, Y_TRACTEUR_3S - 0.015, 0), Vector3(0.10, Y_TRACTEUR_3S - 0.015, 0), Vector3(0.30, -0.02, 0)]:
			u.append((pt as Vector3) + Vector3(0, 0, sz * 0.68))
		RemonteeKit.tube(ch, u, 0.012, "cabine_rouge", 6)
		# petit amortisseur rouge
		RemonteeKit.boite_en(ch, Vector3(0.05, 0.22, 0.05), Vector3(0.21, 0.10, sz * 0.36), "cabine_rouge")
		RemonteeKit.cylindre(ch, 0.03, 0.03, 0.15, Transform3D(Basis.IDENTITY, Vector3(0.21, 0.10, sz * 0.36)), "noir_mat", 8)
		# ouverture de la pince, côté intérieur de la boucle : bras sous le porteur, ressort incliné à disques,
		# paire de galets clairs en bout (ils portent sur le rail courbe de la gare)
		var zp: float = sz * 0.17
		var pied: Vector3 = Vector3(-0.60, -0.10, zp)
		RemonteeKit.poutre(ch, Vector3(-0.12, Y_TRACTEUR_3S + 0.05, zp), pied, 0.05, 0.11, "alu_pince", Vector3.BACK)
		var d_r: Vector3 = Vector3(-0.72, 0.69, 0).normalized()
		var r: Node3D = Node3D.new()
		r.position = pied
		r.basis = Basis(d_r.cross(Vector3.BACK).normalized(), d_r, Vector3.BACK)
		ch.add_child(r)
		RemonteeKit.ressort(r, Vector3.ZERO, Vector3.UP, 0.30, 0.085, 0.016, 9, "ressort_gris")
		_ressorts.append(r)
		var bout: Vector3 = pied + d_r * 0.34
		RemonteeKit.boite_en(ch, Vector3(0.07, 0.07, 0.24), bout, "alu_pince")
		for dz in [-0.11, 0.11]:
			RemonteeKit.cylindre(ch, 0.09, 0.09, 0.07, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), bout + Vector3(-0.07, 0.02, dz)), "polyurethane", 16)
	# grosse articulation ronde, sur le flanc du corps, sous le plan du porteur
	RemonteeKit.poutre(ch, Vector3(0.10, Y_TRACTEUR_3S + Y_CORPS_3S, 0), Vector3(X_PIVOT_3S, Y_PIVOT_3S, 0), 0.40, 0.14, gris, Vector3.BACK)
	RemonteeKit.cylindre(ch, 0.17, 0.17, 0.26, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(X_PIVOT_3S, Y_PIVOT_3S, 0)), gris, 18)
	RemonteeKit.cylindre(ch, 0.07, 0.07, 0.28, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(X_PIVOT_3S, Y_PIVOT_3S, 0)), "acier_noir", 12)


## Suspente, caisse, intérieur et baies de la Zeta (après le chariot).
func _zeta_caisse() -> void:
	var gris: String = "peinture_anthracite"
	# suspente : caisson coudé, de l'articulation au toit ; elle s'écarte pour laisser passer les porteurs
	# puis revient au-dessus du centre de la cabine
	var hs: float = H_SUSP_3S
	var arc_z: PackedVector3Array = PackedVector3Array()
	var q0: Vector3 = Vector3(X_PIVOT_3S, Y_PIVOT_3S, 0)
	var q1: Vector3 = Vector3(1.05, Y_PIVOT_3S - 0.25, 0)
	var q2: Vector3 = Vector3(0.95, -hs + 0.30, 0)
	var q3: Vector3 = Vector3(0.0, -hs + 0.05, 0)
	for k in range(21):
		var t: float = float(k) / 20.0
		var w: float = 1.0 - t
		arc_z.append(q0 * w * w * w + q1 * 3.0 * w * w * t + q2 * 3.0 * w * t * t + q3 * t * t * t)
	RemonteeKit.caisson(self, arc_z, 0.22, 0.30, 0.30, gris, Vector3.BACK)
	RemonteeKit.boite_en(self, Vector3(0.50, 0.12, 0.70), Vector3(0, -hs - 0.02, 0), gris)
	# caisse
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hs - 0.08, 0)
	add_child(cab)
	var H: float = _h_cab(famille)
	var mailles: Dictionary = _maillage_cabine(famille, teinte)
	for cle in ["coque", "vitres"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = cle.capitalize()
		mi.mesh = mailles[cle]
		cab.add_child(mi)
	_logo_station(cab, 1.0)
	for sz in [-1.0, 1.0]:
		var v: Node3D = Node3D.new()
		v.name = "Vantail%s" % ("Avant" if sz < 0 else "Arriere")
		cab.add_child(v)
		for cle2 in ["porte_coque", "porte_vitre"]:
			var mi2: MeshInstance3D = MeshInstance3D.new()
			mi2.mesh = mailles[cle2 + ("_p" if sz > 0 else "_m")]
			v.add_child(mi2)
		_portes.append([v, Vector3.ZERO, Vector3(0.06, 0, sz * 0.62)])
	# intérieur : 24 places sur des banquettes rouge et gris le long des
	# parois, barres de maintien (photo de l'intérieur)
	var yp: float = -H + 0.22
	RemonteeKit.boite_en(cab, Vector3(2.50, 0.03, 2.40), Vector3(0, yp, 0), "noir_mat")
	for sz in [-1.0, 1.0]:
		for i in range(6):
			var xi: float = (i - 2.5) * 0.45
			RemonteeKit.coussin(cab, Vector3(0.42, 0.09, 0.44), Transform3D(Basis.IDENTITY, Vector3(xi, yp + 0.44, sz * 1.00)), "cabine_rouge" if i % 2 == 0 else "assise_grise", 0.035)
			RemonteeKit.coussin(cab, Vector3(0.42, 0.50, 0.07), Transform3D(Basis(Vector3.RIGHT, sz * 0.10), Vector3(xi, yp + 0.80, sz * 1.24)), "cabine_rouge" if i % 2 == 0 else "assise_grise", 0.03)
		RemonteeKit.boite_en(cab, Vector3(2.50, 0.40, 0.38), Vector3(0, yp + 0.20, sz * 1.02), "noir_mat")
	for sx in [-0.5, 0.5]:
		RemonteeKit.barre(cab, Vector3(sx, yp, 0.30), Vector3(sx, -0.30, 0.30), 0.02, "acier", 8)
		RemonteeKit.barre(cab, Vector3(sx, yp, -0.30), Vector3(sx, -0.30, -0.30), 0.02, "acier", 8)
	RemonteeKit.barre(cab, Vector3(-0.5, -0.30, 0.30), Vector3(0.5, -0.30, 0.30), 0.02, "acier", 8)
	RemonteeKit.barre(cab, Vector3(-0.5, -0.30, -0.30), Vector3(0.5, -0.30, -0.30), 0.02, "acier", 8)
	# numéro en bas de vitre, sur les quatre faces
	var no: String = "%d" % numero
	for f in [[Vector3(-0.55, -1.13, 1.415), 0.0], [Vector3(0.55, -1.13, -1.415), PI], [Vector3(1.465, -1.13, 0.55), PI * 0.5],
			[Vector3(-1.465, -1.13, -0.55), -PI * 0.5]]:
		_numero(cab, no, f[0], f[1], 56, 0.0034, Color(1, 1, 1))
	_baies_zeta(cab)


## Deux grandes baies par face (photo à quai) : montant central, poteaux d'angle,
## angles de baie abattus ; tampons noirs sur les flancs, en bas de la caisse.
func _baies_zeta(cab: Node3D) -> void:
	var y_h: float = -0.18
	var y_b: float = -1.24
	var yc: float = (y_h + y_b) * 0.5
	var hb: float = y_h - y_b
	var noir: Material = RemonteeKit.mat("cabine_noire")
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# coin de baie : triangle plein vers l'intérieur de la baie (vu des deux côtés)
	var coin = func(c: Vector3, dt: Vector3, dv: Vector3) -> void:
		for v in [c, c + dt, c + dv, c, c + dv, c + dt]:
			st.add_vertex(v)
	var d_c: float = 0.17
	# faces : [normale x, normale z, demi-largeur droite, cote de la face]
	for f in [[0.0, 1.0, 0.91, 1.415], [0.0, -1.0, 0.91, 1.415], [-1.0, 0.0, 0.86, 1.465]]:
		var n: Vector3 = Vector3(f[0], 0, f[1])
		var t: Vector3 = Vector3(f[1], 0, -f[0]).normalized()
		var hw: float = f[2]
		var o: Vector3 = n * float(f[3])
		var sz_m: Vector3 = Vector3(0.10, hb, 0.04) if absf(float(f[1])) > 0.5 else Vector3(0.04, hb, 0.10)
		RemonteeKit.boite_en(cab, sz_m, o + Vector3(0, yc, 0), "cabine_noire")
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var yv: float = y_h if sv > 0.0 else y_b
				var vers_bas: Vector3 = Vector3(0, -sv * d_c, 0)
				coin.call(o + t * (su * 0.05) + Vector3(0, yv, 0), t * (su * d_c), vers_bas)
				coin.call(o + t * (su * hw) + Vector3(0, yv, 0), t * (-su * d_c), vers_bas)
	st.generate_normals()
	var mc: MeshInstance3D = MeshInstance3D.new()
	mc.mesh = MeshMerge.valider_indexe_retenu(st)
	mc.material_override = noir
	cab.add_child(mc)
	# poteaux d'angle, à 45°
	var pot: ArrayMesh = RemonteeKit.maillage_boite(Vector3(0.16, hb, 0.03), noir)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var mi2: MeshInstance3D = MeshInstance3D.new()
			mi2.mesh = pot
			mi2.position = Vector3(sx * 1.30, yc, sz * 1.25)
			mi2.rotation.y = atan2(sx, sz)
			cab.add_child(mi2)
	# tampons noirs
	for sx in [-1.0, 1.0]:
		for sz in [-0.85, 0.85]:
			RemonteeKit.boite_en(cab, Vector3(0.10, 0.20, 0.34), Vector3(sx * 1.45, -1.76, sz), "noir_mat")


## Téléphérique va-et-vient de la Grande Motte (Von Roll 1975, cabine Swoboda
## 1993 ; photos du reportage remontees-mecaniques.net) : chariot de 8 galets
## en deux bogies sur le câble porteur, attaches du tracteur aux deux bouts ;
## grande suspente pleine en coin ; cabine de 115 + 1 places (6,4 × 3,0 m),
## poste du conducteur à l'avant, barres de maintien, portes au milieu.
const H_SUSP_TPH: float = 5.2         # mesuré en vidéo : Fornet 5,1, Grande Motte 5,7


## Suspente du Fornet (photos) : cadre en A dans le plan de la ligne, centré, deux jambes de métal nu
## du chariot au toit, entretoises, caisson long au milieu du toit.
var style_tph: String = ""


func _suspente_fornet(hs: float) -> void:
	var y_toit: float = -hs - 0.02
	var ecart: float = 1.05
	RemonteeKit.boite_en(self, Vector3(0.50, 0.18, 2.0), Vector3(0, y_toit + 0.09, 0), "galva_pylone")
	for sz in [-1.0, 1.0]:
		var bas: Vector3 = Vector3(0, y_toit + 0.15, sz * ecart)
		var genou: Vector3 = Vector3(0, y_toit + 1.05, sz * ecart * 0.82)
		RemonteeKit.poutre(self, Vector3(0, 0.05, sz * 0.10), genou, 0.22, 0.34, "acier", Vector3.RIGHT)
		RemonteeKit.poutre(self, genou, bas, 0.26, 0.40, "acier", Vector3.RIGHT)
	for u in [0.35, 0.60, 0.82]:
		var y: float = lerpf(0.05, y_toit + 1.05, u)
		var z: float = lerpf(0.10, ecart * 0.82, u)
		RemonteeKit.boite_en(self, Vector3(0.14, 0.12, 2.0 * z), Vector3(0, y, 0), "acier")


func _cabine_tph() -> void:
	pivot = Vector3(0, 0.0, 0)
	var ch: Node3D = Node3D.new()
	ch.name = "Pince"
	add_child(ch)
	var gris: String = "galva_pylone"
	var fornet: bool = style_tph == "fornet"
	# chariot (fiches RM.net) : deux porteurs par voie, une rangée de galets sur chacun — Fornet 24 galets
	# (12 par porteur), Grande Motte 12 (6 par porteur) et un frein par porteur, en amont des galets ; galets
	# par paires sur balanciers, joues de part et d'autre, poutre-caisson en travers des deux rangées,
	# attaches du tracteur aux deux bouts. Châssis rouge au Fornet (photos).
	var rg: float = 0.20 if fornet else 0.22
	var n_g: int = 12 if fornet else 6
	var pas: float = 0.40 if fornet else 0.52
	var lr: float = n_g * pas + 0.3                     # longueur d'une rangée
	var coul: String = "cabine_rouge" if fornet else gris
	var xr: float = E_PORTEURS_TPH * 0.5
	for sx in [-1.0, 1.0]:
		for sj in [-1.0, 1.0]:
			RemonteeKit.boite_en(ch, Vector3(0.03, 0.42, lr), Vector3(sx * xr + sj * 0.15, rg + 0.10, 0), coul)
		for k in range(n_g):
			RemonteeKit.galet(ch, Vector3(sx * xr, rg + PyloneRemontee.R_CABLE, (k - (n_g - 1) * 0.5) * pas), rg)
		for kb in range(n_g / 2):
			var zb: float = (2 * kb + 0.5 - (n_g - 1) * 0.5) * pas
			RemonteeKit.cylindre(ch, 0.05, 0.05, 0.36, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * xr, rg + 0.30, zb)), "acier_noir", 8)
		# frein de chariot : mâchoires sur le porteur, en amont
		RemonteeKit.boite_en(ch, Vector3(0.36, 0.30, 0.55), Vector3(sx * xr, rg * 0.5, -lr * 0.5 - 0.30), "peinture_anthracite")
	# poutre maîtresse entre les deux rangées (les galets restent visibles par-dessus, photos du Fornet)
	RemonteeKit.boite_en(ch, Vector3(0.24, 0.36, lr * 0.85), Vector3(0, rg + 0.12, 0), coul)
	for bz in [-1.0, 1.0]:
		RemonteeKit.boite_en(ch, Vector3(E_PORTEURS_TPH + 0.30, 0.22, 0.30), Vector3(0, 0.25, bz * lr * 0.30), coul)
		RemonteeKit.boite_en(ch, Vector3(0.24, 0.55, 0.34), Vector3(0, 0.08, bz * (lr * 0.5 + 0.15)), gris)
		RemonteeKit.cylindre(ch, 0.08, 0.08, 0.30, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.15, bz * (lr * 0.5 + 0.15))), "acier", 10)
	RemonteeKit.boite_en(ch, Vector3(0.05, 0.10, 0.12), Vector3(xr + 0.24, rg + 0.62, lr * 0.4), "cabine_rouge")       # feu
	var hs: float = H_SUSP_TPH
	if fornet:
		_suspente_fornet(hs)
	# suspente (photos) : grand bras gris en caisson qui monte d'un côté du
	# toit et se recourbe au-dessus du centre de la cabine jusqu'au chariot
	var p0: Vector3 = Vector3(0.0, 0.40, 0)
	var p1: Vector3 = Vector3(1.55, 0.30, 0)
	var p2: Vector3 = Vector3(1.10, -hs + 0.9, 0)
	var p3: Vector3 = Vector3(1.05, -hs + 0.05, 0)
	var arc_t: PackedVector3Array = PackedVector3Array()
	for k in range(25):
		var t: float = float(k) / 24.0
		var u: float = 1.0 - t
		arc_t.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	# caisson qui s'élargit vers le toit (photos)
	if not fornet:
		RemonteeKit.caisson(self, arc_t, 0.40, 0.55, 1.1, "acier", Vector3.BACK)
		RemonteeKit.boite_en(self, Vector3(0.9, 0.14, 1.6), Vector3(1.05, -hs - 0.02, 0), gris)
	# caisse
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hs - 0.08, 0)
	add_child(cab)
	var H: float = _h_cab(famille)
	var mailles: Dictionary = _maillage_cabine(famille, PANS_FORNET if fornet else teinte)
	for cle in ["coque", "vitres"]:
		var mc: MeshInstance3D = MeshInstance3D.new()
		mc.mesh = mailles[cle]
		cab.add_child(mc)
	for sz in [-1.0, 1.0]:
		var v: Node3D = Node3D.new()
		cab.add_child(v)
		for cle2 in ["porte_coque", "porte_vitre"]:
			var m2: MeshInstance3D = MeshInstance3D.new()
			m2.mesh = mailles[cle2 + ("_p" if sz > 0 else "_m")]
			v.add_child(m2)
		_portes.append([v, Vector3.ZERO, Vector3(0.06, 0, sz * 0.75)])
	# deux cabines différentes (fiche RM.net) : la n° 1 Swoboda 1993, toit et
	# liseré bleus, vitrage bleuté ; la n° 2 CWA Varos 2003, liseré gris
	# argent, vitrage sombre
	if numero == 2 or fornet:
		for mc2 in cab.get_children():
			if mc2 is MeshInstance3D and (mc2 as MeshInstance3D).mesh != null:
				var mm: Mesh = (mc2 as MeshInstance3D).mesh
				for k in range(mm.get_surface_count()):
					var ma: Material = mm.surface_get_material(k)
					if ma == null:
						continue
					if ma.resource_name == "remontee_cabine_bleue":
						(mc2 as MeshInstance3D).set_surface_override_material(k, RemonteeKit.mat("peinture_anthracite" if fornet else "peinture_gris"))
					elif ma.resource_name == "remontee_vitre_bleue":
						(mc2 as MeshInstance3D).set_surface_override_material(k, RemonteeKit.mat("vitre_teintee"))
	# meneaux des grandes vitres (trois en façade, cinq sur les côtés)
	# Fornet (photos) : bouts à trois pans (meneau à chaque arête), quatre baies sur une face, trois et la
	# porte sur l'autre
	if fornet:
		var ap: float = 1.52 - 0.16 - R_PANS_FORNET
		var bp: float = 2.80 - 0.16 - R_PANS_FORNET
		for sz5 in [-1.0, 1.0]:
			for sx5 in [-1.0, 1.0]:
				RemonteeKit.boite_en(cab, Vector3(0.07, 1.35, 0.07), Vector3(sx5 * ap, -0.95, sz5 * 2.80), "cabine_blanche")
				RemonteeKit.boite_en(cab, Vector3(0.07, 1.35, 0.07), Vector3(sx5 * 1.52, -0.95, sz5 * bp), "cabine_blanche")
		for zm in [-bp * 0.5, 0.0, bp * 0.5]:
			RemonteeKit.boite_en(cab, Vector3(0.04, 1.35, 0.06), Vector3(-1.52, -0.95, zm), "cabine_blanche")
		for zm2 in [-bp * 0.62]:
			RemonteeKit.boite_en(cab, Vector3(0.04, 1.35, 0.06), Vector3(1.52, -0.95, zm2), "cabine_blanche")
	for sz2 in ([] if fornet else [-1.0, 1.0]):
		for xm in [-0.5, 0.5]:
			RemonteeKit.boite_en(cab, Vector3(0.06, 1.35, 0.04), Vector3(xm, -0.95, sz2 * 2.80), "cabine_blanche")
	for sx2 in ([] if fornet else [-1.0, 1.0]):
		for k2 in range(-2, 3):
			if sx2 > 0.0 and absf(k2) < 1:
				continue          # baie de la porte
			RemonteeKit.boite_en(cab, Vector3(0.04, 1.35, 0.06), Vector3(sx2 * 1.52, -0.95, k2 * 0.95), "cabine_blanche")
	# Fornet (photos) : pas de garde-corps sur le toit, châssis rouge vif sous le plancher
	if fornet:
		RemonteeKit.boite_en(cab, Vector3(2.7, 0.14, 5.2), Vector3(0, -H - 0.07, 0), "cabine_rouge")
	# toit : plate-forme de service, garde-corps, trappe
	for sx3 in ([] if fornet else [-1.0, 1.0]):
		RemonteeKit.barre(cab, Vector3(sx3 * 1.30, 0.55, -2.55), Vector3(sx3 * 1.30, 0.55, 2.55), 0.025, "galva", 6)
		for k3 in range(6):
			var zz: float = -2.55 + k3 * 1.02
			RemonteeKit.barre(cab, Vector3(sx3 * 1.30, 0.0, zz), Vector3(sx3 * 1.30, 0.55, zz), 0.02, "galva", 6)
	RemonteeKit.boite_en(cab, Vector3(0.8, 0.06, 0.8), Vector3(-0.5, 0.03, -1.6), "galva_pylone")
	# intérieur : plancher, poste du conducteur à l'avant, barres de maintien
	var yp: float = -H + 0.12
	RemonteeKit.boite_en(cab, Vector3(2.85, 0.03, 5.4), Vector3(0, yp, 0), "noir_mat")
	RemonteeKit.boite_en(cab, Vector3(1.2, 1.0, 0.6), Vector3(-0.6, yp + 0.5, -2.35), "peinture_anthracite")
	RemonteeKit.boite_en(cab, Vector3(1.1, 0.04, 0.5), Vector3(-0.6, yp + 1.02, -2.35), "noir_mat")
	for k in range(5):
		var z: float = -1.8 + k * 0.9
		RemonteeKit.barre(cab, Vector3(-1.2, -0.45, z), Vector3(1.2, -0.45, z), 0.02, "acier", 6)
		RemonteeKit.barre(cab, Vector3(0, yp, z), Vector3(0, -0.45, z), 0.025, "acier", 6)
	# inscription sous les vitres, sur les quatre faces (photos)
	for f in [[Vector3(0, -2.05, 2.815), 0.0, 1.0], [Vector3(0, -2.05, -2.815), PI, 1.0], [Vector3(1.535, -2.05, -1.2), PI * 0.5, 0.8],
			[Vector3(-1.535, -2.05, 0.0), -PI * 0.5, 1.0]]:
		var l: MeshInstance3D = RemonteeKit.texte_fige(cab, "VAL D'ISÈRE" if fornet else "CAPITALE DU SKI D'ÉTÉ", 80,
			0.0032 * float(f[2]), Color(0.12, 0.25, 0.60) if fornet else Color(0.75, 0.10, 0.12))
		l.visibility_range_end = 120.0
		l.position = f[0]
		l.rotation.y = f[1]
		if miroir:
			l.scale = Vector3(-1, 1, 1)


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
static func _h_cab(fam: String) -> float:
	return {"cabine_3s": 2.30, "cabine_tph": 2.70}.get(fam, _CAB_H)


## Demi-largeur réduite de la baie de porte sur le côté X+ (−1…1 du côté).
static func _s_porte(fam: String) -> float:
	return 0.28 if fam == "cabine_tph" else 0.75


static func _profil_cabine(fam: String) -> Array:
	var anneaux: Array = []
	if fam == "cabine_tph":
		# cabine du téléphérique de la Grande Motte (Swoboda 1993, photos) :
		# grande caisse rectangulaire à angles peu arrondis, toit bleu, bandeau
		# de vitres sombres en haut, caisse blanche à liseré bleu, fond
		# légèrement rentré
		# (photos Commons « 2017-01 Grande Motte Tignes ») : caisse blanche presque
		# parallélépipédique, toit plat blanc, très grand vitrage bleuté sur
		# toute la hauteur utile, soubassement blanc portant l'inscription
		for c in [
			[0.00, 1.42, 2.70, 0.12, "toit"],
			[0.08, 1.50, 2.78, 0.16, "caisse"],
			[0.22, 1.52, 2.80, 0.16, "cadre"],
			[0.27, 1.52, 2.80, 0.16, "vitre"],
			[1.62, 1.52, 2.80, 0.16, "cadre"],
			[1.68, 1.52, 2.80, 0.16, "caisse"],
			[2.42, 1.50, 2.78, 0.16, "jupe"],
			[2.62, 1.40, 2.68, 0.14, "jupe"],
			[2.70, 1.30, 2.58, 0.12, ""],
		]:
			anneaux.append([-float(c[0]), c[1], c[2], c[3], c[4]])
		return anneaux
	if fam == "cabine_3s":
		# CWA Zeta du 3S de l'Olympique, aux mesures des photos (2,3 m de haut,
		# 2,9 m de large, décision d'utilisateur, 02/11/2026) : chapeau blanc, deux
		# grandes baies par face, numéro en bas de vitre, bas blanc (aigle et nom),
		# jupe inclinée en tôle perforée blanche qui se resserre sous le plancher
		for c in [
			# d,    a,    b,    r,    bande
			[0.00, 1.12, 1.07, 0.42, "toit"],
			[0.05, 1.33, 1.28, 0.52, "toit"],
			[0.11, 1.40, 1.35, 0.54, "cadre"],
			[0.18, 1.42, 1.37, 0.54, "vitre"],
			[0.78, 1.45, 1.40, 0.54, "vitre"],
			[1.24, 1.45, 1.40, 0.54, "cadre"],
			[1.30, 1.45, 1.40, 0.54, "caisse"],
			[1.84, 1.42, 1.37, 0.54, "liseré"],
			[1.88, 1.41, 1.36, 0.54, "jupe"],
			[2.16, 1.31, 1.06, 0.47, "jupe"],
			[2.30, 1.21, 0.92, 0.42, ""],
		]:
			anneaux.append([-float(c[0]), c[1], c[2], c[3], c[4]])
		return anneaux
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
## `pans` : coins coupés en un pan droit (bouts à trois pans) au lieu d'un arc, mêmes points.
static func _contour(a: float, b: float, r: float, pans: bool = false) -> Array:
	var out: Array = []
	# subdivisions fines aux bords de la baie de porte (s = ±0,75) et au
	# milieu (jonction des vantaux)
	var cotes: Array = [-1.0, -0.86, -0.75, -0.70, -0.40, -0.28, -0.23, -0.06, 0.0, 0.06, 0.23, 0.28, 0.40, 0.70, 0.75, 0.86]
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
		var th0: float = ca[c][2]
		for k in range(nc):
			var th: float = th0 + PI * 0.5 * float(k) / nc
			var q: Vector3 = Vector3(cx + r * cos(th), 0, cz + r * sin(th))
			if pans:
				var q0: Vector3 = Vector3(cx + r * cos(th0), 0, cz + r * sin(th0))
				var q1: Vector3 = Vector3(cx + r * cos(th0 + PI * 0.5), 0, cz + r * sin(th0 + PI * 0.5))
				q = q0.lerp(q1, float(k) / nc)
			out.append([q, false, 0.0, k == 3 or k == 4])
	return out


static var _cache_cabines: Dictionary = {}


## Couleurs : caisse (bas), cadre (pourtour noir), toit, liseré.
static func _mat_cabine(nom: String, fam: String, teinte_: String = "") -> Material:
	var cle: String = nom + "|" + fam + "|" + teinte_
	if _cache_cabines.has(cle):
		return _cache_cabines[cle]
	var base: String = nom
	match nom:
		"caisse":
			base = {"cabine_diamond": "cabine_noire", "cabine_symphony": "cabine_blanche", "cabine_3s": "cabine_blanche", "cabine_tph": "cabine_blanche"}.get(fam, "cabine_rouge")
		"jupe":
			base = "blanc_plaque"                # tôle perforée de la jupe
		"liseré":
			base = {"cabine_diamond": "acier", "cabine_symphony": "cabine_bleue", "cabine_3s": "cabine_noire", "cabine_tph": "cabine_bleue"}.get(fam, "cabine_rouge")
		"toit":
			base = "cabine_blanche" if fam == "cabine_tph" or fam == "cabine_3s" else "cabine_noire"
		"cadre":
			base = "cabine_noire"
		"vitre":
			base = {"cabine_tph": "vitre_bleue", "cabine_3s": "vitre_bleu_clair"}.get(fam, "vitre_teintee")
	if teinte_ == "noire" and (nom == "caisse" or nom == "liseré" or nom == "toit"):
		base = "cabine_noire"
	elif teinte_ == "gris" and nom == "liseré":
		base = "cabine_noire"
	var m: Material = RemonteeKit.mat(base)
	if nom != "vitre":
		# double face : on voit l'intérieur de la caisse à travers les vitres
		var m2: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		if teinte_ == "gris" and (nom == "caisse" or nom == "toit"):
			# gris métal (photos de Tovière et des Brévières)
			m2.albedo_color = Color(0.60, 0.62, 0.64)
			m2.metallic = 0.75
			m2.roughness = 0.30
		m = m2
	_cache_cabines[cle] = m
	return m


## Maillages (partagés par famille) de la caisse, de son vitrage et des deux
## vantaux : surfaces lissées par anneaux, bande par bande.
static func _maillage_cabine(fam: String, teinte_: String = "") -> Dictionary:
	var cle_m: String = fam + "#" + teinte_
	if _cache_cabines.has(cle_m):
		return _cache_cabines[cle_m]
	var prof: Array = _profil_cabine(fam)
	var H: float = _h_cab(fam)
	var y_haut_porte: float = -0.19 if fam != "cabine_3s" else -0.15
	var y_bas_porte: float = -H + 0.12
	var anneaux: Array = []
	var pans: bool = teinte_ == PANS_FORNET
	for r in prof:
		anneaux.append(_contour(r[1], r[2], r[3] + (R_PANS_FORNET if pans else 0.0), pans))
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
			var dans_baie: bool = a0[1] and a1[1] and absf(s_mid) < _s_porte(fam) and y0 <= y_haut_porte + 0.001 \
				and y1 >= y_bas_porte - 0.001
			if dans_baie:
				var cote: float = 1.0 if s_mid > 0.0 else -1.0
				var mp: String = "vitre" if y1 > -H + 0.45 else "cadre"
				# montants des vantaux : bords de la baie et jonction centrale
				if absf(s_mid) > _s_porte(fam) - 0.05 or absf(s_mid) < 0.06:
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
	res["coque"] = _assembler(st, fam, false, teinte_)
	res["vitres"] = _assembler(st, fam, true, teinte_)
	res["porte_coque_p"] = _assembler(st_porte[1.0], fam, false, teinte_)
	res["porte_vitre_p"] = _assembler(st_porte[1.0], fam, true, teinte_)
	res["porte_coque_m"] = _assembler(st_porte[-1.0], fam, false, teinte_)
	res["porte_vitre_m"] = _assembler(st_porte[-1.0], fam, true, teinte_)
	_cache_cabines[cle_m] = res
	return res


static func _assembler(dico: Dictionary, fam: String, vitres: bool, teinte_: String = "") -> ArrayMesh:
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
		MeshMerge.valider(copie, mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_cabine(mat, fam, teinte_))
	return mesh


## Skis du passager au porte-skis (cabines) : affichés sur le premier vantail.
func porte_skis(oui: bool) -> void:
	for k in range(_skis_ranges.size()):
		(_skis_ranges[k] as Node3D).visible = oui and k == 0


func portes(t: float) -> void:
	if t == _etat_anim[3]:
		return
	_etat_anim[3] = t
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
		_bras = Node3D.new()
		_bras.name = "Bras"
		add_child(_bras)
		_perche_tige = Node3D.new()
		_perche_tige.name = "Perche"
		_bras.add_child(_perche_tige)
		RemonteeKit.barre(_perche_tige, Vector3(0, -0.05, 0), Vector3(0, -1.7, 0), 0.026, "acier", 8)
		RemonteeKit.barre(_perche_tige, Vector3(0, -1.7, 0), Vector3(0, -3.4, 0), 0.020, "galva", 8)
		RemonteeKit.cylindre(_perche_tige, 0.035, 0.035, 0.30, Transform3D(Basis.IDENTITY, Vector3(0, -1.65, 0)), "acier_noir", 10)
		RemonteeKit.cylindre(_perche_tige, 0.13, 0.13, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -3.45, 0)), "jaune_securite", 18)
		return
	# enrouleur : pince fixe sur le câble, étrier en C qui le contourne par
	# l'extérieur (photo Commons « Tellerliftbügel »), boîtier à tambour
	RemonteeKit.boite_en(self, Vector3(0.12, 0.10, 0.26), Vector3(0, 0.08, 0), "galva")
	RemonteeKit.tube(self, RemonteeKit.arc(Vector3(0, 0.0, 0), Vector3.RIGHT, Vector3.UP, 0.13, -PI * 0.5, PI * 0.5, 10), 0.025, "acier_noir", 6)
	RemonteeKit.boite_en(self, Vector3(0.30, 0.42, 0.34), Vector3(0, -0.24, 0), "peinture_gris")
	RemonteeKit.cylindre(self, 0.15, 0.15, 0.32, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.24, 0)), "acier_noir", 18)
	# la corde et la perche pendent d'un bras articulé sous le tambour : tiré,
	# il s'incline vers le skieur, loin derrière la pince (vidéo du Montet :
	# corde et perche en biais, archet sous les fesses)
	_bras = Node3D.new()
	_bras.name = "Bras"
	_bras.position = Vector3(0, -0.45, 0)
	add_child(_bras)
	_corde = Node3D.new()
	_corde.name = "Corde"
	_bras.add_child(_corde)
	RemonteeKit.barre(_corde, Vector3.ZERO, Vector3(0, -1.0, 0), 0.008, "acier_noir", 6)
	_perche_tige = Node3D.new()
	_perche_tige.name = "Perche"
	_bras.add_child(_perche_tige)
	RemonteeKit.barre(_perche_tige, Vector3(0, 0, 0), Vector3(0, -1.10, 0), 0.02, "orange_perche", 8)
	if famille == "perche_tbar":
		# archet biplace (Montet) : barre cintrée en arc, le milieu plus bas
		# que les bouts (retour d'utilisateur, 25/10/2026 : « inverser la courbure de
		# l'archet »), garnie de caoutchouc là où l'on s'appuie
		var arc: PackedVector3Array = PackedVector3Array()
		for k in range(13):
			var u: float = lerpf(-1.0, 1.0, float(k) / 12.0)
			arc.append(Vector3(u * 0.52, -1.18 + 0.10 * u * u, 0))
		RemonteeKit.tube(_perche_tige, arc, 0.028, "noir_mat", 8)     # barre noire, manche orange (vidéo des Montets)
		for sx in [-1.0, 1.0]:
			var a: Vector3 = Vector3(sx * 0.20, -1.18 + 0.10 * 0.15, 0)
			var b: Vector3 = Vector3(sx * 0.50, -1.18 + 0.10 * 0.92, 0)
			RemonteeKit.barre(_perche_tige, a, b, 0.04, "caoutchouc", 10)
	else:
		RemonteeKit.cylindre(_perche_tige, 0.12, 0.12, 0.05, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -1.12, 0)), "assise_noire", 18)
	deroule(0.0)


## Enrouleur : 0 = corde rentrée (perche contre le boîtier), 1 = déroulée
## (skieur tracté, perche ~4 m sous le câble).
## Perche tirée jusqu'à `d` m sous la pince (rondelle ou barre au niveau
## des hanches du skieur tracté) ; d = 0 : perche au repos.
func longueur_perche(d: float) -> void:
	if _perche_tige == null:
		return
	if d <= 0.0 and _bras != null:
		_bras.rotation = Vector3.ZERO
	if famille == "perche_debrayable":
		var k: float = clampf(d / 3.45, 0.35, 2.4) if d > 0.0 else 1.0
		_perche_tige.scale = Vector3(1, k, 1)
		return
	deroule(0.0 if d <= 0.0 else (d - 0.45 - 1.12 - 0.25) / (3.6 - 0.25))


func deroule(t: float) -> void:
	if _corde == null:
		return
	var l: float = lerpf(0.25, 3.6, clampf(t, 0.0, 1.6))
	_corde.scale = Vector3(1, l, 1)
	_perche_tige.position = Vector3(0, -l, 0)


## Perche tendue vers `cible` (repère du véhicule) : la rondelle ou l'archet
## y arrive, corde et perche dans l'axe pince → cible.
var _bras: Node3D = null


func tendre_perche(cible: Vector3) -> void:
	if _bras == null:
		return
	var v: Vector3 = cible - _bras.position
	var dist: float = v.length()
	if dist < 0.1:
		return
	_bras.rotation = Vector3(-atan2(v.z, -v.y), 0.0, 0.0)
	if famille == "perche_debrayable":
		_perche_tige.scale = Vector3(1, clampf(dist / 3.45, 0.35, 2.4), 1)
	else:
		var l: float = clampf(dist - 1.15, 0.25, 6.0)
		_corde.scale = Vector3(1, l, 1)
		_perche_tige.position = Vector3(0, -l, 0)


# --- grandes cabines : 3S et téléphérique -----------------------------------------

## Chariot roulant sur les câbles porteurs (galets en ligne), suspente
## rigide, grande caisse. 3S : cabine CWA Zeta 30 places (24 assises),
## chariot de 2 × 4 galets sur DEUX porteurs, pince sur le tracteur.
## Téléphérique : cabine de 80-115 places avec poste du conducteur, chariot
## de 8 galets par porteur.
func _grande_cabine() -> void:
	if famille == "cabine_3s":
		_cabine_zeta()
		return
	if famille == "cabine_tph":
		_cabine_tph()
		return
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
