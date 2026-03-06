extends Area3D

## 接幣區
## 左右移動接住掉落的金幣，金幣進入時觸發 coin_caught 訊號

@export var move_speed: float = 8.0
@export var left_bound: float = -4.0
@export var right_bound: float = 4.0

## 金幣被接住時發出，參數為 Coin 節點
signal coin_caught(coin: Node3D)

@export var game_camera: Camera3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 2  # catch_zone
	collision_mask = 1   # coins


func _process(_delta: float) -> void:
	if game_camera == null:
		return

	# 將滑鼠螢幕位置轉為 3D 世界座標（與接幣區同平面 Y）
	var viewport := get_viewport()
	var mouse_pos := viewport.get_mouse_position()
	var from := game_camera.project_ray_origin(mouse_pos)
	var dir := game_camera.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3.UP, position.y)
	var intersect = plane.intersects_ray(from, dir)
	if intersect != null:
		var world_pos: Vector3 = intersect
		position = Vector3(clampf(world_pos.x, left_bound, right_bound), position.y, position.z)
		return

	# 鍵盤備用
	var move_dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move_dir = -1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move_dir = 1.0

	if move_dir != 0.0:
		var new_x := position.x + move_dir * move_speed * get_process_delta_time()
		position = Vector3(clampf(new_x, left_bound, right_bound), position.y, position.z)


func set_touch_position(world_pos: Vector3) -> void:
	position = Vector3(clampf(world_pos.x, left_bound, right_bound), position.y, position.z)


func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		# 檢查是否為 Coin（RigidBody3D 且使用 Coin 腳本）
		coin_caught.emit(body)
