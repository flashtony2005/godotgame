extends Node3D
## 2-layer 2600-particle GPU instanced weather system (ported from 41-weather.js).

const U = preload("res://scripts/util.gd")

const COUNT := 2600

var mm_node: MultiMeshInstance3D
var mat: ShaderMaterial
var fade := 1.0
var target_fade := 1.0


func _ready() -> void:
	setup()


func setup() -> void:
	if mm_node != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]
	st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
	st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	var quad_mesh := st.commit()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad_mesh
	mm.instance_count = COUNT
	mm.visible_instance_count = COUNT

	var rng := U.make_rng(4242)
	for i in COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.next_f(), rng.next_f(), rng.next_f(), (float(i) + 0.5) / float(COUNT)))

	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/weather.gdshader")

	mm_node = MultiMeshInstance3D.new()
	mm_node.name = "Weather"
	mm_node.multimesh = mm
	mm_node.material_override = mat
	mm_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm_node.extra_cull_margin = 60.0
	add_child(mm_node)


func apply_biome(bio: Dictionary, instant: bool = false) -> void:
	if mat == null:
		return
	var w: Dictionary = bio["weather"]
	mat.set_shader_parameter("u_n", w["n"])
	mat.set_shader_parameter("u_vel_a", w["velA"])
	mat.set_shader_parameter("u_vel_b", w["velB"])
	mat.set_shader_parameter("u_sway_a", w["swayA"])
	mat.set_shader_parameter("u_sway_b", w["swayB"])
	mat.set_shader_parameter("u_size_a", w["sizeA"])
	mat.set_shader_parameter("u_size_b", w["sizeB"])
	mat.set_shader_parameter("u_col_a", w["colA"])
	mat.set_shader_parameter("u_col_b", w["colB"])
	mat.set_shader_parameter("u_al_a", w["alA"])
	mat.set_shader_parameter("u_al_b", w["alB"])
	mat.set_shader_parameter("u_y_a", w["yA"])
	mat.set_shader_parameter("u_y_b", w["yB"])
	var hs: Color = bio["hemi_s"]
	mat.set_shader_parameter("u_amb", Vector3(hs.r * 0.45, hs.g * 0.45, hs.b * 0.45))
	if instant:
		fade = 1.0
	else:
		fade = 0.0
	target_fade = 1.0
	mat.set_shader_parameter("u_fade", fade)


func step(dt: float, t: float, light_pos: PackedVector3Array, light_col: PackedVector3Array) -> void:
	if mat == null:
		return
	fade = U.damp(fade, target_fade, 1.8, dt)
	mat.set_shader_parameter("u_time", t)
	mat.set_shader_parameter("u_fade", fade)
	mat.set_shader_parameter("u_light_pos", light_pos)
	mat.set_shader_parameter("u_light_col", light_col)
