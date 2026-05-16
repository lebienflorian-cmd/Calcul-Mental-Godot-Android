extends Node
# ============================================================
# AUDIO MANAGER — Musiques + bruitages. Tolère absence de fichiers.
# ============================================================

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 6

const SFX_PATHS := {
	"click":   "res://assets/sounds/sfx_click.wav",
	"back":    "res://assets/sounds/sfx_back.wav",
	"start":   "res://assets/sounds/sfx_start.wav",
	"end":     "res://assets/sounds/sfx_end.wav",
	"step":    "res://assets/sounds/sfx_step.wav",
	"anzan":   "res://assets/sounds/sfx_anzan.wav",
	"ding":    "res://assets/sounds/sfx_ding.wav",
	"correct": "res://assets/sounds/sfx_correct.wav",
	"error":   "res://assets/sounds/sfx_error.wav",
	"save":    "res://assets/sounds/sfx_save.wav",
}

const MUSIC_PATHS := {
	"menu": "res://assets/music/music_menu.ogg",
	"game": "res://assets/music/music_game.ogg",
}

var _sfx_cache: Dictionary = {}
var _current_music: String = ""

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)
	# Précharger
	for key in SFX_PATHS.keys():
		var path: String = SFX_PATHS[key]
		if ResourceLoader.exists(path):
			_sfx_cache[key] = load(path)
	GameState.options_changed.connect(_apply_volumes)
	_apply_volumes()

func _apply_volumes() -> void:
	var mv: float = GameState.options.music_volume / 100.0
	var sv: float = GameState.options.sfx_volume / 100.0
	music_player.volume_db = linear_to_db(max(0.001, mv))
	music_player.stream_paused = not GameState.options.music_enabled
	for p in sfx_players:
		p.volume_db = linear_to_db(max(0.001, sv))

func play_music(name: String) -> void:
	if _current_music == name and music_player.playing:
		return
	if not GameState.options.music_enabled: return
	var path = MUSIC_PATHS.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	music_player.stream = load(path)
	music_player.play()
	_current_music = name

func stop_music() -> void:
	music_player.stop()
	_current_music = ""

func play_sfx(key: String) -> void:
	if not GameState.options.sfx_enabled: return
	if not _sfx_cache.has(key): return
	for p in sfx_players:
		if not p.playing:
			p.stream = _sfx_cache[key]
			p.play()
			return
	# Tous occupés -> on remplace le premier
	sfx_players[0].stream = _sfx_cache[key]
	sfx_players[0].play()
