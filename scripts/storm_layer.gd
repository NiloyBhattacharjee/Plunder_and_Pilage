extends Node2D
## Storms on the map: the clouds, rain and lightning are drawn by the map's cloud shader (assets/map/paper.gdshader),
## which this feeds with where each storm is every frame; this layer writes each storm's name over it.

const KINDS := {"squall": 1, "hurricane": 2, "norther": 3, "fog": 4, "calm": 5}
const MAX := 8  # the shader's array size


func _process(_delta: float) -> void:
	var clouds: ShaderMaterial = $"../Paper".material  # set up in its own _ready, after this one
	var list := PackedVector4Array()
	for s in Weather.storms.slice(0, MAX):
		list.append(Vector4(s.pos.x, s.pos.y, s.radius, KINDS.get(s.kind, 1)))
	list.resize(MAX)
	clouds.set_shader_parameter("storms", list)
	clouds.set_shader_parameter("storm_count", mini(Weather.storms.size(), MAX))
	queue_redraw()


func _draw() -> void:
	for s in Weather.storms:
		draw_set_transform(s.pos, 0.0, Geo.UPRIGHT)
		draw_string(Style.font("italic"), Vector2(-60, 0), Data.rules.storms[s.kind].name, HORIZONTAL_ALIGNMENT_CENTER, 120, 20,
			Color(0.4, 0.42, 0.48, 0.9) if s.kind == "fog" else Color(0.92, 0.94, 1.0, 0.9))
	draw_set_transform(Vector2.ZERO)
