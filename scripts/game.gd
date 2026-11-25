extends Node3D
## Cinderwatch — Master Godot 4.4 Forward Plus Game Controller (ported & enhanced from 62-game.js & 90-main.js).
## Orchestrates:
## - WorldEnvironment (ACES, SSAO, SSIL, HDR Glow/Bloom) + world-space fire-lit valley mist quad
## - 5 Full Biomes (Ashen Vale, Frostfall, Mirefen, Emberscar, Duskmesa) with 6x6 chunked Crumble & Rise stage transitions
## - All 20 monsters + 6 bosses with every special ability, shatter debris, bouncing coins, and slow-mo boss death
## - All 4x3 towers with scaffolding build animations, flaming arrows, recoiling bombard, chain-lightning spire, and rallying footmen
## - Smart AI Commander + full manual mouse/keyboard/gamepad control + Camera Director + Procedural Audio + Persistence

const U = preload("res://scripts/util.gd")
const DevShotScript = preload("res://scripts/devshot.gd")
const TX = preload("res://scripts/textures.gd")
const Defs = preload("res://scripts/defs.gd")
const WorldScript = preload("res://scripts/world.gd")
const FXScript = preload("res://scripts/fx.gd")
const WeatherScript = preload("res://scripts/weather.gd")
const MonsterScript = preload("res://scripts/monster.gd")
const TowerScript = preload("res://scripts/tower.gd")
const RangeScript = preload("res://scripts/range_fx.gd")
const AudioScript = preload("res://scripts/audio.gd")
const PostScript = preload("res://scripts/post.gd")
const HUDScript = preload("res://scripts/hud.gd")

const CFG_PATH := "user://cinderwatch.cfg"
const SAVE_PATH := "user://savegame.json"
const MAX_LIVES := 20
const START_GOLD := 650
const LEVEL_GOLD_BONUS := 300

# Core subsystems
var world_env: WorldEnvironment
var cam: Camera3D
var mist_mat: ShaderMaterial
var world: Node3D
var fx: Node3D
var weather: Node3D
var rigs: Node3D
var range_fx: Node3D
var hover_fx: Node3D
var audio: Node
var post: CanvasLayer
var hud: CanvasLayer

# Game state
var state := "play" # "play" | "clear" | "crumble" | "rise" | "defeat"
var state_t := 0.0
var sim_time := 0.0
var real_time := 0.0
var fade_v := 0.0
var level_num := 1
var biome_idx := 0
var next_biome_idx := 1
var seed_override := -1
var _args_fresh := false
var _demo_t := -1.0
var _demo_kind := ""
var _zap_test := -1.0

var lives := MAX_LIVES
var gold := START_GOLD
var slain := 0
var wave := 0
var best_wave := 0
var press := 1.0
var _saved_muted := false
var _saved_volume := 1.0

# Wave spawner
var wave_queue: Array[Dictionary] = []
var wave_timer := 3.5
var wave_wait_max := 6.0
var wave_active := false
var boss_trickle_t := 0.0
var seen_mobs: Dictionary = {}

# Active entities
var towers: Array[Node3D] = []
var monsters: Array[Dictionary] = []
var footmen: Array[Dictionary] = []
var arrows: Array[Dictionary] = []
var stuck_arrows: Array[Dictionary] = []
var shells: Array[Dictionary] = []
var beacon_flame: Dictionary = {}
var beacon_power := 1.0
var env_flames: Array[Dictionary] = []
var wf_spray_t := 0.0

# Controls & AI Commander
var ai_mode := true
var ai_timer := 1.2
var paused := false
var speed_idx := 0
const SPEEDS := [1.0, 2.0, 3.0]
var selected_pad := -1
var hovered_pad := -1
var hover_build_kind := ""

# Camera Director
var cam_target := Vector3(0.0, 0.5, 0.0)
var cam_goal := Vector3(0.0, 0.5, 0.0)
var cam_yaw := -PI * 0.25
var cam_elev := 0.64
var cam_dist := 34.0
var cam_dist_goal := 34.0
var manual_cam := false
var _dragging := false
var _drag_moved := false
var _drag_start := Vector2.ZERO
var _last_click_t := 0.0
var _focus_pos := Vector3.ZERO
var _focus_timer := 0.0

# Transition tracking
var _crumble_towers: Array[Node3D] = []
var _is_defeat_reset := false
var _rng: U.Rng = U.make_rng(2026)


func _ready() -> void:
	TX.ensure()
	_load_config()
	_parse_cli_args()
	_setup_environment_and_camera()
	_setup_subsystems()
	_start_level(level_num, biome_idx, seed_override, true)
	if not _args_fresh:
		_try_resume()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		best_wave = int(cfg.get_value("run", "best_wave", 0))
		_saved_muted = bool(cfg.get_value("audio", "muted", false))
		_saved_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_wave", best_wave)
	cfg.set_value("audio", "muted", audio.muted if audio != null else false)
	cfg.set_value("audio", "master_volume", audio.master_volume if audio != null else 1.0)
	cfg.save(CFG_PATH)


func _save_game(quiet: bool = false) -> void:
	var tw_list: Array = []
	for t in towers:
		if is_instance_valid(t):
			tw_list.append({"pad": int(t.pad_idx), "kind": String(t.kind), "lvl": int(t.level)})
	var data := {
		"version": 1,
		"stamp": Time.get_datetime_string_from_system(false, true),
		"level": level_num,
		"biome": biome_idx,
		"wave": wave,
		"gold": gold,
		"lives": lives,
		"slain": slain,
		"best_wave": best_wave,
		"towers": tw_list,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	print("[save] wrote ", SAVE_PATH, " level=", level_num, " wave=", wave, " towers=", tw_list.size())
	if not quiet and hud != null:
		hud.show_banner("GAME SAVED", "Stage %d  •  Wave %d  •  %dg" % [level_num, wave, gold], Color(0.62, 0.90, 0.62), 1.8)


func _load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


func _try_resume() -> bool:
	var d := _load_save()
	if d.is_empty():
		return false
	var lv := maxi(1, int(d.get("level", 1)))
	var bio := int(d.get("biome", 0))
	_start_level(lv, bio, seed_override, true)
	gold = int(d.get("gold", gold))
	lives = clampi(int(d.get("lives", lives)), 1, MAX_LIVES)
	slain = int(d.get("slain", 0))
	wave = maxi(0, int(d.get("wave", 0)))
	best_wave = maxi(best_wave, int(d.get("best_wave", 0)))
	wave_active = false
	wave_timer = 5.0
	wave_wait_max = 5.0

	var list: Array = d.get("towers", [])
	var restored := 0
	for e in list:
		if not (e is Dictionary):
			continue
		var pi := int(e.get("pad", -1))
		if pi < 0 or pi >= world.pads.size():
			continue
		var pd: Dictionary = world.pads[pi]
		if bool(pd["occupied"]):
			continue
		var tw: Node3D = TowerScript.new()
		tw.name = "tower_%d" % pi
		add_child(tw)
		var pos := Vector3(float(pd["x"]), float(pd["y"]) + 0.24, float(pd["z"]))
		tw.restore(pi, String(e.get("kind", "archer")), int(e.get("lvl", 0)), pos, level_num * 97 + pi * 31, fx, audio)
		pd["occupied"] = true
		pd["tower"] = tw
		towers.append(tw)
		if String(tw.kind) == "guard":
			_sync_guard_footmen(tw)
		restored += 1

	print("[save] loaded level=", level_num, " wave=", wave, " towers=", restored)
	hud.set_best_wave(best_wave)
	hud.show_banner("SAVE LOADED", "Stage %d  •  Wave %d  •  %d towers restored" % [level_num, wave, restored], Color(0.62, 0.86, 1.0), 2.4)
	return true


func _on_restart() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.json"):
		dir.remove("savegame.json")
	_start_level(1, 0, seed_override, true)
	_save_game(true)
	hud.show_banner("NEW RUN", "Stage 1  •  %dg  •  Fresh start" % gold, Color(0.95, 0.85, 0.55), 2.2)


func _on_save_cmd() -> void:
	_save_game(false)


func _on_quit(save_first: bool) -> void:
	if save_first:
		_save_game(true)
	_save_config()
	get_tree().quit()


func _parse_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seed="):
			seed_override = int(a.substr(7))
		elif a.begins_with("--level="):
			level_num = maxi(1, int(a.substr(8)))
		elif a == "--fresh":
			_args_fresh = true
		elif a == "--demo=build":
			_demo_t = 2.2
			_demo_kind = "build"
		elif a == "--demo=quit":
			_demo_t = 2.2
			_demo_kind = "quit"
		elif a == "--demo=restart":
			_demo_t = 2.2
			_demo_kind = "restart"
		elif a == "--zap-test":
			_zap_test = 1.5
		elif a == "--demo=restart-run":
			_demo_t = 3.0
			_demo_kind = "restart-run"


func _setup_environment_and_camera() -> void:
	# High-fidelity Forward Plus Environment (ACES + SSAO + SSIL + HDR Glow)
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.04, 0.055, 0.095)
	sm.sky_horizon_color = Color(0.11, 0.13, 0.20)
	sm.ground_bottom_color = Color(0.015, 0.018, 0.03)
	sm.ground_horizon_color = Color(0.06, 0.075, 0.12)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.56, 0.78)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.12
	env.ssao_enabled = true
	env.ssao_radius = 1.25
	env.ssao_intensity = 1.45
	env.ssil_enabled = true
	env.ssil_radius = 3.5
	env.ssil_intensity = 0.65
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 0.92
	env.glow_bloom = 0.24
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	add_child(world_env)

	# Isometric-perspective Diorama Camera
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 34.0
	cam.near = 0.5
	cam.far = 220.0
	cam.current = true
	add_child(cam)

	# World-space fire-lit valley mist fullscreen spatial quad attached to Camera3D
	mist_mat = ShaderMaterial.new()
	mist_mat.shader = load("res://shaders/mist.gdshader")
	var mq := MeshInstance3D.new()
	mq.name = "valley_mist_quad"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	mq.mesh = qm
	mq.material_override = mist_mat
	mq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mq.extra_cull_margin = 16384.0
	cam.add_child(mq)


func _setup_subsystems() -> void:
	world = WorldScript.new()
	world.name = "World"
	add_child(world)

	# Apply CLI --biome= if provided
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--biome="):
			biome_idx = world.get_biome_by_key(a.substr(8))

	# 调试截图：--shot=<绝对路径>:<帧数>
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var spec := a.substr(7)
			var parts := spec.split(":")
			var shot := DevShotScript.new()
			shot.out_path = parts[0]
			if parts.size() > 1:
				shot.frames = int(parts[1])
			add_child(shot)

	fx = FXScript.new()
	fx.name = "FX"
	fx.cam_ref = cam
	add_child(fx)

	weather = WeatherScript.new()
	weather.name = "Weather"
	add_child(weather)

	rigs = MonsterScript.new()
	rigs.name = "MonsterRigs"
	add_child(rigs)

	range_fx = RangeScript.new()
	range_fx.name = "RangeFX"
	range_fx.set_height_fn(Callable(world, "height_at"))
	add_child(range_fx)

	hover_fx = RangeScript.new()
	hover_fx.name = "HoverFX"
	hover_fx.set_height_fn(Callable(world, "height_at"))
	add_child(hover_fx)

	audio = AudioScript.new()
	audio.name = "Audio"
	add_child(audio)
	audio.set_master_volume(_saved_volume)
	audio.set_muted(_saved_muted)

	post = PostScript.new()
	post.name = "Post"
	add_child(post)

	hud = HUDScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_best_wave(best_wave)
	hud.sync_audio_controls(audio.master_volume, audio.muted)
	hud.cmd_toggle_ai.connect(_on_toggle_ai)
	hud.cmd_call_wave.connect(_on_call_wave)
	hud.cmd_toggle_pause.connect(_on_toggle_pause)
	hud.cmd_cycle_speed.connect(_on_cycle_speed)
	hud.cmd_toggle_mute.connect(_on_toggle_mute)
	hud.cmd_volume_changed.connect(_on_volume_changed)
	hud.cmd_switch_biome.connect(_on_switch_biome)
	hud.cmd_zoom.connect(_on_zoom_cmd)
	hud.cmd_follow_cam.connect(_on_follow_cam)
	hud.cmd_build.connect(_on_build_cmd)
	hud.cmd_hover_build.connect(_on_hover_build)
	hud.cmd_upgrade.connect(_on_upgrade_cmd)
	hud.cmd_sell.connect(_on_sell_cmd)
	hud.cmd_save.connect(_on_save_cmd)
	hud.cmd_restart.connect(_on_restart)
	hud.cmd_quit.connect(_on_quit)
	hud.cmd_close_menu.connect(func() -> void:
		selected_pad = -1
		hover_build_kind = ""
		range_fx.hide_range()
	)

	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		audio.set_muted(bool(cfg.get_value("audio", "muted", false)))


# ============================================================================
# Level Lifecycle, Crumble & Rise Transitions
# ============================================================================

func _clear_entities() -> void:
	for tw in towers:
		if is_instance_valid(tw):
			tw.clear_visuals(fx)
			tw.queue_free()
	towers.clear()
	_crumble_towers.clear()
	monsters.clear()
	footmen.clear()
	arrows.clear()
	stuck_arrows.clear()
	shells.clear()
	wave_queue.clear()
	env_flames.clear()
	beacon_flame = {}
	fx.clear_fx()
	rigs.clear_pools()
	selected_pad = -1
	hover_build_kind = ""
	range_fx.hide_range()
	hover_fx.hide_range()
	hud.close_menus()


func _start_level(p_level: int, p_biome: int, p_seed: int, instant_appear: bool) -> void:
	_clear_entities()
	level_num = p_level
	biome_idx = posmod(p_biome, world.get_biome_count())
	world.build_level(level_num, biome_idx, p_seed)
	world.apply_biome_look(0.0, true, world_env, fx, mist_mat, weather, post, fade_v)

	# Register beacon, keep sconces, road lanterns, and lava vent flames
	beacon_power = 1.0 if instant_appear else 0.0
	var bp: Vector3 = world.beacon_flame_pos
	beacon_flame = fx.add_flame(bp.x, bp.y, bp.z, 1.38, {"tint": Color(1.0, 0.88, 0.62), "smoke": 0.9, "ember": 0.9, "halo": 0.62})
	beacon_flame["power"] = beacon_power
	for sp in world.sconce_positions:
		var sf: Dictionary = fx.add_flame(sp.x, sp.y, sp.z, 0.44, {"smoke": 0.25, "ember": 0.2, "halo": 0.35})
		sf["power"] = beacon_power
		env_flames.append(sf)
	for lp in world.lantern_positions:
		var lf: Dictionary = fx.add_flame(lp.x, lp.y, lp.z, 0.32, {"smoke": 0.08, "ember": 0.12, "halo": 0.40})
		lf["power"] = beacon_power
		env_flames.append(lf)
	for lv in world.lava_vents:
		var vf: Dictionary = fx.add_flame(lv.x, lv.y, lv.z, 0.72, {"tint": Color(1.0, 0.45, 0.12), "smoke": 0.65, "ember": 0.85, "halo": 0.48})
		vf["power"] = beacon_power
		env_flames.append(vf)

	# Starting economy scales gently with level
	if _is_defeat_reset or level_num == 1:
		lives = MAX_LIVES
		gold = START_GOLD
		slain = 0
		wave = 0
		press = 1.0
		_is_defeat_reset = false
	else:
		lives = mini(MAX_LIVES, lives + 6)
		gold += LEVEL_GOLD_BONUS

	wave_active = false
	wave_timer = 3.6
	wave_wait_max = 3.6
	ai_timer = 0.6

	if instant_appear:
		state = "play"
		state_t = 0.0
		hud.show_banner(String(world.biome["title"]).to_upper(), "Stage %d  •  Defend the Cinderwatch Beacon" % level_num, Color(1.0, 0.84, 0.48), 3.0)
	else:
		# Place all 36 chunks below and landmarks above for dramatic Rise transition
		state = "rise"
		state_t = 0.0
		for pc in world.pieces:
			var nd: Node3D = pc["node"]
			var base_p: Vector3 = pc["base"]
			var kind: String = String(pc["kind"])
			if kind == "chunk":
				nd.position = base_p + Vector3(0.0, -28.0, 0.0)
			else:
				nd.position = base_p + Vector3(0.0, 18.0, 0.0)
		audio.play_sfx("rise", 0.0, 0.95)


func _begin_crumble(target_biome: int, defeat_reset: bool = false) -> void:
	if state == "crumble" or state == "rise":
		return
	state = "crumble"
	state_t = 0.0
	next_biome_idx = posmod(target_biome, world.get_biome_count())
	_is_defeat_reset = defeat_reset
	hud.close_menus()
	range_fx.hide_range()
	hover_fx.hide_range()

	# Reparent active towers onto their underlying terrain chunks so they tumble into the abyss together!
	_crumble_towers.clear()
	for tw in towers:
		if not is_instance_valid(tw):
			continue
		var ci: int = world.chunk_index_at(tw.global_position.x, tw.global_position.z)
		if ci >= 0 and ci < world.chunk_nodes.size():
			var ch: Node3D = world.chunk_nodes[ci]
			var world_xf := tw.global_transform
			tw.get_parent().remove_child(tw)
			ch.add_child(tw)
			tw.global_transform = world_xf
			_crumble_towers.append(tw)

	fx.add_shake(0.65)
	audio.play_sfx("crumble", 0.0, 1.0)


func _update_transitions(dt: float) -> void:
	state_t += dt
	if state == "clear":
		if state_t >= 2.2:
			_begin_crumble(biome_idx + 1, false)
	elif state == "defeat":
		beacon_power = maxf(0.0, beacon_power - dt * 1.4)
		beacon_flame["power"] = beacon_power
		for ef in env_flames:
			ef["power"] = beacon_power
		for tw in towers:
			if is_instance_valid(tw):
				for fh in tw.flame_handles:
					fh["power"] = beacon_power
		if state_t >= 2.6:
			_begin_crumble(0, true)
	elif state == "crumble":
		var dur := 2.4
		for pc in world.pieces:
			var nd: Node3D = pc["node"]
			var base_p: Vector3 = pc["base"]
			var dly: float = float(pc["delay"])
			var spn: Vector3 = pc["spin"]
			var t_loc := state_t - dly
			if t_loc < 0.0:
				# Pre-fall seismic jitter
				var j := clampf(state_t / maxf(0.08, dly), 0.0, 1.0) * 0.12
				nd.position = base_p + Vector3((randf() - 0.5) * j, (randf() - 0.5) * j, (randf() - 0.5) * j)
			else:
				var fall_y := 16.5 * t_loc * t_loc
				nd.position = base_p + Vector3(0.0, -fall_y, 0.0)
				nd.rotation = spn * t_loc * 0.85
				if t_loc < 0.14 and randf() < 0.35:
					fx.fx_dust(base_p.x, base_p.y, base_p.z, 2, 1.5, 0x6a6056)
		if beacon_flame.has("power"):
			beacon_flame["power"] = maxf(0.0, 1.0 - state_t * 1.6)
		for ef in env_flames:
			ef["power"] = maxf(0.0, 1.0 - state_t * 1.6)
		if state_t >= dur:
			var next_lvl := 1 if _is_defeat_reset else level_num + 1
			_start_level(next_lvl, next_biome_idx, -1, false)
	elif state == "rise":
		var dur := 1.95
		var all_settled := true
		for pc in world.pieces:
			var nd: Node3D = pc["node"]
			var base_p: Vector3 = pc["base"]
			var dly: float = float(pc["delay"])
			var kind: String = String(pc["kind"])
			var t_loc := state_t - dly * 0.7
			if t_loc < 0.0:
				all_settled = false
				continue
			var u := clampf(t_loc / 0.85, 0.0, 1.0)
			if u < 1.0:
				all_settled = false
			if kind == "chunk":
				var y_off := (1.0 - U.ease_out_back(u)) * -28.0
				nd.position = base_p + Vector3(0.0, y_off, 0.0)
				nd.rotation = Vector3.ZERO
			else:
				var y_off := (1.0 - U.ease_out(u)) * 18.0
				nd.position = base_p + Vector3(0.0, y_off, 0.0)
				nd.rotation = Vector3(0.0, nd.rotation.y, 0.0)

		if state_t >= dur or all_settled:
			for pc in world.pieces:
				var nd: Node3D = pc["node"]
				nd.position = pc["base"]
				if String(pc["kind"]) == "chunk":
					nd.rotation = Vector3.ZERO
			# Dramatic Beacon Ignition Burst!
			beacon_power = 1.0
			beacon_flame["power"] = 1.0
			for ef in env_flames:
				ef["power"] = 1.0
			var bp: Vector3 = world.beacon_flame_pos
			fx.add_flash(bp.x, bp.y + 1.2, bp.z, 0xffaa44, 18.0, 0.85, 36.0)
			fx.fx_embers(bp.x, bp.y, bp.z, 28, 1.4, 5.2, 0xff8028)
			fx.fx_sparks(bp.x, bp.y, bp.z, 22, 6.2, 0xffe088, 1.4)
			fx.add_shake(0.35)
			audio.play_sfx("ignite", 0.0, 1.0)
			state = "play"
			state_t = 0.0
			hud.show_banner(String(world.biome["title"]).to_upper(), "Stage %d  •  The Beacon Burns Anew" % level_num, Color(1.0, 0.84, 0.48), 3.0)


# ============================================================================
# Main Frame Update
# ============================================================================

func _process(delta: float) -> void:
	if _zap_test > 0.0:
		_zap_test -= delta
		if _zap_test <= 0.0:
			_run_zap_test()

	if _demo_t > 0.0:
		_demo_t -= delta
		if _demo_t <= 0.0:
			if _demo_kind == "quit":
				hud.open_quit_panel()
			elif _demo_kind == "restart":
				hud.open_restart_panel()
			elif _demo_kind == "restart-run":
				_on_restart()
			else:
				_demo_open_build()

	var dt := minf(delta, 0.05)
	real_time += dt
	fade_v = minf(1.0, fade_v + dt * 1.4)

	var spd := 0.0 if paused else float(SPEEDS[speed_idx])
	var sim_dt := dt * spd
	sim_time += sim_dt
	TX.set_time(sim_time)

	# 1. Stage Transitions vs Active Gameplay Simulation
	if state != "play":
		_update_transitions(dt)
		for tw in _crumble_towers:
			if is_instance_valid(tw):
				tw.update_visuals(dt, sim_time, fx, audio)
	elif not paused:
		_step_waves(sim_dt)
		_step_ai_commander(sim_dt)
		_step_towers(sim_dt)
		_step_footmen(sim_dt)
		_step_monsters(sim_dt)
		_step_projectiles(sim_dt)
		_step_waterfall_spray(sim_dt)

	# 2. Render GPU-instanced PartBatch Rigs & FX
	fx.begin_frame(sim_time)
	rigs.begin_frame()
	_emit_all_rigs_and_visuals(sim_dt)
	rigs.update_and_emit_pools(sim_dt if not paused else 0.0, sim_time, Callable(world, "height_at"), fx)
	rigs.end_frame()

	var w_spd := float(world.biome.get("wind", 1.0))
	fx.update_fx(sim_dt if not paused else dt * 0.25, sim_time, Vector3(0.55 * w_spd, 0.0, 0.28 * w_spd))
	fx.end_frame()

	# 3. Dynamic Lighting, Valley Mist, Weather, Biome Grading & Audio
	_update_lights_weather_audio(dt)

	# 4. Camera Director & HUD Overlay
	_update_camera(dt)
	_update_hud(dt)


# ============================================================================
# Waves & Spawning (matching 62-game.js ROSTER + Biome Weights + Boss Waves)
# ============================================================================

func _step_waves(dt: float) -> void:
	if not wave_active:
		wave_timer -= dt
		if wave_timer <= 0.0:
			_start_next_wave()
	else:
		var i := wave_queue.size() - 1
		while i >= 0:
			wave_queue[i]["delay"] = float(wave_queue[i]["delay"]) - dt
			if float(wave_queue[i]["delay"]) <= 0.0:
				var entry: Dictionary = wave_queue[i]
				wave_queue.remove_at(i)
				_spawn_monster(String(entry["kind"]), float(entry.get("lane", 0.0)))
			i -= 1

		# Boss wave trickle reinforcements
		if (wave % 5) == 0 and _has_living_boss():
			boss_trickle_t -= dt
			if boss_trickle_t <= 0.0:
				boss_trickle_t = 3.2
				_spawn_monster(_pick_biome_mob(wave), randf_range(-0.65, 0.65))

		# Check wave clear
		if wave_queue.is_empty() and monsters.is_empty():
			wave_active = false
			var clear_bonus := 22 + wave * 6
			gold += clear_bonus
			if wave > best_wave:
				best_wave = wave
				hud.set_best_wave(best_wave)
				_save_config()
			_save_game(true)

			# Every 5th wave (Boss Wave) clears the realm and advances to the next Biome!
			if (wave % 5) == 0 and wave > 0:
				state = "clear"
				state_t = 0.0
				hud.show_banner("REALM CLEARED!", "The Beacon Endures  •  +%dg Bonus" % clear_bonus, Color(0.98, 0.86, 0.45), 2.4)
				audio.play_sfx("ignite", 0.0, 0.85)
			else:
				wave_wait_max = 6.5
				wave_timer = wave_wait_max


func _start_next_wave() -> void:
	wave += 1
	if OS.get_cmdline_user_args().has("--zap-log"):
		print("[wave] start ", wave, " monsters=", monsters.size(), " towers=", towers.size())

	wave_active = true
	wave_queue.clear()
	var is_boss := (wave % 5) == 0
	var b: Dictionary = world.biome

	if is_boss:
		var b_list: Array = b.get("boss", ["ogre", "giant"])
		var b_kind: String = String(b_list[(wave / 5 - 1) % b_list.size()])
		wave_queue.append({"kind": b_kind, "delay": 0.4, "lane": 0.0})
		# Escort squad around the boss
		var escort_n := 5 + wave
		for i in escort_n:
			wave_queue.append({"kind": _pick_biome_mob(wave), "delay": 1.1 + float(i) * 0.55, "lane": randf_range(-0.68, 0.68)})
		boss_trickle_t = 4.5
		var bd: Dictionary = Defs.MONSTERS[b_kind]
		hud.show_banner("BOSS WAVE %d" % wave, String(bd["name"]) + " Approaches!", Color(1.0, 0.36, 0.24), 3.4)
		audio.play_sfx("hornBoss", 0.0, 1.0)
	else:
		var total_count := int(round((8.0 + float(wave) * 2.6) * clampf(press, 0.85, 1.35)))
		var spacing := maxf(0.28, 0.82 - float(wave) * 0.025)
		for i in total_count:
			wave_queue.append({
				"kind": _pick_biome_mob(wave),
				"delay": 0.25 + float(i) * spacing + randf() * 0.18,
				"lane": randf_range(-0.68, 0.68),
			})
		hud.show_banner("WAVE %d" % wave, "%d Foes Emerging from the Dark" % total_count, Color(1.0, 0.82, 0.46), 2.2)
		audio.play_sfx("horn", 0.0, 0.85)


func _pick_biome_mob(w: int) -> String:
	var b: Dictionary = world.biome
	var mob_w: Dictionary = b.get("mobs", {})
	var early: Dictionary = b.get("early", {})
	var pool: Array = []
	var sum_w := 0.0
	for kind in Defs.ROSTER.keys():
		var k: String = String(kind)
		var row: Array = Defs.ROSTER[kind]
		var min_w: int = int(early.get(k, int(row[4])))
		if w < min_w:
			continue
		var wt: float = float(row[5]) * float(mob_w.get(k, 1.0))
		if wt <= 0.01:
			continue
		pool.append([k, wt])
		sum_w += wt
	if pool.is_empty():
		return "skeleton"
	var pick := randf() * sum_w
	for p in pool:
		pick -= float(p[1])
		if pick <= 0.0:
			return String(p[0])
	return String(pool[0][0])


func _spawn_monster(kind: String, lane: float, dist_along: float = 0.0) -> Dictionary:
	var d: Dictionary = Defs.MONSTERS.get(kind, Defs.MONSTERS["skel"])
	var is_boss := bool(d.get("boss", false))
	var hp_scale := pow(1.13, float(maxi(0, wave - 1))) * (1.0 + float(level_num - 1) * 0.18)
	var max_hp := float(d["hp"]) * hp_scale
	var samp: Dictionary = world.sample_path(dist_along)
	var p: Vector3 = samp["pos"]
	var dir: Vector3 = samp["dir"]
	var side := Vector3(-dir.z, 0.0, dir.x)
	var fly_h := float(d.get("fly", 0.0))
	var spawn_p := p + side * lane + Vector3(0.0, fly_h, 0.0)

	var tints: Dictionary = world.biome.get("tints", {})
	var base_tint: Color = tints.get(kind, Color.WHITE)
	if kind == "wisp":
		base_tint = world.biome.get("wisp_col", Color(0.55, 0.9, 1.0))

	var m := {
		"kind": kind,
		"name": String(d["name"]),
		"boss": is_boss,
		"hp": max_hp,
		"max_hp": max_hp,
		"spd": float(d["spd"]),
		"armor": float(d.get("armor", 0.0)),
		"gold": int(d.get("bounty", d.get("gold", 0))),
		"scale": float(d["scale"]),
		"fly": fly_h,
		"dmg": float(d.get("dmg", 14.0)),
		"lives": int(d.get("lives", 5 if is_boss else 1)),
		"dist": dist_along,
		"lane": lane,
		"pos": spawn_p,
		"yaw": atan2(dir.x, dir.z),
		"phase": randf() * TAU,
		"flash": 0.0,
		"slow_t": 0.0,
		"haste_t": 0.0,
		"atk_t": 0.0,
		"atk_cd": 0.0,
		"spec_cd": 2.4 + randf() * 2.0,
		"step_t": 0.0,
		"phasing": false,
		"dying": false,
		"die_t": 0.0,
		"engaged": null,
		"tint": base_tint,
		"eye_col": Color(1.0, 0.35, 0.14) if not is_boss else Color(1.0, 0.85, 0.25),
	}
	monsters.append(m)

	# First-seen monster tip toast
	if not seen_mobs.has(kind):
		seen_mobs[kind] = true
		hud.show_tip(String(d["name"]), String(d.get("tip", "")), is_boss)
	return m


func _has_living_boss() -> bool:
	for m in monsters:
		if bool(m["boss"]) and not bool(m["dying"]):
			return true
	return false


# ============================================================================
# AI Commander (Smart Auto-Play)
# ============================================================================

func _step_ai_commander(dt: float) -> void:
	if not ai_mode:
		return
	ai_timer -= dt
	if ai_timer > 0.0:
		return
	ai_timer = 0.85

	# Count existing tower kinds
	var counts := {"archer": 0, "bombard": 0, "spire": 0, "guard": 0}
	for tw in towers:
		counts[String(tw.kind)] = int(counts[String(tw.kind)]) + 1

	# 1. Build on best open pad if we have open pads & sufficient gold
	var free_pads: Array[int] = []
	for i in world.pads.size():
		if not bool(world.pads[i]["occupied"]):
			free_pads.append(i)

	if free_pads.size() > 0 and (towers.size() < 4 or gold >= 120):
		var want_kind := "archer"
		if counts["archer"] == 0:
			want_kind = "archer"
		elif counts["guard"] == 0 and towers.size() >= 1:
			want_kind = "guard"
		elif counts["bombard"] == 0 and towers.size() >= 2:
			want_kind = "bombard"
		elif counts["spire"] == 0 and towers.size() >= 3:
			want_kind = "spire"
		else:
			var order := ["archer", "bombard", "spire", "guard"]
			var best_k := "archer"
			var min_c := 999
			for k in order:
				if int(counts[k]) < min_c:
					min_c = int(counts[k])
					best_k = k
			want_kind = best_k

		var cost := int(Defs.tw(want_kind)["cost"])
		if gold >= cost:
			# Score free pads by road coverage
			var best_pi := free_pads[0]
			var best_sc := -1e9
			var rng_r := float(Defs.tw(want_kind)["range"])
			for pi in free_pads:
				var pd: Dictionary = world.pads[pi]
				var px := float(pd["x"])
				var pz := float(pd["z"])
				var hits := 0.0
				for j in range(0, world.path_pts.size(), 3):
					var pp: Vector3 = world.path_pts[j]
					var d := U.dist2(px, pz, pp.x, pp.z)
					if d <= rng_r * rng_r:
						hits += 1.0
				if want_kind == "guard":
					hits += maxf(0.0, 6.0 - world.dist_to_road(px, pz)) * 2.5
				if hits > best_sc:
					best_sc = hits
					best_pi = pi
			_build_tower(best_pi, want_kind)
			return

	# 2. Otherwise upgrade lowest-level tower we can afford
	var best_tw: Node3D = null
	var best_lvl := 99
	for tw in towers:
		if tw.building or tw.level >= 2:
			continue
		var nxt: Dictionary = tw.get_next_stats()
		if gold >= int(nxt["cost"]) and tw.level < best_lvl:
			best_lvl = tw.level
			best_tw = tw
	if best_tw != null:
		_upgrade_tower(best_tw.pad_idx)


# ============================================================================
# Tower Construction, Upgrade, Sell & Combat
# ============================================================================

func _build_tower(pad_idx: int, kind: String) -> bool:
	if pad_idx < 0 or pad_idx >= world.pads.size():
		return false
	var pd: Dictionary = world.pads[pad_idx]
	if bool(pd["occupied"]):
		return false
	var cost := int(Defs.tw(kind)["cost"])
	if gold < cost:
		audio.play_sfx("uiDeny")
		return false

	gold -= cost
	var tw: Node3D = TowerScript.new()
	tw.name = "tower_%d" % pad_idx
	add_child(tw)
	var p := Vector3(float(pd["x"]), float(pd["y"]) + 0.24, float(pd["z"]))
	tw.setup(pad_idx, kind, p, level_num * 97 + pad_idx * 31, fx, audio)
	pd["occupied"] = true
	pd["tower"] = tw
	towers.append(tw)

	if kind == "guard":
		_sync_guard_footmen(tw)
	if OS.get_cmdline_user_args().has("--zap-log"):
		print("[build] kind=", kind, " pad=", pad_idx, " gold=", gold)

	_focus_pos = p
	_focus_timer = 2.4
	if selected_pad == pad_idx:
		hud.close_menus()
	_save_game(true)
	return true


func _upgrade_tower(pad_idx: int) -> bool:
	if pad_idx < 0 or pad_idx >= world.pads.size():
		return false
	var tw: Node3D = world.pads[pad_idx]["tower"]
	if tw == null or tw.building or tw.level >= 2:
		return false
	var nxt: Dictionary = tw.get_next_stats()
	var cost := int(nxt["cost"])
	if gold < cost:
		audio.play_sfx("uiDeny")
		return false
	gold -= cost
	tw.upgrade(fx, audio)
	if String(tw.kind) == "guard":
		_sync_guard_footmen(tw)
	if selected_pad == pad_idx:
		hud.refresh_menu_gold(gold, tw)
	_save_game(true)
	return true


func _sell_tower(pad_idx: int) -> void:
	if pad_idx < 0 or pad_idx >= world.pads.size():
		return
	var pd: Dictionary = world.pads[pad_idx]
	var tw: Node3D = pd["tower"]
	if tw == null:
		return
	var refund: int = tw.get_sell_value()
	gold += refund
	var p := tw.global_position
	rigs.spawn_shatter(p, "wood", 10, Color(0.76, 0.62, 0.44))
	rigs.spawn_coins(p, 5)
	fx.fx_dust(p.x, p.y, p.z, 10, 1.2, 0x8a7c68)
	audio.play_sfx("sell")

	# Remove associated guard footmen
	var i := footmen.size() - 1
	while i >= 0:
		if footmen[i]["tower"] == tw:
			footmen.remove_at(i)
		i -= 1

	tw.clear_visuals(fx)
	towers.erase(tw)
	tw.queue_free()
	pd["occupied"] = false
	pd["tower"] = null
	hud.close_menus()
	_save_game(true)


func _sync_guard_footmen(tw: Node3D) -> void:
	var st: Dictionary = tw.stats
	var want := int(st.get("count", st.get("n", 0)))
	var max_hp := float(st["hp"])
	var dmg := float(st["dmg"])
	var tp := tw.global_position

	# Find nearest road point for rallying
	var best_p := tp
	var best_d := 1e9
	for pp in world.path_pts:
		var d := U.dist2(tp.x, tp.z, pp.x, pp.z)
		if d < best_d:
			best_d = d
			best_p = pp

	var existing: Array[Dictionary] = []
	for fm in footmen:
		if fm["tower"] == tw:
			fm["max_hp"] = max_hp
			fm["hp"] = minf(max_hp, float(fm["hp"]) + max_hp * 0.4)
			fm["dmg"] = dmg
			existing.append(fm)

	while existing.size() < want:
		var idx := existing.size()
		var a := float(idx) * TAU / float(maxi(1, want))
		var r_pos := best_p + Vector3(cos(a) * 0.85, 0.0, sin(a) * 0.85)
		r_pos.y = world.top_at(r_pos.x, r_pos.z)
		var fm := {
			"tower": tw,
			"kind": "footman",
			"rally": r_pos,
			"pos": tp,
			"yaw": 0.0,
			"scale": 0.92,
			"phase": randf() * TAU,
			"hp": max_hp,
			"max_hp": max_hp,
			"dmg": dmg,
			"alive": true,
			"respawn": 0.0,
			"atk_cd": 0.0,
			"atk_t": 0.0,
			"flash": 0.0,
			"target": null,
			"tint": Color.WHITE,
		}
		footmen.append(fm)
		existing.append(fm)


func _step_towers(dt: float) -> void:
	for tw in towers:
		tw.update_visuals(dt, sim_time, fx, audio)
		if tw.building or tw.stun > 0.0:
			continue

		var kind: String = String(tw.kind)
		if kind == "guard":
			continue

		var st: Dictionary = tw.stats
		var rng_r := float(st["range"])
		var min_r := float(st.get("minR", 0.0))
		var hits_air := bool(st.get("air", false))
		var tp := tw.global_position
		var fire_p: Vector3 = tp + tw.mounts.get("fire_pos", Vector3(0, 3.0, 0))

		tw.cd -= dt
		if kind == "spire":
			tw.charge_t = clampf(1.0 - maxf(0.0, tw.cd) / (1.0 / maxf(0.1, float(st["rate"]))), 0.0, 1.0)

		if tw.cd > 0.0:
			continue

		# Pick furthest-along valid target in range
		var best_m: Dictionary = {}
		var best_dist := -1.0
		for m in monsters:
			if bool(m["dying"]):
				continue
			if float(m["fly"]) > 0.1 and not hits_air:
				continue
			if bool(m["phasing"]) and kind == "archer":
				continue
			var mp: Vector3 = m["pos"]
			var d := U.dist2(tp.x, tp.z, mp.x, mp.z)
			if d <= rng_r * rng_r and d >= min_r * min_r and float(m["dist"]) > best_dist:
				best_dist = float(m["dist"])
				best_m = m

		if best_m.is_empty():
			continue

		tw.cd = 1.0 / maxf(0.1, float(st["rate"]))
		var target_p: Vector3 = best_m["pos"] + Vector3(0.0, 0.65 * float(best_m["scale"]), 0.0)
		tw.aim_yaw = atan2(target_p.x - tp.x, target_p.z - tp.z)

		if kind == "archer":
			var a_list: Array = tw.mounts.get("archers", [])
			var origin := fire_p
			if a_list.size() > 0:
				var ai := randi() % a_list.size()
				origin = tp + a_list[ai] + Vector3(0, 0.75, 0)
				tw.archer_anim[ai]["yaw"] = tw.aim_yaw
				tw.archer_anim[ai]["draw"] = 1.0
			_fire_arrow(origin, best_m, float(st["dmg"]))
			audio.play_sfx("bow", 0.0, 0.55)

		elif kind == "bombard":
			tw.recoil = 1.0
			var muzzle := fire_p + Vector3(sin(tw.aim_yaw) * 0.85, 0.12, cos(tw.aim_yaw) * 0.85)
			_fire_shell(muzzle, best_m["pos"], float(st["dmg"]), float(st["splash"]))
			fx.fx_timed(5, muzzle.x, muzzle.y, muzzle.z, 0.5, 1.4, 0.16, 0xffd078, 1.4)
			fx.fx_sparks(muzzle.x, muzzle.y, muzzle.z, 8, 4.2, 0xffaa44, 0.8)
			fx.fx_smoke(muzzle.x, muzzle.y, muzzle.z, sin(tw.aim_yaw) * 1.4, 1.1, cos(tw.aim_yaw) * 1.4, 0.9, 0.4, 1.4, Color(0.32, 0.30, 0.28), 0.55)
			fx.add_flash(muzzle.x, muzzle.y, muzzle.z, 0xff9a38, 6.5, 0.16, 12.0)
			fx.add_shake(0.12)
			audio.play_sfx("cannon", 0.0, 0.78)

		elif kind == "spire":
			var chains := int(st.get("chains", st.get("jumps", 2)))
			var dmg := float(st["dmg"])
			var cur_p := fire_p
			var hit_list: Array = []
			var cur_m := best_m
			for c_i in chains:
				if cur_m.is_empty():
					break
				var mp: Vector3 = cur_m["pos"] + Vector3(0.0, 0.65 * float(cur_m["scale"]), 0.0)
				fx.fx_bolt(cur_p.x, cur_p.y, cur_p.z, mp.x, mp.y, mp.z, 0x9ce8ff, 0.24 - float(c_i) * 0.03, 0.26)
				fx.fx_sparks(mp.x, mp.y, mp.z, 6, 3.6, 0x9ce8ff, 0.9)
				_damage_monster(cur_m, dmg * pow(0.84, float(c_i)), true) # Magic shreds armor
				var slow_t := float(st.get("slow_t", 1.3)) * (1.0 - float(cur_m.get("slow_res", 0.0)))
				cur_m["slow_t"] = maxf(float(cur_m["slow_t"]), slow_t)
				if OS.get_cmdline_user_args().has("--zap-log"):
					print("[spire] hit ", cur_m["kind"], " dmg=", snappedf(dmg * pow(0.84, float(c_i)), 0.1), " hp=", snappedf(float(cur_m["hp"]), 0.1))
				hit_list.append(cur_m)
				cur_p = mp
				# Jump to next nearest unhit enemy
				var nxt_m: Dictionary = {}
				var nxt_d := 5.2
				for om in monsters:
					if bool(om["dying"]) or hit_list.has(om):
						continue
					var d := mp.distance_to(om["pos"])
					if d < nxt_d:
						nxt_d = d
						nxt_m = om
				cur_m = nxt_m
			tw.charge_t = 0.0
			audio.play_sfx("zap", 0.0, 0.78)
			if OS.is_debug_build() and OS.get_cmdline_user_args().has("--zap-log"):
				print("[spire] zap dmg=", dmg, " jump=", st.get("jumps", "-"), " hits=", hit_list.size())


func _fire_arrow(origin: Vector3, target_m: Dictionary, dmg: float) -> void:
	var tp: Vector3 = target_m["pos"] + Vector3(0, 0.55 * float(target_m["scale"]), 0)
	var d := origin.distance_to(tp)
	var dur := clampf(d / 19.5, 0.14, 0.58)
	arrows.append({
		"p0": origin,
		"p1": tp,
		"target": target_m,
		"pos": origin,
		"prev": origin,
		"arc": minf(2.6, d * 0.18),
		"age": 0.0,
		"dur": dur,
		"dmg": dmg,
	})


func _fire_shell(origin: Vector3, target_pos: Vector3, dmg: float, splash: float) -> void:
	var d := origin.distance_to(target_pos)
	var dur := clampf(d / 11.5, 0.32, 0.92)
	shells.append({
		"p0": origin,
		"p1": target_pos,
		"pos": origin,
		"arc": 2.4 + d * 0.26,
		"age": 0.0,
		"dur": dur,
		"dmg": dmg,
		"splash": splash,
	})


func _step_projectiles(dt: float) -> void:
	# Flaming arrows
	var i := arrows.size() - 1
	while i >= 0:
		var a: Dictionary = arrows[i]
		a["age"] = float(a["age"]) + dt
		var u := clampf(float(a["age"]) / float(a["dur"]), 0.0, 1.0)
		var tm: Dictionary = a["target"]
		if not tm.is_empty() and not bool(tm["dying"]):
			a["p1"] = tm["pos"] + Vector3(0, 0.55 * float(tm["scale"]), 0)
		var p0: Vector3 = a["p0"]
		var p1: Vector3 = a["p1"]
		var pos := p0.lerp(p1, u)
		pos.y += sin(u * PI) * float(a["arc"])
		a["prev"] = a["pos"]
		a["pos"] = pos

		if u >= 1.0:
			if not tm.is_empty() and not bool(tm["dying"]) and pos.distance_to(tm["pos"]) < 1.65:
				_damage_monster(tm, float(a["dmg"]), false)
				fx.fx_sparks(pos.x, pos.y, pos.z, 4, 2.6, 0xffaa44, 0.8)
				audio.play_sfx("arrowHit", 0.0, 0.45)
			else:
				# Stick smoldering missed arrow into the ground!
				var gy: float = world.height_at(pos.x, pos.z)
				var dir: Vector3 = (pos - a["prev"]).normalized()
				if stuck_arrows.size() >= 36:
					stuck_arrows.pop_front()
				stuck_arrows.append({"pos": Vector3(pos.x, gy + 0.06, pos.z), "dir": dir, "age": 0.0, "life": 6.0})
			arrows.remove_at(i)
		i -= 1

	# Stuck arrows decay
	i = stuck_arrows.size() - 1
	while i >= 0:
		stuck_arrows[i]["age"] = float(stuck_arrows[i]["age"]) + dt
		if float(stuck_arrows[i]["age"]) >= float(stuck_arrows[i]["life"]):
			stuck_arrows.remove_at(i)
		i -= 1

	# Arcing cannon shells
	i = shells.size() - 1
	while i >= 0:
		var s: Dictionary = shells[i]
		s["age"] = float(s["age"]) + dt
		var u := clampf(float(s["age"]) / float(s["dur"]), 0.0, 1.0)
		var p0: Vector3 = s["p0"]
		var p1: Vector3 = s["p1"]
		var pos := p0.lerp(p1, u)
		pos.y += sin(u * PI) * float(s["arc"])
		s["pos"] = pos
		if randf() < 0.65:
			fx.fx_smoke(pos.x, pos.y, pos.z, 0, 0.45, 0, 0.55, 0.22, 0.65, Color(0.32, 0.30, 0.28), 0.38)
		if u >= 1.0:
			var rad := float(s["splash"])
			fx.fx_explosion(p1.x, world.height_at(p1.x, p1.z), p1.z, rad, 0xff7024, Callable(world, "height_at"))
			audio.play_sfx("explode", 0.0, 0.85)
			for m in monsters:
				if bool(m["dying"]) or float(m["fly"]) > 0.1:
					continue
				var md := sqrt(U.dist2(p1.x, p1.z, m["pos"].x, m["pos"].z))
				if md <= rad:
					var falloff := lerpf(1.0, 0.45, md / maxf(0.1, rad))
					_damage_monster(m, float(s["dmg"]) * falloff, false)
			shells.remove_at(i)
		i -= 1


# ============================================================================
# Guard Post Footmen AI & Melee Clashes
# ============================================================================

func _step_footmen(dt: float) -> void:
	for fm in footmen:
		fm["flash"] = maxf(0.0, float(fm["flash"]) - dt * 5.0)
		fm["atk_t"] = maxf(0.0, float(fm["atk_t"]) - dt * 3.8)
		if not bool(fm["alive"]):
			fm["respawn"] = float(fm["respawn"]) - dt
			if float(fm["respawn"]) <= 0.0:
				fm["alive"] = true
				fm["hp"] = fm["max_hp"]
				var tw: Node3D = fm["tower"]
				fm["pos"] = tw.global_position if is_instance_valid(tw) else fm["rally"]
				fx.fx_dust(fm["pos"].x, fm["pos"].y, fm["pos"].z, 4, 0.5, 0x908068)
			continue

		var pos: Vector3 = fm["pos"]
		var rally: Vector3 = fm["rally"]
		var tgt = fm["target"]
		if tgt != null and (not monsters.has(tgt) or bool(tgt["dying"]) or sqrt(U.dist2(rally.x, rally.z, tgt["pos"].x, tgt["pos"].z)) > 5.2):
			if tgt != null and tgt.get("engaged") == fm:
				tgt["engaged"] = null
			fm["target"] = null
			tgt = null

		if tgt == null:
			var best_d := 4.4
			for m in monsters:
				if bool(m["dying"]) or float(m["fly"]) > 0.1:
					continue
				if m["engaged"] != null and m["engaged"] != fm:
					continue
				var d := sqrt(U.dist2(rally.x, rally.z, m["pos"].x, m["pos"].z))
				if d < best_d:
					best_d = d
					tgt = m
			if tgt != null:
				fm["target"] = tgt
				tgt["engaged"] = fm

		if tgt != null:
			var mp: Vector3 = tgt["pos"]
			var to_m := Vector3(mp.x - pos.x, 0.0, mp.z - pos.z)
			var d := to_m.length()
			var engage_r := 0.78 + float(tgt["scale"]) * 0.35
			if d > engage_r:
				var dir := to_m / maxf(0.001, d)
				pos += dir * 3.8 * dt
				pos.y = world.top_at(pos.x, pos.z)
				fm["pos"] = pos
				fm["yaw"] = U.ang_damp(float(fm["yaw"]), atan2(dir.x, dir.z), 10.0, dt)
				fm["phase"] = float(fm["phase"]) + dt * 11.0
			else:
				fm["yaw"] = U.ang_damp(float(fm["yaw"]), atan2(to_m.x, to_m.z), 12.0, dt)
				fm["atk_cd"] = float(fm["atk_cd"]) - dt
				if float(fm["atk_cd"]) <= 0.0:
					fm["atk_cd"] = 0.85
					fm["atk_t"] = 1.0
					_damage_monster(tgt, float(fm["dmg"]), false)
					var mid := (pos + mp) * 0.5 + Vector3(0, 0.55, 0)
					fx.fx_timed(7, mid.x, mid.y, mid.z, 0.65, 1.15, 0.22, 0xeef4ff, 1.1, {"rot": float(fm["yaw"])})
					fx.fx_sparks(mid.x, mid.y, mid.z, 4, 2.8, 0xffd890, 0.8)
					audio.play_sfx("clash", 0.0, 0.55)
		else:
			# Return to rally & regenerate HP
			fm["hp"] = minf(float(fm["max_hp"]), float(fm["hp"]) + float(fm["max_hp"]) * 0.08 * dt)
			var to_r := Vector3(rally.x - pos.x, 0.0, rally.z - pos.z)
			var d := to_r.length()
			if d > 0.16:
				var dir := to_r / d
				pos += dir * 3.2 * dt
				pos.y = world.top_at(pos.x, pos.z)
				fm["pos"] = pos
				fm["yaw"] = U.ang_damp(float(fm["yaw"]), atan2(dir.x, dir.z), 9.0, dt)
				fm["phase"] = float(fm["phase"]) + dt * 9.5


# ============================================================================
# Monsters Simulation, Unique Abilities, Boss Slow-Mo Death
# ============================================================================

func _step_monsters(dt: float) -> void:
	var i := monsters.size() - 1
	while i >= 0:
		var m: Dictionary = monsters[i]
		m["flash"] = maxf(0.0, float(m["flash"]) - dt * 5.2)
		m["slow_t"] = maxf(0.0, float(m["slow_t"]) - dt)
		m["haste_t"] = maxf(0.0, float(m["haste_t"]) - dt)
		m["atk_t"] = maxf(0.0, float(m["atk_t"]) - dt * 3.2)

		# Boss dramatic slow-mo death cascade (1.85s)
		if bool(m["dying"]):
			m["die_t"] = float(m["die_t"]) + dt
			var p: Vector3 = m["pos"]
			if randf() < dt * 11.0:
				fx.fx_explosion(p.x + randf_range(-1.1, 1.1), p.y + randf_range(0.2, 1.4), p.z + randf_range(-1.1, 1.1), 1.35, 0xff8028, Callable(world, "height_at"))
			if float(m["die_t"]) >= 1.75:
				fx.fx_explosion(p.x, p.y + 0.5, p.z, 3.2, 0xffaa38, Callable(world, "height_at"))
				rigs.spawn_shatter(p, String(m["kind"]), 22, m["tint"])
				rigs.spawn_coins(p, 8)
				fx.add_shake(0.65)
				audio.play_sfx("bossDie", 0.0, 1.0)
				_award_kill(m)
				monsters.remove_at(i)
			i -= 1
			continue

		var kind: String = String(m["kind"])
		var is_boss: bool = bool(m["boss"])
		var pos: Vector3 = m["pos"]

		# Special abilities per monster class
		m["spec_cd"] = float(m["spec_cd"]) - dt
		if float(m["spec_cd"]) <= 0.0:
			if kind == "necro":
				m["spec_cd"] = 6.2
				_spawn_monster("skeleton", clampf(float(m["lane"]) + randf_range(-0.35, 0.35), -0.7, 0.7), float(m["dist"]))
				fx.fx_timed(4, pos.x, pos.y + 0.1, pos.z, 0.4, 2.2, 0.5, 0x9955ff, 0.9, {"ground": true})
			elif kind == "king":
				m["spec_cd"] = 6.8
				for _k in 2:
					_spawn_monster("mummy", clampf(float(m["lane"]) + randf_range(-0.45, 0.45), -0.7, 0.7), float(m["dist"]))
				fx.fx_timed(4, pos.x, pos.y + 0.1, pos.z, 0.6, 3.2, 0.6, 0xffcc44, 1.0, {"ground": true})
			elif kind == "brood" or kind == "queen":
				m["spec_cd"] = 5.4 if kind == "queen" else 6.8
				var n_sp := 3 if kind == "queen" else 2
				for _k in n_sp:
					_spawn_monster("spider", clampf(float(m["lane"]) + randf_range(-0.5, 0.5), -0.7, 0.7), float(m["dist"]))
				fx.fx_dust(pos.x, pos.y, pos.z, 5, 0.8, 0x453a42)
			elif kind == "shaman":
				m["spec_cd"] = 4.2
				for om in monsters:
					if not bool(om["dying"]) and pos.distance_to(om["pos"]) < 4.5:
						om["hp"] = minf(float(om["max_hp"]), float(om["hp"]) + float(om["max_hp"]) * 0.20)
				fx.fx_timed(4, pos.x, pos.y + 0.12, pos.z, 0.4, 4.2, 0.55, 0x55ff77, 0.9, {"ground": true})
			elif kind == "drummer":
				m["spec_cd"] = 3.8
				for om in monsters:
					if not bool(om["dying"]) and pos.distance_to(om["pos"]) < 5.2:
						om["haste_t"] = 3.0
				fx.fx_timed(4, pos.x, pos.y + 0.12, pos.z, 0.5, 4.8, 0.5, 0xffaa33, 0.9, {"ground": true})
			elif kind == "wraith":
				m["phasing"] = not bool(m["phasing"])
				m["spec_cd"] = 1.8 if bool(m["phasing"]) else 3.5
			elif kind == "jotun":
				# Frost Jotun Boss: stomps & freezes nearby towers!
				m["spec_cd"] = 6.5
				m["atk_t"] = 1.0
				fx.fx_timed(4, pos.x, pos.y + 0.15, pos.z, 0.8, 7.2, 0.65, 0x88dcff, 1.15, {"ground": true})
				fx.add_shake(0.38)
				audio.play_sfx("bossStep", 0.0, 1.0)
				for tw in towers:
					if not tw.building and sqrt(U.dist2(pos.x, pos.z, tw.global_position.x, tw.global_position.z)) < 6.8:
						tw.stun = 3.0
			else:
				m["spec_cd"] = 99.0

		# Engaged in melee with a Guard Footman?
		var eng = m["engaged"]
		if eng != null and (not bool(eng["alive"]) or not footmen.has(eng)):
			m["engaged"] = null
			eng = null

		if eng != null and not is_boss:
			var fp: Vector3 = eng["pos"]
			m["yaw"] = U.ang_damp(float(m["yaw"]), atan2(fp.x - pos.x, fp.z - pos.z), 10.0, dt)
			m["atk_cd"] = float(m["atk_cd"]) - dt
			if float(m["atk_cd"]) <= 0.0:
				m["atk_cd"] = 1.15
				m["atk_t"] = 1.0
				eng["hp"] = float(eng["hp"]) - float(m["dmg"])
				eng["flash"] = 1.0
				if kind == "bomber":
					# Bomber detonates on contact!
					fx.fx_explosion(pos.x, pos.y, pos.z, 2.5, 0xff6020, Callable(world, "height_at"))
					audio.play_sfx("explode", 0.0, 0.9)
					eng["hp"] = 0.0
					m["hp"] = 0.0
				if float(eng["hp"]) <= 0.0:
					eng["alive"] = false
					eng["respawn"] = 7.5
					eng["target"] = null
					m["engaged"] = null
					audio.play_sfx("footmanDie", 0.0, 0.7)
		else:
			# Advance along road
			var spd := float(m["spd"])
			if float(m["slow_t"]) > 0.0:
				spd *= 0.55
			if float(m["haste_t"]) > 0.0:
				spd *= 1.38
			if kind == "colossus" and float(m["hp"]) < float(m["max_hp"]) * 0.45:
				spd *= 1.42
				if randf() < dt * 8.0:
					fx.fx_embers(pos.x, pos.y + 0.9, pos.z, 2, 0.6, 2.6, 0xff5518)

			m["dist"] = float(m["dist"]) + spd * dt
			m["phase"] = float(m["phase"]) + dt * (5.5 + spd * 2.4)
			var samp: Dictionary = world.sample_path(float(m["dist"]))
			var sp_pos: Vector3 = samp["pos"]
			var dir: Vector3 = samp["dir"]
			var side := Vector3(-dir.z, 0.0, dir.x)
			var fly_h := float(m["fly"])
			var target_pos := sp_pos + side * float(m["lane"]) + Vector3(0.0, fly_h, 0.0)
			m["pos"] = pos.lerp(target_pos, minf(1.0, dt * 14.0))
			m["yaw"] = U.ang_damp(float(m["yaw"]), atan2(dir.x, dir.z), 9.0, dt)

			# Heavy boss footsteps (screen shake + ground decals + deep bass SFX)
			if is_boss:
				m["step_t"] = float(m["step_t"]) + dt
				if float(m["step_t"]) >= 0.78:
					m["step_t"] = 0.0
					fx.add_shake(0.11)
					fx.add_decal(m["pos"].x, m["pos"].z, 0.62, 0x161210, 0.48, 12.0, Callable(world, "height_at"))
					audio.play_sfx("bossStep", 0.0, 0.55)

			# Reached Keep Gate? (Leak!)
			if float(m["dist"]) >= world.path_len - 0.8:
				var dmg_l := int(m["lives"])
				lives = maxi(0, lives - dmg_l)
				press = maxf(0.8, press - 0.08)
				fx.add_shake(0.42)
				var kp: Vector3 = world.keep_pos
				fx.add_flash(kp.x, kp.y + 2.0, kp.z, 0xff2818, 10.0, 0.35, 16.0)
				audio.play_sfx("leak", 0.0, 0.95)
				monsters.remove_at(i)
				if lives <= 0 and state == "play":
					state = "defeat"
					state_t = 0.0
					hud.show_banner("THE BEACON HAS FALLEN", "Survived to Wave %d  •  Rebuilding the Watch..." % wave, Color(1.0, 0.30, 0.22), 3.0)
					audio.play_sfx("beaconOut", 0.0, 1.0)
				i -= 1
				continue

		if float(m["hp"]) <= 0.0 and not bool(m["dying"]):
			_handle_monster_death(m, i)
		i -= 1


func _damage_monster(m: Dictionary, raw_dmg: float, magic: bool) -> void:
	if bool(m["dying"]):
		return
	var arm := 0.0 if magic else float(m["armor"])
	var dmg := maxf(1.0, raw_dmg * (1.0 - arm))
	m["hp"] = float(m["hp"]) - dmg
	m["flash"] = 1.0


func _handle_monster_death(m: Dictionary, idx: int) -> void:
	var kind: String = String(m["kind"])
	var pos: Vector3 = m["pos"]
	if m["engaged"] != null:
		m["engaged"]["target"] = null
		m["engaged"] = null

	if bool(m["boss"]):
		m["dying"] = true
		m["die_t"] = 0.0
		_focus_pos = pos
		_focus_timer = 2.6
		audio.play_sfx("roar", 0.0, 1.0)
		return

	# Special on-death triggers
	if kind == "slime":
		for side in [-0.42, 0.42]:
			_spawn_monster("slimelet", clampf(float(m["lane"]) + side, -0.75, 0.75), maxf(0.0, float(m["dist"]) - 0.3))
		fx.add_decal(pos.x, pos.z, 0.95, 0x2a5c24, 0.65, 16.0, Callable(world, "height_at"))
		audio.play_sfx("squelch", 0.0, 0.65)
	elif kind == "bomber":
		fx.fx_explosion(pos.x, pos.y, pos.z, 2.6, 0xff6a20, Callable(world, "height_at"))
		audio.play_sfx("explode", 0.0, 0.85)
	elif kind == "rat" or kind == "scarab":
		audio.play_sfx("ratSqueal", 0.0, 0.45)
	elif kind == "bat" or kind == "gargoyle":
		audio.play_sfx("batScreech", 0.0, 0.48)
	else:
		audio.play_sfx("boneRattle", 0.0, 0.45)

	rigs.spawn_shatter(pos, kind, 6, m["tint"])
	rigs.spawn_coins(pos, clampi(int(m["gold"]) / 4, 1, 5))
	_award_kill(m)
	monsters.remove_at(idx)


func _award_kill(m: Dictionary) -> void:
	gold += int(m["gold"])
	slain += 1
	press = minf(1.32, press + 0.004)
	audio.play_sfx("coin", 0.0, 0.38)
	var p: Vector3 = m["pos"] + Vector3(0, 0.7, 0)
	if cam != null and not cam.is_position_behind(p):
		hud.spawn_flying_coin(cam.unproject_position(p))


func _step_waterfall_spray(dt: float) -> void:
	if not bool(world.fall_at.get("has", false)):
		return
	var sp_type: String = String(world.fall_at.get("spray", "none"))
	if sp_type == "none":
		return
	wf_spray_t -= dt
	if wf_spray_t <= 0.0:
		wf_spray_t = 0.14
		var bp: Vector3 = world.fall_at["bot_pos"]
		if sp_type == "lava":
			fx.fx_embers(bp.x, bp.y + 0.4, bp.z, 3, 1.1, 2.8, 0xff6418)
			fx.fx_smoke(bp.x, bp.y + 0.5, bp.z, 0, 1.6, 0, 1.4, 0.7, 2.2, Color(0.28, 0.20, 0.18), 0.36)
		else:
			fx.fx_smoke(bp.x, bp.y + 0.3, bp.z, randf_range(-0.5, 0.5), 1.3, randf_range(-0.5, 0.5), 1.1, 0.65, 2.0, Color(0.75, 0.85, 0.92), 0.30)


# ============================================================================
# Emit Instanced Rigs, Archers, Footmen, Projectiles & Pad Markers
# ============================================================================

func _emit_all_rigs_and_visuals(_dt: float) -> void:
	# 1. Monsters & Bosses
	for m in monsters:
		rigs.emit_unit(m, sim_time, fx)

	# 2. Guard Post Footmen
	for fm in footmen:
		if bool(fm["alive"]):
			rigs.emit_unit(fm, sim_time, fx)

	# 3. Archer Tower Parapet Sentries
	for tw in towers:
		if tw.building or String(tw.kind) != "archer":
			continue
		var a_list: Array = tw.mounts.get("archers", [])
		var tp := tw.global_position
		for idx in a_list.size():
			var aa: Dictionary = tw.archer_anim[idx]
			rigs.emit_unit({
				"kind": "tower_archer",
				"pos": tp + a_list[idx],
				"yaw": float(aa["yaw"]),
				"scale": 0.82,
				"phase": 0.0,
				"flash": 0.0,
				"tint": Color.WHITE,
				"atk_t": float(aa["draw"]),
			}, sim_time, fx)

	# 4. Flaming Arrows (with bright additive trail ribbons) & Stuck Arrows
	for a in arrows:
		var pos: Vector3 = a["pos"]
		var prev: Vector3 = a["prev"]
		var dir := (pos - prev)
		if dir.length_squared() < 1e-6:
			dir = Vector3.FORWARD
		else:
			dir = dir.normalized()
		var b := Basis.looking_at(-dir, Vector3.UP)
		rigs.push_part("proj_arrow", Transform3D(b, pos))
		fx.push_seg(prev - dir * 0.45, pos, 0.14, Color(1.0, 0.68, 0.24), 1.2)
		fx.push_add(pos.x, pos.y, pos.z, 0.36, 0.36, Color(1.0, 0.72, 0.28), 1.2, 0)

	for sa in stuck_arrows:
		var dir: Vector3 = sa["dir"]
		if dir.length_squared() < 1e-6:
			dir = Vector3.DOWN
		var b := Basis.looking_at(-dir.normalized(), Vector3.UP)
		rigs.push_part("proj_arrow", Transform3D(b, sa["pos"]))

	# 5. Cannon Shells
	for s in shells:
		var pos: Vector3 = s["pos"]
		rigs.push_part("proj_shell", Transform3D(Basis.IDENTITY, pos))
		fx.push_add(pos.x, pos.y, pos.z, 0.42, 0.42, Color(1.0, 0.52, 0.16), 0.9, 0)

	# 6. Floating Brass Compass Crystals over Empty Tower Pads
	if state == "play":
		for i in world.pads.size():
			var pd: Dictionary = world.pads[i]
			if bool(pd["occupied"]):
				continue
			var bob := sin(real_time * 2.4 + float(i) * 0.9) * 0.14
			var sc := 1.25 if (i == hovered_pad or i == selected_pad) else 0.92
			var p := Vector3(float(pd["x"]), float(pd["y"]) + 0.78 + bob, float(pd["z"]))
			var xf := Transform3D(Basis(Vector3.UP, real_time * 1.4 + float(i)).scaled(Vector3.ONE * sc), p)
			rigs.push_part("pad_marker", xf, Color(1.0, 0.88, 0.50), 0.15 if i == hovered_pad else 0.0)


# ============================================================================
# Dynamic Lights, Weather, Biome Look & Procedural Audio
# ============================================================================

func _update_lights_weather_audio(dt: float) -> void:
	world.apply_biome_look(dt, false, world_env, fx, mist_mat, weather, post, fade_v)

	var t_lights: Array = []
	for tw in towers:
		if is_instance_valid(tw):
			var info: Dictionary = tw.get_light_info(sim_time)
			if not info.is_empty():
				t_lights.append(info)

	var torches: Array = []
	for lp in world.lantern_positions:
		torches.append({"pos": lp, "col": Color(1.0, 0.62, 0.24), "inten": 1.8 * beacon_power, "range": 9.5})
	for a in arrows:
		if torches.size() >= 5:
			break
		torches.append({"pos": a["pos"], "col": Color(1.0, 0.58, 0.18), "inten": 1.4, "range": 6.5})

	var env_l: Array = []
	for lv in world.lava_vents:
		env_l.append({"pos": lv + Vector3(0, 0.5, 0), "col": Color(1.0, 0.36, 0.08), "inten": 3.4 * beacon_power, "range": 12.0})
	for ml in world.mushroom_lights:
		env_l.append({"pos": ml, "col": world.biome.get("wisp_col", Color(0.45, 1.0, 0.65)), "inten": 2.4 * beacon_power, "range": 9.5})

	var b_mul := float(world.biome.get("beacon_mul", 1.0))
	var amb_sm: Vector3 = world.biome.get("mist_amb", Vector3(0.08, 0.10, 0.14))
	fx.update_lights_and_mist(
		sim_time,
		world.beacon_flame_pos + Vector3(0, 0.6, 0),
		beacon_power * b_mul,
		Color(1.0, 0.55, 0.18),
		t_lights,
		torches,
		env_l,
		cam_target,
		mist_mat,
		weather,
		Color(amb_sm.x, amb_sm.y, amb_sm.z)
	)

	if mist_mat != null:
		var w_spd := float(world.biome.get("wind", 1.0))
		mist_mat.set_shader_parameter("u_wind", Vector2(sim_time * 0.16 * w_spd, sim_time * 0.08 * w_spd))

	if weather.has_method("step"):
		weather.step(dt, sim_time, fx.mist_pos, fx.mist_col)

	var tension := 0.85 if _has_living_boss() else (0.28 if monsters.size() > 14 else 0.0)
	var wind_a := clampf(float(world.biome.get("wind", 1.0)) * 0.35, 0.12, 0.85)
	audio.set_ambience(0.45 * beacon_power, wind_a, tension)
	audio.update_audio(dt, paused)


# ============================================================================
# Camera Director & Input Handling
# ============================================================================

func _update_camera(dt: float) -> void:
	# WASD / Arrow keys manual pan
	var pan_x := 0.0
	var pan_z := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan_x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan_z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan_z += 1.0
	if absf(pan_x) > 0.01 or absf(pan_z) > 0.01:
		manual_cam = true
		var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
		var rgt := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
		cam_goal += (rgt * pan_x - fwd * pan_z).normalized() * 18.0 * dt

	if not manual_cam:
		# Auto-Director: frame boss, recent build focus, or active combat centroid!
		if _focus_timer > 0.0:
			_focus_timer -= dt
			cam_goal = _focus_pos * 0.55
			cam_dist_goal = 29.0
		elif state == "crumble" or state == "rise":
			cam_goal = Vector3.ZERO
			cam_dist_goal = 40.0
		else:
			var sum_p := Vector3.ZERO
			var sum_w := 0.0
			for m in monsters:
				var w := 6.0 if bool(m["boss"]) else 1.0
				sum_p += m["pos"] * w
				sum_w += w
			if sum_w > 0.1:
				cam_goal = (sum_p / sum_w) * 0.45
				cam_dist_goal = 32.5 if _has_living_boss() else 35.0
			else:
				cam_goal = Vector3(sin(real_time * 0.14) * 2.5, 0.3, cos(real_time * 0.11) * 2.5)
				cam_dist_goal = 36.5

	cam_goal.x = clampf(cam_goal.x, -14.0, 14.0)
	cam_goal.z = clampf(cam_goal.z, -14.0, 14.0)
	cam_dist_goal = clampf(cam_dist_goal, 18.0, 48.0)

	var k := 1.0 - exp(-dt * 4.5)
	cam_target = cam_target.lerp(cam_goal, k)
	cam_dist = lerpf(cam_dist, cam_dist_goal, k)

	var h_dist := cos(cam_elev) * cam_dist
	var v_dist := sin(cam_elev) * cam_dist
	var cam_pos := cam_target + Vector3(sin(cam_yaw) * h_dist, v_dist, cos(cam_yaw) * h_dist)
	cam_pos += Vector3(fx.shake_x, fx.shake_y, fx.shake_x * 0.5)
	cam.position = cam_pos
	cam.look_at(cam_target + Vector3(fx.shake_x * 0.4, fx.shake_y * 0.4, 0.0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		hud.dismiss_title()
		match event.keycode:
			KEY_P:
				_on_toggle_pause()
			KEY_TAB:
				_on_cycle_speed()
			KEY_M:
				_on_toggle_mute()
			KEY_O:
				hud.toggle_audio_overlay()
			KEY_C:
				_on_toggle_ai()
			KEY_Q:
				_on_switch_biome(-1)
			KEY_E:
				_on_switch_biome(1)
			KEY_F, KEY_0:
				_on_follow_cam()
			KEY_SPACE, KEY_ENTER:
				_on_call_wave()
			KEY_R:
				hud.open_restart_panel()
			KEY_ESCAPE:
				if hud.is_restart_panel_open():
					hud.close_restart_panel()
				elif hud.is_quit_panel_open():
					hud.close_quit_panel()
				elif hud.is_audio_overlay_open():
					hud.close_audio_overlay()
				elif hud.is_menu_open():
					hud.close_menus()
				else:
					hud.open_quit_panel()
			KEY_F5:
				_on_save_cmd()
			KEY_1:
				if selected_pad >= 0: _on_build_cmd(selected_pad, "archer")
			KEY_2:
				if selected_pad >= 0: _on_build_cmd(selected_pad, "bombard")
			KEY_3:
				if selected_pad >= 0: _on_build_cmd(selected_pad, "spire")
			KEY_4:
				if selected_pad >= 0: _on_build_cmd(selected_pad, "guard")
			KEY_U:
				if selected_pad >= 0: _on_upgrade_cmd(selected_pad)
			KEY_S:
				if selected_pad >= 0 and world.pads[selected_pad]["occupied"]:
					_on_sell_cmd(selected_pad)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if hud.is_pointer_over_ui(mb.position):
			return
		hud.dismiss_title()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			manual_cam = true
			cam_dist_goal = clampf(cam_dist_goal - 2.6, 18.0, 48.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			manual_cam = true
			cam_dist_goal = clampf(cam_dist_goal + 2.6, 18.0, 48.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start = mb.position
			else:
				if not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
					_handle_world_click(mb.position)
				_dragging = false

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _dragging:
			if mm.position.distance_to(_drag_start) > 6.0:
				_drag_moved = true
				manual_cam = true
				var s := cam_dist * 0.00145
				var rgt := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
				var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
				cam_goal += (-rgt * mm.relative.x + fwd * mm.relative.y) * s
		else:
			_update_pad_hover(mm.position)


func _ray_ground(screen_pos: Vector2) -> Vector3:
	var orig := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t := (0.25 - orig.y) / dir.y
	return orig + dir * maxf(0.0, t)


func _pick_pad_at(screen_pos: Vector2) -> int:
	var hit := _ray_ground(screen_pos)
	var best := -1
	var best_d := 2.25
	for i in world.pads.size():
		var pd: Dictionary = world.pads[i]
		var d := sqrt(U.dist2(hit.x, hit.z, float(pd["x"]), float(pd["z"])))
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_pad_hover(screen_pos: Vector2) -> void:
	if state != "play" or hud.is_pointer_over_ui(screen_pos):
		hovered_pad = -1
		hover_fx.hide_range()
		return
	var pi := _pick_pad_at(screen_pos)
	if pi != hovered_pad:
		hovered_pad = pi
		if pi >= 0:
			audio.play_sfx("uiHover", 0.0, 0.4)
			var pd: Dictionary = world.pads[pi]
			var p := Vector3(float(pd["x"]), 0.0, float(pd["z"]))
			if bool(pd["occupied"]) and pd["tower"] != null:
				var tw: Node3D = pd["tower"]
				hover_fx.show_range(String(tw.kind), float(tw.stats["range"]), float(tw.stats.get("minR", 0.0)), p, 0.55)
			else:
				hover_fx.show_range("pad", 1.55, 0.0, p, 0.85)
		else:
			hover_fx.hide_range()


func _run_zap_test() -> void:
	## 调试：在离路起点最近的空位建一座雷塔，并把一只骷髅直接放到射程内
	var best_i := -1
	var best_d := 1e18
	for i in world.pads.size():
		if bool(world.pads[i]["occupied"]):
			continue
		var pd: Dictionary = world.pads[i]
		var d := U.dist2(float(pd["x"]), float(pd["z"]), world.path_pts[2].x, world.path_pts[2].z)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		print("[zap-test] no free pad")
		return
	_build_tower(best_i, "spire")
	_spawn_monster("skel", 0.0, 0.0)
	_spawn_monster("knight", 0.4, 0.0)
	print("[zap-test] spire pad=", best_i, " monsters=", monsters.size())


func _demo_open_build() -> void:
	## 调试：自动点开第一个空位的建造面板（截图用）
	for i in world.pads.size():
		if bool(world.pads[i]["occupied"]):
			continue
		var pd: Dictionary = world.pads[i]
		var wp := Vector3(float(pd["x"]), float(pd["y"]) + 0.3, float(pd["z"]))
		var sp := cam.unproject_position(wp)
		if sp.x < 120.0 or sp.y < 90.0 or sp.x > 1200.0 or sp.y > 760.0:
			continue
		_handle_world_click(sp)
		return


func _handle_world_click(screen_pos: Vector2) -> void:
	if state != "play":
		return
	var now := real_time
	var pi := _pick_pad_at(screen_pos)
	if pi < 0:
		if now - _last_click_t < 0.32:
			# Double-click ground toggles zoom close/wide
			manual_cam = true
			cam_dist_goal = 22.0 if cam_dist_goal > 28.0 else 36.0
		_last_click_t = now
		hud.close_menus()
		return
	_last_click_t = now

	# Taking manual tower action switches from AI to player command seamlessly
	if ai_mode:
		ai_mode = false
		hud.show_banner("YOU COMMAND", "AI Commander Disengaged — Press [C] to Re-enable", Color(0.95, 0.82, 0.45), 2.0)

	selected_pad = pi
	audio.play_sfx("uiClick")
	var pd: Dictionary = world.pads[pi]
	var p := Vector3(float(pd["x"]), 0.0, float(pd["z"]))
	if bool(pd["occupied"]) and pd["tower"] != null:
		var tw: Node3D = pd["tower"]
		range_fx.show_range(String(tw.kind), float(tw.stats["range"]), float(tw.stats.get("minR", 0.0)), p, 1.0)
		hud.open_inspect_menu(pi, screen_pos, tw, gold)
	else:
		range_fx.show_range("pad", 1.65, 0.0, p, 1.0)
		hud.open_build_menu(pi, screen_pos, gold)


# ============================================================================
# HUD Signal Handlers & Frame Sync
# ============================================================================

func _on_toggle_ai() -> void:
	ai_mode = not ai_mode
	audio.play_sfx("uiClick")
	hud.show_banner("AI COMMANDER" if ai_mode else "YOU COMMAND", "Auto-defense active" if ai_mode else "Click any pad to build or upgrade", Color(0.95, 0.82, 0.48), 1.8)


func _on_call_wave() -> void:
	if state != "play" or wave_active or wave_timer <= 0.3:
		return
	var bonus := int(ceil(wave_timer * 4.0))
	gold += bonus
	wave_timer = 0.0
	audio.play_sfx("coin", 0.0, 0.8)
	_start_next_wave()


func _on_toggle_pause() -> void:
	paused = not paused
	audio.play_sfx("uiClick")


func _on_cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	audio.play_sfx("uiClick")


func _on_toggle_mute() -> void:
	audio.set_muted(not audio.muted)
	hud.sync_audio_controls(audio.master_volume, audio.muted)
	_save_config()


func _on_volume_changed(vol: float) -> void:
	audio.set_master_volume(vol)
	hud.sync_audio_controls(audio.master_volume, audio.muted)
	_save_config()


func _on_switch_biome(dir: int) -> void:
	audio.play_sfx("uiClick")
	_begin_crumble(biome_idx + dir, false)


func _on_zoom_cmd(delta_z: float) -> void:
	manual_cam = true
	cam_dist_goal = clampf(cam_dist_goal + delta_z, 18.0, 48.0)


func _on_follow_cam() -> void:
	manual_cam = false
	audio.play_sfx("uiClick")


func _on_build_cmd(pad_idx: int, kind: String) -> void:
	if _build_tower(pad_idx, kind):
		audio.play_sfx("uiClick")


func _on_hover_build(pad_idx: int, kind: String) -> void:
	if pad_idx < 0 or pad_idx >= world.pads.size():
		return
	hover_build_kind = kind
	var pd: Dictionary = world.pads[pad_idx]
	var st: Dictionary = Defs.tw(kind)
	range_fx.show_range(kind, float(st["range"]), float(st.get("minR", 0.0)), Vector3(float(pd["x"]), 0.0, float(pd["z"])), 0.95)


func _on_upgrade_cmd(pad_idx: int) -> void:
	if _upgrade_tower(pad_idx):
		audio.play_sfx("uiClick")


func _on_sell_cmd(pad_idx: int) -> void:
	_sell_tower(pad_idx)


func _update_hud(dt: float) -> void:
	var call_bonus := 0
	var prog := 0.0
	if state == "play":
		if wave_active:
			prog = 1.0 - float(wave_queue.size() + monsters.size()) / maxf(1.0, float(10 + wave * 3))
		else:
			prog = 1.0 - clampf(wave_timer / maxf(0.1, wave_wait_max), 0.0, 1.0)
			if wave_timer > 0.4:
				call_bonus = int(ceil(wave_timer * 4.0))

	hud.update_stats(
		lives, MAX_LIVES, gold, slain,
		String(world.biome.get("name", "Ashen Vale")),
		maxi(1, wave), prog, call_bonus,
		ai_mode, paused, float(SPEEDS[speed_idx]), audio.muted, manual_cam
	)

	if selected_pad >= 0 and selected_pad < world.pads.size():
		var pd: Dictionary = world.pads[selected_pad]
		hud.refresh_menu_gold(gold, pd["tower"] if bool(pd["occupied"]) else null)

	# Project 3D Health Bars for damaged units & all Bosses
	var bars: Array[Dictionary] = []
	for m in monsters:
		if bool(m["dying"]):
			continue
		var frac := float(m["hp"]) / maxf(1.0, float(m["max_hp"]))
		var is_boss := bool(m["boss"])
		if not is_boss and frac >= 0.99:
			continue
		var wp: Vector3 = m["pos"] + Vector3(0.0, 1.25 * float(m["scale"]) + (0.6 if is_boss else 0.0), 0.0)
		if not cam.is_position_behind(wp):
			bars.append({
				"pos": cam.unproject_position(wp),
				"frac": frac,
				"boss": is_boss,
				"name": String(m["name"]).to_upper(),
				"slow": float(m["slow_t"]) > 0.0,
				"ally": false,
			})
	for fm in footmen:
		if not bool(fm["alive"]):
			continue
		var frac := float(fm["hp"]) / maxf(1.0, float(fm["max_hp"]))
		if frac >= 0.99:
			continue
		var wp: Vector3 = fm["pos"] + Vector3(0.0, 1.15, 0.0)
		if not cam.is_position_behind(wp):
			bars.append({
				"pos": cam.unproject_position(wp),
				"frac": frac,
				"boss": false,
				"ally": true,
			})
	hud.set_hp_bars(bars)
	hud.step_hud(dt)
