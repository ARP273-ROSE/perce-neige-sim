## Traces damées des téléskis débrayables (17/11/2026, retour d'utilisateur validé : « une piste de TKD est terrassée
## et damée sous la ligne : c'est elle qui tient le câble à 4-5 m avec le nombre réel de pylônes »). Un couloir
## orienté le long de l'axe de chaque TKD, maillé sur sa seule largeur (DEMI_TRACE de part et d'autre, puis TALUS de
## raccord au relief), par tronçons le long de la polyligne : pas de grille pleine sur l'emprise d'une ligne en
## diagonale (une pièce fine rectangulaire coûtait ~84 000 sommets et 3 s de construction pour les 7 TKD).
## Niveau de la trace : le câble de référence, posé sur les SEULS pylônes réels (têtes à TETE du terrain, flèche
## d'un câble de téléski), moins SOUS ; le terrain n'est déplacé que pour la part de l'écart au-delà d'une zone morte
## (MORTE), de BORNE au plus — en remblai dans les creux, en déblai sous les bosses (17/11/2026). Le relief de base
## est percé sous le couloir par un masque en coordonnées d'axe (masque() : une bande par TKD, le long de l'axe et en
## travers, ~0,35 × 0,5 m par pixel), lu par le nuanceur du relief et de ses anneaux ; le masque s'arrête un peu
## en deçà du bord du maillage, qui le recouvre donc toujours. hauteur_sol, hauteur_ligne et les collisions du décor
## prennent la hauteur du couloir. Les gares priment : pas de couloir dans leurs pièces fines.
class_name CouloirsTkd
extends RefCounted

const TETE: float = 4.6
const SOUS: float = 4.4
## (8 m : la trace terrassée tient seule le câble entre les pylônes réels, sans pylône intercalé — retour
## d'utilisateur du 18/11/2026 : « enlève les pylônes sup bidons » ; à 3 m, il en fallait 9)
const BORNE: float = 8.0
const MORTE: float = 0.6
const DEMI_TRACE: float = 2.0
const TALUS: float = 12.0
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
	var a_c: float = H / w_l
	var g0: float = _base(a.x, a.y)
	var gL: float = _base(b.x, b.y)
	var cos_moy: float = cos(atan2(gL - g0, maxf(L, 1.0)))
	var y_moy: float = 0.5 * (g0 + gL)
	var pts: PackedVector2Array = PackedVector2Array()
	var gs: PackedFloat32Array = PackedFloat32Array()
	var tv: PackedFloat32Array = PackedFloat32Array()
	var cabs: PackedFloat32Array = PackedFloat32Array()
	var d: float = 15.0
	var k: int = 0
	while d <= L - 15.0:
		while k < appuis.size() - 2 and d > float(appuis[k + 1][0]):
			k += 1
		var x1: float = appuis[k][0]
		var x2: float = appuis[k + 1][0]
		var u: float = clampf((d - x1) / maxf(x2 - x1, 0.01), 0.0, 1.0)
		# (même chaînette que la ligne, paramètre corrigé de l'altitude de la portée comme LigneRemontee._a_portee : la
		# tension baisse vers le bas de la ligne, le câble s'y creuse davantage — avec une flèche constante, la trace
		# laissait le câble à 2,8 m de la neige au bas du 3000, 18/11/2026)
		var y1: float = float(appuis[k][1])
		var y2: float = float(appuis[k + 1][1])
		var cos_p: float = cos(atan2(y2 - y1, maxf(x2 - x1, 0.1)))
		var a_p: float = maxf((a_c / cos_moy + 0.5 * (y1 + y2) - y_moy) * cos_p, 0.3 * a_c)
		var cab: float = LigneRemontee.chainette(clampf(d, x1, x2), x1, y1, x2, y2, a_p) if u > 0.0 and u < 1.0 else lerpf(y1, y2, u)
		var q: Vector2 = pt.call(d)
		var g: float = _base(q.x, q.y)
		pts.append(q)
		gs.append(g)
		var off: float = cab - SOUS - g
		# (au pied des pylônes réels, le terrain reste le leur : leur tête est posée à TETE au-dessus, comme le câble
		# de référence ; la trace ne se déforme qu'entre eux)
		var pres_pyl: float = 1.0
		for ap in appuis:
			pres_pyl = minf(pres_pyl, smoothstep(4.0, 12.0, absf(d - float(ap[0]))))
		cabs.append(cab)
		tv.append(g + clampf(signf(off) * maxf(absf(off) - MORTE, 0.0), -BORNE, BORNE) * pres_pyl)
		d += PAS
	# lissé sur ±15 m, toujours dans ±BORNE du terrain
	var t: PackedFloat32Array = PackedFloat32Array()
	t.resize(tv.size())
	for i in range(tv.size()):
		var sm: float = 0.0
		var nm: int = 0
		for j in range(maxi(i - 3, 0), mini(i + 4, tv.size())):
			sm += tv[j]
			nm += 1
		# (le lissage ne doit pas ramener la trace dans la zone morte sous le câble : une bosse rabotée entre deux
		# remblais remontait, et le câble passait à 2,8 m de la neige au Signal 1, 17/11/2026)
		var haut: float = maxf(gs[i] - BORNE, cabs[i] - SOUS + MORTE)
		var bas: float = minf(gs[i] + BORNE, cabs[i] - SOUS - MORTE)
		t[i] = clampf(clampf(sm / nm, bas, haut), gs[i] - BORNE, gs[i] + BORNE)
		# (le lissage ne doit pas ramener de déplacement au pied des pylônes)
		var dd: float = 15.0 + PAS * i
		for ap2 in appuis:
			if absf(dd - float(ap2[0])) < 4.0:
				t[i] = gs[i]
	# rien là où le relèvement est négligeable, ni dans une pièce de gare (la gare prime)
	var rel: float = 0.0
	var l_rel: float = 0.0
	for i2 in range(t.size()):
		var dans_gare: bool = false
		for r in interdits:
			if (r as Rect2).grow(DEMI_TRACE + TALUS).has_point(pts[i2]):
				dans_gare = true
				break
		if dans_gare or absf(t[i2] - gs[i2]) < 0.15:
			t[i2] = NAN
		else:
			rel = maxf(rel, absf(t[i2] - gs[i2]))
			l_rel += PAS
	var bb: Rect2 = Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		bb = bb.expand(v)
	var ic: int = couloirs.size()
	couloirs.append({"cle": cle, "pts": pts, "t": t, "rect": bb.grow(DEMI_TRACE + TALUS + 1.0), "a": a, "dir": dirh,
		"L": L, "coude": coude, "troncons": []})
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
	var best_lat: float = INF
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
		var h: float = lerpf(base, niv, w)
		# (le segment le plus proche : le bout du segment voisin, pris pour un talus, imposait son niveau à 5 m de
		# là — dents de scie de 2 à 3 m le long de la trace)
		if lat < best_lat - 1e-4:
			best_lat = lat
			best = h
	return best


## Hauteurs d'une grille (collisions du décor) prises au couloir là où il passe.
func relever_grille(rp: Rect2, pas: float, nx: int, nz: int, hc: PackedFloat32Array) -> void:
	if not _rect_touche(rp):
		return
	for jj in range(nz + 1):
		for ii in range(nx + 1):
			var x: float = rp.position.x + ii * pas
			var z: float = rp.position.y + jj * pas
			var k: int = jj * (nx + 1) + ii
			var h: float = hauteur(x, z, hc[k])
			if not is_nan(h):
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
			(c["troncons"] as Array).append([i0, i1])
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
			verts.append(Vector3(q.x, h + (-0.02 if bord else LEVE), q.y))
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


## Masque du relief de base sous les couloirs, en coordonnées d'axe : une bande par TKD dans une texture commune
## (L8, LONG_MASQUE colonnes le long de l'axe, LARG_MASQUE rangées en travers sur ±DEMI_MASQUE). Blanc là où le
## couloir est maillé, à MARGE_MASQUE en deçà de son bord (latéral et bouts des tronçons). Rend [Image, axes
## (origine x, z, direction x, z), dimensions (longueur, demi-largeur, v0, v1)].
const LONG_MASQUE: int = 4096
const LARG_MASQUE: int = 96
const DEMI_MASQUE: float = 24.0
const MARGE_MASQUE: float = 0.5
const MAX_TKD: int = 8


func masque() -> Array:
	var nb: int = mini(couloirs.size(), MAX_TKD)
	if nb == 0:
		return []
	var img: Image = Image.create(LONG_MASQUE, LARG_MASQUE * nb, false, Image.FORMAT_L8)
	var axes: Array = []
	var dims: Array = []
	var px_t: float = 2.0 * DEMI_MASQUE / LARG_MASQUE
	for ic in range(nb):
		var c: Dictionary = couloirs[ic]
		var a: Vector2 = c["a"]
		var dirh: Vector2 = c["dir"]
		var L: float = c["L"]
		var lat_m: Vector2 = Vector2(-dirh.y, dirh.x)
		var pts: PackedVector2Array = c["pts"]
		var px_s: float = L / LONG_MASQUE
		var y0: int = ic * LARG_MASQUE
		axes.append(Vector4(a.x, a.y, dirh.x, dirh.y))
		dims.append(Vector4(L, DEMI_MASQUE, float(y0) / float(LARG_MASQUE * nb), float(y0 + LARG_MASQUE) / float(LARG_MASQUE * nb)))
		for tr in c["troncons"]:
			# axe du couloir en coordonnées d'axe : (s, décalage en travers) aux points de la polyligne
			var i0: int = tr[0]
			var i1: int = tr[1]
			var s0: float = (pts[i0] - a).dot(dirh) + PAS * 0.5 + MARGE_MASQUE
			var s1: float = (pts[i1] - a).dot(dirh) - PAS * 0.5 - MARGE_MASQUE
			var j0: int = clampi(int(ceil(s0 / px_s)), 0, LONG_MASQUE - 1)
			var j1: int = clampi(int(floor(s1 / px_s)), 0, LONG_MASQUE - 1)
			var k: int = i0
			for j in range(j0, j1 + 1):
				var sj: float = (float(j) + 0.5) * px_s
				while k < i1 - 1 and (pts[k + 1] - a).dot(dirh) < sj:
					k += 1
				var sa: float = (pts[k] - a).dot(dirh)
				var sb: float = (pts[k + 1] - a).dot(dirh)
				var u: float = clampf((sj - sa) / maxf(sb - sa, 0.01), 0.0, 1.0)
				var xc: float = lerpf((pts[k] - a).dot(lat_m), (pts[k + 1] - a).dot(lat_m), u)
				var demi: float = DEMI_TRACE + TALUS - MARGE_MASQUE
				var r0: int = clampi(int(ceil((xc - demi + DEMI_MASQUE) / px_t)), 0, LARG_MASQUE - 1)
				var r1: int = clampi(int(floor((xc + demi + DEMI_MASQUE) / px_t)), 0, LARG_MASQUE - 1)
				if r1 >= r0:
					img.fill_rect(Rect2i(j, y0 + r0, 1, r1 - r0 + 1), Color.WHITE)
	return [img, axes, dims]
