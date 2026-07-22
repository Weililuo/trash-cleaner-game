extends CharacterBody2D

## 玩家角色 —— 8 方向移动 + 经验值系统 + 高速移动烟雾特效
## 挂在 main.tscn 的 Player (CharacterBody2D) 节点上

# ---- 移动参数 ----
@export var move_speed: float = 1650.0
@export var acceleration: float = 2000.0 # 加速度（越大越灵敏）
@export var friction: float = 1100.0 # 摩擦力（越大停得越快）

# ---- 移动冻结（Game Over 时序控制） ----
var is_movement_frozen: bool = false

# ---- 烟雾特效 ----
@export var smoke_scene: PackedScene # 在编辑器里拖入 SmokeEffect.tscn
@export var smoke_interval: float = 0.23 # 每 0.23 秒释放一个烟雾
@export var smoke_speed_threshold: float = 0.82 # 速度达到最大速度的 82% 时触发
@export var smoke_offset: Vector2 = Vector2(0, 17) # 烟雾生成偏移（脚底位置）

var _smoke_timer: float = 0.0 # 烟雾生成计时器

# ---- 属性 ----
@export var xp: int = 0:
	set(value):
		xp = value
		xp_changed.emit(xp)
@export var level: int = 1

# ---- 信号 ----
signal xp_changed(new_xp: int)
signal leveled_up(new_level: int)


func _ready() -> void:
	z_index = 2
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_smoke(delta)
	_handle_animation()


func _handle_movement(delta: float) -> void:
	# Game Over 冻结：玩家无法移动
	if is_movement_frozen:
		return

	# 获取输入方向（WASD / 方向键 / 手柄左摇杆）
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# 计算目标速度
	var target_velocity: Vector2 = input_dir * move_speed

	# 平滑加速/减速（move_toward 实现手感舒适的惯性效果）
	velocity = velocity.move_toward(target_velocity, acceleration * delta)

	# 如果输入为零，额外施加摩擦力让角色快速停稳
	if input_dir == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	# ---- 屏幕边界限制逻辑 ----
	var screen_size: Vector2 = get_viewport_rect().size
	var margin: float = -40.0
	position.x = clamp(position.x, margin, screen_size.x - margin)
	position.y = clamp(position.y, margin, screen_size.y - margin)


func _handle_smoke(delta: float) -> void:
	# 没有赋值烟雾场景就不执行
	if smoke_scene == null:
		return

	# 计算当前速度占最大速度的比例
	var speed_ratio: float = velocity.length() / move_speed

	# 速度不达标，不生成烟雾，并且重置计时器（避免松开方向键后立刻喷一口）
	if speed_ratio < smoke_speed_threshold:
		_smoke_timer = 0.0
		return

	# 累计计时器
	_smoke_timer += delta

	# 每满 smoke_interval 秒，释放一个烟雾
	if _smoke_timer >= smoke_interval:
		_smoke_timer -= smoke_interval # 用减法而非清零，避免累积误差
		_spawn_smoke()


## 在玩家脚底位置实例化一个烟雾特效
func _spawn_smoke() -> void:
	var smoke: AnimatedSprite2D = smoke_scene.instantiate()

	# 坐标：玩家脚底
	smoke.position = position + smoke_offset

	# 强制置顶显示，绝不被地板或其他物体遮挡
	smoke.z_index = 5

	# 强制可见（双保险，配合 smoke_effect.gd 里的 _ready 设置）
	smoke.visible = true

	# 添加到主场景根节点
	get_tree().current_scene.add_child(smoke)


func _handle_animation() -> void:
	# 根据移动方向翻转精灵（简单的左右朝向）
	var sprite: Sprite2D = $Sprite2D as Sprite2D
	if sprite == null:
		return

	if velocity.x > 10.0:
		sprite.flip_h = false
	elif velocity.x < -10.0:
		sprite.flip_h = true


# ---- 经验值系统 ----

func add_xp(amount: int) -> void:
	xp += amount
	_check_level_up()


func _check_level_up() -> void:
	var xp_needed: int = _xp_for_next_level()
	while xp >= xp_needed:
		xp -= xp_needed
		level += 1
		leveled_up.emit(level)
		xp_needed = _xp_for_next_level()


func _xp_for_next_level() -> int:
	# 每级所需经验：10 + level * 5（可自行调整公式）
	return 10 + level * 5
