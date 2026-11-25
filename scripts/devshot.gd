extends Node
## 调试辅助：等待若干帧后截取当前视口并存为 PNG，然后退出。
## 由 game.gd 在命令行出现 `--shot=<绝对路径>:<帧数>` 时挂载。

var out_path := ""
var frames := 480
var time_scale := 2.0
var _n := 0


func _ready() -> void:
	Engine.time_scale = time_scale
	process_priority = 1000


func _process(_delta: float) -> void:
	_n += 1
	if _n < frames:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("[shot] ", out_path, " ", img.get_size(), " err=", err)
	get_tree().quit()
