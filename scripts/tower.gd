extends Node3D
## Complete 4x3 Tower System with Scaffolding Build/Upgrade Animations, Recoiling Bombard,
## Levitating Storm Spire Crystal + Rune Ring, Archer Parapet Sentries, Guard Barracks, and Frost Freeze.
## Ported & enhanced from 60-towers.js.

const U = preload("res://scripts/util.gd")
const TX = preload("res://scripts/textures.gd")
const Soup = preload("res://scripts/soup.gd")
const Defs = preload("res://scripts/defs.gd")

var pad_idx := -1
var kind := "archer"
var level := 0 # 0, 1, 2
var stats: Dictionary = {}
var total_cost := 0

# Build / upgrade scaffolding animation state
var building := true
var build_t := 0.0
var build_dur := 1.05
var _pieces_data: Array = [] # [{mi: MeshInstance3D, start: float, dur: float, drop: float, landed: bool}]
var _scaffold_mi: MeshInstance3D = null
var _static_mi: MeshInstance3D = null
var _static_soup: Soup = null

# Active animated sub-parts
var turret_node: Node3D = null # Bombard yaw carriage
var barrel_node: Node3D = null # Bombard pitch & recoil barrel
var crystal_node: Node3D = null # Spire levitating crystal + orbiting shards
var ring_node: Node3D = null # Spire counter-rotating rune ring
var freeze_mi: MeshInstance3D = null # Frost Jotun stun ice shell

# Combat & visual state
var cd := 0.0
var charge_t := 0.0
var recoil := 0.0
var aim_yaw := 0.0
var stun := 0.0
var hit_flash := 0.0
var mounts: Dictionary = {} # {flames: Array[Vector3], archers: Array[Vector3], fire_pos: Vector3, rally: Vector3}
var flame_handles: Array[Dictionary] = []
var archer_anim: Array[Dictionary] = [] # [{yaw: float, draw: float, fire_cd: float}]
var footmen_ids: Array = [] # references to guard footmen managed by game.gd

var _rng: U.Rng


func setup(p_pad_idx: int, p_kind: String, p_pos: Vector3, p_seed: int, fx_node: Node, audio_node: Node) -> void:
	pad_idx = p_pad_idx
	kind = p_kind
	level = 0
	position = p_pos
	_rng = U.make_rng(p_seed)
	stats = Defs.tw(kind, level)
	total_cost = int(stats["cost"])
	_start_construction(fx_node, audio_node)


func upgrade(fx_node: Node, audio_node: Node) -> bool:
	if level >= 2 or building:
		return false
	level += 1
	stats = Defs.tw(kind, level)
	total_cost += int(stats["cost"])
	_clear_flames(fx_node)
	_start_construction(fx_node, audio_node)
	return true


func get_sell_value() -> int:
	return int(round(float(total_cost) * 0.72))


func get_next_stats() -> Dictionary:
	if level >= 2:
		return {}
	return Defs.tw(kind, level + 1)


func clear_visuals(fx_node: Node) -> void:
	_clear_flames(fx_node)
	for ch in get_children():
		ch.queue_free()
	_pieces_data.clear()
	_scaffold_mi = null
	_static_mi = null
	turret_node = null
	barrel_node = null
	crystal_node = null
	ring_node = null
	freeze_mi = null


func _clear_flames(fx_node: Node) -> void:
	if fx_node != null:
		for fh in flame_handles:
			fx_node.remove_flame(fh)
	flame_handles.clear()


func _start_construction(fx_node: Node, audio_node: Node) -> void:
	clear_visuals(fx_node)
	building = true
	build_t = 0.0
	build_dur = 0.92 + float(level) * 0.14

	var bp := _build_blueprint(kind, level, _rng)
	mounts = bp["mounts"]
	_static_soup = Soup.new()

	var piece_soups: Array = bp["pieces"]
	var n := piece_soups.size()
	for i in n:
		var sp: Soup = piece_soups[i]
		_static_soup.merge(sp)
		var mi := sp.instance(self, "bp_%d" % i, TX.mat_world)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visible = false
		var t_start := (float(i) / float(maxi(1, n))) * (build_dur * 0.68)
		_pieces_data.append({
			"mi": mi,
			"start": t_start,
			"dur": 0.24,
			"drop": 2.4 + float(i) * 0.35,
			"landed": false,
		})

	# Build wooden scaffolding cage around the tower
	var sc_sp := _build_scaffold(float(mounts.get("height", 3.2)))
	_scaffold_mi = sc_sp.instance(self, "scaffold", TX.mat_world)
	_scaffold_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_scaffold_mi.scale = Vector3(1.0, 0.01, 1.0)

	# Build animated sub-parts (hidden until build finishes)
	_build_dynamic_parts(bp)

	# Build Frost Jotun stun ice shell (hidden unless stun > 0)
	var ice_sp := Soup.new()
	var C := Soup.COL()
	var th := float(mounts.get("height", 3.2))
	ice_sp.cyl(1.15, th * 0.85, 0, th * 0.42, 0, C["ice"], {"n": 6, "rt": 0.72, "l": TX.L_PLAIN, "rough": 0.18, "emis": 0.45})
	freeze_mi = ice_sp.instance(self, "freeze_shell", TX.mat_world)
	freeze_mi.visible = false
	freeze_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Prepare archer sentry animation states
	archer_anim.clear()
	for _ap in mounts.get("archers", []):
		archer_anim.append({"yaw": 0.0, "draw": 0.0, "fire_cd": 0.0})

	if fx_node != null:
		fx_node.fx_dust(global_position.x, global_position.y, global_position.z, 7, 1.0, 0x8a7860)
	if audio_node != null:
		audio_node.play_sfx("hammer", 0.0, 0.85)


func _build_dynamic_parts(bp: Dictionary) -> void:
	if kind == "bombard" and bp.has("turret_soup"):
		turret_node = Node3D.new()
		turret_node.name = "bombard_turret"
		turret_node.position = mounts["turret_pivot"]
		turret_node.visible = false
		add_child(turret_node)
		var tmi: MeshInstance3D = bp["turret_soup"].instance(turret_node, "carriage", TX.mat_world)
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		barrel_node = Node3D.new()
		barrel_node.name = "bombard_barrel"
		barrel_node.position = Vector3(0.0, 0.24, 0.0)
		turret_node.add_child(barrel_node)
		var bmi: MeshInstance3D = bp["barrel_soup"].instance(barrel_node, "barrel", TX.mat_world)
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	elif kind == "spire" and bp.has("crystal_soup"):
		crystal_node = Node3D.new()
		crystal_node.name = "spire_crystal"
		crystal_node.position = mounts["crystal_pivot"]
		crystal_node.visible = false
		add_child(crystal_node)
		var cmi: MeshInstance3D = bp["crystal_soup"].instance(crystal_node, "crystal", TX.mat_world)
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		if bp.has("ring_soup"):
			ring_node = Node3D.new()
			ring_node.name = "spire_ring"
			ring_node.position = mounts["crystal_pivot"]
			ring_node.visible = false
			add_child(ring_node)
			var rmi: MeshInstance3D = bp["ring_soup"].instance(ring_node, "ring", TX.mat_world)
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _finish_construction(fx_node: Node, audio_node: Node) -> void:
	building = false
	for pd in _pieces_data:
		var mi: MeshInstance3D = pd["mi"]
		if is_instance_valid(mi):
			mi.queue_free()
	_pieces_data.clear()
	if is_instance_valid(_scaffold_mi):
		_scaffold_mi.queue_free()
		_scaffold_mi = null

	# Commit single merged static mesh for optimal draw calls
	if _static_soup != null:
		_static_mi = _static_soup.instance(self, "tower_static", TX.mat_world)
		_static_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_static_soup = null

	if turret_node != null:
		turret_node.visible = true
	if crystal_node != null:
		crystal_node.visible = true
	if ring_node != null:
		ring_node.visible = true

	# Ignite tower flames!
	if fx_node != null:
		var base_p := global_position
		var f_col := Color(0.55, 0.85, 1.2) if kind == "spire" else Color(1.0, 0.90, 0.72)
		var f_scale := 0.52 + float(level) * 0.14
		for fp in mounts.get("flames", []):
			var wp: Vector3 = base_p + fp
			var fh: Dictionary = fx_node.add_flame(wp.x, wp.y, wp.z, f_scale, {
				"tint": f_col,
				"smoke": 0.12 if kind == "spire" else 0.42,
				"ember": 0.35,
				"halo": 0.42,
				"owner": self,
			})
			fh["local_pos"] = fp
			flame_handles.append(fh)
		fx_node.fx_dust(base_p.x, base_p.y + 0.2, base_p.z, 10, 1.15, 0x928068)
		fx_node.fx_sparks(base_p.x, base_p.y + float(mounts.get("height", 3.0)) * 0.65, base_p.z, 10, 3.2, 0xffd078, 1.0)
	if audio_node != null:
		audio_node.play_sfx("buildDone", 0.0, 0.9)


func update_visuals(dt: float, t: float, fx_node: Node, audio_node: Node) -> void:
	# Keep attached flames synced with tower world transform (e.g., during crumble!)
	if flame_handles.size() > 0:
		var xf := global_transform
		for fh in flame_handles:
			var lp: Vector3 = fh["local_pos"]
			var wp := xf * lp
			fh["x"] = wp.x
			fh["y"] = wp.y
			fh["z"] = wp.z

	if building:
		build_t += dt
		var u_sc := clampf(build_t / 0.25, 0.0, 1.0)
		if _scaffold_mi != null:
			var sc_y := U.ease_out_back(u_sc)
			if build_t > build_dur - 0.18:
				sc_y *= clampf((build_dur - build_t) / 0.18, 0.0, 1.0)
			_scaffold_mi.scale = Vector3(1.0, maxf(0.01, sc_y), 1.0)

		for pd in _pieces_data:
			var pt := build_t - float(pd["start"])
			var mi: MeshInstance3D = pd["mi"]
			if pt < 0.0:
				continue
			mi.visible = true
			var pu := clampf(pt / float(pd["dur"]), 0.0, 1.0)
			var y_off := (1.0 - U.ease_in(pu)) * float(pd["drop"])
			mi.position.y = y_off
			if pu >= 1.0 and not bool(pd["landed"]):
				pd["landed"] = true
				if fx_node != null:
					fx_node.fx_dust(global_position.x, global_position.y + 0.3, global_position.z, 3, 0.75, 0x8a7a64)
				if audio_node != null:
					audio_node.play_sfx("hammer", 0.0, 0.65, 0.9 + randf() * 0.25)
			elif pu >= 1.0:
				# Subtle landing squash recovery
				var bt := pt - float(pd["dur"])
				if bt < 0.14:
					var s := 1.0 + sin((bt / 0.14) * PI) * 0.08
					mi.scale = Vector3(s, 1.0 / s, s)
				else:
					mi.scale = Vector3.ONE

		if build_t >= build_dur:
			_finish_construction(fx_node, audio_node)
		return

	# Stun (Frost Jotun freeze)
	if stun > 0.0:
		stun = maxf(0.0, stun - dt)
		if freeze_mi != null:
			freeze_mi.visible = true
			freeze_mi.scale = Vector3.ONE * (0.96 + 0.04 * sin(t * 8.0))
	else:
		if freeze_mi != null:
			freeze_mi.visible = false

	# Bombard turret yaw & recoil recovery
	if turret_node != null:
		turret_node.rotation.y = U.ang_damp(turret_node.rotation.y, aim_yaw, 7.5, dt)
	if barrel_node != null:
		recoil = maxf(0.0, recoil - dt * 3.6)
		barrel_node.position.z = -recoil * 0.34
		barrel_node.rotation.x = -0.32 - recoil * 0.18

	# Storm Spire levitating crystal + counter-rotating rune ring + idle electric sparks
	if crystal_node != null:
		var spd := 1.5 + float(level) * 0.5 + charge_t * 5.0
		crystal_node.rotation.y += dt * spd
		var base_cp: Vector3 = mounts["crystal_pivot"]
		crystal_node.position.y = base_cp.y + sin(t * 2.8 + float(pad_idx)) * 0.16
		var cscale := 1.0 + charge_t * 0.22
		crystal_node.scale = Vector3.ONE * cscale
	if ring_node != null:
		ring_node.rotation.y -= dt * (1.1 + float(level) * 0.35 + charge_t * 3.0)
		ring_node.rotation.x = sin(t * 1.6 + float(pad_idx)) * 0.18
		ring_node.rotation.z = cos(t * 1.3 + float(pad_idx)) * 0.14

	# Archer sentries draw decay
	for aa in archer_anim:
		aa["draw"] = maxf(0.0, float(aa["draw"]) - dt * 3.0)


func get_light_info(t: float) -> Dictionary:
	if building or stun > 0.0:
		return {}
	var base_p := global_position
	var h := float(mounts.get("height", 3.2))
	var flk := 0.88 + 0.12 * sin(t * 13.0 + float(pad_idx) * 2.3)
	if kind == "spire":
		return {
			"pos": base_p + Vector3(0.0, h + 0.4, 0.0),
			"col": Color(0.45, 0.82, 1.0),
			"inten": (2.2 + float(level) * 0.85 + charge_t * 3.0) * flk,
			"range": 14.5 + float(level) * 2.0,
		}
	return {
		"pos": base_p + Vector3(0.0, h + 0.35, 0.0),
		"col": Color(1.0, 0.56, 0.18),
		"inten": (2.0 + float(level) * 0.75) * flk,
		"range": 13.5 + float(level) * 2.0,
	}


# ============================================================================
# Scaffolding Frame Builder
# ============================================================================

static func _build_scaffold(h: float) -> Soup:
	var sp := Soup.new()
	var C := Soup.COL()
	var r := 1.18
	for sx in [-r, r]:
		for sz in [-r, r]:
			sp.box(0.08, h + 0.4, 0.08, sx, (h + 0.4) * 0.5, sz, C["woodL"], {"l": TX.L_WOOD})
	var levels := maxi(2, int(h / 1.1))
	for i in levels:
		var y := 0.55 + float(i) * (h / float(levels))
		for sz in [-r, r]:
			sp.box(r * 2.08, 0.07, 0.07, 0, y, sz, C["wood"], {"l": TX.L_WOOD})
		for sx in [-r, r]:
			sp.box(0.07, 0.07, r * 2.08, sx, y, 0, C["wood"], {"l": TX.L_WOOD})
		sp.seg(Vector3(-r, y - 0.5, r), Vector3(r, y + 0.4, r), 0.035, 0.035, C["woodD"], {"l": TX.L_WOOD, "n": 4})
		sp.seg(Vector3(-r, y + 0.4, -r), Vector3(r, y - 0.5, -r), 0.035, 0.035, C["woodD"], {"l": TX.L_WOOD, "n": 4})
	return sp


# ============================================================================
# Detailed 4 x 3 Tower Blueprints (archer, bombard, spire, guard)
# ============================================================================

static func _build_blueprint(p_kind: String, lvl: int, rng: U.Rng) -> Dictionary:
	var C := Soup.COL()
	var pieces: Array = []
	var flames: Array[Vector3] = []
	var archers: Array[Vector3] = []
	var res: Dictionary = {"pieces": pieces}

	if p_kind == "archer":
		var h := 2.6 + float(lvl) * 0.72
		# Piece 0: Stone base plinth
		var p0 := Soup.new()
		p0.box(1.75, 0.55, 1.75, 0, 0.27, 0, C["stoneD"], {"l": TX.L_MASON, "uvs": 0.45})
		pieces.append(p0)

		# Piece 1: Timber / masonry watchtower shaft
		var p1 := Soup.new()
		if lvl == 0:
			for sx in [-0.62, 0.62]:
				for sz in [-0.62, 0.62]:
					p1.box(0.18, h, 0.18, sx, 0.55 + h * 0.5, sz, C["woodD"], {"l": TX.L_WOOD})
			p1.seg(Vector3(-0.62, 0.6, 0.62), Vector3(0.62, 0.55 + h, 0.62), 0.06, 0.06, C["wood"], {"l": TX.L_WOOD})
			p1.seg(Vector3(0.62, 0.6, -0.62), Vector3(-0.62, 0.55 + h, -0.62), 0.06, 0.06, C["wood"], {"l": TX.L_WOOD})
			p1.box(1.15, h * 0.5, 1.15, 0, 0.55 + h * 0.25, 0, C["wood"], {"l": TX.L_WOOD})
		else:
			p1.box(1.42, h, 1.42, 0, 0.55 + h * 0.5, 0, C["stone"] if lvl == 1 else C["stoneL"], {"l": TX.L_MASON, "uvs": 0.45})
			for sx in [-0.74, 0.74]:
				for sz in [-0.74, 0.74]:
					p1.box(0.24, h + 0.1, 0.24, sx, 0.55 + h * 0.5, sz, C["stoneD"], {"l": TX.L_MASON})
		pieces.append(p1)

		# Piece 2: Overhanging wooden fighting deck & crenellated parapet
		var dy := 0.55 + h
		var p2 := Soup.new()
		var dw := 1.85 + float(lvl) * 0.22
		p2.box(dw, 0.24, dw, 0, dy, 0, C["wood"], {"l": TX.L_WOOD})
		var hw := dw * 0.46
		for sx in [-hw, hw]:
			p2.box(0.16, 0.58, dw, sx, dy + 0.38, 0, C["stoneD"] if lvl > 0 else C["woodD"], {"l": TX.L_MASON if lvl > 0 else TX.L_WOOD})
		for sz in [-hw, hw]:
			p2.box(dw, 0.58, 0.16, 0, dy + 0.38, sz, C["stoneD"] if lvl > 0 else C["woodD"], {"l": TX.L_MASON if lvl > 0 else TX.L_WOOD})
		# Corner torch braziers
		for sx in [-hw, hw]:
			p2.cyl(0.15, 0.20, sx, dy + 0.78, hw, C["iron"], {"n": 6, "rt": 1.25, "l": TX.L_METAL})
			flames.append(Vector3(sx, dy + 0.90, hw))
		if lvl >= 1:
			p2.cloth_panel({"x0": -0.28, "x1": 0.28, "y_top": dy - 0.1, "len": 1.15, "z": hw + 0.14, "col": C["clothB"], "col2": C["gold"], "rng": rng, "sway": 0.85})
		pieces.append(p2)

		# Piece 3: Pitched roof canopy (Lvl 1 & 2)
		if lvl >= 1:
			var p3 := Soup.new()
			for sx in [-hw + 0.08, hw - 0.08]:
				for sz in [-hw + 0.08, hw - 0.08]:
					p3.box(0.12, 1.32, 0.12, sx, dy + 0.78, sz, C["woodD"], {"l": TX.L_WOOD})
			p3.cone(dw * 0.78, 1.15 + float(lvl) * 0.22, 0, dy + 1.92, 0, C["slate"], {"n": 4, "r": Vector3(0, PI * 0.25, 0), "l": TX.L_SLATE, "uvs": 0.75})
			if lvl == 2:
				p3.cyl(0.05, 0.65, 0, dy + 2.85, 0, C["gold"], {"n": 6, "l": TX.L_METAL, "rough": 0.35})
			pieces.append(p3)

		if lvl == 0:
			archers.append(Vector3(0.0, dy + 0.14, 0.0))
		elif lvl == 1:
			archers.append(Vector3(-0.36, dy + 0.14, 0.12))
			archers.append(Vector3(0.36, dy + 0.14, -0.12))
		else:
			archers.append(Vector3(-0.42, dy + 0.14, 0.22))
			archers.append(Vector3(0.42, dy + 0.14, 0.22))
			archers.append(Vector3(0.0, dy + 0.14, -0.38))

		res["mounts"] = {"flames": flames, "archers": archers, "fire_pos": Vector3(0, dy + 0.95, 0), "height": dy + (2.0 if lvl >= 1 else 1.0)}

	elif p_kind == "bombard":
		var h := 1.45 + float(lvl) * 0.38
		# Piece 0: Heavy fortified bastion base
		var p0 := Soup.new()
		p0.cyl(1.38, 0.65, 0, 0.32, 0, C["stoneD"], {"n": 8, "rt": 0.92, "l": TX.L_MASON, "uvs": 0.42})
		pieces.append(p0)

		# Piece 1: Thick masonry gun drum
		var p1 := Soup.new()
		p1.cyl(1.22, h, 0, 0.65 + h * 0.5, 0, C["stone"], {"n": 8, "rt": 0.96, "l": TX.L_MASON, "uvs": 0.45})
		for i in 8:
			var a := float(i) * PI * 0.25
			p1.box(0.24, h * 0.85, 0.24, cos(a) * 1.18, 0.65 + h * 0.45, sin(a) * 1.18, C["stoneD"], {"l": TX.L_MASON, "r": Vector3(0, -a, 0)})
		pieces.append(p1)

		# Piece 2: Iron-banded deck + ammo cannonball stack + furnace glow
		var dy := 0.65 + h
		var p2 := Soup.new()
		p2.cyl(1.32, 0.24, 0, dy, 0, C["iron"], {"n": 8, "l": TX.L_METAL, "rough": 0.48})
		# Stacked black iron cannonballs on deck edge
		for k in 3:
			var a := float(k) * 0.52 + 1.8
			p2.sph(0.14, cos(a) * 0.96, dy + 0.22, sin(a) * 0.96, C["iron"], {"w": 7, "h": 5, "l": TX.L_METAL, "rough": 0.38})
		# Glowing coal pot beside mortar
		p2.cyl(0.22, 0.24, -0.88, dy + 0.24, 0.62, C["iron"], {"n": 6, "rt": 1.2, "l": TX.L_METAL})
		p2.cyl(0.16, 0.08, -0.88, dy + 0.36, 0.62, C["ember"], {"n": 6, "emis": 1.6})
		flames.append(Vector3(-0.88, dy + 0.42, 0.62))
		if lvl == 2:
			p2.cyl(0.22, 0.24, 0.88, dy + 0.24, -0.62, C["iron"], {"n": 6, "rt": 1.2, "l": TX.L_METAL})
			flames.append(Vector3(0.88, dy + 0.42, -0.62))
		pieces.append(p2)

		# Rotating turret carriage + recoiling heavy mortar barrel
		var tur := Soup.new()
		tur.box(0.86, 0.22, 1.05, 0, 0.12, 0, C["woodD"], {"l": TX.L_WOOD})
		for sx in [-0.38, 0.38]:
			tur.box(0.14, 0.46, 0.88, sx, 0.32, -0.05, C["wood"], {"l": TX.L_WOOD})
			tur.cyl(0.22, 0.10, sx * 1.18, 0.20, 0.25, C["iron"], {"n": 8, "r": Vector3(0, 0, PI * 0.5), "l": TX.L_METAL})
		res["turret_soup"] = tur

		var bar := Soup.new()
		var blen := 1.25 + float(lvl) * 0.24
		var brad := 0.24 + float(lvl) * 0.045
		bar.cyl(brad, blen, 0, 0.20, 0.22, C["iron"], {"n": 10, "rt": 0.84, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.38})
		bar.torus(brad * 0.94, 0, 0.20, 0.22 + blen * 0.46, C["brass"], {"n": 10, "t": 0.18, "l": TX.L_METAL, "rough": 0.34})
		bar.torus(brad * 1.06, 0, 0.20, 0.22 - blen * 0.28, C["brass"], {"n": 10, "t": 0.16, "l": TX.L_METAL, "rough": 0.34})
		if lvl == 2:
			# Twin-banded siege dragon cannon accents
			bar.torus(brad * 1.0, 0, 0.20, 0.22 + blen * 0.12, C["gold"], {"n": 10, "t": 0.15, "l": TX.L_METAL, "rough": 0.32})
		res["barrel_soup"] = bar

		res["mounts"] = {
			"flames": flames, "archers": [],
			"turret_pivot": Vector3(0, dy + 0.14, 0),
			"fire_pos": Vector3(0, dy + 0.88, 0),
			"height": dy + 1.15,
		}

	elif p_kind == "spire":
		var h := 3.0 + float(lvl) * 0.65
		# Piece 0: Hexagonal obsidian/stone plinth
		var p0 := Soup.new()
		p0.cyl(1.24, 0.62, 0, 0.31, 0, C["basalt"], {"n": 6, "rt": 0.88, "l": TX.L_ROCK})
		pieces.append(p0)

		# Piece 1: Tapered arcane obelisk shaft with glowing rune inlays
		var p1 := Soup.new()
		p1.cyl(0.84, h, 0, 0.62 + h * 0.5, 0, C["stoneD"], {"n": 6, "rt": 0.56, "l": TX.L_MASON, "uvs": 0.45})
		for i in 3:
			var a := float(i) * TAU / 3.0
			p1.box(0.14, h * 0.72, 0.14, cos(a) * 0.62, 0.62 + h * 0.48, sin(a) * 0.62, C["crystal"], {"l": TX.L_PLAIN, "emis": 1.35 + float(lvl) * 0.35, "r": Vector3(0, -a, 0)})
		pieces.append(p1)

		# Piece 2: Curved iron lightning prongs cradling the levitating crystal
		var cy := 0.62 + h
		var p2 := Soup.new()
		var n_prongs := 3 + lvl
		for i in n_prongs:
			var a := float(i) * TAU / float(n_prongs)
			var b0 := Vector3(cos(a) * 0.46, cy - 0.15, sin(a) * 0.46)
			var bm := Vector3(cos(a) * 0.94, cy + 0.55, sin(a) * 0.94)
			var bt := Vector3(cos(a) * 0.68, cy + 1.35, sin(a) * 0.68)
			p2.seg(b0, bm, 0.10, 0.08, C["ironL"], {"l": TX.L_METAL, "rough": 0.42, "n": 5})
			p2.seg(bm, bt, 0.08, 0.03, C["steel"], {"l": TX.L_METAL, "rough": 0.35, "n": 5})
		pieces.append(p2)

		# Levitating crystal core + orbiting shards
		var crys := Soup.new()
		var cs := 0.44 + float(lvl) * 0.12
		crys.oct(cs, cs * 1.75, cs, 0, 0, 0, C["crystal"], {"l": TX.L_PLAIN, "rough": 0.15, "emis": 2.2 + float(lvl) * 0.45})
		for i in 2 + lvl:
			var a := float(i) * TAU / float(2 + lvl)
			crys.oct(cs * 0.28, cs * 0.58, cs * 0.28, cos(a) * 0.72, sin(a) * 0.18, sin(a) * 0.72, C["crystal"], {"l": TX.L_PLAIN, "rough": 0.18, "emis": 1.9})
		res["crystal_soup"] = crys

		# Counter-rotating carved stone rune ring
		var ring := Soup.new()
		ring.torus(0.95 + float(lvl) * 0.14, 0, 0, 0, C["stoneL"], {"n": 12, "t": 0.11, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_MASON})
		for i in 4:
			var a := float(i) * PI * 0.5
			ring.box(0.14, 0.14, 0.14, cos(a) * (0.95 + float(lvl) * 0.14), 0, sin(a) * (0.95 + float(lvl) * 0.14), C["crystal"], {"emis": 1.7})
		res["ring_soup"] = ring

		flames.append(Vector3(0.0, cy + 1.05, 0.0))
		res["mounts"] = {
			"flames": flames, "archers": [],
			"crystal_pivot": Vector3(0, cy + 0.92, 0),
			"fire_pos": Vector3(0, cy + 1.05, 0),
			"height": cy + 1.65,
		}

	else: # "guard" barracks & garrison post
		var p0 := Soup.new()
		p0.box(2.1, 0.42, 1.95, 0, 0.21, 0, C["stoneD"], {"l": TX.L_MASON, "uvs": 0.45})
		pieces.append(p0)

		var bh := 1.48 + float(lvl) * 0.34
		var p1 := Soup.new()
		p1.box(1.78, bh, 1.56, 0, 0.42 + bh * 0.5, -0.08, C["stone"] if lvl > 0 else C["wood"], {"l": TX.L_MASON if lvl > 0 else TX.L_WOOD, "uvs": 0.5})
		# Timber framing beams + arched barracks doorway
		for sx in [-0.90, 0.90]:
			p1.box(0.16, bh + 0.06, 0.16, sx, 0.42 + bh * 0.5, 0.72, C["woodD"], {"l": TX.L_WOOD})
		p1.box(0.72, 1.08, 0.18, 0, 0.96, 0.68, C["black"], {"l": TX.L_PLAIN})
		p1.box(0.92, 0.16, 0.24, 0, 1.54, 0.72, C["stoneL"] if lvl > 0 else C["woodD"], {"l": TX.L_MASON})
		# Weapon rack / shield mounted on wall
		p1.cyl(0.24, 0.08, -0.56, 1.24, 0.74, C["clothR"], {"n": 8, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.42})
		p1.cyl(0.24, 0.08, 0.56, 1.24, 0.74, C["clothR"], {"n": 8, "r": Vector3(PI * 0.5, 0, 0), "l": TX.L_METAL, "rough": 0.42})
		pieces.append(p1)

		var ry := 0.42 + bh
		var p2 := Soup.new()
		var roof_c: Color = C["thatch"] if lvl == 0 else C["slate"]
		var roof_l: int = TX.L_THATCH if lvl == 0 else TX.L_SLATE
		p2.box(2.18, 0.14, 1.18, 0, ry + 0.36, -0.44, roof_c, {"l": roof_l, "r": Vector3(0.46, 0, 0), "uvs": 0.8})
		p2.box(2.18, 0.14, 1.18, 0, ry + 0.36, 0.32, roof_c, {"l": roof_l, "r": Vector3(-0.46, 0, 0), "uvs": 0.8})
		# Garrison banner mast
		p2.cyl(0.05, 1.95, 0.78, ry + 1.05, -0.05, C["woodD"], {"n": 6, "l": TX.L_WOOD})
		p2.cloth_panel({"x0": 0.78, "x1": 1.48, "y_top": ry + 1.95, "len": 0.78, "z": -0.05, "col": C["clothR"], "col2": C["gold"], "rng": rng, "sway": 1.15})
		# Warm brazier beside entrance
		p2.cyl(0.18, 0.22, -0.78, 0.72, 0.82, C["iron"], {"n": 6, "rt": 1.2, "l": TX.L_METAL})
		flames.append(Vector3(-0.78, 0.86, 0.82))
		if lvl >= 1:
			p2.cyl(0.18, 0.22, 0.78, 0.72, 0.82, C["iron"], {"n": 6, "rt": 1.2, "l": TX.L_METAL})
			flames.append(Vector3(0.78, 0.86, 0.82))
		pieces.append(p2)

		res["mounts"] = {"flames": flames, "archers": [], "fire_pos": Vector3(0, ry + 0.6, 0), "height": ry + 1.4}

	return res
