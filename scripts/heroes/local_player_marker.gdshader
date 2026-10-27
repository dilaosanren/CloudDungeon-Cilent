// Hardlight the original Icons.ARROW silhouette so it remains legible on terrain.
shader_type canvas_item;

void fragment() {
	COLOR = vec4(vec3(1.0, 1.0, 0.2666667), texture(TEXTURE, UV).a * COLOR.a);
}
