class_name AmbienceSystem
extends Node
## Room tone plus sparse, distant, positional noises.
##
## A hospital that is silent between events reads as a diorama. The point of
## this is not realism — it is that the player learns to distinguish "background
## noise" from "something just happened near me", which is the discrimination the
## whole distraction economy depends on.

const MIN_GAP := 3.5
const MAX_GAP := 11.0

## TWELVE HOURS THAT ALL SOUNDED THE SAME.
##
## The only time-driven audio in the whole game was the heartbeat and the duck
## in the last forty minutes — about a real minute of a shift. Everything else,
## the room tone and this table included, was identical at ten past eight in
## the morning and at half past seven at night, in a game whose one pressure is
## the evening arriving and whose lighting is re-graded every single minute.
##
## So each entry now carries what it is worth in each quarter of the day, and
## nothing else changes: same sounds, same placement, same machinery. Visitors
## and deliveries are a daytime thing and thin out; plumbing and a bad chest are
## worse at night; and the first hour is when the building is only just waking
## up, which is why the alarm two wards away is flatly impossible in it. A
## weight of zero is a sound that cannot happen in that stretch at all.
##
## sound, volume, pitch spread, and weights for [08-09, 09-12, 12-17, 17-20]
const SPARSE := [
	["monitor", -30.0, 0.25, [1.0, 1.0, 1.0, 1.0]],
	["cough", -28.0, 0.35, [0.9, 1.0, 1.0, 1.5]],
	["pipe", -32.0, 0.2, [0.5, 0.6, 0.9, 1.7]],
	["trolley", -31.0, 0.25, [1.2, 1.5, 1.6, 0.4]],
	["door", -30.0, 0.3, [1.3, 1.6, 1.4, 0.5]],
	["step", -33.0, 0.3, [1.3, 1.6, 1.4, 0.5]],
	["beep_low", -32.0, 0.3, [1.0, 1.0, 1.0, 1.0]],
	# Three that were synthesised and then never played by anything. A ward two
	# corridors away has an alarm going off in it every so often and nobody in
	# this one reacts, which is both what a hospital sounds like and a free
	# reminder that the building is bigger than the room you are standing in.
	["alarm", -37.0, 0.15, [0.0, 0.2, 0.5, 0.9]],
	["squeak", -34.0, 0.4, [0.6, 0.8, 1.0, 1.6]],
	["gasp", -33.0, 0.3, [0.7, 0.9, 1.1, 1.5]],
]

## Which quarter of the shift it is: 0 the first hour, 1 the rest of the
## morning, 2 the afternoon, 3 from five o'clock. Clamped rather than wrapped,
## so a ward that somehow reads a time outside the shift gets the nearest end
## of it and never an index that is not there.
static func phase_of(minute: int) -> int:
	if minute < Cases.DAY_START_MINUTE + 60:
		return 0
	if minute < 12 * 60:
		return 1
	if minute < 17 * 60:
		return 2
	return 3

## The ward is busier in the middle of the day than at either end of it, and a
## gap is the only knob that says so — the alternative is more sounds, which is
## the wrong answer to "does this place feel awake".
const PHASE_GAP := [1.15, 0.95, 0.85, 1.25]

## THE SOUND A WARD ACTUALLY MAKES.
##
## Five occupied beds and not one of them had a monitor on it. A bedside
## monitor is the single most recognisable noise in a hospital and it is also
## the most useful one this game could have: it is positional, so it tells you
## where the beds are with your eyes shut; it is per-patient, so the ward has
## five voices rather than one; and it is CONTINUOUS, which is what turns a set
## of rooms into a place somebody works.
##
## Round-robin rather than a timer per bed, so five monitors cost one timer and
## can never drift into unison — which is the thing that would make them read
## as one machine instead of five.
const MONITOR_CYCLE := 4.6

## YOUR OWN PULSE, IN THE LAST HOUR.
##
## `heartbeat` was synthesised and played by nothing. The obvious hook — beat
## whenever somebody can see you — is the wrong one: being seen is the NORMAL
## state of standing in a ward, so it would sound constantly and mean nothing,
## and the visible tells on the staff already say it better.
##
## The pressure this game actually has is the evening arriving. Everything
## costs minutes off one clock, the day force-ends at eight, and the last of it
## is when a player is deciding what to leave undone. So it beats there, and
## nowhere else: slow at forty minutes to go, tightening as it closes.
const PULSE_FROM := 40
const PULSE_SLOW := 1.75
const PULSE_FAST := 0.95

## TIME IS THE ONLY THING THE PLAYER SPENDS AND IT MADE NO SOUND.
##
## Every verb costs minutes off one clock, `WardDay.advance_to` skips them
## instantly, the HUD clock jumps, and a five-minute test order was
## indistinguishable from a fifty-minute walk to the registrar. The costs ARE
## the game — the day is a budget and not a checklist — so the resource being
## spent is the one thing that should be audible.
##
## A tick per five minutes, up to five of them, falling a semitone each: five
## minutes is one click and fifty is a run down the stairs. It is driven off
## `GameState.minute_passed` rather than from each verb on purpose. `advance_to`
## calls `skip_to`, which re-enters the minute handler immediately (gotcha 27),
## and a sound emitted per call site therefore fires twice on a re-entrant
## advance; the delta actually APPLIED to the clock is emitted exactly once, and
## that is what this counts. It is also the only place that can see the cost of
## a verb without `WardDay` having to tell anybody about it.
const CLOCK_PER_TICK := 5
const CLOCK_MAX_TICKS := 5
const CLOCK_SPACING := 0.09
## One semitone down per tick.
const CLOCK_FALL := 0.9439

## THE WORLD OUTSIDE THE WINDOWS, WHICH HAS NEVER MADE A SOUND.
##
## One looping emitter per exterior run, two metres beyond the glass at window
## height, so the outside is louder when you are standing at a window and the
## corridor is quieter than the bay. Level and pitch follow a smooth arc across
## the shift rather than a step per hour: busiest in the early afternoon,
## thinning and dropping toward eight, which is the same curve the light is
## graded on and the reason the evening arrives instead of being announced.
##
## Pitch is how the brightness moves, because resampling a noise loop shifts
## the whole band and costs nothing. Down is further away.
const OUTSIDE_QUIET_DB := -32.0
const OUTSIDE_BUSY_DB := -23.0
const OUTSIDE_QUIET_PITCH := 0.84
const OUTSIDE_BUSY_PITCH := 1.06
const OUTSIDE_OFFSET := 2.0
const OUTSIDE_HEIGHT := 1.7
const OUTSIDE_UPDATE := 0.5

var hospital: Hospital = null
var _outside: Array[AudioStreamPlayer3D] = []
var _outside_timer := 0.0
var _timer := 0.0
var _mon_timer := 0.0
var _mon_index := 0
var _pulse := 0.0
var _last_minute := 0
var _ticks_left := 0
var _tick_gap := 0.0
var _tick_pitch := 1.0

func _ready() -> void:
	add_to_group("ambience")
	hospital = get_tree().get_first_node_in_group("hospital")
	AudioMgr.start_ambience()
	_timer = _next_gap()
	_last_minute = GameState.minute_of_day
	# GUARDED, and disconnected on the way out. A node that leaves the tree is
	# not freed by that alone, so an unguarded pair would double the connection
	# — and would leave a ward that has been taken down still listening to the
	# world clock, which is the shape of fault gotcha 11 is about.
	if not GameState.minute_passed.is_connected(_on_minute_passed):
		GameState.minute_passed.connect(_on_minute_passed)
	_spawn_outside()

## Four emitters at the midpoints of the shell, derived from the layout rather
## than written down, so a building that grows a room still has its outside in
## the right place.
func _spawn_outside() -> void:
	if hospital == null:
		return
	var shell := Rect2()
	for i in Hospital.LAYOUT.size():
		var r: Rect2 = Hospital.LAYOUT[i]["rect"]
		shell = r if i == 0 else shell.merge(r)
	var mid := shell.get_center()
	var at := [
		Vector3(mid.x, OUTSIDE_HEIGHT, shell.position.y - OUTSIDE_OFFSET),
		Vector3(mid.x, OUTSIDE_HEIGHT, shell.end.y + OUTSIDE_OFFSET),
		Vector3(shell.position.x - OUTSIDE_OFFSET, OUTSIDE_HEIGHT, mid.y),
		Vector3(shell.end.x + OUTSIDE_OFFSET, OUTSIDE_HEIGHT, mid.y),
	]
	for p in at:
		var v := AudioStreamPlayer3D.new()
		v.stream = AudioMgr._build_outside()
		v.bus = AudioMgr.BUS_WORLD
		v.max_distance = 40.0
		v.unit_size = 6.0
		v.volume_db = OUTSIDE_QUIET_DB
		add_child(v)
		v.global_position = hospital.to_global(p)
		v.play()
		_outside.append(v)
	_outside_pass(OUTSIDE_UPDATE)

## 0 at either end of the shift and 1 in the early afternoon. A sine rather
## than a table because the thing being modelled is a day, and a day does not
## have edges in it.
func _outside_pass(delta: float) -> void:
	_outside_timer -= delta
	if _outside_timer > 0.0 or _outside.is_empty():
		return
	_outside_timer = OUTSIDE_UPDATE
	var span := float(Cases.DEBT_DUE_MINUTE - Cases.DAY_START_MINUTE)
	var through: float = clampf(
		(float(GameState.minute_of_day) - float(Cases.DAY_START_MINUTE)) / maxf(span, 1.0),
		0.0, 1.0)
	var busy: float = sin(PI * through)
	# On the effects slider, like every other positional sound in the game and
	# unlike the room tone, which is levelled with the score.
	var gain: float = linear_to_db(maxf(AudioMgr._sfx_gain(), 0.0001))
	var db: float = lerpf(OUTSIDE_QUIET_DB, OUTSIDE_BUSY_DB, busy) + gain
	var pitch: float = lerpf(OUTSIDE_QUIET_PITCH, OUTSIDE_BUSY_PITCH, busy)
	for v in _outside:
		if not is_instance_valid(v):
			continue
		v.volume_db = db
		v.pitch_scale = pitch

## THE WARD BELONGS TO THE WARD, AND SO DOES EVERYTHING IT IS DOING TO THE MIX.
##
## Two pieces of state outlive this node otherwise, and both of them are silent
## faults of the kind gotcha 58 is about. The music duck was released only from
## `_pulse_pass`, which needs this node alive, the tree unpaused AND the clock
## running — three conditions, each independently sufficient to strand it — so
## the score sat nine decibels down through the force-end, the handover, the
## verdict, both ending cards and the next morning's briefing, and "Quit to
## Menu" after twenty past seven left the title screen ducked for the rest of
## the process. The room tone had the matching fault from the other side:
## `stop_ambience()` had no callers at all, and `_hum_player` is a child of the
## AudioMgr autoload, so the ward's air handling followed the player out to the
## main menu and kept running there.
##
## `_exit_tree` is the one place that cannot be skipped: every way out of a
## shift takes the scene down with it.
func _exit_tree() -> void:
	if GameState.minute_passed.is_connected(_on_minute_passed):
		GameState.minute_passed.disconnect(_on_minute_passed)
	AudioMgr.duck_music(0.0)
	AudioMgr.stop_ambience()
	_stop_outside()

## Stopped, let go of, and freed, in that order — a merely stopped player still
## HOLDS a looping stream whose playback is alive on the audio server's side,
## and `run_tests.sh` fails the day run on any `RIDs of type ... were leaked`
## line. `AudioMgr._exit_tree` records that fixing only some of the players
## passed once and then failed three times running; these are four more of
## exactly that kind and they are the newest, which is what makes them the ones
## a future teardown will forget.
func _stop_outside() -> void:
	for v in _outside:
		if is_instance_valid(v):
			v.stop()
			v.stream = null
			v.free()
	_outside.clear()

## The window being closed is the case a player actually hits, and it fires
## while everything is still alive — unlike `_exit_tree`, which runs as the
## audio server is already coming down.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_outside()

func _process(delta: float) -> void:
	# NOT GUARDED ON THE CLOCK, and that is the whole point of splitting this.
	#
	# `UIRoot._set_modal` sets `GameState.clock_running = false` for every
	# screen that does not pause the world — which is exactly the patient card,
	# the chart and the records screen, the three the player lives in. The tree
	# is not paused for those, so the NPCs keep walking and keep talking, and
	# every machine in the building used to stop dead the instant a card
	# opened: five monitors, every distant door, every cough and trolley, gone,
	# leaving the room tone alone. `screen_base.gd` states the intent outright
	# — "a paused ward is a photograph... they are still in shot, still
	# breathing, still reacting" — and the audio contradicted it at the single
	# most-used interaction in the game. A ward that is visible is a ward that
	# is audible.
	#
	# `_pulse_pass` keeps the guard, because a heart counting down to eight
	# o'clock while the clock is stopped is a lie. No guard is needed for the
	# tree being PAUSED: this node's process mode is INHERIT, so a screen that
	# pauses the world stops this function outright.
	_monitors(delta)
	_clock_pass(delta)
	_outside_pass(delta)
	_pulse_pass(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _next_gap()
	_play_one()

func _next_gap() -> float:
	var phase := phase_of(GameState.minute_of_day)
	return RNG.randf_range_s("ambience", MIN_GAP, MAX_GAP) * float(PHASE_GAP[phase])

## Every advance of the world clock, including the one-per-minute ones. Only a
## JUMP is a verb: a minute passing on its own is the day going by and has the
## HUD to say so.
func _on_minute_passed(m: int) -> void:
	var jump: int = m - _last_minute
	_last_minute = m
	if jump <= 1 or jump > 12 * 60:
		return
	_ticks_left = clampi(jump / CLOCK_PER_TICK, 1, CLOCK_MAX_TICKS)
	_tick_gap = 0.0
	_tick_pitch = 1.0

func _clock_pass(delta: float) -> void:
	if _ticks_left <= 0:
		return
	_tick_gap -= delta
	if _tick_gap > 0.0:
		return
	_tick_gap = CLOCK_SPACING
	_ticks_left -= 1
	# Not positional. Time is not somewhere in the room.
	AudioMgr.play("clock", -19.0, _tick_pitch)
	_tick_pitch *= CLOCK_FALL

## Two beats, a fifth of a second apart, because one is a click and two is a
## heart. Not positional: it is the only sound in the game that is inside the
## player's head rather than in the room.
func _pulse_pass(delta: float) -> void:
	# The one thing in this file that a stopped clock genuinely should stop.
	# Note what it does NOT do: it leaves the duck exactly where it is rather
	# than releasing it, because a card opened at ten to eight has not moved
	# the evening back to lunchtime.
	if not GameState.clock_running:
		return
	var left: int = Cases.DEBT_DUE_MINUTE - GameState.minute_of_day
	if left > PULSE_FROM or left < 0:
		_pulse = 0.0
		# ...AND THE MUSIC COMES BACK UP OUTSIDE THE WINDOW, which matters
		# because the next morning is a new day on the same audio server: a
		# duck that is only ever applied leaves the score nine decibels down
		# for the rest of the career.
		AudioMgr.duck_music(0.0)
		return
	_pulse -= delta
	# THE SCORE STEPS BACK OVER THE SAME FORTY MINUTES THE HEART BEATS IN.
	#
	# One piece of music, played the whole time, at exactly the same level at
	# ten past eight in the morning as at five to eight at night — in a game
	# whose entire pressure is a man arriving at eight. Pulling it down here
	# adds nothing and composes nothing; it lets the ward the player has been
	# standing in all day finally be audible, with the monitors and the pulse
	# in front of it. Ramped off `left`, so it arrives with the deadline
	# rather than at it.
	AudioMgr.duck_music(1.0 - clampf(float(left) / float(PULSE_FROM), 0.0, 1.0))
	if _pulse > 0.0:
		return
	var t: float = clampf(float(left) / float(PULSE_FROM), 0.0, 1.0)
	_pulse = lerpf(PULSE_FAST, PULSE_SLOW, t)
	var vol: float = lerpf(-19.0, -27.0, t)
	AudioMgr.play("heartbeat", vol, 1.0)
	# The second beat, quieter and a touch lower, is what stops it reading as a
	# metronome.
	var tree := get_tree()
	if tree:
		await tree.create_timer(0.21).timeout
		if is_inside_tree() and GameState.clock_running:
			AudioMgr.play("heartbeat", vol - 4.0, 0.88)

## One beep, from one bed, moving round the ward.
func _monitors(delta: float) -> void:
	_mon_timer -= delta
	if _mon_timer > 0.0:
		return
	var beds := get_tree().get_nodes_in_group("bed")
	var live: Array = []
	for b in beds:
		if b is Node3D and b.get("occupant") != null:
			live.append(b)
	if live.is_empty():
		_mon_timer = MONITOR_CYCLE
		return
	# The whole cycle is divided between the beds that exist, so the ward beeps
	# at a steady rate however many people are in it.
	_mon_timer = MONITOR_CYCLE / float(live.size())
	_mon_index = (_mon_index + 1) % live.size()
	var bed: Node3D = live[_mon_index]
	if not bed.is_inside_tree():
		return
	# A pitch per BED, stable across the shift: two monitors at the same pitch
	# are one monitor, and a monitor that changes pitch is a monitor nobody
	# believes in. Quiet, because five of them are playing.
	var pitch := 0.94 + float(_mon_index) * 0.035
	AudioMgr.play_at("monitor", bed.global_position + Vector3(0, 1.1, 0), -26.0, pitch)

## One sparse sound, weighted by the hour. `RNG.pick_weighted` takes a
## dictionary and returns a KEY, so the keys are indices into SPARSE — the
## alternative is a name, and two entries could then never share a sound.
func _pick_sparse() -> Array:
	var phase := phase_of(GameState.minute_of_day)
	var weights := {}
	for i in SPARSE.size():
		var spec: Array = SPARSE[i]
		weights[i] = float((spec[3] as Array)[phase])
	var at = RNG.pick_weighted("ambience_pick", weights)
	if at == null:
		return SPARSE[0]
	return SPARSE[int(at)]

func _play_one() -> void:
	if hospital == null:
		return
	var spec: Array = _pick_sparse()
	# Deliberately placed AWAY from the player, so ambience never gets confused
	# with a prop falling over next to them.
	var player = get_tree().get_first_node_in_group("player")
	# THE ROOMS THAT EXIST, WEIGHTED TOWARD THE ONE YOU ARE STANDING IN.
	#
	# This picked from six keys and the building has four: `lobby`, `ward_101`,
	# `ward_105` and `supply` were all demolished in the redesign. Four of every
	# six picks missed, fell through `Hospital.point_in`'s push_error to
	# Vector3.ZERO, and played from the corner where the corridor meets the
	# station — audible right across a 29m building on a 30m falloff. And the
	# five-bed bay, where the entire game happens, was never named at all: the
	# ward had no ambience of its own for as long as it has existed.
	var pos := hospital.point_in(String(RNG.pick("ambience_room",
		["ward", "ward", "ward", "corridor", "station", "office"])), "ambience_pt")
	if player != null and pos.distance_to(player.global_position) < 8.0:
		return
	AudioMgr.play_at_var(String(spec[0]), pos, float(spec[1]), float(spec[2]))
