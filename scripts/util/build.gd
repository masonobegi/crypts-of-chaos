class_name Build
extends RefCounted
## Procedural geometry helpers. The entire hospital, every prop and every NPC is
## assembled from primitives at runtime, so the project needs no art pipeline and
## a new room or item is a few lines of data rather than a modelling session.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

# ------------------------------------------------------------------ materials
static func mat(color: Color, rough := 0.85, metal := 0.0, emission := Color(0, 0, 0),
		line := 0.016) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.4f" % [color.to_html(), rough, metal, emission.to_html(), line]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	# A soft rim, tinted toward the surface's own colour. This is most of what
	# separates "a grey box" from "a stylised grey box": every object picks up a
	# light edge where it turns away from you, so silhouettes read at distance
	# and nothing dissolves into the wall behind it.
	m.rim_enabled = true
	m.rim = 0.42
	m.rim_tint = 0.55
	if emission.r + emission.g + emission.b > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.6
	if line > 0.0:
		m.next_pass = outline(line)
	_mat_cache[key] = m
	return m

## The dark line around everything.
##
## A single shared inverted-hull pass: the same mesh drawn again, grown along
## its own normals, with front faces culled so only the sliver that sticks out
## past the silhouette survives. It is the cheapest cartoon outline there is and
## it is most of the difference between "primitives" and "a style".
##
## It only works on geometry with SMOOTH normals. A BoxMesh has three separate
## normals at every corner, so growing along them tears the hull into three
## detached slabs and the outline breaks at exactly the place the eye is
## looking. That is why everything below is built from rounded boxes instead:
## the outline is the reason for the geometry, not a coat of paint over it.
static func outline(width := 0.016, shade := Color(0.09, 0.10, 0.14)) -> StandardMaterial3D:
	var key := "outline|%.4f|%s" % [width, shade.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = shade
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	m.disable_receive_shadows = true
	m.no_depth_test = false
	_mat_cache[key] = m
	return m

static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "unlit|" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m

# ------------------------------------------------------------------ meshes
## Every "box" in this game is a rounded box.
##
## This is the same call it always was and every one of the ~60 call sites is
## unchanged, but it returns rbox_mesh now. Two reasons, and the second is the
## real one: a hard-cornered box reads as programmer art at any distance, and
## the outline pass CANNOT work on one — a BoxMesh has three separate normals at
## every corner, so growing along them tears the hull into three detached slabs
## and the line breaks at exactly the corner the eye is drawn to.
##
## Nothing casts the result to BoxMesh or reads `.size` back off it, which is
## the only reason this could be done in one place instead of sixty.
static func box_mesh(size: Vector3) -> Mesh:
	return rbox_mesh(size, corner_for(size))

## A box with its edges rounded off.
##
## Built as a Minkowski sum: take a sphere of the corner radius and push each of
## its vertices out to the nearest corner of the box's inner core, by the sign of
## its own normal. Everything in one octant lands on the same corner, so the
## sphere's octants become the eight rounded corners and the rings between them
## stretch into the flat faces — one mesh, smooth normals throughout, and no
## seams for the outline pass to break on.
##
## Radius is clamped to half the smallest dimension, so a thin panel becomes a
## rounded slab rather than turning inside out.
static func rbox_mesh(size: Vector3, radius := 0.05, segments := 8) -> ArrayMesh:
	var r: float = minf(radius, minf(size.x, minf(size.y, size.z)) * 0.49)
	var key := "rbox%s_%.4f_%d" % [size, r, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var core := Vector3(
		maxf(size.x * 0.5 - r, 0.0),
		maxf(size.y * 0.5 - r, 0.0),
		maxf(size.z * 0.5 - r, 0.0))
	var src := SphereMesh.new()
	src.radius = r
	src.height = r * 2.0
	src.radial_segments = segments
	src.rings = maxi(3, segments / 2)
	var arr: Array = src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = norms[i]
		out[i] = verts[i] + Vector3(
			signf(n.x) * core.x, signf(n.y) * core.y, signf(n.z) * core.z)
	arr[Mesh.ARRAY_VERTEX] = out
	# UVs came off a sphere and are meaningless once it has been stretched into
	# a box. Nothing in this project textures anything, and leaving them in is a
	# tangent-space warning per surface.
	arr[Mesh.ARRAY_TEX_UV] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = am
	return am

## A rounded box that is a different width at the top than at the bottom.
##
## Same Minkowski trick as rbox_mesh, but the core half-extents are interpolated
## by the vertex's FINAL height rather than being constant — so one mesh gives a
## torso that is broad at the shoulders and narrow at the waist.
##
## This exists because of the outline pass. A body assembled from three stacked
## slabs gets three outlines, and every seam between them draws a hard black
## band across the chest: the first render of the restyled character was a
## person made of pillows. One shape, one line.
static func taper_mesh(bottom: Vector2, top: Vector2, height: float,
		radius := 0.08, segments := 8) -> ArrayMesh:
	var r: float = minf(radius, minf(height, minf(bottom.x, minf(bottom.y,
		minf(top.x, top.y)))) * 0.49)
	var key := "taper%s_%s_%.3f_%.4f_%d" % [bottom, top, height, r, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var core_y: float = maxf(height * 0.5 - r, 0.0)
	var src := SphereMesh.new()
	src.radius = r
	src.height = r * 2.0
	src.radial_segments = segments
	src.rings = maxi(3, segments / 2)
	var arr: Array = src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = norms[i]
		var fy: float = verts[i].y + signf(n.y) * core_y
		var t: float = clampf((fy + height * 0.5) / maxf(height, 0.0001), 0.0, 1.0)
		var hw: float = lerpf(bottom.x, top.x, t) * 0.5
		var hd: float = lerpf(bottom.y, top.y, t) * 0.5
		out[i] = Vector3(
			verts[i].x + signf(n.x) * maxf(hw - r, 0.0),
			fy,
			verts[i].z + signf(n.z) * maxf(hd - r, 0.0))
	arr[Mesh.ARRAY_VERTEX] = out
	arr[Mesh.ARRAY_TEX_UV] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Normals are still the sphere's, which on a taper leaves the side faces
	# shaded as though they were vertical. At this scale, with this lighting,
	# that reads as a soft roll rather than as an error, and recomputing them
	# would cost the smooth normals the outline pass depends on.
	_mesh_cache[key] = am
	return am

static func cyl_mesh(radius: float, height: float, sides := 12) -> CylinderMesh:
	var key := "cyl%.3f_%.3f_%d" % [radius, height, sides]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	_mesh_cache[key] = c
	return c

static func sphere_mesh(radius: float) -> SphereMesh:
	var key := "sph%.3f" % radius
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	_mesh_cache[key] = s
	return s

static func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "cap%.3f_%.3f" % [radius, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0 + 0.01)
	c.radial_segments = 10
	c.rings = 4
	_mesh_cache[key] = c
	return c

# ------------------------------------------------------------------ visual bits
static func mi(mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.rotation = rot
	m.scale = scl
	return m

## Every "box" in the game is a rounded box now. The corner radius scales with
## the object so a syringe is not rounded off as hard as a wall, and is capped so
## a big flat panel keeps a crisp face.
static func box_mi(size: Vector3, color: Color, pos := Vector3.ZERO, rough := 0.85,
		line := 0.016) -> MeshInstance3D:
	return mi(rbox_mesh(size, corner_for(size)), mat(color, rough, 0.0, Color(0, 0, 0), line), pos)

## How hard to round something of this size. Small objects get a proportionally
## generous radius (it is what makes a prop read as moulded plastic rather than
## a cube); large ones get a fixed small chamfer so walls stay walls.
static func corner_for(size: Vector3) -> float:
	var smallest: float = minf(size.x, minf(size.y, size.z))
	return clampf(smallest * 0.34, 0.006, 0.075)

static func cyl_mi(radius: float, height: float, color: Color, pos := Vector3.ZERO, sides := 12) -> MeshInstance3D:
	return mi(cyl_mesh(radius, height, sides), mat(color), pos)

# ------------------------------------------------------------------ static geo
## A solid, collidable box — walls, floors, counters, anything you bump into.
## `line` is the outline width; pass 0.0 for architecture.
##
## Floors, ceilings and wall runs are the largest surfaces on screen and they
## are the ones that gain least from an outline — a room already has an edge
## where its own walls meet. Drawing them a second time, full-screen, doubled
## the fill cost of every frame for a line nobody was going to look at.
static func wall(size: Vector3, color: Color, pos: Vector3, rot_y := 0.0,
		line := 0.016) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation.y = rot_y
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	b.add_child(box_mi(size, color, Vector3.ZERO, 0.85, line))
	return b

## Same, but flagged so NPC vision cannot see through it.
static func opaque_wall(size: Vector3, color: Color, pos: Vector3, rot_y := 0.0,
		line := 0.016) -> StaticBody3D:
	var w := wall(size, color, pos, rot_y, line)
	w.collision_layer = 1 | 32   # world | vision_blocker
	return w

# ------------------------------------------------------------------ props
## Build a physics prop from a list of visual parts and one collision box.
## parts: Array of {mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3}
static func make_prop(id: String, disp: String, collision_size: Vector3, mass: float,
		parts: Array, script_path := "res://scripts/items/prop.gd") -> Prop:
	var p: Prop = load(script_path).new()
	p.name = id
	p.item_id = id
	p.display = disp
	p.mass = mass
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collision_size
	cs.shape = shape
	p.add_child(cs)
	var root := Node3D.new()
	root.name = "Mesh"
	p.add_child(root)
	for part in parts:
		root.add_child(mi(part["mesh"], part["mat"],
			part.get("pos", Vector3.ZERO), part.get("rot", Vector3.ZERO), part.get("scl", Vector3.ONE)))
	return p

## Shorthand: a single-box prop.
static func simple_prop(id: String, disp: String, size: Vector3, color: Color, mass := 1.5) -> Prop:
	return make_prop(id, disp, size, mass, [{"mesh": box_mesh(size), "mat": mat(color)}])

# ------------------------------------------------------------------ text
## World-space label. Used for room signs, machine dials and floating name tags.
static func label3d(text: String, size := 0.12, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.no_depth_test = false
	l.shaded = false
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	return l

# ------------------------------------------------------------------ lighting
static func ceiling_light(pos: Vector3, energy := 1.4, color := Color(1.0, 0.97, 0.9), range_m := 9.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var lamp := OmniLight3D.new()
	lamp.light_energy = energy
	lamp.light_color = color
	lamp.omni_range = range_m
	lamp.shadow_enabled = false
	lamp.light_specular = 0.15
	root.add_child(lamp)
	# A fitting, not a floating slab. A dark housing with a lit panel recessed
	# into it: the housing gives the ceiling — which is otherwise a single
	# unbroken plane across the top third of every interior shot — something to
	# be interrupted by, and the recess is what makes the panel read as a light
	# rather than as a white rectangle somebody left up there.
	var housing := mi(rbox_mesh(Vector3(1.26, 0.10, 0.48), 0.035),
		mat(Color(0.86, 0.87, 0.85), 0.5, 0.0, Color(0, 0, 0), 0.012), Vector3(0, 0.055, 0))
	root.add_child(housing)
	root.add_child(mi(rbox_mesh(Vector3(1.08, 0.05, 0.33), 0.02), unshaded(color),
		Vector3(0, 0.015, 0)))
	return root

# ------------------------------------------------------------------ palette
##
## Bright and cartoon, not clinical. The old palette was correct hospital
## colours — desaturated sage, institutional grey-green, muted teal — and the
## result looked like a documentary about a hospital rather than a comedy set
## in one. Everything here is pushed up in both saturation and value: a wall is
## cream rather than off-grey, a dado is a real teal rather than a suggestion of
## one, and a warning is a proper sunny orange.
##
## The rule for adding to this: if you would describe the colour with the word
## "slightly", it is wrong. Pick the actual colour.
const FLOOR_A := Color(0.72, 0.80, 0.74)
const FLOOR_B := Color(0.66, 0.75, 0.72)
const WALL_LOWER := Color(0.22, 0.62, 0.60)
const WALL_UPPER := Color(0.87, 0.83, 0.71)
## Darker than the walls on purpose. A ceiling is the top third of every
## interior shot and it is lit from below by a lamp every five metres, so at
## anything near the wall's value it clips to flat white and the room loses its
## lid — the first pass had 0.84 here and the corners of every photograph were
## pure paper.
const CEILING := Color(0.66, 0.67, 0.66)
const TRIM := Color(0.13, 0.50, 0.54)
const BED_FRAME := Color(0.90, 0.92, 0.95)
const LINEN := Color(0.96, 0.97, 0.99)
const SCRUB_BLUE := Color(0.20, 0.56, 0.94)
const SCRUB_GREEN := Color(0.16, 0.78, 0.56)
## Not really metal any more — see the metallic values at its call sites. A
## stylised interior has no reflection probes, so anything above about 0.2
## metallic has nothing to reflect and renders as grey mud. Chrome in this game
## is painted chrome.
const METAL := Color(0.80, 0.85, 0.92)
const PLASTIC := Color(0.90, 0.92, 0.95)
const WARN := Color(1.00, 0.74, 0.14)
const BAD := Color(0.98, 0.32, 0.32)
const GOOD := Color(0.28, 0.86, 0.46)
const PAPER := Color(0.97, 0.96, 0.89)
## Two more, because a cartoon needs an accent that is not a warning.
const SUNNY := Color(1.00, 0.85, 0.32)
const GRAPE := Color(0.60, 0.44, 0.90)
