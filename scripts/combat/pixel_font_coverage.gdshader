// FreeTypeFontGenerator.renderCount: 3 below size 20, 2 otherwise.
// Boost raster coverage before applying vertex alpha so lifetime fade stays linear.
shader_type canvas_item;
render_mode unshaded;
uniform float render_count = 3.0;
varying vec4 draw_color;
void vertex() {
	draw_color = COLOR;
}
void fragment() {
	vec4 glyph = texture(TEXTURE, UV);
	float coverage = 1.0 - pow(1.0 - glyph.a, render_count);
	COLOR = vec4(glyph.rgb * draw_color.rgb, coverage * draw_color.a);
}
