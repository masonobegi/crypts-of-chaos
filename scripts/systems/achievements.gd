class_name Achievements
extends RefCounted
## Named things to have done, checked against the career's own statistics.
##
## Not a completion checklist. Every one of these is a SENTENCE about how
## somebody played — "you kept a man in a bed for nine days and he thanked you
## for it" is a story, "discharge 50 patients" is a chore — and the point of
## having them is that a player reads the list afterwards and recognises their
## own career in it.
##
## Deliberately evaluated from `GameState.stats` and a handful of flags rather
## than fired from inside systems. A system that has to remember to award an
## achievement is a system with an achievement bug in it; a pure read over the
## numbers cannot drift, cannot double-fire, and works on a career loaded from
## a save.
##
## `hidden` ones are not shown until earned, because their names are spoilers.

const LIST := [
	# ---- the job, done properly
	{"id": "clean_hands", "name": "Clean Hands",
	 "desc": "Finish a shift with nobody's suspicion above a murmur."},
	{"id": "textbook", "name": "Textbook",
	 "desc": "Perform a procedure well enough to be called textbook."},
	{"id": "the_round", "name": "The Round",
	 "desc": "See every patient on the ward personally in one day."},
	{"id": "sent_home", "name": "Sent Home Well",
	 "desc": "Discharge twenty patients who were genuinely better."},
	{"id": "second_opinion", "name": "Ask Somebody Else",
	 "desc": "Image a patient you had been quietly working on."},

	# ---- money
	{"id": "in_the_black", "name": "In The Black",
	 "desc": "Clear a day's debts without missing a payment."},
	{"id": "solvent", "name": "Briefly Solvent",
	 "desc": "Hold fifty thousand of your own money at once."},
	{"id": "landlord", "name": "Landlord",
	 "desc": "Bill a single patient for more than ten days."},
	{"id": "renovator", "name": "Renovator",
	 "desc": "Open every department in the building."},

	# ---- the quiet half
	{"id": "an_arrangement", "name": "An Arrangement",
	 "desc": "Have a quiet word that works."},
	{"id": "no_thank_you", "name": "Put That Away",
	 "desc": "Offer somebody money and be refused."},
	{"id": "the_whole_ward", "name": "The Whole Ward", "hidden": true,
	 "desc": "Have five members of staff on your books at once."},
	{"id": "known_risk", "name": "A Recognised Risk", "hidden": true,
	 "desc": "File an injury you caused under a cause nobody can disprove."},
	{"id": "unlucky", "name": "An Unfortunate Reaction", "hidden": true,
	 "desc": "Cause a reaction that reads on the record as bad luck."},

	# ---- the evening
	{"id": "night_shift", "name": "Moonlighting", "hidden": true,
	 "desc": "Come back from an evening out with somebody on your list."},
	{"id": "unseen", "name": "Nobody Looked Up", "hidden": true,
	 "desc": "Three evenings out, none of them seen."},
	{"id": "recognised", "name": "Do I Know You?", "hidden": true,
	 "desc": "Treat somebody who is trying to place your face."},

	# ---- the letters
	{"id": "served", "name": "A Letter Before Action",
	 "desc": "Have somebody you discharged decide to do something about it."},
	{"id": "settled", "name": "Without Admission Of Liability",
	 "desc": "Settle a claim rather than answer it."},
	{"id": "day_in_court", "name": "Day In Court",
	 "desc": "Win at trial."},
	{"id": "expensive_friend", "name": "An Expensive Friend", "hidden": true,
	 "desc": "Win a trial with counsel who spoke to the witnesses first."},
	{"id": "the_full_amount", "name": "The Full Amount",
	 "desc": "Lose at trial and pay for it."},

	# ---- careers
	{"id": "fortnight", "name": "A Fortnight",
	 "desc": "Survive fourteen days."},
	{"id": "long_service", "name": "Long Service",
	 "desc": "Survive thirty."},
	{"id": "struck_off", "name": "Struck Off",
	 "desc": "Lose your licence. It happens."},
]

static func spec(id: String) -> Dictionary:
	for a in LIST:
		if String(a["id"]) == id:
			return a
	return {}

## Everything the career currently qualifies for. A pure read: call it as often
## as you like, from anywhere, on any save.
static func earned_now() -> Array[String]:
	var out: Array[String] = []
	var s: Dictionary = GameState.stats

	if bool(GameState.flag("ach_clean_shift", false)):
		out.append("clean_hands")
	if bool(GameState.flag("ach_textbook", false)):
		out.append("textbook")
	if bool(GameState.flag("ach_full_round", false)):
		out.append("the_round")
	if int(s.get("patients_cured", 0)) >= 20:
		out.append("sent_home")
	if bool(GameState.flag("ach_imaged_own_work", false)):
		out.append("second_opinion")

	if bool(GameState.flag("ach_all_debts_paid", false)):
		out.append("in_the_black")
	if int(s.get("personal_earned", 0)) >= 50000:
		out.append("solvent")
	if float(s.get("longest_stay", 0.0)) >= 10.0:
		out.append("landlord")
	if GameState.unlocked_departments.size() >= 4:
		out.append("renovator")

	if int(s.get("bribes_paid", 0)) >= 1:
		out.append("an_arrangement")
	if int(s.get("bribes_refused", 0)) >= 1:
		out.append("no_thank_you")
	if int(GameState.flag("corrupt_staff_count", 0)) >= 5:
		out.append("the_whole_ward")
	if int(s.get("injuries_documented", 0)) >= 1:
		out.append("known_risk")
	if bool(GameState.flag("ach_plausible_reaction", false)):
		out.append("unlucky")

	if int(s.get("night_jobs", 0)) >= 1 and int(s.get("night_jobs_clean", 0)) \
			+ int(s.get("night_jobs_botched", 0)) >= 1:
		out.append("night_shift")
	if int(s.get("night_jobs_clean", 0)) >= 3:
		out.append("unseen")
	if bool(GameState.flag("ach_recognised", false)):
		out.append("recognised")

	if int(s.get("lawsuits_filed", 0)) >= 1:
		out.append("served")
	if int(s.get("lawsuits_settled", 0)) >= 1:
		out.append("settled")
	if int(s.get("lawsuits_won", 0)) >= 1:
		out.append("day_in_court")
	if bool(GameState.flag("ach_shady_win", false)):
		out.append("expensive_friend")
	if int(s.get("lawsuits_lost", 0)) >= 1:
		out.append("the_full_amount")

	if GameState.day >= 14:
		out.append("fortnight")
	if GameState.day >= 30:
		out.append("long_service")
	if GameState.sanction_level >= 8:
		out.append("struck_off")
	return out
