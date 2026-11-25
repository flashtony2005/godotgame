shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_add;

// Additive 3D ribbon segment shader for storm-spire lightning bolts and flaming arrow trails.
// UV.y is 0..1 across the ribbon width (0.5 = bright core, 0/1 = soft outer halo).
varying vec2 v_uv;
varying vec4 v_col;

void vertex() {
	v_uv = UV;
	v_col = COLOR;
}

void fragment() {
	float d = abs(v_uv.y - 0.5) * 2.0;
	float core = smoothstep(1.0, 0.0, d);
	float glow = pow(core, 1.4);
	float hot = pow(core, 4.5);
	vec3 col = v_col.rgb * glow + vec3(1.0, 0.96, 0.9) * hot * 0.65;
	float a = glow * v_col.a;
	if (a <= 0.002) {
		discard;
	}
	ALBEDO = col * v_col.a;
	ALPHA = 1.0;
}
