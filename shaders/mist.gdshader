shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;

// World-space drifting low-lying valley mist lit dynamically by Beacon & Tower fires!
// Ported from 20-post.js M.atmo for Godot 4.4 Forward Plus.
uniform sampler2D u_depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 u_mist_amb = vec3(0.05, 0.08, 0.15);
uniform vec4 u_mist = vec4(-0.3, 0.48, 0.82, 0.14); // y0, height_scale, density, brightness
uniform vec2 u_wind = vec2(0.0, 0.0);

uniform vec3 u_light_pos[12];
uniform vec3 u_light_col[12];

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(u_depth_tex, SCREEN_UV).r;
	// In Godot 4 Forward Plus, reversed-Z: sky/background is near 0.0
	if (depth <= 0.0001) {
		discard;
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 P = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;

	float n = vn(P.xz * 0.15 + u_wind) * 0.65 + vn(P.xz * 0.44 - u_wind * 1.65) * 0.35;
	float tau = min(u_mist.z * exp(-(max(P.y, -1.2) - u_mist.x) / max(u_mist.y, 0.05)), 1.35)
		* smoothstep(0.32, 0.86, n)
		* smoothstep(-3.0, -1.1, P.y);
	float f = clamp(1.0 - exp(-tau), 0.0, 0.82);

	vec3 L = u_mist_amb;
	vec3 Pm = P + vec3(0.0, 0.38, 0.0);
	for (int i = 0; i < 12; i++) {
		vec3 lc = u_light_col[i];
		if (lc.r + lc.g + lc.b > 0.001) {
			vec3 dv = u_light_pos[i] - Pm;
			L += lc / (dot(dv, dv) + 2.2);
		}
	}

	ALBEDO = L * u_mist.w;
	ALPHA = f;
}
