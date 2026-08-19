class_name NavGrid
extends RefCounted
## Deterministic grid navigation over the hospital floor.
##
## A custom A* grid is used instead of a baked NavigationMesh on purpose: the
## whole floor is generated procedurally, the tests run headless with no
## rendering server doing geometry parsing, and NPC routing needs to be
## reproducible from a seed so a funny shift can be replayed.

const CELL := 0.75

var astar := AStar3D.new()
var _ids: Dictionary = {}          ## Vector2i -> int
var _walkable: Dictionary = {}     ## Vector2i -> true
var _blocked: Dictionary = {}      ## Vector2i -> blocker count (props, spills)
var _y := 0.0

func _init(y_level: float = 0.0) -> void:
	_y = y_level

func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL)), int(floor(pos.z / CELL)))

func cell_center(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) + 0.5) * CELL, _y, (float(c.y) + 0.5) * CELL)

## Mark every cell whose centre falls inside `r` (an XZ rect) as walkable.
func add_area(r: Rect2) -> void:
	var x0 := int(floor(r.position.x / CELL))
	var x1 := int(ceil(r.end.x / CELL))
	var z0 := int(floor(r.position.y / CELL))
	var z1 := int(ceil(r.end.y / CELL))
	for x in range(x0, x1):
		for z in range(z0, z1):
			var c := Vector2i(x, z)
			var centre := cell_center(c)
			if r.has_point(Vector2(centre.x, centre.z)):
				_walkable[c] = true

## Build the A* graph. Call once after all areas are added.
func bake() -> void:
	astar.clear()
	_ids.clear()
	var next := 0
	for c in _walkable:
		_ids[c] = next
		astar.add_point(next, cell_center(c))
		next += 1
	for c in _walkable:
		var id: int = _ids[c]
		# 4-connectivity plus diagonals, but a diagonal is only valid when both
		# of its orthogonal neighbours are open — NPCs must not clip corners
		# through door frames.
		var orth: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
		for d in orth:
			var n: Vector2i = c + d
			if _ids.has(n):
				astar.connect_points(id, _ids[n], true)
		var diag: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1)]
		for d in diag:
			var n: Vector2i = c + d
			if not _ids.has(n):
				continue
			if _ids.has(Vector2i(c.x + d.x, c.y)) and _ids.has(Vector2i(c.x, c.y + d.y)):
				astar.connect_points(id, _ids[n], true)
	Log.i("nav baked: %d cells" % _ids.size(), "Nav")

func is_walkable(pos: Vector3) -> bool:
	return _ids.has(cell_of(pos))

func nearest_cell(pos: Vector3) -> Vector2i:
	var c := cell_of(pos)
	if _ids.has(c) and not _blocked.has(c):
		return c
	# Spiral outward for the closest open cell — used when something spawns or
	# gets shoved into geometry.
	for radius in range(1, 14):
		var best := Vector2i(-99999, -99999)
		var best_d := INF
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var n := c + Vector2i(dx, dz)
				if not _ids.has(n) or _blocked.has(n):
					continue
				var d := cell_center(n).distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = n
		if best.x != -99999:
			return best
	return c

func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_cell(from)
	var b := nearest_cell(to)
	if not _ids.has(a) or not _ids.has(b):
		return PackedVector3Array()
	var raw := astar.get_point_path(_ids[a], _ids[b])
	return _smooth(raw)

## Drop waypoints that lie on a straight run — NPCs should walk corridors in a
## line rather than shuffling cell to cell.
func _smooth(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() <= 2:
		return path
	var out := PackedVector3Array()
	out.append(path[0])
	for i in range(1, path.size() - 1):
		var prev: Vector3 = out[out.size() - 1]
		var cur: Vector3 = path[i]
		var next: Vector3 = path[i + 1]
		var d1 := (cur - prev).normalized()
		var d2 := (next - cur).normalized()
		if d1.dot(d2) < 0.999:
			out.append(cur)
	out.append(path[path.size() - 1])
	return out

## Temporarily block cells — a toppled cart genuinely reroutes staff, which is
## the whole reason toppling a cart is a strategy.
func block_area(r: Rect2) -> Array[Vector2i]:
	var affected: Array[Vector2i] = []
	for c in _ids:
		var centre := cell_center(c)
		if r.has_point(Vector2(centre.x, centre.z)):
			_blocked[c] = int(_blocked.get(c, 0)) + 1
			affected.append(c)
			astar.set_point_disabled(_ids[c], true)
	return affected

func unblock_cells(cells: Array[Vector2i]) -> void:
	for c in cells:
		var n := int(_blocked.get(c, 0)) - 1
		if n <= 0:
			_blocked.erase(c)
			if _ids.has(c):
				astar.set_point_disabled(_ids[c], false)
		else:
			_blocked[c] = n

func random_point_in(r: Rect2, stream := "nav") -> Vector3:
	var candidates: Array[Vector3] = []
	for c in _ids:
		if _blocked.has(c):
			continue
		var centre := cell_center(c)
		if r.has_point(Vector2(centre.x, centre.z)):
			candidates.append(centre)
	if candidates.is_empty():
		return Vector3(r.get_center().x, _y, r.get_center().y)
	return RNG.pick(stream, candidates)

func cell_count() -> int:
	return _ids.size()
