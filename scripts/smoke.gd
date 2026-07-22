extends AnimatedSprite2D

## 烟雾特效 —— 播放一次完整动画后自动销毁
## 挂在 smoke_effect.tscn 的 AnimatedSprite2D 根节点上

func _ready() -> void:
	# 1. 确保烟雾一出生，立刻强制播放名叫 "smoke effects" 的动画
	play("smoke")

	# 2. 连接信号：动画播放完毕 → 自动销毁自己
	animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	# 动画放完这 7 帧，立刻自我毁灭，不占用内存
	queue_free()