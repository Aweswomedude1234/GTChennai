shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Ground by area kind (CUSTOM0.x): 0 urban earth/cement, 1 park, 2 playground earth, 3 dry sand,
// 4 temple granite, 5 cemetery, 6 wet sand, 7 parking, 8 institution, 9 commercial, 10 residential.
uniform sampler2D earth_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D granite_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying flat float kind;
varying float tintv;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = CUSTOM0.x;
	tintv = COLOR.r;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = wp.xz;
	vec4 nz = texture(noise, p / 140.0);
	vec4 nz2 = texture(noise, p / 17.0);
	vec3 col; vec4 nm; float rough;
	int k = int(kind + 0.5);
	if (k == 1 || k == 5) {
		col = texture(grass_c, p / 4.0).rgb; nm = texture(grass_n, p / 4.0);
		// worn footpaths and dry patches across the lawn
		float dry = smoothstep(0.45, 0.75, nz.r + (nz2.g - 0.5) * 0.3);
		col = mix(col, texture(earth_c, p / 4.0).rgb, dry * 0.7);
		rough = 0.95;
	} else if (k == 3 || k == 6) {
		col = texture(sand_c, p / 6.0).rgb; nm = texture(sand_n, p / 6.0);
		float wetsand = float(k == 6);
		// litter line and footprints-darkened sand near the promenade
		col *= mix(1.0, 0.62, wetsand) * (0.92 + nz.g * 0.16);
		rough = mix(0.95, 0.45, wetsand);
	} else if (k == 4) {
		col = texture(granite_c, p / 3.6).rgb * 0.8; nm = texture(granite_n, p / 3.6); rough = nm.b;
	} else if (k == 7 || k == 9) {
		col = texture(concrete_c, p / 3.0).rgb * 0.42; nm = texture(concrete_n, p / 3.0); rough = 0.9;
		col = mix(col, texture(earth_c, p / 4.0).rgb, smoothstep(0.55, 0.8, nz.g) * 0.6);
	} else if (k == 2) {
		col = texture(earth_c, p / 4.0).rgb * vec3(1.15, 0.95, 0.8); nm = texture(earth_n, p / 4.0); rough = 0.97;
	} else {
		// urban ground: compacted earth with cement patches, dust and scattered litter
		col = texture(earth_c, p / 4.0).rgb; nm = texture(earth_n, p / 4.0); rough = 0.96;
		float cem = smoothstep(0.62, 0.7, nz.g * 0.7 + nz2.r * 0.3) * 0.75;
		vec3 cemc = texture(concrete_c, p / 3.0).rgb * 0.42 * mix(vec3(1.0), texture(earth_c, p / 4.0).rgb * 2.2, 0.35);
		col = mix(col, cemc, cem);
		float weed = smoothstep(0.62, 0.8, nz.r) * (1.0 - cem);
		col = mix(col, texture(grass_c, p / 4.0).rgb * 0.8, weed * 0.6);
		vec2 lc = floor(p * 1.6);
		float litter = step(0.985, hash21(lc)) * step(0.4, nz.g);
		vec3 lcol = mix(vec3(0.85, 0.85, 0.8), mix(vec3(0.6, 0.1, 0.1), vec3(0.1, 0.3, 0.7), hash21(lc + 3.1)), step(0.5, hash21(lc + 7.7)));
		col = mix(col, lcol, litter * box2(fract(p * 1.6), vec2(0.2), vec2(0.5 + hash21(lc) * 0.3)));
	}
	col *= tintv * (0.9 + nz.r * 0.2);
	col *= mix(1.0, 0.65, wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.35, wet * 0.5);
	NORMAL_MAP = nmap(nm);
}
