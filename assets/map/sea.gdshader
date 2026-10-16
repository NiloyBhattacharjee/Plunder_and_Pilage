// Sea on the chart: depth tint from the terrain mask (deep -> shallow), stippled reefs, faint drifting
// wave strokes and paper grain. Colours come from data/palette.json (set by scripts/sea_layer.gd).
shader_type canvas_item;

uniform sampler2D mask_soft : filter_linear;   // terrain mask: r 0 deep, 0.5 shallow, 0.75 reef, 1 land
uniform sampler2D mask_near : filter_nearest;
uniform vec4 deep_color : source_color;
uniform vec4 shallow_color : source_color;
uniform vec4 reef_color : source_color;
uniform vec4 ink : source_color;
uniform vec2 map_size = vec2(3829.0, 2400.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 px = UV * map_size;
	// The mask is one texel per terrain cell: a small tent blur rounds the stair-steps into smooth banks.
	vec2 tx = 1.0 / vec2(textureSize(mask_soft, 0));
	float soft = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			float wgt = float(3 - abs(i)) * float(3 - abs(j));
			soft += min(texture(mask_soft, UV + vec2(float(i), float(j)) * tx * 0.6).r, 0.5) * wgt;
		}
	}
	float depth = soft / 81.0 * 2.0;    // 0 deep .. 1 shallow (land and reefs count as shallow)
	// a crisp edge along the middle of the soft mask follows the bank smoothly, with a faint gradient either side
	vec4 col = mix(deep_color, shallow_color, smoothstep(0.42, 0.58, depth) * 0.85 + depth * 0.15);
	float edge = 1.0 - smoothstep(0.0, fwidth(depth) * 1.5, abs(depth - 0.5));
	col = mix(col, ink, edge * 0.3);   // the dotted-line "soundings" contour of period charts
	float r = texture(mask_near, UV).r;
	if (r > 0.6 && r < 0.9) {                                    // reef: tint plus a stipple of ink dots
		col = mix(col, reef_color, 0.6);
		vec2 cell = fract(px / 7.0) - 0.5;
		col = mix(col, ink, step(length(cell), 0.12) * 0.55);
	}
	// wave strokes: short broken horizontal lines, only in deeper water, drifting slowly
	float n = noise(px / 60.0 + vec2(TIME * 0.02, 0.0));
	float stroke = smoothstep(0.92, 1.0, sin(px.y / 9.0 + n * 6.0)) * step(0.55, noise(px / 25.0 + TIME * 0.03));
	col = mix(col, ink, stroke * 0.10 * (1.0 - depth));
	col.rgb *= 0.97 + noise(px / 2.5) * 0.05;                   // paper grain
	COLOR = col;
}
