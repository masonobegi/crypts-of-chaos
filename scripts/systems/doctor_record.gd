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
const COUNTED := {
	"uncorroborated_stay": "beds nobody but you ever saw a reason for",
	"backdated": "notes written up after the fact",
	"reversed_a_colleague": "times you have overruled somebody in writing",
	"sent_home_unwell": "people sent home against what was on the chart",
}

var counts: Dictionary = {}     ## kind -> times, across the whole career
var referrals := 0              ## REFERRED verdicts. Three and you are finished
var flagged_nights := 0
var clean_nights := 0
var nights := 0

static func load_from_state() -> DoctorRecord:
	var r := DoctorRecord.new()
	var d: Dictionary = GameState.flag(FLAG, {})
	r.counts = Dictionary(d.get("counts", {})).duplicate(true)
	r.referrals = int(d.get("referrals", 0))
	r.flagged_nights = int(d.get("flagged_nights", 0))
	r.clean_nights = int(d.get("clean_nights", 0))
	r.nights = int(d.get("nights", 0))
	return r

func save_to_state() -> void:
	GameState.set_flag(FLAG, {
		"counts": counts.duplicate(true),
		"referrals": referrals,
		"flagged_nights": flagged_nights,
		"clean_nights": clean_nights,
		"nights": nights,
	})

static func wipe() -> void:
	GameState.set_flag(FLAG, {})

func times(kind: String) -> int:
	return int(counts.get(kind, 0))

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
	match verdict:
		ReviewSystem.OUTCOME_ESCALATED:
			referrals += 1
			flagged_nights += 1
		ReviewSystem.OUTCOME_FLAGGED:
			flagged_nights += 1
		ReviewSystem.OUTCOME_CLEAR:
			clean_nights += 1
	save_to_state()

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
			% String(COUNTED.get(worst, "this"))
	if referrals >= 1:
		return "You know coding are still on last week."
	return ""

## Plain, and available to the player before the review — she is not hiding it.
func summary_lines() -> Array:
	var out: Array = []
	for k in COUNTED:
		var n := times(k)
		if n > 0:
			out.append("%d  %s" % [n, String(COUNTED[k])])
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
