class_name SaveGame
## Saves and loads the whole game as one JSON file. Each system provides save_state()/load_state().
## JSON.from_native keeps Godot types (Vector2, ints vs floats) intact in the JSON.
## Saves live in user:// (on Windows: %APPDATA%/Godot/app_userdata/Plunder and Pillage/saves/).

const QUICKSAVE := "user://saves/quicksave.json"
const VERSION := 11


static func save_game(world: Node, path := QUICKSAVE) -> Error:
	var data := {
		"version": VERSION,
		"clock": Clock.save_state(),
		"weather": Weather.save_state(),
		"ports": Ports.save_state(),
		"people": People.save_state(),
		"factions": Factions.save_state(),
		"politics": Politics.save_state(),
		"bonds": Bonds.save_state(),
		"contracts": Contracts.save_state(),
		"events": Events.save_state(),
		"shipping": world.shipping.save_state(),
		"ship": world.ship.save_state(),
	}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(JSON.from_native(data), "\t"))
	return OK


static func load_game(world: Node, path := QUICKSAVE) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		return ERR_PARSE_ERROR
	var data: Dictionary = JSON.to_native(parsed)
	if data.get("version", 0) != VERSION:
		return ERR_INVALID_DATA
	Clock.load_state(data.clock)
	Weather.load_state(data.weather)
	Ports.load_state(data.ports)
	People.load_state(data.people)
	Factions.load_state(data.factions)
	Politics.load_state(data.politics)
	Bonds.load_state(data.bonds)
	Contracts.load_state(data.contracts)
	Events.load_state(data.events)
	world.shipping.load_state(data.shipping)
	world.ship.load_state(data.ship)
	return OK
