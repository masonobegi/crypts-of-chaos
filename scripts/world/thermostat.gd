class_name Thermostat
extends Fixture
## Ward temperature control.
##
## Quieter than opening a window: there is no physical tell in the room, so a
## nurse walking in sees nothing out of place. The trade is that a thermostat is
## a device with a SETTING, and a setting is a thing an inspector can read back
## to you — the same bargain as the machine dial.

const MIN_SET := 10
const MAX_SET := 28

var setting := 21
var log_entries: Array[Dictionary] = []
var _label: Label3D = null

func build() -> void:
	fixture_name = "Thermostat"
	setup_body(Vector3(0.2, 0.26, 0.07), [
		{"mesh": Build.box_mesh(Vector3(0.18, 0.24, 0.05)), "mat": Build.mat(Color(0.90, 0.90, 0.86))},
		{"mesh": Build.box_mesh(Vector3(0.13, 0.09, 0.02)), "mat": Build.mat(Color(0.10, 0.16, 0.14), 0.2, 0.0, Color(0.06, 0.28, 0.20)), "pos": Vector3(0, 0.04, 0.03)},
	])
	_label = Build.label3d("21", 0.045, Color(0.55, 1.0, 0.8), false)
	_label.position = Vector3(0, 0.04, 0.05)
	add_child(_label)
	_refresh()

func _refresh() -> void:
	if _label:
		_label.text = "%d" % setting

func prompt(_player) -> Array:
	var r := room()
	var actual := "%.0f" % r.temperature if r else "--"
	return ["Thermostat — set %d°" % setting, "room is at %s°   [E] adjust" % actual]

func interact(_player, _held) -> void:
	setting -= 2
	if setting < MIN_SET:
		setting = MAX_SET
	_refresh()
	AudioMgr.play_at_var("tick", global_position, -16.0)
	log_entries.append({
		"time": GameState.career_minutes, "day": GameState.day, "setting": setting,
	})
	var r := room()
	if r:
		r.target_override = float(setting)
	# Almost invisible in the moment — a small movement at a wall panel. The
	# record it leaves is the actual cost.
	emit_event("thermostat_set", 0.08 if absi(setting - 21) < 5 else 0.2,
		["environment", "device"], "facilities",
		"set the %s thermostat to %d" % [r.display if r else "ward", setting])

## What a facilities audit finds. Anything well off comfortable, on the record.
func suspicious_log_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log_entries:
		if absi(int(e["setting"]) - 21) >= 6:
			out.append(e)
	return out

func to_dict() -> Dictionary:
	return {"set": setting, "log": log_entries}

func from_dict(d: Dictionary) -> void:
	setting = int(d.get("set", 21))
	log_entries.clear()
	for e in d.get("log", []):
		log_entries.append(e)
	_refresh()
	var r := room()
	if r:
		r.target_override = float(setting)
