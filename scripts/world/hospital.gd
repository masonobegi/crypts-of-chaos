class_name Hospital
extends Node3D
## Procedurally assembles the whole floor from the LAYOUT table below, then
## bakes navigation over it. Adding a room is one entry plus a furniture recipe;
## nothing else in the game needs to know the floor plan changed.

const WALL_H := 3.2
const WALL_T := 0.16
const DOOR_W := 1.4

## Rect2(x, z, width, depth). North wing is z 4..13, corridor z 0..4,
## south wing z -10..0. Rooms tile exactly so no wall is ever built twice.
##
## The west annexe (x -16..0) is built on day one and SEALED behind roller
## shutters until the matching department is bought. Rooms you can see but not
## enter are worth far more than rooms that pop into existence when you can
## afford them: the shutters are visible from the corridor from the first shift,
## so the money has somewhere to be going long before there is any.
const LAYOUT := [
	{"key": "corridor", "display": "Ward C Corridor", "kind": "corridor",
		"rect": Rect2(-16, 0, 62, 4), "floor": 0},
	# ---- north wing: patient rooms
	{"key": "ward_101", "display": "Room 101", "kind": "ward", "rect": Rect2(0, 4, 9, 9), "door": 4.5},
	{"key": "ward_102", "display": "Room 102", "kind": "ward", "rect": Rect2(9, 4, 9, 9), "door": 13.5},
	{"key": "ward_103", "display": "Room 103", "kind": "ward", "rect": Rect2(18, 4, 10, 9), "door": 23.0},
	{"key": "ward_104", "display": "Room 104", "kind": "ward", "rect": Rect2(28, 4, 9, 9), "door": 32.5},
	{"key": "ward_105", "display": "Room 105", "kind": "ward", "rect": Rect2(37, 4, 9, 9), "door": 41.5},
	# ---- south wing: everything else
	{"key": "lobby", "display": "Lobby & Intake", "kind": "lobby",
		"rect": Rect2(0, -10, 11, 10), "door": 5.5, "door_w": 2.6},
	{"key": "station", "display": "Nurses' Station", "kind": "station",
		"rect": Rect2(11, -10, 8, 10), "door": 15.0, "door_w": 2.2},
	{"key": "treatment", "display": "Treatment Bay", "kind": "treatment",
		"rect": Rect2(19, -10, 10, 10), "door": 24.0, "door_w": 2.2},
	{"key": "supply", "display": "Supply Room", "kind": "supply", "rect": Rect2(29, -10, 6, 10), "door": 32.0},
	{"key": "bathroom", "display": "Staff WC", "kind": "bathroom", "rect": Rect2(35, -10, 5, 10), "door": 37.5},
	{"key": "office", "display": "Your Office", "kind": "office", "rect": Rect2(40, -10, 6, 10), "door": 43.0},
	# ---- west annexe: departments, shuttered until bought
	{"key": "intake", "display": "Emergency Intake", "kind": "intake",
		"rect": Rect2(-16, 4, 16, 9), "door": -8.0, "door_w": 2.6,
		"locked_by": "dept_emergency"},
	# Wide openings on purpose: the shutter IS the door, so no leaf is built.
	{"key": "radiology", "display": "Radiology", "kind": "radiology",
		"rect": Rect2(-16, -10, 8, 10), "door": -12.0, "door_w": 2.2,
		"locked_by": "dept_radiology"},
	{"key": "day_room", "display": "Psych Day Room", "kind": "day_room",
		"rect": Rect2(-8, -10, 8, 10), "door": -4.0, "door_w": 2.2,
		"locked_by": "dept_psych"},
]

var rooms: Dictionary = {}          ## key -> Room
var nav: NavGrid = null
var doors: Array = []
var shutters: Dictionary = {}       ## room key -> RollerShutter (open ones included)
var _room_list: Array[Room] = []

func _ready() -> void:
	add_to_group("hospital")

func build() -> void:
	nav = NavGrid.new(0.0)
	_build_rooms()
	_build_shell()
	_build_doors()
	_build_signage()
	# Furniture must exist before navigation is baked: NPCs were previously
	# pathing straight through desks, shelves and beds, and a nurse who spawned
	# behind the station counter never went anywhere again.
	var blocked := Furniture.furnish(self)
	_bake_nav(blocked)
	_build_shutters()
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.game_loaded.connect(refresh_departments)
	Log.i("hospital built: %d rooms, %d nav cells" % [rooms.size(), nav.cell_count()], "Hospital")

# ------------------------------------------------------------------ rooms
func _build_rooms() -> void:
	for entry in LAYOUT:
		var r := Room.new()
		r.key = String(entry["key"])
		r.display = String(entry["display"])
		r.kind = String(entry["kind"])
		r.rect = entry["rect"]
		r.name = r.key
		r.position = r.center()
		add_child(r)
		rooms[r.key] = r
		_room_list.append(r)
		_build_floor_and_ceiling(r)
		_build_room_lights(r)

func _build_floor_and_ceiling(r: Room) -> void:
	var size := Vector3(r.rect.size.x, 0.2, r.rect.size.y)
	var tint := _floor_colour(r.kind)
	var f := Build.wall(size, tint, Vector3(0, -0.1, 0))
	f.name = "Floor"
	r.add_child(f)
	# Ceiling is visual only — no collision, so thrown objects leave the room and
	# the player can never get stuck against it.
	var c := Build.box_mi(Vector3(r.rect.size.x, 0.1, r.rect.size.y), Build.CEILING,
		Vector3(0, WALL_H, 0))
	r.add_child(c)

func _floor_colour(kind: String) -> Color:
	match kind:
		"corridor": return Color(0.66, 0.69, 0.68)
		"ward": return Color(0.74, 0.76, 0.71)
		"lobby": return Color(0.60, 0.63, 0.66)
		"station": return Color(0.56, 0.62, 0.64)
		"treatment": return Color(0.68, 0.72, 0.75)
		"supply": return Color(0.58, 0.57, 0.54)
		"bathroom": return Color(0.72, 0.75, 0.78)
		"office": return Color(0.52, 0.45, 0.38)
		"intake": return Color(0.63, 0.60, 0.58)
		"radiology": return Color(0.50, 0.54, 0.60)
		"day_room": return Color(0.70, 0.66, 0.56)
	return Build.FLOOR_A

func _build_room_lights(r: Room) -> void:
	var cols := maxi(1, int(r.rect.size.x / 5.0))
	var rows := maxi(1, int(r.rect.size.y / 5.0))
	for i in cols:
		for j in rows:
			var x := r.rect.position.x + r.rect.size.x * (float(i) + 0.5) / float(cols)
			var z := r.rect.position.y + r.rect.size.y * (float(j) + 0.5) / float(rows)
			var lamp := Build.ceiling_light(
				Vector3(x, WALL_H - 0.25, z) - r.center(), 1.25, Color(1.0, 0.98, 0.92), 8.5)
			lamp.set_meta("is_light", true)
			r.add_child(lamp)

# ------------------------------------------------------------------ shell
func _build_shell() -> void:
	var north_gaps := _gaps_for(["intake",
		"ward_101", "ward_102", "ward_103", "ward_104", "ward_105"])
	var south_gaps := _gaps_for(["radiology", "day_room",
		"lobby", "station", "treatment", "supply", "bathroom", "office"])

	# Walls running along X.
	_wall_along_x(13.0, -16.0, 46.0, [])            # north exterior
	_wall_along_x(4.0, -16.0, 46.0, north_gaps)     # corridor <-> north wing
	_wall_along_x(0.0, -16.0, 46.0, south_gaps)     # corridor <-> south wing
	_wall_along_x(-10.0, -16.0, 46.0, [])           # south exterior

	# Walls running along Z.
	_wall_along_z(-16.0, -10.0, 13.0, [])           # west exterior
	_wall_along_z(46.0, -10.0, 13.0, [])            # east exterior
	# x = 0 was the west exterior before the annexe existed. It is now an
	# interior divider, and it must NOT cross the corridor band (z 0..4) or the
	# corridor is severed and the annexe is unreachable however many shutters
	# you open.
	_wall_along_z(0.0, 4.0, 13.0, [])               # intake <-> Room 101
	_wall_along_z(0.0, -10.0, 0.0, [])              # day room <-> lobby
	for x in [9.0, 18.0, 28.0, 37.0]:               # between patient rooms
		_wall_along_z(x, 4.0, 13.0, [])
	for x in [-8.0, 11.0, 19.0, 29.0, 35.0, 40.0]:  # between south rooms
		_wall_along_z(x, -10.0, 0.0, [])

func _gaps_for(keys: Array) -> Array:
	var out: Array = []
	for entry in LAYOUT:
		if not keys.has(String(entry["key"])):
			continue
		var centre := float(entry.get("door", 0.0))
		var w := float(entry.get("door_w", DOOR_W))
		out.append(Vector2(centre - w * 0.5, centre + w * 0.5))
	out.sort_custom(func(a, b): return a.x < b.x)
	return out

## Build a wall run with doorway gaps punched out of it.
func _wall_along_x(z: float, x0: float, x1: float, gaps: Array) -> void:
	var cursor := x0
	for g in gaps:
		var gap: Vector2 = g
		if gap.x > cursor:
			_wall_segment(Vector3(cursor, 0, z), Vector3(gap.x, 0, z))
		# Lintel above the doorway so you can't see over it and it reads as a door.
		_lintel(Vector3(gap.x, 0, z), Vector3(gap.y, 0, z))
		cursor = maxf(cursor, gap.y)
	if cursor < x1:
		_wall_segment(Vector3(cursor, 0, z), Vector3(x1, 0, z))

func _wall_along_z(x: float, z0: float, z1: float, gaps: Array) -> void:
	var cursor := z0
	for g in gaps:
		var gap: Vector2 = g
		if gap.x > cursor:
			_wall_segment(Vector3(x, 0, cursor), Vector3(x, 0, gap.x))
		_lintel(Vector3(x, 0, gap.x), Vector3(x, 0, gap.y))
		cursor = maxf(cursor, gap.y)
	if cursor < z1:
		_wall_segment(Vector3(x, 0, cursor), Vector3(x, 0, z1))

func _wall_segment(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(length, WALL_H, WALL_T) if horizontal else Vector3(WALL_T, WALL_H, length)
	# Two-tone walls: a scuffed dado below, institutional off-white above.
	var lower_h := 1.1
	var lower := Vector3(size.x, lower_h, size.z)
	var upper := Vector3(size.x, WALL_H - lower_h, size.z)
	add_child(Build.opaque_wall(lower, Build.WALL_LOWER, mid + Vector3(0, lower_h * 0.5, 0)))
	add_child(Build.opaque_wall(upper, Build.WALL_UPPER, mid + Vector3(0, lower_h + upper.y * 0.5, 0)))

func _lintel(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	var h := WALL_H - 2.1
	var size := Vector3(length, h, WALL_T) if horizontal else Vector3(WALL_T, h, length)
	add_child(Build.opaque_wall(size, Build.WALL_UPPER, mid + Vector3(0, 2.1 + h * 0.5, 0)))

# ------------------------------------------------------------------ doors
func _build_doors() -> void:
	for entry in LAYOUT:
		if not entry.has("door"):
			continue
		var key := String(entry["key"])
		var rect: Rect2 = entry["rect"]
		var w := float(entry.get("door_w", DOOR_W))
		var centre := float(entry["door"])
		var north := rect.position.y > 0.0
		var z := 4.0 if north else 0.0
		# The lobby and treatment bay have wide openings with no leaf — you need
		# to be able to shove a bed through them.
		if w > 2.0:
			continue
		var d := SwingDoor.new()
		d.room_key = key
		d.width = w
		d.build(Vector3(centre - w * 0.5, 0, z), Vector3(centre + w * 0.5, 0, z), not north)
		add_child(d)
		doors.append(d)

# ------------------------------------------------------------------ shutters
func _build_shutters() -> void:
	for entry in LAYOUT:
		if not entry.has("locked_by"):
			continue
		var key := String(entry["key"])
		var rect: Rect2 = entry["rect"]
		var w := float(entry.get("door_w", DOOR_W))
		var centre := float(entry["door"])
		var z := 4.0 if rect.position.y > 0.0 else 0.0
		var sh := RollerShutter.new()
		sh.name = "Shutter_" + key
		sh.room_key = key
		sh.upgrade_id = String(entry["locked_by"])
		add_child(sh)
		sh.build(Vector3(centre - w * 0.5, 0, z), Vector3(centre + w * 0.5, 0, z),
			String(entry["display"]))
		shutters[key] = sh
	refresh_departments()

func _on_upgrade_purchased(_id: String) -> void:
	refresh_departments()

## Bring the shutters into line with what has actually been bought. Called on
## build, on every purchase, and after a save is loaded — a career restored from
## disk must not find its paid-for departments still sealed.
func refresh_departments() -> void:
	for key in shutters:
		var sh: RollerShutter = shutters[key]
		if sh.is_open:
			continue
		if GameState.has_upgrade(sh.upgrade_id):
			sh.open(nav)
			EventBus.toast.emit("%s is open." % room(key).display, "good")
		else:
			sh.seal_nav(nav, _doorway_rect(key))

## Can anyone — player or NPC — currently get into this room?
func is_room_open(key: String) -> bool:
	var sh = shutters.get(key, null)
	return sh == null or sh.is_open

## Every room that is actually reachable right now. Anything picking a room at
## random must use this: a nurse who chooses a sealed department stands in the
## corridor waiting for a path that will never exist.
func open_room_keys() -> Array[String]:
	var out: Array[String] = []
	for r in _room_list:
		if is_room_open(r.key):
			out.append(r.key)
	return out

func _doorway_rect(key: String) -> Rect2:
	for entry in LAYOUT:
		if String(entry["key"]) != key:
			continue
		var rect: Rect2 = entry["rect"]
		var w := float(entry.get("door_w", DOOR_W))
		var centre := float(entry["door"])
		var z := 4.0 if rect.position.y > 0.0 else 0.0
		return Rect2(centre - w * 0.5, z - 1.1, w, 2.2)
	return Rect2()

# ------------------------------------------------------------------ signage
func _build_signage() -> void:
	for entry in LAYOUT:
		if String(entry["kind"]) == "corridor":
			continue
		var rect: Rect2 = entry["rect"]
		var centre := float(entry.get("door", rect.get_center().x))
		var north := rect.position.y > 0.0
		var z := (4.0 - 0.2) if north else (0.0 + 0.2)
		var sign := Build.label3d(String(entry["display"]), 0.085, Color(0.96, 0.97, 0.94), false)
		# Offset to the side of the doorway rather than over it, so the sign
		# reads as a door plate instead of a banner across the opening.
		var w := float(entry.get("door_w", DOOR_W))
		sign.position = Vector3(centre + w * 0.5 + 0.45, 2.05, z + (0.11 if not north else -0.11))
		sign.rotation.y = PI if north else 0.0
		add_child(sign)

# ------------------------------------------------------------------ nav
func _bake_nav(blocked: Array[Rect2] = []) -> void:
	for entry in LAYOUT:
		var r: Rect2 = entry["rect"]
		nav.add_area(r.grow(-0.55))
	# Bridge each doorway so paths flow between corridor and rooms.
	for entry in LAYOUT:
		if not entry.has("door"):
			continue
		var rect: Rect2 = entry["rect"]
		var w := float(entry.get("door_w", DOOR_W))
		var centre := float(entry["door"])
		var z := 4.0 if rect.position.y > 0.0 else 0.0
		nav.add_area(Rect2(centre - w * 0.35, z - 0.9, w * 0.7, 1.8))
	for f in blocked:
		nav.carve(f)
	nav.bake()

# ------------------------------------------------------------------ queries
func room_at(pos: Vector3) -> String:
	for r in _room_list:
		if r.contains(pos):
			return r.key
	return ""

func room(key: String) -> Room:
	return rooms.get(key, null)

func room_list() -> Array[Room]:
	return _room_list

func wards() -> Array[Room]:
	var out: Array[Room] = []
	for r in _room_list:
		if r.kind == "ward":
			out.append(r)
	return out

## A sensible spot inside a room to stand, walk to, or drop something.
func point_in(key: String, stream := "nav") -> Vector3:
	var r: Room = rooms.get(key, null)
	if r == null:
		return Vector3.ZERO
	return nav.random_point_in(r.rect.grow(-1.0), stream)

func bed_position(ward_key: String) -> Vector3:
	var r: Room = rooms.get(ward_key, null)
	if r == null:
		return Vector3.ZERO
	# Beds sit against the far (exterior) wall of each ward.
	return Vector3(r.rect.get_center().x - 1.4, 0.0, r.rect.position.y + r.rect.size.y - 2.6)

func to_dict() -> Dictionary:
	var d := {}
	for k in rooms:
		d[k] = (rooms[k] as Room).to_dict()
	return d

func from_dict(d: Dictionary) -> void:
	for k in d:
		var r: Room = rooms.get(k, null)
		if r:
			r.from_dict(d[k])
