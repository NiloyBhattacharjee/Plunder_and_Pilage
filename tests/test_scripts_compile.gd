extends GutTest
## Loads every script and scene in the project, so UI code that tests don't exercise still fails here
## when it stops compiling.


func _files(dir: String, ext: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d), ext))
	return out


func test_all_scripts_compile():
	for dir in ["res://scripts", "res://ui"]:
		for path in _files(dir, ".gd"):
			var script = load(path)
			assert_not_null(script, path)


func test_all_scenes_load():
	for dir in ["res://scenes", "res://ui"]:
		for path in _files(dir, ".tscn"):
			assert_not_null(load(path), path)
