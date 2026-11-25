shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

// Ground-conforming organic scorch / goo / footprint decal shader (ported from 40-fx.js DecalBatch).
varying vec2 v_uv;
varying vec4 v_col;
varying float v_seed;

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
	v_uv = UV;
	v_col = COLOR;
	v_seed = CUSTOM0.x;
}

void fragment() {
	float r = length(v_uv);
	float n = noise(v_uv * 3.0 + v_seed * 3.7) * 0.6 + noise(v_uv * 7.0 + v_seed) * 0.4;
	float a = smoothstep(1.0, 0.34, r + (n - 0.5) * 0.8);
	float th = atan(v_uv.y, v_uv.x);
	a *= 0.74 + 0.26 * noise(vec2(th * 3.0, v_seed));
	float alpha = a * v_col.a;
	if (alpha <= 0.01) {
		discard;
	}
	ALBEDO = v_col.rgb;
	ALPHA = alpha;
}
