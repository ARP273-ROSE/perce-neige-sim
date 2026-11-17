## Traces damées des téléskis débrayables (17/11/2026, retour d'utilisateur validé : « une piste de TKD est terrassée
## et damée sous la ligne : c'est elle qui tient le câble à 4-5 m avec le nombre réel de pylônes »). Un couloir
## orienté le long de l'axe de chaque TKD, maillé sur sa seule largeur (DEMI_TRACE de part et d'autre, puis TALUS de
## raccord au relief), par tronçons le long de la polyligne : pas de grille pleine sur l'emprise d'une ligne en
## diagonale (une pièce fine rectangulaire coûtait ~84 000 sommets et 3 s de construction pour les 7 TKD).
## Niveau de la trace : le câble de référence, posé sur les SEULS pylônes réels (têtes à TETE du terrain, flèche
## d'un câble de téléski), moins SOUS ; le terrain n'est relevé que pour la part au-delà d'une zone morte (MORTE) et
## de BORNE au plus — un remblai : les creux sont comblés, les bosses restent (un pylône intercalé y garde le
## câble à hauteur, LigneRemontee._tetes_teleski). Sans déblai, le relief de base n'a pas à être percé (son masque
## à ~10 m par pixel ne suit pas une trace de 4 m en biais) : le couloir passe juste au-dessus de lui.
## hauteur_sol, hauteur_ligne et les collisions du décor prennent le plus haut du relief et du couloir. Les gares
## priment : pas de couloir dans leurs pièces fines.
class_name CouloirsTkd
extends RefCounted

const TETE: float = 4.6
const SOUS: float = 4.4
const BORNE: float = 3.0
const MORTE: float = 1.2
const DEMI_TRACE: float = 2.0
const TALUS: float = 8.0
const PAS: float = 5.0
const CASE: float = 50.0
const LEVE: float = 0.04                    # le dessus du couloir, juste au-dessus du relief (pas de scintillement)

var relief: Node = null
## Par couloir : {"cle", "pts": PackedVector2Array (axe), "t": PackedFloat32Array (niveau de la trace, ou NAN : rien),
## "rect": Rect2}
var couloirs: Array = []
var _cases: Dictionary = {}                 # Vector2i → [[couloir, segment], …]
var n_sommets: int = 0
var n_pieces: int = 0                       # maillages (un par TKD relevé)
var n_troncons: int = 0
var duree_ms: float = 0.0
var resume: Array = []                      # [clé, longueur relevée (m), relèvement maxi (m)]


func preparer(r: Node, interdits: Array) -> void:
	relief = r
	var t0: int = Time.get_ticks_usec()
	for D in RemonteesDonnees.LIGNES:
		if String(D["famille"]) != "perche_debrayable":
			continue
		_preparer_ligne(D, interdits)
	duree_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _base(x: float, z: float) -> float:
	return relief._hauteur_tri(x, z)


func _preparer_ligne(D: Dictionary, interdits: Array) -> void:
	var cle: String = String(D["cle"])
	var a: Vector2 = RemonteesDomaine.monde(float(D["aval"][0]), float(D["aval"][1]))
	var b: Vector2 = RemonteesDomaine.monde(float(D["amont"][0]), float(D["amont"][1]))
	var a0: Vector2 = a
	var L: float = (b - a).length()
	if L < 60.0:
		return
	var dirh: Vector2 = (b - a) / L
	var lat_m: Vector2 = Vector2(-dirh.y, dirh.x)
	var coude: Array = []
	if bool(D.get("axe_coude", false)):
		coude.append(Vector2(0.0, 0.0))
		for pc in D["pylones"]:
			coude.append(Vector2(float(pc["d"]), float((pc as Dictionary).get("x", 0.0))))
		coude.append(Vector2(L, 0.0))
	var pt := func(d: float) -> Vector2:
		return a + dirh * d + lat_m * RemonteesDomaine._x_coude(coude, d)
	# appuis du câble de référence : bouts de gare et pylônes RÉELS (à leur place, comme RemonteesDomaine._poser)
	var Ld: float = float(D["profil"][D["profil"].size() - 1][0])
	var appuis: Array = []
	for dd in [12.0, L - 12.0]:
		var q0: Vector2 = pt.call(dd)
		appuis.append([dd, _base(q0.x, q0.y) + TETE])
	for p in D["pylones"]:
		var w: Vector2 = a0 + dirh * (float(p["d"]) * L / maxf(Ld, 1.0))
		var dp: float = (w - a).dot(dirh)
		if dp > 15.0 and dp < L - 15.0:
			var q1: Vector2 = pt.call(dp)
			appuis.append([dp, _base(q1.x, q1.y) + TETE])
	appuis.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var e: float = maxf(float(D.get("espacement", 12.0)), 8.0)
	var w_l: float = 0.0039 * 16.0 * 16.0 * 9.81 + (25.0 + 80.0 * 0.7) * 9.81 / e
	var H: float = 30000.0
	var pts: PackedVector2Array = PackedVector2Array()
	var gs: PackedFloat32Array = PackedFloat32Array()
	var tv: PackedFloat32Array = PackedFloat32Array()
	var d: float = 15.0
	var k: int = 0
	while d <= L - 15.0:
		while k < appuis.size() - 2 and d > float(appuis[k + 1][0]):
			k += 1
		var x1: float = appuis[k][0]
		var x2: float = appuis[k + 1][0]
		var u: float = clampf((d - x1) / maxf(x2 - x1, 0.01), 0.0, 1.0)
		var cab: float = lerpf(float(appuis[k][1]), float(appuis[k + 1][1]), u) - w_l * (d - x1) * (x2 - d) / (2.0 * H)
		var q: Vector2 = pt.call(d)
		var g: float = _base(q.x, q.y)
		pts.append(q)
		gs.append(g)
		tv.append(g + clampf(cab - SOUS - g - MORTE, 0.0, BORNE))
		d += PAS
	# lissé sur ±15 m (le dessus reste un remblai : jamais sous le terrain)
	var t: PackedFloat32Array = PackedFloat32Array()
	t.resize(tv.size())
	for i in range(tv.size()):
		var sm: float = 0.0
		var nm: int = 0
		for j in range(maxi(i - 3, 0), mini(i + 4, tv.size())):
			sm += tv[j]
			nm += 1
		t[i] = clampf(sm / nm, gs[i], gs[i] + BORNE)
	# rien là où le relèvement est négligeable, ni dans une pièce de gare (la gare prime)
	var rel: float = 0.0
	var l_rel: float = 0.0
	for i2 in range(t.size()):
		var dans_gare: bool = false
		for r in interdits:
			if (r as Rect2).grow(DEMI_TRACE + TALUS).has_point(pts[i2]):
				dans_gare = true
				break
		if dans_gare or t[i2] - gs[i2] < 0.15:
			t[i2] = NAN
		else:
			rel = maxf(rel, t[i2] - gs[i2])
			l_rel += PAS
	var bb: Rect2 = Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		bb = bb.expand(v)
	var ic: int = couloirs.size()
	couloirs.append({"cle": cle, "pts": pts, "t": t, "rect": bb.grow(DEMI_TRACE + TALUS + 1.0)})
	resume.append([cle, l_rel, rel])
	for s in range(pts.size() - 1):
		if is_nan(t[s]) and is_nan(t[s + 1]):
			continue
		var sb: Rect2 = Rect2(pts[s], Vector2.ZERO).expand(pts[s + 1]).grow(DEMI_TRACE + TALUS + 1.0)
		for cx in range(floori(sb.position.x / CASE), floori(sb.end.x / CASE) + 1):
			for cz in range(floori(sb.position.y / CASE), floori(sb.end.y / CASE) + 1):
				var c: Vector2i = Vector2i(cx, cz)
				if not _cases.has(c):
					_cases[c] = []
				(_cases[c] as Array).append([ic, s])


## Hauteur du couloir en (x, z) au-dessus du relief `base` (déjà connu), ou NAN hors des couloirs relevés.
func hauteur(x: float, z: float, base: float) -> float:
	var lst: Variant = _cases.get(Vector2i(floori(x / CASE), floori(z / CASE)))
	if lst == null:
		return NAN
	var q: Vector2 = Vector2(x, z)
	var best: float = NAN
	for e in lst:
		var c: Dictionary = couloirs[int(e[0])]
		var s: int = e[1]
		var pts: PackedVector2Array = c["pts"]
		var t: PackedFloat32Array = c["t"]
		var p0: Vector2 = pts[s]
		var p1: Vector2 = pts[s + 1]
		var ab: Vector2 = p1 - p0
		var u: float = clampf((q - p0).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var lat: float = q.distance_to(p0 + ab * u)
		if lat > DEMI_TRACE + TALUS:
			continue
		var t0: float = t[s]
		var t1: float = t[s + 1]
		var niv: float
		if is_nan(t0) and is_nan(t1):
			continue
		elif is_nan(t0):
			niv = lerpf(base, t1, u)            # (bout du tronçon relevé : raccord le long de l'axe)
		elif is_nan(t1):
			niv = lerpf(t0, base, u)
		else:
			niv = lerpf(t0, t1, u)
		var w: float = 1.0 - smoothstep(DEMI_TRACE, DEMI_TRACE + TALUS, lat)
		var h: float = lerpf(base, maxf(niv, base), w)
		if is_nan(best) or h > best:
			best = h
	return best


## Relève les hauteurs d'une grille (collisions du décor) là où passe un couloir.
func relever_grille(rp: Rect2, pas: float, nx: int, nz: int, hc: PackedFloat32Array) -> void:
	if not _rect_touche(rp):
		return
	for jj in range(nz + 1):
		for ii in range(nx + 1):
			var x: float = rp.position.x + ii * pas
			var z: float = rp.position.y + jj * pas
			var k: int = jj * (nx + 1) + ii
			var h: float = hauteur(x, z, hc[k])
			if not is_nan(h) and h > hc[k]:
				hc[k] = h


func _rect_touche(rp: Rect2) -> bool:
	for c in couloirs:
		if (c["rect"] as Rect2).intersects(rp):
			return true
	return false


## Maillages des couloirs : par tronçon relevé, une bande en travers de l'axe (talus, trace, talus), une rangée
## tous les PAS m ; le bord extérieur posé un peu sous le relief.
func maillages() -> Array:
	var out: Array = []
	var travers: Array = [-(DEMI_TRACE + TALUS), -(DEMI_TRACE + TALUS * 0.6), -(DEMI_TRACE + TALUS * 0.25), -DEMI_TRACE,
		0.0, DEMI_TRACE, DEMI_TRACE + TALUS * 0.25, DEMI_TRACE + TALUS * 0.6, DEMI_TRACE + TALUS]
	for c in couloirs:
		var pts: PackedVector2Array = c["pts"]
		var t: PackedFloat32Array = c["t"]
		var bandes: Array = []
		var i: int = 0
		while i < pts.size():
			if is_nan(t[i]):
				i += 1
				continue
			# tronçon relevé, élargi d'une rangée de chaque côté (raccord le long de l'axe), 40 rangées au plus
			var i0: int = maxi(i - 1, 0)
			var i1: int = i
			while i1 < pts.size() - 1 and not is_nan(t[i1 + 1]) and i1 - i0 < 40:
				i1 += 1
			i1 = mini(i1 + 1, pts.size() - 1)
			bandes.append(_bande(pts, i0, i1, travers))
			i = i1 + 1 if i1 > i else i + 1
		if bandes.is_empty():
			continue
		# (un seul maillage par TKD : un appel de dessin par ligne ; les emprises des tronçons restent, pour les collisions)
		var v: PackedVector3Array = PackedVector3Array()
		var uv: PackedVector2Array = PackedVector2Array()
		var ix: PackedInt32Array = PackedInt32Array()
		var bb: Rect2 = bandes[0][3]
		var rects: Array = []
		for bd in bandes:
			var o: int = v.size()
			v.append_array(bd[0])
			uv.append_array(bd[1])
			for k in (bd[2] as PackedInt32Array):
				ix.append(k + o)
			bb = bb.merge(bd[3])
			rects.append((bd[3] as Rect2).grow(DEMI_TRACE + TALUS))
		out.append([v, uv, ix, bb.grow(DEMI_TRACE + TALUS), rects])
		n_pieces += 1
	return out


func _bande(pts: PackedVector2Array, i0: int, i1: int, travers: Array) -> Array:
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var nt: int = travers.size()
	var bb: Rect2 = Rect2(pts[i0], Vector2.ZERO)
	for i in range(i0, i1 + 1):
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var tg: Vector2 = (b - a).normalized()
		var nrm: Vector2 = Vector2(-tg.y, tg.x)
		for k in range(nt):
			var q: Vector2 = pts[i] + nrm * float(travers[k])
			var base: float = _base(q.x, q.y)
			var h: float = hauteur(q.x, q.y, base)
			if is_nan(h):
				h = base
			var bord: bool = k == 0 or k == nt - 1 or i == i0 or i == i1
			verts.append(Vector3(q.x, h + (-0.05 if bord else LEVE), q.y))
			uvs.append(Vector2((q.x - ReliefDonnees.X_OUEST) / (ReliefDonnees.X_EST - ReliefDonnees.X_OUEST),
				(q.y - ReliefDonnees.Z_NORD) / (ReliefDonnees.Z_SUD - ReliefDonnees.Z_NORD)))
			bb = bb.expand(q)
	var nr: int = i1 - i0 + 1
	for r in range(nr - 1):
		for k2 in range(nt - 1):
			var p: int = r * nt + k2
			idx.append_array(PackedInt32Array([p, p + nt, p + 1, p + 1, p + nt, p + nt + 1]))
	n_sommets += verts.size()
	n_troncons += 1
	return [verts, uvs, idx, bb]
