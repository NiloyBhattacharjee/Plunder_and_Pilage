// Paper laid over the whole chart: grain, foxing and a darker vignette towards the edges.
// `charted` hides what hasn't been explored yet (white = charted); leave it white until exploration exists.
shader_type canvas_item;

uniform sampler2D charted : filter_linear, hint_default_white;
uniform vec4 parchment : source_color;
uniform vec4 ink : source_color;
uniform vec2 map_size = vec2(3829.0, 2400.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 px = UV * map_size;
	float grain = noise(px / 1.7) * 0.5 + noise(px / 9.0) * 0.5;
	float foxing = smoothstep(0.7, 0.9, noise(px / 140.0)) * 0.5;
	vec2 e = min(UV, 1.0 - UV);
	float vignette = 1.0 - smoothstep(0.0, 0.08, min(e.x * map_size.x / map_size.y, e.y));
	float a = grain * 0.05 + foxing * 0.08 + vignette * 0.25;
	vec4 mark = vec4(ink.rgb, a);
	float c = texture(charted, UV).r;
	COLOR = mix(vec4(parchment.rgb, 0.96), mark, c);
}
