shader_type canvas_item;
// Frosted glass behind dialogs and overlays: blurred, tinted copy of what is underneath.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.19, 0.21, 0.26, 0.35);
uniform float spread = 7.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * spread;
	vec3 acc = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			acc += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, 3.0).rgb;
		}
	}
	acc /= 9.0;
	COLOR = vec4(mix(acc, tint.rgb, clamp(tint.a * 1.6, 0.0, 0.85)), COLOR.a);
}
