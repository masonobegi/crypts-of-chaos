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

## Apply the grade to an Environment. Leaves `background_mode`, the sky and
## anything renderer-specific to the caller.
static func apply(env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
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
	env.adjustment_brightness = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = GLOW_THRESHOLD
