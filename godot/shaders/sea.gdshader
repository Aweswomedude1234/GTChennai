shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Bay of Bengal off Marina (STYLE_BIBLE §7): grey-green #5d7066, 2–4 white surf lines rolling in,
// foam on the wet sand, gentle swell. UV.x = metres offshore from the surf line.
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
varying float off;

float swell(vec2 p, float t) {
	return sin(p.x * 0.09 - t * 0.9 + sin(p.y * 0.013) * 2.0) * 0.18 + sin(p.x * 0.23 + p.y * 0.05 - t * 1.6) * 0.07 + sin(p.y * 0.11 + p.x * 0.04 - t * 1.1) * 0.05;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	off = UV.x;
	float damp = smoothstep(0.0, 40.0, off);
	VERTEX.y += swell(wp.xz, TIME) * damp;
	float e = 0.5;
	float hx = swell(wp.xz + vec2(e, 0.0), TIME) - swell(wp.xz - vec2(e, 0.0), TIME);
	float hz = swell(wp.xz + vec2(0.0, e), TIME) - swell(wp.xz - vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-hx * damp, 2.0 * e, -hz * damp));
}

void fragment() {
	float t = TIME;
	vec4 nz = texture(noise, wp.xz / 60.0 + vec2(t * 0.004, t * 0.002));
	vec4 nz2 = texture(noise, wp.xz / 9.0 - vec2(t * 0.02, 0.0));
	vec3 deep = vec3(0.07, 0.12, 0.11);
	vec3 shallow = vec3(0.16, 0.22, 0.19);
	vec3 col = mix(shallow, deep, smoothstep(10.0, 300.0, off)) * (0.85 + nz.r * 0.3);
	// surf: breaking lines travelling shoreward
	float phase = off / 14.0 + t * 0.12 + nz.g * 0.6;
	float line = smoothstep(0.82, 0.97, fract(phase)) * (1.0 - smoothstep(25.0, 70.0, off));
	float wash = (1.0 - smoothstep(0.0, 9.0, off + (nz2.r - 0.5) * 6.0));
	float foam = max(line * (0.6 + nz2.g * 0.6), wash * smoothstep(0.35, 0.7, nz2.b));
	col = mix(col, vec3(0.75, 0.78, 0.76), clamp(foam, 0.0, 1.0));
	col *= mix(1.0, 0.35, night);
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.6, foam);
	SPECULAR = 0.6;
	NORMAL_MAP = vec3(0.5 + (nz2.r - 0.5) * 0.25, 0.5 + (nz2.g - 0.5) * 0.25, 1.0);
}
