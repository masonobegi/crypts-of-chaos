class_name Upgrades
extends RefCounted
## Hospital and personal upgrades.
##
## The design rule: roughly half of these make you MORE money and MORE visible.
## Security cameras are the clearest case — they raise hospital reputation,
## which brings better-insured patients, and they also watch you all day.
##
## Costs are scaled against a profitable ward clearing roughly $15k/day. The
## balance harness originally bought the entire catalogue inside twenty days,
## which left the back half of a career with nothing to spend on; the whole list
## is now about a full 30-day career of total reinvestment.

const CATALOGUE := {
	# ---------------------------------------------------------- pure upside
	"better_beds": {
		"name": "Adjustable Beds", "cost": 8400, "tier": 1,
		"desc": "Patients recover slightly faster and complain less.",
		"note": "Comfort improves satisfaction across the ward.",
	},
	"coffee_machine": {
		"name": "Decent Coffee Machine", "cost": 3600, "tier": 1,
		"desc": "The nurses' station gets a real coffee machine.",
		"note": "Staff spend more time at the station. Fewer eyes in the wards.",
	},
	"admin_assistant": {
		"name": "Ward Clerk", "cost": 13500, "tier": 2,
		"desc": "Someone else does the filing.",
		"note": "Undocumented complications get chased up automatically — fewer omissions, but the clerk notices patterns.",
	},
	"private_rooms": {
		"name": "Convert to Private Rooms", "cost": 23000, "tier": 2,
		"desc": "Doors, curtains, dignity.",
		"note": "Higher billing. Far fewer witnesses. The single best purchase in the game and everyone knows it.",
	},
	"vip_suite": {
		"name": "VIP Suite (Room 105)", "cost": 36000, "tier": 3,
		"desc": "Room 105 becomes something you'd photograph.",
		"note": "Attracts platinum patients. Attracts platinum scrutiny.",
	},
	"diagnostics": {
		"name": "Advanced Diagnostic Bench", "cost": 24500, "tier": 2,
		"desc": "Vitals readouts get noticeably less noisy.",
		"note": "You can finally see what you're doing. So can everyone reviewing it afterwards.",
	},
	"security_cameras": {
		"name": "Corridor Cameras", "cost": 16500, "tier": 2,
		"desc": "Cameras in the corridor and lobby.",
		"note": "Hospital reputation up. Anything you do in a covered area is recorded — and recordings do not forget.",
	},
	"maintenance_contract": {
		"name": "Equipment Service Contract", "cost": 11000, "tier": 2,
		"desc": "Machines get serviced weekly.",
		"note": "Fewer breakdowns. Miscalibration gets found and fixed — and reported.",
	},
	"legal_retainer": {
		"name": "Legal Retainer", "cost": 19500, "tier": 3,
		"desc": "A solicitor who answers the phone.",
		"note": "Investigations need substantially more to stick.",
	},
	"union_rep_lunch": {
		"name": "Buy The Ward Lunch", "cost": 2400, "tier": 1,
		"desc": "Every week. Forever.",
		"note": "Staff trust up. Staff are less likely to talk to investigators.",
	},
	"shred_bin": {
		"name": "Confidential Waste Contract", "cost": 6800, "tier": 1,
		"desc": "A proper locked bin for confidential waste.",
		"note": "Destroying paperwork stops looking like destroying paperwork.",
	},
	# ---------------------------------------------------------- departments
	"dept_emergency": {
		"name": "Open Emergency Intake", "cost": 28000, "tier": 2,
		"desc": "The ward starts taking emergency admissions.",
		"note": "Short stays, enormous day rates, and patients who arrive MID-SHIFT with no warning. Chaos is profitable and chaos is witnessed.",
	},
	"dept_radiology": {
		"name": "Radiology Bench", "cost": 32000, "tier": 3,
		"desc": "An imaging bench in the treatment bay.",
		"note": "Imaging shows a patient's true condition instead of noisy vitals — and writes what it saw into the record, permanently.",
	},
	"dept_psych": {
		"name": "Psychiatric Liaison", "cost": 25000, "tier": 2,
		"desc": "Long, lucrative admissions that respond to comfort rather than kit.",
		"note": "These patients recover on environment and satisfaction, not treatment. They are also the most observant people in the building.",
	},
	"records_consultant": {
		"name": "Records Consultant", "cost": 38000, "tier": 3,
		"desc": "A specialist who tidies the record at the end of every shift.",
		"note": "Undocumented complications get a plausible cause filed automatically. She is very good, very expensive, and she keeps her own notes.",
	},
	"board_appointment": {
		"name": "Seat On The Board", "cost": 62000, "tier": 3,
		"desc": "You are now partly the management you have been avoiding.",
		"note": "Profit share up substantially. Government scrutiny grows faster, and the board reads its own audit reports.",
	},
	"second_opinion_policy": {
		"name": "Second Opinion Policy", "cost": 13000, "tier": 2,
		"desc": "Every extended stay gets a colleague's sign-off.",
		"note": "Hospital reputation up. A second doctor now reads all of your extensions.",
	},
}

static func spec(id: String) -> Dictionary:
	return CATALOGUE.get(id, {})

static func cost(id: String) -> int:
	return int(CATALOGUE.get(id, {}).get("cost", 0))

static func available() -> Array[String]:
	var out: Array[String] = []
	for id in CATALOGUE:
		if GameState.has_upgrade(id):
			continue
		out.append(id)
	return out

static func can_afford(id: String) -> bool:
	return GameState.hospital_money >= cost(id)

static func purchase(id: String) -> bool:
	if GameState.has_upgrade(id) or not can_afford(id):
		return false
	GameState.add_hospital(-cost(id), "upgrade: %s" % CATALOGUE[id]["name"])
	GameState.owned_upgrades.append(id)
	_apply(id)
	EventBus.upgrade_purchased.emit(id)
	EventBus.toast.emit("Installed: %s" % CATALOGUE[id]["name"], "good")
	return true

static func _apply(id: String) -> void:
	match id:
		"better_beds":
			GameState.adjust_rep("patient_sat", 0.08)
		"coffee_machine":
			GameState.adjust_rep("staff_trust", 0.05)
		"private_rooms":
			GameState.adjust_rep("hospital", 0.06)
		"vip_suite":
			GameState.adjust_rep("hospital", 0.1)
			GameState.adjust_rep("gov_scrutiny", 0.04)
		"security_cameras":
			GameState.adjust_rep("hospital", 0.09)
		"legal_retainer":
			GameState.adjust_rep("gov_scrutiny", -0.03)
		"union_rep_lunch":
			GameState.adjust_rep("staff_trust", 0.14)
		"second_opinion_policy":
			GameState.adjust_rep("hospital", 0.08)
			GameState.adjust_rep("insurer_trust", 0.06)
		"diagnostics":
			GameState.adjust_rep("doctor", 0.05)
		"admin_assistant":
			GameState.adjust_rep("insurer_trust", 0.05)
		"maintenance_contract":
			GameState.adjust_rep("hospital", 0.04)
		"dept_emergency":
			GameState.unlocked_departments.append("emergency")
			GameState.adjust_rep("hospital", 0.07)
		"dept_radiology":
			GameState.unlocked_departments.append("radiology")
			GameState.adjust_rep("doctor", 0.06)
			GameState.adjust_rep("insurer_trust", 0.05)
		"dept_psych":
			GameState.unlocked_departments.append("psych")
			GameState.adjust_rep("hospital", 0.05)
		"records_consultant":
			GameState.adjust_rep("insurer_trust", 0.08)
		"board_appointment":
			GameState.bonus_rate += 0.06
			GameState.adjust_rep("hospital", 0.1)
			GameState.adjust_rep("gov_scrutiny", 0.08)

# ---------------------------------------------------------------- live effects
## Multiplier on how noisy vitals readouts are.
static func vitals_noise_scale() -> float:
	return 0.45 if GameState.has_upgrade("diagnostics") else 1.0

## Extra recovery for everyone, from comfort upgrades.
static func recovery_bonus() -> float:
	return 0.06 if GameState.has_upgrade("better_beds") else 0.0

## Private rooms mean fewer people can see into a ward.
static func witness_scale() -> float:
	return 0.55 if GameState.has_upgrade("private_rooms") else 1.0

## Cameras record the corridor and lobby regardless of who is standing there.
static func camera_rooms() -> Array[String]:
	if GameState.has_upgrade("security_cameras"):
		return ["corridor", "lobby"]
	return []

static func investigation_threshold_scale() -> float:
	return 1.45 if GameState.has_upgrade("legal_retainer") else 1.0

static func staff_silence_bonus() -> float:
	return 0.2 if GameState.has_upgrade("union_rep_lunch") else 0.0

static func shredding_is_normal() -> bool:
	return GameState.has_upgrade("shred_bin")
