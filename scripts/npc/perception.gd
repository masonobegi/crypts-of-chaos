class_name NPCPerception
extends Node
## Decides whether this character actually noticed a thing that happened.
##
## Perception is where the stealth game lives. Whether you got away with it
## depends on angle, distance, line of sight, whether a door was shut, what the
## witness was busy doing, and whether something loud just happened somewhere
## else — all of which are things you can manipulate on purpose.

const FOV_DEG := 112.0
const SIGHT_RANGE := 13.0
const CLOSE_RANGE := 3.0

var body: NPCBody = null
## 0..1. Drops while the character is absorbed in a task or has just been
## distracted by a noise; this is the window a thrown bedpan buys you.
var attention := 1.0
var _distraction := 0.0
## Where they are currently looking, if they are deliberately watching something.
var focus: Vector3 = Vector3.ZERO
var has_focus := false

func setup(p_body: NPCBody) -> void:
	body = p_body

func _process(delta: float) -> void:
	_distraction = maxf(0.0, _distraction - delta * 0.35)
	attention = clampf(1.0 - _distraction, 0.15, 1.0)

## Called when something loud happens elsewhere — they look away from you.
func distract(strength: float) -> void:
	_distraction = clampf(_distraction + strength, 0.0, 0.9)

func eye_position() -> Vector3:
	return body.head_position() if body else Vector3.ZERO

func can_see(target: Vector3, ignore_fov := false) -> bool:
	if body == null:
		return false
	var eye := eye_position()
	var to := target - eye
	var dist := to.length()
	if dist > SIGHT_RANGE:
		return false
	if not ignore_fov and dist > CLOSE_RANGE:
		var forward := -body.global_transform.basis.z
		var ang := rad_to_deg(forward.angle_to(Vector3(to.x, 0, to.z).normalized()))
		if ang > FOV_DEG * 0.5:
			return false
	return has_line_of_sight(target)

## Walls and CLOSED DOORS block sight. Doors are on the vision-blocker layer
## precisely so that shutting one behind you is a real mechanic.
func has_line_of_sight(target: Vector3) -> bool:
	if body == null:
		return false
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye_position(), target)
	q.collision_mask = 32          # vision_blocker
	q.exclude = [body.get_rid()]
	return space.intersect_ray(q).is_empty()

func can_hear(pos: Vector3, radius: float) -> bool:
	if body == null or radius <= 0.0:
		return false
	return body.global_position.distance_to(pos) <= radius

func same_room(room_key: String) -> bool:
	return body != null and room_key != "" and body.current_room() == room_key

## Evaluate one world event. Returns an empty dict if it went unnoticed.
## `quality` folds distance, angle, attention and the character's own observance
## into how certain they are about what they saw.
func evaluate(evt: WorldEvent) -> Dictionary:
	if body == null or body.mind == null:
		return {}
	var mind := body.mind
	var observance: float = mind.observance * attention

	# --- sight
	if evt.visual_weight > 0.0 and can_see(evt.pos):
		var dist := body.global_position.distance_to(evt.pos)
		var proximity := clampf(1.0 - dist / SIGHT_RANGE, 0.1, 1.0)
		var quality := clampf(observance * (0.45 + 0.55 * proximity), 0.0, 1.0)
		# An unobservant person standing right next to you still notices; an
		# observant one across the ward might not. Roll, don't threshold.
		if RNG.randf_s("perceive_%s" % mind.id) < quality + 0.15:
			return {
				"source": Evidence.Source.WITNESSED,
				"weight": evt.visual_weight,
				"certainty": clampf(quality + 0.2, 0.15, 1.0),
			}

	# --- hearing (rarely incriminating on its own, but it moves people)
	if evt.hear_radius > 0.0 and can_hear(evt.pos, evt.hear_radius):
		distract(0.55)
		if body.has_method("on_heard_noise"):
			body.call("on_heard_noise", evt)
		if evt.audio_weight > 0.0:
			return {
				"source": Evidence.Source.HEARD,
				"weight": evt.audio_weight,
				"certainty": clampf(observance * 0.7, 0.1, 0.85),
			}

	# --- ambient: some things you just notice by being in the room
	if evt.ambient and same_room(evt.room):
		return {
			"source": Evidence.Source.WITNESSED,
			"weight": evt.visual_weight * 0.6,
			"certainty": clampf(observance * 0.8, 0.1, 0.9),
		}
	return {}

## Is this character currently able to see the player? Used for the "can I do
## this right now" read that the HUD surfaces as a watched-by indicator.
func sees_player() -> bool:
	var p = body.get_tree().get_first_node_in_group("player") if body else null
	if p == null:
		return false
	return can_see(p.global_position + Vector3(0, 1.5, 0))
