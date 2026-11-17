shader_type canvas_item;
// Day/night switch: the previous frame stays outside a circle that grows from the click point,
// with a bright accent ring on the edge. Works on GL Compatibility (desktop, Android, Web).
uniform vec2 extent = vec2(1920.0, 1080.0);
uniform vec2 center = vec2(0.0);
uniform float radius = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);

void fragment() {
	vec2 p = UV * extent;
	float d = distance(p, center);
	vec4 old = texture(TEXTURE, UV);
	float outside = smoothstep(radius - 1.5, radius + 1.5, d);
	float ring = (1.0 - smoothstep(0.0, 12.0, abs(d - radius))) * step(1.0, radius);
	float halo = (1.0 - smoothstep(0.0, 90.0, radius - d)) * (1.0 - outside) * 0.22;
	vec3 rgb = mix(old.rgb, ring_color.rgb, ring);
	rgb = mix(rgb, ring_color.rgb, (1.0 - outside));
	COLOR = vec4(rgb, max(outside, max(ring * 0.95, halo)));
}
