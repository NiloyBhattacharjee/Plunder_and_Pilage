shader_type canvas_item;
// HD-2D's miniature look on the world map (world_map.gd _pixel_layers): the top and bottom of the view drift out of
// focus, and a little haze lies over the far (northern) edge. The names and the HUD are drawn above it, sharp.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float focus = 0.36;    // half the height of the sharp band, as a share of the screen
uniform float centre = 0.55;   // where the band sits (a little below the middle: the ship)
uniform float blur = 1.3;      // how far out of focus the edges go (mip levels)
uniform vec4 haze : source_color = vec4(0.72, 0.8, 0.9, 0.22);

void fragment() {
	float off = clamp((abs(SCREEN_UV.y - centre) - focus) / (0.5 - focus), 0.0, 1.0);
	float lod = off * off * blur;
	vec2 px = SCREEN_PIXEL_SIZE * (1.0 + lod * 2.0);
	vec3 c = (textureLod(screen, SCREEN_UV, lod).rgb * 2.0
		+ textureLod(screen, SCREEN_UV + vec2(px.x, 0.0), lod).rgb + textureLod(screen, SCREEN_UV - vec2(px.x, 0.0), lod).rgb
		+ textureLod(screen, SCREEN_UV + vec2(0.0, px.y), lod).rgb + textureLod(screen, SCREEN_UV - vec2(0.0, px.y), lod).rgb) / 6.0;
	c = mix(c, haze.rgb, haze.a * smoothstep(0.3, 0.0, SCREEN_UV.y));
	COLOR = vec4(c, 1.0);
}
