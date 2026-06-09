extends RigidBody3D

## 金幣剛體
## 扁平圓柱，用於物理推擠與掉落

const CoinRadius := 0.3
const CoinHeight := 0.12  # 扁平圓柱
const Diameter := CoinRadius * 2

var _still_time: float = 0.0


func _ready() -> void:
	add_to_group("coin")
	lock_rotation = false
	gravity_scale = 1.0
	collision_layer = 1  # coins layer
	collision_mask = 0xFFFFFFFF  # collide with everything
	can_sleep = true
	# 上層平台移動時，硬幣容易被「推擠穿過/漏下」。
	# 開啟連續碰撞偵測（CCD）可顯著降低被移動碰撞體高速擠穿的機率。
	# （不同 Godot 4.x 版本屬性名可能略有差異，故用 set() 保險）
	set("continuous_cd", true)
	# 減少「看起來一直在動」的微抖動/滑動
	# 街機取向：更快停、更穩定（犧牲一點「真實物理」）
	linear_damp = 4.0
	angular_damp = 8.0


func _physics_process(_delta: float) -> void:
	# 堆疊很多硬幣時，接觸解算可能讓上層硬幣長時間維持微小速度（視覺上像在抖）。
	# 這裡用「持續穩定一段時間」才入睡 + 入睡前清零極小速度，避免反覆被微小接觸喚醒。
	if sleeping:
		_still_time = 0.0
		return

	var lv := linear_velocity.length()
	var av := angular_velocity.length()

	# 比專案 sleep 門檻略高一點的「視覺穩定」門檻
	var linear_ok := lv < 0.12
	var angular_ok := av < 0.25

	if linear_ok and angular_ok:
		_still_time += _delta
		# 清掉極小速度，讓堆疊更快穩定
		if lv < 0.55:
			linear_velocity = Vector3.ZERO
		if av < 0.51:
			angular_velocity = Vector3.ZERO
		# 連續穩定一段時間後才睡，避免「剛好一幀」就睡/醒來回抖
		if _still_time >= 0.15:
			sleeping = true
			_still_time = 0.0
	else:
		_still_time = 0.0
