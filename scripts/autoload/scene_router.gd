extends Node
# ============================================================
# SCENE ROUTER — Navigation entre scènes avec fondu noir.
# ============================================================

const FADE_DURATION := 0.35

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _busy := false
var _history: Array[String] = []
var _current_scene: String = ""

func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_layer.add_child(_fade_rect)

func goto(scene_path: String) -> void:
	if _current_scene != "" and _current_scene != scene_path:
		_history.append(_current_scene)
	_change_scene(scene_path)

func back(fallback_scene: String = "res://scenes/MainMenu.tscn") -> void:
	var target := fallback_scene
	if not _history.is_empty():
		target = _history.pop_back()
	_change_scene(target)

func _change_scene(scene_path: String) -> void:
	if _busy: return
	_busy = true
	# Fade in (vers noir)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color", Color(0, 0, 0, 1), FADE_DURATION)
	await tw.finished
	get_tree().change_scene_to_file(scene_path)
	_current_scene = scene_path
	# Fade out (depuis noir)
	await get_tree().create_timer(0.05).timeout
	var tw2 := create_tween()
	tw2.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), FADE_DURATION)
	await tw2.finished
	_busy = false
