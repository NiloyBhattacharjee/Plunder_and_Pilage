class_name Geo
## Map projection, units and compass maths.
## Projection constants come from data/map/coastline.json (written by tools/build_map.py) so both always match.
## Bearings are compass degrees: 0 = north (up the screen), 90 = east. Screen y points down.

const COMPASS := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


static func px_per_nm() -> float:
	return Data.map.projection.px_per_deg / 60.0


static func latlon_to_px(lat: float, lon: float) -> Vector2:
	var p: Dictionary = Data.map.projection
	var x_scale: float = cos(deg_to_rad(p.lat_ref)) * p.px_per_deg
	return Vector2((lon - p.lon_min) * x_scale, (p.lat_max - lat) * p.px_per_deg)


static func knots_to_px_per_day(knots: float) -> float:
	return knots * 24.0 * px_per_nm()


static func bearing(v: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)


static func from_bearing(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), -cos(r))


## Smallest angle between two bearings, 0..180.
static func angle_between(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


static func compass_name(deg: float) -> String:
	return COMPASS[int(round(fposmod(deg, 360.0) / 22.5)) % 16]
