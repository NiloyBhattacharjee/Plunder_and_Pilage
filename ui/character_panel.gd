class_name CharacterPanel
extends PanelContainer
## One character up close: their level, the points and perks they've earned (you choose for the captain and
## officers), and, in port or at your own base, a new name and new looks from the barber and tailor.

signal closed

var c: Dictionary
var role := "officer"
var docked := false
var _body: VBoxContainer


static func open_for(parent: Node, character: Dictionary, as_role: String, in_port: bool) -> CharacterPanel:
	var p := CharacterPanel.new()
	p.c = character
	p.role = as_role
	p.docked = in_port
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -560
	p.offset_right = 560
	p.offset_top = -400
	p.offset_bottom = 400
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	UIKit.clear(self)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var title := UIKit.label(_body, c.name)
	title.theme_type_variation = &"Title"
	UIKit.label(_body, Growth.summary(c), "Experience from using skills (in battle, at sea, trading) also raises a character's level.", Style.c("header"))

	if int(c.get("points", 0)) > 0:
		UIKit.label(_body, "Spend a point (%d left):" % c.points, "", Style.c("header"))
		var g := UIKit.grid(_body, 6)
		for k in People.STATS + People.SKILLS:
			UIKit.label(g, "%s %d" % [People.SKILL_NAMES[k], People.value(c, k)], People.breakdown(c, k))
			var b := UIKit.button(g, " +1 ", func():
				Growth.raise(c, k)
				_build())
			var why := Growth.can_raise(c, k)
			b.disabled = why != ""
			b.tooltip_text = why
	if int(c.get("perk_picks", 0)) > 0:
		UIKit.label(_body, "Choose a perk:", "", Style.c("header"))
		var open := Growth.perks_open(c)
		if open.is_empty():
			UIKit.label(_body, "Nothing open yet: perks need skill. Raise one and come back.", "", Style.c("dim"))
		for id in open:
			var p: Dictionary = Data.table("perks")[id]
			UIKit.button(_body, "%s: %s" % [p.name, p.description], func():
				Growth.take_perk(c, id)
				_build(), "Needs %s." % Growth.perk_needs_text(id)).alignment = HORIZONTAL_ALIGNMENT_LEFT
	if c.has("focus"):  # your captain: a lifestyle to grow into
		UIKit.label(_body, "Focus", "One at a time. Every day in a focus teaches a little, and in time its perks. Change it whenever you like: what you learned in the others is kept.", Style.c("header"))
		var row := UIKit.row(_body)
		for f in Data.table("focus"):
			if f.begins_with("_"):
				continue
			var d: Dictionary = Data.table("focus")[f]
			var ladder := "\n".join(d.perks.map(func(p): return "%s %s: %s" % ["*" if Growth.has_perk(c, p) else "-", Data.table("perks")[p].name, Data.table("perks")[p].description]))
			var b := UIKit.button(row, ("> %s <" if c.focus == f else "  %s  ") % d.name, func():
				c.focus = f
				_build(), "%s\n\n%s\n\n%s" % [d.description, Growth.focus_text(c, f), ladder])
			b.disabled = c.focus == f
		if c.focus != "":
			UIKit.label(_body, Growth.focus_text(c, c.focus), "", Style.c("dim"))
	var locked: Array = Data.table("perks").keys().filter(func(id): return Growth.pickable(id) and not Growth.has_perk(c, id) and not id in Growth.perks_open(c))
	if not locked.is_empty():
		UIKit.label(_body, "Perks for later: " + ", ".join(locked.map(func(id): return Data.table("perks")[id].name)),
			"\n".join(locked.map(func(id): return "%s (needs %s): %s" % [Data.table("perks")[id].name, Growth.perk_needs_text(id), Data.table("perks")[id].description])),
			Style.c("dim"))

	UIKit.label(_body, "")
	UIKit.label(_body, "Name and looks", "", Style.c("header"))
	if docked or not Data.rules.growth.looks_need_port:
		var row := UIKit.row(_body)
		var edit := LineEdit.new()
		edit.text = c.name
		edit.custom_minimum_size.x = 360
		edit.text_submitted.connect(func(t): _rename(t))
		edit.focus_exited.connect(func(): _rename(edit.text))
		row.add_child(edit)
		var looks := LooksEditor.new()
		_body.add_child(looks)
		looks.edit(c, role)
	else:
		_body.add_child(Portrait.make(c, role, 128))
		UIKit.label(_body, "A barber and a tailor can be found in any port, or at your own base.", "", Style.c("dim"))
	UIKit.button(_body, "  Done  ", func():
		closed.emit()
		queue_free())


func _rename(t: String) -> void:
	t = t.strip_edges()
	if t != "" and t != c.name:
		c.history.append("Now goes by %s." % t)
		c.name = t
