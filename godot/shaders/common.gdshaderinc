// Shared helpers for GTIndian shaders. Global uniforms are declared in project.godot [shader_globals].
global uniform float night;     // 0 day … 1 night (drives street lights, shop tubes, windows)
global uniform float hour;      // game clock 0..24
global uniform float wet;       // rain wetness 0..1
global uniform float power;     // 0 during a power cut
global uniform vec3 wind;       // xz direction * strength, y = gust phase

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 hash22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float fbm2(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }

// box mask in 2D (1 inside [lo, hi])
float box2(vec2 p, vec2 lo, vec2 hi) { vec2 s = step(lo, p) * step(p, hi); return s.x * s.y; }
// anti-aliased box using derivatives (for markings / frames)
float aabox(vec2 p, vec2 lo, vec2 hi) {
	vec2 w = fwidth(p) * 0.75 + 1e-4;
	vec2 a = smoothstep(lo - w, lo + w, p) * (1.0 - smoothstep(hi - w, hi + w, p));
	return a.x * a.y;
}
vec3 srgb(vec3 c) { return pow(c, vec3(2.2)); }
// packed detail sample: rg normal, b roughness, a height
vec3 nmap(vec4 t) { return vec3(t.rg, 1.0); }
