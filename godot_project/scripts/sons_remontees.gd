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
## 3S : prises réelles depuis une cabine (tools_sons_reels.py) — ambiance de gare
## portes ouvertes, gare motrice portes fermées, ligne ; lanceurs et pylônes en
## coups uniques.
var _coup3s: AudioStreamPlayer = null
## Ruisseau sous un télésiège (retour d'utilisateur, 25/10/2026 : « au début du
## trajet du TSF on entend un ruisseau couler ») : la prise monte à l'approche
## du ruisseau (OSM) et s'éteint 40 m après.
var _ruisseau: AudioStreamPlayer = null
const PORTEE_RUISSEAU: float = 40.0
var _coup3s_b: AudioStreamPlayer = null       # second joueur : lanceur puis pylône juste après
var _zone3s: String = ""
var _x3s_prec: float = -1.0
var _pyl3s: Dictionary = {}
var _sons: Dictionary = {}
var _t_gares: float = 0.0
var _file: Array = []                  # chocs à venir : [t, son, 3D ?, position, volume, hauteur]
var _t: float = 0.0
var _d_prec: float = NAN               # à bord : distance précédente le long de la ligne
var _etats: Dictionary = {}            # ligne → dernier état (arrêt d'urgence)
var _proche: Array = []                # [ligne, pylône, d, {i véhicule → d précédent}]


## Sons des remontées (fichiers de DOSSIER), chargés à l'entrée en skieur.
const NOMS: Array = ["gare_debrayable", "gare_fixe", "lanceur", "ligne_siege", "ligne_cabine", "ligne_3s", "teleski",
	"galet_support", "galet_compression", "arret_urgence",
	"3s_gare", "3s_ligne", "3s_motrice", "3s_lanceur_acc", "3s_lanceur_dec", "3s_pylone",
	"tcd_gare", "tcd_ligne", "tcd_lanceur_acc", "tcd_lanceur_dec", "tcd_pyl_s", "tcd_pyl_c", "tcd_pyl_cc", "tcd_pyl_sc", "tcd_pyl_c1", "tsd_pyl_c", "tke_pyl_c1",
	"tsd_galet_c", "tsd_galet_s", "tcd_galet_c", "tcd_galet_s", "tsf_galet_c", "tsf_galet_s", "tkd_galet_c", "tkd_galet_s",
	"tke_galet_c", "boisses_galet_s",
	"tkd_gare", "tkd_ligne", "tkd_depart", "tkd_lacher", "tkd_pyl_s", "tkd_pyl_c",
	"tsf_motrice", "tsf_arrivee", "tsf_ligne", "tsf_arret", "tsf_redemarrage", "tsf_embarquement", "tsf_pyl_s", "tsf_pyl_c",
	"tsf_ruisseau",
	"tsd_forfait", "tsd_gare", "tsd_portillons", "tsd_embarquement", "tsd_pyl_cc", "tsd_pyl_s", "tsd_ligne", "tsd_arret", "tsd_arrete", "tsd_redemarrage", "tsd_arrivee", "tsd_debarquement", "tsd_gare_haut", "boisses_gare", "boisses_lanceur_acc", "boisses_ligne", "boisses_pyl_s", "boisses_lanceur_dec", "file_huees",
	"tke_gare", "tke_depart", "tke_ligne", "tke_pyl_s", "tke_pyl_c", "tke_arrivee",
	"tph_quai", "tph_ligne", "tph_croisement", "tph_arrivee"]


## Chargement d'avance, en tâche de fond, dès le démarrage (PC) : à l'entrée en skieur, load() les trouve prêts
## (58 ms d'un bloc sur le fil principal sinon, relevé du 10/11/2026). Mêmes ressources.
static func precharger() -> void:
	for nom in NOMS:
		ResourceLoader.load_threaded_request(DOSSIER + nom + ".wav")
	for e in SONS_FUNI:
		ResourceLoader.load_threaded_request("res://sounds/%s.wav" % e[1])


func _ready() -> void:
	for nom in NOMS:
		var st: AudioStream = load(DOSSIER + nom + ".wav")
		if st is AudioStreamWAV and nom in ["gare_debrayable", "gare_fixe", "lanceur", "ligne_siege", "ligne_cabine",
				"ligne_3s", "teleski", "3s_gare", "3s_ligne", "3s_motrice", "tcd_gare", "tcd_ligne", "tkd_gare", "tkd_ligne", "tsf_motrice", "tsf_arrivee", "tsf_ligne", "tsf_ruisseau",
				"tsd_gare", "tsd_ligne", "tsd_arrete", "tsd_gare_haut", "boisses_gare", "boisses_ligne", "tke_gare", "tke_ligne", "tph_quai", "tph_ligne"]:
			var w: AudioStreamWAV = (st as AudioStreamWAV).duplicate()
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = maxi(int(w.get_length() * w.mix_rate) - 1, 0)
			st = w
		_sons[nom] = st
	for e in SONS_FUNI:
		var st2: AudioStream = load("res://sounds/%s.wav" % e[1])
		if st2 is AudioStreamWAV and bool(e[2]):
			var w2: AudioStreamWAV = (st2 as AudioStreamWAV).duplicate()
			w2.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w2.loop_begin = 0
			w2.loop_end = maxi(int(w2.get_length() * w2.mix_rate) - 1, 0)
			st2 = w2
		_sons[e[0]] = st2
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
	_coup3s = _joueur()
	_ruisseau = _joueur()
	_coup3s_b = _joueur()
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
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("sons_remontees", t0_prof)
	else:
		_process_corps(delta)


## Ambiances des remontées plus fortes (retour d'utilisateur, 27/10/2026 : « trop
## faibles ») ; le vent de dehors s'efface sous elles (`couverture`, lue par
## SonsSkieur), comme au funiculaire.
const GAIN_AMBIANCE: float = 6.0
static var couverture: float = 0.0       # 0 : rien des remontées ; 1 : à bord ou au pied d'une gare


func _maj_couverture(delta: float, sk: Vector3) -> void:
	var c: float = 0.0
	if not domaine.a_bord.is_empty():
		c = 1.0
	else:
		for e in _gares:
			var p3: AudioStreamPlayer3D = e[0]
			if p3.playing and p3.volume_db > -40.0:
				c = maxf(c, clampf(1.0 - (p3.global_position.distance_to(sk) - 25.0) / 60.0, 0.0, 1.0))
	couverture = move_toward(couverture, c, delta * 1.5)


func _process_corps(delta: float) -> void:
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
	_maj_couverture(delta, sk)
	_portiques(sk)
	_a_bord(delta)
	_pylone_proche()
	_arrets()
	_jouer_file()


func _tout_couper() -> void:
	couverture = 0.0
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
				cand.append([d, lg, p, aval])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in range(N_GARES):
		var e2: Array = _gares[k]
		var p3: AudioStreamPlayer3D = e2[0]
		if k >= cand.size():
			e2[1] = null
			continue
		var lg2: LigneRemontee = cand[k][1]
		var son: String = "gare_fixe" if (lg2.fixe() or lg2.vaetvient()) else "gare_debrayable"
		if _prises(lg2) == "tsf":
			son = "tsf_motrice" if bool(cand[k][3]) else "tsf_arrivee"
		elif _prises(lg2) == "tph":
			son = "tph_quai"
		elif _prises(lg2) == "funi":
			# (gare amont : la salle des machines, prise réelle ; gare aval : poulie de renvoi, sans moteur)
			son = "gare_fixe" if bool(cand[k][3]) else "funi_machines"
		elif _prises(lg2) == "tsd":
			son = "tsd_gare" if bool(cand[k][3]) else "tsd_gare_haut"
		elif _prises(lg2) != "":
			son = _prises(lg2) + "_gare"
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
		var cible: float = -60.0 if r < 0.02 else -8.0 + GAIN_AMBIANCE + 20.0 * log(maxf(r, 0.05)) / log(10.0)
		if not p3.playing and r > 0.02:
			p3.volume_db = -60.0
			p3.play(randf() * 4.0)
		p3.volume_db = move_toward(p3.volume_db, cible, delta * 40.0)
		p3.pitch_scale = lerpf(0.55, 1.0, r)


# --- portiques et portillons --------------------------------------------------------

## Sous le portique d'entrée d'une remontée, le forfait est validé (bip, toutes
## les remontées) ; aux TSD, le passage des portillons et du tapis roulant
## (retour d'utilisateur, 25/10/2026).
var _vus: Dictionary = {}          # repère → instant du dernier son


func _portiques(sk: Vector3) -> void:
	if not domaine.a_bord.is_empty():
		return
	for e in _gares:
		if e[1] == null or not is_instance_valid(e[1]):
			continue
		var lg: LigneRemontee = e[1]
		for n in domaine._portiques(lg):          # (en cache : find_children à chaque image coûtait 3 ms)
			var c: Vector3 = (n as Node3D).global_position
			if Vector2(sk.x - c.x, sk.z - c.z).length() < 1.6 and absf(sk.y - c.y) < 3.0:
				_une_fois(n, "tsd_forfait", 8.0)
		if _prises(lg) == "tsd":
			for aval in [true, false]:
				var q: Vector3 = lg.global_transform * lg.position_portillons(aval)
				if Vector2(sk.x - q.x, sk.z - q.z).length() < 1.4 and absf(sk.y - q.y) < 3.0:
					_une_fois(str(lg.get_instance_id()) + str(aval), "tsd_portillons", 15.0)


func _une_fois(cle: Variant, nom: String, delai: float) -> void:
	if _vus.has(cle) and _t - float(_vus[cle]) < delai:
		_vus[cle] = _t
		return
	_vus[cle] = _t
	_coup(null, nom)


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
	# téléski : départ à la prise de la perche, lâcher (et retour de la perche) à la fin
	var tk_ici: LigneRemontee = null
	if not ab.is_empty() and is_instance_valid(ab[0]) and (ab[0] as LigneRemontee).teleski():
		tk_ici = ab[0]
	var tsd_ici: LigneRemontee = null
	if not ab.is_empty() and is_instance_valid(ab[0]) and _prises(ab[0]) == "tsd":
		tsd_ici = ab[0]
	if tsd_ici != null and _tsd_prec == null:
		_coup(tsd_ici, "tsd_embarquement")
	elif tsd_ici == null and _tsd_prec != null and is_instance_valid(_tsd_prec):
		_coup(_tsd_prec, "tsd_debarquement")
	_tsd_prec = tsd_ici
	var tsf_ici: LigneRemontee = null
	if not ab.is_empty() and is_instance_valid(ab[0]) and (ab[0] as LigneRemontee).famille.begins_with("siege_fixe"):
		tsf_ici = ab[0]
	if tsf_ici != null and _tsf_prec == null:
		_coup(tsf_ici, "tsf_embarquement")
	_tsf_prec = tsf_ici
	if tk_ici != null and _tk_prec == null:
		_coup(tk_ici, _prises(tk_ici) + "_depart")
	elif tk_ici == null and _tk_prec != null and is_instance_valid(_tk_prec):
		_coup(_tk_prec, "tkd_lacher" if _prises(_tk_prec) == "tkd" else "tke_arrivee")
	_tk_prec = tk_ici
	if ab.is_empty() or not is_instance_valid(ab[0]) or not (ab[0] as LigneRemontee).roule:
		_ligne.volume_db = move_toward(_ligne.volume_db, -60.0, delta * 50.0)
		_lanceur.volume_db = move_toward(_lanceur.volume_db, -60.0, delta * 50.0)
		if _ligne.volume_db <= -59.0:
			_ligne.stop()
		if _lanceur.volume_db <= -59.0:
			_lanceur.stop()
		_d_prec = NAN
		_zone3s = ""
		_x3s_prec = -1.0
		_ruisseau.volume_db = move_toward(_ruisseau.volume_db, -60.0, delta * 40.0)
		if _ruisseau.volume_db <= -59.0:
			_ruisseau.stop()
		return
	var lg: LigneRemontee = ab[0]
	var i: int = ab[1]
	if i >= lg.nombre_vehicules():
		return
	var s: float = lg._vehicules[i][1]
	var z: Array = lg.zone(s)
	var v: float = lg.vitesse_en(s) * lg.regime()
	var vr: float = clampf(v / maxf(lg.vitesse, 0.1), 0.0, 1.2)
	_maj_ruisseau(delta, lg, s)
	var pref: String = _prises(lg)
	if pref != "":
		_a_bord_3s(delta, lg, s, z, v, pref)
		return
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


## 3S et télécabines, à bord (prises réelles) : ambiance de la zone (gare portes ouvertes en aval, gare
## motrice portes fermées en amont, ligne), fondue à chaque changement ;
## freinage au lanceur en entrant en gare, accélération en en sortant ;
## passage de pylône joué pour que ses chocs (1,5–2,9 s dans la prise)
## tombent au droit du pylône.
## Préfixe des prises réelles de la ligne : "3s" (Olympique), "tcd" (télécabines
## débrayables), ou "" (sons synthétisés).
func _prises(lg: LigneRemontee) -> String:
	if lg.tricable():
		return "3s"
	if lg.famille == "cabine_funi":
		return "funi"          # (avant le va-et-vient : le Funival en hérite)
	if lg.name == "tcd10_boisses":
		return "boisses"
	if lg.famille.begins_with("siege") and not lg.famille.begins_with("siege_fixe"):
		return "tsd"
	if lg.famille == "perche_debrayable":
		return "tkd"           # (les téléskis à enrouleur, différents, gardent leurs sons)
	if lg.teleski():
		return "tke"           # enrouleurs et perches en T
	if lg.famille.begins_with("siege_fixe"):
		return "tsf"
	if lg.vaetvient():
		return "tph"
	if lg.famille.begins_with("cabine") and not lg.vaetvient():
		return "tcd"
	return ""


## Prise du passage d'un pylône et instant du choc dans la prise (s) : télécabine
## selon les galets (porteur, compression, les deux, deux compressions
## rapprochées) ; 3S, une seule prise.
func _prise_pylone(lg: LigneRemontee, k: int, montee: bool, pref: String) -> Array:
	if pref == "3s":
		return ["3s_pylone", 1.6]
	if pref == "boisses":
		var pr0: Array = _prise_pylone(lg, k, montee, "tcd")
		return pr0 if String(pr0[0]) != "tcd_pyl_s" else ["boisses_pyl_s", 1.7]
	if pref == "tsd":
		# compressions : UN passage par pylône (retour d'utilisateur du 11/11/2026 : « le son des galets compression
		# sur pylône est décalé et en double ») — la prise des deux pylônes n'avait pas de choc repéré : calée à
		# 0,3 s, ses galets ne sonnaient qu'à 1,75 s (spectrogramme), et la fin (souffle) faisait un second
		# passage ; tsd_pyl_c = son premier train de chocs seul, choc à 0,3 s
		var nat0: Array = lg.pylones[k].get("montee" if montee else "descente", []).map(func(g1): return String(g1[1]))
		if "C" in nat0 and not ("S" in nat0 or "SC" in nat0):
			return ["tsd_pyl_c", 0.3]
		return ["tsd_pyl_s", 1.15]
	if pref == "tkd" or pref == "tsf" or pref == "tke":
		# (instants des chocs relus au spectrogramme, 11/11/2026 : téléski à enrouleurs, galets à 2,0 s et non 2,95 —
		# la perche qui redescend, à 3,4 s, faisait un second passage : prise réduite aux galets, tke_pyl_c1)
		var chocs: Dictionary = {"tkd": [0.3, 0.42], "tsf": [T_PYL_C_TSF, 1.65], "tke": [0.3, 1.52]}
		for g0 in lg.pylones[k].get("montee" if montee else "descente", []):
			if String(g0[1]) in ["C", "SC"]:
				return [pref + ("_pyl_c1" if pref == "tke" else "_pyl_c"), chocs[pref][0]]
		return [pref + "_pyl_s", chocs[pref][1]]
	var p: Dictionary = lg.pylones[k]
	var s_: bool = false
	var c_: bool = false
	for g in p.get("montee" if montee else "descente", []):
		var nat: String = String(g[1])
		s_ = s_ or nat in ["S", "SC"]
		c_ = c_ or nat in ["C", "SC"]
	if s_ and c_:
		return ["tcd_pyl_sc", 0.6]
	if c_:
		# une autre compression à moins de 40 m : les deux pylônes rapprochés
		for k2 in [k - 1, k + 1]:
			if k2 >= 0 and k2 < lg.pylones.size() and absf(float(lg.pylones[k2]["d"]) - float(p["d"])) < 40.0:
				for g2 in lg.pylones[k2].get("montee" if montee else "descente", []):
					if String(g2[1]) == "C":
						# (un passage court par pylône : la prise des deux pylônes, déclenchée au premier avec son second
						# train à 2,9 s, ne tombait sur le second qu'à une vitesse et un écart donnés)
						return ["tcd_pyl_c1", 0.25]
		return ["tcd_pyl_c", 6.15]      # (galets de 6,1 à 7,7 s au spectrogramme ; 6,8 tombait au milieu)
	return ["tcd_pyl_s", 1.1]


func _a_bord_3s(delta: float, lg: LigneRemontee, s: float, z: Array, v: float, pref: String) -> void:
	_lanceur.volume_db = move_toward(_lanceur.volume_db, -60.0, delta * 60.0)
	var zone: String = "ligne"
	if pref == "tkd" or pref == "tke":
		z = ["ligne", 0.0, 0.0]
	if pref == "tph":
		_a_bord_tph(delta, lg)
		return
	if pref == "funi":
		_a_bord_funi(delta, lg)
		return
	if pref == "tsd":
		var zd: String = "ligne" if z[0] == "ligne" else ("gare" if z[0] == "gare_aval" else "gare_haut")
		if zd == "ligne" and lg.regime() < 0.05 and lg.etat != "marche":
			zd = "arrete"
		if _zone3s == "ligne" and zd != "ligne" and zd != "arrete":
			_coup(lg, "tsd_arrivee")
		_zone3s = zd
		_ambiance(delta, lg, "tsd_" + zd, -2.0 if zd != "arrete" else 0.0)
		# (dès la gare : les compressions de sortie de gare sont passées avant le
		# début de la zone « ligne », leur prise arrivait trop tard — retour
		# d'utilisateur, 27/10/2026)
		_pylones_reels(lg, s, v, pref, zd != "arrete")
		return
	if pref == "tsf":
		var zt: String = "ligne" if z[0] == "ligne" else ("motrice" if z[0] == "gare_aval" else "arrivee")
		_ambiance(delta, lg, pref + "_" + zt, -2.0)
		_pylones_reels(lg, s, v, pref, zt == "ligne")
		return
	if z[0] == "gare_aval":
		zone = "gare"
	elif z[0] == "gare_amont":
		zone = "motrice" if pref == "3s" else "gare"
	# coups : freinage en entrant en gare, accélération au début du lanceur de sortie
	var x: float = z[1] if z[0] != "ligne" else -1.0
	var l: float = z[2] if z[0] != "ligne" else 0.0
	if _zone3s == "ligne" and zone != "ligne":
		_coup(lg, pref + "_lanceur_dec")
	if x >= 0.0 and _x3s_prec >= 0.0 and _x3s_prec < l - LigneRemontee.L_FREIN - 1.0 and x >= l - LigneRemontee.L_FREIN - 1.0:
		_coup(lg, pref + "_lanceur_acc")
	_x3s_prec = x
	_zone3s = zone
	# boucle d'ambiance : changement de prise en fondu ; abaissée pendant les coups
	var son: String = pref + "_" + zone
	var cible: float = -4.0 + GAIN_AMBIANCE
	if _coup3s.playing or _coup3s_b.playing:
		cible = -18.0 + GAIN_AMBIANCE
	# la cabine vibre de plus en plus à l'approche d'un pylône (retour d'utilisateur,
	# 25/10/2026) : l'ambiance monte de 5 dB dans les 2 s qui précèdent
	cible += 5.0 * _approche
	cible += _accord_vitesse(lg, son)[0]
	if lg.regime() < 0.02 and zone == "ligne":
		cible = -24.0 + GAIN_AMBIANCE         # arrêté en ligne : le vent, la cabine qui grince
	if _ligne.stream != _sons[son]:
		_ligne.volume_db = move_toward(_ligne.volume_db, -50.0, delta * 80.0)
		if _ligne.volume_db <= -49.0 or not _ligne.playing:
			_ligne.stream = _sons[son]
			_ligne.play(randf() * 3.0)
	elif not _ligne.playing:
		_ligne.volume_db = -50.0
		_ligne.play(randf() * 3.0)
	else:
		_ligne.volume_db = move_toward(_ligne.volume_db, cible, delta * 20.0)
	_ligne.pitch_scale = _accord_vitesse(lg, son)[1] if not (lg.regime() < 0.02 and zone == "ligne") else 1.0
	# pylônes : la prise démarre 1,6 s avant le pylône (à la vitesse du moment)
	if zone != "ligne" or v < 0.5:
		return
	var p: Vector3 = lg.point(s)[0]
	var d: float = -p.z
	var monte: bool = signf(p.x) == signf(lg._x_brin(true))
	_approche = 0.0
	for k in range(lg.pylones.size()):
		var dp: float = float(lg.pylones[k]["d"])
		var ecart: float = (dp - d) if monte else (d - dp)
		if ecart <= 0.0:
			continue
		_approche = maxf(_approche, clampf(1.0 - (ecart / v) / 2.0, 0.0, 1.0))
		if ecart / v > 8.0:
			continue            # (la plus longue avance d'une prise : 6,15 s ; plus loin, rien à décider à cette image)
		var pr: Array = _prise_pylone(lg, k, monte, pref)
		if String(pr[0]) == "":
			continue
		var cle: String = "%s_%d" % [lg.name, int(dp)]
		# télécabines : un choc réel par galet (comme _pylones_reels) ; le 3S garde sa prise (pas de chocs isolables)
		var liste: Array = _galets_pylone(lg, k, monte, pref) if pref != "3s" else []
		if not liste.is_empty():
			var pas: float = PAS_GALET
			var avance: float = (float(liste.size() - 1) * 0.5 * pas) / v + 0.05
			if ecart / v < avance and (not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0):
				_pyl3s[cle] = _t
				var t0: float = _t + maxf(ecart / v - avance + 0.05, 0.0)
				for j in range(liste.size()):
					_file.append([t0 + float(j) * pas / v, liste[j], false, Vector3.ZERO, randf_range(-6.0, -3.0), randf_range(0.95, 1.05)])
			continue
		# prise enregistrée à pleine vitesse : au ralenti, rejouée plus lentement (chocs des galets espacés comme sur le
		# câble), son choc d'autant plus tard
		var hp: float = clampf(lg.regime(), 0.5, 1.0)
		if ecart / v < float(pr[1]) / hp:
			if not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0:
				_pyl3s[cle] = _t
				_coup(lg, pr[0], hp)


func _maj_ruisseau(delta: float, lg: LigneRemontee, s: float) -> void:
	var proche: float = INF
	if lg.famille.begins_with("siege") and not lg.ruisseaux.is_empty() and lg.zone(s)[0] == "ligne":
		var d: float = -(lg.point(s)[0] as Vector3).z
		for dr in lg.ruisseaux:
			proche = minf(proche, absf(d - dr))
	var cible: float = -60.0
	if proche < PORTEE_RUISSEAU:
		cible = lerpf(-6.0, -40.0, proche / PORTEE_RUISSEAU)
		if not _ruisseau.playing:
			_ruisseau.stream = _sons["tsf_ruisseau"]
			_ruisseau.volume_db = -60.0
			_ruisseau.play(randf() * 4.0)
	_ruisseau.volume_db = move_toward(_ruisseau.volume_db, cible, delta * 15.0)
	if cible <= -59.0 and _ruisseau.volume_db <= -59.0 and _ruisseau.playing:
		_ruisseau.stop()


## Téléphérique (va-et-vient) : quai à l'arrêt, ligne en route ; croisement des
## deux cabines au milieu ; approche de la gare d'arrivée.
var _tph_crois: float = -100.0
var _tph_arr: float = -100.0


func _a_bord_tph(delta: float, lg: LigneRemontee) -> void:
	var tp: Telepherique = lg as Telepherique
	var en_route: bool = tp._phase == "route"
	_ambiance(delta, lg, "tph_ligne" if en_route else "tph_quai", -2.0)
	if not en_route:
		return
	var d1: float = tp._vehicules[0][1]
	var d2: float = tp._vehicules[1][1]
	if absf(d1 - d2) < 40.0 and _t - _tph_crois > 30.0:
		_tph_crois = _t
		_coup(lg, "tph_croisement")
	var ab: Array = domaine.a_bord
	var d: float = tp._vehicules[ab[1]][1]
	var monte: bool = (tp._sens > 0.0) == (int(ab[1]) == 0)
	var but: float = tp._x_quai(not monte)
	if absf(but - d) < 90.0 and absf(tp._v) > 0.5 and _t - _tph_arr > 40.0:
		_tph_arr = _t
		_coup(lg, "tph_arrivee")


## Funival à bord : ses propres sons, tirés des vidéos de la montée (vue cabine) et de la descente (salle des machines)
## — retour d'utilisateur du 11/11/2026 : « extraire les sons des différentes étapes et ambiances du Funival des vidéos
## au lieu de copier Perce-Neige » (tools_sons_reels.py, profils funi et funi_machines) : en ligne sur le viaduc ou
## dans le tunnel (hauteur et force selon la vitesse réelle), ralentissement à l'approche de la gare amont, passage de
## l'évitement (prise de 12 s, son milieu au croisement), bips puis fermeture des portes avant le départ ; la salle des
## machines s'entend autour de la gare amont.
const SONS_FUNI: Array = [["funi_dehors", "remontees/funi_dehors", true], ["funi_tunnel", "remontees/funi_tunnel", true],
	["funi_croisement", "remontees/funi_croisement", false], ["funi_buzzer", "remontees/funi_buzzer", false],
	["funi_portes", "remontees/funi_portes", false], ["funi_ralenti", "remontees/funi_ralenti", false],
	["funi_machines", "remontees/funi_machines", true]]
const FUNI_CLIP_CROISEMENT: float = 12.0    # s (funi_croisement.wav)
const FUNI_CLIP_RALENTI: float = 10.0       # s : la prise du ralentissement finit à l'arrêt en gare
var _funi_crois: float = -100.0
var _funi_buzz: float = -100.0
var _funi_portes: float = -100.0
var _funi_ral: float = -100.0
var _funi_ecart: float = INF                  # écart précédent entre les deux véhicules (ils se rapprochent ?)


func _a_bord_funi(delta: float, lg: LigneRemontee) -> void:
	var tp: Telepherique = lg as Telepherique
	var v: float = absf(tp._v)
	var fv: Funival = lg as Funival
	var ab: Array = domaine.a_bord
	var i_v: int = int(ab[1]) if ab.size() > 1 else 0
	var d_v: float = float(tp._vehicules[i_v][1])
	var dedans: bool = fv != null and fv.dans_tunnel(d_v)
	_ambiance(delta, lg, "funi_tunnel" if dedans else "funi_dehors", -6.0)
	# ralentissement : la prise finit quand le véhicule s'arrête au quai d'arrivée
	var monte: bool = (tp._sens > 0.0) == (i_v == 0)
	var but: float = tp._x_quai(not monte)
	if tp._phase != "quai" and v > 0.5 and absf(but - d_v) / maxf(v, 0.5) < FUNI_CLIP_RALENTI * 0.6 and _t - _funi_ral > 60.0:
		_funi_ral = _t
		_coup(lg, "funi_ralenti")
	if tp._phase == "quai":
		# buzzer 7 s avant le départ (durée du buzzer du Perce-Neige), puis les portes
		if tp._t_quai < 7.5 and tp._t_quai > 6.5 and _t - _funi_buzz > 20.0:
			_funi_buzz = _t
			_coup(lg, "funi_buzzer")
		if tp._t_quai < 1.2 and _t - _funi_portes > 20.0:
			_funi_portes = _t
			_coup(lg, "funi_portes")
		return
	# croisement : les deux véhicules se rapprochent à 2 v ; le milieu de la prise au moment où ils se croisent
	var d1: float = tp._vehicules[0][1]
	var d2: float = tp._vehicules[1][1]
	var ecart: float = absf(d1 - d2)
	var avant: float = ecart / maxf(2.0 * v, 1.0)
	if v > 1.0 and ecart < _funi_ecart and avant < FUNI_CLIP_CROISEMENT * 0.5 and _t - _funi_crois > 60.0:
		_funi_crois = _t
		_coup(lg, "funi_croisement")
	_funi_ecart = ecart


## Boucle d'ambiance à bord, changée en fondu ; abaissée pendant les coups,
## montée à l'approche d'un pylône.
func _ambiance(delta: float, lg: LigneRemontee, son: String, base: float) -> void:
	var cible: float = base + GAIN_AMBIANCE
	if _coup3s.playing or _coup3s_b.playing:
		cible = base - 14.0
	cible += 5.0 * _approche
	cible += _accord_vitesse(lg, son)[0]
	if lg.regime() < 0.02 and not son.ends_with("_arrete"):
		cible = base - 20.0
	if _ligne.stream != _sons[son]:
		_ligne.volume_db = move_toward(_ligne.volume_db, -50.0, delta * 80.0)
		if _ligne.volume_db <= -49.0 or not _ligne.playing:
			_ligne.stream = _sons[son]
			_ligne.play(randf() * 3.0)
	elif not _ligne.playing:
		_ligne.volume_db = -50.0
		_ligne.play(randf() * 3.0)
	else:
		_ligne.volume_db = move_toward(_ligne.volume_db, cible, delta * 20.0)
	_ligne.pitch_scale = _accord_vitesse(lg, son)[1]


## Ambiance qui suit la vitesse RÉELLE de l'installation (retour d'utilisateur du 11/11/2026 : « adapter le bruit
## ambiant des gares TS, TC, TK et 3S en fonction de la vitesse réelle ») : les prises sont enregistrées à pleine
## vitesse ; au cran réduit, au démarrage et au freinage, la machinerie et les pneus des lanceurs tournent moins vite —
## gares : plus grave (jusqu'à 0,6) et plus faible (20·log du régime) ; en ligne : un peu plus grave, un peu plus
## faible (vent, câble). [décalage de volume (dB), hauteur]
func _accord_vitesse(lg: LigneRemontee, son: String) -> Array:
	if son.ends_with("_arrete") or son.begins_with("tph"):
		return [0.0, 1.0]
	var r: float = clampf(lg.regime(), 0.0, 1.0)
	if son.contains("gare") or son.contains("motrice") or son.contains("arrivee"):
		return [20.0 * log(maxf(r, 0.08)) / log(10.0), lerpf(0.6, 1.0, r)]
	return [10.0 * log(maxf(r, 0.1)) / log(10.0), lerpf(0.8, 1.0, r)]


## Prises des pylônes, déclenchées pour que leur choc tombe au droit du pylône.
func _pylones_reels(lg: LigneRemontee, s: float, v: float, pref: String, en_ligne: bool) -> void:
	_approche = 0.0
	if not en_ligne or v < 0.5:
		return
	var p: Vector3 = lg.point(s)[0]
	var d: float = -p.z
	var monte: bool = signf(p.x) == signf(lg._x_brin(true))
	for k in range(lg.pylones.size()):
		var dp: float = float(lg.pylones[k]["d"])
		var ecart: float = (dp - d) if monte else (d - dp)
		if ecart <= 0.0:
			continue
		_approche = maxf(_approche, clampf(1.0 - (ecart / v) / 2.0, 0.0, 1.0))
		if ecart / v > 8.0:
			continue            # (la plus longue avance d'une prise : 6,15 s ; plus loin, rien à décider à cette image)
		var pr: Array = _prise_pylone(lg, k, monte, pref)
		if String(pr[0]) == "":
			continue
		var cle: String = "%s_%d" % [lg.name, int(dp)]
		# un choc réel par galet du balancier, au pas des galets et à la vitesse du câble (retour d'utilisateur du
		# 11/11/2026 : « compter le nombre de galets passés et adapter le son en fonction des galets et de la vitesse ») ;
		# le premier galet est à la moitié du balancier avant l'axe du pylône
		var liste: Array = _galets_pylone(lg, k, monte, pref)
		if not liste.is_empty():
			var pas: float = PAS_GALET if not lg.teleski() else 0.36
			var avance: float = (float(liste.size() - 1) * 0.5 * pas) / v + 0.05
			if ecart / v < avance and (not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0):
				_pyl3s[cle] = _t
				var t0: float = _t + maxf(ecart / v - avance + 0.05, 0.0)
				for j in range(liste.size()):
					_file.append([t0 + float(j) * pas / v, liste[j], false, Vector3.ZERO, randf_range(-2.5, 0.5), randf_range(0.95, 1.05)])
			continue
		var hp: float = clampf(lg.regime(), 0.5, 1.0)        # (prise de pleine vitesse rejouée à la vitesse du câble)
		if ecart / v < float(pr[1]) / hp:
			if not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0:
				_pyl3s[cle] = _t
				_coup(lg, pr[0], hp)


## Chocs de galets réels d'un pylône, dans l'ordre de passage : un par galet de chaque balancier du brin (porteur,
## compression ; un porteur-compresseur alterne les deux), pris dans la vidéo de l'appareil du même type (un choc net
## relevé dans le train de chocs d'un passage, spectrogramme du 11/11/2026). Vide : pas de chocs réels pour ce type.
func _galets_pylone(lg: LigneRemontee, k: int, montee: bool, pref: String) -> Array:
	var s_nom: String = pref + "_galet_s"
	var c_nom: String = pref + "_galet_c"
	if pref == "tke":
		s_nom = "tke_galet_c"
	elif pref == "boisses":
		c_nom = "tcd_galet_c"
	if not (_sons.has(s_nom) and _sons.has(c_nom)):
		return []
	var r: Array = []
	for g in lg.pylones[k].get("montee" if montee else "descente", []):
		var n: int = int(g[0]) if g[0] != null else 4
		var nat: String = String(g[1])
		for j in range(n if nat != "SC" else maxi(n / 2, 1)):
			r.append(c_nom if nat == "C" else (s_nom if nat == "S" else (s_nom if j % 2 == 0 else c_nom)))
	return r


var _approche: float = 0.0
var _tk_prec: LigneRemontee = null
var _tsf_prec: LigneRemontee = null
var _tsd_prec: LigneRemontee = null
const T_PYL_C_TSF: float = 2.8         # début du train de chocs (spectrogramme, 11/11/2026 ; 3,7 en tombait au milieu)


func _coup(_lg: LigneRemontee, nom: String, hauteur: float = 1.0) -> void:
	# deux joueurs : la prise la plus ancienne cède la place
	var p: AudioStreamPlayer = _coup3s
	if _coup3s.playing and not _coup3s_b.playing:
		p = _coup3s_b
	elif _coup3s.playing and _coup3s_b.playing:
		p = _coup3s if _coup3s.get_playback_position() > _coup3s_b.get_playback_position() else _coup3s_b
	p.stream = _sons[nom]
	p.volume_db = 0.0
	p.pitch_scale = hauteur
	p.play()


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
	# (chocs réels de l'appareil du même type quand il y en a, au lieu des chocs de synthèse)
	var pref_s: String = _prises(lg)
	var reel_s: String = (pref_s + "_galet_s") if pref_s != "tke" else "tke_galet_c"
	var reel_c: String = (pref_s + "_galet_c") if pref_s != "boisses" else "tcd_galet_c"
	if _sons.has(reel_s) and _sons.has(reel_c):
		liste = liste.map(func(n0: String) -> String: return reel_c if n0 == "galet_compression" else reel_s)
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
				_proche = [lg, py, float(q[1]), {}, {}]


func _pylone_proche() -> void:
	if _proche.is_empty() or not is_instance_valid(_proche[0]) or not is_instance_valid(_proche[1]) \
			or not (_proche[0] as LigneRemontee).roule:
		_proche = []
		return
	var lg: LigneRemontee = _proche[0]
	var py: Node3D = _proche[1]
	var dp: float = _proche[2]
	var prec: Dictionary = _proche[3]
	# un véhicule ne s'approche pas du pylône (en plan) de plus que le câble parcouru : tant que son écart au
	# pylône, au dernier calcul, dépasse 6 m plus ce chemin, il n'est pas recalculé (lg.point par véhicule et
	# par image : sr.pylone_proche, 0,12 ms par image en approche de gare)
	var vu: Dictionary = _proche[4]
	for i in range(lg.nombre_vehicules()):
		var s: float = lg._vehicules[i][1]
		var e: Vector2 = vu.get(i, Vector2(INF, 0.0))
		if e.x != INF and absf(e.y - dp) - 6.0 > absf(s - e.x):
			continue
		var p: Vector3 = lg.point(s)[0]
		var d: float = -p.z
		vu[i] = Vector2(s, d)
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
	if _prises(lg) == "tsd" and a_bord:
		if (lg.etat == "arret_normal" or lg.etat == "urgence") and avant == "marche":
			_coup(lg, "tsd_arret")
		elif lg.etat == "marche" and avant != "marche":
			_coup(lg, "tsd_redemarrage")
	if _prises(lg) == "tsf":
		var nom: String = ""
		if lg.etat == "arret_normal" and avant == "marche":
			nom = "tsf_arret"
		elif lg.etat == "marche" and (avant == "arret" or avant == "arret_normal"):
			nom = "tsf_redemarrage"
		if nom != "":
			if a_bord:
				_coup(lg, nom)
			else:
				_file.append([_t, nom, true, pos, 0.0, 1.0])
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
