class_name MachineRunButton
extends Fixture
## The big green button. Separate from the dial so a treatment is always a
## deliberate act you held down for three seconds, never a misclick.

var machine: TreatmentMachine = null

func build(m: TreatmentMachine) -> void:
	machine = m
	fixture_name = "Run Cycle"
	setup_body(Vector3(0.26, 0.26, 0.14), [
		{"mesh": Build.cyl_mesh(0.11, 0.06, 14), "mat": Build.mat(Color(0.3, 0.32, 0.34)), "rot": Vector3(PI / 2, 0, 0)},
		{"mesh": Build.cyl_mesh(0.085, 0.07, 14), "mat": Build.mat(Build.GOOD, 0.3, 0.0, Build.GOOD * 0.4), "pos": Vector3(0, 0, 0.03), "rot": Vector3(PI / 2, 0, 0)},
	])

func prompt(_player) -> Array:
	if machine == null:
		return ["Run Cycle", ""]
	return ["Run %s" % machine.fixture_name, "dial is at %d   [hold E]" % machine.dial]

func use_seconds(_player, _held) -> float:
	return float(DB.treatment(machine.treatment_id).get("time", 3.0)) if machine else 2.0

func interact(player, _held) -> void:
	if machine == null:
		return
	EventBus.request_ui.emit("run_machine", {"machine": machine, "player": player})
