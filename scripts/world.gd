extends Node3D
## Complete Procedural World, Layout, 6x6 Chunked Terrain Slab, Water/Waterfall, Props, Flora,
## and Smooth Biome Look Controller (ported & enhanced from 30-layout.js, 31-terrain.js, 29-biome.js).

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")
const Soup = preload("res://scripts/soup.gd")
const Defs = preload("res://scripts/defs.gd")
const Props = preload("res://scripts/props.gd")
const Flora = preload("res://scripts/flora.gd")

const MAP_HALF := 18.0
const CHUNK_G := 6 # 6x6 = 36 animated terrain chunks
const GRID_RES := 72 # 12x12 terrain cells per chunk (high detail!)

# Active level & biome state
var biomes: Array[Dictionary] = []
var biome_idx := 0
var biome: Dictionary = {}
var level_num := 1
var level_seed := 1
var mirrored := false

# Path, stream, pads, landmarks
var path_pts: Array[Vector3] = []
var path_cum: PackedFloat32Array = PackedFloat32Array()
var path_len := 1.0
var stream_pts: Array[Vector3] = []
var ponds: Array[Dictionary] = [] # [{x, z, r}]
var pads: Array[Dictionary] = [] # [{x, y, z, occupied, tower, chunk_idx, marker_pos}]
var bridge_pos := Vector3.ZERO
var bridge_yaw := 0.0
var keep_pos := Vector3.ZERO
var keep_yaw := 0.0
var cave_pos := Vector3.ZERO
var cave_yaw := 0.0
var beacon_flame_pos := Vector3.ZERO
var fall_at: Dictionary = {} # {has, pos, dir, top_y, bot_y}

# World dynamic emitters registered for FX/Lighting
var sconce_positions: Array[Vector3] = []
var lantern_positions: Array[Vector3] = []
var lava_vents: Array[Vector3] = []
var mushroom_lights: Array[Vector3] = []
var wisp_zones: Array[Vector3] = []

# Animated crumble/rise chunks & landmarks
# Each entry: {node: Node3D, base: Vector3, spin: Vector3, delay: float, kind: String, idx: int}
var pieces: Array[Dictionary] = []
var chunk_nodes: Array[Node3D] = []
var keep_node: Node3D = null
var beacon_node: Node3D = null
var cave_node: Node3D = null
var bridge_node: Node3D = null

var _relief_seed := 13
var _water_level := -0.45

# Smoothly interpolated biome visual state
var _cur_look: Dictionary = {}
var _has_look := false


func _ready() -> void:
	TX.ensure()
	biomes = Defs.get_biomes()
	biome = biomes[0]


func get_biome_count() -> int:
	return biomes.size()


func get_biome_by_key(key: String) -> int:
	for i in biomes.size():
		if String(biomes[i]["key"]) == key:
			return i
	return 0


# ============================================================================
# World Generation
# ============================================================================

func build_level(p_level: int, p_biome_idx: int, p_seed: int = -1) -> void:
	clear_world()
	level_num = p_level
	biome_idx = posmod(p_biome_idx, biomes.size())
	biome = biomes[biome_idx]
	level_seed = p_seed if p_seed >= 0 else (p_level * 977 + biome_idx * 313 + 42)
	mirrored = (p_level % 2) == 0
	_relief_seed = (level_seed * 17 + 31) & 0x7fffffff

	var rng := U.make_rng(level_seed)
	Soup.set_rng(rng)

	_generate_layout(rng)
	_build_chunks_and_dressing(rng)
	_build_landmarks(rng)


func clear_world() -> void:
	for ch in get_children():
		ch.queue_free()
	pieces.clear()
	chunk_nodes.clear()
	keep_node = null
	beacon_node = null
	cave_node = null
	bridge_node = null
	path_pts.clear()
	stream_pts.clear()
	ponds.clear()
	pads.clear()
	sconce_positions.clear()
	lantern_positions.clear()
	lava_vents.clear()
	mushroom_lights.clear()
	wisp_zones.clear()
	fall_at = {"has": false}


# ============================================================================
# Layout (30-layout.js): Winding Road, Stream, Bridge, Ponds, Pads
# ============================================================================

func _m_pt(x: float, z: float) -> Vector2:
	return Vector2(z, x) if mirrored else Vector2(x, z)


func _generate_layout(rng: U.Rng) -> void:
	# Winding S-curve road from Cave (NW) to Keep (SE)
	var ctrl: Array[Vector2] = [
		Vector2(-14.6, -12.8),
		Vector2(-7.5 + rng.frange(-1.8, 1.8), -11.2 + rng.frange(-1.8, 1.8)),
		Vector2(2.2 + rng.frange(-2.2, 2.2), -5.8 + rng.frange(-2.0, 2.0)),
		Vector2(-5.4 + rng.frange(-2.2, 2.2), 2.2 + rng.frange(-2.0, 2.0)),
		Vector2(4.6 + rng.frange(-2.0, 2.0), 8.2 + rng.frange(-1.8, 1.8)),
		Vector2(12.8, 12.2),
	]
	if mirrored:
		for i in ctrl.size():
			ctrl[i] = Vector2(ctrl[i].y, ctrl[i].x)

	# Catmull-Rom smooth spline sampling
	var raw_2d: Array[Vector2] = []
	var steps_per_seg := 16
	for i in ctrl.size() - 1:
		var p0 := ctrl[maxi(0, i - 1)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(ctrl.size() - 1, i + 2)]
		for s in steps_per_seg:
			var t := float(s) / float(steps_per_seg)
			var t2 := t * t
			var t3 := t2 * t
			var pt := 0.5 * (
				(2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			)
			raw_2d.append(pt)
	raw_2d.append(ctrl[ctrl.size() - 1])

	# Generate crossing stream (if enabled by biome)
	var terr: Dictionary = biome["terrain"]
	var has_stream: bool = bool(terr.get("stream", true))
	var cross_idx := int(raw_2d.size() * 0.48)
	var cross_p := raw_2d[cross_idx]
	var road_tan := (raw_2d[mini(raw_2d.size() - 1, cross_idx + 2)] - raw_2d[maxi(0, cross_idx - 2)]).normalized()
	var perp := Vector2(-road_tan.y, road_tan.x)

	if has_stream:
		var s_ctrl: Array[Vector2] = [
			cross_p - perp * 22.0 + road_tan * rng.frange(-3.0, 3.0),
			cross_p - perp * 11.0 + road_tan * rng.frange(-2.2, 2.2),
			cross_p,
			cross_p + perp * 11.0 + road_tan * rng.frange(-2.2, 2.2),
			cross_p + perp * 22.5 + road_tan * rng.frange(-3.0, 3.0),
		]
		for i in s_ctrl.size() - 1:
			var p0 := s_ctrl[maxi(0, i - 1)]
			var p1 := s_ctrl[i]
			var p2 := s_ctrl[i + 1]
			var p3 := s_ctrl[mini(s_ctrl.size() - 1, i + 2)]
			for s in 12:
				var t := float(s) / 12.0
				var t2 := t * t
				var t3 := t2 * t
				var pt := 0.5 * (
					(2.0 * p1) +
					(-p0 + p2) * t +
					(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
					(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
				)
				stream_pts.append(Vector3(pt.x, 0.0, pt.y))

	# Biome ponds (away from road & landmarks)
	var n_ponds := int(terr.get("ponds", 1))
	for _i in n_ponds * 12:
		if ponds.size() >= n_ponds:
			break
		var px := rng.frange(-13.5, 13.5)
		var pz := rng.frange(-13.5, 13.5)
		var pr := rng.frange(2.0, 3.3)
		if _dist_to_poly_2d(px, pz, raw_2d) < pr + 3.0:
			continue
		if Vector2(px, pz).distance_to(ctrl[0]) < 6.0 or Vector2(px, pz).distance_to(ctrl[ctrl.size() - 1]) < 6.5:
			continue
		var ok := true
		for po in ponds:
			if U.dist2(px, pz, float(po["x"]), float(po["z"])) < pr + float(po["r"]) + 2.5:
				ok = false
				break
		if ok:
			ponds.append({"x": px, "z": pz, "r": pr})

	# Store 2D path first so height_at() can query road distance
	path_pts.clear()
	for pt in raw_2d:
		path_pts.append(Vector3(pt.x, 0.0, pt.y))

	# Compute keep & cave positions & orientations
	var c0 := path_pts[0]
	var c1 := path_pts[3]
	cave_pos = Vector3(c0.x, 0.0, c0.z)
	cave_yaw = atan2(c1.x - c0.x, c1.z - c0.z)

	var k0 := path_pts[path_pts.size() - 1]
	var k1 := path_pts[path_pts.size() - 4]
	keep_pos = Vector3(k0.x, 0.0, k0.z)
	keep_yaw = atan2(k1.x - k0.x, k1.z - k0.z)

	bridge_pos = Vector3(cross_p.x, 0.0, cross_p.y)
	bridge_yaw = atan2(-road_tan.y, road_tan.x)

	# Generate 11-12 strategic tower pads along the road (avoiding stream, ponds, keep, cave)
	var pad_candidates: Array[Vector2] = []
	for i in range(6, path_pts.size() - 7, 3):
		var p := Vector2(path_pts[i].x, path_pts[i].z)
		var t_dir := (Vector2(path_pts[i + 1].x, path_pts[i + 1].z) - Vector2(path_pts[i - 1].x, path_pts[i - 1].z)).normalized()
		var n_dir := Vector2(-t_dir.y, t_dir.x)
		for side in [-1.0, 1.0]:
			var cand: Vector2 = p + n_dir * side * rng.frange(2.75, 3.65)
			if absf(cand.x) > MAP_HALF - 2.6 or absf(cand.y) > MAP_HALF - 2.6:
				continue
			pad_candidates.append(cand)

	# Shuffle candidates deterministically
	for i in range(pad_candidates.size() - 1, 0, -1):
		var j := rng.irange(0, i)
		var tmp := pad_candidates[i]
		pad_candidates[i] = pad_candidates[j]
		pad_candidates[j] = tmp

	for cand in pad_candidates:
		if pads.size() >= 12:
			break
		if dist_to_road(cand.x, cand.y) < 2.25:
			continue
		if dist_to_stream(cand.x, cand.y) < 2.35:
			continue
		if _in_pond(cand.x, cand.y, 1.6):
			continue
		if U.dist2(cand.x, cand.y, keep_pos.x, keep_pos.z) < 5.8:
			continue
		if U.dist2(cand.x, cand.y, cave_pos.x, cave_pos.z) < 5.0:
			continue
		var too_close := false
		for ep in pads:
			if U.dist2(cand.x, cand.y, float(ep["x"]), float(ep["z"])) < 4.2:
				too_close = true
				break
		if too_close:
			continue
		pads.append({
			"x": cand.x, "y": 0.0, "z": cand.y,
			"occupied": false, "tower": null,
			"chunk_idx": chunk_index_at(cand.x, cand.y),
		})

	# Now finalize 3D Y coordinates using height_at()
	path_cum.resize(path_pts.size())
	var acc := 0.0
	for i in path_pts.size():
		var p := path_pts[i]
		var y := top_at(p.x, p.z)
		path_pts[i] = Vector3(p.x, y, p.z)
		if i > 0:
			acc += path_pts[i].distance_to(path_pts[i - 1])
		path_cum[i] = acc
	path_len = maxf(1.0, acc)

	cave_pos.y = height_at(cave_pos.x, cave_pos.z)
	keep_pos.y = height_at(keep_pos.x, keep_pos.z)
	bridge_pos.y = height_at(bridge_pos.x, bridge_pos.z)
	for pd in pads:
		pd["y"] = height_at(float(pd["x"]), float(pd["z"]))


func _dist_to_poly_2d(x: float, z: float, pts: Array[Vector2]) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((Vector2(x, z) - a).dot(ab) / l2, 0.0, 1.0)
		var d := Vector2(x, z).distance_to(a + ab * t)
		if d < best:
			best = d
	return best


func dist_to_road(x: float, z: float) -> float:
	var best := 1e9
	for i in range(0, path_pts.size() - 1, 2):
		var a := path_pts[i]
		var b := path_pts[mini(path_pts.size() - 1, i + 2)]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		var t := 0.0 if l2 < 1e-6 else clampf(((x - a.x) * abx + (z - a.z) * abz) / l2, 0.0, 1.0)
		var dx := x - (a.x + abx * t)
		var dz := z - (a.z + abz * t)
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
	return best


func dist_to_stream(x: float, z: float) -> float:
	if stream_pts.size() < 2:
		return 1e9
	var best := 1e9
	for i in stream_pts.size() - 1:
		var a := stream_pts[i]
		var b := stream_pts[i + 1]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		var t := 0.0 if l2 < 1e-6 else clampf(((x - a.x) * abx + (z - a.z) * abz) / l2, 0.0, 1.0)
		var dx := x - (a.x + abx * t)
		var dz := z - (a.z + abz * t)
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
	return best


func _in_pond(x: float, z: float, margin: float = 0.0) -> bool:
	for po in ponds:
		if U.dist2(x, z, float(po["x"]), float(po["z"])) < float(po["r"]) + margin:
			return true
	return false


func sample_path(dist_along: float) -> Dictionary:
	var d := clampf(dist_along, 0.0, path_len)
	var lo := 0
	var hi := path_cum.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if path_cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg_l := maxf(1e-5, path_cum[hi] - path_cum[lo])
	var f := clampf((d - path_cum[lo]) / seg_l, 0.0, 1.0)
	var p := path_pts[lo].lerp(path_pts[hi], f)
	var dir := (path_pts[hi] - path_pts[lo])
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		dir = Vector3(1, 0, 0)
	else:
		dir = dir.normalized()
	return {"pos": p, "dir": dir, "u": d / path_len}


# ============================================================================
# Continuous 3D Heightfield (height_at & top_at)
# ============================================================================

func height_at(x: float, z: float) -> float:
	var rel: Dictionary = biome.get("relief", {"hills": 0.9, "hf": 0.07, "detail": 0.3, "dunes": 0.0})
	var hf: float = float(rel["hf"])
	var hills: float = float(rel["hills"])
	var detail: float = float(rel["detail"])
	var dunes: float = float(rel["dunes"])

	var h := (U.fbm(x * hf + 13.0, z * hf + 7.0, _relief_seed, 3) - 0.45) * 2.4 * hills
	h += (U.vnoise(x * 0.24, z * 0.24, _relief_seed + 5) - 0.5) * detail
	if dunes > 0.01:
		var w := sin(x * 0.32 + z * 0.22 + U.vnoise(x * 0.1, z * 0.1, _relief_seed + 11) * 2.2)
		h += (w * 0.5 + 0.5) * dunes

	# Flatten around road (gentle natural crown)
	var dr := dist_to_road(x, z)
	var road_k := 1.0 - U.smooth(1.05, 3.0, dr)
	h = lerpf(h, clampf(h * 0.32, -0.25, 0.45), road_k)

	# Flatten Keep & Cave plateaus
	var dk := U.dist2(x, z, keep_pos.x, keep_pos.z)
	if dk < 6.2:
		h = lerpf(h, 0.35, 1.0 - U.smooth(3.2, 6.2, dk))
	var dc := U.dist2(x, z, cave_pos.x, cave_pos.z)
	if dc < 5.4:
		h = lerpf(h, 0.25, 1.0 - U.smooth(2.6, 5.4, dc))

	# Flatten Tower Pads into clean build terraces
	for pd in pads:
		var dp := U.dist2(x, z, float(pd["x"]), float(pd["z"]))
		if dp < 2.6:
			var base_h := clampf(h * 0.45 + 0.22, 0.05, 0.85)
			h = lerpf(h, base_h, 1.0 - U.smooth(1.45, 2.6, dp))

	# Carve stream valley bed
	if stream_pts.size() >= 2:
		var ds := dist_to_stream(x, z)
		if ds < 3.4:
			var carve := 1.0 - U.smooth(0.85, 3.4, ds)
			h = lerpf(h, -1.18, carve * 0.92)

	# Carve ponds
	for po in ponds:
		var dp2 := U.dist2(x, z, float(po["x"]), float(po["z"]))
		var pr := float(po["r"])
		if dp2 < pr + 1.8:
			var pc := 1.0 - U.smooth(pr * 0.55, pr + 1.8, dp2)
			h = lerpf(h, -1.05, pc * 0.9)

	# Subtle outer rim cliff drop-off
	var edge := maxf(absf(x), absf(z))
	if edge > MAP_HALF - 1.2:
		h -= U.smooth(MAP_HALF - 1.2, MAP_HALF + 0.2, edge) * 0.45
	return h


func top_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	# Lift walking height smoothly over the stone arch bridge
	if stream_pts.size() >= 2:
		var dx := x - bridge_pos.x
		var dz := z - bridge_pos.z
		var ca := cos(-bridge_yaw)
		var sa := sin(-bridge_yaw)
		var lx := dx * ca - dz * sa
		var lz := dx * sa + dz * ca
		if absf(lx) < 2.8 and absf(lz) < 1.6:
			var arch := cos(clampf(lx / 2.8, -1.0, 1.0) * PI * 0.5)
			h = maxf(h, _water_level + 0.55 + arch * 0.52)
	return h


func chunk_index_at(x: float, z: float) -> int:
	var cs := (MAP_HALF * 2.0) / float(CHUNK_G)
	var gx := clampi(int(floor((x + MAP_HALF) / cs)), 0, CHUNK_G - 1)
	var gz := clampi(int(floor((z + MAP_HALF) / cs)), 0, CHUNK_G - 1)
	return gz * CHUNK_G + gx


# ============================================================================
# 6x6 Chunked Terrain Slab + Water/Waterfall + Props & Biome Flora
# ============================================================================

func _build_chunks_and_dressing(rng: U.Rng) -> void:
	var pal: Dictionary = biome["pal"]
	var terr: Dictionary = biome["terrain"]
	var rel: Dictionary = biome["relief"]
	var cliff_d: float = float(rel.get("cliff", 3.2))
	var cell_per_chunk := GRID_RES / CHUNK_G
	var cs := (MAP_HALF * 2.0) / float(CHUNK_G)
	var step := cs / float(cell_per_chunk)

	var chunk_soups: Array = []
	var water_soups: Array = []
	chunk_soups.resize(CHUNK_G * CHUNK_G)
	water_soups.resize(CHUNK_G * CHUNK_G)
	for i in CHUNK_G * CHUNK_G:
		chunk_soups[i] = Soup.new()
		water_soups[i] = Soup.new()

	var grass_c: Color = pal["grass"]
	var grass_d: Color = pal["grassD"]
	var earth_c: Color = pal["earth"]
	var road_c: Color = pal["road"]
	var road_d: Color = pal["roadD"]
	var mud_c: Color = pal["mud"]
	var strata: Array = pal["strata"]
	var main_layer := float(terr["layer"])
	var bed_layer := float(terr["bed_layer"])
	var road_layer := float(terr["road_layer"])
	var main_rough := float(terr["rough"])
	var cliff_rough := float(terr["cliff_rough"])
	var has_vein := bool(terr["vein"])
	var water_on := bool(biome["water_on"])
	var ember_c := U.col_hex(0xff5a18)

	# 1. Build 6x6 terrain top surface + stratified outer cliffs + water surface
	for gz in CHUNK_G:
		for gx in CHUNK_G:
			var ci := gz * CHUNK_G + gx
			var sp: Soup = chunk_soups[ci]
			var wsp: Soup = water_soups[ci]
			var cx := -MAP_HALF + (float(gx) + 0.5) * cs
			var cz := -MAP_HALF + (float(gz) + 0.5) * cs
			var x0_c := -MAP_HALF + float(gx) * cs
			var z0_c := -MAP_HALF + float(gz) * cs

			# Height & color grid for this chunk
			var H := PackedFloat32Array()
			var COLS: Array[Color] = []
			var LAY := PackedFloat32Array()
			var n1 := cell_per_chunk + 1
			H.resize(n1 * n1)
			COLS.resize(n1 * n1)
			LAY.resize(n1 * n1)

			for j in n1:
				for i in n1:
					var wx := x0_c + float(i) * step
					var wz := z0_c + float(j) * step
					var wy := height_at(wx, wz)
					var idx := j * n1 + i
					H[idx] = wy

					var dr := dist_to_road(wx, wz)
					var ds := dist_to_stream(wx, wz)
					var nv := U.fbm(wx * 0.16, wz * 0.16, _relief_seed + 3, 2)
					var c := U.mix_c(grass_d, grass_c, nv)
					var ly := main_layer
					if wy < _water_level + 0.25 or ds < 2.2:
						var wk := 1.0 - U.smooth(_water_level - 0.1, _water_level + 0.35, wy)
						c = U.mix_c(c, mud_c, maxf(wk, 1.0 - U.smooth(1.0, 2.2, ds)))
						ly = bed_layer if wk > 0.45 else main_layer
					if dr < 1.55:
						var rk := 1.0 - U.smooth(0.85, 1.55, dr)
						# Subtle twin wagon wheel ruts along road
						var rut := 1.0 - U.smooth(0.08, 0.26, absf(dr - 0.46))
						var rc := U.mix_c(road_c, road_d, rut * 0.6 + (1.0 - nv) * 0.25)
						c = U.mix_c(c, rc, rk)
						if rk > 0.48:
							ly = road_layer
					COLS[idx] = c
					LAY[idx] = ly

			# Emit top terrain quads (in chunk-local coordinates!)
			for j in cell_per_chunk:
				for i in cell_per_chunk:
					var i00 := j * n1 + i
					var i10 := i00 + 1
					var i11 := i00 + n1 + 1
					var i01 := i00 + n1
					var lx0 := (x0_c + float(i) * step) - cx
					var lx1 := lx0 + step
					var lz0 := (z0_c + float(j) * step) - cz
					var lz1 := lz0 + step
					var p00 := Vector3(lx0, H[i00], lz0)
					var p10 := Vector3(lx1, H[i10], lz0)
					var p11 := Vector3(lx1, H[i11], lz1)
					var p01 := Vector3(lx0, H[i01], lz1)
					var ly := LAY[i00]
					var rg := 0.84 if ly == road_layer else main_rough
					sp.tri(p00, p10, p11, COLS[i00], ly, rg, {"ca": COLS[i00], "cb": COLS[i10], "cc": COLS[i11], "uvs": 0.38})
					sp.tri(p00, p11, p01, COLS[i00], ly, rg, {"ca": COLS[i00], "cb": COLS[i11], "cc": COLS[i01], "uvs": 0.38})

					# Water surface patch where terrain dips below water level
					if water_on and minf(minf(H[i00], H[i10]), minf(H[i11], H[i01])) < _water_level - 0.02:
						var w00 := Vector3(lx0, _water_level, lz0)
						var w10 := Vector3(lx1, _water_level, lz0)
						var w11 := Vector3(lx1, _water_level, lz1)
						var w01 := Vector3(lx0, _water_level, lz1)
						wsp.quad(w00, w10, w11, w01, Color.WHITE, TX.L_PLAIN, 0.15, {"uvs": 0.25})

			# Stratified stepped outer cliff walls on perimeter chunks
			var sides := []
			if gz == 0:
				sides.append([0, -1])
			if gz == CHUNK_G - 1:
				sides.append([0, 1])
			if gx == 0:
				sides.append([-1, 0])
			if gx == CHUNK_G - 1:
				sides.append([1, 0])

			for sd in sides:
				var sx_dir: int = sd[0]
				var sz_dir: int = sd[1]
				var tiers := 4
				for k in cell_per_chunk:
					var i_a := k if sz_dir != 0 else (0 if sx_dir < 0 else cell_per_chunk)
					var j_a := (0 if sz_dir < 0 else cell_per_chunk) if sz_dir != 0 else k
					var i_b := i_a + (1 if sz_dir != 0 else 0)
					var j_b := j_a + (1 if sx_dir != 0 else 0)
					var ha := H[j_a * n1 + i_a]
					var hb := H[j_b * n1 + i_b]
					var ax := (x0_c + float(i_a) * step) - cx
					var az := (z0_c + float(j_a) * step) - cz
					var bx := (x0_c + float(i_b) * step) - cx
					var bz := (z0_c + float(j_b) * step) - cz
					var y_top_a := ha
					var y_top_b := hb
					for t_i in tiers:
						var f0 := float(t_i) / float(tiers)
						var f1 := float(t_i + 1) / float(tiers)
						var ya0 := lerpf(y_top_a, -cliff_d, f0)
						var yb0 := lerpf(y_top_b, -cliff_d, f0)
						var ya1 := lerpf(y_top_a, -cliff_d, f1)
						var yb1 := lerpf(y_top_b, -cliff_d, f1)
						var jut0 := sin(f0 * PI) * 0.22
						var jut1 := sin(f1 * PI) * 0.22
						var p0 := Vector3(ax + float(sx_dir) * jut0, ya0, az + float(sz_dir) * jut0)
						var p1 := Vector3(bx + float(sx_dir) * jut0, yb0, bz + float(sz_dir) * jut0)
						var p2 := Vector3(bx + float(sx_dir) * jut1, yb1, bz + float(sz_dir) * jut1)
						var p3 := Vector3(ax + float(sx_dir) * jut1, ya1, az + float(sz_dir) * jut1)
						var sc: Color = strata[mini(strata.size() - 1, t_i)]
						var emis := 0.0
						if has_vein and t_i == 2 and U.h2(gx * 16 + k, gz * 16 + t_i, 77) > 0.72:
							sc = ember_c
							emis = 1.85
						# Outward winding depends on edge side
						if sz_dir < 0 or sx_dir > 0:
							sp.quad(p0, p3, p2, p1, sc, TX.L_ROCK, cliff_rough, {"emis": emis, "uvs": 0.34})
						else:
							sp.quad(p0, p1, p2, p3, sc, TX.L_ROCK, cliff_rough, {"emis": emis, "uvs": 0.34})

			# Dark underside cap so tumbling chunks look solid during crumble!
			var hcs := cs * 0.5
			sp.quad(
				Vector3(-hcs, -cliff_d, -hcs), Vector3(-hcs, -cliff_d, hcs),
				Vector3(hcs, -cliff_d, hcs), Vector3(hcs, -cliff_d, -hcs),
				earth_c * 0.45, TX.L_ROCK, 0.95
			)

	# 2. Merge Tower Pads directly into their terrain chunks!
	for pd in pads:
		var px := float(pd["x"])
		var py := float(pd["y"])
		var pz := float(pd["z"])
		var ci := int(pd["chunk_idx"])
		var c_center := _chunk_center(ci)
		var pad_sp := Props.build_pad(pal)
		chunk_soups[ci].merge(pad_sp, {"p": Vector3(px - c_center.x, py, pz - c_center.z)})

	# 3. Dress Biome Props & Flora directly into their chunks (so every tree/rock/grave falls with its chunk!)
	_dress_world(chunk_soups, rng)

	# 4. Commit all 36 chunks as individual Node3D pieces
	for gz in CHUNK_G:
		for gx in CHUNK_G:
			var ci := gz * CHUNK_G + gx
			var c_center := _chunk_center(ci)
			var node := Node3D.new()
			node.name = "chunk_%d_%d" % [gx, gz]
			node.position = c_center
			add_child(node)

			var sp: Soup = chunk_soups[ci]
			if sp.verts() > 0:
				var mi := sp.instance(node, "terrain", TX.mat_world)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

			var wsp: Soup = water_soups[ci]
			if wsp.verts() > 0:
				var wmi := wsp.instance(node, "water", TX.mat_water)
				wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			chunk_nodes.append(node)
			var dist_edge := minf(minf(float(gx), float(CHUNK_G - 1 - gx)), minf(float(gz), float(CHUNK_G - 1 - gz)))
			pieces.append({
				"node": node,
				"base": c_center,
				"spin": Vector3(rng.frange(-1.4, 1.4), rng.frange(-0.8, 0.8), rng.frange(-1.4, 1.4)),
				"delay": dist_edge * 0.14 + rng.frange(0.0, 0.22),
				"kind": "chunk",
				"idx": ci,
			})


func _chunk_center(ci: int) -> Vector3:
	var cs := (MAP_HALF * 2.0) / float(CHUNK_G)
	var gx := ci % CHUNK_G
	var gz := ci / CHUNK_G
	return Vector3(-MAP_HALF + (float(gx) + 0.5) * cs, 0.0, -MAP_HALF + (float(gz) + 0.5) * cs)


func _merge_at(chunk_soups: Array, prop: Soup, wx: float, wy: float, wz: float, ry: float = 0.0, s: float = 1.0) -> void:
	if absf(wx) > MAP_HALF - 0.35 or absf(wz) > MAP_HALF - 0.35:
		return
	var ci := chunk_index_at(wx, wz)
	var cc := _chunk_center(ci)
	chunk_soups[ci].merge(prop, {"p": Vector3(wx - cc.x, wy, wz - cc.z), "ry": ry, "s": s})


func _can_place(x: float, z: float, min_road: float, min_pad: float, allow_water: bool = false) -> bool:
	if absf(x) > MAP_HALF - 0.9 or absf(z) > MAP_HALF - 0.9:
		return false
	if dist_to_road(x, z) < min_road:
		return false
	if not allow_water:
		if dist_to_stream(x, z) < 2.0 or _in_pond(x, z, 0.8):
			return false
	if U.dist2(x, z, keep_pos.x, keep_pos.z) < 5.2:
		return false
	if U.dist2(x, z, cave_pos.x, cave_pos.z) < 4.5:
		return false
	for pd in pads:
		if U.dist2(x, z, float(pd["x"]), float(pd["z"])) < min_pad:
			return false
	return true


func _dress_world(chunk_soups: Array, rng: U.Rng) -> void:
	var pal: Dictionary = biome["pal"]
	var fl: Dictionary = biome["flora"]
	var C := Soup.COL()
	var frost := String(biome["key"]) == "frost"

	# Helper to scatter N instances of a builder
	var scatter := func(count: int, min_r: float, min_p: float, builder: Callable) -> void:
		var placed := 0
		for _t in count * 6:
			if placed >= count:
				break
			var x := rng.frange(-MAP_HALF + 1.0, MAP_HALF - 1.0)
			var z := rng.frange(-MAP_HALF + 1.0, MAP_HALF - 1.0)
			if not _can_place(x, z, min_r, min_p):
				continue
			var y := height_at(x, z)
			var sp := Soup.new()
			builder.call(sp, x, y, z)
			_merge_at(chunk_soups, sp, x, y, z, rng.frange(0, TAU), 1.0)
			placed += 1

	# Standard deciduous/gnarled trees
	if fl.has("tree"):
		var tc: Array = fl["tree"]
		scatter.call(int(tc[0]), 2.5, 2.5, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Props.add_tree(sp, rng, pal, rng.frange(float(tc[1]) * 0.8, float(tc[1]) * 1.25), float(tc[2]))
		)

	# Snow-laden pines
	if fl.has("pine"):
		scatter.call(int(fl["pine"]), 2.4, 2.4, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_pine(sp, rng, pal, rng.frange(0.75, 1.3), frost)
		)

	# Weeping willows
	if fl.has("willow"):
		scatter.call(int(fl["willow"]), 2.5, 2.5, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_willow(sp, rng, pal, rng.frange(0.85, 1.25))
		)

	# Charred ember trees
	if fl.has("charred"):
		scatter.call(int(fl["charred"]), 2.4, 2.4, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_charred_tree(sp, rng, pal, rng.frange(0.8, 1.25))
		)

	# Desert palms
	if fl.has("palm"):
		scatter.call(int(fl["palm"]), 2.5, 2.5, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_palm(sp, rng, pal, rng.frange(0.85, 1.25))
		)

	# Saguaro cacti
	if fl.has("cactus"):
		scatter.call(int(fl["cactus"]), 2.1, 2.1, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_cactus(sp, rng, pal, rng.frange(0.75, 1.25))
		)

	# Basalt columns
	if fl.has("basalt"):
		scatter.call(int(fl["basalt"]), 2.4, 2.4, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_basalt_column(sp, rng, pal)
		)

	# Mesa rock spires
	if fl.has("spire"):
		scatter.call(int(fl["spire"]), 2.8, 2.6, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_rock_spire(sp, rng, pal)
		)

	# Lava vents (also register dynamic glow/fire emitters!)
	if fl.has("vent"):
		scatter.call(int(fl["vent"]), 2.5, 2.4, func(sp: Soup, x: float, y: float, z: float) -> void:
			Flora.add_lava_vent(sp, rng, pal)
			lava_vents.append(Vector3(x, y + 0.62, z))
		)

	# Glowing swamp mushrooms
	if fl.has("shroom"):
		var sh_col: Color = biome.get("wisp_col", Color(0.45, 1.0, 0.65))
		scatter.call(int(fl["shroom"]), 1.9, 1.9, func(sp: Soup, x: float, y: float, z: float) -> void:
			Flora.add_mushroom(sp, rng, sh_col)
			if mushroom_lights.size() < 4 and rng.chance(0.4):
				mushroom_lights.append(Vector3(x, y + 0.45, z))
		)

	# Snow drifts & ice crystals
	if fl.has("drift"):
		scatter.call(int(fl["drift"]), 2.0, 2.0, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_snow_drift(sp, rng)
		)
	if fl.has("crystal"):
		scatter.call(int(fl["crystal"]), 2.2, 2.2, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_ice_crystal(sp, rng)
		)

	# Desert jars, fallen logs, stumps, boulders, grass tufts
	if fl.has("jar"):
		scatter.call(int(fl["jar"]), 1.8, 1.8, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_desert_jar(sp, rng)
		)
	if fl.has("log"):
		scatter.call(int(fl["log"]), 2.2, 2.2, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Flora.add_fallen_log(sp, rng, pal)
		)
	if fl.has("stump"):
		scatter.call(int(fl["stump"]), 2.0, 2.0, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Props.add_stump(sp, rng, pal, rng.frange(0.8, 1.25))
		)
	if fl.has("boulder"):
		var rk: Color = pal["rock"]
		scatter.call(int(fl["boulder"]), 1.9, 1.9, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			sp.rock(rng.frange(0.28, 0.82), 0, 0.14, 0, rk, {"sq": rng.frange(0.55, 0.88)})
		)
	if fl.has("tuft"):
		scatter.call(int(fl["tuft"]), 1.5, 1.6, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
			Props.add_grass_tuft(sp, rng, pal, rng.frange(0.75, 1.35))
		)

	# Water-edge reeds & pond lily pads
	if fl.has("reed") and stream_pts.size() >= 2:
		for _i in int(fl["reed"]):
			var pt := stream_pts[rng.irange(0, stream_pts.size() - 1)]
			var rx := pt.x + rng.frange(-2.2, 2.2)
			var rz := pt.z + rng.frange(-2.2, 2.2)
			if absf(rx) > MAP_HALF - 1.0 or absf(rz) > MAP_HALF - 1.0 or dist_to_road(rx, rz) < 2.2:
				continue
			var ry := height_at(rx, rz)
			if ry > _water_level - 0.35 and ry < _water_level + 0.55:
				var sp := Soup.new()
				Flora.add_reeds(sp, rng, pal, rng.frange(0.75, 1.25))
				_merge_at(chunk_soups, sp, rx, ry, rz, rng.frange(0, TAU))

	if fl.has("lily") and ponds.size() > 0:
		for _i in int(fl["lily"]):
			var po: Dictionary = ponds[rng.irange(0, ponds.size() - 1)]
			var a := rng.frange(0, TAU)
			var d := rng.frange(0.15, float(po["r"]) * 0.78)
			var lx := float(po["x"]) + cos(a) * d
			var lz := float(po["z"]) + sin(a) * d
			var sp := Soup.new()
			Flora.add_lily_pad(sp, rng, pal)
			_merge_at(chunk_soups, sp, lx, _water_level + 0.01, lz, rng.frange(0, TAU))

	# Graveyard cluster (graves + iron fence + skull piles)
	if bool(fl.get("grave", false)):
		for _try in 20:
			var gx := rng.frange(-11.0, 11.0)
			var gz := rng.frange(-11.0, 11.0)
			if _can_place(gx, gz, 3.8, 3.6):
				for _g in rng.irange(5, 8):
					var ox := gx + rng.frange(-2.4, 2.4)
					var oz := gz + rng.frange(-2.4, 2.4)
					if _can_place(ox, oz, 1.8, 1.9):
						var sp := Soup.new()
						Props.add_grave(sp, rng, pal)
						_merge_at(chunk_soups, sp, ox, height_at(ox, oz), oz, rng.frange(-0.4, 0.4))
				var fsp := Soup.new()
				Props.add_fence(fsp, rng, 3)
				_merge_at(chunk_soups, fsp, gx, height_at(gx, gz), gz - 2.3, 0.0)
				wisp_zones.append(Vector3(gx, height_at(gx, gz) + 0.8, gz))
				break

	# Ruined walls, ruined tower, roadside carts, well, statue, gibbet, signpost, banners, lanterns, bones
	var n_ruins := int(fl.get("ruins", 3))
	for i in n_ruins:
		for _try in 16:
			var rx := rng.frange(-13.0, 13.0)
			var rz := rng.frange(-13.0, 13.0)
			if _can_place(rx, rz, 3.2, 3.0):
				var sp := Soup.new()
				if i == 0:
					Props.add_ruined_tower(sp, rng, pal)
				elif i == 1:
					Props.add_well(sp, rng, pal)
				elif i == 2:
					Props.add_statue(sp, pal)
				else:
					Props.add_ruined_wall(sp, rng, pal, rng.frange(2.5, 3.8))
				_merge_at(chunk_soups, sp, rx, height_at(rx, rz), rz, rng.frange(0, TAU))
				break

	# Roadside details: lanterns, signpost, cart, barrels/crates, banners, gibbet, cairns, bones/ribcage
	var road_spots := [0.16, 0.30, 0.44, 0.62, 0.76, 0.88]
	for idx in road_spots.size():
		var samp := sample_path(path_len * float(road_spots[idx]))
		var p: Vector3 = samp["pos"]
		var d: Vector3 = samp["dir"]
		var side_v := Vector3(-d.z, 0, d.x) * (1.0 if idx % 2 == 0 else -1.0)
		var wx := p.x + side_v.x * 2.15
		var wz := p.z + side_v.z * 2.15
		if not _can_place(wx, wz, 1.55, 1.95):
			continue
		var wy := height_at(wx, wz)
		var sp := Soup.new()
		if idx == 0:
			Props.add_signpost(sp, rng)
		elif idx == 1:
			Props.add_cart(sp, rng, rng.chance(0.5))
		elif idx == 2:
			Props.add_gibbet(sp, rng)
		elif idx == 3:
			Props.add_banner(sp, rng, C["clothR"], 2.7, C["gold"])
		elif idx == 4:
			Props.add_barrel(sp, rng, false)
			var c2 := Soup.new()
			Props.add_crate(c2, rng, 0.56)
			sp.merge(c2, {"p": Vector3(0.62, 0, 0.2)})
		else:
			var l_off := Props.add_lantern_post(sp, rng, pal)
			var ry := atan2(-side_v.x, -side_v.z)
			var rot_off := Vector3(l_off.x * cos(ry) + l_off.z * sin(ry), l_off.y, -l_off.x * sin(ry) + l_off.z * cos(ry))
			lantern_positions.append(Vector3(wx, wy, wz) + rot_off)
			_merge_at(chunk_soups, sp, wx, wy, wz, ry)
			continue
		_merge_at(chunk_soups, sp, wx, wy, wz, rng.frange(0, TAU))

	# Additional glowing road lanterns near keep & cave
	for frac in [0.10, 0.82]:
		var samp := sample_path(path_len * float(frac))
		var p: Vector3 = samp["pos"]
		var d: Vector3 = samp["dir"]
		var side_v := Vector3(-d.z, 0, d.x)
		var wx := p.x + side_v.x * 1.95
		var wz := p.z + side_v.z * 1.95
		if _can_place(wx, wz, 1.45, 1.8):
			var wy := height_at(wx, wz)
			var sp := Soup.new()
			var l_off := Props.add_lantern_post(sp, rng, pal)
			var ry := atan2(-side_v.x, -side_v.z)
			var rot_off := Vector3(l_off.x * cos(ry) + l_off.z * sin(ry), l_off.y, -l_off.x * sin(ry) + l_off.z * cos(ry))
			lantern_positions.append(Vector3(wx, wy, wz) + rot_off)
			_merge_at(chunk_soups, sp, wx, wy, wz, ry)

	# Bones, ribcages & cairns
	scatter.call(5, 1.7, 1.8, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
		if rng.chance(0.35):
			Props.add_ribcage(sp, rng)
		else:
			Props.add_bones(sp, rng)
	)
	scatter.call(4, 1.9, 1.9, func(sp: Soup, _x: float, _y: float, _z: float) -> void:
		Props.add_cairn(sp, rng, pal)
	)


func _build_landmarks(rng: U.Rng) -> void:
	var pal: Dictionary = biome["pal"]
	var frost := String(biome["key"]) == "frost"

	# 1. Keep & Beacon Spire Tower
	var kd := Props.build_keep(pal, rng)
	keep_node = Node3D.new()
	keep_node.name = "keep"
	keep_node.position = keep_pos
	keep_node.rotation.y = keep_yaw
	add_child(keep_node)
	var kmi: MeshInstance3D = kd["keep"].instance(keep_node, "keep_mesh", TX.mat_world)
	kmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	beacon_node = Node3D.new()
	beacon_node.name = "beacon"
	beacon_node.position = keep_pos
	beacon_node.rotation.y = keep_yaw
	add_child(beacon_node)
	var bmi: MeshInstance3D = kd["beacon"].instance(beacon_node, "beacon_mesh", TX.mat_world)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Compute world-space beacon flame & sconce coordinates
	var k_xf := Transform3D(Basis(Vector3.UP, keep_yaw), keep_pos)
	beacon_flame_pos = k_xf * kd["flame_local"]
	for sc_l in kd["sconces"]:
		sconce_positions.append(k_xf * sc_l)

	pieces.append({"node": keep_node, "base": keep_pos, "spin": Vector3(0.4, 0.3, -0.35), "delay": 0.42, "kind": "keep", "idx": -1})
	pieces.append({"node": beacon_node, "base": keep_pos, "spin": Vector3(-0.3, 0.5, 0.4), "delay": 0.52, "kind": "beacon", "idx": -1})

	# 2. Craggy Cave Entrance
	cave_node = Node3D.new()
	cave_node.name = "cave"
	cave_node.position = cave_pos
	cave_node.rotation.y = cave_yaw
	add_child(cave_node)
	var cave_sp := Props.build_cave(pal, rng, frost)
	var cmi := cave_sp.instance(cave_node, "cave_mesh", TX.mat_world)
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pieces.append({"node": cave_node, "base": cave_pos, "spin": Vector3(-0.5, -0.25, 0.45), "delay": 0.36, "kind": "cave", "idx": -1})

	# 3. Stone Arch Bridge + Waterfall Ribbon at Stream Edge
	if stream_pts.size() >= 2:
		bridge_node = Node3D.new()
		bridge_node.name = "bridge"
		bridge_node.position = Vector3(bridge_pos.x, _water_level + 0.50, bridge_pos.z)
		bridge_node.rotation.y = bridge_yaw
		add_child(bridge_node)
		var bsp := Props.build_bridge(pal, 2.75, 5.6, frost)
		var brmi := bsp.instance(bridge_node, "bridge_mesh", TX.mat_world)
		brmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pieces.append({"node": bridge_node, "base": bridge_node.position, "spin": Vector3(0.7, -0.4, 0.5), "delay": 0.28, "kind": "bridge", "idx": -1})

		_build_waterfall()


func _build_waterfall() -> void:
	if not bool(biome["water_on"]) or stream_pts.size() < 2:
		return
	# Find where stream crosses the outer slab edge
	var edge_p := Vector3.ZERO
	var edge_dir := Vector3.ZERO
	var found := false
	for i in range(stream_pts.size() - 1, 0, -1):
		var p := stream_pts[i]
		var prev := stream_pts[i - 1]
		if (absf(p.x) >= MAP_HALF or absf(p.z) >= MAP_HALF) and absf(prev.x) < MAP_HALF and absf(prev.z) < MAP_HALF:
			var t := 0.5
			edge_p = prev.lerp(p, t)
			edge_p.x = clampf(edge_p.x, -MAP_HALF, MAP_HALF)
			edge_p.z = clampf(edge_p.z, -MAP_HALF, MAP_HALF)
			edge_dir = (p - prev).normalized()
			found = true
			break
	if not found:
		return

	var cliff_d := float(biome["relief"].get("cliff", 3.2)) + 2.8
	var top_y := _water_level
	var bot_y := -cliff_d
	var side := Vector3(-edge_dir.z, 0.0, edge_dir.x).normalized()
	var hw := 1.18

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 10
	for r in rows:
		var v0 := float(r) / float(rows)
		var v1 := float(r + 1) / float(rows)
		var y0 := lerpf(top_y, bot_y, v0)
		var y1 := lerpf(top_y, bot_y, v1)
		var out0 := (1.0 - pow(1.0 - v0, 2.0)) * 0.72 + 0.14
		var out1 := (1.0 - pow(1.0 - v1, 2.0)) * 0.72 + 0.14
		var c0 := Vector3(edge_p.x, y0, edge_p.z) + edge_dir * out0
		var c1 := Vector3(edge_p.x, y1, edge_p.z) + edge_dir * out1
		var a := c0 - side * hw
		var b := c0 + side * hw
		var c := c1 + side * hw
		var d := c1 - side * hw
		var verts := [a, b, c, a, c, d]
		var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v0), Vector2(1, v1), Vector2(0, v1)]
		for k in 6:
			st.set_uv(uvs[k])
			st.add_vertex(verts[k])

	var wf_mi := MeshInstance3D.new()
	wf_mi.name = "waterfall"
	wf_mi.mesh = st.commit()
	wf_mi.material_override = TX.mat_waterfall
	wf_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ci := chunk_index_at(clampf(edge_p.x, -MAP_HALF + 0.5, MAP_HALF - 0.5), clampf(edge_p.z, -MAP_HALF + 0.5, MAP_HALF - 0.5))
	var cc := _chunk_center(ci)
	wf_mi.position = -cc
	chunk_nodes[ci].add_child(wf_mi)

	fall_at = {
		"has": true,
		"pos": Vector3(edge_p.x, top_y, edge_p.z) + edge_dir * 0.55,
		"bot_pos": Vector3(edge_p.x, bot_y + 0.6, edge_p.z) + edge_dir * 0.85,
		"dir": edge_dir,
		"spray": String(biome.get("spray", "water")),
	}


# ============================================================================
# Smooth Biome Look & Shader/Environment Interpolation
# ============================================================================

func apply_biome_look(
	dt: float,
	instant: bool,
	world_env: WorldEnvironment,
	fx_node: Node,
	mist_mat: ShaderMaterial,
	weather_node: Node,
	post_node: Node,
	fade_v: float = 1.0
) -> void:
	var b := biome
	if not _has_look or instant:
		_cur_look = {
			"clear": b["clear"],
			"sky_top": b["sky_top"],
			"sky_hor": b["sky_hor"],
			"hemi_s": b["hemi_s"],
			"hemi_i": float(b["hemi_i"]),
			"moon": b["moon"],
			"moon_i": float(b["moon_i"]),
			"moon_pos": b["moon_pos"],
			"fill": b["fill"],
			"fill_i": float(b["fill_i"]),
			"rim": b["rim"],
			"rim_amt": float(b["rim_amt"]),
			"mist_amb": b["mist_amb"],
			"mist": b["mist"],
			"sky_refl": b["sky_refl"],
			"grade_sat": float(b["grade_sat"]),
			"grade_con": float(b["grade_con"]),
			"grade_tint": b["grade_tint"],
			"wind": float(b["wind"]),
			"cover": b["cover"],
			"cover_col": b["cover_col"],
			"cover_p": b["cover_p"],
			"sparkle": float(b["sparkle"]),
			"wat": b["wat"],
			"wat_a": b["wat_a"],
			"wat_b": b["wat_b"],
			"wf_a": b["wf_a"],
			"wf_b": b["wf_b"],
			"wf_spd": float(b["wf_spd"]),
			"wf_em": float(b["wf_em"]),
		}
		_has_look = true
		if weather_node != null and weather_node.has_method("apply_biome"):
			weather_node.apply_biome(b, true)
	else:
		var k := 1.0 - exp(-dt * 2.2)
		_cur_look["clear"] = _cur_look["clear"].lerp(b["clear"], k)
		_cur_look["sky_top"] = _cur_look["sky_top"].lerp(b["sky_top"], k)
		_cur_look["sky_hor"] = _cur_look["sky_hor"].lerp(b["sky_hor"], k)
		_cur_look["hemi_s"] = _cur_look["hemi_s"].lerp(b["hemi_s"], k)
		_cur_look["hemi_i"] = lerpf(float(_cur_look["hemi_i"]), float(b["hemi_i"]), k)
		_cur_look["moon"] = _cur_look["moon"].lerp(b["moon"], k)
		_cur_look["moon_i"] = lerpf(float(_cur_look["moon_i"]), float(b["moon_i"]), k)
		_cur_look["moon_pos"] = _cur_look["moon_pos"].lerp(b["moon_pos"], k)
		_cur_look["fill"] = _cur_look["fill"].lerp(b["fill"], k)
		_cur_look["fill_i"] = lerpf(float(_cur_look["fill_i"]), float(b["fill_i"]), k)
		_cur_look["rim"] = _cur_look["rim"].lerp(b["rim"], k)
		_cur_look["rim_amt"] = lerpf(float(_cur_look["rim_amt"]), float(b["rim_amt"]), k)
		_cur_look["mist_amb"] = _cur_look["mist_amb"].lerp(b["mist_amb"], k)
		_cur_look["mist"] = _cur_look["mist"].lerp(b["mist"], k)
		_cur_look["sky_refl"] = _cur_look["sky_refl"].lerp(b["sky_refl"], k)
		_cur_look["grade_sat"] = lerpf(float(_cur_look["grade_sat"]), float(b["grade_sat"]), k)
		_cur_look["grade_con"] = lerpf(float(_cur_look["grade_con"]), float(b["grade_con"]), k)
		_cur_look["grade_tint"] = _cur_look["grade_tint"].lerp(b["grade_tint"], k)
		_cur_look["wind"] = lerpf(float(_cur_look["wind"]), float(b["wind"]), k)
		_cur_look["cover"] = _cur_look["cover"].lerp(b["cover"], k)
		_cur_look["cover_col"] = _cur_look["cover_col"].lerp(b["cover_col"], k)
		_cur_look["cover_p"] = _cur_look["cover_p"].lerp(b["cover_p"], k)
		_cur_look["sparkle"] = lerpf(float(_cur_look["sparkle"]), float(b["sparkle"]), k)
		_cur_look["wat"] = b["wat"]
		_cur_look["wat_a"] = _cur_look["wat_a"].lerp(b["wat_a"], k)
		_cur_look["wat_b"] = _cur_look["wat_b"].lerp(b["wat_b"], k)
		_cur_look["wf_a"] = _cur_look["wf_a"].lerp(b["wf_a"], k)
		_cur_look["wf_b"] = _cur_look["wf_b"].lerp(b["wf_b"], k)
		_cur_look["wf_spd"] = lerpf(float(_cur_look["wf_spd"]), float(b["wf_spd"]), k)
		_cur_look["wf_em"] = lerpf(float(_cur_look["wf_em"]), float(b["wf_em"]), k)
		# Weather biome only swaps on instant biome change (not every frame)

	var L := _cur_look
	# World shaders (static + instanced)
	for mat in [TX.mat_world, TX.mat_inst]:
		mat.set_shader_parameter("u_wind", float(L["wind"]))
		mat.set_shader_parameter("u_rim_col", L["rim"])
		mat.set_shader_parameter("u_rim_amt", float(L["rim_amt"]))
		mat.set_shader_parameter("u_cover", L["cover"])
		mat.set_shader_parameter("u_cover_col", L["cover_col"])
		mat.set_shader_parameter("u_cover_p", L["cover_p"])
		mat.set_shader_parameter("u_cover_sparkle", float(L["sparkle"]))

	# Water & waterfall shaders
	TX.mat_water.set_shader_parameter("u_wat", L["wat"])
	TX.mat_water.set_shader_parameter("u_wat_a", L["wat_a"])
	TX.mat_water.set_shader_parameter("u_wat_b", L["wat_b"])
	TX.mat_water.set_shader_parameter("u_sky", L["sky_refl"])

	TX.mat_waterfall.set_shader_parameter("u_col_a", L["wf_a"])
	TX.mat_waterfall.set_shader_parameter("u_col_b", L["wf_b"])
	TX.mat_waterfall.set_shader_parameter("u_speed", float(L["wf_spd"]))
	TX.mat_waterfall.set_shader_parameter("u_emissive", float(L["wf_em"]))

	# Environment sky & ambient
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		env.background_color = L["clear"]
		env.ambient_light_color = L["hemi_s"]
		env.ambient_light_energy = float(L["hemi_i"]) * 0.72
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = L["sky_top"]
			sm.sky_horizon_color = L["sky_hor"]
			sm.ground_horizon_color = L["sky_hor"] * 0.65
			sm.ground_bottom_color = L["clear"]

	# Directional moonlight & opposite rim fill
	if fx_node != null:
		var sun: DirectionalLight3D = fx_node.sun_light
		var fill: DirectionalLight3D = fx_node.fill_light
		if sun != null:
			sun.light_color = L["moon"]
			sun.light_energy = float(L["moon_i"]) * 0.44
			var mp: Vector3 = L["moon_pos"]
			sun.position = mp
			if mp.length_squared() > 1.0:
				sun.look_at(Vector3.ZERO, Vector3.UP)
		if fill != null:
			fill.light_color = L["fill"]
			fill.light_energy = float(L["fill_i"]) * 0.36

	# Valley mist shader
	if mist_mat != null:
		mist_mat.set_shader_parameter("u_mist", L["mist"])
		mist_mat.set_shader_parameter("u_mist_amb", L["mist_amb"])

	# Post grading
	if post_node != null and post_node.has_method("set_grade"):
		post_node.set_grade(float(L["grade_sat"]), float(L["grade_con"]), L["grade_tint"], fade_v)
