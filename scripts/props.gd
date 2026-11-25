extends RefCounted
## Complete Props & Architectural Structure Builders (ported & enriched from 32-props.js).
## Every prop, graveyard piece, ruined masonry, cart, banner, bridge, pad, keep, beacon tower, and cave mouth.

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")
const Soup = preload("res://scripts/soup.gd")


static func _c(pal: Dictionary, k: String) -> Color:
	var base := Soup.COL()
	return pal.get(k, base.get(k, Color.WHITE))


# ============================================================================
# Environmental Props (merged into terrain chunks)
# ============================================================================

static func add_barrel(sp: Soup, rng: U.Rng, broken: bool = false) -> void:
	var C := Soup.COL()
	var h := 0.44 if broken else 0.72
	sp.cyl(0.28, h, 0, h * 0.5, 0, C["wood"], {"n": 8, "rt": 0.94, "l": TX.L_WOOD, "uvs": 0.9})
	sp.cyl(0.295, 0.05, 0, h * 0.25, 0, C["iron"], {"n": 8, "l": TX.L_METAL, "rough": 0.52})
	if not broken:
		sp.cyl(0.295, 0.05, 0, h * 0.78, 0, C["iron"], {"n": 8, "l": TX.L_METAL, "rough": 0.52})
	else:
		for _i in 3:
			sp.box(0.08, 0.28, 0.04, rng.frange(-0.2, 0.2), 0.12, rng.frange(-0.2, 0.2), C["woodD"], {"l": TX.L_WOOD, "r": Vector3(rng.frange(-0.9, 0.9), rng.frange(0, TAU), rng.frange(-0.9, 0.9))})


static func add_crate(sp: Soup, rng: U.Rng, sz: float = 0.6) -> void:
	var C := Soup.COL()
	sp.box(sz, sz, sz, 0, sz * 0.5, 0, C["wood"], {"l": TX.L_WOOD, "uvs": 0.85})
	var t := sz * 0.1
	for sy in [-1.0, 1.0]:
		sp.box(sz + 0.03, t, sz + 0.03, 0, sz * 0.5 + sy * (sz * 0.42), 0, C["woodD"], {"l": TX.L_WOOD})
	sp.box(sz * 1.15, t * 0.85, 0.04, 0, sz * 0.5, sz * 0.51, C["woodD"], {"l": TX.L_WOOD, "r": Vector3(0, 0, 0.78)})
	if rng.chance(0.4):
		sp.box(sz * 0.55, sz * 0.55, sz * 0.55, rng.frange(-0.1, 0.1), sz + sz * 0.27, rng.frange(-0.1, 0.1), C["woodL"], {"l": TX.L_WOOD, "r": Vector3(0, rng.frange(0, TAU), 0)})


static func add_tree(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0, foliage_amt: float = 0.45) -> void:
	var bark := _c(pal, "bark")
	var leaf := _c(pal, "leaf")
	var leaf_l := _c(pal, "leafL")
	var h := (2.6 + rng.next_f() * 1.6) * s
	var r0 := (0.20 + rng.next_f() * 0.09) * s
	var lean_x := rng.frange(-0.26, 0.26) * s
	var lean_z := rng.frange(-0.26, 0.26) * s

	# Flared roots
	for i in 4:
		var a := float(i) * PI * 0.5 + rng.frange(-0.35, 0.35)
		var rp := Vector3(cos(a) * r0 * 2.1, -0.08, sin(a) * r0 * 2.1)
		sp.seg(Vector3(cos(a) * r0 * 0.4, 0.38 * s, sin(a) * r0 * 0.4), rp, r0 * 0.48, r0 * 0.16, bark, {"l": TX.L_WOOD, "n": 5})

	# Twisted multi-segment trunk
	var p0 := Vector3(0, -0.06, 0)
	var p1 := Vector3(lean_x * 0.45, h * 0.45, lean_z * 0.45)
	var p2 := Vector3(lean_x, h, lean_z)
	sp.seg(p0, p1, r0, r0 * 0.72, bark, {"l": TX.L_WOOD, "n": 7, "uvs": 0.6})
	sp.seg(p1, p2, r0 * 0.72, r0 * 0.36, bark, {"l": TX.L_WOOD, "n": 6, "uvs": 0.6})

	# Recursive gnarled boughs
	var nb := rng.irange(4, 6)
	for i in nb:
		var a := (float(i) / float(nb)) * TAU + rng.frange(-0.35, 0.35)
		var elev := rng.frange(0.28, 0.75)
		var blen := (1.1 + rng.next_f() * 0.9) * s
		var base_t := rng.frange(0.55, 0.96)
		var start := p1.lerp(p2, base_t)
		var mid := start + Vector3(cos(a) * blen * 0.55, blen * elev * 0.65, sin(a) * blen * 0.55)
		var tip := mid + Vector3(cos(a + rng.frange(-0.4, 0.4)) * blen * 0.52, blen * (elev * 0.45 + rng.frange(-0.18, 0.22)), sin(a + rng.frange(-0.4, 0.4)) * blen * 0.52)
		sp.seg(start, mid, r0 * 0.38, r0 * 0.22, bark, {"l": TX.L_WOOD, "n": 5})
		sp.seg(mid, tip, r0 * 0.22, r0 * 0.08, bark, {"l": TX.L_WOOD, "n": 4})

		# Sub-twig
		var a2 := a + rng.sign_val() * rng.frange(0.45, 0.9)
		var sub := mid + Vector3(cos(a2) * blen * 0.42, blen * rng.frange(0.15, 0.45), sin(a2) * blen * 0.42)
		sp.seg(mid, sub, r0 * 0.16, r0 * 0.05, bark, {"l": TX.L_WOOD, "n": 4})

		if foliage_amt > 0.05 and rng.next_f() < foliage_amt + 0.35:
			var fr := (0.45 + rng.next_f() * 0.42) * s * (0.65 + foliage_amt * 0.6)
			var fc := U.mix_c(leaf, leaf_l, rng.next_f())
			sp.ico(fr, tip.x, tip.y, tip.z, fc, {"d": 1, "l": TX.L_THATCH, "sc": Vector3(1.15, 0.72, 1.15), "sway": 0.42 * s, "jit": 0.12})
			if rng.chance(0.55):
				sp.ico(fr * 0.72, sub.x, sub.y, sub.z, leaf, {"d": 1, "l": TX.L_THATCH, "sc": Vector3(1.1, 0.75, 1.1), "sway": 0.38 * s, "jit": 0.12})

	if foliage_amt > 0.2:
		sp.ico(0.65 * s * (0.7 + foliage_amt * 0.5), p2.x, p2.y + 0.18 * s, p2.z, leaf_l, {"d": 1, "l": TX.L_THATCH, "sc": Vector3(1.2, 0.78, 1.2), "sway": 0.48 * s})


static func add_stump(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var bark := _c(pal, "bark")
	var C := Soup.COL()
	var r := 0.26 * s
	var h := (0.32 + rng.next_f() * 0.24) * s
	sp.cyl(r * 1.12, h, 0, h * 0.5, 0, bark, {"n": 7, "rt": 0.85, "l": TX.L_WOOD})
	sp.cyl(r * 0.88, 0.04, 0, h, 0, C["woodL"], {"n": 7, "l": TX.L_WOOD})
	for i in 3:
		var a := float(i) * TAU / 3.0 + rng.frange(-0.3, 0.3)
		sp.seg(Vector3(cos(a) * r * 0.5, h * 0.4, sin(a) * r * 0.5), Vector3(cos(a) * r * 1.7, -0.04, sin(a) * r * 1.7), r * 0.36, r * 0.12, bark, {"l": TX.L_WOOD, "n": 4})


static func add_grave(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var earth := _c(pal, "earth")
	var tilt := Vector3(rng.frange(-0.18, 0.18), rng.frange(-0.22, 0.22), rng.frange(-0.20, 0.20))
	var kind := rng.irange(0, 3)
	# Grave mound
	sp.dome(0.36, 0.14, 0.62, 0, -0.02, 0.45, earth, {"l": TX.L_DIRT, "w": 8, "h": 4})
	if kind == 0:
		# Classic rounded headstone
		sp.box(0.50, 0.72, 0.12, 0, 0.36, 0, st, {"l": TX.L_MASON, "r": tilt})
		sp.cyl(0.25, 0.12, 0, 0.72, 0, st, {"n": 8, "l": TX.L_MASON, "r": Vector3(PI * 0.5, 0, 0) + tilt})
	elif kind == 1:
		# Celtic / iron cross
		sp.box(0.12, 0.92, 0.10, 0, 0.46, 0, st_d, {"l": TX.L_ROCK, "r": tilt})
		sp.box(0.56, 0.12, 0.10, 0, 0.64, 0, st_d, {"l": TX.L_ROCK, "r": tilt})
	elif kind == 2:
		# Broken obelisk
		sp.cyl(0.20, 0.88, 0, 0.44, 0, st, {"n": 4, "rt": 0.68, "l": TX.L_MASON, "r": tilt})
		sp.box(0.54, 0.14, 0.54, 0, 0.07, 0, st_d, {"l": TX.L_MASON})
	else:
		# Weathered stone slab & ledger
		sp.box(0.58, 0.16, 1.02, 0, 0.08, 0.42, st_d, {"l": TX.L_MASON, "r": Vector3(0, rng.frange(-0.1, 0.1), 0)})
		sp.box(0.46, 0.48, 0.12, 0, 0.24, -0.14, st, {"l": TX.L_MASON, "r": tilt})


static func add_cart(sp: Soup, rng: U.Rng, broken: bool = false) -> void:
	var C := Soup.COL()
	var tilt := Vector3(0.18 if broken else 0.0, 0.0, -0.22 if broken else 0.0)
	sp.box(1.15, 0.10, 1.75, 0, 0.55, 0, C["wood"], {"l": TX.L_WOOD, "r": tilt})
	for sx in [-0.54, 0.54]:
		sp.box(0.08, 0.42, 1.75, sx, 0.78, 0, C["woodD"], {"l": TX.L_WOOD, "r": tilt})
		sp.box(0.08, 0.08, 0.95, sx * 0.72, 0.48, 1.32, C["wood"], {"l": TX.L_WOOD, "r": Vector3(0.22, 0, 0)})
	sp.box(1.12, 0.42, 0.08, 0, 0.78, -0.84, C["woodD"], {"l": TX.L_WOOD, "r": tilt})
	# Spoked wheels
	for sx in [-0.66, 0.66]:
		if broken and sx > 0.0:
			# Detached wheel lying flat nearby
			sp.torus(0.36, 1.18, 0.09, 0.25, C["woodD"], {"n": 10, "t": 0.14, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_WOOD})
			continue
		sp.torus(0.38, sx, 0.42, 0, C["woodD"], {"n": 10, "t": 0.15, "r": Vector3(0, PI * 0.5, 0), "l": TX.L_WOOD})
		for k in 4:
			var a := float(k) * PI * 0.25
			sp.box(0.05, 0.72, 0.05, sx, 0.42, 0, C["wood"], {"l": TX.L_WOOD, "r": Vector3(a, 0, 0)})
	if rng.chance(0.75):
		sp.box(0.45, 0.42, 0.45, -0.18, 0.82, -0.22, C["woodL"], {"l": TX.L_WOOD, "r": Vector3(0, 0.35, 0) + tilt})
		sp.cyl(0.20, 0.48, 0.24, 0.84, 0.18, C["wood"], {"n": 7, "l": TX.L_WOOD, "r": tilt})


static func add_bones(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	for _i in rng.irange(3, 6):
		var x := rng.frange(-0.45, 0.45)
		var z := rng.frange(-0.45, 0.45)
		var a := rng.frange(0, TAU)
		var ln := rng.frange(0.24, 0.46)
		sp.seg(Vector3(x - cos(a) * ln * 0.5, 0.04, z - sin(a) * ln * 0.5), Vector3(x + cos(a) * ln * 0.5, 0.05, z + sin(a) * ln * 0.5), 0.035, 0.03, C["bone"], {"l": TX.L_BONE, "n": 5})
	if rng.chance(0.7):
		add_skull(sp, rng.frange(-0.25, 0.25), 0.10, rng.frange(-0.25, 0.25), 1.0, rng.frange(0, TAU))


static func add_skull(sp: Soup, x: float, y: float, z: float, s: float = 1.0, ry: float = 0.0) -> void:
	var C := Soup.COL()
	sp.sph(0.11 * s, x, y + 0.02 * s, z, C["bone"], {"l": TX.L_BONE, "w": 7, "h": 5, "sc": Vector3(0.95, 1.05, 1.1)})
	var fx := sin(ry)
	var fz := cos(ry)
	var rx := fz
	var rz := -fx
	sp.box(0.10 * s, 0.06 * s, 0.08 * s, x + fx * 0.07 * s, y - 0.05 * s, z + fz * 0.07 * s, C["boneD"], {"l": TX.L_BONE, "r": Vector3(0, ry, 0)})
	for side in [-1.0, 1.0]:
		sp.box(0.035 * s, 0.035 * s, 0.03 * s, x + fx * 0.10 * s + rx * 0.042 * side * s, y + 0.01 * s, z + fz * 0.10 * s + rz * 0.042 * side * s, C["black"])


static func add_ribcage(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	sp.seg(Vector3(0, 0.05, -0.45), Vector3(0, 0.08, 0.45), 0.05, 0.045, C["boneD"], {"l": TX.L_BONE})
	for i in 5:
		var z := -0.34 + float(i) * 0.17
		for side in [-1.0, 1.0]:
			var mid := Vector3(side * 0.28, 0.24 + rng.frange(-0.03, 0.03), z)
			var tip := Vector3(side * 0.18, 0.42, z + 0.03)
			sp.seg(Vector3(0, 0.06, z), mid, 0.03, 0.025, C["bone"], {"l": TX.L_BONE, "n": 4})
			sp.seg(mid, tip, 0.025, 0.016, C["bone"], {"l": TX.L_BONE, "n": 4})


static func add_banner(sp: Soup, rng: U.Rng, col: Color, h: float = 2.6, col2: Color = Color(0.88, 0.68, 0.26)) -> void:
	var C := Soup.COL()
	sp.cyl(0.045, h, 0, h * 0.5, 0, C["woodD"], {"n": 6, "l": TX.L_WOOD})
	sp.box(0.74, 0.055, 0.055, 0, h - 0.16, 0.04, C["iron"], {"l": TX.L_METAL, "rough": 0.48})
	sp.cone(0.07, 0.22, 0, h + 0.10, 0, C["brass"], {"n": 5, "l": TX.L_METAL, "rough": 0.4})
	sp.cloth_panel({
		"x0": -0.32, "x1": 0.32, "y_top": h - 0.18, "len": h * 0.52, "z": 0.06,
		"col": col, "col2": col2, "rng": rng, "sway": 1.1, "rag": 0.36
	})


static func add_fence(sp: Soup, rng: U.Rng, segs: int = 3) -> void:
	var C := Soup.COL()
	var span := 1.05
	for i in segs + 1:
		var x := (float(i) - float(segs) * 0.5) * span
		var tilt := rng.frange(-0.12, 0.12)
		sp.box(0.11, 0.82, 0.11, x, 0.40, 0, C["woodD"], {"l": TX.L_WOOD, "r": Vector3(rng.frange(-0.08, 0.08), 0, tilt)})
	for i in segs:
		if rng.chance(0.18):
			continue
		var x0 := (float(i) - float(segs) * 0.5) * span
		var x1 := x0 + span
		sp.seg(Vector3(x0, 0.62, 0.03), Vector3(x1, 0.60 + rng.frange(-0.06, 0.06), 0.03), 0.042, 0.04, C["wood"], {"l": TX.L_WOOD, "n": 4})
		sp.seg(Vector3(x0, 0.32, 0.03), Vector3(x1, 0.30 + rng.frange(-0.05, 0.05), 0.03), 0.04, 0.038, C["wood"], {"l": TX.L_WOOD, "n": 4})


static func add_well(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var C := Soup.COL()
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	# Circular stone curb
	for i in 10:
		var a := float(i) * TAU / 10.0
		sp.box(0.32, 0.64, 0.24, cos(a) * 0.56, 0.32, sin(a) * 0.56, st if i % 2 == 0 else st_d, {"l": TX.L_MASON, "r": Vector3(0, -a, 0)})
	sp.cyl(0.46, 0.06, 0, 0.18, 0, C["black"], {"n": 10})
	# Timber roof frame
	for sx in [-0.58, 0.58]:
		sp.box(0.11, 1.55, 0.11, sx, 0.85, 0, C["woodD"], {"l": TX.L_WOOD})
	sp.cyl(0.055, 1.12, 0, 1.15, 0, C["wood"], {"n": 6, "r": Vector3(0, 0, PI * 0.5), "l": TX.L_WOOD})
	sp.box(1.55, 0.10, 0.82, 0, 1.72, -0.26, C["slate"], {"l": TX.L_SLATE, "r": Vector3(0.45, 0, 0)})
	sp.box(1.55, 0.10, 0.82, 0, 1.72, 0.26, C["slate"], {"l": TX.L_SLATE, "r": Vector3(-0.45, 0, 0)})
	if rng.chance(0.6):
		sp.cyl(0.14, 0.22, 0.12, 0.72, 0.14, C["woodL"], {"n": 6, "l": TX.L_WOOD})


static func add_ruined_wall(sp: Soup, rng: U.Rng, pal: Dictionary, length: float = 3.2) -> void:
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var n := maxi(4, int(length * 2.2))
	for i in n:
		var u := float(i) / float(n - 1) - 0.5
		var arch := 1.0 - absf(u) * 1.4
		var h := maxf(0.35, (0.9 + arch * 1.15 + rng.frange(-0.35, 0.35)))
		sp.box(length / float(n) * 1.06, h, 0.46 + rng.frange(-0.04, 0.06), u * length, h * 0.5 - 0.08, rng.frange(-0.04, 0.04), st if rng.chance(0.65) else st_d, {"l": TX.L_MASON, "uvs": 0.45})
	# Fallen rubble blocks nearby
	for _i in 4:
		sp.box(rng.frange(0.24, 0.44), rng.frange(0.18, 0.32), rng.frange(0.24, 0.44), rng.frange(-length * 0.55, length * 0.55), 0.10, rng.frange(-0.9, 0.9), st_d, {"l": TX.L_ROCK, "r": Vector3(rng.frange(-0.4, 0.4), rng.frange(0, TAU), rng.frange(-0.4, 0.4))})


static func add_ruined_tower(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var r := 1.25
	for i in 12:
		var a := float(i) * TAU / 12.0
		var gap := (i >= 3 and i <= 5)
		var h := rng.frange(0.55, 1.05) if gap else rng.frange(2.1, 3.6)
		sp.box(0.66, h, 0.44, cos(a) * r, h * 0.5 - 0.12, sin(a) * r, st if i % 2 == 0 else st_d, {"l": TX.L_MASON, "r": Vector3(0, -a, 0), "uvs": 0.4})
	for _i in 6:
		var a := rng.frange(0, TAU)
		var d := rng.frange(0.3, 1.9)
		sp.rock(rng.frange(0.22, 0.42), cos(a) * d, 0.10, sin(a) * d, st_d)


static func add_signpost(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	sp.box(0.11, 1.55, 0.11, 0, 0.76, 0, C["woodD"], {"l": TX.L_WOOD, "r": Vector3(0, 0, rng.frange(-0.08, 0.08))})
	sp.box(0.84, 0.20, 0.05, 0.12, 1.32, 0.06, C["wood"], {"l": TX.L_WOOD, "r": Vector3(0, rng.frange(-0.25, 0.25), 0.05)})
	if rng.chance(0.65):
		sp.box(0.72, 0.18, 0.05, -0.10, 1.06, -0.06, C["woodL"], {"l": TX.L_WOOD, "r": Vector3(0, rng.frange(-0.4, 0.4), -0.08)})


static func add_gibbet(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	sp.box(0.16, 2.7, 0.16, 0, 1.32, 0, C["woodD"], {"l": TX.L_WOOD})
	sp.box(1.15, 0.14, 0.14, 0.46, 2.55, 0, C["woodD"], {"l": TX.L_WOOD})
	sp.seg(Vector3(0.05, 2.0, 0), Vector3(0.55, 2.52, 0), 0.05, 0.05, C["wood"], {"l": TX.L_WOOD})
	# Hanging iron cage
	sp.seg(Vector3(0.92, 2.50, 0), Vector3(0.92, 1.92, 0), 0.02, 0.02, C["iron"], {"l": TX.L_METAL})
	sp.cyl(0.24, 0.06, 0.92, 1.90, 0, C["iron"], {"n": 6, "l": TX.L_METAL})
	sp.cyl(0.24, 0.06, 0.92, 1.24, 0, C["iron"], {"n": 6, "l": TX.L_METAL})
	for i in 6:
		var a := float(i) * TAU / 6.0
		sp.seg(Vector3(0.92 + cos(a) * 0.22, 1.90, sin(a) * 0.22), Vector3(0.92 + cos(a) * 0.22, 1.24, sin(a) * 0.22), 0.018, 0.018, C["iron"], {"l": TX.L_METAL, "n": 4})
	if rng.chance(0.7):
		add_skull(sp, 0.92, 1.40, 0.0, 0.95, rng.frange(0, TAU))


static func add_cairn(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var rk := _c(pal, "rock")
	var st := _c(pal, "stone")
	var y := 0.08
	var r := 0.34
	for i in 4:
		sp.rock(r, rng.frange(-0.04, 0.04), y, rng.frange(-0.04, 0.04), st if i % 2 == 0 else rk, {"sq": 0.56})
		y += r * 0.85
		r *= 0.72


static func add_statue(sp: Soup, pal: Dictionary) -> void:
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	sp.box(0.96, 0.22, 0.96, 0, 0.11, 0, st_d, {"l": TX.L_MASON})
	sp.box(0.72, 0.68, 0.72, 0, 0.54, 0, st, {"l": TX.L_MASON})
	# Cloaked weathered figure
	sp.cyl(0.28, 1.22, 0, 1.48, 0, st, {"n": 8, "rt": 0.68, "l": TX.L_ROCK})
	sp.sph(0.18, 0, 2.20, 0.02, st, {"l": TX.L_ROCK, "w": 8, "h": 6})
	sp.box(0.10, 1.15, 0.06, 0, 1.48, 0.26, st_d, {"l": TX.L_ROCK})
	sp.box(0.36, 0.08, 0.08, 0, 1.82, 0.26, st_d, {"l": TX.L_ROCK})


static func add_grass_tuft(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var ta := _c(pal, "tuftA")
	var tb := _c(pal, "tuftB")
	var nb := rng.irange(4, 7)
	for _i in nb:
		var a := rng.frange(0, TAU)
		var h := rng.frange(0.22, 0.46) * s
		var w := 0.065 * s
		var lean := rng.frange(0.08, 0.24) * s
		var c := U.mix_c(ta, tb, rng.next_f())
		var dx := cos(a)
		var dz := sin(a)
		var px := -dz * w
		var pz := dx * w
		var ox := rng.frange(-0.12, 0.12) * s
		var oz := rng.frange(-0.12, 0.12) * s
		var v0 := Vector3(ox - px, 0.0, oz - pz)
		var v1 := Vector3(ox + px, 0.0, oz + pz)
		var vt := Vector3(ox + dx * lean, h, oz + dz * lean)
		sp.tri(v0, vt, v1, c, TX.L_THATCH, 0.94, {"sway": 0.55 * s})
		sp.tri(v1, vt, v0, c, TX.L_THATCH, 0.94, {"sway": 0.55 * s})


static func add_lantern_post(sp: Soup, rng: U.Rng, pal: Dictionary) -> Vector3:
	var C := Soup.COL()
	var st := _c(pal, "stoneD")
	sp.box(0.36, 0.22, 0.36, 0, 0.11, 0, st, {"l": TX.L_MASON})
	sp.box(0.11, 2.05, 0.11, 0, 1.12, 0, C["woodD"], {"l": TX.L_WOOD})
	sp.box(0.56, 0.09, 0.09, 0.24, 2.08, 0, C["iron"], {"l": TX.L_METAL, "rough": 0.5})
	sp.cyl(0.14, 0.24, 0.46, 1.86, 0, C["iron"], {"n": 6, "l": TX.L_METAL, "rough": 0.45})
	sp.cyl(0.09, 0.16, 0.46, 1.86, 0, C["ember"], {"n": 6, "l": TX.L_PLAIN, "emis": 1.6})
	if rng.chance(0.5):
		sp.cone(0.18, 0.14, 0.46, 2.04, 0, C["iron"], {"n": 6, "l": TX.L_METAL})
	return Vector3(0.46, 1.86, 0.0)


# ============================================================================
# Structural Landmarks (Bridge, Pads, Keep + Beacon Tower, Cave Mouth)
# ============================================================================

static func build_bridge(pal: Dictionary, width: float, span: float, frost: bool = false) -> Soup:
	var sp := Soup.new()
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var st_l := _c(pal, "stoneL")
	var C := Soup.COL()
	var segs := 10
	for i in segs:
		var u0 := float(i) / float(segs) - 0.5
		var u1 := float(i + 1) / float(segs) - 0.5
		var um := (u0 + u1) * 0.5
		var arch := cos(um * PI) * 0.48
		var seg_l := span / float(segs) * 1.06
		var slope := -sin(um * PI) * 0.48 * PI / span
		# Cobble deck
		sp.box(seg_l, 0.26, width, um * span, arch + 0.04, 0, st if i % 2 == 0 else st_l, {"l": TX.L_COBBLE, "r": Vector3(0, 0, atan(slope)), "uvs": 0.55})
		# Underside masonry arch rib
		sp.box(seg_l, 0.42, width * 0.92, um * span, arch - 0.22, 0, st_d, {"l": TX.L_MASON, "r": Vector3(0, 0, atan(slope))})
		# Low stone parapets on both sides
		for sz in [-width * 0.48, width * 0.48]:
			sp.box(seg_l * 0.96, 0.42, 0.22, um * span, arch + 0.34, sz, st_d, {"l": TX.L_MASON, "r": Vector3(0, 0, atan(slope))})
			sp.box(seg_l * 1.02, 0.10, 0.28, um * span, arch + 0.56, sz, st_l, {"l": TX.L_MASON, "r": Vector3(0, 0, atan(slope))})
	# Corner bridge piers + finials
	for sx in [-span * 0.5, span * 0.5]:
		for sz in [-width * 0.48, width * 0.48]:
			sp.box(0.42, 1.35, 0.42, sx, 0.18, sz, st_d, {"l": TX.L_MASON})
			sp.box(0.48, 0.14, 0.48, sx, 0.88, sz, st_l, {"l": TX.L_MASON})
	if frost:
		# Hanging icicles under bridge arch
		for i in 9:
			var x := lerpf(-span * 0.42, span * 0.42, float(i) / 8.0)
			var arch := cos((x / span) * PI) * 0.48
			for sz in [-width * 0.42, width * 0.42]:
				sp.cone(0.06, 0.42 + fmod(float(i) * 0.13, 0.25), x, arch - 0.48, sz, C["ice"], {"n": 5, "r": Vector3(PI, 0, 0), "l": TX.L_PLAIN, "rough": 0.22})
	return sp


static func build_pad(pal: Dictionary) -> Soup:
	var sp := Soup.new()
	var C := Soup.COL()
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var st_l := _c(pal, "stoneL")
	# Octagonal foundation plinth
	sp.cyl(1.42, 0.26, 0, 0.04, 0, st_d, {"n": 8, "rt": 0.94, "l": TX.L_MASON, "uvs": 0.48})
	sp.cyl(1.26, 0.10, 0, 0.20, 0, st, {"n": 8, "l": TX.L_COBBLE, "uvs": 0.65})
	# Brass inlaid compass ring + corner studs
	sp.torus(0.86, 0, 0.255, 0, C["brass"], {"n": 12, "t": 0.045, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.38})
	for i in 8:
		var a := float(i) * PI * 0.25 + PI * 0.125
		sp.box(0.18, 0.12, 0.18, cos(a) * 1.18, 0.22, sin(a) * 1.18, st_l, {"l": TX.L_MASON, "r": Vector3(0, -a, 0)})
		if i % 2 == 0:
			sp.box(0.08, 0.04, 0.55, cos(a) * 0.56, 0.255, sin(a) * 0.56, C["brass"], {"l": TX.L_METAL, "rough": 0.36, "r": Vector3(0, -a + PI * 0.5, 0)})
	return sp


static func build_keep(pal: Dictionary, rng: U.Rng) -> Dictionary:
	var C := Soup.COL()
	var st := _c(pal, "stone")
	var st_d := _c(pal, "stoneD")
	var st_l := _c(pal, "stoneL")

	var keep := Soup.new()
	# Broad raised keep foundation plinth
	keep.box(5.8, 1.3, 5.4, 0, 0.25, 0, st_d, {"l": TX.L_MASON, "uvs": 0.36})
	# Main fortress body
	keep.box(4.8, 3.0, 4.4, 0, 2.2, -0.1, st, {"l": TX.L_MASON, "uvs": 0.38})
	# Crenellated roof parapet
	for i in 5:
		var x := -2.1 + float(i) * 1.05
		keep.box(0.55, 0.55, 0.44, x, 3.92, 1.92, st_l, {"l": TX.L_MASON})
		keep.box(0.55, 0.55, 0.44, x, 3.92, -2.12, st_l, {"l": TX.L_MASON})
	for j in 4:
		var z := -1.6 + float(j) * 1.06
		keep.box(0.44, 0.55, 0.55, -2.22, 3.92, z, st_l, {"l": TX.L_MASON})
		keep.box(0.44, 0.55, 0.55, 2.22, 3.92, z, st_l, {"l": TX.L_MASON})

	# 4 Corner Drum Turrets with slate roofs
	for sx in [-2.35, 2.35]:
		for sz in [-2.15, 2.15]:
			keep.cyl(0.82, 4.4, sx, 2.15, sz, st_d, {"n": 8, "rt": 0.94, "l": TX.L_MASON, "uvs": 0.42})
			keep.cyl(0.92, 0.26, sx, 4.38, sz, st_l, {"n": 8, "l": TX.L_MASON})
			keep.cone(1.02, 1.35, sx, 5.16, sz, C["slate"], {"n": 8, "l": TX.L_SLATE, "uvs": 0.7})
			keep.cyl(0.05, 0.55, sx, 5.95, sz, C["iron"], {"n": 5, "l": TX.L_METAL})

	# Gatehouse entrance arch + iron portcullis + dark interior
	keep.box(1.75, 2.15, 0.55, 0, 1.65, 2.12, st_d, {"l": TX.L_MASON})
	keep.box(1.30, 1.80, 0.40, 0, 1.48, 2.18, C["black"], {"l": TX.L_PLAIN})
	for i in 5:
		var bx := -0.50 + float(i) * 0.25
		keep.box(0.05, 1.65, 0.05, bx, 1.56, 2.36, C["iron"], {"l": TX.L_METAL, "rough": 0.45})
	for j in 3:
		keep.box(1.24, 0.05, 0.05, 0, 1.0 + float(j) * 0.42, 2.36, C["iron"], {"l": TX.L_METAL, "rough": 0.45})
	# Stone steps up to gate
	keep.box(2.2, 0.24, 0.9, 0, 0.12, 2.85, st_l, {"l": TX.L_COBBLE})
	keep.box(1.9, 0.22, 0.65, 0, 0.34, 2.58, st, {"l": TX.L_COBBLE})

	# Gatehouse fluttering banners
	for sx in [-1.45, 1.45]:
		keep.box(0.56, 0.06, 0.06, sx, 3.25, 2.32, C["iron"], {"l": TX.L_METAL})
		keep.cloth_panel({
			"x0": sx - 0.24, "x1": sx + 0.24, "y_top": 3.22, "len": 1.38, "z": 2.34,
			"col": C["clothR"], "col2": C["gold"], "rng": rng, "sway": 0.95, "rag": 0.28
		})

	# Wall fire sconces flanking gate
	var sconces: Array[Vector3] = []
	for sx in [-1.18, 1.18]:
		keep.box(0.14, 0.34, 0.24, sx, 2.05, 2.34, C["iron"], {"l": TX.L_METAL, "rough": 0.48})
		keep.cyl(0.16, 0.18, sx, 2.26, 2.42, C["iron"], {"n": 6, "rt": 1.2, "l": TX.L_METAL})
		sconces.append(Vector3(sx, 2.36, 2.42))

	# Separate tall Beacon Spire Tower (rises dramatically during stage transitions!)
	var beacon := Soup.new()
	beacon.cyl(1.18, 3.8, 0, 5.2, -0.25, st, {"n": 8, "rt": 0.86, "l": TX.L_MASON, "uvs": 0.4})
	beacon.cyl(1.26, 0.36, 0, 7.12, -0.25, st_l, {"n": 8, "l": TX.L_MASON})
	# Ornate iron brazier cage on top
	beacon.cyl(0.95, 0.48, 0, 7.52, -0.25, C["iron"], {"n": 8, "rt": 1.24, "l": TX.L_METAL, "rough": 0.44})
	beacon.cyl(0.76, 0.18, 0, 7.66, -0.25, C["ember"], {"n": 8, "l": TX.L_ROCK, "emis": 1.45})
	for i in 8:
		var a := float(i) * PI * 0.25
		beacon.box(0.10, 0.88, 0.10, cos(a) * 0.96, 7.82, -0.25 + sin(a) * 0.96, C["iron"], {"l": TX.L_METAL, "r": Vector3(0, -a, 0.16)})
	# Glowing arrow slits on beacon shaft
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		beacon.box(0.16, 0.72, 0.12, cos(a) * 1.06, 5.4, -0.25 + sin(a) * 1.06, C["ember"], {"l": TX.L_PLAIN, "emis": 1.35, "r": Vector3(0, -a, 0)})

	return {
		"keep": keep,
		"beacon": beacon,
		"flame_local": Vector3(0.0, 7.88, -0.25),
		"sconces": sconces,
	}


static func build_cave(pal: Dictionary, rng: U.Rng, frost: bool = false) -> Soup:
	var sp := Soup.new()
	var C := Soup.COL()
	var rk := _c(pal, "rock")
	var st_d := _c(pal, "stoneD")

	# Craggy mountain arch boulders framing the spawn tunnel
	for i in 9:
		var u := float(i) / 8.0
		var a := lerpf(-0.1, PI + 0.1, u)
		var r := 2.35 + rng.frange(-0.22, 0.25)
		var px := cos(a) * r
		var py := maxf(0.25, sin(a) * 2.55)
		var pz := rng.frange(-0.55, 0.45)
		sp.rock(rng.frange(0.85, 1.35), px, py, pz, rk if i % 2 == 0 else st_d, {"sq": 0.82})
	# Heavy rocky mound behind cave mouth
	for _i in 10:
		sp.rock(rng.frange(1.0, 1.75), rng.frange(-2.6, 2.6), rng.frange(0.6, 2.4), rng.frange(-2.8, -0.9), rk, {"sq": 0.78})
	# Pitch-black tunnel interior depth box
	sp.box(3.3, 2.8, 2.4, 0, 1.35, -1.15, C["black"], {"l": TX.L_PLAIN})

	# Hanging stalactites (or icicles in Frostfall)
	for i in 6:
		var sx := lerpf(-1.3, 1.3, float(i) / 5.0)
		var ln := rng.frange(0.35, 0.78)
		sp.cone(0.11, ln, sx, 2.32 - ln * 0.45, 0.32 + rng.frange(-0.15, 0.15), C["ice"] if frost else st_d, {"n": 5, "r": Vector3(PI, 0, 0), "l": TX.L_PLAIN if frost else TX.L_ROCK, "rough": 0.22 if frost else 0.9})

	# Warning skulls on wooden pikes flanking the cave entrance
	for side in [-1.0, 1.0]:
		var px: float = side * 2.15
		var pz := 1.05
		sp.cyl(0.055, 1.55, px, 0.75, pz, C["woodD"], {"n": 5, "l": TX.L_WOOD, "r": Vector3(0.08, 0, -side * 0.12)})
		add_skull(sp, px + side * 0.08, 1.55, pz + 0.06, 1.15, -side * 0.35)

	return sp
