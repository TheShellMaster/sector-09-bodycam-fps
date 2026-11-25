shader_type canvas_item;

// Fast single-pass Bodycam post-processing shader optimized for Linux OpenGL 3.3 & Vulkan.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform float barrel_strength : hint_range(0.0, 0.25) = 0.08;
uniform float grain_strength : hint_range(0.0, 0.15) = 0.032;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.36;
uniform float nvg_amount : hint_range(0.0, 1.0) = 0.0;
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shutter_flash : hint_range(0.0, 1.0) = 0.0;

float fast_hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 centered = SCREEN_UV * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float scale = 1.0 / (1.0 + barrel_strength * 0.8);
    vec2 uv = (centered * (1.0 + barrel_strength * r2) * scale) * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        // Single fast texture fetch (huge FPS win on integrated GPUs)
        vec3 col = texture(screen_texture, uv).rgb;

        // Subtle cool bodycam color grade
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(vec3(luma), col, 0.90) * vec3(0.985, 0.995, 1.015);

        // Lightweight CMOS grain (stronger in shadows)
        if (grain_strength > 0.001) {
            float n = fast_hash(floor(FRAGCOORD.xy * 0.5) + fract(TIME * 29.0) * 60.0) - 0.5;
            col += vec3(n * grain_strength * mix(1.45, 0.45, clamp(luma * 2.0, 0.0, 1.0)));
        }

        // Optional Night Vision / IR mode
        if (nvg_amount > 0.01) {
            float ir = pow(clamp(luma * 2.4 + 0.04, 0.0, 1.0), 0.78);
            vec3 nvg = vec3(ir * 0.2, ir * 1.0, ir * 0.38);
            col = mix(col, nvg, nvg_amount);
        }

        // Lens vignette
        float vig = smoothstep(1.35, 0.25, length(centered) * (0.85 + vignette_strength * 0.45));
        col *= mix(1.0 - vignette_strength * 0.5, 1.0, vig);

        // Injury pulse
        if (damage_amount > 0.01) {
            float edge = smoothstep(0.35, 1.1, length(centered));
            col = mix(col, vec3(0.55, 0.03, 0.03), edge * damage_amount * 0.65);
        }

        col += vec3(shutter_flash * 0.14);
        COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
    }
}
