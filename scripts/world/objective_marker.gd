class_name ObjectiveMarker
extends Node3D
## Where the current objective actually IS.
##
## The objective was one line of text at the top of the screen — "Check your
## list. It's on the board by the treatment bay" — and the first person to play
## this got lost inside two minutes. Telling somebody the name of a room in a
## building they have never been in is not direction.
##
## A soft chevron over the target, visible through walls, with the distance
## under it, fading out as you arrive. Deliberately restrained: it is a hint,
## not a quest arrow, and it disappears the moment you are close enough to read
## the thing it is pointing at.

const FADE_NEAR := 3.2      ## fully faded by here
const FADE_FAR := 6.0       ## fully solid beyond here

var target: Vector3 = Vector3.INF
var label_text := ""

var _chevron: MeshInstance3D = null
var _label: Label3D = null
var _dist: Label3D = null
var _bob := 0.0

func _ready() -> void:
	add_to_group("objective_marker")
	# Always on top: the whole point is being findable from the other end of a
	# corridor, through a wall, in a building you do not know yet.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.86, 0.78)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 8

	_chevron = MeshInstance3D.new()
	_chevron.mesh = Build.rbox_mesh(Vector3(0.30, 0.30, 0.30), 0.06)
	_chevron.material_override = mat
	_chevron.rotation = Vector3(0.0, PI * 0.25, PI * 0.25)
	add_child(_chevron)

	_label = Build.label3d("", 0.16, Color(0.90, 0.98, 0.96))
	_label.position = Vector3(0, 0.42, 0)
	_label.no_depth_test = true
	_label.render_priority = 9
	add_child(_label)

	_dist = Build.label3d("", 0.115, Color(0.55, 0.86, 0.82))
	_dist.position = Vector3(0, 0.24, 0)
	_dist.no_depth_test = true
	_dist.render_priority = 9
	add_child(_dist)

	EventBus.objective_target_changed.connect(_on_target)
	visible = false

func _on_target(pos: Vector3, text: String) -> void:
	target = pos
	label_text = text
	if _label:
		_label.text = text
	visible = _has_target()

func _has_target() -> bool:
	return target.is_finite()

func _process(delta: float) -> void:
	if not _has_target():
		visible = false
		return
	global_position = target
	_bob += delta * 2.2
	if _chevron:
		_chevron.position.y = sin(_bob) * 0.07
		_chevron.rotation.y += delta * 1.1

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var d: float = player.global_position.distance_to(target)
	# Fades out as you arrive rather than switching off, so it never pops.
	var alpha: float = clampf((d - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0.0, 1.0)
	visible = alpha > 0.02
	if not visible:
		return
	if _dist:
		_dist.text = "%dm" % int(round(d))
		_dist.modulate.a = alpha
	if _label:
		_label.modulate.a = alpha
	if _chevron:
		var m := _chevron.material_override as StandardMaterial3D
		if m:
			m.albedo_color.a = alpha * 0.9
