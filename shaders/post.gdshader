shader_type canvas_item;
render_mode unshaded;

// Refined full-screen diorama post-processing:
// Tilt-shift edge softness + subtle CA + biome color grading + fade + dynamic film grain + vignette + 96-level Bayer dithering.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float blur_strength = 0.72;
uniform float grain_amt = 0.032;
uniform float vig_amt = 0.44;
uniform float levels = 96.0;
uniform float ca_amt = 0.28;
uniform float saturation = 1.08;
uniform float contrast = 1.05;
uniform float fade = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.98, 0.96);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = y * 4 + x;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return m[idx] / 16.0;
}

vec3 blur_v(vec2 uv, float r) {
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = -4; i <= 4; i++) {
		float w = 1.0 - abs(float(i)) * 0.17;
		acc += texture(screen_tex, uv + vec2(0.0, float(i) * r)).rgb * w;
		wsum += w;
	}
	return acc / wsum;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = smoothstep(0.22, 0.94, abs(uv.y - 0.5) * 2.0);
	float r = blur_strength * 0.0026 * band;

	vec3 sharp = texture(screen_tex, uv).rgb;
	float ca = ca_amt * 0.00075 * (0.35 + band);
	sharp.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	sharp.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;

	vec3 col = sharp;
	if (r > 0.0001) {
		vec3 blurred = blur_v(uv, r);
		blurred.r = blur_v(uv + vec2(ca, 0.0), r).r;
		blurred.b = blur_v(uv - vec2(ca, 0.0), r).b;
		col = mix(sharp, blurred, clamp(band * 1.15, 0.0, 1.0));
	}

	// Biome color grading
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= tint;

	// Subtle film grain (stronger in shadows)
	float g = hash21(FRAGCOORD.xy + vec2(TIME * 37.0, TIME * 17.0));
	col += (g - 0.5) * grain_amt * (0.30 + 0.70 * (1.0 - lum));

	// Cinematic vignette
	float v = distance(uv, vec2(0.5, 0.5));
	col *= 1.0 - vig_amt * pow(clamp(v * 1.30, 0.0, 1.0), 2.15);

	// Smooth startup/transition fade
	col *= clamp(fade, 0.0, 1.0);

	// Subtle ordered dithering to eliminate dark sky/fog banding
	col = floor(col * levels + bayer4(FRAGCOORD.xy)) / levels;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
