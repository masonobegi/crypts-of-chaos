class_name Evidence
extends RefCounted
## One character's memory of one incriminating thing. The *belief layer*.
##
## Suspicion is never stored — it is derived by summing the live weight of the
## evidence a character holds. That is what makes it manipulable: you cannot
## lower a number, but you CAN destroy the chart, contradict the claim, provide a
## cover story, wait for it to fade, or make sure there was only ever one witness.

enum Source {
	WITNESSED,   ## saw it happen. Heavy, hard to argue with.
	HEARD,       ## heard it but didn't see it. Lighter, easy to explain.
	GOSSIP,      ## someone told them. Degrades with each retelling.
	RECORD,      ## found it in the paperwork. Slow-burn, survives everything.
	INFERRED,    ## noticed a pattern (your patients always take twice as long).
}

var kind: String = ""            ## mirrors WorldEvent.kind
var about_actor: String = ""     ## who they think did it
var patient_id: String = ""
var source: Source = Source.WITNESSED
var time: int = 0                ## career minute observed
var base_weight: float = 0.0     ## 0..1-ish, before certainty and decay
var certainty: float = 1.0       ## 0..1 — how sure they are it was you
var tags: PackedStringArray = PackedStringArray()
var summary: String = ""
var cover_tag: String = ""

## Ids of others known to have seen the same thing. Corroboration is the real
## killer: one witness is deniable, two is a pattern.
var corroborators: PackedStringArray = PackedStringArray()

## Set when the player successfully explained this away. Neutralised evidence
## still exists — an investigator can un-neutralise it if they find a contradiction.
var neutralized: bool = false
## How many times the player has leaned on this excuse. Reusing a cover story
## on the same character stops working, which forces improvisation.
var explained_attempts: int = 0

## Evidence forgets. Records and inferences barely do.
func decay_per_day() -> float:
	match source:
		Source.WITNESSED: return 0.10
		Source.HEARD: return 0.22
		Source.GOSSIP: return 0.28
		Source.RECORD: return 0.01
		Source.INFERRED: return 0.04
	return 0.15

func source_multiplier() -> float:
	match source:
		Source.WITNESSED: return 1.0
		Source.HEARD: return 0.45
		Source.GOSSIP: return 0.35
		Source.RECORD: return 0.8
		Source.INFERRED: return 0.6
	return 0.5

## Live weight right now, for a given observer personality.
func current_weight(now_minutes: int, cover_active: bool = false) -> float:
	if neutralized:
		return base_weight * certainty * 0.12   # residue: never fully gone
	var days := float(now_minutes - time) / float(GameState.MINUTES_PER_DAY)
	var fade := maxf(0.0, 1.0 - decay_per_day() * maxf(0.0, days))
	var w := base_weight * certainty * source_multiplier() * fade
	# Corroboration is superlinear — that is why isolating witnesses matters.
	w *= 1.0 + 0.55 * float(corroborators.size())
	if cover_active and cover_tag != "":
		w *= 0.25
	return w

func is_stale(now_minutes: int) -> bool:
	return current_weight(now_minutes) < 0.01

func label() -> String:
	if summary != "":
		return summary
	return kind.replace("_", " ")

func source_label() -> String:
	return ["saw it", "heard it", "was told", "found it in the file", "worked it out"][int(source)]

static func from_world_event(e: WorldEvent, src: Source, weight: float, cert: float) -> Evidence:
	var ev := Evidence.new()
	ev.kind = e.kind
	ev.about_actor = e.actor
	ev.patient_id = e.patient_id
	ev.source = src
	ev.time = e.time
	ev.base_weight = weight
	ev.certainty = cert
	ev.tags = e.tags.duplicate()
	ev.summary = e.summary
	ev.cover_tag = e.cover_tag
	return ev

## Retelling degrades a claim — the game of telephone is a real mechanic.
func retold() -> Evidence:
	var c := Evidence.new()
	c.kind = kind
	c.about_actor = about_actor
	c.patient_id = patient_id
	c.source = Source.GOSSIP
	c.time = time
	c.base_weight = base_weight
	c.certainty = clampf(certainty * 0.72, 0.05, 1.0)
	c.tags = tags.duplicate()
	c.summary = summary
	c.cover_tag = cover_tag
	return c

func to_dict() -> Dictionary:
	return {
		"kind": kind, "actor": about_actor, "pid": patient_id, "src": int(source),
		"t": time, "w": base_weight, "c": certainty, "tags": Array(tags),
		"sum": summary, "cov": cover_tag, "corr": Array(corroborators),
		"neu": neutralized, "exp": explained_attempts,
	}

static func from_dict(d: Dictionary) -> Evidence:
	var ev := Evidence.new()
	ev.kind = d.get("kind", "")
	ev.about_actor = d.get("actor", "")
	ev.patient_id = d.get("pid", "")
	ev.source = int(d.get("src", 0)) as Source
	ev.time = int(d.get("t", 0))
	ev.base_weight = float(d.get("w", 0.0))
	ev.certainty = float(d.get("c", 1.0))
	ev.tags = PackedStringArray(d.get("tags", []))
	ev.summary = d.get("sum", "")
	ev.cover_tag = d.get("cov", "")
	ev.corroborators = PackedStringArray(d.get("corr", []))
	ev.neutralized = bool(d.get("neu", false))
	ev.explained_attempts = int(d.get("exp", 0))
	return ev
