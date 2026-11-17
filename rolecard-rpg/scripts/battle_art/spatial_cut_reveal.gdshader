shader_type canvas_item;
// Reveal the independently generated cut along its diagonal. Not a generated frame.
uniform float spread : hint_range(0.0,1.0) = 0.0;
uniform float opacity : hint_range(0.0,1.0) = 1.0;
void fragment() {
    vec4 sample_color = texture(TEXTURE, UV);
    float diagonal_distance = abs((UV.x - 0.5) - (UV.y - 0.5)) * 0.5;
    float edge = 0.018;
    float reveal = 1.0 - smoothstep(max(0.0, spread * 0.5 - edge), spread * 0.5 + edge, diagonal_distance);
    COLOR = vec4(sample_color.rgb, sample_color.a * reveal * opacity);
}
