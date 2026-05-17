extends Node2D

func _ready() -> void:
	SceneRouter.clear_history()
	SceneRouter.goto("res://scenes/MainMenu.tscn")
