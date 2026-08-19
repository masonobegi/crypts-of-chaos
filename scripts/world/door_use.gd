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
	door.push(player.global_position if player else global_position)
