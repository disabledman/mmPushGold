extends Area3D

## 掉幣區
## 金幣進入時觸發 coin_caught 訊號（不需要移動接幣）

## 金幣被接住時發出，參數為 Coin 節點
signal coin_caught(coin: Node3D)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 2  # catch_zone
	collision_mask = 1   # coins


func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D:
		# 檢查是否為 Coin（RigidBody3D 且使用 Coin 腳本）
		coin_caught.emit(body)
