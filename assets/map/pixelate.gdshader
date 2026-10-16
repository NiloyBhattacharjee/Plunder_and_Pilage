shader_type canvas_item;
// Turns everything drawn beneath it (the chart, the sea, ships) into chunky pixels with a limited palette,
// for the pixel-art look. Port names sit on a layer above it so they stay readable.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float pixel = 3.0;     // screen pixels per art pixel
uniform float levels = 32.0;   // colour steps per channel

void fragment() {
	vec2 cell = (floor(FRAGCOORD.xy / pixel) + 0.5) * pixel;
	vec3 c = texture(screen, cell * SCREEN_PIXEL_SIZE).rgb;
	COLOR = vec4(floor(c * levels + 0.5) / levels, 1.0);
}
