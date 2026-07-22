extends AnimatedSprite2D

## 烟雾特效 —— 防秒杀加固版
## 挂在 SmokeEffect.tscn 的 AnimatedSprite2D 根节点上

# 你的 SpriteFrames 里的动画叫什么名字？在这里改一次即可
@export var anim_name: String = "smoke"


func _ready() -> void:
	# ---- 第 0 步：强制可见性和层级（双保险） ----
	visible = true
	z_index = 5
	modulate.a = 1.0

	# ---- 第 1 步：立刻停掉一切，强制归零帧 ----
	stop()
	frame = 0

	# ---- 第 2 步：延迟到下一空闲帧再真正启动 ----
	# call_deferred 确保本节点的 _ready() 和场景树初始化全部跑完
	call_deferred("_safe_start")


## 延迟安全启动 —— 先连信号，再播动画
func _safe_start() -> void:
	# 安全检查：SpriteFrames 资源是否已被释放
	if sprite_frames == null:
		queue_free()
		return

	# 安全检查：指定动画是否存在
	if not sprite_frames.has_animation(anim_name):
		push_error("smoke_effect: SpriteFrames 中没有名为 '" + anim_name + "' 的动画！请检查名字是否一致。")
		queue_free()
		return

	# 二次保险：再次归零
	frame = 0

	# 确保动画不会循环（只播一次）
	sprite_frames.set_animation_loop(anim_name, false)

	# 先连接信号，再播放 —— 这是关键顺序
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)

	# 开播
	play(anim_name)


func _on_animation_finished() -> void:
	queue_free()
