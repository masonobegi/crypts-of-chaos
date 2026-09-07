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

// A DETAIL FINER THAN A PIXEL IS NOT DETAIL, IT IS NOISE.
//
// `q` is the pattern coordinate AFTER scaling, so one unit of q is one cycle
// and `fwidth(q)` is literally cycles per pixel. Returns 1 while a cycle is
// comfortably wider than a pixel and 0 once it is not.
//
// This is the same argument `grid_line` makes about lines, and until now it was
// the only place in this file making it. Every other surface sampled noise at
// 24 to 60 cycles per metre with no guard at all — and the broad soft diagonal
// bands across the ceiling of every interior shot this project has taken were
// not the sun and were not the tile grid, which are the two things they were
// blamed on: they were 60-per-metre mineral-board pitting beating against the
// pixel grid at a grazing angle. Measured: the ceiling of the wide shot varied
// by up to 24 levels along those bands, on a term whose own amplitude is 7.
//
// A SYMMETRIC term fades to its mean (0.5 for vnoise and fbm2) so the surface
// does not change brightness with distance. A MASK fades to zero, which costs
// under two per cent of albedo at the far wall and reads as aerial perspective.
float detail_fade(vec2 q) {
	float cycles_per_pixel = max(fwidth(q.x), fwidth(q.y));
	return 1.0 - smoothstep(0.30, 0.85, cycles_per_pixel);
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
	// THE ANTIALIAS BAND NEVER EXCEEDS THE LINE'S OWN WIDTH. Feeding a raw
	// `fw` into the smoothstep is correct only while the pixel is smaller than
	// the line; past that the band is wider than the thing it is smoothing and
	// the line grows into a stripe. Capping it means the mark can only ever
	// soften, never spread.
	vec2 aa = min(fw, vec2(width));
	vec2 line = 1.0 - smoothstep(width - aa, width + aa, g);
	float l = clamp(max(line.x, line.y), 0.0, 1.0);
	float density = max(fw.x, fw.y);
	// ...AND IT IS GONE BY THE TIME A PIXEL SPANS THE LINE, not five times it.
	//
	// This is the second go at the ceiling streaks and it is the one that
	// worked. The first (fade instead of widen) took the worst of it out and
	// left broad soft diagonals across the top third of every interior shot,
	// which were then blamed on the sun's shadow map and on the tile grid
	// being "too strong". They were neither: rendering the ward with each term
	// of the ceiling shader switched off in turn put the horizontal standard
	// deviation across the ceiling at 9.33 with the runner on and 5.92 with it
	// off, and every diagonal vanished with it. They were MOIRÉ — a 14mm mark
	// on a 600mm grid, sampled by a pixel covering 20 to 70mm, beating against
	// its own period at whatever angle the two frequencies happened to make.
	//
	// A mark thinner than a pixel has no honest answer, so it fades to the
	// average it would integrate to (`2*width/period` of the surface) rather
	// than to nothing, and the far ceiling keeps the faint overall tone the
	// grid gives it instead of getting brighter as it recedes.
	float resolved = 1.0 - smoothstep(width * 0.8, width * 2.5, density);
	float mean_cover = clamp(2.0 * width / period, 0.0, 1.0);
	return mix(mean_cover, l, resolved);
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

## HOW MUCH EDGE LIGHT A SURFACE CATCHES, AND IT IS ZERO.
##
## Godot's `RIM` is added PER LIGHT and scaled by that light's energy and
## attenuation. A ward has a ceiling fitting every five metres, the spot on
## each carries `Build.SPOT_GAIN` (4.4) and the fill `FILL_GAIN` (3.1), and
## four of them reach any given square metre — so the rim term arrives four
## times over at roughly three units of energy each. Nothing survives that.
##
## Measured on the real frames rather than argued about. The figure box in
## `20_struck_off` is 28.8% pure 255 at the old 0.55, and 0.3% at zero; the
## sweep between them is a cliff, not a slope (0.22 -> 26.8%, 0.10 -> 17.5%,
## 0.05 -> 1.7%), because the term saturates the moment several lights agree.
## Side by side, the difference is not subtle and it is not confined to
## characters: with the rim on, Adeyemi's blue scrubs are a white blob, the
## nurses' station counter is a white slab, the notice board is a blank yellow
## rectangle and every bed in the ward is a featureless white shape. With it
## off, all of them have form.
##
## The comment this replaces said the rim was "most of what gives a body its
## form in a room lit from straight above". It was true when it was written and
## the lights were dimmer; after `ceiling_light` was split into a shadowed spot
## plus a fill and the gains went up, the term stopped supplementing the
## shading and started erasing it. Same shape as the ceiling's `self_lit` and
## the fabric's weave pitch: a number tuned against a world that has since
## moved, still doing exactly what it was told.
##
## Kept as a constant at zero rather than deleted, because the next person to
## reach for an edge light needs the measurements more than they need a clean
## file. If it is ever turned back on, the lights are what has to give first.
const RIM_EDGE := 0.0

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
	float fine = mix(0.5, vnoise(p * 48.0), detail_fade(p * 48.0));
	float chips = smoothstep(0.66, 0.84, vnoise(p * 30.0)) * detail_fade(p * 30.0);
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
	// The x2.7 is fbm2's second octave: the fade has to be aimed at the
	// FINEST thing in the term, not at the coordinate it was handed.
	vec2 tooth_q = p.xy * 24.0 + p.zz * 7.0;
	float tooth = mix(0.5, fbm2(tooth_q), detail_fade(tooth_q * 2.7));
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
## How much light the ceiling carries of its own, because the fixtures point
## down and gl_compatibility has no bounce. ONE place, read by the material and
## quoted in the shader's own default, so the two cannot say different things
## again. Chosen by rendering the ward at three values and reading the ceiling
## off the frame — see the note in `ceiling_mat`.
const CEIL_SELF_LIT := 0.30

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
// THE NUMBER IS `CEIL_SELF_LIT` AND IT IS SET FROM GDSCRIPT. This default is
// only what the shader falls back to if nobody sets it; the paragraph above
// used to describe 0.22 while the material handed it 0.85, which is CLAUDE.md
// 48 exactly — a value in two places, the comment describing one of them, and
// the picture siding with the other. Measured off a 1600x900 render of the
// ward: the ceiling came back at L=215 against an upper wall at 200 and a
// floor at 150, so the largest surface in the top third of every frame was
// the brightest thing in the room. A ceiling under downlighters is the
// DARKEST of the three.
uniform float self_lit = 0.30;

void fragment() {
	vec2 p = world_pos.xz;
	// The fissures in mineral board: stretched noise, so it reads as combed
	// rather than as static.
	vec2 fissure_q = vec2(p.x * 26.0, p.y * 7.0);
	float fissure = mix(0.5, fbm2(fissure_q), detail_fade(fissure_q * 2.7));
	float pits = smoothstep(0.62, 0.96, vnoise(p * 60.0)) * detail_fade(p * 60.0);
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
	m.set_shader_parameter("self_lit", CEIL_SELF_LIT)
	_cache[key] = m
	return m

## ------------------------------------------------------------------ fabric
##
## Curtains, bedding, upholstery. A woven cross-hatch and a soft sheen along the
## grain, which is most of what separates cloth from painted plastic.
## Threads per metre, in ONE place. It was a default here and a hard-coded 180
## at the only call site, so raising the default reached nothing and the
## comments below went on describing a pitch that no object in the game had —
## which is the same class of fault as a constant nothing reads, only quieter,
## because the code and the comment disagree and the picture sides with the
## code.
##
## 180 and not the 300 that was briefly written here. Rendered both: at 300 the
## weave dissolves almost completely by half a metre, so a gown at the distance
## you actually read one is flat pink. The pitch was never the problem — the
## gingham came from two sines of the SAME pitch averaged into a square
## lattice, and what fixed it was perturbing the phase, running warp and weft
## at pitches that do not divide into each other, multiplying rather than
## averaging, and halving the amplitude.
const WEAVE := 180.0

static func fabric_mat(base: Color, weave := WEAVE, shared := true) -> ShaderMaterial:
	var key := "fab|%s|%.0f" % [base.to_html(), weave]
	if shared and _cache.has(key):
		return _cache[key]
	var sh := _shader("fab_sh", """
uniform vec3 base_col : source_color = vec3(0.8, 0.8, 0.85);
uniform float rim_edge = 0.0;
uniform float weave = 180.0;   // see WEAVE above; this is only the fallback

void fragment() {
	vec3 p = world_pos;
	vec2 uv = vec2(p.x + p.z, p.y) * weave;
	// NOT A CHECK. Two sines of the SAME pitch averaged together is a square
	// lattice, and a square lattice on a hospital gown is gingham — which is
	// what the first version of this put on the closest object in the game.
	// Three changes, and they only work together: the pitch is finer, the two
	// threads run at pitches that do not divide into each other, and the phase
	// is dragged about by the same noise that carries the slub. What is left
	// is irregular at every scale, which is what cloth is.
	float slub = fbm2(p.xy * 9.0);
	uv += (slub - 0.5) * 1.7;
	// FADE IT OUT BEFORE IT ALIASES. A 180-per-metre sine is finer than a
	// pixel at about three metres, and an un-faded one crawls and moirés
	// across a curtain every time the player moves. `fwidth` says how much of
	// the pattern falls inside this pixel; past about half a cycle there is no
	// honest answer, so it dissolves to the flat colour it averages to — which
	// is also true of real cloth, which has no visible weave across a room.
	float density = max(fwidth(uv.x), fwidth(uv.y));
	float visible = 1.0 - smoothstep(1.0, 2.6, density);
	float warp = sin(uv.x) * 0.5 + 0.5;
	float weft = sin(uv.y * 1.27 + 2.1) * 0.5 + 0.5;
	// MULTIPLIED, because threads cross: you see the crossing point where both
	// are at the top of their cycle, and the gap everywhere else.
	float cloth = mix(0.5, warp * weft, visible);
	// And much less of it. The weave was nine per cent of the albedo, which is
	// a pattern you can name from two metres; cloth is a texture you notice
	// the absence of, so the irregular half now carries as much as the regular
	// half does.
	ALBEDO = base_col * (0.955 + cloth * 0.055 + (slub - 0.5) * 0.055);
	ROUGHNESS = 0.94 - cloth * 0.08;
	SPECULAR = 0.16;
	// See `RIM_EDGE`. Set from GDScript, and this default only applies if
	// nobody sets it.
	RIM = rim_edge;
	RIM_TINT = 0.35;
}
""")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("weave", weave)
	m.set_shader_parameter("rim_edge", RIM_EDGE)
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
uniform float rim_edge = 0.0;
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform vec3 emis : source_color = vec3(0.0);
uniform float emis_energy = 0.0;
uniform float grain = 0.05;

void fragment() {
	// Drift comes off the vertex stage; only the grain is per-pixel, because
	// this shader runs on every solid object in the building.
	vec2 fine_q = world_pos.xy * 52.0 + world_pos.zz * 27.0;
	float fine = mix(0.5, vnoise(fine_q), detail_fade(fine_q));
	vec3 col = base_col * (1.0 + (drift - 0.5) * grain * 1.6
		+ (fine - 0.5) * grain * 0.7);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	RIM = rim_edge;
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
	m.set_shader_parameter("rim_edge", RIM_EDGE)
	if shared:
		_cache[key] = m
	return m
