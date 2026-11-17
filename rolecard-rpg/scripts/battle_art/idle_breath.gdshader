shader_type canvas_item;
uniform float phase = 0.0;
uniform float breath_strength = 0.004;
uniform float sway_strength = 0.002;
void fragment() {
    vec2 uv = UV;
    float influence = (1.0 - smoothstep(0.25, 0.96, uv.y));
    float sway = sin(phase) * sway_strength * influence;
    float breath = sin(phase) * breath_strength * influence;
    vec2 sample_uv = vec2(uv.x - sway, uv.y + breath);
    if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) { COLOR = vec4(0.0); }
    else { COLOR = texture(TEXTURE, sample_uv); }
}

