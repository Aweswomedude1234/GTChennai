// Vehicle body materials (GLBs from tools/vehicles/build_vehicles.py). One shader, `part` picks the role:
//  0 paint — per-instance colour + optional second livery colour in an object-space height band
//            (auto-rickshaw green skirt, bus stripes), clear coat, Chennai road dust rising from the
//            sills, a few scuffs, rain wetness.
//  (glass lives in vehicle_glass.gdshader: it must be in the transparent pass)
//  2 head lamp, 3 tail lamp, 4 indicator — lenses that light at night (tail also when braking,
//            indicators blink when `blink` is set).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://shaders/common.gdshaderinc"

uniform int part = 0;
uniform bool second = false;      // the "paint2" material: whole surface in the second colour
instance uniform vec4 paint : source_color, instance_index(0) = vec4(0.95, 0.75, 0.05, 1.0);
instance uniform vec4 paint2 : source_color, instance_index(1) = vec4(0.1, 0.35, 0.18, 1.0);
instance uniform vec4 band : instance_index(2) = vec4(-10.0, -10.0, -10.0, -10.0);   // (lo, hi) object-space Y ranges using paint2; zw a 2nd band
instance uniform float dirt : instance_index(3) = 0.4;
instance uniform float age : instance_index(4) = 0.3;          // fading + scuffs
instance uniform float brake : instance_index(5) = 0.0;
instance uniform float blink : instance_index(6) = 0.0;        // -1 left, 1 right, 2 hazards
instance uniform float lights : instance_index(7) = 0.0;       // headlights forced on (player)

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

float aaband(float y, float lo, float hi) {
	float w = fwidth(y) * 0.8 + 1e-4;
	return smoothstep(lo - w, lo + w, y) * (1.0 - smoothstep(hi - w, hi + w, y));
}

void fragment() {
	float n1 = fbm2(opos.xz * 3.1 + opos.y * 2.0);
	float n2 = vnoise(opos.xy * 23.0 + opos.z * 7.0);
	// dust: heavier low on the body and on upward faces; streaks under rain
	float low = 1.0 - smoothstep(0.15, 0.9 + dirt * 0.3, opos.y);
	float dust = clamp((low * 0.8 + max(onrm.y, 0.0) * 0.35) * dirt * (0.55 + n1 * 0.9), 0.0, 1.0) * (1.0 - wet * 0.6);
	vec3 dust_col = vec3(0.47, 0.40, 0.31);
	if (part == 0) {
		float b = max(aaband(opos.y, band.x, band.y), aaband(opos.y, band.z, band.w));
		vec3 col = second ? paint2.rgb : mix(paint.rgb, paint2.rgb, b);
		// sun fade (older paint loses saturation on top surfaces)
		float fade = age * max(onrm.y, 0.0) * 0.35;
		col = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))) * 1.15 + 0.03, fade);
		float scuff = step(0.93 - age * 0.06, n2) * (1.0 - smoothstep(0.3, 0.7, opos.y)) * age;
		col = mix(col, vec3(0.35, 0.33, 0.3), scuff * 0.7);
		ALBEDO = mix(col, dust_col, dust * 0.75);
		ROUGHNESS = mix(0.22 + age * 0.25, 0.85, dust) * (1.0 - wet * 0.5);
		METALLIC = 0.1;
		CLEARCOAT = (1.0 - dust) * (1.0 - age * 0.6);
		CLEARCOAT_ROUGHNESS = 0.08 + age * 0.2;
		SPECULAR = 0.5;
	} else {
		vec3 lens = part == 2 ? vec3(0.92, 0.92, 0.9) : (part == 3 ? vec3(0.6, 0.03, 0.02) : vec3(0.95, 0.45, 0.03));
		vec3 glow = part == 2 ? vec3(1.0, 0.95, 0.82) * 6.0 : (part == 3 ? vec3(1.0, 0.05, 0.02) * 3.0 : vec3(1.0, 0.5, 0.05) * 5.0);
		float on = 0.0;
		if (part == 2) on = max(smoothstep(0.35, 0.7, night), lights);
		else if (part == 3) on = max(smoothstep(0.35, 0.7, night) * 0.45, brake);
		else {
			float side = sign(opos.x);
			bool active = blink > 1.5 || (blink != 0.0 && sign(blink) == side);
			on = active ? step(0.5, fract(TIME * 1.4)) : 0.0;
		}
		ALBEDO = mix(lens, dust_col, dust * 0.4);
		ROUGHNESS = 0.08;
		SPECULAR = 0.8;
		EMISSION = glow * on;
	}
}
