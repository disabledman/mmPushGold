extends Node

## 全域遊戲管理單例
## 提供遊戲常數與共用狀態

static var Instance: Node = null

const InitialCoins := 100
const UpperLayerCycleSeconds := 4.0
const LogoDisplaySeconds := 2.0
const GameOverDelaySeconds := 5.0


func _ready() -> void:
	Instance = self


func _exit_tree() -> void:
	Instance = null
