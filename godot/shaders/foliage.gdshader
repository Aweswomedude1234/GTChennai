shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Leaf cards (trees, palms, shrubs). Alpha-scissored atlas, two-sided with back-lit translucency,
// wind sway driven by the global `wind` uniform. COLOR tints the leaves (species / season / dust),
// CUSTOM0.x = texture (0 leaf cluster, 1 palm frond), CUSTOM0.y = sway weight.
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D frond : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying flat float tex_id;
varying vec3 wp;

void vertex() {
	tex_id = CUSTOM0.x;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = CUSTOM0.y;
	float t = TIME;
	vec2 wd = wind.xz;
	float gust = 0.6 + 0.4 * sin(t * 0.7 + wp.x * 0.05 + wp.z * 0.03);
	float flutter = sin(t * 4.0 + wp.x * 1.7 + wp.y * 2.3) * 0.04;
	VERTEX.xz += (wd * 0.25 * gust + vec2(flutter)) * w;
	VERTEX.y += flutter * 0.5 * w;
}

void fragment() {
	vec4 c = tex_id < 0.5 ? texture(leaves, UV) : texture(frond, UV);
	if (c.a < 0.5) discard;
	vec3 col = c.rgb * COLOR.rgb;
	// dust on leaves near roads (Chennai trees are dusty before the monsoon)
	col = mix(col, col * vec3(1.05, 1.0, 0.9) + 0.03, (1.0 - wet) * 0.25);
	ALBEDO = col * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(0.75, 0.35, wet);
	SPECULAR = 0.35;
	BACKLIGHT = col * 0.6;
	if (!FRONT_FACING) NORMAL = -NORMAL;
}
