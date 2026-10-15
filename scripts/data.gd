extends Node
## Autoload "Data": loads every JSON table in res://data/ at startup.
## Use Data.table("ports"), Data.rules, Data.map. Add a new JSON file and it is loaded automatically.

const DATA_DIR := "res://data/"

# Required fields per table, and fields that must reference ids in another table.
# A bad entry fails loudly at startup naming the file, entry and field.
const SCHEMA := {
	"ports": {"required": ["name", "faction", "lat", "lon", "produces", "wants"],
		"refs": {"faction": "factions", "produces": "goods", "wants": "goods"}},
	"goods": {"required": ["name", "base_price"]},
	"factions": {"required": ["name", "color"]},
	"ships": {"required": ["name", "speed_knots", "polar", "hull", "crew_max", "cargo"]},
}

var tables := {}
var rules: Dictionary
var map: Dictionary  # coastline polygons + projection, from tools/build_map.py
var errors := PackedStringArray()


func _init() -> void:
	# _init (not _ready) so other autoloads can use Data in their own _ready.
	for file in DirAccess.get_files_at(DATA_DIR):
		if file.ends_with(".json"):
			tables[file.get_basename()] = read_json(DATA_DIR + file)
	rules = tables.get("rules", {})
	map = read_json(DATA_DIR + "map/coastline.json")
	errors = validate(tables)
	for e in errors:
		push_error("Data: " + e)


func table(name: String) -> Dictionary:
	return tables[name]


static func read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Data: %s is missing or not a JSON object" % path)
		return {}
	return parsed


static func validate(all: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for tname in SCHEMA:
		if not all.has(tname):
			out.append("missing table %s.json" % tname)
			continue
		var spec: Dictionary = SCHEMA[tname]
		var refs: Dictionary = spec.get("refs", {})
		for id in all[tname]:
			var entry: Dictionary = all[tname][id]
			for field in spec.required:
				if not entry.has(field):
					out.append("%s.json: '%s' is missing '%s'" % [tname, id, field])
			for field in refs:
				var target: Dictionary = all.get(refs[field], {})
				var values = entry.get(field, [])
				for v in (values if values is Array else [values]):
					if not target.has(v):
						out.append("%s.json: '%s'.%s = '%s' is not in %s.json" % [tname, id, field, v, refs[field]])
	return out
