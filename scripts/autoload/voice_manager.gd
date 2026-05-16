extends Node
# ============================================================
# VOICE MANAGER — TTS (DisplayServer) + STT (plugin Android natif requis).
# Sur PC : TTS via DisplayServer.tts_speak si dispo.
# Sur Android : DisplayServer.tts_speak utilise TextToSpeech natif.
# STT (reconnaissance) : nécessite un plugin Godot Android (voir README).
# Si plugin absent, les fonctions STT sont des no-op.
# ============================================================

signal tts_finished
signal stt_result(text: String)
signal stt_error(reason: String)

var tts_available: bool = false
var stt_plugin = null  # Référence au plugin Android si présent

var _current_utt_id: int = -1

func _ready() -> void:
	tts_available = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	if tts_available:
		# Connecte le callback TTS
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_ENDED,
			Callable(self, "_on_tts_ended")
		)
	# Tente de charger un plugin STT Android (nom hypothétique)
	if Engine.has_singleton("AndroidSpeechRecognizer"):
		stt_plugin = Engine.get_singleton("AndroidSpeechRecognizer")
		stt_plugin.connect("on_result", Callable(self, "_on_stt_result"))
		stt_plugin.connect("on_error", Callable(self, "_on_stt_error"))

# ---- TTS ----
func speak(text: String) -> void:
	if not tts_available:
		# Fallback : on simule la fin après un délai
		await get_tree().create_timer(0.5).timeout
		emit_signal("tts_finished")
		return
	var voices := DisplayServer.tts_get_voices_for_language(_lang_code())
	var voice_id = voices[0] if voices.size() > 0 else ""
	DisplayServer.tts_stop()
	_current_utt_id += 1
	DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, _current_utt_id)

func stop_speaking() -> void:
	if tts_available:
		DisplayServer.tts_stop()

func _on_tts_ended(_id: int) -> void:
	emit_signal("tts_finished")

func _lang_code() -> String:
	return "fr" if GameState.options.stt_lang == "fr" else "en"

# ---- STT ----
func start_listening() -> bool:
	if stt_plugin == null:
		emit_signal("stt_error", "no_plugin")
		return false
	stt_plugin.startListening(_lang_code())
	return true

func stop_listening() -> void:
	if stt_plugin != null:
		stt_plugin.stopListening()

func _on_stt_result(text: String) -> void:
	emit_signal("stt_result", text)

func _on_stt_error(reason: String) -> void:
	emit_signal("stt_error", reason)

# ---- Extraction de nombre depuis texte parlé ----
static func text_to_number(text: String) -> Variant:
	if text == null or text.strip_edges() == "":
		return null
	var t := text.to_lower().strip_edges()
	# Tente d'abord un nombre direct
	if t.is_valid_int():
		return int(t)
	if t.is_valid_float():
		return float(t)
	# Cherche un nombre dans la chaîne
	var rgx := RegEx.new()
	rgx.compile("-?\\d+(?:[.,]\\d+)?")
	var m := rgx.search(t)
	if m != null:
		var s := m.get_string().replace(",", ".")
		if s.is_valid_float():
			return float(s) if "." in s else int(s)
	# Conversion mots->nombre français basique
	return _french_words_to_number(t)

static func _french_words_to_number(t: String) -> Variant:
	var d := {
		"zero": 0, "zéro": 0,
		"un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
		"six": 6, "sept": 7, "huit": 8, "neuf": 9,
		"dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14,
		"quinze": 15, "seize": 16, "vingt": 20, "trente": 30, "quarante": 40,
		"cinquante": 50, "soixante": 60, "cent": 100, "cents": 100, "mille": 1000,
	}
	var words := t.replace("-", " ").split(" ", false)
	var total := 0
	var current := 0
	var negative := false
	for w in words:
		if w == "moins":
			negative = true
			continue
		if not d.has(w):
			continue
		var v: int = d[w]
		if v == 100:
			current = max(1, current) * 100
		elif v == 1000:
			total += max(1, current) * 1000
			current = 0
		else:
			current += v
	total += current
	if negative: total = -total
	if total == 0 and words.size() == 0:
		return null
	return total
