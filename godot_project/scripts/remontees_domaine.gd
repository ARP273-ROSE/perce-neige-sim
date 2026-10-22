class_name RemonteesDomaine
extends Node3D
## Remontées mécaniques du domaine posées dans le monde du jeu, à leur place
## réelle (positions OpenStreetMap), sur le relief affiché. Données :
## RemonteesDonnees (générées par le dossier des remontées).
##
## Économie (PWA) : véhicules invisibles au-delà de VEHICULES_JUSQUA m ; une
## ligne dont le milieu est à plus de ACTIVE_JUSQUA m de la caméra ne fait
## plus avancer ses véhicules.

const LAT_O: float = 45.45188591       # origine du monde : pied de la voie du funiculaire
const LON_O: float = 6.89898136        # (mêmes constantes que tools_relief3d.py)
const M_LAT: float = 111320.0
const VEHICULES_JUSQUA: float = 700.0
const PYLONES_JUSQUA: float = 3000.0
const ACTIVE_JUSQUA: float = 2500.0

var relief: ReliefBuilder = null
var skieur: SkieurJoueur = null
var lignes: Array = []          # [LigneRemontee, milieu monde]
var _t_lod: float = 0.0
## À bord d'un siège : [ligne, indice du véhicule, place, gare de départ aval ?]
var a_bord: Array = []
var _repos: float = 0.0          # pas de nouvel embarquement juste après un débarquement
signal message(texte: String)


static func monde(lat: float, lon: float) -> Vector2:
	var m_lon: float = M_LAT * cos(deg_to_rad(LAT_O))
	return Vector2((lon - LON_O) * m_lon, -(lat - LAT_O) * M_LAT)


func construire(r: ReliefBuilder) -> void:
	relief = r
	for D in RemonteesDonnees.LIGNES:
		_poser(D)
	print("[Remontees] %d lignes posées" % lignes.size())


func _poser(D: Dictionary) -> void:
	var a: Vector2 = monde(float(D["aval"][0]), float(D["aval"][1]))
	var b: Vector2 = monde(float(D["amont"][0]), float(D["amont"][1]))
	var dirh: Vector2 = b - a
	var L: float = dirh.length()
	if L < 10.0:
		return
	dirh /= L
	var h0: float = relief.hauteur_sol(a.x, a.y)
	# profil sous l'axe, pris sur le relief AFFICHÉ (pas l'IGN) : pylônes et
	# gares posés sur le sol que l'on voit
	var prof: PackedVector2Array = PackedVector2Array()
	var d: float = 0.0
	while d < L:
		var p: Vector2 = a + dirh * d
		prof.append(Vector2(d, relief.hauteur_sol(p.x, p.y) - h0))
		d += 10.0
	prof.append(Vector2(L, relief.hauteur_sol(b.x, b.y) - h0))
	var lg: LigneRemontee = LigneRemontee.new()
	lg.name = String(D["cle"])
	lg.profil = prof
	# distances des pylônes ramenées à la longueur gare-à-gare du monde
	var Ld: float = float(D["profil"][D["profil"].size() - 1][0])
	var py: Array = []
	for p in D["pylones"]:
		var q: Dictionary = (p as Dictionary).duplicate()
		q["d"] = float(p["d"]) * L / maxf(Ld, 1.0)
		py.append(q)
	lg.pylones = py
	lg.voie = float(D["voie"])
	lg.vitesse = float(D["vitesse"])
	lg.espacement = float(D["espacement"])
	lg.famille = String(D["famille"])
	lg.sens_droite = bool(D["sens_droite"])
	lg.diametre_cable = float(D.get("diametre_cable", 47.0))
	lg.nom_ligne = String(D["nom"])
	# repère : origine au sol de la gare aval, −Z local vers l'amont
	var fwd: Vector3 = Vector3(dirh.x, 0.0, dirh.y)
	lg.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(a.x, h0, a.y))
	lg.avec_collisions = true
	add_child(lg)
	lg.construire()
	_portees(lg)
	# éclairées par la lumière de jour des vues extérieures (comme les gares)
	Cabin.tag_layer(lg, Cabin.LAYER_VOIE)
	var m: Vector2 = (a + b) * 0.5
	lignes.append([lg, Vector3(m.x, relief.hauteur_sol(m.x, m.y), m.y)])


## Distances de visibilité : véhicules proches seulement, pylônes et câble loin.
func _portees(lg: LigneRemontee) -> void:
	for c in lg.get_children():
		var portee: float = VEHICULES_JUSQUA if c is VehiculeRemontee else PYLONES_JUSQUA
		var pile: Array = [c]
		while not pile.is_empty():
			var n: Node = pile.pop_back()
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).visibility_range_end = portee
				(n as GeometryInstance3D).visibility_range_end_margin = portee * 0.05
			for k in n.get_children():
				pile.append(k)


func _ready() -> void:
	# après les lignes (véhicules déjà déplacés), avant le skieur (priorité 100)
	process_priority = 50


func _process(delta: float) -> void:
	_embarquement()
	_t_lod -= delta
	if _t_lod > 0.0:
		return
	_t_lod = 0.5
	# distance au skieur quand il est là (sa caméra le suit), sinon à la caméra
	var p: Vector3
	if skieur != null and skieur.actif:
		p = skieur.global_position
	else:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam == null:
			return
		p = cam.global_position
	for e in lignes:
		var lg: LigneRemontee = e[0]
		lg.set_process(p.distance_to(e[1]) < ACTIVE_JUSQUA + lg.longueur_h() * 0.5)


# --- monter à bord d'un télésiège -----------------------------------------------------

## Le siège arrivant par derrière « ramasse » le skieur qui attend à la ligne
## d'arrêt : il s'assoit tout seul, se laisse emporter, et se lève à la
## gare d'arrivée. Dans une cabine on entre à pied, portes ouvertes : le
## corps de collision de la cabine le porte (comme une rame du funiculaire).
func _embarquement() -> void:
	if skieur == null or not skieur.actif:
		return
	if not a_bord.is_empty():
		_suivre_siege()
		return
	_repos = maxf(0.0, _repos - get_process_delta_time())
	if _repos > 0.0:
		return
	var p: Vector3 = skieur.global_position
	for e in lignes:
		var lg: LigneRemontee = e[0]
		if lg.famille.begins_with("cabine") or lg.famille.begins_with("perche") or not lg.is_processing():
			continue
		for aval in [true, false]:
			var q: Vector3 = lg.global_transform * lg.point_embarquement(aval)
			if p.distance_to(q) > 6.0:
				continue
			var i: int = lg.vehicule_a_embarquer(aval)
			if i < 0:
				continue
			var v: VehiculeRemontee = lg.vehicule(i)
			var loc: Vector3 = v.global_transform.affine_inverse() * p
			var place0: Vector3 = v.place_assise(0)
			var W: float = 0.50 * v.places + 0.20
			# le siège arrive par derrière : le skieur est devant l'assise
			if absf(loc.x) < W * 0.5 + 0.15 and loc.z > place0.z - 0.6 and loc.z < place0.z + 0.35 \
					and absf(loc.y - place0.y) < 1.2:
				var k: int = clampi(int(floor((absf(loc.x) * signf(loc.x) + W * 0.5 - 0.10) / 0.50)), 0, v.places - 1)
				a_bord = [lg, i, k, aval]
				skieur.support = null
				skieur.embarque = true
				skieur.asseoir(_cap(v), true)
				_suivre_siege()
				message.emit("Assis — %s" % lg.nom_ligne)
				return


func _cap(v: Node3D) -> float:
	var f: Vector3 = -v.global_transform.basis.z
	return atan2(-f.x, -f.z)


func _suivre_siege() -> void:
	var lg: LigneRemontee = a_bord[0]
	var i: int = a_bord[1]
	var v: VehiculeRemontee = lg.vehicule(i)
	skieur.global_position = v.vers_monde(v.place_assise(a_bord[2]))
	skieur.velocity = Vector3.ZERO
	var cap: float = _cap(v)
	skieur._visuel.rotation = Vector3(0.0, cap, 0.0)
	skieur._visuel.position = Vector3(sin(cap), 0.0, cos(cap)) * SkieurJoueur.RECUL_ASSIS
	# arrivée à l'autre gare : il se lève sur la rampe, devant le siège
	var arr: Array = lg.arrivee(i)
	if not arr.is_empty() and bool(arr[0]) != bool(a_bord[3]):
		var aval_arr: bool = arr[0]
		var y_quai: float = (lg.global_transform * Vector3(0, lg.terrain(0.0 if aval_arr else lg.longueur_h()), 0)).y
		# hors du couloir des sièges (2,2 m à l'extérieur) : le siège continue,
		# remonte et contourne la poulie — posé devant lui, le skieur était
		# rattrapé, porté par l'assise et rassis pour la descente
		var loc: Vector3 = lg.global_transform.affine_inverse() * v.vers_monde(v.place_assise(a_bord[2]))
		loc.x = signf(loc.x if absf(loc.x) > 0.5 else 1.0) * (lg.voie * 0.5 + 2.2)
		var pos: Vector3 = lg.global_transform * loc
		pos.y = y_quai + 0.15
		skieur.embarque = false
		skieur.lever()
		skieur.global_position = pos
		skieur.dernier_sol = pos
		skieur.support = null
		message.emit("Arrivé — %s" % lg.nom_ligne)
		a_bord = []
		_repos = 6.0
