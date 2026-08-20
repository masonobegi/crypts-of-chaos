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

## XZ footprints of everything solid that was placed, so navigation can be baked
## around it. Without this, NPCs path straight through desks and shelves and get
## wedged against them — a nurse spawned behind the station counter simply never
## went anywhere again.
static var footprints: Array[Rect2] = []

## Where walk-ins sit while they wait to be seen. A clinic with people visibly
## waiting in it is a different room from one where they materialise wherever
## the navigation grid felt like putting them, and "how many are still out
## there" ought to be answerable by looking.
static var clinic_seats: Array[Vector3] = []

static func furnish(h: Hospital) -> Array[Rect2]:
	footprints = []
	clinic_seats = []
	for r in h.room_list():
		match r.kind:
			"ward": _ward(h, r)
			"corridor": _corridor(h, r)
			"lobby": _lobby(h, r)
			"station": _station(h, r)
			"treatment": _treatment(h, r)
			"supply": _supply(h, r)
			"office": _office(h, r)
			"bathroom": _bathroom(h, r)
			"intake": _intake(h, r)
			"radiology": _radiology(h, r)
			"day_room": _day_room(h, r)
		_dress(h, r)
	return footprints

# ------------------------------------------------------------------ dressing
## Which wall is which. Wards are on the north side of the corridor and their
## door is on their MINIMUM z edge; everything in the south wing opens onto the
## same corridor from below, so its door is on its MAXIMUM z edge. One check
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
		Dressing.vent(h, Vector3(c.x + w * 0.26, Hospital.WALL_H - 0.07, c.z - d * 0.24))
		Dressing.sprinkler(h, Vector3(c.x - w * 0.24, Hospital.WALL_H - 0.09, c.z + d * 0.22))
	if r.kind != "corridor":
		Dressing.dispenser(h, _door_wall(r, 0.14, 1.32), _door_rot(r))
	match r.kind:
		"ward": _dress_ward(h, r)
		"corridor": _dress_corridor(h, r)
		"lobby": _dress_lobby(h, r)
		"station": _dress_station(h, r)
		"treatment": _dress_treatment(h, r)
		"supply": _dress_supply(h, r)
		"office": _dress_office(h, r)
		"bathroom": _dress_bathroom(h, r)
		"intake": _dress_intake(h, r)
		"radiology": _dress_radiology(h, r)
		"day_room": _dress_day_room(h, r)

static func _dress_ward(h: Hospital, r: Room) -> void:
	var bed := h.bed_position(r.key)
	var far_z := _far_wall_z(r)
	var toward: float = -1.0 if _door_on_min_z(r) else 1.0
	# Gas outlets behind the head of the bed, and a curtain rail across it.
	Dressing.oxygen_panel(h, Vector3(bed.x, 1.42, far_z + toward * 0.10), _far_rot(r))
	Dressing.curtain(h, Vector3(bed.x - 0.2, 0, bed.z + toward * -0.95), 3.0, 0.0,
		_ward_tint(r.key))
	Dressing.sharps(h, Vector3(bed.x - 1.55, 1.15, bed.z + toward * -0.30), _far_rot(r))
	Dressing.poster(h, _left_wall(r, 0.62, 1.62), LEFT_ROT, 0.60, 0.84,
		_ward_tint(r.key), 5)
	Dressing.wall_art(h, _right_wall(r, 0.55, 1.70), RIGHT_ROT, 0.86, 0.66,
		_ward_tint(r.key), Color(0.98, 0.78, 0.38))
	Dressing.clock(h, _door_wall(r, 0.72, 2.34), _door_rot(r))
	Dressing.bin(h, Vector3(r.rect.position.x + 0.8, 0, _door_wall_z(r) - toward * 0.9))
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, far_z + toward * 0.9), 0.9)

## One colour per room, so a ward is somewhere rather than anywhere.
static func _ward_tint(key: String) -> Color:
	var tints := [Color(0.36, 0.68, 0.72), Color(0.86, 0.55, 0.40),
		Color(0.48, 0.62, 0.86), Color(0.52, 0.74, 0.46), Color(0.78, 0.52, 0.74)]
	return tints[absi(hash(key)) % tints.size()]

static func _dress_corridor(h: Hospital, r: Room) -> void:
	var z0: float = r.rect.position.y
	var z1: float = r.rect.end.y
	var x0: float = r.rect.position.x + 1.0
	var x1: float = r.rect.end.x - 1.0
	# Rails both sides, and the coloured lines on the floor that every real
	# hospital uses instead of signage nobody reads.
	Dressing.handrail(h, x0, x1, z0 + 0.12)
	Dressing.handrail(h, x0, x1, z1 - 0.12)
	Dressing.floor_line(h, x0, x1, z0 + 0.75, Color(0.30, 0.58, 0.88))
	Dressing.floor_line(h, x0, x1, z0 + 0.95, Color(0.94, 0.72, 0.24))
	Dressing.floor_line(h, x0, x1, z1 - 0.80, Color(0.42, 0.76, 0.52))
	var signs := [[-6.0, "◀  RADIOLOGY   ·   INTAKE"], [12.0, "WARDS 101–105  ▶"],
		[30.0, "SUPPLY  ·  OFFICE  ▶"]]
	for sgn in signs:
		Dressing.ceiling_sign(h, Vector3(float(sgn[0]), 2.62, (z0 + z1) * 0.5),
			String(sgn[1]))
	Dressing.noticeboard(h, Vector3(7.0, 1.65, z1 - 0.10), PI, 1.8, 1.1)
	Dressing.extinguisher(h, Vector3(20.5, 1.05, z1 - 0.10), PI)
	Dressing.extinguisher(h, Vector3(-2.0, 1.05, z0 + 0.10), 0.0)
	for x in [3.0, 17.0, 27.0, 39.0]:
		Dressing.poster(h, Vector3(float(x), 1.72, z1 - 0.10), PI, 0.58, 0.80,
			Color(0.35, 0.72, 0.70), 4)
	for x2 in [-9.0, 25.0, 44.0]:
		Dressing.plant(h, Vector3(float(x2), 0, z1 - 0.55), 0.95)
	Dressing.bin(h, Vector3(10.5, 0, z1 - 0.5), Color(0.30, 0.50, 0.58))

static func _dress_lobby(h: Hospital, r: Room) -> void:
	Dressing.noticeboard(h, _far_wall(r, 0.30, 1.70), _far_rot(r), 1.8, 1.1)
	Dressing.wall_art(h, _far_wall(r, 0.72, 1.75), _far_rot(r), 1.10, 0.80,
		Color(0.40, 0.74, 0.86), Color(0.98, 0.66, 0.30))
	Dressing.wall_art(h, _left_wall(r, 0.40, 1.70), LEFT_ROT, 0.80, 0.62,
		Color(0.52, 0.80, 0.60), Color(0.92, 0.46, 0.42))
	Dressing.clock(h, _far_wall(r, 0.50, 2.36), _far_rot(r))
	Dressing.plant(h, Vector3(r.rect.position.x + 1.0, 0, r.rect.position.y + 1.2), 1.15)
	Dressing.plant(h, Vector3(r.rect.end.x - 1.1, 0, r.rect.position.y + 1.4), 0.95)
	Dressing.bin(h, Vector3(r.rect.position.x + 1.2, 0, r.rect.end.y - 1.6))

static func _dress_station(h: Hospital, r: Room) -> void:
	Dressing.noticeboard(h, _far_wall(r, 0.50, 1.68), _far_rot(r), 1.7, 1.05)
	Dressing.poster(h, _left_wall(r, 0.35, 1.66), LEFT_ROT, 0.56, 0.78,
		Color(0.94, 0.66, 0.30), 5)
	Dressing.clock(h, _far_wall(r, 0.16, 2.30), _far_rot(r))
	Dressing.linen(h, Vector3(r.rect.position.x + 0.9, 0.90, r.rect.position.y + 1.2))
	Dressing.trays(h, Vector3(r.rect.end.x - 1.0, 0.90, r.rect.position.y + 1.4))
	Dressing.bin(h, Vector3(r.rect.position.x + 0.9, 0, r.rect.end.y - 1.4))
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, r.rect.end.y - 1.5), 0.85)

static func _dress_treatment(h: Hospital, r: Room) -> void:
	Dressing.oxygen_panel(h, _far_wall(r, 0.30, 1.42), _far_rot(r))
	Dressing.sharps(h, _far_wall(r, 0.58, 1.18), _far_rot(r))
	Dressing.sharps(h, _left_wall(r, 0.45, 1.18), LEFT_ROT)
	Dressing.poster(h, _far_wall(r, 0.76, 1.68), _far_rot(r), 0.62, 0.86,
		Color(0.40, 0.76, 0.72), 6)
	Dressing.curtain(h, Vector3(r.rect.get_center().x, 0,
		r.rect.position.y + r.rect.size.y * 0.34), 2.6, 0.0, Color(0.44, 0.70, 0.78))
	Dressing.trays(h, Vector3(r.rect.position.x + 1.0, 0.90, r.rect.get_center().y))
	Dressing.bin(h, Vector3(r.rect.end.x - 1.0, 0, r.rect.get_center().y + 1.2),
		Color(0.66, 0.34, 0.34))

static func _dress_supply(h: Hospital, r: Room) -> void:
	Dressing.boxes(h, Vector3(r.rect.position.x + 0.9, 0, r.rect.get_center().y - 1.4), 0.3)
	Dressing.boxes(h, Vector3(r.rect.end.x - 1.0, 0, r.rect.get_center().y + 1.6), -0.5)
	Dressing.linen(h, Vector3(r.rect.get_center().x, 0.92, r.rect.position.y + 1.1))
	Dressing.mop_bucket(h, Vector3(r.rect.position.x + 0.8, 0, r.rect.end.y - 1.3), 0.4)
	Dressing.poster(h, _far_wall(r, 0.50, 1.70), _far_rot(r), 0.54, 0.76,
		Color(0.86, 0.62, 0.34), 4)

static func _dress_office(h: Hospital, r: Room) -> void:
	Dressing.wall_art(h, _far_wall(r, 0.36, 1.72), _far_rot(r), 0.94, 0.72,
		Color(0.72, 0.52, 0.86), Color(0.96, 0.80, 0.42))
	Dressing.poster(h, _far_wall(r, 0.74, 1.70), _far_rot(r), 0.52, 0.74,
		Color(0.60, 0.48, 0.86), 5)
	Dressing.clock(h, _left_wall(r, 0.30, 2.28), LEFT_ROT)
	Dressing.plant(h, Vector3(r.rect.end.x - 0.9, 0, r.rect.position.y + 1.2), 1.1)
	Dressing.bin(h, Vector3(r.rect.position.x + 0.9, 0, r.rect.position.y + 1.1),
		Color(0.46, 0.36, 0.30))

static func _dress_bathroom(h: Hospital, r: Room) -> void:
	Dressing.poster(h, _far_wall(r, 0.50, 1.66), _far_rot(r), 0.46, 0.66,
		Color(0.44, 0.74, 0.84), 4)
	Dressing.bin(h, Vector3(r.rect.position.x + 0.7, 0, r.rect.get_center().y),
		Color(0.40, 0.62, 0.70))

static func _dress_intake(h: Hospital, r: Room) -> void:
	Dressing.ceiling_sign(h, Vector3(r.rect.get_center().x, 2.62,
		r.rect.position.y + 1.6), "EMERGENCY INTAKE", 0.0, Color(0.62, 0.22, 0.22))
	Dressing.noticeboard(h, _far_wall(r, 0.28, 1.68), _far_rot(r), 1.6, 1.0)
	Dressing.extinguisher(h, _left_wall(r, 0.30, 1.05), LEFT_ROT)
	Dressing.floor_line(h, r.rect.position.x + 1.0, r.rect.end.x - 1.0,
		r.rect.get_center().y, Color(0.88, 0.32, 0.30), 0.14)
	Dressing.bin(h, Vector3(r.rect.end.x - 1.2, 0, r.rect.end.y - 1.4),
		Color(0.62, 0.30, 0.30))
	Dressing.plant(h, Vector3(r.rect.position.x + 1.2, 0, r.rect.end.y - 1.4), 1.0)

static func _dress_radiology(h: Hospital, r: Room) -> void:
	for i in 3:
		Dressing.poster(h, _far_wall(r, 0.24 + float(i) * 0.24, 1.72), _far_rot(r),
			0.48, 0.66, Color(0.34, 0.52, 0.86), 3)
	Dressing.sharps(h, _left_wall(r, 0.40, 1.15), LEFT_ROT)
	Dressing.bin(h, Vector3(r.rect.end.x - 0.9, 0, r.rect.position.y + 1.2),
		Color(0.34, 0.44, 0.62))

static func _dress_day_room(h: Hospital, r: Room) -> void:
	Dressing.wall_art(h, _far_wall(r, 0.32, 1.72), _far_rot(r), 0.92, 0.70,
		Color(0.96, 0.72, 0.34), Color(0.44, 0.78, 0.62))
	Dressing.wall_art(h, _far_wall(r, 0.70, 1.68), _far_rot(r), 0.76, 0.60,
		Color(0.52, 0.72, 0.92), Color(0.92, 0.52, 0.60))
	Dressing.plant(h, Vector3(r.rect.position.x + 1.1, 0, r.rect.position.y + 1.3), 1.2)
	Dressing.plant(h, Vector3(r.rect.end.x - 1.1, 0, r.rect.position.y + 1.5), 1.0)
	Dressing.bin(h, Vector3(r.rect.position.x + 1.0, 0, r.rect.end.y - 1.5),
		Color(0.72, 0.62, 0.36))

## Record a solid footprint, grown slightly so NPCs keep their shoulders clear.
static func _occupy(centre_x: float, centre_z: float, w: float, d: float) -> void:
	footprints.append(Rect2(centre_x - w * 0.5 - 0.25, centre_z - d * 0.5 - 0.25,
		w + 0.5, d + 0.5))

# ------------------------------------------------------------------ helpers
static func _add(h: Hospital, node: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	h.add_child(node)
	node.position = pos
	node.rotation.y = rot_y
	return node

static func _prop(h: Hospital, id: String, pos: Vector3, rot_y := 0.0) -> Prop:
	var p := Items.spawn(id)
	h.add_child(p)
	p.position = pos
	p.rotation.y = rot_y
	return p

## Simple static furniture: a box with collision, no behaviour.
static func _block(h: Hospital, size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var b := Build.wall(size, color, pos, rot_y)
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

## A rolling cart with loose junk on top. Crashing one is the cheapest, loudest,
## most reliable distraction in the building.
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
	# Loose stock on the top shelf — this is what actually scatters.
	for i in 3:
		_prop(h, ["tray", "pill_bottle", "syringe"][i], pos + Vector3(-0.18 + 0.18 * float(i), 0.75, 0))
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
static func _ward(h: Hospital, r: Room) -> void:
	var c := r.center()
	var far_z := r.rect.position.y + r.rect.size.y      # exterior wall
	var bed_pos := h.bed_position(r.key)

	var bed := PatientBed.new()
	bed.room_key = r.key
	bed.name = "Bed_" + r.key
	h.add_child(bed)
	bed.build()
	bed.position = bed_pos + Vector3(0, 0.4, 0)

	var vc := VitalsConsole.new()
	vc.room_key = r.key
	h.add_child(vc)
	vc.build()
	vc.position = bed_pos + Vector3(-1.0, 1.5, -0.6)

	# Bedside treatment device.
	var m := TreatmentMachine.new()
	m.room_key = r.key
	m.machine_id = "machine_humour"
	m.treatment_id = "humour_rebalance"
	m.units = "HUMOUR GRADIENT"
	h.add_child(m)
	m.build("Humour Rebalancer")
	m.position = bed_pos + Vector3(1.5, 0, -0.2)
	m.rotation.y = PI
	_occupy(bed_pos.x + 1.5, bed_pos.z - 0.2, 1.1, 0.7)

	var rb := MachineRunButton.new()
	rb.room_key = r.key
	h.add_child(rb)
	rb.build(m)
	rb.position = m.position + Vector3(-0.3, 1.05, -0.4)

	var win := WindowUnit.new()
	win.room_key = r.key
	h.add_child(win)
	win.build(1.8, 1.2)
	win.position = Vector3(c.x + 1.6, 1.7, far_z - 0.12)

	var sw := LightSwitch.new()
	sw.room_key = r.key
	h.add_child(sw)
	sw.build()
	sw.position = Vector3(float(h.LAYOUT[0]["rect"].position.x) + 0.0, 0, 0)
	# Beside the door, on the corridor wall.
	sw.position = Vector3(_door_x(r) + 1.1, 1.25, r.rect.position.y + 0.14)
	sw.rotation.y = PI

	var thermo := Thermostat.new()
	thermo.room_key = r.key
	h.add_child(thermo)
	thermo.build()
	thermo.position = Vector3(_door_x(r) + 1.6, 1.25, r.rect.position.y + 0.14)
	thermo.rotation.y = PI

	_chair(h, Vector3(c.x - 2.2, 0, c.z + 1.0), 1.2)
	_table(h, Vector3(c.x - 2.6, 0, c.z - 0.6), 0.5, 0.5)
	_iv_stand(h, bed_pos + Vector3(0.9, 0, -0.9))
	_prop(h, "flowers", Vector3(c.x - 2.6, 0.95, c.z - 0.6))
	_prop(h, "bedpan", bed_pos + Vector3(-1.1, 0.3, 0.9))
	_wall_sign(h, r.display, Vector3(c.x, 2.1, far_z - 0.14), PI, 0.2)

static func _door_x(r: Room) -> float:
	for entry in Hospital.LAYOUT:
		if String(entry["key"]) == r.key:
			return float(entry.get("door", r.rect.get_center().x))
	return r.rect.get_center().x

# ------------------------------------------------------------------ corridor
static func _corridor(h: Hospital, r: Room) -> void:
	var z := r.rect.get_center().y
	_cart(h, Vector3(7.0, 0, z - 1.1), 0.3)
	_cart(h, Vector3(26.5, 0, z + 1.1), -1.9)
	_prop(h, "wet_floor_sign", Vector3(20.0, 0.3, z))
	_prop(h, "mop", Vector3(34.0, 0.3, z + 1.2), 1.1)
	_prop(h, "bucket", Vector3(34.4, 0.3, z + 1.4))
	_prop(h, "extinguisher", Vector3(1.0, 0.3, z + 1.5))
	# Wheelchairs roll. That is the entire feature and it is worth having.
	_prop(h, "wheelchair", Vector3(9.5, 0.55, z + 1.2), 0.4)
	_prop(h, "wheelchair", Vector3(30.5, 0.55, z - 1.2), -1.1)
	_iv_stand(h, Vector3(17.0, 0, z + 1.3))
	# Wayfinding stripes down the floor.
	#
	# Three painted lines along the south side of the corridor, which is exactly
	# what a real hospital does and exactly what this floor was missing: sixty-two
	# metres of unbroken pale blue with nothing on it to measure your own
	# progress against. They also give the eye something to follow towards the
	# far end, which had been reading as a white void.
	var stripes := [
		[0.72, Color(0.16, 0.62, 0.66)],
		[0.88, Color(0.94, 0.68, 0.24)],
		[1.04, Color(0.84, 0.36, 0.44)],
	]
	for st in stripes:
		var strip := Build.box_mi(Vector3(61.0, 0.012, 0.09), st[1],
			Vector3(15.0, 0.008, float(st[0])), 0.5, 0.0)
		h.add_child(strip)

	# Benches along the corridor wall, clear of every doorway.
	#
	# The pair used to sit at 11.0 and 12.4, and ward 102's opening starts at
	# 12.8 — so the second bench was four centimetres of clearance from the
	# doorway a player walking the north wall arrives at, and they caught on it
	# every time. It was the one door of eleven that failed the door harness's
	# lateral approach, and it read for a long time as a fault in the door.
	# North-wing openings are 3.8-5.2, 12.8-14.2, 22.3-23.7, 31.8-33.2 and
	# 40.8-42.2; these sit in the middle of two of the gaps between them.
	for x in [9.4, 10.8, 37.0, 38.4]:
		_chair(h, Vector3(x, 0, z + 1.5), PI)
	_wall_sign(h, "◄  WARDS 101-105        TREATMENT  ►", Vector3(23.0, 2.6, 3.85), PI, 0.16)

	# The day's list, on the corridor wall by the treatment bay. The tablet has
	# the same information; this exists because reading somebody's name off a
	# wall on your way past is a different thing from opening a menu, and
	# because a slot nobody attended keeps their name on it all day in front of
	# everybody who walks by.
	var board := ClinicBoard.new()
	board.room_key = r.key
	h.add_child(board)
	board.build()
	board.position = Vector3(27.0, 1.5, 3.9)
	board.rotation.y = PI

	# ---- west annexe end of the corridor. Deliberately underfurnished: it is
	# meant to look like a part of the hospital that stopped being maintained,
	# which is exactly what the player is buying their way out of.
	_wall_sign(h, "WEST ANNEXE", Vector3(-8.0, 2.6, 3.85), PI, 0.18)
	_wall_sign(h, "◄  INTAKE   RADIOLOGY   DAY ROOM", Vector3(-8.0, 2.25, 3.85), PI, 0.1)
	_prop(h, "wet_floor_sign", Vector3(-2.0, 0.3, z + 1.0))
	_prop(h, "bucket", Vector3(-14.0, 0.3, z - 1.4))
	_cart(h, Vector3(-5.5, 0, z + 1.2), 1.7)
	for x in [-13.0, -11.6]:
		_chair(h, Vector3(x, 0, z + 1.5), PI)

# ------------------------------------------------------------------ lobby
static func _lobby(h: Hospital, r: Room) -> void:
	var c := r.center()
	_block(h, Vector3(3.4, 1.05, 0.7), Color(0.45, 0.52, 0.58), Vector3(c.x - 2.0, 0.52, c.z - 2.4))
	_block(h, Vector3(3.6, 0.08, 0.9), Color(0.62, 0.66, 0.70), Vector3(c.x - 2.0, 1.08, c.z - 2.4))
	_wall_sign(h, "RECEPTION", Vector3(c.x - 2.0, 1.6, c.z - 2.4), 0.0, 0.14)
	for i in 4:
		for j in 2:
			_chair(h, Vector3(c.x + 1.6 + float(j) * 1.4, 0, c.z - 1.5 + float(i) * 0.95), PI * float(j))
	_prop(h, "wheelchair", Vector3(c.x - 3.6, 0.55, c.z + 2.4), 1.9)
	# Vending machine.
	_block(h, Vector3(0.9, 1.9, 0.7), Color(0.75, 0.25, 0.22), Vector3(r.rect.position.x + 0.7, 0.95, c.z + 3.2))
	_wall_sign(h, "OUT OF ORDER\n(since 2019)", Vector3(r.rect.position.x + 0.7, 1.5, c.z + 2.83), 0.0, 0.07)
	# Notice board — where complaints and inspection notices get pinned.
	_block(h, Vector3(1.8, 1.1, 0.08), Color(0.45, 0.35, 0.25), Vector3(c.x + 3.0, 1.6, r.rect.position.y + 0.15))
	_prop(h, "coffee", Vector3(c.x - 2.0, 1.2, c.z - 2.4))
	_wall_sign(h, "ST. ARDENT'S  ·  WARD C", Vector3(c.x, 2.5, r.rect.position.y + 0.16), 0.0, 0.2)

# ------------------------------------------------------------------ station
static func _station(h: Hospital, r: Room) -> void:
	var c := r.center()
	# The back worktop, against the exterior wall.
	_block(h, Vector3(6.0, 1.1, 0.6), Color(0.48, 0.55, 0.58), Vector3(c.x, 0.55, r.rect.position.y + 0.5))
	_block(h, Vector3(6.2, 0.08, 0.85), Color(0.66, 0.70, 0.72), Vector3(c.x, 1.12, r.rect.position.y + 0.5))

	# ...and the counter that actually faces the corridor, in two runs either
	# side of the doorway. The comment above the back worktop used to claim it
	# was this one, and it is at the far wall, ten metres and a partition away
	# from anything: the nurses' station photographed and read as an empty room
	# with a sideboard in it, which is a strange thing for the building's one
	# permanent surveillance post to look like.
	var corridor_z: float = r.rect.position.y + r.rect.size.y - 0.9
	for sx in [c.x - 3.0, c.x + 3.0]:
		_block(h, Vector3(2.4, 1.1, 0.6), Color(0.48, 0.55, 0.58), Vector3(sx, 0.55, corridor_z))
		_block(h, Vector3(2.6, 0.08, 0.9), Color(0.66, 0.70, 0.72), Vector3(sx, 1.12, corridor_z))
		_occupy(sx, corridor_z, 2.6, 0.9)
	_wall_sign(h, "NURSES' STATION", Vector3(c.x - 3.0, 1.55, corridor_z + 0.32), 0.0, 0.13)
	_prop(h, "blank_form", Vector3(c.x + 3.4, 1.22, corridor_z))

	for i in 2:
		var t := RecordsTerminal.new()
		t.room_key = r.key
		t.mode = "ehr"
		h.add_child(t)
		t.build("Ward Terminal", false)
		t.position = Vector3(c.x - 1.4 + float(i) * 2.8, 0.5, c.z - 0.4)
		t.rotation.y = PI
		_occupy(c.x - 1.4 + float(i) * 2.8, c.z - 0.4, 0.7, 0.5)

	_table(h, Vector3(c.x - 2.4, 0, c.z + 2.6), 1.6, 0.8, 0.75)
	_chair(h, Vector3(c.x - 2.4, 0, c.z + 1.8), 0.0)
	_chair(h, Vector3(c.x + 1.2, 0, c.z + 2.4), 2.6)
	# Coffee machine: the single most important object to a nurse's schedule.
	_block(h, Vector3(0.5, 0.6, 0.45), Color(0.30, 0.32, 0.36), Vector3(c.x + 2.6, 1.05, c.z + 3.2))

	# ...and the rest of a room people actually work in.
	#
	# Seen from above with the roof off, this was conspicuously the emptiest
	# room in the building — a counter, two terminals and forty square metres of
	# floor — which is a strange look for the ward's one permanent staffed post
	# and the room every nurse in the game walks back to all day.
	# Filing along the west wall, a rota board over the worktop, a printer that
	# is out of paper, and something alive on the end of the counter.
	for fi in 3:
		var fx: float = r.rect.position.x + 0.55
		var fz: float = c.z - 2.0 + float(fi) * 1.15
		_block(h, Vector3(0.62, 1.32, 1.0), Color(0.52, 0.56, 0.60), Vector3(fx, 0.66, fz))
		for drawer in 3:
			_block(h, Vector3(0.05, 0.06, 0.34), Color(0.30, 0.33, 0.37),
				Vector3(fx + 0.33, 0.34 + 0.38 * float(drawer), fz))
		_occupy(fx, fz, 0.7, 1.0)
	_wall_sign(h, "PERSONNEL", Vector3(r.rect.position.x + 0.2, 1.75, c.z - 0.85), PI * 0.5, 0.085)

	# The rota, over the back worktop. Whiteboard, four ruled lines, permanently
	# out of date.
	var board_z: float = r.rect.position.y + 0.2
	_block(h, Vector3(2.6, 1.2, 0.07), Color(0.93, 0.94, 0.92), Vector3(c.x - 1.4, 1.85, board_z))
	for ln in 4:
		_block(h, Vector3(2.3, 0.03, 0.02), Color(0.62, 0.68, 0.72),
			Vector3(c.x - 1.4, 1.42 + 0.24 * float(ln), board_z + 0.05))
	_wall_sign(h, "TODAY", Vector3(c.x - 1.4, 2.32, board_z + 0.06), 0.0, 0.095)

	# A printer, and the paper it has run out of.
	_block(h, Vector3(0.52, 0.34, 0.44), Color(0.86, 0.87, 0.85),
		Vector3(c.x + 2.2, 1.29, r.rect.position.y + 0.5))
	_block(h, Vector3(0.40, 0.03, 0.30), Build.PAPER,
		Vector3(c.x + 2.2, 1.47, r.rect.position.y + 0.62))
	_prop(h, "blank_form", Vector3(c.x + 1.5, 1.2, r.rect.position.y + 0.55))
	_prop(h, "coffee", Vector3(c.x - 3.6, 1.2, corridor_z))

	# Something alive, in a pot, that somebody is quietly keeping going.
	_block(h, Vector3(0.26, 0.24, 0.26), Color(0.72, 0.46, 0.34),
		Vector3(c.x + 3.9, 1.28, corridor_z))
	h.add_child(Build.mi(Build.sphere_mesh(0.22), Build.mat(Color(0.26, 0.62, 0.34)),
		Vector3(c.x + 3.9, 1.56, corridor_z), Vector3.ZERO, Vector3(1.0, 0.85, 1.0)))
	_table(h, Vector3(c.x + 2.6, 0, c.z + 3.2), 0.8, 0.6, 0.75)
	_wall_sign(h, "COFFEE", Vector3(c.x + 2.6, 1.5, c.z + 2.95), 0.0, 0.08)
	_prop(h, "coffee", Vector3(c.x + 2.2, 0.9, c.z + 3.0))
	_prop(h, "clipboard_blank", Vector3(c.x, 1.2, r.rect.position.y + 0.5))
	_prop(h, "stapler", Vector3(c.x + 0.6, 1.2, r.rect.position.y + 0.5))
	# Records cabinet — physical copies. Investigators love these.
	_block(h, Vector3(1.2, 1.6, 0.5), Color(0.55, 0.57, 0.52), Vector3(r.rect.position.x + 0.8, 0.8, c.z + 3.4))
	_wall_sign(h, "WARD RECORDS", Vector3(r.rect.position.x + 0.8, 1.72, c.z + 3.4), 0.0, 0.07)

# ------------------------------------------------------------------ treatment
static func _treatment(h: Hospital, r: Room) -> void:
	var c := r.center()
	var specs := [
		{"id": "machine_vibe", "t": "vibe_stabilize", "n": "Vibe Stabiliser", "u": "RESONANCE INDEX", "x": -2.6},
		{"id": "machine_dread", "t": "dread_extraction", "n": "Ambient Dread Extractor", "u": "SUCTION GRADE", "x": 1.0},
	]
	for s in specs:
		var m := TreatmentMachine.new()
		m.room_key = r.key
		m.machine_id = String(s["id"])
		m.treatment_id = String(s["t"])
		m.units = String(s["u"])
		h.add_child(m)
		m.build(String(s["n"]))
		m.position = Vector3(c.x + float(s["x"]), 0, r.rect.position.y + 1.0)
		_occupy(c.x + float(s["x"]), r.rect.position.y + 1.0, 1.1, 0.7)
		var rb := MachineRunButton.new()
		rb.room_key = r.key
		h.add_child(rb)
		rb.build(m)
		rb.position = m.position + Vector3(0.7, 1.05, 0.4)

	# The imaging bench used to appear here the moment Radiology was bought.
	# It now lives in Radiology, which is a room, which you have to walk to.

	var shelf := SupplyShelf.new()
	shelf.room_key = r.key
	h.add_child(shelf)
	shelf.build("Treatment Stock",
		["syringe", "iv_bag", "compress", "splint", "sling", "mallet", "wrench", "duster"])
	shelf.position = Vector3(r.rect.position.x + 1.2, 0, c.z + 3.2)
	# +PI/2. Same bug as the three units in the supply room: a shelf's front is
	# its local +Z, and -90 degrees about Y turns that into the wall behind it.
	shelf.rotation.y = PI / 2
	_occupy(r.rect.position.x + 1.2, c.z + 3.2, 0.6, 1.8)

	_table(h, Vector3(c.x + 2.6, 0, c.z + 2.0), 1.2, 0.7)
	_prop(h, "tray", Vector3(c.x + 2.6, 0.85, c.z + 2.0))
	_prop(h, "dread_canister", Vector3(c.x + 1.6, 0.4, r.rect.position.y + 1.9))
	_cart(h, Vector3(c.x + 3.0, 0, c.z - 1.0), 1.4)
	# The waiting row, along the west wall, facing into the room.
	for i in 5:
		var seat := Vector3(r.rect.position.x + 1.1, 0, c.z - 3.2 + float(i) * 1.15)
		_chair(h, seat, PI / 2, Color(0.34, 0.40, 0.46))
		clinic_seats.append(seat)
	_wall_sign(h, "PLEASE WAIT TO BE CALLED",
		Vector3(r.rect.position.x + 0.18, 1.9, c.z - 3.6), PI / 2, 0.075)

	# A scrub sink, a bin, and a wall chart nobody reads. The bay had two
	# machines and a lot of floor, and it is the room the player spends the
	# second-most time in.
	var sink_x: float = r.rect.position.x + r.rect.size.x - 1.3
	_block(h, Vector3(1.1, 0.86, 0.6), Color(0.60, 0.64, 0.68), Vector3(sink_x, 0.43, c.z - 2.6))
	_block(h, Vector3(1.15, 0.10, 0.65), Color(0.88, 0.90, 0.92), Vector3(sink_x, 0.91, c.z - 2.6))
	_block(h, Vector3(0.62, 0.07, 0.40), Color(0.72, 0.78, 0.82), Vector3(sink_x, 0.95, c.z - 2.6))
	h.add_child(Build.cyl_mi(0.022, 0.34, Build.METAL,
		Vector3(sink_x, 1.12, c.z - 2.85), 8))
	_occupy(sink_x, c.z - 2.6, 1.2, 0.7)
	_block(h, Vector3(0.42, 0.62, 0.42), Color(0.24, 0.30, 0.36), Vector3(sink_x - 0.95, 0.31, c.z - 2.6))
	_wall_sign(h, "WASH YOUR HANDS\n(all of them)",
		Vector3(sink_x, 1.62, r.rect.position.y + r.rect.size.y * 0.5 - 3.0), 0.0, 0.075)

	# A folding privacy screen, parked against the wall the way they always are.
	for pi in 3:
		_block(h, Vector3(0.05, 1.65, 0.62), Color(0.62, 0.74, 0.76),
			Vector3(sink_x + 0.4 - 0.09 * float(pi), 0.86, c.z + 1.2 + 0.04 * float(pi)))

	_wall_sign(h, "TREATMENT BAY", Vector3(c.x, 2.4, r.rect.position.y + 0.16), 0.0, 0.18)

# ------------------------------------------------------------------ supply
static func _supply(h: Hospital, r: Room) -> void:
	var c := r.center()
	var stock := [
		# splint and sling are the tools for Splinting and Sling Support. They
		# were defined, meshed, priced and printed on the chart as INDICATED —
		# and stocked nowhere in the building, so the only two treatments for a
		# fracture could not be given by anybody.
		["General Stock", ["compress", "blanket", "splint", "sling", "pillow", "bedpan",
			"thermometer", "duster"], false],
		["Pharmacy Stock", ["syringe", "pill_bottle", "iv_bag", "placebex_kit"], true],
		["Forms & Stationery", ["blank_form", "clipboard_blank", "stapler"], false],
	]
	for i in stock.size():
		var s: Array = stock[i]
		var shelf := SupplyShelf.new()
		shelf.room_key = r.key
		shelf.restricted = bool(s[2])
		h.add_child(shelf)
		var items: Array = s[1]
		# Drop any ids that don't exist yet rather than spawning magenta cubes.
		var valid: Array = []
		for it in items:
			if Items.SPECS.has(String(it)):
				valid.append(it)
		shelf.build(String(s[0]), valid)
		shelf.position = Vector3(r.rect.position.x + 0.5, 0, c.z - 2.4 + float(i) * 2.4)
		# +PI/2, not -PI/2. A shelf's front is its local +Z, and rotating -90
		# degrees about Y sends +Z to -X — straight into the wall it is standing
		# against. All three units in the room the game sends you to for
		# equipment were facing the wall, showing the room their backs.
		shelf.rotation.y = PI / 2
		_occupy(r.rect.position.x + 0.5, c.z - 2.4 + float(i) * 2.4, 0.6, 1.8)

	_prop(h, "colour_lamp", Vector3(c.x + 1.4, 0.4, c.z - 1.0))
	_prop(h, "steam_kit", Vector3(c.x + 1.4, 0.4, c.z + 0.2))
	_prop(h, "extinguisher", Vector3(c.x + 1.6, 0.4, c.z + 2.6))
	_cart(h, Vector3(c.x + 1.0, 0, c.z + 3.4), 0.2)
	_wall_sign(h, "SUPPLY", Vector3(c.x, 2.4, r.rect.position.y + 0.16), 0.0, 0.16)

# ------------------------------------------------------------------ office
static func _office(h: Hospital, r: Room) -> void:
	var c := r.center()
	_table(h, Vector3(c.x, 0, c.z + 1.0), 2.0, 1.0, 0.75, Color(0.42, 0.30, 0.22))
	_chair(h, Vector3(c.x, 0, c.z + 2.0), 0.0, Color(0.30, 0.26, 0.28))

	var t := RecordsTerminal.new()
	t.room_key = r.key
	t.mode = "admin"
	h.add_child(t)
	t.build("Your Terminal", true)
	t.position = Vector3(c.x - 0.3, 0.55, c.z + 0.7)
	_occupy(c.x - 0.3, c.z + 0.7, 0.7, 0.5)

	var sh := Shredder.new()
	sh.room_key = r.key
	h.add_child(sh)
	sh.build()
	sh.position = Vector3(c.x + 1.8, 0, c.z + 1.6)
	_occupy(c.x + 1.8, c.z + 1.6, 0.6, 0.5)

	_block(h, Vector3(1.0, 1.5, 0.5), Color(0.5, 0.52, 0.48), Vector3(r.rect.position.x + 0.8, 0.75, c.z - 2.4))
	_wall_sign(h, "PERSONAL FILES", Vector3(r.rect.position.x + 0.8, 1.62, c.z - 2.4), 0.0, 0.07)

	var win := WindowUnit.new()
	win.room_key = r.key
	h.add_child(win)
	win.build(1.4, 1.0)
	win.position = Vector3(c.x, 1.7, r.rect.position.y + 0.12)

	_prop(h, "coffee", Vector3(c.x + 0.6, 0.9, c.z + 1.0))
	_prop(h, "incident_report", Vector3(c.x - 0.6, 0.9, c.z + 1.3))
	# The debt letters. Purely narrative, entirely load-bearing.
	_wall_sign(h, "FINAL NOTICE\nFINAL NOTICE\nFINAL NOTICE", Vector3(c.x + 2.2, 1.5, c.z - 2.0), 0.0, 0.075)
	_wall_sign(h, "DR. YOU", Vector3(c.x, 2.3, r.rect.position.y + 0.14), 0.0, 0.15)

# ------------------------------------------------------------------ bathroom
static func _bathroom(h: Hospital, r: Room) -> void:
	var c := r.center()
	for i in 3:
		_block(h, Vector3(0.5, 0.2, 0.42), Color(0.92, 0.93, 0.95),
			Vector3(r.rect.position.x + 0.9, 0.85, c.z - 1.6 + float(i) * 1.1))
	_wall_sign(h, "STAFF ONLY", Vector3(c.x, 2.3, r.rect.position.y + 0.16), 0.0, 0.12)
	# Stalls: the only place in the building with no line of sight at all.
	for i in 2:
		var x := c.x + 0.9
		var z := c.z + 1.4 + float(i) * 1.5
		_block(h, Vector3(1.4, 2.0, 0.08), Color(0.55, 0.62, 0.60), Vector3(x, 1.0, z - 0.7))
		_block(h, Vector3(0.08, 2.0, 1.4), Color(0.55, 0.62, 0.60), Vector3(x + 0.7, 1.0, z))
		_block(h, Vector3(0.42, 0.42, 0.42), Color(0.92, 0.93, 0.95), Vector3(x, 0.21, z))
	_prop(h, "mop", Vector3(c.x - 1.2, 0.3, c.z + 3.0), 0.6)

# ------------------------------------------------------------------ annexe
## Emergency Intake. Wide, loud, and full of people who did not choose to be
## here — the opposite of the quiet ward, and the point of buying it.
static func _intake(h: Hospital, r: Room) -> void:
	var c := r.center()
	var west := r.rect.position.x
	var east := r.rect.position.x + r.rect.size.x
	var far := r.rect.position.y + r.rect.size.y

	# Triage desk, set well back from the doorway and facing it. Everything in
	# this room is arranged to be read from the corridor door at z = 4.
	_block(h, Vector3(4.2, 1.05, 0.8), Color(0.48, 0.44, 0.40), Vector3(c.x, 0.52, c.z + 1.2))
	_block(h, Vector3(4.4, 0.08, 1.0), Color(0.66, 0.62, 0.56), Vector3(c.x, 1.08, c.z + 1.2))
	_wall_sign(h, "TRIAGE", Vector3(c.x, 1.6, c.z + 0.75), PI, 0.11)
	_chair(h, Vector3(c.x, 0, c.z + 2.2), PI, Color(0.32, 0.36, 0.42))

	var term := RecordsTerminal.new()
	term.room_key = r.key
	term.mode = "ward"
	h.add_child(term)
	term.build("Intake Terminal", false)
	term.position = Vector3(c.x - 1.5, 0.55, c.z + 1.3)
	term.rotation.y = PI
	_occupy(c.x, c.z + 1.2, 4.4, 1.0)

	# Trolleys down the east side. These are REAL beds, on wheels, in the bed
	# group — so when the ward is full an admission physically lands on one of
	# them, and anybody can push it anywhere. A corridor is a place you can
	# legitimately put a patient, and the game does not distinguish between
	# doing that because there was no room and doing it on purpose.
	for i in 3:
		var trolley := PatientBed.new()
		trolley.room_key = r.key
		trolley.name = "Trolley_%d" % i
		h.add_child(trolley)
		trolley.build()
		var z := r.rect.position.y + 2.0 + float(i) * 2.6
		trolley.position = Vector3(east - 2.4, 0.4, z)
		trolley.rotation.y = PI / 2
		_occupy(east - 2.4, z, 2.4, 1.3)
		_iv_stand(h, Vector3(east - 3.9, 0, z))

	# Waiting chairs along the west wall, facing nothing in particular.
	for i in 5:
		_chair(h, Vector3(west + 1.1, 0, r.rect.position.y + 1.6 + float(i) * 1.1), PI / 2)

	var shelf := SupplyShelf.new()
	shelf.room_key = r.key
	h.add_child(shelf)
	shelf.build("Intake Stock", ["compress", "blanket", "syringe", "clipboard_blank"])
	shelf.position = Vector3(east - 0.6, 0, far - 1.6)
	shelf.rotation.y = PI / 2
	_occupy(east - 0.6, far - 1.6, 0.6, 1.8)

	_cart(h, Vector3(c.x + 2.8, 0, c.z + 2.6), 1.1)
	_prop(h, "wheelchair", Vector3(west + 2.6, 0.55, r.rect.position.y + 1.4), 0.7)
	_prop(h, "extinguisher", Vector3(west + 0.6, 0.3, far - 1.0))

	# The ambulance bay. Purely a backdrop — it is on the exterior wall and the
	# player never goes through it — but a room with no way in but the corridor
	# does not read as an emergency department.
	_block(h, Vector3(4.4, 2.4, 0.12), Color(0.44, 0.46, 0.50), Vector3(c.x + 2.0, 1.2, far - 0.2))
	_wall_sign(h, "▲  AMBULANCE BAY  ▲", Vector3(c.x + 2.0, 2.62, far - 0.32), PI, 0.17)
	_wall_sign(h, "DAYS SINCE LAST INCIDENT:  0", Vector3(c.x - 3.6, 2.3, far - 0.17), PI, 0.13)
	_wall_sign(h, "EMERGENCY INTAKE", Vector3(c.x + 3.2, 2.5, r.rect.position.y + 0.17), PI, 0.16)

	var win := WindowUnit.new()
	win.room_key = r.key
	h.add_child(win)
	win.build(2.0, 1.1)
	win.position = Vector3(c.x - 4.5, 1.8, far - 0.12)

	var t := Thermostat.new()
	t.room_key = r.key
	h.add_child(t)
	t.build()
	t.position = Vector3(west + 0.22, 1.45, r.rect.position.y + 7.6)
	t.rotation.y = PI / 2

## Radiology. The imaging bench used to appear in the treatment bay the instant
## the upgrade was bought. Putting it in a room of its own costs the player a
## walk, which is the whole difference between "a button I have" and "a thing I
## have to decide is worth leaving the ward for".
static func _radiology(h: Hospital, r: Room) -> void:
	var c := r.center()
	# The doorway is at z = 0, on the corridor side, so the room is laid out to
	# be READ from there: gantry at the far end, bench in front of it, control
	# booth off to one side. Walking in should tell you what the room is for.
	var lane := c.x + 0.8

	# The gantry. A square bore rather than a ring of loose boxes: at this
	# fidelity a circle made of cubes reads as debris, and a frame reads as
	# equipment.
	var bore := 1.25
	var ring_z := r.rect.position.y + 1.9
	var shell := Color(0.84, 0.86, 0.89)
	_block(h, Vector3(bore * 2.0 + 1.2, 0.6, 1.1), shell, Vector3(lane, bore * 2.0 + 0.3, ring_z))
	for sx in [-1.0, 1.0]:
		_block(h, Vector3(0.6, bore * 2.0, 1.1), shell,
			Vector3(lane + sx * (bore + 0.3), bore, ring_z))
	_block(h, Vector3(bore * 2.0 + 1.2, 0.35, 1.1), shell.darkened(0.15),
		Vector3(lane, 0.18, ring_z))
	# The bore itself, dark, so the hole reads as a hole.
	h.add_child(Build.box_mi(Vector3(bore * 2.0, bore * 1.7, 0.9),
		Color(0.10, 0.11, 0.13), Vector3(lane, bore * 0.95, ring_z)))
	_occupy(lane, ring_z, bore * 2.0 + 1.2, 1.1)

	# The couch that slides through it, and the bench you actually operate.
	_block(h, Vector3(0.9, 0.55, 2.4), Color(0.72, 0.74, 0.78), Vector3(lane, 0.62, ring_z + 2.2))
	_block(h, Vector3(0.85, 0.10, 2.3), Build.LINEN, Vector3(lane, 0.94, ring_z + 2.2))
	_occupy(lane, ring_z + 2.2, 0.9, 2.4)

	var img := TreatmentMachine.new()
	img.room_key = r.key
	img.machine_id = "machine_imaging"
	img.treatment_id = "imaging"
	img.units = "APERTURE DEPTH"
	h.add_child(img)
	img.build("Imaging Bench")
	img.position = Vector3(r.rect.position.x + r.rect.size.x - 1.3, 0, c.z + 0.4)
	img.rotation.y = -PI / 2
	_occupy(r.rect.position.x + r.rect.size.x - 1.3, c.z + 0.4, 0.7, 1.1)

	var rb := MachineRunButton.new()
	rb.room_key = r.key
	h.add_child(rb)
	rb.build(img)
	rb.position = img.position + Vector3(-0.4, 1.05, 0.7)

	# Control booth: a screen wall with a viewing window, in the near corner.
	# Standing behind it is the one spot in the department where nobody in the
	# room can see your hands.
	var bx := r.rect.position.x + 2.3
	_block(h, Vector3(0.14, 1.05, 3.0), Color(0.46, 0.50, 0.54), Vector3(bx, 0.52, c.z + 2.6))
	_block(h, Vector3(0.14, 0.75, 3.0), Color(0.46, 0.50, 0.54), Vector3(bx, 2.02, c.z + 2.6))
	h.add_child(Build.box_mi(Vector3(0.06, 0.9, 2.9), Color(0.55, 0.72, 0.78, 1.0),
		Vector3(bx, 1.55, c.z + 2.6)))
	_block(h, Vector3(1.9, 1.05, 0.7), Color(0.44, 0.48, 0.52), Vector3(bx - 1.1, 0.52, c.z + 1.4))
	_block(h, Vector3(2.0, 0.08, 0.9), Color(0.60, 0.64, 0.68), Vector3(bx - 1.1, 1.08, c.z + 1.4))

	var term := RecordsTerminal.new()
	term.room_key = r.key
	term.mode = "ward"
	h.add_child(term)
	term.build("Imaging Console", false)
	term.position = Vector3(bx - 1.1, 0.55, c.z + 1.3)
	_occupy(bx - 1.1, c.z + 1.4, 2.0, 0.9)

	# Lead aprons on a rack. Nobody in this building has ever worn one.
	for i in 3:
		_block(h, Vector3(0.14, 1.0, 0.5), Color(0.28, 0.30, 0.36),
			Vector3(r.rect.position.x + 0.4, 1.1, c.z - 1.0 + float(i) * 0.7))
	_wall_sign(h, "APRONS", Vector3(r.rect.position.x + 0.55, 1.85, c.z - 0.3), PI / 2, 0.075)

	# On the east wall, not the far one: the gantry stands in front of the far
	# wall and would hide anything written on it.
	var east := r.rect.position.x + r.rect.size.x - 0.17
	_wall_sign(h, "CONTROLLED AREA\nDO NOT ENTER WHEN LIT\n(bulb on order)",
		Vector3(east, 1.7, c.z - 2.2), -PI / 2, 0.075)
	_wall_sign(h, "RADIOLOGY", Vector3(east, 2.5, c.z - 3.6), -PI / 2, 0.16)
	_prop(h, "clipboard_blank", Vector3(bx - 1.1, 1.2, c.z + 1.6))

	var t := Thermostat.new()
	t.room_key = r.key
	h.add_child(t)
	t.build()
	t.position = Vector3(r.rect.position.x + r.rect.size.x - 0.22, 1.45, c.z - 3.4)
	t.rotation.y = -PI / 2

## The Psych Day Room. These patients recover on comfort rather than kit, so
## this is the only room in the building where the FURNITURE is the treatment —
## and therefore the only room where rearranging it is a medical intervention.
static func _day_room(h: Hospital, r: Room) -> void:
	var c := r.center()

	# A ring of armchairs, because someone read that circles are therapeutic.
	for i in 6:
		var a := TAU * float(i) / 6.0
		_chair(h, Vector3(c.x + cos(a) * 1.9, 0, c.z + sin(a) * 1.9), a + PI,
			Color(0.46, 0.38, 0.52))
	_table(h, Vector3(c.x, 0, c.z), 1.1, 1.1, 0.42, Color(0.50, 0.38, 0.28))
	_prop(h, "tray", Vector3(c.x, 0.55, c.z))

	# The television. Mounted too high, permanently on a channel nobody chose.
	_block(h, Vector3(1.5, 0.9, 0.12), Color(0.12, 0.13, 0.15), Vector3(c.x, 1.85, r.rect.position.y + 0.2))
	_wall_sign(h, "~ daytime television ~", Vector3(c.x, 1.85, r.rect.position.y + 0.28), 0.0, 0.075)

	# Bookcase, with the good books already taken.
	_block(h, Vector3(0.4, 1.8, 1.8), Color(0.46, 0.34, 0.24), Vector3(r.rect.position.x + 0.5, 0.9, c.z + 1.2))
	_wall_sign(h, "LIBRARY", Vector3(r.rect.position.x + 0.85, 1.9, c.z + 1.2), PI / 2, 0.08)

	# The jigsaw. It is missing a piece and everyone knows which one.
	_table(h, Vector3(c.x + 2.2, 0, c.z - 3.0), 1.2, 0.8, 0.72, Color(0.66, 0.60, 0.50))
	_chair(h, Vector3(c.x + 2.2, 0, c.z - 3.9), 0.0, Color(0.40, 0.44, 0.40))
	_wall_sign(h, "1000 PIECES\n(999)", Vector3(c.x + 2.2, 0.85, c.z - 3.0), 0.0, 0.06)

	_prop(h, "colour_lamp", Vector3(c.x - 2.4, 0.4, c.z - 2.8))
	_prop(h, "coffee", Vector3(c.x - 2.6, 0.9, c.z + 3.0))
	_block(h, Vector3(0.6, 1.2, 0.6), Color(0.30, 0.45, 0.28), Vector3(c.x + 2.8, 0.6, c.z + 3.2))
	_wall_sign(h, "DAY ROOM", Vector3(c.x, 2.6, r.rect.position.y + 0.16), 0.0, 0.16)

	var win := WindowUnit.new()
	win.room_key = r.key
	h.add_child(win)
	win.build(2.2, 1.2)
	win.position = Vector3(c.x, 1.8, r.rect.position.y + 0.12)

	# Comfort is the treatment here, so the two controls that set comfort are
	# both in the room and both worth reaching.
	var t := Thermostat.new()
	t.room_key = r.key
	h.add_child(t)
	t.build()
	t.position = Vector3(r.rect.position.x + r.rect.size.x - 0.22, 1.45, c.z - 3.4)
	t.rotation.y = -PI / 2

	var sw := LightSwitch.new()
	sw.room_key = r.key
	h.add_child(sw)
	sw.build()
	sw.position = Vector3(r.rect.position.x + r.rect.size.x - 0.22, 1.3, c.z - 2.4)
	sw.rotation.y = -PI / 2
