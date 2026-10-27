// Noosa Visual.tint: original RGB * (1-strength) + tint RGB * strength.
shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength = 0.0;
varying vec4 vertex_color;
void vertex() {
	vertex_color = COLOR;
}
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	COLOR = vec4(mix(pixel.rgb, tint_color.rgb, strength), pixel.a) * vertex_color;
}
