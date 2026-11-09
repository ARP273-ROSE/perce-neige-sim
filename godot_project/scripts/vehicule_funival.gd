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
const H_TOIT: float = 4.05              # toit, perpendiculairement à la voie
const L_PORTE: float = 1.2              # vantail vitré (photos de quai : ~1,2 m, estimé)
const H_PORTE: float = 2.3
## Section (photos ok-44, ok-45 et quai amont) : flancs droits, épaule arrondie de R_EPAULE, toit plat ; nez en face
## unique inclinée vers l'arrière de NEZ_RECUL entre le haut du bas de caisse et le toit, vitrée sur presque toute sa
## hauteur (on voit devant depuis la caisse — remarque d'utilisateur du 09/11/2026).
const R_EPAULE: float = 0.55
const NEZ_RECUL: float = 1.0
const Y_VITRE: float = 1.1              # bas des vitrages (dessus du bas de caisse noir)
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


## Bout de la caisse (z) à la hauteur y : nez incliné vers l'arrière au-dessus du bas de caisse.
static func z_bout(y: float, sz: float) -> float:
	var t: float = clampf((y - (Y_VITRE - 0.1)) / (H_TOIT - (Y_VITRE - 0.1)), 0.0, 1.0)
	return sz * (DEMI_L - NEZ_RECUL * t)


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
	cabine = true
	places = 272
	masse = 21840.0
	return [_caisse, _interieur, _portes_funi, _phares, func() -> void: MeshMerge.merge(self, _portes_noeuds() + _phares_l, "Funi")]


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


## Caisse : châssis, bas de caisse noir à liseré rouge et blanc, flancs vitrés à montants noirs (le vitrage s'arrête
## au droit des portes), épaules arrondies et toit plat noirs, nez incliné vitré, grand aigle.
func _caisse() -> void:
	var L: float = DEMI_L * 2.0
	var W: float = DEMI_LARGEUR
	RemonteeKit.boite_en(self, Vector3(1.9, 0.45, L - 1.0), Vector3(0, 0.30, 0), "acier_noir")           # châssis, bogies cachés
	RemonteeKit.boite_en(self, Vector3(2.0 * W + 0.02, 0.06, L - 0.1), Vector3(0, 0.84, 0), "rouge_val")  # liseré
	RemonteeKit.boite_en(self, Vector3(2.0 * W + 0.02, 0.04, L - 0.1), Vector3(0, 0.76, 0), "cabine_blanche")
	# profil d'une demi-section, de bas en haut (x, y)
	var prof: Array = [Vector2(W, 0.45), Vector2(W, Y_VITRE), Vector2(W, H_TOIT - R_EPAULE)]
	for a in range(1, 7):
		var th: float = PI * 0.5 * float(a) / 6.0
		prof.append(Vector2(W - R_EPAULE + R_EPAULE * cos(th), H_TOIT - R_EPAULE + R_EPAULE * sin(th)))
	prof.append(Vector2(0.0, H_TOIT))
	var noir: SurfaceTool = SurfaceTool.new()
	noir.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verre: SurfaceTool = SurfaceTool.new()
	verre.begin(Mesh.PRIMITIVE_TRIANGLES)
	# coque : chaque segment du profil balayé d'un bout à l'autre (sauf les flancs vitrés, posés par compartiment)
	for sx in [-1.0, 1.0]:
		for i in range(prof.size() - 1):
			var a0: Vector2 = prof[i]
			var a1: Vector2 = prof[i + 1]
			if i == 1:
				continue
			_quad(noir, Vector3(sx * a0.x, a0.y, z_bout(a0.y, 1.0)), Vector3(sx * a0.x, a0.y, z_bout(a0.y, -1.0)),
				Vector3(sx * a1.x, a1.y, z_bout(a1.y, -1.0)), Vector3(sx * a1.x, a1.y, z_bout(a1.y, 1.0)))
		# flancs vitrés : coupés au droit de chaque porte (vitrage au-dessus seulement)
		var y0: float = Y_VITRE
		var y1: float = H_TOIT - R_EPAULE
		var coupes: Array = []
		for k in range(N_COMP):
			coupes.append([z_comp(k) - L_PORTE * 0.5, z_comp(k) + L_PORTE * 0.5])
		coupes.sort_custom(func(u, v): return u[0] < v[0])
		var z_prec: float = -INF
		for c in coupes + [[INF, INF]]:
			var za: float = z_prec
			var zb: float = float(c[0])
			_flanc(verre, sx, za, zb, y0, y1)
			if c[0] != INF:
				var yh: float = H_PLANCHER + H_PORTE + 0.05
				_flanc(verre, sx, float(c[0]), float(c[1]), yh, y1)
				# montants du cadre de la baie de porte
				for zm in [float(c[0]), float(c[1])]:
					RemonteeKit.boite_en(self, Vector3(0.07, y1 - y0, 0.07), Vector3(sx * W, (y0 + y1) * 0.5, zm), "cabine_noire")
			z_prec = float(c[1])
		# montants entre compartiments, lisse haute sous l'épaule
		for k in range(1, N_COMP):
			var z: float = DEMI_L - l_comp() * float(k)
			RemonteeKit.boite_en(self, Vector3(0.07, y1 - y0, 0.07), Vector3(sx * W, (y0 + y1) * 0.5, z), "cabine_noire")
		RemonteeKit.boite_en(self, Vector3(0.08, 0.10, L - 2.0 * NEZ_RECUL), Vector3(sx * W, y1, 0), "cabine_noire")
	# nez : face inclinée, bas noir, vitrage jusque sous le toit, cadre noir
	for sz in [-1.0, 1.0]:
		for i in range(prof.size() - 1):
			var a0: Vector2 = prof[i]
			var a1: Vector2 = prof[i + 1]
			var ym: float = (a0.y + a1.y) * 0.5
			var st: SurfaceTool = verre if (ym > Y_VITRE and ym < H_TOIT - 0.3) else noir
			_quad(st, Vector3(-a0.x, a0.y, z_bout(a0.y, sz)), Vector3(a0.x, a0.y, z_bout(a0.y, sz)),
				Vector3(a1.x, a1.y, z_bout(a1.y, sz)), Vector3(-a1.x, a1.y, z_bout(a1.y, sz)))
		var phi: float = atan(NEZ_RECUL / (H_TOIT - Y_VITRE + 0.1))
		var b_nez: Basis = (Basis.IDENTITY if sz > 0.0 else Basis(Vector3.UP, PI)) * Basis(Vector3.RIGHT, -phi)
		# cadre : montant central et traverse basse
		var ym2: float = (Y_VITRE + H_TOIT - 0.3) * 0.5
		RemonteeKit.boite(self, Vector3(0.08, (H_TOIT - 0.3 - Y_VITRE) / cos(phi), 0.06),
			Transform3D(b_nez, Vector3(0, ym2, z_bout(ym2, sz) + sz * 0.02)), "cabine_noire")
		RemonteeKit.boite(self, Vector3(2.0 * W, 0.10, 0.06), Transform3D(b_nez, Vector3(0, Y_VITRE, z_bout(Y_VITRE, sz) + sz * 0.02)), "cabine_noire")
		RemonteeKit.boite_en(self, Vector3(2.0 * W, 0.55, 0.4), Vector3(0, 0.62, sz * (DEMI_L - 0.2)), "cabine_noire")
		# grand aigle blanc de Val d'Isère sur la face avant (photos), sur le vitrage
		var mi: MeshInstance3D = MeshInstance3D.new()
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(1.4, 1.4)
		mi.mesh = q
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.94, 0.94, 0.94)
		m.albedo_texture = VehiculeRemontee._aigle()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ya: float = 1.85
		mi.transform = Transform3D(b_nez, Vector3(-sz * W * 0.45, ya, z_bout(ya, sz) + sz * 0.03))
		mi.set_meta(MeshMerge.SANS_FUSION, true)
		add_child(mi)
	var mn: MeshInstance3D = MeshInstance3D.new()
	mn.name = "Coque"
	noir.generate_normals()
	mn.mesh = noir.commit()
	if _mat_coque == null:
		_mat_coque = RemonteeKit.mat("cabine_noire").duplicate()
		_mat_coque.cull_mode = BaseMaterial3D.CULL_DISABLED
	mn.material_override = _mat_coque
	add_child(mn)
	var mv: MeshInstance3D = MeshInstance3D.new()
	mv.name = "Vitrages"
	verre.generate_normals()
	mv.mesh = verre.commit()
	mv.material_override = vitre_funi()
	mv.set_meta(MeshMerge.SANS_FUSION, true)
	add_child(mv)


## Quadrilatère (coque mince : matières sans face cachée, vue de dedans comme de dehors).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## Vitrage du flanc sx entre za et zb (bornés par le nez incliné), de y0 à y1.
static func _flanc(st: SurfaceTool, sx: float, za: float, zb: float, y0: float, y1: float) -> void:
	var W: float = DEMI_LARGEUR
	var a0: float = maxf(za, z_bout(y0, -1.0))
	var a1: float = maxf(za, z_bout(y1, -1.0))
	var b0: float = minf(zb, z_bout(y0, 1.0))
	var b1: float = minf(zb, z_bout(y1, 1.0))
	if b0 - a0 < 0.01 and b1 - a1 < 0.01:
		return
	_quad(st, Vector3(sx * W, y0, a0), Vector3(sx * W, y0, b0), Vector3(sx * W, y1, b1), Vector3(sx * W, y1, a1))


## Intérieur (ok-50 à ok-54) : sans cloison — paliers de caillebotis devant les portes et volées de marches entre eux,
## doublure blanche sous les vitres, plafond blanc à pans rouges, cadres de barres rouges en haut de chaque palier,
## banquette garnie sous la vitre de chaque bout.
func _interieur() -> void:
	var R: Basis = _niveau()
	var W: float = DEMI_LARGEUR
	var lw: float = 2.0 * W - 0.1
	for k in range(N_COMP):
		var c: Vector3 = _palier_niv(k)
		# palier (plein jusqu'à 1 m dessous ; les bouts vont jusqu'au nez)
		var z0: float = c.z - L_PALIER * 0.5
		var z1: float = c.z + L_PALIER * 0.5
		if k == 0:
			z1 = c.z + l_comp() * 0.5
		if k == N_COMP - 1:
			z0 = c.z - l_comp() * 0.5
		RemonteeKit.boite(self, Vector3(lw, 1.0, z1 - z0), Transform3D(R, R * Vector3(0, c.y - 0.5, (z0 + z1) * 0.5)), "caillebotis")
		# volée vers le palier suivant (amont)
		if k + 1 < N_COMP:
			var e1: Vector3 = c + Vector3(0, 0, -L_PALIER * 0.5)
			var e2: Vector3 = _palier_niv(k + 1) + Vector3(0, 0, L_PALIER * 0.5)
			var mont: float = e2.y - e1.y
			var course: float = e1.z - e2.z
			for j in range(1, N_MARCHES + 1):
				var haut: float = e1.y + mont * float(j) / float(N_MARCHES)
				var zc: float = e1.z - course * (float(j) - 0.5) / float(N_MARCHES)
				var h: float = haut - (e1.y - 1.0)
				RemonteeKit.boite(self, Vector3(lw, h, course / float(N_MARCHES) + 0.01),
					Transform3D(R, R * Vector3(0, haut - h * 0.5, zc)), "caillebotis")
		# cadre de barres rouges au bord amont du palier : deux poteaux, deux lisses de chaque côté (passage au milieu)
		var e: Vector3 = c + Vector3(0, 0, -L_PALIER * 0.5 + 0.05)
		for sx in [-1.0, 1.0]:
			RemonteeKit.barre(self, R * (e + Vector3(sx * 0.40, 0.0, 0)), R * (e + Vector3(sx * 0.40, 2.1, 0)), 0.022, "rouge_val", 6)
			for hb in [1.0, 2.0]:
				RemonteeKit.barre(self, R * (e + Vector3(sx * 0.40, hb, 0)), R * (e + Vector3(sx * (W - 0.10), hb, 0)), 0.02, "rouge_val", 6)
	# doublure blanche sous les vitres, plafond blanc, pans rouges sous les épaules
	var long_i: float = DEMI_L * 2.0 - 2.0 * NEZ_RECUL
	for sx in [-1.0, 1.0]:
		RemonteeKit.boite_en(self, Vector3(0.04, Y_VITRE - 0.5, long_i), Vector3(sx * (W - 0.05), (Y_VITRE + 0.5) * 0.5, 0), "cabine_blanche")
		RemonteeKit.boite(self, Vector3(0.55, 0.03, long_i), Transform3D(Basis(Vector3.BACK, -sx * 0.7),
			Vector3(sx * (W - 0.32), H_TOIT - 0.30, 0)), "rouge_val")
	RemonteeKit.boite_en(self, Vector3(2.0 * W - 0.9, 0.03, long_i), Vector3(0, H_TOIT - 0.06, 0), "cabine_blanche")
	# banquettes de bout, garnies de moquette grise, dos au nez
	for sz in [-1.0, 1.0]:
		var k2: int = 0 if sz > 0.0 else N_COMP - 1
		var cb: Vector3 = _palier_niv(k2)
		var zb: float = cb.z + sz * (l_comp() * 0.5 - 0.55)
		RemonteeKit.boite(self, Vector3(2.0 * W - 0.3, 0.45, 0.5), Transform3D(R, R * Vector3(0, cb.y + 0.225, zb)), "acier_noir")


## Portes : un grand vantail vitré à cadre noir par compartiment et par côté (photos de quai : traverse au milieu,
## virgule rouge et blanche en bas), qui coulisse vers l'aval le long de la caisse.
func _portes_funi() -> void:
	var W: float = DEMI_LARGEUR
	for sx in [-1.0, 1.0]:
		for k in range(N_COMP):
			var z: float = z_comp(k)
			var p: Node3D = Node3D.new()
			p.name = "Porte_%d_%d" % [k, int(sx)]
			add_child(p)
			var hl: float = H_PORTE * 0.5
			var ll: float = L_PORTE * 0.5
			for zm in [-ll + 0.03, ll - 0.03]:
				RemonteeKit.boite_en(p, Vector3(0.05, H_PORTE, 0.06), Vector3(0, 0, zm), "cabine_noire")
			for ym in [-hl + 0.04, hl - 0.03, -0.1]:
				RemonteeKit.boite_en(p, Vector3(0.05, 0.07 if ym != -hl + 0.04 else 0.12, L_PORTE), Vector3(0, ym, 0), "cabine_noire")
			# virgule rouge et blanche en bas du vitrage
			RemonteeKit.boite(p, Vector3(0.012, 0.05, L_PORTE * 0.9), Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(sx * 0.03, -hl + 0.35, 0)), "rouge_val")
			RemonteeKit.boite(p, Vector3(0.012, 0.035, L_PORTE * 0.8), Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(sx * 0.03, -hl + 0.24, 0.05)), "cabine_blanche")
			var v: MeshInstance3D = RemonteeKit.boite_en(p, Vector3(0.02, H_PORTE - 0.12, L_PORTE - 0.1), Vector3.ZERO, "vitre")
			v.material_override = vitre_funi()
			v.set_meta(MeshMerge.SANS_FUSION, true)
			MeshMerge.merge(p, [v], "Porte")
			var ferme: Vector3 = Vector3(sx * (W + 0.05), H_PLANCHER + hl, z)
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
