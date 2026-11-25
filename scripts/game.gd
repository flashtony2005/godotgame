extends Node3D

const Defs := preload("res://scripts/defs.gd")
const MeshKit := preload("res://scripts/meshkit.gd")

## Cinderwatch · Godot 版主控：波次、战斗、AI 指挥官、相机与输入。
## 原版是自走塔防（AI 全自动打），这里保留「随时接管」的玩法。

const WorldS := preload("res://scripts/world.gd")
const TowerS := preload("res://scripts/tower.gd")
const MonsterS := preload("res://scripts/monster.gd")
const HudS := preload("res://scripts/hud.gd")
const PostS := preload("res://scripts/post.gd")
const RangeFXS := preload("res://scripts/range_fx.gd")

var world = null
var hud = null
var camera: Camera3D

# 经济与进度
var gold := 150
var lives := 20
var max_lives := 20
var wave_no := 0
var level := 0
var phase := "play"
var pressure := 1.0
var best_wave := 0
var leaks := 0
var wave_leaks := 0
var wave_kills := 0
var leak_types := {}

# 波次
var queue: Array = []
var wave_t := 0.0
var spawning := false
var boss_wave := false
var next_in := 7.0
var clear_t := 0.0
var trickle := 0.0

# 实体
var monsters: Array = []
var towers: Array = []
var projectiles: Array = []
var fx_list: Array = []
var footmen: Array = []

# 控制
var ai_active := true
var paused := false
var speed := 1
var follow := true
var camera_target := Vector3(0, 0, 0)
var camera_size := 25.0
var selected_pad: Dictionary = {}
var selected_tower = null
var range_fx = null
var range_fxs: Array = []
var preview_kind := "archer"
var _range_target = null
var hovered_pad: Dictionary = {}
var hovered_tower: Node = null

# 地图
var biome_index := 0
var biome: Dictionary = {}
var biome_key := "ashen"
var biome_wisp_color := Color("b090ff")
var seed_value := 0
var seen := {}
var ai_timer := 0.0
var time := 0.0
var selftest := false
var selftest_t := 0.0
var selftest_logged := false
var selftest_tick := 0.0
var _shot_mode := false
var _shot_times: Array = [6.0, 15.0, 24.0]
var _shot_i := 0

func _ready() -> void:
	randomize()
	var args := OS.get_cmdline_user_args()
	selftest = "--selftest" in args or "--shots" in args or "--showcase" in args
	_shot_mode = "--shots" in args
	seed_value = 12345 if selftest else randi() % 1000000
	for a in args:
		if a.begins_with("--biome="):
			biome_index = int(a.split("=")[1])
	biome_index = 0 if selftest and biome_index == 0 else biome_index
	if not selftest:
		biome_index = randi() % Defs.BIOMES.size()
	_setup_world()
	_setup_camera()
	_setup_hud()
	range_fxs.clear()
	for i in 4:
		var fx := RangeFXS.new()
		add_child(fx)
		range_fxs.append(fx)
	range_fx = range_fxs[0]
	hud.toast("第一波还有 7 秒。点击空地建塔，也可以直接看着 AI 打。")
	hud.set_stats(self)
	if selftest:
		ai_active = not ("--noai" in args)
		print("[selftest] seed=%d biome=%s pads=%d len=%.1f ai=%s" % [seed_value, biome_key, world.pads.size(), world.length, ai_active])
		if "--showcase" in args:
			_showcase()
		else:
			_run_pick_test()

func _setup_world() -> void:
	world = WorldS.new()
	add_child(world)
	var ok := false
	for attempt in 12:
		var s := seed_value + attempt * 97
		var b := (biome_index + attempt) % Defs.BIOMES.size()
		ok = world.generate(s, b)
		if ok:
			seed_value = s
			biome_index = b
			break
	if not ok:
		push_error("地图生成失败")
	biome = Defs.BIOMES[biome_index]
	biome_key = biome["key"]
	biome_wisp_color = biome["wisp_hex"]
	world.build_visuals()
	var post := PostS.new()
	add_child(post)
	post.set_tint(biome.get("post_tint", Color.WHITE))

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)
	var dir := Vector3(1.0, 1.15, 1.0).normalized() * 60.0
	camera.position = dir + camera_target
	camera.look_at(camera_target, Vector3.UP)
	camera.make_current()

func camera_basis() -> Basis:
	return camera.global_transform.basis

# ---------------------------------------------------------------- HUD 桥

func _setup_hud() -> void:
	hud = HudS.new()
	add_child(hud)
	hud.game = self

func toast(msg: String) -> void:
	hud.toast(msg)

# ---------------------------------------------------------------- 主循环

func _run_pick_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if world.pads.is_empty():
		print("[test] no pads")
		return
	var pad: Dictionary = world.pads[0]
	var sp: Vector2 = camera.unproject_position(Vector3(float(pad["x"]), 0.25, float(pad["z"])))
	_on_click(sp)
	print("[test] click pad at screen %s -> selected=%s" % [sp, not selected_pad.is_empty()])
	if not selected_pad.is_empty():
		var ok: bool = build_tower(selected_pad, "archer")
		print("[test] build archer ok=%s towers=%d gold=%d" % [ok, towers.size(), gold])

func _showcase() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	gold = 99999
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	if only == "range":
		await _showcase_range()
		return
	for t in towers:
		if is_instance_valid(t):
			t.queue_free()
	towers.clear()
	for m in monsters:
		if is_instance_valid(m):
			m.queue_free()
	monsters.clear()
	paused = true
	var kinds := ["archer", "bombard", "spire", "guard"]
	for i in kinds.size():
		var pad: Dictionary = {"x": -9.0 + float(i) * 6.0, "z": -9.0, "s": 0.0}
		var t = TowerS.new()
		add_child(t)
		t.setup(kinds[i], pad, self)
		t.lvl = 1
		t.upgrade()  # 升到 2 级重建一次
		towers.append(t)
	var types: Array = Defs.MON.keys()
	types.sort()
	if only != "":
		types = only.split(",")
	else:
		pass
	var want_mon := only != "towers"
	if not want_mon:
		types = []
	for i in types.size():
		var col := i % 4
		var row := i / 4
		var m = MonsterS.new()
		add_child(m)
		m.setup(types[i], 1.0, 10.0, 0.0, self)
		m.speed_mul = 0.0
		m.position = Vector3(-5.0 + float(col) * 3.2, 0, 0.0 + float(row) * 3.4)
		monsters.append(m)
	camera_target = Vector3(0.0, 1.6, 8.0)
	camera_size = 26.0
	if only == "towers":
		camera_target = Vector3(0.0, 2.2, -9.0)
		camera_size = 15.0
	elif only != "":
		camera_target = Vector3(0.0, 0.9, 1.0)
		camera_size = 7.0
	var dir := Vector3(1.0, 1.15, 1.0).normalized() * 60.0
	camera.position = dir + camera_target
	camera.look_at(camera_target, Vector3.UP)
	await get_tree().create_timer(1.6).timeout
	var tri_t := 0
	var tri_m := 0
	for t in towers:
		for mi in t.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				tri_t += mi.mesh.get_faces().size() / 3
	for m in monsters:
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				tri_m += mi.mesh.get_faces().size() / 3
	print("[showcase] towers=%s tris=%d monsters=%d tris=%d total=%d" % [towers.size(), tri_t, monsters.size(), tri_m, tri_t + tri_m])
	await _capture(9)
	get_tree().quit()

func _showcase_range() -> void:
	var kinds := ["archer", "bombard", "spire", "guard"]
	paused = true
	camera_target = Vector3(float(world.pads[1]["x"]), 0.5, float(world.pads[1]["z"]))
	camera_size = 22.0
	camera.position = camera_target + Vector3(1.0, 1.15, 1.0).normalized() * 60.0
	camera.look_at(camera_target, Vector3.UP)
	selected_pad = world.pads[1]
	selected_tower = null
	hud.open_build(world.pads[1])
	for i in kinds.size():
		preview_build(kinds[i])
		await get_tree().create_timer(0.55).timeout
		await _capture(i + 1)
	get_tree().quit()

func _capture(idx: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := "/tmp/cw_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/shot_%d.png" % [dir, idx])
	print("[shot] saved %d" % idx)

func _process(delta: float) -> void:
	var dt := delta
	if not paused:
		dt = delta * float(speed)
		time += dt
		_tick(dt)
	_update_camera(delta)
	_update_hover()
	if selftest and _shot_mode and _shot_i < _shot_times.size() and selftest_t >= float(_shot_times[_shot_i]):
		_shot_i += 1
		_capture(_shot_i)
	if selftest:
		selftest_t += delta
		if _shot_mode and selftest_t > 25.0:
			get_tree().quit()
		if selftest_t - selftest_tick >= 6.0:
			selftest_tick = selftest_t
			print("[t] %.0f wave=%d gold=%d lives=%d towers=%d mon=%d kills=%d next=%.1f" % [selftest_t, wave_no, gold, lives, towers.size(), monsters.size(), wave_kills, next_in])
		if selftest_t > 26.0 and not selftest_logged:
			selftest_logged = true
			print("[selftest] t=%.0f wave=%d gold=%d lives=%d towers=%d monsters=%d kills=%d" % [selftest_t, wave_no, gold, lives, towers.size(), monsters.size(), wave_kills])
			if not _shot_mode:
				get_tree().quit()

func _tick(dt: float) -> void:
	_update_waves(dt)
	_update_towers(dt)
	_update_footmen(dt)
	_update_monsters(dt)
	_update_projectiles(dt)
	_update_fx(dt)
	_ai_think(dt)
	hud.set_stats(self)

# ---------------------------------------------------------------- 波次

func wave_menu(k: int, lv: int) -> Array:
	var w := lv * 5 + k
	var menu: Array = []
	for ty in Defs.ROSTER:
		var r: Array = Defs.ROSTER[ty]
		var mobs: Dictionary = biome["mobs"]
		var mul := float(mobs.get(ty, 1.0))
		var early: Dictionary = biome["early"]
		var unlock: int = mini(int(r[4]), int(early.get(ty, 99)))
		var weight: float = float(r[5]) * mul if float(r[5]) > 0.0 else float(mobs.get(ty, 0.0))
		if w >= unlock and weight > 0.0:
			menu.append([ty, weight * (2.2 if (w == unlock and w > 1) else 1.0)])
	return menu

func boss_type() -> String:
	var b: Array = biome["boss"]
	return String(b[(level / Defs.BIOMES.size()) % b.size()])

func build_wave(k: int, lv: int) -> Array:
	var q: Array = []
	var boss := k == 5
	var lv_mul := 1.0 + 0.25 * float(lv)
	var budget := (34.0 + 25.0 * float(k - 1)) * lv_mul * pressure * (0.7 if boss else 1.0)
	var heavy := 0
	var air := budget * 0.42
	var hp_mul := (1.0 + 0.13 * float(k - 1)) * (1.0 + 0.27 * float(lv)) * (0.85 + 0.15 * pressure)
	var menu := wave_menu(k, lv)
	var tot := 0.0
	for m in menu:
		tot += float(m[1])
	if tot <= 0.0:
		menu = [["skel", 1.0]]
		tot = 1.0
	var t := 0.6
	if boss:
		q.append({"t": 2.2, "type": boss_type(), "hp": (1.0 + 0.4 * float(lv)) * pow(pressure, 0.4)})
	var guard := 0
	while budget > 0.0 and guard < 400:
		guard += 1
		var r := randf() * tot
		var ty := "skel"
		for m in menu:
			r -= float(m[1])
			if r <= 0.0:
				ty = String(m[0])
				break
		var R: Array = Defs.ROSTER[ty]
		var mdef: Dictionary = Defs.MON[ty]
		if float(R[0]) > budget + 5.0 or (float(R[0]) >= 30.0 and heavy >= 1 + (lv >> 1)) or (mdef.get("fly", false) and air <= 0.0):
			ty = "skel"
			R = Defs.ROSTER["skel"]
		if float(R[0]) >= 30.0:
			heavy += 1
		var n := int(floor(randf_range(float(R[1]), float(R[2]) + 0.999)))
		var gap: float = float(R[3])
		for i in n:
			if budget <= 0.0:
				break
			q.append({"t": t, "type": ty, "hp": hp_mul})
			t += gap * randf_range(0.8, 1.25)
			budget -= float(R[0])
			if mdef.get("fly", false):
				air -= float(R[0])
		t += randf_range(1.1, 2.3) * (1.5 if boss else 1.0)
	q.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return q

func start_wave() -> void:
	level = int(wave_no / 5) if wave_no > 0 else 0
	var k := (wave_no % 5) + 1
	wave_no = level * 5 + k
	queue = build_wave(k, level)
	wave_t = 0.0
	spawning = true
	boss_wave = k == 5
	wave_kills = 0
	wave_leaks = 0
	clear_t = 0.0
	trickle = 6.0
	best_wave = maxi(best_wave, wave_no)
	hud.banner("第 %d 波%s" % [wave_no, " · " + String(Defs.MON[boss_type()]["name"]) if boss_wave else ""], boss_wave)
	hud.set_stats(self)

func end_wave() -> void:
	if wave_leaks == 0:
		pressure *= 1.17
	elif wave_leaks >= 6:
		pressure *= 0.8
	elif wave_leaks >= 3:
		pressure *= 0.9
	if lives <= 6:
		pressure *= 0.9
	pressure = clampf(pressure, 0.6, 2.2)
	var bonus := 24 + 9 * ((wave_no - 1) % 5 + 1) + 10 * level
	gold += bonus
	hud.toast("第 %d 波清场，+%d 金" % [wave_no, bonus])

func _update_waves(dt: float) -> void:
	if phase != "play":
		return
	if spawning:
		wave_t += dt
		while not queue.is_empty() and float(queue[0]["t"]) <= wave_t:
			if monsters.size() > 90:
				break
			var e: Dictionary = queue.pop_front()
			_spawn(String(e["type"]), float(e["hp"]))
		if queue.is_empty():
			var boss_alive := false
			for m in monsters:
				if m.boss and m.alive:
					boss_alive = true
			if boss_wave and boss_alive:
				trickle -= dt
				if trickle <= 0.0:
					trickle = randf_range(3.2, 4.6)
					var tm: Array = wave_menu(5, level).filter(func(e): return float(Defs.ROSTER[String(e[0])][0]) < 13.0)
					if not tm.is_empty():
						var ty := String(tm[randi() % tm.size()][0])
						var n := maxi(1, mini(5, int(round(8.0 / float(Defs.ROSTER[ty][0])))))
						for i in n:
							queue.append({"t": wave_t + float(i) * 0.4, "type": ty, "hp": 1.5 * (1.0 + 0.22 * float(level))})
			else:
				spawning = false
				end_wave()
				next_in = 6.5
	elif boss_wave:
		clear_t += dt
		var any_alive := false
		for m in monsters:
			if m.alive:
				any_alive = true
		if not any_alive or clear_t > 40.0:
			_advance_stage()
	else:
		next_in -= dt
		if next_in <= 0.0:
			start_wave()
	if lives <= 0 and phase == "play":
		_defeat()

func _advance_stage() -> void:
	level += 1
	wave_no = level * 5
	phase = "clear"
	hud.banner("这一片地碎了，下一片在黑暗里拼起来", false)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func():
		biome_index = (biome_index + 1) % Defs.BIOMES.size()
		_setup_world()
		_clear_field()
		phase = "play"
		next_in = 8.0
		wave_no = level * 5
		hud.toast("进入 %s" % String(biome["name"]))
	)

func _clear_field() -> void:
	for m in monsters:
		m.queue_free()
	monsters.clear()
	for t in towers:
		t.queue_free()
	towers.clear()
	footmen.clear()
	for p in projectiles:
		if p.has("node") and is_instance_valid(p["node"]):
			p["node"].queue_free()
	projectiles.clear()
	selected_pad = {}
	selected_tower = null
	hud.close_menus()

func call_wave_early() -> void:
	if phase == "play" and not spawning and not boss_wave and next_in > 0.4:
		gold += int(round(next_in * 3.0))
		next_in = 0.05
		hud.toast("提前叫波 +%d 金" % int(round(next_in * 3.0)))

func _defeat() -> void:
	phase = "defeat"
	hud.banner("信标熄了 —— 你撑到第 %d 波，按 R 重来" % wave_no, true)

# ---------------------------------------------------------------- 生成

func _spawn(type: String, hp_mul: float, at_s := -1.0):
	if not Defs.MON.has(type):
		return null
	var m := MonsterS.new()
	var s0 := at_s if at_s >= 0.0 else randf_range(-1.2, 0.4)
	var lat := randf_range(-0.85, 0.85)
	add_child(m)
	m.setup(type, hp_mul, s0, lat, self)
	monsters.append(m)
	if not seen.has(type):
		seen[type] = true
		var tip := String(Defs.MON[type].get("tip", ""))
		if tip != "":
			hud.toast("%s：%s" % [String(Defs.MON[type]["name"]), tip])
	return m

# ---------------------------------------------------------------- 塔

func build_tower(pad: Dictionary, kind: String, quiet := false) -> bool:
	if phase != "play" or pad.is_empty() or pad.has("tower"):
		return false
	var cost: int = int(Defs.TOWER[kind]["cost"][0])
	if gold < cost:
		if not quiet:
			hud.toast("金币不够，还差 %d" % (cost - gold))
		return false
	gold -= cost
	var t := TowerS.new()
	add_child(t)
	t.setup(kind, pad, self)
	towers.append(t)
	pad["tower"] = t
	selected_pad = {}
	selected_tower = t
	hud.close_menus()
	hud.open_tower(t)
	_show_tower_range(t, 1.0)
	return true

func upgrade_tower(t, quiet := false) -> void:
	if t == null or not is_instance_valid(t) or not t.alive or not t.can_upgrade():
		return
	var cost: int = t.upgrade_cost()
	if gold < cost:
		if not quiet:
			hud.toast("金币不够，还差 %d" % (cost - gold))
		return
	gold -= cost
	t.upgrade()
	if t.kind == "guard":
		_refresh_footmen()
	hud.open_tower(t)
	_show_tower_range(t, 1.0)

func sell_tower(t: Node) -> void:
	if t == null or not is_instance_valid(t) or not t.alive:
		return
	gold += t.sell_refund()
	_refresh_footmen()
	var p: Dictionary = t.pad
	p.erase("tower")
	towers.erase(t)
	t.alive = false
	t.queue_free()
	selected_tower = null
	hud.close_menus()
	hide_range()

# ---------------------------------------------------------------- 射程预览

func _kind_range(k: String, lv: int) -> float:
	var d: Dictionary = Defs.TOWER[k]
	var arr: Array = d["range"]
	return float(arr[mini(lv, arr.size() - 1)])

func _kind_min(k: String) -> float:
	return float(Defs.TOWER[k].get("min_range", 0.0))

func preview_build(k: String) -> void:
	preview_kind = k
	if range_fxs.is_empty():
		return
	if not selected_pad.is_empty():
		_refresh_pad_ranges(selected_pad)
	elif selected_tower != null and is_instance_valid(selected_tower):
		_show_tower_range(selected_tower, 1.0)
	elif not hovered_pad.is_empty() and not hovered_pad.has("tower"):
		_show_pad_range(hovered_pad, k, 0.5)

func _pad_ring_pos(pad: Dictionary) -> Vector3:
	return Vector3(float(pad["x"]), 0.32, float(pad["z"]))

# 选中空格子：四种塔的射程同时画出来，各自造型/颜色不同，当前要建的那座最亮
func _refresh_pad_ranges(pad: Dictionary) -> void:
	if range_fxs.is_empty() or pad.is_empty():
		return
	var pos := _pad_ring_pos(pad)
	var kinds := Defs.TOWER_KINDS
	for i in range_fxs.size():
		var k := String(kinds[mini(i, kinds.size() - 1)])
		var a: float = 1.0 if k == preview_kind else 0.42
		range_fxs[i].show_range(k, _kind_range(k, 0), _kind_min(k), pos, a)

func _show_pad_range(pad: Dictionary, k: String, alpha: float) -> void:
	if range_fxs.is_empty() or pad.is_empty():
		return
	hide_range()
	range_fxs[0].show_range(k, _kind_range(k, 0), _kind_min(k), _pad_ring_pos(pad), alpha)

func _show_tower_range(t, alpha: float) -> void:
	if range_fxs.is_empty() or t == null or not is_instance_valid(t):
		return
	hide_range()
	var lv: int = int(t.lvl)
	var k := String(t.kind)
	range_fxs[0].show_range(k, _kind_range(k, lv), _kind_min(k),
		Vector3(t.position.x, 0.32, t.position.z), alpha)

func hide_range() -> void:
	for fx in range_fxs:
		if fx != null:
			fx.hide_range()

func _refresh_footmen() -> void:
	footmen.clear()
	for t in towers:
		if t.kind == "guard":
			for f in t.footmen:
				footmen.append(f)

func _update_towers(dt: float) -> void:
	for t in towers:
		if not is_instance_valid(t) or not t.alive:
			continue
		if t.stun > 0.0:
			t.stun -= dt
			continue
		t.cooldown -= dt
		if t.cooldown > 0.0:
			continue
		if t.kind == "guard":
			t.cooldown = 0.2
			continue
		var st: Dictionary = t.stats()
		var target: Node = _find_target(t, float(st["range"]), t.kind == "bombard")
		if target == null:
			continue
		t.cooldown = float(st["rate"])
		match t.kind:
			"archer":
				_fire_archer(t, target, st)
			"bombard":
				_fire_bombard(t, target, st)
			"spire":
				_fire_spire(t, target, st)
		if t.turret != null and is_instance_valid(t.turret):
			var to: Vector3 = target.position - t.global_position
			t.turret.rotation.y = atan2(to.x, to.z)

func _find_target(t, range_v: float, min_range: bool):
	var best = null
	var best_s := -1.0
	var def: Dictionary = t.def
	for m in monsters:
		if not is_instance_valid(m) or not m.alive:
			continue
		if m.flying and not def.get("air", false):
			continue
		if not m.flying and not def.get("ground", true):
			continue
		var d: float = (m.global_position - t.global_position).length()
		if d > range_v:
			continue
		if min_range and d < float(def.get("min_range", 0.0)):
			continue
		if m.s > best_s:
			best_s = m.s
			best = m
	return best

func _fire_archer(t: Node, target: Node, st: Dictionary) -> void:
	var count: int = int(st.get("count", 1))
	for i in count:
		var from: Vector3 = t.global_position + Vector3(0, 2.0 + float(t.lvl) * 0.6, 0)
		var p := {"kind": "arrow", "from": from, "to": target, "t": 0.0, "time": 0.28,
			"speed": 22.0, "dmg": float(st["dmg"]), "target": target, "node": null,
			"delay": float(i) * 0.06}
		_spawn_projectile(p, Color("ffcf8a"), 0.5)

func _fire_bombard(t: Node, target: Node, st: Dictionary) -> void:
	var from: Vector3 = t.global_position + Vector3(0, 2.4 + float(t.lvl) * 0.5, 0)
	var aim: Vector3 = target.global_position
	var p := {"kind": "shell", "from": from, "to_pos": aim, "t": 0.0, "time": 0.72,
		"dmg": float(st["dmg"]), "splash": float(st["splash"]), "node": null, "arc": 2.6}
	_spawn_projectile(p, Color("2a2620"), 0.16)

func _fire_spire(t: Node, target: Node, st: Dictionary) -> void:
	var dmg: float = float(st["dmg"])
	var jumps: int = int(st.get("jumps", 3))
	var slow: float = float(st.get("slow", 0.0))
	var slow_t: float = float(st.get("slow_t", 0.0))
	var from: Vector3 = t.global_position + Vector3(0, 3.0 + float(t.lvl) * 0.7, 0)
	var hit: Array = [target]
	var dead: bool = target.take_damage(dmg, "light", t)
	target.set_slow(slow, slow_t)
	_lightning(from, target.global_position + Vector3(0, 0.5, 0))
	var last = target
	var cur_dmg := dmg * 0.78
	for j in jumps:
		var nxt = null
		var best_d := 4.0
		for m in monsters:
			if not is_instance_valid(m) or not m.alive or m == last:
				continue
			if hit.has(m):
				continue
			var d: float = (m.global_position - last.global_position).length()
			if d < best_d:
				best_d = d
				nxt = m
		if nxt == null:
			break
		_lightning(last.global_position + Vector3(0, 0.6, 0), nxt.global_position + Vector3(0, 0.5, 0))
		nxt.take_damage(cur_dmg, "light", t)
		nxt.set_slow(slow * 0.8, slow_t)
		hit.append(nxt)
		last = nxt
		cur_dmg *= 0.78
	if dead:
		_on_kill(target, "light")

func add_damage(_v: float) -> void:
	pass

# ---------------------------------------------------------------- 弹道

func _spawn_projectile(p: Dictionary, col: Color, r: float) -> void:
	var node := MeshInstance3D.new()
	if String(p["kind"]) == "arrow":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.02
		cm.height = 0.7
		cm.radial_segments = 4
		node.mesh = cm
		node.material_override = MeshKit.mat(col, 1.2)
		node.rotation = Vector3(PI * 0.5, 0, 0)
	else:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 6
		node.mesh = sm
		node.material_override = MeshKit.mat(col, 0.2)
	add_child(node)
	node.position = p["from"]
	p["node"] = node
	projectiles.append(p)

func _update_projectiles(dt: float) -> void:
	var remove: Array = []
	for p in projectiles:
		p["t"] += dt
		var node = p["node"]
		if not is_instance_valid(node):
			remove.append(p)
			continue
		if p.has("delay") and float(p["delay"]) > 0.0:
			p["delay"] = float(p["delay"]) - dt
			node.visible = false
			continue
		node.visible = true
		var k: float = clampf(float(p["t"]) / float(p["time"]), 0.0, 1.0)
		if String(p["kind"]) == "arrow":
			var target = p["target"]
			var to: Vector3
			if target != null and is_instance_valid(target) and target.alive:
				to = target.global_position + Vector3(0, float(target.def["top"]) * 0.6, 0)
				p["to_point"] = to
			else:
				to = p.get("to_point", p["from"])
			node.position = (p["from"] as Vector3).lerp(to, k)
			node.look_at(to + Vector3(0, 0.01, 0))
			node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			if k >= 1.0:
				if target != null and is_instance_valid(target) and target.alive:
					var died: bool = target.take_damage(float(p["dmg"]), "arrow", p.get("tower"))
					if died:
						_on_kill(target, "arrow")
				node.queue_free()
				remove.append(p)
		else:
			var from: Vector3 = p["from"]
			var to_pos: Vector3 = p["to_pos"]
			var arc := sin(k * PI) * float(p["arc"])
			node.position = from.lerp(to_pos, k) + Vector3(0, arc, 0)
			if k >= 1.0:
				_explode(to_pos, float(p["splash"]), float(p["dmg"]), "blast", null)
				node.queue_free()
				remove.append(p)
	for p in remove:
		projectiles.erase(p)

func _explode(pos: Vector3, radius: float, dmg: float, kind: String, src: Node) -> void:
	for m in monsters.duplicate():
		if not is_instance_valid(m) or not m.alive or m.flying:
			continue
		var d: float = (m.global_position - pos).length()
		if d > radius + m.radius:
			continue
		var falloff: float = 1.0 - 0.5 * d / (radius + m.radius)
		var died: bool = m.take_damage(dmg * falloff, kind, null)
		if died:
			_on_kill(m, kind)
	for f in footmen:
		if not f["alive"]:
			continue
		var node = f["node"]
		var d: float = (node.global_position - pos).length()
		if d < radius:
			f["hp"] = float(f["hp"]) - dmg * 0.6
			if float(f["hp"]) <= 0.0:
				_footman_dies(f)
	_fx_ring(pos, radius, Color("ffa040"))

func _lightning(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	if ln <= 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, ln)
	mi.mesh = bm
	mi.material_override = MeshKit.mat(Color("9fe8ff"), 3.0)
	add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	fx_list.append({"node": mi, "t": 0.0, "life": 0.22, "kind": "fade"})

func _update_fx(dt: float) -> void:
	var remove: Array = []
	for f in fx_list:
		f["t"] += dt
		var node = f["node"]
		if not is_instance_valid(node):
			remove.append(f)
			continue
		var k: float = float(f["t"]) / float(f["life"])
		if k >= 1.0:
			node.queue_free()
			remove.append(f)
			continue
		if node is MeshInstance3D:
			var m: StandardMaterial3D = node.material_override
			if m != null:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(m.albedo_color.r, m.albedo_color.g, m.albedo_color.b, 1.0 - k)
			if f.get("grow", false):
				node.scale = node.scale * (1.0 + dt * 2.5)
	for f in remove:
		fx_list.erase(f)

func _fx_ring(pos: Vector3, radius: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.4
	cm.height = 0.04
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = MeshKit.mat(col, 2.0)
	mi.position = pos + Vector3(0, 0.1, 0)
	add_child(mi)
	fx_list.append({"node": mi, "t": 0.0, "life": 0.5, "kind": "fade", "grow": true})
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), 0.45)

# ---------------------------------------------------------------- 步兵

func _update_footmen(dt: float) -> void:
	footmen.clear()
	for t in towers:
		if not is_instance_valid(t) or not t.alive:
			continue
		if t.kind != "guard":
			continue
		var range_v: float = float(t.stats()["range"])
		var dmg: float = float(t.stats()["dmg"])
		for f in t.footmen:
			footmen.append(f)
			if not f["alive"]:
				f["respawn"] = float(f.get("respawn", 0.0)) - dt
				if float(f["respawn"]) <= 0.0:
					f["alive"] = true
					f["hp"] = f["max_hp"]
					f["node"].visible = true
					f["node"].position = f["home"]
				continue
			var node = f["node"]
			var home: Vector3 = t.global_position + f["home"]
			var target = null
			var best := range_v
			for m in monsters:
				if not is_instance_valid(m) or not m.alive or m.flying or m.def.get("slip", false):
					continue
				var d: float = (m.global_position - home).length()
				if d < best:
					best = d
					target = m
			if target != null:
				var to: Vector3 = target.global_position
				var d2: float = (node.global_position - to).length()
				if d2 > 0.78:
					var dir: Vector3 = to - node.global_position
					dir.y = 0.0
					if dir.length_squared() > 0.001:
						node.position += dir.normalized() * minf(dt * 2.1, d2 - 0.7)
				f["cd"] = float(f["cd"]) - dt
				if d2 < 1.3 and float(f["cd"]) <= 0.0:
					f["cd"] = 0.66
					var died: bool = target.take_damage(dmg * 1.15, "sword", t)
					var sw = f.get("sword")
					if sw != null and is_instance_valid(sw):
						var tw2: Tween = create_tween()
						tw2.tween_property(sw, "rotation", Vector3(-0.6, 0.0, 0.0), 0.08)
						tw2.tween_property(sw, "rotation", Vector3.ZERO, 0.16)
					if died:
						_on_kill(target, "sword")
			else:
				var dh: float = (node.global_position - home).length()
				if dh > 0.2:
					var back: Vector3 = home - node.global_position
					back.y = 0.0
					node.position += back.normalized() * minf(dt * 1.4, dh)
			f["hp"] = minf(float(f["max_hp"]), float(f["hp"]) + dt * 4.0)
			node.rotation.y += dt * 2.0

func _footman_dies(f: Dictionary) -> void:
	f["alive"] = false
	f["hp"] = 0.0
	f["respawn"] = 8.0
	f["node"].visible = false

# ---------------------------------------------------------------- 怪物

func _update_monsters(dt: float) -> void:
	var remove: Array = []
	# 鼓手光环
	var drummers: Array = []
	for m in monsters:
		if is_instance_valid(m) and m.alive and m.type == "drummer":
			drummers.append(m)
	for m in monsters:
		if not is_instance_valid(m) or not m.alive:
			continue
		m.haste = 1.0
		for d in drummers:
			if d == m:
				continue
			if (d.global_position - m.global_position).length() < float(d.def["aura"][0]):
				m.haste = 1.0 + float(d.def["aura"][1])
		# 怨灵虚化
		if m.def.has("ghost"):
			m.ghost_t -= dt
			if m.ghost_t <= 0.0:
				m.ghosting = not m.ghosting
				m.ghost_t = randf_range(float(m.def["ghost"][0]), float(m.def["ghost"][1]))
		# 被步兵挡路
		var blocked: Dictionary = {}
		if not m.flying and not m.def.get("slip", false):
			for f in footmen:
				if not f["alive"]:
					continue
				var fn = f["node"]
				if (fn.global_position - m.global_position).length() < 0.85 + m.radius:
					blocked = f
					break
		if blocked.is_empty():
			m.advance(dt, world)
		else:
			m.atk_cd -= dt
			if m.atk_cd <= 0.0 and float(m.def["dmg"]) > 0.0:
				m.atk_cd = float(m.def["atk_t"])
				blocked["hp"] = float(blocked["hp"]) - float(m.def["dmg"])
				if float(blocked["hp"]) <= 0.0:
					_footman_dies(blocked)
		# 召唤 / 踏地
		if m.def.has("summon"):
			m.sum_t -= dt
			if m.sum_t <= 0.0:
				var sdef: Dictionary = m.def["summon"]
				m.sum_t = float(sdef["every"]) * randf_range(0.8, 1.1)
				for i in int(sdef["n"]):
					_spawn(String(sdef["type"]), float(sdef["hp"]), maxf(0.0, m.s - 1.2))
		if m.def.has("stomp"):
			m.stomp_t -= dt
			if m.stomp_t <= 0.0:
				m.stomp_t = float(m.def["stomp"]["every"])
				var radius: float = float(m.def["stomp"]["r"])
				for t in towers:
					if (t.global_position - m.global_position).length() < radius:
						t.stun = float(m.def["stomp"]["stun"])
				_fx_ring(m.global_position, radius, Color("8fe0ff"))
		m.animate(dt, blocked.is_empty())
		# 到达信标
		if m.s >= world.length:
			lives -= int(m.def["lives"])
			wave_leaks += int(m.def["lives"])
			leaks += int(m.def["lives"])
			var ty: String = m.type
			leak_types[ty] = int(leak_types.get(ty, 0)) + 1
			remove.append(m)
			m.alive = false
			m.queue_free()
			hud.flash_lives()
	# 清理
	for m in remove:
		monsters.erase(m)
	if lives < 0:
		lives = 0

func _on_kill(m, kind: String) -> void:
	if not is_instance_valid(m) or not monsters.has(m):
		return
	var def: Dictionary = m.def
	gold += int(def.get("bounty", 0))
	wave_kills += 1
	var pos: Vector3 = m.global_position
	if def.has("split"):
		var sp: Array = def["split"]
		for i in int(sp[1]):
			var child = _spawn(String(sp[0]), 1.0, m.s)
			if child != null:
				child.position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	if def.has("explode"):
		var ex: Dictionary = def["explode"]
		_explode(pos, float(ex["r"]), float(ex["dmg"]), "blast", null)
	_fx_burst(pos, def)
	monsters.erase(m)
	m.alive = false
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(1.6, 0.2, 1.6), 0.22)
	tw.tween_callback(m.queue_free)

func _fx_burst(pos: Vector3, def: Dictionary) -> void:
	var col: Color = Color("e8e0c8")
	if def.get("death", "") == "goo":
		col = Color("6ac07a")
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 6
	mi.mesh = sm
	mi.material_override = MeshKit.mat(col, 1.2)
	mi.position = pos + Vector3(0, 0.4, 0)
	add_child(mi)
	fx_list.append({"node": mi, "t": 0.0, "life": 0.32, "kind": "fade", "grow": true})

# ---------------------------------------------------------------- AI 指挥官

func _ai_think(dt: float) -> void:
	if not ai_active or phase != "play" or paused:
		return
	ai_timer -= dt
	if ai_timer > 0.0:
		return
	ai_timer = 0.45
	var empty: Array = []
	for p in world.pads:
		if not p.has("tower"):
			empty.append(p)
	var count := {"archer": 0, "bombard": 0, "spire": 0, "guard": 0}
	for t in towers:
		if is_instance_valid(t) and t.alive:
			count[t.kind] = int(count[t.kind]) + 1
	var n := towers.size()
	var ideal := {"archer": 0.36, "bombard": 0.22, "spire": 0.20, "guard": 0.22}
	var air := 0
	var armor := 0
	var swarm := 0
	for ty in leak_types:
		var cat: String = String(Defs.MON[ty].get("cat", ""))
		if cat == "air":
			air += int(leak_types[ty])
		elif cat == "armor":
			armor += int(leak_types[ty])
		elif cat == "swarm":
			swarm += int(leak_types[ty])
	var gate_press: float = clampf(float(leaks) / 8.0, 0.0, 1.0)
	# 先升级已有塔（钱多的时候）
	if n >= 3 and gold > 200:
		for t in towers:
			if is_instance_valid(t) and t.alive and t.can_upgrade() and gold >= t.upgrade_cost():
				upgrade_tower(t, true)
				return
	if empty.is_empty():
		return
	var best_score := -1e9
	var best_kind := ""
	var best_pad: Dictionary = {}
	for kind in Defs.TOWER_KINDS:
		var d: Dictionary = Defs.TOWER[kind]
		var need: float = float(ideal[kind]) * (float(n) + 1.6) - float(count[kind]) + 0.35
		if kind == "archer":
			need += float(air) * 0.2 + (1.0 if n == 0 else 0.0)
		if kind == "spire":
			need += float(air) * 0.12 + float(armor) * 0.1
		if kind == "bombard":
			need += float(armor) * 0.08 + float(swarm) * 0.06 + (0.5 if (n >= 2 and int(count["bombard"]) == 0) else 0.0)
		if kind == "guard":
			need += float(swarm) * 0.04 + (0.9 if (n >= 1 and int(count["guard"]) == 0) else 0.0)
		if need <= 0.0:
			continue
		if gold < int(d["cost"][0]):
			continue
		for p in empty:
			var cov: float = world.coverage(p, float(d["range"][0])) / (float(d["range"][0]) * 2.0)
			var score: float = need * (0.55 + cov * 0.5)
			var rel: float = world.pad_rel(p)
			if n < 2:
				score *= 1.0 - absf(rel - 0.42) * 0.9
			score *= 1.0 + gate_press * (rel - 0.5) * 0.8
			if score > best_score:
				best_score = score
				best_kind = kind
				best_pad = p
	if best_kind != "" and not best_pad.is_empty():
		build_tower(best_pad, best_kind, true)

func toggle_ai() -> void:
	ai_active = not ai_active
	hud.toast("指挥权交给 %s" % ("AI" if ai_active else "你"))

# ---------------------------------------------------------------- 相机

func _update_camera(dt: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move.length_squared() > 0.0:
		follow = false
		camera_target += move.normalized() * dt * 12.0 * (camera_size / 30.0)
	camera_target.x = clampf(camera_target.x, -18.0, 18.0)
	camera_target.z = clampf(camera_target.z, -18.0, 18.0)
	if follow and not monsters.is_empty():
		var lead = null
		var best := -1.0
		for m in monsters:
			if is_instance_valid(m) and m.alive and m.progress() > best:
				best = m.progress()
				lead = m
		if lead != null:
			camera_target = camera_target.lerp(Vector3(lead.position.x, 0, lead.position.z), minf(1.0, dt * 0.8))
	if Input.is_key_pressed(KEY_LEFT):
		camera_target.x -= dt * 14.0
	if Input.is_key_pressed(KEY_RIGHT):
		camera_target.x += dt * 14.0
	if Input.is_key_pressed(KEY_UP):
		camera_target.z -= dt * 14.0
	if Input.is_key_pressed(KEY_DOWN):
		camera_target.z += dt * 14.0
	camera.size = lerpf(camera.size, camera_size, minf(1.0, dt * 6.0))
	camera.position = camera_target + Vector3(1.0, 1.15, 1.0).normalized() * 60.0
	camera.look_at(camera_target, Vector3.UP)

func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	var hit = screen_to_ground(mp)
	hovered_pad = {}
	hovered_tower = null
	if hit == null:
		return
	for p in world.pads:
		if Vector2(hit.x - float(p["x"]), hit.z - float(p["z"])).length() < 1.25:
			hovered_pad = p
			break
	for t in towers:
		if is_instance_valid(t) and t.alive:
			if Vector2(hit.x - t.position.x, hit.z - t.position.z).length() < 1.2:
				hovered_tower = t
				break
	# 没选中任何东西时，悬停也给一圈淡预览
	if range_fx != null and selected_pad.is_empty() and selected_tower == null:
		if hovered_tower != null and is_instance_valid(hovered_tower):
			_show_tower_range(hovered_tower, 0.5)
		elif not hovered_pad.is_empty() and not hovered_pad.has("tower"):
			_show_pad_range(hovered_pad, preview_kind, 0.5)
		else:
			hide_range()
	# 空格子给一点光
	for p in world.pads:
		if p.has("glow"):
			var g = p["glow"]
			var want: bool = (p == hovered_pad and not p.has("tower"))
			if g.visible != want:
				g.visible = want

func screen_to_ground(screen: Vector2) -> Variant:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return null
	var ndc := Vector2((screen.x / vp.x) * 2.0 - 1.0, 1.0 - (screen.y / vp.y) * 2.0)
	var basis := camera.global_transform.basis
	var size_v := camera.size
	var aspect := vp.x / vp.y
	var origin: Vector3 = camera.global_position + basis.x * (ndc.x * size_v * aspect * 0.5) + basis.y * (ndc.y * size_v * 0.5)
	var dir: Vector3 = -basis.z
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t <= 0.0:
		return null
	return origin + dir * t

# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_size = clampf(camera_size * 0.9, 8.0, 44.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_size = clampf(camera_size * 1.1, 8.0, 44.0)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_on_click(mb.position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				pass
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			var hit = screen_to_ground(mb.position)
			if hit != null:
				camera_target = Vector3(hit.x, 0, hit.z)
				camera_size = clampf(camera_size * 0.6, 8.0, 44.0)
				follow = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT or mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var scale_f := camera_size / 600.0
			camera_target.x -= mm.relative.x * scale_f
			camera_target.z -= mm.relative.y * scale_f * 1.4
			follow = false
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_1:
				if not selected_pad.is_empty():
					build_tower(selected_pad, "archer")
			KEY_2:
				if not selected_pad.is_empty():
					build_tower(selected_pad, "bombard")
			KEY_3:
				if not selected_pad.is_empty():
					build_tower(selected_pad, "spire")
			KEY_4:
				if not selected_pad.is_empty():
					build_tower(selected_pad, "guard")
			KEY_U:
				if selected_tower != null:
					upgrade_tower(selected_tower)
			KEY_X:
				if selected_tower != null:
					sell_tower(selected_tower)
			KEY_SPACE:
				call_wave_early()
			KEY_C:
				toggle_ai()
			KEY_P:
				paused = not paused
				hud.toast("暂停" if paused else "继续")
			KEY_TAB:
				speed = 1 if speed == 3 else speed + 1
				hud.toast("速度 %dx" % speed)
			KEY_EQUAL:
				camera_size = clampf(camera_size * 0.9, 8.0, 44.0)
			KEY_MINUS:
				camera_size = clampf(camera_size * 1.1, 8.0, 44.0)
			KEY_F, KEY_0:
				follow = !follow
				hud.toast("镜头跟随 %s" % ("开" if follow else "关"))
			KEY_R:
				if phase == "defeat":
					get_tree().reload_current_scene()
			KEY_ESCAPE:
				selected_pad = {}
				selected_tower = null
				hud.close_menus()

func _on_click(screen: Vector2) -> void:
	var hit = screen_to_ground(screen)
	if hit == null:
		return
	for p in world.pads:
		if Vector2(hit.x - float(p["x"]), hit.z - float(p["z"])).length() < 1.3:
			selected_tower = null
			if p.has("tower"):
				selected_pad = {}
				selected_tower = p["tower"]
				hud.open_tower(p["tower"])
				_show_tower_range(p["tower"], 1.0)
			else:
				selected_pad = p
				hud.open_build(p)
				preview_build(preview_kind)
			return
	for t in towers:
		if is_instance_valid(t) and t.alive:
			if Vector2(hit.x - t.position.x, hit.z - t.position.z).length() < 1.3:
				selected_pad = {}
				selected_tower = t
				hud.open_tower(t)
				_show_tower_range(t, 1.0)
				return
	selected_pad = {}
	selected_tower = null
	hud.close_menus()
	hide_range()

# ---------------------------------------------------------------- 辅助

func tower_counts() -> Dictionary:
	var c := {"archer": 0, "bombard": 0, "spire": 0, "guard": 0}
	for t in towers:
		if is_instance_valid(t) and t.alive:
			c[t.kind] = int(c[t.kind]) + 1
	return c

func next_wave_in() -> float:
	return next_in

func wave_label() -> String:
	if spawning or boss_wave:
		return "第 %d 波进行中" % wave_no
	if phase == "clear":
		return "换场中"
	if phase == "defeat":
		return "信标已灭"
	return "第 %d 波 · 还有 %.1f 秒" % [wave_no, maxf(0.0, next_in)]
