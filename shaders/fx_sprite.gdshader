shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_add;

// Procedural multi-type additive FX billboard shader (ported from 40-fx.js SPR_FRAG_ADD).
// INSTANCE_CUSTOM: r = type (0..7), g = seed, b = age (0..1), a = ground_flag (0=billboard, 1=flat ground)
// COLOR: rgba = HDR color * alpha

uniform float u_time = 0.0;

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
	v_uv = VERTEX.xy; // -1..1 quad
	v_col = COLOR;
	v_misc = INSTANCE_CUSTOM;

	// Extract world position & scale/rotation packed in MODEL_MATRIX
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 sx_v = MODEL_MATRIX[0].xyz;
	vec3 sy_v = MODEL_MATRIX[1].xyz;
	float w = length(sx_v);
	float h = length(sy_v);
	// Rotation packed into MODEL_MATRIX[2].x, anchor in MODEL_MATRIX[2].y
	float rot = MODEL_MATRIX[2].x;
	float anchor = MODEL_MATRIX[2].y;

	vec2 q = VERTEX.xy;
	q.y += anchor;
	float c = cos(rot);
	float s = sin(rot);
	q = vec2(q.x * c - q.y * s, q.x * s + q.y * c) * vec2(w, h) * 0.5;

	if (INSTANCE_CUSTOM.a > 0.5) {
		vec3 wp = center + vec3(q.x, 0.0, q.y);
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	} else {
		vec4 mv = VIEW_MATRIX * vec4(center, 1.0);
		mv.xy += q;
		POSITION = PROJECTION_MATRIX * mv;
	}
}

void fragment() {
	int type = int(v_misc.x + 0.5);
	float seed = v_misc.y;
	float age = v_misc.z;
	vec2 p = v_uv;
	float r = length(p);
	vec3 col = v_col.rgb;
	float a = 0.0;

	if (type == 0) {
		// Soft glowing orb / ember / eye glint
		a = smoothstep(1.0, 0.0, r);
		a *= a;
	} else if (type == 1) {
		// Animated roaring volumetric flame tongue
		float y = p.y * 0.5 + 0.5;
		float t = u_time * 1.65 + seed * 17.0;
		float n1 = noise(vec2(p.x * 2.6 + seed * 7.0, y * 3.2 - t * 2.4));
		float n2 = noise(vec2(p.x * 5.6 - seed * 3.0, y * 6.2 - t * 4.1));
		float x = p.x + (n1 - 0.5) * 0.55 * y;
		float w = mix(0.68, 0.02, pow(clamp(y, 0.0, 1.0), 0.85));
		float body = 1.0 - smoothstep(w * 0.34, w, abs(x));
		float d = body * (1.08 - y) + (n1 * 0.62 + n2 * 0.38 - 0.5) * (0.28 + 0.6 * y) - smoothstep(0.0, 0.07, 0.07 - y) * 0.6;
		a = smoothstep(0.10, 0.18, d);
		col *= mix(vec3(1.0, 0.22, 0.03), vec3(1.0, 0.58, 0.10), smoothstep(0.24, 0.32, d));
		col = mix(col, v_col.rgb * vec3(1.0, 0.88, 0.44), smoothstep(0.45, 0.54, d));
		col = mix(col, v_col.rgb * vec3(1.25, 1.12, 0.86), smoothstep(0.68, 0.78, d));
	} else if (type == 2) {
		// Warm radial aura / glow halo
		a = pow(max(0.0, 1.0 - r), 2.35);
	} else if (type == 3) {
		// Expanding turbulent explosion fireball
		float n = noise(p * 2.5 + seed * 13.0 + vec2(0.0, -age * 1.7)) * 0.6 + noise(p * 5.4 - seed * 7.0) * 0.4;
		float d = (1.0 - r) + (n - 0.5) * 0.95 - age * 0.92;
		a = smoothstep(0.02, 0.12, d);
		vec3 hot = mix(vec3(0.95, 0.20, 0.03), vec3(1.05, 0.64, 0.16), smoothstep(0.16, 0.26, d));
		hot = mix(hot, vec3(1.25, 1.05, 0.78), smoothstep(0.42, 0.54, d));
		col *= hot * (1.0 - age * 0.55);
	} else if (type == 4) {
		// Ground shockwave / aura pulse ring
		float R0 = 0.25 + 0.75 * sqrt(clamp(age, 0.0, 1.0));
		a = smoothstep(0.14, 0.0, abs(r - R0)) * (1.0 - age) * (1.0 - age);
	} else if (type == 5) {
		// Radial star burst / muzzle flash / coin pop
		float th = atan(p.y, p.x);
		a = pow(max(0.0, 1.0 - r), 1.6) * (0.25 + 0.75 * pow(abs(cos(th * 2.5 + seed)), 6.0)) * (1.0 - age);
		a += pow(max(0.0, 1.0 - r * 2.2), 2.0) * (1.0 - age * 0.5);
	} else if (type == 6) {
		// Velocity-stretched spark streak
		a = smoothstep(1.0, 0.0, abs(p.y)) * smoothstep(1.0, 0.3, abs(p.x));
	} else if (type == 7) {
		// Sweeping melee blade slash arc
		float th = atan(p.y, p.x);
		float front = mix(-1.5, 1.5, smoothstep(0.0, 0.55, age));
		float band = smoothstep(0.50, 0.74, r) * smoothstep(1.0, 0.90, r);
		float trail = smoothstep(front - 1.5, front, th) * step(th, front) * step(-1.6, th);
		a = band * trail * (1.0 - smoothstep(0.45, 1.0, age));
	}

	if (a <= 0.002) {
		discard;
	}
	ALBEDO = col * a * v_col.a;
	ALPHA = 1.0;
}
