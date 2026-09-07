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

## sound, volume, pitch spread
const SPARSE := [
	["monitor", -30.0, 0.25],
	["cough", -28.0, 0.35],
	["pipe", -32.0, 0.2],
	["trolley", -31.0, 0.25],
	["door", -30.0, 0.3],
	["step", -33.0, 0.3],
	["beep_low", -32.0, 0.3],
	# Three that were synthesised and then never played by anything. A ward two
	# corridors away has an alarm going off in it every so often and nobody in
	# this one reacts, which is both what a hospital sounds like and a free
	# reminder that the building is bigger than the room you are standing in.
	["alarm", -37.0, 0.15],
	["squeak", -34.0, 0.4],
	["gasp", -33.0, 0.3],
]

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

var hospital: Hospital = null
var _timer := 0.0
var _mon_timer := 0.0
var _mon_index := 0
var _pulse := 0.0

func _ready() -> void:
	add_to_group("ambience")
	hospital = get_tree().get_first_node_in_group("hospital")
	AudioMgr.start_ambience()
	_timer = RNG.randf_range_s("ambience", MIN_GAP, MAX_GAP)

func _process(delta: float) -> void:
	if not GameState.clock_running:
		return
	_monitors(delta)
	_pulse_pass(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = RNG.randf_range_s("ambience", MIN_GAP, MAX_GAP)
	_play_one()

## Two beats, a fifth of a second apart, because one is a click and two is a
## heart. Not positional: it is the only sound in the game that is inside the
## player's head rather than in the room.
func _pulse_pass(delta: float) -> void:
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

func _play_one() -> void:
	if hospital == null:
		return
	var spec: Array = RNG.pick("ambience_pick", SPARSE)
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
