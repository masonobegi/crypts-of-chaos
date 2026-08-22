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

func begin(all_findings: Array) -> void:
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

## What she will accept for this particular finding. Options are offered only
## when the world actually supports them — "I asked the nurse to review" is not
## on the menu unless a nurse review exists in the chart.
func options(f, records: Records) -> Array:
	var out: Array = [
		{"a": Answer.STAND_BY, "text": "That is what I observed."},
		{"a": Answer.DEFER, "text": "I would defer to the nursing note."},
	]
	if f.kind == "backdated" or f.kind == "addendum_cascade":
		out.append({"a": Answer.WROTE_IT_LATE, "text": "I wrote it up late. It was a busy shift."})
	if _has_nurse_support(f, records):
		out.append({"a": Answer.POINT_AT_NURSE, "text": "Adeyemi reviewed him and agreed with me."})
	# THE SKILLED ANSWER, and it is only on the menu when the day you actually
	# had supports it. Without this the review had no skill in it at all: the two
	# heavy findings could not be talked down by any means, so a player who had
	# sequenced their day carefully scored exactly the same as one who had not.
	var rec := _reconciliation(f, records)
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
			for e in list:
				if e.supports_discharge() and e.stated_minute >= Cases.DEBT_DUE_MINUTE:
					return "He was fine by then. That is why he went home this morning."
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
				effect = "She writes one word and moves on."
			else:
				effect = "She reads it again, and then reads it a third time."

		Answer.WROTE_IT_LATE:
			if f.kind == "backdated" or f.kind == "addendum_cascade":
				cleared = true
				effect = "\"Everybody does. Try not to.\""
			else:
				effect = "\"That isn't what I asked you.\""

		Answer.DEFER:
			# YOU CANNOT DEFER TO A NURSING NOTE ABOUT A PATTERN. Deferring is
			# "her observation over mine", which only answers a question about
			# one observation — it says nothing about why three people stayed,
			# or why a bed was billed with nothing written down at all. Those
			# used to clear for free, which is why five findings totalling 2.69
			# could be talked to zero.
			if f.patient_id == "" or f.kind == "no_reason_recorded":
				effect = "\"That isn't an answer to what I asked.\""
				transcript.append({
					"kind": f.kind, "question": f.question, "answer": choice,
					"effect": effect, "cleared": false, "because": f.because,
					"severity": f.severity,
				})
				return {"cleared": false, "effect": effect}
			cleared = true
			effect = "She accepts it, and writes that down."
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
				effect += " Then she looks up."

		Answer.POINT_AT_NURSE:
			# Only about the patient she actually reviewed. Pointing at Adeyemi
			# answers "did anybody else see this", not "why did three people
			# stay" — and the option is only on the menu when a supporting
			# nursing note exists for that patient in the first place.
			if f.patient_id == "":
				effect = "\"She reviewed one of them. I'm asking about all of them.\""
			else:
				cleared = true
				effect = "\"I'll ask her.\" She does, later, and it holds."

		Answer.RECONCILE:
			cleared = true
			effect = "\"...All right. Yes. That happens.\""

		Answer.BLAME_SYSTEM:
			# It is an answer about TIMESTAMPS. It used to clear anything of any
			# severity on its first use — a conflicting observation, a normal
			# result, an entire pattern — which made it a free pass out of the
			# worst question in the folder.
			if times == 0 and (f.kind == "backdated" or f.kind == "addendum_cascade"):
				cleared = true
				effect = "\"Hm. I'll raise it with IT.\""
			elif times == 0:
				effect = "\"The clocks have nothing to do with this one.\""
			else:
				# The same excuse twice is not an excuse, it is a pattern.
				var g := Contradictions.Finding.new()
				g.kind = "story_shifting"
				g.axis = "how you are explaining this"
				g.severity = 0.60 + 0.2 * float(times)
				g.question = "That is the second time you've blamed the clocks."
				g.because = "The same excuse was used %d times in one conversation." % (times + 1)
				extra.append(g)
				effect = "She stops writing."

	if cleared:
		resolved.append(f)
	transcript.append({
		"kind": f.kind, "question": f.question, "answer": choice,
		"effect": effect, "cleared": cleared, "because": f.because,
		"severity": f.severity,
	})
	return {"cleared": cleared, "effect": effect}

## What is left standing when she closes the folder.
func outcome() -> Dictionary:
	var unresolved := 0.0
	var worst = null
	for f in findings:
		if resolved.has(f):
			continue
		unresolved += f.severity
		if worst == null or f.severity > worst.severity:
			worst = f
	for g in extra:
		unresolved += g.severity
		if worst == null or g.severity > worst.severity:
			worst = g
	var verdict := OUTCOME_CLEAR
	if unresolved > 2.5:
		verdict = OUTCOME_ESCALATED
	elif unresolved > 1.4:
		verdict = OUTCOME_FLAGGED
	elif unresolved > 0.6:
		verdict = OUTCOME_QUESTIONS
	return {
		"verdict": verdict,
		"unresolved": unresolved,
		"worst": worst,
		# THE CAUSAL CHAIN, so a bad morning is never mysterious.
		"because": worst.because if worst != null else "Nothing in the folder disagreed with itself.",
		"transcript": transcript,
		"created": extra.size(),
	}

## Her closing line. Written to tell the player what happened, not to score them.
static func closing(verdict: String) -> String:
	match verdict:
		OUTCOME_CLEAR:
			return "\"Fine. Go home, you look dreadful.\""
		OUTCOME_QUESTIONS:
			return "\"I've made a note. It's probably nothing.\""
		OUTCOME_FLAGGED:
			return "\"I'm going to have coding look at this one. Nothing personal.\""
		OUTCOME_ESCALATED:
			return "\"I'd like you to put all of that in writing, please. Today.\""
	return ""
