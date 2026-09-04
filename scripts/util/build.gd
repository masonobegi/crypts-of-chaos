class_name Build
extends RefCounted
## Procedural geometry helpers. The entire hospital, every prop and every NPC is
## assembled from primitives at runtime, so the project needs no art pipeline and
## a new room or item is a few lines of data rather than a modelling session.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
## Mesh instance id -> the thinnest extent, in metres, of the thing it is. Every
## mesh in this game comes out of a factory below that knows its own dimensions,
## so recording them here is exact and free; asking the RenderingServer for an
## AABB instead is neither, and returns nothing at all under `--headless`.
## `_fit_line` is the only reader: it is how a 4cm pole gets a 4cm object's line.
static var _mesh_thin: Dictionary = {}

# ------------------------------------------------------------------ materials
static func mat(color: Color, rough := 0.85, metal := 0.0, emission := Color(0, 0, 0),
		line := 0.016) -> Material:
	var key := "%s|%.2f|%.2f|%s|%.4f" % [color.to_html(), rough, metal, emission.to_html(), line]
	if _mat_cache.has(key):
		return _mat_cache[key]
	# A PROCEDURAL SURFACE, NOT A FLAT COLOUR — on everything, not just on the
	# walls. `Surfaces` gave the architecture speckle, tooth and tile, and left
	# every prop, fixture and person in the building one perfectly uniform
	# colour; a cabinet with no variation at all standing on a speckled vinyl
	# floor reads worse than both did before, like an object pasted into a
	# photograph. This is the same soft rim the StandardMaterial carried, plus a
	# large-scale drift off the vertex stage and a fine per-pixel grain, at a
	# strength you should never be able to name.
	# UNSHARED, because the next line writes to it. `Surfaces` caches by colour
	# and finish and knows nothing about outlines, so two call sites asking for
	# the same grey with different line weights used to be handed the SAME
	# material and the second one's next_pass silently replaced the first's —
	# which is why a 4cm rail and a 40cm cabinet could never have different
	# lines. `Build` caches the finished article under a key that includes the
	# weight, so nothing is built twice.
	var m: Material = Surfaces.prop_mat(color, rough, metal, emission, 0.05, false)
	if line > 0.0:
		m.next_pass = outline(line, ink_for(color))
	# What it was made of, so `_fit_line` can ask for a thinner-lined one
	# without duplicating this material — see `_fit_line` for why duplicating a
	# ShaderMaterial is not an option.
	m.set_meta("recipe", [color, rough, metal, emission, line])
	_mat_cache[key] = m
	return m

## THE INK IS NOT BLACK.
##
## Every line in the building was the same near-black (0.09, 0.10, 0.14) —
## round the beds, round the people, round a lime-green sharps bin and round a
## pink privacy screen. One flat ink on everything is the single loudest
## "drawn by a program" signal a cel style can send, because an illustrator
## picks the line out of the colour it encloses: a red object is outlined in
## a deep red-brown, never in the same black as the grey cabinet beside it.
##
## So the line is the object's own hue, run down to a deep shade and pushed a
## third of the way toward one shared cool near-black — the shade keeps the
## drawing coherent (everything still looks inked by the same hand), the hue
## keeps it from looking stamped out.
##
## How DEEP was measured rather than argued about. A sweep that re-tinted every
## outline material in the live ward and photographed the same bed under each
## showed pure black and a per-object ink at v*0.30 to be indistinguishable —
## the line was not too pale, it was too thin AND not deep enough to separate
## from a white object. At v*0.14, with the weight below, the same frame reads
## as a drawing.
static func ink_for(color: Color) -> Color:
	var c := Color.from_hsv(color.h,
		clampf(color.s * 1.30 + 0.08, 0.0, 0.70),
		clampf(color.v * 0.14, 0.022, 0.15))
	return c.lerp(Color(0.035, 0.042, 0.065), 0.34)

## HOW HEAVY A LINE THIS OBJECT CAN CARRY.
##
## The hull grows outward in every direction, so on a thin object the line eats
## the object: a 5cm handrail with the standard weight is about a third ink by
## the time you are three metres from it, which is why the corridors were full
## of black bars and the IV poles were black sticks. The weight is a relative
## number that lands at `width * LINE_GAIN * 3` metres of growth at a typical
## three-metre read, so capping it at a fifth of the thinnest dimension keeps
## the ink off the middle of the object. It binds below about 7.5cm — which is
## most of the panels a bed, a cabinet or a chair is made of — and everything
## chunkier keeps the standard line.
##
## The fraction and `LINE_GAIN` must be chosen TOGETHER. Trimming this to 0.14
## "so the cap and the gain move together" cancelled the gain exactly on every
## thin panel in the building, which is most of what the eye reads, and took
## the whole weight increase back off the objects it was raised for.
static func line_for(size: Vector3, base := 0.016) -> float:
	var thin: float = minf(size.x, minf(size.y, size.z))
	return minf(base, maxf(thin * 0.21, 0.0015))

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
## THE LINE IS THE SAME WEIGHT WHEREVER THE OBJECT IS.
##
## `StandardMaterial3D.grow_amount` is in METRES, and the apparent thickness of
## a world-space quantity falls off as 1/distance — so a 16mm line was five
## pixels thick on a patient you were standing over, one pixel on a bed four
## metres away and nothing at all past about six. Every screenshot this project
## has taken shows it: heavy black lines on the nearest object, none whatever on
## the identical object behind it. That inconsistency is one of the strongest
## "amateur" signals a stylised game can send, because a cel line is supposed to
## be a property of the DRAWING and not of the scene.
##
## So the hull is grown in a vertex shader by an amount proportional to view
## depth, which cancels the perspective divide and leaves a constant thickness
## in pixels. Verified on gl_compatibility before it was written: custom spatial
## shaders, vertex displacement and MODELVIEW_MATRIX all work on this backend.
##
## `width` keeps its old meaning as a RELATIVE weight — the call sites that ask
## for a finer line on a small object still get one — and `LINE_GAIN` turns it
## into metres of hull growth per metre of view depth.
##
## That constant was 0.22, and raising it is the single biggest thing in this
## restyle. A sweep through the live ward — every outline material re-tinted
## and re-weighted in place, the same bed photographed under each — showed the
## ink COLOUR barely mattering and the weight mattering enormously: at 0.22 a
## white bed against a pale floor is an outlined shape you have to look for.
## Three renders at 0.33, 0.66 and the same frame at ten metres settled it;
## 0.66 is where a bed, a cabinet, a drip stand and a person all carry a line
## you can see at six metres and none of them has turned into a black bar.
const LINE_GAIN := 0.66

static func outline(width := 0.016, shade := Color(0.09, 0.10, 0.14)) -> ShaderMaterial:
	var key := "outline|%.4f|%s" % [width, shade.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var sh: Shader = _outline_shader()
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("weight", width * LINE_GAIN)
	m.set_shader_parameter("shade", shade)
	_mat_cache[key] = m
	return m

static var _outline_sh: Shader = null

static func _outline_shader() -> Shader:
	if _outline_sh != null:
		return _outline_sh
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_opaque;

uniform float weight = 0.0035;
uniform vec4 shade : source_color = vec4(0.09, 0.10, 0.14, 1.0);

void vertex() {
	// How far this vertex is from the eye, in metres.
	float dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	// Grow PROPORTIONALLY to that, so the projection's own 1/d shrink cancels
	// and the line lands at a constant width in pixels. Clamped at the near end
	// so pressing the camera into a wall does not inflate a hull over the whole
	// screen, and at the far end so a corridor's worth of distant geometry
	// stops paying for a line nobody can see.
	VERTEX += NORMAL * (weight * clamp(dist, 1.2, 26.0));
}

void fragment() {
	ALBEDO = shade.rgb;
}
"""
	_outline_sh = s
	return s

## An emissive panel that reads as a source of light rather than as a white
## rectangle: unshaded so it never takes shading, and emitting above 1.0 so the
## glow pass has something to find.
static func lit_panel(color: Color) -> StandardMaterial3D:
	var key := "panel|" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.4
	m.disable_receive_shadows = true
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
## `segments` was 8, which is 8 radial and 4 rings — a corner made of two
## facets. That is a chamfer, not a round, and at any size big enough to notice
## the rounding you could count the flats. 14 reads as a curve and still shares
## one cached mesh across every object of the same size.
## RECOMPUTE THE NORMALS FROM THE SHAPE YOU ACTUALLY BUILT.
##
## `rbox_mesh` and `taper_mesh` take a sphere, push its vertices out to the
## corners of a box, and hand the result straight to the renderer — WITH THE
## SPHERE'S NORMALS STILL ON IT. So every flat face of every object in this
## game, from a twenty-metre ceiling to a bedside cabinet, was shaded as though
## it were curved: the normal across one flat wall wandered by up to 22 degrees,
## and the wall rendered as a soft radial blob brightest somewhere near its
## middle with no light source that explained it.
##
## That is the single largest reason the picture read as a smudge. Nothing in
## the frame was a flat plane, so nothing in the frame could be crisply lit, and
## every attempt at lighting landed on geometry whose shading was already
## wandering. Found by an audit that dumped the arrays rather than trusting the
## comment above them.
##
## Area-weighted, accumulated onto SHARED vertices and then normalised, which
## gives exactly what this shape wants: a flat region's vertices are surrounded
## by coplanar triangles and come out flat, while a corner round's vertices are
## surrounded by triangles at angles to each other and come out smoothly curved.
## Sharing matters for a second reason — the cel outline is an inverted hull
## grown along these normals, and it only stays closed if the vertices it grows
## from are shared. Splitting them per-face would tear the line open at every
## corner, which is the whole reason this project builds rounded boxes.
static func _reface(arr: Array) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for i in acc.size():
		acc[i] = Vector3.ZERO
	var t := 0
	while t + 2 < idx.size():
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		# NOT normalised: the cross product's length is twice the triangle's
		# area, so leaving it alone area-weights the average for free — which
		# is what stops a fan of tiny triangles at a pole from outvoting the
		# large flat one beside it.
		var fn: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
		acc[a] += fn
		acc[b] += fn
		acc[c] += fn
		t += 3
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in out.size():
		out[i] = acc[i].normalized() if acc[i].length_squared() > 1e-12 else Vector3.UP
	arr[Mesh.ARRAY_NORMAL] = out

static func rbox_mesh(size: Vector3, radius := 0.05, segments := 14) -> ArrayMesh:
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
	# a box. Nothing in this project textures anything through UVs — the
	# procedural surfaces in `Surfaces` key off world position for exactly this
	# reason — and leaving them in is a tangent-space warning per surface.
	arr[Mesh.ARRAY_TEX_UV] = null
	arr[Mesh.ARRAY_TANGENT] = null
	_reface(arr)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = am
	_mesh_thin[am.get_instance_id()] = minf(size.x, minf(size.y, size.z))
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
## `segments` was 8, which is 8 radial and 4 rings — so every head, torso, arm
## and leg in the game was an OCTAGON, and the flat facets read at any distance
## a face is worth looking at. The rounded boxes moved to 14 for exactly this
## reason and the people, who are the thing a player looks at most, were left
## behind. 18 is round at conversational distance and costs a few hundred
## vertices on a ward of ten.
static func taper_mesh(bottom: Vector2, top: Vector2, height: float,
		radius := 0.08, segments := 18) -> ArrayMesh:
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
	_reface(arr)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = am
	_mesh_thin[am.get_instance_id()] = minf(
		minf(bottom.x, top.x), minf(minf(bottom.y, top.y), height))
	return am

## A CYLINDER WITH A ROUNDED RIM, BECAUSE A `CylinderMesh` CANNOT BE OUTLINED.
##
## Godot's cylinder has three separate normals wherever the side meets a cap, so
## growing it along them tears the inverted hull into three detached pieces —
## the side wall's tube and two floating discs — and the line breaks at every
## rim. Every pole, leg, bin, rail and roll in the building had that, which is
## roughly a third of the objects on screen.
##
## Same Minkowski trick as `rbox_mesh`, with a cylindrical core instead of a
## box one: push each sphere vertex out to a circle of `radius - rim` in XZ and
## to +/- `height/2 - rim` in Y by the sign of its own normal. The sphere's two
## hemispheres become the two rim rounds, its equator band stretches into the
## side wall, and the whole thing is one closed surface with shared vertices —
## which is what the outline pass needs and, incidentally, what makes a pole
## read as a turned metal tube rather than as a paper straw.
##
## `sides` keeps its meaning and every call site keeps its number: it is still
## the radial segment count, and the low ones (6, 8, 10) on thin objects still
## buy exactly what they bought.
static func cyl_mesh(radius: float, height: float, sides := 24) -> ArrayMesh:
	var key := "rcyl%.4f_%.4f_%d" % [radius, height, sides]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	# The rim round is a fixed small fraction of the radius, capped so a wide
	# flat disc (a stool top, a bin lid) does not become a lens.
	var rim: float = clampf(radius * 0.24, 0.004, minf(radius * 0.49, height * 0.32))
	var core_r: float = maxf(radius - rim, 0.0)
	var core_h: float = maxf(height * 0.5 - rim, 0.0)
	var src := SphereMesh.new()
	src.radius = rim
	src.height = rim * 2.0
	src.radial_segments = sides
	src.rings = maxi(3, sides / 3)
	var arr: Array = src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = norms[i]
		var radial := Vector2(n.x, n.z)
		var push := Vector3.ZERO
		if radial.length_squared() > 1e-10:
			radial = radial.normalized() * core_r
			push.x = radial.x
			push.z = radial.y
		push.y = signf(n.y) * core_h
		out[i] = verts[i] + push
	arr[Mesh.ARRAY_VERTEX] = out
	_reface(arr)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = am
	_mesh_thin[am.get_instance_id()] = minf(radius * 2.0, height)
	return am

static func sphere_mesh(radius: float) -> SphereMesh:
	var key := "sph%.3f" % radius
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	# 12x6 is a d20 with pretensions, and a patient's head is the closest object
	# to the camera in the entire game.
	s.radial_segments = 24
	s.rings = 12
	_mesh_cache[key] = s
	_mesh_thin[s.get_instance_id()] = radius * 2.0
	return s

static func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "cap%.3f_%.3f" % [radius, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0 + 0.01)
	c.radial_segments = 20
	c.rings = 8
	_mesh_cache[key] = c
	_mesh_thin[c.get_instance_id()] = radius * 2.0
	return c

# ------------------------------------------------------------------ visual bits
# ------------------------------------------------------------ contact shadow
## A SOFT DARK PATCH UNDER A THING, so it stands on the floor instead of over it.
##
## The project ships on the Compatibility renderer, which is the only one this
## machine can run and therefore the only one anything has ever been verified
## against — and Compatibility has no SSAO. So every bed, chair, table and
## person in the building was lit from two directions with nothing underneath
## them: a room of objects hovering a centimetre over a flat plane, which is
## most of what "it looks like placeholder" actually means.
##
## Still no assets. The falloff is an Image built at runtime, once, the same way
## every sound in this game is a buffer built at runtime — and it is cached, so
## the two hundred of these in a building share one texture and one material.
static var _shadow_mat: StandardMaterial3D = null

## BLACK, WITH THE FALLOFF IN ALPHA — and NOT multiplied.
##
## Two goes at this. Multiply is the correct blend for a shadow: it darkens
## whatever floor it lands on, and this building has four floor colours, so a
## grey disc is wrong on at least three of them. But the Compatibility renderer
## — which is the one this game ships on, because it is the only one that can be
## verified here — does not sample the albedo texture under BLEND_MODE_MUL. The
## texture was correct (centre 0.45, corners 1.0, mipmapped, attached to the
## material; all four confirmed by dumping it) and every shadow in the ward
## still rendered as a flat dark rectangle with four sharp corners. Worse than
## no shadow at all, and it looked like a bug in the geometry rather than in a
## sampler.
##
## So: ordinary alpha blending, black, with the falloff in the alpha channel.
## Slightly less correct over a dark floor than a multiply would be, and it
## works everywhere.
static func shadow_texture() -> ImageTexture:
	const N := 64
	## Alpha at the centre of the patch. 0.52 was set against an ambient of
	## 0.30; the room carries nearly four times that now and there is no
	## occlusion on this renderer to take it away again, so the patch has to
	## work harder or every object goes back to hovering.
	const STRENGTH := 0.62
	var img := Image.create(N, N, true, Image.FORMAT_RGBA8)
	var c := float(N - 1) * 0.5
	for y in N:
		for x in N:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / c
			# Smoothstep, so the edge dissolves instead of ending. A linear
			# falloff reads as a disc with a soft rim rather than as a shadow.
			# A FLAT CORE, then a soft edge. A pure smoothstep from the centre
			# peaks in exactly one pixel and reads as a vignette rather than as
			# a shadow — what puts an object on the floor is the darkness
			# UNDER it, which is broad; the gradient is only the last third.
			var t: float = clampf((1.0 - d) * 1.45, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(0, 0, 0, t * STRENGTH))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func shadow_material() -> StandardMaterial3D:
	if _shadow_mat != null:
		return _shadow_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = shadow_texture()
	m.albedo_color = Color(1, 1, 1, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	# Never casts, never receives, never writes depth: it is a smudge on the
	# floor and it must not fight with anything standing in it.
	m.disable_receive_shadows = true
	_shadow_mat = m
	return m

## One patch. `size` is its width and depth in metres.
static func blob_shadow(size: Vector2, y := 0.02) -> MeshInstance3D:
	var q := PlaneMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.name = "ContactShadow"
	mi.mesh = q
	mi.material_override = shadow_material()
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func mi(mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _fit_line(mesh, material)
	m.position = pos
	m.rotation = rot
	m.scale = scl
	return m

## THE LINE IS TRIMMED TO FIT THE MESH IT IS DRAWN ROUND.
##
## `line_for` covers the call sites that build their own box, but most of the
## geometry in this building is a cylinder or a bespoke shape handed straight to
## `mi()` with a default-weight material — every IV pole, table leg, handrail,
## castor and pen. Those are precisely the thin things, and the standard line on
## a 4cm pole is most of the pole: the corridors were full of black bars and the
## drip stands were black sticks with a chrome edge.
##
## So the fit happens here, where the MESH is known. The thinness comes out of
## `_mesh_thin` rather than out of `Mesh.get_aabb()`, which would query the
## RenderingServer — and returns nothing useful under the headless dummy driver
## that every test in this project runs on. A mesh nothing registered is left
## exactly as it was.
##
## Weights are snapped to 2mm so the variant cache stays small: a shared
## material per weight, not one per object.
##
## The thinner-lined material is REBUILT from the recipe the original recorded,
## never duplicated. `ShaderMaterial.duplicate()` copies the shader and loses
## every parameter that was set on it, so the copy renders with the shader's
## defaults — the first version of this function turned every steel bed leg and
## the orange visitor chair cream-white, and the only reason it was caught is
## that somebody looked at the picture.
static func _fit_line(mesh: Mesh, material: Material) -> Material:
	if not (material is ShaderMaterial):
		return material
	var thin: float = float(_mesh_thin.get(mesh.get_instance_id(), -1.0))
	if thin <= 0.0:
		return material
	# `has_meta` first, and it is not a style choice: `get_meta(key, null)`
	# raises "The object does not have any 'meta' values with the key ..." on
	# every miss, because a NIL default is indistinguishable from no default at
	# all inside the engine. Every mesh in the building comes through here, so
	# the first run of this filled two thousand lines of the test log — and the
	# quiet check, which reads what the game prints while it is being played,
	# is the only thing that caught it.
	if material.has_meta("cloth_recipe"):
		var cloth: Array = material.get_meta("cloth_recipe")
		var want_c: float = snappedf(line_for(Vector3(thin, thin, thin), cloth[1]), 0.002)
		if want_c >= float(cloth[1]) - 0.0005:
			return material
		return cloth_mat(cloth[0], want_c)
	if not material.has_meta("recipe"):
		return material
	var r: Array = material.get_meta("recipe")
	var want: float = snappedf(line_for(Vector3(thin, thin, thin), r[4]), 0.002)
	if want >= float(r[4]) - 0.0005:
		return material
	return mat(r[0], r[1], r[2], r[3], want)

## Every "box" in the game is a rounded box now. The corner radius scales with
## the object so a syringe is not rounded off as hard as a wall, and is capped so
## a big flat panel keeps a crisp face.
static func box_mi(size: Vector3, color: Color, pos := Vector3.ZERO, rough := 0.85,
		line := 0.016) -> MeshInstance3D:
	return mi(rbox_mesh(size, corner_for(size)),
		mat(color, rough, 0.0, Color(0, 0, 0), line_for(size, line)), pos)

## The same box, made of cloth. Bedding, curtains, upholstery — anything whose
## surface should have a weave in it rather than a paint finish.
static func cloth_mi(size: Vector3, color: Color, pos := Vector3.ZERO,
		line := 0.016) -> MeshInstance3D:
	return mi(rbox_mesh(size, corner_for(size)), cloth_mat(color, line_for(size, line)), pos)

## The same, as a material, for the call sites that build their own mesh — a
## tapered torso, a coat, a chair seat. `Surfaces.fabric_mat` had been written
## and called by nothing at all: the curtains, the bedding, the gowns and the
## upholstery were every one of them a flat colour on a ward that had just been
## given a speckled floor and a fissured ceiling, and the mismatch read worse
## than the flat floor had.
static func cloth_mat(color: Color, line := 0.016) -> Material:
	var key := "cloth|%s|%.4f" % [color.to_html(), line]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material = Surfaces.fabric_mat(color, 180.0, false)
	if line > 0.0:
		m.next_pass = outline(line, ink_for(color))
	m.set_meta("cloth_recipe", [color, line])
	_mat_cache[key] = m
	return m

## How hard to round something of this size. Small objects get a proportionally
## generous radius (it is what makes a prop read as moulded plastic rather than
## a cube); large ones get a fixed small chamfer so walls stay walls.
## HOW ROUNDED A BOX OF THIS SIZE SHOULD BE.
##
## The cap used to be 0.075. On anything chunky that is invisible: a 50cm
## cabinet, a bin, a monitor, a bedside locker all have a smallest dimension of
## 40-60cm, so the fraction wanted 13-20cm of corner and got seven and a half —
## a radius small enough that the eye reads the silhouette as a hard rectangle.
## Everything in the building is built from these, so everything looked like it
## was made of bricks.
##
## The FRACTION is what keeps architecture safe. A wall is 15cm thick, so it
## asks for 0.28 * 0.15 = 4cm and never reaches the cap however high the cap
## goes — walls, floors and panels stay square-edged and keep meeting each other
## cleanly. Only objects whose SMALLEST dimension is large get the bigger radius,
## and those are exactly the ones that were reading as boxes.
static func corner_for(size: Vector3) -> float:
	var smallest: float = minf(size.x, minf(size.y, size.z))
	return clampf(smallest * 0.28, 0.006, 0.16)

static func cyl_mi(radius: float, height: float, color: Color, pos := Vector3.ZERO, sides := 24) -> MeshInstance3D:
	return mi(cyl_mesh(radius, height, sides),
		mat(color, 0.85, 0.0, Color(0, 0, 0), line_for(Vector3(radius * 2.0, height, radius * 2.0))), pos)

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

## THE SAME WALL, WITH A SURFACE ON IT.
##
## `wall()` gives every square metre of the building one flat albedo colour.
## These two hand the MeshInstance a procedural material from `Surfaces`
## instead — paint tooth, a contact gradient at the skirting, vinyl speckle,
## acoustic tile — which is the difference between a room and a set of coloured
## planes. Collision, layers and the node shape are identical, so nothing that
## walks, sees or shoots a raycast through the building can tell.
static func surfaced_wall(size: Vector3, mat_override: Material, pos: Vector3,
		rot_y := 0.0) -> StaticBody3D:
	var b := wall(size, Color(1, 1, 1), pos, rot_y, 0.0)
	_repaint(b, mat_override)
	return b

static func surfaced_opaque_wall(size: Vector3, mat_override: Material, pos: Vector3,
		rot_y := 0.0) -> StaticBody3D:
	var w := surfaced_wall(size, mat_override, pos, rot_y)
	w.collision_layer = 1 | 32
	return w

static func _repaint(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = m
		_repaint(c, m)

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
	# A FIXED LABEL MUST NOT RENDER ITS OWN MIRROR.
	#
	# This was `true` for everything. A billboard always turns to face you, so
	# double-sided costs it nothing — but a sign bolted to a wall or hung from a
	# ceiling shows its BACK face to anyone behind it, and the back face of text
	# is the text backwards. Every hanging corridor sign in the building read
	# correctly walking one way and mirrored walking the other, and
	# `Dressing.ceiling_sign` had already been given a second, properly rotated
	# back label to fix exactly that — so what was actually on screen was the
	# correct back label with the front label's mirror image drawn on top of it.
	# `Hospital._build_signage` carries a comment about the same bug and sets
	# this to false by hand; it is the default's job, not every caller's.
	l.double_sided = billboard
	l.no_depth_test = false
	l.shaded = false
	# 12 was a halo half a stroke wide. At any distance the outlines of adjacent
	# glyphs merged and every sign in the building read as a dark blob with a
	# suggestion of letters in it. 5 is a keyline: it separates the text from
	# whatever is behind it without eating the text.
	l.outline_size = 5
	l.outline_modulate = Color(0.04, 0.06, 0.09, 0.85)
	return l

# ------------------------------------------------------------------ lighting
## How the one `energy` argument every call site passes is split between the
## shadow-casting cone and the shadowless fill. Kept as constants because they
## are a lighting RATIO, and the fifteen call sites should not each have an
## opinion about it.
## The spot points DOWN, so everything the old single omni used to put on the
## WALLS now has to come from the fill — which is why this is well above the
## energy the one light used to carry. Tuned against the ward: at 1.3 the upper
## walls went olive and the room read as underlit, which is a worse failure than
## the flat lighting it replaced.
const SPOT_GAIN := 4.4
const FILL_GAIN := 3.1

static func ceiling_light(pos: Vector3, energy := 1.4, color := Color(1.0, 0.97, 0.9), range_m := 9.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	# A SHADOWED SPOT, POINTING DOWN, PLUS AN UNSHADOWED FILL.
	#
	# This was one OmniLight with `shadow_enabled = false`, and the whole
	# building was lit like a diagram: no pool under any fitting, nothing
	# casting anything, every object apparently floating an inch off a floor it
	# never touched. Verified on gl_compatibility before writing this — spot and
	# omni shadows both work on this backend; the project had simply never
	# switched them on.
	#
	# A SPOT rather than an omni for the shadowed half, for two reasons: its
	# frustum points away from the ceiling, so the ceiling cannot shadow-acne
	# (an omni directly under one produced stepped black streaks across the
	# whole plane), and one shadow map is a sixth of the cost of a cube.
	#
	# And a fill beside it, because a cone has an edge and a room does not. The
	# spot alone left a hard dark band across the top of every wall where the
	# cone ran out, which is exactly what makes an interior read as a stage set.
	# The fill is unshadowed, so it costs no map at all.
	var lamp := SpotLight3D.new()
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_energy = energy * SPOT_GAIN
	lamp.light_color = color
	lamp.spot_range = range_m
	lamp.spot_angle = 82.0
	lamp.spot_angle_attenuation = 0.35
	lamp.spot_attenuation = 1.0
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.035
	lamp.shadow_normal_bias = 1.2
	lamp.shadow_opacity = 0.82
	lamp.light_specular = 0.55
	root.add_child(lamp)
	var fill := OmniLight3D.new()
	fill.light_energy = energy * FILL_GAIN
	fill.light_color = color
	fill.omni_range = range_m * 0.85
	fill.omni_attenuation = 1.6
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	root.add_child(fill)
	# A fitting, not a floating slab. A dark housing with a lit panel recessed
	# into it: the housing gives the ceiling — which is otherwise a single
	# unbroken plane across the top third of every interior shot — something to
	# be interrupted by, and the recess is what makes the panel read as a light
	# rather than as a white rectangle somebody left up there.
	var housing := mi(rbox_mesh(Vector3(1.26, 0.10, 0.48), 0.035),
		mat(Color(0.86, 0.87, 0.85), 0.5, 0.0, Color(0, 0, 0), 0.012), Vector3(0, 0.055, 0))
	root.add_child(housing)
	# THE PANEL IS BRIGHTER THAN WHITE. Glow only picks up what is over the HDR
	# threshold, and an unshaded material tops out at 1.0 — so the one object in
	# an interior that should bloom never could. Dropping the threshold under 1
	# instead was the wrong lever: it pulls the whole frame into the glow buffer
	# and SOFTLIGHT then cools and darkens everything that was merely bright.
	root.add_child(mi(rbox_mesh(Vector3(1.08, 0.05, 0.33), 0.02), lit_panel(color),
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
## SCRUBS THE SAME AGE AS THE BUILDING.
##
## These were (0.20, 0.56, 0.94) and (0.16, 0.78, 0.56) — fully saturated
## primaries in a world made of washed teal, cream and pale green, on the one
## character the player looks at most. With the rim pass on top of them she did
## not read as a nurse standing in a ward, she read as a nurse from a different
## game standing in front of one, and her sleeves went to flat slabs of colour
## with no shading left in them.
##
## Muted to something a hospital laundry has had for a while. Still the only
## blue figure in a room of pale gowns, which is all the distinctness the
## suspicion layer needs from a colour.
const SCRUB_BLUE := Color(0.29, 0.47, 0.63)
const SCRUB_GREEN := Color(0.31, 0.53, 0.46)
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
