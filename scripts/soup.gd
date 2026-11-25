extends RefCounted
## High-detail procedural mesh builder (ported from 10-gfx.js Soup & 32-props.js clothPanel).
## Stores position, normal, linear vertex color, triplanar UV, and CUSTOM0(layer, rough, sway, emis).

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")

var P := PackedVector3Array()
var N := PackedVector3Array()
var K := PackedColorArray()
var UV := PackedVector2Array()
var S := PackedColorArray() # CUSTOM0: r=layer, g=rough, b=sway, a=emis

static var _rng: U.Rng = U.make_rng(777)
static var _geo_cache: Dictionary = {}
static var _col_cache: Dictionary = {}


static func COL() -> Dictionary:
	if _col_cache.is_empty():
		_col_cache = {
			"stone": U.col_hex(0x767b88), "stoneD": U.col_hex(0x4c505c), "stoneL": U.col_hex(0x9499a4),
			"basalt": U.col_hex(0x30323c), "basaltL": U.col_hex(0x454856),
			"earth": U.col_hex(0x54473c), "earthD": U.col_hex(0x352d27),
			"grass": U.col_hex(0x55583f), "grassD": U.col_hex(0x3f4231), "moss": U.col_hex(0x48553a),
			"road": U.col_hex(0x8a8176), "roadD": U.col_hex(0x5e574e), "mud": U.col_hex(0x43362b),
			"wood": U.col_hex(0x7a5c40), "woodD": U.col_hex(0x4e3a26), "woodL": U.col_hex(0x9a7a54),
			"bark": U.col_hex(0x3a3029), "rope": U.col_hex(0x8a7754),
			"iron": U.col_hex(0x3c4049), "ironL": U.col_hex(0x646b78), "steel": U.col_hex(0x8a93a2),
			"brass": U.col_hex(0x9a7b3a), "bronze": U.col_hex(0x7a5a34), "gold": U.col_hex(0xe2aa3c),
			"bone": U.col_hex(0xe0d7c0), "boneD": U.col_hex(0xa39a84),
			"clothR": U.col_hex(0x7c2c24), "clothB": U.col_hex(0x2f4c6c), "clothD": U.col_hex(0x2a2622), "clothT": U.col_hex(0x8a8068),
			"slate": U.col_hex(0x424a5a), "thatch": U.col_hex(0x8a7646), "black": U.col_hex(0x08090c),
			"ember": U.col_hex(0xff7a2a), "crystal": U.col_hex(0x7fc4ff),
			"tuftA": U.col_hex(0x55583f), "tuftB": U.col_hex(0x8a7646),
			"snow": U.col_hex(0xdfe8f4), "ice": U.col_hex(0x9fcfee),
			"leaf": U.col_hex(0x33492c), "leafL": U.col_hex(0x58703a),
			"sand": U.col_hex(0xb9976a), "ash": U.col_hex(0x4a4648),
			"slime": U.col_hex(0x4a6a44), "slimeD": U.col_hex(0x28402c),
			"rat": U.col_hex(0x51453c), "ratD": U.col_hex(0x372e28), "bat": U.col_hex(0x2e2a36),
			"ogre": U.col_hex(0x93a076), "ogreD": U.col_hex(0x63704e),
			"leather": U.col_hex(0x5a4030), "skin": U.col_hex(0xb98a6a),
		}
	return _col_cache


static func material() -> ShaderMaterial:
	TX.ensure()
	return TX.mat_world


static func set_rng(r: U.Rng) -> void:
	_rng = r


func verts() -> int:
	return P.size()


func clear() -> void:
	P.clear()
	N.clear()
	K.clear()
	UV.clear()
	S.clear()


func v(p: Vector3, n: Vector3, c: Color, uv: Vector2, layer: float = TX.L_PLAIN, rough: float = 0.92, sway: float = 0.0, emis: float = 0.0) -> void:
	P.append(p)
	N.append(n)
	K.append(c)
	UV.append(uv)
	S.append(Color(layer, rough, sway, emis))


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, layer: float = TX.L_PLAIN, rough: float = 0.92, o: Dictionary = {}) -> void:
	var n := (c - a).cross(b - a)
	var ln := n.length()
	if ln < 1e-10:
		return
	n /= ln
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	var mode := 0 if (ay >= ax and ay >= az) else (1 if ax >= az else 2)
	var sw: float = o.get("sway", 0.0)
	var em: float = o.get("emis", 0.0)
	var uvs: float = o.get("uvs", 0.25)
	var ca: Color = o.get("ca", col)
	var cb: Color = o.get("cb", col)
	var cc: Color = o.get("cc", col)
	var pts := [a, b, c]
	var cols := [ca, cb, cc]
	for i in 3:
		var pt: Vector3 = pts[i]
		var u := pt.x if mode == 0 else (pt.z if mode == 1 else pt.x)
		var w := pt.z if mode == 0 else pt.y
		v(pt, n, cols[i], Vector2(u * uvs, w * uvs), layer, rough, sw, em)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, layer: float = TX.L_PLAIN, rough: float = 0.92, o: Dictionary = {}) -> void:
	tri(a, b, c, col, layer, rough, o)
	tri(a, c, d, col, layer, rough, o)


static func _base_box() -> Dictionary:
	if _geo_cache.has("box"):
		return _geo_cache["box"]
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var d := _extract_mesh(bm)
	_geo_cache["box"] = d
	return d


static func _base_cyl(n: int = 8, rt: float = 1.0, open_ends: bool = false) -> Dictionary:
	var key := "cyl_%d_%.3f_%s" % [n, rt, "o" if open_ends else "c"]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var cm := CylinderMesh.new()
	cm.top_radius = maxf(0.0, rt)
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = n
	cm.rings = 1
	cm.cap_top = not open_ends and rt > 0.0001
	cm.cap_bottom = not open_ends
	var d := _extract_mesh(cm)
	_geo_cache[key] = d
	return d


static func _base_sph(w: int = 10, h: int = 6) -> Dictionary:
	var key := "sph_%d_%d" % [w, h]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = w
	sm.rings = h
	var d := _extract_mesh(sm)
	_geo_cache[key] = d
	return d


static func _base_dome(w: int = 10, h: int = 5) -> Dictionary:
	var key := "dome_%d_%d" % [w, h]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	sm.is_hemisphere = true
	sm.radial_segments = w
	sm.rings = h
	var d := _extract_mesh(sm)
	_geo_cache[key] = d
	return d


static func _base_ico(subdiv: int = 1) -> Dictionary:
	var key := "ico_%d" % subdiv
	if _geo_cache.has(key):
		return _geo_cache[key]
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var raw_v := [
		Vector3(-1, phi, 0), Vector3(1, phi, 0), Vector3(-1, -phi, 0), Vector3(1, -phi, 0),
		Vector3(0, -1, phi), Vector3(0, 1, phi), Vector3(0, -1, -phi), Vector3(0, 1, -phi),
		Vector3(phi, 0, -1), Vector3(phi, 0, 1), Vector3(-phi, 0, -1), Vector3(-phi, 0, 1),
	]
	for i in raw_v.size():
		raw_v[i] = raw_v[i].normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var tris: Array = []
	for f in faces:
		tris.append([raw_v[f[0]], raw_v[f[1]], raw_v[f[2]]])
	for _s in subdiv:
		var nxt: Array = []
		for t in tris:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			nxt.append([a, ab, ca])
			nxt.append([b, bc, ab])
			nxt.append([c, ca, bc])
			nxt.append([ab, bc, ca])
		tris = nxt
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for t in tris:
		# Flip winding for Godot CW front-face outward normals
		pos.append(t[0]); pos.append(t[2]); pos.append(t[1])
		nrm.append(t[0]); nrm.append(t[2]); nrm.append(t[1])
	var d := {"pos": pos, "nrm": nrm}
	_geo_cache[key] = d
	return d


static func _base_oct() -> Dictionary:
	if _geo_cache.has("oct"):
		return _geo_cache["oct"]
	var top := Vector3(0, 1, 0)
	var bot := Vector3(0, -1, 0)
	var ring := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		var nt := (b - top).cross(a - top).normalized()
		pos.append(top); pos.append(b); pos.append(a)
		nrm.append(nt); nrm.append(nt); nrm.append(nt)
		var nb := (a - bot).cross(b - bot).normalized()
		pos.append(bot); pos.append(a); pos.append(b)
		nrm.append(nb); nrm.append(nb); nrm.append(nb)
	var d := {"pos": pos, "nrm": nrm}
	_geo_cache["oct"] = d
	return d


static func _base_torus(n: int = 10, tube: float = 0.2, m: int = 5) -> Dictionary:
	var key := "tor_%d_%.2f_%d" % [n, tube, m]
	if _geo_cache.has(key):
		return _geo_cache[key]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var ca0 := cos(a0); var sa0 := sin(a0)
		var ca1 := cos(a1); var sa1 := sin(a1)
		for j in m:
			var b0 := TAU * float(j) / float(m)
			var b1 := TAU * float(j + 1) / float(m)
			var cb0 := cos(b0); var sb0 := sin(b0)
			var cb1 := cos(b1); var sb1 := sin(b1)
			var p00 := Vector3((1.0 + tube * cb0) * ca0, (1.0 + tube * cb0) * sa0, tube * sb0)
			var p10 := Vector3((1.0 + tube * cb0) * ca1, (1.0 + tube * cb0) * sa1, tube * sb0)
			var p11 := Vector3((1.0 + tube * cb1) * ca1, (1.0 + tube * cb1) * sa1, tube * sb1)
			var p01 := Vector3((1.0 + tube * cb1) * ca0, (1.0 + tube * cb1) * sa0, tube * sb1)
			var n00 := Vector3(cb0 * ca0, cb0 * sa0, sb0)
			var n10 := Vector3(cb0 * ca1, cb0 * sa1, sb0)
			var n11 := Vector3(cb1 * ca1, cb1 * sa1, sb1)
			var n01 := Vector3(cb1 * ca0, cb1 * sa0, sb1)
			pos.append(p00); pos.append(p10); pos.append(p11)
			nrm.append(n00); nrm.append(n10); nrm.append(n11)
			pos.append(p00); pos.append(p11); pos.append(p01)
			nrm.append(n00); nrm.append(n11); nrm.append(n01)
	var d := {"pos": pos, "nrm": nrm}
	_geo_cache[key] = d
	return d


static func _extract_mesh(pm: PrimitiveMesh) -> Dictionary:
	var arr := pm.get_mesh_arrays()
	var verts_in: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms_in: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx_in: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	if idx_in.size() > 0:
		pos.resize(idx_in.size())
		nrm.resize(idx_in.size())
		for i in idx_in.size():
			var vi := idx_in[i]
			pos[i] = verts_in[vi]
			nrm[i] = norms_in[vi]
	else:
		pos = verts_in
		nrm = norms_in
	return {"pos": pos, "nrm": nrm}


func add_src(src: Dictionary, o: Dictionary) -> void:
	var sp: PackedVector3Array = src["pos"]
	var sn: PackedVector3Array = src["nrm"]
	var count := sp.size()
	var sc := Vector3.ONE
	if o.has("s"):
		var sv: Variant = o["s"]
		if sv is Vector3:
			sc = sv
		else:
			var f := float(sv)
			sc = Vector3(f, f, f)
	var q := Quaternion.IDENTITY
	if o.has("q"):
		q = o["q"]
	elif o.has("r"):
		var rv: Vector3 = o["r"]
		q = Quaternion.from_euler(rv)
	var pos: Vector3 = o.get("p", Vector3.ZERO)
	var col: Color = o.get("c", Color.WHITE)
	var jit: float = o.get("jit", 0.07)
	var k := 1.0 + (_rng.next_f() * 2.0 - 1.0) * jit
	var cr := col.r * k
	var cg := col.g * k
	var cb := col.b * k
	var layer: float = float(o.get("l", TX.L_PLAIN))
	var rough: float = float(o.get("rough", 0.92))
	var sway: float = float(o.get("sway", 0.0))
	var emis: float = float(o.get("emis", 0.0))
	var uvs: float = float(o.get("uvs", 0.25))
	var uo := floor(_rng.next_f() * 64.0) / 16.0
	var vo := floor(_rng.next_f() * 64.0) / 16.0
	var smooth_n: bool = o.get("smooth", false)
	var has_deform: bool = o.has("deform")
	var deform_fn: Callable = o.get("deform", Callable())
	var has_grad: bool = o.has("grad")
	var grad: Array = o.get("grad", [])
	var has_cf: bool = o.has("cf")
	var cf_fn: Callable = o.get("cf", Callable())
	var has_swayf: bool = o.has("swayf")
	var swayf_fn: Callable = o.get("swayf", Callable())
	var has_c2: bool = o.has("c2")
	var c2_col: Color = o.get("c2_col", Color.WHITE)
	var c2_fn: Callable = o.get("c2", Callable())
	var dbl: bool = o.get("dbl", false)

	var start := P.size()
	var i := 0
	while i + 2 < count:
		var v0 := Vector3(sp[i].x * sc.x, sp[i].y * sc.y, sp[i].z * sc.z)
		var v1 := Vector3(sp[i + 1].x * sc.x, sp[i + 1].y * sc.y, sp[i + 1].z * sc.z)
		var v2 := Vector3(sp[i + 2].x * sc.x, sp[i + 2].y * sc.y, sp[i + 2].z * sc.z)
		if has_deform:
			v0 = deform_fn.call(v0)
			v1 = deform_fn.call(v1)
			v2 = deform_fn.call(v2)
		# Godot CW front face outward normal = (v2 - v0).cross(v1 - v0)
		var fn := (v2 - v0).cross(v1 - v0)
		var ln := fn.length()
		if ln < 1e-10:
			i += 3
			continue
		fn /= ln
		var ax := absf(fn.x)
		var ay := absf(fn.y)
		var az := absf(fn.z)
		var mode := 0 if (ay >= ax and ay >= az) else (1 if ax >= az else 2)
		var tri_v := [v0, v1, v2]
		for j in 3:
			var pt: Vector3 = tri_v[j]
			var uu := pt.x if mode == 0 else (pt.z if mode == 1 else pt.x)
			var ww := pt.z if mode == 0 else pt.y
			var uv := Vector2(uu * uvs + uo, ww * uvs + vo)
			var g := 1.0
			if has_grad:
				g = lerpf(float(grad[2]), 1.0, U.smooth(float(grad[0]), float(grad[1]), pt.y))
			if has_cf:
				g *= float(cf_fn.call(pt))
			var vc: Color
			if has_c2:
				var ct := clampf(float(c2_fn.call(pt)), 0.0, 1.0)
				vc = Color(lerpf(cr, c2_col.r, ct) * g, lerpf(cg, c2_col.g, ct) * g, lerpf(cb, c2_col.b, ct) * g, 1.0)
			else:
				vc = Color(cr * g, cg * g, cb * g, 1.0)
			var sw := float(swayf_fn.call(pt)) if has_swayf else sway
			var nv: Vector3
			if smooth_n:
				var on: Vector3 = sn[i + j]
				nv = (q * Vector3(on.x / maxf(absf(sc.x), 1e-4), on.y / maxf(absf(sc.y), 1e-4), on.z / maxf(absf(sc.z), 1e-4)).normalized())
			else:
				nv = q * fn
			var wp := q * pt + pos
			P.append(wp)
			N.append(nv)
			K.append(vc)
			UV.append(uv)
			S.append(Color(layer, rough, sw, emis))
		i += 3
	if dbl:
		_double_from(start)


func _double_from(start: int) -> void:
	var end := P.size()
	var i := start
	while i + 2 < end:
		for j in [0, 2, 1]:
			var k := i + j
			P.append(P[k])
			N.append(-N[k])
			K.append(K[k])
			UV.append(UV[k])
			S.append(S[k])
		i += 3


func box(w: float, h: float, d: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	opt["s"] = Vector3(w, h, d)
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_box(), opt)


func cyl(r: float, h: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	var rz: float = float(opt.get("rz", r))
	opt["s"] = Vector3(r, h, rz)
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_cyl(int(opt.get("n", 8)), float(opt.get("rt", 1.0)), bool(opt.get("open", false))), opt)


func cone(r: float, h: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	var rz: float = float(opt.get("rz", r))
	opt["s"] = Vector3(r, h, rz)
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_cyl(int(opt.get("n", 6)), 0.0, false), opt)


func ico(r: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	if opt.has("sc"):
		var sv: Vector3 = opt["sc"]
		opt["s"] = Vector3(r * sv.x, r * sv.y, r * sv.z)
	else:
		opt["s"] = r
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_ico(int(opt.get("d", 1))), opt)


func sph(r: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	if opt.has("sc"):
		var sv: Vector3 = opt["sc"]
		opt["s"] = Vector3(r * sv.x, r * sv.y, r * sv.z)
	else:
		opt["s"] = r
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	if not opt.has("smooth"):
		opt["smooth"] = true
	add_src(_base_sph(int(opt.get("w", 10)), int(opt.get("h", 6))), opt)


func dome(sx: float, sy: float, sz: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	opt["s"] = Vector3(sx, sy, sz)
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_dome(int(opt.get("w", 10)), int(opt.get("h", 5))), opt)


func oct(sx: float, sy: float, sz: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	opt["s"] = Vector3(sx, sy, sz)
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_oct(), opt)


func torus(r: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	opt["s"] = r
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_torus(int(opt.get("n", 10)), float(opt.get("t", 0.2)), int(opt.get("m", 5))), opt)


func seg(a: Vector3, b: Vector3, r0: float, r1: float, c: Color, o: Dictionary = {}) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1e-5:
		return
	var dir := d / ln
	var q: Quaternion
	if dir.dot(Vector3.UP) < -0.9999:
		q = Quaternion(Vector3.RIGHT, PI)
	else:
		q = Quaternion(Vector3.UP, dir)
	var opt := o.duplicate()
	opt["q"] = q
	opt["p"] = (a + b) * 0.5
	opt["s"] = Vector3(r0, ln, r0)
	opt["c"] = c
	add_src(_base_cyl(int(opt.get("n", 6)), r1 / maxf(r0, 1e-4), bool(opt.get("open", false))), opt)


func rock(r: float, x: float, y: float, z: float, c: Color, o: Dictionary = {}) -> void:
	var opt := o.duplicate()
	var sd := _rng.next_f() * 100.0
	var f := 1.5 / maxf(r, 0.05)
	var sq: float = float(opt.get("sq", 0.75))
	opt["deform"] = func(pt: Vector3) -> Vector3:
		var kk := 0.72 + 0.56 * U.vnoise(pt.x * f + pt.y * f * 0.7 + sd, pt.z * f - pt.y * f * 0.6 + sd, 7)
		return Vector3(pt.x * kk, pt.y * kk * sq, pt.z * kk)
	if not opt.has("l"):
		opt["l"] = TX.L_ROCK
	if not opt.has("r"):
		opt["r"] = Vector3(_rng.next_f() * 0.5, _rng.next_f() * TAU, _rng.next_f() * 0.5)
	opt["s"] = r
	opt["p"] = Vector3(x, y, z)
	opt["c"] = c
	add_src(_base_ico(int(opt.get("d", 1))), opt)


## Tattered swaying cloth banner / loincloth panel (ported from 32-props.js clothPanel).
func cloth_panel(o: Dictionary) -> void:
	var x0: float = float(o.get("x0", -0.2))
	var x1: float = float(o.get("x1", 0.2))
	var y_top: float = float(o.get("y_top", 1.0))
	var length: float = float(o.get("len", 0.6))
	var z0: float = float(o.get("z", 0.0))
	var col: Color = o.get("col", COL()["clothR"])
	var has_c2: bool = o.has("col2")
	var col2: Color = o.get("col2", col)
	var rng: U.Rng = o.get("rng", _rng)
	var sway: float = float(o.get("sway", 1.0))
	var nx: int = int(o.get("nx", 4))
	var ny: int = int(o.get("ny", 6))
	var rag: float = float(o.get("rag", 0.35))
	var drop_arr: Array[float] = []
	for i in nx + 1:
		drop_arr.append(length * (1.0 - rag * rng.next_f()))
	var grid: Array = []
	for j in ny + 1:
		var row: Array = []
		var vv := float(j) / float(ny)
		for i in nx + 1:
			var uu := float(i) / float(nx)
			var xx := lerpf(x0, x1, uu)
			var yy := y_top - vv * drop_arr[i]
			var zz := z0 + sin(vv * PI) * 0.04 + (rng.next_f() - 0.5) * 0.025 * vv
			row.append(Vector3(xx, yy, zz))
		grid.append(row)
	for j in ny:
		var v0 := float(j) / float(ny)
		var v1 := float(j + 1) / float(ny)
		for i in nx:
			var u0 := float(i) / float(nx)
			var u1 := float(i + 1) / float(nx)
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			var cc := col
			if has_c2 and (i == 0 or i == nx - 1 or j == ny - 1):
				cc = col2
			var k0 := 0.8 + 0.2 * (1.0 - v0)
			var k1 := 0.8 + 0.2 * (1.0 - v1)
			var c0 := U.mul_c(cc, k0)
			var c1 := U.mul_c(cc, k1)
			var nrm := (c - a).cross(b - a)
			nrm = nrm.normalized() if nrm.length_squared() > 1e-8 else Vector3(0, 0, 1)
			var s0 := sway * v0 * v0
			var s1 := sway * v1 * v1
			# Front & back faces (double-sided)
			v(a, nrm, c0, Vector2(u0, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(b, nrm, c0, Vector2(u1, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(c, nrm, c1, Vector2(u1, v1), TX.L_CLOTH, 0.94, s1, 0.0)
			v(a, nrm, c0, Vector2(u0, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(c, nrm, c1, Vector2(u1, v1), TX.L_CLOTH, 0.94, s1, 0.0)
			v(d, nrm, c1, Vector2(u0, v1), TX.L_CLOTH, 0.94, s1, 0.0)
			v(a, -nrm, c0, Vector2(u0, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(c, -nrm, c1, Vector2(u1, v1), TX.L_CLOTH, 0.94, s1, 0.0)
			v(b, -nrm, c0, Vector2(u1, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(a, -nrm, c0, Vector2(u0, v0), TX.L_CLOTH, 0.94, s0, 0.0)
			v(d, -nrm, c1, Vector2(u0, v1), TX.L_CLOTH, 0.94, s1, 0.0)
			v(c, -nrm, c1, Vector2(u1, v1), TX.L_CLOTH, 0.94, s1, 0.0)


func merge(other, opt: Dictionary = {}) -> void:
	var p: Vector3 = opt.get("p", Vector3.ZERO)
	var s: float = float(opt.get("s", 1.0))
	var q := Quaternion.IDENTITY
	if opt.has("q"):
		q = opt["q"]
	elif opt.has("r"):
		q = Quaternion.from_euler(opt["r"])
	elif opt.has("ry"):
		q = Quaternion(Vector3.UP, float(opt["ry"]))
	var has_tint: bool = opt.has("tint") and opt["tint"] != null
	var tint: Color = opt["tint"] if has_tint else Color.WHITE
	var has_ao: bool = opt.has("ao") and opt["ao"] != null
	var ao: Array = opt["ao"] if has_ao else []

	var op: PackedVector3Array = other.P
	var on: PackedVector3Array = other.N
	var ok: PackedColorArray = other.K
	var ou: PackedVector2Array = other.UV
	var os: PackedColorArray = other.S
	var n := op.size()
	for i in n:
		var lp := op[i]
		var wp := q * (lp * s) + p
		var wn := q * on[i]
		var g := 1.0
		if has_ao:
			g = lerpf(float(ao[2]), 1.0, U.smooth(float(ao[0]), float(ao[1]), lp.y))
		var kc := ok[i]
		if has_tint:
			K.append(Color(kc.r * tint.r * g, kc.g * tint.g * g, kc.b * tint.b * g, 1.0))
		else:
			K.append(Color(kc.r * g, kc.g * g, kc.b * g, 1.0))
		P.append(wp)
		N.append(wn)
		UV.append(ou[i])
		S.append(os[i])


func mirror_xz() -> void:
	for i in P.size():
		P[i] = Vector3(P[i].z, P[i].y, P[i].x)
		N[i] = Vector3(N[i].z, N[i].y, N[i].x)
	var i := 0
	while i + 2 < P.size():
		var tp := P[i + 1]; P[i + 1] = P[i + 2]; P[i + 2] = tp
		var tn := N[i + 1]; N[i + 1] = N[i + 2]; N[i + 2] = tn
		var tk := K[i + 1]; K[i + 1] = K[i + 2]; K[i + 2] = tk
		var tu := UV[i + 1]; UV[i + 1] = UV[i + 2]; UV[i + 2] = tu
		var ts := S[i + 1]; S[i + 1] = S[i + 2]; S[i + 2] = ts
		i += 3


func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var n := P.size()
	for i in n:
		st.set_normal(N[i])
		st.set_color(K[i])
		st.set_uv(UV[i])
		st.set_custom(0, S[i])
		st.add_vertex(P[i])
	return st.commit()


func mesh() -> ArrayMesh:
	return build()


func instance(node_parent: Node3D, name_str: String = "", mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build()
	mi.material_override = mat if mat != null else material()
	mi.name = name_str
	node_parent.add_child(mi)
	return mi
