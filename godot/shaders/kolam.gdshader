shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Kolam (rice-flour doorstep drawings, STYLE_BIBLE §8): drawn by 07:00, fading to ~30% by 14:00,
// mostly gone by night; trampled patches. CUSTOM0 = (atlas cell 0–15, red border flag).
uniform sampler2D atlas : filter_linear_mipmap;
varying flat vec2 kc;
varying vec3 wp;
void vertex() { kc = CUSTOM0.xy; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = vec2(mod(kc.x, 4.0), floor(kc.x / 4.0));
	vec4 t = texture(atlas, (cell + UV) / 4.0);
	float a = t.a;
	float fresh = hour < 5.5 ? 0.15 : (hour < 7.0 ? smoothstep(5.5, 7.0, hour) : mix(1.0, 0.3, smoothstep(7.0, 14.0, hour)));
	if (hour > 19.0) fresh *= 0.6;
	float trample = smoothstep(0.35, 0.6, fbm2(wp.xz * 3.0));
	a *= fresh * (1.0 - trample * 0.7) * (1.0 - wet * 0.8);
	vec3 col = vec3(0.93, 0.92, 0.88);
	float edge = smoothstep(0.42, 0.5, max(abs(UV.x - 0.5), abs(UV.y - 0.5)));
	col = mix(col, vec3(0.75, 0.12, 0.1), kc.y * edge);
	a = max(a, kc.y * edge * fresh * 0.7 * step(0.47, max(abs(UV.x - 0.5), abs(UV.y - 0.5))));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.95;
}
