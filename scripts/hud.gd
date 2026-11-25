extends CanvasLayer
## Complete Dark-Fantasy HUD & Interactive Menus (ported & upgraded from 72-ui.js).
## Features:
## - Top-left stats plate (flickering flame lives, animated gold counter, slain, biome badge)
## - Top-center wave plate with countdown progress bar & clickable early-call +gold button
## - Top-right AI Commander / You Command toggle
## - Bottom bar (Pause, 1x/2x/3x speed, Mute, Prev/Next Biome, Zoom -/+, Follow the Fight)
## - Floating contextual Build Menu (4 towers with hover range preview) & Inspect Menu (3 stars, green Next diff, 2-step Sell)
## - 3D-projected health bars + Boss nameplates + 2D flying gold coins + First-seen monster tips + Title card & banners

const Defs = preload("res://scripts/defs.gd")

signal cmd_toggle_ai()
signal cmd_call_wave()
signal cmd_toggle_pause()
signal cmd_cycle_speed()
signal cmd_toggle_mute()
signal cmd_volume_changed(vol: float)
signal cmd_switch_biome(dir: int)
signal cmd_zoom(delta: float)
signal cmd_follow_cam()
signal cmd_build(pad_idx: int, kind: String)
signal cmd_hover_build(pad_idx: int, kind: String)
signal cmd_upgrade(pad_idx: int)
signal cmd_sell(pad_idx: int)
signal cmd_close_menu()

# Custom 2D canvas overlay for health bars, flying coins, title card, banners, tips
var overlay: Control

# Interactive panels
var top_left: PanelContainer
var top_center: PanelContainer
var top_right: PanelContainer
var bottom_bar: PanelContainer
var build_panel: PanelContainer
var inspect_panel: PanelContainer
var audio_backdrop: ColorRect
var audio_overlay: PanelContainer

# Dynamic labels & buttons
var lbl_lives: Label
var lbl_gold: Label
var lbl_slain: Label
var lbl_biome: Label
var lbl_wave: Label
var bar_wave: ProgressBar
var btn_call: Button
var btn_ai: Button
var btn_pause: Button
var btn_speed: Button
var btn_mute: Button
var btn_follow: Button

# Contextual menu widgets
var _menu_pad := -1
var _menu_mode := "" # "" | "build" | "inspect"
var _build_btns: Dictionary = {}
var _insp_title: Label
var _insp_stats: Label
var _insp_next: Label
var _insp_upg: Button
var _insp_sell: Button
var _sell_armed := false
var _sell_timer := 0.0

# Audio overlay widgets
var _audio_slider: HSlider
var _audio_vol_lbl: Label
var _audio_mute_btn: Button
var _audio_syncing := false

# Visual FX state
var _t := 0.0
var _gold_bump := 0.0
var _last_gold := 0
var _title_t := 0.0
var _title_visible := true
var _best_wave := 0
var _banners: Array[Dictionary] = [] # [{title, sub, col, age, life}]
var _tip: Dictionary = {} # {title, body, col, age, life}
var _fly_coins: Array[Dictionary] = [] # [{p0, p1, age, dur}]
var _hp_bars: Array[Dictionary] = [] # [{pos: Vector2, frac: float, boss: bool, name: String, shield: bool, slow: bool}]

var _style_plate: StyleBoxFlat
var _style_btn: StyleBoxFlat
var _style_btn_hov: StyleBoxFlat
var _style_btn_act: StyleBoxFlat


func _ready() -> void:
	layer = 10
	_build_styles()
	_build_overlay()
	_build_top_bar()
	_build_bottom_bar()
	_build_context_menus()
	_build_audio_overlay()


func _build_styles() -> void:
	_style_plate = StyleBoxFlat.new()
	_style_plate.bg_color = Color(0.055, 0.058, 0.082, 0.84)
	_style_plate.border_color = Color(0.76, 0.58, 0.28, 0.62)
	_style_plate.set_border_width_all(1)
	_style_plate.set_corner_radius_all(6)
	_style_plate.set_content_margin_all(8)
	_style_plate.shadow_color = Color(0, 0, 0, 0.45)
	_style_plate.shadow_size = 8

	_style_btn = StyleBoxFlat.new()
	_style_btn.bg_color = Color(0.10, 0.105, 0.145, 0.90)
	_style_btn.border_color = Color(0.68, 0.52, 0.26, 0.55)
	_style_btn.set_border_width_all(1)
	_style_btn.set_corner_radius_all(5)
	_style_btn.set_content_margin_all(6)

	_style_btn_hov = _style_btn.duplicate()
	_style_btn_hov.bg_color = Color(0.18, 0.165, 0.21, 0.96)
	_style_btn_hov.border_color = Color(0.95, 0.76, 0.38, 0.92)

	_style_btn_act = _style_btn.duplicate()
	_style_btn_act.bg_color = Color(0.28, 0.19, 0.11, 0.96)
	_style_btn_act.border_color = Color(1.0, 0.78, 0.34, 1.0)


func _style_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _style_btn)
	btn.add_theme_stylebox_override("hover", _style_btn_hov)
	btn.add_theme_stylebox_override("pressed", _style_btn_act)
	btn.add_theme_stylebox_override("focus", _style_btn_hov)
	btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.40))
	btn.add_theme_font_size_override("font_size", 13)
	btn.focus_mode = Control.FOCUS_NONE


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "hud_overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_on_overlay_draw)
	add_child(overlay)


func _build_top_bar() -> void:
	# Top-Left Stats Plate
	top_left = PanelContainer.new()
	top_left.add_theme_stylebox_override("panel", _style_plate)
	top_left.position = Vector2(14, 12)
	add_child(top_left)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	top_left.add_child(hb)

	lbl_lives = _mk_stat_lbl("🔥 20", Color(1.0, 0.62, 0.32))
	lbl_gold = _mk_stat_lbl("● 160", Color(0.98, 0.82, 0.36))
	lbl_slain = _mk_stat_lbl("☠ 0", Color(0.82, 0.82, 0.88))
	lbl_biome = _mk_stat_lbl("ASHEN VALE", Color(0.74, 0.80, 0.92))
	hb.add_child(lbl_lives)
	hb.add_child(lbl_gold)
	hb.add_child(lbl_slain)
	hb.add_child(lbl_biome)

	# Top-Center Wave Plate
	top_center = PanelContainer.new()
	top_center.add_theme_stylebox_override("panel", _style_plate)
	top_center.anchor_left = 0.5
	top_center.anchor_right = 0.5
	top_center.offset_left = -128
	top_center.offset_right = 128
	top_center.offset_top = 12
	add_child(top_center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	top_center.add_child(vb)

	var whb := HBoxContainer.new()
	whb.alignment = BoxContainer.ALIGNMENT_CENTER
	whb.add_theme_constant_override("separation", 10)
	vb.add_child(whb)

	lbl_wave = _mk_stat_lbl("WAVE 1", Color(0.98, 0.88, 0.66))
	lbl_wave.add_theme_font_size_override("font_size", 15)
	whb.add_child(lbl_wave)

	btn_call = Button.new()
	btn_call.text = "Next Wave +0g"
	_style_button(btn_call)
	btn_call.visible = false
	btn_call.pressed.connect(func() -> void: cmd_call_wave.emit())
	whb.add_child(btn_call)

	bar_wave = ProgressBar.new()
	bar_wave.custom_minimum_size = Vector2(220, 6)
	bar_wave.show_percentage = false
	bar_wave.min_value = 0.0
	bar_wave.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.14, 0.18, 0.9)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.94, 0.62, 0.24, 0.95)
	fg.set_corner_radius_all(3)
	bar_wave.add_theme_stylebox_override("background", bg)
	bar_wave.add_theme_stylebox_override("fill", fg)
	vb.add_child(bar_wave)

	# Top-Right Commander Mode Plate
	top_right = PanelContainer.new()
	top_right.add_theme_stylebox_override("panel", _style_plate)
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -168
	top_right.offset_right = -14
	top_right.offset_top = 12
	add_child(top_right)

	btn_ai = Button.new()
	btn_ai.text = "AI Commander [C]"
	_style_button(btn_ai)
	btn_ai.pressed.connect(func() -> void: cmd_toggle_ai.emit())
	top_right.add_child(btn_ai)


func _build_bottom_bar() -> void:
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _style_plate)
	bottom_bar.anchor_left = 0.5
	bottom_bar.anchor_right = 0.5
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_left = -280
	bottom_bar.offset_right = 280
	bottom_bar.offset_top = -56
	bottom_bar.offset_bottom = -12
	add_child(bottom_bar)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	bottom_bar.add_child(hb)

	btn_pause = Button.new()
	btn_pause.text = "Pause [P]"
	_style_button(btn_pause)
	btn_pause.pressed.connect(func() -> void: cmd_toggle_pause.emit())
	hb.add_child(btn_pause)

	btn_speed = Button.new()
	btn_speed.text = "1x [Tab]"
	_style_button(btn_speed)
	btn_speed.pressed.connect(func() -> void: cmd_cycle_speed.emit())
	hb.add_child(btn_speed)

	btn_mute = Button.new()
	btn_mute.text = "Audio 100% [O]"
	_style_button(btn_mute)
	btn_mute.pressed.connect(func() -> void: toggle_audio_overlay())
	hb.add_child(btn_mute)

	var b_prev := Button.new()
	b_prev.text = "◀ Realm [Q]"
	_style_button(b_prev)
	b_prev.pressed.connect(func() -> void: cmd_switch_biome.emit(-1))
	hb.add_child(b_prev)

	var b_next := Button.new()
	b_next.text = "Realm ▶ [E]"
	_style_button(b_next)
	b_next.pressed.connect(func() -> void: cmd_switch_biome.emit(1))
	hb.add_child(b_next)

	var b_zm := Button.new()
	b_zm.text = "-"
	b_zm.custom_minimum_size = Vector2(28, 0)
	_style_button(b_zm)
	b_zm.pressed.connect(func() -> void: cmd_zoom.emit(3.5))
	hb.add_child(b_zm)

	var b_zp := Button.new()
	b_zp.text = "+"
	b_zp.custom_minimum_size = Vector2(28, 0)
	_style_button(b_zp)
	b_zp.pressed.connect(func() -> void: cmd_zoom.emit(-3.5))
	hb.add_child(b_zp)

	btn_follow = Button.new()
	btn_follow.text = "Follow Fight [F]"
	_style_button(btn_follow)
	btn_follow.visible = false
	btn_follow.pressed.connect(func() -> void: cmd_follow_cam.emit())
	hb.add_child(btn_follow)


func _build_context_menus() -> void:
	# Build Menu (4 towers)
	build_panel = PanelContainer.new()
	build_panel.add_theme_stylebox_override("panel", _style_plate)
	build_panel.visible = false
	add_child(build_panel)

	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 5)
	build_panel.add_child(bvb)

	var hdr := _mk_stat_lbl("CONSTRUCT TOWER", Color(0.95, 0.78, 0.42))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bvb.add_child(hdr)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	bvb.add_child(grid)

	var key_nums := ["1", "2", "3", "4"]
	for i in Defs.TOWER_KINDS.size():
		var k: String = Defs.TOWER_KINDS[i]
		var st: Dictionary = Defs.TOWERS[k][0]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(142, 46)
		btn.text = "[%s] %s  %dg\n%s" % [key_nums[i], String(st["name"]), int(st["cost"]), String(st["desc"])]
		_style_button(btn)
		btn.pressed.connect(func() -> void:
			if _menu_pad >= 0:
				cmd_build.emit(_menu_pad, k)
		)
		btn.mouse_entered.connect(func() -> void:
			if _menu_pad >= 0:
				cmd_hover_build.emit(_menu_pad, k)
		)
		grid.add_child(btn)
		_build_btns[k] = btn

	# Inspect Menu (Upgrade + 2-Step Sell)
	inspect_panel = PanelContainer.new()
	inspect_panel.add_theme_stylebox_override("panel", _style_plate)
	inspect_panel.visible = false
	add_child(inspect_panel)

	var ivb := VBoxContainer.new()
	ivb.add_theme_constant_override("separation", 5)
	inspect_panel.add_child(ivb)

	_insp_title = _mk_stat_lbl("TOWER ★☆☆", Color(0.98, 0.84, 0.44))
	_insp_title.add_theme_font_size_override("font_size", 15)
	ivb.add_child(_insp_title)

	_insp_stats = _mk_stat_lbl("", Color(0.86, 0.86, 0.90))
	ivb.add_child(_insp_stats)

	_insp_next = _mk_stat_lbl("", Color(0.48, 0.95, 0.56))
	ivb.add_child(_insp_next)

	var ihb := HBoxContainer.new()
	ihb.add_theme_constant_override("separation", 8)
	ivb.add_child(ihb)

	_insp_upg = Button.new()
	_insp_upg.custom_minimum_size = Vector2(128, 34)
	_style_button(_insp_upg)
	_insp_upg.pressed.connect(func() -> void:
		if _menu_pad >= 0:
			cmd_upgrade.emit(_menu_pad)
	)
	ihb.add_child(_insp_upg)

	_insp_sell = Button.new()
	_insp_sell.custom_minimum_size = Vector2(112, 34)
	_style_button(_insp_sell)
	_insp_sell.pressed.connect(func() -> void:
		if _menu_pad < 0:
			return
		if not _sell_armed:
			_sell_armed = true
			_sell_timer = 3.0
			_insp_sell.text = "Confirm Sell?"
		else:
			_sell_armed = false
			cmd_sell.emit(_menu_pad)
	)
	ihb.add_child(_insp_sell)


func _build_audio_overlay() -> void:
	audio_backdrop = ColorRect.new()
	audio_backdrop.name = "audio_backdrop"
	audio_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	audio_backdrop.color = Color(0.01, 0.012, 0.03, 0.62)
	audio_backdrop.visible = false
	audio_backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close_audio_overlay()
	)
	add_child(audio_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_backdrop.add_child(center)

	audio_overlay = PanelContainer.new()
	audio_overlay.name = "audio_overlay"
	audio_overlay.custom_minimum_size = Vector2(340, 0)
	var style_modal := _style_plate.duplicate()
	style_modal.bg_color = Color(0.055, 0.06, 0.09, 0.96)
	style_modal.border_color = Color(0.84, 0.65, 0.30, 0.85)
	style_modal.set_border_width_all(2)
	style_modal.set_content_margin_all(16)
	audio_overlay.add_theme_stylebox_override("panel", style_modal)
	center.add_child(audio_overlay)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	audio_overlay.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)

	var title := _mk_stat_lbl("AUDIO SETTINGS", Color(0.95, 0.78, 0.36))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 28)
	_style_button(close_btn)
	close_btn.pressed.connect(func() -> void: close_audio_overlay())
	head.add_child(close_btn)

	var vol_row := HBoxContainer.new()
	vb.add_child(vol_row)

	var vol_lbl := _mk_stat_lbl("Master Volume", Color(0.94, 0.89, 0.80))
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_row.add_child(vol_lbl)

	_audio_vol_lbl = _mk_stat_lbl("100%", Color(0.95, 0.78, 0.36))
	vol_row.add_child(_audio_vol_lbl)

	_audio_slider = HSlider.new()
	_audio_slider.min_value = 0.0
	_audio_slider.max_value = 100.0
	_audio_slider.step = 1.0
	_audio_slider.value = 100.0
	_audio_slider.custom_minimum_size = Vector2(300, 24)
	_audio_slider.value_changed.connect(func(val: float) -> void:
		if _audio_syncing:
			return
		cmd_volume_changed.emit(clampf(val / 100.0, 0.0, 1.0))
	)
	vb.add_child(_audio_slider)

	_audio_mute_btn = Button.new()
	_audio_mute_btn.text = "Mute Audio [M]"
	_audio_mute_btn.custom_minimum_size = Vector2(0, 38)
	_style_button(_audio_mute_btn)
	_audio_mute_btn.pressed.connect(func() -> void: cmd_toggle_mute.emit())
	vb.add_child(_audio_mute_btn)

	var hint := _mk_stat_lbl("Shortcuts: [O] Menu  •  [M] Mute  •  [Esc] Close", Color(0.65, 0.62, 0.56))
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)


func _mk_stat_lbl(txt: String, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 14)
	return l


# ============================================================================
# External State Updates from game.gd
# ============================================================================

func set_best_wave(bw: int) -> void:
	_best_wave = bw


func dismiss_title() -> void:
	_title_visible = false


func is_pointer_over_ui(pos: Vector2) -> bool:
	if audio_backdrop != null and audio_backdrop.visible:
		return true
	for p in [top_left, top_center, top_right, bottom_bar, build_panel, inspect_panel]:
		if p != null and p.visible and p.get_global_rect().has_point(pos):
			return true
	return false


func is_audio_overlay_open() -> bool:
	return audio_backdrop != null and audio_backdrop.visible


func open_audio_overlay() -> void:
	if audio_backdrop != null:
		audio_backdrop.visible = true


func close_audio_overlay() -> void:
	if audio_backdrop != null:
		audio_backdrop.visible = false


func toggle_audio_overlay() -> void:
	if is_audio_overlay_open():
		close_audio_overlay()
	else:
		open_audio_overlay()


func sync_audio_controls(vol: float, muted_on: bool) -> void:
	var pct := int(round(clampf(vol, 0.0, 1.0) * 100.0))
	_audio_syncing = true
	if _audio_slider != null:
		_audio_slider.value = float(pct)
	_audio_syncing = false
	if _audio_vol_lbl != null:
		_audio_vol_lbl.text = "%d%%" % pct
	if _audio_mute_btn != null:
		_audio_mute_btn.text = "Unmute Audio [M]" if muted_on else "Mute Audio [M]"
	if btn_mute != null:
		btn_mute.text = "Muted [O]" if (muted_on or pct == 0) else ("Audio %d%% [O]" % pct)


func open_build_menu(pad_idx: int, screen_pos: Vector2, gold: int) -> void:
	_menu_pad = pad_idx
	_menu_mode = "build"
	_sell_armed = false
	inspect_panel.visible = false
	build_panel.visible = true
	_position_popup(build_panel, screen_pos)
	refresh_menu_gold(gold)


func open_inspect_menu(pad_idx: int, screen_pos: Vector2, tower_node: Node, gold: int) -> void:
	_menu_pad = pad_idx
	_menu_mode = "inspect"
	_sell_armed = false
	build_panel.visible = false
	inspect_panel.visible = true
	_refresh_inspect(tower_node, gold)
	_position_popup(inspect_panel, screen_pos)


func close_menus() -> void:
	_menu_pad = -1
	_menu_mode = ""
	_sell_armed = false
	build_panel.visible = false
	inspect_panel.visible = false
	cmd_close_menu.emit()


func refresh_menu_gold(gold: int, tower_node: Node = null) -> void:
	if _menu_mode == "build":
		for k in _build_btns:
			var btn: Button = _build_btns[k]
			var cost := int(Defs.TOWERS[k][0]["cost"])
			btn.disabled = gold < cost
	elif _menu_mode == "inspect" and tower_node != null:
		_refresh_inspect(tower_node, gold)


func _refresh_inspect(tw: Node, gold: int) -> void:
	var lvl: int = int(tw.level)
	var st: Dictionary = tw.stats
	var stars := "★".repeat(lvl + 1) + "☆".repeat(2 - lvl)
	_insp_title.text = "%s  %s" % [String(st["name"]), stars]
	if String(tw.kind) == "guard":
		_insp_stats.text = "Footmen: %d  |  HP: %d  |  DMG: %d  |  Range: %.1f" % [int(st["count"]), int(st["hp"]), int(st["dmg"]), float(st["range"])]
	else:
		_insp_stats.text = "DMG: %d  |  Rate: %.1f/s  |  Range: %.1f" % [int(st["dmg"]), float(st["rate"]), float(st["range"])]

	var nxt: Dictionary = tw.get_next_stats()
	if nxt.is_empty():
		_insp_next.text = "Max Level Reached"
		_insp_upg.text = "MAX LEVEL"
		_insp_upg.disabled = true
	else:
		if String(tw.kind) == "guard":
			_insp_next.text = "Next: %d Footmen, %d HP, %d DMG" % [int(nxt["count"]), int(nxt["hp"]), int(nxt["dmg"])]
		else:
			_insp_next.text = "Next: %d DMG, %.1f/s, %.1f Range" % [int(nxt["dmg"]), float(nxt["rate"]), float(nxt["range"])]
		var cost := int(nxt["cost"])
		_insp_upg.text = "Upgrade (%dg) [U]" % cost
		_insp_upg.disabled = gold < cost or bool(tw.building)

	if not _sell_armed:
		_insp_sell.text = "Sell (+%dg) [S]" % int(tw.get_sell_value())


func _position_popup(panel: Control, screen_pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var sz := panel.get_combined_minimum_size()
	if sz.x < 120.0:
		sz = Vector2(305, 145)
	var px := clampf(screen_pos.x - sz.x * 0.5, 16.0, vp.x - sz.x - 16.0)
	var py := screen_pos.y - sz.y - 26.0
	if py < 72.0:
		py = screen_pos.y + 32.0
	py = clampf(py, 72.0, vp.y - sz.y - 68.0)
	panel.position = Vector2(px, py)


func update_stats(lives: int, max_lives: int, gold: int, slain: int, biome_name: String, wave: int, wave_prog: float, call_bonus: int, ai_on: bool, paused: bool, speed_val: float, muted_on: bool, manual_cam: bool) -> void:
	if gold > _last_gold:
		_gold_bump = 1.0
	_last_gold = gold
	lbl_lives.text = "🔥 %d/%d" % [lives, max_lives]
	lbl_gold.text = "● %dg" % gold
	lbl_slain.text = "☠ %d" % slain
	lbl_biome.text = biome_name.to_upper()
	lbl_wave.text = "WAVE %d" % maxi(1, wave)
	bar_wave.value = clampf(wave_prog, 0.0, 1.0)

	btn_call.visible = call_bonus > 0
	if call_bonus > 0:
		btn_call.text = "Call +%dg [Space]" % call_bonus

	btn_ai.text = "AI Commander [C]" if ai_on else "You Command [C]"
	btn_pause.text = "Resume [P]" if paused else "Pause [P]"
	btn_speed.text = "%dx [Tab]" % int(round(speed_val))
	btn_follow.visible = manual_cam


func show_banner(title: String, sub: String = "", col: Color = Color(1.0, 0.84, 0.48), dur: float = 2.8) -> void:
	_banners.append({"title": title, "sub": sub, "col": col, "age": 0.0, "life": dur})


func show_tip(title: String, body: String, is_boss: bool = false) -> void:
	_tip = {
		"title": ("BOSS: " if is_boss else "NEW FOE: ") + title,
		"body": body,
		"col": Color(1.0, 0.42, 0.28) if is_boss else Color(0.95, 0.82, 0.48),
		"age": 0.0,
		"life": 5.2 if is_boss else 4.2,
	}


func spawn_flying_coin(screen_pos: Vector2) -> void:
	if _fly_coins.size() >= 36:
		return
	var target := lbl_gold.global_position + Vector2(24.0, 10.0)
	_fly_coins.append({"p0": screen_pos, "p1": target, "age": 0.0, "dur": 0.55 + randf() * 0.18})


func set_hp_bars(bars: Array[Dictionary]) -> void:
	_hp_bars = bars


func step_hud(dt: float) -> void:
	_t += dt
	_gold_bump = maxf(0.0, _gold_bump - dt * 3.5)
	lbl_gold.add_theme_color_override("font_color", Color(0.98, 0.82, 0.36).lerp(Color(1.0, 1.0, 0.85), _gold_bump))

	if _title_visible:
		_title_t += dt
		if _title_t > 4.6:
			_title_visible = false

	if _sell_armed:
		_sell_timer -= dt
		if _sell_timer <= 0.0:
			_sell_armed = false

	var i := _banners.size() - 1
	while i >= 0:
		_banners[i]["age"] = float(_banners[i]["age"]) + dt
		if float(_banners[i]["age"]) >= float(_banners[i]["life"]):
			_banners.remove_at(i)
		i -= 1

	if not _tip.is_empty():
		_tip["age"] = float(_tip["age"]) + dt
		if float(_tip["age"]) >= float(_tip["life"]):
			_tip.clear()

	i = _fly_coins.size() - 1
	while i >= 0:
		_fly_coins[i]["age"] = float(_fly_coins[i]["age"]) + dt
		if float(_fly_coins[i]["age"]) >= float(_fly_coins[i]["dur"]):
			_fly_coins.remove_at(i)
			_gold_bump = 1.0
		i -= 1

	overlay.queue_redraw()


# ============================================================================
# Custom 2D Overlay Rendering (HP Bars, Boss Plates, Flying Coins, Banners, Title)
# ============================================================================

func _on_overlay_draw() -> void:
	var font := ThemeDB.fallback_font
	var vp := overlay.get_viewport_rect().size

	# 1. 3D-projected Unit & Boss Health Bars
	for hb in _hp_bars:
		var p: Vector2 = hb["pos"]
		var f := clampf(float(hb["frac"]), 0.0, 1.0)
		var is_boss: bool = bool(hb["boss"])
		var is_ally: bool = bool(hb.get("ally", false))
		var w := 112.0 if is_boss else 34.0
		var h := 8.0 if is_boss else 4.5
		var r := Rect2(p.x - w * 0.5, p.y - h, w, h)
		overlay.draw_rect(r.grow(1.5), Color(0.03, 0.03, 0.05, 0.86))
		var fill_c := Color(0.32, 0.86, 0.45) if is_ally else (Color(0.95, 0.24, 0.16) if is_boss else Color(0.92, 0.32, 0.22))
		if bool(hb.get("slow", false)):
			fill_c = Color(0.45, 0.84, 1.0)
		overlay.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), fill_c)
		if is_boss:
			overlay.draw_rect(r.grow(1.5), Color(0.92, 0.72, 0.34, 0.9), false, 1.5)
			var bname: String = String(hb.get("name", "BOSS"))
			overlay.draw_string(font, Vector2(p.x - w * 0.5, p.y - h - 5.0), bname, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1.0, 0.88, 0.56))

	# 2. 2D Flying Gold Coins arcing to top-left counter
	for fc in _fly_coins:
		var u := clampf(float(fc["age"]) / float(fc["dur"]), 0.0, 1.0)
		var p0: Vector2 = fc["p0"]
		var p1: Vector2 = fc["p1"]
		var mid := (p0 + p1) * 0.5 + Vector2(0.0, -75.0)
		var q0 := p0.lerp(mid, u)
		var q1 := mid.lerp(p1, u)
		var pos := q0.lerp(q1, u)
		overlay.draw_circle(pos, 5.5, Color(1.0, 0.82, 0.26, 1.0 - u * 0.2))
		overlay.draw_circle(pos, 2.8, Color(1.0, 0.96, 0.78, 1.0 - u * 0.2))

	# 3. First-Seen Monster Tip Toast (bottom-left above bar)
	if not _tip.is_empty():
		var u := float(_tip["age"]) / float(_tip["life"])
		var al := minf(1.0, u * 5.0) * minf(1.0, (1.0 - u) * 4.5)
		var box := Rect2(16.0, vp.y - 124.0, 340.0, 56.0)
		overlay.draw_rect(box, Color(0.05, 0.055, 0.08, 0.86 * al))
		overlay.draw_rect(box, Color(0.76, 0.58, 0.28, 0.65 * al), false, 1.0)
		var tc: Color = _tip["col"]
		overlay.draw_string(font, box.position + Vector2(12, 22), String(_tip["title"]), HORIZONTAL_ALIGNMENT_LEFT, 316, 14, Color(tc.r, tc.g, tc.b, al))
		overlay.draw_string(font, box.position + Vector2(12, 42), String(_tip["body"]), HORIZONTAL_ALIGNMENT_LEFT, 316, 12, Color(0.88, 0.86, 0.82, al))

	# 4. Dramatic Center Banners (Wave / Boss / Biome / Clear / Defeat)
	if _banners.size() > 0:
		var b: Dictionary = _banners[_banners.size() - 1]
		var u := float(b["age"]) / float(b["life"])
		var al := minf(1.0, u * 4.5) * minf(1.0, (1.0 - u) * 3.2)
		var cy := vp.y * 0.22
		var c: Color = b["col"]
		overlay.draw_rect(Rect2(vp.x * 0.5 - 220, cy - 30, 440, 66), Color(0.04, 0.04, 0.06, 0.68 * al))
		overlay.draw_line(Vector2(vp.x * 0.5 - 180, cy - 28), Vector2(vp.x * 0.5 + 180, cy - 28), Color(c.r, c.g, c.b, 0.7 * al), 1.5)
		overlay.draw_line(Vector2(vp.x * 0.5 - 180, cy + 34), Vector2(vp.x * 0.5 + 180, cy + 34), Color(c.r, c.g, c.b, 0.7 * al), 1.5)
		overlay.draw_string(font, Vector2(vp.x * 0.5 - 220, cy + 4), String(b["title"]), HORIZONTAL_ALIGNMENT_CENTER, 440, 26, Color(c.r, c.g, c.b, al))
		if String(b["sub"]) != "":
			overlay.draw_string(font, Vector2(vp.x * 0.5 - 220, cy + 25), String(b["sub"]), HORIZONTAL_ALIGNMENT_CENTER, 440, 13, Color(0.92, 0.88, 0.80, al))

	# 5. Opening Title Card
	if _title_visible:
		var al := minf(1.0, _title_t * 2.0) * (1.0 - smoothstep(3.6, 4.6, _title_t))
		var cy := vp.y * 0.36
		overlay.draw_string(font, Vector2(vp.x * 0.5 - 260, cy), "CINDERWATCH", HORIZONTAL_ALIGNMENT_CENTER, 520, 44, Color(1.0, 0.82, 0.44, al))
		overlay.draw_line(Vector2(vp.x * 0.5 - 140, cy + 12), Vector2(vp.x * 0.5 + 140, cy + 12), Color(1.0, 0.58, 0.22, 0.8 * al), 2.0)
		var sub_txt := "Hold the beacon against the dark"
		if _best_wave > 0:
			sub_txt += "   •   Best run: Wave %d" % _best_wave
		overlay.draw_string(font, Vector2(vp.x * 0.5 - 260, cy + 36), sub_txt, HORIZONTAL_ALIGNMENT_CENTER, 520, 14, Color(0.90, 0.86, 0.78, al * 0.92))
