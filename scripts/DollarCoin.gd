extends RigidBody3D

## 美元圖示（dollar-icon.glb）
## 落地穩定後發出 settled，由 Game 增加可發射金幣。
##
## 預設使用 Blender 匯入的材質（綠鈔、白封帶、$ 等）。整份場景掛在 Visual 下，避免只拆第一個 Mesh 而缺件。
## 若仍顯示白塊，可在 Inspector 開啟 `force_game_material` 改為單色備用。

signal settled(dollar_coin: RigidBody3D)

@export var mesh_source: PackedScene
@export var settle_seconds: float = 0.25
## 相對一般金幣直徑 0.6 的倍率（略大於獎勵幣以便辨識）
@export var size_multiplier: float = 2.5
## 開啟時覆寫為遊戲內單色材質（僅備用；正確外觀請維持關閉以使用匯入材質）
@export var force_game_material: bool = false

const _CoinRadius: float = 0.3
const _CoinHeight: float = 0.12
const _RewardedMetaKey := &"rewarded"

var _still_time: float = 0.0
var _has_touched: bool = false


func _apply_dollar_material(mi: MeshInstance3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.7, 0.36, 1)
	mat.metallic = 0.78
	mat.roughness = 0.32
	mat.vertex_color_use_as_albedo = false
	var mesh: Mesh = mi.mesh
	if mesh != null and mesh.get_surface_count() > 0:
		mi.material_override = null
		for i in mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	else:
		mi.material_override = mat


func _apply_dollar_material_to_tree(node: Node) -> void:
	if node is MeshInstance3D:
		_apply_dollar_material(node as MeshInstance3D)
	for c in node.get_children():
		_apply_dollar_material_to_tree(c)


static func _count_mesh_instances(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			n += 1
	for c in node.get_children():
		n += _count_mesh_instances(c)
	return n


static func _max_mesh_horizontal_extent(node: Node) -> float:
	var m := 0.0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var ab := mi.mesh.get_aabb()
			m = maxf(ab.size.x, ab.size.z)
	for c in node.get_children():
		m = maxf(m, _max_mesh_horizontal_extent(c))
	return m


func _ready() -> void:
	add_to_group("dollar_coin")
	can_sleep = true
	gravity_scale = 1.0
	lock_rotation = false
	scale = Vector3.ONE
	# 需要接觸數量來判定「已落地/碰撞過」才可結算
	contact_monitor = true
	max_contacts_reported = 8

	if mesh_source == null:
		mesh_source = load("res://assets/3d/dollar-icon.glb") as PackedScene

	var visual := get_node_or_null("Visual") as Node3D
	var placeholder := visual.get_node_or_null("Mesh") as MeshInstance3D if visual != null else null
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D

	if mesh_source != null and visual != null:
		var tmp := mesh_source.instantiate()
		if _count_mesh_instances(tmp) == 0:
			tmp.queue_free()
			push_error("DollarCoin: no MeshInstance3D with mesh in dollar-icon.glb")
		else:
			if placeholder != null:
				placeholder.queue_free()
			tmp.name = "DollarModel"
			visual.add_child(tmp)

			var max_xz: float = _max_mesh_horizontal_extent(tmp)
			var mult: float = maxf(0.01, size_multiplier)
			var target_d: float = _CoinRadius * 2.0 * mult
			if max_xz > 0.0001:
				var s: float = target_d / max_xz
				while s < 0.05:
					s *= 10.0
				while s > 500.0:
					s *= 0.1
				tmp.scale = Vector3.ONE * s

			if force_game_material:
				_apply_dollar_material_to_tree(tmp)

	if cs != null:
		var mult_col: float = maxf(0.01, size_multiplier)
		var cyl := CylinderShape3D.new()
		cyl.height = _CoinHeight * mult_col
		cyl.radius = _CoinRadius * mult_col
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

	# 必須先碰到任何物體（桌面/硬幣/牆），才允許結算；避免空中「慢速 → 入睡」誤觸發 +1000
	if get_contact_count() > 0:
		_has_touched = true
	if not _has_touched:
		_still_time = 0.0
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
