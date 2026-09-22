class_name Dressing
extends RefCounted
## The stuff on the walls.
##
## Playtest note, verbatim: "spice up the game graphics on the inside, it seems
## bare right now." It was. Every room had the objects the SIMULATION needed —
## a bed, a machine, a console — standing in a large empty box with a coloured
## floor, and nothing else. Nobody works in a room like that.
##
## Everything in this file is decoration and nothing in it is interactive, has
## collision, or takes a navigation footprint. That is deliberate: dressing is
## added last, can be added anywhere, and can never be the reason a nurse gets
## stuck or a thrown bedpan lands on a ledge. If it needs to be usable it does
## not belong here — it belongs in Furniture with a footprint.
##
## Wall pieces sit 9cm off the room rect so they clear the 16cm walls without
## z-fighting against them; ceiling pieces hang from WALL_H. The one rule is
## that nothing may stick more than about 15cm into the room, because the
## player is a capsule that walks along walls.

const PAPER := Color(0.97, 0.96, 0.89)
const FRAME := Color(0.20, 0.24, 0.28)
const CORK := Color(0.78, 0.60, 0.38)
const STEEL := Color(0.80, 0.85, 0.92)

## `depth` is how far the piece sticks out from its own origin, and it exists
## because wall fittings are not flat. A poster is 3cm thick and can sit 9cm
## proud of the plaster; a sharps bin is 20cm deep and half of it was inside the
## wall — which is exactly the "things phasing through each other" the second
## playtest reported. Pushing the root out by half its depth along its own
## facing makes one mounting offset correct for everything.
## Everything that hangs from the ceiling, so a test can find ALL of it.
##
## Not by name: Godot discards an explicit name when it collides with a sibling
## and substitutes the CLASS name — two nodes both called "Vent" under the same
## parent become "Vent" and "@Node3D@5306". Every fitting in the building is
## added to the Hospital node, so thirteen of the fourteen vents are called
## @Node3D@something and cannot be found by name at all. A check that looked for
## them by name found exactly one of each kind, in a fifteen-room hospital, and
## pronounced them all correct.
const CEILING_GROUP := "ceiling_fitting"
## The underside of the ceiling slab. `Hospital.WALL_H` is where the slab is
## CENTRED and it is 10cm thick, so anything hung from the ceiling stops here.
const CEILING_Y := Hospital.WALL_H - 0.05

## An EXTRA group for whatever is being dressed right now, so a caller can throw
## its own pieces away again without knowing what they were. Set around a block
## of calls and cleared after; see `Furniture.redress_ward`.
static var tag := ""

static func _add(h: Node3D, n: Node3D, pos: Vector3, rot_y := 0.0, depth := 0.0) -> Node3D:
	# WHAT THIS PIECE IS, RECORDED BEFORE THE ENGINE TAKES THE NAME AWAY.
	#
	# Gotcha 17: Godot DISCARDS an explicit name when it collides with a sibling
	# and substitutes the class name, and every piece of scenery in the building
	# is parented to the same Hospital node — so the second poster, the second
	# vent and the thirteenth bin are all called `@Node3D@5306` and nothing can
	# say what they are afterwards. The group rule fixes "find all the vents";
	# it does not fix "this thing is floating ninety centimetres above the floor
	# and I cannot tell you what it is", which is what an audit of the whole
	# building needs. One line, set on the way past, while the name still says.
	n.set_meta("dressing_kind", String(n.name))
	h.add_child(n)
	if tag != "":
		n.add_to_group(tag)
	# EVERYTHING DECORATIVE ANSWERS TO ONE NAME. Scenery has no collision and no
	# navigation footprint, which is what lets there be a lot of it — and also
	# means nothing in the engine will ever object to a piece of it standing in
	# the arc of a door. The smoke run checks that instead, and it needs to be
	# able to tell a poster from a wall.
	n.add_to_group("dressing")
	# AND ANYTHING STANDING ON THE FLOOR GETS A PATCH UNDER IT.
	#
	# `Furniture._block` carries the same rule for structural boxes, but almost
	# everything in a ward is scenery: the bins, the plants, the stools, the
	# water coolers, the hampers, the folding screens, the bedside cabinets.
	# Naming them one at a time is how the first pass at contact shadows left
	# every one of them floating while the beds and tables sat properly.
	#
	# `pos.y < 0.05` is the test for "on the floor" — every wall piece is
	# mounted at a height, and a poster does not cast onto lino. The size comes
	# off the piece's own geometry, so a plant and a cupboard get the right
	# patch without either of them being asked.
	if pos.y < 0.05:
		var box := _local_box(n)
		# ...UNLESS IT IS A MARKING RATHER THAN AN OBJECT.
		#
		# A painted strip is not standing on the floor, it IS the floor, and this
		# gave one to the bay zone under the beds — an eighteen-metre blob shadow
		# centred on an eighteen-metre painted rectangle, radial, so it darkened
		# itself most in the middle. That is the shadow trench running the length
		# of every ward frame in the game, and it was blamed in turn on the zone's
		# tint, on the ceiling fittings and on the beds' own shadows merging.
		# Settled by turning the zone BRIGHT RED and re-rendering one frame: pure
		# red came back at 190 along the strip's front edge and 73 through the
		# middle of it, which is not a lighting gradient, it is a blob.
		#
		# Four centimetres is the line. A doormat, a wayfinding line and a bay
		# marking are paint; a bin, a plant and a bedside cabinet are objects.
		if box.size.y > 0.04 and box.size.x > 0.16 and box.size.z > 0.16:
			var sh := Build.blob_shadow(
				Vector2(box.size.x + 0.22, box.size.z + 0.22), 0.02)
			sh.position = Vector3(box.get_center().x, 0.02 - pos.y,
				box.get_center().z)
			n.add_child(sh)
	# AND ANYTHING HUNG IN A WINDOW GETS A PIER TO BE HUNG ON.
	#
	# All four exterior runs are glazed from the sill to the head over their
	# whole length, and every room has one — so `_far_wall`, `_left_wall` and
	# `_right_wall` hand back picture height on a pane about half the time.
	# Photographed in `07_office`: the wall art and the notice float in the
	# middle of the glazing with hedges and sky visible round them and a
	# mullion passing BEHIND the frame. It is the same fault as the sharps bin
	# beside every bed, and there were eight more of it.
	#
	# Here rather than at the call sites, because the call sites are the one
	# place that cannot see it: a wall is a wall in `Furniture` and only the
	# `Hospital` knows which runs it glazed. Long pieces are skipped — a
	# nineteen-metre handrail would ask for a nineteen-metre pier — and so is
	# anything standing on the floor, which is in front of a window rather than
	# on it.
	if pos.y >= 0.05 and h.has_method("glazed_at") and h.glazed_at(pos) \
			and not _has_pier(h, pos, rot_y):
		var mounted := _local_box(n)
		if mounted.size.x < 3.2 and mounted.size.y < 2.0:
			wall_pier(h, pos, rot_y, mounted.size.x + 0.52)
	n.position = pos + Vector3(sin(rot_y), 0.0, cos(rot_y)) * depth * 0.5
	n.rotation.y = rot_y
	return n

## Every mesh under a node, merged, in the node's own space. Called before the
## piece is in the tree, so global transforms are not available and must not be.
static func _local_box(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if not (cur is MeshInstance3D):
			continue
		var mi: MeshInstance3D = cur
		if mi.mesh == null:
			continue
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

# ------------------------------------------------------------------ paper
## A framed notice. Faces +Z before rotation, so `rot_y` is which wall it is on:
## 0 for a wall behind you, PI for the wall you are looking at.
##
## The lines of "text" are bars rather than a Label3D on purpose. Real text on a
## poster is a promise the game has to keep — the player will walk up and read
## it — and eleven readable posters is eleven pieces of writing that have to be
## funny. Bars read as writing at the distance anybody sees them from.
static func poster(h: Node3D, pos: Vector3, rot_y: float, w := 0.62, tall := 0.86,
		accent := Color(0.35, 0.72, 0.70), lines := 4) -> Node3D:
	var root := Node3D.new()
	root.name = "Poster"
	root.add_child(Build.box_mi(Vector3(w, tall, 0.035), FRAME, Vector3.ZERO, 0.6, 0.010))
	root.add_child(Build.box_mi(Vector3(w - 0.07, tall - 0.07, 0.012), PAPER,
		Vector3(0, 0, 0.022), 0.9, 0.0))
	root.add_child(Build.box_mi(Vector3(w - 0.18, tall * 0.17, 0.008), accent,
		Vector3(0, tall * 0.30, 0.030), 0.7, 0.0))
	for i in lines:
		var lw: float = (w - 0.20) * (0.95 if i % 3 != 2 else 0.55)
		root.add_child(Build.box_mi(Vector3(lw, 0.026, 0.006),
			Color(0.42, 0.45, 0.48),
			Vector3(-(w - 0.20 - lw) * 0.5, tall * 0.10 - float(i) * tall * 0.12, 0.030),
			0.9, 0.0))
	return _add(h, root, pos, rot_y, 0.035)

## A cork board with notes pinned to it at slightly wrong angles, because a
## noticeboard where everything is straight is a noticeboard nobody uses.
static func noticeboard(h: Node3D, pos: Vector3, rot_y: float, w := 1.5, tall := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Noticeboard"
	root.add_child(Build.box_mi(Vector3(w + 0.08, tall + 0.08, 0.05), FRAME,
		Vector3.ZERO, 0.6, 0.010))
	root.add_child(Build.box_mi(Vector3(w, tall, 0.02), CORK, Vector3(0, 0, 0.032), 0.95, 0.0))
	var tints := [PAPER, Color(0.96, 0.87, 0.55), Color(0.72, 0.90, 0.94),
		Color(0.96, 0.74, 0.76), PAPER]
	var cols := maxi(2, int(w / 0.42))
	for i in cols:
		for j in 2:
			var note := Build.box_mi(Vector3(0.28, 0.34, 0.008),
				tints[(i + j * 2) % tints.size()],
				Vector3(-w * 0.5 + 0.24 + float(i) * (w - 0.4) / maxf(1.0, float(cols - 1)),
					tall * 0.22 - float(j) * 0.40, 0.046), 0.95, 0.006)
			note.rotation.z = (0.09 if (i + j) % 2 == 0 else -0.07)
			root.add_child(note)
	return _add(h, root, pos, rot_y, 0.050)

## Framed art. Abstract, cheerful, and exactly as related to medicine as the
## art in a real waiting room.
static func wall_art(h: Node3D, pos: Vector3, rot_y: float, w := 0.9, tall := 0.7,
		a := Color(0.30, 0.70, 0.85), b := Color(0.98, 0.72, 0.32)) -> Node3D:
	var root := Node3D.new()
	root.name = "WallArt"
	root.add_child(Build.box_mi(Vector3(w, tall, 0.045), FRAME, Vector3.ZERO, 0.5, 0.010))
	root.add_child(Build.box_mi(Vector3(w - 0.08, tall - 0.08, 0.012),
		Color(0.95, 0.94, 0.90), Vector3(0, 0, 0.028), 0.9, 0.0))
	root.add_child(Build.mi(Build.cyl_mesh(tall * 0.24, 0.01, 16), Build.mat(a, 0.8),
		Vector3(-w * 0.16, tall * 0.06, 0.036), Vector3(PI * 0.5, 0, 0)))
	root.add_child(Build.box_mi(Vector3(w * 0.30, tall * 0.30, 0.01), b,
		Vector3(w * 0.18, -tall * 0.10, 0.036), 0.8, 0.006))
	root.add_child(Build.box_mi(Vector3(w * 0.62, 0.03, 0.01), Color(0.28, 0.32, 0.36),
		Vector3(0, -tall * 0.30, 0.036), 0.8, 0.0))
	return _add(h, root, pos, rot_y, 0.045)

# ------------------------------------------------------------------ fittings
## A privacy curtain on a rail, gathered at one end. Gathered rather than drawn
## because a drawn curtain hides the bed, and the bed is where the game is.
static func curtain(h: Node3D, pos: Vector3, span: float, rot_y := 0.0,
		tint := Color(0.36, 0.68, 0.72)) -> Node3D:
	var root := Node3D.new()
	root.name = "Curtain"
	root.add_to_group(CEILING_GROUP)
	root.add_child(Build.mi(Build.cyl_mesh(0.022, span, 10), Build.mat(STEEL, 0.4, 0.6),
		Vector3(0, 2.28, 0), Vector3(0, 0, PI * 0.5)))
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.05, 0.16, 0.05), STEEL,
			Vector3(-span * 0.5 + float(i) * span, 2.36, 0), 0.4, 0.008))
		# ...AND A DROP TO THE CEILING, which is the fault `ceiling_sign` had
		# and `curtain_track` was given a comment about, on the piece next to
		# both of them. The bracket stopped at 2.44 and the ceiling's underside
		# is at 3.10, so every bay divider in the ward — four of them, in the
		# frame a store page leads with — hung on two steel posts with
		# sixty-six centimetres of air above each one. Photographed in
		# `04c_visitor` it is a pale cylinder floating under a ceiling tile.
		root.add_child(Build.mi(Build.cyl_mesh(0.016, CEILING_Y - 2.44, 8),
			Build.mat(STEEL, 0.4, 0.6),
			Vector3(-span * 0.5 + float(i) * span, (2.44 + CEILING_Y) * 0.5, 0)))
	# The gather: seven slats of slightly different depth, which is what a
	# bunched curtain is when you look at one.
	for i in 7:
		var t := float(i) / 6.0
		var slat := Build.cloth_mi(Vector3(0.11, 1.86, 0.055 + 0.03 * sin(t * PI * 3.0)),
			tint.lightened(0.06 * sin(t * PI * 2.0)),
			Vector3(-span * 0.5 + 0.10 + t * 0.62, 1.30, 0.02 * sin(t * 9.0)), 0.010)
		root.add_child(slat)
	return _add(h, root, pos, rot_y)

## Gas outlets behind a bed. Four coloured spigots on a steel plate: the single
## most "this is a hospital" object per polygon in the entire building.
static func oxygen_panel(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "OxygenPanel"
	root.add_child(Build.box_mi(Vector3(0.86, 0.34, 0.06), Color(0.90, 0.92, 0.94),
		Vector3.ZERO, 0.45, 0.010))
	var cols := [Color(0.30, 0.66, 0.95), Color(0.96, 0.96, 0.96),
		Color(0.36, 0.82, 0.52), Color(0.95, 0.72, 0.28)]
	for i in 4:
		root.add_child(Build.mi(Build.cyl_mesh(0.045, 0.09, 10),
			Build.mat(cols[i], 0.5, 0.2),
			Vector3(-0.30 + float(i) * 0.20, 0.0, 0.070), Vector3(PI * 0.5, 0, 0)))
	root.add_child(Build.box_mi(Vector3(0.80, 0.03, 0.008), Color(0.35, 0.40, 0.44),
		Vector3(0, 0.13, 0.034), 0.8, 0.0))
	return _add(h, root, pos, rot_y, 0.060)

## Sharps bin. Yellow, lidded, and the correct kind of ominous.
static func sharps(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Sharps"
	root.add_child(Build.box_mi(Vector3(0.26, 0.30, 0.20), Color(0.98, 0.80, 0.14),
		Vector3.ZERO, 0.8, 0.010))
	root.add_child(Build.box_mi(Vector3(0.27, 0.07, 0.21), Color(0.92, 0.36, 0.20),
		Vector3(0, 0.18, 0), 0.7, 0.008))
	root.add_child(Build.box_mi(Vector3(0.14, 0.02, 0.06), Color(0.25, 0.20, 0.10),
		Vector3(0, 0.215, 0.02), 0.9, 0.0))
	return _add(h, root, pos, rot_y, 0.200)

## Hand gel by the door. Everybody in the building walks past one of these
## fifty times a shift and the player is about to as well.
static func dispenser(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Dispenser"
	root.add_child(Build.box_mi(Vector3(0.16, 0.28, 0.11), Color(0.92, 0.94, 0.96),
		Vector3.ZERO, 0.55, 0.008))
	root.add_child(Build.box_mi(Vector3(0.10, 0.16, 0.06), Color(0.55, 0.86, 0.80),
		Vector3(0, 0.01, 0.055), 0.35, 0.006))
	root.add_child(Build.box_mi(Vector3(0.09, 0.04, 0.05), Color(0.35, 0.40, 0.44),
		Vector3(0, -0.16, 0.04), 0.6, 0.006))
	return _add(h, root, pos, rot_y, 0.110)

static func extinguisher(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Extinguisher"
	root.add_child(Build.box_mi(Vector3(0.30, 0.50, 0.03), Color(0.90, 0.90, 0.88),
		Vector3(0, 0.05, 0), 0.9, 0.0))
	root.add_child(Build.mi(Build.cyl_mesh(0.085, 0.42, 12),
		Build.mat(Color(0.88, 0.20, 0.18), 0.5, 0.1), Vector3(0, 0, 0.11)))
	root.add_child(Build.mi(Build.cyl_mesh(0.028, 0.10, 8), Build.mat(STEEL, 0.4, 0.7),
		Vector3(0, 0.25, 0.11)))
	root.add_child(Build.box_mi(Vector3(0.12, 0.03, 0.03), Color(0.20, 0.22, 0.24),
		Vector3(0.06, 0.29, 0.11), 0.6, 0.006))
	return _add(h, root, pos, rot_y, 0.220)

static func clock(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Clock"
	root.add_child(Build.mi(Build.cyl_mesh(0.20, 0.05, 18), Build.mat(FRAME, 0.5),
		Vector3.ZERO, Vector3(PI * 0.5, 0, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.175, 0.02, 18), Build.unshaded(PAPER),
		Vector3(0, 0, 0.033), Vector3(PI * 0.5, 0, 0)))
	root.add_child(Build.box_mi(Vector3(0.02, 0.12, 0.008), Color(0.15, 0.16, 0.18),
		Vector3(0, 0.05, 0.045), 0.9, 0.0))
	var min_hand := Build.box_mi(Vector3(0.016, 0.15, 0.008), Color(0.15, 0.16, 0.18),
		Vector3(0.045, -0.02, 0.045), 0.9, 0.0)
	min_hand.rotation.z = 1.9
	root.add_child(min_hand)
	return _add(h, root, pos, rot_y, 0.050)

## A ceiling vent. Four slats in a frame — the thing that stops a ceiling being
## an unbroken plane across the top third of every shot.
## LOCAL ZERO IS THE CEILING PLANE, and callers pass Hospital.WALL_H rather than
## WALL_H minus a guess. Every ceiling fitting in the building was positioned by
## its caller subtracting a number that had nothing to do with the piece's own
## height — the vent by 0.07 against a 0.04 frame, the sprinkler by 0.09 against
## a 0.05 body — so all of them hung a few centimetres below the plaster with
## daylight above them. It is the same mistake as mounting a sharps bin with a
## poster's offset (CLAUDE.md 13), in the other axis: the piece knows how tall it
## is and the caller does not.
static func vent(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Vent"
	root.add_to_group(CEILING_GROUP)
	root.add_child(Build.box_mi(Vector3(0.62, 0.04, 0.42), Color(0.88, 0.89, 0.87),
		Vector3(0, -0.02, 0), 0.5, 0.008))
	for i in 4:
		root.add_child(Build.box_mi(Vector3(0.54, 0.02, 0.055), Color(0.55, 0.58, 0.60),
			Vector3(0, -0.048, -0.14 + float(i) * 0.093), 0.7, 0.0))
	return _add(h, root, pos, rot_y)

## Also hung from local zero. See vent().
static func sprinkler(h: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Sprinkler"
	root.add_to_group(CEILING_GROUP)
	# AN ESCUTCHEON YOU CAN SEE. The plate was 4.5cm of pale steel against a
	# white ceiling — invisible — so all that read was the orange nozzle hanging
	# 12cm below it, and every wide shot of the ward had a small brown speck
	# floating in the middle of the ceiling with nothing holding it up. Wider,
	# a shade darker than the plaster, and the drop shortened so the whole
	# fitting reads as one object attached to something.
	root.add_child(Build.mi(Build.cyl_mesh(0.085, 0.022, 16),
		Build.mat(Color(0.72, 0.74, 0.76), 0.45, 0.35), Vector3(0, -0.011, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.030, 0.038, 12),
		Build.mat(STEEL, 0.35, 0.7), Vector3(0, -0.040, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.016, 0.030, 10),
		Build.mat(Color(0.85, 0.45, 0.25), 0.4, 0.3), Vector3(0, -0.072, 0)))
	return _add(h, root, pos)

## A rail along a corridor wall, with brackets. Runs from x0 to x1 at a fixed z.
## A handrail that stops at the doorways.
##
## `gaps` is a list of Vector2(from, to) in x. The corridor rail used to be one
## unbroken cylinder from end to end, which meant it ran straight across every
## door opening at waist height — you walked through a rail to get into a room,
## and every screenshot of a ward door had a gold bar drawn across it.
static func handrail_run(h: Node3D, x0: float, x1: float, z: float,
		gaps: Array, y := 0.92, tint := Color(0.62, 0.64, 0.68)) -> void:
	var cuts: Array = gaps.duplicate()
	cuts.sort_custom(func(a, b): return a.x < b.x)
	var cursor := x0
	for g in cuts:
		var from: float = maxf(x0, float(g.x))
		var to: float = minf(x1, float(g.y))
		if to <= cursor:
			continue
		if from - cursor > 0.5:
			handrail(h, cursor, from, z, y, tint)
		cursor = maxf(cursor, to)
	if x1 - cursor > 0.5:
		handrail(h, cursor, x1, z, y, tint)

static func handrail(h: Node3D, x0: float, x1: float, z: float, y := 0.92,
		tint := Color(0.62, 0.64, 0.68)) -> Node3D:
	var root := Node3D.new()
	root.name = "Handrail"
	var span: float = absf(x1 - x0)
	root.add_child(Build.mi(Build.cyl_mesh(0.045, span, 10), Build.mat(tint, 0.6),
		Vector3.ZERO, Vector3(0, 0, PI * 0.5)))
	# Rounded returns, so a rail that stops at a door looks finished rather
	# than snapped off.
	for sx in [-1.0, 1.0]:
		root.add_child(Build.mi(Build.sphere_mesh(0.046), Build.mat(tint, 0.6),
			Vector3(sx * span * 0.5, 0, 0)))
	var brackets := maxi(2, int(span / 2.4))
	for i in brackets:
		var t: float = float(i) / float(maxi(1, brackets - 1))
		root.add_child(Build.box_mi(Vector3(0.05, 0.05, 0.14), Color(0.55, 0.58, 0.62),
			Vector3(-span * 0.5 + t * span, 0, -0.09), 0.5, 0.006))
	return _add(h, root, Vector3((x0 + x1) * 0.5, y, z))

## Guide lines on the floor. Follow the blue line to Radiology, and so on: the
## cheapest wayfinding in architecture and the cheapest here too.
static func floor_line(h: Node3D, x0: float, x1: float, z: float, tint: Color,
		width := 0.10, room := Rect2()) -> Node3D:
	var root := Node3D.new()
	root.name = "FloorLine"
	# Paint, through the one place that knows what paint is: see
	# `Build.floor_paint`. As a flat box these read as glowing tape.
	root.add_child(Build.floor_paint(Vector3(absf(x1 - x0), 0.012, width), tint,
		Vector3.ZERO, room))
	return _add(h, root, Vector3((x0 + x1) * 0.5, 0.008, z))

## The head of a curtain track: one thin rail across the bay at head height.
## Every bed already has a curtain gathered against its divider and not one of
## them has anything to hang from, which reads exactly as it sounds.
static func curtain_track(h: Node3D, x0: float, x1: float, z: float,
		y := 2.36) -> Node3D:
	var root := Node3D.new()
	root.name = "CurtainTrack"
	root.add_to_group(CEILING_GROUP)
	var span: float = absf(x1 - x0)
	root.add_child(Build.box_mi(Vector3(span, 0.05, 0.045), Color(0.80, 0.82, 0.83),
		Vector3.ZERO, 0.35, 0.006))
	# Drops to the ceiling, because a rail hanging from nothing is the fault
	# `ceiling_sign` already had once.
	var n: int = maxi(2, int(span / 2.4))
	for i in n + 1:
		var t: float = float(i) / float(n)
		root.add_child(Build.mi(Build.cyl_mesh(0.010, Hospital.WALL_H - y, 6),
			Build.mat(STEEL, 0.4, 0.6),
			Vector3(-span * 0.5 + span * t, (Hospital.WALL_H - y) * 0.5, 0)))
	return _add(h, root, Vector3((x0 + x1) * 0.5, y, z))

## A hanging sign, the kind every hospital corridor has too many of.
static func ceiling_sign(h: Node3D, pos: Vector3, text: String, rot_y := 0.0,
		tint := Color(0.16, 0.42, 0.52)) -> Node3D:
	var root := Node3D.new()
	root.name = "CeilingSign"
	root.add_to_group(CEILING_GROUP)
	# The hangers RUN FROM THE CEILING to the top of the board, which they did
	# not: the caller placed the board at a fixed 2.62 and the two 34cm rods sat
	# above it ending at 3.09, eleven centimetres short of a 3.2m ceiling. Every
	# corridor sign in the building was suspended from nothing.
	# THE PLATE IS SIZED TO THE TEXT, which `_wall_sign` has always done and this
	# had not: a fixed 1.5m board with "WARD 9 ▲ ◀ STATION" on it at 17cm is a
	# sign whose words hang off both ends into the air. The 0.62 is the same
	# advance-per-character estimate the wall plates use.
	var plate_w: float = maxf(1.2, float(text.length()) * 0.17 * 0.62 + 0.22)
	for dx in [-plate_w * 0.36, plate_w * 0.36]:
		root.add_child(Build.mi(Build.cyl_mesh(0.012, 0.34, 6), Build.mat(STEEL, 0.4, 0.6),
			Vector3(dx, -0.17, 0)))
	root.add_child(Build.box_mi(Vector3(plate_w, 0.34, 0.06), tint,
		Vector3(0, -0.51, 0), 0.7, 0.010))
	var l := Build.label3d(text, 0.17, Color(0.96, 0.98, 0.98), false)
	l.position = Vector3(0, -0.51, 0.045)
	root.add_child(l)
	var back := Build.label3d(text, 0.17, Color(0.96, 0.98, 0.98), false)
	back.position = Vector3(0, -0.51, -0.045)
	back.rotation.y = PI
	root.add_child(back)
	return _add(h, root, pos, rot_y)

# ------------------------------------------------------------------ clutter
## Everything below stands on the floor and is small enough to walk around
## without a footprint. Anything bigger than a bin belongs in Furniture.
static func bin(h: Node3D, pos: Vector3, tint := Color(0.32, 0.55, 0.62),
		pedal := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Bin"
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.30, 0.30), Vector2(0.34, 0.34), 0.46),
		Build.mat(tint, 0.75), Vector3(0, 0.23, 0)))
	root.add_child(Build.box_mi(Vector3(0.36, 0.04, 0.36), tint.lightened(0.22),
		Vector3(0, 0.475, 0), 0.6, 0.008))
	if pedal:
		root.add_child(Build.box_mi(Vector3(0.16, 0.03, 0.08), Color(0.45, 0.48, 0.52),
			Vector3(0, 0.03, 0.20), 0.5, 0.006))
	return _add(h, root, pos)

static func plant(h: Node3D, pos: Vector3, scale_f := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Plant"
	root.scale = Vector3.ONE * scale_f
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.24, 0.24), Vector2(0.32, 0.32), 0.30),
		Build.mat(Color(0.78, 0.46, 0.32), 0.85), Vector3(0, 0.15, 0)))
	root.add_child(Build.box_mi(Vector3(0.28, 0.03, 0.28), Color(0.28, 0.22, 0.18),
		Vector3(0, 0.30, 0), 0.95, 0.0))
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		var leaf := Build.box_mi(Vector3(0.10, 0.44, 0.03),
			Color(0.24, 0.62, 0.34).lightened(0.10 * sin(a * 2.0)),
			Vector3(sin(a) * 0.14, 0.52, cos(a) * 0.14), 0.9, 0.008)
		leaf.rotation = Vector3(cos(a) * 0.5, -a, sin(a) * 0.5)
		root.add_child(leaf)
	return _add(h, root, pos)

## Folded linen. Four towels in a stack with the colours slightly off each
## other, because a stack of one colour reads as a solid block.
static func linen(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Linen"
	for i in 4:
		root.add_child(Build.box_mi(Vector3(0.40, 0.07, 0.30),
			Color(0.94, 0.95, 0.97).darkened(0.045 * float(i % 2)),
			Vector3(0.012 * float(i % 3), 0.04 + float(i) * 0.075, 0), 0.95, 0.008))
	return _add(h, root, pos, rot_y)

static func mop_bucket(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "MopBucket"
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.40, 0.30), Vector2(0.46, 0.34), 0.34),
		Build.mat(Color(0.95, 0.72, 0.20), 0.8), Vector3(0, 0.17, 0)))
	root.add_child(Build.box_mi(Vector3(0.20, 0.14, 0.26), Color(0.55, 0.58, 0.62),
		Vector3(0.14, 0.42, 0), 0.5, 0.008))
	var pole := Build.mi(Build.cyl_mesh(0.022, 1.30, 8),
		Build.mat(Color(0.30, 0.55, 0.72), 0.6), Vector3(-0.10, 0.75, 0.06))
	pole.rotation = Vector3(0.12, 0, 0.18)
	root.add_child(pole)
	root.add_child(Build.box_mi(Vector3(0.16, 0.22, 0.10), Color(0.80, 0.80, 0.74),
		Vector3(-0.30, 1.34, 0.14), 0.95, 0.008))
	return _add(h, root, pos, rot_y)

## A cardboard box, or three. The universal signal that a room is used by
## people who are behind on something.
static func boxes(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Boxes"
	var sizes := [Vector3(0.52, 0.36, 0.42), Vector3(0.44, 0.30, 0.36),
		Vector3(0.36, 0.26, 0.30)]
	var y := 0.0
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		var b := Build.box_mi(s, Color(0.80, 0.64, 0.44).darkened(0.04 * float(i)),
			Vector3(0.04 * float(i), y + s.y * 0.5, -0.03 * float(i)), 0.95, 0.010)
		b.rotation.y = 0.16 * float(i)
		root.add_child(b)
		root.add_child(Build.box_mi(Vector3(s.x * 0.9, 0.012, 0.06),
			Color(0.88, 0.84, 0.72),
			Vector3(0.04 * float(i), y + s.y + 0.004, -0.03 * float(i)), 0.9, 0.0))
		y += s.y
	return _add(h, root, pos, rot_y)

## A wheeled drip stand's poorer cousin: a stack of trays on a shelf unit face.
static func trays(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Trays"
	# THE ORIGIN IS THE BASE, like `linen` and `boxes` and unlike this used to
	# be: the first tray was CENTRED on y = 0, so the bottom of the stack sat
	# 17mm below the point every caller was treating as "where it stands", and a
	# stack placed exactly on a worktop cut into it.
	for i in 5:
		root.add_child(Build.box_mi(Vector3(0.34, 0.035, 0.26),
			[Color(0.36, 0.68, 0.72), Color(0.94, 0.86, 0.42)][i % 2],
			Vector3(0, 0.018 + float(i) * 0.05, 0), 0.8, 0.006))
	return _add(h, root, pos, rot_y)

## A mug and a stack of paper on a desk, which is the difference between a desk
## and a table.
static func desk_clutter(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "DeskClutter"
	root.add_child(Build.mi(Build.cyl_mesh(0.043, 0.10, 10),
		Build.mat(Color(0.92, 0.44, 0.36), 0.6), Vector3(0.22, 0.05, 0.04)))
	root.add_child(Build.box_mi(Vector3(0.02, 0.05, 0.05), Color(0.92, 0.44, 0.36),
		Vector3(0.27, 0.06, 0.04), 0.6, 0.006))
	for i in 6:
		root.add_child(Build.box_mi(Vector3(0.22, 0.006, 0.30), PAPER,
			Vector3(0.004 * float(i % 3), 0.004 + float(i) * 0.007, 0), 0.95, 0.0))
	# A POT, not a plate. The pens were three sticks standing at an angle over a
	# 10cm x 2cm tile, which is the one arrangement of a pen and a desk that
	# cannot happen — photographed on the station worktop at eighty centimetres
	# they read as three coloured straws balancing on a coaster. The pot is a
	# cylinder with a darker mouth ring, so it is open at the top rather than
	# being a peg the pens are stuck into.
	root.add_child(Build.mi(Build.cyl_mesh(0.038, 0.11, 10),
		Build.mat(Color(0.35, 0.40, 0.44), 0.7), Vector3(-0.24, 0.055, 0.06)))
	root.add_child(Build.mi(Build.cyl_mesh(0.032, 0.02, 10),
		Build.mat(Color(0.22, 0.26, 0.30), 0.8), Vector3(-0.24, 0.105, 0.06)))
	for i in 3:
		var pen := Build.box_mi(Vector3(0.012, 0.012, 0.15),
			[Color(0.25, 0.45, 0.85), Color(0.90, 0.30, 0.30), Color(0.30, 0.70, 0.45)][i],
			Vector3(-0.245 + 0.018 * float(i), 0.135, 0.058), 0.5, 0.0)
		pen.rotation = Vector3(1.32 + 0.09 * float(i), 0.5 * float(i), 0)
		root.add_child(pen)
	return _add(h, root, pos, rot_y)

## THE PRINTER, and it was a white brick.
##
## `_station` built it as one `_block` — 0.52 x 0.34 x 0.44 in near-white — with
## a single sheet of paper laid on the lid. It is the largest object on six
## metres of worktop and the thing closest to the camera in `06_station`, and
## at eighty centimetres it is a blank box with a blank box on it: no slot, no
## lid line, no panel, nothing that says which way round it is or what it does.
##
## Gotcha 120 in a third place. `_station`'s own comment lists what turns a slab
## into joinery — a recess, a shadow gap, a line where two parts meet — and none
## of it had been applied to the objects STANDING on the thing it was written
## about. A printer is a body, a lid sitting on it with a gap, a slot the paper
## comes out of, a tray under the slot with paper in it and a panel you press.
## Five boxes and two of them are two centimetres.
static func printer(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Printer"
	var body := Color(0.80, 0.81, 0.82)
	# Body, lid and the dark seam between them. The lid is INSET, because a
	# shadow gap is a horizontal inset and not a vertical one: two boxes the
	# same width with air between them read as one box with a crack in it.
	root.add_child(Build.box_mi(Vector3(0.52, 0.20, 0.44), body,
		Vector3(0, 0.10, 0), 0.6, 0.010))
	root.add_child(Build.box_mi(Vector3(0.47, 0.03, 0.40), Color(0.24, 0.26, 0.29),
		Vector3(0, 0.205, 0), 0.8, 0.0))
	root.add_child(Build.box_mi(Vector3(0.50, 0.06, 0.42), body.darkened(0.10),
		Vector3(0, 0.25, 0), 0.6, 0.010))
	# The slot, the lip under it and the sheet halfway out of it. The slot is a
	# dark recess rather than a painted line: it is 12mm deep, so it catches a
	# shadow of its own at any angle the worktop is seen from.
	root.add_child(Build.box_mi(Vector3(0.36, 0.035, 0.012), Color(0.16, 0.17, 0.19),
		Vector3(0, 0.145, 0.214), 0.9, 0.0))
	root.add_child(Build.box_mi(Vector3(0.34, 0.012, 0.11), body.darkened(0.06),
		Vector3(0, 0.118, 0.265), 0.6, 0.006))
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.30, 0.006, 0.13), PAPER,
			Vector3(0.004 * float(i), 0.127 + 0.007 * float(i), 0.255 - 0.006 * float(i)),
			0.95, 0.0))
	# The panel, on the right of the lid where a right-handed person reaches,
	# with a green light and an amber one. The amber is why it is out of paper.
	root.add_child(Build.box_mi(Vector3(0.15, 0.012, 0.09), Color(0.28, 0.31, 0.34),
		Vector3(0.16, 0.287, 0.10), 0.7, 0.0))
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.018, 0.010, 0.018),
			[Color(0.36, 0.84, 0.46), Color(0.95, 0.68, 0.20)][i],
			Vector3(0.115 + float(i) * 0.045, 0.290, 0.128), 0.4, 0.0))
	# The feed tray at the back, with the ream it is not printing.
	var tray := Build.box_mi(Vector3(0.38, 0.012, 0.16), body.darkened(0.04),
		Vector3(0, 0.30, -0.24), 0.7, 0.006)
	tray.rotation.x = -0.42
	root.add_child(tray)
	return _add(h, root, pos, rot_y)

## A bedside cabinet with a drawer, a lamp and a beaker on it. Small enough to
## walk round, big enough that the space beside a bed stops being empty floor.
static func cabinet(h: Node3D, pos: Vector3, rot_y := 0.0,
		tint := Color(0.92, 0.93, 0.95)) -> Node3D:
	var root := Node3D.new()
	root.name = "Cabinet"
	root.add_child(Build.box_mi(Vector3(0.52, 0.66, 0.46), tint, Vector3(0, 0.33, 0), 0.7, 0.012))
	# TWO DRAWERS, not two bars glued to a box. The cabinet had a pair of
	# handles floating on a blank front and nothing for them to be attached to,
	# so the eye read it as a cupboard with go-faster stripes. A drawer front
	# proud of the carcass by six millimetres, with a shadow gap between the
	# two, is what makes it a chest of drawers — and it is the object that
	# stands beside every bed in the building.
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.47, 0.26, 0.03), tint.lightened(0.04),
			Vector3(0, 0.17 + float(i) * 0.29, 0.235), 0.7, 0.008))
		root.add_child(Build.box_mi(Vector3(0.20, 0.022, 0.035), Color(0.55, 0.60, 0.64),
			Vector3(0, 0.24 + float(i) * 0.29, 0.248), 0.5, 0.005))
	root.add_child(Build.box_mi(Vector3(0.54, 0.04, 0.48), tint.darkened(0.10),
		Vector3(0, 0.68, 0), 0.6, 0.010))
	# A lamp and a beaker of water, because a flat top is a shelf nobody uses.
	root.add_child(Build.mi(Build.cyl_mesh(0.07, 0.03, 12),
		Build.mat(Color(0.35, 0.40, 0.44), 0.5), Vector3(-0.14, 0.71, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.015, 0.22, 8),
		Build.mat(Color(0.55, 0.58, 0.62), 0.5), Vector3(-0.14, 0.82, 0)))
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.16, 0.16), Vector2(0.09, 0.09), 0.13),
		Build.mat(Color(0.96, 0.86, 0.52), 0.8, 0.0, Color(0.30, 0.26, 0.10)),
		Vector3(-0.14, 0.99, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.042, 0.11, 10),
		Build.mat(Color(0.72, 0.90, 0.94), 0.35), Vector3(0.14, 0.755, 0.04)))
	return _add(h, root, pos, rot_y)

## The tray table that swings over a bed and is never where anybody wants it.
static func overbed_table(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "OverbedTable"
	root.add_child(Build.box_mi(Vector3(0.46, 0.03, 0.30), Color(0.62, 0.66, 0.70),
		Vector3(0, 0.03, 0), 0.6, 0.008))
	root.add_child(Build.mi(Build.cyl_mesh(0.035, 0.86, 10),
		Build.mat(STEEL, 0.4, 0.6), Vector3(0, 0.45, 0)))
	root.add_child(Build.box_mi(Vector3(0.78, 0.045, 0.44), Color(0.94, 0.90, 0.78),
		Vector3(0.20, 0.90, 0), 0.75, 0.012))
	root.add_child(Build.mi(Build.cyl_mesh(0.055, 0.09, 12),
		Build.mat(Color(0.90, 0.94, 0.96), 0.4), Vector3(0.34, 0.965, 0.10)))
	root.add_child(Build.box_mi(Vector3(0.20, 0.012, 0.26), PAPER,
		Vector3(0.06, 0.928, -0.06), 0.9, 0.0))
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.16, 0.02, 0.02),
			[Color(0.55, 0.60, 0.66), Color(0.92, 0.62, 0.30)][i],
			Vector3(0.02, 0.936 + float(i) * 0.022, 0.08), 0.5, 0.0))
	return _add(h, root, pos, rot_y)

## A round stool on castors. Doctors sit on these to look sympathetic.
static func stool(h: Node3D, pos: Vector3, tint := Color(0.28, 0.52, 0.60)) -> Node3D:
	var root := Node3D.new()
	root.name = "Stool"
	root.add_child(Build.mi(Build.cyl_mesh(0.22, 0.09, 14), Build.mat(tint, 0.75),
		Vector3(0, 0.56, 0)))
	root.add_child(Build.mi(Build.cyl_mesh(0.035, 0.50, 8), Build.mat(STEEL, 0.4, 0.6),
		Vector3(0, 0.28, 0)))
	for i in 5:
		var a: float = TAU * float(i) / 5.0
		root.add_child(Build.box_mi(Vector3(0.06, 0.04, 0.24), Color(0.35, 0.38, 0.42),
			Vector3(sin(a) * 0.11, 0.06, cos(a) * 0.11), 0.6, 0.006))
		root.add_child(Build.mi(Build.cyl_mesh(0.035, 0.03, 8),
			Build.mat(Color(0.20, 0.22, 0.24), 0.6),
			Vector3(sin(a) * 0.22, 0.035, cos(a) * 0.22), ))
	return _add(h, root, pos)

## A laundry hamper with a bag in it, sagging.
static func hamper(h: Node3D, pos: Vector3, rot_y := 0.0,
		tint := Color(0.46, 0.72, 0.66)) -> Node3D:
	var root := Node3D.new()
	root.name = "Hamper"
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		root.add_child(Build.mi(Build.cyl_mesh(0.022, 0.68, 8), Build.mat(STEEL, 0.4, 0.6),
			Vector3(sin(a) * 0.24, 0.34, cos(a) * 0.24)))
	root.add_child(Build.mi(Build.cyl_mesh(0.27, 0.05, 14), Build.mat(STEEL, 0.4, 0.6),
		Vector3(0, 0.70, 0)))
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.44, 0.44), Vector2(0.52, 0.52), 0.60),
		Build.mat(tint, 0.95), Vector3(0, 0.34, 0)))
	root.add_child(Build.box_mi(Vector3(0.30, 0.10, 0.26), Color(0.96, 0.97, 0.99),
		Vector3(0.04, 0.70, 0.02), 0.95, 0.008))
	return _add(h, root, pos, rot_y)

## A mat inside a doorway, and the reason a floor has a threshold.
##
## NOT DARK. At 0.22 of a value on a floor at 0.72 it is not a mat, it is a
## rectangular HOLE in the vinyl — which is exactly what it reads as in the wide
## ward shot, and a black rectangle lying flat with no thickness is the single
## most convincing way to tell somebody your floor is broken. A doormat is a mid
## grey-brown; the trim inside it carries whatever contrast it needs.
static func floor_mat(h: Node3D, pos: Vector3, size := Vector2(1.4, 0.9),
		tint := Color(0.42, 0.47, 0.48), rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "FloorMat"
	root.add_child(Build.box_mi(Vector3(size.x, 0.016, size.y), tint, Vector3.ZERO, 0.95, 0.0))
	root.add_child(Build.box_mi(Vector3(size.x - 0.16, 0.018, size.y - 0.16),
		tint.lightened(0.12), Vector3(0, 0.004, 0), 0.95, 0.0))
	return _add(h, root, pos + Vector3(0, 0.01, 0), rot_y)

## A screen on a bracket in the corner, showing nothing anybody chose.
static func wall_tv(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "WallTv"
	root.add_child(Build.box_mi(Vector3(0.10, 0.10, 0.22), Color(0.35, 0.38, 0.42),
		Vector3(0, 0, 0.11), 0.5, 0.008))
	root.add_child(Build.box_mi(Vector3(0.92, 0.54, 0.06), Color(0.16, 0.17, 0.20),
		Vector3(0, -0.02, 0.24), 0.5, 0.012))
	root.add_child(Build.box_mi(Vector3(0.84, 0.46, 0.02), Color(0.28, 0.46, 0.60),
		Vector3(0, -0.02, 0.275), 0.4, 0.0))
	root.add_child(Build.box_mi(Vector3(0.30, 0.10, 0.01), Color(0.62, 0.80, 0.88),
		Vector3(-0.20, 0.08, 0.286), 0.4, 0.0))
	root.add_child(Build.box_mi(Vector3(0.52, 0.05, 0.01), Color(0.52, 0.70, 0.80),
		Vector3(-0.10, -0.06, 0.286), 0.4, 0.0))
	return _add(h, root, pos, rot_y, 0.300)

## A water cooler. Nobody has ever seen one of these being refilled.
static func water_cooler(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "WaterCooler"
	root.add_child(Build.box_mi(Vector3(0.34, 0.92, 0.34), Color(0.90, 0.92, 0.94),
		Vector3(0, 0.46, 0), 0.6, 0.012))
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.30, 0.30), Vector2(0.16, 0.16), 0.46),
		Build.mat(Color(0.52, 0.80, 0.92, 1.0), 0.25), Vector3(0, 1.15, 0)))
	root.add_child(Build.box_mi(Vector3(0.10, 0.06, 0.06), Color(0.30, 0.55, 0.65),
		Vector3(0, 0.62, 0.19), 0.5, 0.006))
	root.add_child(Build.mi(Build.cyl_mesh(0.05, 0.34, 10),
		Build.mat(Color(0.94, 0.95, 0.96), 0.7), Vector3(0.22, 0.17, 0.10)))
	return _add(h, root, pos, rot_y)

## A vending machine, half empty, humming.
static func vending(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Vending"
	root.add_child(Build.box_mi(Vector3(0.90, 1.80, 0.60), Color(0.24, 0.30, 0.36),
		Vector3(0, 0.90, 0), 0.6, 0.014))
	root.add_child(Build.box_mi(Vector3(0.70, 1.24, 0.04), Color(0.14, 0.16, 0.20),
		Vector3(-0.05, 1.10, 0.30), 0.4, 0.008))
	var snacks := [Color(0.92, 0.62, 0.28), Color(0.36, 0.72, 0.52), Color(0.86, 0.36, 0.38),
		Color(0.42, 0.58, 0.86), Color(0.94, 0.84, 0.36)]
	for row in 4:
		for col in 4:
			if (row * 4 + col) % 5 == 3:
				continue
			root.add_child(Build.box_mi(Vector3(0.13, 0.18, 0.02),
				snacks[(row * 3 + col) % snacks.size()],
				Vector3(-0.29 + float(col) * 0.16, 0.62 + float(row) * 0.30, 0.315), 0.8, 0.006))
	root.add_child(Build.box_mi(Vector3(0.34, 0.20, 0.04), Color(0.10, 0.11, 0.13),
		Vector3(-0.05, 0.28, 0.31), 0.4, 0.008))
	root.add_child(Build.box_mi(Vector3(0.16, 0.30, 0.03), Color(0.55, 0.86, 0.80),
		Vector3(0.32, 1.20, 0.31), 0.4, 0.006))
	return _add(h, root, pos, rot_y)

## A whiteboard with a grid of nonsense on it and a pen tray.
static func whiteboard(h: Node3D, pos: Vector3, rot_y := 0.0, w := 1.6, tall := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Whiteboard"
	root.add_child(Build.box_mi(Vector3(w + 0.06, tall + 0.06, 0.05), Color(0.62, 0.66, 0.70),
		Vector3.ZERO, 0.5, 0.010))
	# RECESSED INTO THE FRAME, not standing on top of it. The frame is 5cm deep
	# and the writing surface sat at z=0.032 with a half-thickness of 0.01, so
	# it stuck 17mm PROUD of the thing that is supposed to hold it — a board
	# floating in front of its own bezel, which is the sort of detail that reads
	# as "assembled" without anybody being able to say why. It sits 7mm behind
	# the frame face now and everything drawn on it moved with it.
	root.add_child(Build.box_mi(Vector3(w, tall, 0.02), Color(0.96, 0.97, 0.97),
		Vector3(0, 0, 0.008), 0.35, 0.0))
	for i in 4:
		root.add_child(Build.box_mi(Vector3(w - 0.14, 0.012, 0.006), Color(0.45, 0.50, 0.55),
			Vector3(0, tall * 0.32 - float(i) * tall * 0.20, 0.019), 0.9, 0.0))
	for i in 3:
		root.add_child(Build.box_mi(Vector3(0.012, tall - 0.16, 0.006), Color(0.45, 0.50, 0.55),
			Vector3(-w * 0.28 + float(i) * w * 0.28, 0, 0.019), 0.9, 0.0))
	# THE FIFTH MAGNET WAS BELOW THE BOARD. The step was 0.19 of the height
	# starting from 0.22, so the last of five landed at -0.648 of a board whose
	# bottom edge is at -0.5 — four and a half centimetres of coloured plastic
	# floating in front of the pen tray, on all three whiteboards in the
	# building and at every size they are built at. A run that steps off the end
	# of the thing it is decorating is the same arithmetic fault whichever way
	# it goes; 0.16 keeps all five inside by a comfortable margin at any `tall`.
	for i in 5:
		root.add_child(Build.box_mi(Vector3(w * 0.18, 0.02, 0.006),
			[Color(0.24, 0.44, 0.82), Color(0.80, 0.26, 0.26)][i % 2],
			Vector3(-w * 0.24 + float(i % 3) * w * 0.26,
				tall * 0.32 - float(i) * tall * 0.16, 0.023), 0.9, 0.0))
	root.add_child(Build.box_mi(Vector3(w * 0.5, 0.04, 0.09), Color(0.55, 0.60, 0.64),
		Vector3(0, -tall * 0.5 - 0.04, 0.06), 0.5, 0.008))
	for i in 2:
		root.add_child(Build.mi(Build.cyl_mesh(0.014, 0.13, 8),
			Build.mat([Color(0.20, 0.22, 0.26), Color(0.80, 0.26, 0.26)][i], 0.5),
			Vector3(-0.10 + float(i) * 0.12, -tall * 0.5 - 0.01, 0.08),
			Vector3(0, 0, PI * 0.5)))
	return _add(h, root, pos, rot_y, 0.050)

## A bay of different-coloured flooring, with a border. Hospitals mark out the
## bit of the room the bed lives in, and a floor with a zone on it is a floor
## somebody planned rather than a coloured plane.
##
## IT IS PAINT ON THE VINYL, AND IT WAS A SLAB OF FLAT COLOUR LAID ON TOP.
##
## This is the largest single painted shape in the game — eighteen metres by
## four, about a third of the floor in `02_ward_from_door` — and it was two
## `box_mi` boxes, which is `rbox_mesh` plus `Build.mat`. Two things follow
## from that and both of them are visible in every ward frame this project has
## ever rendered:
##
##   * `rbox_mesh` is a Minkowski-summed sphere and puts its vertices on the
##     EDGES, so a slab eighteen metres across has nothing in the middle of it
##     to light. That is gotcha 2b in `shot_impl`'s own words — "a lamp three
##     metres above the middle of a twenty-metre floor had nothing to light" —
##     and it is why the floor is built from `slab_mesh` and subdivided. The
##     zone was not. Measured off `02_ward_from_door`: across the strip the
##     luma runs 118..124, a spread of SIX, while the plain vinyl in front of
##     it runs 194..242, a spread of forty-eight. Four ceiling fittings hang
##     over that strip and not one of them reached it.
##   * `Build.mat` is one flat albedo, so the speckle, the fleck and the welded
##     seam every two metres all STOPPED at the marking and picked up again on
##     the far side. A floor covering that stops is a different floor covering.
##
## Between them that is a grey platform the beds stand on rather than a bay
## marked out on the floor, with a hard straight edge across the middle of the
## hero frame. `Surfaces.floor_mat` is keyed to WORLD POSITION (that is the
## whole argument at the top of that file), so tinting it and laying it over
## the real floor continues the fleck and the seams straight through the
## marking, in register, which is what paint on vinyl does.
static func floor_zone(h: Node3D, centre: Vector3, size: Vector2, tint: Color,
		room := Rect2()) -> Node3D:
	var root := Node3D.new()
	root.name = "FloorZone"
	root.add_child(Build.floor_paint(Vector3(size.x, 0.012, size.y), tint,
		Vector3.ZERO, room))
	root.add_child(Build.floor_paint(Vector3(size.x - 0.14, 0.014, size.y - 0.14),
		tint.lightened(0.10), Vector3(0, 0.003, 0), room))
	return _add(h, root, Vector3(centre.x, 0.008, centre.z))

## IS THIS SPOT ALREADY BACKED BY A PIER?
##
## ASKED OF THE BUILDING, NOT OF A REGISTER, and the register is the version
## that had to be thrown away. A static list of "piers put in so far" is right
## for exactly one build: `Hospital.reskin` runs every morning and
## `Furniture.redress_ward` throws the whole ward's dressing away and makes it
## again — so from the first day rollover the register still held five bed-head
## piers that had been freed, said "already covered" to every fitting on that
## wall, and the ward went back to having its sharps bins hung on the window
## with nothing behind them. Same shape as gotcha 71: state bound to objects
## that get replaced reads as working and serialises an orphan.
##
## Each pier records its own span in a meta, and this walks the hospital's
## children. A freed node is not one of them, so the answer cannot go stale.
## The CENTRE, not the whole span: a piece that overhangs a pier by a few
## centimetres wants the pier it has rather than a second one overlapping it.
const PIER_SPAN := "pier_span"

static func _has_pier(h: Node3D, pos: Vector3, rot_y: float) -> bool:
	var along_x: bool = absf(sin(rot_y)) < 0.5
	for n in h.get_children():
		if not n.has_meta(PIER_SPAN):
			continue
		var p: Array = n.get_meta(PIER_SPAN)
		if bool(p[0]) != along_x:
			continue
		var plane: float = pos.z if along_x else pos.x
		if absf(float(p[1]) - plane) > 0.30:
			continue
		var c: float = pos.x if along_x else pos.z
		if c >= float(p[2]) - 0.05 and c <= float(p[3]) + 0.05:
			return true
	return false

## A PIER, because everything on an outside wall was mounted on GLASS.
##
## The ward's far wall is the north exterior run and `Hospital._glaze` puts one
## unbroken pane across all twenty metres of it from y 1.05 to 2.30 — which is
## exactly the band a bed head needs. So the oxygen outlets at 1.42 and the
## sharps bin at 1.15 were screwed to a window, five of each, in `03_bedside`:
## the frame this whole game is played through. A 20cm-deep yellow box hanging
## in front of the countryside with hedges visible round it is the same fault
## gotcha 13 is about, arriving from the other side — the mounting offset was
## right and there was nothing behind it to mount to.
##
## A pier between the windows is what a real ward has and what the glazing was
## missing: bed, pier, window, bed. It is scenery, so it costs nothing and
## takes no footprint; the pane behind it keeps the collision it always had.
static func wall_pier(h: Node3D, pos: Vector3, rot_y := 0.0,
		w := 1.66, tall := 0.0) -> Node3D:
	if tall <= 0.0:
		tall = Hospital.WIN_HEAD - Hospital.WIN_SILL
	var root := Node3D.new()
	root.name = "WallPier"
	# ITS OWN SPAN, ON ITSELF, and set before `_add` parents it — `_add` is what
	# asks whether a spot already has a pier, and building this one goes
	# through it.
	var along_x: bool = absf(sin(rot_y)) < 0.5
	var c: float = pos.x if along_x else pos.z
	root.set_meta(PIER_SPAN, [along_x, pos.z if along_x else pos.x,
		c - w * 0.5, c + w * 0.5])
	# `slab_mesh` and the wall's own shader rather than `box_mi`: this is a
	# piece of WALL, and a flat albedo panel between two shaded ones is the
	# fault gotcha 55 records about the title screen.
	# BEHIND THE FACE, NOT IN FRONT OF IT. `_add`'s convention is that the
	# position a wall piece is given is the plane its BACK sits on and
	# everything it is made of stands in front of that, into the room — so a
	# pier built the same way stands in front of the plaster and swallows
	# whatever is mounted on it. Measured on the first version: all five gas
	# panels 100% inside the pier and all five sharps bins 70%, which is the
	# fault this piece exists to fix, arriving from the other side. The mesh
	# sits at local -0.03 instead, filling the six centimetres of reveal behind
	# the plaster line. The pane is at the run's centreline with a 26mm
	# thickness, which is why it is six and not sixteen.
	root.add_child(Build.mi(Build.slab_mesh(Vector3(w, tall, 0.06)),
		Surfaces.wall_mat(Build.WALL_UPPER), Vector3(0, 0, -0.03)))
	# A reveal down each side in the window frame's own colour, so it reads as
	# the pier BETWEEN two windows rather than as a board screwed over one.
	# FLUSH WITH THE PLASTER AND NOT PROUD OF IT. Three centimetres of reveal
	# sticking into the room is three centimetres the piece hung on this pier
	# is standing inside: measured, the office's notice was 39% inside its own
	# backing and the station's noticeboard 27%. Everything a pier is made of
	# lives behind the face, same as the panel.
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.06, tall + 0.02, 0.07),
			Color(0.95, 0.94, 0.90),
			Vector3(-w * 0.5 + w * float(i), 0, -0.035), 0.6, 0.0))
	return _add(h, root, pos, rot_y)

## A folding privacy screen, parked. Three leaves at an angle, which is the one
## piece of hospital furniture that is always somewhere nobody put it.
static func screen_partition(h: Node3D, pos: Vector3, rot_y := 0.0,
		tint := Color(0.52, 0.72, 0.74)) -> Node3D:
	var root := Node3D.new()
	root.name = "ScreenPartition"
	for i in 3:
		var a: float = -0.5 + float(i) * 0.42
		# Stretched fabric on a frame, and it is built as fabric: the screen is
		# a metre and a half of one flat colour standing in the middle of the
		# ward, which is the largest unbroken surface in the room after the
		# floor and the wall.
		var leaf := Build.cloth_mi(Vector3(0.62, 1.62, 0.05), tint.lightened(0.05 * float(i % 2)),
			Vector3(a, 0.90, 0.10 * sin(float(i) * 2.1)), 0.010)
		leaf.rotation.y = 0.42 * (1.0 if i % 2 == 0 else -1.0)
		root.add_child(leaf)
		root.add_child(Build.box_mi(Vector3(0.10, 0.06, 0.10), Color(0.42, 0.46, 0.50),
			Vector3(a, 0.05, 0.10 * sin(float(i) * 2.1)), 0.5, 0.008))
	return _add(h, root, pos, rot_y)

## A rail of hooks by the door with one coat on it that nobody has claimed.
static func coat_hooks(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CoatHooks"
	root.add_child(Build.box_mi(Vector3(0.80, 0.09, 0.04), Color(0.55, 0.42, 0.30),
		Vector3.ZERO, 0.8, 0.008))
	for i in 4:
		root.add_child(Build.box_mi(Vector3(0.03, 0.10, 0.09), Color(0.62, 0.66, 0.70),
			Vector3(-0.30 + float(i) * 0.20, -0.06, 0.05), 0.5, 0.006))
	# The coat. One, always, on the second hook.
	root.add_child(Build.mi(Build.taper_mesh(Vector2(0.30, 0.14), Vector2(0.40, 0.18), 0.62),
		Build.mat(Color(0.34, 0.40, 0.52), 0.95), Vector3(-0.10, -0.36, 0.09)))
	root.add_child(Build.box_mi(Vector3(0.10, 0.10, 0.06), Color(0.34, 0.40, 0.52),
		Vector3(-0.10, -0.03, 0.07), 0.95, 0.006))
	return _add(h, root, pos, rot_y, 0.14)
