class_name SupplyShelf
extends Fixture
## Dispenses items. Taking things is unremarkable; taking things you have no
## reason to need, while someone is watching, is the start of a story.

@export var items: Array[String] = []
@export var restricted := false      ## controlled stock — taking it is noteworthy

var _index := 0

func build(disp: String, stock: Array) -> void:
	fixture_name = disp
	items.clear()
	for s in stock:
		items.append(String(s))
	var frame := Build.mat(Color(0.62, 0.64, 0.66), 0.5, 0.4)
	var parts := [
		{"mesh": Build.box_mesh(Vector3(1.6, 0.06, 0.5)), "mat": frame, "pos": Vector3(0, 0.5, 0)},
		{"mesh": Build.box_mesh(Vector3(1.6, 0.06, 0.5)), "mat": frame, "pos": Vector3(0, 1.0, 0)},
		{"mesh": Build.box_mesh(Vector3(1.6, 0.06, 0.5)), "mat": frame, "pos": Vector3(0, 1.5, 0)},
		{"mesh": Build.box_mesh(Vector3(0.06, 1.9, 0.5)), "mat": frame, "pos": Vector3(-0.78, 0.95, 0)},
		{"mesh": Build.box_mesh(Vector3(0.06, 1.9, 0.5)), "mat": frame, "pos": Vector3(0.78, 0.95, 0)},
		{"mesh": Build.box_mesh(Vector3(1.6, 1.9, 0.04)), "mat": Build.mat(Color(0.5, 0.52, 0.54)), "pos": Vector3(0, 0.95, -0.25)},
	]
	# Dummy stock so the shelf reads as full even after you empty it.
	for i in 6:
		parts.append({
			"mesh": Build.box_mesh(Vector3(0.2, 0.22, 0.28)),
			"mat": Build.mat(Color(0.7 + 0.05 * float(i % 3), 0.65, 0.5)),
			"pos": Vector3(-0.55 + 0.22 * float(i), 0.64, 0.02),
		})
	setup_body(Vector3(1.7, 1.9, 0.55), parts, Vector3(0, 0.95, 0))

	var sign := Build.label3d(disp, 0.09, Color(0.9, 0.92, 0.88), false)
	sign.position = Vector3(0, 1.78, 0.3)
	add_child(sign)

func prompt(_player) -> Array:
	if items.is_empty():
		return [fixture_name, "empty"]
	var id: String = items[_index % items.size()]
	return ["Take %s" % Items.display_name(id),
		"[E] take   [hold E] next item (%d/%d)" % [(_index % items.size()) + 1, items.size()]]

func use_seconds(_player, _held) -> float:
	return 0.6 if items.size() > 1 else 0.0

## Hold cycles the shelf; tap dispenses. Two verbs, one key.
func interact(player, _held) -> void:
	if items.is_empty():
		return
	if Input.is_action_pressed("interact") and items.size() > 1:
		_index += 1
		AudioMgr.play_at_var("tick", global_position, -16.0)
		return
	_dispense(player, items[_index % items.size()])

func _dispense(player, id: String) -> void:
	var p := Items.spawn(id)
	# Parent to the hospital rather than current_scene, which is null when the
	# game is instantiated into the tree instead of loaded as the scene root.
	var parent: Node = get_tree().get_first_node_in_group("hospital")
	if parent == null:
		parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(p)
	p.global_position = global_position + Vector3(0, 1.25, 0) + global_transform.basis.z * 0.5
	AudioMgr.play_at_var("pickup", global_position, -12.0)
	if restricted:
		emit_event("took_restricted_stock", 0.35, ["supply"], "administrative",
			"took %s from restricted stock" % Items.display_name(id))
	# Put it straight in the player's hands — fumbling in a supply room is not
	# the kind of friction this game is about.
	if player and player.interactor and player.interactor.held == null:
		await get_tree().physics_frame
		if is_instance_valid(p):
			player.interactor.grab(p)
