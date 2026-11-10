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
const DEMI_LARGEUR: float = 1.075       # 2,15 m : croisement à ~0,2 m de jeu avec l'entraxe de 2,35 m de l'évitement
const N_COMP: int = 9                   # ~9 baies par flanc (estimé)
const PENTE_GRADINS: float = 0.30       # pente pour laquelle les planchers sont de niveau = pente en gare amont (utilisateur, 08/11/2026)
const H_PLANCHER: float = 1.05          # plancher au milieu d'un compartiment, au-dessus des rails
const H_TOIT: float = 3.65              # toit, perpendiculairement à la voie (2,6 m au-dessus du plancher : ok-36, ok-45, quai amont)
## Porte (photos de quai amont, ok-47) : vantail extérieur coulissant, posé devant la caisse, de la hauteur de la baie
## (linteau sous la gouttière) ; garé devant le panneau fixe vers l'amont.
const L_PORTE: float = 1.35
const H_PORTE: float = 2.10
const L_JAMBAGE: float = 0.10
## Section (ok-44, ok-45, nez_escalier_metal) : flancs rentrants au-dessus de la ceinture, gouttière, dos arrondi.
const Y_CEINTURE: float = 1.15          # plus grande largeur
const Y_GOUTTIERE: float = 3.17         # haut des flancs, gouttière inox
const RENTRE: float = 0.17              # le flanc rentre d'autant de la ceinture à la gouttière
## Nez (ok-44, ok-45, ok-46) : bombé en plan, fuyant en profil.
const NEZ_RECUL: float = 1.0            # recul du haut du nez
const NEZ_PLAN: float = 0.20            # recul des coins en plan
const Y_NEZ: float = 0.75               # le nez commence à fuir au-dessus
const Y_VITRE: float = 1.70             # bas des vitrages des flancs et des portes (le bas est noir, à vagues)
const Y_VITRE_NEZ: float = 1.32         # bas du pare-brise
## Intérieur (ok-50, ok-51) : pas de cloison ; un palier devant chaque porte, une volée de N_MARCHES marches entre deux
## paliers, cadres de barres rouges.
const L_PALIER: float = 1.6
const N_MARCHES: int = 5

static var _mat_coque: StandardMaterial3D = null
static var _mat_vitre: StandardMaterial3D = null


## Vitrage des flancs : sombre et peu réfléchissant, sans lumière ambiante (dans le tunnel, le vitrage clair des
## autres cabines prenait la lumière du ciel et voilait tout de blanc — captures du 08/11/2026).
static func vitre_funi() -> StandardMaterial3D:
	if _mat_vitre == null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = Color(0.06, 0.07, 0.08, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.2
		m.metallic_specular = 0.2
		m.disable_ambient_light = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_vitre = m
	return _mat_vitre


static func l_comp() -> float:
	return DEMI_L * 2.0 / float(N_COMP)


## Milieu (z) du compartiment k, 0 en bas (aval, +Z).
static func z_comp(k: int) -> float:
	return DEMI_L - l_comp() * (float(k) + 0.5)


static func compartiment(z: float) -> int:
	return clampi(int(floor((DEMI_L - z) / l_comp())), 0, N_COMP - 1)


## Hauteur du plancher (repère du véhicule) au droit de z : palier de niveau (pente des gradins) devant la porte,
## volée de marches (approchée par sa pente) jusqu'au palier voisin.
static func y_plancher(z: float) -> float:
	var k: int = compartiment(z)
	var dz: float = z - z_comp(k)
	var hp: float = L_PALIER * 0.5
	if absf(dz) <= hp or (dz > 0.0 and k == 0) or (dz < 0.0 and k == N_COMP - 1):
		return H_PLANCHER + dz * PENTE_GRADINS
	var bord: float = hp * PENTE_GRADINS
	var t: float = (absf(dz) - hp) / maxf(l_comp() - 2.0 * hp, 0.01)
	# vers l'amont (dz < 0), du bord bas de ce palier au bord haut du suivant ; vers l'aval, l'inverse
	return H_PLANCHER + (lerpf(-bord, bord, t) if dz < 0.0 else lerpf(bord, -bord, t))


## Demi-largeur du flanc à la hauteur y (jusqu'à la gouttière), puis du dos arrondi.
static func demi_l_y(y: float) -> float:
	if y <= Y_CEINTURE:
		return DEMI_LARGEUR
	var a_g: float = DEMI_LARGEUR - RENTRE
	if y <= Y_GOUTTIERE:
		return lerpf(DEMI_LARGEUR, a_g, (y - Y_CEINTURE) / (Y_GOUTTIERE - Y_CEINTURE))
	var t: float = clampf((y - Y_GOUTTIERE) / (H_TOIT - Y_GOUTTIERE), 0.0, 1.0)
	return a_g * sqrt(maxf(1.0 - t * t, 0.0))


## Recul du nez à la hauteur y (profil fuyant et bombé).
static func recul_nez(y: float) -> float:
	var t: float = clampf((y - Y_NEZ) / (H_TOIT - Y_NEZ), 0.0, 1.0)
	return NEZ_RECUL * pow(t, 1.6)


## Bout de la caisse (z) à la hauteur y ; u : position en travers (0 au milieu, ±1 aux coins).
static func z_bout(y: float, sz: float, u: float = 1.0) -> float:
	return sz * (DEMI_L - recul_nez(y) - NEZ_PLAN * u * u)


## Repère « de niveau » des gradins : un plan horizontal quand la voie a la pente PENTE_GRADINS (gare amont).
static func _niveau() -> Basis:
	return Basis(Vector3.RIGHT, -atan(PENTE_GRADINS))


## Centre du palier k dans le repère de niveau.
static func _palier_niv(k: int) -> Vector3:
	return _niveau().inverse() * Vector3(0, H_PLANCHER, z_comp(k))


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
	_roues.clear()
	cabine = true
	places = 272
	masse = 21840.0
	return [_caisse, _interieur, _portes_funi, _phares, func() -> void: MeshMerge.merge(self, _portes_noeuds() + _phares_l + _roues, "Funi")]


## Phares : un projecteur chaud à chaque nez (vidéos : parois très éclairées devant le véhicule), sans ombre.
var _phares_l: Array = []


func _phares() -> void:
	_phares_l.clear()
	for sz in [-1.0, 1.0]:
		var sp: SpotLight3D = SpotLight3D.new()
		sp.name = "Phare_amont" if sz < 0.0 else "Phare_aval"
		sp.light_color = Color(1.0, 0.94, 0.84)      # blanc légèrement chaud (l'ocre saturait la paroi)
		sp.light_energy = 3.5
		sp.spot_range = 60.0
		sp.spot_angle = 50.0
		sp.spot_attenuation = 1.0
		sp.shadow_enabled = false
		sp.visible = false
		# SpotLight3D éclaire vers son −Z : vers l'amont tel quel, vers l'aval retourné
		sp.transform = Transform3D(Basis.IDENTITY if sz < 0.0 else Basis(Vector3.UP, PI), Vector3(0, 1.4, sz * (DEMI_L + 1.0)))
		add_child(sp)
		_phares_l.append(sp)


## Allume le phare du côté amont (vers_amont) ou aval ; `oui` faux : éteints.
func phares(vers_amont: bool, oui: bool) -> void:
	if _phares_l.size() < 2:
		return
	(_phares_l[0] as Node3D).visible = oui and vers_amont
	(_phares_l[1] as Node3D).visible = oui and not vers_amont


func _portes_noeuds() -> Array:
	var r: Array = []
	for p in _portes:
		r.append(p[0])
	return r


## Angle d'inclinaison du flanc (entre la ceinture et la gouttière).
static func _th_flanc() -> float:
	return atan(RENTRE / (Y_GOUTTIERE - Y_CEINTURE))


## Vagues du bas de caisse (quai amont, ok-47) : blanche, grise et rouge, qui courent d'un bout à l'autre et se croisent.
static func y_vague(z: float, n: int) -> float:
	var ph: float = TAU * z / 7.11
	match n:
		0:
			return 1.34 + 0.20 * sin(ph + 0.4)
		1:
			return 1.20 + 0.15 * sin(ph + 1.7)
		_:
			return 1.16 + 0.27 * sin(ph + 2.7)


const VAGUES: Array = [["cabine_blanche", 0.075], ["galva", 0.045], ["rouge_val", 0.065]]


## Vagues posées par courts tronçons entre z0 et z1 (zc : abscisse locale de `parent` ; y0 : son origine en hauteur).
static func _vagues(parent: Node3D, b: Basis, x: float, z0: float, z1: float, zc: float, y0: float, y_max: float) -> void:
	var n: int = maxi(int(ceil((z1 - z0) / 0.28)), 1)
	for iv in range(VAGUES.size()):
		for j in range(n):
			var za: float = lerpf(z0, z1, float(j) / float(n))
			var zb: float = lerpf(z0, z1, float(j + 1) / float(n))
			var ya: float = minf(y_vague(za, iv), y_max)
			var yb: float = minf(y_vague(zb, iv), y_max)
			var lg: float = Vector2(zb - za, yb - ya).length()
			var pente: Basis = Basis(Vector3.RIGHT, -atan2(yb - ya, zb - za))
			RemonteeKit.boite(parent, Vector3(0.008, float(VAGUES[iv][1]), lg + 0.01),
				Transform3D(b * pente, Vector3(x, (ya + yb) * 0.5 - y0, (za + zb) * 0.5 - zc)), String(VAGUES[iv][0]))


## Profil d'une demi-section, de bas en haut.
static func _profil() -> Array:
	var prof: Array = [Vector2(DEMI_LARGEUR, 0.45), Vector2(DEMI_LARGEUR, Y_CEINTURE), Vector2(DEMI_LARGEUR - RENTRE, Y_GOUTTIERE)]
	var a_g: float = DEMI_LARGEUR - RENTRE
	var b_g: float = H_TOIT - Y_GOUTTIERE
	for a in range(1, 9):
		var ph: float = PI * 0.5 * float(a) / 8.0
		prof.append(Vector2(a_g * cos(ph), Y_GOUTTIERE + b_g * sin(ph)))
	return prof


## Intervalles des baies de porte sur z, triés : [zmin, zmax].
static func _baies() -> Array:
	var r: Array = []
	for k in range(N_COMP):
		r.append([z_comp(k) - L_PORTE * 0.5, z_comp(k) + L_PORTE * 0.5])
	r.sort_custom(func(u, v): return u[0] < v[0])
	return r


## Caisse (ok-44 à ok-47, quai amont) : flancs rentrants, gouttière inox, dos arrondi noir ; à chaque compartiment une baie
## de porte à jambages blancs et linteau rouge, puis un panneau fixe (vitrage haut, bas noir à vagues) devant lequel le
## vantail se gare ; nez bombé et fuyant, pare-brise cerclé de noir, grand aigle blanc sur le bas du nez.
func _caisse() -> void:
	var L: float = DEMI_L * 2.0
	var W: float = DEMI_LARGEUR
	var prof: Array = _profil()
	var noir: SurfaceTool = SurfaceTool.new()
	noir.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verre: SurfaceTool = SurfaceTool.new()
	verre.begin(Mesh.PRIMITIVE_TRIANGLES)
	# fond de caisse et deux bogies à roues Abt, comme au Perce-Neige (retour d'utilisateur du 11/11/2026 : « le dessous
	# de la rame c'est comme Perce-Neige avec des roues différentes en fonction de la rame », pas un caisson plein)
	RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.1, 0.06, L - 1.4), Vector3(0, Y_FOND, 0), "acier_noir")
	for zb in [-(DEMI_L - Z_BOGIE), DEMI_L - Z_BOGIE]:
		_bogie(zb)
	var th: float = _th_flanc()
	var baies: Array = _baies()
	for sx in [-1.0, 1.0]:
		var bf: Basis = Basis(Vector3.BACK, sx * th)
		# dos arrondi : d'un nez à l'autre
		for i in range(2, prof.size() - 1):
			var a0: Vector2 = prof[i]
			var a1: Vector2 = prof[i + 1]
			_quad(noir, Vector3(sx * a0.x, a0.y, z_bout(a0.y, 1.0)), Vector3(sx * a0.x, a0.y, z_bout(a0.y, -1.0)),
				Vector3(sx * a1.x, a1.y, z_bout(a1.y, -1.0)), Vector3(sx * a1.x, a1.y, z_bout(a1.y, 1.0)))
		# gouttière
		RemonteeKit.boite(self, Vector3(0.09, 0.05, L - 2.0 * (NEZ_RECUL * 0.8 + NEZ_PLAN)), Transform3D(bf,
			Vector3(sx * (demi_l_y(Y_GOUTTIERE) + 0.02), Y_GOUTTIERE + 0.02, 0)), "acier")
		# bas de caisse sous les seuils, sur toute la longueur
		_panneau(noir, sx, -INF, INF, 0.45, H_PLANCHER - 0.26)
		# liseré bas rouge et blanc
		RemonteeKit.boite_en(self, Vector3(0.01, 0.06, L - 0.5), Vector3(sx * (W + 0.006), 0.62, 0), "rouge_val")
		RemonteeKit.boite_en(self, Vector3(0.01, 0.04, L - 0.5), Vector3(sx * (W + 0.006), 0.54, 0), "cabine_blanche")
		var z_prec: float = -INF
		for c in baies + [[INF, INF]]:
			var za: float = z_prec
			var zb: float = float(c[0])
			# panneau fixe : bas noir, vitrage
			_panneau(noir, sx, za, zb, H_PLANCHER - 0.26, Y_VITRE)
			_panneau(verre, sx, za, zb, Y_VITRE, Y_GOUTTIERE)
			var z0p: float = maxf(za, z_bout(Y_VITRE, -1.0))
			var z1p: float = minf(zb, z_bout(Y_VITRE, 1.0))
			_vagues(self, Basis.IDENTITY, sx * (W + 0.006), z0p + 0.02, z1p - 0.02, 0.0, 0.0, Y_VITRE - 0.06)
			# doublure blanche sous les vitres
			RemonteeKit.boite(self, Vector3(0.04, Y_VITRE - H_PLANCHER + 0.26, z1p - z0p), Transform3D(Basis.IDENTITY,
				Vector3(sx * (W - 0.07), (Y_VITRE + H_PLANCHER - 0.26) * 0.5, (z0p + z1p) * 0.5)), "cabine_blanche")
			# cadres : traverses haute et basse, montant central du panneau
			var zmil: float = (z0p + z1p) * 0.5
			var lgp: float = z1p - z0p
			for yt in [Y_VITRE, Y_GOUTTIERE - 0.05]:
				RemonteeKit.boite(self, Vector3(0.05, 0.07, lgp), Transform3D(bf, Vector3(sx * demi_l_y(yt), yt, zmil)), "cabine_noire")
			if lgp > 1.2:
				_montant(sx, zmil, bf, 0.05)
			if c[0] != INF:
				var z0b: float = float(c[0])
				var z1b: float = float(c[1])
				# linteau noir, jambages noirs à dehors, blancs à dedans, seuil inox et plinthe à grille
				var yl: float = H_PLANCHER + H_PORTE
				_panneau(noir, sx, z0b, z1b, yl, Y_GOUTTIERE)
				for zj in [z0b, z1b]:
					_montant(sx, zj, bf, 0.11)
					RemonteeKit.boite(self, Vector3(0.16, H_PORTE + 0.30, L_JAMBAGE), Transform3D(bf,
						Vector3(sx * (demi_l_y(2.0) - 0.08), H_PLANCHER + (H_PORTE - 0.30) * 0.5, zj + signf((z0b + z1b) * 0.5 - zj) * 0.05)), "cabine_blanche")
				var zm_b: float = (z0b + z1b) * 0.5
				RemonteeKit.boite_en(self, Vector3(0.22, 0.03, z1b - z0b), Vector3(sx * (W - 0.05), H_PLANCHER - 0.25, zm_b), "acier")
				RemonteeKit.boite_en(self, Vector3(0.03, 0.24, z1b - z0b), Vector3(sx * (W - 0.02), H_PLANCHER - 0.38, zm_b), "acier")
				for ng in [-1.0, 1.0]:
					RemonteeKit.boite_en(self, Vector3(0.01, 0.13, 0.42), Vector3(sx * (W - 0.002), H_PLANCHER - 0.38, zm_b + ng * 0.33), "acier_noir")
				# linteau rouge à l'intérieur
				RemonteeKit.boite_en(self, Vector3(0.45, 0.05, z1b - z0b), Vector3(sx * (W - 0.32), yl - 0.03, zm_b), "rouge_val")
				z_prec = z1b
			else:
				z_prec = INF
	# nez : surface bombée en grille, vitrée au milieu
	const NU: int = 14
	for sz in [-1.0, 1.0]:
		for i in range(prof.size() - 1):
			var a0: Vector2 = prof[i]
			var a1: Vector2 = prof[i + 1]
			var ym: float = (a0.y + a1.y) * 0.5
			for j in range(NU):
				var u0: float = -1.0 + 2.0 * float(j) / float(NU)
				var u1: float = -1.0 + 2.0 * float(j + 1) / float(NU)
				var um: float = (u0 + u1) * 0.5
				var vitre: bool = absf(um) < 0.86 and ym > Y_VITRE_NEZ and ym < Y_GOUTTIERE + 0.12
				_quad(verre if vitre else noir,
					Vector3(a0.x * u0, a0.y, z_bout(a0.y, sz, u0)), Vector3(a0.x * u1, a0.y, z_bout(a0.y, sz, u1)),
					Vector3(a1.x * u1, a1.y, z_bout(a1.y, sz, u1)), Vector3(a1.x * u0, a1.y, z_bout(a1.y, sz, u0)))
		# bas du nez et butée
		# (sous l'aigle, en noir mat : brillante à 0,6 m, elle barrait l'aigle d'une bande grise vue de derrière)
		RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.1, 0.22, 0.25), Vector3(0, 0.50, sz * (DEMI_L - 0.15)), "acier_noir")
		# doublure blanche autour de la baie de tête (ok-48, ok-54) : allège, imposte et piédroits ; la vitre reste libre
		var z_d: float = sz * (DEMI_L - 0.92)
		# (plancher du palier de bout au droit de la doublure, dans le repère de la caisse : la hauteur du palier dans
		# le repère de niveau, prise telle quelle, montait l'allège à 4,9 m, au-dessus du toit — retour d'utilisateur du
		# 10/11/2026, « truc gris qui dépasse au-dessus de l'avant du wagon »)
		var cb0: Vector3 = _palier_niv(0 if sz > 0.0 else N_COMP - 1)
		var Rn: Basis = _niveau()
		var py: Vector3 = Rn * Vector3(0, cb0.y, 0)
		var pz: Vector3 = Rn * Vector3(0, 0, 1)
		var y_sol: float = py.y + (z_d - py.z) / pz.z * pz.y
		# (bas borné au-dessus du bas de caisse : le palier de bout est sous la caisse côté aval, l'allège descendait sous
		# les rails et faisait un panneau gris sous le nez, vu de derrière — retour d'utilisateur du 10/11/2026)
		var y_all: float = maxf(y_sol - 0.2, 0.55)
		RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.25, 1.40 - y_all, 0.04), Vector3(0, (1.40 + y_all) * 0.5, z_d), "cabine_blanche")
		RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.55, 0.22, 0.04), Vector3(0, 3.10, z_d), "cabine_blanche")
		for su in [-1.0, 1.0]:
			RemonteeKit.boite_en(self, Vector3(0.20, 1.60, 0.04), Vector3(su * (W - 0.24), 2.20, z_d), "cabine_blanche")
		# grand aigle blanc sur le bas du nez (ok-45, ok-46), dépassant sur le pare-brise
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(1.35, 1.35)
		mi.mesh = q
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.94, 0.94, 0.94)
		m.albedo_texture = VehiculeRemontee._aigle()
		# (bords lissés : en découpe nette, l'aigle de 128 px était déchiqueté)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ya: float = 1.18
		var ph2: float = atan2(recul_nez(ya + 0.3) - recul_nez(ya - 0.3), 0.6)
		var b_nez: Basis = (Basis.IDENTITY if sz > 0.0 else Basis(Vector3.UP, PI)) * Basis(Vector3.RIGHT, -ph2)
		mi.transform = Transform3D(b_nez, Vector3(0.0, ya, z_bout(ya, sz, 0.0) + sz * 0.05))
		mi.set_meta(MeshMerge.SANS_FUSION, true)
		add_child(mi)
	var mn: MeshInstance3D = MeshInstance3D.new()
	mn.name = "Coque"
	noir.generate_normals()
	mn.mesh = MeshMerge.commit_retenu(noir)
	if _mat_coque == null:
		_mat_coque = RemonteeKit.mat("cabine_noire").duplicate()
		_mat_coque.cull_mode = BaseMaterial3D.CULL_DISABLED
	mn.material_override = _mat_coque
	add_child(mn)
	var mv: MeshInstance3D = MeshInstance3D.new()
	mv.name = "Vitrages"
	verre.generate_normals()
	mv.mesh = MeshMerge.commit_retenu(verre)
	mv.material_override = vitre_funi()
	mv.set_meta(MeshMerge.SANS_FUSION, true)
	add_child(mv)


## Épaisseur d'un bloc du plancher (dessus à y_haut dans le repère de niveau, de z0 à z1) pour que son dessous reste
## au-dessus du fond de caisse dans le repère du véhicule ; au plus `maxi`, au moins 0,05 m.
static func _epaisseur_sur_fond(R: Basis, y_haut: float, z0: float, z1: float, maxi: float) -> float:
	var ky: float = (R * Vector3.UP).y
	var t: float = maxi
	for z in [z0, z1]:
		t = minf(t, ((R * Vector3(0, y_haut, z)).y - (Y_FOND + 0.03)) / ky)
	return clampf(t, 0.05, maxi)


## Bogie : longerons, traverse, deux essieux et leurs boîtes, quatre roues sur pivots (tournées par tourner_roues).
## Système Abt : le véhicule 1 (voie de gauche dans l'évitement) est guidé par ses roues de gauche, à double boudin
## sur le rail extérieur ; ses roues de droite sont des cylindres larges sans boudin qui passent l'aiguillage ;
## l'inverse pour le véhicule 2. La caisse n'est jamais retournée : le côté guidé ne change pas.
const R_ROUE: float = 0.30
const Z_BOGIE: float = 4.0               # centre du bogie depuis le bout de la caisse (estimé)
const Y_FOND: float = 0.45               # fond de caisse au-dessus des rails : bas des flancs (les roues montent dans la caisse)
var _roues: Array = []


func _bogie(zc: float) -> void:
	var y_ax: float = R_ROUE
	for sx in [-0.86, 0.86]:
		RemonteeKit.boite_en(self, Vector3(0.12, 0.18, 2.7), Vector3(sx, y_ax + 0.16, zc), "acier_noir")
	RemonteeKit.boite_en(self, Vector3(1.84, 0.20, 0.30), Vector3(0, y_ax + 0.20, zc), "acier_noir")
	var guide_gauche: bool = numero != 2
	var axe: Basis = Basis(Vector3.BACK, PI * 0.5)
	for dz in [-0.95, 0.95]:
		RemonteeKit.boite_en(self, Vector3(1.50, 0.08, 0.08), Vector3(0, y_ax, zc + dz), "acier")
		for sx in [-0.86, 0.86]:
			RemonteeKit.boite_en(self, Vector3(0.16, 0.24, 0.28), Vector3(sx, y_ax + 0.02, zc + dz), "acier_noir")
		for sx in [-1.0, 1.0]:
			var piv: Node3D = Node3D.new()
			piv.name = "Roue"
			piv.position = Vector3(sx * ECART_ROUES, y_ax, zc + dz)
			add_child(piv)
			_roues.append(piv)
			var ext: float = sx * 0.07
			if (sx < 0.0) == guide_gauche:
				# double boudin : bandage étroit entre deux flasques qui enserrent le rail
				RemonteeKit.cylindre(piv, R_ROUE, R_ROUE, 0.10, Transform3D(axe, Vector3.ZERO), "acier", 20)
				for fx in [-0.065, 0.065]:
					RemonteeKit.cylindre(piv, R_ROUE + 0.035, R_ROUE + 0.035, 0.025, Transform3D(axe, Vector3(fx, 0, 0)), "acier", 20)
			else:
				ext = sx * 0.13
				RemonteeKit.cylindre(piv, R_ROUE, R_ROUE, 0.24, Transform3D(axe, Vector3.ZERO), "acier", 20)
			# moyeu clair et barre radiale sur la face extérieure : une roue lisse qui tourne ne se voit pas
			RemonteeKit.cylindre(piv, 0.09, 0.09, 0.02, Transform3D(axe, Vector3(ext, 0, 0)), "galva", 12)
			RemonteeKit.boite_en(piv, Vector3(0.015, 2.0 * R_ROUE - 0.08, 0.05), Vector3(ext, 0, 0), "galva")
			MeshMerge.merge(piv, [], "Roue")
const ECART_ROUES: float = 0.60          # demi-écartement (voie de 1,20 m)


## Roues tournées de la distance parcourue d (m) le long de la voie.
func tourner_roues(d: float) -> void:
	for piv in _roues:
		(piv as Node3D).rotation.x = -d / R_ROUE


## Montant noir du flanc, de la ceinture de vitrage à la gouttière (bas compris si `large`).
func _montant(sx: float, z: float, bf: Basis, large: float) -> void:
	var y0: float = H_PLANCHER - 0.26
	var y1: float = Y_GOUTTIERE
	if z < z_bout(y1, -1.0) or z > z_bout(y1, 1.0):
		return
	RemonteeKit.boite(self, Vector3(0.06, y1 - y0, large), Transform3D(bf, Vector3(sx * demi_l_y((y0 + y1) * 0.5), (y0 + y1) * 0.5, z)), "cabine_noire")


## Quadrilatère (coque mince : matières sans face cachée, vue de dedans comme de dehors).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## Panneau du flanc sx entre za et zb (bornés par le nez), de y0 à y1, suivant le rentrant du flanc.
static func _panneau(st: SurfaceTool, sx: float, za: float, zb: float, y0: float, y1: float) -> void:
	var ys: Array = [y0, y1]
	if y0 < Y_CEINTURE and y1 > Y_CEINTURE:
		ys = [y0, Y_CEINTURE, y1]
	for i in range(ys.size() - 1):
		var ya: float = ys[i]
		var yb: float = ys[i + 1]
		var a0: float = maxf(za, z_bout(ya, -1.0))
		var a1: float = maxf(za, z_bout(yb, -1.0))
		var b0: float = minf(zb, z_bout(ya, 1.0))
		var b1: float = minf(zb, z_bout(yb, 1.0))
		if b0 - a0 < 0.01 and b1 - a1 < 0.01:
			continue
		var wa: float = demi_l_y(ya)
		var wb: float = demi_l_y(yb)
		_quad(st, Vector3(sx * wa, ya, a0), Vector3(sx * wa, ya, b0), Vector3(sx * wb, yb, b1), Vector3(sx * wb, yb, a1))


## Intérieur (ok-50 à ok-54, quai amont) : sans cloison — paliers et volées de marches gris acier ; à chaque palier, un
## cadre de barres rouges à deux poteaux et deux lisses, un arceau rouge dans chaque baie de porte, une lisse en long de
## chaque côté ; plafond blanc à bandeau lumineux, grands pans rouges sous le dos arrondi ; banquette de moquette grise
## dans chaque bout, sous la baie de tête ; extincteurs en housse rouge.
func _interieur() -> void:
	var R: Basis = _niveau()
	var W: float = DEMI_LARGEUR
	var lw: float = 2.0 * W - 0.1
	for k in range(N_COMP):
		var c: Vector3 = _palier_niv(k)
		var z0: float = c.z - L_PALIER * 0.5
		var z1: float = c.z + L_PALIER * 0.5
		if k == 0:
			z1 = c.z + l_comp() * 0.5
		if k == N_COMP - 1:
			z0 = c.z - l_comp() * 0.5
		# (épaisseur bornée au-dessus du fond de caisse : épais de 1 m et inclinés, paliers et marches sortaient sous la
		# caisse et la traversaient entre les bogies — retour d'utilisateur du 11/11/2026)
		var ep: float = _epaisseur_sur_fond(R, c.y, z0, z1, 1.0)
		RemonteeKit.boite(self, Vector3(lw, ep, z1 - z0), Transform3D(R, R * Vector3(0, c.y - ep * 0.5, (z0 + z1) * 0.5)), "caillebotis")
		if k + 1 < N_COMP:
			var e1: Vector3 = c + Vector3(0, 0, -L_PALIER * 0.5)
			var e2: Vector3 = _palier_niv(k + 1) + Vector3(0, 0, L_PALIER * 0.5)
			var mont: float = e2.y - e1.y
			var course: float = e1.z - e2.z
			for j in range(1, N_MARCHES + 1):
				var haut: float = e1.y + mont * float(j) / float(N_MARCHES)
				var zc: float = e1.z - course * (float(j) - 0.5) / float(N_MARCHES)
				var run: float = course / float(N_MARCHES)
				var h: float = _epaisseur_sur_fond(R, haut, zc - run * 0.5, zc + run * 0.5, haut - (e1.y - 1.0))
				RemonteeKit.boite(self, Vector3(lw, h, course / float(N_MARCHES) + 0.01),
					Transform3D(R, R * Vector3(0, haut - h * 0.5, zc)), "caillebotis")
				# nez de marche inox
				RemonteeKit.boite(self, Vector3(lw, 0.012, 0.05), Transform3D(R, R * Vector3(0, haut + 0.006, zc + course / float(N_MARCHES) * 0.5 - 0.03)), "acier")
		# cadre au bord amont du palier : deux poteaux du sol au plafond, lisses vers les flancs (passage au milieu)
		var e: Vector3 = c + Vector3(0, 0, -L_PALIER * 0.5 + 0.05)
		for sx in [-1.0, 1.0]:
			RemonteeKit.barre(self, R * (e + Vector3(sx * 0.38, 0.0, 0)), R * (e + Vector3(sx * 0.38, 2.25, 0)), 0.024, "rouge_val", 6)
			for hb in [1.05, 1.95]:
				RemonteeKit.barre(self, R * (e + Vector3(sx * 0.38, hb, 0)), R * (e + Vector3(sx * (W - 0.14), hb, 0)), 0.02, "rouge_val", 6)
			# arceau dans la baie de porte (ok-46, quai amont) : deux montants et un dessus arrondi, le côté aval de la baie
			var ax: float = sx * (W - 0.34)
			var zh0: float = c.z + L_PORTE * 0.5 - 0.10
			var zh1: float = c.z + 0.05
			var pts: Array = [Vector3(ax, 0.0, zh0), Vector3(ax, 0.95, zh0), Vector3(ax, 1.08, zh0 - 0.10), Vector3(ax, 1.12, zh0 - 0.26),
				Vector3(ax, 1.12, zh1 + 0.26), Vector3(ax, 1.08, zh1 + 0.10), Vector3(ax, 0.95, zh1), Vector3(ax, 0.0, zh1)]
			var cf: Vector3 = Vector3(0, c.y, 0)
			for ip in range(pts.size() - 1):
				RemonteeKit.barre(self, R * (cf + pts[ip]), R * (cf + pts[ip + 1]), 0.022, "rouge_val", 6)
		# extincteur en housse rouge, un compartiment sur trois (ok-52)
		if k % 3 == 1:
			RemonteeKit.boite(self, Vector3(0.22, 0.55, 0.26), Transform3D(R, R * (c + Vector3(-(W - 0.22), 0.30, -L_PALIER * 0.5 - 0.35))), "rouge_val")
	var long_i: float = DEMI_L * 2.0 - 2.0 * (NEZ_RECUL + NEZ_PLAN)
	# plafond : blanc, bandeau lumineux au milieu, pans rouges sous le dos arrondi, de chaque côté
	RemonteeKit.boite_en(self, Vector3(1.1, 0.03, long_i), Vector3(0, H_TOIT - 0.10, 0), "cabine_blanche")
	var lampe: MeshInstance3D = RemonteeKit.boite_en(self, Vector3(0.16, 0.02, long_i), Vector3(0, H_TOIT - 0.125, 0), "cabine_blanche")
	var ml: StandardMaterial3D = RemonteeKit.mat("cabine_blanche").duplicate()
	ml.emission_enabled = true
	ml.emission = Color(1.0, 0.97, 0.90)
	ml.emission_energy_multiplier = 1.4
	lampe.material_override = ml
	lampe.set_meta(MeshMerge.SANS_FUSION, true)
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite(self, Vector3(0.62, 0.03, long_i), Transform3D(Basis(Vector3.BACK, -sx * 0.52),
			Vector3(sx * (W - 0.46), H_TOIT - 0.34, 0)), "rouge_val")
		# lisse en long sous les vitres, de chaque côté
		# (le long de la caisse, pas de niveau : posée de niveau sur 29 m, elle sortait par le toit d'un bout et par le
		# plancher de l'autre — les deux longs traits rouges, retour d'utilisateur du 10/11/2026)
		RemonteeKit.boite_en(self, Vector3(0.04, 0.04, long_i), Vector3(sx * (W - 0.11), H_PLANCHER + 1.0, 0), "rouge_val")
	# banquettes de bout : assise et dossier en moquette grise, dos au nez (ok-54)
	for sz in [-1.0, 1.0]:
		var k2: int = 0 if sz > 0.0 else N_COMP - 1
		var cb: Vector3 = _palier_niv(k2)
		var zb: float = cb.z + sz * (l_comp() * 0.5 - 0.75)
		RemonteeKit.boite(self, Vector3(2.0 * W - 0.5, 0.42, 0.75), Transform3D(R, R * Vector3(0, cb.y + 0.21, zb)), "galva_sombre")
		RemonteeKit.boite(self, Vector3(2.0 * W - 0.5, 0.75, 0.10), Transform3D(R, R * Vector3(0, cb.y + 0.75, zb + sz * 0.42)), "galva_sombre")


## Portes (quai amont, ok-47) : vantail extérieur à cadre noir, posé devant la caisse ; bas noir à vagues, vitrage haut
## barré de deux traverses boulonnées, « Val d'Isère » et petit aigle entre elles ; il coulisse vers l'amont, devant le panneau fixe.
func _portes_funi() -> void:
	var W: float = DEMI_LARGEUR
	var th: float = _th_flanc()
	for sx in [-1.0, 1.0]:
		var b: Basis = Basis(Vector3.BACK, sx * th)
		for k in range(N_COMP):
			var z: float = z_comp(k)
			var p: Node3D = Node3D.new()
			p.name = "Porte_%d_%d" % [k, int(sx)]
			add_child(p)
			var hl: float = H_PORTE * 0.5
			var ll: float = L_PORTE * 0.5
			var y_ctr: float = H_PLANCHER + hl
			var yv: float = Y_VITRE - y_ctr              # bas du vitrage, repère du vantail
			# cadre
			for zm in [-ll + 0.035, ll - 0.035]:
				RemonteeKit.boite_en(p, Vector3(0.05, H_PORTE, 0.07), Vector3(0, 0, zm), "cabine_noire")
			RemonteeKit.boite_en(p, Vector3(0.05, 0.08, L_PORTE), Vector3(0, hl - 0.04, 0), "cabine_noire")
			RemonteeKit.boite_en(p, Vector3(0.05, 0.08, L_PORTE), Vector3(0, yv, 0), "cabine_noire")
			# bas noir et vagues (continues avec celles des panneaux, porte fermée)
			RemonteeKit.boite_en(p, Vector3(0.03, yv + hl, L_PORTE - 0.04), Vector3(0, (yv - hl) * 0.5, 0), "cabine_noire")
			_vagues(p, Basis.IDENTITY, sx * 0.02, z - ll + 0.05, z + ll - 0.05, z, y_ctr, Y_VITRE - 0.08)
			# vitrage, traverses boulonnées
			var hv: float = hl - 0.08 - yv
			var ymv: float = (hl - 0.08 + yv) * 0.5
			var v: MeshInstance3D = RemonteeKit.boite_en(p, Vector3(0.015, hv, L_PORTE - 0.12), Vector3(0, ymv, 0), "vitre")
			v.material_override = vitre_funi()
			v.set_meta(MeshMerge.SANS_FUSION, true)
			var y_tr: Array = [yv + hv * 0.36, yv + hv * 0.67]
			for yt in y_tr:
				RemonteeKit.boite_en(p, Vector3(0.035, 0.04, L_PORTE - 0.10), Vector3(sx * 0.012, yt, 0), "cabine_noire")
				for zb in [-ll + 0.10, ll - 0.10]:
					RemonteeKit.boite_en(p, Vector3(0.012, 0.025, 0.025), Vector3(sx * 0.035, yt, zb), "acier")
			var lab: MeshInstance3D = RemonteeKit.texte_fige(p, "Val d'Isère", 64, 0.0026, Color(0.93, 0.93, 0.93))
			lab.transform = Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * 0.035, (y_tr[0] + y_tr[1]) * 0.5, 0))
			lab.visibility_range_end = 50.0
			lab.set_meta(MeshMerge.SANS_FUSION, true)
			MeshMerge.merge(p, [v, lab], "Porte")
			var y_x: float = demi_l_y(y_ctr)
			var ferme: Vector3 = Vector3(sx * (y_x + 0.07), y_ctr, z)
			p.basis = b
			p.position = ferme
			_portes.append([p, ferme, Vector3(0, 0, -(L_PORTE + 0.04))])


## Debout au milieu du compartiment i, sur son plancher.
func place_assise(i: int = -1, _avant: bool = false) -> Vector3:
	var k: int = clampi(i if i >= 0 else 4, 0, N_COMP - 1)
	var z: float = z_comp(k)
	return Vector3(0.55, H_PLANCHER + 0.02, z)


func inclinaison(_a: float) -> void:
	pass


func balancer(_dt: float, _en_gare: bool) -> void:
	pass


## Formes de collision (repère du véhicule) : [taille, transformée, paroi à porte ?]. Paliers et rampes (une par
## volée, par-dessus les marches) épais de 0,6 m vers le bas : la caisse est déplacée à chaque image, un plancher
## mince se faisait traverser (iPad, 08/11/2026).
func formes_funi() -> Array:
	var r: Array = []
	var R: Basis = _niveau()
	var W: float = DEMI_LARGEUR
	var ep: float = 0.6
	for k in range(N_COMP):
		var c: Vector3 = _palier_niv(k)
		var z0: float = c.z - L_PALIER * 0.5
		var z1: float = c.z + L_PALIER * 0.5
		if k == 0:
			z1 = c.z + l_comp() * 0.5
		if k == N_COMP - 1:
			z0 = c.z - l_comp() * 0.5
		r.append([Vector3(2.0 * W, ep, z1 - z0), Transform3D(R, R * Vector3(0, c.y - ep * 0.5, (z0 + z1) * 0.5)), false])
		if k + 1 < N_COMP:
			var e1: Vector3 = c + Vector3(0, 0, -L_PALIER * 0.5)
			var e2: Vector3 = _palier_niv(k + 1) + Vector3(0, 0, L_PALIER * 0.5)
			var th: float = atan2(e2.y - e1.y, e1.z - e2.z)
			var bt: Basis = Basis(Vector3.RIGHT, th)
			var n: Vector3 = bt * Vector3.UP
			var m: Vector3 = (e1 + e2) * 0.5 - n * (ep * 0.5)
			r.append([Vector3(2.0 * W, ep, e1.distance_to(e2) + 0.2), Transform3D(R * bt, R * m), false])
	for sx in [-1.0, 1.0]:
		r.append([Vector3(0.1, H_TOIT, DEMI_L * 2.0), Transform3D(Basis.IDENTITY, Vector3(sx * DEMI_LARGEUR, H_TOIT * 0.5, 0)), true])
	for sz in [-1.0, 1.0]:
		r.append([Vector3(2.0 * W, H_TOIT, 0.2), Transform3D(Basis.IDENTITY, Vector3(0, H_TOIT * 0.5, sz * (DEMI_L - NEZ_RECUL * 0.5))), false])
	r.append([Vector3(2.0 * DEMI_LARGEUR, 0.2, DEMI_L * 2.0), Transform3D(Basis.IDENTITY, Vector3(0, H_TOIT + 0.1, 0)), false])
	return r
