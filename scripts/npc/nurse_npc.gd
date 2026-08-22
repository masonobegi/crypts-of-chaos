class_name NurseNPC
extends StaffNPC
## A nurse. Nurses are the primary witness class: they are always around, they
## talk to each other constantly, and they are the reason the noise-distraction
## economy exists.

func _ready() -> void:
	role = "nurse"
	outfit = Build.SCRUB_BLUE if archetype != "corrupt" else Build.SCRUB_GREEN
	home_room = "station"
	if patrol_rooms.is_empty():
		# THESE ARE THE ONLY FOUR ROOMS THERE ARE. The old list named ten, of
		# which six were demolished with the departments and the bay itself was
		# not among them, so `point_in` returned Vector3.ZERO and every patrol
		# leg walked her to the corner of the world.
		patrol_rooms = ["corridor", "station", "ward"]
	super._ready()
