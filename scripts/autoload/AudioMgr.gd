extends Node
## Procedural audio. Every sound in the game is synthesised at runtime into an
## AudioStreamWAV, so the project ships with zero audio assets and new sounds are
## a few lines of maths rather than a trip to a sample library.

## TWO SAMPLE RATES, AND THE SPLIT IS THE POINT.
##
## `SR` is the rate the two long beds run at — the room tone and the score,
## whose highest partial is the electric piano's fourth-harmonic bell at about
## 4 kHz. 22050 is plenty for those and they are by far the largest buffers in
## the game, so their cost is what it buys.
##
## The one-shots are the opposite case and were paying the same tax: the whole
## table is under eight seconds of audio, and four recipes (`paper` 3000,
## `glass` 2600, `page` 2200, `tick` 1800) ask for content an 11 kHz ceiling
## cannot give an octave of room above. Once those became real filtered noise
## rather than the same hiss as everything else, a high-pass at 3 kHz into an
## 11 kHz ceiling had one octave to work in — which is why every "bright" sound
## in this game used to be the same kind of dull. At 44100 the whole table
## costs about 660 KB more and gets three octaves.
##
## Anything reading a duration off a byte count must use the STREAM's own
## `mix_rate` rather than this constant: `AudioStreamWAV` carries its own rate
## and the two coexist in one mixer with no conversion anywhere.
const SR := 22050
const SR_SFX := 44100
const MAX_VOICES := 24

## Voices for speech, kept separate from the shared pool because a bus
## assignment has to be permanent: writing `p.bus` per play on the shared pool
## would leave whichever player spoke last pointing somewhere else, and the
## smoke run rightly asserts that every voice in the shared 3D pool is in the
## room. Six is more people than ever speak at once on a five-bed ward.
const MAX_VOICE_VOICES := 6

var _cache: Dictionary = {}          ## name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next3d := 0
## Speech, on its own pair of pools so it can sit on its own bus — which is
## what lets the score get out of its way. See `BUS_VOICE`.
var _voices: Array[AudioStreamPlayer] = []
var _voices3d: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _next_voice3d := 0
## Three knobs, so the settings screen has something to turn. `master_volume`
## was the only one and nothing exposed it.
##
## THE DEFAULTS BELONG TO `Settings` AND THIS IS A CHECKED COPY OF THEM.
## `Settings._ready()` overwrites all three on every path into the tree, so
## what is written here is only read in the window before that happens — which
## is why `music_volume` sat at 0.55 while `Settings.DEFAULTS` said 0.75 and
## nothing went wrong, and why the gain-staging note in
## `refresh_music_volume()` traced the chain through the dead number. Two
## copies of a tuned value, with the comment siding with the wrong one: gotcha
## 48, quietly. They stay literals, because an autoload cannot safely read
## another autoload's constants while its own members are initialising — so
## the smoke run asserts this dictionary equals `Settings.DEFAULTS` instead.
const VOLUME_FALLBACK := {"master_volume": 0.7, "sfx_volume": 1.0,
	"music_volume": 0.75, "ambience_volume": 0.75}
var master_volume: float = VOLUME_FALLBACK["master_volume"]
var sfx_volume: float = VOLUME_FALLBACK["sfx_volume"]
var music_volume: float = VOLUME_FALLBACK["music_volume"]
var ambience_volume: float = VOLUME_FALLBACK["ambience_volume"]

## Effective gain for a one-shot effect, in linear terms.
func _sfx_gain() -> float:
	return clampf(master_volume * sfx_volume, 0.0, 1.0)

## ...AND FOR THE TWO CONTINUOUS BEDS, which are neither effects nor music.
##
## The line is the useful part and it is not "positional or not": it is whether
## the sound is an EVENT. A cough down the corridor, a trolley, a door two
## rooms away are things that just happened and belong with every other thing
## that just happened, on Effects. The room tone and the world beyond the
## glazing are not happening — they are the level the building sits at, and the
## slider a person reaches for to quieten a hospital is the one that should
## move them. See `Settings.DEFAULTS["ambience_volume"]`.
func _ambience_gain() -> float:
	return clampf(master_volume * ambience_volume, 0.0, 1.0)

## name -> waveform, frequency, duration, decay, noise mix, sweep, vibrato,
## and — new, and the reason eleven of these stopped being the same sound —
## which response of the state-variable filter the recipe is played through.
##
## `filt` defaults to "off", so the tonal recipes are untouched: they are
## oscillators whose `f` is a pitch, and a filter on top of a sine is a volume
## control. It is the noise recipes that need it, because for them `f` had no
## reader at all — see the note above `_build`.
const RECIPES := {
	"beep":      {"w": "sine",  "f": 880.0, "d": 0.08, "dec": 14.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	"beep_low":  {"w": "sine",  "f": 320.0, "d": 0.12, "dec": 10.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	"ding":      {"w": "sine",  "f": 1320.0,"d": 0.5,  "dec": 6.0,  "n": 0.0,  "sw": 0.0,   "vib": 3.0},
	"error":     {"w": "square","f": 180.0, "d": 0.22, "dec": 9.0,  "n": 0.02, "sw": -0.35, "vib": 0.0},
	"money":     {"w": "sine",  "f": 1046.0,"d": 0.35, "dec": 7.0,  "n": 0.0,  "sw": 0.55,  "vib": 0.0},
	"thud":      {"w": "sine",  "f": 90.0,  "d": 0.18, "dec": 22.0, "n": 0.25, "sw": -0.5,  "vib": 0.0},
	# A cupboard's worth of crockery: a wide band around 400 Hz, falling.
	"clatter":   {"w": "noise", "f": 400.0, "d": 0.35, "dec": 12.0, "n": 1.0,  "sw": -0.2,  "vib": 0.0, "filt": "bp"},
	# Glass is all top and no body — the low end is what makes noise sound like
	# a cardboard box, and a high-pass is the only thing that removes it.
	"glass":     {"w": "noise", "f": 2600.0,"d": 0.4,  "dec": 11.0, "n": 0.8,  "sw": -0.1,  "vib": 0.0, "filt": "hp"},
	"squeak":    {"w": "saw",   "f": 700.0, "d": 0.16, "dec": 10.0, "n": 0.06, "sw": 0.4,   "vib": 22.0},
	# A shoe on vinyl: a band low enough to have weight, sweeping down as the
	# heel takes the load. The most-played sound in the game by a distance.
	"step":      {"w": "noise", "f": 200.0, "d": 0.07, "dec": 30.0, "n": 1.0,  "sw": -0.3,  "vib": 0.0, "filt": "bp"},
	"paper":     {"w": "noise", "f": 3000.0,"d": 0.14, "dec": 18.0, "n": 1.0,  "sw": 0.2,   "vib": 0.0, "filt": "hp"},
	"alarm":     {"w": "square","f": 660.0, "d": 0.6,  "dec": 1.5,  "n": 0.0,  "sw": 0.0,   "vib": 9.0},
	"gasp":      {"w": "noise", "f": 900.0, "d": 0.3,  "dec": 7.0,  "n": 1.0,  "sw": 0.6,   "vib": 0.0, "filt": "bp"},
	"grunt":     {"w": "saw",   "f": 130.0, "d": 0.22, "dec": 11.0, "n": 0.3,  "sw": -0.3,  "vib": 4.0},
	"whoosh":    {"w": "noise", "f": 500.0, "d": 0.3,  "dec": 8.0,  "n": 1.0,  "sw": 0.8,   "vib": 0.0, "filt": "bp"},
	"suspicion": {"w": "sine",  "f": 210.0, "d": 0.8,  "dec": 3.0,  "n": 0.02, "sw": -0.2,  "vib": 2.0},
	# A rubber stamp is a thump with a paper edge on it, so this one goes the
	# other way: everything above 150 Hz taken off, sweeping lower still.
	"stamp":     {"w": "noise", "f": 150.0, "d": 0.12, "dec": 26.0, "n": 0.9,  "sw": -0.4,  "vib": 0.0, "filt": "lp"},
	"heartbeat": {"w": "sine",  "f": 55.0,  "d": 0.25, "dec": 12.0, "n": 0.0,  "sw": -0.2,  "vib": 0.0},
	"pickup":    {"w": "sine",  "f": 520.0, "d": 0.09, "dec": 16.0, "n": 0.05, "sw": 0.35,  "vib": 0.0},
	"drop":      {"w": "sine",  "f": 300.0, "d": 0.1,  "dec": 18.0, "n": 0.15, "sw": -0.4,  "vib": 0.0},
	"tick":      {"w": "noise", "f": 1800.0,"d": 0.04, "dec": 40.0, "n": 1.0,  "sw": 0.0,   "vib": 0.0, "filt": "hp"},
	# THE CLOCK, WHICH IS THE ONLY THING IN THIS GAME THE PLAYER ACTUALLY
	# SPENDS. Every verb costs minutes and `advance_to` skips them instantly, so
	# the one resource the design is built on made no sound at all. A short
	# filtered click, played once per five minutes spent — see
	# `AmbienceSystem._clock_pass`.
	"clock":     {"w": "noise", "f": 2400.0,"d": 0.035,"dec": 70.0, "n": 1.0,  "sw": -0.55, "vib": 0.0, "filt": "bp"},
	# Voice blips. Not words — a pitched click per few letters, which is what
	# every game that does readable character dialogue without voice acting uses.
	"mumble":   {"w": "sine",  "f": 420.0, "d": 0.055,"dec": 46.0, "n": 0.10, "sw": -0.1,  "vib": 0.0},
	"mumble_lo":{"w": "saw",   "f": 250.0, "d": 0.060,"dec": 42.0, "n": 0.14, "sw": -0.12, "vib": 0.0},
	"mumble_hi":{"w": "sine",  "f": 640.0, "d": 0.048,"dec": 52.0, "n": 0.08, "sw": -0.08, "vib": 0.0},
	"page":     {"w": "noise", "f": 2200.0,"d": 0.10, "dec": 22.0, "n": 1.0,  "sw": 0.3,   "vib": 0.0, "filt": "hp"},
	# A cough is a burst of air with a throat around it: a band that starts
	# where a voice does and falls away.
	"cough":     {"w": "noise", "f": 420.0, "d": 0.22, "dec": 13.0, "n": 1.0,  "sw": -0.5,  "vib": 0.0, "filt": "bp"},
	"monitor":   {"w": "sine",  "f": 1180.0,"d": 0.09, "dec": 16.0, "n": 0.0,  "sw": 0.0,   "vib": 0.0},
	# Castors on vinyl. The 7 Hz vibrato was in this recipe from the start and
	# was read by nothing; on the filter corner it is the rumble of a wheel.
	"trolley":   {"w": "noise", "f": 260.0, "d": 0.5,  "dec": 5.0,  "n": 1.0,  "sw": 0.1,   "vib": 7.0, "filt": "bp"},
	"pipe":      {"w": "sine",  "f": 95.0,  "d": 0.8,  "dec": 3.5,  "n": 0.12, "sw": -0.15, "vib": 1.5},
	# ---------------------------------------------------------------------
	# THE FIVE MOMENTS THE GAME IS ACTUALLY ABOUT, WHICH SHARED THREE UI SOUNDS.
	#
	# `examine` costs a quarter of an hour, is the only verb in the game that
	# cannot be wrong, and was a 60 ms `mumble_lo` blip. Adeyemi's four fixed
	# rounds are the rhythm of the day and the one pattern a player has to learn
	# by ear, and they arrived on the same `paper` as every tutorial line. The
	# returning test result — the only delayed payoff in the whole loop, ten
	# minutes to order and seventy-five to come back — was the `beep` you heard
	# when you ordered it, a third higher. And eight o'clock, the arrival of the
	# man the entire game is about, was a 220 ms square wave it shared with a
	# failed button press.
	#
	# `round` and `lab` are single notes ON PURPOSE: the FIGURE is built at the
	# call site (`HUD._chime`) out of two or three plays at fixed intervals,
	# because a two-note chime cannot be written as one oscillator and a decay,
	# and because an interval is what makes a sound learnable rather than
	# merely different from the last one.
	"curtain":   {"w": "noise", "f": 900.0, "d": 0.55, "dec": 4.2,  "n": 1.0,  "sw": -0.66, "vib": 0.0, "filt": "bp"},
	"round":     {"w": "sine",  "f": 720.0, "d": 0.34, "dec": 9.0,  "n": 0.02, "sw": -0.10, "vib": 0.0},
	"lab":       {"w": "sine",  "f": 990.0, "d": 0.45, "dec": 6.5,  "n": 0.0,  "sw": 0.0,   "vib": 2.5},
	# THE ONLY SOUND IN THE GAME THAT SWELLS RATHER THAN STRIKES, which is the
	# whole reason `atk` exists — see `_build`. Everything else in this table is
	# a thing that has happened; this one is a thing that is arriving, and it
	# has to be audibly on its way before it is here or it is just a low beep.
	# 150 Hz, not 116, and the reason is the room tone's reason: at 116 with the
	# low-pass corner tied to the fundamental it measured 80/19/0 across the
	# three bands, which is `pipe` with a longer front on it and is not there
	# at all on a laptop. At 150 it is 72/28/0 — still unmistakably the bottom
	# of the mix, and now with something in it a television can reproduce.
	"vinnie":    {"w": "saw",   "f": 150.0, "d": 1.7,  "dec": 0.70, "n": 0.10, "sw": -0.22, "vib": 0.55, "filt": "lp", "atk": 0.55},
	# ---------------------------------------------------------------------
	# ONE BUZZING SAW WAS EVERY DOOR IN A BUILDING MADE OF CORRIDORS, and one
	# push played it three times: `push()`, the `is_open()` threshold crossing a
	# few frames later, and the crossing back on the way shut, all inside two
	# seconds with a ten per cent pitch spread. `door` was a 350 ms saw at
	# 180 Hz with a 3 Hz vibrato on it, which is a kazoo, and it measured
	# 43/46/11 across the three bands — a drone with no transient in it at all.
	#
	# A door is three separate events and they do not sound alike: the leaf
	# moving is hinge and air, the latch is a bright tick collapsing into a
	# thump, and somebody else's door swinging past you down the corridor is a
	# short bump. See `SwingDoor`, which plays one of each at the moment it
	# belongs to instead of the same buzz at all three.
	"door_swing": {"w": "noise", "f": 320.0, "d": 0.42, "dec": 5.5,  "n": 1.0, "sw": -0.50, "vib": 0.0, "filt": "bp"},
	"door_latch": {"w": "noise", "f": 1400.0,"d": 0.22, "dec": 13.0, "n": 1.0, "sw": -0.88, "vib": 0.0, "filt": "lp"},
	"door_bump":  {"w": "noise", "f": 620.0, "d": 0.09, "dec": 32.0, "n": 1.0, "sw": -0.40, "vib": 0.0, "filt": "bp"},
	# A FOURTH VOICE BANK, AND IT IS NOT A PERSON. The tannoy speaks through
	# `Typewriter` like everybody else now, and a ceiling speaker that blips in
	# the same three timbres as the man in bed two is a person hiding in the
	# ceiling. A square wave with grit on it and no low end is what a small
	# paging horn sounds like. Picked by `mumble()` off `PA_VOICE` and never by
	# hash, so it can never be dealt to a character.
	"mumble_pa": {"w": "square","f": 430.0, "d": 0.05, "dec": 40.0, "n": 0.22, "sw": -0.15, "vib": 0.0},
	# ---------------------------------------------------------------------
	# THIRTEEN RECIPES USED TO SIT HERE AND NOTHING PLAYED ANY OF THEM: a
	# procedure bench (squelch, stitch, crack, bone_grind, inject, swab, wet),
	# three that came in with a shift loop (snap, theatre, pills), a chair, and
	# two machine states. Every one of them belonged to a system that has since
	# been cut, and a recipe with no caller is the audio version of a constant
	# nothing reads — it looks like the game has a feature and it does not.
	#
	# Two of the survivors were rescued rather than deleted: `alarm`, `squeak`
	# and `gasp` went into the sparse ambience, and `heartbeat` beats in the
	# last forty minutes of the shift. Every recipe below is played by
	# something, and there is a check in the smoke run that keeps it that way.
}

## The continuous bed: a long, low, quietly unpleasant loop. Built separately
## from the one-shots because it needs seamless looping rather than a decay.
##
## ELEVEN SECONDS, NOT THREE. The score was taken from a sixteen-second loop to
## ninety-four for exactly one reason — "the loop point is now four times
## further apart than the longest thing anybody does in one place" — and the
## room tone, which plays for the whole twelve hours underneath it, was left at
## three. Three seconds is short enough for the ear to lock onto and then
## never let go of, and the noise floor in it is seeded, so it repeated
## identically fourteen thousand times a shift.
##
## Both partials still fit a WHOLE NUMBER OF CYCLES in the buffer, which is
## what makes the loop seamless with no cross-fade: 50 Hz gives 550 cycles in
## eleven seconds and 74 Hz gives 814. That is not a free choice — pick a
## length that leaves either of them mid-cycle and the loop clicks, once every
## eleven seconds, forever. `HUM_PARTIALS` is what the smoke run checks it
## against.
## ...AND IT HAS TO HAVE SOMETHING ABOVE A HUNDRED HERTZ IN IT.
##
## Gotcha 59 fixed the LENGTH of this loop and nobody ever looked at its
## spectrum. Two sines at 50 and 74 Hz plus `lerpf(lp, noise, 0.02)` — a
## one-pole at about 71 Hz — put 94% of the energy below 200 Hz, measured off
## the built buffer. Laptop and TV speakers roll off hard below 200 Hz, so on
## the hardware most of Steam plays on the game's only continuous ambience was
## not there at all, and the slider named after it turned down nothing anybody
## could hear.
##
## A hospital room tone is three things and this now has all three: a plant
## fundamental (50/74), fluorescent ballast around 100-120 Hz, and — the one
## that carries on a small speaker — HVAC hiss across a couple of hundred hertz
## to a few kilohertz.
##
## `HUM_PARTIALS` are the tones and every one of them still has to fit a WHOLE
## number of cycles in the buffer or the loop clicks once every eleven seconds,
## under everything, forever: 50 Hz gives 550, 74 gives 814, 100 gives 1100,
## 120 gives 1320, 220 gives 2420. `HUM_LEVELS` is their balance and is
## parallel to it rather than paired into it, because the smoke run reads
## `HUM_PARTIALS` as a list of frequencies and that check is worth more than
## the tidiness.
const HUM_SECONDS := 11.0
const HUM_PARTIALS := [50.0, 74.0, 100.0, 120.0, 220.0]
const HUM_LEVELS := [0.32, 0.19, 0.17, 0.12, 0.08]

## The hiss band, and the reason it can be made with a filter after all.
##
## The obvious objection to filtering noise for a loop is the right one:
## filtered noise does not close, because the filter's STATE at the top of the
## buffer is zero and its state at the bottom is whatever the last few hundred
## samples left there, and the difference is a click — the exact fault gotcha
## 59 records, in the one sound nothing else in this repo can hear.
##
## What closes it is a warm-up. The noise sequence is seeded, so the samples
## before position 0 on the second lap are known: they are the last samples of
## the buffer. Run the filters over those before starting, and the state
## entering sample 0 is by construction the state leaving sample N-1. A
## one-pole forgets its input within a few dozen samples, so 4096 is four
## orders of magnitude more warm-up than the argument needs; the smoke run
## measures the seam in the finished buffer rather than trusting any of this.
## The two slow swells, in CYCLES PER LOOP rather than in hertz, because a
## modulation that does not fit a whole number of times clicks at the loop point
## exactly like a partial does — and it is a way to break the seam that
## `HUM_PARTIALS` cannot see. One breath from the plant, two from the air
## handling, deliberately out of phase so the two never swell together and give
## the bed a period the ear can find.
const HUM_BREATH_CYCLES := 1.0
const HUM_DRAUGHT_CYCLES := 2.0
const HUM_HISS_HP := 180.0
const HUM_HISS_LP := 3200.0
const HUM_HISS_LEVEL := 1.15
const HUM_WARMUP := 4096
## Peak of the finished bed, before `_hum_base_db` and the sliders. Chosen
## against the score rather than guessed: see `start_ambience`.
const HUM_PEAK := 0.20

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

## Every voice pool there is, so that the three teardown passes below cannot be
## written for some of them. The speech pools were added later and this is
## exactly the shape of thing that gets missed when they are: a stopped-but-not
## -freed player holds its playback server-side and is reported as leaked, and
## the report names a count and not a pool.
func _all_pools() -> Array:
	return [_players, _players3d, _voices, _voices3d]

func _exit_tree() -> void:
	stop_music()
	if _hum_player != null and is_instance_valid(_hum_player):
		_hum_player.stop()
	for pool in _all_pools():
		for p in pool:
			if is_instance_valid(p):
				p.stop()
	# Stopping is not enough: the player still HOLDS its stream, and the stream
	# holds a live playback. Both have to be let go, and the synthesis cache
	# with them, or the two survive the tree and are reported as leaked.
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.stream = null
	if _hum_player != null and is_instance_valid(_hum_player):
		_hum_player.stream = null
	for pool in _all_pools():
		for p in pool:
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
	for pool in _all_pools():
		for p in pool:
			if is_instance_valid(p):
				p.free()
		pool.clear()
	_cache.clear()

## Built lazily rather than only in _ready(): headless tooling drives the game
## from a SceneTree script, whose _initialize() runs BEFORE any node's _ready(),
## so anything that plays a sound during setup would otherwise index an empty
## voice pool.
func _ensure_voices() -> void:
	if not _players.is_empty():
		return
	_ensure_buses()
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 30.0
		p.unit_size = 4.0
		p.bus = BUS_WORLD
		add_child(p)
		_players3d.append(p)
	for i in MAX_VOICE_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 30.0
		p.unit_size = 4.0
		p.bus = BUS_VOICE
		add_child(p)
		_voices3d.append(p)
	# Non-positional speech is rarer — the tannoy, and a blip under a subtitle
	# whose speaker is off screen — but it has to land on the same bus or the
	# score stops getting out of the way exactly when the line matters most.
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_VOICE
		add_child(p)
		_voices.append(p)

## THE ROOM. Everything positional goes through it and nothing else does.
##
## Every sound in this game was DRY — a footstep on a vinyl floor, a door in a
## corridor and a monitor forty feet away all arrived with no room around them,
## which is the single loudest "this was made in a week" tell an interior game
## can have. A hospital is hard floors, painted plaster and long straight runs;
## it is one of the more reverberant places a person is ever in.
##
## Only the positional pools are routed here — the 3D voices directly, and the
## speech pool through `Voice`, which sends here rather than to Master so that
## a line spoken across the ward still has the ward around it. The music and
## the UI clicks stay dry on purpose: a button that echoes is a button in a
## cave, and putting a room around a score that is meant to be coming from
## nowhere makes it sound like it is coming from the next ward. That is still
## true now the score has a bus of its own; what is on that bus is a
## compressor and a filter, and neither of them is a room.
##
## Wet is deliberately low. The point is not that you notice a reverb; it is
## that you stop noticing its absence. Above about 0.3 the ward turns into a
## swimming pool and every line of dialogue smears.

## FOUR BUSES, AND EACH ONE EXISTS BECAUSE SOMETHING WAS WRONG WITHOUT IT.
##
##   Master  ← a limiter, because nothing was catching the sum. Five monitors,
##            a door, a footstep, a stamp and a score normalised to 0.74 peak
##            can add past full scale, and clipping in a mix nobody is metering
##            is the one fault a player hears as "cheap" without knowing why.
##   World   ← the room (above). Everything positional.
##   Voice   ← speech, and it SENDS TO WORLD rather than to Master, so a line
##            spoken across the ward still has the ward around it. Its only
##            purpose beyond that is to be a key: a bus the compressor on
##            Music can listen to.
##   Music   ← the score, with that compressor on it, plus the low-pass the
##            evening closes (see `duck_music`). The room tone deliberately
##            does NOT come here: it is the thing the evening is supposed to
##            let through, so ducking and darkening it with the music would
##            undo the one dynamic the shift has.
const BUS_WORLD := "World"
const BUS_VOICE := "Voice"
const BUS_MUSIC := "Music"

## THE THREE TIMBRES A PERSON CAN HAVE, as a list rather than as a literal
## inside `mumble()`.
##
## It was a literal, and the smoke run's "every recipe is played by something"
## scan carried a hard-coded copy of the same three names as a permanent
## exemption — because these are chosen by hash rather than written at a call
## site, so the source scan cannot see them. A hard-coded exemption is a list
## that stops matching the code the moment either one moves; the check reads
## THIS now, so a fourth bank is covered the day it is added and a bank dropped
## from here without being deleted from `RECIPES` goes red.
const MUMBLE_BANKS := ["mumble", "mumble_lo", "mumble_hi"]

## The tannoy is not a person and must never be dealt a person's bank. Any
## caller that speaks as the building passes this as the voice id — see
## `PASystem.announce` — and it is a string no `npc_id` can collide with.
const PA_VOICE := "@pa"
const PA_BANK := "mumble_pa"

## Which recipes are somebody talking. `grunt` is what `NPCBody.say` plays under
## every line in the game, so this is not hypothetical routing: it is the key
## the sidechain fires on, several times a minute, all shift — and now that
## `Typewriter` is actually wired to a subtitle, so is every blip in this list.
const VOICE_SOUNDS := {"grunt": true, "mumble": true, "mumble_lo": true,
	"mumble_hi": true, "mumble_pa": true}

func _ensure_buses() -> void:
	_ensure_master_limiter()
	_ensure_world_bus()
	_ensure_send_bus(BUS_VOICE, BUS_WORLD)
	_ensure_music_bus()

## A bus that exists, sends where it is told, and is left alone afterwards.
func _ensure_send_bus(bus_name: String, send_to: String) -> int:
	var at := AudioServer.get_bus_index(bus_name)
	if at != -1:
		return at
	at = AudioServer.bus_count
	AudioServer.add_bus(at)
	AudioServer.set_bus_name(at, bus_name)
	AudioServer.set_bus_send(at, send_to)
	return at

## THE ONLY THING BETWEEN THE MIX AND FULL SCALE.
##
## Not a loudness stage and not a colour: the ceiling is half a decibel under
## and the soft clip is what a limiter is for. It is here because a game that
## synthesises everything has no mastering step at all — every level in this
## file was chosen against one sound at a time, and the moment five of them
## agree there is nothing holding the sum.
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	for fx_i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, fx_i) is AudioEffectLimiter:
			return
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	lim.threshold_db = -1.5
	lim.soft_clip_db = 2.0
	AudioServer.add_bus_effect(master, lim)

## THE SCORE GETS OUT OF THE WAY OF A VOICE, AND CANNOT FORGET TO COME BACK.
##
## This is not the duck gotcha 58 is about and it does not replace it — that
## one is the deliberate nine-decibel step-back over the last forty minutes of
## a shift, keyed on the CLOCK, and it still lives in `duck_music` with its
## release path. This is the small automatic one that every mix has: three or
## four decibels off the music for as long as somebody is speaking, released by
## the compressor itself, which is a machine that structurally cannot be
## applied-and-never-released.
func _ensure_music_bus() -> void:
	var at := _ensure_send_bus(BUS_MUSIC, "Master")
	if AudioServer.get_bus_effect_count(at) > 0:
		return
	var comp := AudioEffectCompressor.new()
	comp.threshold = -22.0
	comp.ratio = 4.0
	comp.attack_us = 20000.0
	comp.release_ms = 250.0
	comp.sidechain = BUS_VOICE
	AudioServer.add_bus_effect(at, comp)
	# ...AND A SECOND STATE FOR A SCORE THAT ONLY HAD ONE.
	#
	# The whole dynamic range of this game's music was a blanket nine decibels
	# down. Nine decibels down is the same music, quieter — the ear reads it as
	# somebody nudging the volume knob, not as the evening arriving. Closing a
	# low-pass over the same forty minutes is what actually moves it: the score
	# goes into the next room and stays there, and the ward, the monitors and
	# the pulse are what is left in this one. It costs no material, which is
	# the point — there is one piece of music and there is going to be one
	# piece of music.
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = MUSIC_LP_OPEN
	AudioServer.add_bus_effect(at, lpf)

func _ensure_world_bus() -> void:
	if AudioServer.get_bus_index(BUS_WORLD) != -1:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, BUS_WORLD)
	AudioServer.set_bus_send(i, "Master")
	var rev := AudioEffectReverb.new()
	# A corridor, not a cathedral: ~1.1s of tail, damped by the plaster, with a
	# short pre-delay so the direct sound still arrives first and the source
	# still has a direction. `hipass` keeps the low end out of the tail, which
	# is what stops a footstep booming.
	rev.room_size = 0.62
	rev.damping = 0.46
	rev.predelay_msec = 18.0
	rev.predelay_feedback = 0.28
	rev.spread = 0.85
	rev.hipass = 0.18
	rev.dry = 1.0
	rev.wet = 0.20
	AudioServer.add_bus_effect(i, rev)

# ------------------------------------------------------------------ synthesis
## THE FILTER THE TABLE HAS ALWAYS DESCRIBED AND NEVER HAD.
##
## `f`, `sw` and `vib` were computed into `phase` and then thrown away for
## every `w: "noise"` recipe, because the noise branch reads `randf_range` and
## nothing else. Eleven of the thirty recipes are noise, so a footstep, a page
## turn, a cough, a pane of breaking glass, a rubber stamp and a trolley
## differed only in how long they lasted and how fast they decayed — measured
## over the built buffers, all eleven sat inside a three-point spread of the
## same three-band split (4-6% below 200 Hz, 30-33% to 2 kHz, 63-67% above).
## The comment over the inner loop said "band-ish shaping for noise so it isn't
## pure hiss" and described code that did not exist: pure hiss is exactly what
## it was. That is gotcha 15 living inside the sound table — 33 tuned numbers
## with no reader, and the one place a player could hear the difference.
##
## Q is deliberately low. At Q 4 a band-passed noise burst rings and every
## sound becomes a bell; at about 1.2 it is a shape rather than a pitch, which
## is the difference between "a filtered noise" and "a footstep".
const FILTER_Q := 0.85
const RELEASE_S := 0.006
const PEAK_TARGET := 22000.0

## FOUR OF EVERY NOISE, BECAUSE PITCH ALONE DOES NOT HIDE A REPEAT.
##
## The synthesis RNG is seeded from the sound's NAME, so a recipe was built
## once and every play after that was bit-for-bit the same waveform;
## `play_var` only resamples it, which shifts the pitch of an identical crunch.
## The ear locks onto a repeated noise transient far faster than onto a
## repeated tone, and `step` fires from the player continuously and from every
## NPC within twenty metres — it is by a wide margin the most repeated sound in
## the game. Four variants of `step` is twelve kilobytes.
##
## Variant 0 is the canonical build and is what `_build(name)` returns, so the
## smoke run's recipe scan and everything else that asks for a sound by name
## alone gets the same stream it always did.
const NOISE_VARIANTS := 4

func _build(name: String, variant := 0) -> AudioStreamWAV:
	var key: String = name if variant == 0 else "%s#%d" % [name, variant]
	if _cache.has(key):
		return _cache[key]
	# A NAME THAT IS NOT A RECIPE IS A TYPO, AND IT SAYS SO.
	#
	# This fell back to "beep" in silence, so a mistyped sound name did not
	# fail — it played the wrong sound, forever, and the only way to notice was
	# to know what that action was supposed to sound like. Same silent-substitute
	# shape as `GameState.adjust_rep()` throwing and taking its function with it:
	# the failure is invisible precisely because something plausible happens.
	#
	# Still falls back, because a missing sound must never take a verb down with
	# it. Once per name, because `_cache` catches the second call.
	if not RECIPES.has(name):
		push_error("AudioMgr: no recipe named '%s' — playing beep instead" % name)
	var r: Dictionary = RECIPES.get(name, RECIPES["beep"])
	var dur: float = float(r["d"])
	var n_samples := int(dur * SR_SFX)
	var rng := RandomNumberGenerator.new()
	# The seed is the NAME, so a recipe is one fixed waveform — plus the
	# variant, which is what stops it being the SAME fixed waveform every time.
	# See `play_var`.
	rng.seed = hash(name) + variant * 7919
	var wave := String(r["w"])
	var filt := String(r.get("filt", "off"))
	var base_f: float = float(r["f"])
	var nm: float = float(r["n"])
	var dec: float = float(r["dec"])
	var sweep: float = float(r["sw"])
	var vibrato: float = float(r["vib"])
	# HOW LONG IT TAKES TO ARRIVE. Four milliseconds for everything was right
	# for as long as every sound in the table was a thing that had already
	# happened — the attack existed only to stop the click on the first sample.
	# `vinnie` is not one of those: eight o'clock is a thing approaching, and a
	# swell with a 4 ms front on it is a low beep. Defaulted, so the other
	# thirty-eight recipes are untouched, and floored well above zero because
	# zero is exactly the click this multiplier exists to remove.
	var atk: float = maxf(float(r.get("atk", 0.004)), 0.0005)
	# Rendered as floats and converted at the end, because the level a filter
	# leaves behind is not knowable in advance: a band-pass at this Q throws
	# away six to ten decibels and a high-pass on a low corner throws away
	# more. Normalising at the end is what lets the recipes be written as a
	# SHAPE, with every per-call-site `volume_db` in the game still meaning
	# what it meant.
	var xs := PackedFloat32Array()
	xs.resize(n_samples)
	var phase := 0.0
	var lp := 0.0
	var bp := 0.0
	var peak := 0.0
	for i in n_samples:
		var t := float(i) / float(SR_SFX)
		var prog := t / dur
		var f: float = base_f * (1.0 + sweep * prog)
		if vibrato > 0.0:
			f *= 1.0 + 0.06 * sin(TAU * vibrato * t)
		var s := 0.0
		if wave == "noise":
			s = rng.randf_range(-1.0, 1.0)
		else:
			phase += TAU * f / float(SR_SFX)
			match wave:
				"sine": s = sin(phase)
				"square": s = 1.0 if sin(phase) >= 0.0 else -1.0
				"saw": s = fposmod(phase, TAU) / PI - 1.0
			if nm > 0.0:
				s = lerpf(s, rng.randf_range(-1.0, 1.0), nm)
		if filt != "off":
			# Chamberlin state variable: two integrators, all three responses,
			# and the corner is `f` — so the frequency and the sweep that were
			# already written into every one of these recipes finally have a
			# reader. Clamped well under Nyquist because the topology goes
			# unstable as the corner approaches it, and 20 Hz at the bottom so
			# a sweep that runs past zero cannot park the filter on DC.
			var fq := 2.0 * sin(PI * clampf(f, 20.0, float(SR_SFX) * 0.16) / float(SR_SFX))
			lp += fq * bp
			var hi := s - lp - FILTER_Q * bp
			bp += fq * hi
			match filt:
				"lp": s = lp
				"bp": s = bp
				_: s = hi
		var env: float = exp(-dec * t)
		# Short fade-in kills the click on attack.
		env *= clampf(t / atk, 0.0, 1.0)
		# ...AND A SHORT FADE-OUT KILLS THE ONE ON THE WAY OUT, which is the
		# half that was missing. Every stream in the table stopped mid-decay
		# and the mixer dropped straight to DC: measured on the built buffers,
		# `alarm` ended at -7.8 dBFS, `beep` — the UI button, the terminal and
		# the test order — at -9.7, and `monitor`, which fires every 0.92 s for
		# a whole shift, at -12.5. That is a small tick at the end of nearly
		# every sound the game makes, all day. Six milliseconds is long enough
		# to remove the discontinuity and short enough not to soften a 40 ms
		# `tick`. Same fault as gotcha 59's loop click, in the code the loop
		# click reasoning was never applied to.
		env *= clampf((dur - t) / RELEASE_S, 0.0, 1.0)
		var vf := s * env
		xs[i] = vf
		peak = maxf(peak, absf(vf))
	var norm: float = PEAK_TARGET / maxf(peak, 0.0001)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	for i in n_samples:
		var v := int(clampf(xs[i] * norm, -32768.0, 32767.0))
		var uv := v & 0xFFFF
		data[i * 2] = uv & 0xFF
		data[i * 2 + 1] = (uv >> 8) & 0xFF
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR_SFX
	st.stereo = false
	st.data = data
	_cache[key] = st
	return st

# ------------------------------------------------------------------ ambience
var _hum_player: AudioStreamPlayer = null

## Builds the room tone: two detuned low tones plus filtered noise, loop-enabled
## so it runs continuously without a seam. Cross-faded at the ends so the loop
## point is inaudible.
## A SEAMLESS LOOP OF BAND-LIMITED NOISE, and the warm-up is the whole trick.
##
## Both continuous beds in this game are made of this — the room tone's HVAC
## hiss and the world outside the windows — so it is written once. See the note
## above `HUM_HISS_HP` for why filtered noise can be made to close at all: the
## noise sequence is seeded, so the samples before position 0 on the second lap
## are known, and running the filters over them before starting makes the state
## entering sample 0 the state leaving sample N-1 by construction.
func _noise_loop(n_samples: int, hp: float, lp: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Generated in full first, because the filters have to be walked over the
	# TAIL of it before they are walked over its head.
	var w := PackedFloat32Array()
	w.resize(n_samples)
	for i in n_samples:
		w[i] = rng.randf_range(-1.0, 1.0)
	var a_hp: float = 1.0 - exp(-TAU * hp / float(SR))
	var a_lp: float = 1.0 - exp(-TAU * lp / float(SR))
	var lo := 0.0
	var band := 0.0
	var warm: int = mini(HUM_WARMUP, n_samples)
	for k in warm:
		var x: float = w[n_samples - warm + k]
		lo += a_hp * (x - lo)
		band += a_lp * ((x - lo) - band)
	var out := PackedFloat32Array()
	out.resize(n_samples)
	for i in n_samples:
		var x: float = w[i]
		lo += a_hp * (x - lo)
		band += a_lp * ((x - lo) - band)
		out[i] = band
	return out

## THE VIEW MAKES A SOUND.
##
## Gotcha 47 records a whole session spent building a world outside — three
## rings of trees at three depths, a town on the horizon and a procedural sky
## re-tinted every minute of the shift — for the single reason that a window
## with nothing behind it is worse than a wall. It has never made a sound. The
## morning had no traffic, the afternoon nothing, and the evening was not
## quieter than either, in a building whose light knows exactly what time it is.
##
## Low and wide rather than detailed: a town four hundred metres away through
## glass is a band of noise and nothing else, and anything more specific — a
## car, a bird — is a thing you can hear is synthesised. Thirteen seconds
## against the room tone's eleven, so the two beds never come round together.
const OUTSIDE_SECONDS := 13.0
const OUTSIDE_HP := 90.0
const OUTSIDE_LP := 1250.0
const OUTSIDE_SWELLS := 3.0
const OUTSIDE_PEAK := 0.42

func _build_outside() -> AudioStreamWAV:
	if _cache.has("__outside"):
		return _cache["__outside"]
	var n_samples := int(OUTSIDE_SECONDS * SR)
	var band := _noise_loop(n_samples, OUTSIDE_HP, OUTSIDE_LP, 0x0DDD00)
	var xs := PackedFloat32Array()
	xs.resize(n_samples)
	var peak := 0.0
	for i in n_samples:
		var t := float(i) / float(SR)
		# Three swells a loop, deep enough to read as weather rather than as a
		# level. Whole cycles, for the same reason as everything else here.
		var gust := 1.0 + sin(TAU * OUTSIDE_SWELLS * t / OUTSIDE_SECONDS) * 0.35
		var s: float = band[i] * gust
		xs[i] = s
		peak = maxf(peak, absf(s))
	var norm: float = OUTSIDE_PEAK * 32767.0 / maxf(peak, 0.0001)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	for i in n_samples:
		var v := int(clampf(xs[i] * norm, -32768.0, 32767.0))
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
	_cache["__outside"] = st
	return st

func _build_hum() -> AudioStreamWAV:
	if _cache.has("__hum"):
		return _cache["__hum"]
	var n_samples := int(HUM_SECONDS * SR)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var band := _noise_loop(n_samples, HUM_HISS_HP, HUM_HISS_LP, 0xA11BEE)
	var xs := PackedFloat32Array()
	xs.resize(n_samples)
	var peak := 0.0
	for i in n_samples:
		var t := float(i) / float(SR)
		# Frequencies chosen so a whole number of cycles fits the buffer, which
		# is what makes the loop seamless without any cross-fade.
		var tone := 0.0
		for k in HUM_PARTIALS.size():
			tone += sin(TAU * float(HUM_PARTIALS[k]) * t) * float(HUM_LEVELS[k])
		# ONE SLOW BREATH PER LOOP, and exactly one, so the modulation is
		# seamless by construction rather than by luck. A plant of this size
		# does not hold a perfectly steady note; without this the tone is
		# audibly a synthesiser holding one, which is the other half of what
		# makes a short loop noticeable.
		var breath := 1.0 + sin(TAU * HUM_BREATH_CYCLES * t / HUM_SECONDS) * 0.14
		# The air handling breathes too, twice a loop and out of phase with the
		# plant, so the two never swell together and give the bed a period the
		# ear can find. Two whole cycles, for the same reason as everything
		# else in this function.
		var draught := 1.0 + sin(TAU * HUM_DRAUGHT_CYCLES * t / HUM_SECONDS + 1.7) * 0.22
		var s: float = tone * breath + band[i] * HUM_HISS_LEVEL * draught
		xs[i] = s
		peak = maxf(peak, absf(s))
	var norm: float = HUM_PEAK * 32767.0 / maxf(peak, 0.0001)
	for i in n_samples:
		var v := int(clampf(xs[i] * norm, -32768.0, 32767.0))
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
## THIRTY-TWO BARS, NOT EIGHT.
##
## Eight bars at 82bpm is 23.4 seconds, and there is exactly one piece of music
## in the game: it starts on the title screen and it does not stop until the
## career ends. That is something like two hundred and fifty passes of the same
## eight bars in one sitting, which is the single most common thing anybody
## says about a small game with a synthesised score.
##
## The material was not the problem — the playtest note that produced this
## arrangement was answered — so this is a FORM rather than a rewrite: the
## eight bars people liked, twice, then a bridge, then the eight again, with
## the arrangement thinning and thickening across the four passes so that no
## two of them sound the same. Ninety-four seconds, and the loop point is now
## four times further apart than the longest thing anybody does in one place.
const MUSIC_BARS := 32
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
	# A A B A, eight bars each. A is the head this arrangement was built around
	# and is played three times; B lifts and then walks back down to it, so the
	# return has somewhere to return from.
	"prog": [
		## A
		{"b": 0, "c": [3, 7, 10]}, {"b": -2, "c": [1, 5, 10]},
		{"b": -4, "c": [3, 7, 10]}, {"b": -5, "c": [0, 4, 7]},
		{"b": 0, "c": [3, 7, 10]}, {"b": 5, "c": [8, 12, 15]},
		{"b": -2, "c": [1, 5, 10]}, {"b": -5, "c": [0, 4, 9]},
		## A again — the head repeats, which is what a head does
		{"b": 0, "c": [3, 7, 10]}, {"b": -2, "c": [1, 5, 10]},
		{"b": -4, "c": [3, 7, 10]}, {"b": -5, "c": [0, 4, 7]},
		{"b": 0, "c": [3, 7, 10]}, {"b": 5, "c": [8, 12, 15]},
		{"b": -2, "c": [1, 5, 10]}, {"b": -5, "c": [0, 4, 9]},
		## B, up a minor third and then back down through the ii-V
		{"b": 3, "c": [4, 7, 11]}, {"b": 3, "c": [2, 7, 10]},
		{"b": -1, "c": [3, 6, 10]}, {"b": -1, "c": [2, 5, 9]},
		{"b": 1, "c": [4, 8, 11]}, {"b": 1, "c": [3, 7, 10]},
		{"b": -2, "c": [1, 5, 10]}, {"b": -5, "c": [0, 4, 7]},
		## A, last time
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
		# Which of the four eight-bar passes this is. Read by the comping, the
		# lead and the kit — see the arrangement note below.
		var section: int = bar / 8

		# No bass line. The chord below carries the bar's root as its bottom
		# note instead, which is enough to say where the harmony is without
		# putting something low on every beat.
		#
		# Comping, off the beat, because a chord on the beat is a hymn.
		if comp > 0.0:
			# And the comping opens up on the last pass — an extra push on the
			# and-of-four, which is where the head wants to go round again.
			var pushes: Array = [1.0 + swing, 2.5 + swing, 3.0]
			if section == 3:
				pushes.append(3.5 + swing)
			for h in pushes:
				var voicing: Array = [b0 - 12.0]
				voicing.append_array(chord)
				for n in voicing:
					_render(buf, "keys", bar_t + float(h) * beat, beat * 1.6,
						_semitone(root, float(n) - 12.0), comp * 0.20, rng)

		# THE ARRANGEMENT CHANGES ACROSS THE FOUR PASSES, or the form is just
		# the same eight bars four times and the length bought nothing. What
		# separates a loop you stop hearing from a loop you notice is whether
		# anything is ever ABSENT: an instrument dropping out and coming back
		# is the cheapest structure there is, and it costs no material at all.
		#
		#   A   head, lead phrasing two bars on two bars off
		#   A'  lead tacet, brushes pulled back to the rim — the quiet pass
		#   B   bridge, lead on the odd bars only, hats back
		#   A'' the head again, lead fullest, to end on the biggest thing
		# The lead phrases: it lands on a chord tone and leaves room. Sparse
		# enough to sit under eighteen minutes of a shift.
		var lead_here: bool = false
		match section:
			0: lead_here = bar % 4 < 2
			1: lead_here = false
			2: lead_here = bar % 2 == 0
			_: lead_here = bar % 4 < 3
		if lead > 0.0 and lead_here:
			var figure := [0.0, 0.75 + swing * 0.5, 1.5, 2.5 + swing]
			for i in figure.size():
				if rng.randf() > 0.82:
					continue
				var pick: int = int(chord[i % chord.size()]) if i % 2 == 0 \
					else int(scale[rng.randi() % scale.size()])
				_render(buf, "vibe", bar_t + float(figure[i]) * beat, beat * 2.2,
					_semitone(root, float(pick) + 12.0), lead * 0.13, rng)

		# Kit, brushes only. No kick: that and the bass were the DUH DUH DUH.
		#
		# The hats come off for the second pass. With the lead already tacet
		# there, that pass is a comping keyboard and a rim click, which is a
		# genuinely different texture rather than the same one turned down —
		# and it makes the bridge arriving with the hats back an event.
		if drums > 0.0:
			for b in [1.0, 3.0]:
				_render(buf, "rim", bar_t + b * beat, 0.14, 0.0, drums * 0.26, rng)
			if section != 1:
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
		_music_player.name = "MusicPlayer"
		_music_player.bus = BUS_MUSIC
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

## THE LAST HOUR, IN DECIBELS.
##
## There is one piece of music and it plays the whole time, which is a decision
## and a good one (three shift moods is how the menu's track came to be thrown
## away the moment a shift started). But a score that is at exactly the same
## level at ten past eight in the morning as it is at five to eight at night —
## in a game whose entire pressure is a man arriving at eight — is a score that
## is not in the game, it is a score playing over it.
##
## So it steps back rather than changing. `AmbienceSystem` already knows when
## the last stretch begins, because it starts the heartbeat there; the same
## window pulls the music down and lets the ward, the monitors and the pulse
## come forward. Nothing new is added and nothing is composed twice: what the
## player hears at the end is the room they have been standing in all day,
## which they have not been able to hear until now.
##
## Negative decibels, applied on top of both sliders, so a player who has
## turned the music down does not get it turned back up by this.
var music_duck := 0.0

## Wide open, and the next room. 1100 Hz leaves the vibraphone's fundamentals
## and takes the brushes and the top of the electric piano off it, which is
## what a closed door does; going much lower reads as broken rather than
## distant.
const MUSIC_LP_OPEN := 20000.0
const MUSIC_LP_EVENING := 1100.0
const MUSIC_DUCK_DB := -9.0

## 0 at the start of the window, 1 at the end of it. Idempotent and cheap: it
## is called every frame of the last forty minutes.
func duck_music(amount: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	var to: float = MUSIC_DUCK_DB * a
	if is_equal_approx(to, music_duck):
		return
	music_duck = to
	_set_music_filter(a)
	refresh_music_volume()

## The other half of the step-back, and the half that is a change rather than a
## level. Nothing else writes this filter, so the duck amount is the only thing
## that decides where the score is standing.
func _set_music_filter(amount: float) -> void:
	var at := AudioServer.get_bus_index(BUS_MUSIC)
	if at < 0:
		return
	for fx_i in AudioServer.get_bus_effect_count(at):
		var fx := AudioServer.get_bus_effect(at, fx_i)
		if fx is AudioEffectLowPassFilter:
			# Geometric rather than linear: a filter sweep that is even in
			# hertz spends nine tenths of its travel in the top octave and
			# sounds like nothing at all until the very end.
			(fx as AudioEffectLowPassFilter).cutoff_hz = MUSIC_LP_OPEN * pow(
				MUSIC_LP_EVENING / MUSIC_LP_OPEN, clampf(amount, 0.0, 1.0))

func refresh_music_volume() -> void:
	# -4, not -13.
	#
	# The chain matters and I got it wrong by about thirteen decibels. Source
	# peaks at roughly half full scale (-3.1 dB); at -13 dB of player gain and
	# the music slider under a 0.7 master, the score reached the speakers at
	# about -27 dBFS. The first playtester's report was "there's no background
	# music", and they were effectively right.
	#
	# This traced the chain through a music slider of 0.55, which is what
	# `AudioMgr` said the default was and has never been what `Settings` said —
	# see `VOLUME_FALLBACK`. At the real 0.75 the arithmetic lands two and a
	# half decibels higher and the conclusion is the same one.
	var g: float = maxf(master_volume * music_volume, 0.0001)
	if _music_player != null:
		_music_player.volume_db = -4.0 + linear_to_db(g) + music_duck
	# The room tone has to be re-levelled here too, and it is on its OWN slider
	# now rather than on the score's. `start_ambience()` runs exactly once, at
	# ward load, and baked the slider values into volume_db at that moment — so
	# a player who dragged a slider to zero silenced the score and then listened
	# to the hum at its original level for the rest of the run. Settings only
	# knows to call this function, so this is where the beds get told.
	#
	# The name of the function is now half a lie and it keeps it anyway: it is
	# the one entry point Settings calls for every volume key, and splitting it
	# would give the ambience slider a second place to be forgotten from.
	if _hum_player != null:
		_hum_player.volume_db = _hum_base_db + linear_to_db(
			maxf(_ambience_gain(), 0.0001))
	# ...and so does the world outside the windows, which is the other bed and
	# lives on the ward rather than in here. It is re-levelled every half
	# second off the same gain, so this only has to not contradict it.
	var amb := get_tree().get_first_node_in_group("ambience") if get_tree() != null else null
	if amb != null and amb.has_method("relevel_outside"):
		amb.call("relevel_outside")

## The hum's level BEFORE the sliders, remembered so refresh_music_volume() can
## re-apply them to it without start_ambience() being called again.
var _hum_base_db := -15.0

## -15, AND THE NUMBER IS THE RESULT OF A MEASUREMENT RATHER THAN AN OPINION.
##
## It was -30, then -18 on the argument that a room tone twenty-six decibels
## under the music is not quiet but absent. Both of those were reasoning about
## a bed that was 94% sub-100 Hz, so they were arguments about a level for
## something most speakers were not reproducing at all.
##
## Measured off the built buffers, both at the same sliders: the score's RMS is
## -20.2 dBFS and it plays at -4, so it reaches the mix at about -30. The room
## tone's RMS is -24.9 dBFS, so at -15 it reaches the mix at about -46 — call
## it sixteen decibels under the score, which is a bed you notice when it stops
## and not while it runs. In the last forty minutes the score comes down nine
## and goes behind a low-pass, and the same bed is then about seven decibels
## under it, which is the ward coming forward that the whole evening is for.
func start_ambience(volume_db := -15.0) -> void:
	_ensure_voices()
	if _hum_player == null:
		_hum_player = AudioStreamPlayer.new()
		_hum_player.name = "Hum"
		add_child(_hum_player)
	_hum_player.stream = _build_hum()
	_hum_base_db = volume_db
	_hum_player.volume_db = volume_db + linear_to_db(maxf(_ambience_gain(), 0.0001))
	_hum_player.play()

func stop_ambience() -> void:
	if _hum_player:
		_hum_player.stop()

# ------------------------------------------------------------------ playback
## WHAT WAS ASKED FOR, WHETHER OR NOT THERE WAS ANYWHERE TO PLAY IT.
##
## Every harness in this repo is headless, `play()` returns on the first line
## when there is no audio device, and `AudioStreamPlayer.playing` is false in a
## paused tree anyway — so until this existed NO check anywhere in the project
## could assert that doing a thing makes a noise. The two source scans in the
## smoke run verify that every name asked for is a recipe and that every recipe
## is named somewhere, which is a check on the SPELLING at both ends; neither
## of them can tell whether the sound a verb plays is the same one the button
## next to it plays, and that is exactly how five of the game's biggest moments
## came to share three interface beeps and how eleven recipes came to be one
## white noise.
##
## A short ring of names, appended before the headless guard and before
## anything else can fail. `play_at` records too, and records TWICE on the path
## where it has no scene to place a sound in and falls through to `play()` —
## which nothing cares about, because the question this answers is "was it
## asked for", never "how many times".
const HEARD_MAX := 32
var heard: PackedStringArray = PackedStringArray()

func _heard(name: String) -> void:
	heard.append(name)
	if heard.size() > HEARD_MAX:
		heard.remove_at(0)

## Everything since the last time somebody looked. The caller clears it; there
## is no automatic reset, because a check that clears its own window is a check
## that cannot be confused by the frame it happens to run in.
func forget_heard() -> void:
	heard.clear()

func play(name: String, volume_db: float = -6.0, pitch: float = 1.0, variant := 0) -> void:
	_heard(name)
	# Nothing to play to. The headless harnesses call every verb in the game a
	# few thousand times and each one wanted a sound, which buried the actual
	# output of a probe under eighteen identical engine errors per simulated
	# day. There is no audio device in a `--headless` run and there never was.
	if DisplayServer.get_name() == "headless":
		return
	_ensure_voices()
	var st := _build(name, variant)
	var p: AudioStreamPlayer = _voices[_next_voice] if VOICE_SOUNDS.has(name) else _players[_next]
	if VOICE_SOUNDS.has(name):
		_next_voice = (_next_voice + 1) % _voices.size()
	else:
		_next = (_next + 1) % _players.size()
	p.stream = st
	p.volume_db = volume_db + linear_to_db(maxf(_sfx_gain(), 0.0001))
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

func play_at(name: String, pos: Vector3, volume_db: float = -4.0, pitch: float = 1.0,
		variant := 0) -> void:
	_heard(name)
	_ensure_voices()
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		play(name, volume_db, pitch, variant)
		return
	var st := _build(name, variant)
	var p: AudioStreamPlayer3D = _voices3d[_next_voice3d] if VOICE_SOUNDS.has(name) \
		else _players3d[_next3d]
	if VOICE_SOUNDS.has(name):
		_next_voice3d = (_next_voice3d + 1) % _voices3d.size()
	else:
		_next3d = (_next3d + 1) % _players3d.size()
	p.global_position = pos
	p.stream = st
	p.volume_db = volume_db + linear_to_db(maxf(_sfx_gain(), 0.0001))
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

## One blip of somebody talking.
##
## `voice` is any stable string — an npc_id — so the same character always
## sounds like themselves. Three base timbres and a pitch offset off the hash is
## enough that a ward full of people is a ward full of different voices.
##
## The pitch comes from `voice_pitch()`, which is now the ONLY place a
## character's pitch is decided. It used to be `0.82 + (h % 40) * 0.011` here
## and `0.74 + (h % 1000) / 1000 * 0.68` in `NPCBody._voice_pitch()` — two
## different numbers off the same string, so the grunt a person makes under a
## line and the blips of the line itself were two different people. Nobody
## could hear it while nothing called `mumble()` at all.
func mumble(voice: String, volume_db := -20.0) -> void:
	# The building talking, which is a different instrument and not a voice on
	# the ward's spread at all: a paging horn is band-limited, honky, and the
	# same every time it speaks because there is only one of it.
	if voice == PA_VOICE:
		play(PA_BANK, volume_db, 0.97 + randf_range(-0.04, 0.04))
		return
	var bank: String = MUMBLE_BANKS[absi(hash(voice)) % MUMBLE_BANKS.size()]
	# Plus a small per-syllable wobble, so a line is not a monotone.
	play(bank, volume_db, voice_pitch(voice) + randf_range(-0.06, 0.06))

## A STEADY PITCH PER CHARACTER, AND ONE DEFINITION OF IT.
##
## 0.74 to 1.42 — deep enough for an eighty-year-old man, high enough for a
## twenty-two-year-old, and every step between is audibly a different person
## rather than the same one on a bad day. It lived in `NPCBody._voice_pitch()`,
## which is where it was measured; it is here because the HUD now needs it too
## and the alternative was a second formula (see `mumble`). `NPCBody` still
## caches its own answer, because a hash per line is a hash per line.
func voice_pitch(voice: String) -> float:
	return 0.74 + float(absi(hash(voice)) % 1000) / 1000.0 * 0.68

## Slight random pitch keeps repeated sounds from sounding like a machine gun —
## and, for the noise recipes, a different noise as well as a different pitch.
## Pitch alone does not do it: resampling the same crunch is still the same
## crunch, and a footstep is heard several times a second.
func play_var(name: String, volume_db: float = -6.0, spread: float = 0.12) -> void:
	play(name, volume_db, 1.0 + randf_range(-spread, spread), _pick_variant(name))

func play_at_var(name: String, pos: Vector3, volume_db: float = -4.0, spread: float = 0.12) -> void:
	play_at(name, pos, volume_db, 1.0 + randf_range(-spread, spread), _pick_variant(name))

## Only the noise recipes get variants: an oscillator seeded differently is the
## same tone, so a second copy of `beep` would cost cache and buy nothing.
func _pick_variant(name: String) -> int:
	var r: Dictionary = RECIPES.get(name, {})
	if String(r.get("w", "")) != "noise":
		return 0
	return randi() % NOISE_VARIANTS
