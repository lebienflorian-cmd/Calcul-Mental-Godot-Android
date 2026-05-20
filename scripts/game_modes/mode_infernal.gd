extends "res://scripts/game_modes/mode_base.gd"
# Calcul Infernal n-back : afficher des calculs en continu, le joueur
# répond au calcul d'il y a N tours.

var n_back: int = 2
var tempo: int = 1
var queue: Array = []  # FIFO de {expr, target}
var time_left: float = 90.0
var current_expr: String = ""
var current_target: float = 0.0
var current_index: int = 0
var awaiting_answer: bool = false
var _interval_timer: Timer = null

func start() -> void:
	n_back = GameState.options.infernal_n
	tempo = GameState.options.infernal_tempo
	time_left = float(GameState.options.infernal_duration)
	scene.top_label.text = "🔥 Calcul Infernal (N = %d)" % n_back
	scene.second_panel.visible = true
	scene.show_countdown(Callable(self, "_begin"))

func _begin() -> void:
	set_process(true)
	_interval_timer = Timer.new()
	_interval_timer.wait_time = _interval()
	_interval_timer.one_shot = false
	_interval_timer.timeout.connect(_show_new_calc)
	add_child(_interval_timer)
	_show_new_calc()
	_interval_timer.start()

func _interval() -> float:
	match tempo:
		0: return 4.0  # lent
		2: return 2.0  # rapide
		3: return 1.5  # très rapide
		4: return 1.0  # extrême
		_: return 3.0  # moyen

func _process(delta: float) -> void:
	time_left -= delta
	scene.top_right_label.text = "%05.1f s" % max(0.0, time_left)
	if time_left <= 0:
		set_process(false)
		if _interval_timer:
			_interval_timer.stop()
		scene.end_session()
		return

func _show_new_calc() -> void:
	# Player missed previous question (timer fired before they answered)
	if awaiting_answer:
		awaiting_answer = false
		var pending_text := ""
		if is_instance_valid(scene) and is_instance_valid(scene.answer_input):
			pending_text = String(scene.answer_input.text).strip_edges()
		_record_and_feedback(current_expr, current_target, pending_text)
	AudioManager.play_sfx("anzan")
	current_index += 1
	var d := CalcGenerator.generate()
	queue.append({"expr": d.expr_str, "target": d.value, "idx": current_index})
	var infernal_text := "[%d]  %s" % [current_index, d.expr_str]
	scene.calc_renderer.fallback_text = infernal_text
	scene.calc_renderer.expr_tree = {}
	scene.calc_renderer.queue_redraw()
	# Le joueur répond au calcul d'il y a N tours
	if queue.size() > n_back:
		var target_item = queue[queue.size() - 1 - n_back]
		current_expr = target_item.expr
		current_target = target_item.target
		scene.second_label.text = "[%d]  ?  =" % target_item.idx
		scene.show_calc(infernal_text, false)
		awaiting_answer = true
	else:
		scene.second_label.text = "..."
		awaiting_answer = false
		scene.awaiting_input = false

func handle_submit(text: String) -> void:
	if not awaiting_answer: return
	awaiting_answer = false
	var _ok := _record_and_feedback(current_expr, current_target, text)
	# Force le calcul suivant immédiatement
	if _interval_timer:
		_interval_timer.stop()
		_show_new_calc()
		_interval_timer.start()
