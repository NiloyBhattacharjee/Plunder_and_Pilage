// The sea on the world map, HD-2D style (like the battle sea): deep blue offshore, turquoise over the banks,
// pale water over the reefs, surf along the coasts, slow pixel waves with foam on the crests, and glints of sun.
// Snapped to a world grid of art pixels and posterised. Colours come from data/palette.json (scripts/sea_layer.gd).
shader_type canvas_item;

uniform sampler2D mask_soft : filter_linear;   // terrain mask: r 0 deep, 0.5 shallow, 0.75 reef, 1 land
uniform sampler2D mask_near : filter_nearest;
uniform vec4 deep_color : source_color;
uniform vec4 shallow_color : source_color;
uniform vec4 reef_color : source_color;
uniform vec4 ink : source_color;          // unused here; kept for the chart look
uniform vec4 parchment : source_color;
uniform vec2 map_size = vec2(3829.0, 2400.0);
uniform float art_px = 1.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 px = (floor(UV * map_size / art_px) + 0.5) * art_px;
	vec2 uv = px / map_size;
	// one texel per terrain cell: a small tent blur rounds the stair-steps into smooth banks
	vec2 tx = 1.0 / vec2(textureSize(mask_soft, 0));
	float soft = 0.0;
	float wide = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			float wgt = float(3 - abs(i)) * float(3 - abs(j));
			soft += min(texture(mask_soft, uv + vec2(float(i), float(j)) * tx * 0.6).r, 0.5) * wgt;
			wide += texture(mask_soft, uv + vec2(float(i), float(j)) * tx * 2.5).r * wgt;
		}
	}
	float depth = soft / 81.0 * 2.0;     // 0 deep .. 1 shallow
	float coast = wide / 81.0;           // rises toward land: where the surf is
	vec3 deep2 = deep_color.rgb * 0.75;
	vec3 col = mix(deep2, deep_color.rgb, smoothstep(0.0, 0.35, depth + noise(px / 140.0) * 0.25));
	col = mix(col, shallow_color.rgb, smoothstep(0.42, 0.6, depth));
	float r = texture(mask_near, uv).r;
	if (r > 0.6 && r < 0.9) {            // reef: pale water and broken white
		col = mix(col, reef_color.rgb, 0.7);
		col = mix(col, vec3(0.95), step(0.82, noise(px / 3.0 + TIME * 0.4)) * 0.6);
	}
	// waves: long swells drifting west on the trade wind, foam on the crests, only in open water
	float swell = sin(px.x * 0.035 + px.y * 0.012 + TIME * 0.9 + noise(px / 80.0) * 5.0);
	float crest = step(0.985, swell) * step(0.62, noise(px / 14.0 + vec2(TIME * 0.05, 0.0)));
	col = mix(col, vec3(0.9, 0.96, 1.0), crest * 0.45 * (1.0 - depth));
	// surf: bands of foam rolling in toward the beaches
	float band = smoothstep(0.35, 0.7, coast) * (1.0 - step(0.97, coast));
	float roll = step(0.75, sin(coast * 38.0 - TIME * 2.2 + noise(px / 30.0) * 3.0));
	col = mix(col, vec3(0.94, 0.98, 1.0), band * roll * 0.6);
	// glints of sun
	col += vec3(0.7) * step(0.9994, hash(floor(px / 3.0) + floor(TIME * 2.0))) * (1.0 - depth);
	COLOR = vec4(floor(col * 20.0 + 0.5) / 20.0, 1.0);
}
