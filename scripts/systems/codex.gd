class_name Codex
extends Node
## Notes your character works out by doing things twice.
##
## The game refuses to label anything "questionable" up front. The codex is the
## compromise: once you have personally caused the same effect twice, your
## character writes down what they think is going on — in their own words, which
## are not always exactly right.

const ENTRIES := {
	"machine_deviation": {
		"title": "Dials",
		"text": "Twice now, running a machine well off its prescribed setting has been "
			+ "followed by the patient developing something new. The machines log the "
			+ "setting. I should check what else those logs say.",
	},
	"clean_documentation": {
		"title": "Getting in front of it",
		"text": "A complication with a cause written down before anyone noticed it is "
			+ "just medicine. The same complication with nothing on the chart is an "
			+ "incident. The difference is about four seconds at a terminal.",
	},
	"witnesses": {
		"title": "Being seen",
		"text": "People remember what they watch me do. Two of them remembering the same "
			+ "thing seems to be far worse than one — they talk to each other, and then "
			+ "it stops being my word against theirs.",
	},
	"substitution": {
		"title": "Labels",
		"text": "What is in the container decides what happens to the patient. What is on "
			+ "the label decides what everyone thinks happened. Nobody has ever checked "
			+ "which is which from across a room.",
	},
	"environment": {
		"title": "The building's fault",
		"text": "Cold wards make people worse. That is the building's fault, provided "
			+ "somebody filed a ticket about the building first.",
	},
	"phantom_billing": {
		"title": "Line items",
		"text": "Nothing stops me billing for a treatment I did not give. Nothing at all. "
			+ "It sits in the record permanently, though, and records are the one thing "
			+ "that never forget.",
	},
	"rumours": {
		"title": "Talking",
		"text": "It got back to someone who was not there. The story was worse and less "
			+ "accurate, which somehow did not help me.",
	},
	"noise": {
		"title": "Noise",
		"text": "Something falling over at the far end of the ward moves everybody toward "
			+ "it. For about twenty seconds, nobody is looking at anything else.",
	},
	"overdue": {
		"title": "Dates",
		"text": "Patients count the days. So do their families, and they compare notes. "
			+ "Moving the date on the chart does not move the date in their head.",
	},
	"privacy": {
		"title": "Where I do it",
		"text": "Editing records at the nurses' station and editing them in my office with "
			+ "the door shut are not the same act, whatever the record ends up saying.",
	},
}

const REQUIRED := 2

var _counts: Dictionary = {}

func _ready() -> void:
	add_to_group("codex")
	EventBus.world_event.connect(_on_world_event)
	EventBus.evidence_recorded.connect(_on_evidence)
	EventBus.rumor_spread.connect(func(_a, _b, _c): observe("rumours"))
	EventBus.complication_added.connect(_on_complication)

func observe(id: String) -> void:
	if GameState.codex_unlocked.has(id) or not ENTRIES.has(id):
		return
	_counts[id] = int(_counts.get(id, 0)) + 1
	if int(_counts[id]) < REQUIRED:
		return
	GameState.unlock_codex(id)
	var spec: Dictionary = ENTRIES[id]
	EventBus.toast.emit("Noted: %s" % String(spec["title"]), "info")
	AudioMgr.play("paper", -12.0)

func _on_world_event(evt) -> void:
	var e: WorldEvent = evt
	if e.actor != "player":
		if e.kind == "prop_noise":
			return
		return
	if e.tags.has("machine") and e.kind == "machine_extreme_dial":
		observe("machine_deviation")
	if e.tags.has("substitution"):
		observe("substitution")
	if e.kind == "phantom_billing":
		observe("phantom_billing")
	if e.tags.has("environment"):
		observe("environment")
	if e.kind == "discharge_date_moved":
		observe("overdue")
	if e.tags.has("records") and e.visual_weight < 0.1:
		observe("privacy")

func _on_evidence(_witness, ev) -> void:
	var e: Evidence = ev
	if e.source == Evidence.Source.WITNESSED and e.base_weight > 0.25:
		observe("witnesses")

func _on_complication(_p, comp) -> void:
	var c: Complication = comp
	if c.true_cause == "machine_deviation":
		observe("machine_deviation")
	elif c.true_cause == "facilities":
		observe("environment")

## Called by RecordsSystem when a complication is filed cleanly.
func note_clean_documentation() -> void:
	observe("clean_documentation")

## Called when a thrown/dropped prop pulls staff off station.
func note_distraction() -> void:
	observe("noise")

func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in GameState.codex_unlocked:
		if ENTRIES.has(id):
			out.append({"id": id, "title": ENTRIES[id]["title"], "text": ENTRIES[id]["text"]})
	return out

func to_dict() -> Dictionary:
	return {"counts": _counts}

func from_dict(d: Dictionary) -> void:
	_counts = d.get("counts", {})
