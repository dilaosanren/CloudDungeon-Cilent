// CharSprite.flash: additive white RGB, preserving the sprite's alpha.
shader_type canvas_item;

void fragment() {
	COLOR = vec4(vec3(1.0), texture(TEXTURE, UV).a * COLOR.a);
}
