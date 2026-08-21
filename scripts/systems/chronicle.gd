class_name Chronicle
extends Node
## The story of a career, kept while it happens.
##
## This game manufactures anecdotes constantly and then throws every one of them
## away. A run ends on a table of counters — "complications caused: 71" — when
## what actually happened was that you met Ruthven Pike on Ossory Street on the
## sixth, he was in bed 2 by Tuesday, and he spent nine days trying to place
## your face.
##
## That is the thing a person screenshots, and it is the only artefact this game
## produces that would make somebody else want to play it.
##
## IT IS A LISTENER, NOT AN API
##
## Same rule the achievements follow, for the same reason: a system that has to
## remember to write its own history is a system with a hole in its history. It
## connects to EventBus and writes its own entries. Four beats carry context no
## signal has, and those call `note()` directly — the street, the courtroom, the
## envelope, and the hidden achievements.
##
## Nothing here holds a node. Names and ids only. A log that keeps references to
## patients is a log that hits the freed-object-abort trap on the first
## discharge, and it would do it silently.

## Kinds, and what each is worth remembering. Weight is not severity — it is how
## much of the STORY the entry is. A sanction is the story. An admission is
## scene-setting, unless you are the reason for it.
const W_SCENE := 0.30
const W_TURN := 0.60
const W_BEAT := 0.85
const W_STORY := 1.00

const CAP := 200

func _ready() -> void:
	add_to_group("chronicle")
	EventBus.patient_admitted.connect(_on_admitted)
	EventBus.patient_discharged.connect(_on_discharged)
	EventBus.complication_added.connect(_on_complication)
	EventBus.complaint_filed.connect(_on_complaint)
	EventBus.investigation_opened.connect(_on_investigation_opened)
	EventBus.investigation_closed.connect(_on_investigation_closed)
	EventBus.sanction_applied.connect(_on_sanction)
	EventBus.world_event.connect(_on_world_event)

# ------------------------------------------------------------------ writing
## The one entry point. Static so the four beats that have no signal can reach
## it without looking the node up.
static func note(kind: String, weight: float, text: String) -> void:
	if text.strip_edges() == "":
		return
	GameState.chronicle.append({
		"day": GameState.day,
		"minute": GameState.minute_of_day,
		"kind": kind,
		"weight": clampf(weight, 0.0, 1.0),
		"text": text,
	})
	_prune()

## Keep the save small by dropping the least storyish thing, not the oldest.
## A career's first day is often its best material.
static func _prune() -> void:
	if GameState.chronicle.size() <= CAP:
		return
	var worst := 0
	for i in GameState.chronicle.size():
		if float(GameState.chronicle[i]["weight"]) < float(GameState.chronicle[worst]["weight"]):
			worst = i
	GameState.chronicle.remove_at(worst)

# ------------------------------------------------------------------ listening
func _on_admitted(p) -> void:
	if p == null:
		return
	# Somebody you fetched yourself is a different sentence from somebody the
	# morning brought in, and it is the better one.
	var from_the_street: bool = bool(p.get_meta("from_the_street", false))
	if from_the_street:
		note("street", W_BEAT, "%s arrived with %s. You already knew that."
			% [p.display_name, p.condition_name()])
	else:
		note("admitted", W_SCENE, "%s came in with %s."
			% [p.display_name, p.condition_name()])

func _on_discharged(p, reason: String) -> void:
	if p == null:
		return
	match reason:
		"cured":
			note("discharged", W_SCENE, "%s went home well." % p.display_name)
		"early":
			note("discharged", W_TURN,
				"You sent %s home before they were right." % p.display_name)
		"wrong":
			note("discharged", W_BEAT,
				"%s went home on the wrong thing." % p.display_name)
		_:
			note("discharged", W_SCENE, "%s left." % p.display_name)

func _on_complication(p, comp) -> void:
	if p == null or comp == null:
		return
	# An injury sustained on your ward is the story; a complication of the
	# illness they came in with is weather.
	if bool(comp.is_injury):
		# "Picked up", not "left with" — they are still in the bed when this
		# fires, and the tense was wrong. It also dodges an article-and-pronoun
		# problem the game has no information to solve.
		note("injury", W_BEAT, "%s picked up %s on your ward."
			% [p.display_name, _a(comp.display_name)])
	else:
		note("complication", W_SCENE, "%s developed %s."
			% [p.display_name, _a(comp.display_name)])

func _on_complaint(about: String, _by_id: String, severity: float) -> void:
	note("complaint", W_TURN if severity < 0.6 else W_BEAT,
		"Somebody put a complaint in about %s." % about)

func _on_investigation_opened(_inv) -> void:
	note("investigation", W_STORY, "Meridian Mutual opened a file.")

func _on_investigation_closed(_inv, outcome: String) -> void:
	if outcome == "cleared":
		note("investigation", W_BEAT, "The file was closed. No findings.")
	else:
		note("investigation", W_STORY, "The file was closed, and not in your favour.")

func _on_sanction(level: int, reason: String) -> void:
	note("sanction", W_STORY, "%s — %s." % [
		String(GameState.SANCTIONS[clampi(level, 0, GameState.SANCTIONS.size() - 1)]),
		reason if reason != "" else "no reason given"])

## The only signal that carries the interesting verbs. Everything the ward does
## that somebody could have seen goes through here.
func _on_world_event(evt) -> void:
	if evt == null:
		return
	var tags: Array = evt.tags if evt.get("tags") != null else []
	if tags.has("violence"):
		note("violence", W_STORY, "There was an altercation in %s." % _room(evt))

## "a Fractured Wrist", "an Inflamed Funny Bone". Cheap and wrong about an
## hour, a union and a European; there are none of those in the catalogue.
static func _a(name: String) -> String:
	if name == "":
		return name
	return ("an " if "aeiouAEIOU".contains(name[0]) else "a ") + name

func _room(evt) -> String:
	var r := String(evt.room) if evt.get("room") != null else ""
	return r.capitalize().replace("_", " ") if r != "" else "the ward"

# ------------------------------------------------------------------ reading
## The handful of things that actually happened, in order.
##
## Picked by weight, but with a cap per kind — a career of nothing but botched
## sutures should still read as a story rather than as the same sentence nine
## times. Then sorted by day, because a story is chronological even when the
## selection is not.
static func story(n := 9, per_kind := 2) -> Array:
	var pool: Array = GameState.chronicle.duplicate()
	pool.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var taken: Array = []
	var counts: Dictionary = {}
	for e in pool:
		if taken.size() >= n:
			break
		var k := String(e["kind"])
		if int(counts.get(k, 0)) >= per_kind:
			continue
		counts[k] = int(counts.get(k, 0)) + 1
		taken.append(e)
	# Top up. A short career, or one that only ever did one KIND of thing, still
	# deserves a full page — the cap is there to stop the same sentence nine
	# times, not to hand back four lines when there are nine worth telling.
	if taken.size() < n:
		for e in pool:
			if taken.size() >= n:
				break
			if not taken.has(e):
				taken.append(e)
	taken.sort_custom(func(a, b):
		if int(a["day"]) != int(b["day"]):
			return int(a["day"]) < int(b["day"])
		return int(a["minute"]) < int(b["minute"]))
	return taken

## "Day 4" — the only stamp on the line. A time of day would be false precision
## about something that is being remembered rather than recorded.
static func stamp(entry: Dictionary) -> String:
	return "Day %d" % int(entry.get("day", 1))
