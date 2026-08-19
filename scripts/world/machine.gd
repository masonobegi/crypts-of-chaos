class_name TreatmentMachine
extends Fixture
## A fictional treatment device with a physical dial and a maintenance panel.
##
## Design rules this class exists to enforce:
##  * The UI NEVER says "questionable". It shows a dial, a prescribed value, and
##    fictional units. What deviation does is learned by watching patients.
##  * The machine keeps its own LOG. Running at 11 is trivially easy and leaves
##    a record an auditor will read back to you months later. Clearing the log is
##    possible, and is itself one of the most incriminating acts in the game.
##  * Calibration is a persistent, invisible, deniable sabotage: every treatment
##    afterwards underperforms and "equipment variance" is a real cause tag.

const DIAL_MIN := 0
const DIAL_MAX := 11

@export var machine_id := "machine_humour"
@export var treatment_id := "humour_rebalance"
@export var units := "PLASMA GRADIENT"

var dial := 5
var prescribed := 5
var calibration := 1.0        ## 1.0 = correct. Nobody can see this but a technician.
var log_entries: Array[Dictionary] = []
var log_cleared_count := 0
var running := false

var _dial_label: Label3D = null
var _readout: Label3D = null
var _lamp: MeshInstance3D = null
var _panel_open := false
var _prescribed_for := ""
## Seconds since the dial last moved, and the last value we told the room about.
## See interact(): a dial passing THROUGH a setting is not a dial SET to it.
## Starts settled, so a machine nobody has touched never announces anything —
## and a machine whose prescribed value changes under it (a new patient in the
## bed) does not report the player for something the player did not do.
var _dial_settle := 1.0
var _announced_dial := -1

func build(disp: String) -> void:
	fixture_name = disp
	var body := Build.mat(Color(0.86, 0.88, 0.90))
	var trim := Build.mat(Color(0.30, 0.42, 0.48))
	var screen := Build.mat(Color(0.10, 0.16, 0.14), 0.2, 0.0, Color(0.05, 0.35, 0.22))
	setup_body(Vector3(1.1, 1.5, 0.7), [
		{"mesh": Build.box_mesh(Vector3(1.1, 1.5, 0.7)), "mat": body, "pos": Vector3(0, 0.75, 0)},
		{"mesh": Build.box_mesh(Vector3(1.14, 0.12, 0.74)), "mat": trim, "pos": Vector3(0, 1.02, 0)},
		{"mesh": Build.box_mesh(Vector3(0.62, 0.34, 0.04)), "mat": screen, "pos": Vector3(0, 1.24, 0.36)},
		{"mesh": Build.cyl_mesh(0.11, 0.06, 14), "mat": trim, "pos": Vector3(-0.32, 0.78, 0.36), "rot": Vector3(PI / 2, 0, 0)},
		{"mesh": Build.box_mesh(Vector3(0.34, 0.24, 0.03)), "mat": Build.mat(Color(0.55, 0.58, 0.6)), "pos": Vector3(0.3, 0.72, 0.36)},
	], Vector3(0, 0.75, 0))

	_lamp = Build.mi(Build.sphere_mesh(0.05), Build.unshaded(Build.GOOD), Vector3(0.44, 1.3, 0.36))
	get_node("Mesh").add_child(_lamp)

	_readout = Build.label3d("", 0.052, Color(0.5, 1.0, 0.75), false)
	_readout.position = Vector3(0, 1.29, 0.39)
	_readout.width = 1100
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_readout)

	_dial_label = Build.label3d("5", 0.14, Color(1, 1, 1), false)
	_dial_label.position = Vector3(-0.32, 0.78, 0.41)
	add_child(_dial_label)
	_refresh()

# ------------------------------------------------------------------ display
func _refresh() -> void:
	if _dial_label:
		_dial_label.text = str(dial)
	if _readout:
		_readout.text = "%s\nSET %02d   PRESCRIBED %02d\nCAL %s" % [
			units, dial, prescribed,
			"OK" if absf(calibration - 1.0) < 0.02 else "OK",   # always claims OK
		]
	if _lamp:
		var m := _lamp.material_override as StandardMaterial3D
		if m:
			var c := Build.GOOD
			if absi(dial - prescribed) >= 4:
				c = Build.BAD
			elif absi(dial - prescribed) >= 2:
				c = Build.WARN
			_lamp.material_override = Build.unshaded(c)

# ------------------------------------------------------------------ interaction
## Four states, four prompts. See interact().
func prompt(player) -> Array:
	return _prompt_for(player, null)

## Carrying something changes what this machine is for, so the carry prompt is
## the same decision as the empty-handed one.
func prompt_with_item(player, held) -> Array:
	return _prompt_for(player, held)

func _prompt_for(player, held) -> Array:
	var wrench := _is_wrench(held)
	if _panel_open and wrench:
		return ["Turn the calibration screw",
			"calibration %d%%   ·   nobody checks these" % int(round(calibration * 100.0))]
	if _panel_open:
		return ["Wipe the %s log" % fixture_name,
			"%d entries   ·   [hold E]" % log_entries.size()]
	if wrench:
		return ["Open the maintenance panel", "the screw is behind it"]
	var p = _nearby_patient(player)
	if p == null:
		return ["%s — dial %d" % [fixture_name, dial],
			"[E] up   [Shift+E] down   (no patient present)"]
	return ["%s on %s" % [DB.treatment_name(treatment_id), p.display_name],
		"dial %d   ·   prescribed %d      [E] up   [Shift+E] down" % [dial, prescribed]]

## Wiping a device log is the one thing here you have to stand and do.
func use_seconds(_player, held) -> float:
	return 2.5 if (_panel_open and not _is_wrench(held)) else 0.0

func _is_wrench(held) -> bool:
	return held != null and is_instance_valid(held) \
		and held.has_method("get_item_id") and String(held.get_item_id()) == "wrench"

## The maintenance panel had no way in at all.
##
## `open_panel()` had no caller anywhere in the shipping game, `_panel_open` was
## initialised false and never written, and `_nudge_calibration()` is the only
## code in the project that lowers `calibration`. So calibration was always
## exactly 1.0, `is_miscalibrated()` could never return true, and the branch in
## run_cycle that reads it never fired. This class's own docstring calls
## calibration sabotage a headline mechanic; SPOILERS.md documents it to the
## developer as a real player verb. It did not exist.
##
## Neither did wiping a device log — `clear_log()` had no caller either, and its
## comment describes it as the act of somebody with something to hide.
##
## Both now hang off one object the player can already find: the wrench, which
## Treatment Stock has been carrying all along.
##
##   panel shut,  wrench in hand   →  open the panel
##   panel open,  wrench in hand   →  turn the screw (tap)
##   panel open,  hands free       →  wipe the log (hold)
##   panel shut,  hands free       →  the dial, as before
func interact(player, held) -> void:
	if _panel_open:
		if _is_wrench(held):
			_nudge_calibration()
		else:
			clear_log()
			_panel_open = false
		_push_prompt(player, held)
		return
	if _is_wrench(held):
		_panel_open = true
		AudioMgr.play_at_var("squeak", global_position, -16.0)
		_push_prompt(player, held)
		return
	# Tap turns the dial; the run action is on a separate fixture (the big
	# button), so you can never fat-finger a treatment you didn't mean to give.
	#
	# It goes BOTH WAYS. It used to only climb and wrap at 11, which meant the
	# only route from 9 down to 4 ran 10, 11, 0, 1, 2, 3, 4 — seven stops, five
	# of them four or more off prescription, each one broadcasting to everybody
	# in the room that you had just cranked the machine to an extreme. Turning
	# a dial DOWN was the most incriminating thing in the building, and no part
	# of the interface said so.
	if Input.is_action_pressed("sprint"):
		dial = DIAL_MAX if dial <= DIAL_MIN else dial - 1
	else:
		dial = DIAL_MIN if dial >= DIAL_MAX else dial + 1
	_dial_settle = 0.0
	AudioMgr.play_at_var("tick", global_position, -14.0)
	_refresh()
	# And the prompt has to follow the dial. The interactor only pushes a prompt
	# when the thing you are looking at CHANGES, so the readout for the single
	# most important control in the game sat frozen on whatever it said when you
	# walked up — you were setting a number while being shown a different one.
	_push_prompt(player)

## A setting is what the dial is left on, not everything it passed over.
##
## The event used to fire on every single click. Nobody in a real room reacts to
## a dial sweeping past a number; they react to where it stops. Announcing every
## intermediate value meant a player who overshot by one and corrected had
## published two extreme readings instead of none.
func _push_prompt(player, held = null) -> void:
	var pr := _prompt_for(player, held)
	EventBus.interact_prompt.emit(String(pr[0]), String(pr[1]))

func _process(delta: float) -> void:
	# A panel left hanging open is a panel somebody will notice. It shuts itself
	# once you have walked away from it.
	if _panel_open:
		var pl = get_tree().get_first_node_in_group("player")
		if pl == null or pl.global_position.distance_to(global_position) > 3.2:
			_panel_open = false
	if _dial_settle >= 0.7:
		return
	_dial_settle += delta
	if _dial_settle < 0.7:
		return
	if dial == _announced_dial:
		return
	_announced_dial = dial
	if absi(dial - prescribed) < 4:
		return
	# Leaving it on an extreme is a visible, physical act. Being seen doing it is
	# the single most direct way to get caught.
	emit_event("machine_extreme_dial", 0.62, ["machine", "treatment"], "equipment_variance",
		"set the %s to %d" % [fixture_name, dial])

func set_prescribed_for(p) -> void:
	if p == null:
		return
	# Every condition has a by-the-book setting. It is on the chart. Deviating
	# from it is trivially easy and entirely on you.
	prescribed = 3 + (hash(p.condition_id) % 5)
	_prescribed_for = p.id
	_refresh()

func _nearby_patient(_player):
	var best = null
	var best_d := 3.4
	for n in get_tree().get_nodes_in_group("patient_npc"):
		var d: float = n.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n.get("data")
	# Machines that live outside the wards — the treatment bay, and Radiology —
	# treat whoever has been WHEELED to them, so the by-the-book setting has to
	# follow the patient in. Without this the readout showed a prescribed value
	# belonging to nobody present, which quietly made the dial meaningless in
	# exactly the two rooms built around it.
	if best != null and String(best.id) != _prescribed_for:
		set_prescribed_for(best)
	return best

# ------------------------------------------------------------------ running
## Apply the machine's effect to a patient. Returns a result dictionary that the
## treatment system turns into recovery, complications and evidence.
func run_cycle(p) -> Dictionary:
	if p == null:
		return {}
	running = true
	AudioMgr.play_at("machine_on" if absi(dial - prescribed) < 4 else "machine_bad",
		global_position, -6.0)

	var deviation := dial - prescribed
	var abs_dev: int = absi(deviation)
	var band := "normal"
	if abs_dev >= 5: band = "extreme"
	elif abs_dev >= 3: band = "high"
	elif abs_dev >= 1: band = "slight"

	var correct: bool = DB.is_correct_treatment(p.condition_id, treatment_id)
	var spec: Dictionary = DB.treatment(treatment_id)
	var base: float = float(spec.get("effect", 0.2)) if correct else float(spec.get("wrong", 0.0))

	# Deviation scales the benefit down and, past a point, inverts it. The curve
	# is deliberately smooth so there is no obvious cliff to memorise.
	var effect_scale := 1.0 - float(abs_dev) * 0.28
	var result := {
		"treatment_id": treatment_id,
		"recovery": base * effect_scale * calibration,
		"band": band,
		"deviation": deviation,
		"complication": "",
		"cover": "equipment_variance",
		"visual": 0.0,
		"correct": correct,
	}

	match band:
		"normal":
			result["visual"] = 0.0
		"slight":
			result["visual"] = 0.05
			if RNG.chance("machine_comp", 0.18):
				result["complication"] = _complication_for()
		"high":
			result["visual"] = 0.3
			if RNG.chance("machine_comp", 0.62):
				result["complication"] = _complication_for()
		"extreme":
			result["visual"] = 0.55
			result["complication"] = _complication_for()

	# Miscalibration quietly steals effectiveness on every single cycle and looks
	# exactly like a machine that needs servicing — because it is one.
	if calibration < 0.9 and RNG.chance("machine_cal", 0.3):
		result["complication"] = _complication_for()

	_write_log(p, deviation)
	running = false
	return result

## What each machine goes wrong AS. Data rather than a match statement so a test
## can read it: a complication no source can produce is dead content, and it
## would never show up as anything except a thing that never happened.
const COMPLICATION_POOLS := {
	"": ["ambient_dread", "rebound_hiccups", "ferrous_aura",
		"post_percussive_ringing", "reactive_shivers", "gravitational_relapse"],
	"machine_humour": ["rebound_hiccups", "ambient_dread", "chart_fatigue",
		"escalating_politeness"],
	"machine_vibe": ["gravitational_relapse", "reactive_shivers", "secondary_beige",
		"residual_hum"],
	"machine_dread": ["ambient_dread", "nocturnal_confusion", "ferrous_aura",
		"delayed_reaction"],
	"machine_imaging": ["residual_hum", "sympathetic_draft", "spectral_itch"],
}

func _complication_for() -> String:
	var pool: Array = COMPLICATION_POOLS.get(machine_id, COMPLICATION_POOLS[""])
	return String(RNG.pick("machine_comp_pick", pool))

# ------------------------------------------------------------------ the log
func _write_log(p, deviation: int) -> void:
	log_entries.append({
		"time": GameState.career_minutes, "day": GameState.day,
		"patient": p.id, "patient_name": p.display_name,
		"dial": dial, "prescribed": prescribed, "deviation": deviation,
	})

## Entries an auditor would flag. This is the paper trail your dial leaves.
func suspicious_log_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log_entries:
		if absi(int(e["deviation"])) >= 3:
			out.append(e)
	return out

func clear_log() -> void:
	log_cleared_count += 1
	var n := log_entries.size()
	log_entries.clear()
	# Wiping a device log is not deniable. It is the act of someone with
	# something to hide, and every investigator in the game knows it.
	emit_event("machine_log_cleared", 0.8, ["machine", "records", "coverup"], "",
		"wiped %d entries from the %s log" % [n, fixture_name])
	GameState.add_heat(0.04, "machine log wiped")

# ------------------------------------------------------------------ calibration
func open_panel() -> void:
	_panel_open = true

func close_panel() -> void:
	_panel_open = false

func _nudge_calibration() -> void:
	calibration = clampf(calibration - 0.12, 0.3, 1.2)
	AudioMgr.play_at_var("squeak", global_position, -12.0)
	emit_event("machine_miscalibrated", 0.5, ["machine", "sabotage"], "equipment_variance",
		"adjusted the calibration screw on the %s" % fixture_name)

func is_miscalibrated() -> bool:
	return calibration < 0.9

func to_dict() -> Dictionary:
	return {"dial": dial, "cal": calibration, "log": log_entries, "cleared": log_cleared_count}

func from_dict(d: Dictionary) -> void:
	dial = int(d.get("dial", 5))
	calibration = float(d.get("cal", 1.0))
	log_entries.clear()
	for e in d.get("log", []):
		log_entries.append(e)
	log_cleared_count = int(d.get("cleared", 0))
	_refresh()
