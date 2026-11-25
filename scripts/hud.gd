extends CanvasLayer

const Defs := preload("res://scripts/defs.gd")

## 全部 UI 由代码拼出来（原版的 HUD 也是 canvas 画的），没有额外字体/贴图资源。

var game = null

const BG := Color("0d1014")
const BORDER := Color("e8b04a")
const TEXT := Color("e6dcc4")
const DIM := Color("9a9280")
const BAD := Color("d04a3a")

var gold_label: Label
var lives_label: Label
var wave_label: Label
var best_label: Label
var log_box: VBoxContainer
var banner_label: Label
var build_panel: PanelContainer
var build_buttons: Array = []
var build_title: Label
var tower_panel: PanelContainer
var tower_title: Label
var tower_stats: Label
var upgrade_btn: Button
var sell_btn: Button
var ai_btn: Button
var speed_btn: Button
var pause_btn: Button
var wave_btn: Button
var current_pad: Dictionary = {}
var current_tower = null
var log_lines: Array = []
var _banner_tween: Tween = null

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top_left(root)
	_build_top_right(root)
	_build_log(root)
	_build_banner(root)
	_build_build_panel(root)
	_build_tower_panel(root)
	_build_wave_button(root)

func _style(alpha := 0.86) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BG.r, BG.g, BG.b, alpha)
	sb.border_color = Color(BORDER.r, BORDER.g, BORDER.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _label(text: String, size: int, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func _button(text: String, cb: Callable, w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color("ffe2a0"))
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.45, 0.7))
	b.pressed.connect(cb)
	if w > 0:
		b.custom_minimum_size = Vector2(w, 36)
	return b

func _build_top_left(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(14, 12)
	root.add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	gold_label = _label("金 120", 20, Color("ffd27a"))
	lives_label = _label("信标 20/20", 20, Color("ff9a6a"))
	wave_label = _label("第 1 波", 20)
	best_label = _label("最好 0", 16, DIM)
	box.add_child(gold_label)
	box.add_child(lives_label)
	box.add_child(wave_label)
	box.add_child(best_label)

func _build_top_right(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -302
	panel.offset_right = -14
	panel.offset_top = 12
	panel.offset_bottom = 12
	root.add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	ai_btn = _button("AI 指挥", Callable(self, "_on_ai"), 110)
	speed_btn = _button("1x", Callable(self, "_on_speed"), 54)
	pause_btn = _button("暂停", Callable(self, "_on_pause"), 66)
	box.add_child(ai_btn)
	box.add_child(speed_btn)
	box.add_child(pause_btn)

func _on_ai() -> void:
	if game != null:
		game.toggle_ai()

func _on_speed() -> void:
	if game != null:
		game.speed = 1 if game.speed == 3 else game.speed + 1

func _on_pause() -> void:
	if game != null:
		game.paused = not game.paused
		toast("暂停" if game.paused else "继续")

func _build_log(root: Control) -> void:
	var wrap := VBoxContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	wrap.position = Vector2(16, -150)
	wrap.custom_minimum_size = Vector2(560, 0)
	wrap.add_theme_constant_override("separation", 2)
	root.add_child(wrap)
	log_box = wrap

func _build_banner(root: Control) -> void:
	banner_label = _label("", 34, Color("ffe2a0"))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.anchor_left = 0.0
	banner_label.anchor_right = 1.0
	banner_label.offset_top = 118
	banner_label.offset_bottom = 170
	banner_label.offset_left = 0
	banner_label.offset_right = 0
	banner_label.modulate = Color(1, 1, 1, 0)
	root.add_child(banner_label)

func _build_build_panel(root: Control) -> void:
	build_panel = PanelContainer.new()
	build_panel.add_theme_stylebox_override("panel", _style())
	build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_panel.offset_left = -330
	build_panel.offset_right = 330
	build_panel.offset_top = -118
	build_panel.offset_bottom = -18
	build_panel.visible = false
	root.add_child(build_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	build_panel.add_child(box)
	build_title = _label("选择要建的塔（悬停预览射程，按 1-4 也可）", 15, DIM)
	box.add_child(build_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var kinds := Defs.TOWER_KINDS
	for i in kinds.size():
		var kind: String = kinds[i]
		var b := _button("%d  %s\n%d 金" % [i + 1, String(Defs.TOWER[kind]["name"]), int(Defs.TOWER[kind]["cost"][0])], _make_build_cb(kind), 150)
		b.custom_minimum_size = Vector2(150, 58)
		b.mouse_entered.connect(_hover_build.bind(kind))
		b.mouse_exited.connect(_unhover_build.bind(kind))
		row.add_child(b)
		build_buttons.append({"button": b, "kind": kind})

func _hover_build(kind: String) -> void:
	if game != null:
		game.preview_build(kind)
	for e in build_buttons:
		var b: Button = e["button"]
		b.add_theme_color_override("font_color", Color("ffd27a") if String(e["kind"]) == kind else TEXT)

func _unhover_build(_kind: String) -> void:
	for e in build_buttons:
		var b: Button = e["button"]
		b.add_theme_color_override("font_color", TEXT)

func _on_upgrade() -> void:
	if game != null and current_tower != null:
		game.upgrade_tower(current_tower)

func _on_sell() -> void:
	if game != null and current_tower != null:
		game.sell_tower(current_tower)

func _on_call_wave() -> void:
	if game != null:
		game.call_wave_early()

func _make_build_cb(kind: String) -> Callable:
	return func() -> void:
		if game != null and not current_pad.is_empty():
			game.build_tower(current_pad, kind)

func _build_tower_panel(root: Control) -> void:
	tower_panel = PanelContainer.new()
	tower_panel.add_theme_stylebox_override("panel", _style())
	tower_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tower_panel.offset_left = -260
	tower_panel.offset_right = 260
	tower_panel.offset_top = -128
	tower_panel.offset_bottom = -18
	tower_panel.visible = false
	root.add_child(tower_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	tower_panel.add_child(box)
	tower_title = _label("", 18, Color("ffe2a0"))
	tower_stats = _label("", 14, DIM)
	box.add_child(tower_title)
	box.add_child(tower_stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	upgrade_btn = _button("升级", Callable(self, "_on_upgrade"), 160)
	sell_btn = _button("卖掉", Callable(self, "_on_sell"), 120)
	row.add_child(upgrade_btn)
	row.add_child(sell_btn)

func _build_wave_button(root: Control) -> void:
	wave_btn = _button("叫下一波", Callable(self, "_on_call_wave"), 190)
	wave_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wave_btn.offset_left = -210
	wave_btn.offset_right = -16
	wave_btn.offset_top = -60
	wave_btn.offset_bottom = -20
	root.add_child(wave_btn)

# ---------------------------------------------------------------- 对外

func set_stats(g) -> void:
	if g == null:
		return
	gold_label.text = "金 %d" % g.gold
	lives_label.text = "信标 %d/%d" % [g.lives, g.max_lives]
	wave_label.text = g.wave_label()
	best_label.text = "最好 %d" % g.best_wave
	ai_btn.text = "AI 指挥" if g.ai_active else "你来指挥"
	ai_btn.add_theme_color_override("font_color", Color("ffd27a") if g.ai_active else Color("8fe0ff"))
	speed_btn.text = "%dx" % g.speed
	pause_btn.text = "继续" if g.paused else "暂停"
	var early := int(round(maxf(0.0, g.next_in) * 3.0))
	wave_btn.text = "叫下一波 +%d 金" % early if (not g.spawning and not g.boss_wave and g.phase == "play") else "波次进行中"
	wave_btn.disabled = g.spawning or g.boss_wave or g.phase != "play"
	if not current_pad.is_empty() and build_panel.visible:
		for entry in build_buttons:
			var kind: String = entry["kind"]
			var cost: int = int(Defs.TOWER[kind]["cost"][0])
			var b: Button = entry["button"]
			b.disabled = g.gold < cost
	if current_tower != null and is_instance_valid(current_tower) and tower_panel.visible:
		_update_tower_panel(g)

func open_build(pad: Dictionary) -> void:
	current_pad = pad
	current_tower = null
	tower_panel.visible = false
	build_panel.visible = true
	build_title.text = "选择要建的塔（悬停预览射程，按 1-4 也可）"
	if game != null:
		set_stats(game)

func open_tower(t) -> void:
	current_tower = t
	current_pad = {}
	build_panel.visible = false
	tower_panel.visible = true
	if game != null:
		_update_tower_panel(game)

func _update_tower_panel(g) -> void:
	var t = current_tower
	if t == null or not is_instance_valid(t):
		tower_panel.visible = false
		return
	var st: Dictionary = t.stats()
	tower_title.text = "%s  Lv %d" % [String(t.def["name"]), int(t.lvl) + 1]
	tower_stats.text = "射程 %.1f · 伤害 %.0f · 间隔 %.2fs%s" % [float(st["range"]), float(st["dmg"]), float(st["rate"]),
		(" · 溅射 %.1f" % float(st["splash"])) if st.has("splash") else (" · 连锁 %d" % int(st["jumps"])) if st.has("jumps") else ""]
	if t.can_upgrade():
		var c: int = t.upgrade_cost()
		upgrade_btn.text = "升级 → Lv %d（%d 金）" % [int(t.lvl) + 2, c]
		upgrade_btn.disabled = g.gold < c
	else:
		upgrade_btn.text = "已满级"
		upgrade_btn.disabled = true
	sell_btn.text = "卖掉 +%d 金" % t.sell_refund()

func close_menus() -> void:
	build_panel.visible = false
	tower_panel.visible = false
	current_pad = {}
	current_tower = null

func toast(msg: String) -> void:
	var l := _label(msg, 14, TEXT)
	log_box.add_child(l)
	log_lines.append(l)
	while log_lines.size() > 4:
		var old: Label = log_lines.pop_front()
		old.queue_free()

func banner(text: String, boss: bool) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", Color("ff7a5a") if boss else Color("ffe2a0"))
	banner_label.modulate = Color(1, 1, 1, 1)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.6)
	_banner_tween.tween_property(banner_label, "modulate", Color(1, 1, 1, 0), 1.4)

func flash_lives() -> void:
	lives_label.modulate = Color(1.6, 0.6, 0.4, 1)
	var tw := create_tween()
	tw.tween_property(lives_label, "modulate", Color(1, 1, 1, 1), 0.5)
