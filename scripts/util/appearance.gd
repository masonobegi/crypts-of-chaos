class_name Appearance
## WHAT SOMEBODY LOOKS LIKE, decided once from who they are.
##
## Every patient in the game used to be the same person. `PatientSystem._spawn`
## passed `p.skin_tone`, `p.shirt_color` and a hardcoded brown, and those two
## fields on `Patient` were never assigned from anything — so all forty authored
## people were one body: same skin, same gown, same brown hair, same height,
## rendered five at a time in a row. On a game whose entire premise is that
## these five are individuals you make decisions about, the ward read as a
## warehouse of one mannequin.
##
## Derived rather than authored, for the reason everything else in this game is
## data: adding a patient should not mean picking six colours, and forty hand
## chosen palettes is forty chances to pick two that are nearly the same. The
## hash is over the id, so it is stable across saves, wards and machines, and
## adding somebody new cannot change anybody who already exists.
##
## `age` — which was in every record and read by nothing — decides how grey
## somebody is, which is the one property that should NOT be arbitrary.

## Real ranges, dark to light, deliberately not evenly spaced: the middle of
## this range is where most people are.
const SKIN := [
	Color(0.29, 0.20, 0.15), Color(0.36, 0.25, 0.18), Color(0.44, 0.31, 0.22),
	Color(0.52, 0.38, 0.27), Color(0.60, 0.45, 0.33), Color(0.68, 0.52, 0.39),
	Color(0.75, 0.60, 0.47), Color(0.82, 0.67, 0.54), Color(0.87, 0.73, 0.61),
	Color(0.91, 0.78, 0.68), Color(0.94, 0.82, 0.73), Color(0.96, 0.86, 0.79),
]

## Not grey — grey is decided by age below.
const HAIR := [
	Color(0.07, 0.06, 0.06),   ## black
	Color(0.13, 0.10, 0.08),   ## near black
	Color(0.22, 0.15, 0.11),   ## dark brown
	Color(0.31, 0.21, 0.14),   ## brown
	Color(0.40, 0.28, 0.18),   ## light brown
	Color(0.44, 0.24, 0.13),   ## auburn
	Color(0.55, 0.31, 0.14),   ## ginger
	Color(0.62, 0.50, 0.28),   ## dark blond
	Color(0.76, 0.65, 0.42),   ## blond
]

const GREY := Color(0.62, 0.61, 0.60)
const WHITE_HAIR := Color(0.86, 0.86, 0.85)

## Hospital gowns, all washed a hundred times. Close enough together to read as
## a uniform, far enough apart that five in a row are five people.
##
## The first pass had these between 0.78 and 0.90 on every channel, which on a
## white bed under a flat ceiling light is six shades of the same thing: five
## patients in one gown, sitting on linen the same colour as the gown. Pulled
## apart on hue and down in value — still unmistakably NHS-issue, still nobody's
## idea of a colour they chose, but the row now reads as five people.
const GOWN := [
	Color(0.62, 0.72, 0.80),   ## pale blue
	Color(0.66, 0.74, 0.64),   ## sage
	Color(0.80, 0.78, 0.72),   ## bone
	Color(0.74, 0.66, 0.70),   ## faded rose
	Color(0.58, 0.70, 0.71),   ## washed teal
	Color(0.78, 0.74, 0.60),   ## weak custard
	Color(0.68, 0.66, 0.76),   ## grey lilac
]

## Splitmix-style, and NOT String.hash() — Godot's string hash does not spread
## into the low bits, so `hash(id) % 12` came back with three values across the
## whole cast. Constants stay under 2^63 because GDScript's ints are signed and
## the textbook ones wrap to something that is not a bijection any more.
static func _mix(id: String, salt: int) -> int:
	var h: int = 0x2545F491 + salt * 0x9E3779B1
	for i in id.length():
		h = (h ^ id.unicode_at(i)) * 0x01000193
		h = h & 0x0FFFFFFFFFFFFFFF
	h = (h ^ (h >> 30)) * 0x0BF58476D1CE4E5
	h = h & 0x0FFFFFFFFFFFFFFF
	h = (h ^ (h >> 27)) * 0x094D049BB133111
	h = h & 0x0FFFFFFFFFFFFFFF
	return h ^ (h >> 31)

static func _pick(id: String, salt: int, list: Array):
	return list[_mix(id, salt) % list.size()]

## 0.0 .. 1.0, stable for a given id and salt.
static func _unit(id: String, salt: int) -> float:
	return float(_mix(id, salt) % 10000) * 0.0001

## Everything the body builder needs, from an authored case record.
##
## Returns a dictionary rather than a class because it crosses into `NPCBody`,
## which is an autoload-adjacent `class_name` — and CLAUDE.md 1 is about what
## happens when those start referring to each other.
static func of(c: Dictionary) -> Dictionary:
	var id := String(c.get("id", ""))
	var age := int(c.get("age", 50))
	return {
		"skin": _pick(id, 1, SKIN),
		"hair": hair_for(id, age),
		"outfit": _pick(id, 3, GOWN),
		# A person is not a scale factor, but a ward of identical heights is
		# five copies of one, and the eye reads height before it reads a face.
		# Under ten per cent either way: enough to tell them apart down a bay,
		# not so much that anybody is a child or a giant.
		"height": 0.93 + _unit(id, 4) * 0.15,
		# Width independent of height, so nobody is merely a scaled copy of
		# anybody else. This is the difference between five sizes of one person
		# and five people.
		"girth": 0.88 + _unit(id, 5) * 0.30,
		# Hair thins with age and does it to about half of anybody. 0 is a full
		# head, 1 is bald.
		"bald": _balding(id, age),
		# AUTHORED, NOT DERIVED. The first pass rolled facial hair from the same
		# hash as everything else, which meant the game invented a beard for
		# characters whose own written prose describes them — deciding something
		# about a person from a number rather than from what they are. Skin,
		# height and build are interchangeable at this fidelity and a hash is
		# the right tool for them. This one is a fact about somebody, so it
		# lives in their record with the rest of the facts about them.
		"beard": bool(c.get("beard", false)),
	}

## Grey is the one thing here that should not be arbitrary. Nobody under thirty
## is going grey; by eighty almost everybody is white.
static func hair_for(id: String, age: int) -> Color:
	var base: Color = _pick(id, 2, HAIR)
	var greyness: float = clampf((float(age) - 32.0) / 46.0, 0.0, 1.0)
	# Individual variation, so two sixty-year-olds are not the same grey.
	greyness = clampf(greyness * (0.55 + _unit(id, 8) * 0.9), 0.0, 1.0)
	if greyness <= 0.02:
		return base
	var target: Color = GREY.lerp(WHITE_HAIR, clampf((float(age) - 62.0) / 24.0, 0.0, 1.0))
	return base.lerp(target, greyness)

## Men lose it, and they lose it with age; nobody in this game loses it at
## nineteen. The pattern is deliberately coarse — the body has one hair volume
## dial, not a map.
static func _balding(id: String, age: int) -> float:
	var prone: bool = _unit(id, 9) < 0.42
	if not prone:
		return 0.0
	var t: float = clampf((float(age) - 30.0) / 45.0, 0.0, 1.0)
	# Capped short of 1.0. The body builder shrinks the crown by this, and a
	# full 1.0 removes it entirely — a head with no hair mesh at all reads as
	# shaved, which is a decision, where thinning is just time passing.
	return clampf(t * (0.4 + _unit(id, 10) * 1.0), 0.0, 0.92)

## For characters with no authored record — visitors, the man from Coding.
## Same machinery, so a crowd scene is not one face repeated either.
static func anyone(id: String, age := 45) -> Dictionary:
	return of({"id": id, "age": age})
