shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Black hair, often coconut-oiled (glossy) in Tamil Nadu; strands from stretched noise, anisotropic sheen.
uniform vec3 color : source_color = vec3(0.02, 0.016, 0.012);
uniform float oil = 0.6;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec4 s = texture(noise, UV * vec2(260.0, 18.0));
	ALBEDO = color * (0.75 + s.a * 0.5);
	ROUGHNESS = mix(0.7, 0.42, oil) + s.r * 0.15;
	SPECULAR = 0.55;
	ANISOTROPY = 0.7;
	NORMAL_MAP = vec3(0.5 + (s.g - 0.5) * 0.4, 0.5, 1.0);
}
