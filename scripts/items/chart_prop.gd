extends Prop
## The physical patient chart. Carrying it is normal. Carrying it into your
## office with the door shut is normal-ish. Feeding it to the shredder is not.

var patient_id := ""

func _ready() -> void:
	super._ready()
	# So the objective marker can find "a chart" without knowing which one.
	add_to_group("chart_prop")

func get_patient_id() -> String:
	return patient_id

func bind(p) -> void:
	patient_id = p.id
	label = "%s — %s" % [p.display_name, p.condition_name()]
	display = "Chart"

func prompt(_player) -> Array:
	return ["Read chart", label if label != "" else "unassigned"]

func interact(_player, _held) -> void:
	if patient_id == "":
		return
	AudioMgr.play_var("paper", -14.0)
	EventBus.request_ui.emit("chart", {"patient_id": patient_id})
