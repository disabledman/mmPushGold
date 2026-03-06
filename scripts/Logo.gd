extends Control

## Logo 畫面
## 顯示約 2 秒，可點擊跳過

var _timer: Timer


func _ready() -> void:
	_timer = get_node("Timer")
	_timer.timeout.connect(_on_timer_timeout)
	_timer.start(GameManager.LogoDisplaySeconds)

	# Click/tap to skip
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_go_to_main_menu()
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_go_to_main_menu()


func _on_timer_timeout() -> void:
	_go_to_main_menu()


func _go_to_main_menu() -> void:
	_timer.stop()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
