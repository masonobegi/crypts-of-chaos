class_name WardDay
extends Node
## One ward, five people, one shift, one payment due at eight o'clock.
##
## This replaces ShiftSystem entirely. There are no shift types, no phases, no
## appointment list and no night out — there is a day, the four ways of putting
## something in a chart, and somebody who reads it in the morning.

signal money_changed(cash: int)
signal entry_written(entry)
## A bed decided. Emitted only on an actual change, so re-confirming the same
## disposition does not count as a new decision.
signal disposition_set(pid, what)
## Somebody's family is at the bedside. (patient_id, display name.) Untyped on
## purpose — see CLAUDE.md 1.
signal visitor_arrived(pid, who)
signal patient_changed(pid: String)
signal day_ended(result: Dictionary)

## Which room each machine stands in, so a WorldEvent raised by writing on one
## is heard by the people in that room rather than at the world origin.
const TERMINAL_ROOM := {
	"the ward terminal": "ward",
	"the nurses' station": "station",
	"the office": "office",
}

const TERMINAL_WARD := "the ward terminal"
const TERMINAL_STATION := "the nurses' station"
const TERMINAL_OFFICE := "the office"

var records := Records.new()
var cash := Cases.STARTING_CASH
var minute := 8 * 60          ## the shift starts at eight in the morning
var ended := false

## Runtime state per patient, keyed by case id. Nothing in here is displayed as
## a number; it is what the simulation knows, which is not the same thing.
var state: Dictionary = {}

## Everything the player did, for the instrumentation. Development only.
var telemetry: Array = []

## Ruth Kerrigan arrives at seven whether you are ready or not. She is a retired
## ward sister, she reads her mother's chart the way she read charts for thirty
## years, and she is the only person in the building who will look at the notes
## without being asked to.
## Kept as the hour Dot Kerrigan's daughter is due, which is what the smoke run
## and `_reads_own_chart` both mean by "Ruth has been". The other two families
## carry their own `family_at`.
const RUTH_ARRIVES := 19 * 60
## patient id -> their family has been today.
var _family_been: Dictionary = {}
## minutes-before-eight -> already called today.
var _called: Dictionary = {}

## Tonight's number. Usually Cases.DEBT_DUE; more if last night came up short.
var debt_tonight := Cases.DEBT_DUE

## How long a result takes to come back. Long enough that ordering one is a
## commitment rather than a lookup, and short enough to land inside the shift.
const TEST_TURNAROUND := 75

## Orders waiting on a result: entry id -> the minute it lands.
var _pending: Dictionary = {}

func _ready() -> void:
	add_to_group("ward_day")
	# THE WARD CLOCK IS THE GAME CLOCK. Without this the day was frozen at eight
	# in the morning: `advance_to` had no callers anywhere outside the tests, so
	# Adeyemi never walked a round, Ruth never arrived, no ordered test ever came
	# back, and the "+15 min" control on the chart could never move because it
	# clamps to a `minute` that never changed. Every measurement in the twenty
	# playthroughs drove the clock by hand and therefore never noticed.
	# GUARDED, BECAUSE `start()` CAN RUN FIRST. A WardDay built with `.new()` and
	# started before it is added to the tree connects in `start()` and then
	# connects again here when `_ready()` finally fires — two ticks per minute on
	# the same node, and a red ERROR at the end of every headless run. `_ready()`
	# is not the only entry point, so it does not get to assume it is the first.
	if not GameState.minute_passed.is_connected(_on_minute):
		GameState.minute_passed.connect(_on_minute)

func _on_minute(now: int) -> void:
	if ended:
		return
	_advance_locally(now)
	for eid in _pending.keys():
		if now < int(_pending[eid]):
			continue
		_pending.erase(eid)
		var order := records.by_id(String(eid))
		if order != null and order.fulfilled_by == "":
			var r := resolve_test(order)
			# "result", not "info". This is the only delayed payoff in the loop —
			# five minutes to order, seventy-five to come back — and it shared a
			# silent toast kind with every hint in the game.
			EventBus.toast.emit("%s is back." % order.order_kind.capitalize(), "result")
	# Vinnie does not wait, and neither does the day. The whole pitch is a
	# number owed at eight o'clock, and until this existed nothing anywhere
	# read DEBT_DUE_MINUTE — a player could wander until three in the morning
	# at no cost, which is the pressure the design is built on simply absent.
	_last_call(now)
	if now >= Cases.DEBT_DUE_MINUTE:
		EventBus.toast.emit("Eight o'clock. He is in the corridor.", "bad")
		sign_off()
		EventBus.request_ui.emit("review", {})

## THE RUN-UP TO EIGHT.
##
## The day ended without a word of warning. At 20:00 every bed still undecided
## was sent home, the shift closed and the handover opened — and the first thing
## the game had ever said about it was "Eight o'clock. He is in the corridor.",
## by which point it had already happened.
##
## The clock is in the corner, so this was never hidden. But a game whose entire
## pressure is a deadline should COUNT DOWN to it, and the useful part of the
## warning is not the time — it is how many beds you have not decided about,
## which is the one thing the player cannot see without opening something.
##
## An hour out, twenty minutes out, and five. Each once: `_advance_locally` runs
## on every verb that jumps the clock, so an ungated toast here fires several
## times a minute.
const LAST_CALL := {60: "An hour left.", 20: "Twenty minutes.", 5: "Five minutes."}

func _last_call(now: int) -> void:
	for mins in LAST_CALL:
		var at: int = Cases.DEBT_DUE_MINUTE - int(mins)
		if now < at or _called.has(mins):
			continue
		_called[mins] = true
		var undecided := 0
		for pid in state:
			if String(state[pid]["disposition"]) == "":
				undecided += 1
		if undecided == 0:
			EventBus.toast.emit("%s All five decided." % String(LAST_CALL[mins]), "info")
		else:
			EventBus.toast.emit("%s %d bed%s still undecided — they go home at eight."
				% [String(LAST_CALL[mins]), undecided, "" if undecided == 1 else "s"],
				"bad" if int(mins) <= 20 else "info")

## ENDING THE SHIFT, once. A bed nobody decided about is a bed sent home — you
## were the doctor and you did not say otherwise — and that is what makes the
## HUD's projection honest, because it counts undecided beds the same way.
##
## Both callers used to spell this loop out for themselves: the eight o'clock
## close here and the office terminal's "Sign off for the night". Two copies of
## the rule that decides how a shift ends, in a game whose whole subject is what
## you did and did not write down.
func sign_off() -> Dictionary:
	for c in Cases.roster():
		var pid := String(c["id"])
		if String(state[pid]["disposition"]) == "":
			set_disposition(pid, "discharge")
	return end_day()

func start() -> void:
	cash = GameState.cash
	# ...and starts listening again, because `start()` is also how tomorrow
	# begins on the same node.
	if not GameState.minute_passed.is_connected(_on_minute):
		GameState.minute_passed.connect(_on_minute)
	# Anything Vinnie did not get last night is on top of tonight.
	# What he wants tonight, which is his usual number unless there is less than
	# that left of the whole thing — nobody hands over more than they owe.
	debt_tonight = mini(Cases.DEBT_DUE, GameState.debt_remaining())
	# CASH CARRIES. This said `cash = Cases.STARTING_CASH` and `start()` is
	# called every morning, so the player was minted nine hundred pounds a night
	# out of nowhere — a third of any night's takings, under every strategy, in
	# every measurement this project has ever taken. It also made "he takes
	# everything at eight" vacuous, because nothing survived the night for him
	# to take. The float is granted once, at the start of a career.
	minute = 8 * 60
	# One clock, and a new shift starts at eight. Without this, a day begun
	# after a handover (or loaded from a save taken at one) opened with the ward
	# at eight in the morning and the HUD at eight at night.
	GameState.minute_of_day = 8 * 60
	ended = false
	_result = {}
	records = Records.new()
	state.clear()
	_read.clear()
	for c in Cases.roster():
		state[String(c["id"])] = {
			"id": String(c["id"]),
			"disposition": "",        ## "", "hold", "discharge"
			"asked_symptom": false,   ## you put a symptom to them
			"agreed": false,          ## and they went along with it
			"recalls": [],            ## entry ids the patient would stand behind
			"suggested": [],          ## ...and remembers you putting into their head
			"nurse_checked": 0,
			"asked_count": 0,         ## how many times you have been back
			"examined": false,        ## you went and looked at them yourself
			"colleague": 0,           ## times you asked Dr Costa
			"tests": 0,
			"discharged_at": -1,
		}
	_family_been.clear()
	_called.clear()
	for pe in Cases.prior_entries():
		var e := ChartEntry.new()
		e.patient_id = String(pe["patient"])
		e.claim = ChartEntry.Claim[String(pe["claim"])]
		e.author = ChartEntry.Author[String(pe["author"])]
		e.author_id = String(pe.get("author_id", ""))
		e.text = String(pe["text"])
		e.stated_minute = int(pe["minute"])
		e.written_minute = int(pe["minute"]) + 3
		e.terminal_id = TERMINAL_WARD
		records.add(e)
	_log("day_start", {"cash": cash, "due": debt_tonight})
	_update_objective()

## Reading a chart properly takes time you do not have. THE HONEST DAY IS AN
## INVESTIGATION: the only way to know Marchetti is the one who genuinely needs
## the bed is to open five records and read them, and until this cost something
## a careful day and a careless one were indistinguishable — the instrumentation
## measured the honest run at five clicks, and it was right. Twelve minutes a
## chart means reading the whole ward is an hour of a twelve-hour shift, which
## is affordable once and not affordable twice.
const READ_COST := 12

## And so does everything else. A twelve-hour shift is a budget, not a backdrop:
## every act of authorship walks you closer to the next round, which is the only
## reason the timing of a note is a decision rather than a text field. The
## cascade is the case that matters — patching a lie three times costs the best
## part of an hour, and an hour is how far it is from a safe gap into Adeyemi
## writing her round up beside you.
const WRITE_COST := 8      ## typing it, at a terminal, properly
const ASK_COST := 10       ## sitting down with somebody and leading them
const NURSE_COST := 15     ## finding her, asking, waiting to be told
const ORDER_COST := 5      ## a form
const EXAMINE_COST := 15   ## curtains round, sleeves up, actually looking
const COLLEAGUE_COST := 25 ## he covers two wards and you have to find him

## Charts read so far today, so re-checking something you already looked at is
## free. The cost is for LEARNING it, not for remembering it.
var _read: Dictionary = {}

func read_chart(pid: String) -> void:
	if ended or _read.has(pid):
		return
	_read[pid] = true
	_log("read_chart", {"pid": pid})
	AudioMgr.play("page", -14.0)
	advance_to(minute + READ_COST)

func has_read(pid: String) -> bool:
	return _read.has(pid)

# ------------------------------------------------------------ the four verbs
## 1. WRITE IT YOURSELF. Cheapest, fastest, and entirely your word.
func write_entry(pid: String, claim: int, text: String, stated: int,
		terminal := TERMINAL_WARD, explains := "") -> ChartEntry:
	var e := ChartEntry.new()
	e.patient_id = pid
	e.claim = claim as ChartEntry.Claim
	e.text = text
	e.stated_minute = stated
	e.written_minute = minute
	e.author = ChartEntry.Author.YOU
	e.author_id = "player"
	e.terminal_id = terminal
	# WHAT THIS NOTE IS ADDING TO, worked out rather than asked for.
	#
	# `explains` had no writer anywhere in the project. Every call to this
	# function left it "", so `_addendum_cascade` — an authored finding with a
	# question, a severity and three answer branches built for it — could never
	# fire once, and `WRITE_COST`'s own design note sells exactly the case it
	# covers: "patching a lie three times costs the best part of an hour". It
	# cost the hour and produced nothing.
	#
	# It does not need a control on the form. Writing the SAME claim about the
	# SAME patient again is what an addendum is: the second note is not a new
	# observation, it is the first one restated because the first one did not
	# hold. So the chain builds itself out of what the player actually does, and
	# by the third one the record is visibly arguing with itself — which is the
	# finding, word for word.
	#
	# Same claim only. A note about the leg at ten and one about the chest at
	# four are two observations, not a patch on a patch, and chaining those
	# would have made ordinary thorough documentation look like a cover-up.
	e.explains = explains if explains != "" else _restates(pid, claim)
	e.seen_by = _who_can_see_me()
	# ...AND THE PEOPLE WHO SAW IT KNOW THEY SAW IT.
	#
	# The two halves of this game were not connected. The paperwork crime is
	# audited at eight o'clock through `seen_by` and `Contradictions`; the
	# suspicion layer — nametag colour, staff stopping to watch you, following
	# you round the ward at high tier — is fed entirely by WorldEvents, and the
	# only things that emit those are slamming a door, throwing a prop and a
	# patient getting out of bed. So a doctor who spent the whole shift writing
	# fabrications at the bedside was watched exactly as closely as one who
	# wrote nothing: the observable crime produced no observation.
	#
	# Typing a note that keeps somebody in, standing where they can watch you do
	# it, is the observable half of the crime this game is about. Weighted low —
	# a doctor writing at a bedside is also just a doctor writing at a bedside —
	# so it takes a pattern rather than one note to make Adeyemi look up.
	if e.supports_stay() and not e.seen_by.is_empty() and is_inside_tree():
		WorldEvent.new("wrote_at_the_bedside", "player") \
			.at(_player_pos(), TERMINAL_ROOM.get(terminal, "ward")) \
			.seen(0.28).in_the_room().tag("paperwork") \
			.says("wrote a note at the bedside").emit()
	records.add(e)
	_log("write", {"pid": pid, "stated": stated, "written": minute,
		"backdated": e.backdated_by(), "terminal": terminal,
		"supports_stay": e.supports_stay(), "explains": explains})
	entry_written.emit(e)
	# THE LOOP WAS SILENT. Every sound in this game is synthesised and there
	# were twenty-eight of them, and not one fired on the four verbs the player
	# spends the entire day inside. A note lands on the record with a paper
	# sound; a backdated one lands with a lower, flatter version of it, which is
	# the only tell in the game that is not written down somewhere.
	AudioMgr.play("paper", -12.0, 0.8 if e.is_backdated() else 1.0)
	advance_to(minute + WRITE_COST)
	return e

## The most recent note of YOUR OWN making this same claim about this patient,
## which the next one is an addendum to. Empty when this is the first.
func _restates(pid: String, claim: int) -> String:
	var last := ""
	for e in records.entries:
		if e.patient_id != pid or e.author != ChartEntry.Author.YOU:
			continue
		if int(e.claim) != claim:
			continue
		last = e.id
	return last

## 2. ASK A LEADING QUESTION. The patient becomes the source — but only if they
## go along with it, and it only survives the morning if they remember doing so.
func ask_patient(pid: String, symptom: String) -> ChartEntry:
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["asked_symptom"] = true
	var agreed: bool = RNG.chance("lead_%s" % pid, float(c.get("suggestible", 0.3)))
	st["agreed"] = agreed
	_log("ask_patient", {"pid": pid, "symptom": symptom, "agreed": agreed})
	if not agreed:
		AudioMgr.play("mumble_lo", -13.0)
		advance_to(minute + ASK_COST)
		return null
	var e := ChartEntry.new()
	e.patient_id = pid
	e.claim = ChartEntry.Claim.UNWELL
	e.text = "Patient reports %s." % symptom
	e.stated_minute = minute
	e.written_minute = minute
	e.author = ChartEntry.Author.PATIENT
	e.author_id = String(c.get("name", pid))
	e.terminal_id = TERMINAL_WARD
	records.add(e)
	# Whether they will still stand behind it in the morning is a different
	# question from whether they nodded now — AND whether they remember being
	# ASKED, which is the other half and the more dangerous one. A patient who
	# recalls the conversation recalls that the symptom was your idea.
	# TWO ROLLS, NOT ONE.
	#
	# This was a single roll that appended to BOTH lists, and the two lists mean
	# opposite things: `recalls` makes the entry corroboration, `suggested`
	# makes it `symptom_was_suggested`, which is in the CONTRADICTED set and is
	# checked first. So remembering lost and not remembering lost — verb three
	# of six could never corroborate anything and was a pure trap in both
	# branches, while the comment above it described a trade the code did not
	# implement. Whether they will stand behind it and whether they remember
	# WHOSE IDEA IT WAS are different questions, and the second is rarer.
	if RNG.chance("recall_%s" % pid, float(c.get("recall", 0.6))):
		(st["recalls"] as Array).append(e.id)
	if RNG.chance("whose_idea_%s" % pid, float(c.get("recall", 0.6)) * 0.4):
		(st["suggested"] as Array).append(e.id)
	entry_written.emit(e)
	AudioMgr.play("mumble", -13.0)
	advance_to(minute + ASK_COST)
	return e

## WHAT THEY SAY WHEN YOU COME BACK.
##
## "Ask how they have been" returned the same sentence every time it was
## pressed, all day, forever — so every person on this ward was four lines long
## and the third conversation was identical to the first. A ward is people you
## keep walking past. Sam Oduya asking whether it is his heart for the third
## time at seven in the evening is worth more than a seventh verb would be.
##
## Chosen from what has actually happened to them, in order of how much it says:
## what you have WRITTEN about them beats how many times you have been back,
## which beats what time it is.
func what_they_say(pid: String) -> String:
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["asked_count"] = int(st.get("asked_count", 0)) + 1
	var asked: int = int(st["asked_count"])

	# You have written that they are unwell. Some of them read it.
	for e in records.for_patient(pid):
		if e.author == ChartEntry.Author.YOU and e.supports_stay() \
				and c.has("on_your_note"):
			return String(c["on_your_note"])
	if asked >= 3 and c.has("pressed"):
		return String(c["pressed"])
	if minute >= 17 * 60 and c.has("evening"):
		return String(c["evening"])
	if asked >= 2 and c.has("later"):
		return String(c["later"])
	return String(c.get("opening", ""))

## 5. GO AND LOOK AT THEM.
##
## THE ONLY VERB THAT TELLS YOU THE TRUTH, and the only one that cannot be
## performed from a terminal. Everything else on this ward is a document: the
## chart is what somebody wrote, the nurse is what somebody found and reported,
## a test is a number about one thing. An examination is the patient, in front
## of you, now — and Peter Lomax on the second ward exists entirely so that
## there is a bed the chart cannot tell you about.
##
## IT WRITES NOTHING, deliberately. This is the verb that informs a decision
## rather than justifying one, and keeping it off the record is what stops it
## becoming a free corroborating note you can award yourself. What it leaves
## behind is that you were there, which is why sending home somebody you
## examined and found unwell is a much harder conversation in the morning.
func examine(pid: String) -> String:
	var st: Dictionary = state[pid]
	# Looking again is free and tells you the same thing. THE COST IS FOR THE
	# FIRST LOOK — a screen that redraws itself must be able to ask what you
	# found without charging you another quarter of an hour for it, which is
	# exactly what the card did on every rebuild until this guard existed.
	if bool(st.get("examined", false)):
		return examination_of(pid)
	st["examined"] = true
	_log("examine", {"pid": pid,
		"found_unwell": not bool(Cases.by_id(pid).get("truly_well", true))})
	AudioMgr.play("mumble_lo", -14.0)
	advance_to(minute + EXAMINE_COST)
	return examination_of(pid)

## What you found, for anything that needs to say it again. No cost, no record.
func examination_of(pid: String) -> String:
	var c := Cases.by_id(pid)
	if bool(c.get("truly_well", true)):
		return String(c.get("exam_well",
			"Nothing to find. They are as well as the chart says they are."))
	return String(c.get("exam_unwell",
		"They are not right, and it is not in the notes."))

func has_examined(pid: String) -> bool:
	return bool(state.get(pid, {}).get("examined", false))

## WHAT A DOCUMENT WOULD SAY, as against what is true.
##
## THE SECOND WARD'S WHOLE PREMISE. Peter Lomax is not well, and every
## instrument that produces a piece of paper says he is: his CIWA is scored at
## fixed times by somebody working through a list, his bloods are unremarkable,
## and he answers the questions. The tremor is intermittent and he is a man who
## says "I'm all right" to anyone who asks.
##
## Without this the rounds simply announced him — Adeyemi wrote "still not right"
## at ten o'clock and the bed was corroborated before the player had got out of
## the office, which made going to look at anybody pointless. A patient flagged
## `only_visible_in_person` reads as well to the ROUNDS, the NURSE and the
## MACHINE, and as what he is to the two verbs that involve somebody sitting
## down in front of him: your own examination, and the registrar's.
static func reads_as_well(pid: String) -> bool:
	var c := Cases.by_id(pid)
	if bool(c.get("only_visible_in_person", false)):
		return true
	return bool(c.get("truly_well", true))

## 6. ASK A COLLEAGUE.
##
## THE STRONGEST CORROBORATION IN THE GAME AND THE MOST DANGEROUS REQUEST.
##
## A nurse looks at the patient. A registrar reads the CHART — all of it, every
## line you have put on it today — and then looks at the patient, and then
## writes down what he THINKS. If they genuinely need the bed he says so in his
## own name, and that bed is defended by a peer: the only thing in the game
## that makes a stay something nobody can take apart.
##
## And if they do not need it, he does not write "settled". He writes a PLAN.
## Disagreeing with a nurse's observation is an argument about a fact.
## Disagreeing with a named doctor's plan is an argument with a colleague, and
## the reviewer has both documents in front of her in the morning.
##
## He covers two wards. He is here at two points in the day and unreachable
## otherwise, which makes asking him something you schedule rather than a
## button you press when it goes wrong.
const COLLEAGUE := "Dr Costa"
const COLLEAGUE_HOURS := [[11 * 60, 13 * 60], [15 * 60, 17 * 60]]

static func colleague_available(at: int) -> bool:
	for w in COLLEAGUE_HOURS:
		if at >= int(w[0]) and at <= int(w[1]):
			return true
	return false

## When he is next about — for a screen that has to say so rather than greying
## a button out and leaving the player to guess.
static func colleague_next(after: int) -> int:
	for w in COLLEAGUE_HOURS:
		if after < int(w[0]):
			return int(w[0])
	return -1

func ask_colleague(pid: String) -> ChartEntry:
	if not colleague_available(minute):
		return null
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["colleague"] = int(st.get("colleague", 0)) + 1
	var well: bool = bool(c.get("truly_well", true))
	# THE REGISTRAR IS NOT AN ORACLE, AND ON THE FOURTH WARD HE IS THE PROBLEM.
	#
	# This verb read `truly_well` and returned it, which made asking Dr Costa a
	# free and perfectly accurate truth detector that also happened to be the
	# strongest defence in the game. Twenty-five minutes bought certainty. The
	# only reason it was not a dominant strategy is that his hours are short.
	#
	# A doctor who has already written his opinion at twenty past four in the
	# morning does not enjoy being asked for it again at half eleven, and he does
	# not go and look a second time — he restates it. On a patient carrying
	# `colleague_wrong` that is exactly what you get: his morning opinion, in his
	# name, on the wrong side, at your request, and now there are two of them in
	# the notes. The tell is in the text, and it is fair: he says when he saw
	# them, and it was before you came on.
	#
	# What this makes true is the point of the ward. `examine` is the only verb
	# in the game that cannot be wrong, and it is the one that writes nothing —
	# so the ward where the paperwork is most confident is the ward where you
	# have to go and look at people yourself.
	var stale: bool = bool(c.get("colleague_wrong", false))
	if stale:
		well = not well
	var e := ChartEntry.new()
	e.patient_id = pid
	e.author = ChartEntry.Author.DOCTOR
	e.author_id = COLLEAGUE
	e.stated_minute = minute
	e.written_minute = minute + 6
	e.terminal_id = TERMINAL_STATION
	e.at_your_request = true
	if well:
		e.claim = ChartEntry.Claim.FIT_FOR_DISCHARGE
		e.text = "Asked to review. Nothing here needing an inpatient bed. For discharge."
		if stale:
			e.text = ("Asked to review again. I saw this patient at %s and my "
				+ "opinion is unchanged. For discharge.") % String(c.get("colleague_seen", "06:40"))
	else:
		e.claim = ChartEntry.Claim.UNWELL
		e.text = "Asked to review. Agree, not safe to go today. Continue as inpatient."
		if stale:
			e.text = ("Asked to review again. As per my note at %s. Not for "
				+ "discharge today.") % String(c.get("colleague_seen", "04:20"))
	records.add(e)
	_log("ask_colleague", {"pid": pid, "backed": not well})
	entry_written.emit(e)
	AudioMgr.play("paper", -12.0, 0.9)
	advance_to(minute + COLLEAGUE_COST)
	return e

## 3. ASK A NURSE TO CHECK. Independently authored, which is the strongest kind
## of record there is — and she writes WHAT SHE FINDS, not what you wanted.
func nurse_check(pid: String) -> ChartEntry:
	var c := Cases.by_id(pid)
	var st: Dictionary = state[pid]
	st["nurse_checked"] = int(st["nurse_checked"]) + 1
	# She scores him. That is what a nurse review IS, and it is why it cannot
	# find the man whose problem does not show up in a score.
	var well: bool = reads_as_well(pid)
	var e := ChartEntry.new()
	e.patient_id = pid
	e.author = ChartEntry.Author.NURSE
	e.author_id = "Adeyemi"
	e.stated_minute = minute
	e.written_minute = minute + 2
	e.terminal_id = TERMINAL_STATION
	e.at_your_request = true
	if well:
		e.claim = ChartEntry.Claim.SETTLED
		e.text = "Reviewed at doctor's request. Settled, no complaints."
	else:
		e.claim = ChartEntry.Claim.UNWELL
		e.text = "Reviewed at doctor's request. Agree, not right yet."
	records.add(e)
	_log("nurse_check", {"pid": pid, "corroborated": not well})
	# SHE SAYS SOMETHING. Adeyemi has been on this ward since six, she writes
	# every round in it, she is the only reason a fabrication is dangerous — and
	# she had not spoken once in the entire game. Being asked to go and confirm
	# something about a man she wrote up as comfortable an hour ago is the
	# moment she would.
	EventBus.subtitle.emit("Adeyemi", _adeyemi_on(pid, well), 4.5)
	entry_written.emit(e)
	AudioMgr.play("paper", -13.0, 1.15)
	advance_to(minute + NURSE_COST)
	return e

## What she says when you send her to look at somebody. Never a mechanic and
## never a warning — she is not the game's conscience, she is a colleague who
## has been here since six and has an opinion about being sent back.
func _adeyemi_on(pid: String, well: bool) -> String:
	var st: Dictionary = state[pid]
	var asked: int = int(st["nurse_checked"])
	var name := String(Cases.by_id(pid).get("name", "them")).split(" ")[-1]
	if not well:
		return RNG.pick("adeyemi_agrees", [
			"I'll look in on %s now, doctor." % name,
			"I was going to say something myself, actually.",
			"Yes. I'm not happy with %s either." % name,
		])
	if asked >= 2:
		return RNG.pick("adeyemi_again", [
			"Again? I looked at %s an hour ago." % name,
			"...Right you are, doctor. Same as I wrote last time, I expect.",
			"I'll go. I'll write down what I find, mind.",
		])
	return RNG.pick("adeyemi_doubts", [
		"%s? I wrote %s up as comfortable this morning." % [name, "them"],
		"If you like. I was in there twenty minutes ago.",
		"Of course. Is there something I've missed?",
	])

## 4. ORDER A TEST. World truth, permanently, whatever anybody wanted.
func order_test(pid: String, kind: String) -> ChartEntry:
	var st: Dictionary = state[pid]
	st["tests"] = int(st["tests"]) + 1
	var o := ChartEntry.new()
	o.patient_id = pid
	o.claim = ChartEntry.Claim.ORDER
	o.text = "%s requested." % kind
	o.order_kind = kind
	o.stated_minute = minute
	o.written_minute = minute
	o.author = ChartEntry.Author.YOU
	o.terminal_id = TERMINAL_WARD
	records.add(o)
	_pending[o.id] = minute + TEST_TURNAROUND
	_log("order_test", {"pid": pid, "kind": kind, "due": minute + TEST_TURNAROUND})
	entry_written.emit(o)
	AudioMgr.play("beep", -13.0)
	advance_to(minute + ORDER_COST)
	return o

## The result lands later. It does not care what the chart says.
func resolve_test(order: ChartEntry) -> ChartEntry:
	var c := Cases.by_id(order.patient_id)
	var well: bool = reads_as_well(order.patient_id)
	# THE MACHINE DOES NOT CARE HOW WELL SOMEBODY LOOKS.
	#
	# `only_visible_in_person` makes a patient read as well to the rounds, the
	# nurse AND the laboratory, which is right for the second ward — Peter Lomax
	# is a man whose numbers are fine and who is plainly not — and wrong for the
	# fourth. Gwen Ashworth was written up for home by the night registrar, the
	# nurse cannot see it either, and asking Costa again gets his morning
	# opinion back, so there was NO route to corroborating her: the correct hold
	# on the ward was uncorroboratable by construction, and the best honest day
	# available on a quarter of the game was NOTED. The probe found it; eleven
	# hundred strategies could not reach a clean stamp.
	#
	# `test_reveals` is the one route, and it costs what it should: five minutes
	# to order and seventy-five to come back, which has to be spent before
	# lunchtime or it lands after you have had to decide. The night registrar
	# did not repeat her bloods. You do, and they are worse.
	if well and bool(c.get("test_reveals", false)) \
			and not bool(c.get("truly_well", true)):
		well = false
	var r := ChartEntry.new()
	r.patient_id = order.patient_id
	r.author = ChartEntry.Author.MACHINE
	r.author_id = order.order_kind
	r.stated_minute = minute
	r.written_minute = minute
	r.terminal_id = TERMINAL_STATION
	if well:
		r.claim = ChartEntry.Claim.RESULT_NORMAL
		r.text = "%s — within normal limits." % order.order_kind
	else:
		r.claim = ChartEntry.Claim.RESULT_ABNORMAL
		r.text = "%s — abnormal, consistent with the picture." % order.order_kind
	records.add(r)
	order.fulfilled_by = r.id
	_log("test_result", {"pid": order.patient_id, "normal": well})
	entry_written.emit(r)
	return r

# ------------------------------------------------------------ dispositions
func set_disposition(pid: String, what: String) -> void:
	var st: Dictionary = state[pid]
	var before: String = String(st["disposition"])
	st["disposition"] = what
	if what == "discharge":
		st["discharged_at"] = minute
	if before != what:
		_log("disposition", {"pid": pid, "from": before, "to": what})
		disposition_set.emit(pid, what)
		# A bed decided sounds like a rubber stamp, because that is what it is.
		AudioMgr.play("stamp", -11.0, 1.0 if what == "discharge" else 0.85)
	patient_changed.emit(pid)
	_update_objective()

## WHAT TO DO NEXT, AND WHERE IT IS.
##
## The HUD line was set once by the morning card and never touched again, and
## the 3D marker listened to a signal nobody sent — so a player who put the
## morning card down had a building, five strangers and no idea what the game
## wanted. Both are driven from the day's actual state now.
func _update_objective() -> void:
	if ended:
		return
	var undecided := 0
	for pid in state:
		if String(state[pid]["disposition"]) == "":
			undecided += 1
	var h = get_tree().get_first_node_in_group("hospital") if is_inside_tree() else null
	if undecided > 0:
		EventBus.objective_changed.emit("Five beds. %s to decide." % (
			"All five" if undecided == 5 else "%d still" % undecided))
		if h != null:
			EventBus.objective_target_changed.emit(h.door_point("ward"), "Ward C")
		return
	EventBus.objective_changed.emit(
		"All five decided. Sign off in your office before eight.")
	if h != null:
		EventBus.objective_target_changed.emit(h.door_point("office"), "Your office")

func held_ids() -> Array:
	var out: Array = []
	for pid in state:
		if String(state[pid]["disposition"]) == "hold":
			out.append(pid)
	return out

func discharged_ids() -> Array:
	var out: Array = []
	for pid in state:
		if String(state[pid]["disposition"]) == "discharge":
			out.append(pid)
	return out

func free_beds() -> int:
	return Cases.BEDS - held_ids().size()

## WHAT A BOUNCE ACTUALLY COSTS: the admission that would have filled the bed
## it is lying in. Charged once, here, rather than by making the bed itself
## worthless — which had the mechanic paying you to re-dump the patient.
func admissions_taken() -> int:
	var back := 0
	for c in Cases.roster():
		if bool(c.get("readmitted", false)):
			back += 1
	return maxi(0, mini(Cases.ADMISSIONS_WAITING - back, free_beds()))

## What tonight pays, if the day ended right now.
##
## "RIGHT NOW" HAS TO MEAN THE SAME THING ON BOTH SIDES OF THE SUM.
##
## It did not. `free_beds()` is `BEDS - held`, so an undecided bed counted as
## free and paid its $500 admission — while `discharged_ids()` counts only the
## beds explicitly marked, so the same undecided bed paid no discharge fee. At
## 08:00 with nothing decided at all, the corner of the screen therefore read
## $1,900: nine hundred in hand plus two admissions for five beds nobody had
## touched, and none of the five discharge fees those admissions imply.
##
## The figure was not merely early, it was arithmetic nothing could produce.
## Sign off on that exact state and the shift pays $2,650, because `sign_off()`
## sends every undecided bed home first. The HUD was quoting a ward that does
## not exist, in a game whose entire score is one number, on the first screen —
## thirty seconds after a briefing card reading "In your account $900".
##
## So an undecided bed is counted the way signing off counts it: as a
## discharge. The projection now answers the question it claims to answer.
func projected() -> Dictionary:
	var nights := 0
	for pid in held_ids():
		nights += night_value(pid)
	var going: int = Cases.BEDS - held_ids().size()
	var d: int = going * Cases.DISCHARGE_FEE
	var adm: int = admissions_taken() * Cases.ADMISSION_FEE
	return {"nights": nights, "discharges": d, "admissions": adm,
		"earned": nights + d + adm, "total": cash + nights + d + adm,
		"due": debt_tonight}

## WHAT A NIGHT IN THIS BED IS ACTUALLY WORTH.
##
## Nothing, if the person in it is back within a day of a discharge you signed.
## An early readmission is not reimbursed, which is true of real coding and is
## also the only thing that stops readmission being a REWARD — the people who
## bounce keep their insurance tier, so without this, sending a premium patient
## home wrongly handed you a premium bed you could then hold entirely honestly.
## Instead the bed you emptied by mistake sits there earning you nothing all
## day, which costs an honest player the best part of six nights of progress.
## The money was never meant to be the punishment; the record is.
##
## A readmitted bed used to pay nothing, and that inverted the entire mechanic:
## HOLDING somebody you had wrongly sent home earned zero, while re-discharging
## them paid $150 and freed a $500 admission. Putting right what you got wrong
## cost you $650 against doing it again. What a bounce actually costs is the
## admission it displaces, which is charged once, in `admissions_taken`.
func night_value(pid: String) -> int:
	return Cases.night_fee(int(Cases.by_id(pid)["tier"]))

## Time passes, and Adeyemi walks her round when she walks it. Anything she
## finds goes in the chart in her name, truthfully, whether it suits you or not.
## Move this ward's own clock, and let the world's follow.
##
## THE WRITE-BACK IS SEPARATE FROM THE READ, and it has to be. When `_on_minute`
## called this, every WardDay in memory both listened to `minute_passed` and
## emitted through it, so two of them alive at once dragged each other forward:
## ward A advancing to half past four woke ward B, which was at half past six,
## which pushed the shared clock to half past six, which woke ward A. The tests
## keep several days alive at once and every one of them silently ran three
## hours late; in the game there is one ward, which is the only reason this had
## not been noticed.
func advance_to(m: int) -> void:
	_advance_locally(m)
	GameState.skip_to(minute)

## The same thing without touching the world clock — what a ward does when the
## world clock is what moved.
func _advance_locally(m: int) -> void:
	var from := minute
	minute = maxi(minute, m)
	var todays: Array = rounds_today()
	for i in todays.size():
		var r: int = int(todays[i])
		if r > from and r <= minute:
			_routine_round(r, i)
	_self_discharges(from)
	_family_arrives(from)

## WHOEVER'S FAMILY IS DUE, at the hour that patient's own prose promises.
##
## This was one hardcoded block for Ruth Kerrigan at seven o'clock. Three
## patients have a `family` authored and every one of them names a time out
## loud — "My son's coming at eleven", "Yemi's coming at six", and Dot Kerrigan's
## daughter in the evening — so the hour is a field now rather than a constant
## that only one of the three could ever match.
##
## And somebody actually arrives. The Ruth line has been printed since the day
## it was written and nothing ever spawned anybody: the same unkept promise as
## "Ms Ferrand from Coding is on the ward today", which was fixed earlier by
## making her turn up. `Game._on_visitor` builds the body; this decides who and
## when, because the ward is what knows the time.
func _family_arrives(from: int) -> void:
	for c in Cases.roster():
		var at: int = int(c.get("family_at", 0))
		if at <= 0 or at <= from or at > minute:
			continue
		var pid := String(c["id"])
		if _family_been.has(pid):
			continue
		_family_been[pid] = true
		EventBus.toast.emit("%s is here. %s" % [String(c.get("family", "The family")),
			String(c.get("family_note", "They read every line."))], "info")
		visitor_arrived.emit(pid, String(c.get("family", "The family")))
		_log("family_arrived", {"pid": pid, "at": at})

## A BED WITH A CLOCK ON IT.
##
## Tallulah Ferreira has a shift at four and has asked three times. If you have
## not decided about her by then she decides for herself, and the ward does not
## stop to ask you first. She is the only pressure in the game that runs the
## other way from the debt: everything else rewards you for taking your time and
## getting the timing right, and she punishes you for it.
##
## What she leaves behind is a note in her own hand, which is a document you did
## not write and cannot control — and if you had already written that she was
## unwell, it is a document that says otherwise.
func _self_discharges(from: int) -> void:
	for c in Cases.roster():
		var at: int = int(c.get("self_discharges_at", 0))
		if at <= 0 or at <= from or at > minute:
			continue
		var pid := String(c["id"])
		var st: Dictionary = state[pid]
		if String(st["disposition"]) != "":
			continue          ## you got to her in time, either way
		st["disposition"] = "discharge"
		st["discharged_at"] = at
		st["self_discharged"] = true
		# ...AND SHE ACTUALLY WALKS OUT. This writes the disposition straight
		# into the state dictionary rather than going through
		# `set_disposition`, so the signal that tells her body to get up and
		# leave never fired. Tallulah Ferreira is the only pressure in the game
		# that runs the other way from the debt — she has a shift at four and
		# she does not wait — and she signed herself out in the paperwork while
		# lying in the bed for the rest of the night.
		disposition_set.emit(pid, "discharge")
		var e := ChartEntry.new()
		e.patient_id = pid
		e.claim = ChartEntry.Claim.MOBILISING
		e.author = ChartEntry.Author.PATIENT
		e.author_id = String(c.get("name", pid))
		e.text = "Self-discharged against advice. Signed the form. Left at %s." \
			% ChartEntry._hhmm(at)
		e.stated_minute = at
		e.written_minute = at
		e.terminal_id = TERMINAL_STATION
		records.add(e)
		_log("self_discharge", {"pid": pid, "at": at})
		# NOT "herself". The toast said it about whoever walked, and a ward of
		# five is drawn from forty people — so the game misgendered the patient
		# roughly half the times it fired, at the moment it most wanted to land.
		EventBus.toast.emit(Cases.about(pid,
			"%s has signed {themselves} out." % String(c.get("name", pid))), "bad")
		AudioMgr.play("door", -10.0)
		patient_changed.emit(pid)
		_update_objective()

## A ward that is already being looked at is a ward with more writing in it.
## This is where last night's verdict stops being a paragraph: after a flag,
## Adeyemi writes her rounds up twice as often, which halves the gaps a
## fabrication has to fit into.
func rounds_today() -> Array:
	var base: Array = []
	for r in Cases.ROUNDS:
		# The 21:00 round was an hour after the day force-ends at eight and
		# could never fire.
		if int(r) < Cases.DEBT_DUE_MINUTE:
			base.append(int(r))
	if not GameState.flag("watched", false):
		return base
	# HARDER, NOT IMPOSSIBLE.
	#
	# The extra rounds used to go at the MIDPOINT between two existing ones, so
	# a watched day ran 10, 11:30, 13, 14:30, 16, 17:30, 19 — ninety minutes
	# apart, every one of them. `ChartEntry.SAME_MOMENT` is forty-five minutes,
	# so each round claims a ninety-minute window and those windows tile the
	# entire shift edge to edge. There was not one minute between quarter past
	# nine and quarter to eight at night when a note could be written without
	# reading as two people disagreeing about the same half hour.
	#
	# Writing in the gap between rounds is the central timing skill of this game.
	# Doubling the rounds should make that skill harder to exercise; instead it
	# deleted the skill, and since the findings that produces get you flagged
	# again, one bad night was a spiral with no way out of it.
	#
	# She writes up twice now — same number of notes, same "Adeyemi has started
	# writing her rounds up twice" on the card — but the second one follows the
	# first by forty-five minutes rather than splitting the gap. That leaves
	# three real windows in the day, about forty-five minutes each, and finding
	# them is the whole point.
	var dense: Array = []
	for i in base.size():
		dense.append(base[i])
		var second: int = base[i] + ChartEntry.SAME_MOMENT
		if i + 1 >= base.size() or second + ChartEntry.SAME_MOMENT < base[i + 1]:
			dense.append(second)
	dense.sort()
	return dense

func _routine_round(at: int, which := 0) -> void:
	for c in Cases.roster():
		var pid := String(c["id"])
		var st: Dictionary = state[pid]
		# Somebody who has gone home is not on the round.
		if String(st["disposition"]) == "discharge" and int(st["discharged_at"]) <= at:
			continue
		var e := ChartEntry.new()
		e.patient_id = pid
		e.author = ChartEntry.Author.NURSE
		e.author_id = "Adeyemi"
		e.stated_minute = at
		e.written_minute = at + 4
		e.terminal_id = TERMINAL_STATION
		# NOT EVERYBODY HAS A LEG PROBLEM.
		#
		# Every unwell patient on every ward got "Round: still not right. Leg
		# remains warm." — a woman with a pulmonary embolism, a man with
		# pancreatitis, a woman with diverticulitis, all described as having a
		# warm leg, four times a night, on the chart screen that is the entire
		# game. It was written for Ivo Marchetti's cellulitis on the first ward
		# and then said about all forty people.
		#
		# PER PATIENT AND PER ROUND. Picking on the patient alone was meant to
		# make a chart read as one nurse describing one person all day rather
		# than as a shuffle — but four rounds then produced four notes that were
		# identical word for word, stacked on the chart screen, which is the
		# screen the whole game happens on. A nurse who looks at somebody four
		# times writes four notes; she says the same THING, not the same words,
		# and a column of copy-paste reads as a bug however it was reasoned.
		#
		# The patient still decides where in the list she starts, so their chart
		# keeps its own voice; the round walks on from there.
		var start: int = absi(hash(pid))
		if reads_as_well(pid):
			e.claim = ChartEntry.Claim.SETTLED
			e.text = String(ROUND_LINES_WELL[(start + which) % ROUND_LINES_WELL.size()])
		else:
			e.claim = ChartEntry.Claim.UNWELL
			e.text = String(ROUND_LINES_UNWELL[(start + which) % ROUND_LINES_UNWELL.size()])
		records.add(e)
	_log("round", {"at": at})

## What a nurse writes at a bedside four times a night — EIGHT on a watched day,
## which is why there are eight of each. Any fewer and a flagged night, the one
## where the chart is being read hardest, is the one where the same line comes
## round twice on the same patient.
##
## Deliberately unspecific: she is recording that she looked and what she found,
## not making a diagnosis, and a line that names a body part is a line that is
## wrong about most of the ward.
const ROUND_LINES_UNWELL := [
	"Round: no better than this morning. Obs unchanged.",
	"Round: still uncomfortable. Asked for something for it.",
	"Round: not settling. Has not eaten today.",
	"Round: poor colour. Slept badly.",
	"Round: still not right. Reviewed with the co-ordinator.",
	"Round: no improvement since handover.",
	"Round: needed help back to bed. Unsteady.",
	"Round: declined supper. Says it is no worse.",
]

const ROUND_LINES_WELL := [
	"Round: comfortable, no concerns.",
	"Round: settled. Up to the toilet unaided.",
	"Round: eating and drinking. No complaints.",
	"Round: comfortable. Asking when they can go.",
	"Round: no concerns. Obs stable.",
	"Round: dressed and sitting out. Waiting on a lift.",
	"Round: slept through. Nothing to report.",
	"Round: independent to the bathroom. Wants to know the plan.",
]

# ------------------------------------------------------------ close of play
## Cached, because more than one thing legitimately asks how the day went — the
## office desk that ended it, the review screen, the harnesses — and handing the
## second caller an empty dictionary made the answer depend on call order.
var _result: Dictionary = {}

func end_day() -> Dictionary:
	if ended:
		return _result
	# GOING HOME EARLY DOES NOT STOP THE EVENING HAPPENING.
	#
	# The office desk ended the day at whatever minute you walked into it, which
	# meant the safest possible shift was to hold three beds at five past eight
	# in the morning and sign off before Adeyemi had walked a single round:
	# nothing to contradict, full money, out by nine. She works the evening
	# whether you are on the ward or not, and she writes it up. What leaving
	# early actually buys you is not being there when she does — every round
	# between now and handover lands on the chart with you unable to answer it.
	# ENDED FIRST, THEN THE EVENING. `advance_to` moves the shared clock, which
	# comes straight back through `_on_minute` and, past eight, calls end_day()
	# again — so the debt was taken off the takings twice and whichever call
	# lost the race handed its caller an empty dictionary. `_on_minute` returns
	# early once this is set, which makes the re-entry a no-op.
	ended = true
	# A FINISHED DAY STOPS LISTENING. `ended` guarded `_on_minute` but the
	# connection stayed, and a ward that is over still reacted to every tick the
	# world sent — which in the harnesses, where several days are alive at once,
	# meant each of them force-discharging its ward and paying Vinnie out of the
	# same career debt when any ONE of them advanced the clock to eight. In the
	# game there is one ward, which is the only reason this was survivable.
	if GameState.minute_passed.is_connected(_on_minute):
		GameState.minute_passed.disconnect(_on_minute)
	advance_to(Cases.DEBT_DUE_MINUTE)
	# THE LAB DOES NOT STOP BECAUSE YOU WENT HOME.
	#
	# `ended` is set above and `_on_minute` returns early once it is, and the
	# clock is disconnected — so every test still in flight was silently thrown
	# away. Then `_unfulfilled_orders` charged 0.30 a piece for "you ordered
	# this and there is nothing to say it was ever done". Ordering bloods was
	# punished twice: you paid five minutes for a result you never got, and then
	# the ward sister held the missing result against you.
	#
	# Anything whose seventy-five minutes were up before eight o'clock comes
	# back. Anything ordered so late it could not have landed by the end of the
	# shift is genuinely outstanding, and that one is fair.
	for eid in _pending.keys():
		if int(_pending[eid]) > Cases.DEBT_DUE_MINUTE:
			continue
		_pending.erase(eid)
		var late := records.by_id(String(eid))
		if late != null and late.fulfilled_by == "":
			resolve_test(late)
	var p := projected()
	# HE TAKES EVERYTHING. What you made tonight goes against what is left of
	# what you owe, and the remainder is the only score the game keeps.
	var in_hand: int = int(p["total"])
	var handed_over: int = mini(in_hand, GameState.debt_remaining())
	var still_owed: int = GameState.pay_vinnie(handed_over)
	# TEN PER CENT A NIGHT ON WHAT IS LEFT, every night, whether you were short
	# or not. It is the only money mechanism in the game: a bad night is never
	# charged twice, it simply takes longer to get out from under. And it is
	# what makes coasting diverge instead of merely being slow.
	var interest := 0
	if still_owed > 0:
		var before_interest := still_owed
		still_owed = int(round(float(still_owed) * (1.0 + Cases.DEBT_INTEREST)))
		interest = still_owed - before_interest
		GameState.set_flag("debt_remaining", still_owed)
	cash = in_hand - handed_over
	GameState.cash = cash
	var short: bool = handed_over < debt_tonight and still_owed > 0
	var res := {
		"earned": p["earned"], "paid": handed_over, "cash": cash,
		"still_owed": still_owed, "wanted": debt_tonight,
		# EXPORTED SO A SCREEN CAN SAY IT. Ten per cent a night compounding is
		# the only money mechanism in the game and no screen mentioned it: night
		# one on the honest path hands over $3,350 against a $15,500 debt and
		# then reads "Still owed $13,365", when 15,500 - 3,350 is 12,150. In a
		# game whose entire score is one number owed, $1,215 appeared from
		# nowhere on the wrong side of the ledger. On a bad night tomorrow's
		# figure is LARGER than today's after you handed over real money, which
		# reads as the game cheating rather than as a loan shark.
		"interest": interest,
		"short": short, "held": held_ids(), "discharged": discharged_ids(),
		"findings": review_findings(),
	}
	_log("day_end", {"earned": p["earned"], "short": short, "cash": cash,
		"findings": res["findings"].size()})
	# Failure is not an ending, it is a worse tomorrow. He does not break
	# anything; he stands in the corridor being pleasant, and Adeyemi asks who
	# he is. A new pair of eyes in your workplace, permanently.
	if short:
		GameState.set_flag("vinnie_visits", true)
	# WHO IS COMING BACK. Anybody you sent home who was not fit to go is in a bed
	# tomorrow — not as a punishment the reviewer hands out, but because that is
	# what happens. It is the only consequence in the game that arrives before
	# anybody has read anything.
	var bouncing := PackedStringArray()
	for pid in state:
		var st: Dictionary = state[pid]
		if String(st["disposition"]) != "discharge":
			continue
		if bool(st.get("self_discharged", false)):
			continue          ## they signed themselves out. That one is not yours.
		if bool(Cases.by_id(pid).get("truly_well", true)):
			continue
		if bool(Cases.by_id(pid).get("readmitted", false)):
			continue          ## already a readmission. Once round is enough.
		bouncing.append(pid)
	# PENDING, NOT LIVE. `Cases.roster()` reads the live flag on every call and
	# the day does not turn over until "Work tomorrow" is pressed — so setting it
	# here readmitted them onto the ward they are still lying on, in time for the
	# handover to ask about it. `screen_day_over._carry()` promotes this.
	GameState.set_flag(Cases.READMIT_PENDING, bouncing)
	res["readmitted"] = bouncing

	_result = res
	AudioMgr.play("money" if not short else "error", -8.0)
	money_changed.emit(cash)
	day_ended.emit(res)
	return res

## What the ward sister will find. Available to the player at any time, because
## she is not using information the chart does not contain.
## What the simulation knows, for the reviewer's bed-by-bed audit. Exposed
## because `Contradictions.audit_beds` needs it and the review screen builds
## that itself rather than being handed a pre-chewed float.
## A file is read harder if it came into the day with something on it: an
## authored flag (Winifred Blake), or a readmission — somebody who was here
## yesterday, went home on your say-so, and is back.
##
## It used to also mean "a bed the sister could not corroborate last night",
## which was dead code in a career: the wards alternate, so that patient was
## never on the ward again before the flag was overwritten. What accumulates
## about a DOCTOR is in `DoctorRecord`; what accumulates about a PATIENT is
## being back in the bed you emptied.
func is_flagged(pid: String) -> bool:
	var c := Cases.by_id(pid)
	return c.has("audit_flag") or c.has("readmitted")

## ONE BUILDER, NOT TWO. `review_truth` and `review_findings` each assembled
## their own copy of this dictionary and had already drifted apart by one key —
## which meant the reviewer's questions and her bed-by-bed audit were reading
## two different accounts of the same day.
func review_truth() -> Dictionary:
	var truth := {}
	for pid in state:
		var c := Cases.by_id(pid)
		var st: Dictionary = state[pid]
		var disp := String(st["disposition"])
		truth[pid] = {
			"well": bool(c.get("truly_well", true)),
			"name": String(c.get("name", pid)),
			"held": disp == "hold",
			## Sent home — by you, or by walking out because you took too long.
			"discharged": disp == "discharge",
			"self_discharged": bool(st.get("self_discharged", false)),
			## You were at the bedside and you know what you found.
			"examined": bool(st.get("examined", false)),
			## Did you go anywhere near them at all? Reading their chart or
			## sending somebody counts; deciding blind does not.
			"looked_at": bool(st.get("examined", false)) or has_read(pid)
				or int(st.get("nurse_checked", 0)) > 0
				or int(st.get("colleague", 0)) > 0
				or int(st.get("asked_count", 0)) > 0,
			## They were here yesterday, you sent them home, and here they are.
			"bounced_back": bool(Cases.by_id(pid).get("readmitted", false)),
			"patient_recalls": st["recalls"],
			"patient_suggested": st["suggested"],
			"flagged": is_flagged(pid),
			"tells_everyone": bool(c.get("tells_everyone", false)),
			"was_asked": bool(st["asked_symptom"]),
			## Somebody outside the hospital reads this chart — either because
			## they asked for a copy before you got here, which is authored, or
			## because they are standing at the bed having turned up.
			##
			## This named Ruth Kerrigan, and she was the only family in the game
			## who could ever arrive. Now that all three do, the rule is what it
			## always meant: whoever is here reads it.
			"family_reads_charts": bool(c.get("family_reads_charts", false))
				or _family_been.has(pid),
			## ...and one patient reads it herself.
			"reads_own_chart": bool(c.get("reads_own_chart", false)),
			"family": String(c.get("family", "The family")),
			"family_note": String(c.get("family_note", "They read every line.")),
			"no_care_at_home": bool(c.get("no_care_at_home", false)),
			## She wants it, and that is the problem.
			"asks_to_stay": bool(c.get("asks_to_stay", false)),
		}
	return truth

func review_findings() -> Array:
	return Contradictions.find_all(records.entries, review_truth(), records.placements)

# ------------------------------------------------------- place and time
## WHERE YOU WERE, AND WHO COULD SEE YOU BEING THERE.
##
## This is the whole reason the game is in first person. A claim to have observed
## something at half past seven is checkable against where you actually were at
## half past seven, and the only thing that makes that checkable is somebody
## having seen you somewhere else. Called on a timer by Game; cheap, because it
## only records a bucket per quarter hour.
func observe_player(room: String, witnesses: PackedStringArray) -> void:
	if witnesses.is_empty():
		return
	# The room the ward's patients are in is where a bedside observation is
	# expected to have happened. Being seen anywhere else at that minute is what
	# `author_elsewhere` is looking for.
	records.place("player", minute, room, String(witnesses[0]), "ward")

## WHO COULD SEE YOU DOING THIS.
##
## A VISION CONE IS THE WRONG TEST FOR WRITING A NOTE. `can_see` answers "is
## this person looking at that point right now", which is exactly right for a
## thing that happens in an instant and exactly wrong for standing at a terminal
## typing for five minutes: five people lying in a row all face the same way, so
## from any one bedside four of them were outside a 112-degree cone and the only
## witness to anything was whoever you happened to be standing in front of. In
## the corridor the answer was nobody at all, which quietly switched off the
## entire reason the game is in first person.
##
## Being in the room is the test. You turn round, they look up, it takes
## minutes. That is also what makes the two terminals mean what the game says
## they mean: the one in the bay is in full view of the ward, and the one in
## your office has a door on it.
## Where the player is standing, for anything that needs to place an event in
## the world. Falls back to the ward's own centre in the headless harnesses,
## which have no player.
func _player_pos() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var p = get_tree().get_first_node_in_group("player")
	return p.global_position if p != null else Vector3.ZERO

func _who_can_see_me() -> PackedStringArray:
	var out := PackedStringArray()
	# CLAUDE.md 5: a node added during a SceneTree's _initialize() is not inside
	# the tree, and get_tree() is null there. The headless harnesses build a
	# WardDay exactly that way.
	if not is_inside_tree():
		return out
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	var player = get_tree().get_first_node_in_group("player")
	var h = get_tree().get_first_node_in_group("hospital")
	if sus == null or player == null:
		return out
	var mine: String = String(h.room_at(player.global_position)) if h != null else ""
	for m in sus.all_minds():
		var b = sus.body_of(m.id)
		if b == null or not is_instance_valid(b) or not b.is_inside_tree():
			continue
		if b.perception == null or b.perception.suppressed:
			continue          ## asleep, or out cold
		# Same room, or watching you from another one.
		if (mine != "" and b.current_room() == mine) \
				or b.perception.sees_player():
			out.append(m.display_name)
	return out

func _log(kind: String, data: Dictionary) -> void:
	data["t"] = minute
	data["kind"] = kind
	telemetry.append(data)
