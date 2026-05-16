extends Node
# ============================================================
# GAME STATE — Etat global partagé. Options courantes, mode, session.
# ============================================================

enum Mode {
	CONTRE_LA_MONTRE = 0,
	SERIE_CHRONO     = 1,
	FLASH_ANZAN      = 2,
	AUDIO            = 3,
	INFERNAL         = 4,
}

const MODE_NAMES := {
	Mode.CONTRE_LA_MONTRE: "Contre-la-montre",
	Mode.SERIE_CHRONO:     "Série chronométrée",
	Mode.FLASH_ANZAN:      "Flash Anzan",
	Mode.AUDIO:            "Mode audio",
	Mode.INFERNAL:         "Calcul Infernal",
}

# ---- Options (défaut) ----
var options: Dictionary = {
	"mode": Mode.CONTRE_LA_MONTRE,

	# Durées / quantités
	"duration_sec": 60,
	"target_count": 20,
	"flash_count":  10,
	"flash_series": 3,
	"infernal_n":   2,
	"infernal_duration": 90,
	"infernal_tempo": 1, # 0 lent, 1 moyen, 2 rapide

	# Opérations
	"op_add": true,
	"op_sub": true,
	"op_mul": false,
	"op_div": false,
	"mix_ops": false,

	# Opérandes
	"operand_min": 2,
	"operand_max": 2,

	# Tailles
	"size_units":     true,
	"size_tens":      true,
	"size_hundreds":  false,
	"size_thousands": false,
	"size_tenk":      false,
	"size_hundk":     false,
	"mix_sizes":      false,

	# Contraintes
	"positive_only":     true,
	"allow_negative":    false,
	"only_negative":     false,
	"integer_div":       true,
	"add_no_carry":      false,
	"sub_no_borrow":     false,
	"parentheses":       false,
	"limit_tables":      false,
	"tables_max":        10,
	"max_time_per_q":    0,    # 0 = pas de limite
	"limit_result":      false,
	"result_max":        100,
	"repeat_until_ok":   false,

	# Audio & voix
	"audio_enabled":  false,
	"tts_voice":      "default",
	"voice_input":    false,
	"stt_lang":       "fr",
	"hide_calc":      false,
	"auto_validate":  false,

	# Musique
	"music_enabled": true,
	"music_volume":  60,
	"sfx_enabled":   true,
	"sfx_volume":    80,

	# Affichage
	"fullscreen":      false,
	"center_text":     true,
	"center_offset":   0,
	"font_size":       36,
	"green_correct":   true,
	"game_bg":         "rects_colors",  # rects_colors | rects | none
}

# ---- Session en cours ----
var session: Dictionary = {}

signal options_changed

func reset_session() -> void:
	session = {
		"mode": options.mode,
		"start_time": Time.get_ticks_msec(),
		"answers": [],          # array de {expr, correct, given, time_ms, ok}
		"level": _compute_level(),
	}

func _compute_level() -> int:
	# Niveau approximatif basé sur taille / opérations / opérandes
	var lvl := 1
	if options.size_hundreds: lvl += 1
	if options.size_thousands: lvl += 2
	if options.size_tenk: lvl += 2
	if options.size_hundk: lvl += 3
	if options.op_mul: lvl += 1
	if options.op_div: lvl += 1
	if options.operand_max >= 3: lvl += 1
	if options.parentheses: lvl += 1
	return lvl

func record_answer(expr: String, correct_val: float, given_val, time_ms: int, ok: bool) -> void:
	session.answers.append({
		"expr": expr,
		"correct": correct_val,
		"given": given_val,
		"time_ms": time_ms,
		"ok": ok,
	})

func compute_final_stats() -> Dictionary:
	var total := session.answers.size()
	var correct := 0
	var total_time := 0
	for a in session.answers:
		if a.ok: correct += 1
		total_time += a.time_ms
	var accuracy := 0.0 if total == 0 else float(correct) / float(total)
	var avg_time := 0.0 if total == 0 else float(total_time) / float(total) / 1000.0
	var elapsed := (Time.get_ticks_msec() - session.start_time) / 1000.0
	var level: int = session.level
	var score := 1000.0 * accuracy + 10.0 * correct + 20.0 * level - 5.0 * avg_time
	score = max(0.0, score)
	return {
		"total": total,
		"correct": correct,
		"accuracy": accuracy,
		"avg_time": avg_time,
		"elapsed": elapsed,
		"level": level,
		"score": int(round(score)),
		"mode": session.mode,
		"date": Time.get_datetime_string_from_system(false, true),
	}

func set_option(key: String, value) -> void:
	if options.has(key):
		options[key] = value
		emit_signal("options_changed")

# ---- Sérialisation pour profil ----
func options_to_dict() -> Dictionary:
	return options.duplicate(true)

func options_from_dict(d: Dictionary) -> void:
	for k in d.keys():
		if options.has(k):
			options[k] = d[k]
	emit_signal("options_changed")
