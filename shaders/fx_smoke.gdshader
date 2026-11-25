shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

// Lit volumetric smoke & dust cloud billboard shader (ported & smoothed from 40-fx.js SPR_FRAG_ALPHA).
uniform float u_time = 0.0;
uniform vec3 u_amb = vec3(0.14, 0.17, 0.24);
uniform vec3 u_light_pos[12];
uniform vec3 u_light_col[12];

varying vec2 v_uv;
varying vec4 v_col;
varying vec4 v_misc;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	v_uv = VERTEX.xy;
	v_misc = INSTANCE_CUSTOM;

	vec3 center = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	float rot = MODEL_MATRIX[2].x;

	vec2 q = VERTEX.xy;
	float c = cos(rot);
	float s = sin(rot);
	q = vec2(q.x * c - q.y * s, q.x * s + q.y * c) * vec2(w, h) * 0.5;

	vec3 L = u_amb;
	for (int i = 0; i < 12; i++) {
		vec3 lc = u_light_col[i];
		if (lc.r + lc.g + lc.b > 0.001) {
			vec3 d = u_light_pos[i] - center;
			L += lc / (dot(d, d) + 3.0);
		}
	}
	v_col = vec4(COLOR.rgb * L, COLOR.a);

	vec4 mv = VIEW_MATRIX * vec4(center, 1.0);
	mv.xy += q;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	float seed = v_misc.y;
	float age = v_misc.z;
	vec2 p = v_uv;
	float r = length(p);
	float n = noise(p * 1.8 + seed * 9.0 + vec2(0.0, -age * 0.65)) * 0.65 + noise(p * 4.0 + seed * 5.0) * 0.35;
	float a = smoothstep(1.0, 0.22, r + (n - 0.5) * 0.88);
	if (a <= 0.01) {
		discard;
	}
	ALBEDO = v_col.rgb * (0.72 + 0.48 * n);
	ALPHA = a * v_col.a;
}
