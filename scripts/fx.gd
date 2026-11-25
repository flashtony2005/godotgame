extends Node3D
## Complete FX Engine + Dynamic Light Pool (ported and enhanced from 40-fx.js & 10-gfx.js).
## Includes:
## - 2600-instance additive FX sprite batch (orbs, volumetric flames, halos, fireballs, rings, star bursts, spark streaks, slash arcs)
## - 700-instance fire-lit volumetric smoke & dust cloud batch
## - Dynamic billboarded 3D ribbon mesh for jagged branching lightning bolts & flaming arrow trails
## - 40 terrain-conforming 4x4 subdivided organic decals (scorch marks, slime goo, boss footprints)
## - Shadow-casting Moonlight + Fill + Beacon OmniLight + 3 dynamic SpotLights + 24 pooled OmniLights + 12-light mist/smoke/weather feeder

const U = preload("res://scripts/util.gd")

const ADD_CAP := 2600
const SMOKE_CAP := 700
const DECAL_CAP := 40
const MAX_LIGHTS := 12

# Sprite batches
var add_mm: MultiMeshInstance3D
var add_mat: ShaderMaterial
var smoke_mm: MultiMeshInstance3D
var smoke_mat: ShaderMaterial
var seg_mi: MeshInstance3D
var seg_mesh: ImmediateMesh
var seg_mat: ShaderMaterial
var decal_mat: ShaderMaterial
var decal_nodes: Array[MeshInstance3D] = []
var decal_age: PackedFloat32Array = PackedFloat32Array()
var decal_life: PackedFloat32Array = PackedFloat32Array()
var decal_col: Array[Color] = []
var decal_seed: PackedFloat32Array = PackedFloat32Array()
var decal_active: Array[bool] = []
var decal_next := 0

# Dynamic FX pools
var flames: Array[Dictionary] = []
var parts: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var timed_fx: Array[Dictionary] = []
var bolts: Array[Dictionary] = []

# Per-frame additive sprite cursor (also usable by external callers like eyes/arrows/wisps)
var _add_n := 0
var _smoke_n := 0
var _seg_list: Array = [] # [{a: Vector3, b: Vector3, w: float, col: Color, alpha: float}]

# Camera shake
var shake := 0.0
var shake_x := 0.0
var shake_y := 0.0

# Lighting rig
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var beacon_light: OmniLight3D
var tower_spots: Array[SpotLight3D] = []
var tower_lights: Array[OmniLight3D] = []
var flash_lights: Array[OmniLight3D] = []
var flash_slots: Array[Dictionary] = []
var torch_lights: Array[OmniLight3D] = []
var env_lights: Array[OmniLight3D] = []

# Mist/smoke/weather light arrays (size 12)
var mist_pos: PackedVector3Array = PackedVector3Array()
var mist_col: PackedVector3Array = PackedVector3Array()

# Active camera reference for billboarded ribbons
var cam_ref: Camera3D = null


func _ready() -> void:
	mist_pos.resize(MAX_LIGHTS)
	mist_col.resize(MAX_LIGHTS)
	for i in MAX_LIGHTS:
		mist_pos[i] = Vector3.ZERO
		mist_col[i] = Vector3.ZERO

	_setup_batches()
	_setup_decals()
	_setup_lights()


func _setup_batches() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)

	# Additive FX sprite MultiMesh
	add_mat = ShaderMaterial.new()
	add_mat.shader = load("res://shaders/fx_sprite.gdshader")
	var amm := MultiMesh.new()
	amm.transform_format = MultiMesh.TRANSFORM_3D
	amm.use_colors = true
	amm.use_custom_data = true
	amm.mesh = quad
	amm.instance_count = ADD_CAP
	amm.visible_instance_count = 0
	add_mm = MultiMeshInstance3D.new()
	add_mm.name = "fx_add_mm"
	add_mm.multimesh = amm
	add_mm.material_override = add_mat
	add_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_mm.extra_cull_margin = 200.0
	add_child(add_mm)

	# Lit smoke/dust MultiMesh
	smoke_mat = ShaderMaterial.new()
	smoke_mat.shader = load("res://shaders/fx_smoke.gdshader")
	smoke_mat.set_shader_parameter("u_light_pos", mist_pos)
	smoke_mat.set_shader_parameter("u_light_col", mist_col)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.use_colors = true
	smm.use_custom_data = true
	smm.mesh = quad
	smm.instance_count = SMOKE_CAP
	smm.visible_instance_count = 0
	smoke_mm = MultiMeshInstance3D.new()
	smoke_mm.name = "fx_smoke_mm"
	smoke_mm.multimesh = smm
	smoke_mm.material_override = smoke_mat
	smoke_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_mm.extra_cull_margin = 200.0
	add_child(smoke_mm)

	# Dynamic 3D ribbon segment mesh (lightning + arrow trails)
	seg_mat = ShaderMaterial.new()
	seg_mat.shader = load("res://shaders/fx_seg.gdshader")
	seg_mesh = ImmediateMesh.new()
	seg_mi = MeshInstance3D.new()
	seg_mi.name = "fx_seg_mi"
	seg_mi.mesh = seg_mesh
	seg_mi.material_override = seg_mat
	seg_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seg_mi.extra_cull_margin = 200.0
	add_child(seg_mi)


func _setup_decals() -> void:
	decal_mat = ShaderMaterial.new()
	decal_mat.shader = load("res://shaders/decal.gdshader")
	decal_age.resize(DECAL_CAP)
	decal_life.resize(DECAL_CAP)
	decal_seed.resize(DECAL_CAP)
	decal_col.resize(DECAL_CAP)
	decal_active.resize(DECAL_CAP)
	for i in DECAL_CAP:
		decal_age[i] = 0.0
		decal_life[i] = 1.0
		decal_seed[i] = 0.0
		decal_col[i] = Color(0.05, 0.04, 0.03, 0.0)
		decal_active[i] = false
		var mi := MeshInstance3D.new()
		mi.name = "decal_%d" % i
		mi.material_override = decal_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		decal_nodes.append(mi)


func _setup_lights() -> void:
	# Primary directional moonlight (shadow-casting)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "moon_light"
	sun_light.light_color = Color(0.55, 0.68, 0.92)
	sun_light.light_energy = 0.55
	sun_light.shadow_enabled = true
	sun_light.shadow_bias = 0.025
	sun_light.shadow_normal_bias = 1.4
	sun_light.shadow_blur = 1.8
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_max_distance = 110.0
	sun_light.position = Vector3(-28.0, 42.0, -24.0)
	add_child(sun_light)
	sun_light.look_at(Vector3.ZERO, Vector3.UP)

	# Secondary opposite rim/fill directional light
	fill_light = DirectionalLight3D.new()
	fill_light.name = "fill_light"
	fill_light.light_color = Color(0.32, 0.42, 0.62)
	fill_light.light_energy = 0.25
	fill_light.shadow_enabled = false
	fill_light.position = Vector3(30.0, 18.0, 26.0)
	add_child(fill_light)
	fill_light.look_at(Vector3.ZERO, Vector3.UP)

	# Shadow-casting Keep Beacon fire light
	beacon_light = OmniLight3D.new()
	beacon_light.name = "beacon_light"
	beacon_light.light_color = Color(1.0, 0.54, 0.16)
	beacon_light.light_energy = 8.0
	beacon_light.omni_range = 34.0
	beacon_light.omni_attenuation = 1.45
	beacon_light.shadow_enabled = true
	beacon_light.shadow_bias = 0.04
	beacon_light.shadow_normal_bias = 1.2
	beacon_light.shadow_blur = 2.0
	add_child(beacon_light)

	# 3 shadow-casting downward spotlights for nearest lit towers
	for i in 3:
		var sp := SpotLight3D.new()
		sp.name = "tower_spot_%d" % i
		sp.light_color = Color(1.0, 0.58, 0.20)
		sp.light_energy = 0.0
		sp.spot_range = 17.0
		sp.spot_attenuation = 1.4
		sp.spot_angle = 66.0
		sp.spot_angle_attenuation = 0.65
		sp.shadow_enabled = true
		sp.shadow_bias = 0.03
		sp.shadow_normal_bias = 1.2
		sp.shadow_blur = 1.8
		sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(sp)
		tower_spots.append(sp)

	# 12 pooled tower OmniLights
	for i in 12:
		var l := OmniLight3D.new()
		l.name = "tower_l_%d" % i
		l.light_energy = 0.0
		l.omni_range = 16.0
		l.omni_attenuation = 1.45
		add_child(l)
		tower_lights.append(l)

	# 4 pooled flash OmniLights (explosions, lightning, muzzle flashes, beacon ignite)
	for i in 4:
		var fl := OmniLight3D.new()
		fl.name = "flash_l_%d" % i
		fl.light_energy = 0.0
		fl.omni_range = 18.0
		fl.omni_attenuation = 1.35
		add_child(fl)
		flash_lights.append(fl)
		flash_slots.append({"x": 0.0, "y": 0.0, "z": 0.0, "col": Color.WHITE, "inten": 0.0, "life": 0.0, "max": 0.1, "range": 14.0})

	# 5 pooled torch / arrow / wisp OmniLights
	for i in 5:
		var tl := OmniLight3D.new()
		tl.name = "torch_l_%d" % i
		tl.light_energy = 0.0
		tl.omni_range = 11.0
		tl.omni_attenuation = 1.5
		add_child(tl)
		torch_lights.append(tl)

	# 3 pooled environment OmniLights (lava vents, glowing mushrooms)
	for i in 3:
		var el := OmniLight3D.new()
		el.name = "env_l_%d" % i
		el.light_energy = 0.0
		el.omni_range = 12.0
		el.omni_attenuation = 1.5
		add_child(el)
		env_lights.append(el)


# ============================================================================
# Public FX Spawners
# ============================================================================

func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func add_flash(x: float, y: float, z: float, col_hex: int, inten: float, dur: float, rad: float = 14.0) -> void:
	var best := 0
	var best_v := 1e9
	for i in flash_slots.size():
		var sl: Dictionary = flash_slots[i]
		var v: float = float(sl["life"]) * float(sl["inten"])
		if v < best_v:
			best_v = v
			best = i
	var s: Dictionary = flash_slots[best]
	s["x"] = x
	s["y"] = y
	s["z"] = z
	s["col"] = U.col_hex(col_hex)
	s["inten"] = inten
	s["life"] = dur
	s["max"] = maxf(0.01, dur)
	s["range"] = rad


func add_flame(x: float, y: float, z: float, scale: float, opts: Dictionary = {}) -> Dictionary:
	var f := {
		"x": x,
		"y": y,
		"z": z,
		"scale": scale,
		"tint": opts.get("tint", Color(1.0, 0.94, 0.80)),
		"smoke": float(opts.get("smoke", 0.55)),
		"ember": float(opts.get("ember", 0.4)),
		"halo": float(opts.get("halo", 0.35)),
		"seed": randf() * 100.0,
		"next_s": randf() * 0.4,
		"next_e": randf() * 0.5,
		"alive": true,
		"power": 1.0,
		"owner": opts.get("owner", null),
		"chunk_idx": int(opts.get("chunk_idx", -1)),
		"local_pos": Vector3.ZERO,
	}
	flames.append(f)
	return f


func remove_flame(f: Dictionary) -> void:
	f["alive"] = false
	var idx := flames.find(f)
	if idx >= 0:
		flames.remove_at(idx)


func fx_part(x: float, y: float, z: float, vx: float, vy: float, vz: float, life: float, size: float, col: Color, alpha: float = 1.0, grav: float = 0.0, type_id: int = 0, streak: float = 0.0) -> void:
	if parts.size() >= 1500:
		parts.pop_front()
	parts.append({
		"x": x, "y": y, "z": z,
		"vx": vx, "vy": vy, "vz": vz,
		"age": 0.0, "life": maxf(0.05, life),
		"size": size, "col": col, "alpha": alpha,
		"grav": grav, "type": type_id, "streak": streak,
		"seed": randf() * 100.0,
	})


func fx_smoke(x: float, y: float, z: float, vx: float, vy: float, vz: float, life: float, s0: float, s1: float, col: Color, alpha: float = 0.4) -> void:
	if smokes.size() >= 550:
		smokes.pop_front()
	smokes.append({
		"x": x, "y": y, "z": z,
		"vx": vx, "vy": vy, "vz": vz,
		"age": 0.0, "life": maxf(0.1, life),
		"s0": s0, "s1": s1, "col": col, "alpha": alpha,
		"seed": randf() * 100.0,
		"rot": randf() * TAU,
		"vrot": (randf() - 0.5) * 0.85,
	})


func fx_sparks(x: float, y: float, z: float, n: int, speed: float, col_hex: int = 0xffb858, up: float = 1.0) -> void:
	var c := U.col_hex(col_hex)
	for _i in n:
		var a := randf() * TAU
		var s := speed * (0.4 + randf() * 0.8)
		fx_part(
			x, y, z,
			cos(a) * s, (0.45 + randf() * 0.95) * speed * up, sin(a) * s,
			0.25 + randf() * 0.45,
			0.14 + randf() * 0.16,
			c, 1.35, -12.0, 6, 1.0
		)


func fx_embers(x: float, y: float, z: float, n: int, spread: float = 0.4, up: float = 2.0, col_hex: int = 0xff7020) -> void:
	var c := U.col_hex(col_hex)
	for _i in n:
		var a := randf() * TAU
		var r := randf() * spread
		fx_part(
			x + cos(a) * r, y, z + sin(a) * r,
			(randf() - 0.5) * 1.1, up * (0.55 + randf() * 0.85), (randf() - 0.5) * 1.1,
			0.9 + randf() * 1.35,
			0.11 + randf() * 0.13,
			c, 1.25, 0.35, 0, 0.0
		)


func fx_dust(x: float, y: float, z: float, n: int = 6, spread: float = 0.6, col_hex: int = 0x7a6a58) -> void:
	var c := U.col_hex(col_hex)
	for _i in n:
		var a := randf() * TAU
		var r := randf() * spread
		fx_smoke(
			x + cos(a) * r, y + 0.12, z + sin(a) * r,
			cos(a) * (0.6 + randf() * 0.9), 0.7 + randf() * 1.0, sin(a) * (0.6 + randf() * 0.9),
			0.75 + randf() * 0.75,
			0.45, 1.85 + randf() * 0.9,
			c, 0.46
		)


func fx_timed(type_id: int, x: float, y: float, z: float, s0: float, s1: float, life: float, col_hex: int, alpha: float = 1.0, opts: Dictionary = {}) -> void:
	timed_fx.append({
		"type": type_id,
		"x": x, "y": y, "z": z,
		"s0": s0, "s1": s1,
		"age": 0.0, "life": maxf(0.05, life),
		"col": U.col_hex(col_hex),
		"alpha": alpha,
		"rot": float(opts.get("rot", randf() * TAU)),
		"seed": randf() * 100.0,
		"ground": bool(opts.get("ground", false)),
		"vy": float(opts.get("vy", 0.0)),
	})


func fx_explosion(x: float, y: float, z: float, radius: float = 2.0, col_hex: int = 0xff7024, height_fn: Callable = Callable()) -> void:
	# Multi-puff expanding fireball
	for i in 5:
		var a := randf() * TAU
		var d := (0.0 if i == 0 else randf() * radius * 0.42)
		fx_timed(
			3,
			x + cos(a) * d, y + 0.28 + randf() * 0.35, z + sin(a) * d,
			radius * 0.45, radius * (1.25 + randf() * 0.55),
			0.42 + randf() * 0.25,
			col_hex, 1.35, {"vy": 0.75 + randf() * 0.75}
		)
	# Core flash star burst + ground shockwave ring
	fx_timed(5, x, y + 0.4, z, radius * 0.7, radius * 2.1, 0.22, 0xffe4a0, 1.5)
	fx_timed(4, x, y + 0.08, z, radius * 0.4, radius * 2.5, 0.48, 0xffaa48, 0.95, {"ground": true})

	# Rising fire-lit smoke plume
	var sm_c := U.col_hex(0x3a322e)
	for _i in 7:
		var a := randf() * TAU
		var d := randf() * radius * 0.5
		fx_smoke(
			x + cos(a) * d, y + 0.3, z + sin(a) * d,
			cos(a) * 0.7, 1.3 + randf() * 1.4, sin(a) * 0.7,
			1.25 + randf() * 0.95,
			radius * 0.42, radius * 1.65,
			sm_c, 0.6
		)

	fx_sparks(x, y + 0.35, z, int(10.0 + radius * 4.5), 4.6 + radius * 1.1, 0xffc060, 1.35)
	fx_embers(x, y + 0.25, z, 10, radius * 0.5, 2.7, 0xff6018)
	add_flash(x, y + 1.1, z, 0xff8030, 8.5 + radius * 2.4, 0.42, 13.0 + radius * 3.0)
	add_decal(x, z, radius * 0.88, 0x0b0806, 0.68, 22.0, height_fn)
	add_shake(minf(0.58, 0.14 + radius * 0.10))


func fx_bolt(ax: float, ay: float, az: float, bx: float, by: float, bz: float, col_hex: int = 0x9ce4ff, width: float = 0.22, life: float = 0.24) -> void:
	var segs: Array = []
	var steps := 10
	var pts: Array[Vector3] = []
	var dx := bx - ax
	var dy := by - ay
	var dz := bz - az
	var dist := sqrt(dx * dx + dy * dy + dz * dz)
	var amp := minf(0.95, dist * 0.14)
	for i in steps + 1:
		var f := float(i) / float(steps)
		var env := sin(f * PI)
		var jx := (randf() - 0.5) * 2.0 * amp * env
		var jy := (randf() - 0.5) * 1.5 * amp * env
		var jz := (randf() - 0.5) * 2.0 * amp * env
		pts.append(Vector3(ax + dx * f + jx, ay + dy * f + jy, az + dz * f + jz))
	for i in steps:
		segs.append([pts[i], pts[i + 1], width])
		# Forked lightning sub-branches
		if i > 1 and i < steps - 1 and randf() < 0.42:
			var bp0 := pts[i]
			var bp1 := bp0 + Vector3((randf() - 0.5) * 1.5, (randf() - 0.5) * 1.1, (randf() - 0.5) * 1.5)
			segs.append([bp0, bp1, width * 0.48])
	bolts.append({
		"segs": segs,
		"col": U.col_hex(col_hex),
		"age": 0.0,
		"life": maxf(0.06, life),
	})
	add_flash(bx, by + 0.5, bz, col_hex, 6.5, 0.18, 12.0)


func add_decal(x: float, z: float, rad: float, col_hex: int, alpha: float = 0.65, life: float = 20.0, height_fn: Callable = Callable()) -> void:
	var idx := decal_next % DECAL_CAP
	decal_next += 1
	var col := U.col_hex(col_hex)
	col.a = alpha
	var seed_v := randf() * 100.0
	decal_age[idx] = 0.0
	decal_life[idx] = maxf(1.0, life)
	decal_col[idx] = col
	decal_seed[idx] = seed_v
	decal_active[idx] = true

	# Build a 4x4 terrain-conforming grid mesh
	var G := 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)

	var grid_p: Array[Vector3] = []
	var grid_uv: Array[Vector2] = []
	for j in G + 1:
		for i in G + 1:
			var ux := -1.0 + 2.0 * float(i) / float(G)
			var uz := -1.0 + 2.0 * float(j) / float(G)
			var wx := x + ux * rad
			var wz := z + uz * rad
			var wy := 0.06
			if height_fn.is_valid():
				wy = float(height_fn.call(wx, wz)) + 0.06
			grid_p.append(Vector3(wx, wy, wz))
			grid_uv.append(Vector2(ux, uz))

	var cust := Color(seed_v, 0.0, 0.0, 0.0)
	for j in G:
		for i in G:
			var a := j * (G + 1) + i
			var b := a + 1
			var c := a + G + 2
			var d := a + G + 1
			for k in [a, b, c, a, c, d]:
				st.set_color(col)
				st.set_uv(grid_uv[k])
				st.set_custom(0, cust)
				st.add_vertex(grid_p[k])

	var mi := decal_nodes[idx]
	mi.mesh = st.commit()
	mi.visible = true
	mi.transparency = 0.0


func clear_fx() -> void:
	flames.clear()
	parts.clear()
	smokes.clear()
	timed_fx.clear()
	bolts.clear()
	_seg_list.clear()
	for i in DECAL_CAP:
		decal_active[i] = false
		decal_nodes[i].visible = false
	for sl in flash_slots:
		sl["life"] = 0.0
	for l in tower_lights:
		l.light_energy = 0.0
	for sp in tower_spots:
		sp.light_energy = 0.0
	for tl in torch_lights:
		tl.light_energy = 0.0
	for el in env_lights:
		el.light_energy = 0.0
	for fl in flash_lights:
		fl.light_energy = 0.0
	shake = 0.0
	shake_x = 0.0
	shake_y = 0.0


# ============================================================================
# Frame Push Helpers (called between begin_frame and end_frame)
# ============================================================================

func begin_frame(t: float) -> void:
	_add_n = 0
	_smoke_n = 0
	_seg_list.clear()
	add_mat.set_shader_parameter("u_time", t)
	smoke_mat.set_shader_parameter("u_time", t)


func push_add(x: float, y: float, z: float, w: float, h: float, col: Color, alpha: float, type_id: int, seed_v: float = 0.0, age: float = 0.0, rot: float = 0.0, anchor: float = 0.0, ground: bool = false) -> void:
	if _add_n >= ADD_CAP:
		return
	var mm := add_mm.multimesh
	var xform := Transform3D(
		Basis(Vector3(w, 0.0, 0.0), Vector3(0.0, h, 0.0), Vector3(rot, anchor, 1.0)),
		Vector3(x, y, z)
	)
	mm.set_instance_transform(_add_n, xform)
	mm.set_instance_color(_add_n, Color(col.r, col.g, col.b, alpha))
	mm.set_instance_custom_data(_add_n, Color(float(type_id), seed_v, age, 1.0 if ground else 0.0))
	_add_n += 1


func push_smoke(x: float, y: float, z: float, w: float, h: float, col: Color, alpha: float, seed_v: float, age: float, rot: float) -> void:
	if _smoke_n >= SMOKE_CAP:
		return
	var mm := smoke_mm.multimesh
	var xform := Transform3D(
		Basis(Vector3(w, 0.0, 0.0), Vector3(0.0, h, 0.0), Vector3(rot, 0.0, 1.0)),
		Vector3(x, y, z)
	)
	mm.set_instance_transform(_smoke_n, xform)
	mm.set_instance_color(_smoke_n, Color(col.r, col.g, col.b, alpha))
	mm.set_instance_custom_data(_smoke_n, Color(0.0, seed_v, age, 0.0))
	_smoke_n += 1


func push_seg(a: Vector3, b: Vector3, width: float, col: Color, alpha: float) -> void:
	if _seg_list.size() >= 600:
		return
	_seg_list.append([a, b, width, col, alpha])


# ============================================================================
# Simulation & Commit
# ============================================================================

func update_fx(dt: float, t: float, wind_v: Vector3 = Vector3(0.45, 0.0, 0.2)) -> void:
	# Camera shake decay
	if shake > 0.001:
		shake = maxf(0.0, shake - dt * 1.45)
		var amp := shake * shake * 0.72
		shake_x = sin(t * 47.0) * amp
		shake_y = cos(t * 53.0) * amp * 0.78
	else:
		shake = 0.0
		shake_x = 0.0
		shake_y = 0.0

	# Flames (2 overlapping animated tongues + warm glow halo + smoke + embers)
	for f in flames:
		var pw: float = float(f["power"])
		if pw <= 0.01:
			continue
		var s: float = float(f["scale"]) * pw
		var sd: float = float(f["seed"])
		var fx: float = float(f["x"])
		var fy: float = float(f["y"])
		var fz: float = float(f["z"])
		var tint: Color = f["tint"]
		var flk := 0.88 + 0.14 * sin(t * 14.0 + sd) + 0.08 * sin(t * 23.0 + sd * 2.1)
		push_add(fx, fy - 0.04 * s, fz, s * 1.12 * flk, s * 1.72 * flk, tint, 1.15, 1, sd, 0.0, 0.0, 0.92, false)
		push_add(fx, fy - 0.02 * s, fz, s * 0.84 * flk, s * 1.38 * flk, tint, 0.85, 1, sd + 19.3, 0.0, 0.0, 0.88, false)
		var halo: float = float(f["halo"])
		if halo > 0.01:
			var hc := Color(tint.r * 1.0, tint.g * 0.56, tint.b * 0.20)
			push_add(fx, fy + s * 0.42, fz, s * 3.3 * flk, s * 3.3 * flk, hc, halo * pw * 0.85, 2, sd, 0.0, 0.0, 0.0, false)

		if float(f["smoke"]) > 0.0:
			f["next_s"] = float(f["next_s"]) - dt
			if float(f["next_s"]) <= 0.0:
				f["next_s"] = (0.16 + randf() * 0.22) / maxf(0.25, float(f["smoke"]))
				var sm_c := U.col_hex(0x302b28)
				fx_smoke(
					fx + (randf() - 0.5) * s * 0.42,
					fy + s * 0.72,
					fz + (randf() - 0.5) * s * 0.42,
					wind_v.x * 0.45 + (randf() - 0.5) * 0.32,
					0.95 + randf() * 0.65,
					wind_v.z * 0.45 + (randf() - 0.5) * 0.32,
					1.3 + randf() * 1.0,
					s * 0.58, s * 2.1,
					sm_c, 0.28 * pw
				)

		if float(f["ember"]) > 0.0:
			f["next_e"] = float(f["next_e"]) - dt
			if float(f["next_e"]) <= 0.0:
				f["next_e"] = (0.24 + randf() * 0.42) / maxf(0.25, float(f["ember"]))
				var ec := Color(tint.r, tint.g * 0.58, tint.b * 0.16)
				fx_part(
					fx + (randf() - 0.5) * s * 0.45,
					fy + s * 0.52,
					fz + (randf() - 0.5) * s * 0.45,
					wind_v.x * 0.55 + (randf() - 0.5) * 0.85,
					1.45 + randf() * 1.45,
					wind_v.z * 0.55 + (randf() - 0.5) * 0.85,
					0.85 + randf() * 1.15,
					0.09 + randf() * 0.08 * s,
					ec, 1.35, 0.25, 0, 0.0
				)

	# Timed FX (fireballs, shockwaves, bursts, slashes)
	var i := timed_fx.size() - 1
	while i >= 0:
		var e: Dictionary = timed_fx[i]
		e["age"] = float(e["age"]) + dt
		var u := float(e["age"]) / float(e["life"])
		if u >= 1.0:
			timed_fx.remove_at(i)
		else:
			e["y"] = float(e["y"]) + float(e["vy"]) * dt
			var sz := lerpf(float(e["s0"]), float(e["s1"]), U.ease_out(u))
			var al := float(e["alpha"]) * (1.0 - u * 0.35)
			push_add(float(e["x"]), float(e["y"]), float(e["z"]), sz, sz, e["col"], al, int(e["type"]), float(e["seed"]), u, float(e["rot"]), 0.0, bool(e["ground"]))
		i -= 1

	# Particles (sparks, embers, orbs)
	var cam_right := Vector3.RIGHT
	var cam_up := Vector3.UP
	if cam_ref != null:
		cam_right = cam_ref.global_basis.x
		cam_up = cam_ref.global_basis.y
	i = parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p["age"] = float(p["age"]) + dt
		var u := float(p["age"]) / float(p["life"])
		if u >= 1.0:
			parts.remove_at(i)
		else:
			var vy: float = float(p["vy"]) + float(p["grav"]) * dt
			p["vy"] = vy
			var vx: float = float(p["vx"])
			var vz: float = float(p["vz"])
			p["x"] = float(p["x"]) + vx * dt
			p["y"] = float(p["y"]) + vy * dt
			p["z"] = float(p["z"]) + vz * dt
			var fade := 1.0 - u * u
			var sz: float = float(p["size"]) * (1.0 - 0.35 * u)
			if float(p["streak"]) > 0.5:
				var vel := Vector3(vx, vy, vz)
				var sx := vel.dot(cam_right)
				var sy := vel.dot(cam_up)
				var rot := atan2(sy, sx)
				var spd := sqrt(sx * sx + sy * sy)
				push_add(float(p["x"]), float(p["y"]), float(p["z"]), maxf(sz, sz * (1.2 + spd * 0.16)), sz * 0.42, p["col"], float(p["alpha"]) * fade, 6, float(p["seed"]), u, rot, 0.0, false)
			else:
				push_add(float(p["x"]), float(p["y"]), float(p["z"]), sz, sz, p["col"], float(p["alpha"]) * fade, int(p["type"]), float(p["seed"]), u, 0.0, 0.0, false)
		i -= 1

	# Smokes & dust clouds
	i = smokes.size() - 1
	while i >= 0:
		var sm: Dictionary = smokes[i]
		sm["age"] = float(sm["age"]) + dt
		var u := float(sm["age"]) / float(sm["life"])
		if u >= 1.0:
			smokes.remove_at(i)
		else:
			sm["vx"] = float(sm["vx"]) * (1.0 - dt * 0.45)
			sm["vz"] = float(sm["vz"]) * (1.0 - dt * 0.45)
			sm["x"] = float(sm["x"]) + float(sm["vx"]) * dt
			sm["y"] = float(sm["y"]) + float(sm["vy"]) * dt
			sm["z"] = float(sm["z"]) + float(sm["vz"]) * dt
			sm["rot"] = float(sm["rot"]) + float(sm["vrot"]) * dt
			var sz := lerpf(float(sm["s0"]), float(sm["s1"]), sqrt(u))
			var al := float(sm["alpha"]) * U.smooth(0.0, 0.16, u) * (1.0 - U.smooth(0.45, 1.0, u))
			push_smoke(float(sm["x"]), float(sm["y"]), float(sm["z"]), sz, sz, sm["col"], al, float(sm["seed"]), u, float(sm["rot"]))
		i -= 1

	# Lightning bolts
	i = bolts.size() - 1
	while i >= 0:
		var b: Dictionary = bolts[i]
		b["age"] = float(b["age"]) + dt
		var u := float(b["age"]) / float(b["life"])
		if u >= 1.0:
			bolts.remove_at(i)
		else:
			var al := (1.0 - u) * (0.72 + 0.28 * sin(u * 38.0))
			for seg in b["segs"]:
				push_seg(seg[0], seg[1], float(seg[2]) * (1.0 - 0.35 * u), b["col"], al * 1.45)
		i -= 1

	# Decals fade-out
	for d_i in DECAL_CAP:
		if not decal_active[d_i]:
			continue
		decal_age[d_i] += dt
		var u := decal_age[d_i] / decal_life[d_i]
		if u >= 1.0:
			decal_active[d_i] = false
			decal_nodes[d_i].visible = false
		elif u > 0.72:
			decal_nodes[d_i].transparency = U.smooth(0.72, 1.0, u)

	# Decay flashes
	for idx in flash_slots.size():
		var sl: Dictionary = flash_slots[idx]
		var fl := flash_lights[idx]
		if float(sl["life"]) > 0.0:
			sl["life"] = maxf(0.0, float(sl["life"]) - dt)
			var u := float(sl["life"]) / float(sl["max"])
			fl.position = Vector3(float(sl["x"]), float(sl["y"]), float(sl["z"]))
			fl.light_color = sl["col"]
			fl.omni_range = float(sl["range"])
			fl.light_energy = float(sl["inten"]) * u * u
		else:
			fl.light_energy = 0.0


func end_frame() -> void:
	add_mm.multimesh.visible_instance_count = _add_n
	smoke_mm.multimesh.visible_instance_count = _smoke_n

	# Rebuild billboarded ribbon segments
	seg_mesh.clear_surfaces()
	if _seg_list.size() > 0 and cam_ref != null:
		var cam_pos := cam_ref.global_position
		seg_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in _seg_list:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var hw: float = float(seg[2]) * 0.5
			var col: Color = seg[3]
			var al: float = float(seg[4])
			var c_rgba := Color(col.r, col.g, col.b, al)
			var dir := b - a
			if dir.length_squared() < 1e-6:
				continue
			var mid := (a + b) * 0.5
			var to_cam := (cam_pos - mid).normalized()
			var side := dir.normalized().cross(to_cam)
			if side.length_squared() < 1e-5:
				side = Vector3.UP
			else:
				side = side.normalized()
			var off := side * hw
			var v0 := a - off
			var v1 := a + off
			var v2 := b + off
			var v3 := b - off
			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(0.0, 0.0))
			seg_mesh.surface_add_vertex(v0)
			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(0.0, 1.0))
			seg_mesh.surface_add_vertex(v1)
			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(1.0, 1.0))
			seg_mesh.surface_add_vertex(v2)

			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(0.0, 0.0))
			seg_mesh.surface_add_vertex(v0)
			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(1.0, 1.0))
			seg_mesh.surface_add_vertex(v2)
			seg_mesh.surface_set_color(c_rgba)
			seg_mesh.surface_set_uv(Vector2(1.0, 0.0))
			seg_mesh.surface_add_vertex(v3)
		seg_mesh.surface_end()


func update_lights_and_mist(
	t: float,
	beacon_pos: Vector3,
	beacon_power: float,
	beacon_col: Color,
	towers_data: Array,
	torches_data: Array,
	env_sources: Array,
	cam_target: Vector3,
	mist_mat: ShaderMaterial,
	weather_node: Node,
	amb_smoke: Color
) -> void:
	# Beacon light with organic fire flicker
	var flk := 0.86 + 0.14 * sin(t * 11.7) + 0.08 * sin(t * 19.3) + 0.05 * sin(t * 31.1)
	beacon_light.position = beacon_pos
	beacon_light.light_color = beacon_col
	beacon_light.light_energy = maxf(0.0, beacon_power * 7.8 * flk)
	beacon_light.omni_range = 24.0 + 14.0 * clampf(beacon_power, 0.0, 1.5)

	# Sort active tower light emitters by proximity to camera target for the 3 shadow-casting spotlights
	var sorted_t := towers_data.duplicate()
	sorted_t.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		return pa.distance_squared_to(cam_target) < pb.distance_squared_to(cam_target)
	)

	for i in tower_spots.size():
		var sp := tower_spots[i]
		if i < sorted_t.size():
			var td: Dictionary = sorted_t[i]
			var p: Vector3 = td["pos"]
			sp.position = Vector3(p.x, p.y + 3.4, p.z)
			sp.light_color = td["col"]
			sp.light_energy = float(td["inten"]) * 1.15
		else:
			sp.light_energy = 0.0

	for i in tower_lights.size():
		var l := tower_lights[i]
		if i < sorted_t.size():
			var td: Dictionary = sorted_t[i]
			l.position = td["pos"]
			l.light_color = td["col"]
			l.light_energy = float(td["inten"])
			l.omni_range = float(td.get("range", 15.0))
		else:
			l.light_energy = 0.0

	for i in torch_lights.size():
		var tl := torch_lights[i]
		if i < torches_data.size():
			var td: Dictionary = torches_data[i]
			tl.position = td["pos"]
			tl.light_color = td["col"]
			tl.light_energy = float(td["inten"])
			tl.omni_range = float(td.get("range", 10.0))
		else:
			tl.light_energy = 0.0

	for i in env_lights.size():
		var el := env_lights[i]
		if i < env_sources.size():
			var ed: Dictionary = env_sources[i]
			var ef := 0.85 + 0.15 * sin(t * 7.2 + float(i) * 2.1)
			el.position = ed["pos"]
			el.light_color = ed["col"]
			el.light_energy = float(ed["inten"]) * ef
			el.omni_range = float(ed.get("range", 11.0))
		else:
			el.light_energy = 0.0

	# Collect top 12 dynamic lights for mist, volumetric smoke, and weather particles
	var n := 0
	if beacon_light.light_energy > 0.05:
		mist_pos[n] = beacon_light.position
		var bc := beacon_light.light_color
		var bi := beacon_light.light_energy * 2.2
		mist_col[n] = Vector3(bc.r * bi, bc.g * bi, bc.b * bi)
		n += 1

	for fl in flash_lights:
		if n >= MAX_LIGHTS:
			break
		if fl.light_energy > 0.1:
			mist_pos[n] = fl.position
			var fc := fl.light_color
			var fi := fl.light_energy * 2.4
			mist_col[n] = Vector3(fc.r * fi, fc.g * fi, fc.b * fi)
			n += 1

	for td in sorted_t:
		if n >= MAX_LIGHTS:
			break
		var ti := float(td["inten"])
		if ti > 0.05:
			mist_pos[n] = td["pos"]
			var tc: Color = td["col"]
			mist_col[n] = Vector3(tc.r * ti * 1.9, tc.g * ti * 1.9, tc.b * ti * 1.9)
			n += 1

	for ed in env_sources:
		if n >= MAX_LIGHTS:
			break
		var ei := float(ed["inten"])
		if ei > 0.05:
			mist_pos[n] = ed["pos"]
			var ec: Color = ed["col"]
			mist_col[n] = Vector3(ec.r * ei * 1.8, ec.g * ei * 1.8, ec.b * ei * 1.8)
			n += 1

	while n < MAX_LIGHTS:
		mist_pos[n] = Vector3.ZERO
		mist_col[n] = Vector3.ZERO
		n += 1

	smoke_mat.set_shader_parameter("u_amb", Vector3(amb_smoke.r, amb_smoke.g, amb_smoke.b))
	smoke_mat.set_shader_parameter("u_light_pos", mist_pos)
	smoke_mat.set_shader_parameter("u_light_col", mist_col)
	if mist_mat != null:
		mist_mat.set_shader_parameter("u_light_pos", mist_pos)
		mist_mat.set_shader_parameter("u_light_col", mist_col)
	if weather_node != null and weather_node.has_method("set_lights"):
		weather_node.set_lights(mist_pos, mist_col)
