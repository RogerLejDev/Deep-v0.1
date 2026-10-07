extends Node
## Autoload: Audio
##
## Every sound in DEEP V0.1 is synthesised at boot into AudioStreamWAV buffers.
## That keeps the repository free of binary audio while still giving real,
## tuned feedback for mining, pickups, discovery and ambience. Replacing a
## synthesised cue with an authored .ogg later is a one-line change in `_bank`.

const SAMPLE_RATE: int = 22050

var _bank: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _ambient_active_is_a: bool = true
var _ambient_target: String = ""
var _rng := RandomNumberGenerator.new()

var sfx_volume_db: float = -6.0
var ambient_volume_db: float = -16.0
var muted: bool = false


func _ready() -> void:
	_rng.randomize()
	_build_bank()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	_ambient_a = AudioStreamPlayer.new()
	_ambient_b = AudioStreamPlayer.new()
	for p in [_ambient_a, _ambient_b]:
		p.volume_db = -60.0
		add_child(p)
	EventBus.block_hit.connect(_on_block_hit)
	EventBus.block_mined.connect(_on_block_mined)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.item_crafted.connect(func(_i: String, _a: int) -> void: play("craft"))
	EventBus.codex_entry_discovered.connect(func(_s: String, _v: String) -> void: play("discovery"))
	EventBus.player_damaged.connect(func(_a: float, _s: String) -> void: play("hurt"))


# --- Public ------------------------------------------------------------------

func play(id: String, pitch: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if muted or not _bank.has(id):
		return
	var p := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	p.stream = _bank[id]
	p.pitch_scale = clampf(pitch, 0.4, 2.4)
	p.volume_db = sfx_volume_db + volume_offset_db
	p.play()


func play_varied(id: String, spread: float = 0.12) -> void:
	play(id, 1.0 + _rng.randf_range(-spread, spread))


## Cross-fade the looping ambience. `id` is an ambience bank key.
func set_ambience(id: String) -> void:
	if id == _ambient_target or not _bank.has(id):
		return
	_ambient_target = id
	var incoming := _ambient_b if _ambient_active_is_a else _ambient_a
	var outgoing := _ambient_a if _ambient_active_is_a else _ambient_b
	_ambient_active_is_a = not _ambient_active_is_a
	incoming.stream = _bank[id]
	incoming.volume_db = -60.0
	incoming.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", ambient_volume_db if not muted else -60.0, 2.2)
	tw.tween_property(outgoing, "volume_db", -60.0, 2.2)
	tw.chain().tween_callback(outgoing.stop)


func set_muted(value: bool) -> void:
	muted = value
	var cur := _ambient_a if _ambient_active_is_a else _ambient_b
	cur.volume_db = -60.0 if muted else ambient_volume_db


# --- Signal glue -------------------------------------------------------------

func _on_block_hit(_tile: Vector2i, _block_id: int, _progress: float) -> void:
	play("pick_tap", _rng.randf_range(0.88, 1.18), -3.0)


func _on_block_mined(_tile: Vector2i, block_id: int, _by_player: bool) -> void:
	var def := BlockDB.get_block(block_id)
	play_varied("crystal_break" if def.emission > 0.05 else "rock_break", 0.1)


func _on_item_collected(_item_id: String, _amount: int) -> void:
	play("pickup", _rng.randf_range(0.95, 1.2))


# --- Synthesis ---------------------------------------------------------------

func _build_bank() -> void:
	_bank["pick_tap"] = _make(_syn_pick_tap(0.085))
	_bank["rock_break"] = _make(_syn_break(0.26, 160.0))
	_bank["crystal_break"] = _make(_syn_crystal(0.42))
	_bank["pickup"] = _make(_syn_blip(0.14, 740.0, 1180.0))
	_bank["craft"] = _make(_syn_craft(0.34))
	_bank["jump"] = _make(_syn_blip(0.10, 300.0, 520.0))
	_bank["land"] = _make(_syn_break(0.12, 90.0))
	_bank["hurt"] = _make(_syn_hurt(0.2))
	_bank["ui_click"] = _make(_syn_blip(0.055, 520.0, 420.0))
	_bank["discovery"] = _make(_syn_discovery(1.5))
	_bank["creature_chirp"] = _make(_syn_chirp(0.17))
	_bank["amb_surface"] = _make(_syn_ambience(4.0, 0.0), true)
	_bank["amb_shallow"] = _make(_syn_ambience(4.0, 1.0), true)
	_bank["amb_deep"] = _make(_syn_ambience(4.0, 2.0), true)


func _make(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _buffer(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * SAMPLE_RATE))
	return a


func _syn_pick_tap(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := buf.size()
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * 58.0)
		var body: float = sin(TAU * 220.0 * t) * 0.4
		var click: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 180.0)
		buf[i] = (body + click * 0.7) * env
	return buf


func _syn_break(d: float, base: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * 14.0)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.22)
		var thump: float = sin(TAU * base * t * (1.0 - t * 1.4)) * exp(-t * 26.0)
		buf[i] = (lp * 0.8 + thump * 0.5) * env
	return buf


func _syn_crystal(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var partials := [1420.0, 1890.0, 2610.0, 3310.0]
	for i in buf.size():
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * 7.5)
		var v := 0.0
		for k in partials.size():
			v += sin(TAU * float(partials[k]) * t) * (0.34 / (k + 1))
		var shatter := _rng.randf_range(-1.0, 1.0) * exp(-t * 48.0) * 0.5
		buf[i] = (v + shatter) * env
	return buf


func _syn_blip(d: float, f0: float, f1: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := maxi(buf.size(), 1)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var u := float(i) / float(n)
		var f: float = lerpf(f0, f1, u * u)
		phase += TAU * f / SAMPLE_RATE
		var env: float = sin(PI * u) * exp(-t * 7.0)
		buf[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.2) * env
	return buf


func _syn_craft(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := buf.size()
	for i in n:
		var t := float(i) / SAMPLE_RATE
		# Two metallic taps, slight delay on the second.
		var a: float = exp(-maxf(t, 0.0) * 30.0)
		var b: float = exp(-maxf(t - 0.09, 0.0) * 30.0) if t > 0.09 else 0.0
		var tone: float = sin(TAU * 540.0 * t) + sin(TAU * 810.0 * t) * 0.6
		buf[i] = tone * (a * 0.5 + b * 0.45) * 0.6
	return buf


func _syn_hurt(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := maxi(buf.size(), 1)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f: float = lerpf(420.0, 110.0, u)
		phase += TAU * f / SAMPLE_RATE
		var env: float = exp(-u * 5.5)
		var grit := _rng.randf_range(-1.0, 1.0) * 0.35
		buf[i] = (sin(phase) * 0.8 + grit) * env
	return buf


func _syn_chirp(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := maxi(buf.size(), 1)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f: float = 900.0 + sin(u * PI * 3.0) * 420.0
		phase += TAU * f / SAMPLE_RATE
		buf[i] = sin(phase) * sin(PI * u) * 0.5
	return buf


func _syn_discovery(d: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := maxi(buf.size(), 1)
	# Rising shimmer plus a resolving minor-to-major third.
	var notes := [392.0, 523.25, 659.25, 783.99]
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var u := float(i) / float(n)
		var v := 0.0
		for k in notes.size():
			var start := float(k) * 0.14
			if t < start:
				continue
			var lt := t - start
			var env: float = exp(-lt * 2.6)
			v += sin(TAU * float(notes[k]) * lt) * 0.26 * env
			v += sin(TAU * float(notes[k]) * 2.0 * lt) * 0.08 * env
		var shimmer: float = sin(TAU * 2400.0 * t + sin(t * 30.0) * 3.0) * 0.05 * sin(PI * u)
		buf[i] = (v + shimmer) * minf(1.0, u * 12.0)
	return buf


## depth_tier: 0 surface wind, 1 shallow drips, 2 deep cavern drone.
func _syn_ambience(d: float, depth_tier: float) -> PackedFloat32Array:
	var buf := _buffer(d)
	var n := maxi(buf.size(), 1)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var u := float(i) / float(n)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.04 - depth_tier * 0.011)
		lp2 = lerpf(lp2, lp, 0.08)
		var v: float = lp2 * (0.55 - depth_tier * 0.12)
		if depth_tier >= 1.0:
			# Low cavern drone, two detuned sines.
			v += sin(TAU * (48.0 - depth_tier * 8.0) * t) * 0.14
			v += sin(TAU * (72.5 - depth_tier * 10.0) * t) * 0.09
		if depth_tier >= 2.0:
			v += sin(TAU * 31.0 * t + sin(t * 0.7) * 2.0) * 0.12
		# Equal-power cross-fade at the loop seam so the loop is inaudible.
		var seam: float = minf(1.0, minf(u, 1.0 - u) * 24.0)
		buf[i] = v * seam
	return buf
