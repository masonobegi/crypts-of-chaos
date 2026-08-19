extends Area3D
## Interaction surface for a PatientBed — brake toggle and (later) bed controls.

var bed = null

func prompt(_player) -> Array:
	if bed == null:
		return ["", ""]
	if bed.brake_on:
		return ["Release bed brake", "the bed will roll" if bed.occupant else ""]
	return ["Set bed brake", "push the bed to move it"]

func interact(_player, _held) -> void:
	if bed:
		bed.toggle_brake()
