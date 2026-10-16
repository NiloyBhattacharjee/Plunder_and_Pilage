class_name ShipLooksUI
## The shipwright's pattern book: rename a ship and choose her paint, sails and figurehead. Used in port
## shipyards and at your base's yard. `v` is the ship (your flagship's state, or a squadron ship); `s` pays.


static func build(box: Node, v: Dictionary, s: Dictionary, done: Callable) -> void:
	var L: Dictionary = Data.rules.ship_looks
	UIKit.label(box, "Her name and looks", "Paint and sails are for show (black sails aside); a figurehead matters to a superstitious crew.", Style.c("header"))
	var row := UIKit.row(box)
	UIKit.label(row, "Name: ")
	var edit := LineEdit.new()
	edit.text = v.name
	edit.custom_minimum_size.x = 300
	row.add_child(edit)
	UIKit.button(row, "Rename", func():
		var n := edit.text.strip_edges()
		if n != "":
			v.name = n
		done.call("She's the %s now." % v.name))
	for part in ["paint", "sails", "figurehead"]:
		var table: Dictionary = L[{"paint": "paints", "sails": "sails", "figurehead": "figureheads"}[part]]
		var r := UIKit.row(box)
		UIKit.label(r, part.capitalize() + ": ").custom_minimum_size.x = 110
		var now: String = v.get("look", {}).get(part, table.keys()[0])
		for id in table:
			var o: Dictionary = table[id]
			var cost := ShipStats.look_cost(v, part, id)
			var b := UIKit.button(r, o.name, func():
				s.gold -= cost
				v.look = v.get("look", {})
				v.look[part] = id
				done.call("%s: %s, for %d gold." % [part.capitalize(), o.name.to_lower(), cost]),
				"%s%d gold." % [o.get("description", "") + "\n" if o.has("description") else "", cost])
			b.disabled = id == now or cost > s.gold
			if o.has("color"):
				b.add_theme_color_override("font_color", Color(o.color).darkened(0.1) if Color(o.color).v < 0.95 else Style.c("wax_text"))
