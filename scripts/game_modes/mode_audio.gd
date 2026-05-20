extends "res://scripts/game_modes/mode_base.gd"
# Mode audio : TTS lit le calcul, STT écoute la réponse.

var current_target: float = 0.0
var current_expr: String = ""
var target_count: int = 10
var done: int = 0

func start() -> void:
	target_count = GameState.options.target_count
	scene.top_label.text = "🔊 Mode audio"
	_next_calc()

func _next_calc() -> void:
	if done >= target_count:
		scene.end_session()
		return
	scene.set_mic_active(false)
	scene.top_right_label.text = "%d / %d" % [done, target_count]
	var d := CalcGenerator.generate()
	current_target = d.value
	current_expr = d.expr_str
	scene.show_calc(d.expr_str, GameState.options.hide_calc, d.get("tree", {}))
	VoiceManager.speak(d.expr_str)

func on_tts_started() -> void:
	var delay := float(GameState.options.stt_delay)
	if delay < 0.0:
		await get_tree().create_timer(maxf(0.0, -delay)).timeout
		scene.set_mic_active(true)

func on_tts_done() -> void:
	var delay := float(GameState.options.stt_delay)
	if delay >= 0.0:
		await get_tree().create_timer(delay).timeout
		scene.set_mic_active(true)
	# delay < 0 : mic already started before TTS finished via on_tts_started

func handle_submit(text: String) -> void:
	var _ok := _record_and_feedback(current_expr, current_target, text)
	done += 1
	await get_tree().create_timer(0.5).timeout
	_next_calc()

func repeat_audio() -> void:
	VoiceManager.speak(current_expr)
