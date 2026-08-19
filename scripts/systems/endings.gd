class_name Endings
extends RefCounted
## How a career finishes. Endings are evaluated against the run's whole record,
## not a single choice, so the ending you get is a description of how you played
## rather than a menu option you picked at the end.

const ENDINGS := {
	"saint": {
		"title": "The Saint",
		"line": "You stopped. Actually stopped. The ward is the best on the floor and you still can't afford the rent.",
		"epitaph": "Beloved. Broke.",
	},
	"tycoon": {
		"title": "Hospital Tycoon",
		"line": "Nobody ever proved anything. The wing has your name on it now, which is either an honour or evidence.",
		"epitaph": "Cleared every review. Every single one.",
	},
	"medical_mafia": {
		"title": "Medical Mafia",
		"line": "It stopped being your scheme somewhere around the third nurse. The whole ward runs on it now.",
		"epitaph": "You are no longer the most corrupt person here.",
	},
	"fraud_king": {
		"title": "Fraud King",
		"line": "The billing figures are, frankly, art. Meridian Mutual has a folder with your name on it and no idea what's in it.",
		"epitaph": "Never treated anybody. Billed everybody.",
	},
	"whistleblower": {
		"title": "Whistleblower",
		"line": "You handed over everything. Including your own file. Especially your own file.",
		"epitaph": "Did the right thing, eventually, loudly.",
	},
	"prison": {
		"title": "Custodial",
		"line": "It was the machine logs. It is always the machine logs.",
		"epitaph": "Should have wiped them. Wiping them is also how they got you.",
	},
	"license_revoked": {
		"title": "Struck Off",
		"line": "You keep the debts. You do not keep the licence.",
		"epitaph": "Formerly a doctor. Currently a defendant.",
	},
	"legendary": {
		"title": "Legendary Doctor",
		"line": "Impeccable reputation. Immaculate figures. An absolutely enormous amount of fraud.",
		"epitaph": "Nobody suspected a thing, and they were all wrong.",
	},
	"bankrupt": {
		"title": "Repossessed",
		"line": "Vinnie got the car. The bank got the flat. The hospital got a two-week notice period.",
		"epitaph": "Out-earned by your own interest.",
	},
}

## Pick the ending that best describes this run. Order matters: hard failures
## first, then the interesting ones, then the defaults.
static func evaluate(stats: Dictionary) -> String:
	if GameState.sanction_level >= 9:
		return "prison"
	if GameState.sanction_level >= 8:
		return "license_revoked"
	if GameState.flag("whistleblew", false):
		return "whistleblower"
	if GameState.personal_money < -2000 or GameState.flag("evicted", false):
		return "bankrupt"

	var forged := int(stats.get("forged_entries", 0))
	var cured := int(stats.get("patients_cured", 0))
	var complications := int(stats.get("complications_caused", 0))
	var clean := int(stats.get("complications_clean", 0))
	var earned := int(stats.get("personal_earned", 0))
	var corrupt_staff := int(GameState.flag("corrupt_staff_count", 0))

	# Legendary: enormous fraud, immaculate standing. The hardest one to get.
	if forged >= 12 and GameState.rep("doctor") >= 0.75 and GameState.sanction_level == 0 \
			and GameState.heat < 0.2:
		return "legendary"
	if corrupt_staff >= 3:
		return "medical_mafia"
	if forged >= 20 and earned >= 30000:
		return "fraud_king"
	if earned >= 25000 and GameState.sanction_level <= 1:
		return "tycoon"
	if complications <= 2 and cured >= 12 and GameState.rep("patient_sat") >= 0.7:
		return "saint"
	if clean >= 10:
		return "tycoon"
	return "saint" if complications < cured else "fraud_king"

static func spec(id: String) -> Dictionary:
	return ENDINGS.get(id, ENDINGS["saint"])

## A local-news headline for the shift report. Pure streamer bait and it costs
## almost nothing to generate.
static func headline(stats: Dictionary) -> String:
	var name: String = String(stats.get("longest_stay_name", ""))
	var days: float = float(stats.get("longest_stay", 0.0))
	var pool: Array = [
		"WARD C REPORTS 'ENTIRELY NORMAL' WEEK",
		"LOCAL HOSPITAL DENIES ANYTHING AT ALL",
		"'THE MACHINE WAS LIKE THAT WHEN I GOT HERE', SAYS DOCTOR",
		"MERIDIAN MUTUAL 'LOOKING INTO IT', SAYS MERIDIAN MUTUAL",
		"ST. ARDENT'S NAMED REGION'S MOST THOROUGH HOSPITAL",
	]
	if name != "" and days > 3.0:
		pool.append("LOCAL DOCTOR SETS RECORD TREATING %s FOR %d DAYS" % [name.to_upper(), int(days)])
		pool.append("'I FEEL FINE', INSISTS %s, DAY %d" % [name.to_upper(), int(days)])
	if int(stats.get("items_broken", 0)) > 4:
		pool.append("HOSPITAL ORDERS RECORD NUMBER OF REPLACEMENT TRAYS")
	if int(stats.get("complaints", 0)) > 3:
		pool.append("COMPLAINTS UP. HOSPITAL BLAMES 'INCREASED AWARENESS OF COMPLAINTS'")
	return String(RNG.pick("headline", pool))
