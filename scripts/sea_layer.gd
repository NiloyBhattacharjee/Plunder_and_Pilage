extends Sprite2D
## The sea, drawn by assets/map/sea.gdshader from the terrain mask (one texel per terrain cell).
## Also reused for the paper overlay (set `shader_path` to the paper shader).

@export_file("*.gdshader") var shader_path := "res://assets/map/sea.gdshader"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # the terrain mask is coarse: blend it, let the pixel pass do the pixels
	var mask: Texture2D = load("res://data/map/terrain.png")
	texture = mask
	centered = false
	scale = Vector2.ONE * Data.map.cell_px
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("map_size", Vector2(Data.map.size[0], Data.map.size[1]))
	mat.set_shader_parameter("mask_soft", mask)
	mat.set_shader_parameter("mask_near", mask)
	for key in ["deep", "shallow", "reef"]:
		mat.set_shader_parameter(key + "_color", Style.c(key))
	mat.set_shader_parameter("ink", Style.c("chart_ink"))
	mat.set_shader_parameter("parchment", Style.c("chart_paper"))
	mat.set_shader_parameter("art_px", float(Data.table("palette").map_pixel))
	material = mat
