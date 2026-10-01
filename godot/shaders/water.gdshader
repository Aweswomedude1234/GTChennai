shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Temple tank water: still, green-grey #4a5a48 with algae tint, light ripples and floating leaves/flowers.
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec4 a = texture(noise, wp.xz / 7.0 + vec2(TIME * 0.01, TIME * 0.006));
	vec4 b = texture(noise, wp.xz / 5.0 - vec2(TIME * 0.008, -TIME * 0.011));
	vec4 c = texture(noise, wp.xz / 40.0);
	vec3 col = mix(vec3(0.05, 0.075, 0.055), vec3(0.09, 0.12, 0.07), c.r);
	float scum = smoothstep(0.68, 0.8, c.g) * 0.6;
	col = mix(col, vec3(0.16, 0.2, 0.08), scum);
	vec2 fl = floor(wp.xz * 1.3);
	float flower = step(0.993, hash21(fl)) * step(length(fract(wp.xz * 1.3) - 0.5), 0.12);
	col = mix(col, mix(vec3(0.85, 0.5, 0.05), vec3(0.9, 0.85, 0.75), hash21(fl + 2.0)), flower);
	ALBEDO = col * mix(1.0, 0.4, night);
	ROUGHNESS = mix(0.04, 0.6, max(scum, flower));
	SPECULAR = 0.55;
	NORMAL_MAP = vec3(0.5 + (a.g - b.g) * 0.12, 0.5 + (a.b - b.r) * 0.12, 1.0);
}
