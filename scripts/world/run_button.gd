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
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null:
		return
	var p = machine._nearby_patient(player)
	if p == null:
		EventBus.toast.emit("The cycle runs. There is nobody in it.", "info")
		AudioMgr.play_at_var("machine_on", global_position, -14.0)
		machine.begin_cycle(1.6, 0, null)
		return
	# Straight into the world. No modal, nothing paused: the machine makes its
	# noise, the patient reacts where you can see them, and whoever is standing
	# in the doorway gets to watch you do it.
	#
	# The cycle is started BEFORE the treatment resolves and outlasts it by a
	# second and a half. That gap is the whole point: a machine that finishes
	# the instant you let go of the button costs you nothing to use, and the
	# exposure in this game is the time you spend standing next to one that is
	# obviously working.
	var body = null
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps != null:
		body = ps.get_body(p.id)
	machine.begin_cycle(2.4, machine.dial - machine.prescribed, body)
	if body != null and body.has_method("undergo_cycle"):
		body.undergo_cycle(2.4, absi(machine.dial - machine.prescribed))
	ts.run_machine(machine, p)
	var rs = get_tree().get_first_node_in_group("records_system")
	if rs:
		rs.log_real_treatment(p, machine.treatment_id)
