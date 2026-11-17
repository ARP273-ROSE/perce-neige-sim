class_name ReliefBuilder
extends Node3D
## Vue extérieure : le VRAI massif autour du funiculaire, et le tunnel vu
## « aux rayons X » à travers la montagne.
##
## Historique : 06/10/2026, un puits autour de la rame (« 3 m après le
## départ, la vue panoramique du haut, statique, en lévitation ») ; 07/10,
## un écorché (« au lieu d'un éclaté, diminue l'opacité du sol autour du
## tunnel pour le voir en entier ») ; puis un couloir de sol translucide —
## mais à travers on voyait le vide sous la surface (« la zone marron qui
## entoure le trajet, c'est moche, et on ne voit pas les sommets juste à
## côté et au-dessus »).
##
## Maintenant le relief est OPAQUE (on voit les sommets) et c'est le tunnel
## qui se dessine à travers lui :
##  - bloc détaillé : IGN RGE ALTI à 25 m + orthophoto IGN, 8,6 × 10,2 km, du
##    sommet de la Grande Motte au lac de Tignes (tools_relief3d.py) ;
##  - anneau lointain jusqu'à l'horizon : 44 × 44 km, maille 200 m, rotondité
##    de la Terre, orthophoto IGN, brume de distance
##    (tools_relief_lointain.py) ;
##  - le tunnel EN ENTIER : un trait ambre suit son axe de bout en bout, de
##    largeur constante à l'écran, en deux passes — plein là où il est à
##    découvert, à 45 % à travers la montagne ; interrompu à la place des
##    rames et effacé près de la caméra, où l'on voit le vrai tube ;
##  - vu de dessous (caméra sous la voie, sous la montagne), le relief est
##    assombri ;
##  - les lieux nommés.
## N'existe qu'en vue extérieure (main.gd). Aucune contrainte sur la caméra.

const CHUNK: int = 64                 # mailles par côté de tuile (frustum culling)
const GAMMA_WEB: float = 0.625        # rendu Compatibility : voir MachineRoomBuilder
const Y_SOCLE: float = 1550.0
const BRUME: Color = Color(0.50, 0.62, 0.78)   # linéaire (≈ 0,73 0,81 0,90 en sRGB)
## Sol du bloc détaillé (opaque ; dessous assombri). Deux usages :
## - les tuiles du bloc (piece = 0) : percées aux emplacements des pièces
##   fines des gares (`pieces`, rectangles x0, z0, x1, z1) ;
## - les pièces fines elles-mêmes (piece = 1) : percées là où se trouvent
##   les bâtiments (masque `trous`, posé sur leur rectangle `emprise`).
const SHADER_TERRAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D trous : filter_nearest, repeat_disable;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
uniform vec4 pieces[12];
uniform int n_pieces = 0;
uniform sampler2D masque_tkd : filter_nearest, repeat_disable;
uniform vec4 tkd_axe[8];            // traces damées des TKD (CouloirsTkd) : origine x, z, direction x, z
uniform vec4 tkd_dim[8];            // longueur, demi-largeur de la bande, rangées de l'atlas (v0, v1)
uniform int n_tkd = 0;
uniform sampler2D masque_gares : filter_nearest, repeat_disable;
uniform vec4 bloc_masque = vec4(0.0, 0.0, 1.0, 1.0);
uniform float avec_masque = 0.0;
uniform float piece = 0.0;
uniform vec4 emprise = vec4(0.0, 0.0, 1.0, 1.0);
varying vec3 pw;
uniform float hiver = 0.0;          // skieur : neige, relief ombré
uniform float leger = 0.0;          // crans ≥ 3 : sans grain ni détail de près
uniform sampler2D pistes : filter_linear, repeat_disable;
uniform float avec_pistes = 0.0;
uniform vec3 soleil = vec3(0.40, 0.78, 0.48);
varying vec3 nw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nw = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
// Hiver (skieur jouable) : neige partout sauf sur la roche raide (> ~45°)
// et sous 1 800 m ; pistes damées (masque OSM) toujours enneigées ; relief
// ombré par le soleil fixe des gares (même loi que GareAmont).
float hache(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hache(i), hache(i + vec2(1.0, 0.0)), f.x),
		mix(hache(i + vec2(0.0, 1.0)), hache(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 en_hiver(vec3 c, vec2 uv, vec3 cam) {
	vec3 n = normalize(nw);
	float dam = avec_pistes > 0.5 ? texture(pistes, uv).r : 0.0;
	float neige = smoothstep(0.62, 0.80, n.y) * smoothstep(1750.0, 1950.0, pw.y);
	neige = max(neige, dam);
	// ombrage marqué (la neige ne se lit que par ses ombres)
	float l = 0.36 + 0.74 * max(dot(n, normalize(soleil)), 0.0);
	// hors-piste : gris bleuté, avec le grain de la photo (bosses, rochers
	// affleurants) ; piste damée : blanc net
	float grain = dot(c, vec3(0.30, 0.59, 0.11));
	vec3 poudre = vec3(0.74, 0.79, 0.88) * (0.74 + 0.36 * grain);
	vec3 blanc = mix(poudre, vec3(0.97, 0.98, 1.0), dam);
	// grain de la neige près de l'œil (sensation de vitesse), effacé au loin
	// (12 sinus par pixel : calculé seulement à moins de 350 m, et pas en mode léger)
	float pres = clamp(1.0 - distance(pw, cam) / 350.0, 0.0, 1.0) * (1.0 - leger);
	if (pres > 0.0) {
		vec2 q = mod(pw.xz, 1024.0);
		float g = 0.5 * bruit(q * 0.5) + 0.3 * bruit(q * 2.0) + 0.2 * bruit(q * 0.07);
		blanc *= 1.0 + (g - 0.5) * 0.16 * pres;
	}
	return mix(c, mix(c * 0.80, blanc, neige) * l, hiver);
}
void fragment() {
	if (piece < 0.5) {
		for (int i = 0; i < n_pieces; i++) {
			vec4 r = pieces[i];
			if (pw.x > r.x && pw.x < r.z && pw.z > r.y && pw.z < r.w) {
				discard;
			}
		}
		if (avec_masque > 0.5 && texture(masque_gares, (pw.xz - bloc_masque.xy) / (bloc_masque.zw - bloc_masque.xy)).r > 0.5) {
			discard;
		}
		// sous les traces damées des TKD (déblai) : le couloir prend la place
		for (int i = 0; i < n_tkd; i++) {
			vec2 o = pw.xz - tkd_axe[i].xy;
			float sa = dot(o, tkd_axe[i].zw);
			float ta = dot(o, vec2(-tkd_axe[i].w, tkd_axe[i].z));
			if (sa > 0.0 && sa < tkd_dim[i].x && abs(ta) < tkd_dim[i].y) {
				vec2 uvm = vec2(sa / tkd_dim[i].x, mix(tkd_dim[i].z, tkd_dim[i].w, ta / tkd_dim[i].y * 0.5 + 0.5));
				if (texture(masque_tkd, uvm).r > 0.5) {
					discard;
				}
			}
		}
	} else if (texture(trous, (pw.xz - emprise.xy) / (emprise.zw - emprise.xy)).r > 0.5) {
		discard;
	}
	vec3 c = texture(ortho, UV).rgb;
	if (hiver > 0.0) {
		c = en_hiver(c, UV, CAMERA_POSITION_WORLD);
	}
	if (!FRONT_FACING) {
		c *= 0.45;                     // dessous du relief (caméra sous la surface)
	}
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
}
"""
## Flancs du bloc détaillé : prolongent sa bordure (couleur de l'orthophoto
## au bord) jusque sous l'anneau lointain.
const SHADER_FLANC: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
varying vec3 pw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
uniform vec4 bloc;                 // emprise du bloc détaillé
void fragment() {
	// caméra dans le bloc (sous la montagne) : on les verrait de l'intérieur
	vec3 cam = CAMERA_POSITION_WORLD;
	if (cam.x > bloc.x && cam.x < bloc.z && cam.z > bloc.y && cam.z < bloc.w) {
		discard;
	}
	float d = distance(pw, cam);
	ALBEDO = pow(mix(texture(ortho, UV).rgb * 0.85, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)),
		vec3(gamma));
}
"""
const SHADER_LOINTAIN: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform sampler2D ortho : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 bloc;                 // emprise du bloc détaillé (trou de l'anneau)
uniform float gamma = 1.0;
uniform vec3 brume = vec3(0.50, 0.62, 0.78);
varying vec3 pw;
uniform float hiver = 0.0;          // skieur : neige, relief ombré
uniform float leger = 0.0;          // crans ≥ 3 : sans grain ni détail de près
uniform sampler2D pistes : filter_linear, repeat_disable;
uniform float avec_pistes = 0.0;
uniform vec3 soleil = vec3(0.40, 0.78, 0.48);
varying vec3 nw;
void vertex() {
	pw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nw = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
// Hiver (skieur jouable) : neige partout sauf sur la roche raide (> ~45°)
// et sous 1 800 m ; pistes damées (masque OSM) toujours enneigées ; relief
// ombré par le soleil fixe des gares (même loi que GareAmont).
float hache(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hache(i), hache(i + vec2(1.0, 0.0)), f.x),
		mix(hache(i + vec2(0.0, 1.0)), hache(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 en_hiver(vec3 c, vec2 uv, vec3 cam) {
	vec3 n = normalize(nw);
	float dam = avec_pistes > 0.5 ? texture(pistes, uv).r : 0.0;
	float neige = smoothstep(0.62, 0.80, n.y) * smoothstep(1750.0, 1950.0, pw.y);
	neige = max(neige, dam);
	// ombrage marqué (la neige ne se lit que par ses ombres)
	float l = 0.36 + 0.74 * max(dot(n, normalize(soleil)), 0.0);
	// hors-piste : gris bleuté, avec le grain de la photo (bosses, rochers
	// affleurants) ; piste damée : blanc net
	float grain = dot(c, vec3(0.30, 0.59, 0.11));
	vec3 poudre = vec3(0.74, 0.79, 0.88) * (0.74 + 0.36 * grain);
	vec3 blanc = mix(poudre, vec3(0.97, 0.98, 1.0), dam);
	// grain de la neige près de l'œil (sensation de vitesse), effacé au loin
	// (12 sinus par pixel : calculé seulement à moins de 350 m, et pas en mode léger)
	float pres = clamp(1.0 - distance(pw, cam) / 350.0, 0.0, 1.0) * (1.0 - leger);
	if (pres > 0.0) {
		vec2 q = mod(pw.xz, 1024.0);
		float g = 0.5 * bruit(q * 0.5) + 0.3 * bruit(q * 2.0) + 0.2 * bruit(q * 0.07);
		blanc *= 1.0 + (g - 0.5) * 0.16 * pres;
	}
	return mix(c, mix(c * 0.80, blanc, neige) * l, hiver);
}
void fragment() {
	if (pw.x > bloc.x && pw.x < bloc.z && pw.z > bloc.y && pw.z < bloc.w) {
		discard;
	}
	vec3 c = texture(ortho, UV).rgb;
	if (hiver > 0.0) {
		c = en_hiver(c, UV, CAMERA_POSITION_WORLD);
	}
	if (!FRONT_FACING) {
		c *= 0.45;
	}
	float d = distance(pw, CAMERA_POSITION_WORLD);
	ALBEDO = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
}
"""
## Trait du tunnel : ruban tourné vers la caméra le long de l'axe (sommets
## posés sur l'axe, NORMAL = tangente, UV.x = côté, UV.y = abscisse s),
## ≈ 3 px de large. Deux passes : %s = mode de rendu (la passe « rayons X »
## ignore la profondeur), %s = opacité. Interrompu à la place des deux
## rames (on y voit leur silhouette) et effacé à moins de 40-160 m de la
## caméra (on y voit le vrai tube).
const SHADER_TRAIT: String = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, world_vertex_coords%s;
uniform vec4 couleur : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform float px_rad = 0.0022;     // demi-largeur ≈ distance × px_rad
uniform float s_rame1 = -1000.0;
uniform float s_rame2 = -1000.0;
varying float fondu;
void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float d = distance(VERTEX, cam);
	vec3 cote = normalize(cross(NORMAL, normalize(cam - VERTEX)));
	VERTEX += cote * UV.x * max(0.12, d * px_rad);
	fondu = smoothstep(40.0, 160.0, d)
		* smoothstep(18.0, 26.0, min(abs(UV.y - s_rame1), abs(UV.y - s_rame2)));
}
void fragment() {
	ALBEDO = couleur.rgb;
	ALPHA = %s * fondu;
}
"""

var tunnel: TunnelBuilder = null
var _h: PackedFloat32Array = PackedFloat32Array()
var fin: ReliefFin = null               # essai : zone à 4 m, voir ReliefFin
var _cran_depart: int = 0
var _dx: float = 1.0
var _dz: float = 1.0
## Prêt à être affiché (construction terminée).
var pret: bool = false

# --- Construction EN TÂCHE DE FOND (optimisation du 06/10/2026 : « un beau
# truc qui ne consomme pas énormément de ressources ») -------------------
# 1. préparation des données (décodage des altitudes, sommets et indices de
#    chaque tuile, bloc détaillé puis anneau lointain) : sur PC dans un fil
#    parallèle (WorkerThreadPool) ; dans la PWA, qui n'a pas de fils, par
#    tranches de 3 ms par image sur le fil principal ;
# 2. maillages (appels au moteur de rendu) : fil principal, quelques
#    tuiles par image.
# Aucun gel au démarrage ; le relief apparaît en vue extérieure dès qu'il
# est prêt (≈ 1 s).
# Résolution selon la machine (cran du PerfManager) : maille de 25 m et
# orthophotos 2048 px pour une bonne carte graphique ; maille de 50 m
# (4 fois moins de triangles) et orthophotos 1024 px sinon.
const BUDGET_US: int = 3000
var _pas: int = 1                     # 1 = 25 m, 2 = 50 m
var _ortho_l: int = 2048
var _etape: int = 0                   # 0 décodage, 1 tuiles, 2 maillages, 3 fini
var _k: int = 0                       # avancement dans l'étape
var _octets: PackedByteArray = PackedByteArray()
var _octets_loin: PackedByteArray = PackedByteArray()
var _hl: PackedFloat32Array = PackedFloat32Array()   # anneau lointain
var _tuiles: Array = []               # [i0, i1, j0, j1, lointain]
var _tableaux: Array = []             # tableaux de sommets prêts
var _tache: int = -1
var _mat_terrain: ShaderMaterial = null
var _mat_loin: ShaderMaterial = null
var _tex_ortho: ImageTexture = null
var _mat_trait: ShaderMaterial = null

# --- aménagements des gares : pièces de terrain fines -------------------------
## Posé par main.gd avant la fin de la construction : une entrée par gare,
## {"rect": Rect2 (x, z, largeur, profondeur), "trous": [PackedVector2Array]
## (bâtiments : terrain retiré), "plats": [[PackedVector2Array, y, fondu]]
## (place, escalier : terrain aplani à y, raccordé sur `fondu` m),
## "remblais": [[PackedVector2Array, y, fondu]] (devant une porte : terrain
## remonté à y, jamais abaissé),
## "rabots": [[PackedVector2Array, y, fondu]] (terrasse : terrain rasé
## au-dessous de y),
## "rampes": [[Vector3 bas, Vector3 haut, demi_largeur, fondu]] (tapis couverts : terrain mis à la pente continue
## du bas au haut dans le couloir, raccordé sur `fondu` m),
## "couloirs": [[s0, s1, demi_largeur, couverture, fondu = 10 m]] (quais
## souterrains : terrain relevé à au moins `couverture` m au-dessus du
## plafond de la salle)}. Le relief IGN maillé à 25 m traversait les bâtiments et les
## quais (« le relief rentre dans le bâtiment et les quais », 07/10/2026).
var amenagements: Array = []
var amenagements_poses: bool = false    # les gares du funiculaire y sont
## Callables appelés au fil principal juste avant les pièces fines, quand
## hauteur() répond : chacun rend un aménagement (ou {}).
var amenageurs: Array = []
var gares_plain_pied: int = 0
var pieces_groupees: int = 0
var _trait: Node3D = null
var _trait_on: bool = true
const PAS_PIECE: float = 2.0
var _rects_pieces: Array = []
var _pieces: Array = []               # [rect, nx, nz, hauteurs, masque] (bancs)


func build(t: TunnelBuilder, cran: int = 0) -> void:
	tunnel = t
	for k in range(PALIERS.size()):
		amenageurs.append(_amenagement_palier.bind(k))
	amenageurs.append(_amenagements_gares_plain_pied)
	_cran_depart = cran
	_pas = 1 if cran <= 2 else 2
	# 21 km d'emprise depuis le 09/10/2026 (Tignes – Val d'Isère) : 4096 px =
	# 5,1 m/px sur une bonne machine ; 2048 px (10 m/px) sinon et sur le web
	_ortho_l = 4096 if cran <= 2 else 2048
	# (photo au mètre du pack : celle-ci ne sert plus qu'au loin, à plus de 16 m par texel)
	if ReliefFin.voulu(cran) and ReliefFin.niveau_hd() > 0 and FileAccess.file_exists(ReliefFin.dossier_pack().path_join("ortho.pnhd")):
		_ortho_l = 2048
	_octets = _octets_png("res://textures/relief_hauteurs.png")
	_octets_loin = _octets_png("res://textures/relief_lointain_hauteurs.png")
	_h.resize(ReliefDonnees.NX * ReliefDonnees.NZ)
	_hl.resize(ReliefLointainDonnees.N * ReliefLointainDonnees.N)
	_dx = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / float(ReliefDonnees.NX - 1)
	_dz = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / float(ReliefDonnees.NZ - 1)
	var i0: int = 0
	while i0 < ReliefDonnees.NZ - 1:
		var j0: int = 0
		while j0 < ReliefDonnees.NX - 1:
			_tuiles.append([i0, mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1),
				j0, mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1), false])
			j0 = mini(j0 + CHUNK * _pas, ReliefDonnees.NX - 1)
		i0 = mini(i0 + CHUNK * _pas, ReliefDonnees.NZ - 1)
	# anneau lointain : 4 × 4 tuiles
	var nl: int = ReliefLointainDonnees.N
	var cl: int = int(ceil((nl - 1) / 4.0))
	for a in range(4):
		for b in range(4):
			_tuiles.append([a * cl, mini((a + 1) * cl, nl - 1), b * cl, mini((b + 1) * cl, nl - 1), true])
	_tableaux.resize(_tuiles.size())
	visible = false
	if OS.has_feature("threads"):
		_tache = WorkerThreadPool.add_task(_preparer_tout, false, "relief")
	print("[Relief] maille %d m, orthophoto %d px, %d tuiles, préparation %s" % [
		25 * _pas, _ortho_l, _tuiles.size(),
		"en parallèle" if _tache >= 0 else "par tranches"])


func _octets_png(chemin: String) -> PackedByteArray:
	var img: Image = (load(chemin) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	return img.get_data()


## Quitter pendant le chargement : le fil de préparation finit avant que le nœud disparaisse.
## (Il crée des textures : ces appels attendent le fil principal, qu'une attente simple figerait
## pour toujours. D'où la boucle, qui les laisse passer.)
func _exit_tree() -> void:
	amenagements_poses = true
	if _tache >= 0:
		while not WorkerThreadPool.is_task_completed(_tache):
			RenderingServer.force_sync()
			OS.delay_msec(1)
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("relief_builder", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(_delta: float) -> void:
	if _etape >= 3:
		if _f_active:
			_fenetre_pas(_delta)
		else:
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
			# décodage, une ligne de la grille à la fois : bloc détaillé,
			# puis anneau lointain
			if _k < nz:
				var base: int = _k * nx
				for j in range(nx):
					var o: int = 3 * (base + j)
					_h[base + j] = ReliefDonnees.H_BASE \
						+ float(int(_octets[o]) * 256 + int(_octets[o + 1])) * ReliefDonnees.H_ECHELLE
			else:
				_decoder_ligne_lointaine(_k - nz)
			_k += 1
			if _k >= nz + ReliefLointainDonnees.N:
				var seules: bool = ReliefFin.normales_voulues(_cran_depart)
				var h0: PackedFloat32Array = _h.duplicate() if ReliefFin.voulu(_cran_depart) or seules else PackedFloat32Array()
				_creuser_gares()
				if seules:
					var rn: ReliefFin = ReliefFin.new()
					rn.preparer_normales(self, h0)
					if rn.pret:
						_normales_seules = rn
				elif not h0.is_empty():
					var rf: ReliefFin = ReliefFin.new()
					rf.preparer(self, h0)
					if rf.pret:
						fin = rf
				_etape = 1
				_k = 0
				_octets = PackedByteArray()
				_octets_loin = PackedByteArray()
		else:
			var t: Array = _tuiles[_k]
			_tableaux[_k] = _tableaux_lointain(t) if t[4] else _tableaux_tuile(t)
			_k += 1
			if _k >= _tuiles.size():
				# images de l'orthophoto préparées ici (fil de travail quand il
				# y en a un) : au fil principal, l'envoi seul
				_img_ortho = _image_ortho("res://textures/relief_ortho.jpg")
				_img_loin = _image_ortho("res://textures/relief_lointain.jpg")
				_etape = 2
				_k = 0
		if Time.get_ticks_usec() > fin_us:
			return


## Ligne i de l'anneau lointain ; dans le bloc détaillé et sur une maille
## autour, ses sommets prennent l'altitude du bloc (raccord sans marche).
func _decoder_ligne_lointaine(i: int) -> void:
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var z: float = ReliefLointainDonnees.Z_NORD + i * pas
	for j in range(n):
		var o: int = 3 * (i * n + j)
		var x: float = ReliefLointainDonnees.X_OUEST + j * pas
		var hh: float = float(int(_octets_loin[o]) * 256 + int(_octets_loin[o + 1])) \
			* ReliefLointainDonnees.H_ECHELLE
		if x > ReliefDonnees.X_OUEST - pas and x < ReliefDonnees.X_EST + pas \
				and z > ReliefDonnees.Z_NORD - pas and z < ReliefDonnees.Z_SUD + pas:
			hh = _hauteur_bloc(x, z)
		_hl[i * n + j] = hh


func _tableaux_tuile(t: Array) -> Array:
	var st: Dictionary = _tuile_debut(t)
	_tuile_pas(st, 1 << 62)
	return _tuile_fin(st)


## Tuile du bloc détaillé en étapes reprenables (fenêtre fine de la PWA : par tranches de BUDGET_US) :
## _tuile_debut, puis _tuile_pas jusqu'à vrai, puis _tuile_fin.
func _tuile_debut(t: Array) -> Dictionary:
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
	return {"lignes": lignes, "cols": cols, "verts": PackedVector3Array(), "uvs": PackedVector2Array(),
		"normales": PackedVector3Array(), "idx": PackedInt32Array(), "extra": {}, "ph": 0, "r": 0}


func _tuile_pas(st: Dictionary, fin_us: int) -> bool:
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var lignes: Array = st["lignes"]
	var cols: Array = st["cols"]
	var w: int = cols.size()
	var verts: PackedVector3Array = st["verts"]
	var uvs: PackedVector2Array = st["uvs"]
	var normales: PackedVector3Array = st["normales"]
	var idx: PackedInt32Array = st["idx"]
	var extra: Dictionary = st["extra"]          # nœud intermédiaire (mailles redécoupées) → sommet
	# (sorties de l'état le temps du pas : sinon chaque ajout recopiait le tableau partagé)
	st["verts"] = null
	st["uvs"] = null
	st["normales"] = null
	st["idx"] = null
	var fini: bool = false
	while true:
		if st["ph"] == 0:
			# sommets de la grille de la tuile, une ligne à la fois
			var ii: int = lignes[st["r"]]
			for jj in cols:
				verts.append(Vector3(ReliefDonnees.X_OUEST + jj * _dx, _h[ii * nx + jj],
					ReliefDonnees.Z_NORD + ii * _dz))
				uvs.append(Vector2(float(jj) / (nx - 1), float(ii) / (nz - 1)))
				normales.append(_normale_grille(_h, nx, nz, ii, jj, _dx, _dz))
			st["r"] += 1
			if st["r"] >= lignes.size():
				st["ph"] = 1
				st["r"] = 0
		else:
			if st["r"] >= lignes.size() - 1:
				fini = true
				break
			var a_i: int = st["r"]
			for a_j in range(w - 1):
				var a: int = a_i * w + a_j
				var ia: int = lignes[a_i]
				var ja: int = cols[a_j]
				if _pas > 1 and lignes[a_i + 1] - ia == _pas and cols[a_j + 1] - ja == _pas \
						and raffine_maille(ia / _pas, ja / _pas):
					# maille redécoupée : quatre carrés de 25 m, même découpe
					var ids: Array = []
					for di in range(_pas + 1):
						for dj in range(_pas + 1):
							if di % _pas == 0 and dj % _pas == 0:
								ids.append(a + (di / _pas) * w + dj / _pas)
								continue
							var kk: int = (ia + di) * nx + ja + dj
							if not extra.has(kk):
								extra[kk] = verts.size()
								verts.append(Vector3(ReliefDonnees.X_OUEST + (ja + dj) * _dx, _h[kk], ReliefDonnees.Z_NORD + (ia + di) * _dz))
								uvs.append(Vector2(float(ja + dj) / (nx - 1), float(ia + di) / (nz - 1)))
								normales.append(_normale_grille(_h, nx, nz, ia + di, ja + dj, _dx, _dz))
							ids.append(extra[kk])
					var m: int = _pas + 1
					for si in range(_pas):
						for sj in range(_pas):
							var q0: int = ids[si * m + sj]
							var q1: int = ids[si * m + sj + 1]
							var q2: int = ids[(si + 1) * m + sj]
							var q3: int = ids[(si + 1) * m + sj + 1]
							idx.append_array(PackedInt32Array([q0, q1, q2, q1, q3, q2]))
					continue
				idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
			st["r"] += 1
		if Time.get_ticks_usec() > fin_us:
			break
	st["verts"] = verts
	st["uvs"] = uvs
	st["normales"] = normales
	st["idx"] = idx
	return fini


func _tuile_fin(st: Dictionary) -> Array:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = st["verts"]
	arr[Mesh.ARRAY_NORMAL] = st["normales"]
	arr[Mesh.ARRAY_TEX_UV] = st["uvs"]
	arr[Mesh.ARRAY_INDEX] = st["idx"]
	return arr


## Normale (lissée) d'un nœud de grille d'altitudes, par différences
## centrées : ombrage du relief en hiver (skieur).
static func _normale_grille(h: PackedFloat32Array, nx: int, nz: int, i: int, j: int,
		dx: float, dz: float) -> Vector3:
	var j0: int = maxi(j - 1, 0)
	var j1: int = mini(j + 1, nx - 1)
	var i0: int = maxi(i - 1, 0)
	var i1: int = mini(i + 1, nz - 1)
	var gx: float = (h[i * nx + j1] - h[i * nx + j0]) / (dx * (j1 - j0))
	var gz: float = (h[i1 * nx + j] - h[i0 * nx + j]) / (dz * (i1 - i0))
	return Vector3(-gx, 1.0, -gz).normalized()


## Tuile de l'anneau lointain : les carrés entièrement dans le bloc détaillé
## sont sautés (le nuanceur découpe exactement le bord).
func _tableaux_lointain(t: Array) -> Array:
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var w: int = t[3] - t[2] + 1
	var normales: PackedVector3Array = PackedVector3Array()
	for ii in range(t[0], t[1] + 1):
		for jj in range(t[2], t[3] + 1):
			verts.append(Vector3(ReliefLointainDonnees.X_OUEST + jj * pas, _hl[ii * n + jj],
				ReliefLointainDonnees.Z_NORD + ii * pas))
			uvs.append(Vector2(float(jj) / (n - 1), float(ii) / (n - 1)))
			normales.append(_normale_grille(_hl, n, n, ii, jj, pas, pas))
	for a_i in range(t[1] - t[0]):
		for a_j in range(w - 1):
			var x0: float = ReliefLointainDonnees.X_OUEST + (t[2] + a_j) * pas
			var z0: float = ReliefLointainDonnees.Z_NORD + (t[0] + a_i) * pas
			if x0 >= ReliefDonnees.X_OUEST and x0 + pas <= ReliefDonnees.X_EST \
					and z0 >= ReliefDonnees.Z_NORD and z0 + pas <= ReliefDonnees.Z_SUD:
				continue
			var a: int = a_i * w + a_j
			idx.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normales
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


var _img_ortho: Image = null
var _img_loin: Image = null


func _image_ortho(chemin: String) -> Image:
	# web : fichier déjà réduit, chargé comme image (ni envoi à la carte
	# graphique ni relecture) — cf. tools_textures_web.py
	var img: Image
	if OS.has_feature("web"):
		img = load(chemin.replace("res://textures/", "res://textures/web/")) as Image
	else:
		img = (load(chemin) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	# (mode allégé de la PWA : 25 Mo de moins, 03/11/2026)
	var larg: int = mini(_ortho_l, 1024) if PerfManager.secours_web > 0 else _ortho_l
	if img.get_width() > larg:
		img.resize(larg, int(img.get_height() * float(larg) / img.get_width()),
			Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## Fil principal : quelques tuiles par image, puis flancs, trait du
## tunnel, lieux.
func _creer_maillages(fin_us: int) -> void:
	if _pas_mat <= PAS_MAT_DERNIER:
		_materiaux_pas()
		return
	if fin != null and fin.hd and not fin.envoyer_couches(fin_us):
		return
	if _normales_seules != null and not _normales_seules.envoyer_couches(fin_us):
		return
	while _k < _tableaux.size():
		var arr: Array = _tableaux[_k]
		if (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, _mat_loin if _tuiles[_k][4] else _mat_terrain)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1 | Cabin.LAYER_RELIEF
			add_child(mi)
			if FENETRE > 0.0:
				if _mi_tuiles.size() != _tuiles.size():
					_mi_tuiles.resize(_tuiles.size())
				_mi_tuiles[_k] = mi
		_tableaux[_k] = null
		_k += 1
		if Time.get_ticks_usec() > fin_us:
			return
	while not _finition_pas():
		if Time.get_ticks_usec() > fin_us:
			return
	_tableaux.clear()
	_etape = 3
	pret = true
	print("[Relief] prêt")


var _tex_normales: Texture2DArrayRD = null
var _tex_ortho_hd: Texture2DArrayRD = null
var _h0_ref: PackedFloat32Array = PackedFloat32Array()   # banc du sol au mètre
var _hn5_ref: PackedFloat32Array = PackedFloat32Array()


## Une étape par image : réunies, elles faisaient une image de 250 ms en fin de chargement.
const PAS_MAT_DERNIER: int = 6
var _normales_seules: ReliefFin = null
var _detail_seul: bool = false
var _pas_mat: int = 0


func _materiaux_pas() -> void:
	match _pas_mat:
		0:
			_tex_ortho = ImageTexture.create_from_image(_img_ortho if _img_ortho != null
				else _image_ortho("res://textures/relief_ortho.jpg"))
		1:
			_detail_seul = (fin == null or not fin.hd) and _normales_seules == null and not OS.has_feature("web") and ClassDB.class_exists("ReliefHD")
			if _detail_seul:
				ReliefAnneaux.preparer_detail()
			_mat_terrain = _shader(ReliefAnneaux.code_hd(SHADER_TERRAIN) if (fin != null and fin.hd) or _normales_seules != null
				else ReliefAnneaux.code_detail(SHADER_TERRAIN) if _detail_seul else SHADER_TERRAIN)
			if _detail_seul:
				ReliefAnneaux.regler_detail_seul(_mat_terrain)
			_mat_terrain.set_shader_parameter("ortho", _tex_ortho)
		2:
			if fin != null and fin.hd:
				ReliefAnneaux.preparer_detail()
				_tex_normales = fin.normales_texture()
				_tex_ortho_hd = fin.ortho_texture()
				ReliefAnneaux.regler_hd(_mat_terrain, _tex_normales, _tex_ortho_hd)
			elif _normales_seules != null:
				ReliefAnneaux.preparer_detail()
				_tex_normales = _normales_seules.normales_texture()
				ReliefAnneaux.regler_hd(_mat_terrain, _tex_normales, null)
		3:
			_mat_loin = _shader(SHADER_LOINTAIN)
		4:
			_mat_loin.set_shader_parameter("ortho", ImageTexture.create_from_image(_img_loin if _img_loin != null
				else _image_ortho("res://textures/relief_lointain.jpg")))
			_img_ortho = null
			_img_loin = null
			_mat_loin.set_shader_parameter("bloc", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
				ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
		5:
			_hiver_mat(_mat_terrain, true)
		6:
			_hiver_mat(_mat_loin, false)
	_pas_mat += 1


## Fin du chargement, un morceau à la fois (ensemble : une image de 430 ms). Vrai quand tout est posé.
var _pas_fin: int = 0
var _pieces_us: int = 0
var _pieces_pire_us: int = 0
var _piece_en_cours: bool = false
var _t_piece: int = 0
const PIECE_US: int = 6000


var couloirs: CouloirsTkd = null
var _rects_couloirs: Array = []          # emprises des tronçons de trace (collisions : maillage fin à 2 m)
var _bandes_couloirs: Array = []
var _couloirs_us: int = 0
var _couloirs_pire_us: int = 0


## Une bande de trace damée (CouloirsTkd.maillages) : même matériau que les pièces fines.
func _build_bande_couloir(bd: Array) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: PackedVector3Array = bd[0]
	var uvs: PackedVector2Array = bd[1]
	for i in range(verts.size()):
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	for k in (bd[2] as PackedInt32Array):
		st.add_index(k)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var r: Rect2 = bd[3]
	mesh.surface_set_material(0, _materiau_piece(r, Image.create(1, 1, false, Image.FORMAT_L8)))
	_instance(mesh, "TraceTkd")
	_rects_couloirs.append_array(bd[4])


func _piece_etalee(am: Dictionary) -> void:
	await _build_piece(am, _pause_piece)
	_pieces_us += Time.get_ticks_usec() - _t_piece
	_pieces_pire_us = maxi(_pieces_pire_us, Time.get_ticks_usec() - _t_piece)
	_piece_en_cours = false


func _pause_piece() -> void:
	if Time.get_ticks_usec() - _t_piece > PIECE_US:
		_pieces_us += Time.get_ticks_usec() - _t_piece
		_pieces_pire_us = maxi(_pieces_pire_us, Time.get_ticks_usec() - _t_piece)
		await get_tree().process_frame
		_t_piece = Time.get_ticks_usec()
var _k_fin: int = 0


func _finition_pas() -> bool:
	match _pas_fin:
		0:
			# aménagements qui dépendent des altitudes (SortieSecours), avant les pièces
			if _k_fin < amenageurs.size():
				var am: Variant = (amenageurs[_k_fin] as Callable).call()
				if am is Dictionary and not (am as Dictionary).is_empty():
					amenagements.append(am)
				_k_fin += 1
				return false
			amenageurs.clear()
			_rects_pieces.clear()
			_rects_masque.clear()
			# traces damées des TKD (couloirs le long de leur axe), hors des pièces des gares
			var t0_c: int = Time.get_ticks_usec()
			couloirs = CouloirsTkd.new()
			couloirs.preparer(self, amenagements.map(func(am0: Dictionary) -> Rect2: return am0["rect"]))
			_couloirs_us = Time.get_ticks_usec() - t0_c
			_couloirs_pire_us = _couloirs_us
			_k_fin = 0
			_pas_fin = 1
		1:
			if _piece_en_cours:
				return false
			if _k_fin < amenagements.size():
				# étalée sur plusieurs images (PIECE_US au plus par image) : la pièce commune de cinq gares voisines
				# prenait 109 ms d'un bloc sur ce PC
				_piece_en_cours = true
				_t_piece = Time.get_ticks_usec()
				_piece_etalee(amenagements[_k_fin])
				_k_fin += 1
				return false
			print("[Relief] pièces fines : %d, %.0f ms en tout, pire tranche %.1f ms" % [amenagements.size(), _pieces_us / 1000.0, _pieces_pire_us / 1000.0])
			_poser_trous()
			_bandes_couloirs = couloirs.maillages() if couloirs != null else []
			_k_fin = 0
			_pas_fin = 7
		7:
			# un tronçon de trace damée par image
			if _k_fin < _bandes_couloirs.size():
				var t0_b: int = Time.get_ticks_usec()
				_build_bande_couloir(_bandes_couloirs[_k_fin])
				var dt_b: int = Time.get_ticks_usec() - t0_b
				_couloirs_us += dt_b
				_couloirs_pire_us = maxi(_couloirs_pire_us, dt_b)
				_k_fin += 1
				return false
			if couloirs != null:
				print("[Relief] traces damées des TKD : %d maillages, %d tronçons, %d sommets, %.0f ms en tout, pire tranche %.1f ms" % [
					couloirs.n_pieces, couloirs.n_troncons, couloirs.n_sommets, _couloirs_us / 1000.0, _couloirs_pire_us / 1000.0])
			_bandes_couloirs = []
			_poser_masque_tkd()
			_pas_fin = 2
		2:
			_build_flancs()
			_pas_fin = 3
		3:
			_build_trait()
			_pas_fin = 4
		4:
			_build_lieux()
			_pas_fin = 5
		5:
			if fin != null and fin.get_parent() == null:
				add_child(fin)
			if _normales_seules != null and _normales_seules.get_parent() == null:
				add_child(_normales_seules)
			_pas_fin = 6
		_:
			return true
	return false


## Altitude sur les triangles du maillage du bloc (comme les tuiles) : les
## pièces fines s'y raccordent sans marche.
func _hauteur_tri(x: float, z: float) -> float:
	if fin != null and fin.fine_ici(x, z):
		return fin.hauteur(x, z)
	if not _raffine.is_empty() and raffine_ici(x, z):
		return _tri_sur(_h, x, z, 1)
	return _tri_sur(_h, x, z)


## Maille à 50 m (PWA, crans bas) autour des gares de remontées : ses mailles y sont redécoupées à 25 m et
## prennent le sol pour lequel gares, quais et lignes sont réglés (grille à 25 m). À 50 m seulement, le sol
## affiché bombait de plusieurs mètres sous les gares : terrain dans la salle du 3S, sièges et cabines sous
## terre à quai, terrassements absurdes (retours d'utilisateur sur la PWA, 10/11/2026). Les nœuds au bord de
## la zone gardent le sol à 50 m : pas de fente avec les mailles voisines.
const RAFFINE_PLEIN: float = 8.0       # m autour de l'emprise de la gare : sol à 25 m
const RAFFINE_FONDU: float = 30.0
## Sous les lignes : écart toléré entre sol affiché à 50 m et sol à 25 m (m), pas d'échantillonnage (m).
const RAFFINE_ECART: float = 0.5
const RAFFINE_ECHANT: float = 10.0      # m de raccord vers le sol à 50 m
var _raffine: PackedByteArray = PackedByteArray()     # par maille de 50 m : 1 si redécoupée
var _raff_nx: int = 0


## --- Fenêtre fine autour du point de vue (PWA, maille à 50 m) -----------------------------------------------
## Demande d'utilisateur (16/11/2026) : « plus de détail du relief au moins autour de la position sur la PWA ». Les
## mailles de 50 m à moins de FENETRE m de la caméra sont redécoupées à 25 m comme autour des gares (même
## coutures : sol fondu vers la grille à 25 m, poids nul au bord, pas de fente), les tuiles touchées refaites
## par tranches de BUDGET_US quand la caméra s'est déplacée de plus d'un tiers du rayon. PWA : FENETRE_WEB par défaut ;
## --relief-fenetre=R (PC, maille à 50 m : crans ≥ 3) ou window.__pn_relief_fenetre = R (PWA).
static var FENETRE: float = _fenetre_voulue()
## Sol affiché changé dans `rect` (monde, x/z) : les objets posés au sol une fois pour toutes (jalons, panneaux) s'y
## reposent, d'après ecart_sol.
signal sol_modifie(rect: Rect2)
const FENETRE_FONDU: float = 150.0
const FENETRE_WEB: int = 800
## Bancs : point visé au lieu de la caméra (Vector3.INF : la caméra).
static var cible_fenetre: Vector3 = Vector3.INF
var _f_active: bool = false
var _h_aff0: PackedFloat32Array = PackedFloat32Array()     # sol affiché après les gares (référence)
var _raffine0: PackedByteArray = PackedByteArray()
var _mi_tuiles: Array = []
var _f_centre: Vector2 = Vector2.INF
var _f_cellules: PackedInt32Array = PackedInt32Array()       # mailles de 50 m de la fenêtre en place
var _f_job: Dictionary = {}
var _f_t: float = 0.0
## Relevés (bancs) : dernière reconstruction.
var fenetre_stats: Dictionary = {}


static func _fenetre_voulue() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relief-fenetre="):
			return maxf(0.0, float(a.substr(17)))
	if OS.has_feature("web"):
		# (800 m par défaut depuis le 16/11/2026 : essai WebKit tactile à 1 000 m, 106 Mo de tampons avec comme sans,
		# aucune perte de contexte ; window.__pn_relief_fenetre = 0 la coupe)
		return maxf(0.0, float(JavaScriptBridge.eval("window.__pn_relief_fenetre ?? %d" % FENETRE_WEB, true)))
	return 0.0


func _fenetre_initialiser() -> void:
	var p: int = _pas
	_raff_nx = (ReliefDonnees.NX - 1) / p
	var raff_nz: int = (ReliefDonnees.NZ - 1) / p
	if _raffine.size() != _raff_nx * raff_nz:
		_raffine = PackedByteArray()
		_raffine.resize(_raff_nx * raff_nz)
	_h_aff0 = _h.duplicate()
	_raffine0 = _raffine.duplicate()
	_f_active = true


func _cible_fenetre() -> Vector2:
	if cible_fenetre != Vector3.INF:
		return Vector2(cible_fenetre.x, cible_fenetre.z)
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return Vector2.INF
	return Vector2(cam.global_position.x, cam.global_position.z)


func _fenetre_pas(delta: float) -> void:
	var fin: int = Time.get_ticks_usec() + BUDGET_US
	if _f_job.is_empty():
		_f_t += delta
		if _f_t < 0.5 and cible_fenetre == Vector3.INF:
			return
		_f_t = 0.0
		var c: Vector2 = _cible_fenetre()
		if c == Vector2.INF or (_f_centre != Vector2.INF and c.distance_to(_f_centre) < FENETRE / 3.0):
			return
		_f_job = _fenetre_preparer(c)
	var t0: int = Time.get_ticks_usec()
	_fenetre_avancer(fin)
	var dt: float = (Time.get_ticks_usec() - t0) / 1000.0
	if not _f_job.is_empty():
		_f_job["pire_ms"] = maxf(float(_f_job["pire_ms"]), dt)
		_f_job["images"] = int(_f_job["images"]) + 1


func _fenetre_preparer(c: Vector2) -> Dictionary:
	var t0: int = Time.get_ticks_usec()
	var p: int = _pas
	var raff_nz: int = (ReliefDonnees.NZ - 1) / p
	var taille: float = _dx * p
	var r: float = FENETRE + taille
	var ci0: int = clampi(int((c.y - r - ReliefDonnees.Z_NORD) / (_dz * p)), 0, raff_nz - 1)
	var ci1: int = clampi(int((c.y + r - ReliefDonnees.Z_NORD) / (_dz * p)), 0, raff_nz - 1)
	var cj0: int = clampi(int((c.x - r - ReliefDonnees.X_OUEST) / taille), 0, _raff_nx - 1)
	var cj1: int = clampi(int((c.x + r - ReliefDonnees.X_OUEST) / taille), 0, _raff_nx - 1)
	var nouv: PackedInt32Array = PackedInt32Array()
	for ci in range(ci0, ci1 + 1):
		for cj in range(cj0, cj1 + 1):
			var cc: Vector2 = Vector2(ReliefDonnees.X_OUEST + (cj + 0.5) * taille, ReliefDonnees.Z_NORD + (ci + 0.5) * _dz * p)
			if cc.distance_to(c) < FENETRE + taille * 0.75:
				nouv.append(ci * _raff_nx + cj)
	# mailles à reprendre : l'ancienne fenêtre et la nouvelle
	var dans_nouv: Dictionary = {}
	for k in nouv:
		dans_nouv[k] = true
	var toutes: Dictionary = dans_nouv.duplicate()
	for k2 in _f_cellules:
		toutes[k2] = true
	return {"centre": c, "nouv": nouv, "dans_nouv": dans_nouv, "cellules": PackedInt32Array(toutes.keys()),
		"i": 0, "tuiles": [], "it": 0, "st": {}, "pire_ms": (Time.get_ticks_usec() - t0) / 1000.0, "images": 1,
		"t0": t0, "noeuds": 0, "imin": 1 << 30, "imax": -1, "jmin": 1 << 30, "jmax": -1}


## Altitude affichée d'un nœud d'une maille de la nouvelle fenêtre : sol de référence (gares comprises, sinon
## sol à 50 m sous ses triangles) fondu vers la grille à 25 m ; poids nul au bord de la fenêtre.
func _fenetre_noeud(i: int, j: int, c: Vector2) -> float:
	var n: int = ReliefDonnees.NX
	var p: int = _pas
	var k: int = i * n + j
	var x: float = ReliefDonnees.X_OUEST + j * _dx
	var z: float = ReliefDonnees.Z_NORD + i * _dz
	var poids: float = 1.0 - smoothstep(FENETRE - FENETRE_FONDU, FENETRE, Vector2(x, z).distance_to(c))
	var base: float = _h_aff0[k]
	if not (i % p == 0 and j % p == 0) and not _noeud_raffine0(i, j):
		base = _tri_sur(_h_aff0, x, z, p)
	return lerpf(base, _h25[k], poids)


func _noeud_raffine0(i: int, j: int) -> bool:
	var p: int = _pas
	var raff_nz: int = (ReliefDonnees.NZ - 1) / p
	for ci in [i / p, (i - 1) / p]:
		for cj in [j / p, (j - 1) / p]:
			if ci >= 0 and cj >= 0 and ci < raff_nz and cj < _raff_nx and _raffine0[ci * _raff_nx + cj] == 1:
				return true
	return false


func _fenetre_avancer(fin_us: int) -> void:
	var job: Dictionary = _f_job
	var n: int = ReliefDonnees.NX
	var p: int = _pas
	var c: Vector2 = job["centre"]
	var cellules: PackedInt32Array = job["cellules"]
	var dans_nouv: Dictionary = job["dans_nouv"]
	# 1. altitudes et marques des mailles reprises
	while job["i"] < cellules.size():
		var kc: int = cellules[job["i"]]
		job["i"] += 1
		var ci: int = kc / _raff_nx
		var cj: int = kc % _raff_nx
		var garder: bool = dans_nouv.has(kc)
		for di in range(p + 1):
			for dj in range(p + 1):
				var i: int = ci * p + di
				var j: int = cj * p + dj
				if i >= ReliefDonnees.NZ or j >= n:
					continue
				# (nœud partagé avec une maille de la nouvelle fenêtre : c'est elle qui décide)
				var dedans: bool = garder or _noeud_dans(i, j, dans_nouv)
				_h[i * n + j] = _fenetre_noeud(i, j, c) if dedans else _h_aff0[i * n + j]
				job["noeuds"] += 1
		_raffine[kc] = 1 if garder else _raffine0[kc]
		job["imin"] = mini(int(job["imin"]), ci * p)
		job["imax"] = maxi(int(job["imax"]), ci * p + p)
		job["jmin"] = mini(int(job["jmin"]), cj * p)
		job["jmax"] = maxi(int(job["jmax"]), cj * p + p)
		if Time.get_ticks_usec() > fin_us:
			return
	# 2. tuiles touchées, refaites une à une par tranches
	if job["tuiles"].is_empty() and job["it"] == 0:
		# tuiles du bloc qui croisent l'étendue des nœuds repris (bornes comprises : une tuile voisine partage
		# ses nœuds de bord) — la recherche maille par maille faisait une image de 30 ms
		var tl: Dictionary = {}
		for k in range(_tuiles.size()):
			var t: Array = _tuiles[k]
			if not t[4] and int(job["imin"]) <= t[1] and int(job["imax"]) >= t[0] and int(job["jmin"]) <= t[3] and int(job["jmax"]) >= t[2]:
				tl[k] = true
		job["tuiles"] = tl.keys()
	while job["it"] < (job["tuiles"] as Array).size():
		var kt: int = job["tuiles"][job["it"]]
		if (job["st"] as Dictionary).is_empty():
			job["st"] = _tuile_debut(_tuiles[kt])
		if not _tuile_pas(job["st"], fin_us):
			return
		var arr: Array = _tuile_fin(job["st"])
		job["st"] = {}
		job["it"] += 1
		if kt < _mi_tuiles.size() and _mi_tuiles[kt] != null:
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(0, _mat_terrain)
			(_mi_tuiles[kt] as MeshInstance3D).mesh = mesh
		if Time.get_ticks_usec() > fin_us:
			return
	# 3. fini
	_f_centre = c
	_f_cellules = job["nouv"]
	var tri: int = 0
	for mi in _mi_tuiles:
		if mi != null and (mi as MeshInstance3D).mesh != null:
			tri += (mi as MeshInstance3D).mesh.surface_get_array_index_len(0) / 3
	fenetre_stats = {"mailles": (job["nouv"] as PackedInt32Array).size(), "reprises": cellules.size(),
		"noeuds": job["noeuds"], "tuiles": (job["tuiles"] as Array).size(), "images": job["images"],
		"pire_ms": job["pire_ms"], "total_ms": (Time.get_ticks_usec() - int(job["t0"])) / 1000.0, "triangles_bloc": tri}
	print("[Relief] fenêtre à 25 m autour de (%.0f, %.0f) : %d mailles de 50 m redécoupées, %d tuiles refaites en %d images (pire %.1f ms), %d triangles dans le bloc" % [
		c.x, c.y, fenetre_stats["mailles"], fenetre_stats["tuiles"], fenetre_stats["images"], fenetre_stats["pire_ms"], tri])
	var r0: Vector2 = Vector2(ReliefDonnees.X_OUEST + int(job["jmin"]) * _dx, ReliefDonnees.Z_NORD + int(job["imin"]) * _dz)
	var r1: Vector2 = Vector2(ReliefDonnees.X_OUEST + int(job["jmax"]) * _dx, ReliefDonnees.Z_NORD + int(job["imax"]) * _dz)
	_f_job = {}
	sol_modifie.emit(Rect2(r0, r1 - r0).grow(_dx))


## Sol sans la fenêtre fine (celui sur lequel les objets du domaine sont posés au chargement).
func hauteur_sol_ref(x: float, z: float) -> float:
	if not _f_active or _h_aff0.is_empty():
		return hauteur_sol(x, z)
	for pc in _pieces:
		if (pc[0] as Rect2).has_point(Vector2(x, z)):
			var tp: Array = terrain_piece(x, z)
			if not is_nan(float(tp[0])):
				return float(tp[0])
	if fin != null and fin.fine_ici(x, z):
		return fin.hauteur(x, z)
	var cj: int = int((x - ReliefDonnees.X_OUEST) / (_dx * _pas))
	var ci: int = int((z - ReliefDonnees.Z_NORD) / (_dz * _pas))
	if ci >= 0 and cj >= 0 and cj < _raff_nx and ci * _raff_nx + cj < _raffine0.size() and _raffine0[ci * _raff_nx + cj] == 1:
		return _tri_sur(_h_aff0, x, z, 1)
	return _tri_sur(_h_aff0, x, z)


## Écart du sol affiché au sol de référence (0 hors de la fenêtre fine).
func ecart_sol(x: float, z: float) -> float:
	if not _f_active or _h_aff0.is_empty():
		return 0.0
	return hauteur_sol(x, z) - hauteur_sol_ref(x, z)


## Rectangle (monde) de la fenêtre en place, ou vide.
func rect_fenetre() -> Rect2:
	if _f_centre == Vector2.INF:
		return Rect2()
	return Rect2(_f_centre - Vector2.ONE * (FENETRE + 60.0), Vector2.ONE * 2.0 * (FENETRE + 60.0))


func _noeud_dans(i: int, j: int, dans_nouv: Dictionary) -> bool:
	var p: int = _pas
	for ci in [i / p, (i - 1) / p]:
		for cj in [j / p, (j - 1) / p]:
			if ci >= 0 and cj >= 0 and cj < _raff_nx and dans_nouv.has(ci * _raff_nx + cj):
				return true
	return false


func raffine_ici(x: float, z: float) -> bool:
	var cj: int = int((x - ReliefDonnees.X_OUEST) / (_dx * _pas))
	var ci: int = int((z - ReliefDonnees.Z_NORD) / (_dz * _pas))
	return raffine_maille(ci, cj)


func raffine_maille(ci: int, cj: int) -> bool:
	if _raffine.is_empty() or ci < 0 or cj < 0 or cj >= _raff_nx:
		return false
	var k: int = ci * _raff_nx + cj
	return k < _raffine.size() and _raffine[k] == 1


func _raffiner_gares() -> void:
	var t_us: int = Time.get_ticks_usec()
	var n: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var p: int = _pas
	var w: PackedFloat32Array = PackedFloat32Array()
	w.resize(n * nz)
	# mailles de 50 m entières (la dernière colonne, d'une seule maille à 25 m, reste telle quelle),
	# marquées par _marquer_raffine dès qu'un de leurs nœuds a un poids
	_raff_nx = (n - 1) / p
	var raff_nz: int = (nz - 1) / p
	_raffine = PackedByteArray()
	_raffine.resize(_raff_nx * raff_nz)
	var exclus: Array = []
	var nb_l: int = 0
	for am in amenagements:
		exclus.append((am["rect"] as Rect2).grow(60.0))
	for D in RemonteesDonnees.LIGNES:
		var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
		var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
		if a.distance_to(b) < 10.0:
			continue
		var u: Vector2 = (b - a).normalized()
		var lg: float = LigneRemontee.l_gare_pour(String(D["famille"])) + 2.0
		var demi: float = float(D["voie"]) * 0.5 + RAFFINE_PLEIN
		for bout in [[a, -u], [b, u]]:
			var o: Vector2 = bout[0]
			var vers: Vector2 = bout[1]               # vers l'arrière de la gare
			_marquer_raffine(w, o - vers * 12.0, o + vers * (lg + 12.0), demi, exclus)
		# sous la ligne : la ligne est calée sur le sol à 25 m (hauteur_ligne) ; là où le sol affiché à 50 m
		# passe au-dessus, la cabine frôle le sol (3S : 1,70 m de garde au lieu de 3 m). Redécoupé là seulement.
		var L: float = a.distance_to(b)
		var nrm: Vector2 = Vector2(-u.y, u.x)
		var bord: float = float(D["voie"]) * 0.5 + 3.0
		var n_s: int = maxi(int(L / RAFFINE_ECHANT), 2)
		var debut: Vector2 = Vector2.INF                # points consécutifs au-dessus : un seul segment
		var fin: Vector2 = Vector2.INF
		for k in range(1, n_s + 1):
			var c: Vector2 = a + u * (L * float(k) / float(n_s))
			var au_dessus: bool = false
			if k < n_s:
				for off in [-bord, 0.0, bord]:
					var q2: Vector2 = c + nrm * float(off)
					if _tri_sur(_h, q2.x, q2.y, p) - _tri_sur(_h25, q2.x, q2.y, 1) > RAFFINE_ECART:
						au_dessus = true
						break
			if au_dessus:
				nb_l += 1
				if debut == Vector2.INF:
					debut = c
				fin = c
			elif debut != Vector2.INF:
				_marquer_raffine(w, debut, fin, demi, exclus)
				debut = Vector2.INF
	var nb: int = _raffine.count(1)
	# altitudes : sol à 50 m d'origine (ses triangles) fondu vers la grille à 25 m ; les nœuds d'une maille
	# restée à 50 m ont un poids nul, donc le bord de la zone reste exactement sur le sol à 50 m
	var h0: PackedFloat32Array = _h.duplicate()
	for ci in range(raff_nz):
		for cj in range(_raff_nx):
			if _raffine[ci * _raff_nx + cj] != 1:
				continue
			for di in range(p + 1):
				for dj in range(p + 1):
					var i: int = ci * p + di
					var j: int = cj * p + dj
					var k: int = i * n + j
					var base: float = h0[k] if (di % p == 0 and dj % p == 0) else \
						_tri_sur(h0, ReliefDonnees.X_OUEST + j * _dx, ReliefDonnees.Z_NORD + i * _dz, p)
					_h[k] = lerpf(base, _h25[k], w[k])
	print("[Relief] maille 50 m : %d mailles redécoupées à 25 m autour des gares et sous les lignes (%d points de ligne), %.0f ms" % [nb, nb_l, (Time.get_ticks_usec() - t_us) / 1000.0])



## Poids de redécoupage (0..1) des nœuds autour du segment p0-p1 : plein jusqu'à `demi`, fondu sur RAFFINE_FONDU.
func _marquer_raffine(w: PackedFloat32Array, p0: Vector2, p1: Vector2, demi: float, exclus: Array) -> void:
	var n: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
	var r: float = demi + RAFFINE_FONDU
	var rz: int = (nz - 1) / _pas
	var j0: int = clampi(int((minf(p0.x, p1.x) - r - ReliefDonnees.X_OUEST) / _dx), 0, n - 1)
	var j1: int = clampi(int((maxf(p0.x, p1.x) + r - ReliefDonnees.X_OUEST) / _dx) + 1, 0, n - 1)
	var i0: int = clampi(int((minf(p0.y, p1.y) - r - ReliefDonnees.Z_NORD) / _dz), 0, nz - 1)
	var i1: int = clampi(int((maxf(p0.y, p1.y) + r - ReliefDonnees.Z_NORD) / _dz) + 1, 0, nz - 1)
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var q: Vector2 = Vector2(ReliefDonnees.X_OUEST + j * _dx, ReliefDonnees.Z_NORD + i * _dz)
			var t: float = clampf((q - p0).dot(p1 - p0) / maxf((p1 - p0).length_squared(), 1.0), 0.0, 1.0)
			var dist: float = q.distance_to(p0.lerp(p1, t)) - demi
			var poids: float = 1.0 - smoothstep(0.0, RAFFINE_FONDU, dist)
			if poids <= 0.0:
				continue
			var hors: bool = false
			for ex in exclus:
				if (ex as Rect2).has_point(q):
					hors = true
					break
			if not hors:
				w[i * n + j] = maxf(w[i * n + j], poids)
				for ci in range(maxi((i - 1) / _pas, 0), mini(i / _pas, rz - 1) + 1):
					for cj in range(maxi((j - 1) / _pas, 0), mini(j / _pas, _raff_nx - 1) + 1):
						_raffine[ci * _raff_nx + cj] = 1


func _tri_sur(grille: PackedFloat32Array, x: float, z: float, pas: int = 0) -> float:
	if pas <= 0:
		pas = _pas
	var lim_x: int = ReliefDonnees.NX - 1
	var lim_z: int = ReliefDonnees.NZ - 1
	var fx: float = clampf((x - ReliefDonnees.X_OUEST) / _dx, 0.0, lim_x - 0.001) / pas
	var fz: float = clampf((z - ReliefDonnees.Z_NORD) / _dz, 0.0, lim_z - 0.001) / pas
	var j0: int = int(fx) * pas
	var i0: int = int(fz) * pas
	var wx: float = fx - int(fx)
	var wz: float = fz - int(fz)
	var j1: int = mini(j0 + pas, lim_x)
	var i1: int = mini(i0 + pas, lim_z)
	var n: int = ReliefDonnees.NX
	var a: float = grille[i0 * n + j0]
	var b: float = grille[i0 * n + j1]
	var c: float = grille[i1 * n + j0]
	var d: float = grille[i1 * n + j1]
	# même découpe que les tuiles : (a, a+1, a+w) puis (a+1, a+w+1, a+w)
	if wx + wz <= 1.0:
		return a + (b - a) * wx + (c - a) * wz
	return d + (c - d) * (1.0 - wx) + (b - d) * (1.0 - wz)


## Déblai des gares de remontées (retour d'utilisateur, 02/11/2026 : « creuser la montagne en
## amont plutôt que relever l'aval ») : la gare était posée au plus haut du terrain sous
## son emprise, jusqu'à 18 m au-dessus du sol côté aval (médiane 2,9 m). On abaisse la
## grille sous l'emprise à DEBLAI_PART de la dénivelée, talus raide autour. Le sol
## affiché, la collision et le profil des lignes (lu sur hauteur_sol) suivent.
const DEBLAI_PART: float = 0.35
const DEBLAI_TALUS: float = 1.0        # hauteur par mètre, autour de l'emprise
# bâtiments existants ; 3S : machinerie en fosse, gare posée à son niveau (creux de 10 m, PC 03/11/2026)
const DEBLAI_NON: Array = ["tph_grande_motte", "olympique"]


## Maille à 50 m : le déblai couvre des mailles entières, plus large qu'à 25 m (4 m de trop au pied de
## l'escalier de la terrasse). Les pièces des gares lisent une copie creusée comme à 25 m.
func _creuser_gares() -> void:
	if _pas > 1:
		var h_aff: PackedFloat32Array = _h
		var pas_aff: int = _pas
		_h = _h.duplicate()
		_pas = 1
		_creuser_gares_corps()
		_plafonner_grille()
		_h25 = _h
		_h = h_aff
		_pas = pas_aff
	_creuser_gares_corps()
	if _pas > 1 and not _h25.is_empty() and not "--sans-raffine" in OS.get_cmdline_user_args():
		_raffiner_gares()
	if FENETRE > 0.0 and _pas > 1 and not _h25.is_empty():
		_fenetre_initialiser()
	# (relief fin : il a son propre sol. Maille à 50 m : seule sa copie à 25 m est plafonnée, plus haut)
	if _pas == 1 and not ReliefFin.voulu(_cran_depart):
		_plafonner_grille()


func _creuser_gares_corps() -> void:
	var interieur: Dictionary = {}
	for j in RemonteesDomaine.JUMELAGES:
		interieur[[j[0], false]] = true    # (tronçon bas : gare amont intermédiaire)
		interieur[[j[1], true]] = true
	for D in RemonteesDonnees.LIGNES:
		var cle: String = String(D["cle"])
		if cle not in DEBLAI_NON:
			var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
			var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
			if a.distance_to(b) < 10.0:
				continue
			var dirh: Vector2 = (b - a).normalized()
			a += dirh * float(RemonteesDomaine.AVANCES_AVAL.get(cle, 0.0))
			b -= dirh * float(RemonteesDomaine.RECULS_AMONT.get(cle, 0.0))
			var demi: float = float(D["voie"]) * 0.5 + 1.5
			var lg: float = LigneRemontee.l_gare_pour(String(D["famille"])) + 2.0
			for bout in [[true, a, -dirh], [false, b, dirh]]:
				if interieur.has([cle, bout[0]]) or _sur_replat(cle, bout[0]):
					continue
				_creuser_gare(bout[1], bout[2], demi, lg)
	_araser_cretes()
	_poser_replats()


## Replats communs à plusieurs gares (remarque d'utilisateur, iPad du 08/11/2026 : « le socle de la gare amont du 3S
## est complètement délirant et irréaliste, elle est posée au sol, c'est level avec l'arrivée de Fontaine Froide ») :
## sommet de Bellevarde, arrivées du 3S (2690 m) et de Fontaine Froide (2688,2 m) de plain-pied. Le relief y descendait
## de 2 à 6 m sous la gare du 3S (remblai blanc de 10 m de haut) et le déblai de Fontaine Froide l'avait mise à 2677 m.
## [[clé, aval ?, recul derrière la gare (m)]..., altitude du replat, demi-largeur ajoutée, raccord (m)]
## Gare aval du 3S (« le sol rentre à l'intérieur de la gare aval », 09/11/2026) : le relief y dépassait de 0,2 m la dalle,
## qui suit son altitude au nez de la gare (DEBLAI_NON : pas de déblai).
const REPLATS: Array = [[[["olympique", false, 30.0], ["tsd6_fontaine_froide", false, 8.0]], 2689.5, 6.0, 25.0],
	[[["olympique", true, 8.0]], 1832.30, 4.0, 14.0]]


static func _bb_poly(poly: PackedVector2Array) -> Rect2:
	var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	return bb


func _y_replat(cle: String, aval: bool) -> float:
	for rp in REPLATS:
		for g in rp[0]:
			if String(g[0]) == cle and bool(g[1]) == aval:
				return float(rp[1])
	return NAN


func _sur_replat(cle: String, aval: bool) -> bool:
	for rp in REPLATS:
		for g in rp[0]:
			if String(g[0]) == cle and bool(g[1]) == aval:
				return true
	return false


## Paliers fins (pièce à 2 m) communs à des gares de plain-pied, quand l'une d'elles est au bord d'un à-pic : la
## grille de 25 m d'un replat (REPLATS) relevait la neige jusqu'à 50 m devant son nez. Le Fornet : arrivée du
## téléphérique et départ du Vallon (retour d'utilisateur, iPad du 13/11/2026 : « le TCD Vallon est au même niveau
## que le Fornet, ça passe tout seul sans monter » ; données : 2321,9 et 2324,8 m). Le relief mettait le quai du
## Fornet à 2316,6 m et celui du Vallon, sur son éperon, à 2322,9 m ; on y montait par un escalier.
## [[clé, aval ?, recul derrière la gare (m), à pic ?]..., altitude, demi-largeur ajoutée, raccord (m)]. À pic : le
## palier commence à un raccord derrière le nez, le terrain d'origine reste devant (les cabines en sortent).
const PALIERS: Array = [[[["tph_fornet", false, 10.0, true], ["tcd10_vallon_iseran", true, 30.0, false]], 2322.9, 5.0, 10.0]]


## Gares de plain-pied (retour d'utilisateur du 16/11/2026 : « tes terrassements où on est super haut ; en vrai on
## arrive de plain-pied ») : la gare était posée au plus haut du terrain sous son quai et le reste comblé par un
## remblai de neige (jusqu'à 10 m aux Boisses, plus de 3 m sur une vingtaine de gares). Quand le terrain varie de plus
## de SEUIL_PLAIN_PIED sous l'emprise, une pièce fine le met à plat à mi-hauteur (autant de déblai que de remblai)
## sous toute la largeur du quai, l'aire d'attente, le débarquement et l'aire d'arrivée à pied (plus de rampe),
## raccordée à la pente sur 12 à 30 m. Gares voisines : une seule pièce.
## Pas pour : téléskis (pas de quai), téléphériques et Funival (bâtiments), replats et paliers communs, gares
## intermédiaires des lignes jumelées (une pièce pour les deux).
const SEUIL_PLAIN_PIED: float = 2.0
const SEUIL_REBORD: float = 0.6        # dévers sous une gare à partir duquel ses abords sont raccordés
const SEUIL_CREUX: float = 1.2          # terrain des abords (à 8 m) au-dessus de la gare
## Longueur de l'aire d'arrivée à pied, à plat, derrière le bout du quai (m).
const ACCES_PLAIN_PIED: float = 12.0


func _amenagements_gares_plain_pied() -> Dictionary:
	var hors: Dictionary = {}
	# gare intermédiaire de deux lignes jumelées : une seule pièce, sous les deux gares dos à dos
	var double: Dictionary = {}
	for j in RemonteesDomaine.JUMELAGES:
		double[[j[0], false]] = true
		hors[[j[1], true]] = true
	for pl in PALIERS:
		for g in pl[0]:
			hors[[String(g[0]), bool(g[1])]] = true
	var liste: bool = "--liste-plain-pied" in OS.get_cmdline_user_args()
	var cands: Array = []           # {rect, plat, seul} : `seul` faux = posée seulement si une voisine l'atteint
	for D in RemonteesDonnees.LIGNES:
		var cle: String = String(D["cle"])
		var fam: String = String(D["famille"])
		if fam.begins_with("perche") or fam == "cabine_funi" or fam == "cabine_tph":
			continue
		var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
		var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
		if a.distance_to(b) < 10.0:
			continue
		var u: Vector2 = (b - a).normalized()
		var lat: Vector2 = Vector2(-u.y, u.x)
		a += u * float(RemonteesDomaine.AVANCES_AVAL.get(cle, 0.0))
		b -= u * float(RemonteesDomaine.RECULS_AMONT.get(cle, 0.0))
		# toute la largeur du quai et de ses talus (quai : voie / 2 + 5 m, plus le contour extérieur du double
		# embarquement), et derrière, l'aire d'arrivée à pied côté portillons : à voie / 2 + 4 m et l_gare + 10 m, les
		# bords du quai et la rampe d'accès des télésièges (jusqu'à 40 m) sortaient de la pièce, sur des remblais de
		# 2 à 7 m (retour d'utilisateur : « tes terrassements où on est super haut ; en vrai on arrive de plain-pied »)
		var jum: bool = false
		for jg in RemonteesDomaine.JUMELAGES:
			jum = jum or cle in jg
		var hl: float = float(D["voie"]) * 0.5 + 8.0 + (LigneRemontee.DECAL_CONTOUR if jum else 0.0)
		var t0: float = -6.0
		var lgg: float = LigneRemontee.l_gare_pour(fam)
		var bq: float = lgg + float(D["voie"]) * 0.25 + 8.25          # bout du quai (RemonteesDomaine, rampes)
		var t1: float = maxf(lgg + 10.0, bq + ACCES_PLAIN_PIED)
		var hln: float = float(D["voie"]) * 0.5 + 4.0                # emprise de la gare seule
		var t1n: float = lgg + 10.0
		for aval in [true, false]:
			if hors.has([cle, aval]):
				continue
			var o: Vector2 = a if aval else b
			var vers: Vector2 = -u if aval else u
			var mn: float = INF
			var mx: float = -INF
			var t0g: float = -t1 if double.has([cle, aval]) else t0
			# niveau mesuré sous l'emprise de la gare seule (quai, poulie) : la mettre à plat sur l'aire d'arrivée suffit à
			# supprimer la rampe ; l'abaisser vers cette aire raidissait la sortie du câble (Cugnai aval, 19,5°) et changeait
			# le sens de déviation de pylônes voisins (bench_profil_lignes)
			var t0n: float = -t1n if double.has([cle, aval]) else t0
			var t: float = t0n
			while t <= t1n:
				for kx in range(-2, 3):
					var q: Vector2 = o + vers * t + lat * (hln * kx * 0.5)
					var h: float = _hauteur_tri(q.x, q.y)
					mn = minf(mn, h)
					mx = maxf(mx, h)
				t += 3.0
			# à mi-hauteur (autant de déblai que de remblai) ; gares sans déblai (DEBLAI_NON) : au plus haut, comme avant
			var y_plat: float = (mn + mx) * 0.5
			# gare sur un replat (sommet de Bellevarde) : à son niveau, posée seulement si une voisine l'atteint, pour
			# que le raccord de celle-ci ne creuse pas le replat (Olympique : 1,8 m de remblai sinon)
			var y_rp: float = _y_replat(cle, aval)
			var denivelee: float = mx - mn
			var seul: bool = denivelee >= SEUIL_PLAIN_PIED and cle not in DEBLAI_NON and is_nan(y_rp)
			if not is_nan(y_rp):
				y_plat = y_rp
			elif cle in DEBLAI_NON:
				y_plat = mx
			elif denivelee < SEUIL_PLAIN_PIED:
				# gare en creux (retour d'utilisateur du 16/11/2026 : « le bas de l'Aiguille Percée m'a l'air sous
				# terre ») : sol presque plat sous la gare, mais terrain plus haut autour (versant en travers, déblai de
				# la grille) — la gare garde son niveau, les abords sont raccordés en pente douce
				var haut: float = -INF
				var ta: float = t0n - 8.0
				while ta <= t1n + 8.0:
					for sx in [-1.0, 1.0]:
						var qa: Vector2 = o + vers * ta + lat * (sx * (hln + 8.0))
						haut = maxf(haut, _hauteur_tri(qa.x, qa.y))
					ta += 4.0
				for kx2 in range(-2, 3):
					for tb in [t0n - 8.0, t1n + 8.0]:
						var qb: Vector2 = o + vers * tb + lat * ((hln + 8.0) * kx2 * 0.5)
						haut = maxf(haut, _hauteur_tri(qb.x, qb.y))
				y_plat = mx
				if haut - mx >= SEUIL_CREUX:
					seul = true
					denivelee = haut - mx
				elif denivelee >= SEUIL_REBORD:
					# sol en léger dévers sous la gare (bas de l'Aiguille Percée, tour des gares du 16/11/2026 : gare
					# sur un plateau au rebord franc d'un mètre) : la gare garde son niveau, le terrain monte jusqu'à
					# elle et se raccorde en pente douce
					seul = true
			# raccord en racine de la dénivelée : courbure bornée (à 1,5 fois la dénivelée, un raccord de 10 m pour 5 m
			# de haut laissait 6 cm entre le sol affiché et la collision, au pas de 2 m — bench_ski)
			var fondu: float = clampf(8.5 * sqrt(maxf(denivelee, 0.0)), 12.0, 30.0)
			var poly: PackedVector2Array = PackedVector2Array([o + vers * t0g - lat * hl, o + vers * t0g + lat * hl,
				o + vers * t1 + lat * hl, o + vers * t1 - lat * hl])
			var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
			for v in poly:
				bb = bb.expand(v)
			# niveau de la gare telle que RemonteesDomaine la pose sans pièce : au plus haut du sol des lignes sous le quai
			var y_gare: float = -INF
			var tg: float = -2.0
			while tg <= lgg + 2.0:
				for xg in [-1.0, 0.0, 1.0]:
					var qg: Vector2 = o + vers * tg + lat * (xg * (float(D["voie"]) * 0.5 + 1.5))
					y_gare = maxf(y_gare, hauteur_ligne(qg.x, qg.y))
				tg += 3.0
			# rectangle de la pièce de la gare seule (règle d'origine : emprise de la gare, premier arrivé)
			var pn: Rect2 = Rect2(o + vers * t0n, Vector2.ZERO).expand(o + vers * t0n + lat * hln).expand(o + vers * t0n - lat * hln) 				.expand(o + vers * t1n + lat * hln).expand(o + vers * t1n - lat * hln)
			cands.append({"rect": bb.grow(fondu + 6.0), "plat": [poly, y_plat, fondu], "seul": seul, "y_gare": y_gare, "replat": not is_nan(y_rp),
				"r_seule": pn.grow(fondu + 6.0),
				"nom": "%-26s %-5s sol %.1f à %.1f m → %.1f, raccord %.0f m" % [cle, "aval" if aval else "amont", mn, mx, y_plat, fondu]})
	# pas sur un aménagement déjà posé (palier du Fornet à côté du départ des Pyramides : le socle du Vallon se
	# retrouvait à nu, 35 bords ouverts à bench_garde_fous)
	var deja: Array = amenagements.duplicate()
	# gares qui avaient déjà leur pièce seules (premier arrivé, sans recouvrement) : à mi-hauteur. Les autres (sur un
	# aménagement, sur une voisine) gardent le niveau où RemonteesDomaine les posait, et c'est le terrain qui monte
	# jusqu'au quai : les câbles ne bougent pas (abaissées à mi-hauteur, Tufs, Marais, Pyramides changeaient le sens
	# de déviation de pylônes voisins — bench_profil_lignes)
	var seules: Array = []
	for c in cands:
		var accepte: bool = bool(c["seul"])
		if accepte:
			for am0 in deja:
				if ((am0 as Dictionary)["rect"] as Rect2).grow(GRANDI_PIECE).intersects(c["r_seule"]):
					accepte = false
					break
		if accepte:
			for r0 in seules:
				if (r0 as Rect2).grow(GRANDI_PIECE).intersects(c["r_seule"]):
					accepte = false
					break
		if accepte:
			seules.append(c["r_seule"])
		c["seule"] = accepte
	var ecartees: Array = []        # emprises (rectangle du plat) des gares laissées comme avant
	# ni sur le haut du Funival, aménagé plus tard en jeu par la ligne elle-même (salle rasée, bâtiment : 7 bords
	# ouverts à bench_garde_fous quand la pièce commune du sommet de Bellevarde l'atteignait)
	for D2 in RemonteesDonnees.LIGNES:
		if String(D2["famille"]) == "cabine_funi":
			var bf: Vector2 = RemonteesDomaine.monde(float(D2["amont"][0]), float(D2["amont"][1]))
			cands = cands.filter(func(c: Dictionary) -> bool:
				var hors_funi: bool = not Rect2(bf - Vector2.ONE * 75.0, Vector2.ONE * 150.0).grow(GRANDI_PIECE).intersects(c["rect"])
				if not hors_funi:
					ecartees.append(_bb_poly(c["plat"][0]))
					if liste and bool(c["seul"]):
						print("PLAIN_PIED_NON %s : sur le haut du Funival" % c["nom"])
				return hors_funi)
	# … sauf sur un aménagement fait seulement de plats (palier du Fornet et départ des Pyramides, 6,8 m de remblai) :
	# la gare y ajoute le sien, mêlé comme entre gares voisines
	for c in cands:
		if not bool(c["seul"]):
			continue
		var touche: Array = deja.filter(func(am0: Dictionary) -> bool: return (am0["rect"] as Rect2).grow(GRANDI_PIECE).intersects(c["rect"]))
		if touche.size() != 1 or not (touche[0] as Dictionary).keys().all(func(k2) -> bool: return k2 in ["rect", "plats", "masque", "melange"]):
			continue
		var am1: Dictionary = touche[0]
		var r1: Rect2 = (am1["rect"] as Rect2).merge(c["rect"])
		if deja.any(func(am0: Dictionary) -> bool: return am0 != am1 and (am0["rect"] as Rect2).grow(GRANDI_PIECE).intersects(r1)):
			continue
		am1["rect"] = r1
		(am1["plats"] as Array).append(c["plat"])
		am1["melange"] = true
		c["fondue"] = true
		gares_plain_pied += 1
		if liste:
			print("PLAIN_PIED %s, mêlée à l'aménagement voisin" % c["nom"])
	cands = cands.filter(func(c: Dictionary) -> bool:
		if c.has("fondue"):
			return false
		for am0 in deja:
			if ((am0 as Dictionary)["rect"] as Rect2).grow(GRANDI_PIECE).intersects(c["rect"]):
				ecartees.append(_bb_poly(c["plat"][0]))
				if liste and bool(c["seul"]):
					print("PLAIN_PIED_NON %s : sur un autre aménagement" % c["nom"])
				return false
		return true)
	# ni sur l'emprise d'une gare écartée : son raccord la mettait en remblai (Marmottes amont, 2,2 m, à côté du groupe
	# du sommet de Bellevarde)
	cands = cands.filter(func(c: Dictionary) -> bool:
		for re in ecartees:
			if (re as Rect2).grow(2.0).intersects(c["rect"]):
				if liste and bool(c["seul"]):
					print("PLAIN_PIED_NON %s : touche une gare écartée" % c["nom"])
				return false
		return true)
	# gares voisines (sommet de Bellevarde, Marais et Leissières…) : une seule pièce, un plat par gare, mêlés
	# par l'inverse de la distance (chaque quai reste à son niveau) ; avant, la première posée gardait sa pièce et
	# les autres restaient sur leur remblai, et une voisine sans pièce voyait son sol bouger sous le raccord
	var grp: Array = range(cands.size())
	var racine := func(i: int) -> int:
		while grp[i] != i:
			i = grp[i]
		return i
	for i in range(cands.size()):
		for j in range(i + 1, cands.size()):
			if (cands[i]["rect"] as Rect2).grow(GRANDI_PIECE).intersects(cands[j]["rect"]):
				grp[racine.call(j)] = racine.call(i)
	var groupes: Dictionary = {}
	for i in range(cands.size()):
		var k: int = racine.call(i)
		if not groupes.has(k):
			groupes[k] = []
		groupes[k].append(cands[i])
	var n_pieces: int = 0
	for k in groupes:
		var membres: Array = groupes[k]
		if not membres.any(func(c: Dictionary) -> bool: return bool(c["seul"])):
			continue
		if liste:
			for c in membres:
				print("PLAIN_PIED %s%s" % [c["nom"], "" if membres.size() == 1 else " (groupe de %d)" % membres.size()])
		if membres.size() == 1:
			amenagements.append({"rect": membres[0]["rect"], "plats": [membres[0]["plat"]], "masque": true})
			gares_plain_pied += 1
			n_pieces += 1
			continue
		# plats qui se recouvrent (gares dos à dos : Brévières amont et Boisses aval, 7,8 m d'écart) : celui de la gare qui
		# avait déjà sa pièce reste entier, l'autre est rogné ; mêlés, les deux quais restaient sur 4 m de remblai, et au
		# même niveau, le câble de l'une changeait de profil (bench_profil_lignes)
		for i in range(membres.size()):
			if not bool(membres[i]["seule"]):
				continue
			for j in range(membres.size()):
				if i == j or bool(membres[j]["seule"]):
					continue
				var pj: PackedVector2Array = membres[j]["plat"][0]
				if Geometry2D.intersect_polygons(membres[i]["plat"][0], pj).is_empty():
					continue
				var reste: Array = Geometry2D.clip_polygons(pj, membres[i]["plat"][0])
				var meilleur: PackedVector2Array = PackedVector2Array()
				var aire: float = 0.0
				for rp in reste:
					if Geometry2D.is_polygon_clockwise(rp):
						continue
					var bbr: Rect2 = _bb_poly(rp)
					if bbr.get_area() > aire:
						aire = bbr.get_area()
						meilleur = rp
				if not meilleur.is_empty():
					membres[j]["plat"][0] = meilleur
		var r_g: Rect2 = membres[0]["rect"]
		var plats: Array = []
		for c in membres:
			r_g = r_g.merge(c["rect"])
			plats.append(c["plat"])
		var libre: bool = true
		for am0 in deja:
			if ((am0 as Dictionary)["rect"] as Rect2).grow(GRANDI_PIECE).intersects(r_g):
				libre = false
		if not libre:
			# (rectangle commun sur un autre aménagement : comme avant, la première gare garde sa pièce)
			var poses: Array = []
			for c in membres:
				if not bool(c["seul"]) or poses.any(func(r0: Rect2) -> bool: return r0.grow(GRANDI_PIECE).intersects(c["rect"])):
					continue
				poses.append(c["rect"])
				amenagements.append({"rect": c["rect"], "plats": [c["plat"]], "masque": true})
				gares_plain_pied += 1
				n_pieces += 1
			continue
		amenagements.append({"rect": r_g, "plats": plats, "masque": true, "melange": true})
		gares_plain_pied += membres.size()
		n_pieces += 1
		pieces_groupees += 1
	print("[Relief] gares de plain-pied : %d gares, %d pièces (%d groupées)" % [gares_plain_pied, n_pieces, pieces_groupees])
	return {}


func _amenagement_palier(k: int) -> Dictionary:
	var pl: Array = PALIERS[k]
	var y: float = float(pl[1])
	var fondu: float = float(pl[3])
	var coins: PackedVector2Array = PackedVector2Array()
	for g in pl[0]:
		for D in RemonteesDonnees.LIGNES:
			if String(D["cle"]) != String(g[0]):
				continue
			var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
			var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
			var u: Vector2 = (b - a).normalized()
			var lat: Vector2 = Vector2(-u.y, u.x)
			# (gares avancées ou reculées sur leur axe : le Vallon, 42 m)
			var o: Vector2 = a + u * float(RemonteesDomaine.AVANCES_AVAL.get(String(g[0]), 0.0)) if bool(g[1]) \
					else b - u * float(RemonteesDomaine.RECULS_AMONT.get(String(g[0]), 0.0))
			var vers: Vector2 = -u if bool(g[1]) else u          # vers l'arrière de la gare
			var t0: float = fondu if bool(g[3]) else -8.0
			var t1: float = LigneRemontee.l_gare_pour(String(D["famille"])) + 2.0 + float(g[2])
			var hl: float = float(D["voie"]) * 0.5 + float(pl[2])
			for t in [t0, t1]:
				for sx in [-1.0, 1.0]:
					coins.append(o + vers * t + lat * (sx * hl))
	if coins.size() < 3:
		return {}
	var poly: PackedVector2Array = Geometry2D.convex_hull(coins)
	var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	return {"rect": bb.grow(fondu + 6.0), "plats": [[poly, y, fondu]]}


## Terrain mis au niveau du replat sous l'emprise de chaque gare (remblai comme déblai), raccord doux autour.
func _poser_replats() -> void:
	for rp in REPLATS:
		var rects: Array = []        # [centre, axe, demi-longueur, demi-largeur]
		for g in rp[0]:
			for D in RemonteesDonnees.LIGNES:
				if String(D["cle"]) != String(g[0]):
					continue
				var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
				var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
				var u: Vector2 = (b - a).normalized()
				var o: Vector2 = a if bool(g[1]) else b
				var vers: Vector2 = -u if bool(g[1]) else u          # vers l'arrière de la gare
				var lg: float = LigneRemontee.l_gare_pour(String(D["famille"])) + 2.0
				var arr: float = float(g[2])
				var devant: float = 8.0                            # (devant le quai : la maille de 25 m y mêlait la pente)
				var c: Vector2 = o + vers * ((lg + arr - devant) * 0.5)
				rects.append([c, u, (lg + arr + devant) * 0.5, float(D["voie"]) * 0.5 + float(rp[2])])
		if rects.is_empty():
			continue
		var y: float = float(rp[1])
		var fondu: float = float(rp[3])
		var r_max: float = 0.0
		var bb: Rect2 = Rect2(rects[0][0], Vector2.ZERO)
		for rc in rects:
			r_max = maxf(r_max, maxf(rc[2], rc[3]))
			bb = bb.expand(rc[0])
		bb = bb.grow(r_max + fondu + maxf(_dx, _dz) * _pas)
		var n: int = ReliefDonnees.NX
		var j0: int = clampi(int((bb.position.x - ReliefDonnees.X_OUEST) / _dx), 0, n - 1)
		var j1: int = clampi(int((bb.end.x - ReliefDonnees.X_OUEST) / _dx) + 1, 0, n - 1)
		var i0: int = clampi(int((bb.position.y - ReliefDonnees.Z_NORD) / _dz), 0, ReliefDonnees.NZ - 1)
		var i1: int = clampi(int((bb.end.y - ReliefDonnees.Z_NORD) / _dz) + 1, 0, ReliefDonnees.NZ - 1)
		var m_c: float = maxf(_dx, _dz) * _pas
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var q: Vector2 = Vector2(ReliefDonnees.X_OUEST + j * _dx, ReliefDonnees.Z_NORD + i * _dz)
				var dist: float = INF
				for rc in rects:
					var v: Vector2 = q - (rc[0] as Vector2)
					var uu: Vector2 = rc[1]
					var lat: Vector2 = Vector2(-uu.y, uu.x)
					dist = minf(dist, Vector2(maxf(absf(v.dot(uu)) - float(rc[2]), 0.0), maxf(absf(v.dot(lat)) - float(rc[3]), 0.0)).length())
				# (toute la maille qui touche l'emprise est au niveau, puis le raccord)
				var w: float = 1.0 - smoothstep(0.0, fondu, maxf(dist - m_c, 0.0))
				if w > 0.0:
					var k: int = i * n + j
					_h[k] = lerpf(_h[k], y, w)


## Crêtes terrassées pour une ligne : sommet pointu du relevé remplacé par un replat (retour
## d'utilisateur, 04/11/2026 : la montagne a été creusée, replat de 30 m). Déblai côté haut, remblai
## côté bas. [clé, d du centre, demi-longueur le long de la ligne, demi-largeur en travers,
## abaissement sous le point le plus haut du replat]
const ARASEMENTS: Array = [["tsd6_leissieres", 581.0, 15.0, 28.0, 4.6]]
const ARASEMENT_RACCORD: float = 18.0


## Buttes de la seule grille à 25 m : sur une falaise, ses triangles passent jusqu'à 8 m au-dessus du sol
## du relevé fin, et la cabine du 3S les traversait à l'approche de l'ouvrage (l'altitude du câble vient du
## document, on ne la touche pas). [clé, d début, d fin, demi-largeur, altitude maximale]. Plafond resté
## au-dessus du sol fin (2708,7 m à d=1785).
const PLAFONDS_25: Array = [["olympique", 1772.0, 1826.0, 12.0, 2711.0]]


func _plafonner_grille() -> void:
	for pl in PLAFONDS_25:
		for D in RemonteesDonnees.LIGNES:
			if String(D["cle"]) == pl[0]:
				var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
				var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
				var u: Vector2 = (b - a).normalized()
				var demi_l: float = (float(pl[2]) - float(pl[1])) * 0.5
				var c: Vector2 = a + u * (float(pl[1]) + demi_l)
				var lat: Vector2 = Vector2(-u.y, u.x)
				var demi_x: float = pl[3]
				var r: float = maxf(demi_l, demi_x) + ARASEMENT_RACCORD + maxf(_dx, _dz)
				var n: int = ReliefDonnees.NX
				var j0: int = clampi(int((c.x - r - ReliefDonnees.X_OUEST) / _dx), 0, n - 1)
				var j1: int = clampi(int((c.x + r - ReliefDonnees.X_OUEST) / _dx) + 1, 0, n - 1)
				var i0: int = clampi(int((c.y - r - ReliefDonnees.Z_NORD) / _dz), 0, ReliefDonnees.NZ - 1)
				var i1: int = clampi(int((c.y + r - ReliefDonnees.Z_NORD) / _dz) + 1, 0, ReliefDonnees.NZ - 1)
				for i in range(i0, i1 + 1):
					for j in range(j0, j1 + 1):
						var v: Vector2 = Vector2(ReliefDonnees.X_OUEST + j * _dx, ReliefDonnees.Z_NORD + i * _dz) - c
						var dist: float = Vector2(maxf(absf(v.dot(u)) - demi_l, 0.0), maxf(absf(v.dot(lat)) - demi_x, 0.0)).length()
						var poids: float = 1.0 - smoothstep(0.0, ARASEMENT_RACCORD, dist)
						if poids > 0.0:
							var k: int = i * n + j
							_h[k] = minf(_h[k], lerpf(_h[k], float(pl[4]), poids))


func _araser_cretes() -> void:
	for ar in ARASEMENTS:
		for D in RemonteesDonnees.LIGNES:
			if String(D["cle"]) == ar[0]:
				var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
				var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
				_araser(a, (b - a).normalized(), ar)


func _araser(a: Vector2, u: Vector2, ar: Array) -> void:
	var c: Vector2 = a + u * float(ar[1])
	var lat: Vector2 = Vector2(-u.y, u.x)
	var demi_l: float = ar[2]
	var demi_x: float = ar[3]
	var haut: float = -INF
	var t: float = -demi_l
	while t <= demi_l:
		haut = maxf(haut, _hauteur_tri((c + u * t).x, (c + u * t).y))
		t += 2.0
	var y0: float = haut - float(ar[4])
	var r: float = maxf(demi_l, demi_x) + ARASEMENT_RACCORD + maxf(_dx, _dz)
	var n: int = ReliefDonnees.NX
	var j0: int = clampi(int((c.x - r - ReliefDonnees.X_OUEST) / _dx), 0, n - 1)
	var j1: int = clampi(int((c.x + r - ReliefDonnees.X_OUEST) / _dx) + 1, 0, n - 1)
	var i0: int = clampi(int((c.y - r - ReliefDonnees.Z_NORD) / _dz), 0, ReliefDonnees.NZ - 1)
	var i1: int = clampi(int((c.y + r - ReliefDonnees.Z_NORD) / _dz) + 1, 0, ReliefDonnees.NZ - 1)
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			var v: Vector2 = Vector2(ReliefDonnees.X_OUEST + j * _dx, ReliefDonnees.Z_NORD + i * _dz) - c
			var tv: float = v.dot(u)
			var xv: float = v.dot(lat)
			var dist: float = Vector2(maxf(absf(tv) - demi_l, 0.0), maxf(absf(xv) - demi_x, 0.0)).length()
			var poids: float = 1.0 - smoothstep(0.0, ARASEMENT_RACCORD, dist)
			if poids <= 0.0:
				continue
			var k: int = i * n + j
			_h[k] = lerpf(_h[k], y0, poids)


func _creuser_gare(o: Vector2, u: Vector2, demi: float, long_g: float) -> void:
	for am in amenagements:
		if (am["rect"] as Rect2).grow(30.0).has_point(o):
			return                         # gare du funiculaire
	var lat: Vector2 = Vector2(-u.y, u.x)
	var mi: float = INF
	var ma: float = -INF
	var t: float = -2.0
	while t <= long_g:
		for x in [-demi, 0.0, demi]:
			var q: Vector2 = o + u * t + lat * x
			var h: float = _hauteur_tri(q.x, q.y)
			mi = minf(mi, h)
			ma = maxf(ma, h)
		t += 3.0
	if ma - mi < 1.0:
		return
	var y: float = mi + (ma - mi) * DEBLAI_PART
	var n: int = ReliefDonnees.NX
	var m_c: float = maxf(_dx, _dz) * _pas
	var r: float = long_g + demi + m_c * 2.0 + (ma - y) / DEBLAI_TALUS
	var j0: int = clampi(int((o.x - r - ReliefDonnees.X_OUEST) / _dx), 0, n - 1)
	var j1: int = clampi(int((o.x + r - ReliefDonnees.X_OUEST) / _dx) + 1, 0, n - 1)
	var i0: int = clampi(int((o.y - r - ReliefDonnees.Z_NORD) / _dz), 0, ReliefDonnees.NZ - 1)
	var i1: int = clampi(int((o.y + r - ReliefDonnees.Z_NORD) / _dz) + 1, 0, ReliefDonnees.NZ - 1)
	for i in range(i0, i1 + 1):
		var zv: float = ReliefDonnees.Z_NORD + i * _dz
		for j in range(j0, j1 + 1):
			var v: Vector2 = Vector2(ReliefDonnees.X_OUEST + j * _dx, zv) - o
			var tv: float = v.dot(u)
			var xv: float = v.dot(lat)
			var dt: float = maxf(maxf(-2.0 - tv, tv - long_g), 0.0)
			var dx: float = maxf(absf(xv) - demi, 0.0)
			# toute la maille qui touche l'emprise, puis le talus
			var dist: float = maxf(Vector2(dt, dx).length() - m_c, 0.0)
			var k: int = i * n + j
			_h[k] = minf(_h[k], y - 0.3 + dist * DEBLAI_TALUS)


## Distance d'un point à un polygone (0 dedans).
static func _dist_poly(q: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(q, poly):
		return 0.0
	var d: float = INF
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return d


## Pièces de terrain fines (maille de 2 m) autour des gares.
## Trous du relief : pièces fines des gares (remplacées par leur maillage
## fin) et fosses ouvertes (`percer` : rien dessous, la remontée y dessine
## sa fosse — contrepoids et motrice de l'Olympique). 8 au plus.
var _fosses: Dictionary = {}          # clé → Rect2


func percer(cle: String, r: Rect2) -> void:
	_fosses[cle] = r
	_poser_trous()


func reboucher(cle: String) -> void:
	if _fosses.erase(cle):
		_poser_trous()


## Emprises percées dans les tuiles (pièces fines, fosses) : taille du tableau `pieces` des shaders du relief.
const MAX_PIECES: int = 12
## Au-delà (gares de plain-pied : 34 pièces) : masque sur toute l'emprise du bloc, un pixel = 10,3 × 8,4 m, lu au plus
## proche — une lecture de texture par point du sol au lieu d'une boucle sur les rectangles.
const MASQUE_GARES: int = 2048
var _rects_masque: Array = []
var _tex_masque: ImageTexture = null


func _poser_masque() -> void:
	if _rects_masque.is_empty() or _mat_terrain == null:
		return
	var img: Image = Image.create(MASQUE_GARES, MASQUE_GARES, false, Image.FORMAT_L8)
	var px: float = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / MASQUE_GARES
	var pz: float = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / MASQUE_GARES
	for r in _rects_masque:
		var j0: int = clampi(int(round((r.position.x - ReliefDonnees.X_OUEST) / px)), 0, MASQUE_GARES)
		var j1: int = clampi(int(round((r.end.x - ReliefDonnees.X_OUEST) / px)), 0, MASQUE_GARES)
		var i0: int = clampi(int(round((r.position.y - ReliefDonnees.Z_NORD) / pz)), 0, MASQUE_GARES)
		var i1: int = clampi(int(round((r.end.y - ReliefDonnees.Z_NORD) / pz)), 0, MASQUE_GARES)
		if j1 > j0 and i1 > i0:
			img.fill_rect(Rect2i(j0, i0, j1 - j0, i1 - i0), Color.WHITE)
	_tex_masque = ImageTexture.create_from_image(img)
	var bloc: Vector4 = Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD, ReliefDonnees.X_EST, ReliefDonnees.Z_SUD)
	var mats: Array = [_mat_terrain]
	if fin != null and fin.anneaux != null:
		mats.append_array(fin.anneaux.get("_mats"))
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("masque_gares", _tex_masque)
		(m as ShaderMaterial).set_shader_parameter("bloc_masque", bloc)
		(m as ShaderMaterial).set_shader_parameter("avec_masque", 1.0)


## Masque des traces damées des TKD (CouloirsTkd.masque) sur le relief et ses anneaux.
var _masque_tkd: Array = []


func _poser_masque_tkd() -> void:
	if _mat_terrain == null or couloirs == null or couloirs.n_pieces == 0:
		return
	if _masque_tkd.is_empty():
		var m: Array = couloirs.masque()
		if m.is_empty():
			return
		_masque_tkd = [ImageTexture.create_from_image(m[0]), m[1], m[2]]
	var axes: Array = (_masque_tkd[1] as Array).duplicate()
	var dims: Array = (_masque_tkd[2] as Array).duplicate()
	var n: int = axes.size()
	while axes.size() < CouloirsTkd.MAX_TKD:
		axes.append(Vector4.ZERO)
		dims.append(Vector4.ZERO)
	var mats: Array = [_mat_terrain]
	if fin != null and fin.anneaux != null:
		mats.append_array(fin.anneaux.get("_mats"))
	for mt in mats:
		(mt as ShaderMaterial).set_shader_parameter("masque_tkd", _masque_tkd[0])
		(mt as ShaderMaterial).set_shader_parameter("tkd_axe", axes)
		(mt as ShaderMaterial).set_shader_parameter("tkd_dim", dims)
		(mt as ShaderMaterial).set_shader_parameter("n_tkd", n)


func _poser_trous() -> void:
	if _mat_terrain == null:
		return
	var v: Array = []
	for r in _rects_pieces + _fosses.values():
		v.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	var n: int = mini(v.size(), MAX_PIECES)
	if v.size() > MAX_PIECES:
		push_warning("relief : %d pièces et fosses, %d au plus — les dernières restent couvertes" % [v.size(), MAX_PIECES])
	while v.size() < MAX_PIECES:
		v.append(Vector4.ZERO)
	_mat_terrain.set_shader_parameter("pieces", v.slice(0, MAX_PIECES))
	_mat_terrain.set_shader_parameter("n_pieces", n)
	_poser_masque()
	_poser_masque_tkd()
	if fin != null and fin.anneaux != null:
		# (anneaux sous le bord des pièces fines : de même surface, et plus de points de ciel à la jonction)
		var sous_pieces: Array = _rects_pieces.map(func(r: Rect2) -> Rect2: return r.grow(-1.5))
		fin.anneaux.poser_trous(sous_pieces + _fosses.values().filter(func(r: Rect2) -> bool: return r != _fosses.get("relief_fin", Rect2())))


const FONDU_PIECE: float = 15.0
const GRANDI_PIECE: float = 25.0
var _h25: PackedFloat32Array = PackedFloat32Array()


## `pause` (facultative) : attendue toutes les quelques rangées de la grille et entre les étapes, pour une pièce
## posée en jeu sur le fil principal (gare amont du Funival : 28 ms d'un bloc, relevé du 12/11/2026). Sans elle,
## tout se fait d'un bloc, comme avant.
func _build_piece(am: Dictionary, pause: Callable = Callable()) -> void:
	# (maille à 50 m : le fondu vers les tuiles ne doit pas atteindre les ouvrages, ici 8 m d'écart entre les grilles)
	var r: Rect2 = (am["rect"] as Rect2).grow(GRANDI_PIECE if _pas > 1 else 0.0)
	var au_masque: bool = bool(am.get("masque", false))
	if au_masque:
		# percée par le masque des gares : rectangle élargi aux pixels du masque (lecture au plus proche = bord exact)
		var px: float = (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST) / MASQUE_GARES
		var pz: float = (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD) / MASQUE_GARES
		var x0: float = ReliefDonnees.X_OUEST + floorf((r.position.x - ReliefDonnees.X_OUEST) / px) * px
		var z0: float = ReliefDonnees.Z_NORD + floorf((r.position.y - ReliefDonnees.Z_NORD) / pz) * pz
		var x1: float = ReliefDonnees.X_OUEST + ceilf((r.end.x - ReliefDonnees.X_OUEST) / px) * px
		var z1: float = ReliefDonnees.Z_NORD + ceilf((r.end.y - ReliefDonnees.Z_NORD) / pz) * pz
		r = Rect2(x0, z0, x1 - x0, z1 - z0)
	var nx: int = int(ceil(r.size.x / PAS_PIECE)) + 1
	var nz: int = int(ceil(r.size.y / PAS_PIECE)) + 1
	var lx: float = r.size.x / (nx - 1)
	var lz: float = r.size.y / (nz - 1)
	# axe des couloirs : points de la voie tous les 2 m
	var axes: Array = []
	for c in am.get("couloirs", []):
		var pts: Array = []
		var s: float = c[0] - 12.0
		while s <= c[1] + 12.0:
			var sc: float = clampf(s, 0.0, PNConstants.LENGTH)
			var xf: Transform3D = tunnel.transform_at(sc)
			var t: Vector3 = -xf.basis.z
			var p: Vector3 = xf.origin + t * (s - sc)
			pts.append([s, p])
			s += 2.0
			if pause.is_valid() and pts.size() % 64 == 0:
				await pause.call()
		axes.append([c, pts])
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i in range(nz):
		if pause.is_valid() and i % 3 == 0:
			await pause.call()
		for j in range(nx):
			var x: float = r.position.x + j * lx
			var z: float = r.position.y + i * lz
			var q: Vector2 = Vector2(x, z)
			var h: float = _hauteur_tri(x, z)
			# maille à 50 m (crans bas) : l'intérieur de la pièce reste sur la grille à 25 m, celle pour
			# laquelle les ouvrages sont réglés (la neige montait de 0,9 m au pied de l'escalier de la terrasse)
			if _pas > 1 and (fin == null or not fin.fine_ici(x, z)):
				var d_bord: float = minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
				h = lerpf(h, _tri_sur(_h25, x, z, 1), smoothstep(0.0, FONDU_PIECE, d_bord))
			# bords de la pièce : exactement le bloc (aucune marche)
			var bord: bool = i == 0 or j == 0 or i == nz - 1 or j == nx - 1
			if not bord:
				# quais souterrains : relevé au-dessus du plafond de la salle
				for ax in axes:
					var c: Array = ax[0]
					var best: float = INF
					var bp: Array = []
					for e in ax[1]:
						var dd: float = q.distance_squared_to(Vector2(e[1].x, e[1].z))
						if dd < best:
							best = dd
							bp = e
					var travers: float = sqrt(best)
					var s_p: float = bp[0]
					var fondu: float = c[4] if c.size() > 4 else 10.0
					var w: float = (1.0 - smoothstep(c[2], c[2] + fondu, travers)) \
						* (1.0 - smoothstep(0.0, fondu, maxf(c[0] - s_p, s_p - c[1])))
					# au-dessus de la section à cet endroit (salle ou tube)
					var s_c: float = clampf(s_p, 0.0, PNConstants.LENGTH)
					var sect: float = maxf(tunnel.tunnel_radius, tunnel._horseshoe_dims_at(s_c).y)
					var cible: float = (bp[1] as Vector3).y + sect + c[3]
					h += maxf(cible - h, 0.0) * w
				# place, escalier : aplanis
				if am.get("melange", false):
					# gares voisines : chaque plat pèse l'inverse du carré de sa distance (exact sur chaque quai)
					var sw: float = 0.0
					var sy: float = 0.0
					var wmax: float = 0.0
					for pl in am["plats"]:
						var d5: float = _dist_poly(q, pl[0])
						var w5: float = 1.0 - smoothstep(0.0, pl[2], d5)
						if w5 > 0.0:
							var k5: float = w5 / (d5 * d5 + 0.01)
							sw += k5
							sy += k5 * float(pl[1])
							wmax = maxf(wmax, w5)
					if sw > 0.0:
						h = lerpf(h, sy / sw, wmax)
				else:
					for pl in am.get("plats", []):
						var d: float = _dist_poly(q, pl[0])
						var w2: float = 1.0 - smoothstep(0.0, pl[2], d)
						h = lerpf(h, pl[1], w2)
				# rampes (tapis couverts de Solaise) : terrain mis à la pente continue de la rampe dans son couloir
				for rp in am.get("rampes", []):
					var ra: Vector3 = rp[0]
					var rb2: Vector3 = rp[1]
					var ab: Vector2 = Vector2(rb2.x - ra.x, rb2.z - ra.z)
					var lab: float = ab.length()
					var tr: float = (q - Vector2(ra.x, ra.z)).dot(ab) / maxf(lab * lab, 0.01)
					var tc: float = clampf(tr, 0.0, 1.0)
					var pc: Vector2 = Vector2(ra.x, ra.z) + ab * tc
					var lat: float = q.distance_to(pc)
					var dehors: float = maxf(-tr, tr - 1.0) * lab
					var w6: float = (1.0 - smoothstep(float(rp[2]), float(rp[2]) + float(rp[3]), lat)) \
						* (1.0 - smoothstep(0.0, float(rp[3]), maxf(dehors, 0.0)))
					h = lerpf(h, lerpf(ra.y, rb2.y, tc), w6)
				# remblai (porte Génépy) : terrain remonté jusqu'au niveau,
				# jamais abaissé (le tunnel reste couvert)
				for rm in am.get("remblais", []):
					var w4: float = 1.0 - smoothstep(0.0, rm[2], _dist_poly(q, rm[0]))
					h = maxf(h, lerpf(h, rm[1], w4))
				# terrasse sur pilotis : terrain rasé sous son niveau
				for rb in am.get("rabots", []):
					if h > rb[1]:
						var w3: float = 1.0 - smoothstep(0.0, rb[2], _dist_poly(q, rb[0]))
						h = lerpf(h, rb[1], w3)
			verts.append(Vector3(x, h, z))
			uvs.append(Vector2((x - ReliefDonnees.X_OUEST) / (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST),
				(z - ReliefDonnees.Z_NORD) / (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD)))
	for i in range(nz - 1):
		if pause.is_valid() and i % 16 == 0:
			await pause.call()
		for j in range(nx - 1):
			var a: int = i * nx + j
			idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var hp: PackedFloat32Array = PackedFloat32Array()
	for v in verts:
		hp.append(v.y)
	var normales: PackedVector3Array = PackedVector3Array()
	for i in range(nz):
		if pause.is_valid() and i % 8 == 0:
			await pause.call()
		for j in range(nx):
			normales.append(_normale_grille(hp, nx, nz, i, j, lx, lz))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normales
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	if pause.is_valid():
		await pause.call()
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# masque des bâtiments (0,25 m par pixel)
	# (pièce sans bâtiment : masque d'un pixel, une texture de moins par gare)
	var mw: int = 1 if am.get("trous", []).is_empty() else int(ceil(r.size.x * 4.0))
	var mh: int = 1 if am.get("trous", []).is_empty() else int(ceil(r.size.y * 4.0))
	var img: Image = Image.create(mw, mh, false, Image.FORMAT_L8)
	for poly in am.get("trous", []):
		var bb: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			bb = bb.expand(v)
		var i0: int = clampi(int((bb.position.y - r.position.y) * 4.0), 0, mh - 1)
		var i1: int = clampi(int((bb.end.y - r.position.y) * 4.0) + 1, 0, mh - 1)
		var j0: int = clampi(int((bb.position.x - r.position.x) * 4.0), 0, mw - 1)
		var j1: int = clampi(int((bb.end.x - r.position.x) * 4.0) + 1, 0, mw - 1)
		for i in range(i0, i1 + 1):
			if pause.is_valid() and i % 16 == 0:
				await pause.call()
			for j in range(j0, j1 + 1):
				var q: Vector2 = r.position + Vector2((j + 0.5) / 4.0, (i + 0.5) / 4.0)
				if Geometry2D.is_point_in_polygon(q, poly):
					img.set_pixel(j, i, Color.WHITE)
	if pause.is_valid():
		await pause.call()
	mesh.surface_set_material(0, _materiau_piece(r, img))
	_instance(mesh, "PieceGare")
	if au_masque:
		_rects_masque.append(r)
	else:
		_rects_pieces.append(r)
	var hs: PackedFloat32Array = PackedFloat32Array()
	for v in verts:
		hs.append(v.y)
	_pieces.append([r, nx, nz, hs, img])


## Matériau d'une pièce fine (et des traces damées) : celui du relief, emprise et masque des bâtiments.
func _materiau_piece(r: Rect2, img: Image) -> ShaderMaterial:
	# (pack haute définition : même photo et mêmes normales que le sol alentour)
	var hd_piece: bool = _tex_normales != null and ((fin != null and fin.hd) or _normales_seules != null)
	var mat: ShaderMaterial = _mat_terrain.duplicate() if hd_piece or _detail_seul else _shader(SHADER_TERRAIN)
	mat.set_shader_parameter("ortho", _tex_ortho)
	if hd_piece:
		ReliefAnneaux.regler_hd(mat, _tex_normales, _tex_ortho_hd)
	mat.set_shader_parameter("piece", 1.0)
	mat.set_shader_parameter("trous", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("emprise", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	_hiver_mat(mat, true)
	return mat


## Terrain affiché en (x, z) dans une pièce fine : [altitude, retiré (dans
## un bâtiment)] ; [NAN, false] hors des pièces. Pour les bancs.
func terrain_piece(x: float, z: float) -> Array:
	for pc in _pieces:
		var r: Rect2 = pc[0]
		if not r.has_point(Vector2(x, z)):
			continue
		var nx: int = pc[1]
		var nz: int = pc[2]
		var fx: float = (x - r.position.x) / r.size.x * (nx - 1)
		var fz: float = (z - r.position.y) / r.size.y * (nz - 1)
		var j: int = clampi(int(fx), 0, nx - 2)
		var i: int = clampi(int(fz), 0, nz - 2)
		var u: float = fx - j
		var v: float = fz - i
		var hs: PackedFloat32Array = pc[3]
		var h: float = lerpf(lerpf(hs[i * nx + j], hs[i * nx + j + 1], u),
			lerpf(hs[(i + 1) * nx + j], hs[(i + 1) * nx + j + 1], u), v)
		var img: Image = pc[4]
		if img.get_width() <= 1:
			return [h, false]
		var mx: int = clampi(int((x - r.position.x) * 4.0), 0, img.get_width() - 1)
		var mz: int = clampi(int((z - r.position.y) * 4.0), 0, img.get_height() - 1)
		return [h, img.get_pixel(mx, mz).r > 0.5]
	return [NAN, false]


## Trait ambre du tunnel et noms des lieux : en vue extérieure seulement
## (pas pour le skieur).
func montrer_trait(on: bool) -> void:
	if on == _trait_on:
		return
	_trait_on = on
	if _trait != null:
		_trait.visible = on
	# (09/10/2026 : les noms des lieux, dessinés par-dessus tout, se voyaient
	# à travers les parois de la rame — ils naissaient visibles et n'étaient
	# masqués qu'au premier passage en vue extérieure)
	for lab in get_children():
		if lab is Label3D and lab.is_in_group("relief_lieux"):
			(lab as Label3D).visible = on


## Abscisses des deux rames : le trait du tunnel s'y interrompt.
func set_rames(s1: float, s2: float) -> void:
	for m in [_mat_trait, _mat_trait.next_pass if _mat_trait != null else null]:
		if m != null:
			m.set_shader_parameter("s_rame1", s1)
			m.set_shader_parameter("s_rame2", s2)


func _shader(code: String) -> ShaderMaterial:
	var sh: Shader = Shader.new()
	sh.code = code
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("gamma", _gamma())
	m.set_shader_parameter("brume", Vector3(BRUME.r, BRUME.g, BRUME.b))
	return m


func _instance(mesh: Mesh, nom: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = nom
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | Cabin.LAYER_RELIEF
	add_child(mi)
	return mi


## Trait du tunnel : l'axe de bout en bout, tous les 10 m.
func _build_trait() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: PackedVector3Array = PackedVector3Array()
	var s: float = 0.0
	while s < PNConstants.LENGTH:
		pts.append(tunnel.transform_at(s).origin)
		s += 10.0
	pts.append(tunnel.transform_at(PNConstants.LENGTH).origin)
	for k in range(pts.size() - 1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var sa: float = minf(k * 10.0, PNConstants.LENGTH)
		var sb: float = minf((k + 1) * 10.0, PNConstants.LENGTH)
		var t: Vector3 = (b - a).normalized()
		for e in [[a, -1.0, sa], [b, -1.0, sb], [b, 1.0, sb], [a, -1.0, sa], [b, 1.0, sb], [a, 1.0, sa]]:
			st.set_normal(t)
			st.set_uv(Vector2(e[1], e[2]))
			st.add_vertex(e[0])
	# plein là où il est à découvert, 45 % à travers la montagne
	_mat_trait = _shader(SHADER_TRAIT % ["", "couleur.a"])
	var rx: ShaderMaterial = _shader(SHADER_TRAIT % [", depth_test_disabled", "0.45"])
	_mat_trait.next_pass = rx
	st.set_material(_mat_trait)
	var mi: MeshInstance3D = _instance(st.commit(), "TraitTunnel")
	mi.extra_cull_margin = 50.0
	# construit en tâche de fond : s'il a déjà été masqué (skieur, vue
	# cabine), il doit NAÎTRE masqué (retour d'utilisateur, 11/10/2026 : « en
	# mode skieur, j'ai toujours le tracé orange du funi »)
	mi.visible = _trait_on
	_trait = mi


## Flancs du bloc détaillé (« jupe ») : de sa bordure jusqu'à Y_SOCLE, sous
## l'anneau lointain, colorés comme le bord de l'orthophoto — ils bouchent
## les écarts entre les deux maillages.
func _build_flancs() -> void:
	var mat: ShaderMaterial = _shader(SHADER_FLANC)
	mat.set_shader_parameter("ortho", _tex_ortho)
	mat.set_shader_parameter("bloc", Vector4(ReliefDonnees.X_OUEST, ReliefDonnees.Z_NORD,
		ReliefDonnees.X_EST, ReliefDonnees.Z_SUD))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = ReliefDonnees.NX
	var nz: int = ReliefDonnees.NZ
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
	for bord in [b0, b1, b2, b3]:
		for k in range(bord.size() - 1):
			var a: Vector2i = bord[k]
			var b: Vector2i = bord[k + 1]
			var pa: Vector3 = Vector3(ReliefDonnees.X_OUEST + a.y * _dx, _h[a.x * nx + a.y], ReliefDonnees.Z_NORD + a.x * _dz)
			var pb: Vector3 = Vector3(ReliefDonnees.X_OUEST + b.y * _dx, _h[b.x * nx + b.y], ReliefDonnees.Z_NORD + b.x * _dz)
			var ua: Vector2 = Vector2(float(a.y) / (nx - 1), float(a.x) / (nz - 1))
			var ub: Vector2 = Vector2(float(b.y) / (nx - 1), float(b.x) / (nz - 1))
			var qa: Vector3 = Vector3(pa.x, Y_SOCLE, pa.z)
			var qb: Vector3 = Vector3(pb.x, Y_SOCLE, pb.z)
			for e in [[pa, ua], [pb, ub], [qb, ub], [pa, ua], [qb, ub], [qa, ua]]:
				st.set_uv(e[1])
				st.add_vertex(e[0])
	st.set_material(mat)
	_instance(st.commit(), "Flancs")


# --- Hiver et sol du skieur (07/10/2026) -----------------------------------------

var _mats_hiver: Array = []
var _hiver: float = 0.0
var _tex_pistes: Texture2D = null


func _hiver_mat(m: ShaderMaterial, pistes_ok: bool) -> void:
	if pistes_ok:
		if _tex_pistes == null:
			_tex_pistes = load("res://textures/web/pistes_masque.png" if OS.has_feature("web")
				else "res://textures/pistes_masque.png") as Texture2D
		m.set_shader_parameter("pistes", _tex_pistes)
		m.set_shader_parameter("avec_pistes", 1.0)
	m.set_shader_parameter("hiver", _hiver)
	m.set_shader_parameter("leger", 1.0 if _leger else 0.0)
	_mats_hiver.append(m)
	_ombres_sur(m)


## Neige, relief ombré et pistes damées (skieur jouable) : 1 ; été
## (photographie aérienne seule, vue extérieure) : 0.
## Ombres portées sur la neige (PC, cran 0) : le relief garde son aspect, sans éclairage ; une
## part de sa couleur passe en albédo, et le soleil dédié ne rend que cette part, sauf à l'ombre.
const OMBRE_FORCE: float = 0.45
const _ALBEDO_TERRAIN: String = "ALBEDO = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));"
var _shaders_ombres: Dictionary = {}     # shader d'origine → version qui reçoit l'ombre
var _ombres_permises: bool = false
var _ombres_force: float = 0.0


func _shader_ombres(sh: Shader) -> Shader:
	if _shaders_ombres.has(sh):
		return _shaders_ombres[sh]
	var code: String = sh.code
	if not code.contains(_ALBEDO_TERRAIN):
		_shaders_ombres[sh] = sh
		return sh
	code = code.replace("render_mode unshaded, fog_disabled, cull_disabled;",
		"render_mode fog_disabled, cull_disabled, ambient_light_disabled, specular_disabled;
uniform float ombre_k = 0.0;")
	code = code.replace(_ALBEDO_TERRAIN, "vec3 c_fin = pow(mix(c, brume, clamp(1.0 - exp(-d / 28000.0), 0.0, 0.7)), vec3(gamma));
	ALBEDO = c_fin * ombre_k;
	EMISSION = c_fin * (1.0 - ombre_k);
	ROUGHNESS = 1.0;")
	code += "
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += ATTENUATION;
	}
}
"
	var s2: Shader = Shader.new()
	s2.code = code
	_shaders_ombres[sh] = s2
	_shaders_ombres[s2] = s2
	return s2


func _ombres_sur(m: ShaderMaterial) -> void:
	if not _ombres_permises or m.shader == null:
		return
	m.shader = _shader_ombres(m.shader)
	m.set_shader_parameter("ombre_k", _ombres_force)


## permises : shaders éclairés ou d'origine ; actives : le soleil dédié est allumé.
func set_ombres_portees(permises: bool, actives: bool) -> void:
	var force: float = OMBRE_FORCE if permises and actives else 0.0
	if permises == _ombres_permises and is_equal_approx(force, _ombres_force):
		return
	var retour: bool = _ombres_permises and not permises
	_ombres_permises = permises
	_ombres_force = force
	for m in _mats_hiver:
		var mat: ShaderMaterial = m
		if retour:
			for k in _shaders_ombres:
				if _shaders_ombres[k] == mat.shader and k != mat.shader:
					mat.shader = k
					break
		else:
			_ombres_sur(mat)


## Relief léger (crans ≥ 3, puces intégrées et petites cartes) : ni grain procédural de la neige, ni détail de près
## (bosses, sillons, paillettes, grain de roche et de paroi). La photo, les normales et l'ombrage restent : le relief
## garde sa lecture, il perd le grain qu'on ne voit qu'à quelques mètres.
var _leger: bool = false


func set_leger(oui: bool) -> void:
	if oui == _leger:
		return
	_leger = oui
	for m in _mats_hiver:
		(m as ShaderMaterial).set_shader_parameter("leger", 1.0 if oui else 0.0)
	if fin != null and fin.anneaux != null:
		fin.anneaux.regler_detail(not oui and fin.repli < ReliefFin.REPLI_MAX)
	elif _mat_terrain != null and not oui:
		_mat_terrain.set_shader_parameter("a_detail", 1.0 if ReliefAnneaux._tex_detail != null else 0.0)
	if _mat_terrain != null and oui:
		_mat_terrain.set_shader_parameter("a_detail", 0.0)
	print("[Relief] %s" % ("léger : sans grain ni détail de près" if oui else "détail complet"))


func set_hiver(f: float) -> void:
	if absf(f - _hiver) < 0.001:
		return
	_hiver = f
	for m in _mats_hiver:
		(m as ShaderMaterial).set_shader_parameter("hiver", f)


## Altitude du sol AFFICHÉ en (x, z) : la pièce fine d'une gare si l'on y
## est (hors bâtiments), sinon les triangles du bloc — le skieur glisse
## exactement sur ce qu'on voit.
## Sol sur lequel les lignes sont calculées : le même à tous les crans. Sur la maille à 50 m, le sol affiché
## bombe et se creuse de plusieurs mètres : la garde au sol relevait les pylônes un par un, câble en dents
## de scie et angles à l'arrivée en gare (Loyes P15-P17, Fontaine Froide P9-P10).
func hauteur_ligne(x: float, z: float) -> float:
	if _pas <= 1 or _h25.is_empty() or _etape < 1:
		return hauteur_sol(x, z)
	for pc in _pieces:
		if (pc[0] as Rect2).has_point(Vector2(x, z)):
			return hauteur_sol(x, z)
	var h25: float = _tri_sur(_h25, x, z, 1)
	if couloirs != null:
		var hc2: float = couloirs.hauteur(x, z, h25)
		if not is_nan(hc2):
			return hc2
	return h25


func hauteur_sol(x: float, z: float) -> float:
	if _etape < 1:
		return -INF
	for pc in _pieces:
		if (pc[0] as Rect2).has_point(Vector2(x, z)):
			var tp: Array = terrain_piece(x, z)
			if not is_nan(float(tp[0])):
				return float(tp[0])
	var hb: float = _hauteur_tri(x, z)
	if couloirs != null:
		# (trace damée d'un TKD : déblai et remblai, le relief de base percé dessous)
		var hc: float = couloirs.hauteur(x, z, hb)
		if not is_nan(hc):
			return hc
	return hb


## Normale lissée du sol (différences centrées sur ± e mètres).
func normale_sol(x: float, z: float, e: float = 3.0) -> Vector3:
	var gx: float = (hauteur_sol(x + e, z) - hauteur_sol(x - e, z)) / (2.0 * e)
	var gz: float = (hauteur_sol(x, z + e) - hauteur_sol(x, z - e)) / (2.0 * e)
	return Vector3(-gx, 1.0, -gz).normalized()


## Le point (x, z) est-il dans l'emprise du relief détaillé ?
func dans_le_bloc(x: float, z: float, marge: float = 30.0) -> bool:
	return x > ReliefDonnees.X_OUEST + marge and x < ReliefDonnees.X_EST - marge \
		and z > ReliefDonnees.Z_NORD + marge and z < ReliefDonnees.Z_SUD - marge


## Altitude du terrain (m) au point (x, z) du repère du jeu, bilinéaire,
## dans le bloc détaillé (−INF tant qu'il n'est pas décodé).
func hauteur(x: float, z: float) -> float:
	if _etape < 1:
		return -INF
	return _hauteur_bloc(x, z)


func _hauteur_bloc(x: float, z: float) -> float:
	if fin != null and fin.fine_ici(x, z):
		return fin.hauteur(x, z)
	var fx: float = clampf((x - ReliefDonnees.X_OUEST) / _dx, 0.0, ReliefDonnees.NX - 1.001)
	var fz: float = clampf((z - ReliefDonnees.Z_NORD) / _dz, 0.0, ReliefDonnees.NZ - 1.001)
	var i: int = int(fz)
	var j: int = int(fx)
	var u: float = fx - j
	var v: float = fz - i
	var n: int = ReliefDonnees.NX
	return lerpf(lerpf(_h[i * n + j], _h[i * n + j + 1], u),
		lerpf(_h[(i + 1) * n + j], _h[(i + 1) * n + j + 1], u), v)


## Altitude partout : bloc détaillé, sinon anneau lointain.
func hauteur_partout(x: float, z: float) -> float:
	if _etape < 1:
		return -INF
	if x >= ReliefDonnees.X_OUEST and x <= ReliefDonnees.X_EST \
			and z >= ReliefDonnees.Z_NORD and z <= ReliefDonnees.Z_SUD:
		return _hauteur_bloc(x, z)
	var n: int = ReliefLointainDonnees.N
	var pas: float = ReliefLointainDonnees.PAS
	var fx: float = clampf((x - ReliefLointainDonnees.X_OUEST) / pas, 0.0, n - 1.001)
	var fz: float = clampf((z - ReliefLointainDonnees.Z_NORD) / pas, 0.0, n - 1.001)
	var i: int = int(fz)
	var j: int = int(fx)
	var u: float = fx - j
	var v: float = fz - i
	return lerpf(lerpf(_hl[i * n + j], _hl[i * n + j + 1], u),
		lerpf(_hl[(i + 1) * n + j], _hl[(i + 1) * n + j + 1], u), v)


func _gamma() -> float:
	return GAMMA_WEB if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0


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
		lab.add_to_group("relief_lieux")
		lab.visible = _trait_on          # vue extérieure seulement
		add_child(lab)
