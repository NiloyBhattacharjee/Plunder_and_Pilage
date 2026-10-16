// Laid over the whole map: the shadows of clouds drifting west on the trade wind, a few thin clouds above them,
// and a soft darkening at the map's edges. (Once the chart's paper and foxing; the file keeps its name.)
// `charted` would hide unexplored waters (white = charted); it's left white until exploration exists.
shader_type canvas_item;

uniform sampler2D charted : filter_linear, hint_default_white;
uniform vec4 parchment : source_color;
uniform vec4 ink : source_color;
uniform vec2 map_size = vec2(3829.0, 2400.0);
uniform float art_px = 1.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float clouds(vec2 p) {
	return noise(p / 260.0) * 0.6 + noise(p / 90.0) * 0.3 + noise(p / 30.0) * 0.1;
}

void fragment() {
	vec2 px = (floor(UV * map_size / art_px) + 0.5) * art_px;
	vec2 drift = vec2(TIME * 6.0, TIME * 1.5);
	float shadow = smoothstep(0.62, 0.7, clouds(px + drift + vec2(40.0, 60.0)));   // offset: the sun is high in the east
	float cloud = smoothstep(0.66, 0.76, clouds(px + drift));
	vec2 e = min(UV, 1.0 - UV);
	float vignette = 1.0 - smoothstep(0.0, 0.05, min(e.x * map_size.x / map_size.y, e.y));
	vec4 col = vec4(0.05, 0.08, 0.15, shadow * 0.22 + vignette * 0.5);
	col = mix(col, vec4(0.97, 0.98, 1.0, 0.55), cloud * 0.8);
	col.a = floor(col.a * 8.0 + 0.5) / 8.0;
	COLOR = col;
}
