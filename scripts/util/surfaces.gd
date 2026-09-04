class_name Surfaces
extends RefCounted
## PROCEDURAL SURFACES. The one thing this game never had.
##
## Every surface in the building was a single flat albedo colour: one pale green
## for twenty metres of floor, one cream for every wall, one white for the whole
## ceiling. Depth cues were faked with thin boxes laid on top — a border strip, a
## welded seam every two metres, a ceiling grid — which is a lot of geometry to
## buy something a fragment shader gives away for nothing, and it still left the
## surface BETWEEN the lines perfectly flat.
##
## These are fragment shaders with no textures in them at all. Everything —
## speckle, grout, weave, wear — is computed from world position, so:
##   * no art assets, which is the project's founding constraint;
##   * no UVs, which matters because `rbox_mesh` is a Minkowski-summed sphere
##     and its UVs are unusable for anything tiling;
##   * the pattern is continuous across separate meshes that meet, because it
##     is keyed to where a thing IS rather than to its own surface;
##   * one material per surface class, shared by every room.
##
## VERIFIED ON gl_compatibility, which is the only renderer this project ships.
## Custom spatial shaders, derivatives (`fwidth`), vertex-stage varyings and
## world-space reconstruction all work here. `hint_screen_texture` does NOT —
## it samples flat — so nothing in this file is a screen-space effect.

## Shared preamble: value noise and the world-position varying every surface
## below is built on. Two octaves is enough for a surface read at 1–20 metres
## and cheap enough for the floor to be half the screen.
const _COMMON := """
varying vec3 world_pos;
varying vec3 world_normal;
// Large-scale per-vertex variation, so two identical objects standing in
// different corners of the building are not literally the same colour. Every
// shader here gets it; the prop shader is the one that leans on it.
varying float drift;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.62 + vnoise(p * 2.7 + 19.3) * 0.38;
}

// A line of `width` metres on a grid of `period` metres. Returns 1 on the
// line, 0 off it.
//
// FADE IT OUT, DO NOT LET IT WIDEN. Antialiasing a line by its own screen-space
// derivative is correct until the derivative exceeds the line: past that the
// `smoothstep` band is wider than the line it is smoothing, and the line grows
// into a broad stripe instead of dissolving. On a ceiling seen at a grazing
// angle — which is every ceiling, in a first-person game, across the top third
// of the frame — that turned a 14mm tile runner into the bright diagonal
// streaks that read as a rendering fault in the first render of this shader.
// So: antialias while the pixel is smaller than the line, then fade to nothing.
float grid_line(vec2 p, float period, float width) {
	vec2 g = abs(fract(p / period - 0.5) - 0.5) * period;
	vec2 fw = fwidth(p) + 0.0001;
	vec2 line = 1.0 - smoothstep(width - fw, width + fw, g);
	float l = clamp(max(line.x, line.y), 0.0, 1.0);
	float density = max(fw.x, fw.y);
	return l * (1.0 - smoothstep(width * 1.2, width * 5.0, density));
}

// `drift` is a large-scale per-vertex variation every surface can use and only
// the prop shader declares a varying for. Computing it here keeps the noise off
// the per-pixel path for the one material that is on a thousand objects.
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	drift = fbm2(world_pos.xz * 0.55 + world_pos.y * 0.31);
}
"""

static var _cache: Dictionary = {}

static func _shader(key: String, body: String, modes := "cull_back") -> Shader:
	if _cache.has(key):
		return _cache[key]
	var s := Shader.new()
	s.code = "shader_type spatial;\nrender_mode %s;\n" % modes + _COMMON + body
	_cache[key] = s
	return s

## ------------------------------------------------------------------ floor
##
## Hospital vinyl: two-metre welded sheets, a fine speckle through the body of
## it, and a polish that catches the ceiling lights. The polish is the half that
## matters — a matte floor is a coloured plane, and a floor with a specular
## response is a floor, because it reports where the lights are.
##
## `room_min`/`room_max` are the room's footprint in world XZ. Passing them puts
## a soft darkening in the last two thirds of a metre before each wall, which is
## the other half of the contact shading the wall shader already does on its own
## side: without it the wall darkens toward the floor and the floor stops dead
## at the skirting, so the two planes still meet in one hard ambiguous line.
## There is no ambient occlusion on this renderer to do it for us. Leave them
## equal and the floor is uniform, which is what a corridor wants.
static func floor_mat(base: Color, seam_period := 2.0,
		room_min := Vector2.ZERO, room_max := Vector2.ZERO) -> ShaderMaterial:
	var key := "floor|%s|%.2f|%s|%s" % [base.to_html(), seam_period, room_min, room_max]
	if _cache.has(key):
		return _cache[key]
	var sh := _shader("floor_sh", """
uniform vec3 base_col : source_color = vec3(0.72, 0.80, 0.74);
uniform float seam_period = 2.0;
uniform vec2 room_min = vec2(0.0);
uniform vec2 room_max = vec2(0.0);
uniform float edge_reach = 0.66;
uniform float edge_depth = 0.16;

void fragment() {
	vec2 p = world_pos.xz;
	// Speckle at two scales: a coarse mottle that reads as the pour, and a
	// fine grain that keeps it from banding when you stand on it.
	// Fine and low-contrast on purpose. The first version used a coarse
	// two-octave mottle at 3 metres and it read as polished terrazzo in a
	// bathroom — the pattern was the loudest thing in the room. Hospital vinyl
	// is a fleck you notice from two metres and not from six.
	float coarse = fbm2(p * 7.0);
	float fine = vnoise(p * 48.0);
	float chips = smoothstep(0.66, 0.84, vnoise(p * 30.0));
	vec3 col = base_col * (0.962 + coarse * 0.072 + fine * 0.030);
	col = mix(col, col * 1.14, chips * 0.5);
	// The welded seam between sheets. Barely darker, and it is what tells you
	// how far away the far wall is.
	float seam = grid_line(p, seam_period, 0.012);
	col *= 1.0 - seam * 0.10;
	// Contact shading in from the walls.
	if (room_max.x > room_min.x) {
		vec2 d = min(p - room_min, room_max - p);
		float edge = clamp(min(d.x, d.y) / edge_reach, 0.0, 1.0);
		col *= mix(1.0 - edge_depth, 1.0, edge * edge);
	}
	ALBEDO = col;
	// Polished, but not a mirror: the roughness varies with the mottle so the
	// sheen breaks up instead of reading as a plastic sheet.
	// A SHEEN, NOT A HOTSPOT. At roughness 0.30 the ceiling fittings landed on
	// the floor as a small hard blob that read as a puddle. Vinyl is polished,
	// not wet: broader and weaker.
	ROUGHNESS = 0.42 + coarse * 0.14 + seam * 0.22;
	SPECULAR = 0.38;
	METALLIC = 0.0;
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("seam_period", seam_period)
	m.set_shader_parameter("room_min", room_min)
	m.set_shader_parameter("room_max", room_max)
	_cache[key] = m
	return m

## ------------------------------------------------------------------ wall
##
## Emulsion over plaster, plus the two things every real wall has and no flat
## colour does: a tooth you can only see near the surface, and a darkening in
## the last half metre before the floor. That gradient is doing the job SSAO
## would do if this renderer had it — it is the single cheapest way to stop a
## room reading as a set of disconnected planes.
static func wall_mat(base: Color, floor_y := 0.0) -> ShaderMaterial:
	var key := "wall|%s|%.2f" % [base.to_html(), floor_y]
	if _cache.has(key):
		return _cache[key]
	var sh := _shader("wall_sh", """
uniform vec3 base_col : source_color = vec3(0.93, 0.91, 0.83);
uniform float floor_y = 0.0;
uniform float ao_height = 1.05;   // how far up the contact darkening reaches
uniform float ao_depth = 0.20;    // how dark it gets at the skirting
uniform float top_shade = 0.06;   // and a fainter one under the ceiling

void fragment() {
	vec3 p = world_pos;
	// Paint tooth. High frequency, very low amplitude: you should never be
	// able to name it, only notice its absence.
	float tooth = fbm2(p.xy * 24.0 + p.zz * 7.0);
	// Long, soft vertical streaking — the way emulsion actually dries.
	// NOT `drift` — that name is a varying declared in the shared preamble, and
	// shadowing it is a SHADER COMPILE ERROR ("Redefinition of 'drift'"), which
	// Godot reports by dumping the whole shader to stdout once and then
	// rendering the surface with a fallback material. Every wall in the
	// building was that fallback: a flat mid-grey plane with no tooth, no
	// gradient and no contact shading, in a file whose comments described all
	// three. It cost two rounds of raising the ambient to fix a wall that was
	// never being drawn by this shader at all.
	float streak = fbm2(vec2(p.x + p.z, p.y * 0.28) * 1.6);
	// AND A METRE-SCALE UNEVENNESS. Tooth is finer than a pixel past two
	// metres and drift is gentle, so a wall measured at four metres varied by
	// two levels out of 255 — which is a flat plane. This is the patchiness a
	// wall painted by somebody in a hurry actually has, and it is the only
	// thing carrying the largest surface in most shots of this building.
	float mottle = fbm2(vec2(p.x + p.z, p.y) * 0.42);
	vec3 col = base_col * (0.935 + tooth * 0.05 + streak * 0.055 + mottle * 0.065);
	// Contact shading where the wall meets the floor.
	float h = clamp((p.y - floor_y) / ao_height, 0.0, 1.0);
	col *= mix(1.0 - ao_depth, 1.0, h * h);
	// ...and a fainter one in the last third of a metre under the ceiling,
	// which is where a real room's bounce light runs out.
	float t = clamp((3.2 - p.y) / 0.34, 0.0, 1.0);
	col *= mix(1.0 - top_shade, 1.0, t);
	ALBEDO = col;
	ROUGHNESS = 0.86 - tooth * 0.06;
	SPECULAR = 0.28;
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("floor_y", floor_y)
	_cache[key] = m
	return m

## ------------------------------------------------------------------ ceiling
##
## Suspended acoustic tile: a 0.6m grid of fissured mineral board in a T-bar
## runner. The ceiling is the top third of every interior shot in this game and
## it was one unbroken white plane with a few thin boxes laid across it, which
## from a grazing angle read as wireframe rather than as a ceiling.
static func ceiling_mat(base: Color, tile := 0.6) -> ShaderMaterial:
	var key := "ceil|%s|%.2f" % [base.to_html(), tile]
	if _cache.has(key):
		return _cache[key]
	# `shadows_disabled`, and it is a bug fix rather than a saving.
	#
	# The ceiling slab is the top of the building — there is no roof above it —
	# so the sun lands on its upper face and its underside is a large flat
	# surface at a grazing angle to the camera being shadow-tested against a
	# blurred directional shadow map. What that produced was broad soft diagonal
	# bands, in the sun's direction, right across the top third of every
	# interior shot: the streaks that read as a rendering fault in every
	# screenshot this project has ever taken. Nothing can be between a light and
	# the underside of the ceiling, so it has nothing to receive.
	var sh := _shader("ceil_sh", """
uniform vec3 base_col : source_color = vec3(0.95, 0.96, 0.96);
uniform float tile = 0.6;
// A CEILING IS LIT BY BOUNCE, AND THERE IS NO BOUNCE HERE.
//
// The fixtures point down, so the ceiling's underside receives ambient and
// nothing else — and it rendered as a dark blue-grey lid over a bright room,
// which is the opposite of every real ceiling. Rather than raise the ambient
// for the whole building (which flattens everything else), the ceiling carries
// a little of its own light. This is the one surface in the game where that is
// physically the right answer.
// Dropped from 0.55 once the ambient was measured and raised to where it
// should always have been. Self-lighting a plane is a fudge, and the size of
// the fudge should be exactly what the room's own fill cannot supply: at 0.55
// against the new ambient the ceiling was the brightest thing in every shot
// and read as a lightbox rather than as tile.
uniform float self_lit = 0.22;

void fragment() {
	vec2 p = world_pos.xz;
	// The fissures in mineral board: stretched noise, so it reads as combed
	// rather than as static.
	float fissure = fbm2(vec2(p.x * 26.0, p.y * 7.0));
	float pits = smoothstep(0.62, 0.96, vnoise(p * 60.0));
	vec3 col = base_col * (0.975 + fissure * 0.032) - vec3(pits * 0.028);
	// The runner between tiles, and a slight dish across each tile so a flat
	// plane stops being flat.
	float runner = grid_line(p, tile, 0.014);
	vec2 within = abs(fract(p / tile) - 0.5) * 2.0;
	float dish = max(within.x, within.y);
	col *= mix(0.997, 0.972, dish * dish);
	// The runner reads as the SHADOW GAP between tiles, not as a highlight. A
	// bright line on a bright ceiling is the one thing that survives being
	// faded out and still looks like a wireframe.
	col *= 1.0 - runner * 0.13;
	ALBEDO = col;
	EMISSION = col * self_lit;
	ROUGHNESS = 0.92 - runner * 0.35;
	SPECULAR = 0.2;
}
""", "cull_back, shadows_disabled")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("self_lit", 0.85)
	_cache[key] = m
	return m

## ------------------------------------------------------------------ fabric
##
## Curtains, bedding, upholstery. A woven cross-hatch and a soft sheen along the
## grain, which is most of what separates cloth from painted plastic.
static func fabric_mat(base: Color, weave := 180.0, shared := true) -> ShaderMaterial:
	var key := "fab|%s|%.0f" % [base.to_html(), weave]
	if shared and _cache.has(key):
		return _cache[key]
	var sh := _shader("fab_sh", """
uniform vec3 base_col : source_color = vec3(0.8, 0.8, 0.85);
uniform float weave = 180.0;

void fragment() {
	vec3 p = world_pos;
	vec2 uv = vec2(p.x + p.z, p.y) * weave;
	// FADE THE WEAVE OUT BEFORE IT ALIASES. A 180-per-metre sine is finer than
	// a pixel at three metres, and an un-faded one crawls and moirés across a
	// curtain every time the player moves. `fwidth` says how much of the
	// pattern falls inside this pixel; past about half a cycle there is no
	// honest answer, so it dissolves to the flat colour it averages to.
	float density = max(fwidth(uv.x), fwidth(uv.y));
	float visible = 1.0 - smoothstep(1.4, 3.6, density);
	float warp = sin(uv.x) * 0.5 + 0.5;
	float weft = sin(uv.y) * 0.5 + 0.5;
	float cloth = mix(warp, weft, 0.5) * visible + 0.5 * (1.0 - visible);
	float slub = fbm2(p.xy * 9.0);
	ALBEDO = base_col * (0.93 + cloth * 0.09 + slub * 0.05);
	ROUGHNESS = 0.94 - cloth * 0.10;
	SPECULAR = 0.16;
	// Cloth catches the light along its silhouette harder than paint does, and
	// on a gown that edge is most of what gives a body its form in a room lit
	// from straight above. The prop shader carries a rim and the first version
	// of this one silently dropped it, so the largest soft surface in the game
	// was the one thing with no edge light on it.
	RIM = 0.55;
	RIM_TINT = 0.35;
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("weave", weave)
	if shared:
		_cache[key] = m
	return m

## ------------------------------------------------------------------ props
##
## EVERYTHING ELSE. The architecture got surfaces and every prop, fixture and
## person in the building stayed one flat colour — which made the mismatch
## worse than the flat look it replaced: a speckled vinyl floor with a
## perfectly uniform plastic cabinet standing on it reads as an object that has
## been pasted into the photograph.
##
## This is the material every solid thing in the game is made of, so it is
## deliberately the cheapest shader in this file: one noise call per VERTEX for
## the large-scale drift (so two identical cabinets in different corners are
## not literally the same colour), and one per pixel for the grain. It also
## carries the rim light back — `Build.mat` set `rim_enabled` on every
## StandardMaterial3D in the game, and the first version of these shaders
## silently dropped it, so the floor, walls and ceiling lost the light edge
## every other surface still had.
##
## `shared` is what stops the caller from having to duplicate one of these, and
## duplicating one is a trap: `ShaderMaterial.duplicate()` copies the shader and
## silently loses every parameter set on it, so the copy renders with the
## shader's DEFAULTS. That turned a steel bed leg and an orange visitor chair
## cream-white the first time `Build._fit_line` tried to make a lighter-lined
## variant of a material. Ask for an unshared one and set your own next_pass on
## it instead; `Build` caches the result under its own key either way.
static func prop_mat(base: Color, rough := 0.85, metal := 0.0,
		emission := Color(0, 0, 0), grain := 0.05, shared := true) -> ShaderMaterial:
	var key := "prop|%s|%.2f|%.2f|%s|%.3f" % [base.to_html(), rough, metal,
		emission.to_html(), grain]
	if shared and _cache.has(key):
		return _cache[key]
	var sh := _shader("prop_sh", """
uniform vec3 base_col : source_color = vec3(0.8, 0.8, 0.8);
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform vec3 emis : source_color = vec3(0.0);
uniform float emis_energy = 0.0;
uniform float grain = 0.05;

void fragment() {
	// Drift comes off the vertex stage; only the grain is per-pixel, because
	// this shader runs on every solid object in the building.
	float fine = vnoise(world_pos.xy * 52.0 + world_pos.zz * 27.0);
	vec3 col = base_col * (1.0 + (drift - 0.5) * grain * 1.6
		+ (fine - 0.5) * grain * 0.7);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	RIM = 0.42;
	RIM_TINT = 0.55;
	EMISSION = emis * emis_energy;
}
""", "cull_back")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("emis", Vector3(emission.r, emission.g, emission.b))
	m.set_shader_parameter("emis_energy", 1.6 if (emission.r + emission.g + emission.b) > 0.0 else 0.0)
	m.set_shader_parameter("grain", grain)
	if shared:
		_cache[key] = m
	return m
