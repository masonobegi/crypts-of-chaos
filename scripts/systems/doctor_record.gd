class_name DoctorRecord
extends RefCounted
## WHAT SHE REMEMBERS ABOUT YOU, as against what she remembers about a bed.
##
## The first version of this remembered BEDS: a stay the ward sister could not
## corroborate put a note on that patient's file, and the file was read harder
## the next day. It was measured, it worked, and it was completely dead in a
## career — because the wards alternate, so the patient whose file was marked is
## not on the ward tomorrow, and the flag was overwritten before they ever came
## back. A probe that played seven days found "lie once a night" clearing $850
## every night for a week at no rising cost at all.
##
## The thing that actually accumulates is the DOCTOR. Sister Nkemelu has now
## asked you about four beds nobody else ever saw; she does not need to remember
## which four. This is a handful of counters that never reset, and everything
## about the escalation reads off them:
##
##   - her opening line, which stops being polite
##   - the weight of a finding of a kind she has raised before
##   - whether she is prepared to hear the same excuse again
##   - and, at three referrals, whether you are still a doctor
##
## Stored in GameState flags rather than as a node, because it has to survive a
## save, a roster change and the ward being rebuilt from scratch every morning.

const FLAG := "doctor_record"

## The kinds she counts. Deliberately not every finding — these are the four
## habits that describe a way of working rather than a bad Tuesday.
## kind -> [one of them, more than one of them]. Two forms because the tally is
## read out loud on two screens and "1 people sent home" is a sentence written
## by a spreadsheet.
const COUNTED := {
	"uncorroborated_stay": ["a bed nobody but you ever saw a reason for",
		"beds nobody but you ever saw a reason for"],
	"backdated": ["a note written up after the fact",
		"notes written up after the fact"],
	"reversed_a_colleague": ["time you overruled somebody in writing",
		"times you have overruled somebody in writing"],
	"sent_home_unwell": ["somebody sent home against what was on the chart",
		"people sent home against what was on the chart"],
}

static func _phrase(kind: String, n: int) -> String:
	var pair: Array = COUNTED.get(kind, ["", ""])
	return String(pair[0] if n == 1 else pair[1])

var counts: Dictionary = {}     ## kind -> times, across the whole career
var referrals := 0              ## REFERRED verdicts, for the record and the tally

## HOW CLOSE THE BOARD IS, and the strike currency of the whole game.
##
## This used to be `referrals >= 3`, and it fired at nobody. The money-optimal
## play — hold three, because a fourth costs a $500 admission to gain at most
## $850 — lands on FLAGGED on BOTH authored wards and never on REFERRED, which
## needs two indefensible beds. So the optimal player accrued zero strikes
## forever, the auditor never spawned, and the flat seven-day loop the whole
## redesign exists to kill survived one verdict tier down.
##
## A score instead. A clean night pays a strike back, a queried one is free, a
## flagged one costs, and a referral costs properly. Five and the Board writes
## to you. The $4,350 farm reaches five at the end of night five and dies one
## night short of paying off; an honest career never leaves zero.
const STRIKE_FOR := {
	ReviewSystem.OUTCOME_CLEAR: -1,
	ReviewSystem.OUTCOME_QUESTIONS: 0,
	ReviewSystem.OUTCOME_FLAGGED: 1,
	ReviewSystem.OUTCOME_ESCALATED: 3,
}
const STRIKES_TO_STRIKE_OFF := 5
var strikes := 0
var flagged_nights := 0
var clean_nights := 0
var nights := 0

static func load_from_state() -> DoctorRecord:
	var r := DoctorRecord.new()
	var d: Dictionary = GameState.flag(FLAG, {})
	r.counts = Dictionary(d.get("counts", {})).duplicate(true)
	r.referrals = int(d.get("referrals", 0))
	r.strikes = int(d.get("strikes", 0))
	r.flagged_nights = int(d.get("flagged_nights", 0))
	r.clean_nights = int(d.get("clean_nights", 0))
	r.nights = int(d.get("nights", 0))
	return r

func save_to_state() -> void:
	GameState.set_flag(FLAG, {
		"counts": counts.duplicate(true),
		"referrals": referrals,
		"strikes": strikes,
		"flagged_nights": flagged_nights,
		"clean_nights": clean_nights,
		"nights": nights,
	})

static func wipe() -> void:
	GameState.set_flag(FLAG, {})

func times(kind: String) -> int:
	return int(counts.get(kind, 0))

## The number the review reads to decide how much of this is a habit. A rate and
## not a total, so a long careful career is not punished for being long: forty
## clean nights with four bad ones in them is a tenth, and a tenth is nothing.
func uncorroborated_rate() -> float:
	if nights <= 0:
		return 0.0
	return float(times("uncorroborated_stay")) / float(nights)

## How much heavier a finding of this kind is, given how often she has raised it
## before. The FIRST one is worth what it says on the tin — a discrepancy is a
## discrepancy and a ward runs on them. It is the fourth that describes you.
##
## Capped, because a career should get harder and not become a formality: at
## some point she is reading everything closely and there is nothing left to
## escalate to except the two endings.
func weight_for(kind: String) -> float:
	if not COUNTED.has(kind):
		return 1.0
	return minf(1.0 + 0.28 * float(times(kind)), 2.2)

## Written at the handover, from the findings she actually raised and the
## verdict she actually reached. Nothing here is stored during the day.
func record_night(findings: Array, verdict: String) -> void:
	nights += 1
	var seen := {}
	for f in findings:
		var k := String(f.kind)
		if COUNTED.has(k) and not seen.has(k):
			# ONCE PER NIGHT PER KIND. Counting every instance made a single bad
			# shift look like a career, and the point of this is the shape of a
			# career.
			seen[k] = true
			counts[k] = times(k) + 1
	strikes = maxi(0, strikes + int(STRIKE_FOR.get(verdict, 0)))
	match verdict:
		ReviewSystem.OUTCOME_ESCALATED:
			referrals += 1
			flagged_nights += 1
		ReviewSystem.OUTCOME_FLAGGED:
			flagged_nights += 1
		ReviewSystem.OUTCOME_CLEAR:
			clean_nights += 1
	save_to_state()

## How near the edge, in words. On the handover screen, because a threshold the
## player cannot see coming is a threshold that feels arbitrary when it lands.
func standing() -> String:
	var left: int = STRIKES_TO_STRIKE_OFF - strikes
	if strikes <= 0:
		return ""
	if left <= 1:
		return "One more bad night and the Board writes to you."
	return "%d more bad nights and the Board writes to you." % left

## THE OTHER LADDER, IN WORDS. `standing()` counts strikes, which the player can
## feel going up and down. This one counts the rate, which they cannot — and
## crossing it turns a flag into a referral, three strikes instead of one. A
## threshold nobody can see coming is a threshold that feels arbitrary when it
## lands, and this is the one that ends most careers.
func habit_warning() -> String:
	if nights < ReviewSystem.HABIT_NIGHTS:
		return ""
	var rate := uncorroborated_rate()
	if rate >= ReviewSystem.ENTRENCHED_RATE and nights >= ReviewSystem.ENTRENCHED_NIGHTS:
		return "She no longer asks about these one at a time. The next bed " \
			+ "you are the only witness for goes straight to the panel."
	if rate >= ReviewSystem.HABIT_RATE:
		return "\"Only you saw it\" has stopped being a reason, doctor. " \
			+ "Keep this up and it stops being a question, too."
	return ""

## What she says before she says anything else. Empty on a clean record, which
## is the point — the first few days she has no reason to open with anything.
func opening_line() -> String:
	var worst := ""
	var worst_n := 0
	for k in counts:
		if int(counts[k]) > worst_n:
			worst_n = int(counts[k])
			worst = String(k)
	if worst_n >= 4:
		return "That's the %s time this month, doctor. I have started keeping a list." \
			% _ordinal(worst_n)
	if worst_n == 3:
		return "This is the third time I've had to ask you about %s." \
			% _phrase(worst, 2)
	if referrals >= 1:
		return "You know coding are still on last week."
	return ""

## Plain, and available to the player before the review — she is not hiding it.
func summary_lines() -> Array:
	var out: Array = []
	for k in COUNTED:
		var n := times(k)
		if n > 0:
			out.append("%d  %s" % [n, _phrase(String(k), n)])
	return out

static func _ordinal(n: int) -> String:
	match n:
		1: return "first"
		2: return "second"
		3: return "third"
		4: return "fourth"
		5: return "fifth"
		6: return "sixth"
		7: return "seventh"
	return "%dth" % n
