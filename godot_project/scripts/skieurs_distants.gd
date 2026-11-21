## Mode réseau : les autres joueurs du salon (ReseauClient), dessinés avec le skieur commun (SkieurMesh) dans la
## posture qu'ils envoient (à ski, à pied, assis, debout à bord), leur nom au-dessus de la tête.
##
## Reconnaissables entre les skieurs automatiques des pistes (retour d'utilisateur du 21/11/2026 : « on identifie
## bien l'autre skieur du réseau vs les skieurs auto ? »), de près comme de loin, PWA comme PC, sans vraie lumière :
##   - tenue à SA couleur (veste et casque unis, empiècements blancs en dossard, veste un peu lumineuse) — le
##     nuanceur des skieurs le reconnaît à sa graine (INSTANCE_CUSTOM.a < 0) ;
##   - étiquette nom + distance, de taille fixe à l'écran (lisible à toute distance), contour noir, à sa couleur ;
##   - chevron à sa couleur au-dessus de la tête, grossi avec la distance (quelques pixels au moins), et une
##     balise verticale au loin (au-delà de BALISE_M) ;
##   - anneau à sa couleur au sol sous ses skis (pas à bord) ;
##   - hors champ : flèche au bord de l'écran, avec son nom et sa distance.
## La même couleur sert à son point sur la carte. Huit joueurs au plus : une quarantaine de nœuds, posés une fois.
class_name SkieursDistants
extends Node3D

const MAX: int = 8
const HAUTEUR_NOM: float = 2.15
const HAUTEUR_CHEVRON: float = 2.75
const BALISE_M: float = 80.0              # au-delà : balise verticale
const BALISE_H: float = 40.0
const MARGE_BORD: float = 46.0            # px, indicateur hors champ

var _mm: Array = []           # [ski corps, skis aux pieds, à pied, assis, debout]
var _noms: Array = []         # Label3D par place
var _chevrons: Array = []     # MeshInstance3D par place
var _balises: Array = []
var _anneaux: Array = []
var _mats: Array = []         # matériau de couleur par place (chevron, vu à travers le décor)
var _mats_sol: Array = []     # matériau de l'anneau au sol (caché par le décor, lui)
var _bords: Array = []        # indicateurs hors champ (Control)
var _calque: CanvasLayer = null
var positions: Array = []     # pieds dessinés (bancs)
var hors_champ: Array = []    # places dont l'indicateur de bord est affiché (bancs)


func _ready() -> void:
	name = "SkieursDistants"
	var mat: ShaderMaterial = SkieurMesh.materiau()
	var maill: Array = [
		SkieurMesh.passager_squelette(SkieurMesh.squelette_glisse(), "skis", "casque", mat),
		SkieurMesh.skis_aux_pieds(mat),
		SkieurMesh.passager("skis", "casque", mat),
		SkieurMesh.passager("assis", "casque", mat),
		SkieurMesh.passager("debout", "casque", mat)]
	for m in maill:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		mi.top_level = true
		add_child(mi)
		_mm.append(mm)
	var chevron := PrismMesh.new()            # pointe en bas une fois retourné
	chevron.size = Vector3(0.55, 0.45, 0.12)
	var balise := CylinderMesh.new()
	balise.top_radius = 0.18
	balise.bottom_radius = 0.18
	balise.height = 1.0
	balise.radial_segments = 6
	balise.rings = 1
	var anneau := TorusMesh.new()
	anneau.inner_radius = 0.95
	anneau.outer_radius = 1.2
	anneau.rings = 24
	anneau.ring_segments = 4
	_calque = CanvasLayer.new()
	_calque.layer = 6
	add_child(_calque)
	for k in range(MAX):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0016
		l.font_size = 30
		l.outline_size = 10
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = Color(0, 0, 0, 0.9)
		l.render_priority = 10
		l.visible = false
		l.top_level = true
		add_child(l)
		_noms.append(l)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		# (sans test de profondeur : seulement dans la passe transparente — opaque, il était caché par les bâtiments)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.render_priority = 9
		_mats.append(m)
		var ms := StandardMaterial3D.new()
		ms.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ms.disable_fog = true
		_mats_sol.append(ms)
		var mb := StandardMaterial3D.new()
		mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mb.disable_fog = true
		mb.no_depth_test = true            # la balise se voit par-dessus le relief : on retrouve le joueur
		mb.render_priority = 8
		mb.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ch := MeshInstance3D.new()
		ch.mesh = chevron
		ch.material_override = m
		ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.top_level = true
		ch.visible = false
		add_child(ch)
		_chevrons.append(ch)
		var ba := MeshInstance3D.new()
		ba.mesh = balise
		ba.material_override = mb
		ba.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ba.top_level = true
		ba.visible = false
		add_child(ba)
		_balises.append(ba)
		var an := MeshInstance3D.new()
		an.mesh = anneau
		an.material_override = _mats_sol[k]
		an.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		an.top_level = true
		an.visible = false
		add_child(an)
		_anneaux.append(an)
		_bords.append(_indicateur())


## Indicateur hors champ : un triangle orientable et une étiquette.
func _indicateur() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	var tri := Polygon2D.new()
	tri.name = "Fleche"
	tri.polygon = PackedVector2Array([Vector2(16, 0), Vector2(-10, -11), Vector2(-10, 11)])
	c.add_child(tri)
	var l := Label.new()
	l.name = "Texte"
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	_calque.add_child(c)
	return c


## Graine du nuanceur des skieurs pour un joueur du réseau : sa couleur, drapeau en alpha négatif.
static func graine_joueur(c: Color) -> Color:
	return Color(c.r, c.g, c.b, -1.0)


## Taille du chevron selon la distance : vrai à moins de 40 m, puis grossi pour garder quelques pixels.
static func echelle_chevron(dist: float) -> float:
	return clampf(dist / 16.0, 1.0, 60.0)


## Indicateur de bord : `ecran` = projection du joueur, `derriere` = derrière la caméra, `taille` = la vue.
## Rend [] s'il est dans le champ, sinon [position (Vector2) sur le bord, angle (rad) de la flèche].
static func bord_ecran(ecran: Vector2, derriere: bool, taille: Vector2, marge: float = MARGE_BORD) -> Array:
	var dedans: Rect2 = Rect2(Vector2.ZERO, taille)
	if not derriere and dedans.has_point(ecran):
		return []
	var centre: Vector2 = taille * 0.5
	var d: Vector2 = ecran - centre
	if derriere:
		d = -d                                  # derrière : la projection est en miroir
	if d.length() < 1e-3:
		d = Vector2(0.0, 1.0)
	var demi: Vector2 = centre - Vector2(marge, marge)
	var f: float = minf(demi.x / maxf(absf(d.x), 1e-3), demi.y / maxf(absf(d.y), 1e-3))
	return [centre + d * f, d.angle()]


## liste : [[pieds (Vector3), cap, posture, couleur, nom], …]
func poser(liste: Array) -> void:
	if _mm.is_empty():
		return
	var n: Array = [0, 0, 0, 0, 0]
	positions.clear()
	hors_champ.clear()
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var taille: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1, 1)
	for k in range(mini(liste.size(), MAX)):
		var e: Array = liste[k]
		var p: Vector3 = e[0]
		var b: Basis = Basis(Vector3.UP, float(e[1]))
		var po: int = int(e[2])
		var c: Color = e[3]
		var graine: Color = graine_joueur(c)
		var quoi: Array = [0, 1] if po == 0 or po == 4 else ([2] if po == 1 or po == 5 else ([3] if po == 2 else [4]))
		for q in quoi:
			var mm: MultiMesh = _mm[q]
			var j: int = n[q]
			mm.set_instance_transform(j, Transform3D(b, p))
			mm.set_instance_custom_data(j, graine)
			n[q] = j + 1
		var dist: float = cam.global_position.distance_to(p) if cam != null else 0.0
		var clair: Color = c.lerp(Color.WHITE, 0.45)
		var l: Label3D = _noms[k]
		l.text = "%s\n%s" % [String(e[4]), _dist_texte(dist)]
		l.modulate = clair
		l.global_position = p + Vector3(0.0, HAUTEUR_NOM, 0.0)
		l.visible = true
		var m: StandardMaterial3D = _mats[k]
		m.albedo_color = c.lerp(Color.WHITE, 0.15)
		(_mats_sol[k] as StandardMaterial3D).albedo_color = c
		var s: float = echelle_chevron(dist)
		var ch: MeshInstance3D = _chevrons[k]
		var yaw: float = atan2(cam.global_position.x - p.x, cam.global_position.z - p.z) if cam != null else 0.0
		# (au-dessus de l'étiquette, qui est de taille fixe à l'écran : l'écart grandit avec la distance)
		var y_ch: float = HAUTEUR_CHEVRON + 0.06 * dist + 0.225 * s
		ch.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI).scaled(Vector3(s, s, s)),
			p + Vector3(0.0, y_ch, 0.0))
		ch.visible = true
		var ba: MeshInstance3D = _balises[k]
		ba.visible = dist > BALISE_M
		if ba.visible:
			var lb: float = BALISE_H * clampf(dist / 400.0, 1.0, 6.0)
			var rb: float = clampf(dist / 400.0, 1.0, 8.0)
			(ba.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.45)
			ba.global_transform = Transform3D(Basis().scaled(Vector3(rb, lb, rb)),
				p + Vector3(0.0, y_ch + 0.25 * s + lb * 0.5, 0.0))
		var an: MeshInstance3D = _anneaux[k]
		an.visible = po == 0 or po == 1 or po == 4 or po == 5
		if an.visible:
			an.global_transform = Transform3D(Basis(), p + Vector3(0.0, 0.05, 0.0))
		positions.append(p)
		_poser_bord(k, cam, p, taille, c, String(e[4]), dist)
	for q2 in range(_mm.size()):
		(_mm[q2] as MultiMesh).visible_instance_count = n[q2]
	for k2 in range(mini(liste.size(), MAX), MAX):
		(_noms[k2] as Label3D).visible = false
		(_chevrons[k2] as Node3D).visible = false
		(_balises[k2] as Node3D).visible = false
		(_anneaux[k2] as Node3D).visible = false
		(_bords[k2] as Control).visible = false


func _poser_bord(k: int, cam: Camera3D, p: Vector3, taille: Vector2, c: Color, nom: String, dist: float) -> void:
	var ind: Control = _bords[k]
	if cam == null:
		ind.visible = false
		return
	var tete: Vector3 = p + Vector3(0.0, 1.6, 0.0)
	var derriere: bool = cam.is_position_behind(tete)
	var r: Array = bord_ecran(cam.unproject_position(tete), derriere, taille)
	ind.visible = not r.is_empty()
	if r.is_empty():
		return
	hors_champ.append(k)
	# (pas sous la manette virtuelle ni sous les boutons du bas : le bas de l'écran est réservé)
	ind.position = Vector2((r[0] as Vector2).x, minf((r[0] as Vector2).y, taille.y - 240.0))
	var fl: Polygon2D = ind.get_node("Fleche")
	fl.rotation = float(r[1])
	fl.color = c.lerp(Color.WHITE, 0.2)
	var l: Label = ind.get_node("Texte")
	l.text = "%s · %s" % [nom, _dist_texte(dist)]
	l.add_theme_color_override("font_color", c.lerp(Color.WHITE, 0.45))
	# texte du côté intérieur de l'écran
	var dx: float = cos(float(r[1]))
	var dy: float = sin(float(r[1]))
	l.position = Vector2(-l.size.x - 22.0 if dx > 0.3 else (22.0 if dx < -0.3 else -l.size.x * 0.5),
		-34.0 if dy > 0.3 else (14.0 if dy < -0.3 else -12.0))


static func _dist_texte(d: float) -> String:
	return ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % roundi(d))


func vider() -> void:
	poser([])
