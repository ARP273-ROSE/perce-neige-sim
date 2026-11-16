class_name TapisRoulant
extends Node3D
## Tapis roulant (« magic carpet ») : une bande de caoutchouc au ras de la neige qui monte les skieurs à pied ou à
## skis. Demande d'utilisateur du 12/11/2026 : « fais-moi le double tapis pour remonter sur la tête de Solaise ».
## Tracé et vitesse : deux montées enregistrées au GPS (avril 2026, une sur chaque bande ; retour d'utilisateur du
## 13/11/2026 : « les tapis de Solaise doivent être au GPX ») — droite ajustée sur les deux traces, cap −39,3°,
## bandes à 1,5 m d'axe en axe, 232,8 m du bas au haut, parcourus en 227 s (1,0 m/s). Noms « Pim » et « Pam » :
## OpenStreetMap. Largeur et joues estimées (bande courante de 0,8 m).
##
## Retour d'utilisateur du 16/11/2026 : « ton double tapis est nul à Solaise, il suit le terrain au lieu d'avoir une
## pente continue ; les tapis sont couverts ». Les bandes sont maintenant droites, à pente constante du bas au haut
## (14,5 % d'après le relief IGN aux deux bouts ; 15,4 % sur la fiche du constructeur) ; le terrain est mis à cette pente
## sous elles (aménagement « rampes » du relief : déblai jusqu'à 2,7 m, remblai jusqu'à 1,3 m). Couverture d'après les
## photos publiques et la fiche du constructeur (Funbelt, 2015 : galerie aluminium élargie au débarquement) : un tube
## étroit par bande (arceaux ronds tous les 1,5 m, panneaux translucides, plinthe de planches au pied), portail arqué
## noir à l'embarquement avec le nom en vertical, gare haute fermée commune aux deux bandes, coque argent sur une base
## bardée de bois.
##
## Le skieur posé sur la bande avance avec elle (il peut y marcher pour aller plus vite) ; au bout, il est déposé
## sur la neige.

const LARGEUR: float = 0.80
const VITESSE: float = 1.2                   # m/s, fiche du constructeur (choix d'utilisateur du 16/11/2026 ; GPS : 232,8 m en 227 s)
const PENTE: float = 0.154                   # fiche du constructeur : 35 m pour 230 m (le relief IGN aux deux bouts donnait 14,5 %)
const PAS: float = 1.0                       # échantillonnage du profil (m)
const H_BANDE: float = 0.03                  # dessus de la bande au-dessus de la neige
const PERIODE_RAYURES: float = 0.40          # m : une rayure claire tous les 40 cm (on la voit avancer)

## [nom, [lat, lon] du bas, [lat, lon] du haut] — relevé GPS (embarquement et débarquement).
const TAPIS: Array = [
	["Pim", [45.4302006, 6.9957608], [45.4318184, 6.9938724]],
	["Pam", [45.4301921, 6.9957460], [45.4318098, 6.9938576]],
]
const CONSTRUIRE_JUSQUA: float = 900.0
const DEMI_GALERIE: float = 0.70            # demi-largeur intérieure d'un tube (bandes à 1,5 m d'axe en axe : tubes accolés)
const H_PIED_GALERIE: float = 1.70           # hauteur des côtés droits
const H_GALERIE: float = 2.40                # sous la clé de l'arc (un adulte à skis y tient debout)
const PAS_ARCEAU: float = 1.5
const L_GARE_HAUTE: float = 6.0              # gare haute fermée : de L − 6 m à L + 3 m
const RECUL_PORTAIL: float = 0.4             # portail du bas, 0,4 m avant le début de la bande


## Axe commun des deux bandes (milieu), bas et haut, monde (x, z).
static func _axe_commun() -> Array:
	var a0: Vector2 = Vector2.ZERO
	var b0: Vector2 = Vector2.ZERO
	for t in TAPIS:
		a0 += RemonteesDomaine.monde(float(t[1][0]), float(t[1][1])) / TAPIS.size()
		b0 += RemonteesDomaine.monde(float(t[2][0]), float(t[2][1])) / TAPIS.size()
	return [a0, b0]


## Terrassement sous les tapis (appelé par le relief avant ses pièces fines) : couloir à la pente continue du bas
## au haut, sol relevé aux deux bouts sur la neige d'origine.
static func amenagement_relief(r: ReliefBuilder) -> Dictionary:
	if r == null:
		return {}
	var ax: Array = _axe_commun()
	var a0: Vector2 = ax[0]
	var b0: Vector2 = ax[1]
	var u: Vector2 = (b0 - a0).normalized()
	# un peu avant et après les bouts : aires d'embarquement et de débarquement à plat sur la pente
	var pa: Vector2 = a0 - u * 3.0
	var pb: Vector2 = b0 + u * 3.0
	# pente du constructeur depuis la neige du bas : le haut est relevé (ou creusé) d'autant, le relief s'y raccorde
	var ya: float = r.hauteur(pa.x, pa.y)
	var yb: float = ya + PENTE * pa.distance_to(pb)
	var bb: Rect2 = Rect2(pa, Vector2.ZERO).expand(pb)
	var demi: float = DEMI_GALERIE + 1.5
	var fondu: float = 6.0
	return {"rect": bb.grow(demi + fondu + 6.0), "rampes": [[Vector3(pa.x, ya, pa.y), Vector3(pb.x, yb, pb.y), demi, fondu]],
		"masque": true}

var relief: ReliefBuilder = null
var domaine: RemonteesDomaine = null        # (son skieur, posé après la construction)
var nom: String = ""
var a: Vector2 = Vector2.ZERO               # bas (monde, x z)
var b: Vector2 = Vector2.ZERO               # haut
var _u: Vector2 = Vector2.ZERO              # direction horizontale du bas vers le haut
var _w: Vector2 = Vector2.ZERO              # travers (à gauche en montant)
var _long: float = 0.0
var _ys: PackedFloat32Array = PackedFloat32Array()   # dessus de la bande, tous les PAS
var _construit: bool = false
var _mat: StandardMaterial3D = null
var _defile: float = 0.0
var _porte: bool = false                    # le skieur est sur cette bande
var _s_porte: float = 0.0                   # son abscisse le long de la bande
var _t_verif: float = 1.0
var _brut: PackedFloat32Array = PackedFloat32Array()   # neige relevée sous la bande (bord le plus haut)
var _parque: Vector3 = Vector3.INF          # déposé à skis au bout, immobile tant qu'il ne commande rien


## Les tapis du domaine, enfants de `parent`.
static func poser_tous(parent: RemonteesDomaine, r: ReliefBuilder) -> Array:
	var out: Array = []
	for t in TAPIS:
		var n: TapisRoulant = TapisRoulant.new()
		n.name = "Tapis_" + String(t[0])
		n.nom = String(t[0])
		n.relief = r
		n.domaine = parent
		n.a = RemonteesDomaine.monde(float(t[1][0]), float(t[1][1]))
		n.b = RemonteesDomaine.monde(float(t[2][0]), float(t[2][1]))
		parent.add_child(n)
		out.append(n)
	return out


func _ready() -> void:
	# après le skieur : on corrige sa position une fois qu'il a fait son pas
	process_priority = 100
	_long = a.distance_to(b)
	_u = (b - a) / maxf(_long, 0.01)
	_w = Vector2(_u.y, -_u.x)


func _process(delta: float) -> void:
	if relief == null or not relief.pret:
		return
	var sk: SkieurJoueur = domaine.skieur if domaine != null else null
	var p: Vector3 = sk.global_position if sk != null and sk.actif else _camera()
	var dist: float = _distance(Vector2(p.x, p.z))
	if not _construit:
		if dist < CONSTRUIRE_JUSQUA:
			_construire()
		return
	visible = dist < CONSTRUIRE_JUSQUA + 200.0
	if not visible:
		return
	# le relief fin arrive près du skieur après la construction (relevé sur le relief grossier, la bande était
	# enterrée par endroits, joues cassées) : on la refait quand la neige sous elle a changé de hauteur
	_t_verif -= delta
	if _t_verif <= 0.0 and dist < 500.0:
		_t_verif = 1.0
		if _relief_change():
			for c in get_children():
				c.queue_free()
			_construire()
	_defile = fposmod(_defile + VITESSE * delta, PERIODE_RAYURES)
	_mat.uv1_offset = Vector3(0.0, -_defile / PERIODE_RAYURES, 0.0)
	if sk != null and sk.actif and not sk.embarque:
		_porter(sk, delta)


func _camera() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.INF


## Distance horizontale au segment de la bande.
func _distance(q: Vector2) -> float:
	var s: float = clampf((q - a).dot(_u), 0.0, _long)
	return (a + _u * s).distance_to(q)


## Dessus de la bande à l'abscisse s.
func y_bande(s: float) -> float:
	if _ys.is_empty():
		return 0.0
	var f: float = clampf(s / PAS, 0.0, float(_ys.size() - 1))
	var i: int = mini(int(f), _ys.size() - 2)
	return lerpf(_ys[i], _ys[i + 1], f - i)


func _point(s: float, w: float) -> Vector3:
	var q: Vector2 = a + _u * s + _w * w
	return Vector3(q.x, y_bande(s), q.y)


func _haut_neige(s: float) -> float:
	var q: Vector2 = a + _u * s
	return maxf(relief.hauteur_sol(q.x + _w.x * LARGEUR * 0.5, q.y + _w.y * LARGEUR * 0.5),
		relief.hauteur_sol(q.x - _w.x * LARGEUR * 0.5, q.y - _w.y * LARGEUR * 0.5))


## Sept points du profil : la neige a-t-elle bougé de plus de 4 cm depuis la construction ?
func _relief_change() -> bool:
	var n: int = _brut.size()
	if n < 2:
		return false
	for k in range(7):
		var i: int = int(float(n - 1) * k / 6.0)
		if absf(_haut_neige(minf(i * PAS, _long)) - _brut[i]) > 0.04:
			return true
	return false


## Profil (neige sous l'axe, lissé sur ±2 m), bande à rayures, joues et peignes.
func _construire() -> void:
	_construit = true
	var n: int = int(ceil(_long / PAS)) + 1
	var brut: PackedFloat32Array = PackedFloat32Array()
	brut.resize(n)
	for k in range(n):
		var s: float = minf(k * PAS, _long)
		var q: Vector2 = a + _u * s
		# (la bande ne s'enfonce pas : le plus haut des deux bords)
		var h0: float = relief.hauteur_sol(q.x + _w.x * LARGEUR * 0.5, q.y + _w.y * LARGEUR * 0.5)
		var h1: float = relief.hauteur_sol(q.x - _w.x * LARGEUR * 0.5, q.y - _w.y * LARGEUR * 0.5)
		brut[k] = maxf(h0, h1)
	_brut = brut
	# pente continue du bas au haut (le terrain y est mis par l'aménagement « rampes ») ; posée sur la neige relevée
	# aux deux bouts, et jamais sous la neige ailleurs (si le terrassement n'est pas là : cuisson, relief grossier)
	_ys.resize(n)
	var y0: float = brut[0]
	var y1: float = y0 + PENTE * _long
	var leve: float = 0.0
	for k2 in range(n):
		leve = maxf(leve, brut[k2] - lerpf(y0, y1, float(k2) / float(n - 1)))
	leve = minf(leve, 0.25)
	for k2 in range(n):
		_ys[k2] = lerpf(y0, y1, float(k2) / float(n - 1)) + leve + H_BANDE
	# bande : un ruban, V le long de la bande (en mètres / PERIODE_RAYURES), rayures défilantes
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e: float = LARGEUR * 0.5
	for k3 in range(n - 1):
		var s0: float = minf(k3 * PAS, _long)
		var s1: float = minf((k3 + 1) * PAS, _long)
		var p00: Vector3 = _point(s0, -e)
		var p01: Vector3 = _point(s0, e)
		var p10: Vector3 = _point(s1, -e)
		var p11: Vector3 = _point(s1, e)
		var v0: float = s0 / PERIODE_RAYURES
		var v1: float = s1 / PERIODE_RAYURES
		var nm: Vector3 = (p10 - p00).cross(p01 - p00).normalized()
		if nm.y < 0.0:
			nm = -nm
		for t in [[p00, Vector2(0, v0)], [p10, Vector2(0, v1)], [p11, Vector2(1, v1)], [p00, Vector2(0, v0)], [p11, Vector2(1, v1)], [p01, Vector2(1, v0)]]:
			st.set_normal(nm)
			st.set_uv(t[1])
			st.add_vertex(t[0] - global_position)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Bande"
	mi.mesh = st.commit()
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = _rayures()
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat.roughness = 0.9
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = _mat
	add_child(mi)
	# joues : profilés jaunes de 12 cm de chaque côté, à 4 cm de la bande ; peignes au bas et en haut
	var joues: Node3D = Node3D.new()
	joues.name = "Joues"
	add_child(joues)
	var o: Vector3 = global_position
	for sw in [-1.0, 1.0]:
		var k4: int = 0
		while k4 < n - 1:
			var k5: int = mini(k4 + 4, n - 1)
			var pa: Vector3 = _point(minf(k4 * PAS, _long), sw * (e + 0.10)) - o + Vector3(0, 0.02, 0)
			var pb: Vector3 = _point(minf(k5 * PAS, _long), sw * (e + 0.10)) - o + Vector3(0, 0.02, 0)
			RemonteeKit.poutre(joues, pa, pb, 0.12, 0.10, "jaune_securite")
			k4 = k5
	for s_b in [0.0, _long]:
		var c0: Vector3 = _point(s_b, 0.0) - o
		var dir: Vector3 = (_point(minf(s_b + 1.0, _long), 0.0) - _point(maxf(s_b - 1.0, 0.0), 0.0)).normalized()
		var bas: bool = s_b == 0.0
		var cp: Vector3 = c0 + dir * (-0.35 if bas else 0.35)
		RemonteeKit.boite(joues, Vector3(LARGEUR + 0.32, 0.05, 0.70), Transform3D(Basis.looking_at(dir, Vector3.UP), cp + Vector3(0, -0.005, 0)), "galva")
		# bout : tambour sous un carter (dessus 10 cm au-dessus de la neige)
		RemonteeKit.boite(joues, Vector3(LARGEUR + 0.32, 0.12, 0.30), Transform3D(Basis.looking_at(dir, Vector3.UP), c0 + dir * (-0.85 if bas else 0.85) + Vector3(0, 0.02, 0)), "peinture_anthracite")
	MeshMerge.merge(joues, [], "Joues", true)
	_galerie()
	if nom == String(TAPIS[0][0]):
		_gare_haute()


## Galerie couverte commune aux deux bandes (posée par la première) : arceaux, panneaux translucides, côtés
## fermés ; collisions des côtés et du toit (on y entre par les bouts).
func _galerie() -> void:
	var a0: Vector2 = a
	var lg: float = _long
	var u2: Vector2 = _u
	var w2: Vector2 = _w
	var o: Vector3 = global_position
	var pente: float = (y_bande(_long) - y_bande(0.0)) / maxf(_long, 0.01)
	var pt := func(s: float, w: float, y: float) -> Vector3:
		var q: Vector2 = a0 + u2 * s + w2 * w
		# (dessus de la bande à la même abscisse, prolongé à la même pente au-delà des bouts)
		return Vector3(q.x, y_bande(clampf(s, 0.0, _long)) + pente * (s - clampf(s, 0.0, _long)) + y, q.y) - o
	var g: Node3D = Node3D.new()
	g.name = "Galerie"
	add_child(g)
	var prof: Array = []           # demi-section : [w, y] du pied à la clé
	prof.append([DEMI_GALERIE, -0.05])
	prof.append([DEMI_GALERIE, H_PIED_GALERIE])
	for k in range(1, 9):
		var ang: float = PI * 0.5 * float(k) / 8.0
		prof.append([DEMI_GALERIE * cos(ang), H_PIED_GALERIE + (H_GALERIE - H_PIED_GALERIE) * sin(ang)])
	var sec: Array = []
	for p in prof:
		sec.append([p[0], p[1]])
	for k2 in range(prof.size() - 2, -1, -1):
		sec.append([-float(prof[k2][0]), prof[k2][1]])
	var s0: float = -RECUL_PORTAIL
	var s1: float = lg - L_GARE_HAUTE + 0.5
	# panneaux : un ruban translucide le long de la section, coupé par tronçon
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s: float = s0
	while s < s1 - 0.01:
		var sn: float = minf(s + PAS_ARCEAU, s1)
		for k3 in range(sec.size() - 1):
			var p00: Vector3 = pt.call(s, sec[k3][0], sec[k3][1])
			var p01: Vector3 = pt.call(s, sec[k3 + 1][0], sec[k3 + 1][1])
			var p10: Vector3 = pt.call(sn, sec[k3][0], sec[k3][1])
			var p11: Vector3 = pt.call(sn, sec[k3 + 1][0], sec[k3 + 1][1])
			var nm: Vector3 = (p10 - p00).cross(p01 - p00).normalized()
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(nm)
				st.add_vertex(v)
		s = sn
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.90, 0.94, 0.38)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pan: MeshInstance3D = MeshInstance3D.new()
	pan.name = "Panneaux"
	pan.mesh = st.commit()
	pan.material_override = m
	pan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(pan)
	# arceaux et lisses basses
	var ar: Node3D = Node3D.new()
	ar.name = "Arceaux"
	g.add_child(ar)
	s = s0
	while s <= s1 + 0.01:
		var pts: PackedVector3Array = PackedVector3Array()
		for e in sec:
			pts.append(pt.call(s, e[0] * 1.01, e[1] + 0.01))
		RemonteeKit.tube(ar, pts, 0.035, "galva", 6)
		s += PAS_ARCEAU
	for sw in [-1.0, 1.0]:
		for yl in [0.05, H_PIED_GALERIE]:
			var pa: Vector3 = pt.call(s0, sw * DEMI_GALERIE * 1.01, yl)
			var pb: Vector3 = pt.call(s1, sw * DEMI_GALERIE * 1.01, yl)
			RemonteeKit.barre(ar, pa, pb, 0.03, "galva", 5)
	# plinthe de planches au pied des deux côtés
	for sw3 in [-1.0, 1.0]:
		var s3: float = s0
		while s3 < s1 - 0.01:
			var s4: float = minf(s3 + 3.0, s1)
			RemonteeKit.poutre(ar, pt.call(s3, sw3 * (DEMI_GALERIE + 0.03), 0.15), pt.call(s4, sw3 * (DEMI_GALERIE + 0.03), 0.15), 0.03, 0.30, "bois_fonce")
			s3 = s4
	MeshMerge.merge(ar, [], "Arceaux", true)
	# portail du bas : arc noir opaque plus large que le tube, nom en vertical sur le montant extérieur
	var por: Node3D = Node3D.new()
	por.name = "Portail"
	g.add_child(por)
	var cadre: PackedVector3Array = PackedVector3Array()
	for e3 in sec:
		cadre.append(pt.call(s0, float(e3[0]) * 1.12, float(e3[1]) * 1.06 + 0.02))
	RemonteeKit.tube(por, cadre, 0.16, "noir_mat", 8)
	var cote_ext: float = signf((a - _axe_commun()[0]).dot(_w))
	if cote_ext == 0.0:
		cote_ext = 1.0
	var pm: Vector3 = pt.call(s0 - 0.05, cote_ext * (DEMI_GALERIE + 0.22), 1.25)
	RemonteeKit.boite(por, Vector3(0.10, 2.3, 0.55), Transform3D(Basis.looking_at(Vector3(u2.x, 0, u2.y), Vector3.UP), pm), "noir_mat")
	var lab: MeshInstance3D = RemonteeKit.texte_fige(por, "\n".join(nom.to_upper().split("")), 48, 0.0042, Color(0.98, 0.98, 0.98))
	lab.position = pt.call(s0 - 0.33, cote_ext * (DEMI_GALERIE + 0.22), 1.55)
	lab.rotation = Vector3(0, atan2(-u2.x, -u2.y), 0)
	# collisions : côtés et toit (boîtes inclinées par tronçon)
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsGalerie"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	g.add_child(corps)
	s = s0
	while s < s1 - 0.01:
		var sn2: float = minf(s + PAS_ARCEAU, s1)
		for e2 in [[DEMI_GALERIE + 0.05, H_PIED_GALERIE * 0.5, 0.1, H_PIED_GALERIE + 0.1], [0.0, H_GALERIE + 0.05, DEMI_GALERIE * 2.0, 0.1]]:
			for sw2 in ([-1.0, 1.0] if float(e2[0]) > 0.0 else [1.0]):
				var c0: Vector3 = pt.call(s, sw2 * float(e2[0]), float(e2[1]))
				var c1: Vector3 = pt.call(sn2, sw2 * float(e2[0]), float(e2[1]))
				var dir: Vector3 = (c1 - c0).normalized()
				var cs: CollisionShape3D = CollisionShape3D.new()
				var bs: BoxShape3D = BoxShape3D.new()
				bs.size = Vector3(float(e2[2]), float(e2[3]), c0.distance_to(c1) + 0.02)
				cs.shape = bs
				cs.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (c0 + c1) * 0.5)
				corps.add_child(cs)
		s = sn2


## Gare haute commune aux deux bandes : coque argent fermée sur une base bardée de bois, plus large que les deux tubes,
## ouverte vers l'amont (sortie frontale) ; collisions des côtés et du toit.
func _gare_haute() -> void:
	var ax: Array = _axe_commun()
	var a0: Vector2 = ax[0]
	var b0: Vector2 = ax[1]
	var lg: float = a0.distance_to(b0)
	var u2: Vector2 = (b0 - a0) / maxf(lg, 0.01)
	var o: Vector3 = global_position
	var y_haut: float = y_bande(_long)
	var pente: float = (y_bande(_long) - y_bande(0.0)) / maxf(_long, 0.01)
	var z0: float = lg - L_GARE_HAUTE
	var z1: float = lg + 3.0
	var demi: float = 0.75 + DEMI_GALERIE + 0.45
	var h: float = 3.2
	var base: float = 1.0
	var g: Node3D = Node3D.new()
	g.name = "GareHaute"
	add_child(g)
	var bas: Basis = Basis.looking_at(Vector3(u2.x, 0, u2.y), Vector3.UP)
	var w2: Vector2 = Vector2(u2.y, -u2.x)
	var corps: StaticBody3D = StaticBody3D.new()
	corps.name = "CollisionsGareHaute"
	corps.collision_layer = CollisionsJeu.COUCHE_DECOR
	corps.collision_mask = 0
	g.add_child(corps)
	var piece := func(taille: Vector3, wq: float, sq: float, yq: float, m: String, col: bool) -> void:
		var q: Vector2 = a0 + u2 * sq + w2 * wq
		var y: float = y_haut + pente * minf(sq - lg, 0.0) + yq
		var c: Vector3 = Vector3(q.x, y, q.y) - o
		RemonteeKit.boite(g, taille, Transform3D(bas, c), m)
		if col:
			var cs: CollisionShape3D = CollisionShape3D.new()
			var bs: BoxShape3D = BoxShape3D.new()
			bs.size = taille
			cs.shape = bs
			cs.transform = Transform3D(bas, c)
			corps.add_child(cs)
	var lz: float = z1 - z0
	var zm: float = (z0 + z1) * 0.5
	for sw in [-1.0, 1.0]:
		piece.call(Vector3(0.12, base, lz), sw * demi, zm, base * 0.5 - 0.1, "bois_meleze", true)
		piece.call(Vector3(0.10, h - base, lz), sw * demi, zm, base + (h - base) * 0.5 - 0.1, "blanc_plaque", true)
	# toit bombé : trois pans argent
	for k in [-1, 0, 1]:
		piece.call(Vector3(demi * 0.72, 0.10, lz + 0.4), float(k) * demi * 0.66, zm, h + (0.18 if k == 0 else 0.0), "alu_pince", k == 0)
	# fond côté aval : mur au-dessus des deux tubes qui entrent
	piece.call(Vector3(demi * 2.0, h - H_GALERIE - 0.2, 0.12), 0.0, z0, H_GALERIE + 0.2 + (h - H_GALERIE - 0.2) * 0.5, "blanc_plaque", false)


## Bande grise à rayures claires (une période sur la hauteur de l'image).
static var _tex_rayures: ImageTexture = null


static func _rayures() -> ImageTexture:
	if _tex_rayures != null:
		return _tex_rayures
	var img: Image = Image.create(8, 32, false, Image.FORMAT_RGB8)
	for y in range(32):
		var c: Color = Color(0.52, 0.54, 0.56) if y < 6 else Color(0.14, 0.15, 0.16)
		for x in range(8):
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex_rayures = ImageTexture.create_from_image(img)
	return _tex_rayures


## Skieur sur la bande : il avance avec elle (et de son propre pas s'il marche dans le sens de la montée), garde
## son écart latéral, reste posé sur le caoutchouc ; au bout, déposé 1,2 m après le peigne.
func _porter(sk: SkieurJoueur, delta: float) -> void:
	var p: Vector3 = sk.global_position
	# déposé à skis : il reste où on l'a posé tant qu'il ne commande rien (la pente le ramenait sur la bande)
	if _parque != Vector3.INF:
		if sk.chausse and sk.entree.length() < 0.1 and sk._clavier().length() < 0.1 and p.distance_to(_parque) < 0.5:
			sk.global_position = _parque
			sk._v_ski = Vector3.ZERO
			return
		_parque = Vector3.INF
	var q: Vector2 = Vector2(p.x, p.z) - a
	var s: float = q.dot(_u)
	var w: float = q.dot(_w)
	var sur: bool = s > -0.2 and s < _long + (0.4 if _porte else 0.0) and absf(w) < LARGEUR * 0.5 + 0.05 and absf(p.y - y_bande(clampf(s, 0.0, _long))) < 0.45
	if not sur:
		_porte = false
		return
	if not _porte:
		_porte = true
		_s_porte = maxf(s, 0.0)
	# à pied, son propre pas vers le haut s'ajoute ; vers le bas, la bande l'emporte (à skis, sa glisse va déjà à la
	# vitesse de la bande : seule la bande compte)
	var s_n: float = _s_porte + VITESSE * delta
	if not sk.chausse:
		s_n = maxf(s_n, s + VITESSE * delta)
	_s_porte = s_n
	if s_n >= _long:
		_porte = false
		var fin: Vector3 = _point(_long, w)
		var dir: Vector3 = (_point(_long, 0.0) - _point(_long - 2.0, 0.0)).normalized()
		var dep: Vector3 = fin + dir * 1.2
		dep.y = relief.hauteur_sol(dep.x, dep.z)
		sk.global_position = dep
		if sk.chausse:
			# arrêté en chasse-neige tant qu'il ne commande rien (la pente le ramenait sur la bande)
			sk._v_ski = Vector3.ZERO
			sk.frein_auto = 3.0
			_parque = dep
		return
	var np: Vector3 = _point(s_n, clampf(w, -LARGEUR * 0.5 + 0.12, LARGEUR * 0.5 - 0.12))
	sk.global_position = np
	if sk.chausse:
		# (la glisse ne le tire pas vers le bas de la pente : sa vitesse est celle de la bande)
		sk._v_ski = (_point(minf(s_n + 1.0, _long), 0.0) - _point(maxf(s_n - 1.0, 0.0), 0.0)).normalized() * VITESSE
	else:
		sk.velocity = Vector3(0.0, minf(sk.velocity.y, 0.0), 0.0)
