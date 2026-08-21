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

## Who this cycle is for.
##
## Proximity was the whole answer while machines lived at the bedside. They do
## not any more: the imaging bench is the last device in the building and it
## stands in Radiology, and nothing in the hospital can bring a patient to it.
## Beds became static chairs, so nobody is wheeled anywhere; a patient who gets
## up walks to the day room or the corridor and back; and a re-room is only
## accepted into a ward or Intake. So _nearby_patient() could only ever return
## null here, and with it went every imaging finding, the machine_deviation
## cause tag, and the one honest way to answer a colleague who asked for a scan
## — buying Radiology could only ever make the player's position worse.
##
## Imaging is an appointment rather than a bedside act, so the bench works the
## list instead: somebody asked for a scan, and this is the room where scans
## happen. Proximity still wins when it can, because the person standing in
## front of you is always the one you meant.
func _target(player):
	if machine == null:
		return null
	# One lookup, on the machine, so the dial, the readout on the front and this
	# button can never disagree about who the cycle is for. It used to live here
	# alone, which meant the bench said "(no patient present)" while the button
	# a metre away named the person who had been booked.
	var best = machine._nearby_patient(player)
	# The prescribed aperture belongs to the patient, and _nearby_patient() is
	# what normally carries it in. On this path nobody walked in, so it is
	# fetched here — from prompt() as well as from interact(), so the readout on
	# the front of the bench is right BEFORE the dial is touched rather than
	# changing under the player at the moment they hold the button down.
	# Only when it actually changes: _refresh() rebuilds the readout and the lamp
	# material, and prompt() runs every frame the player is aiming at the button.
	if best != null and machine._prescribed_for != String(best.id):
		machine.set_prescribed_for(best)
	return best

func prompt(player) -> Array:
	if machine == null:
		return ["Run Cycle", ""]
	var p = _target(player)
	return ["Run %s" % machine.fixture_name, "%s   ·   dial is at %d   [hold E]" % [
		"nobody booked" if p == null else String(p.display_name), machine.dial]]

func use_seconds(_player, _held) -> float:
	return float(DB.treatment(machine.treatment_id).get("time", 3.0)) if machine else 2.0

func interact(player, _held) -> void:
	if machine == null:
		return
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null:
		return
	var p = _target(player)
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
	var ps2 = get_tree().get_first_node_in_group("patient_system")
	if ps2 != null:
		body = ps2.get_body(p.id)
	# Only if they are actually in the room. Somebody two corridors away does
	# not flinch at a machine they cannot hear, and the beam has nothing to
	# point at — a booked scan is the paperwork version of the same act, and it
	# reads as the bench running rather than as a body being worked on.
	if body != null and (not is_instance_valid(body) or not body.is_inside_tree()
			or body.global_position.distance_to(global_position) > 3.4):
		body = null
	machine.begin_cycle(2.4, machine.dial - machine.prescribed, body)
	if body != null and body.has_method("undergo_cycle"):
		body.undergo_cycle(2.4, absi(machine.dial - machine.prescribed))
	ts.run_machine(machine, p)
	var rs = get_tree().get_first_node_in_group("records_system")
	if rs:
		rs.log_real_treatment(p, machine.treatment_id)
