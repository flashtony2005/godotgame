shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Waterfall / Lavafall / Frozen Cascade ribbon shader (ported & enhanced from 31-terrain.js).
uniform float u_time = 0.0;
uniform vec3 u_col_a = vec3(0.03, 0.055, 0.10);
uniform vec3 u_col_b = vec3(0.32, 0.44, 0.62);
uniform float u_speed = 1.7;
uniform float u_emissive = 0.35;

float cw_h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float cw_n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(cw_h(i), cw_h(i + vec2(1.0, 0.0)), f.x),
		mix(cw_h(i + vec2(0.0, 1.0)), cw_h(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	float t = u_time * u_speed;
	float s1 = cw_n(vec2(UV.x * 7.5, UV.y * 2.4 - t * 2.3));
	float s2 = cw_n(vec2(UV.x * 16.0 + 3.1, UV.y * 4.5 - t * 3.8));
	float streak = s1 * 0.6 + s2 * 0.4;
	float foam = smoothstep(0.45, 0.85, streak) + smoothstep(0.18, 0.0, UV.y) * 0.45;
	float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x);
	float tail = smoothstep(1.0, 0.72, UV.y);

	vec3 col = mix(u_col_a, u_col_b, clamp(foam, 0.0, 1.0));
	ALBEDO = col * (1.0 + u_emissive * 2.4);
	ALPHA = clamp((0.68 + 0.32 * foam) * edge * tail, 0.0, 0.96);
}
