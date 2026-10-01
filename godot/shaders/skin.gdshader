shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Human skin (MPFB UV layout). Tone is per person (STYLE_BIBLE §6: wheatish to deep brown, no
// colourism). Pigmented lips and eyelids from MPFB's CC0 region masks, subtle mottling and pores,
// subsurface scattering, and a humid-climate sheen that rises with the heat of the day.
uniform vec3 tone : source_color = vec3(0.55, 0.36, 0.24);
uniform float age = 0.5;
uniform float male = 1.0;
uniform float sweat = 0.4;
uniform sampler2D masks : hint_default_black, filter_linear_mipmap;   // r lips, g eyelids, b nails, a face
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec4 m = texture(masks, UV);
	vec4 n1 = texture(noise, UV * 23.0);
	vec4 n2 = texture(noise, UV * 160.0);
	vec3 c = tone * (0.94 + n1.r * 0.1);
	// slightly darker, warmer around the eyes and at knuckles/creases; redder cheeks are rare on dark skin
	c *= mix(1.0, 0.78, m.g);
	c = mix(c, tone * vec3(0.62, 0.42, 0.42), m.r * 0.85);
	c = mix(c, vec3(0.75, 0.6, 0.55) * (tone * 0.6 + 0.4), m.b * 0.8);
	// age: uneven tone and dryness
	c *= 1.0 - age * 0.08 * n1.g;
	ALBEDO = c;
	float pore = n2.a;
	ROUGHNESS = mix(0.55, 0.38, sweat * (hour > 10.0 && hour < 17.0 ? 1.0 : 0.6)) + pore * 0.08 - m.r * 0.15;
	SPECULAR = 0.42;
	NORMAL_MAP = vec3(0.5 + (n2.r - 0.5) * 0.18, 0.5 + (n2.g - 0.5) * 0.18, 1.0);
	SSS_STRENGTH = 0.32;
	BACKLIGHT = tone * 0.35;
}
