extends Node
## WHAT THE CAREER ADDED UP TO, kept across careers and nowhere else.
##
## THIS FILE EXISTS AGAINST A RULE THIS PROJECT WROTE DOWN, so it is worth being
## precise about which rule and why it does not apply. CLAUDE.md says "there are
## no achievements and no stats dictionary — both existed, both were read by
## nothing, and both were cut". That is a rule about DEAD CODE: the old version
## was a dictionary that systems wrote into and no screen ever read. It is not a
## rule about a player being able to see what they have done, and a store page
## with an empty achievement list reads to a buyer as a game somebody stopped
## working on.
##
## So the shape here is chosen to be the thing that was cut's opposite:
##
##   - NOTHING WRITES TO IT DURING A SHIFT. There is no `achievements.foo += 1`
##     anywhere and there never may be. `evaluate()` is a PURE READ over
##     `DoctorRecord` and `GameState`, exactly like `DoctorRecord.standing()`
##     and `greeting()` are pure reads over their own counters. A system that
##     has to remember to unlock something is a system with an unlock bug in it.
##   - IT IS EVALUATED AT THE HANDOVER AND NOWHERE ELSE. Never mid-shift. The
##     design rule that nothing in the interface scores the player's choice for
##     them is load-bearing — a toast saying "Achievement: Fraud!" the moment a
##     note is typed would tell the player what the game thinks of a decision
##     they have not seen the consequences of yet. These are read AFTER the
##     ward sister has said her piece, which is the one moment in the game where
##     a verdict is the subject.
##   - NOTHING HERE READS `truly_well`, a chart, or anything the investigation
##     layer exists to make you deduce. An achievement that named a patient
##     would be a spoiler with a trophy on it.
##
## The unlocked set is PERMANENT and lives outside the save. That is what an
## achievement is — `SaveSystem.delete_save` runs at the end of every career and
## a career-scoped trophy that vanishes with the save is not one. It is also why
## `both_endings` can exist at all: it is a read over the unlocked set itself,
## which is the only fact here that outlives a career.

const FILE := "user://achievements.json"

## THE LIST. `check` is a Callable taking (rec: DoctorRecord) and returning a
## bool; everything else it needs is on the autoloads. Order is display order.
##
## Deliberately NOT a prize for doing the bad thing. Steam achievements are
## read by some players as a to-do list, so a trophy for "overrule a colleague
## in writing" is an instruction to commit fraud on a ward where the design
## rule is that information must never have negative expected value. The two
## here that record bad outcomes — `struck_off` and `the_list` — are records of
## somewhere a career ended up, which a player reaches by playing badly rather
## than by going and fetching.
const LIST := [
	{
		"id": "first_shift", "name": "Eight to Eight",
		"desc": "Finish a shift and hand the ward over.",
	},
	{
		"id": "first_clean", "name": "Nothing In It",
		"desc": "Sign a shift off with nothing raised against it.",
	},
	{
		"id": "five_clean", "name": "Five Tidy Folders",
		"desc": "Sign off five shifts in one career.",
	},
	{
		"id": "every_ward", "name": "Every Ward in the Building",
		"desc": "Work a shift on all six wards in one career.",
	},
	{
		"id": "paid", "name": "Paid",
		"desc": "Clear what you owe.",
	},
	{
		"id": "never_counted", "name": "Never Had to Count",
		"desc": "Clear it without one flagged night.",
	},
	{
		"id": "long_way", "name": "The Long Way Round",
		"desc": "Clear it without overruling anybody in writing and without "
			+ "sending anybody home against their chart.",
	},
	{
		"id": "out_by_one", "name": "Out By One",
		"desc": "Clear it carrying four of the five.",
	},
	{
		"id": "benefit_of_doubt", "name": "The Benefit of the Doubt",
		"desc": "Use up every clean night she is prepared to count for you.",
	},
	{
		"id": "the_list", "name": "She Has Started Keeping a List",
		"desc": "Have her ask you about the same thing four times.",
	},
	{
		"id": "struck_off", "name": "A Letter, and a Woman from Coding",
		"desc": "Lose your licence.",
	},
	{
		"id": "both_endings", "name": "Both Ways Out",
		"desc": "Reach both endings.",
	},
]

## THE STEAM SEAM, and it is eight lines rather than a note in a document.
##
## GodotSteam is a GDExtension and a separate build, so there is no `Steam`
## singleton in this repo and there cannot be one. What there CAN be is the
## mapping — an achievement's id here against the API Name typed into the
## Steamworks partner site — in the file that owns the list, so that turning it
## on is a build step and not an archaeology exercise. Without the extension
## `_push_to_platform` returns at its first line and the game is unchanged.
##
## The names follow Steam's own convention of a screaming prefix because the
## partner site's field is not the display name and the two get confused.
const STEAM_API_NAME := {
	"first_shift": "ACH_FIRST_SHIFT",
	"first_clean": "ACH_FIRST_CLEAN",
	"five_clean": "ACH_FIVE_CLEAN",
	"every_ward": "ACH_EVERY_WARD",
	"paid": "ACH_PAID",
	"never_counted": "ACH_NEVER_COUNTED",
	"long_way": "ACH_LONG_WAY",
	"out_by_one": "ACH_OUT_BY_ONE",
	"benefit_of_doubt": "ACH_BENEFIT_OF_DOUBT",
	"the_list": "ACH_THE_LIST",
	"struck_off": "ACH_STRUCK_OFF",
	"both_endings": "ACH_BOTH_ENDINGS",
}

var unlocked: Dictionary = {}

func _ready() -> void:
	_load()

## THE WHOLE RULE SET, IN ONE PLACE, AS A READ.
##
## Written as a match rather than as a Callable per entry in `LIST` because a
## Callable stored in a `const` dictionary is a Callable built at parse time
## against an autoload that may not be resolvable yet — the same loader hazard
## gotcha 1 and gotcha 4 are about. A match over an id is dull and it works
## from a `--script` main loop, which is where every probe in this repo lives.
func holds(id: String, rec: DoctorRecord) -> bool:
	match id:
		"first_shift":
			return rec.nights >= 1
		"first_clean":
			return rec.clean_nights >= 1
		"five_clean":
			return rec.clean_nights >= 5
		"every_ward":
			# The ward order is a per-career permutation that visits every ward
			# once before it repeats, so a career that has worked as many nights
			# as there are wards has seen all of them — whatever order it drew.
			return rec.nights >= Cases.DAYS.size()
		"paid":
			return GameState.paid_off()
		"never_counted":
			return GameState.paid_off() and rec.flagged_nights == 0 \
				and rec.referrals == 0
		"long_way":
			return GameState.paid_off() \
				and rec.times("reversed_a_colleague") == 0 \
				and rec.times("sent_home_unwell") == 0
		"out_by_one":
			return GameState.paid_off() \
				and rec.strikes >= DoctorRecord.STRIKES_TO_STRIKE_OFF - 1
		"benefit_of_doubt":
			return rec.forgiven >= DoctorRecord.FORGIVENESS
		"the_list":
			for k in rec.counts:
				if int(rec.counts[k]) >= 4:
					return true
			return false
		"struck_off":
			return GameState.struck_off()
		"both_endings":
			return has("paid") and has("struck_off")
	return false

## Called at the handover and at an ending card, and nowhere else. Returns the
## ids that went from locked to unlocked on THIS call, so the card can show them
## without keeping a second list of what it has already shown.
##
## `both_endings` reads the unlocked set, so the pass runs in `LIST` order and
## that entry is last — a rule that depends on another rule has to be evaluated
## after it, and the alternative (iterate to a fixed point) is a loop written to
## hide an ordering question rather than answer it.
func evaluate() -> Array:
	var rec := DoctorRecord.load_from_state()
	var fresh: Array = []
	for a in LIST:
		var id := String(a["id"])
		if unlocked.has(id):
			continue
		if holds(id, rec):
			unlocked[id] = true
			fresh.append(id)
			_push_to_platform(id)
			Log.i("unlocked '%s'" % id, "Achievements")
	if not fresh.is_empty():
		_save()
	return fresh

func has(id: String) -> bool:
	return unlocked.has(id)

func count() -> int:
	return unlocked.size()

func entry(id: String) -> Dictionary:
	for a in LIST:
		if String(a["id"]) == id:
			return a
	return {}

func _push_to_platform(id: String) -> void:
	# `has_singleton` first, then `has_method` on the object: a call to a method
	# that does not exist is a runtime error, and a runtime error ABORTS THE
	# CALLING FUNCTION rather than raising (gotcha 20) — which would take the
	# rest of `evaluate()`'s loop with it and leave half a pass saved.
	if not Engine.has_singleton("Steam"):
		return
	var api := String(STEAM_API_NAME.get(id, ""))
	if api == "":
		return
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("setAchievement"):
		return
	steam.call("setAchievement", api)
	if steam.has_method("storeStats"):
		steam.call("storeStats")

func _load() -> void:
	unlocked.clear()
	if not FileAccess.file_exists(FILE):
		return
	var text := FileAccess.get_file_as_string(FILE)
	# `JSON.parse_string` pushes the engine's own error on top of yours, so a
	# player with one damaged file gets two errors in the log and the first is
	# about a line number in a file they have never opened (gotcha 72).
	var j := JSON.new()
	if j.parse(text) != OK or typeof(j.data) != TYPE_DICTIONARY:
		Log.w("achievements file will not parse; starting empty", "Achievements")
		return
	for k in Dictionary(j.data):
		# Only ids the build still knows about. A name dropped from `LIST` must
		# not come back as a blank row on the screen.
		if entry(String(k)).is_empty():
			continue
		if bool(Dictionary(j.data)[k]):
			unlocked[String(k)] = true

func _save() -> void:
	# Write, rename, keep the old one — the same shape `SaveSystem` uses, for
	# the same reason: `FileAccess.WRITE` truncates, so writing straight to the
	# path leaves a window in which a crash replaces the file with nothing.
	var tmp := FILE + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.w("cannot write %s" % tmp, "Achievements")
		return
	f.store_string(JSON.stringify(unlocked, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(FILE.get_file()):
		dir.rename(FILE.get_file(), FILE.get_file() + ".bak")
	dir.rename(tmp.get_file(), FILE.get_file())
