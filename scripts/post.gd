extends CanvasLayer

## 后处理层：挂在 layer 1（低于 HUD 的 layer 10），整屏叠一层移轴 / 抖动 / 颗粒 / 暗角。

var rect: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	layer = 1
	var sh: Shader = load("res://shaders/post.gdshader")
	mat = ShaderMaterial.new()
	if sh != null:
		mat.shader = sh
	rect = ColorRect.new()
	rect.name = "post_rect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)

func set_tint(c: Color) -> void:
	if mat != null:
		mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))

func set_strength(v: float) -> void:
	if mat != null:
		mat.set_shader_parameter("blur_strength", v)
