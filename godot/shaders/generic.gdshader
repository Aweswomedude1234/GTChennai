shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Generic props/detail. COLOR = linear base colour, UV in metres, CUSTOM0 = (type, roughness, emissive, rnd).
// Types: 0 painted, 1 corrugated tin, 2 tarpaulin, 3 plastic water tank, 4 clay roof tile, 5 concrete,
// 6 metal, 7 glass, 8 emissive lamp/tube, 9 cloth, 10 granite, 11 sand, 12 wood, 13 lime-wash stucco,
// 14 footpath pavers, 15 kerb painted black/yellow, 16 exposed brick, 17 black rubber/plastic,
// 18 rusted iron, 19 sodium lamp, 20 LED lamp
uniform sampler2D plaster_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rooftile_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rooftile_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloth_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying vec3 wn;
varying flat vec4 gm;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	gm = CUSTOM0;
	if (abs(NORMAL.y) > 0.7) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
	else { TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL)); BINORMAL = vec3(0.0, 1.0, 0.0); }
}

void fragment() {
	int t = int(gm.x + 0.5);
	vec3 base = COLOR.rgb;
	vec4 nz = texture(noise, (wp.xz + wp.y * 0.7) / 9.0);
	vec4 nz2 = texture(noise, (wp.xz + wp.yy) / 2.3);
	vec3 col = base * (0.9 + nz.g * 0.2);
	float rough = gm.y;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	vec3 emis = vec3(0.0);
	if (t == 1) { // corrugated tin with rust
		float corr = sin(UV.x * 2.0 * PI / 0.076) * 0.5 + 0.5;
		float rust = smoothstep(0.55, 0.8, nz.r + nz2.b * 0.3);
		col = mix(base * (0.75 + corr * 0.35), vec3(0.32, 0.16, 0.07), rust);
		nm = vec3(0.5 + cos(UV.x * 2.0 * PI / 0.076) * 0.35, 0.5, 1.0);
		metal = 0.6 * (1.0 - rust); rough = mix(0.45, 0.9, rust);
	} else if (t == 2) { // tarpaulin wrinkles
		float wr = fbm2(UV * vec2(2.0, 3.0) + gm.w * 9.0);
		col = base * (0.78 + wr * 0.35);
		nm = vec3(0.5 + (fbm2(UV * 3.0 + 1.3) - 0.5) * 0.6, 0.5 + (wr - 0.5) * 0.6, 1.0);
		rough = 0.7;
	} else if (t == 3) { // black plastic water tank, horizontal ribs and dust
		float rib = step(0.5, fract(wp.y * 2.5));
		col = base * (0.8 + rib * 0.25) + vec3(0.12, 0.1, 0.08) * smoothstep(0.3, 0.9, nz.r) * step(0.0, wn.y + 0.3);
		rough = 0.55;
	} else if (t == 4) {
		vec2 u = UV / 1.5;
		col = texture(rooftile_c, u).rgb * (base / vec3(0.4, 0.09, 0.03)) * 0.9; vec4 n4 = texture(rooftile_n, u); nm = nmap(n4); rough = n4.b;
		col = clamp(col, 0.0, 1.0);
	} else if (t == 5) {
		vec4 n4 = texture(concrete_n, UV / 3.0); col = texture(concrete_c, UV / 3.0).rgb * 1.3 * (base / 0.5); nm = nmap(n4); rough = 0.92;
	} else if (t == 6) { // painted/galvanised metal
		col = base * (0.9 + nz2.r * 0.2); metal = 0.35; rough = max(gm.y, 0.35);
		col = mix(col, vec3(0.3, 0.17, 0.08), smoothstep(0.7, 0.9, nz2.g) * 0.5);
	} else if (t == 7) {
		col = base * 0.2; rough = 0.05; metal = 0.2;
	} else if (t == 8) { // fluorescent tube / LED
		col = base; rough = 0.3;
		emis = base * gm.z * mix(0.4, 6.0, night) * power;
	} else if (t == 9) {
		col = base * (0.85 + texture(cloth_n, UV * 4.0).a * 0.3); rough = 0.95;
		nm = nmap(texture(cloth_n, UV * 4.0));
	} else if (t == 10) {
		vec4 n4 = texture(granite_n, wp.xz / 3.6 + UV * 0.3); col = texture(granite_c, wp.xz / 3.6 + UV * 0.3).rgb * 1.3 * base; nm = nmap(n4); rough = n4.b;
	} else if (t == 11) {
		col = texture(sand_c, wp.xz / 6.0).rgb * base; rough = 0.95;
	} else if (t == 12) { // wood grain
		float g = sin((UV.y * 40.0 + fbm2(UV * vec2(3.0, 0.5)) * 6.0)) * 0.5 + 0.5;
		col = base * (0.75 + g * 0.3); rough = 0.75;
	} else if (t == 13) { // lime-wash stucco
		vec4 n4 = texture(plaster_n, UV / 2.0); col = base * (0.86 + n4.a * 0.22) * (0.92 + nz.r * 0.12); nm = nmap(n4); rough = 0.92;
		col = mix(col, col * 0.7, smoothstep(0.6, 0.85, nz2.g) * step(wp.y, 0.6)); // splash dirt at the base
	} else if (t == 14) { // pavers with broken/missing ones
		vec2 u = UV / 1.2;
		vec4 n4 = texture(pavers_n, u); col = texture(pavers_c, u).rgb * base * 1.2; nm = nmap(n4); rough = 0.85;
		float broken = step(0.8, hash21(floor(u * vec2(3.0, 6.0)) + gm.w * 17.0)) * step(0.5, nz.b);
		col = mix(col, vec3(0.32, 0.27, 0.21), broken);
	} else if (t == 15) { // kerb with 1 m black/yellow alternation, faded
		float s = step(0.5, fract((UV.x) / 1.0));
		col = mix(vec3(0.03), vec3(0.75, 0.6, 0.05), s);
		col = mix(col, vec3(0.45, 0.43, 0.4), smoothstep(0.45, 0.8, nz2.r)); rough = 0.85;
	} else if (t == 16) {
		vec4 n4 = texture(brick_n, UV / 1.2); col = texture(brick_c, UV / 1.2).rgb * (base * 1.1); nm = nmap(n4); rough = 0.9;
	} else if (t == 17) {
		col = base * 0.6; rough = 0.6;
	} else if (t == 18) {
		col = mix(base, vec3(0.35, 0.17, 0.07), smoothstep(0.35, 0.75, nz2.r)); rough = 0.8; metal = 0.3;
	} else if (t == 19 || t == 20) { // street lamp heads
		col = base; rough = 0.3;
		vec3 lc = (t == 19) ? vec3(1.0, 0.62, 0.25) : vec3(0.9, 0.95, 1.0);
		emis = lc * step(0.5, night) * gm.z * 8.0 * power;
	} else {
		vec4 n4 = texture(plaster_n, UV / 2.0); col = base * (0.88 + n4.a * 0.2); nm = mix(vec3(0.5, 0.5, 1.0), nmap(n4), 0.6);
	}
	// dust on upward-facing surfaces, and the wet look
	col = mix(col, vec3(0.42, 0.37, 0.3), smoothstep(0.75, 1.0, wn.y) * smoothstep(0.5, 0.9, nz.r) * 0.35 * float(t != 8 && t != 19 && t != 20));
	col *= mix(1.0, 0.7, wet * step(0.0, wn.y));
	ALBEDO = col;
	ROUGHNESS = mix(clamp(rough, 0.04, 1.0), 0.2, wet * 0.5 * step(0.5, wn.y));
	METALLIC = metal;
	NORMAL_MAP = nm;
	EMISSION = emis;
}
