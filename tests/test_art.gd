extends GutTest
## The art pipeline: every path in data points at a real file, portraits rebuild identically from their seed
## and follow the story, and the theme builds from the palette.


func test_every_referenced_art_file_exists():
	for id in Data.table("ships"):
		var art: String = Data.table("ships")[id].art
		for f in ["hull.png", "hull_damaged.png", "sails_furled.png", "sails_half.png", "sails_full.png", "sails_torn.png"]:
			assert_true(ResourceLoader.exists(art.path_join(f)), art.path_join(f))
	for id in Data.table("flags"):
		assert_true(ResourceLoader.exists(Data.table("flags")[id].path), id)
	for id in Data.table("goods"):
		assert_true(ResourceLoader.exists(Data.table("goods")[id].icon), id)
	for layer in Data.table("portraits").parts:
		for part in Data.table("portraits").parts[layer]:
			assert_true(ResourceLoader.exists(part.path), part.path)
	for kind in Data.table("palette").fonts:
		assert_true(ResourceLoader.exists(Data.table("palette").fonts[kind]), kind)


func test_every_sound_has_files():
	for id in Sfx.SOUNDS:
		assert_false(Sfx.files(id).is_empty(), id)


func test_portrait_rebuilds_identically_from_its_seed():
	var c := People.generate({"nationality": "french"})
	var a := Portraits.layers(c, ["crew"]).map(func(l): return l.id)
	var saved: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(c))))
	var b := Portraits.layers(saved, ["crew"]).map(func(l): return l.id)
	assert_eq(a, b)


func test_portraits_follow_the_story():
	var c := People.generate()
	c.traits = []
	c.age = 25
	var before := Portraits.layers(c, ["crew"])
	c.traits = ["one_eyed", "hook_hand"]
	c.age = 60
	var after := Portraits.layers(c, ["crew"])
	var layers_after := after.map(func(l): return l.layer)
	assert_true("eyepatch" in layers_after)
	assert_true("hook" in layers_after)
	assert_true("wrinkles" in layers_after)
	# the rest of the face stays the same person
	for l in before:
		if l.layer in ["head", "eyes", "nose", "mouth"]:
			assert_true(after.any(func(x): return x.layer == l.layer and x.id == l.id), l.layer)


func test_role_picks_clothing():
	var c := People.generate()
	c.traits = []
	var gov := Portraits.layers(c, ["governor"]).filter(func(l): return l.layer == "body")
	assert_eq(gov[0].id, "governor_coat")
	var navy := Portraits.layers(c, ["navy"]).filter(func(l): return l.layer == "body")
	assert_eq(navy[0].id, "navy_coat")


func test_theme_builds_from_palette():
	var t: Theme = Style.build_theme()
	assert_not_null(t.default_font)
	assert_eq(t.get_type_variation_base("Title"), &"Label")
	assert_eq(t.get_color("font_color", "Label"), Style.c("ink"))


func test_ship_sprite_switches_layers_with_condition():
	var sp: Node2D = load("res://scenes/ship_sprite.tscn").instantiate()
	add_child_autofree(sp)
	sp.setup("brig", "england")
	sp.set_state(1.0, 1.0, 2)
	assert_string_contains(sp.get_node("Sails").texture.resource_path, "sails_full")
	sp.set_state(0.3, 0.2, 2)
	assert_string_contains(sp.get_node("Hull").texture.resource_path, "hull_damaged")
	assert_string_contains(sp.get_node("Sails").texture.resource_path, "sails_torn")
	sp.set_state(0.3, 0.2, 0, true)
	assert_string_contains(sp.get_node("Sails").texture.resource_path, "sails_furled")
	assert_false(sp.get_node("Flag").visible, "struck colours")


func test_map_trees_stand_on_land():
	var t0 := Time.get_ticks_msec()
	var trees := TreeLayer.place()
	gut.p("%d trees placed in %d ms" % [trees.size(), Time.get_ticks_msec() - t0])
	assert_gt(trees.size(), 1000)
	var terrain := TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	for t in trees:
		assert_eq(terrain.at(t.foot), TerrainGrid.LAND, str(t.foot))
