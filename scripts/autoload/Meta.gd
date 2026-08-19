extends Node
## Progress that survives a career.
##
## One career is 45–120 minutes and terminates in an ending. Without something
## carried forward, the sandbox has no reason to be replayed once you have seen
## it work. Endings unlock starting perks, so the ways you fail are also the ways
## you get stronger — and the perks are deliberately shaped by the ending that
## grants them.

const PATH := "user://meta.json"

## ending id -> perk it unlocks
const PERKS := {
	"consolidated": {
		"name": "Consolidated Debt", "from": "bankrupt",
		"desc": "You finally got the loans onto one statement. Daily outflow down 20%.",
	},
	"good_name": {
		"name": "A Good Name", "from": "saint",
		"desc": "People remember the ward you ran. Hospital and doctor standing start higher.",
	},
	"retainer": {
		"name": "Solicitor On Speed Dial", "from": "tycoon",
		"desc": "You start with the legal retainer already in place.",
	},
	"loyal_ward": {
		"name": "The Old Crew", "from": "medical_mafia",
		"desc": "Staff start considerably more loyal, and considerably less talkative.",
	},
	"clean_slate": {
		"name": "Cooperating Witness", "from": "whistleblower",
		"desc": "Government scrutiny starts at zero, and institutional heat cools faster.",
	},
	"old_hand": {
		"name": "Steady Hands", "from": "legendary",
		"desc": "You read patients better. Vitals are markedly less noisy from day one.",
	},
	"confidential_waste": {
		"name": "Contacts In Facilities", "from": "fraud_king",
		"desc": "The confidential waste contract is already signed.",
	},
	"a_friend": {
		"name": "A Friend Outside", "from": "prison",
		"desc": "Somebody owed you. Start with an extra $2,000 and no questions.",
	},
	"thick_skin": {
		"name": "Thick Skin", "from": "license_revoked",
		"desc": "You have been through it. The sanction ladder starts one rung more forgiving.",
	},
}

var endings_seen: Dictionary = {}       ## ending id -> times reached
var runs_completed: int = 0
var best_earnings: int = 0
## The best run, as the game actually scores it: how much you took out of the
## place before somebody stopped you. Kept whole rather than as a number so the
## next career can be told what it is beating and by what margin.
var best_haul: Dictionary = {}
var longest_career: int = 0
var selected_perk: String = ""

func _ready() -> void:
	load_meta()

# ------------------------------------------------------------------ unlocks
func unlocked_perks() -> Array[String]:
	var out: Array[String] = []
	for id in PERKS:
		if endings_seen.has(String(PERKS[id]["from"])):
			out.append(String(id))
	return out

func is_unlocked(perk_id: String) -> bool:
	return unlocked_perks().has(perk_id)

func perk_name(perk_id: String) -> String:
	return String(PERKS.get(perk_id, {}).get("name", perk_id))

func perk_desc(perk_id: String) -> String:
	return String(PERKS.get(perk_id, {}).get("desc", ""))

## Which ending is still needed to unlock a given perk.
func perk_source(perk_id: String) -> String:
	return String(PERKS.get(perk_id, {}).get("from", ""))

func select_perk(perk_id: String) -> void:
	selected_perk = perk_id if is_unlocked(perk_id) else ""
	save_meta()

# ------------------------------------------------------------------ recording
func record_ending(ending_id: String) -> void:
	endings_seen[ending_id] = int(endings_seen.get(ending_id, 0)) + 1
	runs_completed += 1
	var earned := int(GameState.stats.get("personal_earned", 0))
	if earned > int(best_haul.get("earned", -1)):
		best_haul = {
			"earned": earned,
			"days": GameState.day,
			"ending": ending_id,
			"injuries": int(GameState.stats.get("injuries_caused", 0)),
			"admitted": int(GameState.stats.get("patients_admitted", 0)),
			"sanction": GameState.SANCTIONS[GameState.sanction_level],
		}
	best_earnings = maxi(best_earnings, earned)
	longest_career = maxi(longest_career, GameState.day)
	save_meta()

func endings_found() -> int:
	return endings_seen.size()

# ------------------------------------------------------------------ application
## Applied immediately after GameState.start_new_career().
func apply_perk() -> void:
	if selected_perk == "" or not is_unlocked(selected_perk):
		return
	match selected_perk:
		"consolidated":
			for d in GameState.debts:
				d["daily"] = int(float(d.get("daily", 0)) * 0.8)
		"good_name":
			GameState.adjust_rep("hospital", 0.18)
			GameState.adjust_rep("doctor", 0.15)
		"retainer":
			GameState.owned_upgrades.append("legal_retainer")
		"loyal_ward":
			GameState.set_flag("perk_loyal_ward", true)
		"clean_slate":
			GameState.reputation["gov_scrutiny"] = 0.0
			GameState.set_flag("perk_fast_cooling", true)
		"old_hand":
			GameState.set_flag("perk_steady_hands", true)
		"confidential_waste":
			GameState.owned_upgrades.append("shred_bin")
		"a_friend":
			GameState.add_personal(2000, "a friend outside")
		"thick_skin":
			GameState.set_flag("perk_thick_skin", true)
	Log.i("perk applied: %s" % selected_perk, "Meta")

# ------------------------------------------------------------------ persistence
func save_meta() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"endings": endings_seen, "runs": runs_completed,
		"best": best_earnings, "longest": longest_career, "haul": best_haul,
		"perk": selected_perk,
	}, "  "))
	f.close()

func load_meta() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	endings_seen = d.get("endings", {})
	runs_completed = int(d.get("runs", 0))
	best_earnings = int(d.get("best", 0))
	best_haul = d.get("haul", {})
	longest_career = int(d.get("longest", 0))
	selected_perk = String(d.get("perk", ""))

func reset() -> void:
	endings_seen.clear()
	runs_completed = 0
	best_earnings = 0
	best_haul = {}
	longest_career = 0
	selected_perk = ""
	save_meta()
