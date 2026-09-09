class_name Grade
extends RefCounted
## THE LOOK, IN ONE PLACE.
##
## Everything below was chosen by a measured sweep: six settings of ambient,
## exposure, white point, saturation and contrast applied to the live ward in
## one boot and photographed from the same two vantages, then scored on mean
## saturation, luminance spread and how much of the frame clipped. The long
## account of why each number is what it is lives beside it, below.
##
## IT IS HERE BECAUSE IT WAS IN TWO PLACES AND THEY DISAGREED. `Game` had the
## swept values; `MenuScene` had an older set with a blue ambient at a
## different exposure — so the title screen, whose whole reason for existing is
## that the first frame of the game should look like the game, was graded like
## a different game. Two copies of a tuned number is CLAUDE.md 48, and a look
## is the one thing where the divergence is guaranteed to be visible.
##
## `sky` is the one thing the two callers genuinely differ on: the ward has a
## procedural sky it sees through the windows, and the title vignette is one
## room with no outside, so it takes a flat colour instead.

## Warm-neutral, NOT sky-blue. Ambient is the only bounce light this renderer
## has, so it is what every vertical surface is actually lit by — and a blue
## ambient on cream walls is why the ward went slate the moment the normals
## were corrected. Measured: a cream wall reads (113, 124, 129) at 0.62 and
## (195, 197, 194) at 3.0, so the knob works and 0.30 was an order out. 3.0
## flattens the building into a white-out.
const AMBIENT := Color(0.88, 0.87, 0.84)
const AMBIENT_ENERGY := 1.15

## AND THE SAME TWO NUMBERS AT THE END OF THE DAY.
##
## THE EVENING NEVER ARRIVED, AND THE FLOOR WAS BIT-IDENTICAL.
##
## `Game.apply_shift_look` moved the sun, the sky and the fittings every minute
## of the shift and never touched the ambient — and ambient is the only bounce
## light this renderer has, so it is what every surface not directly under a
## fitting is actually lit by. Worse, the two things that DID move cancelled:
## the sun came down 1.05 -> 0.22 while the lamps went UP 0.62 -> 0.78.
##
## `09_ward_evening` is the frame that finally measured it — the same camera as
## `02_ward_from_door`, the same ward, the same seed, twelve hours later. With
## the shipped constant ambient, at 19:25 against 08:00:
##   upper cream wall  208.2 -> 191.5   (-16.7)
##   ceiling           198.3 -> 157.2   (-41.1)
##   floor             153.6 -> 153.6   (0.0)
## The floor number is not a rounding: over a 900x250 box, 225,000 pixels, the
## worst channel difference between morning and evening was ZERO. The largest
## surface in the frame of a game whose whole pressure is a clock running
## towards eight was the same picture at both ends of the day.
##
## The sweep, all at 19:25 on that frame, wall / floor / ceiling:
##   1.15 (0.88,0.87,0.84) — 191.5  153.6  157.2   the shipped build
##   0.72 (0.74,0.75,0.83) — 149.1  109.4  118.0   <- this
##   0.62 (0.68,0.72,0.84) — 136.9   97.6  107.9
##   0.46 (0.62,0.68,0.86) — 118.7   80.2   93.6
## Close to linear across that range and nowhere near the cliff gotcha 40 warns
## about — that reading (a cream wall at 113 with ambient 0.62) predates the
## fittings being split into a shadowed spot at SPOT_GAIN 4.4 plus a fill at
## 3.1, and with eleven of those in the building the ambient's share of a lit
## surface is much smaller than it was. 0.46 is a genuinely dusk ward and is
## the most attractive of the four; it is not the one shipped, because this is
## a game about reading five faces and five charts at four metres and the last
## two hours of every shift are when the player is under the most pressure to
## do it. 0.72 is the point where the room has plainly changed and nothing has
## become harder to see.
##
## COLOUR AS WELL AS ENERGY, and it is doing at least half the work. The lamps
## warm (1.00,0.97,0.90 -> 1.00,0.88,0.70) as the ambient goes cool, so the
## evening is a two-colour room rather than a dimmer one: warm under the
## fittings, cool everywhere they do not reach. Dimming alone reads as a
## brightness fault; the split reads as dusk. The blue is deliberately mild —
## at (0.62,0.68,0.86) the ward's green vinyl floor turns teal and the room
## stops being this game's palette, which is the same complaint the AMBIENT
## constant above records from the last time somebody put blue in it.
const AMBIENT_LATE := Color(0.74, 0.75, 0.83)
const AMBIENT_ENERGY_LATE := 0.72

## FILMIC, not LINEAR: linear keeps colour pure to 1.0 and then clips flat, and
## this scene has an ambient term, a key, a fill and a lamp every five metres
## landing on the same white wall. A lower exposure against a HIGHER white
## point is what buys colour back — the white point is where the curve
## saturates, so pushing it out keeps the midtones off the shoulder.
const EXPOSURE := 0.70
const WHITE := 3.2
## One global knob for "more cartoon". This pairing carries the most colour
## (0.161 against 0.132) and the most contrast (sd 44.7 against 41.9) of the
## six that were scored, for no extra clipping.
const SATURATION := 1.35
const CONTRAST := 1.16
## ABOVE ONE, so only lit panels and signage get in. At 0.92 half the frame
## entered the glow buffer and SOFTLIGHT cooled and darkened every wall in the
## building. `Build.lit_panel` emits at 2.4.
const GLOW_THRESHOLD := 1.05

## The ambient at a given point in the shift, as [Color, float].
##
## ONE definition, called from both places, because a look that lives in two
## files diverges (gotcha 55) and a number that is a default in one place and a
## literal in another never moves at all (gotcha 48). `Grade.apply` calls it at
## warmth 0.0 so a scene with no clock — the title vignette — gets the morning;
## `Game.apply_shift_look` calls it every minute with the same `warmth` the sun
## and the fittings are driven from, so all three move together or none do.
static func ambient_for(warmth: float) -> Array:
	var w := clampf(warmth, 0.0, 1.0)
	return [AMBIENT.lerp(AMBIENT_LATE, w), lerpf(AMBIENT_ENERGY, AMBIENT_ENERGY_LATE, w)]

## THE ONE THING IN THIS FILE THAT IS NOT AN ENVIRONMENT SETTING.
##
## Every frame this project has ever rendered has its brightest values running
## straight off the edge of the image — the ceiling in the top corners of 02,
## 05, 06 and 08 reads 196-202 all the way to the border — so nothing pulls the
## eye toward the middle and the result reads as an engine viewport rather than
## as a shot. A vignette is the cheapest thing that separates the two, it costs
## one full-screen alpha blend, and `canvas_item` shaders run on
## gl_compatibility without complaint.
##
## It lives HERE, and both `Game` and `MenuScene` build it from this function,
## for the reason the rest of the file exists: the title screen is the first
## frame anybody sees and it has to be the same picture as the ward behind it
## (gotcha 55).
##
## LAYER 5, which is under `UIRoot`'s 10. A vignette over the HUD dims the
## clock, the money and the patient card — the two things `screenshots.sh`
## measures are about that card, so getting the order wrong would be both
## visible and measured.
##
## `length(UV - 0.5)` rather than an aspect-corrected radius, deliberately: in
## UV space the falloff is an ellipse fitted to the frame, so an ultrawide gets
## the same darkening at the middle of its left edge as a 16:9 does, which is
## the behaviour wanted. Correcting by aspect would put the ultrawide's sides
## back into the bright band and defeat the point.
const VIGNETTE := 0.18

static func vignette_layer() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = "Vignette"
	cl.layer = 5
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.18;

void fragment() {
	// 0.71 at the middle of an edge, 1.00 in a corner: almost all of the
	// darkening is in the corners, and the middle third of the frame is
	// untouched.
	float r = length(UV - vec2(0.5)) * 1.42;
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.55, 1.05, r) * strength);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("strength", VIGNETTE)
	var r := ColorRect.new()
	r.material = m
	r.color = Color(1, 1, 1, 1)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not the default STOP. A full-rect Control over the whole screen
	# with the default mouse filter eats every click in the game, and this one
	# sits under the HUD where nothing would ever say so.
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(r)
	return cl

## Apply the grade to an Environment. Leaves `background_mode`, the sky and
## anything renderer-specific to the caller.
static func apply(env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Through `ambient_for` even at warmth zero, so there is exactly one
	# expression of "what the ambient is" and the morning is the same statement
	# as the evening rather than a separate one that happens to agree.
	var amb := ambient_for(0.0)
	env.ambient_light_color = amb[0]
	env.ambient_light_energy = amb[1]
	# Says out loud what the ambient source already implies. Measured to be a
	# no-op on this backend with AMBIENT_SOURCE_COLOR — the default of 1.0
	# renders identically, pixel for pixel — so it is a statement of intent.
	env.ambient_light_sky_contribution = 0.0
	# No fog. Distance haze is what makes a corridor look grim, and this one is
	# sixty-two metres long.
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = EXPOSURE
	env.tonemap_white = WHITE
	env.adjustment_enabled = true
	env.adjustment_saturation = SATURATION
	env.adjustment_contrast = CONTRAST
	# THE ONE KNOB A PLAYER LOOKS FOR AND COULD NOT FIND. This game is dark HUD
	# type over a bright ward and it ships with no brightness control at all,
	# which on a laptop screen in a lit room is a refund. It lives HERE rather
	# than in a `_apply` branch of its own, because `Grade` is the single
	# definition of the look and two copies of a tuned number is gotcha 55 — the
	# title screen and the ward have to agree, and they only do if there is one
	# place that says so.
	env.adjustment_brightness = float(Settings.get_value("brightness"))
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = GLOW_THRESHOLD
