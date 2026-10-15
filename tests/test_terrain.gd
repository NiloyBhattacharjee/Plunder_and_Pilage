extends GutTest


func _grid_with_wall() -> TerrainGrid:
	# 20x20 sea with a land wall at x=10 from y=0..15; the gap is at the bottom.
	var img := Image.create(20, 20, false, Image.FORMAT_L8)
	for y in 16:
		img.set_pixel(10, y, Color8(255, 255, 255))
	img.set_pixel(3, 3, Color8(128, 128, 128))
	return TerrainGrid.new(img, 4)


func test_cell_types():
	var g := _grid_with_wall()
	assert_eq(g.at(Vector2(2, 2)), TerrainGrid.DEEP)
	assert_eq(g.at(Vector2(13, 13)), TerrainGrid.SHALLOW)
	assert_eq(g.at(Vector2(42, 10)), TerrainGrid.LAND)
	assert_eq(g.at(Vector2(-5, 10)), TerrainGrid.LAND, "off-map counts as land")


func test_path_goes_around_land():
	var g := _grid_with_wall()
	var path := g.find_path(Vector2(10, 10), Vector2(70, 10))
	assert_false(path.is_empty())
	assert_eq(path[-1], Vector2(70, 10))
	var prev := Vector2(10, 10)
	for p in path:
		assert_true(g.clear_line(prev, p), "leg %s -> %s crosses land" % [prev, p])
		prev = p


func test_real_map_routes_port_royal_to_havana_around_cuba():
	var g := TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	var start := g.nearest_sea(Geo.latlon_to_px(17.937, -76.841))
	var goal := g.nearest_sea(Geo.latlon_to_px(23.136, -82.359))
	var path := g.find_path(start, goal)
	assert_false(path.is_empty())
	assert_lt(path.size(), 30, "smoothing should leave a handful of legs")
	var prev := start
	for p in path:
		assert_true(g.clear_line(prev, p))
		prev = p


func test_every_port_has_an_anchorage():
	var g := TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		var pos := Geo.latlon_to_px(p.lat, p.lon)
		assert_ne(g.at(g.nearest_sea(pos)), TerrainGrid.LAND, id)
