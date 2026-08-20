class_name Bribery
extends RefCounted
## Having a quiet word with somebody who saw something.
##
## The building was already full of people who watch you, remember it, and tell
## somebody — and the only way to get a witness off your back was to explain it
## away, or to wait for a member of staff to come to YOU with a price. Nothing
## let the player walk up to the woman in the doorway and make the problem go
## away, which is the single most obvious thing a person in this position would
## try.
##
## So: three envelopes, three prices, and a roll.
##
## THE SHAPE OF IT
##
##   * How receptive somebody is depends on who they are. A tired nurse on a
##     twelve-hour shift is a different proposition from the patient's daughter,
##     and both are a different proposition from an inspector.
##   * How much you offer moves the odds, and it moves them a LOT — but the
##     going rate is computed from what they saw, so buying silence about
##     something serious is genuinely expensive.
##   * If they refuse, you have not spent any money and you have made everything
##     worse: they now hold "tried to pay me off", which is worth more than
##     whatever they saw in the first place and cannot be explained away.
##   * And the offer itself is an ACT, in a room, with a visibility. Somebody
##     else can watch you do it. That is the best evidence in the game, and it
##     is generated entirely by the player trying to be careful.

## Who takes money, roughly. Nothing here is a certainty in either direction:
## an inspector on 0.10 is not impossible, they are a bad idea.
const RECEPTIVE := {
	"nurse": 0.62,
	"doctor": 0.46,
	"admin": 0.74,
	"porter": 0.72,
	"patient": 0.44,
	"family": 0.32,
	"insurer": 0.22,
	"inspector": 0.10,
	"police": 0.07,
}

## What you can put in the envelope. `mult` scales both price and odds; the
## labels are deliberately euphemistic because this is a thing people say in
## corridors rather than a menu of crimes.
const TIERS := [
	{"key": "token", "label": "Buy them a coffee.", "mult": 0.45, "odds": -0.16,
		"say": "Long shift. Get yourself something."},
	{"key": "going", "label": "Make it worth their while.", "mult": 1.0, "odds": 0.0,
		"say": "Let's call it a misunderstanding, shall we."},
	{"key": "silence", "label": "Make it worth their while, properly.", "mult": 2.4,
		"odds": 0.20, "say": "I'd like this to be the end of it."},
]

## The going rate for what they are holding. Scales hard with weight, because
## the cheap version of this must not solve the expensive problem.
static func price(mind: Mind, tier_mult: float) -> int:
	var worst := mind.strongest(GameState.career_minutes)
	var weight: float = worst.current_weight(GameState.career_minutes) if worst != null else 0.15
	var role_cost: float = 1.0 + (1.0 - float(RECEPTIVE.get(mind.role, 0.4))) * 1.2
	var base: float = 140.0 + weight * weight * 3200.0
	return int(round(base * role_cost * tier_mult / 10.0) * 10.0)

## Whether they take it. Everything in here is a property of the person and of
## what they saw — none of it is a difficulty setting.
static func chance(mind: Mind, tier: Dictionary) -> float:
	var worst := mind.strongest(GameState.career_minutes)
	var weight: float = worst.current_weight(GameState.career_minutes) if worst != null else 0.15
	var c: float = float(RECEPTIVE.get(mind.role, 0.4))
	c += float(tier.get("odds", 0.0))
	# Somebody who likes you is easier to ask, and somebody who has already
	# decided to escalate is nearly impossible.
	c += (mind.trust - 0.5) * 0.34
	c -= mind.escalation * 0.30
	c -= mind.skepticism * 0.14
	# The worse the thing they saw, the less an envelope covers it.
	c -= weight * 0.42
	# Reputation cuts both ways: staff who trust you take it as a favour; a
	# doctor everybody already distrusts is a doctor nobody wants to be paid by.
	c += (GameState.rep("staff_trust") - 0.5) * 0.22
	if GameState.flag("perk_quiet_word", false):
		c += 0.12
	if int(GameState.flag("corrupt_staff_count", 0)) >= 3:
		# It gets easier once it is known that this is a thing you do, and it
		# gets much worse if it ever comes out. See LegalSystem.
		c += 0.08
	return clampf(c, 0.03, 0.94)

## The one line the player is allowed to read about their odds. No percentage,
## same grammar as every other conversation in the game.
static func band(c: float) -> String:
	if c >= 0.8: return "they'll take it"
	if c >= 0.6: return "probably"
	if c >= 0.4: return "could go either way"
	if c >= 0.2: return "they might be offended"
	return "this is a terrible idea"

## Make the offer. Returns what happened, for the screen to say out loud.
static func attempt(mind: Mind, tier: Dictionary, at: Vector3, room := "") -> Dictionary:
	var cost := price(mind, float(tier["mult"]))
	if GameState.personal_money < cost:
		return {"ok": false, "broke": true, "cost": cost,
			"reply": "...are you offering me something? You've got nothing to offer."}
	var odds := chance(mind, tier)
	var took := RNG.chance("bribe_%s_%d" % [mind.id, GameState.career_minutes], odds)

	# Offering is an act that happens in a room. Whether it lands or not, the
	# offer is visible to anybody with a line of sight — and being seen paying
	# somebody off is worse than being seen doing the thing you are paying them
	# to forget.
	var e := WorldEvent.new("bribe_offered", "player").at(at, room) \
		.seen(0.55).heard(0.25, 5.0).cover("") \
		.tag("bribery").tag("misconduct") \
		.says("was putting something in %s's hand" % mind.display_name)
	e.emit()

	if took:
		GameState.add_personal(-cost, "an arrangement")
		mind.deal_state = "paid"
		mind.adjust_trust(0.35)
		# Bought silence is real silence — while it lasts.
		for ev in mind.evidence:
			if ev.about_actor == "player":
				ev.neutralized = true
		mind.escalation = clampf(mind.escalation * 0.2, 0.0, 1.0)
		mind.talkativeness = clampf(mind.talkativeness * 0.3, 0.0, 1.0)
		mind.watching = false
		GameState.set_flag("corrupt_staff_count",
			int(GameState.flag("corrupt_staff_count", 0)) + 1)
		GameState.stats.bribes_paid = int(GameState.stats.get("bribes_paid", 0)) + 1
		GameState.add_heat(0.02, "an arrangement")
		AudioMgr.play("money", -12.0)
		return {"ok": true, "cost": cost, "odds": odds,
			"reply": String(RNG.pick("bribe_yes", [
				"...I didn't see anything. I was on my break.",
				"Pleasure doing business, doctor.",
				"I've got three kids. Don't make me do this again.",
				"You never gave me this. I never took it."]))}

	# Refused. The money stays in your pocket and everything else gets worse.
	mind.deal_state = "refused"
	mind.adjust_trust(-0.45)
	mind.escalation = clampf(mind.escalation + 0.45, 0.0, 1.0)
	mind.talkativeness = clampf(mind.talkativeness + 0.3, 0.0, 1.0)
	mind.watching = true
	var ev2 := Evidence.new()
	ev2.kind = "attempted_bribery"
	ev2.about_actor = "player"
	ev2.source = Evidence.Source.WITNESSED
	ev2.time = GameState.career_minutes
	# Worth more than most of what it is trying to cover, and there is no cover
	# story for it: nobody accidentally offers a colleague four hundred pounds.
	ev2.base_weight = 0.72
	ev2.certainty = 1.0
	ev2.cover_tag = ""
	ev2.summary = "was offered money to keep quiet about it"
	mind.add_evidence(ev2)
	GameState.add_heat(0.06, "an offer somebody refused")
	GameState.stats.bribes_refused = int(GameState.stats.get("bribes_refused", 0)) + 1
	AudioMgr.play("error", -12.0)
	return {"ok": false, "cost": cost, "odds": odds,
		"reply": String(RNG.pick("bribe_no", [
			"...I'm going to walk away and pretend that didn't happen. I won't, though.",
			"Are you serious? Are you actually serious?",
			"No. No — put that away. Put that AWAY.",
			"I'm writing this one down twice."]))}
