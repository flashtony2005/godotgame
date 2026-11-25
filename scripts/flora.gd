extends RefCounted
## Complete Biome Flora & Ecological Dressing Builders (ported from 33-flora.js).
## Includes: Snow-laden Pines, Swaying Weeping Willows, Charred Ember-Tipped Trees, Desert Palms,
## Saguaro Cacti, Cattail Reeds, Flowering Lily Pads, Glowing Mire Mushrooms, Fallen Logs,
## Hexagonal Basalt Columns, Mesa Rock Spires, Molten Lava Vents, Terracotta Jars, Snow Drifts, and Ice Crystals.

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")
const Soup = preload("res://scripts/soup.gd")
const Props = preload("res://scripts/props.gd")


static func _c(pal: Dictionary, k: String) -> Color:
	var base := Soup.COL()
	return pal.get(k, base.get(k, Color.WHITE))


# ============================================================================
# Biome-Specific Flora Builders
# ============================================================================

static func add_pine(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0, snowy: bool = true) -> void:
	var C := Soup.COL()
	var bark := _c(pal, "bark")
	var leaf := _c(pal, "leaf")
	var leaf_l := _c(pal, "leafL")
	var h := (3.2 + rng.next_f() * 1.8) * s
	sp.cyl(0.18 * s, h * 0.62, 0, h * 0.30, 0, bark, {"n": 6, "rt": 0.45, "l": TX.L_WOOD})
	var tiers := 4
	for i in tiers:
		var f := float(i) / float(tiers - 1)
		var y := h * (0.34 + f * 0.56)
		var rad := lerpf(1.18, 0.34, f) * s
		var th := lerpf(1.22, 0.72, f) * s
		var col := U.mix_c(leaf, leaf_l, f * 0.6 + rng.next_f() * 0.25)
		sp.cone(rad, th, 0, y, 0, col, {"n": 7, "l": TX.L_THATCH, "sway": (0.14 + f * 0.35) * s, "r": Vector3(0, rng.frange(0, TAU), 0)})
		if snowy:
			sp.cone(rad * 0.88, th * 0.54, 0, y + th * 0.24, 0, C["snow"], {"n": 7, "l": TX.L_PLAIN, "rough": 0.62, "sway": (0.14 + f * 0.35) * s})


static func add_willow(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var bark := _c(pal, "bark")
	var leaf := _c(pal, "leaf")
	var leaf_l := _c(pal, "leafL")
	var h := (2.6 + rng.next_f() * 1.1) * s
	var lean := Vector3(rng.frange(-0.35, 0.35) * s, 0, rng.frange(-0.35, 0.35) * s)
	var top := Vector3(lean.x, h, lean.z)
	sp.seg(Vector3(0, -0.08, 0), top, 0.26 * s, 0.14 * s, bark, {"l": TX.L_WOOD, "n": 7})
	# Sweeping branches + swaying hanging vine ribbons
	for i in 7:
		var a := float(i) * TAU / 7.0 + rng.frange(-0.3, 0.3)
		var reach := (1.2 + rng.next_f() * 0.65) * s
		var tip := top + Vector3(cos(a) * reach, rng.frange(-0.15, 0.45) * s, sin(a) * reach)
		sp.seg(top * 0.86, tip, 0.11 * s, 0.04 * s, bark, {"l": TX.L_WOOD, "n": 4})
		sp.ico(0.48 * s, tip.x, tip.y + 0.12 * s, tip.z, U.mix_c(leaf, leaf_l, rng.next_f()), {"d": 1, "sc": Vector3(1.15, 0.65, 1.15), "l": TX.L_THATCH, "sway": 0.35 * s})
		# 3 hanging swaying willow curtains per bough
		for j in 3:
			var ja := a + float(j - 1) * 0.35
			var vx := tip.x + cos(ja) * 0.26 * s
			var vz := tip.z + sin(ja) * 0.26 * s
			var vlen := rng.frange(1.2, 2.0) * s
			sp.box(0.09 * s, vlen, 0.03 * s, vx, tip.y - vlen * 0.48, vz, leaf if j % 2 == 0 else leaf_l, {"l": TX.L_THATCH, "sway": 0.95 * s, "r": Vector3(0, ja, 0)})


static func add_charred_tree(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var C := Soup.COL()
	var bark := _c(pal, "bark")
	var h := (2.4 + rng.next_f() * 1.5) * s
	var p1 := Vector3(rng.frange(-0.2, 0.2) * s, h * 0.55, rng.frange(-0.2, 0.2) * s)
	var p2 := Vector3(rng.frange(-0.35, 0.35) * s, h, rng.frange(-0.35, 0.35) * s)
	sp.seg(Vector3(0, -0.08, 0), p1, 0.22 * s, 0.14 * s, bark, {"l": TX.L_WOOD, "n": 6})
	sp.seg(p1, p2, 0.14 * s, 0.05 * s, bark, {"l": TX.L_WOOD, "n": 5})
	for i in 5:
		var a := float(i) * TAU / 5.0 + rng.frange(-0.4, 0.4)
		var st := p1.lerp(p2, rng.frange(0.2, 0.92))
		var tip := st + Vector3(cos(a) * rng.frange(0.65, 1.35) * s, rng.frange(0.25, 0.85) * s, sin(a) * rng.frange(0.65, 1.35) * s)
		sp.seg(st, tip, 0.08 * s, 0.025 * s, bark, {"l": TX.L_WOOD, "n": 4})
		# Smoldering glowing ember branch tips
		if rng.chance(0.55):
			sp.ico(0.065 * s, tip.x, tip.y, tip.z, C["ember"], {"d": 0, "l": TX.L_PLAIN, "emis": 1.65})


static func add_palm(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var bark := _c(pal, "bark")
	var leaf := _c(pal, "leaf")
	var leaf_l := _c(pal, "leafL")
	var h := (3.1 + rng.next_f() * 1.5) * s
	var curve_a := rng.frange(0, TAU)
	var bend := rng.frange(0.45, 0.95) * s
	var segs := 6
	var prev := Vector3(0, -0.06, 0)
	for i in segs:
		var f := float(i + 1) / float(segs)
		var cur := Vector3(cos(curve_a) * bend * f * f, h * f, sin(curve_a) * bend * f * f)
		sp.seg(prev, cur, lerpf(0.18, 0.10, f) * s, lerpf(0.15, 0.08, f) * s, bark, {"l": TX.L_WOOD, "n": 6})
		prev = cur
	# Coconuts
	for i in 3:
		var a := float(i) * TAU / 3.0
		sp.sph(0.09 * s, prev.x + cos(a) * 0.14 * s, prev.y - 0.12 * s, prev.z + sin(a) * 0.14 * s, bark, {"w": 6, "h": 4})
	# Sweeping arched palm fronds
	for i in 7:
		var a := float(i) * TAU / 7.0 + rng.frange(-0.2, 0.2)
		var fl := (1.15 + rng.next_f() * 0.45) * s
		var mid := prev + Vector3(cos(a) * fl * 0.55, 0.26 * s, sin(a) * fl * 0.55)
		var tip := prev + Vector3(cos(a) * fl, -0.32 * s, sin(a) * fl)
		var fc := leaf if i % 2 == 0 else leaf_l
		sp.seg(prev, mid, 0.14 * s, 0.10 * s, fc, {"l": TX.L_THATCH, "n": 4, "sway": 0.42 * s})
		sp.seg(mid, tip, 0.10 * s, 0.02 * s, fc, {"l": TX.L_THATCH, "n": 4, "sway": 0.72 * s})


static func add_cactus(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var col := _c(pal, "leaf")
	var col_l := _c(pal, "leafL")
	var h := (1.45 + rng.next_f() * 1.1) * s
	sp.cyl(0.18 * s, h, 0, h * 0.5, 0, col, {"n": 7, "l": TX.L_PLAIN})
	sp.sph(0.18 * s, 0, h, 0, col_l, {"w": 7, "h": 5})
	# 1 or 2 saguaro arms
	var arms := rng.irange(1, 2)
	for i in arms:
		var side := -1.0 if i == 0 else 1.0
		var ay := h * rng.frange(0.36, 0.62)
		var ah := h * rng.frange(0.32, 0.52)
		sp.seg(Vector3(0, ay, 0), Vector3(side * 0.38 * s, ay + 0.06 * s, 0), 0.13 * s, 0.12 * s, col, {"n": 6})
		sp.cyl(0.12 * s, ah, side * 0.38 * s, ay + 0.06 * s + ah * 0.5, 0, col, {"n": 6})
		sp.sph(0.12 * s, side * 0.38 * s, ay + 0.06 * s + ah, 0, col_l, {"w": 6, "h": 4})
	if rng.chance(0.45):
		sp.ico(0.09 * s, 0, h + 0.16 * s, 0, U.col_hex(0xe86442), {"d": 0})


static func add_reeds(sp: Soup, rng: U.Rng, pal: Dictionary, s: float = 1.0) -> void:
	var C := Soup.COL()
	var ta := _c(pal, "tuftA")
	var tb := _c(pal, "tuftB")
	var n := rng.irange(5, 9)
	for _i in n:
		var ox := rng.frange(-0.28, 0.28) * s
		var oz := rng.frange(-0.28, 0.28) * s
		var h := rng.frange(0.75, 1.35) * s
		var lx := rng.frange(-0.14, 0.14) * s
		var lz := rng.frange(-0.14, 0.14) * s
		sp.seg(Vector3(ox, -0.05, oz), Vector3(ox + lx, h, oz + lz), 0.028 * s, 0.012 * s, U.mix_c(ta, tb, rng.next_f()), {"n": 4, "sway": 0.65 * s})
		if rng.chance(0.45):
			sp.cyl(0.042 * s, 0.20 * s, ox + lx * 0.82, h * 0.82, oz + lz * 0.82, C["woodD"], {"n": 5, "sway": 0.55 * s})


static func add_lily_pad(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var lf := _c(pal, "leaf")
	var lf_l := _c(pal, "leafL")
	var r := rng.frange(0.22, 0.42)
	sp.cyl(r, 0.025, 0, 0.02, 0, U.mix_c(lf, lf_l, rng.next_f()), {"n": 8, "l": TX.L_PLAIN})
	if rng.chance(0.35):
		sp.ico(0.085, 0.03, 0.075, 0.02, U.col_hex(0xf4d8c8), {"d": 0, "emis": 0.25})


static func add_mushroom(sp: Soup, rng: U.Rng, glow_col: Color) -> void:
	var C := Soup.COL()
	var cnt := rng.irange(2, 4)
	for i in cnt:
		var ox := 0.0 if i == 0 else rng.frange(-0.32, 0.32)
		var oz := 0.0 if i == 0 else rng.frange(-0.32, 0.32)
		var s := rng.frange(0.7, 1.35) if i == 0 else rng.frange(0.45, 0.85)
		var h := 0.32 * s
		sp.cyl(0.05 * s, h, ox, h * 0.5, oz, C["boneD"], {"n": 5, "l": TX.L_PLAIN})
		sp.dome(0.22 * s, 0.14 * s, 0.22 * s, ox, h - 0.02, oz, glow_col, {"w": 8, "h": 4, "l": TX.L_PLAIN, "emis": 1.15})


static func add_fallen_log(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var bark := _c(pal, "bark")
	var leaf := _c(pal, "leaf")
	var ln := rng.frange(1.6, 2.8)
	var r := rng.frange(0.18, 0.28)
	sp.cyl(r, ln, 0, r * 0.72, 0, bark, {"n": 7, "rt": 0.85, "r": Vector3(0, 0, PI * 0.5), "l": TX.L_WOOD})
	if rng.chance(0.7):
		sp.ico(r * 0.85, rng.frange(-ln * 0.3, ln * 0.3), r * 1.2, 0, leaf, {"d": 1, "sc": Vector3(1.4, 0.55, 0.9), "l": TX.L_THATCH})


static func add_basalt_column(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var rk := _c(pal, "rock")
	var st_d := _c(pal, "stoneD")
	var cnt := rng.irange(3, 5)
	for i in cnt:
		var a := float(i) * TAU / float(cnt) + rng.frange(-0.2, 0.2)
		var d := 0.0 if i == 0 else rng.frange(0.32, 0.62)
		var h := rng.frange(1.4, 3.2) if i == 0 else rng.frange(0.65, 2.0)
		var r := rng.frange(0.24, 0.38)
		sp.cyl(r, h, cos(a) * d, h * 0.5 - 0.15, sin(a) * d, rk if i % 2 == 0 else st_d, {"n": 6, "l": TX.L_ROCK, "rough": 0.84})


static func add_rock_spire(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var st := _c(pal, "stone")
	var rk := _c(pal, "rock")
	var h := rng.frange(2.2, 4.4)
	var r := rng.frange(0.55, 0.95)
	sp.cyl(r, h * 0.65, 0, h * 0.30, 0, rk, {"n": 7, "rt": 0.62, "l": TX.L_ROCK})
	sp.cyl(r * 0.68, h * 0.42, 0, h * 0.78, 0, st, {"n": 7, "rt": 0.84, "l": TX.L_ROCK})
	sp.rock(r * 0.72, rng.frange(-0.5, 0.5), 0.22, rng.frange(-0.5, 0.5), rk, {"sq": 0.65})


static func add_lava_vent(sp: Soup, rng: U.Rng, pal: Dictionary) -> void:
	var C := Soup.COL()
	var rk := _c(pal, "rock")
	sp.cyl(0.88, 0.62, 0, 0.26, 0, rk, {"n": 8, "rt": 0.56, "l": TX.L_ROCK})
	sp.cyl(0.44, 0.14, 0, 0.55, 0, C["ember"], {"n": 8, "l": TX.L_PLAIN, "emis": 2.4})
	for i in 5:
		var a := float(i) * TAU / 5.0 + rng.frange(-0.25, 0.25)
		sp.rock(rng.frange(0.22, 0.36), cos(a) * 0.62, 0.16, sin(a) * 0.62, rk, {"sq": 0.7})


static func add_desert_jar(sp: Soup, rng: U.Rng) -> void:
	var clay := U.col_hex(0x9a5c3c)
	var clay_d := U.col_hex(0x6e3e28)
	var cnt := rng.irange(1, 3)
	for i in cnt:
		var ox := 0.0 if i == 0 else rng.frange(-0.42, 0.42)
		var oz := 0.0 if i == 0 else rng.frange(-0.42, 0.42)
		var s := rng.frange(0.75, 1.15)
		sp.sph(0.24 * s, ox, 0.26 * s, oz, clay if i % 2 == 0 else clay_d, {"w": 8, "h": 6, "sc": Vector3(0.95, 1.25, 0.95), "l": TX.L_PLAIN})
		sp.cyl(0.11 * s, 0.18 * s, ox, 0.54 * s, oz, clay_d, {"n": 8, "rt": 1.25, "l": TX.L_PLAIN})


static func add_snow_drift(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	sp.dome(rng.frange(0.75, 1.55), rng.frange(0.22, 0.46), rng.frange(0.55, 1.15), 0, -0.04, 0, C["snow"], {"w": 9, "h": 4, "l": TX.L_PLAIN, "rough": 0.62})


static func add_ice_crystal(sp: Soup, rng: U.Rng) -> void:
	var C := Soup.COL()
	var cnt := rng.irange(3, 5)
	for i in cnt:
		var a := float(i) * TAU / float(cnt) + rng.frange(-0.3, 0.3)
		var h := rng.frange(0.85, 1.85) if i == 0 else rng.frange(0.45, 1.15)
		var r := rng.frange(0.14, 0.24)
		var tilt := Vector3(rng.frange(-0.28, 0.28), a, rng.frange(-0.28, 0.28))
		sp.cone(r, h, cos(a) * (0.0 if i == 0 else 0.22), h * 0.45, sin(a) * (0.0 if i == 0 else 0.22), C["ice"], {"n": 5, "l": TX.L_PLAIN, "rough": 0.18, "emis": 0.35, "r": tilt})
