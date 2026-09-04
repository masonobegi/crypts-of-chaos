class_name Furniture
extends RefCounted
## Populates each room with fixtures and physics props.
##
## Kept separate from Hospital so the floor plan and its contents can change
## independently — a new room kind is one match arm here.
##
## Everything here sets LOCAL `position`, never `global_position`. The hospital
## node sits at the origin with an identity transform, so the two are equivalent
## — but global_position is only valid once a node is inside the tree, and the
## floor is assembled before that is guaranteed (headless tooling adds nodes in
## a SceneTree's _initialize(), where the root is not yet considered in-tree).
## Using local positions makes construction independent of tree membership.
##
## There used to be recipes here for a lobby, a treatment bay, a supply room, a
## staff WC, an emergency intake, a radiology department and a psych day room.
## They furnished rooms that no longer exist, out of machines, shelves,
## shredders, thermostats and an item database that no longer exist either.
## Four rooms, four recipes.

## XZ footprints of everything solid that was placed, so navigation can be baked
## around it. Without this, NPCs path straight through desks and shelves and get
## wedged against them — a nurse spawned behind the station counter simply never
## went anywhere again.
static var footprints: Array[Rect2] = []

static func furnish(h: Hospital) -> Array[Rect2]:
	footprints = []
	h.beds = []
	for r in h.room_list():
		match r.kind:
			"ward": _ward(h, r)
			"corridor": _corridor(h, r)
			"station": _station(h, r)
			"office": _office(h, r)
		_dress(h, r)
	return footprints

# ------------------------------------------------------------------ dressing
## Which wall is which. The ward is on the north side of the corridor and its
## door is on its MINIMUM z edge; the station and the office open onto the same
## corridor from below, so their door is on their MAXIMUM z edge. One check
## against the corridor's own z, and every room after this can say "the wall
## with the door in it" and mean it.
static func _door_on_min_z(r: Room) -> bool:
	return r.rect.position.y >= 4.0

static func _door_wall_z(r: Room) -> float:
	return r.rect.position.y if _door_on_min_z(r) else r.rect.position.y + r.rect.size.y

static func _far_wall_z(r: Room) -> float:
	return r.rect.position.y + r.rect.size.y if _door_on_min_z(r) else r.rect.position.y

## A point on a wall, `t` along it from one end, `y` up it, standing 9cm proud
## of the plaster. Dressing is flat and shallow, so 9cm clears the wall without
## ever being something the player can walk into.
const OFF := 0.09

static func _door_wall(r: Room, t: float, y: float) -> Vector3:
	var z := _door_wall_z(r)
	return Vector3(r.rect.position.x + r.rect.size.x * t, y,
		z + (OFF if _door_on_min_z(r) else -OFF))

static func _far_wall(r: Room, t: float, y: float) -> Vector3:
	var z := _far_wall_z(r)
	return Vector3(r.rect.position.x + r.rect.size.x * t, y,
		z + (-OFF if _door_on_min_z(r) else OFF))

static func _left_wall(r: Room, t: float, y: float) -> Vector3:
	return Vector3(r.rect.position.x + OFF, y, r.rect.position.y + r.rect.size.y * t)

static func _right_wall(r: Room, t: float, y: float) -> Vector3:
	return Vector3(r.rect.end.x - OFF, y, r.rect.position.y + r.rect.size.y * t)

static func _door_rot(r: Room) -> float:
	return 0.0 if _door_on_min_z(r) else PI

static func _far_rot(r: Room) -> float:
	return PI if _door_on_min_z(r) else 0.0

const LEFT_ROT := PI * 0.5
const RIGHT_ROT := -PI * 0.5

## Everything that is on a wall or a ceiling and does nothing.
##
## Called for every room after its real furniture is placed. Nothing here takes
## a footprint or has collision, so it can be added anywhere without a nurse
## getting stuck on it — which is the rule that lets there be a lot of it.
static func _dress(h: Hospital, r: Room) -> void:
	var c := r.center()
	var w: float = r.rect.size.x
	var d: float = r.rect.size.y
	# Air and water, on every ceiling. The ceiling is the top third of every
	# interior shot and it used to be one unbroken plane with a lamp in it.
	if w > 4.0 and d > 4.0:
		Dressing.vent(h, Vector3(c.x + w * 0.26, Hospital.WALL_H, c.z - d * 0.24))
		Dressing.sprinkler(h, Vector3(c.x - w * 0.24, Hospital.WALL_H, c.z + d * 0.22))
	if r.kind != "corridor":
		Dressing.dispenser(h, _door_wall(r, 0.14, 1.32), _door_rot(r))
	match r.kind:
		"ward": _dress_ward(h, r)
		"corridor": _dress_corridor(h, r)
		"station": _dress_station(h, r)
		"office": _dress_office(h, r)

## Everything in the bay that is not a bed. The per-bed dressing — gas panel,
## bed number, cabinet, table — is placed with the bed itself in _ward(),
## because it belongs to the bed rather than to the room.
static func _dress_ward(h: Hospital, r: Room) -> void:
	var into := _toward(r)
	var far_z := _far_wall_z(r)
	var bed_z: float = h.bed_position(1).z
	# The bay, marked out on the floor: one long strip the beds stand on, mixed
	# toward the floor's own colour rather than painted in a room tint, because
	# a saturated rectangle reads as a rug somebody laid down and this is meant
	# to be vinyl somebody specified.
	Dressing.floor_zone(h, Vector3(r.rect.get_center().x, 0, bed_z + into * 0.4),
		Vector2(r.rect.size.x - 1.6, 3.6),
		_bay_tint(0).darkened(0.28).lerp(Color(0.56, 0.66, 0.57), 0.55))
	# A curtain track between each pair of bays, gathered against the divider.
	for i in Hospital.BEDS - 1:
		var mid: float = (h.bed_position(i + 1).x + h.bed_position(i + 2).x) * 0.5
		Dressing.curtain(h, Vector3(mid, 0, bed_z + into * 0.1), 2.6, LEFT_ROT,
			_bay_tint(i))
	Dressing.poster(h, _left_wall(r, 0.62, 1.62), LEFT_ROT, 0.60, 0.84, _bay_tint(1), 5)
	Dressing.wall_art(h, _right_wall(r, 0.55, 1.70), RIGHT_ROT, 0.86, 0.66,
		_bay_tint(3), Color(0.98, 0.78, 0.38))
	Dressing.wall_tv(h, _right_wall(r, 0.80, 2.05), RIGHT_ROT)
	Dressing.clock(h, _door_wall(r, 0.72, 2.34), _door_rot(r))
	Dressing.coat_hooks(h, _left_wall(r, 0.14, 1.72), LEFT_ROT)
	Dressing.bin(h, Vector3(r.rect.position.x + 0.8, 0, _door_wall_z(r) - into * 0.9))
	# Down at the door end: at the far wall it stood in bed five's visitor chair.
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, _door_wall_z(r) - into * 3.4), 0.9)
	Dressing.floor_mat(h, Vector3(_door_x(r), 0, _door_wall_z(r) - into * 1.05),
		Vector2(1.5, 0.9), Color(0.22, 0.30, 0.32))
	_dress_ward_top(h, r)

## THE TOP OF THE WARD, which was a hundred and twenty square metres of nothing.
##
## Every bed is against the far wall, so the half of the bay nearest the door was
## bare vinyl and one blank painted wall — twenty metres of it — with a fire
## door in the middle. In a wide shot down the ward that reads as a level
## somebody had not finished building, and it is the first thing a player sees
## walking in. It was also the first thing in the screenshots that looked like a
## prototype rather than a game.
##
## A real ward puts its working end here: the linen and the hamper, because
## somebody has to change five beds; the trolley of boxes nobody has put away;
## the whiteboard with the bed list on it; the gel dispensers by the door, which
## are the most photographed object in any hospital; and chairs, because
## visitors wait at this end rather than at the bedside.
##
## All of it is Dressing, so none of it has collision or a navigation footprint
## and no member of staff can get stuck on any of it. That is the rule that
## lets there be this much of it. The overlap audit in `smoke_run.gd` is what
## keeps it honest — two of these were placed inside each other on the way in.
static func _dress_ward_top(h: Hospital, r: Room) -> void:
	var into := _toward(r)
	var dz := _door_wall_z(r)
	var lx: float = r.rect.position.x
	var rx: float = r.rect.end.x

	# The working corner: linen in, dirty out, and the boxes in between.
	Dressing.linen(h, Vector3(lx + 1.5, 0, dz - into * 1.5), _door_rot(r))
	Dressing.hamper(h, Vector3(lx + 2.6, 0, dz - into * 1.5), _door_rot(r))
	Dressing.boxes(h, Vector3(lx + 0.9, 0, dz - into * 2.9), LEFT_ROT)
	Dressing.mop_bucket(h, Vector3(lx + 3.6, 0, dz - into * 1.3), _door_rot(r))

	# The board the shift is actually run off, and the gel nobody uses.
	Dressing.whiteboard(h, _door_wall(r, 0.30, 1.62), _door_rot(r), 2.0, 1.15)
	Dressing.noticeboard(h, _door_wall(r, 0.62, 1.58), _door_rot(r), 1.7, 1.05)
	Dressing.dispenser(h, _door_wall(r, 0.46, 1.32), _door_rot(r))
	Dressing.extinguisher(h, _door_wall(r, 0.86, 1.05), _door_rot(r))

	# Where people wait. Two chairs and something to put a cup on, at the end of
	# the bay furthest from anybody being examined.
	Dressing.stool(h, Vector3(rx - 1.3, 0, dz - into * 1.6))
	Dressing.stool(h, Vector3(rx - 2.2, 0, dz - into * 1.6))
	Dressing.water_cooler(h, Vector3(rx - 0.8, 0, dz - into * 2.8), RIGHT_ROT)
	Dressing.plant(h, Vector3(rx - 3.3, 0, dz - into * 1.4), 1.05)

	# Trays stack ON something. Parked in open floor they read as a thing
	# somebody dropped in the middle of the room, which is exactly how they
	# looked in the first screenshot after this went in.
	Dressing.trays(h, Vector3(lx + 4.5, 0, dz - into * 1.35), _door_rot(r))
	Dressing.screen_partition(h, Vector3(r.rect.get_center().x - 2.6, 0,
		dz - into * 3.2), LEFT_ROT)
	# The handrail every ward has, down the blank wall — cut around the doorway,
	# because a rail across a fire door is the sort of detail that makes a room
	# read as generated rather than built.
	var door_x := _door_x(r)
	Dressing.handrail_run(h, lx + 5.2, rx - 5.2, dz - into * 0.06,
		[Vector2(door_x - 1.5, door_x + 1.5)], 0.92)
	# The near half of the bay, which is otherwise a lot of empty floor between
	# the door and the people.
	var hmp := Vector3(r.rect.position.x + 1.0, 0, _door_wall_z(r) - into * 2.4)
	Dressing.hamper(h, hmp, 0.4)
	_occupy(hmp.x, hmp.z, 0.6, 0.6)
	var scr := Vector3(r.rect.end.x - 1.2, 0, _door_wall_z(r) - into * 2.2)
	Dressing.screen_partition(h, scr, _door_rot(r) + 0.5, _bay_tint(4))
	_occupy(scr.x, scr.z, 1.4, 0.6)

## One colour per bay, so bed three is somewhere rather than anywhere.
static func _bay_tint(index: int) -> Color:
	var tints := [Color(0.36, 0.68, 0.72), Color(0.86, 0.55, 0.40),
		Color(0.48, 0.62, 0.86), Color(0.52, 0.74, 0.46), Color(0.78, 0.52, 0.74)]
	return tints[posmod(index, tints.size())]

static func _dress_corridor(h: Hospital, r: Room) -> void:
	var z0: float = r.rect.position.y
	var z1: float = r.rect.end.y
	var x0: float = r.rect.position.x + 1.0
	var x1: float = r.rect.end.x - 1.0
	# Rails both sides, broken at every doorway on that side, and the coloured
	# lines on the floor that every real hospital uses instead of signage nobody
	# reads.
	var north_gaps: Array = []
	var south_gaps: Array = []
	for entry in Hospital.LAYOUT:
		if String(entry["kind"]) == "corridor":
			continue
		var rect: Rect2 = entry["rect"]
		var centre := float(entry.get("door", rect.get_center().x))
		var w := float(entry.get("door_w", Hospital.DOOR_W)) * 0.5 + 0.45
		# A room north of the corridor opens onto the corridor's north wall.
		if rect.position.y > 0.0:
			north_gaps.append(Vector2(centre - w, centre + w))
		else:
			south_gaps.append(Vector2(centre - w, centre + w))
	Dressing.handrail_run(h, x0, x1, z0 + 0.12, south_gaps)
	Dressing.handrail_run(h, x0, x1, z1 - 0.12, north_gaps)
	Dressing.floor_line(h, x0, x1, z0 + 0.75, Color(0.30, 0.58, 0.88))
	Dressing.floor_line(h, x0, x1, z0 + 0.95, Color(0.94, 0.72, 0.24))
	Dressing.floor_line(h, x0, x1, z1 - 0.80, Color(0.42, 0.76, 0.52))
	# Hung between the ceiling lamps rather than on top of them.
	Dressing.ceiling_sign(h, Vector3(5.0, Hospital.WALL_H, (z0 + z1) * 0.5),
		"WARD C  ▲      ◀  STATION")
	Dressing.ceiling_sign(h, Vector3(15.0, Hospital.WALL_H, (z0 + z1) * 0.5),
		"YOUR OFFICE  ▶")
	Dressing.noticeboard(h, Vector3(9.0, 1.65, z0 + 0.10), 0.0, 1.8, 1.1)
	Dressing.extinguisher(h, Vector3(2.0, 1.05, z0 + 0.10), 0.0)
	for x in [7.0, 13.0]:
		Dressing.poster(h, Vector3(float(x), 1.72, z1 - 0.10), PI, 0.58, 0.80,
			Color(0.35, 0.72, 0.70), 4)
	Dressing.wall_art(h, Vector3(11.6, 1.74, z0 + 0.10), 0.0, 0.82, 0.62,
		Color(0.44, 0.76, 0.86), Color(0.96, 0.72, 0.34))
	for x2 in [1.0, 18.6]:
		Dressing.plant(h, Vector3(float(x2), 0, z1 - 0.55), 0.95)
	Dressing.bin(h, Vector3(12.0, 0, z1 - 0.5), Color(0.30, 0.50, 0.58))

static func _dress_station(h: Hospital, r: Room) -> void:
	# Raised from 1.68 to clear the back worktop it hangs over.
	Dressing.noticeboard(h, _far_wall(r, 0.50, 1.78), _far_rot(r), 1.7, 1.05)
	Dressing.poster(h, _left_wall(r, 0.35, 1.66), LEFT_ROT, 0.56, 0.78,
		Color(0.94, 0.66, 0.30), 5)
	Dressing.clock(h, _far_wall(r, 0.16, 2.30), _far_rot(r))
	Dressing.linen(h, Vector3(r.rect.position.x + 0.9, 0.90, r.rect.position.y + 1.2))
	Dressing.trays(h, Vector3(r.rect.end.x - 1.0, 0.90, r.rect.position.y + 1.4))
	Dressing.bin(h, Vector3(r.rect.position.x + 0.9, 0, r.rect.end.y - 3.0))
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, r.rect.end.y - 3.0), 0.85)
	# The board every ward station has, with the bed list on it in somebody's
	# handwriting. It is the room's whole reason for existing, on a wall.
	Dressing.whiteboard(h, _right_wall(r, 0.42, 1.72), RIGHT_ROT, 1.5, 1.0)
	var cool := Vector3(r.rect.position.x + 0.7, 0, r.rect.get_center().y + 1.8)
	Dressing.water_cooler(h, cool, LEFT_ROT)
	_occupy(cool.x, cool.z, 0.5, 0.5)

static func _dress_office(h: Hospital, r: Room) -> void:
	Dressing.wall_art(h, _far_wall(r, 0.36, 1.72), _far_rot(r), 0.94, 0.72,
		Color(0.72, 0.52, 0.86), Color(0.96, 0.80, 0.42))
	Dressing.poster(h, _far_wall(r, 0.74, 1.70), _far_rot(r), 0.52, 0.74,
		Color(0.60, 0.48, 0.86), 5)
	Dressing.clock(h, _left_wall(r, 0.30, 2.28), LEFT_ROT)
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, r.rect.position.y + 1.2), 1.1)
	Dressing.bin(h, Vector3(r.rect.position.x + 0.9, 0, r.rect.position.y + 1.1),
		Color(0.46, 0.36, 0.30))
	Dressing.floor_mat(h, Vector3(r.rect.get_center().x, 0, r.rect.get_center().y),
		Vector2(2.6, 1.8), Color(0.42, 0.24, 0.22))
	Dressing.whiteboard(h, _left_wall(r, 0.62, 1.66), LEFT_ROT, 1.1, 0.8)

## Record a solid footprint, grown slightly so NPCs keep their shoulders clear.
static func _occupy(centre_x: float, centre_z: float, w: float, d: float) -> void:
	footprints.append(Rect2(centre_x - w * 0.5 - 0.25, centre_z - d * 0.5 - 0.25,
		w + 0.5, d + 0.5))

# ------------------------------------------------------------------ helpers
## Simple static furniture: a box with collision, no behaviour.
static func _block(h: Hospital, size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var b := Build.wall(size, color, pos, rot_y)
	b.name = "Block"
	h.add_child(b)
	# Only things tall enough to stop a person count as obstacles; a low plinth
	# at ankle height does not need to be routed around.
	if size.y > 0.35:
		if absf(rot_y) > 0.01:
			_occupy(pos.x, pos.z, size.z, size.x)   # rotated 90 degrees
		else:
			_occupy(pos.x, pos.z, size.x, size.z)
	return b

static func _table(h: Hospital, pos: Vector3, w := 0.6, d := 0.5, height := 0.72,
		color := Color(0.72, 0.66, 0.55)) -> void:
	_block(h, Vector3(w, 0.06, d), color, pos + Vector3(0, height, 0))
	_occupy(pos.x, pos.z, w, d)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_block(h, Vector3(0.05, height, 0.05), color.darkened(0.3),
				pos + Vector3(sx * (w * 0.5 - 0.06), height * 0.5, sz * (d * 0.5 - 0.06)))

static func _chair(h: Hospital, pos: Vector3, rot_y := 0.0, color := Color(0.35, 0.48, 0.55)) -> void:
	var root := Node3D.new()
	root.name = "Chair"
	h.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var seat := Build.wall(Vector3(0.44, 0.06, 0.44), color, Vector3(0, 0.45, 0))
	root.add_child(seat)
	_occupy(pos.x, pos.z, 0.5, 0.5)
	var back := Build.wall(Vector3(0.44, 0.5, 0.06), color, Vector3(0, 0.7, -0.19))
	root.add_child(back)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			root.add_child(Build.wall(Vector3(0.04, 0.45, 0.04), color.darkened(0.4),
				Vector3(sx * 0.18, 0.22, sz * 0.18)))

## A rolling cart. Crashing one is the cheapest, loudest, most reliable
## distraction in the building.
##
## The loose stock that used to sit on its top shelf went with the item
## database — every prop in the game was spawned from an id in that table.
static func _cart(h: Hospital, pos: Vector3, rot_y := 0.0) -> Prop:
	var size := Vector3(0.62, 0.9, 0.46)
	var metal := Build.mat(Build.METAL, 0.45, 0.12)
	var cart := Build.make_prop("med_cart", "Medical Cart", size, 26.0, [
		{"mesh": Build.box_mesh(Vector3(0.62, 0.05, 0.46)), "mat": metal, "pos": Vector3(0, 0.42, 0)},
		{"mesh": Build.box_mesh(Vector3(0.58, 0.05, 0.42)), "mat": metal, "pos": Vector3(0, 0.1, 0)},
		{"mesh": Build.box_mesh(Vector3(0.58, 0.28, 0.42)), "mat": Build.mat(Color(0.75, 0.62, 0.35)), "pos": Vector3(0, 0.26, 0)},
		{"mesh": Build.box_mesh(Vector3(0.05, 0.5, 0.05)), "mat": metal, "pos": Vector3(-0.28, 0.2, -0.2)},
		{"mesh": Build.box_mesh(Vector3(0.05, 0.5, 0.05)), "mat": metal, "pos": Vector3(0.28, 0.2, -0.2)},
		{"mesh": Build.box_mesh(Vector3(0.05, 0.5, 0.05)), "mat": metal, "pos": Vector3(-0.28, 0.2, 0.2)},
		{"mesh": Build.box_mesh(Vector3(0.05, 0.5, 0.05)), "mat": metal, "pos": Vector3(0.28, 0.2, 0.2)},
		{"mesh": Build.box_mesh(Vector3(0.5, 0.04, 0.05)), "mat": metal, "pos": Vector3(0, 0.62, -0.2)},
	])
	cart.noise_radius = 18.0
	cart.blurb = "Wheels. No brake. Load-bearing to the plot."
	h.add_child(cart)
	cart.position = pos + Vector3(0, 0.25, 0)
	cart.rotation.y = rot_y
	return cart

static func _iv_stand(h: Hospital, pos: Vector3) -> Prop:
	var metal := Build.mat(Build.METAL, 0.40, 0.15)
	var stand := Build.make_prop("iv_stand", "IV Stand", Vector3(0.35, 1.8, 0.35), 6.0, [
		{"mesh": Build.cyl_mesh(0.018, 1.7), "mat": metal, "pos": Vector3(0, 0.85, 0)},
		{"mesh": Build.cyl_mesh(0.2, 0.04, 10), "mat": metal, "pos": Vector3(0, 0.02, 0)},
		{"mesh": Build.box_mesh(Vector3(0.24, 0.02, 0.02)), "mat": metal, "pos": Vector3(0, 1.68, 0)},
	])
	stand.blurb = "Top-heavy by design."
	stand.noise_radius = 14.0
	h.add_child(stand)
	stand.position = pos + Vector3(0, 0.9, 0)
	return stand

## Signage on a plate. White outlined text floating directly on a pale wall was
## legible in the sense that you could read it if you already knew it was there;
## a hospital's actual signs are a coloured plate with the text on it, which is
## both what the building looks like and the reason you can find anything in it
## from the far end of a corridor.
static func _wall_sign(h: Hospital, text: String, pos: Vector3, rot_y: float,
		size := 0.1, plate := true) -> void:
	# The wall normal the sign is mounted on, so the plate sits just behind the
	# text rather than z-fighting with it.
	var out := Vector3(sin(rot_y), 0.0, cos(rot_y))
	if plate:
		var lines: PackedStringArray = text.split("\n")
		var widest := 0
		for ln in lines:
			widest = maxi(widest, ln.length())
		var w := float(widest) * size * 0.62 + size * 0.9
		var tall := float(lines.size()) * size * 1.34 + size * 0.7
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, tall)
		q.mesh = qm
		q.material_override = Build.unshaded(Color(0.14, 0.20, 0.26))
		h.add_child(q)
		q.position = pos - out * 0.012
		q.rotation.y = rot_y
	var l := Build.label3d(text, size, Color(0.96, 0.97, 0.94), false)
	h.add_child(l)
	l.position = pos
	l.rotation.y = rot_y

# ------------------------------------------------------------------ ward
## Five beds down the far wall, numbered the way the case file numbers them.
##
## There were five separate patient rooms with one day-chair in each. Five
## people in one bay is a different game: everybody in it can hear what you say
## to everybody else, and the four beds you are not standing at are four
## witnesses.
##
## The vitals console, the window unit, the light switch and the thermostat that
## used to stand in every patient room went with the systems that read them. The
## only instrument left in here is the person in the bed.
static func _ward(h: Hospital, r: Room) -> void:
	var far_z := _far_wall_z(r)
	var into := _toward(r)
	for i in Hospital.BEDS:
		var n := i + 1
		var slot := h.bed_position(n)

		var bed := PatientBed.new()
		bed.room_key = r.key
		bed.name = "Bed_%d" % n
		# The bed's number, so anything holding a case file can find the bed it
		# names without counting nodes.
		bed.set_meta("bed_index", n)
		h.add_child(bed)
		bed.build()
		bed.position = slot
		# Head to the far wall, foot toward the door.
		bed.rotation.y = _far_rot(r)
		h.beds.append(bed)
		_occupy(slot.x, slot.z, 1.0, 2.1)

		# Gas outlets and the bed number, on the wall behind the head.
		# ON the wall plane. `Dressing._add` already pushes every piece out by
		# half its own depth — that is what the depth argument is for, and
		# CLAUDE.md 13 is about exactly this — so a caller that adds its own
		# standoff on top is double-offsetting. The gas panel hung 13cm proud of
		# the plaster and the sharps bin a full 30cm, floating in mid-air beside
		# every bed on the ward.
		Dressing.oxygen_panel(h, Vector3(slot.x, 1.42, far_z), _far_rot(r))
		# OFF TO THE SIDE, because the patient's floating name tag is centred
		# over the same bed. Directly above the head the two sat on top of each
		# other and every bedside shot read "Sam Oduya" with a "4" printed
		# through it. Beside the head is also where a real bed number is.
		# 1.35m out, not 0.86. The patient's name tag is a billboard floating at
		# the bed centre; the number is fixed on the wall behind it. They are
		# 70cm apart vertically, so this is a projection overlap rather than a
		# collision — but at the angle you stand at to talk to somebody they
		# still landed on top of each other. Beds are 4m apart, so there is room.
		_wall_sign(h, str(n), Vector3(slot.x - 1.35, 2.30, far_z + into * 0.14),
			_far_rot(r), 0.16)
		Dressing.sharps(h, Vector3(slot.x + 0.66, 1.15, far_z), _far_rot(r))

		# The cabinet by the head and the tray table across the foot: the two
		# things that are actually beside a hospital bed. Both take a footprint,
		# because both are big enough for a nurse to walk into.
		var cab := Vector3(slot.x - 1.05, 0, slot.z - into * 0.45)
		Dressing.cabinet(h, cab, _far_rot(r))
		_occupy(cab.x, cab.z, 0.6, 0.55)
		var tray := Vector3(slot.x + 1.00, 0, slot.z + into * 0.35)
		Dressing.overbed_table(h, tray, _door_rot(r))
		_occupy(tray.x + 0.2, tray.z, 0.8, 0.5)
		_iv_stand(h, Vector3(slot.x - 0.66, 0, slot.z - into * 0.80))
		# A visitor's chair, turned toward the person in the bed.
		_chair(h, Vector3(slot.x + 1.14, 0, slot.z - into * 0.60), RIGHT_ROT,
			_bay_tint(i).darkened(0.25))

	# The ward terminal. One of the three places a note can be written, and the
	# only one standing in the room the note is about: its screen is turned to
	# the door, so you write with all five beds in front of you and whatever is
	# in them looking back.
	var term_x: float = _door_x(r) + 3.2
	var term_z: float = _door_wall_z(r) - into * 1.4
	_table(h, Vector3(term_x, 0, term_z), 1.2, 0.7, 0.75, Color(0.52, 0.56, 0.60))
	var t := RecordsTerminal.new()
	t.room_key = r.key
	t.mode = "ehr"
	h.add_child(t)
	t.build("Ward Terminal", false)
	t.position = Vector3(term_x, 0.55, term_z)
	t.rotation.y = _far_rot(r)
	_occupy(term_x, term_z, 0.7, 0.5)

	_wall_sign(h, r.display, Vector3(r.rect.get_center().x, 2.62, far_z + into * 0.14),
		_far_rot(r), 0.14)

## Which way is "into the room" from the far wall.
static func _toward(r: Room) -> float:
	return -1.0 if _door_on_min_z(r) else 1.0

static func _door_x(r: Room) -> float:
	for entry in Hospital.LAYOUT:
		if String(entry["key"]) == r.key:
			return float(entry.get("door", r.rect.get_center().x))
	return r.rect.get_center().x

# ------------------------------------------------------------------ corridor
static func _corridor(h: Hospital, r: Room) -> void:
	var z := r.rect.get_center().y
	_cart(h, Vector3(7.6, 0, z - 1.1), 0.3)
	_cart(h, Vector3(13.2, 0, z + 1.1), -1.9)
	_iv_stand(h, Vector3(17.6, 0, z + 1.3))

	# Wayfinding stripes down the floor. They give the eye something to follow
	# and something to measure your own progress against, which an unbroken pale
	# blue plane does not.
	var stripes := [
		[0.72, Color(0.16, 0.62, 0.66)],
		[0.88, Color(0.94, 0.68, 0.24)],
		[1.04, Color(0.84, 0.36, 0.44)],
	]
	for st in stripes:
		var strip := Build.box_mi(Vector3(19.0, 0.012, 0.09), st[1],
			Vector3(10.0, 0.008, float(st[0])), 0.5, 0.0)
		h.add_child(strip)

	# Benches along the north wall, clear of the ward opening at 9.2-10.8. A
	# bench four centimetres from a doorway is a bench every player walking that
	# wall catches on — which happened, and read for a long time as a fault in
	# the door rather than as a chair in front of it.
	for x in [4.0, 5.4, 14.4, 15.8]:
		_chair(h, Vector3(x, 0, z + 1.5), PI)
	_wall_sign(h, "WARD C  ▲", Vector3(6.8, 2.6, 3.85), PI, 0.16)
	_wall_sign(h, "◄  NURSES' STATION        YOUR OFFICE  ►",
		Vector3(11.0, 2.6, 0.15), 0.0, 0.13)

# ------------------------------------------------------------------ station
static func _station(h: Hospital, r: Room) -> void:
	var c := r.center()
	# The back worktop, against the exterior wall.
	_block(h, Vector3(6.0, 1.1, 0.6), Color(0.48, 0.55, 0.58), Vector3(c.x, 0.55, r.rect.position.y + 0.5))
	_block(h, Vector3(6.2, 0.08, 0.85), Color(0.66, 0.70, 0.72), Vector3(c.x, 1.12, r.rect.position.y + 0.5))

	# ...and the counter that actually faces the corridor, in two runs either
	# side of the opening. This is the post the whole floor plan is arranged
	# around: whoever is behind it can see the corridor, the ward door, and
	# anybody walking between the two.
	var corridor_z: float = r.rect.position.y + r.rect.size.y - 0.9
	# Both runs clear the 2.2m opening at x 4.4-6.6 by a comfortable margin.
	# They used to be positioned so that 30cm of worktop stood inside the end
	# wall — one of the "things phasing through each other" from the playtest,
	# and the reason the overlap audit exists at all.
	for sx in [c.x - 3.0, c.x + 3.0]:
		_block(h, Vector3(2.1, 1.1, 0.6), Color(0.48, 0.55, 0.58), Vector3(sx, 0.55, corridor_z))
		_block(h, Vector3(2.3, 0.08, 0.9), Color(0.66, 0.70, 0.72), Vector3(sx, 1.12, corridor_z))
		_occupy(sx, corridor_z, 2.3, 0.9)
	_wall_sign(h, "NURSES' STATION", Vector3(c.x - 3.0, 1.55, corridor_z + 0.32), 0.0, 0.13)

	# THE BOARD, on the back wall behind the worktop, facing into the room. You
	# have to be standing IN the station to read it — which is the point: it is
	# the one piece of information in the game that is somewhere rather than on
	# a screen you can open from anywhere.
	var board := HandoverBoard.new()
	board.room_key = r.key
	h.add_child(board)
	board.build()
	board.position = Vector3(c.x - 1.6, 1.55, r.rect.position.y + 0.14)

	# The station terminal, on the counter with its screen turned into the room:
	# to use it you stand behind the counter, two metres from a doorway that has
	# no door on it, with whoever is on duty at your shoulder. Writing a note
	# here is not the same act as writing it in your office with the door shut,
	# and the building is what says so.
	var t := RecordsTerminal.new()
	t.room_key = r.key
	t.mode = "ehr"
	h.add_child(t)
	t.build("Station Terminal", false)
	t.position = Vector3(c.x + 3.0, 0.70, corridor_z)
	t.rotation.y = PI

	_table(h, Vector3(c.x - 2.4, 0, c.z + 2.6), 1.6, 0.8, 0.75)
	_chair(h, Vector3(c.x - 2.4, 0, c.z + 1.8), 0.0)
	_chair(h, Vector3(c.x + 1.2, 0, c.z + 2.4), 2.6)
	# Coffee machine: the single most important object to a nurse's schedule.
	# In the east corner rather than the middle of the corridor frontage, where
	# it stood inside the counter once the room lost two metres of depth.
	_table(h, Vector3(c.x + 4.6, 0, c.z + 2.0), 0.8, 0.6, 0.75)
	_block(h, Vector3(0.5, 0.6, 0.45), Color(0.30, 0.32, 0.36), Vector3(c.x + 4.6, 1.08, c.z + 2.0))
	_wall_sign(h, "COFFEE", Vector3(c.x + 4.6, 1.6, c.z + 1.75), 0.0, 0.08)

	# Filing along the west wall, a rota board over the worktop, and a printer
	# that is out of paper. Seen from above with the roof off this was
	# conspicuously the emptiest room in the building, which is a strange look
	# for the ward's one permanently staffed post.
	for fi in 2:
		var fx: float = r.rect.position.x + 0.55
		var fz: float = c.z - 1.0 + float(fi) * 1.15
		_block(h, Vector3(0.62, 1.32, 1.0), Color(0.52, 0.56, 0.60), Vector3(fx, 0.66, fz))
		for drawer in 3:
			_block(h, Vector3(0.05, 0.06, 0.34), Color(0.30, 0.33, 0.37),
				Vector3(fx + 0.33, 0.34 + 0.38 * float(drawer), fz))
		_occupy(fx, fz, 0.7, 1.0)
	_wall_sign(h, "PERSONNEL", Vector3(r.rect.position.x + 0.2, 1.75, c.z - 0.4), LEFT_ROT, 0.085)

	# The rota, over the far end of the back worktop. Whiteboard, four ruled
	# lines, permanently out of date. Kept to the east end because the clock and
	# the noticeboard are on the same wall and something has to give.
	var board_z: float = r.rect.position.y + 0.2
	_block(h, Vector3(2.6, 1.2, 0.07), Color(0.93, 0.94, 0.92), Vector3(c.x + 3.6, 1.85, board_z))
	for ln in 4:
		_block(h, Vector3(2.3, 0.03, 0.02), Color(0.62, 0.68, 0.72),
			Vector3(c.x + 3.6, 1.42 + 0.24 * float(ln), board_z + 0.05))
	_wall_sign(h, "TODAY", Vector3(c.x + 3.6, 2.32, board_z + 0.06), 0.0, 0.095)

	# A printer, and the paper it has run out of.
	_block(h, Vector3(0.52, 0.34, 0.44), Color(0.86, 0.87, 0.85),
		Vector3(c.x + 2.2, 1.29, r.rect.position.y + 0.5))
	_block(h, Vector3(0.40, 0.03, 0.30), Build.PAPER,
		Vector3(c.x + 2.2, 1.47, r.rect.position.y + 0.62))

	# Records cabinet — physical copies. Investigators love these.
	_block(h, Vector3(1.2, 1.6, 0.5), Color(0.55, 0.57, 0.52), Vector3(r.rect.position.x + 0.8, 0.8, c.z + 3.4))
	_wall_sign(h, "WARD RECORDS", Vector3(r.rect.position.x + 0.8, 1.72, c.z + 3.66), 0.0, 0.07)

# ------------------------------------------------------------------ office
static func _office(h: Hospital, r: Room) -> void:
	var c := r.center()
	_table(h, Vector3(c.x, 0, c.z + 1.0), 2.0, 1.0, 0.75, Color(0.42, 0.30, 0.22))
	_chair(h, Vector3(c.x, 0, c.z + 2.0), 0.0, Color(0.30, 0.26, 0.28))

	# The private terminal. The shredder that used to stand beside it went with
	# the paper trail it destroyed; what is written in here is written in an
	# empty room with a door on it, and that is the whole difference the room
	# buys you.
	var t := RecordsTerminal.new()
	t.room_key = r.key
	t.mode = "admin"
	h.add_child(t)
	t.build("Your Terminal", true)
	t.position = Vector3(c.x - 0.3, 0.55, c.z + 0.7)
	_occupy(c.x - 0.3, c.z + 0.7, 0.7, 0.5)

	_block(h, Vector3(1.0, 1.5, 0.5), Color(0.5, 0.52, 0.48), Vector3(r.rect.position.x + 0.8, 0.75, c.z - 2.4))
	_wall_sign(h, "PERSONAL FILES", Vector3(r.rect.position.x + 0.10, 1.62, c.z - 2.4),
		LEFT_ROT, 0.07)
	# The debt letters. Purely narrative, entirely load-bearing.
	_wall_sign(h, "FINAL NOTICE\nFINAL NOTICE\nFINAL NOTICE",
		Vector3(r.rect.end.x - 0.10, 1.5, c.z - 1.0), RIGHT_ROT, 0.075)
	_wall_sign(h, "DR. YOU", Vector3(c.x, 2.3, r.rect.position.y + 0.14), 0.0, 0.15)
