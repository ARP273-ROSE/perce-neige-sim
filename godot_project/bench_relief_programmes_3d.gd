## Banc des programmes et textures du relief (retour d'essai PWA du 21/11/2026 : contexte WebGL perdu après 22 min,
## 922 programmes ; gels de 3,9 s « après le script » à l'arrivée près d'une gare). Deux défauts :
##  - chaque pièce fine des gares recevait un Shader neuf (même code) : un programme de plus à compiler et à garder,
##    une soixantaine sur la partie ;
##  - copiée du matériau du relief (PC), une pièce gardait en vie le masque des gares de 2048² du moment, remplacé
##    à chaque pièce posée ensuite (sonde de mémoire : +4 Mo par gare visitée, sans plafond).
## Vérifie : deux pièces fabriquées par le chemin de la PWA partagent leur Shader ; aucune pièce posée ne tient de
## masque des gares ; le nombre de Shaders distincts du relief ne croît pas avec les pièces posées en cours de partie.
extends SceneTree

var _main: Node = null
var _f: int = 0
var _ok: bool = true
var _etape: int = 0
var _lignes: Array = []
var _t: int = 0
var _n_sh0: int = -1
var _visites: int = 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(_main)
	process_frame.connect(_tick)


func _verif(nom: String, cond: bool, detail: String = "") -> void:
	print("%s %s%s" % ["[OK]  " if cond else "[ECHEC]", nom, (" — " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _pieces(r: ReliefBuilder) -> Array:
	var out: Array = []
	for c in r.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("PieceGare") and (c as MeshInstance3D).mesh != null:
			var m: Material = (c as MeshInstance3D).mesh.surface_get_material(0)
			if m is ShaderMaterial:
				out.append(m)
	return out


func _shaders(r: ReliefBuilder) -> int:
	var vus: Dictionary = {}
	for m in _pieces(r):
		vus[(m as ShaderMaterial).shader] = true
	return vus.size()


func _tick() -> void:
	_f += 1
	if _f > 60 * 1200:
		_verif("fin dans les temps", false)
		_fin()
		return
	var pm: Node = _main.get("perf_manager")
	if pm != null and not bool(pm.get("banc")):
		pm.set("banc", true)
	var r: ReliefBuilder = _main.get("relief")
	if r == null or not r.pret or _f < 30:
		return
	if not _main.mode_skieur:
		_main.basculer_skieur()
		return
	if _main.remontees == null or not _main.remontees.pret:
		return
	match _etape:
		0:
			# chemin de la PWA (_detail_seul faux, pas de pack) : deux pièces, un seul Shader
			var garde: bool = r._detail_seul
			r._detail_seul = false
			var img: Image = Image.create(4, 4, false, Image.FORMAT_L8)
			var m1: ShaderMaterial = r._materiau_piece(Rect2(0, 0, 1, 1), img)
			var m2: ShaderMaterial = r._materiau_piece(Rect2(2, 2, 1, 1), img)
			r._detail_seul = garde
			_verif("pièces de la PWA : un Shader partagé", m1.shader == m2.shader)
			_verif("pièce : pas de masque des gares", m1.get_shader_parameter("masque_gares") == null)
			for e in _main.remontees.lignes:
				_lignes.append(e[0])
			_n_sh0 = _shaders(r)
			_etape = 1
			_t = _f
		1:
			# le skieur visite quelques gares : des pièces se posent en cours de partie
			if _f - _t < 240:
				return
			if _visites < 6 and _lignes.size() > 0:
				_main.aller_a_remontee(_lignes[(_visites * 11) % _lignes.size()])
				_visites += 1
				_t = _f
				return
			_etape = 2
		2:
			var ps: Array = _pieces(r)
			var avec_masque: int = 0
			for m in ps:
				if (m as ShaderMaterial).get_shader_parameter("masque_gares") != null:
					avec_masque += 1
			_verif("aucune pièce posée ne tient un masque des gares", avec_masque == 0, "%d sur %d" % [avec_masque, ps.size()])
			var n_sh: int = _shaders(r)
			_verif("Shaders distincts des pièces : pas un par pièce", n_sh <= 2,
				"%d Shaders pour %d pièces (départ %d)" % [n_sh, ps.size(), _n_sh0])
			_fin()


func _fin() -> void:
	print("BENCH_RELIEF_PROGRAMMES %s" % ("OK" if _ok else "ECHEC"))
	quit(0 if _ok else 1)
