extends AudioStreamPlayer

## BGM 背景音乐管理器
## 挂在 main.tscn 的 BGM (AudioStreamPlayer) 节点上
##
## 使用方式（在其他脚本中）：
##   var bgm := get_tree().get_first_node_in_group("bgm") as BgmPlayer
##   bgm.fade_to(new_stream, 1.5)   # 1.5 秒交叉淡入到新曲
##   bgm.set_volume_linear(0.5)     # 降到 50% 音量


func _ready() -> void:
	add_to_group("bgm")

	# 🎧 核心修改：游戏一启动，自动把音乐初始音量降低到 30%！
	# 你可以自由修改这里的 0.3 (30%)。比如觉得还吵就改 0.15，觉得小了就改 0.5
	my_set_volume_linear(0.3)
	
	# 如果编辑器里已经在 Stream 属性里拖入了音频文件
	# 且勾选了 Autoplay，下面这行不会重复播放
	if stream != null and not playing:
		play()


# ---- 基础控制 ----

## 播放（如果传了 stream 参数就顺便切换曲子）
func play_bgm(new_stream: AudioStream = null) -> void:
	if new_stream != null:
		stream = new_stream
	if stream != null:
		play()


## 停止
func stop_bgm() -> void:
	stop()


## 暂停（保留播放位置）
func pause_bgm() -> void:
	stream_paused = true


## 恢复
func resume_bgm() -> void:
	stream_paused = false


# ---- 音量控制 ----

## 设置线性音量 (0.0 = 静音, 1.0 = 原始音量)
func my_set_volume_linear(vol: float) -> void:
	volume_db = linear_to_db(clamp(vol, 0.0, 1.0))

## 设置分贝音量 (-80.0 = 静音, 0.0 = 原始音量)
func my_set_volume_db(db: float) -> void:
	volume_db = clamp(db, -80.0, 0.0)


# ---- 高级：淡入淡出 + 切歌 ----

## 在 duration 秒内把音量从当前平滑过渡到目标值
func fade_volume_to(target_linear: float, duration: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		my_set_volume_linear, # 👈 ⚠️ 注意：这里也要改成新的函数名
		db_to_linear(volume_db), # 起点：当前实际音量
		clamp(target_linear, 0.0, 1.0), # 终点
		duration
	)


## 淡出 → 切歌 → 淡入
func fade_to(new_stream: AudioStream, duration: float = 1.0) -> void:
	if new_stream == null:
		return

	# 淡出
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(set_volume_linear, db_to_linear(volume_db), 0.0, duration * 0.5)

	# 淡出完成后切歌
	tween.tween_callback(_switch_and_fade_in.bind(new_stream, duration * 0.5))


func _switch_and_fade_in(new_stream: AudioStream, fade_duration: float) -> void:
	stream = new_stream
	play()

	# 从 0 淡入
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(set_volume_linear, 0.0, 1.0, fade_duration)
