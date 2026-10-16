shader_type canvas_item;
// Portraits as pixel art: every layer is sampled on a coarse grid with a reduced palette, so the layered
// portrait parts read as one pixel-art face at any size.

uniform float cells = 40.0;    // art pixels across the portrait
uniform float levels = 10.0;   // colour steps per channel

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 uv = (floor(UV * cells) + 0.5) / cells;
	vec4 c = texture(TEXTURE, uv) * tint;
	c.rgb = floor(c.rgb * levels + 0.5) / levels;
	c.a = step(0.5, c.a) * c.a;
	COLOR = c;
}
