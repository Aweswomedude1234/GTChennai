shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Eyeball: dark brown iris and pupil facing forward (glTF +Z), wet glossy cornea.
uniform vec3 iris : source_color = vec3(0.12, 0.07, 0.04);
varying vec3 lp; varying vec3 ln;
void vertex() { lp = VERTEX; ln = NORMAL; }
void fragment() {
	float front = clamp(ln.z, 0.0, 1.0);
	vec3 c = mix(vec3(0.82, 0.8, 0.76), iris, smoothstep(0.86, 0.9, front));
	c = mix(c, vec3(0.01), smoothstep(0.965, 0.975, front));
	ALBEDO = c;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}
