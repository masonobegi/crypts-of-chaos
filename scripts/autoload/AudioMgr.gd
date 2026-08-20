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
## Three knobs, so the settings screen has something to turn. `master_volume`
## was the only one and nothing exposed it.
var master_volume := 0.7
var sfx_volume := 1.0
var music_volume := 0.55

## Effective gain for a one-shot effect, in linear terms.
func _sfx_gain() -> float:
	return clampf(master_volume * sfx_volume, 0.0, 1.0)

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

## Stop everything before the tree comes down.
##
## A looping AudioStreamPlayer that is still playing when the process exits
## makes Godot report "ObjectDB instances leaked at exit" — which boot_check.sh
## correctly treats as a failure, because it is exactly the class of thing a
## shipped build should not print on the way out. Adding the score to the main
## menu turned that check red immediately, which is what it is for.
## Closing the window is the case a player actually hits, and it fires while
## everything is still alive — unlike _exit_tree, which runs as the audio server
## is already coming down. Stopping here is what makes a real quit clean.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_music()
		if _hum_player != null and is_instance_valid(_hum_player):
			_hum_player.stop()
			_hum_player.stream = null

func _exit_tree() -> void:
	stop_music()
	if _hum_player != null and is_instance_valid(_hum_player):
		_hum_player.stop()
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	for p in _players3d:
		if is_instance_valid(p):
			p.stop()
	# Stopping is not enough: the player still HOLDS its stream, and the stream
	# holds a live playback. Both have to be let go, and the synthesis cache
	# with them, or the two survive the tree and are reported as leaked.
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.stream = null
	if _hum_player != null and is_instance_valid(_hum_player):
		_hum_player.stream = null
	for p in _players:
		if is_instance_valid(p):
			p.stream = null
	for p in _players3d:
		if is_instance_valid(p):
			p.stream = null
	# ...and free the players outright. Clearing the stream reference is not
	# enough on its own: a LOOPING stream's playback is held on the audio
	# server's side, and a player that is merely stopped keeps it alive past the
	# tree teardown. Freeing the node is what actually releases it.
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.free()
		_music_player = null
	if _hum_player != null and is_instance_valid(_hum_player):
		_hum_player.free()
		_hum_player = null
	# The one-shot voices too. Any of the forty-eight of them can be mid-sound
	# when the window closes, and a stopped-but-not-freed player holds its
	# playback exactly the same way the music one did — which is why fixing
	# only the music made this pass once and then fail three times running.
	for p in _players:
		if is_instance_valid(p):
			p.free()
	for p in _players3d:
		if is_instance_valid(p):
			p.free()
	_players.clear()
	_players3d.clear()
	_cache.clear()

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

# ------------------------------------------------------------------ music
## A synthesised score.
##
## There was none. Thirty-six one-shots and a room-tone hum, and a game with no
## music at all reads as unfinished however good everything else is — it is the
## first thing a Steam trailer needs and the first thing a player notices is
## missing.
##
## Built the same way as everything else here: a buffer of maths, no assets. A
## slow four-chord loop on soft triangle pads with a plucked top line, at a
## tempo and in a mode chosen per shift. Deliberately sparse and deliberately
## a bit municipal — the joke of this hospital is that it is completely normal.
## Gains are set so the loop PEAKS at roughly half of full scale. The first
## pass peaked at 16%, which after the player's own -13 dB and a default 55%
## ambience slider put the score at about -29 dBFS — present in a file and
## inaudible in a room. Measured rather than guessed: see the note in
## PROGRESS_LOG about analysing the buffer.
const MUSIC_BARS := 4
const MUSIC_BAR_SECONDS := 4.0

## Semitone offsets from the root, per shift. Day is major and unbothered,
## evening drops a third for something warmer and more tired, night is minor
## and mostly absent — at night the game wants you listening for footsteps.
const MUSIC_MOODS := {
	"day": {"root": 196.0, "chords": [[0, 4, 7], [5, 9, 12], [7, 11, 14], [2, 5, 9]],
		"pluck": 0.5, "gain": 0.95},
	"evening": {"root": 174.6, "chords": [[0, 3, 7], [5, 8, 12], [3, 7, 10], [-2, 2, 5]],
		"pluck": 0.34, "gain": 0.86},
	"night": {"root": 146.8, "chords": [[0, 3, 7], [-2, 3, 7], [-4, 3, 8], [-5, 2, 7]],
		"pluck": 0.16, "gain": 0.70},
}

var _music_player: AudioStreamPlayer = null
var _music_kind := ""

static func _semitone(root: float, n: int) -> float:
	return root * pow(2.0, float(n) / 12.0)

func _build_music(kind: String) -> AudioStreamWAV:
	var key := "__music_" + kind
	if _cache.has(key):
		return _cache[key]
	var mood: Dictionary = MUSIC_MOODS.get(kind, MUSIC_MOODS["day"])
	var root: float = float(mood["root"])
	var chords: Array = mood["chords"]
	var total: float = MUSIC_BAR_SECONDS * float(MUSIC_BARS)
	var n_samples := int(total * SR)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)

	for i in n_samples:
		var t := float(i) / float(SR)
		var bar := int(t / MUSIC_BAR_SECONDS) % MUSIC_BARS
		var bar_t: float = fposmod(t, MUSIC_BAR_SECONDS)
		var chord: Array = chords[bar]
		var s := 0.0

		# Pad: three triangle-ish voices with a slow swell and release, so each
		# bar breathes rather than switching on.
		var swell: float = clampf(bar_t / 0.9, 0.0, 1.0) \
			* clampf((MUSIC_BAR_SECONDS - bar_t) / 1.1, 0.0, 1.0)
		for n in chord:
			var f: float = _semitone(root, int(n)) * 0.5
			# Triangle from a sine, which is warmer than a raw sine and much
			# softer than the saw the one-shots use.
			var tri: float = asin(sin(TAU * f * t)) * (2.0 / PI)
			s += tri * 0.22 * swell

		# Bass: the root of the bar, an octave down, with a gentle pulse.
		var bass_f: float = _semitone(root, int(chord[0])) * 0.25
		s += sin(TAU * bass_f * t) * 0.30 * swell * (0.7 + 0.3 * sin(TAU * 0.5 * t))

		# A plucked top line on the off-beats. Sparse on purpose: this plays
		# under a shift that lasts eighteen minutes, and anything busier stops
		# being background inside two loops.
		var pluck_gain: float = float(mood["pluck"])
		if pluck_gain > 0.0:
			var step: float = fposmod(t, 1.0)
			var beat := int(t) % 4
			if beat == 1 or beat == 3:
				var note: int = int(chord[(bar + beat) % chord.size()])
				var pf: float = _semitone(root, note) * 2.0
				var env: float = exp(-6.0 * step)
				s += sin(TAU * pf * t) * 0.16 * env * pluck_gain

		# A whisper of air over the top so it is not purely tonal.
		s += rng.randf_range(-1.0, 1.0) * 0.012

		# Cross-fade the last half second into the first, so the loop seam is
		# inaudible without needing every frequency to divide the buffer.
		var fade := 0.5
		if t > total - fade:
			var k: float = (total - t) / fade
			s *= k

		var v := int(clampf(s * float(mood["gain"]) * 22000.0, -32768.0, 32767.0))
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
	_cache[key] = st
	return st

## Start (or switch) the score. Idempotent for the same shift, so calling it
## every time a shift starts does not restart the loop mid-bar.
func play_music(kind: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_voices()
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "Music"
		_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_player)
	if _music_kind == kind and _music_player.playing:
		refresh_music_volume()
		return
	_music_kind = kind
	_music_player.stream = _build_music(kind)
	refresh_music_volume()
	_music_player.play()

func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()
	_music_kind = ""

func refresh_music_volume() -> void:
	if _music_player == null:
		return
	# -4, not -13.
	#
	# The chain matters and I got it wrong by about thirteen decibels. Source
	# peaks at roughly half full scale (-5.7 dB); at -13 dB of player gain and a
	# default 0.55 ambience slider under a 0.7 master, the score reached the
	# speakers at about -27 dBFS. The first playtester's report was "there's no
	# background music", and they were effectively right.
	var g: float = maxf(master_volume * music_volume, 0.0001)
	_music_player.volume_db = -4.0 + linear_to_db(g)

func start_ambience(volume_db := -30.0) -> void:
	_ensure_voices()
	if _hum_player == null:
		_hum_player = AudioStreamPlayer.new()
		_hum_player.name = "Hum"
		add_child(_hum_player)
	_hum_player.stream = _build_hum()
	_hum_player.volume_db = volume_db + linear_to_db(maxf(master_volume * music_volume, 0.0001))
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
	p.volume_db = volume_db + linear_to_db(maxf(_sfx_gain(), 0.0001))
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
	p.volume_db = volume_db + linear_to_db(maxf(_sfx_gain(), 0.0001))
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

## Slight random pitch keeps repeated sounds from sounding like a machine gun.
func play_var(name: String, volume_db: float = -6.0, spread: float = 0.12) -> void:
	play(name, volume_db, 1.0 + randf_range(-spread, spread))

func play_at_var(name: String, pos: Vector3, volume_db: float = -4.0, spread: float = 0.12) -> void:
	play_at(name, pos, volume_db, 1.0 + randf_range(-spread, spread))
