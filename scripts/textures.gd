extends RefCounted
## High-resolution (128x128) 11-layer procedural material texture array + normal map array + shared PBR materials.
## Upgraded from 10-gfx.js (64x64 -> 128x128 with crisp Sobel normal maps and metallic/roughness encoding).

const U = preload("res://scripts/util.gd")

const L_DIRT := 0
const L_ROCK := 1
const L_MASON := 2
const L_WOOD := 3
const L_COBBLE := 4
const L_METAL := 5
const L_SLATE := 6
const L_CLOTH := 7
const L_PLAIN := 8
const L_BONE := 9
const L_THATCH := 10
const TEX_LAYERS := 11
const TEX_N := 128

static var _ready := false
static var tex_albedo: Texture2DArray
static var tex_normal: Texture2DArray
static var mat_world: ShaderMaterial
static var mat_inst: ShaderMaterial
static var mat_water: ShaderMaterial
static var mat_waterfall: ShaderMaterial


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	_generate_textures()
	_create_materials()


static func _generate_textures() -> void:
	var N := TEX_N
	var sc := float(N) / 64.0
	var albedo_imgs: Array[Image] = []
	var normal_imgs: Array[Image] = []

	# Precompute Voronoi cobble sites (8x8 periodic grid)
	var CG := 8
	var CS := float(N) / float(CG)
	var sites: Array = []
	for j in CG:
		for i in CG:
			sites.append([
				(float(i) + 0.2 + 0.6 * U.h2(i, j, 11)) * CS,
				(float(j) + 0.2 + 0.6 * U.h2(i, j, 12)) * CS,
				U.h2(i, j, 13),
				U.h2(i, j, 14),
			])

	var heights: Array[PackedFloat32Array] = []
	var albedos: Array[PackedByteArray] = []
	for _l in TEX_LAYERS:
		var hb := PackedFloat32Array()
		hb.resize(N * N)
		heights.append(hb)
		var ab := PackedByteArray()
		ab.resize(N * N * 4)
		albedos.append(ab)

	for y in N:
		var yf := float(y) / sc # 0..64 coordinate space for crisp scaled patterns
		var yi := int(yf)
		for x in N:
			var xf := float(x) / sc
			var xi := int(xf)
			var idx := y * N + x
			var off := idx * 4

			# 0: L_DIRT
			var n := U.pfbm(xf / 8.0, yf / 8.0, 8, 1, 4)
			var sp := U.h2(x, y, 3)
			var n2 := U.pfbm(xf / 16.0, yf / 16.0, 4, 5, 2)
			var m := 0.78 + 0.34 * n + (n2 - 0.5) * 0.2
			var h := 0.35 + 0.35 * n
			if sp > 0.985:
				m += 0.14
				h += 0.4
			elif sp < 0.03:
				m -= 0.1
				h -= 0.12
			_put(albedos[L_DIRT], heights[L_DIRT], idx, off, m * 1.02, m, m * 0.97, h)

			# 1: L_ROCK
			n = U.pfbm(xf / 8.0, yf / 8.0, 8, 21, 4)
			n2 = U.pfbm(xf / 16.0, yf / 16.0, 4, 23, 3)
			var n3 := U.pfbm(xf / 16.0 + 9.0, yf / 16.0 + 3.0, 4, 27, 3)
			var crack := 1.0 if (absf(n2 - 0.5) < 0.022 or absf(n3 - 0.52) < 0.016) else 0.0
			var strata := sin((yf + n2 * 26.0) * TAU / 16.0) * 0.055
			m = 0.74 + 0.42 * n + strata - crack * 0.34 + (U.h2(x, y, 29) - 0.5) * 0.07
			h = 0.3 + 0.6 * n - crack * 0.42
			_put(albedos[L_ROCK], heights[L_ROCK], idx, off, m, m, m * 1.03, h)

			# 2: L_MASON (beveled stonework courses with mortar)
			var row := int(floor(yf / 8.0))
			var ox := 8 if (row & 1) != 0 else 0
			var bx := int(floor((xf + float(ox)) / 16.0))
			var lx := fmod(xf + float(ox), 16.0)
			var ly := fmod(yf, 8.0)
			var id := U.h2(bx % 4, row, 31)
			var id2 := U.h2(bx % 4, row, 32)
			var mortar := (ly < 0.85 or lx < 0.85)
			n = U.pnoise2(xf / 2.0, yf / 2.0, 32, 32, 33) - 0.5
			m = 0.8 + 0.32 * id + n * 0.2
			h = 0.66 + 0.2 * id2 + n * 0.15
			if id2 > 0.86:
				m -= 0.12
				h -= 0.22
			if ly >= 0.85 and ly < 1.8 or lx >= 0.85 and lx < 1.8:
				m += 0.09
			if ly > 6.8 or lx > 14.8:
				m -= 0.1
			var mr := m * (1.0 + (id - 0.5) * 0.06)
			var mg := m
			var mb := m * (1.0 - (id - 0.5) * 0.08)
			if mortar:
				mr = 0.44 + n * 0.1
				mg = mr
				mb = mr
				h = 0.10
			_put(albedos[L_MASON], heights[L_MASON], idx, off, mr, mg, mb, h)

			# 3: L_WOOD (planks, grain, butt joints, nails, knots)
			var pl := int(floor(xf / 8.0))
			var wlx := fmod(xf, 8.0)
			id = U.h2(pl, 0, 41)
			var grain := U.pnoise2(xf * 1.25, yf / 7.0, 80, 9, 42 + pl)
			var g2 := U.pnoise2(xf * 2.5, yf / 3.0, 160, 21, 44)
			m = 0.8 + 0.28 * id + (grain - 0.5) * 0.34 + (g2 - 0.5) * 0.12
			h = 0.55 + grain * 0.25
			var joint := int(floor(8.0 + id * 48.0))
			if wlx < 0.7 or absf(yf - float(joint)) < 0.6:
				m = 0.42
				h = 0.10
			elif wlx < 1.6:
				m += 0.06
			elif wlx > 6.9:
				m -= 0.08
			var jy1 := posmod(joint + 3, 64)
			var jy2 := posmod(joint + 61, 64)
			if (absf(yf - float(jy1)) < 0.7 or absf(yf - float(jy2)) < 0.7) and (absf(wlx - 2.0) < 0.7 or absf(wlx - 6.0) < 0.7):
				m = 0.38
				h = 0.84
			var knot := U.dist2(wlx, yf, 4.0, float(posmod(joint + 29, 64)))
			if knot < 5.0 and id > 0.5:
				m -= 0.2 * (1.0 - knot / 5.0)
			_put(albedos[L_WOOD], heights[L_WOOD], idx, off, m * 1.03, m, m * 0.95, h)

			# 4: L_COBBLE (domed Voronoi cobblestones)
			var d1 := 1e9
			var d2 := 1e9
			var s1: Array = sites[0]
			var half_n := float(N) * 0.5
			for s in sites:
				var dx := absf(float(x) + 0.5 - float(s[0]))
				var dy := absf(float(y) + 0.5 - float(s[1]))
				if dx > half_n:
					dx = float(N) - dx
				if dy > half_n:
					dy = float(N) - dy
				var d := sqrt(dx * dx * 0.85 + dy * dy * 1.15)
				if d < d1:
					d2 = d1
					d1 = d
					s1 = s
				elif d < d2:
					d2 = d
			var edge := (d2 - d1) / sc
			n = U.pnoise2(xf / 2.0, yf / 2.0, 32, 32, 51) - 0.5
			var cr := 0.36
			var cg := 0.36
			var cb := 0.36
			if edge < 1.15:
				m = 0.36 + n * 0.1
				h = 0.04
				cr = m * 1.04
				cg = m
				cb = m * 0.95
			else:
				var dome := U.smooth(1.15, 4.2, edge)
				m = 0.7 + 0.42 * float(s1[2]) + n * 0.16 + dome * 0.1
				h = 0.25 + 0.7 * dome + n * 0.1
				var warm := (float(s1[3]) - 0.5) * 0.12
				cr = m * (1.0 + warm)
				cg = m
				cb = m * (1.0 - warm)
				if float(s1[2]) > 0.9:
					cr *= 0.8
					cg *= 0.8
					cb *= 0.82
					h *= 0.7
			_put(albedos[L_COBBLE], heights[L_COBBLE], idx, off, cr, cg, cb, h)

			# 5: L_METAL (brushed iron, rust patina, rivets)
			var st := U.pnoise2(xf / 3.0, yf * 1.5, 21, 96, 61) - 0.5
			var rust := U.pfbm(xf / 16.0, yf / 16.0, 4, 63, 3)
			var pit := U.h2(x, y, 65)
			m = 0.92 + st * 0.22
			cr = m
			cg = m
			cb = m * 1.03
			h = 0.5 + st * 0.12
			if rust > 0.58:
				var rk := U.smooth(0.58, 0.72, rust)
				cr = lerpf(cr, m * 1.05, rk)
				cg = lerpf(cg, m * 0.74, rk)
				cb = lerpf(cb, m * 0.55, rk)
				h -= 0.08 * rk
			if pit < 0.025:
				cr *= 0.7
				cg *= 0.7
				cb *= 0.7
				h -= 0.2
			var rx := fmod(xf, 16.0)
			var ry := fmod(yf, 16.0)
			if (absf(rx - 2.0) < 0.75 or absf(rx - 13.0) < 0.75) and (absf(ry - 2.0) < 0.75 or absf(ry - 13.0) < 0.75):
				cr *= 1.25
				cg *= 1.25
				cb *= 1.25
				h = 1.0
			_put(albedos[L_METAL], heights[L_METAL], idx, off, cr, cg, cb, h)

			# 6: L_SLATE (overlapping roof shingles)
			var srow := int(floor(yf / 8.0))
			var sox := 4 if (srow & 1) != 0 else 0
			var sbx := int(floor((xf + float(sox)) / 8.0))
			var slx := fmod(xf + float(sox), 8.0)
			var sly := fmod(yf, 8.0)
			id = U.h2(sbx % 8, srow, 71)
			n = U.pnoise2(xf / 2.0, yf / 2.0, 32, 32, 73) - 0.5
			m = 0.78 + 0.34 * id + n * 0.14
			h = 0.3 + 0.55 * (sly / 7.5)
			if sly > 6.8:
				m += 0.1
			if sly < 0.85:
				m -= 0.3
				h = 0.1
			if slx < 0.75:
				m -= 0.2
				h -= 0.2
			_put(albedos[L_SLATE], heights[L_SLATE], idx, off, m * 0.98, m, m * 1.05, h)

			# 7: L_CLOTH (woven fabric + weathering)
			var wv := 1.05 if ((xi + yi) & 1) != 0 else 0.95
			n = U.pfbm(xf / 16.0, yf / 16.0, 4, 81, 3)
			var stn := U.pfbm(xf / 8.0 + 3.0, yf / 8.0, 8, 83, 2)
			m = wv * (0.84 + 0.3 * n)
			if stn > 0.66:
				m *= 0.78
			_put(albedos[L_CLOTH], heights[L_CLOTH], idx, off, m, m, m, 0.5 + (wv - 1.0) * 0.8)

			# 8: L_PLAIN (subtle micro-grain)
			n = U.pnoise2(xf / 2.0, yf / 2.0, 32, 32, 91) - 0.5
			_put(albedos[L_PLAIN], heights[L_PLAIN], idx, off, 1.0 + n * 0.07, 1.0 + n * 0.07, 1.0 + n * 0.07, 0.5 + n * 0.1)

			# 9: L_BONE (striated porous bone)
			st = U.pnoise2(xf / 2.0, yf / 6.0, 32, 11, 95) - 0.5
			pit = U.h2(x, y, 97)
			m = 0.96 + st * 0.2
			if pit < 0.035:
				m -= 0.22
			_put(albedos[L_BONE], heights[L_BONE], idx, off, m * 1.02, m, m * 0.94, 0.5 + st * 0.25)

			# 10: L_THATCH (layered straw bundles)
			var th := U.pnoise2(xf * 1.6, yf / 5.0, 103, 13, 101)
			var trow := fmod(yf, 16.0)
			m = 0.76 + 0.42 * th
			if trow < 1.0:
				m -= 0.3
			elif trow < 2.0:
				m += 0.08
			_put(albedos[L_THATCH], heights[L_THATCH], idx, off, m * 1.04, m, m * 0.88, 0.3 + th * 0.5 + (trow / 16.0) * 0.2)

	# Build mipmapped albedo + Sobel normal map Texture2DArrays
	for l in TEX_LAYERS:
		var aimg := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, albedos[l])
		aimg.generate_mipmaps()
		albedo_imgs.append(aimg)

		var nb := PackedByteArray()
		nb.resize(N * N * 4)
		var hb := heights[l]
		var strength := 2.4 if (l == L_COBBLE or l == L_MASON or l == L_ROCK) else (1.8 if l == L_WOOD or l == L_SLATE or l == L_THATCH else 1.2)
		for y in N:
			var ym := (y - 1 + N) % N
			var yp := (y + 1) % N
			for x in N:
				var xm := (x - 1 + N) % N
				var xp := (x + 1) % N
				var tl := hb[ym * N + xm]
				var tc := hb[ym * N + x]
				var tr := hb[ym * N + xp]
				var ml := hb[y * N + xm]
				var mr := hb[y * N + xp]
				var bl := hb[yp * N + xm]
				var bc := hb[yp * N + x]
				var br := hb[yp * N + xp]
				var gx := (tr + 2.0 * mr + br - tl - 2.0 * ml - bl) * strength
				var gy := (bl + 2.0 * bc + br - tl - 2.0 * tc - tr) * strength
				var nv := Vector3(-gx, -gy, 1.0).normalized()
				var o := (y * N + x) * 4
				nb[o] = int(clampf((nv.x * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				nb[o + 1] = int(clampf((nv.y * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				nb[o + 2] = int(clampf((nv.z * 0.5 + 0.5) * 255.0, 0.0, 255.0))
				nb[o + 3] = 255
		var nimg := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, nb)
		nimg.generate_mipmaps()
		normal_imgs.append(nimg)

	tex_albedo = Texture2DArray.new()
	tex_albedo.create_from_images(albedo_imgs)
	tex_normal = Texture2DArray.new()
	tex_normal.create_from_images(normal_imgs)


static func _put(ab: PackedByteArray, hb: PackedFloat32Array, idx: int, off: int, r: float, g: float, b: float, h: float) -> void:
	ab[off] = int(clampf(r * 127.5, 0.0, 255.0))
	ab[off + 1] = int(clampf(g * 127.5, 0.0, 255.0))
	ab[off + 2] = int(clampf(b * 127.5, 0.0, 255.0))
	ab[off + 3] = int(clampf(h * 255.0, 0.0, 255.0))
	hb[idx] = clampf(h, 0.0, 1.0)


static func _create_materials() -> void:
	var world_sh: Shader = load("res://shaders/world.gdshader")
	mat_world = ShaderMaterial.new()
	mat_world.shader = world_sh
	mat_world.set_shader_parameter("u_tex_albedo", tex_albedo)
	mat_world.set_shader_parameter("u_tex_normal", tex_normal)
	mat_world.set_shader_parameter("u_is_instanced", 0.0)
	mat_world.set_shader_parameter("u_normal_scale", 0.88)

	mat_inst = ShaderMaterial.new()
	mat_inst.shader = world_sh
	mat_inst.set_shader_parameter("u_tex_albedo", tex_albedo)
	mat_inst.set_shader_parameter("u_tex_normal", tex_normal)
	mat_inst.set_shader_parameter("u_is_instanced", 1.0)
	mat_inst.set_shader_parameter("u_normal_scale", 0.72)

	var water_sh: Shader = load("res://shaders/water.gdshader")
	mat_water = ShaderMaterial.new()
	mat_water.shader = water_sh

	var wf_sh: Shader = load("res://shaders/waterfall.gdshader")
	mat_waterfall = ShaderMaterial.new()
	mat_waterfall.shader = wf_sh


static func set_time(t: float) -> void:
	if not _ready:
		return
	mat_world.set_shader_parameter("u_time", t)
	mat_inst.set_shader_parameter("u_time", t)
	mat_water.set_shader_parameter("u_time", t)
	mat_waterfall.set_shader_parameter("u_time", t)
