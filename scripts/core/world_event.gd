class_name WorldEvent
extends RefCounted
## An objective fact: something observable happened, somewhere, at some time.
##
## This is the *truth layer*. It says nothing about who noticed. Perception turns
## a WorldEvent into per-witness [Evidence]; a WorldEvent nobody perceives still
## happened (and can still surface later through records or statistics).

## What happened. Free-form so new content can add kinds without touching core.
var kind: String = ""
## Who caused it. "player", an NPC id, or "" for acts of god / physics.
var actor: String = ""
## Patient this concerns, if any.
var patient_id: String = ""
## Where it happened (for line-of-sight and hearing checks).
var pos: Vector3 = Vector3.ZERO
## Room key, so an NPC in the same room can infer without perfect LOS.
var room: String = ""
## In-game minute-of-career when it happened.
var time: int = 0

## How incriminating it looks to someone who SEES it. 0 = mundane.
var visual_weight: float = 0.0
## How incriminating it sounds. Most physical chaos is loud but innocent.
var audio_weight: float = 0.0
## Metres at which the sound is audible at all. 0 = silent.
var hear_radius: float = 0.0
## If true, being in the same room is enough — no line of sight required
## (e.g. a smell, a scream, the lights going out).
var ambient: bool = false

## Free tags used by personalities and codex rules, e.g. ["paperwork","forgery"].
var tags: PackedStringArray = PackedStringArray()

## If the player has an active cover story with this tag, witnesses discount the
## event heavily. This is the core of the "get in front of it" loop.
var cover_tag: String = ""

## Human-readable line used in incident reports and the shift summary.
var summary: String = ""

func _init(p_kind: String = "", p_actor: String = "") -> void:
	kind = p_kind
	actor = p_actor

## Fluent builders keep call sites to one line at the hundreds of emit points.
func at(p: Vector3, p_room: String = "") -> WorldEvent:
	pos = p
	room = p_room
	return self

func about(pid: String) -> WorldEvent:
	patient_id = pid
	return self

func seen(w: float) -> WorldEvent:
	visual_weight = w
	return self

func heard(w: float, radius: float = 12.0) -> WorldEvent:
	audio_weight = w
	hear_radius = radius
	return self

func smelled() -> WorldEvent:
	ambient = true
	return self

func tag(t: String) -> WorldEvent:
	tags.append(t)
	return self

func cover(t: String) -> WorldEvent:
	cover_tag = t
	return self

func says(s: String) -> WorldEvent:
	summary = s
	return self

## Fire it. One call, and every perception system in the world gets a chance.
func emit() -> WorldEvent:
	time = GameState.career_minutes
	EventBus.world_event.emit(self)
	return self

func to_dict() -> Dictionary:
	return {
		"kind": kind, "actor": actor, "patient_id": patient_id,
		"pos": [pos.x, pos.y, pos.z], "room": room, "time": time,
		"vw": visual_weight, "aw": audio_weight, "hr": hear_radius,
		"amb": ambient, "tags": Array(tags), "cover": cover_tag, "sum": summary,
	}

static func from_dict(d: Dictionary) -> WorldEvent:
	var e := WorldEvent.new()
	e.kind = d.get("kind", "")
	e.actor = d.get("actor", "")
	e.patient_id = d.get("patient_id", "")
	var p: Array = d.get("pos", [0, 0, 0])
	e.pos = Vector3(p[0], p[1], p[2])
	e.room = d.get("room", "")
	e.time = int(d.get("time", 0))
	e.visual_weight = float(d.get("vw", 0.0))
	e.audio_weight = float(d.get("aw", 0.0))
	e.hear_radius = float(d.get("hr", 0.0))
	e.ambient = bool(d.get("amb", false))
	e.tags = PackedStringArray(d.get("tags", []))
	e.cover_tag = d.get("cover", "")
	e.summary = d.get("sum", "")
	return e
