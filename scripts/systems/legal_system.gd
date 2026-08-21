class_name LegalSystem
extends Node
## Being sued.
##
## The ward has always had two ways of catching you — somebody watching, and
## somebody reading the file afterwards. Both of them end in HEAT, which is
## institutional and slow. Nothing in the game ever came from the PATIENT, and
## the patient is the person it happened to.
##
## A claim is what a discharged patient does about it. It is not suspicion and
## it does not care about heat: it is a number, it is served on a specific day,
## and it has to be answered. The three ways to answer are pay, fight, or lose
## by ignoring it.
##
## WHAT MAKES A CLAIM STRONG
##
## Not what you did — what can be SHOWN. That is the whole design, and it is the
## same three-layer game the rest of the simulation plays:
##
##   * truth   — what actually happened to their body
##   * record  — what the chart says happened, which you write
##   * belief  — who saw it and what they will say under oath
##
## A patient you genuinely hurt, whose chart documents a recognised risk, and
## whose witnesses you have already had a quiet word with, has a weak claim. A
## patient you barely touched whose imaging contradicts your own note has a
## strong one. Imaging is the killer: it is the one document in the building you
## cannot edit, and it turns up in court exactly as it was taken.

signal claim_filed(claim: Dictionary)
signal claim_resolved(claim: Dictionary)

## Days between the discharge and the letter. Long enough that you have moved
## on, short enough that you remember the name.
const SERVE_DELAY := [2, 6]
## How long you have to answer before it goes against you by default.
const ANSWER_WINDOW := 3

var claims: Array[Dictionary] = []
var _next_id := 1

func _ready() -> void:
	add_to_group("legal_system")

# ------------------------------------------------------------------ lawyers
## Four ways to be represented, in ascending order of price and descending
## order of scruple. `shady` is what they will do to the other side's case
## before it gets in front of anybody, and it is a real advantage with a real
## bill attached: if the shady work is discovered, it is worse than the claim.
const LAWYERS := [
	{
		"id": "duty", "name": "The duty solicitor", "skill": 0.30, "shady": 0.0,
		"fee_flat": 0, "fee_rate": 0.0,
		"blurb": "Free. Reads the file in the corridor on the way in.",
	},
	{
		"id": "firm", "name": "Habersham & Pike", "skill": 0.56, "shady": 0.08,
		"fee_flat": 2500, "fee_rate": 0.03,
		"blurb": "Competent, thorough, and audibly disappointed in you.",
	},
	{
		"id": "fixer", "name": "Mr Vance", "skill": 0.70, "shady": 0.55,
		"fee_flat": 6000, "fee_rate": 0.06,
		"blurb": "Would like a word with the witnesses first. Just a word.",
	},
	{
		"id": "shark", "name": "Delphine Crowe KC", "skill": 0.88, "shady": 0.85,
		"fee_flat": 18000, "fee_rate": 0.11,
		"blurb": "Has never lost. Two of her cases are still being looked into.",
	},
]

static func lawyer(id: String) -> Dictionary:
	for l in LAWYERS:
		if String(l["id"]) == id:
			return l
	return LAWYERS[0]

static func lawyer_fee(id: String, amount: int) -> int:
	var l := lawyer(id)
	return int(l["fee_flat"]) + int(round(float(amount) * float(l["fee_rate"])))

# ------------------------------------------------------------------ filing
## Somebody who was discharged decides to do something about it.
##
## `risk` is whatever the ward accumulated against this patient: the procedures
## that went badly, the discharge that came too early, the injury nobody
## documented. Not every risk becomes a claim — most people go home and get on
## with it, which is what makes the ones who do not feel like a consequence
## rather than a tax.
func consider_claim(p, reason: String, risk: float) -> void:
	if p == null or risk <= 0.0:
		return
	if GameState.flag("perk_arbitration_clause", false):
		risk *= 0.55
	if not RNG.chance("sue_%s_%s" % [p.id, reason], clampf(risk, 0.0, 0.92)):
		return
	file_claim(p, reason)

func file_claim(p, reason: String) -> Dictionary:
	var strength := _strength_of(p, reason)
	var amount := _amount_for(p, reason, strength)
	var claim := {
		"id": "claim_%d" % _next_id,
		"patient_id": p.id,
		"patient": p.display_name,
		"condition": p.condition_name(),
		"reason": reason,
		"summary": _summary_for(p, reason),
		"amount": amount,
		"strength": strength,
		"day_filed": GameState.day + RNG.randi_range_s("serve", SERVE_DELAY[0], SERVE_DELAY[1]),
		"state": "pending",
		"witnesses": _witnesses_against(p),
		"imaging": p.chart != null and bool(p.chart.imaging_done),
		"lawyer": "",
	}
	_next_id += 1
	claims.append(claim)
	GameState.stats.lawsuits_filed += 1
	return claim

## A claim that did not come from the ward at all.
##
## Somebody watched you do something in a street and is willing to say so. It
## goes through the same machinery as every other claim — served after a delay,
## settled or fought, argued in front of the same four barristers — because from
## the courtroom's point of view it is the same document. What makes it worse is
## `witnesses`: there is one, they are not a colleague, and they owe you
## nothing.
func file_street_claim(who: String, where: String, condition_id: String,
		who_saw := "a passer-by") -> bool:
	var claim := {
		"id": "claim_%d" % _next_id,
		"patient_id": "",
		"patient": who,
		"condition": String(DB.condition(condition_id).get("name", condition_id)),
		"reason": "street",
		"summary": "Claimant states that on the evening in question, at %s, the "
			% where + "defendant caused the injury for which they were "
			+ "subsequently admitted to the defendant's own ward.",
		"amount": 9000 + RNG.randi_range_s("street_claim", 0, 7000)
			+ 400 * maxi(0, GameState.day - 1),
		# High, and not much you can do about it: the difference between this
		# and a discharge claim is that somebody saw it happen.
		"strength": 0.72,
		"day_filed": GameState.day + RNG.randi_range_s("serve", SERVE_DELAY[0], SERVE_DELAY[1]),
		"state": "pending",
		# A list of names, like every other claim's — there is exactly one on it
		# and they are not a colleague, which is what makes a flat denial the
		# expensive answer here.
		"witnesses": [who_saw],
		"imaging": false,
		"lawyer": "",
	}
	_next_id += 1
	claims.append(claim)
	GameState.stats.lawsuits_filed += 1
	return true

## Everything the claimant can actually put in front of a court.
func _strength_of(p, reason: String) -> float:
	var s := 0.22
	match reason:
		"premature_discharge":
			s += clampf(1.0 - p.recovery, 0.0, 1.2) * 0.55
		"procedure":
			s += 0.26
		"injury":
			s += 0.34
		"night":
			s += 0.30
	# What is on their body when somebody else examines it.
	for c in p.complications:
		if c.is_injury:
			s += 0.11
			if c.documented_cause == "":
				# Nobody wrote down how it happened. That is the sentence the
				# other side reads out.
				s += 0.09
	# The one document you cannot rewrite.
	if p.chart != null and bool(p.chart.imaging_done):
		if not bool(p.chart.imaging_clear):
			s += 0.16
	# People who will say what they saw.
	s += float(_witnesses_against(p).size()) * 0.07
	# And what the ward already thinks of you.
	s += GameState.heat * 0.18
	return clampf(s, 0.05, 0.97)

## Who would stand up. Anybody holding live, un-neutralised evidence about you
## that concerns this patient — which is exactly what a quiet word buys off.
func _witnesses_against(p) -> Array:
	var out: Array = []
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus == null or not sus.has_method("all_minds"):
		return out
	for m in sus.all_minds():
		if m == null or m.deal_state == "paid":
			continue
		for ev in m.evidence:
			if ev.neutralized or ev.about_actor != "player":
				continue
			if ev.patient_id != "" and ev.patient_id != p.id:
				continue
			if ev.current_weight(GameState.career_minutes) < 0.12:
				continue
			out.append(m.display_name)
			break
	return out

## What they are asking for. Scales with what happened to them rather than with
## your ability to pay, because a claim is not a difficulty slider.
func _amount_for(p, reason: String, strength: float) -> int:
	var base := 40000.0
	match reason:
		"premature_discharge": base = 60000.0
		"procedure": base = 110000.0
		"injury": base = 180000.0
		"night": base = 250000.0
	for c in p.complications:
		if c.is_injury:
			base += 45000.0
	base *= 0.7 + strength * 0.9
	# Round to something a letter would actually say.
	return int(round(base / 5000.0) * 5000.0)

func _summary_for(p, reason: String) -> String:
	match reason:
		"premature_discharge":
			return "%s says they were sent home before they were fit, and that it cost them." \
				% p.display_name
		"procedure":
			return "%s says a procedure was performed badly and made things worse." \
				% p.display_name
		"injury":
			return "%s says they arrived with one problem and left with two." % p.display_name
		"night":
			return "%s says the injury that brought them in did not happen the way it is written down." \
				% p.display_name
	return "%s is not happy." % p.display_name

# ------------------------------------------------------------------ the diary
## Claims served and waiting for an answer today.
func due_claims() -> Array:
	var out: Array = []
	for c in claims:
		if String(c["state"]) == "pending" and int(c["day_filed"]) <= GameState.day:
			out.append(c)
	return out

func open_claims() -> Array:
	return due_claims()

## Anything left unanswered past its window goes against you in default, which
## is the most expensive way to deal with a letter.
func expire_overdue() -> void:
	for c in claims:
		if String(c["state"]) != "pending":
			continue
		if GameState.day > int(c["day_filed"]) + ANSWER_WINDOW:
			_pay(c, int(c["amount"]), "default judgment")
			c["state"] = "lost"
			GameState.stats.lawsuits_lost += 1
			GameState.add_heat(0.12, "a judgment in default")
			claim_resolved.emit(c)

# ------------------------------------------------------------------ answers
## What they will take to go away. Half, near enough, and less than half if
## their case is thin — a weak claimant knows it too.
static func settlement(claim: Dictionary) -> int:
	var frac: float = 0.34 + float(claim["strength"]) * 0.30
	return int(round(float(claim["amount"]) * frac / 1000.0) * 1000.0)

func settle(claim: Dictionary) -> Dictionary:
	var cost := settlement(claim)
	_pay(claim, cost, "settlement")
	claim["state"] = "settled"
	GameState.stats.lawsuits_settled += 1
	# Settling is not an admission, but it is not nothing either: the insurer
	# reads the ledger.
	GameState.add_heat(0.04, "a settlement")
	GameState.adjust_rep("patient_sat", -0.02)
	Chronicle.note("court", 0.85, "You paid %s to make %s's claim go away."
		% [UIKit.money_str(cost), String(claim["patient"])])
	claim_resolved.emit(claim)
	Meta.check_achievements()
	return {"paid": cost, "outcome": "settled"}

## Going to court. `score` comes out of the hearing itself.
func verdict(claim: Dictionary, lawyer_id: String, score: float) -> Dictionary:
	var l := lawyer(lawyer_id)
	var fee := lawyer_fee(lawyer_id, int(claim["amount"]))
	# The claimant's case, less whatever your representation did about it before
	# anybody sat down.
	var against: float = float(claim["strength"]) * (1.0 - float(l["shady"]) * 0.28)
	var won: bool = score >= against
	var out := {"won": won, "fee": fee, "score": score, "against": against}

	if fee > 0:
		GameState.add_personal(-fee, "%s's fee" % String(l["name"]))
	if won:
		claim["state"] = "won"
		GameState.stats.lawsuits_won += 1
		if float(l["shady"]) > 0.4:
			GameState.set_flag("ach_shady_win", true)
		GameState.adjust_rep("doctor", 0.04)
		out["paid"] = 0
	else:
		# Losing costs more than settling would have, which is the entire reason
		# settling is on the table.
		var frac: float = 0.62 + float(claim["strength"]) * 0.38
		var damages := int(round(float(claim["amount"]) * frac / 1000.0) * 1000.0)
		_pay(claim, damages, "damages")
		claim["state"] = "lost"
		GameState.stats.lawsuits_lost += 1
		GameState.add_heat(0.16, "a judgment against you")
		GameState.adjust_rep("doctor", -0.10)
		GameState.adjust_rep("patient_sat", -0.06)
		out["paid"] = damages

	# What the shady half of the bill actually bought, and what it risks. A
	# fixer who leaned on the witnesses has left a trail of his own.
	if float(l["shady"]) > 0.3 and RNG.chance("shady_lawyer_%s" % String(claim["id"]),
			float(l["shady"]) * 0.30):
		GameState.add_heat(0.10, "questions about your representation")
		out["exposed"] = true
	claim["lawyer"] = lawyer_id
	Chronicle.note("court", 1.0, ("You beat %s in court, with %s." if won
		else "%s beat you in court, and %s could not stop it.") % [
			String(claim["patient"]), String(l["name"])])
	claim_resolved.emit(claim)
	Meta.check_achievements()
	return out

func _pay(claim: Dictionary, amount: int, why: String) -> void:
	# Damages come out of you personally first and then out of the hospital,
	# because the hospital's lawyers were very clear about that in your contract.
	var personal: int = mini(amount, GameState.personal_money)
	if personal > 0:
		GameState.add_personal(-personal, why)
	var rest: int = amount - personal
	if rest > 0:
		GameState.hospital_money -= rest
	GameState.stats.damages_paid = int(GameState.stats.get("damages_paid", 0)) + amount

# ------------------------------------------------------------------ the hearing
## Three exchanges, each of which is a thing the other side says and three ways
## of answering it. What makes an answer good is not how clever it is — it is
## whether the RECORD supports it, which is a document you wrote weeks ago and
## may not remember writing.
const REPLIES := {
	"record": {
		"label": "The record is clear about this.",
		"note": "Everything rests on what you wrote at the time.",
	},
	"risk": {
		"label": "A recognised risk of the procedure.",
		"note": "True of a great many things, if it was written down as one.",
	},
	"deny": {
		"label": "That is simply not what happened.",
		"note": "Works until somebody who was there says otherwise.",
	},
	"concede": {
		"label": "We accept the delay and regret it.",
		"note": "Costs you the point. Costs them the theatre.",
	},
}

## What the other side says next, given what you have just said.
##
## The first version read three fixed lines whatever you did, which made the
## hearing a form with quotes on it: your answer changed the score and nothing
## else. Counsel answers you now. Lean on the record and they ask to read it
## beside the scan; deny it and they name the person who was standing there;
## concede and they stop arguing about whether and start arguing about how much.
##
## Which means the first thing you say decides what you have to answer next,
## and that is the whole reason to have a hearing rather than a die roll.
const HEARING_LENGTH := 4

const FOLLOW_UPS := {
	"record": {
		"imaged": {
			"them": "\"Then let us read your note. Out loud. Beside a scan taken the same week.\"",
			"replies": ["risk", "concede", "deny"],
		},
		"clear": {
			"them": "\"Your note. Written by you, about you, and the only account of it anywhere.\"",
			"replies": ["risk", "deny", "concede"],
		},
	},
	"deny": {
		"witnessed": {
			"them": "\"Not what happened. We will hear from %s, who was standing in the room.\"",
			"replies": ["concede", "record", "risk"],
		},
		"alone": {
			"them": "\"Nobody saw it, so nobody can contradict you. How convenient that is.\"",
			"replies": ["record", "risk", "concede"],
		},
	},
	"concede": {
		"any": {
			"them": "\"You accept it. Then we can stop arguing about whether, and start on how much.\"",
			"replies": ["risk", "record", "deny"],
		},
	},
	"risk": {
		"any": {
			"them": "\"A recognised risk. Recognised when, doctor — before, or in the writing-up?\"",
			"replies": ["record", "concede", "deny"],
		},
	},
}

## The closing, which is the same question however you got there.
const CLOSING := {
	"them": "\"Is there anything the court has not heard?\"",
	"replies": ["concede", "record", "deny"],
}

## `said` is what the defence has already said, in order. Empty means the
## hearing has not started.
static func exchange(claim: Dictionary, said: Array) -> Dictionary:
	if said.is_empty():
		return {
			"them": "\"%s\"" % String(claim["summary"]),
			"replies": ["record", "deny", "concede"],
		}
	if said.size() >= HEARING_LENGTH - 1:
		return CLOSING.duplicate(true)
	var last := String(said[said.size() - 1])
	var branch: Dictionary = FOLLOW_UPS.get(last, FOLLOW_UPS["concede"])
	var wits: Array = claim.get("witnesses", [])
	var key := "any"
	if branch.has("imaged"):
		key = "imaged" if bool(claim.get("imaging", false)) else "clear"
	elif branch.has("witnessed"):
		key = "witnessed" if wits.size() > 0 else "alone"
	var spec: Dictionary = branch[key].duplicate(true)
	if String(spec["them"]).contains("%s"):
		spec["them"] = String(spec["them"]) % (String(wits[0]) if wits.size() > 0 else "the ward")
	return spec

## Kept for anything that wants the whole hearing at once — a harness playing
## it through, or a test walking every line it can reach.
static func exchanges(claim: Dictionary) -> Array:
	var out: Array = []
	var said: Array = []
	for i in HEARING_LENGTH:
		var ex := exchange(claim, said)
		out.append(ex)
		said.append(String(ex["replies"][0]))
	return out

## How well an answer lands. Skill is your representation; the rest is the
## claim's own facts arguing back at you.
## `times_said` is how often the defence has already used this line. Saying the
## same thing four times is not a strategy, it is a man with one answer, and the
## court notices before you do.
static func reply_score(claim: Dictionary, reply: String, lawyer_id: String,
		times_said := 0) -> float:
	var l := lawyer(lawyer_id)
	var skill: float = float(l["skill"])
	var wits: int = Array(claim.get("witnesses", [])).size()
	var imaged: bool = bool(claim.get("imaging", false))
	var base := 0.0
	match reply:
		"record":
			# Only as good as the paperwork. Imaging that disagrees with the
			# chart is the worst moment available in this game — and a claim
			# about a STREET is not in the paperwork at all, so pointing at the
			# notes is pointing at a document nobody is asking about.
			if String(claim["reason"]) == "street":
				base = 0.16
			else:
				base = 0.62 if not imaged else 0.18
		"risk":
			base = 0.55 if String(claim["reason"]) in ["procedure", "injury"] else 0.30
		"deny":
			base = 0.70 - float(wits) * 0.22
		"concede":
			# Never brilliant, never a disaster. The floor under a bad case.
			base = 0.42
	return clampf(base * (0.55 + skill * 0.75) / (1.0 + 0.55 * float(times_said)),
		0.0, 1.0)

## Averaged rather than summed so the number the verdict compares against is on
## the same scale as the claim's strength.
static func hearing_score(scores: Array) -> float:
	if scores.is_empty():
		return 0.0
	var total := 0.0
	for s in scores:
		total += float(s)
	return clampf(total / float(scores.size()), 0.0, 1.0)

# ------------------------------------------------------------------ save
func to_dict() -> Dictionary:
	return {"claims": claims.duplicate(true), "next": _next_id}

func from_dict(d: Dictionary) -> void:
	claims.clear()
	for c in Array(d.get("claims", [])):
		claims.append(Dictionary(c))
	_next_id = int(d.get("next", 1))
