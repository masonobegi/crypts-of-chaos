class_name Build
extends RefCounted
## Procedural geometry helpers. The entire hospital, every prop and every NPC is
## assembled from primitives at runtime, so the project needs no art pipeline and
## a new room or item is a few lines of data rather than a modelling session.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

# ------------------------------------------------------------------ materials
static func mat(color: Color, rough := 0.85, metal := 0.0, emission := Color(0, 0, 0)) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s" % [color.to_html(), rough, metal, emission.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission.r + emission.g + emission.b > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.6
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
static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b := BoxMesh.new()
	b.size = size
	_mesh_cache[key] = b
	return b

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

static func box_mi(size: Vector3, color: Color, pos := Vector3.ZERO, rough := 0.85) -> MeshInstance3D:
	return mi(box_mesh(size), mat(color, rough), pos)

static func cyl_mi(radius: float, height: float, color: Color, pos := Vector3.ZERO, sides := 12) -> MeshInstance3D:
	return mi(cyl_mesh(radius, height, sides), mat(color), pos)

# ------------------------------------------------------------------ static geo
## A solid, collidable box — walls, floors, counters, anything you bump into.
static func wall(size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
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
	b.add_child(box_mi(size, color))
	return b

## Same, but flagged so NPC vision cannot see through it.
static func opaque_wall(size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var w := wall(size, color, pos, rot_y)
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
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.75)
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
	root.add_child(lamp)
	root.add_child(mi(box_mesh(Vector3(1.1, 0.06, 0.35)), unshaded(color), Vector3(0, 0.06, 0)))
	return root

# ------------------------------------------------------------------ palette
const FLOOR_A := Color(0.72, 0.74, 0.70)
const FLOOR_B := Color(0.64, 0.67, 0.64)
const WALL_LOWER := Color(0.42, 0.55, 0.55)
const WALL_UPPER := Color(0.86, 0.87, 0.83)
const CEILING := Color(0.90, 0.90, 0.88)
const TRIM := Color(0.30, 0.38, 0.40)
const BED_FRAME := Color(0.80, 0.82, 0.84)
const LINEN := Color(0.93, 0.95, 0.96)
const SCRUB_BLUE := Color(0.24, 0.45, 0.62)
const SCRUB_GREEN := Color(0.28, 0.55, 0.45)
const METAL := Color(0.70, 0.72, 0.76)
const PLASTIC := Color(0.85, 0.86, 0.88)
const WARN := Color(0.90, 0.62, 0.20)
const BAD := Color(0.80, 0.28, 0.26)
const GOOD := Color(0.35, 0.72, 0.45)
const PAPER := Color(0.95, 0.94, 0.88)
