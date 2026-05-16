extends Node2D

func _ready() -> void:
	# Redirection vers le menu principal
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
