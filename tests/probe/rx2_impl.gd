extends RefCounted
var tree: SceneTree = null

func _w() -> WardDay:
	for n in tree.root.get_children():
		if n is WardDay: tree.root.remove_child(n); n.free()
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _earn(hold_n: int) -> int:
	var w := _w()
	var i := 0
	for c in Cases.roster():
		w.set_disposition(String(c["id"]), "hold" if i < hold_n else "discharge")
		i += 1
	var p := w.projected()
	return int(p["earned"])

func run() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	print("NO readmissions (ward 1), earnings by number of beds held:")
	for n in range(0, 6):
		print("   hold %d -> %d" % [n, _earn(n)])
	GameState.set_flag(Cases.READMIT_FLAG, ["marchetti", "oduya"])
	print("TWO readmissions on the same ward:")
	for n in range(0, 6):
		print("   hold %d -> %d" % [n, _earn(n)])
