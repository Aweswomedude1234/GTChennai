shader_type sky;
render_mode use_debanding;
// Chennai sky (STYLE_BIBLE §1): rarely deep blue; zenith #a9c2dc–#bccfe0 washing to near-white
// haze at the horizon; golden hour 17:15–18:10; never-black night with sodium-orange city glow.
uniform vec3 zenith : source_color = vec3(0.66, 0.76, 0.86);
uniform vec3 horizon : source_color = vec3(0.87, 0.89, 0.89);
uniform vec3 ground_col : source_color = vec3(0.45, 0.42, 0.38);
uniform vec3 sun_col : source_color = vec3(1.0, 0.97, 0.93);
uniform float night_f = 0.0;
uniform float haze = 0.6;
uniform float cloud_cover = 0.35;
uniform float sky_energy = 1.0;

float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y); }
float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.07 + 13.1; a *= 0.5; } return s; }

void sky() {
	vec3 d = EYEDIR;
	float up = max(d.y, 0.0);
	// day gradient: hazy horizon band
	float hz = pow(1.0 - up, 4.0 + (1.0 - haze) * 6.0);
	vec3 day = mix(zenith, horizon, hz);
	vec3 sd = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float sdot = max(dot(d, sd), 0.0);
	// mie glow around the sun, broader near the horizon (humid air)
	day += sun_col * (pow(sdot, 8.0) * 0.25 + pow(sdot, 64.0) * 0.6) * (1.0 - night_f);
	float disk = smoothstep(0.9996, 0.99985, sdot);
	day += sun_col * disk * 30.0 * (1.0 - night_f);
	// clouds: thin stratocumulus / haze patches drifting
	vec2 cp = d.xz / (d.y + 0.08) * 0.6 + vec2(TIME * 0.002, TIME * 0.001);
	float cl = smoothstep(1.0 - cloud_cover, 1.0, fbm(cp * 1.3)) * smoothstep(0.0, 0.25, d.y);
	vec3 cloudc = mix(horizon * 1.05, sun_col * 0.9, pow(sdot, 4.0) * 0.5);
	day = mix(day, cloudc, cl * 0.75);
	// night dome: murky navy overhead, orange light pollution low down, sparse stars
	float glow = pow(1.0 - up, 6.0);
	vec3 nightc = mix(vec3(0.016, 0.02, 0.04), vec3(0.11, 0.065, 0.04), glow);
	vec3 cell = floor(d * 420.0);
	float star = step(0.9975, h21(cell.xy + cell.z * 17.0)) * smoothstep(0.15, 0.5, up) * 0.6;
	nightc += vec3(star);
	nightc = mix(nightc, nightc + vec3(0.03, 0.025, 0.02), cl);
	vec3 col = mix(day * sky_energy, nightc, night_f);
	if (d.y < 0.0) col = mix(col, ground_col * mix(1.0, 0.1, night_f), smoothstep(0.0, -0.08, d.y));
	COLOR = col;
}
