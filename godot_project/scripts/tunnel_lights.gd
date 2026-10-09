class_name TunnelLights
extends Node3D
## Néons muraux du tunnel Perce-Neige.
## Un tube tous les 10 m sur le mur latéral, un sur deux allumé : un néon
## ALLUMÉ tous les 20 m, mesuré sur la vidéo de descente à 12 m/s (un néon
## toutes les 1,633 s en croisière, audit_physique/calage_descente.sage).
##
## Sur un tunnel en montée, les néons sont sur le mur gauche.
## En descente, ils apparaissent sur le mur droit (même physique, vue miroir).

@export var spacing_m: float = 10.0          # espacement des tubes (un sur deux allumé)
# À 1,40 m du centre, le néon était DANS le gabarit de la caisse (rayon
# 1,72 : demi-largeur 1,57 m à 0,7 m au-dessus de l'axe) — « les néons et
# les câbles défilent à l'intérieur de la cabine côté gauche en montant »
# (retour d'utilisateur, 07/10/2026, vue skieur). Sur la paroi (rayon 1,95 : 1,73 m à cette
# hauteur), à 5 cm d'elle.
@export var wall_offset: float = 1.68        # distance du centre du tunnel
@export var height_offset: float = 0.9       # hauteur (plafond)
@export var light_energy: float = 8.0
@export var light_range: float = 23.0   # recouvre l'entraxe de 20 m des
                                        # néons ALLUMÉS (un sur deux) →
                                        # éclairage uniforme, sans creux

# Culling par distance : ~225 néons + signaux = autant d'OmniLight3D qui
# participent toutes au clustering Forward+ et au fog volumétrique chaque
# frame si on les laisse actives. Au-delà de LIGHT_CULL_DIST des deux rames,
# la lumière est éteinte (le bâtonnet émissif, lui, reste visible de loin).
const LIGHT_CULL_DIST: float = 450.0
# Web (rendu Compatibility, iPad) : chaque OmniLight active coûte cher en
# WebGL2 → rayon de culling réduit. Les bâtonnets émissifs restent
# visibles au-delà, l'éclairage perçu reste uniforme.
const LIGHT_CULL_DIST_WEB: float = 200.0

var tunnel: TunnelBuilder = null
var _lights: Array = []   # paires [OmniLight3D, s_m] pour le culling
# Interrupteur général (demande du 03/10/2026 : « l'option de couper tous
# les éclairages du tunnel ») : éteint les sources ET le tube émissif.
var enabled: bool = true
var _neon_mat_on: StandardMaterial3D = null
var _neon_mat_off: StandardMaterial3D = null
var _tubes_allumes: Array[MeshInstance3D] = []
var _tubes_s: PackedFloat32Array = PackedFloat32Array()   # abscisse de chaque tube allumable
var _tubes_etat: PackedByteArray = PackedByteArray()      # 1 = allumé
var _dernier_s: float = NAN


func _ready() -> void:
	pass


func build(t: TunnelBuilder) -> void:
	tunnel = t
	_populate()


func _populate() -> void:
	var neon_color: Color = Color(0.75, 0.85, 1.0)  # blanc-bleuté néon industriel
	# Commence APRÈS la salle de gare basse et s'arrête AVANT la haute :
	# dans les salles élargies, un néon à wall_offset du centre flotterait
	# loin du mur (les gares ont leur propre éclairage plafond).
	var s: float = tunnel.station_low_end + 4.0
	var max_s: float = tunnel.station_high_start - 4.0

	# Mesh visible du néon lui-même (bâtonnet émissif)
	var neon_mat: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat.albedo_color = Color(0.9, 0.95, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = neon_color
	neon_mat.emission_energy_multiplier = 4.0
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_neon_mat_on = neon_mat

	# Tube ÉTEINT : un néon sur deux — retour d'exploitation 2026-07 : le
	# tunnel est éclairé uniformément TOUT DU LONG (pas de zones sombres),
	# mais seul un néon sur deux est allumé. Le tube éteint reste visible
	# (gris, sans émission ni lumière).
	var neon_mat_off: StandardMaterial3D = StandardMaterial3D.new()
	neon_mat_off.albedo_color = Color(0.45, 0.47, 0.50)
	neon_mat_off.roughness = 0.55
	neon_mat_off.metallic = 0.2
	_neon_mat_off = neon_mat_off

	var neon_mesh: BoxMesh = BoxMesh.new()
	neon_mesh.size = Vector3(0.05, 0.08, 1.6)    # tube horizontal 1.6 m

	var idx: int = 0
	while s < max_s:
		var lit: bool = (idx % 2) == 0
		_add_neon(s, neon_mesh, neon_mat if lit else neon_mat_off,
			neon_color, lit)
		# Tube d'évitement DROIT (voie de la rame 2) : sa propre rangée de
		# néons — la rangée principale suit la paroi du tube GAUCHE, et le
		# tube droit restait noir (retour d'essai 2026-07-13). Ajoutée
		# seulement quand les deux tubes sont réellement séparés (offset
		# suffisant) ; aux extrémités fusionnées, la rangée principale
		# éclaire l'espace commun.
		if absf(tunnel.passing_loop_offset(s, 1.0)) > wall_offset + 0.4:
			_add_neon(s, neon_mesh, neon_mat if lit else neon_mat_off,
				neon_color, lit, true)
		idx += 1
		s += spacing_m
	# (Signaux LED verts du croisement SUPPRIMÉS — retour d'essai 2026-07 :
	# ils teintaient le tunnel en vert/rouge à l'entrée, au milieu et à la
	# sortie de l'évitement ; l'éclairage doit rester uniforme comme ailleurs.)



# Éteint les OmniLight3D loin des deux rames (rame 1 à s_cabin, rame 2 à
# MIROIR_S − s_cabin). À appeler à basse fréquence (~2 Hz) depuis main.gd —
# inutile de le faire à 60 Hz, une rame parcourt < 7 m entre deux appels.
#
# Allumage PROGRESSIF (retour d'essai iPad 2026-07-12) : l'énergie monte
# en fondu sur les LIGHT_FADE_M derniers mètres avant la limite de
# culling au lieu d'un tout-ou-rien — les néons ne « poppent » plus par
# salves à l'approche, et light_energy est un simple uniform (pas cher).
const LIGHT_FADE_M: float = 60.0

## `s_web` : rame autour de laquelle allumer les lampes en web (la rame
## pilotée, ou en vue salle des machines celle qui approche de la gare).
##
## Allumage PAR ZONE (retour d'un utilisateur du 06/10/2026 : « le tunnel vu de la
## machinerie, s'il est allumé, ne s'allume que progressivement à
## l'approche de la rame ») : un tube ne s'allume que dans la zone éclairée
## autour d'une rame, tube après tube quand elle avance.
const ZONE_ALLUMEE: float = 300.0

func update_light_culling(s_cabin: float, s_web: float = NAN) -> void:
	var web: bool = OS.has_feature("web")
	var cull: float = LIGHT_CULL_DIST_WEB if web else LIGHT_CULL_DIST
	var s_ghost: float = PNConstants.miroir(s_cabin)
	_dernier_s = s_cabin
	_appliquer_zone(s_cabin, s_ghost)
	if is_nan(s_web):
		s_web = s_cabin
	for entry in _lights:
		var light: OmniLight3D = entry[0]
		var ls: float = entry[1]
		# Web : autour de la rame pilotée seulement. Le rendu Compatibility
		# ne dessine qu'un nombre limité de lampes par image et laisse
		# tomber les autres dans un ordre arbitraire : en seconde moitié de
		# montée, les néons de l'autre rame (créés avant, plus bas)
		# prenaient la place de ceux de la cabine → tunnel noir (retour
		# iPad du 05/10/2026). Elle est à plus d'un kilomètre : ses néons
		# ne servent pas en vue cabine.
		var d: float = absf(ls - s_web) if web else minf(absf(ls - s_cabin), absf(ls - s_ghost))
		# jamais de lampe hors de la zone allumée (tube éteint)
		d = maxf(d, minf(absf(ls - s_cabin), absf(ls - s_ghost)) + cull - ZONE_ALLUMEE)
		var k: float = clampf((cull - d) / LIGHT_FADE_M, 0.0, 1.0)
		light.visible = k > 0.01
		if light.visible:
			light.light_energy = light_energy * k if enabled else 0.0


## Tubes allumés seulement dans la zone de ZONE_ALLUMEE autour de l'une
## ou l'autre rame ; le matériau n'est changé que quand l'état change (le
## matériau éteint est déjà compilé : pas de recompilation en web).
func _appliquer_zone(s_a: float, s_b: float) -> void:
	for i in range(_tubes_allumes.size()):
		var ts: float = _tubes_s[i]
		var allume: int = 1 if enabled and minf(absf(ts - s_a), absf(ts - s_b)) <= ZONE_ALLUMEE else 0
		if _tubes_etat[i] != allume:
			_tubes_etat[i] = allume
			_tubes_allumes[i].set_surface_override_material(0, _neon_mat_on if allume == 1 else _neon_mat_off)


## Allume ou coupe tout l'éclairage du tunnel : sources lumineuses ET
## tubes. Retour d'essai iPad du 05/10/2026 : « tu éteins le tunnel puis tu
## le rallumes et ça reste tout sombre » (non reproduit sous Chromium ni
## WebKit). L'ancien interrupteur cachait les ~200 lampes et changeait le
## mode d'ombrage du matériau des tubes : deux changements qui imposent au
## rendu web de recompiler des shaders à chaud. Ici rien ne change de
## nature : les lampes restent en place à énergie nulle, et les tubes
## prennent le matériau des tubes éteints, déjà compilé au chargement (la
## moitié des tubes l'utilise).
func set_enabled(on: bool) -> void:
	enabled = on
	for i in range(_tubes_allumes.size()):
		_tubes_etat[i] = 2      # forcer la mise à jour
	if is_nan(_dernier_s):
		for tube in _tubes_allumes:
			tube.set_surface_override_material(0, _neon_mat_on if on else _neon_mat_off)
	else:
		_appliquer_zone(_dernier_s, PNConstants.miroir(_dernier_s))
	for entry in _lights:
		var light: OmniLight3D = entry[0]
		if light.visible and not on:
			light.light_energy = 0.0


func _add_neon(s: float, mesh: BoxMesh, neon_mat: StandardMaterial3D,
		color: Color, lit: bool = true, right_tube: bool = false) -> void:
	var xform: Transform3D = tunnel.transform_at(s)
	var right: Vector3 = xform.basis.x
	var up: Vector3 = xform.basis.y
	# Néon sur le mur gauche (côté -X local). Dans la chambre de croisement,
	# la paroi s'écarte de |passing_loop_offset| → le néon suit le mur au
	# lieu de rester suspendu au milieu (la rame le traverserait).
	# `right_tube` : néon du tube d'évitement DROIT — posé sur le flanc
	# gauche de CE tube (axe à +offset, mur à +offset − wall_offset).
	var loop_off: float = absf(tunnel.passing_loop_offset(s, 1.0))
	var wall_pos: Vector3
	if right_tube:
		wall_pos = xform.origin + right * (loop_off - wall_offset) + up * height_offset
	else:
		wall_pos = xform.origin - right * (wall_offset + loop_off) + up * height_offset

	# Source lumineuse — seulement pour les tubes ALLUMÉS (un sur deux)
	if lit:
		var light: OmniLight3D = OmniLight3D.new()
		light.position = wall_pos
		light.light_color = color
		light.light_energy = light_energy
		light.omni_range = light_range
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		add_child(light)
		_lights.append([light, s])

	# Bâtonnet visible (pour voir la source dans le brouillard volumétrique)
	var neon: MeshInstance3D = MeshInstance3D.new()
	neon.mesh = mesh
	neon.set_surface_override_material(0, neon_mat)
	if lit:
		_tubes_allumes.append(neon)
		_tubes_s.append(s)
		_tubes_etat.append(1)
	neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neon)
	# Positionner APRÈS add_child (global_transform nécessite d'être dans l'arbre)
	var neon_xform: Transform3D = xform
	neon_xform.origin = wall_pos
	neon.global_transform = neon_xform
