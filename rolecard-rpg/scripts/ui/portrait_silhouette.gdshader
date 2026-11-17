shader_type canvas_item;
// Preserve only the outer alpha contour. RGB details never reach the display.
void fragment() {
	float opacity = texture(TEXTURE, UV).a * COLOR.a;
	COLOR = vec4(vec3(0.10), opacity);
}
