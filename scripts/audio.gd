extends Node
const U = preload("res://scripts/util.gd")
## Complete procedural dark-fantasy audio synthesizer (ported from 80-audio.js).
## Generates 16-bit PCM AudioStreamWAV clips at startup for all 31 combat/UI/transition SFX,
## plus seamless looping wind, campfire roar, boss tension drone, generative dark-fantasy chords,
## sparse atmospheric piano notes, and deep timpani pulses.

const RATE := 22050
const SFX_VOICES := 20

var muted := false
var master_volume := 1.0
var sfx_clips: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _last_play: Dictionary = {}

# Ambient loops
var _wind_player: AudioStreamPlayer
var _fire_player: AudioStreamPlayer
var _drone_player: AudioStreamPlayer
var _wind_target := 0.28
var _fire_target := 0.35
var _tension_target := 0.0
var _wind_cur := 0.0
var _fire_cur := 0.0
var _tension_cur := 0.0

# Music players
var _chord_clips: Array[AudioStreamWAV] = []
var _piano_clips: Array[AudioStreamWAV] = []
var _timpani_clip: AudioStreamWAV
var _music_players: Array[AudioStreamPlayer] = []
var _music_next := 0
var _chord_timer := 1.2
var _piano_timer := 2.8
var _timp_timer := 1.0
var _crackle_timer := 0.4
var _chord_idx := 0

const COOLDOWNS := {
	"bow": 0.055,
	"arrowHit": 0.045,
	"cannon": 0.10,
	"explode": 0.08,
	"charge": 0.14,
	"zap": 0.075,
	"clash": 0.06,
	"slash": 0.06,
	"ratSqueal": 0.12,
	"boneRattle": 0.09,
	"squelch": 0.10,
	"batScreech": 0.16,
	"roar": 0.25,
	"bossStep": 0.28,
	"coin": 0.045,
	"hammer": 0.055,
	"uiHover": 0.04,
	"splash": 0.09,
}


func _ready() -> void:
	_build_sfx_bank()
	_build_ambient_loops()
	_build_music_bank()
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	for i in 6:
		var mp := AudioStreamPlayer.new()
		mp.bus = "Master"
		add_child(mp)
		_music_players.append(mp)


func set_muted(m: bool) -> void:
	muted = m
	if not muted and master_volume <= 0.001:
		master_volume = 0.5
	_apply_master_bus()


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	if master_volume > 0.001 and muted:
		muted = false
	_apply_master_bus()


func _apply_master_bus() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted or master_volume <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, master_volume)))


func set_ambience(fire_lvl: float, wind_lvl: float, tension_lvl: float) -> void:
	_fire_target = clampf(fire_lvl, 0.0, 1.0)
	_wind_target = clampf(wind_lvl, 0.0, 1.0)
	_tension_target = clampf(tension_lvl, 0.0, 1.0)


func play_sfx(name: String, _pan: float = 0.0, gain: float = 1.0, pitch: float = 1.0) -> void:
	if muted or not sfx_clips.has(name):
		return
	var now := Time.get_ticks_msec() * 0.001
	var cd := float(COOLDOWNS.get(name, 0.03))
	if now - float(_last_play.get(name, -9.0)) < cd:
		return
	_last_play[name] = now

	var p := _sfx_players[_sfx_next % SFX_VOICES]
	_sfx_next += 1
	p.stream = sfx_clips[name]
	p.volume_db = linear_to_db(clampf(gain * 0.65, 0.001, 2.0))
	p.pitch_scale = clampf(pitch * (0.94 + randf() * 0.12), 0.5, 2.0)
	p.play()


func update_audio(dt: float, paused: bool = false) -> void:
	var k := 1.0 - exp(-dt * 2.4)
	_wind_cur = lerpf(_wind_cur, _wind_target, k)
	_fire_cur = lerpf(_fire_cur, _fire_target, k)
	_tension_cur = lerpf(_tension_cur, _tension_target, k)

	_wind_player.volume_db = linear_to_db(maxf(0.0002, _wind_cur * 0.16))
	_fire_player.volume_db = linear_to_db(maxf(0.0002, _fire_cur * 0.18))
	_drone_player.volume_db = linear_to_db(maxf(0.0002, _tension_cur * 0.16))

	if muted or paused:
		return

	# Occasional fire crackle
	_crackle_timer -= dt
	if _crackle_timer <= 0.0:
		_crackle_timer = 0.25 + randf() * 0.65
		if _fire_cur > 0.15 and randf() < _fire_cur:
			play_sfx("_crackle", 0.0, 0.22 * _fire_cur, 0.8 + randf() * 0.5)

	# Dark-fantasy pad chord progression (D minor / modal)
	_chord_timer -= dt
	if _chord_timer <= 0.0:
		_chord_timer = 7.5 + randf() * 3.5
		if _chord_clips.size() > 0:
			var cp := _music_players[_music_next % _music_players.size()]
			_music_next += 1
			cp.stream = _chord_clips[_chord_idx % _chord_clips.size()]
			_chord_idx += 1
			cp.volume_db = linear_to_db(0.11 + _tension_cur * 0.04)
			cp.pitch_scale = 1.0
			cp.play()

	# Sparse ambient piano notes
	_piano_timer -= dt
	if _piano_timer <= 0.0:
		_piano_timer = 2.6 + randf() * 4.4
		if _piano_clips.size() > 0 and randf() < 0.72:
			var pp := _music_players[_music_next % _music_players.size()]
			_music_next += 1
			pp.stream = _piano_clips[randi() % _piano_clips.size()]
			pp.volume_db = linear_to_db(0.08 + randf() * 0.05)
			pp.pitch_scale = 1.0
			pp.play()

	# Boss timpani heartbeat
	if _tension_cur > 0.25:
		_timp_timer -= dt
		if _timp_timer <= 0.0:
			_timp_timer = 0.92 - _tension_cur * 0.22
			var tp := _music_players[_music_next % _music_players.size()]
			_music_next += 1
			tp.stream = _timpani_clip
			tp.volume_db = linear_to_db(0.16 * _tension_cur)
			tp.pitch_scale = 0.95 + randf() * 0.1
			tp.play()


# ============================================================================
# PCM Synthesis Helpers
# ============================================================================

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s & 0xff
		bytes[i * 2 + 1] = (s >> 8) & 0xff
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


func _synth(dur: float, fn: Callable, loop: bool = false) -> AudioStreamWAV:
	var n := maxi(64, int(dur * float(RATE)))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var state := {"lp": 0.0, "hp": 0.0, "ph": 0.0, "ph2": 0.0, "seed": 1234567}
	for i in n:
		var t := float(i) / float(RATE)
		var u := float(i) / float(n)
		buf[i] = float(fn.call(t, u, state))
	return _make_wav(buf, loop)


func _noise(state: Dictionary) -> float:
	var x: int = int(state["seed"])
	x = (x * 1664525 + 1013904223) & 0x7fffffff
	state["seed"] = x
	return (float(x) / 1073741824.0) - 1.0


func _lp(val: float, alpha: float, state: Dictionary, key: String = "lp") -> float:
	var prev := float(state.get(key, 0.0))
	prev += alpha * (val - prev)
	state[key] = prev
	return prev


# ============================================================================
# SFX Bank (31 Cues + Fire Crackle)
# ============================================================================

func _build_sfx_bank() -> void:
	# 1. Bow twang + arrow whoosh
	sfx_clips["bow"] = _synth(0.16, func(t: float, u: float, st: Dictionary) -> float:
		var env := exp(-t * 28.0)
		var f := lerpf(420.0, 170.0, u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var twang := sin(float(st["ph"])) * 0.45 * env
		var whoosh := _lp(_noise(st), 0.25, st) * exp(-t * 22.0) * 0.45
		return twang + whoosh
	)

	# 2. Arrow thud hit
	sfx_clips["arrowHit"] = _synth(0.09, func(t: float, u: float, st: Dictionary) -> float:
		var env := exp(-t * 48.0)
		var thud := sin(TAU * lerpf(210.0, 68.0, u) * t) * 0.65 * env
		var snap := _lp(_noise(st), 0.4, st) * exp(-t * 60.0) * 0.4
		return thud + snap
	)

	# 3. Bombard cannon boom
	sfx_clips["cannon"] = _synth(0.52, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(135.0, 32.0, pow(u, 0.45))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var punch := sin(float(st["ph"])) * exp(-t * 7.5) * 0.85
		var blast := _lp(_noise(st), 0.14, st) * exp(-t * 6.5) * 0.9
		return clampf((punch + blast) * 1.15, -1.0, 1.0)
	)

	# 4. Explosion
	sfx_clips["explode"] = _synth(0.68, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(110.0, 24.0, pow(u, 0.5))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var sub := sin(float(st["ph"])) * exp(-t * 5.2) * 0.75
		var roar := _lp(_noise(st), 0.09 + 0.18 * (1.0 - u), st) * exp(-t * 4.4) * 1.15
		var crack := _noise(st) * exp(-t * 36.0) * 0.5
		return tanh((sub + roar + crack) * 1.2)
	)

	# 5. Storm spire charge hum
	sfx_clips["charge"] = _synth(0.28, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(240.0, 880.0, u * u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return (sin(float(st["ph"])) * 0.4 + sin(float(st["ph"]) * 2.0) * 0.18) * sin(u * PI)
	)

	# 6. Lightning zap crack
	sfx_clips["zap"] = _synth(0.26, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(1450.0, 180.0, pow(u, 0.4))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var arc := (1.0 if sin(float(st["ph"])) > 0.0 else -1.0) * 0.35 * exp(-t * 14.0)
		var crackle := _noise(st) * exp(-t * 16.0) * 0.72
		return tanh((arc + crackle) * 1.3)
	)

	# 7. Steel clash
	sfx_clips["clash"] = _synth(0.20, func(t: float, _u: float, st: Dictionary) -> float:
		var ring := (sin(TAU * 1180.0 * t) + sin(TAU * 1790.0 * t) * 0.7 + sin(TAU * 2640.0 * t) * 0.45) * exp(-t * 22.0) * 0.28
		var hit := _noise(st) * exp(-t * 55.0) * 0.45
		return ring + hit
	)

	# 8. Melee slash
	sfx_clips["slash"] = _synth(0.14, func(t: float, u: float, st: Dictionary) -> float:
		var env := sin(u * PI) * exp(-t * 10.0)
		var sw := _lp(_noise(st), 0.18 + 0.32 * sin(u * PI), st) * env * 0.85
		return sw
	)

	# 9. Rat squeal
	sfx_clips["ratSqueal"] = _synth(0.14, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(1650.0, 920.0, u) + sin(t * 95.0) * 180.0
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return sin(float(st["ph"])) * sin(u * PI) * 0.35
	)

	# 10. Skeleton bone rattle
	sfx_clips["boneRattle"] = _synth(0.22, func(t: float, _u: float, st: Dictionary) -> float:
		var clicks := 0.0
		for k in [0.0, 0.055, 0.115]:
			var dt2 := t - float(k)
			if dt2 >= 0.0 and dt2 < 0.04:
				clicks += sin(TAU * (820.0 + float(k) * 1800.0) * dt2) * exp(-dt2 * 90.0)
		return clicks * 0.5 + _lp(_noise(st), 0.35, st) * exp(-t * 24.0) * 0.25
	)

	# 11. Slime squelch
	sfx_clips["squelch"] = _synth(0.18, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(160.0, 460.0, sin(u * PI))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return (sin(float(st["ph"])) * 0.45 + _lp(_noise(st), 0.2, st) * 0.35) * exp(-t * 16.0)
	)

	# 12. Bat screech
	sfx_clips["batScreech"] = _synth(0.16, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(2400.0, 1300.0, u) + sin(t * 140.0) * 240.0
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return sin(float(st["ph"])) * sin(u * PI) * 0.3
	)

	# 13. Monster/Ogre roar
	sfx_clips["roar"] = _synth(0.46, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(130.0, 72.0, u) + sin(t * 28.0) * 14.0
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var gr := tanh(sin(float(st["ph"])) * 2.4 + _lp(_noise(st), 0.12, st) * 1.4)
		return gr * sin(u * PI) * 0.65
	)

	# 14. Boss footstep
	sfx_clips["bossStep"] = _synth(0.32, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(85.0, 28.0, u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return (sin(float(st["ph"])) * 0.8 + _lp(_noise(st), 0.08, st) * 0.55) * exp(-t * 11.0)
	)

	# 15. Boss death detonation
	sfx_clips["bossDie"] = _synth(1.25, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(140.0, 22.0, pow(u, 0.55))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var sub := sin(float(st["ph"])) * exp(-t * 2.4) * 0.85
		var rumble := _lp(_noise(st), 0.08, st) * exp(-t * 2.0) * 1.1
		var bell := sin(TAU * 220.0 * t) * exp(-t * 3.5) * 0.25
		return tanh((sub + rumble + bell) * 1.2)
	)

	# 16. Gold coin clink
	sfx_clips["coin"] = _synth(0.18, func(t: float, _u: float, _st: Dictionary) -> float:
		var a := sin(TAU * 1760.0 * t) * exp(-t * 26.0)
		var b := sin(TAU * 2637.0 * maxf(0.0, t - 0.035)) * (1.0 if t > 0.035 else 0.0) * exp(-maxf(0.0, t - 0.035) * 22.0)
		return (a + b) * 0.34
	)

	# 17. Construction hammer tap
	sfx_clips["hammer"] = _synth(0.12, func(t: float, u: float, st: Dictionary) -> float:
		var knock := sin(TAU * lerpf(540.0, 160.0, u) * t) * exp(-t * 42.0) * 0.65
		var clack := _lp(_noise(st), 0.45, st) * exp(-t * 70.0) * 0.45
		return knock + clack
	)

	# 18. Tower build complete chord
	sfx_clips["buildDone"] = _synth(0.42, func(t: float, _u: float, _st: Dictionary) -> float:
		var s := sin(TAU * 293.66 * t) + sin(TAU * 440.0 * t) * 0.75 + sin(TAU * 587.33 * t) * 0.55
		return s * exp(-t * 6.5) * 0.24
	)

	# 19. Sell coins scatter
	sfx_clips["sell"] = _synth(0.30, func(t: float, _u: float, _st: Dictionary) -> float:
		var acc := 0.0
		for i in 4:
			var dt2 := t - float(i) * 0.055
			if dt2 > 0.0:
				acc += sin(TAU * (1500.0 + float(i) * 340.0) * dt2) * exp(-dt2 * 28.0)
		return acc * 0.26
	)

	# 20. Wave war horn
	sfx_clips["horn"] = _synth(0.95, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(146.8, 164.8, U.smooth(0.0, 0.25, u))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var brass := tanh((sin(float(st["ph"])) + 0.55 * sin(float(st["ph"]) * 2.0) + 0.3 * sin(float(st["ph"]) * 3.0)) * 1.4)
		var env := U.smooth(0.0, 0.14, u) * (1.0 - U.smooth(0.65, 1.0, u))
		return brass * env * 0.42
	)

	# 21. Boss deep war horn
	sfx_clips["hornBoss"] = _synth(1.45, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(73.4, 82.4, U.smooth(0.0, 0.22, u))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		st["ph2"] = float(st["ph2"]) + TAU * (f * 1.498) / float(RATE)
		var brass := tanh((sin(float(st["ph"])) + 0.65 * sin(float(st["ph"]) * 2.0) + 0.4 * sin(float(st["ph2"]))) * 1.6)
		var env := U.smooth(0.0, 0.12, u) * (1.0 - U.smooth(0.68, 1.0, u))
		return brass * env * 0.5
	)

	# 22. Keep leak alarm
	sfx_clips["leak"] = _synth(0.45, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(240.0, 110.0, u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return tanh(sin(float(st["ph"])) * 2.0) * exp(-t * 5.0) * 0.5
	)

	# 23. Footman death grunt
	sfx_clips["footmanDie"] = _synth(0.24, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(210.0, 95.0, u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return (sin(float(st["ph"])) * 0.5 + _lp(_noise(st), 0.18, st) * 0.3) * exp(-t * 12.0)
	)

	# 24-26. UI cues
	sfx_clips["uiHover"] = _synth(0.045, func(t: float, _u: float, _st: Dictionary) -> float:
		return sin(TAU * 920.0 * t) * exp(-t * 85.0) * 0.22
	)
	sfx_clips["uiClick"] = _synth(0.075, func(t: float, u: float, _st: Dictionary) -> float:
		return sin(TAU * lerpf(640.0, 960.0, u) * t) * exp(-t * 55.0) * 0.34
	)
	sfx_clips["uiDeny"] = _synth(0.14, func(t: float, u: float, _st: Dictionary) -> float:
		return sin(TAU * lerpf(220.0, 145.0, u) * t) * exp(-t * 22.0) * 0.38
	)

	# 27. Stage crumble rumble
	sfx_clips["crumble"] = _synth(1.4, func(t: float, u: float, st: Dictionary) -> float:
		var env := U.smooth(0.0, 0.12, u) * (1.0 - U.smooth(0.65, 1.0, u))
		var rum := _lp(_noise(st), 0.055, st) * 1.4
		var sub := sin(TAU * lerpf(64.0, 26.0, u) * t) * 0.55
		return tanh((rum + sub) * env * 1.3) * 0.72
	)

	# 28. Stage rise swell
	sfx_clips["rise"] = _synth(1.3, func(t: float, u: float, st: Dictionary) -> float:
		var env := U.smooth(0.0, 0.2, u) * (1.0 - U.smooth(0.75, 1.0, u))
		var f := lerpf(52.0, 146.8, u)
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		var hum := sin(float(st["ph"])) * 0.45 + _lp(_noise(st), 0.07 + 0.08 * u, st) * 0.7
		return tanh(hum * env * 1.2) * 0.62
	)

	# 29. Beacon snuffed out
	sfx_clips["beaconOut"] = _synth(0.75, func(t: float, u: float, st: Dictionary) -> float:
		var hiss := _lp(_noise(st), 0.25 * (1.0 - u * 0.7), st) * exp(-t * 4.2) * 0.85
		var drop := sin(TAU * lerpf(280.0, 48.0, u) * t) * exp(-t * 5.5) * 0.5
		return hiss + drop
	)

	# 30. Beacon ignite whoosh
	sfx_clips["ignite"] = _synth(0.95, func(t: float, u: float, st: Dictionary) -> float:
		var env := U.smooth(0.0, 0.08, u) * exp(-t * 2.8)
		var whoosh := _lp(_noise(st), 0.16, st) * env * 1.2
		var shimmer := (sin(TAU * 293.66 * t) + sin(TAU * 440.0 * t) * 0.6 + sin(TAU * 587.33 * t) * 0.4) * env * 0.26
		return tanh((whoosh + shimmer) * 1.2) * 0.72
	)

	# 31. Water / swamp splash
	sfx_clips["splash"] = _synth(0.24, func(t: float, u: float, st: Dictionary) -> float:
		var env := sin(u * PI) * exp(-t * 9.0)
		return _lp(_noise(st), 0.28, st) * env * 0.65
	)

	# Internal campfire crackle pop
	sfx_clips["_crackle"] = _synth(0.035, func(t: float, _u: float, st: Dictionary) -> float:
		return _noise(st) * exp(-t * 140.0) * 0.85
	)


func _build_ambient_loops() -> void:
	# Wind loop (3.5s seamless)
	var wind_wav := _synth(3.5, func(_t: float, u: float, st: Dictionary) -> float:
		var swell := 0.7 + 0.3 * sin(u * TAU)
		return _lp(_noise(st), 0.035 + 0.025 * sin(u * TAU), st) * swell * 1.4
	, true)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = wind_wav
	_wind_player.volume_db = -60.0
	add_child(_wind_player)
	_wind_player.play()

	# Campfire low roar loop (3.0s seamless)
	var fire_wav := _synth(3.0, func(_t: float, u: float, st: Dictionary) -> float:
		var mod := 0.78 + 0.22 * sin(u * TAU * 3.0)
		return _lp(_noise(st), 0.06, st) * mod * 1.5
	, true)
	_fire_player = AudioStreamPlayer.new()
	_fire_player.stream = fire_wav
	_fire_player.volume_db = -60.0
	add_child(_fire_player)
	_fire_player.play()

	# Boss tension sub-drone loop (4.0s seamless)
	var drone_wav := _synth(4.0, func(t: float, u: float, _st: Dictionary) -> float:
		var lfo := 0.7 + 0.3 * sin(u * TAU)
		return (sin(TAU * 55.0 * t) * 0.6 + sin(TAU * 82.41 * t) * 0.35 + sin(TAU * 110.0 * t) * 0.2) * lfo
	, true)
	_drone_player = AudioStreamPlayer.new()
	_drone_player.stream = drone_wav
	_drone_player.volume_db = -60.0
	add_child(_drone_player)
	_drone_player.play()


func _build_music_bank() -> void:
	# 4 dark-fantasy modal pad chords (Dm, Bb, C, Am)
	var chords := [
		[146.83, 220.00, 261.63, 349.23], # Dm7
		[116.54, 174.61, 220.00, 293.66], # BbMaj7
		[130.81, 196.00, 261.63, 329.63], # C
		[110.00, 164.81, 220.00, 261.63], # Am
	]
	for ch in chords:
		var freqs: Array = ch
		_chord_clips.append(_synth(5.2, func(t: float, u: float, _st: Dictionary) -> float:
			var env := U.smooth(0.0, 0.28, u) * (1.0 - U.smooth(0.55, 1.0, u))
			var s := 0.0
			for f in freqs:
				var fv := float(f)
				s += sin(TAU * fv * t) * 0.28 + sin(TAU * (fv * 1.003) * t) * 0.14
			return s * env * 0.55
		))

	# Sparse D-minor pentatonic piano notes
	var notes := [293.66, 349.23, 392.00, 440.00, 523.25, 587.33, 659.25]
	for nf in notes:
		var f0 := float(nf)
		_piano_clips.append(_synth(2.4, func(t: float, _u: float, _st: Dictionary) -> float:
			var env := (1.0 - exp(-t * 95.0)) * exp(-t * 1.9)
			var s := sin(TAU * f0 * t) * 0.65 + sin(TAU * f0 * 2.0 * t) * 0.22 * exp(-t * 3.5) + sin(TAU * f0 * 3.0 * t) * 0.08 * exp(-t * 6.0)
			return s * env * 0.52
		))

	# Deep timpani drum pulse
	_timpani_clip = _synth(0.65, func(t: float, u: float, st: Dictionary) -> float:
		var f := lerpf(92.0, 58.0, pow(u, 0.35))
		st["ph"] = float(st["ph"]) + TAU * f / float(RATE)
		return (sin(float(st["ph"])) * 0.8 + sin(float(st["ph"]) * 1.5) * 0.22) * exp(-t * 5.2)
	)
