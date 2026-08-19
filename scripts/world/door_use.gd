extends Area3D
## Interaction surface for a SwingDoor. Separate node so the raycast has
## something with an `interact` method to hit without making the physics leaf
## itself interactable (which would fight with the grab system).

var door = null

func prompt(_player) -> Array:
	if door == null:
		return ["", ""]
	return ["Open door" if not door.is_open() else "Pull door", "or just walk into it"]

func interact(player, _held) -> void:
	if door == null:
		return
	# Open it if it is shut, pull it shut if it is open. It used to call push()
	# either way, so "Pull door" opened the door.
	if door.is_open():
		door.pull_shut()
	else:
		door.push(player.global_position if player else global_position)
