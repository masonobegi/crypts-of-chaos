extends Node
## What people are like, and what they are called. Everything else that used to
## live here — forty joke conditions, twenty-five treatments, the prescription
## table, three shift types, the machine settings — went with the redesign.
##
## What survives is the part that feeds `Mind`: how observant somebody is, how
## much they talk, how readily they believe a doctor. Those are never shown to
## the player as numbers or labels. They decide how a person behaves, and the
## player is expected to work it out by watching them.

## The one nurse on this ward, and the sister who reads the folder in the
## morning. A five-bed ward does not need a rota.
const WARD_NURSE := "Adeyemi"
const WARD_SISTER := "Nkemelu"


# =============================================================== PERSONALITIES
## Traits are read by systems via trait_of(). Missing traits fall back to a
## default, so new archetypes only need to specify what makes them different.
const PATIENT_ARCHETYPES := {
	"trusting": {
		"name": "Trusting", "observance": 0.25, "skepticism": 0.3, "trust": 0.75,
		"talkativeness": 0.35, "escalation": 0.2, "impatience": 0.7, "vital_bias": 0.2,
		"blurb": "Believes you. Genuinely. It's almost upsetting.",
	},
	"paranoid": {
		"name": "Paranoid", "observance": 0.75, "skepticism": 0.9, "trust": 0.25,
		"talkativeness": 0.6, "escalation": 0.75, "impatience": 1.3, "vital_bias": -0.3,
		"blurb": "Has already written down your name. Twice.",
	},
	"hypochondriac": {
		"name": "Hypochondriac", "observance": 0.5, "skepticism": 0.35, "trust": 0.6,
		"talkativeness": 0.8, "escalation": 0.3, "impatience": 0.3, "vital_bias": -0.6,
		"blurb": "Wants to stay. Actively lobbies to stay. Free money.",
	},
	"confrontational": {
		"name": "Confrontational", "observance": 0.55, "skepticism": 0.7, "trust": 0.3,
		"talkativeness": 0.7, "escalation": 0.95, "impatience": 1.5, "vital_bias": 0.1,
		"blurb": "Will escalate. Loudly. In the corridor.",
	},
	"confused": {
		"name": "Confused", "observance": 0.15, "skepticism": 0.2, "trust": 0.6,
		"talkativeness": 0.5, "escalation": 0.15, "impatience": 0.3, "vital_bias": 0.3,
		"blurb": "Not entirely sure this is a hospital.",
	},
	"observant": {
		"name": "Extremely Observant", "observance": 0.95, "skepticism": 0.75, "trust": 0.45,
		"talkativeness": 0.5, "escalation": 0.6, "impatience": 1.0, "vital_bias": -0.1,
		"blurb": "Noticed the dial. Noticed you noticing them notice the dial.",
	},
	"stoic": {
		"name": "Stoic", "observance": 0.4, "skepticism": 0.5, "trust": 0.55,
		"talkativeness": 0.15, "escalation": 0.25, "impatience": 0.5, "vital_bias": 0.7,
		"blurb": "Reports feeling fine. Is not fine. Reports feeling fine.",
	},
	"litigious": {
		"name": "Litigious", "observance": 0.7, "skepticism": 0.8, "trust": 0.3,
		"talkativeness": 0.65, "escalation": 1.0, "impatience": 1.2, "vital_bias": -0.4,
		"blurb": "Knows a guy. The guy is a lawyer. The guy is very available.",
	},
}

const NURSE_ARCHETYPES := {
	"lazy": {
		"name": "Lazy", "observance": 0.2, "skepticism": 0.3, "trust": 0.6,
		"talkativeness": 0.3, "escalation": 0.15, "patrol_speed": 0.7, "idle_bias": 2.0,
		"blurb": "Will not walk to the far end of the ward. Ever.",
	},
	"suspicious": {
		"name": "Suspicious", "observance": 0.85, "skepticism": 0.9, "trust": 0.3,
		"talkativeness": 0.5, "escalation": 0.7, "patrol_speed": 1.1, "idle_bias": 0.4,
		"blurb": "Has a theory about you and is collecting supporting material.",
	},
	"loyal": {
		"name": "Loyal", "observance": 0.6, "skepticism": 0.35, "trust": 0.9,
		"talkativeness": 0.25, "escalation": 0.1, "patrol_speed": 1.0, "idle_bias": 0.8,
		"blurb": "Would cover for you. Would feel bad about it. Would still do it.",
	},
	"gossip": {
		"name": "Gossip", "observance": 0.55, "skepticism": 0.5, "trust": 0.5,
		"talkativeness": 1.0, "escalation": 0.35, "patrol_speed": 1.0, "idle_bias": 1.4,
		"blurb": "The fastest information network in the building.",
	},
	"rule_follower": {
		"name": "Rule Follower", "observance": 0.7, "skepticism": 0.6, "trust": 0.45,
		"talkativeness": 0.4, "escalation": 0.95, "patrol_speed": 1.05, "idle_bias": 0.5,
		"blurb": "Writes it down. Files it. Follows up on it.",
	},
	"corrupt": {
		"name": "Enterprising", "observance": 0.6, "skepticism": 0.4, "trust": 0.55,
		"talkativeness": 0.4, "escalation": 0.05, "patrol_speed": 0.95, "idle_bias": 1.0,
		"blurb": "Saw everything. Has a number in mind.",
	},
	"incompetent": {
		"name": "Incompetent", "observance": 0.3, "skepticism": 0.4, "trust": 0.6,
		"talkativeness": 0.5, "escalation": 0.4, "patrol_speed": 1.2, "idle_bias": 0.9,
		"blurb": "A danger to your plans purely by accident.",
	},
}

const FAMILY_ARCHETYPES := {
	"absent": {
		"name": "Rarely Visits", "observance": 0.3, "skepticism": 0.4, "trust": 0.6,
		"talkativeness": 0.3, "escalation": 0.3, "visit_rate": 0.15,
		"blurb": "Will call. Once. From a car.",
	},
	"constant": {
		"name": "Constantly Visits", "observance": 0.65, "skepticism": 0.6, "trust": 0.45,
		"talkativeness": 0.7, "escalation": 0.6, "visit_rate": 0.9,
		"blurb": "Has a favourite chair here now.",
	},
	"questioner": {
		"name": "Asks Lots Of Questions", "observance": 0.7, "skepticism": 0.7, "trust": 0.4,
		"talkativeness": 0.8, "escalation": 0.5, "visit_rate": 0.6,
		"blurb": "Follow-up questions. Always follow-up questions.",
	},
	"litigious_family": {
		"name": "Threatens Lawsuits", "observance": 0.6, "skepticism": 0.85, "trust": 0.2,
		"talkativeness": 0.6, "escalation": 1.0, "visit_rate": 0.5,
		"blurb": "Opens with the lawsuit. Closes with the lawsuit.",
	},
	"knows_medicine": {
		"name": "Knows Medicine", "observance": 0.9, "skepticism": 0.85, "trust": 0.35,
		"talkativeness": 0.5, "escalation": 0.75, "visit_rate": 0.55,
		"blurb": "Nurse for eleven years. Will spot it in four seconds.",
	},
	"clueless": {
		"name": "Completely Clueless", "observance": 0.1, "skepticism": 0.15, "trust": 0.8,
		"talkativeness": 0.6, "escalation": 0.2, "visit_rate": 0.5,
		"blurb": "Thinks the Vibe Stabiliser is a vending machine.",
	},
}

const TRAIT_DEFAULTS := {
	"observance": 0.5, "skepticism": 0.5, "trust": 0.5, "talkativeness": 0.4,
	"escalation": 0.4, "impatience": 1.0, "vital_bias": 0.0, "patrol_speed": 1.0,
	"idle_bias": 1.0, "visit_rate": 0.5,
}

# =============================================================== NAMES

# =============================================================== NAMES
const FIRST_NAMES := [
	"Greg", "Marlene", "Dougie", "Priya", "Constance", "Bev", "Yusuf", "Tam",
	"Delia", "Roland", "Fenwick", "Moira", "Cliff", "Ines", "Bartholomew",
	"Sandra", "Ogden", "Lurleen", "Vikram", "Trish", "Maurice", "Camille",
	"Herb", "Nadia", "Pontus", "Glenda", "Wes", "Oksana", "Rudy", "Bernadette",
	"Chip", "Femi", "Rosalind", "Duncan", "Marguerite", "Kip", "Astrid", "Lyle",
]

const LAST_NAMES := [
	"Pumbleton", "Vasquez", "Nokes", "Achterberg", "Dill", "Crumb", "Okafor",
	"Feathers", "Stankiewicz", "Bright", "Muldoon", "Han", "Pratchett-Adjacent",
	"Wollop", "Bream", "Oyelaran", "Gundersen", "Spleen", "Marchetti", "Blunt",
	"Kowalczyk", "Tremble", "Dupree", "Nkemdirim", "Fossey", "Ratchet", "Vane",
	"Pillsbury-Ng", "Ostrowski", "Bracket", "Quill", "Mbeki", "Sunderland",
]

const STAFF_FIRST := [
	"Sarah", "Deepa", "Marcus", "Nell", "Terrance", "Yolanda", "Joon", "Bridget",
	"Ola", "Craig", "Simone", "Hank", "Amara", "Vince", "Petra", "Desmond",
]

# =============================================================== HELPERS

## Look a trait up across every archetype table, so callers never need to know
## which role a given archetype belongs to.
func archetype_data(arch: String) -> Dictionary:
	for tbl in [PATIENT_ARCHETYPES, NURSE_ARCHETYPES, FAMILY_ARCHETYPES]:
		if tbl.has(arch):
			return tbl[arch]
	return {}

func trait_of(arch: String, key: String, fallback: float = -9999.0) -> float:
	var d := archetype_data(arch)
	if d.has(key):
		return float(d[key])
	if fallback != -9999.0:
		return fallback
	return float(TRAIT_DEFAULTS.get(key, 0.5))

func archetype_name(arch: String) -> String:
	return String(archetype_data(arch).get("name", arch.capitalize()))

func archetype_blurb(arch: String) -> String:
	return String(archetype_data(arch).get("blurb", ""))

## Build a Mind pre-configured from an archetype.

## Build a Mind pre-configured from an archetype.
func make_mind(id: String, display: String, role: String, arch: String) -> Mind:
	var m := Mind.new(id, display, role)
	m.archetype = arch
	m.observance = trait_of(arch, "observance")
	m.skepticism = trait_of(arch, "skepticism")
	m.trust = trait_of(arch, "trust")
	m.talkativeness = trait_of(arch, "talkativeness")
	m.escalation = trait_of(arch, "escalation")
	return m

## Which treatments are correct for a condition.

## Kept because the redesign still bills by who is paying, and the joke is in
## the names of the companies rather than in the illnesses.
const INSURANCE := {
	"meridian": {"name": "Meridian Mutual", "blurb": "Pays quickly. Reads everything."},
	"standard": {"name": "Standard cover", "blurb": "Pays eventually."},
	"state": {"name": "State", "blurb": "Pays what it decides to pay."},
}

func insurance_name(id: String) -> String:
	return String(INSURANCE.get(id, {}).get("name", id))
