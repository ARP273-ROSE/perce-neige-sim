extends SceneTree
## Frappe relayée par le PC vers un champ de texte de la 3D (StateReceiver.saisir) : sous Windows la vue 3D
## embarquée n'a pas le clavier, le code du salon ne s'écrivait pas (retour d'utilisateur du 21/11/2026).
var _f: int = 0
var _sr: StateReceiver
var _le: LineEdit
var _soumis: String = ""
func _initialize() -> void:
	_sr = StateReceiver.new()
	get_root().add_child(_sr)
	var c: Control = Control.new()
	get_root().add_child(c)
	_le = LineEdit.new()
	_le.max_length = 9
	_le.text_submitted.connect(func(t: String) -> void: _soumis = t)
	c.add_child(_le)
	process_frame.connect(_tick)
func _tick() -> void:
	_f += 1
	if _f == 2:
		_le.grab_focus()
	if _f != 4:
		return
	var ok: bool = true
	_sr.saisir([{"t": "a"}, {"t": "b"}, {"t": "c"}, {"k": "BackSpace"}, {"t": "Z"}])
	ok = ok and _le.text == "abZ"
	_sr.saisir([{"k": "Home"}, {"k": "Delete"}, {"k": "End"}, {"t": "-12345678"}])
	ok = ok and _le.text.length() <= 9 and _le.text.begins_with("bZ-")
	var avant: String = _le.text
	_sr.saisir([{"k": "Enter"}])
	ok = ok and _soumis == avant
	_sr.saisir([{"k": "Escape"}])
	ok = ok and not _le.has_focus()
	_sr.saisir([{"t": "x"}])
	ok = ok and _le.text == avant
	print("SAISIE texte=", _le.text, " soumis=", _soumis)
	print("SAISIE_OK" if ok else "SAISIE_ECHEC")
	quit(0 if ok else 1)
