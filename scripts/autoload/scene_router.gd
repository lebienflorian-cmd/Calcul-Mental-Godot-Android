extends Node
# ============================================================
# SCENE ROUTER — Navigation entre scènes avec fondu noir.
# + Swipe-back depuis le bord gauche (geste smartphone).
# ============================================================

const FADE_DURATION := 0.30
const SWIPE_EDGE_WIDTH := 240.0
const SWIPE_THRESHOLD := 120.0
const SWIPE_MAX_Y_RATIO := 2.5

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _busy := false
var _history: Array = []
var _current_scene: String = ""
var _swipe_active: bool = false
var _swipe_start: Vector2 = Vector2.ZERO

var _back_map: Dictionary = {
	"res://scenes/OptionsScene.tscn": "res://scenes/MainMenu.tscn",
	"res://scenes/RulesScene.tscn": "res://scenes/MainMenu.tscn",
	"res://scenes/ScoresScene.tscn": "res://scenes/MainMenu.tscn",
	"res://scenes/GameScene.tscn": "res://scenes/MainMenu.tscn",
	"res://scenes/EndScene.tscn": "res://scenes/MainMenu.tscn",
}

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
	if _busy: return
	_busy = true
	if _current_scene != "":
		_history.append(_current_scene)
	_current_scene = scene_path
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color", Color(0, 0, 0, 1), FADE_DURATION)
	await tw.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().create_timer(0.05).timeout
	var tw2 := create_tween()
	tw2.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), FADE_DURATION)
	await tw2.finished
	_busy = false

func go_back() -> void:
	if _busy: return
	var dest := ""
	if _history.size() > 0:
		dest = _history.pop_back()
	elif _back_map.has(_current_scene):
		dest = _back_map[_current_scene]
	if dest == "": return
	AudioManager.play_sfx("back")
	_current_scene = dest
	_busy = true
	# Swipe transition: panel slides in from left, then out to right
	var vp_size := get_viewport().get_visible_rect().size
	_fade_rect.anchor_right = 0.0
	_fade_rect.anchor_bottom = 0.0
	_fade_rect.size = vp_size
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.position = Vector2(-vp_size.x, 0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_fade_rect, "position:x", 0.0, FADE_DURATION)
	await tw.finished
	get_tree().change_scene_to_file(dest)
	await get_tree().create_timer(0.05).timeout
	var tw2 := create_tween()
	tw2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw2.tween_property(_fade_rect, "position:x", vp_size.x, FADE_DURATION)
	await tw2.finished
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.position = Vector2.ZERO
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_busy = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < SWIPE_EDGE_WIDTH:
				_swipe_active = true
				_swipe_start = event.position
			else:
				_swipe_active = false
		else:
			if _swipe_active:
				var dx: float = event.position.x - _swipe_start.x
				var dy: float = absf(event.position.y - _swipe_start.y)
				if dx > SWIPE_THRESHOLD and (dy < dx * SWIPE_MAX_Y_RATIO):
					if _current_scene != "res://scenes/MainMenu.tscn" \
							and _current_scene != "res://scenes/GameScene.tscn":
						go_back()
				_swipe_active = false
