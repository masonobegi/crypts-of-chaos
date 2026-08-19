extends Node
## Procedural audio. Every sound in the game is synthesised at runtime into an
## AudioStreamWAV, so the project ships with zero audio assets and new sounds are
## a few lines of maths rather than a trip to a sample library.

const SR := 22050
const MAX_VOICES := 24

var _cache: Dictionary = {}          ## name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next3d := 0
var master_volume := 0.7

## name -> [waveform, freq, dur, decay, noise_mix, sweep, vibrato]
const RECIPES := {
	"beep":      {"w": "sine",  "f": 880.0, "d": 0.08, "dec": 14.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	"beep_low":  {"w": "sine",  "f": 320.0, "d": 0.12, "dec": 10.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	"ding":      {"w": "sine",  "f": 1320.0,"d": 0.5,  "dec": 6.0,  "n": 0.0,  "sw": 0.0,   "vib": 3.0},
	"error":     {"w": "square","f": 180.0, "d": 0.22, "dec": 9.0,  "n": 0.02, "sw": -0.35, "vib": 0.0},
	"money":     {"w": "sine",  "f": 1046.0,"d": 0.35, "dec": 7.0,  "n": 0.0,  "sw": 0.55,  "vib": 0.0},
	"thud":      {"w": "sine",  "f": 90.0,  "d": 0.18, "dec": 22.0, "n": 0.25, "sw": -0.5,  "vib": 0.0},
	"clatter":   {"w": "noise", "f": 400.0, "d": 0.35, "dec": 12.0, "n": 1.0,  "sw": -0.2,  "vib": 0.0},
	"glass":     {"w": "noise", "f": 2600.0,"d": 0.4,  "dec": 11.0, "n": 0.8,  "sw": -0.1,  "vib": 0.0},
	"squeak":    {"w": "saw",   "f": 700.0, "d": 0.16, "dec": 10.0, "n": 0.06, "sw": 0.4,   "vib": 22.0},
	"step":      {"w": "noise", "f": 200.0, "d": 0.07, "dec": 30.0, "n": 1.0,  "sw": -0.3,  "vib": 0.0},
	"paper":     {"w": "noise", "f": 3000.0,"d": 0.14, "dec": 18.0, "n": 1.0,  "sw": 0.2,   "vib": 0.0},
	"machine_on":{"w": "saw",   "f": 120.0, "d": 0.7,  "dec": 2.2,  "n": 0.05, "sw": 0.5,   "vib": 5.0},
	"machine_bad":{"w":"square","f": 70.0,  "d": 0.9,  "dec": 2.0,  "n": 0.15, "sw": -0.25, "vib": 11.0},
	"alarm":     {"w": "square","f": 660.0, "d": 0.6,  "dec": 1.5,  "n": 0.0,  "sw": 0.0,   "vib": 9.0},
	"gasp":      {"w": "noise", "f": 900.0, "d": 0.3,  "dec": 7.0,  "n": 1.0,  "sw": 0.6,   "vib": 0.0},
	"grunt":     {"w": "saw",   "f": 130.0, "d": 0.22, "dec": 11.0, "n": 0.3,  "sw": -0.3,  "vib": 4.0},
	"whoosh":    {"w": "noise", "f": 500.0, "d": 0.3,  "dec": 8.0,  "n": 1.0,  "sw": 0.8,   "vib": 0.0},
	"suspicion": {"w": "sine",  "f": 210.0, "d": 0.8,  "dec": 3.0,  "n": 0.02, "sw": -0.2,  "vib": 2.0},
	"stamp":     {"w": "noise", "f": 150.0, "d": 0.12, "dec": 26.0, "n": 0.9,  "sw": -0.4,  "vib": 0.0},
	"heartbeat": {"w": "sine",  "f": 55.0,  "d": 0.25, "dec": 12.0, "n": 0.0,  "sw": -0.2,  "vib": 0.0},
	"pickup":    {"w": "sine",  "f": 520.0, "d": 0.09, "dec": 16.0, "n": 0.05, "sw": 0.35,  "vib": 0.0},
	"drop":      {"w": "sine",  "f": 300.0, "d": 0.1,  "dec": 18.0, "n": 0.15, "sw": -0.4,  "vib": 0.0},
	"door":      {"w": "saw",   "f": 180.0, "d": 0.35, "dec": 7.0,  "n": 0.2,  "sw": -0.3,  "vib": 3.0},
	"tick":      {"w": "noise", "f": 1800.0,"d": 0.04, "dec": 40.0, "n": 1.0,  "sw": 0.0,   "vib": 0.0},
	"cough":     {"w": "noise", "f": 420.0, "d": 0.22, "dec": 13.0, "n": 1.0,  "sw": -0.5,  "vib": 0.0},
	"monitor":   {"w": "sine",  "f": 1180.0,"d": 0.09, "dec": 16.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	"trolley":   {"w": "noise", "f": 260.0, "d": 0.5,  "dec": 5.0,  "n": 1.0,  "sw": 0.1,   "vib": 7.0},
	"pipe":      {"w": "sine",  "f": 95.0,  "d": 0.8,  "dec": 3.5,  "n": 0.12, "sw": -0.15, "vib": 1.5},
	# The three that arrived with the shift loop. A snap for something giving
	# way under your hands, a wet drag for theatre, and a rattle for a bottle of
	# pills going into somebody's bag.
	"snap":      {"w": "noise", "f": 1400.0,"d": 0.11, "dec": 34.0, "n": 0.85, "sw": -0.65, "vib": 0.0},
	"theatre":   {"w": "noise", "f": 240.0, "d": 0.55, "dec": 6.0,  "n": 0.9,  "sw": -0.25, "vib": 3.0},
	"pills":     {"w": "noise", "f": 2100.0,"d": 0.22, "dec": 15.0, "n": 1.0,  "sw": 0.15,  "vib": 26.0},
}

## The continuous bed: a long, low, quietly unpleasant loop. Built separately
## from the one-shots because it needs seamless looping rather than a decay.
const HUM_SECONDS := 3.0

func _ready() -> void:
	# UI screens pause the tree; sound must keep working while they are open.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_voices()

## Built lazily rather than only in _ready(): headless tooling drives the game
## from a SceneTree script, whose _initialize() runs BEFORE any node's _ready(),
## so anything that plays a sound during setup would otherwise index an empty
## voice pool.
func _ensure_voices() -> void:
	if not _players.is_empty():
		return
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 30.0
		p.unit_size = 4.0
		add_child(p)
		_players3d.append(p)

# ------------------------------------------------------------------ synthesis
func _build(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var r: Dictionary = RECIPES.get(name, RECIPES["beep"])
	var dur: float = float(r["d"])
	var n_samples := int(dur * SR)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var phase := 0.0
	var base_f: float = float(r["f"])
	for i in n_samples:
		var t := float(i) / float(SR)
		var prog := t / dur
		var f: float = base_f * (1.0 + float(r["sw"]) * prog)
		if float(r["vib"]) > 0.0:
			f *= 1.0 + 0.06 * sin(TAU * float(r["vib"]) * t)
		phase += TAU * f / float(SR)
		var s := 0.0
		match String(r["w"]):
			"sine": s = sin(phase)
			"square": s = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw": s = fposmod(phase, TAU) / PI - 1.0
			"noise": s = rng.randf_range(-1.0, 1.0)
		var nm: float = float(r["n"])
		if nm > 0.0 and String(r["w"]) != "noise":
			s = lerpf(s, rng.randf_range(-1.0, 1.0), nm)
		# Band-ish shaping for noise so it isn't pure hiss.
		var env: float = exp(-float(r["dec"]) * t)
		# Short fade-in kills the click on attack.
		env *= clampf(t / 0.004, 0.0, 1.0)
		var v := int(clampf(s * env * 22000.0, -32768.0, 32767.0))
		var uv := v & 0xFFFF
		data[i * 2] = uv & 0xFF
		data[i * 2 + 1] = (uv >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR
	st.stereo = false
	st.data = data
	_cache[name] = st
	return st

# ------------------------------------------------------------------ ambience
var _hum_player: AudioStreamPlayer = null

## Builds the room tone: two detuned low tones plus filtered noise, loop-enabled
## so it runs continuously without a seam. Cross-faded at the ends so the loop
## point is inaudible.
func _build_hum() -> AudioStreamWAV:
	if _cache.has("__hum"):
		return _cache["__hum"]
	var n_samples := int(HUM_SECONDS * SR)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA11BEE
	var lp := 0.0
	for i in n_samples:
		var t := float(i) / float(SR)
		# Frequencies chosen so a whole number of cycles fits the buffer, which
		# is what makes the loop seamless without any cross-fade.
		var a := sin(TAU * 50.0 * t) * 0.5
		var b := sin(TAU * 74.0 * t) * 0.3
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.02)
		var s := a + b + lp * 0.5
		var v := int(clampf(s * 2600.0, -32768.0, 32767.0))
		var uv := v & 0xFFFF
		data[i * 2] = uv & 0xFF
		data[i * 2 + 1] = (uv >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n_samples
	_cache["__hum"] = st
	return st

func start_ambience(volume_db := -30.0) -> void:
	_ensure_voices()
	if _hum_player == null:
		_hum_player = AudioStreamPlayer.new()
		_hum_player.name = "Hum"
		add_child(_hum_player)
	_hum_player.stream = _build_hum()
	_hum_player.volume_db = volume_db + linear_to_db(master_volume)
	_hum_player.play()

func stop_ambience() -> void:
	if _hum_player:
		_hum_player.stop()

# ------------------------------------------------------------------ playback
func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	_ensure_voices()
	var st := _build(name)
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.volume_db = volume_db + linear_to_db(master_volume)
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

func play_at(name: String, pos: Vector3, volume_db: float = -4.0, pitch: float = 1.0) -> void:
	_ensure_voices()
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		play(name, volume_db, pitch)
		return
	var st := _build(name)
	var p := _players3d[_next3d]
	_next3d = (_next3d + 1) % _players3d.size()
	p.global_position = pos
	p.stream = st
	p.volume_db = volume_db + linear_to_db(master_volume)
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

## Slight random pitch keeps repeated sounds from sounding like a machine gun.
func play_var(name: String, volume_db: float = -6.0, spread: float = 0.12) -> void:
	play(name, volume_db, 1.0 + randf_range(-spread, spread))

func play_at_var(name: String, pos: Vector3, volume_db: float = -4.0, spread: float = 0.12) -> void:
	play_at(name, pos, volume_db, 1.0 + randf_range(-spread, spread))
