class_name RollerShutter
extends Node3D
## A corrugated steel shutter sealing an unopened department.
##
## The annexe behind it is fully built, lit and furnished from the first shift.
## You can stand in the corridor and read the sign. What you cannot do is get
## in, and neither can anybody else — the panel blocks movement, blocks line of
## sight, and the doorway is cut out of the navigation graph, so nothing paths
## through a department the hospital has not bought.
##
## Wanting a room you can already see is a much better motivation than a menu
## entry, and it means the corridor tells the story of the career: how much of
## the west end is still shut is a running score you walk past every shift.

const HEIGHT := 2.1
const SLAT_H := 0.16

@export var room_key := ""
@export var upgrade_id := ""

var is_open := false

var _panel: StaticBody3D = null
var _mesh_root: Node3D = null
var _blocked_cells: Array[Vector2i] = []

## `a` and `b` are the two ends of the doorway, on the wall line.
func build(a: Vector3, b: Vector3, display: String) -> void:
	var w := a.distance_to(b)
	position = (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	if not horizontal:
		rotation.y = PI * 0.5

	_panel = Build.opaque_wall(Vector3(w, HEIGHT, 0.12), Color(0.52, 0.54, 0.57),
		Vector3(0, HEIGHT * 0.5, 0))
	add_child(_panel)

	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	# Corrugation. Purely so it reads as a shutter and not as a wall somebody
	# forgot to put a door in.
	var slats := int(HEIGHT / SLAT_H)
	for i in slats:
		var y := SLAT_H * (float(i) + 0.5)
		var shade := 0.10 if i % 2 == 0 else -0.04
		_mesh_root.add_child(Build.box_mi(Vector3(w - 0.06, SLAT_H * 0.8, 0.15),
			Color(0.52, 0.54, 0.57).lightened(maxf(0.0, shade)).darkened(maxf(0.0, -shade)),
			Vector3(0, y, 0)))
	# Both faces, so it reads from inside the sealed room too.
	for side in [-1.0, 1.0]:
		var sign_node := Build.label3d("%s\nCLOSED" % display.to_upper(), 0.1,
			Color(0.95, 0.86, 0.42), false)
		sign_node.position = Vector3(0, 1.45, 0.09 * side)
		sign_node.rotation.y = 0.0 if side > 0.0 else PI
		_mesh_root.add_child(sign_node)
		var strip := Build.box_mi(Vector3(w - 0.4, 0.5, 0.02), Color(0.20, 0.22, 0.24),
			Vector3(0, 1.45, 0.075 * side))
		_mesh_root.add_child(strip)

## Cut the doorway out of the navigation graph. Must be called after the graph
## is baked, and the rect is in world XZ.
func seal_nav(nav: NavGrid, doorway: Rect2) -> void:
	if is_open:
		return
	_blocked_cells = nav.block_area(doorway)

## Roll it up. One-way — a department, once bought, stays bought.
func open(nav: NavGrid) -> void:
	if is_open:
		return
	is_open = true
	if nav != null and not _blocked_cells.is_empty():
		nav.unblock_cells(_blocked_cells)
		_blocked_cells = []
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	if _mesh_root != null and is_instance_valid(_mesh_root):
		_mesh_root.queue_free()
		_mesh_root = null
