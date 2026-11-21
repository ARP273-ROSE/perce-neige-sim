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
## - Calage des remontées : l'hôte (premier du salon) diffuse chaque seconde, pour les lignes proches de lui,
##   l'abscisse d'un de ses véhicules en ligne ; chacun ajuste de quelques % la marche du temps de la même ligne
##   (LigneRemontee.facteur_temps) jusqu'à ce que ses véhicules soient aux mêmes places (modulo l'espacement).
## Hors réseau, ce nœud n'existe pas (créé à la première ouverture du panneau RÉSEAU).
class_name ReseauClient
extends Node

signal change(texte: String)

const PERIODE_ETAT: float = 0.1
const PERIODE_LIGNES: float = 1.0
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
var _cal_lignes: Dictionary = {}           # LigneRemontee → instant local du dernier calage
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
	_cal_lignes.clear()
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
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"arrivee":
			hote_id = int(d.get("hote", hote_id))
			_nouveau_pair(int(d["id"]), String(d.get("nom", "")), d.get("c", [0.8, 0.2, 0.2]))
			_statut("Salon %s — %d joueur(s)" % [code_lisible(code), pairs.size() + 1])
		"depart":
			hote_id = int(d.get("hote", hote_id))
			pairs.erase(int(d["id"]))
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
			if int(d.get("id", -1)) == hote_id:
				_caler(d)
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
	if hote_id == mon_id:
		_t_lignes -= delta
		if _t_lignes <= 0.0:
			_t_lignes = PERIODE_LIGNES
			var dl: Array = _lignes_a_caler()
			if not dl.is_empty():
				_ws.send_text(JSON.stringify({"t": "lignes", "tc": maintenant(), "d": dl}))


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
			e["o"] = [_borne(o.x, 11.9), _borne(o.y, 11.9), _borne(o.z, 11.9)]
	elif sk.embarque and sk.support != null:
		e["po"] = 3
	return e


static func calable(lg: LigneRemontee) -> bool:
	return lg != null and is_instance_valid(lg) and lg.pret and lg.roule and lg.jumelee == null \
		and not lg.vaetvient() and not lg._vehicules.is_empty() and lg.espacement > 1.0 and lg.longueur_boucle > 0.0


static func _reference(lg: LigneRemontee) -> int:
	for k in range(lg._vehicules.size()):
		if lg.zone_vehicule(k) == "ligne":
			return k
	return -1


func _lignes_a_caler() -> Array:
	var out: Array = []
	var sk: SkieurJoueur = main.get("skieur")
	var rd: Node = main.get("remontees")
	if sk == null or rd == null:
		return out
	var p: Vector3 = sk.global_position
	for e in rd.get("lignes"):
		var lg: LigneRemontee = e[0]
		if not calable(lg) or _re.search(String(lg.name)) == null:
			continue
		if Vector2(p.x, p.z).distance_to(Vector2((e[1] as Vector3).x, (e[1] as Vector3).z)) > PORTEE_CALAGE \
				+ lg.longueur_h() * 0.5:
			continue
		var k: int = _reference(lg)
		if k < 0:
			continue
		out.append([String(lg.name), fposmod(float(lg._vehicules[k][1]), lg.longueur_boucle),
			clampf(lg.vitesse_reelle, -19.9, 19.9), clampf(lg.regime(), 0.0, 1.5)])
		if out.size() >= 40:
			break
	return out


func _caler(d: Dictionary) -> void:
	var rd: Node = main.get("remontees") if main != null else null
	if rd == null:
		return
	var tc: float = float(d.get("tc", 0.0))
	var tl: float = temps_local()
	for e in d.get("d", []):
		var lg: LigneRemontee = rd.call("_ligne_nommee", String(e[0]))
		if not calable(lg):
			continue
		var vh: float = float(e[2])
		var v: float = lg.vitesse_reelle
		if float(e[3]) < 0.98 or lg.regime() < 0.98 or absf(vh - v) > 0.05 or absf(v) < 0.3:
			lg.facteur_temps = 1.0
			continue
		var k: int = _reference(lg)
		if k < 0:
			continue
		var sh: float = float(e[1]) + vh * (maintenant() - tc)
		var esp: float = lg.espacement
		var ecart: float = wrapf(sh - float(lg._vehicules[k][1]), -esp * 0.5, esp * 0.5)
		lg.facteur_temps = 1.0 if absf(ecart) < 0.02 else clampf(1.0 + ecart / (v * GAIN_CALAGE_S), 1.0 - FACTEUR_MAX,
			1.0 + FACTEUR_MAX)
		_cal_lignes[lg] = tl
		calages += 1
	for lg2 in _cal_lignes.keys():
		if not is_instance_valid(lg2) or tl - float(_cal_lignes[lg2]) > 3.0:
			if is_instance_valid(lg2):
				(lg2 as LigneRemontee).facteur_temps = 1.0
			_cal_lignes.erase(lg2)


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
	var lg: LigneRemontee = rd.call("_ligne_nommee", String(ref["l"]))
	if lg == null or not lg.pret or lg._vehicules.is_empty() or lg.longueur_boucle <= 0.0:
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
