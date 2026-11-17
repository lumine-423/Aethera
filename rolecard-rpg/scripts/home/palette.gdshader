shader_type canvas_item;
render_mode unshaded;
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool clean_alpha = true;
uniform bool decorative = false;
uniform bool glyph = false;
uniform bool preserve_ink = false;
uniform int key_mode = 0;
uniform vec4 keep_white_rect = vec4(0.0);
uniform vec4 erase_rect = vec4(0.0);
uniform vec4 erase_rect_b = vec4(0.0);
uniform float erase_sample_x = 0.0;
uniform float erase_shift_y = 0.0;
uniform bool erase_ink_only = false;
uniform int mask_count = 0;
uniform vec2 mask_points[24];
uniform float sheen_position = -1.0;
uniform float sheen_strength = 0.0;
uniform bool ambient_motion = false;
uniform bool backdrop = false;
uniform float motion_time = 0.0;
uniform vec4 art_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float edge_slant = 0.0;
uniform vec4 night_base_color : source_color = vec4(0.075,0.090,0.118,1.0);
uniform vec4 night_plane_color : source_color = vec4(0.17,0.27,0.40,1.0);
uniform vec4 night_accent_color : source_color = vec4(1.0,0.86,0.16,1.0);
uniform vec4 night_decoration_color : source_color = vec4(0.18,0.32,0.50,1.0);
uniform vec4 day_accent_color : source_color = vec4(0.81,0.10,0.20,1.0);
uniform vec4 glyph_color : source_color = vec4(1.0);
varying vec4 modulation;

void vertex() { modulation = COLOR; }

void fragment() {
	vec2 sample_uv=UV;
	// Separate affine transforms retain straight geometric edges. Overscan covers the viewport.
	if (backdrop && ambient_motion) {
		float t=motion_time;
		float zoom=decorative?1.035:1.065;
		vec2 drift=decorative?vec2(sin(t*0.22+0.8)*0.011,cos(t*0.17+0.3)*0.009):vec2(sin(t*0.16)*0.023,cos(t*0.12)*0.019);
		sample_uv=(UV-0.5)/zoom+0.5+drift;
	}
	vec4 tex = texture(TEXTURE, sample_uv);
	if ((UV.x>erase_rect.x && UV.y>erase_rect.y && UV.x<erase_rect.x+erase_rect.z && UV.y<erase_rect.y+erase_rect.w) ||
		(UV.x>erase_rect_b.x && UV.y>erase_rect_b.y && UV.x<erase_rect_b.x+erase_rect_b.z && UV.y<erase_rect_b.y+erase_rect_b.w)) {
		vec3 replacement=texture(TEXTURE,vec2(erase_sample_x>0.0?erase_sample_x:UV.x,UV.y+erase_shift_y)).rgb;
		float amount=erase_ink_only?1.0-smoothstep(0.45,0.72,dot(tex.rgb,vec3(0.299,0.587,0.114))):1.0;
		tex.rgb=mix(tex.rgb,replacement,amount);
	}
	vec2 local_uv = (UV-art_region.xy)/art_region.zw;
	if (mask_count>2) {
		bool inside=false; int j=mask_count-1;
		for (int i=0;i<24;i++) {
			if (i>=mask_count) break;
			vec2 a=mask_points[i]; vec2 b=mask_points[j];
			if ((a.y>local_uv.y)!=(b.y>local_uv.y) && local_uv.x<(b.x-a.x)*(local_uv.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
			j=i;
		}
		if (!inside) discard;
	}
	if (local_uv.x < edge_slant*(1.0-local_uv.y) || local_uv.x > 1.0-edge_slant*local_uv.y) discard;
	float alpha = clean_alpha ? smoothstep(0.08, 0.86, tex.a) : tex.a;
	float light = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float red = smoothstep(0.08, 0.4, tex.r - max(tex.g, tex.b));
	float plane = pow(clamp((1.0 - light) * 3.2, 0.0, 1.0), 0.9);
	vec3 dark = mix(night_base_color.rgb, night_plane_color.rgb, plane);
	vec3 yellow = night_accent_color.rgb * (0.72 + 0.28 * tex.r);
	if (decorative) yellow = mix(yellow, night_decoration_color.rgb, smoothstep(0.48, 0.76, light));
	if (decorative && UV.x > 0.78 && UV.y > 0.30) yellow = night_decoration_color.rgb;
	dark = mix(dark, yellow, red);
	if (preserve_ink) dark=mix(dark,vec3(0.93,0.95,0.98),(1.0-smoothstep(0.24,0.42,light))*(1.0-red));
	if (UV.x>keep_white_rect.x && UV.y>keep_white_rect.y && UV.x<keep_white_rect.x+keep_white_rect.z && UV.y<keep_white_rect.y+keep_white_rect.w && UV.x+UV.y*0.365<0.791)
		dark=mix(dark,tex.rgb,smoothstep(0.78,0.92,light));
	vec3 rgb = mix(tex.rgb, dark, night_mix);
	if (backdrop && ambient_motion && !decorative) {
		float travel=fract(motion_time/24.0)*2.0-0.5;
		float sweep=exp(-pow((UV.x+UV.y*0.28-travel)*8.0,2.0));
		rgb=mix(rgb,vec3(0.97,0.985,1.0),sweep*mix(0.045,0.025,night_mix));
	}
	vec3 accent = mix(day_accent_color.rgb, night_accent_color.rgb, night_mix);
	rgb = mix(rgb, accent, hover_amount * 0.045);
	float sheen=max(0.0,1.0-abs(local_uv.x-sheen_position)/0.20)*sheen_strength;
	rgb=mix(rgb,vec3(1.0),sheen);
	if (key_mode==1) alpha*=1.0-smoothstep(0.45,0.72,light);
	if (key_mode==2) alpha*=smoothstep(0.80,0.96,light);
	if (glyph) rgb = glyph_color.rgb;
	COLOR = vec4(rgb, alpha) * modulation;
}
