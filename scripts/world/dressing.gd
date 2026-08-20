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

static func _add(h: Node3D, n: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	h.add_child(n)
	n.position = pos
	n.rotation.y = rot_y
	return n

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
	return _add(h, root, pos, rot_y)

## A cork board with notes pinned to it at slightly wrong angles, because a
## noticeboard where everything is straight is a noticeboard nobody uses.
static func noticeboard(h: Node3D, pos: Vector3, rot_y: float, w := 1.5, tall := 1.0) -> Node3D:
	var root := Node3D.new()
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
	return _add(h, root, pos, rot_y)

## Framed art. Abstract, cheerful, and exactly as related to medicine as the
## art in a real waiting room.
static func wall_art(h: Node3D, pos: Vector3, rot_y: float, w := 0.9, tall := 0.7,
		a := Color(0.30, 0.70, 0.85), b := Color(0.98, 0.72, 0.32)) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(w, tall, 0.045), FRAME, Vector3.ZERO, 0.5, 0.010))
	root.add_child(Build.box_mi(Vector3(w - 0.08, tall - 0.08, 0.012),
		Color(0.95, 0.94, 0.90), Vector3(0, 0, 0.028), 0.9, 0.0))
	root.add_child(Build.mi(Build.cyl_mesh(tall * 0.24, 0.01, 16), Build.mat(a, 0.8),
		Vector3(-w * 0.16, tall * 0.06, 0.036), Vector3(PI * 0.5, 0, 0)))
	root.add_child(Build.box_mi(Vector3(w * 0.30, tall * 0.30, 0.01), b,
		Vector3(w * 0.18, -tall * 0.10, 0.036), 0.8, 0.006))
	root.add_child(Build.box_mi(Vector3(w * 0.62, 0.03, 0.01), Color(0.28, 0.32, 0.36),
		Vector3(0, -tall * 0.30, 0.036), 0.8, 0.0))
	return _add(h, root, pos, rot_y)

# ------------------------------------------------------------------ fittings
## A privacy curtain on a rail, gathered at one end. Gathered rather than drawn
## because a drawn curtain hides the bed, and the bed is where the game is.
static func curtain(h: Node3D, pos: Vector3, span: float, rot_y := 0.0,
		tint := Color(0.36, 0.68, 0.72)) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.mi(Build.cyl_mesh(0.022, span, 10), Build.mat(STEEL, 0.4, 0.6),
		Vector3(0, 2.28, 0), Vector3(0, 0, PI * 0.5)))
	for i in 2:
		root.add_child(Build.box_mi(Vector3(0.05, 0.16, 0.05), STEEL,
			Vector3(-span * 0.5 + float(i) * span, 2.36, 0), 0.4, 0.008))
	# The gather: seven slats of slightly different depth, which is what a
	# bunched curtain is when you look at one.
	for i in 7:
		var t := float(i) / 6.0
		var slat := Build.box_mi(Vector3(0.11, 1.86, 0.055 + 0.03 * sin(t * PI * 3.0)),
			tint.lightened(0.06 * sin(t * PI * 2.0)),
			Vector3(-span * 0.5 + 0.10 + t * 0.62, 1.30, 0.02 * sin(t * 9.0)), 0.92, 0.010)
		root.add_child(slat)
	return _add(h, root, pos, rot_y)

## Gas outlets behind a bed. Four coloured spigots on a steel plate: the single
## most "this is a hospital" object per polygon in the entire building.
static func oxygen_panel(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
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
	return _add(h, root, pos, rot_y)

## Sharps bin. Yellow, lidded, and the correct kind of ominous.
static func sharps(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(0.26, 0.30, 0.20), Color(0.98, 0.80, 0.14),
		Vector3.ZERO, 0.8, 0.010))
	root.add_child(Build.box_mi(Vector3(0.27, 0.07, 0.21), Color(0.92, 0.36, 0.20),
		Vector3(0, 0.18, 0), 0.7, 0.008))
	root.add_child(Build.box_mi(Vector3(0.14, 0.02, 0.06), Color(0.25, 0.20, 0.10),
		Vector3(0, 0.215, 0.02), 0.9, 0.0))
	return _add(h, root, pos, rot_y)

## Hand gel by the door. Everybody in the building walks past one of these
## fifty times a shift and the player is about to as well.
static func dispenser(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(0.16, 0.28, 0.11), Color(0.92, 0.94, 0.96),
		Vector3.ZERO, 0.55, 0.008))
	root.add_child(Build.box_mi(Vector3(0.10, 0.16, 0.06), Color(0.55, 0.86, 0.80),
		Vector3(0, 0.01, 0.055), 0.35, 0.006))
	root.add_child(Build.box_mi(Vector3(0.09, 0.04, 0.05), Color(0.35, 0.40, 0.44),
		Vector3(0, -0.16, 0.04), 0.6, 0.006))
	return _add(h, root, pos, rot_y)

static func extinguisher(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(0.30, 0.50, 0.03), Color(0.90, 0.90, 0.88),
		Vector3(0, 0.05, 0), 0.9, 0.0))
	root.add_child(Build.mi(Build.cyl_mesh(0.085, 0.42, 12),
		Build.mat(Color(0.88, 0.20, 0.18), 0.5, 0.1), Vector3(0, 0, 0.11)))
	root.add_child(Build.mi(Build.cyl_mesh(0.028, 0.10, 8), Build.mat(STEEL, 0.4, 0.7),
		Vector3(0, 0.25, 0.11)))
	root.add_child(Build.box_mi(Vector3(0.12, 0.03, 0.03), Color(0.20, 0.22, 0.24),
		Vector3(0.06, 0.29, 0.11), 0.6, 0.006))
	return _add(h, root, pos, rot_y)

static func clock(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
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
	return _add(h, root, pos, rot_y)

## A ceiling vent. Four slats in a frame — the thing that stops a ceiling being
## an unbroken plane across the top third of every shot.
static func vent(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(0.62, 0.04, 0.42), Color(0.88, 0.89, 0.87),
		Vector3.ZERO, 0.5, 0.008))
	for i in 4:
		root.add_child(Build.box_mi(Vector3(0.54, 0.02, 0.055), Color(0.55, 0.58, 0.60),
			Vector3(0, -0.028, -0.14 + float(i) * 0.093), 0.7, 0.0))
	return _add(h, root, pos, rot_y)

static func sprinkler(h: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.mi(Build.cyl_mesh(0.045, 0.05, 10), Build.mat(STEEL, 0.35, 0.7),
		Vector3.ZERO))
	root.add_child(Build.mi(Build.cyl_mesh(0.018, 0.07, 8),
		Build.mat(Color(0.85, 0.45, 0.25), 0.4, 0.3), Vector3(0, -0.055, 0)))
	return _add(h, root, pos)

## A rail along a corridor wall, with brackets. Runs from x0 to x1 at a fixed z.
static func handrail(h: Node3D, x0: float, x1: float, z: float, y := 0.92,
		tint := Color(0.78, 0.62, 0.38)) -> Node3D:
	var root := Node3D.new()
	var span: float = absf(x1 - x0)
	root.add_child(Build.mi(Build.cyl_mesh(0.045, span, 10), Build.mat(tint, 0.6),
		Vector3.ZERO, Vector3(0, 0, PI * 0.5)))
	var brackets := maxi(2, int(span / 2.4))
	for i in brackets:
		var t: float = float(i) / float(maxi(1, brackets - 1))
		root.add_child(Build.box_mi(Vector3(0.05, 0.05, 0.14), Color(0.55, 0.58, 0.62),
			Vector3(-span * 0.5 + t * span, 0, -0.09), 0.5, 0.006))
	return _add(h, root, Vector3((x0 + x1) * 0.5, y, z))

## Guide lines on the floor. Follow the blue line to Radiology, and so on: the
## cheapest wayfinding in architecture and the cheapest here too.
static func floor_line(h: Node3D, x0: float, x1: float, z: float, tint: Color,
		width := 0.10) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.box_mi(Vector3(absf(x1 - x0), 0.012, width), tint,
		Vector3.ZERO, 0.6, 0.0))
	return _add(h, root, Vector3((x0 + x1) * 0.5, 0.008, z))

## A hanging sign, the kind every hospital corridor has too many of.
static func ceiling_sign(h: Node3D, pos: Vector3, text: String, rot_y := 0.0,
		tint := Color(0.16, 0.42, 0.52)) -> Node3D:
	var root := Node3D.new()
	for dx in [-0.55, 0.55]:
		root.add_child(Build.mi(Build.cyl_mesh(0.012, 0.34, 6), Build.mat(STEEL, 0.4, 0.6),
			Vector3(dx, 0.30, 0)))
	root.add_child(Build.box_mi(Vector3(1.5, 0.34, 0.06), tint, Vector3.ZERO, 0.7, 0.010))
	var l := Build.label3d(text, 0.17, Color(0.96, 0.98, 0.98), false)
	l.position = Vector3(0, 0, 0.045)
	root.add_child(l)
	var back := Build.label3d(text, 0.17, Color(0.96, 0.98, 0.98), false)
	back.position = Vector3(0, 0, -0.045)
	back.rotation.y = PI
	root.add_child(back)
	return _add(h, root, pos, rot_y)

# ------------------------------------------------------------------ clutter
## Everything below stands on the floor and is small enough to walk around
## without a footprint. Anything bigger than a bin belongs in Furniture.
static func bin(h: Node3D, pos: Vector3, tint := Color(0.32, 0.55, 0.62),
		pedal := true) -> Node3D:
	var root := Node3D.new()
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
	for i in 4:
		root.add_child(Build.box_mi(Vector3(0.40, 0.07, 0.30),
			Color(0.94, 0.95, 0.97).darkened(0.045 * float(i % 2)),
			Vector3(0.012 * float(i % 3), 0.04 + float(i) * 0.075, 0), 0.95, 0.008))
	return _add(h, root, pos, rot_y)

static func mop_bucket(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
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
	for i in 5:
		root.add_child(Build.box_mi(Vector3(0.34, 0.035, 0.26),
			[Color(0.36, 0.68, 0.72), Color(0.94, 0.86, 0.42)][i % 2],
			Vector3(0, float(i) * 0.05, 0), 0.8, 0.006))
	return _add(h, root, pos, rot_y)

## A mug and a stack of paper on a desk, which is the difference between a desk
## and a table.
static func desk_clutter(h: Node3D, pos: Vector3, rot_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.add_child(Build.mi(Build.cyl_mesh(0.043, 0.10, 10),
		Build.mat(Color(0.92, 0.44, 0.36), 0.6), Vector3(0.22, 0.05, 0.04)))
	root.add_child(Build.box_mi(Vector3(0.02, 0.05, 0.05), Color(0.92, 0.44, 0.36),
		Vector3(0.27, 0.06, 0.04), 0.6, 0.006))
	for i in 6:
		root.add_child(Build.box_mi(Vector3(0.22, 0.006, 0.30), PAPER,
			Vector3(0.004 * float(i % 3), 0.004 + float(i) * 0.007, 0), 0.95, 0.0))
	root.add_child(Build.box_mi(Vector3(0.10, 0.02, 0.10), Color(0.35, 0.40, 0.44),
		Vector3(-0.24, 0.01, 0.06), 0.6, 0.006))
	for i in 3:
		var pen := Build.box_mi(Vector3(0.012, 0.012, 0.15),
			[Color(0.25, 0.45, 0.85), Color(0.90, 0.30, 0.30), Color(0.30, 0.70, 0.45)][i],
			Vector3(-0.24 + 0.02 * float(i), 0.08, 0.06), 0.5, 0.0)
		pen.rotation = Vector3(1.25 + 0.1 * float(i), 0.2 * float(i), 0)
		root.add_child(pen)
	return _add(h, root, pos, rot_y)
