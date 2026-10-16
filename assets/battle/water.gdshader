shader_type spatial;
// The battle sea, HD-2D style: real 3D waves and light, but coloured on a world-space pixel grid with a few
// colour steps, so it reads as pixel art. Crests get pixel foam; the sun leaves glints.

uniform vec3 deep : source_color = vec3(0.04, 0.19, 0.32);
uniform vec3 shallow : source_color = vec3(0.10, 0.45, 0.55);
uniform vec3 foam : source_color = vec3(0.88, 0.94, 1.0);
uniform float px = 9.0;        // art pixels per world unit
uniform float swell = 1.0;     // storms raise it
uniform float steps = 14.0;    // colour steps

varying vec3 wpos;

float wave(vec2 p, float t) {
	return sin(p.x * 0.35 + t * 1.1) * 0.16 + sin(p.y * 0.55 + p.x * 0.2 + t * 0.8) * 0.12
		+ sin((p.x + p.y) * 0.9 - t * 1.7) * 0.05;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(wpos.xz, TIME) * swell;
}

void fragment() {
	vec2 p = floor(wpos.xz * px) / px;
	float h = wave(p, TIME) * swell;
	vec3 c = mix(deep, shallow, smoothstep(-0.25 * swell, 0.3 * swell, h));
	float crest = step(0.27 * swell, h + hash(floor(p * 2.0)) * 0.08);
	c = mix(c, foam, crest * 0.75);
	float glint = step(0.992, hash(floor(p * 3.0) + floor(TIME * 3.0)));
	ALBEDO = floor(c * steps + 0.5) / steps;
	ROUGHNESS = 0.65;
	SPECULAR = 0.2;
	EMISSION = foam * glint * 0.8;
}
