class_name Contradictions
extends RefCounted
## The reviewer's entire brain, and the thing the whole redesign is betting on.
##
## There is no suspicion die. A question gets asked because two specific pieces
## of the world cannot both be true, and the player can read the same chart the
## reviewer reads. Getting caught is therefore always explicable after the fact:
## THIS entry against THAT observation, at THIS time, seen by THAT person.
##
## THE HYPOTHESIS THIS FILE EXISTS TO TEST: that lies COMPOUND rather than
## merely accumulate. The mechanism is deliberate and threefold —
##
##   1. Every fix is itself an entry, so patching a hole digs a new one.
##   2. Severity is raised for entries that already appear in another finding,
##      so the second question about the same line is worse than the first.
##   3. A stay has to be justified AT THE MOMENT IT IS BILLED. An addendum that
##      says the patient was fine by nine o'clock does not just sit there: it
##      retroactively removes the reason they were still in the bed at ten.
##
## If those three do not produce escalation in play, the design is wrong and the
## document gets changed, not the measurements.
##
## REBALANCED AFTER THE FIRST MEASUREMENT. The initial severities made a single
## fabricated note produce three findings at maximum severity, which meant there
## was no such thing as a small lie and nothing to escalate from — the second
## and third steps of a deception added literally nothing because everything had
## already saturated. Wards run on discrepancies; one is ordinary, and the game
## is only interesting if a player can tell a small lie and live with it. The
## numbers now treat a lone disagreement as noise and let the PATTERN convict.

class Finding extends RefCounted:
	var kind: String = ""
	var patient_id: String = ""
	var entries: PackedStringArray = PackedStringArray()
	var severity: float = 0.0
	var axis: String = ""        ## what the reviewer was looking at when she found it
	var question: String = ""    ## what she actually says
	var because: String = ""     ## the causal line, for the player, afterwards
	var compounded := 0          ## how many other findings share an entry with this

	func label() -> String:
		return "%s (%.2f)" % [kind, severity]

# ---------------------------------------------------------------- detection
## `truth` maps patient_id -> {well: bool, held: bool, patient_recalls: Array[String]}
## `placements` maps "actor|minute_bucket" -> room, from what witnesses saw.
## Eight in the morning. `WardDay.minute` starts here, so an entry written
## before it belongs to a shift that is not yours.
const SHIFT_START := 8 * 60

static func find_all(entries: Array, truth: Dictionary, placements: Dictionary) -> Array:
	var out: Array = []
	var by_patient := {}
	for e in entries:
		var pid: String = e.patient_id
		if not by_patient.has(pid):
			by_patient[pid] = []
		by_patient[pid].append(e)

	for pid in by_patient:
		var list: Array = by_patient[pid]
		list.sort_custom(func(a, b): return a.stated_minute < b.stated_minute)
		var t: Dictionary = truth.get(pid, {})
		out.append_array(_conflicting_observations(pid, list))
		out.append_array(_backdating(pid, list))
		out.append_array(_author_elsewhere(pid, list, placements))
		out.append_array(_patient_no_recall(pid, list, t))
		out.append_array(_symptom_was_suggested(pid, list, t))
		out.append_array(_grateful_witness(pid, list, t))
		out.append_array(_family_read_it(pid, list, t))
		out.append_array(_social_hold_is_a_lie(pid, list, t))
		out.append_array(_unfulfilled_orders(pid, list))
		out.append_array(_objective_refutes(pid, list))
		if bool(t.get("held", false)):
			# NOT for somebody you are keeping BECAUSE they bounced. Their file
			# is flagged by construction, which made `already_being_looked_at`
			# fire unconditionally at 0.98 on any held readmission — and that
			# kind is checked before `backed`, so BACKED was unreachable for a
			# readmitted bed however you documented it. The mechanic built as
			# the consequence of harming somebody took a third of your licence
			# for putting it right.
			if not bool(t.get("bounced_back", false)):
				out.append_array(_already_being_looked_at(pid, t))
			out.append_array(_no_reason_recorded(pid, list))
			out.append_array(_justification_undermined(pid, list))
			out.append_array(_uncorroborated_stay(pid, list, t))
		out.append_array(_reversed_a_colleague(pid, list, t))
		out.append_array(_written_in_front_of_them(pid, list, t))
		out.append_array(_reads_own_chart(pid, list, t))
		out.append_array(_they_asked_you_to(pid, list, t))
		out.append_array(_addendum_cascade(pid, list))
		out.append_array(_leaned_on_last_night(pid, list, t))

	# The other half of the ledger. Everything above asks whether a bed you
	# BILLED was defensible; this asks whether a bed you emptied was.
	out.append_array(_sent_home_unwell(by_patient, truth))
	out.append_array(_never_laid_eyes_on_them(truth))
	out.append_array(_they_came_back(truth))

	out.append_array(pattern_findings(entries, truth))
	# A file already marked for review is read by somebody whose eyes are open.
	# The player can find this out; it is written on the record. They have to go
	# and look, which is the only reason the flag is interesting.
	for f in out:
		if f.patient_id != "" and bool(truth.get(f.patient_id, {}).get("flagged", false)):
			f.severity = minf(0.98, f.severity * 1.6)
			f.axis = "%s (file already under review)" % f.axis

	# AND SO IS A DOCTOR. The fourth time she raises the same kind of thing with
	# the same person, it stops being a discrepancy and starts being a habit —
	# and unlike a note on a patient's file, this survives the ward changing
	# overnight, which is the only reason it works at all.
	var rec := DoctorRecord.load_from_state()
	for f in out:
		var w := rec.weight_for(f.kind)
		if w > 1.0:
			f.severity = minf(0.98, f.severity * w)
			f.axis = "%s (and not for the first time)" % f.axis
	_compound(out)
	out.sort_custom(func(a, b): return a.severity > b.severity)
	return out

## YOU SENT SOMEBODY HOME WHO WAS NOT WELL.
##
## THE HOLE THIS CLOSES: for three iterations the reviewer only ever asked about
## beds you KEPT. Every finding in this file was a question about billing, so the
## game punished greed and was completely indifferent to haste — and the fastest
## way to a clean review was to empty the ward, which is the one thing a doctor
## must not do. A day is a set of decisions about people, and half of those
## decisions were unexamined.
##
## Three ways she can know, in ascending order of how badly it reads:
##
##   1. The chart says so. Somebody wrote UNWELL and nobody wrote anything
##      after it, and you sent them home regardless.
##   2. A colleague said so. You asked for an opinion, got "not safe to go
##      today", and went ahead — which is worse than never asking.
##   3. You examined them. You were at the bedside, you found it, and nobody
##      needs a document to establish that you knew.
static func _sent_home_unwell(by_patient: Dictionary, truth: Dictionary) -> Array:
	var out: Array = []
	for pid in by_patient:
		var t: Dictionary = truth.get(pid, {})
		if bool(t.get("held", false)) or not t.get("discharged", false):
			continue
		if bool(t.get("well", true)):
			continue          ## they were fine. Sending them home was correct.
		var list: Array = by_patient[pid]
		# The last word on the chart about whether they could go.
		var last_stay = null
		var last_go = null
		for e in list:
			if e.supports_stay():
				last_stay = e
			elif e.supports_discharge():
				last_go = e
		var examined: bool = bool(t.get("examined", false))
		var peer = null
		for e in list:
			if e.author == ChartEntry.Author.DOCTOR and e.supports_stay():
				peer = e
		var documented: bool = last_stay != null and (
			last_go == null or last_stay.stated_minute > last_go.stated_minute)

		# A LADDER, NOT A GATE.
		#
		# This used to `continue` unless one of the three was true — and all
		# three are things the PLAYER does. So the way to make a wrongful
		# discharge invisible was to never read the chart, never examine
		# anybody and never ask: information had strictly negative expected
		# value, because looking at a patient was the only way to manufacture
		# the evidence that convicted you of the decision you then made. Peter
		# Lomax, the man the second ward is built around, was SAFEST for a
		# player who never went near him.
		#
		# Sending somebody home who was not fit to go is a finding either way.
		# What the three routes decide is how badly it reads.
		var f := Finding.new()
		f.kind = "sent_home_unwell"
		f.patient_id = pid
		f.axis = "the bed you emptied"
		if peer != null:
			f.entries = PackedStringArray([peer.id])
			f.severity = 0.85
			# NOT "He". `peer.author_id` is whoever wrote the entry, and on
			# this ward that is as often Adeyemi as the registrar.
			f.question = ("You asked %s to review %s, and the answer came back: "
				+ "not today. They went home at teatime.") % [peer.author_id, _who(t)]
			f.because = "You obtained an opinion that they were not fit to go, and discharged them anyway."
		elif examined:
			f.entries = PackedStringArray([last_stay.id]) if last_stay != null \
				else PackedStringArray()
			f.severity = 0.72
			f.question = "You examined %s yourself. Then you sent them home. Talk me through it." % _who(t)
			f.because = "You were at the bedside, you found what was there, and you discharged them."
		elif documented:
			f.entries = PackedStringArray([last_stay.id])
			f.severity = 0.58
			f.question = ("The last thing anybody wrote about %s is %s. "
				+ "Nothing after it. And they went home.") % [_who(t), _short(last_stay)]
			f.because = "The final entry on the chart said they were unwell, and nobody wrote anything else."
		else:
			# NOBODY LOOKED. Not a defence — the softest rung on the ladder.
			f.severity = 0.55
			f.question = ("%s came back within the day. Who saw them before they "
				+ "went? I can't find anybody.") % _who(t)
			f.because = ("Nobody examined them, nobody was asked, and there is "
				+ "nothing on the chart either way. They went home on nothing.")
		out.append(f)
	return out

## YOU DECIDED ABOUT SOMEBODY YOU NEVER WENT NEAR.
##
## The other half of closing the wilful-blindness hole. Every finding in this
## file is about a document, so a player who produced no documents produced no
## findings — and the fastest clean handover in the game was to walk in at five
## past eight, empty the ward without opening anything, and go home. The ward
## sister does not need a contradiction to ask why you signed off five people
## you never saw.
static func _never_laid_eyes_on_them(truth: Dictionary) -> Array:
	var out: Array = []
	var blind: Array = []
	for pid in truth:
		var t: Dictionary = truth[pid]
		if not bool(t.get("held", false)) and not bool(t.get("discharged", false)):
			continue
		if bool(t.get("self_discharged", false)):
			continue
		if bool(t.get("examined", false)) or bool(t.get("looked_at", false)):
			continue
		blind.append(pid)
	# One or two on a busy shift is a busy shift. Three is how you spent the day.
	if blind.size() < 3:
		return out
	var f := Finding.new()
	f.kind = "never_laid_eyes_on_them"
	f.patient_id = String(blind[0])
	f.axis = "what you actually did"
	f.severity = clampf(0.30 + 0.16 * float(blind.size()), 0.30, 0.90)
	f.question = ("You made a decision about %d of the five and I can't find "
		+ "that you looked at any of them. What did you do all day?") % blind.size()
	f.because = ("%d beds were decided by somebody who never examined the "
		+ "patient, asked the nurse, or opened the chart.") % blind.size()
	out.append(f)
	return out

## THEY CAME BACK.
##
## The one finding in this file the PLAYER did not author. Everything else is a
## question about something somebody wrote; this is a question about a man in a
## bed. It is ungated on purpose — no amount of not-looking makes it go away,
## which is what stops "know nothing, decide anyway" being a strategy.
static func _they_came_back(truth: Dictionary) -> Array:
	var out: Array = []
	for pid in truth:
		var t: Dictionary = truth[pid]
		if not bool(t.get("bounced_back", false)):
			continue
		var f := Finding.new()
		f.kind = "readmitted_after_your_discharge"
		f.patient_id = pid
		f.axis = "what happened to them"
		f.severity = 0.80
		# TWO DIFFERENT CONVERSATIONS. Keeping the person you got wrong and
		# sending them home a second time are not the same act, and she read
		# them out identically.
		if bool(t.get("held", false)):
			f.question = Cases.about(pid,
				"%s was back in that bed before the night staff went home. You "
				+ "signed the discharge yourself. What is different today?") % _who(t)
			f.because = ("You discharged them, they were readmitted within the "
				+ "day, and you kept them the second time.")
		else:
			f.severity = 0.92
			f.question = Cases.about(pid,
				"%s came back in the night and you have sent {them} home "
				+ "again. Talk me through the second one.") % _who(t)
			f.because = ("You discharged them, they were readmitted within the "
				+ "day, and you discharged them again.")
		out.append(f)
	return out

static func _who(t: Dictionary) -> String:
	return String(t.get("name", "them"))

## Two entries about the same half hour that argue opposite ways.
static func _conflicting_observations(pid: String, list: Array) -> Array:
	var out: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a = list[i]
			var b = list[j]
			if not a.concerns_same_moment_as(b):
				continue
			if not ((a.supports_stay() and b.supports_discharge())
					or (a.supports_discharge() and b.supports_stay())):
				continue
			var invited: bool = a.at_your_request or b.at_your_request
			var f := Finding.new()
			f.kind = "invited_contradiction" if invited else "conflicting_observations"
			f.patient_id = pid
			f.entries = PackedStringArray([a.id, b.id])
			f.axis = "the timeline"
			# Two people disagreeing is worse than one person disagreeing with
			# themselves — a second author is a second memory to manage.
			f.severity = 0.45 if a.author != b.author else 0.30
			if invited:
				# You sent her. She looked. She wrote the opposite of what you
				# needed, and you kept him anyway.
				f.severity = 0.60
				f.question = Cases.about(f.patient_id,
					"You asked Adeyemi to review {them} and she came back with "
					+ "%s. You kept {them} in regardless. Why ask?") % _short(
						b if b.at_your_request else a)
				f.because = ("You requested a second opinion, got one that "
					+ "disagreed with you, and billed the night anyway.")
				out.append(f)
				continue
			f.question = "You've got %s at %s. %s has %s at %s. Walk me through that." % [
				_short(a), ChartEntry._hhmm(a.stated_minute),
				b.author_label().capitalize(), _short(b),
				ChartEntry._hhmm(b.stated_minute)]
			f.because = "%s and %s describe the same half hour and disagree." % [
				_short(a), _short(b)]
			out.append(f)
	return out

## Written long after the moment it describes.
static func _backdating(pid: String, list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e.author != ChartEntry.Author.YOU or not e.is_backdated():
			continue
		var late: int = e.backdated_by()
		var f := Finding.new()
		f.kind = "backdated"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "entry metadata"
		# Twenty minutes late is a busy shift. Two hours late is a document
		# written about a moment nobody was present for, and the clamp at 0.45
		# meant those were very nearly the same number.
		f.severity = clampf(0.10 + float(late) / 240.0, 0.10, 0.90)
		f.question = "This note is timed %s but you wrote it at %s. Why the gap?" % [
			ChartEntry._hhmm(e.stated_minute), ChartEntry._hhmm(e.written_minute)]
		f.because = "%s was written %d minutes after it says it happened." % [_short(e), late]
		out.append(f)
	return out

## You cannot have observed it from another room.
static func _author_elsewhere(pid: String, list: Array, placements: Dictionary) -> Array:
	var out: Array = []
	for e in list:
		if e.author != ChartEntry.Author.YOU:
			continue
		var key := "player|%d" % int(e.stated_minute / 15)
		if not placements.has(key):
			continue
		var seen_in: String = String(placements[key].get("room", ""))
		var expected: String = String(placements[key].get("expected", ""))
		if seen_in == "" or seen_in == expected:
			continue
		var f := Finding.new()
		f.kind = "author_elsewhere"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "who was where"
		f.severity = 0.70
		f.question = "You say you saw this at %s. %s puts you in %s at %s." % [
			ChartEntry._hhmm(e.stated_minute),
			String(placements[key].get("witness", "somebody")), seen_in,
			ChartEntry._hhmm(e.stated_minute)]
		f.because = "A witness placed you in %s when %s says you were at the bedside." % [
			seen_in, _short(e)]
		out.append(f)
	return out

## "Patient reports" — from a patient with no memory of reporting it.
static func _patient_no_recall(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	var recalls: Array = t.get("patient_recalls", [])
	for e in list:
		if e.author != ChartEntry.Author.PATIENT:
			continue
		if recalls.has(e.id):
			continue
		var f := Finding.new()
		f.kind = "patient_no_recall"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "what the patient says"
		f.severity = 0.45
		f.question = "The note says the patient reported this. He doesn't remember saying it."
		f.because = "%s is attributed to the patient and the patient has no memory of it." % _short(e)
		out.append(f)
	return out

## "Patient reports" — from a patient who remembers being asked leading questions
## until he reported it.
##
## Without this, putting a symptom into a suggestible patient's mouth was free
## money: the entry is authored by the PATIENT, so it never counted as your
## uncorroborated word, and if he remembered saying it there was nothing to find
## at all. It made the highest-paying play in the game also the safest one.
##
## The trade it creates is the good one. Agreeing and remembering are separate
## rolls, so the person easiest to lead is the person least likely to recall it
## — and on this ward that is an eighty-one-year-old on state funding who is
## worth almost nothing to keep. The patient you can most easily use is the one
## it is least worth using.
static func _symptom_was_suggested(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	var suggested: Array = t.get("patient_suggested", [])
	for e in list:
		if e.author != ChartEntry.Author.PATIENT or not suggested.has(e.id):
			continue
		var f := Finding.new()
		f.kind = "symptom_was_suggested"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "where the symptom came from"
		f.severity = 0.55
		f.question = ("He says you asked him about it. Several times. Did he "
			+ "volunteer this, or did you go looking for it?")
		f.because = ("The patient remembers being asked about the symptom before "
			+ "he ever reported it.")
		out.append(f)
	return out

## GRATITUDE IS TESTIMONY.
##
## Sam Oduya is frightened, wants to stay, and will tell anybody who asks how
## thorough his doctor was. That reads as the safest patient on the ward and it
## is the opposite: an enthusiastic witness gives a DETAILED account, and the
## detail includes how many times you asked him whether he felt faint. The
## patients who resent you say nothing useful. The one who likes you describes
## the whole conversation.
static func _grateful_witness(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("tells_everyone", false)) or not bool(t.get("held", false)):
		return out
	if not bool(t.get("was_asked", false)):
		return out
	var f := Finding.new()
	f.kind = "grateful_witness"
	f.patient_id = pid
	f.axis = "what the patient told me himself"
	f.severity = 0.50
	f.question = ("He was very complimentary about you. He also told me, without "
		+ "my asking, how many times you brought up feeling faint.")
	f.because = ("The patient volunteered a detailed account of the conversation, "
		+ "because he was grateful.")
	out.append(f)
	return out

## SOMEBODY'S DAUGHTER USED TO DO THIS JOB.
##
## Ruth Kerrigan was a ward sister for thirty years and reads her mother's chart
## the way she read charts for all of them. She is the only person in the
## building who looks at the notes without being asked, and unlike the reviewer
## she is there AT SEVEN, while the day is still going on — so what she sees is
## whatever the chart said before you had a chance to tidy it.
##
## She does not need a contradiction either. She has looked after enough old
## women to know what an eighty-one-year-old is doing in a bed on a Tuesday.
static func _family_read_it(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("family_reads_charts", false)) or not bool(t.get("held", false)):
		return out
	var reason_before_seven := false
	for e in list:
		if e.supports_stay() and e.stated_minute <= 19 * 60:
			reason_before_seven = true
	# WHOSE FAMILY. Written for Ruth Kerrigan and hardcoded to her, which was
	# fine while she was the only relative in the game; the second ward has a
	# solicitor reading her father's notes and the reviewer was calling her Mrs
	# Kerrigan's daughter.
	var who := String(t.get("family", "The family"))
	var note := String(t.get("family_note", "They read every line."))
	var f := Finding.new()
	f.kind = "family_read_it"
	f.patient_id = pid
	f.axis = "what the family were told"
	f.severity = 0.40 if reason_before_seven else 0.75
	if reason_before_seven:
		f.question = ("%s rang me. They'd read the notes and wanted to know "
			+ "how long. Did you speak to them?") % who
		f.because = "%s read the chart and followed it up." % who
	else:
		f.question = Cases.about(f.patient_id,
			"%s read the notes and there was nothing in them about keeping "
			+ "{them} in. %s") % [who, note]
		f.because = ("%s read the chart before there was any reason written in "
			+ "it. %s") % [who, note]
	out.append(f)
	return out

## SHE ASKED YOU TO.
##
## THE SHARPEST SQUARE ON THE BOARD, and the one the game has been circling
## since the first redesign. Rosalind Fry is well, she is the best-paying bed
## on her ward, she asks you outright to keep her in, and she will agree to any
## symptom you put to her. Everything about it is easy.
##
## And consent is not a defence, because the person consenting is the person
## who tells the ward sister about it in the morning. She is grateful, she is
## specific, and she has no idea she is describing a fraud.
static func _they_asked_you_to(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("asks_to_stay", false)) or not bool(t.get("held", false)):
		return out
	var yours = null
	for e in list:
		if e.author == ChartEntry.Author.YOU and e.supports_stay():
			yours = e
	if yours == null:
		return out
	var f := Finding.new()
	f.kind = "they_asked_you_to"
	f.patient_id = pid
	f.entries = PackedStringArray([yours.id])
	f.axis = "who wanted this"
	f.severity = 0.72
	f.question = Cases.about(pid,
		"%s told me {they}'d asked you to keep {them} in. {They} {were} very "
		+ "warm about it. Is that what this note is?") % _who(t)
	f.because = Cases.about(pid,
		"{They} asked you to, you wrote it down as a symptom, and {they} told "
		+ "the ward sister that {they} had asked.")
	out.append(f)
	return out

## THEY READ THEIR OWN NOTES.
##
## Winifred Blake's trap was a flag on a file, and the player finds it by opening
## the record. Imelda Voss is the same trap turned inside out: there is nothing
## on her file at all, and the danger is the woman in the bed, who spent
## forty-one years reading exactly these documents and reads this one every
## evening. She does not need a contradiction and she does not need the reviewer
## to find one. She simply knows what was in her chart yesterday and what is in
## it now.
static func _reads_own_chart(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("reads_own_chart", false)):
		return out
	var yours = null
	for e in list:
		if e.author == ChartEntry.Author.YOU and e.supports_stay():
			yours = e
	if yours == null:
		return out
	var f := Finding.new()
	f.kind = "reads_own_chart"
	f.patient_id = pid
	f.entries = PackedStringArray([yours.id])
	f.axis = "what the patient read"
	# Worse if she was in a position to watch you type it.
	var watched: bool = not yours.seen_by.is_empty()
	f.severity = 0.80 if watched else 0.66
	if watched:
		f.question = Cases.about(pid,
			"%s read what you wrote about {them}, in front of {them}, and asked "
			+ "me what the indication was. {They} had the wording.") % _who(t)
		f.because = Cases.about(pid,
			"{They} {v:read} {their} own chart every evening, and you "
			+ "typed that line standing where {they} could see the screen.")
	else:
		f.question = Cases.about(pid,
			"%s read {their} own notes last night. {They} wanted to know who "
			+ "had observed %s, because nobody had been near {them}.") % [
			_who(t), _short(yours)]
		f.because = Cases.about(pid,
			"{They} {v:read} {their} own chart, and {they} {v:remember} "
			+ "what was not in it yesterday.")
	out.append(f)
	return out

## "No care at home" about somebody with a home to go to.
##
## The honest use of this claim is the only way to keep a bed without inventing
## a symptom, and it pays almost nothing — which is the point. Used on anybody
## else it is the easiest lie in the game to check, because the ward already
## knows who is being collected and by whom.
static func _social_hold_is_a_lie(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if bool(t.get("no_care_at_home", false)):
		return out
	for e in list:
		if e.claim != ChartEntry.Claim.SOCIAL:
			continue
		var f := Finding.new()
		f.kind = "social_hold_is_a_lie"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "who is collecting them"
		f.severity = 0.65
		f.question = "You've got no care at home. Somebody rang for them at six. Who told you that?"
		f.because = "A social admission was recorded for a patient who has somewhere to go."
		out.append(f)
	return out

static func _unfulfilled_orders(pid: String, list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e.claim != ChartEntry.Claim.ORDER or e.fulfilled_by != "":
			continue
		var f := Finding.new()
		f.kind = "unfulfilled_order"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "orders against actions"
		f.severity = 0.30
		f.question = "You ordered %s and there's nothing to say it was ever done." % e.order_kind
		f.because = "%s was ordered and never carried out." % e.order_kind
		out.append(f)
	return out

## A machine found nothing, and you had written that something was there.
static func _objective_refutes(pid: String, list: Array) -> Array:
	var out: Array = []
	for r in list:
		if r.claim != ChartEntry.Claim.RESULT_NORMAL:
			continue
		for e in list:
			if not e.supports_stay() or e.author == ChartEntry.Author.MACHINE:
				continue
			if e.stated_minute > r.stated_minute:
				continue
			var f := Finding.new()
			f.kind = "objective_refutes"
			f.patient_id = pid
			f.entries = PackedStringArray([e.id, r.id])
			f.axis = "results against notes"
			f.severity = 0.55
			f.question = "You documented %s, then the %s came back clear. What changed?" % [
				_short(e), _short(r)]
			f.because = "An objective result contradicts %s, and a result cannot be talked to." % _short(e)
			out.append(f)
	return out

## THE COMPOUNDING ONE. If the last thing the record says about a held patient is
## that they were fine, then the record no longer explains why they were still in
## the bed when the night was billed. Patching a hole at nine o'clock removes the
## reason for the bed at ten.
static func _justification_undermined(pid: String, list: Array) -> Array:
	var out: Array = []
	var last_support = null
	var later_clear = null
	for e in list:
		if e.supports_stay():
			last_support = e
		# YOUR OWN later note, or a result you ordered — not a nurse's. Being
		# contradicted by a colleague is `conflicting_observations` and counting
		# it here as well was double jeopardy: a single fabricated line produced
		# three findings and there was no such thing as a small lie. THIS finding
		# is specifically about undermining YOURSELF, which is the compounding
		# mechanic the whole design rests on.
		elif e.supports_discharge() and last_support != null \
				and e.stated_minute > last_support.stated_minute \
				and (e.author == ChartEntry.Author.YOU
					or e.author == ChartEntry.Author.MACHINE):
			later_clear = e
	if last_support == null or later_clear == null:
		return out
	var f := Finding.new()
	f.kind = "justification_undermined"
	f.patient_id = pid
	f.entries = PackedStringArray([last_support.id, later_clear.id])
	f.axis = "why they were still here"
	f.severity = 0.60
	f.question = ("If %s by %s, why was the bed still occupied at ten?"
		% [_short(later_clear), ChartEntry._hhmm(later_clear.stated_minute)])
	f.because = ("The chart says the problem had resolved by %s, which leaves the "
		+ "night with nothing holding it up.") % ChartEntry._hhmm(later_clear.stated_minute)
	out.append(f)
	return out

## A BED WAS BILLED AND THE CHART SAYS NOTHING AT ALL.
##
## The simplest possible check, and it was missing, which made the cheapest
## exploit in the game invisible: keep somebody in, write nothing down, and
## there was no entry for anything else to disagree with. Twenty measured
## playthroughs found it — asking a frightened man a leading question, having
## him decline, and keeping him anyway produced the highest cash in the set with
## a completely silent review.
##
## This is also the one finding a reviewer would notice from the corridor. She
## does not need a contradiction; she needs a reason, and there isn't one.
## THE FILE THAT WAS ALREADY OPEN.
##
## Winifred Blake's record carries a coding query from three weeks before the
## player started, and it is written on her chart and nowhere else. Multiplying
## her other findings by 1.6 was not enough to make the authored trap do
## anything: one 0.25 finding became 0.40, which is under every threshold, so
## the patient designed to look free actually WAS free. Holding somebody whose
## file is already with the insurer is its own problem, and it does not need a
## contradiction to be one.
static func _already_being_looked_at(pid: String, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("flagged", false)):
		return out
	var f := Finding.new()
	f.kind = "already_being_looked_at"
	f.patient_id = pid
	f.axis = "a file the insurer had already queried"
	f.severity = 0.70
	f.question = ("Of all of them, you kept the one Meridian already had a coding "
		+ "query open on. Did you read her file?")
	f.because = ("Her record was flagged for review before you started, and you "
		+ "billed another night on it.")
	out.append(f)
	return out

static func _no_reason_recorded(pid: String, list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e.supports_stay():
			return out
	var f := Finding.new()
	f.kind = "no_reason_recorded"
	f.patient_id = pid
	f.axis = "why they were still here"
	f.severity = 0.70
	f.question = "There is nothing in these notes explaining why this bed was occupied. Was there a reason?"
	f.because = "The night was billed and the chart offers no clinical reason for it at all."
	out.append(f)
	return out

## Your word, alone, against somebody else's routine observation.
## YOU WROTE IT IN THE ROOM, AND THE ROOM WAS FULL.
##
## THE REASON THIS GAME IS IN FIRST PERSON. `seen_by` was recorded on every
## entry and read by nothing, so which terminal you walked to made no difference
## to anything — the ward's "in full view of the ward" and the office's "door's
## shut, nobody's looking" were two pieces of flavour text describing the same
## act. A note claiming somebody is unwell, typed where they could see you type
## it, about somebody who is not, is a note the reviewer can check by walking
## four metres and asking them. Going somewhere private to write it is the crime
## the game is about, and it costs the minutes it takes to get there and back.
static func _written_in_front_of_them(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if bool(t.get("well", true)) == false:
		return out            ## it is true, so it does not matter who saw it
	# ...and neither is "nowhere to go tonight" about somebody with nowhere to
	# go. This used the BODY as a proxy for whether the note was a lie, so the
	# one honest act of kindness in the game — Dot Kerrigan's social hold —
	# became an indefensible bed the moment anybody was in the room while you
	# typed it. The other two detectors already carry this exemption.
	var only_social := true
	for e in list:
		if e.author == ChartEntry.Author.YOU and e.supports_stay() \
				and e.claim != ChartEntry.Claim.SOCIAL:
			only_social = false
	if only_social and bool(t.get("no_care_at_home", false)):
		return out
	var who := String(t.get("name", ""))
	for e in list:
		if e.author != ChartEntry.Author.YOU or not e.supports_stay():
			continue
		if e.seen_by.is_empty():
			continue
		var by_the_patient: bool = who != "" and Array(e.seen_by).has(who)
		var f := Finding.new()
		f.kind = "written_in_front_of_them"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id])
		f.axis = "who was in the room"
		f.severity = 0.62 if by_the_patient else 0.34
		if by_the_patient:
			f.question = "You typed this standing at the bed. %s was awake. I asked." % who
			f.because = "%s watched you write it and says the conversation in it never happened." % who
		else:
			f.question = "%s were in the room while you wrote this up. None of them saw the examination." % \
				_and_list(e.seen_by)
			f.because = "The people who were in the room when you wrote %s did not see it happen." % _short(e)
		out.append(f)
	return out

static func _and_list(names: PackedStringArray) -> String:
	var a := Array(names)
	if a.size() == 1:
		return String(a[0])
	if a.size() == 2:
		return "%s and %s" % [a[0], a[1]]
	return "%s and %d others" % [a[0], a.size() - 1]

static func _uncorroborated_stay(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	# A social admission needs no corroborating observation — there is nothing
	# clinical to corroborate. Whether it is TRUE is a different question, and
	# `_social_hold_is_a_lie` asks it.
	for e in list:
		if e.claim == ChartEntry.Claim.SOCIAL and bool(t.get("no_care_at_home", false)):
			return out
	var mine := 0
	var theirs := 0
	var first_mine = null
	for e in list:
		if e.supports_stay():
			if e.author == ChartEntry.Author.YOU:
				mine += 1
				if first_mine == null:
					first_mine = e
			else:
				theirs += 1
	if mine == 0 or theirs > 0:
		return out
	var f := Finding.new()
	f.kind = "uncorroborated_stay"
	f.patient_id = pid
	f.entries = PackedStringArray([first_mine.id])
	f.axis = "who else saw it"
	f.severity = 0.25
	f.question = "Nobody but you ever saw this. Did you ask anyone to confirm it?"
	f.because = "Every note keeping this patient in was written by you and nobody else."
	out.append(f)
	return out

## An explanation that needed explaining. Each layer is thinner than the last.
static func _addendum_cascade(pid: String, list: Array) -> Array:
	var out: Array = []
	var depth := {}
	for e in list:
		if e.explains == "":
			continue
		depth[e.id] = int(depth.get(e.explains, 0)) + 1
		if int(depth[e.id]) < 2:
			continue
		var f := Finding.new()
		f.kind = "addendum_cascade"
		f.patient_id = pid
		f.entries = PackedStringArray([e.id, e.explains])
		f.axis = "the shape of the record"
		f.severity = 0.40 + 0.08 * float(depth[e.id])
		f.question = "There are three notes here all explaining each other. Which one is the observation?"
		f.because = "An addendum explaining an addendum — the record is arguing with itself."
		out.append(f)
	return out

# ---------------------------------------------------------------- compounding
## A line already in trouble gets worse when it turns up again. This is the
## difference between three separate awkward questions and one bad morning.
static func _compound(findings: Array) -> void:
	var seen := {}
	for f in findings:
		for eid in f.entries:
			seen[eid] = int(seen.get(eid, 0)) + 1
	for f in findings:
		var overlap := 0
		for eid in f.entries:
			overlap = maxi(overlap, int(seen.get(eid, 1)) - 1)
		f.compounded = overlap
		if overlap > 0:
			# Not additive: the second question about the same note is the one
			# that turns a discrepancy into a pattern.
			# Capped below certainty on purpose: no single line should ever be
			# fatal on its own. It is the ACCUMULATION across a patient that convicts.
			f.severity = minf(0.95, f.severity * (1.0 + 0.30 * float(overlap)))

## Somebody wrote a PLAN and you reversed it. Unlike an observation, a plan is
## not softened by the clock — Adeyemi said at nine in the morning that this man
## was going home, and at three in the afternoon you said he was not, and she is
## going to hear about it either way.
static func _reversed_a_colleague(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	for plan in list:
		if plan.claim != ChartEntry.Claim.FIT_FOR_DISCHARGE:
			continue
		for e in list:
			if not e.supports_stay() or e.author != ChartEntry.Author.YOU:
				continue
			# WRITTEN, not stated. Stating a time is free — the exploit was to
			# claim you saw him at eight o'clock, fifty minutes before Adeyemi
			# wrote her discharge plan, and the reversal simply did not register.
			# When you actually typed it is not yours to choose.
			if e.written_minute < plan.written_minute:
				continue
			var f := Finding.new()
			f.kind = "reversed_a_colleague"
			f.patient_id = pid
			f.entries = PackedStringArray([plan.id, e.id])
			f.axis = "who decided what"
			# A REGISTRAR'S PLAN IS NOT A NURSE'S PLAN. Adeyemi wrote down what
			# she found and what she expected to happen; Dr Costa was asked for
			# an opinion, gave one, and put his name on it. Overturning the
			# second one silently is the most expensive single act available,
			# and it is only available to somebody who went and asked for it.
			var peer: bool = plan.author == ChartEntry.Author.DOCTOR
			f.severity = 0.78 if peer else 0.55
			# AN EXAMINATION TODAY OUTRANKS AN OPINION FROM LAST NIGHT.
			#
			# The fourth ward could not reach a signed-off day in eleven hundred
			# strategies, and this was why: the one genuinely ill woman on it was
			# written up for discharge at twenty to seven by the night registrar,
			# so keeping her — which is the correct thing to do, and the whole
			# point of the ward — made her bed CONTRADICTED and the day FLAGGED,
			# while sending her home was a wrongful discharge. There was no
			# clean play, and no way for the player to find that out except by
			# never managing one.
			#
			# So: if you went to the bedside yourself and she is genuinely
			# unwell, this stops being a professional disagreement and becomes a
			# doctor doing the job. She still ASKS — the question is a good one
			# and you should have to answer it — but it no longer sinks the bed.
			#
			# Both halves are needed and neither is a gate on the player alone.
			# `examined` without `unwell` is somebody who looked and held a well
			# patient anyway, which is worse rather than better; `unwell` without
			# `examined` is being right by luck, and luck does not overrule a
			# named colleague. Kept deliberately below 0.40 even at the 2.2x
			# career weighting, so a doctor who is right about this four times
			# does not get convicted of being right about it four times.
			var justified: bool = bool(t.get("examined", false)) \
				and not bool(t.get("well", true))
			if justified:
				f.severity = 0.12
			var them := "them" if peer else "her"
			f.question = ("%s had %s down for home at %s. You've reversed that. "
				+ "Did you speak to %s?") % [
				plan.author_id, "him", ChartEntry._hhmm(plan.stated_minute), them]
			f.because = "%s's discharge plan was overturned in writing, by you, without %s." % [
				plan.author_id, them]
			if peer and not justified:
				f.because += " You asked for that opinion yourself."
			if justified:
				f.question = ("%s had %s down for home at %s and you have overturned "
					+ "it. I gather you went and looked yourself.") % [
					plan.author_id, "them",
					ChartEntry._hhmm(plan.stated_minute)]
				f.because = ("%s's plan was overturned by a doctor who examined the "
					+ "patient afterwards and found them unwell. The plan was wrong.") \
					% plan.author_id
			out.append(f)
	return out

## THE SHIFT STARTS AT EIGHT AND SO DOES YOUR RESPONSIBILITY.
##
## The fourth ward is built on decisions somebody else already made, and it
## opened a hole the first three could not: a bed whose only support is an entry
## written BEFORE your shift, by a doctor who has gone home. Hold it and you have
## written nothing, led nobody, asked nobody — so `_no_clinical_reason` sees a
## supporting entry and stays quiet, `_reads_own_chart` and `_grateful_witness`
## both key on something YOU wrote and stay quiet, and `_reversed_a_colleague`
## is about overturning a peer rather than sheltering behind one. A well patient
## on a premium bed with a stale note in the file was a free crime, which is the
## one thing this game is not allowed to contain.
##
## The fiction is exactly the mechanic: the night registrar's four-twenty
## opinion is not an observation of today, and the person who wrote it cannot be
## asked about it, because he is asleep. Leaning on it is not a lie — it is the
## absence of a decision, which is why it is graded lower than a fabrication and
## why writing your own note makes it stop. It is a prompt to do the job rather
## than a punishment for doing it.
##
## Graded on whether they turned out to need the bed: 0.66 if today says they
## are well and you billed the night anyway, 0.28 if they genuinely needed it
## and you were right by luck. Luck is not free and it is not a crime either.
static func _leaned_on_last_night(pid: String, list: Array, t: Dictionary) -> Array:
	var out: Array = []
	if not bool(t.get("held", false)):
		return out
	# Nowhere safe to go tonight is a reason that does not expire overnight, and
	# the other detectors on this ward already carry the same exemption.
	if bool(t.get("no_care_at_home", false)):
		return out
	# AND IF YOU WENT AND LOOKED, YOU DID NOT LEAN ON ANYTHING.
	#
	# The first version of this had no such exemption, and the frontier probe
	# caught it in one run: Adeyemi writes her handover note at twenty past
	# seven, forty minutes before the shift starts, so the ONE unmistakably ill
	# man on the fourth ward — nurse's note and all — produced a finding for
	# being kept in. Ward four could not reach a signed-off day in eleven hundred
	# strategies, which would have made honest play impossible on a quarter of
	# the game.
	#
	# The question this finding asks out loud is "did you see this patient at
	# all". If the answer is yes — you examined them, read them, sent somebody,
	# asked them — then it is answered and there is nothing to raise. Punishing a
	# player who looked would be the exact inversion the career rework exists to
	# prevent, wearing last night's clothes.
	if bool(t.get("looked_at", false)):
		return out
	var newest = null
	for e in list:
		if not e.supports_stay():
			continue
		if newest == null or e.written_minute > newest.written_minute:
			newest = e
	if newest == null:
		return out            ## nothing supports it at all — a different finding
	if newest.written_minute >= SHIFT_START:
		return out            ## somebody put their name to it today
	var f := Finding.new()
	f.kind = "leaned_on_last_night"
	f.patient_id = pid
	f.entries = PackedStringArray([newest.id])
	f.axis = "who was on when that was written"
	var well: bool = bool(t.get("well", true))
	f.severity = 0.66 if well else 0.28
	var who := String(newest.author_id) if String(newest.author_id) != "" else "the night staff"
	f.question = ("The only thing holding this bed was written at %s, by %s, "
		+ "before you came on. Did you see this patient at all?") % [
		ChartEntry._hhmm(newest.written_minute), who]
	f.because = ("The night was billed on an entry written at %s by somebody who "
		+ "had gone home before the shift started, and nothing was added to it "
		+ "all day.") % ChartEntry._hhmm(newest.written_minute)
	out.append(f)
	return out

## THE INSTITUTION NOTICING THE DOCTOR, rather than the note.
##
## Any single well-timed fabrication is survivable and should be. What is not
## survivable is the shape of a day in which several people stayed and the only
## person who ever saw a reason was you. Without this, the money-optimal play —
## hold three, write two careful notes in the gaps between rounds — was also the
## safest play in the game, which made it a dominant strategy and no decision at
## all.
static func pattern_findings(entries: Array, truth: Dictionary) -> Array:
	var out: Array = []
	var solo_holds: Array = []
	for pid in truth:
		if not bool(truth[pid].get("held", false)):
			continue
		var mine := false
		var anyone_else := false
		for e in entries:
			if e.patient_id != pid or not e.supports_stay():
				continue
			if e.author == ChartEntry.Author.YOU:
				mine = true
			else:
				anyone_else = true
		if mine and not anyone_else:
			solo_holds.append(pid)
	if solo_holds.size() < 2:
		return out
	var f := Finding.new()
	f.kind = "pattern_of_holds"
	f.patient_id = ""
	f.axis = "the shape of your day"
	f.severity = clampf(0.35 * float(solo_holds.size()), 0.35, 1.0)
	f.question = ("%d of them stayed last night and in every case the only person "
		+ "who saw a reason was you. Is that a fair summary?") % solo_holds.size()
	f.because = ("%d patients were held on findings nobody but you ever recorded."
		% solo_holds.size())
	out.append(f)
	return out

# ======================================================================
# THE BED AUDIT — what replaced the severity sum.
#
# For three iterations the verdict was a float: add up every finding, compare
# against four thresholds. It was gamed three times running, and each fix built
# the next exploit. Killing "hold three and write two notes" made an EMPTY
# CHART the safest play in the game, because a chart with nothing in it has
# nothing to contradict. Adding `pattern_of_holds` to catch that was switched
# off by writing the note as PATIENT-authored instead. Rebalancing severities
# downward moved most findings into the band where standing by them is free.
#
# The flaw is structural, not numerical. A sum lets the player make findings
# NOT HAPPEN, and the cheapest way to make a finding not happen is to write
# nothing at all — which is the exact opposite of the game.
#
# So the reviewer no longer adds anything up. She goes bed by bed and asks one
# question about each: WHY WAS THIS BED OCCUPIED LAST NIGHT? A held bed cannot
# be made to disappear from that list, and an empty chart is not a way of
# dodging the question — it is the worst possible answer to it.
enum Defence {
	BACKED,        ## somebody other than you put a reason in the record
	SOLO,          ## your word, and only your word
	CONTRADICTED,  ## the record actively disagrees with the reason you gave
	NONE,          ## there is no reason in the record at all
}

class BedAudit extends RefCounted:
	var patient_id := ""
	var state: Defence = Defence.NONE
	var why := ""
	var findings: Array = []
	## True for a bed you KEPT and billed, false for one you emptied. The two
	## are audited by opposite questions — "what was the reason" against "what
	## did you have that said otherwise" — and the summary line the player reads
	## has to be able to tell them apart.
	var billed := true

	func indefensible() -> bool:
		return state == Defence.NONE or state == Defence.CONTRADICTED

## One verdict per DECIDED bed — kept or wrongly emptied. `findings` are the
## questions she has about it.
static func audit_beds(entries: Array, truth: Dictionary, findings: Array) -> Array:
	var out: Array = []
	for pid in truth:
		# EVERY DECISION, NOT EVERY BILL. A bed you emptied when the world said
		# otherwise is a decision she audits exactly as closely as a bed you
		# kept — and until it was, the fastest route to a clean handover was to
		# send the whole ward home, which is the single thing a doctor must not
		# do. The bed still has to have been DECIDED: somebody who walked out
		# on their own is not on your conscience.
		var t: Dictionary = truth[pid]
		var kept: bool = bool(t.get("held", false))
		var emptied_wrongly: bool = bool(t.get("discharged", false)) \
			and not bool(t.get("well", true)) \
			and not bool(t.get("self_discharged", false))
		if not kept and not emptied_wrongly:
			continue
		var a := BedAudit.new()
		a.patient_id = pid
		a.billed = kept
		for f in findings:
			if f.patient_id == pid:
				a.findings.append(f)

		var mine := false
		var backed := false
		var contradicted := false
		var recalls: Array = truth[pid].get("patient_recalls", [])
		for e in entries:
			if e.patient_id != pid or not e.supports_stay():
				continue
			match e.author:
				ChartEntry.Author.YOU:
					mine = true
				ChartEntry.Author.NURSE, ChartEntry.Author.MACHINE, ChartEntry.Author.DOCTOR:
					backed = true
				ChartEntry.Author.PATIENT:
					# Only if he would still say it in the morning. A symptom the
					# patient does not remember reporting is not corroboration,
					# it is a second thing to explain.
					if recalls.has(e.id):
						backed = true
					else:
						mine = true
		# AND `readmitted_after_your_discharge` IS NOT IN THAT LIST.
		#
		# It was, and this branch only ever runs for a bed you are KEEPING — so
		# holding the man who bounced back at one in the morning because you got
		# it wrong was automatically "the record disagrees with the reason
		# given", which is CONTRADICTED, which is at minimum FLAGGED and a
		# strike. Examine him, send the nurse, document it properly: same
		# verdict. Send him home AGAIN: same verdict. Putting right the one
		# mistake the whole readmission mechanic exists to make you feel was
		# worth precisely nothing, and the design comments on that mechanic say
		# the opposite in as many words.
		#
		# This is the identical bug the file already found and excluded three
		# hundred lines up, for `already_being_looked_at`, on the same bed, for
		# the same reason: a kind checked before `backed` makes BACKED
		# unreachable however well you document it.
		#
		# She still asks. The bounce is still on the record and it still costs —
		# what it cost was yesterday, as `sent_home_unwell`, on the night you
		# signed the discharge. Today's bed is judged on today's documents.
		for f in a.findings:
			# A symptom the patient says you put in his head is not corroboration,
			# and neither is a grateful man describing how many times you asked.
			# Both were counted as "somebody other than you recorded a reason",
			# which made leading a patient the safest documentation in the game.
			# A NOTE WRITTEN NINETY MINUTES AFTER THE FACT IS NOT A LATE NOTE.
			# `backdated` was not in this list at all, so the headline mechanic
			# of the whole game — the two timestamps — could not affect a single
			# verdict however far apart they were.
			if f.kind == "backdated" and f.severity >= 0.48:
				contradicted = true
			# A REVERSAL YOU CAN STAND UP IS NOT A CONTRADICTION. Graded, the
			# way `backdated` is, rather than listed — an overruled colleague
			# sinks the bed when you never went and looked, and does not when
			# you did. See `_reversed_a_colleague`.
			if f.kind == "reversed_a_colleague" and f.severity >= 0.40:
				contradicted = true
			if f.kind in ["objective_refutes", "justification_undermined",
					"conflicting_observations", "invited_contradiction",
					"social_hold_is_a_lie", "patient_no_recall",
					"symptom_was_suggested", "grateful_witness",
					"already_being_looked_at",
					"written_in_front_of_them", "reads_own_chart",
					"they_asked_you_to"]:
				contradicted = true

		# A DISCHARGE IS AUDITED THE OTHER WAY UP. There is no "reason for the
		# bed" to corroborate — the question is whether anything in the world
		# said they should have stayed, and whether you can show you looked.
		if not a.billed:
			var caught := false
			for f in a.findings:
				if f.kind == "sent_home_unwell":
					caught = true
			if caught:
				a.state = Defence.CONTRADICTED
				a.why = "they were not fit to go and you had been told so"
			elif bool(t.get("examined", false)) or bool(t.get("looked_at", false)):
				a.state = Defence.BACKED
				a.why = "you looked, and nothing said they should have stayed"
			else:
				# AN EMPTY RECORD IS YOUR WORD, NOT A COLLEAGUE'S. Stamping a
				# bed BACKED because nobody wrote anything about it rewarded
				# the player for producing no documents at all.
				a.state = Defence.SOLO
				a.why = "you sent them home without anybody looking at them"
			out.append(a)
			continue

		if contradicted:
			a.state = Defence.CONTRADICTED
			a.why = "the record disagrees with the reason given"
		elif backed:
			a.state = Defence.BACKED
			a.why = "somebody other than you recorded a reason"
		elif mine:
			a.state = Defence.SOLO
			a.why = "the only person who recorded a reason was you"
		else:
			a.state = Defence.NONE
			a.why = "no reason was recorded at all"
		out.append(a)
	return out

static func _short(e) -> String:
	return e.text if e.text.length() < 46 else e.text.substr(0, 43) + "..."
