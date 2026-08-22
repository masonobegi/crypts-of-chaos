extends SceneTree
func _initialize() -> void:
	var w = WardDay.new(); root.add_child(w); w.start()
	w.advance_to(16*60+30)
	w.write_entry("oduya", ChartEntry.Claim.UNWELL, "Reports dizziness.", 16*60+25)
	var o = w.order_test("oduya", "lying and standing BP")
	w.advance_to(16*60+45)
	w.resolve_test(o)
	w.set_disposition("oduya", "hold")
	for e in w.records.for_patient("oduya"):
		print("  %s stated=%d written=%d claim=%d author=%d" % [e.text, e.stated_minute, e.written_minute, e.claim, e.author])
	for f in w.review_findings():
		print("FINDING ", f.kind, " sev=", f.severity)
	quit()
