extends Node

## 垃圾生成器 v7 —— 动态难度 + 间隔加速 + 结算通知
## 挂在 main.tscn 的 TrashSpawner 节点上
##
## 核心逻辑：
##   1. 垃圾超标 → 立刻实例化 GameOverPanel（时序完全由面板接管）
##   2. 从 ~60s 开始，生成间隔从 1.8s 线性加速到 0.8s
##   3. 多发连爆概率随时间线性增长

# ---- 基础生成配置 ----
@export var trash_scene: PackedScene              # 把 trash.tscn 拖入这里
@export var spawn_margin: float = 60.0            # 屏幕边缘安全边距（像素）
@export var safe_radius: float = 150.0            # 避开玩家的最小距离

# ---- 生成间隔加速 ----
@export var spawn_interval_start: float = 1.8     # 初始生成间隔（秒）
@export var spawn_interval_min: float = 0.8       # 最快生成间隔（秒），到达后不再加快
@export var interval_ramp_start: float = 60.0     # 几秒后开始加速
@export var interval_ramp_duration: float = 60.0  # 加速持续多久后触底

# ---- 游戏结束条件 ----
@export var max_trash_allowed: int = 50           # 地图上最多允许同时存在的垃圾数

# ---- 动态难度曲线（多发概率） ----
@export var difficulty_ramp_duration: float = 120.0   # 多发概率达到顶峰的时间（秒）

# ---- 结算面板 ----
@export var game_over_panel_scene: PackedScene    # 把 GameOverPanel.tscn 拖入这里

# ---- 内部状态 ----
@onready var _timer: Timer = $Timer
var _game_time: float = 0.0
var _game_ended: bool = false


func _ready() -> void:
	_timer.wait_time = spawn_interval_start

	if not _timer.timeout.is_connected(_on_timer_timeout):
		_timer.timeout.connect(_on_timer_timeout)

	_spawn_trash()


func _process(delta: float) -> void:
	if _game_ended:
		return

	_game_time += delta

	# ---- 生成间隔加速：每帧动态更新 Timer ----
	var interval_ramp: float = clamp(
		(_game_time - interval_ramp_start) / interval_ramp_duration,
		0.0,
		1.0
	)
	_timer.wait_time = lerp(spawn_interval_start, spawn_interval_min, interval_ramp)

	# ---- 实时监控垃圾数量 ----
	var alive_count: int = get_tree().get_nodes_in_group("trash").size()

	if alive_count >= max_trash_allowed:
		_trigger_game_over(alive_count)


## ============================================================
##   游戏结束触发 —— 仅负责停表 + 实例化面板
##   所有时序（死寂 / 黑屏 / 悬停 / 暴扣 / 回弹 / 暂停）
##   全部由 game_over_panel.gd 内部统一接管。
## ============================================================
func _trigger_game_over(trash_count: int) -> void:
	_game_ended = true
	_timer.stop()

	print("══════════════════════════════════")
	print("【游戏结束】垃圾超标！")
	print("   当前垃圾数：", trash_count, " / 上限：", max_trash_allowed)
	print("   存活时间：", "%.1f" % _game_time, " 秒")
	print("   → 实例化 GameOverPanel，时序由面板接管")
	print("══════════════════════════════════")

	if game_over_panel_scene == null:
		push_error("trash_spawner: game_over_panel_scene 未赋值！请在编辑器里拖入 GameOverPanel.tscn")
		get_tree().paused = true   # 保底回退
		return

	var panel: CanvasLayer = game_over_panel_scene.instantiate()
	panel.set("final_time", _game_time)
	panel.set("final_trash_count", trash_count)
	get_tree().current_scene.add_child(panel)
	# game_over_panel.gd._ready() 接管一切：
	#   死寂 0.4s → 瞬间黑屏 → 悬停 0.15s → 暴扣 0.25s → SFX + 震屏 + 回弹 → 暂停


# ---- 定时器触发 ----

func _on_timer_timeout() -> void:
	_spawn_trash()


# ---- 生成入口：摇骰子决定 1 / 2 / 3 连爆 ----

func _spawn_trash() -> void:
	if trash_scene == null:
		return

	if _game_ended:
		return

	var difficulty: float = clamp(_game_time / difficulty_ramp_duration, 0.0, 1.0)

	var double_chance: float = lerp(0.05, 0.50, difficulty)
	var triple_chance: float = lerp(0.00, 0.25, difficulty)

	var roll: float = randf()
	var count: int = 1

	if roll < triple_chance:
		count = 3
	elif roll < triple_chance + double_chance:
		count = 2

	for i in range(count):
		_spawn_single_trash()

	if count >= 2:
		print("🔥 连爆 x", count,
			" | 间隔: ", "%.2f" % _timer.wait_time, "s",
			" | 时间: ", "%.1f" % _game_time, "s")


# ---- 单个垃圾生成（含避开玩家算法） ----

func _spawn_single_trash() -> void:
	var trash: Area2D = trash_scene.instantiate()
	if trash == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var min_x: float = spawn_margin
	var max_x: float = viewport_size.x - spawn_margin
	var min_y: float = spawn_margin
	var max_y: float = viewport_size.y - spawn_margin

	if max_x < min_x:
		min_x = 0.0
		max_x = viewport_size.x
	if max_y < min_y:
		min_y = 0.0
		max_y = viewport_size.y

	var spawn_pos: Vector2 = _find_safe_position(min_x, max_x, min_y, max_y)

	trash.position = spawn_pos
	get_tree().current_scene.add_child(trash)
	trash.add_to_group("trash")


func _find_safe_position(min_x: float, max_x: float, min_y: float, max_y: float) -> Vector2:
	var player = get_tree().get_first_node_in_group("player")

	if player == null:
		return Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))

	var attempts: int = 0
	while attempts < 15:
		var candidate: Vector2 = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)
		if candidate.distance_to(player.position) > safe_radius:
			return candidate
		attempts += 1

	return Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
