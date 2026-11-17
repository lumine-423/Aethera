shader_type canvas_item;
uniform int phase = 0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
    vec2 p = UV * vec2(1280.0, 720.0) - vec2(640.0, 360.0);
    float d = length(p);
    float radius = progress * 800.0;
    float boundary = smoothstep(radius - 75.0, radius + 75.0, d);
    float core = phase == 0 ? 1.0 - boundary : (phase == 1 ? 1.0 : boundary);
    if (phase == 1) {
        COLOR = vec4(1.0);
    } else {
        // Small luminous particles travel outward from the character, with a soft halo.
        float travel = phase == 0 ? progress : 0.75 + progress * 0.45;
        float particles = 0.0;
        float halo = 0.0;
        for (int i = 0; i < 150; i++) {
            float fi = float(i);
            float angle = hash21(vec2(fi, 3.0)) * 6.2831853;
            float speed = 850.0 + 1150.0 * hash21(vec2(fi, 7.0));
            vec2 loc = vec2(cos(angle), sin(angle)) * speed * travel;
            float size = 2.0 + 3.5 * hash21(vec2(fi, 13.0));
            float dist = length(p - loc);
            float twinkle = 0.55 + 0.45 * hash21(vec2(fi, 19.0));
            particles = max(particles, (1.0 - smoothstep(size * 0.3, size * 1.35, dist)) * twinkle);
            halo = max(halo, exp(-dist / (size * 3.3)) * 0.35 * twinkle);
        }
        float visibility = phase == 0 ? smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.82, 1.0, progress)) : (1.0 - smoothstep(0.15, 1.0, progress));
        float light = max(particles, halo) * visibility;
        float alpha = max(core, light);
        vec3 color = mix(vec3(1.0, 0.80, 0.46), vec3(1.0), max(core, particles));
        COLOR = vec4(color, alpha);
    }
}
