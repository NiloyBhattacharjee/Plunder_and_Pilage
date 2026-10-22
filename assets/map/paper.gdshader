// Laid over the whole map: the shadows of clouds drifting west on the trade wind, a few thin clouds above them,
// and a soft darkening at the map's edges. (Once the chart's paper and foxing; the file keeps its name.)
// Storms (set each frame by scripts/storm_layer.gd) are dense, dark cloud with pixel rain and now and then a flash
// of lightning; a hurricane turns about its eye; fog is a white bank; a calm, a pale glassy sheen.
// `charted` would hide unexplored waters (white = charted); it's left white until exploration exists.
shader_type canvas_item;

uniform sampler2D charted : filter_linear, hint_default_white;
uniform vec4 parchment : source_color;
uniform vec4 ink : source_color;
uniform vec2 map_size = vec2(3829.0, 2400.0);
uniform float art_px = 1.5;
uniform vec4 storms[8];       // x, y, radius (map px), kind: 1 squall, 2 hurricane, 3 norther, 4 fog, 5 calm
uniform int storm_count = 0;

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
	for (int i = 0; i < storm_count; i++) {
		vec4 s = storms[i];
		vec2 d = px - s.xy;
		float r = length(d) / s.z;
		if (r > 1.3) {
			continue;
		}
		float k = 1.0 - smoothstep(0.55, 1.1, r + (noise(px / 40.0) - 0.5) * 0.35);  // a ragged edge, not a circle
		int kind = int(s.w + 0.5);
		if (kind == 5) {
			col = mix(col, vec4(1.0, 0.95, 0.75, 0.2), k);
			continue;
		}
		vec2 q = px;
		if (kind == 2) {  // a hurricane turns about its eye, faster near the middle
			float a = TIME * 0.2 + (1.0 - r) * 3.0;
			q = s.xy + mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * d;
		}
		float dense = smoothstep(0.3, 0.6, clouds(q * 1.4 + drift * 2.0));
		if (kind == 4) {
			col = mix(col, vec4(0.92, 0.93, 0.95, 0.35 + dense * 0.4), k);
			continue;
		}
		vec4 storm = vec4(0.16, 0.18, 0.24, 0.45 + dense * 0.4);
		if (kind == 2) {
			storm.a *= smoothstep(0.04, 0.14, r);  // the eye
		}
		float rain = step(0.94, hash(vec2(floor(px.x / (art_px * 2.0)), floor((px.y + px.x * 0.3 - TIME * 240.0) / (art_px * 8.0)))));
		storm = mix(storm, vec4(0.75, 0.8, 0.9, 0.7), rain * 0.6);
		if (kind != 3) {  // lightning: now and then the cloud lights up from inside
			float t = TIME * 0.7 + float(i) * 3.1;
			float flash = step(0.85, hash(vec2(floor(t), float(i)))) * step(fract(t), 0.1);
			storm = mix(storm, vec4(0.9, 0.92, 1.0, 0.8), flash * dense);
		}
		col = mix(col, storm, k);
	}
	col.a = floor(col.a * 8.0 + 0.5) / 8.0;
	COLOR = col;
}
