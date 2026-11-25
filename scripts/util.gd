extends RefCounted
## Deterministic math, noise, easing, and color utilities (ported from 00-util.js).

class Rng extends RefCounted:
	var s: int = 1

	func _init(seed_val: int = 0xC1DE5) -> void:
		s = (seed_val & 0xFFFFFFFF)
		if s == 0:
			s = 1

	func next_f() -> float:
		s = (s + 0x6D2B79F5) & 0xFFFFFFFF
		var t: int = _imul32(s ^ (s >> 15), 1 | s)
		t = (_imul32(t ^ (t >> 7), 61 | t) + t) & 0xFFFFFFFF
		t = (t ^ (t >> 14)) & 0xFFFFFFFF
		return float(t) / 4294967296.0

	func frange(a: float, b: float) -> float:
		return a + (b - a) * next_f()

	func irange(a: int, b: int) -> int:
		return a + int(floor(float(b - a + 1) * next_f()))

	func pick(arr: Array) -> Variant:
		if arr.is_empty():
			return null
		return arr[int(floor(next_f() * float(arr.size()))) % arr.size()]

	func sign_val() -> float:
		return -1.0 if next_f() < 0.5 else 1.0

	func chance(p: float) -> bool:
		return next_f() < p

	static func _imul32(a: int, b: int) -> int:
		return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF


static func make_rng(seed_val: int) -> Rng:
	return Rng.new(seed_val)

static func sat(x: float) -> float:
	return clampf(x, 0.0, 1.0)

static func smooth(a: float, b: float, x: float) -> float:
	if absf(b - a) < 1e-8:
		return 0.0 if x < a else 1.0
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func damp(a: float, b: float, lam: float, dt: float) -> float:
	return b + (a - b) * exp(-lam * dt)

static func ease_out(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u

static func ease_in(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * u

static func ease_in_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	if u < 0.5:
		return 4.0 * u * u * u
	var k := -2.0 * u + 2.0
	return 1.0 - (k * k * k) * 0.5

static func ease_out_back(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var d := u - 1.0
	return 1.0 + c3 * d * d * d + c1 * d * d

static func ang_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	return d

static func ang_damp(a: float, b: float, lam: float, dt: float) -> float:
	return a + ang_diff(a, b) * (1.0 - exp(-lam * dt))

static func _imul32(a: int, b: int) -> int:
	return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF

static func h2(x: int, y: int, s: int = 0) -> float:
	var h: int = (_imul32(x, 0x27D4EB2D) ^ _imul32(y, 0x165667B1) ^ _imul32(s, 0x9E3779B1)) & 0xFFFFFFFF
	h = _imul32(h ^ (h >> 15), 0x85EBCA6B)
	h = _imul32(h ^ (h >> 13), 0xC2B2AE35)
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967296.0

static func vnoise(x: float, y: float, s: int = 0) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - float(xi)
	var yf := y - float(yi)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := h2(xi, yi, s)
	var b := h2(xi + 1, yi, s)
	var c := h2(xi, yi + 1, s)
	var d := h2(xi + 1, yi + 1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

static func fbm(x: float, y: float, s: int = 0, oct: int = 4) -> float:
	var amp := 0.5
	var freq := 1.0
	var total := 0.0
	var norm := 0.0
	for i in oct:
		total += amp * vnoise(x * freq, y * freq, s + i * 17)
		norm += amp
		amp *= 0.5
		freq *= 2.03
	return total / norm

static func pnoise2(x: float, y: float, per_x: int, per_y: int, s: int = 0) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - float(xi)
	var yf := y - float(yi)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var mx0 := posmod(xi, per_x)
	var mx1 := posmod(xi + 1, per_x)
	var my0 := posmod(yi, per_y)
	var my1 := posmod(yi + 1, per_y)
	var a := h2(mx0, my0, s)
	var b := h2(mx1, my0, s)
	var c := h2(mx0, my1, s)
	var d := h2(mx1, my1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

static func pfbm(x: float, y: float, per: int, s: int = 0, oct: int = 3) -> float:
	var amp := 0.5
	var freq := 1
	var total := 0.0
	var norm := 0.0
	for i in oct:
		total += amp * pnoise2(x * float(freq), y * float(freq), per * freq, per * freq, s + i * 31)
		norm += amp
		amp *= 0.5
		freq *= 2
	return total / norm

static func n1(t: float, s: float = 0.0) -> float:
	return vnoise(t, s * 7.31, 91) * 2.0 - 1.0

static func dist2(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := ax - bx
	var dz := az - bz
	return dx * dx + dz * dz

static func col_hex(hex_val: int, mul: float = 1.0) -> Color:
	var r := float((hex_val >> 16) & 0xFF) / 255.0
	var g := float((hex_val >> 8) & 0xFF) / 255.0
	var b := float(hex_val & 0xFF) / 255.0
	var c := Color(r, g, b, 1.0).srgb_to_linear()
	return Color(c.r * mul, c.g * mul, c.b * mul, 1.0)

static func mix_c(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), 1.0)

static func mul_c(a: Color, k: float) -> Color:
	return Color(a.r * k, a.g * k, a.b * k, 1.0)
