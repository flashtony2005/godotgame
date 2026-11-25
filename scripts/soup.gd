extends RefCounted

## 程序化建模器：把带棱的棱柱、锥、球，连同逐顶点 AO 一起烘进一张顶点色网格。
## 对应原版 10-gfx.js 里的 Soup / S.seg / S.box / S.cyl / S.cone / S.sph 那一套。

var st: SurfaceTool
var vcount := 0
static var _mat: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.86
		m.metallic = 0.02
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_mat = m
	return _mat

func _init() -> void:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

func _v(p: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c.srgb_to_linear())
	st.add_vertex(p)
	vcount += 1

func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	_v(a, n, col)
	_v(b, n, col)
	_v(c, n, col)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	quad4(a, b, c, d, n, col, col, col, col)

func quad4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_v(a, n, ca)
	_v(b, n, cb)
	_v(c, n, cc)
	_v(a, n, ca)
	_v(c, n, cc)
	_v(d, n, cd)

func _mix(c: Color, ao: float) -> Color:
	return Color(c.r * ao, c.g * ao, c.b * ao)

## 轴对齐或任意朝向的方料；AO 从底到顶渐变，模拟接触阴影
func box(center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY, ao_bot := 0.76, ao_top := 1.0) -> void:
	var h := size * 0.5
	var cs: Array[Vector3] = []
	for i in 8:
		var lx := h.x if (i & 1) != 0 else -h.x
		var ly := h.y if (i & 2) != 0 else -h.y
		var lz := h.z if (i & 4) != 0 else -h.z
		cs.append(center + basis * Vector3(lx, ly, lz))
	# 逐角 AO：按 y 高度
	var aos: Array[float] = []
	for i in 8:
		var ly := 1.0 if (i & 2) != 0 else -1.0
		aos.append(lerpf(ao_bot, ao_top, (ly + 1.0) * 0.5))
	var ax := basis.x.normalized()
	var ay := basis.y.normalized()
	var az := basis.z.normalized()
	# +X 面: 1,3,7,5 ; -X: 0,4,6,2 ; +Y: 2,6,7,3 ; -Y: 0,1,5,4 ; +Z: 4,5,7,6 ; -Z: 0,2,3,1
	_face([1, 3, 7, 5], cs, aos, col, ax)
	_face([0, 4, 6, 2], cs, aos, col, -ax)
	_face([2, 6, 7, 3], cs, aos, col, ay)
	_face([0, 1, 5, 4], cs, aos, col, -ay)
	_face([4, 5, 7, 6], cs, aos, col, az)
	_face([0, 2, 3, 1], cs, aos, col, -az)

func _face(idx: Array, cs: Array[Vector3], aos: Array[float], col: Color, n: Vector3) -> void:
	if idx.size() != 4:
		return
	var a := int(idx[0])
	var b := int(idx[1])
	var c := int(idx[2])
	var d := int(idx[3])
	quad4(cs[a], cs[b], cs[c], cs[d], n,
		_mix(col, aos[a]), _mix(col, aos[b]), _mix(col, aos[c]), _mix(col, aos[d]))

## 两点之间的锥柱（木梁、石柱、骨头、炮管都用它），sides=4 就是方料，sides=6/8 是柱
func beam(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, twist := 0.0, ao0 := 0.85, ao1 := 1.0, caps := true) -> void:
	var axis := b - a
	var ln := axis.length()
	if ln < 0.00001:
		return
	axis = axis / ln
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := up.cross(axis).normalized()
	var y := axis.cross(x).normalized()
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	var botc: Array[Color] = []
	var topc: Array[Color] = []
	for i in sides:
		var ang := TAU * float(i) / float(sides) + twist
		var dir := x * cos(ang) + y * sin(ang)
		bot.append(a + dir * r0)
		top.append(b + dir * r1)
		botc.append(_mix(col, ao0))
		topc.append(_mix(col, ao1))
	for i in sides:
		var j := (i + 1) % sides
		var nrm := ((bot[i] - a).normalized() + (bot[j] - a).normalized()).normalized()
		quad4(bot[i], bot[j], top[j], top[i], nrm, botc[i], botc[j], topc[j], topc[i])
	if caps:
		for i in sides:
			var j := (i + 1) % sides
			tri(a, bot[i], bot[j], -axis, _mix(col, ao0 * 0.9))
			tri(b, top[j], top[i], axis, _mix(col, ao1))

func cyl(center: Vector3, r0: float, r1: float, h: float, col: Color, sides := 8, twist := 0.0, ao_bot := 0.8, ao_top := 1.0) -> void:
	beam(center + Vector3(0, -h * 0.5, 0), center + Vector3(0, h * 0.5, 0), r0, r1, sides, col, twist, ao_bot, ao_top)

func cone(base: Vector3, r: float, h: float, col: Color, sides := 8, twist := 0.0, ao_bot := 0.75) -> void:
	beam(base, base + Vector3(0, h, 0), r, 0.0015, sides, col, twist, ao_bot, 1.0, true)

func sphere(center: Vector3, r: float, col: Color, seg := 12, rings := 7, squash := Vector3.ONE, ao_bot := 0.62, ao_top := 1.0) -> void:
	for ri in rings:
		var v0 := -PI * 0.5 + PI * float(ri) / float(rings)
		var v1 := -PI * 0.5 + PI * float(ri + 1) / float(rings)
		var y0 := sin(v0)
		var y1 := sin(v1)
		var r0 := cos(v0)
		var r1 := cos(v1)
		var a0 := _mix(col, lerpf(ao_bot, ao_top, (y0 + 1.0) * 0.5))
		var a1 := _mix(col, lerpf(ao_bot, ao_top, (y1 + 1.0) * 0.5))
		for si in seg:
			var t0 := TAU * float(si) / float(seg)
			var t1 := TAU * float(si + 1) / float(seg)
			var p00 := center + Vector3(cos(t0) * r0 * squash.x, y0 * squash.y, sin(t0) * r0 * squash.z) * r
			var p10 := center + Vector3(cos(t1) * r0 * squash.x, y0 * squash.y, sin(t1) * r0 * squash.z) * r
			var p11 := center + Vector3(cos(t1) * r1 * squash.x, y1 * squash.y, sin(t1) * r1 * squash.z) * r
			var p01 := center + Vector3(cos(t0) * r1 * squash.x, y1 * squash.y, sin(t0) * r1 * squash.z) * r
			var n := (p00 - center).normalized()
			if n.length_squared() < 0.0001:
				n = Vector3.UP
			if ri == 0:
				tri(p00, p10, p11, (p00 - center).normalized(), a0)
			elif ri == rings - 1:
				tri(p00, p01, p11, (p01 - center).normalized(), a1)
			else:
				quad4(p00, p10, p11, p01, (p00 + p10 + p11 + p01 - center * 4.0).normalized(), a0, a0, a1, a1)

## 一叠木板（甲板、屋顶、墙板），板与板之间留缝
func planks(center: Vector3, w: float, d: float, count: int, thick: float, col: Color, basis := Basis.IDENTITY, gap := 0.04) -> void:
	for i in count:
		var u := (float(i) + 0.5) / float(count) - 0.5
		var off := basis * Vector3(0, 0, u * d)
		var shade := 0.86 + 0.14 * float(i % 3) / 2.0
		box(center + off, basis * Vector3(w, thick, d / float(count) - gap), _mix(col, shade), basis, 0.8, 1.0)

func mesh() -> ArrayMesh:
	var m := st.commit()
	return m

func instance(node_parent: Node3D, name_ := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh()
	mi.material_override = material()
	mi.name = name_
	node_parent.add_child(mi)
	return mi
