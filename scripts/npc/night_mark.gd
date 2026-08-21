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

## How fast this person walks home, from the street's own `mark_speed`. Held on
## the mark rather than written onto `_speed` after start(), because the route
## is followed one leg at a time and every leg calls follow() again.
var pace := 0.0

func start(points: PackedVector3Array) -> void:
	route = points
	if route.size() > 0:
		global_position = route[0]
	_leg = 1
	_walk_on()

func _walk_on() -> void:
	if _done or _leg >= route.size():
		return
	follow(PackedVector3Array([route[_leg]]), false, pace)

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
	var night = get_tree().get_first_node_in_group("night_system")
	if night == null:
		return [display, "[hold E]"]
	match String(NightSystem.act_of(String(night._place.get("id", "")))):
		"rig":
			# Nothing to do to them directly. The thing you did is up the road.
			return [display, "not like this"]
		"bump":
			# Only at the kerb. Everywhere else this is a man walking into
			# somebody, which is not an injury and is very much a witness.
			if night.bump_window() <= 0.0:
				return [display, "not here"]
			return [display, "NOW · [hold E]"]
	return [display, "[hold E]"]

func use_seconds(_player, _held) -> float:
	# The timing act is a shove, not a procedure. Holding for a second at the
	# kerb is not a thing the window has room for.
	var night = get_tree().get_first_node_in_group("night_system")
	if night != null and String(NightSystem.act_of(
			String(night._place.get("id", "")))) == "bump":
		return 0.25
	return 1.1

func interact(_player, _held) -> void:
	if _done:
		return
	var night2 = get_tree().get_first_node_in_group("night_system")
	if night2 != null and not night2.can_act():
		return
	_done = true
	stop_moving()
	startle(1.0)
	var night = get_tree().get_first_node_in_group("night_system")
	if night != null:
		night.strike()
