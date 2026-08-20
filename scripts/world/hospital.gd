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
	refresh_fittings()
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.game_loaded.connect(refresh_departments)
	EventBus.game_loaded.connect(refresh_fittings)
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
	r.add_child(c)

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

## A different, bright floor per room kind. These are how you know which room
## you are in from the doorway, so they are proper colours rather than eleven
## shades of the same grey — which is what they were, and it is why the whole
## floor plan read as one continuous corridor.
## Roughly a fifth darker than the first pass across the board.
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
		"lobby": return Color(0.62, 0.56, 0.45)
		"station": return Color(0.44, 0.60, 0.68)
		"treatment": return Color(0.48, 0.62, 0.72)
		"supply": return Color(0.58, 0.52, 0.42)
		"bathroom": return Color(0.54, 0.66, 0.74)
		"office": return Color(0.56, 0.41, 0.31)
		"intake": return Color(0.70, 0.56, 0.46)
		"radiology": return Color(0.45, 0.53, 0.70)
		"day_room": return Color(0.66, 0.58, 0.38)
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

## Re-tint every ceiling lamp in the building. Called when a shift starts, so
## the same corridor is a different place at midnight than it is at nine.
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
	for side in [1.0, -1.0]:
		add_child(Build.box_mi(rail_len, Color(0.95, 0.93, 0.86),
			mid + out * side + Vector3(0, lower_h, 0), 0.55))
		add_child(Build.box_mi(skirt_len, Color(0.17, 0.22, 0.27),
			mid + out * side + Vector3(0, 0.08, 0), 0.6))

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
	refresh_fittings()

# ------------------------------------------------------------------ fittings
## What the money BOUGHT, standing in the building.
##
## Eighteen upgrades, and the only one of them you could see was a department
## shutter rolling up. Everything else — cameras watching the corridor, curtains
## round every bed, the confidential-waste bin, a seat on the board — was a
## boolean read by a system and never by the player, so a career's worth of
## reinvestment left the ward looking exactly as it did on the first morning.
## Half of these change how you have to play; you should be able to walk down
## the corridor and see which half you bought.
##
## Rebuilt wholesale rather than diffed: it runs on build, on purchase and on
## load, and a career restored from disk must find its fittings there.
var _fittings: Node3D = null

func refresh_fittings() -> void:
	if _fittings != null and is_instance_valid(_fittings):
		# remove_child BEFORE freeing. queue_free() is deferred, so the old node
		# is still a child holding the name "Fittings" when the new one is added
		# — Godot renames the newcomer to "Fittings2", get_node("Fittings")
		# returns the corpse, and every refresh quietly adds another whole set of
		# cameras and curtains on top of the last.
		remove_child(_fittings)
		_fittings.queue_free()
	_fittings = Node3D.new()
	_fittings.name = "Fittings"
	add_child(_fittings)

	if GameState.has_upgrade("security_cameras"):
		_fit_cameras()
	if GameState.has_upgrade("private_rooms"):
		_fit_curtains()
	if GameState.has_upgrade("better_beds"):
		_fit_bed_rails()
	if GameState.has_upgrade("shred_bin"):
		_fit_shred_bin()
	if GameState.has_upgrade("vip_suite"):
		_fit_vip()
	if GameState.has_upgrade("board_appointment") or GameState.has_upgrade("legal_retainer"):
		_fit_office_wall()
	if GameState.has_upgrade("coffee_machine"):
		_fit_coffee()

## One per covered room, mounted high and angled down the corridor. The lens is
## unshaded red so it reads from the far end — which is the point, because
## camera_rooms() is a list of places it is now a much worse idea to be seen in.
func _fit_cameras() -> void:
	var mounts := {
		# Picked to sit BETWEEN the ward door signs rather than on top of them —
		# the doors are at 4.5, 13.5, 23, 32.5 and 41.5, and each carries a flag
		# sign at door + half a doorway + 0.28.
		"corridor": [Vector3(9.5, 2.72, 3.66), Vector3(19.5, 2.72, 3.66),
			Vector3(29.0, 2.72, 3.66), Vector3(-6.0, 2.72, 3.66)],
		"lobby": [Vector3(9.9, 2.72, -1.4)],
	}
	for key in mounts:
		if not Upgrades.camera_rooms().has(key):
			continue
		for pos in mounts[key]:
			var body := Build.box_mi(Vector3(0.34, 0.24, 0.46), Color(0.93, 0.94, 0.96), pos)
			_fittings.add_child(body)
			var arm := Build.box_mi(Vector3(0.07, 0.36, 0.07),
				Color(0.50, 0.53, 0.58), pos + Vector3(0, 0.28, 0.18))
			_fittings.add_child(arm)
			var lens := Build.cyl_mi(0.085, 0.14, Color(0.10, 0.11, 0.13),
				pos + Vector3(0, -0.04, -0.28))
			lens.rotation.x = PI * 0.5
			_fittings.add_child(lens)
			var led := Build.mi(Build.sphere_mesh(0.035),
				Build.unshaded(Color(1.0, 0.20, 0.22)), pos + Vector3(0.12, 0.08, -0.23))
			_fittings.add_child(led)

## A rail and a drawn-back curtain beside every bed. Private rooms are the
## single biggest reduction in witnesses in the game; this is what that bought.
func _fit_curtains() -> void:
	for r in wards():
		var b := bed_position(r.key)
		# The rail runs along the bed, which lies along X — a cylinder stands up
		# by default, so it is rotation.z that lays it down the right way.
		var rail := Build.cyl_mi(0.028, 3.0, Color(0.80, 0.82, 0.86),
			b + Vector3(0.1, 2.16, -0.55), 8)
		rail.rotation.z = PI * 0.5
		_fittings.add_child(rail)
		# Droppers from the ceiling down to the rail, not stubs poking up off it.
		for hook in 2:
			_fittings.add_child(Build.cyl_mi(0.02, 1.02, Color(0.80, 0.82, 0.86),
				b + Vector3(-1.3 + float(hook) * 2.8, 2.67, -0.55), 6))
		# Drawn back and bunched at the foot end, the way a curtain in a room
		# somebody is currently in actually sits.
		# Bunched at the end of the rail AWAY from the vitals console, which is
		# the one thing in the room you need to be able to see and reach.
		var drape := Build.box_mi(Vector3(0.34, 1.72, 0.42), Color(0.40, 0.72, 0.74),
			b + Vector3(-1.32, 1.22, -0.55))
		_fittings.add_child(drape)

## Adjustable beds get a visible head section and a control pendant.
func _fit_bed_rails() -> void:
	for r in wards():
		var b := bed_position(r.key)
		_fittings.add_child(Build.box_mi(Vector3(1.0, 0.06, 0.5),
			Color(0.86, 0.89, 0.94), b + Vector3(0, 0.62, -0.72)))
		_fittings.add_child(Build.box_mi(Vector3(0.10, 0.16, 0.05),
			Color(0.30, 0.34, 0.40), b + Vector3(0.62, 0.72, -0.2)))

func _fit_shred_bin() -> void:
	var o: Room = rooms.get("office", null)
	if o == null:
		return
	var c := o.center()
	_fittings.add_child(Build.box_mi(Vector3(0.5, 0.9, 0.5),
		Color(0.20, 0.24, 0.30), Vector3(c.x - 2.1, 0.45, c.z - 1.4)))
	_fittings.add_child(Build.box_mi(Vector3(0.44, 0.06, 0.10),
		Color(0.10, 0.11, 0.13), Vector3(c.x - 2.1, 0.92, c.z - 1.4)))

func _fit_vip() -> void:
	var r: Room = rooms.get("ward_105", null)
	if r == null:
		return
	var c := r.center()
	# A rug, a lamp and something alive, which is more than anybody else gets.
	_fittings.add_child(Build.box_mi(Vector3(3.2, 0.03, 2.4),
		Color(0.46, 0.19, 0.23), Vector3(c.x, 0.02, c.z + 1.2)))
	_fittings.add_child(Build.cyl_mi(0.22, 0.5, Color(0.55, 0.40, 0.28),
		Vector3(c.x + 2.6, 0.25, c.z + 2.6), 10))
	_fittings.add_child(Build.mi(Build.sphere_mesh(0.42),
		Build.mat(Color(0.24, 0.62, 0.34)), Vector3(c.x + 2.6, 0.85, c.z + 2.6)))

## Two framed things on your office wall, in the order you bought them.
func _fit_office_wall() -> void:
	var o: Room = rooms.get("office", null)
	if o == null:
		return
	var c := o.center()
	var wall_z: float = o.rect.position.y + 0.14
	# Clear of the desk terminal in the middle of that wall, or the expensive
	# framed things you bought are behind a monitor.
	if GameState.has_upgrade("legal_retainer"):
		_fittings.add_child(Build.box_mi(Vector3(0.5, 0.66, 0.04),
			Color(0.34, 0.26, 0.18), Vector3(c.x - 2.3, 2.15, wall_z)))
		_fittings.add_child(Build.box_mi(Vector3(0.42, 0.56, 0.02),
			Build.PAPER, Vector3(c.x - 2.3, 2.15, wall_z + 0.03)))
	if GameState.has_upgrade("board_appointment"):
		_fittings.add_child(Build.box_mi(Vector3(0.72, 0.52, 0.04),
			Color(0.30, 0.24, 0.16), Vector3(c.x + 2.3, 2.15, wall_z)))
		_fittings.add_child(Build.box_mi(Vector3(0.62, 0.42, 0.02),
			Color(0.94, 0.88, 0.62), Vector3(c.x + 2.3, 2.15, wall_z + 0.03)))

## The machine that is, mechanically, a nurse-retention device.
func _fit_coffee() -> void:
	var st: Room = rooms.get("station", null)
	if st == null:
		return
	var c := st.center()
	_fittings.add_child(Build.box_mi(Vector3(0.62, 0.86, 0.52),
		Color(0.16, 0.18, 0.22), Vector3(c.x + 2.6, 1.18, c.z + 3.2)))
	_fittings.add_child(Build.box_mi(Vector3(0.5, 0.16, 0.03),
		Color(0.94, 0.36, 0.24), Vector3(c.x + 2.6, 1.44, c.z + 2.93)))

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

## A free seat in the clinic waiting row, or the treatment bay's floor if every
## chair is taken. Occupancy is checked against who is actually sitting there,
## so somebody being admitted frees their chair for the next arrival.
func clinic_seat(taken: Array) -> Vector3:
	for seat in Furniture.clinic_seats:
		var free := true
		for pos in taken:
			if (pos as Vector3).distance_to(seat) < 0.6:
				free = false
				break
		if free:
			return seat
	return point_in("treatment", "walkin_spot")

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
		var door_plate := Build.box_mi(
			Vector3(float(String(entry["display"]).length()) * 0.085 * 0.62 + 0.1, 0.17, 0.03),
			Color(0.14, 0.20, 0.26), Vector3.ZERO)
		var sign := Build.label3d(String(entry["display"]), 0.085, Color(0.96, 0.97, 0.94), false)
		# Offset to the side of the doorway rather than over it, so the sign
		# reads as a door plate instead of a banner across the opening.
		var w := float(entry.get("door_w", DOOR_W))
		sign.position = Vector3(centre + w * 0.5 + 0.45, 2.05, z + (0.11 if not north else -0.11))
		sign.rotation.y = PI if north else 0.0
		# Clear of the plate face, or the text z-fights with it and vanishes.
		door_plate.position = sign.position + Vector3(0, 0, -0.03 if not north else 0.03)
		add_child(door_plate)
		add_child(sign)

		# A flag sign, projecting into the corridor at right angles to the wall.
		# The plate above reads at four metres and the corridor is sixty-two
		# long, so from anywhere useful the whole floor was unlabelled — you
		# navigated by counting doors. This is what a real corridor does.
		# Two labels back to back, each showing only its front face. A single
		# double-sided Label3D projecting into a corridor is legible walking one
		# way and MIRRORED walking the other, which is worse than no sign at all
		# — the first screenshot of this read "l0l" and "ǝʞɐʇnI ⅋ ʎqqo˥".
		var short := _short_name(String(entry["display"]))
		# The plate the two faces are stuck to. Without it the text hangs in
		# mid-air off the wall, which is the one thing signage never does, and
		# reads as a HUD element that has escaped into the world.
		var plate_w := float(short.length()) * 0.155 * 0.62 + 0.16
		var plate := Build.box_mi(Vector3(0.05, 0.30, plate_w),
			Color(0.14, 0.20, 0.26), Vector3.ZERO)
		plate.position = Vector3(centre + w * 0.5 + 0.28, 2.42,
			z + (0.30 if not north else -0.30))
		add_child(plate)
		# A stub back to the wall, so the plate is mounted rather than hovering.
		var arm := Build.box_mi(Vector3(0.04, 0.05, 0.30),
			Color(0.14, 0.20, 0.26), Vector3.ZERO)
		arm.position = Vector3(centre + w * 0.5 + 0.28, 2.42,
			z + (0.16 if not north else -0.16))
		add_child(arm)
		for face in [0.0, PI]:
			var flag := Build.label3d(short, 0.155, Color(0.93, 0.96, 0.98), false)
			flag.double_sided = false
			# Each face sits proud of its own side of the plate. Centred, both
			# labels are buried inside the box and the corridor loses its signs.
			var side := 0.045 if is_zero_approx(face) else -0.045
			flag.position = Vector3(centre + w * 0.5 + 0.28 + side, 2.42,
				z + (0.30 if not north else -0.30))
			flag.rotation.y = PI * 0.5 + face
			add_child(flag)

		# ...and beside each ward door, who is behind it.
		if String(entry["kind"]) == "ward":
			var card := WardDoorCard.new()
			card.room_key = String(entry["key"])
			add_child(card)
			card.build(_short_name(String(entry["display"])))
			card.position = Vector3(centre - w * 0.5 - 0.42, 1.52,
				z + (0.09 if not north else -0.09))
			card.rotation.y = PI if north else 0.0

## "Room 101" reads as "101" on a corridor flag; "Nurses' Station" does not
## shorten and should not.
func _short_name(display: String) -> String:
	return display.trim_prefix("Room ") if display.begins_with("Room ") else display

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
func point_in(key: String, stream := "nav") -> Vector3:
	var r: Room = rooms.get(key, null)
	if r == null:
		return Vector3.ZERO
	return nav.random_point_in(r.rect.grow(-1.0), stream)

## Where a shift starts. Authored so the first frame of a run is composed
## rather than rolled — see the note at Game._spawn_player.
func lobby_spawn() -> Vector3:
	var r: Room = rooms.get("lobby", null)
	if r == null:
		return Vector3.ZERO
	return Vector3(r.rect.position.x + 6.2, 0.0, r.rect.position.y + 2.4)

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
