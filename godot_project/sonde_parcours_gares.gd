## Sonde (pas un banc de la suite : les défauts trouvés dépendent de la graine) — parcours au clavier dans les gares à escaliers (16/11/2026, retour d'utilisateur : « je me prends des murs, je
## n'arrive pas à monter des escaliers »). Dans chaque gare, le skieur à pied marche au clavier (vraie touche Z, Maj de
## temps en temps) dans des directions tirées au hasard (graine fixe), la vue tournée comme à la souris, en 3e puis en
## 1re personne. Échec si :
##  - il traverse un mur : un rayon entre deux positions successives, à hauteur de buste, touche le décor fixe ;
##  - il tombe : chute signalée par le skieur, ou plus de 4 m perdus en une seconde ;
##  - il reste coincé : Z tenu, il n'avance plus dans aucune des quatre directions ;
##  - le filet de dégagement du jeu se déclenche (corps pris dans le décor).
##   godot --headless --fixed-fps 60 --path godot_project -s sonde_parcours_gares.gd -- [--gare=funival_aval] [--graine=1]
extends SceneTree

const R_ZONE: float = 28.0          # rayon exploré autour du point de départ
const SEGMENT_S: float = 4.0
const SEGMENTS: int = 10
const BLOQUE_S: float = 2.0

var _main: Node
var _f: int = 0
var _ok: bool = true
var _rng := RandomNumberGenerator.new()
var _gares: Array = []      # [nom, ligne ou "", amont ?]
var _ig: int = 0
var _prem: bool = false
var _etat: String = "attente"
var _att: int = 0
var _centre: Vector3
var _seg: int = 0
var _t: float = 0.0
var _cap: float = 0.0
var _p_prec: Vector3
var _p_bloc: Vector3
var _t_bloc: float = 0.0
var _tours: int = 0
var _hist: Array = []       # [t, y]
var _d0: int = 0
var _chutes: int = 0
var _bilan: Array = []
var _filtre: String = ""
var _p_avant_filet: Vector3 = Vector3.ZERO
var _embarques: int = 0


## Collisions qui touchent une sphère de 0,4 m au buste et aux pieds du skieur en p (noms des corps et de leurs parents).
func _touches(sk: SkieurJoueur, p: Vector3) -> String:
	var noms: PackedStringArray = PackedStringArray()
	for h in [0.3, 1.0]:
		var q := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.4
		q.shape = sph
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * h)
		q.exclude = [sk.get_rid()]
		q.collision_mask = sk.collision_mask
		for r in sk.get_world_3d().direct_space_state.intersect_shape(q, 8):
			var c: Node = r.collider
			var nom: String = "%s/%s" % [c.get_parent().name if c.get_parent() != null else "", c.name]
			if not nom in noms:
				noms.append(nom)
	return ", ".join(noms)


func _initialize() -> void:
	var graine: int = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--graine="):
			graine = int(a.substr(9))
		elif a.begins_with("--gare="):
			_filtre = a.substr(7)
	_rng.seed = graine
	_gares = [["pn_val_claret", "", false], ["funival_aval", "funival", false], ["funival_amont", "funival", true],
		["grande_motte_aval", "tph_grande_motte", false], ["grande_motte_amont", "tph_grande_motte", true],
		["fornet_aval", "tph_fornet", false], ["fornet_amont", "tph_fornet", true],
		["solaise_aval", "tcd10_solaise", false], ["solaise_amont", "tcd10_solaise", true]]
	if _filtre != "":
		_gares = _gares.filter(func(g): return String(g[0]).contains(_filtre))
	LigneRemontee.construction_en_fond = false
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(label: String, cond: bool, detail: String) -> void:
	print("%s %s — %s" % ["[OK]  " if cond else "[ECHEC]", label, detail])
	_ok = _ok and cond


func _touche(k: Key, enfonce: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = enfonce
	Input.parse_input_event(e)


func _ligne(cle: String) -> LigneRemontee:
	for e in _main.remontees.lignes:
		if String(e[0].name) == cle:
			return e[0]
	return null


func _tick() -> void:
	_f += 1
	if _main.get("perf_manager") != null:
		_main.perf_manager.banc = true
	if _main.get("relief") == null or not _main.relief.pret or _f < 30:
		return
	var sk: SkieurJoueur = _main.get("skieur")
	match _etat:
		"attente":
			_main.basculer_skieur()
			_etat = "skieur"
		"skieur":
			if sk == null or not sk.actif or _main.get("remontees") == null:
				return
			sk.chute.connect(func(): _chutes += 1)
			_etat = "gare"
			_ig = 0
			_prem = false
			_aller()
		"gare":
			_att += 1
			var g: Array = _gares[_ig]
			var lg: LigneRemontee = _ligne(String(g[1])) if String(g[1]) != "" else null
			var occupe: bool = _main.remontees._en_cours != null or (_main.get("collisions") != null and not _main.collisions._taches.is_empty())
			if _att < 240 or ((lg != null and not lg.pret) or occupe) and _att < 4000:
				return
			if _att == 240 or _centre == Vector3.ZERO:
				pass
			_centre = sk.global_position
			_depart(sk)
		"marche":
			_marche(sk, 1.0 / 60.0)


## Point de départ de la gare : celui du jeu (dépose au pied de la remontée, place de Val Claret) ; gares amont : à
## côté du bâtiment, comme la sonde du moteur.
func _aller() -> void:
	var g: Array = _gares[_ig]
	var sk: SkieurJoueur = _main.skieur
	_att = 0
	_main.remontees.quitter()
	if sk.chausse:
		_main.basculer_ski()
	if String(g[0]) == "pn_val_claret":
		var gare: Node = _main.station_halls.gare_aval
		var dep: Array = gare.point_depart()
		_poser(dep[0], dep[1])
		return
	var lg: LigneRemontee = _ligne(String(g[1]))
	if not bool(g[2]):
		_main.aller_a_remontee(lg)
		return
	var xf: Transform3D = lg.global_transform
	var L: float = lg.longueur_h()
	var p: Vector3
	if lg is Funival:
		var fu = lg
		p = xf * Vector3(0, fu.sol_batiment() + 0.2, -(L - 0.72) + 6.0)
	else:
		var cote: float = signf(lg._x_brin(true))
		p = xf * Vector3(cote * (lg.voie * 0.5 + 12.0), 0.0, -L + 10.0)
		p.y = _main.relief.hauteur_sol(p.x, p.z) + 0.1
	var aval: Vector3 = xf.basis.z
	_poser(p, atan2(-aval.x, -aval.z))
	_main._depose_remontee = lg


func _poser(p: Vector3, cap: float) -> void:
	var sk: SkieurJoueur = _main.skieur
	_main.collisions.assurer_autour(p)
	sk.activer(p, cap)
	sk.support = null
	sk.refuge = p
	sk.dernier_sol = p
	sk.cam_yaw = cap


func _depart(sk: SkieurJoueur) -> void:
	if sk.premiere_personne != _prem:
		_main.commandes_skieur.basculer_vue()
	_seg = 0
	_t = 0.0
	_nouveau_cap(sk)
	_p_prec = sk.global_position
	_p_bloc = sk.global_position
	_t_bloc = 0.0
	_tours = 0
	_hist = []
	_d0 = sk.degagements
	_chutes = 0
	_embarques = 0
	_bilan = [0, 0, 0, 0, 0.0]          # traversées, chutes, coincés, filets, distance
	_touche(KEY_W, true)
	_etat = "marche"


func _nouveau_cap(sk: SkieurJoueur) -> void:
	_cap = _rng.randf_range(-PI, PI)
	# loin du centre : on revient vers lui
	var d: Vector3 = _centre - sk.global_position
	d.y = 0.0
	if d.length() > R_ZONE:
		_cap = atan2(-d.x, -d.z)
	_touche(KEY_SHIFT, _rng.randf() < 0.3)


func _marche(sk: SkieurJoueur, dt: float) -> void:
	_t += dt
	_t_bloc += dt
	sk.cam_yaw = lerp_angle(sk.cam_yaw, _cap, 0.15)
	# monté par mégarde dans un véhicule (cabine, siège) : ce n'est pas la gare qu'on éprouve ; on redescend au centre
	if not _main.remontees.a_bord.is_empty() or sk.embarque:
		_embarques += 1
		_main.remontees.quitter()
		_poser(_centre, _cap)
		_p_prec = _centre
		_p_bloc = _centre
		_p_avant_filet = _centre
		_hist = []
		_d0 = sk.degagements - _bilan[3]
		return
	var p: Vector3 = sk.global_position
	# mur traversé : rayon à hauteur de buste entre les deux dernières positions (décor fixe seulement)
	# (remonté d'un coup à la verticale : le jeu repose le skieur sur la gare après la dépose, ce n'est pas une traversée)
	var vertical: bool = Vector2(p.x - _p_prec.x, p.z - _p_prec.z).length() < 0.3 and absf(p.y - _p_prec.y) > 1.0
	if p.distance_to(_p_prec) > 0.02 and sk.degagements == _d0 + _bilan[3] and not vertical:
		var q := PhysicsRayQueryParameters3D.create(_p_prec + Vector3.UP * 1.1, p + Vector3.UP * 1.1)
		q.exclude = [sk.get_rid()]
		q.collision_mask = sk.collision_mask
		var h: Dictionary = sk.get_world_3d().direct_space_state.intersect_ray(q)
		# (caisse d'un véhicule en mouvement : elle a bougé entre les deux images, ce n'est pas un mur)
		if not h.is_empty() and h.collider is StaticBody3D and not (h.collider as Node).has_meta("vehicule"):
			_bilan[0] += 1
			print("   TRAVERSE %s : de %s à %s, %s" % [_gares[_ig][0], _p_prec.snapped(Vector3.ONE * 0.01), p.snapped(Vector3.ONE * 0.01), String(h.collider.get_path()).get_file()])
	var pas: float = Vector2(p.x - _p_prec.x, p.z - _p_prec.z).length()
	if pas > 1.5:
		print("   SAUT %s : %.1f m en une image, de %s à %s, porté %s" % [_gares[_ig][0], pas, _p_prec.snapped(Vector3.ONE * 0.01), p.snapped(Vector3.ONE * 0.01), str(sk.support.get_path()).get_file() if sk.support != null else "non"])
	_bilan[4] += pas
	_p_prec = p
	if sk.degagements == _d0 + _bilan[3]:
		_p_avant_filet = p
	# filet du jeu
	if sk.degagements > _d0 + _bilan[3]:
		_bilan[3] += 1
		print("   FILET %s à %s, avant %s ; touché : %s" % [_gares[_ig][0], p.snapped(Vector3.ONE * 0.01), _p_avant_filet.snapped(Vector3.ONE * 0.01), _touches(sk, _p_avant_filet)])
	# chute : plus de 4 m perdus en une seconde
	_hist.append([_t, p.y])
	while _hist.size() > 0 and _t - float(_hist[0][0]) > 1.0:
		_hist.pop_front()
	if not _hist.is_empty() and float(_hist[0][1]) - p.y > 4.0:
		_bilan[1] += 1
		print("   CHUTE %s à %s" % [_gares[_ig][0], p.snapped(Vector3.ONE * 0.01)])
		_hist = []
	# bloqué : on tourne de 90° ; quatre fois de suite, coincé
	if _t_bloc > BLOQUE_S:
		if Vector2(p.x - _p_bloc.x, p.z - _p_bloc.z).length() < 0.3:
			_tours += 1
			if _tours >= 4:
				_bilan[2] += 1
				print("   COINCE %s à %s" % [_gares[_ig][0], p.snapped(Vector3.ONE * 0.01)])
				_tours = 0
				_main.skieur.refuge = _centre
			_cap = wrapf(_cap + PI * 0.5, -PI, PI)
		else:
			_tours = 0
		_p_bloc = p
		_t_bloc = 0.0
	if _t > SEGMENT_S * (_seg + 1):
		_seg += 1
		_nouveau_cap(sk)
	if _seg >= SEGMENTS:
		_touche(KEY_W, false)
		_touche(KEY_SHIFT, false)
		_bilan[1] += _chutes
		var nom: String = "%s, %s personne" % [_gares[_ig][0], "1re" if _prem else "3e"]
		_verif(nom, _bilan[0] == 0 and _bilan[1] == 0 and _bilan[2] == 0 and _bilan[3] == 0,
			"%.0f m parcourus ; murs traversés %d, chutes %d, coincé %d, filet %d (monté dans un véhicule %d fois, écarté)" % [_bilan[4], _bilan[0], _bilan[1], _bilan[2], _bilan[3], _embarques])
		if not _prem:
			_prem = true
			_aller()
			_etat = "gare"
			return
		_prem = false
		_ig += 1
		if _ig >= _gares.size():
			print("SONDE_PARCOURS_GARES " + ("OK" if _ok else "ECHEC"))
			FinBanc.quitter(self, _main, 0 if _ok else 1)
			return
		_aller()
		_etat = "gare"
