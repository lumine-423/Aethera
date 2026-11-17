shader_type canvas_item;
uniform int phase = 0; // 0 expanding white, 1 fully white, 2 opening a transparent hole
uniform float progress : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 delta = UV * vec2(1280.0, 720.0) - vec2(640.0, 360.0);
	float d = length(delta);
	float r = progress * 760.0;
	float outside = smoothstep(r - 12.0, r + 12.0, d);
	float a = phase == 0 ? 1.0 - outside : (phase == 1 ? 1.0 : outside);
	COLOR = vec4(1.0, 1.0, 1.0, a);
}
