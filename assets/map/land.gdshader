shader_type canvas_item;
// The land on the world map, HD-2D style: a stylised relief (assets/map/height.png, made by
// tools/make_heightmap.py) lit from the upper left, so hills and mountains stand up off the page.
// Colour climbs from beach to grass to forest to bare rock; the jungle tile adds texture. Pixel-snapped on a
// world grid and posterised, so it reads as pixel art at any zoom.
// The map is seen from a camera tilted toward the north (Geo.TILT), so the hills really rise: each pixel shows the
// first ground that the camera's ray meets, coming over the land to the south of it.

uniform sampler2D height_map : filter_linear;
uniform sampler2D detail : repeat_enable, filter_nearest;
uniform vec2 map_size = vec2(3829.0, 2400.0);
uniform float art_px = 1.5;          // map pixels per art pixel
uniform float relief = 9.0;          // how steep the light makes the slopes look
uniform float tilt = 0.7;            // Geo.TILT: the sine of the camera's elevation
uniform float hill_height = 130.0;    // how many map pixels the highest peak rises
uniform vec3 sand : source_color = vec3(0.86, 0.78, 0.55);
uniform vec3 grass : source_color = vec3(0.42, 0.62, 0.30);
uniform vec3 forest : source_color = vec3(0.20, 0.40, 0.22);
uniform vec3 rock : source_color = vec3(0.50, 0.44, 0.36);
uniform vec3 peak : source_color = vec3(0.70, 0.66, 0.60);

varying vec2 mp;

void vertex() {
	mp = VERTEX;
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
	vec2 p = surface((floor(mp / art_px) + 0.5) * art_px);
	float h = h_at(p);
	float step_px = art_px * 3.0;
	vec3 n = normalize(vec3((h_at(p - vec2(step_px, 0.0)) - h_at(p + vec2(step_px, 0.0))) * relief,
		(h_at(p - vec2(0.0, step_px)) - h_at(p + vec2(0.0, step_px))) * relief, 1.0));
	float light = clamp(dot(n, normalize(vec3(-0.55, -0.65, 0.7))), 0.0, 1.0);
	vec3 col = mix(sand, grass, smoothstep(0.0, 0.06, h));
	col = mix(col, forest, smoothstep(0.18, 0.45, h));
	col = mix(col, rock, smoothstep(0.8, 0.93, h));
	col = mix(col, peak, smoothstep(0.96, 1.0, h));
	vec3 tex = texture(detail, p / 96.0).rgb;
	col *= mix(vec3(1.0), tex / vec3(0.33, 0.48, 0.25), 0.35 * smoothstep(0.04, 0.2, h) * (1.0 - smoothstep(0.6, 0.8, h)));
	col *= mix(0.62, 1.18, light);
	col = mix(col * 0.35, col, COLOR.r);  // the coastline is drawn black: keep it a dark edge
	COLOR = vec4(floor(col * 18.0 + 0.5) / 18.0, 1.0);
}
