class_name ReliefBuilder
extends Node3D
## Relief 3D RÉEL du massif autour du funiculaire, en vue extérieure
## (demande de Kevin du 06/10/2026 : « prolonger le paysage 3D jusqu'au
## tunnel et jusqu'en bas, jusqu'au lac de Tignes, et dans le rayon
## autour », pour se rendre compte d'où passe le tunnel).
##
## - Relief IGN RGE ALTI, maille de 25 ou 50 m, sur 8,6 × 10,2 km (du sommet de
##   la Grande Motte au lac de Tignes), texturé par l'orthophotographie IGN
##   (Licence Ouverte) — données préparées par tools_relief3d.py ;
## - le tracé du tunnel dessiné en surface (ruban orange), des étiquettes
##   pour les lacs, villages et sommets (OpenStreetMap) ;
## - autour de la rame, le terrain s'ouvre (« trou » qui grandit avec le
##   recul de la caméra) : on voit dessous la rame, le tunnel (ligne orange à
##   sa vraie profondeur) et le socle rocheux du bloc.
## N'existe qu'en vue extérieure (main.gd).

const CHUNK: int = 64                 # mailles par côté de tuile (frustum culling)
const GAMMA_WEB: float = 0.625        # rendu Compatibility : voir MachineRoomBuilder
const SHADER_TERRAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 trou_centre = vec3(0.0);
uniform float trou_r = 60.0;
uniform float gamma = 1.0;
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = distance(pw.xz, trou_centre.xz);
	vec3 c = pow(texture(ortho, UV).rgb, vec3(gamma));
	if (d < trou_r) {
		// maquette découpée autour de la rame : on voit dessous le tunnel
		// (ligne orange à sa vraie profondeur), la rame et le socle rocheux
		discard;
	}
	float bord = smoothstep(trou_r - 3.0, trou_r, d) * (1.0 - smoothstep(trou_r, trou_r * 1.04 + 3.0, d));
	ALBEDO = mix(c, vec3(1.0, 0.78, 0.25), bord * 0.8);
}
"""
## Socle et flancs du bloc de relief (maquette) : roche sombre à strates
const SHADER_SOCLE: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform float gamma = 1.0;
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float strate = 0.5 + 0.5 * sin(pw.y * 0.21 + sin(pw.x * 0.013 + pw.z * 0.011) * 2.0);
	vec3 roche = mix(vec3(0.20, 0.17, 0.15), vec3(0.30, 0.26, 0.22), strate);
	// fond du bloc uni et sombre ; flancs à strates
	vec3 c = pw.y < 1551.0 ? vec3(0.10, 0.09, 0.08) : roche * mix(0.55, 1.0, clamp((pw.y - 1550.0) / 1500.0, 0.0, 1.0));
	ALBEDO = pow(c, vec3(gamma));
}
"""
const Y_SOCLE: float = 1550.0
## Paroi du puits découpé autour de la rame : cylindre de roche qui s'arrête
## à la surface du relief (lue dans une texture des altitudes)
const SHADER_PUITS: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D hauteurs : filter_linear, repeat_disable;
uniform vec4 emprise;          // x ouest, z nord, x est, z sud
uniform float gamma = 1.0;
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = (pw.xz - emprise.xy) / (emprise.zw - emprise.xy);
	float h = texture(hauteurs, uv).r;
	if (pw.y > h || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	float strate = 0.5 + 0.5 * sin(pw.y * 0.11 + sin(pw.x * 0.05 + pw.z * 0.04) * 1.2);
	vec3 roche = mix(vec3(0.28, 0.24, 0.20), vec3(0.36, 0.31, 0.26), strate);
	// plus sombre vers le fond, liseré clair sous la surface
	float prof = clamp((h - pw.y) / 400.0, 0.0, 1.0);
	ALBEDO = pow(roche * mix(1.0, 0.45, prof) + vec3(0.25, 0.2, 0.08) * (1.0 - smoothstep(0.0, 4.0, h - pw.y)),
		vec3(gamma));
}
"""
var _puits: MeshInstance3D = null
const SHADER_TRACE: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform vec3 trou_centre = vec3(0.0);
uniform float trou_r = 60.0;
uniform vec4 couleur : source_color = vec4(1.0, 0.55, 0.08, 0.9);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (distance(pw.xz, trou_centre.xz) < trou_r) {
		discard;
	}
	ALBEDO = couleur.rgb;
	ALPHA = couleur.a;
}
"""

var tunnel: TunnelBuilder = null
var _h: PackedFloat32Array = PackedFloat32Array()
var _dx: float = 1.0
var _dz: float = 1.0
var _mats: Array[ShaderMaterial] = []
## Prêt à être affiché (construction terminée).
var pret: bool = false

# --- Construction EN TÂCHE DE FOND (optimisation du 06/10/2026 : « un beau
# truc qui ne consomme pas énormément de ressources ») -------------------
# 1. préparation des données (décodage des 141 000 altitudes, sommets et
#    indices de chaque tuile) : sur PC dans un fil parallèle
#    (WorkerThreadPool) ; dans la PWA, qui n'a pas de fils, par tranches de
#    3 ms par image sur le fil principal ;
# 2. création des maillages (appels au moteur de rendu) : fil principal,
#    quelques tuiles par image.
# Aucun gel au démarrage ; le relief apparaît en vue extérieure dès qu'il
# est prêt (≈ 1 s).
# Résolution selon la machine (cran du PerfManager) : maille de 25 m et
# orthophoto 2048 px pour une bonne carte graphique ; maille de 50 m
# (4 fois moins de triangles) et orthophoto 1024 px sinon (iPad, carte
# intégrée modeste, rendu logiciel).
const BUDGET_US: int = 3000
var _pas: int = 1                     # 1 = 25 m, 2 = 50 m
var _ortho_l: int = 2048
var _etape: int = 0                   # 0 décodage, 1 tuiles, 2 maillages, 3 fini
var _k: int = 0                       # avancement dans l'étape
var _octets: PackedByteArray = PackedByteArray()
var _tuiles: Array = []               # [i0, i1, j0, j1] en indices de la grille
var _tableaux: Array = []             # tableaux de sommets prêts
var _tache: int = -1
var _mat_terrain: ShaderMaterial = null


func build(t: TunnelBuilder, cran: int = 0) -> void:
	tunnel = t
	_pas = 1 if cran <= 2 else 2
	_ortho_l = 2048 if cran <= 2 else 1024
	var img: Image = (load("res://textures/relief_hauteurs.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	_octets = img.get_data()
	_h.resize(ReliefDonnees.NX * ReliefDonnees.NZ)
	_dx = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / float(ReliefDonnees.NX - 1)
	_dz = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / float(ReliefDonnees.NZ - 1)
	var i0: int = 0
	while i0 < ReliefDonnees.NZ - 1:
		var j0: int = 0
		while j0 < ReliefDonnees.NX - 1:
			_tuiles.append([i0, mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1),
				j0, mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1)])
			j0 = mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1)
		i0 = mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1)
	_tableaux.resize(_tuiles.size())
	visible = false
	if OS.has_feature("threads"):
		_tache = WorkerThreadPool.add_task(_preparer_tout, false, "relief")
	print("[Relief] maille %d m, orthophoto %d px, %d tuiles, préparation %s" % [
		25 * _pas, _ortho_l, _tuiles.size(),
		"en parallèle" if _tache >= 0 else "par tranches"])


func _process(_delta: float) -> void:
	if _etape >= 3:
		set_process(false)
		return
	if _tache >= 0:
		if not WorkerThreadPool.is_task_completed(_tache):
			return
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
	elif _etape < 2:
		_preparer(Time.get_ticks_usec() + BUDGET_US)
		return
	_creer_maillages(Time.get_ticks_usec() + BUDGET_US)


## Fil parallèle : toute la préparation d'un coup.
func _preparer_tout() -> void:
	while _etape < 2:
		_preparer(1 << 62)


## Avance la préparation jusqu'à l'échéance `fin_us` (ou la fin).
func _preparer(fin_us: int) -> void:
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	while _etape < 2:
		if _etape == 0:
			# décodage, une ligne de la grille à la fois
			var base: int = _k * nx
			for j in range(nx):
				var o: int = 3 * (base + j)
				_h[base + j] = ReliefDonnees.H_BASE \
					+ float(int(_octets[o]) * 256 + int(_octets[o + 1])) * ReliefDonnees.H_ECHELLE
			_k += 1
			if _k >= nz:
				_etape = 1
				_k = 0
				_octets = PackedByteArray()
		else:
			_tableaux[_k] = _tableaux_tuile(_tuiles[_k])
			_k += 1
			if _k >= _tuiles.size():
				_etape = 2
				_k = 0
		if Time.get_ticks_usec() > fin_us:
			return


func _tableaux_tuile(t: Array) -> Array:
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var lignes: Array = []
	var cols: Array = []
	var i: int = t[0]
	while true:
		lignes.append(i)
		if i >= t[1]:
			break
		i = mini(i + _pas, t[1])
	var j: int = t[2]
	while true:
		cols.append(j)
		if j >= t[3]:
			break
		j = mini(j + _pas, t[3])
	var w: int = cols.size()
	for ii in lignes:
		for jj in cols:
			verts.append(Vector3(ReliefDonnees.X_OUEST + jj * _dx, _h[ii * nx + jj],
				ReliefDonnees.Z_NORD + ii * _dz))
			uvs.append(Vector2(float(jj) / (nx - 1), float(ii) / (nz - 1)))
	for a_i in range(lignes.size() - 1):
		for a_j in range(w - 1):
			var a: int = a_i * w + a_j
			idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Fil principal : quelques tuiles par image, puis socle, tracés, lieux.
func _creer_maillages(fin_us: int) -> void:
	if _mat_terrain == null:
		_mat_terrain = _shader(SHADER_TERRAIN)
		var img: Image = (load("res://textures/relief_ortho.jpg") as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_width() > _ortho_l:
			img.resize(_ortho_l, int(img.get_height() * float(_ortho_l) / img.get_width()),
				Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		_mat_terrain.set_shader_parameter("ortho", ImageTexture.create_from_image(img))
		_mat_terrain.set_shader_parameter("gamma", _gamma())
	while _k < _tableaux.size():
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _tableaux[_k])
		mesh.surface_set_material(0, _mat_terrain)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tableaux[_k] = null
		_k += 1
		if Time.get_ticks_usec() > fin_us:
			return
	_build_socle()
	_build_trace()
	_build_trace(true)
	_build_puits()
	_build_lieux()
	_tableaux.clear()
	_etape = 3
	pret = true
	print("[Relief] prêt")


## Altitude du terrain (m) au point (x, z) du repère du jeu, bilinéaire.
func hauteur(x: float, z: float) -> float:
	if _etape < 1:            # altitudes pas encore décodées
		return -INF
	var fx: float = clampf((x - ReliefDonnees.X_OUEST) / _dx, 0.0, ReliefDonnees.NX - 1.001)
	var fz: float = clampf((z - ReliefDonnees.Z_NORD) / _dz, 0.0, ReliefDonnees.NZ - 1.001)
	var i: int = int(fz)
	var j: int = int(fx)
	var u: float = fx - j
	var v: float = fz - i
	var n: int = ReliefDonnees.NX
	return lerpf(lerpf(_h[i * n + j], _h[i * n + j + 1], u),
		lerpf(_h[(i + 1) * n + j], _h[(i + 1) * n + j + 1], u), v)


## Ouvre le terrain autour de `centre` (la rame), d'un rayon `r`.
func set_trou(centre: Vector3, r: float) -> void:
	for m in _mats:
		m.set_shader_parameter("trou_centre", centre)
		m.set_shader_parameter("trou_r", r)
	if _puits != null:
		# puits jusqu'à 60 m sous la rame, fermé par un fond de roche
		var fond: float = centre.y - 60.0
		_puits.transform = Transform3D(Basis.from_scale(Vector3(r, 3800.0 - fond, r)),
			Vector3(centre.x, fond, centre.z))


func _gamma() -> float:
	return GAMMA_WEB if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0


func _shader(code: String) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = code
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	_mats.append(m)
	return m


## Le relief n'est qu'une surface : sous elle, rien. On le pose sur un
## bloc (socle à Y_SOCLE et quatre flancs) comme une maquette, pour que le
## « trou » autour de la rame donne sur de la roche et non sur le ciel.
func _build_socle() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var sh: Shader = Shader.new()
	sh.code = SHADER_SOCLE
	mat.shader = sh
	mat.set_shader_parameter("gamma", _gamma())
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var bords: Array = []
	var b0: Array = []
	var b1: Array = []
	var b2: Array = []
	var b3: Array = []
	for j in range(nx):
		b0.append(Vector2i(0, j))
		b2.append(Vector2i(nz - 1, nx - 1 - j))
	for i in range(nz):
		b1.append(Vector2i(i, nx - 1))
		b3.append(Vector2i(nz - 1 - i, 0))
	bords = [b0, b1, b2, b3]
	for bord in bords:
		for k in range(bord.size() - 1):
			var a: Vector2i = bord[k]
			var b: Vector2i = bord[k + 1]
			var pa: Vector3 = Vector3(ReliefDonnees.X_OUEST + a.y * _dx, _h[a.x * nx + a.y], ReliefDonnees.Z_NORD + a.x * _dz)
			var pb: Vector3 = Vector3(ReliefDonnees.X_OUEST + b.y * _dx, _h[b.x * nx + b.y], ReliefDonnees.Z_NORD + b.x * _dz)
			var qa: Vector3 = Vector3(pa.x, Y_SOCLE, pa.z)
			var qb: Vector3 = Vector3(pb.x, Y_SOCLE, pb.z)
			for v in [pa, pb, qb, pa, qb, qa]:
				st.add_vertex(v)
	var c0: Vector3 = Vector3(ReliefDonnees.X_OUEST, Y_SOCLE, ReliefDonnees.Z_NORD)
	var c1: Vector3 = Vector3(ReliefDonnees.X_EST, Y_SOCLE, ReliefDonnees.Z_NORD)
	var c2: Vector3 = Vector3(ReliefDonnees.X_EST, Y_SOCLE, ReliefDonnees.Z_SUD)
	var c3: Vector3 = Vector3(ReliefDonnees.X_OUEST, Y_SOCLE, ReliefDonnees.Z_SUD)
	for v in [c0, c1, c2, c0, c2, c3]:
		st.add_vertex(v)
	st.set_material(mat)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Socle"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_puits() -> void:
	var img: Image = Image.create_from_data(ReliefDonnees.NX, ReliefDonnees.NZ, false,
		Image.FORMAT_RF, _h.to_byte_array())
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var mat: ShaderMaterial = ShaderMaterial.new()
	var sh: Shader = Shader.new()
	sh.code = SHADER_PUITS
	mat.shader = sh
	mat.set_shader_parameter("hauteurs", tex)
	mat.set_shader_parameter("emprise", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
		ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
	mat.set_shader_parameter("gamma", _gamma())
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 72
	for i in range(n):
		var a0: float = TAU * i / n
		var a1: float = TAU * (i + 1) / n
		var p00: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var p10: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var p01: Vector3 = p00 + Vector3.UP
		var p11: Vector3 = p10 + Vector3.UP
		for v in [p00, p10, p11, p00, p11, p01]:
			st.add_vertex(v)
		for v in [Vector3.ZERO, p10, p00]:      # fond
			st.add_vertex(v)
	st.set_material(mat)
	_puits = MeshInstance3D.new()
	_puits.name = "Puits"
	_puits.mesh = st.commit()
	# la tuile reste visible quelle que soit l'échelle (AABB généreuse)
	_puits.extra_cull_margin = 4000.0
	_puits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puits)


## Tracé du tunnel en surface : ruban orange posé sur le relief au-dessus de
## la voie, de portail à portail.
func _build_trace(en_profondeur: bool = false) -> void:
	# en profondeur : le tunnel lui-même, à son altitude, vu à travers la
	# montagne dans la zone « rayons X » autour de la rame (ailleurs le
	# relief le cache)
	var mat: ShaderMaterial
	if en_profondeur:
		mat = ShaderMaterial.new()
		var sh: Shader = Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
void fragment() {
	ALBEDO = vec3(1.0, 0.62, 0.12);
}
"""
		mat.shader = sh
	else:
		mat = _shader(SHADER_TRACE)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_g: Vector3 = Vector3.ZERO
	var prev_d: Vector3 = Vector3.ZERO
	var s: float = 0.0
	var premier: bool = true
	while s <= PNConstants.LENGTH + 0.01:
		var xf: Transform3D = tunnel.transform_at(minf(s, PNConstants.LENGTH))
		var dr: Vector3 = xf.basis.x
		dr.y = 0.0
		dr = dr.normalized() * 5.0
		var p: Vector3 = xf.origin
		var g: Vector3 = p - dr
		var d: Vector3 = p + dr
		# 8 m au-dessus du relief : le maillage (triangles de 25 m) s'écarte
		# de quelques mètres de l'interpolation bilinéaire sur les pentes
		if en_profondeur:
			# sous la voie (la rame et le tube restent visibles au-dessus),
			# 3 m de large
			g = p - dr * 0.3 + Vector3(0.0, -2.2, 0.0)
			d = p + dr * 0.3 + Vector3(0.0, -2.2, 0.0)
		else:
			g.y = hauteur(g.x, g.z) + 8.0
			d.y = hauteur(d.x, d.z) + 8.0
		if not premier:
			for v in [prev_g, prev_d, d, prev_g, d, g]:
				st.add_vertex(v)
		prev_g = g
		prev_d = d
		premier = false
		s += 10.0
	st.set_material(mat)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "TunnelProfond" if en_profondeur else "TraceTunnel"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_lieux() -> void:
	for l in ReliefDonnees.LIEUX:
		var lab: Label3D = Label3D.new()
		var nom: String = l[0]
		lab.text = nom if int(l[3]) == 0 else "%s\n%d m" % [nom, int(l[3])]
		lab.font_size = 34
		lab.outline_size = 10
		lab.modulate = Color(1.0, 1.0, 1.0)
		lab.outline_modulate = Color(0.05, 0.08, 0.15)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0009
		lab.no_depth_test = true
		lab.render_priority = 2
		lab.position = Vector3(l[1], hauteur(l[1], l[2]) + 40.0, l[2])
		add_child(lab)
