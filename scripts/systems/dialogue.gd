class_name Dialogue
extends RefCounted
## Barks and conversations.
##
## Two halves:
##   * BARKS — one-liners NPCs say unprompted, selected by role, personality and
##     what they currently believe. These are the game's readability layer.
##   * CONVERSATIONS — the player picking a line, with a real success chance
##     derived from personality, trust, how strong the evidence is, and whether
##     they have heard that excuse before. Excuses are a depleting resource.

# ================================================================== BARKS
const WITNESS_LINES := {
	1: [
		"Hm.", "...huh.", "That's a new one.", "Sorry, what was that?",
		"Doctor? ...never mind.", "Odd.",
		"Hm. No. Carry on.", "Thought I heard something.",
		"That's — no, fine.", "Long day.",
	],
	2: [
		"Doctor, what are you doing?", "Is that... normal?",
		"I don't think that's the setting.", "Hang on.",
		"That's not what the chart says.", "Should I be writing this down?",
		"Sorry — is there a reason for that?",
		"I'm going to pretend I'm looking at the window.",
		"That's the second time today.",
	],
	3: [
		"I saw that. I definitely saw that.", "Doctor. DOCTOR.",
		"I'm going to have to mention this.", "That is not a treatment.",
		"You know I can see you, right?",
		"I'd like to be somewhere else, please.",
		"No. No, I'm not doing this again.",
		"Whatever that was, it wasn't clinical.",
	],
	4: [
		"Right. I'm reporting this.", "I've written it all down. All of it.",
		"You're going to explain this to someone who isn't me.",
		"I've been counting, you know.",
		"There's a form for this. I've already got one.",
		"I've stopped giving you the benefit of the doubt.",
		"Names, times, rooms. All of it.",
	],
}

const ROLE_FLAVOUR := {
	"nurse": ["Not my ward, not my problem. ...it is my ward.", "Twelve hour shift. Twelve.",
		"I have four of these and two hands.", "Nobody tells me anything and then everyone does."],
	"doctor": ["Interesting technique.", "Is that in the guidelines? It isn't.",
		"I'd have done it differently. I'd have done it correctly."],
	"patient": ["Was that meant to happen?", "I felt that in my teeth.",
		"Should I say something? I'm going to say something."],
	"family": ["Excuse me — what was that?", "Is that standard?",
		"I'd like whoever is in charge. Not you. Whoever is in charge."],
}

const GOSSIP_LINES := [
	"You didn't hear this from me, but —",
	"Have you seen what's going on in %s?",
	"So I was walking past and —",
	"Right, so. You know that doctor.",
	"I'm not saying anything. I'm just saying.",
	"Between us? Something's off.",
	"Do me a favour and keep an eye on %s.",
	"I'd have said nothing last week. This week I'm saying something.",
	"It's not one thing, is it. That's what I mean.",
	"Ask me again at handover.",
]

const PATIENT_IDLE := {
	"trusting": ["Whatever you think is best, doctor.", "You're the expert!",
		"I feel a bit better, I think.", "You'd tell me, wouldn't you.",
		"My wife says I'm in good hands. I said yes, obviously.",
		"Take your time. I'm not going anywhere. ...am I?"],
	"paranoid": ["Why is that machine humming?", "Who else has been in this room?",
		"I'd like that in writing.", "Somebody moved my chair.",
		"That's a different pen. That's a different pen to yesterday.",
		"I don't sleep. I want you to know that I don't sleep."],
	"hypochondriac": ["I've got a new symptom.", "Should I stay another night? I should, shouldn't I.",
		"I read about this. It's usually fatal.", "Is my foot meant to be that temperature?",
		"I've been having a feeling. In the general area.",
		"My cousin had this and he's still not right."],
	"confrontational": ["How long is this going to take?", "I want to speak to someone senior.",
		"This is ridiculous.", "I've been very patient and I'd like that noted.",
		"Don't do the voice. I know the voice.",
		"Right. Who do I talk to about the food."],
	"confused": ["Is this the airport?", "Have I eaten?", "Which one are you again?",
		"Have they let the dog out?", "I'll get my coat, shall I.",
		"You've got your father's hands."],
	"observant": ["That dial was on five yesterday.", "You've changed the chart.",
		"The window's open again. It was open last night too.",
		"You came in at ten past. The other one comes at nine.",
		"That's not the same clipboard.",
		"There were two of those this morning."],
	"stoic": ["Fine.", "Mm.", "It's fine.", "No complaints.", "Been worse.", "Aye."],
	"litigious": ["My cousin's a solicitor, you know.", "I've kept a log.",
		"I'd like a copy of everything.", "What's your full name, sorry?",
		"I'm writing the time down. Not for any reason.",
		"I'd like that repeated slowly."],
}

const OVERDUE_LINES := [
	"Doctor... wasn't I supposed to leave yesterday?",
	"It's been %d days. It was meant to be %d.",
	"My family keep asking when I'm coming home.",
	"I feel fine. I felt fine on Tuesday.",
	"Is there a reason I'm still here?",
	"I've started recognising the trolley by its sound.",
	"The man in the next room has been and gone twice.",
	"I've run out of things to look at.",
	"Somebody must know. Somebody must know when.",
]

## Said by somebody who is well, whose paperwork is not finished, and who has
## worked that out. The whole game is downstream of this line landing: it is the
## first time the player is told, by a person rather than by a number, that
## there is a decision here and that they are the one making it.
##
## Nothing in it names the alternative. It does not have to.
const READY_LINES := [
	"I feel completely fine, actually. Am I going home today?",
	"So that's it, is it? I'm done? Someone said today.",
	"My daughter's outside in the car park. Should I tell her to wait?",
	"I packed. Probably shouldn't have packed.",
	"Nobody's said anything, but I feel ready. I feel ready.",
	"I'm allowed to just... ask, aren't I? When I can go?",
	"I've said my goodbyes twice now. It's getting awkward.",
	"There's nothing wrong with me, is there. Say if there is.",
	"I'd quite like to sleep in my own bed. That's all it is.",
]

const FAMILY_LINES := {
	"absent": ["I can't stay long.", "Just popping in.", "I've left the car on a meter.",
		"Tell him I came. Tell him I came for a while."],
	"constant": ["I've been here since six.", "I brought a chair. My own chair.",
		"I've met all the nurses. I know about Bev.",
		"I'll be here tomorrow. And the day after."],
	"questioner": ["What's that machine for?", "Why has the date changed?", "And what does that do?",
		"Who signed that?", "Is that the same one as yesterday, or a different one?",
		"Sorry — one more."],
	"litigious_family": ["I've spoken to a solicitor.", "I want this documented.",
		"You'll be hearing from someone.", "I'd like your name for my notes.",
		"We're past 'concerns'. We're at 'complaint'."],
	"knows_medicine": ["That's not the setting for this.", "I was a nurse for eleven years.",
		"Where's the incident report?", "You've not written that up, have you.",
		"I know what that noise means, and so do you."],
	"clueless": ["Is the big humming one the good one?", "Does he need more of the beeping?",
		"Should I be pressing anything?", "I brought grapes. Is that still a thing?"],
}

static func witness_line(mind: Mind, _ev: Evidence, tier: int) -> String:
	var pool: Array = WITNESS_LINES.get(clampi(tier, 1, 4), WITNESS_LINES[1])
	if RNG.chance("bark_flavour", 0.25) and ROLE_FLAVOUR.has(mind.role):
		pool = ROLE_FLAVOUR[mind.role]
	return String(RNG.pick("bark", pool))

## Gossip names a real room where it can. It used to say "101" every single time
## regardless of where anything happened, which is a small lie that a player who
## is paying attention catches inside one shift — and paying attention is the
## skill the whole game is asking for.
static func gossip_line(_mind: Mind, ev: Evidence) -> String:
	var line := String(RNG.pick("gossip_line", GOSSIP_LINES))
	if not line.contains("%s"):
		return line
	var where := "one of the side rooms"
	var ps = Engine.get_main_loop().get_first_node_in_group("patient_system") \
		if Engine.get_main_loop() != null else null
	var h = Engine.get_main_loop().get_first_node_in_group("hospital") \
		if Engine.get_main_loop() != null else null
	if ev != null and ev.patient_id != "" and ps != null and h != null:
		var p = ps.get_patient(ev.patient_id)
		if p != null and h.room(p.room) != null:
			where = h.room(p.room).display
	return line.replace("%s", where)

static func patient_idle(p) -> String:
	var pool: Array = PATIENT_IDLE.get(p.archetype, PATIENT_IDLE["trusting"])
	return String(RNG.pick("patient_idle", pool))

static func patient_ready(_p) -> String:
	return String(RNG.pick("patient_ready", READY_LINES))

static func patient_overdue(p) -> String:
	var line := String(RNG.pick("overdue", OVERDUE_LINES))
	if line.count("%d") == 2:
		return line % [int(p.days_admitted), int(p.expected_stay_days)]
	return line

static func family_idle(arch: String) -> String:
	var pool: Array = FAMILY_LINES.get(arch, FAMILY_LINES["questioner"])
	return String(RNG.pick("family_idle", pool))

# ================================================================== CONVERSATION
## A conversation option. `tone` decides which stat resists it, `cover` is the
## cover-story tag it establishes on success, and `risk` is what it costs when
## it fails.
class Option extends RefCounted:
	var text := ""
	var tone := "reassure"     ## reassure|deflect|blame|authority|honest|bribe|intimidate
	var cover := ""
	var risk := 0.3
	var cost := 0
	var effect := ""           ## neutralize|trust|discharge_promise|delay|none
	var requires := ""

	func _init(p_text: String, p_tone: String, p_cover := "", p_risk := 0.3,
			p_effect := "neutralize", p_cost := 0) -> void:
		text = p_text
		tone = p_tone
		cover = p_cover
		risk = p_risk
		effect = p_effect
		cost = p_cost

## How readily each personality accepts each kind of answer. Missing pairs fall
## back to 0.5, so a new archetype only specifies what makes it distinctive.
const TONE_AFFINITY := {
	"trusting":       {"reassure": 0.95, "deflect": 0.8, "authority": 0.9, "honest": 0.7, "blame": 0.6},
	"paranoid":       {"reassure": 0.25, "deflect": 0.15, "authority": 0.3, "honest": 0.6, "blame": 0.35},
	"hypochondriac":  {"reassure": 0.5, "deflect": 0.75, "authority": 0.8, "honest": 0.4, "blame": 0.6},
	"confrontational":{"reassure": 0.3, "deflect": 0.2, "authority": 0.45, "honest": 0.65, "intimidate": 0.15},
	"confused":       {"reassure": 0.9, "deflect": 0.95, "authority": 0.9, "honest": 0.5},
	"observant":      {"reassure": 0.3, "deflect": 0.2, "authority": 0.35, "honest": 0.75, "blame": 0.3},
	"stoic":          {"reassure": 0.6, "deflect": 0.6, "authority": 0.7, "honest": 0.7},
	"litigious":      {"reassure": 0.2, "deflect": 0.15, "authority": 0.3, "honest": 0.55},
	"lazy":           {"reassure": 0.85, "deflect": 0.9, "authority": 0.85, "bribe": 0.7},
	"suspicious":     {"reassure": 0.25, "deflect": 0.2, "authority": 0.35, "honest": 0.6},
	"loyal":          {"reassure": 0.9, "deflect": 0.8, "authority": 0.9, "honest": 0.85},
	"gossip":         {"reassure": 0.6, "deflect": 0.55, "authority": 0.5, "bribe": 0.5},
	"rule_follower":  {"reassure": 0.35, "deflect": 0.2, "authority": 0.55, "honest": 0.8},
	"corrupt":        {"reassure": 0.6, "deflect": 0.7, "bribe": 0.98, "authority": 0.5},
	"incompetent":    {"reassure": 0.8, "deflect": 0.85, "authority": 0.8},
	"knows_medicine": {"reassure": 0.25, "deflect": 0.15, "authority": 0.3, "honest": 0.7},
	"clueless":       {"reassure": 0.95, "deflect": 0.95, "authority": 0.95},
	"litigious_family": {"reassure": 0.2, "deflect": 0.1, "authority": 0.25, "honest": 0.5},
	"questioner":     {"reassure": 0.45, "deflect": 0.35, "authority": 0.5, "honest": 0.7},
	"constant":       {"reassure": 0.5, "deflect": 0.4, "authority": 0.55, "honest": 0.7},
	"absent":         {"reassure": 0.8, "deflect": 0.85, "authority": 0.8},
}

static func tone_affinity(arch: String, tone: String) -> float:
	var row: Dictionary = TONE_AFFINITY.get(arch, {})
	return float(row.get(tone, 0.5))

## Probability this line lands. Deliberately shown to the player as a coarse
## band rather than a number — see success_band().
static func success_chance(mind: Mind, opt: Option) -> float:
	if opt.tone in ["none", "small_talk"]:
		return 1.0
	var base := tone_affinity(mind.archetype, opt.tone)
	base *= 0.55 + mind.trust * 0.7
	# Strong evidence makes talk cheap. You cannot smooth-talk your way past
	# something they watched you do twice.
	var worst := mind.strongest(GameState.career_minutes)
	if worst != null:
		base *= clampf(1.0 - worst.current_weight(GameState.career_minutes) * 0.75, 0.12, 1.0)
	# A doctor with a good reputation gets the benefit of the doubt.
	base *= 0.75 + GameState.rep("doctor") * 0.5
	if opt.cover != "":
		base *= 0.45 + mind.cover_effectiveness(opt.cover) * 0.55
	if opt.tone == "bribe":
		base = tone_affinity(mind.archetype, "bribe") * (0.6 + GameState.rep("staff_trust") * 0.4)
	return clampf(base, 0.03, 0.97)

## The player never sees a percentage — they see how confident their character
## feels. Confidently wrong is funnier and more tense than precisely informed.
static func success_band(chance: float) -> String:
	if chance >= 0.8: return "they'll buy this"
	if chance >= 0.6: return "probably fine"
	if chance >= 0.4: return "risky"
	if chance >= 0.2: return "they are not going to like this"
	return "this will make it worse"

## Build the option list for a conversation with `mind`, optionally about `p`.
static func options_for(mind: Mind, p = null) -> Array:
	var opts: Array = []
	var has_evidence := mind.strongest(GameState.career_minutes) != null

	# A live proposition takes over the conversation entirely.
	if mind.deal_state == "offered":
		opts.append(Option.new("Pay them off.", "bribe", "", 0.7, "deal_accept", mind.deal_price))
		opts.append(Option.new("You didn't see anything.", "intimidate", "", 0.85, "deal_threaten"))
		opts.append(Option.new("Report yourself before they do.", "honest", "", 0.0, "deal_confess"))
		opts.append(Option.new("[walk away]", "none", "", 0.0, "none"))
		return opts

	if p != null and mind.role == "patient":
		if p.is_overdue():
			opts.append(Option.new("Just being cautious.", "reassure", "clinical_caution", 0.25))
			opts.append(Option.new("Your latest results concerned me.", "authority", "clinical_findings", 0.35))
			opts.append(Option.new("Insurance paperwork hasn't cleared.", "deflect", "administrative", 0.3))
			opts.append(Option.new("You don't want to rush recovery.", "reassure", "clinical_caution", 0.2))
			opts.append(Option.new("...who told you that?", "intimidate", "", 0.75, "none"))
			opts.append(Option.new("You're right. I'll start your discharge.", "honest", "", 0.0,
				"discharge_promise"))
		else:
			# Ordinary bedside manner. These cannot fail and must not be rolled:
			# showing "they are not going to like this" against "how are you
			# feeling?" is nonsense, and it teaches the player to distrust the
			# confidence band everywhere else.
			opts.append(Option.new("How are you feeling?", "small_talk", "", 0.0, "trust"))
			opts.append(Option.new("Everything's on track.", "small_talk", "", 0.0, "trust"))

	if has_evidence:
		opts.append(Option.new("That's a known equipment fault. It's logged.", "deflect",
			"equipment_variance", 0.4))
		opts.append(Option.new("That's the protocol for this condition.", "authority",
			"clinical_findings", 0.35))
		opts.append(Option.new("Facilities have been told about it twice.", "deflect",
			"facilities", 0.35))
		opts.append(Option.new("You've misread the situation.", "authority", "", 0.55))
		if mind.role in ["nurse", "doctor"]:
			opts.append(Option.new("Let's keep this between us.", "bribe", "", 0.6, "neutralize", 200))

	if mind.role == "nurse":
		opts.append(Option.new("How's the ward?", "small_talk", "", 0.0, "trust"))
		# A directed distraction: same effect as a thrown bedpan, except you
		# chose where they went and nobody heard a thing.
		opts.append(Option.new("Could you go and check the far end?", "authority",
			"", 0.15, "delay"))
	if mind.role == "family":
		opts.append(Option.new("We're monitoring them closely.", "reassure", "clinical_caution", 0.3))
		opts.append(Option.new("I'd rather not discuss it in the corridor.", "deflect",
			"administrative", 0.4))

	opts.append(Option.new("[walk away]", "none", "", 0.0, "none"))
	return opts

## Roll the option and apply consequences. Returns a result dict for the UI.
static func resolve(mind: Mind, opt: Option, p = null) -> Dictionary:
	if opt.tone == "none":
		return {"success": true, "reply": "", "walked_away": true}

	if opt.tone == "small_talk":
		mind.adjust_trust(0.04)
		return {"success": true, "reply": _small_talk_reply(mind), "small_talk": true}

	if opt.effect == "deal_accept":
		if GameState.personal_money < opt.cost:
			return {"success": false,
				"reply": "You haven't got it, have you. That's almost worse."}
		GameState.add_personal(-opt.cost, "an arrangement")
		mind.deal_state = "paid"
		mind.adjust_trust(0.45)
		# Bought silence is real silence: everything they hold is neutralised and
		# they stop talking to investigators. They are staff now, in the other sense.
		for ev in mind.evidence:
			ev.neutralized = true
		mind.escalation = 0.02
		mind.talkativeness = 0.05
		GameState.set_flag("corrupt_staff_count", int(GameState.flag("corrupt_staff_count", 0)) + 1)
		return {"success": true, "reply": String(RNG.pick("deal_yes", [
			"Pleasure doing business, doctor.",
			"I never liked that patient anyway.",
			"Same again next week, then."])), "deal": "paid"}

	if opt.effect == "deal_threaten":
		# Threatening someone who is already blackmailing you goes exactly as
		# well as you would expect.
		mind.deal_state = "refused"
		mind.adjust_trust(-0.4)
		mind.escalation = clampf(mind.escalation + 0.4, 0.0, 1.0)
		var ev := Evidence.new()
		ev.kind = "threatened_a_colleague"
		ev.about_actor = "player"
		ev.source = Evidence.Source.WITNESSED
		ev.time = GameState.career_minutes
		ev.base_weight = 0.5
		ev.certainty = 1.0
		ev.summary = "was threatened over it"
		mind.add_evidence(ev)
		return {"success": false, "reply": "That's a very interesting thing to say to me."}

	if opt.effect == "deal_confess":
		mind.deal_state = "refused"
		GameState.set_flag("self_reported", true)
		GameState.adjust_rep("doctor", 0.05)
		GameState.add_heat(0.1, "self-reported")
		return {"success": true, "reply": "...huh. Well. That's one way to do it."}

	if opt.effect == "discharge_promise":
		mind.adjust_trust(0.25)
		return {"success": true, "reply": "Oh — thank you, doctor. Really.",
			"discharge_promise": true}

	if opt.tone == "bribe":
		if GameState.personal_money < opt.cost:
			return {"success": false, "reply": "...are you offering me something? You've got nothing to offer.",
				"broke": true}
		GameState.add_personal(-opt.cost, "discretion")

	var chance := success_chance(mind, opt)
	var success := RNG.randf_s("dialogue") < chance
	GameState.stats.cover_stories_used += 1

	if opt.cover != "":
		mind.burn_cover(opt.cover)

	if success and opt.effect == "delay":
		mind.adjust_trust(0.02)
		return {"success": true, "send_away": true,
			"reply": String(RNG.pick("errand_yes", [
				"Suppose so.", "Fine, yes.", "You're the doctor."]))}

	if success:
		var worst := mind.strongest(GameState.career_minutes)
		if worst != null and opt.effect == "neutralize":
			worst.neutralized = true
			worst.explained_attempts += 1
		mind.adjust_trust(0.06)
		if opt.cover != "":
			GameState.add_cover(opt.cover, 180)
		return {"success": true, "reply": _success_reply(mind, opt)}

	# Failure isn't just "no". Being caught in a bad excuse is its own evidence,
	# and it's the kind that doesn't fade.
	mind.adjust_trust(-0.12)
	var ev := Evidence.new()
	ev.kind = "implausible_explanation"
	ev.about_actor = "player"
	ev.patient_id = p.id if p != null else ""
	ev.source = Evidence.Source.WITNESSED
	ev.time = GameState.career_minutes
	ev.base_weight = opt.risk
	ev.certainty = 0.85
	ev.summary = "gave an explanation that did not hold up"
	mind.add_evidence(ev)
	return {"success": false, "reply": _failure_reply(mind, opt)}

## Being decent to people is not a mechanic with a roll attached, but it is not
## free either — it costs shift time, and trust is a genuine defence later.
## The first thing they say when you walk up, before you have said anything.
##
## A conversation that opens on a menu of things YOU could say is a menu. A
## conversation that opens with somebody talking to you is a conversation, and
## it is what the second playtest asked for: "lock you in a talking phase where
## you have to click for them to mumble words."
##
## What they open with is the most useful readout in the game, because it comes
## straight off what they are holding: a nurse on tier three greets you very
## differently from a nurse on tier zero, and you learn where you stand before
## you have picked a single line.
static func greeting(mind: Mind, p = null) -> String:
	var tier := mind.tier(GameState.career_minutes)
	if tier >= 2:
		return String(RNG.pick("greet_hot_%s" % mind.id, WITNESS_LINES[tier]))
	if mind.deal_state == "paid":
		return String(RNG.pick("greet_paid", [
			"Doctor. Everything's fine. Everything's always fine.",
			"I've not seen anything all week.",
			"Whatever it is — no, I didn't."]))
	if p != null and mind.role == "patient":
		if p.is_overdue():
			return String(RNG.pick("greet_overdue_%s" % mind.id, [
				"Am I going home today? Only you said Tuesday.",
				"I've been counting the ceiling tiles. There are sixty-one.",
				"My sister keeps asking when I'm out. I keep not knowing."]))
		if not p.admitted:
			return String(RNG.pick("greet_walkin_%s" % mind.id, [
				"I've been sat here a while. Not complaining.",
				"It's probably nothing. It's probably nothing, isn't it?",
				"They said to wait for a doctor. Are you a doctor?"]))
		return _small_talk_reply(mind)
	if ROLE_FLAVOUR.has(mind.role):
		return String(RNG.pick("greet_role_%s" % mind.id, ROLE_FLAVOUR[mind.role]))
	return String(RNG.pick("greet_generic", [
		"Doctor.", "Yes?", "Sorry — busy. Go on.", "Alright?"]))

static func _small_talk_reply(mind: Mind) -> String:
	match mind.archetype:
		"paranoid": return "Fine. Why?"
		"stoic": return "Mm."
		"hypochondriac": return "Worse, actually. Much worse. Since you ask."
		"confrontational": return "How do you think I'm feeling?"
		"confused": return "Is it Thursday?"
		"observant": return "I'm alright. You look busy."
		"litigious": return "I'd rather that went in the notes."
	return String(RNG.pick("small_talk", [
		"Not too bad, thanks doctor.", "Bit better today, I think.",
		"Can't complain. Well. I could.", "Yeah, alright."]))

static func _success_reply(mind: Mind, opt: Option) -> String:
	match opt.tone:
		"bribe": return String(RNG.pick("reply", [
			"...I didn't see anything.", "We never had this conversation.",
			"Same time next week, then."]))
		"authority": return String(RNG.pick("reply", [
			"Right. Sorry, doctor.", "Understood.", "You'd know better than me."]))
		"deflect": return String(RNG.pick("reply", [
			"Typical. This place.", "Of course it is.", "Figures."]))
		"reassure": return String(RNG.pick("reply", [
			"Okay. Okay, thank you.", "That's reassuring.", "If you say so."]))
		"intimidate": return String(RNG.pick("reply", [
			"...no one. Forget I said anything.", "Nobody. Sorry."]))
	return "Alright."

static func _failure_reply(mind: Mind, opt: Option) -> String:
	match opt.tone:
		"bribe": return "I'm going to pretend you didn't say that."
		"intimidate": return "Don't you talk to me like that."
		"authority": return "No. I've read the same guidelines you have."
	if mind.archetype == "observant":
		return "That doesn't match what I saw."
	if mind.archetype == "paranoid":
		return "I knew it. I knew there was something."
	return String(RNG.pick("reply_fail", [
		"That's not what happened.", "I don't believe you.",
		"You said that last time.", "Hm. No."]))
