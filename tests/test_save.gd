extends GutTest

const PATH := "user://test_save.json"
var world


func before_each():
	world = load("res://scenes/world_map.tscn").instantiate()
	add_child_autofree(world)


func after_each():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	Clock.day = 0.0
	Ports.reset()
	Weather.storms = []


func test_round_trip_restores_world():
	world.ship.state.gold = 1234.0
	world.ship.state.cargo["cocoa"] = 7
	world.ship.position = Vector2(1500, 900)
	world.ship.route = PackedVector2Array([Vector2(1600, 950)])
	Clock.day = 42.5
	Ports.state.havana.stock.wine = 3.0
	Ports.record_prices("havana", 40)
	Weather.spawn_storm("hurricane")
	var storm_pos: Vector2 = Weather.storms[0].pos
	assert_eq(SaveGame.save_game(world, PATH), OK)

	world.ship.state.gold = 0.0
	world.ship.position = Vector2.ZERO
	Clock.day = 0.0
	Ports.reset()
	Weather.storms = []

	assert_eq(SaveGame.load_game(world, PATH), OK)
	assert_eq(world.ship.state.gold, 1234.0)
	assert_eq(world.ship.state.cargo.cocoa, 7)
	assert_eq(world.ship.position, Vector2(1500, 900))
	assert_eq(world.ship.route[0], Vector2(1600, 950))
	assert_eq(Clock.day, 42.5)
	assert_eq(Ports.state.havana.stock.wine, 3.0)
	assert_true(Ports.known.has("havana"))
	assert_eq(Weather.storms[0].pos, storm_pos)


func test_missing_file_fails_cleanly():
	assert_eq(SaveGame.load_game(world, "user://nope.json"), ERR_FILE_NOT_FOUND)
