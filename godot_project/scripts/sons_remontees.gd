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


func _ready() -> void:
	for nom in ["gare_debrayable", "gare_fixe", "lanceur", "ligne_siege", "ligne_cabine", "ligne_3s", "teleski",
			"galet_support", "galet_compression", "arret_urgence",
			"3s_gare", "3s_ligne", "3s_motrice", "3s_lanceur_acc", "3s_lanceur_dec", "3s_pylone",
			"tcd_gare", "tcd_ligne", "tcd_lanceur_acc", "tcd_lanceur_dec", "tcd_pyl_s", "tcd_pyl_c", "tcd_pyl_cc", "tcd_pyl_sc",
			"tkd_gare", "tkd_ligne", "tkd_depart", "tkd_lacher", "tkd_pyl_s", "tkd_pyl_c",
			"tsf_motrice", "tsf_arrivee", "tsf_ligne", "tsf_arret", "tsf_redemarrage", "tsf_embarquement", "tsf_pyl_s", "tsf_pyl_c",
			"tsf_ruisseau",
			"tsd_forfait", "tsd_gare", "tsd_portillons", "tsd_embarquement", "tsd_pyl_cc", "tsd_pyl_s", "tsd_ligne", "tsd_arret", "tsd_arrete", "tsd_redemarrage", "tsd_arrivee", "tsd_debarquement", "tsd_gare_haut", "boisses_gare", "boisses_lanceur_acc", "boisses_ligne", "boisses_pyl_s", "boisses_lanceur_dec", "file_huees",
			"tke_gare", "tke_depart", "tke_ligne", "tke_pyl_s", "tke_pyl_c", "tke_arrivee",
			"tph_quai", "tph_ligne", "tph_croisement", "tph_arrivee"]:
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
	_portiques(sk)
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
		var cible: float = -60.0 if r < 0.02 else -8.0 + 20.0 * log(maxf(r, 0.05)) / log(10.0)
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
		return pr0 if String(pr0[0]) != "tcd_pyl_s" else ["boisses_pyl_s", 1.9]
	if pref == "tsd":
		var c0: bool = false
		for g1 in lg.pylones[k].get("montee" if montee else "descente", []):
			c0 = c0 or String(g1[1]) in ["C", "SC"]
		if c0:
			# premières compressions après la gare : la prise des deux pylônes
			return ["tsd_pyl_cc", 0.3] if k == 0 else ["", 0.0]
		return ["tsd_pyl_s", 1.6]
	if pref == "tkd" or pref == "tsf" or pref == "tke":
		var chocs: Dictionary = {"tkd": [0.3, 0.5], "tsf": [T_PYL_C_TSF, 1.65], "tke": [2.95, 1.52]}
		for g0 in lg.pylones[k].get("montee" if montee else "descente", []):
			if String(g0[1]) in ["C", "SC"]:
				return [pref + "_pyl_c", chocs[pref][0]]
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
						return ["tcd_pyl_cc", 2.9] if (k2 > k) == montee else ["", 0.0]
		return ["tcd_pyl_c", 6.8]
	return ["tcd_pyl_s", 1.1]


func _a_bord_3s(delta: float, lg: LigneRemontee, s: float, z: Array, v: float, pref: String) -> void:
	_lanceur.volume_db = move_toward(_lanceur.volume_db, -60.0, delta * 60.0)
	var zone: String = "ligne"
	if pref == "tkd" or pref == "tke":
		z = ["ligne", 0.0, 0.0]
	if pref == "tph":
		_a_bord_tph(delta, lg)
		return
	if pref == "tsd":
		var zd: String = "ligne" if z[0] == "ligne" else ("gare" if z[0] == "gare_aval" else "gare_haut")
		if zd == "ligne" and lg.regime() < 0.05 and lg.etat != "marche":
			zd = "arrete"
		if _zone3s == "ligne" and zd != "ligne" and zd != "arrete":
			_coup(lg, "tsd_arrivee")
		_zone3s = zd
		_ambiance(delta, lg, "tsd_" + zd, -2.0 if zd != "arrete" else 0.0)
		_pylones_reels(lg, s, v, pref, zd == "ligne")
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
	var cible: float = -4.0
	if _coup3s.playing or _coup3s_b.playing:
		cible = -18.0
	# la cabine vibre de plus en plus à l'approche d'un pylône (retour d'utilisateur,
	# 25/10/2026) : l'ambiance monte de 5 dB dans les 2 s qui précèdent
	cible += 5.0 * _approche
	if lg.regime() < 0.02 and zone == "ligne":
		cible = -24.0                         # arrêté en ligne : le vent, la cabine qui grince
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
	_ligne.pitch_scale = 1.0
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
		var pr: Array = _prise_pylone(lg, k, monte, pref)
		if String(pr[0]) == "":
			continue
		var cle: String = "%s_%d" % [lg.name, int(dp)]
		if ecart / v < float(pr[1]):
			if not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0:
				_pyl3s[cle] = _t
				_coup(lg, pr[0])


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


## Boucle d'ambiance à bord, changée en fondu ; abaissée pendant les coups,
## montée à l'approche d'un pylône.
func _ambiance(delta: float, lg: LigneRemontee, son: String, base: float) -> void:
	var cible: float = base
	if _coup3s.playing or _coup3s_b.playing:
		cible = base - 14.0
	cible += 5.0 * _approche
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
	_ligne.pitch_scale = 1.0


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
		var pr: Array = _prise_pylone(lg, k, monte, pref)
		if String(pr[0]) == "":
			continue
		var cle: String = "%s_%d" % [lg.name, int(dp)]
		if ecart / v < float(pr[1]):
			if not _pyl3s.has(cle) or _t - float(_pyl3s[cle]) > 20.0:
				_pyl3s[cle] = _t
				_coup(lg, pr[0])


var _approche: float = 0.0
var _tk_prec: LigneRemontee = null
var _tsf_prec: LigneRemontee = null
var _tsd_prec: LigneRemontee = null
const T_PYL_C_TSF: float = 3.7


func _coup(_lg: LigneRemontee, nom: String) -> void:
	# deux joueurs : la prise la plus ancienne cède la place
	var p: AudioStreamPlayer = _coup3s
	if _coup3s.playing and not _coup3s_b.playing:
		p = _coup3s_b
	elif _coup3s.playing and _coup3s_b.playing:
		p = _coup3s if _coup3s.get_playback_position() > _coup3s_b.get_playback_position() else _coup3s_b
	p.stream = _sons[nom]
	p.volume_db = 0.0
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
