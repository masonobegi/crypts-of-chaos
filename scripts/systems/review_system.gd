class_name ReviewSystem
extends RefCounted
## Ten past eight in the morning. The ward sister has the folder.
##
## This is not a courtroom and it is not a die roll. She arrives holding exactly
## what the ward wrote down overnight, and she asks about the things that cannot
## both be true. Every question names the two documents that produced it, so
## when it goes badly the player can point at the line that did it.
##
## The player's ANSWERS ARE EVIDENCE TOO. Standing behind a note commits you to
## it. Deferring to the nursing note kills the question and, if you kept the
## patient, immediately raises a worse one — you have just said in front of a
## witness that there was no reason for the bed. And an excuse only works once:
## the second time you blame the terminal clocks she stops writing and looks up.

enum Answer { STAND_BY, WROTE_IT_LATE, DEFER, POINT_AT_NURSE, BLAME_SYSTEM, RECONCILE }

const OUTCOME_CLEAR := "signed off"
const OUTCOME_QUESTIONS := "noted"
const OUTCOME_FLAGGED := "flagged for audit"
const OUTCOME_ESCALATED := "referred"

## THE TWO RATES. How often you have taken a bed nobody else ever saw a reason
## for, measured across the career rather than tonight — one bad night is a bad
## night and a ward runs on those; it is the ratio that describes a person.
##
## At a half she stops accepting "only I saw it" as a defence of the bed. At
## three-quarters she stops accepting it as a defence of you, and one bed is a
## referral. Both wait for a few nights first, so nobody is described by their
## first Tuesday. Everything about the difficulty curve of a career is these
## four numbers.
const HABIT_NIGHTS := 4
const HABIT_RATE := 0.5
const ENTRENCHED_NIGHTS := 5
const ENTRENCHED_RATE := 0.75

## She opens with the softest thing she found and works inward. A reviewer who
## leads with her best question teaches you what she knows before you have to
## answer it.
const MAX_QUESTIONS := 5

var findings: Array = []          ## Array[Contradictions.Finding], ascending
var asked := 0
var resolved: Array = []          ## findings the player talked down
var used_answers := {}            ## Answer -> times used
var transcript: Array = []        ## {question, answer, effect, because}
var extra: Array = []             ## findings the player created in the room
var _beds: Array = []             ## Contradictions.BedAudit, one per billed night
var _upgraded: Dictionary = {}    ## beds the player successfully explained
var _abandoned: Dictionary = {}   ## beds the player gave up on, out loud

## What she already knows about you before she opens the folder. Loaded once per
## review, so the opening line and the escalation both read off one snapshot.
var record: DoctorRecord = null

func begin(all_findings: Array, entries: Array = [], truth: Dictionary = {}) -> void:
	record = DoctorRecord.load_from_state()
	_beds = Contradictions.audit_beds(entries, truth, all_findings)
	_upgraded.clear()
	_abandoned.clear()
	findings = all_findings.duplicate()
	findings.sort_custom(func(a, b): return a.severity < b.severity)
	if findings.size() > MAX_QUESTIONS:
		# She has limited patience, and takes the worst of them.
		findings = findings.slice(findings.size() - MAX_QUESTIONS)
	asked = 0
	resolved.clear()
	used_answers.clear()
	transcript.clear()
	extra.clear()

func current():
	return findings[asked] if asked < findings.size() else null

func finished() -> bool:
	return asked >= findings.size()

## THE NURSE NOTE IS NOT ALWAYS ON YOUR SIDE.
##
## `_has_nurse_support` looks for a NURSE entry that supports the patient
## STAYING, and offering "Adeyemi reviewed them and agreed with me" on the back
## of one made perfect sense for a bed you HELD: somebody else saw what you saw.
##
## For a bed you EMPTIED it is the accusation, word for word. `_sent_home_unwell`
## is built out of exactly that entry — a nurse wrote that this person should
## stay and you sent them home anyway — so the strongest wrongful-discharge
## question in the game was cleared by citing the note that proves it. It was
## the top option on the menu, it needed no verbs, no chart and no examination,
## and it moved the bed from CONTRADICTED to SOLO: FLAGGED became NOTED. Empty
## the ward at five past eight, press the first button, go home. Every night,
## forever, for nothing.
##
## Three findings are about the discharge rather than the stay, and for all
## three a nurse note supporting the stay is what you are being asked about.
##
## The fourth is the room. `she_was_standing_there` is somebody who watched you
## type the only note there was, so answering it with "Adeyemi reviewed them and
## agreed with me" is offering a witness against a witness — and offering her
## against a question that exists precisely because nobody else looked.
const NURSE_IS_THE_ACCUSATION := ["sent_home_unwell", "never_laid_eyes_on_them",
	"readmitted_after_your_discharge", "she_was_standing_there"]

static func _nurse_is_a_defence(f) -> bool:
	return not (String(f.kind) in NURSE_IS_THE_ACCUSATION)

## What she will accept for this particular finding. Options are offered only
## when the world actually supports them — "I asked the nurse to review" is not
## on the menu unless a nurse review exists in the chart.
func options(f, records: Records) -> Array:
	var out: Array = [
		{"a": Answer.STAND_BY, "text": "That is what I observed."},
		{"a": Answer.DEFER, "text": "I would defer to the nursing note."},
	]
	# ONCE. "I wrote it up late" was the answer to the game's headline mechanic
	# and it had no hardening at all, unlike blaming the clocks — so the play was
	# to write everything at twenty to eight, state it for five past eight, and
	# clear it from a menu every single night.
	if (f.kind == "backdated" or f.kind == "addendum_cascade") \
			and int(used_answers.get(Answer.WROTE_IT_LATE, 0)) == 0:
		out.append({"a": Answer.WROTE_IT_LATE, "text": "I wrote it up late. It was a busy shift."})
	if _nurse_is_a_defence(f) and _has_nurse_support(f, records) \
			and not (record != null and record.weight_for(f.kind) >= 1.8):
		out.append({"a": Answer.POINT_AT_NURSE,
			"text": Cases.about(f.patient_id,
				"Adeyemi reviewed {them} and agreed with me.")})
	# THE SKILLED ANSWER, and it is only on the menu when the day you actually
	# had supports it. Without this the review had no skill in it at all: the two
	# heavy findings could not be talked down by any means, so a player who had
	# sequenced their day carefully scored exactly the same as one who had not.
	# AND SHE STOPS OFFERING YOU THE GOOD ANSWERS. The same rule the file
	# already applies to blaming the terminal clocks — an excuse used often
	# enough is not an excuse, it is a pattern — extended to the two answers
	# that actually move a bed. This is what the record DOES.
	var worn_out: bool = record != null and record.weight_for(f.kind) >= 1.8
	var rec := _reconciliation(f, records) if not worn_out else ""
	if rec != "":
		out.append({"a": Answer.RECONCILE, "text": rec})
	out.append({"a": Answer.BLAME_SYSTEM, "text": "The terminal clocks have been out all week."})
	return out

## Is there a clinically coherent story here, given the times things actually
## happened? A transient symptom that has settled by the time somebody tests for
## it is not a contradiction, it is Tuesday. But it is only available if you
## ordered the test LATE, which is a decision made hours earlier.
func _reconciliation(f, records: Records) -> String:
	if records == null or f.patient_id == "":
		return ""
	var list := records.for_patient(f.patient_id)
	match f.kind:
		"objective_refutes":
			var symptom := 0
			var result := 0
			for e in list:
				if e.supports_stay() and e.author != ChartEntry.Author.MACHINE:
					symptom = maxi(symptom, e.stated_minute)
				if e.claim == ChartEntry.Claim.RESULT_NORMAL:
					result = maxi(result, e.stated_minute)
			if result - symptom >= 60:
				return "It was transient. It had settled by the time we tested."
		"conflicting_observations":
			var a = records.by_id(f.entries[0])
			var b = records.by_id(f.entries[1])
			if a == null or b == null:
				return ""
			# NOT against a machine. "It came and went" explains two people
			# disagreeing; it does not explain a test that went looking twenty
			# minutes later and found nothing, and letting it do so handed the
			# player back the very answer that ordering the test was supposed to
			# have cost them.
			if a.author == ChartEntry.Author.MACHINE or b.author == ChartEntry.Author.MACHINE:
				return ""
			if absi(a.stated_minute - b.stated_minute) >= 25:
				return "It came and went. That is what transient means."
		"justification_undermined":
			# You wrote that he was unwell, then wrote that he had settled, and
			# billed the night anyway. That is only defensible if the settling
			# happened too late in the day to act on — you cannot put a
			# seventy-year-old in a taxi at half past six because he perked up.
			# The gate used to be `>= DEBT_DUE_MINUTE`, which is the minute the
			# ward closes: no entry can ever be stated at or after it, so this
			# answer had never once been offered to anybody.
			for e in list:
				if e.supports_discharge() and e.stated_minute >= Cases.DEBT_DUE_MINUTE - 90:
					return "He settled at that hour. I was not sending him home in the dark."
		"reversed_a_colleague":
			for e in list:
				if e.author == ChartEntry.Author.NURSE and e.supports_stay():
					return "I asked her to look again, and she agreed with me."
	return ""

func _has_nurse_support(f, records: Records) -> bool:
	if f.patient_id == "" or records == null:
		return false
	for e in records.for_patient(f.patient_id):
		if e.author == ChartEntry.Author.NURSE and e.supports_stay():
			return true
	return false

## WHAT SHE SAYS BACK, AND WHY THERE USED TO BE FOURTEEN OF THEM.
##
## One string was hard-coded per (Answer, outcome) pair — "She writes one word
## and moves on.", "That isn't what I asked you.", and about a dozen others. A
## career is nine handovers of up to five questions, so the player reads those
## fourteen sentences something like forty-five times. Every other speaking part
## in this game has variant sets: Adeyemi has three buckets of three, the
## patients have five conversational states each and a different line for every
## one of forty people. The one character the player is guaranteed to sit
## opposite on every night of the career had none — and she is the character the
## tone document specifically names, because "the ward sister's courtesy" is
## where the comedy is supposed to live. Fourteen strings cannot carry withering
## courtesy across nine mornings.
##
## TWO REGISTERS, AND THE SECOND ONE IS THE CAREER. `warm` is a reviewer doing
## her job; `cold` is the same woman who has raised this exact kind of finding
## about you twice already, or who has had to refer you. That escalation is what
## `opening_line()` has always narrated and what the effects never once
## reflected.
##
## CHOSEN BY INDEX, NOT BY `RNG.pick`. Three reasons, and the last one decided
## it. A pick advances a named stream, and streams are saved and restored by
## position (gotcha 70), so a screen that rebuilds on every answer would write
## randomness into the save on a path nothing else touches. A pick can hand the
## same sentence out three times in one conversation, which is the fault this
## exists to fix. And an index on `record.nights` plus the question number walks
## the list — so a career sees a different one every night by construction
## rather than by luck, and the same review never repeats itself.
const EFFECTS := {
	"stand_by_ok": {
		"warm": [
			"She writes one word and moves on.",
			"\"Fine.\" She turns the page before you have finished saying it.",
			"She underlines something small and carries on down the list.",
		],
		"cold": [
			"She writes one word. She has written that word about you before.",
			"\"Observed.\" She says it the way you would read out a postcode.",
		],
	},
	"stand_by_hardens": {
		"warm": [
			"She reads it again, and then reads it a third time.",
			"\"Mm.\" She does not write anything, which is worse than if she had.",
			"She holds the page nearer the light and says nothing for a while.",
		],
		"cold": [
			"She does not read it again. She has read it enough times to know what it says.",
			"\"You've said that before, doctor. It didn't cover it then either.\"",
		],
	},
	"late_ok": {
		"warm": [
			"\"Everybody does. Try not to.\"",
			"\"Half this ward writes at twenty to eight. I'd rather you didn't join them.\"",
			"\"Late is not the same as wrong. It is not the same as right, either.\"",
		],
		"cold": [
			"\"Everybody does. You do it more than everybody.\"",
			"\"I'll take that. I am not going to keep taking it.\"",
		],
	},
	"late_wrong": {
		"warm": [
			"\"That isn't what I asked you.\"",
			"\"I know when you wrote it. I asked you what it says.\"",
			"\"The time is not the difficulty here.\"",
		],
		"cold": [
			"\"That isn't what I asked you. It wasn't last time either.\"",
			"\"You do reach for that one, don't you.\"",
		],
	},
	"defer_refused": {
		"warm": [
			"\"That isn't an answer to what I asked.\"",
			"\"You can defer to her about a temperature. You cannot defer to her about a bed.\"",
			"\"That is her opinion about one patient. I asked you about a pattern.\"",
		],
		"cold": [
			"\"No. We have been round this one.\"",
			"\"That isn't an answer, and you know by now that it isn't.\"",
		],
	},
	"defer_ok": {
		"warm": [
			"She accepts it, and writes that down.",
			"\"Right. Her observation over yours. I'll put that.\"",
			"She writes 'defers to nursing' and does not look up while she does it.",
		],
		"cold": [
			"She writes it down, and then writes something after it you cannot read upside down.",
			"\"Her observation over yours. Again.\"",
		],
	},
	"defer_looks_up": {
		"warm": [
			"Then she looks up.",
			"Then she stops, and looks at you rather than at the folder.",
			"Then she puts the pen down.",
		],
		"cold": [
			"Then she looks up, and she does not look back down.",
			"Then she closes the folder over her finger and waits.",
		],
	},
	"nurse_wrong_scope": {
		"warm": [
			"\"She reviewed one of them. I'm asking about all of them.\"",
			"\"Adeyemi is not a defence to a pattern, doctor. She's a nurse.\"",
			"\"One bed. I have five of them here.\"",
		],
		"cold": [
			"\"One bed, and you have offered me her for all five before.\"",
			"\"She reviewed one of them. You know that isn't the question.\"",
		],
	},
	"nurse_ok": {
		"warm": [
			"\"I'll ask her.\" She does, later, and it holds.",
			"\"Then she'll say so.\" She asks Adeyemi on the way out, and Adeyemi does.",
			"She writes Adeyemi's name beside yours, which is what you wanted.",
		],
		"cold": [
			"\"I'll ask her.\" She does. It holds, and she notes that you sent her to ask.",
			"She writes Adeyemi's name beside yours again. She has stopped writing it neatly.",
		],
	},
	"reconcile_ok": {
		"warm": [
			"\"...All right. Yes. That happens.\"",
			"\"Hm. That does hang together, actually.\"",
			"She reads the two times, then reads them the other way round. \"Yes.\"",
		],
		"cold": [
			"\"...All right. That one hangs together.\" She does not say which one didn't.",
			"\"Yes. That happens.\" She writes the time down anyway.",
		],
	},
	"clocks_ok": {
		"warm": [
			"\"Hm. I'll raise it with IT.\"",
			"\"They have been out. I'll put it in the book with the others.\"",
			"\"That would explain the stamp. It doesn't explain a great deal else.\"",
		],
		"cold": [
			"\"I'll raise it with IT.\" She does not write anything down.",
			"\"The clocks. Right.\" She writes the word 'clocks' and rings it.",
		],
	},
	"clocks_wrong": {
		"warm": [
			"\"The clocks have nothing to do with this one.\"",
			"\"There is no timestamp in this question, doctor.\"",
			"\"That is an answer to a different folder.\"",
		],
		"cold": [
			"\"The clocks. Again. No.\"",
			"\"We are not going to do the clocks.\"",
		],
	},
	"clocks_pattern": {
		"warm": [
			"She stops writing.",
			"She stops writing, and puts the pen down flat on the page.",
			"She stops writing and looks at you until you stop talking.",
		],
		"cold": [
			"She stops writing. She was expecting that one.",
			"She does not stop writing. She writes it down as the second time.",
		],
	},
}

## HAS SHE HEARD THIS FROM YOU BEFORE. `weight_for` is 1.0 + 0.28 per previous
## finding of the kind, so two of them is 1.56 — compared against 1.5 rather than
## 1.56 because that arithmetic is a float and a literal equal to it is the kind
## of comparison that works everywhere except on the machine that matters.
func _colder(f) -> bool:
	if record == null:
		return false
	if record.referrals >= 1:
		return true
	return f != null and record.weight_for(String(f.kind)) >= 1.5

## THE PICK HAPPENS AFTER `cleared` IS DECIDED, ALWAYS, and never feeds back into
## it — the verdict has to stay a pure function of the answer, because
## `playtest_impl` and `frontier_impl` between them drive this several thousand
## times and read the outcome. Nothing in here reads or writes anything but text.
func _effect(key: String, f) -> String:
	var bank: Dictionary = EFFECTS.get(key, {})
	var list: Array = Array(bank.get("cold" if _colder(f) else "warm", []))
	if list.is_empty():
		list = Array(bank.get("warm", []))
	if list.is_empty():
		return ""
	# `transcript.size()` is how many questions she has already put to you
	# tonight, and it is stable for a given question because the chosen string
	# is stored in the transcript rather than re-derived. `nights` moves the
	# whole conversation along one every morning.
	var nights: int = record.nights if record != null else 0
	return String(list[(nights + transcript.size()) % list.size()])

## Answer the question in front of you. Returns what it did, in plain words.
func answer(choice: int, held_ids: Array) -> Dictionary:
	var f = current()
	if f == null:
		return {}
	asked += 1
	var times := int(used_answers.get(choice, 0))
	used_answers[choice] = times + 1
	var effect := ""
	var cleared := false

	match choice:
		Answer.STAND_BY:
			# Insisting works on a small discrepancy and hardens a large one.
			if f.severity < 0.5:
				cleared = true
				effect = _effect("stand_by_ok", f)
			else:
				effect = _effect("stand_by_hardens", f)

		Answer.WROTE_IT_LATE:
			if f.kind == "backdated" or f.kind == "addendum_cascade":
				cleared = true
				effect = _effect("late_ok", f)
			else:
				effect = _effect("late_wrong", f)

		Answer.DEFER:
			# YOU CANNOT DEFER TO A NURSING NOTE ABOUT A PATTERN. Deferring is
			# "her observation over mine", which only answers a question about
			# one observation — it says nothing about why three people stayed,
			# or why a bed was billed with nothing written down at all. Those
			# used to clear for free, which is why five findings totalling 2.69
			# could be talked to zero.
			if f.patient_id == "" or f.kind == "no_reason_recorded":
				effect = _effect("defer_refused", f)
				transcript.append({
					"kind": f.kind, "question": f.question, "answer": choice,
					"effect": effect, "cleared": false, "because": f.because,
					"severity": f.severity,
				})
				return {"cleared": false, "effect": effect}
			cleared = true
			effect = _effect("defer_ok", f)
			_abandoned[f.patient_id] = true
			# ...and if the bed was billed, you have just removed its reason.
			if f.patient_id != "" and held_ids.has(f.patient_id):
				var g := Contradictions.Finding.new()
				g.kind = "justification_abandoned"
				g.patient_id = f.patient_id
				g.axis = "what you just said"
				g.severity = 0.75
				g.question = "So there was no clinical reason for the bed. Why was he in it?"
				g.because = ("You told the reviewer, out loud, that the note keeping "
					+ "this patient in was wrong. The night was billed on that note.")
				extra.append(g)
				effect += " " + _effect("defer_looks_up", f)

		Answer.POINT_AT_NURSE:
			# Only about the patient she actually reviewed. Pointing at Adeyemi
			# answers "did anybody else see this", not "why did three people
			# stay" — and the option is only on the menu when a supporting
			# nursing note exists for that patient in the first place.
			if f.patient_id == "":
				effect = _effect("nurse_wrong_scope", f)
			else:
				cleared = true
				effect = _effect("nurse_ok", f)
				_upgraded[f.patient_id] = true

		Answer.RECONCILE:
			cleared = true
			effect = _effect("reconcile_ok", f)
			_upgraded[f.patient_id] = true

		Answer.BLAME_SYSTEM:
			# It is an answer about TIMESTAMPS. It used to clear anything of any
			# severity on its first use — a conflicting observation, a normal
			# result, an entire pattern — which made it a free pass out of the
			# worst question in the folder.
			if times == 0 and (f.kind == "backdated" or f.kind == "addendum_cascade"):
				cleared = true
				effect = _effect("clocks_ok", f)
			elif times == 0:
				effect = _effect("clocks_wrong", f)
			else:
				# The same excuse twice is not an excuse, it is a pattern.
				var g := Contradictions.Finding.new()
				g.kind = "story_shifting"
				g.axis = "how you are explaining this"
				g.severity = 0.60 + 0.2 * float(times)
				g.question = "That is the second time you've blamed the clocks."
				g.because = "The same excuse was used %d times in one conversation." % (times + 1)
				extra.append(g)
				effect = _effect("clocks_pattern", f)

	if cleared:
		resolved.append(f)
	transcript.append({
		"kind": f.kind, "question": f.question, "answer": choice,
		"effect": effect, "cleared": cleared, "because": f.because,
		"severity": f.severity,
	})
	return {"cleared": cleared, "effect": effect}

## What is left standing when she closes the folder.
## THE VERDICT IS PER BED, NOT PER FLOAT.
##
## She goes down the list of beds that were billed and asks one question about
## each: why was this one occupied? A held bed cannot be removed from that list
## by writing nothing — an empty chart is the WORST answer to the question, not
## a way of avoiding it. That is the whole reason this replaced a sum: a sum
## rewards making findings not happen, and the cheapest way to make a finding
## not happen was to stop playing the game.
func outcome() -> Dictionary:
	var beds: Array = _beds
	# What the player said in the room can move a bed either way.
	for pid in _upgraded:
		for b in beds:
			if b.patient_id == pid and b.state == Contradictions.Defence.CONTRADICTED:
				b.state = Contradictions.Defence.SOLO
				b.why = "explained, but still only on your word"
	for pid in _abandoned:
		for b in beds:
			if b.patient_id == pid:
				b.state = Contradictions.Defence.NONE
				b.why = "you told her the reason was wrong"

	# THE RECORD REACHES THE VERDICT. `weight_for` only ever scaled a finding's
	# severity, and severity has three consumers — which questions get asked,
	# whether STAND_BY works, and screen text. None of them writes a bed state,
	# so the entire escalation produced no change to the verdict, the money or
	# the ending. It made the review LESS playable (heavier questions crowd out
	# the ones about the beds you could still save) while leaving the outcome
	# identical.
	#
	# Measured as a RATE, not a career total, so a long careful run is not
	# punished for its length: once you are averaging an uncorroborated bed
	# every other night, "only you saw it" stops being something she accepts.
	var rate: float = record.uncorroborated_rate() if record != null else 0.0
	var habitual: bool = record != null and record.nights >= HABIT_NIGHTS \
		and rate >= HABIT_RATE
	# AND THE RATE ABOVE THAT ONE, which is a different conversation.
	#
	# `habitual` turns a solo bed into an indefensible one, and one indefensible
	# bed is FLAGGED — worth a single strike, which a clean night pays straight
	# back. So the doctor who took exactly one bed on his own word EVERY night
	# sat at "flagged for audit" forever: five strikes takes five bad nights and
	# the debt clears in six, so the most dishonest policy in the game was also
	# the fastest way out of it. Escalation needed TWO indefensible beds in one
	# night, and a once-a-night liar never produces two.
	#
	# The one-night measure could not see him, because there was nothing wrong
	# with any single night of it. What is wrong is the sequence, and the record
	# is the only thing that holds the sequence. So above three-quarters — she
	# has asked about this on three nights in four and heard the same answer —
	# one bed is enough. This is the ladder `opening_line()` has always narrated
	# ("I have started keeping a list") and the verdict never climbed.
	#
	# The gap between the two rates is deliberate and it is the whole game: an
	# uncorroborated bed every other night stays survivable forever, and that is
	# the policy the design is trying to make findable.
	var entrenched: bool = record != null and record.nights >= ENTRENCHED_NIGHTS \
		and rate >= ENTRENCHED_RATE
	var indefensible: Array = []
	var solo: Array = []
	for b in beds:
		if b.indefensible():
			indefensible.append(b)
		elif b.state == Contradictions.Defence.SOLO:
			if habitual:
				b.why = "on your word alone, again — and she has stopped taking it"
				indefensible.append(b)
			else:
				solo.append(b)

	var verdict := OUTCOME_CLEAR
	if indefensible.size() >= 2 or (entrenched and indefensible.size() >= 1):
		verdict = OUTCOME_ESCALATED
	elif indefensible.size() == 1 or solo.size() >= 2:
		verdict = OUTCOME_FLAGGED
	elif solo.size() == 1:
		verdict = OUTCOME_QUESTIONS

	var worst_bed = indefensible[0] if not indefensible.is_empty() \
		else (solo[0] if not solo.is_empty() else null)
	var because := "Every bed you billed had a reason in it that somebody else had seen."
	if worst_bed != null:
		var who := Cases.name_of(worst_bed.patient_id)
		because = "%s stayed the night and %s." % [who, worst_bed.why]

	# SHE REMEMBERS THE DOCTOR, NOT THE BED. This used to return the patients
	# whose beds she could not stand up, and tomorrow read their files harder —
	# which was measured, worked, and was completely dead in a career, because
	# the wards alternate and those people are not on the ward tomorrow. What
	# accumulates is the person she keeps having to ask. Still returned by name
	# so the end-of-day screen can say who tonight's were.
	var remembered := PackedStringArray()
	for b in beds:
		if b.indefensible() or b.state == Contradictions.Defence.SOLO:
			remembered.append(b.patient_id)

	return {
		"verdict": verdict,
		"beds": beds.size(),
		"indefensible": indefensible.size(),
		"solo": solo.size(),
		"because": because,
		"transcript": transcript,
		"created": extra.size(),
		"remembered": remembered,
		## What she said before she said anything else, and empty on a clean
		## record — for the first few days she has no reason to open with
		## anything at all.
		"opening": record.opening_line() if record != null else "",
	}

## THE ONE PLACE THE NIGHT GOES ON YOUR RECORD.
##
## Separate from `outcome()`, which several screens call and which must stay a
## pure read — a counter that incremented every time somebody looked at the
## verdict would have made the escalation depend on how many times the player
## opened a card.
func commit(findings_raised: Array) -> void:
	if record == null:
		record = DoctorRecord.load_from_state()
	record.record_night(findings_raised, String(outcome()["verdict"]))

## Her closing line. Written to tell the player what happened, not to score them.
##
## Four verdicts and, until this session, four strings — so the last thing she
## said to you was identical on every night of a nine-night career. Three each
## now, walked by `GameState.day` rather than picked: `screen_review._closing`
## is reached through `rebuild()`, so a random pick would hand out a different
## sentence every time the card redrew, and the day number is both stable inside
## a night (it does not move until "Work tomorrow" is pressed on the NEXT
## screen) and different on the next one, which is exactly what was wanted.
const CLOSINGS := {
	OUTCOME_CLEAR: [
		"\"Fine. Go home, you look dreadful.\"",
		"\"Nothing here. Go on, before somebody finds you something.\"",
		"\"That's all of it. Go home and eat something.\"",
	],
	OUTCOME_QUESTIONS: [
		"\"I've made a note. It's probably nothing.\"",
		"\"I'll put a note on. That's all it is at the minute.\"",
		"\"One note. I'd rather not write a second one about the same thing.\"",
	],
	OUTCOME_FLAGGED: [
		"\"I'm going to have coding look at this one. Nothing personal.\"",
		"\"This goes to Coding. It isn't me you'll be explaining it to.\"",
		"\"Coding can have this one. I'd tidy the rest of the week, if I were you.\"",
	],
	OUTCOME_ESCALATED: [
		"\"I'd like you to put all of that in writing, please. Today.\"",
		"\"All of it, in writing, before you leave the building. Today.\"",
		"\"Write it down. All of it, in your own words. Somebody upstairs reads it.\"",
	],
}

static func closing(verdict: String) -> String:
	var list: Array = Array(CLOSINGS.get(verdict, []))
	if list.is_empty():
		return ""
	return String(list[maxi(GameState.day - 1, 0) % list.size()])
