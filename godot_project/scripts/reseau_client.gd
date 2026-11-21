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
## Salons ouverts reçus du relais : [{code, hote, n}] (rejoindre d'un bouton, sans clavier — 21/11/2026)
signal liste_recue(salons: Array)

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
const PERIODE_LISTE: float = 3.0           # le panneau RÉSEAU ouvert redemande la liste des salons ouverts
## Commandes d'une remontée partagées avec tout le salon (retour d'utilisateur du 21/11/2026 : « mon frère a demandé un
## arrêt que je n'ai pas eu, et du coup on est désynchronisés ») : chacun les exécute chez lui, quel que soit le pilote.
const ORDRES: Array = ["demarrer", "arreter", "urgence", "rearmer", "cran"]
## Ligne arrêtée (ou tout juste construite) dont les véhicules ne sont pas à la place de ceux du pilote : décalés d'un
## coup au premier état reçu (au-delà, la marche du temps s'en charge en roulant).
const SAUT_CALAGE_M: float = 0.3
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
var _ws_liste: WebSocketPeer = null        # connexion courte : liste des salons ouverts (avant d'entrer)
var _t_liste: float = 0.0
var _liste_voulue: bool = false
var _t_reliste: float = -1.0
var salons_ouverts: Array = []
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
var _ordre_distant: bool = false           # commande d'un autre joueur en cours d'exécution : pas renvoyée
var _calees: Dictionary = {}               # LigneRemontee → n° de la construction déjà calée une fois
var _t_vu: float = 0.0
var _t_pilotes: float = 0.0
var _t_pn: float = 0.0
var _rotation: int = 0
var _reconnexions: int = 0
var _t_reconnexion: float = -1.0
var _voulu: bool = false
var _re: RegEx = null
## Piques du mode réseau (21/11/2026) : GuetReseau décide, on affiche.
var guet: GuetReseau = GuetReseau.new()
var _t_guet: float = 0.0
var _seul_s: float = 0.0
var _rtt: float = 0.0
# descente à la corde chacun son tour (21/11/2026)
var file_corde: FileCorde = FileCorde.new()     # (hôte) demandes et files
var cordes: Dictionary = {}                     # id → {"ph", "l", "s", "t" (local), "snaps", "bilan", "vu": {}}
var _ma_corde: Dictionary = {}                  # notre demande : {"l", "s", "ph", "t0", "rang", "go", "tours", "am"}
var _file_recue: Dictionary = {}                # {"d": [ids], "t": local} : la file qui nous contient
var _t_corde: float = 0.0
var _t_file: float = 0.0
var _files_publiees: bool = false
var _cordes_mi: Dictionary = {}                 # id → [brin porteur, brin libre]


func _init() -> void:
	name = "Reseau"
	_re = RegEx.new()
	_re.compile(_RE_LIGNE)
	set_process(false)


const RELAIS_PUBLIC: String = "wss://funiculaire.giff.re/reseau"


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
	# appli PC : le relais public de la PWA (retour d'utilisateur du 21/11/2026 : champ vide, le frère « a rejoint »
	# sans jamais atteindre le relais — et il ne pouvait de toute façon rien y taper)
	return RELAIS_PUBLIC


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


## Liste des salons ouverts, redemandée toutes les PERIODE_LISTE s jusqu'à arreter_liste() (panneau fermé, salon
## rejoint) : liste_recue à chaque réponse.
func lister() -> void:
	if url == "":
		_statut("Adresse du relais à régler")
		return
	_liste_voulue = true
	if _ws_liste != null:
		return
	_ws_liste = WebSocketPeer.new()
	_t_liste = 0.0
	if _ws_liste.connect_to_url(url) != OK:
		_ws_liste = null
		_t_reliste = PERIODE_LISTE
		return
	set_process(true)


func arreter_liste() -> void:
	_liste_voulue = false
	if _ws_liste != null:
		_ws_liste.close(1000, "liste")
	_ws_liste = null
	if _ws == null and not _voulu:
		set_process(false)


## Entrer dans un salon de la liste (son code vient du relais : rien à taper).
func rejoindre_salon(code_liste: String) -> void:
	arreter_liste()
	quitter()
	rejoindre(code_liste)


func _poll_liste(delta: float) -> void:
	if _ws_liste == null:
		if _liste_voulue and _t_reliste >= 0.0:
			_t_reliste -= delta
			if _t_reliste < 0.0:
				lister()
		return
	_ws_liste.poll()
	var st: int = _ws_liste.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_t_liste -= delta
		if _t_liste <= 0.0:
			_t_liste = PERIODE_LISTE
			_ws_liste.send_text(JSON.stringify({"t": "liste"}))
		# (un bouton de la liste peut fermer cette connexion pendant liste_recue : on s'arrête là)
		while _ws_liste != null and _ws_liste.get_available_packet_count() > 0:
			var d: Variant = JSON.parse_string(_ws_liste.get_packet().get_string_from_utf8())
			if d is Dictionary and String((d as Dictionary).get("t", "")) == "liste" and (d as Dictionary).get("d") is Array:
				salons_ouverts = []
				for e in (d as Dictionary)["d"]:
					if e is Dictionary and String(e.get("code", "")).length() == 8:
						salons_ouverts.append({"code": String(e["code"]), "hote": String(e.get("hote", "?")).substr(0, 16),
							"n": int(e.get("n", 1))})
				liste_recue.emit(salons_ouverts)
	elif st == WebSocketPeer.STATE_CLOSED:
		# (coupée par le relais au bout de 10 s sans demande, ou réseau perdu) : rouverte au tour suivant
		_ws_liste = null
		_t_reliste = PERIODE_LISTE


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
	set_process(_ws_liste != null)


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
	_calees.clear()
	pilotes.clear()
	_bail.clear()
	LigneRemontee.sur_geste = Callable()
	RemonteesDomaine.choix_place_perche = Callable()
	if RemonteesDomaine.corde_reseau == self:
		RemonteesDomaine.corde_reseau = null
	cordes.clear()
	file_corde = FileCorde.new()
	_file_recue = {}
	_cacher_cordes([])
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
	_poll_liste(delta)
	_guetter(delta)
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
			guet.signaler("COUPURE", temps_local())
		else:
			_voulu = false
			_statut("Déconnecté" + ((" (%s)" % raison) if raison != "" else ""))
			set_process(_ws_liste != null)


func _recevoir(txt: String) -> void:
	var m: Variant = JSON.parse_string(txt)
	if not (m is Dictionary):
		return
	var d: Dictionary = m
	match String(d.get("t", "")):
		"bienvenue":
			connecte = true
			if _reconnexions > 0:
				guet.signaler("RECONNEXION", temps_local())
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
			RemonteesDomaine.choix_place_perche = place_perche
			RemonteesDomaine.corde_reseau = self
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"arrivee":
			_changer_hote(int(d.get("hote", hote_id)))
			_nouveau_pair(int(d["id"]), String(d.get("nom", "")), d.get("c", [0.8, 0.2, 0.2]))
			guet.signaler("ARRIVEE", temps_local(), String(d.get("nom", "")))
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"depart":
			if pairs.has(int(d["id"])):
				guet.signaler("DEPART", temps_local(), String(pairs[int(d["id"])]["nom"]))
			pairs.erase(int(d["id"]))
			cordes.erase(int(d["id"]))
			file_corde.oublier(int(d["id"]))
			_changer_hote(int(d.get("hote", hote_id)))
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
			_rtt = float(_mesures[_mesures.size() - 1][0])
		"lignes":
			_caler(d, int(d.get("id", -1)))
		"cmd":
			if int(d.get("a", 0)) == 2:
				_executer_ordre(d)
			elif hote_id == mon_id:
				if int(d.get("a", 0)) == 0:
					_arbitrer(String(d.get("l", "")), int(d.get("id", -1)))
				elif pilotes.get(String(d.get("l", "")), -1) == int(d.get("id", -1)):
					pilotes.erase(String(d.get("l", "")))
					_publier_pilotes()
		"corde":
			_recevoir_corde(d)
		"file":
			var fd: Array = []
			for v in d.get("d", []):
				fd.append(int(v))
			if int(d.get("id", -1)) == hote_id and fd.has(mon_id):
				_file_recue = {"d": fd, "t": temps_local()}
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
		# (en descente à la corde, la position part à 10 Hz dans les messages « corde » : l'état seulement à 2 Hz, le
		# relais coupe au-delà de 20 messages par seconde)
		_t_etat = 0.5 if not _ma_corde.is_empty() and int(_ma_corde["ph"]) == 1 else PERIODE_ETAT
		var e: Dictionary = etat_local()
		if not e.is_empty():
			_ws.send_text(JSON.stringify(e))
	_t_vu -= delta
	if _t_vu <= 0.0:
		_t_vu = 0.1
		_gestes_locaux()
		_places_perche()
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
	_envoyer_corde(delta)
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
	var en_corde: bool = rd != null and not (rd.get("_corde") as Dictionary).is_empty()
	if en_corde:
		e["po"] = 2
	elif ab.size() >= 2 and is_instance_valid(ab[0]):
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
		if lg == null:
			continue
		# (aussi pas encore construite ici : elle naîtra dans l'état du pilote — arrêtée, au même cran)
		lg.appliquer_etat_reseau(int(e[4]), int(e[5]), float(e[6]))
		if not lg.pret:
			continue
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
		var esp: float = lg.espacement
		var sh: float = float(e[1]) + vh * age
		var ecart: float = wrapf(sh - float(lg._vehicules[k][1]), -esp * 0.5, esp * 0.5) if k >= 0 else 0.0
		if k >= 0 and absf(v) < 0.05 and absf(vh) < 0.05:
			# arrêtées toutes deux : la marche du temps n'y peut rien. Première fois depuis sa construction (on arrive
			# à une ligne arrêtée par un autre) : ses véhicules sont posés d'un coup à la place de ceux du pilote
			if int(_calees.get(lg, -1)) != lg.constructions and absf(ecart) > SAUT_CALAGE_M:
				lg.decaler_phase(ecart)
				calages += 1
			_calees[lg] = lg.constructions
		elif k >= 0 and absf(v) >= 0.3 and absf(vh - v) <= maxf(0.05, 0.08 * absf(vh)):
			# (aussi au démarrage et au freinage, pas seulement à pleine vitesse : après un arrêt les deux repartent
			# presque ensemble, l'écart est rattrapé dès qu'elles roulent)
			if int(_calees.get(lg, -1)) != lg.constructions and absf(ecart) > esp * 0.25:
				# première fois depuis sa construction, loin de la place du pilote : d'un coup plutôt qu'en 10 s (à la
				# perche prise aussitôt arrivés, l'autre aurait été dessiné sur la perche voisine)
				lg.decaler_phase(ecart)
				ecart = 0.0
			_calees[lg] = lg.constructions
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
func _geste_ligne(lg: LigneRemontee, ordre: String = "", arg: Variant = null) -> void:
	if _ordre_distant or not connecte or lg == null or not is_instance_valid(lg) or _re.search(String(lg.name)) == null:
		return
	_demander(String(lg.name))
	# la commande elle-même part à tout le salon : chacun l'exécute, pilote ou pas (l'arrêt d'un joueur qui n'a pas
	# la main n'est plus défait par l'état du pilote, et une ligne pas encore construite chez l'autre naît arrêtée)
	if ordre in ORDRES and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var k: int = clampi(int(arg) if ordre == "cran" and arg != null else lg.cran, 0, 9)
		_ws.send_text(JSON.stringify({"t": "cmd", "l": String(lg.name), "a": 2, "o": ordre, "k": k, "tc": maintenant()}))


## Commande d'une remontée faite par un autre joueur : exécutée ici comme au poste (construite ou pas).
func _executer_ordre(d: Dictionary) -> void:
	var o: String = String(d.get("o", ""))
	var rd: Node = main.get("remontees") if main != null else null
	if not (o in ORDRES) or rd == null:
		return
	var lg: LigneRemontee = rd.call("_ligne_nommee", String(d.get("l", "")))
	if lg == null or not is_instance_valid(lg):
		return
	_ordre_distant = true
	lg.exploitation().commande(o, int(d.get("k", lg.cran)) if o == "cran" else null)
	_ordre_distant = false


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
	# notre véhicule le plus proche de son abscisse (calées : le même endroit). Revu à chaque fois : choisi une fois
	# pour toutes, il restait faux si les véhicules n'étaient pas encore calés quand il est monté (le calage les
	# déplaçait ensuite sous lui) ; gardé tant qu'il reste assez près (pas de bascule d'un véhicule à l'autre)
	var s: float = float(ref["s"]) + lg.vitesse_reelle * clampf(t - float(ref["tc"]), 0.0, 1.0)
	var pv: Array = vehicule_proche(lg, s)
	var cur: int = int(pr.get("veh", -1)) if String(pr["choix"]) == cle else -1
	if cur >= 0 and cur < lg._vehicules.size() and absf(wrapf(float(lg._vehicules[cur][1]) - s,
			-lg.longueur_boucle * 0.5, lg.longueur_boucle * 0.5)) < lg.espacement * 0.35:
		pass
	elif int(pv[0]) < 0 or float(pv[1]) > lg.espacement:
		return Vector3.INF
	else:
		pr["choix"] = cle
		pr["veh"] = int(pv[0])
	var jv: int = int(pr["veh"])
	if not lg.vehicule_a_jour(jv):
		return Vector3.INF
	var o: Vector3 = Vector3(ref["o"][0], ref["o"][1], ref["o"][2])
	return lg.vehicule(jv).global_transform * o


## Notre véhicule le plus proche de l'abscisse `s` d'une ligne : [indice, distance] ([-1, INF] sans véhicule).
static func vehicule_proche(lg: LigneRemontee, s: float) -> Array:
	var best: int = -1
	var dmin: float = INF
	for j in range(lg._vehicules.size()):
		var dj: float = absf(wrapf(float(lg._vehicules[j][1]) - s, -lg.longueur_boucle * 0.5, lg.longueur_boucle * 0.5))
		if dj < dmin:
			dmin = dj
			best = j
	return [best, dmin]


## Pairs sur la perche `i` de la ligne `lg` (dernier état reçu, ramené à notre véhicule) : [[id, place], …], la place
## d'après son décalage en travers sur l'archet (-1 tant qu'il est encore au milieu).
func _sur_la_perche(lg: LigneRemontee, i: int) -> Array:
	var out: Array = []
	if lg == null or lg.longueur_boucle <= 0.0:
		return out
	for id in pairs:
		var sn: Array = pairs[id]["snaps"]
		if sn.is_empty():
			continue
		var der: Dictionary = sn[sn.size() - 1]
		if String(der.get("l", "")) != String(lg.name):
			continue
		var s: float = float(der["s"]) + lg.vitesse_reelle * clampf(maintenant() - float(der["tc"]), 0.0, 1.0)
		var pv: Array = vehicule_proche(lg, s)
		if int(pv[0]) != i or float(pv[1]) > lg.espacement * 0.35:
			continue
		var ox: float = float(der["o"][0])
		out.append([int(id), (1 if ox > 0.0 else 0) if absf(ox) > 0.15 else -1])
	return out


## (RemonteesDomaine.choix_place_perche) Place à prendre sur la perche `i` : l'autre, si un joueur y est déjà.
func place_perche(lg: LigneRemontee, i: int) -> int:
	for e in _sur_la_perche(lg, i):
		if int(e[1]) >= 0:
			return 1 - int(e[1])
	return 0


## Deux joueurs partis ensemble sur la même perche, à la même place : celui dont l'identifiant est le plus grand
## change de côté (chacun le sait de son côté, sans échange de plus).
func _places_perche() -> void:
	var rd: RemonteesDomaine = main.get("remontees") if main != null else null
	if rd == null or rd.a_bord.size() < 6 or String(rd.a_bord[5]) != "perche":
		return
	var lg: LigneRemontee = rd.a_bord[0]
	var k: int = rd.place_perche()
	for e in _sur_la_perche(lg, int(rd.a_bord[1])):
		if int(e[1]) == k and int(e[0]) < mon_id:
			rd.changer_place_perche(1 - k)
			return


func _dessiner() -> void:
	if main == null:
		return
	if dessin == null or not is_instance_valid(dessin):
		dessin = SkieursDistants.new()
		main.add_child(dessin)
	var t: float = maintenant() - DELAI_RENDU
	var liste: Array = []
	var carte: Array = []
	var cordes_vues: Array = []
	for id in pairs:
		var e: Dictionary = etat_pair(id, t)
		if e.is_empty():
			continue
		var cd: Dictionary = corde_pair(id, t)
		if not cd.is_empty():
			e["p"] = cd["p"]
			e["po"] = 2
			e["cap"] = float(e["cap"]) + float(cd["psi"])
			e.erase("bord")
			cordes_vues.append([id, cd["a"], cd["p"]])
		pairs[id]["rendu"] = e
		liste.append([e["p"], e["cap"], e["po"], pairs[id]["c"], pairs[id]["nom"]])
		carte.append([Vector2((e["p"] as Vector3).x, (e["p"] as Vector3).z), pairs[id]["c"], pairs[id]["nom"], e["cap"]])
	dessin.poser(liste)
	_carte_distants(carte)
	_cacher_cordes(cordes_vues)


func _carte_distants(l: Array) -> void:
	var cs: Node = main.get("commandes_skieur") if main != null else null
	if cs != null and cs.get("carte") != null:
		cs.carte.distants = l


# --- piques (21/11/2026) ------------------------------------------------------------------------------------

## Nouvel hôte annoncé par le relais : pique si ce n'est plus le même (pas au premier accueil).
func _changer_hote(h: int) -> void:
	if h != hote_id and hote_id != -1 and h != -1:
		if h == mon_id:
			guet.signaler("HOTE_MOI", temps_local())
		elif pairs.has(h):
			guet.signaler("HOTE_AUTRE", temps_local(), String(pairs[h]["nom"]))
	hote_id = h


## Deux fois par seconde : la situation pour GuetReseau, et la pique qu'il choisit, s'il en choisit une.
func _guetter(delta: float) -> void:
	_seul_s = _seul_s + delta if connecte and pairs.is_empty() else 0.0
	_t_guet -= delta
	if _t_guet > 0.0 or main == null:
		return
	_t_guet = 0.5
	var r: Array = guet.observer(temps_local(), observation(), 0.5)
	if r.is_empty():
		return
	var cs: Node = main.get("commandes_skieur")
	if cs == null or not cs.has_method("pique"):
		return
	var lang: String = "fr"
	var ch: Variant = main.get("challenge")
	if ch != null and ch.get("lang") != null:
		lang = String(ch.lang)
	var t: String = PiquesReseau.texte("RESEAU_" + String(r[0]), lang, String(r[1]), float(r[2]), float(r[3]))
	if t != "":
		cs.pique(t, 7.0)
		main.set("_pique_attente", 12.0)     # (les autres piques du skieur laissent la place)


## Situation vue par le guet des piques (bancs : appelable seule).
func observation() -> Dictionary:
	var o: Dictionary = {"connecte": connecte, "latence": _rtt, "seul_s": _seul_s, "pairs": [],
		"pilote_ici": "", "urgence_ici": "", "a_bord": false, "ma_vitesse": 0.0}
	var sk: Node3D = main.get("skieur") if main != null else null
	if sk == null or not is_instance_valid(sk):
		return o
	var moi: Vector3 = sk.global_position
	var mv: Vector3 = sk.get("velocity") if sk.get("velocity") != null else Vector3.ZERO
	o["ma_vitesse"] = mv.length()
	var rd: Node = main.get("remontees")
	var ab: Array = rd.get("a_bord") if rd != null else []
	o["a_bord"] = not ab.is_empty() or (main.has_method("_rame_du_skieur") and main.call("_rame_du_skieur") != null)
	for id in pairs:
		var e: Dictionary = pairs[id].get("rendu", {})
		if e.is_empty():
			continue
		var p: Vector3 = e["p"]
		var sn: Array = pairs[id]["snaps"]
		var v: Vector3 = Vector3.ZERO
		if not sn.is_empty():
			var der: Dictionary = sn[sn.size() - 1]
			v = Vector3(der["v"][0], der["v"][1], der["v"][2])
		o["pairs"].append({"nom": String(pairs[id]["nom"]), "dist": moi.distance_to(p), "v_rel": (v - mv).length(),
			"vitesse": v.length(), "skie": int(e.get("po", 1)) in [0, 4], "bord": bool(e.get("bord", false))})
	# la remontée où l'on est : son pilote (s'il a pris la main) et son arrêt d'urgence
	var lg: LigneRemontee = null
	if not ab.is_empty() and ab[0] is LigneRemontee:
		lg = ab[0]
	elif rd != null and rd.has_method("ligne_courante"):
		lg = rd.call("ligne_courante", moi)
	if lg != null and is_instance_valid(lg):
		var n: String = String(lg.name)
		var pil: int = int(pilotes.get(n, hote_id))
		if pilotes.has(n) and pil != mon_id and pairs.has(pil):
			o["pilote_ici"] = String(pairs[pil]["nom"])
		if lg.etat == "urgence" and pil != mon_id and pairs.has(pil):
			o["urgence_ici"] = String(pairs[pil]["nom"])
	return o


# --- descente à la corde, chacun son tour (retour d'utilisateur du 21/11/2026) -------------------------------
## Celui qui doit descendre se signale (corde, phase 0) ; l'hôte range les demandes voisines en files (FileCorde)
## et les publie ; on ne part que premier de sa file et personne de son groupe en descente. Celui qui descend
## publie son pendule à 10 Hz (ancrage, position, rotation, longueur de corde) : les autres le voient au bout de sa
## corde ; au sol, son bilan (tours, balancement) pour les comparaisons. Sans file de l'hôte après
## CORDE_ATTENTE_FILE_S, ordre par identifiant (ordre d'arrivée au salon).

const CORDE_PERIODE_ATTENTE: float = 0.5
const CORDE_PERIODE_DESCENTE: float = 0.1
const CORDE_ATTENTE_FILE_S: float = 3.0
const CORDE_SEUL_S: float = 1.0               # seul à demander : on part après ce délai (une demande voisine en vol)
const CORDE_OMEGA_AUTRE: float = 0.5          # rad/s : « il tourne »
const CORDE_ANGLE_AUTRE: float = 0.12         # rad (7°) : « il balance »
const CORDE_TRAINE_S: float = 8.0
const CORDE_BILAN_S: float = 300.0
## Celui qui descend ne sort de la file qu'au sol (phase 2) ou en quittant le salon (« depart ») ; son silence ne
## compte qu'au-delà de ce délai (une image figée de plusieurs secondes, chez lui ou chez nous, sur une machine
## chargée, laissait sinon le suivant partir pendant qu'il descendait encore — suite des bancs du 21/11/2026).
const CORDE_SILENCE_DESCENTE_S: float = 20.0


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() == 3 else Vector3.ZERO


static func _proches(l1: String, s1: float, l2: String, s2: float) -> bool:
	return l1 == l2 and absf(s1 - s2) <= FileCorde.ECART_GROUPE_M


func _envoyer_json(o: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(o))


func _nom_de(id: int) -> String:
	return String(pairs[id]["nom"]) if pairs.has(id) else ""


## Corde d'un pair en descente au temps commun t : {"a", "p", "psi"} interpolés, ou {}.
func corde_pair(id: int, t: float) -> Dictionary:
	var c: Dictionary = cordes.get(id, {})
	if c.is_empty() or int(c["ph"]) != 1 or temps_local() - float(c["t"]) > 1.5:
		return {}
	var sn: Array = c["snaps"]
	if sn.is_empty():
		return {}
	var a: Dictionary = sn[0]
	var b: Dictionary = sn[0]
	for k in range(sn.size()):
		if float(sn[k]["tc"]) <= t:
			a = sn[k]
			b = sn[mini(k + 1, sn.size() - 1)]
	var f: float = 0.0
	if float(b["tc"]) > float(a["tc"]) + 1e-4:
		f = clampf((t - float(a["tc"])) / (float(b["tc"]) - float(a["tc"])), 0.0, 1.0)
	return {"a": _v3(a["a"]).lerp(_v3(b["a"]), f), "p": _v3(a["p"]).lerp(_v3(b["p"]), f),
		"psi": lerpf(float(a["psi"]), float(b["psi"]), f)}


func _recevoir_corde(d: Dictionary) -> void:
	var id: int = int(d.get("id", -1))
	if id == mon_id or id < 0:
		return
	var ph: int = int(d["ph"])
	var l: String = String(d["l"])
	var s: float = float(d["s"])
	var c: Dictionary = cordes.get(id, {})
	var avant: int = int(c.get("ph", -1))
	if c.is_empty() or (avant == 2 and ph < 2):
		c = {"snaps": [], "vu": {}, "bilan": {}}
	c["ph"] = ph
	c["l"] = l
	c["s"] = s
	c["t"] = temps_local()
	cordes[id] = c
	if hote_id == mon_id:
		file_corde.noter(id, l, s, ph, maintenant())
	var voisin: bool = not _ma_corde.is_empty() and _proches(l, s, String(_ma_corde["l"]), float(_ma_corde["s"]))
	var nom_p: String = _nom_de(id)
	if ph == 1:
		var sn: Array = c["snaps"]
		sn.append({"tc": float(d["tc"]), "a": d["a"], "p": d["p"], "psi": float(d["psi"])})
		sn.sort_custom(func(x, y) -> bool: return float(x["tc"]) < float(y["tc"]))
		while sn.size() > 24:
			sn.pop_front()
		if avant != 1 and voisin and int(_ma_corde["ph"]) == 0:
			guet.signaler("CORDE_AUTRE_DESCEND", temps_local(), nom_p)
		# sa physique : il tourne vite, il balance fort (une fois par descente chacune)
		if voisin and sn.size() >= 2:
			var e1: Dictionary = sn[sn.size() - 2]
			var e2: Dictionary = sn[sn.size() - 1]
			var dt: float = float(e2["tc"]) - float(e1["tc"])
			var vu: Dictionary = c["vu"]
			if dt > 1e-3 and absf(float(e2["psi"]) - float(e1["psi"])) / dt > CORDE_OMEGA_AUTRE and not vu.has("tourne"):
				vu["tourne"] = true
				guet.signaler("CORDE_AUTRE_TOURNE", temps_local(), nom_p)
			var axe: Vector3 = _v3(e2["a"]) - _v3(e2["p"])
			if axe.length() > 0.5 and Vector3.UP.angle_to(axe) > CORDE_ANGLE_AUTRE and not vu.has("balance"):
				vu["balance"] = true
				guet.signaler("CORDE_AUTRE_BALANCE", temps_local(), nom_p)
	elif ph == 2:
		c["bilan"] = {"tr": float(d.get("tr", 0.0)), "am": float(d.get("am", 0.0)), "t": temps_local()}
		if avant == 1 and voisin:
			guet.signaler("CORDE_AUTRE_SOL", temps_local(), nom_p)


func _envoyer_corde(delta: float) -> void:
	var tl: float = temps_local()
	if not _ma_corde.is_empty():
		var ph: int = int(_ma_corde["ph"])
		if ph == 0 and tl - float(_ma_corde.get("t_dem", 0.0)) > 1.0:
			_ma_corde = {}            # (le jeu ne demande plus : remontée repartie, skieur descendu autrement)
		elif ph == 2 and tl - float(_ma_corde.get("fini", tl)) > CORDE_BILAN_S:
			_ma_corde = {}
	_t_corde -= delta
	if not _ma_corde.is_empty() and int(_ma_corde["ph"]) == 0 and _t_corde <= 0.0:
		_t_corde = CORDE_PERIODE_ATTENTE
		_envoyer_json({"t": "corde", "l": _ma_corde["l"], "s": clampf(float(_ma_corde["s"]), 0.0, 99999.0), "ph": 0,
			"tc": maintenant()})
		if hote_id == mon_id:
			file_corde.noter(mon_id, String(_ma_corde["l"]), float(_ma_corde["s"]), 0, maintenant())
	if hote_id == mon_id:
		_t_file -= delta
		if _t_file <= 0.0:
			_t_file = 0.5
			var fl: Array = file_corde.calculer(maintenant())
			for e in fl:
				var ids: Array = (e[1] as Array).slice(0, 8)
				_envoyer_json({"t": "file", "l": e[0], "d": ids})
				if ids.has(mon_id):
					_file_recue = {"d": ids, "t": tl}


## (RemonteesDomaine, à chaque image tant que la descente attend son tour) Notre demande pour la ligne `l`, le
## véhicule à l'abscisse `s`, `h` m au-dessus du sol → {"go": bool, "rang": int, "eta": s, "devant": nom}.
func corde_demander(l: String, s: float, h: float) -> Dictionary:
	var tl: float = temps_local()
	if _ma_corde.is_empty() or int(_ma_corde["ph"]) != 0 or String(_ma_corde["l"]) != l:
		_ma_corde = {"l": l, "s": s, "ph": 0, "t0": tl, "rang": -1, "go": false, "groupe": false, "tete": -1,
			"t_tete": tl}
		_t_corde = 0.0
		if hote_id == mon_id:
			file_corde.noter(mon_id, l, s, 0, maintenant())
	_ma_corde["s"] = s
	_ma_corde["t_dem"] = tl
	if not connecte:
		return {"go": true, "rang": 0, "eta": 0.0, "devant": ""}
	var autres: Array = []
	var descend: int = -1
	var finis: int = 0
	for id in cordes:
		var c: Dictionary = cordes[id]
		if not _proches(l, s, String(c["l"]), float(c["s"])):
			continue
		var vivant: float = CORDE_SILENCE_DESCENTE_S if int(c["ph"]) == 1 else FileCorde.OUBLI_S
		if int(c["ph"]) < 2 and tl - float(c["t"]) < vivant and pairs.has(id):
			autres.append(id)
			if int(c["ph"]) == 1:
				descend = id
		elif int(c["ph"]) == 2 and tl - float((c["bilan"] as Dictionary).get("t", -1e9)) < CORDE_BILAN_S:
			finis += 1
	var ma_file: Array = []
	if not _file_recue.is_empty() and tl - float(_file_recue["t"]) < 2.0:
		ma_file = _file_recue["d"]
	var go: bool = false
	var rang: int = -1
	if autres.is_empty():
		rang = 0
		go = tl - float(_ma_corde["t0"]) >= CORDE_SEUL_S or pairs.is_empty()
	elif descend >= 0:
		rang = maxi(1, FileCorde.rang(ma_file, mon_id))
	elif not ma_file.is_empty() and ma_file.has(mon_id):
		rang = FileCorde.rang(ma_file, mon_id)
		go = rang == 0
	elif tl - float(_ma_corde["t0"]) > CORDE_ATTENTE_FILE_S:
		rang = 0
		for id2 in autres:
			if int(id2) < mon_id:
				rang += 1
		go = rang == 0
	# piques : la file se forme, la tête traîne, c'est notre tour (ou on est le dernier)
	if not autres.is_empty() and not bool(_ma_corde["groupe"]) and rang >= 0:
		_ma_corde["groupe"] = true
		if rang == 0:
			guet.signaler("CORDE_FILE_PREMIER", tl, _nom_de(int(autres[0])))
		else:
			var tete: int = descend if descend >= 0 else (int(ma_file[0]) if not ma_file.is_empty() else int(autres[0]))
			guet.signaler("CORDE_FILE_APRES", tl, _nom_de(tete))
	if not ma_file.is_empty() and int(ma_file[0]) != mon_id:
		var tete2: int = int(ma_file[0])
		if tete2 != int(_ma_corde["tete"]):
			_ma_corde["tete"] = tete2
			_ma_corde["t_tete"] = tl
		elif descend < 0 and tl - float(_ma_corde["t_tete"]) > CORDE_TRAINE_S and not _ma_corde.has("traine"):
			_ma_corde["traine"] = true
			guet.signaler("CORDE_TRAINE", tl, _nom_de(tete2))
	if go and not bool(_ma_corde["go"]) and int(_ma_corde["rang"]) > 0:
		guet.signaler("CORDE_DERNIER" if finis > 0 and autres.is_empty() else "CORDE_MON_TOUR", tl,
			_nom_de(int(_ma_corde.get("dernier_devant", -1))))
	if descend >= 0:
		_ma_corde["dernier_devant"] = descend
	_ma_corde["go"] = go
	if rang >= 0:
		_ma_corde["rang"] = rang
	# temps d'attente estimé : la fin de la descente en cours, puis une descente entière par joueur devant
	var eta: float = 0.0
	var devant: String = ""
	var v_d: float = RemonteesDomaine.V_DESCENTE_CORDE
	if descend >= 0:
		devant = _nom_de(descend)
		var sn: Array = cordes[descend]["snaps"]
		if not sn.is_empty():
			var pd: Vector3 = _v3(sn[sn.size() - 1]["p"])
			var rel: Node = main.get("relief") if main != null else null
			var sol: float = rel.hauteur_sol(pd.x, pd.z) if rel != null else pd.y - h
			eta += maxf(pd.y - sol, 0.0) / v_d + 3.0
	elif not ma_file.is_empty() and int(ma_file[0]) != mon_id:
		devant = _nom_de(int(ma_file[0]))
	var n_devant: int = maxi(0, rang - (1 if descend >= 0 else 0))
	eta += float(n_devant) * (maxf(h, 0.0) / v_d + 6.0)
	return {"go": go, "rang": rang, "eta": eta, "devant": devant}


## (RemonteesDomaine) Notre descente : phase 1 à chaque image (publiée à 10 Hz), phase 2 une fois au sol.
## d : {"l", "s", "a": Vector3, "p": Vector3, "psi", "lc"} ; au sol {"l", "s"}.
func corde_publier(ph: int, d: Dictionary) -> void:
	if not connecte:
		return
	var tl: float = temps_local()
	var l: String = String(d.get("l", ""))
	var s: float = clampf(float(d.get("s", 0.0)), 0.0, 99999.0)
	if _re.search(l) == null:
		return
	if ph == 1:
		if _ma_corde.is_empty() or int(_ma_corde["ph"]) != 1:
			_ma_corde = {"l": l, "s": s, "ph": 1, "t0": tl, "tours": 0.0, "am": 0.0, "t_dem": tl}
			_t_corde = 0.0
		var a: Vector3 = d["a"]
		var p: Vector3 = d["p"]
		var psi: float = float(d.get("psi", 0.0))
		_ma_corde["tours"] = maxf(float(_ma_corde["tours"]), absf(psi) / TAU)
		var axe: Vector3 = a - p
		if axe.length() > 0.5:
			_ma_corde["am"] = maxf(float(_ma_corde["am"]), rad_to_deg(Vector3.UP.angle_to(axe)))
		if hote_id == mon_id:
			file_corde.noter(mon_id, l, s, 1, maintenant())
		_t_corde -= get_process_delta_time()
		if _t_corde > 0.0:
			return
		_t_corde = CORDE_PERIODE_DESCENTE
		_envoyer_json({"t": "corde", "l": l, "s": s, "ph": 1, "tc": maintenant(),
			"a": [_borne(a.x, 39999.0), clampf(a.y, -499.0, 5999.0), _borne(a.z, 39999.0)],
			"p": [_borne(p.x, 39999.0), clampf(p.y, -499.0, 5999.0), _borne(p.z, 39999.0)],
			"psi": clampf(psi, -999.0, 999.0), "lc": clampf(float(d.get("lc", 0.0)), 0.0, 399.0)})
		return
	# au sol : bilan, trois fois (un message perdu ne bloque pas la file : l'hôte oublie aussi après OUBLI_S)
	var tours: float = float(_ma_corde.get("tours", 0.0))
	var am: float = clampf(float(_ma_corde.get("am", 0.0)), 0.0, 89.0)
	var m: Dictionary = {"t": "corde", "l": l, "s": s, "ph": 2, "tc": maintenant(), "tr": clampf(tours, 0.0, 999.0),
		"am": am}
	for _k in range(3):
		_envoyer_json(m)
	if hote_id == mon_id:
		file_corde.noter(mon_id, l, s, 2, maintenant())
	_ma_corde = {"l": l, "s": s, "ph": 2, "fini": tl, "tours": tours, "am": am}
	# comparaison avec la descente d'un voisin déjà au sol
	var meilleur: int = -1
	for id in cordes:
		var c: Dictionary = cordes[id]
		var b: Dictionary = c["bilan"]
		if not b.is_empty() and tl - float(b["t"]) < CORDE_BILAN_S and _proches(l, s, String(c["l"]), float(c["s"])):
			meilleur = id
	if meilleur >= 0:
		var b2: Dictionary = cordes[meilleur]["bilan"]
		var genre: String = "CORDE_COMPARE_BALANCE"
		if absf(float(b2["tr"]) - tours) >= 0.5:
			genre = "CORDE_COMPARE_TOURS_LUI" if float(b2["tr"]) > tours else "CORDE_COMPARE_TOURS_MOI"
		guet.signaler(genre, tl, _nom_de(meilleur))


## Brins de corde des pairs en descente ([id, ancrage, position]) ; les autres cachés.
func _cacher_cordes(vues: Array) -> void:
	var gardes: Dictionary = {}
	for v in vues:
		var id: int = int(v[0])
		gardes[id] = true
		if not _cordes_mi.has(id):
			var paire: Array = []
			for _k in range(2):
				var mi: MeshInstance3D = MeshInstance3D.new()
				var cy: CylinderMesh = CylinderMesh.new()
				cy.top_radius = 0.011
				cy.bottom_radius = 0.011
				cy.height = 1.0
				cy.radial_segments = 6
				cy.rings = 1
				var m: StandardMaterial3D = StandardMaterial3D.new()
				m.albedo_color = Color(0.95, 0.35, 0.10)
				cy.material = m
				mi.mesh = cy
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if main != null:
					main.add_child(mi)
				paire.append(mi)
			_cordes_mi[id] = paire
		var a: Vector3 = v[1]
		var p: Vector3 = v[2]
		var rel: Node = main.get("relief") if main != null else null
		var sol: float = rel.hauteur_sol(p.x, p.z) if rel != null else p.y - 1.0
		RemonteesDomaine._poser_brin(_cordes_mi[id][0], a, p + Vector3(0, 0.9, 0))
		RemonteesDomaine._poser_brin(_cordes_mi[id][1], p + Vector3(0, 0.9, 0), Vector3(p.x, sol, p.z))
	for id2 in _cordes_mi.keys():
		if not gardes.has(id2):
			for mi2 in _cordes_mi[id2]:
				if is_instance_valid(mi2):
					(mi2 as Node).queue_free()
			_cordes_mi.erase(id2)
