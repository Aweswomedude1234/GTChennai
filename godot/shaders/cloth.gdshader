shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Garment cloth: base colour plus pattern — 0 plain, 1 checks (lungi, shirts), 2 border band at the
// hem (veshti, saree: gold zari or contrast), 3 vertical stripes, 4 small print (saree / kurta motifs).
uniform vec3 color : source_color = vec3(0.8);
uniform vec3 color2 : source_color = vec3(0.2);
uniform int pattern = 0;
uniform float scale = 1.0;
uniform float sheen = 0.0;        // silk / synthetic
uniform sampler2D weave : hint_default_white, filter_linear_mipmap, repeat_enable;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	// pattern coordinates in metres around the body (cylindrical), so checks and stripes stay even
	float ang = atan(lp.x, lp.z);
	vec2 u = vec2(ang * 0.16, lp.y) / (0.045 * scale);
	vec3 c = color;
	if (pattern == 1) {
		float a = step(0.5, fract(u.x * 0.5)); float b = step(0.5, fract(u.y * 0.5));
		float thin = max(step(0.92, fract(u.x * 2.0)), step(0.92, fract(u.y * 2.0)));
		c = mix(color, color2, a * b * 0.85 + (a + b) * 0.15);
		c = mix(c, vec3(0.95), thin * 0.3);
	} else if (pattern == 2) {
		float band = smoothstep(0.24, 0.22, lp.y) * smoothstep(0.06, 0.08, lp.y);
		float line = smoothstep(0.012, 0.0, abs(lp.y - 0.28));
		c = mix(color, color2, max(band, line));
	} else if (pattern == 3) {
		c = mix(color, color2, step(0.7, fract(u.x * 0.8)) * 0.8);
	} else if (pattern == 4) {
		vec2 cell = fract(u * 0.7) - 0.5;
		c = mix(color, color2, smoothstep(0.16, 0.1, length(cell)) * 0.9);
	}
	vec4 w = texture(weave, u * 1.5);
	c *= 0.86 + w.a * 0.22;
	c *= mix(1.0, 0.82, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.45, sheen);
	SPECULAR = mix(0.3, 0.6, sheen);
	NORMAL_MAP = vec3(w.rg, 1.0);
	NORMAL_MAP_DEPTH = 0.5;
	BACKLIGHT = c * 0.25;
}
