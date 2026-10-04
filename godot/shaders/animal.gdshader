// Street animals (dogs, cows, goats) in MultiMeshes, animated without skeletons.
// UV2.x = body part (0 body, 1–4 legs FL FR BL BR, 5 tail, 6 head/neck, 7 ears), UV2.y = shade
// (dark nose/eyes/hooves). INSTANCE_CUSTOM = (state 0 stand / 1 walk / 2 lie / 3 sit / 4 sleep,
// phase, gait speed, seed). Instance COLOR = coat colour.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;
#include "res://shaders/common.gdshaderinc"

uniform vec3 hip0 = vec3(-0.05, 0.42, -0.2);   // leg hip pivots (Godot model space)
uniform vec3 hip1 = vec3(0.05, 0.42, -0.2);
uniform vec3 hip2 = vec3(-0.05, 0.44, 0.24);
uniform vec3 hip3 = vec3(0.05, 0.44, 0.24);
uniform float lie_drop = 0.33;
uniform float height = 0.5;
uniform vec3 patch_col : source_color = vec3(0.95, 0.93, 0.88);
uniform float patchy = 0.5;
uniform float lie_front = 1.45;                 // front legs when lying: + stretched forward (dogs), − folded under (cattle)
uniform float side_r = 0.12;                    // half-width of the torso (rest height when sleeping on the side)                     // how often coats are patched / two-tone

varying vec3 opos;
varying float shade;
varying flat float seed;
varying flat int part;

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }

void vertex() {
	part = int(UV2.x * 8.0);
	shade = 1.0 - UV2.y;   // glTF stores V flipped
	float state = INSTANCE_CUSTOM.x;
	float t = TIME * INSTANCE_CUSTOM.z * 6.0 + INSTANCE_CUSTOM.y;
	seed = INSTANCE_CUSTOM.w;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	opos = v;
	bool lying = state > 1.5 && state < 2.5;
	bool on_side = state > 3.5;
	bool walking = state > 0.5 && state < 1.5;
	if (part >= 1 && part <= 4) {
		vec3 hip = part == 1 ? hip0 : (part == 2 ? hip1 : (part == 3 ? hip2 : hip3));
		bool front = part <= 2;
		float a = 0.0;
		if (walking) {
			// diagonal walk: FL with BR, FR with BL
			float ph = (part == 1 || part == 4) ? 0.0 : PI;
			a = sin(t + ph) * 0.42;
		} else if (lying) {
			a = front ? lie_front : 1.55;      // sternal: front legs forward (or folded under), hind legs tucked forward under the belly
		} else if (on_side) {
			a = front ? 0.35 : -0.3;           // relaxed legs when stretched out on the side
		} else if (state > 2.5) {
			a = front ? 0.0 : 1.4;             // sitting on the haunches, hind legs forward
		}
		mat3 r = rot_x(a);
		v = hip + r * (v - hip);
		n = r * n;
	}
	if (part == 5) {    // tail: wag (dogs wag faster when walking), droop when lying
		vec3 base = vec3(0.0, height * 0.95, (hip2.z + 0.05));
		float w = sin(TIME * (walking ? 9.0 : 4.0) + seed * 13.0) * (lying ? 0.15 : 0.45);
		mat3 r = rot_y(w);
		v = base + r * (v - base); n = r * n;
	}
	if (part == 6 || part == 7) {   // head looks around; rests low when sleeping
		vec3 neck = vec3(0.0, height * 1.05, hip0.z - 0.02);
		float look = (fbm2(vec2(TIME * 0.15, seed * 7.0)) - 0.5) * 1.6;
		if (walking) look *= 0.3;
		mat3 r = rot_y(look);
		if (lying) r = rot_x(-0.35) * r;     // head lowered
		v = neck + r * (v - neck); n = r * n;
		if (part == 7) v.y += sin(TIME * 2.3 + seed * 5.0) * 0.004;
	}
	if (lying) {
		v.y -= lie_drop;
		v.y = max(v.y, 0.012 + (part >= 1 && part <= 4 ? 0.0 : 0.03));
	} else if (on_side) {
		// asleep on its side, stretched out on the warm footpath
		float c = 0.0, sn = 1.0;   // roll 90° about the long axis
		vec3 q = v - vec3(0.0, height * 0.9, 0.0);
		v = vec3(q.y * sn, -q.x * sn + side_r, q.z);
		n = vec3(n.y * sn, -n.x * sn, n.z);
		v.y = max(v.y, 0.01);
	} else if (state > 2.5) {
		// sit: rear lowered, chest up
		float k = clamp((v.z - hip0.z) / max(hip2.z - hip0.z, 0.01), 0.0, 1.0);
		v.y -= k * lie_drop * 0.8;
		v.y = max(v.y, 0.012);
	}
	if (walking) v.y += abs(sin(t)) * 0.012 * height;
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	vec3 coat = COLOR.rgb;
	// patches (white socks/chest on dogs, piebald goats, grey-white cows), keyed by the seed
	float pm = fbm2(opos.xz * 6.0 + opos.yy * 4.0 + vec2(seed * 31.0, seed * 17.0));
	float has = step(1.0 - patchy, fract(seed * 7.13));
	float m = has * smoothstep(0.52, 0.6, pm);
	float lowpale = smoothstep(height * 0.62, height * 0.35, opos.y) * 0.35 * float(part == 0);   // paler belly
	vec3 c = mix(coat, patch_col, max(m, lowpale));
	if (part >= 1 && part <= 4) c = mix(c, patch_col, has * step(0.5, fract(seed * 3.7)) * smoothstep(0.16 * height, 0.08 * height, opos.y));   // white socks
	c *= mix(0.08, 1.0, shade);
	// short coat: noise-driven fur variation and a dusty tint
	float fur = vnoise(opos.xy * 120.0 + opos.zz * 90.0);
	c *= 0.88 + fur * 0.2;
	c = mix(c, vec3(0.45, 0.38, 0.3), 0.12 * smoothstep(height * 0.3, 0.0, opos.y));
	ALBEDO = c;
	ROUGHNESS = shade < 0.2 ? 0.3 : 0.82;
	SPECULAR = 0.3;
	SSS_STRENGTH = 0.1;
}
