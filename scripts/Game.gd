extends Node3D

## 遊戲主場景
## 管理發射、上層伸縮、接幣、遊戲結束等邏輯

@export var coin_scene: PackedScene
@export var shoot_origin: Node3D
@export var back_board: Node3D
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
var _upper_layer_retracted_z: float
var _upper_layer_extended_z: float

# 上層：前後伸縮（Z 軸）。收回終點需與後板內側面對齊（保留小間隙）。
@export var upper_layer_retract_gap: float = 0.002 # 0.002 = 2mm（單位為米；依場景比例可調）。避免設為 0，否則可能 z-fighting 閃爍
@export var upper_layer_cycle_seconds: float = 0.0 # 0=使用 GameManager.UpperLayerCycleSeconds

# 掉出畫面外的 Y 閾值，低於此值則回收
const CoinRecycleThresholdY := -2.0

# 下層平台範圍（用於散佈初始金幣）
const LowerLayerMinX := -5.5
const LowerLayerMaxX := 5.5
const LowerLayerMinZ := -2.3
const LowerLayerMaxZ := 1.3
const LowerLayerTopY := 0.65
const InitialCoinsOnLower := 200


func _ready() -> void:
	_coins_container = get_node("CoinsContainer")
	if coin_scene == null:
		coin_scene = load("res://scenes/Coin.tscn") as PackedScene
	if shoot_origin == null:
		shoot_origin = get_node("GameArea/ShootOrigin")
	if back_board == null:
		back_board = get_node("GameArea/BackBoard")
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

	# 掉幣區不需要移動；仍保留相機用於瞄準射擊
	_camera = get_node_or_null("Camera3D")

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
	_refresh_upper_layer_motion_targets()
	# 起始位置放在收回終點，避免一開始就與後板距離不正確
	upper_layer.position.z = _upper_layer_retracted_z
	_start_upper_layer_animation()


func _get_box_shape_size_z(body: Node3D) -> float:
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		return 0.0
	if not (cs.shape is BoxShape3D):
		return 0.0
	var box := cs.shape as BoxShape3D
	return box.size.z * body.scale.z


func _refresh_upper_layer_motion_targets() -> void:
	# 1) 後板內側面：取最靠近發射點（玩家側）的那一面
	var back_thickness := _get_box_shape_size_z(back_board)
	var back_center_z := back_board.global_position.z
	var shoot_z := shoot_origin.global_position.z
	var player_dir := signf(shoot_z - back_center_z)
	if player_dir == 0.0:
		player_dir = 1.0

	var back_face_a := back_center_z - back_thickness * 0.5
	var back_face_b := back_center_z + back_thickness * 0.5
	var back_inner_z := back_face_a if absf(back_face_a - shoot_z) < absf(back_face_b - shoot_z) else back_face_b

	# 2) 上層：找出哪一個面是「面向後板」的那一面（離 back_inner_z 較近）
	var upper_depth := _get_box_shape_size_z(upper_layer)
	if upper_depth <= 0.0:
		upper_depth = 3.0 # fallback，避免未設定碰撞盒時崩潰
	var half := upper_depth * 0.5

	var current_center_z := upper_layer.position.z
	var upper_face_min := current_center_z - half
	var upper_face_max := current_center_z + half
	var use_max := absf(upper_face_max - back_inner_z) < absf(upper_face_min - back_inner_z)
	var face_sign := 1.0 if use_max else -1.0

	# 3) 目標：上層面與後板內側面對齊（留 gap，方向由兩者相對位置決定）
	var dir := signf(current_center_z - back_inner_z)
	if dir == 0.0:
		dir = 1.0
	# 永遠保留最小間隙，避免後板與上層面共平面造成 z-fighting（視覺閃爍）
	# 這是「視覺安全距離」，與物理需求相比可以稍大一點（仍幾乎看不出來）
	var effective_gap := maxf(absf(upper_layer_retract_gap), 0.001) # 1mm
	var target_face_z := back_inner_z + dir * effective_gap
	_upper_layer_retracted_z = target_face_z - face_sign * half

	# 4) 伸出目標：保留現有「伸出到下層一半附近」的設計，以目前場景下層中心 Z + 其深度一半推算
	var lower_layer := get_node_or_null("GameArea/LowerLayer") as Node3D
	if lower_layer != null:
		var lower_center_z := lower_layer.position.z
		# 精準 50%：上層「面向玩家」的前緣對齊下層中心（伸出到一半）
		_upper_layer_extended_z = lower_center_z - player_dir * (upper_depth * 0.5)
	else:
		_upper_layer_extended_z = current_center_z + 1.0


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
		# 下層初始金幣：平放，避免因微傾斜導致長時間緩慢滑動（視覺上像一直在動）
		coin.rotation = Vector3(0.0, rng.randf_range(0, TAU), 0.0)
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
	var seconds := upper_layer_cycle_seconds if upper_layer_cycle_seconds > 0.0 else GameManager.UpperLayerCycleSeconds
	var cycle_time := seconds / 2.0
	_animate_upper_layer(true, cycle_time)


func _animate_upper_layer(extend_toward_player: bool, duration: float) -> void:
	if _upper_layer_tween != null:
		_upper_layer_tween.kill()
	_upper_layer_tween = create_tween()

	var target_z := _upper_layer_extended_z if extend_toward_player else _upper_layer_retracted_z
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
