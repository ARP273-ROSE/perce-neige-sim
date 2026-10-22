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
var lignes: Array = []          # [LigneRemontee, milieu monde]
var _t_lod: float = 0.0


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
	lg.nom_ligne = String(D["nom"])
	# repère : origine au sol de la gare aval, −Z local vers l'amont
	var fwd: Vector3 = Vector3(dirh.x, 0.0, dirh.y)
	lg.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(a.x, h0, a.y))
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


func _process(delta: float) -> void:
	_t_lod -= delta
	if _t_lod > 0.0:
		return
	_t_lod = 0.5
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var p: Vector3 = cam.global_position
	for e in lignes:
		var lg: LigneRemontee = e[0]
		lg.set_process(p.distance_to(e[1]) < ACTIVE_JUSQUA + lg.longueur_h() * 0.5)
