extends Node

## Procedural 8-bit audio engine
## Generates chiptune music and SFX entirely in GDScript — no audio files required.

# ─── Constants ────────────────────────────────────────────────────────────────
const SAMPLE_RATE  := 44100.0
const BPM          := 108.0
const STEP_SAMPLES := int(44100.0 * 60.0 / 108.0 / 4.0)  # samples per 16th note

# Note frequencies (Hz)
const R  := 0.0
const E2 := 82.41;   const G2 := 98.00
const A2 := 110.00;  const C3 := 130.81
const D3 := 146.83;  const E3 := 164.81
const G3 := 196.00;  const A3 := 220.00;  const B3 := 246.94
const C4 := 261.63;  const D4 := 293.66;  const E4 := 329.63
const G4 := 392.00;  const A4 := 440.00
const C5 := 523.25;  const E5 := 659.25;  const G5 := 783.99

# ─── Sequencer Data ──────────────────────────────────────────────────────────
# 64-step dungeon theme in A natural minor (Am pentatonic with passing tones)

var SEQ_LEAD: Array = [
	# Bar 1 – opening motif
	A3, R,  C4, R,  E4, D4, C4, R,
	# Bar 2
	A3, R,  G3, R,  A3, C4, E4, R,
	# Bar 3 – rising tension
	A3, B3, C4, D4, E4, R,  G4, R,
	# Bar 4 – descend
	E4, D4, C4, B3, A3, R,  A3, R,
	# Bar 5 – darker phrase
	G3, R,  A3, R,  C4, B3, A3, G3,
	# Bar 6
	E3, R,  G3, A3, E3, R,  R,  R,
	# Bar 7 – resolution climb
	A3, C4, E4, C4, A3, R,  G4, E4,
	# Bar 8 – resolve
	A3, R,  A3, R,  A3, R,  R,  R,
]

var SEQ_BASS: Array = [
	A2, R,  A2, R,  A2, R,  E3, R,
	A2, R,  G2, R,  A2, R,  E2, R,
	C3, R,  C3, R,  G2, R,  G2, R,
	A2, R,  A2, R,  A2, R,  A2, R,
	G2, R,  G2, R,  C3, R,  C3, R,
	E2, R,  E2, R,  A2, R,  A2, R,
	A2, R,  C3, R,  E3, R,  C3, R,
	A2, R,  A2, R,  A2, R,  A2, R,
]

# Drum pattern: 0=rest, 1=kick, 2=snare, 3=hihat
var SEQ_DRUM: Array = [
	1, 3, 3, 3,  2, 3, 1, 3,  1, 3, 3, 3,  2, 3, 3, 3,
	1, 3, 3, 3,  2, 3, 1, 3,  1, 3, 3, 3,  2, 3, 3, 3,
	1, 3, 3, 3,  2, 3, 1, 3,  1, 3, 3, 3,  2, 3, 3, 3,
	1, 3, 3, 3,  2, 3, 1, 3,  1, 3, 1, 3,  2, 0, 0, 0,
]

var seq_len: int = 0

# ─── Music State ─────────────────────────────────────────────────────────────
var music_player:   AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback

var seq_step:          int   = 0
var sample_in_step:    int   = 0

var phase_lead:  float = 0.0
var phase_bass:  float = 0.0
var phase_arp:   float = 0.0

var lead_freq:   float = 0.0
var bass_freq:   float = 0.0
var lead_env:    float = 0.0
var bass_env:    float = 0.0
var drum_env:    float = 0.0
var drum_noise:  float = 0.0
var drum_type:   int   = 0

var music_enabled: bool = true
var music_volume:  float = 0.55

# ─── SFX Pool ─────────────────────────────────────────────────────────────────
var sfx_pool:  Array = []   # Array of AudioStreamPlayer
const SFX_POOL_SIZE := 8
var sfx_index: int   = 0
var sfx_cache: Dictionary = {}   # name -> AudioStreamWAV

var sfx_volume: float = 0.85

# ─── Lifecycle ───────────────────────────────────────────────────────────────
func _ready() -> void:
	seq_len = SEQ_LEAD.size()
	_setup_music_player()
	_build_sfx_pool()
	_pregenerate_sfx()

func _setup_music_player() -> void:
	var gen             := AudioStreamGenerator.new()
	gen.mix_rate        = SAMPLE_RATE
	gen.buffer_length   = 0.08
	music_player        = AudioStreamPlayer.new()
	music_player.stream = gen
	music_player.volume_db = linear_to_db(music_volume)
	add_child(music_player)
	music_player.play()
	music_playback = music_player.get_stream_playback()

func _build_sfx_pool() -> void:
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = linear_to_db(sfx_volume)
		add_child(p)
		sfx_pool.append(p)

func _pregenerate_sfx() -> void:
	sfx_cache["attack"]  = _sfx_attack()
	sfx_cache["hit"]     = _sfx_hit()
	sfx_cache["pickup"]  = _sfx_pickup()
	sfx_cache["levelup"] = _sfx_levelup()
	sfx_cache["death"]   = _sfx_death()
	sfx_cache["scroll"]  = _sfx_scroll()
	sfx_cache["stairs"]  = _sfx_stairs()
	sfx_cache["gold"]    = _sfx_gold()
	sfx_cache["menu"]    = _sfx_menu()
	sfx_cache["denied"]  = _sfx_denied()

# ─── Process: fill music buffer ───────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not music_enabled or music_playback == null:
		return
	var avail := music_playback.get_frames_available()
	for _i in avail:
		var s := _next_sample()
		music_playback.push_frame(Vector2(s, s))

func _next_sample() -> float:
	# Advance sequencer step
	sample_in_step += 1
	if sample_in_step >= STEP_SAMPLES:
		sample_in_step = 0
		_advance_step()

	# Lead channel: square wave with envelope
	var lead_out := 0.0
	if lead_freq > 1.0:
		phase_lead += TAU * lead_freq / SAMPLE_RATE
		lead_out    = _sq(phase_lead) * lead_env * 0.28
		lead_env   *= 0.9998

	# Bass channel: square wave
	var bass_out := 0.0
	if bass_freq > 1.0:
		phase_bass += TAU * bass_freq / SAMPLE_RATE
		bass_out    = _sq(phase_bass) * bass_env * 0.22
		bass_env   *= 0.9999

	# Drum channel
	var drum_out := 0.0
	if drum_env > 0.001:
		match drum_type:
			1:  # kick
				drum_noise += 0.04
				drum_out    = sin(drum_noise * exp(-drum_env * 3.0) * 8.0) * drum_env * 0.35
			2:  # snare
				drum_out    = randf_range(-1.0, 1.0) * drum_env * 0.25
			3:  # hihat
				drum_out    = randf_range(-1.0, 1.0) * drum_env * 0.08
		drum_env *= 0.88 if drum_type == 3 else 0.93

	return clamp(lead_out + bass_out + drum_out, -1.0, 1.0)

# Square wave: fully typed to avoid sign() inference issues in lambdas
func _sq(phase: float) -> float:
	return 1.0 if sin(phase) >= 0.0 else -1.0

static func _sq_s(phase: float) -> float:
	return 1.0 if sin(phase) >= 0.0 else -1.0

func _advance_step() -> void:
	seq_step = (seq_step + 1) % seq_len

	var mel_f: float = SEQ_LEAD[seq_step]
	var bas_f: float = SEQ_BASS[seq_step]
	var drm:   int   = SEQ_DRUM[seq_step]

	if mel_f > 1.0:
		lead_freq = mel_f
		lead_env  = 1.0
		phase_lead = 0.0
	elif mel_f == R:
		lead_env = 0.0

	if bas_f > 1.0:
		bass_freq = bas_f
		bass_env  = 1.0
	elif bas_f == R:
		bass_env = 0.0

	if drm > 0:
		drum_type  = drm
		drum_env   = 1.0
		drum_noise = 0.0

# ─── Public API ───────────────────────────────────────────────────────────────
func play_sfx(name: String) -> void:
	if not sfx_cache.has(name):
		return
	var player := sfx_pool[sfx_index] as AudioStreamPlayer
	sfx_index   = (sfx_index + 1) % SFX_POOL_SIZE
	player.stream    = sfx_cache[name]
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func set_music_volume(vol: float) -> void:
	music_volume = vol
	if music_player:
		music_player.volume_db = linear_to_db(vol)

func stop_music() -> void:
	music_enabled = false
	if music_player:
		music_player.stop()

func start_music() -> void:
	music_enabled = true
	if music_player and not music_player.playing:
		music_player.play()
		music_playback = music_player.get_stream_playback()

# ─── SFX Generators ──────────────────────────────────────────────────────────
func _make_wav(duration_sec: float, gen_fn: Callable) -> AudioStreamWAV:
	var wav        := AudioStreamWAV.new()
	wav.format      = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate    = 22050
	wav.stereo      = false
	var n_samples   := int(22050.0 * duration_sec)
	var data        := PackedByteArray()
	data.resize(n_samples * 2)
	for i in n_samples:
		var t       := float(i) / 22050.0
		var val: float = gen_fn.call(t, duration_sec)
		var s       := int(clamp(val, -1.0, 1.0) * 28000.0)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	wav.data = data
	return wav

func _sfx_attack() -> AudioStreamWAV:
	# Short metallic sword slash: descending frequency square wave
	return _make_wav(0.14, func(t: float, dur: float) -> float:
		var env: float  = pow(1.0 - t / dur, 1.5)
		var freq: float = maxf(60.0, 480.0 - t * 2200.0)
		return _sq_s(TAU * freq * t) * env * 0.9
	)

func _sfx_hit() -> AudioStreamWAV:
	# Low thud when player is hit
	return _make_wav(0.18, func(t: float, dur: float) -> float:
		var env: float   = pow(1.0 - t / dur, 1.2)
		var freq: float  = maxf(40.0, 200.0 - t * 800.0)
		var tone: float  = _sq_s(TAU * freq * t) * 0.6
		var noise: float = randf_range(-0.3, 0.3) * 0.4
		return (tone + noise) * env
	)

func _sfx_pickup() -> AudioStreamWAV:
	# Cheerful ascending arpeggio
	return _make_wav(0.22, func(t: float, dur: float) -> float:
		var env: float   = 1.0 - t / dur
		var notes: Array = [523.25, 659.25, 783.99, 1046.5]
		var idx: int     = int(t / dur * notes.size())
		if idx >= notes.size(): idx = notes.size() - 1
		var freq: float  = float(notes[idx])
		return _sq_s(TAU * freq * t) * env * 0.75
	)

func _sfx_levelup() -> AudioStreamWAV:
	# Triumphant fanfare: fast ascending run
	return _make_wav(0.55, func(t: float, dur: float) -> float:
		var env: float  = 1.0 - t / dur * 0.4
		var freq: float = 261.63
		if   t < 0.08: freq = 261.63
		elif t < 0.16: freq = 329.63
		elif t < 0.24: freq = 392.00
		elif t < 0.32: freq = 523.25
		elif t < 0.40: freq = 659.25
		else:          freq = 783.99
		return _sq_s(TAU * freq * t) * env * 0.8
	)

func _sfx_death() -> AudioStreamWAV:
	# Sad descending chromatic scale
	return _make_wav(1.2, func(t: float, dur: float) -> float:
		var env: float   = pow(1.0 - t / dur, 0.5) * 0.9
		var notes: Array = [440.0, 415.30, 392.00, 369.99, 349.23, 329.63,
							311.13, 293.66, 277.18, 261.63, 246.94, 220.0]
		var idx: int     = int(t / dur * notes.size())
		if idx >= notes.size(): idx = notes.size() - 1
		var freq: float  = float(notes[idx])
		var noise: float = randf_range(-0.1, 0.1)
		return (_sq_s(TAU * freq * t) * 0.7 + noise) * env
	)

func _sfx_scroll() -> AudioStreamWAV:
	# Fire scroll: crackling burst then whoosh
	return _make_wav(0.4, func(t: float, _dur: float) -> float:
		var freq: float  = 800.0 + sin(t * 40.0) * 400.0
		var env: float   = exp(-t * 4.0)
		var noise: float = randf_range(-1.0, 1.0) * 0.5
		var tone: float  = _sq_s(TAU * freq * t) * 0.5
		return (tone + noise) * env
	)

func _sfx_stairs() -> AudioStreamWAV:
	# Portal sweep: two detuned oscillators
	return _make_wav(0.65, func(t: float, _dur: float) -> float:
		var freq1: float = 200.0 + t * 300.0
		var freq2: float = 250.0 + t * 280.0
		var env: float   = sin(t * PI / 0.65)
		var wave: float  = _sq_s(TAU * freq1 * t) * 0.5 + _sq_s(TAU * freq2 * t) * 0.5
		return wave * env * 0.8
	)

func _sfx_gold() -> AudioStreamWAV:
	# Coin chime: two high pings
	return _make_wav(0.18, func(t: float, dur: float) -> float:
		var env: float  = pow(1.0 - t / dur, 0.7)
		var freq: float = 1318.51 if t < 0.09 else 1567.98
		return sin(TAU * freq * t) * env * 0.9
	)

func _sfx_menu() -> AudioStreamWAV:
	# Soft UI click
	return _make_wav(0.08, func(t: float, dur: float) -> float:
		var env: float = 1.0 - t / dur
		return _sq_s(TAU * 660.0 * t) * env * 0.5
	)

func _sfx_denied() -> AudioStreamWAV:
	# Error buzz
	return _make_wav(0.1, func(t: float, dur: float) -> float:
		var env: float = 1.0 - t / dur
		return _sq_s(TAU * 120.0 * t) * env * 0.6
	)
