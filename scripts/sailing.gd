class_name Sailing
## Points of sail. "Angle off the wind": 0 = heading straight into the wind, 180 = wind dead astern.
## A ship's polar is a list of [angle, speed fraction] pairs from ships.json.


static func polar_factor(polar: Array, angle: float) -> float:
	for i in range(1, polar.size()):
		if angle <= polar[i][0]:
			var a0: float = polar[i - 1][0]
			var a1: float = polar[i][0]
			return lerpf(polar[i - 1][1], polar[i][1], (angle - a0) / (a1 - a0))
	return polar[-1][1]


## Best way to make progress toward a target `angle` off the wind.
## If sailing straight is slow (upwind, or dead downwind for some rigs) the ship tacks or gybes:
## it zig-zags at `sail_angle` and its progress along the line is speed * cos(deviation).
## Returns {factor: progress along the line as a fraction of top speed, sail_angle, tacking}.
static func best_course(polar: Array, angle: float) -> Dictionary:
	var best := polar_factor(polar, angle)
	var best_angle := angle
	for a in range(0, 181, 5):
		var dev := absf(a - angle)
		if dev < 90.0:
			var v := polar_factor(polar, a) * cos(deg_to_rad(dev))
			if v > best * 1.02:  # only tack for a real gain
				best = v
				best_angle = a
	return {"factor": best, "sail_angle": best_angle, "tacking": best_angle != angle}


static func point_of_sail(angle: float) -> String:
	if angle < 30: return "in irons"
	if angle < 60: return "close-hauled"
	if angle < 110: return "beam reach"
	if angle < 160: return "broad reach"
	return "running"
