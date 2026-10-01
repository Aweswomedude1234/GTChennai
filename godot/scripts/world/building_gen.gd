class_name BuildingGen
extends RefCounted
## Procedural Chennai building generator (port of src/world/gen/buildings.ts, extended).
## One quad per façade cell (bay × floor) so the façade shader knows exactly what to draw,
## plus real geometry for the cues that matter in silhouette: chajjas over every opening,
## balconies with grilles, parapets, AC units, drain pipes, roof water tanks, mumty headrooms,
## dish antennas, Mangalore-tile roofs, clothes lines, and full shop fronts.
## Runs on worker threads: touches only its own builders.

enum Cell { PLAIN, WINDOW, BALCONY, SHOP, GLASS, VENT, DOOR, STILT, TRIM }
enum GM { PAINT, TIN, TARP, TANK, TILE, CONCRETE, METAL, GLASS, EMISSIVE, CLOTH, GRANITE, SAND, WOOD, STUCCO, PAVERS, KERB, BRICK, RUBBER, RUST, SODIUM, LED }

const SIGN_COLS := 4
const SIGN_CW := 256
const SIGN_CH := 80
const SIGN_W := SIGN_COLS * SIGN_CW

class Ctx:
	var facade := MB.new(true)
	var generic := MB.new(false)
	var sign := MB.new(false)
	var signs: Array = []          # {cell, kind, seed, trade, road, upper}
	var max_signs := 96
	var shops: Array = []          # {x, z, nx, nz, w, trade, seed, sign, y}
	var lights := PackedFloat32Array()   # x, y, z, type (0 tube, 1 warm window)
	var colliders: Array = []      # {f: PackedVector2Array, h}
	var fronts: Array = []         # street-facing edges {a, b, n (Vector2 outward), kind, road, seed, h, commercial}
	var doors: Array = []          # {p: Vector2, n: Vector2}
	var street = null              # StreetDetail.Out
	var detail := true
	var trade_w: Array = []
	var style: Dictionary
	var sign_rows := 0

static func sign_uv(cell: int, rows_total: int) -> Rect2:
	var c := cell % SIGN_COLS
	var r := cell / SIGN_COLS
	var H := float(rows_total * SIGN_CH)
	var pad := 2.0
	return Rect2((c * SIGN_CW + pad) / SIGN_W, (r * SIGN_CH + pad) / H, (SIGN_CW - pad * 2) / SIGN_W, (SIGN_CH - pad * 2) / H)

static func _j(c: Color, r: Rng, amt: float) -> Color:
	var k := 1.0 + (r.next() - 0.5) * 2.0 * amt
	return Color(c.r * k, c.g * k, c.b * k)

static func gen(b: Dictionary, ctx: Ctx) -> void:
	var st := ctx.style
	var r := Rng.new(int(b.s))
	var P := CityPack.pts2(b.f)
	var n := P.size()
	if n < 3: return
	var kind: String = b.k
	var sacred := kind in ["temple", "church", "mosque", "mandapam"]
	var levels := maxi(1, int(b.l))
	var commercial := kind == "commercial"
	var gh := r.range_f(3.6, 4.2) if commercial else (3.6 if kind == "institution" else r.range_f(3.0, 3.3))
	if kind == "mandapam":
		gh = r.range_f(4.6, 5.6)
		levels = 1
	var fh := float(st.floorH) + (r.next() - 0.5) * 0.2
	var H := gh + (levels - 1) * fh
	if b.has("h") and float(b.h) > 0.0:
		H = float(b.h)
		levels = maxi(1, roundi((H - gh) / fh) + 1)
	var palette: Array = st.paint.get(kind, st.paint.residential)
	var paint := _j(Rng.hex_lin(r.pick(palette)), r, 0.08)
	var accent := Rng.hex_lin(r.pick(st.accent))
	var ws_list: Array = st.windowStyles.get(kind, st.windowStyles.default)
	var ws: int = 5 if kind == "apartment" and r.next() < 0.15 else int(r.pick(ws_list))
	var weather := r.range_f(0.2, 1.0) * (0.7 if kind == "apartment" else 1.0)
	if kind in ["oldhouse", "agraharam", "informal"]: weather = minf(1.0, weather + 0.25)
	var bseed := r.next()
	var glassy := kind == "institution" and r.next() < 0.15
	var stilt := kind == "apartment" and r.next() < 0.7
	var tile_roof := (kind == "agraharam" or kind == "oldhouse") and n == 4 and r.next() < 0.55
	var balcony_p: float = st.balconyChance.get(kind, st.balconyChance.default)
	var ac_p: float = st.acChance.get(kind, st.acChance.default)
	var ch_d := r.range_f(st.chajjaDepth[0], st.chajjaDepth[1])
	var F := ctx.facade; var G := ctx.generic
	var edges: Array = b.e
	var road_of: Array = b.get("r", [])
	var drain_col := Rng.hex_lin(r.pick(["#8e8e88", "#6b6b66", "#a8a29a", "#2c2c2c", "#3a5f8a"]))
	var trim_col := paint.lerp(Color(1, 1, 1), 0.25) if r.next() < 0.5 else accent
	var band := r.next() < float(st.get("floorBandChance", 0.5)) and not sacred
	var band_col := paint.lerp(Color(1, 1, 1), 0.3) if r.next() < 0.6 else trim_col

	var cell_quad := func(a: Vector2, bb: Vector2, y0: float, y1: float, nrm: Vector3, ck: int, flr: int, c: Color, ws2: int) -> void:
		var w := a.distance_to(bb)
		F.quad(Vector3(a.x, y0, a.y), Vector3(bb.x, y0, bb.y), Vector3(bb.x, y1, bb.y), Vector3(a.x, y1, a.y), nrm, c,
			Vector4(r.next(), ws2, ck, weather), Vector4(w, y1 - y0, flr, bseed))
	var fbox := func(c: Vector3, h: Vector3, rot: float, color: Color, ck: int) -> void:
		F.box(c, h, rot, color, Vector4(r.next(), 0, ck, weather), Vector4(h.x * 2, h.y * 2, 0, bseed))
	var gbox := func(c: Vector3, h: Vector3, rot: float, color: Color, t: int, rough := 0.8, em := 0.0) -> void:
		G.box(c, h, rot, color, Vector4(t, rough, em, r.next()))

	for i in n:
		var p0 := P[i]; var p1 := P[(i + 1) % n]
		var L := p0.distance_to(p1)
		if L < 0.3: continue
		var t := (p1 - p0) / L
		var nrm := Vector3(t.y, 0, -t.x)          # outward for CCW footprints (dz, -dx)
		var rot := atan2(nrm.x, nrm.z)            # local +z = outward
		var front: bool = i < edges.size() and int(edges[i]) > 0
		var at := func(s: float) -> Vector2: return p0 + t * s
		var road_i: int = int(road_of[i]) if i < road_of.size() else -1
		if front and L > 2.0:
			ctx.fronts.append({"a": p0, "b": p1, "n": Vector2(nrm.x, nrm.z), "kind": kind, "road": road_i, "seed": r.seed_int(), "h": H, "gh": gh, "commercial": commercial, "levels": levels})

		# ---------------- ground floor
		if commercial and front and L > 2.4:
			var ns := maxi(1, roundi(L / r.range_f(st.shopW[0], st.shopW[1])))
			var sw := L / ns
			for j in ns:
				var a: Vector2 = at.call(j * sw); var bb: Vector2 = at.call((j + 1) * sw)
				cell_quad.call(a, bb, 0.0, gh, nrm, Cell.SHOP, 0, paint, ws)
				if not ctx.detail: continue
				_shop_front(ctx, r, st, (a + bb) * 0.5, t, nrm, rot, sw, gh, paint, road_i)
		else:
			var nb := maxi(1, roundi(L / r.range_f(st.bayW[0], st.bayW[1])))
			var bw := L / nb
			var door_bay := int(r.next() * nb) if front else -1
			for j in nb:
				var a: Vector2 = at.call(j * bw); var bb: Vector2 = at.call((j + 1) * bw)
				var k := Cell.WINDOW
				if sacred: k = Cell.PLAIN
				elif stilt: k = Cell.STILT
				elif j == door_bay: k = Cell.DOOR
				elif not front and r.next() < 0.45: k = Cell.VENT if r.next() < 0.3 else Cell.PLAIN
				if glassy: k = Cell.GLASS
				cell_quad.call(a, bb, 0.0, gh, nrm, k, 0, paint, ws)
				if ctx.detail and (k == Cell.WINDOW or k == Cell.DOOR) and bw > 1.4:
					_chajja(fbox, a, bb, nrm, rot, ch_d, 2.25 if k == Cell.DOOR else 2.3, paint)
				if ctx.detail and k == Cell.DOOR:
					# entrance step, and a kolam on the doorstep of homes (drawn by morning)
					var m := (a + bb) * 0.5
					ctx.doors.append({"p": m, "n": Vector2(nrm.x, nrm.z), "kind": kind})
					gbox.call(Vector3(m.x + nrm.x * 0.35, 0.09, m.y + nrm.z * 0.35), Vector3(0.75, 0.09, 0.35), rot, Color(0.5, 0.49, 0.46), GM.CONCRETE)
		# ---------------- upper floors
		var nb2 := maxi(1, roundi(L / r.range_f(st.bayW[0], st.bayW[1])))
		var bw2 := L / nb2
		for f in range(1, levels):
			var y0 := gh + (f - 1) * fh; var y1 := y0 + fh
			for j in nb2:
				var a: Vector2 = at.call(j * bw2); var bb: Vector2 = at.call((j + 1) * bw2)
				var k := Cell.WINDOW
				if sacred: k = Cell.PLAIN
				elif glassy or ws == 5: k = Cell.GLASS
				elif front and r.next() < balcony_p and bw2 > 2.2: k = Cell.BALCONY
				elif not front and r.next() < 0.45: k = Cell.VENT if r.next() < 0.35 else Cell.PLAIN
				cell_quad.call(a, bb, y0, y1, nrm, k, f, paint, ws)
				if not ctx.detail or bw2 < 1.4: continue
				var m := (a + bb) * 0.5
				if k == Cell.WINDOW or k == Cell.BALCONY:
					_chajja(fbox, a, bb, nrm, rot, ch_d, y0 + (2.35 if k == Cell.BALCONY else 2.3), paint)
				if k == Cell.BALCONY:
					_balcony(ctx, r, fbox, gbox, m, t, nrm, rot, bw2, y0, paint, accent)
				if k == Cell.WINDOW and r.next() < ac_p:
					var side := -1.0 if r.next() < 0.5 else 1.0
					var off := minf(bw2 * 0.5 - 0.45, 0.95) * side
					var ac := Vector3(m.x + t.x * off + nrm.x * 0.16, y0 + 0.55, m.y + t.y * off + nrm.z * 0.16)
					gbox.call(ac, Vector3(0.4, 0.27, 0.14), rot, Rng.hex_lin("#e9e7e1" if r.next() < 0.8 else "#c9c6bd"), GM.METAL, 0.5)
					gbox.call(ac + Vector3(nrm.x * 0.141, 0, nrm.z * 0.141), Vector3(0.3, 0.18, 0.002), rot, Color(0.25, 0.25, 0.25), GM.METAL, 0.6)
					if r.next() < 0.6:  # copper pipe + drip hose
						G.tube(ac + Vector3(0, -0.27, 0), ac + Vector3(0, -0.6 - r.next(), 0), 0.012, 3, Color(0.1, 0.1, 0.1), Vector4(GM.RUBBER, 0.6, 0, 0))
				if k == Cell.WINDOW and wsi_has_sill(ws):
					gbox.call(Vector3(m.x + nrm.x * 0.08, y0 + 0.85, m.y + nrm.z * 0.08), Vector3(minf(0.75, bw2 * 0.3), 0.04, 0.1), rot, paint.lerp(Color(0.5, 0.5, 0.5), 0.15), GM.CONCRETE)
		# ---------------- floor bands: projecting slab edge at each floor (common on RCC frames)
		if ctx.detail and band and levels > 1 and L > 2.5:
			var mid := (p0 + p1) * 0.5
			for f in range(1, levels):
				var by := gh + (f - 1) * fh
				fbox.call(Vector3(mid.x + nrm.x * 0.05, by, mid.y + nrm.z * 0.05), Vector3(L * 0.5 + 0.05, 0.075, 0.06), rot, band_col, Cell.TRIM)
		# ---------------- parapet (flat roofs)
		if not tile_roof and not sacred:
			var ph := r.range_f(0.9, 1.1); var th := 0.14
			var ix := -nrm.x * th; var iz := -nrm.z * th
			cell_quad.call(p0, p1, H, H + ph, nrm, Cell.PLAIN, levels, paint, ws)
			F.quad(Vector3(p1.x + ix, H, p1.y + iz), Vector3(p0.x + ix, H, p0.y + iz), Vector3(p0.x + ix, H + ph, p0.y + iz), Vector3(p1.x + ix, H + ph, p1.y + iz),
				-nrm, paint.lerp(Color(0.5, 0.5, 0.5), 0.25), Vector4(r.next(), 0, Cell.PLAIN, weather), Vector4(L, ph, levels, bseed))
			F.quad(Vector3(p0.x, H + ph, p0.y), Vector3(p1.x, H + ph, p1.y), Vector3(p1.x + ix, H + ph, p1.y + iz), Vector3(p0.x + ix, H + ph, p0.y + iz),
				Vector3.UP, trim_col if r.next() < 0.5 else paint, Vector4(r.next(), 0, Cell.TRIM, weather), Vector4(L, th, levels, bseed))
			# painted band below the parapet (common on commercial blocks)
			if ctx.detail and (commercial or r.next() < 0.3) and L > 2.0:
				fbox.call(Vector3((p0.x + p1.x) * 0.5 + nrm.x * 0.04, H - 0.12, (p0.y + p1.y) * 0.5 + nrm.z * 0.04), Vector3(L * 0.5, 0.12, 0.05), rot, trim_col, Cell.TRIM)
		# ---------------- drain pipes on front faces
		if ctx.detail and front and L > 4.0 and levels > 1:
			for d in range(1 + int(r.next() * 2.0)):
				var dp: Vector2 = at.call(r.range_f(0.2, L - 0.2))
				G.tube(Vector3(dp.x + nrm.x * 0.08, 0.1, dp.y + nrm.z * 0.08), Vector3(dp.x + nrm.x * 0.08, H + 0.3, dp.y + nrm.z * 0.08), 0.055, 6, drain_col, Vector4(GM.PAINT, 0.5, 0, 0))
		# ---------------- electricity meter board + exposed wiring at the ground floor of homes
		if ctx.detail and front and not commercial and not sacred and r.next() < 0.7:
			var mp: Vector2 = at.call(r.range_f(0.4, maxf(0.5, L - 0.4)))
			gbox.call(Vector3(mp.x + nrm.x * 0.06, 1.75, mp.y + nrm.z * 0.06), Vector3(0.3, 0.25, 0.05), rot, Color(0.12, 0.12, 0.12), GM.RUBBER, 0.6)
			G.tube(Vector3(mp.x + nrm.x * 0.07, 2.0, mp.y + nrm.z * 0.07), Vector3(mp.x + nrm.x * 0.07, gh + 0.4, mp.y + nrm.z * 0.07), 0.015, 3, Color(0.05, 0.05, 0.05), Vector4(GM.RUBBER, 0.6, 0, 0))

	# ---------------- roof
	var tris := Geometry2D.triangulate_polygon(P)
	if tile_roof:
		_tile_roof(ctx, r, P, H, paint, levels, weather, bseed)
	elif not tris.is_empty():
		G.polygon(P, tris, H + 0.02, true, paint.lerp(Rng.hex_lin("#8a8478"), 0.65), Vector4(GM.CONCRETE, 0.95, 0, r.next()))
	# ---------------- roof clutter
	if ctx.detail and not tile_roof and not sacred and not tris.is_empty():
		_roof_clutter(ctx, r, P, H, levels, paint, fbox, gbox, kind)
	ctx.colliders.append({"f": P, "h": H + (1.5 if tile_roof else 1.0)})

static func wsi_has_sill(ws: int) -> bool:
	return ws != 5

static func _chajja(fbox: Callable, a: Vector2, bb: Vector2, nrm: Vector3, rot: float, d: float, y_top: float, paint: Color) -> void:
	var m := (a + bb) * 0.5
	var cw := minf(a.distance_to(bb) - 0.2, 1.9)
	fbox.call(Vector3(m.x + nrm.x * d * 0.5, y_top + 0.05, m.y + nrm.z * d * 0.5), Vector3(cw * 0.5, 0.05, d * 0.5), rot, paint.lerp(Color(0.4, 0.4, 0.4), 0.12), Cell.PLAIN)

static func _balcony(ctx: Ctx, r: Rng, fbox: Callable, gbox: Callable, m: Vector2, t: Vector2, nrm: Vector3, rot: float, bw: float, y0: float, paint: Color, accent: Color) -> void:
	var d := r.range_f(0.9, 1.2); var hw := bw * 0.5 - 0.15
	var c := Vector3(m.x + nrm.x * d * 0.5, y0 + 0.06, m.y + nrm.z * d * 0.5)
	fbox.call(c, Vector3(hw, 0.08, d * 0.5), rot, paint.lerp(Color(1, 1, 1), 0.1), Cell.PLAIN)
	var grilled := r.next() < 0.55
	var rail_col := Rng.hex_lin(r.pick(["#1c1c1c", "#2f5a44", "#2b4a7a", "#5a5a5a"])) if grilled else (accent if r.next() < 0.4 else paint)
	if grilled:
		# MS grille railing: top rail + balusters
		var top := Vector3(m.x + nrm.x * (d - 0.04), y0 + 1.0, m.y + nrm.z * (d - 0.04))
		ctx.generic.box(top, Vector3(hw, 0.025, 0.025), rot, rail_col, Vector4(GM.METAL, 0.5, 0, 0))
		ctx.generic.box(top - Vector3(0, 0.82, 0), Vector3(hw, 0.02, 0.02), rot, rail_col, Vector4(GM.METAL, 0.5, 0, 0))
		var nbal := int(hw * 2.0 / 0.12)
		for s in nbal:
			var o := -hw + (s + 0.5) * (hw * 2.0 / nbal)
			var bp := top + Vector3(t.x * o, -0.45, t.y * o)
			ctx.generic.box(bp, Vector3(0.008, 0.42, 0.008), rot, rail_col, Vector4(GM.METAL, 0.5, 0, 0))
		for sd in [-1.0, 1.0]:
			ctx.generic.box(Vector3(m.x + nrm.x * d * 0.5 + t.x * sd * hw, y0 + 0.6, m.y + nrm.z * d * 0.5 + t.y * sd * hw), Vector3(0.015, 0.42, d * 0.5), rot, rail_col, Vector4(GM.METAL, 0.5, 0, 0))
	else:
		fbox.call(Vector3(m.x + nrm.x * (d - 0.05), y0 + 0.55, m.y + nrm.z * (d - 0.05)), Vector3(hw, 0.45, 0.06), rot, rail_col, Cell.PLAIN)
		for sd in [-1.0, 1.0]:
			fbox.call(Vector3(m.x + nrm.x * d * 0.5 + t.x * sd * hw, y0 + 0.55, m.y + nrm.z * d * 0.5 + t.y * sd * hw), Vector3(0.06, 0.45, d * 0.5), rot, paint, Cell.PLAIN)
	# clothes drying on the railing (40% of balconies, STYLE_BIBLE §2)
	if r.next() < 0.4:
		var nc := 1 + int(r.next() * 3.0)
		for q in nc:
			var o := r.range_f(-hw + 0.3, hw - 0.3)
			var cc := Rng.hex_lin(r.pick(["#c62828", "#1565c0", "#f5f5f5", "#2e7d32", "#f9a825", "#6a1b9a", "#ef6c00", "#455a64", "#ad1457"]))
			var cp := Vector3(m.x + nrm.x * (d + 0.02) + t.x * o, y0 + 0.7, m.y + nrm.z * (d + 0.02) + t.y * o)
			ctx.generic.box(cp, Vector3(r.range_f(0.2, 0.45), r.range_f(0.25, 0.45), 0.01), rot, cc, Vector4(GM.CLOTH, 0.95, 0, r.next()))
	# potted plant / plastic chair
	if r.next() < 0.35:
		var o := r.range_f(-hw + 0.3, hw - 0.3)
		var pp := Vector3(m.x + nrm.x * d * 0.5 + t.x * o, y0 + 0.14, m.y + nrm.z * d * 0.5 + t.y * o)
		ctx.generic.cylinder(pp.x, pp.y, pp.z, 0.14, 0.25, 7, Rng.hex_lin("#9a4a2a"), Vector4(GM.PAINT, 0.8, 0, 0), Vector4.ZERO, false, 0.17)
		ctx.generic.cylinder(pp.x, pp.y + 0.25, pp.z, 0.2, 0.25, 6, Rng.hex_lin("#3f6b2a"), Vector4(GM.CLOTH, 0.9, 0, 0), Vector4.ZERO, true, 0.05)

static func _shop_front(ctx: Ctx, r: Rng, st: Dictionary, m: Vector2, t: Vector2, nrm: Vector3, rot: float, sw: float, gh: float, paint: Color, road_i: int) -> void:
	var G := ctx.generic
	var shop_seed := r.seed_int()
	var trade := Rng.new(shop_seed).pick_w(ctx.trade_w)
	var sign_top := gh - 0.08; var sign_bot := gh - r.range_f(0.85, 1.1)
	var cell := -1
	if ctx.signs.size() < ctx.max_signs:
		cell = ctx.signs.size()
		ctx.signs.append({"cell": cell, "kind": "flex" if r.next() < 0.6 else "paint", "seed": shop_seed, "trade": trade, "road": road_i})
		var off := 0.1; var hw := sw * 0.5 - 0.06
		# viewer's right (looking at the wall) is -t, so the sign's left edge sits at +t
		var s0 := Vector3(m.x + t.x * hw + nrm.x * off, 0, m.y + t.y * hw + nrm.z * off)
		var s1 := Vector3(m.x - t.x * hw + nrm.x * off, 0, m.y - t.y * hw + nrm.z * off)
		var cellv := Vector4(cell, 1 if r.next() < 0.35 else 0, 0, 0)  # y: backlit flex
		ctx.sign.quad(Vector3(s0.x, sign_bot, s0.z), Vector3(s1.x, sign_bot, s1.z), Vector3(s1.x, sign_top, s1.z), Vector3(s0.x, sign_top, s0.z), nrm, Color(1, 1, 1), cellv, Vector4.ZERO,
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
		G.box(Vector3(m.x + nrm.x * 0.05, (sign_top + sign_bot) * 0.5, m.y + nrm.z * 0.05), Vector3(hw + 0.03, (sign_top - sign_bot) * 0.5 + 0.03, 0.045), rot, Color(0.08, 0.08, 0.08), Vector4(GM.METAL, 0.5, 0, 0))
	ctx.shops.append({"x": m.x, "z": m.y, "nx": nrm.x, "nz": nrm.z, "tx": t.x, "tz": t.y, "w": sw, "trade": trade, "seed": shop_seed, "sign": cell, "gh": gh})
	# rolling-shutter housing
	G.box(Vector3(m.x + nrm.x * 0.12, sign_bot - 0.17, m.y + nrm.z * 0.12), Vector3(sw * 0.5 - 0.08, 0.15, 0.12), rot, Color(0.32, 0.33, 0.34), Vector4(GM.METAL, 0.6, 0, 0))
	# tube lights under the sign (1–3, STYLE_BIBLE §1)
	var ntube := 1 + int(r.next() * minf(3.0, sw / 1.4))
	for q in ntube:
		var o := (float(q) + 0.5) / ntube * sw - sw * 0.5
		var tp := Vector3(m.x + nrm.x * 0.3 + t.x * o, sign_bot - 0.36, m.y + nrm.z * 0.3 + t.y * o)
		G.box(tp, Vector3(minf(0.6, sw / ntube * 0.4), 0.022, 0.022), rot, Color(0.9, 0.95, 1.0), Vector4(GM.EMISSIVE, 0.3, 1.0, 0))
	ctx.lights.append_array([m.x + nrm.x * 0.6, sign_bot - 0.4, m.y + nrm.z * 0.6, 0.0])
	# plinth step (shops sit 0.25–0.45 m above the road)
	var ph := r.range_f(0.25, 0.45)
	G.box(Vector3(m.x + nrm.x * 0.4, ph * 0.5, m.y + nrm.z * 0.4), Vector3(sw * 0.5, ph * 0.5, 0.4), rot, Rng.hex_lin("#8f8a80").lerp(paint, 0.15), Vector4(GM.GRANITE, 0.7, 0, 0))
	# awning: sloped tin or tarpaulin
	if r.next() < float(st.awningChance):
		var ac := Rng.hex_lin(r.pick(st.awningColors))
		var depth := r.range_f(0.9, 1.6); var y0 := sign_bot - 0.05; var y1 := y0 - r.range_f(0.35, 0.6)
		var hw2 := sw * 0.5 - 0.02
		var a0 := Vector3(m.x - t.x * hw2, y0, m.y - t.y * hw2); var a1 := Vector3(m.x + t.x * hw2, y0, m.y + t.y * hw2)
		var b1 := a1 + Vector3(nrm.x * depth, y1 - y0, nrm.z * depth); var b0 := a0 + Vector3(nrm.x * depth, y1 - y0, nrm.z * depth)
		var slope_n := Vector3(nrm.x * 0.35, 0.94, nrm.z * 0.35)
		var tt := GM.TIN if r.next() < 0.5 else GM.TARP
		G.quad(a0, a1, b1, b0, slope_n, ac, Vector4(tt, 0.6, 0, r.next()), Vector4.ZERO, Vector2(0, 0), Vector2(sw, 0), Vector2(sw, depth), Vector2(0, depth))
		G.quad(a0, b0, b1, a1, -slope_n, ac * 0.7, Vector4(tt, 0.6, 0, r.next()), Vector4.ZERO, Vector2(0, 0), Vector2(sw, 0), Vector2(sw, depth), Vector2(0, depth))
		# bamboo/MS poles holding the awning edge
		for sd in [-1.0, 1.0]:
			var pb := b0 if sd < 0 else b1
			G.tube(Vector3(pb.x, 0.0, pb.z), pb, 0.025, 4, Color(0.35, 0.3, 0.22), Vector4(GM.WOOD, 0.8, 0, 0))

static func _tile_roof(ctx: Ctx, r: Rng, P: PackedVector2Array, H: float, paint: Color, levels: int, weather: float, bseed: float) -> void:
	var G := ctx.generic; var F := ctx.facade
	var e0 := P[0].distance_to(P[1]); var e1 := P[1].distance_to(P[2])
	var s := 0 if e0 >= e1 else 1
	var A := P[s]; var B := P[(s + 1) % 4]; var C := P[(s + 2) % 4]; var D := P[(s + 3) % 4]
	var pitch := 0.42
	var ridge_h := minf(e0, e1) * 0.5 * tan(pitch)
	var m1 := Vector3((A.x + D.x) * 0.5, H + ridge_h, (A.y + D.y) * 0.5); var m2 := Vector3((B.x + C.x) * 0.5, H + ridge_h, (B.y + C.y) * 0.5)
	var tile := _j(Rng.hex_lin(ctx.style.tileRoof), r, 0.12)
	var ov := 0.45
	var ext := func(p: Vector2, q: Vector3) -> Vector3:
		var vv := Vector2(p.x - q.x, p.y - q.z).normalized()
		return Vector3(p.x + vv.x * ov, H - ov * tan(pitch), p.y + vv.y * ov)
	var a: Vector3 = ext.call(A, m1); var bb: Vector3 = ext.call(B, m2); var c: Vector3 = ext.call(C, m2); var d: Vector3 = ext.call(D, m1)
	for q in [[a, bb, m2, m1], [c, d, m1, m2]]:
		var p0: Vector3 = q[0]; var p1: Vector3 = q[1]; var p2: Vector3 = q[2]; var p3: Vector3 = q[3]
		var nn := (p1 - p0).cross(p3 - p0).normalized()
		if nn.y < 0: nn = -nn
		var len := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		var sl := p0.distance_to(p3)
		G.quad(p0, p1, p2, p3, nn, tile, Vector4(GM.TILE, 0.85, 0, r.next()), Vector4.ZERO, Vector2(0, 0), Vector2(len, 0), Vector2(len, sl), Vector2(0, sl))
		G.quad(p0, p3, p2, p1, -nn, tile * 0.5, Vector4(GM.WOOD, 0.85, 0, r.next()))  # underside: wooden rafters
	# ridge capping
	G.beam(m1 + Vector3(0, 0.05, 0), m2 + Vector3(0, 0.05, 0), 0.22, 0.12, tile * 0.85, Vector4(GM.TILE, 0.85, 0, 0))
	# gable walls
	for g in [[A, D, m1], [C, B, m2]]:
		var p: Vector2 = g[0]; var q: Vector2 = g[1]; var m: Vector3 = g[2]
		var vv := (q - p)
		var l := vv.length()
		var gn := Vector3(vv.y / l, 0, -vv.x / l)
		F.tri(Vector3(p.x, H, p.y), Vector3(q.x, H, q.y), m, gn, paint, Vector4(r.next(), 0, Cell.PLAIN, weather), Vector4(l, ridge_h, levels, bseed))

static func _roof_clutter(ctx: Ctx, r: Rng, P: PackedVector2Array, H: float, levels: int, paint: Color, fbox: Callable, gbox: Callable, kind: String) -> void:
	var st := ctx.style
	var G := ctx.generic
	var n := P.size()
	var cen := Vector2.ZERO
	for p in P: cen += p
	cen /= n
	var inside := func(f: float) -> Vector2:
		var v: Vector2 = P[int(r.next() * n) % n]
		return v + (cen - v) * f
	var rot0 := atan2(P[1].x - P[0].x, P[1].y - P[0].y)
	# staircase headroom (mumty)
	if r.next() < float(st.mumtyChance) and levels >= 2:
		var mp: Vector2 = inside.call(r.range_f(0.3, 0.45))
		fbox.call(Vector3(mp.x, H + 1.25, mp.y), Vector3(1.3, 1.25, 1.15), rot0, paint, Cell.PLAIN)
		gbox.call(Vector3(mp.x, H + 2.55, mp.y), Vector3(1.45, 0.06, 1.3), rot0, paint.lerp(Color(0.3, 0.3, 0.3), 0.3), GM.CONCRETE)
		# door into the mumty
		G.box(Vector3(mp.x + sin(rot0) * 1.31, H + 1.0, mp.y + cos(rot0) * 1.31), Vector3(0.45, 1.0, 0.02), rot0, Rng.hex_lin("#2f6a5a"), Vector4(GM.WOOD, 0.8, 0, 0))
	# black plastic water tanks on stands (80% of roofs)
	if r.next() < float(st.tankChance):
		var nt := 1 + r.pick_w([55, 30, 15])
		var tp: Vector2 = inside.call(r.range_f(0.25, 0.4))
		var stand := r.range_f(0.3, 1.4)
		var tr := r.range_f(0.55, 0.75); var th := r.range_f(1.1, 1.6)
		for q in nt:
			var ox := tp.x + q * (tr * 2.0 + 0.15)
			if stand > 0.5:
				gbox.call(Vector3(ox, H + stand * 0.5, tp.y), Vector3(tr + 0.05, stand * 0.5, tr + 0.05), 0.0, paint.lerp(Color(0.4, 0.4, 0.4), 0.4), GM.CONCRETE)
			G.cylinder(ox, H + stand, tp.y, tr, th, 12, Rng.hex_lin("#1d1d1d" if r.next() < 0.85 else "#2f4f8f"), Vector4(GM.TANK, 0.55, 0, r.next()))
			# inlet/outlet pipes down to the roof
			G.tube(Vector3(ox + tr, H + stand + 0.15, tp.y), Vector3(ox + tr + 0.3, H, tp.y), 0.03, 4, Color(0.9, 0.9, 0.88), Vector4(GM.PAINT, 0.5, 0, 0))
	# dish antenna
	if r.next() < float(st.dishChance):
		var dp: Vector2 = inside.call(r.range_f(0.15, 0.3))
		gbox.call(Vector3(dp.x, H + 1.0, dp.y), Vector3(0.03, 0.45, 0.03), 0.0, Color(0.6, 0.6, 0.6), GM.METAL)
		G.cylinder(dp.x + 0.12, H + 1.2, dp.y, 0.32, 0.08, 10, Color(0.85, 0.85, 0.83), Vector4(GM.METAL, 0.4, 0, 0), Vector4.ZERO, true, 0.05)
	# clothes lines on the terrace
	if r.next() < float(st.get("clothesChance", 0.25)):
		var a: Vector2 = inside.call(0.15); var b: Vector2 = inside.call(0.15)
		if a.distance_to(b) > 2.0:
			var A3 := Vector3(a.x, H + 1.7, a.y); var B3 := Vector3(b.x, H + 1.7, b.y)
			G.tube(Vector3(a.x, H, a.y), A3, 0.02, 3, Color(0.3, 0.3, 0.3), Vector4(GM.METAL, 0.6, 0, 0))
			G.tube(Vector3(b.x, H, b.y), B3, 0.02, 3, Color(0.3, 0.3, 0.3), Vector4(GM.METAL, 0.6, 0, 0))
			G.cable(A3, B3, 0.15, 0.006, Color(0.2, 0.2, 0.2), Vector4(GM.RUBBER, 0.6, 0, 0), 4)
			var dir := (B3 - A3)
			var rr := atan2(dir.z, -dir.x) + PI * 0.5
			for q in 2 + int(r.next() * 4.0):
				var tt := r.range_f(0.15, 0.85)
				var cp := A3.lerp(B3, tt) - Vector3(0, 0.15 * 4.0 * tt * (1.0 - tt) + 0.35, 0)
				G.box(cp, Vector3(r.range_f(0.2, 0.5), r.range_f(0.25, 0.55), 0.01), rr, Rng.hex_lin(r.pick(["#c62828", "#1565c0", "#f5f5f5", "#2e7d32", "#f9a825", "#6a1b9a", "#ef6c00", "#ad1457", "#00838f"])), Vector4(GM.CLOTH, 0.95, 0, r.next()))
	# mobile tower on commercial roofs (1 in 60)
	if kind == "commercial" and r.next() < 1.0 / 60.0:
		var mp: Vector2 = inside.call(0.5)
		for q in 4:
			var ang := q * PI * 0.5 + PI * 0.25
			var base := Vector3(mp.x + cos(ang) * 1.2, H, mp.y + sin(ang) * 1.2)
			G.tube(base, Vector3(mp.x + cos(ang) * 0.3, H + 14.0, mp.y + sin(ang) * 0.3), 0.06, 4, Color(0.75, 0.75, 0.75), Vector4(GM.METAL, 0.5, 0, 0))
		for q in 3:
			var ang := q * TAU / 3.0
			G.box(Vector3(mp.x + cos(ang) * 0.5, H + 12.5, mp.y + sin(ang) * 0.5), Vector3(0.15, 0.7, 0.06), -ang + PI * 0.5, Color(0.9, 0.9, 0.9), Vector4(GM.PAINT, 0.5, 0, 0))
