shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float barrel_strength : hint_range(0.0, 0.35) = 0.115;
uniform float ca_strength : hint_range(0.0, 0.012) = 0.0022;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.048;
uniform float vignette_strength : hint_range(0.0, 1.2) = 0.44;
uniform float sharpness : hint_range(0.0, 1.2) = 0.35;
uniform float nvg_amount : hint_range(0.0, 1.0) = 0.0;
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rain_lens_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shutter_flash : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 barrel_distort(vec2 uv, float k) {
    vec2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float scale = 1.0 / (1.0 + k * 0.85);
    vec2 distorted = centered * (1.0 + k * r2) * scale;
    return distorted * 0.5 + 0.5;
}

vec2 rain_drop_offset(vec2 uv, float t) {
    vec2 grid = vec2(18.0, 10.0);
    vec2 st = uv * grid;
    st.y -= t * 0.42;
    vec2 id = floor(st);
    vec2 f = fract(st) - 0.5;
    float rnd = hash12(id);
    if (rnd < 0.72) {
        return vec2(0.0);
    }
    vec2 drop_pos = vec2(sin(rnd * 41.0) * 0.25, fract(t * (0.25 + rnd * 0.35) + rnd) - 0.5);
    vec2 d = f - drop_pos;
    float dist = length(d * vec2(1.0, 0.75));
    float mask = smoothstep(0.16, 0.02, dist);
    return d * mask * 0.018;
}

void fragment() {
    vec2 uv = barrel_distort(SCREEN_UV, barrel_strength);

    // Subtle raindrops refracting on bodycam lens outdoors
    if (rain_lens_amount > 0.01) {
        uv += rain_drop_offset(uv, TIME) * rain_lens_amount;
    }

    // Out-of-bounds lens mask
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec2 from_center = uv - 0.5;
        float dist2 = dot(from_center, from_center);

        // Radial chromatic aberration (stronger toward edges like wide-angle bodycam glass)
        vec2 ca_off = from_center * dist2 * ca_strength * 4.2;
        float r = texture(screen_texture, clamp(uv + ca_off, 0.001, 0.999)).r;
        float g = texture(screen_texture, uv).g;
        float b = texture(screen_texture, clamp(uv - ca_off, 0.001, 0.999)).b;
        vec3 col = vec3(r, g, b);

        // Subtle bodycam digital micro-sharpening (Unrecord / Axon look)
        if (sharpness > 0.01) {
            vec2 px = SCREEN_PIXEL_SIZE * 1.15;
            vec3 blur = (
                texture(screen_texture, uv + vec2(px.x, 0.0)).rgb +
                texture(screen_texture, uv - vec2(px.x, 0.0)).rgb +
                texture(screen_texture, uv + vec2(0.0, px.y)).rgb +
                texture(screen_texture, uv - vec2(0.0, px.y)).rgb
            ) * 0.25;
            col = mix(col, col + (col - blur) * 1.35, sharpness);
        }

        // Realistic CMOS ISO noise: stronger in low-light shadows!
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        float shadow_boost = mix(1.85, 0.45, smoothstep(0.0, 0.6, luma));
        float n1 = hash12(uv * vec2(1280.0, 720.0) + fract(TIME * 37.3) * 100.0) - 0.5;
        float n2 = hash12(uv * vec2(640.0, 360.0) + fract(TIME * 19.7) * 100.0) - 0.5;
        float grain = (n1 * 0.65 + n2 * 0.35) * grain_strength * shadow_boost;
        col += vec3(grain);

        // Subtle cool-neutral bodycam color grading (slightly desaturated midtones, deep blacks)
        float lum_c = dot(col, vec3(0.2126, 0.7152, 0.0722));
        col = mix(vec3(lum_c), col, 0.88);
        col *= vec3(0.985, 0.995, 1.02);

        // Optional Night Vision / IR Bodycam mode
        if (nvg_amount > 0.01) {
            float ir_lum = pow(clamp(lum_c * 2.65 + 0.03, 0.0, 1.0), 0.72);
            float scanline = 0.92 + 0.08 * sin(SCREEN_UV.y * 900.0 + TIME * 4.0);
            vec3 nvg_col = vec3(ir_lum * 0.22, ir_lum * 1.05, ir_lum * 0.42) * scanline;
            nvg_col += vec3(0.0, n1 * 0.11, 0.0);
            col = mix(col, nvg_col, nvg_amount);
        }

        // Subtle lens vignette
        float vig = smoothstep(0.92, 0.18, length(from_center) * (1.05 + vignette_strength * 0.65));
        col *= mix(1.0 - vignette_strength * 0.55, 1.0, vig);

        // Injury blood/tunnel-vision pulse
        if (damage_amount > 0.01) {
            float pulse = 0.75 + 0.25 * sin(TIME * 7.5);
            float edge = smoothstep(0.28, 0.78, length(from_center));
            col = mix(col, vec3(0.55, 0.02, 0.02), edge * damage_amount * 0.72 * pulse);
        }

        // Subtle muzzle/lightning auto-exposure flash
        col += vec3(shutter_flash * 0.16);

        COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
    }
}
