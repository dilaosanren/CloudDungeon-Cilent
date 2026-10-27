// ItemSprite.update: rm=gm=bm=1-value, additive RGB=glow*value.
shader_type canvas_item;
uniform vec3 glow_color = vec3(1.0);
uniform float glow_strength = 0.0;
varying vec4 item_modulate;

void vertex() {
	// Fragment COLOR already includes TEXTURE. Preserve only the vertex tint,
	// otherwise using COLOR below would multiply the item image a second time.
	item_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(source.rgb * (1.0 - glow_strength) + glow_color * glow_strength, source.a) * item_modulate;
}
