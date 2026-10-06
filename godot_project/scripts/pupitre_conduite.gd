class_name PupitreConduite
extends Node3D
## Pupitre de conduite de la cabine, reproduit d'après les photos de Kevin
## du 26/04/2026 (094300, 094305, 094308, 094402) et la vidéo de descente de
## 2013 — demande du 06/10/2026 : « reproduire fidèlement le poste de
## commande avec les bons boutons, les bons noms et l'écran LCD qui marche
## et affiche les bonnes infos en direct ».
##
## Un caisson gris sur le tube transversal, avec :
##   - à gauche, sur un cadre noir : l'écran tactile Pro-face (EcranProface,
##     rendu en direct dans une texture, 4 fois par seconde) ;
##   - à droite, la plaque à boutons, disposée comme sur la photo :
##       PORTES 1 à 6 : OUVERTURE (blanc), FERMETURE (vert)
##       PORTES 7 à 12 : OUVERTURE (blanc), FERMETURE (vert)
##       PRÊT (vert)   · bouton noir · sélecteur · commutateur à clé
##       KLAXON        · ÉCLAIRAGE : CABINE (0/1), COMPARTIMENT, SECOURS
##     Les libellés du bouton noir, du sélecteur et du commutateur à clé
##     de la deuxième rangée sont illisibles sur les photos : laissés sans
##     texte plutôt qu'inventés.
## Les voyants suivent l'état réel de la rame : FERMETURE vert portes
## fermées, OUVERTURE blanc portes ouvertes, PRÊT vert rame prête,
## COMPARTIMENT blanc éclairage de la cabine, SECOURS toujours allumé,
## sélecteur CABINE sur 0 ou 1, KLAXON enfoncé quand on klaxonne.
## Repère : celui de l'intérieur de la cabine (avant = −Z) ; la face du
## pupitre est inclinée vers le conducteur.

const R_TUBE: float = 0.13
const LONG_TUBE: float = 1.10
const INCLINAISON: float = 0.07
const X_ECRAN: float = -0.215          # centre du cadre de l'écran
const X_PLAQUE: float = 0.095          # centre de la plaque à boutons
const L_CADRE: float = 0.30
const L_PLAQUE: float = 0.31
const P_FACE: float = 0.19             # profondeur de la face
const ECRAN_L: float = 0.17           # dalle ≈ 7,7" (photo : ¾ de la largeur de la plaque)
const ECRAN_H: float = 0.10
const PERIODE_ECRAN: float = 0.25

var _face: Node3D = null
var _sv: SubViewport = null
var ecran: EcranProface = null
var _t_ecran: float = 0.0
var _voyants: Dictionary = {}          # nom → [matériau, couleur allumée]
var _cabine_bouton: Node3D = null
var _klaxon: Node3D = null


func construire(z_console: float, y_top: float, lumieres: Array) -> void:
	var gris: StandardMaterial3D = _mat(Color(0.70, 0.71, 0.72), 0.6, 0.1)
	var plaque_mat: StandardMaterial3D = _mat(Color(0.62, 0.62, 0.59), 0.75, 0.0)   # gris clair mat (photo)
	var noir: StandardMaterial3D = _mat(Color(0.07, 0.07, 0.08), 0.5, 0.2)
	var chrome: StandardMaterial3D = _mat(Color(0.70, 0.71, 0.73), 0.35, 0.75)
	var filet: StandardMaterial3D = _mat(Color(0.20, 0.20, 0.22), 0.7, 0.0)
	# tube transversal
	var tube: MeshInstance3D = _cylindre(gris, R_TUBE, LONG_TUBE, 28)
	tube.name = "PupitreTube"
	tube.position = Vector3(0.0, y_top - R_TUBE - 0.015, z_console)
	tube.rotation = Vector3(INCLINAISON, 0.0, PI * 0.5)
	add_child(tube)
	for xb in [-LONG_TUBE * 0.38, LONG_TUBE * 0.38]:
		_boite(_mat(Color(0.25, 0.25, 0.28), 0.45, 0.7), Vector3(0.024, y_top + 0.9, 0.024),
			Vector3(xb, (y_top - R_TUBE - 0.95) * 0.5, z_console + 0.04), self)
	# face inclinée : caisson sous la face, cadre noir, plaque à boutons
	_face = Node3D.new()
	_face.name = "FacePupitre"
	_face.position = Vector3(0.0, y_top, z_console)
	_face.rotation = Vector3(INCLINAISON, 0.0, 0.0)
	add_child(_face)
	var x0: float = X_ECRAN - L_CADRE * 0.5
	var x1: float = X_PLAQUE + L_PLAQUE * 0.5
	# caisson juste assez haut pour rejoindre le tube sous les bords de la face
	_boite(gris, Vector3(x1 - x0 + 0.01, 0.055, P_FACE + 0.006),
		Vector3((x0 + x1) * 0.5, -0.0305, 0.0), _face)
	_boite(noir, Vector3(L_CADRE, 0.006, P_FACE), Vector3(X_ECRAN, 0.0, 0.0), _face)
	_boite(plaque_mat, Vector3(L_PLAQUE, 0.006, P_FACE), Vector3(X_PLAQUE, 0.0, 0.0), _face)
	_construire_ecran()
	_etiquette("Pro-face", Vector2(X_ECRAN, 0.068), 26, Color(0.55, 0.56, 0.60))
	_construire_boutons(chrome, noir, filet)
	# éclairage doux de la face (fait partie de l'éclairage cabine)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0.0, y_top + 0.06, z_console + 0.05)
	fill.light_color = Color(0.92, 0.96, 1.0)
	fill.light_energy = 0.22
	fill.omni_range = 0.55
	fill.shadow_enabled = false
	fill.light_cull_mask = Cabin.LAYER_RAME
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	lumieres.append(fill)


func _construire_ecran() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(int(EcranProface.L), int(EcranProface.H))
	_sv.transparent_bg = false
	_sv.disable_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_sv)
	ecran = EcranProface.new()
	_sv.add_child(ecran)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _sv.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(ECRAN_L, ECRAN_H)
	q.material = m
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "EcranProface"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# couché sur la face, haut de l'écran vers le pare-brise
	mi.position = Vector3(X_ECRAN, 0.0035, -0.016)
	mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_face.add_child(mi)


func _construire_boutons(chrome: StandardMaterial3D, noir: StandardMaterial3D,
		filet: StandardMaterial3D) -> void:
	# grille : 4 colonnes, 3 rangées (z vers le conducteur)
	var cols: Array = [X_PLAQUE - 0.105, X_PLAQUE - 0.040, X_PLAQUE + 0.035, X_PLAQUE + 0.100]
	var rangs: Array = [-0.058, 0.012, 0.074]
	var c_blanc: Color = Color(1.0, 0.98, 0.92)
	var c_vert: Color = Color(0.25, 1.0, 0.45)
	# rangée 1 : portes
	for g in range(2):
		var xa: float = cols[2 * g]
		var xb: float = cols[2 * g + 1]
		_cadre(filet, xa - 0.03, xb + 0.03, rangs[0] - 0.048, rangs[0] + 0.026,
			"PORTES 1 à 6" if g == 0 else "PORTES 7 à 12")
		_lumineux(chrome, Vector2(xa, rangs[0]), "ouverture_%d" % g, c_blanc)
		_lumineux(chrome, Vector2(xb, rangs[0]), "fermeture_%d" % g, c_vert)
		_etiquette("OUVERTURE", Vector2(xa, rangs[0] - 0.032), 14, Color(0.06, 0.06, 0.07))
		_etiquette("FERMETURE", Vector2(xb, rangs[0] - 0.032), 14, Color(0.06, 0.06, 0.07))
	# rangée 2 : PRÊT, bouton noir, sélecteur, commutateur à clé
	_lumineux(chrome, Vector2(cols[0], rangs[1]), "pret", c_vert)
	_etiquette("PRÊT", Vector2(cols[0], rangs[1] - 0.032), 16, Color(0.06, 0.06, 0.07))
	_poussoir_noir(chrome, noir, Vector2(cols[1], rangs[1]))
	var sel: Node3D = _selecteur(chrome, noir, Vector2(cols[2], rangs[1]))
	sel.rotation.y = 0.5
	_cle(chrome, noir, Vector2(cols[3], rangs[1]))
	# rangée 3 : KLAXON, groupe ÉCLAIRAGE
	_klaxon = _poussoir_noir(chrome, noir, Vector2(cols[0], rangs[2]))
	_etiquette("KLAXON", Vector2(cols[0], rangs[2] - 0.032), 15, Color(0.06, 0.06, 0.07))
	_cadre(filet, cols[1] - 0.03, cols[3] + 0.03, rangs[2] - 0.046, rangs[2] + 0.026, "ÉCLAIRAGE")
	_cabine_bouton = _selecteur(chrome, noir, Vector2(cols[1], rangs[2]))
	_etiquette("CABINE", Vector2(cols[1], rangs[2] - 0.032), 14, Color(0.06, 0.06, 0.07))
	_etiquette("0", Vector2(cols[1] - 0.017, rangs[2] - 0.012), 12, Color(0.06, 0.06, 0.07))
	_etiquette("1", Vector2(cols[1] + 0.017, rangs[2] - 0.012), 12, Color(0.06, 0.06, 0.07))
	_lumineux(chrome, Vector2(cols[2], rangs[2]), "compartiment", c_blanc)
	_etiquette("COMPARTIMENT", Vector2(cols[2], rangs[2] - 0.032), 13, Color(0.06, 0.06, 0.07))
	_lumineux(chrome, Vector2(cols[3], rangs[2]), "secours", c_blanc)
	_etiquette("SECOURS", Vector2(cols[3], rangs[2] - 0.032), 14, Color(0.06, 0.06, 0.07))


## Met à jour voyants, commandes et écran depuis l'état de la rame.
func mettre_a_jour(ph: TrainPhysics, dt: float, vehicule: int, ecran_visible: bool) -> void:
	if ph == null:
		return
	var ouvertes: bool = ph.door_leaves_open or ph.doors_open
	var pret: bool = ph.pret_externe == 1 if ph.pret_externe >= 0 \
		else (not ouvertes and not ph.emergency and not ph.cable_rupture)
	for g in range(2):
		_allumer("ouverture_%d" % g, ouvertes)
		_allumer("fermeture_%d" % g, not ouvertes)
	_allumer("pret", pret)
	_allumer("compartiment", ph.lights_cabin)
	_allumer("secours", true)
	if _cabine_bouton != null:
		_cabine_bouton.rotation.y = -0.6 if ph.lights_cabin else 0.6
	if _klaxon != null:
		_klaxon.position.y = 0.002 if ph.horn else 0.0055
	if not ecran_visible or ecran == null:
		return
	_t_ecran -= dt
	if _t_ecran > 0.0:
		return
	_t_ecran = PERIODE_ECRAN
	var e: EcranProface = ecran
	e.vitesse = absf(ph.vitesse_roues())
	e.distance = PNConstants.distance_compteur(ph.s, ph.direction)
	e.vehicule = vehicule
	var en_gare: bool = absf(ph.v) < 0.05 and (ph.s < PNConstants.START_S + 3.0
		or ph.s > PNConstants.STOP_S - 3.0)
	e.page_portes = en_gare
	e.portes_ouvertes = ouvertes
	e.arret_frein_service = ph.maint_brake or ph.brake > 0.5 or ph.manual_brake_held
	e.arret_elec = ph.arret_elec or ph.emergency
	e.alarme = ph.alarme_externe or ph.speed_cap_external < PNConstants.V_MAX or ph.cable_rupture
	e.pret_motrice = not ph.cable_rupture and not ph.emergency
	e.pret_autre = ph.pret_autre_externe if ph.pret_externe >= 0 else not ph.cable_rupture
	e.marche = ph.trip_started and absf(ph.v) > 0.05
	e.autorisation_portes = en_gare and not ph.trip_started
	e.frein_voie_leve = not ph.cable_rupture and ph.overspeed_level < 3
	e.ralentisseur_leve = true
	e.portes_secours_fermees = true
	e.vitesse_reduite = ph.speed_cap_external < PNConstants.V_MAX
	e.queue_redraw()
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- éléments ---------------------------------------------------------------

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _boite(m: Material, taille: Vector3, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = taille
	b.material = m
	mi.mesh = b
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cylindre(m: Material, r: float, h: float, seg: int = 18) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.material = m
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sur_face(n: Node3D, p: Vector2, y: float) -> Node3D:
	n.position = Vector3(p.x, y, p.y)
	_face.add_child(n)
	return n


## Bouton-poussoir lumineux : bague chromée et cabochon (s'allume).
func _lumineux(chrome: StandardMaterial3D, p: Vector2, nom: String, c: Color) -> void:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = _eteint(c)
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	_sur_face(_cylindre(m, 0.0135, 0.011), p, 0.0065)
	_voyants[nom] = [m, c]


## Cabochon éteint : blanc laiteux grisé, vert presque noir (sur la photo
## le blanc éteint reste clair, le vert éteint est sombre).
func _eteint(c: Color) -> Color:
	return c.darkened(0.55) if c.g < 0.99 or c.r > 0.9 else c.darkened(0.88)


func _allumer(nom: String, on: bool) -> void:
	var v: Array = _voyants.get(nom, [])
	if v.is_empty():
		return
	var m: StandardMaterial3D = v[0]
	var e: float = 2.2 if on else 0.0
	if m.emission_energy_multiplier != e:
		m.emission_energy_multiplier = e
		m.albedo_color = (v[1] as Color) if on else _eteint(v[1])


func _poussoir_noir(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> Node3D:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	return _sur_face(_cylindre(noir, 0.0145, 0.008), p, 0.0055)


## Sélecteur rotatif : bouton noir et index blanc (tourne autour de y).
func _selecteur(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> Node3D:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	var pivot: Node3D = Node3D.new()
	_sur_face(pivot, p, 0.006)
	var corps: MeshInstance3D = _cylindre(noir, 0.0135, 0.010)
	pivot.add_child(corps)
	var index: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = Vector3(0.004, 0.016, 0.022)
	b.material = noir
	index.mesh = b
	index.position = Vector3(0.0, 0.010, 0.0)
	pivot.add_child(index)
	var blanc: MeshInstance3D = MeshInstance3D.new()
	var bb: BoxMesh = BoxMesh.new()
	bb.size = Vector3(0.0045, 0.002, 0.012)
	bb.material = _mat(Color(0.95, 0.95, 0.93), 0.4, 0.0)
	blanc.mesh = bb
	blanc.position = Vector3(0.0, 0.0185, -0.004)
	pivot.add_child(blanc)
	return pivot


func _cle(chrome: StandardMaterial3D, noir: StandardMaterial3D, p: Vector2) -> void:
	_sur_face(_cylindre(chrome, 0.0175, 0.008), p, 0.004)
	_sur_face(_cylindre(chrome, 0.012, 0.014), p, 0.010)
	var cle: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = Vector3(0.003, 0.022, 0.016)
	b.material = noir
	cle.mesh = b
	_sur_face(cle, p, 0.026)


## Cadre de groupe gravé, libellé au milieu du côté haut.
func _cadre(filet: StandardMaterial3D, xa: float, xb: float, za: float, zb: float, titre: String) -> void:
	var e: float = 0.0012
	for z in [za, zb]:
		_boite(filet, Vector3(xb - xa, 0.0008, e), Vector3((xa + xb) * 0.5, 0.0034, z), _face)
	for x in [xa, xb]:
		_boite(filet, Vector3(e, 0.0008, zb - za), Vector3(x, 0.0034, (za + zb) * 0.5), _face)
	var lab: Label3D = _etiquette(titre, Vector2((xa + xb) * 0.5, za), 18, Color(0.05, 0.05, 0.06))
	lab.outline_size = 14
	lab.outline_modulate = Color(0.62, 0.62, 0.59)


## Libellé gravé, à plat sur la face, lisible depuis le siège.
func _etiquette(t: String, p: Vector2, taille: int, c: Color) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = t
	l.font_size = taille
	l.pixel_size = 0.00048   # plus gros qu'en vrai : lisible depuis le siège
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_sur_face(l, p, 0.0036)
	return l
