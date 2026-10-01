shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// Chennai façade cells (STYLE_BIBLE §2–3). One quad per bay × floor.
// COLOR = paint (linear). UV = 0..1 across the cell. CUSTOM0 = (cell seed, window style, cell kind, weathering),
// CUSTOM1 = (cell width m, cell height m, floor, building seed).
// Cell kinds: 0 plain, 1 window, 2 balcony door, 3 shop, 4 glass curtain wall, 5 vent, 6 door, 7 stilt parking, 8 trim.
// Window styles: 1 square MS grille, 2 diamond grille, 3 wooden shutters (old houses), 4 aluminium sliders, 5 glazing.
// Windows and shops use interior mapping (a parallax room behind the glass), so they have real depth.
uniform sampler2D plaster_n : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying vec3 wn;
varying vec3 wt;
varying flat vec4 fa;
varying flat vec4 fb;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	fa = CUSTOM0; fb = CUSTOM1;
	if (abs(NORMAL.y) > 0.7) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
	else { TANGENT = normalize(cross(NORMAL, vec3(0.0, 1.0, 0.0))); BINORMAL = vec3(0.0, 1.0, 0.0); }
	wt = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

// parallax room: returns colour of the interior seen through an opening at (lx, ly) of a cell
// `room` = (width, height, depth); `lit` 0..1; kind 1 = home, 3 = shop
vec3 interior(vec3 o, vec3 d, vec3 room, float seed, float lit, int ikind, out float depth) {
	vec3 inv = 1.0 / max(abs(d), vec3(1e-4)) * sign(d + 1e-6);
	float tx = ((d.x > 0.0 ? room.x : 0.0) - o.x) * inv.x;
	float ty = ((d.y > 0.0 ? room.y : 0.0) - o.y) * inv.y;
	float tz = (room.z - o.z) * inv.z;
	float t = min(min(tx, ty), tz);
	vec3 h = o + d * t;
	depth = t;
	float h1 = hash11(seed * 13.7), h2 = hash11(seed * 7.3), h3 = hash11(seed * 3.1);
	vec3 wallc = mix(vec3(0.75, 0.72, 0.62), mix(vec3(0.55, 0.7, 0.75), vec3(0.8, 0.6, 0.55), h2), step(0.5, h1));
	vec3 c;
	if (t == tz) {
		// back wall: cupboard / calendar / shelves (shop: stocked racks)
		c = wallc;
		if (ikind == 3) {
			float shelf = step(0.82, fract(h.y * 2.4));
			vec2 cell = floor(vec2(h.x * 3.0, h.y * 2.4));
			vec3 stock = vec3(hash21(cell + seed), hash21(cell + seed * 2.0), hash21(cell + seed * 3.0));
			stock = mix(stock, vec3(0.9, 0.85, 0.7), 0.25) * (0.6 + 0.4 * step(0.3, fract(h.x * 9.0 + hash21(cell))));
			c = mix(stock, vec3(0.25, 0.2, 0.16), shelf);
			c = mix(c, wallc, step(room.y - 0.6, h.y));
		} else {
			float cup = box2(h.xy, vec2(room.x * (0.15 + h2 * 0.3), 0.0), vec2(room.x * (0.15 + h2 * 0.3) + 1.0, 2.0));
			c = mix(c, mix(vec3(0.35, 0.22, 0.14), vec3(0.6, 0.6, 0.62), step(0.6, h3)), cup);
			float cal = box2(h.xy, vec2(room.x * 0.7, 1.4), vec2(room.x * 0.7 + 0.35, 1.9)) * step(0.4, h2);
			c = mix(c, vec3(0.9, 0.85, 0.75), cal);
		}
	} else if (t == ty) {
		if (d.y < 0.0) {
			// floor: red oxide, mosaic or vitrified tile
			vec2 tl = floor(h.xz * 2.0);
			float chk = mod(tl.x + tl.y, 2.0);
			c = mix(vec3(0.45, 0.14, 0.09), mix(vec3(0.7, 0.68, 0.62), vec3(0.6, 0.58, 0.55), chk), step(0.45, h3));
		} else {
			c = vec3(0.8, 0.79, 0.75);
			// tube light on the ceiling
			c += vec3(2.0, 2.1, 2.2) * lit * box2(h.xz, vec2(room.x * 0.3, room.z * 0.5), vec2(room.x * 0.7, room.z * 0.5 + 0.05));
		}
	} else {
		c = wallc * 0.9;
	}
	float shade = mix(0.18, 0.45, h1) * (1.0 - clamp(t * 0.12, 0.0, 0.5));
	vec3 lightc = mix(vec3(1.0, 0.75, 0.45), vec3(0.85, 0.92, 1.0), step(0.55, h2));
	return c * (shade + lit * lightc * 0.9);
}

void fragment() {
	float cseed = fa.x, ws = fa.y, kind = fa.z, weather = fa.w;
	float cw = fb.x, chh = fb.y, flr = fb.z, bseed = fb.w;
	vec3 paint = COLOR.rgb;
	float lx = UV.x * cw, ly = UV.y * chh;
	int k = int(kind + 0.5);
	int wsi = int(ws + 0.5);
	float along = dot(wp.xz, wt.xz);
	vec4 nz = texture(noise, vec2(along, wp.y) / 11.0 + bseed * 7.0);
	vec4 nz2 = texture(noise, vec2(along, wp.y) / 3.1 + bseed * 3.0);
	vec4 pn = texture(plaster_n, vec2(along, wp.y) / 2.0);
	float h1 = hash11(cseed * 9137.1), h2 = hash11(cseed * 5113.7), h3 = hash11(cseed * 771.3);

	// ---------------- openings (metres in cell space)
	float ww = min(1.3, cw * 0.55); float wx0 = (cw - ww) * 0.5, wx1 = wx0 + ww;
	float win = (k == 1) ? box2(vec2(lx, ly), vec2(wx0, 0.9), vec2(wx1, 2.25)) : 0.0;
	float bal = (k == 2) ? box2(vec2(lx, ly), vec2(cw * 0.5 - 0.55, 0.06), vec2(cw * 0.5 + 0.55, 2.25)) : 0.0;
	float shop = (k == 3) ? box2(vec2(lx, ly), vec2(0.1, 0.38), vec2(cw - 0.1, chh - 1.05)) : 0.0;
	float vent = (k == 5) ? box2(vec2(lx, ly), vec2(cw * 0.5 - 0.3, 1.65), vec2(cw * 0.5 + 0.3, 2.1)) : 0.0;
	float door = (k == 6) ? box2(vec2(lx, ly), vec2(cw * 0.5 - 0.55, 0.12), vec2(cw * 0.5 + 0.55, 2.2)) : 0.0;
	float stilt = (k == 7) ? box2(vec2(lx, ly), vec2(0.0), vec2(cw, chh - 0.45)) * (1.0 - box2(vec2(lx, ly), vec2(cw * 0.5 - 0.18, 0.0), vec2(cw * 0.5 + 0.18, 10.0))) : 0.0;
	float glass = (k == 4) ? 1.0 : 0.0;
	float opening = max(max(win, bal), max(vent, glass));

	// ---------------- wall with weathering
	float grime = nz.r;
	float streak_n = texture(noise, vec2(along * 0.7, wp.y * 0.05) + bseed).g;
	// rain streaks hang from each floor slab / chajja line and fade downward
	float from_top = clamp((chh - ly) / max(chh, 0.1), 0.0, 1.0);
	float streak = smoothstep(0.66, 0.86, streak_n) * weather * 0.35 * (1.0 - smoothstep(0.0, 0.85, from_top));
	// black rain streaks from both ends of each chajja/window head (STYLE_BIBLE §2)
	float under = 0.0;
	if (k == 1 || k == 2) {
		float sy = (k == 1) ? 2.35 : 2.4;
		float dropl = 0.3 + h3 * 0.9;
		float band_ = smoothstep(sy, sy - dropl, ly) * step(ly, sy);
		float ends = max(1.0 - smoothstep(0.0, 0.18, abs(lx - (wx0 - 0.15))), 1.0 - smoothstep(0.0, 0.18, abs(lx - (wx1 + 0.15))));
		under = band_ * ends * weather * (0.6 + nz2.b * 0.5);
	}
	float damp = (1.0 - smoothstep(0.0, 0.9 + nz.g * 0.4, wp.y)) * (0.3 + weather * 0.5);
	float repaint = step(0.8, hash21(floor(vec2(along * 0.22, wp.y * 0.28)) + bseed * 1000.0)) * 0.08;
	vec3 wall = paint * (0.86 + grime * 0.2) * (0.9 + pn.a * 0.16) * (1.0 + repaint);
	wall *= 1.0 - streak - under * 0.55;
	wall = mix(wall, wall * vec3(0.58, 0.64, 0.56), damp);
	// peeling paint revealing grey plaster or brick on weathered/old buildings
	float peel = smoothstep(0.86, 0.9, nz2.r * 0.7 + nz.b * 0.3 + weather * 0.08) * step(0.75, weather) * (1.0 - opening);
	wall = mix(wall, mix(vec3(0.45, 0.44, 0.41), texture(brick_c, vec2(along, wp.y) / 1.2).rgb, step(0.95, nz2.r)), peel);
	if (k == 8) wall = paint * (0.9 + grime * 0.12);

	// ---------------- window frames, grilles, shutters
	float fx = min(lx - wx0, wx1 - lx), fy = min(ly - 0.9, 2.25 - ly);
	float frame = win * step(min(fx, fy), 0.06);
	float gs = 0.13;
	float sq = max(step(fract(lx / gs), 0.12), step(fract(ly / gs), 0.12));
	float dia = max(step(fract((lx + ly) / 0.18), 0.1), step(fract((lx - ly) / 0.18), 0.1));
	float grille = ((wsi == 1) ? sq : (wsi == 2) ? dia : 0.0) * max(win, vent);
	grille = max(grille, step(fract(lx / 0.11), 0.1) * bal * step(ly, 1.0) * float(wsi != 5)); // balcony door grille half
	float slider = float(wsi == 4) * win * step(abs(lx - cw * 0.5), 0.025);
	vec3 frame_col = mix(vec3(0.85, 0.83, 0.78), paint * 0.7, step(0.5, hash11(bseed * 31.7)));
	frame_col = mix(frame_col, vec3(0.16, 0.36, 0.3), float(wsi == 3));
	vec3 grille_col = mix(vec3(0.07), vec3(0.12, 0.26, 0.19), step(0.6, hash11(bseed * 77.1)));
	grille_col = mix(grille_col, vec3(0.5, 0.5, 0.52), step(0.85, hash11(bseed * 17.3)));

	// ---------------- interior / glass through openings (parallax rooms)
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz); // fragment → camera, world
	vec3 dl = vec3(dot(-V, wt), -V.y, dot(-V, -wn));
	dl.z = max(dl.z, 0.05);
	float litfrac = mix(0.12, 0.6, night) * ((hour > 23.5 || hour < 5.0) ? 0.25 : 1.0);
	float lit = step(hash11(cseed * 3331.7), litfrac) * power * night;
	float curtain = step(0.45, h1);
	float cpos = lx - wx0;
	float cmask = curtain * step(cpos / ww, h2 * 0.75 + 0.15);
	vec3 curtain_col = mix(vec3(0.85, 0.78, 0.62), mix(vec3(0.7, 0.24, 0.38), vec3(0.24, 0.42, 0.66), h3), step(0.5, h2));
	float idepth;
	vec3 room = vec3(0.0);
	if (k == 1 || k == 2 || k == 5) room = interior(vec3(lx, ly, 0.0), dl, vec3(cw, chh, 3.5), cseed, lit, 1, idepth);
	float fres = pow(1.0 - clamp(dot(wn, V), 0.0, 1.0), 4.0);
	vec3 skyc = mix(vec3(0.45, 0.52, 0.6), vec3(0.75, 0.8, 0.85), clamp(V.y * 0.5 + 0.5, 0.0, 1.0)) * mix(1.0, 0.06, night);
	vec3 winc = mix(room, curtain_col * mix(0.35, 1.2, lit), cmask * 0.9);
	winc = mix(winc, skyc, 0.15 + fres * 0.6);
	// old-house wooden shutters, half the time closed
	if (wsi == 3) {
		float closed = step(0.4, h1);
		float louv = step(0.55, fract(ly * 11.0));
		vec3 wood = mix(vec3(0.16, 0.34, 0.28), vec3(0.32, 0.2, 0.12), step(0.5, h3)) * (0.75 + 0.25 * louv);
		winc = mix(winc, wood, closed * win);
	}
	// glass curtain wall: bands of glazing with spandrels
	vec3 glassc = mix(vec3(0.08, 0.12, 0.14), skyc, 0.35 + fres * 0.5);
	float spandrel = glass * step(ly, 0.95);
	float mull = glass * max(step(fract(lx / 1.5), 0.03), step(abs(ly - 0.95), 0.04));

	// ---------------- shops: open interior (scheduled) or rolled-down shutter
	float open_h = 6.5 + h2 * 4.0, close_h = 20.5 + h3 * 3.0;
	float is_open = step(open_h, hour) * step(hour, close_h);
	float sdepth;
	vec3 shop_in = vec3(0.0);
	if (k == 3) shop_in = interior(vec3(lx, ly, 0.0), dl, vec3(cw, chh, 5.0), cseed, mix(0.35, 1.0, night) * power, 3, sdepth);
	float shutter_rib = step(0.3, fract(ly * 14.0));
	vec3 shutter = mix(vec3(0.42, 0.44, 0.45), vec3(0.45, 0.3, 0.2), smoothstep(0.4, 0.8, nz2.g)) * (0.75 + 0.25 * shutter_rib);
	shutter = mix(shutter, paint * 0.8, step(0.75, h1)); // painted shutters
	vec3 shopc = mix(shutter, shop_in, is_open);

	// ---------------- compose
	vec3 col = wall;
	col = mix(col, winc, max(win, bal));
	col = mix(col, room * 0.7, vent);
	col = mix(col, glassc, glass);
	col = mix(col, paint * 0.8, spandrel);
	col = mix(col, frame_col, frame);
	col = mix(col, grille_col, grille);
	col = mix(col, vec3(0.7, 0.71, 0.72), slider);
	col = mix(col, vec3(0.16, 0.18, 0.2), mull);
	col = mix(col, shopc, shop);
	vec3 door_col = mix(vec3(0.16, 0.34, 0.28), mix(vec3(0.3, 0.18, 0.1), vec3(0.12), step(0.7, h1)), step(0.4, h3));
	col = mix(col, door_col * (0.85 + 0.15 * step(0.04, fract(lx * 2.0))), door);
	col = mix(col, vec3(0.05, 0.05, 0.05), stilt);

	float glazing = max(max(win, bal), max(vent, glass)) * (1.0 - grille) * (1.0 - frame) * (1.0 - cmask * 0.8) * (1.0 - spandrel);
	if (wsi == 3) glazing *= 1.0 - step(0.4, h1);
	col *= mix(1.0, 0.8, wet);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.9, 0.08, glazing), 0.45, wet * 0.4 * (1.0 - glazing));
	SPECULAR = mix(0.5, 0.9, glazing);
	NORMAL_MAP = mix(nmap(pn), vec3(0.5, 0.5, 1.0), max(opening, max(shop, door)));
	NORMAL_MAP_DEPTH = 0.8;
	// night: lit windows show their room; open shops glow
	vec3 emis = winc * max(win, bal) * lit * 1.6 * (1.0 - grille * 0.8);
	emis += shop_in * shop * is_open * mix(0.25, 1.3, night) * power;
	EMISSION = emis;
}
