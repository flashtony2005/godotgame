extends Node3D

## 高模版怪：18 种类型共用 9 套精细骨架（人形 / 四足 / 史莱姆 / 虫 / 飞行 / 怨灵 / 蟾蜍 / 灵体 / 石像）。
## 每一只都是 Soup 现拼的网格：两段式四肢、关节、装备、布料都有单独部件，行走/挥击靠枢轴旋转。

const Defs := preload("res://scripts/defs.gd")
const MeshKit := preload("res://scripts/meshkit.gd")
const Soup := preload("res://scripts/soup.gd")
const IRON_D := Color("3c4048")

var type := "skel"
var def: Dictionary = {}
var hp := 1.0
var max_hp := 1.0
var s := 0.0
var lateral := 0.0
var base_speed := 1.0
var speed_mul := 1.0
var slow_amt := 0.0
var slow_t := 0.0
var haste := 1.0
var flying := false
var alt := 0.0
var side := 0.0
var alive := true
var radius := 0.3
var body_root: Node3D
var parts: Dictionary = {}
var hpbar: Node3D
var hpfill: MeshInstance3D
var t := 0.0
var flash := 0.0
var atk_cd := 0.5
var sum_t := 0.0
var stomp_t := 0.0
var ghost_t := 0.0
var ghosting := false
var enraged := false
var boss := false
var yaw := 0.0
var last_hit := -9.0
var hit_by_guard := false
var game = null

const SKIN := {
	"skel": Color("d8d2c0"), "slime": Color("6ac07a"), "slimelet": Color("7ad08a"),
	"knight": Color("8a92a0"), "ghoul": Color("8c7a86"), "spider": Color("3a3236"),
	"scarab": Color("4a3a24"), "wolf": Color("6a5a4a"), "bomber": Color("8a6a58"),
	"wraith": Color("a8d8d0"), "toad": Color("5a7048"), "wisp": Color("c8b0ff"),
	"drummer": Color("7a6a58"), "gargoyle": Color("7a7264"), "necro": Color("5a4a6a"),
	"mummy": Color("c8b490"), "brute": Color("7a9a5a"), "golem": Color("7a7a72"),
	"brood": Color("5a3a48"), "giant": Color("d8d2c0"), "ogre": Color("8a7a4a"),
	"jotun": Color("a8c8e8"), "queen": Color("6a3a6a"), "colossus": Color("5a3a30"),
	"king": Color("c8b078"),
}

func setup(p_type: String, hp_mul: float, p_s: float, p_lat: float, p_game) -> void:
	type = p_type
	def = Defs.MON[type]
	game = p_game
	max_hp = float(def["hp"]) * hp_mul
	hp = max_hp
	s = p_s
	lateral = p_lat
	base_speed = float(def["spd"]) * randf_range(0.93, 1.07)
	radius = float(def["rad"])
	flying = def.get("fly", false)
	boss = def.get("boss", false)
	if flying:
		alt = randf_range(float(def["alt"][0]), float(def["alt"][1]))
		side = randf_range(-1.1, 1.1) * (1.4 if def.has("glow") else 1.0)
	sum_t = float(def.get("summon", {}).get("every", 7.0)) * randf_range(0.45, 0.7) if def.has("summon") else 0.0
	stomp_t = float(def.get("stomp", {}).get("every", 10.0)) * 0.6 if def.has("stomp") else 0.0
	atk_cd = randf_range(0.1, 0.5)
	_build_body()
	_build_hpbar()

func _build_hpbar() -> void:
	hpbar = Node3D.new()
	hpbar.position = Vector3(0, float(def["top"]) * float(def["scale"]) + 0.35, 0)
	add_child(hpbar)
	MeshKit.box(hpbar, Vector3(0.62, 0.08, 0.02), Vector3.ZERO, Color("141018"))
	hpfill = MeshKit.box(hpbar, Vector3(0.6, 0.055, 0.03), Vector3(0, 0, 0.01), Color("e8b04a"))
	hpbar.visible = boss

func _skin() -> Color:
	var base: Color = SKIN.get(type, Defs.MON_COL["flesh"])
	var tint: Dictionary = Defs.TINTS.get(game.biome_key, {})
	if tint.has(type):
		base = base * tint[type]
	return base

func _build_body() -> void:
	body_root = Node3D.new()
	var sc := float(def["scale"])
	body_root.scale = Vector3.ONE * sc
	add_child(body_root)
	var c := _skin()
	var top := float(def["top"])
	match String(def["body"]):
		"humanoid": _humanoid(c, top)
		"quad": _quad(c, top)
		"blob": _blob(c, top)
		"bug": _bug(c, top)
		"bat": _bat(c)
		"ghost": _ghost(c)
		"toad": _toad(c)
		"wisp": _wisp(c)
		"golem": _golem(c, top)
		_: _humanoid(c, top)
	if def.has("glow"):
		var light := OmniLight3D.new()
		light.light_color = game.biome_wisp_color
		light.light_energy = 1.2
		light.omni_range = 2.6
		add_child(light)

func _glow_dot(parent: Node3D, pos: Vector3, r: float, col: Color) -> void:
	var mi := MeshKit.sphere(parent, r, pos, col, 6, 2.4)
	if mi != null:
		mi.material_override = MeshKit.mat(col, 2.4, 0.5)

func _eye_color() -> Color:
	if type == "ghoul":
		return Color("ff5a2a")
	if type == "brute":
		return Color("ffd24a")
	return Defs.MON_COL["eye"]

# ---------------------------------------------------------------- 人形

func _humanoid(c: Color, top: float) -> void:
	var leg_h := top * 0.42
	var torso_h := top * 0.34
	var head_r := top * 0.11
	var leg_c := c.darkened(0.28)
	var skin_c := c
	if type == "skel" or type == "giant" or type == "king":
		skin_c = Color("cfc8b4")
	if type == "knight":
		skin_c = Color("7d848f")
	# 骨盆
	var s := Soup.new()
	s.beam(Vector3(0, leg_h, 0), Vector3(0, leg_h + torso_h * 0.22, 0), top * 0.15, top * 0.14, 6, skin_c.darkened(0.1))
	# 袍 / 胸甲 / 缠布
	match type:
		"knight":
			s.box(Vector3(0, leg_h + torso_h * 0.6, 0), Vector3(top * 0.32, torso_h * 0.68, top * 0.22), Color("9aa4b4"), Basis.IDENTITY, 0.8, 1.0)
			s.box(Vector3(0, leg_h + torso_h * 0.55, 0), Vector3(top * 0.34, torso_h * 0.12, top * 0.24), Color("c8d0d8"))
			s.sphere(Vector3(-top * 0.2, leg_h + torso_h * 0.92, 0), top * 0.11, Color("9aa4b4"), 8, 5, Vector3(1.2, 0.8, 1.1), 0.8, 1.0)
			s.sphere(Vector3(top * 0.2, leg_h + torso_h * 0.92, 0), top * 0.11, Color("9aa4b4"), 8, 5, Vector3(1.2, 0.8, 1.1), 0.8, 1.0)
			s.cyl(Vector3(0, leg_h + torso_h + head_r * 1.05, 0), head_r * 1.05, head_r * 1.05, head_r * 1.5, Color("8a92a0"), 8, 0.0, 0.75, 1.0)
			s.box(Vector3(0, leg_h + torso_h + head_r * 0.95, head_r * 0.8), Vector3(head_r * 1.4, head_r * 0.35, head_r * 0.18), IRON_D)
		"necro":
			s.cone(Vector3(0, 0.02, 0), top * 0.31, leg_h + torso_h * 1.3, c.darkened(0.42), 8, 0.0, 0.45)
			s.sphere(Vector3(0, leg_h + torso_h * 0.7, 0), top * 0.15, Color("c8b490"), 8, 5, Vector3(1, 1.2, 0.8), 0.8)
			s.cone(Vector3(0, leg_h + torso_h + head_r * 1.4, 0), head_r * 1.5, head_r * 2.6, c.darkened(0.55), 7)
		"mummy":
			for k in 5:
				s.box(Vector3(0, leg_h + torso_h * (0.12 + 0.19 * float(k)), 0), Vector3(top * 0.33, top * 0.045, top * 0.24), Color("a89870"), Basis(Vector3.RIGHT, 0.1 * float(k % 2)))
			s.cone(Vector3(0, 0.05, 0), top * 0.26, leg_h * 0.95, Color("b8a880"), 7, 0.0, 0.5)
		"drummer":
			s.beam(Vector3(0, leg_h, 0), Vector3(0, leg_h + torso_h, 0), top * 0.17, top * 0.15, 6, c)
			s.sphere(Vector3(0, leg_h + torso_h * 0.55, 0), top * 0.16, c.darkened(0.15), 8, 5, Vector3(1, 1.1, 0.85), 0.75)
		"brute", "ogre":
			s.sphere(Vector3(0, leg_h + torso_h * 0.55, 0), top * 0.26, c.lightened(0.12), 10, 6, Vector3(1.05, 0.95, 0.9), 0.6, 1.0)
			s.box(Vector3(0, leg_h + torso_h * 0.85, 0), Vector3(top * 0.4, top * 0.12, top * 0.3), c.darkened(0.2))
		"king":
			s.beam(Vector3(0, leg_h, 0), Vector3(0, leg_h + torso_h, 0), top * 0.18, top * 0.16, 6, Color("a89878"))
			s.box(Vector3(0, leg_h + torso_h * 0.7, 0), Vector3(top * 0.36, torso_h * 0.6, top * 0.26), Color("6a4a7a"), Basis.IDENTITY, 0.8)
			for k in 5:
				var a := TAU * float(k) / 5.0
				s.cone(Vector3(cos(a) * head_r * 0.75, leg_h + torso_h + head_r * 1.75, sin(a) * head_r * 0.75), head_r * 0.28, head_r * 0.9, Color("e8c860"), 4)
		_:
			s.beam(Vector3(0, leg_h, 0), Vector3(0, leg_h + torso_h, 0), top * 0.16, top * 0.13, 6, skin_c)
			# 肋骨
			for k in 4:
				var yy := leg_h + torso_h * (0.35 + 0.16 * float(k))
				s.box(Vector3(0, yy, 0), Vector3(top * 0.26 - top * 0.03 * float(k), top * 0.025, top * 0.18), skin_c.lightened(0.1))
			s.box(Vector3(0, leg_h + torso_h * 0.95, 0), Vector3(top * 0.34, top * 0.05, top * 0.2), skin_c.darkened(0.15))
	# 脖子 + 头
	var head_y := leg_h + torso_h + head_r * 1.15
	s.cyl(Vector3(0, leg_h + torso_h + head_r * 0.35, 0), head_r * 0.62, head_r * 0.55, head_r * 0.7, skin_c.darkened(0.15), 6)
	s.sphere(Vector3(0, head_y, 0), head_r, skin_c.lightened(0.05), 10, 7, Vector3(1.0, 1.06, 1.12), 0.7, 1.0)
	s.box(Vector3(0, head_y - head_r * 0.55, head_r * 0.28), Vector3(head_r * 0.9, head_r * 0.45, head_r * 0.7), skin_c.darkened(0.12))
	for sx in [-1.0, 1.0]:
		s.box(Vector3(sx * head_r * 0.34, head_y + head_r * 0.1, head_r * 0.82), Vector3(head_r * 0.34, head_r * 0.3, head_r * 0.16), Color("181418"))
	if type == "brute" or type == "ogre":
		for sx in [-1.0, 1.0]:
			s.cone(Vector3(sx * head_r * 0.45, head_y - head_r * 0.35, head_r * 0.7), head_r * 0.13, head_r * 0.5, Color("e8e0c8"), 4, 0.0, 0.8)
	if type == "king":
		s.cone(Vector3(0, head_y + head_r * 0.85, 0), head_r * 0.9, head_r * 1.4, Color("8a2f4a"), 7)
	# 眼
	var eye_c := _eye_color()
	for sx in [-1.0, 1.0]:
		_glow_dot(body_root, Vector3(sx * head_r * 0.3, head_y + head_r * 0.12, head_r * 0.78), head_r * 0.17, eye_c)
	# 腿（髋枢轴，两段）
	for sx in [-1.0, 1.0]:
		var hip := MeshKit.pivot(body_root, Vector3(sx * top * 0.09, leg_h, 0))
		var ls := Soup.new()
		ls.beam(Vector3(0, 0, 0), Vector3(0, -leg_h * 0.52, 0.01), top * 0.075, top * 0.06, 6, leg_c)
		ls.sphere(Vector3(0, -leg_h * 0.53, 0.01), top * 0.062, leg_c.lightened(0.08), 8, 5)
		ls.beam(Vector3(0, -leg_h * 0.53, 0.01), Vector3(0, -leg_h * 0.96, 0.03), top * 0.055, top * 0.045, 6, leg_c)
		ls.box(Vector3(0, -leg_h * 0.99, top * 0.05), Vector3(top * 0.13, top * 0.06, top * 0.22), leg_c.darkened(0.35), Basis.IDENTITY, 0.6, 0.9)
		ls.instance(hip, "leg")
		parts["legL" if sx < 0.0 else "legR"] = hip
	# 手臂（肩枢轴）
	for sx in [-1.0, 1.0]:
		var sh := MeshKit.pivot(body_root, Vector3(sx * top * 0.19, leg_h + torso_h * 0.88, 0))
		var as_ := Soup.new()
		as_.sphere(Vector3(0, 0, 0), top * 0.075, skin_c.lightened(0.12), 8, 5)
		as_.beam(Vector3(0, 0, 0), Vector3(sx * top * 0.02, -torso_h * 0.5, top * 0.02), top * 0.065, top * 0.052, 6, skin_c.darkened(0.08))
		as_.sphere(Vector3(sx * top * 0.02, -torso_h * 0.52, top * 0.02), top * 0.055, skin_c, 7, 5)
		as_.beam(Vector3(sx * top * 0.02, -torso_h * 0.52, top * 0.02), Vector3(sx * top * 0.04, -torso_h * 0.95, top * 0.06), top * 0.05, top * 0.04, 6, skin_c.darkened(0.08))
		as_.sphere(Vector3(sx * top * 0.04, -torso_h * 0.98, top * 0.06), top * 0.05, skin_c.darkened(0.02), 7, 5, Vector3(1, 1.15, 1), 0.6, 1.0)
		# 武器
		if sx > 0.0 and (def.get("boss", false) or type in ["skel", "knight", "giant", "king", "necro", "bomber", "mummy", "ghoul"]):
			var bl := top * 0.62
			as_.box(Vector3(0, -torso_h * 1.0, top * 0.06), Vector3(top * 0.055, top * 0.16, top * 0.05), Color("5a4632"))
			as_.box(Vector3(0, -torso_h * 1.0 - top * 0.08, top * 0.06), Vector3(top * 0.22, top * 0.045, top * 0.05), Color("8a8a92"))
			as_.beam(Vector3(0, -torso_h * 1.0 - top * 0.1, top * 0.06), Vector3(0, -torso_h * 1.0 - top * 0.1 - bl, top * 0.06), top * 0.032, top * 0.008, 4, Color("d8dee8"), 0.0, 0.85, 1.0)
		if type == "drummer":
			as_.beam(Vector3(0, -torso_h * 0.95, 0), Vector3(-top * 0.05, -torso_h * 1.02, top * 0.12), top * 0.02, top * 0.015, 4, Color("c8b490"))
		as_.instance(sh, "arm")
		parts["armL" if sx < 0.0 else "armR"] = sh
	# 鼓
	if type == "drummer":
		s.cyl(Vector3(0, leg_h * 0.55, top * 0.16), top * 0.18, top * 0.2, top * 0.24, Color("8a6a4a"), 8, 0.0, 0.55, 0.95)
		for yy in [-0.1, 0.1]:
			s.cyl(Vector3(0, leg_h * 0.55 + yy, top * 0.16), top * 0.2, top * 0.2, top * 0.03, Color("3a2a1e"), 8)
		s.box(Vector3(0, leg_h * 0.55, top * 0.09), Vector3(top * 0.34, top * 0.02, top * 0.02), Color("3a2a1e"))
	s.instance(body_root, "body")
	# 骑士盾
	if type == "knight":
		var sh2 := Soup.new()
		sh2.beam(Vector3(-top * 0.28, leg_h + torso_h * 0.75, top * 0.02), Vector3(-top * 0.3, leg_h + torso_h * 0.25, top * 0.05), top * 0.16, top * 0.19, 6, Color("5a6470"), 0.0, 0.8, 1.0)
		sh2.box(Vector3(-top * 0.3, leg_h + torso_h * 0.5, top * 0.06), Vector3(top * 0.05, top * 0.2, top * 0.03), Color("c8d0d8"))
		sh2.instance(body_root, "shield")

# ---------------------------------------------------------------- 四足

func _quad(c: Color, top: float) -> void:
	var bl := top * 1.5
	var s := Soup.new()
	# 躯干：胸 + 腰 + 臀三节，收放有致
	s.sphere(Vector3(0, top * 0.42, -bl * 0.3), top * 0.3, c, 10, 6, Vector3(0.9, 0.95, 1.25), 0.6, 1.0)
	s.sphere(Vector3(0, top * 0.42, bl * 0.05), top * 0.27, c.darkened(0.05), 10, 6, Vector3(0.85, 0.9, 1.2), 0.6, 1.0)
	s.sphere(Vector3(0, top * 0.44, bl * 0.4), top * 0.25, c.darkened(0.1), 9, 6, Vector3(0.85, 0.9, 1.0), 0.6, 1.0)
	# 颈 + 头 + 吻 + 耳 + 下颌
	s.beam(Vector3(0, top * 0.5, -bl * 0.5), Vector3(0, top * 0.62, -bl * 0.75), top * 0.19, top * 0.15, 7, c)
	s.sphere(Vector3(0, top * 0.63, -bl * 0.8), top * 0.19, c.lightened(0.08), 10, 6, Vector3(1.0, 0.95, 1.15), 0.65, 1.0)
	s.beam(Vector3(0, top * 0.6, -bl * 0.9), Vector3(0, top * 0.56, -bl * 1.05), top * 0.1, top * 0.075, 5, c.darkened(0.05))
	s.box(Vector3(0, top * 0.53, -bl * 1.0), Vector3(top * 0.11, top * 0.05, top * 0.18), c.darkened(0.3))
	for sx in [-1.0, 1.0]:
		s.cone(Vector3(sx * top * 0.1, top * 0.76, -bl * 0.72), top * 0.055, top * 0.16, c.darkened(0.15), 4, 0.3)
		s.box(Vector3(sx * top * 0.5, top * 0.44, -bl * 0.35), Vector3(top * 0.1, top * 0.24, top * 0.3), c.darkened(0.18))
	_glow_dot(body_root, Vector3(top * 0.09, top * 0.68, -bl * 0.92), top * 0.045, _eye_color())
	_glow_dot(body_root, Vector3(-top * 0.09, top * 0.68, -bl * 0.92), top * 0.045, _eye_color())
	# 背脊鬃毛（只在肩背一小段，短而斜）
	for k in 3:
		var z := -bl * 0.42 + float(k) * bl * 0.16
		s.cone(Vector3(0, top * 0.66, z), top * 0.045, top * 0.13, c.darkened(0.15), 4, 0.2, 0.8)
	# 尾（三节渐细）
	var tz := bl * 0.6
	for k in 3:
		var p0 := Vector3(0, top * 0.5 - top * 0.03 * float(k), tz + float(k) * top * 0.2)
		s.beam(p0, p0 + Vector3(0, top * 0.03, top * 0.22), top * (0.055 - 0.014 * float(k)), top * (0.045 - 0.012 * float(k)), 5, c.darkened(0.12 + 0.06 * float(k)))
	s.instance(body_root, "body")
	# 四条腿（肩/髋枢轴，两段）
	for i in 4:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var sz: float = -bl * 0.34 if i < 2 else bl * 0.34
		var leg := MeshKit.pivot(body_root, Vector3(sx * top * 0.2, top * 0.42, sz))
		var ls := Soup.new()
		ls.beam(Vector3(0, 0, 0), Vector3(sx * top * 0.05, -top * 0.2, sz * 0.02), top * 0.075, top * 0.055, 6, c.darkened(0.2))
		ls.sphere(Vector3(sx * top * 0.05, -top * 0.21, sz * 0.02), top * 0.05, c.darkened(0.1), 7, 5)
		ls.beam(Vector3(sx * top * 0.05, -top * 0.21, sz * 0.02), Vector3(sx * top * 0.03, -top * 0.4, sz * 0.02 + top * 0.03), top * 0.045, top * 0.035, 6, c.darkened(0.25))
		ls.box(Vector3(sx * top * 0.03, -top * 0.42, sz * 0.02 + top * 0.05), Vector3(top * 0.13, top * 0.05, top * 0.16), Color("2a2420"), Basis.IDENTITY, 0.6, 0.9)
		ls.instance(leg, "leg")
		parts["leg%d" % i] = leg

# ---------------------------------------------------------------- 史莱姆

func _blob(c: Color, top: float) -> void:
	var s := Soup.new()
	# 主体：大球压扁 + 底部外扩的裙边 + 内部核
	s.sphere(Vector3(0, top * 0.5, 0), top * 0.62, c, 14, 8, Vector3(1.0, 0.85, 1.0), 0.55, 1.0)
	s.sphere(Vector3(0, top * 0.16, 0), top * 0.58, c.darkened(0.12), 12, 5, Vector3(1.0, 0.34, 1.0), 0.45, 0.75)
	s.sphere(Vector3(0, top * 0.4, 0), top * 0.2, c.lightened(0.3), 8, 5, Vector3(1, 1.1, 1), 0.9, 1.0)
	# 表面挂滴
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.3
		s.sphere(Vector3(cos(a) * top * 0.52, top * 0.18, sin(a) * top * 0.52), top * 0.08, c.darkened(0.05), 6, 4, Vector3(1, 1.4, 1), 0.5, 0.8)
	# 高光
	s.sphere(Vector3(-top * 0.16, top * 0.68, -top * 0.3), top * 0.13, c.lightened(0.5), 7, 4, Vector3(1, 0.6, 1), 0.9, 1.0)
	s.instance(body_root, "body")
	for sx in [-1.0, 1.0]:
		MeshKit.sphere(body_root, top * 0.085, Vector3(sx * top * 0.18, top * 0.62, top * 0.5), Color("101820"), 6, 1.2)
		var p := MeshKit.pivot(body_root, Vector3(sx * top * 0.18, top * 0.62, top * 0.55))
		_glow_dot(p, Vector3.ZERO, top * 0.06, Color("e8f8e0"))
		parts["eye%d" % int(sx)] = p

# ---------------------------------------------------------------- 虫

func _bug(c: Color, top: float) -> void:
	var s := Soup.new()
	# 腹节（三节由后到前抬升）
	for k in 3:
		var z := top * (0.16 + 0.22 * float(k))
		s.sphere(Vector3(0, top * (0.4 + 0.03 * float(k)), z), top * (0.36 - 0.05 * float(k)), c.darkened(0.06 * float(k)), 11, 7, Vector3(1.05, 0.9, 1.0), 0.55, 1.0)
	# 背甲分线
	for k in 2:
		s.box(Vector3(0, top * 0.68, top * (0.3 + 0.24 * float(k))), Vector3(top * 0.5, top * 0.03, top * 0.06), c.darkened(0.35))
	# 头 + 复眼 + 螯
	s.sphere(Vector3(0, top * 0.46, -top * 0.36), top * 0.26, c.lightened(0.08), 10, 6, Vector3(1.1, 0.95, 1.0), 0.6, 1.0)
	for sx in [-1.0, 1.0]:
		s.sphere(Vector3(sx * top * 0.13, top * 0.55, -top * 0.5), top * 0.075, Color("101018"), 6, 4)
		_glow_dot(body_root, Vector3(sx * top * 0.13, top * 0.56, -top * 0.55), top * 0.045, Color("ff3a20"))
		for k in 2:
			s.beam(Vector3(sx * top * 0.06, top * 0.38, -top * 0.5), Vector3(sx * top * 0.16, top * 0.3 - 0.02 * float(k), -top * 0.72), top * 0.03, top * 0.012, 4, c.darkened(0.3))
		# 触角
		s.beam(Vector3(sx * top * 0.1, top * 0.6, -top * 0.42), Vector3(sx * top * 0.22, top * 0.82, -top * 0.62), top * 0.015, top * 0.008, 3, c.darkened(0.4))
	if type == "brood" or type == "queen":
		for k in 5:
			var a := TAU * float(k) / 5.0
			s.sphere(Vector3(cos(a) * top * 0.32, top * 0.6, sin(a) * top * 0.32), top * 0.15, c.lightened(0.2), 7, 5, Vector3(1, 1.15, 1), 0.7, 1.0)
	s.instance(body_root, "body")
	# 六条腿（两段）
	for i in 6:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var zz: float = (float(i / 2) - 1.0) * top * 0.3
		var leg := MeshKit.pivot(body_root, Vector3(sx * top * 0.26, top * 0.36, zz))
		var ls := Soup.new()
		ls.beam(Vector3(0, 0, 0), Vector3(sx * top * 0.26, top * 0.06, zz * 0.2), top * 0.035, top * 0.028, 5, c.darkened(0.28))
		ls.sphere(Vector3(sx * top * 0.26, top * 0.08, zz * 0.2), top * 0.028, c.darkened(0.15), 6, 4)
		ls.beam(Vector3(sx * top * 0.26, top * 0.08, zz * 0.2), Vector3(sx * top * 0.4, -top * 0.14, zz * 0.5), top * 0.024, top * 0.012, 5, c.darkened(0.32))
		ls.instance(leg, "leg")
		parts["leg%d" % i] = leg

# ---------------------------------------------------------------- 飞行

func _bat(c: Color) -> void:
	var s := Soup.new()
	s.beam(Vector3(0, 0.14, 0.12), Vector3(0, 0.16, -0.12), 0.075, 0.06, 6, c, 0.0, 0.6, 1.0)
	s.sphere(Vector3(0, 0.2, -0.16), 0.095, c.lightened(0.12), 8, 6, Vector3(1, 0.95, 1.1), 0.7, 1.0)
	for sx in [-1.0, 1.0]:
		s.cone(Vector3(sx * 0.04, 0.26, -0.16), 0.035, 0.12, c.darkened(0.15), 4, 0.3)
	s.box(Vector3(0, 0.15, 0.18), Vector3(0.03, 0.02, 0.14), c.darkened(0.3))
	s.instance(body_root, "body")
	for sx in [-1.0, 1.0]:
		_glow_dot(body_root, Vector3(sx * 0.042, 0.225, -0.235), 0.022, Color("ff3a20"))
	# 翼（肩枢轴，骨 + 膜）
	for sx in [-1.0, 1.0]:
		var w := MeshKit.pivot(body_root, Vector3(sx * 0.055, 0.19, 0))
		var ws := Soup.new()
		var tip := Vector3(sx * 0.42, 0.05, 0.06)
		var mid := Vector3(sx * 0.22, 0.12, -0.06)
		ws.beam(Vector3.ZERO, tip, 0.028, 0.01, 4, c.darkened(0.15))
		ws.beam(Vector3.ZERO, mid, 0.024, 0.008, 4, c.darkened(0.2))
		ws.quad(Vector3.ZERO, Vector3(sx * 0.05, 0.0, 0.1), tip, mid, Vector3.UP, c.darkened(0.05))
		ws.quad(Vector3.ZERO, mid, tip, Vector3(sx * 0.12, 0.0, 0.14), Vector3.UP, c.darkened(0.12))
		ws.instance(w, "wing")
		parts["wingL" if sx < 0.0 else "wingR"] = w

func _ghost(c: Color) -> void:
	var s := Soup.new()
	# 长袍：八棱锥体 + 下摆起伏
	s.cyl(Vector3(0, 0.75, 0), 0.2, 0.34, 1.1, c, 8, 0.0, 0.45, 1.0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var len_v := 0.12 + 0.09 * sin(float(k) * 1.7)
		s.cone(Vector3(cos(a) * 0.28, 0.22 - len_v, sin(a) * 0.28), 0.075, len_v + 0.1, c.darkened(0.08), 4, 0.0, 0.4)
	parts["body"] = s.instance(body_root, "ghost")
	var h := Soup.new()
	h.sphere(Vector3(0, 1.18, 0), 0.19, c.lightened(0.18), 9, 6, Vector3(1, 1.05, 1.05), 0.85, 1.0)
	h.cone(Vector3(0, 1.28, 0), 0.22, 0.34, c.darkened(0.4), 8, 0.0, 0.75)
	h.box(Vector3(0, 1.12, 0.16), Vector3(0.14, 0.1, 0.08), Color("181420"))
	# 袖
	for sx in [-1.0, 1.0]:
		h.beam(Vector3(sx * 0.19, 1.12, 0), Vector3(sx * 0.3, 0.74, 0.08), 0.075, 0.11, 6, c.darkened(0.05))
	h.instance(body_root, "head")
	for sx in [-1.0, 1.0]:
		_glow_dot(body_root, Vector3(sx * 0.075, 1.2, 0.16), 0.04, Color("80ffe0"))

func _wisp(c: Color) -> void:
	var s := Soup.new()
	s.sphere(Vector3(0, 0.22, 0), 0.17, c, 10, 7, Vector3(1, 1, 1), 0.9, 1.0)
	s.sphere(Vector3(0, 0.22, 0), 0.1, Color("ffffff"), 8, 6, Vector3(1, 1, 1), 1.0, 1.0)
	# 拖尾光丝
	for k in 3:
		var a := TAU * float(k) / 3.0
		s.beam(Vector3(cos(a) * 0.1, 0.18, sin(a) * 0.1), Vector3(cos(a + 1.2) * 0.08, -0.2, sin(a + 1.2) * 0.08), 0.03, 0.004, 4, c.darkened(0.1), 0.0, 0.9, 1.0)
	parts["blob"] = s.instance(body_root, "wisp")
	for k in 3:
		var a := TAU * float(k) / 3.0
		_glow_dot(body_root, Vector3(cos(a) * 0.24, 0.22 + sin(a) * 0.1, sin(a) * 0.24), 0.045, c.lightened(0.2))

# ---------------------------------------------------------------- 蟾蜍

func _toad(c: Color) -> void:
	var s := Soup.new()
	s.sphere(Vector3(0, 0.3, 0), 0.44, c, 12, 7, Vector3(1.15, 0.72, 1.25), 0.5, 1.0)
	s.sphere(Vector3(0, 0.42, -0.06), 0.3, c.lightened(0.06), 10, 6, Vector3(1.05, 0.85, 1.0), 0.6, 1.0)
	# 头部 + 眼包 + 嘴
	s.sphere(Vector3(0, 0.36, -0.42), 0.26, c.darkened(0.02), 10, 6, Vector3(1.15, 0.8, 1.0), 0.6, 1.0)
	s.box(Vector3(0, 0.28, -0.6), Vector3(0.3, 0.035, 0.1), c.darkened(0.4))
	for sx in [-1.0, 1.0]:
		s.sphere(Vector3(sx * 0.17, 0.5, -0.44), 0.12, c.lightened(0.1), 9, 6)
		_glow_dot(body_root, Vector3(sx * 0.17, 0.54, -0.52), 0.05, Color("101820"))
	# 背疣
	for k in 7:
		var a := TAU * float(k) / 7.0
		s.sphere(Vector3(cos(a) * 0.28, 0.48, sin(a) * 0.24 - 0.05), 0.03, c.darkened(0.25), 5, 3)
	s.instance(body_root, "body")
	# 前后腿
	for i in 4:
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var front := i < 2
		var leg := MeshKit.pivot(body_root, Vector3(sx * 0.3, 0.24, -0.28 if front else 0.3))
		var ls := Soup.new()
		if front:
			ls.beam(Vector3(0, 0, 0), Vector3(sx * 0.1, -0.16, 0.06), 0.05, 0.04, 5, c.darkened(0.15))
			ls.box(Vector3(sx * 0.14, -0.2, 0.12), Vector3(0.12, 0.03, 0.16), c.darkened(0.25))
		else:
			ls.beam(Vector3(0, 0, 0), Vector3(sx * 0.12, -0.1, -0.1), 0.075, 0.055, 5, c.darkened(0.12))
			ls.sphere(Vector3(sx * 0.13, -0.11, -0.1), 0.055, c.darkened(0.2), 6, 4)
			ls.beam(Vector3(sx * 0.13, -0.11, -0.1), Vector3(sx * 0.16, -0.2, 0.12), 0.05, 0.035, 5, c.darkened(0.16))
			ls.box(Vector3(sx * 0.17, -0.22, 0.2), Vector3(0.14, 0.03, 0.2), c.darkened(0.28))
		ls.instance(leg, "leg")
		parts["leg%d" % i] = leg

# ---------------------------------------------------------------- 石像

func _golem(c: Color, top: float) -> void:
	var leg_h := top * 0.38
	var s := Soup.new()
	var glow: Color = game.biome.get("wisp_hex", Color("ff8030")) if biome_hot() else Color("8fe0ff")
	# 腿：石块堆叠
	for sx in [-1.0, 1.0]:
		s.box(Vector3(sx * top * 0.16, leg_h * 0.5, 0), Vector3(top * 0.2, leg_h * 0.8, top * 0.2), c.darkened(0.18), Basis.IDENTITY, 0.5, 1.0)
		s.box(Vector3(sx * top * 0.16, leg_h * 0.12, top * 0.03), Vector3(top * 0.24, leg_h * 0.24, top * 0.26), c.darkened(0.3), Basis.IDENTITY, 0.5, 0.95)
	# 躯干：三块错位巨石
	s.box(Vector3(0, leg_h + top * 0.24, 0), Vector3(top * 0.5, top * 0.45, top * 0.34), c, Basis(Vector3.FORWARD, 0.06), 0.55, 1.0)
	s.box(Vector3(0, leg_h + top * 0.12, 0), Vector3(top * 0.44, top * 0.22, top * 0.3), c.darkened(0.12))
	s.box(Vector3(-top * 0.28, leg_h + top * 0.34, 0), Vector3(top * 0.2, top * 0.26, top * 0.28), c.lightened(0.06), Basis(Vector3.FORWARD, -0.1))
	s.box(Vector3(top * 0.28, leg_h + top * 0.34, 0), Vector3(top * 0.2, top * 0.26, top * 0.28), c.lightened(0.06), Basis(Vector3.FORWARD, 0.1))
	# 头：方石 + 眼槽
	s.box(Vector3(0, leg_h + top * 0.56, -top * 0.02), Vector3(top * 0.28, top * 0.22, top * 0.26), c.lightened(0.08), Basis.IDENTITY, 0.7, 1.0)
	s.box(Vector3(0, leg_h + top * 0.54, -top * 0.14), Vector3(top * 0.3, top * 0.07, top * 0.06), Color("141018"))
	for sx in [-1.0, 1.0]:
		_glow_dot(body_root, Vector3(sx * top * 0.07, leg_h + top * 0.55, -top * 0.15), top * 0.03, Color("ffb24a"))
	# 肩甲
	for sx in [-1.0, 1.0]:
		s.sphere(Vector3(sx * top * 0.3, leg_h + top * 0.46, 0), top * 0.17, c.lightened(0.04), 8, 5, Vector3(1.1, 0.6, 1.1), 0.7, 1.0)
	# 熔岩/冰裂纹
	for k in 5:
		s.box(Vector3((float(k) - 2.0) * top * 0.09, leg_h + top * 0.22, -top * 0.17), Vector3(top * 0.055, top * 0.02, top * 0.2), glow, Basis(Vector3.FORWARD, 0.35 * float(k)), 1.0, 1.0)
	# 手臂（枢轴）
	for sx in [-1.0, 1.0]:
		var arm := MeshKit.pivot(body_root, Vector3(sx * top * 0.34, leg_h + top * 0.44, 0))
		var as_ := Soup.new()
		as_.box(Vector3(0, -top * 0.12, 0), Vector3(top * 0.16, top * 0.28, top * 0.16), c.darkened(0.08), Basis.IDENTITY, 0.6, 1.0)
		as_.box(Vector3(sx * top * 0.03, -top * 0.32, 0), Vector3(top * 0.19, top * 0.2, top * 0.19), c)
		as_.box(Vector3(sx * top * 0.05, -top * 0.46, 0.01), Vector3(top * 0.22, top * 0.12, top * 0.22), c.darkened(0.15))
		as_.instance(arm, "arm")
		parts["armL" if sx < 0.0 else "armR"] = arm
	s.instance(body_root, "body")
	# 胸核
	var core := Soup.new()
	core.sphere(Vector3.ZERO, top * 0.09, glow, 8, 5, Vector3(1, 1, 1), 1.0, 1.0)
	var cmi := core.instance(body_root, "core")
	cmi.position = Vector3(0, leg_h + top * 0.26, -top * 0.18)
	cmi.material_override = MeshKit.mat(glow, 2.2, 0.5)

func biome_hot() -> bool:
	return String(game.biome_key) == "ember"

# ---------------------------------------------------------------- 每帧

func advance(dt: float, world) -> void:
	var slowness := 1.0 - slow_amt
	var fr := 1.0
	if def.has("frenzy"):
		fr = 1.0 + float(def["frenzy"]) * (1.0 - hp / max_hp)
	if def.has("enrage") and not enraged and hp / max_hp <= float(def["enrage"][0]):
		enraged = true
		boss_moment()
	var spd := base_speed * speed_mul * slowness * haste * fr
	s += spd * dt
	var p: Vector3 = world.world_at(s, lateral)
	if flying:
		p.y = alt
		p.x += side * 0.4
		p.z += cos(t * 1.3) * 0.3
	position = p
	var nxt: Vector3 = world.world_at(minf(s + 0.4, world.length), lateral)
	var dir := nxt - Vector3(p.x, 0, p.z)
	if dir.length_squared() > 0.001:
		yaw = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, dt * 8.0))
	if slow_t > 0.0:
		slow_t -= dt
		if slow_t <= 0.0:
			slow_amt = 0.0
	if def.has("regen"):
		hp = minf(max_hp, hp + max_hp * float(def["regen"]) * dt)

func animate(dt: float, moving: bool) -> void:
	t += dt
	var b := sin(t * 9.0)
	if parts.has("legL") and moving:
		parts["legL"].rotation.x = b * 0.7
		parts["legR"].rotation.x = -b * 0.7
	if parts.has("armL"):
		parts["armL"].rotation.x = -b * 0.5
		parts["armR"].rotation.x = b * 0.5
	for k in 6:
		var key := "leg%d" % k
		if parts.has(key) and moving:
			parts[key].rotation.z = sin(t * 14.0 + float(k)) * 0.32
	if parts.has("wingL"):
		parts["wingL"].rotation.z = sin(t * 18.0) * 0.85
		parts["wingR"].rotation.z = -sin(t * 18.0) * 0.85
	if parts.has("blob"):
		var kk := sin(t * (7.0 if def.has("hop") else 3.0))
		parts["blob"].scale = Vector3(1.0 + kk * 0.08, 1.0 - kk * 0.1, 1.0 + kk * 0.08)
	if body_root != null:
		body_root.position.y = absf(sin(t * 6.0)) * 0.03
	if flash > 0.0:
		flash = maxf(0.0, flash - dt * 4.0)
		if hpfill != null:
			hpfill.scale.x = maxf(0.02, hp / max_hp)
	if hpbar != null and hpbar.visible:
		hpbar.global_transform = Transform3D(game.camera.global_basis, hpbar.global_position)
		hpfill.scale.x = clampf(hp / max_hp, 0.01, 1.0)
		hpfill.position.x = -0.3 * (1.0 - hpfill.scale.x)

func set_slow(amount: float, dur: float) -> void:
	var a := amount
	var d := dur
	if boss:
		a *= 0.4
		d *= 0.6
	if def.has("slow_res"):
		a *= 1.0 - float(def["slow_res"])
	if a > slow_amt:
		slow_amt = a
	slow_t = maxf(slow_t, d)

func take_damage(amount: float, kind: String, source: Node = null) -> bool:
	if not alive:
		return false
	if ghosting and (kind == "arrow" or kind == "sword"):
		if randf() < 0.5:
			return false
		amount *= 0.5
	if kind == "arrow" and def.has("armor"):
		amount *= float(def["armor"])
	hp -= amount
	flash = 1.0
	last_hit = Time.get_ticks_msec() / 1000.0
	if source != null and source.has_method("add_damage"):
		source.add_damage(amount)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false

func boss_moment() -> void:
	if hpbar != null:
		hpbar.visible = true

func hp_ratio() -> float:
	return hp / max_hp

func progress() -> float:
	return s
