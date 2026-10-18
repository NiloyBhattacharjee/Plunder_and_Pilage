class_name Tutorial
## First-voyage hints: a short word the first time you meet each part of the game (data/tutorial.json).
## On for a new game unless you untick it; each hint shows once, and "No more hints" turns them off.
## A hint is either its own dialog (show) or a paragraph added to a dialog that's opening anyway (note).


static func on(s: Dictionary) -> bool:
	return s.get("tutorial", false)


static func _take(s: Dictionary, id: String) -> bool:
	if not on(s) or id in s.get("tutorial_seen", []):
		return false
	if not s.has("tutorial_seen"):
		s.tutorial_seen = []
	s.tutorial_seen.append(id)
	return true


## The hint as a paragraph for a dialog that's already opening, or "" if it's been seen (or hints are off).
static func note(s: Dictionary, id: String) -> String:
	return "\n\n[First voyage] " + Data.table("tutorial")[id].text if _take(s, id) else ""


## The hint as its own dialog, with time stopped while you read it.
static func show(world: Node, id: String) -> void:
	var s: Dictionary = world.ship.state
	if not _take(s, id):
		return
	var was_running := Clock.speed_index > 0
	UIKit.pause_clock()
	var h: Dictionary = Data.table("tutorial")[id]
	var pick: int = await world.dialog.ask(h.title, h.text, [{"text": "Got it"}, {"text": "No more hints", "tooltip": "Turn the first-voyage hints off for this game."}])
	if pick == 1:
		s.tutorial = false
	if was_running:
		UIKit.resume_clock()
