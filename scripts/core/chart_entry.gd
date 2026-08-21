class_name ChartEntry
extends RefCounted
## One line in a patient's chart, and the most important object in the game.
##
## An entry is not a fact. It is a CLAIM, made by somebody, about a moment,
## written down at another moment, at a physical terminal, possibly in front of
## witnesses. The player controls what the claim says and what time it says it
## happened. The world records everything else, and everything else is what the
## ward sister reads in the morning.
##
## Nothing here is secret. The player can open the same chart the reviewer will
## open and read the same metadata. The game is not about hidden numbers; it is
## about whether the timeline you built survives being read by somebody who is
## looking at it properly.

enum Author {
	YOU,       ## your name, your login, your problem
	NURSE,     ## independently authored — the strongest kind, and not yours to write
	PATIENT,   ## "patient reports…". Only as good as the patient's memory of saying it
	MACHINE,   ## a result. True whatever anybody wanted it to be
}

## What the entry is claiming, in a form other entries can be compared against.
## The prose is flavour; `claim` is what the contradiction detector reads.
enum Claim {
	UNWELL,        ## something is wrong — supports staying
	SETTLED,       ## comfortable, stable, unremarkable — supports going home
	MOBILISING,    ## up and about, self-caring — supports going home, strongly
	RESULT_NORMAL, ## an objective test that found nothing
	RESULT_ABNORMAL,
	ORDER,         ## a request for something to be done
	ADMIN,         ## a note that claims nothing clinical
	FIT_FOR_DISCHARGE, ## a colleague's explicit PLAN, not an observation.
	                   ## Reversing one of these is a professional disagreement
	                   ## with a named person, and time of day does not soften it.
}

var id: String = ""
var patient_id: String = ""

var claim: Claim = Claim.ADMIN
var text: String = ""              ## what it reads as on the chart

## THE TWO TIMESTAMPS. `stated_minute` is the moment the entry describes and is
## chosen by whoever wrote it. `written_minute` is when it was actually typed and
## is chosen by nobody.
var stated_minute: int = 0
var written_minute: int = 0

var author: Author = Author.YOU
var author_id: String = "player"
var terminal_id: String = ""       ## which machine it was typed on
var seen_by: PackedStringArray = PackedStringArray()  ## who was in sightline of that terminal

## Set when this entry exists to explain an earlier one. An addendum is an
## admission that the record needed help.
var explains: String = ""

## Set when this entry exists because YOU asked for it. A nurse's routine round
## disagreeing with you is bad luck; a nurse disagreeing with you because you
## sent her to look is a different thing entirely, and the reviewer can tell the
## difference because the request is in the notes.
var at_your_request := false

## Orders only: what was asked for, and whether it ever happened.
var order_kind: String = ""
var fulfilled_by: String = ""

const BACKDATE_TOLERANCE := 20   ## minutes. Writing up a round late is normal.

func backdated_by() -> int:
	return maxi(0, written_minute - stated_minute)

func is_backdated() -> bool:
	return backdated_by() > BACKDATE_TOLERANCE

## Does this entry argue the patient should still be here at the end of the day?
func supports_stay() -> bool:
	return claim == Claim.UNWELL or claim == Claim.RESULT_ABNORMAL

## ...or that they were fit to go?
func supports_discharge() -> bool:
	return claim == Claim.SETTLED or claim == Claim.MOBILISING \
		or claim == Claim.RESULT_NORMAL or claim == Claim.FIT_FOR_DISCHARGE

## Two entries are ABOUT THE SAME MOMENT if the windows they describe overlap.
## Half an hour either side, because a ward round is not a stopwatch.
const SAME_MOMENT := 30

func concerns_same_moment_as(other: ChartEntry) -> bool:
	return absi(stated_minute - other.stated_minute) <= SAME_MOMENT

func author_label() -> String:
	match author:
		Author.YOU: return "you"
		Author.NURSE: return author_id
		Author.PATIENT: return "patient-reported"
		Author.MACHINE: return "result"
	return "?"

## How the line reads on a chart, which is how the player and the reviewer both
## see it. Deliberately identical for both — there is no privileged view.
func as_line() -> String:
	return "%s  %s  (%s)" % [_hhmm(stated_minute), text, author_label()]

static func _hhmm(m: int) -> String:
	return "%02d:%02d" % [(m / 60) % 24, m % 60]

func metadata_line() -> String:
	var bits := PackedStringArray()
	bits.append("written %s" % _hhmm(written_minute))
	if terminal_id != "":
		bits.append("at %s" % terminal_id)
	if is_backdated():
		bits.append("%d min after the fact" % backdated_by())
	return "   ".join(bits)

func to_dict() -> Dictionary:
	return {
		"id": id, "pid": patient_id, "claim": int(claim), "text": text,
		"st": stated_minute, "wr": written_minute, "au": int(author),
		"aid": author_id, "term": terminal_id, "seen": seen_by,
		"exp": explains, "ok": order_kind, "fb": fulfilled_by, "req": at_your_request,
	}

static func from_dict(d: Dictionary) -> ChartEntry:
	var e := ChartEntry.new()
	e.id = String(d.get("id", ""))
	e.patient_id = String(d.get("pid", ""))
	e.claim = d.get("claim", 0) as Claim
	e.text = String(d.get("text", ""))
	e.stated_minute = int(d.get("st", 0))
	e.written_minute = int(d.get("wr", 0))
	e.author = d.get("au", 0) as Author
	e.author_id = String(d.get("aid", "player"))
	e.terminal_id = String(d.get("term", ""))
	e.seen_by = PackedStringArray(d.get("seen", []))
	e.explains = String(d.get("exp", ""))
	e.order_kind = String(d.get("ok", ""))
	e.fulfilled_by = String(d.get("fb", ""))
	e.at_your_request = bool(d.get("req", false))
	return e
