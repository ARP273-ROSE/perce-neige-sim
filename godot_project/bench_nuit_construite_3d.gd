## Banc : une remontée la nuit, une fois construite, garde ses couleurs (retour d'essai PWA du 21/11/2026 : « quand la
## remontée se construit c'est pas blafard mais ensuite c'est blafard de nuit »). Pendant la construction, la PWA
## montre la version cuite (lumière du jour cuite dans la couleur, teinte CycleJour.teinte_remontees) ; ensuite, la
## ligne construite : pièces éclairées et véhicules allégés. Deux défauts mesurés (sonde _sonde_nuit_constr.gd) :
## - métaux (pylônes galvanisés à 0,75) sans rien à refléter la nuit : au noir, ligne monochrome ;
## - sièges allégés sous la lueur chaude des cabines éclairées : beige pâle, couleurs délavées.
##   godot --headless --fixed-fps 60 --path godot_project -s bench_nuit_construite_3d.gd
## Vérifie, à 23 h, sur un télésiège construit en mode PWA (GDScript seul, véhicules allégés) :
## 1. luminance d'un pylône galvanisé éclairé par l'ambiante ≥ 80 % de celle de sa version cuite ;
## 2. saturation d'une assise bleue sur un siège allégé ≥ 60 % de celle du jour, sans lueur chaude ;
## 3. les sièges allégés de la ligne ont le matériau des véhicules ouverts, les cabines celui des fermés ;
## 4. à midi, métaux rendus (0,75) et teintes neutres.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _etape: int = 0
var _n: int = 0
var _lg: LigneRemontee = null
const CLE: String = "tsd6_bollin"


func _initialize() -> void:
	LigneRemontee.noyau_desactive = true
	LigneRemontee.lod_force = true
	HeureJeu.regler(2026, 11, 21, 23, 0, 1.0, false)
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(nom: String, c: bool, detail: String = "") -> void:
	print(("  OK  " if c else "  ÉCHEC  ") + nom + ("" if detail == "" else " — " + detail))
	_ok = _ok and c


static func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11


static func _sat(c: Color) -> float:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	var mn: float = minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


func _tick() -> void:
	_f += 1
	if _f > 60 * 600:
		print("BENCH_NUIT_CONSTRUITE ECHEC (délai)")
		quit(1)
		return
	var relief = _main.get("relief")
	if relief == null or not relief.pret or _f < 30:
		return
	if not _main.mode_skieur:
		_main.basculer_skieur()
		return
	if _main.remontees == null or not _main.remontees.pret:
		return
	if _lg == null:
		for e in _main.remontees.lignes:
			if String((e[0] as Node).name) == CLE:
				_lg = e[0]
		_main.aller_a_remontee(_lg)
		return
	if not _lg.pret:
		return
	_n += 1
	if _etape == 0 and _n == 120:
		_etape = 1
		_nuit()
		HeureJeu.regler(2026, 11, 21, 12, 0, 1.0, false)
		_n = 0
	elif _etape == 1 and _n == 300:
		_jour()
		print("BENCH_NUIT_CONSTRUITE " + ("OK" if _ok else "ECHEC"))
		quit(0 if _ok else 1)


func _nuit() -> void:
	var n: float = float(_main.etat_jour.get("nuit", 0.0))
	_verif("il fait nuit", n > 0.5, "nuit %.2f" % n)
	var env: Environment = _main._env
	var amb: Color = env.ambient_light_color * env.ambient_light_energy
	# 1. pylône galvanisé : diffusion = albédo × (1 − métal) × ambiante ; version cuite : albédo × teinte
	var galva: StandardMaterial3D = RemonteeKit.mat("galva_pylone")
	var a: Color = galva.albedo_color
	var lit: float = _lum(a) * (1.0 - galva.metallic) * _lum(amb)
	var teinte: Color = CycleJour.teinte_remontees(_main.etat_jour["decor"], n)
	var cuit: float = _lum(a) * _lum(teinte)
	_verif("pylône éclairé ≥ 80 % de sa version cuite", lit >= 0.8 * cuit,
		"métal %.2f, %.4f contre %.4f (%.0f %%)" % [galva.metallic, lit, cuit, 100.0 * lit / maxf(cuit, 1e-6)])
	_verif("métaux ternis la nuit", galva.metallic <= 0.75 * (1.0 - RemonteeKit.REDUCTION_METAL_NUIT * n) + 0.01,
		"%.2f" % galva.metallic)
	# 2. assise bleue sur un siège allégé (couleur cuite × teinte du matériau, en sRVB)
	var bleu: Color = RemonteeKit.COULEURS["assise_bleue"][0]
	var t_ouv: Color = VehiculesLod.materiau_ouverts().albedo_color
	var sb: Color = Color(bleu.r * t_ouv.r, bleu.g * t_ouv.g, bleu.b * t_ouv.b)
	_verif("assise bleue d'un siège allégé : saturation ≥ 60 % du jour", _sat(sb) >= 0.6 * _sat(bleu),
		"%.2f contre %.2f" % [_sat(sb), _sat(bleu)])
	_verif("siège allégé sans lueur chaude (teinte des pylônes, pas plus rouge que bleue)", t_ouv.r <= t_ouv.b + 0.01
		and t_ouv.is_equal_approx(VehiculesLod.materiau_pylones().albedo_color), str(t_ouv))
	var t_ferme: Color = VehiculesLod.materiau().albedo_color
	_verif("cabine allégée : lueur chaude gardée", t_ferme.r > t_ferme.b, str(t_ferme))
	# 3. matériaux des maillages allégés
	var v0: VehiculeRemontee = _lg._vehicules[0][0]
	var cle: String = "%s|%s|%s|%s|%s" % [v0.famille, v0.livree, v0.teinte, str(v0.pince_a108), v0.style_tph]
	var m: ArrayMesh = VehiculesLod.maillage(cle, "L1", not _lg.sens_droite)
	_verif("sièges allégés de la ligne : matériau des véhicules ouverts", m != null
		and m.surface_get_material(0) == VehiculesLod.materiau_ouverts(), cle)
	_verif("cabine : matériau des véhicules fermés", VehiculesLod.ferme("cabine_omega4|x") and not VehiculesLod.ferme(cle))


func _jour() -> void:
	var n: float = float(_main.etat_jour.get("nuit", 0.0))
	_verif("il fait jour", n < 0.01, "nuit %.2f" % n)
	var galva: StandardMaterial3D = RemonteeKit.mat("galva_pylone")
	_verif("à midi, métaux rendus", absf(galva.metallic - 0.75) < 0.011, "%.2f" % galva.metallic)
	var t_ouv: Color = VehiculesLod.materiau_ouverts().albedo_color
	_verif("à midi, sièges allégés à la teinte des pylônes", t_ouv.is_equal_approx(VehiculesLod.materiau_pylones().albedo_color),
		str(t_ouv))
