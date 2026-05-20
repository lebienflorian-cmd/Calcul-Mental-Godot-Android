extends "res://scripts/game_modes/mode_base.gd"
# Flash Anzan : afficher des nombres un par un, le joueur donne la somme.

var current_series: int = 0
var total_series: int = 1
var numbers: Array = []
var target_sum: float = 0.0
var awaiting_answer: bool = false
var current_expr: String = "Anzan"

func start() -> void:
	total_series = GameState.options.flash_series
	current_series = 0
	scene.top_label.text = "⚡ Flash Anzan"
	scene.calc_panel.visible = false
	# Cache aussi le panneau secondaire / clavier resté actif
	scene.show_countdown(Callable(self, "_begin_series"))

func _begin_series() -> void:
	current_series += 1
	scene.top_right_label.text = "Série %d / %d" % [current_series, total_series]
	var d := CalcGenerator.generate()
	numbers = d.numbers
	target_sum = d.value
	current_expr = "Σ = %d" % int(target_sum)
	_play_numbers()

func _play_numbers() -> void:
	scene.anzan_label.visible = true
	scene.calc_panel.visible = false
	var delay := _delay_per_level()
	for n in numbers:
		scene.anzan_label.text = str(n)
		scene.anzan_label.modulate.a = 0.0
		scene.anzan_label.scale = Vector2(1.4, 1.4)
		AudioManager.play_sfx("anzan")
		var tw := create_tween()
		tw.parallel().tween_property(scene.anzan_label, "modulate:a", 1.0, delay * 0.3)
		tw.parallel().tween_property(scene.anzan_label, "scale", Vector2.ONE, delay * 0.5)
		tw.tween_interval(delay * 0.3)
		tw.tween_property(scene.anzan_label, "modulate:a", 0.0, delay * 0.4)
		await tw.finished
	# Affiche "?"
	scene.anzan_label.text = "?"
	scene.anzan_label.modulate.a = 1.0
	scene.anzan_label.scale = Vector2.ONE
	AudioManager.play_sfx("ding")
	await get_tree().create_timer(0.3).timeout
	scene.anzan_label.visible = false
	scene.calc_panel.visible = true
	scene.show_calc("Entrez la somme", false)
	awaiting_answer = true

func _delay_per_level() -> float:
	var lvl: int = int(GameState.options.anzan_level)
	match lvl:
		0: return 1.5
		1: return 1.0
		3: return 0.5
		4: return 0.3
		_: return 0.7  # 2 = moyen

func handle_submit(text: String) -> void:
	if not awaiting_answer: return
	awaiting_answer = false
	var _ok := _record_and_feedback(current_expr, target_sum, text)
	await get_tree().create_timer(0.7).timeout
	if current_series < total_series:
		_begin_series()
	else:
		scene.end_session()
