class_name Hospital
extends Node3D
## Procedurally assembles the whole floor from the LAYOUT table below, then
## bakes navigation over it. Adding a room is one entry plus a furniture recipe;
## nothing else in the game needs to know the floor plan changed.

const WALL_H := 3.2
const WALL_T := 0.16
const DOOR_W := 1.4

## How many beds stand in the ward. Cases numbers its five people 1..5 and this
## is the other half of that agreement.
const BEDS := 5

## Rect2(x, z, width, depth). The ward is z 4..13, the corridor z 0..4, the
## station and the office z -8..0. Rooms tile exactly so no wall is ever built
## twice.
##
## Four rooms, and that is the whole hospital. There used to be eleven — a
## lobby, a treatment bay, a supply room, a staff WC and a west annexe of
## departments behind roller shutters you bought your way through. All of it
## served systems that no longer exist, and a building whose far end you never
## walk to is worse than a small building. What is left is the four places the
## day is actually made of: the ward you round on, the station the nurse watches
## it from, the office with a door you can shut, and the corridor between them.
const LAYOUT := [
	{"key": "corridor", "display": "Ward C Corridor", "kind": "corridor",
		"rect": Rect2(0, 0, 20, 4), "floor": 0},
	# The five-bed bay. One room, one door, and everyone in it can see the door.
	{"key": "ward", "display": "Ward C", "kind": "ward",
		"rect": Rect2(0, 4, 20, 9), "door": 10.0, "door_w": 1.6},
	# Deliberately a wide opening with no leaf: the station's whole job is that
	# somebody sitting in it can see who walks past.
	{"key": "station", "display": "Nurses' Station", "kind": "station",
		"rect": Rect2(0, -8, 12, 8), "door": 5.5, "door_w": 2.2},
	{"key": "office", "display": "Your Office", "kind": "office",
		"rect": Rect2(12, -8, 8, 8), "door": 16.0},
]

var rooms: Dictionary = {}          ## key -> Room
var nav: NavGrid = null
var doors: Array = []
## The five PatientBeds, in bed order, filled in by Furniture as it places them.
var beds: Array = []
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
	# No outline on floors, ceilings or wall runs: they are the biggest surfaces
	# on screen, a room already has an edge where its own walls meet, and the
	# outline pass draws every one of them a second time at full screen size.
	var f := Build.wall(size, tint, Vector3(0, -0.1, 0), 0.0, 0.0)
	f.name = "Floor"
	r.add_child(f)
	# Ceiling is visual only — no collision, so thrown objects leave the room and
	# the player can never get stuck against it.
	var c := Build.box_mi(Vector3(r.rect.size.x, 0.1, r.rect.size.y), Build.CEILING,
		Vector3(0, WALL_H, 0), 0.85, 0.0)
	# Tagged, because "the only bare MeshInstance3D parented to a Room" stopped
	# being a safe way to find a ceiling the moment floor borders were added.
	c.set_meta("is_ceiling", true)
	r.add_child(c)
	_ceiling_grid(r)

	# An inlaid border a foot in from the walls, in a darker shade of the room's
	# own floor. Four thin strips per room, and it is the difference between a
	# floor and a coloured plane: a border tells you where the room ENDS, gives
	# the eye a scale to measure the space against, and makes the middle of the
	# room read as somewhere deliberately left clear rather than as somewhere
	# nothing was put.
	var band := tint.darkened(0.34)
	var inset := 0.45
	var w: float = r.rect.size.x - inset * 2.0
	var d: float = r.rect.size.y - inset * 2.0
	if w > 1.0 and d > 1.0:
		for edge in [Vector3(0, 0, -d * 0.5), Vector3(0, 0, d * 0.5)]:
			r.add_child(Build.box_mi(Vector3(w, 0.014, 0.09), band,
				edge + Vector3(0, 0.008, 0), 0.6, 0.0))
		for edge2 in [Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0)]:
			r.add_child(Build.box_mi(Vector3(0.09, 0.014, d), band,
				edge2 + Vector3(0, 0.008, 0), 0.6, 0.0))
	_floor_seams(r, tint, inset)

## WELDED SEAMS, every two metres.
##
## The floor is the biggest thing in almost every frame of this game — a
## twenty-metre ward seen from the door is more floor than anything else — and
## it was one flat colour from wall to wall with a border round it. Nothing at
## all between the border and the far side, so the middle of every room read as
## a coloured plane rather than as a surface, and there was no way to judge how
## far away anything was standing on it.
##
## Hospital vinyl comes in two-metre sheets welded together, so this is what is
## actually there: a line every two metres, barely darker than the floor, in
## the long direction only. It is the cheapest possible depth cue and it costs
## about ten thin boxes a room.
static func _floor_seams(r: Room, tint: Color, inset: float) -> void:
	var seam := tint.darkened(0.13)
	var w: float = r.rect.size.x - inset * 2.0
	var d: float = r.rect.size.y - inset * 2.0
	if w <= 1.0 or d <= 1.0:
		return
	# Across the SHORT axis, so the lines run the length of the room the way a
	# sheet is laid — down a corridor rather than across it.
	if r.rect.size.x >= r.rect.size.y:
		var n := int(w / 2.0)
		for i in range(1, n):
			var x: float = -w * 0.5 + float(i) * (w / float(n))
			r.add_child(Build.box_mi(Vector3(0.022, 0.012, d), seam,
				Vector3(x, 0.007, 0), 0.7, 0.0))
	else:
		var n2 := int(d / 2.0)
		for i in range(1, n2):
			var z: float = -d * 0.5 + float(i) * (d / float(n2))
			r.add_child(Build.box_mi(Vector3(w, 0.012, 0.022), seam,
				Vector3(0, 0.007, z), 0.7, 0.0))

## SUSPENDED TILE, on a grid.
##
## Same problem as the floor and worth fixing for the same reason: the player
## stands at 1.7m in a 3m room, so the ceiling is the top third of most frames
## and it was one unbroken white plane with two light fittings in it. A room
## with a flat ceiling reads as a box with a lid; a room with a tile grid reads
## as a building, and it is the same trick — the eye gets something to measure
## the span against.
##
## 1.2m rather than the 600mm a real ceiling uses: at twenty metres that is
## sixteen lines instead of thirty-three, and at the angle anybody actually
## sees it the finer grid is noise.
static func _ceiling_grid(r: Room) -> void:
	var line := Build.CEILING.darkened(0.10)
	var w: float = r.rect.size.x
	var d: float = r.rect.size.y
	var y: float = WALL_H - 0.052
	var step := 1.2
	var nx := int(w / step)
	for i in range(1, nx):
		var x: float = -w * 0.5 + float(i) * (w / float(nx))
		r.add_child(Build.box_mi(Vector3(0.022, 0.012, d), line,
			Vector3(x, y, 0), 0.9, 0.0))
	var nz := int(d / step)
	for i in range(1, nz):
		var z: float = -d * 0.5 + float(i) * (d / float(nz))
		r.add_child(Build.box_mi(Vector3(w, 0.012, 0.022), line,
			Vector3(0, y, z), 0.9, 0.0))

## A different, bright floor per room kind. These are how you know which room
## you are in from the doorway, so they are proper colours rather than eleven
## shades of the same grey — which is what they were, and it is why the whole
## floor plan read as one continuous corridor.
##
## Every one of these was chosen against a flat grey scene and then the lighting
## was raised to make the building bright — so by the time there was an ambient
## term, a key, a fill and a ceiling lamp every five metres, a ward floor at
## 0.74 was clipping to white and everything standing on it lost its footing.
## Floors are the largest surface in shot and they should be the DARKEST of the
## three planes, not the brightest: props read against them, characters cast
## onto them, and the walls above them get to be the bright thing.
func _floor_colour(kind: String) -> Color:
	match kind:
		"corridor": return Color(0.52, 0.62, 0.68)
		"ward": return Color(0.56, 0.66, 0.57)
		"station": return Color(0.44, 0.60, 0.68)
		"office": return Color(0.56, 0.41, 0.31)
	return Build.FLOOR_A

func _build_room_lights(r: Room) -> void:
	var cols := maxi(1, int(r.rect.size.x / 5.0))
	var rows := maxi(1, int(r.rect.size.y / 5.0))
	for i in cols:
		for j in rows:
			var x := r.rect.position.x + r.rect.size.x * (float(i) + 0.5) / float(cols)
			var z := r.rect.position.y + r.rect.size.y * (float(j) + 0.5) / float(rows)
			var lamp := Build.ceiling_light(
				Vector3(x, WALL_H - 0.25, z) - r.center(), 0.82, Color(1.0, 0.97, 0.90), 8.5)
			lamp.set_meta("is_light", true)
			r.add_child(lamp)

## Re-tint every ceiling lamp in the building. Called when the day starts, so
## the same corridor is a different place at eight in the evening than it is at
## eight in the morning.
func set_lamp_look(colour: Color, energy: float) -> void:
	for r in _room_list:
		for c in r.get_children():
			if not (c is Node3D) or not c.has_meta("is_light"):
				continue
			for l in (c as Node3D).get_children():
				if l is OmniLight3D:
					(l as OmniLight3D).light_color = colour
					(l as OmniLight3D).light_energy = energy
				elif l is MeshInstance3D:
					# The visible fitting matches the light coming out of it.
					var m := (l as MeshInstance3D).material_override as StandardMaterial3D
					if m != null:
						(l as MeshInstance3D).material_override = Build.unshaded(colour)

# ------------------------------------------------------------------ shell
func _build_shell() -> void:
	var north_gaps := _gaps_for(["ward"])
	var south_gaps := _gaps_for(["station", "office"])

	# Walls running along X.
	_wall_along_x(13.0, 0.0, 20.0, [])             # north exterior
	_wall_along_x(4.0, 0.0, 20.0, north_gaps)      # corridor <-> ward
	_wall_along_x(0.0, 0.0, 20.0, south_gaps)      # corridor <-> station, office
	_wall_along_x(-8.0, 0.0, 20.0, [])             # south exterior

	# Walls running along Z.
	_wall_along_z(0.0, -8.0, 13.0, [])             # west exterior
	_wall_along_z(20.0, -8.0, 13.0, [])            # east exterior
	# The one interior divider left. It must NOT cross the corridor band
	# (z 0..4), or the corridor is severed and half the building is unreachable.
	_wall_along_z(12.0, -8.0, 0.0, [])             # station <-> office

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
	add_child(Build.opaque_wall(lower, Build.WALL_LOWER, mid + Vector3(0, lower_h * 0.5, 0), 0.0, 0.0))
	add_child(Build.opaque_wall(upper, Build.WALL_UPPER, mid + Vector3(0, lower_h + upper.y * 0.5, 0), 0.0, 0.0))

	# A skirting board and a dado rail, both proud of the wall by three
	# centimetres and both outlined.
	#
	# Cheap, and out of all proportion to what they cost. A flat two-tone wall
	# is a gradient with a line across it; the same wall with a rail on the seam
	# and a skirting at the floor has EDGES, and edges are what the eye uses to
	# decide whether a room was built or generated. They also stop the floor and
	# the wall meeting in a single ambiguous corner, which was most of why the
	# rooms read as empty boxes.
	var out := Vector3(0.0, 0.0, WALL_T * 0.45) if horizontal else Vector3(WALL_T * 0.45, 0.0, 0.0)
	var rail_len := Vector3(size.x, 0.075, WALL_T * 0.55) if horizontal \
		else Vector3(WALL_T * 0.55, 0.075, size.z)
	var skirt_len := Vector3(size.x, 0.16, WALL_T * 0.7) if horizontal \
		else Vector3(WALL_T * 0.7, 0.16, size.z)
	# The rail is PALE and the skirting is DARK, which is the wrong way round
	# from how it was first written and the reason none of it showed: a dark
	# teal skirting under a teal dado is the same wall with a slightly different
	# teal at the bottom. What reads is contrast against what it sits on.
	# ...and a picture rail near the top, and a cornice on the ceiling line.
	#
	# Same argument, applied to the other end of the wall. The dado fixed the
	# bottom two-fifths and left the upper three-fifths as an unbroken cream
	# plane running the length of the building — which is most of the remaining
	# "it looks bare" in an interior shot, because it is the surface directly
	# behind everybody's head.
	var picture_len := Vector3(size.x, 0.05, WALL_T * 0.5) if horizontal \
		else Vector3(WALL_T * 0.5, 0.05, size.z)
	var cornice_len := Vector3(size.x, 0.13, WALL_T * 0.8) if horizontal \
		else Vector3(WALL_T * 0.8, 0.13, size.z)
	for side in [1.0, -1.0]:
		add_child(Build.box_mi(rail_len, Color(0.95, 0.93, 0.86),
			mid + out * side + Vector3(0, lower_h, 0), 0.55))
		add_child(Build.box_mi(skirt_len, Color(0.17, 0.22, 0.27),
			mid + out * side + Vector3(0, 0.08, 0), 0.6))
		add_child(Build.box_mi(picture_len, Color(0.80, 0.78, 0.70),
			mid + out * side + Vector3(0, WALL_H - 0.62, 0), 0.6))
		add_child(Build.box_mi(cornice_len, Color(0.97, 0.96, 0.93),
			mid + out * side + Vector3(0, WALL_H - 0.07, 0), 0.5))

func _lintel(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	var h := WALL_H - 2.1
	var size := Vector3(length, h, WALL_T) if horizontal else Vector3(WALL_T, h, length)
	add_child(Build.opaque_wall(size, Build.WALL_UPPER, mid + Vector3(0, 2.1 + h * 0.5, 0), 0.0, 0.0))

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
		# The station has a wide opening with no leaf. It is the one room whose
		# whole point is that you can be seen from it.
		if w > 2.0:
			continue
		var d := SwingDoor.new()
		d.room_key = key
		d.width = w
		d.build(Vector3(centre - w * 0.5, 0, z), Vector3(centre + w * 0.5, 0, z), not north)
		add_child(d)
		doors.append(d)

# ------------------------------------------------------------------ signage
func _build_signage() -> void:
	## One sign per door, not three.
	##
	## Every room used to get a name plate on the wall, a number flag projecting
	## into the corridor AND (for wards) a door card — three labels within a
	## metre of each other, all saying the same number, and at any distance the
	## three overlapped into an unreadable stack. The playtest note was
	## "signage is still bad" and it was right.
	##
	## The ward door cards went with the five separate patient rooms: there is
	## one ward now, and who is in it is a question you answer by walking in.
	## Every door gets ONE projecting flag, because these are destinations you
	## navigate towards rather than doors you check.
	for entry in LAYOUT:
		if String(entry["kind"]) == "corridor":
			continue
		var rect: Rect2 = entry["rect"]
		var centre := float(entry.get("door", rect.get_center().x))
		var north := rect.position.y > 0.0
		var z := (4.0 - 0.2) if north else (0.0 + 0.2)
		var w := float(entry.get("door_w", DOOR_W))

		# A flag projecting into the corridor at right angles to the wall. Two
		# labels back to back, each showing only its front face: a single
		# double-sided Label3D is legible walking one way and MIRRORED walking
		# the other, and the first screenshot of this read "ǝʞɐʇnI ⅋ ʎqqo˥".
		var short := String(entry["display"])
		var plate_w := float(short.length()) * 0.105 * 0.62 + 0.14
		var plate := Build.box_mi(Vector3(0.04, 0.21, plate_w),
			Color(0.14, 0.20, 0.26), Vector3.ZERO)
		plate.position = Vector3(centre + w * 0.5 + 0.30, 2.46,
			z + (0.28 if not north else -0.28))
		add_child(plate)
		# A stub back to the wall, so the plate is mounted rather than hovering.
		var arm := Build.box_mi(Vector3(0.035, 0.04, 0.28),
			Color(0.14, 0.20, 0.26), Vector3.ZERO)
		arm.position = Vector3(centre + w * 0.5 + 0.30, 2.46,
			z + (0.15 if not north else -0.15))
		add_child(arm)
		for face in [0.0, PI]:
			var flag := Build.label3d(short, 0.105, Color(0.93, 0.96, 0.98), false)
			flag.double_sided = false
			# Each face sits proud of its own side of the plate. Centred, both
			# labels are buried inside the box and the corridor loses its signs.
			var side := 0.032 if is_zero_approx(face) else -0.032
			flag.position = Vector3(centre + w * 0.5 + 0.30 + side, 2.46,
				z + (0.28 if not north else -0.28))
			flag.rotation.y = PI * 0.5 + face
			add_child(flag)

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
		# ...and mark it as a place a route must be steered THROUGH.
		nav.add_pinch(Vector3(centre, 0.0, z))
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
## The doorway of a room, at head height, for pointing at from a corridor.
##
## `point_in` returns a random floor tile, which is a fine place to send a nurse
## and a poor place to put a marker: from the corridor it reads as a chevron
## halfway up a wall, and it moves every time it is asked.
func door_point(key: String) -> Vector3:
	for entry in LAYOUT:
		if String(entry["key"]) != key or not entry.has("door"):
			continue
		var rect: Rect2 = entry["rect"]
		var north: bool = rect.position.y > 0.0
		var z := 4.0 if north else 0.0
		return Vector3(float(entry["door"]), 1.7, z)
	var r: Room = rooms.get(key, null)
	if r == null:
		push_error("door_point: no room named '%s'" % key)
		return Vector3.ZERO
	return Vector3(r.rect.get_center().x, 1.7, r.rect.get_center().y)

func point_in(key: String, stream := "nav") -> Vector3:
	var r: Room = rooms.get(key, null)
	if r == null:
		# Silently returning the origin is how a nurse ended up patrolling to
		# the corner of the building for a room that had been demolished.
		push_error("point_in: no room named '%s'" % key)
		return Vector3.ZERO
	return nav.random_point_in(r.rect.grow(-1.0), stream)

## Where the day starts. Authored so the first frame of a run is composed rather
## than rolled — see the note at Game._spawn_player. The corridor, a few metres
## east of the ward door, facing the length of the building: you arrive at eight
## in the morning outside the room you are responsible for.
##
## This was lobby_spawn() until the lobby was demolished with the rest of the
## departments.
func spawn_point() -> Vector3:
	var r: Room = rooms.get("corridor", null)
	if r == null:
		return Vector3.ZERO
	return Vector3(r.rect.position.x + 14.0, 0.0, r.rect.position.y + 2.0)

## Where bed `index` (1..BEDS) stands: down the ward's far wall, head to the
## plaster, foot toward the door, evenly spaced across the bay.
func bed_position(index: int) -> Vector3:
	var r: Room = rooms.get("ward", null)
	if r == null:
		return Vector3.ZERO
	var i := clampi(index - 1, 0, BEDS - 1)
	var x: float = r.rect.position.x + r.rect.size.x * (float(i) + 0.5) / float(BEDS)
	return Vector3(x, 0.0, r.rect.position.y + r.rect.size.y - 1.35)

## The bed itself, or null before Furniture has run.
func bed(index: int) -> PatientBed:
	var i := index - 1
	if i < 0 or i >= beds.size():
		return null
	return beds[i]

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
