extends Sprite2D
## The sea, drawn by assets/map/sea.gdshader from the terrain mask (one texel per terrain cell).
## Also reused for the paper overlay (set `shader_path` to the paper shader).

@export_file("*.gdshader") var shader_path := "res://assets/map/sea.gdshader"


func _ready() -> void:
	var mask: Texture2D = load("res://data/map/terrain.png")
	texture = mask
	centered = false
	scale = Vector2.ONE * Data.map.cell_px
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("map_size", Vector2(Data.map.size[0], Data.map.size[1]))
	mat.set_shader_parameter("mask_soft", mask)
	mat.set_shader_parameter("mask_near", mask)
	for key in ["deep", "shallow", "reef", "ink", "parchment"]:
		mat.set_shader_parameter(key + "_color" if key in ["deep", "shallow", "reef"] else key, Style.c(key))
	material = mat
