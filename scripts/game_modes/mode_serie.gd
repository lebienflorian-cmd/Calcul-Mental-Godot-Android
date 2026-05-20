extends "res://scripts/game_modes/mode_base.gd"
# Série chronométrée : N calculs, on mesure le temps total.

var target_count: int = 20
var done_count: int = 0
var start_time: int = 0
var current_target: float = 0.0
var current_expr: String = ""
var current_tree: Dictionary = {}

func start() -> void:
	target_count = GameState.options.target_count
	done_count = 0
	start_time = Time.get_ticks_msec()
	scene.top_label.text = "📋  Série chronométrée"
	_next_calc()
	set_process(true)

func _next_calc() -> void:
	if done_count >= target_count:
		_finish()
		return
	var d := CalcGenerator.generate()
	current_target = d.value
	current_expr = d.expr_str
	current_tree = d.get("tree", {})
	scene.show_calc(d.expr_str, GameState.options.hide_calc, current_tree)
	if GameState.options.audio_enabled:
		VoiceManager.speak(d.expr_str)

func _process(_delta: float) -> void:
	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	scene.top_right_label.text = "%d / %d  —  %.1fs" % [done_count, target_count, elapsed]

func handle_submit(text: String) -> void:
	var ok := _record_and_feedback(current_expr, current_target, text)
	if ok or not GameState.options.repeat_until_ok:
		done_count += 1
	await get_tree().create_timer(0.4).timeout
	if done_count < target_count:
		_next_calc()
	else:
		_finish()

func repeat_audio() -> void:
	if GameState.options.audio_enabled:
		VoiceManager.speak(current_expr)

func _finish() -> void:
	set_process(false)
	scene.end_session()
