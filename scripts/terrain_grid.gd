class_name TerrainGrid
extends RefCounted
## Coarse terrain mask (data/map/terrain.png) for gameplay queries and route finding.
## Each mask pixel is one cell of `cell_px` map pixels: 0 deep, 128 shallow, 255 land.

enum { DEEP, SHALLOW, LAND }

var image: Image
var cell_px: int
var astar := AStarGrid2D.new()  # Godot's built-in grid pathfinder
var _shallow_cells: Array[Vector2i] = []
var shallow_cost := 1.0


func _init(mask: Image, cell: int) -> void:
	image = mask
	cell_px = cell
	astar.region = Rect2i(Vector2i.ZERO, image.get_size())
	astar.cell_size = Vector2(cell, cell)
	astar.offset = Vector2(cell, cell) * 0.5  # path points at cell centres
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in image.get_height():
		for x in image.get_width():
			match _cell_type(Vector2i(x, y)):
				LAND: astar.set_point_solid(Vector2i(x, y))
				SHALLOW: _shallow_cells.append(Vector2i(x, y))


## How much routes avoid shallow water: 1 for shallow-draught ships, higher for deep keels.
func set_shallow_cost(cost: float) -> void:
	shallow_cost = cost
	for c in _shallow_cells:
		astar.set_point_weight_scale(c, cost)


func at(pos: Vector2) -> int:
	return _cell_type(to_cell(pos))


func to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / cell_px).floor())


func _cell_type(c: Vector2i) -> int:
	if not astar.region.has_point(c):
		return LAND  # off-map counts as land so nothing sails away
	var v := image.get_pixelv(c).r8
	return LAND if v > 200 else (SHALLOW if v > 64 else DEEP)


## Nearest navigable cell centre to `pos`, searching outward ring by ring. Returns pos if none nearby.
func nearest_sea(pos: Vector2, max_cells := 12) -> Vector2:
	var c := to_cell(pos)
	for r in max_cells + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and _cell_type(c + Vector2i(dx, dy)) != LAND:
					return (Vector2(c + Vector2i(dx, dy)) + Vector2(0.5, 0.5)) * cell_px
	return pos


## Sea route from `from` to `to`, smoothed into straight legs. Empty if unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := to_cell(nearest_sea(from))
	var b := to_cell(nearest_sea(to))
	if a == b or astar.is_point_solid(b):
		return PackedVector2Array([to]) if at(to) != LAND else PackedVector2Array()
	var raw := astar.get_point_path(a, b)
	if raw.is_empty():
		return raw
	if at(from) != LAND:
		raw[0] = from
	if at(to) != LAND:
		raw[-1] = to
	return _smooth(raw)


# Greedy string-pulling: from each point, keep extending the straight leg while the line stays clear.
# ponytail: many line checks per route; fine for one route per click, cache or use a navmesh if NPC fleets route often.
func _smooth(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < path.size() - 1:
		var j := i + 1
		while j + 1 < path.size() and _clear_leg(path[i], path[j + 1]):
			j += 1
		out.append(path[j])
		i = j
	return out  # excludes the start point: the ship is already there


# A smoothed leg must not cut across shallows the weighted route went around (unless it starts or ends in them).
func _clear_leg(a: Vector2, b: Vector2) -> bool:
	var avoid := shallow_cost > 1.0 and at(a) != SHALLOW and at(b) != SHALLOW
	return clear_line(a, b, SHALLOW if avoid else LAND)


## True if the straight line from a to b never touches terrain of type `blocked` or worse.
func clear_line(a: Vector2, b: Vector2, blocked := LAND) -> bool:
	var steps := int(a.distance_to(b) / (cell_px * 0.5)) + 1
	for k in steps + 1:
		if at(a.lerp(b, float(k) / steps)) >= blocked:
			return false
	return true
