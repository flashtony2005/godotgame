shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_add;

// 2-layer GPU instanced weather system (ported & enhanced from 41-weather.js):
// Dust motes, Blizzard snow + gusts, Glowing fireflies + bog mist, Volcanic ash + embers, Desert sandstorm.

uniform float u_time = 0.0;
uniform float u_fade = 1.0;
uniform vec3 u_amb = vec3(0.22, 0.28, 0.40);
uniform vec3 u_light_pos[12];
uniform vec3 u_light_col[12];

uniform vec2 u_n = vec2(0.45, 0.0);
uniform vec3 u_vel_a = vec3(0.45, -0.18, 0.25);
uniform vec3 u_vel_b = vec3(0.0);
uniform vec2 u_sway_a = vec2(0.8, 0.7);
uniform vec2 u_sway_b = vec2(0.0);
uniform vec2 u_size_a = vec2(0.032, 0.068);
uniform vec2 u_size_b = vec2(0.02, 0.04);
uniform vec4 u_col_a = vec4(0.68, 0.76, 0.94, 0.85);
uniform vec4 u_col_b = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 u_al_a = vec3(0.32, 0.0, 0.0);
uniform vec3 u_al_b = vec3(0.0);
uniform vec2 u_y_a = vec2(0.4, 8.0);
uniform vec2 u_y_b = vec2(0.4, 8.0);

varying vec4 v_col;
varying vec2 v_uv;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float is_b = step(seed.w, u_n.y);
	float show = step(seed.w, u_n.x + u_n.y);

	vec3 vel = mix(u_vel_a, u_vel_b, is_b);
	vec3 al = mix(u_al_a, u_al_b, is_b);
	vec2 sway = mix(u_sway_a, u_sway_b, is_b);
	vec2 sz = mix(u_size_a, u_size_b, is_b);
	vec2 yr = mix(u_y_a, u_y_b, is_b);
	vec4 cp = mix(u_col_a, u_col_b, is_b);

	float r1 = fract(seed.w * 91.7 + seed.x * 3.1);
	float r2 = fract(seed.w * 357.3 + seed.z * 5.7);
	float span = max(yr.y - yr.x, 0.05);

	vec3 p = vec3(seed.x * 48.0, seed.y * span, seed.z * 48.0) + vel * u_time * (0.65 + 0.7 * r1);
	p.x += sin(u_time * sway.y * (0.6 + r2) + seed.y * 40.0) * sway.x;
	p.z += cos(u_time * sway.y * (0.5 + r1) + seed.x * 40.0) * sway.x;
	p.y += sin(u_time * sway.y * 0.7 + r1 * 30.0) * sway.x * 0.3;

	p.x = mod(p.x, 48.0) - 24.0;
	p.z = mod(p.z, 48.0) - 24.0;
	p.y = mod(p.y, span) + yr.x;

	float size = mix(sz.x, sz.y, r2);
	vec4 mv = VIEW_MATRIX * vec4(p, 1.0);
	vec3 vv = (VIEW_MATRIX * vec4(vel, 0.0)).xyz;
	float vl = length(vv.xy);
	vec2 dir = vl > 0.0001 ? vv.xy / vl : vec2(0.0, 1.0);
	mv.xy += VERTEX.x * vec2(-dir.y, dir.x) * size + VERTEX.y * dir * size * (1.0 + al.z * vl);

	if (show > 0.5 && u_fade > 0.005) {
		POSITION = PROJECTION_MATRIX * mv;
	} else {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}

	vec3 L = u_amb;
	for (int i = 0; i < 12; i++) {
		vec3 lc = u_light_col[i];
		if (lc.r + lc.g + lc.b > 0.001) {
			vec3 d = u_light_pos[i] - p;
			L += lc / (dot(d, d) + 3.5);
		}
	}
	float tw = al.y > 0.0 ? pow(max(0.0, sin(u_time * al.y * (0.5 + r1) + r2 * 60.0)), 4.0) : 1.0;
	float ef = smoothstep(24.0, 20.5, max(abs(p.x), abs(p.z)))
		* smoothstep(yr.x, yr.x + 0.5, p.y)
		* smoothstep(yr.y, yr.y - 1.2, p.y);
	v_col = vec4(cp.rgb * mix(vec3(1.0), L, cp.a), al.x * tw * ef * u_fade);
	v_uv = VERTEX.xy;
}

void fragment() {
	float a = smoothstep(1.0, 0.22, length(v_uv)) * v_col.a;
	if (a <= 0.003) {
		discard;
	}
	ALBEDO = v_col.rgb * a;
	ALPHA = 1.0;
}
