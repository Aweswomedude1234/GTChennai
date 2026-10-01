shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Chennai roads (STYLE_BIBLE §4): asphalt from new #3a3a3a to dusty #5a5853, patch repairs,
// potholes, sand/dust drifted to the edges, faded centre dashes on secondary+ roads, wet sheen.
uniform sampler2D asphalt_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying vec4 rd; // wear, rank, width, rnd

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rd = CUSTOM0;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float wear = rd.x, rank = rd.y, width = rd.z, rnd = rd.w;
	float along = UV.x, across = UV.y; // across: -1..1 (0.45 marks junction patches)
	bool junction = abs(UV.y - 0.45) < 0.01 && UV.x == 0.0;
	vec2 tuv = wp.xz / 4.0;
	vec3 asph = texture(asphalt_c, tuv).rgb;
	vec4 an = texture(asphalt_n, tuv);
	vec4 nz = texture(noise, wp.xz / 160.0);
	vec4 nz2 = texture(noise, wp.xz / 23.0);
	// age: new black asphalt → grey dusty; varies along the road too
	float age = clamp(wear * 0.8 + (nz.r - 0.5) * 0.5, 0.0, 1.0);
	vec3 col = asph * mix(vec3(0.85), vec3(1.6, 1.55, 1.45), age);
	float rough = mix(0.78, 0.92, age) * an.b * 1.05;
	// patch repairs: darker rectangles 8–15% of the area
	vec2 pc = floor(vec2(along / 6.0, (across + 1.0) * 1.5) + rnd * 13.0);
	float ph = hash21(pc);
	vec2 pf = fract(vec2(along / 6.0, (across + 1.0) * 1.5) + rnd * 13.0);
	float patch_m = step(0.87, ph) * box2(pf, vec2(0.08 + ph * 0.1, 0.1), vec2(0.7 + ph * 0.2, 0.85));
	if (junction) patch_m = 0.0;
	col = mix(col, asph * 0.75, patch_m);
	// potholes: more on residential streets (rank <= 2)
	float pd = (rank <= 2.0) ? 0.6 : 0.25;
	vec2 hc = floor(wp.xz / 3.0);
	vec2 hp = hash22(hc + rnd);
	float hole_r = 0.25 + hash21(hc * 1.7) * 0.4;
	float hd = length(wp.xz - (hc + hp) * 3.0) / hole_r;
	float hole = step(1.0 - pd * 0.12, hash21(hc + 0.37)) * (1.0 - smoothstep(0.75, 1.0, hd + (nz2.g - 0.5) * 0.6));
	hole *= step(abs(across), 0.85);
	if (junction) hole *= 0.5;
	col = mix(col, texture(earth_c, tuv * 2.0).rgb * 0.55, hole * 0.85);
	// edge dust and sand drift (heavier on lanes, near the beach)
	float edge = smoothstep(0.55, 1.0, abs(across) + (nz2.r - 0.5) * 0.35);
	float dust_amt = mix(0.55, 0.95, step(rank, 2.5));
	vec3 dust = texture(earth_c, tuv).rgb * vec3(1.1, 1.05, 0.98);
	if (!junction) col = mix(col, dust, edge * dust_amt);
	// faded markings: centre dashes on secondary+ (3 m dash, 4.5 m gap); edge lines on primary
	float mark = 0.0;
	if (!junction && rank >= 4.0) {
		float dash = step(fract(along / 7.5), 0.4);
		float wdt = 0.12 / max(width * 0.5, 1.0);
		mark = dash * (1.0 - smoothstep(wdt * 0.6, wdt, abs(across)));
		if (rank >= 5.0) mark = max(mark, 1.0 - smoothstep(0.012, 0.03, abs(abs(across) - 0.93)));
	}
	float fade = smoothstep(0.25, 0.7, nz.g + (hash11(floor(along / 40.0) + rnd) - 0.5) * 0.6);
	mark *= (1.0 - fade) * (1.0 - patch_m) * 0.85;
	col = mix(col, vec3(0.78, 0.77, 0.72), mark);
	// wet: darker, glossy, puddles in potholes and low edges
	float puddle = clamp(hole + edge * smoothstep(0.55, 0.75, nz2.b) * 0.8, 0.0, 1.0) * smoothstep(0.2, 0.8, wet);
	col *= mix(1.0, 0.6, wet * 0.8);
	rough = mix(rough, 0.25, wet * 0.6);
	col = mix(col, col * 0.5, puddle);
	rough = mix(rough, 0.04, puddle);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	SPECULAR = 0.4;
	NORMAL_MAP = mix(nmap(an), vec3(0.5, 0.5, 1.0), max(puddle, mark * 0.6));
	NORMAL_MAP_DEPTH = 1.0 + hole * 0.5;
}
