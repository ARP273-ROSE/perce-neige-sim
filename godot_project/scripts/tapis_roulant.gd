class_name TapisRoulant
extends Node3D
## Tapis roulant (« magic carpet ») : une bande de caoutchouc au ras de la neige qui monte les skieurs à pied ou à
## skis. Demande d'utilisateur du 12/11/2026 : « fais-moi le double tapis pour remonter sur la tête de Solaise ».
## Tracé : OpenStreetMap (aerialway=magic_carpet, « Pim » et « Pam », deux bandes jumelles de 231 m qui montent du
## plateau à la gare amont de la TCD de Solaise) ; largeur, vitesse et joues estimées (tapis courants : bande de
## 0,8 m, 0,6 à 0,8 m/s).
##
## Le skieur posé sur la bande avance avec elle (il peut y marcher pour aller plus vite) ; au bout, il est déposé
## sur la neige.

const LARGEUR: float = 0.80
const VITESSE: float = 0.80                  # m/s
const PAS: float = 1.0                       # échantillonnage du profil (m)
const H_BANDE: float = 0.03                  # dessus de la bande au-dessus de la neige
const PERIODE_RAYURES: float = 0.40          # m : une rayure claire tous les 40 cm (on la voit avancer)

## [nom, [lat, lon] du bas, [lat, lon] du haut] — OpenStreetMap (ODbL), coordonnées seules.
const TAPIS: Array = [
	["Pim", [45.4302038, 6.9957115], [45.4318232, 6.9938587]],
	["Pam", [45.4301946, 6.9956928], [45.4318138, 6.9938401]],
]
const CONSTRUIRE_JUSQUA: float = 900.0

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
	_ys.resize(n)
	for k2 in range(n):
		var somme: float = 0.0
		var c: int = 0
		for j in range(maxi(0, k2 - 2), mini(n, k2 + 3)):
			somme += brut[j]
			c += 1
		_ys[k2] = maxf(somme / c, brut[k2]) + H_BANDE
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
