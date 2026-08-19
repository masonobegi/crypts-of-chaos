class_name VitalsConsole
extends Fixture
## Bedside readout. Shows three fictional vitals, noisily. It never shows
## recovery, because a recovery percentage would turn the whole game into
## arithmetic — you are supposed to read the patient, not the number.

@export var patient_id := ""
var _screen: Label3D = null
var _refresh_accum := 0.0

func build() -> void:
	fixture_name = "Vitals Monitor"
	var case_mat := Build.mat(Color(0.22, 0.24, 0.28))
	var screen := Build.mat(Color(0.06, 0.12, 0.10), 0.15, 0.0, Color(0.06, 0.28, 0.22))
	setup_body(Vector3(0.5, 0.4, 0.16), [
		{"mesh": Build.box_mesh(Vector3(0.5, 0.4, 0.14)), "mat": case_mat},
		{"mesh": Build.box_mesh(Vector3(0.44, 0.32, 0.01)), "mat": screen, "pos": Vector3(0, 0, 0.076)},
	])
	_screen = Build.label3d("", 0.05, Color(0.55, 1.0, 0.8), false)
	_screen.position = Vector3(0, 0.02, 0.09)
	_screen.width = 460
	_screen.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_screen)
	set_process(true)

func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < 0.9:
		return
	_refresh_accum = 0.0
	_update()

func _update() -> void:
	if _screen == null:
		return
	var p = _patient()
	if p == null:
		_screen.text = "NO PATIENT\n--- --- ---"
		return
	var v: Dictionary = p.vitals()
	_screen.text = "%s\nHUM %0.0f\nSPL %0.1f\nDRD %0.0f" % [
		p.display_name.to_upper(), v["humour_balance"], v["spleen_torque"], v["ambient_dread"]]

func _patient():
	var ps = get_tree().get_first_node_in_group("patient_system")
	if ps == null:
		return null
	return ps.get_patient(patient_id)

func prompt(_player) -> Array:
	var p = _patient()
	if p == null:
		return ["Vitals Monitor", "no patient assigned"]
	var v: Dictionary = p.vitals()
	return ["%s — vitals" % p.display_name,
		"humour %0.0f · spleen torque %0.1f · dread %0.0f" % [
			v["humour_balance"], v["spleen_torque"], v["ambient_dread"]]]

func interact(_player, _held) -> void:
	var p = _patient()
	if p == null:
		return
	EventBus.request_ui.emit("vitals", {"patient_id": p.id})
