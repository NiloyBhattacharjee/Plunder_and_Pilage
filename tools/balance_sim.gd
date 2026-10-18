extends SceneTree
## Balance report: runs the parts of the game that can't be judged from a single playthrough, headless, and
## prints the numbers that matter. Tune data/rules.json, run it again, compare.
##
##   bin/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/balance_sim.gd -- --runs 20 --years 50
##
## 1. Wars of the moment: how often they start, how much of the time someone is at war, how many towns change hands.
## 2. The price on your head: a pirate taking --attacks ships a month (and sacking a town every --sack months).
## 3. Held towns: taxes against upkeep at each tax level, and the odds a garrison beats each expedition.
## 4. Invasion squadrons: the odds each smaller town falls.

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	# loaded now, not at startup: the report uses the autoloads, which only exist once the tree is up
	load("res://tools/balance_report.gd").new().run(root, _args())
	return true


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out
