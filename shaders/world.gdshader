shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// High-detail procedural material shader for Cinderwatch terrain, architecture, props, towers & rigs.
// CUSTOM0 carries: x = material layer (0..10), y = base roughness, z = wind sway factor, w = emissive intensity.

uniform sampler2DArray u_tex_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray u_tex_normal : filter_linear_mipmap, repeat_enable;

uniform float u_wind = 1.0;
uniform float u_normal_scale = 0.85;
uniform float u_is_instanced = 0.0;
uniform float u_time = 0.0;

// Biome top-cover overlay (snow / moss / ash / sand)
uniform vec4 u_cover = vec4(0.0, 0.55, 0.3, 0.5);       // amount, normal_y threshold, noise span, cobble factor
uniform vec3 u_cover_col = vec3(1.0, 1.0, 1.0);         // linear cover albedo
uniform vec4 u_cover_p = vec4(0.7, 0.6, 0.0, 0.0);      // rough, normal_flatten, bump_amp, ripple_amp
uniform float u_cover_sparkle = 0.0;                    // snow/ice micro-glint

uniform vec3 u_rim_col = vec3(0.28, 0.38, 0.62);
uniform float u_rim_amt = 0.14;

varying vec4 v_surf;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec4 v_inst_custom;

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

void vertex() {
	v_surf = CUSTOM0;
	v_inst_custom = INSTANCE_CUSTOM;

	if (u_is_instanced < 0.5 && CUSTOM0.z > 0.001) {
		vec3 wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float ph = u_time * 1.7 + wp0.x * 0.85 + wp0.z * 0.72;
		float g = sin(ph) * 0.62 + sin(ph * 2.35 + 1.7) * 0.38;
		VERTEX.x += g * 0.075 * CUSTOM0.z * u_wind;
		VERTEX.z += cos(ph * 0.82) * 0.055 * CUSTOM0.z * u_wind;
		VERTEX.y += sin(ph * 1.9) * 0.022 * CUSTOM0.z * u_wind;
	}

	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_wpos = wp.xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float layer = clamp(floor(v_surf.x + 0.5), 0.0, 10.0);
	vec4 tex_a = texture(u_tex_albedo, vec3(UV, layer));
	vec3 tex_n = texture(u_tex_normal, vec3(UV, layer)).rgb * 2.0 - 1.0;

	vec3 col = COLOR.rgb;
	float flash = 0.0;
	if (u_is_instanced > 0.5) {
		// INSTANCE_CUSTOM: rgb = tint (defaults to 0 if unset, so check length), a = hit flash
		vec3 tint = v_inst_custom.rgb;
		if (dot(tint, tint) > 0.0001) {
			col *= tint;
		}
		flash = clamp(v_inst_custom.a, 0.0, 1.0);
	}

	// Detail albedo modulation (2.0 centers 0.5 mid-gray at 1.0 multiplier)
	col *= tex_a.rgb * 2.0;

	// Height-driven micro-AO and roughness
	float h_val = tex_a.a;
	float rough = clamp(v_surf.y * (1.16 - 0.32 * h_val), 0.06, 0.99);
	float metal = 0.02;
	if (layer > 4.5 && layer < 5.5) {
		// L_METAL: forged iron, steel, brass, gold glint
		metal = 0.72;
		rough = clamp(rough * 0.72, 0.14, 0.78);
	} else if (layer > 5.5 && layer < 6.5) {
		// L_SLATE: slight sheen on wet/chiseled roof slate
		metal = 0.06;
		rough = clamp(rough * 0.88, 0.25, 0.92);
	}

	// Screen-space tangent basis for procedural normal map perturbation
	vec3 wn = normalize(v_wnrm);
	vec3 up_ref = abs(wn.y) < 0.98 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 T = normalize(cross(up_ref, wn));
	vec3 B = cross(wn, T);
	vec3 perturbed_w = normalize(wn + (T * tex_n.x + B * tex_n.y) * u_normal_scale);

	// Biome top-cover overlay (snow, moss, ash, sand) on world geometry
	float cover_cv = 0.0;
	if (u_is_instanced < 0.5 && u_cover.x > 0.001) {
		float n1 = cw_n(v_wpos.xz * 0.78 + vec2(17.0, 9.0));
		float n2 = cw_n(v_wpos.xz * 3.3 + vec2(v_wpos.y * 1.25));
		float nn = n1 * 0.62 + n2 * 0.38;
		float cv = smoothstep(u_cover.y, u_cover.y + 0.22, perturbed_w.y + (nn - 0.5) * u_cover.z);
		if (layer > 3.5 && layer < 4.5) {
			// Cobble: cover gathers in mortar cracks first
			cv *= u_cover.w * smoothstep(0.82, 0.24, h_val - (n1 - 0.5) * 0.85);
		}
		cv *= u_cover.x * (1.0 - clamp(v_surf.w * 40.0, 0.0, 1.0));
		cover_cv = cv;

		vec3 ccol = u_cover_col * (0.90 + 0.20 * n1);
		// Subtle wind-rippled sand dunes or soft snow variation
		if (u_cover_p.w > 0.001) {
			float rip = sin(dot(v_wpos.xz, vec2(5.1, 3.3)) + n1 * 7.0);
			ccol *= 1.0 + rip * 0.055;
			perturbed_w = normalize(perturbed_w + vec3(rip * u_cover_p.w * cv, 0.0, rip * u_cover_p.w * 0.7 * cv));
		}
		col = mix(col, ccol, cv);
		rough = mix(rough, u_cover_p.x, cv);
		metal = mix(metal, 0.0, cv);
		perturbed_w = normalize(mix(perturbed_w, wn, cv * u_cover_p.y));
	}

	// Transform world-space normal to view-space for Godot 4 spatial NORMAL
	NORMAL = normalize((VIEW_MATRIX * vec4(perturbed_w, 0.0)).xyz);

	// Crisp moonlight/firelight rim highlight for miniature diorama readability
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.2);

	vec3 emis = col * v_surf.w * 5.8;
	if (u_cover_sparkle > 0.01 && cover_cv > 0.25) {
		float sp = cw_h(floor(v_wpos.xz * 26.0) + floor(VIEW.xy * 18.0));
		float glint = smoothstep(0.985, 1.0, sp) * cover_cv * u_cover_sparkle;
		emis += vec3(0.75, 0.90, 1.15) * glint * 1.4;
	}
	if (flash > 0.001) {
		emis += vec3(1.15, 0.88, 0.58) * flash * 0.85;
	}
	// Subtle atmospheric rim on characters & towers
	emis += u_rim_col * fres * u_rim_amt * (u_is_instanced > 0.5 ? 1.45 : 0.55);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.45, 0.72, metal);
	EMISSION = emis;
}
