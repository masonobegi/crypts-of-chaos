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
]

var hospital: Hospital = null
var _timer := 0.0

func _ready() -> void:
	add_to_group("ambience")
	hospital = get_tree().get_first_node_in_group("hospital")
	AudioMgr.start_ambience()
	_timer = RNG.randf_range_s("ambience", MIN_GAP, MAX_GAP)

func _process(delta: float) -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = RNG.randf_range_s("ambience", MIN_GAP, MAX_GAP)
	_play_one()

func _play_one() -> void:
	if hospital == null:
		return
	var spec: Array = RNG.pick("ambience_pick", SPARSE)
	# Deliberately placed AWAY from the player, so ambience never gets confused
	# with a prop falling over next to them.
	var player = get_tree().get_first_node_in_group("player")
	var pos := hospital.point_in(String(RNG.pick("ambience_room",
		["corridor", "lobby", "station", "ward_101", "ward_105", "supply"])), "ambience_pt")
	if player != null and pos.distance_to(player.global_position) < 8.0:
		return
	AudioMgr.play_at_var(String(spec[0]), pos, float(spec[1]), float(spec[2]))
