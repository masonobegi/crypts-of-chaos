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
		{"mesh": Build.box_mesh(Vector3(1.6, 1.9, 0.04)), "mat": Build.mat(Color(0.34, 0.37, 0.40)), "pos": Vector3(0, 0.95, -0.25)},
	]
	# Dummy stock so the shelf reads as full even after you empty it.
	#
	# ALL THREE shelves, and in more than one shape. Only the bottom one was
	# ever filled, so a supply room photographed as three blank white cabinets
	# — which is a strange look for the room the whole game sends you to for
	# equipment. Boxes, cartons and bottles, sized and coloured off the index so
	# it is the same shelf every run and no RNG stream is disturbed.
	const CARTONS := [
		Color(0.86, 0.72, 0.46), Color(0.72, 0.80, 0.86), Color(0.84, 0.56, 0.50),
		Color(0.64, 0.78, 0.62), Color(0.90, 0.86, 0.74), Color(0.58, 0.62, 0.74),
	]
	for row in 3:
		var y := 0.64 + 0.50 * float(row)
		for i in 6:
			var n := row * 6 + i
			var col: Color = CARTONS[n % CARTONS.size()]
			if n % 5 == 3:
				# A bottle, standing. One round thing per shelf is enough to stop
				# the whole unit reading as a wall of identical cubes.
				parts.append({
					"mesh": Build.cyl_mesh(0.055, 0.26, 10),
					"mat": Build.mat(col.lightened(0.10), 0.35),
					"pos": Vector3(-0.56 + 0.224 * float(i), y + 0.02, 0.02),
				})
				continue
			var w := 0.17 + 0.04 * float(n % 3)
			var tall := 0.19 + 0.05 * float((n + 1) % 3)
			parts.append({
				"mesh": Build.box_mesh(Vector3(w, tall, 0.28)),
				"mat": Build.mat(col),
				"pos": Vector3(-0.56 + 0.224 * float(i), y - 0.11 + tall * 0.5, 0.02),
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
		"[E] take   [Shift] next  (%d of %d)" % [(_index % items.size()) + 1, items.size()]]

## Tap takes; Shift+E cycles. One key, two verbs, and neither of them is a hold.
##
## This used to be "tap takes, HOLD cycles", which could not work and meant no
## shelf in the building ever dispensed anything. `use_seconds()` returned 0.6
## whenever there was more than one item — every shelf — so the interactor's tap
## branch (`hold_time <= 0.0`) was unreachable, and the only surviving route was
## the hold-completion call, which fires while E is still physically down. That
## made `Input.is_action_pressed("interact")` true, so it cycled and returned.
## `_dispense()` was dead code on every shelf. You could not pick up a syringe,
## an IV bag, a compress or a splint — which is to say you could not treat
## anybody — and the tutorial cheerfully sent you to the supply room to try.
func use_seconds(_player, _held) -> float:
	return 0.0

func interact(player, _held) -> void:
	if items.is_empty():
		return
	if Input.is_action_pressed("sprint") and items.size() > 1:
		_index += 1
		AudioMgr.play_at_var("tick", global_position, -14.0)
		EventBus.interact_prompt.emit(prompt(player)[0], prompt(player)[1])
		return
	_dispense(player, items[_index % items.size()])

func _dispense(player, id: String) -> void:
	var p := Items.spawn(id)
	# During a shortage, pharmacy sends substitutes. Sometimes what comes off
	# the shelf is not what the label says — and today, that is genuinely not
	# your fault, which is exactly why a shortage day is worth waiting for.
	if GameState.flag("supply_shortage", false) and p.contents != "" \
			and RNG.chance("shortage_swap", 0.35):
		p.contents = "saline_plus"
		EventBus.toast.emit("Pharmacy substituted. Again.", "info")
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
