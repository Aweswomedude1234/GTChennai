shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Shop signboards from the per-chunk atlas. UV = 0..1 within the board; CUSTOM0.x = atlas cell,
// CUSTOM0.y = 1 for backlit flex boxes (glow at night).
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float rows = 1.0;
uniform float cols = 4.0;
varying flat vec2 cell;
varying flat float backlit;

void vertex() {
	cell = vec2(mod(CUSTOM0.x, cols), floor(CUSTOM0.x / cols));
	backlit = CUSTOM0.y;
}

void fragment() {
	vec2 pad = vec2(2.0 / 256.0, 2.0 / 80.0);
	vec2 uv = (cell + pad + UV * (1.0 - 2.0 * pad)) / vec2(cols, rows);
	vec3 c = texture(atlas, uv).rgb;
	ALBEDO = c * mix(1.0, 0.85, wet);
	ROUGHNESS = mix(0.55, 0.85, 1.0 - backlit);
	EMISSION = c * backlit * smoothstep(0.2, 0.8, night) * 1.4 * power;
}
