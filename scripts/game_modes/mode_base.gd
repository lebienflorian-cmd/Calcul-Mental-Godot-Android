extends Node
class_name ModeHandlerBase
# ============================================================
# Base class pour les handlers de mode.
# Le `scene` est injecté depuis GameScene.
# ============================================================

var scene: Control = null

func start() -> void:
	pass

func handle_submit(text: String) -> void:
	pass

func repeat_audio() -> void:
	pass

func on_tts_done() -> void:
	pass

# Helpers communs
func _parse_answer(text: String) -> Variant:
	var t := text.strip_edges().replace(",", ".")
	if t == "" or t == "-":
		return null
	if "." in t:
		if t.is_valid_float():
			return float(t)
	else:
		if t.is_valid_int():
			return int(t)
	return null

func _is_correct(user_val: Variant, target: float) -> bool:
	if user_val == null: return false
	return abs(float(user_val) - target) < 1e-6

func _record_and_feedback(expr: String, target: float, user_text: String) -> bool:
	var user_val = _parse_answer(user_text)
	var ok := _is_correct(user_val, target)
	var t_ms = Time.get_ticks_msec() - scene.question_start_ms
	GameState.record_answer(expr, target, user_val, t_ms, ok)
	scene.feedback(ok)
	return ok
