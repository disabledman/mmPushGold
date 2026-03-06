extends Node3D

## 遊戲主場景
## 管理發射、上層伸縮、接幣、遊戲結束等邏輯

@export var coin_scene: PackedScene
@export var shoot_origin: Node3D
@export var upper_layer: Node3D
@export var catch_zone_node: Area3D
@export var coins_label: Label
@export var pause_menu: Control
@export var game_over_overlay: Control
@export var game_over_stats: Label
@export var shoot_button: Button
@export var pause_button: Button

var _coins_remaining: int
var _coins_collected: int
var _game_start_time: float
var _game_over: bool
var _paused: bool
var _upper_layer_tween: Tween
var _coins_container: Node3D
var _camera: Camera3D
var _last_aim_position: Vector3  # 每幀更新，供發射時使用

# 上層：深 300 單位，伸出到 50% 位置（下層一半），縮回到 10% 位置（近後板）
const UpperLayerDepth := 3.0           # 上層深度（300 單位 = 3）
const BackBoardZ := -2.5              # 後板 Z
const LowerLayerHalfZ := -0.5         # 下層一半位置
const UpperLayerRetractedZ := BackBoardZ + UpperLayerDepth * 0.1 - UpperLayerDepth * 0.5  # 10% 伸出
const UpperLayerExtendedZ := LowerLayerHalfZ - UpperLayerDepth * 0.5  # 50%：前緣到下層一半

# 掉出畫面外的 Y 閾值，低於此值則回收
const CoinRecycleThresholdY := -2.0

# 下層平台範圍（用於散佈初始金幣）
const LowerLayerMinX := -5.5
const LowerLayerMaxX := 5.5
const LowerLayerMinZ := -2.3
const LowerLayerMaxZ := 1.3
const LowerLayerTopY := 0.65
const InitialCoinsOnLower := 1000


func _ready() -> void:
	_coins_container = get_node("CoinsContainer")
	if coin_scene == null:
		coin_scene = load("res://scenes/Coin.tscn") as PackedScene
	if shoot_origin == null:
		shoot_origin = get_node("GameArea/ShootOrigin")
	if upper_layer == null:
		upper_layer = get_node("GameArea/UpperLayer")
	if catch_zone_node == null:
		catch_zone_node = get_node("CatchZone")
	if coins_label == null:
		coins_label = get_node("UI/CoinsLabel")
	if pause_menu == null:
		pause_menu = get_node("UI/PauseMenu")
	if game_over_overlay == null:
		game_over_overlay = get_node("UI/GameOverOverlay")
	if game_over_stats == null:
		game_over_stats = get_node("UI/GameOverOverlay/VBox/GameOverStats")
	if shoot_button == null:
		shoot_button = get_node("UI/ShootButton")
	if pause_button == null:
		pause_button = get_node("UI/PauseButton")

	# 設定接幣區的攝影機（用於滑鼠轉 3D 座標）
	_camera = get_node_or_null("Camera3D")
	if _camera != null:
		catch_zone_node.set("game_camera", _camera)

	# 攝影機對準接幣前緣（視角稍高）
	if _camera != null:
		_camera.look_at(Vector3(0.0, 1.5, 1.2), Vector3.UP)

	_coins_remaining = GameManager.InitialCoins
	_coins_collected = 0
	_game_start_time = Time.get_ticks_msec() / 1000.0
	_game_over = false
	_paused = false

	_update_coins_label()
	pause_menu.visible = false
	game_over_overlay.visible = false

	catch_zone_node.coin_caught.connect(_on_coin_caught)
	shoot_button.pressed.connect(_on_shoot_pressed)
	pause_button.pressed.connect(_on_pause_button_pressed)

	get_node("UI/PauseMenu/VBox/ResumeButton").pressed.connect(_on_resume_pressed)
	get_node("UI/PauseMenu/VBox/MainMenuButton").pressed.connect(_on_pause_main_menu_pressed)

	_last_aim_position = shoot_origin.global_position
	_spawn_initial_coins_on_lower_layer()
	_start_upper_layer_animation()


func _spawn_initial_coins_on_lower_layer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in InitialCoinsOnLower:
		var coin: RigidBody3D = coin_scene.instantiate()
		var x := rng.randf_range(LowerLayerMinX, LowerLayerMaxX)
		var z := rng.randf_range(LowerLayerMinZ, LowerLayerMaxZ)
		coin.global_position = Vector3(x, LowerLayerTopY, z)
		coin.linear_velocity = Vector3.ZERO
		coin.angular_velocity = Vector3.ZERO
		coin.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0, TAU), rng.randf_range(-0.1, 0.1))
		_coins_container.add_child(coin)


func _process(_delta: float) -> void:
	if _game_over or _paused:
		return
	_recycle_coins_fallen_out_of_view()
	_update_last_aim_position()


func _update_last_aim_position() -> void:
	_last_aim_position = _get_mouse_world_position_on_shoot_plane()


func _recycle_coins_fallen_out_of_view() -> void:
	for child in _coins_container.get_children():
		if child is RigidBody3D and child.global_position.y < CoinRecycleThresholdY:
			child.queue_free()


func _input(ev: InputEvent) -> void:
	if _game_over or _paused:
		return

	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not shoot_button.get_global_rect().has_point(mb.global_position):
				_try_shoot()


func _start_upper_layer_animation() -> void:
	var cycle_time := GameManager.UpperLayerCycleSeconds / 2.0
	_animate_upper_layer(true, cycle_time)


func _animate_upper_layer(extend_toward_player: bool, duration: float) -> void:
	if _upper_layer_tween != null:
		_upper_layer_tween.kill()
	_upper_layer_tween = create_tween()

	var target_z := UpperLayerExtendedZ if extend_toward_player else UpperLayerRetractedZ
	_upper_layer_tween.tween_property(upper_layer, "position:z", target_z, duration)\
		.set_ease(Tween.EASE_IN_OUT)\
		.set_trans(Tween.TRANS_SINE)
	_upper_layer_tween.tween_callback(func(): _animate_upper_layer(not extend_toward_player, duration))


func _try_shoot() -> void:
	if _coins_remaining <= 0 or _game_over or _paused:
		return

	var spawn_pos := _last_aim_position
	var coin: RigidBody3D = coin_scene.instantiate()
	coin.global_position = spawn_pos
	coin.linear_velocity = Vector3(0, -3.0, 0)  # 向下射至上層平台
	_coins_container.add_child(coin)

	_coins_remaining -= 1
	_update_coins_label()

	if _coins_remaining <= 0:
		check_game_over_after_coins_settled.call_deferred()


func _get_mouse_world_position_on_shoot_plane() -> Vector3:
	var origin := shoot_origin.global_position
	if _camera == null:
		return origin

	var viewport := get_viewport()
	var mouse_pos := viewport.get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3.UP, 0.7)
	var intersect = plane.intersects_ray(from, dir)
	if intersect != null:
		var world_pos: Vector3 = intersect
		return Vector3(
			clampf(world_pos.x, LowerLayerMinX, LowerLayerMaxX),
			origin.y,
			origin.z  # Z 固定於後板處
		)
	return origin


func _on_shoot_pressed() -> void:
	_try_shoot()


func check_game_over_after_coins_settled() -> void:
	await get_tree().create_timer(2.0).timeout
	if _game_over:
		return
	if _coins_remaining > 0:
		return

	var any_moving := false
	for child in _coins_container.get_children():
		if child is RigidBody3D and is_instance_valid(child):
			var coin := child as RigidBody3D
			if coin.linear_velocity.length() > 10:
				any_moving = true
				break

	if any_moving:
		check_game_over_after_coins_settled.call_deferred()
		return

	_show_game_over()


func _on_coin_caught(coin: Node3D) -> void:
	if _game_over:
		return

	_coins_collected += 1
	_coins_remaining += 1
	coin.queue_free()
	_update_coins_label()


func _update_coins_label() -> void:
	coins_label.text = "剩餘: %d" % _coins_remaining


func _show_game_over() -> void:
	_game_over = true
	var elapsed := Time.get_ticks_msec() / 1000.0 - _game_start_time
	game_over_stats.text = "收集金幣: %d\n存活時間: %.1f 秒" % [_coins_collected, elapsed]
	game_over_overlay.visible = true

	var timer := get_tree().create_timer(GameManager.GameOverDelaySeconds)
	timer.timeout.connect(func():
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)


func _on_resume_pressed() -> void:
	_paused = false
	get_tree().paused = false
	pause_menu.visible = false


func _on_pause_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_pause_button_pressed() -> void:
	if _game_over:
		return
	_paused = true
	get_tree().paused = true
	pause_menu.visible = true
