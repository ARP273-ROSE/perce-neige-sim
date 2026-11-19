## Lumières des villages et des chalets la nuit (19/11/2026, retour d'essai : « que l'arrivée au village soit
## féerique ») : une ou plusieurs fenêtres éclairées par bâtiment d'OpenStreetMap (BatiDonnees, 2 572 bâtiments :
## Tignes le Lac, Val Claret, Le Lavachet, Les Boisses, Les Brévières, Tignes 1800, Val d'Isère, La Daille, Le Fornet,
## Le Laisinant… et les chalets isolés des hauteurs). Points lumineux de taille constante à l'écran (PointsLumineux),
## couleur chaude variée, sans hasard d'une partie à l'autre ; une partie des fenêtres s'éteint au cœur de la nuit.
## Coût : une passe de dessin, aucune vraie lumière ; construit à la première tombée de la nuit.
class_name LumieresVillages
extends Node3D

var points: PointsLumineux = null
var n_fenetres: int = 0
var _pts: PackedVector3Array = PackedVector3Array()
var _coul: PackedColorArray = PackedColorArray()
var _heure_eteinte: PackedFloat32Array = PackedFloat32Array()    # heure (0..30) où chaque fenêtre s'éteint
var _h_pose: float = -100.0


func _init() -> void:
	name = "LumieresVillages"


func construire(relief: ReliefBuilder) -> void:
	if points != null:
		return
	var t0: int = Time.get_ticks_usec()
	points = PointsLumineux.new("FenetresVillages", 3.0 if not OS.has_feature("web") else 3.5)
	add_child(points)
	var oct: PackedByteArray = Marshalls.base64_to_raw(BatiDonnees.DONNEES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1800
	var teintes: Array = [Color(1.0, 0.78, 0.45), Color(1.0, 0.70, 0.38), Color(1.0, 0.86, 0.60), Color(0.95, 0.90, 0.80)]
	for i in range(oct.size() / 6):
		var x: float = float(oct.decode_s16(i * 6))
		var z: float = float(oct.decode_s16(i * 6 + 2))
		var grand: bool = oct.decode_s16(i * 6 + 4) >= 2
		var h: float = relief.hauteur_sol(x, z) if relief != null else 0.0
		if is_inf(h) or is_nan(h):
			continue
		var n: int = rng.randi_range(3, 7) if grand else rng.randi_range(1, 2)
		for k in range(n):
			var a: float = rng.randf() * TAU
			var r: float = rng.randf_range(2.0, 7.0 if grand else 4.0)
			var etage: float = rng.randf_range(1.5, 12.0 if grand else 5.0)
			_pts.append(Vector3(x + cos(a) * r, h + etage, z + sin(a) * r))
			var c: Color = teintes[rng.randi_range(0, teintes.size() - 1)] * rng.randf_range(0.7, 1.25)
			c.a = 0.0
			_coul.append(c)
			# coucher : de 21 h à 1 h du matin (25 h), un quart des fenêtres restent allumées toute la nuit
			_heure_eteinte.append(rng.randf_range(21.0, 25.0) if rng.randf() < 0.75 else 99.0)
	n_fenetres = _pts.size()
	_poser(20.0)
	print("[Nuit] %d fenêtres éclairées (%d bâtiments), %.0f ms" % [n_fenetres, oct.size() / 6, (Time.get_ticks_usec() - t0) / 1000.0])


## Fenêtres allumées à l'heure h (Tignes) ; niveau : CycleJour « eclairage ».
func regler(niveau: float, h: float) -> void:
	if points == null:
		return
	# (heure ramenée sur la nuit : 0 h-8 h → 24-32)
	var hn: float = h + 24.0 if h < 12.0 else h
	if absf(hn - _h_pose) > 0.25:
		_poser(hn)
	points.regler_niveau(niveau)


func _poser(hn: float) -> void:
	_h_pose = hn
	var p := PackedVector3Array()
	var c := PackedColorArray()
	# au matin (après 6 h, hn ≥ 30) les lumières se rallument une à une
	var matin: bool = hn >= 30.0
	for i in range(_pts.size()):
		if hn < _heure_eteinte[i] or (matin and i % 3 != 0):
			p.append(_pts[i])
			c.append(_coul[i])
	points.poser(p, c)
