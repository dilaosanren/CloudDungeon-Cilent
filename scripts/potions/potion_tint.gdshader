shader_type canvas_item;
uniform vec3 tint_color = vec3(0.83, 1.17, 1.33);
uniform float strength = 0.0;
// Fragment COLOR already contains the texture. Preserve the vertex modulation
// separately so IceBlock's additive tint also lightens dark outlines.
varying vec4 sprite_modulate;
void vertex() {
	sprite_modulate = COLOR;
}
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(source.rgb * (1.0 - strength) + tint_color * strength, source.a) * sprite_modulate;
}
