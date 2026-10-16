extends GutTest


func test_shipped_data_is_valid():
	assert_eq(Data.errors, PackedStringArray(), "data/ files should validate cleanly")
	assert_between(Data.table("ports").size(), 12, 15)


func test_validation_catches_missing_field_and_bad_reference():
	var bad := Data.tables.duplicate(true)
	bad.ports.port_royal.erase("lat")
	bad.ports.havana.laws.contraband = ["unicorns"]
	var errors := Data.validate(bad)
	assert_eq(errors.size(), 2)
	assert_string_contains(errors[0] + errors[1], "unicorns")
	assert_string_contains(errors[0] + errors[1], "'lat'")
