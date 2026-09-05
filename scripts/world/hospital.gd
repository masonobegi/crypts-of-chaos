class_name Hospital
extends Node3D
## Procedurally assembles the whole floor from the LAYOUT table below, then
## bakes navigation over it. Adding a room is one entry plus a furniture recipe;
## nothing else in the game needs to know the floor plan changed.

const WALL_H := 3.2
const WALL_T := 0.16
const DOOR_W := 1.4

## The glazing band on an exterior wall. The sill is high enough that a bed
## goes under it rather than in front of it, and the head is below the picture
## rail so the window sits in the part of the wall that carried nothing.
const WIN_SILL := 1.05
const WIN_HEAD := 2.30
## Runs shorter than this get no window: a stub of exterior wall with a pane in
## it reads as a mistake rather than as a building.
const WIN_MIN_RUN := 2.2
## Mullion spacing. Real hospital glazing is a repeating bay; one unbroken pane
## twenty metres long reads as a missing wall.
const WIN_BAY := 1.9

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
	_build_outside()
	_build_doors()
	_build_signage()
	# Furniture must exist before navigation is baked: NPCs were previously
	# pathing straight through desks, shelves and beds, and a nurse who spawned
	# behind the station counter never went anywhere again.
	var blocked := Furniture.furnish(self)
	_bake_nav(blocked)
	Log.i("hospital built: %d rooms, %d nav cells" % [rooms.size(), nav.cell_count()], "Hospital")

# ------------------------------------------------------------------ outside
## SOMETHING TO LOOK AT, BEFORE THERE IS ANYTHING TO LOOK THROUGH.
##
## The project builds a full procedural sky — sun angle, horizon and ground
## colours, re-tinted every minute as the shift runs — and nothing in the game
## can see it, because the building has no windows. Glazing was tried first and
## reverted, and the reason is the useful part: with nothing outside, a window
## at eye level fills with the sky's GROUND hemisphere, which is a flat murky
## green, and reads as glazing painted over with sage. The view has to exist
## before the glass does.
##
## Everything here is scenery in the strictest sense — no collision, no
## navigation footprint, no outline — and all of it sits outside the building
## footprint (x 0..20, z -8..13) except the ground, which passes underneath at a
## level below the floor slabs so it can never be seen from inside except
## through an opening.
##
## Aerial perspective is BAKED INTO THE COLOURS rather than done with fog. Fog
## is deliberately off in this project — a sixty-two metre corridor with haze in
## it was the single biggest reason the far end read as a bad place to be — so
## distance is carried by desaturating toward the sky instead.
const OUTSIDE_GROUP := "outside"

func _build_outside() -> void:
	var ground := Color(0.47, 0.58, 0.42)
	var apron := Color(0.60, 0.61, 0.58)
	var boundary := Color(0.38, 0.47, 0.36)
	var trees := Color(0.35, 0.47, 0.40)
	var far_block := Color(0.66, 0.70, 0.75)

	# The ground, well below the floor slabs (which span -0.2..0.0) so the two
	# never fight for the same pixel. Big enough that its own edge is past the
	# horizon from any window.
	_outside(Build.box_mi(Vector3(400, 0.6, 400), ground,
		Vector3(10.0, -0.75, 2.5), 0.95, 0.0))
	_outside(Build.box_mi(Vector3(50, 0.5, 50), apron,
		Vector3(10.0, -0.62, 2.5), 0.9, 0.0))

	# A WINDOW SHOWS A NARROW SLICE OF THE WORLD, and everything below is
	# placed to land inside it. From an eye at 1.7m the aperture spans roughly
	# three degrees below the horizontal to nine above, so anything close is
	# cut off at the knees and anything short is under the sill. Three rings at
	# three depths, each sized so its VISIBLE part falls in that band:
	# a boundary you look over, a treeline that breaks the horizon, and massing
	# behind it far enough away to fit inside nine degrees.
	#
	# Rings rather than the six scattered blocks this started as. A window on
	# any of four walls has to find something to look at, and scattered massing
	# means three of them see an empty field.
	for i in 44:
		var t := float(i) / 44.0
		var a := t * TAU
		var w := sin(float(i) * 2.3) * 0.5 + 0.5
		var w2 := sin(float(i) * 1.7 + 1.1) * 0.5 + 0.5

		# The boundary of the grounds, low and close: it sits along the bottom
		# of the glass and is what gives the view a near edge to measure from.
		var rb: float = 12.5 + w * 1.5
		_outside(Build.box_mi(Vector3(3.4, 1.0 + w * 0.5, 1.0), boundary,
			Vector3(10.0 + cos(a) * rb, 0.1, 2.5 + sin(a) * rb), 0.95, 0.0))

		# The treeline. Far enough back that the tops stay under the window
		# head, dense enough to read as a line rather than as shrubs.
		var rt: float = 42.0 + w2 * 9.0
		var ht: float = 6.5 + w * 3.0
		_outside(Build.box_mi(Vector3(9.0 + w * 5.0, ht, 7.0 + w2 * 4.0), trees,
			Vector3(10.0 + cos(a + 0.07) * rt, ht * 0.5 - 0.6,
				2.5 + sin(a + 0.07) * rt), 0.95, 0.0))

	# And the town behind it: a ring of pale slabs at a distance where a
	# fifteen-metre building fits inside the nine degrees a window gives you.
	for i in 20:
		var a := (float(i) / 20.0) * TAU + 0.16
		var w := sin(float(i) * 3.1) * 0.5 + 0.5
		var rr: float = 88.0 + w * 26.0
		var hh: float = 11.0 + w * 9.0
		var at := Vector3(10.0 + cos(a) * rr, hh * 0.5 - 0.5, 2.5 + sin(a) * rr)
		_outside(Build.box_mi(Vector3(20.0 + w * 18.0, hh, 18.0), far_block, at, 0.9, 0.0))
		# A darker band at the base, which is all it takes for a slab to read
		# as standing on the ground rather than floating in front of it.
		_outside(Build.box_mi(Vector3(21.0 + w * 18.0, 1.8, 19.0),
			far_block.darkened(0.20), at - Vector3(0, hh * 0.5 - 0.9, 0), 0.9, 0.0))

## Scenery, and answering to one name so a test can find all of it.
func _outside(n: Node3D) -> Node3D:
	n.add_to_group(OUTSIDE_GROUP)
	add_child(n)
	return n

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
	# THE FLOOR HAS A SURFACE ON IT NOW. Twenty metres of one flat pale green
	# was the single biggest reason a room read as a diagram: `Surfaces.floor_mat`
	# is speckled vinyl in two-metre welded sheets with a polish that catches the
	# ceiling fittings, computed from world position so it runs continuously
	# from room to room and needs no UVs (which matters — `rbox_mesh` is a
	# Minkowski-summed sphere and its UVs tile like nothing on earth).
	# The rect is passed so the shader can darken the floor as it approaches
	# each wall — the other half of the contact shading the wall already has on
	# its own side, and the thing that stops a room reading as a coloured plane
	# with walls standing on it.
	var f := Build.surfaced_wall(size,
		Surfaces.floor_mat(tint, 2.0, r.rect.position, r.rect.end), Vector3(0, -0.1, 0))
	f.name = "Floor"
	r.add_child(f)
	# Ceiling is visual only — no collision, so thrown objects leave the room and
	# the player can never get stuck against it.
	var c := Build.mi(Build.rbox_mesh(Vector3(r.rect.size.x, 0.1, r.rect.size.y), 0.02),
		Surfaces.ceiling_mat(Build.CEILING), Vector3(0, WALL_H, 0))
	# Tagged, because "the only bare MeshInstance3D parented to a Room" stopped
	# being a safe way to find a ceiling the moment floor borders were added.
	c.set_meta("is_ceiling", true)
	r.add_child(c)
	# `_ceiling_grid` used to lay thin boxes across this plane to suggest tiles.
	# The shader draws the runners now — antialiased against the screen-space
	# derivative, so they fade with distance instead of turning into the white
	# wireframe the geometry version became at a grazing angle.

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
	# `_floor_seams` laid a thin box every two metres for the same reason, and
	# the shader draws those too, continuously across room boundaries.

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

## ONE FITTING EVERY THREE AND A HALF METRES, not every five.
##
## A twenty-by-nine ward got four fittings, all of them on its centre line, and
## that was survivable only while every surface in the building was shaded with
## sphere normals — geometry whose normal wanders catches light from everywhere
## and hides how little of it there is. With the normals corrected the ward went
## honest and showed what it had: two bright pools and a lot of dark floor.
## Five by two is what a real bay of this size carries.
func _build_room_lights(r: Room) -> void:
	var cols := maxi(1, int(round(r.rect.size.x / 3.6)))
	var rows := maxi(1, int(round(r.rect.size.y / 3.6)))
	for i in cols:
		for j in rows:
			var x := r.rect.position.x + r.rect.size.x * (float(i) + 0.5) / float(cols)
			var z := r.rect.position.y + r.rect.size.y * (float(j) + 0.5) / float(rows)
			# Tighter range as well as more of them: a short throw keeps each
			# shadow frustum small, which is both cheaper and sharper than one
			# big one, and overlapping pools are what an even ceiling looks like.
			# FLUSH WITH THE CEILING. The fitting hung 14cm below the plane it
			# is supposed to be recessed into — a slab floating under the
			# ceiling with a gap of daylight over it, which is visible in every
			# wide shot of the ward and is not how a troffer is fitted. The
			# housing is 10cm deep and sits 5mm above its root, so the root
			# goes 10.5cm under the ceiling and the top of the housing lands on
			# the plasterboard.
			var lamp := Build.ceiling_light(
				Vector3(x, WALL_H - 0.105, z) - r.center(), 0.62, Color(1.0, 0.97, 0.90), 6.6)
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
				# BOTH HALVES OF THE FITTING. A ceiling light is a shadowed
				# spot plus an unshadowed omni fill now, and re-tinting only the
				# omni left every cone in the building on the morning's colour
				# for the whole of the evening.
				if l is Light3D:
					(l as Light3D).light_color = colour
					# ...AND THE SAME SPLIT THE FITTING WAS BUILT WITH. This
					# line was `(l as OmniLight3D).light_energy = energy`, which
					# on the spot half casts to null and then assigns to it —
					# a runtime error that ABORTS THE FUNCTION (CLAUDE.md 11),
					# so the first fitting in the first room would have taken
					# the whole evening re-light down with it.
					(l as Light3D).light_energy = energy * (Build.SPOT_GAIN
						if l is SpotLight3D else Build.FILL_GAIN)
				elif l is MeshInstance3D:
					# The visible fitting matches the light coming out of it —
					# and stays a LIT PANEL while it does. This line handed it
					# `Build.unshaded`, which is not emissive, so re-tinting the
					# lamps at any point in the day quietly took the one object
					# in an interior that is supposed to bloom out of the glow
					# pass. Only the panel is re-tinted; the housing is a
					# ShaderMaterial and fails the cast, which is what we want.
					if (l as MeshInstance3D).material_override is StandardMaterial3D:
						(l as MeshInstance3D).material_override = Build.lit_panel(colour)

# ------------------------------------------------------------------ shell
func _build_shell() -> void:
	var north_gaps := _gaps_for(["ward"])
	var south_gaps := _gaps_for(["station", "office"])

	# Walls running along X.
	_wall_along_x(13.0, 0.0, 20.0, [], true)       # north exterior
	_wall_along_x(4.0, 0.0, 20.0, north_gaps)      # corridor <-> ward
	_wall_along_x(0.0, 0.0, 20.0, south_gaps)      # corridor <-> station, office
	_wall_along_x(-8.0, 0.0, 20.0, [], true)       # south exterior

	# Walls running along Z.
	_wall_along_z(0.0, -8.0, 13.0, [], true)       # west exterior
	_wall_along_z(20.0, -8.0, 13.0, [], true)      # east exterior
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
func _wall_along_x(z: float, x0: float, x1: float, gaps: Array, exterior := false) -> void:
	var cursor := x0
	for g in gaps:
		var gap: Vector2 = g
		if gap.x > cursor:
			_wall_segment(Vector3(cursor, 0, z), Vector3(gap.x, 0, z), exterior)
		# Lintel above the doorway so you can't see over it and it reads as a door.
		_lintel(Vector3(gap.x, 0, z), Vector3(gap.y, 0, z))
		cursor = maxf(cursor, gap.y)
	if cursor < x1:
		_wall_segment(Vector3(cursor, 0, z), Vector3(x1, 0, z), exterior)

func _wall_along_z(x: float, z0: float, z1: float, gaps: Array, exterior := false) -> void:
	var cursor := z0
	for g in gaps:
		var gap: Vector2 = g
		if gap.x > cursor:
			_wall_segment(Vector3(x, 0, cursor), Vector3(x, 0, gap.x), exterior)
		_lintel(Vector3(x, 0, gap.x), Vector3(x, 0, gap.y))
		cursor = maxf(cursor, gap.y)
	if cursor < z1:
		_wall_segment(Vector3(x, 0, cursor), Vector3(x, 0, z1), exterior)

## `exterior` glazes it — see `_glaze`. Only the four runs of the outer shell
## get windows, and that is what makes them free: nobody is ever OUTSIDE the
## building, so a pane that does not block sight cannot change a sight line.
func _wall_segment(a: Vector3, b: Vector3, exterior := false) -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(length, WALL_H, WALL_T) if horizontal else Vector3(WALL_T, WALL_H, length)
	if exterior and length > WIN_MIN_RUN:
		_glaze(mid, size, horizontal, length)
		return
	# Two-tone walls: a scuffed dado below, institutional off-white above.
	var lower_h := 1.1
	var lower := Vector3(size.x, lower_h, size.z)
	var upper := Vector3(size.x, WALL_H - lower_h, size.z)
	# PAINT, NOT A COLOUR. `Surfaces.wall_mat` carries a fine tooth, the long
	# soft drift emulsion actually dries in, and — the half that matters — a
	# darkening in the last half metre before the floor. That gradient is doing
	# the job SSAO would if this renderer had it, and it is what stops a room
	# reading as a set of disconnected planes.
	add_child(Build.surfaced_opaque_wall(lower, Surfaces.wall_mat(Build.WALL_LOWER),
		mid + Vector3(0, lower_h * 0.5, 0)))
	add_child(Build.surfaced_opaque_wall(upper, Surfaces.wall_mat(Build.WALL_UPPER),
		mid + Vector3(0, lower_h + upper.y * 0.5, 0)))

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

## AN EXTERIOR WALL WITH WINDOWS IN IT.
##
## Safe here and nowhere else. The pane is built with `surfaced_wall`, which
## collides on layer 1 but NOT on 32 — so a thrown bedpan bounces off it and
## stays in the building, while NPC sight, which tests layer 32, passes
## straight through. That would matter enormously on an interior wall and
## matters not at all on this one: there is nobody outside to see.
##
## The dado stops at the sill rather than running to 1.1 as it does inside.
## Teal up to a sill swallows the lower two thirds of an exterior wall, which
## is the note that came back from the first attempt at this.
func _glaze(mid: Vector3, size: Vector3, horizontal: bool, length: float) -> void:
	var t := WALL_T
	var below := Vector3(size.x, WIN_SILL, size.z)
	var above := Vector3(size.x, WALL_H - WIN_HEAD, size.z)
	add_child(Build.surfaced_opaque_wall(below, Surfaces.wall_mat(Build.WALL_LOWER),
		mid + Vector3(0, WIN_SILL * 0.5, 0)))
	add_child(Build.surfaced_opaque_wall(above, Surfaces.wall_mat(Build.WALL_UPPER),
		mid + Vector3(0, WIN_HEAD + above.y * 0.5, 0)))

	# The pane: thin, collidable, and it does not cast — a transparent shadow
	# caster on this renderer is an opaque black rectangle on the floor.
	var pane_h := WIN_HEAD - WIN_SILL
	var pane := Vector3(size.x, pane_h, t * 0.16) if horizontal \
		else Vector3(t * 0.16, pane_h, size.z)
	var glass := Build.surfaced_wall(pane, Build.glass_mat(),
		mid + Vector3(0, WIN_SILL + pane_h * 0.5, 0))
	for c in glass.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	# A sill, a head and the mullions between them, proud of the plaster on
	# both faces. The frame is what makes it read as a window rather than as a
	# hole somebody forgot to fill in.
	var frame := Color(0.95, 0.94, 0.90)
	var band := Vector3(size.x, 0.09, t + 0.05) if horizontal \
		else Vector3(t + 0.05, 0.09, size.z)
	add_child(Build.box_mi(band, frame, mid + Vector3(0, WIN_SILL - 0.02, 0), 0.6, 0.010))
	add_child(Build.box_mi(band, frame, mid + Vector3(0, WIN_HEAD + 0.02, 0), 0.6, 0.010))
	var bays := maxi(1, int(round(length / WIN_BAY)))
	for i in range(1, bays):
		var off: float = -length * 0.5 + length * float(i) / float(bays)
		var mull := Vector3(0.07, pane_h, t + 0.04) if horizontal \
			else Vector3(t + 0.04, pane_h, 0.07)
		var at := Vector3(off, 0, 0) if horizontal else Vector3(0, 0, off)
		add_child(Build.box_mi(mull, frame,
			mid + at + Vector3(0, WIN_SILL + pane_h * 0.5, 0), 0.6, 0.008))

func _lintel(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var horizontal := absf(b.x - a.x) > absf(b.z - a.z)
	var h := WALL_H - 2.1
	var size := Vector3(length, h, WALL_T) if horizontal else Vector3(WALL_T, h, length)
	add_child(Build.surfaced_opaque_wall(size, Surfaces.wall_mat(Build.WALL_UPPER),
		mid + Vector3(0, 2.1 + h * 0.5, 0)))

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
		_door_lining(centre, w, z)

## A LINED OPENING, not a hole where two wall boxes stop.
##
## The doorways in this building were negative space: two wall runs that ended
## short of each other with 16cm of raw wall section showing in the gap, and a
## lintel over the top doing the same. Every real opening has a lining — two
## jambs and a head, proud of the plaster on both sides — and it is what makes a
## doorway read as something that was BUILT rather than as a missing piece of
## wall. It is also the only thing in the corridor at eye level between the
## skirting and the sign, so it does a lot of the work of telling you how far
## away the far end is.
func _door_lining(centre: float, w: float, z: float) -> void:
	var head_y := 2.1
	var lining := Color(0.93, 0.92, 0.88)
	var t := WALL_T + 0.06          ## proud by 3cm each side
	for sx in [-1.0, 1.0]:
		add_child(Build.box_mi(Vector3(0.06, head_y + 0.06, t), lining,
			Vector3(centre + sx * (w * 0.5 + 0.03), (head_y + 0.06) * 0.5, z), 0.6, 0.008))
	add_child(Build.box_mi(Vector3(w + 0.12, 0.06, t), lining,
		Vector3(centre, head_y + 0.03, z), 0.6, 0.008))

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
