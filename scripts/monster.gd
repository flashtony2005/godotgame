extends Node3D
## Complete Instanced PartBatch Skeletal Rig System & 26-Creature Bestiary Renderer
## (ported & enhanced from 50-rig.js, 51-bestiary.js, 61-monsters.js).
## Renders every monster, boss, guard footman, tower archer, projectile, gold coin, shatter debris,
## and empty pad marker via GPU-instanced MultiMeshInstance3D batches with hit flash & biome tints!

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")
const Soup = preload("res://scripts/soup.gd")

# PartBatch dictionary: name -> {mm: MultiMesh, mmi: MultiMeshInstance3D, cap: int, count: int}
var batches: Dictionary = {}

# Dynamic visual physics pools (shatter debris, bouncing coins)
var debris: Array[Dictionary] = []
var coins: Array[Dictionary] = []


func _ready() -> void:
	TX.ensure()
	_build_all_kits()


func clear_pools() -> void:
	debris.clear()
	coins.clear()


func begin_frame() -> void:
	for k in batches:
		batches[k]["count"] = 0


func end_frame() -> void:
	for k in batches:
		var b: Dictionary = batches[k]
		var mm: MultiMesh = b["mm"]
		mm.visible_instance_count = int(b["count"])


func _reg(key: String, sp: Soup, cap: int, cast_sh: bool = true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = true
	mm.mesh = sp.build()
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "kit_%s" % key
	mmi.multimesh = mm
	mmi.material_override = TX.mat_inst
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 160.0
	add_child(mmi)
	batches[key] = {"mm": mm, "mmi": mmi, "cap": cap, "count": 0}


func push_part(key: String, xf: Transform3D, tint: Color = Color.WHITE, flash: float = 0.0) -> void:
	if not batches.has(key):
		return
	var b: Dictionary = batches[key]
	var idx: int = int(b["count"])
	if idx >= int(b["cap"]):
		return
	var mm: MultiMesh = b["mm"]
	mm.set_instance_transform(idx, xf)
	mm.set_instance_custom_data(idx, Color(tint.r, tint.g, tint.b, flash))
	b["count"] = idx + 1


# ============================================================================
# Kit Mesh Construction (every body part, weapon, armor, prop, pickup, debris)
# ============================================================================

func _build_all_kits() -> void:
	var C := Soup.COL()
	var rng := U.make_rng(5051)
	Soup.set_rng(rng)

	# --- 1. Humanoid / Skeleton / Footman / Boss parts ---
	var sp := Soup.new()
	sp.box(0.28, 0.34, 0.18, 0, 0.17, 0, C["bone"], {"l": TX.L_BONE})
	for ry in [0.08, 0.16, 0.24]:
		sp.box(0.32, 0.04, 0.21, 0, ry, 0, C["boneD"], {"l": TX.L_BONE})
	_reg("skel_torso", sp, 220)

	sp = Soup.new()
	sp.sph(0.14, 0, 0.12, 0, C["bone"], {"l": TX.L_BONE, "w": 8, "h": 6, "sc": Vector3(0.92, 1.05, 1.05)})
	sp.box(0.11, 0.07, 0.09, 0, 0.02, 0.08, C["boneD"], {"l": TX.L_BONE})
	_reg("skel_head", sp, 220)

	sp = Soup.new()
	sp.cyl(0.045, 0.36, 0, -0.18, 0, C["bone"], {"n": 6, "l": TX.L_BONE})
	_reg("skel_limb", sp, 700)

	# Armored Footman / Archer / Brute body
	sp = Soup.new()
	sp.box(0.34, 0.40, 0.22, 0, 0.20, 0, C["ironL"], {"l": TX.L_METAL, "rough": 0.46})
	sp.box(0.36, 0.12, 0.24, 0, 0.06, 0, C["clothR"], {"l": TX.L_CLOTH})
	_reg("foot_torso", sp, 160)

	sp = Soup.new()
	sp.sph(0.14, 0, 0.12, 0, C["skin"], {"w": 8, "h": 6})
	sp.dome(0.16, 0.15, 0.16, 0, 0.14, 0, C["steel"], {"w": 8, "h": 4, "l": TX.L_METAL, "rough": 0.36})
	_reg("foot_head", sp, 160)

	sp = Soup.new()
	sp.cyl(0.06, 0.36, 0, -0.18, 0, C["leather"], {"n": 6, "l": TX.L_CLOTH})
	_reg("foot_limb", sp, 500)

	# Heavy Ogre / Colossus / Golem torso & limbs
	sp = Soup.new()
	sp.sph(0.46, 0, 0.38, 0, C["ogre"], {"w": 9, "h": 7, "sc": Vector3(1.12, 1.05, 0.92), "l": TX.L_PLAIN})
	sp.box(0.72, 0.20, 0.52, 0, 0.08, 0, C["leather"], {"l": TX.L_CLOTH})
	_reg("ogre_torso", sp, 48)

	sp = Soup.new()
	sp.sph(0.24, 0, 0.18, 0, C["ogreD"], {"w": 8, "h": 6, "sc": Vector3(1.0, 0.92, 1.08)})
	sp.box(0.22, 0.08, 0.14, 0, 0.06, 0.16, C["bone"], {"l": TX.L_BONE})
	_reg("ogre_head", sp, 48)

	sp = Soup.new()
	sp.cyl(0.13, 0.56, 0, -0.26, 0, C["ogreD"], {"n": 7, "rt": 0.78})
	_reg("ogre_limb", sp, 160)

	# Stone Golem / Magma Colossus blocky body
	sp = Soup.new()
	sp.rock(0.48, 0, 0.38, 0, C["stone"], {"sq": 0.95})
	sp.box(0.24, 0.24, 0.14, 0, 0.42, 0.34, C["ember"], {"emis": 1.6})
	_reg("golem_torso", sp, 64)

	sp = Soup.new()
	sp.rock(0.24, 0, 0.18, 0, C["stoneD"], {"sq": 0.92})
	_reg("golem_head", sp, 64)

	sp = Soup.new()
	sp.box(0.22, 0.54, 0.22, 0, -0.26, 0, C["stoneD"], {"l": TX.L_ROCK})
	_reg("golem_limb", sp, 220)

	# --- 2. Creature Kits (Rat, Slime, Bat, Gargoyle, Spider, Wolf, Wraith, Wisp, Toad) ---
	# Rat / Scarab body + head + tail
	sp = Soup.new()
	sp.sph(0.20, 0, 0.14, 0, C["rat"], {"w": 8, "h": 6, "sc": Vector3(0.85, 0.72, 1.45)})
	sp.cone(0.11, 0.22, 0, 0.13, 0.30, C["ratD"], {"n": 6, "r": Vector3(PI * 0.5, 0, 0)})
	sp.sph(0.055, -0.09, 0.22, 0.16, C["ratD"], {"w": 5, "h": 4})
	sp.sph(0.055, 0.09, 0.22, 0.16, C["ratD"], {"w": 5, "h": 4})
	_reg("rat_body", sp, 160)

	sp = Soup.new()
	sp.seg(Vector3(0, 0, 0), Vector3(0, 0.05, -0.42), 0.032, 0.01, C["skin"], {"n": 4})
	_reg("rat_tail", sp, 160)

	# Slime dome blob
	sp = Soup.new()
	sp.dome(0.36, 0.38, 0.36, 0, 0.0, 0, C["slime"], {"w": 10, "h": 6, "l": TX.L_PLAIN, "rough": 0.22})
	sp.sph(0.14, 0.08, 0.16, 0.06, C["slimeD"], {"w": 6, "h": 4, "rough": 0.18})
	_reg("slime_body", sp, 140)

	# Bat / Gargoyle body + hinged wing
	sp = Soup.new()
	sp.sph(0.16, 0, 0.0, 0, C["bat"], {"w": 7, "h": 5, "sc": Vector3(0.85, 0.85, 1.25)})
	sp.cone(0.05, 0.14, -0.08, 0.14, 0.06, C["bat"], {"n": 4})
	sp.cone(0.05, 0.14, 0.08, 0.14, 0.06, C["bat"], {"n": 4})
	_reg("bat_body", sp, 140)

	sp = Soup.new()
	sp.tri(Vector3(0, 0, 0.08), Vector3(0.55, 0.08, 0.16), Vector3(0.42, -0.04, -0.22), C["bat"], TX.L_CLOTH, 0.85)
	sp.tri(Vector3(0, 0, 0.08), Vector3(0.42, -0.04, -0.22), Vector3(0, 0, -0.14), C["bat"], TX.L_CLOTH, 0.85)
	sp.tri(Vector3(0, 0, 0.08), Vector3(0.42, -0.04, -0.22), Vector3(0.55, 0.08, 0.16), C["bat"], TX.L_CLOTH, 0.85)
	sp.tri(Vector3(0, 0, 0.08), Vector3(0, 0, -0.14), Vector3(0.42, -0.04, -0.22), C["bat"], TX.L_CLOTH, 0.85)
	_reg("bat_wing", sp, 280)

	# Spider / Broodmother / Spider Queen abdomen + thorax + articulated leg
	sp = Soup.new()
	sp.sph(0.28, 0, 0.24, -0.22, C["basalt"], {"w": 8, "h": 6, "sc": Vector3(0.95, 0.88, 1.22)})
	sp.sph(0.16, 0, 0.20, 0.16, C["basaltL"], {"w": 7, "h": 5})
	sp.box(0.10, 0.06, 0.12, -0.06, 0.16, 0.30, C["clothR"])
	sp.box(0.10, 0.06, 0.12, 0.06, 0.16, 0.30, C["clothR"])
	_reg("spider_body", sp, 120)

	sp = Soup.new()
	sp.seg(Vector3(0, 0, 0), Vector3(0.26, 0.14, 0), 0.036, 0.028, C["basalt"], {"n": 4})
	sp.seg(Vector3(0.26, 0.14, 0), Vector3(0.46, -0.22, 0), 0.028, 0.012, C["basaltL"], {"n": 4})
	_reg("spider_leg", sp, 700)

	# Wolf body + head + tail
	sp = Soup.new()
	sp.box(0.28, 0.26, 0.62, 0, 0.34, 0, C["rat"], {"l": TX.L_CLOTH})
	sp.box(0.22, 0.20, 0.28, 0, 0.44, 0.36, C["ratD"], {"l": TX.L_CLOTH})
	sp.box(0.12, 0.10, 0.18, 0, 0.39, 0.54, C["ratD"])
	sp.cone(0.05, 0.12, -0.08, 0.58, 0.32, C["ratD"], {"n": 4})
	sp.cone(0.05, 0.12, 0.08, 0.58, 0.32, C["ratD"], {"n": 4})
	_reg("wolf_body", sp, 120)

	# Wraith cloaked phantom
	sp = Soup.new()
	sp.cone(0.32, 1.05, 0, 0.56, 0, C["clothD"], {"n": 8, "l": TX.L_CLOTH, "sway": 0.45})
	sp.sph(0.16, 0, 1.02, 0.04, C["black"], {"w": 7, "h": 5})
	sp.dome(0.20, 0.22, 0.22, 0, 1.04, 0.0, C["clothD"], {"w": 8, "h": 5, "l": TX.L_CLOTH})
	_reg("wraith_body", sp, 100)

	# Glowing Wisp orb
	sp = Soup.new()
	sp.ico(0.22, 0, 0, 0, C["crystal"], {"d": 1, "emis": 2.4})
	_reg("wisp_body", sp, 100, false)

	# Mire Toad body
	sp = Soup.new()
	sp.sph(0.30, 0, 0.22, 0, C["ogre"], {"w": 8, "h": 6, "sc": Vector3(1.12, 0.78, 1.22)})
	sp.sph(0.16, 0, 0.18, 0.22, C["ogreD"], {"w": 7, "h": 5, "sc": Vector3(1.2, 0.7, 0.9)})
	sp.sph(0.07, -0.14, 0.34, 0.18, C["gold"], {"w": 6, "h": 4, "emis": 0.5})
	sp.sph(0.07, 0.14, 0.34, 0.18, C["gold"], {"w": 6, "h": 4, "emis": 0.5})
	_reg("toad_body", sp, 100)

	# --- 3. Weapons, Shields, Helmets, Robes, Crowns, Kegs, Drums ---
	sp = Soup.new()
	sp.box(0.05, 0.58, 0.02, 0, 0.32, 0, C["steel"], {"l": TX.L_METAL, "rough": 0.3})
	sp.box(0.20, 0.04, 0.04, 0, 0.04, 0, C["brass"], {"l": TX.L_METAL, "rough": 0.38})
	sp.cyl(0.025, 0.14, 0, -0.05, 0, C["woodD"], {"n": 5})
	_reg("item_sword", sp, 220)

	sp = Soup.new()
	sp.cyl(0.22, 0.05, 0, 0, 0, C["wood"], {"n": 8, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_WOOD})
	sp.torus(0.22, 0, 0, 0, C["iron"], {"n": 8, "t": 0.14, "l": TX.L_METAL})
	sp.sph(0.06, 0, 0, 0.04, C["brass"], {"w": 6, "h": 4, "l": TX.L_METAL})
	_reg("item_shield", sp, 180)

	sp = Soup.new()
	sp.seg(Vector3(0, -0.28, 0), Vector3(0, 0, 0.14), 0.022, 0.025, C["woodL"], {"n": 4})
	sp.seg(Vector3(0, 0, 0.14), Vector3(0, 0.28, 0), 0.025, 0.022, C["woodL"], {"n": 4})
	_reg("item_bow", sp, 120)

	sp = Soup.new()
	sp.cyl(0.035, 1.15, 0, 0.45, 0, C["woodD"], {"n": 6, "l": TX.L_WOOD})
	sp.oct(0.11, 0.18, 0.11, 0, 1.06, 0, C["crystal"], {"emis": 2.1})
	_reg("item_staff", sp, 80)

	sp = Soup.new()
	sp.cyl(0.05, 0.85, 0, 0.42, 0, C["wood"], {"n": 6, "rt": 2.2, "l": TX.L_WOOD})
	_reg("item_club", sp, 80)

	sp = Soup.new()
	sp.cyl(0.20, 0.34, 0, 0.18, 0, C["woodD"], {"n": 8, "l": TX.L_WOOD})
	sp.cyl(0.21, 0.04, 0, 0.08, 0, C["iron"], {"n": 8, "l": TX.L_METAL})
	sp.cyl(0.21, 0.04, 0, 0.28, 0, C["iron"], {"n": 8, "l": TX.L_METAL})
	_reg("item_keg", sp, 80)

	sp = Soup.new()
	sp.cyl(0.18, 0.22, 0, 0.0, 0, C["wood"], {"n": 8, "l": TX.L_WOOD})
	sp.cyl(0.17, 0.03, 0, 0.12, 0, C["bone"], {"n": 8})
	_reg("item_drum", sp, 48)

	sp = Soup.new()
	sp.torus(0.14, 0, 0.05, 0, C["gold"], {"n": 8, "t": 0.22, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.3})
	for i in 5:
		var a := float(i) * TAU / 5.0
		sp.cone(0.03, 0.11, cos(a) * 0.14, 0.11, sin(a) * 0.14, C["gold"], {"n": 4, "l": TX.L_METAL})
	_reg("item_crown", sp, 32)

	sp = Soup.new()
	sp.cyl(0.24, 0.68, 0, 0.34, 0, C["clothR"], {"n": 8, "rt": 0.68, "l": TX.L_CLOTH})
	_reg("item_robe", sp, 100)

	# --- 4. Projectiles, Gold Coins, Shatter Debris, Pad Marker ---
	sp = Soup.new()
	sp.cyl(0.018, 0.68, 0, 0, 0, C["woodL"], {"n": 5, "r": Vector3(PI * 0.5, 0, 0)})
	sp.cone(0.045, 0.14, 0, 0, 0.36, C["steel"], {"n": 4, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL})
	sp.box(0.08, 0.015, 0.14, 0, 0, -0.28, C["ember"], {"emis": 1.4})
	_reg("proj_arrow", sp, 180, false)

	sp = Soup.new()
	sp.sph(0.18, 0, 0, 0, C["iron"], {"w": 8, "h": 6, "l": TX.L_METAL, "rough": 0.36})
	_reg("proj_shell", sp, 80)

	sp = Soup.new()
	sp.cyl(0.14, 0.045, 0, 0, 0, C["gold"], {"n": 8, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.25, "emis": 0.45})
	_reg("coin", sp, 160, false)

	sp = Soup.new()
	sp.rock(0.16, 0, 0, 0, C["stone"], {"sq": 0.8})
	_reg("debris_rock", sp, 260)

	sp = Soup.new()
	sp.box(0.08, 0.04, 0.34, 0, 0, 0, C["bone"], {"l": TX.L_BONE})
	_reg("debris_bone", sp, 260)

	sp = Soup.new()
	sp.box(0.12, 0.04, 0.46, 0, 0, 0, C["wood"], {"l": TX.L_WOOD})
	_reg("debris_plank", sp, 180)

	# Gentle floating compass crystal over empty build pads
	sp = Soup.new()
	sp.oct(0.18, 0.36, 0.18, 0, 0.0, 0, C["gold"], {"l": TX.L_METAL, "rough": 0.28, "emis": 1.1})
	_reg("pad_marker", sp, 16, false)


# ============================================================================
# Skeletal Rig Pose Emitters (All 26 Creatures + Archers + Footmen)
# ============================================================================

func emit_unit(u: Dictionary, t: float, fx_node: Node) -> void:
	var kind: String = String(u["kind"])
	var pos: Vector3 = u["pos"]
	var yaw: float = float(u["yaw"])
	var s: float = float(u["scale"])
	var ph: float = float(u["phase"])
	var flash: float = float(u["flash"])
	var tint: Color = u["tint"]
	var atk: float = float(u.get("atk_t", 0.0))
	var eye_col: Color = u.get("eye_col", Color(1.0, 0.35, 0.12))

	var b_root := Basis(Vector3.UP, yaw)
	var sw := sin(ph)
	var bob := absf(cos(ph)) * 0.07 * s
	var base := Transform3D(b_root.scaled(Vector3.ONE * s), pos + Vector3(0.0, bob, 0.0))

	match kind:
		"rat", "scarab":
			var sc_tint := Color(0.95, 0.72, 0.22) if kind == "scarab" else tint
			push_part("rat_body", base * Transform3D(Basis.from_euler(Vector3(sw * 0.08, 0, sw * 0.1)), Vector3.ZERO), sc_tint, flash)
			push_part("rat_tail", base * Transform3D(Basis.from_euler(Vector3(0, sw * 0.35, 0)), Vector3(0, 0.12, -0.22)), sc_tint, flash)
			_emit_eyes(fx_node, base, Vector3(0, 0.16, 0.24), 0.07, 0.14 * s, eye_col)

		"slime", "slimelet":
			var sq := 1.0 + sin(ph * 1.4) * 0.18
			var slime_xf := Transform3D(b_root.scaled(Vector3(s * sq, s / sq, s * sq)), pos)
			push_part("slime_body", slime_xf, tint, flash)
			_emit_eyes(fx_node, slime_xf, Vector3(0, 0.22, 0.28), 0.11, 0.16 * s, eye_col)

		"bat", "gargoyle":
			var flap := sin(ph * 2.2) * 0.82
			var hov := pos + Vector3(0, sin(ph * 1.1) * 0.18, 0)
			var b_xf := Transform3D(b_root.scaled(Vector3.ONE * s), hov)
			var bt := Color(0.62, 0.64, 0.72) if kind == "gargoyle" else tint
			push_part("bat_body", b_xf, bt, flash)
			push_part("bat_wing", b_xf * Transform3D(Basis(Vector3.FORWARD, flap), Vector3(0.08, 0.02, 0)), bt, flash)
			push_part("bat_wing", b_xf * Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.FORWARD, flap), Vector3(-0.08, 0.02, 0)), bt, flash)
			_emit_eyes(fx_node, b_xf, Vector3(0, 0.04, 0.16), 0.06, 0.14 * s, eye_col)

		"spider", "brood", "queen":
			var st := Color(0.58, 0.36, 0.68) if kind == "queen" else (Color(0.55, 0.48, 0.42) if kind == "brood" else tint)
			push_part("spider_body", base, st, flash)
			for i in 4:
				var zo := -0.18 + float(i) * 0.12
				var leg_sw := sin(ph + float(i) * 1.4) * 0.32
				push_part("spider_leg", base * Transform3D(Basis.from_euler(Vector3(0, -0.25 + float(i) * 0.18 + leg_sw, 0)), Vector3(0.14, 0.20, zo)), st, flash)
				push_part("spider_leg", base * Transform3D(Basis.from_euler(Vector3(0, PI + 0.25 - float(i) * 0.18 - leg_sw, 0)), Vector3(-0.14, 0.20, zo)), st, flash)
			_emit_eyes(fx_node, base, Vector3(0, 0.22, 0.30), 0.07, 0.18 * s, Color(1.0, 0.22, 0.14))

		"wolf":
			var wf := Transform3D(b_root.scaled(Vector3.ONE * s), pos + Vector3(0, absf(sw) * 0.10 * s, 0))
			push_part("wolf_body", wf, tint, flash)
			for sx in [-0.12, 0.12]:
				push_part("foot_limb", wf * Transform3D(Basis(Vector3.RIGHT, sw * 0.65), Vector3(sx, 0.28, 0.22)), tint, flash)
				push_part("foot_limb", wf * Transform3D(Basis(Vector3.RIGHT, -sw * 0.65), Vector3(sx, 0.28, -0.22)), tint, flash)
			_emit_eyes(fx_node, wf, Vector3(0, 0.45, 0.50), 0.07, 0.15 * s, Color(0.95, 0.78, 0.25))

		"wraith":
			var wr_p := pos + Vector3(0, 0.22 + sin(t * 3.0 + ph) * 0.14, 0)
			var w_xf := Transform3D(b_root.scaled(Vector3.ONE * s), wr_p)
			var phase_k := 0.55 if bool(u.get("phasing", false)) else 1.0
			push_part("wraith_body", w_xf, tint * Color(0.75, 0.95, 1.15) * phase_k, flash)
			_emit_eyes(fx_node, w_xf, Vector3(0, 1.02, 0.16), 0.06, 0.22 * s, Color(0.45, 0.92, 1.0))

		"wisp":
			var wp := pos + Vector3(0, sin(t * 4.2 + ph) * 0.24, 0)
			var w_xf := Transform3D(b_root.rotated(Vector3.UP, t * 2.5).scaled(Vector3.ONE * s), wp)
			push_part("wisp_body", w_xf, tint, flash)
			if fx_node != null:
				fx_node.push_add(wp.x, wp.y, wp.z, 1.3 * s, 1.3 * s, tint, 0.65, 2, ph)

		"toad":
			var hop := maxf(0.0, sin(ph)) * 0.42 * s
			var t_xf := Transform3D(b_root.scaled(Vector3.ONE * s), pos + Vector3(0, hop, 0))
			push_part("toad_body", t_xf, tint, flash)

		"ogre", "colossus":
			var is_col := (kind == "colossus")
			var tk := "golem_torso" if is_col else "ogre_torso"
			var hk := "golem_head" if is_col else "ogre_head"
			var lk := "golem_limb" if is_col else "ogre_limb"
			var ot := Color(1.35, 0.52, 0.30) if is_col else tint
			var arm_atk := -sin(atk * PI) * 1.45 if atk > 0.0 else sw * 0.45
			push_part(tk, base * Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0)), ot, flash)
			push_part(hk, base * Transform3D(Basis.IDENTITY, Vector3(0, 1.08, 0.08)), ot, flash)
			push_part(lk, base * Transform3D(Basis(Vector3.RIGHT, sw * 0.5), Vector3(-0.24, 0.52, 0)), ot, flash)
			push_part(lk, base * Transform3D(Basis(Vector3.RIGHT, -sw * 0.5), Vector3(0.24, 0.52, 0)), ot, flash)
			var r_arm := base * Transform3D(Basis(Vector3.RIGHT, arm_atk), Vector3(0.46, 0.94, 0))
			push_part(lk, r_arm, ot, flash)
			push_part(lk, base * Transform3D(Basis(Vector3.RIGHT, -sw * 0.45), Vector3(-0.46, 0.94, 0)), ot, flash)
			push_part("item_club", r_arm * Transform3D(Basis(Vector3.RIGHT, 1.25), Vector3(0, -0.46, 0.14)), ot, flash)
			_emit_eyes(fx_node, base, Vector3(0, 1.24, 0.28), 0.10, 0.28 * s, Color(1.0, 0.55, 0.12) if is_col else Color(1.0, 0.28, 0.15))

		"golem":
			push_part("golem_torso", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), tint, flash)
			push_part("golem_head", base * Transform3D(Basis.IDENTITY, Vector3(0, 1.02, 0.04)), tint, flash)
			push_part("golem_limb", base * Transform3D(Basis(Vector3.RIGHT, sw * 0.42), Vector3(-0.24, 0.50, 0)), tint, flash)
			push_part("golem_limb", base * Transform3D(Basis(Vector3.RIGHT, -sw * 0.42), Vector3(0.24, 0.50, 0)), tint, flash)
			push_part("golem_limb", base * Transform3D(Basis(Vector3.RIGHT, -sw * 0.35), Vector3(-0.44, 0.88, 0)), tint, flash)
			push_part("golem_limb", base * Transform3D(Basis(Vector3.RIGHT, sw * 0.35), Vector3(0.44, 0.88, 0)), tint, flash)
			_emit_eyes(fx_node, base, Vector3(0, 1.18, 0.22), 0.09, 0.24 * s, Color(1.0, 0.55, 0.16))

		_: # All Humanoid Skeletons, Guards, Brutes, Necros, Shamans, Drummers, Bombers, Mummies, Bosses, Footmen!
			_emit_humanoid(kind, base, s, sw, atk, tint, flash, eye_col, fx_node)


func _emit_humanoid(kind: String, base: Transform3D, s: float, sw: float, atk: float, tint: Color, flash: float, eye_col: Color, fx_node: Node) -> void:
	var armored := (kind == "footman" or kind == "guard" or kind == "brute" or kind == "archer" or kind == "tower_archer")
	var tk := "foot_torso" if armored else "skel_torso"
	var hk := "foot_head" if armored else "skel_head"
	var lk := "foot_limb" if armored else "skel_limb"

	var t_use := tint
	if kind == "mummy" or kind == "king":
		t_use = tint * Color(0.92, 0.86, 0.68)
	elif kind == "jotun":
		t_use = tint * Color(0.72, 0.94, 1.25)
	elif kind == "necro":
		t_use = tint * Color(0.78, 0.58, 0.95)
	elif kind == "shaman":
		t_use = tint * Color(0.68, 0.95, 0.68)

	var leg_a := sw * 0.58
	var arm_r_a := -sin(atk * PI) * 1.55 if atk > 0.0 else -sw * 0.45
	var arm_l_a := sw * 0.45
	if kind == "bomber":
		arm_r_a = -2.4
		arm_l_a = -2.4
	elif kind == "tower_archer":
		leg_a = 0.0
		arm_l_a = -1.45
		arm_r_a = -1.35 - atk * 0.35

	push_part(tk, base * Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0)), t_use, flash)
	push_part(hk, base * Transform3D(Basis.IDENTITY, Vector3(0, 0.72, 0)), t_use, flash)
	push_part(lk, base * Transform3D(Basis(Vector3.RIGHT, leg_a), Vector3(-0.10, 0.38, 0)), t_use, flash)
	push_part(lk, base * Transform3D(Basis(Vector3.RIGHT, -leg_a), Vector3(0.10, 0.38, 0)), t_use, flash)

	var r_arm := base * Transform3D(Basis(Vector3.RIGHT, arm_r_a), Vector3(0.21, 0.68, 0))
	var l_arm := base * Transform3D(Basis(Vector3.RIGHT, arm_l_a), Vector3(-0.21, 0.68, 0))
	push_part(lk, r_arm, t_use, flash)
	push_part(lk, l_arm, t_use, flash)

	# Class gear & silhouette landmarks
	if kind == "necro" or kind == "shaman":
		push_part("item_robe", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0)), t_use, flash)
		push_part("item_staff", r_arm * Transform3D(Basis.IDENTITY, Vector3(0, -0.28, 0.10)), t_use, flash)
	elif kind == "bomber":
		push_part("item_keg", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.96, 0.08)), Color.WHITE, flash)
		if fx_node != null:
			var fp := base * Vector3(0, 1.32, 0.08)
			fx_node.push_add(fp.x, fp.y, fp.z, 0.35 * s, 0.35 * s, Color(1.0, 0.65, 0.20), 1.3, 0, sw)
	elif kind == "drummer":
		push_part("item_drum", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.52, 0.24)), Color.WHITE, flash)
	elif kind == "archer" or kind == "tower_archer":
		push_part("item_bow", l_arm * Transform3D(Basis.IDENTITY, Vector3(0, -0.22, 0.14)), Color.WHITE, flash)
	elif kind == "brute" or kind == "giant" or kind == "jotun":
		push_part("item_club", r_arm * Transform3D(Basis(Vector3.RIGHT, 1.25), Vector3(0, -0.32, 0.08)), t_use, flash)
		if kind == "jotun" or kind == "giant":
			push_part("item_crown", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.94, 0)), t_use, flash)
	elif kind == "king":
		push_part("item_robe", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0)), Color(0.88, 0.72, 0.32), flash)
		push_part("item_crown", base * Transform3D(Basis.IDENTITY, Vector3(0, 0.94, 0)), Color.WHITE, flash)
		push_part("item_sword", r_arm * Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, -0.32, 0.08)), Color(1.1, 0.92, 0.45), flash)
	else:
		# Footman, Skeleton, Guard, Mummy
		push_part("item_sword", r_arm * Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, -0.30, 0.08)), Color.WHITE, flash)
		if kind == "footman" or kind == "guard":
			push_part("item_shield", l_arm * Transform3D(Basis.IDENTITY, Vector3(-0.08, -0.24, 0.12)), Color.WHITE, flash)

	if kind != "footman" and kind != "tower_archer":
		_emit_eyes(fx_node, base, Vector3(0, 0.84, 0.13), 0.055, 0.16 * s, eye_col)


func _emit_eyes(fx_node: Node, xf: Transform3D, local_center: Vector3, sep: float, sz: float, col: Color) -> void:
	if fx_node == null:
		return
	var el := xf * (local_center + Vector3(-sep, 0, 0))
	var er := xf * (local_center + Vector3(sep, 0, 0))
	fx_node.push_add(el.x, el.y, el.z, sz, sz, col, 1.4, 0)
	fx_node.push_add(er.x, er.y, er.z, sz, sz, col, 1.4, 0)


# ============================================================================
# Shatter Debris & Bouncing Coins
# ============================================================================

func spawn_shatter(pos: Vector3, kind: String, count: int, col: Color) -> void:
	var key := "debris_bone"
	if kind == "golem" or kind == "colossus" or kind == "gargoyle" or kind == "tower":
		key = "debris_rock"
	elif kind == "wood":
		key = "debris_plank"
	for _i in count:
		if debris.size() >= 220:
			debris.pop_front()
		var a := randf() * TAU
		var spd := 1.8 + randf() * 3.8
		debris.append({
			"key": key,
			"pos": pos + Vector3((randf() - 0.5) * 0.4, 0.35 + randf() * 0.45, (randf() - 0.5) * 0.4),
			"vel": Vector3(cos(a) * spd, 2.8 + randf() * 3.8, sin(a) * spd),
			"rot": Vector3(randf() * TAU, randf() * TAU, randf() * TAU),
			"vrot": Vector3((randf() - 0.5) * 11.0, (randf() - 0.5) * 11.0, (randf() - 0.5) * 11.0),
			"scale": 0.65 + randf() * 0.75,
			"col": col,
			"age": 0.0,
			"life": 1.4 + randf() * 1.1,
		})


func spawn_coins(pos: Vector3, n: int) -> void:
	for _i in mini(n, 8):
		if coins.size() >= 120:
			coins.pop_front()
		var a := randf() * TAU
		var spd := 1.2 + randf() * 2.2
		coins.append({
			"pos": pos + Vector3(0, 0.45, 0),
			"vel": Vector3(cos(a) * spd, 3.4 + randf() * 2.2, sin(a) * spd),
			"rot": randf() * TAU,
			"age": 0.0,
			"life": 1.15 + randf() * 0.35,
		})


func update_and_emit_pools(dt: float, t: float, height_fn: Callable, fx_node: Node) -> void:
	# Update & draw shatter debris
	var i := debris.size() - 1
	while i >= 0:
		var d: Dictionary = debris[i]
		d["age"] = float(d["age"]) + dt
		var u := float(d["age"]) / float(d["life"])
		if u >= 1.0:
			debris.remove_at(i)
		else:
			var vel: Vector3 = d["vel"]
			var p: Vector3 = d["pos"]
			vel.y -= 15.5 * dt
			p += vel * dt
			var gy := float(height_fn.call(p.x, p.z)) + 0.08 if height_fn.is_valid() else 0.08
			if p.y < gy:
				p.y = gy
				vel.y = absf(vel.y) * 0.34
				vel.x *= 0.65
				vel.z *= 0.65
				d["vrot"] = d["vrot"] * 0.55
			d["pos"] = p
			d["vel"] = vel
			d["rot"] = d["rot"] + d["vrot"] * dt
			var sc := float(d["scale"]) * (1.0 - U.smooth(0.65, 1.0, u))
			var xf := Transform3D(Basis.from_euler(d["rot"]).scaled(Vector3.ONE * sc), p)
			push_part(String(d["key"]), xf, d["col"], 0.0)
		i -= 1

	# Update & draw bouncing gold coins
	i = coins.size() - 1
	while i >= 0:
		var c: Dictionary = coins[i]
		c["age"] = float(c["age"]) + dt
		var u := float(c["age"]) / float(c["life"])
		if u >= 1.0:
			coins.remove_at(i)
		else:
			var vel: Vector3 = c["vel"]
			var p: Vector3 = c["pos"]
			vel.y -= 14.5 * dt
			p += vel * dt
			var gy := float(height_fn.call(p.x, p.z)) + 0.14 if height_fn.is_valid() else 0.14
			if p.y < gy:
				p.y = gy
				vel.y = absf(vel.y) * 0.45
				vel.x *= 0.72
				vel.z *= 0.72
			c["pos"] = p
			c["vel"] = vel
			c["rot"] = float(c["rot"]) + dt * 7.5
			var sc := 1.0 - U.smooth(0.75, 1.0, u)
			var xf := Transform3D(Basis(Vector3.UP, float(c["rot"])).scaled(Vector3.ONE * sc), p)
			push_part("coin", xf, Color.WHITE, 0.0)
			if fx_node != null and u < 0.25:
				fx_node.push_add(p.x, p.y, p.z, 0.45, 0.45, Color(1.0, 0.85, 0.35), (1.0 - u * 4.0) * 0.7, 5, float(c["rot"]), u * 4.0)
		i -= 1

	# Suppress unused warning for t
	var _t_used := t
