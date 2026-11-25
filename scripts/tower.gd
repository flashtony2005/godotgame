extends Node3D

## 高模版塔：全部几何由 Soup 程序化生成（渐缩棱柱 / 梁 / 球 / 板），逐顶点 AO 烘进顶点色。
## 一座塔合成一张网格；炮管、水晶、塔顶弓手这类需要转向的部件单独一张。

const Defs := preload("res://scripts/defs.gd")
const Soup := preload("res://scripts/soup.gd")

const WOOD := Color("6b4a32")
const WOOD_D := Color("3f2c1e")
const WOOD_L := Color("8a6544")
const STONE := Color("7a7684")
const STONE_D := Color("454250")
const STONE_L := Color("9a96a2")
const IRON := Color("3c4048")
const EMBER := Color("ff8a3c")
const CLOTH_R := Color("8a2f2a")
const CLOTH_B := Color("2f4a7a")
const BASALT := Color("35313f")
const BASALT_L := Color("4e4a5e")
const COPPER := Color("8a5a3a")
const CRYSTAL := Color("8fe0ff")
const SKIN := Color("c8b090")

var kind := "archer"
var lvl := 0
var def: Dictionary = {}
var pad: Dictionary = {}
var body: Node3D
var turret: Node3D
var spent := 0
var dealt := 0.0
var cooldown := 0.0
var stun := 0.0
var alive := true
var footmen: Array = []
var game = null
var _lights: Array = []
var _shards: Array = []
var _t := 0.0

func setup(p_kind: String, p_pad: Dictionary, p_game) -> void:
	kind = p_kind
	pad = p_pad
	game = p_game
	def = Defs.TOWER[kind]
	lvl = 0
	spent = int(def["cost"][0])
	position = Vector3(pad["x"], 0.24, pad["z"])
	_rebuild()

func stats() -> Dictionary:
	var d := def
	var out := {}
	for k in ["range", "dmg", "rate"]:
		out[k] = float(d[k][lvl])
	if d.has("count"):
		out["count"] = int(d["count"][lvl])
	if d.has("splash"):
		out["splash"] = float(d["splash"][lvl])
	if d.has("jumps"):
		out["jumps"] = int(d["jumps"][lvl])
	if d.has("slow"):
		out["slow"] = float(d["slow"][lvl])
		out["slow_t"] = float(d["slow_t"][lvl])
	if d.has("hp"):
		out["hp"] = float(d["hp"][lvl])
	return out

func can_upgrade() -> bool:
	return alive and lvl < 2

func upgrade_cost() -> int:
	if lvl >= 2:
		return 0
	return int(def["cost"][lvl + 1])

func upgrade() -> void:
	if lvl >= 2:
		return
	lvl += 1
	spent += int(def["cost"][lvl])
	_rebuild()

func sell_refund() -> int:
	return int(round(float(spent) * 0.6))

func add_damage(v: float) -> void:
	dealt += v

func _rebuild() -> void:
	if body != null:
		body.queue_free()
	for l in _lights:
		if is_instance_valid(l):
			l.queue_free()
	_lights.clear()
	_shards.clear()
	body = Node3D.new()
	add_child(body)
	turret = null
	match kind:
		"archer": _build_archer()
		"bombard": _build_bombard()
		"spire": _build_spire()
		"guard": _build_guard()
	body.scale = Vector3(1.0, 0.22, 1.0)
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if kind == "guard":
		_spawn_footmen()

func _torch(pos: Vector3, size_v: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color("ff9a4a")
	l.light_energy = 0.9 + size_v
	l.omni_range = 3.4 + size_v * 2.2
	l.position = pos
	body.add_child(l)
	_lights.append(l)

func _process(delta: float) -> void:
	_t += delta
	for l in _lights:
		if is_instance_valid(l):
			l.light_energy = 0.85 + 0.25 * sin(_t * 7.0 + float(l.get_instance_id() % 7))
	for sh in _shards:
		if is_instance_valid(sh["node"]):
			var pivot: Node3D = sh["node"]
			pivot.rotation.y = _t * float(sh["spin"])
			pivot.position.y = float(sh["y"]) + sin(_t * 1.4 + float(sh["ph"])) * 0.08

# ---------------------------------------------------------------- 弓手塔

func _build_archer() -> void:
	var l := lvl
	var bh: float = [0.25, 1.0, 1.9][l]
	var h: float = [2.0, 2.7, 3.35][l]
	var w: float = [0.75, 0.85, 0.93][l]
	var s := Soup.new()
	# 台基：一层暗基石 + 四角石墩
	s.box(Vector3(0, 0.13, 0), Vector3(1.66, 0.26, 1.66), STONE_D, Basis.IDENTITY, 0.55, 1.0)
	for ax in [-1.0, 1.0]:
		for az in [-1.0, 1.0]:
			s.box(Vector3(ax * 0.66, 0.19, az * 0.66), Vector3(0.34, 0.38, 0.34), STONE_L, Basis.IDENTITY, 0.6, 1.0)
	# 石鼓塔身（≥1 级）
	if l >= 1:
		s.box(Vector3(0, 0.15, 0), Vector3(1.84, 0.3, 1.84), STONE_D, Basis.IDENTITY, 0.5, 1.0)
		s.cyl(Vector3(0, 0.3 + (bh - 0.3) * 0.5, 0), 1.06, 0.92, bh - 0.3, STONE, 4, PI * 0.25, 0.55, 1.0)
		s.box(Vector3(0, bh - 0.05, 0), Vector3(1.44, 0.15, 1.44), STONE_L, Basis.IDENTITY, 0.65, 1.0)
		for k in 3:
			s.box(Vector3(0, 0.4 + float(k) * (bh - 0.55) / 3.0, 0.72), Vector3(1.3, 0.035, 0.05), STONE_D)
		s.box(Vector3(0, 0.62, 0.735), Vector3(0.32, 0.5, 0.06), Color("0a0806"))
		if l == 2:
			for ax in [-1.0, 1.0]:
				for az in [-1.0, 1.0]:
					s.beam(Vector3(ax * 0.88, 0.28, az * 0.88), Vector3(ax * 0.8, bh + 0.3, az * 0.8), 0.12, 0.09, 4, STONE_L, 0.0, 0.55, 0.95)
	# 四根立柱（微收分）+ 铁箍
	for ax in [-1.0, 1.0]:
		for az in [-1.0, 1.0]:
			var foot := Vector3(ax * 0.64, bh, az * 0.64)
			var top := Vector3(ax * (w - 0.08), h, az * (w - 0.08))
			s.beam(foot, top, 0.095, 0.075, 6, WOOD_D, 0.0, 0.62, 1.0)
			var n := (top - foot).normalized()
			s.cyl(foot + n * 0.18, 0.105, 0.105, 0.09, IRON, 6)
			s.cyl(top - n * 0.1, 0.09, 0.09, 0.08, IRON, 6)
	# 中段横梁 + 交叉斜撑
	var ym := (bh + h) * 0.5
	var rm := lerpf(0.64, w - 0.08, 0.45)
	for k in 4:
		var a := float(k) * PI * 0.5
		s.beam(Vector3(cos(a) * rm, ym, sin(a) * rm), Vector3(-sin(a) * rm, ym, cos(a) * rm), 0.045, 0.045, 4, WOOD, 0.0, 0.75, 0.95)
	for k in 4:
		var a1 := float(k) * PI * 0.5
		var a2 := float((k + 1) % 4) * PI * 0.5
		s.beam(Vector3(cos(a1) * 0.64, bh + 0.12, sin(a1) * 0.64), Vector3(cos(a2) * (w - 0.1), h - 0.15, sin(a2) * (w - 0.1)), 0.035, 0.035, 4, WOOD_L, 0.0, 0.7, 0.95)
		s.beam(Vector3(cos(a2) * 0.64, bh + 0.12, sin(a2) * 0.64), Vector3(cos(a1) * (w - 0.1), h - 0.15, sin(a1) * (w - 0.1)), 0.035, 0.035, 4, WOOD, 0.0, 0.7, 0.95)
	# 甲板：先承重梁，再三排木板，最后一圈收边
	s.box(Vector3(0, h - 0.05, 0), Vector3(w * 2.0 + 0.3, 0.1, w * 2.0 + 0.3), WOOD_D, Basis.IDENTITY, 0.6, 0.9)
	for k in 3:
		var u := (float(k) - 1.0) * w * 0.62
		s.box(Vector3(u, h - 0.12, 0), Vector3(0.12, 0.1, w * 2.0 + 0.3), WOOD_D)
		s.box(Vector3(0, h - 0.12, u), Vector3(w * 2.0 + 0.3, 0.1, 0.12), WOOD_D)
	s.planks(Vector3(0, h + 0.03, 0), w * 2.0 + 0.2, w * 2.0 + 0.2, 8, 0.06, WOOD, Basis.IDENTITY, 0.03)
	# 栏杆：立板高低交错，背面留楼梯缺口
	var y0 := h + 0.1
	for k in 4:
		var ang := float(k) * PI * 0.5
		var cs := cos(ang)
		var sn := sin(ang)
		for j in 5:
			if k == 2 and (j == 1 or j == 2):
				continue
			var u := (float(j) - 2.0) * w * 0.42
			var hh: float = 0.3 if (j % 2) == 1 else 0.5
			var x := u * cs + (w + 0.02) * sn
			var z := -u * sn + (w + 0.02) * cs
			s.box(Vector3(x, y0 + hh * 0.5, z), Vector3(w * 0.4, hh, 0.05), WOOD if (j % 2) == 1 else WOOD_L, Basis(Vector3.UP, ang), 0.62, 1.0)
	for ax in [-1.0, 1.0]:
		for az in [-1.0, 1.0]:
			s.box(Vector3(ax * (w + 0.02), y0 + 0.34, az * (w + 0.02)), Vector3(0.11, 0.68, 0.11), WOOD_D, Basis.IDENTITY, 0.6, 0.95)
			s.box(Vector3(ax * (w + 0.02), y0 + 0.7, az * (w + 0.02)), Vector3(0.15, 0.06, 0.15), IRON)
	# 背面梯子
	var lz := -w - 0.02
	for sg in [-1.0, 1.0]:
		s.beam(Vector3(sg * 0.17, 0.05, lz - 0.5), Vector3(sg * 0.17, h + 0.06, lz), 0.038, 0.038, 4, WOOD_D)
	var rungs := int(h / 0.3)
	for i in rungs:
		var u := (float(i) + 0.6) / float(rungs)
		s.box(Vector3(0, 0.16 + u * (h - 0.06), lz - 0.5 + u * 0.5), Vector3(0.36, 0.045, 0.045), WOOD_L)
	# 火盆
	var bx := -w + 0.33
	var bz := -w + 0.35
	var by := h + 0.1
	var bs: float = [0.4, 0.46, 0.56][l]
	if l == 2:
		s.cyl(Vector3(bx, h + 0.24, bz), 0.18, 0.14, 0.4, STONE_D, 5)
		by += 0.38
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.5
		s.beam(Vector3(bx + cos(a) * 0.17, by, bz + sin(a) * 0.17), Vector3(bx + cos(a) * 0.05, by + 0.3, bz + sin(a) * 0.05), 0.026, 0.02, 4, IRON)
	s.cyl(Vector3(bx, by + 0.33, bz), bs * 0.3, bs * 0.44, bs * 0.24, IRON, 8, 0.0, 0.5, 0.9)
	s.sphere(Vector3(bx, by + 0.42, bz), bs * 0.33, EMBER, 6, 3, Vector3(1, 0.45, 1), 0.85, 1.0)
	_torch(Vector3(bx, by + 0.6, bz), bs)
	# 旗
	if l >= 1:
		s.beam(Vector3(w - 0.08, h + 0.1, -w + 0.08), Vector3(w - 0.08, h + 1.9, -w + 0.08), 0.032, 0.022, 5, WOOD_D)
		s.box(Vector3(w - 0.42, h + 1.58, -w + 0.06), Vector3(0.62, 0.34, 0.02), CLOTH_R, Basis.IDENTITY, 0.85, 1.0)
		s.box(Vector3(w - 0.42, h + 1.4, -w + 0.06), Vector3(0.5, 0.08, 0.02), CLOTH_R.darkened(0.35))
	# 塔顶弓手（随目标转向）
	var tur := Node3D.new()
	tur.position = Vector3(0, h + 0.09, 0)
	body.add_child(tur)
	turret = tur
	var spots: Array = [[Vector3(0.1, 0, 0.26)], [Vector3(-0.3, 0, 0.4), Vector3(0.4, 0, 0.08)], [Vector3(-0.34, 0, 0.46), Vector3(0.46, 0, 0.26), Vector3(0.2, 0, -0.4)]][l]
	for sp in spots:
		_archer_figure(tur, sp, 0.9)
	s.instance(body, "mesh")

func _archer_figure(parent: Node3D, at: Vector3, sc: float) -> void:
	var s := Soup.new()
	var leg := 0.34 * sc
	var torso := 0.26 * sc
	for sx in [-1.0, 1.0]:
		s.beam(at + Vector3(sx * 0.05, leg, 0), at + Vector3(sx * 0.055, 0, -0.02), 0.042, 0.033, 4, Color("2c2a2e"))
	s.beam(at + Vector3(0, leg, 0), at + Vector3(0, leg + torso, 0), 0.1, 0.085, 6, CLOTH_B)
	s.box(at + Vector3(0, leg + torso * 0.55, 0), Vector3(0.21, 0.17, 0.15), Color("6a5030"))
	s.sphere(at + Vector3(0, leg + torso + 0.09, 0), 0.085, SKIN, 8, 5)
	s.cone(at + Vector3(0, leg + torso + 0.07, 0), 0.125, 0.15, CLOTH_B.darkened(0.45), 7)
	s.beam(at + Vector3(-0.1, leg + torso * 0.9, 0), at + Vector3(-0.12, leg + torso * 0.5, 0.12), 0.028, 0.026, 4, CLOTH_B)
	s.beam(at + Vector3(0.1, leg + torso * 0.9, 0), at + Vector3(0.14, leg + torso * 0.52, 0.1), 0.028, 0.026, 4, CLOTH_B)
	var bow_c := at + Vector3(0.17, leg + torso * 0.72, 0.13)
	for k in 5:
		var a := -0.95 + 1.9 * float(k) / 4.0
		var p0 := bow_c + Vector3(0, cos(a) * 0.26, sin(a) * 0.26)
		var p1 := bow_c + Vector3(0, cos(a + 0.47) * 0.26, sin(a + 0.47) * 0.26)
		s.beam(p0, p1, 0.011, 0.011, 3, WOOD_D)
	s.cyl(at + Vector3(-0.08, leg + torso * 0.75, -0.13), 0.045, 0.05, 0.2, Color("5a3a22"), 6)
	s.instance(parent, "archer")

# ---------------------------------------------------------------- 臼炮

func _build_bombard() -> void:
	var l := lvl
	var rr: float = [1.0, 1.08, 1.15][l]
	var h: float = [1.1, 1.5, 1.9][l]
	var s := Soup.new()
	s.cyl(Vector3(0, 0.13, 0), rr + 0.26, rr + 0.18, 0.26, STONE_D, 12, 0.0, 0.5, 0.95)
	if l == 2:
		s.cyl(Vector3(0, 0.36, 0), rr + 0.14, rr + 0.1, 0.2, STONE, 12)
	# 石鼓塔身 + 砌层压条
	s.cyl(Vector3(0, h * 0.5 + 0.1, 0), rr, rr * 0.93, h, STONE, 12, 0.0, 0.55, 1.0)
	for c in 2 + l:
		var yy := 0.36 + float(c) * (h - 0.55) / float(1.5 + float(l))
		var r3 := rr * (1.0 - 0.05 * (0.5 + float(c)) / float(2 + l)) + 0.012
		s.cyl(Vector3(0, yy, 0), r3, r3, 0.15, STONE_D, 12, 0.0, 0.8, 0.95)
	s.box(Vector3(0, 0.42, rr * 0.96), Vector3(0.36, 0.58, 0.12), Color("0a0806"))
	if l >= 1:
		for k in 4:
			var a := float(k) * PI * 0.5 + PI * 0.25
			s.beam(Vector3(cos(a) * (rr + 0.02), 0.3, sin(a) * (rr + 0.02)), Vector3(cos(a) * (rr + 0.06), h * 0.85, sin(a) * (rr + 0.06)), 0.19, 0.16, 4, STONE_D, 0.0, 0.5, 0.95)
			s.box(Vector3(cos(a) * (rr + 0.06), h * 0.9, sin(a) * (rr + 0.06)), Vector3(0.36, 0.14, 0.46), STONE_L, Basis(Vector3.UP, -a))
	# 平台 + 木板 + 城垛
	s.cyl(Vector3(0, h + 0.14, 0), rr * 0.95 + 0.16, rr * 0.95 + 0.1, 0.18, STONE_L, 12)
	s.planks(Vector3(0, h + 0.24, 0), rr * 1.5, rr * 1.5, 5, 0.05, WOOD, Basis.IDENTITY, 0.03)
	for k in 12:
		if k % 4 == 0:
			continue
		var a := (float(k) + 0.5) / 12.0 * TAU
		s.box(Vector3(cos(a) * rr * 0.94, h + 0.42, sin(a) * rr * 0.94), Vector3(0.5, 0.34, 0.26), STONE_L, Basis(Vector3.UP, -a + PI * 0.5), 0.6, 1.0)
	# 炮车
	var tur := Node3D.new()
	tur.position = Vector3(0, h + 0.3, 0)
	body.add_child(tur)
	turret = tur
	var ts := Soup.new()
	var blen: float = [0.95, 1.12, 1.25][l]
	var gr: float = [0.15, 0.18, 0.215][l]
	ts.beam(Vector3(0, 0.02, 0), Vector3(0, 0.06, blen), gr * 1.25, gr, 10, IRON, 0.0, 0.72, 1.0)
	ts.cyl(Vector3(0, 0.05, blen - 0.05), gr * 1.52, gr * 1.52, 0.13, IRON, 10, 0.0, 0.6, 0.95)
	ts.sphere(Vector3(0, 0.03, -0.02), gr * 1.35, IRON, 8, 5, Vector3(1, 0.9, 1), 0.55, 0.95)
	for k in 3:
		ts.cyl(Vector3(0, 0.06, 0.2 + float(k) * (blen - 0.42) / 2.0), gr * 1.32, gr * 1.32, 0.05, Color("6a6e76"), 10)
	for sx in [-1.0, 1.0]:
		ts.cyl(Vector3(sx * (gr + 0.04), 0.02, 0.26), 0.06, 0.06, 0.14, IRON, 6, 0.0, 0.6, 0.9)
	ts.instance(tur, "barrel")
	# 弹药与火药桶
	var base_y := h + 0.3
	s.sphere(Vector3(-0.44, base_y + 0.06, -0.44), 0.1, Color("2e3038"), 7, 4, Vector3.ONE, 0.5)
	s.sphere(Vector3(-0.2, base_y + 0.05, -0.5), 0.1, Color("2e3038"), 7, 4, Vector3.ONE, 0.5)
	s.sphere(Vector3(-0.33, base_y + 0.2, -0.43), 0.1, Color("2e3038"), 7, 4, Vector3.ONE, 0.5)
	var barrel := Vector3(0.5, base_y, -0.52)
	s.cyl(barrel, 0.16, 0.14, 0.42, Color("6a4a2c"), 8, 0.0, 0.5, 0.9)
	for yv in [-0.12, 0.12]:
		s.cyl(barrel + Vector3(0, yv, 0), 0.168, 0.168, 0.04, IRON, 8)
	# 灯笼
	var lx := -rr * 0.82
	s.beam(Vector3(lx, h + 0.14, 0.2), Vector3(lx, h + 1.3, 0.2), 0.042, 0.032, 5, IRON)
	s.beam(Vector3(lx, h + 1.3, 0.2), Vector3(lx, h + 1.3, 0.54), 0.028, 0.028, 4, IRON)
	s.box(Vector3(lx, h + 1.19, 0.54), Vector3(0.22, 0.05, 0.22), IRON)
	s.box(Vector3(lx, h + 1.05, 0.54), Vector3(0.15, 0.22, 0.15), Color("ffcf8a"), Basis.IDENTITY, 0.95, 1.0)
	s.box(Vector3(lx, h + 0.92, 0.54), Vector3(0.22, 0.05, 0.22), IRON)
	_torch(Vector3(lx, h + 1.05, 0.54), 0.2)
	s.instance(body, "mesh")

# ---------------------------------------------------------------- 雷塔

func _build_spire() -> void:
	var l := lvl
	var h: float = [2.7, 3.4, 4.1][l]
	var s := Soup.new()
	s.box(Vector3(0, 0.11, 0), Vector3(1.6, 0.22, 1.6), BASALT_L, Basis.IDENTITY, 0.5, 0.9)
	s.box(Vector3(0, 0.31, 0), Vector3(1.2, 0.18, 1.2), BASALT)
	if l >= 1:
		for ax in [-1.0, 1.0]:
			for az in [-1.0, 1.0]:
				s.cone(Vector3(ax * 0.6, 0.3, az * 0.6), 0.17, 0.55, BASALT_L, 4, PI * 0.25, 0.5)
	# 八棱渐缩塔身
	s.cyl(Vector3(0, 0.4 + (h - 0.42) * 0.5, 0), 0.62, 0.34, h - 0.42, BASALT, 8, PI * 0.125, 0.45, 1.0)
	# 扶壁
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		s.beam(Vector3(cos(a) * 0.56, 0.34, sin(a) * 0.56), Vector3(cos(a) * 0.46, h * 0.42, sin(a) * 0.46), 0.16, 0.1, 4, BASALT_L, 0.0, 0.55, 0.95)
	# 符文
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		for j in 3 + l:
			var u := (float(j) + 0.7) / float(3 + l) * 0.82
			var yy := 0.44 + u * (h - 0.5)
			var rad := lerpf(0.62, 0.34, u) * 0.93
			s.box(Vector3(cos(a) * rad, yy, sin(a) * rad), Vector3(0.1, 0.22, 0.035), Color("7fd8ff"), Basis(Vector3.UP, -a + PI * 0.5), 1.0, 1.0)
	# 铜箍
	if l >= 1:
		var us: Array = [0.3, 0.58, 0.82] if l == 2 else [0.4, 0.75]
		for u in us:
			var rr := lerpf(0.62, 0.34, float(u)) + 0.028
			s.cyl(Vector3(0, 0.4 + float(u) * (h - 0.42), 0), rr, rr, 0.1, COPPER, 8, PI * 0.125, 0.6, 0.95)
	# 顶部爪
	for k in 4:
		var a := float(k) * PI * 0.5 + PI * 0.25
		s.beam(Vector3(cos(a) * 0.24, h - 0.1, sin(a) * 0.24), Vector3(cos(a) * 0.44, h + 0.3, sin(a) * 0.44), 0.07, 0.05, 4, BASALT_L)
		s.beam(Vector3(cos(a) * 0.44, h + 0.3, sin(a) * 0.44), Vector3(cos(a) * 0.23, h + 0.8, sin(a) * 0.23), 0.05, 0.012, 4, COPPER if l > 0 else BASALT_L)
	s.cyl(Vector3(0, h - 0.02, 0), 0.36, 0.3, 0.12, BASALT_L, 8, PI * 0.125)
	# 环绕的悬浮碎片
	var cs: float = [0.2, 0.24, 0.29][l]
	var shard_count: int = [0, 2, 4][l]
	for k in shard_count:
		var pivot := Node3D.new()
		var a := TAU * float(k) / float(maxi(1, shard_count)) + 0.4
		pivot.position = Vector3(cos(a) * 0.52, h + 0.55, sin(a) * 0.52)
		body.add_child(pivot)
		var ss := Soup.new()
		ss.beam(Vector3(0, -0.14, 0), Vector3(0, 0.18, 0), 0.052, 0.002, 5, CRYSTAL, 0.0, 0.8, 1.0)
		ss.instance(pivot, "shard")
		_shards.append({"node": pivot, "spin": 0.55 + float(k) * 0.22, "y": h + 0.55, "ph": float(k) * 1.7})
	# 会转的水晶簇
	var tur := Node3D.new()
	tur.position = Vector3(0, h + 0.42, 0)
	body.add_child(tur)
	turret = tur
	var tn := Soup.new()
	for k in 3:
		var a := TAU * float(k) / 3.0
		tn.beam(Vector3(cos(a) * 0.11, -0.06, sin(a) * 0.11), Vector3(cos(a) * 0.06, cs * 1.35, sin(a) * 0.06), cs * 0.6, 0.008, 5, CRYSTAL, 0.0, 0.9, 1.0)
	tn.sphere(Vector3(0, 0.01, 0), cs * 0.62, Color("bff0ff"), 8, 5, Vector3(1, 1.25, 1), 1.0, 1.0)
	tn.instance(tur, "crystal")
	var glow := OmniLight3D.new()
	glow.light_color = Color("7fd8ff")
	glow.light_energy = 1.7
	glow.omni_range = 4.6
	tur.add_child(glow)
	_lights.append(glow)
	s.instance(body, "mesh")

# ---------------------------------------------------------------- 哨所

func _build_guard() -> void:
	var l := lvl
	var w: float = [1.5, 1.7, 1.9][l]
	var d: float = [1.3, 1.4, 1.5][l]
	var wh: float = [1.05, 1.25, 1.5][l]
	var stone_walls := l == 2
	var s := Soup.new()
	# 地台 + 台阶
	s.box(Vector3(0, 0.09, 0.1), Vector3(w + 0.55, 0.18, d + 0.75), STONE_D, Basis.IDENTITY, 0.5, 0.9)
	s.box(Vector3(0, 0.05, d * 0.5 + 0.56), Vector3(0.78, 0.1, 0.42), STONE)
	if l == 1:
		s.box(Vector3(0, 0.36, 0), Vector3(w + 0.08, 0.36, d + 0.08), STONE, Basis.IDENTITY, 0.55, 1.0)
	# 墙体
	var wall_c := STONE_L if stone_walls else Color("8f7a5c")
	s.box(Vector3(0, 0.18 + wh * 0.5, 0), Vector3(w, wh, d), wall_c, Basis.IDENTITY, 0.55, 1.0)
	if stone_walls:
		for k in 4:
			s.box(Vector3(0, 0.28 + float(k) * wh / 4.2, d * 0.5 + 0.012), Vector3(w * 0.97, 0.035, 0.03), STONE_D)
			s.box(Vector3(0, 0.28 + float(k) * wh / 4.2, -d * 0.5 - 0.012), Vector3(w * 0.97, 0.035, 0.03), STONE_D)
	else:
		var cols := int(w / 0.24)
		for i in cols:
			var x := -w * 0.5 + 0.12 + float(i) * 0.24
			s.box(Vector3(x, 0.18 + wh * 0.5, d * 0.5 + 0.02), Vector3(0.2, wh * 0.98, 0.03), WOOD if i % 2 == 0 else WOOD_L)
			s.box(Vector3(x, 0.18 + wh * 0.5, -d * 0.5 - 0.02), Vector3(0.2, wh * 0.98, 0.03), WOOD if i % 2 == 0 else WOOD_L)
		for sg in [-1.0, 1.0]:
			s.box(Vector3(sg * w * 0.5, 0.18 + wh * 0.55, 0), Vector3(0.04, wh * 0.98, d), WOOD_L)
		for yy in [0.18 + wh * 0.3, 0.18 + wh * 0.75]:
			s.box(Vector3(0, yy, d * 0.5 + 0.03), Vector3(w + 0.05, 0.08, 0.03), WOOD_D)
			s.box(Vector3(0, yy, -d * 0.5 - 0.03), Vector3(w + 0.05, 0.08, 0.03), WOOD_D)
	# 门框、门板、门轴、踏石
	s.box(Vector3(0, 0.58, d * 0.5 + 0.02), Vector3(0.5, 0.82, 0.06), Color("2a2018"))
	s.box(Vector3(0, 1.0, d * 0.5 + 0.03), Vector3(0.66, 0.09, 0.1), WOOD_D)
	for sg in [-1.0, 1.0]:
		s.box(Vector3(sg * 0.29, 0.6, d * 0.5 + 0.04), Vector3(0.1, 0.9, 0.1), WOOD_D)
	for yy in [0.45, 0.78]:
		s.box(Vector3(0.13, yy, d * 0.5 + 0.06), Vector3(0.1, 0.05, 0.04), IRON)
	# 窗与铁栏
	s.box(Vector3(w * 0.32, 0.18 + wh * 0.62, d * 0.5 + 0.02), Vector3(0.26, 0.26, 0.05), Color("0a0806"))
	for k in 2:
		s.box(Vector3(w * 0.32, 0.18 + wh * 0.62 + (float(k) - 0.5) * 0.12, d * 0.5 + 0.05), Vector3(0.26, 0.02, 0.02), WOOD_D)
	# 屋顶：檐板 + 两坡瓦垄 + 屋脊
	var ry := 0.18 + wh
	s.box(Vector3(0, ry + 0.07, 0), Vector3(w + 0.5, 0.14, d + 0.5), WOOD_L, Basis.IDENTITY, 0.7, 1.0)
	for side in [-1.0, 1.0]:
		var basis := Basis(Vector3.RIGHT, -side * 0.6)
		var mid := Vector3(0, ry + 0.3, side * (d * 0.5 + 0.1))
		for k in 3:
			s.box(mid + Vector3(0, 0.055 * float(k), side * 0.13 * float(k)), Vector3(w + 0.62 - 0.1 * float(k), 0.1, 0.4), WOOD_D if k % 2 == 0 else WOOD, basis, 0.65, 1.0)
		s.beam(Vector3(-w * 0.5 - 0.3, ry + 0.14, side * 0.18), Vector3(w * 0.5 + 0.3, ry + 0.14, side * 0.18), 0.045, 0.045, 4, WOOD_D)
	s.beam(Vector3(0, ry + 0.05, -d * 0.5 - 0.26), Vector3(0, ry + 0.8, 0), 0.07, 0.05, 4, WOOD_D)
	s.box(Vector3(0, ry + 0.62, 0.01), Vector3(0.14, 0.18, 0.14), IRON)
	# 旗
	s.beam(Vector3(w * 0.44, ry + 0.1, -d * 0.44), Vector3(w * 0.44, ry + 1.4, -d * 0.44), 0.038, 0.028, 5, WOOD_D)
	s.box(Vector3(w * 0.44 - 0.22, ry + 1.16, -d * 0.44), Vector3(0.44, 0.3, 0.02), CLOTH_B, Basis.IDENTITY, 0.85, 1.0)
	# 门边挂盾
	var shield_c := Vector3(-w * 0.62, 0.62, d * 0.5 + 0.01)
	s.sphere(shield_c, 0.2, Color("6a3a2e"), 9, 5, Vector3(1.0, 1.15, 0.35), 0.85, 1.0)
	s.box(shield_c + Vector3(0, 0, 0.07), Vector3(0.05, 0.3, 0.03), IRON)
	# 火盆
	var bpos := Vector3(-w * 0.36, ry + 0.18, -d * 0.3)
	s.cyl(bpos + Vector3(0, 0.14, 0), 0.15, 0.22, 0.2, IRON, 8, 0.0, 0.6)
	s.sphere(bpos + Vector3(0, 0.3, 0), 0.17, EMBER, 6, 3, Vector3(1, 0.5, 1), 0.9)
	_torch(bpos + Vector3(0, 0.46, 0), 0.2)
	s.instance(body, "mesh")

# ---------------------------------------------------------------- 步兵

func _spawn_footmen() -> void:
	for f in footmen:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	footmen.clear()
	var count: int = int(def["count"][lvl])
	var hp: float = float(def["hp"][lvl])
	for i in count:
		var n := Node3D.new()
		add_child(n)
		var a := TAU * float(i) / float(count)
		n.position = Vector3(cos(a) * 0.62, 0, sin(a) * 0.62)
		n.scale = Vector3(0.74, 0.74, 0.74)
		var s := Soup.new()
		# 腿
		for sx in [-1.0, 1.0]:
			s.beam(Vector3(sx * 0.075, 0.52, 0), Vector3(sx * 0.085, 0.0, 0.03), 0.055, 0.048, 4, Color("3a3430"))
			s.box(Vector3(sx * 0.085, 0.03, 0.05), Vector3(0.13, 0.07, 0.2), Color("2a2422"))
		# 躯干 + 罩袍 + 腰带
		s.beam(Vector3(0, 0.5, 0), Vector3(0, 0.97, 0), 0.135, 0.115, 6, CLOTH_B)
		s.box(Vector3(0, 0.66, 0), Vector3(0.29, 0.34, 0.2), Color("6a3a2e"), Basis.IDENTITY, 0.8, 1.0)
		s.box(Vector3(0, 0.52, 0), Vector3(0.3, 0.07, 0.21), Color("2a2018"))
		# 头 + 头盔 + 鼻梁护
		s.sphere(Vector3(0, 1.07, 0), 0.105, SKIN, 8, 5)
		s.sphere(Vector3(0, 1.09, 0), 0.128, Color("8a929e"), 9, 5, Vector3(1.05, 0.75, 1.05), 0.8, 1.0)
		s.box(Vector3(0, 1.07, 0.09), Vector3(0.035, 0.16, 0.05), IRON)
		s.box(Vector3(0, 1.02, -0.13), Vector3(0.16, 0.1, 0.03), Color("6a3a2e"))
		# 盾
		var sh := Soup.new()
		sh.sphere(Vector3.ZERO, 0.19, Color("7a4a36"), 9, 5, Vector3(1.0, 1.2, 0.32), 0.85, 1.0)
		sh.box(Vector3(0, 0, 0.05), Vector3(0.05, 0.28, 0.02), IRON)
		var shi := sh.instance(n, "shield")
		shi.position = Vector3(-0.23, 0.72, 0.07)
		shi.rotation = Vector3(0, 0.25, 0)
		# 剑（以手为枢轴，挥击动画在 game.gd 里转 rotation.x）
		var sw := Soup.new()
		sw.beam(Vector3(0, 0, 0), Vector3(0.02, 0.44, 0.06), 0.022, 0.016, 4, Color("c8d0d8"))
		sw.box(Vector3(0, 0, 0), Vector3(0.13, 0.045, 0.05), IRON)
		sw.box(Vector3(0, -0.09, 0), Vector3(0.04, 0.14, 0.045), Color("3a2a20"))
		var sword := sw.instance(n, "sword")
		sword.position = Vector3(0.2, 0.74, 0.06)
		var cape := Soup.new()
		cape.box(Vector3(0, 0.68, -0.14), Vector3(0.28, 0.52, 0.035), CLOTH_B.darkened(0.3), Basis.IDENTITY, 0.7, 1.0)
		cape.instance(n, "cape")
		footmen.append({
			"node": n, "hp": hp, "max_hp": hp, "cd": 0.0, "target": null,
			"home": n.position, "sword": sword, "alive": true, "regen": 0.0,
		})

func footmen_alive() -> int:
	var c := 0
	for f in footmen:
		if f["alive"]:
			c += 1
	return c
