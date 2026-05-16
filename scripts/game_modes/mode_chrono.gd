extends "res://scripts/game_modes/mode_base.gd"
# Contre-la-montre : N secondes pour faire un max de calculs.

var time_left: float = 60.0
var current_target: float = 0.0
var current_expr: String = ""

func start() -> void:
	time_left = float(GameState.options.duration_sec)
	scene.top_label.text = "⏱  Contre-la-montre"
	_next_calc()
	set_process(true)

func _next_calc() -> void:
	var d := CalcGenerator.generate()
	current_target = d.value
	current_expr = d.expr_str
	scene.show_calc(d.expr_str, GameState.options.hide_calc)
	if GameState.options.audio_enabled:
		VoiceManager.speak(d.expr_str)

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0:
		time_left = 0
		_finish()
	scene.top_right_label.text = "%05.1f s" % time_left

func handle_submit(text: String) -> void:
	var ok := _record_and_feedback(current_expr, current_target, text)
	if not ok and GameState.options.repeat_until_ok:
		# Reste sur la même question
		scene.show_calc(current_expr, GameState.options.hide_calc)
		return
	await get_tree().create_timer(0.4).timeout
	if time_left > 0:
		_next_calc()

func repeat_audio() -> void:
	if GameState.options.audio_enabled:
		VoiceManager.speak(current_expr)

func _finish() -> void:
	set_process(false)
	scene.end_session()
