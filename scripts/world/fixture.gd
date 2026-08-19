class_name Fixture
extends StaticBody3D
## Base for everything bolted to the floor that the player can use: machines,
## windows, switches, terminals, shelves, shredders.
##
## Fixtures are on the `interactable` physics layer so the look-ray finds them
## without them participating in prop collisions.

@export var room_key := ""
@export var fixture_name := "Fixture"

func _ready() -> void:
	add_to_group("fixture")
	if collision_layer == 1:
		collision_layer = 1 | 16

## Attach a collision box plus optional visual parts in one call.
func setup_body(size: Vector3, parts: Array, offset := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = offset
	add_child(cs)
	var root := Node3D.new()
	root.name = "Mesh"
	add_child(root)
	for part in parts:
		root.add_child(Build.mi(part["mesh"], part["mat"],
			part.get("pos", Vector3.ZERO), part.get("rot", Vector3.ZERO), part.get("scl", Vector3.ONE)))

func room() -> Room:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null:
		return null
	return h.room(room_key)

func display_name() -> String:
	return fixture_name

func prompt(_player) -> Array:
	return [fixture_name, ""]

## Override. `held` is the prop in the player's hands, or null.
func interact(_player, _held) -> void:
	pass

## Return > 0 to require a hold-to-use with a progress bar.
func use_seconds(_player, _held) -> float:
	return 0.0

func emit_event(kind: String, visual := 0.0, tags: Array = [], cover := "", summary := "") -> WorldEvent:
	var e := WorldEvent.new(kind, "player").at(global_position, room_key).seen(visual)
	for t in tags:
		e.tag(String(t))
	if cover != "":
		e.cover(cover)
	if summary != "":
		e.says(summary)
	return e.emit()
