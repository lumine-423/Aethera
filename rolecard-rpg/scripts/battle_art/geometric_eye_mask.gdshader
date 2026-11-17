shader_type canvas_item;
// Same slanted opening as the reviewed preview, in a 1280 x 450 local panel.
void fragment() {
	vec2 p = UV * vec2(1280.0, 450.0);
	float inside = step(200.0 - 0.145 * p.x, p.y) * step(p.y, 370.0 - 0.125 * p.x);
	COLOR = texture(TEXTURE, UV) * inside;
}
