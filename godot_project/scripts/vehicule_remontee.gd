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
var _galets_roul: Array = []      # galets du chariot du 3S (axe local X)
const R_GALET_CHARIOT: float = 0.17


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
func _ready() -> void:
	if not _construit:
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
const REFS: Array = ["_machoire", "_levier", "_gc", "_bulle", "_susp", "_pince", "_corde", "_perche_tige", "_bras"]
const LISTES: Array = ["_ressorts", "_galets_roul", "_skis_ranges"]
const VALEURS: Array = ["places", "cabine", "pivot", "masse", "longueur_pendule", "_gc_releve", "_ressort_l0", "_etat_anim"]


## Modèles libérés en quittant le jeu.
static func vider_modeles() -> void:
	for k in _modeles:
		((_modeles[k] as Array)[0] as Node).free()
	_modeles.clear()


func _type() -> String:
	return "%s|%s|%s" % [famille, str(miroir), livree]


func construire() -> void:
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
		return
	_fabriquer()
	_modeles[cle] = _modele()


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


## Fabrication complète (le premier véhicule de chaque variante).
func _fabriquer() -> void:
	_ressorts.clear()
	_galets_roul.clear()
	_portes.clear()
	_skis_ranges.clear()
	_etat_anim = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
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
		masse = 2950.0 if famille == "cabine_3s" else (9000.0 if famille == "cabine_tph" else 850.0)
		longueur_pendule = 3.6 if famille == "cabine_3s" else (5.0 if famille == "cabine_tph" else 2.3)
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
	for g in _galets_roul:
		garder.append(g)
	for p in _portes:
		garder.append(p[0])
	if _pince != null:
		MeshMerge.merge(_pince, garder, "Pince", true)
	MeshMerge.merge(_susp, garder, "Vehicule", true)
	for n in garder:
		MeshMerge.merge(n, _skis_ranges, "Piece", true)      # skis rangés : affichés à la demande
	for n in _skis_ranges:
		MeshMerge.merge(n, [], "Skis", true)
	# pièces de détail, invisibles de loin (audit de fluidité, 26/10/2026 : 36 000
	# objets à dessiner au pied des pistes, 7 sur 10 par siège sont ces pièces) ;
	# les portes et la bulle restent : sans elles, la cabine serait trouée
	for n in [_machoire, _levier, _gc] + _ressorts + _galets_roul + _skis_ranges:
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
	# gaines noires aux deux bouts : demi-cônes ouverts par-dessous, le
	# GRAND diamètre accroché à la pince et la pointe vers l'extérieur
	# (retours d'utilisateur, 23/10/2026) — la pince passe mieux sous les
	# galets de compression des pylônes
	for sz in [-1.0, 1.0]:
		RemonteeKit.demi_cone(p, Vector3(0, 0, sz * L * 0.5), Vector3(0, 0, sz * (L * 0.5 + 0.34)), 0.055, 0.0245, "noir_mat", 12)
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
	var bmf: bool = constructeur() == "bartholet"
	if rc == "rouge_ressort" and not bmf:
		rc = "ressort_gris"          # Doppelmayr récents : ressorts gris (rouges = ET/A108 anciens)
	# (ressorts plus courts : la plaque de friction, au-dessus, reste au plus
	# près du câble, et les pneus du lanceur aussi — retour d'utilisateur, 22/10/2026)
	var l_r: float = Y_PLAQUE - 0.022 - 0.025 - 0.22
	for sz in [-1.0, 1.0]:
		for sx in ([0.0] if bmf else [-0.045, 0.045]):
			var r: Node3D = Node3D.new()
			r.position = Vector3(0.28 + sx, 0.22, sz * 0.15)
			p.add_child(r)
			if bmf:
				# un seul gros ressort à genouillère, spires serrées
				RemonteeKit.ressort(r, Vector3.ZERO, Vector3.UP, l_r, 0.062, 0.014, 9, rc)
			else:
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
	# (plus de numéro sur la plaque : vus de loin, ces petits textes flottaient
	# à côté des pinces — retour d'utilisateur, 25/10/2026 : « numéros fantômes »)


## Numéro lisible À L'ENDROIT : une étiquette d'un seul côté (vue de dos,
## elle s'effaçait en miroir — retour d'utilisateur, 23/10/2026), contre-
## inversée sur les véhicules en miroir ; `rot` oriente sa face (autour de Y).
func _numero(parent: Node3D, texte: String, pos: Vector3, rot: float, taille: int, px: float, coul: Color) -> void:
	# maillage de texte (TextMesh), partagé par texte et taille, fusionné avec
	# le véhicule : des centaines de Label3D qui bougent coûtaient ~25 ms par
	# image au pied de Solaise
	var cle: String = "%s|%d|%.4f" % [texte, taille, px]
	if not _textes.has(cle):
		var tm: TextMesh = TextMesh.new()
		tm.text = texte
		tm.font_size = taille
		tm.pixel_size = px
		tm.depth = 0.0
		tm.curve_step = 2.0
		_textes[cle] = tm
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _textes[cle]
	mi.material_override = _mat_texte(coul)
	mi.position = pos
	mi.rotation.y = rot
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
					img.set_pixel(i, j, Color(0.05, 0.05, 0.06, 1.0))
					break
	img.generate_mipmaps()
	_tex_aigle = ImageTexture.create_from_image(img)
	return _tex_aigle


## Panneau sous les vitres : [demi-largeur x, demi-longueur z, y] (repère de la caisse).
static func _dims_panneau(fam: String, H: float) -> Array:
	var a: float = 0.0
	var b: float = 0.0
	var y: float = -H * 0.70
	for r in _profil_cabine(fam):
		a = maxf(a, float(r[1]))
		b = maxf(b, float(r[2]))
		if String(r[4]) == "caisse":
			y = float(r[0]) - 0.30
	return [a, b, y]


func _logo_station(cab: Node3D, a: float, b: float, y: float, face_portes: float) -> void:
	if livree != "Val d'Isère":
		return
	var t: float = clampf(a * 0.35, 0.30, 0.55)          # côté de l'aigle
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _aigle()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(t, t)
	# face sans portes (x opposé) : aigle et nom côte à côte
	var fx: float = -face_portes
	var rot: float = fx * PI * 0.5
	var ai: MeshInstance3D = MeshInstance3D.new()
	ai.mesh = q
	ai.material_override = m
	ai.position = Vector3(fx * (a + 0.012), y, -fx * b * 0.42)
	ai.rotation.y = rot
	if miroir:
		ai.scale = Vector3(-1, 1, 1)
	ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cab.add_child(ai)
	_numero(cab, "Val d'Isère", Vector3(fx * (a + 0.012), y - 0.02, fx * b * 0.16), rot, 64, t * 0.0062, Color(0.05, 0.05, 0.06))
	# faces avant et arrière : le nom
	for sz in [-1.0, 1.0]:
		_numero(cab, "Val d'Isère", Vector3(0, y, sz * (b + 0.012)), 0.0 if sz > 0.0 else PI, 64, t * 0.0055, Color(0.05, 0.05, 0.06))


static var _textes: Dictionary = {}
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
	if _levier != null:
		_levier.rotation.z = -0.55 * clampf(t, 0.0, 1.0)
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
		return H_SUSP_3S + 0.08 + 2.80 - 0.22 + Machinerie3S.H_QUAI
	if fam.begins_with("cabine"):
		return 1.15 + 0.10 + 2.25 - 0.07 + 0.02
	if fam.begins_with("perche"):
		return 4.2          # rondelle à ~2,4 m du sol, perche rentrée
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
	if famille == "cabine_tph":
		# debout, au milieu de la cabine (on tient la barre)
		var yp2: float = -H_SUSP_TPH - 0.08 - 2.70 + 0.12
		var zi: float = (clampf(float(i if i >= 0 else 2), 0.0, 4.0) - 2.0) * 1.0
		return Vector3(0.6, yp2, zi)
	if famille == "cabine_3s":
		# banquettes de 6 places face à face (z = ±0,95), plancher 0,20 m
		# au-dessus du bas de la caisse
		var yp: float = -H_SUSP_3S - 0.08 - 2.80 + 0.22
		var xi: float = (clampf(float(i if i >= 0 else 2), 0.0, 5.0) - 2.5) * 0.45
		var zs: float = 1.06 - 0.42
		return Vector3(xi, yp + 0.44 + 0.045 - 0.45, -zs if avant else zs)
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
		var yb: float = -H_SUSP_3S - 0.08 - 2.80 + 0.22
		f.append([Vector3(2.9, 0.15, 2.8), Vector3(0, yb - 0.075, 0), false])           # plancher
		f.append([Vector3(2.9, 0.10, 2.8), Vector3(0, -H_SUSP_3S - 0.10, 0), false])    # toit
		f.append([Vector3(2.9, 2.45, 0.06), Vector3(0, yb + 1.22, -1.44), false])
		f.append([Vector3(2.9, 2.45, 0.06), Vector3(0, yb + 1.22, 1.44), false])
		f.append([Vector3(0.06, 2.45, 2.8), Vector3(-cote_ext * 1.50, yb + 1.22, 0), false])
		f.append([Vector3(0.06, 2.45, 2.8), Vector3(cote_ext * 1.50, yb + 1.22, 0), true])     # côté portes
		f.append([Vector3(2.7, 0.42, 0.40), Vector3(0, yb + 0.21, 1.09), false])
		f.append([Vector3(2.7, 0.42, 0.40), Vector3(0, yb + 0.21, -1.09), false])
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
	var x_att: float = 0.30 if not fixe else x0 + 0.10
	var y_att: float = 0.14 if not fixe else 0.02
	pivot = Vector3(x_att, y_att, 0)
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
	var x_att: float = 0.30 if not fixe else 0.17      # bras de la pince, ou monopince
	var y_att: float = 0.14 if not fixe else 0.02
	pivot = Vector3(x_att, y_att, 0)
	# siège à bulle (Lanches) : arceau à ~1,55 m au-dessus de l'assise (vidéos
	# de la ligne), la bulle ouverte se loge dessous → poutre remontée
	var dp: float = 0.55 if famille.ends_with("_bulle") else 0.0
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(x_att, y_att, 0))
	pts.append(Vector3(0.44, y_att - 0.06, 0))
	pts.append(Vector3(0.50, -0.30, 0))
	pts.append(Vector3(0.50, -hs + 0.75 + dp, 0))
	for p in RemonteeKit.arc(Vector3(0.12, -hs + 0.75 + dp, 0), Vector3.RIGHT, Vector3.DOWN, 0.38, 0.0, PI * 0.5, 8):
		pts.append(p)
	pts.append(Vector3(0.02, -hs + 0.12 + dp, 0.0))
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
	RemonteeKit.boite_en(siege, Vector3(2.0 * plein_c, hp, ep), Vector3(0, (yb0 + yb1) * 0.5, zb), m_alu)
	for sx in [-1.0, 1.0]:
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
	RemonteeKit.coussin(siege, Vector3(W - 0.02, dossier_h + 0.06, 0.05), Transform3D(t_dos, Vector3(0, y_dos, 0.245)), "coque_siege", 0.022)
	var couleurs: Array = _couleurs_assise()
	for i in range(places):
		var cx: float = -W * 0.5 + 0.10 + 0.50 * (i + 0.5)
		var coul: String = couleurs[i % couleurs.size()]
		var a: MeshInstance3D = RemonteeKit.coussin(siege, Vector3(0.48, 0.085, 0.48),
			Transform3D(t_assise, Vector3(cx, -0.975, -0.08)), coul, 0.035)
		a.name = "Assise%d" % i
		RemonteeKit.coussin(siege, Vector3(0.48, dossier_h, 0.08), Transform3D(t_dos, Vector3(cx, y_dos, 0.20)), coul, 0.035)
	# attaches du dossier sous la poutre
	for sx in [-1.0, 1.0]:
		RemonteeKit.barre(siege, Vector3(sx * W * 0.25, yb0, zb), Vector3(sx * W * 0.25, y_dos + dossier_h * 0.5, 0.25), 0.028, m_alu, 8)
	_garde_corps(siege, W, m_alu)


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
		"siege_doppelmayr_e98_6", "siege_doppelmayr_e98_8":
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
	for k in range(places / 2):
		var cx: float = -W * 0.5 + 0.10 + 1.0 * (k + 0.5)
		# une seule tige, légèrement coudée, de la barre au repose-pieds
		RemonteeKit.tube(_gc, PackedVector3Array([Vector3(cx, ventre.y, ventre.z), Vector3(cx, (ventre.y + pied.y) * 0.5, ventre.z - 0.10),
			Vector3(cx, pied.y, pied.z)]), 0.017, m, 6)
		# patin en T : traverse et semelle caoutchouc, pour deux paires de skis
		RemonteeKit.poutre(_gc, Vector3(cx - 0.40, pied.y, pied.z), Vector3(cx + 0.40, pied.y, pied.z), 0.05, 0.025, m)
		RemonteeKit.boite_en(_gc, Vector3(0.78, 0.02, 0.13), Vector3(cx, pied.y + 0.02, pied.z + 0.01), "caoutchouc")


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
## 0 ») : 2,50 m de large ; de profil une coque en « D » (corde moyeu → bord
## 1,37 m, flèche 0,73 m, courbure serrée près du moyeu, plus plate vers le
## bord) ; de face un rectangle aux coins arrondis, extrémités en calottes
## bombées, face avant presque verticale et toit presque plat ; fermée,
## sommet à ~1,0 m au-dessus de l'assise et bord ~0,12 m
## dessous ; moyeu de chaque côté à ~0,25 m au-dessus de l'assise, à
## l'aplomb du dossier ; elle bascule de 90° vers l'ARRIÈRE et se loge
## au-dessus et derrière le dossier. Bandeau bas sombre de 0,35 m portant
## une plaque blanche « TIGNES » (rouge) au milieu et un carré blanc au
## logo bleu à chaque bout, deux sangles noires de préhension ;
## polycarbonate fumé gris.
var _bulle_l: float = 2.50           # largeur hors tout (2,50 m mesurés ; selon le siège)
const BULLE_CORDE: float = 1.00      # moyeu → bord du bandeau (1,37 mesurés : trop longue vers l'avant, retour d'utilisateur 28/10/2026)
const BULLE_FLECHE: float = 0.90     # bombé maxi, perpendiculaire à la corde
const BULLE_INCL: float = 0.38       # corde fermée : 22° sous l'horizontale (bord ~0,12 m sous l'assise)
const BULLE_BANDEAU: float = 0.35


## Point de la coque (repère de la bulle : moyeu à l'origine, bulle fermée) ;
## s : de 0 (moyeu) à 1 (bord du bandeau) ; t : de -1 à 1 sur la largeur.
func _bulle_point(s: float, t: float) -> Vector3:
	var c: Vector2 = Vector2(-cos(BULLE_INCL), -sin(BULLE_INCL))      # (z, y)
	var n: Vector2 = Vector2(-sin(BULLE_INCL), cos(BULLE_INCL))       # bombé : vers le haut et l'avant
	# profil en « D » plein (superellipse) : flancs raides au moyeu et à la face
	# avant, toit presque plat — la bulle fermée est une « boîte » arrondie
	var f: float = pow(maxf(0.0, 1.0 - pow(absf(2.0 * s - 1.0), 3.0)), 1.0 / 3.0)
	# calottes : la flèche tombe à zéro aux extrémités (superellipse)
	var k: float = pow(maxf(0.0, 1.0 - pow(absf(t), 4.0)), 0.25)
	var p: Vector2 = c * (s * BULLE_CORDE) + n * (BULLE_FLECHE * f * k)
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
		var tm: TextMesh = TextMesh.new()
		tm.text = e[0]
		tm.font_size = e[2]
		tm.pixel_size = e[3]
		tm.depth = 0.0
		var mt: MeshInstance3D = MeshInstance3D.new()
		mt.mesh = tm
		mt.material_override = _mat_texte(e[4])
		# le texte regarde le long de la normale, à l'endroit (axe x de la bulle)
		var z_: Vector3 = nrm
		var x_: Vector3 = Vector3.UP.cross(z_).normalized() if absf(z_.y) < 0.95 else Vector3.RIGHT
		var bs_: Basis = Basis(x_, z_.cross(x_), z_)
		mt.transform = Transform3D(bs_, p0 + nrm * 0.012 - bs_.y * (0.0 if e[0] == "TIGNES" else 0.06))
		# plaque blanche sous le texte (centre : 0,60 × 0,22 ; bouts : carré 0,28)
		var pl: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.60, 0.22, 0.008) if e[0] == "TIGNES" else Vector3(0.28, 0.26, 0.008)
		pl.mesh = bm
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
	var dp: Array = _dims_panneau(famille, H)
	_logo_station(cab, dp[0], dp[1], dp[2], 1.0)
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
const E_PORTEURS_3S: float = 0.62
const Y_TRACTEUR_3S: float = -0.42
const H_SUSP_3S: float = 2.15        # du chariot au toit de la cabine


## Véhicule du 3S de l'Olympique (photos de la ligne, reportage
## remontees-mecaniques.net) : chariot de 2×4 galets alu sur balanciers bleus,
## un train par câble porteur ; pince du tracteur au milieu, sous eux, avec
## ses ressorts ; suspente unique en caisson gris foncé, coudée ; cabine
## CWA Zeta 30 places (24 assises), portes coulissantes côté quai.
func _cabine_zeta() -> void:
	# le chariot roule sur les porteurs (nœud « Pince », fixe) ; suspente et
	# cabine balancent autour de l'articulation, sous le longeron
	pivot = Vector3(0, 0.30, 0)
	var ch: Node3D = Node3D.new()
	ch.name = "Pince"
	add_child(ch)
	var gris: String = "peinture_anthracite"
	var e: float = E_PORTEURS_3S * 0.5
	var rg: float = 0.17                       # rayon des galets (gorge)
	var pas: float = 0.42
	# châssis du chariot : longeron central, deux poutres de balanciers
	RemonteeKit.boite_en(ch, Vector3(0.30, 0.20, 2.0), Vector3(0, 0.36, 0), gris)
	for sx in [-1.0, 1.0]:
		var x: float = sx * e
		# deux balanciers par câble (2 galets chacun) sur un palonnier
		for bz in [-1.0, 1.0]:
			var piv: Vector3 = Vector3(x, rg + 0.10, bz * pas)
			RemonteeKit.boite_en(ch, Vector3(0.05, 0.10, pas + 0.18), piv + Vector3(sx * 0.10, 0.02, 0), "bleu_ressort")
			RemonteeKit.boite_en(ch, Vector3(0.05, 0.10, pas + 0.18), piv + Vector3(-sx * 0.10, 0.02, 0), "bleu_ressort")
			for gz in [-0.5, 0.5]:
				# chaque galet sur son axe : il tourne en roulant sur le porteur
				# (retour d'utilisateur, 25/10/2026)
				var gn: Node3D = Node3D.new()
				gn.name = "GaletChariot"
				gn.position = Vector3(x, rg + PyloneRemontee.R_CABLE, bz * pas + gz * pas)
				ch.add_child(gn)
				RemonteeKit.galet(gn, Vector3.ZERO, rg)
				_galets_roul.append(gn)
			RemonteeKit.cylindre(ch, 0.03, 0.03, 0.26, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), piv), "acier", 8)
			# étiquette rouge (contrôle des galets, photos)
			RemonteeKit.boite_en(ch, Vector3(0.012, 0.07, 0.10), piv + Vector3(sx * 0.13, 0.10, 0), "cabine_rouge")
		RemonteeKit.boite_en(ch, Vector3(0.10, 0.12, 1.9), Vector3(x + sx * 0.14, 0.36, 0), gris)
		RemonteeKit.boite_en(ch, Vector3(sx * 0.14 + 0.08, 0.10, 0.20), Vector3(x * 0.5 + sx * 0.07, 0.36, 0), gris)
	# pince du tracteur, sous les porteurs, avec ses ressorts et ses gaines
	RemonteeKit.boite_en(ch, Vector3(0.16, 0.20, 0.70), Vector3(0, Y_TRACTEUR_3S + 0.06, 0), "alu_pince")
	for sz in [-1.0, 1.0]:
		RemonteeKit.demi_cone(ch, Vector3(0, Y_TRACTEUR_3S, sz * 0.35), Vector3(0, Y_TRACTEUR_3S, sz * 0.62), 0.05, 0.028, "noir_mat", 12)
		var r: Node3D = Node3D.new()
		r.position = Vector3(0, Y_TRACTEUR_3S + 0.16, sz * 0.20)
		ch.add_child(r)
		RemonteeKit.ressort(r, Vector3.ZERO, Vector3.UP, 0.30, 0.055, 0.012, 8, "ressort_gris")
		_ressorts.append(r)
	RemonteeKit.boite_en(ch, Vector3(0.16, 0.40, 0.20), Vector3(0, (Y_TRACTEUR_3S + 0.36) * 0.5 + 0.12, 0), gris)
	# galets de roulement de gare, de part et d'autre
	for sx in [-1.0, 1.0]:
		for sz in [-0.7, 0.7]:
			RemonteeKit.cylindre(ch, 0.09, 0.09, 0.07, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.62, 0.36, sz)), "polyurethane", 16)
	# suspente : caisson rectangulaire coudé, du chariot (au-dessus de
	# l'axe) au toit — elle s'écarte vers l'extérieur pour laisser passer les
	# porteurs, puis revient au-dessus du centre de la cabine
	var hs: float = H_SUSP_3S
	var arc: PackedVector3Array = PackedVector3Array()
	var q0: Vector3 = Vector3(0.0, 0.42, 0)
	var q1: Vector3 = Vector3(0.95, 0.40, 0)
	var q2: Vector3 = Vector3(0.95, -hs + 0.30, 0)
	var q3: Vector3 = Vector3(0.0, -hs + 0.05, 0)
	var arc_z: PackedVector3Array = PackedVector3Array()
	for k in range(21):
		var t: float = float(k) / 20.0
		var u: float = 1.0 - t
		arc_z.append(q0 * u * u * u + q1 * 3.0 * u * u * t + q2 * 3.0 * u * t * t + q3 * t * t * t)
	RemonteeKit.caisson(self, arc_z, 0.22, 0.30, 0.30, gris, Vector3.BACK)
	RemonteeKit.boite_en(self, Vector3(0.50, 0.12, 0.70), Vector3(0, -hs - 0.02, 0), gris)
	# caisse
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hs - 0.08, 0)
	add_child(cab)
	var H: float = _h_cab(famille)
	var mailles: Dictionary = _maillage_cabine(famille)
	for cle in ["coque", "vitres"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = cle.capitalize()
		mi.mesh = mailles[cle]
		cab.add_child(mi)
	var dp: Array = _dims_panneau(famille, H)
	_logo_station(cab, dp[0], dp[1], dp[2], 1.0)
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
	RemonteeKit.boite_en(cab, Vector3(2.60, 0.03, 2.50), Vector3(0, yp, 0), "noir_mat")
	for sz in [-1.0, 1.0]:
		for i in range(6):
			var xi: float = (i - 2.5) * 0.45
			RemonteeKit.coussin(cab, Vector3(0.42, 0.09, 0.44), Transform3D(Basis.IDENTITY, Vector3(xi, yp + 0.44, sz * 1.06)), "cabine_rouge" if i % 2 == 0 else "assise_grise", 0.035)
			RemonteeKit.coussin(cab, Vector3(0.42, 0.50, 0.07), Transform3D(Basis(Vector3.RIGHT, sz * 0.10), Vector3(xi, yp + 0.80, sz * 1.31)), "cabine_rouge" if i % 2 == 0 else "assise_grise", 0.03)
		RemonteeKit.boite_en(cab, Vector3(2.60, 0.40, 0.38), Vector3(0, yp + 0.20, sz * 1.08), "noir_mat")
	for sx in [-0.5, 0.5]:
		RemonteeKit.barre(cab, Vector3(sx, yp, 0.30), Vector3(sx, -0.30, 0.30), 0.02, "acier", 8)
		RemonteeKit.barre(cab, Vector3(sx, yp, -0.30), Vector3(sx, -0.30, -0.30), 0.02, "acier", 8)
	RemonteeKit.barre(cab, Vector3(-0.5, -0.30, 0.30), Vector3(0.5, -0.30, 0.30), 0.02, "acier", 8)
	RemonteeKit.barre(cab, Vector3(-0.5, -0.30, -0.30), Vector3(0.5, -0.30, -0.30), 0.02, "acier", 8)
	# numéro dans le cadre noir, sur les quatre faces
	var no: String = "%d" % numero
	for f in [[Vector3(0, -0.11, 1.46), 0.0], [Vector3(0, -0.11, -1.46), PI], [Vector3(1.52, -0.11, 0.55), PI * 0.5],
			[Vector3(-1.52, -0.11, 0.0), -PI * 0.5]]:
		_numero(cab, no, f[0], f[1], 56, 0.0020, Color(1, 1, 1))


## Téléphérique va-et-vient de la Grande Motte (Von Roll 1975, cabine Swoboda
## 1993 ; photos du reportage remontees-mecaniques.net) : chariot de 8 galets
## en deux bogies sur le câble porteur, attaches du tracteur aux deux bouts ;
## grande suspente pleine en coin ; cabine de 115 + 1 places (6,4 × 3,0 m),
## poste du conducteur à l'avant, barres de maintien, portes au milieu.
const H_SUSP_TPH: float = 4.6


func _cabine_tph() -> void:
	pivot = Vector3(0, 0.0, 0)
	var ch: Node3D = Node3D.new()
	ch.name = "Pince"
	add_child(ch)
	var gris: String = "galva_pylone"
	var rg: float = 0.22
	# chariot : poutre-caisson, deux bogies de 4 galets (2 balanciers de 2)
	# sur le porteur, joues latérales, attaches du tracteur aux deux bouts
	RemonteeKit.boite_en(ch, Vector3(0.44, 0.34, 4.6), Vector3(0, 0.62, 0), gris)
	for bz in [-1.0, 1.0]:
		var zb: float = bz * 1.20
		for sx in [-1.0, 1.0]:
			RemonteeKit.boite_en(ch, Vector3(0.03, 0.44, 2.0), Vector3(sx * 0.16, rg + 0.10, zb), "galva_patine")
		for k in range(4):
			RemonteeKit.galet(ch, Vector3(0, rg + PyloneRemontee.R_CABLE, zb + (k - 1.5) * 0.48), rg)
		RemonteeKit.cylindre(ch, 0.06, 0.06, 0.46, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.50, zb)), "acier_noir", 10)
		RemonteeKit.boite_en(ch, Vector3(0.24, 0.55, 0.34), Vector3(0, 0.08, bz * 2.35), gris)
		RemonteeKit.cylindre(ch, 0.08, 0.08, 0.30, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.15, bz * 2.35)), "acier", 10)
	RemonteeKit.boite_en(ch, Vector3(0.05, 0.10, 0.12), Vector3(0.24, 0.84, 2.0), "cabine_rouge")       # feu
	# suspente (photos) : grand bras gris en caisson qui monte d'un côté du
	# toit et se recourbe au-dessus du centre de la cabine jusqu'au chariot
	var hs: float = H_SUSP_TPH
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
	RemonteeKit.caisson(self, arc_t, 0.40, 0.55, 1.1, "acier", Vector3.BACK)
	RemonteeKit.boite_en(self, Vector3(0.9, 0.14, 1.6), Vector3(1.05, -hs - 0.02, 0), gris)
	# caisse
	var cab: Node3D = Node3D.new()
	cab.name = "Caisse"
	cab.position = Vector3(0, -hs - 0.08, 0)
	add_child(cab)
	var H: float = _h_cab(famille)
	var mailles: Dictionary = _maillage_cabine(famille)
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
	if numero == 2:
		for mc2 in cab.get_children():
			if mc2 is MeshInstance3D and (mc2 as MeshInstance3D).mesh != null:
				var mm: Mesh = (mc2 as MeshInstance3D).mesh
				for k in range(mm.get_surface_count()):
					var ma: Material = mm.surface_get_material(k)
					if ma == null:
						continue
					if ma.resource_name == "remontee_cabine_bleue":
						(mc2 as MeshInstance3D).set_surface_override_material(k, RemonteeKit.mat("peinture_gris"))
					elif ma.resource_name == "remontee_vitre_bleue":
						(mc2 as MeshInstance3D).set_surface_override_material(k, RemonteeKit.mat("vitre_teintee"))
	# meneaux des grandes vitres (trois en façade, cinq sur les côtés)
	for sz2 in [-1.0, 1.0]:
		for xm in [-0.5, 0.5]:
			RemonteeKit.boite_en(cab, Vector3(0.06, 1.35, 0.04), Vector3(xm, -0.95, sz2 * 2.80), "cabine_blanche")
	for sx2 in [-1.0, 1.0]:
		for k2 in range(-2, 3):
			if sx2 > 0.0 and absf(k2) < 1:
				continue          # baie de la porte
			RemonteeKit.boite_en(cab, Vector3(0.04, 1.35, 0.06), Vector3(sx2 * 1.52, -0.95, k2 * 0.95), "cabine_blanche")
	# toit : plate-forme de service, garde-corps, trappe
	for sx3 in [-1.0, 1.0]:
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
		var l: Label3D = Label3D.new()
		l.text = "CAPITALE DU SKI D'ÉTÉ"
		l.visibility_range_end = 120.0
		l.font_size = 80
		l.pixel_size = 0.0032 * float(f[2])
		l.modulate = Color(0.75, 0.10, 0.12)
		l.outline_size = 0
		l.double_sided = false
		l.position = f[0]
		l.rotation.y = f[1]
		if miroir:
			l.scale = Vector3(-1, 1, 1)
		cab.add_child(l)


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
	return {"cabine_3s": 2.80, "cabine_tph": 2.70}.get(fam, _CAB_H)


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
		# CWA Zeta du 3S de l'Olympique (photos de la ligne), agrandie de 12 %
		# (retour d'utilisateur, 25/10/2026 : « cabines trop petites » ; 30 places dont
		# 24 assises ≈ 7,5 m² de plancher) : caisse presque
		# carrée aux angles très arrondis, toit plat noir, grand vitrage
		# panoramique de 1,1 m, bandeau blanc (logo), jupe inclinée en tôle
		# perforée blanche qui se resserre sous le plancher
		for c in [
			# d,    a,    b,    r,    bande
			[0.00, 1.23, 1.18, 0.45, "toit"],
			[0.06, 1.43, 1.38, 0.56, "toit"],
			[0.15, 1.50, 1.44, 0.58, "cadre"],
			[0.24, 1.52, 1.47, 0.58, "vitre"],
			[0.88, 1.55, 1.49, 0.58, "vitre"],
			[1.50, 1.55, 1.49, 0.58, "cadre"],
			[1.56, 1.55, 1.49, 0.58, "caisse"],
			[2.22, 1.52, 1.47, 0.58, "liseré"],
			[2.27, 1.51, 1.46, 0.58, "jupe"],
			[2.64, 1.41, 1.14, 0.50, "jupe"],
			[2.81, 1.30, 0.99, 0.45, ""],
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
static func _contour(a: float, b: float, r: float) -> Array:
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
			base = {"cabine_diamond": "cabine_noire", "cabine_symphony": "cabine_blanche", "cabine_3s": "cabine_blanche", "cabine_tph": "cabine_blanche"}.get(fam, "cabine_rouge")
		"jupe":
			base = "blanc_plaque"                # tôle perforée de la jupe
		"liseré":
			base = {"cabine_diamond": "acier", "cabine_symphony": "cabine_bleue", "cabine_3s": "cabine_noire", "cabine_tph": "cabine_bleue"}.get(fam, "cabine_rouge")
		"toit":
			base = "cabine_blanche" if fam == "cabine_tph" else "cabine_noire"
		"cadre":
			base = "cabine_noire"
		"vitre":
			base = {"cabine_tph": "vitre_bleue", "cabine_3s": "vitre_bleu_clair"}.get(fam, "vitre_teintee")
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
	var H: float = _h_cab(fam)
	var y_haut_porte: float = -0.19 if fam != "cabine_3s" else -0.22
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
		MeshMerge.valider(copie, mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat_cabine(mat, fam))
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
