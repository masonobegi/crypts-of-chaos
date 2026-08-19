class_name ObstructionMonitor
extends Node
## Watches for heavy things left in doorways and takes those cells out of the
## navigation graph.
##
## This is what turns "shove the cart into the doorway" from a visual gag into a
## tactic: staff genuinely cannot path through a blocked door, so a cart in the
## right place buys you a private ward. It also means you can trap yourself, and
## trap a nurse, which is funnier.

const CHECK_INTERVAL := 0.5
const HEAVY_MASS := 8.0
const DOOR_HALF_WIDTH := 0.9
const DOOR_HALF_DEPTH := 0.7

var hospital: Hospital = null
var _accum := 0.0
## door key -> {cells, prop}
var _blocked: Dictionary = {}
var _door_rects: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("obstruction")
	hospital = get_tree().get_first_node_in_group("hospital")
	_collect_doorways()

func _collect_doorways() -> void:
	if hospital == null:
		return
	for entry in Hospital.LAYOUT:
		if not entry.has("door"):
			continue
		var rect: Rect2 = entry["rect"]
		var centre := float(entry["door"])
		var z := 4.0 if rect.position.y > 0.0 else 0.0
		_door_rects.append({
			"key": String(entry["key"]),
			"rect": Rect2(centre - DOOR_HALF_WIDTH, z - DOOR_HALF_DEPTH,
				DOOR_HALF_WIDTH * 2.0, DOOR_HALF_DEPTH * 2.0),
		})

func _process(delta: float) -> void:
	if hospital == null or hospital.nav == null:
		return
	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0
	for d in _door_rects:
		_check_doorway(d)

func _check_doorway(d: Dictionary) -> void:
	var key: String = String(d["key"])
	var rect: Rect2 = d["rect"]
	var blocker := _blocker_in(rect)
	var was_blocked: bool = _blocked.has(key)

	if blocker != null and not was_blocked:
		var cells := hospital.nav.block_area(rect)
		_blocked[key] = {"cells": cells, "prop": blocker}
		AudioMgr.play_at_var("squeak", blocker.global_position, -20.0)
		# Blocking a doorway is visible and slightly odd, but it is not evidence
		# of fraud — it is the cost of the tactic, not a crime in itself.
		WorldEvent.new("doorway_blocked", "player") \
			.at(blocker.global_position, key).seen(0.12) \
			.tag("obstruction").cover("facilities") \
			.says("left %s across a doorway" % blocker.display_name()).emit()
	elif blocker == null and was_blocked:
		var stored: Dictionary = _blocked[key]
		hospital.nav.unblock_cells(stored["cells"])
		_blocked.erase(key)

## Only genuinely heavy things block a door; you cannot barricade a ward with a
## clipboard.
func _blocker_in(rect: Rect2) -> Node3D:
	for p in get_tree().get_nodes_in_group("prop"):
		if not (p is RigidBody3D):
			continue
		var rb: RigidBody3D = p
		if rb.mass < HEAVY_MASS:
			continue
		if rb.linear_velocity.length() > 0.6:
			continue      # still moving; not settled yet
		var pos := rb.global_position
		if rect.has_point(Vector2(pos.x, pos.z)):
			return rb
	for b in get_tree().get_nodes_in_group("bed"):
		var pos: Vector3 = b.global_position
		if rect.has_point(Vector2(pos.x, pos.z)):
			return b
	return null

func blocked_doorways() -> Array[String]:
	var out: Array[String] = []
	for k in _blocked:
		out.append(String(k))
	return out
