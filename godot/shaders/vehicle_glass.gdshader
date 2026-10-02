// Vehicle glazing: dark tint, Fresnel reflections, a film of road dust. Transparent pass.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://shaders/common.gdshaderinc"

instance uniform float dirt : instance_index(3) = 0.4;
varying vec3 opos;

void vertex() { opos = VERTEX; }

void fragment() {
	float n1 = fbm2(opos.xz * 3.1 + opos.y * 2.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float d = smoothstep(0.7, 1.0, n1) * dirt * 0.4 * (1.0 - wet * 0.7);
	ALBEDO = mix(vec3(0.02, 0.026, 0.03), vec3(0.3, 0.26, 0.2), d);
	ROUGHNESS = mix(0.03, 0.5, d);
	SPECULAR = 0.9;
	ALPHA = clamp(0.6 + fres * 0.38 + d * 0.3, 0.0, 1.0);
}
