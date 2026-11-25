extends Node3D

## 射程预览圈：贴地画环，四种塔四种画法。
## 弓手=细实线 + 外圈 + 8 根刻度；臼炮=粗虚线 + 内侧「最小射程」死区 + 炮弹珠
## 雷塔=细线 + 一圈会转的电弧刻度 + 4 道折线；哨所=短虚线 + 4 个步兵站位楔形

const COL := {
	"archer": Color("ffd27a"),
	"bombard": Color("ff9a4a"),
	"spire": Color("8fe0ff"),
	"guard": Color("a8e08a"),
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
		add_child(mi)
		match i:
			0: mi_fill = mi
			1: mi_edge = mi
			_: mi_spin = mi

# ---------------------------------------------------------------- 对外

func show_range(p_kind: String, p_radius: float, p_min: float, pos_xz: Vector3, alpha := 1.0) -> void:
	position = pos_xz
	var need := (p_kind != kind or absf(p_radius - radius) > 0.01 or absf(p_min - min_r) > 0.01)
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

func update_alpha(a: float) -> void:
	_pulse = a
	if mat != null:
		mat.albedo_color = Color(1, 1, 1, a)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var c: Color = COL.get(kind, Color("ffd27a"))
	var pulse := 1.0 + 0.035 * sin(_t * 3.2)
	if mi_fill != null:
		mi_fill.scale = Vector3(pulse, 1.0, pulse)
	if mi_spin != null:
		mi_spin.rotation.y = _t * (2.2 if kind == "spire" else 0.35)
	if mat != null:
		var glow_a := _pulse * (0.9 + 0.1 * sin(_t * 2.6))
		mat.albedo_color = Color(1, 1, 1, glow_a)
	# 哨所的站桩点轻微呼吸
	if kind == "guard" and mi_spin != null:
		mi_spin.rotation.y = 0.0

# ---------------------------------------------------------------- 画

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

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)

func _arc(st: SurfaceTool, r: float, w: float, a0: float, a1: float, col: Color) -> void:
	var seg := maxi(3, int(absf(a1 - a0) * maxf(2.0, r) * 2.2))
	for i in seg:
		var u0 := float(i) / float(seg)
		var u1 := float(i + 1) / float(seg)
		var an0 := lerpf(a0, a1, u0)
		var an1 := lerpf(a0, a1, u1)
		var d0 := Vector3(cos(an0), 0, sin(an0))
		var d1 := Vector3(cos(an1), 0, sin(an1))
		_quad(st, d0 * (r - w), d1 * (r - w), d1 * (r + w), d0 * (r + w), col)

func _disc(st: SurfaceTool, r: float, col: Color) -> void:
	var seg := 44
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		_tri(st, Vector3.ZERO, Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3(cos(a1) * r, 0, sin(a1) * r), col)

func _bead(st: SurfaceTool, at: Vector3, r: float, col: Color) -> void:
	var seg := 8
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := at + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := at + Vector3(cos(a1) * r, 0, sin(a1) * r)
		_tri(st, at, p0, p1, col)

func _build() -> void:
	var c: Color = COL.get(kind, Color("ffd27a"))
	# 底色盘：中心浅、边缘几乎透明（用两层叠出柔和的填充）
	var fs := _mk_st()
	_disc(fs, radius, Color(c.r, c.g, c.b, 0.035))
	_disc(fs, radius * 0.72, Color(c.r, c.g, c.b, 0.018))
	mi_fill.mesh = fs.commit()

	var es := _mk_st()
	var ss := _mk_st()
	match kind:
		"archer":
			_arc(es, radius, 0.045, 0.0, TAU, Color(c.r, c.g, c.b, 0.85))
			_arc(es, radius + 0.12, 0.014, 0.0, TAU, Color(c.r, c.g, c.b, 0.35))
			for k in 8:
				var a := TAU * float(k) / 8.0 + 0.2
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-sin(a), 0, cos(a))
				_quad(es, d * (radius + 0.02) + side * 0.03, d * (radius + 0.32) + side * 0.005,
					d * (radius + 0.32) - side * 0.005, d * (radius + 0.02) - side * 0.03, Color(c.r, c.g, c.b, 0.7))
		"bombard":
			# 粗虚线
			var n := 20
			for k in n:
				var a0 := TAU * float(k) / float(n)
				_arc(es, radius, 0.075, a0, a0 + TAU / float(n) * 0.62, Color(c.r, c.g, c.b, 0.9))
			# 最小射程死区
			var nm := 12
			for k in nm:
				var a0 := TAU * float(k) / float(nm) + 0.1
				_arc(es, min_r, 0.035, a0, a0 + TAU / float(nm) * 0.5, Color(c.r, c.g, c.b, 0.55))
			# 炮弹珠 + 溅射半径暗示
			for k in 8:
				var a := TAU * float(k) / 8.0
				_bead(es, Vector3(cos(a) * radius, 0, sin(a) * radius), 0.09, Color(c.r, c.g, c.b, 0.75))
			_arc(es, radius * 0.42, 0.02, 0.0, TAU, Color(c.r, c.g, c.b, 0.22))
		"spire":
			_arc(es, radius, 0.03, 0.0, TAU, Color(c.r, c.g, c.b, 0.75))
			_arc(es, radius * 0.55, 0.018, 0.0, TAU, Color(c.r, c.g, c.b, 0.3))
			# 4 道折线
			for k in 4:
				var a := TAU * float(k) / 4.0 + 0.4
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-sin(a), 0, cos(a))
				for j in 3:
					var r0 := radius * (0.55 + 0.15 * float(j))
					var r1 := r0 + radius * 0.1
					var off0: float = 0.09 * (1.0 if j % 2 == 0 else -1.0)
					var off1: float = -off0
					_quad(es, d * r0 + side * off0, d * r1 + side * off1, d * r1 + side * (off1 + 0.03),
						d * r0 + side * (off0 + 0.03), Color(c.r, c.g, c.b, 0.75))
			# 旋转的电弧刻度
			for k in 16:
				var a0 := TAU * float(k) / 16.0
				_arc(ss, radius + 0.16, 0.02, a0, a0 + TAU / 16.0 * 0.55, Color(c.r, c.g, c.b, 0.6))
		"guard":
			var n2 := 28
			for k in n2:
				var a0 := TAU * float(k) / float(n2)
				_arc(es, radius, 0.04, a0, a0 + TAU / float(n2) * 0.45, Color(c.r, c.g, c.b, 0.8))
			_arc(es, 1.15, 0.03, 0.0, TAU, Color(c.r, c.g, c.b, 0.45))
			# 4 个站位楔形（步兵会散出去的方向）
			for k in 4:
				var a2 := TAU * float(k) / 4.0 + PI * 0.25
				var d2 := Vector3(cos(a2), 0, sin(a2))
				var side2 := Vector3(-sin(a2), 0, cos(a2))
				_quad(ss, d2 * 1.15 + side2 * 0.16, d2 * 1.55 + side2 * 0.02,
					d2 * 1.55 - side2 * 0.02, d2 * 1.15 - side2 * 0.16, Color(c.r, c.g, c.b, 0.7))
				_bead(ss, d2 * (radius - 0.35), 0.06, Color(c.r, c.g, c.b, 0.6))
		_:
			_arc(es, radius, 0.04, 0.0, TAU, Color(c.r, c.g, c.b, 0.8))
	mi_edge.mesh = es.commit()
	mi_spin.mesh = ss.commit()
