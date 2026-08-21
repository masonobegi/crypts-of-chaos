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
	# Voice blips. Not words — a pitched click per few letters, which is what
	# every game that does readable character dialogue without voice acting uses.
	"mumble":   {"w": "sine",  "f": 420.0, "d": 0.055,"dec": 46.0, "n": 0.10, "sw": -0.1,  "vib": 0.0},
	"mumble_lo":{"w": "saw",   "f": 250.0, "d": 0.060,"dec": 42.0, "n": 0.14, "sw": -0.12, "vib": 0.0},
	"mumble_hi":{"w": "sine",  "f": 640.0, "d": 0.048,"dec": 52.0, "n": 0.08, "sw": -0.08, "vib": 0.0},
	"page":     {"w": "noise", "f": 2200.0,"d": 0.10, "dec": 22.0, "n": 1.0,  "sw": 0.3,   "vib": 0.0},
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
	# The procedure bench. Asked for by name after the second playtest: "sound
	# effects for all the things I can do, gross if needed". These are the gross
	# ones. Every hand-procedure in the game makes at least one of them, and the
	# difference between a good manoeuvre and a bad one is audible before the
	# verdict text arrives.
	"squelch":   {"w": "noise", "f": 300.0, "d": 0.30, "dec": 9.0,  "n": 1.0,  "sw": -0.58, "vib": 4.0},
	"stitch":    {"w": "noise", "f": 2500.0,"d": 0.07, "dec": 30.0, "n": 0.9,  "sw": -0.45, "vib": 0.0},
	"crack":     {"w": "noise", "f": 950.0, "d": 0.09, "dec": 46.0, "n": 0.7,  "sw": -0.80, "vib": 0.0},
	"bone_grind":{"w": "saw",   "f": 145.0, "d": 0.45, "dec": 4.5,  "n": 0.55, "sw": -0.18, "vib": 28.0},
	"seat":      {"w": "sine",  "f": 190.0, "d": 0.20, "dec": 15.0, "n": 0.30, "sw": -0.45, "vib": 0.0},
	"inject":    {"w": "saw",   "f": 680.0, "d": 0.45, "dec": 3.2,  "n": 0.22, "sw": 0.30,  "vib": 13.0},
	"swab":      {"w": "noise", "f": 1600.0,"d": 0.20, "dec": 11.0, "n": 1.0,  "sw": -0.25, "vib": 0.0},
	"wet":       {"w": "noise", "f": 175.0, "d": 0.40, "dec": 7.0,  "n": 1.0,  "sw": -0.62, "vib": 2.0},
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
## The first version was a four-chord pad loop, sixteen seconds long, three
## triangle voices and a bass note. The playtest note was "this music sucks,
## it's so bland" and that was fair: it had no rhythm section, no phrasing and
## no second half, so by the third loop it had stopped being music and started
## being a tone.
##
## This is an arrangement. Eight bars, a rhythm section, a comping keyboard and
## a lead that phrases — lounge jazz for a waiting room, which is the joke: the
## hospital is completely normal and the music is the music of somewhere
## completely normal, played slightly too smoothly, while you decide whether to
## break a man's wrist for the bed-days.
##
## Everything is still maths and no assets. Notes are rendered as EVENTS into a
## float buffer rather than evaluated per sample across every voice — a
## twenty-second loop is 440,000 samples and forty voices, and doing that the
## naive way is seventeen million trig calls in GDScript, which takes long
## enough to stall the boot.
##
## Events wrap around the end of the buffer, so the tail of the last chord
## decays into the top of the first bar and the loop has no seam to hide.
const MUSIC_BARS := 8
const BEATS_PER_BAR := 4

## One entry per bar: `b` is the root the bar is built on in semitones from the
## key, `c` is the voicing above it.
##
## There is ONE piece of music and it plays the whole time — menu, ward, street,
## courtroom. Three shift moods meant the title screen's track was thrown away
## the moment a shift started, which is where "the menu music and the game music
## overlap" came from, and the one people liked was the menu's.
##
## And there is no bass line and no kick drum. The note was "there's a weird DUH
## DUH DUH going on in the background that I hate, but I like the melody" —
## between them the walking bass and the kick put something low on every single
## beat, which is the one thing a loop this long cannot get away with. What is
## left is what people were actually listening to: brushes, a comping electric
## piano off the beat, and a vibraphone that phrases.
const SCORE := {
	"key": 233.08, "bpm": 82.0, "swing": 0.20, "gain": 0.95,
	"drums": 0.5, "comp": 1.0, "lead": 1.0, "seed": 4471,
	"prog": [
		{"b": 0, "c": [3, 7, 10]}, {"b": -2, "c": [1, 5, 10]},
		{"b": -4, "c": [3, 7, 10]}, {"b": -5, "c": [0, 4, 7]},
		{"b": 0, "c": [3, 7, 10]}, {"b": 5, "c": [8, 12, 15]},
		{"b": -2, "c": [1, 5, 10]}, {"b": -5, "c": [0, 4, 9]},
	],
	"scale": [0, 2, 3, 5, 7, 8, 10],
}

var _music_player: AudioStreamPlayer = null
var _music_kind := ""

static func _semitone(root: float, n: float) -> float:
	return root * pow(2.0, n / 12.0)

## A sine table, because the score is twenty-three seconds of rendered audio —
## half a million samples — and `sin()` in GDScript is the whole cost of it.
##
## Measured before writing this: back when there were three moods the
## arrangement took 7.8 seconds to build them, which is a visible stall
## whenever it happens. Table lookup for the oscillators and an incremental
## multiplier for the envelopes (exp(-k*u) becomes env *= exp(-k/SR), which is
## exact, not an approximation) take it to a fraction of that. It is still not
## free — the one score costs about eight tenths of a second — which is why the
## menu waits until its first frame is on the screen before asking for it.
const SIN_BITS := 12
const SIN_SIZE := 1 << SIN_BITS
const SIN_MASK := SIN_SIZE - 1
static var _sin_tab: PackedFloat32Array = PackedFloat32Array()

static func _sin_table() -> PackedFloat32Array:
	if _sin_tab.size() == SIN_SIZE:
		return _sin_tab
	var tab := PackedFloat32Array()
	tab.resize(SIN_SIZE)
	for i in SIN_SIZE:
		tab[i] = sin(TAU * float(i) / float(SIN_SIZE))
	_sin_tab = tab
	return _sin_tab

## Add one note into the buffer, wrapping past the end.
##
## One function per timbre, and the choice made ONCE per note rather than once
## per sample. That is the whole optimisation: the first version had a
## `match voice:` on a String inside the inner loop, and comparing three strings
## four hundred thousand times a second cost more than every oscillator and
## envelope in the arrangement put together — eight seconds to build the score,
## which is a stall nobody would sit through.
##
## Oscillators read a sine table and envelopes are incremental multipliers
## (exp(-k*u) becomes env *= exp(-k/SR), which is exact rather than an
## approximation). Everything gets a three-millisecond attack, because a sine
## that starts at full amplitude is a click and forty of them a bar is a
## percussion section nobody asked for.
func _render(buf: PackedFloat32Array, voice: String, at: float, dur: float,
		f: float, gain: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	if n == 0 or gain <= 0.0:
		return
	var start := int(at * float(SR))
	var count := mini(int(dur * float(SR)), n)
	if count <= 0:
		return
	# Four voices, and four is the whole band. There were three more — a walking
	# bass, a kick and a held pad — and they were removed from the arrangement
	# when the DUH DUH DUH went and the night mood stopped existing. Their
	# renderers went with them rather than staying here as arms nothing can
	# reach: an unreachable oscillator is a trap for whoever next sits down to
	# tune one, because they can retune it all afternoon and hear nothing
	# change. That there is no kick drum in this score is a decision, and it is
	# enforced by _build_music not asking for one.
	match voice:
		"keys": _r_keys(buf, start, count, f, gain)
		"vibe": _r_vibe(buf, start, count, f, gain)
		"hat": _r_hat(buf, start, count, gain, rng)
		"rim": _r_rim(buf, start, count, gain, rng)

const ATTACK_S := 0.003

## Electric piano: a body, a twin a few cents off for the chorus every one of
## these has, and a bell partial that dies first.
func _r_keys(buf: PackedFloat32Array, start: int, count: int, f: float, gain: float) -> void:
	var tab := _sin_table()
	var n := buf.size()
	var sr := float(SR)
	var inc := f / sr * float(SIN_SIZE)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	var e1 := gain * 0.55
	var e2 := gain * 0.55 * 0.18
	var d1 := exp(-2.6 / sr)
	var d2 := exp(-9.0 / sr)
	var attack := int(ATTACK_S * sr)
	var i := start % n
	for j in count:
		var v: float = (tab[int(p1) & SIN_MASK] + tab[int(p2) & SIN_MASK] * 0.8) * e1
		v += tab[int(p3) & SIN_MASK] * e2
		if j < attack:
			v *= float(j) / float(attack)
		buf[i] += v
		p1 += inc
		p2 += inc * 1.004
		p3 += inc * 4.0
		e1 *= d1
		e2 *= d2
		i += 1
		if i >= n:
			i = 0

## Vibraphone, motor on.
func _r_vibe(buf: PackedFloat32Array, start: int, count: int, f: float, gain: float) -> void:
	var tab := _sin_table()
	var n := buf.size()
	var sr := float(SR)
	var inc := f / sr * float(SIN_SIZE)
	var minc := 5.4 / sr * float(SIN_SIZE)
	var p1 := 0.0
	var p2 := 0.0
	var e1 := gain
	var d1 := exp(-1.9 / sr)
	var attack := int(ATTACK_S * sr)
	var i := start % n
	for j in count:
		var v: float = tab[int(p1) & SIN_MASK] * e1 * (0.86 + 0.14 * tab[int(p2) & SIN_MASK])
		if j < attack:
			v *= float(j) / float(attack)
		buf[i] += v
		p1 += inc
		p2 += minc
		e1 *= d1
		i += 1
		if i >= n:
			i = 0

## Brushed: noise differenced against itself, which is a one-pole high pass and
## costs one subtraction.
func _r_hat(buf: PackedFloat32Array, start: int, count: int, gain: float,
		rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var e1 := gain * 0.5
	var d1 := exp(-34.0 / float(SR))
	var last := 0.0
	var i := start % n
	for j in count:
		var w := rng.randf_range(-1.0, 1.0)
		buf[i] += (w - last) * e1
		last = w
		e1 *= d1
		i += 1
		if i >= n:
			i = 0

func _r_rim(buf: PackedFloat32Array, start: int, count: int, gain: float,
		rng: RandomNumberGenerator) -> void:
	var tab := _sin_table()
	var n := buf.size()
	var inc := 340.0 / float(SR) * float(SIN_SIZE)
	var p1 := 0.0
	var e1 := gain
	var d1 := exp(-46.0 / float(SR))
	var i := start % n
	for j in count:
		buf[i] += (rng.randf_range(-1.0, 1.0) * 0.5 + tab[int(p1) & SIN_MASK]) * e1
		p1 += inc
		e1 *= d1
		i += 1
		if i >= n:
			i = 0

## `kind` is ignored. It is still in the signature because both call sites pass
## a shift name, and there being one piece of music is a fact about the score
## rather than about them.
func _build_music(_kind := "") -> AudioStreamWAV:
	var key := "__score"
	if _cache.has(key):
		return _cache[key]
	var mood: Dictionary = SCORE
	var root: float = float(mood["key"])
	var prog: Array = mood["prog"]
	var scale: Array = mood["scale"]
	var beat: float = 60.0 / float(mood["bpm"])
	var swing: float = float(mood["swing"])
	var total: float = beat * float(BEATS_PER_BAR * MUSIC_BARS)
	var n_samples := int(total * float(SR))
	var buf := PackedFloat32Array()
	buf.resize(n_samples)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(mood["seed"])

	var drums: float = float(mood["drums"])
	var comp: float = float(mood["comp"])
	var lead: float = float(mood["lead"])

	for bar in MUSIC_BARS:
		var here: Dictionary = prog[bar % prog.size()]
		var b0 := float(here["b"])
		var chord: Array = here["c"]
		var bar_t := float(bar) * beat * float(BEATS_PER_BAR)

		# No bass line. The chord below carries the bar's root as its bottom
		# note instead, which is enough to say where the harmony is without
		# putting something low on every beat.
		#
		# Comping, off the beat, because a chord on the beat is a hymn.
		if comp > 0.0:
			for h in [1.0 + swing, 2.5 + swing, 3.0]:
				var voicing: Array = [b0 - 12.0]
				voicing.append_array(chord)
				for n in voicing:
					_render(buf, "keys", bar_t + float(h) * beat, beat * 1.6,
						_semitone(root, float(n) - 12.0), comp * 0.20, rng)

		# The lead phrases: two bars on, two bars off, and it lands on a chord
		# tone. Sparse enough to sit under eighteen minutes of a shift.
		if lead > 0.0 and bar % 4 < 2:
			var figure := [0.0, 0.75 + swing * 0.5, 1.5, 2.5 + swing]
			for i in figure.size():
				if rng.randf() > 0.82:
					continue
				var pick: int = int(chord[i % chord.size()]) if i % 2 == 0 \
					else int(scale[rng.randi() % scale.size()])
				_render(buf, "vibe", bar_t + float(figure[i]) * beat, beat * 2.2,
					_semitone(root, float(pick) + 12.0), lead * 0.13, rng)

		# Kit, brushes only. No kick: that and the bass were the DUH DUH DUH.
		if drums > 0.0:
			for b in [1.0, 3.0]:
				_render(buf, "rim", bar_t + b * beat, 0.14, 0.0, drums * 0.26, rng)
			for i in 8:
				var pos: float = float(i) * 0.5
				if i % 2 == 1:
					pos += swing * 0.5
				_render(buf, "hat", bar_t + pos * beat, 0.10,
					0.0, drums * (0.13 if i % 2 == 0 else 0.08), rng)

	# Normalise to a known peak. The previous score was mixed by eye and landed
	# thirteen decibels quieter than anybody could hear; measuring it is one
	# pass over a buffer that already exists.
	var peak := 0.0
	for i in n_samples:
		peak = maxf(peak, absf(buf[i]))
	var norm: float = (0.74 * float(mood["gain"])) / maxf(peak, 0.0001)

	var data := PackedByteArray()
	data.resize(n_samples * 2)
	for i in n_samples:
		var v := int(clampf(buf[i] * norm * 32767.0, -32768.0, 32767.0))
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

## Start the score. There is only one, so this is idempotent from anywhere:
## whoever gets there first starts the loop and nobody else interrupts it
## mid-bar.
func play_music(_kind := "") -> void:
	if DisplayServer.get_name() == "headless":
		return
	# One score, so this is a no-op after the first call from anywhere. That is
	# the fix for the menu's track being replaced the moment a shift started.
	var kind := "score"
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
	# -4, not -13.
	#
	# The chain matters and I got it wrong by about thirteen decibels. Source
	# peaks at roughly half full scale (-5.7 dB); at -13 dB of player gain and a
	# default 0.55 ambience slider under a 0.7 master, the score reached the
	# speakers at about -27 dBFS. The first playtester's report was "there's no
	# background music", and they were effectively right.
	var g: float = maxf(master_volume * music_volume, 0.0001)
	if _music_player != null:
		_music_player.volume_db = -4.0 + linear_to_db(g)
	# The room tone is on the same two sliders and has to be re-levelled here
	# too. start_ambience() runs exactly once, at ward load, and baked the slider
	# values into volume_db at that moment — so a player who dragged "Ambience"
	# (or Master) to zero silenced the score and then listened to a 50/74 Hz hum
	# at its original level for the rest of the run, which is the one sound the
	# slider is actually named after. Settings only knows to call this function,
	# so this is where the hum gets told.
	if _hum_player != null:
		_hum_player.volume_db = _hum_base_db + linear_to_db(g)

## The hum's level BEFORE the sliders, remembered so refresh_music_volume() can
## re-apply them to it without start_ambience() being called again.
var _hum_base_db := -30.0

func start_ambience(volume_db := -30.0) -> void:
	_ensure_voices()
	if _hum_player == null:
		_hum_player = AudioStreamPlayer.new()
		_hum_player.name = "Hum"
		add_child(_hum_player)
	_hum_player.stream = _build_hum()
	_hum_base_db = volume_db
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
## One blip of somebody talking.
##
## `voice` is any stable string — an npc_id — so the same character always
## sounds like themselves. Three base timbres and a pitch offset off the hash is
## enough that a ward full of people is a ward full of different voices.
func mumble(voice: String, volume_db := -20.0) -> void:
	var h := absi(hash(voice))
	var bank: String = ["mumble", "mumble_lo", "mumble_hi"][h % 3]
	# A fifth of an octave either side, plus a small per-syllable wobble so a
	# line is not a monotone.
	var base := 0.82 + float(h % 40) * 0.011
	play(bank, volume_db, base + randf_range(-0.06, 0.06))

func play_var(name: String, volume_db: float = -6.0, spread: float = 0.12) -> void:
	play(name, volume_db, 1.0 + randf_range(-spread, spread))

func play_at_var(name: String, pos: Vector3, volume_db: float = -4.0, spread: float = 0.12) -> void:
	play_at(name, pos, volume_db, 1.0 + randf_range(-spread, spread))
