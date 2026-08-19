extends Area3D
## Interaction surface for a SwingDoor. Separate node so the raycast has
## something with an `interact` method to hit without making the physics leaf
## itself interactable (which would fight with the grab system).

var door = null

func prompt(_player) -> Array:
	if door == null:
		return ["", ""]
	if door.is_open():
		return ["Pull door shut", "[Shift+E] slam it"]
	return ["Open door", "or just walk into it"]

func interact(player, _held) -> void:
	if door == null:
		return
	# Open it if it is shut, pull it shut if it is open. It used to call push()
	# either way, so "Pull door" opened the door.
	# Shift is the "other way round" modifier everywhere else in this game — the
	# supply shelf cycles with it, the treatment dial goes down with it — so it
	# slams here. slam() existed with no caller at all: it zeroes the leaf,
	# thuds, and emits a noise event with a sixteen-metre radius, which is one
	# of the loudest distractions in the building and could not be produced.
	if door.is_open() and Input.is_action_pressed("sprint"):
		door.slam()
	elif door.is_open():
		door.pull_shut()
	else:
		door.push(player.global_position if player else global_position)
