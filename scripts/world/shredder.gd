class_name Shredder
extends Fixture
## Destroys paperwork. Fast, permanent, and the most quietly damning act
## available: a missing chart is worse than a bad chart, and everyone knows it.

var shredded_count := 0

func build() -> void:
	fixture_name = "Document Shredder"
	var body := Build.mat(Color(0.24, 0.26, 0.30))
	setup_body(Vector3(0.5, 0.8, 0.4), [
		{"mesh": Build.box_mesh(Vector3(0.5, 0.5, 0.4)), "mat": Build.mat(Color(0.35, 0.36, 0.38)), "pos": Vector3(0, 0.25, 0)},
		{"mesh": Build.box_mesh(Vector3(0.52, 0.3, 0.42)), "mat": body, "pos": Vector3(0, 0.65, 0)},
		{"mesh": Build.box_mesh(Vector3(0.34, 0.02, 0.05)), "mat": Build.mat(Color(0.05, 0.05, 0.05)), "pos": Vector3(0, 0.81, 0)},
	], Vector3(0, 0.4, 0))

func prompt(_player, held = null) -> Array:
	return ["Document Shredder", "hold paperwork and press [E]"]

func prompt_with_item(_player, held) -> Array:
	if held and _is_paper(held):
		return ["Shred %s" % held.display_name(), "this cannot be undone"]
	return ["Document Shredder", "that will not fit"]

func use_seconds(_player, held) -> float:
	return 1.1 if (held and _is_paper(held)) else 0.0

func _is_paper(held) -> bool:
	if held == null:
		return false
	var id: String = String(held.get_item_id()) if held.has_method("get_item_id") else ""
	return id in ["chart", "blank_form", "incident_report", "clipboard_blank"]

func interact(player, held) -> void:
	if not _is_paper(held):
		return
	var what: String = held.display_name()
	var pid := ""
	if held.has_method("get_patient_id"):
		pid = String(held.call("get_patient_id"))
	if player and player.interactor:
		player.interactor.force_release()
	held.queue_free()
	shredded_count += 1
	AudioMgr.play_at("clatter", global_position, -4.0, 0.6)

	# Loud, visible, and impossible to explain. The noise radius is generous on
	# purpose — shredding is meant to be a risk, not a get-out-of-jail button.
	var e := WorldEvent.new("document_shredded", "player").at(global_position, room_key) \
		.about(pid).seen(0.85).heard(0.35, 14.0).tag("records").tag("coverup") \
		.says("shredded %s" % what)
	e.emit()
	GameState.add_heat(0.05, "document shredded")
	GameState.stats.forged_entries += 1
