## Skieurs sur les pistes (16/11/2026, retour d'utilisateur : « on met des gens que dans le funi Perce-Neige et
## nulle part ailleurs sur d'autres remontées ou pistes »). Des skieurs descendent les pistes balisées autour de
## la caméra : chacun suit l'axe d'une piste (PistesDonnees) vers le bas, en virages réguliers de part et d'autre
## de l'axe, à sa vitesse ; au bout, il enchaîne sur une piste qui part de là, sinon il réapparaît ailleurs.
## Nombre selon l'heure (OccupationRemontees.affluence_pistes), rien au-delà de PORTEE ; ils apparaissent entre
## APPARITION_MIN et PORTEE de la caméra (pas sous les yeux du joueur). Corps et skis : un MultiMesh par maillage,
## mis à jour à chaque image.
class_name SkieursPistes
extends Node3D

const PORTEE: float = 300.0
const APPARITION_MIN: float = 120.0
const PAS_ECH: float = 25.0                # échantillons des axes de pistes (m)
const CASE_ECH: float = 200.0

var relief: ReliefBuilder = null
var _axes: Array = []                     # PackedVector2Array par piste
var _longs: Array = []                    # PackedFloat32Array : abscisse cumulée de chaque sommet
var _ech_cases: Dictionary = {}           # Vector2i → [[piste, abscisse, point 2D], …]
var _agents: Array = []                   # Dictionary par skieur actif
var _mmi: Array = []                      # [corps casque, corps bonnet, skis]
var _rng := RandomNumberGenerator.new()
var _t_maj: float = 0.0
var n_voulu: int = 0
var _n_ids: int = 0
var positions: PackedVector3Array = PackedVector3Array()     # pieds des skieurs dessinés (bancs)
## Tampons des MultiMesh (12 flottants de transformée + 4 de couleur par place), écrits d'un coup à chaque image :
## deux set_instance_transform par skieur pesaient autant que le reste (relevé du cœur, 17/11/2026).
var _tampons: Array = []
## Nuit (0..1, posé par main : CycleJour « eclairage ») : pistes fermées, mais un ou deux skieurs nocturnes, rares,
## descendent quand même, frontale allumée (19/11/2026).
var nuit: float = 0.0
## Forcer n skieurs nocturnes (bancs, captures) ; −1 : selon l'heure.
var nocturnes_forces: int = -1
var _frontales: Array = []                # Frontale (lumière sur le plus proche seulement)


## Skieurs nocturnes voulus : un tirage par tranche de 20 min (sans hasard d'une partie à l'autre), souvent aucun,
## parfois un, rarement deux.
func n_nocturnes() -> int:
	if nocturnes_forces >= 0:
		return nocturnes_forces
	if nuit < 0.5:
		return 0
	var r: float = float(hash(int(HeureJeu.unix_utc() / 1200.0)) & 0xFFFF) / 65535.0
	return 2 if r < 0.12 else (1 if r < 0.45 else 0)


static func n_max() -> int:
	if PerfManager.allege or OS.has_feature("web"):
		return 18
	if PerfManager.cran_courant >= 5:
		return 30
	return 60


func preparer(r: ReliefBuilder) -> void:
	relief = r
	_rng.seed = 2026
	for i in range(PistesDonnees.PISTES.size()):
		var a: PackedVector2Array = PistesDonnees.axe(i)
		_axes.append(a)
		var l: PackedFloat32Array = PackedFloat32Array([0.0])
		for k in range(1, a.size()):
			l.append(l[k - 1] + a[k - 1].distance_to(a[k]))
		_longs.append(l)
		if a.size() < 2 or l[l.size() - 1] < 60.0:
			continue
		var s: float = PAS_ECH * 0.5
		while s < l[l.size() - 1] - 20.0:
			var q: Vector2 = _point(i, s)
			var c: Vector2i = Vector2i(floori(q.x / CASE_ECH), floori(q.y / CASE_ECH))
			if not _ech_cases.has(c):
				_ech_cases[c] = []
			(_ech_cases[c] as Array).append([i, s, q])
			s += PAS_ECH
	var mat: ShaderMaterial = SkieurMesh.materiau()
	var sq: Dictionary = SkieurMesh.squelette_glisse()
	var maill: Array = [SkieurMesh.passager_squelette(sq, "skis", "casque", mat),
		SkieurMesh.passager_squelette(sq, "skis", "bonnet", mat), SkieurMesh.skis_aux_pieds(mat)]
	var nm: int = n_max()
	for k in range(3):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = maill[k]
		mm.instance_count = nm
		var tp: PackedFloat32Array = PackedFloat32Array()
		tp.resize(nm * 16)
		for j in range(nm):
			var cj: Color = Color(_rng.randf(), _rng.randf(), _rng.randf(), 1.0)
			mm.set_instance_custom_data(j, cj)
			tp[j * 16] = 1.0
			tp[j * 16 + 5] = 1.0
			tp[j * 16 + 10] = 1.0
			tp[j * 16 + 12] = cj.r
			tp[j * 16 + 13] = cj.g
			tp[j * 16 + 14] = cj.b
			tp[j * 16 + 15] = cj.a
		_tampons.append(tp)
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.name = "Skieurs%d" % k
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = PORTEE
		mi.top_level = true
		add_child(mi)
		_mmi.append(mi)


func _point(i: int, s: float) -> Vector2:
	var a: PackedVector2Array = _axes[i]
	var l: PackedFloat32Array = _longs[i]
	s = clampf(s, 0.0, l[l.size() - 1])
	var k: int = l.bsearch(s, true) - 1
	k = clampi(k, 0, a.size() - 2)
	var t: float = (s - l[k]) / maxf(l[k + 1] - l[k], 1e-3)
	return a[k].lerp(a[k + 1], t)


func _hauteur(q: Vector2) -> float:
	return relief.hauteur_sol(q.x, q.y) if relief != null else 0.0


## Sens de la descente au point s de la piste i : +1 si l'abscisse croissante descend.
func _sens(i: int, s: float) -> float:
	var l: float = (_longs[i] as PackedFloat32Array)[(_longs[i] as PackedFloat32Array).size() - 1]
	var a: float = clampf(s - 15.0, 0.0, l)
	var b: float = clampf(s + 15.0, 0.0, l)
	return 1.0 if _hauteur(_point(i, b)) <= _hauteur(_point(i, a)) else -1.0


## Échantillons de piste entre r0 et r1 de c (2D).
func _echantillons(c: Vector2, r0: float, r1: float) -> Array:
	var out: Array = []
	var c0: Vector2i = Vector2i(floori((c.x - r1) / CASE_ECH), floori((c.y - r1) / CASE_ECH))
	var c1: Vector2i = Vector2i(floori((c.x + r1) / CASE_ECH), floori((c.y + r1) / CASE_ECH))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for e in _ech_cases.get(Vector2i(cx, cz), []):
				var d: float = (e[2] as Vector2).distance_to(c)
				if d >= r0 and d <= r1:
					out.append(e)
	return out


func _nouvel_agent(c: Vector2, r0: float) -> Dictionary:
	var ech: Array = _echantillons(c, r0, PORTEE)
	if ech.is_empty():
		return {}
	var e: Array = ech[_rng.randi_range(0, ech.size() - 1)]
	var i: int = e[0]
	var s: float = e[1]
	var coul: int = int(PistesDonnees.PISTES[i][1])
	# vitesse selon la piste (verte à noire) et le skieur ; virages : amplitude et période
	var v: float = _rng.randf_range(5.0, 9.0) + 1.5 * float(maxi(coul, 0))
	_n_ids += 1
	return {"id": _n_ids, "i": i, "s": s, "sens": _sens(i, s), "v": v, "amp": _rng.randf_range(3.0, PistesDonnees.LARGEUR * 0.35),
		"per": _rng.randf_range(16.0, 32.0), "ph": _rng.randf() * TAU, "dec": _rng.randf_range(-3.0, 3.0),
		"casque": _rng.randf() < 0.72}


## Au bout de sa piste : une autre piste qui part à moins de 30 m, vers le bas ; sinon rien.
func _enchainer(ag: Dictionary) -> bool:
	var q: Vector2 = _point(int(ag["i"]), float(ag["s"]))
	var best: Array = []
	for e in _echantillons(q, 0.0, 30.0):
		if int(e[0]) == int(ag["i"]):
			continue
		var sn: float = _sens(int(e[0]), float(e[1]))
		var l: PackedFloat32Array = _longs[int(e[0])]
		var reste: float = (l[l.size() - 1] - float(e[1])) if sn > 0.0 else float(e[1])
		if reste > 80.0:
			best = [e[0], e[1], sn]
			break
	if best.is_empty():
		return false
	ag["i"] = best[0]
	ag["s"] = best[1]
	ag["sens"] = best[2]
	return true


func _process(delta: float) -> void:
	if Prof.actif:
		var t0_prof: int = Time.get_ticks_usec()
		_process_corps(delta)
		Prof.ajouter("skieurs_pistes", t0_prof)
	else:
		_process_corps(delta)


func _process_corps(delta: float) -> void:
	if relief == null or _mmi.is_empty() or not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var pc: Vector3 = cam.global_position
	var c: Vector2 = Vector2(pc.x, pc.z)
	_t_maj -= delta
	if _t_maj <= 0.0:
		_t_maj = 2.0
		n_voulu = mini(int(round(float(n_max()) * OccupationRemontees.affluence_pistes())),
			(_mmi[2] as MultiMeshInstance3D).multimesh.instance_count)
		if n_voulu == 0:
			n_voulu = n_nocturnes()
	# trop loin ou en trop : retirés ; manquants : ajoutés hors de la vue proche
	for k in range(_agents.size() - 1, -1, -1):
		# (position de l'image précédente, gardée au dessin)
		var q0: Vector2 = _agents[k]["q"] if _agents[k].has("q") else _point(int(_agents[k]["i"]), float(_agents[k]["s"]))
		if q0.distance_to(c) > PORTEE + 20.0 or k >= n_voulu:
			_agents.remove_at(k)
	var essais: int = 0
	while _agents.size() < n_voulu and essais < 4:
		essais += 1
		var ag: Dictionary = _nouvel_agent(c, APPARITION_MIN if not _agents.is_empty() or n_voulu < 2 else 0.0)
		if not ag.is_empty():
			_agents.append(ag)
	# avance et dessin
	var n_c: Array = [0, 0, 0]
	positions.clear()
	var n_front: int = 0
	var d_front: float = 160.0
	var front_proche: int = -1
	for k2 in range(_agents.size() - 1, -1, -1):
		var ag2: Dictionary = _agents[k2]
		var i: int = ag2["i"]
		var l: PackedFloat32Array = _longs[i]
		var s: float = float(ag2["s"]) + float(ag2["sens"]) * float(ag2["v"]) * delta
		if s < 0.0 or s > l[l.size() - 1]:
			ag2["s"] = clampf(s, 0.0, l[l.size() - 1])
			if not _enchainer(ag2):
				_agents.remove_at(k2)
			continue
		ag2["s"] = s
		var sg: float = float(ag2["sens"])
		# point et tangente d'une seule recherche dans l'axe (2 m plus loin sur le même segment : sa direction)
		var a: PackedVector2Array = _axes[i]
		var kk: int = clampi(l.bsearch(s, true) - 1, 0, a.size() - 2)
		var q: Vector2 = a[kk].lerp(a[kk + 1], (s - l[kk]) / maxf(l[kk + 1] - l[kk], 1e-3))
		var s2: float = clampf(s + sg * 2.0, 0.0, l[l.size() - 1])
		var q2: Vector2 = q + (a[kk + 1] - a[kk]) * ((s2 - s) / maxf(l[kk + 1] - l[kk], 1e-3)) 			if s2 >= l[kk] and s2 <= l[kk + 1] else _point(i, s2)
		ag2["q"] = q
		var tg: Vector2 = (q2 - q).normalized() if q2.distance_to(q) > 1e-3 else Vector2(0, -1)
		var nrm: Vector2 = Vector2(-tg.y, tg.x)
		var w: float = TAU / float(ag2["per"])
		var arg: float = s * sg * w + float(ag2["ph"])
		var lat: float = float(ag2["dec"]) + float(ag2["amp"]) * sin(arg)
		var p2: Vector2 = q + nrm * lat
		# cap le long de la trace (axe + balancement)
		var d_lat: float = float(ag2["amp"]) * w * cos(arg)
		var dir: Vector2 = (tg + nrm * d_lat).normalized()
		var cap: float = atan2(-dir.x, -dir.y)
		# penché dans le virage : v²·courbure
		var kappa: float = -float(ag2["amp"]) * w * w * sin(arg)
		var roll: float = clampf(atan(float(ag2["v"]) * float(ag2["v"]) * kappa / 9.81), -0.6, 0.6)
		var pos: Vector3 = Vector3(p2.x, _hauteur(p2) + 0.02, p2.y)
		var b: Basis = Basis(Vector3.UP, cap) * Basis(Vector3.BACK, roll)
		var cle: int = 0 if bool(ag2["casque"]) else 1
		_ecrire(_tampons[cle], n_c[cle], b, pos)
		n_c[cle] += 1
		_ecrire(_tampons[2], n_c[2], b, pos)
		n_c[2] += 1
		positions.append(pos)
		# frontale des skieurs nocturnes (casque : à 1,72 m, un peu en avant)
		if nuit > 0.3 and n_front < 2:
			if _frontales.size() <= n_front:
				var fr := Frontale.new(true)
				fr.top_level = true
				add_child(fr)
				_frontales.append(fr)
			var f: Frontale = _frontales[n_front]
			f.global_transform = Transform3D(b, pos + b * Vector3(0.0, Frontale.HAUTEUR, -0.13))
			f.allumer(true)
			var dcam: float = pos.distance_to(pc)
			if dcam < d_front:
				d_front = dcam
				front_proche = n_front
			n_front += 1
	for j in range(_frontales.size()):
		var fj: Frontale = _frontales[j]
		if j >= n_front:
			fj.allumer(false)
		else:
			fj.eclaire = j == front_proche
			if fj.lampe != null:
				fj.lampe.visible = fj.eclaire and Frontale.lumiere_reelle()
	for k3 in range(3):
		var mm3: MultiMesh = (_mmi[k3] as MultiMeshInstance3D).multimesh
		if n_c[k3] > 0:
			mm3.buffer = _tampons[k3]
		mm3.visible_instance_count = n_c[k3]


## Transformée de la place j dans un tampon de MultiMesh (lignes de la matrice 3 × 4).
static func _ecrire(tp: PackedFloat32Array, j: int, b: Basis, o: Vector3) -> void:
	var k: int = j * 16
	tp[k] = b.x.x
	tp[k + 1] = b.y.x
	tp[k + 2] = b.z.x
	tp[k + 3] = o.x
	tp[k + 4] = b.x.y
	tp[k + 5] = b.y.y
	tp[k + 6] = b.z.y
	tp[k + 7] = o.y
	tp[k + 8] = b.x.z
	tp[k + 9] = b.y.z
	tp[k + 10] = b.z.z
	tp[k + 11] = o.z
