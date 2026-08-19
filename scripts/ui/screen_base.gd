class_name ScreenBase
extends Control
## Shared chrome for modal screens.

var ctx: Dictionary = {}
var ui = null
var body: VBoxContainer = null

func shell(width: float, height: float, heading: String, subheading := "") -> VBoxContainer:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background())
	var panel := UIKit.center_panel(width, height)
	add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	if heading != "":
		v.add_child(UIKit.title(heading, 26, UIKit.ACCENT))
	if subheading != "":
		v.add_child(UIKit.label(subheading, 14, UIKit.INK_DIM))
	if heading != "":
		v.add_child(UIKit.rule())
	body = v
	return v

func close() -> void:
	if ui:
		ui.close()

func patient_system():
	return get_tree().get_first_node_in_group("patient_system")

func records():
	return get_tree().get_first_node_in_group("records_system")

func suspicion():
	return get_tree().get_first_node_in_group("suspicion_system")

func shift_system():
	return get_tree().get_first_node_in_group("shift_system")

func player():
	return get_tree().get_first_node_in_group("player")

## Rebuild the whole screen in place — simpler and less bug-prone than trying to
## patch individual widgets after an action changes the underlying data.
func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	body = null
	call_deferred("_build")

func _ready() -> void:
	_build()

func _build() -> void:
	pass
