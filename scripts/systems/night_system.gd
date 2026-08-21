class_name NightSystem
extends Node
## The other half of the day.
##
## The ward has a supply problem that the game never acknowledged: patients
## arrive because a table said so. A doctor whose income depends on occupancy,
## in a building with five beds, has an obvious and appalling solution to an
## empty ward, and the whole tone of the thing points at it.
##
## So the evening is a phase. You go out, you find somebody, and if you are not
## seen doing it they are on your list in the morning with an injury that
## matches the place you found them in.
##
## IT IS THE SAME GAME AS THE WARD
##
## Deliberately. The ward is a stealth game about lines of sight and about who
## can later say what they saw; the street is that game with the furniture
## removed. Cones of vision, a lamp that makes you visible, a person walking a
## route, and a timer. Nothing here is a combat system and nothing here is
## graphic: the act itself is a single beat and a sound, and everything before
## it is positioning.
##
## What comes back is a PATIENT, with a name, in a bed, who has an opinion about
## how they got there — which is where the risk lives. A clean night is an
## admission. A messy one is an admission who remembers a face.

signal night_resolved(result: Dictionary)

## Where you go, who is there, and what they turn up with. Each place maps onto
## a different procedure, so a week of evenings fills a ward with variety rather
## than with five identical forearms.
const PLACES := [
	{
		"id": "ladder_yard", "name": "The Ladder Yard",
		"blurb": "Scaffolders finishing up. Everything here is already leaning.",
		"condition": "acute_shatter", "watchers": 3, "lamps": 2,
		"pay": 1.0, "mark_speed": 62.0,
	},
	{
		"id": "ossory_steps", "name": "Ossory Street steps",
		"blurb": "Forty-one wet steps and one handrail, on the wrong side.",
		"condition": "fractured_ankle", "watchers": 2, "lamps": 1,
		"pay": 0.9, "mark_speed": 48.0,
	},
	{
		"id": "the_anchor", "name": "The Anchor, at closing",
		"blurb": "Nobody in this street is a reliable witness and all of them are here.",
		"condition": "cracked_ribs", "watchers": 5, "lamps": 3,
		"pay": 1.25, "mark_speed": 40.0,
	},
	{
		"id": "multi_storey", "name": "The multi-storey, level four",
		"blurb": "One camera, pointed at the barrier. Concrete everywhere else.",
		"condition": "dislocated_shoulder", "watchers": 2, "lamps": 2,
		"pay": 1.15, "mark_speed": 70.0,
	},
	{
		"id": "allotments", "name": "The allotments",
		"blurb": "Uneven ground, low fences, and a man who is always there.",
		"condition": "torn_knee", "watchers": 1, "lamps": 0,
		"pay": 0.75, "mark_speed": 44.0,
	},
	{
		"id": "tram_stop", "name": "The tram stop on Fell Row",
		"blurb": "Well lit, well used, and the last tram was twenty minutes ago.",
		"condition": "percussive_sinus", "watchers": 4, "lamps": 3,
		"pay": 1.1, "mark_speed": 56.0,
	},
]

static func place(id: String) -> Dictionary:
	for p in PLACES:
		if String(p["id"]) == id:
			return p
	return PLACES[0]

## Names for people who are about to have an accident. Kept apart from the
## ward's own name pool so a mark never shares a name with somebody in a bed.
const MARK_NAMES := [
	"Wendell Tosh", "Bridie Kellaway", "Norbert Flitch", "Sable Ganney",
	"Ruthven Pike", "Delia Moss", "Aubrey Sprint", "Hettie Vaunt",
	"Cosmo Pell", "Ida Brannock", "Percy Loam", "Marguerite Ock",
]

## How exposed you were when it happened, and what that means.
const CLEAN := 0.26
const MESSY := 0.62

var patient_system: PatientSystem = null
var legal = null
## Set while the evening's result is waiting to be reported in the morning.
var last_result: Dictionary = {}
## One outing per night. The rest of the evening is yours.
var used_tonight := false

func _ready() -> void:
	add_to_group("night_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")
	legal = get_tree().get_first_node_in_group("legal_system")

## Is there any point going out? A full ward is the one honest reason not to.
func available() -> bool:
	if used_tonight:
		return false
	return not GameState.flag("tutorial_active", false)

func beds_free() -> int:
	if patient_system == null:
		return 0
	return patient_system.free_wards().size()

static func mark_name(seed_key: String) -> String:
	return String(RNG.pick("mark_%s" % seed_key, MARK_NAMES))

## Turn an evening into a morning.
##
## `exposure` is 0..1 — how much of the act happened where somebody could see
## it. `reached` is whether you got to them at all.
func resolve(place_id: String, mark: String, exposure: float, reached: bool) -> Dictionary:
	used_tonight = true
	var spec := place(place_id)
	var res := {
		"place": String(spec["name"]), "mark": mark, "exposure": exposure,
		"admitted": false, "outcome": "missed",
	}
	GameState.stats.night_jobs += 1

	if not reached:
		# You stood in a doorway for twenty minutes and went home. It costs
		# nothing but the evening, which is the correct price for losing nerve.
		res["outcome"] = "missed"
		res["line"] = "They went in before you got near them. You walk home the long way."
		last_result = res
		night_resolved.emit(res)
		return res

	var clean: bool = exposure < CLEAN
	var messy: bool = exposure < MESSY
	res["outcome"] = "clean" if clean else ("messy" if messy else "caught")

	if clean:
		GameState.stats.night_jobs_clean += 1
		res["line"] = "Nobody looked up. They are going to need somebody to look at that."
	elif messy:
		GameState.stats.night_jobs_botched += 1
		GameState.add_heat(0.08, "something on Fell Row")
		res["line"] = "Somebody in a window. Somebody always in a window."
	else:
		GameState.stats.night_jobs_botched += 1
		GameState.add_heat(0.22, "a description given to police")
		res["line"] = "Two people saw the whole thing and one of them ran after you."

	# Whatever happened, they need a hospital, and yours is the near one. Even
	# the caught case sends them your way — which is the joke and the trap: the
	# witness to your evening is now in your ward, in your care, all week.
	if beds_free() > 0 or messy:
		_book_admission(spec, mark, res["outcome"])
		res["admitted"] = true
	else:
		res["line"] += " There is nowhere to put them; they go across town."

	last_result = res
	night_resolved.emit(res)
	Meta.check_achievements()
	return res

## They turn up tomorrow. Held as a booking rather than a patient so the night
## genuinely ends in between — same machinery a readmission uses, because from
## the ward's point of view that is exactly what this is: somebody arriving in
## the morning with a plausible story.
func _book_admission(spec: Dictionary, mark: String, outcome: String) -> void:
	if patient_system == null:
		return
	patient_system.night_admissions.append({
		"condition": String(spec["condition"]),
		"name": mark,
		"day": GameState.day + 1,
		"outcome": outcome,
		"place": String(spec["name"]),
	})

func new_day() -> void:
	used_tonight = false

func to_dict() -> Dictionary:
	return {"used": used_tonight, "last": last_result.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	used_tonight = bool(d.get("used", false))
	last_result = Dictionary(d.get("last", {}))
