shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Pasted posters and painted wall writing from the global poster atlas.
// CUSTOM0 = (cell, type 0 poster / 1 wall panel, wear, 0). UV = 0..1 over the poster.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
const float PW = 192.0; const float PH = 256.0; const float WW = 384.0; const float WH = 96.0;
const float AW = 1536.0; const float AH = 1600.0;
varying flat vec4 pc;
varying vec3 wp;
void vertex() { pc = CUSTOM0; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv;
	if (pc.y < 0.5) {
		float c = mod(pc.x, 32.0);
		vec2 cell = vec2(mod(c, 8.0), floor(c / 8.0));
		uv = (cell * vec2(PW, PH) + vec2(UV.x, 1.0 - UV.y) * vec2(PW, PH)) / vec2(AW, AH);
	} else {
		float c = mod(pc.x, 24.0);
		vec2 cell = vec2(mod(c, 4.0), floor(c / 4.0));
		uv = (vec2(0.0, 4.0 * PH) + cell * vec2(WW, WH) + vec2(UV.x, 1.0 - UV.y) * vec2(WW, WH)) / vec2(AW, AH);
	}
	vec3 col = texture(atlas, uv).rgb;
	// torn and rain-washed patches show the wall behind
	float n = fbm2(UV * vec2(6.0, 8.0) + pc.x * 3.7);
	float torn = smoothstep(0.62, 0.66, n + pc.z * 0.25) * step(pc.y, 0.5);
	if (torn > 0.5) discard;
	col *= mix(1.0, 0.82 + 0.18 * n, pc.z);
	ALBEDO = col * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(0.8, 0.4, wet);
}
