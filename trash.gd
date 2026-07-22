extends Area2D

## 可拾取垃圾 —— 玩家走进范围后自动拾取
## 挂在 trash.tscn 的根节点 Area2D 上

# 拾取后给予的经验值
@export var xp_value: int = 10

# 拾取后的漂浮动画（视觉反馈）
@export var float_height: float = 8.0
@export var float_speed: float = 3.0

var _floating: bool = false
var _start_y: float


func _ready() -> void:
	# 连接 body_entered 信号 —— 任何 PhysicsBody 进入都会触发
	body_entered.connect(_on_body_entered)

	# 记录初始 Y 坐标，用于后续的上下浮动效果
	_start_y = position.y

	# 初始随机偏移，避免所有垃圾同步浮动
	_start_y += randf_range(-float_height, float_height)


func _process(delta: float) -> void:
	# 简单的上下浮动动画，让垃圾看起来更生动
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_height


func _on_body_entered(body: Node2D) -> void:
	# 只有 Player 能拾取（通过 group 判断）
	if not body.is_in_group("player"):
		return

	# 调用 Player 的加经验方法
	if body.has_method("add_xp"):
		body.add_xp(xp_value)

	# 播放拾取特效（可选，后续扩展）
	_on_pickup_effect()

	# 销毁自己
	queue_free()


func _on_pickup_effect() -> void:
	# TODO: 后续可在此添加粒子特效、音效等
	# 目前先用一个快速的缩放消失效果作为占位
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.08)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
