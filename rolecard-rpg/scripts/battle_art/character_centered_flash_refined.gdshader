shader_type canvas_item;
// 0: radial emergence, 1: full white hold, 2: clear outward from center.
uniform int phase = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * vec2(1280.0, 720.0) - vec2(640.0, 360.0);
	float d = length(p);
	float diamond = abs(p.x) * 0.85 + abs(p.y) * 1.15;
	float shape_distance = mix(diamond, d, smoothstep(0.35, 0.8, progress));
	float radius = progress * 760.0;
	float outside = smoothstep(radius - 24.0, radius + 24.0, shape_distance);
	float core = phase == 0 ? 1.0 - outside : (phase == 1 ? 1.0 : outside);
	float edge = (1.0 - smoothstep(2.0, 7.0, abs(shape_distance - radius))) * (1.0 - progress * 0.45);
	float glow = exp(-abs(shape_distance - radius) / 28.0) * 0.32 * (1.0 - progress * 0.55);
	float span = 120.0 + 1100.0 * progress;
	float horiz = exp(-abs(p.y) / 3.0) * (1.0 - smoothstep(span * 0.55, span, abs(p.x)));
	float vert = exp(-abs(p.x) / 3.0) * (1.0 - smoothstep(span * 0.45, span * 0.85, abs(p.y)));
	float diag1 = exp(-abs(p.y - p.x * 0.55) / 2.5) * (1.0 - smoothstep(span * 0.40, span * 0.75, d));
	float diag2 = exp(-abs(p.y + p.x * 0.55) / 2.5) * (1.0 - smoothstep(span * 0.40, span * 0.75, d));
	float rays = max(max(horiz, vert), max(diag1, diag2) * 0.55) * (1.0 - progress);
	if (phase == 1) {
		COLOR = vec4(1.0);
	} else {
		float detail = clamp(max(edge * 0.72, max(glow, rays * 0.7)), 0.0, 1.0);
		float alpha = max(core, detail);
		vec3 color = mix(vec3(1.0, 0.81, 0.51), vec3(1.0), max(core, rays));
		COLOR = vec4(color, alpha);
	}
}
