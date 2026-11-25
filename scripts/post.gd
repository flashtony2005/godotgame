extends CanvasLayer
## Post-processing layer (layer 1, below HUD layer 10): diorama tilt-shift, biome grading, fade, grain, vignette.

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


func set_grade(sat: float, con: float, tint_c: Color, fade_v: float = 1.0) -> void:
	if mat != null:
		mat.set_shader_parameter("saturation", sat)
		mat.set_shader_parameter("contrast", con)
		mat.set_shader_parameter("tint", Vector3(tint_c.r, tint_c.g, tint_c.b))
		mat.set_shader_parameter("fade", fade_v)


func set_strength(v: float) -> void:
	if mat != null:
		mat.set_shader_parameter("blur_strength", v)
