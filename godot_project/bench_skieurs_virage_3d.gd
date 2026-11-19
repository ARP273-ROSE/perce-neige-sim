## Banc des skieurs des pistes (SkieursPistes) : dans les virages, ils penchent VERS L'INTÉRIEUR (retour d'essai du
## 19/11/2026 : « tes skieurs automatiques ne s'inclinent pas du bon côté dans les virages »). Pendant 20 s, pour
## chaque skieur suivi d'une image à l'autre : accélération horizontale (p₂ − 2p₁ + p₀) et axe vertical du corps
## (colonne Y de sa transformée) ; dans un virage net, l'axe doit pencher du côté de l'accélération (le centre du
## virage). Optionnel : CAPT=fichier.png, une capture au milieu.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _t0: int = 0
var _att: int = 0
var _prec: Array = []          # [positions image n-2, n-1]
var _bons: int = 0
var _mauvais: int = 0
var _ok: bool = true
var _capt: String = ""


func _initialize() -> void:
	OccupationRemontees.heure_forcee = 11.0
	_capt = OS.get_environment("CAPT")
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _tick() -> void:
	_f += 1
	var pm: Node = _main.get("perf_manager")
	if pm != null and not bool(pm.get("banc")):
		pm.set("banc", true)
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		if _f > 60 * 600:
			_fin(false, "relief jamais prêt")
		return
	if _t0 == 0:
		_t0 = _f
		_main.basculer_skieur()
		return
	if not _main.mode_skieur or _main.get("domaine") == null:
		return
	var dom: Node = _main.domaine
	if dom.get("skieurs") == null:
		if _f > _t0 + 60 * 300:
			_fin(false, "domaine jamais posé")
		return
	if _att == 0:
		# au pied des pistes de Val Claret (beaucoup de pistes, du monde à 11 h)
		_main.aller_a_remontee(_main.remontees.ligne_par_id("tsd6_grattalu"))
	_att += 1
	if _att < 240:
		return
	var sp: SkieursPistes = dom.skieurs
	var pos: PackedVector3Array = sp.positions
	var tp: PackedFloat32Array = sp.get("_tampons")[2]
	var cur: Array = []
	for i in range(pos.size()):
		var k: int = i * 16
		cur.append([pos[i], Vector3(tp[k + 1], tp[k + 5], tp[k + 9])])
	if _prec.size() == 2:
		for c in cur:
			var p2: Vector3 = c[0]
			var p1: Variant = _proche(_prec[1], p2, 1.0)
			if p1 == null:
				continue
			var p0: Variant = _proche(_prec[0], p1, 1.0)
			if p0 == null:
				continue
			var a: Vector3 = p2 - 2.0 * (p1 as Vector3) + (p0 as Vector3)
			a.y = 0.0
			var v: Vector3 = p2 - (p1 as Vector3)
			v.y = 0.0
			if v.length() < 0.05:
				continue
			# part de l'accélération en travers de la trace (virage), en m/s² (images de 1/60 s)
			var lat: Vector3 = a - v.normalized() * a.dot(v.normalized())
			if lat.length() * 3600.0 < 1.5:
				continue
			var haut: Vector3 = c[1]
			var haut_h: Vector3 = Vector3(haut.x, 0.0, haut.z)
			if haut_h.length() < 0.02:
				continue
			if haut_h.dot(lat) > 0.0:
				_bons += 1
			else:
				_mauvais += 1
	_prec.append(cur)
	if _prec.size() > 2:
		_prec.pop_front()
	if _capt != "" and _att == 240 + 600:
		RenderingServer.force_draw(false)
		get_root().get_texture().get_image().save_png(_capt)
		print("SHOT ", _capt)
	if _att >= 240 + 1200:
		var n: int = _bons + _mauvais
		var part: float = float(_bons) / maxf(float(n), 1.0)
		_fin(n >= 50 and part > 0.95, "%d mesures en virage, %.1f %% penchées vers l'intérieur" % [n, part * 100.0])


func _proche(liste: Array, p: Vector3, rmax: float) -> Variant:
	var best: Variant = null
	var db: float = rmax
	for e in liste:
		var d: float = (e[0] as Vector3).distance_to(p)
		if d < db:
			db = d
			best = e[0]
	return best


func _fin(ok: bool, detail: String) -> void:
	print("%s skieurs des pistes penchés vers l'intérieur des virages — %s" % ["[OK]  " if ok else "[ECHEC]", detail])
	print("BENCH_SKIEURS_VIRAGE " + ("OK" if ok else "ECHEC"))
	FinBanc.quitter(self, _main, 0 if ok else 1)
