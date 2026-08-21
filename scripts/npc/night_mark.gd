class_name NightMark
extends NPCBody
## Somebody walking home, who does not know you are behind them.
##
## An NPCBody with two additions: it walks a route nothing pathfound, and it can
## be interacted with. Everything else — the head that turns, the blink, the
## breathing, the speech bubble — is the same person the ward is full of, which
## is the entire point of doing the evening in 3D. The thing you are creeping up
## on has to be a person or the phase is a diagram.

var route: PackedVector3Array = PackedVector3Array()
var _leg := 0
var _done := false

func start(points: PackedVector3Array) -> void:
	route = points
	if route.size() > 0:
		global_position = route[0]
	_leg = 1
	_walk_on()

func _walk_on() -> void:
	if _done or _leg >= route.size():
		return
	follow(PackedVector3Array([route[_leg]]))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _done or route.is_empty():
		return
	if _leg < route.size() and global_position.distance_to(route[_leg]) < 1.0:
		_leg += 1
		_walk_on()

## Has the walk finished? They have gone inside and the evening is over.
func home() -> bool:
	return _leg >= route.size()

func prompt(_player) -> Array:
	if _done:
		return ["", ""]
	return [display, "[hold E]"]

func use_seconds(_player, _held) -> float:
	# A hold, not a tap. The one act in the game that ought to take a moment of
	# committing to, and long enough that a bystander's sweep can catch you
	# halfway through it.
	return 1.1

func interact(_player, _held) -> void:
	if _done:
		return
	_done = true
	stop_moving()
	startle(1.0)
	var night = get_tree().get_first_node_in_group("night_system")
	if night != null:
		night.strike()
