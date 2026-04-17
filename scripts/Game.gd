extends Node3D

## 遊戲主場景
## 管理發射、上層伸縮、接幣、遊戲結束等邏輯

@export var coin_scene: PackedScene
@export var bonus_coin_scene: PackedScene
@export var dollar_coin_scene: PackedScene
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
var _coins_fallen_out: int
var _coins_shot_out: int
var _game_start_time: float
var _game_over: bool
var _paused: bool
var _upper_layer_tween: Tween
var _coins_container: Node3D
var _camera: Camera3D
var _last_aim_position: Vector3  # 每幀更新，供發射時使用
var _upper_layer_retracted_z: float
var _upper_layer_extended_z: float

@export var bonus_drop_every_fallen: int = 20
@export var bonus_add_coins_on_settled: int = 10
@export var bonus_drop_every_shots: int = 20
@export var dollar_drop_every_shots: int = 30
@export var dollar_add_coins_on_settled: int = 1000
## 同一發同時掉 bonus + dollar 時，中心點左右錯開（半寬，兩者相距約 2×此值），避免重疊穿模
@export var special_item_spawn_half_extent: float = 0.45
## 同時多個時依序略抬高，減少初幀重疊
@export var special_item_spawn_y_step: float = 0.08

# 上層：前後伸縮（Z 軸）。收回終點需與後板內側面對齊（保留小間隙）。
@export var upper_layer_retract_gap: float = 0.002 # 0.002 = 2mm（單位為米；依場景比例可調）。避免設為 0，否則可能 z-fighting 閃爍
@export var upper_layer_cycle_seconds: float = 0.0 # 0=使用 GameManager.UpperLayerCycleSeconds

# 掉出畫面外的 Y 閾值，低於此值則回收
# 注意：掉幣區命中的金幣會繼續往下掉一段，讓玩家看得到它離開畫面後才消失
const CoinRecycleThresholdY := -6.0

const CollectedMetaKey := &"collected"
const CollectedFallSpeed := 6.0

# 下層平台範圍（用於散佈初始金幣）
const LowerLayerMinX := -5.5
const LowerLayerMaxX := 5.5
const LowerLayerMinZ := -2.3
const LowerLayerMaxZ := 1.3
const InitialCoinsOnLower := 100

# 初始生成時，幣要「剛好落在」下層頂面上方一點點：
# 若直接用常數，任何平台/幣厚度調整都可能造成微穿模 → 反覆解算 → 視覺抖動。
const SpawnSurfaceGapY := 0.3  # 300mm 視覺上看不出、但能避免穿模
const SpawnEdgeSafeMargin := 1.0 # 額外內縮：避免初期推擠直接溢出平台
const SpawnBackEdgeExtraMargin := 1.2 # 後緣額外內縮：避免靠近後板/後緣縫隙掉落


func _ready() -> void:
	_coins_container = get_node("CoinsContainer")
	if coin_scene == null:
		coin_scene = load("res://scenes/Coin.tscn") as PackedScene
	if coin_scene == null:
		push_error("coin_scene is null. Failed to load res://scenes/Coin.tscn")
		set_process(false)
		set_physics_process(false)
		return
	if bonus_coin_scene == null:
		bonus_coin_scene = load("res://scenes/BonusCoin.tscn") as PackedScene
	if dollar_coin_scene == null:
		dollar_coin_scene = load("res://scenes/DollarCoin.tscn") as PackedScene
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
	_coins_fallen_out = 0
	_coins_shot_out = 0
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
	_ensure_lower_layer_drop_rails()
	_spawn_initial_coins_on_lower_layer()
	_refresh_upper_layer_motion_targets()
	# 起始位置放在收回終點，避免一開始就與後板距離不正確
	upper_layer.position.z = _upper_layer_retracted_z
	_start_upper_layer_animation_deferred.call_deferred()


func _start_upper_layer_animation_deferred() -> void:
	# 讓初始撒幣先經過至少一個 physics frame 解算穩定，
	# 避免上層一開始就移動時把仍在重疊/穿模邊緣的硬幣擠飛或擠落。
	await get_tree().physics_frame
	if not is_instance_valid(upper_layer) or _game_over:
		return
	_start_upper_layer_animation()


func _ensure_lower_layer_drop_rails() -> void:
	# 下層僅「前緣」（朝玩家 / 接幣區的 Z 較大側）可讓金幣落下；其餘三邊用矮牆擋住，
	# 避免從左右、後緣或縫隙整排漏下。
	var game_area := get_node_or_null("GameArea") as Node3D
	if game_area == null:
		return

	var lower := game_area.get_node_or_null("LowerLayer") as Node3D
	if lower == null:
		return
	var lower_cs := lower.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if lower_cs == null or not (lower_cs.shape is BoxShape3D):
		return

	var lower_box := lower_cs.shape as BoxShape3D
	var lower_scale := lower_cs.global_transform.basis.get_scale()
	var lower_half_x := (lower_box.size.x * absf(lower_scale.x)) * 0.5
	var lower_half_z := (lower_box.size.z * absf(lower_scale.z)) * 0.5

	var curb_height := 0.25
	var curb_thickness := 0.25
	var top_y := _get_static_body_top_y(lower, 0.5)
	var curb_y := top_y + curb_height * 0.5 - 0.01

	var phys_mat: PhysicsMaterial = null
	if lower is StaticBody3D:
		phys_mat = (lower as StaticBody3D).physics_material_override

	var cx := lower_cs.global_position.x
	var cz := lower_cs.global_position.z

	# 後緣（Z 較小）
	if game_area.get_node_or_null("LowerBackCurb") == null:
		var back := StaticBody3D.new()
		back.name = "LowerBackCurb"
		game_area.add_child(back)
		back.physics_material_override = phys_mat
		back.global_position = Vector3(cx, curb_y, cz - lower_half_z + curb_thickness * 0.5)
		var back_shape := BoxShape3D.new()
		back_shape.size = Vector3(lower_half_x * 2.0, curb_height, curb_thickness)
		var back_cs := CollisionShape3D.new()
		back_cs.shape = back_shape
		back.add_child(back_cs)

	# 左緣（X 較小）
	if game_area.get_node_or_null("LowerLeftCurb") == null:
		var left := StaticBody3D.new()
		left.name = "LowerLeftCurb"
		game_area.add_child(left)
		left.physics_material_override = phys_mat
		left.global_position = Vector3(cx - lower_half_x + curb_thickness * 0.5, curb_y, cz)
		var left_shape := BoxShape3D.new()
		left_shape.size = Vector3(curb_thickness, curb_height, lower_half_z * 2.0)
		var left_cs := CollisionShape3D.new()
		left_cs.shape = left_shape
		left.add_child(left_cs)

	# 右緣（X 較大）
	if game_area.get_node_or_null("LowerRightCurb") == null:
		var right := StaticBody3D.new()
		right.name = "LowerRightCurb"
		game_area.add_child(right)
		right.physics_material_override = phys_mat
		right.global_position = Vector3(cx + lower_half_x - curb_thickness * 0.5, curb_y, cz)
		var right_shape := BoxShape3D.new()
		right_shape.size = Vector3(curb_thickness, curb_height, lower_half_z * 2.0)
		var right_cs := CollisionShape3D.new()
		right_cs.shape = right_shape
		right.add_child(right_cs)


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

	var lower_layer := get_node_or_null("GameArea/LowerLayer") as Node3D
	var lower_top_y := _get_static_body_top_y(lower_layer, 0.5)
	var lower_rect := _get_static_body_top_rect_xz(lower_layer)

	for i in InitialCoinsOnLower:
		var coin: RigidBody3D = coin_scene.instantiate()
		var coin_radius_xz := _get_rigid_body_radius_xz(coin, 0.3)
		# 生成範圍要「向內縮」一個半徑，否則硬幣中心落在邊緣附近時會有一部分懸空，會直接掉下去。
		# 另外再加安全邊界，避免一開始硬幣互相推擠時「立刻」溢出平台。
		var inset := coin_radius_xz + SpawnEdgeSafeMargin
		var min_x := lower_rect.position.x + inset
		var max_x := lower_rect.position.x + lower_rect.size.x - inset
		# Rect2 的 y 對應 world Z；後緣是 min_z（本場景後板在較小的 Z）
		var min_z := lower_rect.position.y + inset + SpawnBackEdgeExtraMargin
		var max_z := lower_rect.position.y + lower_rect.size.y - inset

		# 若場景配置不完整導致 rect 無效，就回退到原本常數（但仍會保留半徑 inset 的概念）
		if min_x >= max_x:
			min_x = LowerLayerMinX + inset
			max_x = LowerLayerMaxX - inset
		if min_z >= max_z:
			min_z = LowerLayerMinZ + inset
			max_z = LowerLayerMaxZ - inset

		var x := rng.randf_range(min_x, max_x)
		var z := rng.randf_range(min_z, max_z)
		var coin_half_height_y := _get_rigid_body_half_height_y(coin, 0.06)
		# 一次生成很多枚時，若全都在同一個 Y 平面，重疊會導致初幀解算「爆炸式推擠」。
		# 稍微分層往上疊，讓它更像自然落下堆疊，且不會瞬間把部分硬幣推到邊緣掉落。
		var coins_per_layer := 35
		var layer := i / coins_per_layer
		var layer_step := maxf(coin_half_height_y * 2.0, 0.12) * 0.6
		var y := lower_top_y + coin_half_height_y + SpawnSurfaceGapY + layer * layer_step
		coin.global_position = Vector3(x, y, z)
		coin.linear_velocity = Vector3.ZERO
		coin.angular_velocity = Vector3.ZERO
		# 下層初始金幣：平放，避免因微傾斜導致長時間緩慢滑動（視覺上像一直在動）
		coin.rotation = Vector3(0.0, rng.randf_range(0, TAU), 0.0)
		_coins_container.add_child(coin)


func _get_static_body_top_y(body: Node3D, fallback_top_y: float) -> float:
	if body == null:
		return fallback_top_y
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return fallback_top_y
	if cs.shape is BoxShape3D:
		var box := cs.shape as BoxShape3D
		# 用 CollisionShape3D 的全域 transform（它可能有 local offset/scale）
		var scale_y := _get_global_scale_y(cs)
		return cs.global_position.y + (box.size.y * scale_y) * 0.5
	return fallback_top_y


func _get_rigid_body_half_height_y(body: Node3D, fallback_half_height_y: float) -> float:
	if body == null:
		return fallback_half_height_y
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return fallback_half_height_y
	var scale_y := _get_global_scale_y(body)
	if cs.shape is CylinderShape3D:
		var cyl := cs.shape as CylinderShape3D
		return (cyl.height * scale_y) * 0.5
	if cs.shape is BoxShape3D:
		var box := cs.shape as BoxShape3D
		return (box.size.y * scale_y) * 0.5
	if cs.shape is SphereShape3D:
		var s := cs.shape as SphereShape3D
		return s.radius * scale_y
	return fallback_half_height_y


func _get_global_scale_y(node: Node3D) -> float:
	# Godot 4: Node3D 沒有可直接取用的 global_scale 屬性；用 global_transform 的 basis 取得縮放。
	# 若發生奇怪狀況（例如 scale 為 0），回退到 1。
	var s := node.global_transform.basis.get_scale()
	var y := absf(s.y)
	return 1.0 if is_zero_approx(y) else y


func _get_static_body_top_rect_xz(body: Node3D) -> Rect2:
	# 回傳下層板「頂面投影」的 XZ 矩形（Rect2 的 x/y 對應 world x/z）。
	# 注意：只支援 BoxShape3D（本專案平台就是 box）。
	if body == null:
		return Rect2()
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return Rect2()
	if not (cs.shape is BoxShape3D):
		return Rect2()

	var box := cs.shape as BoxShape3D
	# 用 CollisionShape3D 的全域 transform（它可能有 local offset/scale）
	var scale := cs.global_transform.basis.get_scale()
	var half_x := (box.size.x * absf(scale.x)) * 0.5
	var half_z := (box.size.z * absf(scale.z)) * 0.5
	var cx := cs.global_position.x
	var cz := cs.global_position.z
	return Rect2(cx - half_x, cz - half_z, half_x * 2.0, half_z * 2.0)


func _get_rigid_body_radius_xz(body: Node3D, fallback_radius: float) -> float:
	if body == null:
		return fallback_radius
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return fallback_radius
	var scale := body.global_transform.basis.get_scale()
	var scale_xz := maxf(absf(scale.x), absf(scale.z))
	if cs.shape is CylinderShape3D:
		var cyl := cs.shape as CylinderShape3D
		return cyl.radius * scale_xz
	if cs.shape is SphereShape3D:
		var s := cs.shape as SphereShape3D
		return s.radius * scale_xz
	if cs.shape is BoxShape3D:
		# 粗略：取 box 的對角半徑，避免生成到邊緣懸空
		var b := cs.shape as BoxShape3D
		var half_x := (b.size.x * absf(scale.x)) * 0.5
		var half_z := (b.size.z * absf(scale.z)) * 0.5
		return sqrt(half_x * half_x + half_z * half_z)
	return fallback_radius


func _process(_delta: float) -> void:
	if _game_over or _paused:
		return
	_recycle_coins_fallen_out_of_view()
	_update_last_aim_position()


func _update_last_aim_position() -> void:
	_last_aim_position = _get_mouse_world_position_on_shoot_plane()


func _recycle_coins_fallen_out_of_view() -> void:
	for child in _coins_container.get_children():
		if not (child is Node3D):
			continue
		var n := child as Node3D
		if n.global_position.y >= CoinRecycleThresholdY:
			continue

		# 只統計真正的金幣掉落（避免把獎勵幣也算進 20 枚）
		if n.is_in_group("coin"):
			# 命中接幣區的金幣會被標記 collected，仍會掉到畫面外才回收；不把這種「已收集」算進掉落 20 枚
			if not n.has_meta(CollectedMetaKey):
				_coins_fallen_out += 1

		n.queue_free()


func _special_item_spawn_pos(slot: int) -> Vector3:
	var base := _last_aim_position
	var dx := (float(slot) - 0.5) * 2.0 * special_item_spawn_half_extent
	var p := base + Vector3(dx, float(slot) * special_item_spawn_y_step, 0.0)
	p.x = clampf(p.x, LowerLayerMinX, LowerLayerMaxX)
	return p


func _spawn_bonus_coin_at(spawn_pos: Vector3) -> void:
	if bonus_coin_scene == null or _game_over or _paused:
		return

	var bonus := bonus_coin_scene.instantiate()
	if not (bonus is RigidBody3D):
		push_error("BonusCoin scene root must be RigidBody3D")
		return

	var rb := bonus as RigidBody3D
	rb.global_position = spawn_pos
	rb.linear_velocity = Vector3(0.0, -3.0, 0.0)
	rb.angular_velocity = Vector3.ZERO
	rb.sleeping = false
	_coins_container.add_child(rb)


func _spawn_dollar_coin_at(spawn_pos: Vector3) -> void:
	if dollar_coin_scene == null or _game_over or _paused:
		return

	var inst := dollar_coin_scene.instantiate()
	if not (inst is RigidBody3D):
		push_error("DollarCoin scene root must be RigidBody3D")
		return

	var rb := inst as RigidBody3D
	rb.global_position = spawn_pos
	rb.linear_velocity = Vector3(0.0, -3.0, 0.0)
	rb.angular_velocity = Vector3.ZERO
	rb.sleeping = false
	_coins_container.add_child(rb)


func _apply_caught_fall_behavior(body: Node3D) -> void:
	# 進入掉幣區後：不要立刻消失，讓它垂直掉到畫面外再由回收邏輯清掉
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.sleeping = false
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.linear_velocity = Vector3(0.0, -CollectedFallSpeed, 0.0)
		rb.angular_velocity = Vector3.ZERO


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
	# 上層是物理互動物件（AnimatableBody3D），用 physics tween 避免非物理幀更新造成瞬移擠飛。
	_upper_layer_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

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

	# 每發射/掉下 20 枚金幣，自動掉下一枚獎勵幣
	_coins_shot_out += 1
	var spawn_bonus := bonus_drop_every_shots > 0 and (_coins_shot_out % bonus_drop_every_shots) == 0
	var spawn_dollar := dollar_drop_every_shots > 0 and (_coins_shot_out % dollar_drop_every_shots) == 0
	if spawn_bonus and spawn_dollar:
		_spawn_bonus_coin_at(_special_item_spawn_pos(0))
		_spawn_dollar_coin_at(_special_item_spawn_pos(1))
	else:
		if spawn_bonus:
			_spawn_bonus_coin_at(_last_aim_position)
		if spawn_dollar:
			_spawn_dollar_coin_at(_last_aim_position)

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

	if coin.has_meta(CollectedMetaKey):
		return
	coin.set_meta(CollectedMetaKey, true)

	# bonus / dollar：必須「掉進前方掉幣區」才給獎勵
	if coin.is_in_group("bonus_coin"):
		_coins_remaining += maxi(0, bonus_add_coins_on_settled)
		_apply_caught_fall_behavior(coin)
		_update_coins_label()
		return
	if coin.is_in_group("dollar_coin"):
		_coins_remaining += maxi(0, dollar_add_coins_on_settled)
		_apply_caught_fall_behavior(coin)
		_update_coins_label()
		return

	# 一般金幣：原本行為（接到 +1 並計入收集數）
	_coins_collected += 1
	_coins_remaining += 1

	_apply_caught_fall_behavior(coin)
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
