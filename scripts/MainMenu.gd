extends Control

## 主選單
## 開始遊戲、結束遊戲


func _ready() -> void:
	var start_button := get_node("VBoxContainer/StartButton") as Button
	var quit_button := get_node("VBoxContainer/QuitButton") as Button

	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
