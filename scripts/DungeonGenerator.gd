class_name DungeonGenerator

## Procedural dungeon generator using room placement + L-corridor connection

const TILE_WALL   := 0
const TILE_FLOOR  := 1
const TILE_STAIRS := 2

static func generate(width: int, height: int, floor_num: int) -> Dictionary:
	var dungeon: Array = []
	var rooms: Array  = []

	# Fill with walls
	for y in height:
		dungeon.append([])
		for _x in width:
			dungeon[y].append(TILE_WALL)

	# Room parameters scale slightly with floor
	var min_size := 4
	var max_size := 9
	var attempts := 25 + floor_num

	for _i in attempts:
		var rw := min_size + randi() % (max_size - min_size + 1)
		var rh := min_size + randi() % (max_size - min_size + 1)
		var rx := 1 + randi() % (width  - rw - 2)
		var ry := 1 + randi() % (height - rh - 2)

		var overlaps := false
		for room in rooms:
			if rx < room.x + room.w + 2 and rx + rw + 2 > room.x and \
			   ry < room.y + room.h + 2 and ry + rh + 2 > room.y:
				overlaps = true
				break

		if not overlaps:
			_carve_room(dungeon, rx, ry, rw, rh)
			rooms.append({
				"x": rx, "y": ry, "w": rw, "h": rh,
				"center": Vector2i(rx + rw / 2, ry + rh / 2),
				"cleared": false
			})

	# Connect rooms in order
	for i in range(1, rooms.size()):
		var a: Vector2i = rooms[i - 1].center
		var b: Vector2i = rooms[i].center
		if randi() % 2 == 0:
			_carve_h(dungeon, a.x, b.x, a.y)
			_carve_v(dungeon, a.y, b.y, b.x)
		else:
			_carve_v(dungeon, a.y, b.y, a.x)
			_carve_h(dungeon, a.x, b.x, b.y)

	# Place stairs in last room
	if rooms.size() > 0:
		var last := rooms[rooms.size() - 1]
		dungeon[last.center.y][last.center.x] = TILE_STAIRS

	var player_start := Vector2i(0, 0)
	if rooms.size() > 0:
		player_start = rooms[0].center

	return {
		"dungeon": dungeon,
		"rooms": rooms,
		"player_start": player_start,
		"width": width,
		"height": height
	}

static func _carve_room(dungeon: Array, rx: int, ry: int, rw: int, rh: int) -> void:
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			dungeon[y][x] = TILE_FLOOR

static func _carve_h(dungeon: Array, x1: int, x2: int, y: int) -> void:
	var h := dungeon.size()
	var w := dungeon[0].size() if h > 0 else 0
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if y >= 0 and y < h and x >= 0 and x < w:
			dungeon[y][x] = TILE_FLOOR

static func _carve_v(dungeon: Array, y1: int, y2: int, x: int) -> void:
	var h := dungeon.size()
	var w := dungeon[0].size() if h > 0 else 0
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if y >= 0 and y < h and x >= 0 and x < w:
			dungeon[y][x] = TILE_FLOOR
