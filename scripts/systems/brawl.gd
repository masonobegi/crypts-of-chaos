class_name Brawl
extends RefCounted
## A physical disagreement with a patient.
##
## Asked for by name: "maybe I can fight my patients — if I win, they're staying
## in the hospital longer; if they win, I lose medical bills plus the medical
## day is ended plus no crime at night that night."
##
## Which is a better mechanic than it sounds, because it is the only thing in
## the game where the DOWNSIDE is your own time rather than your reputation. Everything
## else you do badly costs you standing you can still trade against; losing a
## fight to a man with a sore elbow costs you the afternoon, the evening and a
## bill, and no amount of paperwork makes that back.
##
## Nothing here is a treatment and none of it goes on a chart as one. Winning
## leaves them with an injury they did not arrive with, in a room with a door,
## and the ward's existing machinery for "who saw that" does the rest.

## Hits. Six landed on them wins it; four landed on you loses it.
const THEIR_GUARD := 6
const YOUR_GUARD := 4

## How long the wind-up lasts. It shortens as the fight goes on, which is what
## keeps the last two exchanges tense when the first two were free.
const TELEGRAPH_START := 0.90
const TELEGRAPH_MIN := 0.40
const TELEGRAPH_STEP := 0.06

## How far either side of the strike a block still counts, in seconds. Generous
## on purpose: the decision this asks for is WHICH SIDE, not what your reaction
## time is, and a game about picking a side should not be a game about latency.
const WINDOW := 0.26

## Seconds after a swing lands before the next one starts.
const RECOVER := 0.55

static func telegraph_for(exchange: int) -> float:
	return maxf(TELEGRAPH_MIN, TELEGRAPH_START - TELEGRAPH_STEP * float(exchange))

## Who will actually square up.
##
## Anybody admitted, awake and not already discharged. It is not gated on them
## being angry — the joke is that you can start it — but somebody who already
## has a reason is more likely to swing first, which the screen uses for its
## opening line rather than for any rule.
static func can_fight(p) -> bool:
	if p == null or p.discharged:
		return false
	return p.admitted

## Do they have a grievance? Only changes what gets said.
static func has_a_grievance(p, mind) -> bool:
	if p == null:
		return false
	if not p.acquired_injuries().is_empty():
		return true
	if p.is_overdue():
		return true
	if mind != null and mind.strongest(GameState.career_minutes) != null:
		return true
	return false

const OPENERS := {
	"grievance": [
		"You've got a nerve showing up in here.",
		"I've been thinking about this all week.",
		"No. No, we're doing this now.",
	],
	"ordinary": [
		"Sorry — is this about the parking?",
		"I don't want any trouble. I'm just going to have some anyway.",
		"Right. Well. If you insist.",
	],
}

static func opener(p, mind, seed_n: int) -> String:
	var pool: Array = OPENERS["grievance" if has_a_grievance(p, mind) else "ordinary"]
	return String(pool[absi(seed_n) % pool.size()])

## What happens afterwards, as data. The screen grades a brawl and hands the
## spec over; `apply()` is the only thing that touches the world.
const OUTCOMES := {
	"won": {
		"label": "They sit back down",
		"stay": 3.0, "harm": "disputed_contusion", "visual": 0.85, "sue": 0.30,
		"line": "They are staying in. For observation. Of the bruising.",
		"say": ["Alright. ALRIGHT.", "I'd like to make a complaint.",
			"That is going in a letter."],
	},
	"lost": {
		"label": "You wake up on the floor",
		"bill": 1800, "visual": 0.95, "sue": 0.0,
		"line": "The rest of the day is gone, the evening with it, and the "
			+ "hospital has billed you for the stitches.",
		"say": ["Somebody get a doctor. Not him. A different one.",
			"He went down like a filing cabinet.", "Is he meant to be that colour?"],
	},
}

static func outcome(won: bool) -> Dictionary:
	return (OUTCOMES["won"] if won else OUTCOMES["lost"]).duplicate(true)

## The bill for losing, which is the only number in this that scales — a broken
## nose costs the same on day one and day thirty, and on day thirty that is
## nothing at all.
static func bill_for(day: int) -> int:
	return int(OUTCOMES["lost"]["bill"]) + 260 * maxi(0, day - 1)
