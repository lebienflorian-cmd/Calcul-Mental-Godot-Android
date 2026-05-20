extends Node
# ============================================================
# VOICE MANAGER — TTS (DisplayServer) + STT.
# Windows  : processus PowerShell SAPI persistant + polling fichier temp.
# Android  : plugin natif AndroidSpeechRecognizer (si présent).
# ============================================================

signal tts_finished
signal tts_started
signal stt_result(text: String)
signal stt_partial(text: String)
signal stt_error(reason: String)

var tts_available: bool = false
var stt_plugin = null

var _current_utt_id: int = -1

# Windows STT — processus persistant
var _stt_pid: int = -1
var _stt_tmpfile: String = ""
var _stt_active: bool = false   # true = Godot traite les résultats
var _ps1_path: String = ""

# Script PowerShell : reconnaissance asynchrone (latence minimale)
const _PS1 := """param([string]$out, [string]$lang = 'fr-FR')
Add-Type -AssemblyName System.Speech
$e = $null
try {
    $e = New-Object System.Speech.Recognition.SpeechRecognitionEngine(
        [System.Globalization.CultureInfo]::new($lang))
} catch {
    try { $e = New-Object System.Speech.Recognition.SpeechRecognitionEngine
    } catch { [System.IO.File]::WriteAllText($out + '.err', 'init_failed'); exit 1 }
}
try {
    $fr = $lang -like 'fr*'
    $ws = if ($fr) { [string[]]@(
        'zero','zéro','un','une','deux','trois','quatre','cinq','six','sept','huit','neuf',
        'dix','onze','douze','treize','quatorze','quinze','seize',
        'vingt','trente','quarante','cinquante','soixante','cent','mille','et','moins',
        'zéros','zeros','vingts','cents','milles',
        'dix-sept','dix-huit','dix-neuf','soixante-dix',
        'quatre-vingt','quatre-vingts','quatre-vingt-dix',
        'dix sept','dix huit','dix neuf','soixante dix',
        'quatre vingt','quatre vingts','quatre vingt dix'
    ) } else { [string[]]@(
        'zero','one','two','three','four','five','six','seven','eight','nine',
        'ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen',
        'seventeen','eighteen','nineteen','twenty','thirty','forty','fifty',
        'sixty','seventy','eighty','ninety','hundred','thousand','and','minus','negative'
    ) }
    $ch = [System.Speech.Recognition.Choices]::new($ws)
    $gb = [System.Speech.Recognition.GrammarBuilder]::new()
    $gb.Culture = [System.Globalization.CultureInfo]::new($lang)
    $gb.Append([System.Speech.Recognition.GrammarBuilder]::new($ch), 1, 8)
    $e.LoadGrammar([System.Speech.Recognition.Grammar]::new($gb))
} catch {
    $e.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new())
}
$e.SetInputToDefaultAudioDevice()
Register-ObjectEvent -InputObject $e -EventName SpeechRecognized -MessageData $out -Action {
    $t = $Event.SourceArgs[1].Result.Text.Trim()
    if ($t -ne '') { [System.IO.File]::WriteAllText($Event.MessageData, $t) }
} | Out-Null
$e.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
while ($true) { Wait-Event -TimeoutSec 0.1 | Out-Null }"""

func _ready() -> void:
	tts_available = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	if tts_available:
		DisplayServer.tts_set_utterance_callback(
			DisplayServer.TTS_UTTERANCE_ENDED,
			Callable(self, "_on_tts_ended"))
	if Engine.has_singleton("AndroidSpeechRecognizer"):
		stt_plugin = Engine.get_singleton("AndroidSpeechRecognizer")
		stt_plugin.connect("on_result",  Callable(self, "_on_stt_result"))
		stt_plugin.connect("on_partial", Callable(self, "_on_stt_partial"))
		stt_plugin.connect("on_error",   Callable(self, "_on_stt_error"))
	if OS.get_name() == "Windows":
		_write_ps1()
	set_process(false)

func _write_ps1() -> void:
	_ps1_path = OS.get_temp_dir().replace("\\", "/") + "/godot_stt_loop.ps1"
	var f := FileAccess.open(_ps1_path, FileAccess.WRITE)
	if f:
		f.store_string(_PS1)
		f.close()

# ---- _process : polling du fichier résultat (Windows uniquement) ----
func _process(_delta: float) -> void:
	if not _stt_active: return
	if not FileAccess.file_exists(_stt_tmpfile): return
	var f := FileAccess.open(_stt_tmpfile, FileAccess.READ)
	if f == null: return
	var text := f.get_as_text().strip_edges()
	f.close()
	DirAccess.remove_absolute(_stt_tmpfile)  # supprimer pour ne pas relire
	if text != "":
		emit_signal("stt_result", text)

# ---- TTS ----
func speak(text: String) -> void:
	if not tts_available:
		await get_tree().create_timer(0.5).timeout
		emit_signal("tts_finished")
		return
	var voices := DisplayServer.tts_get_voices_for_language(_tts_lang_code())
	var voice_id = voices[0] if voices.size() > 0 else ""
	DisplayServer.tts_stop()
	_current_utt_id += 1
	emit_signal("tts_started")
	DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, _current_utt_id)

func stop_speaking() -> void:
	if tts_available:
		DisplayServer.tts_stop()

func _on_tts_ended(_id: int) -> void:
	emit_signal("tts_finished")

func _tts_lang_code() -> String:
	return "fr" if GameState.options.tts_lang == "fr" else "en"

func _lang_code() -> String:
	return "fr" if GameState.options.stt_lang == "fr" else "en"

# ---- STT ----
func start_listening() -> bool:
	if OS.get_name() == "Windows":
		# Vider les résultats périmés (ex: TTS capté pendant la pause)
		if FileAccess.file_exists(_stt_tmpfile):
			DirAccess.remove_absolute(_stt_tmpfile)
		if _stt_pid >= 0:
			# Processus déjà en vie → reprendre simplement
			_stt_active = true
			set_process(true)
			return true
		# Premier démarrage du processus persistant
		var tmp := OS.get_temp_dir().replace("\\", "/")
		_stt_tmpfile = "%s/godot_stt_%d.txt" % [tmp, Time.get_ticks_msec()]
		var lang := "fr-FR" if GameState.options.stt_lang == "fr" else "en-US"
		_stt_pid = OS.create_process("powershell",
			["-NonInteractive", "-NoProfile", "-ExecutionPolicy", "Bypass",
			 "-File", _ps1_path, "-out", _stt_tmpfile, "-lang", lang])
		_stt_active = true
		set_process(true)
		return true
	if stt_plugin == null:
		emit_signal("stt_error", "no_plugin")
		return false
	stt_plugin.startListening(_lang_code())
	return true

func stop_listening() -> void:
	if OS.get_name() == "Windows":
		# Suspend : le processus continue de tourner (reste chaud), on ignore les résultats
		_stt_active = false
		set_process(false)
	elif stt_plugin != null:
		stt_plugin.stopListening()

func shutdown_stt() -> void:
	# Appelé depuis game_scene quand on quitte la session de jeu
	_stt_active = false
	set_process(false)
	if OS.get_name() == "Windows" and _stt_pid >= 0:
		OS.kill(_stt_pid)
		_stt_pid = -1
	elif stt_plugin != null:
		stt_plugin.stopListening()

func _on_stt_result(text: String) -> void:
	emit_signal("stt_result", text)

func _on_stt_partial(text: String) -> void:
	emit_signal("stt_partial", text)

func _on_stt_error(reason: String) -> void:
	emit_signal("stt_error", reason)

# ---- Extraction de nombre depuis texte parlé ----
static func text_to_number(text: String) -> Variant:
	if text == null or text.strip_edges() == "":
		return null
	var t := text.to_lower().strip_edges()
	if t.is_valid_int():
		return int(t)
	if t.is_valid_float():
		return float(t)
	var rgx := RegEx.new()
	rgx.compile("-?\\d+(?:[.,]\\d+)?")
	var m := rgx.search(t)
	if m != null:
		var s := m.get_string().replace(",", ".")
		if s.is_valid_float():
			return float(s) if "." in s else int(s)
	return _french_words_to_number(t)

static func _french_words_to_number(t: String) -> Variant:
	t = t.replace("-", " ").replace("milles", "mille").replace("cents", "cent")
	t = t.replace("vingts", "vingt")
	var tokens: Array = []
	for tok in t.split(" ", false):
		if tok != "et" and tok != "and":
			tokens.append(tok)
	if tokens.is_empty(): return null
	var neg := false
	var mi: int = tokens.find("moins")
	if mi >= 0:
		neg = true
		tokens.remove_at(mi)
	var result = _fr_full(tokens)
	if result == null: return null
	return -result if neg else result

static func _fr_full(tokens: Array) -> Variant:
	var idx: int = tokens.find("mille")
	if idx < 0: return _fr_hundreds(tokens)
	var th = 1 if idx == 0 else _fr_hundreds(tokens.slice(0, idx))
	if th == null: return null
	var rest_t: Array = tokens.slice(idx + 1)
	var rest = 0 if rest_t.is_empty() else _fr_hundreds(rest_t)
	if rest == null: rest = 0
	return th * 1000 + rest

static func _fr_hundreds(tokens: Array) -> Variant:
	var idx: int = tokens.find("cent")
	if idx < 0: return _fr_tens(tokens)
	var h = 1 if idx == 0 else _fr_tens(tokens.slice(0, idx))
	if h == null: return null
	var rest_t: Array = tokens.slice(idx + 1)
	var rest = 0 if rest_t.is_empty() else _fr_tens(rest_t)
	if rest == null: rest = 0
	return h * 100 + rest

static func _fr_tens(tokens: Array) -> Variant:
	if tokens.is_empty(): return 0
	var U := {"zero":0,"zéro":0,"un":1,"une":1,"deux":2,"trois":3,"quatre":4,
	          "cinq":5,"six":6,"sept":7,"huit":8,"neuf":9}
	var T10 := {"dix":10,"onze":11,"douze":12,"treize":13,"quatorze":14,
	            "quinze":15,"seize":16,"dix sept":17,"dix huit":18,"dix neuf":19}
	var T := {"vingt":20,"trente":30,"quarante":40,"cinquante":50,"soixante":60}
	var j: String = " ".join(PackedStringArray(tokens))
	if j.is_valid_int(): return int(j)
	if T10.has(j): return T10[j]
	if U.has(j): return U[j]
	if T.has(j): return T[j]
	if tokens[0] == "quatre" and tokens.size() > 1 and tokens[1] == "vingt":
		var base := 80
		var rest: Array = tokens.slice(2)
		if rest.is_empty(): return base
		var rj: String = " ".join(PackedStringArray(rest))
		if T10.has(rj): return base + T10[rj]
		if rest.size() == 1 and U.has(rest[0]): return base + U[rest[0]]
		return null
	if tokens[0] == "soixante" and tokens.size() > 1:
		var rest: Array = tokens.slice(1)
		var rj: String = " ".join(PackedStringArray(rest))
		if T10.has(rj): return 60 + T10[rj]
		if rest.size() == 1 and U.has(rest[0]): return 60 + U[rest[0]]
		return null
	if T.has(tokens[0]):
		var base: int = T[tokens[0]]
		if tokens.size() == 1: return base
		if tokens.size() == 2 and U.has(tokens[1]): return base + U[tokens[1]]
		return null
	return null
