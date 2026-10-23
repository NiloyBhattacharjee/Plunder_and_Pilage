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
	Economy.model.stock.havana.wine = 3.0
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
	assert_eq(Economy.stock("havana", "wine"), 3.0)
	assert_true(Ports.known.has("havana"))
	assert_eq(Weather.storms[0].pos, storm_pos)


func test_missing_file_fails_cleanly():
	assert_eq(SaveGame.load_game(world, "user://nope.json"), ERR_FILE_NOT_FOUND)


func test_continue_without_a_valid_save_starts_a_default_game():
	WorldMap.start_config = {"load": true}
	var w = load("res://scenes/world_map.tscn").instantiate()
	add_child_autofree(w)
	WorldMap.start_config = {}
	assert_false(w.ship.state.is_empty())
	assert_true(People.chars.has(w.ship.state.captain))


func test_saving_over_a_save_replaces_it_whole():
	world.ship.state.gold = 1.0
	assert_eq(SaveGame.save_game(world, PATH), OK)
	world.ship.state.gold = 2.0
	assert_eq(SaveGame.save_game(world, PATH), OK, "the new save is swapped in over the old one")
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "nothing half-written left behind")
	world.ship.state.gold = 0.0
	SaveGame.load_game(world, PATH)
	assert_eq(world.ship.state.gold, 2.0)
