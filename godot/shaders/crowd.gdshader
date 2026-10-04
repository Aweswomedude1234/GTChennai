shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"
// Mid-distance crowd: vertex-animation-texture people (baked from the MPFB bodies + CMU mocap by
// tools/humans/bake_vat.py). One MultiMesh per body variant; per-instance data:
//   COLOR            = top garment colour (rgb), a = skin tone index / 8
//   INSTANCE_CUSTOM  = (clip row * 1000 + clip frames, phase in frames, playback speed, lower colour packed 0xRRGGBB)
// UV2.x = vertex column in the VAT, UV2.y = part (0 skin, 1 top, 2 lower, 3 drape, 4 hair, 5 extra, 6 eyes, 7 shoes).
uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform float vat_range = 1.0;
uniform float fps = 30.0;
uniform float grey_hair = 0.0;
uniform sampler2D weave : hint_default_white, filter_linear_mipmap, repeat_enable;
const vec3 SKIN[9] = vec3[](vec3(0.584, 0.332, 0.191), vec3(0.485, 0.254, 0.125), vec3(0.413, 0.198, 0.090), vec3(0.332, 0.150, 0.064),
	vec3(0.262, 0.111, 0.048), vec3(0.202, 0.081, 0.035), vec3(0.147, 0.058, 0.025), vec3(0.105, 0.042, 0.018), vec3(0.074, 0.030, 0.014));

varying flat int part;
varying vec3 top_c;
varying vec3 low_c;
varying vec3 skin_c;
varying vec3 lp;

vec3 unpack_rgb(float v) {
	float r = floor(v / 65536.0); float g = floor((v - r * 65536.0) / 256.0); float b = v - r * 65536.0 - g * 256.0;
	return pow(vec3(r, g, b) / 255.0, vec3(2.2));
}

void vertex() {
	float clip = INSTANCE_CUSTOM.x;
	float row0 = floor(clip / 1000.0);
	float frames = clip - row0 * 1000.0;
	float f = mod(INSTANCE_CUSTOM.y + TIME * fps * INSTANCE_CUSTOM.z, max(frames, 1.0));
	float fa = floor(f), t = f - fa;
	float fb = mod(fa + 1.0, max(frames, 1.0));
	ivec2 size = textureSize(vat_pos, 0);
	int x = int(UV2.x * float(size.x));
	vec3 pa = texelFetch(vat_pos, ivec2(x, int(row0 + fa)), 0).rgb;
	vec3 pb = texelFetch(vat_pos, ivec2(x, int(row0 + fb)), 0).rgb;
	vec3 na = texelFetch(vat_nrm, ivec2(x, int(row0 + fa)), 0).rgb;
	vec3 nb = texelFetch(vat_nrm, ivec2(x, int(row0 + fb)), 0).rgb;
	VERTEX += (mix(pa, pb, t) - 0.5) * 2.0 * vat_range;
	NORMAL = normalize(mix(na, nb, t) * 2.0 - 1.0);
	lp = VERTEX;
	part = int(UV2.y * 8.0);
	top_c = COLOR.rgb;
	low_c = unpack_rgb(INSTANCE_CUSTOM.w);
	skin_c = SKIN[clamp(int(COLOR.a * 8.0 + 0.5), 0, 8)];
}

void fragment() {
	vec3 c;
	float rough = 0.9;
	vec4 w = texture(weave, vec2(atan(lp.x, lp.z) * 0.16, lp.y) * 30.0);
	if (part == 0) { c = skin_c; rough = 0.5; }
	else if (part == 1) { c = top_c * (0.88 + w.a * 0.2); }
	else if (part == 2 || part == 3) {
		c = low_c * (0.88 + w.a * 0.2);
		// border band near the hem for veshti / saree (skirts reach the ankle)
		c = mix(c, vec3(0.6, 0.45, 0.12), smoothstep(0.2, 0.18, lp.y) * smoothstep(0.06, 0.08, lp.y) * step(0.5, float(part == 3 || low_c.r + low_c.g + low_c.b > 2.2)));
	}
	else if (part == 4) { c = mix(vec3(0.018, 0.014, 0.011), vec3(0.45), grey_hair); rough = 0.45; }
	else if (part == 5) { c = vec3(0.85, 0.83, 0.76); }
	else if (part == 7) { c = vec3(0.05, 0.035, 0.025); rough = 0.4; }   // shoes
	else { c = vec3(0.8, 0.78, 0.74); rough = 0.2; }
	ALBEDO = c * mix(1.0, 0.85, wet);
	ROUGHNESS = rough;
	BACKLIGHT = c * 0.2;
}
