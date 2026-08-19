class_name Prop
extends RigidBody3D
## A physics object. Everything you can pick up, knock over, throw at a wall, or
## leave somewhere incriminating is one of these.
##
## Props are the distraction economy: noise pulls NPC attention, and NPC
## attention is the resource you are actually managing all shift.

@export var item_id := "prop"
@export var display := "Thing"
## Shown under the interaction prompt.
@export var blurb := ""
@export var fragile := false
@export var breaks_above := 4.0        ## impact speed that shatters it
@export var noisy := true
@export var noise_radius := 11.0
## If set, an NPC that sees this lying around records evidence with this tag.
@export var incriminating_tag := ""
@export var incriminating_weight := 0.0
## Consumable contents (medicine, dread, mop water). Label can lie about it.
@export var contents := ""
@export var label := ""

var broken := false
var _last_speed := 0.0
var _impact_cooldown := 0.0
var _mesh_root: Node3D = null

func _ready() -> void:
	add_to_group("prop")
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	_mesh_root = get_node_or_null("Mesh")

func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	_last_speed = linear_velocity.length()

func get_item_id() -> String: return item_id
func display_name() -> String: return label if label != "" else display

func prompt(_player) -> Array:
	var sub := blurb
	if label != "" and label != display:
		sub = "Labelled: %s" % label
	return ["Pick up %s" % display_name(), sub]

# ------------------------------------------------------------------ decanting
## Holding one container and looking at another lets you move what is inside
## from one to the other, leaving both labels exactly where they were.
##
## This is the substitution verb made physical: no menu, no confirmation, just
## two objects and whoever happens to be in the room.
func prompt_with_item(_player, held) -> Array:
	if held == null or held == self:
		return ["", ""]
	if not (held is Prop):
		return ["", ""]
	var other: Prop = held
	if other.contents == "" or contents == other.contents:
		return ["", ""]
	if not _accepts_contents():
		return ["", ""]
	return ["Decant %s into %s" % [Items.substance_name(other.contents), display_name()],
		"the label stays as it is"]

func use_seconds(_player, held) -> float:
	if held is Prop and (held as Prop).contents != "" and _accepts_contents():
		return 1.4
	return 0.0

func _accepts_contents() -> bool:
	return item_id in ["syringe", "iv_bag", "pill_bottle", "bucket", "coffee", "dread_canister"]

func interact(_player, held) -> void:
	if held == null or not (held is Prop):
		return
	var other: Prop = held
	if other.contents == "" or not _accepts_contents():
		return
	var moved := other.contents
	swap_contents(moved)
	AudioMgr.play_at_var("squeak", global_position, -16.0, 0.2)
	EventBus.toast.emit("%s now contains %s. It still says %s." % [
		display, Items.substance_name(moved), label if label != "" else "nothing"], "info")

func _on_body_entered(_body: Node) -> void:
	if _impact_cooldown > 0.0:
		return
	var speed := _last_speed
	if speed < 1.2:
		return
	_impact_cooldown = 0.12
	var loud := clampf(speed / 8.0, 0.1, 1.0)
	if noisy:
		AudioMgr.play_at_var("clatter" if not fragile else "glass", global_position, -20.0 + loud * 12.0)
		_emit_noise(loud)
	if fragile and speed > breaks_above and not broken:
		_break()

func _emit_noise(loud: float) -> void:
	# Noise is loud but INNOCENT: audio_weight is ~0, so it never incriminates
	# you directly. What it does is move NPCs, which is far more useful.
	WorldEvent.new("prop_noise", "").at(global_position, _room()) \
		.heard(0.0, noise_radius * (0.5 + loud)) \
		.tag("noise").says("%s clattered" % display_name()).emit()

func _break() -> void:
	broken = true
	AudioMgr.play_at("glass", global_position, -6.0)
	GameState.stats.items_broken += 1
	EventBus.item_broke.emit(self)
	# Breaking hospital property is a facilities expense and a small reputational
	# ding, but it is not evidence of fraud — which makes it a cheap distraction.
	# A broken thing on the floor is a mess, and mess is a real number that four
	# separate rules read — comfort, the room's complaint list, whether a fault
	# is plausible, and the environmental complication roll. Nothing had ever
	# called soil() or clean(), so cleanliness sat at exactly 1.0 for every room
	# in the building for the entire game and all four read a spotless hospital.
	var h = get_tree().get_first_node_in_group("hospital")
	var r = h.room(h.room_at(global_position)) if h != null else null
	if r != null:
		r.soil(0.18 if fragile else 0.09)
	WorldEvent.new("prop_broken", "player").at(global_position, _room()) \
		.heard(0.05, noise_radius * 1.6).tag("mess").tag("facilities") \
		.says("%s broke" % display_name()).emit()
	if _mesh_root:
		for c in _mesh_root.get_children():
			if c is MeshInstance3D:
				var m := (c as MeshInstance3D).get_active_material(0)
				if m is StandardMaterial3D:
					var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.albedo_color = dup.albedo_color.darkened(0.45)
					(c as MeshInstance3D).material_override = dup
		_mesh_root.scale = Vector3(1.0, 0.35, 1.0)
	freeze = false

func _room() -> String:
	var h := get_tree().get_first_node_in_group("hospital")
	if h and h.has_method("room_at"):
		return h.room_at(global_position)
	return ""

func on_grabbed(_player) -> void:
	if incriminating_tag != "":
		# Picking up something you shouldn't be holding is itself observable.
		WorldEvent.new("handling_" + incriminating_tag, "player") \
			.at(global_position, _room()).seen(incriminating_weight * 0.5) \
			.tag(incriminating_tag).says("handling %s" % display_name()).emit()

func on_dropped(_player) -> void: pass

func on_thrown(_player) -> void:
	WorldEvent.new("prop_thrown", "player").at(global_position, _room()) \
		.seen(0.12).tag("chaos").says("threw %s" % display_name()).emit()

## Swap what a container actually holds while leaving the label alone. This is
## the single most useful verb in the game and it is two lines of code.
func swap_contents(new_contents: String) -> void:
	contents = new_contents
	WorldEvent.new("contents_swapped", "player").at(global_position, _room()) \
		.seen(0.55).tag("substitution").cover("equipment_variance") \
		.says("swapped the contents of %s" % display_name()).emit()

func relabel(new_label: String) -> void:
	label = new_label
	WorldEvent.new("relabelled", "player").at(global_position, _room()) \
		.seen(0.5).tag("substitution").cover("administrative") \
		.says("relabelled %s" % display_name()).emit()

## True when the label no longer matches reality — what an observant nurse spots.
func is_mislabelled() -> bool:
	return contents != "" and label != "" and not label.to_lower().contains(contents.to_lower())
