class_name Anatomy
extends RefCounted
## Drawing people, one part at a time.
##
## The procedure screens used to be abstractions — a needle sweeping a coloured
## bar, six numbered buttons in a row. They tested the same reflex whatever was
## wrong with the patient, and the playtest note was exactly right: "make the
## minigames show the body part you are treating, it should be med themed, not
## just some reaction test."
##
## So every procedure now happens on a drawing of the actual part: a forearm
## with a radius and an ulna in it and a hand on the end, an ankle with a foot,
## a ribcage, a shoulder with a ball in a socket. The thing you drag IS the
## distal fragment, and the hand on the end of it swings when the fragment does.
##
## EVERYTHING HERE IS A CAPSULE.
##
## One primitive — a line with a radius at each end — draws limbs, palms,
## fingers, ribs, skulls and bones, and a circle is just a capsule whose ends
## are in the same place. That matters for more than tidiness: a group of
## capsules is drawn as GROWN-DARK-FIRST, then filled, so the outlines of
## overlapping pieces are covered by their neighbours' fill and a hand reads as
## one object with a line around it rather than as five sausages in a bag.
##
## Rigs are unit-space (0..1 across the field, 0..1 down it) so the same forearm
## draws at any field size, and radii are in units of the field HEIGHT so parts
## do not stretch when the field is wide.

const OUTLINE := Color(0.12, 0.10, 0.13, 1.0)
const BONE := Color(0.97, 0.94, 0.84)
const BONE_SHADE := Color(0.72, 0.69, 0.62)
const BONE_GHOST := Color(0.55, 0.90, 0.82, 0.55)
const NAIL := Color(0.98, 0.90, 0.86)
const FLESH := Color(0.62, 0.24, 0.26)
const BLOOD := Color(0.48, 0.13, 0.16)
const THREAD := Color(0.16, 0.16, 0.20)
const GLASS := Color(0.82, 0.92, 0.95, 0.30)
const FLUID := Color(0.55, 0.86, 0.78, 0.92)

## A handful of skin tones, picked per person rather than per screen, so it is
## recognisably the same patient's arm every time you open them up.
const TONES := [
	Color(0.96, 0.80, 0.68), Color(0.90, 0.71, 0.56), Color(0.79, 0.58, 0.43),
	Color(0.62, 0.43, 0.31), Color(0.45, 0.30, 0.22), Color(0.98, 0.86, 0.76),
]

static func tone_for(who: String) -> Color:
	return TONES[absi(hash(who)) % TONES.size()]

# ------------------------------------------------------------------ primitive
## A tapered capsule as a closed polygon. `pad` grows it, which is how the dark
## silhouette under a group is drawn.
static func capsule_poly(a: Vector2, b: Vector2, ra: float, rb: float,
		pad := 0.0, cap_steps := 12) -> PackedVector2Array:
	var out := PackedVector2Array()
	ra += pad
	rb += pad
	var d := (b - a)
	if d.length() < 0.0001:
		d = Vector2.RIGHT
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	var ang := d.angle()
	out.append(a + n * ra)
	out.append(b + n * rb)
	for i in range(cap_steps + 1):
		out.append(b + Vector2.from_angle(ang + PI * 0.5 - PI * float(i) / float(cap_steps)) * rb)
	out.append(b - n * rb)
	out.append(a - n * ra)
	for i in range(cap_steps + 1):
		out.append(a + Vector2.from_angle(ang - PI * 0.5 - PI * float(i) / float(cap_steps)) * ra)
	return out

static func outline_poly(ci: CanvasItem, poly: PackedVector2Array, width := 3.0,
		colour := OUTLINE) -> void:
	if poly.size() < 2:
		return
	var closed := poly.duplicate()
	closed.append(poly[0])
	ci.draw_polyline(closed, colour, width, true)

## One capsule in a rig: unit-space ends, unit-height radii, and which palette
## slot it is painted from.
static func cap(ax: float, ay: float, bx: float, by: float, ra: float,
		rb := -1.0, slot := "skin") -> Dictionary:
	return {"a": Vector2(ax, ay), "b": Vector2(bx, by), "ra": ra,
		"rb": rb if rb >= 0.0 else ra, "slot": slot}

static func dot(x: float, y: float, r: float, slot := "bone") -> Dictionary:
	return cap(x, y, x, y, r, r, slot)

static func _slot_colour(slot: String, tone: Color) -> Color:
	match slot:
		"bone": return BONE
		"nail": return tone.lightened(0.34)
		"shade": return tone.darkened(0.18)
		"pale": return tone.lightened(0.14)
	return tone

## Draw a group of capsules as one object: dark silhouette under everything,
## then every fill, then a soft highlight on the fat ones. `xf` moves the whole
## group, which is how a distal fragment swings with its hand attached.
static func draw_caps(ci: CanvasItem, caps: Array, field: Vector2, tone: Color,
		xf := Transform2D.IDENTITY, alpha := 1.0, rim := 3.2) -> void:
	var polys: Array = []
	for c in caps:
		var a: Vector2 = xf * (Vector2(c["a"]) * field)
		var b: Vector2 = xf * (Vector2(c["b"]) * field)
		var ra: float = float(c["ra"]) * field.y
		var rb: float = float(c["rb"]) * field.y
		polys.append({"a": a, "b": b, "ra": ra, "rb": rb, "slot": String(c["slot"])})
	if rim > 0.0:
		var dark := OUTLINE
		dark.a = alpha
		for p in polys:
			ci.draw_colored_polygon(capsule_poly(p["a"], p["b"], p["ra"], p["rb"], rim), dark)
	for p in polys:
		var col := _slot_colour(String(p["slot"]), tone)
		col.a = alpha
		ci.draw_colored_polygon(capsule_poly(p["a"], p["b"], p["ra"], p["rb"]), col)
	# The highlight: a thin capsule up and to the left inside the fat pieces.
	# Small and offset rather than a scaled copy of the whole shape, which is
	# what made the first version look like a sausage inside a sausage.
	for p in polys:
		if float(p["ra"]) < 9.0 or String(p["slot"]) == "bone":
			continue
		var lit := _slot_colour(String(p["slot"]), tone).lightened(0.20)
		lit.a = 0.52 * alpha
		var shift := Vector2(-1.2, -1.0).normalized() * float(p["ra"]) * 0.40
		ci.draw_colored_polygon(capsule_poly(
			Vector2(p["a"]) + shift, Vector2(p["b"]) + shift,
			float(p["ra"]) * 0.40, float(p["rb"]) * 0.40), lit)

## The broken end. Not a flat cut — three teeth, because a flat cut reads as a
## sliced sausage and this is meant to make you wince slightly.
static func draw_fracture_end(ci: CanvasItem, at: Vector2, dir: Vector2, r: float,
		xf := Transform2D.IDENTITY) -> void:
	var n := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([
		at + n * r, at + n * r * 0.4 + dir * r * 0.7, at - dir * r * 0.15,
		at - n * r * 0.45 + dir * r * 0.6, at - n * r,
	])
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(xf * p)
	ci.draw_polyline(moved, BONE_SHADE, 2.5, true)

# ------------------------------------------------------------------ the rigs
## Display names, and the registry of what can be drawn at all.
const PART_NAMES := {
	"forearm": "left forearm",
	"wrist": "right wrist",
	"hand": "right hand",
	"ankle": "right ankle",
	"knee": "left knee",
	"shoulder": "left shoulder",
	"ribs": "lower ribs",
	"brow": "brow and nasal bridge",
	"flank": "left flank",
}

static func part_name(part: String) -> String:
	return String(PART_NAMES.get(part, "limb"))

## A rig is: what is fixed (`prox`), what is in your hands (`dist`), the bones
## inside each, where the break is, and where a laceration would run.
static func rig(part: String) -> Dictionary:
	match part:
		"wrist": return _rig_forearm(0.70)
		"hand": return _rig_hand()
		"ankle": return _rig_ankle()
		"knee": return _rig_knee()
		"shoulder": return _rig_shoulder()
		"ribs": return _rig_ribs()
		"brow": return _rig_brow()
		"flank": return _rig_flank()
	return _rig_forearm(0.52)

## Fingers, fanned off a palm. Used by the hand and by both forearm rigs, so a
## wrist and a hand are the same fingers.
static func _fingers(base: Vector2, dir: Vector2, span: float, length: float,
		slot := "skin") -> Array:
	var out: Array = []
	var n := dir.orthogonal().normalized()
	for i in 4:
		var t: float = (float(i) / 3.0 - 0.5) * span
		var l: float = length * (0.80 + 0.24 * sin((float(i) + 0.6) * 1.1))
		var a: Vector2 = base + n * t
		var b: Vector2 = a + dir * l + n * t * 0.22
		out.append(cap(a.x, a.y, b.x, b.y, 0.025, 0.022, slot))
		# The nail sits IN the fingertip, not past it. A dot beyond the end of
		# the finger reads as a claw, which is not the register this game wants.
		var tip: Vector2 = b - dir * 0.006
		out.append(cap(tip.x, tip.y, tip.x, tip.y, 0.010, 0.010, "nail"))
	return out

## Elbow on the left, hand on the right. `brk` is how far along the fracture
## sits, which is the only difference between "forearm" and "wrist".
##
## Built from two points and a direction rather than from thirty literals: the
## first version was hand-typed coordinates and it took four passes to stop it
## looking like a baguette with fingers.
static func _rig_forearm(brk: float) -> Dictionary:
	var elbow := Vector2(0.135, 0.735)
	var wristp := Vector2(0.690, 0.415)
	var d := (wristp - elbow).normalized()
	var n := d.orthogonal()
	var pivot := elbow + (wristp - elbow) * brk
	var prox: Array = [
		cap(elbow.x, elbow.y, elbow.x, elbow.y, 0.140),           # elbow
		cap(elbow.x, elbow.y, pivot.x, pivot.y, 0.128, 0.104),
	]
	var pbone: Array = [
		_bone_between(elbow + d * 0.03 - n * 0.030, pivot - n * 0.028, 0.022, 0.019),
		_bone_between(elbow + d * 0.03 + n * 0.034, pivot + n * 0.030, 0.018, 0.015),
	]
	var palm := wristp + d * 0.062
	var dist: Array = [
		cap(pivot.x, pivot.y, wristp.x, wristp.y, 0.104, 0.084),
		cap(wristp.x, wristp.y, palm.x, palm.y, 0.084, 0.100),    # palm
	]
	var thumb_a := wristp + d * 0.020 + n * 0.082
	var thumb_b := thumb_a + (d * 0.5 + n * 0.9).normalized() * 0.072
	dist.append(cap(thumb_a.x, thumb_a.y, thumb_b.x, thumb_b.y, 0.030, 0.025))
	dist.append_array(_fingers(palm + d * 0.026, d, 0.168, 0.078))
	var dbone: Array = [
		_bone_between(pivot + d * 0.014 - n * 0.028, wristp - n * 0.024, 0.021, 0.018),
		_bone_between(pivot + d * 0.014 + n * 0.030, wristp + n * 0.026, 0.017, 0.014),
		dot((wristp + d * 0.016).x, (wristp + d * 0.016).y, 0.022),
		dot((wristp + d * 0.032 - n * 0.030).x, (wristp + d * 0.032 - n * 0.030).y, 0.017),
		dot((wristp + d * 0.032 + n * 0.030).x, (wristp + d * 0.032 + n * 0.030).y, 0.017),
	]
	for i in 4:
		var t: float = (float(i) / 3.0 - 0.5) * 0.168
		var a: Vector2 = palm - d * 0.030 + n * t * 0.6
		var b: Vector2 = palm + d * 0.026 + n * t
		dbone.append(_bone_between(a, b, 0.011, 0.009))
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": d, "bone_r": 0.024,
		"wound": [elbow + (wristp - elbow) * 0.18 + n * 0.055,
			elbow + (wristp - elbow) * 0.72 + n * 0.040],
	}

static func _bone_between(a: Vector2, b: Vector2, ra: float, rb: float) -> Dictionary:
	return cap(a.x, a.y, b.x, b.y, ra, rb, "bone")

static func _rig_hand() -> Dictionary:
	var pivot := Vector2(0.60, 0.48)
	var prox: Array = [
		cap(0.16, 0.52, 0.42, 0.50, 0.115, 0.100),               # wrist
		cap(0.42, 0.50, pivot.x, pivot.y, 0.100, 0.108),         # palm
		cap(0.545, 0.580, 0.640, 0.650, 0.030, 0.025),           # thumb
	]
	var pbone: Array = [
		cap(0.19, 0.505, 0.41, 0.492, 0.030, 0.026, "bone"),
		cap(0.19, 0.552, 0.41, 0.530, 0.024, 0.021, "bone"),
		dot(0.45, 0.500, 0.028), dot(0.475, 0.470, 0.022), dot(0.475, 0.532, 0.022),
	]
	var dist: Array = _fingers(Vector2(0.645, 0.470), Vector2(1.0, -0.05).normalized(),
		0.190, 0.115)
	var dbone: Array = []
	for i in 4:
		var t: float = (float(i) / 3.0 - 0.5) * 0.190
		dbone.append(cap(0.60, 0.470 + t * 0.6, 0.70, 0.470 + t, 0.013, 0.011, "bone"))
		dbone.append(cap(0.71, 0.470 + t * 1.05, 0.79, 0.470 + t * 1.25, 0.011, 0.009, "bone"))
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(1.0, -0.05).normalized(),
		"bone_r": 0.020, "wound": [Vector2(0.26, 0.470), Vector2(0.58, 0.446)],
	}

static func _rig_ankle() -> Dictionary:
	var pivot := Vector2(0.415, 0.640)
	var prox: Array = [
		cap(0.345, 0.070, pivot.x, pivot.y, 0.108, 0.088),       # shin
		cap(0.345, 0.070, 0.345, 0.070, 0.115),                  # knee end
	]
	var pbone: Array = [
		cap(0.352, 0.110, 0.408, 0.610, 0.032, 0.028, "bone"),   # tibia
		cap(0.400, 0.140, 0.442, 0.596, 0.019, 0.016, "bone"),   # fibula
	]
	var heel := Vector2(0.395, 0.800)
	var dist: Array = [
		cap(pivot.x, pivot.y, heel.x, heel.y, 0.086, 0.080),
		cap(heel.x, heel.y, 0.660, 0.828, 0.080, 0.052),         # foot
	]
	dist.append_array(_fingers(Vector2(0.680, 0.822), Vector2(1.0, 0.10).normalized(),
		0.070, 0.036))
	var dbone: Array = [
		dot(pivot.x + 0.012, pivot.y + 0.030, 0.038),            # talus
		dot(0.398, 0.766, 0.042),                                # calcaneus
	]
	for i in 3:
		dbone.append(cap(0.450, 0.790 + float(i) * 0.016, 0.640, 0.818 + float(i) * 0.012,
			0.014, 0.011, "bone"))
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(0.10, 1.0).normalized(),
		"bone_r": 0.032, "wound": [Vector2(0.300, 0.260), Vector2(0.372, 0.600)],
	}

static func _rig_knee() -> Dictionary:
	var pivot := Vector2(0.455, 0.490)
	var prox: Array = [
		cap(0.290, 0.040, pivot.x, pivot.y, 0.140, 0.112),       # thigh
	]
	var pbone: Array = [
		cap(0.302, 0.080, 0.448, 0.452, 0.036, 0.030, "bone"),   # femur
		dot(0.455, 0.470, 0.040),                                # condyle
	]
	var dist: Array = [
		cap(pivot.x, pivot.y, 0.560, 0.930, 0.110, 0.086),       # shin
	]
	var dbone: Array = [
		dot(0.500, 0.498, 0.052),                                # patella
		cap(0.470, 0.548, 0.556, 0.900, 0.032, 0.027, "bone"),
		cap(0.518, 0.566, 0.586, 0.884, 0.017, 0.014, "bone"),
	]
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(0.22, 1.0).normalized(),
		"bone_r": 0.036, "wound": [Vector2(0.352, 0.190), Vector2(0.420, 0.430)],
	}

static func _rig_shoulder() -> Dictionary:
	var pivot := Vector2(0.440, 0.360)
	var prox: Array = [
		cap(0.090, 0.300, 0.330, 0.560, 0.210, 0.195),           # chest wall
	]
	var pbone: Array = [
		cap(0.150, 0.290, 0.420, 0.336, 0.024, 0.020, "bone"),   # clavicle
		dot(0.352, 0.430, 0.072),                                # scapula
	]
	var dist: Array = [
		cap(pivot.x, pivot.y, 0.760, 0.610, 0.118, 0.092),       # upper arm
		cap(0.760, 0.610, 0.880, 0.700, 0.090, 0.080),           # elbow onward
	]
	var dbone: Array = [
		dot(0.452, 0.376, 0.066),                                # humeral head
		cap(0.478, 0.396, 0.762, 0.606, 0.032, 0.026, "bone"),
	]
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(1.0, 0.62).normalized(),
		"bone_r": 0.034, "wound": [Vector2(0.180, 0.330), Vector2(0.400, 0.470)],
	}

## A ribcage seen from the side. Each rib is a chain of three capsules, which is
## the cheapest arc there is; the fractured one is the fourth, and its outer
## half is what swings.
static func _rig_ribs() -> Dictionary:
	var pivot := Vector2(0.520, 0.420)
	var prox: Array = [
		cap(0.120, 0.300, 0.880, 0.400, 0.215, 0.185),           # torso
	]
	var pbone: Array = [
		cap(0.150, 0.230, 0.150, 0.690, 0.030, 0.030, "bone"),   # spine
	]
	for i in 5:
		var y: float = 0.250 + float(i) * 0.082
		var sag: float = 0.030 + float(i) * 0.012
		if i == 3:
			# The broken one: only the half nearest the spine stays put.
			pbone.append(cap(0.178, y, 0.380, y + sag, 0.020, 0.018, "bone"))
			continue
		pbone.append(cap(0.178, y, 0.420, y + sag, 0.020, 0.018, "bone"))
		pbone.append(cap(0.420, y + sag, 0.660, y + sag * 1.5, 0.018, 0.016, "bone"))
		pbone.append(cap(0.660, y + sag * 1.5, 0.800, y + sag * 1.2, 0.016, 0.014, "bone"))
	var dist: Array = [
		cap(0.500, 0.398, 0.760, 0.436, 0.070, 0.060, "pale"),   # the flesh over it
	]
	var dbone: Array = [
		cap(0.400, 0.496, 0.640, 0.520, 0.019, 0.016, "bone"),
		cap(0.640, 0.520, 0.790, 0.508, 0.016, 0.014, "bone"),
	]
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(1.0, 0.10).normalized(),
		"bone_r": 0.020, "wound": [Vector2(0.300, 0.300), Vector2(0.720, 0.360)],
	}

static func _rig_brow() -> Dictionary:
	var pivot := Vector2(0.500, 0.470)
	var prox: Array = [
		dot(0.430, 0.400, 0.215, "skin"),                        # cranium
		cap(0.380, 0.600, 0.590, 0.640, 0.105, 0.088),           # jaw
		cap(0.300, 0.470, 0.300, 0.470, 0.050),                  # ear
	]
	var pbone: Array = [
		dot(0.430, 0.392, 0.175),                                # skull
		cap(0.400, 0.610, 0.575, 0.640, 0.030, 0.024, "bone"),
	]
	var dist: Array = [
		cap(pivot.x, pivot.y, 0.615, 0.540, 0.070, 0.048),       # nose
	]
	var dbone: Array = [
		cap(pivot.x + 0.006, pivot.y - 0.006, 0.590, 0.530, 0.024, 0.016, "bone"),
	]
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(1.0, 0.42).normalized(),
		"bone_r": 0.024, "wound": [Vector2(0.330, 0.255), Vector2(0.560, 0.320)],
	}

static func _rig_flank() -> Dictionary:
	var pivot := Vector2(0.560, 0.480)
	var prox: Array = [
		cap(0.110, 0.260, 0.860, 0.520, 0.200, 0.170),
	]
	var pbone: Array = [
		cap(0.160, 0.230, 0.160, 0.640, 0.028, 0.028, "bone"),
	]
	for i in 3:
		var y: float = 0.330 + float(i) * 0.090
		pbone.append(cap(0.188, y, 0.430, y + 0.040, 0.019, 0.016, "bone"))
		if i != 1:
			pbone.append(cap(0.430, y + 0.040, 0.700, y + 0.062, 0.016, 0.013, "bone"))
	var dist: Array = [
		cap(0.520, 0.460, 0.780, 0.520, 0.062, 0.052, "pale"),
	]
	var dbone: Array = [
		cap(0.430, 0.460, 0.720, 0.492, 0.016, 0.013, "bone"),
	]
	return {
		"prox": prox, "dist": dist, "pbone": pbone, "dbone": dbone,
		"pivot": pivot, "axis": Vector2(1.0, 0.16).normalized(),
		"bone_r": 0.018, "wound": [Vector2(0.260, 0.300), Vector2(0.700, 0.400)],
	}

## The whole part, unmoving — what the suture and dose screens stand on.
static func draw_part(ci: CanvasItem, part: String, field: Vector2, tone: Color,
		xf := Transform2D.IDENTITY, with_bones := false) -> void:
	var r := rig(part)
	var all: Array = []
	all.append_array(r["prox"])
	all.append_array(r["dist"])
	draw_caps(ci, all, field, tone, xf)
	if with_bones:
		var bones: Array = []
		bones.append_array(r["pbone"])
		bones.append_array(r["dbone"])
		draw_caps(ci, bones, field, tone, xf, 0.85, 2.0)

## The part mid-procedure: fixed half, swinging half, and the bones showing
## through both like a lamp behind a hand.
static func draw_part_split(ci: CanvasItem, part: String, field: Vector2, tone: Color,
		xf: Transform2D, bone_alpha := 0.55) -> Dictionary:
	var r := rig(part)
	draw_caps(ci, r["prox"], field, tone)
	draw_caps(ci, r["dist"], field, tone, xf)
	draw_caps(ci, r["pbone"], field, tone, Transform2D.IDENTITY, bone_alpha, 2.0)
	draw_caps(ci, r["dbone"], field, tone, xf, bone_alpha, 2.0)
	return r

# ------------------------------------------------------------------ wounds
## An irregular line across a patch of skin. Deterministic from `seed_value`, so
## the same laceration on the same patient looks the same every time you open
## the screen, which matters as soon as you have had to come back to one.
static func wound_centreline(a: Vector2, b: Vector2, seed_value: int,
		steps := 14, jag := 9.0) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := (b - a)
	var n := Vector2(-d.y, d.x).normalized()
	var out := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		out.append(a + d * t + n * rng.randf_range(-jag, jag) * sin(t * PI))
	return out

## The wound itself. `open` is per-vertex separation in pixels — as stitches go
## in, the lips either side pull together and the red between them narrows.
static func draw_wound(ci: CanvasItem, line: PackedVector2Array, open: Array,
		tone: Color) -> void:
	if line.size() < 2:
		return
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i in line.size():
		var prev: Vector2 = line[maxi(i - 1, 0)]
		var next: Vector2 = line[mini(i + 1, line.size() - 1)]
		var n := (next - prev).orthogonal().normalized()
		var w: float = float(open[i]) if i < open.size() else 6.0
		upper.append(line[i] + n * w)
		lower.append(line[i] - n * w)
	var poly := upper.duplicate()
	for i in range(lower.size() - 1, -1, -1):
		poly.append(lower[i])
	ci.draw_colored_polygon(poly, FLESH)
	ci.draw_polyline(line, BLOOD, 3.0, true)
	var bruise := tone.darkened(0.26)
	bruise.a = 0.55
	ci.draw_polyline(upper, bruise, 5.0, true)
	ci.draw_polyline(lower, bruise, 5.0, true)
	outline_poly(ci, poly, 2.0, OUTLINE)

## One stitch: a cross of thread over the wound with a knot on it.
static func draw_stitch(ci: CanvasItem, at: Vector2, along: Vector2, reach: float,
		quality: float) -> void:
	var n := along.orthogonal().normalized() * reach
	var t := along.normalized() * reach * 0.45
	var skew: float = (1.0 - quality) * reach * 0.55
	ci.draw_line(at - n - t, at + n + t + Vector2(skew, 0), THREAD, 3.0, true)
	ci.draw_line(at - n + t + Vector2(skew, 0), at + n - t, THREAD, 3.0, true)
	ci.draw_circle(at, 3.0, THREAD)

## Where the next stitch wants to go. A cross-hair on the skin, not a button.
static func draw_target(ci: CanvasItem, at: Vector2, along: Vector2, reach: float,
		colour: Color, pulse := 1.0) -> void:
	var n := along.orthogonal().normalized() * reach * pulse
	ci.draw_line(at - n, at + n, colour, 2.0, true)
	ci.draw_arc(at, reach * 0.62 * pulse, 0.0, TAU, 20, colour, 2.0, true)

# ------------------------------------------------------------------ syringe
## A barrel with graduations, a plunger, and two marks on it: the one printed on
## the side by the manufacturer, and the one you are actually aiming at.
static func draw_syringe(ci: CanvasItem, rect: Rect2, level: float, target: float,
		tolerance: float, target_colour: Color) -> void:
	var barrel := Rect2(rect.position, rect.size)
	ci.draw_rect(barrel, Color(0.10, 0.13, 0.15, 0.9))
	var h: float = barrel.size.y * clampf(level, 0.0, 1.0)
	ci.draw_rect(Rect2(barrel.position + Vector2(0, barrel.size.y - h),
		Vector2(barrel.size.x, h)), FLUID)
	var ty: float = barrel.position.y + barrel.size.y * (1.0 - target)
	var th: float = barrel.size.y * tolerance
	var band := target_colour
	band.a = 0.30
	ci.draw_rect(Rect2(Vector2(barrel.position.x, ty - th),
		Vector2(barrel.size.x, th * 2.0)), band)
	ci.draw_line(Vector2(barrel.position.x - 8, ty), Vector2(barrel.end.x + 8, ty),
		target_colour, 2.5, true)
	for i in range(1, 10):
		var y: float = barrel.position.y + barrel.size.y * float(i) / 10.0
		var long: bool = i % 5 == 0
		ci.draw_line(Vector2(barrel.position.x, y),
			Vector2(barrel.position.x + (18.0 if long else 10.0), y),
			Color(0.85, 0.92, 0.94, 0.55), 1.5)
	ci.draw_rect(barrel, GLASS, false, 3.0)
	var py: float = barrel.position.y + barrel.size.y * (1.0 - clampf(level, 0.0, 1.0))
	var plunger := Rect2(Vector2(barrel.position.x - 4, py - 9),
		Vector2(barrel.size.x + 8, 12))
	ci.draw_rect(plunger, Color(0.30, 0.34, 0.38))
	ci.draw_rect(plunger, OUTLINE, false, 2.0)
	ci.draw_line(Vector2(barrel.get_center().x, py - 9),
		Vector2(barrel.get_center().x, barrel.position.y - 34), Color(0.30, 0.34, 0.38), 9.0)
	ci.draw_line(Vector2(barrel.get_center().x, barrel.end.y),
		Vector2(barrel.get_center().x, barrel.end.y + 46), Color(0.78, 0.83, 0.86), 3.0)

# ------------------------------------------------------------------ chrome
## A drape with a window cut in it — the frame every one of these is seen
## through, so the screens read as a sterile field rather than a diagram.
static func draw_drape(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.16, 0.30, 0.34, 1.0))
	var inner := rect.grow(-14.0)
	ci.draw_rect(inner, Color(0.10, 0.13, 0.16, 1.0))
	ci.draw_rect(inner, Color(0.35, 0.78, 0.72, 0.35), false, 2.0)
	var c := inner.get_center()
	for i in range(6, 0, -1):
		ci.draw_circle(c, inner.size.y * 0.20 * float(i), Color(1.0, 0.98, 0.90, 0.014))

## Vitals scribble along the bottom of the field: it moves, it means nothing,
## and its absence made every one of these screens feel like a form.
static func draw_trace(ci: CanvasItem, rect: Rect2, phase: float, colour: Color,
		agitation := 0.0) -> void:
	var pts := PackedVector2Array()
	var n := 96
	for i in range(n + 1):
		var t := float(i) / float(n)
		var beat: float = fposmod(t * 3.0 - phase, 1.0)
		var y := 0.0
		if beat < 0.06:
			y = -beat / 0.06
		elif beat < 0.13:
			y = 2.6 * ((beat - 0.06) / 0.07) - 1.0
		elif beat < 0.20:
			y = 1.6 - 2.4 * ((beat - 0.13) / 0.07)
		elif beat < 0.30:
			y = -0.8 + 0.8 * ((beat - 0.20) / 0.10)
		else:
			y = sin(beat * 26.0) * 0.06 * (1.0 + agitation * 5.0)
		pts.append(Vector2(rect.position.x + rect.size.x * t,
			rect.get_center().y - y * rect.size.y * 0.42))
	ci.draw_polyline(pts, colour, 2.0, true)
