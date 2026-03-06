extends RigidBody3D

## 金幣剛體
## 扁平圓柱，用於物理推擠與掉落

const CoinRadius := 0.15
const CoinHeight := 0.06  # 扁平圓柱
const Diameter := CoinRadius * 2


func _ready() -> void:
	lock_rotation = false
	gravity_scale = 1.0
	collision_layer = 1  # coins layer
	collision_mask = 0xFFFFFFFF  # collide with everything
