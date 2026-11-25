shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 4-mode biome fluid/surface shader (ported & enhanced from 10-gfx.js):
// u_wat.x: 0 = Cold Mountain Stream, 1 = Frozen Cracked Ice, 2 = Molten Magma/Lava, 3 = Murky Swamp Bog
// u_wat.y = flow speed, u_wat.z = ripple bump strength, u_wat.w = mask relief height
// CUSTOM0.z carries per-vertex flow factor (0 in still ponds, 1 in flowing stream)

uniform float u_time = 0.0;
uniform vec4 u_wat = vec4(0.0, 1.0, 1.0, 0.0);
uniform vec3 u_wat_a = vec3(0.014, 0.024, 0.036);
uniform vec3 u_wat_b = vec3(0.32, 0.42, 0.52);
uniform vec3 u_sky = vec3(0.03, 0.055, 0.11);

varying vec4 v_surf;
varying vec3 v_wpos;

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

float cw_ripple(vec2 p, float t, float flow) {
	float a = cw_n(vec2(p.x * 2.6, p.y * 1.3 - t * flow * 1.0));
	float b = cw_n(vec2(p.x * 5.2 + 3.7, p.y * 2.6 - t * (0.15 + flow * 1.45)));
	float c = cw_n(vec2(p.x * 13.0 - t * 0.14, p.y * 9.0 - t * (0.22 + flow * 2.15)));
	return a + b * 0.85 + c * 0.22;
}

void vertex() {
	v_surf = CUSTOM0;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Subtle vertical surface heave for liquid modes
	if (u_wat.x < 0.5 || u_wat.x > 2.5) {
		float w = sin(u_time * 2.1 + v_wpos.x * 1.7 + v_wpos.z * 1.4) * 0.016 * min(CUSTOM0.z + 0.25, 1.0);
		VERTEX.y += w;
	}
}

void fragment() {
	float flow = v_surf.z;
	float t_flow = u_time * u_wat.y;
	float wn1 = cw_n(UV * vec2(1.6, 0.8) + 3.0);
	float wn2 = cw_n(UV * vec2(5.0, 2.6) + 11.0);

	vec3 col = u_wat_a;
	vec3 emis = vec3(0.0);
	float rough = 0.08;
	float metal = 0.08;
	float w_mask = 0.0;
	float w_heat = 0.0;

	if (u_wat.x > 0.5 && u_wat.x < 1.5) {
		// Frozen Frostfall Ice with fracture veins and frost drift
		float frost = smoothstep(0.38, 0.74, wn1 * 0.65 + wn2 * 0.35);
		float ck1 = smoothstep(0.036, 0.0, abs(cw_n(UV * vec2(2.3, 1.2) + 40.0) - 0.5));
		float ck2 = smoothstep(0.032, 0.0, abs(cw_n(UV * vec2(1.2, 2.7) + 71.0) - 0.48));
		float ck = clamp(ck1 + ck2, 0.0, 1.0);
		w_mask = clamp(frost * 0.82 + ck * 0.75, 0.0, 1.0);
		col = mix(u_wat_a * (0.72 + 0.58 * wn2), u_wat_b, w_mask);
		rough = mix(0.07, 0.58, w_mask);
		metal = mix(0.18, 0.02, w_mask);
		emis = vec3(0.18, 0.34, 0.52) * ck * 0.45;
	} else if (u_wat.x > 1.5 && u_wat.x < 2.5) {
		// Emberscar Molten Magma Stream
		float t = t_flow * (0.16 + 0.36 * min(flow, 1.0));
		float c1 = cw_n(vec2(UV.x * 2.1, UV.y * 1.1 - t));
		float c2 = cw_n(vec2(UV.x * 4.6 + 7.0, UV.y * 2.4 - t * 1.7));
		float c3 = cw_n(vec2(UV.x * 9.0 - 3.0, UV.y * 5.0 - t * 2.3));
		float ra = 1.0 - abs(2.0 * c1 - 1.0);
		float rb = 1.0 - abs(2.0 * c2 - 1.0);
		float crack = max(pow(ra, 3.2), pow(rb, 4.4) * 0.85);
		float pool = smoothstep(0.55, 0.74, c1 * 0.55 + c3 * 0.45);
		w_heat = clamp(crack * 0.9 + pool, 0.0, 1.0);
		w_mask = 1.0 - smoothstep(0.36, 0.68, w_heat);
		col = mix(u_wat_a, u_wat_b * (0.62 + 0.78 * c3), w_mask);
		rough = mix(0.45, 0.94, w_mask);
		metal = 0.0;
		float pulse = 0.92 + 0.14 * sin(u_time * 2.8 + c1 * 6.0);
		emis = mix(vec3(0.85, 0.09, 0.01), vec3(2.35, 0.68, 0.08), w_heat * w_heat) * (1.0 - w_mask) * pulse
			+ vec3(0.14, 0.018, 0.002) * w_mask * (0.3 + wn2);
	} else if (u_wat.x > 2.5) {
		// Mirefen Swamp Bog with floating algae/duckweed patches
		w_mask = smoothstep(0.54, 0.68, wn1 * 0.55 + wn2 * 0.45 + 0.12 * (1.0 - min(flow, 1.0))) * step(0.01, flow + 0.02);
		col = mix(u_wat_a, u_wat_b * (0.76 + 0.48 * wn2), w_mask);
		rough = mix(0.14, 0.88, w_mask);
		metal = 0.04;
	} else {
		// Ashen Pass Cold Flowing Water with subtle aerated stream foam
		float foam_n = cw_n(vec2(UV.x * 6.5, UV.y * 3.2 - t_flow * 1.4));
		float edge_foam = smoothstep(0.74, 0.92, foam_n) * min(flow, 1.0) * 0.35;
		col = mix(u_wat_a, u_wat_b * 1.15, edge_foam);
		rough = mix(0.06, 0.42, edge_foam);
		metal = 0.12;
	}

	// Finite-difference ripple normal
	float eps = 0.045;
	float h0 = cw_ripple(UV, t_flow, flow) + w_mask * u_wat.w;
	float hx = cw_ripple(UV + vec2(eps, 0.0), t_flow, flow) + w_mask * u_wat.w;
	float hz = cw_ripple(UV + vec2(0.0, eps), t_flow, flow) + w_mask * u_wat.w;
	float sc = (0.12 + 0.38 * min(flow, 1.0)) * u_wat.z;
	vec3 wn = normalize(vec3((h0 - hx) * sc / eps, 1.0, (h0 - hz) * sc / eps));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Moonlight sky Fresnel shimmer
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	vec3 sky_refl = u_sky * (0.55 + 4.8 * fres) * (1.45 - 0.5 * min(flow, 1.0)) * (1.0 - w_mask * 0.82);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.72;
	EMISSION = emis + sky_refl;
}
