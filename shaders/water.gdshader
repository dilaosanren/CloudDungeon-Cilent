shader_type canvas_item;
uniform sampler2D water_texture : filter_nearest, repeat_enable;
uniform vec2 map_pixels;
uniform vec2 water_pixels;

void fragment() {
	vec2 pixels = UV * map_pixels + vec2(0.0, -TIME * 5.0);
	COLOR = texture(water_texture, pixels / water_pixels);
}
