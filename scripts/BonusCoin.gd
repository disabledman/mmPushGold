extends RigidBody3D

## 獎勵幣（OBJ 模型）
## 當掉落並堆疊到穩定（入睡）後，發出 settled 信號，供 Game 增加可發射金幣數量。
##
## 注意：請勿縮放 RigidBody3D 根節點（Godot 物理體縮放容易造成視覺/碰撞不一致）。
## 視覺只縮放 MeshInstance3D；碰撞為圓柱，尺寸依 `size_multiplier` 相對一般金幣放大。

signal settled(bonus_coin: RigidBody3D)

@export var settle_seconds: float = 0.25
## 相對一般金幣（直徑 0.6）的倍率；預設 2 = 直徑約 1.2、較醒目
@export var size_multiplier: float = 2.0

## 與 `scripts/Coin.gd` / `scenes/Coin.tscn` 一致（一般金幣基準）
const _CoinRadius: float = 0.3
const _CoinHeight: float = 0.12

const _RewardedMetaKey := &"rewarded"

var _still_time: float = 0.0


func _apply_gold_material(mi: MeshInstance3D) -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.75, 0.2, 1)
	gold.metallic = 0.8
	gold.roughness = 0.3
	gold.vertex_color_use_as_albedo = false
	var mesh: Mesh = mi.mesh
	if mesh != null and mesh.get_surface_count() > 0:
		mi.material_override = null
		for i in mesh.get_surface_count():
			mi.set_surface_override_material(i, gold)
	else:
		mi.material_override = gold


func _ready() -> void:
	add_to_group("bonus_coin")
	can_sleep = true
	gravity_scale = 1.0
	lock_rotation = false
	# 物理體維持單位縮放；尺寸由碰撞形狀與子節點縮放決定
	scale = Vector3.ONE

	var visual := get_node_or_null("Visual") as Node3D
	var mi := visual.get_node_or_null("Mesh") as MeshInstance3D if visual != null else null
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D

	if mi != null and mi.mesh != null:
		var aabb: AABB = (mi.mesh as Mesh).get_aabb()
		var max_xz: float = maxf(aabb.size.x, aabb.size.z)
		var mult: float = maxf(0.01, size_multiplier)
		var target_d: float = _CoinRadius * 2.0 * mult
		if max_xz > 0.0001:
			var s: float = target_d / max_xz
			# OBJ 若以 mm/cm 匯出，AABB 可能極小或極大；把比例拉回合理範圍
			while s < 0.05:
				s *= 10.0
			while s > 500.0:
				s *= 0.1
			mi.scale = Vector3.ONE * s

		# OBJ/MTL 貼圖常遺失；強制黃金材質。部分匯入 mesh 的 `material_override` 會不生效，改逐 surface 覆寫。
		_apply_gold_material(mi)

	# 圓柱碰撞與視覺倍率一致（不依賴 OBJ 凸包）
	if cs != null:
		var mult: float = maxf(0.01, size_multiplier)
		var cyl := CylinderShape3D.new()
		cyl.height = _CoinHeight * mult
		cyl.radius = _CoinRadius * mult
		cs.shape = cyl

	var phys := PhysicsMaterial.new()
	phys.friction = 1.3
	phys.bounce = 0.0
	physics_material_override = phys

	set("continuous_cd", true)
	linear_damp = 4.0
	angular_damp = 8.0


func _physics_process(delta: float) -> void:
	if has_meta(_RewardedMetaKey):
		return

	if sleeping:
		set_meta(_RewardedMetaKey, true)
		settled.emit(self)
		return

	var lv := linear_velocity.length()
	var av := angular_velocity.length()
	var linear_ok := lv < 0.12
	var angular_ok := av < 0.25

	if linear_ok and angular_ok:
		_still_time += delta
		if _still_time >= settle_seconds:
			sleeping = true
			_still_time = 0.0
	else:
		_still_time = 0.0
