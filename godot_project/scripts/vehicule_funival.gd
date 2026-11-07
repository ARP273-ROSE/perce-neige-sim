class_name VehiculeFunival
extends VehiculeRemontee
## Véhicule du Funival (Cwa, « 272 + 1 pers., 21 840 kg ») d'après les photos du reportage remontees-mecaniques.net
## (fiche de cotes : _cuites/funival/FICHE_PHOTOS.md ; dimensions ESTIMÉES sur photo) : une longue caisse noire très
## vitrée, en gradins — chaque compartiment a son plancher horizontal, sa porte de chaque côté —, liseré rouge et
## blanc en bas, intérieur blanc à bandeau rouge et barres de maintien rouges.
##
## Repère : origine au dessus des rails, au milieu de la caisse ; −Z vers l'amont, Y perpendiculaire à la voie
## (le véhicule est incliné comme elle par la ligne).

const DEMI_L: float = 16.0              # longueur 30-34 m (estimé)
const DEMI_LARGEUR: float = 1.40        # largeur 2,7-2,9 m (estimé)
const N_COMP: int = 9                   # ~9 baies par flanc (estimé)
const PENTE_GRADINS: float = 0.45       # pente pour laquelle les planchers sont de niveau (tunnel 48 %, dehors 27 %)
const H_PLANCHER: float = 1.05          # plancher au milieu d'un compartiment, au-dessus des rails
const H_TOIT: float = 4.05              # toit, perpendiculairement à la voie
const L_PORTE: float = 1.0
const H_PORTE: float = 2.0

static var _mat_interieur: StandardMaterial3D = null


static func l_comp() -> float:
	return DEMI_L * 2.0 / float(N_COMP)


## Milieu (z) du compartiment k, 0 en bas (aval, +Z).
static func z_comp(k: int) -> float:
	return DEMI_L - l_comp() * (float(k) + 0.5)


static func compartiment(z: float) -> int:
	return clampi(int(floor((DEMI_L - z) / l_comp())), 0, N_COMP - 1)


## Hauteur du plancher (repère du véhicule) au droit de z : plan de niveau pour la pente des gradins.
static func y_plancher(z: float) -> float:
	var k: int = compartiment(z)
	return H_PLANCHER + (z - z_comp(k)) * PENTE_GRADINS


## Plancher du compartiment au droit de d, véhicule à quai (repère de la ligne) : pour les quais en gradins.
static func y_plancher_monde(lg: Funival, d: float) -> float:
	return lg.y_voie(d) + H_PLANCHER / sqrt(1.0 + pow(lg.pente_voie(d), 2.0))


func construire() -> void:
	for f in _phases():
		(f as Callable).call()


func construire_par_tranches(pause: Callable) -> void:
	for f in _phases():
		(f as Callable).call()
		await pause.call()


func _phases() -> Array:
	for c in get_children():
		c.queue_free()
	_portes.clear()
	cabine = true
	places = 272
	masse = 21840.0
	return [_caisse, _interieur, _portes_funi, func() -> void: MeshMerge.merge(self, _portes_noeuds(), "Funi")]


func _portes_noeuds() -> Array:
	var r: Array = []
	for p in _portes:
		r.append(p[0])
	return r


## Caisse : châssis, flancs vitrés à montants noirs, toit, bouts, liseré rouge et blanc.
func _caisse() -> void:
	var L: float = DEMI_L * 2.0
	var W: float = DEMI_LARGEUR
	RemonteeKit.boite_en(self, Vector3(1.9, 0.45, L - 1.0), Vector3(0, 0.30, 0), "acier_noir")           # châssis, bogies cachés
	RemonteeKit.boite_en(self, Vector3(2.0 * W, 0.35, L), Vector3(0, 0.62, 0), "cabine_noire")           # bas de caisse
	RemonteeKit.boite_en(self, Vector3(2.0 * W + 0.02, 0.06, L), Vector3(0, 0.84, 0), "rouge_val")        # liseré
	RemonteeKit.boite_en(self, Vector3(2.0 * W + 0.02, 0.04, L), Vector3(0, 0.76, 0), "cabine_blanche")
	var hv: float = H_TOIT - 0.9
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(self, Vector3(0.03, hv, L), Vector3(sx * (W - 0.02), 0.9 + hv * 0.5, 0), "vitre_teintee")
		for k in range(N_COMP + 1):
			var z: float = DEMI_L - l_comp() * float(k)
			RemonteeKit.boite_en(self, Vector3(0.08, hv, 0.10), Vector3(sx * W, 0.9 + hv * 0.5, z), "cabine_noire")
		RemonteeKit.boite_en(self, Vector3(0.08, 0.14, L), Vector3(sx * W, H_TOIT - 0.07, 0), "cabine_noire")
	# toit arrondi (deux pans et un faîte)
	for sx2 in [-1.0, 1.0]:
		RemonteeKit.boite(self, Vector3(W + 0.05, 0.08, L), Transform3D(Basis(Vector3.BACK, sx2 * 0.22),
			Vector3(sx2 * W * 0.5, H_TOIT + 0.12, 0)), "cabine_noire")
	# bouts : nez en dièdre vitré, montants noirs, numéro
	for sz in [-1.0, 1.0]:
		var z0: float = sz * DEMI_L
		for sx3 in [-1.0, 1.0]:
			RemonteeKit.boite(self, Vector3(W + 0.02, H_TOIT - 0.7, 0.04),
				Transform3D(Basis(Vector3.UP, sx3 * sz * 0.35), Vector3(sx3 * W * 0.48, 0.7 + (H_TOIT - 0.7) * 0.5, z0 + sz * 0.22)), "vitrage_sombre")
		RemonteeKit.boite_en(self, Vector3(0.10, H_TOIT - 0.7, 0.10), Vector3(0, 0.7 + (H_TOIT - 0.7) * 0.5, z0 + sz * 0.42), "cabine_noire")
		RemonteeKit.boite_en(self, Vector3(2.0 * W, 0.55, 0.5), Vector3(0, 0.62, z0 + sz * 0.2), "cabine_noire")


## Intérieur : planchers de niveau (caillebotis gris), cloisons blanches entre compartiments, plafond blanc à
## bandeau rouge, cadre de barres rouges au milieu de chaque compartiment.
func _interieur() -> void:
	if _mat_interieur == null:
		_mat_interieur = StandardMaterial3D.new()
		_mat_interieur.albedo_color = Color(0.93, 0.93, 0.92)
		_mat_interieur.roughness = 0.7
		_mat_interieur.cull_mode = BaseMaterial3D.CULL_DISABLED
	var a: float = -atan(PENTE_GRADINS)            # plancher de niveau dans le véhicule incliné
	var lc: float = l_comp()
	var W: float = DEMI_LARGEUR
	for k in range(N_COMP):
		var z: float = z_comp(k)
		var long_p: float = lc * sqrt(1.0 + PENTE_GRADINS * PENTE_GRADINS)
		RemonteeKit.boite(self, Vector3(2.0 * W - 0.1, 0.08, long_p), Transform3D(Basis(Vector3.RIGHT, a),
			Vector3(0, H_PLANCHER - 0.04, z)), "caillebotis")
		# cloison du compartiment côté amont, de son plancher au plancher suivant et jusqu'au toit
		var zc: float = z - lc * 0.5
		var y_bas: float = 0.8
		RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.1, H_TOIT - y_bas, 0.05), Vector3(0, y_bas + (H_TOIT - y_bas) * 0.5, zc), "cabine_blanche")
		# barres de maintien : deux poteaux et une lisse, rouges
		var yf: float = H_PLANCHER
		for sx in [-0.45, 0.45]:
			RemonteeKit.boite_en(self, Vector3(0.04, H_TOIT - 0.15 - yf, 0.04), Vector3(sx, yf + (H_TOIT - 0.15 - yf) * 0.5, z), "rouge_val")
		RemonteeKit.boite_en(self, Vector3(0.94, 0.04, 0.04), Vector3(0, yf + 1.9, z), "rouge_val")
	RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.1, 0.03, DEMI_L * 2.0), Vector3(0, H_TOIT - 0.06, 0), "cabine_blanche")
	RemonteeKit.boite_en(self, Vector3(0.5, 0.025, DEMI_L * 2.0), Vector3(0, H_TOIT - 0.09, 0), "rouge_val")


## Portes : un vantail vitré à cadre noir par compartiment et par côté, coulissant vers l'aval.
func _portes_funi() -> void:
	for sx in [-1.0, 1.0]:
		for k in range(N_COMP):
			var z: float = z_comp(k)
			var p: Node3D = Node3D.new()
			p.name = "Porte_%d_%d" % [k, int(sx)]
			add_child(p)
			var y0: float = y_plancher(z) + H_PORTE * 0.5
			RemonteeKit.boite_en(p, Vector3(0.05, H_PORTE, L_PORTE), Vector3.ZERO, "cabine_noire")
			RemonteeKit.boite_en(p, Vector3(0.06, H_PORTE - 0.2, L_PORTE - 0.16), Vector3.ZERO, "vitre_teintee")
			var ferme: Vector3 = Vector3(sx * (DEMI_LARGEUR + 0.03), y0, z)
			p.position = ferme
			_portes.append([p, ferme, Vector3(0, 0, L_PORTE * 0.95)])


## Debout au milieu du compartiment i, sur son plancher.
func place_assise(i: int = -1, _avant: bool = false) -> Vector3:
	var k: int = clampi(i if i >= 0 else 4, 0, N_COMP - 1)
	var z: float = z_comp(k)
	return Vector3(0.55, H_PLANCHER + 0.02, z)


func inclinaison(_a: float) -> void:
	pass


func balancer(_dt: float, _en_gare: bool) -> void:
	pass


## Formes de collision (repère du véhicule) : [taille, transformée, paroi à porte ?].
func formes_funi() -> Array:
	var r: Array = []
	var a: float = -atan(PENTE_GRADINS)
	var lc: float = l_comp()
	var long_p: float = lc * sqrt(1.0 + PENTE_GRADINS * PENTE_GRADINS)
	for k in range(N_COMP):
		var z: float = z_comp(k)
		r.append([Vector3(2.0 * DEMI_LARGEUR, 0.2, long_p), Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, H_PLANCHER - 0.1, z)), false])
		r.append([Vector3(2.0 * DEMI_LARGEUR, H_TOIT, 0.1), Transform3D(Basis.IDENTITY, Vector3(0, H_TOIT * 0.5, z - lc * 0.5)), false])
	for sx in [-1.0, 1.0]:
		r.append([Vector3(0.1, H_TOIT, DEMI_L * 2.0), Transform3D(Basis.IDENTITY, Vector3(sx * DEMI_LARGEUR, H_TOIT * 0.5, 0)), true])
	r.append([Vector3(2.0 * DEMI_LARGEUR, 0.2, DEMI_L * 2.0), Transform3D(Basis.IDENTITY, Vector3(0, H_TOIT + 0.1, 0)), false])
	return r
