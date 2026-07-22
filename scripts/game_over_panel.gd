extends CanvasLayer

## Game Over 结算动效 v7 —— 一体化死亡秀 + 音频 Seek 切除空白
##   时序完全在本脚本内闭环：死寂 → 黑屏 → 悬停 → 暴扣 → 回弹 → 冻结
##   挂在 GameOverPanel.tscn 的 CanvasLayer 根节点上
##
## ⚠️ 节点依赖（必须严格遵守命名和类型）：
##   必须有子节点: BackgroundMask (ColorRect)
##   必须有子节点: GameOverImage  (TextureRect)
##   必须有子节点: SFX            (AudioStreamPlayer)
##   三者缺一不可，名字必须一字不差（含大小写和空格）

# ---- 外部数据（由 trash_spawner.gd 注入） ----
var final_time: float = 0.0
var final_trash_count: int = 0

# ---- 动效参数（全部可在检查器中微调） ----
@export var dead_silence_duration: float = 0.15   ## 死寂时长：BGM 停止 + 玩家冻结，画面仍可见（秒）
@export var hover_duration: float = 0.0            ## 黑屏后图片在空中蓄力悬停的时长（秒）
@export var fall_duration: float = 1.2             ## 坠落飞行时长 —— 越短越有打击感（秒）
@export var settle_duration: float = 1.0           ## 撞击后弹性回稳时长（秒）
@export var impact_scale_peak: float = 5.0         ## 撞击瞬间水平拉伸峰值
@export var target_y_offset: float = 0.0           ## Y 轴微调：正=下移，负=上移，0=死死居中
@export var sfx_seek_offset: float = 0.16          ## SFX 起始跳过秒数 —— 切除 WAV 开头静音空白

# ---- 节点引用 ----
@onready var _mask: ColorRect = $BackgroundMask
@onready var _image: TextureRect = $GameOverImage
@onready var _sfx: AudioStreamPlayer = $SFX

# ---- 运行时计算 ----
var _target_y: float = 0.0   ## 图片落点的 Y 坐标（视口半高 + 偏移 - 图片半高）


func _ready() -> void:
	# ============================================================
	#   第 0 步：安全防御性检查
	# ============================================================
	if not _validate_nodes():
		return

	# ============================================================
	#   第 1 步：暴力提升渲染层级
	# ============================================================
	layer = 128

	# ============================================================
	#   第 2 步：【死寂期初始化】遮罩全透明 + 图片隐藏
	#     此时面板已经挂上场景树，但玩家还能看见游戏画面。
	#     遮罩透明 = 不遮挡视野，图片隐藏 = 不剧透死亡动画。
	# ============================================================
	_mask.color = Color(0.0, 0.0, 0.0, 0.0)          # 完全透明
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 死寂期不拦截点击（虽然玩家已冻结）
	_image.visible = false

	# ============================================================
	#   第 3 步：动态计算绝对居中坐标（趁还没黑屏先算好）
	# ============================================================
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_h: float = viewport_size.y
	var viewport_w: float = viewport_size.x

	# pivot_offset 锁死在图片几何中心
	_image.pivot_offset = _image.size * 0.5

	# 终点 Y：视口半高 + 用户偏移 - 图片半高
	_target_y = (viewport_h * 0.5) + target_y_offset - (_image.size.y * 0.5)

	# 终点 X：水平绝对居中
	var target_x: float = (viewport_w - _image.size.x) * 0.5

	# 图片初始姿态
	_image.modulate = Color.WHITE
	_image.rotation = 0.0
	_image.scale = Vector2.ONE
	_image.position = Vector2(target_x, -(_image.size.y * 1.5))

	# ============================================================
	#   第 4 步：【死寂】掐断 BGM + 冻结玩家
	#     在死寂等待之前立刻执行，制造"失控 + 静默"的绝望。
	# ============================================================
	_kill_bgm()
	_freeze_player()

	print("══════════════════════════════════")
	print("   死寂开始 —— BGM 静音，玩家冻结")
	print("   存活时间：", "%.1f" % final_time, " 秒")
	print("   最终垃圾数：", final_trash_count)
	print("══════════════════════════════════")

	# ============================================================
	#   第 5 步：【死寂等待】—— 画面可见但完全无法操作
	#     游戏世界没有变黑！玩家眼睁睁看着垃圾包围自己，
	#     却不能移动、不能操作、BGM 死寂无声。
	# ============================================================
	if dead_silence_duration > 0.0:
		await get_tree().create_timer(dead_silence_duration).timeout

	# ============================================================
	#   第 6 步：【瞬间全黑屏】
	#     死寂结束 → "啪"地拉灯！不渐变，一刀切。
	# ============================================================
	_mask.color = Color(0.0, 0.0, 0.0, 1.0)         # 瞬间不透明
	_mask.mouse_filter = Control.MOUSE_FILTER_STOP    # 现在开始拦截点击
	_image.visible = true                              # 图片在黑屏上方浮现

	# ============================================================
	#   第 7 步：【空中蓄力悬停】→ 暴扣下砸
	#     纯黑废土中，图片悬停 hover_duration 秒，
	#     然后裹挟重力加速度砸向屏幕正中央！
	# ============================================================
	if hover_duration > 0.0:
		await get_tree().create_timer(hover_duration).timeout
	_play_fall_phase()


## ============================================================
##   安全防御：逐节点验证是否缺失或类型不对
## ============================================================
func _validate_nodes() -> bool:
	var ok: bool = true

	if _mask == null:
		push_error("""
❌【GameOverPanel 崩溃拦截】未找到 BackgroundMask 节点！

请按以下步骤排查：
  1. 打开 GameOverPanel.tscn 场景
  2. 在场景树中右键点击 GameOverPanel 根节点 → 添加子节点
  3. 搜索 "ColorRect" → 点击创建
  4. 将新节点【重命名】为 BackgroundMask（注意大小写、无空格）
  5. 选中 BackgroundMask → Layout → Anchors Preset → 选择【Full Rect】
  6. Color 属性设为纯黑色 #000000
  7. 保存场景，重新运行
""")
		ok = false

	if _image == null:
		push_error("""
❌【GameOverPanel 崩溃拦截】未找到 GameOverImage 节点！

请按以下步骤排查：
  1. 打开 GameOverPanel.tscn 场景
  2. 确认是否存在名为 GameOverImage 的 TextureRect 子节点
  3. 如果不存在：右键根节点 → 添加子节点 → 搜索 "TextureRect" → 重命名为 GameOverImage
  4. 检查名称是否一字不差（G、O、I 大写，无空格）
  5. 保存场景，重新运行
""")
		ok = false

	if _sfx == null:
		push_error("""
❌【GameOverPanel 崩溃拦截】未找到 SFX 节点！

请按以下步骤排查：
  1. 打开 GameOverPanel.tscn 场景
  2. 右键根节点 → 添加子节点 → 搜索 "AudioStreamPlayer" → 重命名为 SFX
  3. 在检查器 Stream 属性中拖入你的 GAME OVER Sound.wav
  4. 保存场景，重新运行
""")
		ok = false

	return ok


## ============================================================
##   掐断关卡背景音乐 —— 不淡出，一刀切断
## ============================================================
func _kill_bgm() -> void:
	var bgm := get_tree().get_first_node_in_group("bgm")
	if bgm == null:
		return

	if bgm is AudioStreamPlayer:
		bgm.stop()


## ============================================================
##   冻结玩家操作 —— 通过 player.gd 的 is_movement_frozen 标志位
## ============================================================
func _freeze_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("GameOverPanel: 未找到 'player' 组的节点，跳过冻结")
		return

	player.set("is_movement_frozen", true)


## ============================================================
##   阶段 1：图片从天而降 → 砸向绝对居中位置
##     EXPO + EASE_IN = 模拟重力加速
## ============================================================
func _play_fall_phase() -> void:
	# ---- 图片自由落体 ----
	var tween: Tween = create_tween()

	tween.tween_property(_image, "position:y", _target_y, fall_duration) \
		.set_trans(Tween.TRANS_EXPO) \
		.set_ease(Tween.EASE_IN)

	tween.tween_callback(_on_impact)


## ============================================================
##   撞击时刻：震屏 + 果冻形变 + 垂直弹跳
##     SFX 已在 _play_fall_phase() 中提前播放，
##     此时音频的重音刚好与视觉撞击同步炸裂。
## ============================================================
func _on_impact() -> void:
	# ---- 音效炸裂 ----
	#   play() + seek() 在同一帧内先后执行：
	#   play() 启动音频流 → seek() 瞬间将播放头跳过开头静音空白，
	#   重音在千万分之一秒内喷涌而出，与视觉撞击像素级卡点。
	if _sfx and _sfx.stream:
		_sfx.play()
		_sfx.seek(sfx_seek_offset)

	# ---- 相机疯狂抖动 ----
	_trigger_camera_shake()

	# 确保 pivot 指向图片中心（形变围绕中心发生）
	_image.pivot_offset = _image.size * 0.5

	# ---- 弹跳 + 果冻形变（并行动画） ----
	var settle: Tween = create_tween()
	settle.set_parallel(true)
	settle.set_trans(Tween.TRANS_ELASTIC)
	settle.set_ease(Tween.EASE_OUT)

	# A 通道：垂直弹跳（先略微弹过头，再稳定回目标位置）
	settle.tween_property(_image, "position:y", _target_y + 60.0, 0.08)
	settle.tween_property(_image, "position:y", _target_y, settle_duration)

	# B 通道：果冻物理形变（水平压扁 → 垂直拉长 → 恢复原状）
	settle.tween_property(_image, "scale",
		Vector2(impact_scale_peak, 1.0 / impact_scale_peak), 0.06)
	settle.tween_property(_image, "scale",
		Vector2(1.0 / impact_scale_peak, impact_scale_peak), 0.10)
	settle.tween_property(_image, "scale",
		Vector2.ONE, settle_duration)

	settle.tween_callback(_on_settle_complete)


## ============================================================
##   相机抖动 —— 通过 player 的 Camera2D 偏移模拟震屏
## ============================================================
func _trigger_camera_shake() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var camera: Camera2D = (players[0] as Node2D).get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	var shake: Tween = create_tween()
	shake.set_trans(Tween.TRANS_SINE)
	shake.set_ease(Tween.EASE_IN_OUT)
	shake.tween_property(camera, "offset", Vector2(14, -8), 0.025)
	shake.tween_property(camera, "offset", Vector2(-12, 10), 0.025)
	shake.tween_property(camera, "offset", Vector2(10, -6), 0.025)
	shake.tween_property(camera, "offset", Vector2(-8, 4), 0.025)
	shake.tween_property(camera, "offset", Vector2(4, -2), 0.025)
	shake.tween_property(camera, "offset", Vector2.ZERO, 0.04)


## ============================================================
##   动画平息 → 冷静期 → 冻结世界
## ============================================================
func _on_settle_complete() -> void:
	print("══════════════════════════════════")
	print("        💀  G A M E   O V E R  💀")
	print("  存活时间：", "%.1f" % final_time, " 秒")
	print("  最终垃圾数：", final_trash_count)
	print("══════════════════════════════════")

	await get_tree().create_timer(0.4).timeout
	get_tree().paused = true
