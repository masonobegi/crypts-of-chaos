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
		patrol_rooms = ["corridor", "station", "ward_101", "ward_102", "ward_103",
			"ward_104", "ward_105", "supply", "intake", "day_room"]
	super._ready()
