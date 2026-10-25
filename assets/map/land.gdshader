shader_type canvas_item;
// The land on the world map, HD-2D style: a stylised relief (assets/map/height.png, made by
// tools/make_heightmap.py) lit from the upper left, so hills and mountains stand up off the page.
// Colour climbs from beach to grass to forest floor to bare rock, painted as pixel art: speckled grass, a dark
// mossy floor where the trees stand (scripts/tree_layer.gd draws them), cracked rock, snowy-grey peaks. Pixel-snapped on a world grid
// and dithered, so it reads as pixel art at any zoom.
// The map is seen from a camera tilted toward the north (Geo.TILT), so the hills really rise: each pixel shows the
// first ground that the camera's ray meets, coming over the land to the south of it.

uniform sampler2D height_map : filter_linear;
uniform vec2 map_size = vec2(3829.0, 2400.0);
uniform float art_px = 1.5;          // map pixels per art pixel
uniform float relief = 7.0;          // how steep the light makes the slopes look
uniform float tilt = 0.7;            // Geo.TILT: the sine of the camera's elevation
uniform float hill_height = 70.0;    // how many map pixels the highest peak rises
uniform vec3 sand : source_color = vec3(0.89, 0.81, 0.58);
uniform vec3 grass : source_color = vec3(0.47, 0.66, 0.29);
uniform vec3 forest : source_color = vec3(0.19, 0.42, 0.22);
uniform vec3 rock : source_color = vec3(0.55, 0.48, 0.39);
uniform vec3 peak : source_color = vec3(0.80, 0.77, 0.72);

varying vec2 mp;

void vertex() {
	mp = VERTEX;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// 4x4 ordered dither, -0.5..0.5: smooth shading in a few flat pixel colours, without bands
float bayer(vec2 a) {
	int x = int(mod(a.x, 4.0)), y = int(mod(a.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return float(m[y * 4 + x]) / 16.0 - 0.5;
}

float h_at(vec2 p) {
	return texture(height_map, p / map_size).r;
}

// The ray through this point on the ground came down over the land to the south, dropping 1/cot per map pixel.
// Walking it from the camera's side, the first ground as high as the ray is what's seen here.
vec2 surface(vec2 p) {
	float cot = sqrt(1.0 - tilt * tilt) / tilt;
	float reach = hill_height * cot;
	float step_d = reach / 32.0;
	for (int i = 32; i > 0; i--) {
		float d = step_d * float(i);
		if (h_at(p + vec2(0.0, d)) * hill_height >= d / cot) {
			float lo = d, hi = d + step_d;  // ground at lo, air at hi: narrow it down, or the slopes come out in steps
			for (int k = 0; k < 5; k++) {
				float mid = (lo + hi) * 0.5;
				if (h_at(p + vec2(0.0, mid)) * hill_height >= mid / cot) { lo = mid; } else { hi = mid; }
			}
			return p + vec2(0.0, lo);
		}
	}
	return p;
}

void fragment() {
	vec2 a = floor(mp / art_px);  // this art pixel
	vec2 p = surface((a + 0.5) * art_px);
	vec2 ga = floor(p / art_px);  // the art pixel of the ground actually seen (up a slope, south of this one)
	float h = h_at(p);
	float step_px = art_px * 3.0;
	vec3 n = normalize(vec3((h_at(p - vec2(step_px, 0.0)) - h_at(p + vec2(step_px, 0.0))) * relief,
		(h_at(p - vec2(0.0, step_px)) - h_at(p + vec2(0.0, step_px))) * relief, 1.0));
	float light = clamp(dot(n, normalize(vec3(-0.55, -0.65, 0.7))), 0.0, 1.0);

	float patch = noise(ga / 14.0) - 0.5;  // meadows and thickets: broad changes of shade
	vec3 g = grass * (1.0 + patch * 0.18) * (0.93 + 0.14 * step(0.6, hash(ga)));  // speckled grass
	vec3 col = mix(sand * (0.97 + 0.06 * hash(ga)), g, smoothstep(0.0, 0.06, h));
	float woods = smoothstep(0.14, 0.3, h + patch * 0.12) * (1.0 - smoothstep(0.82, 0.9, h));
	vec3 floor_col = forest * (0.85 + 0.2 * step(0.7, hash(ga + 3.0)));  // under the trees: dark, mossy
	col = mix(col, floor_col, step(0.5, woods + (hash(ga + 3.0) - 0.5) * 0.3));
	float crag = step(0.78, noise(ga / vec2(3.0, 1.2)));  // rock: ledges and cracks
	col = mix(col, rock * (1.0 - crag * 0.25), smoothstep(0.84, 0.9, h + patch * 0.1));
	col = mix(col, peak, step(0.97, h + (hash(ga + 9.0) - 0.5) * 0.04));

	float shade = mix(0.6, 1.2, light) + bayer(a) * 0.08;
	col *= floor(shade * 8.0 + 0.5) / 8.0;  // light in steps, dithered between them
	col = mix(mix(col, sand * 0.5, 0.75), col, COLOR.r);  // the coastline is drawn dark: a dark, wet edge
	COLOR = vec4(col, 1.0);
}
