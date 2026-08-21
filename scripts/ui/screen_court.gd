extends ScreenBase
## The letter, and what you do about it.
##
## Four screens in one, in the order a person actually meets them: the claim,
## the decision, your representation, and then the room itself.
##
## The hearing is the only place in the game where the three layers are put side
## by side in front of somebody whose job it is to notice. Whatever you wrote in
## the chart weeks ago is read out. Whoever you did not have a quiet word with
## is called. Any imaging you ordered — the one document you cannot edit —
## arrives exactly as it was taken. None of that is generated here; it is all
## just the ward, showing up.

var _claim: Dictionary = {}
var _stage := "letter"
var _lawyer := ""
var _exchange := 0
var _scores: Array[float] = []
var _outcome: Dictionary = {}

func legal():
	return get_tree().get_first_node_in_group("legal_system")

func _build() -> void:
	_claim = Dictionary(ctx.get("claim", {}))
	if _claim.is_empty():
		close()
		return
	match _stage:
		"letter": _build_letter()
		"lawyers": _build_lawyers()
		"hearing": _build_hearing()
		_: _build_verdict()

# ------------------------------------------------------------------ the letter
func _build_letter() -> void:
	var v := shell(820, 720, "A letter before action",
		"%s · %s" % [String(_claim["patient"]), String(_claim["condition"])])

	first_time_note(v, "court")
	var box := UIKit.panel(Color(0.20, 0.14, 0.14, 0.9), 6, 1, UIKit.BAD)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label(String(_claim["summary"]), 16, Color(1, 0.88, 0.86),
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.label("They are asking for %s." % UIKit.money_str(int(_claim["amount"])),
		20, UIKit.BAD))
	box.add_child(bv)
	v.add_child(box)

	# What the other side has, in the same grammar the ward uses everywhere
	# else: facts, not a strength bar.
	v.add_child(UIKit.rule())
	var wits: Array = _claim.get("witnesses", [])
	v.add_child(UIKit.row("Witnesses prepared to attend",
		"none they have found" if wits.is_empty() else ", ".join(wits),
		UIKit.GOOD if wits.is_empty() else UIKit.BAD))
	v.add_child(UIKit.row("Imaging in the file",
		"yes — taken on the ward" if bool(_claim.get("imaging", false)) else "none",
		UIKit.BAD if bool(_claim.get("imaging", false)) else UIKit.GOOD))
	v.add_child(UIKit.row("Your own note on the discharge",
		"as filed", UIKit.INK_DIM))
	v.add_child(UIKit.rule())

	var settle_cost: int = LegalSystem.settlement(_claim)
	var s := UIKit.panel(UIKit.PANEL_LIGHT, 6, 2, UIKit.WARN)
	var sv := UIKit.vbox(3)
	sv.add_child(UIKit.label("Settle it now — %s" % UIKit.money_str(settle_cost),
		18, UIKit.WARN))
	sv.add_child(UIKit.label(
		"They take it and it is over today. No hearing, no witnesses, no finding.",
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	sv.add_child(UIKit.button("Pay it", _settle))
	s.add_child(sv)
	v.add_child(s)

	var f := UIKit.panel(UIKit.PANEL_LIGHT, 6, 2, UIKit.ACCENT)
	var fv := UIKit.vbox(3)
	fv.add_child(UIKit.label("Fight it", 18, UIKit.ACCENT))
	fv.add_child(UIKit.label(
		"Win and you pay your lawyer and nothing else. Lose and you pay a good "
		+ "deal more than the settlement, in front of everybody.",
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	fv.add_child(UIKit.button("Instruct someone", func():
		_stage = "lawyers"
		rebuild()))
	f.add_child(fv)
	v.add_child(f)

	v.add_child(UIKit.label(
		"Ignore it and it goes against you in default in %d days, for the whole amount."
			% LegalSystem.ANSWER_WINDOW, 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_CENTER, true))
	v.add_child(UIKit.button("Put it in the drawer", close))

func _settle() -> void:
	var lg = legal()
	if lg == null:
		close()
		return
	if GameState.personal_money + GameState.hospital_money < LegalSystem.settlement(_claim):
		EventBus.toast.emit("There is not that much money in the building.", "bad")
		return
	_outcome = lg.settle(_claim)
	_outcome["settled"] = true
	AudioMgr.play("stamp", -8.0)
	_stage = "verdict"
	rebuild()

# ------------------------------------------------------------------ counsel
func _build_lawyers() -> void:
	var v := shell(820, 720, "Representation",
		"Claim of %s · %s" % [UIKit.money_str(int(_claim["amount"])),
			String(_claim["patient"])])
	v.add_child(UIKit.label(
		"They will all tell you they are confident. The difference is what they "
		+ "are prepared to do about the other side's witnesses.",
		14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var list := UIKit.vbox(6)
	for l in LegalSystem.LAWYERS:
		list.add_child(_lawyer_option(l))
	v.add_child(UIKit.scroll(list))
	v.add_child(UIKit.button("Back to the letter", func():
		_stage = "letter"
		rebuild()))

func _lawyer_option(l: Dictionary) -> Control:
	var fee := LegalSystem.lawyer_fee(String(l["id"]), int(_claim["amount"]))
	var tint: Color = UIKit.INK if float(l["shady"]) < 0.3 else UIKit.WARN
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6)
	var bv := UIKit.vbox(2)
	bv.add_child(UIKit.label("%s — %s" % [String(l["name"]),
		"no fee" if fee == 0 else UIKit.money_str(fee)], 17, tint))
	bv.add_child(UIKit.label(String(l["blurb"]), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if float(l["shady"]) > 0.3:
		bv.add_child(UIKit.label(
			"What he does to the other side's case can come out afterwards.",
			12, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	var b := UIKit.button("Instruct", func(): _instruct(String(l["id"])))
	b.disabled = GameState.personal_money < fee
	bv.add_child(b)
	p.add_child(bv)
	return p

func _instruct(id: String) -> void:
	_lawyer = id
	_stage = "hearing"
	_exchange = 0
	_scores.clear()
	AudioMgr.play("paper", -10.0)
	rebuild()

# ------------------------------------------------------------------ the room
func _build_hearing() -> void:
	var rounds := LegalSystem.exchanges(_claim)
	if _exchange >= rounds.size():
		_finish_hearing()
		return
	var ex: Dictionary = rounds[_exchange]
	var v := shell(820, 700, "In the matter of %s" % String(_claim["patient"]),
		"%s for the defendant · exchange %d of %d" % [
			String(LegalSystem.lawyer(_lawyer)["name"]), _exchange + 1, rounds.size()])

	var box := UIKit.panel(Color(0.14, 0.16, 0.22, 0.92), 6, 1, UIKit.BAD)
	var rl := UIKit.label("", 17, Color(0.94, 0.90, 0.88), HORIZONTAL_ALIGNMENT_LEFT, true)
	rl.custom_minimum_size.y = 56
	box.add_child(rl)
	v.add_child(box)
	# Typed rather than printed, same as every other person in this game who is
	# saying something to your face.
	var typer := Typewriter.new()
	add_child(typer)
	typer.speak(rl, String(ex["them"]), "claimant_counsel")

	v.add_child(UIKit.spacer(6))
	for key in ex["replies"]:
		v.add_child(_reply_button(String(key)))

func _reply_button(key: String) -> Control:
	var spec: Dictionary = LegalSystem.REPLIES[key]
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6)
	var bv := UIKit.vbox(2)
	bv.add_child(UIKit.label(String(spec["label"]), 16, UIKit.INK))
	bv.add_child(UIKit.label(String(spec["note"]), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.button("Say it", func(): _say(key)))
	p.add_child(bv)
	return p

func _say(key: String) -> void:
	_scores.append(LegalSystem.reply_score(_claim, key, _lawyer))
	_exchange += 1
	AudioMgr.play("stamp", -16.0)
	rebuild()

func _finish_hearing() -> void:
	var lg = legal()
	if lg == null:
		close()
		return
	_outcome = lg.verdict(_claim, _lawyer, LegalSystem.hearing_score(_scores))
	AudioMgr.play("ding" if bool(_outcome.get("won", false)) else "suspicion", -6.0)
	_stage = "verdict"
	rebuild()

# ------------------------------------------------------------------ the finding
func _build_verdict() -> void:
	var settled: bool = bool(_outcome.get("settled", false))
	var won: bool = bool(_outcome.get("won", false))
	var heading := "Settled" if settled else ("Claim dismissed" if won else "Judgment for the claimant")
	var v := shell(760, 560, heading, String(_claim["patient"]))

	var tint: Color = UIKit.WARN if settled else (UIKit.GOOD if won else UIKit.BAD)
	var box := UIKit.panel(UIKit.PANEL_LIGHT, 6, 2, tint)
	var bv := UIKit.vbox(4)
	if settled:
		bv.add_child(UIKit.label(
			"They took %s and signed something saying none of it happened."
				% UIKit.money_str(int(_outcome.get("paid", 0))), 16, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	elif won:
		bv.add_child(UIKit.label(
			"Nothing to pay but your own costs. Nobody in that room believed you; "
			+ "they simply could not show otherwise.", 16, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		bv.add_child(UIKit.label(
			"%s in damages, and it is on the record with your name on it."
				% UIKit.money_str(int(_outcome.get("paid", 0))), 16, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	if int(_outcome.get("fee", 0)) > 0:
		bv.add_child(UIKit.row("Your representation",
			UIKit.money_str(int(_outcome["fee"])), UIKit.INK_DIM))
	if bool(_outcome.get("exposed", false)):
		bv.add_child(UIKit.label(
			"Somebody has asked how your side came to know so much about the "
			+ "claimant's witnesses.", 14, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(bv)
	v.add_child(box)
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("That's that", close))
