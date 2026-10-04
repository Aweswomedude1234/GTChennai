class_name StreetDetail
extends RefCounted
## Street furniture and clutter per near chunk (STYLE_BIBLE §3–4, BRIEF §15 detail standards):
## concrete electricity poles every 30–40 m with power lines and service-drop cable tangles to the
## buildings, street lights (LED on main roads, sodium on old streets), street trees and palms,
## transformers, speed breakers, RCC drain slabs, compound walls with gates and kolams, parked
## two-wheeler rows outside shops, trade-specific shop clutter, posters and political wall writing.
## Road-level placements are precomputed once (deterministic by road id and arc length) and
## bucketed by chunk; per-chunk geometry is built on worker threads.

const GM := BuildingGen.GM
var pack: CityPack
var by_chunk := {}          # chunk key → Array of furniture items
var foot_w := {}            # road index → footpath width (0 if none)

class Out:
	var inst := {}          # mesh name → Array [Transform3D, Color]
	var lights: Array = []  # {p: Vector3, kind: "led"|"sodium"|"tube"}
	var deco := MB.new(false)     # generic-material unique geometry (cables, walls, breakers, drains)
	var posters := MB.new(false)  # poster-material quads
	var kolams := MB.new(false)   # kolam decals
	var people: Array = []        # [Vector3 p, yaw, clip, seed]: vendors, tea drinkers (registered with the crowd)

func _init(p: CityPack) -> void:
	pack = p
	_precompute()

func _key(x: float, z: float) -> String:
	var b := pack.bounds
	return "%d_%d" % [floori((x - b.position.x) / pack.chunk_size), floori((z - b.position.y) / pack.chunk_size)]

func _add(x: float, z: float, item: Dictionary) -> void:
	var k := _key(x, z)
	if not by_chunk.has(k): by_chunk[k] = []
	by_chunk[k].append(item)

## Marina: vendor carts on the dry sand by the promenade, 12 m four-head lamp posts along the
## promenade edge, and fishing boats drawn up near the waterline at the fishing hamlets
func _precompute_beach() -> void:
	if not pack.has_coast(): return
	var rnd := Rng.new(4242)
	for a in pack.region.areas:
		if a.k != "beach": continue
		var poly := CityPack.pts2(a.pts)
		if poly.size() < 3: continue
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly: bb = bb.expand(p)
		var z := bb.position.y
		while z < bb.end.y:
			# the promenade edge: westmost sand point on this z line
			# scanline: crossings of this z line with the polygon edges
			var xs: Array[float] = []
			for i in poly.size():
				var pa := poly[i]; var pb := poly[(i + 1) % poly.size()]
				if (pa.y <= z) != (pb.y <= z):
					xs.append(pa.x + (z - pa.y) / (pb.y - pa.y) * (pb.x - pa.x))
			xs.sort()
			if xs.size() >= 2 and xs[1] - xs[0] > 12.0:
				var x0: float = xs[0]
				var cx := pack.coast_x(z)
				if int(z) % 40 < 4:
					_add(x0 + 2.0, z, {"t": "mlamp", "p": Vector2(x0 + 2.0, z)})
				# vendor carts in a loose band 15–70 m from the promenade
				for k in 2:
					if rnd.next() < 0.55:
						var px := x0 + rnd.range_f(14.0, 70.0)
						if px < cx - 25.0:
							_add(px, z, {"t": "cart", "p": Vector2(px, z + rnd.range_f(-3.0, 3.0)), "yaw": rnd.range_f(-0.5, 0.5) + PI * 0.5, "seed": rnd.seed_int()})
				# boats near the waterline in the fishing hamlets
				if (z > -720.0 and z < -440.0) or (z > 560.0 and z < 1040.0):
					if rnd.next() < 0.7:
						var bx := cx - rnd.range_f(8.0, 26.0)
						_add(bx, z, {"t": "boat", "p": Vector2(bx, z + rnd.range_f(-2.0, 2.0)), "yaw": rnd.range_f(-0.25, 0.25), "seed": rnd.seed_int()})
			z += 6.0

## walk every road once: poles (+cables to the previous pole), lamps, trees, breakers, drains
func _precompute() -> void:
	_precompute_beach()
	var roads: Array = pack.region.roads
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var rank := int(r.rank)
		if rank < 1: continue
		var P: Array = r.pts
		var n := P.size() / 2
		if n < 2: continue
		var rnd := Rng.new(int(r.id) ^ 0x51ED)
		var hw := float(r.w) * 0.5
		var fw := 0.0
		if rank >= 3: fw = 2.1 if rank >= 5 else 1.5
		foot_w[ri] = fw
		var pole_side := 1.0 if rnd.next() < 0.5 else -1.0
		var pole_gap := rnd.range_f(30.0, 40.0)
		var lamp_main := rank >= 4
		var lamp_gap := rnd.range_f(26.0, 34.0)
		var next_pole := rnd.range_f(4.0, pole_gap)
		var next_lamp := rnd.range_f(4.0, lamp_gap)
		var next_tree := rnd.range_f(3.0, 18.0)
		var next_bump := rnd.range_f(40.0, 120.0)
		var acc := 0.0
		var prev_pole := Vector3.INF
		var pole_count := 0
		for i in n - 1:
			var a := Vector2(P[i * 2], P[i * 2 + 1]); var b := Vector2(P[i * 2 + 2], P[i * 2 + 3])
			var L := a.distance_to(b)
			if L < 0.5: continue
			var t := (b - a) / L
			var nn := Vector2(-t.y, t.x)
			var yaw := atan2(-t.x, -t.y)
			# drains: RCC slab strip along both edges of residential/tertiary roads
			if rank >= 2 and rank <= 3 and L > 3.0:
				for sd in [-1.0, 1.0]:
					var o: float = (hw + 0.32) * sd
					var m := a + t * L * 0.5 + nn * o
					_add(m.x, m.y, {"t": "drain", "a": a + nn * o, "b": b + nn * o, "seed": rnd.seed_int(), "j0": int(r.j[i]) >= 0, "j1": int(r.j[i + 1]) >= 0})
			var guard := 0
			while guard < 400:
				guard += 1
				var here := minf(minf(next_pole, next_lamp), minf(next_tree, next_bump))
				var s := here - acc
				if s > L: break
				var p := a + t * maxf(s, 0.0)
				if absf(here - next_pole) < 0.001:
					var off: float = (hw + fw + 0.35) * pole_side
					var pp := p + nn * off
					var lamp_on_pole := (not lamp_main) and pole_count % 2 == 0
					var trafo := rnd.next() < 0.06
					var item := {"t": "pole", "p": pp, "yaw": yaw + (PI if pole_side < 0 else 0.0), "lamp": lamp_on_pole, "trafo": trafo, "seed": rnd.seed_int(), "road": ri, "side": pole_side, "rank": rank, "dir": t}
					var top := Vector3(pp.x, 8.48, pp.y)
					if prev_pole != Vector3.INF and prev_pole.distance_to(top) < 60.0: item["prev"] = prev_pole
					prev_pole = top
					_add(pp.x, pp.y, item)
					pole_count += 1
					next_pole = here + rnd.range_f(30.0, 40.0)
				elif absf(here - next_lamp) < 0.001:
					if lamp_main:
						for sd in [-1.0, 1.0]:
							var lp: Vector2 = p + nn * (hw + fw * 0.5 + 0.2) * sd
							_add(lp.x, lp.y, {"t": "lamp", "p": lp, "yaw": yaw + (PI if sd < 0 else 0.0), "seed": rnd.seed_int()})
					next_lamp = here + rnd.range_f(26.0, 34.0) * (1.0 if lamp_main else 1.8)
				elif absf(here - next_tree) < 0.001:
					var sd := 1.0 if rnd.next() < 0.5 else -1.0
					var off: float = (hw + (fw * 0.55 if fw > 0.0 else rnd.range_f(0.9, 2.2))) * sd
					var tp := p + nn * off
					var species: String = ["tree_rain", "tree_neem", "tree_neem", "tree_gulmohar", "tree_young", "palm", "palm_short"][rnd.pick_w([22, 30, 0, 12, 14, 10, 6])]
					_add(tp.x, tp.y, {"t": "tree", "p": tp, "sp": species, "seed": rnd.seed_int()})
					var density: float = [0, 0.55, 0.75, 0.5, 0.45, 0.45, 0.4][rank]
					next_tree = here + rnd.range_f(8.0, 26.0) / float(density)
				else:
					if rank >= 1 and rank <= 3 and L > 6.0 and s > 3.0 and s < L - 3.0:
						_add(p.x, p.y, {"t": "bump", "p": p, "dir": t, "w": float(r.w), "seed": rnd.seed_int()})
					next_bump = here + rnd.range_f(80.0, 150.0) * (1.0 if rank <= 2 else 1.6)
			acc += L
			if acc > 1e7: break
		# banners strung across busy roads (political flex, festival greetings) and pennant strings
		if rank >= 3:
			var tot := 0.0
			for i in n - 1: tot += Vector2(P[i * 2 + 2] - P[i * 2], P[i * 2 + 3] - P[i * 2 + 1]).length()
			var at := rnd.range_f(30.0, 90.0)
			while at < tot - 10.0:
				var acc2 := 0.0
				for i in n - 1:
					var a := Vector2(P[i * 2], P[i * 2 + 1]); var b := Vector2(P[i * 2 + 2], P[i * 2 + 3])
					var L := a.distance_to(b)
					if acc2 + L >= at and L > 0.5:
						var t := (b - a) / L
						var pm := a + t * (at - acc2)
						_add(pm.x, pm.y, {"t": "banner" if rnd.next() < 0.6 else "pennants", "p": pm, "dir": t, "w": float(r.w) + 2.0 * fw + 0.8, "seed": rnd.seed_int()})
						break
					acc2 += L
				at += rnd.range_f(70.0, 160.0)
	# flex hoardings on junction corners of busy roads (birthday wishes, film releases, party flex)
	for ji in pack.region.junctions.size():
		var jn: Dictionary = pack.region.junctions[ji]
		var best := -1; var bw := 0.0
		for rv in jn.roads:
			var rd: Dictionary = roads[int(rv)]
			if int(rd.rank) >= 3 and float(rd.w) > bw: bw = float(rd.w); best = int(rv)
		if best < 0: continue
		var jr := Rng.new(int(jn.id) ^ 0x40A2)
		if jr.next() > 0.45: continue
		var rd: Dictionary = roads[best]
		var P: Array = rd.pts
		var jp := Vector2(jn.p[0], jn.p[1])
		var first := Vector2(P[0], P[1]).distance_to(jp) < Vector2(P[P.size() - 2], P[P.size() - 1]).distance_to(jp)
		var q := Vector2(P[2], P[3]) if first else Vector2(P[P.size() - 4], P[P.size() - 3])
		var along := (q - jp).normalized()
		var side := Vector2(-along.y, along.x) * (1.0 if jr.next() < 0.5 else -1.0)
		var hp := jp + along * (bw * 0.5 + 6.0) + side * (bw * 0.5 + float(foot_w.get(best, 0.0)) + 1.6)
		var face := -along   # faces traffic arriving at the junction
		_add(hp.x, hp.y, {"t": "hoarding", "p": hp, "yaw": atan2(face.x, face.y), "seed": jr.seed_int()})

# ---------------------------------------------------------------------------------------------
func build_chunk(key: String, _center: Vector2, ctx: BuildingGen.Ctx) -> void:
	var o := Out.new()
	var foot: Array = []   # building footprints for clearance tests
	for c in ctx.colliders: foot.append(c.f)
	var walls_drawn := {}
	var shop_pts: Array = []
	for s in ctx.shops: shop_pts.append(Vector2(s.x, s.z))
	for it in by_chunk.get(key, []):
		match it.t:
			"pole": _pole(o, it, ctx, foot)
			"lamp": _lamp(o, it)
			"tree": _tree(o, it, foot, shop_pts)
			"bump": _bump(o, it)
			"drain": _drain(o, it)
			"mlamp":
				_inst(o, "marina_lamp", _xf(it.p, 0.0, 0.0))
				o.lights.append({"p": Vector3(it.p.x, 11.6, it.p.y), "kind": "led"})
			"cart":
				var cr := Rng.new(it.seed)
				_inst(o, "cart", _xf(it.p, 0.0, it.yaw), Rng.hex_lin(cr.pick(["#1565c0", "#c62828", "#2e7d32", "#f9a825", "#6a1b9a", "#ef6c00"])))
				o.lights.append({"p": Vector3(it.p.x, 2.1, it.p.y), "kind": "tube"})
				for q in 2 + int(cr.next() * 3.0):
					var sp: Vector2 = it.p + Vector2(cr.range_f(-2.0, 2.0), cr.range_f(1.2, 2.4) * (1.0 if cr.next() < 0.5 else -1.0))
					_inst(o, "stool", _xf(sp, 0.0, cr.next() * TAU), Rng.hex_lin(cr.pick(["#c62828", "#1565c0", "#f5f5f5"])))
			"banner": _banner(o, it, false)
			"pennants": _banner(o, it, true)
			"hoarding":
				var hr := Rng.new(it.seed)
				_inst(o, "hoarding", _xf(it.p, 0.0, it.yaw))
				_poster_quad(o, Vector3(it.p.x, 4.4, it.p.y), it.yaw, 3.2, 4.2, int(hr.next() * 32.0), 0, hr.next() * 0.4, -0.085)
			"boat":
				var br := Rng.new(it.seed)
				_inst(o, "boat", _xf(it.p, -0.25, it.yaw + (PI if br.next() < 0.5 else 0.0)), Rng.hex_lin(br.pick(["#1565c0", "#2e7d32", "#c62828", "#f9a825", "#00838f", "#f5f5f5"])))
	for f in ctx.fronts:
		if f.commercial: _shop_frontage(o, f, ctx)
		else: _compound(o, f, foot)
	for s in ctx.shops: _shop_clutter(o, s)
	ctx.street = o

func _inside_any(p: Vector2, foot: Array, margin := 0.4) -> bool:
	for f in foot:
		if Geometry2D.is_point_in_polygon(p, f): return true
		if margin > 0.0:
			var pf: PackedVector2Array = f
			for i in pf.size():
				if Geometry2D.get_closest_point_to_segment(p, pf[i], pf[(i + 1) % pf.size()]).distance_to(p) < margin: return true
	return false

func _xf(p: Vector2, y: float, yaw: float, s := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))

func _inst(o: Out, mesh: String, xf: Transform3D, col := Color(1, 1, 1)) -> void:
	if not o.inst.has(mesh): o.inst[mesh] = []
	o.inst[mesh].append([xf, col])

func _pole(o: Out, it: Dictionary, ctx: BuildingGen.Ctx, foot: Array) -> void:
	var r := Rng.new(it.seed)
	var p: Vector2 = it.p
	if _inside_any(p, foot, 0.25): p += Vector2(-it.dir.y, it.dir.x) * -it.side * 0.8
	_inst(o, "pole_lamp" if it.lamp else "pole", _xf(p, 0.0, it.yaw))
	if it.lamp: o.lights.append({"p": Vector3(p.x, 7.4, p.y) + Vector3(sin(it.yaw), 0, cos(it.yaw)) * -1.5, "kind": "led" if r.next() < 0.6 else "sodium"})
	if it.trafo:
		var d: Vector2 = it.dir
		_inst(o, "transformer", _xf(p + d * 1.1, 0.0, it.yaw))
	var cable_col := Color(0.03, 0.03, 0.03)
	var cg := Vector4(GM.RUBBER, 0.6, 0, 0)
	# power lines to the previous pole (3 conductors) + 1–4 low cable-TV/fibre lines
	if it.has("prev"):
		var a: Vector3 = it.prev
		var b := Vector3(p.x, 8.48, p.y)
		var right := Vector3(-(b - a).z, 0, (b - a).x).normalized()
		for x in [-0.65, 0.0, 0.65]:
			o.deco.cable(a + right * x, b + right * x, 0.55 + r.next() * 0.3, 0.012, cable_col, cg, 6)
		for k in 1 + int(r.next() * 4.0):
			var h := 5.6 + r.next() * 1.2
			o.deco.cable(Vector3(a.x, h, a.z), Vector3(b.x, h - r.next() * 0.3, b.z), 0.8 + r.next() * 0.9, 0.009, cable_col, cg, 7)
		# coils of spare cable hanging from the pole
		if r.next() < 0.4:
			o.deco.cylinder(p.x + 0.12, 5.0, p.y, 0.22, 0.06, 8, cable_col, cg, Vector4.ZERO, false)
	# service drops: from the pole to nearby façades at first-floor height (the famous cable tangle)
	var drops := 2 + int(r.next() * 4.0)
	var made := 0
	for f in ctx.fronts:
		if made >= drops: break
		var fa: Vector2 = f.a; var fb: Vector2 = f.b
		var m := fa.lerp(fb, r.range_f(0.2, 0.8))
		var d := m.distance_to(p)
		if d < 3.0 or d > 28.0: continue
		var h: float = minf(float(f.gh) + 0.8, float(f.h) - 0.3)
		var end := Vector3(m.x, h, m.y) + Vector3(f.n.x, 0, f.n.y) * 0.05
		o.deco.cable(Vector3(p.x, 6.2 - r.next() * 1.2, p.y), end, 0.4 + d * 0.03, 0.008, cable_col, cg, 6)
		made += 1
	# posters pasted on the pole at eye height
	if r.next() < 0.45:
		_poster_quad(o, Vector3(p.x, 2.2 + r.next() * 0.5, p.y), it.yaw + PI * 0.5 * (1.0 if r.next() < 0.5 else -1.0), 0.5, 0.7, int(r.next() * 32.0), 0, r.next(), 0.12)

func _lamp(o: Out, it: Dictionary) -> void:
	_inst(o, "lamp_post", _xf(it.p, 0.0, it.yaw))
	o.lights.append({"p": Vector3(it.p.x, 8.6, it.p.y) + Vector3(sin(it.yaw), 0, cos(it.yaw)) * -2.0, "kind": "sodium" if Rng.new(it.seed).next() < 0.35 else "led"})

func _tree(o: Out, it: Dictionary, foot: Array, shops: Array) -> void:
	var p: Vector2 = it.p
	var big: bool = it.sp in ["tree_rain", "tree_gulmohar"]
	if _inside_any(p, foot, 1.2 if big else 0.6): return
	for s in shops:
		if (s as Vector2).distance_to(p) < 2.5: return   # shopkeepers keep the frontage clear
	var r := Rng.new(it.seed)
	var tint := Color(1, 1, 1) * r.range_f(0.85, 1.1)
	_inst(o, it.sp, _xf(p, 0.0, r.next() * TAU, r.range_f(0.8, 1.2)), tint)

func _bump(o: Out, it: Dictionary) -> void:
	# speed breaker: a low hump across the road; half painted black/yellow
	var r := Rng.new(it.seed)
	var d: Vector2 = it.dir
	var nn := Vector2(-d.y, d.x)
	var hw: float = it.w * 0.5
	var p: Vector2 = it.p
	var painted := r.next() < 0.5
	var prof := [[-0.9, 0.0], [-0.45, 0.07], [0.0, 0.1], [0.45, 0.07], [0.9, 0.0]]
	for k in prof.size() - 1:
		var s0: float = prof[k][0]; var h0: float = prof[k][1]; var s1: float = prof[k + 1][0]; var h1: float = prof[k + 1][1]
		var q0 := p + d * s0; var q1 := p + d * s1
		var nrm := Vector3(-d.x * (h1 - h0), absf(s1 - s0), -d.y * (h1 - h0)).normalized()
		o.deco.quad(Vector3(q0.x - nn.x * hw, 0.03 + h0, q0.y - nn.y * hw), Vector3(q0.x + nn.x * hw, 0.03 + h0, q0.y + nn.y * hw),
			Vector3(q1.x + nn.x * hw, 0.03 + h1, q1.y + nn.y * hw), Vector3(q1.x - nn.x * hw, 0.03 + h1, q1.y - nn.y * hw), nrm,
			Color(1, 1, 1) if painted else Rng.hex_lin("#4a4844"), Vector4(GM.KERB if painted else GM.CONCRETE, 0.85, 0, 0), Vector4.ZERO,
			Vector2(0, 0), Vector2(hw * 2.0, 0), Vector2(hw * 2.0, 1), Vector2(0, 1))

func _drain(o: Out, it: Dictionary) -> void:
	# RCC slab covers (0.6 × 1 m) along the road edge; ~10% broken, showing the dark drain below
	var r := Rng.new(it.seed)
	var a: Vector2 = it.a; var b: Vector2 = it.b
	var L := a.distance_to(b)
	var t := (b - a) / L
	var nn := Vector2(-t.y, t.x)
	var s := 3.0 if it.j0 else 0.5
	var e := L - (3.0 if it.j1 else 0.5)
	var col := Rng.hex_lin("#8a857a")
	while s + 1.0 <= e:
		var p0 := a + t * s; var p1 := a + t * (s + 0.97)
		if r.next() < 0.1:
			o.deco.quad(Vector3(p0.x - nn.x * 0.3, 0.0, p0.y - nn.y * 0.3), Vector3(p1.x - nn.x * 0.3, 0.0, p1.y - nn.y * 0.3), Vector3(p1.x + nn.x * 0.3, 0.0, p1.y + nn.y * 0.3), Vector3(p0.x + nn.x * 0.3, 0.0, p0.y + nn.y * 0.3), Vector3.UP, Color(0.02, 0.02, 0.015), Vector4(GM.RUBBER, 0.3, 0, 0))
		else:
			var y := 0.05 + r.next() * 0.03
			o.deco.box(Vector3((p0.x + p1.x) * 0.5, y * 0.5, (p0.y + p1.y) * 0.5), Vector3(0.3, y * 0.5, 0.485), atan2(t.x, t.y), col * r.range_f(0.85, 1.1), Vector4(GM.CONCRETE, 0.9, 0, r.next()))
		s += 1.0

## commercial frontage: parked two-wheeler rows at 60–80° along the kerb, posters on pillars
func _shop_frontage(o: Out, f: Dictionary, _ctx: BuildingGen.Ctx) -> void:
	var r := Rng.new(f.seed)
	var a: Vector2 = f.a; var b: Vector2 = f.b
	var L := a.distance_to(b)
	var t := (b - a) / L
	var nrm: Vector2 = f.n
	var road_i: int = f.road
	var dist := 3.2 + r.next() * 0.8
	if road_i >= 0:
		var rr: Dictionary = pack.region.roads[road_i]
		var mid := (a + b) * 0.5
		var near := pack.nearest_road(mid.x, mid.y, 30.0, 0)
		if not near.is_empty() and near.ri == road_i:
			dist = maxf(1.6, near.d - float(rr.w) * 0.5 + 0.9)
	var s := 0.6
	var fill := r.range_f(0.45, 0.9)
	# a footpath vendor on a third of busy frontages: fruit cart / flowers / tender coconut / tea,
	# often under a big striped umbrella, with the vendor and a customer or two
	var vend_s := -100.0
	var rank: int = int(pack.region.roads[road_i].rank) if road_i >= 0 else 0
	if rank >= 2 and L > 5.0 and r.next() < (0.45 if rank >= 3 else 0.25):
		vend_s = r.range_f(1.5, L - 1.5)
		var vp := a + t * vend_s + nrm * maxf(dist - 0.9, 1.2)
		var rot := atan2(nrm.x, nrm.y)
		var kind: String = r.pick(["fruit_cart", "fruit_cart", "flower_mat", "coconuts", "cart"])
		var cols := ["#c62828", "#1565c0", "#2e7d32", "#f9a825", "#6a1b9a", "#ef6c00", "#00838f"]
		_inst(o, kind, _xf(vp, 0.0, rot + PI * 0.5 + r.range_f(-0.15, 0.15)), Rng.hex_lin(r.pick(cols)) if kind == "cart" else Color(1, 1, 1))
		if kind != "cart" and r.next() < 0.7:
			_inst(o, "umbrella", _xf(vp + t * 0.3, 0.0, r.next() * TAU), Rng.hex_lin(r.pick(cols)))
		if kind == "cart": o.lights.append({"p": Vector3(vp.x, 2.1, vp.y), "kind": "tube"})
		var vendor_p := vp - nrm * 0.75 + t * r.range_f(-0.5, 0.5)
		o.people.append([Vector3(vendor_p.x, 0.0, vendor_p.y), atan2(-nrm.x, -nrm.y) + PI, "idle" if r.next() < 0.6 else "talk", r.seed_int()])
		for k in int(r.next() * 3.0):
			var cp := vp + nrm * r.range_f(0.9, 1.4) + t * r.range_f(-1.0, 1.0)
			o.people.append([Vector3(cp.x, 0.0, cp.y), atan2(nrm.x, nrm.y) + PI + r.range_f(-0.4, 0.4), "talk" if r.next() < 0.5 else "idle", r.seed_int()])
	while s < L - 0.5:
		if absf(s - vend_s) < 1.8:
			s += 0.8
			continue
		if r.next() < fill:
			var p := a + t * s + nrm * (dist - 0.2 + r.next() * 0.3)
			var ang := atan2(-nrm.x, -nrm.y) + r.range_f(0.35, 0.65) * (1.0 if r.next() < 0.8 else -1.0)
			var col := Rng.hex_lin(r.pick(["#151515", "#8a1010", "#1a3a8a", "#5a5a5a", "#0d0d0d", "#c7c7c7", "#e0e0e0", "#2a5a2a", "#7a1a5a"]))
			var xf := Transform3D(Basis(Vector3.UP, ang) * Basis(Vector3.BACK, 0.12), Vector3(p.x, 0.0, p.y))
			if r.next() < 0.55: _inst(o, "bike_parked", xf)
			else: _inst(o, "scooter_parked", xf, col)
		s += r.range_f(0.75, 0.95)
	# pillar/wall posters between shops
	if r.next() < 0.6:
		var p := a + t * r.range_f(0.3, maxf(0.4, L - 0.3)) + nrm * 0.03
		_poster_quad(o, Vector3(p.x, 1.4, p.y), atan2(nrm.x, nrm.y), 0.55, 0.75, int(r.next() * 32.0), 0, r.next() * 0.6)

## a banner (or a string of pennants) across the road between two bamboo poles
func _banner(o: Out, it: Dictionary, pennants: bool) -> void:
	var r := Rng.new(it.seed)
	var d: Vector2 = it.dir
	var nn := Vector2(-d.y, d.x)
	var half: float = it.w * 0.5
	var p0: Vector2 = it.p - nn * half; var p1: Vector2 = it.p + nn * half
	var bamboo := Rng.hex_lin("#a8885a")
	var h := r.range_f(5.0, 6.2)
	for pp in [p0, p1]:
		o.deco.tube(Vector3(pp.x, 0.0, pp.y), Vector3(pp.x, h + 0.4, pp.y), 0.045, 5, bamboo, Vector4(GM.WOOD, 0.9, 0, 0))
	var A := Vector3(p0.x, h, p0.y); var B := Vector3(p1.x, h, p1.y)
	o.deco.cable(A, B, 0.25 if pennants else 0.05, 0.008, Rng.hex_lin("#2a2a2a"), Vector4(GM.RUBBER, 0.8, 0, 0))
	var rot := atan2(d.x, d.y)
	if pennants:
		var cols := ["#c62828", "#f9a825", "#2e7d32", "#1565c0", "#f5f5f5", "#ef6c00", "#ad1457"]
		var n := int(it.w / 0.45)
		for k in n:
			var t0 := (k + 0.1) / n; var t1 := (k + 0.9) / n
			var a := A.lerp(B, t0) - Vector3(0, sin(t0 * PI) * 0.25, 0)
			var b := A.lerp(B, t1) - Vector3(0, sin(t1 * PI) * 0.25, 0)
			var tip := (a + b) * 0.5 - Vector3(0, 0.32, 0)
			var col := Rng.hex_lin(cols[(k + int(it.seed)) % cols.size()])
			o.deco.tri(a, b, tip, Vector3(d.x, 0, d.y), col, Vector4(GM.TARP, 0.8, 0, 0))
			o.deco.tri(b, a, tip, Vector3(-d.x, 0, -d.y), col, Vector4(GM.TARP, 0.8, 0, 0))
		return
	var bw := minf(it.w - 1.2, r.range_f(5.5, 8.0))
	var bh := bw / 4.0
	var c := Vector3(it.p.x, h - bh * 0.5 - 0.05, it.p.y)
	var cell := int(r.next() * 24.0)
	# both faces: one for each traffic direction
	_poster_quad(o, c, rot, bw, bh, cell, 1, r.next() * 0.3, 0.004)
	_poster_quad(o, c, rot + PI, bw, bh, (cell + 5) % 24, 1, r.next() * 0.3, 0.004)
	for sx in [-0.5, 0.5]:
		var e: Vector3 = Vector3(it.p.x, 0, it.p.y) + Vector3(nn.x, 0, nn.y) * bw * sx
		o.deco.cable(Vector3(e.x, h, e.z), Vector3(e.x, h - bh - 0.05, e.z), 0.0, 0.006, Rng.hex_lin("#2a2a2a"), Vector4(GM.RUBBER, 0.8, 0, 0), 1)

## residential frontage: compound wall + gate on the setback line, kolam at the gate, plants,
## political wall-writing on 15% of walls
func _compound(o: Out, f: Dictionary, foot: Array) -> void:
	var r := Rng.new(f.seed)
	var a: Vector2 = f.a; var b: Vector2 = f.b
	var L := a.distance_to(b)
	if L < 3.0: return
	var t := (b - a) / L
	var nrm: Vector2 = f.n
	var mid := (a + b) * 0.5
	var road_i: int = f.road
	if road_i < 0: return
	var rr: Dictionary = pack.region.roads[road_i]
	var near := pack.nearest_road(mid.x, mid.y, 40.0, 0)
	if near.is_empty(): return
	var gap: float = near.d - float(rr.w) * 0.5 - float(foot_w.get(road_i, 0.0)) - 0.35
	if gap < 1.1 or gap > 12.0: return
	var off := gap - 0.15
	var h := r.range_f(1.2, 1.8)
	var paint := Rng.hex_lin(r.pick(pack.style.paint.residential))
	var wa := a + nrm * off - t * 0.3
	var wb := b + nrm * off + t * 0.3
	var WL := wa.distance_to(wb)
	var gate_w := r.range_f(2.6, 3.4) if WL > 6.0 else 1.1
	var gate_s := r.range_f(0.5, maxf(0.6, WL - gate_w - 0.5))
	var rot := atan2(nrm.x, nrm.y)
	var g := Vector4(GM.STUCCO, 0.9, 0, r.next())
	# two wall runs either side of the gate
	for run in [[0.0, gate_s], [gate_s + gate_w, WL]]:
		var s0: float = run[0]; var s1: float = run[1]
		if s1 - s0 < 0.2: continue
		var c := wa + t * ((s0 + s1) * 0.5)
		o.deco.box(Vector3(c.x, h * 0.5, c.y), Vector3((s1 - s0) * 0.5, h * 0.5, 0.11), rot, paint, g)
		o.deco.box(Vector3(c.x, h + 0.04, c.y), Vector3((s1 - s0) * 0.5 + 0.02, 0.04, 0.14), rot, paint * 0.85, Vector4(GM.CONCRETE, 0.9, 0, 0))  # coping
		# political wall-writing / posters on the street face
		if s1 - s0 > 4.5 and r.next() < 0.18:
			var wc := wa + t * ((s0 + s1) * 0.5) + nrm * 0.115
			_poster_quad(o, Vector3(wc.x, h * 0.5, wc.y), rot, minf(4.2, s1 - s0 - 0.4), h * 0.8, int(r.next() * 24.0), 1, 0.3)
		elif s1 - s0 > 2.0 and r.next() < 0.3:
			var wc := wa + t * r.range_f(s0 + 0.4, s1 - 0.4) + nrm * 0.115
			_poster_quad(o, Vector3(wc.x, h * 0.55, wc.y), rot, 0.5, 0.68, int(r.next() * 32.0), 0, r.next())
	# gate pillars + MS gate (painted green / black / grey)
	var gcol := Rng.hex_lin(r.pick(["#1f4a3a", "#1a1a1a", "#3a3a3a", "#2b4a7a", "#5a1a1a"]))
	for s in [gate_s, gate_s + gate_w]:
		var c: Vector2 = wa + t * s
		o.deco.box(Vector3(c.x, (h + 0.3) * 0.5, c.y), Vector3(0.18, (h + 0.3) * 0.5, 0.18), rot, paint * 0.95, g)
	var gc := wa + t * (gate_s + gate_w * 0.5)
	var open := r.next() < 0.35
	if not open:
		o.deco.box(Vector3(gc.x, h * 0.5 + 0.05, gc.y), Vector3(gate_w * 0.5 - 0.2, h * 0.45, 0.02), rot, gcol, Vector4(GM.METAL, 0.5, 0, 0))
	# kolam on the swept ground just outside the gate (mornings; fades through the day)
	var kp := gc + nrm * 0.9
	var ks := r.range_f(0.6, 1.4)
	_kolam(o, kp, ks, int(r.next() * 16.0), r.next() < 0.2)
	# a potted plant or two on the wall, a tulsi madam inside
	if r.next() < 0.4:
		var pp := wa + t * r.range_f(0.3, maxf(0.35, gate_s - 0.3))
		_inst(o, "shrub", _xf(pp + nrm * -0.6, 0.0, r.next() * TAU, 0.8))
	if r.next() < 0.25:
		_inst(o, "palm_short", _xf(wa + t * r.range_f(0.5, maxf(0.6, WL - 0.5)) - nrm * 1.0, 0.0, r.next() * TAU))
	if r.next() < 0.3:
		_inst(o, "scooter_parked", Transform3D(Basis(Vector3.UP, rot + PI * 0.5), Vector3(gc.x - nrm.x * 1.2, 0.0, gc.y - nrm.y * 1.2)), Rng.hex_lin(r.pick(["#151515", "#e0e0e0", "#8a1010", "#1a3a8a"])))

func _kolam(o: Out, p: Vector2, s: float, cell: int, border: bool) -> void:
	var y := 0.025
	var h := s * 0.5
	o.kolams.quad(Vector3(p.x - h, y, p.y - h), Vector3(p.x + h, y, p.y - h), Vector3(p.x + h, y, p.y + h), Vector3(p.x - h, y, p.y + h), Vector3.UP,
		Color(1, 1, 1) if not border else Color(1.0, 0.85, 0.85), Vector4(cell, 1.0 if border else 0.0, 0, 0))

func _poster_quad(o: Out, c: Vector3, rot: float, w: float, h: float, cell: int, kind: int, wear: float, off := 0.0) -> void:
	var n := Vector3(sin(rot), 0, cos(rot))
	var t := Vector3(cos(rot), 0, -sin(rot))
	var cc := c + n * (off + 0.006)
	o.posters.quad(cc - t * w * 0.5 - Vector3(0, h * 0.5, 0), cc + t * w * 0.5 - Vector3(0, h * 0.5, 0), cc + t * w * 0.5 + Vector3(0, h * 0.5, 0), cc - t * w * 0.5 + Vector3(0, h * 0.5, 0),
		n, Color(1, 1, 1), Vector4(cell, kind, wear, 0), Vector4.ZERO, Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))

## trade-specific clutter in front of each shop (≥5 props per shop, BRIEF §15)
func _shop_clutter(o: Out, s: Dictionary) -> void:
	var r := Rng.new(int(s.seed) ^ 0x77)
	var trade: String = pack.names.trades[int(s.trade)].id
	var p0 := Vector2(s.x, s.z)
	var nrm := Vector2(s.nx, s.nz)
	var t := Vector2(s.tx, s.tz)
	var w: float = s.w
	var rot := atan2(nrm.x, nrm.y)
	var spot := func(depth: float) -> Vector2: return p0 + nrm * depth + t * r.range_f(-w * 0.42, w * 0.42)
	var items: Array = []
	match trade:
		"fruit", "veg":
			for k in 4 + int(r.next() * 4): items.append(["crate", r.range_f(0.6, 1.2), Rng.hex_lin("#c62828" if r.next() < 0.6 else "#1565c0")])
			items.append(["stand", 0.7, Rng.hex_lin(r.pick(["#e0b030", "#7cb342", "#ef6c00"]))])
		"provision", "pooja", "stationery":
			for k in 2 + int(r.next() * 3): items.append(["sack", r.range_f(0.5, 1.0), Color(1, 1, 1)])
			items.append(["stand", 0.6, Rng.hex_lin(r.pick(["#f5f5f5", "#ffd54f", "#4fc3f7", "#e57373"]))])
			items.append(["crate", 0.9, Rng.hex_lin("#1565c0")])
		"tea", "mess", "biryani", "juice", "sweets":
			for k in 3 + int(r.next() * 4): items.append(["stool", r.range_f(0.8, 2.0), Rng.hex_lin(r.pick(["#c62828", "#1565c0", "#f5f5f5", "#2e7d32"]))])
			items.append(["cylinder", 0.5, Color(1, 1, 1)])
			items.append(["drum", 0.5, Rng.hex_lin("#1565c0")])
		"textile", "tailor", "fancy":
			for k in 2 + int(r.next() * 2): items.append(["stand", r.range_f(0.6, 1.0), Rng.hex_lin(r.pick(["#c2185b", "#7b1fa2", "#ff8f00", "#00838f", "#f9a825"]))])
		"hardware", "electric", "cycle", "service", "vessels":
			for k in 2 + int(r.next() * 3): items.append(["drum" if r.next() < 0.4 else "crate", r.range_f(0.5, 1.4), Rng.hex_lin(r.pick(["#1565c0", "#5a5a5a", "#c62828"]))])
			items.append(["sack", 0.6, Color(1, 1, 1)])
		_:
			items.append(["stand", 0.6, Rng.hex_lin(r.pick(["#f5f5f5", "#ffd54f", "#4fc3f7"]))])
			items.append(["stool", 1.2, Rng.hex_lin(r.pick(["#c62828", "#1565c0", "#f5f5f5"]))])
	if r.next() < 0.3: items.append(["bin", 2.2, Color(1, 1, 1)])
	if r.next() < 0.5: items.append(["crate", 1.0, Rng.hex_lin("#c62828")])
	for it in items:
		var p: Vector2 = spot.call(float(it[1]))
		_inst(o, it[0], _xf(p, 0.0 if it[0] != "crate" or r.next() < 0.6 else 0.3, rot + r.range_f(-0.4, 0.4)), it[2])

# ---------------------------------------------------------------------------------------------
static var _poster_mat: ShaderMaterial
static var _kolam_mat: ShaderMaterial
static var poster_atlas: Texture2D

static func poster_mat() -> ShaderMaterial:
	if _poster_mat == null:
		_poster_mat = ShaderMaterial.new()
		_poster_mat.shader = load("res://shaders/poster.gdshader")
	if poster_atlas: _poster_mat.set_shader_parameter("atlas", poster_atlas)
	return _poster_mat

static func kolam_mat() -> ShaderMaterial:
	if _kolam_mat == null:
		_kolam_mat = ShaderMaterial.new()
		_kolam_mat.shader = load("res://shaders/kolam.gdshader")
		_kolam_mat.set_shader_parameter("atlas", load("res://textures/kolam.png"))
	return _kolam_mat

func attach_chunk(node: Node3D, ctx: BuildingGen.Ctx) -> void:
	var o: Out = ctx.street
	if o == null: return
	var shadows: bool = Settings.q("shadows")
	for mesh_name in o.inst:
		var arr: Array = o.inst[mesh_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Props.get_mesh(mesh_name)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i][0])
			mm.set_instance_color(i, arr[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "mm_" + mesh_name
		mmi.multimesh = mm
		var big: bool = mesh_name.begins_with("tree") or mesh_name.begins_with("palm") or mesh_name.begins_with("pole") or mesh_name == "lamp_post"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	for pair in [[o.deco, Mats.generic(), true], [o.posters, poster_mat(), false], [o.kolams, kolam_mat(), false]]:
		var mb: MB = pair[0]
		if mb.count() == 0: continue
		var mi := MeshInstance3D.new()
		mi.mesh = mb.to_mesh(pair[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pair[2] and shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	# street lights: real lights at night (clustered Forward+), energy driven by the clock
	var lights := Node3D.new()
	lights.name = "StreetLights"
	lights.add_to_group("street_lights")
	for l in o.lights:
		var ol := OmniLight3D.new()
		ol.position = l.p
		ol.omni_range = 22.0
		ol.omni_attenuation = 1.1
		ol.light_energy = 6.0
		ol.light_color = Color(1.0, 0.68, 0.32) if l.kind == "sodium" else Color(0.86, 0.92, 1.0)
		if l.kind == "tube": ol.omni_range = 7.0; ol.light_energy = 1.4; ol.light_color = Color(0.92, 0.97, 1.0)
		ol.shadow_enabled = false
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 140.0
		ol.distance_fade_length = 40.0
		lights.add_child(ol)
	node.add_child(lights)
