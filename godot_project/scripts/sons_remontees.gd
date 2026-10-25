class_name SonsRemontees
extends Node3D
## Sons des remontées du domaine (retour d'utilisateur, 25/10/2026) :
##   - les gares s'entendent de loin et montent quand on s'approche (sons
##     positionnés, atténués avec la distance) : débrayables (réducteur,
##     pneus des lanceurs, pinces) ou pinces fixes ; muettes à l'arrêt, plus
##     graves au ralenti ;
##   - à bord : vent du télésiège, intérieur d'une télécabine ou d'une grande
##     cabine (3S, téléphérique), téléski ; leur force suit la vitesse ;
##   - le lanceur : ronflement des pneus dont la hauteur suit la vitesse du
##     véhicule (freinage à l'arrivée, accélération au départ) ;
##   - chaque pylône : une salve de chocs, un par galet du balancier, espacés
##     du pas des galets à la vitesse du câble ; porteur (choc grave) ou
##     compression (choc sec) ; étouffée et plus grave en cabine ; on entend
##     aussi passer les autres véhicules au pylône le plus proche ;
##   - l'arrêt d'urgence : frein de poulie et câble qui vibre.
## Sons : tools_sons_remontees.py (synthétisés, calés sur des vidéos de lignes).

var domaine: RemonteesDomaine = null
const DOSSIER: String = "res://sounds/remontees/"
const N_GARES: int = 4                 # gares entendues à la fois
const PAS_GALET: float = 0.52
var _gares: Array = []                 # AudioStreamPlayer3D
var _ligne: AudioStreamPlayer = null   # à bord : vent / intérieur
var _lanceur: AudioStreamPlayer = null
var _coups: Array = []                 # AudioStreamPlayer (à bord), en tourniquet
var _coups3d: Array = []               # AudioStreamPlayer3D (pylône proche)
var _arret: AudioStreamPlayer = null
var _sons: Dictionary = {}
var _t_gares: float = 0.0
var _file: Array = []                  # chocs à venir : [t, son, 3D ?, position, volume, hauteur]
var _t: float = 0.0
var _d_prec: float = NAN               # à bord : distance précédente le long de la ligne
var _etats: Dictionary = {}            # ligne → dernier état (arrêt d'urgence)
var _proche: Array = []                # [ligne, pylône, d, {i véhicule → d précédent}]


func _ready() -> void:
	for nom in ["gare_debrayable", "gare_fixe", "lanceur", "ligne_siege", "ligne_cabine", "ligne_3s", "teleski",
			"galet_support", "galet_compression", "arret_urgence"]:
		var st: AudioStream = load(DOSSIER + nom + ".wav")
		if st is AudioStreamWAV and not nom.begins_with("galet") and nom != "arret_urgence":
			var w: AudioStreamWAV = (st as AudioStreamWAV).duplicate()
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = maxi(int(w.get_length() * w.mix_rate) - 1, 0)
			st = w
		_sons[nom] = st
	for k in range(N_GARES):
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 220.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_reglage_web3d(p)
		add_child(p)
		_gares.append([p, null])
	_ligne = _joueur()
	_lanceur = _joueur()
	_lanceur.stream = _sons["lanceur"]
	_arret = _joueur()
	_arret.stream = _sons["arret_urgence"]
	for k in range(8):
		_coups.append(_joueur())
	for k in range(6):
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		_reglage_web3d(p3)
		add_child(p3)
		_coups3d.append(p3)


func _joueur() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	if PNConstants.safari_web():
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(p)
	return p


func _reglage_web3d(p: AudioStreamPlayer3D) -> void:
	if PNConstants.safari_web():
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM


func _process(delta: float) -> void:
	if domaine == null or domaine.skieur == null or not domaine.skieur.actif:
		_tout_couper()
		return
	_t += delta
	var sk: Vector3 = domaine.skieur.global_position
	_t_gares -= delta
	if _t_gares <= 0.0:
		_t_gares = 0.3
		_purger_etats()
		_choisir_gares(sk)
		_choisir_pylone(sk)
	_maj_gares(delta)
	_a_bord(delta)
	_pylone_proche()
	_arrets()
	_jouer_file()


func _tout_couper() -> void:
	for e in _gares:
		(e[0] as AudioStreamPlayer3D).stop()
	_ligne.stop()
	_lanceur.stop()


# --- gares ------------------------------------------------------------------------------

func _choisir_gares(sk: Vector3) -> void:
	var cand: Array = []
	for e in domaine.lignes:
		var lg: LigneRemontee = e[0]
		if not lg.roule:
			continue
		var L: float = lg.longueur_h()
		for aval in [true, false]:
			var zc: float = lg.l_gare * 0.5 if aval else -L - lg.l_gare * 0.5
			var p: Vector3 = lg.global_transform * Vector3(0, lg.terrain(0.0 if aval else L) + 3.0, zc)
			var d: float = p.distance_to(sk)
			if d < 220.0:
				cand.append([d, lg, p])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in range(N_GARES):
		var e2: Array = _gares[k]
		var p3: AudioStreamPlayer3D = e2[0]
		if k >= cand.size():
			e2[1] = null
			continue
		var lg2: LigneRemontee = cand[k][1]
		var son: String = "gare_fixe" if (lg2.fixe() or lg2.vaetvient()) else "gare_debrayable"
		if p3.stream != _sons[son]:
			p3.stream = _sons[son]
		p3.global_position = cand[k][2]
		e2[1] = lg2


func _maj_gares(delta: float) -> void:
	for e in _gares:
		var p3: AudioStreamPlayer3D = e[0]
		if e[1] != null and not is_instance_valid(e[1]):
			e[1] = null
		var lg: LigneRemontee = e[1]
		if lg == null or not lg.roule:
			if p3.playing:
				p3.volume_db = move_toward(p3.volume_db, -60.0, delta * 60.0)
				if p3.volume_db <= -59.0:
					p3.stop()
			continue
		var r: float = clampf(lg.regime(), 0.0, 1.0)
		var cible: float = -60.0 if r < 0.02 else -8.0 + 20.0 * log(maxf(r, 0.05)) / log(10.0)
		if not p3.playing and r > 0.02:
			p3.volume_db = -60.0
			p3.play(randf() * 4.0)
		p3.volume_db = move_toward(p3.volume_db, cible, delta * 40.0)
		p3.pitch_scale = lerpf(0.55, 1.0, r)


# --- à bord -----------------------------------------------------------------------------

func _son_ligne(lg: LigneRemontee) -> String:
	if lg.teleski():
		return "teleski"
	if lg.tricable() or lg.vaetvient():
		return "ligne_3s"
	if lg.famille.begins_with("cabine"):
		return "ligne_cabine"
	return "ligne_siege"


func _a_bord(delta: float) -> void:
	var ab: Array = domaine.a_bord
	if ab.is_empty() or not is_instance_valid(ab[0]) or not (ab[0] as LigneRemontee).roule:
		_ligne.volume_db = move_toward(_ligne.volume_db, -60.0, delta * 50.0)
		_lanceur.volume_db = move_toward(_lanceur.volume_db, -60.0, delta * 50.0)
		if _ligne.volume_db <= -59.0:
			_ligne.stop()
		if _lanceur.volume_db <= -59.0:
			_lanceur.stop()
		_d_prec = NAN
		return
	var lg: LigneRemontee = ab[0]
	var i: int = ab[1]
	if i >= lg.nombre_vehicules():
		return
	var s: float = lg._vehicules[i][1]
	var z: Array = lg.zone(s)
	var v: float = lg.vitesse_en(s) * lg.regime()
	var vr: float = clampf(v / maxf(lg.vitesse, 0.1), 0.0, 1.2)
	var son: String = _son_ligne(lg)
	if _ligne.stream != _sons[son]:
		_ligne.stream = _sons[son]
	if not _ligne.playing:
		_ligne.volume_db = -60.0
		_ligne.play(randf() * 6.0)
	# le vent et le roulement suivent la vitesse ; en gare, abrité
	var cible: float = -60.0 if vr < 0.02 else -10.0 + 20.0 * log(maxf(vr, 0.05)) / log(10.0)
	if z[0] != "ligne" and son == "ligne_siege":
		cible -= 8.0
	_ligne.volume_db = move_toward(_ligne.volume_db, cible, delta * 30.0)
	_ligne.pitch_scale = lerpf(0.75, 1.05, clampf(vr, 0.0, 1.0))
	# lanceur : en gare d'un débrayable, pneus à la vitesse du véhicule
	var pneus: bool = z[0] != "ligne" and not lg.fixe() and not lg.vaetvient() and v > 0.05
	var c2: float = -9.0 if pneus else -60.0
	if pneus and not _lanceur.playing:
		_lanceur.volume_db = -60.0
		_lanceur.play()
	_lanceur.volume_db = move_toward(_lanceur.volume_db, c2, delta * 60.0)
	_lanceur.pitch_scale = clampf(v / 5.0, 0.25, 1.8)
	if not pneus and _lanceur.volume_db <= -59.0:
		_lanceur.stop()
	# pylônes franchis par le véhicule où l'on est (pas au téléphérique
	# va-et-vient : il n'a pas de boucle)
	if lg.vaetvient():
		_d_prec = NAN
		return
	var p: Vector3 = lg.point(s)[0]
	var d: float = -p.z
	var montee: bool = signf(p.x) == signf(lg._x_brin(true))
	if z[0] == "ligne" and not is_nan(_d_prec) and absf(d - _d_prec) < 5.0:
		for q in lg._pyl:
			var dp: float = q[1]
			if (_d_prec - dp) * (d - dp) <= 0.0 and d != _d_prec:
				_salve(lg, q[0], montee, absf(v), false, Vector3.ZERO)
	_d_prec = d if z[0] == "ligne" else NAN


## Salve de chocs au passage d'un balancier : un par galet, au pas des galets.
func _salve(lg: LigneRemontee, py: Node, montee: bool, v: float, en3d: bool, pos: Vector3) -> void:
	if v < 0.2:
		return
	var compo: Array = []
	if py is PyloneRemontee:
		compo = (py as PyloneRemontee).compo_montee if montee else (py as PyloneRemontee).compo_descente
	var liste: Array = []          # types de chocs, dans l'ordre
	for g in compo:
		var n: int = int(g[0]) if g[0] != null else 2
		var nat: String = String(g[1])
		for k in range(n if nat != "SC" else n / 2):
			liste.append("galet_compression" if nat == "C" else ("galet_support" if nat == "S" else ("galet_support" if k % 2 == 0 else "galet_compression")))
	if liste.is_empty():
		liste = ["galet_support", "galet_support", "galet_support", "galet_support"]
	var pas: float = PAS_GALET if not lg.teleski() else 0.36
	var dt: float = pas / v
	var cabine: bool = lg.famille.begins_with("cabine")
	var vol: float = (-14.0 if cabine else -6.0) - (10.0 if en3d else 0.0)
	var haut: float = 0.8 if cabine else 1.0
	for k in range(liste.size()):
		_file.append([_t + k * dt, liste[k], en3d, pos, vol + randf_range(-2.0, 1.0), haut * randf_range(0.93, 1.07)])


# --- pylône le plus proche (à pied ou à ski) ------------------------------------------

func _choisir_pylone(sk: Vector3) -> void:
	_proche = []
	if not domaine.a_bord.is_empty():
		return
	var meilleur: float = 70.0
	for e in domaine.lignes:
		var lg: LigneRemontee = e[0]
		if not lg.roule or lg.tricable() or lg.vaetvient():
			continue
		for q in lg._pyl:
			var py: Node3D = q[0]
			var d: float = py.global_position.distance_to(sk)
			if d < meilleur:
				meilleur = d
				_proche = [lg, py, float(q[1]), {}]


func _pylone_proche() -> void:
	if _proche.is_empty() or not is_instance_valid(_proche[0]) or not is_instance_valid(_proche[1]) \
			or not (_proche[0] as LigneRemontee).roule:
		_proche = []
		return
	var lg: LigneRemontee = _proche[0]
	var py: Node3D = _proche[1]
	var dp: float = _proche[2]
	var prec: Dictionary = _proche[3]
	for i in range(lg.nombre_vehicules()):
		var s: float = lg._vehicules[i][1]
		var p: Vector3 = lg.point(s)[0]
		var d: float = -p.z
		if absf(d - dp) > 6.0:
			prec.erase(i)
			continue
		if prec.has(i) and (float(prec[i]) - dp) * (d - dp) <= 0.0 and d != float(prec[i]):
			var montee: bool = signf(p.x) == signf(lg._x_brin(true))
			var tete: Vector3 = lg.global_transform * Vector3(p.x, p.y, -dp)
			_salve(lg, py, montee, lg.vitesse_en(s) * lg.regime(), true, tete)
		prec[i] = d


# --- arrêts d'urgence -------------------------------------------------------------------

func _arrets() -> void:
	var ab: Array = domaine.a_bord
	var ici: LigneRemontee = null
	if not ab.is_empty() and is_instance_valid(ab[0]):
		ici = ab[0]
	for e in _gares:
		if e[1] == null or not is_instance_valid(e[1]):
			continue
		var lg: LigneRemontee = e[1]
		if lg != ici:
			_surveiller(lg, false, (e[0] as Node3D).global_position)
	if ici != null:
		_surveiller(ici, true, Vector3.ZERO)


func _purger_etats() -> void:
	for k in _etats.keys():
		if not is_instance_valid(k):
			_etats.erase(k)


func _surveiller(lg: LigneRemontee, a_bord: bool, pos: Vector3) -> void:
	var avant: String = _etats.get(lg, lg.etat)
	_etats[lg] = lg.etat
	if lg.etat == "urgence" and avant != "urgence":
		if a_bord:
			_arret.volume_db = -4.0
			_arret.play()
		else:
			_file.append([_t, "arret_urgence", true, pos, -2.0, 1.0])


# --- file des chocs ----------------------------------------------------------------------

func _jouer_file() -> void:
	var reste: Array = []
	for c in _file:
		if float(c[0]) > _t:
			reste.append(c)
			continue
		if bool(c[2]):
			var p3: AudioStreamPlayer3D = _coups3d.pop_front()
			_coups3d.append(p3)
			p3.stream = _sons[c[1]]
			p3.global_position = c[3]
			p3.volume_db = c[4]
			p3.pitch_scale = c[5]
			p3.play()
		else:
			var p: AudioStreamPlayer = _coups.pop_front()
			_coups.append(p)
			p.stream = _sons[c[1]]
			p.volume_db = c[4]
			p.pitch_scale = c[5]
			p.play()
	_file = reste
