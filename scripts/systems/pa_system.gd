class_name PASystem
extends Node
## The overhead announcements.
##
## Mostly atmosphere, but not only: the tannoy is the cheapest possible way to
## tell the player that the institution has noticed something, and it does it
## without a UI element. When heat is high the announcements get pointed, and
## when an inspection is on the floor everybody starts being told to look busy.

const MIN_GAP := 22       ## in-game minutes
const MAX_GAP := 55

const IDLE_LINES := [
	"Would the owner of the blue estate blocking the ambulance bay please move it. Again.",
	"Ward C, your dressings trolley is in the lift. The lift is between floors.",
	"A reminder that the third-floor vending machine is not a shared resource.",
	"Catering apologises for today's lunch, and for tomorrow's.",
	"Would whoever keeps setting the Vibe Stabiliser to eleven please stop.",
	"The hot tap in the staff WC is decorative.",
	"Lost property has a great many single shoes and would like fewer.",
	"Please do not race the wheelchairs. Please do not bet on the wheelchairs.",
	"Reminder: patients are not to be stored in corridors, regardless of tidiness.",
	"The suggestion box has been removed following suggestions.",
	"Would the doctor who left a bedpan on the vending machine please collect it.",
	"Meridian Mutual reminds you that every line item is a promise.",
	"Housekeeping to Room 103. Housekeeping, wherever you are, to Room 103.",
	"The fire door is not a shortcut. It is a fire door.",
	"Staff are reminded that the mortuary lift is not the goods lift.",
	"Today's mandatory training has been cancelled due to lack of interest.",
]

const INSPECTION_LINES := [
	"All staff: our visitor is on the floor. Please be excellent.",
	"Reminder to all clinicians: charts should reflect care given. Ideally today.",
	"Would all staff ensure corridors are clear. Especially that corridor.",
	"Administration thanks you in advance for a quiet, unremarkable afternoon.",
]

const HEAT_LINES := [
	"Would the duty physician please report to Administration.",
	"Administration is reviewing this week's length-of-stay figures.",
	"A reminder that all extended admissions require a documented cause.",
	"Records has requested several charts from Ward C. Several.",
	"Would the duty physician contact Administration. At their convenience. Today.",
]

const PRESS_LINES := [
	"All staff: there is press in the lobby. Smile with your whole face.",
	"Please direct all media enquiries to Administration, and then walk away.",
]

var _next_at := 0

func _ready() -> void:
	add_to_group("pa_system")
	EventBus.clock_tick.connect(_on_tick)
	EventBus.shift_started.connect(func(_d): _schedule(8))

func _schedule(gap := 0) -> void:
	if gap <= 0:
		gap = RNG.randi_range_s("pa_gap", MIN_GAP, MAX_GAP)
	_next_at = GameState.career_minutes + gap

func _on_tick(_minute: int) -> void:
	if GameState.phase != GameState.Phase.SHIFT:
		return
	if _next_at == 0:
		_schedule()
		return
	if GameState.career_minutes < _next_at:
		return
	_schedule()
	announce(_pick())

## Weighted so the tannoy reflects what is actually going on: it is the
## institution talking, and the institution has moods.
func _pick() -> String:
	var inv = get_tree().get_first_node_in_group("investigation_system")
	var inspection_visible: bool = inv != null and not inv.active_titles().is_empty()
	var weights := {
		"idle": 3.0,
		"heat": GameState.heat * 4.0,
		"inspection": 3.0 if inspection_visible else 0.0,
		"press": 2.5 if GameState.flag("press_present", false) else 0.0,
	}
	match String(RNG.pick_weighted("pa_kind", weights)):
		"heat": return String(RNG.pick("pa_heat", HEAT_LINES))
		"inspection": return String(RNG.pick("pa_insp", INSPECTION_LINES))
		"press": return String(RNG.pick("pa_press", PRESS_LINES))
	return String(RNG.pick("pa_idle", IDLE_LINES))

func announce(text: String) -> void:
	AudioMgr.play("ding", -16.0, 0.75)
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree():
		return
	EventBus.subtitle.emit("Tannoy", text, 5.5)
