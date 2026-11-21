## Mode réseau (demande d'utilisateur du 21/11/2026 : « un mode réseau que je puisse skier avec mon frère,
## intercompatible PWA / PC ») : client du relais WebSocket (reseau/relais/relais.py). Tout en GDScript (la PWA
## n'a pas le module C++), WebSocketPeer marche au PC comme dans le navigateur.
##
## Salon : le créateur reçoit un code (8 caractères) que les autres tapent ; le relais ne fait que redistribuer.
## - État du skieur ~10 fois par seconde (position, cap, vitesse, posture ; à bord : ligne, véhicule, abscisse,
##   place dans le véhicule), daté en temps commun.
## - Horloge commune façon NTP : décalage local → serveur pris sur l'échange au plus court aller-retour.
## - Les autres skieurs sont dessinés DELAI_RENDU en retard, interpolés entre deux états (extrapolés au plus
##   EXTRAPOLATION_MAX) ; à bord, posés dans le véhicule de NOTRE ligne le plus proche de leur abscisse.
## - Remontées calées (« cale tout », 21/11/2026) : chaque remontée a un PILOTE, l'hôte (premier du salon) par
##   défaut. Il publie deux fois par seconde l'état de celles qui tournent chez lui : état d'exploitation (marche,
##   arrêt, urgence), cran, plafond des pannes ; pour les débrayables et pinces fixes, l'abscisse d'un véhicule en
##   ligne (les autres ajustent de quelques % la marche du temps de la ligne, LigneRemontee.facteur_temps, jusqu'à
##   avoir leurs véhicules aux mêmes places, modulo l'espacement ; tronçons jumelés ensemble) ; pour les va-et-vient
##   (téléphériques, Funival), l'état complet (position, vitesse, sens, phase, quai, portes : Telepherique.
##   appliquer_reseau) ; pour le funiculaire, la position de la rame, son sens, ses portes, l'urgence (Main.
##   pn_reseau). Chacun ne retient que l'état publié par le pilote de la remontée.
## - Pilotage : celui qui agit sur une remontée (poste, pupitre, arrêt d'urgence ; mener le funiculaire) en demande
##   la main ; l'hôte l'accorde si personne d'autre n'y a touché depuis BAIL_S et publie les pilotes. Un seul
##   pilote par remontée ; en attendant la réponse, son geste n'est pas défait par l'état de l'ancien pilote.
## Hors réseau, ce nœud n'existe pas (créé à la première ouverture du panneau RÉSEAU).
class_name ReseauClient
extends Node

signal change(texte: String)

const PERIODE_ETAT: float = 0.1
const PERIODE_LIGNES: float = 0.5
const LIGNES_PAR_MESSAGE: int = 12        # (1 Ko par message au plus, côté relais)
const MESSAGES_LIGNES: int = 2            # messages d'état des remontées par période, au plus
const BAIL_S: float = 60.0                # la main sur une remontée, sans geste, se perd après une minute
const ATTENTE_PRISE: float = 1.5          # geste local protégé le temps que l'hôte réponde
const PN: String = "perce_neige"
const DELAI_RENDU: float = 0.12
const EXTRAPOLATION_MAX: float = 0.3
const PORTEE_CALAGE: float = 900.0
const GAIN_CALAGE_S: float = 4.0          # l'écart de phase est rattrapé en ~4 s
const FACTEUR_MAX: float = 0.25           # marche du temps d'une ligne : 1 ± 25 % au plus
const RECONNEXIONS_MAX: int = 5
const _RE_LIGNE: String = "^[a-z0-9_]{1,40}$"

var main: Node = null
var url: String = ""
var nom: String = "Skieur"
var couleur: Color = Color(0.85, 0.2, 0.2)
var code: String = ""
var jeton: String = ""
var mon_id: int = -1
var hote_id: int = -1
var connecte: bool = false
var statut: String = "Hors réseau"
var pairs: Dictionary = {}                 # id → {nom, c, snaps, rendu, choix}
var dessin: SkieursDistants = null
var decalage: float = 0.0                  # temps commun − temps local (s)
var a_decalage: bool = false
var calages: int = 0                       # messages de calage appliqués (bancs)

var _ws: WebSocketPeer = null
var _entree: Dictionary = {}
var _entree_envoyee: bool = false
var _t_etat: float = 0.0
var _t_lignes: float = 0.0
var _t_horloge: float = 0.0
var _n_horloge: int = 0
var _mesures: Array = []                   # [aller-retour, décalage]
var _cal_lignes: Dictionary = {}           # LigneRemontee → instant local du dernier état reçu
var pilotes: Dictionary = {}               # remontée → identifiant de son pilote (absente : l'hôte)
var _bail: Dictionary = {}                 # (hôte) remontée → temps commun du dernier geste de son pilote
var _prise: Dictionary = {}                # remontée → instant local de notre demande de pilotage
var _t_vu: float = 0.0
var _t_pilotes: float = 0.0
var _t_pn: float = 0.0
var _rotation: int = 0
var _reconnexions: int = 0
var _t_reconnexion: float = -1.0
var _voulu: bool = false
var _re: RegEx = null


func _init() -> void:
	name = "Reseau"
	_re = RegEx.new()
	_re.compile(_RE_LIGNE)
	set_process(false)


## Adresse du relais : réglage (user://reseau.cfg, ou --reseau=URL), sinon, dans le navigateur, /reseau de
## l'origine de la page (wss:// en https).
static func url_par_defaut() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reseau="):
			return a.trim_prefix("--reseau=")
	var cfg := ConfigFile.new()
	if cfg.load("user://reseau.cfg") == OK and String(cfg.get_value("reseau", "url", "")) != "":
		return String(cfg.get_value("reseau", "url", ""))
	if OS.has_feature("web"):
		var u: Variant = JavaScriptBridge.eval(
			"(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/reseau'", true)
		if u is String:
			return u
	return ""


func charger_reglages() -> void:
	url = url_par_defaut()
	var cfg := ConfigFile.new()
	if cfg.load("user://reseau.cfg") == OK:
		nom = String(cfg.get_value("reseau", "nom", nom))
		var c: Variant = cfg.get_value("reseau", "couleur", couleur)
		if c is Color:
			couleur = c


func garder_reglages(url_saisie: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://reseau.cfg")
	cfg.set_value("reseau", "nom", nom)
	cfg.set_value("reseau", "couleur", couleur)
	if url_saisie != "":
		cfg.set_value("reseau", "url", url_saisie)
	cfg.save("user://reseau.cfg")


static func temps_local() -> float:
	return float(Time.get_ticks_usec()) / 1.0e6


## Temps commun (secondes, celui du relais), estimé.
func maintenant() -> float:
	return temps_local() + decalage


# --- salon -----------------------------------------------------------------------------------------------

func creer() -> void:
	_entree = {"t": "creer", "nom": nom, "c": [couleur.r, couleur.g, couleur.b]}
	_ouvrir()


func rejoindre(code_saisi: String) -> void:
	code = code_saisi.strip_edges().to_upper().replace("-", "").replace(" ", "")
	_entree = {"t": "rejoindre", "code": code, "nom": nom, "c": [couleur.r, couleur.g, couleur.b]}
	_ouvrir()


func quitter() -> void:
	_voulu = false
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "quitter"}))
		_ws.close(1000, "quitter")
	_ws = null
	_fin()
	code = ""
	jeton = ""
	_statut("Hors réseau")
	set_process(false)


func _ouvrir() -> void:
	if url == "":
		_statut("Adresse du relais à régler")
		return
	_voulu = true
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = 1 << 16
	_ws.inbound_buffer_size = 1 << 16
	_entree_envoyee = false
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		_statut("Relais injoignable (%d)" % err)
		_ws = null
		return
	_statut("Connexion…")
	set_process(true)


func _fin() -> void:
	connecte = false
	pairs.clear()
	for lg in _cal_lignes:
		if is_instance_valid(lg):
			(lg as LigneRemontee).facteur_temps = 1.0
			(lg as LigneRemontee).cap_reseau = -1.0
	_cal_lignes.clear()
	pilotes.clear()
	_bail.clear()
	LigneRemontee.sur_geste = Callable()
	_prise.clear()
	if main != null:
		main.set("pn_reseau", {})
	if dessin != null:
		dessin.vider()
	_carte_distants([])


func _statut(t: String) -> void:
	statut = t
	change.emit(t)


# --- boucle -----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ws == null:
		if _voulu and _t_reconnexion >= 0.0:
			_t_reconnexion -= delta
			if _t_reconnexion < 0.0:
				_ouvrir()
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _entree_envoyee:
			_ws.send_text(JSON.stringify(_entree))
			_entree_envoyee = true
		while _ws.get_available_packet_count() > 0:
			_recevoir(_ws.get_packet().get_string_from_utf8())
		if connecte:
			_envoyer(delta)
			_dessiner()
	elif st == WebSocketPeer.STATE_CLOSED:
		var raison: String = _ws.get_close_reason()
		_ws = null
		_fin()
		if _voulu and code != "" and _reconnexions < RECONNEXIONS_MAX:
			_reconnexions += 1
			_t_reconnexion = 2.0 * pow(2.0, _reconnexions - 1)
			_entree = {"t": "rejoindre", "code": code, "nom": nom, "c": [couleur.r, couleur.g, couleur.b]}
			if jeton != "":
				_entree["jeton"] = jeton
			_statut("Coupé (%s) — reconnexion…" % raison)
		else:
			_voulu = false
			_statut("Déconnecté" + ((" (%s)" % raison) if raison != "" else ""))
			set_process(false)


func _recevoir(txt: String) -> void:
	var m: Variant = JSON.parse_string(txt)
	if not (m is Dictionary):
		return
	var d: Dictionary = m
	match String(d.get("t", "")):
		"bienvenue":
			connecte = true
			_reconnexions = 0
			code = String(d.get("code", ""))
			mon_id = int(d.get("id", -1))
			hote_id = int(d.get("hote", -1))
			if String(d.get("jeton", "")) != "":
				jeton = String(d["jeton"])
			if not a_decalage:
				decalage = float(d.get("ts", 0.0)) - temps_local()
			for mb in d.get("membres", []):
				if int(mb["id"]) != mon_id:
					_nouveau_pair(int(mb["id"]), String(mb["nom"]), mb["c"])
			_n_horloge = 0
			_t_horloge = 0.0
			LigneRemontee.sur_geste = _geste_ligne
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"arrivee":
			hote_id = int(d.get("hote", hote_id))
			_nouveau_pair(int(d["id"]), String(d.get("nom", "")), d.get("c", [0.8, 0.2, 0.2]))
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"depart":
			hote_id = int(d.get("hote", hote_id))
			pairs.erase(int(d["id"]))
			if hote_id == mon_id:
				var change_p: bool = false
				for n in pilotes.keys():
					if int(pilotes[n]) == int(d["id"]):
						pilotes.erase(n)
						change_p = true
				if change_p:
					_publier_pilotes()
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"etat":
			var id: int = int(d.get("id", -1))
			if not pairs.has(id):
				_nouveau_pair(id, "?", [0.8, 0.8, 0.8])
			var sn: Array = pairs[id]["snaps"]
			sn.append(d)
			sn.sort_custom(func(a, b) -> bool: return float(a["tc"]) < float(b["tc"]))
			while sn.size() > 24:
				sn.pop_front()
		"horloge":
			var c: float = float(d["c"])
			var rtt: float = temps_local() - c
			_mesures.append([rtt, float(d["s"]) - (c + rtt * 0.5)])
			if _mesures.size() > 12:
				_mesures.pop_front()
			var best: Array = _mesures[0]
			for me in _mesures:
				if float(me[0]) < float(best[0]):
					best = me
			decalage = float(best[1])
			a_decalage = true
		"lignes":
			_caler(d, int(d.get("id", -1)))
		"cmd":
			if hote_id == mon_id:
				if int(d.get("a", 0)) == 0:
					_arbitrer(String(d.get("l", "")), int(d.get("id", -1)))
				elif pilotes.get(String(d.get("l", "")), -1) == int(d.get("id", -1)):
					pilotes.erase(String(d.get("l", "")))
					_publier_pilotes()
		"pilotes":
			if int(d.get("id", -1)) == hote_id:
				_recevoir_pilotes(d.get("d", []))
		"erreur":
			_voulu = false
			_statut("Refusé : " + String(d.get("raison", "")))


func _nouveau_pair(id: int, n: String, c: Variant) -> void:
	var col: Color = Color(0.8, 0.2, 0.2)
	if c is Array and (c as Array).size() == 3:
		col = Color(float(c[0]), float(c[1]), float(c[2]))
	pairs[id] = {"nom": n, "c": col, "snaps": [], "rendu": {}, "choix": ""}


static func code_lisible(c: String) -> String:
	return c.substr(0, 4) + "-" + c.substr(4) if c.length() == 8 else c


# --- envoi ------------------------------------------------------------------------------------------------

func _envoyer(delta: float) -> void:
	_t_horloge -= delta
	if _t_horloge <= 0.0:
		_t_horloge = 0.25 if _n_horloge < 8 else 5.0
		_n_horloge += 1
		_ws.send_text(JSON.stringify({"t": "horloge", "c": temps_local()}))
	_t_etat -= delta
	if _t_etat <= 0.0:
		_t_etat = PERIODE_ETAT
		var e: Dictionary = etat_local()
		if not e.is_empty():
			_ws.send_text(JSON.stringify(e))
	_t_vu -= delta
	if _t_vu <= 0.0:
		_t_vu = 0.1
		_gestes_locaux()
	_t_lignes -= delta
	if _t_lignes <= 0.0:
		_t_lignes = PERIODE_LIGNES
		var dl: Array = _lignes_a_publier()
		if not dl.is_empty():
			var n_msg: int = mini(MESSAGES_LIGNES, int(ceil(float(dl.size()) / LIGNES_PAR_MESSAGE)))
			var debut: int = (_rotation * LIGNES_PAR_MESSAGE) % dl.size()
			for m in range(n_msg):
				var morceau: Array = []
				for k in range(LIGNES_PAR_MESSAGE):
					if m * LIGNES_PAR_MESSAGE + k >= dl.size():
						break
					morceau.append(dl[(debut + m * LIGNES_PAR_MESSAGE + k) % dl.size()])
				_ws.send_text(JSON.stringify({"t": "lignes", "tc": maintenant(), "d": morceau}))
			_rotation += n_msg
	if hote_id == mon_id:
		_t_pilotes -= delta
		if _t_pilotes <= 0.0:
			_t_pilotes = 5.0
			_expirer_bails()


static func _borne(x: float, b: float) -> float:
	return clampf(x, -b, b) if is_finite(x) else 0.0


## État du skieur local, au format du relais (bornes du schéma respectées), ou {} s'il n'y a pas de skieur.
func etat_local() -> Dictionary:
	var sk: SkieurJoueur = main.get("skieur") if main != null else null
	if sk == null or not sk.actif:
		return {}
	var p: Vector3 = sk.global_position
	var cap: float = wrapf(sk._visuel.global_rotation.y if sk._visuel != null else 0.0, -PI, PI)
	var v: Vector3 = sk.velocity
	var po: int = 0 if sk.chausse else 1
	var e: Dictionary = {"t": "etat", "p": [_borne(p.x, 39999.0), clampf(p.y, -499.0, 5999.0), _borne(p.z, 39999.0)],
		"cap": cap, "v": [_borne(v.x, 79.0), _borne(v.y, 79.0), _borne(v.z, 79.0)], "po": po, "tc": maintenant()}
	var rd: Node = main.get("remontees")
	var ab: Array = rd.get("a_bord") if rd != null else []
	if ab.size() >= 2 and is_instance_valid(ab[0]):
		var lg: LigneRemontee = ab[0]
		var i: int = int(ab[1])
		if ab.size() <= 5:
			e["po"] = 2 if sk.assis else 3
		if _re.search(String(lg.name)) != null and i >= 0 and i < lg._vehicules.size():
			var veh: Node3D = lg.vehicule(i)
			var o: Vector3 = veh.global_transform.affine_inverse() * p
			e["l"] = String(lg.name)
			e["i"] = i
			e["s"] = fposmod(float(lg._vehicules[i][1]), maxf(lg.longueur_boucle, 1.0))
			e["o"] = [_borne(o.x, 39.9), _borne(o.y, 39.9), _borne(o.z, 39.9)]
	elif sk.embarque and sk.support != null:
		e["po"] = 3
		# dans une rame du funiculaire : sa place dans la rame (même rame chez les autres, calée)
		var rame: Node3D = main.call("_rame_du_skieur") if main.has_method("_rame_du_skieur") else null
		if rame != null and main.get("physics") != null:
			var o2: Vector3 = rame.global_transform.affine_inverse() * p
			e["l"] = PN
			e["i"] = 0 if rame == main.get("cabin") else 1
			e["s"] = clampf(float(main.physics.s), 0.0, 99999.0)
			e["o"] = [_borne(o2.x, 39.9), _borne(o2.y, 39.9), _borne(o2.z, 39.9)]
	return e


## Ligne à véhicules en boucle calable par la marche du temps (débrayables, pinces fixes, téléskis ; tronçons
## jumelés compris : le tronçon bas mène, le haut suit au même facteur).
static func calable(lg: LigneRemontee) -> bool:
	return lg != null and is_instance_valid(lg) and lg.pret and lg.roule and not lg.vaetvient() \
		and not lg._vehicules.is_empty() and lg.espacement > 1.0 and lg.longueur_boucle > 0.0


static func _reference(lg: LigneRemontee) -> int:
	for k in range(lg._vehicules.size()):
		if lg.zone_vehicule(k) == "ligne":
			return k
	return -1


## Pilote d'une remontée : celui que l'hôte a désigné, sinon l'hôte (aussi quand le pilote est parti).
func pilote_de(n: String) -> int:
	var id: int = int(pilotes.get(n, hote_id))
	if id != mon_id and id != hote_id and not pairs.has(id):
		return hote_id
	return id


static func _active(lg: LigneRemontee) -> bool:
	return lg != null and is_instance_valid(lg) and lg.pret and lg.roule and lg.is_processing()


## État des remontées que nous pilotons et qui tournent chez nous (les autres en prennent ce qu'ils voient).
func _lignes_a_publier() -> Array:
	var out: Array = []
	var rd: Node = main.get("remontees") if main != null else null
	if rd != null:
		for e in rd.get("lignes"):
			var lg: LigneRemontee = e[0]
			var n: String = String(lg.name)
			if not _active(lg) or _re.search(n) == null or pilote_de(n) != mon_id:
				continue
			var cap: float = clampf(lg.cap_exploitation(), 0.0, 1.5)
			var base: Array = [n, 0.0, 0.0, clampf(lg.regime(), 0.0, 1.5), lg.etat_reseau_code(), clampi(lg.cran, 0, 9),
				cap, []]
			if lg.vaetvient() and lg is Telepherique:
				var x: Array = (lg as Telepherique).etat_reseau()
				base[1] = clampf(float(x[0]), -99999.0, 99999.0)
				base[2] = clampf(float(x[1]), -39.9, 39.9)
				base[7] = x
			elif calable(lg):
				var k: int = _reference(lg)
				base[1] = fposmod(float(lg._vehicules[k][1]), lg.longueur_boucle) if k >= 0 else -1.0
				base[2] = clampf(lg.vitesse_reelle, -39.9, 39.9)
			else:
				base[1] = -1.0
				base[2] = clampf(lg.vitesse_reelle, -39.9, 39.9)
			out.append(base)
	var ph: Variant = main.get("physics") if main != null else null
	if ph != null and pilote_de(PN) == mon_id:
		out.append([PN, clampf(float(ph.s), 0.0, 99999.0), clampf(float(ph.v), -39.9, 39.9), 0.0,
			3 if bool(ph.emergency) else 0, 0, 1.0, [float(ph.direction), 1.0 if bool(ph.doors_open) else 0.0]])
	return out


## État publié par un joueur : seules les remontées dont il est le pilote sont prises.
func _caler(d: Dictionary, id: int) -> void:
	var rd: Node = main.get("remontees") if main != null else null
	if rd == null or id == mon_id:
		return
	var tc: float = float(d.get("tc", 0.0))
	var tl: float = temps_local()
	var age: float = maintenant() - tc
	for e in d.get("d", []):
		var n: String = String(e[0])
		if pilote_de(n) != id or (_prise.has(n) and tl - float(_prise[n]) < ATTENTE_PRISE):
			continue
		if n == PN:
			var x0: Array = e[7]
			if x0.size() >= 2 and main != null:
				main.set("pn_reseau", {"s": float(e[1]), "v": float(e[2]), "dir": 1 if float(x0[0]) >= 0.0 else -1,
					"portes": float(x0[1]) > 0.5, "urg": int(e[4]) == 3, "tc": tc})
				calages += 1
			continue
		var lg: LigneRemontee = rd.call("_ligne_nommee", n)
		if lg == null or not lg.pret:
			continue
		lg.appliquer_etat_reseau(int(e[4]), int(e[5]), float(e[6]))
		_cal_lignes[lg] = tl
		if lg.vaetvient() and lg is Telepherique:
			(lg as Telepherique).appliquer_reseau(e[7], age)
			calages += 1
			continue
		# (tronçons jumelés : calés sur le tronçon HAUT, dont les sièges sont tous pareils ; le bas suit au même
		# facteur. Calé sur le bas, modulo son espacement, le haut pouvait rester décalé d'un siège du bas — l'autre
		# solution du jumelage — et ses sièges à mi-chemin de ceux de l'hôte)
		if not calable(lg) or float(e[1]) < 0.0 or lg.role == "bas":
			continue
		var jm: LigneRemontee = lg.jumelee if lg.jumelee != null and is_instance_valid(lg.jumelee) else null
		var vh: float = float(e[2])
		var v: float = lg.vitesse_reelle
		var f: float = 1.0
		var k: int = _reference(lg)
		if k >= 0 and float(e[3]) >= 0.98 and lg.regime() >= 0.98 and absf(vh - v) <= 0.05 and absf(v) >= 0.3:
			var sh: float = float(e[1]) + vh * age
			var esp: float = lg.espacement
			var ecart: float = wrapf(sh - float(lg._vehicules[k][1]), -esp * 0.5, esp * 0.5)
			f = 1.0 if absf(ecart) < 0.02 else clampf(1.0 + ecart / (v * GAIN_CALAGE_S), 1.0 - FACTEUR_MAX,
				1.0 + FACTEUR_MAX)
			calages += 1
		lg.facteur_temps = f
		if jm != null:
			jm.facteur_temps = f
			_cal_lignes[jm] = tl
	for lg2 in _cal_lignes.keys():
		if not is_instance_valid(lg2) or tl - float(_cal_lignes[lg2]) > 3.0:
			if is_instance_valid(lg2):
				(lg2 as LigneRemontee).facteur_temps = 1.0
				(lg2 as LigneRemontee).cap_reseau = -1.0
			_cal_lignes.erase(lg2)


# --- pilotage ---------------------------------------------------------------------------------------------

## Commande du joueur sur une ligne (ExploitationRemontee.commande : poste, pupitre) : on en demande la main.
func _geste_ligne(lg: LigneRemontee) -> void:
	if connecte and lg != null and is_instance_valid(lg) and _re.search(String(lg.name)) != null:
		_demander(String(lg.name))


## Mener le funiculaire (hors mode skieur) : on en demande la main, renouvelée toutes les 10 s.
func _gestes_locaux() -> void:
	_t_pn -= 0.1
	if main != null and main.get("physics") != null and not bool(main.get("mode_skieur")) and _t_pn <= 0.0:
		_t_pn = 10.0
		_demander(PN)


func _demander(n: String) -> void:
	if hote_id == mon_id:
		_arbitrer(n, mon_id)
		return
	if pilote_de(n) != mon_id:
		_prise[n] = temps_local()
	_ws.send_text(JSON.stringify({"t": "cmd", "l": n, "a": 0}))


## (hôte) Demande de la main sur une remontée : accordée si le demandeur l'a déjà, ou si personne n'y a touché
## depuis BAIL_S (ou que son pilote est parti). Les pilotes sont republiés dans tous les cas.
func _arbitrer(n: String, id: int) -> void:
	if _re.search(n) == null:
		return
	var t: float = maintenant()
	var cur: int = pilote_de(n)
	if cur == id or t - float(_bail.get(n, -1e9)) > BAIL_S:
		if id == hote_id:
			pilotes.erase(n)
		else:
			pilotes[n] = id
		_bail[n] = t
		_maj_pilote_local(n)
	_publier_pilotes()


func _expirer_bails() -> void:
	var t: float = maintenant()
	var change_p: bool = false
	for n in pilotes.keys():
		if t - float(_bail.get(n, -1e9)) > BAIL_S:
			pilotes.erase(n)
			change_p = true
	if change_p or not pilotes.is_empty():
		_publier_pilotes()


func _publier_pilotes() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var d: Array = []
	for n in pilotes:
		d.append([n, int(pilotes[n])])
		if d.size() >= 24:
			break
	_ws.send_text(JSON.stringify({"t": "pilotes", "d": d}))


func _recevoir_pilotes(d: Array) -> void:
	pilotes.clear()
	for e in d:
		pilotes[String(e[0])] = int(e[1])
	for n in _prise.keys():
		_maj_pilote_local(n)
	_prise.clear()
	for n2 in pilotes:
		_maj_pilote_local(n2)


## Remontée dont nous devenons le pilote : plus rien de reçu n'y est appliqué.
func _maj_pilote_local(n: String) -> void:
	if pilote_de(n) != mon_id or main == null:
		return
	if n == PN:
		main.set("pn_reseau", {})
		return
	var rd: Node = main.get("remontees")
	var lg: LigneRemontee = rd.call("_ligne_nommee", n) if rd != null else null
	if lg != null:
		lg.facteur_temps = 1.0
		lg.cap_reseau = -1.0
		_cal_lignes.erase(lg)


# --- rendu des autres -------------------------------------------------------------------------------------

## Position, cap et posture d'un pair au temps commun t (interpolés, ou extrapolés au plus EXTRAPOLATION_MAX).
func etat_pair(id: int, t: float) -> Dictionary:
	if not pairs.has(id):
		return {}
	var sn: Array = pairs[id]["snaps"]
	if sn.is_empty():
		return {}
	var a: Dictionary = sn[0]
	var b: Dictionary = sn[0]
	for k in range(sn.size()):
		if float(sn[k]["tc"]) <= t:
			a = sn[k]
			b = sn[mini(k + 1, sn.size() - 1)]
	var pa: Vector3 = Vector3(a["p"][0], a["p"][1], a["p"][2])
	var pb: Vector3 = Vector3(b["p"][0], b["p"][1], b["p"][2])
	var ta: float = float(a["tc"])
	var tb: float = float(b["tc"])
	var p: Vector3
	var cap: float
	var ref: Dictionary = a
	if tb > ta + 1e-4 and t <= tb:
		var f: float = clampf((t - ta) / (tb - ta), 0.0, 1.0)
		p = pa.lerp(pb, f)
		cap = lerp_angle(float(a["cap"]), float(b["cap"]), f)
		ref = a if f < 0.5 else b
	else:
		var der: Dictionary = sn[sn.size() - 1]
		var pd: Vector3 = Vector3(der["p"][0], der["p"][1], der["p"][2])
		var vd: Vector3 = Vector3(der["v"][0], der["v"][1], der["v"][2])
		p = pd + vd * clampf(t - float(der["tc"]), 0.0, EXTRAPOLATION_MAX)
		cap = float(der["cap"])
		ref = der
	var out: Dictionary = {"p": p, "cap": cap, "po": int(ref["po"])}
	# à bord : dans le véhicule de notre ligne qui est à sa place
	if ref.has("l"):
		var pv: Vector3 = _place_a_bord(id, ref, t)
		if pv != Vector3.INF:
			out["p"] = pv
			out["bord"] = true
	return out


func _place_a_bord(id: int, ref: Dictionary, t: float) -> Vector3:
	var rd: Node = main.get("remontees") if main != null else null
	if rd == null:
		return Vector3.INF
	var o0: Vector3 = Vector3(ref["o"][0], ref["o"][1], ref["o"][2])
	if String(ref["l"]) == PN:
		# (rames du funiculaire calées : la même rame, à la même place)
		var rame: Node3D = main.get("cabin") if int(ref["i"]) == 0 else main.get("cabin_ghost")
		return rame.global_transform * o0 if rame != null else Vector3.INF
	var lg: LigneRemontee = rd.call("_ligne_nommee", String(ref["l"]))
	if lg == null or not lg.pret or lg._vehicules.is_empty():
		return Vector3.INF
	if lg.vaetvient():
		# (va-et-vient calés d'état complet : le même véhicule, par son numéro)
		var iv: int = int(ref["i"])
		if iv < 0 or iv >= lg._vehicules.size() or not lg.vehicule_a_jour(iv):
			return Vector3.INF
		return lg.vehicule(iv).global_transform * o0
	if lg.longueur_boucle <= 0.0:
		return Vector3.INF
	var cle: String = "%s:%d" % [ref["l"], int(ref["i"])]
	var pr: Dictionary = pairs[id]
	if String(pr["choix"]) != cle or int(pr.get("veh", -1)) >= lg._vehicules.size():
		# notre véhicule le plus proche de son abscisse (calées : le même endroit)
		var s: float = float(ref["s"]) + lg.vitesse_reelle * lg.regime() * clampf(t - float(ref["tc"]), 0.0, 1.0)
		var best: int = -1
		var dmin: float = INF
		for j in range(lg._vehicules.size()):
			var dj: float = absf(wrapf(float(lg._vehicules[j][1]) - s, -lg.longueur_boucle * 0.5,
				lg.longueur_boucle * 0.5))
			if dj < dmin:
				dmin = dj
				best = j
		if best < 0 or dmin > lg.espacement:
			return Vector3.INF
		pr["choix"] = cle
		pr["veh"] = best
	var jv: int = int(pr["veh"])
	if not lg.vehicule_a_jour(jv):
		return Vector3.INF
	var o: Vector3 = Vector3(ref["o"][0], ref["o"][1], ref["o"][2])
	return lg.vehicule(jv).global_transform * o


func _dessiner() -> void:
	if main == null:
		return
	if dessin == null or not is_instance_valid(dessin):
		dessin = SkieursDistants.new()
		main.add_child(dessin)
	var t: float = maintenant() - DELAI_RENDU
	var liste: Array = []
	var carte: Array = []
	for id in pairs:
		var e: Dictionary = etat_pair(id, t)
		if e.is_empty():
			continue
		pairs[id]["rendu"] = e
		liste.append([e["p"], e["cap"], e["po"], pairs[id]["c"], pairs[id]["nom"]])
		carte.append([Vector2((e["p"] as Vector3).x, (e["p"] as Vector3).z), pairs[id]["c"], pairs[id]["nom"]])
	dessin.poser(liste)
	_carte_distants(carte)


func _carte_distants(l: Array) -> void:
	var cs: Node = main.get("commandes_skieur") if main != null else null
	if cs != null and cs.get("carte") != null:
		cs.carte.distants = l
