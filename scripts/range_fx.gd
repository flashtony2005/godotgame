extends Node3D
## Terrain-conforming glowing tower range & hover pad indicator (enhanced from original range_fx.gd).
## Samples world.height_at(x, z) so every arc, dash, dead-zone ring, and rally wedge hugs hills & valleys!

const COL := {
	"archer": Color("ffd27a"),
	"bombard": Color("ff9a4a"),
	"spire": Color("8fe0ff"),
	"guard": Color("a8e08a"),
	"pad": Color("f6c86a"),
}

var kind := ""
var radius := 6.0
var min_r := 0.0
var mat: StandardMaterial3D
var mi_edge: MeshInstance3D
var mi_spin: MeshInstance3D
var mi_fill: MeshInstance3D
var _t := 0.0
var _pulse := 1.0
var _height_fn: Callable = Callable()
var _last_pos := Vector3(9999, 0, 9999)


func _ready() -> void:
	visible = false
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.material_override = mat
		mi.name = ["fill", "edge", "spin"][i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		match i:
			0: mi_fill = mi
			1: mi_edge = mi
			_: mi_spin = mi


func set_height_fn(fn: Callable) -> void:
	_height_fn = fn


func show_range(p_kind: String, p_radius: float, p_min: float, pos_xz: Vector3, alpha: float = 1.0) -> void:
	var moved := pos_xz.distance_squared_to(_last_pos) > 0.01
	var need := (p_kind != kind or absf(p_radius - radius) > 0.01 or absf(p_min - min_r) > 0.01 or moved)
	position = Vector3(pos_xz.x, 0.0, pos_xz.z)
	_last_pos = pos_xz
	kind = p_kind
	radius = p_radius
	min_r = p_min
	if need:
		_build()
	visible = true
	_pulse = alpha
	if mat != null:
		mat.albedo_color = Color(1, 1, 1, alpha)


func hide_range() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if mi_spin != null:
		mi_spin.rotation.y = 0.0 if kind == "guard" else _t * (2.2 if kind == "spire" else 0.45)
	if mat != null:
		var glow_a := _pulse * (0.88 + 0.12 * sin(_t * 3.0))
		mat.albedo_color = Color(1, 1, 1, glow_a)


func _pt(lx: float, lz: float, lift: float = 0.12) -> Vector3:
	var wy := lift
	if _height_fn.is_valid():
		wy = float(_height_fn.call(position.x + lx, position.z + lz)) + lift
	return Vector3(lx, wy, lz)


func _mk_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


func _quad_xz(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, lift: float = 0.12) -> void:
	var va := _pt(a.x, a.y, lift)
	var vb := _pt(b.x, b.y, lift)
	var vc := _pt(c.x, c.y, lift)
	var vd := _pt(d.x, d.y, lift)
	_tri(st, va, vb, vc, col)
	_tri(st, va, vc, vd, col)


func _arc(st: SurfaceTool, r: float, w: float, a0: float, a1: float, col: Color, flat_y: bool = false) -> void:
	var seg := maxi(3, int(absf(a1 - a0) * maxf(2.0, r) * 2.2))
	var base_y := float(_height_fn.call(position.x, position.z)) + 0.16 if (flat_y and _height_fn.is_valid()) else 0.14
	for i in seg:
		var an0 := lerpf(a0, a1, float(i) / float(seg))
		var an1 := lerpf(a0, a1, float(i + 1) / float(seg))
		var d0 := Vector2(cos(an0), sin(an0))
		var d1 := Vector2(cos(an1), sin(an1))
		if flat_y:
			var va := Vector3(d0.x * (r - w), base_y, d0.y * (r - w))
			var vb := Vector3(d1.x * (r - w), base_y, d1.y * (r - w))
			var vc := Vector3(d1.x * (r + w), base_y, d1.y * (r + w))
			var vd := Vector3(d0.x * (r + w), base_y, d0.y * (r + w))
			_tri(st, va, vb, vc, col)
			_tri(st, va, vc, vd, col)
		else:
			_quad_xz(st, d0 * (r - w), d1 * (r - w), d1 * (r + w), d0 * (r + w), col)


func _disc(st: SurfaceTool, r: float, col: Color) -> void:
	var rings := 4
	var seg := 36
	for rk in rings:
		var r0 := r * float(rk) / float(rings)
		var r1 := r * float(rk + 1) / float(rings)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			_quad_xz(st, d0 * r0, d1 * r0, d1 * r1, d0 * r1, col, 0.09)


func _build() -> void:
	var c: Color = COL.get(kind, Color("ffd27a"))
	var fs := _mk_st()
	if kind != "pad":
		_disc(fs, radius, Color(c.r, c.g, c.b, 0.045))
	mi_fill.mesh = fs.commit()

	var es := _mk_st()
	var ss := _mk_st()
	match kind:
		"archer":
			_arc(es, radius, 0.055, 0.0, TAU, Color(c.r, c.g, c.b, 0.90))
			_arc(es, radius + 0.14, 0.018, 0.0, TAU, Color(c.r, c.g, c.b, 0.42))
			for k in 8:
				var a := TAU * float(k) / 8.0 + 0.2
				var d := Vector2(cos(a), sin(a))
				var side := Vector2(-sin(a), cos(a))
				_quad_xz(es, d * (radius + 0.02) + side * 0.035, d * (radius + 0.36) + side * 0.008, d * (radius + 0.36) - side * 0.008, d * (radius + 0.02) - side * 0.035, Color(c.r, c.g, c.b, 0.78))
		"bombard":
			var n := 20
			for k in n:
				var a0 := TAU * float(k) / float(n)
				_arc(es, radius, 0.08, a0, a0 + TAU / float(n) * 0.62, Color(c.r, c.g, c.b, 0.92))
			if min_r > 0.2:
				for k in 12:
					var a0 := TAU * float(k) / 12.0 + 0.1
					_arc(es, min_r, 0.04, a0, a0 + TAU / 12.0 * 0.5, Color(c.r, c.g, c.b, 0.62))
		"spire":
			_arc(es, radius, 0.04, 0.0, TAU, Color(c.r, c.g, c.b, 0.85))
			_arc(es, radius * 0.55, 0.022, 0.0, TAU, Color(c.r, c.g, c.b, 0.38))
			for k in 16:
				var a0 := TAU * float(k) / 16.0
				_arc(ss, radius + 0.18, 0.025, a0, a0 + TAU / 16.0 * 0.55, Color(c.r, c.g, c.b, 0.72), true)
		"guard":
			for k in 28:
				var a0 := TAU * float(k) / 28.0
				_arc(es, radius, 0.048, a0, a0 + TAU / 28.0 * 0.45, Color(c.r, c.g, c.b, 0.86))
			_arc(es, 1.35, 0.035, 0.0, TAU, Color(c.r, c.g, c.b, 0.55))
		"pad":
			_arc(es, radius, 0.07, 0.0, TAU, Color(c.r, c.g, c.b, 0.95))
			_arc(ss, radius + 0.18, 0.03, 0.0, TAU * 0.22, Color(c.r, c.g, c.b, 0.8), true)
			_arc(ss, radius + 0.18, 0.03, PI, PI + TAU * 0.22, Color(c.r, c.g, c.b, 0.8), true)
		_:
			_arc(es, radius, 0.05, 0.0, TAU, Color(c.r, c.g, c.b, 0.85))

	mi_edge.mesh = es.commit()
	mi_spin.mesh = ss.commit()
