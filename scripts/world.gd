extends Node3D

const Defs := preload("res://scripts/defs.gd")
const MeshKit := preload("res://scripts/meshkit.gd")
const Soup := preload("res://scripts/soup.gd")

## 地图生成：道路 → 塔位 → 地面/路面/装饰/灯光。
## 算法移植自原版 src/30-layout.js（随机游走 + Catmull-Rom 平滑 + 塔位筛选）。

const STEP := 0.3
const ROAD_HALF := 1.25
const HALF := 18.0

var rng := RandomNumberGenerator.new()
var seed_value := 0
var pts := PackedVector2Array()
var length := 0.0
var pads: Array = []
var cave := Vector2.ZERO
var gate := Vector2.ZERO
var biome: Dictionary = {}
var biome_index := 0
var stream_pts := PackedVector2Array()

var _pad_nodes: Array[Node3D] = []

func generate(p_seed: int, p_biome: int) -> bool:
	seed_value = p_seed
	biome_index = p_biome
	biome = Defs.BIOMES[p_biome]
	rng.seed = p_seed * 7919 + 13
	var best: Dictionary = {}
	for attempt in 600:
		var road: Dictionary = _try_road()
		if road.is_empty():
			continue
		var p: Dictionary = _choose_pads(road)
		if p.is_empty():
			continue
		if best.is_empty() or float(p["score"]) > float(best["score"]):
			best = road.duplicate()
			best["pads"] = p["pads"]
			best["score"] = p["score"]
		if attempt > 300 and not best.is_empty():
			break
	if best.is_empty():
		return false
	pts = best["poly"]
	length = float(best["L"])
	cave = Vector2(-14.6, float(best["zc"]))
	gate = Vector2(float(best["kx"]), -11.4)
	pads = best["pads"]
	return true

# ---------------------------------------------------------------- 路

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 0.0:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (p - (a + ab * t)).length()

func _seg_inter(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r := b - a
	var s := d - c
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 0.000000001:
		return -1.0
	var t := ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / den
	var u := ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / den
	return t if (t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0) else -1.0

func _catmull(way: PackedVector2Array, step: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	var n := way.size()
	for i in n - 1:
		var p0 := way[max(0, i - 1)]
		var p1 := way[i]
		var p2 := way[i + 1]
		var p3 := way[min(n - 1, i + 2)]
		for k in 24:
			var t := float(k) / 24.0
			var t2 := t * t
			var t3 := t2 * t
			var x := 0.5 * ((2.0 * p1.x) + (-p0.x + p2.x) * t + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3)
			var z := 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)
			raw.append(Vector2(x, z))
	raw.append(way[n - 1])
	return _resample(raw, step)

func _resample(raw: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw.size() < 2:
		return raw
	var total := 0.0
	for i in raw.size() - 1:
		total += (raw[i + 1] - raw[i]).length()
	if total <= 0.0:
		return raw
	out.append(raw[0])
	var target := step
	var i := 0
	var acc := 0.0
	while target < total - 0.001:
		while i < raw.size() - 1:
			var seglen := (raw[i + 1] - raw[i]).length()
			if acc + seglen >= target:
				break
			acc += seglen
			i += 1
		if i >= raw.size() - 1:
			break
		var seglen2 := (raw[i + 1] - raw[i]).length()
		var t := 0.0 if seglen2 <= 0.0 else (target - acc) / seglen2
		out.append(raw[i] + (raw[i + 1] - raw[i]) * t)
		target += step
	if (raw[raw.size() - 1] - out[out.size() - 1]).length() > step * 0.4:
		out.append(raw[raw.size() - 1])
	return out

func _relax(poly: PackedVector2Array, iters: int) -> PackedVector2Array:
	for k in iters:
		for i in range(1, poly.size() - 1):
			poly[i] = poly[i] * 0.5 + (poly[i - 1] + poly[i + 1]) * 0.25
	return poly

func _try_road() -> Dictionary:
	var zc := rng.randf_range(-6.5, 9.0)
	var kx := rng.randf_range(0.5, 10.5)
	var way := PackedVector2Array([Vector2(-17.6, zc), Vector2(-12.0, zc)])
	var end_a := Vector2(kx, -6.2)
	var end_b := Vector2(kx, -11.4)
	var cur := way[1]
	var dir := 0.0
	var n_mid := rng.randi_range(4, 7)
	for k in n_mid:
		var ok := false
		for t in 30:
			var a := dir + rng.randf_range(-2.3, 2.3)
			var l := rng.randf_range(5.5, 11.5)
			var p := cur + Vector2(cos(a), sin(a)) * l
			if p.x < -10.5 or p.x > 14.2 or p.y < -6.5 or p.y > 14.2:
				continue
			if p.x + p.y > 24.0:
				continue
			if absf(p.x - kx) < 6.5 and p.y < -4.0:
				continue
			var clear := true
			for i in way.size() - 2:
				if _seg_dist(p, way[i], way[i + 1]) < 6.2:
					clear = false
					break
			if not clear:
				continue
			var bad := false
			for i in way.size() - 2:
				if _seg_inter(cur, p, way[i], way[i + 1]) >= 0.0:
					bad = true
				var u := 0.25
				while u <= 1.0 and not bad:
					if _seg_dist(cur + (p - cur) * u, way[i], way[i + 1]) < 5.6:
						bad = true
					u += 0.25
			if bad:
				continue
			way.append(p)
			dir = atan2(p.y - cur.y, p.x - cur.x)
			cur = p
			ok = true
			break
		if not ok:
			return {}
	way.append(end_a)
	way.append(end_b)
	var poly := _catmull(way, STEP)
	poly = _relax(poly, 10)
	poly = _resample(poly, STEP)
	poly[poly.size() - 1] = end_b
	var n := poly.size()
	var L := float(n - 1) * STEP
	if L < 58.0 or L > 92.0:
		return {}
	var gap := int(round(10.0 / STEP))
	for i in n:
		var pt := poly[i]
		var s := float(i) * STEP
		if pt.x > 15.3 or pt.y > 15.3 or pt.y < -11.6 or pt.x + pt.y > 26.0:
			return {}
		if s > 7.0 and pt.x < -12.2:
			return {}
		if s < L - 5.5 and absf(pt.x - kx) < 5.6 and pt.y < -8.6:
			return {}
		if s > 7.0 and s < L - 6.0 and pt.y < -9.2:
			return {}
		var j := i + gap
		while j < n:
			if (poly[j] - pt).length() < 6.0:
				return {}
			j += 2
		if i >= 4 and i < n - 4:
			var a1 := atan2(poly[i].y - poly[i - 4].y, poly[i].x - poly[i - 4].x)
			var a2 := atan2(poly[i + 4].y - poly[i].y, poly[i + 4].x - poly[i].x)
			if absf(_ang_diff(a1, a2)) > 0.62:
				return {}
	return {"poly": poly, "L": L, "zc": zc, "kx": kx}

func _ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU) - PI
	return d

func _poly_min_dist(poly: PackedVector2Array, p: Vector2, i0 := 0, i1 := -1) -> float:
	var best := 1e9
	var last := poly.size() - 1 if i1 < 0 else i1
	for i in range(i0, last):
		var d := _seg_dist(p, poly[i], poly[i + 1])
		if d < best:
			best = d
	return best

func _choose_pads(road: Dictionary) -> Dictionary:
	var poly: PackedVector2Array = road["poly"]
	var L: float = road["L"]
	var kx: float = road["kx"]
	var cand: Array = []
	var off := ROAD_HALF + 2.0
	var s := 7.5
	while s < L - 3.5:
		var i := int(round(s / STEP))
		var a := poly[max(0, i - 2)]
		var b := poly[min(poly.size() - 1, i + 2)]
		var t := b - a
		var tl := t.length()
		if tl <= 0.0:
			s += 0.9
			continue
		var nx := -t.y / tl
		var nz := t.x / tl
		for side in [-1, 1]:
			var x: float = poly[i].x + nx * off * side
			var z: float = poly[i].y + nz * off * side
			if absf(x) > HALF - 2.4 or absf(z) > HALF - 2.4 or x < -11.2:
				continue
			if absf(x - kx) < 6.4 and z < -9.6:
				continue
			if z < -12.6 or x + z < -21.0:
				continue
			var v := Vector2(x, z)
			if _poly_min_dist(poly, v) < off - 0.25:
				continue
			var cov := 0.0
			for j in range(0, poly.size(), 2):
				if (v - poly[j]).length_squared() < 36.0:
					cov += STEP * 2.0
			cand.append({"x": x, "z": z, "s": s, "side": side, "cov": cov})
		s += 0.9
	if cand.size() < 8:
		return {}
	cand.sort_custom(func(p, q): return p["cov"] > q["cov"])
	var chosen: Array = []
	var thirds := [0, 0, 0]
	for pass_i in 2:
		for third in 3:
			for c in cand:
				var idx: int = min(2, int(floor(float(c["s"]) / L * 3.0)))
				if idx != third:
					continue
				if _far_from(chosen, c, 4.6):
					chosen.append(c)
					thirds[third] += 1
					break
	for c in cand:
		if chosen.size() >= 11:
			break
		if _far_from(chosen, c, 4.6):
			chosen.append(c)
	if chosen.size() < 8:
		return {}
	chosen.sort_custom(func(p, q): return p["s"] < q["s"])
	var score := minf(L, 84.0) * 0.55 + chosen.size() * 2.0 + rng.randf() * 5.0
	return {"pads": chosen, "score": score}

func _far_from(list: Array, c: Dictionary, dmin: float) -> bool:
	for p in list:
		var dx: float = p["x"] - c["x"]
		var dz: float = p["z"] - c["z"]
		if dx * dx + dz * dz <= dmin * dmin:
			return false
	return true

# ---------------------------------------------------------------- 路径采样

func point_at(s: float) -> Dictionary:
	var n := pts.size()
	var f := clampf(s, 0.0, length) / STEP
	var i := int(floor(f))
	if i >= n - 1:
		i = n - 2
	var u := f - float(i)
	var a := pts[i]
	var b := pts[i + 1]
	var p := a + (b - a) * u
	var t := (b - a).normalized()
	return {"x": p.x, "z": p.y, "tx": t.x, "tz": t.y}

func world_at(s: float, lateral: float) -> Vector3:
	var p := point_at(s)
	return Vector3(p["x"] - p["tz"] * lateral, 0.0, p["z"] + p["tx"] * lateral)

## 把塔位按 s 归到路线上的比例（AI 用）
func pad_rel(pad: Dictionary) -> float:
	return float(pad["s"]) / length

func coverage(pad: Dictionary, radius: float) -> float:
	var r2 := radius * radius
	var c := 0.0
	for i in range(0, pts.size(), 2):
		var dx := pts[i].x - float(pad["x"])
		var dz := pts[i].y - float(pad["z"])
		if dx * dx + dz * dz < r2:
			c += STEP * 2.0
	return c

# ---------------------------------------------------------------- 视觉

var ground_mat: StandardMaterial3D
var road_mat: StandardMaterial3D

func build_visuals() -> void:
	_clear_visuals()
	var b := biome
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = b["sky"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = b["amb"]
	e.ambient_light_energy = float(b["amb_e"]) * 1.2
	e.fog_enabled = true
	e.fog_light_color = b["fog"]
	e.fog_density = float(b["fog_density"])
	e.fog_sky_affect = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.65
	e.glow_bloom = 0.2
	e.glow_hdr_threshold = 0.9
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = b["light"]
	sun.light_energy = float(b["light_e"])
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 2.2
	sun.shadow_opacity = 0.92
	sun.rotation_degrees = Vector3(-52, -38, 0)
	add_child(sun)

	# 补光：让背光面（尤其崖壁）不至于纯黑
	var fill := DirectionalLight3D.new()
	fill.light_color = b["amb"]
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-28, 145, 0)
	add_child(fill)

	# 地面：细分网格 + 顶点色斑驳（无贴图也做出「地皮」层次），外围再挂一圈悬崖 → 悬浮地台
	_build_ground()
	_build_cliff()
	_build_road()
	_build_water()
	_build_cave_gate()
	_build_decor()
	_build_detail()
	_build_pads()

func _clear_visuals() -> void:
	for c in get_children():
		c.queue_free()

func _build_road():
	var mat_main := StandardMaterial3D.new()
	mat_main.albedo_color = Color.WHITE
	mat_main.vertex_color_use_as_albedo = true
	mat_main.roughness = 0.95
	road_mat = mat_main
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var base: Color = biome["road"]
	var edge: Color = biome["road_d"]
	# 底下一层更宽的暗色带 → 路肩
	for band in [[ROAD_HALF + 0.18, 0.043, edge], [ROAD_HALF, 0.055, base]]:
		var half: float = band[0]
		var y: float = band[1]
		var col: Color = band[2]
		for i in n - 1:
			var a := pts[i]
			var c := pts[i + 1]
			var t := c - a
			if t.length_squared() <= 0.0:
				continue
			t = t.normalized()
			var nrm := Vector2(-t.y, t.x) * half
			var shade := 0.94 + 0.06 * sin(float(i) * 0.15)
			var cc := Color(col.r * shade, col.g * shade, col.b * shade)
			var a0 := Vector3(a.x - nrm.x, y, a.y - nrm.y)
			var a1 := Vector3(a.x + nrm.x, y, a.y + nrm.y)
			var b0 := Vector3(c.x - nrm.x, y, c.y - nrm.y)
			var b1 := Vector3(c.x + nrm.x, y, c.y + nrm.y)
			_tri(st, a0, b0, b1, cc)
			_tri(st, a0, b1, a1, cc)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = road_mat
	add_child(mi)
	return mi

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var lc := col.srgb_to_linear()
	st.set_color(lc)
	st.add_vertex(a)
	st.set_color(lc)
	st.add_vertex(b)
	st.set_color(lc)
	st.add_vertex(c)

func _build_water() -> void:
	var is_lava: bool = bool(biome.get("lava", false))
	if not (bool(biome.get("water", false)) or is_lava):
		return
	# 在路线中段旁挑一处空地放水塘 / 熔岩池，别压在路上
	var mid := int(pts.size() * 0.55)
	var a := pts[max(0, mid - 3)]
	var b := pts[min(pts.size() - 1, mid + 3)]
	var t := (b - a)
	if t.length_squared() <= 0.0:
		return
	t = t.normalized()
	var nrm := Vector2(-t.y, t.x)
	var r := 4.2
	var best: Vector3 = Vector3.ZERO
	var found := false
	for sgn in [1.0, -1.0]:
		var c: Vector2 = pts[mid] + nrm * 8.6 * sgn
		if absf(c.x) > 15.0 or absf(c.y) > 15.0:
			continue
		if _poly_min_dist(pts, c) < r + 1.6:
			continue
		best = Vector3(c.x, 0, c.y)
		found = true
		break
	if not found:
		return
	var rim_col: Color = Color("1a1518") if is_lava else biome["earth_d"]
	MeshKit.cyl(self, r + 0.55, 0.06, best + Vector3(0, 0.02, 0), rim_col, 14)
	var col: Color = Color("ff5a10") if is_lava else Color("2f4a52")
	var glow: float = 1.1 if is_lava else 0.0
	MeshKit.cyl(self, r, 0.03, best + Vector3(0, 0.045, 0), col, 14, Vector3.ZERO, glow)
	# 池边几块碎石
	for k in 5:
		var ang := TAU * float(k) / 5.0 + 0.4
		MeshKit.box(self, Vector3(0.5, 0.3, 0.4), best + Vector3(cos(ang) * (r + 0.4), 0.12, sin(ang) * (r + 0.4)), biome["rock"], Vector3(0, ang, 0))
	if is_lava:
		var light := OmniLight3D.new()
		light.light_color = Color("ff6a20")
		light.light_energy = 1.3
		light.omni_range = 8.0
		light.position = best + Vector3(0, 0.8, 0)
		add_child(light)

func _build_cave_gate() -> void:
	# 洞口：两侧石柱 + 黑暗门洞 + 火光
	var dark: Color = Color("0a0806")
	var rock_c: Color = biome["rock"]
	var cave_p := Vector3(cave.x - 1.2, 0, cave.y)
	MeshKit.box(self, Vector3(3.0, 3.6, 0.7), cave_p + Vector3(0, 1.8, 0), rock_c)
	MeshKit.box(self, Vector3(2.0, 2.6, 0.9), cave_p + Vector3(0.1, 1.35, 0.2), dark)
	for s in [-1, 1]:
		MeshKit.box(self, Vector3(0.7, 3.2, 0.9), cave_p + Vector3(0.1, 1.6, 1.6 * s), biome["rock_l"])
		MeshKit.sphere(self, 0.16, cave_p + Vector3(1.5, 2.4, 1.5 * s), Color("ff8a3c"), 6, 2.0)
	var fire := OmniLight3D.new()
	fire.light_color = Color("ff8a3c")
	fire.light_energy = 1.6
	fire.omni_range = 7.0
	fire.position = cave_p + Vector3(1.0, 1.6, 0)
	add_child(fire)

	# 门：两座灯楼 + 中间大信标（对应原版 beacon）
	var gate_p := Vector3(gate.x, 0, gate.y - 1.6)
	for s in [-1, 1]:
		MeshKit.box(self, Vector3(1.4, 4.4, 1.4), gate_p + Vector3(1.5 * s, 2.2, 0), rock_c)
		MeshKit.box(self, Vector3(1.6, 0.5, 1.6), gate_p + Vector3(1.5 * s, 4.5, 0), biome["rock_l"])
		MeshKit.sphere(self, 0.3, gate_p + Vector3(1.5 * s, 4.9, 0), Color("ff8a3c"), 8, 2.6)
	MeshKit.cone(self, 1.0, 2.6, gate_p + Vector3(0, 5.4, 0), biome["rock_l"], 6)
	var beacon := MeshKit.sphere(self, 0.55, gate_p + Vector3(0, 4.4, 0), Color("ffd27a"), 12, 3.2)
	var blight := OmniLight3D.new()
	blight.light_color = Color("ffc060")
	blight.light_energy = 2.2
	blight.omni_range = 11.0
	blight.position = gate_p + Vector3(0, 4.4, 0)
	add_child(blight)
	# 轻微呼吸的灯塔
	var tw := create_tween().set_loops()
	tw.tween_property(blight, "light_energy", 1.5, 1.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(blight, "light_energy", 2.4, 1.8).set_trans(Tween.TRANS_SINE)

func _build_decor() -> void:
	var decor: Array = biome.get("decor", ["rock"])
	var rock: Color = biome["rock"]
	var rock_l: Color = biome["rock_l"]
	var flora: Color = biome["flora"]
	var flora_l: Color = biome["flora_l"]
	var earth_d: Color = biome["earth_d"]
	# 地面色块：打散大片纯色，做出「地皮」的感觉
	for i in 46:
		var px := rng.randf_range(-19.0, 19.0)
		var pz := rng.randf_range(-19.0, 19.0)
		var w := rng.randf_range(1.6, 4.4)
		var d := rng.randf_range(1.6, 4.4)
		if _poly_min_dist(pts, Vector2(px, pz)) < ROAD_HALF + 1.4:
			continue
		var shade := earth_d.lerp(rock, rng.randf_range(0.0, 0.3))
		var patch := MeshKit.cyl(self, maxf(w, d) * 0.5, 0.02, Vector3(px, 0.005, pz), shade, 9)
		patch.scale = Vector3(1.0, 1.0, d / maxf(w, d))
	var placed: Array = []
	var tries := 0
	while placed.size() < 40 and tries < 400:
		tries += 1
		var x := rng.randf_range(-17.0, 17.0)
		var z := rng.randf_range(-17.0, 17.0)
		var v := Vector2(x, z)
		if _poly_min_dist(pts, v) < ROAD_HALF + 1.0:
			continue
		var blocked := false
		for p in pads:
			if (Vector2(float(p["x"]), float(p["z"])) - v).length() < 2.6:
				blocked = true
				break
		if blocked:
			continue
		for q in placed:
			if (Vector2(q.x, q.z) - v).length() < 2.2:
				blocked = true
				break
		if blocked:
			continue
		placed.append(Vector3(x, 0, z))
		var kind: String = decor[placed.size() % decor.size()]
		if kind == "rock" and rng.randf() < 0.55:
			var rc: Color = rock if rng.randf() < 0.6 else rock_l
			_rock(Vector3(x, 0, z), rng.randf_range(0.32, 0.85), rc, rock_l.lightened(0.12))
		else:
			_tree_hd(Vector3(x, 0, z), kind, flora, flora_l)

func _tree(pos: Vector3, kind: String, flora: Color, flora_l: Color) -> void:
	var trunk := flora_l if kind != "charred" else Color("1a1512")
	match kind:
		"pine":
			MeshKit.cyl(self, 0.16, 1.5, pos + Vector3(0, 0.75, 0), trunk, 6)
			for k in 3:
				MeshKit.cone(self, 0.95 - 0.22 * k, 1.5, pos + Vector3(0, 1.5 + k * 0.75, 0), flora if k % 2 == 0 else Color(flora.r * 1.2, flora.g * 1.2, flora.b * 1.2), 7)
		"willow":
			MeshKit.cyl(self, 0.2, 2.4, pos + Vector3(0, 1.2, 0), trunk, 6)
			MeshKit.sphere(self, 1.5, pos + Vector3(0, 2.9, 0), flora, 7)
			for k in 5:
				var a := TAU * float(k) / 5.0
				MeshKit.cyl(self, 0.06, 1.6, pos + Vector3(cos(a) * 1.1, 2.0, sin(a) * 1.1), flora_l, 4)
		"palm":
			for k in 4:
				var a := TAU * float(k) / 4.0 + 0.4
				MeshKit.box(self, Vector3(0.08, 2.6, 0.3), pos + Vector3(cos(a) * 0.9, 1.5, sin(a) * 0.9), flora, Vector3(0.5, a, 0))
			MeshKit.cyl(self, 0.14, 3.0, pos + Vector3(0, 1.5, 0), trunk, 6)
		"charred":
			MeshKit.cyl(self, 0.15, 2.4, pos + Vector3(0, 1.2, 0), Color("15110f"), 5, Vector3(0.06, 0, 0.05))
			for k in 3:
				MeshKit.cyl(self, 0.06, 0.9, pos + Vector3(0.2 * k, 2.2 + 0.3 * k, -0.2 * k), Color("15110f"), 4, Vector3(0.4, 0.8 * k, 0))
		_:
			MeshKit.cyl(self, 0.18, 2.0, pos + Vector3(0, 1.0, 0), trunk, 6)
			MeshKit.sphere(self, 1.2, pos + Vector3(0, 2.4, 0), flora, 7)
			MeshKit.sphere(self, 0.75, pos + Vector3(0.6, 2.0, 0.5), flora_l, 6)

# ---------------------------------------------------------------- 高模：地形

func _hash2(x: float, z: float) -> float:
	return fmod(abs(sin(x * 12.9898 + z * 78.233) * 43758.5453), 1.0)

func _ground_h(x: float, z: float) -> float:
	# 起伏保持在路面以下，避免和路面/地台穿插
	var n := sin(x * 0.42) * cos(z * 0.37) * 0.012 + sin(x * 1.1 + z * 0.8) * 0.006
	return -0.035 + n

func _build_ground() -> void:
	var base: Color = biome["earth"]
	var dark: Color = biome["earth_d"]
	var rock: Color = biome["rock"]
	var grass: Color = biome["flora"]
	var s := Soup.new()
	var half := 22.0
	var cells := 36
	var st := half * 2.0 / float(cells)
	for ix in cells:
		for iz in cells:
			var x0 := -half + float(ix) * st
			var x1 := x0 + st
			var z0 := -half + float(iz) * st
			var z1 := z0 + st
			var p00 := Vector3(x0, _ground_h(x0, z0), z0)
			var p10 := Vector3(x1, _ground_h(x1, z0), z0)
			var p11 := Vector3(x1, _ground_h(x1, z1), z1)
			var p01 := Vector3(x0, _ground_h(x0, z1), z1)
			var c00 := _ground_col(Vector2(x0, z0), base, dark, rock, grass)
			var c10 := _ground_col(Vector2(x1, z0), base, dark, rock, grass)
			var c11 := _ground_col(Vector2(x1, z1), base, dark, rock, grass)
			var c01 := _ground_col(Vector2(x0, z1), base, dark, rock, grass)
			var n := Vector3.UP
			s.quad4(p00, p10, p11, p01, n, c00, c10, c11, c01)
	s.instance(self, "ground")

func _ground_col(p: Vector2, base: Color, dark: Color, rock: Color, grass: Color) -> Color:
	var h := _hash2(p.x * 1.7, p.y * 1.7)
	var h2 := _hash2(p.x * 5.3 + 11.0, p.y * 5.3 + 7.0)
	var big := sin(p.x * 0.33 + 1.2) * cos(p.y * 0.29 - 0.8)
	var col := base.lerp(dark, 0.12 + 0.3 * h)
	if big > 0.0:
		col = col.lerp(dark, 0.28 * big)
	else:
		col = col.lerp(grass, 0.14 * (-big))
	if h2 > 0.62:
		col = col.lerp(rock, 0.28 * (h2 - 0.62) / 0.38)
	if h2 < 0.18:
		col = col.lerp(grass, 0.35)
	col = col.lerp(dark, clampf(0.12 - 0.02 * float(int(p.x + 22) % 5), 0.0, 0.2))
	return col.darkened(0.08)

func _build_cliff() -> void:
	var s := Soup.new()
	var half := 22.0
	var seg := 26
	var ring: Array[Vector2] = []
	for i in seg:
		ring.append(Vector2(-half + 2.0 * half * float(i) / float(seg), -half))
	for i in seg:
		ring.append(Vector2(half, -half + 2.0 * half * float(i) / float(seg)))
	for i in seg:
		ring.append(Vector2(half - 2.0 * half * float(i) / float(seg), half))
	for i in seg:
		ring.append(Vector2(-half, half - 2.0 * half * float(i) / float(seg)))
	var n := ring.size()
	var top_c: Color = biome["earth_d"]
	var mid_c: Color = biome["rock"].darkened(0.25)
	var low_c: Color = biome["rock"].darkened(0.62)
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var mid := (a + b) * 0.5
		var outv := Vector3(mid.x, 0, mid.y).normalized()
		var depth := 4.2 + 2.4 * _hash2(mid.x * 0.9, mid.y * 0.9)
		var wob := 0.12 + 0.5 * _hash2(mid.x * 2.3 + 5.0, mid.y * 2.3)
		var a_top := Vector3(a.x, -0.02, a.y) + outv * wob
		var b_top := Vector3(b.x, -0.02, b.y) + outv * wob
		var bands: Array[float] = [0.0, 0.28, 0.62, 1.0]
		var cols: Array[Color] = [top_c, mid_c, mid_c.darkened(0.2), low_c]
		for k in 3:
			var u0: float = bands[k]
			var u1: float = bands[k + 1]
			var a0 := a_top + Vector3(0, -depth * u0, 0) - outv * (wob * 0.3 * float(k))
			var b0 := b_top + Vector3(0, -depth * u0, 0) - outv * (wob * 0.3 * float(k))
			var a1 := a_top + Vector3(0, -depth * u1, 0) - outv * (wob * 0.35 * float(k + 1))
			var b1 := b_top + Vector3(0, -depth * u1, 0) - outv * (wob * 0.35 * float(k + 1))
			var shade := 0.9 + 0.2 * _hash2(mid.x * 3.1, mid.y * 3.1 + float(k))
			var c0: Color = cols[k]
			var c1: Color = cols[k + 1]
			s.quad4(a0, b0, b1, a1, outv, c0, c0, c1, c1)
		# 崖壁上贴几块凸出的岩块
		if _hash2(mid.x * 7.7 + 3.0, mid.y * 7.7) > 0.72:
			var rp := Vector2(mid.x + outv.x * (wob + 0.3), mid.y + outv.z * (wob + 0.3))
			var rs: float = 0.5 + 0.7 * _hash2(mid.x * 1.3, mid.y * 1.3)
			s.sphere(Vector3(rp.x, -depth * 0.45, rp.y), rs, mid_c.darkened(0.1), 7, 5, Vector3(1.3, 0.9, 1.3), 0.5, 0.9)
	# 崖顶亮边：沿边缘压一条浅色土带
	for i in n:
		var a2 := ring[i]
		var b2 := ring[(i + 1) % n]
		var m2 := (a2 + b2) * 0.5
		var ov := Vector3(m2.x, 0, m2.y).normalized()
		var edge_c: Color = biome["earth"].lightened(0.22)
		s.quad4(Vector3(a2.x, 0.012, a2.y), Vector3(b2.x, 0.012, b2.y),
			Vector3(b2.x, -0.02, b2.y), Vector3(a2.x, -0.02, a2.y), ov, edge_c, edge_c, edge_c.darkened(0.5), edge_c.darkened(0.5))
	# 底部暗板
	var bm := Soup.new()
	bm.box(Vector3(0, -7.0, 0), Vector3(46, 0.4, 46), Color("0c0a10"), Basis.IDENTITY, 0.4, 0.8)
	bm.instance(self, "cliff_bottom")
	s.instance(self, "cliff")

func _rock(pos: Vector3, sc: float, col: Color, col_l: Color) -> void:
	var s := Soup.new()
	var seed := _hash2(pos.x, pos.z)
	s.sphere(pos + Vector3(0, sc * 0.32, 0), sc * 0.62, col, 8, 6, Vector3(1.25, 0.85 + 0.25 * seed, 1.1), 0.5, 1.0)
	s.sphere(pos + Vector3(sc * 0.4, sc * 0.2, sc * 0.25), sc * 0.36, col_l, 7, 5, Vector3(1.1, 0.8, 1.0), 0.5, 1.0)
	s.sphere(pos + Vector3(-sc * 0.34, sc * 0.15, -sc * 0.3), sc * 0.3, col.darkened(0.2), 7, 5, Vector3(1.0, 0.7, 1.2), 0.45, 0.95)
	if seed > 0.5:
		s.sphere(pos + Vector3(sc * 0.1, sc * 0.55, -sc * 0.15), sc * 0.26, col_l.lightened(0.1), 6, 4, Vector3(1.2, 0.6, 1.0), 0.6, 1.0)
	# 顶部薄苔/灰
	s.sphere(pos + Vector3(0, sc * 0.62, 0), sc * 0.34, biome["flora"].darkened(0.3), 6, 4, Vector3(1.1, 0.35, 1.1), 0.8, 1.0)
	s.instance(self, "rock")

func _build_detail() -> void:
	# 草簇 / 碎石 / 白骨：全部烘进一张网格，省节点
	var s := Soup.new()
	var grass_c: Color = biome["flora_l"]
	var rock_c: Color = biome["rock"]
	var tries := 0
	var placed := 0
	while placed < 130 and tries < 900:
		tries += 1
		var x := rng.randf_range(-20.0, 20.0)
		var z := rng.randf_range(-20.0, 20.0)
		var v := Vector2(x, z)
		if _poly_min_dist(pts, v) < ROAD_HALF + 0.5:
			continue
		var near_pad := false
		for p in pads:
			if (Vector2(float(p["x"]), float(p["z"])) - v).length() < 1.4:
				near_pad = true
				break
		if near_pad:
			continue
		placed += 1
		var kind := _hash2(x * 3.3, z * 3.3)
		if kind < 0.68:
			# 草簇：几片斜出的窄叶
			var blades := 3 + int(kind * 5.0)
			for b in blades:
				var a := TAU * float(b) / float(blades) + kind * 3.0
				s.beam(Vector3(x, -0.02, z), Vector3(x + cos(a) * 0.12, 0.16 + 0.12 * _hash2(x + float(b), z), z + sin(a) * 0.12), 0.022, 0.003, 3, grass_c, 0.0, 0.6, 1.0)
		elif kind < 0.9:
			s.sphere(Vector3(x, 0.02, z), 0.07 + 0.08 * kind, rock_c, 5, 3, Vector3(1.2, 0.6, 1.1), 0.5, 0.9)
		else:
			# 白骨
			var ry := rng.randf_range(0, TAU)
			s.beam(Vector3(x, 0.02, z), Vector3(x + cos(ry) * 0.3, 0.03, z + sin(ry) * 0.3), 0.028, 0.02, 4, Color("d8d2c0"))
			s.sphere(Vector3(x + cos(ry) * 0.36, 0.06, z + sin(ry) * 0.36), 0.06, Color("cfc8b4"), 6, 4, Vector3(1.1, 0.9, 1.0), 0.6, 1.0)
	s.instance(self, "detail")

# ---------------------------------------------------------------- 高模：植被

func _tree_hd(pos: Vector3, kind: String, flora: Color, flora_l: Color) -> void:
	var s := Soup.new()
	var h := _hash2(pos.x, pos.z)
	var trunk_c := flora_l.darkened(0.45)
	var rot := h * TAU
	match kind:
		"pine":
			s.beam(pos, pos + Vector3(0, 1.5, 0), 0.19, 0.1, 6, trunk_c, rot, 0.55, 1.0)
			var tiers := 4
			for k in tiers:
				var y := 1.1 + float(k) * 0.52
				var r := 1.0 - 0.19 * float(k)
				s.cone(pos + Vector3(0, y, 0), r, 1.0, flora.lightened(0.06).darkened(0.04 * float(k)), 8, rot + float(k) * 0.4, 0.62)
				# 外挑的枝尖，让轮廓不那么「圆锥」
				for b in 7:
					var a := TAU * float(b) / 7.0 + float(k) * 0.6
					s.beam(pos + Vector3(cos(a) * r * 0.5, y + 0.16, sin(a) * r * 0.5),
						pos + Vector3(cos(a) * r * 0.95, y - 0.1, sin(a) * r * 0.95), 0.05, 0.012, 3, flora_l)
			s.cone(pos + Vector3(0, 1.1 + float(tiers) * 0.52 - 0.1, 0), 0.3, 0.7, flora_l.lightened(0.1), 6)
		"willow":
			var tp := pos
			for k in 3:
				var p1: Vector3 = tp + Vector3(sin(float(k) * 1.1 + h) * 0.14, 0.75, cos(float(k) * 1.1) * 0.1)
				s.beam(tp, p1, 0.2 - 0.03 * float(k), 0.15 - 0.03 * float(k), 6, trunk_c)
				tp = p1
			var crown := tp + Vector3(0, 0.5, 0)
			for k in 6:
				var a := TAU * float(k) / 6.0
				s.sphere(crown + Vector3(cos(a) * 0.7, 0.1 * sin(a * 2.0), sin(a) * 0.7), 0.85, flora, 9, 6, Vector3(1.0, 0.8, 1.0), 0.55, 1.0)
			s.sphere(crown + Vector3(0, 0.4, 0), 0.8, flora_l, 9, 6, Vector3(1.0, 0.75, 1.0), 0.7, 1.0)
			for k in 9:
				var a2 := TAU * float(k) / 9.0 + h
				var r2 := 0.9 + 0.35 * _hash2(pos.x + float(k), pos.z)
				var top := crown + Vector3(cos(a2) * r2, -0.1, sin(a2) * r2)
				s.beam(top, top + Vector3(cos(a2) * 0.12, -1.35 - 0.3 * _hash2(float(k), pos.x), sin(a2) * 0.12), 0.035, 0.012, 3, flora_l.darkened(0.1))
				s.sphere(top + Vector3(0, -1.35, 0), 0.09, flora_l, 5, 3, Vector3(0.8, 1.4, 0.8), 0.7, 1.0)
		"palm":
			var tp2 := pos
			for k in 6:
				var bend := float(k) * 0.22
				var p2: Vector3 = tp2 + Vector3(sin(bend) * 0.28, 0.56, cos(bend) * 0.12)
				s.beam(tp2, p2, 0.19 - 0.025 * float(k), 0.16 - 0.025 * float(k), 6, trunk_c, 0.0, 0.6, 1.0)
				tp2 = p2
			var crown2 := tp2
			s.sphere(crown2 + Vector3(0, 0.1, 0), 0.2, flora_l.darkened(0.2), 7, 5)
			for k in 8:
				var a3 := TAU * float(k) / 8.0 + h
				var side := Vector3(-sin(a3), 0.0, cos(a3))
				var outd := Vector3(cos(a3), 0.0, sin(a3))
				# 每片叶：四段主脉 + 沿脉的宽叶片，末端下垂
				var p_prev := crown2 + Vector3(0, 0.08, 0)
				var w_prev := 0.16
				for b in 4:
					var u := (float(b) + 1.0) / 4.0
					var drop := 0.9 * u * u
					var p_cur: Vector3 = crown2 + outd * (1.75 * u) + Vector3(0, 0.42 - drop, 0)
					var w_cur := 0.2 * (1.0 - 0.62 * u)
					# 叶片（左右各一条带）
					var c_mid: Color = flora.lightened(0.05) if b < 2 else flora.darkened(0.08)
					s.quad(p_prev + side * w_prev, p_cur + side * w_cur, p_cur - side * w_cur, p_prev - side * w_prev,
						Vector3.UP, c_mid)
					s.beam(p_prev, p_cur, 0.035, 0.014, 3, flora_l.darkened(0.25), 0.0, 0.8, 1.0)
					p_prev = p_cur
					w_prev = w_cur
			for k in 3:
				var a4 := TAU * float(k) / 3.0
				s.sphere(crown2 + Vector3(cos(a4) * 0.22, -0.12, sin(a4) * 0.22), 0.11, Color("5a4632"), 6, 4)
		"charred":
			var burnt := Color("171210")
			var burnt_l := Color("2a211c")
			s.beam(pos, pos + Vector3(0.06, 1.8, -0.04), 0.22, 0.12, 5, burnt, 0.0, 0.5, 1.0)
			for k in 4:
				var a5 := TAU * float(k) / 4.0 + h
				var p3: Vector3 = pos + Vector3(0.05, 1.1 + 0.28 * float(k), -0.03)
				var p4: Vector3 = p3 + Vector3(cos(a5) * 0.55, 0.5, sin(a5) * 0.55)
				s.beam(p3, p4, 0.09, 0.03, 4, burnt_l)
				s.beam(p4, p4 + Vector3(cos(a5) * 0.2, 0.24, sin(a5) * 0.2), 0.03, 0.006, 3, burnt)
			# 余烬
			for k in 6:
				var a6 := TAU * float(k) / 6.0 + 2.0
				s.sphere(pos + Vector3(cos(a6) * 0.36, 0.05 + 0.5 * _hash2(float(k), h), sin(a6) * 0.36), 0.045, Color("ff6a20"), 5, 3, Vector3.ONE, 0.9, 1.0)
		_:
			# 落叶乔木：粗树干 + 三根主枝 + 五团叶簇（明暗两层）
			s.beam(pos, pos + Vector3(0.04, 1.75, 0.02), 0.23, 0.12, 7, trunk_c, 0.0, 0.5, 1.0)
			s.beam(pos + Vector3(0, 0.05, 0), pos + Vector3(0.16, 0.32, -0.1), 0.26, 0.18, 7, trunk_c.darkened(0.15), 0.0, 0.4, 0.9)
			for k in 3:
				var a7 := TAU * float(k) / 3.0 + h
				var bp := pos + Vector3(0, 1.25 + 0.16 * float(k), 0)
				var bt := bp + Vector3(cos(a7) * 0.62, 0.72, sin(a7) * 0.62)
				s.beam(bp, bt, 0.095, 0.05, 5, trunk_c)
				s.sphere(bt + Vector3(0, 0.14, 0), 0.42 + 0.1 * _hash2(float(k), h), flora.lightened(0.05), 8, 5, Vector3(1.05, 0.9, 1.05), 0.78, 1.0)
			for k in 5:
				var a8 := TAU * float(k) / 5.0 + 0.6
				var r3: float = 0.42 + 0.22 * _hash2(float(k), pos.z)
				var cy: float = 2.35 + 0.32 * sin(float(k) * 1.7)
				s.sphere(pos + Vector3(cos(a8) * (0.3 + r3), cy, sin(a8) * (0.3 + r3)), 0.5 + 0.1 * _hash2(float(k) * 3.0, pos.x),
					flora if k % 2 == 0 else flora.lightened(0.12), 8, 5, Vector3(1.1, 0.85, 1.1), 0.8, 1.0)
			s.sphere(pos + Vector3(0, 2.95, 0), 0.52, flora_l.lightened(0.1), 8, 5, Vector3(1.2, 0.8, 1.2), 0.85, 1.0)
	var mi := s.instance(self, "tree")
	mi.rotation.y = rng.randf_range(0.0, TAU)
	mi.scale = Vector3.ONE * rng.randf_range(0.82, 1.2)

# ---------------------------------------------------------------- 高模：建造台

func _build_pads() -> void:
	_pad_nodes.clear()
	var stone: Color = biome["rock"]
	var stone_l: Color = biome["rock_l"]
	var earth: Color = biome["earth_d"]
	for i in pads.size():
		var pad: Dictionary = pads[i]
		var root := Node3D.new()
		root.position = Vector3(pad["x"], 0, pad["z"])
		add_child(root)
		var s := Soup.new()
		# 台基：12 棱石台 + 一圈外凸的毛石 + 顶面石盘
		s.cyl(Vector3(0, 0.1, 0), 1.22, 1.12, 0.2, stone, 12, 0.0, 0.45, 0.85)
		for k in 12:
			var a := TAU * float(k) / 12.0
			if k % 3 == 0:
				s.box(Vector3(cos(a) * 1.02, 0.12, sin(a) * 1.02), Vector3(0.28, 0.18, 0.3), stone_l, Basis(Vector3.UP, -a))
		s.cyl(Vector3(0, 0.235, 0), 1.05, 1.0, 0.055, stone_l.darkened(0.12), 12, 0.0, 0.8, 1.0)
		s.cyl(Vector3(0, 0.02, 0), 1.3, 1.28, 0.05, earth, 12, 0.0, 0.4, 0.6)
		# 四角石墩 + 刻痕
		for k in 4:
			var a2 := TAU * float(k) / 4.0 + PI * 0.25
			s.beam(Vector3(cos(a2) * 0.94, 0.22, sin(a2) * 0.94), Vector3(cos(a2) * 0.94, 0.46, sin(a2) * 0.94), 0.09, 0.075, 4, stone_l, 0.0, 0.6, 1.0)
			s.box(Vector3(cos(a2) * 0.94, 0.46, sin(a2) * 0.94), Vector3(0.14, 0.04, 0.14), stone, Basis.IDENTITY, 0.8, 1.0)
		s.instance(root, "pad")
		# 可建造高亮圈
		var glow := Node3D.new()
		glow.position = Vector3(0, 0.29, 0)
		glow.visible = false
		root.add_child(glow)
		for k in 12:
			var a3 := TAU * float(k) / 12.0
			var mi := MeshKit.box(glow, Vector3(0.16, 0.03, 0.05), Vector3(cos(a3) * 1.0, 0, sin(a3) * 1.0), Color("ffb060"), Vector3(0, -a3 + PI * 0.5, 0), 1.6)
			if mi != null:
				mi.material_override = MeshKit.mat(Color("ffb060"), 1.6, 0.4)
		pad["node"] = root
		pad["glow"] = glow
		_pad_nodes.append(root)
